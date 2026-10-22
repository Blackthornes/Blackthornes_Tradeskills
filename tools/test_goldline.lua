-- Logic/GoldLog.lua outside WoW: the line of your gold over the Gold chart.
--
--   1. The longer periods (3m, Year, All) come back as bars.
--   2. For all your characters the line is worked back from the gold they
--      have now, leaving out gold moved between them.
--   3. For the character playing it reads the gold written down by GUID,
--      and a bin with nothing written down before it is not known.
--   4. A character kept by name only writes nothing.

local savedTime, savedDate = time, date
date = os.date

local ns = {}
ns.NewModule = function(name) local m = {} ns[name] = m return m end
ns.RegisterEvent = function() return true end

local key = "Player-1-0A"
ns.Config = {
  GetRealmKey = function() return "Realm-A" end,
  GetCharacterKey = function() return key end,
}
ns.db = { characters = {} }

local purse = 50000
GetMoney = function() return purse end
local everyone = 200000
ns.GoldGoal = { Total = function(_, _, all) return all and everyone or purse end }

local chunk = assert(loadfile(lfs_cwd .. "/Logic/GoldLog.lua"))
chunk("Blackthornes_TS", ns)

local GL = ns.GoldLog
local failures = 0

local function check(label, got, want)
  if got ~= want then
    failures = failures + 1
    print(string.format("  FAIL  %-56s got %s, wanted %s", label, tostring(got), tostring(want)))
  else
    print(string.format("  ok    %-56s %s", label, tostring(got)))
  end
end

local NOW = os.time({ year = 2026, month = 10, day = 22, hour = 12 })
time = function(t) if t then return os.time(t) end return NOW end
local DAY = 86400

print("\ngold line: periods")
check("3m reaches back 91 days, a bar a week", #GL:Bins("quarter", nil, nil, NOW), 13)
check("a year, a bar a week", #GL:Bins("year", nil, nil, NOW), 53)
check("All with nothing kept still shows a week", #GL:Bins("all", nil, nil, NOW), 7)
GL:Record("loot", 100, NOW - 20 * DAY)
check("All reaches back to the first day kept", #GL:Bins("all", nil, nil, NOW), 21)

print("\ngold line: all characters")
GL.session = {}
GL.sessionStart = NOW - 3600
GL:Record("loot", 3000, NOW - 2 * DAY)
GL:Record("repairs", -1000, NOW - DAY)
GL:Record("transfer", 40000, NOW - DAY)
local bins = GL:Bins("week", nil, nil, NOW)
local line = GL:Line(bins, "all", "week", NOW)
check("one value a bar", #line, #bins)
check("today's bar is the gold now", line[#line], everyone)
check("yesterday's end leaves out today", line[#line - 1], everyone)
check("before the repair it was more", line[#line - 2], everyone + 1000)
check("before the loot it was less, moved gold left out", line[#line - 3], everyone + 1000 - 3000)

print("\ngold line: this character")
local lineHere = GL:Line(bins, "character", "week", NOW)
check("nothing written down: not known", lineHere[1], false)
check("today is the purse now", lineHere[#lineHere], purse)
GL:NoteGold(42000, NOW - 2 * DAY)
lineHere = GL:Line(bins, "character", "week", NOW)
check("the bar after a reading shows it", lineHere[#lineHere - 1], 42000)
check("a bar before any reading is still not known", lineHere[#lineHere - 3], false)
local kept = GL:GetLog().goldByCharacter
check("kept by GUID", type(kept[key]), "table")

print("\ngold line: session")
GL:Record("loot", 500, NOW - 600)
local sessionBins = GL:Bins("session", nil, nil, NOW)
local sessionLine = GL:Line(sessionBins, "character", "session", NOW)
check("the first bar is before the loot", sessionLine[1], purse - 500)
check("the last bar is the purse", sessionLine[#sessionLine], purse)

print("\ngold line: a character known by name only")
key = "Ana-Realm A"
GL:NoteGold(1, NOW)
check("nothing written under a name", kept["Ana-Realm A"], nil)

GetMoney = nil
time, date = savedTime, savedDate
if failures > 0 then error(failures .. " failure(s)") end
print("\nall checks passed")
