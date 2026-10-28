-- The Sale Total on the drawer's Sell view (2026-10-28).
--
-- What must hold:
--   1. Held lines count for nothing; the total is the rest's postTotal.
--   2. Changes lists the items that rose, biggest first, and adds up the
--      drops and the items gone.
--   3. Milestones fall on round numbers: 10g under 100g, then the power of
--      ten below the total.
--   4. The count-up never takes longer than REVEAL_MOST.
--   5. "Up" and "Down" since the last scan, nothing under a gold.
--   6. On by default; off when unticked.
--   7. After a scan the band counts up to the true total, then keeps the
--      total and the best, and says New Best only past a best kept before.
--   8. A change that is no scan rolls straight to the new total.

local GLOBALS = { "CreateFrame", "GetTime", "GameTooltip" }
local saved = {}
for _, key in ipairs(GLOBALS) do saved[key] = _G[key] end

local function check(cond, message)
    if not cond then error(message, 2) end
end

local G = 10000

-- A frame, texture or font string that takes any call.
local function Stub()
    local object = { shown = true, text = "" }
    return setmetatable(object, { __index = function(_, key)
        if key == "IsShown" then return function(self) return self.shown end end
        if key == "SetShown" then return function(self, on) self.shown = on and true or false end end
        if key == "Show" then return function(self) self.shown = true end end
        if key == "Hide" then return function(self) self.shown = false end end
        if key == "SetText" then return function(self, text) self.text = text end end
        if key == "GetFrameLevel" then return function() return 1 end end
        if key == "CreateTexture" or key == "CreateFontString" then return function() return Stub() end end
        return function() end
    end })
end
CreateFrame = function() return Stub() end
local clock = 100
GetTime = function() return clock end
GameTooltip = Stub()

local ns = {}
ns.NewModule = function(name) local m = {}; ns[name] = m; return m end
local settings = {}
ns.Config = { Get = function(_, k) return settings[k] end, Set = function(_, k, v) settings[k] = v end }
ns.Util = {
    Comma = function(n) return tostring(n) end,
    FormatMoney = function(c) return tostring(math.floor(c)) .. "c" end,
}
ns.Theme = {
    FONT = "font", sizes = { title = 16 },
    Fill = function() return Stub() end, Border = function() end,
    AccentStripe = function() return Stub() end, SetGradientAlpha = function() end,
    LightGradient = function() end, CreateLabel = function() return Stub() end,
    Unpack = function() return 1, 1, 1, 1 end, TextWidth = function() return 40 end,
}
-- Subtle: the number rolls, no coins fly; every tween lands at once.
ns.Motion = {
    Level = function() return "subtle" end,
    Run = function(_, _, _, _, apply, opts) apply(1); if opts and opts.done then opts.done() end end,
    Stop = function() end, SetValue = function() end,
    Blend = function(_, _, _, target, _, apply) apply(target) end,
    EaseOut = function(p) return p end, EaseOutBack = function(p) return p end,
}

assert(loadfile(lfs_cwd .. "/UI/SaleTotal.lua"))("Blackthornes_TS", ns)
local ST = ns.SaleTotal

-- 1. Worths.
local worths, total = ST.Worths({
    { itemID = 1, postTotal = 5 * G },
    { itemID = 1, postTotal = 2 * G },
    { itemID = 2, postTotal = 3 * G, held = true },
    { itemID = 3, postTotal = 1 * G },
})
check(total == 8 * G, "held lines are left out of the total")
check(worths[1] == 7 * G and worths[2] == nil, "two stacks of one item add up")

-- 2. Changes.
local rises, rest = ST.Changes({ [1] = 2 * G, [3] = 4 * G, [9] = 1 * G }, { [1] = 7 * G, [3] = 1 * G, [4] = 9 * G })
check(#rises == 2 and rises[1].itemID == 4 and rises[1].amount == 9 * G, "biggest rise first")
check(rises[2].itemID == 1 and rises[2].amount == 5 * G, "a rise counts only what it rose by")
check(rest == -4 * G, "drops and items gone are added up apart")

-- 3. Milestones.
check(ST.MilestoneStep(40 * G) == 10 * G, "under 100g milestones are every 10g")
check(ST.MilestoneStep(450 * G) == 100 * G, "at 450g they are every 100g")
check(ST.MilestoneStep(1000 * G) == 1000 * G, "at 1,000g every 1,000g")
check(ST.Crossed(95 * G, 104 * G) == 100 * G, "passing 100g is a milestone")
check(ST.Crossed(101 * G, 150 * G) == nil, "no round number passed, no milestone")
check(ST.Crossed(150 * G, 100 * G) == nil, "going down is never a milestone")

-- 4. The count-up's pace.
check(ST.PerStep(3) == ST.LEAST_A_BEAT, "a short list goes a few a beat")
local steps = math.ceil(200 / ST.PerStep(200))
check(steps * ST.BEAT <= ST.REVEAL_MOST + 1e-9, "a long list still finishes in time")

-- 5. Since the last scan.
check(ST.DeltaText(100 * G, 112 * G) == "Up 12g since last scan", "up")
check(ST.DeltaText(100 * G, 96 * G) == "Down 4g since last scan", "down")
check(ST.DeltaText(100 * G, 100 * G + 30) == nil, "under a gold says nothing")
check(ST.DeltaText(nil, 5 * G) == nil, "no scan before, nothing to compare")

-- 6. On by default.
check(ST:IsOn(), "on while never set")
settings.saleTotal = false
check(not ST:IsOn(), "off when unticked")
settings.saleTotal = nil

-- 7. A scan, counted up.
ST:Build(Stub(), Stub(), Stub())
check(ST:SetShown(true), "the band shows on Sell")
settings.saleTotalLast = 10 * G
settings.saleTotalBest = 12 * G

local lines = {
    { itemID = 1, postTotal = 6 * G },
    { itemID = 2, postTotal = 4 * G },
    { itemID = 3, postTotal = 3 * G },
}
ST:Progress(0.5)
ST:Update(lines, 0)
check(ST.status.text == "Pricing 2 of 3", "while scanning it counts what is priced")
check(ST.shown == 13 * G, "the first look shows the total as it stands")

lines[1].postTotal = 9 * G
ST:ScanFinished()
ST:Update(lines, 1)
check(ST.shown == 13 * G, "the rise waits for the count-up")
check(ST.ticking, "the count-up has started")
ST:Tick(1)
check(ST.shown == 16 * G, "the rise lands")
ST:Tick(1)
check(not ST.ticking, "it stops once all are in")
check(ST.shown == 16 * G, "it ends on the true total")
check(settings.saleTotalLast == 16 * G and settings.saleTotalBest == 16 * G, "the total and the best are kept")
check(ST.delta.text == "Up 6g since last scan", "it says how far it moved")
check(ST.best.shown, "a new best is told")
check(ST.status.text == "3 of 3 priced", "all priced")

-- 8. No scan: straight to the new total, nothing kept.
table.remove(lines, 2)
ST:Update(lines, 0)
check(ST.shown == 12 * G and not ST.ticking, "a listing rolls straight down")
check(settings.saleTotalLast == 16 * G, "only a scan moves the kept total")

for _, key in ipairs(GLOBALS) do _G[key] = saved[key] end
print("test_saletotal: ok")
