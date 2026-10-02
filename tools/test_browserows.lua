-- Page-by-page scans: an item's rows read together, and a sweep that keeps
-- going when a page lands early.
--
--  * An item can come back as several browse rows, one per item key: gear
--    with a random suffix shares one itemID. Recorded a row at a time, the
--    last row won: a green at 50s and 4g was stored at 4g, with one of its
--    four counted, and counted as scanned twice in one sweep.
--  * A page that landed while the ask for the next one was still waiting its
--    turn queued that ask again under the same key. The queue replaced the
--    waiting one and ran its give-up, and the give-up ended the sweep:
--    "scan stopped early" after page 2.

-- Tests share one Lua state, so every global replaced here is put back,
-- including the ones that were not set at all.
local GLOBALS = { "GetTime", "time", "C_Timer", "C_AuctionHouse", "AuctionHouseFrame" }
local saved = {}
for _, key in ipairs(GLOBALS) do saved[key] = _G[key] end

local function noop() end

local clock = 1000
GetTime = function() return clock end
time = function() return 100000 end
C_Timer = {
    After = noop,
    NewTimer = function() return { Cancel = noop } end,
    NewTicker = function() return { Cancel = noop } end,
}
AuctionHouseFrame = nil

-- The client's throttle says whether a request may go. While it says no,
-- whatever the scanner asks for waits in the queue.
local ready = false
local sent = {}
local browseResults, full = {}, false
C_AuctionHouse = {
    IsThrottledMessageSystemReady = function() return ready end,
    GetBrowseResults = function() return browseResults end,
    HasFullBrowseResults = function() return full end,
    RequestMoreBrowseResults = function() sent[#sent + 1] = "more" return true end,
}

local ns = {}
ns.COLORS = setmetatable({}, { __index = function() return "ffffffff" end })
ns.NewModule = function(name) local m = {}; ns[name] = m; return m end
ns.RegisterCommand = noop
ns.RegisterEvent = function() return true end
local printed = {}
ns.Print = function(msg) printed[#printed + 1] = msg end
ns.PrintRaw, ns.Debug, ns.Warn = noop, noop, noop

ns.Util = {
    Comma = function(n) return tostring(n) end,
    FormatMoney = function(c) return tostring(c) end,
    HasFunction = function(path)
        return path == "C_AuctionHouse.IsThrottledMessageSystemReady"
            or path == "C_AuctionHouse.GetBrowseResults"
            or path == "C_AuctionHouse.HasFullBrowseResults"
    end,
}

local settings = { learnFromSearches = true }
local priceTable = {}
ns.Config = {
    Get = function(_, k) return settings[k] end,
    GetPriceTable = function() return priceTable end,
    GetRealmKey = function() return "TestRealm" end,
}
ns.db = {}

-- Your own auctions as last read back.
local ownListings = {}
ns.Auctions = { GetOwnMinPrice = function(_, itemID) return ownListings[itemID] end }

assert(loadfile(lfs_cwd .. "/Core/AHQueue.lua"))("Blackthornes_TS", ns)
assert(loadfile(lfs_cwd .. "/Data/Prices.lua"))("Blackthornes_TS", ns)
assert(loadfile(lfs_cwd .. "/Data/Scanner.lua"))("Blackthornes_TS", ns)

local AHQueue, Prices, Scanner = ns.AHQueue, ns.Prices, ns.Scanner
Scanner.isAuctionHouseOpen = true

-- The rows sent on for an exact search, rather than searching.
local followedUp
Scanner.FollowUpOwned = function(_, itemIDs)
    if itemIDs and #itemIDs > 0 then followedUp = itemIDs end
end

local passed, failed = 0, 0
local function check(label, condition)
    if condition then
        passed = passed + 1
        print(("  ok    %s"):format(label))
    else
        failed = failed + 1
        print(("  FAIL  %s"):format(label))
    end
end

local function Reset()
    for key in pairs(priceTable) do priceTable[key] = nil end
    for key in pairs(ownListings) do ownListings[key] = nil end
    printed, sent, followedUp = {}, {}, nil
    Scanner.passiveSeen = nil
end

local function Said(text)
    for _, line in ipairs(printed) do
        if tostring(line):find(text, 1, true) then return true end
    end
    return false
end

local GLOVES, BOLT = 9783, 2996

print("")
print("one item, several rows")

Reset()
Scanner:CommitBrowseResults({
    { itemKey = { itemID = GLOVES, itemSuffix = 1 }, minPrice = 5000, totalQuantity = 3 },
    { itemKey = { itemID = GLOVES, itemSuffix = 2 }, minPrice = 40000, totalQuantity = 1 },
}, { ended = true })

do
    local gloves = Prices:Get(GLOVES)
    check("the cheapest row is the price", gloves ~= nil and gloves.min == 5000 and gloves.rivalMin == 5000)
    check("and the market", gloves ~= nil and gloves.market == 5000)
    check("every row's count adds up", gloves ~= nil and gloves.quantity == 4)
    check("scanned once in one sweep", gloves ~= nil and gloves.scans == 1)
    check("and counted as one item", Said("scan complete: 1 items"))
end

-- Your listing on one row, a rival's on another: the rival is known, so
-- there is nothing to settle with an exact search.
Reset()
ownListings[GLOVES] = 6300
Scanner:CommitBrowseResults({
    { itemKey = { itemID = GLOVES, itemSuffix = 1 }, minPrice = 6300, totalQuantity = 2, containsOwnerItem = true },
    { itemKey = { itemID = GLOVES, itemSuffix = 2 }, minPrice = 7000, totalQuantity = 1 },
})

do
    local gloves = Prices:Get(GLOVES)
    check("your price comes from your row", gloves ~= nil and gloves.ownMin == 6300)
    check("the rival's from theirs", gloves ~= nil and gloves.rivalMin == 7000)
    check("so no exact search is needed", followedUp == nil)
end

-- On its own, the row at your price still asks.
Reset()
ownListings[GLOVES] = 6300
Scanner:CommitBrowseResults({
    { itemKey = { itemID = GLOVES, itemSuffix = 1 }, minPrice = 6300, totalQuantity = 2, containsOwnerItem = true },
})
check("a lone row at your price is still followed up",
    followedUp ~= nil and followedUp[1] == GLOVES and #followedUp == 1)

-- The player's own browse is read the same way.
Reset()
browseResults = {
    { itemKey = { itemID = GLOVES, itemSuffix = 1 }, minPrice = 5000, totalQuantity = 3 },
    { itemKey = { itemID = GLOVES, itemSuffix = 2 }, minPrice = 40000, totalQuantity = 1 },
}
check("the player's own browse learns one price for the item", Scanner:CapturePassiveBrowse() == 1)
check("its cheapest row, every row counted",
    Prices:Get(GLOVES) ~= nil and Prices:Get(GLOVES).min == 5000 and Prices:Get(GLOVES).quantity == 4)

print("")
print("a page that lands early")

local function Page(count)
    local rows = {}
    for i = 1, count do
        rows[i] = { itemKey = { itemID = 10000 + i }, minPrice = 100 + i, totalQuantity = 1 }
    end
    return rows
end

local function StartSweep()
    Scanner.isBrowsing = true
    Scanner.isScanning = true
    Scanner.browsePages = 0
    Scanner.browseRowsSeen = nil
    Scanner.browseLast = nil
    Scanner.browseForeign = false
    Scanner.scanStartedAt = clock
    Scanner.scanStartedWall = time()
end

Reset()
StartSweep()
ready = false

browseResults, full = Page(100), false
Scanner:OnBrowseResults()
check("the next page is asked for, and waits its turn", AHQueue:GetPendingCount() == 1)

-- Something else asked for more of the same results before ours went out.
browseResults = Page(200)
Scanner:OnBrowseResults()
check("the sweep is still running", Scanner.isBrowsing == true)
check("nothing was cut short", not Said("stopped early") and next(priceTable) == nil)
check("one ask for the next page is waiting", AHQueue:GetPendingCount() == 1)

clock = clock + 2
ready = true
AHQueue:Drain()
check("and it goes out", sent[1] == "more")

browseResults, full = Page(250), true
Scanner:OnBrowseResults()
check("the sweep runs to its end", Scanner.isBrowsing == false and Said("scan complete: 250 items"))

-- An ask that never gets to go still ends the sweep with what was read.
Reset()
StartSweep()
ready = false
browseResults, full = Page(100), false
Scanner:OnBrowseResults()
clock = clock + 61
AHQueue:Drain()
check("a page never asked for ends the sweep with what was read",
    Scanner.isBrowsing == false and Said("scan stopped early: 100 items"))

for _, key in ipairs(GLOBALS) do _G[key] = saved[key] end

print("")
print(("%d passed, %d failed"):format(passed, failed))
assert(failed == 0, "browse row checks failed")
