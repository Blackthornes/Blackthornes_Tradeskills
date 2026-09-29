-- Making a sub-craft that is also on the queue in its own right.
--
-- Queue 5 bolts and a bag that needs 3 more. The queue shows the bag's 3
-- bolts as a derived sub-craft above the 5 you asked for. Make 2 bolts:
-- Crafting:OnBagUpdate used to count the sub-craft down through
-- Queue:SetQuantity, which finds the MANUAL entry for that recipe first, so
-- your 5 became 1 and were then removed as finished. The sub-craft is derived
-- from what is held, so it is re-derived instead of counted down.
--
-- Also: a recipe queued while the profession window was already open had no
-- bag snapshot until the next bag change, so its first craft was missed.

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

local BOLT, BAG, GLOVES = 100, 200, 300
local OIL_A, OIL_B = 400, 401
local recipes = {
    -- Two recipes that make the same item.
    [OIL_A] = { recipeID = OIL_A, outputItemID = 4000, quantityMin = 1, reagents = {} },
    [OIL_B] = { recipeID = OIL_B, outputItemID = 4000, quantityMin = 1, reagents = {} },
    [BOLT] = { recipeID = BOLT, outputItemID = 1000, quantityMin = 1,
        reagents = { { itemID = 10, quantity = 2 } } },
    [BAG] = { recipeID = BAG, outputItemID = 2000, quantityMin = 1,
        reagents = { { itemID = 1000, quantity = 3 } } },
    [GLOVES] = { recipeID = GLOVES, outputItemID = 3000, quantityMin = 1,
        reagents = { { itemID = 1000, quantity = 1 } } },
}
ns.Recipes = {
    Get = function(_, id) return recipes[id] end,
    GetAny = function(_, id) return recipes[id] end,
    GetDisplayLink = function(_, id) return "recipe" .. tostring(id) end,
}

local bags = {}
ns.Inventory = {
    GetBagCount = function(_, itemID) return bags[itemID] or 0 end,
    GetOwnedCount = function(_, itemID) return bags[itemID] or 0 end,
}

-- The cost engine says bolts are cheaper to make than to buy.
ns.Cost = {
    GetCraftCost = function(_, recipeID)
        local recipe = recipes[recipeID]
        local reagents = {}
        for _, reagent in ipairs(recipe.reagents) do
            reagents[#reagents + 1] = {
                itemID = reagent.itemID, quantity = reagent.quantity,
                crafted = reagent.itemID == 1000,
            }
        end
        return { reagents = reagents }
    end,
    FindRecipeForItem = function(_, itemID) return itemID == 1000 and BOLT or nil end,
}
ns.Profit = { Analyse = function() return nil end }

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

local function Manual(recipeID)
    local _, entry = Queue:Find(recipeID, true)
    return entry
end
local function Derived(recipeID)
    for _, entry in ipairs(Queue:GetAll()) do
        if entry.recipeID == recipeID and entry.isDependency then return entry end
    end
end

print("\na sub-craft that is also queued by hand")

Queue:Add(BOLT, 5)
Queue:Add(BAG, 1)
Crafting:RememberOutputs()

check("the bag wants 3 bolts made first", Derived(BOLT) and Derived(BOLT).quantity == 3)
check("and the 5 you asked for are listed too", Manual(BOLT) and Manual(BOLT).quantity == 5)

-- Make two bolts.
bags[1000] = 2
printed = {}
Crafting:OnBagUpdate()

-- The two bolts go to the bag first. They were also taken off the 5 you
-- asked for, so one craft counted twice: 8 bolts wanted, 2 made, 4 left.
check("the bag now wants 1 more bolt made", Derived(BOLT) and Derived(BOLT).quantity == 1)
check("the bolts you asked for are all still to make", Manual(BOLT) and Manual(BOLT).quantity == 5)
check("the bag is still queued", Manual(BAG) and Manual(BAG).quantity == 1)
check("the crafts were reported once", #printed == 1)

-- Two more: one finishes the bag's share, the other is the first of yours.
bags[1000] = 4
printed = {}
Crafting:OnBagUpdate()

check("the bag needs no more bolts", Derived(BOLT) == nil)
check("one of yours counted down", Manual(BOLT) and Manual(BOLT).quantity == 4)

print("\nthe first craft of something queued with the window open")

-- The window is open (the snapshot was taken) and the player queues gloves.
Queue:Add(GLOVES, 2)
bags[3000] = 1
Crafting:OnBagUpdate()

check("the first pair of gloves counted down", Manual(GLOVES) and Manual(GLOVES).quantity == 1)

print("\ntwo recipes that make the same item")

-- One craft used to count down both, since each compared the same bag count.
Queue:Add(OIL_A, 2)
Queue:Add(OIL_B, 2)
Crafting:RememberOutputs()
Crafting.isTradeSkillOpen = true
Crafting:OnCastSucceeded(nil, "player", nil, OIL_B)
bags[4000] = 1
Crafting:OnBagUpdate()

check("the recipe that was cast counted down", Manual(OIL_B) and Manual(OIL_B).quantity == 1)
check("the other one did not", Manual(OIL_A) and Manual(OIL_A).quantity == 2)

print(("\n%d check(s) passed\n"):format(checks))
