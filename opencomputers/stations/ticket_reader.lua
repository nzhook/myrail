--[[ Station Ticket Gate Reader v1
     Created for the Youtube channel https://youtube.com/user/nzHook 2019
     myRail Episode Showing Usage: https://youtu.be/szz2IGiNp14
     
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
--   -- Connect a Redstone IO, Screen teir 2 or higher (on floor) and a transposer where it can read what is ontop of the screen
--   -- Configure ticketid, ticketlabel as appropriate
--   -- Optionally configure doorside, ticketinslot and whitelistedplayer
--   -- Start the code (add it to .rc.sh for it to start on reboot)
--   -- When a player walks on the screen a 'walk' event will fire
--   --   this will trigger the connected transposer(s) to look in the players inventory (at the ticketinslot slot)
---  --   if the item ticketid with a label of ticketlabel is detected
--   --   a redstone signal will be sent out the doorside to open any redstone controlled doors
--   -- note: sometimes the screen wont trigger a walk event from the same player going in the same direction
--   --   walking over a second screen will normally fix this
---

local event = require("event")
local sides = require("sides")
local component = require("component")
local os = require("os")

local rs = component.redstone
local computer = component.computer

--config
-- doorside = the side to output a redstone signal to open the door = use -1 for all sides
local doorside = -1
-- ticketinslot = the slot to check in the players inventory for a valid ticket (5 = offhand) 
local ticketinslot = 5

-- whitelistedplayer = a player who does not require a ticket to pass (station owner?)
local whitelistedplayer = "nzhook"
-- ticketid = The minecraft itemid of the item to natch
local ticketid = "minecraft:paper"
-- ticketlabel = The label/name that item should have to pass
local ticketlabel = "Waterview"
-- end config


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


closedoor()

while true do
    local e = {event.pull()}
    -- on a walk event if it is the station owner just open the door
    if e[1] == "walk" and e[5] == whitelistedplayer then
      opendoor()
      os.sleep(2)
      closedoor()
    -- if its a walk event then we need to do the check
    elseif e[1] == "walk" then
      local doopen = false

      -- for each connected Transposer check all possible sides to see if the 'chest'
      --  has the correct item in the slot. For our purposes the chest will be a player
      local tlist = component.list("transposer")
      for t, t2 in pairs(tlist) do
        local tran = component.proxy(t)
        for i = 0, 5 do
          local tt = tran.getStackInSlot(i, ticketinslot)
          if tt ~= nil then
            -- Check for the correct item and the correct label
            if tt.name == ticketid and tt.label == ticketlabel then
              doopen = true
              break
            end
          end
        end
      end
      -- If we found a valid item, open the door for a couple of seconds
      if doopen then
        computer.beep(500, 0.1)
        computer.beep(600, 0.1)
        opendoor()
        os.sleep(2)
        closedoor()
      else
        -- We didnt find the item, give some feedback
        computer.beep(200, 0.2)
        computer.beep(100, 0.4)
      end
    end
end
