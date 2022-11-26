-- requires
local term = require("term")
local os = require("os")
local event = require("event")
local component = require("component")
local computer = require("computer")
local modem = component.modem
local fs = require("filesystem")
local sides = require("sides")
local serialization = require("serialization")

if(not fs.exists("/lib/guielements.lua")) then
   print("/lib/guielements.lua library is not installed, download it from https://raw.githubusercontent.com/nzhook/myrail/master/opencomputers/lib/guielements.lua")
   os.exit()
end
local gui = require("guielements")

-- settings

-- port number to use, needs to match the eeprom
local COMPORT = 2022

-- side of redstone io to use when the sequence is complete
--  note: all other sides will trigger an open/close
local restoneside_ready = sides.front


--
-- init
local pistons = {}
local retracter = nil
local nextretracter = 0
local nextaction = "open"
local running = false
local guiscroll = 1
local ininputbox = false

--
-- functions
local function save_pistons() 
	local tmpf = io.open("/pistonConfig", "w")
	tmpf:write(serialization.serialize(pistons, math.maxinteger))
	tmpf:close()
end


local function dopistons(action, pistonorder, delay) 
	for _, id in ipairs(pistonorder) do
		piston = pistons[id]
		if piston.boot == "boot" then				
			-- when a microcontroller is pushed/pulled it turns off so we need to turn it back on
			--  again (note this requires us to slow down so the controller can boot)
			modem.send(id:sub(1, 36), COMPORT, "BOOT")
			os.sleep(0.2)
		end

		os.sleep(delay)
		local laction = action
		-- handle pistons that are reversed (eg. they close when in openmode)
		if laction == "open" and piston.type == "close" then
			laction = "close"
		elseif laction == "close" and piston.type == "close" then
			laction = "open"
		end

		modem.send(id:sub(1, 36), COMPORT, laction)
	end
end

-- provide the order for the action
local function getpistonorder(action)
	local sortorder = {}
	local returnorder = {}
	-- generate the sortable list
	for id, piston in pairs(pistons) do
		if piston.actionorder[action] > 0 then
			table.insert(sortorder, {id = id, order = piston.actionorder[action]})
		end
	end

	local function sorter(a, b)
		if(a.order < b.order) then
			return true
		end
	end

	table.sort(sortorder, sorter)

	-- now loop back in with the final order
	for _, d in pairs(sortorder) do
		table.insert(returnorder, d.id)
	end

	return returnorder
end

local function poweroffpistons()
	-- send the OFF signal for any not connected via cable
	modem.broadcast(COMPORT, "OFF")

	-- turn off any connected ones (they should have also got the off command but this double checks)
	for id, t in pairs(component.list("microcontroller")) do
		component.invoke(id, "stop")
	end
end

local function boxmsg(msg)
	touchpos = {}
	gui.reset()
	local x, y, w, h = gui.box(nil, nil, 61, 23, nil, 0x00ff00, 0xffff00, 0x004400, true)
	gui.setBackground(0x004400)
	gui.setForeground(0xffffff)
	gui.printcenter(y + math.floor(h / 2) - 1, msg, w, x)
	gui.setBackground(0x000000)
	return x, y + math.floor(h / 2) - 1, w, h
end


local function makepistonsready(scanmode)
	-- start all the connected microcontroller's up
	for id, t in pairs(component.list("microcontroller")) do
		component.invoke(id, "start")
	end

	-- send the bootup message for any controllers not on the current cable
	modem.broadcast(COMPORT, "BOOT")

	if not scanmode then
		-- still allow 2 seconds for them to boot
		os.sleep(2)
		return
	end

	-- wait for the controllers to register
	local e, r, sndr, p, d, msg = true
	local i = #pistons + 1
	while e do
		e, r, sndr, p, d, msg, msg2 = event.pull(2, "modem_message")
		if e == "modem_message" then
			if msg == "BOOT" then
				i = i + 1
				if not pistons[sndr] then
					pistons[sndr] = {type = "open", boot ="", controller = msg2, name = msg2, actionorder = {open = i, close = i}}
				end
			end
		end
	end
end

-- open the door when requested
local isopen = false
local function ev_redstone(_, _, s, a)
	-- only trip if the redstone signal is going FROM 0
	if a ~= 0 then
		return
	end
	if s == restoneside_ready then		-- ignore our own output signal
		return
	end

	boxmsg("Please wait")

	if not isopen then
		-- make sure the pistons are online (we would have turned them off to save power)
		makepistonsready(false)

		boxmsg("Door Opening")
		local pistonorder = getpistonorder("open")
		dopistons("open", pistonorder, 0.3)
		isopen = true
	else
		isopen = false
		boxmsg("Door Closing")
		local pistonorder = getpistonorder("close")
		dopistons("close", pistonorder, 0.1)
		poweroffpistons()
	end

	if component.redstone then
		-- send the redstone signal, we leave a little bit of time for the pistons to complete
		os.sleep(2)
		component.redstone.setOutput(restoneside_ready, 15)
		os.sleep(1)
		component.redstone.setOutput(restoneside_ready, 0)
	end

	local selectedPiston = getpistonorder("open")[1]
	draw_gui("open", selectedPiston)
