-- A quick scan of a big auction house read slowly.
--
-- The game hands the whole snapshot over fast, but reading it took minutes
-- on a busy realm. For every row of an item nobody had said was a commodity,
-- the read walked every bag slot looking for one to ask about, and did it
-- again each time its short "not held" note ran out. Every row also asked
-- again whose listing it was, and asked the game for the stack size of
-- items it had not cached yet.
--
-- The read now looks in the bags once, asks each item and each seller once,
-- and prices come out the same.

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
local FIRST_ITEM = 20000     -- items nobody holds or has searched
local ITEMS = 400
local ROWS_EACH = 5
local SLOTS = 16

-- Only the first half of the items is cached by the client.
local itemInfoAsks = 0
C_Item = {
    GetItemInfo = function(itemID)
        itemInfoAsks = itemInfoAsks + 1
        if itemID == HELD_CLOTH then return "Silk", "link", 1, 1, 1, "Trade Goods", "Cloth", 20 end
        if itemID < FIRST_ITEM + ITEMS / 2 then return "x", "link", 1, 1, 1, "Trade Goods", "x", 20 end
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

-- Rows: every item listed ROWS_EACH times, mixed through the snapshot the
-- way a real one is, two at a time by three sellers; the silk listed by you and a rival.
local rows = {}
for r = 1, ROWS_EACH do
    for i = 0, ITEMS - 1 do
        local seller = ({ "Ann", "Bob", "Cat" })[(i + r) % 3 + 1]
        rows[#rows + 1] = { 2, 2 * (1000 + i), FIRST_ITEM + i, seller, seller .. "-TestRealm" }
    end
end
rows[#rows + 1] = { 40, 4000, HELD_CLOTH, "Me", "Me-TestRealm" }      -- 1s each, yours
rows[#rows + 1] = { 40, 6000, HELD_CLOTH, "Rival", "Rival-TestRealm" } -- 1s 50c each

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

local ownerAsks = 0
local IsOwnAuction = Scanner.IsOwnAuction
Scanner.IsOwnAuction = function(...)
    ownerAsks = ownerAsks + 1
    return IsOwnAuction(...)
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

print("")
print("a big quick scan reads each thing once")
-- Once to see what's held, once more to find the silk to ask the game about.
check(("the bags are looked through twice, not per row (%d slot reads)"):format(slotReads),
    slotReads <= 2 * 4 * SLOTS)
-- Ann, Bob, Cat, you and the rival.
check(("each seller is asked about once (%d asks)"):format(ownerAsks), ownerAsks <= 5)
check(("each item's stack size is asked once at most (%d asks)"):format(itemInfoAsks),
    itemInfoAsks <= ITEMS + 1)

print("")
print("and prices come out the same")
local silk = Prices:Get(HELD_CLOTH)
check("the silk in the bags is read as a commodity", ns.db.commodity[HELD_CLOTH] == true)
check("so it's priced at 1s each", silk ~= nil and silk.min == 100)
check("your own listing is told apart from the rival's", silk ~= nil and silk.ownMin == 100
    and silk.rivalMin == 150)
local first = Prices:Get(FIRST_ITEM)
check("an item nobody holds is priced from its rows", first ~= nil and first.min == 1000)
check("and is not taken for a commodity", ns.db.commodity[FIRST_ITEM] == nil)
local last = Prices:Get(FIRST_ITEM + ITEMS - 1)
check("an item the client hasn't cached is priced too", last ~= nil and last.min == 1000 + ITEMS - 1)

for _, key in ipairs(GLOBALS) do _G[key] = saved[key] end

print("")
print(("%d passed, %d failed"):format(passed, failed))
assert(failed == 0, "quick scan speed checks failed")
