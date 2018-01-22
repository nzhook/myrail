--[[ Tablet location training tool
     Created for the Youtube channel https://youtube.com/user/nzHook 2018
     myRail Episode Showing Usage: https://www.youtube.com/watch?v=uimspQP-1S4
     NOTE: Requires GPS position and master server to receieve. see railmap.lua or netrelaytest.lua
     
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
-- - Add a GUI that allows selecting the controller to identify
-- - Auto turn off after X amount of time unused to save energy
local event  = require("event")
local component = require("component")
local computer = require("computer")        -- Only used for uptime()

local tunnel_port = 1234

local looking_for = nil
local lastuptime = 0

local gpsfile = io.open("/.gps_start.pos", "r")
local gpsX = gpsfile:read()
local gpsZ = gpsfile:read()
gpsfile:close()

while true do
  local a, b, c, e, f, g, h, i, j= event.pull(10)
  if a == "modem_message" and h == "IDENT" then
    -- NOTE: Having a check to make sure we are not already looking for seems to break here :(
    --   so after a reboot this may get a little busy, you should wait for it to settle
    looking_for = i
    lastuptime = 0        -- so we go into the ping condition
    
    -- we cant do the magic, you are getting closer beep, so just an alert at the start will have to do
    --  TODO: We possibly can if we used wireless cards instead, although that adds a different headache
    component.computer.beep(700, 0.2)
    component.computer.beep(800, 0.2)
    component.computer.beep(700, 0.2)
  elseif a == "modem_message" and h == "MSG"  then
    -- Let the master talk to us (eg. I ack that you selected that block at ..., or I got another event you might want to know about)
    print("[master] ", i)
    component.computer.beep(100, 0.1)
  elseif a =="tablet_use" and looking_for then
    -- When a block is selected (hold down shift and right click for more than 1 second)
    --  send the position back to the master
    print("block " .. looking_for .. " located at X: " .. (b.posX + gpsX), "Z:" .. (b.posZ + gpsZ))
    component.tunnel.send(tunnel_port, "FOUND", looking_for, (b.posX + gpsX), b.posY, (b.posZ + gpsZ))
    looking_for = nil
    component.computer.beep(900, 0.2)
    component.computer.beep(950, 0.2)
  elseif a == "touch" then
    -- On touch send a 'reboot' command back to the master
    component.tunnel.send(tunnel_port, "REBOOT")
    -- If we request a reboot, we should stop looking for the previous one
    looking_for = nil
  elseif a == "key_down" then
    -- The way out is to press the 'any' key
    os.exit()
--  else
--    print(a)
  end
  
  -- While we are looking for something send a notification back to the master, so it can keep issuing an identifiy command
  --   (using the tunnel is high energy use)
  if looking_for and computer.uptime() > lastuptime + 10 then
    print("Please locate", looking_for, "once found hold right click for 1 second")
    component.tunnel.send(tunnel_port, "PING", looking_for)       -- The remote end times out the ping requests
    lastuptime = computer.uptime()
  end

end
