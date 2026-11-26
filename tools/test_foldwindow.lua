-- The fold gem and the round button (UI/FoldWindow.lua), outside WoW. The
-- same test in all five Blackthornes addons.
--
-- What must hold:
--   1. A dressed window gets a gem left of its close gem, with the tooltip
--      "Collapse this window".
--   2. Folding hides everything on the window, the frame too, takes no
--      clicks and leaves Escape alone; a round button shows on its top
--      right corner, where the fold gem is, and the fold is saved with the
--      button's spot.
--   3. The window showing a piece again while folded keeps it hidden; a piece
--      it hides itself stays hidden when the window opens.
--   4. A click on the button opens the window, same size and place; the
--      button goes and the save is cleared.
--   5. The button dragged, the window opens where the button is, and hears
--      it was dropped there.
--   6. Closing a folded window opens it full next time.
--   7. In a fight a window showing a guarded button does not fold.
--   8. After a /reload: a window up at login folds again, its button where
--      it was left; one not up comes back as a button its opener opens.
--   9. A newer button steps down off an older one.
--  10. The button's tooltip and its number.
--  11. A page that closes the window as it hides (inside the one window)
--      does not close it while it folds; a window closed that way anyway
--      opens full.

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
    -- As the game has it: EnableMouse sets clicks and passing over at once,
    -- and the part that hears the mouse is the frame less its insets.
    function o:EnableMouse(on)
        self.mouse = on and true or false
        self.click, self.motion = self.mouse, self.mouse
    end
    function o:IsMouseEnabled() return self.mouse ~= false end
    function o:SetMouseClickEnabled(on) self.click = on and true or false end
    function o:IsMouseClickEnabled() return self.click ~= false end
    function o:SetMouseMotionEnabled(on) self.motion = on and true or false end
    function o:IsMouseMotionEnabled() return self.motion ~= false end
    function o:SetHitRectInsets(l, r, t, b) self.insets = { l, r, t, b } end
    function o:GetHitRectInsets()
        local i = self.insets or { 0, 0, 0, 0 }
        return i[1], i[2], i[3], i[4]
    end
    -- Does the game's ping land on it ("Can't ping this.")? As players saw
    -- it (2026-11-25), the ping stopped over a shown window with the mouse
    -- turned off: only a window hidden or with no part left that hears the
    -- mouse lets it through.
    function o:Catches()
        if not self.shown then return false end
        local l, r, t, b = self:GetHitRectInsets()
        return self.rect[3] - l - r > 0 and self.rect[4] - t - b > 0
    end
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
assert(loadfile(lfs_cwd .. "/UI/FoldWindow.lua"))("Blackthornes_Test", ns)
local FoldWindow = ns.FoldWindow

-- A window 400 wide and 300 tall, its top left at (100, 700).
local function Window(name)
    local frame = CreateFrame("Frame", nil, UIParent)
    frame.name = name
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


local SIZE, OUT = FoldWindow.SIZE, FoldWindow.OUT

