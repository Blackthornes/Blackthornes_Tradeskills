-- Gathered materials are priced like gathered materials.
--
-- Light Leather is also a craft (three Ruined Leather Scraps make one), and
-- Medium and Heavy Leather are made from the leather below them. Most in the
-- bags were skinned, though, and they sell at the market's price. The Sell
-- list held Light Leather back as "below what the materials cost" whenever
-- three scraps were worth more than one Light Leather, so it never listed
-- (the owner, 2026-11-23). Trade goods are now priced by the market and the
-- vendor only. A real craft (a bag) keeps its cost.

-- Tests share one Lua state, so every global replaced here is put back.
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

-- Light Leather (a trade good) is also made from Ruined Leather Scraps.
-- Medium Leather, also a trade good, is made from Light Leather, and Heavy
-- from Medium. The bag is a real craft, made from wool, and keeps its cost.
local SCRAPS, LIGHT, MEDIUM, HEAVY, BAG, WOOL = 2934, 2318, 2319, 4234, 4245, 2592
local LIGHT_RECIPE, MEDIUM_RECIPE, HEAVY_RECIPE, BAG_RECIPE = 301, 302, 303, 201
local TRADE_GOODS = { [SCRAPS] = true, [LIGHT] = true, [MEDIUM] = true, [HEAVY] = true, [WOOL] = true }

C_Item = {
    GetItemInfo = function(itemID)
        -- The eleventh return is what a vendor pays: 1c, out of the way here.
        return "item " .. itemID, "link", 1, 1, 1, "", "", 1, "", "", 1
    end,
    -- The sixth return is the class: 7 is Trade Goods, 1 a container.
    GetItemInfoInstant = function(itemID)
        return itemID, "", "", "", 0, TRADE_GOODS[itemID] and 7 or 1, 0
    end,
}

local function Recipe(recipeID, name, output, reagent, count)
    return { recipeID = recipeID, name = name, outputItemID = output,
             quantityMin = 1, quantityMax = 1, reagents = { { itemID = reagent, quantity = count } } }
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

current = "Skinner"
byCharacter = { Skinner = {
    [LIGHT_RECIPE] = Recipe(LIGHT_RECIPE, "Light Leather", LIGHT, SCRAPS, 3),
    [MEDIUM_RECIPE] = Recipe(MEDIUM_RECIPE, "Medium Leather", MEDIUM, LIGHT, 4),
    [HEAVY_RECIPE] = Recipe(HEAVY_RECIPE, "Heavy Leather", HEAVY, MEDIUM, 5),
    [BAG_RECIPE] = Recipe(BAG_RECIPE, "Woolen Bag", BAG, WOOL, 10),
} }
Cost:InvalidateIndex()

-- Scraps at 50c, so three make 1s 50c of "materials" for one Light Leather,
-- while the auction house sells Light Leather at 34c. Wool at 30c, and
-- every listing of the bag is yours, at 2s.
ns.Prices:Record(SCRAPS, 50, 50, 200, time(), 50, nil)
ns.Prices:Record(LIGHT, 34, 34, 500, time(), 34, nil)
ns.Prices:Record(MEDIUM, 90, 90, 500, time(), 90, nil)
ns.Prices:Record(WOOL, 30, 30, 200, time(), 30, nil)
ns.Prices:Record(BAG, 200, 200, 2, time(), nil, 200)

print("")
print("gathered materials list at the market's price")

check("Light Leather at 33c is not held back by scraps", Posting:BelowCost(LIGHT, 33), nil)
check("nor Medium Leather by Light Leather", Posting:BelowCost(MEDIUM, 89), nil)
local price, basis = Profit:ChoosePostPrice(LIGHT)
check("Light Leather undercuts the market", price, 33)
check("as a plain undercut", basis, "undercut")

print("")
print("never scanned, a material is not priced from what it is made of")

check("Heavy Leather gets no made-up price", (Profit:ChoosePostPrice(HEAVY)), nil)

print("")
print("a real craft still keeps its cost")

check("the bag under its 3s of wool is held back", Posting:BelowCost(BAG, 200), 300)
check("its price still comes from its materials", (Profit:ChoosePostPrice(BAG)), 450)

for _, key in ipairs(GLOBALS) do _G[key] = saved[key] end

print("")
print(("%d passed, %d failed"):format(passed, failed))
assert(failed == 0, "gathered material checks failed")
