-- A craft is worth whichever pays more: the listing it would make, or a
-- vendor (Trent's rule, max(auction, vendor)).
--
-- With a rival listing under what a vendor pays, the Profit tab costed the
-- undercut: 7 Linen Cloth at 10c made a belt it would list at 59c, a 13c
-- loss after the cut, so the craft was hidden. A vendor pays 80c for it, a
-- 10c profit, and Posting refuses the 59c listing anyway ("a vendor pays
-- more than that"). Valued at the vendor there is no auction cut and no
-- deposit.

-- Tests share one Lua state, so every global replaced here is put back,
-- including the ones that were not set at all.
local GLOBALS = { "CreateFrame", "GetTime", "time", "C_Item" }
local saved = {}
for _, key in ipairs(GLOBALS) do saved[key] = _G[key] end

local function noop() end

CreateFrame = function()
    return setmetatable({}, { __index = function(_, k)
        if type(k) == "string" and k:match("^%u") then return noop end
    end })
end
GetTime = function() return 1000 end
time = function() return 100000 end

local BELT, LINEN, RECIPE = 5000, 2589, 300

-- What a vendor pays is the eleventh return: 80c for the belt.
C_Item = { GetItemInfo = function(itemID)
    return "item " .. itemID, "link", 1, 1, 1, "", "", 1, "", "", itemID == BELT and 80 or 1
end }

local recipe = { recipeID = RECIPE, name = "Linen Belt", outputItemID = BELT,
    quantityMin = 1, quantityMax = 1, reagents = { { itemID = LINEN, quantity = 7 } } }

local settings = { undercutCopper = 1, auctionCut = 0.05, expectedRelists = 1, minProfit = 0,
    staleAfterSeconds = 48 * 3600, valueOwnedMaterials = true, unscannedMarkupPercent = 50,
    priceUnscannedCrafts = true }

local ns = {}
ns.COLORS = setmetatable({}, { __index = function() return "ffffffff" end })
ns.NewModule = function(name) local m = {}; ns[name] = m; return m end
ns.RegisterEvent = noop
local commands, printed = {}, {}
ns.RegisterCommand = function(name, _, fn) commands[name] = fn end
ns.Print = function(text) printed[#printed + 1] = text end
ns.PrintRaw = function(text) printed[#printed + 1] = text end
ns.Debug, ns.Warn = noop, noop

local priceTable = {}
ns.Config = {
    Get = function(_, key) return settings[key] end,
    GetCharacterKey = function() return "Me" end,
    GetPriceTable = function() return priceTable end,
}
ns.Recipes = {
    GetAll = function() return { [RECIPE] = recipe } end,
    Get = function() return recipe end,
    GetAny = function() return recipe, "Me" end,
    GetAccountWide = function() return { [RECIPE] = recipe } end,
    GetCharacterName = function() return "Me" end,
    IsDropped = function() return false end,
    Find = function() return { recipe } end,
    GetDisplayLink = function() return "[Linen Belt]" end,
}
ns.Inventory = {
    GetBagCount = function() return 0 end, GetCharacterBagCount = function() return 0 end,
    GetBankCount = function() return 0 end, GetOwnedCount = function() return 0 end,
    GetAltTotal = function() return 0 end,
}
ns.Vendor = { GetUnitPrice = function() return nil end }
ns.Scanner = { GetCommodityStatus = function() return true end }
ns.Auctions = { GetRoom = function() return nil, 0, 0, 0, 0, 0 end }

assert(loadfile(lfs_cwd .. "/Core/Util.lua"))("Blackthornes_TS", ns)
assert(loadfile(lfs_cwd .. "/Data/Prices.lua"))("Blackthornes_TS", ns)
assert(loadfile(lfs_cwd .. "/Logic/Cost.lua"))("Blackthornes_TS", ns)
assert(loadfile(lfs_cwd .. "/Logic/Profit.lua"))("Blackthornes_TS", ns)

-- A deposit of 3c a belt is known from the last listing.
ns.Posting = { GetCachedUnitDeposit = function() return 3 end }

local Profit = ns.Profit

local passed, failed = 0, 0
local function check(label, got, want)
    local ok = got == want
    if ok then passed = passed + 1 else failed = failed + 1 end
    print(string.format("  %-58s %-10s %s", label, tostring(got), ok and "ok" or
        ("WRONG, wanted " .. tostring(want))))
end

local function Printed(fragment)
    for _, line in ipairs(printed) do
        if tostring(line):find(fragment, 1, true) then return true end
    end
    return false
end

-- Linen at 10c: 70c of materials a belt.
ns.Prices:Record(LINEN, 10, 10, 500, time(), 10, nil)

print("")
print("a rival lists the belt at 60c, under the vendor's 80c")

ns.Prices:Record(BELT, 65, 60, 4, time(), 60, nil)
local a = Profit:Analyse(RECIPE)
check("it is valued at what the vendor pays", a.unitRevenue, 80)
check("and says so", a.priceBasis, "vendor")
check("no auction cut", a.cut, 0)
check("no deposit", a.deposit, 0)
check("which is known, not missing", a.depositKnown, true)
check("so it makes 10c", a.profit, 10)
check("and is listed on the Profit tab", (Profit:GetRanked({ minProfit = 0 })[1] or {}).recipeID, RECIPE)
check("the rival is still shown beside it", a.competitorPrice, 60)
check("but not as a match", a.matchedRival, false)

printed = {}
commands.why("Linen Belt")
check("/bts why says the vendor pays more", Printed("a vendor pays more than a listing would"), true)
check("prices it as vendor pays", Printed("vendor pays     80"), true)
check("and takes no cut", Printed("auction cut     -"), false)

print("")
print("a rival at 2s, over the vendor")

ns.Prices:Record(BELT, 200, 200, 4, time(), 200, nil)
a = Profit:Analyse(RECIPE)
check("it is valued at the undercut", a.unitRevenue, 199)
check("as a listing", a.priceBasis, "undercut")
check("which pays the cut", a.cut, 199 * 0.05)
check("and the deposit", a.deposit, 3)

printed = {}
commands.why("Linen Belt")
check("/bts why shows the cut", Printed("auction cut     -"), true)

print("")
print("never scanned, with estimates from materials turned off")

priceTable[BELT] = nil
settings.priceUnscannedCrafts = false
a = Profit:Analyse(RECIPE)
check("the vendor's price still values it", a.unitRevenue, 80)
check("as a vendor sale", a.priceBasis, "vendor")
check("not as an estimate", a.priceDerived, nil)
check("so it can be ranked", a.priceable, true)

for _, key in ipairs(GLOBALS) do _G[key] = saved[key] end

print("")
print(("%d passed, %d failed"):format(passed, failed))
assert(failed == 0, "vendor value checks failed")
