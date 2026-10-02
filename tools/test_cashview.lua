-- "Charge market price" unticked: materials already owned count as free.
--
-- What must hold:
--   1. Only as many as are in the bags are free. One bolt held made all three
--      a Linen Bag needs cost nothing.
--   2. A reagent partly held and with no price is still unpriced, not free.
--   3. Sub-crafts stay queued as they are made. A bolt held priced every bolt
--      at nothing, nothing is cheaper to make than that, so once the first
--      queued bolt was made the other fourteen dropped off the queue.
--   4. Holding one bolt when the bags are queued still queues the rest.
--   5. With the box ticked (the default), what is held changes nothing.

-- Tests share one Lua state, so every global replaced here is put back,
-- including the ones that were not set at all.
local GLOBALS = { "GetTime", "time" }
local saved = {}
for _, key in ipairs(GLOBALS) do saved[key] = _G[key] end

local function noop() end

local now = 100
GetTime = function() return now end
time = function() return 100000 end

local CLOTH, BOLT, BAG, DYE = 2589, 2996, 4240, 2324
local BOLT_RECIPE, BAG_RECIPE, DYED_RECIPE = 2963, 3755, 9000

local ns = {}
local handlers = {}
ns.NewModule = function(name) local m = {}; ns[name] = m; return m end
ns.RegisterCommand = noop
ns.RegisterEvent = function(owner, event, fn)
    handlers[event] = function(...) return fn(owner, event, ...) end
end
ns.Print, ns.PrintRaw, ns.Debug, ns.Warn = noop, noop, noop, noop
ns.Util = { HasFunction = function() return false end }

local settings = { valueOwnedMaterials = false, autoQueueSubCrafts = true }
ns.Config = {
    Get = function(_, key) return settings[key] end,
    GetCharacterKey = function() return "me" end,
}

-- A bolt is two cloth; a bag is three bolts. The dyed bag needs a dye nobody
-- has priced.
local RECIPES = {
    [BOLT_RECIPE] = { recipeID = BOLT_RECIPE, name = "Bolt of Linen Cloth", outputItemID = BOLT,
        quantityMin = 1, quantityMax = 1, reagents = { { itemID = CLOTH, quantity = 2 } } },
    [BAG_RECIPE] = { recipeID = BAG_RECIPE, name = "Linen Bag", outputItemID = BAG,
        quantityMin = 1, quantityMax = 1, reagents = { { itemID = BOLT, quantity = 3 } } },
    [DYED_RECIPE] = { recipeID = DYED_RECIPE, name = "Dyed Bag", outputItemID = 9001,
        quantityMin = 1, quantityMax = 1, reagents = { { itemID = DYE, quantity = 4 } } },
}
ns.Recipes = {
    GetAny = function(_, id) return RECIPES[id], "me" end,
    GetAll = function() return RECIPES end,
    GetDisplayLink = function(_, id) return RECIPES[id].name end,
}

local bags = {}
ns.Inventory = {
    GetBagCount = function(_, id) return bags[id] or 0 end,
    GetBankCount = function() return 0 end,
    GetMailCount = function() return 0 end,
    GetOwnedCount = function(_, id) return bags[id] or 0 end,
}

-- Cloth 10c, bolts 50c on the auction house; making a bolt is 20c of cloth.
local LOWEST = { [CLOTH] = 10, [BOLT] = 50, [BAG] = 400 }
ns.Prices = { GetValue = function(_, id) return LOWEST[id] end }
ns.Vendor = { GetUnitPrice = function() return nil end }
ns.Profit = { Analyse = function() return nil end }
ns.db = { queue = {} }

assert(loadfile(lfs_cwd .. "/Logic/Cost.lua"))("Blackthornes_TS", ns)
assert(loadfile(lfs_cwd .. "/Logic/Queue.lua"))("Blackthornes_TS", ns)
assert(loadfile(lfs_cwd .. "/Logic/Crafting.lua"))("Blackthornes_TS", ns)
local Cost, Queue, Crafting = ns.Cost, ns.Queue, ns.Crafting
Crafting:OnEnable()

local passed, failed = 0, 0

local function check(label, got, want)
    local ok = got == want
    if ok then passed = passed + 1 else failed = failed + 1 end
    print(string.format("  %-58s %-8s %s", label, tostring(got), ok and "ok" or
        ("WRONG, wanted " .. tostring(want))))
end

local function Queued(recipeID, dependency)
    for _, entry in ipairs(Queue:GetAll()) do
        if entry.recipeID == recipeID and (entry.isDependency == true) == dependency then
            return entry.quantity
        end
    end
    return 0
end

print("what a Linen Bag costs out of pocket")

do
    bags = { [BOLT] = 1 }
    local cost = Cost:GetCraftCost(BAG_RECIPE)
    check("one of three bolts held: two still to make", cost.total, 40)
    check("the bolt line costs the two", cost.reagents[1].lineCost, 40)

    bags = { [BOLT] = 3 }
    cost = Cost:GetCraftCost(BAG_RECIPE)
    check("all three held: nothing to pay", cost.total, 0)
    check("and the line says owned", cost.reagents[1].source, "owned")

    bags = {}
    cost = Cost:GetCraftCost(BAG_RECIPE)
    check("none held: three bolts made from bought cloth", cost.total, 60)

    bags = { [DYE] = 1 }
    cost = Cost:GetCraftCost(DYED_RECIPE)
    check("a partly held reagent with no price is not free", cost.priceable, false)

    bags = { [DYE] = 4 }
    cost = Cost:GetCraftCost(DYED_RECIPE)
    check("all of it held costs nothing, price or not", cost.total, 0)
end

print("")
print("with Charge market price ticked")

do
    settings.valueOwnedMaterials = true
    bags = { [BOLT] = 1 }
    check("one bolt held changes nothing", Cost:GetCraftCost(BAG_RECIPE).total, 60)
    bags = { [BOLT] = 3 }
    check("nor do three", Cost:GetCraftCost(BAG_RECIPE).total, 60)
    settings.valueOwnedMaterials = false
end

print("")
print("queued bolts stay queued as they are made")

do
    ns.db.queue = {}
    bags = { [CLOTH] = 30 }
    Queue:Add(BAG_RECIPE, 5)
    check("five bags queue fifteen bolts", Queued(BOLT_RECIPE, true), 15)

    -- The first bolt of the run, made from the profession window.
    Crafting.isTradeSkillOpen = true
    Crafting:RememberOutputs()
    Crafting.active = { recipeID = BOLT_RECIPE, requested = 15, outputItemID = BOLT,
        before = 0, startedAt = now }
    now = now + 2
    bags[CLOTH], bags[BOLT] = 28, 1
    handlers.BAG_UPDATE_DELAYED()
    check("one made: fourteen still queued", Queued(BOLT_RECIPE, true), 14)
    check("the bags are untouched", Queued(BAG_RECIPE, false), 5)

    Crafting.active, Crafting.isTradeSkillOpen = nil, false
end

do
    ns.db.queue = {}
    bags = { [CLOTH] = 30, [BOLT] = 1 }
    Queue:Add(BAG_RECIPE, 5)
    check("one bolt already held: fourteen queued", Queued(BOLT_RECIPE, true), 14)
end

ns.db.queue = {}
for _, key in ipairs(GLOBALS) do _G[key] = saved[key] end

print("")
if failed > 0 then
    error(string.format("FAIL -- %d of %d out-of-pocket checks wrong", failed, passed + failed))
end
print(string.format("PASS -- owned materials are free only as far as they go (%d checks)", passed))
