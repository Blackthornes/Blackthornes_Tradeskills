-- What a craft is worth when the auction house has never priced it.
--
-- The house rule: no auction price for a craft means its price is a markup over
-- what its materials are worth -- 50% by default, adjustable in Settings.
--
-- The whole point of the rule is that it produces a number where there was
-- none, so the things worth guarding are the edges around it: that a real
-- scanned price always beats it, that it never becomes one, that an item
-- auction still gets a price the server will take, and that the materials are
-- valued at what they are worth rather than at what is left to pay for them.

local ns = {}
ns.COLORS = setmetatable({}, {__index = function() return "ffffffff" end})
ns.NewModule = function(name) local m = {}; ns[name] = m; return m end
ns.RegisterCommand = function() end
ns.RegisterEvent = function() end
ns.Print, ns.PrintRaw, ns.Debug, ns.Warn = function() end, function() end, function() end, function() end

-- Core/Util.lua builds a worker frame at load time; it only has to exist.
CreateFrame = function()
    local frame = {}
    for _, name in ipairs({ "SetScript", "Show", "Hide", "SetPoint", "SetSize" }) do
        frame[name] = function() end
    end
    return frame
end

GetTime = function() return os.clock() end
time = time or os.time

--------------------------------------------------------------------------------
-- The world this test describes
--------------------------------------------------------------------------------

local POTION = 3928         -- a commodity: sells by the unit, takes copper
local BELT   = 7357         -- an item auction: whole silver only
local HERB   = 2453         -- a reagent
local VIAL   = 3371         -- a second reagent

local POTION_RECIPE, BELT_RECIPE = 101, 102

local settings, bags, vendorSells

local recipes = {
    [POTION_RECIPE] = {
        recipeID = POTION_RECIPE, name = "Potion", outputItemID = POTION,
        quantityMin = 1, quantityMax = 1,
        reagents = { { itemID = HERB, quantity = 2 }, { itemID = VIAL, quantity = 1 } },
    },
    [BELT_RECIPE] = {
        recipeID = BELT_RECIPE, name = "Belt", outputItemID = BELT,
        quantityMin = 1, quantityMax = 1,
        reagents = { { itemID = HERB, quantity = 3 } },
    },
}

ns.Config = {
    Get = function(_, key) return settings[key] end,
    GetCharacterKey = function() return "Tester-Realm" end,
}

ns.Recipes = {
    GetAll = function() return recipes end,
    GetAny = function(_, recipeID) return recipes[recipeID], "Tester-Realm" end,
    Get = function(_, recipeID) return recipes[recipeID] end,
    GetCharacterName = function() return "Tester" end,
}

ns.Inventory = {
    GetBagCount = function(_, itemID) return bags[itemID] or 0 end,
    GetCharacterBagCount = function(_, _, itemID) return bags[itemID] or 0 end,
    GetBankCount = function() return 0 end,
    GetOwnedCount = function(_, itemID) return bags[itemID] or 0 end,
    GetAltTotal = function() return 0 end,
}

-- What a merchant CHARGES for a reagent. Nothing is sold by one here, so the
-- reagent prices below are the auction house's alone.
ns.Vendor = { GetUnitPrice = function() return nil end }

-- Commodity status: true, false, or nil for never held and never searched.
local commodityStatus = {}
ns.Scanner = {
    GetCommodityStatus = function(_, itemID) return commodityStatus[itemID] end,
    IsCommodity = function(_, itemID) return commodityStatus[itemID] == true end,
}

ns.Posting = { GetCachedUnitDeposit = function() return nil end }

ns.Auctions = {
    GetRoom = function() return nil, 0, 0, 0, nil, 0 end,
    GetPostedCount = function() return 0 end,
}

-- What a vendor PAYS, read by Util.GetVendorSellPrice through the client's
-- own item cache. sellPrice is the eleventh return.
C_Item = {
    GetItemInfo = function(itemID)
        return "item", "link", 1, 1, 1, "", "", 1, "", "", vendorSells[itemID]
    end,
}

local priceTable = {}
ns.Config.GetPriceTable = function() return priceTable end

assert(loadfile(lfs_cwd .. "/Core/Util.lua"))("Blackthornes_TS", ns)
assert(loadfile(lfs_cwd .. "/Data/Prices.lua"))("Blackthornes_TS", ns)
assert(loadfile(lfs_cwd .. "/Logic/Cost.lua"))("Blackthornes_TS", ns)
assert(loadfile(lfs_cwd .. "/Logic/Profit.lua"))("Blackthornes_TS", ns)

