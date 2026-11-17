-- One odd scan must not throw off an item's usual price (the owner,
-- 2026-10-28: a cloak that sold for about 10s read 45g after one scan saw
-- only two listed at 150g each).
--
--   1. A scan more than 3 times above or below the usual price is held back.
--   2. Three such scans in a row, the same way, and the usual price jumps
--      straight to the new one.
--   3. An ordinary scan in between starts the count again.
--   4. Ordinary scans average in as before; a new item takes its first scan.

local failures = 0
local function check(label, got, want)
  if got ~= want then
    failures = failures + 1
    print(string.format("  FAIL  %-52s got %s, wanted %s", label, tostring(got), tostring(want)))
  else
    print(string.format("  ok    %-52s %s", label, tostring(got)))
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
ns.Print, ns.PrintRaw, ns.Debug, ns.Warn = function() end, function() end, function() end, function() end
ns.Config = {
    Get = function() return nil end,
    GetPriceTable = function() return {} end,
}
ns.db = {}
time = time or os.time

assert(loadfile(lfs_cwd .. "/Data/Prices.lua"))("Blackthornes_TS", ns)
local Prices = ns.Prices

print("\nheld back")
local r = {}
Prices.Smooth(r, 1000)
check("a new item takes its first scan", r.market, 1000)
Prices.Smooth(r, 1100)
check("an ordinary scan averages in", r.market, 1030)
Prices.Smooth(r, 1500000)
check("one 150g scan is held back", r.market, 1030)
Prices.Smooth(r, 1000)
check("the next ordinary scan averages in", r.market, 1021)
check("and the count starts again", r.odd, nil)

print("\nbelieved after three")
Prices.Smooth(r, 50000)
Prices.Smooth(r, 52000)
check("two high scans: still held", r.market, 1021)
Prices.Smooth(r, 51000)
check("the third moves it straight there", r.market, 51000)

print("\ndown as well")
Prices.Smooth(r, 100)
Prices.Smooth(r, 200)
check("two low scans: still held", r.market, 51000)
Prices.Smooth(r, 300000)
check("a high one between starts the count again", r.odd.n, 1)
Prices.Smooth(r, 100)
check("one way only counts that way", r.odd.n, 1)

print("\nthe cloak")
local cloak = { market = 395319 }
Prices.Smooth(cloak, 9952)
Prices.Smooth(cloak, 10000)
Prices.Smooth(cloak, 9952)
check("a poisoned price comes back after three scans", cloak.market, 9952)

-- A player's report (2026-11-17): Wool Cloth said "A vendor pays more: 33c
-- each" while thousands sold near 1s 33c. A browse row is only the cheapest
-- listing; one cheap one replaced the rival price on record, and three such
-- rows in a row made it the usual price too.
print("\na lone cheap listing on the browse page")
do
    local store = {}
    ns.Config.GetPriceTable = function() return store end
    local WOOL = 2592
    -- A search for the item read the book: thousands near 1s 33c.
    Prices:Record(WOOL, 133, 130, 27793, 1000, 132, nil, nil, { 132, 400, 133, 2000 })
    for i = 1, 3 do
        Prices:Record(WOOL, 30, 30, 27793, 1000 + i * 120, 30, nil)
    end
    local wool = store[WOOL]
    check("three browse rows leave the usual price", wool.market, 133)
    check("and the cheapest rival on record", wool.rivalMin, 132)
    check("and count as no odd scan", wool.odd, nil)
    check("the cheap one is noted as a lone low", wool.ignoredLow, 30)
    check("it is still the cheapest to buy", wool.min, 30)
    check("the book's steps stay", wool.ladder and wool.ladder[1], 132)

    -- A browse row near the usual price is believed as before.
    Prices:Record(WOOL, 120, 120, 27793, 2000, 120, nil)
    check("a browse row near the usual price moves the rival", wool.rivalMin, 120)
    check("and averages in", wool.market, 129)

    -- A search that reads the whole book still counts toward an odd move.
    for i = 1, 3 do
        Prices:Record(WOOL, 30, 30, 900, 3000 + i, 30, nil, nil, { 30, 900 })
    end
    check("three searches still move a real drop", wool.market, 30)

    -- A browse row far above the usual is still counted (the cheapest is
    -- above it, so every listing is).
    store[7] = { market = 100, scans = 1, history = {} }
    for i = 1, 3 do Prices:Record(7, 400, 400, 5, 4000 + i, 400, nil) end
    check("three high browse rows still move it up", store[7].market, 400)
end

if failures > 0 then error(("%d check(s) failed"):format(failures)) end
print("\ntest_oddscan: ok")
