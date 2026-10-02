-- Regression test for the vendor purchase loop.
--
-- The bug: BuyStep decided how much to buy from live bag counts, then fired
-- again 0.2s later. Bag updates are asynchronous, so the second pass could
-- still see the pre-purchase count and buy the same item twice. Needing 1
-- Coarse Thread bought 2.
--
-- The test simulates the worst case: bag counts that never update at all.

local ns = {}

ns.COLORS = setmetatable({}, { __index = function() return "ffffffff" end })
ns.Print, ns.PrintRaw, ns.Debug, ns.Warn =
    function() end, function() end, function() end, function() end

ns.Util = {
    Count = function(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end,
    FormatMoney = function(c) return tostring(c) end,
    GetItemLabel = function(i) return "item" .. tostring(i) end,
    HasFunction = function(path) return path == "BuyMerchantItem" end,
}

ns.NewModule = function(name)
    local m = {}
    ns[name] = m
    return m
end
ns.RegisterCommand = function() end
ns.RegisterEvent = function() end

-- Purchases recorded here.
local purchases = {}
_G = _G or {}
BuyMerchantItem = function(index, amount)
    purchases[#purchases + 1] = { index = index, amount = amount }
end

GetMoney = function() return 100000 end
time = os.time

-- Run timers immediately: this is the harshest possible schedule, giving bag
-- counts no chance at all to catch up.
C_Timer = {
    After = function(_, fn) fn() end,
}

-- The shortfall NEVER decreases, as if BAG_UPDATE never arrived.
local STALE_SHORTFALL = 1

ns.Queue = {
    GetShoppingList = function()
        return { { itemID = 2320, shortfall = STALE_SHORTFALL } }
    end,
    Count = function() return 1 end,
}

ns.Inventory = { GetOwnedCount = function() return 1 end }
ns.Cost = { InvalidateIndex = function() end }
ns.Recipes = {}

local chunk = assert(loadfile(lfs_cwd .. "/Data/Vendor.lua"))
chunk("Blackthornes_TS", ns)

local Vendor = ns.Vendor

-- One Coarse Thread short, vendor sells it singly.
Vendor.isMerchantOpen = true
Vendor.merchantItems = {
    [2320] = { index = 3, price = 10, stack = 1, numAvailable = -1, extendedCost = false },
}

Vendor:BuyNeeded()

local total = 0
for _, purchase in ipairs(purchases) do
    total = total + purchase.amount
end

print("")
print(("purchase calls : %d"):format(#purchases))
print(("units bought   : %d"):format(total))
print(("expected       : 1"))

if total == 1 then
    print("PASS -- bought exactly what was short, despite stale bag counts")
else
    print("FAIL -- over-bought; the purchase tally is not holding")
end
print("")

--------------------------------------------------------------------------------
-- Vendor or auction house, whichever is cheaper (item 6, 2026-09-29).
--
-- The Buy materials button bought every shortfall the vendor stocked, even
-- when the auction house had the same material for less. A material that is
-- cheaper there, with enough listed to cover what is short, is left for the
-- auction house. With nothing listed, or too few, the vendor still buys it.
--------------------------------------------------------------------------------

local function expect(label, got, want)
    if got ~= want then
        error(("%s: expected %s, got %s"):format(label, tostring(want), tostring(got)), 2)
    end
    print(("  ok  %s"):format(label))
end

-- The real reading of the book, borrowed from Data/Prices.lua, so the lone
-- low rule is the one the rest of the addon uses.
local LowestListed, Summarise
do
    local module
    local priceNs = {
        NewModule = function() module = {}; return module end,
        Util = {}, RegisterCommand = function() end,
    }
    assert(loadfile(lfs_cwd .. "/Data/Prices.lua"))("Blackthornes_TS", priceNs)
    LowestListed = module.LowestListed
    Summarise = function(book) return module:Summarise(book, nil) end
end

local THREAD, VIAL, FLUX = 2320, 3371, 2880
local records = {}
ns.Prices = {
    Get = function(_, itemID) return records[itemID] end,
    LowestListed = LowestListed,
}

local shopping = {
    { itemID = THREAD, shortfall = 10 },
    { itemID = VIAL,   shortfall = 5 },
    { itemID = FLUX,   shortfall = 4 },
}
ns.Queue.GetShoppingList = function() return shopping end

Vendor.merchantItems = {
    [THREAD] = { index = 1, price = 10, stack = 1, numAvailable = -1, extendedCost = false },
    [VIAL]   = { index = 2, price = 20, stack = 1, numAvailable = -1, extendedCost = false },
    [FLUX]   = { index = 3, price = 100, stack = 1, numAvailable = -1, extendedCost = false },
}

print("")
print("vendor or auction house")

-- Thread: 4c each on the auction house, 40 listed. Cheaper there.
records[THREAD] = { market = 6, min = 4, rivalMin = 4, quantity = 40 }
-- Vials: cheaper there, but only 2 listed against 5 short.
records[VIAL] = { market = 20, min = 5, rivalMin = 5, quantity = 2 }
-- Flux: one lone listing at 10c, the rest at 150c. The lone one is left out,
-- so the vendor's 100c is cheaper.
records[FLUX] = { market = 150, min = 10, rivalMin = 150, ignoredLow = 10, quantity = 30 }

local lines, _, cheaper = Vendor:GetNeeded()
local byItem = {}
for _, line in ipairs(lines) do byItem[line.itemID] = line end

expect("thread is left for the auction house", byItem[THREAD], nil)
expect("and counted as cheaper there", cheaper, 1)
expect("vials too few listed: bought from the vendor", byItem[VIAL] and byItem[VIAL].amount, 5)
expect("flux beside a lone low listing: bought from the vendor", byItem[FLUX] and byItem[FLUX].amount, 4)

-- Nothing listed: market value is no price anyone can buy at.
records[THREAD] = { market = 2, quantity = 0 }
lines = Vendor:GetNeeded()
byItem = {}
for _, line in ipairs(lines) do byItem[line.itemID] = line end
expect("nothing listed: the vendor buys it", byItem[THREAD] and byItem[THREAD].amount, 10)

-- A tie goes to the vendor.
records[THREAD] = { market = 10, min = 10, rivalMin = 10, quantity = 40 }
lines = Vendor:GetNeeded()
byItem = {}
for _, line in ipairs(lines) do byItem[line.itemID] = line end
expect("same price: the vendor buys it", byItem[THREAD] and byItem[THREAD].amount, 10)

-- The only cheaper listing is his own: nothing to buy there, so the vendor.
records[THREAD] = { market = 10, min = 4, ownMin = 4, quantity = 40 }
lines = Vendor:GetNeeded()
byItem = {}
for _, line in ipairs(lines) do byItem[line.itemID] = line end
expect("his own cheaper listing: the vendor buys it", byItem[THREAD] and byItem[THREAD].amount, 10)

-- A rival is cheaper, but most of what is listed is his own and the rest
-- does not cover the shortfall.
records[THREAD] = { market = 6, min = 4, rivalMin = 4, ownMin = 5, quantity = 40 }
ns.Auctions = { GetPostedCount = function(_, itemID) return itemID == THREAD and 35 or 0 end }
lines = Vendor:GetNeeded()
byItem = {}
for _, line in ipairs(lines) do byItem[line.itemID] = line end
expect("his own units do not cover the shortfall", byItem[THREAD] and byItem[THREAD].amount, 10)
ns.Auctions = nil

-- A few cheap units in front of a shelf of dearer ones (2026-10-02). The
-- cheapest posting was under the vendor's 10c and the whole book covered
-- what was short, so all 20 thread went to the auction house: 3 at 8c and
-- 17 at 15c, 279c against 200c here. The market value has to be under the
-- vendor price too.
local function ThreadFromBook(book)
    local market, min, quantity, rivalMin, ownMin, ignoredLow = Summarise(book)
    records[THREAD] = { market = market, min = min, quantity = quantity,
        rivalMin = rivalMin, ownMin = ownMin, ignoredLow = ignoredLow }
    lines, _, cheaper = Vendor:GetNeeded()
    byItem = {}
    for _, line in ipairs(lines) do byItem[line.itemID] = line end
end

shopping[1].shortfall = 20

ThreadFromBook({
    { unitPrice = 8, quantity = 3, isOwn = false },
    { unitPrice = 15, quantity = 100, isOwn = false },
    { unitPrice = 15, quantity = 100, isOwn = false },
})
expect("3 at 8c before 200 at 15c: the vendor buys all 20", byItem[THREAD] and byItem[THREAD].amount, 20)
expect("and the tooltip does not call it cheaper there", cheaper, 0)

ThreadFromBook({
    { unitPrice = 8, quantity = 2, isOwn = false },
    { unitPrice = 8, quantity = 2, isOwn = false },
    { unitPrice = 60, quantity = 100, isOwn = false },
    { unitPrice = 62, quantity = 100, isOwn = false },
})
expect("4 at 8c before 200 at 60c: the vendor buys all 20", byItem[THREAD] and byItem[THREAD].amount, 20)

-- Plenty under the vendor price: still left for the auction house.
ThreadFromBook({
    { unitPrice = 6, quantity = 40, isOwn = false },
    { unitPrice = 15, quantity = 100, isOwn = false },
})
expect("40 at 6c: left for the auction house", byItem[THREAD], nil)
expect("and counted as cheaper there", cheaper, 1)

shopping[1].shortfall = 10

ns.Prices = nil
