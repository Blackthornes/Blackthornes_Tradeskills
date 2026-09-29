-- What to charge when you are the only seller.
--
-- Trent, 2026-09-24, about Woolen Reagent Bags: "if there are no items of
-- something i'm selling on the AH the selling price should get pushed up to
-- 50% over material price ... i'm currently the only one selling but the
-- addon just keeps recommending market value."
--
-- Market value counts your own listings, so with nobody competing it is
-- mostly a reflection of what you charged last time. Holding at it means
-- charging that forever. The rule is the same markup the never-scanned case
-- uses, and it only ever pushes the price up: a market value already above it
-- is a real observation of what these sell for, and giving that up would be
-- cutting your own price for nothing.

local ns = {}
ns.COLORS = setmetatable({}, {__index = function() return "ffffffff" end})
ns.NewModule = function(name) local m = {}; ns[name] = m; return m end
ns.RegisterCommand = function() end
ns.RegisterEvent = function() end
ns.Print, ns.PrintRaw, ns.Debug, ns.Warn = function() end, function() end, function() end, function() end

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

local BAG   = 4245          -- Woolen Reagent Bag: an item auction
local CLOTH = 2997          -- Bolt of Woolen Cloth, a commodity he also makes
local WOOL  = 2592          -- the reagent under both

local BAG_RECIPE, CLOTH_RECIPE = 201, 202

local settings, bags, vendorSells

