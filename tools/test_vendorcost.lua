-- Materials a vendor sells cost the vendor price (a player's report, the owner's
-- call, 2026-10-02), and the queue's total charges bag materials once.
--
-- What must hold:
--   1. A vendor-sold material is costed at the vendor price with no vendor
--      ever opened, from Data/VendorPrices.lua.
--   2. A price seen at a vendor wins over that table.
--   3. The vendor price wins even when someone lists it cheaper; only a
--      vendor seen with limited stock gives way to a cheaper auction.
--   4. The shortfall list prices the same way.
--   5. With "Charge market price" unticked, bag materials are free once
--      across the whole queue, not once per craft queued.

local GLOBALS = { "GetTime", "time" }
local saved = {}
for _, key in ipairs(GLOBALS) do saved[key] = _G[key] end

local function noop() end
GetTime = function() return 100 end
time = function() return 100000 end

local VIAL, THREAD, CLOTH, POTION, BOLT = 3371, 2320, 2589, 118, 2996
local POTION_RECIPE, BOLT_RECIPE = 2330, 2963

local ns = {}
ns.NewModule = function(name) local m = {}; ns[name] = m; return m end
ns.RegisterCommand = noop
ns.RegisterEvent = noop
ns.Print, ns.PrintRaw, ns.Debug, ns.Warn = noop, noop, noop, noop
ns.Util = { HasFunction = function() return false end, Count = function() return 0 end }

local settings = { valueOwnedMaterials = true }
ns.Config = {
    Get = function(_, key) return settings[key] end,
    GetCharacterKey = function() return "me" end,
}

local RECIPES = {
    [POTION_RECIPE] = { recipeID = POTION_RECIPE, name = "Minor Healing Potion", outputItemID = POTION,
        quantityMin = 1, quantityMax = 1, reagents = { { itemID = VIAL, quantity = 1 } } },
    [BOLT_RECIPE] = { recipeID = BOLT_RECIPE, name = "Bolt of Linen Cloth", outputItemID = BOLT,
        quantityMin = 1, quantityMax = 1, reagents = { { itemID = CLOTH, quantity = 2 } } },
}
ns.Recipes = {
    GetAny = function(_, id) return RECIPES[id], "me" end,
    GetAll = function() return {} end,
}

local bags = {}
ns.Inventory = {
    GetBagCount = function(_, id) return bags[id] or 0 end,
    GetBankCount = function() return 0 end,
    GetMailCount = function() return 0 end,
    GetOwnedCount = function(_, id) return bags[id] or 0 end,
    GetAltTotal = function() return 0 end,
}

local LOWEST = { [VIAL] = 50, [THREAD] = 3, [CLOTH] = 10 }
ns.Prices = { GetValue = function(_, id) return LOWEST[id] end }
ns.db = { queue = {} }

assert(loadfile(lfs_cwd .. "/Data/VendorPrices.lua"))("Blackthornes_TS", ns)
assert(loadfile(lfs_cwd .. "/Data/Vendor.lua"))("Blackthornes_TS", ns)
assert(loadfile(lfs_cwd .. "/Logic/Cost.lua"))("Blackthornes_TS", ns)
assert(loadfile(lfs_cwd .. "/Logic/Queue.lua"))("Blackthornes_TS", ns)
local Cost, Queue, Vendor = ns.Cost, ns.Queue, ns.Vendor

local passed, failed = 0, 0
local function check(label, got, want)
    local ok = got == want
    if ok then passed = passed + 1 else failed = failed + 1 end
    print(string.format("  %-58s %-8s %s", label, tostring(got), ok and "ok" or
        ("WRONG, wanted " .. tostring(want))))
end

print("vendor-sold materials")

