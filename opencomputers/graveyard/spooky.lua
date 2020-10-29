--[[ Spooky Graveyard hlogram Ghost with redstone output for sounds
     Author: nzHook
     Created for the Youtube channel https://youtube.com/user/nzHook 2020
     myRail Episode Showing Usage: TO BE FILLED
     NOTE: Requires:
       - hologram projectors (tier 2 if below ground level)
          each projector must be placed in the same direction
       - redstone io
    SETUP
      First run will write all the connected projectors to /holo.devices
        The first 3 digits of the component id will be projected above the device
      Open /holo.devices and rearrange to match the order placed (eg. blue, green, yellow... position 1, 2, 3...)
      Save and run again to check the order is now correct
      When the order is correct open /holo.devices again and change setup_mode to false
      Run and the ghost should appear
      If ghost jumps large blocks modify the rotation value (270 and 90 are the norms)
      
      To use sounds you will need an integrated dyanmaics setup see video for
      detail, could be used for something else redstone related
      
      See configs below for other settings

     
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

--
-- config
--

-- side to output a random redstone signal to every now and then
local rsside = 0    -- sides.bottom
-- max signal to output (its analog so absolute max is 15)
local maxrsvalue = 12

-- number of projectors in a row (used during setup)
local holoperrow = 5
-- the colour to make the ghosts (we only use this and transparent)
local color = 0xFFFFFF0

-- the rotation the projectors are in (they need to all be facing the same directiin, this will just set the facing direction)
local rotation = 90

-- min/max sizes of the projector to use
local maxy = 100
local miny = 1
local maxx = (16 * 3)
local minx = 1
local maxz = (16 * 3)
local minz = 1

-- max width is 48 (16 * 3)
-- max height is 32
local imagecount = 2
local images = {
[0] = [[
                   ********
                 ***********
               ***************
              *****************
              *****************
             ********************
             ***   ********   ****
*           ***      *****     ****
***      *******   ********   *********  ***
 *********************  **********************
 ********************    **********************
 ********************    *********************
  ******************************************
   ***************************************
      ***********************************
       *********************************
         *****************************
           **************************
            ************************
            ***********************
             **********************
              ********************
               ******************
                 ***************
                   ***********
                    *********
                     ******
                     ****
                     **
                     * 
                    * 
]],
[1] = [[
                   ********
                 ***********
               ***************
              *****************
              *****************
             ********************
             ***   ********   ****
            ***      *****     ****
 **      *******   ********   *********  **
**********************  *********************
*********************    *********************
 ********************    *********************
  *******************************************
   ****************************************
      ************************************
       *********************************
         *****************************
           **************************
            ************************
            ***********************
             **********************
              ********************
               ******************
                 ***************
                   ***********
                    *********
                     ******
                     ****
                     **
                     * 
                    * 
]]
}

-- for setup, these are the colours
local setup_colors      = {0xFF0000, 0x00FF00, 0x0000FF, 0xFFFF00, 0x00FFFF, 0xFF00FF}
local setup_color_names = {"red",    "green",  "blue",   "yellow", "cyan",   "purple"}
-- (numbers copied from holo-text from Sangar)
local setup_glyphs = {
  ["a"]=[[
  XXXXX
  X   X
  XXXXX
  X   X
  X   X
  ]],
  ["b"]=[[
  XXXX 
  X   X
  XXXX 
  X   X
  XXXX 
  ]],
  ["c"]=[[
  XXXXX
  X    
  X    
  X    
  XXXXX
  ]],
  ["d"]=[[
  XXXX 
  X   X
  X   X
  X   X
  XXXX 
  ]],
  ["e"]=[[
  XXXXX
  X    
  XXXX 
  X    
  XXXXX
  ]],
  ["f"]=[[
  XXXXX
  X    
  XXXX 
  X    
  X    
  ]],
  ["g"]=[[
  XXXXX
  X    
  X XXX
  X   X
  XXXXX
  ]],
  ["h"]=[[
  X   X
  X   X
  XXXXX
  X   X
  X   X
  ]],
  ["i"]=[[
   XXX 
    X  
    X  
    X  
   XXX 
  ]],
  ["j"]=[[
      X
      X
      X
  X   X
  XXXXX
  ]],
  ["k"]=[[
  X   X
  X  X 
  XXX  
  X  X 
  X   X
  ]],
  ["l"]=[[
  X    
  X    
  X    
  X    
  XXXXX
  ]],
  ["m"]=[[
  X   X
  XX XX
  X X X
  X   X
  X   X
  ]],
  ["n"]=[[
  X   X
  XX  X
  X X X
  X  XX
  X   X
  ]],
  ["o"]=[[
  XXXXX
  X   X
  X   X
  X   X
  XXXXX
  ]],
  ["p"]=[[
  XXXXX
  X   X
  XXXXX
  X    
  X    
  ]],
  ["q"]=[[
  XXXXX
  X   X
  X   X
  X  X 
  XXX X
  ]],
  ["r"]=[[
  XXXXX
  X   X
  XXXX 
  X   X
  X   X
  ]],
  ["s"]=[[
  XXXXX
  X    
  XXXXX
      X
  XXXXX
  ]],
  ["t"]=[[
  XXXXX
    X  
    X  
    X  
    X  
  ]],
  ["u"]=[[
  X   X
  X   X
  X   X
  X   X
  XXXXX
  ]],
  ["v"]=[[
  X   X
  X   X
  X   X
   X X 
    X  
  ]],
  ["w"]=[[
  X   X
  X   X
  X X X
  X X X
   X X 
  ]],
  ["x"]=[[
  X   X
   X X 
    X  
   X X 
  X   X
  ]],
  ["y"]=[[
  X   X
  X   X
   XXX 
    X  
    X  
  ]],
  ["z"]=[[
  XXXXX
      X
   XXX 
  X    
  XXXXX
  ]],
  ["0"]=[[
   XXX 
  X   X
  X X X
  X   X
   XXX 
  ]],
  ["1"]=[[
    XX 
   X X 
     X 
     X 
     X 
  ]],
  ["2"]=[[
  XXXX 
      X
    X  
  X    
  XXXXX
  ]],
  ["3"]=[[
  XXXX 
      X
   XXX 
      X
  XXXX 
  ]],
  ["4"]=[[
  X   X
  X   X
  XXXXX
      X
      X
  ]],
  ["5"]=[[
  XXXXX
  X    
  XXXX 
      X
  XXXX 
  ]],
  ["6"]=[[
   XXX 
  X    
  XXXX 
  X   X
   XXX 
  ]],
  ["7"]=[[
  XXXXX
     X 
   XXX 
    X  
   X   
  ]],
  ["8"]=[[
   XXX 
  X   X
   XXX 
  X   X
   XXX 
  ]],
  ["9"]=[[
   XXX 
  X   X
   XXXX
      X
   XXX 
  ]],
  [" "]=[[
       
       
       
       
       
  ]],
}

--
-- some globals and library loads
--
local filesystem = require("filesystem")
local component = require("component")
local os = require("os")
local new_setup = false
-- holoindex and setup_mode need to be a true global so loadfile can set them
holoindex = nil
setup_mode = false
local holos = {}
local maxholdsize = {}


--
-- functions
--
-- similar to the holo-text example
local function draw(hologram, startx, startz, value, colorindex)
  local bm = {}
  for token in value:gmatch("([^\r\n]*)") do
    if token ~= "" then
      table.insert(bm, string.format("%-48s", token))
    end
  end
  local z = minz + startz
  local h,w = #bm,#bm[1]
  for i=1, w do
    local x = minx + i + startx
    for j=1, h do
      local y = miny + j-1
      if bm[1+h-j]:sub(i, i) == " " then
--        hologram.set(x, y, z - 1, 0)
--        hologram.set(x, y, z, 0)
--        hologram.set(x, y, z - 1, 0)
      else
--        hologram.set(x, y, z - 1, colorindex)
        hologram.set(x, y, z, colorindex)
--        hologram.set(x, y, z + 1, colorindex)
      end
    end
  end
end

-- again a copy of holo-text so we can show componentid during setup
local function maketext(text) 
  local value = ""
  -- Generate one big string that represents the concatenated glyphs for the provided text.
  for row = 1, 5 do
    for col = 1, #text do
      local char = string.sub(text:lower(), col, col)
      local glyph = setup_glyphs[char]
      if glyph then
        local s = 0
        for _ = 2, row do
          s = string.find(glyph, "\n", s + 1, true)
          if not s then
            break
          end
        end
        if s then
          local line = string.sub(glyph, s + 1, (string.find(glyph, "\n", s + 1, true) or 0) - 1)
          value = value .. line .. " "
        end
      end
    end
    value = value .. "\n"
  end
  return value
end

-- determine which projector should be active and set its colour and translation
local oldholo
local oldposx = 0
local oldposz = 0
local oldposr = 0
local oldimage = 0
local function move(x, y, z, r)
  local posx = (x % maxx) - 16
  local posy = y + 1
  local posz = (z % maxz)
  local holox = math.floor(x / maxx) + 1
  local holoz = math.floor(z / maxz) + 1

  -- we work in decimals so convert the x and z to decimal
  posx = posx / 100
  posy = posy / 10
  posz = posz / 100
  
  if not holoindex[holoz] or not holoindex[holoz][holox] then
    print("No projector available for ", holox, holoz)
    if oldholo then
      oldholo.setPaletteColor(1, 0)
      oldhold = nil
    end
    return
  end
  local holoid = holoindex[holoz][holox]
  local holo = holos[holoid]
  if not holo then
    print("Invalid projector for ", holoid, "at", holox, holoy)
    if oldholo then
      oldholo.setPaletteColor(1, 0)
      oldhold = nil
    end
    return
  end

  -- make sure the new projector is online
  if oldholo then
    if oldholo ~= holo then
      holo.setPaletteColor(1, color)
    end
  end
  
  local newimage = oldimage + 1
  if newimage >= imagecount then
    newimage = 0
  end
  
  if posz ~= oldposz then
    draw(holo, 1, posz * 100, images[newimage], 1)
  end
  if posy ~= oldposy or posx ~= oldposx then
    holo.setTranslation(posx, 2 - posy, 0)
  end
  if r ~= oldposr then
    holo.setRotation(rotation - r, 0, rotation - r, 0)
  end
  
  -- remove the old one, we do this after drawing the first to avoid the flicker
  if oldholo then
    if oldholo ~= holo then
      oldholo.setPaletteColor(1, 0)
    end
    draw(oldholo, 1, oldposz * 100, images[oldimage], 0)
  end
   
  oldposz = posz
  oldposx = posx
  oldposr = r
  oldimage = newimage
  oldholo = holo
end

-- pick a random start and end point that exists
local function berandom(dir) 
  local startx = math.random(75, 150)
  local limits = maxholdsize[math.ceil(startx / maxx)] * maxx
  local limite = 15
  if dir < 0 then
    local limits = 150
    local limite = (maxholdsize[math.floor(startx / maxx)] * maxx) + 15
  end
  local startz = math.random(75, limits)
  
  local endz = math.random(limite, startz - 15)
  return startx, startz, endz
end

-- code

if filesystem.exists("/holo.devices") then
  print("loading /holo.devices")
  local re, err = loadfile("/holo.devices")
  if not re then
    print(err)
    os.exit()
  end
  
  re()
end
if not holoindex then
  holoindex = {[0] = {}}
  local i = 0
  for id, null in pairs(component.list("hologram")) do
    holoindex[0][i] = id
    i = i + 1
  end
  
  setup_mode = 1
  new_setup = {}
end
local redraw = false

for rown, rowholos in pairs(holoindex) do
  for coln, id in pairs(rowholos) do
    print("Setting up " .. id .. " (" .. rown .. ", " .. coln .. ")")

    holos[id] = component.proxy(id)
    holos[id].setTranslation(0, 0, 0)
    holos[id].setRotation(rotation, 0, rotation, 0)
    holos[id].setScale(1)
    holos[id].clear()
    if not maxholdsize[coln] then
      maxholdsize[coln] = 0
    end
    maxholdsize[coln] = maxholdsize[coln] + 1

    -- we only use white (and transparent) unless in setup mode
    if setup_mode then
      holos[id].setTranslation(0, 3, 0)
      if new_setup then
        local curcolor = math.floor(setup_mode / holoperrow)
        
        if not new_setup[curcolor] then
          new_setup[curcolor] = {}
        end
        coln = (setup_mode % holoperrow)
        rown = curcolor
        new_setup[curcolor][coln] = id
        
        setup_mode = setup_mode + 1
      end
      holos[id].setPaletteColor(1, setup_colors[rown + 1])
      local txt = maketext(" " .. coln .. " ")
      txt = txt .. "\n \n" .. maketext(string.sub(id, 1, 3))
      draw(holos[id], 1, 1, txt, 1)
    else
      holos[id].setPaletteColor(1, color)
--      if redraw then
--        draw(holos[id], 1, 1, images[0], 1)
--      end
    end
  end
end

if setup_mode and new_setup then
  local tmpf = io.open("/holo.devices", "w")
  tmpf:write("-- Holo devices - change to match the colors and numbers shown on the projectors then set setup_mode = false\n")
  tmpf:write("holoindex = {\n")
  for curcolor, newrows in pairs(new_setup) do
    tmpf:write("  -- " .. setup_color_names[curcolor + 1] .. "\n")
    tmpf:write('  [' .. curcolor .. '] = {')
    
    for newcol, id in pairs(newrows) do
      tmpf:write('"' .. id .. '", ')
    end
    
    tmpf:write("},\n")
  end
  tmpf:write("}\n\nsetup_mode = true")
  tmpf:close()
  print("New setup detected, /holo.devices has been written")
end
-- bail out if still in setup mode
if setup_mode then
  print("Setup mode still enabled, edit /holo.devices then run again\n")
  os.exit()
end

--
-- ok, lets do the animation and noises
--

local startx, startz, endz = berandom(0)

local dir = 1
local ghostx = startx
local ghostz = startz
local ghosty = 15
local standardghostmod = 0.3
local ghostmod = standardghostmod 
local ghostmodz = 1
local ghostr = 0
local nextstartx = 0
local nextstartz = 0
local nextendz = 0
local curr = 0
local delay = 0

while true do
  -- play a sound every 10 interations
  if i % 10 == 0 then
    component.redstone.setOutput(rsside, math.random(1, maxrsvalue))
    component.redstone.setOutput(rsside, 0)
  end
  
  if ghostr == 0 then
    ghostr = 2 + curr
  elseif ghostr == 2 then
    ghostr = 1 + curr
  elseif ghostr == 1 then
    ghostr = -2 + curr
  else
    ghostr = 0 + curr
  end
    
  local tmpz = ghostz
  if dir < 0 then
    tmpz = endz + (startz - ghostz)
  end
  if delay < 1 then
    move(ghostx, ghosty, tmpz, ghostr)
  end
  
  if ghostz > endz then
    if ghosty > 10 then
      ghostmod = -0.6
    else
      if i % 3 == 0 then
        if ghostmod > 0 then
          ghostmod = -standardghostmod
        else
          ghostmod = standardghostmod
        end
      end
    end
  else
    if ghostz > (endz - 1.5) then
      if ghostmod ~= 0.6 then
        nextstartx, nextstartz, nextendz = berandom(-dir)
      end
      
      if math.abs(nextstartx - ghostx) > 15 then
        if nextstartx > ghostx then
         curr = (curr - (20 / 15)) * dir
        else
         curr = (curr + (20 / 15)) * dir
        end
      end
      ghostmod = 0.6
      ghostmodz = 0.1
    else
      ghostmod = 0.3
      ghostmodz = 1
      dir = -dir
      delay = math.floor((math.abs(nextstartx - startx) + math.abs(nextstartz - startz)) / 2) * 2
      startx, startz, endz = nextstartx, nextstartz, nextendz
      curr = 0
      

      ghostz = startz
      ghostx = startx
    end
  end
  
  if delay < 1 then
    ghostx = ghostx
    ghosty = ghosty + ghostmod
    ghostz = ghostz - ghostmodz
  else
    delay = delay - 1
  end
  
  os.sleep(0.00001)
end
