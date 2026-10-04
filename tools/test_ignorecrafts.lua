-- Ignoring a craft on the Profit tab (2026-10-03: "permanently add a
-- profit listed craft to ignore so it no longer appears in the recommended
-- list").
--
-- What must hold:
--   * an ignored craft is left out of the ranked list, so out of the rows,
--     Queue All and the empty-list message too;
--   * it is kept by recipe for the whole account, with its name, so Settings
--     can list it A to Z;
--   * Restore puts it back, and nothing else in the saved data is touched;
--   * Reset to defaults (Config.DEFAULTS.settings) never clears the list.

local ns = {}
ns.COLORS = setmetatable({}, { __index = function() return "ffffffff" end })
ns.NewModule = function(name) local m = {}; ns[name] = m; return m end
ns.RegisterCommand = function() end
ns.RegisterEvent = function() end
ns.Print, ns.PrintRaw, ns.Debug, ns.Warn =
    function() end, function() end, function() end, function() end

-- Globals this suite sets are put back at the end: every suite shares one Lua
-- runtime, and a stub C_Item left behind would answer for the next file.
local saved = { C_Item = C_Item, GetTime = GetTime }

GetTime = function() return 1 end
time = time or os.time

-- itemID -> bindType, the fourteenth return of GetItemInfo. Absent means the
-- client has not cached the item, and GetItemInfo returns nothing at all.
local bindTypes = {
    [100] = 1,  -- bind on pickup
    [200] = 2,  -- bind on equip
    [300] = 3,  -- bind on use
    [400] = 4,  -- quest item
    [500] = 0,  -- no binding
}

C_Item = {
    GetItemInfo = function(itemID)
        local bindType = bindTypes[itemID]
        if bindType == nil then return nil end
        return "item" .. itemID, nil, 2, 10, 10, "Armor", "Cloth", 1, "", 1, 50,
            4, 1, bindType
    end,
}

assert(loadfile(lfs_cwd .. "/Core/Util.lua"))("Blackthornes_TS", ns)

local Util = ns.Util

-- Every recipe makes something priced to clear any minimum comfortably.
local recipes = {}
for _, itemID in ipairs({ 100, 200, 300, 400, 500, 600 }) do
    recipes[itemID] = { recipeID = itemID, name = "craft" .. itemID, outputItemID = itemID,
                        reagents = {}, quantityMin = 1 }
end

ns.Config = {
    Get = function(_, key)
        if key == "minProfit" then return 50 end
        if key == "auctionCut" then return 0.05 end
        return nil
    end,
    GetCharacterKey = function() return "Tester-Realm" end,
}
ns.Recipes = {
    GetAll = function() return recipes end,
    GetAny = function(_, recipeID) return recipes[recipeID], "Tester-Realm" end,
    GetCharacterName = function() return "Tester" end,
}
ns.Cost = {
    GetCraftCost = function() return { priceable = true, total = 100, perUnit = 100, yield = 1 } end,
    FindRecipeForItem = function(_, itemID) return itemID end,
    FindAnyRecipeForItem = function(_, itemID) return itemID end,
}
ns.Prices = {
    GetValue = function() return 10000 end,
    Get = function() return { min = 10000 } end,
    HoldsLowest = function() return false end,
    GetConfidence = function() return 1 end,
    GetLiquidity = function() return nil end,
    IsStale = function() return false end,
    GetAge = function() return 0 end,
}
ns.Scanner = { GetCommodityStatus = function() return true end }
ns.Posting = { GetCachedUnitDeposit = function() return nil end }
ns.Auctions = { GetRoom = function() return nil, 0, 0, 0, nil, 0 end }
ns.Inventory = { GetCharacterBagCount = function() return 0 end }

assert(loadfile(lfs_cwd .. "/Logic/SkillUp.lua"))("Blackthornes_TS", ns)
assert(loadfile(lfs_cwd .. "/Logic/Profit.lua"))("Blackthornes_TS", ns)

-- Every craft is orange, so every craft that pays would earn a star.
ns.SkillUp.GetForRecipe = function() return { tier = "optimal" } end

local Profit = ns.Profit

local refreshed = 0
ns.UI = { RefreshActiveTab = function() refreshed = refreshed + 1 end }
ns.db = { postLimits = { [500] = 3 } }

local checks = 0
local function check(label, condition)
    checks = checks + 1
    if not condition then error(("FAILED: %s"):format(label), 2) end
    print(("  ok  %s"):format(label))
end

local function ids(list)
    local seen = {}
    for _, analysis in ipairs(list) do seen[analysis.recipeID] = true end
    return seen
end

print("\nignoring a craft")

check("nothing is ignored to start with", not Profit:IsIgnored(200) and #Profit:GetIgnored() == 0)
check("the craft is on the list", ids(Profit:GetRanked({}))[200] == true)

Profit:SetIgnored(200, true, "Wool Bandage")
check("it reads as ignored", Profit:IsIgnored(200))
check("the tab was redrawn", refreshed == 1)
local ranked = ids(Profit:GetRanked({}))
check("it is gone from the list", not ranked[200])
check("and nothing else went with it", ranked[300] and ranked[500] and ranked[600])
check("nor does a zero minimum bring it back (the empty-list message)",
    not ids(Profit:GetRanked({ minProfit = 0, minMargin = 0 }))[200])
check("includeIgnored still sees it", ids(Profit:GetRanked({ includeIgnored = true }))[200] == true)
check("it is still analysed on its own", Profit:Analyse(200) ~= nil)

Profit:SetIgnored(500, true)
check("a craft ignored without a name takes the recipe's", ns.db.ignoredCrafts[500] == "craft500")
Profit:SetIgnored(999, true)
check("and one not known here still gets a name", ns.db.ignoredCrafts[999] == "recipe 999")

local list = Profit:GetIgnored()
check("Settings lists all three", #list == 3)
check("A to Z, whatever the case", list[1].name == "craft500" and list[2].name == "recipe 999"
    and list[3].name == "Wool Bandage")

print("\nbringing it back")

Profit:SetIgnored(200, false)
check("Restore takes it off the ignored list", not Profit:IsIgnored(200))
check("and it is back on the Profit list", ids(Profit:GetRanked({}))[200] == true)
check("the other ignored crafts stay ignored", Profit:IsIgnored(500) and Profit:IsIgnored(999))
check("the rest of the saved data is untouched", ns.db.postLimits[500] == 3)

print("\nsaved data")

local Config = {}
local configNs = { NewModule = function() return Config end, Util = Util,
    RegisterCommand = function() end, RegisterEvent = function() end }
assert(loadfile(lfs_cwd .. "/Core/Config.lua"))("Blackthornes_TS", configNs)
check("a fresh database starts with an empty list", type(Config.DEFAULTS.ignoredCrafts) == "table"
    and next(Config.DEFAULTS.ignoredCrafts) == nil)
check("it is not a setting, so Reset to defaults leaves it alone",
    Config.DEFAULTS.settings.ignoredCrafts == nil)

C_Item, GetTime = saved.C_Item, saved.GetTime

print(("\n%d check(s) passed\n"):format(checks))
