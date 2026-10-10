-- Wait until it runs low, and Fast sellers keep more (asked 2026-10-10:
-- "only queue new items if I have 0 ... a minimum stock to keep on hand ...
-- and then set a maximum? For items with a high confirmed sale rate ...
-- increase their crafted count"). Drives the real Auctions:GetRoom.

local ns = {}
ns.NewModule = function(name) local m = {}; ns[name] = m; return m end
ns.RegisterCommand = function() end
ns.RegisterEvent = function() end
ns.Print, ns.PrintRaw, ns.Debug, ns.Warn = function() end, function() end, function() end, function() end
ns.Util = {}
ns.db = { queue = {}, postLimits = {}, postedAuctions = {} }

local config = { maxPostedPerItem = 5 }
ns.Config = {
    Get = function(_, key) return config[key] end,
    GetRealmKey = function() return "Test-Realm" end,
}

local ITEM, OTHER = 100, 200
local recipes = { [1] = { recipeID = 1, outputItemID = ITEM, quantityMin = 1 } }
ns.Recipes = { GetAny = function(_, id) return recipes[id] end }

local bags = {}
ns.Inventory = {
    GetBagCount = function(_, id) return bags[id] or 0 end,
    GetBankCount = function() return 0 end,
    GetMailCount = function() return 0 end,
    GetOwnedCount = function(_, id) return bags[id] or 0 end,
}
ns.Queue = { GetAll = function() return ns.db.queue end }

local readings = {}
ns.Demand = { Get = function(_, id) return readings[id] end }

assert(loadfile(lfs_cwd .. "/Data/Auctions.lua"))("Blackthornes_TS", ns)
ns.Auctions.GetPostedCount = function() return 0 end

local A = ns.Auctions
local checks = 0
local function check(label, condition)
    checks = checks + 1
    if not condition then error(("FAILED: %s"):format(label), 2) end
    print(("  ok  %s"):format(label))
end

-- Off: unchanged from before.
bags[ITEM] = 2
local room, _, _, _, limit, _, waiting, extra = A:GetRoom(ITEM)
check("off: tops up to the limit", room == 3 and limit == 5 and not waiting and extra == 0)

-- On at 0: holding any waits; none left fills back up to the limit.
config.restockWhenLow, config.restockAt = true, 0
room, _, _, _, _, _, waiting = A:GetRoom(ITEM)
check("holding 2, restock at 0: nothing more", room == 0 and waiting)
bags[ITEM] = 0
room, _, _, _, _, _, waiting = A:GetRoom(ITEM)
check("holding none: room back up to 5", room == 5 and not waiting)

-- Queued counts toward the limit, but not as stock still held: one craft
-- queued with + leaves room to queue the rest.
ns.db.queue = { { recipeID = 1, quantity = 2 } }
room, _, _, _, _, _, waiting = A:GetRoom(ITEM)
check("2 queued, restock at 0: room for 3 more", room == 3 and not waiting)
ns.db.queue = { { recipeID = 1, quantity = 5 } }
room, _, _, _, _, _, waiting = A:GetRoom(ITEM)
check("5 queued: at the limit, not waiting", room == 0 and not waiting)
ns.db.queue = { { recipeID = 1, quantity = 30, isDependency = true } }
room, _, _, _, _, _, waiting = A:GetRoom(ITEM)
check("a sub-craft queued for another craft is not stock", room == 5 and not waiting)
ns.db.queue = {}

-- On at 2: 3 held waits, 2 held tops up to 5.
config.restockAt = 2
bags[ITEM] = 3
room, _, _, _, _, _, waiting = A:GetRoom(ITEM)
check("holding 3, restock at 2: waits", room == 0 and waiting)
bags[ITEM] = 2
room = A:GetRoom(ITEM)
check("holding 2, restock at 2: room 3", room == 3)

-- At the limit is the limit, not waiting.
bags[ITEM] = 5
room, _, _, _, _, _, waiting = A:GetRoom(ITEM)
check("at the limit: not reported as waiting", room == 0 and not waiting)

-- No limit: the minimum does nothing.
config.maxPostedPerItem = 0
check("no limit: still uncapped", A:GetRoom(ITEM) == nil)
config.maxPostedPerItem = 5
config.restockWhenLow = false

-- Fast sellers: only your own High reading counts.
bags[ITEM] = 5
config.fastSellerBoost, config.fastSellerExtra = true, 3
readings[ITEM] = { level = "high", source = "market" }
check("market High alone: no extra", A:GetRoom(ITEM) == 0)
readings[ITEM] = { level = "some", source = "yours" }
check("your Some: no extra", A:GetRoom(ITEM) == 0)
readings[ITEM] = { level = "high", source = "yours" }
room, _, _, _, limit, _, _, extra = A:GetRoom(ITEM)
check("your High: 3 more room, limit 8", room == 3 and limit == 8 and extra == 3)
check("another item keeps its limit", select(5, A:GetRoom(OTHER)) == 5)
config.fastSellerBoost = false
check("box off: no extra", A:GetRoom(ITEM) == 0)

-- Both together: restock decision uses the raised limit.
config.fastSellerBoost, config.restockWhenLow, config.restockAt = true, true, 0
bags[ITEM] = 0
check("fast seller at none: room 8", A:GetRoom(ITEM) == 8)

print(("restock: %d checks passed"):format(checks))
