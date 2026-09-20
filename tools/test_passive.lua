-- Learning prices from the player's own auction house searches.
--
-- The client announces search results the same way whoever asked for them, so
-- when Trent types into Blizzard's search box the addon's handlers fire with a
-- full set of real prices sitting in the shared state. They used to return
-- early on "not ours" and throw all of it away.
--
-- Two things have to hold for reading them to be safe, and both are checked
-- here because getting either wrong costs gold rather than just data:
--
--  * a passive observation may ADD a price but never REMOVE one. An empty
--    shared result set is as likely to be a set cleared for the next query as
--    it is to be an item nobody has listed, and clearing a real rival price on
--    that guess is how the addon would list far under value.
--  * nothing may be sent. Paging through somebody else's search is exactly
--    what the old early returns were guarding against, and it would spend the
--    throttle budget Trent's own posting needs.

local ns = {}
ns.COLORS = setmetatable({}, {__index = function() return "ffffffff" end})
ns.NewModule = function(name) local m = {}; ns[name] = m; return m end
ns.RegisterCommand = function() end
ns.RegisterEvent = function() return true end
ns.Print, ns.PrintRaw, ns.Debug, ns.Warn = function() end, function() end, function() end, function() end

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
    HasFunction = function(path) return path == "C_AuctionHouse.GetBrowseResults" end,
    -- No queue here, so a follow-up search goes out at once.
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

-- Your own auctions as last read back. A browse row's owner flag only says
-- you have SOME listing of the item among the results, so it is settled
-- against these: yours when you have it listed at exactly that price.
local ownListings = {}
ns.Auctions = { GetOwnMinPrice = function(_, itemID) return ownListings[itemID] end }

-- WoW globals the scanner touches. Anything that would SEND a request is
-- recorded rather than stubbed silently, so the test can assert on it.
time = time or os.time
local clock = 1000
GetTime = function() return clock end
C_Timer = { NewTimer = function() return { Cancel = function() end } end,
            After = function() end }
Enum = { ItemCommodityStatus = { Commodity = 2 }, BagIndex = {} }
UnitName = function() return "Tester" end
GetRealmName = function() return "TestRealm" end

local sent = {}

-- The shared client state a search fills in, and the getters that read it.
local browseResults = {}
local itemResults = {}

