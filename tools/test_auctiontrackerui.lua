-- UI/AuctionTracker.lua (My Auctions) outside WoW.
--
-- What must hold:
--   1. Time left reads "2d", "5h", "12m", "~" before a rough end.
--   2. Off draws nothing; on shows the window with a row per auction,
--      "Sold Today:" and the "%d up" foot; nothing up shows the empty line.
--   3. A sale on Full lights the row, stamps SOLD, pops the gold, slides
--      the row away and counts Sold Today up to the new total.
--   4. Subtle fades it out with no stamp; Off just redraws.
--   5. A row that runs out fades with no gold.
--   6. Transparent thins the glass; the place is kept and Set Default
--      clears it.
--   7. A new post below the rows that show scrolls into sight; a thumb
--      shows while the list is longer than the window.

local GLOBALS = { "CreateFrame", "UIParent", "CreateColor", "GameTooltip", "Minimap", "GetTime",
    "time", "C_Timer", "UISpecialFrames", "tinsert", "date" }
local saved = {}
for _, key in ipairs(GLOBALS) do saved[key] = _G[key] end

local function noop() end

--- The words a label draws, without colour codes.
local function Plain(text)
    return (tostring(text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

--- Characters, not bytes: the dot between professions is two bytes.
local function Length(text)
    return #(Plain(text):gsub("[\128-\191]", ""))
end

-- Frames, textures and font strings in one. Words are half their font size
-- wide per character. GetStringWidth stops at a fixed-width label's width,
-- as a retail client's can; GetUnboundedStringWidth measures all of it.
local function Region(parent, frameType)
    local level = type(parent) == "table" and rawget(parent, "frameLevel") or 0
    local region = { frameType = frameType, parent = parent, shown = true, alpha = 1,
        width = 0, height = 0, points = {}, scripts = {}, events = {}, children = {},
        textures = {}, strings = {}, fontSize = 12, wrap = false, frameLevel = level + 1 }

    region.Show = function(self)
        local was = self.shown
        self.shown = true
        if not was and self.scripts.OnShow then self.scripts.OnShow(self) end
    end
    region.Hide = function(self)
        local was = self.shown
        self.shown = false
        if was and self.scripts.OnHide then self.scripts.OnHide(self) end
    end
    region.SetShown = function(self, on) if on then self:Show() else self:Hide() end end
    region.IsShown = function(self) return self.shown end
    region.IsVisible = function(self) return self.shown end
    region.SetAlpha = function(self, a) self.alpha = a end
    region.GetAlpha = function(self) return self.alpha end
    region.SetWidth = function(self, w) self.width = w end
    region.SetHeight = function(self, h) self.height = h end
    region.GetWidth = function(self) return self.width end
    region.GetHeight = function(self) return self.height end
    region.SetSize = function(self, w, h) self.width, self.height = w, h end
    region.SetColorTexture = function(self, r, g, b, a) self.color = { r, g, b, a or 1 } end
    region.SetGradient = function(self, orientation, from, to) self.gradient = { orientation, from, to } end
    region.SetTexture = function(self, path) self.texture = path end
    region.SetTextColor = function(self, r, g, b, a) self.textColor = { r, g, b, a } end
    region.SetFont = function(self, _, size) self.fontSize = size end
    region.SetText = function(self, text) self.text = text end
    region.GetText = function(self) return self.text end
    region.SetWordWrap = function(self, on) self.wrap = on and true or false end
    region.GetUnboundedStringWidth = function(self) return Length(self.text) * self.fontSize / 2 end
    region.GetStringWidth = function(self)
        local width = self:GetUnboundedStringWidth()
        if self.width > 0 and width > self.width then return self.width end
        return width
    end
    region.GetStringHeight = function(self)
        local width = self:GetUnboundedStringWidth()
        if width == 0 then return 0 end
        local lines = (self.wrap and self.width > 0) and math.ceil(width / self.width) or 1
        return lines * (self.fontSize + 2)
    end
    region.SetScript = function(self, name, fn) self.scripts[name] = fn end
    region.GetScript = function(self, name) return self.scripts[name] end
    region.HookScript = function(self, name, fn)
        local old = self.scripts[name]
        self.scripts[name] = function(...)
            if old then old(...) end
            fn(...)
        end
    end

    -- As the game does: the short forms fill in the parent and the same
    -- point, and setting a point the region already has moves that one.
    region.SetPoint = function(self, point, a, b, c, d)
        local relativeTo, relativePoint, x, y
        if a == nil or type(a) == "number" then
            relativeTo, relativePoint, x, y = self.parent, point, a or 0, b or 0
        elseif type(b) == "string" then
            relativeTo, relativePoint, x, y = a, b, c or 0, d or 0
        else
            relativeTo, relativePoint, x, y = a, point, b or 0, c or 0
        end

        local anchor = { point, relativeTo, relativePoint, x, y }
        for index, existing in ipairs(self.points) do
            if existing[1] == point then
                self.points[index] = anchor
                return
            end
        end
        self.points[#self.points + 1] = anchor
    end
    region.ClearAllPoints = function(self) self.points = {} end
    region.GetNumPoints = function(self) return #self.points end
    region.GetPoint = function(self, index)
        local p = self.points[index or 1]
        if not p then return nil end
        return p[1], p[2], p[3], p[4], p[5]
    end

    region.IsMouseOver = function(self) return self.mouseOver == true end
    region.RegisterEvent = function(self, event) self.events[event] = true end
    region.UnregisterEvent = function(self, event) self.events[event] = nil end
    region.CreateTexture = function(self)
        local texture = Region(self, "Texture")
        self.textures[#self.textures + 1] = texture
        return texture
    end
    region.CreateFontString = function(self)
        local label = Region(self, "FontString")
        self.strings[#self.strings + 1] = label
        return label
    end
    region.GetParent = function(self) return self.parent end
    region.GetFrameLevel = function(self) return self.frameLevel end
    region.SetFrameLevel = function(self, value) self.frameLevel = value end
    region.GetEffectiveScale = function() return 1 end
    region.GetTop = function(self) return rawget(self, "top") end
    region.GetBottom = function(self) return rawget(self, "bottom") end
    region.GetChildren = function(self) return unpack(self.children) end

    -- Sliders: a value kept inside its range, and a change reported.
    region.GetMinMaxValues = function(self) return self.min or 0, self.max or 0 end
    region.SetMinMaxValues = function(self, lo, hi)
        self.min, self.max = lo, hi
        if self.value then self:SetValue(self.value) end
    end
    region.GetValue = function(self) return self.value or 0 end
    region.SetValue = function(self, v)
        if type(self.min) == "number" and v < self.min then v = self.min end
        if type(self.max) == "number" and v > self.max then v = self.max end
        local changed = v ~= self.value
        self.value = v
        if changed and self.scripts.OnValueChanged then self.scripts.OnValueChanged(self, v) end
    end
    region.SetThumbTexture = function(self, thumb) self.thumb = thumb end

    -- Scroll frames.
    region.GetVerticalScroll = function(self) return self.verticalScroll or 0 end
    region.SetVerticalScroll = function(self, value) self.verticalScroll = value end
    region.GetVerticalScrollRange = function(self) return self.scrollRange or 0 end

    -- Edit boxes keep the keyboard the game's way: only SetFocus and
    -- ClearFocus change it, and losing it runs OnEditFocusLost.
    region.SetFocus = function(self) self.focus = true end
    region.HasFocus = function(self) return self.focus == true end
    region.ClearFocus = function(self)
        if not self.focus then return end
        self.focus = false
        if self.scripts.OnEditFocusLost then self.scripts.OnEditFocusLost(self) end
    end

    -- Any other method does nothing. Fields read as nil, as on a real frame.
    return setmetatable(region, { __index = function(_, key)
        if type(key) == "string" and key:match("^%u") then return noop end
    end })
end

CreateFrame = function(frameType, _, parent)
    local frame = Region(parent, frameType)
    if type(parent) == "table" and rawget(parent, "children") then
        parent.children[#parent.children + 1] = frame
    end
    return frame
end
UIParent = Region()
UIParent.top = 768
CreateColor = function(r, g, b, a) return { r = r, g = g, b = b, a = a } end

GameTooltip = Region()
GameTooltip.shown = false
GameTooltip.lines = {}
GameTooltip.SetOwner = function(self, owner) self.owner, self.lines = owner, {} end
GameTooltip.IsOwned = function(self, frame) return self.owner == frame end
GameTooltip.SetText = function(self, text) self.text, self.lines = text, { text } end
GameTooltip.AddLine = function(self, text) self.lines[#self.lines + 1] = text end
GameTooltip.NumLines = function(self) return #self.lines end
GameTooltip.Show = function(self) self.shown = true end
GameTooltip.Hide = function(self) self.shown, self.owner = false, nil end

Minimap = Region()
Minimap.width = 140

local NOW = 1000000
local clock = 5000
time = function() return NOW end
GetTime = function() return clock end
C_Timer = { After = noop, NewTicker = function() return { Cancel = noop } end }
UISpecialFrames = {}
tinsert = table.insert

local passed, failed = 0, 0
local function check(label, got, want)
    if got == want then
        passed = passed + 1
        print(("  ok    %-56s %s"):format(label, tostring(got)))
    else
        failed = failed + 1
        print(("  FAIL  %-56s got %s, wanted %s"):format(label, tostring(got), tostring(want)))
    end
end

local settings = { auctionTracker = false, auctionTrackerEffects = "full" }
local ns = {}
ns.COLORS = setmetatable({}, { __index = function() return "ffffffff" end })
ns.NewModule = function(name) local m = ns[name] or {}; ns[name] = m; return m end
ns.RegisterCommand = noop
ns.RegisterEvent = function() return true end
ns.Print, ns.PrintRaw, ns.Debug, ns.Warn = noop, noop, noop, noop
ns.db = {}
ns.Config = {
    Get = function(_, key) return settings[key] end,
    Set = function(_, key, value) settings[key] = value end,
    GetCharacterKey = function() return "Player-1" end,
}
local live = {}
ns.Auctions = { ownedIDs = {}, live = live, liveAt = NOW }
local today = "2026-11-11"
date = function(fmt) if fmt == "%Y-%m-%d" then return today end return "x" end

local function Load(path)
    assert(loadfile(lfs_cwd .. path))("Blackthornes_TS", ns)
end
Load("/Core/Util.lua")
Load("/UI/Theme.lua")
Load("/UI/Widgets.lua")
Load("/UI/HouseKit.lua")
Load("/Logic/AuctionTracker.lua")
Load("/UI/AuctionTracker.lua")
ns.Util.GetItemName = function(id) return ({ [2589] = "Linen Cloth", [818] = "Tigerseye" })[id] end

local AT, UIx, Motion = ns.AuctionTracker, ns.AuctionTrackerUI, ns.Motion

-- 1. Time left.
check("two days or more in days", UIx.LeftText(NOW + 2 * 86400 + 5, false, NOW), "2d")
check("hours under two days", UIx.LeftText(NOW + 5 * 3600 + 10, false, NOW), "5h")
check("minutes under an hour", UIx.LeftText(NOW + 12 * 60, false, NOW), "12m")
check("never under a minute", UIx.LeftText(NOW + 5, false, NOW), "1m")
check("a rough end says so", UIx.LeftText(NOW + 5 * 3600 + 10, true, NOW), "~5h")

-- 2. Off, then on.
UIx:Apply()
check("off: no window", UIx.frame == nil or not UIx.frame:IsShown(), true)

live[1] = { auctionID = 1, itemID = 2589, quantity = 20, unit = 100, ends = NOW + 3600 * 3 }
live[2] = { auctionID = 2, itemID = 818, quantity = 1, unit = 5000, ends = NOW + 3600 * 10 }
AT:SetOn(true)
check("on: the window shows", UIx.frame ~= nil and UIx.frame:IsShown(), true)
UIx:Refresh(true)
check("a row per auction", UIx.upCount, 2)

local function FindText(frame, want, seen)
    seen = seen or {}
    if seen[frame] or rawget(frame, "shown") == false then return false end
    seen[frame] = true
    for _, s in ipairs(rawget(frame, "strings") or {}) do
        if s.shown and type(s.text) == "string" and s.text:find(want, 1, true) then return true end
    end
    for _, c in ipairs(rawget(frame, "children") or {}) do
        if FindText(c, want, seen) then return true end
    end
    return false
end
check("the title", FindText(UIx.frame, "My Auctions"), true)
check("Sold Today:", FindText(UIx.frame, "Sold Today:"), true)
check("the foot counts them", FindText(UIx.frame, "2 up"), true)

-- 3. A sale on Full.
local row, net = AT:Sold("Tigerseye", nil)
check("the sale found its row", row and row.itemID, 818)
check("the gold less the cut", net, 4750)
check("SOLD is stamped", FindText(UIx.frame, "SOLD"), true)
Motion:FinishAll()
for _ = 1, 30 do Motion:Step(0.2) end
UIx:Refresh(true)
check("the row left", UIx.upCount, 1)
check("Sold Today counted up to the total", UIx.shownSold, 4750)

-- 4. Subtle, then Off.
-- The Tigerseye sold, so the next read no longer has it.
live[2] = { auctionID = 3, itemID = 2589, quantity = 5, unit = 10, ends = NOW + 3600 * 20 }
AT:OnRead()
settings.auctionTrackerEffects = "subtle"
AT:Sold("Linen Cloth", 2589)
check("subtle: no stamp", FindText(UIx.frame, "SOLD"), false)
for _ = 1, 30 do Motion:Step(0.2) end
UIx:Refresh(true)
check("subtle: the cheapest left", UIx.upCount, 1)
settings.auctionTrackerEffects = "off"
AT:Sold("Linen Cloth", 2589)
UIx:Refresh(true)
check("off: gone at once", UIx.upCount, 0)
check("nothing up shows the empty line", FindText(UIx.frame, "Nothing up right now."), true)

-- 5. Runs out.
AT:OnRead()
live[1], live[2] = nil, nil
live[1] = { auctionID = 9, itemID = 2589, quantity = 1, unit = 10, ends = NOW + 30 }
AT:Changed()
UIx:Refresh(true)
check("one up", UIx.upCount, 1)
local soldBefore = AT:SoldToday()
NOW = NOW + 60
UIx:Tick()
for _ = 1, 10 do Motion:Step(0.2) end
UIx:Refresh(true)
check("ran out: gone", UIx.upCount, 0)
check("ran out: no gold", AT:SoldToday(), soldBefore)

-- 6. Transparent and place.
UIx:SetSeeThrough(3)
check("transparent saved", settings.auctionTrackerSeeThrough, 3)
check("transparent on", UIx.seeThroughOn, true)
UIx:SetSeeThrough(0)
check("transparent off", UIx.seeThroughOn and true or false, false)
settings.auctionTrackerX, settings.auctionTrackerY = 100, 200
UIx:ResetPlace()
check("Set Default clears the place", settings.auctionTrackerX, nil)

-- 7. A new post past the rows that show scrolls into sight, and a thumb
-- shows while the list is longer than the window.
for k in pairs(live) do live[k] = nil end
for i = 1, 10 do
    live[i] = { auctionID = 100 + i, itemID = 2589, quantity = 1, unit = 10, ends = NOW + 3600 * i }
end
AT:OnRead()
UIx.offset, UIx.seen = 0, nil
UIx:Refresh(true)
check("ten up", UIx.upCount, 10)
check("the thumb shows on a long list", UIx.thumb:IsShown(), true)
check("the first read keeps the top", UIx.offset, 0)
live[11] = { auctionID = 200, itemID = 818, quantity = 1, unit = 5000, ends = NOW + 3600 * 40 }
AT:OnRead()
UIx:Refresh()
check("eleven up", UIx.upCount, 11)
check("the new post scrolled into sight", UIx.offset, 11 - UIx.MOST_ROWS)
for k in pairs(live) do live[k] = nil end
live[1] = { auctionID = 300, itemID = 818, quantity = 1, unit = 5000, ends = NOW + 3600 }
AT:OnRead()
UIx:Refresh()
check("the thumb hides on a short list", UIx.thumb:IsShown(), false)

AT:SetOn(false)
check("off again: hidden", UIx.frame:IsShown(), false)

Motion:FinishAll()
for _, key in ipairs(GLOBALS) do _G[key] = saved[key] end
print("")
print(("%d passed, %d failed"):format(passed, failed))
assert(failed == 0, "auction tracker window checks failed")
