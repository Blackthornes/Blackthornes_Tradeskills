-- What Equipment reads for its auction house upgrades (the owner said
-- build it, 2026-11-26): Prices:OnSale() gives what was listed at the
-- recent scans, read only, so Equipment never scans on its own.
--
-- What must hold:
--   1. Before any scan it gives nothing, and no time.
--   2. An item listed at a scan within 48 hours comes with its cheapest
--      posting, how many were up and when it was seen.
--   3. One seen longer ago, or with none up, is left out.
--   4. It changes nothing in the price table.

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

local priceTable = {}
local db = {}
ns.db = db
ns.Config = {
    Get = function(_, k)
        if k == "staleAfterSeconds" then return 48 * 3600 end
        return nil
    end,
    GetPriceTable = function() return priceTable end,
    GetRealmKey = function() return "Realm-Horde" end,
}
local clock = 1790000000
time = function() return clock end

assert(loadfile(lfs_cwd .. "/Core/Util.lua"))("Blackthornes_TS", ns)
assert(loadfile(lfs_cwd .. "/Data/Prices.lua"))("Blackthornes_TS", ns)
local Prices = ns.Prices

local failures = 0
local function check(label, got, expected)
    local ok = got == expected
    if not ok then failures = failures + 1 end
    print(("  %-52s %-12s %s"):format(label, tostring(got), ok and "ok" or
        ("FAILED, expected " .. tostring(expected))))
end

-- 1.
local list, at = Prices:OnSale()
check("before any scan: nothing", next(list), nil)
check("and no time", at, nil)

-- 2.
db.lastFullScanByRealm = { ["Realm-Horde"] = clock - 7200 }
Prices:Record(15230, 42000, 42000, 2, clock - 7200, 42000, nil)     -- an axe, 2 up
Prices:Record(9800, 17500, 17500, 1, clock - 3 * 86400, 17500, nil)  -- seen three days ago
Prices:Record(4500, 900, 900, 0, clock - 600, nil, nil)              -- none up
list, at = Prices:OnSale()
check("the last scan's time", at, clock - 7200)
check("the axe is on sale", list[15230] ~= nil, true)
check("at its cheapest posting", list[15230] and list[15230].price, 42000)
check("with how many were up", list[15230] and list[15230].count, 2)
check("and when it was seen", list[15230] and list[15230].seen, clock - 7200)

-- 3.
check("one seen three days ago is left out", list[9800], nil)
check("one with none up is left out", list[4500], nil)

-- 4.
check("the price table keeps its three", (function()
    local n = 0
    for _ in pairs(priceTable) do n = n + 1 end
    return n
end)(), 3)

print("")
if failures > 0 then
    error(("%d on-sale check(s) failed"):format(failures), 0)
end
print("PASS -- Equipment reads what the recent scans saw listed")
print("")
