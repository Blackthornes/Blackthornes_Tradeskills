-- Overcutting (the owner, 2026-10-15): optionally post just under the big
-- stack instead of 1c under a few cheap listings that will sell first.
--
-- What must hold:
--   1. Off, nothing changes: the price is 1c under the cheapest.
--   2. On, with a few cheap ones under a big stack and enough sales a day,
--      the price is 1c under the big stack.
--   3. It falls back to the usual undercut when the cheaper ones would not
--      sell within a day, when no step is a big stack, when the steps are
--      old or no longer start at the cheapest, when it would sit far over
--      market value, when the item sells slowly, and for gear.
--   4. Your auctions just under the big stack are not called undercut.
--   5. A scan keeps when it read the steps.

local ns = {}
ns.COLORS = setmetatable({}, {__index = function() return "ffffffff" end})
ns.NewModule = function(name) local m = {}; ns[name] = m; return m end
ns.RegisterCommand = function() end
ns.RegisterEvent = function() end
ns.Print, ns.PrintRaw, ns.Debug, ns.Warn = function() end, function() end, function() end, function() end

local savedTime, savedGetTime, savedCreateFrame, savedItem = time, GetTime, CreateFrame, C_Item

CreateFrame = function()
    local frame = {}
    for _, name in ipairs({ "SetScript", "Show", "Hide", "SetPoint", "SetSize" }) do
        frame[name] = function() end
    end
    return frame
end

local clock = 2000000
time = function() return clock end
GetTime = function() return clock end

local SILK, BAG = 4305, 4245

local settings
local commodityStatus = {}

ns.Config = {
    Get = function(_, key) return settings[key] end,
    GetCharacterKey = function() return "Tester-Realm" end,
}
ns.Recipes = {
    GetAll = function() return {} end,
    GetAny = function() return nil end,
    Get = function() return nil end,
}
ns.Inventory = {
    GetBagCount = function() return 0 end,
    GetCharacterBagCount = function() return 0 end,
    GetBankCount = function() return 0 end,
    GetOwnedCount = function() return 0 end,
    GetAltTotal = function() return 0 end,
}
ns.Vendor = { GetUnitPrice = function() return nil end }
ns.Scanner = {
    GetCommodityStatus = function(_, itemID) return commodityStatus[itemID] end,
    IsCommodity = function(_, itemID) return commodityStatus[itemID] == true end,
}
ns.Posting = { GetCachedUnitDeposit = function() return nil end }
ns.Auctions = {
    GetRoom = function() return nil, 0, 0, 0, nil, 0 end,
    GetPostedCount = function() return 0 end,
}
C_Item = { GetItemInfo = function() return "item", "link", 1, 1, 1, "", "", 1, "", "", 0 end }

local priceTable = {}
ns.Config.GetPriceTable = function() return priceTable end

assert(loadfile(lfs_cwd .. "/Core/Util.lua"))("Blackthornes_TS", ns)
assert(loadfile(lfs_cwd .. "/Data/Prices.lua"))("Blackthornes_TS", ns)
assert(loadfile(lfs_cwd .. "/Logic/Cost.lua"))("Blackthornes_TS", ns)
assert(loadfile(lfs_cwd .. "/Logic/Profit.lua"))("Blackthornes_TS", ns)
assert(loadfile(lfs_cwd .. "/Logic/MyAuctions.lua"))("Blackthornes_TS", ns)

local Prices, Profit, MyAuctions = ns.Prices, ns.Profit, ns.MyAuctions

local perDay
Prices.GetUnitsSoldPerDay = function() return perDay end

local demand
ns.Demand = { Get = function() return demand end }

-- The book from the mockup: 9 cheap ones, then 60 at 94s 90c.
local BOOK = { 8200, 2, 8450, 3, 8600, 4, 9490, 60, 9500, 40, 9800, 20 }

local function Copy(list)
    local out = {}
    for i, value in ipairs(list) do out[i] = value end
    return out
end

local function Scan(itemID, ladder, market)
    Prices:Record(itemID, market or 9200, ladder[1], 129, clock, ladder[1], nil, nil, Copy(ladder))
end

