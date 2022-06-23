--[[ Basic Signal controller for stations
     Created for the Youtube channel https://youtube.com/user/nzHook 2022
     myRail Episode Showing Usage: NOT PUBLISHED
     NOTE: Requires:
       - Computronics, one signal controller and one signal receiver
       - Normal signals setup, named and linked to those controllers
     To use:
       - Place a signal controller and/or make a signal block
       - Place receivers, Distant signals or Switch acuator motors and link them to
           the digital controller / receiver (do not link them to each other)
       - Use a signal label to match the controllers to the receivers
          eg. label the controller and receivers for the first platform 'Platform 1'
              label the controller and receivers for the second platform 'Platform 2'
       - Run this code, when the aspect of the controller changes ALL the receivers will too
       
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

local event = require("event")
local component = require("component")

while true do
  local e, _, platformName, aspect = event.pull(10, "aspect_changed")
  -- WARNING: An aspect of OFF (6) will cause the controler to throw an error so we wont change the controller
  --   you could add an else set to red to avoid collisions in that case
  if e then
    component.digital_controller_box.setAspect(platformName, component.digital_receiver_box.getAspect(platformName))
  end
end










