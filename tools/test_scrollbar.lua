-- The scroll bars go the way they are dragged.
--
-- The owner found the Sell list's bar backwards (2026-11-24): dragging the
-- thumb down scrolled the list up. On Forever the game's vertical Slider runs
-- the wrong way (Butler met it first, 2026-10-13), and every Tradeskills list,
-- scroll frame and the import box used one. The bar is now drawn and dragged
-- by hand: the thumb sits `value` steps down from the top and follows the
-- cursor while held.
--
-- What must hold:
--   1. No scroll bar is the game's Slider.
--   2. Dragging the thumb down shows rows further down; up goes back up.
--   3. A press below the thumb jumps down, above it jumps up.
--   4. The thumb sits at the top at the start and at the bottom at the end.
--   5. The wheel and code still move the list, and the thumb follows.

local ns = {}
ns.Theme = {
    Fill = function() return { SetColorTexture = function() end, SetAlpha = function() end } end,
    Unpack = function() return 0, 0, 0, 1 end,
    Border = function() end,
    CreateLabel = function() return {} end,
    AccentStripe = function(frame) return frame:CreateTexture() end,
}

local made = {}

local function Frame(kind)
    local frame = { points = {}, scripts = {}, shown = true, height = 0, width = 0, kind = kind }
    frame.SetHeight = function(self, h) self.height = h end
    frame.GetHeight = function(self) return self.height end
    frame.SetWidth = function(self, w) self.width = w end
    frame.SetSize = function(self, w, h) self.width, self.height = w, h end
    frame.SetPoint = function(self, point, ...)
        local args = { ... }
        if type(args[1]) == "table" then
            self.points[point] = { x = args[3], y = args[4] }
        else
            self.points[point] = { x = args[1], y = args[2] }
        end
    end
    frame.ClearAllPoints = function(self) self.points = {} end
    frame.Show = function(self) self.shown = true end
    frame.Hide = function(self) self.shown = false end
    frame.IsShown = function(self) return self.shown end
    frame.SetShown = function(self, on) self.shown = on and true or false end
    frame.SetScript = function(self, name, fn) self.scripts[name] = fn end
    frame.GetScript = function(self, name) return self.scripts[name] end
    frame.HookScript = function(self, name, fn)
        local before = self.scripts[name]
        self.scripts[name] = function(...) if before then before(...) end fn(...) end
    end
    frame.GetTop = function(self) return self.top end
    frame.GetEffectiveScale = function() return 1 end
    frame.CreateTexture = function() return Frame("Texture") end
    return setmetatable(frame, { __index = function() return function() end end })
end

CreateFrame = function(kind)
    local frame = Frame(kind)
    made[#made + 1] = frame
    return frame
end

local cursorY = 0
GetCursorPosition = function() return 0, cursorY end

local Widgets
do
    local chunk = assert(loadfile(lfs_cwd .. "/UI/Widgets.lua"))
    chunk("Blackthornes_TS", ns)
    Widgets = ns.Widgets
end

local passed, failed = 0, 0
local function check(label, got, want)
    local ok = got == want
    if ok then passed = passed + 1 else failed = failed + 1 end
    print(string.format("  %-56s %-8s %s", label, tostring(got), ok and "ok" or
        ("WRONG, wanted " .. tostring(want))))
end

print("")
print("the scroll list's bar")

local list = Widgets.CreateScrollList(Frame("Frame"), { rowHeight = 20 })
list:SetHeight(200) -- ten rows on screen
local bar = list.scrollbar
bar.height = 200
bar.top = 500
local data = {}
for i = 1, 50 do data[i] = { name = "row " .. i } end
list:SetData(data)

-- 1.
local sliders = 0
for _, frame in ipairs(made) do if frame.kind == "Slider" then sliders = sliders + 1 end end
check("no bar is the game's Slider", sliders, 0)
check("the list can scroll 40 rows", select(2, bar:GetMinMaxValues()), 40)

-- The thumb is 200 * 10 / 50 = 40 tall, so it travels 160 pixels for 40 rows.
check("the thumb starts at the top", bar.ThumbTop and bar:ThumbTop(), 0)

-- 2. Catch the thumb 10 pixels into it and drag it 80 pixels down.
local down, up, update = bar:GetScript("OnMouseDown"), bar:GetScript("OnMouseUp")
cursorY = 500 - 10
if down then down(bar, "LeftButton") end
check("a press on the thumb does not move the list", list.offset, 0)
update = bar:GetScript("OnUpdate")
cursorY = 500 - 90
if update then update(bar) end
check("dragging down scrolls down", list.offset, 20)
cursorY = 500 - 50
if update then update(bar) end
check("dragging back up scrolls up", list.offset, 10)
if up then up(bar) end
check("letting go stops following", bar:GetScript("OnUpdate"), nil)

-- 3.
list.offset = 0
list:Refresh()
cursorY = 500 - 190
if down then down(bar, "LeftButton") end
if up then up(bar) end
check("a press low on the bar jumps down", list.offset >= 35, true)
cursorY = 500 - 5
if down then down(bar, "LeftButton") end
if up then up(bar) end
check("a press high on the bar jumps up", list.offset, 0)

-- 4. and 5.
list.offset = 40
list:Refresh()
check("at the end the thumb is at the bottom", bar.ThumbTop and bar:ThumbTop(), 160)
list:GetScript("OnMouseWheel")(list, 1)
check("the wheel turned up scrolls up", list.offset, 37)
check("and the thumb follows", bar:GetValue(), 37)

print("")
print("the scroll frame's bar")

made = {}
local scroll = Widgets.CreateScrollFrame(Frame("Frame"), {})
local sbar = scroll.scrollbar
sliders = 0
for _, frame in ipairs(made) do if frame.kind == "Slider" then sliders = sliders + 1 end end
check("no bar is the game's Slider", sliders, 0)
local scrolled
scroll.SetVerticalScroll = function(_, value) scrolled = value end
sbar.height, sbar.top = 100, 300
sbar:SetMinMaxValues(0, 300)
sbar:SetThumbHeight(25)
cursorY = 300 - 5
sbar:GetScript("OnMouseDown")(sbar, "LeftButton")
cursorY = 300 - 5 - 75 -- all the way down
sbar:GetScript("OnUpdate")(sbar)
sbar:GetScript("OnMouseUp")(sbar)
check("dragging to the bottom scrolls to the end", scrolled, 300)
sbar:SetValue(100)
check("code moving the bar scrolls the frame", scrolled, 100)

print("")
print(string.format("%d passed, %d failed", passed, failed))
if failed > 0 then error(failed .. " scroll bar check(s) failed") end
