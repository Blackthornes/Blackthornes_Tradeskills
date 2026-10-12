-- One record per character (2026-10-11).
--
-- An old "Name-Realm" record left beside the GUID record of the same
-- character was read as a second character: Butler filled a mail to the
-- character the player was on, and told one to mail Medium Leather to
-- itself. What must hold:
--   1. At login the old record is folded away: `characters` has the
--      character once, and the old record is kept whole in
--      `formerCharacters`, never deleted.
--   2. When it was stamped with this GUID, what the GUID record lacks is
--      filled from it, and the queue's references to the old key follow.
--   3. An old record that is somebody else's (another GUID, class, side or
--      last name) is left where it is.
--   4. A /reload where the game will not hand over the GUID still files
--      everything under it (this character's own file remembers it).
--   5. Characters:Same and Characters:IsPlaying, the one test everything
--      asks, see a retired key as the character it went into.

local player = {}

UnitName = function() return player.name end
UnitGUID = function() return player.guid end
UnitClass = function() return player.class, player.class:upper() end
UnitLevel = function() return player.level end
UnitFactionGroup = function() return "Horde" end
GetRealmName = function() return "Forever PvE" end
time = function() return 1000 end

local failures = 0
local function Check(name, ok, detail)
    print(string.format("  %-60s %s", name, ok and "ok" or ("FAIL " .. tostring(detail))))
    if not ok then failures = failures + 1 end
end

local function Load(db, charDb)
    local ns = {}
    ns.NewModule = function(name) local m = { moduleName = name } ns[name] = m return m end
    ns.RegisterCommand = function() end
    ns.RegisterEvent = function() end
    ns.Warn = function() end
    ns.Print = function() end
    ns.PrintRaw = function() end
    ns.Debug = function() end
    ns.COLORS = {}
    ns.Util = {
        Count = function(t) local n = 0 for _ in pairs(t or {}) do n = n + 1 end return n end,
        CopyDeep = function(t) return t end,
    }
    ns.Cost = { InvalidateIndex = function() end }
    ns.Compat = { Get = function() return { tradeskill = {} } end }

    loadfile("Core/Config.lua")("Blackthornes_TS", ns)
    loadfile("Core/Characters.lua")("Blackthornes_TS", ns)
    loadfile("Data/Recipes.lua")("Blackthornes_TS", ns)
    ns.db = db
    ns.charDb = charDb
    return ns
end

local function Login(db, who, charDb)
    for k, v in pairs(who) do player[k] = v end
    local ns = Load(db, charDb or {})
    ns.Recipes:GetCharacterRecord(true)
    return ns
end

local function Count(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end

local ANA = { name = "Ana", guid = "Player-1-00A", class = "Mage", level = 30 }
local LEGACY = "Ana-Forever PvE"

print("an old record beside the GUID one")
local mine = { name = "Ana", surname = "Blackthorne", realm = "Forever PvE", faction = "Horde",
    class = "Mage", guid = ANA.guid, recipes = { [1] = { name = "Bolt" } }, inventory = { [2318] = 4 } }
local old = { name = "Ana", realm = "Forever PvE", guid = ANA.guid, recipes = {}, inventory = { [2318] = 80 },
    bank = { [2319] = 20 }, bankAt = 900 }
local db = {
    characters = { [ANA.guid] = mine, [LEGACY] = old },
    queue = {
        { recipeID = 10, crafter = LEGACY, owner = LEGACY, forCharacters = { [LEGACY] = true } },
        { recipeID = 11, crafter = "Player-1-00B" },
    },
    queueBuys = { { itemID = 5, owner = LEGACY } },
}
local ns = Login(db, ANA)
Check("the character is keyed by its GUID", ns.Config:GetCharacterKey() == ANA.guid)
Check("characters holds it once", Count(db.characters) == 1 and db.characters[LEGACY] == nil, Count(db.characters))
Check("its record is the GUID one", db.characters[ANA.guid] == mine)
Check("the old record is kept whole, not deleted", db.formerCharacters and db.formerCharacters[LEGACY] == old
    and old.inventory[2318] == 80)
Check("and says where it went", old.retiredInto == ANA.guid)
Check("what the GUID record lacked is filled in", mine.bank and mine.bank[2319] == 20 and mine.bankAt == 900)
Check("what it had is not overwritten", mine.inventory[2318] == 4 and mine.recipes[1] ~= nil)
Check("the queue's crafter follows", db.queue[1].crafter == ANA.guid, db.queue[1].crafter)
Check("so does who queued it", db.queue[1].owner == ANA.guid, db.queue[1].owner)
Check("and who it is for", db.queue[1].forCharacters[ANA.guid] == true and db.queue[1].forCharacters[LEGACY] == nil)
Check("another character's entry is untouched", db.queue[2].crafter == "Player-1-00B")
Check("the buy list follows", db.queueBuys[1].owner == ANA.guid)
Check("the Characters tab lists one Ana", #ns.Recipes:GetCharacters() == 1, #ns.Recipes:GetCharacters())
Check("the old key reads as the character", ns.Characters:Canonical(LEGACY) == ANA.guid)
Check("and is the character playing", ns.Characters:IsPlaying(LEGACY) == true)
Check("named in full", ns.Recipes:GetCharacterName(LEGACY) == "Ana Blackthorne", ns.Recipes:GetCharacterName(LEGACY))

ns = Login(db, ANA)
Check("logging in again changes nothing", Count(db.characters) == 1 and Count(db.formerCharacters) == 1)

print("an old record with no GUID on it")
local mine2 = { name = "Ana", realm = "Forever PvE", faction = "Horde", class = "Mage", guid = ANA.guid, recipes = {} }
local old2 = { name = "Ana", realm = "Forever PvE", recipes = { [7] = { name = "Old" } } }
local db2 = { characters = { [ANA.guid] = mine2, [LEGACY] = old2 } }
ns = Login(db2, ANA)
Check("is folded away too", db2.characters[LEGACY] == nil and db2.formerCharacters[LEGACY] == old2)
Check("but nothing of it is copied, it may be another Ana's", mine2.recipes[7] == nil)

print("somebody else's old record")
local function Kept(other, label)
    local db3 = { characters = { [ANA.guid] = { name = "Ana", realm = "Forever PvE", faction = "Horde",
        class = "Mage", surname = "Blackthorne", guid = ANA.guid, recipes = {} }, [LEGACY] = other } }
    Login(db3, ANA)
    Check(label, db3.characters[LEGACY] == other and db3.formerCharacters == nil)
end
Kept({ name = "Ana", guid = "Player-1-0FF", recipes = {} }, "one stamped with another GUID stays")
Kept({ name = "Ana", class = "Warrior", recipes = {} }, "one of another class stays")
Kept({ name = "Ana", surname = "Stone", recipes = {} }, "one with another last name stays")
Kept({ name = "Ana", linkedFrom = "Player-9", recipes = {} }, "another account's copy stays")

print("a reload where the GUID cannot be read")
local charDb = {}
local db4 = { characters = {} }
Login(db4, ANA, charDb)
Check("the GUID is remembered in this character's file", charDb.guid == ANA.guid)
player.guid = nil
ns = Login(db4, { guid = false }, charDb)
player.guid = nil
Check("the key is still the GUID", ns.Config:GetCharacterKey() == ANA.guid, ns.Config:GetCharacterKey())
Check("and no old-style record is made", db4.characters[LEGACY] == nil and Count(db4.characters) == 1)
player.guid = ANA.guid

print("an old record saved under the whole name")
-- 2026-10-12: "Ana Blackthorne (saved before last names): 2 in bags" was on
-- the tooltip of the character playing, counted under "On other characters".
local mine6 = { name = "Ana", surname = "Blackthorne", realm = "Forever PvE", faction = "Horde",
    class = "Mage", guid = ANA.guid, recipes = {}, inventory = {} }
local whole = { name = "Ana Blackthorne", realm = "Forever PvE", recipes = {}, inventory = { [929] = 2 } }
local odd = { name = "Ana", recipes = {}, inventory = { [929] = 5 } }
local bob = { name = "Bob", realm = "Forever PvE", recipes = {}, inventory = { [929] = 3 } }
local other = { name = "Ana Stone", realm = "Forever PvE", recipes = {}, inventory = { [929] = 4 } }
local db6 = { characters = { [ANA.guid] = mine6, ["Ana Blackthorne-Forever PvE"] = whole,
    ["Ana-Forever"] = odd, ["Bob-Forever PvE"] = bob, ["Ana Stone-Forever PvE"] = other },
    queue = { { recipeID = 12, crafter = "Ana Blackthorne-Forever PvE" } } }
ns = Login(db6, ANA)
Check("is folded away", db6.characters["Ana Blackthorne-Forever PvE"] == nil
    and db6.formerCharacters["Ana Blackthorne-Forever PvE"] == whole)
Check("so is one under a key the legacy one no longer matches", db6.characters["Ana-Forever"] == nil
    and db6.formerCharacters["Ana-Forever"] == odd)
Check("and the queue follows", db6.queue[1].crafter == ANA.guid, db6.queue[1].crafter)
Check("Bob stays", db6.characters["Bob-Forever PvE"] == bob)
Check("another Ana with another last name stays", db6.characters["Ana Stone-Forever PvE"] == other)
Check("old records read as the character playing", ns.Characters:IsPlaying("Ana Blackthorne-Forever PvE")
    and ns.Characters:IsPlaying("Ana-Forever"))

print("the one test")
local db5 = { characters = {
    ["Player-1-00A"] = { name = "Ana", surname = "Blackthorne", realm = "R", faction = "Horde", guid = "Player-1-00A" },
    ["Player-1-00B"] = { name = "Ana", surname = "Stone", realm = "R", faction = "Horde", guid = "Player-1-00B" },
    ["Ana-R"] = { name = "Ana", realm = "R", faction = "Horde" },
    ["Bob-R"] = { name = "Bob", realm = "R", faction = "Horde" },
} }
ns = Load(db5, {})
ns.Config.characterKey = "Player-1-00A"
local C = ns.Characters
Check("two GUID keys are two characters", not C:Same("Player-1-00A", "Player-1-00B"))
Check("an old record of the first name is the character playing", C:IsPlaying("Ana-R"))
Check("another first name is not", not C:IsPlaying("Bob-R"))
Check("another Ana is not", not C:IsPlaying("Player-1-00B"))
Check("nil is nobody", not C:IsPlaying(nil) and not C:Same(nil, nil))

if failures > 0 then error(("%d check(s) failed"):format(failures)) end
print("one character: all checks passed")
