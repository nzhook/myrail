--[[ Display OpenComputers Event Signals
     Created for the Youtube channel https://youtube.com/user/nzHook 2019
]]--
local event = require("event")
while true do
   local a, b, c, e, f, g, h = event.pull()
   print(a,b,c,d,e,f,g,h)
end
