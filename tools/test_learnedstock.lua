-- Keep in stock learned from your sales, and restocking what sells.
--
-- The owner, 2026-10-11: the addons should work "almost like magic". With no
-- Keep in stock number set, Queue All keeps about two days of what sold for
-- you this week, and a sale queues another while there is room. A typed
-- number always wins. Drives the real Auctions:GetRoom, Queue.lua and the
-- sale alarm's Restock.

local ns = {}
ns.NewModule = function(name) local m = {}; ns[name] = m; return m end
ns.RegisterCommand = function() end
ns.RegisterEvent = function() end
local printed = {}
ns.Print = function(text) printed[#printed + 1] = text end
ns.PrintRaw, ns.Debug, ns.Warn = function() end, function() end, function() end
ns.Util = {}
ns.db = { queue = {}, postLimits = {}, postedAuctions = {} }

time = time or os.time
local NOW = time()

local config = { maxPostedPerItem = 0, autoQueueSubCrafts = false }
ns.Config = {
    Get = function(_, key) return config[key] end,
    GetRealmKey = function() return "Test-Realm" end,
    GetCharacterKey = function() return "me" end,
}

local BOOTS, SHIRT, CLOAK, BELT = 100, 200, 300, 400
local recipes = {
    [1] = { recipeID = 1, outputItemID = BOOTS, quantityMin = 1 },
    [2] = { recipeID = 2, outputItemID = SHIRT, quantityMin = 1 },
    [3] = { recipeID = 3, outputItemID = CLOAK, quantityMin = 1 },
    [4] = { recipeID = 4, outputItemID = BELT, quantityMin = 1 },
}
ns.Recipes = {
    Get = function(_, id) return recipes[id] end,
    GetAny = function(_, id) return recipes[id] end,
    GetAll = function() return recipes end,
    GetAccountWideOutputs = function() return {} end,
}

local bags = { [SHIRT] = 1 }
ns.Inventory = {
    GetBagCount = function(_, id) return bags[id] or 0 end,
    GetBankCount = function() return 0 end,
    GetMailCount = function() return 0 end,
    GetOwnedCount = function(_, id) return bags[id] or 0 end,
}

-- Your sales: boots sold 7 this week (two days of it is 2), the shirt 1
-- this week, the cloak only a month ago. A shirt sale heard in chat waits
-- for its mail.
local DAY = 86400
local ledger = { entries = {
    { kind = "sold", itemID = BOOTS, quantity = 3, t = NOW - 2 * DAY },
    { kind = "sold", name = "Boots", quantity = 4, t = NOW - 1 * DAY },
    { kind = "expired", itemID = BOOTS, quantity = 5, t = NOW - DAY },
    { kind = "sold", itemID = SHIRT, quantity = 1, t = NOW - 3 * DAY },
    { kind = "sold", itemID = CLOAK, quantity = 9, t = NOW - 30 * DAY },
    { kind = "sold", itemID = BELT, quantity = 100, t = NOW - DAY },
} }
local heard = {}
ns.Mail = {
    GetLedger = function() return ledger end,
    GetHeardList = function() return heard end,
    NameIndex = function() return { Boots = BOOTS } end,
    NoteHeardSale = function(_, name)
        local sale = { t = time(), name = name, itemID = name == "Shirt" and SHIRT or nil }
        heard[#heard + 1] = sale
        return sale
    end,
}

assert(loadfile(lfs_cwd .. "/Data/Auctions.lua"))("Blackthornes_TS", ns)
assert(loadfile(lfs_cwd .. "/Logic/Queue.lua"))("Blackthornes_TS", ns)
assert(loadfile(lfs_cwd .. "/Logic/SaleAlarm.lua"))("Blackthornes_TS", ns)

local profits = {}
ns.Profit = {
    RoomInCrafts = function(room, recipe)
        if room == nil then return nil end
        if room <= 0 then return 0 end
        return math.max(1, math.floor(room / math.max(1, recipe.quantityMin or 1)))
    end,
    Analyse = function(_, id) return { totalCost = 10, profit = profits[id] or 5 } end,
}
ns.Auctions.GetPostedCount = function() return 0 end
ns.UI = { OnQueueUpdated = function() end }

local Auctions, Queue, SaleAlarm = ns.Auctions, ns.Queue, ns.SaleAlarm
local checks = 0
local function check(label, condition, detail)
    checks = checks + 1
    if not condition then error(("FAILED: %s %s"):format(label, tostring(detail or "")), 2) end
    print(("  ok  %s"):format(label))
end
local function queued(recipeID)
    local _, entry = Queue:Find(recipeID, true)
    return entry and entry.quantity or 0
end

check("boots: 7 sold this week, two days' worth is 2", Auctions:GetLearnedLimit(BOOTS) == 2,
    Auctions:GetLearnedLimit(BOOTS))
check("a sale named only by name counts", Auctions:GetLearnedLimit(BOOTS) == 2)
check("shirt: one sale still keeps 1", Auctions:GetLearnedLimit(SHIRT) == 1)
check("cloak: nothing sold this week, nothing learned", Auctions:GetLearnedLimit(CLOAK) == nil)
check("a big seller is capped", Auctions:GetLearnedLimit(BELT) == Auctions.LEARN_MOST)
check("GetRoom alone still says no limit", (Auctions:GetRoom(BOOTS)) == nil)

local rows = {}
for id = 1, 3 do rows[#rows + 1] = { recipeID = id } end
local crafts, _, noLimit, learned = Queue:AddUpToLimit(rows)
check("Queue All works with no number set: boots up to 2", queued(1) == 2, queued(1))
check("the shirt in the bags fills its 1", queued(2) == 0)
check("the cloak is skipped as having no limit", queued(3) == 0 and noLimit == 1)
check("the crafts are counted as learned", crafts == 2 and learned == 2)

-- A typed number always wins.
ns.db.postLimits[BOOTS] = 5
Queue:AddUpToLimit(rows)
check("a per-item number beats what was learned", queued(1) == 5, queued(1))
ns.db.postLimits[BOOTS] = nil

-- A sale queues another while there is room.
ns.db.queue = {}
bags[SHIRT] = 0
SaleAlarm.unpaired = nil
SaleAlarm:LogHeard("Shirt", "notice")
check("a shirt sold: another is queued", queued(2) == 1, queued(2))
check("and chat says so", printed[#printed] == "Shirt sold: queued another to keep your stock up.", printed[#printed])
check("the heard sale counts toward what is learned", Auctions:GetLearnedLimit(SHIRT) == 1)
SaleAlarm.unpaired = nil
SaleAlarm:LogHeard("Shirt", "notice")
check("no room left: nothing more", queued(2) == 1)

-- Never for a craft that loses money, a craft nobody makes, or with it off.
ns.db.queue = {}
profits[2] = -10
check("a losing craft is not restocked", Queue:RestockSold(SHIRT) == nil and queued(2) == 0)
profits[2] = nil
check("an item nobody crafts is not restocked", Queue:RestockSold(999) == nil)
config.restockOnSale = false
check("off, nothing is restocked", Queue:RestockSold(SHIRT) == nil)
config.restockOnSale = nil
check("on again, it is", Queue:RestockSold(SHIRT) == 2 and queued(2) == 1)

-- Wait until it runs low holds a restock back.
ns.db.queue = {}
ns.db.postLimits[BOOTS] = 3
bags[BOOTS] = 2
config.restockWhenLow, config.restockAt = true, 0
check("waiting for it to run low: no restock", Queue:RestockSold(BOOTS) == nil)
config.restockWhenLow = false
check("not waiting: one more of the 3", Queue:RestockSold(BOOTS) == 1 and queued(1) == 1)

-- "Stock from your sales" off: nothing learned, so Queue All and a sale
-- leave a craft with no number alone (a player found Queue All adding
-- crafts the STOCK column showed no number for).
ns.db.queue = {}
ns.db.postLimits[BOOTS] = nil
bags[BOOTS], bags[SHIRT] = 0, 0
config.learnStockFromSales = false
check("off, nothing is learned", Auctions:GetLearnedLimit(BOOTS) == nil)
local offCrafts, _, offNoLimit = Queue:AddUpToLimit(rows)
check("off, Queue All skips crafts with no number", offCrafts == 0 and offNoLimit == 3, offCrafts)
check("off, a sale queues nothing without a number", Queue:RestockSold(SHIRT) == nil and queued(2) == 0)
ns.db.postLimits[BOOTS] = 2
Queue:AddUpToLimit(rows)
check("off, a typed number still works", queued(1) == 2, queued(1))
config.learnStockFromSales = nil
ns.db.postLimits[BOOTS] = nil
check("on again, it learns", Auctions:GetLearnedLimit(BOOTS) == 2)

print(("%d checks passed"):format(checks))
