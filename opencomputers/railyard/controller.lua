--[[ Engine controller - keeps X number of engines in the system
     Author: nzHook
     Created for the Youtube channel https://youtube.com/user/nzHook 2018
     myRail Episode Showing Usage: Ep18 - https://www.youtube.com/watch?v=02_GhpYRju4
     myRail Episode Where Updated For Computronics: Ep43 - https://youtu.be/SisYSkjtHjg
     
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
local component = require("component")
local os = require("os")
local event = require("event")
local sides = require("sides")
local colors = require("colors")
local computer = require("computer")
local serialization = require("serialization")
local filesystem = require("filesystem")
local term = require("term")

-- This is the redstone IO that is the primary
--    there is no garentuee that OC will detect this correctly each boot
--    with the new computronics setup there should only be one now so set this to nil
--    unless you have multiple IOs still attached
--local rsid = "447"
local rsid = nil

-- rsmax is the starting point for the number calcs, eg. if the redstone io is 1 block away then any signal for white
--   would be 15 - 1. so this value should be 14
--   NOTE: Vanilla goes to 15, this code works in base 10, so you can have a maximum of 5 blocks between
--local rsmax = 14

-- Tasks, indexed by their name
--   dest = Name of ticket to assign
--   required = Number of trains to setup initially (delete engines.state file to reset)
--   carts = The cart order to use, trains not in this order are sent to the yard (the yard also requests this)

local tasks = {}
tasks["WoodyTreeTransport"] = {dest = "Treefarm Island", required = 1, carts = "cargo cargo cargo cargo chunk"}
tasks["WaterviewLine"] = {dest = "Waterview Passagengers", required = 1, carts = "basic basic basic basic chunk"}
tasks["CharcoalHillCharcoal"] = {dest = "Charcoal Power", required = 1, carts = "chest chest chunk"}
tasks["XMasLine"] = {dest = "XMas Line", required = 1, carts = "chest basic cargo chest"}

-- Redstone colour maps
colors.blockentry = colors.magenta                    -- Locking track at the entry
colors.enteryard = colors.white                      -- Switch motor for Yard
colors.depotexit = colors.yellow                      -- Locking track at the exit of the depot
colors.blockinuse = colors.orange                     -- Track in use (from block signal)

-- The table set for the routing book into the depot to send a train there
--   This is will only bne set when we want the train to go there
--   so use something that should force the train there (eg. NOT some random name)
--  WARNING Not used currently, routing books update but routing switches ignore. left here for if fixed in the future
local defaultRoutingTable = {"NOT", "Name=IgnoreTheRoutingTable"}

-- Debugging of the redstone
colors.rs = colors
colors.rs[0] = colors.white
colors.rs[1] = colors.orange
colors.rs[2] = colors.magenta
colors.rs[3] = colors.lightblue
colors.rs[4] = colors.yellow

-- The port that we listen on for updates - should be unique
local comms_port = 1234
-- rcomm is the port we send our comms back (nothing yet)
local rcomms_port = 1235


-- Top animation
local ssaver = {}
ssaver[0]   = "                        . . . o o o O O O"
ssaver[1]   = "                              _____       O"

ssaver[0.5] = "                       . . . o o o O O O O"
ssaver[1.5] = "                              _____        "
ssaver[2]   = " ____   ____   ____   __.....  )  |___n__]["
ssaver[3]   = "/\\__/\\_/\\__/\\_/\\__/\\_[_______]_|__|________)|"
ssaver[4]   = "`o  o' `o  o' `o  o'  oo   oo  `oo-OOO-' oo\\\\__"
local screensize = term.getViewport() - 2
local descsize = screensize - (3 + 3 + 6 + 7)

-- Add the whitespace to the start here, saves us recalculating it on every run
for i = 0, 4 do
  ssaver[i] = string.rep(" ", screensize) .. ssaver[i]
end
ssaver[0.5] = string.rep(" ", screensize) .. ssaver[0.5]
ssaver[1.5] = string.rep(" ", screensize) .. ssaver[1.5]


-- Internal vars
local nextstatecheck = 0
local engines = {}
local defaultchecktimeout = 0.1
local checktimeout = defaultchecktimeout
local runstate = 1
local expected_carts = {}


local oldprint = print
local log = {}
local function print(...)
    -- We track previous messages to show in the GUI
    for x = 1, 9 do
        log[x] = log[x + 1]
    end
    log[10] = table.pack(...)
--    oldprint(...)
end

currentssloc = 0
local function draw_gui()
  local curx, cury = term.getCursor()
  term.setCursor(1, 1)
	if currentssloc <= 0 then
		currentssloc = string.len(ssaver[3])
	end
	currentssloc = currentssloc - 1


  term.clearLine()
  oldprint("")

  for i = 0, 4 do
    if i <= 1 and currentssloc % 4 <= 2 then
      oldprint(" " .. string.sub(ssaver[i + 0.5], currentssloc, currentssloc + screensize - 1))
    else
      oldprint(" " .. string.sub(ssaver[i], currentssloc, currentssloc + screensize - 1))
    end
  end


-- DRAW_GUI
  oldprint(" ┌" .. string.rep("─", screensize - 2) .. "┐")
  local lineno = 7
  for k, v in pairs(tasks) do
    lineno = lineno + 1
    oldprint(string.format(" │ %-" .. descsize .. "." .. descsize .. "s %3i/%-3i [-][+] │", k, v.current, v.required))
    tasks[k].guiline = lineno
  end
--  term.clearLine()
  oldprint(" └" .. string.rep("─", screensize - 2) .. "┘")
  for x = 1, 5 do
    term.clearLine()
    if log[x] then
      oldprint(table.unpack(log[x]))
    end
  end
  term.setCursor(curx, cury)
end


local function engine_num(currentB, currentT) 
  -- If you need more than 100 trains, you could change the 10 upto 16 HOWEVER remember the code is based on colours so
  --   can only work out upto 15*15
  -- We add 1 so that we start the train count at 1 (white, white = 1 not 0)
  return (currentB * 10) + currentT + 1
end

local function nextrain()
  if component.redstone.getBundledInput(sides.bottom, colors.blockinuse) > 0 then       -- Double check we dont let something in
    print("Call in the next train")
    component.routing_track.setDestination("")
    --component.routing_switch.setRoutingTable(defaultRoutingTable)
    
    component.redstone.setBundledOutput(sides.bottom, colors.blockentry, 15000)       -- Entry
    component.redstone.setBundledOutput(sides.bottom, colors.depotexit, 0)
    checktimeout = defaultchecktimeout
  end
end

-- Find an appropriate task
--  currenttask is the current task being done by the engine (nil to indicate no current task)
local function find_task(currenttask)
      -- If the engine is fine doing its currenttask then it can keep doing it
      if currenttask and tasks[currenttask] and tasks[currenttask].current <= tasks[currenttask].required then
        print("keeping", currenttask, tasks[currenttask].current, "/", tasks[currenttask].required)
        return currenttask
      end
			if currenttask then
				-- Code used to just change the destination, but as the train may have a different load we send it back to the depot
				--   and allow the decoupling code to unload + normal code would release a new train
				if tasks[currenttask] then
					tasks[currenttask].current = tasks[currenttask].current - 1
				end
				
				return nil
			end
			
      -- Could just detect the first task that is required and return
      --  but if there are not enough engines available something else may suffer
      --  so we find the task with the least amount of engines
      --  TODO Should we make it percetage based (eg. a task needing 100 engines still takes prioity of a task needing 10)
      local returntask = nil
      local returntaskcount = math.huge
      for k, v in pairs(tasks) do
        print(k, v.current, "of", v.required, " ?>> ", returntaskcount)
        if v.current < v.required and v.current < returntaskcount then
          returntask = k
          returntaskcount = v.current
        end
      end
      
      print("Returning ", returntask)
      if returntask then
        tasks[returntask].current = tasks[returntask].current + 1
      end
      return returntask
end

local function state_check()
  nextstatecheck = computer.uptime() + 5
  
  -- Reset the current counters in case they have got out of sync?
  for k, v in pairs(tasks) do
    tasks[k].current = 0
  end

  local ignorebefore = computer.uptime() - 3600
  for k, v in pairs(engines) do
    -- Ignore any engine that hasnt been seen for a while
    if v.lastseen < ignorebefore then
      print("Havnt seen " .. k .. " for a while, I hope its alright? Maybe we need another train (auto-add disabled)")
    end
--    else
      if v.task and tasks[v.task] then
        tasks[v.task].current = tasks[v.task].current + 1
--      end
    end
  end

  -- Do we have enough active locos? if not release the depot
  --  We only release one train each state check. This could be a slow ramp up
  --  but it shouldnt be required too often
  for k, v in pairs(tasks) do
    if tasks[k].current < tasks[k].required then
      print("Releasing a train from the depot to meet demand")
      component.redstone.setBundledOutput(sides.bottom, colors.depotexit, 15)
--      os.sleep(0.5)
--      component.redstone.setBundledOutput(sides.bottom, colors.depotexit, 0)
      -- Recheck earlier if we need more than 1
      if tasks[k].current + 1 < tasks[k].required then
        nextstatecheck = computer.uptime() + 2
      end
      break;
    end
  end
end

local function savestate()
  local tmpf = io.open("/home/engine.states", "w")
  local tmpi = serialization.serialize({engines = engines, tasks = tasks})
  tmpf:write(tmpi)
  tmpf:close()
end


-- Setup the components
if rsid then
  component.setPrimary("redstone", component.get(rsid))
end
component.modem.open(comms_port)


-- Load previous state
if filesystem.exists("/home/engine.states") then
  local f = io.open("/home/engine.states", "r")
  local d = serialization.unserialize(f:read("*all"))
  if not d.engines then
    -- State of required was never saved previously
    --   and engine_ids may have changed when switching to Computronics
    --   convertiong the file would be as easy as
    -- engines = d
    --   but that would not catch the change in engine ids
    --   for now just give a warning and move on
    oldprint("NOTICE")
    oldprint("NOTICE")
    oldprint("Old engine state format detected, due to component changes current states ignored. Recomend sending all engines back for reassignment")
    oldprint("NOTICE")
    oldprint("NOTICE")
    print("Old engine state format detected, due to component changes current states ignored.")
    print("Recomend forcing all engines back for reassignment")
    computer.beep(1000, 0.1)
    computer.beep(1000, 0.1)
    computer.beep(400, 0.5)
    computer.beep(1000, 0.1)
    computer.beep(1000, 0.1)
    computer.beep(400, 0.5)
    computer.beep(1000, 0.1)
    computer.beep(1000, 0.1)
    computer.beep(400, 0.5)
    os.sleep(5)
  else
    engines = d.engines
    for k, v in pairs(d.tasks) do
      if(tasks[k]) then
        tasks[k].required = d.tasks[k].required
      end
    end
    
    f:close()
    print("Loaded engines")
  end
end
for k, v in pairs(tasks) do
	tasks[k].guiline = 0
end

-- Ok, lets get started
for k, v in pairs(engines) do
  engines[k].lastseen = computer.uptime()
end 

state_check()
nextrain()
term.clear()
while runstate > 0 do
  local e, a1, a2, a3, a4, a5, a6, a7 = event.pull(checktimeout)
  
  if not e then
    -- Its the timeout, we can ignore this
    --  Dont put anything here since we may never get here in a busy depot
  elseif e == "key_down" then
    if a2 == 113 then       -- q exits
      print("Ending program - waiting for current loco to clear")
      runstate = 2
    elseif a2 == 114 then   -- r manually releases an engine
      print("Releasing engine from depot")
      component.redstone.setBundledOutput(sides.bottom, colors.depotexit, 15)
--      os.sleep(0.5)
--      component.redstone.setBundledOutput(sides.bottom, colors.depotexit, 0)
    else
      print("Unknown keypress, r = release, q = quit", a2, a3)
    end
  elseif e == "touch" then
    for k, v in pairs(tasks) do
      if v.guiline == a3 then
         if a2 >= descsize + 13 and a2 <= descsize + 13 + 2 then
             if tasks[k].required > 0 then
               tasks[k].required = tasks[k].required - 1
               savestate()
             end
         end
         if a2 >= descsize + 16 and a2 <= descsize + 16 + 2 then
             if tasks[k].required < 256 then      --- 16 top colours * 16 bottom colours = 256
               tasks[k].required = tasks[k].required + 1
               savestate()
             end
         end
      end
    end
  elseif e == "minecart" then
    -- minecart is the computronics signal for the digital cart detector
    -- a1=address
    -- a2=type
    -- a3=name
    -- a4=primaryColor
    -- a5=secondaryColor
    -- a6=destination
    -- a7=owner
    
    if a2 == "locomotive_steam_solid" or a2 == "locomotive_electric" or a2 == "locomotive_creative" then
      currentT = a4
      currentB = a5
    
      -- TODO Do we use the destination here?
      
      
      if not currentT or not currentB then
        -- We couldnt determine a colour? send it to the depot
        currentT = -1
        currentB = -1
        computer.beep(500, 0.2);
        computer.beep(200, 0.2);
      else
        print("Its #", engine_num(currentB, currentT), currentB .. " bottom", currentT .. " top")
        print("Its #", engine_num(currentB, currentT), colors[colors.rs[currentB]] .. " bottom", colors[colors.rs[currentT]] .. " top")
          
        local engineid = engine_num(currentB, currentT)
        if engines[engineid] then
          print("I have seen this one its doing ", engines[engineid].task)
          local oldtask = engines[engineid].task
          engines[engineid].task = find_task(engines[engineid].task)
          engines[engineid].lastseen = computer.uptime()
          if not engines[engineid].task then
            computer.beep(800, 0.001)
            computer.beep(800, 0.001)
            computer.beep(850, 0.05)
            computer.beep(700, 0.05)
            computer.beep(700, 0.05)
          elseif oldtask == engines[engineid].task then
            computer.beep(800, 0.001)
            computer.beep(800, 0.001)
            computer.beep(850, 0.05)
            computer.beep(900, 0.001)
          else
            computer.beep(800, 0.001)
            computer.beep(800, 0.001)
            computer.beep(850, 0.05)
            computer.beep(700, 0.05)
          end
        else
          print("New engine")
          engines[engineid] = {}
          engines[engineid].lastseen = computer.uptime()
          engines[engineid].task = find_task()
          computer.beep(800, 0.001)
          computer.beep(800, 0.001)
          computer.beep(850, 0.05)
          computer.beep(700, 0.05)
        end
        -- track the carts required for the task (if they dont match we tell the cart to return)
        expected_carts = {}
        if engines[engineid].task and tasks[engines[engineid].task] and tasks[engines[engineid].task].carts then
          for i in string.gmatch(tasks[engines[engineid].task].carts, "%S+") do
            table.insert(expected_carts, "cart_" .. i)
          end
        end
          
        savestate()
          
        -- set the routing ticket and switch
        if engines[engineid].task then
          local newdest = engines[engineid].task
          if tasks[engines[engineid].task].dest then
            newdest = tasks[engines[engineid].task].dest
          end
          component.routing_track.setDestination(newdest)
          
          --component.routing_switch.setRoutingTable({"NOT", "Dest=" .. newdest})      -- Set it to be NOT DEST so if the ticket didnt get set or if a train passed that we didnt detect
          -- set the yard entry to on (if there are carts attached it turns off later)
          component.redstone.setBundledOutput(sides.bottom, colors.enteryard, 15)
          --component.routing_switch.setRoutingTable(defaultRoutingTable)
          if tasks[engines[engineid].task].notify then
            component.modem.send(tasks[engines[engineid].task].notify, rcomms_port, "engineupdate", engineid, engines[engineid].task)
          end
        else
          component.routing_track.setDestination("")
          --component.routing_switch.setRoutingTable(defaultRoutingTable)
          -- TODO If a task WAS assigned we should do a notification if defined to say the engine is no longer assigned
        end
      end
    else
      -- If there are any carts besides the engine, make sure its in the correct configuration
      --   otherwise it needs to be disassabled and a new one created
      --  (if only the engine passes this code wont be called)
      -- TODO If the train is smaller than it should be we should also return to depot
      --   this would need to be done by returning to this code after X seconds of no more carts
      if currentT and currentB then
        -- Theres a cart so we dont want to send to the yard
        --component.routing_switch.setRoutingTable({""})
        component.redstone.setBundledOutput(sides.bottom, colors.enteryard, 0)
          
        local expected = table.remove(expected_carts, 1)
        if expected == a2 then
          print("matched expected", expected, "got", a2)
          computer.beep(400, 0.1)
        else
          print("expected", expected, "got", a2)
          computer.beep(150, 0.1)
          computer.beep(100, 0.2)
          
          -- the moment it fails we dont need to check the rest, send it to the depot
          expected_carts = {}
          component.routing_track.setDestination("")
          -- using -1 as the taskid will mean it will return nil but also do the appropriate state changes
          if engines[engine_num(currentB, currentT)] then
            engines[engine_num(currentB, currentT)].task = find_task(-1)
          end
          currentT = -1
          currentB = -1
        end
      end
    end
    
  elseif e == "redstone_changed" then
    if component.isPrimary(a1) then
      -- If its out control redstone then it will a train entering or exiting
      if component.redstone.getBundledInput(sides.bottom, colors.blockinuse) > 0 then
        -- if runstate is not 1 then we are in exit mode, and waiting for this event so we can change to 0 now
        if runstate == 1 then
          nextrain()
        else
          runstate = 0
        end
      else
        -- print("Inbound train")
        component.redstone.setBundledOutput(sides.bottom, colors.blockentry, 0)       -- Block entry
      end
    else
      -- these two are from the old detection method using loco detectors and redstone
      -- changed to use computronic digital detectors (see earlier event)
      ---- Its the detector, track the train type. We can also assume that if these are fireing
      ----   a loco is on its way in so we increase how often we check
      --if sides[a2] == "top" and a4 > 0 then
      --  -- This indicates the train has poast the detector
      --  --checktimeout = 0.3
      --  if not currentT or not currentB then
      --    -- We couldnt determine a colour? send it to the depot
      --    slot_chest = nil
      --    currentT = -1
      --    currentB = -1
      --    computer.beep(500, 0.2);
      --    computer.beep(200, 0.2);
      --  else
      --    print("Its #", engine_num(currentB, currentT), currentB .. " bottom", currentT .. " top")
      --    print("Its #", engine_num(currentB, currentT), colors[colors.rs[currentB]] .. " bottom", colors[colors.rs[currentT]] .. " top")
      --    
      --    local engineid = engine_num(currentB, currentT)
      --    if engines[engineid] then
      --      print("I have seen this one its doing ", engines[engineid].task)
      --      engines[engineid].task = find_task(engines[engineid].task)
      --      engines[engineid].lastseen = computer.uptime()
      --    else
      --      print("New engine")
      --      engines[engineid] = {}
      --      engines[engineid].lastseen = computer.uptime()
      --      engines[engineid].task = find_task()
      --    end
      --    
      --    local tmpf = io.open("/home/engine.states", "w")
      --    local tmpi = serialization.serialize(engines)
      --    tmpf:write(tmpi)
      --    tmpf:close()
      --    
      --    if engines[engineid].task then
      --      slot_chest = tasks[engines[engineid].task].slot
      --      if tasks[engines[engineid].task].notify then
      --        component.modem.send(tasks[engines[engineid].task].notify, rcomms_port, "engineupdate", engineid, engines[engineid].task)
      --      end
      --    else
      --      slot_chest = nil
      --      -- TODO If a task WAS assigned we should do a notification if defined to say the engine is no longer assigned
      --    end
      --  end
      --elseif sides[a2] == "back" and a3 == 0 then
      --  currentB = rsmax - a4
      --elseif sides[a2] == "front" and a3 == 0 then
      --  currentT = rsmax - a4
      --end
    end
	elseif e == "modem_message" then
		if a5 == "yardrequirements" then
			-- yard requirements is the yard asking what should be made. so we send back the requirements
			local engineid = engine_num(a6, a7)
			if engines[engineid] and engines[engineid].task and tasks[engines[engineid].task] then
				print("Yard requested carts for ", engineid, colors[a6], colors[a7])
				component.modem.send(a2, rcomms_port, "yardbuild", tasks[engines[engineid].task].carts)
			else
				-- Somehow an engine with no task arrived, tell the yard there are no carts so it lets it go again
				print("Yard requested carts for ", engineid, colors[a6], colors[a7], " but no task assigned")
				component.modem.send(a2, rcomms_port, "yardbuild", "")
			end
		elseif a5 == "addtrain" then
      -- add train increases the number of trains assigned to a task
      --    NOTE: We track the inbound address to notify in the future - however we only support one notify address at a time
      --       then when a train is released the requestor will know
      if tasks[a6].required < 256 then      --- 16 top colours * 16 bottom colours = 256
        tasks[a6].required = tasks[a6].required + 1
      end
      tasks[a6].notify = a2
		elseif a5 == "remtrain" then
      -- rem train reduces the number of trains assigned to a task
      --   notify works the same as addtrain -- although a notification may not be sent when we retire a train
      if tasks[a6].required > 0 then
        tasks[a6].required = tasks[a6].required - 1
      end
      tasks[a6].notify = a2
		else
			print("UNKNOWN MODEM MESSAGE", a5, a6, a7)
		end
    -- Do other stuff here
  else
--      print("Unknown ", e, a1, a2, a3, a4, a5, a6, a7)
  end

  -- Below code used a transposor to insert and remove a golden ticket, works in 1.10 doesnt work in 1.12
  --  so now uses an adapter against a routing track to set the golden ticket. This is done when the cart is detected (see the minecart event earlier)
  --  it does mean its not possible to hold the train
  ---- It would be nice if OpenComputers fired an inventoryChanged event
  ----   then we could wait for a longer time. But for now we check on every loop
  ----   for an inventroy in front of the transposer
  --if component.transposer.getInventorySize(side_train) and currentT and currentB then
  --  component.redstone.setBundledOutput(sides.bottom, colors.release, 0)
  --  if slot_chest then
  -- print("slot chest", slot_chest, "slot train", slot_train)
  --    component.transposer.transferItem(side_chest, side_train, slot_train, slot_chest)
  --    --os.sleep(1)
  --    component.transposer.transferItem(side_train, side_chest, slot_chest, slot_train)
  --  else
  --    -- Nothing to do, send to depot
  --    component.redstone.setBundledOutput(sides.bottom, colors.enterdepot, 15)
  --  end
  --  checktimeout = defaultchecktimeout
  --
  --  -- trigger the train to move
  --  component.redstone.setBundledOutput(sides.bottom, colors.release, 15)
  --  currentT = nil
  --  currentB = nil
  --end
  
  if computer.uptime() > nextstatecheck then
    state_check()
  end
  
  draw_gui()
end

-- If we get to the end block entry
component.redstone.setBundledOutput(sides.bottom, colors.blockentry, 0)       -- Block entry
