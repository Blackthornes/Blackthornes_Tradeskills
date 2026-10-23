-- The queue counts each in-between material once, the cheaper way.
--
-- The owner's Woolen Reagent Bag: 3 Bolts of Woolen Cloth, a Cerulean Dye and a
-- Fine Thread. Making the bolts from 9 Wool Cloth was cheaper than buying
-- them, so the queue added the bolt crafts. The footer then read 1g 2s 85c:
-- the bag's own cost (which already paid for the wool) plus the bolt crafts
-- (the same wool again). "To buy" listed the bolts to buy and the wool to make
-- them. The right answer is 76s 30c either way.
--
-- Drives the real Cost.lua and Queue.lua, so the craft-or-buy choice that
-- queues the bolts is the same one that prices the bag.

local ns = {}
ns.NewModule = function(name) local m = {}; ns[name] = m; return m end
ns.RegisterCommand = function() end
ns.RegisterEvent = function() end
ns.Print, ns.PrintRaw, ns.Debug, ns.Warn = function() end, function() end, function() end, function() end
ns.Util = {}

time = time or os.time

local BAG, BOLT, WOOL, DYE, THREAD, DUST = 5000, 2997, 2592, 3825, 2321, 10940

local config = { valueOwnedMaterials = true }
ns.Config = { Get = function(_, key) return config[key] end }

local recipes = {
    [10] = { recipeID = 10, outputItemID = BAG, quantityMin = 1, quantityMax = 1,
             reagents = { { itemID = BOLT, quantity = 3 },
                          { itemID = DYE, quantity = 1 },
                          { itemID = THREAD, quantity = 1 } } },
    [20] = { recipeID = 20, outputItemID = BOLT, quantityMin = 1, quantityMax = 1,
             reagents = { { itemID = WOOL, quantity = 3 } } },
    -- An enchant makes no item, so nothing it makes has a price.
    [30] = { recipeID = 30, reagents = { { itemID = DUST, quantity = 4 } } },
}
ns.Recipes = {
    Get = function(_, id) return recipes[id] end,
    GetAny = function(_, id) return recipes[id] end,
    GetAll = function() return recipes end,
}

local bags, bank, mail = {}, {}, {}
ns.Inventory = {
    GetBagCount = function(_, id) return bags[id] or 0 end,
    GetBankCount = function(_, id) return bank[id] or 0 end,
    GetMailCount = function(_, id) return mail[id] or 0 end,
    GetOwnedCount = function(_, id) return (bags[id] or 0) + (bank[id] or 0) + (mail[id] or 0) end,
    GetAltTotal = function() return 0 end,
}

-- Cheapest listing per unit, from the screenshot: bolts 30s 90c for 3,
-- wool 26s 55c for 9, dye 48s 85c. Thread comes from a vendor at 90c.
local auction = { [BOLT] = 1030, [WOOL] = 295, [DYE] = 4885, [DUST] = 78 }
ns.Prices = { GetValue = function(_, id) return auction[id] end }
ns.Vendor = {
    GetUnitPrice = function(_, id) return id == THREAD and 90 or nil end,
    IsLimited = function() return false end,
}

local salePrice = { [BAG] = 7550, [BOLT] = 400 }

assert(loadfile(lfs_cwd .. "/Logic/Cost.lua"))("Blackthornes_TS", ns)
assert(loadfile(lfs_cwd .. "/Logic/Queue.lua"))("Blackthornes_TS", ns)

-- Profit:Analyse reduced to what the queue reads from it.
ns.Profit = { Analyse = function(_, recipeID)
    local cost = ns.Cost:GetCraftCost(recipeID)
    if not cost or not cost.priceable then return { priceable = false } end
    local sells = salePrice[recipes[recipeID].outputItemID or 0]
    if not sells then return { priceable = false, reason = "output has no price data" } end
    return { priceable = true, totalCost = cost.total, profit = sells - cost.total }
end }

local Queue, Cost = ns.Queue, ns.Cost

local checks = 0
local function check(label, condition)
    checks = checks + 1
    if not condition then error(("FAILED: %s"):format(label), 2) end
    print(("  ok  %s"):format(label))
end

local function row(itemID)
    for _, line in ipairs(Queue:GetShoppingList()) do
        if line.itemID == itemID then return line end
    end
end

local function queueOneBag()
    Cost:InvalidateIndex()
    ns.db = { queue = {} }
    Queue:Add(10, 1)
end

print("\nmaking the bolts is cheaper")

