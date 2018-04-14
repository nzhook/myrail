--[[ Rail yard train maker
     Created for the Youtube channel https://youtube.com/user/nzHook 2018
     myRail Episode Showing Usage: Not published yet
     
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
local serialization = require("serialization")
local filesystem = require("filesystem")
local os = require("os")

-- The sides of the transposer
local side_train = sides.right
local side_chest = sides.left
-- The slot in the train to put the ticket
--   in a steam engine this should be 4, in a creative its slot 1
-- TODO: Autodetect
local slot_train = 1
local slot_chest = nil
--- the sides of the redstone io
local side_track = sides.top
local side_release = sides.right

-- TODO: 
--  - Track where carts are stored
--  - Save/load positions
--  - Convert master instructions (wood, chest, chest) to position numbers
--  - Release final train
--  - Detect and request train details from master
--  - Detect arriving train to start shunting
--  - Main loop

local step = 0
local carts = {1, 1, 2}

while true do
  component.redstone.setOutput(side_track, 0)
	local e = event.pull(2)
	
  if component.transposer.getInventorySize(side_train) then
		step = step + 1
		if step > #carts then
			step = 0
			break
		end
		
		local slot_chest = carts[step]
		print(step .. " = " .. slot_chest)
    component.redstone.setOutput(side_track, 0)
    if slot_chest then
      component.transposer.transferItem(side_chest, side_train, slot_train, slot_chest)
      --os.sleep(1)
      component.transposer.transferItem(side_train, side_chest, slot_chest, slot_train)
    end
  
    -- trigger the train to move
    component.redstone.setOutput(side_track, 15)
  end


end


print("train complete")
component.redstone.setOutput(side_release, 15)
os.sleep(1)
component.redstone.setOutput(side_release, 0)
