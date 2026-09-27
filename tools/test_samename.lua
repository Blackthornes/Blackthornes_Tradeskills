-- Forever lets characters share a first name; only first and last name
-- together are unique. The addon used to file characters as "Name-Realm", so
-- "Voldar Ash" and "Voldar Stone" were one character on the Characters tab.
-- Characters are now keyed by GUID, and the old record moves to the first
-- character that owns it without anything being deleted or merged.

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
    print(string.format("  %-52s %s", name, ok and "ok" or ("FAIL " .. tostring(detail))))
    if not ok then failures = failures + 1 end
end

local function Load(db)
    local ns = {}
    local modules = {}
    ns.NewModule = function(name) local m = { moduleName = name } modules[name] = m ns[name] = m return m end
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
    loadfile("Data/Recipes.lua")("Blackthornes_TS", ns)
    ns.db = db
    return ns
end

local function Login(db, who)
    for k, v in pairs(who) do player[k] = v end
    local ns = Load(db)
    ns.Recipes:GetCharacterRecord(true)
    return ns
end

local ASH = { name = "Voldar", guid = "Player-1-000A", class = "Mage", level = 40 }
local STONE = { name = "Voldar", guid = "Player-1-000B", class = "Warrior", level = 22 }

-- Saved data from before the fix: one shared record under the old key.
local legacyRecord = { name = "Voldar", realm = "Forever PvE", recipes = { [1] = { name = "Bolt" } }, gold = 500 }
local db = { characters = { ["Voldar-Forever PvE"] = legacyRecord } }

local ns = Login(db, ASH)
Check("first login keys the character by GUID", ns.Config:GetCharacterKey() == ASH.guid, ns.Config:GetCharacterKey())
Check("old record moved, not copied", db.characters[ASH.guid] == legacyRecord and db.characters["Voldar-Forever PvE"] == nil)
Check("old recipes and gold kept", legacyRecord.recipes[1] and legacyRecord.gold == 500)
Check("record stamped with its owner", legacyRecord.guid == ASH.guid, legacyRecord.guid)

ns = Login(db, STONE)
Check("second Voldar gets a record of its own", db.characters[STONE.guid] ~= nil and db.characters[STONE.guid] ~= legacyRecord)
Check("second Voldar does not inherit the first one's recipes", next(db.characters[STONE.guid].recipes) == nil)
Check("first Voldar's record untouched", db.characters[ASH.guid] == legacyRecord and legacyRecord.recipes[1] ~= nil)

local list = ns.Recipes:GetCharacters()
Check("Characters tab lists both", #list == 2, #list)
local names = {}
for _, entry in ipairs(list) do names[#names + 1] = entry.name end
Check("the two rows read differently", #list == 2 and list[1].name ~= list[2].name, table.concat(names, " | "))
Check("rows name level and class", (names[1] or ""):find("level 22 Warrior", 1, true) ~= nil, names[1])

-- A second login of the first character must not re-adopt anything.
ns = Login(db, ASH)
Check("logging back in finds the same record", ns.Config:GetCharacterKey() == ASH.guid and db.characters[ASH.guid] == legacyRecord)

-- An old record already claimed by someone else is left alone.
local claimed = { name = "Voldar", guid = "Player-1-000C", recipes = {} }
local db2 = { characters = { ["Voldar-Forever PvE"] = claimed } }
Login(db2, STONE)
Check("an old record claimed by another GUID stays put", db2.characters["Voldar-Forever PvE"] == claimed)

-- Last name found in a name the game returns.
player.fullName = nil
UnitFullName = function() return "Voldar Stone", "ForeverPvE" end
local db3 = { characters = {} }
ns = Login(db3, STONE)
Check("last name read from a full name", db3.characters[STONE.guid].surname == "Stone", db3.characters[STONE.guid].surname)
Check("display name includes the last name", ns.Recipes:GetCharacterName(STONE.guid) == "Voldar Stone", ns.Recipes:GetCharacterName(STONE.guid))
UnitFullName = nil

-- Before the game hands over a GUID, the old key is used and not remembered.
player.guid = nil
ns = Load({ characters = {} })
Check("no GUID yet: old key, not cached", ns.Config:GetCharacterKey() == "Voldar-Forever PvE" and ns.Config.characterKey == nil)

if failures > 0 then error(("%d check(s) failed"):format(failures)) end