local recipes = {
    [BAG_RECIPE] = {
        recipeID = BAG_RECIPE, name = "Woolen Reagent Bag", outputItemID = BAG,
        quantityMin = 1, quantityMax = 1,
        reagents = { { itemID = WOOL, quantity = 10 } },
    },
    [CLOTH_RECIPE] = {
        recipeID = CLOTH_RECIPE, name = "Bolt of Woolen Cloth", outputItemID = CLOTH,
        quantityMin = 1, quantityMax = 1,
        reagents = { { itemID = WOOL, quantity = 3 } },
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

ns.Vendor = { GetUnitPrice = function() return nil end }

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
    commodityStatus = { [BAG] = false, [CLOTH] = true }

    for key in pairs(priceTable) do priceTable[key] = nil end

    Cost:InvalidateIndex()
end

--- One scan of a book that holds only your own listings.
local function ScanWithOnlyMine(itemID, myPrice, quantity)
    -- marketValue, minBuyout, quantity, scannedAt, rivalMin, ownMin: rivalMin
    -- nil is what Summarise reports when every listing is yours.
    Prices:Record(itemID, myPrice, myPrice, quantity or 2, time(), nil, myPrice)
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
print("the Woolen Reagent Bag, as he described it")

Reset()
-- 10 wool at 50c is 5s of materials, so the markup price is 7s 50c, which on
-- an item auction rounds up to 8s.
Prices:Record(WOOL, 50, 50, 200, time(), 50, nil)
ScanWithOnlyMine(BAG, 600)      -- his own listings, at 6s

do
    local price, basis, why = Profit:ChoosePostPrice(BAG)

    check("no rival: priced off materials, not market", price, 800)
    check("and the basis says so", basis, "uncontested")
    check("with a sentence naming the markup", type(why), "string")
    check("never the market value it used to recommend", price ~= 600, true)
    check("a price an item auction accepts", Util.IsWholeSilver(price), true)
end

do
    -- The knob is the same one the never-scanned case uses.
    settings.unscannedMarkupPercent = 100
    check("markup at 100%: doubles the material value",
        (Profit:ChoosePostPrice(BAG)), 1000)

    settings.priceUnscannedCrafts = false
    local price, basis = Profit:ChoosePostPrice(BAG)
    check("switched off: back to market value", price, 600)
    check("switched off: basis is market", basis, "market")

    Reset()
    Prices:Record(WOOL, 50, 50, 200, time(), 50, nil)
end

--------------------------------------------------------------------------------
print("")
print("only ever upwards")

do
    -- These have sold well above what they cost to make. That is a real
    -- observation, and cutting to the markup would be giving gold away.
    ScanWithOnlyMine(BAG, 5000)

    local price, basis = Profit:ChoosePostPrice(BAG)
    check("a market value above the markup is kept", price, 5000)
    check("and the basis is market", basis, "market")
end

do
    -- A rival appears at 60s. Nothing about the markup survives that: there
    -- is someone to undercut again, and undercutting by the silver an item
    -- auction forces still clears the minimum profit.
    Prices:Record(BAG, 5000, 6000, 5, time(), 6000, 5000)

    local price, basis = Profit:ChoosePostPrice(BAG)
    check("a rival is undercut, not marked up", price, 5900)
    check("and the basis is undercut", basis, "undercut")
end

do
    -- A rival below what the bag costs to make. The existing rule holds: a
    -- whole silver is not given away when the sale would not clear the
    -- minimum profit, so it matches rather than chasing them down.
    Prices:Record(BAG, 5000, 400, 5, time(), 400, 5000)

    local price, basis = Profit:ChoosePostPrice(BAG)
    check("a rival under material cost is matched", price, 400)
    check("and the basis is match", basis, "match")
end

--------------------------------------------------------------------------------
print("")
print("a commodity you are alone on")

Reset()
Prices:Record(WOOL, 50, 50, 200, time(), 50, nil)
ScanWithOnlyMine(CLOTH, 100)    -- 3 wool is 1s 50c of materials

do
    -- Commodities take copper, so no rounding: 150 * 1.5 = 225.
    local price, basis = Profit:ChoosePostPrice(CLOTH)

    check("commodity: the exact markup, copper and all", price, 225)
    check("commodity: basis is uncontested", basis, "uncontested")
end

--------------------------------------------------------------------------------
print("")
print("what has to keep working")

Reset()
Prices:Record(WOOL, 50, 50, 200, time(), 50, nil)

do
    -- Never scanned at all is still its own case, with its own label: there
    -- is no age and no confidence behind it, unlike an uncontested price.
    local price, basis = Profit:ChoosePostPrice(BAG)
    check("never scanned: still the derived basis", basis, "derived")
    check("never scanned: same number", price, 800)
end

do
    -- An empty book on an item that has sold before. The markup applies --
    -- nobody is competing -- but the market value it beat was real.
    ScanWithOnlyMine(BAG, 600)
    Prices:RecordEmpty(BAG)

    local price, basis = Profit:ChoosePostPrice(BAG)
    check("empty book: marked up over materials", price, 800)
    check("empty book: basis is uncontested", basis, "uncontested")
    check("empty book: market value survived", Prices:GetValue(BAG, "market"), 600)
end

do
    -- Nothing may be written back. The price the addon works out must not
    -- return later looking like something the auction house said.
    check("the market value is untouched by any of this",
        Prices:GetValue(BAG, "market"), 600)
    check("and no rival was invented", Prices:GetValue(BAG, "rival"), nil)
end

do
    -- A reagent nobody has priced leaves nothing to mark up, so the price
    -- falls back to what the book last said rather than disappearing.
    Reset()
    ScanWithOnlyMine(BAG, 600)

    local price, basis = Profit:ChoosePostPrice(BAG)
    check("unpriced materials: market value still used", price, 600)
    check("unpriced materials: basis is market", basis, "market")
end

--------------------------------------------------------------------------------
print("")
print("the Profit tab reads it correctly")

Reset()
Prices:Record(WOOL, 50, 50, 200, time(), 50, nil)
ScanWithOnlyMine(BAG, 600)

do
    local analysis = Profit:Analyse(BAG_RECIPE)

    check("flagged as uncontested", analysis.priceUncontested, true)
    check("not flagged as never scanned", analysis.priceDerived, nil)
    check("revenue is the marked-up price", analysis.revenue, 800)
    check("the scan behind it is still real", analysis.age ~= nil, true)
end

--------------------------------------------------------------------------------
print("")
print("a lone low listing does not set the material cost")

-- Trent, 2026-09-26: a single listing under a third of the next one up, and
-- of market when known, is ignored; two or more low listings count. Material
-- cost and the only-seller price follow the same rule the undercut does.
local function ScanWool(prices)
    local listings = {}
    for _, price in ipairs(prices) do
        listings[#listings + 1] = { unitPrice = price, quantity = 20 }
    end
    local market, min, quantity, rival, own, ignored =
        Prices:Summarise(listings, Prices:GetValue(WOOL, "market"))
    Prices:Record(WOOL, market, min, quantity, time(), rival, own, ignored)
end

Reset()
Prices:Record(WOOL, 50, 50, 200, time(), 50, nil)
ScanWool({ 5, 50, 50, 50 })
ScanWithOnlyMine(BAG, 600)

do
    check("the lone 5c wool was seen as one", Prices:Get(WOOL).ignoredLow, 5)
    check("wool costs the 50c the rest are at", (Cost:GetReagentUnitCost(WOOL)), 50)

    local price, basis = Profit:ChoosePostPrice(BAG)
    check("only seller: marked up off 50c wool", price, 800)
    check("only seller: basis is uncontested", basis, "uncontested")
    check("the Profit tab costs it off 50c wool", Profit:Analyse(BAG_RECIPE).cost.total, 500)
end

Reset()
Prices:Record(WOOL, 50, 50, 200, time(), 50, nil)
ScanWool({ 5, 5, 50, 50 })

do
    check("two low listings are a real price", Prices:Get(WOOL).ignoredLow, nil)
    check("and wool costs 5c", (Cost:GetReagentUnitCost(WOOL)), 5)
end

--------------------------------------------------------------------------------
print("")
if failures > 0 then
    error(("%d uncontested-price check(s) failed"):format(failures), 0)
end
print("PASS -- with nobody competing, the price rises to materials plus the markup")
print("")
