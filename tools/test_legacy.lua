-- Legacy perks, read only (2026-10-22): the config is found through
-- C_Traits, Master Chef's rank raises a cooking recipe's yield for the
-- character playing, and nothing read leaves everything as it was.

local GLOBALS = { "C_Traits", "C_ClassTalents", "C_Spell", "C_CurrencyInfo", "C_Timer", "Enum", "C_TooltipInfo" }
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
local CHEF, OVERTIME = 110289, 110284
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
C_Spell = {
    GetSpellName = function() return "Working Overtime" end,
    GetSpellDescription = function(id) if id == 1225459 then return "Reduces vendor prices by 10%." end end,
    RequestLoadSpellData = noop,
}
C_TooltipInfo = {
    GetTraitEntry = function(entryID, rank)
        if entryID == OVERTIME + 1 then
            return { lines = { { leftText = "Working Overtime" }, { leftText = "Rank " .. rank .. "/5" },
                { leftText = "|cffffffffSkill up chance +" .. (2 * rank) .. "%|r" } } }
        end
    end,
}
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
check("Master Chef is found by its node", Legacy:MasterChefNode(), CHEF)
check("rank 3 of 5 gives 30% more", Legacy:CookingYield(), 1.3)
ranks[CHEF] = 5
Legacy:Changed()
check("a trait event reads it again: 50% at 5", Legacy:CookingYield(), 1.5)
check("Working Overtime found by its English name: 5 ranks add 20%", math.abs(Legacy:SkillUpBonus() - 0.2) < 1e-9, true)
check("no Performance Bonus spent: no favor bonus", Legacy:FavorBonus(), 0)
local lines = Legacy:ProbeLines()
local found = {}
for _, line in ipairs(lines) do found[line[1]] = (found[line[1]] or 0) + 1 end
check("the probe names the config", found["legacy"], 1)
check("the probe lists both nodes", found["legacy node"], 2)
check("the probe says the points left", found["legacy points"], 1)
check("the probe reads both currencies", (found["legacy currency 3485"] or 0) + (found["legacy currency 3499"] or 0), 2)
local text = {}
for _, line in ipairs(lines) do text[line[1]] = line[2] end
check("rank 1 words come from the tooltip", text["legacy perk 110284 rank 1"], "Rank 1/5 / Skill up chance +2%")
check("the last rank is read too", text["legacy perk 110284 rank 5"], "Rank 5/5 / Skill up chance +10%")
check("a rank in between", text["legacy perk 110284 rank 2"] ~= nil, true)
check("no tooltip says so", text["legacy perk 110289 rank 1"], "tooltip not given")
check("a perk not in the config is read by spell ID", text["legacy spell 1225459"], "Bartering: Reduces vendor prices by 10%.")
check("a spell with no words yet says so", text["legacy spell 1225501"], "For Great Honor: no words yet, run the probe again")
check("nothing was ever spent", purchases, 0)

print("")
print("perks found by spell ID, in any language")
do
    -- The live client's IDs, with names a German client might give: found by
    -- spell ID, never by the English name.
    local REAL = { [110290] = { 1225451, "Überstunden", 3 }, [110292] = { 1225456, "Leistungsprämie", 2 },
        [110289] = { 1225457, "Meisterkoch", 0 } }
    local saveNodes, saveInfo, saveEntry, saveDef = C_Traits.GetTreeNodes, C_Traits.GetNodeInfo,
        C_Traits.GetEntryInfo, C_Traits.GetDefinitionInfo
    C_Traits.GetTreeNodes = function() return { 110289, 110290, 110292 } end
    C_Traits.GetNodeInfo = function(configID, nodeID)
        local real = REAL[nodeID]
        if configID ~= 42 or not real then return { ID = 0 } end
        return { ID = nodeID, ranksPurchased = real[3], maxRanks = nodeID == 110292 and 3 or 5, entryIDs = { nodeID } }
    end
    C_Traits.GetEntryInfo = function(_, entryID) return { definitionID = entryID } end
    C_Traits.GetDefinitionInfo = function(id) return { spellID = REAL[id][1], overrideName = REAL[id][2] } end
    Legacy:Changed()
    check("Working Overtime found by spell", Legacy:PerkNode("workingOvertime"), 110290)
    check("3 ranks of Working Overtime add 12%", math.abs(Legacy:SkillUpBonus() - 0.12) < 1e-9, true)
    check("2 ranks of Performance Bonus give a 10% chance", math.abs(Legacy:FavorBonus() - 0.10) < 1e-9, true)
    check("Master Chef with no ranks spent: cooking as before", Legacy:CookingYield(), 1)
    REAL[110290][3] = 5
    check("kept until a trait event", math.abs(Legacy:SkillUpBonus() - 0.12) < 1e-9, true)
    Legacy:Changed()
    check("a trait event reads 5 ranks: 20%", math.abs(Legacy:SkillUpBonus() - 0.2) < 1e-9, true)
    REAL[110290][3] = 0
    Legacy:Changed()
    check("ranks taken back out: no bonus", Legacy:SkillUpBonus(), 0)
    check("nothing was ever spent here", purchases, 0)
    C_Traits.GetTreeNodes, C_Traits.GetNodeInfo, C_Traits.GetEntryInfo, C_Traits.GetDefinitionInfo =
        saveNodes, saveInfo, saveEntry, saveDef
    Legacy:Changed()
end

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
check("no C_Traits: no skill up bonus", Legacy:SkillUpBonus(), 0)
check("no C_Traits: no favor bonus", Legacy:FavorBonus(), 0)
check("and so is the cost", ns.Cost:GetCraftCost(9).yield, 1)

for _, key in ipairs(GLOBALS) do _G[key] = saved[key] end

print("")
print(("%d passed, %d failed"):format(passed, failed))
assert(failed == 0, "legacy checks failed")
