--[[ Signal controller for stations - making station signals easier
     Created for the Youtube channel https://youtube.com/user/nzHook 2022
     myRail Episode Showing Usage: https://youtu.be/SJz_lrf4hQo
     NOTE: Requires:
       - Computronics, one signal controller and one signal receiver
       - Normal signals setup, named and linked to those controllers
     To use:
       - Place a signal controller and/or make a signal block
       - Place receivers, Distant signals or Switch acuator motors and link them to
           the digital controller / receiver (do not link them to each other)
       - Use a signal label to match the controllers to the receivers
          eg. label the controller and receivers for the first platform 'Platform 1'
              label the controller and receivers for the second platform 'Platform 2'
       - Run this code, when the aspect of the controller changes ALL the receivers will too
       
       - Also available
          - Name a receiever / controller as Entrace and it will be block entry if a platform
             is not available (or the controller is red)
     
    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.
    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.
    You should have received a copy of the GNU General Public License
    along with this program.  If not, see <http://www.gnu.org/licenses/>.
]]--

local event = require("event")
local term = require("term")
local os = require("os")
local component = require("component")
local computer = require("computer")
local fs = require("filesystem")

if(not fs.exists("/lib/guielements.lua")) then
   print("/lib/guielements.lua library is not installed, download it from https://raw.githubusercontent.com/nzhook/myrail/master/opencomputers/lib/guielements.lua")
   os.exit()
end
local gui = require("guielements")
local serialization = require("serialization")

local running = true          -- gets set to false to quit
local seenfilters = {}        -- the various cart setups that has been seen at some stage (what can be filtered on)
local currentsetup = nil      -- the setup of train waiting
local platformConditions = {} -- the conditions for entry into a platform
local platformDetail = {}     -- what is shown on screen about the platform
local transposerSides = {}    -- cache of the sides of the transposers that have inventory
local currentAspects = {}     -- the aspects that have been set
local lockedAspects = nil     -- the aspects as they were when a train started entering (the aspects will only go more restrictive)
local touchpos = {}           -- what the on-screen positions are (to identify what was clicked on)
local lock_logs = false       -- disable logs showing in the gui (because a dialog is open)
local platformConfigFiles = "/.platforms"     -- directory platform configs will be stored in

-- These aspects are kept the same for platforms, anything excluded may be adjusted (eg. yellow could be set to flash yellow or red)
local keepAspects = component.digital_controller_box.aspects
keepAspects[component.digital_controller_box.aspects.green] = nil
keepAspects[component.digital_controller_box.aspects.yellow] = nil
  

local gpu = component.gpu


-- This is the map of the dye colours (computronics), Opencomputers uses wool colours
local engineColors = {
    [0] = "black",
    [1] = "red",
    [2] = "green",
    [3] = "brown",    
    [4] = "blue",
    [5] = "purple",
    [6] = "cyan",
    [7] = "silver",
    [8] = "gray",
    [9] = "pink",
    [10] = "lime",
    [11] = "yellow",
    [12] = "lightblue",
    [13] = "magenta",
    [14] = "orange",
    [15] = "white"
  }

-- These are the GPU colours to use
local aspectColors = {
    [1] = 0x00ff00,      -- green
    [2] = 0xffff00,      -- blink_yellow
    [3] = 0xffff00,      -- yellow
    [4] = 0xff0000,      -- blink_red
    [5] = 0xff0000,      -- red
    [6] = 0x000000       -- off
}

-- Lock any changes being made to the setup
local lockSetup = false
function aquireSetupLock() 
  if lockSetup then
    while lockSetup do os.sleep(0.1) end
  end
  lockSetup = true
end
function releaseSetupLock()
  lockSetup = false
end

local oldprint = print
local log = {}
local function print(...)
    -- We track previous messages to show in the GUI
    for x = 1, 20 do
        log[x] = log[x + 1]
    end
    
    log[20] = ""
    local args = table.pack(...)
    for i = 1, args.n do
      log[20] = log[20] .. " " .. tostring(args[i])
    end
--    oldprint(...)
  draw_gui()

end

-- Is the name of the signal a platform?
local function isPlatform(platformName)
    if platformName ~= "Entrance" and string.sub(platformName, -4) ~= "Exit" then
      return true
    end
    
    return false
end

-- Return an table of the platforms
local function getPlatforms() 
  local allPlatforms = component.digital_receiver_box.getSignalNames()
  local platforms = {}
  for k, platformName in pairs(allPlatforms) do
    if isPlatform(platformName) then
      table.insert(platforms, platformName)
    end
  end
  
  return platforms
end

local function getTrainDetail(train)
  if not train then
    return "No train detail?"
  end
  
  debugdetail = ""
  if train.tags then
    local debugtags = ""
    for k, i in pairs(train.tags) do
      debugdetail = debugdetail .. "," .. k
    end
  end

  return debugdetail
end

local function save_platform(platformName) 
    -- TOOD save the platform config back disk
    --   (and load it as well)
    local tmpf = io.open(platformConfigFiles .. "/" .. platformName, "w")
    tmpf:write(serialization.serialize(platformConditions[platformName]))
    tmpf:close()