local function Reset()
    settings = {
        undercutCopper = 1,
        auctionCut = 0.05,
        minProfit = 0,
        staleAfterSeconds = 48 * 3600,
        overcutting = true,
    }
    commodityStatus = { [SILK] = true, [BAG] = false }
    for key in pairs(priceTable) do priceTable[key] = nil end
    perDay, demand = 40, nil
    clock = 2000000
end

local failures = 0
local function check(label, got, expected)
    local ok = got == expected
    if not ok then failures = failures + 1 end
    print(("  %-58s %-10s %s"):format(label, tostring(got), ok and "ok" or
        ("FAILED, expected " .. tostring(expected))))
end

print("")
print("overcutting off")
Reset()
settings.overcutting = false
Scan(SILK, BOOK)
do
    local price, basis = Profit:ChoosePostPrice(SILK)
    check("1c under the cheapest", price, 8199)
    check("as an undercut", basis, "undercut")
end

print("")
print("overcutting on")
Reset()
Scan(SILK, BOOK)
check("the scan notes when it read the steps", priceTable[SILK].ladderAt, clock)
do
    local price, basis, why = Profit:ChoosePostPrice(SILK)
    check("1c under the big stack", price, 9489)
    check("as an overcut", basis, "overcut")
    check("says how many sell first", why, "9 cheaper ones should sell first, then yours")
    local _, _, wall, count, ahead = Profit:Overcut(SILK, 8200, 1)
    check("the big stack's price", wall, 9490)
    check("how many are there", count, 60)
    check("how many are ahead", ahead, 9)
end

settings.undercutCopper = 0
check("Undercut by 0c matches the big stack", (Profit:ChoosePostPrice(SILK)), 9490)

print("")
print("when it falls back")
Reset()
perDay = 5
Scan(SILK, BOOK)
check("the cheaper ones would not sell in a day", select(2, Profit:ChoosePostPrice(SILK)), "undercut")

Reset()
perDay = nil
Scan(SILK, BOOK)
check("no idea how many sell a day", select(2, Profit:ChoosePostPrice(SILK)), "undercut")

Reset()
demand = { level = "low" }
Scan(SILK, BOOK)
check("it sells slowly", select(2, Profit:ChoosePostPrice(SILK)), "undercut")

Reset()
Scan(SILK, { 8200, 4, 8300, 5, 8400, 6, 8500, 5 })
check("no step is a big stack", select(2, Profit:ChoosePostPrice(SILK)), "undercut")

Reset()
Scan(SILK, { 8200, 60, 9490, 20 })
check("the cheapest step is the big stack", select(2, Profit:ChoosePostPrice(SILK)), "undercut")

Reset()
Scan(SILK, BOOK)
clock = clock + 2 * 3600
check("the steps are two hours old", select(2, Profit:ChoosePostPrice(SILK)), "undercut")

Reset()
Scan(SILK, BOOK, 6000)
check("far over market value", select(2, Profit:ChoosePostPrice(SILK)), "undercut")

Reset()
Scan(BAG, { 82000, 1, 84000, 1, 95000, 10 })
check("gear is priced the usual way", select(2, Profit:ChoosePostPrice(BAG)) ~= "overcut", true)

Reset()
Scan(SILK, BOOK)
Prices:Record(SILK, 9200, 8300, 129, clock, 8300, nil)
check("a browse row with a new cheapest drops the steps", priceTable[SILK].ladder, nil)
check("so it undercuts", select(2, Profit:ChoosePostPrice(SILK)), "undercut")

print("")
print("your auctions")
Reset()
Scan(SILK, BOOK)
check("just under the big stack is not undercut", (MyAuctions:Judge(SILK, 9489)), "overcut")
check("over the big stack still is", (MyAuctions:Judge(SILK, 9600)), "undercut")
settings.overcutting = false
check("with it off, it is undercut as before", (MyAuctions:Judge(SILK, 9489)), "undercut")

time, GetTime, CreateFrame, C_Item = savedTime, savedGetTime, savedCreateFrame, savedItem

print("")
assert(failures == 0, failures .. " overcutting check(s) failed")
print("all overcutting checks passed")
