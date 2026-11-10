-- The Sale Total in the drawer's header (2026-10-28): since 2026-11-10 it
-- shows what the Sell list comes to and holds still as you list.
--
-- What must hold:
--   1. Worth is price times count; Left uses each row's own total and skips
--      held lines and lines with a note.
--   2. It reads "Potential Sale Total:" with no line under the number.
--   3. On by default; off when unticked.
--   4. The number is the whole list before anything is listed, follows the
--      prices as they move, holds still while a listing is confirmed and as
--      it goes up, and nothing is written to the save.

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
    FormatMoney = function(c) return tostring(math.floor(c / 10000)) .. "g" end,
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

-- 1. Worth and Left.
check(ST.Worth(100 * G, 2) == 200 * G, "a listing is its price times the stack")
check(ST.Worth(0, 5) == 0, "nothing priced counts nothing")
local left, count = ST.Left({
    { itemID = 1, unitPrice = 10 * G, postQuantity = 2, postTotal = 20 * G },
    { itemID = 2, unitPrice = 50 * G, postQuantity = 1, postTotal = 50 * G, held = true },
    { itemID = 3, unitPrice = 9 * G, postQuantity = 1, postTotal = 9 * G, noted = true },
    { itemID = 4, unitPrice = 2 * G, postQuantity = 3 },
})
check(left == 20 * G + 6 * G, "held and noted lines are left out; no total means price times count")
check(count == 2, "held and noted lines are not counted")

-- 3. The money text (the label and no line under it are checked below).
check(ST.MoneyText(0) == "0g", "nothing shows as 0g")
check(ST.UnderText == nil and ST.DrawUnder == nil, "there is no line under the number")

-- 4. The switch.
check(ST:IsOn(), "on by default")
settings.saleTotal = false
check(not ST:IsOn(), "off when unticked")
settings.saleTotal = nil

-- 5. A visit.
local pending = {}
ns.Posting = { AllPending = function() return pending end }
local bar = Stub()
ST:Attach(bar, Stub())
check(ST.counter and ST.counter:IsShown(), "the counter shows in the header")
check(ST.label.text == "Potential Sale Total:", "it reads Potential Sale Total:")
check(ST.under == nil, "nothing sits under the number")
check(ST:Width() > 0, "it takes room the header text gives way to")
ST:NewVisit()
local function List(a, b)
    local lines = {}
    if a then lines[#lines + 1] = { itemID = 1, unitPrice = a, postQuantity = 1, postTotal = a } end
    if b then lines[#lines + 1] = { itemID = 2, unitPrice = b, postQuantity = 2, postTotal = 2 * b } end
    return lines
end
ST:Update(List(100 * G, 10 * G), 0)
check(ST.shown == 120 * G, "before anything is listed it shows the whole list")
ST:Update(List(100 * G, 15 * G), 0)
check(ST.shown == 130 * G, "a scan that moves a price moves the total")
-- Listing item 1: it is confirmed while the bags catch up.
pending[1] = { itemID = 1 }
ST:Update(List(nil, 15 * G), 0)
check(ST.shown == 130 * G, "while a listing is confirmed the number waits")
pending[1] = nil
ST:NoteListed(1, 1, 100 * G)
check(ST.listed == 100 * G and ST.listings == 1, "a listing joins what was listed")
check(ST.shown == 130 * G, "and the number does not move")
ST:Update(List(nil, 15 * G), 0)
check(ST.shown == 130 * G and ST.left == 30 * G, "once the list catches up it still reads the same")
ST:NewVisit()
check(ST.listed == 0 and ST.listings == 0, "a new visit starts with nothing listed")
ST:Update(List(nil, 15 * G), 0)
check(ST.shown == 30 * G, "a new visit shows what the list holds now")
check(settings.saleTotalBest == nil and settings.saleTotalLast == nil, "nothing is saved")
settings.saleTotal = false
check(ST:SetShown(true) == false and not ST.counter:IsShown(), "unticked, the counter hides")
check(ST:Width() == 0, "hidden, it takes no room")
settings.saleTotal = nil

for _, key in ipairs(GLOBALS) do _G[key] = saved[key] end
print("test_saletotal: ok")
