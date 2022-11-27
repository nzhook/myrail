--[[ Random Spooky holograms
         Author: nzHook
         Created for the Youtube channel https://youtube.com/user/nzHook 2022
         myRail Episode Showing Usage: https://www.youtube.com/watch?v=mF17eDP9-i8

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
local os = require("os")

-- settings
local color = 0xFFFFFF0
local zoffset = 30
local rotation = 0

-- None of this art was created by me, unfortantly none of it had no credits
--  ASCII art was pretty big back before the internet (and its early days) which also 
--  makes tracking down credits difficult.  If you were the creator of any of this art
--  please contact me
local images = {
{
	color = 0xffffff,
	moves = 1,
	art = [[
                   ********
                 ***********
               ***************
              *****************
              *****************
             ********************
             ***   ********   ****
*           ***      *****     ****
***      *******   ********   *********  ***
 *********************  **********************
 ********************    **********************
 ********************    *********************
  ******************************************
   ***************************************
      ***********************************
       *********************************
         *****************************
           **************************
            ************************
            ***********************
             **********************
              ********************
               ******************
                 ***************
                   ***********
                    *********
                     ******
                     ****
                     **
                     * 
                    * 
]]
}, {
	color = 0x777700,
	moves = 0,
	art = [[
                      ***
                    **
                   **
                  **
                 ***
        *********************
     ***************************
   *************** ***************
 ********** ****** ****** *********
 *********   ***** *****   *********
*********     **** ****     ********
********       *** ***       ********
****************** ******************
*****************   *****************
********   ****************  ********
 *******                     *******
  ********                 ********
   ******************************
    ***************************
]]
}, {
	color = 0xff0000,
	moves = 1,
	art = [[
             *********             
         *****************         
       *********************       
      ***********************      
     *************************     
     **** *************** ****     
    ****   *************   ****    
   ****      *********      ****   
   ***   **   *******   **   ***   
   ***  ****   *****   ****  ***   
   ****  *   *** * ***   *  ****   
  ******   ****  *  ****   ******  
 ******** ****  ***  **** ******** 
 ************* ***** ************* 
 **** ** ****  *****  **** ** **** 
  *** ** **** *  *  * **** ** ***  
   * ** ******************* ** *   
     ** ****           **** **     
       **** *  *   *  * ****       
       **** *  *   *  * ****       
       *********************       
        *******************        
        *******************        
         ** * *** *** * **         
         *  * *** *** *  *         
              **   **              
              *     *              
]]
}
}

--
-- functions
--

-- similar to the holo-text example
local function draw(hologram, value, colorindex)
	if not hologram then
		return
	end
	hologram.setPaletteColor(1, value.color)

	local bm = {}
	for token in value.art:gmatch("([^\r\n]*)") do
		if token ~= "" then
			table.insert(bm, string.format("%-46s", token))
		end
	end
	local h, w = #bm, #bm[1]
	local ha, wa, pa = 10, 3, 2
	if h > 30 then
		ha = 4
		wa = 4
		pa = 2
	end
	-- because we need to be higher we only show half the image
	for i = 1, w, pa do
		for j = 1, h, pa do
			if bm[1+h-j]:sub(i, i) ~= " " then
				hologram.set((i / pa) + (w/wa) + 5, (j/pa) - 1 + (h/ha), zoffset, colorindex)
			end
		end
	end
end

-- code

-- When we see a redstone signal of 15, turn on
if component.list("redstone")() then
	component.redstone.setWakeThreshold(15)
end


local newimage = {}
local y = 0
local x = 0
local z = 1
local t = 1		-- force the first loop to do setup


-- move devices to starting positions
for holoid, _ in component.list("hologram") do
	local holo = component.proxy(holoid)
--	holo.setRotation(rotation, 0, rotation, 0)
	-- changing the scale makes it higher, but we need to keep it within size so in draw we half the shown pixels
	holo.setScale(2)
	holo.clear()
--	draw(holo, images[newimage + 1], 1)
end

-- we loop until the timer finishes
local endon = computer.uptime() + 120
while computer.uptime() < endon do
	-- do the spooky images
	--  TODO: Should we time these based on the cart passing?

	t = t + 0.1
	if t > 0.5 then
		t = -1
		x = t
		z = 1
		local w = false
		for holoid, _ in component.list("hologram") do
			local holo = component.proxy(holoid)
			holo.clear()
			if not w then
				os.sleep(1)
				w = true
			end

			newimage[holoid] = 0
			-- 1 in 2 chance we use this hologram projector
			if math.random(1, 2) == 1 then
				newimage[holoid] = math.random(0, #images - 1)
				holo.setTranslation(-0.50, z, x)
				draw(holo, images[newimage[holoid] + 1], 1)
			end
		end
	end
	for holoid, _ in component.list("hologram") do
		x = t
		z = 1
		if newimage[holoid] > 0 and images[newimage[holoid] + 1].moves > 0 then
			z = 0.4 + (math.sin(computer.uptime()) / 20)
			x = t
			local holo = component.proxy(holoid)
			holo.setTranslation(-0.50, z, x)

		end
	end

	os.sleep(0.1)
end

for holoid, _ in component.list("hologram") do
	local holo = component.proxy(holoid)
	holo.clear()
end

-- done, turn off to save power
computer.shutdown()
