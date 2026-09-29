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

-- The account-wide file coming back emptier than this character remembers.
-- A fresh install's new character remembers nothing, so it never warns.
local savedChar = BlackthornesTSCharDB
BlackthornesTSCharDB = {}
ns.Config.accountDataLost = nil
ns.Config:CheckAccountDataLost({ probe = { loadCount = 1 } })
Check("a new character does not warn", ns.Config.accountDataLost == nil)
Check("and remembers the account file's sessions", BlackthornesTSCharDB.accountLoads == 1)

ns.Config:CheckAccountDataLost({ probe = { loadCount = 2 } })
Check("a normal login does not warn", ns.Config.accountDataLost == nil and BlackthornesTSCharDB.accountLoads == 2)

BlackthornesTSCharDB.accountLoads = 300
ns.Config:CheckAccountDataLost({ probe = { loadCount = 1 } })
Check("an account file that came back empty warns", ns.Config.accountDataLost ~= nil)
Check("and the character keeps what it remembered", BlackthornesTSCharDB.accountLoads == 300)

ns.Config.accountDataLost = nil
ns.Config:CheckAccountDataLost({ probe = { loadCount = 2 } })
Check("the next session still warns", ns.Config.accountDataLost ~= nil)

ns.Config.accountDataLost = nil
ns.Config:CheckAccountDataLost({ probe = { loadCount = 301 } })
Check("the restored file stops the warning", ns.Config.accountDataLost == nil)
BlackthornesTSCharDB = savedChar

-- A fresh install: neither saved file came back and there is no backup. That
-- is a welcome, not the saved data warning. Real loss keeps the warning.
local function Boot(accountDB, charDB)
    local booted = Load({})
    booted.Util.ApplyDefaults = function() end
    booted.Compat.Detect = function() return {} end
    local printed = {}
    booted.Print = function(text) printed[#printed + 1] = tostring(text) end
    booted.Warn = booted.Print
    booted.COLORS = { accent = "ffffffff" }
    BlackthornesTSDB, BlackthornesTSCharDB = accountDB, charDB
    booted.Config:Bootstrap()
    return booted, printed
end

local savedAccount = BlackthornesTSDB
local fresh, freshPrinted = Boot(nil, nil)
Check("a fresh install is a first run", fresh.Config:IsFirstRun() == true)
Check("and does not warn about lost data", fresh.Config.accountDataLost == nil)
fresh.Config:Welcome()
Check("the welcome is friendly", freshPrinted[1] ~= nil and freshPrinted[1]:find("welcome", 1, true) ~= nil
    and not freshPrinted[1]:find("did not load", 1, true), freshPrinted[1])

local lost = Boot(nil, { accountLoads = 40 })
Check("real loss is not a first run", lost.Config:IsFirstRun() == false)
Check("and still warns", lost.Config.accountDataLost ~= nil)

local normal = Boot({ probe = { loadCount = 5 } }, { accountLoads = 4 })
Check("a normal login is not a first run", normal.Config:IsFirstRun() == false)

-- The saved data arriving after load: it existed, so no welcome beside the
-- warning about it arriving late.
local late = Boot(nil, nil)
BlackthornesTSDB = { probe = { loadCount = 9 } }
late.Config:CheckLateSavedVariables()
Check("saved data that arrives late is not a first run", late.Config:IsFirstRun() == false)

-- Both saved files missing, but the CVar canary counts earlier logins: the
-- addon has run here before.
local savedCVar = C_CVar
C_CVar = {
    GetCVar = function() return "7" end,
    SetCVar = function() return true end,
    RegisterCVar = function() return true end,
}
local function BootWithCVars()
    local booted = Load({})
    booted.Util.ApplyDefaults = function() end
    booted.Compat.Detect = function() return { cvars = { roundTrip = true, registerVia = "RegisterCVar" } } end
    BlackthornesTSDB, BlackthornesTSCharDB = nil, nil
    booted.Config:Bootstrap()
    return booted
end
local seenBefore = BootWithCVars()
Check("a CVar canary from earlier logins is not a first run", seenBefore.Config:IsFirstRun() == false)
C_CVar.GetCVar = function() return nil end
local reallyNew = BootWithCVars()
Check("with no earlier count it still is", reallyNew.Config:IsFirstRun() == true)
C_CVar = savedCVar
BlackthornesTSDB, BlackthornesTSCharDB = savedAccount, savedChar

if failures > 0 then error(("%d check(s) failed"):format(failures)) end
