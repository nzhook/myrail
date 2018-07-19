--[[ Flying Pig Mover OpenComputers Drone program
     Created for the Youtube channel https://youtube.com/user/nzHook 2018
     myRail Episode Showing Usage: https://youtu.be/UJOmeCY4zxk
     Released under a GNU General Public License v3 (full license text too large for Eeprom)
]]--
     
local leash = component.proxy(component.list("leash")())
local nav = component.proxy(component.list("navigation")())
local leashside = 0

local CHARGER, PIGS, PEN, cx, xy, cz = nil

function getWaypoints()
  cx, cy, cz = 0, 0, 0
  CHARGER, PIGS, PEN = {}, {}, {}
  local waypoints = nav.findWaypoints(64)
  for i=1, waypoints.n do
    if waypoints[i].label == "CHARGER" then
      CHARGER.x = waypoints[i].position[1]
      CHARGER.y = waypoints[i].position[2]
      CHARGER.z = waypoints[i].position[3]
    elseif waypoints[i].label == "PIGS" then
      PIGS.x = waypoints[i].position[1]
      PIGS.y = waypoints[i].position[2]
      PIGS.z = waypoints[i].position[3]
    elseif waypoints[i].label == "PEN" then
      PEN.x = waypoints[i].position[1]
      PEN.y = waypoints[i].position[2]
      PEN.z = waypoints[i].position[3]
    end
  end
end

function move(x, y, z, a)
	drone.setAcceleration(a)
  local dx = x - cx
  local dy = y - cy
  local dz = z - cz
  drone.move(dx, dy, dz)
  while drone.getOffset() > 0.7 or drone.getVelocity() > 0.7 do
    computer.pullSignal(0.2)
  end
  cx, cy, cz = x, y, z
end

getWaypoints()
computer.beep()
-- TODO: Add loop until Pen empty here
move(CHARGER.x, CHARGER.y, CHARGER.z, 100)
move(PIGS.x, PIGS.y + 10, PIGS.z, 100)
move(PIGS.x, PIGS.y + 1, PIGS.z, 100)
if leash.leash(0) then
		move(PIGS.x, PIGS.y + 15, PIGS.z, 10)
		computer.beep()
		move(PEN.x, PEN.y + 20, PEN.z, 100)
    computer.pullSignal(1)
		move(PEN.x, PEN.y + 5, PEN.z, 5)
		leash.unleash()
    computer.pullSignal(0.2)
else
		move(PIGS.x, PIGS.y + 2, PIGS.z, 100)
end
move(CHARGER.x, CHARGER.y + 2, CHARGER.z, 100)
move(CHARGER.x, CHARGER.y, CHARGER.z, 100)

return "Ok"
