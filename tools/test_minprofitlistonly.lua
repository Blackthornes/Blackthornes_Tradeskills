-- Post at Minimum Profit lists only what is in the bags at the minimum.
--
-- The owner (2026-11-17): turning it on made the Profit tab show every craft
-- as worth making, because the Profit tab prices crafts through the same
-- chooser the Sell tab lists at, and that chooser lifted every undercut
-- price up to the least that makes the Minimum Profit. Now only listing
-- what is already in the bags (Posting:GetPostPrice) gets the lift.

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
local settings = { undercutCopper = 1, auctionCut = 0.05, expectedRelists = 1, minProfit = 100, postAtMinProfit = false,
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

local crafts = { [BAG_RECIPE] = Recipe(BAG_RECIPE, "Woolen Reagent Bag", BAG) }
current, byCharacter = "Crafter", { Crafter = crafts }
Cost:InvalidateIndex()

-- Ten wool at 30c is 3s of materials. Others sell the bag for 2s.
ns.Prices:Record(WOOL, 30, 30, 200, time(), 30, nil)
ns.Prices:Record(BAG, 200, 200, 3, time(), 200, nil)

local function Walk(label)
    print("")
    print(label)
    local row = Profit:Analyse(BAG_RECIPE)
    check("the Profit tab prices the bag at what others ask", row.unitRevenue, 199)
    check("so it shows a loss", row.profit ~= nil and row.profit < 0, true)
end

Walk("Post at Minimum Profit off")
local offPrice = Posting:GetPostPrice(BAG, false)
check("the Sell list follows others down", offPrice, 199)

settings.postAtMinProfit = true
Walk("Post at Minimum Profit on")
local onPrice, basis = Posting:GetPostPrice(BAG, false)
check("the bag in your bags lists at your minimum", basis, "minprofit")
check("at a price that covers the 3s of materials and 1s profit", onPrice ~= nil and onPrice >= 400, true)
local tabPrice = Profit:ChoosePostPrice(BAG)
check("a craft list asking the price still sees what others ask", tabPrice, 199)
settings.postAtMinProfit = false

for _, key in ipairs(GLOBALS) do _G[key] = saved[key] end

print("")
print(("%d passed, %d failed"):format(passed, failed))
assert(failed == 0, "post at minimum profit list-only checks failed")
