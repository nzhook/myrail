--[[ Rail yard train maker
     Author: nzHook
     Created for the Youtube channel https://youtube.com/user/nzHook 2018
     myRail Episode Showing Usage: Ep18 - https://www.youtube.com/watch?v=Iq13el02ips
     myRail Episode Where Updated For Computronics: Ep43 - https://youtu.be/SisYSkjtHjg

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
--  Make sure cns.lua library is in the same path as this file or /lib
local cns = require("cns")

-- CHANGE THESE: There is no garentuee that OC will detect this correctly each boot
-- This is the redstone IO that is primary
local rsid = "yard_redstone"
-- This is the redstone IO of the engine detector (recomend using cns to name the device)
local ctid_engine = "engines_in"
-- This is the ID of the inbound cart detector
local ctid_cart = "carts_in"
-- This is the ID of the redstone IO placed next to the carts
local rsid_cart = "cart_waiting"
-- This is the ID of the cart detector where the shunter idles (used to detect it)
local ctid_shunter = "cart_shunting"

-- The sides of the transposer
--local side_train = sides.right
--local side_chest = sides.left
-- The slot in the train to put the ticket
--   in a steam engine this should be 4, in a creative its slot 1
-- TODO: Autodetect
--local slot_train = 1
--local slot_chest = nil
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
local side_cartwaiting = sides.front

-- The port that we send updates to - needs tp match comms_port on master
local comms_port = 1234
-- rcomm is the port we get updates back on -- needs to match rcomms_port on master
local rcomms_port = 1235

-- Sidings the carts are stored in (well the location of the tickets in the chest)
--- TODO: Replace
local cartloc = {}
cartloc["wood"] = 1
cartloc["chest"] = 2
cartloc["basic"] = 3
cartloc["cart"] = 3       -- alias
cartloc["tank"] = 4
cartloc["worldspike_admin"] = 5
cartloc["chunk"] = 5      -- alias
cartloc["cargo"] = 6
cartloc["RETURN"] = 7

-- TODO: 
--  - Track where carts are stored and maybe how many are there
--  - Save/load positions

local modem = component.list("modem")()
if not modem then error("No modem/network found") end
modem = component.proxy(modem)
if not modem then error("Error loading modem") end

-- Setup the components
rs_yard = component.get(cns(rsid))
ct_engine = component.get(cns(ctid_engine))
ct_cart = component.get(cns(ctid_cart))
ct_shunter = component.get(cns(ctid_shunter))
rs_cart = component.get(cns(rsid_cart))

if not rs_yard then
		print("Could not find the primary Redstone IO (" .. rsid .. "/" .. cns(rsid) .. ") as a component")
		os.exit()
end
print("yard redstone", rs_yard)

if not ct_engine then
		print("Could not find the Engine cart_detector (" .. ctid_engine .. "/" .. cns(ctid_engine) .. ") as a component")
		os.exit()
end
print("engine detector", ct_engine)

if not ct_cart then
		print("Could not find the returning Cart cart_detector (" .. ctid_cart  .. "/" .. cns(ctid_cart).. ") as a component")
		os.exit()
end
print("cart detector", ct_cart)

if not rs_cart then
		print("Could not find the waiting Cart Redstone IO (" .. rsid_cart  .. "/" .. cns(rsid_cart).. ") as a component")
		os.exit()
end
print("cart waiting redstone", ct_cart)

if not ct_shunter then
		print("Could not find the shunting cart_detector (" .. ctid_shunter  .. "/" .. cns(ctid_shunter).. ") as a component")
		os.exit()
end
print("shunter detector", ct_shunter)

-- sleep for a few seconds to wait for the components to settle (otherwise it gets a no primary redstone error)
os.sleep(2)
component.setPrimary("redstone", rs_yard)
modem.open(rcomms_port)
modem.broadcast(comms_port, "yardevent", id, "boot")

print("Yard starting")

-- set the destintion to empty
component.locomotive_relay.setDestination("")


local nextresend = 0

-- If something is waiting to be built, we no longer know about it so release it
component.redstone.setBundledOutput(side_bundle, sidecolor_release, 15)
component.redstone.setBundledOutput(side_bundle, sidecolor_release, 0)

-- Currently computonics only provides events not a read now command
--  so if we see a minecart event for the loco stand then we need to store what it is
--  one issue with this is if the cart is we dont get a siganl when the cart leves so this will
--  always be set. Could have a railcraft cart detector as well and when its no longer on we unset
--  but that might be a bit much
local ct_shunter_type = nil
event.listen("minecart", function(_, deviceid, carttype) 
        if(deviceid == ct_shunter) then
          ct_shunter_type = carttype
        end
  end )


while true do
  local step = 0
  local carts = {}
local scounter = 0

	component.redstone.setBundledOutput(side_bundle, sidecolor_decouple, 0)

	-- First loop, wait for something to do
  while true do
     local a, b, c, d, e, f, g = event.pull(1)
    if not a then
     -- timeout
     if component.locomotive_relay.getDestination() == "" or scounter > 0 then
        -- If we have been idle for a while look to see if there
        --  are carts to return. Returning is more important than
        --  building because we may need one of these carts
        if component.invoke(rs_cart, "getInput", side_cartwaiting) > 0 then
          print("A cart is waiting, releasing shunter to pick up")
          --component.transposer.transferItem(side_chest, side_train, slot_train, cartloc["RETURN"])
          --os.sleep(1)
          --component.transposer.transferItem(side_train, side_chest, cartloc["RETURN"], slot_train)
          component.locomotive_relay.setDestination("R1")
          
          
          component.redstone.setOutput(side_track, 15)
          component.redstone.setOutput(side_track, 0)
          component.redstone.setBundledOutput(side_bundle, sidecolor_decouple, 3600)
        else
          -- If no carts are there then release a train - doing this on the timeout is slow
          -- but it ensures we are runniong and can detect the inbound train
          component.redstone.setBundledOutput(side_bundle, sidecolor_next, 3600)
          component.redstone.setBundledOutput(side_bundle, sidecolor_next, 0)
          
          scounter = scounter + 1
          if scounter == 1 then
            component.locomotive_relay.setDestination("Like")
          elseif scounter == 2 then
            component.locomotive_relay.setDestination("and")
          elseif scounter == 3 then
            component.locomotive_relay.setDestination("Subscribe")
          elseif scounter == 4 then
            component.locomotive_relay.setDestination("")
          elseif scounter == 6 then
            scounter = 0
          end

        end
     end
    elseif a == "minecart" then
      -- minecart is the computronics signal for the digital cart detector
      -- b=address
      -- c=type
      -- d=name
      -- e=primaryColor
      -- f=secondaryColor
      -- g=destination
      -- h=owner
      if b == ct_engine then
        -- New engine has rolled in send the number to the master
        currentT = e
        currentB = f
        print("new engine " .. currentB, currentT)
        nextresend = computer.uptime()
      elseif b == ct_cart then
        -- Map the redstone to the cart type
        -- TODO: Need something more dynamic here
        if c == "locomotive_electric" or c == "locomotive_creative" then
          -- ignore the shunter passing
        else
          -- TODO What happens if we dont have a matching cart location?  optimal would be for us to pick a free
          --   siding, but we dont track that at the moment. ATM This will cause a code error
          c = string.sub(c, 6)
          if cartloc[c] then
            print("Cart detector gave " .. c .. "...")
            print(" -> returning to " .. cartloc[c])
            carts = {}
            table.insert(carts, cartloc[c])
            -- TODO: Enable the decoupling tracks --  and disable at start of run (after cart is returned)
          else
            error("Unknown cart " .. c)
          end
          break
        end
      elseif b == ct_shunter then
        if c == "locomotive_electric" or c == "locomotive_creative" then
          -- Its the shunter we can let it idle
        else
          -- Its not the shunter - maybe a cart being pushed. let it go
          component.redstone.setOutput(side_track, 3600)
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
    
    -- we wait for the cart detector to signal that the shunter is stalled
    if component.redstone.getInput(side_isengine) > 2 then
      -- Every now and then, we detect the shunter passing. so wait 1 second and then test again
      os.sleep(2)
      if component.redstone.getInput(side_isengine) > 2 then
        if ct_shunter_type ~= "locomotive_electric" and ct_shunter_type ~= "locomotive_creative" then
					-- Its not the shunter - maybe a cart being pushed. let it go
					component.redstone.setOutput(side_track, 3600)
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
						--component.transposer.transferItem(side_chest, side_train, slot_train, slot_chest)
						--os.sleep(1)
						--component.transposer.transferItem(side_train, side_chest, slot_chest, slot_train)
            component.locomotive_relay.setDestination("T" .. slot_chest)
					end
				
					-- trigger the train to move
					component.redstone.setOutput(side_track, 3600)
				end
      end
    end
  end


  print("train complete")
  component.redstone.setBundledOutput(side_bundle, sidecolor_release, 3600)
  os.sleep(1)
  component.redstone.setBundledOutput(side_bundle, sidecolor_release, 0)
  component.locomotive_relay.setDestination("")
end
