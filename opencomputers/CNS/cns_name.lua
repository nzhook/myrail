--[[ Component name system (CNS) - Tablet naming
     Author: nzHook
     Created for the Youtube channel https://youtube.com/user/nzHook 2019
     myRail Episode Showing Setup: https://youtu.be/lp_uL_2OQrU (episode 42)
     
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
-- How to use (basic)
--   -- Install the server/computer side and start it
--   -- Make a tablet with this code, an analyzer, wireless or tunnel card. A navigation upgrade is also recomended
--   -- With the tablet:
--   --   Start the code or add it to .rc.sh so it starts on boot (return to world)
--   --   Select the server/computer by looking at the server and while holding shift hold right click for approx 2 seconds (tablet will beep)
--   --   Open the tablet and select 'change server'  (return to world)
--   --   Look at a device to be named and while holding shift hold right click for approx 2 seconds (tablet will beep)
--   --   Open the tablet and enter the name and press enter
--   -- On the server/computer, use dns("name you used") in code to reference the selected component
---
local event = require("event")
local component = require("component")
local term = require("term")

-- config
local ns_port = 53

-- initial vars
local running = true  -- program is running (when set to false it will exit)
local remotemachine   -- remote machine to send update request to
local currentedit     -- while in edit mode, contains the currently selected item
local hasGPS = false  -- if a navigation upgrade is installed
local gpsX = 0        -- X read from disk
local gpsZ = 0        -- Z read from disk
local lastmessagetime = 1 -- Time remaining to display the current message
local gx, gy = component.gpu.getResolution()
local msgid = 131     -- Expected message id for the last request sent

-- initial checks

-- we need 2 things, an analyser and a tunnel or wireless card
local haderror = false
if not component.list("barcode_reader")() then
  print("ERROR", "An analyzier is required to obtain address ids, please install one")
  haderror = true
end

if not component.list("modem")() and not component.list("tunnel")() then
  print("ERROR", "A network (wireless) or tunnel upgrade is required to setup DNS names, please install one")
  haderror = true
end

-- we can work without a navigation upgrade but it may not be expected so give a warning
if not component.list("navigation") then
    print("WARNING", "A navigation upgrade is not present GPS coordinates will not be available")
else
  -- Grab the position stored by find00, if not available warn that it will be relative to the map in the navigation upgrade
  local gpsfile = io.open("/.gps_start.pos", "r")
  if not gpsfile then
    print("WARNING", "Navigation upgrades provide GPS coordinates relative to the map they were crafted with")
    print("WARNING", "If real world position are required, use find00 first as stored coordinates will not be updated")
  else
    gpsX = gpsfile:read()
    gpsZ = gpsfile:read()
    gpsfile:close()
    
    hasGPS = true
  end
end


-- we bail after showing all errors and warnings because rebuidling is quite slow
if haderror then
    os.exit()
end


-- Functions
local function border()
  component.gpu.setForeground(0x00ff00)
  component.gpu.setBackground(0x000000)
  for i = 2, gx - 1 do
        component.gpu.set(i, 1, "─")
        component.gpu.set(i, gy, "─")
  end
  for i = 2, gy - 1 do
        component.gpu.set(2, i, "│")
        component.gpu.set(gx - 1, i, "│")
  end
  component.gpu.set(2, 1, "┌")
  component.gpu.set(gx - 1, 1, "┐")
  component.gpu.set(2, gy, "└")
  component.gpu.set(gx - 1, gy, "┘")
  if remotemachine then
    term.setCursor(5, 1)
    component.gpu.setForeground(0xffffff)
    print(" " .. remotemachine.desc .. " ")
  end
end

local function center(y, text)
  local x = math.floor((gx / 2) - (string.len(text) / 2))
  term.setCursor(x, y)
  print(text)
  return x
end
local function waiting()
  currentedit = nil
  term.clear()
  border()
  
  if remotemachine then
    component.gpu.setForeground(0xffff00)
    center(math.floor(gy / 2) - 2, "Waiting...")
  else
    component.gpu.setForeground(0xffffff)
    component.gpu.setBackground(0xff00ff)
    center(math.floor(gy / 2) - 2, "  Select a server  ")
    component.gpu.setBackground(0x000000)
  end
  component.gpu.setForeground(0x555555)
  if remotemachine then
    center(math.floor(gy / 2) + 1, "Face a component")
  else
    center(math.floor(gy / 2) + 1, "Face a computer")
  end
  center(math.floor(gy / 2) + 2, "Hold shift and right click for 2 seconds")
  
end

local function errored(text)
  currentedit = nil
  component.gpu.setForeground(0xff0000)
  center(math.floor(gy / 2) - 2, text)
  component.gpu.setForeground(0x555555)
  component.computer.beep(300, 0.2)
  component.computer.beep(200, 0.5)
  lastmessagetime = 10
end

local function abs(pos)
    if pos >= 0 then
      return pos
    else
      return "n" .. (-pos)
    end
end

local function show_namescreen()
  if currentedit.warning then
    component.gpu.setForeground(0xff0000)
    center(gy - 2, currentedit.warning)
  end
  
  component.gpu.setForeground(0xffff00)
  center(math.floor(gy / 2) - 4, currentedit.newdesc)
  component.gpu.setForeground(0x5555ff)
  center(math.floor(gy / 2) - 3, currentedit.newaddress)
  
  component.gpu.setForeground(0xffff00)
  center(math.floor(gy / 2) - 1, "Name to use:")
  component.gpu.setForeground(0x414141)
  local xp = center(math.floor(gy / 2), "[ " .. string.rep(" ", math.floor(gx * 0.75)) .. " ]")
  component.gpu.setForeground(0xffffff)
  term.setCursor(xp + 2, math.floor(gy / 2))
  print(currentedit.newname)
  
  -- buttons
  component.gpu.setForeground(0x414141)
  component.gpu.setBackground(0xff0000)
  term.setCursor(math.floor((gx /2 ) - string.len("[ Cancel ]")) - 2, math.floor(gy / 2) + 4)
  print("[ Cancel ]")
  
  component.gpu.setForeground(0xffffff)
  component.gpu.setBackground(0x0000ff)
  term.setCursor(math.floor((gx /2 ) + 2), math.floor(gy / 2) + 4)
  print("[   Ok   ]")

  component.gpu.setBackground(0x000000)
end


local function show_serverscreen()
  
  if currentedit.warning then
    component.gpu.setForeground(0xff0000)
    center(gy - 2, currentedit.warning)
  end
  
  component.gpu.setForeground(0xffff00)
  center(math.floor(gy / 2) - 4, currentedit.newdesc)
  component.gpu.setForeground(0x5555ff)
  center(math.floor(gy / 2) - 3, currentedit.newaddress)
  
  component.gpu.setForeground(0xffff00)
  center(math.floor(gy / 2), "Do you want to set entries on this server or name it?")
  
  -- buttons
  component.gpu.setBackground(0x00ff00)
  component.gpu.setForeground(0x414141)
  term.setCursor(math.floor((gx /2 ) - string.len("[ Change ]")) - 2, math.floor(gy / 2) + 2)
  print("[ Change ]")
  
  component.gpu.setForeground(0xffffff)
  component.gpu.setBackground(0x00ff00)
  term.setCursor(math.floor((gx /2 ) + 2), math.floor(gy / 2) + 2)
  print("[  Name  ]")

  component.gpu.setBackground(0x000000)
end


-- tunnels and network cards have slightly different syntax so we have a function handle it
--  command 'lookup' only needs remoteid, name and addressid
--  command 'update' will send all params given for name to remoteid
--  return will be the response from the server
local function modem_send(remoteid, cmd, name, addressid, descript)
  msgid = msgid + 1
  local device 
  if component.list("tunnel")() then
    -- linked tunnel
    device = component.tunnel
    
    device.send(ns_port, "ns", cmd, msgid, name, addressid, comptype, posX, posY, posZ)
  else
    -- modem
    device = component.modem
    
    device.open(ns_port)
    device.send(remoteid, ns_port, "ns", cmd, msgid, name, addressid, descript)
  end
  -- we wait for the response to this msgid and nothing else, if nothing comes back after 5 then nil will be returned
  local e, null, raddr, rport, null, null, rmsgid, msg1, msg2, msg3, msg4, msg5, msg6 = event.pull(5, "modem_message", nil, nil, ns_port, nil, "nsres", msgid)
  if component.list("modem")() then
    device.close(ns_port)
  end
  return msg1, msg2, msg3
end

local function changeserver() 
  term.clear()
  border()
  component.gpu.setForeground(0xffff00)
  center(math.floor(gy / 2), "Testing server")
  component.gpu.setForeground(0x555555)
  lastmessagetime = 900   -- error or idle should kick in before this
  
  -- Check the dns server is running on the selected address
  --  Unfortantly we only have the computer's address and we need to send to the network address
  --  so we need to broadcast an 'arp' request and the server that responds will be the address we use
  --  but we dont need to do that for linked cards since we dont need a remoteserver (leads the question of how did they get here?)
  local remoteid = "tunnel"      -- for a tunnel this is not used
  if component.list("modem")() then
    center(math.floor(gy / 2) + 1, "Finding network address")
    local device = component.modem
    
    device.open(ns_port)
    
    device.broadcast(ns_port, "arp", "who", 11, currentedit.newaddress)
    -- we only want the response from that machine so be very specfifc
    local e, localid
    e, localid, remoteid = event.pull(10, "modem_message", nil, nil, ns_port, nil, "arppong", nil, currentedit.newaddress)
    device.close(ns_port)
    if not e then
      errored("No network card responded for that server, does it have a wireless card?")
    end
  end

  center(math.floor(gy / 2) + 1, "        Testing response        ")
  local rname = modem_send(remoteid, "lookup", currentedit.newaddress)
  if rname == nil then
    errored("Server did not respond correctly to a NS query")
    return
  end
  
  if rname == "" then
    rname = "Server"
  end
  
  remotemachine = {
      desc = rname .. currentedit.newpos,
      computeraddress = currentedit.newaddress,
      address = remoteid
    }
  currentedit = nil
  lastmessagetime = 1
  component.computer.beep(800, 0.2)
  component.computer.beep(900, 0.3)
  
  term.clear()
  border()
  component.gpu.setForeground(0xffff00)
  center(math.floor(gy / 2), "Server has been selected")
  component.gpu.setForeground(0x555555)
  lastmessagetime = 3
end

local function sendtoserver()
  local rname = modem_send(remotemachine.address, "update", currentedit.newname, currentedit.newaddress, currentedit.newdesc)
  
  -- make sure the name saved was the name we set
  if rname ~= currentedit.newname then
    errored("Rename failed to save correctly, please try again")
    return
  end
  
  -- if the device being updated was the current name server update the display name to match
  if remotemachine.computeraddress == currentedit.newaddress then
    remotemachine.desc = rname .. currentedit.newpos
  end
  
  -- its done
  term.clear()
  border()
  component.gpu.setForeground(0xffff00)
  center(math.floor(gy / 2), "Component name saved")
  component.gpu.setForeground(0x555555)
  lastmessagetime = 3
  
  -- return back to the main screen
  currentedit = {}
end

local function ev_end()
  -- end the loop and listen commands
  running = false
end

-- param 2 of table_use contains the detail about what was scanned
-- with a navigation upgrade you get posX, posY, and posZ
-- with a analyser (barcode_reader) you get analyzed which contains the type of machine and its address
--   however something like an adapter may return nothing if its empty (so we ignore that situation)

local function ev_tablet_use(e, b)
    if not b or not b.analyzed or b.analyzed["n"] < 1 then
      errored("No component is installed/available")
      return
    end
    
    -- analyzed only ever seems to have 1 item it, even a computer with multiple components only returns its address
    --  may need to do a 'for idx = 1, b.analyzed["n"] do' loop in the future if it returns components or more
    --  for now we just take the first result
    local idx = 1
    
    if not remotemachine and b.analyzed[idx].type ~= "computer" then
      -- would make more sense to do this at the top, but since we set everything for currentedit before this point
      --  its easier to error here
      currentedit = nil
      errored("Cannot name this device, no server selected")
      return
    end
    
    
    currentedit = {}
    if b.analyzed["n"] > 1 then
      currentedit.warning = "Multiple addresses returned, only first was used"
    end
    currentedit.newgpsX = false
    currentedit.newgpsZ = false
    currentedit.newgpsY = false
    currentedit.newpos = ""
    currentedit.newdesc = ""
    currentedit.newname = ""
    
    if hasGPS then
      currentedit.newgpsX = b.posX + gpsX;
      currentedit.newgpsZ = b.posZ + gpsZ;
      currentedit.newgpsY = b.posY;
      
      currentedit.newpos = " at X:" .. currentedit.newgpsX .. ", Y:" .. currentedit.newgpsY .. ", Z:" .. currentedit.newgpsZ
      currentedit.newname = "_" .. abs(currentedit.newgpsX) .. "_" .. abs(currentedit.newgpsY) .. "_" .. abs(currentedit.newgpsZ)
    end
    currentedit.newtype = b.analyzed[idx].type
    currentedit.newaddress = b.analyzed[idx].address
    currentedit.newdesc = string.upper(string.sub(currentedit.newtype, 0, 1)) .. string.sub(currentedit.newtype, 2) .. currentedit.newpos
    currentedit.newname = currentedit.newtype .. currentedit.newname
    
    -- if it already has a name lets use that instead
    if remotemachine then
      local rname = modem_send(remotemachine.address, "lookup", currentedit.newaddress)
      if rname == nil then
        errored("Name Server is not responding")
        return
      elseif rname ~= "" then
        -- empty string is not defined, otherwise we show the current name
        currentedit.newname = rname
      end
    end
    
    lastmessagetime = 600     -- give up after 10 minutes

    -- If the device is a computer then it could be a server
    --   if its the first selection assume its a server select
    --   otherwise ask if its a server change or a device name
    --   remember: if they select the option to name then we need all of the above set
    if b.analyzed[idx].type == "computer" then
      -- todo: what happens with a rack here? it reports as computer but what address is it giving?
      
      if remotemachine then
        currentedit.mode = 1;
        
        term.clear()
        border()
        show_serverscreen()
        component.computer.beep(800, 0.3)
        component.computer.beep(850, 0.2)
        return
      end
      
      changeserver()
      return
    end
    
    term.clear()
    border()
    show_namescreen()
    component.computer.beep(600, 0.3)
end

local function ev_key_up(null, null, ascii)
  if ascii == 113 and not currentedit then
    -- 113 = q, when pressed during idle exit the program
    ev_end()
    return
  end
  -- ignore any other keypress when not in edit mode
  if not currentedit then
    return
  end
  
  -- if in select mode only enter, N and C work
  if currentedit.mode == 1 then
    if ascii == 13 or ascii == 110 then     -- 13 = enter, 110 = n -- name
      currentedit.mode = nil
      term.clear()
      border()
      show_namescreen()
      lastmessagetime = 600     -- reset the give up time to 10 minutes
    end
    if ascii == 99 then     -- 99 = c -- change
      changeserver()
    end
  
    return
  end
  
  if ascii == 13 then     -- 13 = enter
    sendtoserver()
  elseif ascii == 27 then     -- 27 = escape
    -- we treat this as cancel, it does have the result that it would close the tablet so it may then request
    --  the item to be selected again - if this is annoying we could remove this and add a button?
    currentedit = {}
    lastmessagetime = 1       -- return back to idle
	elseif ascii == 8 then      -- 8 = backspace
		if string.len(currentedit.newname) > 1 then
			currentedit.newname = string.sub(currentedit.newname, 1, string.len(currentedit.newname) - 1)
		else
			currentedit.newname = ""
		end
  elseif (ascii == 32 or ascii == 46 or ascii == 95       -- space, dot, underscore
      or (ascii >= 48 and ascii <= 57)                    -- 0-9
      or (ascii >= 65 and ascii <= 80)                    -- a-z 
      or (ascii >= 97 and ascii <= 122)) then             -- A-Z
		currentedit.newname = currentedit.newname .. string.char(ascii)
	end  
  show_namescreen()
  lastmessagetime = 600     -- reset the give up time to 10 minutes
end

local function ev_touch(null, null, x, y)
  -- ignore any other touches when not noithing is available
  if not currentedit then
    return
  end
  
  local buttonline = math.floor(gy / 2)
  local mid = math.floor(gx /2 )
  
  if currentedit.mode == 1 then
    if y ~= buttonline + 2 then
      return
    end
    local buttonsize = string.len("[ Change ]") 
    
    -- Change button
    if x < mid - 2 and x > mid - 2 - buttonsize then
      changeserver()
      return
    end
    
    -- Name button
    if x > mid + 2 and x < mid + 2 + buttonsize then
      currentedit.mode = nil
      term.clear()
      border()
      show_namescreen()
      lastmessagetime = 600     -- reset the give up time to 10 minutes
      return
    end
    
    return
  else
    if y ~= buttonline + 4 then
      return
    end
    local buttonsize = string.len("[ Cancel ]");
    -- cancel button (same as escape)
    if x < mid - 2 and x > mid - 2 - buttonsize then
      currentedit = {}
      lastmessagetime = 1       -- return back to idle
      return
    end
    
    -- okay button (same as enter)
    if x > mid + 2 and x < mid + 2 + buttonsize then
      sendtoserver()
      return
    end
  end
end


--testaddr = "16bb1ab8-0170-4f81-810b-6f7cbece5374"
--local newname = modem_send(testaddr, "lookup", testaddr)

-- Setup the events (key_up seemes buggy here, so using key_down)
event.listen("key_down", ev_key_up)
event.listen("touch", ev_touch)
event.listen("tablet_use", ev_tablet_use)
event.listen("interupted", ev_end)

-- Main loop
while running do
  if lastmessagetime == 1 then
    waiting()
    lastmessagetime = 0
  elseif lastmessagetime < 1 then
    lastmessagetime = 0
  else
    lastmessagetime = lastmessagetime - 1
  end
  
  -- wait 1 second for the above to apply
  local e, b, c = event.pull(1)
  
end

-- program has been told to exit (q pressed?), we dont want to listen for the events anymore
term.clear()
event.ignore("key_up", ev_key_up)
event.ignore("touch", ev_touch)
event.ignore("table_use", ev_tablet_use)
event.ignore("interupt", ev_end)

