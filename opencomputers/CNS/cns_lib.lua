--[[ Component name system (CNS) - library file
     Author: nzHook
     Created for the Youtube channel https://youtube.com/user/nzHook 2021
     myRail Episode Showing Usage: https://youtu.be/SisYSkjtHjg (myRail episode 43)
     
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
---
-- How to use (basic)
--   -- Install the server/computer side and start it
--   -- Assign names using a tablet or another command that uses the API
--   -- Place this file in the lib path or in the script directory
--   -- Include the file (local cns=require("cns"))
--   -- Call the function cns('name') to return the name from the server
--  See test.lua for an example

--- Note this assumes networked using network cards / wireless not tunnels
local component = require("component")
local event = require("event")


---- config
----
-- Port of the name server, standard internet port for dns is 53
local ns_port = 53
-- ID of the name server to use, if empty the first server to respond to this computers address is used
local ns_id = nil

---
-- Request component name or ID
--
-- Params:
--  requestedname  Name or ID to return detail for
-- 
-- Returns
--  nil, nil, nil if nothing found
--  otherwise:
--  string containing address ID OR a known Name for the requested id
--  string containing the address ID or nil if a host was returned
--  string containing the known Name or nil if a IP was returned
local msgid = math.random(100, 231)
local function cns(requestedname)
  msgid = msgid + 1
  local device 
  -- modem
  device = component.modem
  
  device.open(ns_port)
  if not ns_id then
    device.broadcast(ns_port, "ns", "lookup", msgid, requestedname)
  else
    device.send(ns_id, ns_port, "ns", "lookup", msgid, requestedname)
  end
  
  -- we wait for the response to this msgid and nothing else, if nothing comes back after 5 then nil will be returned
  local e, null, raddr, rport, null, null, rmsgid, msg1, msg2, msg3, msg4, msg5, msg6 = event.pull(5, "modem_message", nil, nil, ns_port, nil, "nsres", msgid)
  device.close(ns_port)
  
  -- If no server ID is currently set then start using the server that responded
  if not ns_id and msg1 then
    ns_id = raddr
  end
  
  return msg3
end

return cns
