--[[ Component name system (CNS) - Test script
     Author: nzHook
     Created for the Youtube channel https://youtube.com/user/nzHook 2021
     
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
-- Load the library (must be in /lib, /home or the script directory)
local cns = require("cns")

-- Should return the component id of the device named 'controller'
print (cns("controller"))

-- Should return the component id of the device named 'engines_in'
print (cns("engines_in"))

-- Should return the name of the device with the component ID of ccadc7fd-0ad1-47a9-819f-7586a3ba9a5f
print (cns("ccadc7fd-0ad1-47a9-819f-7586a3ba9a5f"))
