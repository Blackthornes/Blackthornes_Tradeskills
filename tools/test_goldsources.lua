-- Goblin Gold's card: where this week's gold came from (asked 2026-10-20).
--
-- What must hold:
--   1. The game's Statistics read as numbers: plain counts, money with coin
--      icons, and nothing for "--", an error or a client without them.
--   2. This week's quest gold comes with how many quests were handed in,
--      and mob gold with Blackthornes Farmer's kills and loot worth.
--   3. Without Farmer the mob line shows its gold alone, no kills.
--   4. The card's lines: THIS WEEK and ALL TIME headings only with rows
--      under them, gold "each" by quest and by kill, counts grouped.

local saved = { GetStatistic = GetStatistic, BlackthornesFarmer = BlackthornesFarmer, time = time }
local NOW = 1800000000
time = function(t) if t then return os.time(t) end return NOW end

local stats = {}
GetStatistic = function(id)
    local value = stats[id]
    if value == "boom" then error("secret value") end
    return value
end

local ns = {}
ns.L = setmetatable({ Format = string.format }, { __index = function(_, key) return key end })
ns.Util = { FormatMoney = function(c) return tostring(c) .. "c" end }
ns.NewModule = function(name) local m = {}; ns[name] = m; return m end
ns.RegisterCommand = function() end
ns.RegisterEvent = function() end
ns.Config = { Get = function() return nil end, Set = function() end }
ns.COLORS = { muted = "ff7a8089" }

local week = { quests = { i = 1200 }, loot = { i = 500 }, auctionSales = { i = 9000 }, vendorSales = { i = 0 } }
local colors = { quests = { 0.78, 0.6, 0.98 }, loot = { 0.98, 0.84, 0.35 },
    auctionSales = { 0.31, 0.82, 0.55 }, vendorSales = { 0.53, 0.78, 0.95 } }
local texts = { auctionSales = "Auction sales", vendorSales = "Vendor sales" }
ns.GoldLog = {
    Bins = function() return "bins" end,
    Totals = function(_, bins) return bins == "bins" and { sources = week } or nil end,
    QuestsDone = function(_, days) return days == 7 and 4 or 0 end,
    GetSource = function(_, key) return { text = texts[key] or key, color = colors[key] } end,
}

assert(loadfile(lfs_cwd .. "/Logic/GoldGoal.lua"))("Blackthornes_TS", ns)
local GoldGoal = ns.GoldGoal
ns.Theme, ns.Widgets = {}, {}
assert(loadfile(lfs_cwd .. "/UI/GoldGoal.lua"))("Blackthornes_TS", ns)
local UI = ns.GoldGoalUI

local checks = 0
local function check(label, condition)
    checks = checks + 1
    if not condition then error(("FAILED: %s"):format(label), 2) end
    print(("  ok  %s"):format(label))
end

print("\ngold sources: the game's statistics")
stats[98] = "1,204"
stats[1197] = "--"
stats[326] = "903 |TInterface\\MoneyFrame\\UI-GoldIcon:0:0:2:0|t 12 |TInterface\\MoneyFrame\\UI-SilverIcon:0:0:2:0|t"
stats[333] = "boom"
check("a plain count", GoldGoal.Statistic(98) == 1204)
check("a dash is nothing", GoldGoal.Statistic(1197) == nil)
check("money with coin icons", GoldGoal.Statistic(326) == 903 * 10000 + 12 * 100)
check("an error is nothing", GoldGoal.Statistic(333) == nil)
check("a number as it is", (function() stats[98] = 77 return GoldGoal.Statistic(98) end)() == 77)
local keep = GetStatistic
GetStatistic = nil
check("a client without statistics gives nothing", GoldGoal.Statistic(98) == nil)
GetStatistic = keep
stats[98] = "1,204"

print("\ngold sources: this week")
BlackthornesFarmer = nil
local sources = GoldGoal:Sources(NOW)
check("quest gold and how many", sources.quests.gold == 1200 and sources.quests.count == 4)
check("no Farmer, no kills", sources.mobs == nil and sources.lootGold == 500)
check("all time keeps what the game gave", sources.allTime.quests == 1204 and sources.allTime.kills == nil
    and sources.allTime.questGold == 9031200 and sources.allTime.looted == nil)

BlackthornesFarmer = { Stats = { KillsAndLoot = function(_, days)
    return days == 7 and { kills = 50, loot = 2000, coin = 400 } or nil
end } }
sources = GoldGoal:Sources(NOW)
check("Farmer's kills and their loot", sources.mobs and sources.mobs.kills == 50
    and sources.mobs.loot == 2000 and sources.mobs.gold == 500)
BlackthornesFarmer = { Stats = { KillsAndLoot = function() error("broken") end } }
check("a Farmer that raises is skipped", GoldGoal:Sources(NOW).mobs == nil)

print("\ngold sources: the card's lines")
local function Find(lines, left)
    for index, line in ipairs(lines) do if line.left == left then return line, index end end
end
local lines = UI.SourceLines({}, {
    quests = { gold = 1200, count = 4 }, lootGold = 500,
    mobs = { gold = 500, kills = 50, loot = 2000 },
    auctionSales = 9000, vendorSales = 0,
    allTime = { quests = 1204, kills = 18430, questGold = 9031200 },
})
local heading, at = Find(lines, "THIS WEEK")
check("THIS WEEK heads the week", heading and heading.heading and at == 1)
local quests = Find(lines, "Quests")
check("quests: how many and gold each", quests.note == "4 done" and quests.right:find("^1200c") and quests.right:find("300c each"))
local mobs = Find(lines, "Mobs")
check("mobs: kills and coin plus loot each", mobs.note == "50 killed" and mobs.right:find("^500c") and mobs.right:find("50c each"))
check("their loot is worth", Find(lines, "Their loot is worth").right == "2000c more")
check("auction sales shown, empty vendor sales left out", Find(lines, "Auction sales") and not Find(lines, "Vendor sales"))
check("ALL TIME with counts grouped", Find(lines, "ALL TIME").heading and Find(lines, "Quests done").right == "1,204"
    and Find(lines, "Mobs killed").right == "18,430" and Find(lines, "Gold from quests").right == "9031200c"
    and not Find(lines, "Gold looted"))

lines = UI.SourceLines({}, { quests = { gold = 0, count = 0 }, lootGold = 0, auctionSales = 0, vendorSales = 0, allTime = {} })
check("nothing this week, no headings", #lines == 0)
lines = UI.SourceLines({}, { quests = { gold = 0, count = 3 }, lootGold = 0, allTime = {} })
check("quests with no gold still say how many", Find(lines, "Quests").note == "3 done" and Find(lines, "Quests").right == "0c")
check("big counts grouped", UI.Count(1234567) == "1,234,567" and UI.Count(12) == "12")

GetStatistic, BlackthornesFarmer, time = saved.GetStatistic, saved.BlackthornesFarmer, saved.time
print(("\n%d check(s) passed\n"):format(checks))
