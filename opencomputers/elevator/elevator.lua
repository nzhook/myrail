--[[ Funky Locomotion Elevator
     Created for the Youtube channel https://youtube.com/user/nzHook 2018
     myRail Episode Showing Usage: https://youtu.be/Fv0cJO-NO2c
     
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
local comp = require("component")
local sides = require("sides")
local colors = require("colors")
local os = require("os")
local event = require("event")
local computer = require("computer")
local term = require("term")
local text = require("text")

-- settings
local rsmax = 256              -- max redstone strength (normally 255)
local sideup = sides.right     -- side of redstone block/card for sending up
local sidedown = sides.left    -- side of redstone block/card for sending down
local sidedisplay = sides.top  -- side the segment display is on
local sidedoors = sides.bottom -- side that triggers the doors

local rsio_reader = "320e453e-fc6c-475c-add0-c16c3aa3a2db"   -- the address of the redstone io for reading
local sidefloor = sides.top     -- side the floor will be read from (note use a redstone io)
local sidecall = sides.front    -- side the call buttons will be read from (note use a redstone io)
local floormax = 16             -- the number of floors (for the GUI) - max 16 colors
-- end settings

local rsreader = comp.proxy(rsio_reader)
-- detect the other redstone device
local rs
for k, v in comp.list("redstone") do
	if k ~= rsio_reader then
		rs = comp.proxy(k)
	end
end

-- Test for if arguments were given
--  if so just goto that floor, otherwise go into loop
local args = {...}
local gotofloor
if args[1] then
	gotofloor = args[1] - 1
end
--print(gotofloor)
--print(colors[gotofloor])

-- Given a number output a signal to the bundled cable on sidedisplay
--  which can be connected into a Project Red segment display
local function segdisplay(num)
  local xcol
  if num == 0 then
        xcol = {[colors.silver] = 255, [colors.cyan] = 255, [colors.purple] = 255, [colors.blue] = 255, [colors.brown] = 255, [colors.green] = 255}
  elseif num == 1 then
        xcol = {[colors.brown] = 255, [colors.green] = 255}
  elseif num == 2 then
        xcol = {[colors.blue] = 255, [colors.brown] = 255, [colors.red] = 255, [colors.cyan] = 255, [colors.silver] = 255}
  elseif num == 3 then
        xcol = {[colors.blue] = 255, [colors.brown] = 255, [colors.red] = 255, [colors.green] = 255, [colors.silver] = 255}
  elseif num == 4 then
        xcol = {[colors.purple] = 255, [colors.red] = 255, [colors.brown] = 255, [colors.green] = 255}
  elseif num == 5 then
        xcol = {[colors.blue] = 255, [colors.purple] = 255, [colors.red] = 255, [colors.green] = 255, [colors.silver] = 255}
  elseif num == 6 then
        xcol = {[colors.blue] = 255, [colors.purple] = 255, [colors.red] = 255, [colors.green] = 255, [colors.silver] = 255, [colors.cyan] = 255}
  elseif num == 7 then
        xcol = {[colors.purple] = 255, [colors.blue] = 255, [colors.brown] = 255, [colors.green] = 255}
  elseif num == 8 then
        xcol = {[colors.silver] = 255, [colors.cyan] = 255, [colors.purple] = 255, [colors.blue] = 255, [colors.brown] = 255, [colors.green] = 255, [colors.red] = 255}
  elseif num == 9 then
        xcol = {[colors.silver] = 255, [colors.purple] = 255, [colors.blue] = 255, [colors.brown] = 255, [colors.green] = 255, [colors.red] = 255}
  end
	if xcol then
		-- Unset the other segments
	  for k, v in pairs(colors) do
		  if(not xcol[v]) then
				xcol[v] = 0
			end
		end
		rs.setBundledOutput(sidedisplay, xcol)
	else
		print("Unknown number", num)
	end
end

-- Grab the first color which is on for a Bundled cable on 'side'
local function whichcolor(side) 
	local levels = rsreader.getBundledInput(side) 
	-- levels will be a table of color > signal, we only care about the first non 0
	for k, v in pairs(levels) do
		if v > 0 then
			return k
		end
	end
end

-- Read and store the current floor based on the active redstone cable
local curfloor
local function readfloor()
			local newfloor = whichcolor(sidefloor)
			if newfloor and curfloor ~= newfloor then
				segdisplay(newfloor + 1)
				curfloor = newfloor
			end
end

-- Open/close the doors, 'open' is the color (floor) to open, all other floors will close. Nil = all closed
local function dodoors(open)
	local tosetopen = {}
	for i = 0, floormax - 1 do
		tosetopen[i] = rsmax
	end
	if open then
		tosetopen[open] = 0
	end

	rs.setBundledOutput(sidedoors, tosetopen)
end

-- Display the GUI for inside the Cab
-- NOTE: Changes here need to be updated inside the touch event code later on
local function dogui()
	local w = 20
	local h = 10
	comp.gpu.setResolution(w, h)
	term.clear()
	print("Floor ", curfloor + 1)
	print()
	print()
	local i
	local line = ""
		for i = 1, floormax do
		line = line .. text.padRight("(" .. i .. ")", 5)
		if i % 4 == 0 then
			print(line)
			line = ""
		end
	end
	term.setCursor(1, h - 1)
	print(text.padLeft("[Open]", (w + 4) / 2))
end



-- Main loop
while true do
	readfloor()
	dogui()

	if not gotofloor then
		while gotofloor == nil do
			local e, a1, a2, a3, a4 = event.pull(60)
			if e == "redstone_changed" then
				local callfloor = whichcolor(sidecall)
				if callfloor then
--					print(callfloor +1, colors[callfloor])

					gotofloor = callfloor
				end
			elseif e == "touch" then
				local w = a2
				local h = a3
				
				if h < 9 then
					-- the location of each button can be determined
					-- but we do need to make sure only floors upto maxfloors
					-- note if you change the GUI you may need to update this calc
					local n = ((20 * (h - 4)) + w) / 5
					gotofloor = math.floor(n)
					if (n - gotofloor) < 0.2 or (n - gotofloor) > 0.9 then
						-- Its the whitespace
						gotofloor = nil
					end
					if gotofloor and (gotofloor > floormax or gotofloor < 0) then
						gotofloor = nil
					end
				else
					-- The open button
					computer.beep(700, 0.001)
					computer.beep(800, 0.01)
					computer.beep(700, 0.001)
					dodoors(curfloor)
					os.sleep(5)
					dodoors()
					
					gotofloor = nil
				end
			end
		end
	end

	computer.beep(500, 0.001)
	computer.beep(800, 0.01)
	computer.beep(600, 0.001)

	-- close the doors
	dodoors()

  -- Change the signals
  -- Note its cheaper to update all the redstone colors at once
  --  so we add them into two tables (one for on and one for off)
	local toseton = {}
	local tosetoff = {}
	for i = 0, floormax - 1 do
		local sig = 0
		if i <= gotofloor then
			sig = rsmax
		end
		toseton[i] = sig
		tosetoff[i] = rsmax - sig
	end

	rs.setBundledOutput(sideup, toseton)
	rs.setBundledOutput(sidedown, tosetoff)


	--print("Starting at floor", curfloor + 1)
	if curfloor ~= gotofloor then
    -- Now we wait until we reach the new floor
		local e = "aa"
		while curfloor ~= gotofloor and e do
			e = event.pull(10, "redstone_changed")
			readfloor()
	--		print("Now at floor", curfloor + 1)
		end

	--	print("Arrived at floor", gotofloor + 1)

		-- give the elevator enough time to arrive
		dogui()
		os.sleep(2)
		dogui()
	end

  -- The Ding! Im here noise
	computer.beep(800, 0.001)
	computer.beep(800, 0.01)
	computer.beep(800, 0.001)

	dogui()
	dodoors(curfloor)
	
	os.sleep(10)

	dodoors()
	
	gotofloor = nil
end