do
    local price, source = Cost:GetReagentUnitCost(VIAL)
    check("an Empty Vial costs 4c with no vendor seen", price, 4)
    check("and says it comes from a vendor", source, "vendor")

    price = Cost:GetReagentUnitCost(THREAD)
    check("Coarse Thread listed at 3c still costs the shop's 10c", price, 10)

    check("cloth no vendor sells costs the auction price", Cost:GetReagentUnitCost(CLOTH), 10)

    Vendor:GetTable()[VIAL] = { price = 5 }
    check("a price seen at a vendor wins over the table", Cost:GetReagentUnitCost(VIAL), 5)

    Vendor:GetTable()[THREAD] = { price = 10, limited = true }
    check("a limited shop gives way to a cheaper listing", Cost:GetReagentUnitCost(THREAD), 3)

    Vendor:GetTable()[VIAL] = { price = 5, extendedCost = true }
    check("an item bought with tokens has no gold price", Vendor:GetUnitPrice(VIAL), nil)
    ns.db.vendorPrices = {}

    local short = Cost:GetShortfall(POTION_RECIPE, 3)
    check("the shortfall prices vials at the vendor too", short[1].unitCost, 4)
    check("three of them", short[1].estimatedCost, 12)
end

print("")
print("the queue's total with bag materials free")

do
    -- Profit as the real Analyse works it out: sold for 100c, minus cost.
    ns.Profit = { Analyse = function(_, recipeID)
        local cost = Cost:GetCraftCost(recipeID)
        return { priceable = true, totalCost = cost.total, profit = 100 - cost.total }
    end }

    settings.valueOwnedMaterials = false
    bags = { [CLOTH] = 4 }
    ns.db.queue = { { recipeID = BOLT_RECIPE, quantity = 5 } }

    local costs = Queue:GetEntryCosts()
    local entry = ns.db.queue[1]
    -- Ten cloth for five bolts, four of them held: six bought at 10c.
    check("five bolts with four cloth held cost six cloth", costs[entry].cost, 60)
    check("and earn 500 less that", costs[entry].profit, 440)

    local totals = Queue:GetTotals()
    check("the footer agrees", totals.cost, 60)

    settings.valueOwnedMaterials = true
    costs = Queue:GetEntryCosts()
    check("with Charge market price ticked, all ten are charged", costs[entry].cost, 100)
    settings.valueOwnedMaterials = false
end

print("")
print("the shopping list never sends a stocked vendor item to the auction house")

do
    -- Coarse Thread: the shop's 10c, listed at 3c. A vial: 4c at the shop,
    -- 50c listed. Red Dye's case (the owner, 2026-10-13).
    ns.db.vendorPrices = {}
    bags = {}
    ns.db.queue = { { recipeID = POTION_RECIPE, quantity = 3 } }
    check("thread from the table is kept at the vendor", Vendor:KeepsInStock(THREAD), true)
    check("cloth no vendor sells is not", Vendor:KeepsInStock(CLOTH), false)

    local function Line(id)
        for _, line in ipairs(Queue:BuildShoppingList()) do
            if line.itemID == id then return line end
        end
    end
    RECIPES[POTION_RECIPE].reagents = { { itemID = THREAD, quantity = 1 } }

    local line = Line(THREAD)
    check("thread listed for less still goes to the vendor", line and line.source, "vendor")
    check("and claims no saving for it", line and (line.savingTotal or 0), 0)

    Vendor:GetTable()[THREAD] = { price = 10, limited = true }
    check("a shop seen with limited stock is not kept", Vendor:KeepsInStock(THREAD), false)
    line = Line(THREAD)
    check("so the cheaper listing wins there", line and line.source, "auction")
    ns.db.vendorPrices = {}

    settings.vendorItemsOnAuction = true
    check("ticked, the auction house is offered again", Vendor:KeepsInStock(THREAD), false)
    line = Line(THREAD)
    check("and the cheaper listing wins", line and line.source, "auction")
    settings.vendorItemsOnAuction = nil

    RECIPES[POTION_RECIPE].reagents = { { itemID = VIAL, quantity = 1 } }
end

ns.db.queue = {}
for _, key in ipairs(GLOBALS) do _G[key] = saved[key] end

print("")
if failed > 0 then
    error(string.format("FAIL -- %d of %d vendor cost checks wrong", failed, passed + failed))
end
print(string.format("PASS -- vendor-sold materials cost the vendor price (%d checks)", passed))
