-- Two queued crafts finishing in one bag update.
--
-- Crafting:OnBagUpdate walked the live queue array while SetQuantity removed
-- finished entries from it. Removing entry 1 slides entry 2 into its slot,
-- and ipairs never visits it, so the second craft stayed on the queue after
-- it had been made -- until the next bag change happened to notice.

local ns = {}
ns.NewModule = function(name) local m = {}; ns[name] = m; return m end
ns.RegisterCommand = function() end
ns.RegisterEvent = function() end
ns.Print, ns.PrintRaw, ns.Debug, ns.Warn = function() end, function() end, function() end, function() end
ns.Util = {}

time = time or os.time

ns.Config = { Get = function(_, key)
    if key == "autoQueueSubCrafts" then return false end
    return nil
end }

local recipes = {
    [100] = { recipeID = 100, outputItemID = 1000, quantityMin = 1 },
    [200] = { recipeID = 200, outputItemID = 2000, quantityMin = 1 },
    [300] = { recipeID = 300, outputItemID = 3000, quantityMin = 1 },
}
ns.Recipes = {
    GetAny = function(_, id) return recipes[id] end,
    GetDisplayLink = function(_, id) return "recipe" .. tostring(id) end,
}

local bags = {}
ns.Inventory = {
    GetBagCount = function(_, itemID) return bags[itemID] or 0 end,
    GetOwnedCount = function(_, itemID) return bags[itemID] or 0 end,
}
ns.Cost = { GetCraftCost = function() return nil end, FindRecipeForItem = function() return nil end }

ns.db = { queue = {} }

assert(loadfile(lfs_cwd .. "/Logic/Queue.lua"))("Blackthornes_TS", ns)
assert(loadfile(lfs_cwd .. "/Logic/Crafting.lua"))("Blackthornes_TS", ns)

local Queue, Crafting = ns.Queue, ns.Crafting

local checks = 0
local function check(label, condition)
    checks = checks + 1
    if not condition then error(("FAILED: %s"):format(label), 2) end
    print(("  ok  %s"):format(label))
end

print("\nqueue reconciliation from the bags")

ns.db.queue = {
    { recipeID = 100, quantity = 1 },
    { recipeID = 200, quantity = 1 },
    { recipeID = 300, quantity = 2 },
}
Crafting:RememberOutputs()

-- One bag update carrying the first two crafts and one of the third.
bags[1000], bags[2000], bags[3000] = 1, 1, 1
Crafting:OnBagUpdate()

check("the first finished craft left the queue", Queue:Find(100) == nil)
check("the second finished craft left the queue too", Queue:Find(200) == nil)
local _, third = Queue:Find(300)
check("the partly made craft counted down", third and third.quantity == 1)
check("nothing else is on the queue", Queue:Count() == 1)

print(("\n%d check(s) passed\n"):format(checks))
