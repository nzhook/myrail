--[[ Station Ticket Gate Controller (for use with at least one interface and one ticket reader)
     Created for the Youtube channel https://youtube.com/user/nzHook 2019
     myRail Episode Showing Usage: https://www.youtube.com/watch?v=8byccypmjN0
     
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
-- How to use
--   -- Ensure the controller is on a different computer/server but on the same network as the interfaces
--   -- There is no fancy interface for this, just info about what is happeneing so hide it away out of sight
--   -- Configure commsport, password. Note these are required to configure any other devices
--   -- Start the code once, for ease of use it will put the id needed for 'controllerid' into a file named /modem.txt
--   -- If you stopped the code add the code to .rc.sh so it start on reboot
--   -- reboot or rerun the code (assuming you had stopped it)
--   -- Once running the infaces will talk with this device to get/purchase... tickets
---
local c = require("component")
local event = require("event")
local computer = require("computer")
local modem = c.modem

-- for state storage and reload
local serialization = require("serialization")
local filesystem = require("filesystem")

-- Config
--- The port to listen and respond on
local commsport = 1229
--- All inbound requests must have this password (for basic security)
local password = "S0mthingUnique"

--
-- Config ends here
--

-- Var init
local tickets = {}

local function savestate()
    local tmpf = io.open("/home/ticket.states", "w")
    local tmpi = serialization.serialize(tickets)
    tmpf:write(tmpi)
    tmpf:close()
end

local function maketicketid(deviceid, ticketprefix) 
		-- make the ticketid a semi-random number so its hard to guess
		local failcounter = 0
		repeat 
			failcounter = failcounter + 1
			if failcounter > 20 then
				print("New ticketid had too many uses")
				modem.send(deviceid, commsport, "generated", false)
			end

			ticketid = ticketprefix .. string.char(math.random(65, 90)) .. math.random(1, 9) .. string.char(math.random(65, 90)) .. math.random(11111, 99999)
		until(not tickets[ticketid])

		-- Make it as allocated so we dont try and reuse it
		-- @todo should these timeout if not used?
		tickets[ticketid] = {}
		tickets[ticketid]["uses"] = 0
		tickets[ticketid]["dests"] = nil

		print("New ticketid " .. ticketid)
		modem.send(deviceid, commsport, "generated", ticketid)
end

function purchaseticket(deviceid, ticketid, dest, trips, cost) 
	if not ticketid or not tickets[ticketid] then
		print("Purchase of non reserved ticket ", ticketid)
    
    for k,v in pairs(tickets) do
      print(k, v["uses"], v["dests"])
    end
    
		modem.send(deviceid, commsport, "invalidticket", ticketid)
		return
	end

	-- setup the ticket
	if not tickets[ticketid]["dests"] then
		tickets[ticketid] = {}
		tickets[ticketid]["uses"] = trips
		tickets[ticketid]["dests"] = dest
		print("Purchase of new ticket " .. ticketid .. " with " .. trips .. " trips for " .. cost)
		modem.send(deviceid, commsport, "ticket", ticketid, tickets[ticketid]["uses"], tickets[ticketid]["dests"])
	else
		-- Increase the use count on the ticket
		tickets[ticketid]["uses"] = tickets[ticketid]["uses"] + trips
		print("Topup of ticket " .. ticketid .. " with " .. trips .. " trips for " .. cost)
		modem.send(deviceid, commsport, "ticket", ticketid, tickets[ticketid]["uses"], tickets[ticketid]["dests"])
	end
  savestate()
end

function getticket(deviceid, ticketid)
	if tickets[ticketid] then
		modem.send(deviceid, commsport, "ticket", ticketid, tickets[ticketid]["uses"], tickets[ticketid]["dests"])
		print("Query for ticket " .. ticketid)
	else
		modem.send(deviceid, commsport, "invalidticket", ticketid)
		print("Query for ticket " .. ticketid .. " invalid")
	end
end

function useticket(deviceid, ticketid, dest)
	if not tickets[ticketid] then
		modem.send(deviceid, commsport, "invalidticket", ticketid, "not_found")
		print("Use of ticket " .. ticketid .. " invalid")
	elseif tickets[ticketid]["uses"] <= 0 then
		modem.send(deviceid, commsport, "invalidticket", ticketid, "used")
		print("Use of ticket " .. ticketid .. " out of uses")
	elseif tickets[ticketid]["uses"] > 0 then
		-- make sure the requesting platform is valid
		for check in string.gmatch(tickets[ticketid]["dests"], "([^,]+)") do
			if check == dest then
				tickets[ticketid]["uses"] = tickets[ticketid]["uses"] - 1
        savestate()
				modem.send(deviceid, commsport, "ticket", ticketid, tickets[ticketid]["uses"], tickets[ticketid]["dests"])
				print("Use of ticket " .. ticketid .. " for dest " .. dest .. " - allowed")
				return			-- no need to keep processing
			end
		end

		-- If we got here then the dest was invalid
		modem.send(deviceid, commsport, "invalidticket", ticketid, "invaliddest")
		print("Use of ticket " .. ticketid .. " invalid destination (" .. dest .. ")")
	else
		-- theres another option?
	end
end

function readmessage(event, localdeviceid, remotedeviceid, port, distance, passcode, action, d1, d2, d3, d4)
	if passcode ~= password then
		print("Invalid password (" .. passcode .. ") from " .. remotedeviceid .. " - " .. action .. " (", d1, d2, d3, d4, ")")
	else
		if action == "maketicketid" then
			maketicketid(remotedeviceid, d1)
		elseif action == "purchaseticket" then
			purchaseticket(remotedeviceid, d1, d2, d3, d4)
		elseif action == "getticket" then
			getticket(remotedeviceid, d1)
		elseif action == "useticket" then
			useticket(remotedeviceid, d1, d2)
		elseif action == "hello" then
			print(remotedeviceid .. " said hello")
			modem.send(remotedeviceid, commsport, "hello")
		else
			print("Unknown action " .. action .. " (", d1, d2, d3, d4, ")")
		end
	end
end

-- Load previous state
if filesystem.exists("/home/ticket.states") then
  local f = io.open("/home/ticket.states", "r")
  tickets = serialization.unserialize(f:read("*all"))
  f:close()
end

modem.open(commsport)
event.listen("modem_message", readmessage)

--event.ignore("modem_message", readmessage)
print("Ticket controller running (run iface on different machine(s) to access)")
print("Modem address = " .. modem.address)
local tmpf = io.open("/modem.txt", "w")
tmpf:write(modem.address)
tmpf:close()
print("(Address saved to /modem.txt)")

-- loop forever (avoids someone running iface on the local machine as the modem doesnt respond to localhost requests)
while true do
  event.pull(5, "nothing")
end
