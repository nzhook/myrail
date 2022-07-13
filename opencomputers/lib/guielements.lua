--[[ GUI elements lib
     Created for the Youtube channel https://youtube.com/user/nzHook 2022
     First myRail Episode Showing Usage: https://youtu.be/SJz_lrf4hQo
          
    Various elements are available
      - Buttons
          USAGE
      - Text input
          USAGE
      - Border with title
      
          
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
local term = require("term")
local textlib = require("text")
local component = require("component")
local keyboard = require("keyboard")

local gpu = component.gpu
local gui = {}
local guiw, guih = gpu.getResolution()
local buttons = {}
local extrabuttons = {}

-- override the normal in-event error handler
event.onError = function (msg) 
  if msg and msg.reason == "terminated" then
    -- ?? why is terminated an error?
    event.push("interupted")
    return false
  end
  
  gui.debugvar(msg)
  component.computer.beep(500, 0.5)
  component.computer.beep(400, 1)
  gpu.setForeground(0xffff00)
  print("ERROR", msg)
  gpu.setForeground(0xff0000)
  gpu.setBackground(0x0000ff)
  print(debug.traceback(nil, 2))
  gpu.setBackground(0x000000)
  gpu.setForeground(0xffff00)
  print("RESULT: ", msg)
  running = false
  gpu.setForeground(0xffffff)
  
  -- kill off the event handlers, as we are in a lib we dont know what was set
  --  so we use the handler values, this does kill off some of the general openOS ones
  --  but theres no way to know which they are :(
  for _, v in pairs(event.handlers) do
    if string.sub(v.key, 0, 9) ~= "component" and string.sub(v.key, 0, 6) ~= "screen" then
      --print("Deregistering event", v.key)
      event.ignore(v.key, v.callback)
    end
  end
  os.exit()
end


local log = {}
function gui.print(...)
    -- We track previous messages to show in the GUI
    for x = 1, 20 do
        log[x] = log[x + 1]
    end
    
    log[20] = ""
    local args = table.pack(...)
    for i = 1, args.n do
      log[20] = log[20] .. " " .. tostring(args[i])
    end
end

function gui.debugvar(var)
    print(require("serialization").serialize(var, 1024))
end

function gui.box(x, y, w, h, title, bordercolor, titlecolor, backgroundcolor, clearcontent)
  local curx, cury = term.getCursor()
  local titleleft = "[ "
  local titleright = " ]"

  if not w then
    w = guiw - x
  elseif w < 0 then
    w = guiw + w
  end
  if not h then
    h = guih - y
  elseif h < 0 then
    h = guih + h
  end
  if not x then
    x = math.floor((guiw - w) / 2)
  end
  if not y then
    y = math.floor((guih - h) / 2)
  end
  if not title then
    title = ""
    titleleft = ""
    titleright = ""
  elseif string.len(titleleft .. title .. titleright) >= w - 3 then
    titleleft = "["
    titleright = "]"
  end

  if backgroundcolor then
    gpu.setBackground(backgroundcolor)
  end
  if bordercolor then
    gpu.setForeground(bordercolor)
  end
  gpu.set(x, y, "┌─" .. titleleft .. title .. titleright .. string.rep("─", w - 3 - string.len(titleleft .. title .. titleright)) .. "┐")
  if titlecolor then
    gpu.setForeground(titlecolor)
  end
  gpu.set(x + string.len(titleleft) + 2, y, title)
  
  if bordercolor then
    gpu.setForeground(bordercolor)
  end
  if clearcontent then
    for l = 1, h - 2 do
      gpu.set(x, y + l, "│" .. string.rep(" ", w - 2) .. "│")
    end
  else
    for l = 1, h - 2 do
      gpu.set(x, y + l, "│")
      gpu.set(x + w - 1, y + l, "│")
    end
  end
  
  gpu.set(x, y + h - 1, "└" .. string.rep("─", w - 2) .. "┘")
  if bordercolor or titlecolor then
    gpu.setForeground(0xffffff)
  end
  if backgroundcolor then
    gpu.setBackground(0x000000)
  end
  
  return x, y, w, h
end

function gui.printcenter(y, text, w, startx)
  if not w then
    w = guiw
  end
  if not startx then
    startx = 0
  end
  local x = math.floor((w / 2) - (string.len(text) / 2)) + startx
  gui.set(x, y, text)
  return x
end

function gui.printinbox(x, y, text, w)
  if not w then
    w = guiw
  end
  local l
  local more = true
  while more do
    l, text, more = textlib.wrap(text, w, w)
    gui.set(x, y, l)
    y = y + 1
  end
  
  return y
end

-- Buttons
-- Add a button to the list
  -- text = The label
  -- call = Function to call
  -- side = 0=auto,1=middle,2=left,3=right
  -- extraparams = Anything for internal use (button is passed into call with this value available)
  -- othercolor = Optional background colour (eg. for a cancel button)
  -- textcolor = Optional colour of text
  -- bordercolor = Optional colour of the border around the button
function gui.button(text, call, side, extraparams, othercolor, textcolor, bordercolor)
  
  if not othercolor then
    othercolor = 0xffff00
  end
  if not textcolor then
    textcolor = 0x000000
  end
  if not bordercolor then
    bordercolor = 0xffffff
  end
  
  
	local bdetail = {
    ["text"] = text,
    ["side"] = side,
    ["call"] = call,
    ["params"] = extraparams,
    ["othercolor"] = othercolor,
    ["bordercolor"] = bordercolor,
    ["textcolor"] = textcolor,
    -- These are worked out on display but lets set them here
    ["row"] = nil,
    ["xl"] = nil,
    ["xr"] = nil,
    ["yt"] = nil,
    ["yb"] = nil,
    ["size"] = nil
	}
	table.insert(buttons, bdetail)
end

function gui.reset()
  buttons = {}
  extrabuttons = {}
end

local function _drawbutton(startp, endp, row, bdetail, bigbut) 
  local len
  if bdetail["text"] then
    len = string.len(bdetail["text"])
  else
    len = 1
  end
  
  starttxt = math.floor(((endp - startp - len) / 2) + startp)
  
  gpu.setBackground(bdetail["othercolor"])
  gpu.setForeground(bdetail["textcolor"])
  gpu.set(startp, row, " " .. string.rep(" ", math.ceil((bigbut - len) / 2) - 1) .. bdetail["text"] .. string.rep(" ", math.floor((bigbut - len) / 2)))
  gpu.setForeground(bdetail["bordercolor"])
  gpu.setBackground(0x000000)
  gpu.set(startp - 1, row, "│")
  gpu.set(endp + 1, row, "│")
  gpu.set(startp - 1, row - 1, "┌" .. string.rep("─", bigbut) .. "┐")
  gpu.set(startp - 1, row + 1, "└" .. string.rep("─", bigbut) .. "┘")
	gpu.setForeground(0x00ff00)
	gpu.setBackground(0x000000)
end

function gui.buttonxy(x, y, text, call, extraparams, size, othercolor, textcolor, bordercolor)
  if not othercolor then
    othercolor = 0xffff00
  end
  if not textcolor then
    textcolor = 0x000000
  end
  if not bordercolor then
    bordercolor = 0xffffff
  end
  if not size then
    size = string.len(text)
  end
  
  if size % 2 == 1 then
    size = size + 1
  end
  
	local bdetail = {
    ["text"] = text,
    ["side"] = -1,
    ["call"] = call,
    ["params"] = extraparams,
    ["othercolor"] = othercolor,
    ["bordercolor"] = bordercolor,
    ["textcolor"] = textcolor,
    -- These are worked out on display but lets set them here
    ["row"] = y,
    ["xl"] = x,
    ["xr"] = x + size,
    ["yt"] = y - 1,
    ["yb"] = y + 1,
    ["size"] = size + 2
	}
	table.insert(buttons, bdetail)
  
  _drawbutton(x, x + size + 1, y, bdetail, size + 2)
  gpu.setForeground(0xffffff)
end


function gui.numberselect(x, y, w, initial, call, extraparams, pad, min, max, nilok, othercolor, numbercolor, bordercolor)
  if not pad then
    pad = " "
  end
  if not initial then
    initial = 0
  end
  local suffix, prefix = ""
  if w > string.len(max) and w > string.len(min) then
    suffix = " "
    prefix = " "
  end
  if othercolor then
    gpu.setBackground(othercolor)
  else
    gpu.setBackground(0xffff00)
  end
  if numbercolor then
    gpu.setForeground(numbercolor)
  else
    gpu.setForeground(0x000000)
  end
  
	local bdetail1 = {
    ["type"] = "number",
    ["action"] = "dec",
    ["text"] = "«",
    ["value"] = initial,
    ["size"] = 1,
    ["call"] = call,
    ["params"] = extraparams,
    ["min"] = min,
    ["max"] = max,
    ["nilok"] = nilok,
    ["othercolor"] = othercolor,
    ["bordercolor"] = bordercolor,
    ["textcolor"] = numbercolor,
    ["xl"] = x + 1,
    ["xr"] = x + 1,
    ["yt"] = y,
    ["yb"] = y
	}
  
	local bdetail2 = {
    ["type"] = "number",
    ["action"] = "inc",
    ["text"] = "»",
    ["value"] = initial,
    ["size"] = 1,
    ["call"] = call,
    ["params"] = extraparams,
    ["min"] = min,
    ["max"] = max,
    ["nilok"] = nilok,
    ["othercolor"] = othercolor,
    ["bordercolor"] = bordercolor,
    ["textcolor"] = numbercolor,
    ["xl"] = x + w - 2,
    ["xr"] = x + w - 2,
    ["yt"] = y,
    ["yb"] = y
	}
  
  gpu.set(x + 2, y, string.rep(pad, w - 4 - string.len(prefix .. initial .. suffix)) .. prefix .. initial .. suffix)
  gpu.setBackground(0x0)
  if bordercolor then
    gpu.setForeground(bordercolor)
  else
    gpu.setForeground(0xffffff)
  end
  gpu.set(x, y, "[")
  if initial > min or (nilok and initial ~= 0) then
    gpu.set(x + 1, y, bdetail1["text"])
    table.insert(extrabuttons, bdetail1)
  end
  if initial < max then
    gpu.set(x + w - 2, y, bdetail2["text"])
    table.insert(extrabuttons, bdetail2)
  end
  gpu.set(x + w - 1, y, "]")

  gpu.setForeground(0xffffff)
end

function gui.clickable(x, y, text, call, extraparams, w)
  if not w then
    w = string.len(text)
  end
  
	local bdetail = {
    ["type"] = "string",
    ["text"] = text,
    ["size"] = w,
    ["call"] = call,
    ["params"] = extraparams,
    ["xl"] = x,
    ["xr"] = x + w,
    ["yt"] = y,
    ["yb"] = y
	}
  
  gpu.set(x, y, text)
  table.insert(extrabuttons, bdetail)
end


function gui.scrollbar(x, y, h, current, total, call, extraparams, othercolor, locationcolor, arrowcolor)
	local bdetail1 = {
    ["type"] = "number",
    ["action"] = "dec",
    ["text"] = "▲",
    ["value"] = current,
    ["total"] = total,
    ["size"] = 1,
    ["call"] = call,
    ["params"] = extraparams,
    ["othercolor"] = othercolor,
    ["locationcolor"] = locationcolor,
    ["arrowcolor"] = arrowcolor,
    ["min"] = 1,
    ["max"] = total,
    ["xl"] = x,
    ["xr"] = x,
    ["yt"] = y,
    ["yb"] = y
	}
  
	local bdetail2 = {
    ["type"] = "number",
    ["action"] = "inc",
    ["text"] = "▼",
    ["value"] = current,
    ["total"] = total,
    ["size"] = 1,
    ["call"] = call,
    ["params"] = extraparams,
    ["min"] = 1,
    ["max"] = total,
    ["othercolor"] = othercolor,
    ["locationcolor"] = locationcolor,
    ["arrowcolor"] = arrowcolor,
    ["xl"] = x,
    ["xr"] = x,
    ["yt"] = y + h,
    ["yb"] = y + h
	}  
  
  local hasscroll = false
  local pos = math.floor((current / (total - h)) * (h - 2))
  if current == 1 then
    pos = 0
  end
  
  if arrowcolor then
    gpu.setForeground(arrowcolor)
  end
  if current > 1 then
    gui.set(x, y, bdetail1["text"])
    table.insert(extrabuttons, bdetail1)
  end
  if current + h < total then
    gui.set(x, y + h, bdetail2["text"])
    table.insert(extrabuttons, bdetail2)
  end
  if current > 1
    or current + h < total then
      if othercolor then
        gpu.setForeground(othercolor)
      end
      
      gui.set(x, y + 1, string.rep("░", h - 1), true)
      
      if locationcolor then
        gpu.setForeground(locationcolor)
      end
      gui.set(x, y + 1 + pos, "▓")
      
      hasscroll = true
  end
  
  gpu.setForeground(0xffffff)
  return hasscroll
end


-- Calculate the positions and display (centered)
  -- x=start from this col
  -- y=start from this row
  -- w=width of box to center in
  -- h=height of box to center in (-1 = dont center)
  -- todo: left/right vs up/down
function gui.displaybuttons(x, y, w, h)
	-- determine the largest button size
	local bigbut = 0
	local numrows = 0
	local prevside = 3
  if not x then
    x = 1
  end
  if not y then
    y = 1
  end
  if not w then
    w = guiw
  end
  if not h then
    h = guih
  end

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
	local middle = math.floor(w / 2) + x
	local startl = middle - bigbut - 2
	local startr = middle + 2

	local startrow = y + 1
  if h > 0 then
    startrow = (math.floor(h / 2) - math.ceil(numrows * 2)) + y
  end
	local counter = 0
	for text, bdetail in pairs(buttons) do
		local endp
		local startp
		counter = counter + 1
    
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
      _drawbutton(startp, endp, row, bdetail, bigbut)
    end
  end
end


-- Take care when someone presseses one of the buttons
function gui.ev_touch(e, id, x, y, keymodifer, user)
	for text, bdetail in pairs(buttons) do
		if not bdetail["xl"] then
			-- The buttons were not shown dont keep going
			break
		end
    
		if x >= bdetail["xl"] and x <= bdetail["xr"] 
			and y >= bdetail["yt"] and y <= bdetail["yb"] then
				-- thats a valid button click highliht it then call the function
				gpu.setBackground(0xff0000)
				gpu.setForeground(0x000000)
				gpu.set(bdetail["xl"], bdetail["yt"] + 1, " " .. bdetail["text"] .. string.rep(" ", bdetail["size"] - string.len(bdetail["text"]) - 1))
				gpu.setForeground(0x00ff00)
				gpu.setBackground(0x000000)
				
				return bdetail
		end
	end
  
  -- These buttons are related to other items and not generated by showbuttons
	for text, bdetail in pairs(extrabuttons) do
		if x >= bdetail["xl"] and x <= bdetail["xr"] 
			and y >= bdetail["yt"] and y <= bdetail["yb"] then
				-- thats a valid button click highliht it then call the function
				gpu.setBackground(0xff0000)
				gpu.setForeground(0x000000)
				gpu.set(bdetail["xl"], bdetail["yt"], bdetail["text"] .. string.rep(" ", bdetail["size"] - string.len(bdetail["text"]) - 1))
				gpu.setForeground(0x00ff00)
				gpu.setBackground(0x000000)
        
        if bdetail["type"] == "number" then
          adjvalue = 1
          -- if cntrl is pressed then we increment/decrement by 10
          if keyboard.isControlDown() then
            adjvalue = 10
            
            -- and if its ctrl-shift then its 100
            if keyboard.isShiftDown() then
              adjvalue = 100
            end
          end
          
          if bdetail["action"] == "dec" then
            bdetail["value"] = bdetail["value"] - adjvalue
          else
            if bdetail["nilok"] and bdetail["min"] and bdetail["value"] < bdetail["min"] then
              bdetail["value"] = bdetail["min"] - 1 + adjvalue
            else
              bdetail["value"] = bdetail["value"] + adjvalue
            end
          end
          
          if bdetail["min"] then
            if bdetail["nilok"] and bdetail["value"] < bdetail["min"] then
              bdetail["value"] = 0
            else
              bdetail["value"] = math.max(bdetail["value"], bdetail["min"])
            end
          end
          if bdetail["max"] then
            bdetail["value"] = math.min(bdetail["value"], bdetail["max"])
          end
        end
        
				return bdetail
		end
	end
  
	return false
end

function gui.error(text)
	gpu.setForeground(0xff0000)
	center(math.floor(guih / 2) - 2, text)
	gpu.setForeground(0x555555)
	component.computer.beep(300, 0.2)
	component.computer.beep(200, 0.5)
end


-- also include these so everything is contained in one place
gui.set = gpu.set
gui.setCursor = term.setCursor
gui.setForeground = gpu.setForeground
gui.setBackground = gpu.setBackground
return gui
