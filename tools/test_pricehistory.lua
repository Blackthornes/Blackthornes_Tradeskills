-- The price graph's hourly prices (asked 2026-10-06; volume and average 2026-10-09).
--
-- What must hold:
--   1. Only what the account crafts, its materials and starred items are
--      kept; a star counts from the next scan.
--   2. One price an hour (the newest), nothing older than seven days, never
--      out of order.
--   3. Prices:Record keeps the cheapest posting, leaving out a lone low one.
--   4. The best times are only said once the scans cover 8 hours on 5 days;
--      a steady price names no hour; a falling week does not fake a pattern.
--   5. An old save with no priceHistory loads, keeps everything else, and
--      nothing here touches the price table, my prices or favourites.
--   6. The graph places points by time and price, and falls back to the
--      price table's scans for an item that is not kept.

time = time or os.time
date = date or os.date

local now = 1790000000
local clock = now
time = function() return clock end

local passed, failed = 0, 0
local function check(label, got, want)
    if got == want then
        passed = passed + 1
        print(("  ok    %-60s %s"):format(label, tostring(got)))
    else
        failed = failed + 1
        print(("  FAIL  %-60s got %s, want %s"):format(label, tostring(got), tostring(want)))
    end
end

local ns = {}
ns.COLORS = setmetatable({}, { __index = function() return "ffffffff" end })
ns.Util = {
    Clamp = function(v, l, h) return math.max(l, math.min(h, v)) end,
    Count = function(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end,
    FormatMoney = function(c) return tostring(c) end,
    FormatAge = function() return "" end,
    HasFunction = function() return false end,
    GetItemLabel = function(i) return "item" .. tostring(i) end,
}
ns.NewModule = function(name) local m = {}; ns[name] = m; return m end
ns.RegisterCommand = function() end
ns.RegisterEvent = function() end
ns.Print, ns.PrintRaw, ns.Debug, ns.Warn = function() end, function() end, function() end, function() end

local realm = "Forever-Alliance"
ns.db = {
    prices = {},
    favouritePrices = {},
    myPrices = { [realm] = { [2589] = { price = 30, mode = "use" } } },
    characters = {
        ["Ana-Forever"] = {
            recipes = {
                [2963] = { outputItemID = 2996, reagents = { { itemID = 2589, quantity = 3 } } },
            },
        },
    },
}
ns.Config = {
    Get = function() return nil end,
    GetRealmKey = function() return realm end,
    GetPriceTable = function()
        ns.db.prices[realm] = ns.db.prices[realm] or {}
        return ns.db.prices[realm]
    end,
}

assert(loadfile(lfs_cwd .. "/Data/Prices.lua"))("Blackthornes_TS", ns)
assert(loadfile(lfs_cwd .. "/Data/PriceHistory.lua"))("Blackthornes_TS", ns)

local H = ns.PriceHistory
-- Wool Cloth, the Bolt made from it, Spider Silk, and an item nobody uses.
local WOOL, BOLT, SILK, OTHER = 2589, 2996, 4306, 9999
local HOUR = 3600

print("which items")
check("a craft is kept", H:IsTracked(BOLT), true)
check("its material is kept", H:IsTracked(WOOL), true)
check("anything else is not", H:IsTracked(OTHER), false)
ns.Prices:SetFavourite(SILK, true, "Spider Silk")
check("a starred item is kept at once", H:IsTracked(SILK), true)

H:Note(OTHER, 50, now)
check("an item not kept writes nothing", ns.db.priceHistory == nil, true)

print("one an hour, seven days")
H:Note(WOOL, 40, now)
H:Note(WOOL, 35, now + 600)
local list = ns.db.priceHistory[realm][WOOL]
check("two scans in one hour keep one pair", #list, 2)
check("the newest price stands for the hour", list[2], 35)

H:Note(WOOL, 38, now + HOUR)
check("the next hour adds a pair", #list, 4)
H:Note(WOOL, 99, now - HOUR)
check("an older price is left out, not written out of order", #list, 4)
H:Note(WOOL, 0, now + 2 * HOUR)
H:Note(WOOL, -5, now + 2 * HOUR)
check("no price is not a price", #list, 4)

H:Note(WOOL, 41, now + 8 * 24 * HOUR)
check("after eight days only the new pair is left", #list, 2)
check("and it is the new price", list[2], 41)

print("the price Record keeps")
ns.db.priceHistory = nil
ns.Prices:Record(BOLT, 300, 120, 20, now, 250, 200, nil)
check("Record notes the cheapest posting, yours included",
    ns.db.priceHistory[realm][BOLT][2], 200)
ns.Prices:Record(BOLT, 300, 5, 20, now + HOUR, 260, nil, 5)
check("a lone low listing is left out", ns.db.priceHistory[realm][BOLT][4], 260)
ns.Prices:Record(OTHER, 300, 100, 5, now)
check("the price table still takes every item", ns.Prices:Get(OTHER) ~= nil, true)
check("but no history for it", ns.db.priceHistory[realm][OTHER], nil)

print("points")
clock = now + HOUR
local points = H:GetPoints(BOLT, 24 * HOUR)
check("both scans are in the last 24 hours", #points, 2)
check("oldest first", points[1].p, 200)
check("times come back to the hour", points[2].t, math.floor((now + HOUR) / HOUR) * HOUR)

print("best times")
-- A week starting at local midnight, so hours of the day are known.
local base = os.time({ year = 2026, month = 9, day = 28, hour = 0 })
local function Week(priceAt, hours, days)
    ns.db.priceHistory = nil
    for day = 0, days - 1 do
        for _, h in ipairs(hours) do
            H:Note(WOOL, priceAt(day, h), base + day * 24 * HOUR + h * HOUR)
        end
    end
    clock = base + days * 24 * HOUR
    return H:GetBestTimes(WOOL)
end

local cheapAt4 = function(_, h) return h == 4 and 80 or (h == 20 and 120 or 100) end
local best = Week(cheapAt4, { 2, 4, 8, 11, 14, 17, 20, 23 }, 3)
check("three days is not enough", best.ready, false)
check("but counts its days", best.days, 3)

best = Week(cheapAt4, { 4, 8, 14, 20 }, 7)
check("four hours of the day is not enough", best.ready, false)
check("and counts its hours", best.hours, 4)

best = Week(cheapAt4, { 2, 4, 8, 11, 14, 17, 20, 23 }, 6)
check("8 hours on 6 days is enough", best.ready, true)
check("cheapest at 4am", best.buyHour, 4)
check("dearest at 8pm", best.sellHour, 20)
check("not steady", best.steady, false)
local texts = H:DescribeBestTimes(WOOL)
check("said in words", texts[2], "Cheapest around 4am, dearest around 8pm")

best = Week(function(day, h) return 100 + (h == 4 and 1 or 0) end, { 2, 4, 8, 11, 14, 17, 20, 23 }, 6)
check("a price that holds all day is steady", best.steady, true)

-- Falling 10% a day, the same at every hour within a day: the late hours
-- of a day are not cheaper than its morning, so no hour should stand out.
best = Week(function(day, _) return math.floor(1000 * (0.9 ^ day)) end,
    { 2, 4, 8, 11, 14, 17, 20, 23 }, 6)
check("a falling week is not a time of day pattern", best.steady, true)

check("hour words", H.HourText(0) .. " " .. H.HourText(12) .. " " .. H.HourText(15), "12am 12pm 3pm")

print("upkeep and old saves")
clock = base + 30 * 24 * HOUR
check("prune drops what is over a week old", H:Prune() >= 1, true)
check("nothing left of it", ns.db.priceHistory[realm][WOOL], nil)

ns.db.priceHistory[realm][12345] = "unreadable"
H:Prune()
check("an entry it cannot read is left alone", ns.db.priceHistory[realm][12345], "unreadable")

check("my prices untouched", ns.db.myPrices[realm][2589].price, 30)
check("favourites untouched", ns.db.favouritePrices[SILK], "Spider Silk")
check("prices untouched", ns.Prices:Get(OTHER) ~= nil, true)

-- An old save: no priceHistory at all, reading and pruning work.
ns.db.priceHistory = nil
check("an old save reads as no points", #H:GetPoints(WOOL), 0)
check("and prunes nothing", H:Prune(), 0)
check("and is not given an empty table by reading", ns.db.priceHistory, nil)

print("graph maths")
ns.Theme, ns.Widgets = {}, {}
assert(loadfile(lfs_cwd .. "/UI/PriceGraph.lua"))("Blackthornes_TS", ns)
local G = ns.PriceGraph
local placed, low, high = G.Layout({ { t = 0, p = 10 }, { t = 50, p = 30 }, { t = 100, p = 20 } }, 200, 40, 100, 100)
check("lowest", low, 10)
check("highest", high, 30)
check("x by time", placed[2].x, 100)
check("y by price, highest at the top", placed[2].y, 40)
check("lowest at the foot", placed[1].y, 0)
placed = G.Layout({ { t = 0, p = 10 }, { t = 100, p = 10 } }, 200, 40, 100, 100)
check("a flat line sits in the middle", placed[1].y, 20)

clock = now
ns.db.priceHistory = nil
ns.db.prices[realm] = { [OTHER] = { history = {
    { t = now - 2 * HOUR, m = 90 }, { t = now - HOUR, m = 95 },
} } }
local series, kind = G.Series(OTHER, "day", now)
check("an item not kept falls back to its scans", kind, "market")
check("with both of them", #series, 2)
series, kind = G.Series(WOOL, "day", now)
check("a kept item with no prices draws nothing yet", kind, nil)
check("the window is 24 hours by default", G.GetWindow(), "day")
check("ticks say now at the right", G.TickText("day", now, true), "now")

print("listed each hour")
clock = now
ns.db.priceHistory, ns.db.priceListed = nil, nil
ns.Prices:Record(WOOL, 40, 35, 120, now, 35, nil, nil)
ns.Prices:Record(WOOL, 40, 36, 90, now + HOUR, 36, nil, nil)
ns.Prices:Record(OTHER, 40, 36, 90, now + HOUR, 36, nil, nil)
clock = now + HOUR
local listed = H:GetListed(WOOL, 24 * HOUR)
check("Record keeps how many were listed each hour", #listed, 2)
check("the first hour's count", listed[1].q, 120)
check("the second hour's count", listed[2].q, 90)
check("an item not kept has no counts", ns.db.priceListed[realm][OTHER], nil)
ns.Prices:RecordEmpty(WOOL, now + 2 * HOUR)
clock = now + 2 * HOUR
listed = H:GetListed(WOOL, 24 * HOUR)
check("sold out is a count of none", listed[3] and listed[3].q, 0)
check("and adds no price", #H:GetPoints(WOOL, 24 * HOUR), 2)
check("the prices list keeps its old shape", type(ns.db.priceHistory[realm][WOOL][2]), "number")
clock = now + 30 * 24 * HOUR
H:Prune()
check("prune clears old counts too", ns.db.priceListed[realm][WOOL], nil)
ns.db.priceListed = nil
check("a save from before counts reads as none", #H:GetListed(WOOL), 0)

print("average and bars")
check("the average of what is shown", H.Average({ { p = 10 }, { p = 20 }, { p = 33 } }), 21)
check("nothing shown, no average", H.Average({}), nil)
local bars, most = G.LayoutBars({ { t = 0, q = 50 }, { t = 3600, q = 100 }, { t = 7200, q = 0 } },
    240, 100, 24 * 3600, 24 * 3600)
check("the most listed", most, 100)
check("an hour with none listed gets no bar", #bars, 2)
check("the tallest bar is the share of the height", bars[2].height, 100 * G.BAR_SHARE)
check("half as many, half as tall", bars[1].height, 50 * G.BAR_SHARE)
check("bars sit at their hour", bars[2].x, 10)
check("an hour wide, less a gap", bars[1].width, 9)
bars = G.LayoutBars({ { t = 0, q = 0 } }, 240, 100, 24 * 3600, 24 * 3600)
check("all sold out draws no bars", #bars, 0)

print(("%d passed, %d failed"):format(passed, failed))
if failed > 0 then error(("%d check(s) failed"):format(failed)) end
print("PASS -- the price graph keeps what it should, for as long as it should")
