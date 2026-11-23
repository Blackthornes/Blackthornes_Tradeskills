-- The Sell list asks only what a craft cost to make.
--
-- Posting:GetPostable ran the whole of Profit:Analyse for every crafted
-- stack in the bags, twice a refresh, and read one number from it:
-- costPerUnit. Profit:UnitCostForSale gives that number alone. This pins
-- the two to the same answer in every case Analyse has, and counts that the
-- short way does none of the work the number does not need.

local ns = {}
ns.COLORS = setmetatable({}, { __index = function() return "ffffffff" end })
ns.NewModule = function(name) local m = {}; ns[name] = m; return m end
ns.RegisterCommand = function() end
ns.RegisterEvent = function() end
ns.Print, ns.PrintRaw, ns.Debug, ns.Warn =
    function() end, function() end, function() end, function() end

local saved = { C_Item = C_Item, GetTime = GetTime }
GetTime = function() return 1 end
time = time or os.time

-- itemID -> { bind type, what a vendor pays (the eleventh return) }.
local items = {
    [100] = { 1, 50 },   -- binds on pickup
    [200] = { 2, 50 },   -- sells, and a vendor buys it
    [300] = { 0, 0 },    -- sells, no vendor price
    [400] = { 0, 0 },    -- nothing prices it
    [500] = { 0, 50 },   -- a reagent has no price
    [600] = { 0, 50 },   -- nobody lists it, a vendor buys it
}

C_Item = {
    GetItemInfo = function(itemID)
        local item = items[itemID]
        if not item then return nil end
        return "item" .. itemID, nil, 2, 10, 10, "Armor", "Cloth", 1, "", 1, item[2], 4, 1, item[1]
    end,
}

assert(loadfile(lfs_cwd .. "/Core/Util.lua"))("Blackthornes_TS", ns)

local recipes = {}
for itemID in pairs(items) do
    recipes[itemID] = { recipeID = itemID, name = "craft" .. itemID, outputItemID = itemID,
                        reagents = {}, quantityMin = 1 }
end
-- An enchant: it makes nothing to sell.
recipes[700] = { recipeID = 700, name = "enchant", reagents = {} }

ns.Config = {
    Get = function(_, key)
        if key == "auctionCut" then return 0.05 end
        if key == "priceUnscannedCrafts" then return false end
        return nil
    end,
    GetCharacterKey = function() return "Tester-Realm" end,
}
ns.Recipes = {
    GetAll = function() return recipes end,
    GetAny = function(_, recipeID) return recipes[recipeID], "Tester-Realm" end,
    GetCharacterName = function() return "Tester" end,
}

local costed = 0
ns.Cost = {
    GetCraftCost = function(_, recipeID)
        costed = costed + 1
        if recipeID == 500 then return { priceable = false, unpriced = { 1 } } end
        return { recipeID = recipeID, priceable = true, total = 120, perUnit = 60, yield = 2 }
    end,
    FindRecipeForItem = function(_, itemID) return itemID end,
    FindAnyRecipeForItem = function(_, itemID) return itemID end,
}

local priced = { [100] = true, [200] = true, [300] = true, [500] = true }
ns.Prices = {
    GetValue = function(_, itemID) return priced[itemID] and 10000 or nil end,
    GetScanValue = function(_, itemID) return priced[itemID] and 10000 or nil end,
    Get = function(_, itemID) return priced[itemID] and { min = 10000 } or nil end,
    HoldsLowest = function() return false end,
    GetConfidence = function() return 1 end,
    GetSalesPerDay = function() return nil end,
    IsStale = function() return false end,
    GetAge = function() return 0 end,
    IsCredible = function() return true end,
}
ns.Scanner = { GetCommodityStatus = function() return true end, IsCommodity = function() return true end }
ns.Posting = { GetCachedUnitDeposit = function() return nil end }

local rooms, skills, breaks = 0, 0, 0
ns.Auctions = { GetRoom = function() rooms = rooms + 1; return nil, 0, 0, 0, nil, 0 end }
ns.Inventory = { GetCharacterBagCount = function() return 0 end }
ns.Disenchant = {
    IsDisenchantable = function() breaks = breaks + 1; return false end,
    GetValue = function() return nil end,
}

assert(loadfile(lfs_cwd .. "/Logic/SkillUp.lua"))("Blackthornes_TS", ns)
assert(loadfile(lfs_cwd .. "/Logic/Profit.lua"))("Blackthornes_TS", ns)
ns.SkillUp.GetForRecipe = function() skills = skills + 1; return nil end

local Profit = ns.Profit

local checks = 0
local function check(label, condition)
    checks = checks + 1
    if not condition then error(("FAILED: %s"):format(label), 2) end
    print(("  ok  %s"):format(label))
end

print("\nthe same number as the whole analysis")

local names = {
    [100] = "a craft that binds on pickup",
    [200] = "a craft that sells and a vendor buys",
    [300] = "a craft that sells with no vendor price",
    [400] = "a craft nothing prices",
    [500] = "a craft with an unpriced reagent",
    [600] = "a craft only a vendor prices",
    [700] = "an enchant",
    [999] = "a recipe nobody knows",
}
for recipeID, name in pairs(names) do
    local analysis = Profit:Analyse(recipeID)
    local whole = analysis and analysis.costPerUnit
    check(name .. " costs the same both ways", Profit:UnitCostForSale(recipeID) == whole)
end

check("a craft that sells costs its share of the craft", Profit:UnitCostForSale(200) == 60)
check("one that binds on pickup has no cost to hold a listing to", Profit:UnitCostForSale(100) == nil)
check("one nothing prices has none", Profit:UnitCostForSale(400) == nil)
check("one with an unpriced reagent has none", Profit:UnitCostForSale(500) == nil)

print("\nonly the work the number needs")

costed, rooms, skills, breaks = 0, 0, 0, 0
Profit:UnitCostForSale(200)
check("the craft is costed once", costed == 1)
check("the stock is not read", rooms == 0)
check("the skill-up is not read", skills == 0)
check("disenchanting is not read", breaks == 0)

Profit:Analyse(200)
check("the whole analysis still reads them", rooms > 0 and skills > 0 and breaks > 0)

C_Item, GetTime = saved.C_Item, saved.GetTime

print(("\n%d checks passed"):format(checks))
