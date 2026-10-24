-- The fold gem (UI/FoldWindow.lua), outside WoW. The same test in all five
-- Blackthornes addons.
--
-- What must hold:
--   1. A dressed window gets a gem left of its close gem, with the tooltip
--      "Collapse this window", and "Expand this window" once folded.
--   2. Folding keeps the window's place and width, makes it a strip, hides
--      what is inside and keeps the rim, the fill and the halo.
--   3. The window showing a piece again while folded keeps it hidden; a piece
--      it hides itself stays hidden when the window opens.
--   4. Opening puts back the size, the anchors and every piece it hid; one
--      dragged while folded opens where it was left.
--   5. The window sizing itself while folded is the size it opens to.
--   6. Closing a folded window opens it full next time.
--   7. In a fight a window showing a guarded button does not fold.

-- Put back afterwards, nil ones too, so later suites see the world they expect.
local NAMES = { "CreateFrame", "UIParent", "GameTooltip", "hooksecurefunc", "InCombatLockdown", "C_Texture" }
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
local tip = {}
GameTooltip = setmetatable({
    SetOwner = function() end,
    SetText = function(_, text) tip.text = text end,
    Show = function() end,
    Hide = function() end,
}, {})

local ns = { L = setmetatable({}, { __index = function(_, k) return k end }) }
assert(loadfile(lfs_cwd .. "/UI/FoldWindow.lua"))("Blackthornes_Test", ns)
local FoldWindow = ns.FoldWindow

-- A window 400 wide and 300 tall, its top left at (100, 700).
local function Window()
    local frame = CreateFrame("Frame", nil, UIParent)
    frame.rect = { 100, 400, 400, 300 }
    frame.points = { { "CENTER", UIParent, "CENTER", 10, 20 } }

    local fill = frame:CreateTexture()          -- behind it all
    fill.rect = { 100, 400, 400, 300 }
    local rimTop = frame:CreateTexture()        -- along the top
    rimTop.rect = { 100, 696, 400, 3 }
    local rimBottom = frame:CreateTexture()     -- along the bottom
    rimBottom.rect = { 100, 401, 400, 3 }
    local halo = frame:CreateTexture()          -- above it
    halo.rect = { 100, 700, 400, 10 }
    local light = frame:CreateTexture()         -- the light from the top
    light.rect = { 106, 604, 388, 90 }
    local label = frame:CreateTexture()         -- words inside
    label.rect = { 140, 600, 100, 14 }

    local trim = CreateFrame("Frame", nil, frame)
    trim.corners = { {}, {}, Object(nil, "texture"), Object(nil, "texture") }
    trim.closeButton = CreateFrame("Button", nil, trim)
    trim.closeButton.rect = { 0, 0, 26, 26 }
    frame.titan = trim

    local list = CreateFrame("Frame", nil, frame)
    local grip = CreateFrame("Button", nil, frame)
    local tab = CreateFrame("Button", nil, frame)
    tab.shown = false

    return frame, { fill = fill, rimTop = rimTop, rimBottom = rimBottom, halo = halo,
        light = light, label = label, trim = trim, list = list, grip = grip, tab = tab }
end

-- 1. The gem.
local frame, parts = Window()
local toggled = {}
local button = FoldWindow:Add(frame, { onToggle = function(folded) toggled[#toggled + 1] = folded end })
assert(button and button.parent == parts.trim, "the gem rides on the trim")
local point = button.points[1]
assert(point[1] == "CENTER" and point[2] == parts.trim.closeButton and point[4] < 0, "left of the close gem")
assert(FoldWindow:Add(frame) == button, "a second Add gives back the same gem")
button.scripts.OnEnter(button)
assert(tip.text == "Collapse this window", "the open window's tooltip")

-- 2. Folding.
assert(FoldWindow:Fold(frame), "it folds")
assert(FoldWindow:IsFolded(frame))
assert(frame:GetLeft() == 100 and frame:GetTop() == 700, "the top left stays put")
assert(frame:GetWidth() == 400, "the width stays")
assert(frame:GetHeight() == FoldWindow.HEIGHT, "a strip")
assert(parts.fill.shown and parts.rimTop.shown and parts.rimBottom.shown and parts.halo.shown,
    "the fill, the rims and the halo stay")
assert(not parts.light.shown and not parts.label.shown, "the light and the words hide")
assert(parts.trim.shown, "the trim stays")
assert(not parts.list.shown and not parts.grip.shown, "the window's insides and the grip hide")
assert(not parts.trim.corners[3].shown, "the bottom corners hide on the strip")
assert(toggled[1] == true, "the window hears it fold")
assert(tip.text == "Expand this window", "the tooltip follows")
assert(button.glyph.down.shown, "a plus while folded")

-- 3. Kept hidden; hidden by the window itself.
parts.list:Show()
assert(not parts.list.shown, "the window showing a piece keeps it hidden")
parts.label:SetShown(true)
assert(not parts.label.shown, "a region shown again stays hidden too")
parts.grip:Hide()
parts.tab:Show()
assert(not parts.tab.shown, "a piece first shown while folded hides")

-- 5. Sized while folded.
frame:SetHeight(360)
assert(frame:GetHeight() == FoldWindow.HEIGHT, "still a strip")
frame:SetWidth(420)

-- 4. Opening.
assert(FoldWindow:Unfold(frame))
assert(not FoldWindow:IsFolded(frame))
assert(frame:GetHeight() == 360 and frame:GetWidth() == 420, "it opens to the size the window asked for")
assert(frame.points[1][1] == "CENTER" and frame.points[1][4] == 10, "its anchors come back")
assert(parts.list.shown and parts.label.shown and parts.light.shown and parts.tab.shown, "everything comes back")
assert(not parts.grip.shown, "a piece the window hid itself stays hidden")
assert(parts.trim.corners[3].shown, "the corners come back")
assert(toggled[2] == false)
assert(not button.glyph.down.shown, "a bar while open")

-- 4b. Dragged while folded.
local frame2 = Window()
FoldWindow:Add(frame2)
FoldWindow:Fold(frame2)
frame2:ClearAllPoints()
frame2:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", 250, 500)
FoldWindow:Unfold(frame2)
assert(frame2:GetLeft() == 250 and frame2:GetTop() == 500, "it opens where it was dragged")
assert(frame2:GetHeight() == 300)

-- 6. Closed while folded.
local frame3 = Window()
FoldWindow:Add(frame3)
FoldWindow:Fold(frame3)
frame3:Hide()
assert(not FoldWindow:IsFolded(frame3), "closing opens it")
frame3:Show()
assert(frame3:GetHeight() == 300, "and it shows full")

-- 7. A guarded button in a fight.
local frame4, parts4 = Window()
parts4.list.protected = true
FoldWindow:Add(frame4)
fighting = true
assert(not FoldWindow:Fold(frame4), "no fold over a guarded button in a fight")
fighting = false
assert(FoldWindow:Fold(frame4), "it folds once the fight is over")
fighting = true
FoldWindow:Unfold(frame4)
assert(not parts4.list.shown, "a guarded button waits for the fight to end")
fighting = false
assert(FoldWindow.waiting[parts4.list] == frame4)

-- A Keeps check on its own: no rect, kept.
assert(FoldWindow.Keeps(nil, { 0, 0, 10, 10 }))

for _, name in ipairs(NAMES) do _G[name] = saved[name] end
print("test_foldwindow: ok")
