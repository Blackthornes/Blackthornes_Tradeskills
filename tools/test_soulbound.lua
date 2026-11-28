-- Crafts whose output binds on pickup are not recommended for sale.
--
-- Asked 2026-09-23: "soulbound items cannot be sold on the AH so they should
-- not be recommended to craft to sell". A bind-on-pickup item is soulbound the
-- moment it is made, so any profit the Profit tab showed for one was revenue
-- that could never arrive, and a skill-up star on it said "this pays" about
-- something that cannot be sold at all.
--
-- What this pins down:
--   * bind on pickup and quest items are left out of the AH-ranked list and the
--     star, and say why;
--   * bind on equip and bind on use still sell, so they stay;
--   * an item the client has not cached yet stays too -- dropping a craft on
--     a guess would hide one that may well sell;
--   * "Show unpriced" still lists a soulbound craft, with its skill-up tier,
--     for anyone levelling on it.
--   * under Best, Vendor, DE and Vendor and DE a soulbound craft is ranked
--     by vendor or disenchant, whichever pays more (2026-11-17).

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
    GetSalesPerDay = function() return nil end,
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

local checks = 0
local function check(label, condition)
    checks = checks + 1
    if not condition then error(("FAILED: %s"):format(label), 2) end
    print(("  ok  %s"):format(label))
end

print("\nreading the binding")

check("bind on pickup reads as bound", Util.IsBoundOnPickup(100) == true)
check("a quest item reads as bound", Util.IsBoundOnPickup(400) == true)
check("bind on equip does not", Util.IsBoundOnPickup(200) == false)
check("bind on use does not", Util.IsBoundOnPickup(300) == false)
check("no binding does not", Util.IsBoundOnPickup(500) == false)
check("an uncached item is unknown, not false", Util.IsBoundOnPickup(600) == nil)
check("and no item at all is unknown", Util.IsBoundOnPickup(nil) == nil)
check("the raw bindType comes back for /bts soulbound",
    select(2, Util.IsBoundOnPickup(100)) == 1)

print("\none craft")

local bop = Profit:Analyse(100)
check("a bind-on-pickup craft is not priceable", not bop.priceable)
check("it is marked soulbound", bop.soulbound == true)
check("and says why", bop.reason == "binds on pickup, so it cannot be sold")
check("it carries no profit to rank on", bop.profit == nil)
check("it wears no star", not bop.recommended)
check("but still knows it is a skill up", bop.skillUp and bop.skillUp.tier == "optimal")

local boe = Profit:Analyse(200)
check("a bind-on-equip craft is priced", boe.priceable == true)
check("and still earns its star", boe.recommended == true)

check("a quest-item craft is left out too", Profit:Analyse(400).soulbound == true)
check("an uncached craft is kept", Profit:Analyse(600).priceable == true)

print("\nthe Profit list")

local function ids(list)
    local seen = {}
    for _, analysis in ipairs(list) do seen[analysis.recipeID] = true end
    return seen
end

local ranked = ids(Profit:GetRanked({}))
check("bind on pickup is not in the list", not ranked[100])
check("nor is the quest item", not ranked[400])
check("bind on equip is", ranked[200] == true)
check("bind on use is", ranked[300] == true)
check("no binding is", ranked[500] == true)
check("an uncached output is", ranked[600] == true)

local withUnpriced = Profit:GetRanked({ includeUnpriceable = true })
local shown
for _, analysis in ipairs(withUnpriced) do
    if analysis.recipeID == 100 then shown = analysis end
end
check("Show unpriced still lists a soulbound craft", shown ~= nil)

-- Rows already on screen keep their places (Profit tab right-click to queue).
-- The order handed in is the reverse of the usual one, so a list that sorted
-- afresh would fail this.
local usual = Profit:GetRanked({})
local reversed = {}
for index, analysis in ipairs(usual) do reversed[analysis.recipeID] = #usual - index + 1 end
local held = Profit:GetRanked({ keepOrder = reversed })
check("rows on screen keep the order they were shown in", #usual > 1
    and held[1].recipeID == usual[#usual].recipeID and held[#held].recipeID == usual[1].recipeID)
check("with its skill-up tier for levelling on it", shown and shown.skillUp.tier == "optimal")

local starred = ids(ns.SkillUp:GetRecommended())
check("the star list leaves soulbound out", not starred[100] and not starred[400])
check("and keeps bind on equip", starred[200] == true)

-- Equal profit and the same name: the recipe ID decides, so the rows keep
-- their places from one redraw to the next rather than swapping.
local names = {}
for itemID, recipe in pairs(recipes) do names[itemID] = recipe.name; recipe.name = "Same Name" end
local tied = Profit:GetRanked({})
local inOrder = #tied > 1
for index = 2, #tied do
    if tied[index - 1].recipeID >= tied[index].recipeID then inOrder = false end
end
check("rows tied on profit and name go by recipe", inOrder)
for itemID, name in pairs(names) do recipes[itemID].name = name end

-- A soulbound craft can still go to a vendor or be disenchanted. Only the
-- auction house is out (Profit tab, a player's report, 2026-11-17).
print("\nsoulbound, vendored or disenchanted")

ns.Disenchant = {
    IsDisenchantable = function(_, itemID) return itemID == 100 end,
    GetValue = function() return 800, nil, { outcomes = {} } end,
    GetBestEnchanter = function() return 300 end,
    GetItemFacts = function() return { skill = 1 } end,
}

local best = Profit:Analyse(100, nil, "best")
check("under Best it is priced", best.priceable == true)
check("by disenchanting, which pays more than the vendor", best.via == "disenchant")
check("with the auction house left out", best.ways.auction == nil)
check("and still says it is soulbound", best.soulbound == true)
check("and its profit is the disenchant's", best.profit == 800 * 0.95 - 100)
check("and it earns its star when it pays", best.recommended == true)

local byVendor = Profit:Analyse(100, nil, "vendor")
check("under Vendor it is ranked at the vendor", byVendor.priceable == true
    and byVendor.via == "vendor" and byVendor.profit == 50 - 100)
check("a loss at the vendor wears no star", not byVendor.recommended)

local byDE = Profit:Analyse(100, nil, "disenchant")
check("under DE it is ranked by disenchanting", byDE.priceable == true and byDE.via == "disenchant")

local both = Profit:Analyse(100, nil, "vendordisenchant")
check("under Vendor and DE it takes the better", both.priceable == true and both.via == "disenchant")

local byAH = Profit:Analyse(100, nil, "auction")
check("under AH it stays unpriced", not byAH.priceable)
check("with the soulbound reason", byAH.reason == "binds on pickup, so it cannot be sold")

local sale = Profit:Analyse(100)
check("the sale the Sell tab would make stays out", not sale.priceable and sale.soulbound == true)

check("the Best list ranks it", ids(Profit:GetRanked({ method = "best" }))[100] == true)
check("the AH list does not", not ids(Profit:GetRanked({ method = "auction" }))[100])
check("the star list follows the Profit tab's choice", ids(ns.SkillUp:GetRecommended())[100] == true)

ns.Disenchant = nil

C_Item, GetTime = saved.C_Item, saved.GetTime

print(("\n%d check(s) passed\n"):format(checks))
