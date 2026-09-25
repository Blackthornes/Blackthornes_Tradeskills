-- The price step an item auction imposes, and what to do about it.
--
-- C_AuctionHouse.PostItem takes whole gold and silver only. A price with any
-- copper in it is swallowed silently: no listing, no error worth reading, and
-- from the player's side an internal error on a button that did nothing. That
-- is what a Linen Bag at 2s 99c did, while 3s and 4s both went up fine.
--
-- Which makes a copper undercut impossible on item auctions. The smallest
-- available step down is a whole silver, and against 252 rivals sitting at 3s
-- that is a third of the price given away to beat sellers who could simply
-- have been matched. So the rule is match at the silver, and only spend the
-- extra silver when the sale still clears the minimum profit setting.
--
-- Commodities are untouched -- they take copper, and Linen Cloth has listed at
-- 29c and 32c all along.

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
    GetCraftCost = function(_, recipeID) return craftCost[recipeID] end,
}

ns.Recipes = {
    GetAny = function(_, recipeID) return { outputItemID = recipeID, name = "craft" } end,
}

ns.Posting = {
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

--------------------------------------------------------------------------------
print("")
print("rounding on its own")

check("2s 99c is not a price an item auction takes", Util.IsWholeSilver(299), false)
check("3s is", Util.IsWholeSilver(300), true)
check("2s 99c rounds down to 2s", Util.RoundToSilver(299), 200)
check("2s 50c rounds down to 2s", Util.RoundToSilver(250), 200)
check("3s is already there", Util.RoundToSilver(300), 300)
check("1g 0s 1c loses the copper", Util.RoundToSilver(10001), 10000)

-- Below a silver there is nothing to round down to. Listing above market
-- value is bad; sending a price the server discards is worse.
check("50c has no lower step, so one silver", Util.RoundToSilver(50), 100)
check("1c likewise", Util.RoundToSilver(1), 100)
check("nothing in, nothing out", Util.RoundToSilver(nil), nil)

-- Upwards, for a price with no rival under it to worry about.
check("2s 99c rounds up to 3s", Util.CeilToSilver(299), 300)
check("3s is already there", Util.CeilToSilver(300), 300)
check("50c has no lower step, so one silver", Util.CeilToSilver(50), 100)
check("nothing in, nothing out", Util.CeilToSilver(nil), nil)

--------------------------------------------------------------------------------
print("")
print("the Linen Bag, as it actually happened")

Reset()
prices[BAG] = { market = 320, rival = 300 }

do
    -- Nothing tells us what a bag costs to make, so there is no case for
    -- handing a silver over.
    local price, basis = Profit:ChoosePostPrice(BAG)
    check("no cost known: matches the rival at 3s", price, 300)
    check("no cost known: and says so", basis, "match")
    check("never the price that was refused", price ~= 299, true)
    check("always a price the server takes", Util.IsWholeSilver(price), true)
end

do
    -- 1s to make. Undercutting to 2s nets 190c against 100c of materials, so
    -- the silver buys a sale worth having.
    recipeByOutput[BAG] = BAG
    craftCost[BAG] = { priceable = true, total = 100, perUnit = 100, yield = 1 }

    local price, basis = Profit:ChoosePostPrice(BAG)
    check("profit survives the silver: undercuts to 2s", price, 200)
    check("profit survives the silver: and says so", basis, "undercut")
end

do
    -- The same craft with a minimum profit of 1s set. 2s leaves 90c, which is
    -- under it; 3s leaves 185c, which is not.
    settings.minProfit = 100

    local price, basis = Profit:ChoosePostPrice(BAG)
    check("minimum profit not met at 2s: matches at 3s", price, 300)
    check("minimum profit not met at 2s: and says so", basis, "match")
end

do
    -- A deposit is a real cost of listing, so it can be what tips the balance.
    settings.minProfit = 0
    craftCost[BAG] = { priceable = true, total = 180, perUnit = 180, yield = 1 }
    unitDeposit[BAG] = 40

    check("deposit counted: 2s no longer pays, so match", Profit:ChoosePostPrice(BAG), 300)

    unitDeposit[BAG] = nil
    check("without it, 2s pays and undercuts", Profit:ChoosePostPrice(BAG), 200)
end

--------------------------------------------------------------------------------
print("")
print("saying why it matched")

-- "match" on its own does not distinguish "the numbers said no" from "nobody
-- ever costed this", and those want different things from the player.
Reset()
prices[BAG] = { market = 320, rival = 300 }

do
    local _, basis, why = Profit:ChoosePostPrice(BAG)
    check("uncosted item: still a match", basis, "match")
    check("uncosted item: blames the missing cost",
        why and why:find("cost to make this is unknown") ~= nil, true)
end

do
    settings.minProfit = 100
    recipeByOutput[BAG] = BAG
    craftCost[BAG] = { priceable = true, total = 100, perUnit = 100, yield = 1 }

    local _, basis, why = Profit:ChoosePostPrice(BAG)
    check("priced out: still a match", basis, "match")
    check("priced out: blames the minimum",
        why and why:find("minimum") ~= nil, true)
end

do
    settings.minProfit = 0

    local _, basis, why = Profit:ChoosePostPrice(BAG)
    check("an undercut needs no explaining", basis, "undercut")
    check("so there is none", why, nil)
end

do
    -- Nothing below a rival at one silver, which is its own reason.
    Reset()
    prices[BAG] = { market = 100, rival = 100 }

    local _, _, why = Profit:ChoosePostPrice(BAG)
    check("no legal price below: says so",
        why and why:find("no lower price") ~= nil, true)
end

--------------------------------------------------------------------------------
print("")
print("rivals with nowhere below them")

Reset()

prices[BAG] = { market = 100, rival = 100 }
check("a rival at 1s cannot be undercut", Profit:ChoosePostPrice(BAG), 100)
check("so it is matched", select(2, Profit:ChoosePostPrice(BAG)), "match")

-- A rival price carrying copper should not exist on this client, but a stale
-- scan or a derived unit price can still produce one.
prices[BAG] = { market = 400, rival = 350 }
check("a rival at 3s 50c rounds to the same silver", Profit:ChoosePostPrice(BAG), 300)
check("and that counts as matching, not undercutting",
    select(2, Profit:ChoosePostPrice(BAG)), "match")

--------------------------------------------------------------------------------
print("")
print("nobody listed")

Reset()

prices[BAG] = { market = 299 }
check("market value is rounded too", Profit:ChoosePostPrice(BAG), 200)
check("and reported as market", select(2, Profit:ChoosePostPrice(BAG)), "market")

prices[BAG] = { market = 30 }
check("a near-worthless item still gets a legal price", Profit:ChoosePostPrice(BAG), 100)

prices[BAG] = {}
check("nothing to go on: no price", Profit:ChoosePostPrice(BAG), nil)
check("nothing to go on: no basis", select(2, Profit:ChoosePostPrice(BAG)), nil)

--------------------------------------------------------------------------------
print("")
print("commodities are left alone")

Reset()

prices[CLOTH] = { market = 32, rival = 30 }
check("a copper undercut is still a copper", Profit:ChoosePostPrice(CLOTH), 29)
check("and still an undercut", select(2, Profit:ChoosePostPrice(CLOTH)), "undercut")

prices[CLOTH] = { market = 32 }
check("market value keeps its copper", Profit:ChoosePostPrice(CLOTH), 32)

prices[CLOTH] = { market = 2, rival = 1 }
check("and never goes below a copper", Profit:ChoosePostPrice(CLOTH), 1)

--------------------------------------------------------------------------------
print("")
if failures > 0 then
    error(("%d silver-step check(s) failed"):format(failures), 0)
end
print("PASS -- item auctions are priced in whole silver, commodities in copper")
print("")
