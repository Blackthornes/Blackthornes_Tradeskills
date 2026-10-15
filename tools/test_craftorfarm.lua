-- Craft or farm: gold an hour of your own time (Logic/CraftOrFarm.lua).
--
-- What must hold:
--   1. Farm + craft is what the craft sells for, less what is bought from a
--      vendor, over your farming time plus your crafting time.
--   2. Farm + sell is what the farmed materials sell for over farming time.
--   3. Materials a vendor keeps in stock are bought, never farmed.
--   4. A material made by a craft of yours, with no pace of its own, is
--      followed down to what it is made from, and that cast counts.
--   5. Without Farmer, or with too little farming, the farm ways stay
--      unknown and say how many kills or gathers there are.
--   6. ForMaterial names the craft only when crafting beats selling, and a
--      Farmer that raises breaks nothing.

local ns = {}
ns.NewModule = function(name) local m = {}; ns[name] = m; return m end
ns.db = {}

local CLOTH, BOLT, THREAD, SHIRT, DYE = 2589, 2996, 2320, 2575, 2324

-- Recipes: a shirt from 2 bolts and a thread; a bolt from 2 cloth.
local recipes = {
    [100] = { outputItemID = SHIRT, quantityMin = 1, quantityMax = 1,
        reagents = { { itemID = BOLT, quantity = 2 }, { itemID = THREAD, quantity = 1 } } },
    [200] = { outputItemID = BOLT, quantityMin = 1, quantityMax = 1,
        reagents = { { itemID = CLOTH, quantity = 2 } } },
}
ns.Recipes = {
    GetAll = function() return recipes end,
    GetAny = function(_, id) return recipes[id] end,
    IsDropped = function() return false end,
}
ns.Cost = { FindRecipeForItem = function(_, itemID) if itemID == BOLT then return 200 end end }
ns.Vendor = {
    KeepsInStock = function(_, itemID) return itemID == THREAD end,
    GetUnitPrice = function(_, itemID) if itemID == THREAD then return 10 end end,
}
local market = { [CLOTH] = 100, [BOLT] = 250 }
ns.Prices = { GetValue = function(_, itemID) return market[itemID] end }
ns.Util = { GetVendorSellPrice = function() return nil end }
ns.Profit = {
    -- Market price less a 5% cut, as the real one roughly does.
    NetFromListing = function(_, _, price) return math.floor(price * 0.95) end,
    GetMethod = function() return "market" end,
    IsIgnored = function() return false end,
    Analyse = function(_, recipeID)
        if recipeID == 100 then
            return { recipeID = 100, name = "Linen Shirt", outputItemID = SHIRT, yield = 1,
                priceable = true, profit = 400, totalCost = 600 }
        end
        if recipeID == 200 then
            return { recipeID = 200, name = "Bolt of Cloth", outputItemID = BOLT, yield = 1,
                priceable = true, profit = 30, totalCost = 200 }
        end
    end,
}
local casts = { [100] = 3, [200] = 1 }
ns.CraftTime = {
    GetCast = function(_, id) return casts[id] end,
    PerHour = function(profit, seconds)
        if type(profit) ~= "number" or type(seconds) ~= "number" or seconds <= 0 then return nil end
        return profit * 3600 / seconds
    end,
}

-- Farmer: cloth every 30 s from your own kills; bolts are not farmed.
local paces = { [CLOTH] = { seconds = 30, kind = "kill", source = "Vale Bandit", samples = 40 } }
local farmerRaises = false
_G.BlackthornesFarmer = { Pace = { ForItem = function(_, itemID)
    if farmerRaises then error("boom") end
    if paces[itemID] then return paces[itemID] end
    return nil, { samples = itemID == DYE and 7 or 0 }
end } }

_G.GetTime = function() return 1000 end
_G.C_Timer = nil

assert(loadfile(lfs_cwd .. "/Logic/CraftOrFarm.lua"))("Blackthornes_TS", ns)
local CraftOrFarm = ns.CraftOrFarm

local checks = 0
local function check(label, condition)
    checks = checks + 1
    if not condition then error(("FAILED: %s"):format(label), 2) end
    print(("  ok  %s"):format(label))
