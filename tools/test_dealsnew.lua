-- The Deals tab's "New only" and NEW tag (a player asked, the owner agreeing
-- 2026-10-11).
--
-- What must hold:
--   1. The deals listed the first time on a realm are not new.
--   2. A deal first seen in the latest scan is new, and stops being new
--      once a later scan comes.
--   3. A deal not shown for a week starts over as new.
--   4. Each realm keeps its own.

local ns = {}
ns.NewModule = function(name) local m = {}; ns[name] = m; return m end
ns.RegisterCommand, ns.RegisterEvent = function() end, function() end
ns.Print, ns.Debug = function() end, function() end
ns.Util = {}

local realm, lastScan = "A", 1000
ns.Config = { GetRealmKey = function() return realm end, Get = function() return nil end }
ns.Prices = { GetLastScan = function() return lastScan end }
ns.db = {}

assert(loadfile(lfs_cwd .. "/Logic/VendorFlips.lua"))("Blackthornes_TS", ns)
local VendorFlips = ns.VendorFlips

local passed, failed = 0, 0
local function check(label, got, want)
    local ok = got == want
    if ok then passed = passed + 1 else failed = failed + 1 end
    print(string.format("  %-56s %-8s %s", label, tostring(got), ok and "ok" or
        ("WRONG, wanted " .. tostring(want))))
end

local function Rows(...)
    local rows = {}
    for _, id in ipairs({ ... }) do rows[#rows + 1] = { itemID = id } end
    VendorFlips:NoteSeen(rows)
    local byID = {}
    for _, row in ipairs(rows) do byID[row.itemID] = row end
    return byID
end

print("the first time on a realm")
local rows = Rows(1, 2)
check("a deal already there is not new", rows[1].isNew, false)
check("and has no first scan to show", rows[1].firstSeen, nil)

print("\na new scan")
lastScan = 2000
rows = Rows(1, 2, 3)
check("an old deal stays old", rows[2].isNew, false)
check("one found in this scan is new", rows[3].isNew, true)
check("and says when", rows[3].firstSeen, 2000)
rows = Rows(1, 2, 3)
check("redrawn, it is still new", rows[3].isNew, true)

lastScan = 3000
rows = Rows(1, 2, 3)
check("the next scan, it is not", rows[3].isNew, false)

print("\nlong gone and back")
lastScan = 3000 + VendorFlips.SEEN_FORGET + 10
Rows(1)
lastScan = lastScan + 10
rows = Rows(1, 3)
check("a deal shown all along stays old", rows[1].isNew, false)
check("one gone a week is new again", rows[3].isNew, true)

print("\nanother realm")
realm = "B"
rows = Rows(3)
check("its first time: not new", rows[3].isNew, false)

print("\nthe minimums box unticked")
realm, lastScan = "C", 100
Rows(1)
lastScan = 200
local function Mixed(spec)
    local list = {}
    for _, r in ipairs(spec) do list[#list + 1] = { itemID = r[1], clears = r[2] } end
    VendorFlips:NoteSeen(list)
    local byID = {}
    for _, row in ipairs(list) do byID[row.itemID] = row end
    return byID
end
rows = Mixed({ { 1, true }, { 99, false } })
check("an item under the minimums is not new", rows[99].isNew, false)
check("and is not written down", ns.db.dealsSeen.C.items[99], nil)
rows = Mixed({ { 98, false, }, })
rows[98] = nil
local merged = { itemID = 97, clears = false, others = { { itemID = 97, clears = true } } }
VendorFlips:NoteSeen({ merged })
check("a deal by another route counts", merged.isNew, true)
lastScan = 300
rows = Mixed({ { 99, true } })
check("once it clears them, it is new", rows[99].isNew, true)

print(("\n%d passed, %d failed"):format(passed, failed))
if failed > 0 then error(("%d deals-new check(s) failed"):format(failed)) end
