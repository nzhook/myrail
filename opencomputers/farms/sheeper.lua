--[[ Robot Sheep Management Farm
     Created for the Youtube channel https://youtube.com/user/nzHook 2021
     myRail Episode Showing Usage: https://youtu.be/GXoH2_DkSwM
     
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
-- max and maxy are the maxiumthe robot will travel to work out sizes (in case someone forgot to put a side on the pen)
--  if your farm is larger than these two you may want to up these
local maxx = 100
local maxz = 100
-- bestsheepcount is the best amount to have in the pens, if less than this number was found the robot will try to
--  breed more. Default (nil) determines based on size of pen / 3  (3 squares per sheep)
local bestsheepcount = nil

-- The minimum number of stacks for each colour we should have (assuming 1 stack is 64 items, minstacks of 2 would result in attempting for 128 of each dye given)
local minstacks = 2

-- The thing we drop into the storage chest
local nameofwool = "minecraft:wool"


-- Mapping of wool colour to dye colour ids
-- wool > dye
-- NOTE: This applies to Minecraft 1.12, later versions changed the item names so this may need changing
local colorMap = {
  [0] = 15, -- White   (Bone Meal)
  [1] = 14, -- Orange 
  [2] = 13, -- Magenta
  [3] = 12, -- Light Blue 
  [4] = 11, -- Yellow
  [5] = 10, -- Lime
  [6] = 9, -- Pink
  [7] = 8, -- Gray
  [8] = 7, -- Light Gray
  [9] = 6, -- Cyan
  [10] = 5, -- Purple
  [11] = 4, -- Blue (Lapis)
  [12] = 3, -- Brown (Coco)
  [13] = 2, -- Green (Catcus)
  [14] = 1, -- Red
  [15] = 0  -- Black
}

-- these dont need to be changed
local robot = require("robot")
local sides = require("sides")
local component = require("component")
local computer = require("computer")

local ret, reason
local dir = 0

local sizex = 0
local sizez = 0
local currentx = 0
local currentz = 0
local lastsheepcount = -1
local currentstacks = {}
local lastswitch = 0

local function toot() 
  -- clear the queue
  while computer.pullSignal(1) do end
  -- toot then wait a little bit
  computer.beep()
  computer.beep()
  computer.pullSignal(3)
end

-- determine the size of the area
--   this is based on detecting blocks which would stop it
--   doesnt handle anything but a rectangle (x by z)
--  TODO If we detect chests to the left or right we should reoritenate and start again

-- NOTE This whole process can be slow if sheep are in the way as the robot will keep trying until it can move into a slot
--        recomended getting our there with some wheat to pull the sheep away until the robot returns to operating height

-- first thing we do is drop to the ground and then rise up 2 so we are at the collect level
local ready = false
while(not ready) do
  ret, reason = robot.down()
  -- we need handle if an entity gets in the way
  if(not ret) then
    if reason ~= "entity" then
      -- we must be at ground level (or out of power)
      ready = true
    else
      toot()
    end
  end
end

-- move up two to ensure we have enough space above
for i = 1, 2 do
  local ready = false
  while(not ready) do
    ret, reason = robot.up()
    -- we need handle if an entity gets in the way
    if(not ret) then
      if reason ~= "entity" then
        computer.beep()
        computer.beep()
        computer.beep()
        error("Not enough room to move up, I need at least three blocks (2 blocks for sheep + 1 for me)")
      end
    else
      ready = true
    end
  end
end

-- move back down for measurements because its more reliable to detect
local ready = false
while(not ready) do
  ret, reason = robot.down()
  -- we need handle if an entity gets in the way
  if(not ret) then
    if reason ~= "entity" then
      -- we must be at ground level (or out of power)
      ready = true
    else
      toot()
    end
  end
end
computer.beep()

-- move forward until we find the block that gets in our way (this would be the side of the pen)
--  we dont count this one as we may have started in the middle
--- -------
--- -  >> -
--- -     -
--- -     -
--- -------

ready = false
sizex = 1
while(not ready) do
  -- at this point just keep moving forward if the move fails work out if its a block or entity
  ret, reason = robot.forward()
  if reason then
    if reason ~= "entity" then
      ready = true
    else
      toot()
    end
  else
    sizex = sizex + 1 
    if(sizex > maxx) then
        error("Moved more than maximum X")
    end
  end
end

-- so we are on one edge, try to find the corner
--- -------
--- -    v-
--- -    v-
--- -     -
--- -------
robot.turnLeft()
ready = false
sizez = 1
while(not ready) do
  -- at this point just keep moving forward if the move fails work out if its a block or entity
  ret, reason = robot.forward()
  if reason then
    if reason ~= "entity" then
      ready = true
    else
      toot()
    end
  else
    sizez = sizez + 1
    if(sizez > maxz) then
        error("Moved more than maximum Z")
    end
  end
end

-- we should be in the corner now, we can start to work out the size
robot.turnLeft()
robot.turnLeft()


-- work out x first as we know the direction we just came from will be clear
--- -------
--- -     -
--- -    ^-
--- -    ^-
--- -------
ready = false
sizex = 1
while(not ready) do
  -- at this point just keep moving forward if the move fails work out if its a block or entity
  ret, reason = robot.forward()
  if reason then
    if reason ~= "entity" then
      ready = true
    else
      toot()
    end
  else
    sizex = sizex + 1
    if(sizex > maxx) then
        error("Moved more than maximum X")
    end
  end
end


-- work out z by going back in the reverse directioin from when we started
--- -------
--- - <<  -
--- -     -
--- -     -
--- -------
robot.turnRight()
ready = false
sizez = 1
while(not ready) do
  -- at this point just keep moving forward if the move fails work out if its a block or entity
  ret, reason = robot.forward()
  if reason then
    if reason ~= "entity" then
      ready = true
    else
      toot()
    end
  else
    sizez = sizez + 1
    if(sizez > maxz) then
        error("Moved more than maximum Z")
    end
  end
end

-- we should now have the x and z sizes, we can move back to production level
for i = 1, 2 do
  local ready = false
  while(not ready) do
    ret, reason = robot.up()
    -- we need handle if an entity gets in the way
    if(not ret) then
      if reason ~= "entity" then
        error("Not enough room to move up, I need at least three blocks (2 blocks for sheep + 1 for me)")
      end
    else
      ready = true
    end
  end
end


robot.turnLeft()
robot.turnLeft()
computer.beep()

print(sizex .. "x" .. sizez)
if not bestsheepcount then
  bestsheepcount = (sizex * sizez) / 3
  print("best count in pen", bestsheepcount)
end

-- turns in the appropriate direction based on current direction
local function doTurn() 
  if dir == 0 then
    robot.turnLeft()
    robot.forward()
    robot.turnLeft()
    dir = 1
  else
    robot.turnRight()
    robot.forward()
    robot.turnRight()
    dir = 0
  end
end

-- returns the best item to pick from the chest in front
--  this is the only place you need to update item names if not using vanila items
--   as the returns are generic to the code
local function getBestItem(side)
  local slot = 0
  -- assume the best item is wool
  local bestslot = 0
  local bestweight = 0
  local bestitem = "wool"
  local bestsize = 0
  
  local timesincelast = computer.uptime() - lastswitch
  
  -- find out what we currently hold (this means switching the equiped item with the current slot for a moment)
  component.inventory_controller.equip()
  local currentitem = component.inventory_controller.getStackInInternalSlot()
  component.inventory_controller.equip()
  -- if the slot was equiped then set the name, other set it the nil to an empty string (so we can print it during debugging)
  if currentitem then
    currentitem = currentitem.name
    print("I am holding " .. currentitem)
  else
    currentitem = ""
  end
  
  local foundinstruction = false
  -- setting size here avoids us calling the component everytime which 'could' be power intensive
  local size = component.inventory_controller.getInventorySize(side)
  local inv = component.inventory_controller.getAllStacks(side)
  for slot = 1, size do
    local item = inv[slot]
    if item then
      if item.name == nameofwool then
        -- same as an empty slot but we know we dont need to go any further so just return
        return 0, 0, "wool", item.maxSize - 1
      elseif item.name == "minecraft:dye" then
        foundinstruction = true
        -- dye is for changing colours when we hit the stack limit
        if bestweight < 1 then
          if not currentstacks[item.damage] then
            currentstacks[item.damage] = 0
          end
          print("Dye: Last seen stack count for " .. item.name .. ":" .. item.damage .. " was " .. currentstacks[item.damage] .. "/" .. minstacks .. ", this chest has " .. item.size)
          
          -- we only want to change to dyes once we have done at least one loop (so seen the chest for storage)
          if lastsheepcount > 0 and currentstacks[item.damage] < minstacks and item.size > 1 and timesincelast > 120 then
            -- compare currentStack counter to requirements
            ---- robot.setLightColor(hex)
            
            -- TODO Should we re-order the chest so that when we put the dye back it would be at the end? or do we just try for the same colour until we have enough
            
            
            
            bestweight = 1
            bestitem = "dye"
            bestslot = slot
            bestsize = item.size - 1
          end
        end
      elseif item.name == "minecraft:shears" then
        foundinstruction = true
        -- shears are always the highest item to replace IF we dont current have one (because it broke or we have just done another type of run) or its low on durablity
        --  durablility() returns 0 to 1 with 1 being 100%, change to something like 0.1 to make the robot swap a nearly broken set of shears with a new one
        --   NOTE: There is not a check to pick the best (or worst) shears so if you do change the durablity you may want to add the rule for which to make more preferable
        if bestweight < 3 then
          local dur = robot.durability()
          if not dur then
            dur = 0
          end
          print("Shears: I have " .. currentitem .. " with " .. dur .. " durability")
          if (currentitem ~= "minecraft:shears" or dur <= 0) and timesincelast > 60 then
            bestweight = 3
            bestitem = "tool"
            bestslot = slot
            bestsize = 1    -- these only stack to 1, but we wouldnt need more than 1 anyway
            
            -- since the bestweight is 3 we dont need to continue scanning
            break
          end
        end
      elseif item.name == "minecraft:wheat" then
        foundinstruction = true
        -- wheat is for growing the number of sheep if there are less than the bestsheepcount
        if bestweight < 2 then
          -- if lastsheepcount is -1 this would be the first run and we dont want to breed them just yet
          --  TODO If we have less than 2 then we should goto into sleepy mode and only ever count sheep until the number increases
          print("Wheat: Last sheep count " .. lastsheepcount .. " vs best " .. bestsheepcount)
          if lastsheepcount > 1 and lastsheepcount < bestsheepcount  and item.size > 1 and timesincelast > 120 then
            bestweight = 2
            bestitem = "food"
            bestslot = slot
            bestsize = item.size - 1
          end
        end
      end
    else
      -- slot is empty, assume its a wool slot
      if bestweight < 0 then
        bestweight = 0
        bestitem = "wool"
        bestslot = slot
        bestsize = 64
      end
    end
  end
  if foundinstruction and bestweight < 1 then
    -- there was a control item but we didnt need it so we only want to return air (so its ignored) not wool
    return 0, -1, "air", 0
  end
  
  return bestslot, bestweight, bestitem, bestsize
end


-- okay into the main loop
-- we should start facing the firstion we are going so the turns are at the end
while true do
  local sheepcount = 0
  for currentx = 1, sizex - 1 do
    for currentz = 1, sizez - 1 do
      ret, reason = robot.detectDown()
      if ret then
        if reason == "entity" then
          -- use the shears
          robot.useDown()
          sheepcount = sheepcount + 1
        end
      end
      while not robot.forward() do
        -- something is blocking the movement but we are inside the area? just try and keep moving
        toot()
      end
    end
    
    -- Look for a chest at the end of the row
    if robot.detect() then
      -- all we know is something was detected
      if component.inventory_controller.getInventorySize(sides.front) > 0 then 
        -- if it is a charger wait until we are charged otherwise assume it is a chest
        if component.inventory_controller.getInventoryName(sides.front) == "opencomputers:charger" then 
          if computer.energy() < computer.maxEnergy() * 0.5 then
            local started = computer.uptime()
            print("Filling up on engery")
            computer.beep()
            while computer.energy() < computer.maxEnergy() - 10 and computer.uptime() < started + 100 do
              -- wait for it to supply the energy or 100 seconds pass
              computer.pullSignal(5)
            end
          end
        else
          -- it has an inventory determine if we should pick up or drop off
          local slot, weighted, item, pullsize = getBestItem(sides.front)
          print("INVENTORY", item, pullsize)
          if item == "air" then
            -- we dont to do anything with this chest at this time
          elseif item == "wool" then
            -- This is a drop off chest, drop what we have then count the different wool types (to work out if we have maxstacks)
            --  checking the item count might take more memory put we only want to drop off wool
            for slot = 1, robot.inventorySize() do
              robot.select(slot)
              local currentitem = component.inventory_controller.getStackInInternalSlot()
              if currentitem and currentitem.name == nameofwool then
                -- drop it all
                if not robot.drop() then
                  print("Failed to insert wool, is the chest full?")
                  while computer.pullSignal(1) do end   -- wait for the queue to clear
                  while not robot.drop() do
                    computer.beep(300, 0.3)
                    computer.beep(275, 0.3)
                    computer.beep(250, 0.5)
                    computer.pullSignal(3)
                  end
                  computer.beep(550, 0.1)
                  computer.beep(575, 0.1)
                  computer.beep(600, 0.2)
                  print("issued fixed, moving on")
                end
              end
            end
          
            local size = component.inventory_controller.getInventorySize(sides.front)
            local inv = component.inventory_controller.getAllStacks(sides.front)
            -- reset currentstacks
            --   TODO: Should we handle multiple chests?
            currentstacks = {}
            for slot = 1, size do
              local item = inv[slot]
              if item and item.name == nameofwool and item.size >= item.maxSize then
                if not currentstacks[colorMap[item.damage]] then
                  currentstacks[colorMap[item.damage]] = 0
                end
                currentstacks[colorMap[item.damage]] = currentstacks[colorMap[item.damage]] + 1
              end
            end
          else
            -- Swap the currently equiped item with the suggested one
            component.inventory_controller.equip()
            
            -- drop the current tool, doesnt matter where it goes to (be aware if the chest is full this may drop the item into the world)
            robot.drop()
            
            -- pullsize will have been defined to try and keep one in stock
            component.inventory_controller.suckFromSlot(sides.front, slot, pullsize)
            component.inventory_controller.equip()
            
            lastswitch = computer.uptime()
          end
        end
      end
    end
    
    -- at each end we need to turn a different direction to get to the next row
    if currentx < sizex - 1 then
      doTurn()
      -- TODO check for a chest again but this time it would be behind us (and sides.back doesnt work as it accesses the internal chest)
    else
      -- Unless its the end of the pen at which point we just want to about turn so we are facing the way we came
      robot.turnLeft()
      robot.turnLeft()
    end
    -- Yeild to any signals
    while computer.pullSignal(1) do end
end
  computer.beep(900)
  computer.beep(950)
  lastsheepcount = sheepcount
  print("There were " .. lastsheepcount .. " uses")
end
