--[[ OC-LOGISTICS STATION - sends info about current requests and provided items back to the logistics controller
     Author: nzHook
     Created for the Youtube channel https://youtube.com/user/nzHook 2019
     myRail Episode Showing Usage: https://www.youtube.com/watch?v=4gEuWiLwo1A
     
     
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
--   -- Change 'stationName' below to have the name of the station (as used by routing)
--   -- Change 'requests' below to indicate the amount of items to have - anything not listed is considered prvovided
--   -- Connect computer to transposers which are next to inventories - this will be how the system knows what to provide/request
--   -- Start the code (add it to rc.local even so it starts on boot)
---
local component = require("component")
local computer = require("computer")
local event = require("event")
local os = require("os")

local modem = component.modem
if not modem then
   print("This program requires a network device")
   os.exit()
end

if not component.transposer then
   print("This program uses transposers connect at least one")
   os.exit()
end

--
-- config
--

-- The routing name for this station (well internal name - name -> slot -> ticket)
local stationName = "PowerStation"
-- 0 = both requestoer and provider, 1 = provider only (nothing ever requested) 2 = requestor only (nothing ever provided)
local stationType = 0
-- Multiplier for how important this station gets its items (the higher the number the more chance it has)
local prioRequest = 1
-- Multiplier for how quickly items should be removed from this station its items (the higher the number the more chance we use what it provides first)
local prioProvide = 1

-- Requests are what this station REQUIRES
--  any item in a chest which does not exist in this
--  list or is higher than the threshold is considered PROVIDED
-- NOTE: Threshold on dispatcher is 128 so request at LEAST that many or the request will never be registered
local requests = {}
requests["empoweredoil"] = 4000
--requests["minecraft:log:0"] = 1

-- Dispatchers port
local dport = 1122
-- Dispatchers address we send requests to - will auto detect at startup if not given
--  TODO: Have a way to update when/if the dispatcher changes for some reason
local daddress = nil

-- Dispacher pass code - shouldnt need to change this unless you want multiple networks on the same port
--  This is what we expect the dispacher to send back with all messages
local dcode = "DISPATCH99"
 
--
-- end config
--

-- Grab what is currently stored here
-- If your not using transposers then replace this function with something
-- that returns an table of {item = count, item2 = count2}
local function whatIHave()
  local iHave = {}

  for k, v in pairs(component.list("transposer")) do
     local t = component.proxy(k)
     for side = 0, 5 do
       if t.getInventorySize(side) then
         for slot = 1, t.getInventorySize(side) do
            local item = t.getStackInSlot(side, slot)
            if item and item.size > 0 then
              if not iHave[item.name .. ":" .. item.damage] then
                  iHave[item.name .. ":" .. item.damage] = 0
              end
              
              iHave[item.name .. ":" .. item.damage] = iHave[item.name .. ":" .. item.damage] + item.size
            end
         end
       end
       -- same again for attached tanks for liquids
       if t.getTankCount(side) then
         for slot = 1, t.getTankCount(side) do
            local item = t.getFluidInTank(side, slot)
            if item and item.amount > 0 and item.name then
              if not iHave[item.name] then
                  iHave[item.name] = 0
              end
              
              iHave[item.name] = iHave[item.name] + item.amount
            end
         end
       end
     end
  end

  return iHave
end


-- So we know what we know, now we need to know what we dont know
--  This is the main calculation fuction and we send the results back to
--  the director
local function whatINeed(ihave)
   local notify = ihave
   -- determine differences
   for k, c in pairs(requests) do
      if notify[k] then
         notify[k] = notify[k] - requests[k]
         if notify[k] > 0 then      -- dont send if we have more than we need
           notify[k] = 0
         end
      else
         notify[k] = -requests[k]
      end
   end

   -- send numbers back to dispatch
   -- TODO Need a better way to do this as calling the network card multiple times is slow
   --   but sending one big packet doesnt work :(
   while true do
     local scount = 0
     for k, c in pairs(notify) do
       -- only send the detail if the stationType allows for the dispatcher to know about it
       --   0 = both requestoer and provider, 1 = provider only (nothing ever requested) 2 = requestor only (nothing ever provided)
       if stationType == 0 or (stationType == 1 and c > 0) or (stationType == 2 and c < 0) then
         -- 10-68 - dispatch info
         modem.send(daddress, dport, stationName, "10-68", scount, k, c)
         print("Station item detail: " .. k .. " = " .. c)
         scount = scount + 1
       end
     end

     -- 10-58 - start directing traffic include total sent and priorities
     modem.send(daddress, dport, stationName, "10-58", scount, prioRequest, prioProvide)
     print(scount .. " items sent to dispatcher")

     -- wait for the 10-4 
     local okgo = false
     local ltime = computer.uptime()
     while not okgo do
       local e, mea, da, prt, i1, msg1, msg2, msg3 = event.pull(10)
       -- if we have not had response then we repeat anyway
       if not e or computer.uptime() > ltime + 10 then
           print("No response from dispatch, repeating")
           okgo = true
       elseif e == "modem_message" and da == daddress and msg1 == dcode then
         -- 10-4 acks that the dispatcher got all the items
         if msg2 == "10-4" then
           okgo = true     --- shouldnt matter since we return but for completeness
           if msg3 == scount then    -- double check they have the same number
            print(dcode .. " said " .. msg2)
            return
           end
           print(dcode .. " only got " .. msg3 .. ", repeating")
         -- 10-9 indicates the dispatcher did not get all of the items
         elseif msg2 == "10-9" then
           print(dcode .. " asked for a signal repeat")
           okgo = true
         end
       end
     end
   end
end

-- Find and wait for the dispachers address
--  Used during bootup if the address is not set (todo to allow for changing during operation)
local function findDispatcher()
   daddress = nil           -- If we get here then make sure its nil
   local ltime = 0
   -- wait for a response, sending a referesher everu now and then
   while not daddress do
     if computer.uptime() > ltime + 10 then
       modem.broadcast(dport, stationName, "10-8")
       ltime = computer.uptime()
     end
     local e, mea, da, prt, i1, msg1, msg2, msg3 = event.pull(10)
     if e == "modem_message" and msg1 == dcode and msg2 == "10-2" then
       print("Dispatcher is on " .. da)
       daddress = da
     end
   end
end


-- Lets begin


-- If no name, use the computers address
if not stationName then
-- Was going to assign computer's address as a name but you need to be able to get here
--  so now its an error
--  stationName = computer.address
  print("No stationName given - how can a train get here?")
  os.exit()
end

modem.open(dport)

-- If the dispachers address is not given we need to broadcast for it
if not daddress then
  findDispatcher()
end

local laste = 0

while true do
  if laste + 30 < computer.uptime() then     -- Only update on the timer events
    local ihave = whatIHave()
    whatINeed(ihave)
    laste = computer.uptime()
  end

   -- We only recheck every 30 seconds, but when other messages such as train arrive/depart
   --   we can check again
   local e, e1, e2, e3, e4, e5, e6, e7, e8 = event.pull(10)
   if e == "modem_message" and e6 == dcode then
     -- TODO should handle other notifications here
   elseif e == "redstone_changed" then
      -- TODO Could indicate a train is rleaving / arriving, we should update
   elseif not e then
      -- All good dont debug this
   else
      print(e, e1, e2, e3, e4, e5, e6, e7, e8)
   end
end
