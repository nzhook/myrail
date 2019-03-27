--[[ OC-LOGISTICS STATION - Debugging/setup utility to show raw names of currently stored items
     Author: nzHook
     Created for the Youtube channel https://youtube.com/user/nzHook 2019
     myRail Episode Showing Usage: NOT SHOWN (but part of https://www.youtube.com/watch?v=4gEuWiLwo1A )
     
     
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
local computer = require("computer")

if not component.transposer then
   print("This program uses transposers connect at least one")
   os.exit()
end

--
-- config
--
-- No config here, just run and update station.lua
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

local ihave = whatIHave()
print("Items stored locally...")
print("")
print("local requests = {}")
for k, c in pairs(ihave) do
   print("requests[\"" .. k .. "\"] = " .. c)
end
print("")
