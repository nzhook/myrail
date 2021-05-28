--[[ Display OpenComputers Event Signals
     Created for the Youtube channel https://youtube.com/user/nzHook 2019
]]--
local event = require("event")
--local component = require("component")
--component.modem.open(53)

local function debugvar(var, depth)
  if not depth then
    depth = 0
  end
  
  for k, v in pairs(var) do
    print (string.rep("-", depth * 2) .. k, v)
    if type(v) == "table" then
      debugvar(v, depth + 1)
    end
  end
end

while true do
  local e = {event.pull()}
  print("--")
  debugvar(e)
end
