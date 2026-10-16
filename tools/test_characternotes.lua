-- Logic/CharacterNotes.lua outside WoW, and what the Characters tab reads
-- from it through Recipes:GetCharacters.
--
-- What must hold:
--   1. Nothing is written while the character's GUID is unknown; once it
--      is, race, class, level, XP, rested, resting, zone and when seen go on
--      its own record.
--   2. Played time is asked only for a character never read, once, and the
--      game's answer is counted on from there; a kept time is never asked.
--   3. Rested grows for a character not playing (faster in an inn), tops
--      out at a level and a half, and says nothing at the level cap.
--   4. GetCharacters gives each character its side, notes and mail waiting.

local GLOBALS = { "time", "GetTime", "C_Timer", "UnitRace", "UnitClass", "UnitLevel", "UnitXP",
    "UnitXPMax", "GetXPExhaustion", "IsResting", "GetRealZoneText", "GetZoneText",
    "RequestTimePlayed", "GetMaxPlayerLevel", "GetMaxLevelForPlayerExpansion", "MAX_PLAYER_LEVEL" }
local saved = {}
for _, key in ipairs(GLOBALS) do saved[key] = _G[key] end

local passed, failed = 0, 0
local function check(name, got, want)
    if got == want then
        passed = passed + 1
        print(("  ok    %-52s %s"):format(name, tostring(got)))
    else
        failed = failed + 1
        print(("  FAIL  %-52s got %s, want %s"):format(name, tostring(got), tostring(want)))
    end
end

local now, clock = 1000000, 500
time = function() return now end
GetTime = function() return clock end
local timers = {}
C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end }
local function RunTimers()
    local list = timers
    timers = {}
    for _, fn in ipairs(list) do fn() end
end

local asked = 0
UnitRace = function() return "Orc" end
UnitClass = function() return "Mage", "MAGE" end
UnitLevel = function() return 20 end
UnitXP = function() return 3000 end
UnitXPMax = function() return 10000 end
GetXPExhaustion = function() return 5000 end
IsResting = function() return true end
GetRealZoneText = function() return "Durotar" end
GetZoneText = nil
RequestTimePlayed = function() asked = asked + 1 end
GetMaxLevelForPlayerExpansion = nil
GetMaxPlayerLevel = function() return 60 end

local ns = {}
ns.NewModule = function(name) local m = {} ns[name] = m return m end
local handlers = {}
ns.RegisterEvent = function(_, event, fn) handlers[event] = fn return true end

local record = {}
ns.Config = { characterKey = nil, GetCharacterKey = function(self) return self.characterKey end }
ns.Recipes = { GetCharacterRecord = function() return record end }

assert(loadfile(lfs_cwd .. "/Logic/CharacterNotes.lua"))("Blackthornes_TS", ns)
local Notes = ns.CharacterNotes

print("")
print("notes on the character playing")

handlers.PLAYER_ENTERING_WORLD()
check("no GUID yet: nothing written", record.zone, nil)

ns.Config.characterKey = "Player-1"
handlers.PLAYER_ENTERING_WORLD()
check("race", record.race, "Orc")
check("class file", record.classFile, "MAGE")
check("level", record.level, 20)
check("XP into the level", record.xp, 3000)
check("rested XP", record.restXP, 5000)
check("resting", record.resting, true)
check("zone", record.zone, "Durotar")
check("when seen", record.seenAt, now)

print("")
print("played time")

RunTimers()
check("never read: asked once", asked, 1)
handlers.TIME_PLAYED_MSG(nil, "TIME_PLAYED_MSG", 7200)
check("the answer is kept", record.played, 7200)
clock = clock + 600
Notes:Note()
check("and counted on while playing", record.played, 7800)
check("live for the character playing", Notes.Played(record, true), 7800)
handlers.PLAYER_ENTERING_WORLD()
RunTimers()
check("never asked again", asked, 1)

print("")
print("rested")

local alt = { level = 20, xpMax = 10000, restXP = 1000, seenAt = now, resting = true }
check("as last seen", Notes.Rested(alt, false, now), 10)
local grown, guess = Notes.Rested(alt, false, now + 8 * 3600)
check("in an inn, 5% every 8 hours", grown, 15)
check("and says it grew", guess, true)
alt.resting = false
check("outside, a quarter of that", Notes.Rested(alt, false, now + 8 * 3600), 11)
check("never past a level and a half", Notes.Rested(alt, false, now + 1000 * 86400), 150)
check("the character playing does not grow", Notes.Rested(alt, true, now + 8 * 3600), 10)
alt.level = 60
check("nothing at the level cap", Notes.Rested(alt, false, now), nil)
check("no XP bar at the cap", Notes.LevelShare(alt), nil)
check("XP into the level as a share", Notes.LevelShare({ level = 20, xp = 2500, xpMax = 10000 }), 0.25)
check("a record without notes says nothing", Notes.Rested({ level = 10 }, false, now), nil)

print("")
print("what the Characters tab reads")

-- Recipes:AddNotes on its own, as GetCharacters calls it.
local Recipes = {}
local source = assert(io.open(lfs_cwd .. "/Data/Recipes.lua")):read("*a")
local body = source:match("(local function Text%(value%).-\nend\n\n%-%-%- What the Characters tab.-\nend\n)")
assert(body, "AddNotes found")
local chunk = assert(loadstring("local ns, Recipes = ...\n" .. body))
chunk(ns, Recipes)

local entry = { isCurrent = false }
Recipes:AddNotes(entry, { faction = "Horde", race = "Orc", class = "Mage", classFile = "MAGE",
    level = 20, xp = 5000, xpMax = 10000, restXP = 2000, seenAt = now, zone = "Durotar",
    played = 3600, mail = { [2589] = 20, [2592] = 3 } })
check("side", entry.faction, "Horde")
check("race", entry.race, "Orc")
check("level share", entry.levelShare, 0.5)
check("rested", entry.rested, 20)
check("played", entry.played, 3600)
check("zone", entry.zone, "Durotar")
check("mail waiting, every item counted", entry.mailCount, 23)

local old = { isCurrent = false }
Recipes:AddNotes(old, { name = "Old", inventoryAt = now - 60 })
check("a record from before the notes: no side", old.faction, nil)
check("seen falls back to the last bag read", old.seenAt, now - 60)
check("and no rested", old.rested, nil)

for _, key in ipairs(GLOBALS) do _G[key] = saved[key] end

print("")
print(("%d passed, %d failed"):format(passed, failed))
assert(failed == 0, "character notes checks failed")
