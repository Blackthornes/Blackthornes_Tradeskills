-- Goblin Gold's Transparent setting (asked 2026-10-19, as Farmer's panels).
--
-- What must hold:
--   1. Off by default: the glass stays as it is and no words get a shadow.
--   2. Some, More and Most thin the glass to 0.5, 0.3 and 0.15, and the
--      gold, the gems and the coin are left alone.
--   3. The glass comes back while the mouse is on the bar, and goes again
--      when it leaves.
--   4. Off puts the glass and the words' shadows back as they were.
--   5. The level is saved, and a level it lacks is refused.

local GLOBALS = { "CreateFrame", "UIParent", "GameTooltip", "time", "date", "UISpecialFrames", "tinsert" }
local saved = {}
for _, key in ipairs(GLOBALS) do saved[key] = _G[key] end

local noop = function() end
local mouseOver = false
local withAnimations = true

local function Group(region)
    local group = { plays = 0, stops = 0, playing = false, anims = {} }
    function group:SetLooping(kind) self.looping = kind end
    function group:Play() self.plays = self.plays + 1 self.playing = true end
    function group:Stop() self.stops = self.stops + 1 self.playing = false end
    function group:IsPlaying() return self.playing end
    function group:CreateAnimation(kind)
        local anim = setmetatable({ kind = kind }, { __index = function(t, key)
            return function(self, ...) rawset(self, key:gsub("^Set", ""), { ... }) end
        end })
        self.anims[#self.anims + 1] = anim
        return anim
    end
    region.groups = region.groups or {}
    region.groups[#region.groups + 1] = group
    return group
end

local function Region(parent)
    local region = { parent = parent, shown = true, alpha = 1, width = 0, height = 0, points = {}, scripts = {} }
    region.Show = function(self) self.shown = true if self.scripts.OnShow then self.scripts.OnShow(self) end end
    region.Hide = function(self) self.shown = false end
    region.SetShown = function(self, on) self.shown = on and true or false end
    region.IsShown = function(self) return self.shown end
    region.SetAlpha = function(self, a) self.alpha = a end
    region.SetSize = function(self, w, h) self.width, self.height = w, h end
    region.SetWidth = function(self, w) self.width = w end
    region.SetHeight = function(self, h) self.height = h end
    region.GetWidth = function(self) return self.width end
    region.SetPoint = function(self, ...) self.points[#self.points + 1] = { ... } end
    region.ClearAllPoints = function(self) self.points = {} end
    region.SetScript = function(self, name, fn) self.scripts[name] = fn end
    region.GetScript = function(self, name) return self.scripts[name] end
    region.SetText = function(self, text) self.text = text end
    region.SetTextColor = function(self, r, g, b) self.textColor = { r, g, b } end
    region.SetVertexColor = function(self, r, g, b, a) self.vertex = { r, g, b, a } end
    region.SetDesaturated = function(self, on) self.desaturated = on end
    region.SetTexture = function(self, path) self.texture = path end
    region.GetScale = function() return 1 end
    region.IsMouseOver = function() return mouseOver end
    region.GetShadowOffset = function(self) return self.shadowX or 0, self.shadowY or 0 end
    region.GetShadowColor = function(self) return 0, 0, 0, self.shadowA or 0 end
    region.SetShadowOffset = function(self, x, y) self.shadowX, self.shadowY = x, y end
    region.SetShadowColor = function(self, _, _, _, a) self.shadowA = a end
    region.GetEffectiveScale = function() return 1 end
    region.CreateTexture = function(self) return Region(self) end
    region.GetRegions = function(self) return unpack(self.labels or {}) end
    region.CreateFontString = function(self) return Region(self) end
    if withAnimations then
        region.CreateAnimationGroup = function(self) return Group(self) end
    end
    return setmetatable(region, { __index = function(_, key)
        if type(key) == "string" and key:match("^%u") then return noop end
    end })
end

CreateFrame = function(_, _, parent) return Region(parent) end
UIParent = Region()
GameTooltip = nil
time = function() return 1800000000 end
date = os.date
UISpecialFrames = {}
tinsert = table.insert

local level = "full"
local settings = { goldTracker = true }
local state = { total = 500 * 10000, goal = 1000 * 10000, today = 50 * 10000, best = 40 * 10000 }

local ns = {}
ns.L = setmetatable({ Format = string.format }, { __index = function(_, key) return key end })
ns.Util = { FormatMoney = function(c) return tostring(math.floor((c or 0) / 10000)) .. "g" end }
ns.Config = { Get = function(_, key) return settings[key] end, Set = function(_, key, value) settings[key] = value end }
local PALETTE = { text = { 0.9, 0.9, 0.9 }, accentHi = { 0.95, 0.83, 0.53 } }
ns.Theme = {
    FONT = "font", sizes = { normal = 12, small = 11 },
    Unpack = function(key, alpha)
        local c = PALETTE[key] or { 0.5, 0.5, 0.5 }
        return c[1], c[2], c[3], alpha or 1
    end,
    CreatePanel = function(parent)
        local panel = Region(parent)
        panel.background = Region(panel)
        return panel
    end,
    CreateLabel = function(parent)
        local label = Region(parent)
        label.GetObjectType = function() return "FontString" end
        parent.labels = parent.labels or {}
        parent.labels[#parent.labels + 1] = label
        return label
    end,
    TopSheen = noop, Halo = noop, SetHalo = noop, SetBorderColor = noop,
    SetGradientAlpha = function() return true end,
    TextWidth = function() return 40 end,
}
ns.Widgets = {}
local runs = {}
ns.Motion = {
    Level = function() return level end,
    Run = function(_, owner, slot, _, apply, opts)
        runs[slot] = (runs[slot] or 0) + 1
        apply(0)
        ns.Motion.lastOwner = owner
        apply(1)
        if opts and opts.done then opts.done() end
    end,
    Stop = noop,
}
ns.GoldGoal = {
    STEPS = 10, version = 1,
    IsOn = function() return true end,
    Total = function() return state.total end,
    Goal = function() return state.goal end,
    Record = function() return nil end,
    Step = function(total, goal) return goal and math.floor(math.min(1, total / goal) * 10) or 0 end,
    Today = function() return state.today end,
    BestDay = function() return state.best end,
}
ns.GoldLog = { DayKey = function() return 20261018 end }

assert(loadfile(lfs_cwd .. "/UI/GoldGoal.lua"))("Blackthornes_TS", ns)
local UI = ns.GoldGoalUI

local checks = 0
local function check(label, condition)
    checks = checks + 1
    if not condition then error(("FAILED: %s"):format(label), 2) end
    print(("  ok  %s"):format(label))
end


local function Tick(seconds)
    local script = UI.seeWatch and UI.seeWatch.scripts.OnUpdate
    if not script then return end
    for _ = 1, math.floor(seconds / 0.05) do script(UI.seeWatch, 0.05) end
end

print("\ngoblin gold: transparent")

UI:Apply()
local frame = UI.frame
local title = frame.labels[1]
check("off by default: the window's glass is solid", frame.background.alpha == 1)
check("off by default: the level is 0", UI.SeeThroughLevel() == 0)
check("off by default: no shadow on the words", (title.shadowA or 0) == 0)

level = "off"
for index, clear in ipairs({ 0.5, 0.3, 0.15 }) do
    check("level " .. index .. " is saved", UI:SetSeeThrough(index) and settings.goldTrackerSeeThrough == index)
    check("level " .. index .. " thins the window", math.abs(frame.background.alpha - clear) < 1e-9)
    check("level " .. index .. " thins the bar's well", math.abs(UI.track.background.alpha - clear) < 1e-9)
end
check("the gold is left alone", UI.fill.alpha == 1)
check("the words get a shadow", title.shadowA == 1)

mouseOver = true
Tick(0.2)
check("the glass comes back under the mouse", frame.background.alpha == 1)
mouseOver = false
Tick(0.2)
check("and goes again when the mouse leaves", math.abs(frame.background.alpha - 0.15) < 1e-9)

level = "full"
mouseOver = true
Tick(0.1)
check("on Full it fades back, not all at once",
    frame.background.alpha > 0.15 and frame.background.alpha < 1)
Tick(0.5)
check("and gets there", frame.background.alpha == 1)
mouseOver = false
Tick(0.6)

check("off puts the glass back", UI:SetSeeThrough(0) and frame.background.alpha == 1)
check("off puts the shadow back", title.shadowA == 0)
check("off stops the watcher", UI.seeWatch.scripts.OnUpdate == nil)
check("a level it lacks is refused", UI:SetSeeThrough(7) == false and settings.goldTrackerSeeThrough == 0)

for _, key in ipairs(GLOBALS) do _G[key] = saved[key] end
print(("\n%d checks passed"):format(checks))
