-- The swap gem on the one window and each addon's own windows
-- (UI/SharedWindow.lua, the owner said build it, 2026-11-19). The same test
-- in all five Blackthornes addons.
--
-- What must hold:
--   1. A dressed own window gets the gem once, on its trim, left of its fold
--      gem, as a join gem; an undressed one gets none.
--   2. The one window gets it as a split gem, left of its fold gem.
--   3. The cards say what a click does, in the approved words.
--   4. Split: the one window closes, the choice is off in every save, and
--      the addon showing opens on its own on the same tab.
--   5. Join: every own window closes, the choice is on in every save, and
--      the one window opens on that addon, on the same tab.
--   6. An addon without the swap calls still splits (its open) and joins
--      (the one window opens on it).
--   7. In a fight nothing moves; the swap happens as the fight ends.

local NAMES = { "CreateFrame", "UIParent", "C_Timer", "time", "BlackthornesWindow",
    "UISpecialFrames", "GetTime", "GameTooltip", "InCombatLockdown", "BlackthornesShelves" }
local saved = {}
for _, name in ipairs(NAMES) do saved[name] = _G[name] end

local function Object()
    local o = { shown = true, scripts = {}, scale = 1, left = 100, top = 600 }
    function o:Show() self.shown = true end
    function o:Hide()
        local was = self.shown
        self.shown = false
        if was and self.scripts.OnHide then self.scripts.OnHide(self) end
    end
    function o:IsShown() return self.shown end
    function o:SetScript(name, fn) self.scripts[name] = fn end
    function o:SetScale(scale) self.scale = scale end
    function o:GetScale() return self.scale end
    function o:GetLeft() return self.left end
    function o:GetTop() return self.top end
    function o:GetEffectiveScale() return 1 end
    function o:CreateTexture() return Object() end
    function o:CreateFontString() return Object() end
    function o:SetSize(w, h) self.width, self.height = w, h end
    function o:SetWidth(w) self.width = w end
    function o:SetHeight(h) self.height = h end
    function o:GetWidth() return self.width or 0 end
    function o:GetHeight() return self.height or 0 end
    function o:ClearAllPoints() self.point = nil end
    function o:SetPoint(...) self.point = { ... } end
    return setmetatable(o, { __index = function() return function() end end })
end

CreateFrame = function(_, _, parent)
    local f = Object()
    f.parent = parent
    return f
end
UIParent = Object()
C_Timer = nil
UISpecialFrames = {}
time = function() return 1000 end
GetTime = function() return 50 end
BlackthornesWindow = nil
BlackthornesShelves = nil
local fighting = false
InCombatLockdown = function() return fighting end

