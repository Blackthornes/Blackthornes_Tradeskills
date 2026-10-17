-- Goblin Gold (asked 2026-10-17): the gold on every character of this
-- realm and side, and a goal cheered a tenth at a time.
--
-- What must hold:
--   1. The total adds the characters of this realm and side, the one
--      playing at its live gold; other realms and the other side are left
--      out; one character under two records counts once; your other
--      account's characters count.
--   2. Setting a goal starts at the tenth already reached, so nothing
--      passed before is cheered.
--   3. Each tenth is cheered once: a dip and a climb back is not cheered
--      again, and two tenths passed at once are one cheer, the bigger.
--   4. The goal itself is its own cheer, with how long it took.
--   5. A cheer waits while you are busy and comes once you are free.
--   6. New gold floats up, gold from your own characters does not, and
--      nothing happens while it is off.
--   7. The typed command sets and clears a goal; the next goal offered is
--      a round number past what you have; the words read right.

local GLOBALS = { "GetMoney", "GetRealmName", "UnitFactionGroup", "InCombatLockdown",
    "GetUIPanel", "C_Timer", "time", "date" }
local saved = {}
for _, key in ipairs(GLOBALS) do saved[key] = _G[key] end

local GOLD = 10000
local money = 500 * GOLD
local busy = false
local now = 1800000000

GetMoney = function() return money end
GetRealmName = function() return "Forever" end
UnitFactionGroup = function() return "Horde" end
InCombatLockdown = function() return busy end
GetUIPanel = function() return nil end
C_Timer = nil
time = function(t) if t then return os.time(t) end return now end
date = os.date

local settings = { goldTracker = true }
local printed = {}
local commands = {}

local ns = {}
ns.L = setmetatable({ Format = string.format }, { __index = function(_, key) return key end })
ns.Util = { FormatMoney = function(c) return tostring(math.floor((c or 0) / GOLD)) .. "g" end,
    FormatAgeAgo = function() return "1h ago" end }
