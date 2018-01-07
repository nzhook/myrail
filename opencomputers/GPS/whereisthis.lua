--[[ GPS location finding tool for an OpenComputers navigation upgrade
     Created for the Youtube channel https://youtube.com/user/nzHook 2018
     
     NOTE: This will only work with a Tablet with a navigation upgrade installed and 
     after find00.lua has run
     
     To use: Place the green cursor over a block then sneak and hold right click for 
     over 1 second  (less than will reset the tablet) release right click and then open tablet
     
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
local event  = require("event")

-- Load the GPS details created by find00.lua
-- @todo Should check for the file first, also make sure a nav upgrade is installed?
local gpsfile = io.open("/.gps_start.pos", "r")
local gpsX = gpsfile:read()
local gpsZ = gpsfile:read()
gpsfile:close()

-- This is for testing, so loop over 10 events (click, touch....) before exiting
for i = 1,10 do
  local a, b, c, e, f = event.pull()
  -- The sneak right click produces the tablet_use signal which has a second argument containing a table
  --   with the data we need in it
  if a =="tablet_use" then
    print("block X: " .. (b.posX + gpsX) .. ", Z:" .. (b.posZ + gpsZ))
    
-- Debugging to show what the tablet returned (changes depending on the upgrades installed - Navigation will give you posX, posY...)
--    for aa, ab in pairs(b) do
--      print(aa, ab)
--    end
  end
end
