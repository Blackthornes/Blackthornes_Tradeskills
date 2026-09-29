-- A lucky extra from a variable-yield craft, and the "left" count in chat.
--
-- A recipe that makes 1 to 2 items per craft sometimes gives 2. The bag walk
-- counted items, so that one craft took two off the queue. It is now capped
-- by the casts seen since the last bag update, and falls back to the item
-- count when no cast was seen. The "made 1 of X" chat line also says how
-- many are still queued.

local ns = {}
ns.NewModule = function(name) local m = {}; ns[name] = m; return m end
ns.RegisterCommand = function() end
ns.RegisterEvent = function() end
local printed = {}
ns.Print = function(text) printed[#printed + 1] = text end
ns.PrintRaw, ns.Debug, ns.Warn = function() end, function() end, function() end
ns.Util = {}

time = time or os.time

ns.Config = { Get = function() return nil end }

local recipes = {
    [100] = { recipeID = 100, outputItemID = 1000, quantityMin = 1, quantityMax = 2 },
    [400] = { recipeID = 400 },
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

local function quantity(id)
    local _, entry = Queue:Find(id)
    return entry and entry.quantity
end

print("\nvariable-yield crafts count by casts")

Crafting.isTradeSkillOpen = true
ns.db.queue = { { recipeID = 100, quantity = 5 } }
bags[1000] = 0
Crafting:RememberOutputs()

-- One cast, two items: a lucky extra.
Crafting:OnCastSucceeded("UNIT_SPELLCAST_SUCCEEDED", "player", "cast", 100)
bags[1000] = 2
Crafting:OnBagUpdate()
check("one craft with a lucky extra counts down by one", quantity(100) == 4)
check("chat says how many are left", printed[#printed] == "made 1 of recipe100, 4 left")

-- Two casts in one bag update, three items.
Crafting:OnCastSucceeded("UNIT_SPELLCAST_SUCCEEDED", "player", "cast", 100)
Crafting:OnCastSucceeded("UNIT_SPELLCAST_SUCCEEDED", "player", "cast", 100)
bags[1000] = 5
Crafting:OnBagUpdate()
check("two crafts count down by two", quantity(100) == 2)

-- Casts are not carried over to the next bag update.
bags[1000] = 7
Crafting:OnBagUpdate()
check("with no cast seen, the item count is used", quantity(100) == nil)
check("the last one says all done", printed[#printed] == "made 2 of recipe100, all done")

print("\nenchants say how many are left too")

ns.db.queue = { { recipeID = 400, quantity = 2 } }
Crafting:OnCastSucceeded("UNIT_SPELLCAST_SUCCEEDED", "player", "cast", 400)
check("an enchant line has the count", printed[#printed] == "made 1 of recipe400, 1 left")
Crafting:OnCastSucceeded("UNIT_SPELLCAST_SUCCEEDED", "player", "cast", 400)
check("the last enchant says all done", printed[#printed] == "made 1 of recipe400, all done")

print(("\n%d check(s) passed\n"):format(checks))
