-- Gear, bags and wands match and undercut to the copper on Forever (tried in
-- game 2026-11-16, after a player's report): a 0c undercut against a rival at
-- 2g 45s 37c lists at 2g 45s 37c, not 2g 46s. The one silver floor stays, and
-- a listing with copper that fails to go up switches to whole silver for the
-- rest of the session (Posting:FallBackToWholeSilver).

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
time = time or os.time

--------------------------------------------------------------------------------
-- The world this test describes
--------------------------------------------------------------------------------

local BAG    = 7955   -- an item auction: gear, stacks to one
local CLOTH  = 2589   -- a commodity

local settings = {}
local prices = {}
local commodities = { [CLOTH] = true }

-- recipeByOutput[itemID] = recipeID, and the cost of making one batch.
local recipeByOutput = {}
local craftCost = {}
local unitDeposit = {}

ns.Config = { Get = function(_, key) return settings[key] end }

ns.Prices = {
    GetValue = function(_, itemID, key)
        local entry = prices[itemID]
        return entry and entry[key] or nil
    end,
    HoldsLowest = function() return false end,
}

ns.Scanner = { IsCommodity = function(_, itemID) return commodities[itemID] == true end }

ns.Cost = {
    FindRecipeForItem = function(_, itemID) return recipeByOutput[itemID] end,
    FindAnyRecipeForItem = function(_, itemID) return recipeByOutput[itemID] end,
    GetCraftCost = function(_, recipeID) return craftCost[recipeID] end,
}

ns.Recipes = {
    GetAny = function(_, recipeID) return { outputItemID = recipeID, name = "craft" } end,
}

-- These checks set a 1s least deposit (Forever's rule from 2026-11-06 to
-- 2026-11-10) to test the floor; the 1c rule now is in test_mindeposit.lua.
ns.Posting = {
    MIN_DEPOSIT = 100,
    GetCachedUnitDeposit = function(_, itemID) return unitDeposit[itemID] end,
}

assert(loadfile(lfs_cwd .. "/Core/Util.lua"))("Blackthornes_TS", ns)
assert(loadfile(lfs_cwd .. "/Logic/Profit.lua"))("Blackthornes_TS", ns)

local Util, Profit = ns.Util, ns.Profit

local function Reset()
    settings = { undercutCopper = 1, auctionCut = 0.05, expectedRelists = 1, minProfit = 0 }
    prices = {}
    recipeByOutput = {}
    craftCost = {}
    unitDeposit = {}
end

--------------------------------------------------------------------------------

local failures = 0

local function check(label, got, expected)
    local ok = got == expected
    if not ok then failures = failures + 1 end
    print(("  %-56s %-8s %s"):format(label, tostring(got), ok and "ok" or
        ("FAILED, expected " .. tostring(expected))))
end

print("")
print("prices on their own")

check("2s 99c is a price an item auction takes", Util.IsItemAuctionPrice(299), true)
check("under a silver is not", Util.IsItemAuctionPrice(99), false)
check("a part copper is not", Util.IsItemAuctionPrice(250.5), false)
check("2s 99c stays 2s 99c", Util.ItemAuctionPrice(299), 299)
check("2s 99.6c rounds down to the copper", Util.ItemAuctionPrice(299.6), 299)
check("2s 99.2c rounds up to the copper", Util.ItemAuctionPriceUp(299.2), 300)
check("50c is lifted to the one silver floor", Util.ItemAuctionPrice(50), 100)
check("and upward too", Util.ItemAuctionPriceUp(50), 100)

print("")
print("the report: 0c undercut against a rival at 2g 45s 37c")

Reset()
settings.undercutCopper = 0
prices[BAG] = { market = 25000, rival = 24537 }
do
    local price, basis = Profit:ChoosePostPrice(BAG)
    check("matched to the copper", price, 24537)
    check("and says it matched", basis, "match")
end

print("")
print("a 1c undercut on gear")

Reset()
prices[BAG] = { market = 25000, rival = 24537 }
recipeByOutput[BAG] = BAG
craftCost[BAG] = { priceable = true, total = 1000, perUnit = 1000, yield = 1 }
do
    local price, basis = Profit:ChoosePostPrice(BAG)
    check("one copper under the rival", price, 24536)
    check("and says it undercut", basis, "undercut")
end

print("")
print("a rival at the floor")

Reset()
prices[BAG] = { market = 100, rival = 100 }
do
    local price = Profit:ChoosePostPrice(BAG)
    check("nothing under one silver, so it matches", price, 100)
end

print("")
print("the fallback after a copper listing failed")

Util.wholeSilverOnly = true
Reset()
settings.undercutCopper = 0
prices[BAG] = { market = 25000, rival = 24537 }
do
    local price = Profit:ChoosePostPrice(BAG)
    check("0c undercut rounds up to whole silver", price, 24600)
    check("never under the rival", price >= 24537, true)
end
Util.wholeSilverOnly = false

print("")
if failures > 0 then
    error(failures .. " copper gear check(s) failed")
end
print("all copper gear checks passed")
