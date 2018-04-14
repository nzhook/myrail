--[[ Rail yard train maker
     Created for the Youtube channel https://youtube.com/user/nzHook 2018
     myRail Episode Showing Usage: Not published yet
     
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
local event = require("event")
local sides = require("sides")
local serialization = require("serialization")
local filesystem = require("filesystem")
local os = require("os")
local computer = require("computer")

-- CHANGE THIS: This is the redstone IO taht is primary
--    there is no garentuee that OC will detect this correctly each boot
local rsid = "5b4"

-- rsmax is the starting point for the number calcs, eg. if the redstone io is 1 block away then any signal for white
--   would be 15 - 1. so this value should be 14
--   NOTE: Vanilla goes to 15, this code works in base 10, so you can have a maximum of 5 blocks between
local rsmax = 14

-- The sides of the transposer
local side_train = sides.right
local side_chest = sides.left
-- The slot in the train to put the ticket
--   in a steam engine this should be 4, in a creative its slot 1
-- TODO: Autodetect
local slot_train = 1
local slot_chest = nil
--- the sides of the redstone io
local side_track = sides.top
local side_release = sides.right
local side_next = sides.bottom

-- The port that we send updates to - needs tp match comms_port on master
local comms_port = 1234
-- rcomm is the port we get updates back on -- needs to match rcomms_port on master
local rcomms_port = 1235


-- Load previous state
--if filesystem.exists("/home/engine.states") then
--  local f = io.open("/home/engine.states", "r")
--  engines = serialization.unserialize(f:read("*all"))
--  f:close()
--  print("Loaded engines")
--end

--         local tmpf = io.open("/home/engine.states", "w")
--          local tmpi = serialization.serialize(engines)
--          tmpf:write(tmpi)
--          tmpf:close()


-- TODO: 
--  - Track where carts are stored
--  - Save/load positions
--  - Convert master instructions (wood, chest, chest) to position numbers
--  - Release final train
--  - Detect and request train details from master
--  - Detect arriving train to start shunting
--  - Main loop

local modem = component.list("modem")()
if not modem then error("No modem/network found") end
modem = component.proxy(modem)
if not modem then error("Error loading modem") end

-- Setup the components
component.setPrimary("redstone", component.get(rsid))
modem.open(rcomms_port)
modem.broadcast(comms_port, "yardevent", id, "boot")


local cartloc = {}
cartloc["wood"] = 1
cartloc["chest"] = 2
cartloc["cart"] = 3

while true do
  local step = 0
  local carts = {}


  -- First loop, wait for something to do
  while true do
     local a, b, c, d, e, f, g = event.pull(5)
     if not a then
         -- release a train - doing this on the timeout is slow
         -- but it ensures we are runniong and can detect the inbound train
         component.redstone.setOutput(side_next, 15)
         component.redstone.setOutput(side_next, 0)
     elseif a == "redstone_changed" then 
        print(a, b, sides[c], d, e)
        if e > 0 then -- Ignore when the engine moves off
          -- What we do depends on the side
          if sides[c] == "top" and currentT and currentB then
            -- Engine has rolled over the final detector send the final number to the master
            
            print("new engine " .. currentB, currentT)
            -- Ask the master what this engine should be
            modem.broadcast(comms_port, "yardrequirements", currentB, currentT)
            
            currentB = 0
            currentT = 0
          elseif sides[c] == "front" then
            -- The bottom colour number which we use as the base
            currentB = rsmax - e
          elseif sides[c] == "back" then
            -- The top colour number which we use as the base
            currentT = rsmax - e
          end
        end
      elseif a == "modem_message" then
        print("REPLY", a, b, c, d, e, f, g)
        if f == "yardbuild" then
          -- Its a build request, we exit this loop and move into the build loop
          print("Building", g)
          carts = {}
          step = 0
          for i in string.gmatch(g, "%S+") do
            --print(i)
            if cartloc[i] then
              table.insert(carts, cartloc[i])
            else
              print("CANT FIND A LOCATION FOR ", i)
            end
          end
          if #carts == 0 then
            -- No carts to setup, it takes a few moments for the engine to arrive so lets wait
            --  before sending them onward
            print("Empty? sleeping a moment")
            os.sleep(5)
          end
          break
        else
          print("Unknown modem message", f, g)
        end
      end
  end
  
  
  -- Engine has arrived, build the train
  --- TODO: What happens if we run out of carts?
  while true do
    component.redstone.setOutput(side_track, 0)
    local e = event.pull(2)
    
    if component.transposer.getInventorySize(side_train) then
      -- Every now and then, we detect the shuter passing. so wait 1 second and then test again
      os.sleep(1)
      if component.transposer.getInventorySize(side_train) then
        step = step + 1
        if step > #carts then
          step = 0
          break
        end
        
        local slot_chest = carts[step]
        print(step .. " = " .. slot_chest)
        component.redstone.setOutput(side_track, 0)
        if slot_chest then
          component.transposer.transferItem(side_chest, side_train, slot_train, slot_chest)
          --os.sleep(1)
          component.transposer.transferItem(side_train, side_chest, slot_chest, slot_train)
        end
      
        -- trigger the train to move
        component.redstone.setOutput(side_track, 15)
      end
    end
  end


  print("train complete")
  component.redstone.setOutput(side_release, 15)
  os.sleep(1)
  component.redstone.setOutput(side_release, 0)
end
