--[[ Drone assisted Robot Quarry - Robot
     Created for the Youtube channel https://youtube.com/user/nzHook 2018
     myRail Episode Showing Usage: https://youtu.be/W9s4uPspkE0
     
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
local robot = require("robot")
local computer = require("computer")
local modem = component.modem
local inv = component.inventory_controller
local navigation = component.navigation

-- TODO:
--   refuel
--   return home?

local size = 60 -- best with even numbers
--size = 16     -- This was the small size used in the episode
local segmentheight = 4
local bottomheight = 10
local topheight = 64				-- best teired result from 64
local msgport = 1271

if not component.isAvailable("robot") then
  print("This is the robot program and I dont feel like I am one!")
  os.exit()
end

if not component.isAvailable("navigation") then
  print("To communicate my location with my little monkeys I require a navigation upgrade")
  os.exit()
end

if not component.isAvailable("inventory_controller") then
  print("I need a inventory controller please")
  os.exit()
end

if not component.isAvailable("modem") then
  print("To communicate with my little monkeys I require a wireless modem")
  os.exit()
end

local usingtool
local started = {}
local function message(msg)
	local x,y,z = navigation.getPosition()

	local s
	local inuse = 0
	for s = 1, robot.inventorySize() do
		if(robot.count(s) > 0) then
			inuse = inuse + 1
		end
	end

	modem.broadcast(msgport, 'circledig', msg, x .. "," .. y .. "," .. z, started, size, robot.durability() or 0, inuse, robot.inventorySize())
end

local function newtool()
	-- find a new tool that matches the one we had eqipped
	--  warning: this function will only ever finish when the tool is found
	local s
	local found
	while not found do
		for s = 1, robot.inventorySize() do
			local citem = inv.getStackInInternalSlot(s)
			if citem ~= nil and citem.name == usingtool.name then
				found = s
				break
			end
		end
		if not found then
			robot.select(1)
			-- check the eqipment slot in case it dropped there
			inv.equip()
			local citem = inv.getStackInInternalSlot(s)
			if citem ~= nil and citem.name == usingtool.name then
				found = 1
			else
				inv.equip()
			end
		end
		if not found then
			print("can not find a replacement tool " .. usingtool.name)
			-- todo should just wait and loop until one appears
			message("tool")
			os.sleep(10)
			-- because the drone cant insert into the robot inventroy we
			-- suck anything up that may have fallen (hoping it was a pick
			-- a drone dropped recently)
			robot.suckUp()
		end
	end
	robot.select(found)
	inv.equip()
	robot.select(1)
end
							
local function dounload()
	robot.select(robot.inventorySize())
	inv.equip()
	local lastsent = 10
	while robot.count(robot.inventorySize() - 1) > 0 do
		lastsent = lastsent + 1
		-- resend the request every 10 * 10 seconds
		if lastsent >= 10 then
			lastsent = 0
			print("Inventory full, awaiting drone pick up")
			message("unload")
		end
		os.sleep(10)
	end
	-- swap the tool back
	robot.select(robot.inventorySize())
	inv.equip()
	robot.select(1)
end


local function domove(noSwingDown)
			-- try to move forward, if we cant try swinging the tool
			--  if swinging fails we may need some help
			--  if swiging didnt fail try moving forward
			--  if it doesnt work keep swiging (will catch sand/gravel)
			while robot.detect() do
				if not robot.swing() then
					-- if the swing failed, check if uts because a block is not there
					if robot.durability() == nil or robot.durability() == 0 then
						newtool() 
					else
						print("forward failed and same with a swing")
						message("immovable")
						computer.beep(1000)
						os.sleep(10)
					end
				else
					-- If the last slot is full, call for an unload and wait
					--   drones and robots cant talk? so when a drone
					--   sucks an item it takes the tool first, so to avoid
					--   that we switch the tool for the last slot and switch it back after
					--- FIXME: If OC ever fixes this this code should be rewritten
					if robot.count(robot.inventorySize()) > 0 then
						dounload()
					end
				end
			end
			-- todo check power here?
			robot.forward()

			if not noSwingDown then
				-- Swing down, not really an issue if this fails
				--   todo: should detect a broken pick here too
				robot.swingDown()
			end
end
	

local curx = 0

local from = curx
local to = size
local dir = 1
local dirmod = 1
local facing = 0
local stairpos = 2

local minheight = topheight - (((size - segmentheight) / 2) * (segmentheight/2))
if bottomheight < minheight then
	bottomheight = minheight
	print("Can not reach requested bottom using this size. Only going to " .. bottomheight)
end

-- swap the current tool into slot 1 so we can see what it is
robot.select(1)
inv.equip()
usingtool = inv.getStackInInternalSlot(1)
inv.equip()   -- put it back
if usingtool == nil then
		print("One appears to be without a mining tool.")
		os.exit()
end

local x, y, z = navigation.getPosition()
started = x .. "," .. y .. "," .. z .. "," .. size

robot.setLightColor(0x00ff00)
message("start " .. usingtool.name)

-- need to do the first down block as our func swingsdown after moving
for y = topheight, bottomheight, -2 do
	facing = 0
	robot.swingDown()
	for m2 = 1, (size + 2) * 2 do
		message("status")
		for m1 = from, to, dir do
			domove()
		end

		robot.turnLeft()
		
		facing = facing + 1
		if m2 +1 < (size + 2) * 2 then
			if facing > 2 then
				-- on every circle we strip one off each side until we end up in the middle
				to = to - dirmod
			end
			if facing > 3 then
				if dirmod > 0 then
					domove()
				else
					robot.turnRight()
					robot.turnRight()
					domove()
					robot.turnRight()
					robot.turnRight()
				end
				facing = 0
			end
		end
	end
	-- we need to change the spiral direction (outter > middle then middle > outer)
	--  but we also build in the stairs here too
	if y + 4 >= bottomheight then
		if dirmod == 1 then
				dirmod = -1
				robot.down()
				robot.swingDown()
				robot.down()
		else
				dirmod = 1
				
				-- This is the outside edge so build the stairs here
				robot.setLightColor(0xffff00)
				for m1 = 0, stairpos do
						-- shouldnt need to dig anything but just in case
						domove()
				end
				-- turn into the wall and start the stairs
				robot.turnRight()
				domove(true)
				stairpos = stairpos + 1
				robot.turnLeft()
				
				-- do the next 2 here as well
				domove()
				domove()
				stairpos = stairpos + 1
				robot.down()
				robot.swingDown()
				robot.up()
				stairpos = stairpos + 1
				
				for m1 = from, to - stairpos, dir do
					domove()
					robot.down()
					robot.swingDown()
					robot.down()
					robot.swingDown()
					robot.up()
					robot.up()				
				end
				-- move back out
				robot.turnLeft()
				domove()
				robot.turnLeft()
				robot.down()
				robot.swingDown()
				robot.down()
				for m1 = from, to, dir do
					domove()
				end
				robot.turnLeft()
				robot.turnLeft()
				robot.setLightColor(0x00ff00)
				
				if stairpos + segmentheight > (size-4)-2 then
					stairpos = 2
					if stairpos + segmentheight > (size-4) then
						stairpos = 0
					end
				end
				
				-- if we need to recharge, wait a little while
				if computer.energy()  < 5000 then
					robot.setLightColor(0x0000ff)
					print("LOOOWWWW PPPPOOOWWWEEEEERRRRR!  Sleeping")
					while computer.engery() < computer.maxEngery() - 1000 do
						os.sleep(10)
					end
					print("I feel better")
					robot.setLightColor(0x00ff00)
				end
		end	
	end
	-- for every 4 blocks down we go 2 in (on 2 sides)
	if y % segmentheight == 0 then
			size = size - 4
			if to > size then
				to = size
			end			
	end
end
-- Request an unload
--  maybe we should return before requesting (less distance to travel)
message("unload")
dounload()

-- todo: return  to start?
