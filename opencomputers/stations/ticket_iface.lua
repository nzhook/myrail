--[[ Station Ticket Gate Interface (for use with controller)
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
--   -- Make sure ticket_controller.lua is configured and on a different computer/server in the same network
--   -- Connect a Redstone IO, Screen teir 2 or higher (on floor) and a transposer where it can read what is ontop of the screen
--   -- Configure commsport, password, controllerid and platformname as appropriate
--   -- Optionally configure doorside, ticketinslot and whitelistedplayer
--   -- Start the code (add it to .rc.sh for it to start on reboot)
--   -- When a player walks on the screen a 'walk' event will fire
--   --   this will trigger the connected transposer(s) to look in the players inventory (at the ticketinslot slot)
--   --   if the ticket contains the networkname
--   --   the ticketid will be sent to the ticket_controller which if it accepts the ticket
--   --   a redstone signal will be sent out the doorside to open any redstone controlled doors
--   -- note: sometimes the screen wont trigger a walk event from the same player going in the same direction
--   --   walking over a second screen will normally fix this
---
local event = require("event")
local sides = require("sides")
local component = require("component")
local os = require("os")
local term = require("term")

local rs = component.redstone
local computer = component.computer
local modem = component.modem
local gpu = component.gpu

--config

-- The port to listen and respond to the controller on
local commsport = 1229
-- All outbound requests must have this password (for basic security)
local password = "S0mthingUnique"
-- The controllers modemid (eg. where messages are sent to)
-- @TODO Do we want the normal broadcast if not set here for an easier setup?
--   maybe do it once then save that address? - would mean it couldnt run an on an eeprom in the future
local controllerid = "8ea34d0d-5251-4f4d-bb5c-6958debb36cb"

-- The name of this train network (printed on tickets and use as validation before sending to the controller)
local networkname = "myRail ticket"

-- The destination name that this platform allows access to (must match what the controller issued a ticket for)
local platformname = "waterview"

-- doorside = the side to output a redstone signal to open the door = use -1 for all sides
local doorside = -1
-- ticketinslot = the slot to check in the players inventory for a valid ticket (5 = offhand) 
local ticketinslot = 5

-- whitelistedplayer = any player who does not require a ticket to pass
local whitelistedplayer = "nzhook2"
-- end config

-- show a message on the terminal, nothing fancy
local function showmsg(message, color)
  local sz
  if color == 0x00ff00 then
    gpu.setResolution(4, 2)
    sz = 5
  else
    gpu.setResolution(20, 10)
    sz = 20
  end
	gpu.setBackground(color)
  if color == 0x000000 then
    gpu.setForeground(0xffff00)
  else
    gpu.setForeground(0xffffff)
  end
	term.clear()
	term.setCursor(math.floor((sz - string.len(message)) / 2), 5)
	print(string.upper(message))
end

-- Communicate with the controller for detail
local function askcontroller(action, d1, d2, d3, d4)
	modem.send(controllerid, commsport, password, action, d1, d2, d3, d4)
	local e = {event.pull(120, "modem_message")}
	if not e or not e[1] then
    return "error", d1, "no response"
	end

	if e[3] ~= controllerid then
    return "error", d1, "controller error"
	end

	return e[6], e[7], e[8], e[9], e[10]
end

local function closedoor()
  if doorside == -1 then
    for i = 0, 5 do
      rs.setOutput(i, 0)
    end
  else
    rs.setOutput(doorside, 0)
  end
end

local function opendoor()
  if doorside == -1 then
    for i = 0, 5 do
      rs.setOutput(i, 15)
    end
  else
    rs.setOutput(doorside, 15)
  end
end

modem.open(commsport)
closedoor()

while true do
    local e = {event.pull()}
    if e[1] == "walk" and e[5] == whitelistedplayer then
      showmsg(e[5], 0x0000ff)
      opendoor()
      os.sleep(2)
      closedoor()
    elseif e[1] == "walk" then
      local doopen = false
      local ereason = "Invalid Ticket"

      local tlist = component.list("transposer")
      for t, t2 in pairs(tlist) do
        local tran = component.proxy(t)
        for i = 0, 5 do          
          local tt = tran.getStackInSlot(i, ticketinslot)
          if tt ~= nil then
            if tt.name == "openprinter:printedPage" and string.sub(tt.label, 0, string.len(networkname)) == networkname then
              -- its a matching ticket lets see if the controller will let it pass
              local ticketid = string.sub(tt.label, string.len(networkname) + 2)
              local responseid, tid, usesleft, dests = askcontroller("useticket", ticketid, platformname)
              if responseid == "ticket" then
                if usesleft > 1 then
                  showmsg(usesleft, 0x00ff00)
                else
                  showmsg(usesleft, 0x0000ff)
                  computer.beep(400, 0.1)
                  computer.beep(450, 0.1)
                  computer.beep(475, 0.1)
                end
                doopen = true
              elseif responseid == "invalidticket" then
                ereason = usesleft
              elseif responseid == "error" then
                ereason = usesleft
              end
              break
            end
--            for k,v in pairs(tt) do
--              print(k, v)
--            end   
          end
        end
      end
      if doopen then
        computer.beep(500, 0.1)
        computer.beep(600, 0.1)
        opendoor()
        os.sleep(2)
        closedoor()
      else
        -- that ticketid doesnt exist
        showmsg(ereason, 0xff0000)
        computer.beep(200, 0.2)
        computer.beep(100, 0.4)
      end
      
--    else
--      for k,v in ipairs(e) do
--        print(k, v)
--     end     
    end
    showmsg(platformname, 0x000000)
end
