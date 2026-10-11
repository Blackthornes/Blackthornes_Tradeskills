-- Buying many of a material goes up the auction listings, and what was paid
-- is held to what the shopping list had said (a player asked, the owner
-- agreeing 2026-10-11).
--
-- What must hold:
--   1. A scan keeps the first few price steps of other sellers' listings;
--      your own and a lone low listing are left out.
--   2. Twenty with three listed at 10 and the rest at 14 cost 3x10 + 17x14,
--      not 20x10; past the last step the rest cost the last price.
--   3. A browse row keeps the ladder only while its cheapest still matches.
--   4. Units bought since the scan are passed over, as their listings are gone.
--   5. The player's own "use" price is the price of every one; "floor" lifts
--      every step.
--   6. A purchase writes down what it cost, from the gold that left, against
--      the estimate from before the player looked it up; well over it is
--      flagged.
--   7. The shopping list prices the shortfall up the listings and carries
--      what was paid.

-- Tests share one Lua state, so every global replaced here is put back.
local GLOBALS = { "time", "GetMoney", "GetInboxHeaderInfo", "AUCTION_WON_MAIL_SUBJECT",
    "C_AuctionHouse", "GetTime" }
local saved = {}
for _, key in ipairs(GLOBALS) do saved[key] = _G[key] end

local function noop() end

local clock = 100000
time = function() return clock end
GetTime = function() return clock end
local money = 1000000
GetMoney = function() return money end
AUCTION_WON_MAIL_SUBJECT = "Auction won: %s"

local CLOTH, BOLT = 2589, 2996
local BOLT_RECIPE = 2963

