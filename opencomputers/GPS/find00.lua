--[[ GPS location finding tool for an OpenComputers navigation upgrade
     Created for the Youtube channel https://youtube.com/user/nzHook 2018
     NOTE: Any OpenComputers device using this (I recomend a tablet) will need a Navigation Upgrade
     
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

-- Load the libs
local component = require("component")
local os = require("os")
local computer = component.computer
local io = require("io")

-- Main function which beeps until the X or Z position is reached
-- dir string  To be disabled (eg. 'X', 'Z')
-- co int The array index returned from the getPosition to check against (X = 1, Y = 2, Z = 3)
-- run int The run number (changes the pitch of the beep)
local function getpos(dir, co, run)
  local pos = -1
  local past = 1
  local nextbeep = 0
  -- Loop until we get to 0
  while(math.abs(pos) >= 1) do
    -- This is the navigation upgrades purpose, it returns an array containing X, Y, Z
    local posa = {component.navigation.getPosition()}
    pos = posa[co]
    
    if past >= nextbeep then
      print("Move " .. dir .. " " .. pos)
      if math.abs(pos) >= 1 then
        -- Make a beep based on how far the target is away, max frequency change is 500
        computer.beep(math.max(500 - (math.abs(pos) * 10), 100) * run)
      end
      past = 0
    end
    -- Always sleep for 0.1, as we need to keep updating for how closer the player is
    os.sleep(0.1)
    past = past + 0.5
    -- The next beep increases the closer the player gets. Maximum 4 seconds
    nextbeep = math.min((math.abs(pos) / 20), 4)
  end
end


-- Find X and Y with some notifications
getpos("X", 1, 1)
computer.beep(200, 0.05)
computer.beep(300, 0.05)
computer.beep(200, 0.05)
getpos("Z", 3, 2)
computer.beep(500, 0.05)
computer.beep(400, 0.05)
computer.beep(700, 0.09)
computer.beep(800, 0.09)
-- @todo Add a double check for X and Y to make sure we didnt change course slightly

-- Ok we are here, ask where the player is (or at least what they wanthis to be)
--   They could use 0,0 if they want but this script wouldnt be useful
print("You have reached 0,0 of the map")
print("Please enter the X position")
local startx = io.read()
print("Please enter the Z position")
local startz = io.read()

-- Save it to disk for later use
local f = io.open("/.gps_start.pos", "w")
f:write(startx, "\n", startz)
f:close()
print("GPS position stored")
