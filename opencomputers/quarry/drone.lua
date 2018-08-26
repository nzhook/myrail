--[[  Drone assisted Robot Quarry - Robot
     Created for the Youtube channel https://youtube.com/user/nzHook 2018
     myRail Episode Showing Usage: https://youtu.be/W9s4uPspkE0
     Released under a GNU General Public License v3 (full license text too large for Eeprom)
     NOTE: Only used via Fingercomp's net-flash program
]]--
local nav = component.proxy(component.list("navigation")())
local modem = component.proxy(component.list("modem")())
local inv = component.proxy(component.list("inventory_controller")())

local port = 1271
local bottom = 0      -- sides.bottom
local hover = 4

-- CODE
local STORAGE, TOOL, FUEL, CHARGER = nil

function getWaypoints()
  cx, cy, cz = 0, 0, 0
  STORAGE, TOOL, FUEL, CHARGER = {}, {}, {}, {}
  local waypoints = nav.findWaypoints(64)
  for i= 1, waypoints.n do
    -- the + 1 on tool, chest, and fuel is because we need to be on the block above to use the chest
    if waypoints[i].label == "charger" then
      CHARGER.x = waypoints[i].position[1]
      CHARGER.y = waypoints[i].position[2] + 1
      CHARGER.z = waypoints[i].position[3]
    elseif waypoints[i].label == "tool" then
      TOOL.x = waypoints[i].position[1]
      TOOL.y = waypoints[i].position[2] + 1
      TOOL.z = waypoints[i].position[3]
    elseif waypoints[i].label == "storage" then
      local tempTable = {}
      tempTable.x = waypoints[i].position[1]
      tempTable.y = waypoints[i].position[2]
      tempTable.z = waypoints[i].position[3]
      table.insert(STORAGE, tempTable)
    elseif waypoints[i].label == "fuel" then
      FUEL.x = waypoints[i].position[1]
      FUEL.y = waypoints[i].position[2] + 1
      FUEL.z = waypoints[i].position[3]
    end
  end
end

function realpos(x, y, z)
  local RET = {}
  local x,y,z = nav.getPosition()
  RET.x = x
  RET.y = y
  RET.z = z
  return RET
end

function move(x, y, z, a, txt)
  if txt == "waiting" then
    drone.setLightColor(0xff00ff)
  else
    drone.setLightColor(0x0000ff)
  end
  drone.setAcceleration(a)
  local dx = x - cx
  local dy = y - cy
  local dz = z - cz
  
  drone.setStatusText(txt)
  drone.move(dx, dy, dz)
  while drone.getOffset() > 0.7 or drone.getVelocity() > 0.7 do
    computer.pullSignal(0.2)
  end
  cx, cy, cz = x, y, z
end

getWaypoints()
computer.beep()


-- We need to move all of the waypoints and update with the correct co-ords
--   (waypoints are distance from drone)
move(CHARGER.x, CHARGER.y, CHARGER.z, 100, "charger")
CHARGER = realpos()

move(TOOL.x, TOOL.y, TOOL.z, 100, "tool")
TOOL = realpos()

move(FUEL.x, FUEL.y, FUEL.z, 100, "fuel")
FUEL = realpos()

local i
for i=1, #STORAGE do
  move(STORAGE[i].x, STORAGE[i].y + 1, STORAGE[i].z, 100, "storage")
  STORAGE[i] = realpos()
end
-- Update to our real pos
cx, cy, cz = STORAGE[#STORAGE].x, STORAGE[#STORAGE].y, STORAGE[#STORAGE].z

move(CHARGER.x, CHARGER.y, CHARGER.z, 100, "charger")

drone.setStatusText("Idle")
drone.setLightColor(0x00ff00)
modem.open(port)

local havetool = false
local function gettool()
      if not havetool then
        move(TOOL.x, TOOL.y, TOOL.z, 100, "tool get")
        drone.select(1)
        drone.suck(bottom, 1)
        havetool = true
        -- TODO What happens if we are out of picks?
      end
end

local function unloadrobot(startslot, maxslots)
  -- Just sucking from the robot pulls the tool so we need to give exact slot numbers
  local pulled = 0
  if maxslots > drone.inventorySize() - startslot then
    maxslots = drone.inventorySize() - startslot
  end
  for b = startslot, startslot + maxslots do
    drone.suck(bottom, 64)
    pulled = pulled + 1
  end
  return pulled
end

local function unloaddrone(txt)
    local curchest = 1
    move(STORAGE[curchest].x, STORAGE[curchest].y, STORAGE[curchest].z, 100, txt)
    for b = 1, drone.inventorySize() do
      while drone.count(b) > 0 do
        drone.select(b)
        if not drone.drop(bottom, 64) then
          curchest = curchest + 1
          if curchest <= #STORAGE then
            move(STORAGE[curchest].x, STORAGE[curchest].y, STORAGE[curchest].z, 100, txt)
          else
            break
          end
        end
      end
    end
end

local function split(input)
        local t={} ; i=0
        for str in string.gmatch(input, "([^,]+)") do
                t[i] = str
                i = i + 1
        end 
        return t
end


while true do
  local e = {computer.pullSignal(1)}
  if e[1] == "modem_message" and e[3] and e[6] == "circledig" then
  -- Every message has the status detail
        --  we monitor this detail so we can be ready and 
        --  close by when the need arises
  local rob = split(e[8])
  local started = split(e[9])
  --local qsize = e[10]
  local qsize = started[3]
  local dur = e[11]
  local inuse = e[12]
  local free = e[13] - inuse
  if e[7] == "status" then
    if dur < 0.2 then
      gettool()
      -- Hover above ready to pounce
      move(started[0] + (qsize / 2), started[1] + hover, started[2] + (qsize / 2), 100, "waiting")
    end
    if free < 2 then
      -- Hover above ready to pounce
      move(started[0] + (qsize / 2), started[1] + hover, started[2] + (qsize / 2), 100, "waiting")
    end
        elseif e[7] == "unload" then
    -- The inventory of a drone is smaller than a robot so it may take a couple of passes
    --  to fully unload
    while inuse > 0 do
      move(rob[0], started[1] + 4, rob[2], 100, "unloading")
      move(rob[0], rob[1] + 1, rob[2], 100, "unloading")
      inuse = inuse - unloadrobot(1, inuse)
      unloaddrone("unloading")
    end
    inuse = 0
      
    move(CHARGER.x, CHARGER.y, CHARGER.z, 100, "idle")
    elseif e[7] == "tool" then
      gettool()
    move(rob[0], started[1] + 4, rob[2], 100, "tool drop")
    move(rob[0], rob[1] + 1, rob[2], 100, "tool drop")
    -- We first unload the robot so there is room to drop the tool
    -- Then drop the tool for it to use
    unloadrobot(2, 3)
    drone.select(1)
    -- robots and drones dont like interacting with each other
    --  so we just drop the new pick. the robot does a suck()
    --  every check which wil pick it up
    --- FIXME: If OC ever fixes this this code should be rewritten
    drone.drop(bottom, 1)
    havetool = false
    
    -- return and unload
    unloaddrone("tool dropped")
    move(CHARGER.x, CHARGER.y, CHARGER.z, 100, "idle")
        end
  end
end