local ns = {}
ns.NewModule = function(name) local m = {}; ns[name] = m; return m end
ns.RegisterCommand, ns.RegisterEvent = noop, noop
ns.Print, ns.PrintRaw, ns.Debug, ns.Warn = noop, noop, noop, noop
ns.COLORS = setmetatable({}, { __index = function() return "ffffffff" end })
ns.Util = {
    HasFunction = function(name) return type(_G[name]) == "function" end,
    Count = function(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end,
    FormatMoney = function(c) return tostring(c) end,
}

local settings = { valueOwnedMaterials = true, autoQueueSubCrafts = true,
    suggestOtherCharacters = false, countMailAsStock = true }
local priceTable = {}
ns.Config = {
    Get = function(_, key) return settings[key] end,
    GetCharacterKey = function() return "me" end,
    GetPriceTable = function() return priceTable end,
    GetRealmKey = function() return "Realm" end,
}
ns.db = { queue = {} }

local RECIPES = {
    [BOLT_RECIPE] = { recipeID = BOLT_RECIPE, name = "Bolt of Linen Cloth", outputItemID = BOLT,
        quantityMin = 1, quantityMax = 1, reagents = { { itemID = CLOTH, quantity = 2 } } },
}
local record = {}
ns.Recipes = {
    GetAny = function(_, id) return RECIPES[id], "me" end,
    GetAll = function() return RECIPES end,
    GetCharacterRecord = function() return record end,
}
ns.Inventory = {
    GetBagCount = function() return 0 end,
    GetBankCount = function() return 0 end,
    GetMailCount = function() return 0 end,
    GetOwnedCount = function() return 0 end,
    GetAltTotal = function() return 0 end,
}
local vendorPrice = {}
ns.Vendor = { GetUnitPrice = function(_, id) return vendorPrice[id] end, IsLimited = function() return false end }
ns.Profit = { Analyse = function() return nil end }

assert(loadfile(lfs_cwd .. "/Data/Prices.lua"))("Blackthornes_TS", ns)
assert(loadfile(lfs_cwd .. "/Logic/Cost.lua"))("Blackthornes_TS", ns)
assert(loadfile(lfs_cwd .. "/Logic/Queue.lua"))("Blackthornes_TS", ns)
assert(loadfile(lfs_cwd .. "/Logic/AHBuys.lua"))("Blackthornes_TS", ns)
local Prices, Cost, Queue, AHBuys = ns.Prices, ns.Cost, ns.Queue, ns.AHBuys

local passed, failed = 0, 0

local function check(label, got, want)
    local ok = got == want
    if ok then passed = passed + 1 else failed = failed + 1 end
    print(string.format("  %-60s %-8s %s", label, tostring(got), ok and "ok" or
        ("WRONG, wanted " .. tostring(want))))
end

local function Listing(price, quantity, own)
    return { unitPrice = price, quantity = quantity, isOwn = own or false }
end

-- Three at 10, then the rest at 14: the book the player described.
local function Scan(itemID, listings)
    Prices:CommitScan({ [itemID] = listings }, clock)
end

local function Line(itemID)
    for _, line in ipairs(Queue:GetShoppingList()) do
        if line.itemID == itemID then return line end
    end
end

local function Reset()
    for k in pairs(priceTable) do priceTable[k] = nil end
    record = {}
    ns.db = { queue = {} }
    vendorPrice = {}
    Prices:ForgetBeforeLook()
    AHBuys.awaiting, AHBuys.settling, AHBuys.quote = nil, nil, nil
    clock = 100000
    money = 1000000
end

print("what a scan keeps")
do
    Reset()
    local _, _, _, _, _, _, ladder = Prices:Summarise({
        Listing(10, 2), Listing(10, 1), Listing(12, 4, true), Listing(14, 30),
        Listing(15, 1), Listing(16, 1), Listing(17, 1), Listing(18, 1),
    })
    check("the same price is one step", ladder[2], 3)
    check("your own listing is left out", ladder[3], 14)
    check("five steps at most", #ladder, 10)
    check("the fifth is the last kept", ladder[9], 17)

    local _, _, _, _, _, ignoredLow, lone = Prices:Summarise({
        Listing(1, 1), Listing(10, 5), Listing(11, 5), Listing(12, 5),
    }, 10)
    check("a lone low listing is left out of the market", ignoredLow, 1)
    check("and out of the ladder", lone[1], 10)

    local _, _, _, _, _, _, mineOnly = Prices:Summarise({ Listing(10, 5, true) })
    check("only your own listed: nothing to buy", #mineOnly, 0)
end

print("\ntwenty bought up the listings")
do
    Reset()
    Scan(CLOTH, { Listing(10, 3), Listing(14, 50) })
    check("one costs the cheapest", Prices:GetCostFor(CLOTH, 1), 10)
    check("twenty: 3 at 10 and 17 at 14", Prices:GetCostFor(CLOTH, 20), 3 * 10 + 17 * 14)
    check("past the book, the last price", Prices:GetCostFor(CLOTH, 60), 30 + 50 * 14 + 7 * 14)
    check("three bought since the scan are passed over", Prices:GetCostFor(CLOTH, 2, 3), 28)
    check("the craft's own cost goes up too",
        Cost:GetReagentCost(CLOTH, 20), 3 * 10 + 17 * 14)

    -- A craft that needs 20 of it in one go.
    RECIPES[9999] = { recipeID = 9999, outputItemID = 1, quantityMin = 1, quantityMax = 1,
        reagents = { { itemID = CLOTH, quantity = 20 } } }
    local cost = Cost:GetCraftCost(9999)
    check("a craft needing 20 is priced up the listings", cost.total, 3 * 10 + 17 * 14)
    RECIPES[9999] = nil
end

print("\nbrowse rows and staleness")
do
    Reset()
    Scan(CLOTH, { Listing(10, 3), Listing(14, 50) })
    Prices:Record(CLOTH, 10, 10, 53, clock, 10, nil)
    check("a browse row at the same cheapest keeps the ladder", priceTable[CLOTH].ladder ~= nil, true)
    Prices:Record(CLOTH, 12, 12, 40, clock, 12, nil)
    check("a new cheapest drops it", priceTable[CLOTH].ladder, nil)
    check("and one price stands for all", Prices:GetCostFor(CLOTH, 20), 240)

    Scan(CLOTH, { Listing(10, 3), Listing(14, 50) })
    clock = clock + 3 * 24 * 3600
    check("a stale scan is one price for all", Prices:GetCostFor(CLOTH, 20), 200)
    clock = 100000

    Prices:RecordEmpty(CLOTH, clock)
    check("nothing listed drops it", priceTable[CLOTH].ladder, nil)
end

print("\nyour own price")
do
    Reset()
    Scan(CLOTH, { Listing(10, 3), Listing(14, 50) })
    Prices:SetMine(CLOTH, 20, "use")
    check("use: every one at your price", Prices:GetCostFor(CLOTH, 20), 400)
    Prices:SetMine(CLOTH, 12, "floor")
    check("floor: each step lifted to it", Prices:GetCostFor(CLOTH, 20), 3 * 12 + 17 * 14)
    Prices:SetMine(CLOTH, nil)
end

print("\na purchase and what it cost")
do
    Reset()
    Queue:Add(BOLT_RECIPE, 10)          -- 20 Linen
    Scan(CLOTH, { Listing(10, 3), Listing(14, 50) })
    check("the list prices twenty up the listings", Line(CLOTH).estimatedCost, 268)
    check("each, on average", Line(CLOTH).unitCost, 13)

    -- The player looks it up: someone bought the cheap ones, 30 left at 20.
    Prices:KeepBeforeLook(CLOTH)
    Scan(CLOTH, { Listing(20, 30) })

    AHBuys:OnStartCommodities(CLOTH, 20)
    AHBuys:OnPriceUpdated(20, 400)
    AHBuys:OnConfirmCommodities(CLOTH, 20)
    money = money - 400
    AHBuys:Confirm()

    local paid, units, estimate = AHBuys:PaidFor(CLOTH, 20)
    check("the gold that left is what it cost", paid, 400)
    check("for twenty", units, 20)
    check("held to what the list said before the look", estimate, 268)
    check("well over: flagged", AHBuys.Overpaid(paid, estimate), true)

    local line = Line(CLOTH)
    check("the list carries what was paid", line.paid, 400)
    check("and flags it", line.overpaid, true)
    check("units bought count as gone from the book", AHBuys:BoughtSince(CLOTH, clock), 20)
end

print("\ngold that leaves after the purchase event")
do
    Reset()
    Scan(CLOTH, { Listing(10, 50) })
    AHBuys:OnConfirmCommodities(CLOTH, 5)
    AHBuys:Confirm()
    check("no price yet", AHBuys:GetPaidList(false)[1].paid, nil)
    money = money - 52
    AHBuys:OnMoney()
    check("the gold settles it", AHBuys:GetPaidList(false)[1].paid, 52)
    check("close to the estimate: not flagged", Line(CLOTH) == nil or not Line(CLOTH).overpaid, true)
    check("within a quarter is fine", AHBuys.Overpaid(62, 50), false)
    check("past it is not", AHBuys.Overpaid(63, 50), true)
end

print("\nolder purchases")
do
    Reset()
    AHBuys:GetPaidList(true)[1] = { itemID = CLOTH, quantity = 5, paid = 50, estimate = 50, at = clock - 2 * 24 * 3600 }
    check("yesterday's buys are not today's", AHBuys:PaidFor(CLOTH, 5), nil)
    clock = clock + 8 * 24 * 3600
    AHBuys:Prune()
    check("a week on they are dropped", #AHBuys:GetPaidList(false), 0)
end

for _, key in ipairs(GLOBALS) do _G[key] = saved[key] end

print(("\n%d passed, %d failed"):format(passed, failed))
if failed > 0 then error(("%d ladder check(s) failed"):format(failed)) end