-- A button's top left, from its last point.
local function Spot(round)
    local point = round.button.points[#round.button.points]
    return point[4], point[5]
end

-- 1. The gem.
local frame, parts = Window("TestWindow")
UISpecialFrames[1] = "TestWindow"
frame.wheel = true
local toggled = {}
local button = FoldWindow:Add(frame, { key = "Test", onToggle = function(folded) toggled[#toggled + 1] = folded end })
assert(button and button.parent == parts.trim, "the gem rides on the trim")
local point = button.points[1]
assert(point[1] == "CENTER" and point[2] == parts.trim.closeButton and point[4] < 0, "left of the close gem")
assert(FoldWindow:Add(frame) == button, "a second Add gives back the same gem")
button.scripts.OnEnter(button)
assert(tip.text == "Collapse this window", "the open window's tooltip")
local key = frame.blackthornesFold.key
assert(key == "Blackthornes_Test:Test", "the key carries the addon's name")

-- 2. Folding.
assert(FoldWindow:Fold(frame), "it folds")
assert(FoldWindow:IsFolded(frame))
assert(frame.shown, "the window itself stays up")
assert(frame:GetHeight() == 300 and frame:GetWidth() == 400, "its size stays")
for name, part in pairs(parts) do
    if name ~= "tab" then assert(not part.shown, "everything on it hides: " .. name) end
end
assert(frame.mouse == false and frame.wheel == false, "it takes no clicks or wheel")
assert(frame.click == false and frame.motion == false, "nor the mouse passing over")
assert(not frame:Catches(), "no part of the empty window catches the mouse (the game's ping)")
assert(#UISpecialFrames == 0, "Escape leaves it alone")
local round = FoldWindow.rounds[key]
assert(round and round.button.shown, "the round button shows")
assert(round.button.parent == UIParent, "on the screen, not on the window")
local x, y = Spot(round)
assert(x == 500 + OUT - SIZE and y == 700 + OUT, "on the window's top right corner")
assert(FoldWindow.SavedFolded(key), "the fold is saved")
local spots = FoldWindow.memory.windowSpots
assert(spots and spots["fold:" .. key].x == x and spots["fold:" .. key].y == y, "with the button's spot")
assert(toggled[1] == true, "the window hears it fold")

-- 3. Kept hidden; hidden by the window itself.
parts.list:Show()
assert(not parts.list.shown, "the window showing a piece keeps it hidden")
parts.label:SetShown(true)
assert(not parts.label.shown, "a region shown again stays hidden too")
parts.grip:Hide()
parts.tab:Show()
assert(not parts.tab.shown, "a piece first shown while folded hides")
frame:SetHeight(360)

-- 4. A click on the button opens it.
round.button.scripts.OnClick(round.button)
assert(not FoldWindow:IsFolded(frame))
assert(frame.click ~= false and frame.motion ~= false and frame:Catches(), "open, it hears the mouse again")
assert(frame:GetHeight() == 360 and frame:GetWidth() == 400, "the size the window asked for")
assert(frame.points[1][1] == "CENTER" and frame.points[1][4] == 10, "left where it was")
assert(parts.list.shown and parts.label.shown and parts.light.shown and parts.tab.shown
    and parts.trim.shown and parts.fill.shown, "everything comes back")
assert(not parts.grip.shown, "a piece the window hid itself stays hidden")
assert(frame.mouse == true and frame.wheel == true, "clicks and the wheel come back")
assert(UISpecialFrames[1] == "TestWindow", "Escape closes it again")
assert(not round.button.shown, "the button goes")
assert(not FoldWindow.SavedFolded(key), "the save is cleared")
assert(toggled[2] == false)

-- 5. The button dragged.
local frame2 = Window()
local dropped = 0
frame2.scripts.OnDragStop = function() dropped = dropped + 1 end
FoldWindow:Add(frame2, { key = "Two" })
FoldWindow:Fold(frame2)
local round2 = FoldWindow.rounds["Blackthornes_Test:Two"]
round2.button.scripts.OnDragStart(round2.button)
round2.button.rect = { 300, 454, SIZE, SIZE }      -- its top left at (300, 500)
round2.button.scripts.OnDragStop(round2.button)
round2.button.scripts.OnClick(round2.button)
assert(FoldWindow:IsFolded(frame2), "letting go after a drag is not a click")
round2.button.scripts.OnClick(round2.button)
assert(not FoldWindow:IsFolded(frame2), "the next click opens it")
assert(frame2:GetLeft() + frame2:GetWidth() == 300 + SIZE - OUT and frame2:GetTop() == 500 - OUT,
    "it opens with its top right corner on the button")
assert(frame2:GetHeight() == 300)
assert(dropped == 1, "and hears it was dropped there")

-- 6. Closed while folded.
local frame3 = Window()
FoldWindow:Add(frame3, { key = "Three" })
FoldWindow:Fold(frame3)
frame3:Hide()
assert(not FoldWindow:IsFolded(frame3), "closing opens it")
assert(not FoldWindow.rounds["Blackthornes_Test:Three"].button.shown, "and the button goes")
assert(not FoldWindow.SavedFolded("Blackthornes_Test:Three"))
frame3:Show()
assert(frame3.titan.shown and frame3:GetHeight() == 300, "it shows full")

-- 7. A guarded button in a fight.
local frame4, parts4 = Window()
parts4.list.protected = true
FoldWindow:Add(frame4, { key = "Four" })
fighting = true
assert(not FoldWindow:Fold(frame4), "no fold over a guarded button in a fight")
fighting = false
assert(FoldWindow:Fold(frame4), "it folds once the fight is over")
fighting = true
FoldWindow:Unfold(frame4)
assert(not parts4.list.shown, "a guarded button waits for the fight to end")
fighting = false
assert(FoldWindow.waiting[parts4.list] == frame4)

-- 8. After a /reload.
FoldWindow.memory.foldedWindows = { ["Blackthornes_Test:Five"] = true, ["Blackthornes_Test:Six"] = true,
    ["Blackthornes_Test:Gone"] = true, ["Other_Addon:Main"] = true }
FoldWindow.memory.windowSpots = { ["fold:Blackthornes_Test:Five"] = { x = 50, y = 600 },
    ["fold:Blackthornes_Test:Six"] = { x = 900, y = 300 } }
-- Five is up at login.
local frame5 = Window()
FoldWindow:Add(frame5, { key = "Five" })
assert(FoldWindow:IsFolded(frame5), "up at login, it folds again")
local x5, y5 = Spot(FoldWindow.rounds["Blackthornes_Test:Five"])
assert(x5 == 50 and y5 == 600, "its button where it was left")
-- Six is not up: its opener builds it.
local frame6
FoldWindow:Opener("Six", { open = function()
    frame6 = frame6 or Window()
    FoldWindow:Add(frame6, { key = "Six" })
    frame6:Show()
end })
FoldWindow.Restore()
local round6 = FoldWindow.rounds["Blackthornes_Test:Six"]
assert(round6 and round6.button.shown, "not up, it comes back as a button")
local x6, y6 = Spot(round6)
assert(x6 == 900 and y6 == 300, "where it was left")
assert(not FoldWindow.SavedFolded("Blackthornes_Test:Gone"), "nothing can open this one: it opens full next time")
assert(FoldWindow.SavedFolded("Other_Addon:Main"), "another addon's window is left alone")
round6.button.scripts.OnClick(round6.button)
assert(frame6 and frame6.shown and not FoldWindow:IsFolded(frame6), "a click opens it full")
assert(frame6:GetLeft() + frame6:GetWidth() == 900 + SIZE - OUT and frame6:GetTop() == 300 - OUT, "where the button was")
assert(not round6.button.shown and not FoldWindow.SavedFolded("Blackthornes_Test:Six"))
-- Shown again later this session, a window opens full.
FoldWindow.memory.foldedWindows = { ["Blackthornes_Test:Seven"] = true }
FoldWindow.restored["Blackthornes_Test:Seven"] = true
local frame7 = Window()
FoldWindow:Add(frame7, { key = "Seven" })
assert(not FoldWindow:IsFolded(frame7), "only the first show after logging in folds")

-- 9. A newer button steps down off an older one.
local frame8 = Window()
FoldWindow:Add(frame8, { key = "Eight" })
local frame9 = Window()
FoldWindow:Add(frame9, { key = "Nine" })
FoldWindow:Fold(frame8)
local r8 = FoldWindow.rounds["Blackthornes_Test:Eight"]
r8.button.rect = { 500 + OUT - SIZE, 700 + OUT - SIZE, SIZE, SIZE }
FoldWindow:Fold(frame9)
local _, y9 = Spot(FoldWindow.rounds["Blackthornes_Test:Nine"])
assert(y9 == 700 + OUT - SIZE - FoldWindow.STEP, "the newer one steps down")
local ux, uy = FoldWindow.Unstack(10, 10, { { 10, 10 }, { 10, 10 - SIZE - FoldWindow.STEP } })
assert(ux == 10 and uy == 10 - 2 * (SIZE + FoldWindow.STEP), "past every button in its way")

-- 10. Tooltip and number.
local frame10, parts10 = Window()
parts10.trim.plate = { label = { GetText = function() return "Test Window" end } }
local count = 0
FoldWindow:Add(frame10, { key = "Ten", pill = function() return count > 0 and tostring(count) or nil end,
    line = function() return "This session: " .. count .. " kills." end })
FoldWindow:Fold(frame10)
local r10 = FoldWindow.rounds["Blackthornes_Test:Ten"]
assert(not r10.pill.shown, "no number when there is none")
count = 42
FoldWindow:Refresh(frame10)
assert(r10.pill.shown and r10.pill.label.text == "42", "the number under it")
r10.button.scripts.OnEnter(r10.button)
assert(tip.lines[1] == "Test Window", "the window's name first")
assert(tip.lines[2] == "This session: 42 kills.", "then its own line")
assert(tip.lines[3] == "Click to open it again." and tip.lines[4] == "Drag to move it.")

-- A panel joins with no gem of its own.
local panel = Window("TestPanel")
panel.titan = nil
local state = FoldWindow:Join(panel, {})
assert(state.key == "Blackthornes_Test:TestPanel", "a named panel is keyed by its name")
assert(FoldWindow:Fold(panel) and FoldWindow:IsFolded(panel))
assert(FoldWindow.rounds[state.key].button.shown)

-- 11. A page that closes the window when it hides, as the addons' pages
-- inside the one window do (it vanished for good, 2026-11-22).
local closeFolding = true
local frame11, parts11 = Window("TestOne")
parts11.list.scripts.OnHide = function()
    local state11 = frame11.blackthornesFold
    if closeFolding and state11.folding then return end   -- SharedWindow.Close's guard
    frame11:Hide()
end
FoldWindow:Add(frame11, { key = "Eleven" })
assert(FoldWindow:Fold(frame11), "it folds")
assert(frame11.shown, "the window is not closed by its page hiding")
local r11 = FoldWindow.rounds["Blackthornes_Test:Eleven"]
r11.button.scripts.OnClick(r11.button)
assert(frame11.shown and parts11.list.shown and parts11.trim.shown, "and its button opens it again")
-- Without the guard the window does close: then it is a close, opening full.
closeFolding = false
assert(not FoldWindow:Fold(frame11), "closed as it folded, it does not fold")
assert(not FoldWindow:IsFolded(frame11) and not r11.button.shown, "no button is left behind")
assert(not FoldWindow.SavedFolded("Blackthornes_Test:Eleven"))
frame11:Show()
assert(parts11.trim.shown and parts11.fill.shown, "shown again, it is full")

-- 12. Fold Gem: Small Bar (the All Addons page's pick).
local foldStyle = "bar"
ns.SharedChoices = { Look = function(_, kind) if kind == "fold" then return foldStyle end end }
assert(FoldWindow.Style() == "bar")
local frame12, parts12 = Window()
parts12.trim.plate = { label = { GetText = function() return "Test Window" end } }
FoldWindow:Add(frame12, { key = "Twelve", pill = function() return "3 kills" end })
for _, other in pairs(FoldWindow.rounds) do other.button.shown = false end   -- none in its way
assert(FoldWindow:Fold(frame12), "it folds")
local r12 = FoldWindow.rounds["Blackthornes_Test:Twelve"]
assert(r12.bar and r12.button.shown, "into a small bar")
local width12 = r12.width
assert(width12 >= 110 and width12 <= 280, "sized to its words")
local x12, y12 = Spot(r12)
assert(x12 == 500 - width12 and y12 == 700, "along the window's top right corner")
r12.button.scripts.OnEnter(r12.button)
assert(tip.lines[1] == "Test Window", "the same tooltip")
r12.button.scripts.OnDragStart(r12.button)
r12.button.rect = { 200, 600 - FoldWindow.BAR_HEIGHT, width12, FoldWindow.BAR_HEIGHT }
r12.button.scripts.OnDragStop(r12.button)
r12.button.scripts.OnClick(r12.button)
assert(FoldWindow:IsFolded(frame12), "letting go after a drag is not a click")
r12.button.scripts.OnClick(r12.button)
assert(not FoldWindow:IsFolded(frame12), "a click opens it")
assert(frame12:GetLeft() + frame12:GetWidth() == 200 + width12 and frame12:GetTop() == 600,
    "with its top right corner on the bar's")
foldStyle = "round"
FoldWindow:Fold(frame12)
local back12 = FoldWindow.rounds["Blackthornes_Test:Twelve"]
assert(back12 ~= r12 and not back12.bar and back12.button.shown, "the pick counts from the next fold")
assert(not r12.button.shown, "the old bar stays put away")
FoldWindow:Unfold(frame12)
ns.SharedChoices = nil
assert(FoldWindow.Style() == "round", "the round button when nothing is picked")

for _, name in ipairs(NAMES) do _G[name] = saved[name] end
print("test_foldwindow: ok")
