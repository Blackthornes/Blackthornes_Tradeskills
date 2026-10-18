-- Goblin Gold's glow-up (asked 2026-10-18, from a mockup): motion like
-- Farmer's XP bar, and more shine on the bar.
--
-- What must hold:
--   1. The bar keeps its size, and builds on a client with no animations.
--   2. The star sits on the end of the gold and hides with no gold.
--   3. Full plays the star, the light along the gold, the sparkles and the
--      coin's glint; Subtle only the star and the light; Off nothing.
--   4. The light is set again only when the gold's width moves by 2 or more.
--   5. A tenth's diamond lights once reached, and goes dark below it.
--   6. Today pulses only on Full and only while it beats your best day.
--   7. The total counts up bright on Full and settles to its own colour.

local GLOBALS = { "CreateFrame", "UIParent", "GameTooltip", "time", "date", "UISpecialFrames", "tinsert" }
local saved = {}
for _, key in ipairs(GLOBALS) do saved[key] = _G[key] end

local noop = function() end
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
    region.GetEffectiveScale = function() return 1 end
    region.CreateTexture = function(self) return Region(self) end
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
    CreatePanel = function(parent) return Region(parent) end,
    CreateLabel = function(parent) return Region(parent) end,
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

local function Playing(group) return group and group.playing end

print("\ngoblin gold: the glow-up")

UI:Apply()
check("the bar keeps its size", UI.frame.width == 270 and UI.frame.height == 78)
local inner = UI.trackWidth - 2
local tip = UI.spark.points[1]
check("the star sits on the end of the gold", tip and tip[3] == "LEFT" and tip[4] == 1 + inner * 0.5 and UI.spark.shown)

check("Full: the star breathes, the light runs, the coin glints",
    Playing(UI.breath) and Playing(UI.glowBreath) and Playing(UI.sweepGroup) and Playing(UI.glintGroup))
local twinkling = 0
for _, group in pairs(UI.twinkleGroups) do if group.playing then twinkling = twinkling + 1 end end
check("Full: sparkles twinkle on the gold", twinkling >= 2)
check("Full: Today pulses while it beats your best day", Playing(UI.todayPulse) and UI.todayGlow.shown)

local lit = 0
for _, tick in ipairs(UI.ticks) do if tick.lit then lit = lit + 1 end end
check("the tenths reached light up", lit == 5 and UI.ticks[5].lit and not UI.ticks[6].lit
    and UI.ticks[5].width == UI.TICK_LIT and UI.ticks[6].desaturated == true)

local plays = UI.sweepGroup.plays
UI:FitSweep(UI.sweepWidth + 1)
check("the light is not set again for a pixel", UI.sweepGroup.plays == plays)
UI:FitSweep(UI.sweepWidth + 5)
check("it is for a real move", UI.sweepGroup.plays == plays + 1)

state.total = 600 * 10000
runs.count = 0
UI:Refresh(true)
check("the total counts up and settles to its own colour", runs.count == 1
    and UI.total.textColor[1] == PALETTE.text[1] and UI.totalGlow.alpha == 0)
lit = 0
for _, tick in ipairs(UI.ticks) do if tick.lit then lit = lit + 1 end end
check("a new tenth lights", lit == 6)

state.total = 300 * 10000
UI:Refresh(true)
check("a tenth below goes dark again", not UI.ticks[4].lit and UI.ticks[3].lit)

state.today = 10 * 10000
UI:Refresh(true)
check("no pulse once Today is behind your best day", not Playing(UI.todayPulse) and not UI.todayGlow.shown)

level = "subtle"
state.today = 50 * 10000
UI:Refresh(true)
twinkling = 0
for _, group in pairs(UI.twinkleGroups) do if group.playing then twinkling = twinkling + 1 end end
check("Subtle: the star and the light only", Playing(UI.breath) and Playing(UI.sweepGroup)
    and not Playing(UI.glintGroup) and twinkling == 0 and not Playing(UI.todayPulse))

level = "off"
UI:Refresh(true)
check("Off: nothing moves", not Playing(UI.breath) and not Playing(UI.sweepGroup)
    and not Playing(UI.glintGroup) and not Playing(UI.todayPulse))

state.total = 0
UI:Refresh(true)
check("no gold, no star", not UI.spark.shown and not UI.sparkGlow.shown)

-- A client with no animations still builds and draws the bar.
withAnimations = false
level = "full"
UI.frame = nil
UI.shownTotal = nil
state.total = 500 * 10000
local ok, problem = pcall(function() UI:Apply() UI:Refresh(true) end)
check("builds without animations", ok and UI.frame and UI.breath == nil and UI.spark.shown or error(problem))

for _, key in ipairs(GLOBALS) do _G[key] = saved[key] end

print(("\n%d check(s) passed\n"):format(checks))
