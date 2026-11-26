-- Logic/TidyUp.lua and UI/TidyUpBox.lua outside WoW (a lighter save,
-- 2026-11-26). What must hold:
--   1. Always (the start) finds and removes nothing.
--   2. Find counts old readings and old suffix rows of other items, and
--      changes nothing.
--   3. Yours (crafted, used, starred, priced, listed) is never touched,
--      and no item loses its own price.
--   4. Picking a choice opens the window and saves nothing; Cancel, the
--      close gem and Escape leave the choice and the data as they were.
--   5. Confirm saves the choice and tidies; the next login tidies again.
--   6. The save's size is measured over frames.

local GLOBALS = { "CreateFrame", "UIParent", "UISpecialFrames", "tinsert", "time", "C_Timer" }
local saved = {}
for _, key in ipairs(GLOBALS) do saved[key] = _G[key] end

local failures = 0
local function check(label, got, want)
    if got == want then
        print("  ok   " .. label)
    else
        failures = failures + 1
        print(string.format("  FAIL %s: got %s, want %s", label, tostring(got), tostring(want)))
    end
end

local now = 1790000000
local DAY = 86400
time = function() return now end
C_Timer = nil

local function Frame()
    local frame = { shown = false, height = 0, scripts = {} }
    function frame:Hide()
        local was = self.shown
        self.shown = false
        if was and self.scripts.OnHide then self.scripts.OnHide(self) end
    end
    function frame:Show() self.shown = true end
    function frame:IsShown() return self.shown end
    function frame:SetHeight(h) self.height = h end
    function frame:SetScript(name, fn) self.scripts[name] = fn end
    function frame:CreateTexture() return Frame() end
    return setmetatable(frame, { __index = function() return function() end end })
end
local function Label()
    local label = { text = "" }
    function label:SetText(text) self.text = text end
    function label:GetStringHeight() return 14 end
    return setmetatable(label, { __index = function() return function() end end })
end
CreateFrame = function() return Frame() end
UIParent = Frame()
UISpecialFrames = {}
tinsert = table.insert

