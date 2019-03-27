--[[ OC-LOGISTICS DISPATCHER - the heart of the Logistics system
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
--   -- Start the code (add it to .rc.sh even so it starts on boot)
--   -- Make sure to have station.lua on at least two stations (one to request and one to provide)
--   -- Recomend having microcontrollers with logistic_router.lua on an EEPROM to give orders from Golden Tickets
--   -- You can also enable requesting new trains when low using the oc-controller in the config below
---
local component = require("component")
local computer = require("computer")
local event = require("event")
local term = require("term")
local os = require("os")

local modem = component.modem
if not modem then
   print("This program requires a network device")
   os.exit()
end

--
-- config
--

-- Listening Port (needs to match Dispatchers port in station.lua)
local dport = 1122

-- Routers Port (needs to match Dispatchers port in logistics_router.lua)
local dbport = 1123

-- Dispacher pass code - The code sent back with all of our requests (kind of a password)
local dcode = "DISPATCH99"

-- FOR USE WITH MY DEPOT
-- The maximum number of trains to be requested - set to 0 to use prebuilt trains only
local maxTrains = 0
-- The comms port of the depot
local depot_comms_port = 1234
-- The return comms port from the depot
local depot_rcomms_port = 1235
-- The tasks that sholuld be added/removed from
local depot_train_tasks = {}
depot_train_tasks["goods"] = "LogisticsChest2"
depot_train_tasks["liquid"] = "LogisticsTank2"
-- END DEPOT CONFIG

-- These two are too avoid sending a tarin for 1 item, it should allow for the station to gain more items first
--  both default to 2 stacks
-- The minimum number of items at a provider for it to be considered
local qtyMinProvide = 128

-- The minimum number of items a requestor can ask for before we send a train
local qtyMinRequest = 128


--
-- end config
--

-- Globals vars
local requests = {}
local newinputs = {}
local provides = {}
local trains = {}
local stations = {}
local deliver = {}
local depot_requestedtrain = false

local ntime = 0

-- The nuts and bolts

-- Setup a new train record
local function newtrain(trainid, carttypes)
  -- Quick reverse map for when the depot is used
  if maxTrains > 0 then
    for k, v in pairs(depot_train_tasks) do
      if v == carttypes then
        carttypes = k
      end
    end
  end
  
  trains[trainid] = {
    requestor = nil, 
    provider = nil, 
    onway = nil, 
    id = 0,
    cargotype = carttypes,
    lastitem = nil,
    lastuse = 0
  }
end

-- Setup a new station - doesnt do much yet but called when we are sent station details / request details
local function newstation(stationName, netid)
  stations[stationName] = {
    id = netid,
    prioRequest = msg2, 
    prioProvide = msg3, 
    lastuse = 0
  }
end


-- Find a suitable provider for a request
--  we pass requestor here so we dont choose itself (should never happen)
local function sendToBestProvider(item, amount, reqestor)
   -- If the request is less than our threshold dont do anything
   if amount < qtyMinRequest then
     return nil
   end
   
   -- if no providers available for item just return
   if not provides[item] then
     print("No stations have " .. item)
     return nil
   end

   -- Work out the appropriate stations
   local teststations = {}
   for k, v in pairs(provides[item]) do
      -- Remove any in-progress deliveries
      if deliver[k] and deliver[k][item] then
        for t, damo in pairs(deliver[k][item]) do
          v = v + damo
        end
      end
      -- Make sure we have the minimum threshold
      if v >= qtyMinProvide then
         teststations[#teststations + 1] = {
            id = k,
            prio = stations[k]["prioProvide"],
            count = v,
            lastuse = stations[k]["lastuse"],
            cansatisfy = v > amount
         }
      end
   end
   if #teststations == 0 then
     print("No stations have enough ", item, "need", amount)
     return nil
   end
   
   -- sort all that data so we can pick the best provider station
  table.sort(teststations, function(a, b)
      if a["prio"] ~= b["prio"] then
        return a["prio"] > b["prio"]
      end

      -- Before we check lastused if a station can satisy a full request it is more important
      --  than a station that cant. after that lastused and then last the available amount
      if a["cansatisfy"] ~= b["cansatisfy"] then
         if a["cansatisfy"] then
           return true
         else
           return false
         end
      end

      if a["lastuse"] ~= b["lastuse"] then
        return a["lastuse"] > b["lastuse"]
      end

      return a["count"] > b["count"]
  end)

  -- Best provider will now be at the top, we only send one at a time so the next one may come
  --  off the next best station (as lastused will have changed)
  local useprovider = teststations[1]["id"]
  local reqamount = teststations[1]["count"]
  if reqamount > amount then
    reqamount = amount            -- This is debugging really, since we cant fill a train to an exact amount
  end
  print("station", useprovider, "has", reqamount .. "/" .. amount, item, "for", reqestor)
  if useprovider == reqestor then
     -- Lets assume we just delivered to itself
     stations[reqestor]["lastuse"] = computer.uptime()
     return nil
  end

    -- Cargo is liquid if there is no : for the mod (since tanks dont return the modname)
    local oftype;
    if string.match(item, ":") then
      oftype = "goods"
    else
      oftype = "liquid"
    end

    --
    -- Find an available train that can take this cargo
    --  prefer a train that has recently taken the same
    --  cargo (it may be near the area or be half full?)
    --  and that has been used recently (dont send more
    --  trains into the field than we need)
    --  otherwise we need to request a new one
    --
    local testtrains = {}
    for k, v in pairs(trains) do
      if not trains[k].requestor and trains[k].cargotype == oftype then
        -- could add train size here and filter by an appropriate amount (eg. 256 in a train that holds 1000 vs a train that holds 256)
          testtrains[#testtrains + 1] = {
             id = k,
             haditem = trains[k]["lastitem"] == item,
             lastuse = trains[k]["lastuse"]
          }
       end
    end
    if #testtrains == 0 then
      print("No trains are currently available")
      
      -- If using the depot system, request a new train to be released
      if #trains < maxTrains and not depot_requestedtrain then
          modem.broadcast(depot_comms_port, "addtrain", depot_train_tasks[oftype])
          depot_requestedtrain = true
      end
      
      return nil
    end
     -- sort all that data so we can pick the best provider station
    table.sort(testtrains, function(a, b)
        if a["haditem"] ~= b["haditem"] then
           if a["haditem"] then
             return true
           else
             return false
           end
        end

        return a["lastuse"] < b["lastuse"]
    end)
    -- An appropriate train will now be at the top
    local trainid = testtrains[1]["id"]

  


    -- track delivery and train size (we dont have maximum loading levels - so a train would be compleltly filled)
    if not deliver[reqestor] then
      deliver[reqestor] = {}
    end
    if not deliver[reqestor][item] then
      deliver[reqestor][item] = {}
    end
    deliver[reqestor][item][trainid] = reqamount
    if not deliver[useprovider] then
      deliver[useprovider] = {}
    end
    if not deliver[useprovider][item] then
      deliver[useprovider][item] = {}
    end
    deliver[useprovider][item][trainid] = -reqamount
    
    trains[trainid]["provider"] = useprovider
    trains[trainid]["requestor"] = reqestor
    trains[trainid]["item"] = item
    trains[trainid]["onway"] = false
    
    modem.send(stations[reqestor]["id"], dport, dcode, "10-64", reqestor, item, useprovider, reqamount)   -- Local delivery on way
    modem.send(stations[useprovider]["id"], dport, dcode, "10-82", useprovider, item, reqestor, -reqamount)   -- Reserve Items
    -- Train on its way, update the lastused fields so other stations get a go
    stations[reqestor]["lastuse"] = computer.uptime()
    stations[useprovider]["lastuse"] = computer.uptime()
    modem.broadcast(dbport, dcode, "10-20", trainid, reqestor)    -- Notify all routers of the change
end

-- Do the main dispatchy stuff
local function goDispatch()
   -- sort the stations based on what we want to process requests for first
  table.sort(stations, function(a, b)
      if a["prioRequest"] ~= b["prioRequest"] then
        return a["prioRequest"] > b["prioRequest"]
      end

      -- Avoid always suppling/requesting from the same station
      return a["lastuse"] > b["lastuse"]
  end)
   
   -- loop over the stations (which are now in order)
   --  and process any requests for the station
   for s, sr in pairs(stations) do
      if requests[s] then
        -- print("procesing requests for ", s)
        for r, c in pairs(requests[s]) do
          -- Remove any in-progress deliveries
          if deliver[s] and deliver[s][r] then
            for t, v in pairs(deliver[s][r]) do
              c = c - v
            end
          end
          sendToBestProvider(r, c, s)
        end
      end
   end

  -- clean up / timesouts...
end

-- Regually send out notifications of where trains should be heading
--  this way the routers shouldnt need to call home
local function sendEngineStats()
  for trainid, v in pairs(trains) do
      if trains[trainid]["cargotype"] == "UNKNOWN" then
        modem.broadcast(dbport, dcode, "10-20", trainid, "DEPOT")
        -- TODO We should request a replacement train from the depot here
      elseif trains[trainid]["provider"] and not trains[trainid]["onway"] then
        modem.broadcast(dbport, dcode, "10-20", trainid, trains[trainid]["provider"])
      elseif trains[trainid]["requestor"] then
        modem.broadcast(dbport, dcode, "10-20", trainid, trains[trainid]["requestor"])
      else
        -- In all other cases the train should be at dispatch or will return to dispatch at the next router
        modem.broadcast(dbport, dcode, "10-20", trainid, "DISPATCH")
      end
  end
end

-- Handle when a train arrives at a station/depot
local function trainHere(trainid) 
  -- We dont know which station the train arrived at, but it arrived at a router and
  --   we assume that routers are only AFTER stations
  --   so if the train was heading for a provider we can now say it has picked up
  --   the providers items and will be heading to a requestor. The next stop the routers
  --   will set will be the dispatch again (they should always be one ahead)
  if not trains[trainid] then
      -- Hello. lets assume this is one of ours but we dont know the type
      --   so it needs to go back to the depot to be replaced
      newtrain(trainid, "UNKNOWN")
  end
  
  if not trains[trainid]["onway"] then
      -- mark the provider as free
      trains[trainid]["onway"] = true
      -- At this stage we have told it to head to the provider. Next stop would be the requestor
      modem.broadcast(dbport, dcode, "10-20", trainid, trains[trainid]["requestor"])
  elseif trains[trainid]["provider"] then
      -- mark the provider as free
      deliver[trains[trainid]["provider"]][trains[trainid]["item"]][trainid] = nil
      trains[trainid]["provider"] = nil
      -- When we see it next it will be at the requestor, so send a return command
      modem.broadcast(dbport, dcode, "10-20", trainid, "DISPATCH")
  elseif trains[trainid]["requestor"] then
      -- that should be the delivery complete
      deliver[trains[trainid]["requestor"]][trains[trainid]["item"]][trainid] = nil
      trains[trainid]["requestor"] = nil
      trains[trainid]["lastitem"] = trains[trainid]["item"]
      trains[trainid]["item"] = nil
      trains[trainid]["onway"] = false
      trains[trainid]["lastuse"] = computer.uptime()
      -- We can send an updated order at anytime now
      modem.broadcast(dbport, dcode, "10-20", trainid, "DISPATCH")
  end
end

local function drawGUI() 
  local curx, cury = term.getCursor()
  local screensize = term.getViewport() - 2
  term.setCursor(1, 1)
  term.clearLine()
  print("")

-- DRAW_GUI
  print(" ┌─[ Trains ]─" .. string.rep("─", screensize - 2 - 12) .. "┐")
  for k, v in pairs(trains) do
    local txtp = v.provider
    if not txtp then 
      txtp = ""
    end
    local txtr = v.requestor
    if not txtr then 
      txtr = ""
    end
    local txti = v.item
    if not txti then 
      txti = ""
    end
    if v.cargotype == "UNKNOWN" then
      txtr = "DEPOT"
    end
    print(string.format(" │ %4i%1.1s %10s %27s > %-27s │", k, v.cargotype, txti, txtp, txtr))
  end
  print(" └" .. string.rep("─", screensize - 2) .. "┘")
  
  term.clearLine()
  print("")
  print(" ┌─[ Requests ]─" .. string.rep("─", screensize - 2 - 14) .. "┐")
  for s, sr in pairs(stations) do
    print(string.format(" | %-" .. (screensize - 4) .. "s |", s))
    if requests[s] then
      for r, c in pairs(requests[s]) do
        print(string.format(" │ -> %-" .. (screensize - 7 - 6) .. "s %5i │", r, c))
      end
    end
  end
  print(" └" .. string.rep("─", screensize - 2) .. "┘")
  
  term.clearLine()
  print("")
  print(" ┌─[ Providers ]─" .. string.rep("─", screensize - 2 - 15) .. "┐")
  for r, c in pairs(provides) do
    print(string.format(" │ %-" .. (screensize - 4) .. "s │", r, ""))
  end
  print(" └" .. string.rep("─", screensize - 2) .. "┘")
  
  
  term.setCursor(curx, cury)
end

modem.open(dport)
modem.open(dbport)
if maxTrains > 0 then
  modem.open(depot_rcomms_port)
end


newtrain(45, "goods")

term.clear()
while true do
   -- check for events
   local e, mea, dst, prt, i1, station, cmd, msg1, msg2, msg3 = event.pull(60)
   if e == "modem_message" then
      if maxTrains > 0 and prt == depot_rcomms_port and station == "engineupdate" then
        -- This is the depot sending an update about a train that has been released
        if cmd then
--          print(e, prt, station, cmd, msg1)
          -- TECHNICALLY if msg1 is nil then we should delete the train
          --   but that code is not implemented in the depot so its not here as well
          --  FIXME ^^
          if msg1 then
              newtrain(cmd, msg1)
              depot_requestedtrain = false
          end
        end
       
      -- 10-68: dispatch info, each requested/provided item is sent and we assign to the tmp table until
      --  we get the 10-58 and we can confirm everything is valid
      --  A message with id of 0 = reset the tmp table
      elseif cmd == "10-68" then
        if msg1 == 0 then
           newinputs[station] = {}
        end
        if newinputs[station] then
          newinputs[station][msg2] = msg3
        end
      -- 10-58: start directing, assuming the number in the tmp table matches what the station says in this
      --  message then we convert the tmp table into its requests and providers
      elseif cmd == "10-58" then
         -- count how many items we receieved
         local seen = 0
         local newrequest = {}
         local newprovide = {}
         if msg1 == 0 or not newinputs[station] then
           -- Nothing requested or provided - we just need to ack and empty
           seen = 0
         else
           for k, v in pairs(newinputs[station]) do
             seen = seen + 1
             if v > 0 then
               newprovide[k] = v
             elseif v < 0 then
               newrequest[k] = -v
             end
           end
         end
         if seen ~= msg1 then
           -- print("10-9", seen .. " vs " .. msg1)
            -- If seen doesnt match then send back a 10-9 for retry. The next request should be a reset of the array
            modem.send(dst, dport, dcode, "10-9", seen)
         else
            -- If seen does match then setup the request table and add the new data to the providers
            requests[station] = newrequest
            -- remove all the existing provides for the station (so if the station runs out its no longer left around)
            for k, v in pairs(provides) do
               if provides[k][station] then
                  provides[k][station] = nil
               end
            end
            -- and now add each of the items back
            for k, v in pairs(newprovide) do
              if not provides[k] then
                provides[k] = {}
              end
               provides[k][station] = v
--               print(station .. " provides/requests " .. v .. " " .. k)
            end
            modem.send(dst, dport, dcode, "10-4", seen)   -- ACK

            -- Also in this message was some station settings we should update
            if not stations[station] then
               newstation(station, dst)
            end
            stations[station]["prioRequest"] = msg2
            stations[station]["prioProvide"] = msg3
         end
         -- Dont need the tmp table anymore
         newinputs[station] = nil

      -- 10-8: New station In-Service - mainly so a station can find us. let them know we are here
      --   and if we have not seen this station before lets take note of it now
      elseif cmd == "10-8" then
         modem.send(dst, dport, dcode, "10-2")   -- Good signal, here I am
         if prt == dport then
           if not stations[station] then
              newstation(station, dst)
           end
         elseif prt == dbport then
            sendEngineStats()
         end
      -- 10-75: Router has been in contact with - this indicates train arrived and we can update
      --    it to next destination
      elseif cmd == "10-75" then
          -- we dont ack the message since we send a broadcast with a new station update
          trainHere(msg1)
      
      --
      -- Add more codes here as we need them
      --
      else
          print("Ignored", cmd, " as unknown")
      end
   end
   -- If it has been over 60 seconds since our last update, do the magic
   if computer.uptime() > ntime then
      goDispatch()
      sendEngineStats()
      ntime = computer.uptime() + 10
      drawGUI()
   end
end