C_AuctionHouse = {
    GetBrowseResults = function() return browseResults end,
    HasFullBrowseResults = function() return true end,
    RequestMoreBrowseResults = function() sent[#sent + 1] = "RequestMoreBrowseResults" return true end,
    SendBrowseQuery = function() sent[#sent + 1] = "SendBrowseQuery" return true end,
    SendSearchQuery = function() sent[#sent + 1] = "SendSearchQuery" return true end,
    MakeItemKey = function(itemID) return { itemID = itemID } end,
    GetNumItemSearchResults = function() return #itemResults end,
    GetItemSearchResultInfo = function(_, i) return itemResults[i] end,
    GetNumCommoditySearchResults = function() return #itemResults end,
    GetCommoditySearchResultInfo = function(_, i) return itemResults[i] end,
}

assert(loadfile(lfs_cwd .. "/Data/Prices.lua"))("Blackthornes_TS", ns)
assert(loadfile(lfs_cwd .. "/Data/Scanner.lua"))("Blackthornes_TS", ns)

local Prices, Scanner = ns.Prices, ns.Scanner
Scanner.isAuctionHouseOpen = true

local function reset()
    for k in pairs(priceTable) do priceTable[k] = nil end
    sent = {}
    Scanner.passiveSeen = nil
    Scanner.passiveRecent = nil
    Scanner.passiveItems = nil
    Scanner.passiveCount = nil
    Scanner.passiveItemCount = nil
    Scanner.pendingItem = nil
    Scanner.isBrowsing = false
    settings.learnFromSearches = true
    for k in pairs(ownListings) do ownListings[k] = nil end
end

local checks = 0
local function check(label, condition)
    checks = checks + 1
    if not condition then error(("FAILED: %s"):format(label), 2) end
    print(("  ok  %s"):format(label))
end

print("\npassive capture from the player's own searches")

--------------------------------------------------------------------------------
-- A browse the player ran
--------------------------------------------------------------------------------

reset()
ownListings[5498] = 900
browseResults = {
    { itemKey = { itemID = 2589 }, minPrice = 30,  totalQuantity = 400 },
    { itemKey = { itemID = 4306 }, minPrice = 120, totalQuantity = 60 },
    { itemKey = { itemID = 5498 }, minPrice = 900, totalQuantity = 3, containsOwnerItem = true },
}

Scanner:OnBrowseResults()

check("the player's browse is recorded", Prices:Get(2589) ~= nil and Prices:Get(2589).min == 30)
check("every row is taken, not just the first", Prices:Get(4306) ~= nil)
check("a row at the price you have it listed at sets ownMin, not rivalMin",
    Prices:Get(5498).ownMin == 900 and Prices:Get(5498).rivalMin == nil)
check("a rival row sets rivalMin", Prices:Get(2589).rivalMin == 30)
check("nothing was sent to the auction house", #sent == 0)

--------------------------------------------------------------------------------
-- The same results arriving again
--------------------------------------------------------------------------------

local scansBefore = Prices:Get(2589).scans
Scanner:OnBrowseResults()

check("a repeat of the same price is not recorded twice",
    Prices:Get(2589).scans == scansBefore)

clock = clock + 120
browseResults[1].minPrice = 34
Scanner:OnBrowseResults()

check("a price that has actually moved is recorded",
    Prices:Get(2589).min == 34 and Prices:Get(2589).scans == scansBefore + 1)

--------------------------------------------------------------------------------
-- An item search the player ran by clicking a row
--------------------------------------------------------------------------------

reset()
itemResults = {
    { buyoutAmount = 500, quantity = 1 },
    { buyoutAmount = 700, quantity = 1, containsOwnerItem = true },
    { buyoutAmount = 900, quantity = 1 },
}

Scanner:ITEM_SEARCH_RESULTS_UPDATED(nil, { itemID = 4306 })

local record = Prices:Get(4306)
check("clicking an item in Blizzard's list records its book", record ~= nil)
check("the cheapest rival is the cheapest listing that is not yours",
    record.rivalMin == 500)
check("your own listing is remembered separately", record.ownMin == 700)
check("no request was sent reading it", #sent == 0)

--------------------------------------------------------------------------------
-- THE RULE THAT PROTECTS THE GOLD: a passive empty never clears a price
--------------------------------------------------------------------------------

reset()
Prices:Record(4306, 500, 500, 10, nil, 500, nil)

itemResults = {}
Scanner:ITEM_SEARCH_RESULTS_UPDATED(nil, { itemID = 4306 })

check("an empty result from somebody else's search leaves rivalMin alone",
    Prices:Get(4306).rivalMin == 500)
check("and leaves the minimum buyout alone", Prices:Get(4306).min == 500)

-- The addon's own search is different: there, empty is a real answer and must
-- still clear the rival price. That is what test_postprice guards; this checks
-- only that passive capture did not take the decision away from it.
reset()
Prices:Record(4306, 500, 500, 10, nil, 500, nil)
Scanner.pendingItem = { itemID = 4306, itemKey = { itemID = 4306 } }
itemResults = {}
Scanner:ITEM_SEARCH_RESULTS_UPDATED(nil, { itemID = 4306 })

check("the addon's OWN empty search still clears the rival price",
    Prices:Get(4306).rivalMin == nil)

--------------------------------------------------------------------------------
-- Our own search is still ours
--------------------------------------------------------------------------------

reset()
local gotCallback
Scanner.pendingItem = {
    itemID = 2589,
    itemKey = { itemID = 2589 },
    callback = function(_, market, min, qty, isCommodity, _, status)
        gotCallback = { market = market, min = min, qty = qty,
                        isCommodity = isCommodity, status = status }
    end,
}

itemResults = { { buyoutAmount = 60, quantity = 2 } }
Scanner:ITEM_SEARCH_RESULTS_UPDATED(nil, { itemID = 2589 })

check("a search of ours still reaches its callback", gotCallback ~= nil)
check("and reports itself fresh", gotCallback.status == "fresh")
check("and is not counted as learned from the player",
    (Scanner.passiveCount or 0) == 0)

--------------------------------------------------------------------------------
-- A commodity search the player ran
--------------------------------------------------------------------------------

reset()
itemResults = {
    { unitPrice = 28, quantity = 200 },
    { unitPrice = 31, quantity = 100 },
}
Scanner:COMMODITY_SEARCH_RESULTS_UPDATED(nil, 2589)

check("a commodity search the player ran is recorded",
    Prices:Get(2589) ~= nil and Prices:Get(2589).min == 28)

--------------------------------------------------------------------------------
-- Turned off
--------------------------------------------------------------------------------

reset()
settings.learnFromSearches = false

Scanner:OnBrowseResults()
Scanner:ITEM_SEARCH_RESULTS_UPDATED(nil, { itemID = 4306 })
Scanner:COMMODITY_SEARCH_RESULTS_UPDATED(nil, 2589)

check("with the setting off nothing is recorded", next(priceTable) == nil)
check("and still nothing is sent", #sent == 0)

--------------------------------------------------------------------------------
-- A browse of ours is untouched by any of this
--------------------------------------------------------------------------------

reset()
Scanner.isBrowsing = true
Scanner.browsePages = 0
browseResults = { { itemKey = { itemID = 2589 }, minPrice = 30, totalQuantity = 400 } }

Scanner:OnBrowseResults()

check("our own browse still commits through the scan path",
    Scanner.isBrowsing == false and Prices:Get(2589) ~= nil)
check("and is not counted as learned from the player",
    (Scanner.passiveCount or 0) == 0)

--------------------------------------------------------------------------------
-- A rival who has undercut you
--
-- The row's owner flag is set because you have a listing of the item among
-- the results; the cheapest price on the row is somebody else's. Reading the
-- flag as "the cheapest is mine" erased that rival and said you held the
-- lowest, and the listing sat.
--------------------------------------------------------------------------------

reset()
ownListings[2996] = 500
Prices:Record(2996, 500, 300, 40, time(), 300, 500)   -- a full scan had it right
browseResults = {
    { itemKey = { itemID = 2996 }, minPrice = 300, totalQuantity = 40, containsOwnerItem = true },
}

Scanner:OnBrowseResults()

check("the rival under you is still a rival", Prices:Get(2996).rivalMin == 300)
check("and your own price is still yours", Prices:Get(2996).ownMin == 500)
check("so you do not hold the lowest", not Prices:HoldsLowest(2996))

-- Your auctions never read: the row counts as a rival's rather than erasing
-- one. Undercutting yourself by a silver costs less than undercutting nobody.
reset()
browseResults = {
    { itemKey = { itemID = 2996 }, minPrice = 300, totalQuantity = 40, containsOwnerItem = true },
}
Scanner:OnBrowseResults()
check("with your auctions unread the row is a rival's", Prices:Get(2996).rivalMin == 300)

-- The cheapest listing is yours and a rival is known to sit above it: the
-- row does not contradict that rival, so it stays.
reset()
ownListings[2996] = 300
Prices:Record(2996, 500, 300, 40, time(), 500, 300)
browseResults = {
    { itemKey = { itemID = 2996 }, minPrice = 300, totalQuantity = 40, containsOwnerItem = true },
}
Scanner:OnBrowseResults()
check("a rival known to be above you is kept", Prices:Get(2996).rivalMin == 500)
check("and you hold the lowest", Prices:HoldsLowest(2996))

--------------------------------------------------------------------------------
-- A rival tied with you
--
-- Measured 2026-09-20: Trent at 63s and 64s, other sellers at 63s and 64s.
-- The row reads 63s and yours; it cannot see the tie. A rival on record at
-- your price is not contradicted by that row, so it stays.
--------------------------------------------------------------------------------

reset()
ownListings[2996] = 6300
Prices:Record(2996, 6300, 6300, 17, time(), 6300, 6300)   -- an exact search saw the tie
browseResults = {
    { itemKey = { itemID = 2996 }, minPrice = 6300, totalQuantity = 17, containsOwnerItem = true },
}
Scanner:OnBrowseResults()
check("a rival tied at your price is kept", Prices:Get(2996).rivalMin == 6300)
check("so a tie is not 'you hold the lowest'", not Prices:HoldsLowest(2996))
check("a settled row sends nothing", #sent == 0)

-- Nothing on record about rivals: the addon's own scan settles the row with an
-- exact search, at background priority, rather than guessing either way.
reset()
ownListings[2996] = 6300
Scanner.recentItemScans = nil
Scanner:CommitBrowseResults({
    { itemKey = { itemID = 2996 }, minPrice = 6300, totalQuantity = 17, containsOwnerItem = true },
})
check("an unsettled row leaves no rival rather than a wrong one", Prices:Get(2996).rivalMin == nil)
check("and the addon's own scan follows it up with an exact search",
    sent[1] == "SendSearchQuery" and Scanner.pendingItem and Scanner.pendingItem.itemID == 2996)

-- The exact answer arrives with the tie in it.
itemResults = {
    { buyoutAmount = 6300, quantity = 1, containsOwnerItem = true },
    { buyoutAmount = 6300, quantity = 1, containsOwnerItem = false },
    { buyoutAmount = 6400, quantity = 1, containsOwnerItem = true },
}
Scanner:ITEM_SEARCH_RESULTS_UPDATED(nil, { itemID = 2996 })
check("the follow-up records the tied rival", Prices:Get(2996).rivalMin == 6300
    and Prices:Get(2996).ownMin == 6300)
check("and the follow-up list is spent", Scanner.followUp == nil)

-- The player's own browse never sends anything, unsettled rows included.
reset()
ownListings[2996] = 6300
Scanner:OnBrowseResults()
check("a passive browse still sends nothing", #sent == 0)

print(("\n%d check(s) passed\n"):format(checks))
