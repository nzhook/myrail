--[[ Station Ticket Gate Interface (for use with controller)
     Created for the Youtube channel https://youtube.com/user/nzHook 2019
     myRail Episode Showing Usage: https://www.youtube.com/watch?v=8byccypmjN0
     
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
---
-- How to use
--   -- Make sure ticket_controller.lua is configured and on a different computer/server in the same network
--   -- Connect Screen teir 2 or higher (for touch screen), transpser connected to two chests (one for payment the other for storage)
--   -- You will also need a printer from OpenPrinters with supplies (paper and ink) on top of a transposor
--   -- Configure the settings below as appropriate (remember some settings such as controllerid, networkname and password must match the controller)
--   -- Remember the printer must be above a tranposer
--   -- Start the code (add it to .rc.sh for it to start on reboot)
---
local c = require("component")
local event = require("event")
local term = require("term")
local sides = require("sides")
local computer = require("computer")
local gpu = c.gpu
local modem = c.modem
local transposer      -- we determine this based on what is placed around the main one
local printer = c.openprinter

-- The name of this station (shown in titles)
local stationname = "Theme Station"

-- The port to listen and respond to the controller on
local commsport = 1229
-- All outbound requests must have this password (for basic security)
local password = "S0mthingUnique"
-- The controllers modemid (eg. where messages are sent to)
-- @TODO Do we want the normal broadcast if not set here for an easier setup?
--   maybe do it once then save that address? - would mean it couldnt run an on an eeprom in the future
local controllerid = "8ea34d0d-5251-4f4d-bb5c-6958debb36cb"

-- These are all controlled per station (so one station could have a discount while not affecting the others)
-- What is the currency item
local costitem = "Diamond"
local costitemid = "minecraft:diamond"

-- The side of the transposer which has the payment chest on it
local sidepayment = sides.back
-- The side of the transposer which the payment is moved to (eg. for later collection)
local sidestorage = sides.front
-- The blockid of the chest that is used for storage (the transposer which see this on its sidestorage becomes the main transposer)
local storagechesttype = "minecraft:chest"
-- The side of the transposer where the printer is
-- WARNING: in 1.10.2 openprinters is a sided inventory, printed tickets must be pulled from the bottom (top of the transposer)
--   other sides present other items, eg. pulling from the top returns the paper
local sideprinter = sides.top

-- should the Purchase new ticket be available? (eg. there is a printer to print a new ticket)
local shownew = true
-- should the Update existing ticket be available? (eg. there is a transposer that can read the players offhand)
local showupdate = true
-- Use the connected transposers to look for a ticket in a players offhand (ticketinslot)
--   (if set to false will use storagechest)
local updateusetransposer = true

-- When doing a top up the slot to check in the players inventory for a valid ticket (5 = offhand) 
local ticketinslot = 5

-- ID to prefix all generated ticketids with - this is stored in the tables
--   but is not used to validate the ticket
--   so could be used to identify the station that generated the ticket
local ticketprefix = "NZH"

-- The name of this train network (printed on tickets but not stored)
local networkname = "myRail ticket"

-- The two modifiers -- see below
local costmultiplytrip = 0.75
local costmultiplydest = 0.50

-- how many items does 1 trip cost 
  -- buying multiple trips at once uses costmultiplytrip of 1 trip (so 0.75 = 25% off)
  -- muliline tickets are multipled by costmultiplydest per extra line (so 0.50 = half price)
  -- so final price = costpertrip * (trips * costmultiplytrip) * (lines * costmultiplydest)
  -- note the cost is rounded up (so 0.5/trip = 1, this would mean buying 2 trips is the same price as 1 trip)
local costpertrip = 0.7

--
-- Config options end here
--
-- Var init
local guiw, guih = 0
local doloop = true

--
-- My button interface
--
local buttons = {}
-- Add a button to the list
  -- text = The label
  -- call = Function to call
  -- side = 0=auto,1=middle,2=left,3=right
  -- extraparams = Anything for internal use (button is passed into call with this value available)
  -- othercolor = If set will display in this color (eg. for a cancel button)
local function button(text, call, side, extraparams, othercolor)
	local bdetail = {}
	bdetail["text"] = text
	bdetail["side"] = side
	bdetail["call"] = call
	bdetail["params"] = extraparams
	bdetail["othercolor"] = othercolor
	-- These are worked out on display but lets set them here
	bdetail["row"] = nil
	bdetail["xl"] = nil
	bdetail["xr"] = nil
	bdetail["yt"] = nil
	bdetail["yb"] = nil
	bdetail["size"] = nil
	
	table.insert(buttons, bdetail)
end

-- Calculate the positions and display (centered)
  -- x=start from this col
  -- y=start from this row
local function displaybuttons(x, y)
	-- determine the largest button size
	local bigbut = 0
	local numrows = 0
	local prevside = 3

	for text,bdetail in pairs(buttons) do
		-- 0 = side by side
		-- 1 = center only (will always create a new line)
		-- 2 = left only (may combine with a right)
		-- 3 = right only (will always create a new line)
		if bdetail["side"] == 1 and prevside == 2 then
			-- When centered and the last line didnt make a new row make a new row
			numrows = numrows + 1
		elseif bdetail["side"] == 2 and prevside == 2 then
			-- If the previous button was also left aligned we need to move down one
			numrows = numrows + 1
		end
		buttons[text]["row"] = numrows
		if bdetail["side"] == 1 then
			-- center, always reset
			numrows = numrows + 1
		else
			-- auto, left or right
			if bdetail["side"] == 0 then
				-- auto - determine the side before doing the magics
				if prevside == 2 then
					bdetail["side"] = 3
				else
					bdetail["side"] = 2
				end
				buttons[text]["side"] = bdetail["side"]
			end
			-- nows its only left or right
			if bdetail["side"] == 3 then
				numrows = numrows + 1
			end
		end

		prevside = bdetail["side"]

		-- This is at the bottom for ading debug info
		if buttons[text]["text"] then
			tmptext = buttons[text]["text"]
			if(string.len(tmptext) + 2 > bigbut) then
				bigbut = string.len(tmptext) + 2
			end
		end
	end
	-- Last position should always be centered if its the only one on the line
	-- TODO: What happens to the previous left button when a button is centered? - should this apply in all cases
	if prevside ~= 3 then
		buttons[#buttons]["side"] = 1
	end 
	-- If the biggest button is an odd number it causes the border's to be off by 1
	if bigbut % 2 ~= 1 then
		bigbut = bigbut + 1
	end

	-- Assign the positions and draw
	local middle = math.floor((guiw - x) / 2)
	local startl = middle - bigbut - 2
	local startr = middle + 2

	local startrow = (math.ceil((guih - y) / 2) - math.ceil(numrows * 2)) + y
	local counter = 0
	for text, bdetail in pairs(buttons) do
		local endp
		local startp
		counter = counter + 1
		local len
		if bdetail["text"] then
			len = string.len(bdetail["text"])
		else
			len = 1
		end
		local row = (bdetail["row"] * 4) + startrow
		if bdetail["side"] == 3 then		-- right
			endp = middle + bigbut + 1
			startp = startr
		elseif bdetail["side"] == 1 then	-- center
			endp = middle + math.floor(bigbut/2)
			startp = middle - math.floor(bigbut/2)
		else
			endp = middle - 3
			startp = startl
		end

		buttons[text]["xl"] = startp
		buttons[text]["xr"] = endp
		buttons[text]["yt"] = row - 1
		buttons[text]["yb"] = row + 1
		buttons[text]["size"] = bigbut			-- for quick access later

		if bdetail["text"] then
			if bdetail["othercolor"] then
				gpu.setBackground(bdetail["othercolor"])
			else
				gpu.setBackground(0xffff00)
			end
			gpu.setForeground(0x000000)
	--		gpu.set(startp, row - 1, string.rep(" ", bigbut))
			gpu.set(startp, row, " " .. bdetail["text"] .. string.rep(" ", (bigbut - len) - 1))
	--		gpu.set(startp, row + 1, string.rep(" ", bigbut))
			gpu.setForeground(0xffffff)
			gpu.setBackground(0x000000)
			gpu.set(startp - 1, row, "│")
			gpu.set(endp + 1, row, "│")
			gpu.set(startp - 1, row - 1, "┌" .. string.rep("─", bigbut) .. "┐")
			gpu.set(startp - 1, row + 1, "└" .. string.rep("─", bigbut) .. "┘")
		end
	end
	gpu.setForeground(0x00ff00)
	gpu.setBackground(0x000000)
end
-- Take care when someone presseses one of the buttons
local function buttontoucher(e)
	if not e[1] then 
		return true
	end
	if e[1] ~= "touch" then
		return false
	end
	local x = e[3]
	local y = e[4]
	for text, bdetail in pairs(buttons) do
		if not bdetail["xl"] then
			-- The buttons were not shown
			return
		end
		if x >= bdetail["xl"] and x <= bdetail["xr"] 
			and y >= bdetail["yt"] and y <= bdetail["yb"] then
				-- thats a valid button click highliht it then call the function
				gpu.setBackground(0xff0000)
				gpu.setForeground(0x000000)
				gpu.set(bdetail["xl"], bdetail["yt"] + 1, " " .. bdetail["text"] .. string.rep(" ", bdetail["size"] - string.len(bdetail["text"]) - 1))
				gpu.setForeground(0x00ff00)
				gpu.setBackground(0x000000)
				
				if(bdetail["call"]) then
					bdetail["call"](bdetail)
				end
				return true
		end
	end
	return false
end
--
-- end of the button stuff
--

-- The general page template/display
local function template(title, subtitle, color)
	-- Unset the existing buttons
	buttons = {}

	term.clear()
	guiw, guih = gpu.getResolution()
	if not color then
		gpu.setForeground(0x00ff00)
	else
		gpu.setForeground(color)
	end
	gpu.setBackground(0x000000)
	gpu.set(1, 1, " ┌" .. string.rep("─", guiw - 4) .. "┐")
	gpu.set(1, guih, " └" .. string.rep("─", guiw - 4) .. "┘")

	for i = 2, guih - 1 do
		  gpu.set(2, i, "│")
		  gpu.set(guiw - 1, i, "│")
	end
	gpu.setForeground(0xffff00)
	term.setCursor(math.floor((guiw - string.len(title)) / 2), 2)
	print(title)

	gpu.setForeground(0xffffff)
	term.setCursor(math.floor((guiw - string.len(subtitle)) / 2), 4)
	print(subtitle)
end

-- Communicate with the controller for detail
local function askcontroller(action, d1, d2, d3, d4)
	modem.send(controllerid, commsport, password, action, d1, d2, d3, d4)
	local e = {event.pull(120, "modem_message")}
	if not e or not e[1] then
		template("CONTROLLER ERROR", "Controller on " .. controllerid .. " is not responding", 0xff0000)

		local error = "Please report to management"
		term.setCursor(math.floor((guiw - string.len(error)) / 2), 6)
		print(error)
		return false
	end

	if e[3] ~= controllerid then
		template("CONTROLLER ERROR", "Controller response is not as expected", 0xff0000)
		local error = "Please report to management"
		term.setCursor(math.floor((guiw - string.len(error)) / 2), 6)
		print(error)
		return false
	end

	return e[6], e[7], e[8], e[9], e[10]
end


local function drawchest(arrowhead)

		if arrowhead == "down" then
			gpu.setForeground(0xffff00)
			gpu.set((guiw - 8) / 2, guih - 14, "  ░░░░░   ")
			gpu.set((guiw - 8) / 2, guih - 13, "  ▒▒▒▒▒   ")
			gpu.set((guiw - 8) / 2, guih - 12, "  ▓▓▓▓▓   ")
			gpu.set((guiw - 8) / 2, guih - 11, "  █████   ")
			gpu.set((guiw - 8) / 2, guih - 10, "▄▄█████▄▄ ")
			gpu.set((guiw - 8) / 2, guih - 9 , " ▀█████▀  ")
			gpu.set((guiw - 8) / 2, guih - 8,  "   ▀█▀    ")
		elseif arrowhead == "up" then
			gpu.setForeground(0x00ff00)
			gpu.set((guiw - 8) / 2, guih - 14, "   ▄█▄    ")
			gpu.set((guiw - 8) / 2, guih - 13, " ▄█████▄  ")
			gpu.set((guiw - 8) / 2, guih - 12, "▀▀█████▀▀ ")
			gpu.set((guiw - 8) / 2, guih - 11, "  █████   ")
			gpu.set((guiw - 8) / 2, guih - 10, "  ▓▓▓▓▓   ")
			gpu.set((guiw - 8) / 2, guih - 9 , "  ▒▒▒▒▒   ")
			gpu.set((guiw - 8) / 2, guih - 8 , "  ░░░░░   ")
		end

		gpu.setForeground(0xffff00)
		gpu.set((guiw - 8) / 2, guih - 6, "┌───────┐")
		gpu.set((guiw - 8) / 2, guih - 5, "├───────┤")
		gpu.set((guiw - 8) / 2, guih - 4, "│       │")
		gpu.set((guiw - 8) / 2, guih - 3, "└───────┘")
end

function maketicket(ty, dest, trips, ticketid, cost) 
	template(stationname .. " - Printing", "Thank you, please wait")
	drawchest("")

	local newticket = false
	-- For a new ticket generate the ID now so if there is a failure we have not stolen the funds
	if not ticketid then
		local responseid
		newticket = true
		-- reserve a new ticket id from the controller
		responseid, ticketid = askcontroller("maketicketid", ticketprefix)
		if responseid ~= "generated" or not ticketid then
				template("TICKETID ERROR", "There has been an issue generating a new ticket ID", 0xff0000)

				local error = "Please report to management"
				term.setCursor(math.floor((guiw - string.len(error)) / 2), 6)
				print(error)
 
				-- On failure we want to stay on this screen for a while
				event.pull(600, "kklkl")
				return
		end
	end

	--- @todo Move the item out of the payment chest and into the merchant one


	-- setup the new ticket
	if newticket then
		local responseid, usesleft, dests = askcontroller("purchaseticket", ticketid, dest, trips, cost .. " " .. costitemid)
		if responseid ~= "ticket" then
				template("TICKETPURCHASE ERROR", "There has been an error issuing the ticket", 0xff0000)

				local error = "Please report to management"
				term.setCursor(math.floor((guiw - string.len(error)) / 2), 6)
				print(error)
 
				-- On failure we want to stay on this screen for a while
				--- @todo should we put the items back?
				event.pull(600, "kklkl")
				return
		end

		template(stationname .. " - Printing", "Thank you, your ticket is being printed")
		drawchest("")

		--- print the ticket
    printer.clear()
    printer.writeln(networkname)
    printer.writeln(string.rep("=", string.len(networkname)))
    printer.writeln("")
    printer.writeln("Hold this in your off-hand")
    printer.writeln("when passing a protected gate")
    printer.writeln("")
    printer.writeln("This ticket is valid for")
    printer.writeln(dest)
    printer.writeln("")
    printer.writeln("")
    printer.writeln("Original purchase receipt:")
    printer.writeln("st: " .. stationname)
    printer.writeln("co: " .. cost .. "x" .. costitem)
    
    printer.setTitle(networkname .. " " .. ticketid)
    if not printer.print() then
				template("TICKETPURCHASE ERROR", "There has been an error printing your ticket", 0xff0000)

				local error = "Please report to management"
				term.setCursor(math.floor((guiw - string.len(error)) / 2), 6)
				print(error)
 
				-- On failure we want to stay on this screen for a while
				--- @todo should we put the items back?
				event.pull(600, "kklkl")
				return
    end

    -- Take the ticket from the printer and move it to the payment chest
    --  WARNING: Openprinters in 1.10.2 is sided, so items must be puilled from its bottom
    --   if you dont have the printer on top of the transposer set sideprinter to nil or 0
    --   and extract a different way
    if sideprinter then
      local taken = transposer.transferItem(sideprinter, sidepayment, 1, 1)
    end

		template(stationname .. " - Printed", "Thank you, please take your ticket from the chest")
		drawchest("up")
	else
		-- Increase the use count on the ticket
		local responseid, usesleft, dests = askcontroller("purchaseticket", ticketid, dest, trips, cost .. " " .. costitemid)
		if responseid ~= "ticket" then
				template("TICKETPURCHASE ERROR", "There has been an updating your ticket", 0xff0000)

				local error = "Please report to management"
				term.setCursor(math.floor((guiw - string.len(error)) / 2), 6)
				print(error)
 
				-- On failure we want to stay on this screen for a while
				--- @todo should we put the items back?
				event.pull(600, "kklkl")
				return
		end
		template(stationname .. " - Thank you", "Thank you, your ticket has been updated")
	end

	-- No need for a cancel button since its all done, just a delay before we return
	event.pull(5, "kklkl")
	return
end
 
-- Calculate and display the price for payment
function display_price(bdetail) 
	local e = {"entry"}
	while not buttontoucher(e) do
		local ty = bdetail["params"][1]
		local dest = bdetail["params"][2]
		local trips = bdetail["params"][3]
		local ticketid = bdetail["params"][4]

		local tdis = ""
		if trips > 1 then
			tdis = "s"
		end
		local _, destcount = string.gsub(dest, ",", "")
		destcount = destcount + 1		-- (a single trip wont have a comma)

		local destdis = ""
		if destcount > 1 then
			destdis = "s";
		end

		-- the calculation
		cost = math.ceil(costpertrip * (1 + ((trips - 1) * costmultiplytrip)) * (1 + ((destcount - 1) * costmultiplydest)))

		local costdis = ""
		if cost > 1 then
			costdis = "s"
		end

		template(stationname .. " - " .. ty .. " Trip" .. tdis, "For " .. trips .. " trip" .. tdis .. " on " .. destcount .. " line" .. destdis .. " please deposit " .. cost .. " " .. costitem .. costdis)
--print((1 + ((trips - 1) * 0.75)) .. " trips")
--print((1 + ((destcount - 1) * 0.50)) .. " dests")

		drawchest("down")
		button("Cancel", nil, 1, "", 0x0000ff)
		-- some nil buttons to move the cancel button up
		button(nil, nil, 1)
		button(nil, nil, 1)
		button(nil, nil, 1)
		displaybuttons(2, 6)

		-- we return every second here so we can check to see if they have deposited the amount
		--   it does mean more cpu cycles but i dont believe there is an event of new item at transposer
		--   it also means we need to work on the timeout
		local timeoutcounter = 0
		while timeoutcounter < 60 do
			timeoutcounter = timeoutcounter + 1
			e = {event.pull(1, "touch")}

			-- @todo check the attached chest
			-- @todo if correct amount deposited
      local checkslot
      local paid = 0
      -- wait until the full payment is available - first loop looks for the total amount, if it exists we then extract it
      for checkslot = 1, transposer.getInventorySize(sidepayment) do
            local checkitem = transposer.getStackInSlot(sidepayment, checkslot)
            if checkitem and checkitem.name == costitemid then
              -- match, take the amount and store it
              paid = paid + checkitem.size
            end
      end
			if paid >= cost then
        -- take the full payment out
        local remaincost = cost
        for checkslot = 1, transposer.getInventorySize(sidepayment) do
              local checkitem = transposer.getStackInSlot(sidepayment, checkslot)
              if checkitem and checkitem.name == costitemid then
                -- match, take as much of the payment as possible
                local taken = transposer.transferItem(sidepayment, sidestorage, remaincost, checkslot)
                remaincost = remaincost - taken
                if remaincost <= 0 then
                  break
                end
              end
        end
        if remaincost > 0 then
          -- Ummm..... this would be an indication we have no storage space left
          template("TICKETPURCHASE ERROR", "There has been an issue accepting payment", 0xff0000)

          local error = "Please report to management"
          term.setCursor(math.floor((guiw - string.len(error)) / 2), 6)
          print(error)
   
          -- On failure we want to stay on this screen for a while
          --- @todo should we put the items back?
          event.pull(600, "kklkl")
          return
        end
      
        -- Ok, payment taken lets request the ticket
				return maketicket(ty, dest, trips, ticketid, cost)
			end
		end
	end
end


-- Select the number of trips
function display_tripsselect(bdetail) 
	local e = {"entry"}
	while not buttontoucher(e) do
		local ty = bdetail["params"][1]
		local dest = bdetail["params"][2]

		template(stationname .. " - " ..  bdetail["text"] .. " Ticket", "How many trips?")

		button("1 Trip", display_price, 0, {ty, dest, 1})
		button("5 Trips", display_price, 0, {ty, dest, 5})
		button("10 Trips", display_price, 0, {ty, dest, 10})

		button("Cancel", nil, 1, "", 0x0000ff)
		displaybuttons(2, 6)

		e = {event.pull(10, "touch")}
	end
end

-- Top up Existing / Display
--  requires the player to be close to the reader
function display_topup() 
  local ticketid
	local e = {"entry"}
	while not buttontoucher(e) do
    if updateusetransposer then
      -- Look at each side of all the connected transposers to see if there is a player
      --   and if they have a ticket in their offhand
      for ca, ct in pairs(c.list("transposer")) do
        for checkside = 0, 5 do
          local sname = c.invoke(ca, "getInventoryName", checkside)
          -- players report as air but air reports as nil?
          if sname == "minecraft:air" then
            local tt = c.invoke(ca, "getStackInSlot", checkside, ticketinslot)
            if tt ~= nil then
              if tt.name == "openprinter:printedPage" and string.sub(tt.label, 0, string.len(networkname)) == networkname then
                -- its a match ticketid is what remains
                ticketid = string.sub(tt.label, string.len(networkname) + 2)
                break
              end
            end
          end
        end
        if ticketid then
          break
        end
      end
    else
      -- Look for the ticket in the soragechest
      -- TODO
    end
		
		if not ticketid then
			template(stationname .. " - Top Up Ticket", "Cannot see a valid ticket in your offhand")
			local subtitle2 = "You may need to stand closer to the scanner"
			gpu.setForeground(0xffffff)
			term.setCursor(math.floor((guiw - string.len(subtitle2)) / 2), 5)
			print(subtitle2)
		else
			-- ask the controller if it exists
			local responseid, tid, usesleft, dests = askcontroller("getticket", ticketid)
			if responseid ~= "ticket" then
				-- that ticketid doesnt exist
				template(stationname .. " - Top Up Ticket", "Cannot see a valid ticket in your offhand")
			else
				-- ticket exists
				local multitype = ""
				local _, destcount = string.gsub(dests, ",", "")
				destcount = destcount + 1		-- (a single trip wont have a comma)
				if destcount > 1 then
					multitype = "multi-line"
				else 
					multitype = "single-line"
				end

				local usesleftdis = "s"
				if usesleft == 1 then
					usesleftdis = ""
				end
				template(stationname .. " - Top Up Ticket", "Your " .. multitype .. " ticket has " .. usesleft .. " use" .. usesleftdis .. " left")

				button("Add 1 Trip", display_price, 0, {'Top Up', dests, 1, ticketid})
				button("Add 5 Trips", display_price, 0, {'Top Up', dests, 5, ticketid})
				button("Add 10 Trips", display_price, 0, {'Top Up', dests, 10, ticketid})
			end
		end

		button("Cancel", nil, 1, "", 0x0000ff)
		displaybuttons(2, 6)

		e = {event.pull(10, "touch")}
	end
end


-- Purchase New Ticket screen
function display_newticket() 
	local e = {"entry"}
	while not buttontoucher(e) do
		template(stationname .. " - New Ticket", "Which line would you like the ticket for")

		--- @todo These should be configurable somehow
		button("Waterview", display_tripsselect, 0, {"New", "waterview"})
		button("Attraction", display_tripsselect, 0, {"New", "attraction"})
		---  This is the tricky one for 2 its fine but how do we do 3 or more
		button("Both", display_tripsselect, 1, {"New", "waterview,attraction"})
		button("Cancel", nil, 1, "", 0x0000ff)
		displaybuttons(2, 6)

		e = {event.pull(10, "touch")}
	end
end

-- The welcome screen - where the system will be most of the time
function display_welcome()
	template(stationname, "Welcome, what would you like to do?")

  if shownew then
    button("Purchase New Ticket", display_newticket, 1)
  end
  if showupdate then
    button("Top Up Existing", display_topup, 1)
  end
	displaybuttons(2, 6)

	local costitemdis = ""
	if math.ceil(costpertrip) > 1 then
		costitemdis = "s"
	end

	gpu.setForeground(0x555555)
	gpu.set(4, guih - 2, math.ceil(costpertrip) .. " " .. costitem .. costitemdis .. " per trip")
	gpu.set(guiw - 4 - 16, guih - 3, "Line discount: " .. (100-math.floor(costmultiplydest * 100) .. "%"))
	gpu.set(guiw - 4 - 16, guih - 2, "Trip discount: " .. (100-math.floor(costmultiplytrip * 100) .. "%"))

	-- keep looping until there is inactivity (any form of touch will reset the counter)
	local e = {event.pull(10, "touch")}
	buttontoucher(e)
end

-- find the transposer that is connected to the two chests and printer
--   any other transposer is for reading the player inventroy only
for ca, ct in pairs(c.list("transposer")) do
    local sname = c.invoke(ca, "getInventoryName", sidestorage)
    --  if your not using a chest you will need to change the name
    if sname == storagechesttype then
        transposer = c.proxy(ca)
    end
end

if not transposer then
  print("Could not access a transposer to take/store payment, please connect one")
  
  print("I see the following on the " .. sides[sidestorage] .. " of the transposers (looking for " .. storagechesttype .. ")")
  for ca, ct in pairs(c.list("transposer")) do
    local sname = c.invoke(ca, "getInventoryName", sidestorage)
    print(ca, sname)
  end
  
  os.exit()
end

-- Validate that we have access to the two chests
if not transposer.getInventorySize(sidepayment) or transposer.getInventorySize(sidepayment) < 1 then
  print("Could not access the payment chest on ", sides[sidepayment])
  exit()
end
if not transposer.getInventorySize(sidestorage) or transposer.getInventorySize(sidestorage) < 1 then
  print("Could not access the storage chest on ", sides[sidestorage])
  exit()
end
-- @TODO Should check regually there is available space to store the payment and go offline when there is not

if not printer then
  print("Could not access a printer, please connect one")
  exit()
end
if not transposer.getInventorySize(sideprinter) or transposer.getInventorySize(sideprinter) < 1 then
  print("Could not access the printer storage on ", sides[sideprinter])
  exit()
end

-- for responses we need to open the port
modem.open(commsport)

-- before we start up make sure the controller is configured and listening
print("Waiting for controller to come online")
local e
while not e do
	e = askcontroller("hello")
end

-- disable the ablity to open the interface by default (you can still open it with sneak)
c.screen.setTouchModeInverted(true)
--event.listen("touch", buttontoucher)

while true do
  display_welcome()
end

--event.ignore("touch", buttontoucher)

c.screen.setTouchModeInverted(false)
