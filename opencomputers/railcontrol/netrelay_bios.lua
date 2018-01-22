--[[ Microcontroller bios for relaying (redstone) events to a master (railmap.lua / netrelattest.lua)
     Created for the Youtube channel https://youtube.com/user/nzHook 2018
     myRail Episode Showing Usage: https://www.youtube.com/watch?v=uimspQP-1S4
     NOTE: You may want a network card to make this of any use
     
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

--  @todo Should we handle network events?  maybe keep track of the previous hops, so we dont send back - drop at X number (eg. TTL)
local comms_port = 1232
-- rcomm is for the locate me packet.
local rcomms_port = 1233
local rsside = 0

local id = computer.address()

local modem = component.list("modem")()
if not modem then error("No modem/network found") end
modem = component.proxy(modem)
if not modem then error("Error loading modem") end

local side
local rsstate = 0     -- The initial state of any redstone that is sent
-- setup the redstone card and automatic restart on rs event
local rs = component.list("redstone")()
if rs then      -- If we dont have redstone support its not the en of the world, we beep as well
  rs = component.proxy(rs)
  rs.setWakeThreshold(10)       -- If the microcontroller unloads from the chunk it wont be on when the chunk comes back, so set it to wake up again
  for side = 0, 5 do
    if rsstate < rs.getInput(side) then
      rsstate = rs.getInput(side)
    end
  end
end

-- Setup the sign controller and make it output its device ids (computer and network) to the sign
local sigh = component.list("sign")()
local activeside
if sigh then      -- We were not originally intended for signs so its not the end of the world (hence the varname)
  sigh = component.proxy(sigh)
-- NOTE: In a computer the args are setValue(SIDE, STRING) in a microctronoller its just setValue(STRING)
--  for side = 1, 5 do
--    if sigh.setValue(side, id .. "\n" .. modem.address) then
    if sigh.setValue(id .. "\n" .. modem.address) then
      activeside = 1
    end
--  end
end

-- Open up the communications port and say we have booted
modem.open(rcomms_port)
modem.broadcast(comms_port, "relayevent", id, "boot", rsstate)

-- An endless loop 
while true do
  local a, b, c, d, e, f, g = computer.pullSignal(10)
  if a then
    if a == "modem_message" then
        -- If we get a network message its normally to highlight where we are or an acknowledgement that we exist
        if f == "HIGH" then
          if rs then rs.setOutput(rsside, 15) end
          -- To show we are here, add anything that master sent us to the first line (eg. our address)
          if sigh and activeside then sigh.setValue(g .. "\n\n" .. id .. "\n" .. modem.address) end
        elseif f == "REBOOT" then
          -- reboot (note: this will send a "boot" message when it comes back online)
          computer.shutdown(true)
        else
          -- In all other cases flash on, beep, flash off, beep
          if rs then rs.setOutput(rsside, 15) end
          computer.beep(500, 1.5)
          if rs then rs.setOutput(rsside, 0) end
          computer.beep(500, 1.5)       -- Ensure we pause on and off
        end
    else
     -- send everything else back to the master
     -- note: we send id here as when placed in creative the NIC and RS id's dont differ, 
      --     however the computer was placed so it has a uniuqe id still
      -- TODO: Dont use broadcast messages
      modem.broadcast(comms_port, "relayevent", id, a, b, c, d)
    end
  end
end
