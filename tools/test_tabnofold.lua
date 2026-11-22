-- The sell list and the craft pane as tabs in the one window never fold
-- into their round button (UI/Collapse.lua's canFold, UI/FoldWindow.lua).
--
-- A player's report (2026-11-22, after 1.39.0): with the sell list folded
-- from before, the one window's Auction House tab came up empty. The tab
-- showed the drawer, the drawer heard it show, and Collapse folded it into
-- its round button inside the tab, so nothing could be posted.
--
-- What must hold:
--   1. Folded from before, the panel shown as a tab stays open.
--   2. Beside its game window, the same fold still makes it a round button.

-- Put back afterwards, nil ones too, so later suites see the world they expect.
local NAMES = { "CreateFrame", "UIParent", "GameTooltip", "hooksecurefunc", "InCombatLockdown", "C_Texture",
    "UISpecialFrames", "C_Timer", "BlackthornesFoldHub" }
local saved = {}
for _, name in ipairs(NAMES) do saved[name] = _G[name] end

local function Hook(object, name, fn)
    local old = object[name]
    object[name] = function(...)
        local a, b, c, d = old(...)
        fn(...)
        return a, b, c, d
    end
end
hooksecurefunc = Hook

local fighting = false
InCombatLockdown = function() return fighting end
C_Texture = nil
C_Timer = nil
BlackthornesFoldHub = nil
UISpecialFrames = {}

local function Object(parent, kind)
    local o = { shown = true, parent = parent, scripts = {}, points = {}, kind = kind,
        children = {}, regions = {}, rect = { 0, 0, 0, 0 } }

    function o:Show()
        local was = self.shown
        self.shown = true
        if not was and self.scripts.OnShow then self.scripts.OnShow(self) end
    end
    function o:Hide()
        local was = self.shown
        self.shown = false
        if was and self.scripts.OnHide then self.scripts.OnHide(self) end
    end
    function o:SetShown(on) if on then self:Show() else self:Hide() end end
    function o:IsShown() return self.shown end
    function o:SetScript(name, fn) self.scripts[name] = fn end
    function o:HookScript(name, fn)
        local old = self.scripts[name]
        self.scripts[name] = function(...)
            if old then old(...) end
            fn(...)
        end
    end
    function o:GetParent() return self.parent end
    function o:SetSize(w, h) self.rect[3], self.rect[4] = w, h end
    function o:SetWidth(w) self.rect[3] = w end
    function o:SetHeight(h)
        -- Anchored by its top left, a frame grows downwards.
        local top = self.rect[2] + self.rect[4]
        self.rect[4] = h
        self.rect[2] = top - h
    end
    function o:GetWidth() return self.rect[3] end
    function o:GetHeight() return self.rect[4] end
    function o:GetLeft() return self.rect[1] end
    function o:GetRight() return self.rect[1] + self.rect[3] end
    function o:GetTop() return self.rect[2] + self.rect[4] end
    function o:GetRect() return self.rect[1], self.rect[2], self.rect[3], self.rect[4] end
    function o:SetPoint(point, rel, relPoint, x, y)
        self.points[#self.points + 1] = { point, rel, relPoint, x, y }
        if point == "TOPLEFT" and rel == UIParent and type(x) == "number" then
            self.rect[1] = x
            self.rect[2] = y - self.rect[4]
        end
    end
    function o:ClearAllPoints() self.points = {} end
    function o:GetNumPoints() return #self.points end
    function o:GetPoint(i) return unpack(self.points[i]) end
    function o:GetChildren() return unpack(self.children) end
    function o:GetRegions() return unpack(self.regions) end
    function o:IsProtected() return self.protected == true end
    function o:GetName() return self.name end
    function o:EnableMouse(on) self.mouse = on and true or false end
    function o:IsMouseEnabled() return self.mouse ~= false end
    function o:EnableMouseWheel(on) self.wheel = on and true or false end
    function o:IsMouseWheelEnabled() return self.wheel == true end
    function o:GetScript(name) return self.scripts[name] end
    function o:StopMovingOrSizing() self.stopped = (self.stopped or 0) + 1 end
    function o:CreateFontString()
        local t = Object(self, "font")
        function t:SetText(text) self.text = text end
        function t:GetText() return self.text end
        function t:GetStringWidth() return #(self.text or "") * 6 end
        self.regions[#self.regions + 1] = t
        return t
    end
    function o:CreateTexture()
        local t = Object(self, "texture")
        t.GetChildren, t.GetRegions = nil, nil
        self.regions[#self.regions + 1] = t
        return t
    end
    return setmetatable(o, { __index = function(_, key)
        if type(key) == "string" and key:match("^%u") then return function() end end
    end })
end

CreateFrame = function(_, _, parent)
    local frame = Object(parent, "frame")
    if parent then parent.children[#parent.children + 1] = frame end
    return frame
end
UIParent = Object(nil, "frame")
local tip = { lines = {} }
GameTooltip = setmetatable({
    SetOwner = function() end,
    SetText = function(_, text) tip.text = text; tip.lines = { text } end,
    AddLine = function(_, text) tip.lines[#tip.lines + 1] = text end,
    Show = function() end,
    Hide = function() end,
}, {})

local ns = { L = setmetatable({}, { __index = function(_, k) return k end }) }
assert(loadfile(lfs_cwd .. "/UI/FoldWindow.lua"))("Blackthornes_TS", ns)
local FoldWindow = ns.FoldWindow

local settings = { postPanelCollapsed = true }
ns.Config = {
    Get = function(_, key) return settings[key] end,
    Set = function(_, key, value) settings[key] = value end,
}
ns.Theme = setmetatable({}, { __index = function() return function() end end })
ns.Widgets = { CreateButton = function() return CreateFrame("Button") end }
assert(loadfile(lfs_cwd .. "/UI/Collapse.lua"))("Blackthornes_TS", ns)
local Collapse = ns.Collapse

-- The sell list: a dressed panel 400 wide, 300 tall.
local frame = CreateFrame("Frame", nil, UIParent)
frame.name = "Sell"
frame.rect = { 100, 400, 400, 300 }
local trim = CreateFrame("Frame", nil, frame)
trim.corners = { {}, {}, Object(nil, "texture"), Object(nil, "texture") }
trim.closeButton = CreateFrame("Button", nil, trim)
trim.closeButton.rect = { 0, 0, 26, 26 }
frame.titan = trim
local header = CreateFrame("Frame", nil, frame)
local title = header:CreateFontString()
local body = CreateFrame("Frame", nil, frame)
frame.shown = false

local inOne = false
Collapse.Attach(frame, {
    key = "postPanelCollapsed", header = header, title = title, body = body,
    canFold = function() return not inOne end,
})

-- 1. Laid into the Auction House tab and shown there.
inOne = true
frame:Show()
assert(not FoldWindow:IsFolded(frame), "as a tab, the sell list does not fold")
assert(frame.shown and body.shown and header.shown, "and its rows and Scan strip show")
assert(settings.postPanelCollapsed == true, "the player's fold is kept for later")

-- 2. Back beside the auction house on its own.
inOne = false
frame:Hide()
frame:Show()
assert(FoldWindow:IsFolded(frame), "beside the auction house, the fold holds")
-- Into the tab again: opened there, the fold still kept.
FoldWindow:Unfold(frame, true)
inOne = true
assert(not FoldWindow:IsFolded(frame) and body.shown, "opened in the tab")
assert(settings.postPanelCollapsed == true, "and folded again outside it")
assert(not FoldWindow:Fold(frame), "the fold gem can't fold the tab")

for _, name in ipairs(NAMES) do _G[name] = saved[name] end
print("test_tabnofold: ok")
