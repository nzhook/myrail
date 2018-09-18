--[[ Drone Train Loader - Director
     Created for the Youtube channel https://youtube.com/user/nzHook 2018
     myRail Episode Showing Usage: https://youtu.be/b_ZOIMPXXtY
     
     NOTE: Requires Drone to be running to scan for waypoints
     
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
local sides = require("sides")
local component = require("component")
local os = require("os")
local colors = require("colors")
local computer = require("computer")
local rs = component.redstone
local modem = component.modem
local event = require("event")


-- Max number of items that a train will take (for calculating current usage)
local maxpertrain = 64 * 27

-- Port for talking with drones
local commsport = 3213

-- The side to write the redstone signals to (cannot be the same as the detector)
local redstoneside = sides.bottom

-- These are the part we cant detect :(

-- The ID for the transposer to read items from
-- You can use an analyser to get IDs - Hover over the ID in chat to copy to clipboard
-- @TODO Should assume all connected chests are storage and just ignore Golden Tickets
local chesttransposer = "31858c1b-df95-467c-97a9-6bb340aacb94"
local chestside = sides.top

--  The transposer ids and sides for each platform
--  index is the platform, value is transposerid, side
--   The side the chests we take the tickets from are always on
--  @todo We could detect them by moving items into chests above and have a redstone 
--    for the number of items?
local ticketside = sides.left
local transposersides = {
  {"7ff55733-5835-46b2-bda7-8474bd168984", sides.back},
  {"7ff55733-5835-46b2-bda7-8474bd168984", sides.front},
  {"95f92840-166e-47b9-8c78-a9c61cbff35d", sides.back},
  {"95f92840-166e-47b9-8c78-a9c61cbff35d", sides.front},
}
local trainticketslot = 8

-- tasks:
--   items is an array of lua pattern (matched with string.find) which we will load into a train
--     for that task
--   name is for us humans only
--   slot is the position in the ticket chest(s) for that destination (sharing slot numbers will use the same destination
--        but the train would be dedicated to the given task (eg. cobble in one train and dirt in another)
--   weight gives a task more chance to be used (eg. you could give diamonds a weight of 
--        1000 for it to pick diamonds for loading often -- this is a multipler, so 
--           2,000 cobble at 1 would still be more important than 1 diamond at 1,000)
local tasks = {
		{name = "gold", 	slot = 1, weight = 1,   items = {"minecraft:gold_ore:.*"}},
		{name = "iron", 	slot = 2, weight = 1,   items = {"minecraft:iron_ore:.*"}},
		{name = "cobble", slot = 3, weight = 0.1, items = {"minecraft:cobblestone:.*"}},
		{name = "*", 			slot = 4, weight = 0.3, items = {".*"}},
}

-- Nothing under here needs to be configured

-- Drone colours, drones are coloured by the number of commands we have sent
--   (in order words the colour of the drone means nothing but rainbows)
local drone_colors = {
	0xC11B17, 0xF87A17, 0xFFFF00, 0x00FF00, 0x2B60DE,0x893BFF,
	0xF63817, 0xE78E17, 0xFFFC17, 0x5EFB6E, 0x1531EC, 0x8E35EF
}
local cmdno = 0

-- Whats stored in the chests
local items = {}
-- Each colour wire should link to a platform at the waypoint and the detector track
--  we use the redstone to determine the waypoint for the drone and where the train is
--  HOWEVER we only check at startup to save energy
local platforms = {}
local platformcount = 0
local lastplatform = 0
local drones = {}

-- Statics for making code a little less numbery
local evtType = 1
local evtRemote = 3
local evtCMD = 6
local evtInvSize = 7
local evtPlatform = 7
local evtPlatformPOS = 8
local evtPlatformID = 9
local evtRedstoneSide = 3
local evtRedstoneValue = 5

local function debugmsg(e)
	for k,v in pairs(e) do print(k, " = ", v) end
end

-- function to read contents of chests
local function readitems()
	print("Reading items...")
  items = {}
	local size = component.invoke(chesttransposer, "getInventorySize", chestside)
  for s = 1, size do
    -- determine task from item
		local itm = component.invoke(chesttransposer, "getStackInSlot", chestside, s)
		if itm then
			local itmname = itm.name .. ":" .. itm.damage
			local usetask = nil
			for t = 1, #tasks do			-- we need to do this in order so .* should come last
				for m, searchstr in pairs(tasks[t].items) do
					if string.find(itmname, searchstr) then
						usetask = t
						break
					end
				end
				if usetask then
					break
				end
			end
			if usetask then
				if not items[usetask]  then
					items[usetask] = {total = 0, slots = {}}
				end
				items[usetask].total = items[usetask].total + itm.size
				table.insert(items[usetask].slots, s)
			else
				print("WARNING: No task matched " .. itmname .. " - items ignored (maybe you need a .* task)")
			end
--			print(itmname .. "=" .. itm.size .. " == " .. usetask)
		end
  end
	for k, v in pairs(items) do
			print(tasks[k].name .. " (" .. k .. ")= " .. v.total .. " (x" .. tasks[k].weight .. " = " .. (v.total * tasks[k].weight) .. ")")
	end
end

-- function to setup the platform waypoints
--  we cant have a navigation upgrade so we
--  use an idle drone to do tell us our
--  results
local function setupplatforms()
	local platformids = {}			-- because a waypoint label is not as large as an id :(
  -- firstly make sure they are all off
  local color = 0
	if false then
	-- To ensure there are no trains when we start, set everything to redstone 15
	print("Clearing platforms, please wait")
  for color = 0, 15 do
    rs.setBundledOutput(redstoneside, color, 255)
  end
	os.sleep(1)
	-- Turn redstone off
  for color = 0, 15 do
    rs.setBundledOutput(redstoneside, color, 0)
  end
	end
	
  platforms = {}
  platformcount = 0
  -- now so we can identify each we set the waypoint's label to the
  --  platform number as well as set a redstone signal to make the color
  --  this way we can quickly identify each platform in the scan results
	--  REMINDER: The redstone signal MAY NOT match the platform numbers yet
  for k,v in component.list("waypoint") do
		local cname = component.invoke(k, "getLabel")
		if cname == "charger" or cname == "pickup" then
			-- Ignore any of the specials that maybe connected
		else
			platformcount = platformcount + 1
			-- TODO: is there a need to support more than 15 platforms?
			rs.setBundledOutput(redstoneside, (platformcount-1), platformcount * 16)
			-- print(k .. " (" .. v .. ") " .. " set to " .. platformcount)
			component.invoke(k, "setLabel", "platform" .. platformcount)
			platformids["platform" .. platformcount] = k
		end
  end

  -- wait for an idle drone to check in
  -- then ask it to do a scan for us
  print("Waiting for an Idle drone - if none have been setup please do this now")
  local platformsremain = platformcount
  while platformsremain > 0 do
		
     local e = {event.pull(10, "modem_message")}
     if e then
			if e[evtType] == "modem_message" then
        if e[evtCMD] == "idle" then    -- not a major if we ask multiple 
            print(e[evtRemote] .. " is idle, requesting waypoint scan")
            modem.send(e[evtRemote], commsport, 0x000000, "findWaypoints")
        elseif e[evtCMD] == "waypoint" then  -- each waypoint comes in a different message
				 if e[evtPlatform] > platformcount or e[evtPlatform] < 1 then
					local cname = "?"
					if colors[e[evtPlatform] - 1] then
						cname = colors[e[evtPlatform] - 1]
					end
           print("Waypoint for platform " .. e[evtPlatform] .. " (" .. cname .. ") at {" .. e[evtPlatformPOS]          .. " ignored as unknown redstone signal")
					computer.beep(400, 0.2) 
					computer.beep(300, 0.5) 
				 elseif not platforms[e[evtPlatform]] and platformids[e[evtPlatformID]] then
           platformsremain = platformsremain - 1
           platforms[e[evtPlatform]] = {
              position = e[evtPlatformPOS],
              currenttask = nil,
           }
					 component.invoke(platformids[e[evtPlatformID]], "setLabel", "Platform " .. e[evtPlatform])
           -- dont need the redstone on now
           rs.setBundledOutput(redstoneside, (e[evtPlatform] - 1), 0)
           print("Platform " .. e[evtPlatform] .. " (" .. colors[e[evtPlatform] - 1] .. ") located at {" .. platforms[e[evtPlatform]].position .. "} " .. platformsremain .. " remain")
					else
						print("Unhandled modem message " .. e[evtType] .. " - " .. e[evtCMD])
						debugmsg(e)
					end
				else
						print("Unhandled event " .. e[evtType])
						debugmsg(e)
				end
			end
     end
  end
  print("All platforms found")
end

-- Test devices
if not component.invoke(chesttransposer, "getInventorySize", chestside) then
		print("chesttransposer (" .. chesttransposer .. ") does not return an inventory on " .. sides[chestside] .. " side")
		os.exit()
end



--
-- Startup
--
-- drain the event queue (for if we offline)
local e = 1
print("Clearing event queue")
while event.pull(1) do
	--
end

modem.open(commsport)
setupplatforms()
-- we read the items here as its faster, it may mean
--  the numbers are higher by the time the first train
--  arrives but it shouldnt have too high of an impact
readitems()

-- drain the event queue (the redstone changes we made)
while event.pull(1) do
	--
end
print(" --- Here we go ----")

-- todo: should we bail at anypoint?
while true do
  local e = {event.pull(60)}
	if not e or not e[evtType] then
    -- yeild - maybe we could rescan items or platforms?
  elseif e[evtType] == "redstone_changed" then -- Train should trigger a detector when pulling into station
		if e[evtRedstoneValue] == 0 or e[evtRedstoneSide] == redstoneside then
			-- train has left the block, we dont need to do any magic here really
			--  or its the side we output redstone to
		else
			debugmsg(e)
			-- you cant get the colours from the event so poll now
			local bcol = rs.getBundledInput(e[evtRedstoneSide])
			local col
			-- Bug in OC means we have to work out which colour changed :( (its not passed by the event)
			for c = 0, 15 do
					if bcol[c] == e[evtRedstoneValue] then			
						col = c
						break
					end
			end
			if col then
				print("Train arriving in platform " .. (col+1) .. " (" .. colors[col] .. ")")
				
				-- Find the task with the most required work
				local NEXTTASK = nil
				local NEXTVAL = 0
				for ntask, nvalue in pairs(items) do
					if nvalue.total * tasks[ntask].weight > NEXTVAL then
						NEXTVAL = nvalue.total * tasks[ntask].weight
						NEXTTASK = ntask
					end
				end
				if NEXTTASK then			-- TODO if this is nil that train will just sit there forever, should flag for a check later
					print("Assigning task " .. tasks[NEXTTASK].name .. " (" .. NEXTTASK .. ") to that platform")

					items[NEXTTASK].total = items[NEXTTASK].total - maxpertrain
					-- assign ticket for task to loco in platform col
					-- TODO instruct each available drone to fill train - currently we let the idle cmd do it
					platforms[col + 1].currenttask = NEXTTASK
				end
			end
		end
  elseif e[evtType] == "modem_message" then
		--	debugmsg(e)
    -- drone responding
    if e[evtCMD] == "idle" then
        drones[e[evtRemote]] = nil
        -- scan for another platform that we could help load
        local tested = 0
        while tested < platformcount do
          tested = tested + 1
					lastplatform = lastplatform - 1			-- easy to read modula on the number of platforms but starting at 1
          lastplatform = ((lastplatform + 1) % platformcount)
					lastplatform = lastplatform + 1
          if platforms[lastplatform] and platforms[lastplatform].currenttask then
            drones[e[evtRemote]] = lastplatform
						
						local fromslots = ""
						if items[platforms[lastplatform].currenttask] and items[platforms[lastplatform].currenttask].slots then
							for i = 1, e[evtInvSize] do
								local nextslot = table.remove(items[platforms[lastplatform].currenttask].slots)
								if nextslot then
									fromslots = fromslots .. "," .. nextslot
								end
							end
						end
						-- If no slots were returned, rescan the items
						if fromslots == "" then
----- @todo RE-ENABLE ME
-----								readitems()
								-- this drone gets to relax for this platform
						else
							print("Drone " .. e[evtRemote] .. " is idle, assign platform " .. lastplatform .. " (task " .. platforms[lastplatform].currenttask .. ")")
							cmdno = (cmdno + 1) % (#drone_colors-1)
							modem.send(e[evtRemote], commsport, drone_colors[cmdno + 1], "fill", platforms[lastplatform].position, fromslots)
							 break
						end
					else
		--				print("Platform " .. lastplatform .. " is idle")
					end
        end
    elseif e[evtCMD] == "filled" then  -- train is full
        -- if this is the last drone reporting for the platform
        --   release the train the drone was working on
        local dronesplatform = drones[e[evtRemote]]
				print("Drone " .. e[evtRemote] .. " reports platform ", dronesplatform, " is complete")
				if dronesplatform then
					drones[e[evtRemote]] = nil
					for k, i in pairs(drones) do
						if i == dronesplatform then
							 dronesplatform = nil
							 break
						end
					end
				end
        -- we didnt find another drone on this platform, release train
        if dronesplatform then
					print("No more drones to report in for platform " .. dronesplatform .. ", sending train on its way")
					-- Set the new destination
					component.invoke(transposersides[dronesplatform][1], "transferItem", ticketside, transposersides[dronesplatform][2], trainticketslot, tasks[platforms[dronesplatform].currenttask].slot)
					--os.sleep(1)
					component.invoke(transposersides[dronesplatform][1], "transferItem", transposersides[dronesplatform][2], ticketside, tasks[platforms[dronesplatform].currenttask].slot, trainticketslot)
					
					platforms[dronesplatform].currenttask = nil
		
          rs.setBundledOutput(redstoneside, dronesplatform - 1, 255)
          os.sleep(0.1)
          rs.setBundledOutput(redstoneside, dronesplatform - 1, 0)
        end
		else
			print("Unhandled modem message")
			debugmsg(e)
    end
  else
		print("Unhandled event")
		debugmsg(e)
  end
end
