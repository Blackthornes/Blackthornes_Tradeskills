-- The game stuttered for a few seconds while a quick scan was read.
--
-- Every row asked the client for its item's stack size, even a row of one.
-- Most gear is listed one at a time, and the client hadn't cached most of
-- it, so a scan sent it off for thousands of items. Their answers came back
-- over the next seconds as a flood of item data events, and the game hitched.
--
-- A row of one never needs a stack size: its price is its buyout. Only rows
-- of more than one ask now, and prices come out the same.

local GLOBALS = { "CreateFrame", "GetTime", "time", "C_Timer", "C_Item", "C_AuctionHouse",
    "C_Container", "ItemLocation", "UnitName", "GetRealmName" }
local saved = {}
for _, key in ipairs(GLOBALS) do saved[key] = _G[key] end

local function noop() end

local function Blank()
    return setmetatable({}, { __index = function(_, k)
        if type(k) == "string" and k:match("^%u") then return noop end
    end })
end

-- The clock moves on with every row read, as it does over a long read.
local clock = 1000
CreateFrame = function() return Blank() end
GetTime = function() return clock end
time = function() return 100000 end
C_Timer = {
    After = noop,
    NewTimer = function() return { Cancel = noop } end,
    NewTicker = function() return { Cancel = noop } end,
}
UnitName = function() return "Me" end
GetRealmName = function() return "Test Realm" end

local HELD_CLOTH = 4306      -- in the bags, and the game says it's a commodity
local FIRST_ITEM = 20000     -- gear nobody holds or has searched
local STACKED = 30000        -- a reagent listed as stacks, not yet known as a commodity
local ITEMS = 400
local SLOTS = 16

-- The client has cached none of the items. Asking about one sends it off
-- to the server, and its answer comes back later as an item data event.
local itemInfoAsks = 0
local asked = {}
C_Item = {
    GetItemInfo = function(itemID)
        itemInfoAsks = itemInfoAsks + 1
        if itemID == HELD_CLOTH then return "Silk", "link", 1, 1, 1, "Trade Goods", "Cloth", 20 end
        asked[itemID] = true
        return nil
    end,
}

-- Four bags of sixteen slots; the silk sits in the last slot of the last bag.
local slotReads = 0
C_Container = {
    GetContainerNumSlots = function() return SLOTS end,
    GetContainerItemInfo = function(bag, slot)
        slotReads = slotReads + 1
        if bag == 3 and slot == SLOTS then return { itemID = HELD_CLOTH, stackCount = 5 } end
        return nil
    end,
}
ItemLocation = {
    CreateFromBagAndSlot = function(_, bag, slot)
        return { bag = bag, slot = slot, IsValid = function() return true end }
    end,
}

-- Rows: every piece of gear listed twice, one at a time, by two sellers,
-- and a reagent in stacks of 5 (2s each).
local rows = {}
for r = 1, 2 do
    for i = 0, ITEMS - 1 do
        local seller = ({ "Ann", "Bob" })[r]
        rows[#rows + 1] = { 1, 1000 * r + i, FIRST_ITEM + i, seller, seller .. "-TestRealm" }
    end
end
rows[#rows + 1] = { 5, 1000, STACKED, "Cat", "Cat-TestRealm" }

C_AuctionHouse = {
    GetItemCommodityStatus = function(location)
        return (location and location.bag == 3) and 2 or 1
    end,
    GetReplicateItemInfo = function(index)
        clock = clock + 0.05
        local row = rows[index + 1]
        if not row then return nil end
        return "x", 0, row[1], 1, true, 1, "", 0, 0, row[2], 0, false, nil,
            row[4], row[5], 0, row[3], true
    end,
}

local ns = {}
ns.COLORS = setmetatable({}, { __index = function() return "ffffffff" end })
ns.NewModule = function(name) local m = {}; ns[name] = m; return m end
ns.RegisterCommand = noop
ns.RegisterEvent = function() return true end
ns.Print, ns.PrintRaw, ns.Debug, ns.Warn = noop, noop, noop, noop
ns.Inventory = { GetCarriedBags = function() return { 0, 1, 2, 3 } end }

local priceTable = {}
ns.db = { commodity = {} }
ns.Config = {
    Get = function() return nil end,
    GetRealmKey = function() return "TestRealm-Alliance" end,
    GetPriceTable = function() return priceTable end,
}

assert(loadfile(lfs_cwd .. "/Core/Util.lua"))("Blackthornes_TS", ns)
assert(loadfile(lfs_cwd .. "/Data/Prices.lua"))("Blackthornes_TS", ns)
assert(loadfile(lfs_cwd .. "/Data/Scanner.lua"))("Blackthornes_TS", ns)

local Prices, Scanner = ns.Prices, ns.Scanner

ns.Util.NewWorker = function(opts)
    return { Start = function(_, items)
        for _, item in ipairs(items) do opts.onItem(item) end
        if opts.onDone then opts.onDone() end
    end }
end

local passed, failed = 0, 0
local function check(label, condition)
    if condition then
        passed = passed + 1
        print(("  ok    %s"):format(label))
    else
        failed = failed + 1
        print(("  FAIL  %s"):format(label))
    end
end

Scanner.isScanning = true
Scanner.scanStartedWall = time()
Scanner:ReadReplicateResults(#rows)

local gearAsked = 0
for i = 0, ITEMS - 1 do
    if asked[FIRST_ITEM + i] then gearAsked = gearAsked + 1 end
end

print("")
print("a quick scan of gear listed one at a time")
check(("sends the client off for no gear (%d of %d asked about)"):format(gearAsked, ITEMS), gearAsked == 0)
check("still asks about the reagent listed in stacks", asked[STACKED] == true)
check(("asks the client about one item in all (%d asks)"):format(itemInfoAsks), itemInfoAsks == 1)

print("")
print("and prices come out the same")
local first = Prices:Get(FIRST_ITEM)
check("gear is priced at its cheapest buyout", first ~= nil and first.min == 1000)
local last = Prices:Get(FIRST_ITEM + ITEMS - 1)
check("the last piece too", last ~= nil and last.min == 1000 + ITEMS - 1)
local stacked = Prices:Get(STACKED)
check("the reagent is priced at 2s each", stacked ~= nil and stacked.min == 200)

for _, key in ipairs(GLOBALS) do _G[key] = saved[key] end

print("")
print(("%d passed, %d failed"):format(passed, failed))
assert(failed == 0, "quick scan stutter checks failed")
