-- Author: nzHook - http://youtube.com/nzhook
-- Licensed as GNU, license removed for use in EEPROM - please see License file on github
local sidetop1 = 2
local sidebot1 = 3
local sidetop2 = 4
local sidebot2 = 5
local sidedone = 1
local chestSide = 0
local trainSide = 1
local trainSlot = 1
local rsmax = 14
local dbport = 1123
local dcode = "DISPATCH99"

local modem = component.proxy(component.list("modem")())
local inv = component.proxy(component.list("transposer")())

local engines = {}
local slots = {}

-- Update where the tickets are stored - not when a train is passing over
local function updateslots() 
   for slot = 1, inv.getInventorySize(chestSide) do
      local i = inv.getStackInSlot(chestSide, slot)
      if i and i.label then
        slots[i.label] = slot
      end
   end
end
updateslots()

modem.open(dbport)
computer.beep(300, 0.1); computer.beep(400, 0.1); computer.beep(300, 0.1)

modem.broadcast(dbport, "ROUTER", "10-8")

while true do	
  local e = {computer.pullSignal(5)}

  -- Inbound train
  local sc
  if e[1] == "redstone_changed" then
      -- e3 = side, e4 = old rs, e5 = new rs
      if e[3] == sidedone and e[5] > 0 then
        if cT and cB then
          -- This needs to match engine_num the dispatcher
          local engineid = (cB * 10) + cT + 1
          
          if engines[engineid] and engines[engineid].last - computer.uptime() < 120 then
            sc = engines[engineid].slot
            if slots[sc] then
              modem.broadcast(dbport, "ROUTER", "10-75", engineid)
              sc = slots[sc]
            else
              -- Cant handle the request here (no ticket)
              sc = 1
            end
          else
            -- Not sure, Inform dispatch and send back
            sc = 1
            modem.broadcast(dbport, "ROUTER", "10-75", engineid)
          end
          if sc then
            inv.transferItem(chestSide, trainSide, trainSlot, sc)
            inv.transferItem(trainSide, chestSide, sc, trainSlot)
          end
        end
      elseif (e[3] == sidebot1 or e[3] == sidebot2) and e[4] == 0 then
        cB = rsmax - e[5]
      elseif (e[3] == sidetop1 or e[3] == sidetop2) and e[4] == 0 then
        cT = rsmax - e[5]
      end
  -- Engine status update
  elseif e[1] == "modem_message" and e[6] == dcode and e[7] == "10-20" then
        engines[e[8]] = {}
        engines[e[8]].slot = e[9]
        engines[e[8]].last = computer.uptime()
  end
end
