-- Craft next makes what frees the most bag space first, outside WoW (a
-- player's request, 2026-10-14).
--
-- What must hold:
--   1. Of the crafts ready now, Craft next picks the one freeing the most
--      bag slots: the stacks its materials stop taking, less the new
--      stacks what it makes takes. Ties go to the earlier in the queue.
--   2. A craft never goes before a ready sub-craft of its own, or of one
--      of its sub-crafts.
--   3. Unticked ("craftFreesSpaceFirst" false), it is the queue's order.
--   4. The slots are worked out again when the bags change.

local GLOBALS = { "GetTime", "time", "C_Timer" }
local saved = {}
for _, key in ipairs(GLOBALS) do saved[key] = _G[key] end

local function noop() end
GetTime = function() return 100 end
time = function() return 100000 end
C_Timer = { After = noop, NewTicker = function() return { Cancel = noop } end }

local ns = {}
ns.NewModule = function(name) local m = {}; ns[name] = m; return m end
ns.RegisterCommand = noop
ns.RegisterEvent = noop
ns.Print, ns.PrintRaw, ns.Debug, ns.Warn = noop, noop, noop, noop
ns.Util = { HasFunction = function() return false end }
local config = {}
ns.Config = { Get = function(_, key) return config[key] end, GetCharacterKey = function() return "me" end }

-- Items: what each stacks to.
local LINEN, BOLT, X, Y, Z, W, E_IN, E_OUT = 1, 2, 3, 4, 5, 6, 7, 8
local STACK = { [LINEN] = 20, [BOLT] = 20, [X] = 20, [Y] = 20, [Z] = 20, [W] = 100,
    [E_IN] = 20, [E_OUT] = 20 }
ns.BagsFull = { MaxStack = function(id) return STACK[id] or 1 end }

local RECIPES = {
    [10] = { name = "C", outputItemID = Y, reagents = { { itemID = X, quantity = 1 } } },
    [20] = { name = "A", outputItemID = BOLT, reagents = { { itemID = LINEN, quantity = 2 } } },
    [30] = { name = "D", outputItemID = W, reagents = { { itemID = Z, quantity = 1 } } },
    [40] = { name = "E", outputItemID = E_OUT, reagents = { { itemID = E_IN, quantity = 1 } } },
}
ns.Recipes = { GetAny = function(_, id) return RECIPES[id], "me" end }

local bags = {}
ns.Inventory = {
    changes = 0,
    GetBagCount = function(_, id) return bags[id] or 0 end,
    GetOwnedCount = function(_, id) return bags[id] or 0 end,
}
ns.Profit = {
    GetCraftableCount = function(_, id)
        local can = math.huge
        for _, r in ipairs(RECIPES[id].reagents) do
            can = math.min(can, math.floor((bags[r.itemID] or 0) / r.quantity))
        end
        return can
    end,
}
ns.Cost = { GetCraftCost = function() return nil end, FindRecipeForItem = function() return nil end }
ns.db = { queue = {} }

assert(loadfile(lfs_cwd .. "/Logic/Queue.lua"))("Blackthornes_TS", ns)
assert(loadfile(lfs_cwd .. "/Logic/Crafting.lua"))("Blackthornes_TS", ns)
local Crafting = ns.Crafting

local passed, failed = 0, 0
local function check(label, got, want)
    local ok = got == want
    if ok then passed = passed + 1 else failed = failed + 1 end
    print(string.format("  %-60s %-6s %s", label, tostring(got), ok and "ok" or
        ("WRONG, wanted " .. tostring(want))))
end

local function Moved()
    ns.Inventory.changes = ns.Inventory.changes + 1
end

local function Next()
    local entry, slots = Crafting:GetNextReady()
    return entry and RECIPES[entry.recipeID].name, slots
end

-- C frees 1 and takes 1; A frees 2 and takes 1; D frees 5 and takes 1.
bags = { [X] = 5, [LINEN] = 40, [Z] = 100 }
ns.db.queue = {
    { recipeID = 10, quantity = 5 },
    { recipeID = 20, quantity = 20 },
    { recipeID = 30, quantity = 100 },
}
check("C frees nothing", (Crafting:SlotsFreed(ns.db.queue[1])), 0)
check("A frees 1", (Crafting:SlotsFreed(ns.db.queue[2])), 1)
check("D frees 4", (Crafting:SlotsFreed(ns.db.queue[3])), 4)
local name, slots = Next()
check("Craft next picks the one freeing most", name, "D")
check("and says how many it frees", slots, 4)

-- Only what can be made now counts: 20 Z make 20 W, one slot for one.
bags[Z] = 20
Moved()
check("bags changing work it out again", (Next()), "A")

-- A tie goes to the earlier: C and a two-slot D both free nothing.
bags[LINEN] = 0
Moved()
check("a tie keeps queue order", (Next()), "C")

-- A is a sub-craft of D: D waits while A is ready.
bags = { [X] = 5, [LINEN] = 40, [Z] = 100 }
Moved()
ns.db.queue[2].isDependency = true
ns.db.queue[2].forRecipes = { [30] = true }
check("a craft waits for its ready sub-craft", (Next()), "A")

-- E feeds A, which feeds D. A cannot be made; E can, so D still waits.
bags[LINEN] = 0
bags[E_IN] = 40
Moved()
table.insert(ns.db.queue, 1, { recipeID = 40, quantity = 40, isDependency = true,
    forRecipes = { [20] = true } })
check("and for a sub-craft further down", (Next()), "E")

-- Unticked, it is the queue's order.
config.craftFreesSpaceFirst = false
bags = { [X] = 5, [LINEN] = 40, [Z] = 100 }
Moved()
ns.db.queue = {
    { recipeID = 10, quantity = 5 },
    { recipeID = 30, quantity = 100 },
}
local plain, plainSlots = Next()
check("unticked follows the queue", plain, "C")
check("and says nothing of bag space", plainSlots, nil)
config.craftFreesSpaceFirst = nil
check("ticked again picks D", (Next()), "D")

ns.db.queue = {}
for _, key in ipairs(GLOBALS) do _G[key] = saved[key] end

print("")
if failed > 0 then
    error(string.format("FAIL -- %d of %d free-space-first checks wrong", failed, passed + failed))
end
print(string.format("PASS -- Craft next frees bag space first (%d checks)", passed))
