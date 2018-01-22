--[[ Tablet POI location training tool
     Created for the Youtube channel https://youtube.com/user/nzHook 2018
     myRail Episode Showing Usage: https://www.youtube.com/watch?v=uimspQP-1S4
     NOTE: Requires GPS position and master server to receieve. see railmap.lua
     
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

-- @todo
-- - Auto turn off after X amount of time unused to save energy
local event  = require("event")
local component = require("component")
local computer = require("computer")        -- Only used for uptime()

local tunnel_port = 1234

local gpsfile = io.open("/.gps_start.pos", "r")
local gpsX = gpsfile:read()
local gpsZ = gpsfile:read()
gpsfile:close()

while true do
  local a, b, c, e, f, g, h, i, j= event.pull(10)
  if a == "modem_message" and h == "MSG"  then
    -- Let the master talk to us (eg. I ack that you selected that block at ..., or I got another event you might want to know about)
    print("[master] ", i)
    component.computer.beep(100, 0.1)
  elseif a =="tablet_use" then
    -- When a block is selected (hold down shift and right click for more than 1 second)
    --  ask for a name/label and send the position back to the master
    print("Please provide the label for position: X: " .. (b.posX + gpsX), "Z:" .. (b.posZ + gpsZ))
    component.computer.beep(800, 0.2)
    component.computer.beep(850, 0.3)
		local label = io.read()
    component.tunnel.send(tunnel_port, "POI", label, (b.posX + gpsX), b.posY, (b.posZ + gpsZ))
  elseif a == "key_down" then
    -- The way out is to press the 'any' key
    os.exit()
--  else
--    print(a)
  end

end