local tip = {}
GameTooltip = {
    SetOwner = function() tip.lines = {} end,
    SetText = function(_, text) tip.title = text end,
    AddLine = function(_, text, r, g, b) tip.lines[#tip.lines + 1] = { text = text, g = g, r = r } end,
    Show = function() tip.shown = true end,
    Hide = function() tip.shown = false end,
}

-- A house frame: the trim with its close gem, and the fold gem left of it.
local function Dress(frame)
    local trim = Object()
    trim.closeButton = Object()
    trim.closeButton:SetSize(26, 26)
    frame.titan = trim
    return trim
end
local ns = {
    Theme = {
        Unpack = function() return 0, 0, 0, 1 end,
        Fill = function() end,
        Border = function() end,
        CreateLabel = function() return Object() end,
    },
    Titanforged = { Dress = function(_, frame) return Dress(frame) end },
    FoldWindow = {
        Add = function(_, frame)
            local button = Object()
            button:SetSize(22, 22)
            frame.blackthornesFold = { button = button }
            return button
        end,
    },
}
local chunk = assert(loadfile(lfs_cwd .. "/UI/SharedWindow.lua"))
chunk("Blackthornes_Test", ns)
local SW = ns.SharedWindow
assert(SW and SW.AddSwap and SW.Swap, "SharedWindow loads with the swap gem")
assert(SW.FILE_VERSION >= 14, "a newer copy than the one before the gem")

-- Two addons, each with an own window that can show a tab.
local log = {}
local function Addon(key, order, withSwap)
    local addon = { key = key, db = {}, own = Object(), tab = nil, hosted = false }
    addon.own.shown = false
    local entry = {
        key = key, order = order, name = key, icon = "icon-" .. key,
        db = function() return addon.db end,
        open = function() log[#log + 1] = "open " .. key; addon.own:Show() end,
    }
    entry.host = {
        enter = function() addon.hosted = true; log[#log + 1] = "enter " .. key end,
        leave = function() addon.hosted = false; log[#log + 1] = "leave " .. key end,
    }
    if withSwap then
        entry.host.tab = function() return addon.tab end
        entry.host.show = function(tab)
            log[#log + 1] = "show " .. key .. " " .. tostring(tab)
            addon.tab = tab
            if SW.Hosts(key) then SW.Open(key) else addon.own:Show() end
        end
        entry.host.hide = function() log[#log + 1] = "hide " .. key; addon.own:Hide() end
    end
    addon.entry = entry
    SW:Join(entry)
    return addon
end
local alpha = Addon("alpha", 1, true)
local beta = Addon("beta", 2, true)

-- 1. An own window's gem.
local own = Object()
local trim = Dress(own)
ns.FoldWindow:Add(own)
local gem = SW.AddSwap(own, "alpha")
assert(gem, "a dressed own window gets the gem")
assert(gem.parent == trim, "on its trim, so it hides with the trim inside the one window")
assert(gem.join == true and gem.swapKey == "alpha", "on an own window it joins")
assert(gem.point[1] == "CENTER" and gem.point[2] == own.blackthornesFold.button
    and gem.point[4] == -(11 + 11 + SW.SWAP_GAP), "left of the fold gem")
assert(gem.width == SW.SWAP_GEM, "the fold gem's size")
assert(SW.AddSwap(own, "alpha") == gem, "only once")
assert(SW.AddSwap(Object(), "alpha") == nil, "an undressed window gets none")
local bare = Object()
Dress(bare)
local noFold = SW.AddSwap(bare, "beta")
assert(noFold.point[2] == bare.titan.closeButton and noFold.point[4] == -(13 + 11 + SW.SWAP_GAP),
    "with no fold gem, left of the close gem")

-- 2. The one window's gem.
SW.SetOn(true)
assert(SW.Open("alpha"), "the one window opens")
local frame = BlackthornesWindow.frame
local oneGem = frame.blackthornesSwap
assert(oneGem and oneGem.join == false and rawget(oneGem, "swapKey") == nil, "the one window splits")
assert(oneGem.point[2] == frame.blackthornesFold.button, "left of its fold gem")

-- 3. The cards.
oneGem.scripts.OnEnter(oneGem)
assert(tip.title == "Split Into Own Windows", "split card title")
assert(tip.lines[1].text == "Gives each addon its own window again.", "split card line")
assert(tip.lines[2].text == "You can join them back with this same button." and tip.lines[2].g > tip.lines[2].r,
    "split card hint, in green")
oneGem.scripts.OnLeave(oneGem)
assert(tip.shown == false, "the card goes with the mouse")
gem.scripts.OnEnter(gem)
assert(tip.title == "Join Into One Window", "join card title")
assert(tip.lines[1].text == "Puts every Blackthornes addon in one window, with a button for each down the side.",
    "join card line")
assert(tip.lines[2].text == "You can split them again with this same button.", "join card hint")
gem.scripts.OnLeave(gem)

-- 4. Split, from the one window on alpha's Settings tab.
alpha.tab = "settings"
log = {}
oneGem.scripts.OnClick(oneGem)
assert(not SW.IsOpen(), "the one window closes")
assert(not SW.On(), "the choice is off")
assert(alpha.db.oneWindow == false and beta.db.oneWindow == false, "in every save, so the All Addons box unticks")
assert(log[1] == "leave alpha", "alpha's pages go back first")
assert(log[2] == "show alpha settings", "alpha opens on the same tab")
assert(alpha.own:IsShown() and not beta.own:IsShown(), "only the addon showing opens on its own")

-- 5. Join, from beta's own window on its second tab, with alpha's open too.
beta.own:Show()
beta.tab = "all"
log = {}
gem.swapKey = "beta"
gem.scripts.OnClick(gem)
assert(SW.On(), "the choice is on")
assert(alpha.db.oneWindow == true and beta.db.oneWindow == true, "in every save, so the All Addons box ticks")
assert(not alpha.own:IsShown(), "every other own window closes")
assert(SW.IsOpen(), "the one window opens")
local saw = table.concat(log, ",")
assert(saw:find("hide alpha", 1, true) and saw:find("hide beta", 1, true), "each addon is asked to close")
assert(saw:find("show beta all", 1, true), "on the same tab")
assert(log[#log] == "enter beta", "beta is the one picked")

-- 6. An addon with none of the swap calls.
local gamma = Addon("gamma", 3, false)
assert(SW.Pick("gamma"), "gamma shows in the one window")
log = {}
SW.Swap(nil, false)
assert(not SW.On(), "off")
assert(log[1] == "leave gamma" and log[2] == "open gamma", "it opens its own window the usual way")
log = {}
SW.Swap("gamma", true)
assert(SW.On() and SW.IsOpen(), "on, and the one window opens")
assert(log[#log] == "enter gamma", "on gamma")

-- 7. In a fight.
fighting = true
assert(SW.Swap(nil, false) == false, "nothing moves in a fight")
assert(SW.On() and SW.IsOpen(), "still on and open")
fighting = false
SW.events.scripts.OnEvent(SW.events, "PLAYER_REGEN_ENABLED")
assert(not SW.On() and not SW.IsOpen(), "the swap happens as the fight ends")
SW.events.scripts.OnEvent(SW.events, "PLAYER_REGEN_ENABLED")
assert(not SW.On(), "and only once")

for _, name in ipairs(NAMES) do _G[name] = saved[name] end
print("test_swapgem: ok")
