--[[ Component name system (CNS) - Name Server
     Author: nzHook
     Created for the Youtube channel https://youtube.com/user/nzHook 2019
     myRail Episode Showing Usage: https://youtu.be/lp_uL_2OQrU (episode 42)
     
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
--   -- Add the file to .rc.sh so it starts on boot (note: it runs in the background so you will be returned to the prompt)
--   -- Make a tablet with dns_name installed (see dns_name)
--   -- With the tablet select the computer running this code
--   -- Use the tablet to set names
--   -- Include the cns library in your code
--   -- Use cns("name you used") to reference a named component
---
local event = require("event")
local component = require("component")

-- config
local ns_port = 53

-- initial vars
local names = {}
local interactive = io.output().tty
local gpu
if interactive then
  gpu = component.gpu
end

-- load saved state into memory
local nsfile = io.open("/.comps", "r")
if nsfile then
  -- File format is similar as a hosts file, just with a comment field for identifying
  --  address componentname   comment
  local line
  for line in nsfile:lines() do
    if string.sub(line, 1, 1) ~= "#" then  -- allow for comments (although be aware this is for the internal ones, manual ones would be lost on save)
      local entry = {}
      local a, n, c = string.match(line, "^([%x-]+)%s+([%w_]+)%s*#%s*(.*)$", 1)
      if not a or not n then
        print("WARNING", line, "does not match correct format for component file, it will be removed on next save")
      else
        -- by componentid
        names[n] = {response = a, name = n, address = a, comment = c}
        -- by name
        names[a] = {response = n, name = n, address = a, comment = c, reverse = true}
      end
    end
  end
  nsfile:close()  
end


-- functions
local function log(raddr, cmd, msg1, msgid, ...)
  local args = table.pack(...)
  if interactive then gpu.setForeground(0xCC7777) end
  io.write("[" .. os.date("%T") .. "] ")
  if interactive then gpu.setForeground(0x44CC00) end
  io.write(cmd)
  if msgid then
    if interactive then gpu.setForeground(0xCC7777) end
    io.write("[" .. msgid .. "] ")
  else
    io.write(" ")
  end
  if raddr then
    if interactive then gpu.setForeground(0xCC7777) end
    io.write(string.sub(raddr, 1, 3) .. ".." .. string.sub(raddr, 34, 37) .. " ")
  end
  if interactive then gpu.setForeground(0x44CC00) end
  io.write(msg1 .. " ")
  if interactive then gpu.setForeground(0xFFFFFF) end
  io.write(table.concat(args, " "))
  io.write("\n")
end

-- write the names stored in memory back to disk
local function savenames()
  local nsfile = io.open("/.comps", "w")
  nsfile:write("# Component ID mapping\n")
  nsfile:write("# This file is read on startup, any changes made while ns_server is running will be lost\n")
  nsfile:write("# All comments but these will be removed\n")
  for k, v in pairs(names) do
    if not v.reverse then
      nsfile:write(v.address .. "  " .. v.name .. "  # " .. v.comment .. "\n")
    end
  end
  nsfile:write("# End of list\n")
  nsfile:close()
end


-- the internal function which works out the name (note its global)
function cns(address)
  -- default return should always be what was passed in
  local ret = address
  -- other values are blank strings
  local retname = ""
  local retaddress = ""
  
  if names[address] then
    ret = names[address].response
    retname = names[address].name
    retaddress = names[address].address
  else
    print("No name found for", address)
  end
  
  return ret, retname, retaddress
end

-- the communication api for remote devices like the tablet
local function dns_comms(e, compid, raddr, rport, null, proto, cmd, msgid, msg1, msg2, msg3, msg4, msg5, msg6) 
  if rport ~= ns_port then
    -- not a message for us
    return
  end
  local modem = component.proxy(compid)
  if proto == "arp" and cmd == "who" then
    -- an arp request is to find the computers network id, we only need to respond if its us
    if msg1 == component.computer.address then
      log(raddr, "ARP", msg1, msgid, "arppong", component.computer.address)
      modem.send(raddr, ns_port, "arppong", msgid, component.computer.address)
    end
    
    return
  end
  if proto == "ns" then
    if cmd == "lookup" then
      local returnname = ""
      -- lets see if we can find the address in our local records, we send back the name and address from cns which maybe a set of blank strings (indicating nothing exists)
      local resp, lname, laddress = cns(msg1)
      modem.send(raddr, ns_port, "nsres", msgid, lname, laddress, resp)
      log(raddr, "QUERY", msg1, msgid, lname, laddress, resp)
    elseif cmd == "update" then
      -- save the detail back to memory and to disk
      -- TODO: Should do some validation here just in case
      names[msg1] = {response = msg2, name = msg1, address = msg2, comment = msg3}
      names[msg2] = {response = msg1, name = msg1, address = msg2, comment = msg3, reverse = true}
      savenames()
      
      -- Pull what is saved and return that back
      local null, lname, laddress = cns(msg1)
      log(raddr, "UPDATE", msg1, msgid, lname, laddress)
      modem.send(raddr, ns_port, "nsres", msgid, lname, laddress)
    end
    
  end
  
  -- ignore any unknown commands
end

-- should we loop through all the modems and open the port? Testing seems to indicate this opens on all modems
for comp, _ in component.list("modem") do
  if(not component.invoke(comp, "open", ns_port)) then
    error("Failed to open port " .. tostring(ns_port) .. " on " .. comp)
  end

  log(nil, "START", "CNS server address=" .. comp .. ":" .. ns_port, nil)
end

event.listen("modem_message", dns_comms)
-- event code will now listen in the background, we return back to the OS

print("CNS Server loaded in background")


-- override the component functions with a custom one that does a lookup before passing to the original
local componentrealget = component.get
local componentrealproxy = component.proxy
function component.get(address, componentType)
  checkArg(1, address, "string")
  
  -- if address does not contain a - then see if we have a local name for it
  if not string.match(address, "-") then
    local ret, addr, name = cns(address)
    -- if cns does not know the answer it returns the same value back, so we dont need to check it
    address = ret
  end
  
  return componentrealget(address, componentType)
end


function component.proxy(address)
  checkArg(1, address, "string")
  
  -- if address does not contain a - then see if we have a local name for it
  if not string.match(address, "-") then
    local ret, addr, name = cns(address)
    -- if cns does not know the answer it returns the same value back, so we dont need to check it
    address = ret
  end
  
  return componentrealproxy(address)
end

