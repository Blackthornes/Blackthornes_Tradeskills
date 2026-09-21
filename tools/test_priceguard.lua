-- The price database must never store a number nobody could pay.
--
-- A full scan on 2026-09-21 read a listing at 9,999,990,200 copper (about
-- 999,999g), recorded it as that item's market value and minimum, and then
-- failed the whole database save on it. Serialize can write the number now,
-- but the number was still junk: the cap on a classic-era purse is 2^31
-- copper, so nothing can be bought at that price and no craft should be
-- ranked on it.

local ns = {}
ns.COLORS = setmetatable({}, { __index = function() return "ffffffff" end })
ns.Util = { Clamp = function(v, l, h) return math.max(l, math.min(h, v)) end,
            Count = function(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end,
            FormatMoney = function(c) return tostring(c) end,
            FormatAge = function() return "" end,
            HasFunction = function() return false end,
            GetItemLabel = function(i) return "item" .. tostring(i) end }
ns.NewModule = function(_) return {} end
ns.RegisterCommand = function() end
ns.Print, ns.PrintRaw, ns.Debug, ns.Warn = function() end, function() end, function() end, function() end

local priceTable = {}
ns.Config = {
    Get = function(_, k) if k == "undercutCopper" then return 1 end return 0 end,
    GetPriceTable = function() return priceTable end,
}

-- The addon runs on WoW's `time()`; outside the client os.time is the same idea.
time = time or os.time

local chunk = assert(loadfile(lfs_cwd .. "/Data/Prices.lua"))
local Prices
do
    local realNew = ns.NewModule
    ns.NewModule = function(name) local m = realNew(name); ns[name] = m; Prices = m; return m end
    chunk("Blackthornes_TS", ns)
end

local failures = 0

local function check(label, condition, detail)
    print(string.format("  %-44s %s", label, condition and "ok" or ("FAIL " .. tostring(detail))))
    if not condition then failures = failures + 1 end
end

print("")

-- The boundary itself, both sides of it.
check("the cap is payable", Prices.IsCredible(2 ^ 31 - 1))
check("one copper past the cap is not", not Prices.IsCredible(2 ^ 31))
check("the price from the failed save is not", not Prices.IsCredible(9999990200), 9999990200)
check("an ordinary price is", Prices.IsCredible(4 * 10000 + 64))
check("no price at all is not a junk price", Prices.IsCredible(nil))
check("NaN is refused", not Prices.IsCredible(0 / 0))
check("infinity is refused", not Prices.IsCredible(math.huge))

-- A junk price must not become what an item is worth.
priceTable[3371] = nil
local record = Prices:Record(3371, 9999990200, 9999990200, 1, time())
check("a junk market value records nothing", record == nil and priceTable[3371] == nil,
    priceTable[3371] and priceTable[3371].market)

-- An item that already had a sane price keeps it.
priceTable[2589] = nil
Prices:Record(2589, 1200, 1100, 40, time())
local before = priceTable[2589].market
Prices:Record(2589, 9999990200, 9999990200, 1, time())
check("a junk scan does not overwrite a good price", priceTable[2589].market == before,
    priceTable[2589].market)

-- One absurd figure alongside a sane market value costs only itself.
priceTable[2592] = nil
Prices:Record(2592, 500, 450, 10, time(), 9999990200, nil)
check("a junk rival price is dropped, the record kept",
    priceTable[2592] ~= nil and priceTable[2592].market == 500 and priceTable[2592].rivalMin == nil,
    priceTable[2592] and priceTable[2592].rivalMin)

-- The count is there so a scan can say what it threw away.
local refused = Prices:TakeImplausibleCount()
check("refusals are counted", refused == 2, refused)
check("and the count resets when taken", Prices:TakeImplausibleCount() == 0)

-- A database restored with a junk price in it is cleaned on the way in.
priceTable[3371] = { market = 9999990200, min = 9999990200, scans = 1, history = {} }
priceTable[2589] = { market = 1200, min = 9999990200, rivalMin = 1100, scans = 1, history = {} }
local dropped, cleared = Prices:Scrub()
check("a restored junk record is dropped", dropped == 1 and priceTable[3371] == nil, dropped)
check("a restored junk figure is cleared, record kept",
    cleared == 1 and priceTable[2589] ~= nil and priceTable[2589].min == nil
        and priceTable[2589].market == 1200, cleared)

-- A listing at a junk price must never reach Summarise as the market, but a
-- book of sane listings alongside one is still a book.
local market, min = Prices:Summarise({
    { unitPrice = 100, quantity = 5, isOwn = false },
    { unitPrice = 120, quantity = 5, isOwn = false },
})
check("a sane book still summarises", market ~= nil and min == 100, tostring(market))

print("")
if failures > 0 then
    error(failures .. " price guard failure(s)")
end
print("all price guard tests passed")
print("")
