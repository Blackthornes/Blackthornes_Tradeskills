-- Legacy perks, read only (2026-10-22): the config is found through
-- C_Traits, Master Chef's rank raises a cooking recipe's yield for the
-- character playing, and nothing read leaves everything as it was.

local GLOBALS = { "C_Traits", "C_ClassTalents", "C_Spell", "C_CurrencyInfo", "C_Timer", "Enum" }
local saved = {}
for _, key in ipairs(GLOBALS) do saved[key] = _G[key] end

local passed, failed = 0, 0
local function check(label, got, want)
    local ok = got == want
    if ok then passed = passed + 1 else failed = failed + 1 end
    print(string.format("  %-58s %-10s %s", label, tostring(got), ok and "ok" or
        ("WRONG, wanted " .. tostring(want))))
end

local function noop() end
local ns = {}
ns.NewModule = function(name) local m = {}; ns[name] = m; return m end
ns.RegisterEvent = noop

-- Two configs: class talents (7) and Legacy (42), held by system 5.
local CHEF, OVERTIME = 110290, 110284
local ranks = { [CHEF] = 3, [OVERTIME] = 5 }
local purchases = 0
C_ClassTalents = { GetActiveConfigID = function() return 7 end }
C_Traits = {
    GetConfigIDBySystemID = function(id) if id == 5 then return 42 end if id == 1 then return 7 end end,
    GetConfigIDByTreeID = function() return nil end,
    GetConfigInfo = function(configID)
        if configID == 42 then return { ID = 42, name = "", treeIDs = { 900 } } end
        if configID == 7 then return { ID = 7, name = "Warrior", treeIDs = { 1 } } end
    end,
    GetTreeNodes = function(treeID)
        if treeID == 900 then return { CHEF, OVERTIME } end
        return { 500 }
    end,
    GetNodeInfo = function(configID, nodeID)
        if configID ~= 42 or not ranks[nodeID] then return { ID = 0 } end
        return { ID = nodeID, ranksPurchased = ranks[nodeID], maxRanks = 5, entryIDs = { nodeID + 1 } }
    end,
    GetEntryInfo = function(_, entryID) return { definitionID = entryID + 1 } end,
    GetDefinitionInfo = function(definitionID)
        return { spellID = definitionID, overrideName = definitionID == CHEF + 2 and "Master Chef" or "" }
    end,
    GetTreeCurrencyInfo = function() return { { traitCurrencyID = 77, quantity = 2, spent = 14 } } end,
    PurchaseRank = function() purchases = purchases + 1 end,
    CommitConfig = function() purchases = purchases + 1 end,
}
C_Spell = { GetSpellName = function() return "Working Overtime" end }
C_CurrencyInfo = { GetCurrencyInfo = function(id) return { name = "c" .. id, quantity = 1, maxQuantity = 10 } end }
C_Timer = nil
Enum = nil

assert(loadfile(lfs_cwd .. "/Logic/Legacy.lua"))("Blackthornes_TS", ns)
local Legacy = ns.Legacy

print("")
print("finding and reading the Legacy config")
Legacy:Search()
check("the Legacy config is found", Legacy.configID, 42)
check("class talents are never taken for it", Legacy:IsLegacy(7), false)
check("Master Chef is found by name", Legacy:MasterChefNode(), CHEF)
check("rank 3 of 5 gives 30% more", Legacy:CookingYield(), 1.3)
ranks[CHEF] = 5
Legacy:Changed()
check("a trait event reads it again: 50% at 5", Legacy:CookingYield(), 1.5)
local lines = Legacy:ProbeLines()
local found = {}
for _, line in ipairs(lines) do found[line[1]] = (found[line[1]] or 0) + 1 end
check("the probe names the config", found["legacy"], 1)
check("the probe lists both nodes", found["legacy node"], 2)
check("the probe says the points left", found["legacy points"], 1)
check("the probe reads both currencies", (found["legacy currency 3485"] or 0) + (found["legacy currency 3499"] or 0), 2)
check("nothing was ever spent", purchases, 0)

print("")
print("cooking yield in the cost")
local recipe = { recipeID = 9, skillLineID = 185, quantityMin = 1, quantityMax = 1, reagents = {} }
local other = { recipeID = 10, skillLineID = 197, quantityMin = 1, quantityMax = 1, reagents = {} }
local mine = { [9] = recipe, [10] = other }
ns.Recipes = {
    SKILL_LINE_PROFESSIONS = { [185] = "Cooking", [197] = "Tailoring" },
    Get = function(_, id) return mine[id] end,
    GetAny = function(_, id) return mine[id] or (id == 11 and recipe) end,
}
ns.Config = { Get = function() return true end }
ns.Inventory = { GetBagCount = function() return 0 end, GetBankCount = function() return 0 end }
assert(loadfile(lfs_cwd .. "/Logic/Cost.lua"))("Blackthornes_TS", ns)
check("a cooking recipe makes 1.5 at Master Chef 5", ns.Cost:GetCraftCost(9).yield, 1.5)
check("tailoring is left alone", ns.Cost:GetCraftCost(10).yield, 1)
mine[9] = nil
check("an alt's cooking is left alone", ns.Cost:GetCraftCost(11).yield, 1)
mine[9] = recipe

print("")
print("the later Legacy perks")
check("113508 is a Legacy node", Legacy:InRange(113508), true)
check("110319 still is", Legacy:InRange(110319), true)
check("110320 is not", Legacy:InRange(110320), false)
local wide = Legacy:RangeNodes()
check("the fallback list ends at 113513", wide[#wide], 113513)
local getInfo, getNodes = C_Traits.GetConfigInfo, C_Traits.GetTreeNodes
C_Traits.GetConfigInfo = function(configID)
    if configID == 43 then return { ID = 43, name = "", treeIDs = { 1188 } } end
    return getInfo(configID)
end
C_Traits.GetTreeNodes = function(treeID)
    if treeID == 1188 then return { 113510, 113511 } end
    return getNodes(treeID)
end
check("a tree with only later perks is Legacy", Legacy:IsLegacy(43), true)
C_Traits.GetConfigInfo, C_Traits.GetTreeNodes = getInfo, getNodes

print("")
print("nothing to read")
C_Traits = nil
Legacy.configID, Legacy.searched, Legacy.masterChefNode = nil, nil, nil
Legacy:Changed()
Legacy:Search()
check("no C_Traits: no config", Legacy.configID, nil)
check("no C_Traits: cooking is as before", Legacy:CookingYield(), 1)
check("and so is the cost", ns.Cost:GetCraftCost(9).yield, 1)

for _, key in ipairs(GLOBALS) do _G[key] = saved[key] end

print("")
print(("%d passed, %d failed"):format(passed, failed))
assert(failed == 0, "legacy checks failed")