end
local function near(a, b) return type(a) == "number" and math.abs(a - b) < 0.01 end

print("\ncraft or farm")

check("Farmer is seen", CraftOrFarm:HasFarmer())

-- The shirt: 2 bolts are 4 cloth (2 bolt casts), 1 thread bought.
local mats = CraftOrFarm:Materials(100, {})
check("the bolts are followed down to cloth", mats.farm[CLOTH] == 4 and mats.farm[BOLT] == nil)
check("the thread is bought", mats.buy[THREAD] == 1 and mats.farm[THREAD] == nil)
check("the bolt casts count", mats.casts[200] == 2 and mats.casts[100] == 1)

local shirt = CraftOrFarm:Work(ns.Profit:Analyse(100), {})
check("a row for the shirt", shirt ~= nil and shirt.name == "Linen Shirt")
check("it brings in profit plus costs", shirt.made == 1000)
check("the thread is counted as bought", shirt.bought == 10)
check("farming is 4 cloth at 30 s", shirt.farmSeconds == 120)
check("crafting is 3 s and two 1 s bolts", shirt.craftSeconds == 5)
-- (1000 - 10) over 125 s.
check("farm + craft an hour", near(shirt.farmCraft, 990 * 3600 / 125))
-- 4 cloth at 95 each over 120 s.
check("farm + sell an hour", near(shirt.farmSell, 380 * 3600 / 120))
check("crafting is best here", shirt.best == "craft")
check("buy + craft stays the profit for one", shirt.buyProfit == 400)

-- A craft whose material you have not farmed enough.
recipes[300] = { outputItemID = 9000, quantityMin = 1, quantityMax = 1,
    reagents = { { itemID = DYE, quantity = 3 } } }
local dyed = CraftOrFarm:Work({ recipeID = 300, name = "Dyed", priceable = true,
    profit = 50, totalCost = 50 }, {})
check("too little farming leaves the farm ways unknown",
    dyed and dyed.farmSeconds == nil and dyed.farmCraft == nil and dyed.best == nil)
check("and says how many there are", dyed.missing and dyed.missing.itemID == DYE and dyed.missing.samples == 7)
recipes[300] = nil

-- A craft that only needs vendor goods has nothing to farm.
recipes[400] = { outputItemID = 9001, reagents = { { itemID = THREAD, quantity = 2 } } }
check("nothing to farm, no row", CraftOrFarm:Work({ recipeID = 400, priceable = true,
    profit = 5, totalCost = 20 }, {}) == nil)
recipes[400] = nil
check("an unpriced craft gives no row", CraftOrFarm:Work({ recipeID = 100, priceable = false }, {}) == nil)

-- The whole list, and what Farmer's tooltip would ask.
local built
CraftOrFarm:Build(function(rows) built = rows end, true)
check("the list is built", built and #built == 2)
local forCloth = CraftOrFarm:ForMaterial(CLOTH)
check("cloth is best crafted into the shirt", forCloth and forCloth.recipeID == 100)
check("with its gold an hour", forCloth and near(forCloth.perHour, shirt.farmCraft))
check("a bought material is never named", CraftOrFarm:ForMaterial(THREAD) == nil)
check("nonsense gets nothing", CraftOrFarm:ForMaterial(nil) == nil and CraftOrFarm:ForMaterial("x") == nil)

-- Selling beats crafting: the material is not named.
market[CLOTH] = 100000
CraftOrFarm:Forget()
CraftOrFarm:Build(nil, true)
check("when the cloth sells for more, no craft is named", CraftOrFarm:ForMaterial(CLOTH) == nil)
market[CLOTH] = 100

-- A Farmer that raises, and no Farmer at all.
farmerRaises = true
local broken = CraftOrFarm:Work(ns.Profit:Analyse(100), {})
check("a raising Farmer breaks nothing", broken and broken.farmCraft == nil)
farmerRaises = false
_G.BlackthornesFarmer = nil
check("without Farmer it says so", not CraftOrFarm:HasFarmer())
local alone = CraftOrFarm:Work(ns.Profit:Analyse(100), {})
check("without Farmer the farm ways are unknown", alone and alone.farmCraft == nil and alone.farmSell == nil)

print(("\n%d checks passed"):format(checks))
