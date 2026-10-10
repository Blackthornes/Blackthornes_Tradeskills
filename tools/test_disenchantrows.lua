-- The Enchanting tab's craft list and the bags lists' rows, outside WoW.
--
-- What must hold:
--   1. A craft with a reagent that has no price still shows what it sells
--      for, so it is not counted as worth more disenchanted on that alone.
--   2. A craft's sale price is never under what a vendor pays, and a
--      vendor's price is labelled as one.
--   3. Crafts of a dropped profession are left out, as the Profit tab
--      leaves them out.
--   4. Each bag row carries the link of the first copy carried, for the
--      upgrade arrow; a link the client will not hand over leaves it off.

local GLOBALS = { "C_Item", "C_Container", "GetTime", "CreateFrame", "time" }
local saved = {}
for _, key in ipairs(GLOBALS) do saved[key] = _G[key] end

local ns = {}
ns.COLORS = setmetatable({}, { __index = function() return "ffffffff" end })
ns.NewModule = function(name) local m = {}; ns[name] = m; return m end
ns.RegisterCommand = function() end
ns.RegisterEvent = function() end
ns.Print, ns.PrintRaw, ns.Debug, ns.Warn =
    function() end, function() end, function() end, function() end

-- Core/Util.lua builds a worker frame at load time; it only has to exist.
CreateFrame = function()
    local frame = {}
    for _, name in ipairs({ "SetScript", "Show", "Hide", "SetPoint", "SetSize" }) do
        frame[name] = function() end
    end
    return frame
end

GetTime = function() return 1 end
time = os.time

local STRANGE_DUST, LESSER_ASTRAL, SMALL_GLIMMERING = 10940, 10998, 10978

-- itemID -> quality, itemLevel, equipLoc, classID, bindType, sellPrice
local items = {
    [1001] = { 2, 22, "INVTYPE_CHEST", 4, 2, 50 },    -- worth more disenchanted
    [1002] = { 2, 22, "INVTYPE_WEAPON", 2, 2, 50 },   -- a reagent has no price
    [1011] = { 2, 22, "INVTYPE_LEGS", 4, 2, 900 },    -- a vendor pays more than the auction house
    [1012] = { 2, 22, "INVTYPE_FEET", 4, 2, 50 },     -- from a dropped profession
}

C_Item = {
    GetItemInfo = function(itemID)
        local item = items[itemID]
        if not item then return nil end
        return "item" .. itemID, nil, item[1], item[2], 1, "Armor", "Cloth", 1,
            item[3], 1, item[6], item[4], 1, item[5]
    end,
}

local prices = {
    [STRANGE_DUST] = 160, [LESSER_ASTRAL] = 1000, [SMALL_GLIMMERING] = 2000,
    [1001] = 700, [1002] = 5000, [1011] = 300, [1012] = 700,
}

assert(loadfile(lfs_cwd .. "/Core/Util.lua"))("Blackthornes_TS", ns)

local recipes = {}
for _, itemID in ipairs({ 1001, 1002, 1011, 1012 }) do
    recipes[itemID] = { recipeID = itemID, name = "craft" .. itemID, outputItemID = itemID,
                        reagents = {}, quantityMin = 1, dropped = itemID == 1012 }
end

ns.Config = {
    Get = function(_, key)
        if key == "auctionCut" then return 0.05 end
        if key == "minProfit" then return 0 end
        return nil
    end,
    GetCharacterKey = function() return "Tester-Realm" end,
}
ns.Recipes = {
    GetAll = function() return recipes end,
    GetAny = function(_, recipeID) return recipes[recipeID], "Tester-Realm" end,
    GetCharacterName = function() return "Tester" end,
    Count = function() return 4 end,
    IsDropped = function(_, recipe) return recipe.dropped == true end,
}
ns.Cost = {
    GetCraftCost = function(_, recipeID)
        if recipeID == 1002 then
            return { recipeID = recipeID, priceable = false, unpriced = { 2589 }, yield = 1 }
        end
        return { recipeID = recipeID, priceable = true, total = 100, perUnit = 100, yield = 1 }
    end,
    FindRecipeForItem = function(_, itemID) return itemID end,
    GetMaterialValue = function() return nil end,
}
ns.Prices = {
    GetValue = function(_, itemID) return prices[itemID] end,
    Get = function(_, itemID) return prices[itemID] and { min = prices[itemID] } or nil end,
    HoldsLowest = function() return false end,
    GetConfidence = function() return 1 end,
    GetLiquidity = function() return nil end,
    IsStale = function() return false end,
    GetAge = function() return 0 end,
}
ns.Scanner = { GetCommodityStatus = function() return true end }
ns.Posting = { GetCachedUnitDeposit = function() return nil end }
ns.Auctions = { GetRoom = function() return nil, 0, 0, 0, nil, 0 end }