ns.NewModule = function(name) local m = {}; ns[name] = m; return m end
ns.RegisterCommand = function(name, _, fn) commands[name] = fn end
ns.RegisterEvent = function() end
ns.Print = function(text) printed[#printed + 1] = text end
ns.Config = {
    Get = function(_, key) return settings[key] end,
    Set = function(_, key, value) settings[key] = value end,
    GetCharacterKey = function() return "Player-1-AAA" end,
    GetRealmKey = function() return "Forever-Horde" end,
}
ns.db = { characters = {
    ["Player-1-AAA"] = { name = "Brakka", surname = "Ironfist", realm = "Forever", faction = "Horde", gold = 1 },
    ["Player-1-BBB"] = { name = "Mira", realm = "Forever", faction = "Horde", gold = 200 * GOLD, inventoryAt = now - 3600 },
    -- An old record of Mira, under her name: the same character.
    ["Mira-Forever"] = { name = "Mira", realm = "Forever", faction = "Horde", gold = 150 * GOLD },
    ["Player-1-CCC"] = { name = "Sella", realm = "Forever", faction = "Alliance", gold = 900 * GOLD },
    ["Player-2-DDD"] = { name = "Grizzle", realm = "Elsewhere", faction = "Horde", gold = 900 * GOLD },
    -- Your other account's character, on this realm and side.
    ["Player-1-EEE"] = { name = "Toff", realm = "Forever", faction = "Horde", gold = 100 * GOLD, linkedFrom = "Brakka" },
} }
ns.Characters = { Same = function(_, a, b)
    local pair = a .. "|" .. b
    return a == b or pair == "Player-1-BBB|Mira-Forever" or pair == "Mira-Forever|Player-1-BBB"
end }
ns.Recipes = { GetCharacterName = function(_, key)
    local record = ns.db.characters[key]
    return record.name .. (record.surname and (" " .. record.surname) or "")
end }

local cheers, floats = {}, {}
ns.GoldGoalUI = {
    Cheer = function(_, cheer) cheers[#cheers + 1] = cheer end,
    Float = function(_, amount) floats[#floats + 1] = amount end,
    Refresh = function() end,
    Apply = function() end,
}

assert(loadfile(lfs_cwd .. "/Logic/GoldGoal.lua"))("Blackthornes_TS", ns)
local GoldGoal = ns.GoldGoal

local checks = 0
local function check(label, condition)
    checks = checks + 1
    if not condition then error(("FAILED: %s"):format(label), 2) end
    print(("  ok  %s"):format(label))
end

print("\ngoblin gold: the total")

local total, count = GoldGoal:Total()
check("this realm and side, the one playing live, an old record once, the other account too",
    total == (500 + 200 + 100) * GOLD and count == 3)
local members = GoldGoal:Members()
check("most gold first, whole names", members[1].name == "Brakka Ironfist" and members[1].isCurrent
    and members[2].name == "Mira" and members[3].linked == "Brakka")
check("each with when it was seen", members[2].at == now - 3600 and members[1].at == now)

print("\ngoblin gold: the goal")

GoldGoal:SetGoal(2000 * GOLD)
local record = ns.db.goldGoals["Forever-Horde"]
check("saved for this realm and side", record and record.goal == 2000 * GOLD and record.setAt == now)
check("starting at the tenth already reached", record.best == 4)
check("nothing passed before is cheered", #cheers == 0)

money = money + 150 * GOLD   -- 950g of 2000g: still the fourth tenth
GoldGoal:Changed()
check("short of the next tenth, no cheer", #cheers == 0)

money = money + 60 * GOLD    -- 1010g: the fifth tenth
GoldGoal:Changed()
check("a new tenth is cheered", #cheers == 1 and cheers[1].kind == "step" and cheers[1].step == 5)

money = money - 100 * GOLD
GoldGoal:Changed()
money = money + 100 * GOLD
GoldGoal:Changed()
check("a dip and a climb back is not cheered again", #cheers == 1)

money = money + 450 * GOLD   -- 1460g: past the sixth and seventh
GoldGoal:Changed()
check("two tenths at once are one cheer, the bigger", #cheers == 2 and cheers[2].step == 7)

print("\ngoblin gold: waiting while busy")

busy = true
money = money + 200 * GOLD   -- 1660g: the eighth
GoldGoal:Changed()
check("held in a fight", #cheers == 2 and GoldGoal.pending and GoldGoal.pending.step == 8)
money = money + 200 * GOLD   -- 1860g: the ninth
GoldGoal:Changed()
check("two held are one, the bigger", GoldGoal.pending.step == 9)
busy = false
GoldGoal:Flush()
check("and comes once you are free", #cheers == 3 and cheers[3].step == 9 and GoldGoal.pending == nil)

local auction = { IsShown = function() return true end }
_G.AuctionHouseFrame = auction
check("the auction house counts as busy", GoldGoal:Busy() == true)
_G.AuctionHouseFrame = nil
check("free again", GoldGoal:Busy() == false)

print("\ngoblin gold: reaching it")

now = now + 3 * 86400
money = money + 200 * GOLD   -- 2060g
GoldGoal:Changed()
check("the goal is its own cheer", #cheers == 4 and cheers[4].kind == "goal")
check("with how long it took", cheers[4].took == 3 * 86400 and record.reachedAt == now)
GoldGoal:Changed()
check("and only once", #cheers == 4)

print("\ngoblin gold: floating gold")

GoldGoal:OnRecord("auction", 48 * GOLD)
check("new gold floats up", #floats == 1 and floats[1] == 48 * GOLD)
GoldGoal:OnRecord("transfer", 100 * GOLD)
GoldGoal:OnRecord("vendor", -5 * GOLD)
check("gold from your own characters and gold spent do not", #floats == 1)

settings.goldTracker = false
GoldGoal:OnRecord("auction", 10 * GOLD)
GoldGoal:SetGoal(5000 * GOLD)
money = money + 3000 * GOLD
GoldGoal:Changed()
check("off: nothing floats and nothing cheers", #floats == 1 and #cheers == 4)
settings.goldTracker = true

print("\ngoblin gold: the command and the words")

commands.gold("goal 5,000g")
check("typed goal is set in gold", GoldGoal:Goal() == 5000 * GOLD)
commands.gold("goal")
check("a goal of nothing clears it", GoldGoal:Goal() == nil)
commands.gold("off")
check("off", settings.goldTracker == false)
commands.gold("on")
check("on", settings.goldTracker == true)

check("tenths are counted down", GoldGoal.Step(1999, 2000) == 9 and GoldGoal.Step(5000, 2000) == 10
    and GoldGoal.Step(5, nil) == 0)
check("the next goal is round and past what you have",
    GoldGoal.NextGoal(5120 * GOLD) == 8000 * GOLD and GoldGoal.NextGoal(340 * GOLD) == 550 * GOLD)

ns.Theme, ns.Widgets = {}, {}
ns.GoldLog = {
    KeyStart = function(day) return os.time({ year = math.floor(day / 10000), month = math.floor(day / 100) % 100, day = day % 100, hour = 0 }) end,
    DayStart = function(t) local d = os.date("*t", t) return os.time({ year = d.year, month = d.month, day = d.day, hour = 0 }) end,
}
assert(loadfile(lfs_cwd .. "/UI/GoldGoal.lua"))("Blackthornes_TS", ns)
local UI = ns.GoldGoalUI
check("how long it took", UI.TookText(11 * 86400 + 5) == "Took 11 days" and UI.TookText(86400) == "Took 1 day"
    and UI.TookText(7300) == "Took 2 hours" and UI.TookText(60) == "Took under an hour")
local today = tonumber(os.date("%Y%m%d", now))
check("a best day this week by its name", UI.BestDayText(612 * GOLD, today, now):find("^%a+day, 612g$") ~= nil)
local old = tonumber(os.date("%Y%m%d", now - 12 * 86400))
check("an older one by how long ago", UI.BestDayText(612 * GOLD, old, now) == "612g, 12 days ago")

for _, key in ipairs(GLOBALS) do _G[key] = saved[key] end

print(("\n%d check(s) passed\n"):format(checks))