end

local function ev_changepistonorder(action, selectedPiston, number)
	computer.beep(500, 0.1)

	local o = pistons[selectedPiston].actionorder[action]
	-- take the selectedpiston out
	pistons[selectedPiston].actionorder[action] = 0

	-- reorder the pistions
	local neworder = getpistonorder(action)

	-- insert it into trhe new slot
	table.insert(neworder, number, selectedPiston)

	-- apply the new ordering back
	local i = 0
	for i, id in ipairs(neworder) do
		local o = pistons[id].actionorder[action]
		pistons[id].actionorder[action] = i
	end

	save_pistons()

	-- return to gui
	draw_gui(action, selectedPiston)
end

local function ev_changeactivepiston(mode, newPiston)
	draw_gui(mode, newPiston)
end

local function ev_ident(mode, selectedPiston, state)
	if state == true then
		retracter = selectedPiston
	else
		retracter = nil
	end
	draw_gui(mode, selectedPiston)
end

local function ev_setpistondirection(mode, selectedPiston, direction)
	touchpos = {}
	gui.reset()			-- dont allow any button interaction while we wait
	boxmsg("Sending direction change")

	modem.send(selectedPiston, COMPORT, "BOOT")
	-- should we instead wait for it to 'boot'?
	os.sleep(1)
	modem.send(selectedPiston, COMPORT, "SET", direction)
	computer.beep(500, 0.1)
	draw_gui(mode, selectedPiston)
end

local function ev_setpistonboottype(mode, selectedPiston, boottype)
	pistons[selectedPiston].boot = boottype
	save_pistons()
	computer.beep(500, 0.1)
	draw_gui(mode, selectedPiston)
end

local function ev_setpistontype(mode, selectedPiston, type)
	pistons[selectedPiston].type = type
	save_pistons()
	computer.beep(500, 0.1)
	draw_gui(mode, selectedPiston)
end
	
local function ev_resetpiston(mode, selectedPiston)
	-- TODO: should confirm this action
	touchpos = {}
	gui.reset()			-- dont allow any button interaction while we wait
	boxmsg("Piston reset, rescanning")

	computer.beep(100, 0.2)
	pistons[selectedPiston] = nil
	makepistonsready(true)
	computer.beep(500, 0.1)
	local selectedPiston = getpistonorder("open")[1]
	draw_gui(mode, selectedPiston)
end

local function ev_guichangescrollbar(mode, selectedPiston, newvalue)
	guiscroll = newvalue
	draw_gui(mode, selectedPiston)
end

local function ev_setpistonname(mode, selectedPiston)
	local x, y, w, h = boxmsg("New name for " .. selectedPiston)
	gui.set(x + 2, y + 2, "[ ")
	gui.set(x + w - 4, y + 2, " ]")
	term.setCursor(x + 4, y + 2)

	ininputbox = true
	pistons[selectedPiston].name = io.stdin:read()
	ininputbox = false
	save_pistons()
	computer.beep(500, 0.1)
	draw_gui(mode, selectedPiston)
end

