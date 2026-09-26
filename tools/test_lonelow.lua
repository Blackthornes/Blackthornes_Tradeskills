-- A lone listing far below everything else is not the price to undercut.
--
-- Trent, 2026-09-26: "make undercut ignore a lone low posting". One seller's
-- single listing under a third of the next listing up (and under a third of
-- the stored market value, when there is one) is skipped: the cheapest rival
-- becomes the next real seller and market value leaves it out. Two listings
-- down there are a real price drop and are kept.

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
ns.Print, ns.PrintRaw, ns.Debug, ns.Warn = function() end, function() end, function() end, function() end
local priceTable = {}
ns.Config = {
    Get = function() return nil end,
    GetPriceTable = function() return priceTable end,
}
ns.db = {}
time = time or os.time

assert(loadfile(lfs_cwd .. "/Data/Prices.lua"))("Blackthornes_TS", ns)
local Prices = ns.Prices

local checks = 0
local function check(label, condition)
    checks = checks + 1
    if not condition then error(("FAILED: %s"):format(label), 2) end
    print(("  ok  %s"):format(label))
end

local function L(price, quantity, own)
    return { unitPrice = price, quantity = quantity or 1, isOwn = own or false }
end

print("\na lone low listing")

-- One troll at 1s, a shelf at 50s.
local market, min, qty, rival, own, ignored = Prices:Summarise({
    L(5000, 2), L(100, 1), L(5100, 3), L(5200, 4),
})
check("the lone listing is not the price to beat", rival == 5000)
check("and is reported as ignored", ignored == 100)
check("the true cheapest is still the buy price", min == 100)
check("quantity still counts it", qty == 10)
check("market value leaves it out", market >= 5000)

-- Two listings down low: a real drop, kept.
_, _, _, rival, _, ignored = Prices:Summarise({ L(100), L(110), L(5000, 5) })
check("two low listings are a real drop", rival == 100 and ignored == nil)

-- Not far enough below.
_, _, _, rival, _, ignored = Prices:Summarise({ L(2000), L(5000, 5) })
check("under the next but not by two thirds is kept", rival == 2000 and ignored == nil)

-- Nothing above it to judge against.
_, _, _, rival, _, ignored = Prices:Summarise({ L(100) })
check("a listing on its own is kept", rival == 100 and ignored == nil)

-- The player's own cheap listing is never treated as a troll.
_, _, _, rival, own, ignored = Prices:Summarise({ L(100, 1, true), L(5000, 5) })
check("your own low listing is not skipped", own == 100 and rival == 5000 and ignored == nil)

-- A stored market value vetoes it: the rest of the book is what is odd.
_, _, _, rival, _, ignored = Prices:Summarise({ L(1000), L(5000, 5) }, 1200)
check("near the known market value it is kept", rival == 1000 and ignored == nil)
_, _, _, rival, _, ignored = Prices:Summarise({ L(100), L(5000, 5) }, 4800)
check("far under the known market value it is skipped", rival == 5000 and ignored == 100)

-- Only the lone listing and your own above it: nobody left to undercut.
_, _, _, rival, own, ignored = Prices:Summarise({ L(100), L(5000, 1, true) })
check("with only yours above, there is no rival", rival == nil and own == 5000 and ignored == 100)

-- The caller's table is not changed.
local book = { L(100), L(5000, 5) }
Prices:Summarise(book)
check("the listings passed in are left alone", #book == 2)

-- Recorded, then cleared by an empty search.
local listings = { L(100), L(5000, 5), L(5100, 5) }
local m2, mn2, q2, r2, o2, i2 = Prices:Summarise(listings)
Prices:Record(2589, m2, mn2, q2, time(), r2, o2, i2)
check("the ignored price is stored", priceTable[2589].ignoredLow == 100 and priceTable[2589].rivalMin == 5000)
Prices:RecordEmpty(2589)
check("an empty search clears it", priceTable[2589].ignoredLow == nil)

-- A full scan passes the stored market value in.
priceTable[4306] = { market = 1100, scans = 1, history = {} }
Prices:CommitScan({ [4306] = { L(1000), L(5000, 5) } })
check("a full scan uses the stored market value", priceTable[4306].rivalMin == 1000 and priceTable[4306].ignoredLow == nil)

print(("\n%d check(s) passed\n"):format(checks))
