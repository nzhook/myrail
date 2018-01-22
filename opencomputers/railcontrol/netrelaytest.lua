--[[ Very simple master opencomputers program to show events coming from netrelay_bios.lua (on a microcontroller)
     Created for the Youtube channel https://youtube.com/user/nzHook 2018
     myRail Episode Showing Usage: https://www.youtube.com/watch?v=uimspQP-1S4
     NOTE: Designed for use with a device that relay events back - also handles basic ident.lua updates
           both this device and the remote one require a shared linked card
     
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
local computer = require("computer")
local event = require("event")

local comm_port = 1232
local rcomm_port = 1233
local tunnel_port = 1234

local seen = {}
local pinged = 0
local pinging = nil
local lastpingtime = 0

component.modem.open(comm_port)
--component.tunnel.open(tunnel_port)

for i = 1, 10000 do
  local a, b, c, d, e, f, g, h, i, j, k, l, m = event.pull(3)
  -- Todo Should make this trigger as an event and then make it a lib
  if a == "modem_message" then
    if f == "relayevent" then
      a = h
      b = g       -- the computer id
      --b = i       -- the redstoneid
      b = c       -- the network sourceid
      c = j
      d = k
      e = l
      f = m
      g = n
    elseif g == "FOUND" then
      -- Track that we have seen this ID
      seen[h] = {i, j}
      pinging = nil
      pinged = 0
    elseif g == "PING" then
      -- If the ident.lua script sends a ping request track the id
      print("ping req", h)
      pinging = h
      pinged = 0
    else
      print("Unknown message", f, g)
    end
  end
  -- Remember the above if may reset a so dont use elseif
  
  if (a == "redstone_changed" or a == "boot") and not seen[b] then
    -- We have not seen this device before tell ident.lua over the linked card
    print("MISSING ", b)
    if not pinging then
      component.tunnel.send(tunnel_port, "IDENT", b)
    end
  end
  
  -- Assuming this was not a timeout, print the result
  if a then
    print(a, b, c, d, e, f, g)
  end
  
  -- A way to exit
  if a == "touch" then
    os.exit()
  end
  
  -- Every few seconds send a ping to the microcontroller (netrelay_bios.lua) to highlight it
  if pinging and lastpingtime + 3 <= computer.uptime() then
    component.modem.send(pinging, rcomm_port, "PING")
    pinged = pinged + 1
    if pinged > 10 / 3 then
      pinged = 0
      pinging = nil
    end
    lastpingtime = computer.uptime()
  end
  
end