end

local function adjust_all_platforms(key, newvalue)
  for platformName, _ in pairs(platformDetail) do 
    if not platformConditions[platformName] then
      platformConditions[platformName] = {}
    end
    
    if newvalue == 0 then
      newvalue = nil
    end
    
    platformConditions[platformName][key] = newvalue
    save_platform(platformName)
    
    event.push("aspect_changed", "1234", platformName, component.digital_controller_box.aspects.yellow)
  end
end

local guiw, guih = gpu.getResolution()
function draw_gui()
  local curx, cury = term.getCursor()
  touchpos = {}
  gui.setForeground(0xffffff)

  term.setCursor(1, 5)
  
  -- sort the platform names, would be better to do this once rather than on each display
  local alldisabled = true
  local platforms = {}
  local platformcount = 0
  for k in pairs(platformDetail) do 
    table.insert(platforms, k) 
    platformcount = platformcount + 1
  end
  -- sort the keys
  table.sort(platforms)
  
  local format = "%-20.20s %-70.70s"
  lineno = 3
  for _, platformName in ipairs(platforms) do
    lineno = lineno + 1
    
    if lockedAspects then
      aspect = lockedAspects[platformName]
    else
      aspect = currentAspects[platformName]
    end
    
    local line = string.format(format, platformName, platformDetail[platformName])
    -- term.clearLine() causes flickering due to the border :(
    gui.set(7, lineno, line .. string.rep(" ", guiw - 4 - string.len(line)))
    
    if aspect then
      gpu.setForeground(aspectColors[aspect])
      gpu.set(4, lineno, "▒▒")
    end
    
    gpu.setForeground(0xffffff)
    
    if not platformConditions[platformName] or not platformConditions[platformName].disabled then
      alldisabled = false
    end
    
    touchpos[lineno] = platformName
  end
  lineno = lineno + 1
  -- draw the border after
  gui.box(2, 3, guiw - 3, platformcount + 2, "Platforms", 0x0000ff, 0xff00ff)
  
  if lock_logs then
    -- remove the button bottom border
    gui.set(guiw - 3 - 16, lineno + 1, "                 ")
  else
    gui.reset()
    if alldisabled then
      gui.buttonxy(guiw - 3 - 15, lineno, "Enable All", adjust_all_platforms, {"disabled", nil}, 11, 0x00ff00)
    else
      gui.buttonxy(guiw - 3 - 15, lineno, "Disable All", adjust_all_platforms, {"disabled", true}, 11, 0xff0000)
    end
    
    gui.setCursor(1, lineno + 5)
    
    for x = 1, 10 do
      term.clearLine()
      local line = ""
      if log[x] then
        line = log[x]
      end
      oldprint(line)
    end
  end
  
  term.setCursor(curx, cury)
end

local function adjust_platform_size(platformName, thissetup, key, newvalue)
  if not platformConditions[platformName] then
    platformConditions[platformName] = {}
  end
  if newvalue == 0 then
    newvalue = nil
  end
  
  platformConditions[platformName][key] = newvalue
  save_platform(platformName)  
  display_platform(platformName, thissetup)
end

local function platform_close()
  -- unlock the log diplay again, redraw the box with filled black on black
  lock_logs = false
  gui.reset()
  local x, y, w, h = gui.box(nil, nil, 61, 24, nil, 0x0, 0x0, nil, true)
  draw_gui()
end

-- Force a platform to be green for the current train to pass
-- TODO Should add a confirmation prompt here
local function platform_force(platformName, thissetup)
  aquireSetupLock()
  currentAspects[platformName] = component.digital_controller_box.aspects.green
  -- set a manul currentsetup and set the platforms score to high so it will be the platform chosen
  currentsetup = {
    ["tags"] = {}, ["length"] = 1, ["platformScores"] = {
      [platformName] = {
        ["score"] = math.huge,
        ["reason"] = "Forced Green"
        }
      }
  }

  releaseSetupLock()
  -- checkExists is not defined here, so instead push a signal so the main loop will call it
  -- checkExits()
  event.push("aspect_changed", "1234", platformName, component.digital_controller_box.aspects.red)
  os.sleep(1)
  event.push("aspect_changed", "1234", platformName, component.digital_controller_box.aspects.green)
  display_platform(platformName, thissetup)
end

local display_platform_filters_index = {["available"] = 1, ["assigned"] = 1}
local function display_platform_filters_change(platformName, key, action, item, thissetup)
  if not platformConditions[platformName] then
    platformConditions[platformName] = {}
  end
  if not platformConditions[platformName][key] then
    platformConditions[platformName][key] = {}
  end
  if action == "add" then
    -- for an add the item is the tag
    table.insert(platformConditions[platformName][key], item)
  else
    -- for a remove the item is the index
    table.remove(platformConditions[platformName][key], item)
    
    if next(platformConditions[platformName][key]) == nil then
      -- if its now empty set it to nil
      platformConditions[platformName][key] = nil
    end
  end
  
  save_platform(platformName)
  
  display_platform_filters(platformName, key, thissetup)
end
local function display_platform_filters_scroll(platformName, key, indexname, thissetup, newvalue)
  display_platform_filters_index[indexname] = newvalue
  display_platform_filters(platformName, key, thissetup)
end

function display_platform_filters(platformName, key, thissetup)
    local thisPlatform = platformConditions[platformName]
    if not thisPlatform then
      thisPlatform = {}
    end
    
    -- determine which filters/tags should display
    --   this is a list of filters we have seen but we remove any
    --   tags that are already in use for this platform
    -- TODO Should we allow for adding other tags as well
    local availabletags = {}
    local inusetags = {}
    
    if thisPlatform.nonetags then
      for _, tag in pairs(thisPlatform.nonetags) do
        inusetags[tag] = 1
        if not seenfilters[tag] then
          seenfilters[tag] = 1
        end
      end
    end
    
    if thisPlatform.alltags then
      for _, tag in pairs(thisPlatform.alltags) do
        inusetags[tag] = 1
        if not seenfilters[tag] then
          seenfilters[tag] = 1
        end
      end
    end
    if thisPlatform.anytags then
      for _, tag in pairs(thisPlatform.anytags) do
        inusetags[tag] = 1
        if not seenfilters[tag] then
          seenfilters[tag] = 1
        end
      end
    end
 
    for k, _ in pairs(seenfilters) do
        if not inusetags[k] then
          table.insert(availabletags, k)
        end
    end
    table.sort(availabletags)
    
    assignedtags = {}
    if thisPlatform[key] then
      assignedtags = thisPlatform[key]
      table.sort(assignedtags)
    end
    
    
    local title = ""
    if key == "alltags" then
      title = "Trains must match ALL of these"
    elseif key == "anytags" then
      title = "Trains must have at least ONE of these"
    elseif key == "nonetags" then
      title = "Trains must have NONE of these"
    end
      
    gui.reset()
    local x, y, w, h = gui.box(nil, nil, 61, 24, "Filter for " .. platformName, 0x0000ff, 0xff00ff, nil, true)
    local hx = gui.printcenter(y + 2, title, w, x)
    gui.set(hx, y + 3, string.rep("─", string.len(title)))
    
    
    gui.box(x + 2, y + 5, 26, 15, "Available Tags", 0x666600, 0xffffff, nil, false)
    
    lineno = y + 5
    local truncatesize = 22
    if gui.scrollbar(x + 26, y + 6, 12, display_platform_filters_index["available"], #availabletags, display_platform_filters_scroll, {platformName, key, "available", thissetup}) then
      truncatesize = truncatesize - 1
    end
    for idx, tag in ipairs(availabletags) do
        if idx >= display_platform_filters_index["available"]
          and idx < display_platform_filters_index["available"] + 13 then
          lineno = lineno + 1
          if thissetup and thissetup.tags and thissetup.tags[tag] then
            gui.setForeground(0xffff00)
          else
            gui.setForeground(0xffffff)
          end
          
          gui.clickable(x + 4, lineno, string.sub(tag, 1, truncatesize), display_platform_filters_change, {platformName, key, "add", tag, thissetup}, truncatesize) 
        elseif idx >= display_platform_filters_index["available"] + 13 then
          break
        end
    end
    
    gui.box(x + 3 + 27 + 3, y + 5, 26, 15, "Assigned Tags", 0x666600, 0xffffff, nil, false)
    lineno = y + 5
    truncatesize = 22
    if gui.scrollbar(x + 27 + 5, y + 6, 12, display_platform_filters_index["assigned"], #assignedtags, display_platform_filters_scroll, {platformName, key, "assigned", thissetup}) then
      truncatesize = truncatesize - 1
    end
    for idx, tag in ipairs(assignedtags) do
        if idx >= display_platform_filters_index["assigned"]
          and idx < display_platform_filters_index["assigned"] + 13 then
            
          lineno = lineno + 1
          if thissetup and thissetup.tags and thissetup.tags[tag] then
            gui.setForeground(0xffff00)
          else
            gui.setForeground(0xffffff)
          end
           
          gui.clickable(x + 27 + 8, lineno, string.sub(tag, 1, truncatesize), display_platform_filters_change, {platformName, key, "del", idx, thissetup}, truncatesize) 
        elseif idx >= display_platform_filters_index["assigned"] + 13 then
          break
        end
    end
    
    gui.buttonxy(x + math.floor(w / 2) - 6, y + 21, "Done", display_platform, {platformName, thissetup}, 11, 0x0, 0xffffff, 0xffffff)
end

function display_platform(platformName, thissetup)
  local thisPlatform = platformConditions[platformName]
  if not thisPlatform then
    thisPlatform = {}
  end
  lock_logs = true
  if not thissetup then
    thissetup = currentsetup
  end
  if not thissetup then
    thissetup = {}
  end
  -- lazy way to make sure we start at 0 when the next filter page is opened
  display_platform_filters_index = {["available"] = 1, ["assigned"] = 1}
  
  -- remove any locked detail such as the enable/disable all button
  draw_gui()
  gui.reset()
  
  local x, y, w, h = gui.box(nil, nil, 61, 24, platformName, 0x0000ff, 0xff00ff, nil, true)
  local hx = gui.printcenter(y + 2, "Platform Configuration", w, x)
  gui.set(hx, y + 3, "──────────────────────")
  
  
  gui.box(x + 3, y + 5, 24, 15, "Filters", 0x666600, 0xffffff, nil, false)
  
  local buttoncolor = nil
  if thisPlatform.nonetags then
    buttoncolor = 0x00ff00
  else
    buttoncolor = 0xff0000
  end
  -- text, call, side, extraparams, othercolor
  gui.button("has NONE of", display_platform_filters, 1, {platformName, "nonetags", thissetup}, 0, 0xffffff, buttoncolor)
  
  if thisPlatform.alltags then
    buttoncolor = 0x00ff00
  else
    buttoncolor = 0xff0000
  end
  gui.button("has ALL of", display_platform_filters, 1, {platformName, "alltags", thissetup}, 0, 0xffffff, buttoncolor)
    
  if thisPlatform.anytags then
    buttoncolor = 0x00ff00
  else
    buttoncolor = 0xff0000
  end
  gui.button("has ANY of", display_platform_filters, 1, {platformName, "anytags", thissetup}, 0, 0xffffff, buttoncolor)
    
  gui.displaybuttons(x + 2, y + 7, 24, -1)
  
  gui.setForeground(0xffffff)
  if thisPlatform.min_size then
    buttoncolor = 0x00ff00
  else
    buttoncolor = 0xffff00
  end
  gui.set(x + 29, y + 7,  "  Min length:")
  gui.numberselect(x + 29 + 14, y + 7, 9, thisPlatform.min_size, adjust_platform_size, {platformName, thissetup, "min_size"}, nil, 0, thisPlatform.max_size or 99, true, 0x0, buttoncolor)
  if thisPlatform.max_size then
    buttoncolor = 0x00ff00
  else
    buttoncolor = 0xffff00
  end
  gui.set(x + 29, y + 9,  "  Max length:")
  gui.numberselect(x + 29 + 14, y + 9, 9, thisPlatform.max_size, adjust_platform_size, {platformName, thissetup, "max_size"}, nil, thisPlatform.min_size or 0, 99, true, 0x0, buttoncolor)
  
  if not thisPlatform.weighting then
    -- warning since this is not it is reversed to the above
    buttoncolor = 0xffff00
  elseif thisPlatform.weighting > 0 then
    buttoncolor = 0x00ff00
  else      -- < is the only thing left
    buttoncolor = 0xff0000
  end
  gui.set(x + 29, y + 12, "  Weighting:")
  gui.numberselect(x + 29 + 14, y + 12, 9, thisPlatform.weighting, adjust_platform_size, {platformName, thissetup, "weighting"}, nil, -99, 99, true, 0x0, buttoncolor)
  
  gui.setForeground(0x666666)
  gui.set(x + 29, y + 6, "Restrict trains to:")
  gui.set(x + 29, y + 11, "Score Adjustment:")
  
  gui.printinbox(x + 28, y + 15, "Every filter adjusts the score higher, the available platform with the highest score will be selected first.", w - 29)
  
  -- manual buttons
  gui.buttonxy(x + 6, y + 21, "Done", platform_close, nil, 11, 0x0, 0xffffff, 0xffffff)
  if currentAspects[platformName] ~= component.digital_receiver_box.aspects.green
    and component.digital_receiver_box.getAspect(platformName) == component.digital_receiver_box.aspects.green 
    and (not platformConditions[platformName] or not platformConditions[platformName].disabled)
    then
      gui.buttonxy(x + 23, y + 21, "Force  Green", platform_force, {platformName, thissetup}, 11, 0x0, 0xffffff, 0xffffff)
  end
  
  if thisPlatform.disabled then
    gui.buttonxy(x + 40, y + 21, "Enable", adjust_platform_size, {platformName, thissetup, "disabled", nil}, 11, 0x00ff00)
  else
    gui.buttonxy(x + 40, y + 21, "Disable", adjust_platform_size, {platformName, thissetup, "disabled", true}, 11, 0xff0000)
  end
  
  gui.setForeground(0xffffff)
end

local function ev_touch(e, id, w, h, keymodifer, user)
  local pressed = gui.ev_touch(e, id, w, h, keymodifer, user)
  
  if pressed and pressed.call then
    if pressed.params then
      if type(pressed.params) == "table" then
        -- add the value if one is available to the end of the argument list
        table.insert(pressed.params, pressed.value)
        pressed.call(table.unpack(pressed.params))
      else
        pressed.call(pressed.params, pressed.value)
      end
    else
      pressed.call(pressed.value)
    end
  end
  if touchpos[h] then
    display_platform(touchpos[h])
  end
end

-- Return the score for the given platform
local function scorePlatform(platformName)
  if not platformName then
    print("A signal is not correctly named")
    return 0, "?"
  end
  
  local platformScore = 0
  if not platformConditions or next(platformConditions) == nil then
    -- With no conditions we dont need to do any filtering so keep the aspects the same
    return 1, "MATCH: No conditions"
  end
  
  local thisPlatformCondition = platformConditions[platformName]
  if not thisPlatformCondition then
    -- if there are no conditions then we mirror
    return 1, "MATCH: No platform Conditions set"
  end
  
  
  if not currentsetup or not currentsetup.tags then
      -- ?? not sure how we got get here since currentsetup is defined in our caller
    return 0, "YELLOW: Unsure of current train setup"
  end
  
  
  -- By this point we have a possible, work out if it would be allowed for
  --  the current train setup if its not then the platform goes to yellow to indcate its not valid
  --  if it is and the aspect is currently yellow, then we use red as caution doesnt really apply here
  
  -- train length
  if (thisPlatformCondition.min_size and currentsetup.length < thisPlatformCondition.min_size) or 
    (thisPlatformCondition.max_size and currentsetup.length > thisPlatformCondition.max_size) then
      return 0, "YELLOW: Train did not meet the length requirements (" .. tostring(thisPlatformCondition.min_size) .. " < " .. tostring(currentsetup.length) .. " > " .. tostring(thisPlatformCondition.max_size) .. ")"
  end
  
  -- Same again but for the none of tags
  if thisPlatformCondition.nonetags then
    local matched = nil
    for k, f in pairs(thisPlatformCondition.nonetags) do
      if currentsetup.tags[f] then
        matched = f
        break
      end
    end
    
    if matched then
      -- contained of the NONE OF requirement
      return 0, "YELLOW: Train contains a NONE OF requirement (" .. matched ..")"
    end
    platformScore = platformScore + (1 * 0.1)   -- its still restrictive
  end
  
  -- and lastly the Must have tags
  if thisPlatformCondition.alltags then
    matches = 0
    for k, f in pairs(thisPlatformCondition.alltags) do
      if currentsetup.tags[f] then
        matches = matches + 1
      end
    end
    if matches ~= #thisPlatformCondition.alltags then
      -- Did not match the ALL requirement
      return 0, "YELLOW: Train does not meet the ALL requirement (" .. tostring(matches) .. "/" .. tostring(#thisPlatformCondition.alltags) .. ")"
    end
    
    platformScore = platformScore + (matches * 0.1)
  end
  
  -- if we get here then this platform should be prefered over a unconfigured one
  platformScore = platformScore + 1
  
  -- Look for any matching anytags
  --   it would be faster to return on first match but as each match increases the score we need to process them all
  if thisPlatformCondition.anytags then
    local matches = 0
    for k, f in pairs(thisPlatformCondition.anytags) do
      if currentsetup.tags[f] then
        matches = matches + 1
      end
    end
    
    if matches == 0 then
      -- did not contain the ANY requirement
      return 0, "YELLOW: Train did not meet an ANY requirement"
    end
    
    platformScore = platformScore + (matches * 0.1)
  end
  
  -- Try to fit a larger train into a larger platform and leave smaller platforms for smaller trains
  if thisPlatformCondition.max_size  and thisPlatformCondition.max_size > 0 then
    platformScore = platformScore + ((currentsetup.length * thisPlatformCondition.max_size) / 100)
  end
  if thisPlatformCondition.min_size and thisPlatformCondition.min_size > 0 then
    platformScore = platformScore + (currentsetup.length - thisPlatformCondition.min_size)
  end
  
  if thisPlatformCondition.weighting then
    platformScore = platformScore + thisPlatformCondition.weighting
  end
  
  -- we now have a valid score to return
  return math.max(0, platformScore), "GREEN: " .. platformScore
end

-- Check the available platforms if one is available set it to green and allow entry
local function checkEntry()
  local en = component.digital_receiver_box.getAspect("Entrance")
  if en and en ~= component.digital_receiver_box.aspects.green and en ~= 6 then
    -- No need to check platforms if the controller is not green
    --  this also means that once a train enters the station entrace the green platform will remain available
    --  in theory nothing should be able to use a platform while a train is in the entrance line
    --  @todo do we need to double check that?
    component.digital_controller_box.setAspect("Entrance", en)
    
    return false
  end
  
  -- Entrance is green, unlock the aspects
  lockedAspects = nil
  
  aquireSetupLock()
  local platforms = getPlatforms()
  
  if not currentsetup or not currentsetup.tags then
    -- No active train make no changes beyond automatic ones
    component.digital_controller_box.setAspect("Entrance", component.digital_controller_box.aspects.yellow)
    releaseSetupLock()
    return
  end
  
  print("---- New train")
  print(getTrainDetail(currentsetup))
  
  -- find the best available platform and set signals
  local platformName = nil
  local bestScore = 0
  local bestPlatform = nil
  
  for _, platformName in pairs(platforms) do
      local platformScore = 0
      if currentsetup.platformScores[platformName] then
        platformScore = currentsetup.platformScores[platformName].score
        platformDetail[platformName] = currentsetup.platformScores[platformName].reason
      end
      
      local aspect = component.digital_receiver_box.getAspect(platformName)
      local newAspect = aspect
      
      if not platformScore then
          -- Might be a new platform just added
        platformDetail[platformName] = "RED: Unknown platform"
        newAspect = component.digital_controller_box.aspects.red
        platformScore = -1
      end
      
      -- disabled is the only live test
      if platformConditions[platformName] and platformConditions[platformName].disabled then
        platformDetail[platformName] = "RED: Platform is disabled"
        newAspect = component.digital_controller_box.aspects.red
        platformScore = -1
      end
      
      if not component.digital_controller_box.aspects[aspect] then
        -- We dont know what it should be, this is possibly the receiver sent 'off' but the controller doesnt know 'off'
        platformDetail[platformName] = "RED: Unknown aspect"
        newAspect = component.digital_controller_box.aspects.red
        platformScore = -1
      end
      
      if keepAspects[aspect] then
        -- Its a no-go aspect, so keep it the same
        platformDetail[platformName] = "MATCH: No entry aspect"
        newAspect = aspect     -- for awareness
        platformScore = -1
      end
      
      -- if the current aspect is yellow then its red (since yellow means invalid match)
      if aspect == component.digital_controller_box.aspects.yellow then
        platformDetail[platformName] = "RED: Platform is in-use (yellow block)"
        newAspect = component.digital_controller_box.aspects.red
        platformScore = -1
      end
      
      -- a score of 0 means its not available for the current setup
      if platformScore == 0 then
        newAspect = component.digital_controller_box.aspects.blink_yellow
      elseif platformScore > 0 then
        -- start as yellow until we find the best match
        newAspect = component.digital_controller_box.aspects.yellow
        
        if bestScore < platformScore then
          bestScore = platformScore
          bestPlatform = platformName
        end
      end
      
      if currentAspects[platformName] ~= newAspect then
        currentAspects[platformName] = newAspect
      end
  end
  
  releaseSetupLock()
  
  print("Platform Status")
  for k, v in pairs(platformDetail) do
    print(k, v)
  end

  -- Remember the controller might be green, but we have set the receiver to something else
  if bestPlatform then
    print("Best platform", bestPlatform, bestScore, " >> green")
    component.digital_controller_box.setAspect(bestPlatform, component.digital_controller_box.aspects.green)
    currentAspects[bestPlatform] = component.digital_controller_box.aspects.green
    
    component.digital_controller_box.setAspect("Entrance", component.digital_controller_box.aspects.green)
    
    
    -- lock the aspects to their current state so they only go to a more restrictive one until the train has passed over
    lockedAspects = currentAspects
  else
    -- if we get here then there are no platforms that are green, use red
    component.digital_controller_box.setAspect("Entrance", component.digital_controller_box.aspects.red)
  end

  -- apply the acual aspects, this prevents signals going green > yellow > green while we do the checks
  for _, platformName in pairs(platforms) do
    component.digital_controller_box.setAspect(platformName, currentAspects[platformName])
  end

end

-- Exit is a little more complicated as it needs to work like an interlock
--   and theres three different ways to set it up
--     option 1: A externally controlled exit line (eg. with interlocks) and we treat the signal as standard
--     option 2: Platforms have exit receievers named Platform X Exit and we cycle each platform that is red (even if a train is not ready to leave)
--     option 3: Platforms have exit receievers and controllers named Platform X Exit and we treat the controller as a signal a train wants to leave (emulating an interlock)
--     option 4: A mixture of the above, but that would be insane
local activeExit = 0
local nextExitCheck = 0
local function checkExit()
  local ex = component.digital_receiver_box.getAspect("Exit")
  local exit_controllers = component.digital_controller_box.getSignalNames()
  if ex and ex ~= component.digital_receiver_box.aspects.green and ex ~= 6 then
    -- No need to check platforms if the controller is not green
    component.digital_controller_box.setAspect("Exit", ex)
    for k, exitName in pairs(exit_controllers) do
      if string.sub(exitName, -4) == "Exit" then
        component.digital_controller_box.setAspect(exitName, component.digital_controller_box.aspects.red)
      end
    end
    nextExitCheck = 0
    return false
  end
  
  -- leave each exit open for at least 2 seconds so a train can enter the Exit line
  --  once the Exit line is in-use we can assume it was the train we let in so when it
  --  leaves the line we can open the next one
  if computer.uptime() < nextExitCheck then
    return
  end
  
  local exitName = nil
  local waitingExits = {}
  for k, exitName in pairs(exit_controllers) do
    if string.sub(exitName, -4) == "Exit" then
      local waiting = component.digital_receiver_box.getAspect(exitName)
      
      -- Note normally with interlocks you have to change the controller to output
      --   green when a train is present, we use red since green is the default
      --   and it makes it quicker to place
      if waiting then
        -- We only need to append it to the table if its red (has a train waiting)
        if waiting == component.digital_receiver_box.aspects.red then
          table.insert(waitingExits, exitName)
          component.digital_controller_box.setAspect(exitName, component.digital_controller_box.aspects.red)
        else
          component.digital_controller_box.setAspect(exitName, component.digital_controller_box.aspects.yellow)
        end
      else
        -- If there was no exit controller append it to the table to be cycled
        table.insert(waitingExits, exitName)
        component.digital_controller_box.setAspect(exitName, component.digital_controller_box.aspects.red)
      end
    end
  end
 
  -- Nothing to let out
  if #waitingExits == 0 then
    return
  end
 
  -- Ensure every exit is given the chance to leave
  nextExitCheck = computer.uptime() + 2
  activeExit = activeExit + 1
  if activeExit > #waitingExits then
    activeExit = 1
  end
  component.digital_controller_box.setAspect(waitingExits[activeExit], component.digital_controller_box.aspects.green)
end



local function ev_detect(...)
  local e = {...}
  if not currentsetup then
    currentsetup = {
      ["tags"] = {}, ["length"] = 0, ["platformScores"] = {}
    }
  end
  
  -- Hold a minecart in place until we have read its contents (if any)
  component.digital_controller_box.setAspect("Detector", component.digital_controller_box.aspects.red)
  
  -- If there is a lock in place
  aquireSetupLock()
  
  if e[1] == "minecart" then
    -- cart/engine type
    currentsetup.tags[e[3]] = 1
    -- cart/engine name
    currentsetup.tags[e[4]] = 1
    if e[5] then
      -- engine colours, computronics provides the dye colour values rather than wool colours that opencomputers uses
      currentsetup.tags["has " .. engineColors[e[5]]] = 1
      currentsetup.tags[engineColors[e[5]] .. " top"] = 1
      currentsetup.tags["has " .. engineColors[e[6]]] = 1
      currentsetup.tags[engineColors[e[6]] .. " bottom"] = 1
    end
    if e[7] then
      -- destination name
      if e[7] == "" then
        currentsetup.tags["No Destination"] = 1
      else
        currentsetup.tags[e[7]] = 1
      end
--      print(e[7])
    end
    if e[8] then
      -- owner
      currentsetup.tags[e[8]] = 1
    end
    
    -- Increase the length as carts/engines pass by
    currentsetup["length"] = currentsetup["length"] + 1
  elseif e[1] == "redstone_changed" then
    currentsetup.tags["redstone signal"] = 1
    -- redstone amount
    currentsetup.tags["redstone signal " .. e[5]] = 1
    -- other things we could provide:
    --   - redstone io entityid e[2]
    --   - cns value of redstone io entityid cns(e[2])
    --   - redstone side e[3]
  end
  
  -- if there is a transposer attached then scan any available inventory
  -- we dont want to read the items such as tickets, or fuel
  --  in the locomotive as that will confuse the no_items ruke
  if component.transposer and string.sub(e[3], 0, 10) ~= "locomotive" then
    -- check all attached transposers (for multi cargo trains?)
    for t in component.list("transposer") do
      -- to make the passes faster we cache the active sides of the transposer
      --  so if we have not seen this transposer or its been a while rescan
      if not transposerSides[t] or transposerSides[t].expire < computer.uptime() then
        -- print("Finding active side of transposor, this could take a moment")
        for side = 0, 5 do
          -- getInventoryName returns nil if no inventory
          --  remember to not place an inventory next to a transposer or it will be confused
          local tmpname = component.invoke(t, "getInventoryName", side)
          if tmpname then
            transposerSides[t] = {["side"] = side, ["expire"] = computer.uptime() + 300}
            -- print("Found side", transposerSides[t].side, tmpname)
            break
          end
        end
      end
      if transposerSides[t] and transposerSides[t].side then
        os.sleep(0.2)   -- wait a moment to make sure only the one cart is sitting on the track (avoids a size error with a chest and tank cart)
        local tmpsize = component.invoke(t, "getInventorySize", transposerSides[t].side)
        if tmpsize then
          for slot = 1, tmpsize do
            -- using pcall here, because tanks can return an invalid inventory size which getStackInSlot then returns an error at
            local i = component.invoke(t, "getStackInSlot", transposerSides[t].side, slot)
            if i then
              currentsetup.tags["has items"] = 1
              currentsetup.tags[i.label] = 1
              currentsetup.tags[i.name] = 1
            end
          end
        
          -- getFluidInTank returns an empty array if not inventory so we dont need to recheck
          local tmpfluid = component.invoke(t, "getFluidInTank", transposerSides[t].side)
          if tmpfluid.n > 0 then
            for k, i in pairs(tmpfluid) do
              if k ~= "n" then
                currentsetup.tags["has fluid"] = 1
                currentsetup.tags[i.label] = 1
                currentsetup.tags[i.name] = 1
              end
            end
          end
        end
      end
    end
  end
  
  releaseSetupLock()
  -- just a quick pulse to move one cart forward
  component.digital_controller_box.setAspect("Detector", component.digital_controller_box.aspects.green)
  os.sleep(0.2)
  component.digital_controller_box.setAspect("Detector", component.digital_controller_box.aspects.red)
  
  
  -- calculate the platform scores here
  print("Starting train detail")
  print(getTrainDetail(currentsetup))
  
  -- find the best available platform and set signals
  local platformName = nil
  local platforms = getPlatforms()
  
  for _, platformName in pairs(platforms) do
    local platformScore, scoreReason = scorePlatform(platformName)
    
    currentsetup.platformScores[platformName] = {["score"] = platformScore, ["reason"] = scoreReason}
  end
  
  -- trigger an entry check
  checkEntry()
  
  -- add all the current setups to the seen filters so they can be selected in the GUI later
  for tag, _ in pairs(currentsetup.tags) do
    seenfilters[tag] = computer.uptime()
  end
end

local function ev_exit(e, _, _, ab)
  if e == "key_up" and ab ~= 103 then     -- only exit on 'q'
    return
  end
  
  oldprint("Exiting due to ", e)
  -- should check for if the key is Q here
  running = false
  
  -- set everything to blink red to indicate the controller is offline
  component.digital_controller_box.setEveryAspect(component.digital_controller_box.aspects.blink_red)
  
  -- push the event the main loop is looking for
  event.push("aspect_changed", "1234", "Exit")

  event.ignore("key_up", ev_exit)
  event.ignore("interupted", ev_exit)
  event.ignore("minecart", ev_detect)
  event.ignore("redstone_changed", ev_detect)
  event.ignore("touch", ev_touch)
  --os.exit()
end

-- To avoid any unwanted events on startup set all signals to blink yellow so we know we are in startup
--component.digital_controller_box.setEveryAspect(component.digital_controller_box.aspects.blink_yellow)

-- clear out the event queue so we dont get a key_up event and kill ourselves
local wait = true
while wait do 
  wait = event.pull(1) 
end

-- Load the platform configs from disk
fs.makeDirectory(platformConfigFiles)
local file
for file in fs.list(platformConfigFiles) do
  local f = io.open(platformConfigFiles .. "/" .. file, "r")
  local i = serialization.unserialize(f:read("*all"))
  platformConditions[file] = i
  f:close()
end

local platforms = getPlatforms()
for _, p in pairs(platforms) do
  if platformConditions[p] and platformConditions[p].disabled then
    platformDetail[p] = "Platform is disabled (boot)"
    currentAspects[p] = component.digital_receiver_box.aspects.red
  else
    platformDetail[p] = "Unknown state (boot)"
    currentAspects[p] = component.digital_receiver_box.aspects.blink_yellow
  end
end

term.clear()

-- Loop over all the platforms and match their initial settings
checkEntry()
checkExit()

draw_gui()

event.listen("key_up", ev_exit)
event.listen("interupted", ev_exit)
event.listen("touch", ev_touch)

-- These are used to detect the type of cart to make a decision at the Entrance
event.listen("minecart", ev_detect)             -- computronics digital detector (color and name)
event.listen("redstone_changed", ev_detect)     -- if not using a digital detector, need to signal that we should check the transposer

while running do
  local e, _, platformName, aspect, oo = event.pull(3, "aspect_changed")
  if e then
    local aspectNow = component.digital_receiver_box.getAspect(platformName)
    if isPlatform(platformName) then
      -- aspect 'should' match what the signal currently is but if we are behind on events we dont want to set an old value
      --   so instead we pull the current
      -- we dont set anything lower than a locked Aspect
      if not lockedAspects 
          or not lockedAspects[platformName] 
          or aspectNow >= lockedAspects[platformName] then
            -- if there are no locked aspects then nothing should pass
            if not lockedAspects and aspectNow == component.digital_controller_box.aspects.green then
              aspectNow = component.digital_controller_box.aspects.yellow
            end
            component.digital_controller_box.setAspect(platformName, aspectNow)
      else
        component.digital_controller_box.setAspect(platformName, lockedAspects[platformName])
      end
    end
    
    
    checkEntry()

    if platformName == "Entrance" then
      -- treat yellow as red so its less conditions to check
      if (aspectNow == component.digital_controller_box.aspects.yellow 
        or aspectNow == component.digital_controller_box.aspects.red) then
        aspectNow = component.digital_controller_box.aspects.red
      end
      
      if (aspectNow == component.digital_controller_box.aspects.red 
        and currentAspects[platformName] ~= aspectNow) then
           -- we have let this train pass so we can prepare for the next train
          aquireSetupLock()
          currentsetup = nil
          releaseSetupLock()
          
          currentAspects[platformName] = component.digital_controller_box.aspects.red
      else
        currentAspects[platformName] = aspectNow
      end
    end
  end
  
  -- If there has been no activity we still need to cycle the exits (although it will be slower)
  checkExit()
  
  draw_gui()
end

-- ev_exit should do these but just in case we get here
event.ignore("key_up", ev_exit)
event.ignore("interupted", ev_exit)
event.ignore("minecart", ev_detect)
event.ignore("redstone_changed", ev_detect)
event.ignore("touch", ev_touch)

-- set everything to blink red to indicate the controller is offline
component.digital_controller_box.setEveryAspect(component.digital_controller_box.aspects.blink_red)

os.exit()
