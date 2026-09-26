-- Queue All on the Profit tab: every listed craft up to its Max on hand.
--
-- Trent, 2026-09-26: "a Queue All button ... that will queue the max on hand
-- amount of every item listed." Drives the real Queue.lua and the real
-- Auctions:GetRoom, so what is already held, listed, in the mail or queued
-- comes off each craft exactly as the MAKE and Max numbers count it.

local ns = {}
ns.NewModule = function(name) local m = {}; ns[name] = m; return m end
ns.RegisterCommand = function() end
ns.RegisterEvent = function() end
ns.Print, ns.PrintRaw, ns.Debug, ns.Warn = function() end, function() end, function() end, function() end
ns.Util = {}
ns.db = { queue = {}, postLimits = {}, postedAuctions = {} }

time = time or os.time

local config = { maxPostedPerItem = 4, autoQueueSubCrafts = false }
ns.Config = {
    Get = function(_, key) return config[key] end,
    GetRealmKey = function() return "Test-Realm" end,
}

local BOOTS, SHIRT, CLOAK, BOLT, WOOL = 100, 200, 300, 400, 500
local recipes = {
    [1] = { recipeID = 1, outputItemID = BOOTS, quantityMin = 1 },
    [2] = { recipeID = 2, outputItemID = SHIRT, quantityMin = 1 },
    [3] = { recipeID = 3, outputItemID = CLOAK, quantityMin = 1 },
    [4] = { recipeID = 4, outputItemID = BOLT, quantityMin = 2 },
    -- Two recipes for the same item: the second must not reuse the room the
    -- first one has just filled.
    [5] = { recipeID = 5, outputItemID = WOOL, quantityMin = 1 },
    [6] = { recipeID = 6, outputItemID = WOOL, quantityMin = 1 },
}
ns.Recipes = {
    Get = function(_, id) return recipes[id] end,
    GetAny = function(_, id) return recipes[id] end,
    GetAll = function() return recipes end,
}

local bags, mail = { [SHIRT] = 1 }, { [CLOAK] = 4 }
ns.Inventory = {
    GetBagCount = function(_, id) return bags[id] or 0 end,
    GetBankCount = function() return 0 end,
    GetMailCount = function(_, id) return mail[id] or 0 end,
    GetOwnedCount = function(_, id) return (bags[id] or 0) + (mail[id] or 0) end,
}

assert(loadfile(lfs_cwd .. "/Data/Auctions.lua"))("Blackthornes_TS", ns)
assert(loadfile(lfs_cwd .. "/Logic/Queue.lua"))("Blackthornes_TS", ns)

local function RoomInCrafts(room, recipe)
    if room == nil then return nil end
    if room <= 0 then return 0 end
    return math.max(1, math.floor(room / math.max(1, recipe.quantityMin or 1)))
end
ns.Profit = {
    RoomInCrafts = RoomInCrafts,
    Analyse = function() return { totalCost = 10, profit = 5 } end,
}

-- One listed Boots already.
ns.Auctions:GetTable().items[BOOTS] = { count = 1 }
ns.Auctions.GetPostedCount = function(_, id) return id == BOOTS and 1 or 0 end

local notified = 0
ns.UI = { OnQueueUpdated = function() notified = notified + 1 end }

local Queue = ns.Queue
local checks = 0
local function check(label, condition)
    checks = checks + 1
    if not condition then error(("FAILED: %s"):format(label), 2) end
    print(("  ok  %s"):format(label))
end

local function queued(recipeID)
    local _, entry = Queue:Find(recipeID, true)
    return entry and entry.quantity or 0
end

-- Shirt has one queued already, on top of one in the bags.
Queue:Add(2, 1)
notified = 0

local rows = {}
for id = 1, 6 do rows[#rows + 1] = { recipeID = id } end

local crafts, items, noLimit = Queue:AddUpToLimit(rows)

check("boots: 4 less the 1 listed", queued(1) == 3)
check("shirt: 4 less 1 in bags and 1 queued, the 2 added to the same entry", queued(2) == 3)
check("cloak: 4 in the mail, nothing queued", queued(3) == 0)
check("bolt makes 2 a craft, so 2 crafts fill 4", queued(4) == 2)
check("first wool recipe fills the room", queued(5) == 4)
check("second wool recipe finds none left", queued(6) == 0)
check("totals: 3 + 2 + 2 + 4 crafts", crafts == 11)
check("items: bolts count double", items == 3 + 2 + 4 + 4)
check("no rows without a limit", noLimit == 0)
check("queue announced once", notified == 1)

-- Pressing it again adds nothing: everything is at its Max on hand.
crafts = Queue:AddUpToLimit(rows)
check("second press queues nothing", crafts == 0)
check("second press does not announce", notified == 1)

-- No Keep in stock set: nothing is queued, and it says why.
ns.db.queue = {}
config.maxPostedPerItem = 0
crafts, items, noLimit = Queue:AddUpToLimit(rows)
check("no limit set queues nothing", crafts == 0 and #ns.db.queue == 0)
check("every row reported as having no limit", noLimit == 6)

-- A per-item override still counts when the global setting is off.
ns.db.postLimits[BOOTS] = 2
crafts = Queue:AddUpToLimit(rows)
check("per-item limit of 2 less 1 listed", crafts == 1 and queued(1) == 1)

print(("%d checks passed"):format(checks))
