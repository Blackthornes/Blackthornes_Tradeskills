-- Places in line on the Auctions view (Logic/MyAuctions.lua,
-- UI/AuctionsView.lua; a player asked, the owner said build it 2026-10-20).
--
-- What must hold:
--   1. An item auction counts only others' auctions at its price and its
--      random suffix listed before it, never its own and never cheaper or
--      dearer ones.
--   2. A commodity says how many of others' units share its price.
--   3. Only a "cheapest" auction with others ahead is behind: it sorts first
--      in its group, its badge is amber and it gets a Cancel button.
--   4. A place older than FRESH says nothing.
--   5. The search handlers' reads never raise and read only items you have
--      up; Check Places searches each item (and suffix) once, in turn.

local ns = {}
ns.NewModule = function(name) local m = {}; ns[name] = m; return m end
ns.Print = function() end
ns.Debug = function() end
ns.COLORS = { loss = "ffe5604f", warn = "ffe0a040", profit = "ff60c060", accent = "ffc8a44d" }

local wall = 50000
GetTime = function() return wall end
time = function() return wall end
local timers = {}
C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end }

ns.Util = {
    HasFunction = function() return true end,
    GetItemLabel = function(id) return "Item " .. id end,
    FormatMoney = function(c) return tostring(c) .. "c" end,
    FormatAge = function(s) return tostring(s) .. "s" end,
    FormatAgeAgo = function(s) return tostring(s) .. "s ago" end,
    LinkSuffix = function(link) local s = link and link:match("suffix(%d+)"); return s and tonumber(s) or nil end,
    UnitPriceFromStack = function(_, buyout, quantity) return math.floor(buyout / quantity) end,
}
ns.Config = { GetCharacterKey = function() return "Player-1" end }
ns.Characters = { IsPlaying = function(_, key) return key == "Player-1" end }
ns.Scanner = { isAuctionHouseOpen = true }
ns.Prices = {
    GetAge = function() return 60 end,
    -- Cheapest not yours equals your price: "cheapest", with others there.
    GetScanValue = function(_, id) return ({ [1] = 5500, [2] = 2798, [3] = 125 })[id] end,
}

ns.Auctions = {
    live = {
        { auctionID = 11, itemID = 1, quantity = 1, unit = 5500, link = "item1-suffix7" },
        { auctionID = 12, itemID = 2, quantity = 1, unit = 2798 },
        { auctionID = 13, itemID = 3, quantity = 20, unit = 125 },
        { auctionID = 14, itemID = 1, quantity = 1, unit = 5500, link = "item1-suffix7",
          itemKey = { itemID = 1, itemSuffix = 7 } },
    },
    GetListings = function() return {} end,
}

assert(loadfile(lfs_cwd .. "/Logic/MyAuctions.lua"))("Blackthornes_TS", ns)
local MyAuctions = ns.MyAuctions

local checks = 0
local function check(label, condition)
    checks = checks + 1
    if not condition then error(("FAILED: %s"):format(label), 2) end
end

-- 1: item 1, suffix 7, at 5500. Ahead of auction 11: two others at 5500 of
-- suffix 7 (a cheaper one, a dearer one, another suffix and your own 14 don't
-- count).
MyAuctions:NotePlaces(1, {
    { auctionID = 90, unit = 5400, own = false, suffix = 7 },
    { auctionID = 91, unit = 5500, own = false, suffix = 7 },
    { auctionID = 92, unit = 5500, own = false, suffix = 3 },
    { auctionID = 14, unit = 5500, own = true, suffix = 7 },
    { auctionID = 93, unit = 5501, own = false, suffix = 7 },
    { auctionID = 11, unit = 5500, own = true, suffix = 7 },
    { auctionID = 94, unit = 5600, own = false, suffix = 7 },
})
check("others at your price and suffix before yours", MyAuctions.places[11].ahead == 2)
check("your own auction ahead is not counted", MyAuctions.places[14].ahead == 1)

