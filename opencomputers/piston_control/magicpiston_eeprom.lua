-- This eeprom uses a sticky piston and a network card
--  Once turned on it will send a 'boot' signal and will wait
--  for a open or close signal
-- See myRail https://www.youtube.com/watch?v=mF17eDP9-i8 for more info
local COMPORT = 2022			-- port to communicate on
local TIMEOUT = 300				-- turn back off if no signal in this time

local modem = component.proxy(component.list("modem")())
local piston = component.proxy(component.list("piston")())
local eeprom = component.proxy(component.list("eeprom")())

-- the direction we push is stored in the eeprom
local dir = tonumber(eeprom.getData())
if not dir then	-- push front
	dir = 3
end

-- if we see this on the network, start up
modem.setWakeMessage("BOOT")

-- we also send that message, this will trigger any others
--  but will also tell the master we are online
modem.broadcast(COMPORT, "BOOT", computer.address(), "magicpiston")
modem.open(COMPORT)

-- wait for a signal from the master
-- modem_message(receiverAddress: string, senderAddress: string, port: number, distance: number, ...)
local e, r, s, p, d, act, addi = nil
e = true
while e do
	e, r, s, p, d, act, addi = computer.pullSignal(TIMEOUT)

	if e == "modem_message" and p == COMPORT then
		if act == "open" then
			piston.pull(dir)
		elseif act == "close" then
			piston.push(dir)
		elseif act == "OFF" then
			computer.shutdown()
		elseif act == "SET" then
			eeprom.setData(tostring(addi))
			dir = addi
		elseif act == "BOOT" then
			-- we ignore boot signals
		end
	end
end

-- if we get here we have not had a message for a while so can power off
computer.shutdown()