function draw_gui(mode, selectedPiston) 
	local modetxt = mode
	if mode == "close" then			-- Make it handle the english quirk of closing (not closeing)
		modetxt = "clos"
	end
	modetxt = modetxt:sub(1,1):upper() .. modetxt:sub(2, 100)

	touchpos = {}
	gui.reset()
	gui.setForeground(0xffffff)
	local x, y, w, h = gui.box(nil, nil, 61, 23, "Piston Door Control", 0x00ff00, 0xffff00, nil, true)
	local hx = gui.printcenter(y + 1, "Piston Configuration", w, x)
	gui.set(hx, y + 2, "─────────────────────")

	local currentorder = getpistonorder(mode)

	local px, py, pw, ph = gui.box(x + 29, y + 4, 30, h - 8, pistons[selectedPiston].name:sub(1, 22), 0x0000ff, 0xffffff, nil, false)
	-- clicking the title allows for changing the name
	gui.clickable(px, py, "", ev_setpistonname, {mode, selectedPiston}, 30)
	gui.setForeground(0x555555)
	gui.set(px + 3, py + 1,  pistons[selectedPiston].controller:sub(1, 22))

	-- delete button in top right (X)
	gui.setForeground(0xff0000)
	gui.clickable(px + pw - 2, py + 1, "X", ev_resetpiston, {mode, selectedPiston}, 1)

	gui.setForeground(0xffffff)
	gui.set(px + 3, py + 3,  "  Open Order:")
	gui.numberselect(px + 2 + 15, py + 3, 9, pistons[selectedPiston].actionorder["open"], ev_changepistonorder, {"open", selectedPiston}, nil, 1, #currentorder, false, 0x0, 0x00ff00)

	gui.set(px + 3, py + 4,  " Close Order:")
	gui.numberselect(px + 2 + 15, py + 4, 9, pistons[selectedPiston].actionorder["close"], ev_changepistonorder, {"close", selectedPiston}, nil, 1, #currentorder, false, 0x0, 0x00ff00)

	-- we dont know what the current direction is, so we show all 3 options
	gui.set(px + 3 + 5, py + 6, "Set Direction")
	gui.setForeground(0x00ff00)
	gui.clickable(px + 3 + 1, py + 7, "[ Front ]", ev_setpistondirection, {mode, selectedPiston, 0}, 11)
	gui.clickable(px + 3 + 1, py + 8, "[   Up  ]", ev_setpistondirection, {mode, selectedPiston, sides.top}, 11)
	gui.clickable(px + 3 + 1, py + 9, "[  Down ]", ev_setpistondirection, {mode, selectedPiston, sides.bottom}, 11)

	if pistons[selectedPiston].type == "open" then
		gui.clickable(px + pw - 14, py + 7, "[  Pull  ]", ev_setpistontype, {mode, selectedPiston, "close"}, 10)
	else
		gui.clickable(px + pw - 14, py + 7, "[  Push  ]", ev_setpistontype, {mode, selectedPiston, "open"}, 10)
	end
	if pistons[selectedPiston].boot == "boot" then
		gui.clickable(px + pw - 14, py + 8, "[ Static ]", ev_setpistonboottype, {mode, selectedPiston, ""}, 10)
	else
		gui.clickable(px + pw - 14, py + 8, "[  Moves ]", ev_setpistonboottype, {mode, selectedPiston, "boot"}, 10)
	end

	if retracter then
		gui.buttonxy(px + math.floor((pw - 2 - 8) / 2) - 2, py + 12, "Identify", ev_ident, {mode, selectedPiston, false}, 11, 0xffff00, 0xffffff)
	else
		gui.buttonxy(px + math.floor((pw - 2 - 8) / 2) - 2, py + 12, "Identify", ev_ident, {mode, selectedPiston, true}, 11, 0x0000ff, 0xffffff)
	end


	local line = 1
	local iline = 1
	for porder, pistonid in ipairs(currentorder) do
		if line >= guiscroll and line < guiscroll + (h - 10) then
			gui.setForeground(0xffffff)
			if selectedPiston == pistonid then
				gui.setForeground(0xffff00)
			end

			gui.clickable(x + 4, y + 4 + iline, pistons[pistonid].name:sub(1, 20), ev_changeactivepiston, {mode, pistonid}, 20)
			iline = iline + 1
		end
		line = line + 1
	end
	gui.box(x + 2, y + 4, 24, h - 8, modetxt .. "ing Order", 0x00ff00, 0xffffff, nil, false)
	gui.scrollbar(x + 25, y + 5, h - 11, guiscroll, #currentorder, ev_guichangescrollbar, {mode, selectedPiston})

	gui.buttonxy(x + 3, y + h - 3, "Trigger Door", ev_redstone, {0, 0, 99, 0, 15}, 11, 0x00ff00)
end

local function ev_keyup(e, id, code)
	if ininputbox then
		return
	end
	if code == 13 then		-- enter = ignored
		return
	elseif code == 113 then		-- q = exit
		running = false
		return
	elseif code == 114 then	-- r = rescan pistons (eg. after adding a new one)
		boxmsg("Scanning Pistons")
		makepistonsready(true)
		poweroffpistons()
		local selectedPiston = getpistonorder("open")[1]
		draw_gui("open", selectedPiston)
		return
	else
--		print("Unknown keypress for ", code)
	end
end

local function ev_touch(e, id, w, h, keymodifer, user)
	local pressed = gui.ev_touch(e, id, w, h, keymodifer, user)

	if pressed and pressed.call then
		if pressed.params then
			if type(pressed.params) == "table" then
				-- add the value if one is available to the end of the argument list
				table.insert(pressed.params, pressed.value)
				pressed.call(table.unpack(pressed.params))
			else
				pressed.call(pressed.params, pressed.value)
			end
		else
			pressed.call(pressed.value)
		end
	end
end

--
-- the code

-- load current setupo
local f = io.open("/pistonConfig", "r")
if f then
	local i = serialization.unserialize(f:read("*all"))
	pistons = i
	f:close()
end

term.clear()
modem.open(COMPORT)

boxmsg("Starting up")
makepistonsready(true)
if not pistons then
	error("No Microcontrollers loaded with magicpiston found")
end
-- send a power off command as we dont need to be using power
poweroffpistons()

--save_pistons()
event.listen("touch", ev_touch)
event.listen("redstone_changed", ev_redstone)
event.listen("key_up", ev_keyup)

-- pick a piston to be the starting one
local selectedPiston = getpistonorder("open")[1]
draw_gui("open", selectedPiston)

running = true
while running do
	os.sleep(1)

	if retracter and nextretracter <= computer.uptime() then
		nextretracter = computer.uptime() + 1
		modem.send(retracter:sub(1, 36), COMPORT, "BOOT")
		modem.send(retracter:sub(1, 36), COMPORT, nextaction)
		if nextaction == "open" then
			nextaction = "close"
		else
			nextaction = "open"
		end
	end
end

-- if we exit (eg. q is pressed) then we unregister out events
event.ignore("touch", ev_touch)
event.ignore("redstone_changed", ev_redstone)
event.ignore("key_up", ev_keyup)
