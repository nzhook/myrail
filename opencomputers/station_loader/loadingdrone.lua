--[[ Drone Train Loader - Drone EEPROM (not minified)
     Created for the Youtube channel https://youtube.com/user/nzHook 2018
     myRail Episode Showing Usage: https://youtu.be/b_ZOIMPXXtY

    NOTE: This code needs to be smaller to fit onto the EEPROM
          Remove comments and excess whitespace

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

-- Config
local gpsscansize = 40			   -- How far do we scan for waypoints - higher values use more power
local commsport = 3213
local bottomSide = 0				   -- The side we interact with the chests and minecarts from (we fly above them)
local platformdirection = 1	   -- The direction to travel to find the next cart (1 = x, 3 = z)
local platformdirectionadd = 1 -- The amount to increase in that direction (-1 or 1)

-- End Config
-- Check Devices
local drone = component.proxy(component.list("drone")())
if(not drone) then error("Not a drone") end

local navigation = component.proxy(component.list("navigation")())
if(not navigation) then error("Missing a navigation upgrade") end

local modem = component.proxy(component.list("modem")())
if(not modem) then error("Missing a modem/wireless card") end

local inv = component.proxy(component.list("inventory_controller")())
if(not inv) then error("Missing an inventory_controller upgrade") end

-- defines
local myx,myy,myz  = 0,0,0

-- Only used for testing. Requires modified net-flash code
local function print(txt) 
-- modem.broadcast(1370, "net-eeprom", "debug", txt)
end
local function debugmsg(e)
--	for k,v in pairs(e) do print(k .. " = " .. v) end
end

local function split(input)
	local t={} ; i=1
	for str in string.gmatch(input, "([^,]+)") do
					t[i] = str
					i = i + 1
	end 
	return t
end

local function move(newpos, a, addy)
	local newpos = split(newpos)
	local x = newpos[1]
	local y = newpos[2] + addy
	local z = newpos[3]
	
  drone.setAcceleration(a)
  local dx = x - myx
  local dy = y - myy
  local dz = z - myz
  
  drone.move(dx, dy, dz)
  while drone.getOffset() > 0.7 or drone.getVelocity() > 0.7 do
    computer.pullSignal(0.2)
  end
  myx, myy, myz = x, y, z
end

local function idle() 
	if computer.energy() < 1000 then
		print("Charging " .. computer.energy() .. " < 1000")
		modem.broadcast(commsport, "charging")
		-- If we are low on power return to the charger and charge
		move(chargerpos, 1, 5)
		move(chargerpos, 1, 1)
		while computer.energy() < computer.maxEnergy() - 1000 do
			computer.pullSignal(1)
		end
	end
	
	-- Send the idle signal
	modem.broadcast(commsport, "idle", drone.inventorySize())
end


-- Startup
print("Starting up")
modem.open(commsport)
modem.broadcast(commsport, "boot", drone.inventorySize())

myx,myy,myz = navigation.getPosition()
print("My POS " .. myx .. "," .. myy .. ","  .. myz)

-- We need to find the charger and the storage chest
--  TODO should the storage be sent in the fill message as currently we could only handle one storage
local waps = navigation.findWaypoints(gpsscansize)
local storagepos
local chargerpos 
while not storagepos and not chargerpos do
	for k = 1, waps.n do
		if waps[k].label == "pickup" then
			storagepos = (myx + waps[k].position[1]) .. "," .. (myy + waps[k].position[2]) .. ","  .. (myz + waps[k].position[3])
		elseif waps[k].label == "charger" then
			chargerpos = (myx + waps[k].position[1]) .. "," .. (myy + waps[k].position[2]) .. ","  .. (myz + waps[k].position[3])
		end
	end

	if not storagepos then
		print("No waypoint labeled 'pickup'")
		drone.setLightColor(0xff0000)
		computer.beep(500, 0.3)
		computer.beep(300, 0.5)
		computer.pullSignal(5, "squiggles")
	end
	if not chargerpos then
		print("No waypoint labeled 'charger'")
		drone.setLightColor(0xff0000)
		computer.beep(500, 0.3)
		computer.beep(300, 0.5)
		computer.pullSignal(5, "squiggles")
	end
end

print("Moving to Charger at " .. chargerpos)
move(chargerpos, 20, 1)

-- Loop
print("In loop")
idle()
while true do
	local e = {computer.pullSignal(5)}

	if not e[1] then
		idle()
	elseif e[7] == "fill" then		
		-- Make things pretty, inbound commands will always contain a colour to use
		--    (lets call that a protocol requirement :P )
		drone.setLightColor(e[6])
		
		print("Filling to " .. e[8])
		move(storagepos, 10, 5)
		move(storagepos, 10, 1)
		-- transfer the slots into the inventroy
		for k, v in pairs(split(e[9])) do
			print("loading from slot " .. v)
			inv.suckFromSlot(bottomSide, tonumber(v), 256)
		end
		
		-- move to platform
		newpos = e[8]
		move(newpos, 10, 5)
		move(newpos, 10, 2)
		
		-- unload our internal slots into available carts
		--   the check for inventory is inside the loop to avoid code duplication
		for s = 1, drone.inventorySize() do
			while inv.getInventorySize(bottomSide) do
				drone.select(s)
				if drone.count() == 0 or drone.drop(bottomSide) then
					print("item dropped")
					break
				else
					-- Move to the next available cart
					local tmppos = split(newpos)
					tmppos[platformdirection] = tmppos[platformdirection] + platformdirectionadd
					newpos = tmppos[1] .. "," .. tmppos[2] .. "," .. tmppos[3]
					move(newpos, 10, 2)
				end
			end
			if not inv.getInventorySize(bottomSide) then
				-- If there is no longer an inventroiy under us then tell the director
				--   the train is full (it might not be a train, but it wont hurt)
				modem.broadcast(commsport, "filled")
				-- we need to unload whats left now, so return back to the storage and use the same unload code
				--   but we start from the current slot
				move(storagepos, 10, 5)
				move(storagepos, 10, 1)
				drone.drop(bottomSide)
			end
		end
		idle()
	elseif e[7] == "findWaypoints" then
		-- Make things pretty, inbound commands will always contain a colour to use
		--    (lets call that a protocol requirement :P )
		drone.setLightColor(e[6])
		
		print("waypoint scan requested")
		myx,myy,myz = navigation.getPosition()
		local waps = navigation.findWaypoints(gpsscansize)
		for k = 1, waps.n do
			modem.send(e[3], commsport, "waypoint", waps[k].redstone, (myx + waps[k].position[1]) .. "," .. (myy + waps[k].position[2]) .. "," .. (myz + waps[k].position[3]), waps[k].label)
		end
		idle()
	else
--		print("event " .. e[1] .. " unhandled")
--		debugmsg(e)
	end
end