-- Bag 0: the chest twice, as two different copies, and the weapon. The
-- client will not hand over the link in slot 9.
local LINKS = {
    [2] = "|cff1eff00|Hitem:1001::::::-12:1:60|h[item1001 of the Monkey]|h|r",
    [5] = "|cff1eff00|Hitem:1002::::::-7:1:60|h[item1002 of the Bear]|h|r",
    [7] = "|cff1eff00|Hitem:1001::::::-19:1:60|h[item1001 of the Eagle]|h|r",
    [9] = "secret",
}
local slots = { [2] = 1001, [5] = 1002, [7] = 1001, [9] = 1011 }
C_Container = {
    GetContainerNumSlots = function(bag) return bag == 0 and 12 or 0 end,
    GetContainerItemID = function(bag, slot) return bag == 0 and slots[slot] or nil end,
    GetContainerItemLink = function(bag, slot)
        if bag ~= 0 then return nil end
        if LINKS[slot] == "secret" then error("secret value") end
        return LINKS[slot]
    end,
}

local bags = { [1001] = 2, [1002] = 1, [1011] = 1 }
ns.Inventory = {
    GetCharacterBagCount = function() return 0 end,
    GetBagCounts = function() return bags end,
    GetBagCount = function(_, itemID) return bags[itemID] or 0 end,
    GetCarriedBags = function() return { 0, 1, 2, 3, 4 } end,
}

assert(loadfile(lfs_cwd .. "/Logic/SkillUp.lua"))("Blackthornes_TS", ns)
assert(loadfile(lfs_cwd .. "/Logic/Disenchant.lua"))("Blackthornes_TS", ns)
assert(loadfile(lfs_cwd .. "/Logic/Profit.lua"))("Blackthornes_TS", ns)

ns.SkillUp.GetForRecipe = function() return nil end

local Disenchant, Profit = ns.Disenchant, ns.Profit

local checks = 0
local function check(label, condition)
    checks = checks + 1
    if not condition then error(("FAILED: %s"):format(label), 2) end
    print(("  ok  %s"):format(label))
end

local function CraftRows(beatsOnly)
    local byID = {}
    for _, row in ipairs(Disenchant:GetCraftRows({ beatsOnly = beatsOnly })) do byID[row.itemID] = row end
    return byID
end

print("\na craft with a reagent that has no price")

local analysis = Profit:Analyse(1002)
check("the Profit tab has no sale price for it", analysis.unitRevenue == nil
    and analysis.reason == "a reagent has no price data")

local crafts = CraftRows(false)
-- Undercut by a copper from the 5000 rival listing, as the Sell tab would.
check("the craft list still shows what it sells for", crafts[1002].sells == 4999
    and crafts[1002].sellsAt == "auction")
check("so it is not worth more disenchanted (1500)", crafts[1002].beatsSale == false)
check("and stays out of the \"pays more\" list", CraftRows(true)[1002] == nil)
check("a craft worth more disenchanted is still in it", CraftRows(true)[1001] ~= nil)

print("\na craft that beats its sale price but not its materials")
-- A player's report: a soulbound craft disenchanted beat the vendor price and
-- showed as a win, though every one made lost money against its materials.
local realCost = ns.Cost.GetCraftCost
ns.Cost.GetCraftCost = function(self, recipeID)
    if recipeID == 1001 then
        return { recipeID = recipeID, priceable = true, total = 2000, perUnit = 2000, yield = 1 }
    end
    return realCost(self, recipeID)
end
local dear = CraftRows(false)[1001]
check("it loses against the materials", dear.gain ~= nil and dear.gain < 0)
check("so it is not counted as worth disenchanting", dear.beatsSale == false)
check("and says why", dear.losesToMaterials == true)
check("nor kept by the \"pays more\" box", CraftRows(true)[1001] == nil)
ns.Cost.GetCraftCost = realCost

print("\na craft a vendor pays more for")
check("is priced at what the vendor pays", crafts[1011].sells == 900 and crafts[1011].sellsAt == "vendor")
check("and so is worth more sold than disenchanted", crafts[1011].beatsSale == false)

-- Analyse itself can choose the vendor's price when that pays more than
-- the listing; it says so in priceBasis, and the price is the vendor's.
local realAnalyse = Profit.Analyse
Profit.Analyse = function(self, recipeID, ...)
    local result = realAnalyse(self, recipeID, ...)
    if recipeID == 1001 and result then
        result.unitRevenue, result.priceBasis, result.priceDerived = 50, "vendor", nil
    end
    return result
end
local vendorCrafts = CraftRows(false)
Profit.Analyse = realAnalyse
check("a price Analyse took from a vendor is labelled as one", vendorCrafts[1001].sells == 50
    and vendorCrafts[1001].sellsAt == "vendor")

print("\na dropped profession")
check("its crafts are left out", crafts[1012] == nil)
check("the others stay", crafts[1001] ~= nil and crafts[1002] ~= nil)

print("\nbag rows and their links")

local bagByID = {}
for _, row in ipairs(Disenchant:GetBagRows({ beatsOnly = false })) do bagByID[row.itemID] = row end
check("a row carries the link of the first copy carried", bagByID[1001].link == LINKS[2])
check("each item its own", bagByID[1002].link == LINKS[5])
check("a link the client will not hand over is left off, not an error",
    bagByID[1011] ~= nil and bagByID[1011].link == nil)

for _, key in ipairs(GLOBALS) do _G[key] = saved[key] end

print(("\n%d check(s) passed\n"):format(checks))
