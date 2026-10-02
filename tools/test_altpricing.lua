-- A craft priced the same whoever is logged in.
--
-- The recipe behind an item was looked up among the logged-in character's
-- crafts only. On a bank alt posting what the crafter mailed it, and on the
-- Profit tab with "All characters" ticked, an alt's craft was then priced as
-- if nobody could make it:
--   * every listing yours: market value (your own old price), not the markup
--     over materials;
--   * never scanned: "output has no price data", so the row was hidden;
--   * a rival on an item auction: matched, never undercut, "the cost to make
--     this is unknown";
--   * listing below what the materials cost was not refused.
-- Sub-crafts still come from the logged-in character's own crafts.

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

local BAG, SATCHEL, WOOL = 4245, 4246, 2592       -- the satchel: never scanned
local BAG_RECIPE, SATCHEL_RECIPE = 201, 203

C_Item = { GetItemInfo = function(itemID)
    -- The eleventh return is what a vendor pays: 1c, out of the way here.
    return "item " .. itemID, "link", 1, 1, 1, "", "", 1, "", "", 1
end }

local function Recipe(recipeID, name, output)
    return { recipeID = recipeID, name = name, outputItemID = output,
             quantityMin = 1, quantityMax = 1, reagents = { { itemID = WOOL, quantity = 10 } } }
end

local byCharacter, current
local settings = { undercutCopper = 1, auctionCut = 0.05, expectedRelists = 1, minProfit = 0,
    staleAfterSeconds = 48 * 3600, valueOwnedMaterials = true, unscannedMarkupPercent = 50,
    priceUnscannedCrafts = true }
local itemAuction = {}

local ns = {}
ns.COLORS = setmetatable({}, { __index = function() return "ffffffff" end })
ns.NewModule = function(name) local m = {}; ns[name] = m; return m end
ns.RegisterCommand, ns.RegisterEvent = noop, noop
ns.Print, ns.PrintRaw, ns.Debug, ns.Warn = noop, noop, noop, noop

local priceTable = {}
ns.Config = {
    Get = function(_, key) return settings[key] end,
    GetCharacterKey = function() return current end,
    GetPriceTable = function() return priceTable end,
}
ns.Recipes = {
    GetAll = function() return byCharacter[current] or {} end,
    Get = function(_, recipeID) return (byCharacter[current] or {})[recipeID] end,
    GetAny = function(_, recipeID)
        local mine = (byCharacter[current] or {})[recipeID]
        if mine then return mine, current end
        for key, list in pairs(byCharacter) do
            if list[recipeID] then return list[recipeID], key end
        end
    end,
    GetAccountWide = function()
        local all = {}
        for _, list in pairs(byCharacter) do
            for recipeID, recipe in pairs(list) do all[recipeID] = recipe end
        end
        return all
    end,
    GetCharacterName = function(_, key) return key end,
    IsDropped = function() return false end,
}
ns.Inventory = {
    GetBagCount = function() return 0 end, GetCharacterBagCount = function() return 0 end,
    GetBankCount = function() return 0 end, GetOwnedCount = function() return 0 end,
    GetAltTotal = function() return 0 end,
}
ns.Vendor = { GetUnitPrice = function() return nil end }
ns.Scanner = { GetCommodityStatus = function(_, itemID) return not itemAuction[itemID] end }
ns.Auctions = { GetRoom = function() return nil, 0, 0, 0, 0, 0 end }

assert(loadfile(lfs_cwd .. "/Core/Util.lua"))("Blackthornes_TS", ns)
assert(loadfile(lfs_cwd .. "/Data/Prices.lua"))("Blackthornes_TS", ns)
assert(loadfile(lfs_cwd .. "/Logic/Cost.lua"))("Blackthornes_TS", ns)
assert(loadfile(lfs_cwd .. "/Logic/Profit.lua"))("Blackthornes_TS", ns)
assert(loadfile(lfs_cwd .. "/Logic/Posting.lua"))("Blackthornes_TS", ns)

local Cost, Profit, Posting = ns.Cost, ns.Profit, ns.Posting

local passed, failed = 0, 0
local function check(label, got, want)
    local ok = got == want
    if ok then passed = passed + 1 else failed = failed + 1 end
    print(string.format("  %-60s %-12s %s", label, tostring(got), ok and "ok" or
        ("WRONG, wanted " .. tostring(want))))
end

-- Wool at 30c, so ten of it is 3s of materials, and 4s 50c with the 50%
-- markup. Every listing of the bag is yours, at 2s.
ns.Prices:Record(WOOL, 30, 30, 200, time(), 30, nil)
ns.Prices:Record(BAG, 200, 200, 2, time(), nil, 200)

local function LogIn(key, recipesBy)
    current, byCharacter = key, recipesBy
    Cost:InvalidateIndex()
end

local function Prices(label)
    print("")
    print(label)
    local bag = Profit:Analyse(BAG_RECIPE)
    local satchel = Profit:Analyse(SATCHEL_RECIPE)
    check("the bag sells at the markup", bag.unitRevenue, 450)
    check("as nothing else is listed", bag.priceBasis, "uncontested")
    check("the never-scanned satchel is priced from materials", satchel.unitRevenue, 450)
    check("as an estimate", satchel.priceBasis, "derived")

    local price, basis = Profit:ChoosePostPrice(BAG)
    check("the Sell tab lists the bag at the markup", price, 450)
    check("for the same reason", basis, "uncontested")
end

local crafts = { [BAG_RECIPE] = Recipe(BAG_RECIPE, "Woolen Reagent Bag", BAG),
                 [SATCHEL_RECIPE] = Recipe(SATCHEL_RECIPE, "Woolen Satchel", SATCHEL) }

LogIn("Crafter", { Crafter = crafts })
Prices("logged in on the crafter")

LogIn("Bank", { Crafter = crafts, Bank = {} })
Prices("logged in on a bank alt that knows none of it")

print("")
print("a rival on an item auction, seen from the bank alt")

itemAuction[BAG] = true
ns.Prices:Record(BAG, 600, 600, 3, time(), 600, nil)
do
    local price, basis, why = Profit:ChoosePostPrice(BAG)
    check("it undercuts to the next silver down", price, 500)
    check("rather than matching", basis, "undercut")
    check("with no word of an unknown cost", why, nil)
end

print("")
print("listing below what the materials cost, from the bank alt")

check("2s is refused: the materials cost 3s", Posting:BelowCost(BAG, 200), 300)
check("4s is let through", Posting:BelowCost(BAG, 400), nil)
settings.allowPostingAtALoss = true
check("and 2s is let through with selling at a loss on", Posting:BelowCost(BAG, 200), nil)
settings.allowPostingAtALoss = nil

print("")
print("sub-crafts stay with who is logged in")

check("the bank alt is not offered the bag as a sub-craft", Cost:FindRecipeForItem(BAG), nil)
check("but prices it off the crafter's recipe", Cost:FindAnyRecipeForItem(BAG), BAG_RECIPE)
LogIn("Crafter", { Crafter = crafts })
check("the crafter is offered it", Cost:FindRecipeForItem(BAG), BAG_RECIPE)

for _, key in ipairs(GLOBALS) do _G[key] = saved[key] end

print("")
print(("%d passed, %d failed"):format(passed, failed))
assert(failed == 0, "alt pricing checks failed")
