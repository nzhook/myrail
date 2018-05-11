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
local colors = require("colors")
local serialization = require("serialization")
local filesystem = require("filesystem")
local os = require("os")
local computer = require("computer")

-- CHANGE THESE: There is no garentuee that OC will detect this correctly each boot
-- This is the redstone IO that is primary
local rsid = "5b4"
-- This is the redstone IO of the engine detector
local rsid_engine = "7171"
-- This is the redstone IO of the cart detector
local rsid_cart = "3c5c"

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
--- the sides and colours of the redstone io
local side_track = sides.top
local side_isengine = sides.right
local side_bundle = sides.bottom
local sidecolor_release = colors.white
local sidecolor_next = colors.orange
local sidecolor_decouple = colors.magenta
--- the sides of the redstone io for engine detector
local side_Dbottom = sides.front
local side_Dtop = sides.back
--- the sides of the redstone io for cart detector
local side_cartdetect = sides.top
local side_cartwaiting = sides.back

-- The port that we send updates to - needs tp match comms_port on master
local comms_port = 1234
-- rcomm is the port we get updates back on -- needs to match rcomms_port on master
local rcomms_port = 1235

-- TODO: 
--  - Track where carts are stored and maybe how many are there
--  - Save/load positions

local modem = component.list("modem")()
if not modem then error("No modem/network found") end
modem = component.proxy(modem)
if not modem then error("Error loading modem") end

-- Setup the components
component.setPrimary("redstone", component.get(rsid))
modem.open(rcomms_port)
modem.broadcast(comms_port, "yardevent", id, "boot")


rsid_engine = component.get(rsid_engine)
rsid_cart = component.get(rsid_cart)

if not rsid_engine then
		print("Could not determine Engine detector Redstone IO")
		os.exit()
end
if not rsid_cart then
		print("Could not determine Cart detector Redstone IO")
		os.exit()
end


local nextresend = 0

-- Sidings the carts are stored in (well the location of the tickets in the chest)
local cartloc = {}
cartloc["wood"] = 1
cartloc["chest"] = 2
cartloc["cart"] = 3
cartloc["tanker"] = 4
cartloc["chunk"] = 5
cartloc["cargo"] = 6
cartloc["RETURN"] = 7

-- The mapping of redston in the cart detector to carts
--   Make sure that all the cart names listed here exist in the above array
--   In the future the above array may be dynamic, but this will need to match the detectors
local cartmatch = {}
cartmatch[0] = "wood"
cartmatch[1] = "chest"
cartmatch[2] = "cart"
cartmatch[3] = "tanker"
cartmatch[4] = "chunk"
cartmatch[5] = "cargo"

-- If something is waiting to be built, we no longer know about it so release it
component.redstone.setBundledOutput(side_bundle, sidecolor_release, 15)
component.redstone.setBundledOutput(side_bundle, sidecolor_release, 0)


while true do
  local step = 0
  local carts = {}

	component.redstone.setBundledOutput(side_bundle, sidecolor_decouple, 0)

	-- First loop, wait for something to do
  while true do
     local a, b, c, d, e, f, g = event.pull(2)
     if not a then
			if component.transposer.getInventorySize(side_train) then
				if component.redstone.getInput(side_isengine) == 0 then
					-- Its not the shunter - maybe a cart being pushed. let it go
					component.redstone.setOutput(side_track, 15)
					component.redstone.setOutput(side_track, 0)
				else
					-- If we have been idle for a while look to see if there
					--  are carts to return. Returning is more important than
					--  building because we may need one of these carts
					if component.invoke(rsid_cart, "getInput", side_cartwaiting) > 0 then
						print("A cart is waiting, releasing shunter to pick up")
						component.transposer.transferItem(side_chest, side_train, slot_train, cartloc["RETURN"])
						--os.sleep(1)
						component.transposer.transferItem(side_train, side_chest, cartloc["RETURN"], slot_train)
						
						component.redstone.setOutput(side_track, 15)
						component.redstone.setOutput(side_track, 0)
						component.redstone.setBundledOutput(side_bundle, sidecolor_decouple, 15)
					else
						-- If no carts are there then release a train - doing this on the timeout is slow
						-- but it ensures we are runniong and can detect the inbound train
						component.redstone.setBundledOutput(side_bundle, sidecolor_next, 15)
						component.redstone.setBundledOutput(side_bundle, sidecolor_next, 0)
					end
				end
			end
     elseif a == "redstone_changed" then 
        print(a, b, sides[c], d, e)
        if e > 0 then -- Ignore when the engine moves off
          if b == rsid_engine then
            -- What we do depends on the side
            if sides[c] == "top" and currentT and currentB then
              -- Engine has rolled over the final detector send the final number to the master
            
              print("new engine " .. currentB, currentT)
              nextresend = computer.uptime()
            elseif c == side_Dbottom then
              -- The bottom colour number which we use as the base
              currentB = rsmax - e
            elseif c == side_Dtop then
              -- The top colour number which we use as the base
              currentT = rsmax - e
            end
					elseif b == rsid_cart and c == side_cartdetect then
						-- Map the redstone to the cart type
						-- TODO: Need something more dynamic here
						returncart = cartmatch[rsmax - e]
						print("Cart detector gave " .. (rsmax - e) .. "...")
						print(" -> returning to " .. cartloc[cartmatch[rsmax - e]] .. " (" .. cartmatch[rsmax - e] .. ")")
						carts = {}
						-- TODO What happens if we dont have a matching cart location?  optimal would be for us to pick a free
						--   siding, but we dont track that at the moment. ATM This will cause a code error
						table.insert(carts, cartloc[cartmatch[rsmax - e]])
						-- TODO: Enable the decoupling tracks --  and disable at stat of run (after cart is returned)
						break
					elseif b == rsid and not (c == side_isengine) then
						-- Its not the shunter - maybe a cart being pushed. let it go
						component.redstone.setOutput(side_track, 15)
						component.redstone.setOutput(side_track, 0)
          end
        end
      elseif a == "modem_message" then
        print("REPLY", a, b, c, d, e, f, g)
        if f == "yardbuild" then
          currentB = 0
          currentT = 0
          nextresend = 0

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
      if currentB and currentT and nextresend > 0 and nextresend <= computer.uptime() then
            -- Ask the master what this engine should be
            --  This maybe because the engine ran over the detector OR we have not had a response
            --  from a master so need to resend
            modem.broadcast(comms_port, "yardrequirements", currentB, currentT)
           
            nextresend = computer.uptime() + 10
      end
  end
  
  
  -- Engine has arrived, build the train
  --- TODO: What happens if we run out of carts?
  -- OR we are returning a cart, same process just with another redstone flag set to enable the
  --   decouplers
  while true do
    component.redstone.setOutput(side_track, 0)
    local e = event.pull(2)
		
    if component.transposer.getInventorySize(side_train) then
      -- Every now and then, we detect the shuter passing. so wait 1 second and then test again
      os.sleep(1)
      if component.transposer.getInventorySize(side_train) then
				if component.redstone.getInput(side_isengine) == 0 then
					-- Its not the shunter - maybe a cart being pushed. let it go
					component.redstone.setOutput(side_track, 15)
					component.redstone.setOutput(side_track, 0)
				else
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
  end


  print("train complete")
  component.redstone.setBundledOutput(side_bundle, sidecolor_release, 15)
  os.sleep(1)
  component.redstone.setBundledOutput(side_bundle, sidecolor_release, 0)
end
