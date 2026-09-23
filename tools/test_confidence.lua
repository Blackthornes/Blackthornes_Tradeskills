-- What the confidence percentage blames, and when it should blame nothing.
--
-- The bug this guards against showed up in a real screenshot:
--
--     confidence 99% (stale data)
--
-- about a Linen Bag scanned seconds earlier. The reason was chosen with `<=`
-- comparisons that resolve ties in favour of the first branch, and an item
-- that is fresh, deep and often seen has all three component scores at 1. So
-- every tie went to age, and the line confidently named the one thing that
-- could not have been true.
--
-- A diagnostic that names the wrong cause is worse than one that says nothing,
-- because it sends you looking in the wrong place. Above the threshold there
-- is no weakness, so there is no reason.

local ns = {}
ns.COLORS = setmetatable({}, {__index = function() return "ffffffff" end})
ns.NewModule = function(name) local m = {}; ns[name] = m; return m end
ns.RegisterCommand = function() end
ns.RegisterEvent = function() end
ns.Print, ns.PrintRaw, ns.Debug, ns.Warn = function() end, function() end, function() end, function() end

-- Core/Util.lua builds a worker frame at load time. Nothing here drives it;
-- it only has to exist so the file loads outside the client.
CreateFrame = function()
    local frame = {}
    for _, name in ipairs({ "SetScript", "Show", "Hide", "SetPoint", "SetSize" }) do
        frame[name] = function() end
    end
    return frame
end

GetTime = function() return os.clock() end

local priceTable = {}
ns.Config = {
    Get = function(_, k)
        if k == "undercutCopper" then return 1 end
        if k == "staleAfterSeconds" then return 48 * 3600 end
        return nil
    end,
    GetPriceTable = function() return priceTable end,
}

time = time or os.time

assert(loadfile(lfs_cwd .. "/Core/Util.lua"))("Blackthornes_TS", ns)
assert(loadfile(lfs_cwd .. "/Data/Prices.lua"))("Blackthornes_TS", ns)

local Util, Prices = ns.Util, ns.Prices

local failures = 0

local function check(label, got, expected)
    local ok = got == expected
    if not ok then failures = failures + 1 end
    print(("  %-52s %-12s %s"):format(label, tostring(got), ok and "ok" or
        ("FAILED, expected " .. tostring(expected))))
end

local ITEM = 4238   -- Linen Bag

local function Seen(scans, quantity, secondsAgo)
    priceTable[ITEM] = nil
    for _ = 1, scans do
        Prices:Record(ITEM, 269, 300, quantity, time() - secondsAgo, 300, nil)
    end
end

--------------------------------------------------------------------------------
print("")
print("nothing is wrong with the data")

-- The screenshot's item: six scans, 308 listed, read moments ago.
Seen(6, 308, 0)

do
    local confidence, reason = Prices:GetConfidence(ITEM)
    check("confidence is high", confidence > 0.95, true)
    check("and nothing is blamed for it", reason, nil)
    check("in particular not the freshest thing about it", reason == "stale data", false)
end

--------------------------------------------------------------------------------
print("")
print("something is wrong with the data")

Seen(6, 308, 47 * 3600)
check("old data is called old", select(2, Prices:GetConfidence(ITEM)), "stale data")

Seen(6, 1, 0)
check("a market of one is called thin", select(2, Prices:GetConfidence(ITEM)), "few listed")

Seen(1, 308, 0)
check("a single look is called that", select(2, Prices:GetConfidence(ITEM)), "few scans")

--------------------------------------------------------------------------------
print("")
print("the weakest one is the one named")

-- Thin and slightly old at once. Depth is the lower of the two, so depth is
-- what gets named -- not whichever branch happens to be written first.
Seen(6, 2, 10 * 3600)
check("the lowest score wins, not the first test",
    select(2, Prices:GetConfidence(ITEM)), "few listed")

--------------------------------------------------------------------------------
print("")
print("never seen at all")

priceTable[9999] = nil
do
    local confidence, reason = Prices:GetConfidence(9999)
    check("no confidence", confidence, 0)
    check("and that is worth saying", reason, "never seen")
end

--------------------------------------------------------------------------------
print("")
print("how long ago, in a sentence")

-- The same screenshot carried "seen just now ago". FormatAge returns phrases
-- that are already complete, so appending " ago" to them does not work.
check("just now stands alone", Util.FormatAgeAgo(5), "just now")
check("never stands alone", Util.FormatAgeAgo(nil), "never")
check("a real age gets the word", Util.FormatAgeAgo(600), "10m ago")
check("and so does a long one", Util.FormatAgeAgo(3 * 86400), "3d ago")

--------------------------------------------------------------------------------
print("")
if failures > 0 then
    error(("%d confidence check(s) failed"):format(failures), 0)
end
print("PASS -- confidence blames something only when something is to blame")
print("")