local Util, Prices, Cost, Profit = ns.Util, ns.Prices, ns.Cost, ns.Profit

local function Reset()
    settings = {
        undercutCopper = 1,
        auctionCut = 0.05,
        expectedRelists = 1,
        minProfit = 0,
        staleAfterSeconds = 48 * 3600,
        valueOwnedMaterials = true,
        unscannedMarkupPercent = 50,
        priceUnscannedCrafts = true,
    }

    bags = {}
    vendorSells = {}
    Util._ForgetItemMemo()
    commodityStatus = { [POTION] = true, [BELT] = false }

    for key in pairs(priceTable) do priceTable[key] = nil end

    Cost:InvalidateIndex()
end

--------------------------------------------------------------------------------

local failures = 0

local function check(label, got, expected)
    local ok = got == expected
    if not ok then failures = failures + 1 end
    print(("  %-58s %-10s %s"):format(label, tostring(got), ok and "ok" or
        ("FAILED, expected " .. tostring(expected))))
end

--------------------------------------------------------------------------------
print("")
print("a craft nothing has ever listed")

Reset()
-- 2 herbs at 40c and a vial at 20c: 100c of materials for one potion.
Prices:Record(HERB, 40, 40, 50, time(), 40, nil)
Prices:Record(VIAL, 20, 20, 50, time(), 20, nil)

do
    local price, basis, why = Profit:ChoosePostPrice(POTION)

    check("prices it at 50% over its materials", price, 150)
    check("and says the price was derived", basis, "derived")
    check("with a sentence saying where it came from", type(why), "string")
    check("nothing was written into the price database", Prices:Get(POTION), nil)
    check("so the item still has no market value", Prices:GetValue(POTION, "market"), nil)
end

do
    -- The whole reason this is a setting: 50% is a starting point, not a law.
    settings.unscannedMarkupPercent = 100
    check("markup at 100%: doubles the material value",
        (Profit:ChoosePostPrice(POTION)), 200)

    settings.unscannedMarkupPercent = 0
    check("markup at 0%: prices at material value exactly",
        (Profit:ChoosePostPrice(POTION)), 100)

    settings.unscannedMarkupPercent = 50
end

do
    settings.priceUnscannedCrafts = false
    local price, basis = Profit:ChoosePostPrice(POTION)
    check("switched off: back to no price at all", price, nil)
    check("switched off: and no basis", basis, nil)
    settings.priceUnscannedCrafts = true
end

--------------------------------------------------------------------------------
print("")
print("a real price always wins")

do
    -- Scanned once, a long time ago. Stale is not the same as absent: it is
    -- still the only thing anybody has observed about what this sells for.
    Prices:Record(POTION, 500, 500, 3, time() - (30 * 24 * 3600), nil, nil)

    local price, basis = Profit:ChoosePostPrice(POTION)
    check("a stale market price is used, not the estimate", price, 500)
    check("basis is market", basis, "market")
    check("the price is genuinely stale", Prices:IsStale(POTION), true)
end

do
    -- A rival appears. Nothing about the estimate survives that.
    Prices:Record(POTION, 500, 480, 10, time(), 480, nil)

    local price, basis = Profit:ChoosePostPrice(POTION)
    check("a rival listing is undercut as always", price, 479)
    check("basis is undercut", basis, "undercut")
end

do
    -- An empty search clears the book but keeps the market value, so an item
    -- the addon has seen before never falls back to the estimate.
    Prices:RecordEmpty(POTION)

    local price, basis = Profit:ChoosePostPrice(POTION)
    check("an emptied book still prices at market", price, 500)
    check("basis is market, not derived", basis, "market")
end

--------------------------------------------------------------------------------
print("")
print("an item auction still gets a price the server takes")

Reset()
Prices:Record(HERB, 40, 40, 50, time(), 40, nil)