local ns = {}
ns.NewModule = function(name) local m = {} ns[name] = m return m end
ns.RegisterCommand = function() end
ns.RegisterEvent = function() end
local printed = {}
ns.Print = function(text) printed[#printed + 1] = text end
ns.PrintRaw, ns.Debug, ns.Warn = function() end, function() end, function() end
ns.COLORS = setmetatable({}, { __index = function() return "ffffffff" end })
ns.Util = {
    Clamp = function(v, l, h) return math.max(l, math.min(h, v)) end,
    Count = function(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end,
    FormatMoney = function(c) return tostring(c) end,
    HasFunction = function() return false end,
    GetItemLabel = function(i) return "item" .. tostring(i) end,
}
local buttons = {}
ns.Theme = {
    Fill = function() end,
    AddGameOutline = function() end,
    CreateLabel = function() return Label() end,
    Unpack = function() return 1, 1, 1 end,
}
ns.Widgets = {
    CreateButton = function(_, text, onClick)
        local b = Frame()
        b.text, b.onClick = text, onClick
        function b:SetEnabledState(on) self.disabled = not on end
        buttons[text] = b
        return b
    end,
}

local settings = {}
ns.Config = {
    Get = function(_, key) return settings[key] end,
    Set = function(_, key, value) settings[key] = value end,
    GetRealmKey = function() return "Realm-Alliance" end,
}
ns.PriceHistory = { GetTracked = function() return { [2589] = true } end }

local function Flat(times)
    local h = {}
    for _, t in ipairs(times) do h[#h + 1] = t; h[#h + 1] = 100; h[#h + 1] = 5 end
    return h
end
local old, recent = now - 40 * DAY, now - DAY

local function Fresh()
    ns.db = {
        prices = {
            ["Realm-Alliance"] = {
                -- Someone else's gear: one old suffix row, one new, old readings.
                [7000] = { market = 900, seen = recent, history = Flat({ old, recent }),
                           suffixes = { [11] = { market = 1, seen = old, history = Flat({ old }) },
                                        [12] = { market = 2, seen = recent, history = Flat({ old, recent }) } } },
                -- Crafted (tracked), starred, priced and listed: all yours.
                [2589] = { market = 50, seen = recent, history = Flat({ old, recent }) },
                [2590] = { market = 50, seen = recent, history = Flat({ old, recent }) },
                [2591] = { market = 50, seen = recent, history = Flat({ old, recent }),
                           suffixes = { [3] = { market = 1, seen = old } } },
                [2592] = { market = 50, seen = recent, history = Flat({ old, recent }) },
            },
            ["Other-Horde"] = { [8000] = { market = 5, seen = recent, history = Flat({ old, recent }) } },
        },
        favouritePrices = { [2590] = true },
        myPrices = { ["Realm-Alliance"] = { [2591] = { price = 10 } } },
        lastPosted = { ["Realm-Alliance"] = { [2592] = { price = 10, at = recent } } },
    }
end
Fresh()

assert(loadfile(lfs_cwd .. "/Data/Prices.lua"))("Blackthornes_TS", ns)
local touched = 0
ns.Prices.Touch = function() touched = touched + 1 end
ns.Prices.GetTable = function() return ns.db.prices["Realm-Alliance"] end
assert(loadfile(lfs_cwd .. "/Logic/TidyUp.lua"))("Blackthornes_TS", ns)
assert(loadfile(lfs_cwd .. "/UI/TidyUpBox.lua"))("Blackthornes_TS", ns)
local TidyUp, Box, P = ns.TidyUp, ns.TidyUpBox, ns.Prices
local prices = ns.db.prices["Realm-Alliance"]

local function Count(id, realm)
    return P.HistoryCount(ns.db.prices[realm or "Realm-Alliance"][id].history)
end

print("\nAlways removes nothing")
check("starts at Always", TidyUp:Days(), 0)
local got
TidyUp:Find(0, now, function(t) got = t end)
check("finds nothing", got.readings + got.rows, 0)
TidyUp:Apply(0, now)
check("removes nothing", Count(7000), 2)

print("\nFind changes nothing")
TidyUp:Find(30, now, function(t) got = t end)
check("old suffix rows", got.rows, 1)
check("old readings: item, new suffix row, other realm", got.readings, 3)
check("a size", got.bytes > 0, true)
check("nothing removed yet", Count(7000), 2)
check("old suffix row still there", prices[7000].suffixes[11] ~= nil, true)

print("\nthe window asks first")
local cancelled = 0
Box:Open(30, function() cancelled = cancelled + 1 end)
check("open", Box:IsShown(), true)
check("says the period", Box.old.note.text:find("30 days", 1, true) ~= nil, true)
check("says the size", Box.old.value.text:find("about", 1, true) ~= nil, true)
check("the kept row", Box.kept.value.text, "kept")
check("no choice saved", TidyUp:Days(), 0)
buttons["Cancel"].onClick()
check("Cancel closes", Box:IsShown(), false)
check("Cancel told the page", cancelled, 1)
check("Cancel saved nothing", TidyUp:Days(), 0)
check("Cancel removed nothing", Count(7000), 2)

Box:Open(90, function() cancelled = cancelled + 1 end)
Box.frame:Hide()
check("Escape is Cancel", cancelled, 2)
check("still nothing saved", TidyUp:Days(), 0)

check("Always opens no window", Box:Open(0), false)

print("\nConfirm keeps the choice and tidies")
local tallied
Box:Open(30, function() cancelled = cancelled + 1 end, function(t) tallied = t end)
buttons["Confirm"].onClick()
check("closed", Box:IsShown(), false)
check("not counted as Cancel", cancelled, 2)
check("choice saved", TidyUp:Days(), 30)
check("done told the page", tallied and tallied.rows, 1)
check("old suffix row gone", prices[7000].suffixes[11], nil)
check("new suffix row kept", prices[7000].suffixes[12] ~= nil, true)
check("its old reading gone", P.HistoryCount(prices[7000].suffixes[12].history), 1)
check("item's old reading gone", Count(7000), 1)
check("item keeps its price", prices[7000].market, 900)
check("other realm tidied", Count(8000, "Other-Horde"), 1)
check("said in chat", #printed, 1)
check("marked changed", touched > 0, true)

print("\nyours are kept in full")
check("crafted", Count(2589), 2)
check("starred", Count(2590), 2)
check("priced", Count(2591), 2)
check("priced: its suffix row too", prices[2591].suffixes[3] ~= nil, true)
check("listed", Count(2592), 2)

print("\na packed history tidies too")
Fresh()
prices = ns.db.prices["Realm-Alliance"]
P.PackRecord(prices[7000])
check("packed", type(prices[7000].history), "string")
TidyUp:Apply(30, now)
check("old reading gone from the packed one", Count(7000), 1)

print("\nthe next login")
local queued = {}
C_Timer = { After = function(_, fn) queued[#queued + 1] = fn end }
settings.keepPriceHistoryDays = 0
TidyUp:OnEnable()
check("Always waits for nothing", #queued, 0)
Fresh()
prices = ns.db.prices["Realm-Alliance"]
settings.keepPriceHistoryDays = 30
TidyUp:OnEnable()
check("a kept choice tidies after login", #queued, 1)
while #queued > 0 do table.remove(queued, 1)() end
check("tidied", Count(7000), 1)

print("\nthe save's size")
local size
TidyUp.bytes = nil
TidyUp:Measure(function(bytes) size = bytes end)
check("not in one frame", size, nil)
local frames = 0
while #queued > 0 do table.remove(queued, 1)(); frames = frames + 1 end
check("measured", type(size), "number")
check("about the size of the data", size > 200, true)
check("kept for the page", TidyUp.bytes, size)
check("reads in MB", TidyUp.FormatSize(21.4 * 1024 * 1024), "21 MB")
check("reads small sizes", TidyUp.FormatSize(3.2 * 1024 * 1024), "3.2 MB")
check("reads KB", TidyUp.FormatSize(2048), "2 KB")

for _, key in ipairs(GLOBALS) do _G[key] = saved[key] end
if failures > 0 then error(("%d tidy up check(s) failed"):format(failures)) end
print("\n  tidy up: all checks passed")