-- Item 2: yours first.
MyAuctions:NotePlaces(2, {
    { auctionID = 12, unit = 2798, own = true, suffix = 0 },
    { auctionID = 95, unit = 2798, own = false, suffix = 0 },
})
check("first in line", MyAuctions.places[12].ahead == 0)

-- 2: commodity 3, 500 units at 125, 20 of them yours.
MyAuctions:NoteMore(3, {
    { unit = 120, quantity = 0, ownUnits = 0 },
    { unit = 125, quantity = 500, ownUnits = 20 },
})
check("others' units at your price", MyAuctions.more[3].units[125] == 480)

-- 3
local rows = MyAuctions:Rows()
local byID = {}
for _, row in ipairs(rows) do byID[row.auctionID] = row end
check("behind with others ahead", byID[11].behind == true and byID[13].behind == true)
check("not behind when first", byID[12].behind == nil and byID[12].ahead == 0)
check("the commodity row carries its count", byID[13].more == 480)
check("behind rows sort first among the cheapest", rows[#rows].auctionID == 12)

ns.Theme = {}
ns.Widgets = {}
assert(loadfile(lfs_cwd .. "/UI/AuctionsView.lua"))("Blackthornes_TS", ns)
local View = ns.AuctionsView
local _, color = View.BadgeText(byID[11])
check("amber Cheapest when others sell first", color == "warn")
_, color = View.BadgeText(byID[12])
check("green Cheapest when first", color == "profit")
check("a Cancel button for a behind row", View.Cancellable(byID[11]) and not View.Cancellable(byID[12]))
check("the place is in the detail line", View.DetailTexts(byID[11])[1]:find("2 ahead of you") ~= nil)
check("first in line says so", View.DetailTexts(byID[12])[1]:find("First in line") ~= nil)
check("a commodity says how many more", View.DetailTexts(byID[13])[1]:find("480 more at your price") ~= nil)

-- 4
wall = wall + MyAuctions.FRESH + 1
local old = MyAuctions:Rows()
for _, row in ipairs(old) do
    check("an old place says nothing", row.ahead == nil and row.more == nil and not row.behind)
end
check("and the line has no place", View.PlaceText(old[1]) == nil)

-- 5: reading a search never raises, even when the game does.
C_AuctionHouse = {
    GetNumItemSearchResults = function() error("secret") end,
    GetNumCommoditySearchResults = function() error("secret") end,
}
MyAuctions:NoteItemPlaces({ itemID = 1 })
MyAuctions:NoteCommodityPlaces(3)
check("an item you don't have up is not read", MyAuctions:Wants(99) == false)

C_AuctionHouse = {
    GetNumItemSearchResults = function() return 2 end,
    GetItemSearchResultInfo = function(_, i)
        return ({ { auctionID = 96, buyoutAmount = 2798, quantity = 1, itemLink = "x" },
                  { auctionID = 12, buyoutAmount = 2798, quantity = 1, containsOwnerItem = true } })[i]
    end,
}
MyAuctions:NoteItemPlaces({ itemID = 2, itemSuffix = 0 })
check("a search's rows are read in order", MyAuctions.places[12].ahead == 1 and MyAuctions.places[12].at == wall)

-- Check Places: each item and suffix once, one after another.
local searched = {}
ns.AHQueue = { PRIORITY = { scan = 3 } }
ns.Scanner.ScanItem = function(_, itemID, callback, opts)
    searched[#searched + 1] = { itemID = itemID, key = opts.itemKey, quiet = opts.quiet }
    callback(itemID)
    return true
end
check("Check Places starts", MyAuctions:CheckPlaces())
check("each item once, the suffix key kept", #searched == 3 and searched[1].itemID == 1
    and searched[2].itemID == 2 and searched[3].itemID == 3 and searched[1].quiet)
check("done when the list is empty", MyAuctions.checking == nil)
ns.Scanner.isAuctionHouseOpen = false
check("not away from the auction house", MyAuctions:CheckPlaces() == false)

print(("%d checks passed"):format(checks))