do
    -- 3 herbs at 40c is 120c; 50% over that is 180c, which PostItem would
    -- swallow silently because of the 80 copper on the end.
    local price, basis = Profit:ChoosePostPrice(BELT)

    check("the estimate is rounded to whole silver", price, 200)
    check("basis is still derived", basis, "derived")
    check("and it is a price an item auction accepts", Util.IsWholeSilver(price), true)

    -- Rounded UP, unlike an undercut. Down would be 1s, under the 1s 20c the
    -- materials cost, and Posting refuses to list below material cost -- so
    -- the estimate would have produced a price it then would not use.
    check("rounded up, so it stays above material cost", price > 120, true)
end

--------------------------------------------------------------------------------
print("")
print("the floors that already exist still hold")

Reset()
Prices:Record(HERB, 40, 40, 50, time(), 40, nil)
Prices:Record(VIAL, 20, 20, 50, time(), 20, nil)

do
    -- A vendor pays 300c for the potion. Listing it at 150c would be worse
    -- than walking to that vendor, and Posting's own floor would refuse the
    -- listing outright -- so the estimate would be a number nothing could be
    -- done with.
    vendorSells[POTION] = 300

    check("never estimated below what a vendor pays",
        (Profit:ChoosePostPrice(POTION)), 300)

    vendorSells[POTION] = 100
    Util._ForgetItemMemo()
    check("a vendor paying less changes nothing",
        (Profit:ChoosePostPrice(POTION)), 150)
end

--------------------------------------------------------------------------------
print("")
print("materials are valued at what they are worth")

Reset()
Prices:Record(HERB, 40, 40, 50, time(), 40, nil)
Prices:Record(VIAL, 20, 20, 50, time(), 20, nil)

do
    -- Cash-out-of-pocket: reagents already in the bags cost nothing to use.
    -- That is a fair way to read what a craft will cost you today, and a
    -- terrible way to decide what the result is worth to somebody else.
    settings.valueOwnedMaterials = false
    bags[HERB] = 100
    bags[VIAL] = 100

    check("owning the materials does not make the craft free",
        (Profit:ChoosePostPrice(POTION)), 150)

    -- The costing itself still answers the question it was asked.
    local cost = Cost:GetCraftCost(POTION_RECIPE)
    check("while the craft still costs nothing out of pocket", cost.total, 0)
end

do
    -- A reagent nobody has priced leaves nothing to derive from. A guess on
    -- top of a guess is worse than no number at all.
    Reset()
    Prices:Record(HERB, 40, 40, 50, time(), 40, nil)

    local price, basis = Profit:ChoosePostPrice(POTION)
    check("an unpriced reagent means no estimate", price, nil)
    check("and no basis", basis, nil)
end

do
    -- Nothing this account can make: there are no materials to price it off.
    Reset()
    local price = Profit:ChoosePostPrice(HERB)
    check("a gathered item is not given an estimate", price, nil)
end

--------------------------------------------------------------------------------
print("")
print("the Profit tab reads it as an estimate")

Reset()
Prices:Record(HERB, 40, 40, 50, time(), 40, nil)
Prices:Record(VIAL, 20, 20, 50, time(), 20, nil)

do
    local analysis = Profit:Analyse(POTION_RECIPE)

    check("the craft is priceable now", analysis.priceable, true)
    check("and flagged as an estimate", analysis.priceDerived, true)
    check("revenue is the estimate", analysis.revenue, 150)
    check("profit is what is left after the cut", analysis.profit, 150 - 7.5 - 100)
end

do
    -- Analyse hands its own costing to the estimate so the reagent tree is
    -- not walked twice. That costing is the cash-out-of-pocket one when the
    -- setting says so, and must not be used here -- the same check as above,
    -- but through the path the Profit tab actually takes.
    settings.valueOwnedMaterials = false
    bags[HERB] = 100
    bags[VIAL] = 100

    local analysis = Profit:Analyse(POTION_RECIPE)

    check("the tab's estimate is not the out-of-pocket cost", analysis.revenue, 150)
    check("while its cost column still says out of pocket", analysis.totalCost, 0)

    settings.valueOwnedMaterials = true
    bags = {}
end

do
    Prices:Record(POTION, 500, 500, 10, time(), nil, nil)

    local analysis = Profit:Analyse(POTION_RECIPE)
    check("once scanned, the flag is gone", analysis.priceDerived, nil)
end

--------------------------------------------------------------------------------
print("")
if failures > 0 then
    error(("%d derived-price check(s) failed"):format(failures), 0)
end
print("PASS -- a craft with no auction price is valued off its materials, and says so")
print("")
