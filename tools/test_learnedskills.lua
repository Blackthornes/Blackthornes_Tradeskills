-- The character's profession levels, for Recipes to learn's SKILL colours.
--
-- A player saw the SKILL numbers lose their green and amber, then get them
-- back on their own (2026-10-09). Right after login or a loading screen the
-- client reads every profession as level 0, and Forever lists each one
-- twice, only one of the two carrying the levels. Now the listing that
-- carries them wins, and the last good read saved for the character fills
-- in while the client has none.

local checks = 0
local function check(label, condition)
    checks = checks + 1
    if not condition then error(("FAILED: %s"):format(label), 2) end
    print(("  ok  %s"):format(label))
end

UnitName = function() return "Ana" end
UnitGUID = function() return "Player-1-A" end
UnitClass = function() return "Mage", "MAGE" end
UnitLevel = function() return 30 end
UnitFactionGroup = function() return "Horde" end
GetRealmName = function() return "Forever PvE" end
time = time or os.time

-- Leatherworking under its classic ID (165) and its modern one (2958).
local lines = { 2958, 165 }
local levels = { [165] = { 175, 225 }, [2958] = { 0, 0 } }
C_TradeSkillUI = {
    GetAllProfessionTradeSkillLines = function() return lines end,
    GetProfessionInfoBySkillLineID = function(id)
        return { professionName = "Leatherworking", skillLevel = levels[id][1], maxSkillLevel = levels[id][2] }
    end,
}

local ns = {}
ns.NewModule = function(name) local m = {}; ns[name] = m; return m end
ns.RegisterCommand = function() end
ns.RegisterEvent = function() end
ns.Warn, ns.Print, ns.PrintRaw, ns.Debug = function() end, function() end, function() end, function() end
ns.COLORS = {}
ns.Util = {
    Count = function(t) local n = 0 for _ in pairs(t or {}) do n = n + 1 end return n end,
    CopyDeep = function(t) local c = {} for k, v in pairs(t) do c[k] = v end return c end,
}
ns.Compat = { Get = function() return { tradeskill = { hasAllProfessionLines = true } } end }

assert(loadfile(lfs_cwd .. "/Core/Config.lua"))("Blackthornes_TS", ns)
assert(loadfile(lfs_cwd .. "/Data/Recipes.lua"))("Blackthornes_TS", ns)

local SELF = "Player-1-A"
ns.db = { characters = { [SELF] = { name = "Ana", recipes = {}, inventory = {} } } }
ns.Config.characterKey = SELF
local Recipes = ns.Recipes

local function Level(name)
    for _, p in ipairs(Recipes:GetLearnedProfessions()) do
        if p.name == name then return p.skillLevel end
    end
end

print("\nthe listing with the levels wins")
check("listed second, still read", Level("Leatherworking") == 175)
lines = { 165, 2958 }
check("listed first, the same", Level("Leatherworking") == 175)
check("listed once", #Recipes:GetProfessions() == 1)

print("\nsaved for the character")
Recipes:RefreshProfessions()
check("the good read is kept", ns.db.characters[SELF].professions[1].skillLevel == 175)

print("\nskill levels not loaded yet")
levels[165] = { 0, 0 }
check("the saved level fills in", Level("Leatherworking") == 175)
Recipes:RefreshProfessions()
check("and the empty read does not replace it", Level("Leatherworking") == 175)

print("\nthe client has them again")
levels[165] = { 180, 225 }
check("the live level wins", Level("Leatherworking") == 180)

print("\nnothing saved and nothing loaded")
ns.db.characters[SELF].professions = nil
levels[165] = { 0, 0 }
check("no profession is made up", #Recipes:GetLearnedProfessions() == 0)

print(("\n%d checks passed"):format(checks))
