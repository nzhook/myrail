--[[ Use redstone to detect type of train by colour
     Created for the Youtube channel https://youtube.com/user/nzHook 2018
     myRail Episode Showing Usage: https://www.youtube.com/watch?v=02_GhpYRju4
     
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
local event = require("event")
local component = require("component")
local computer = require("computer")

local sides = {
  [0] = "bottom",
  [1] = "top",
  [2] = "back",
  [3] = "front",
  [4] = "right",
  [5] = "left",
  [6] = "unknown",
}

-- rsmax is the starting point for the number calcs, eg. if the redstone io is 1 block away then any signal for white
--   would be 15 - 1. so this value should be 14
--   NOTE: Vanilla goes to 15, this code works in base 10, so you can have a maximum of 5 blocks between
local rsmax = 14

--  @todo Should we handle network events?  maybe keep track of the previous hops, so we dont send back - drop at X number (eg. TTL)
local comms_port = 1234
-- rcomm is for the locate me packet.
local rcomms_port = 1235

local id = computer.address()

local modem = component.list("modem")()
if not modem then error("No modem/network found") end
modem = component.proxy(modem)
if not modem then error("Error loading modem") end

modem.open(rcomms_port)
modem.broadcast(comms_port, "engineevent", id, "boot")

local t
local currentB = 0
local currentT = 0
while true do
   local a, b, c, d, e = event.pull(60, "redstone_changed")
   if a then
      print(a, b, sides[c], d, e)
			if e > 0 then	-- Ignore when the engine moves off
				-- What we do depends on the side
				if sides[c] == "top" and currentT and currentB then
					-- Engine has rolled over the final detector send the final number to the master
					
					print("sending " .. currentB, currentT)
					modem.broadcast(comms_port, "engineevent", id, currentB, currentT)
					currentB = 0
					currentT = 0
				elseif sides[c] == "left" then
					-- The bottom colour number which we use as the base
					currentB = rsmax - e
				elseif sides[c] == "right" then
					-- The top colour number which we use as the base
					currentT = rsmax - e
				end
			end
		
   else
     -- Its a timeout and we are letting it 'Yeild'
		--  plus if we havnt had an update recently we forget any engine that we havnt sent
		currentT = 0
		currentB = 0
   end

end
