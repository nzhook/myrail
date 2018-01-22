--[[ Rail map display and point collection computer/screen code
     Created for the Youtube channel https://youtube.com/user/nzHook 2018
     myRail Episode Showing Usage: https://www.youtube.com/watch?v=uimspQP-1S4
     NOTE: Requires:
       - microcontrollers/devices to send signals back
       - a linked card connected to another device (eg. tablet) for sending commands back
     
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

---- TODO
----  - When restarting/timeout send a are you still there ping, and remove itrems that dont exist
----  - better map display
----  - change positions / poi names

local component = require("component")
local computer = require("computer")
local event = require("event")
local fs = require("filesystem")
local serialization = require("serialization")
local term = require("term")

local comm_port = 1232
local rcomm_port = 1233
local tunnel_port = 1234
local pointfiles = "/home/points/"
local zsize = 44
local xsize = 26
local linename = "Waterview Line"

local missing = {}
local seen = {}
local pinged = 0
local pinging = nil
local lastpingtime = 0
local minx = math.huge
local minz = math.huge
local miny = math.huge

component.modem.open(comm_port)

-- Load any previously saved points
fs.makeDirectory(pointfiles)
local file
for file in fs.list(pointfiles) do
  local f = io.open(pointfiles .. "/" .. file, "r")
  local i = serialization.unserialize(f:read("*all"))
  seen[i.id] = i
  f:close()
  -- determine the minimum pos's so we can determine placings
  minx = math.min(minx, i.pos[1])
  miny = math.min(miny, i.pos[2])
  minz = math.min(minz, i.pos[3])
end

-- First thing we draw is the standard GUI bits that dont change
term.clear()
local gx, gy = component.gpu.getResolution()
component.gpu.setForeground(0x00ff00)
component.gpu.setBackground(0x000000)
for i = 2, gx - 1 do
      component.gpu.set(i, 1, "-")
      component.gpu.set(i, gy, "-")
end
for i = 2, gx - 1 do
      component.gpu.set(1, i, "|")
      component.gpu.set(gx, i, "|")
end
component.gpu.set(1, 1, "+")
component.gpu.set(1, gy, "+")
component.gpu.set(gx, gy, "+")
component.gpu.set(gx, 1, "+")
component.gpu.set(3, 1, "[ " .. linename .. " ]")
component.gpu.setForeground(0xffff00)
component.gpu.set(5, 1, linename)



-- Tell all the microcontrollers to reboot so they check in again
component.modem.broadcast(rcomm_port, "REBOOT")


while true do
  local a, b, c, d, e, f, g, h, i, j, k, l, m, n = event.pull(3)
  if a == "modem_message" then
    -- TODO Should make this trigger as an event and then make it a lib
    if f == "relayevent" then
      a = h
      b = g       -- the computer id
      --b = i       -- the redstoneid
      b = c       -- the network sourceid
      c = j
      d = k
      e = l
      f = m
      g = n
    elseif g == "FOUND" then
      -- Track that we have seen this ID
      -- We store them as seperate files to avoid corruption as well as easy updates
      local tmpf = io.open(pointfiles .. i .. "," .. j .. "," .. k, "w")
      local tmps = {}
      tmps.id = h
      tmps.pos = {i, j, k}
      local tmpi = serialization.serialize(tmps)
      tmpf:write(tmpi)
      tmpf:close()
      
      -- Restore the known state
      tmps.state = missing[h]
      
      seen[h] = tmps

      -- notify the microcontroller and the tablet
      component.modem.send(h, rcomm_port, "HIGH", seen[h].pos[1] .. "," .. seen[h].pos[2] .. "," .. seen[h].pos[3])
      component.tunnel.send(tunnel_port, "MSG", "Welcome " .. h .. " (" .. seen[h].pos[1] .. "," .. seen[h].pos[2] .. "," .. seen[h].pos[3] .. ")")
   
 
      pinging = nil
      pinged = 0
      missing[h] = nil
      -- If there are more missing find the next one (must be a better way to do a php end(missing)?)
      -- FIXME: This is not working, disabled for now
      --local pingnext, null
      --for pingnext, null in pairs(missing) do
      --    if seen[pingnext] then          -- shouldnt happen, but we dont need to recheck
      --      missing[pingnext] = nil
      --    else
      --      component.tunnel.send(tunnel_port, "IDENT", pingnext)
      --      break
      --    end
      --end
    elseif g == "POI" then
      -- Store any POI's that are sent to us
      -- We store them as seperate files to avoid corruption as well as easy updates
      local tmpf = io.open(pointfiles .. h, "w")
      local tmps = {}
      tmps.id = h
      tmps.pos = {i, j, k}
      tmps.label = h
      local tmpi = serialization.serialize(tmps)
      tmpf:write(tmpi)
      tmpf:close()
      
      seen[h] = tmps

      -- notify the tablet that we got the request
      component.tunnel.send(tunnel_port, "MSG", "Noted POI " .. h .. " (" .. seen[h].pos[1] .. "," .. seen[h].pos[2] .. "," .. seen[h].pos[3] .. ")")
    elseif g == "PING" then
      -- If the ident.lua script sends a ping request track the id
      pinging = h
      pinged = 0
    elseif g == "REBOOT" then
      -- This one we broadcast so that any that are not connected will trigger an alert
      component.tunnel.send(tunnel_port, "MSG", "Broadcasting a reboot request")
      component.modem.broadcast(rcomm_port, "REBOOT")
    else
--      print("Unknown message", f, g)
      component.tunnel.send(tunnel_port, "MSG", "Unknown message " .. f)
    end
  end
  
  -- Remember the netrelay code above may reset 'a' so dont use elseif
  if (a == "redstone_changed" or a == "boot") then
      if not seen[b] then
        -- we have not seen this block before. tell the tablet
        -- print("Unknown position for device ", b)
        component.tunnel.send(tunnel_port, "MSG", "Missing " .. b)
        missing[b] = i

        component.tunnel.send(tunnel_port, "IDENT", b)
      elseif a == "redstone_changed" then
        -- update the state of the block
        seen[b].state = d
      elseif a == "boot" then
				-- @todo The state coming from the microcontrollers is wrong (reports as in use) so for now this is disabled
        --  seen[b].state = i
        -- For debugging after a controller boots and we know about it, tell it to highlight (can be disabled when everything is setup)
        component.modem.send(b, rcomm_port, "HIGH", seen[b].pos[1] .. "," .. seen[b].pos[2] .. "," .. seen[b].pos[3])
        component.tunnel.send(tunnel_port, "MSG", "Hello " .. b .. " (" .. seen[b].pos[1] .. "," .. seen[b].pos[2] .. "," .. seen[b].pos[3] .. ") = " .. i)
      else
        -- ?? did we not catch everything?
        component.tunnel.send(tunnel_port, "MSG", "I have been confused by " .. a .. " logic - " .. b)
      end
  end
  
  -- If the player is using the controller to find a block, tell that controller to identify itself
  if pinging and lastpingtime + 4 <= computer.uptime() then
    component.modem.send(pinging, rcomm_port, "PING")
    pinged = pinged + 1
    if pinged > 10 / 4 then
      pinged = 0
      pinging = nil
    end
    lastpingtime = computer.uptime()
  end

  -- A way to exit
  if a == "key_down" then
    os.exit()
  end
  
  -- If the player touches part of the screen display the (approx) co-ords to help identify issues
  if a == "touch" then
    print(minx + (c * xsize) + 2, minz + (d * zsize) + 2)
  end 
  
  
  
  
  
  --
  --
  -- This is the display/GUI code
  --
  -- Not the best of code, but it does the trick
  local shown = {}
	-- First loop determines best usage (populating shown)
	--  this avoids flickering when a lesser block reports first
  for k, v in pairs(seen) do
		-- POI's have a label and we treat then differently
		-- Which we do in a another loop (so we have access to a fully shown map)
		if not seen[k].label then
			local xp = seen[k].pos[1] - minx
			local yp = seen[k].pos[2] - miny      -- we dont show height but its here as a reminder
			local zp = seen[k].pos[3] - minz
	--     print(k, xp, yp, zp, seen[k].state)
	-- seen[k].state can be one of:
	--   nil = unknown (no activity since boot)
	--   15  = available
	--   0   = in-use
			local state = 0
			component.gpu.setBackground(0xff00ff)
			if seen[k].state == 15 then
				state = 2
				component.gpu.setBackground(0xff0000)
			elseif seen[k].state == 0 then
				state = 1
				component.gpu.setBackground(0x00ff00)
			end

			xp = math.ceil(xp / xsize)
			zp = math.ceil(zp / zsize)
   
			if not shown[xp ..",".. zp] then
				shown[xp ..",".. zp] = -1
			end
			
			-- Only update the state if its higher (eg. in-use wins over not in-use)
			if shown[xp ..",".. zp] < state then
				shown[xp ..",".. zp] = state
			end
		end
	end
	
	
	-- Second loop is the display, could do it based on shown
	--  but we dont accually store the x,z positions so I took the lazy option
	for k, v in pairs(seen) do
		-- POI's have a label and we treat then differently
		-- Which we do in a another loop (so we have access to a fully shown map)
		if not seen[k].label then
			local xp = seen[k].pos[1] - minx
			local yp = seen[k].pos[2] - miny      -- we dont show height but its here as a reminder
			local zp = seen[k].pos[3] - minz
	--     print(k, xp, yp, zp, seen[k].state)
	-- seen[k].state can be one of:
	--   nil = unknown (no activity since boot)
	--   15  = available
	--   0   = in-use
			local state = 0
			component.gpu.setBackground(0xff00ff)
			if seen[k].state == 15 then
				state = 2
				component.gpu.setBackground(0xff0000)
			elseif seen[k].state == 0 then
				state = 1
				component.gpu.setBackground(0x00ff00)
			end

			xp = math.ceil(xp / xsize)
			zp = math.ceil(zp / zsize)
   
			-- Only update the state if its higher (eg. in-use wins over not in-use)
			if shown[xp ..",".. zp] <= state then
				shown[xp ..",".. zp] = state
				component.gpu.set(xp + 3, zp + 3, " ")
			end
		end

  end

  -- Always move back to 2,2 and the colours to avoid screen scrolling and odd displays
	term.setCursor(2,2)
	component.gpu.setBackground(0x000000)
	component.gpu.setForeground(0xffffff)

	-- Final loop is POI, main reason this is now here is for working out text positions
	--   could acculy move this back into the previous loop, but its a little easier to read
	--   in two seperate loops
  for k, v in pairs(seen) do
		if seen[k].label then
			local xp = seen[k].pos[1] - minx
			local yp = seen[k].pos[2] - miny      -- we dont show height but its here as a reminder
			local zp = seen[k].pos[3] - minz

			xp = math.ceil(xp / xsize)
			zp = math.ceil(zp / zsize)
		 
			-- Work out which way the track goes (2 blocks should be a good indication)
			if not shown[xp ..",".. (zp + 2)] and not shown[xp ..",".. (zp + 1)] then
				-- Right of line
				component.gpu.set(xp + 3 + 2, zp + 3, "<- " .. seen[k].label)
			elseif (not shown[xp ..",".. (zp + 2)] and not shown[xp ..",".. (zp + 1)]) or (not shown[xp ..",".. (zp - 2)] and not shown[xp ..",".. (zp - 1)]) then
				-- Below line
				--   Originally had the text going down here but it looks ugly
				if not shown[(xp - 2) ..",".. (zp + 2)] and not shown[(xp - 2) ..",".. (zp + 1)] then
					-- This might handle above the line, but untested
					component.gpu.set(xp + 3, zp + 3 - 1, "|")
					component.gpu.set(xp + 3, zp + 3 - 2, "\\- " .. seen[k].label)
				else
					component.gpu.set(xp + 3, zp + 3 + 2, "|")
					component.gpu.set(xp + 3, zp + 3 + 3, "\\- " .. seen[k].label)
				end
			elseif not shown[(xp - 2) ..",".. zp] and not shown[(xp - 1) ..",".. zp] then
				-- Left of line
				component.gpu.set(xp + 3 - (4 + string.len(seen[k].label)) , zp + 3, seen[k].label .. " ->")
			else
				-- ?? @todo??? make this display something
--				print(seen[k].label .. " ??", shown[(xp-2) ..",".. (zp)], xp, zp)
--				component.gpu.set(xp + 3, zp + 3, "!!")
			end
--		component.gpu.set(1, (zp + 3), "Z>")
--		component.gpu.set((xp + 3), 1, "X")
		end
	end
	
  
  
end
