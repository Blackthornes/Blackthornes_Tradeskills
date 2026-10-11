-- A listing you bought, or a search that found none, stops being offered.
--
-- A player bought the last Blush Ember Ring at its price, and searched for
-- another and got "no items found", and the Disenchanting tab went on
-- offering it at the old price until the next scan. What this pins down:
--
--   * Prices:NoteBought takes what was bought off the record (the ladder's
--     next step, or no price at all), writes no history and leaves a record
--     read after the buy alone;
--   * Prices:TouchedSince names the items changed, or nil when it cannot;
--   * a search by an item's own name whose whole answer leaves it out is
--     recorded as not listed, whoever typed it; a filtered search, a later
--     query or an answer still coming in is not;
--   * AHBuys:Confirm tells Prices what was bought.

local ns = {}
ns.COLORS = setmetatable({}, { __index = function() return "ffffffff" end })
ns.NewModule = function(name) local m = {}; ns[name] = m; return m end
ns.RegisterCommand = function() end
ns.RegisterEvent = function() return true end
ns.Print, ns.PrintRaw, ns.Debug, ns.Warn = function() end, function() end, function() end, function() end

local hasFull = true

ns.Util = {
    Clamp = function(v, l, h) return math.max(l, math.min(h, v)) end,
    Count = function(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end,
    Comma = function(n) return tostring(n) end,
    FormatMoney = function(c) return tostring(c) end,
    FormatAge = function() return "" end,
    FormatAgeAgo = function() return "just now" end,
    GetItemLabel = function(i) return "item" .. tostring(i) end,
    GetMaxStackSize = function() return 20 end,
    UnitPriceFromStack = function(_, buyout, quantity) return math.floor(buyout / (quantity or 1)) end,
    HasFunction = function(path)
        return path == "C_AuctionHouse.GetBrowseResults"
            or (hasFull and path == "C_AuctionHouse.HasFullBrowseResults")
    end,
    WhenAuctionReady = function(action) action() end,
}

local settings = { learnFromSearches = true }
local priceTable = {}

ns.Config = {
    Get = function(_, k) return settings[k] end,
    GetPriceTable = function() return priceTable end,
    GetRealmKey = function() return "TestRealm" end,
}

ns.db = {}
ns.AHQueue = { PRIORITY = { urgent = 10, normal = 50, scan = 90 } }
ns.Auctions = { GetOwnMinPrice = function() return nil end }

local saved = { GetTime = GetTime, C_Timer = C_Timer, Enum = Enum, UnitName = UnitName,
                GetRealmName = GetRealmName, C_AuctionHouse = C_AuctionHouse, GetMoney = GetMoney }

time = time or os.time
local clock = 1000
GetTime = function() return clock end
C_Timer = { NewTimer = function() return { Cancel = function() end } end, After = function() end }
Enum = { ItemCommodityStatus = { Commodity = 2 }, BagIndex = {},
         AuctionHouseFilter = { UsableOnly = 1, UpgradesOnly = 2, UncommonQuality = 7 } }
UnitName = function() return "Tester" end
GetRealmName = function() return "TestRealm" end

local browseResults = {}
local full = true
C_AuctionHouse = {
    GetBrowseResults = function() return browseResults end,
    HasFullBrowseResults = function() return full end,
}

assert(loadfile(lfs_cwd .. "/Data/Prices.lua"))("Blackthornes_TS", ns)
assert(loadfile(lfs_cwd .. "/Data/Scanner.lua"))("Blackthornes_TS", ns)

local Prices, Scanner = ns.Prices, ns.Scanner
Scanner.isAuctionHouseOpen = true

local checks = 0
local function check(label, condition)
    checks = checks + 1
    if not condition then error(("FAILED: %s"):format(label), 2) end
    print(("  ok  %s"):format(label))
end

local RING, BRACERS = 12001, 12002
local now = time()

local function Ring(fields)
    local record = { market = 400, min = 351, rivalMin = 351, quantity = 1, seen = now - 60,
                     scans = 3, history = { { t = now - 60, m = 400, q = 1 } } }
    for k, v in pairs(fields or {}) do record[k] = v end
    priceTable[RING] = record
    return record
end

print("\nbuying what was listed")

local ring = Ring()
local before = Prices.changes or 0
check("buying the only one", Prices:NoteBought(RING, 351, 1, now) == true)
check("leaves no price to buy at", ring.rivalMin == nil and ring.min == nil and ring.quantity == 0)
check("keeps what it is worth", ring.market == 400)
check("and writes no history: nothing was scanned", #ring.history == 1)
check("it counts as a change to that one item", Prices.changes == before + 1
    and Prices:TouchedSince(before) and Prices:TouchedSince(before)[RING] == true)

ring = Ring({ quantity = 3, ladder = { 351, 1, 420, 2 } })
Prices:NoteBought(RING, 351, 1, now)
check("with another listed dearer, that is the price now", ring.rivalMin == 420 and ring.min == 420
    and ring.quantity == 2 and ring.ladder[1] == 420 and ring.ladder[2] == 2)

ring = Ring({ quantity = 3, ladder = { 300, 1, 351, 1, 420, 1 }, rivalMin = 300, min = 300 })
Prices:NoteBought(RING, 351, 1, now)
check("a cheaper one on record had gone: you would have bought it", ring.rivalMin == 420)

ring = Ring({ rivalMin = 900, ignoredLow = 351, quantity = 4, ladder = { 900, 3 } })
Prices:NoteBought(RING, 351, 1, now)
check("buying a lone low listing leaves the rest", ring.ignoredLow == nil and ring.rivalMin == 900
    and ring.ladder[2] == 3)

ring = Ring({ ownMin = 380 })
Prices:NoteBought(RING, 351, 1, now)
check("your own listing is still the cheapest listed", ring.rivalMin == nil and ring.min == 380)

ring = Ring({ seen = now + 5 })
check("a record read after the buy already left it out", Prices:NoteBought(RING, 351, 1, now) == false
    and ring.rivalMin == 351)

ring = Ring({ rivalMin = 500, min = 500 })
check("bought cheaper than anything on record: nothing on record went",
    Prices:NoteBought(RING, 351, 1, now) == false and ring.rivalMin == 500)

ring = Ring({ quantity = 25, ladder = { 10, 20, 12, 5 }, rivalMin = 10, min = 10 })
Prices:NoteBought(RING, nil, 22, now)
check("a commodity's buy takes the cheapest units, whatever they cost",
    ring.rivalMin == 12 and ring.ladder[2] == 3 and ring.quantity == 3)

check("an item never priced is left alone", Prices:NoteBought(99999, 100, 1, now) == false)

print("\nwhat buying one costs now")

ring = Ring({ rivalMin = 420, min = 420 })
check("listed: its cheapest listing", select(1, Prices:ListedNow(RING)) == 420)
Prices:NoteBought(RING, 420, 1, now)
local price, none = Prices:ListedNow(RING)
check("bought out: none listed, not its average", price == nil and none == true)
ring = Ring({ min = 300, ignoredLow = 300 })
ring.rivalMin = nil
check("a lone low listing is still one to buy", select(1, Prices:ListedNow(RING)) == 300)
priceTable[BRACERS] = nil
price, none = Prices:ListedNow(BRACERS)
check("never read: not called none listed", none == false)


local mark = Prices.changes
Prices:Touch(RING)
Prices:Touch(BRACERS)
local items = Prices:TouchedSince(mark)
check("each change names its item", items[RING] and items[BRACERS])
Prices.changes = Prices.changes + 1
check("a change counted without a name cannot be told", Prices:TouchedSince(mark) == nil)
mark = Prices.changes
for _ = 1, 40 do Prices:Touch(RING) end
check("nor can too many", Prices:TouchedSince(mark) == nil)

print("\nsearching by name and finding none")

ns.Persist = nil
local function Results(rows, isFull)
    browseResults, full = rows, isFull ~= false
    Scanner:OnBrowseResults()
end

local function Query(text, extra)
    local query = { searchString = text, sorts = {}, filters = {}, itemClassFilters = {}, minLevel = 0, maxLevel = 0 }
    for k, v in pairs(extra or {}) do query[k] = v end
    Scanner:NameSearchSent(query)
end

ring = Ring()
Scanner:ExpectSearch(RING, "Blush Ember Ring")
Query("Blush Ember Ring")
Results({})
check("the addon's own search coming back empty: nobody is selling one",
    ring.rivalMin == nil and ring.quantity == 0 and ring.seen >= now and ring.market == 400)
check("and it is waited on no more", Scanner.nameSearch == nil)

ring = Ring()
ns.Disenchant = { shownRows = { { itemID = RING, name = "Blush Ember Ring" } } }
Query("blush ember ring")
Results({ { itemKey = { itemID = 5000 }, minPrice = 10, totalQuantity = 1 } })
check("a name typed by hand that names a row counts too", ring.rivalMin == nil)

ring = Ring()
Query("Blush Ember Ring")
Results({ { itemKey = { itemID = RING }, minPrice = 420, totalQuantity = 2 } })
check("found: its price is read and nothing is cleared", ring.rivalMin == 420 and Scanner.nameSearch == nil)

ring = Ring()
Query("Blush Ember Ring")
Results({}, false)
check("an answer not yet whole is waited on", ring.rivalMin == 351 and Scanner.nameSearch ~= nil)
Results({}, true)
check("and settled once it is", ring.rivalMin == nil)

ring = Ring()
Query("Blush Ember Ring")
Query("Linen Cloth")
Results({})
check("a later query owns the results", ring.rivalMin == 351)

ring = Ring()
Query("Blush Ember Ring", { filters = { Enum.AuctionHouseFilter.UsableOnly } })
Results({})
check("a filter that could hide it says nothing", ring.rivalMin == 351)

ring = Ring()
Query("Blush Ember Ring", { minLevel = 40 })
Results({})
check("nor does a level range", ring.rivalMin == 351)

ring = Ring()
Query("Blush")
Results({})
check("a name that is not the item's whole name says nothing", ring.rivalMin == 351)

ring = Ring()
Query("Blush Ember Ring")
clock = clock + 30
Results({})
check("an answer long after is not this search's", ring.rivalMin == 351)

ring = Ring()
Scanner.isBrowsing = true
Query("Blush Ember Ring")
Scanner.isBrowsing = false
check("the addon's own sweep is never read as one", Scanner.nameSearch == nil)

hasFull = false
ring = Ring()
Query("Blush Ember Ring")
Results({ { itemKey = { itemID = 5000 }, minPrice = 10, totalQuantity = 1 } })
check("without the client saying it is whole, other rows could be a first page", ring.rivalMin == 351)
Query("Blush Ember Ring")
Results({})
check("but nothing at all came back", ring.rivalMin == nil)
hasFull = true
ns.Disenchant = nil

print("\nthe buy, from the auction house's own answer")

ns.Recipes = { GetCharacterRecord = function() return nil end }
assert(loadfile(lfs_cwd .. "/Logic/AHBuys.lua"))("Blackthornes_TS", ns)
local AHBuys = ns.AHBuys
GetMoney = function() return 100000 end

ring = Ring()
Scanner.passiveSeen = { [RING] = { at = clock, price = 351 } }
AHBuys:Await(RING, 1, 77, 351)
AHBuys:Confirm(77)
check("a confirmed buyout takes the listing off the record", ring.rivalMin == nil)
check("and the same price seen again is read, as another listing", Scanner.passiveSeen[RING] == nil)

for key, value in pairs(saved) do _G[key] = value end

print(("\n%d checks passed"):format(checks))