queueOneBag()
local _, bolts = Queue:Find(20)
check("the bolt crafts are queued for the bag", bolts and bolts.isDependency and bolts.quantity == 3)

local totals = Queue:GetTotals()
check("the footer counts four crafts", totals.crafts == 4)
check("materials cost 76s 30c, the wool counted once (got " .. totals.cost .. ")", totals.cost == 7630)
check("profit is the bag's alone, not the bolts' too (got " .. totals.profit .. ")", totals.profit == -80)

check("bolts are not on the shopping list", row(BOLT) == nil)
check("the wool to make them is", row(WOOL) and row(WOOL).shortfall == 9)
local toBuy = Queue:GetShoppingTotal()
check("to buy matches the footer (got " .. toBuy .. ")", toBuy == 7630)

print("\nbuying the bolts is cheaper")

auction[WOOL] = 400   -- 3 wool now 12s a bolt, against 10s 30c to buy one
queueOneBag()
check("no bolt crafts are queued", Queue:Find(20) == nil)
totals = Queue:GetTotals()
check("materials cost the bought bolts (got " .. totals.cost .. ")", totals.cost == 3090 + 4885 + 90)
check("the bolts are on the shopping list", row(BOLT) and row(BOLT).shortfall == 3)
check("the wool is not", row(WOOL) == nil)
check("to buy matches the footer", Queue:GetShoppingTotal() == totals.cost)

print("\nsome bolts already owned")

auction[WOOL] = 295
bags[BOLT] = 1
queueOneBag()
_, bolts = Queue:Find(20)
check("only the missing two bolts are queued", bolts and bolts.quantity == 2)
check("the bolt in the bags is used, nothing bought", row(BOLT) and row(BOLT).needed == 1
    and row(BOLT).shortfall == 0)
check("wool for two bolts", row(WOOL) and row(WOOL).shortfall == 6)

bags[BOLT], mail[BOLT] = nil, 1
queueOneBag()
check("a bolt in the mailbox is used too, not bought", row(BOLT) and row(BOLT).shortfall == 0)
mail[BOLT] = nil

print("\nsub-crafts switched off")

-- On Discord (2026-10-07): with "Queue sub-crafts" off, To buy went
-- up to the bought materials but the rows and the footer still priced
-- them as made.
config.autoQueueSubCrafts = false
queueOneBag()
check("no bolt crafts are queued", Queue:Find(20) == nil)
totals = Queue:GetTotals()
check("materials cost the bought bolts (got " .. totals.cost .. ")", totals.cost == 3090 + 4885 + 90)
check("profit follows (got " .. totals.profit .. ")", totals.profit == 7550 - (3090 + 4885 + 90))
local _, bag = Queue:Find(10)
check("the bag's row costs the same", Queue:GetEntryCosts()[bag].cost == totals.cost)
check("to buy matches the footer", Queue:GetShoppingTotal() == totals.cost)

config.autoQueueSubCrafts = nil
queueOneBag()
check("switched back on, the bolts are made again", Queue:GetTotals().cost == 7630)

print("\na kept sub-craft that buying now beats")

-- The bolts stay queued when buying turns cheaper (see RebuildDependencies),
-- so the bag is costed with them made, as To buy has it.
auction[WOOL] = 400
Queue:RebuildDependencies()
_, bolts = Queue:Find(20)
check("the bolt crafts stay", bolts and bolts.buyCheaper)
totals = Queue:GetTotals()
check("materials cost the wool for them (got " .. totals.cost .. ")", totals.cost == 3600 + 4885 + 90)
check("to buy matches the footer", Queue:GetShoppingTotal() == totals.cost)
auction[WOOL] = 295

print("\nan enchant, which makes nothing to sell")

-- Enchant Boots - Minor Stamina x112: the footer said materials 0c while
-- To buy said 348g for the dust.
Cost:InvalidateIndex()
ns.db = { queue = {} }
Queue:Add(30, 112)
totals = Queue:GetTotals()
check("materials count the dust (got " .. totals.cost .. ")", totals.cost == 112 * 4 * 78)
check("profit is not known", totals.priceable == false and totals.profit == 0)
check("to buy matches the footer", Queue:GetShoppingTotal() == totals.cost)
Queue:Add(10, 1)
totals = Queue:GetTotals()
check("beside a priced craft both materials count", totals.cost == 112 * 4 * 78 + 7630)
check("profit is only the priced craft's", totals.profit == 7550 - 7630 and totals.priceable == false)

print(("\n%d check(s) passed\n"):format(checks))
