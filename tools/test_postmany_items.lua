-- Different items listed back to back, each confirmed on its own.
--
-- Asked 2026-10-13: "Do we still need the 5 second wait between listings?"
-- Each listing used to be read back from the auction house before any other
-- item could go up, about five seconds a listing. The auction house itself
-- only asks for about a second between requests, so now a different item
-- goes up after that spacing, up to Posting.MAX_CONFIRMING items being
-- confirmed at once, and one reading of your auctions settles all of them.
--
-- What must hold:
--   1. A second item can be listed while the first is still being checked.
--   2. One reading settles both, each by its own item ID, and listings
--      made close together share that reading.
--   3. A reading from a query sent before a listing existed never settles it
--      (it would report the new listing as missing).
--   4. The cap holds, and a post keeps the auction house's request spacing.

local ns = {}
ns.COLORS = setmetatable({}, {__index = function() return "ffffffff" end})
ns.NewModule = function(name) local m = {}; ns[name] = m; return m end
ns.RegisterCommand = function() end
ns.RegisterEvent = function() return false end
local said = {}
ns.Print = function(text) said[#said + 1] = text end
ns.Warn = ns.Print
ns.PrintRaw, ns.Debug = function() end, function() end

--------------------------------------------------------------------------------
-- A clock and timers
--------------------------------------------------------------------------------

local clock = 100
GetTime = function() return clock end
time = time or os.time

local timers = {}
C_Timer = {
    After = function(delay, fn) timers[#timers + 1] = { at = clock + delay, fn = fn } end,
    NewTicker = function() return { Cancel = function() end } end,
}

--- Run every timer due up to `target`, in the order they come due.
local function RunUntil(target)
    while true do
        local nextIndex, nextAt
        for i = 1, #timers do
            local timer = timers[i]
            if timer and timer.at <= target and (not nextAt or timer.at < nextAt) then
                nextIndex, nextAt = i, timer.at
            end
        end
        if not nextIndex then break end
        local timer = timers[nextIndex]
        timers[nextIndex] = false
        clock = timer.at
        timer.fn()
    end
    clock = target
end

--------------------------------------------------------------------------------
-- A player with bags, and an auction house that shows what it was sent only
-- once we say so
--------------------------------------------------------------------------------

local bags = {}
maxStacks = {}

C_Item = {
    GetItemInfo = function(itemID)
        return "item", nil, 2, 1, 1, "Consumable", "", maxStacks[itemID] or 20
    end,
}

C_Container = {
    GetContainerItemLink = function() return nil end,
    GetContainerNumSlots = function(bag) return bags[bag] and #bags[bag] or 0 end,
    GetContainerItemInfo = function(bag, slot)
        local entry = bags[bag] and bags[bag][slot]
        if not entry then return nil end
        return { itemID = entry.itemID, stackCount = entry.stackCount, isLocked = false }
    end,
}

ItemLocation = {
    CreateFromBagAndSlot = function(_, bag, slot)
        return { bag = bag, slot = slot, IsValid = function() return true end }
    end,
}

CreateFrame = function()
    local frame = {}
    for _, name in ipairs({ "SetScript", "Show", "Hide", "SetPoint", "SetSize" }) do
        frame[name] = function() end
    end
    return frame
end

-- What the auction house has been sent, and what it shows when read.
local sent, listed, queries = {}, {}, 0
C_AuctionHouse = {
    PostItem = function(location) sent[#sent + 1] = location end,
    GetNumOwnedAuctions = function() return #listed end,
    GetOwnedAuctionInfo = function(index)
        local entry = listed[index]
        if not entry then return nil end
        return { itemKey = { itemID = entry.itemID }, quantity = 1, status = 0 }
    end,
    QueryOwnedAuctions = function() queries = queries + 1 end,
}

local function Show(itemID) listed[#listed + 1] = { itemID = itemID } end

ns.db = {}
ns.Config = {
    Get = function(_, k)
        if k == "undercutCopper" then return 1 end
        if k == "staleAfterSeconds" then return 48 * 3600 end
        if k == "postDuration" then return 2 end
        return nil
    end,
    GetPriceTable = function() return {} end,
    GetRealmKey = function() return "TestRealm" end,
}
ns.Scanner = { isAuctionHouseOpen = true, isScanning = false, IsCommodity = function() return false end }
ns.Prices = { GetValue = function() return 1000 end }
ns.Inventory = {
    GetCarriedBags = function() return { 0 } end,
    GetBagCount = function(_, itemID)
        local total = 0
        for _, entry in ipairs(bags[0] or {}) do
            if entry.itemID == itemID then total = total + entry.stackCount end
        end
        return total
    end,
    GetOwnedCount = function() return 0 end,
}
ns.Recipes = { GetAccountWide = function() return {} end, GetAny = function() return nil end }
ns.Queue = { GetShoppingList = function() return {} end, GetAll = function() return {} end }
ns.Cost = { FindRecipeForItem = function() return nil end }
ns.Cost.FindAnyRecipeForItem = ns.Cost.FindRecipeForItem

-- The request queue: sends at once, and remembers when a post went out.
local noted = 0
ns.AHQueue = {
    PRIORITY = { urgent = 10, normal = 50, scan = 90 },
    MIN_SPACING = 1.2,
    SecondsUntilReady = function() return 0, nil end,
    Yield = function() end,
    NoteSend = function() noted = noted + 1 end,
}

assert(loadfile(lfs_cwd .. "/Core/Util.lua"))("Blackthornes_TS", ns)
ns.Util.HasFunction = function(path)
    return path == "C_AuctionHouse.GetNumOwnedAuctions"
        or path == "C_AuctionHouse.GetOwnedAuctionInfo"
        or path == "C_AuctionHouse.QueryOwnedAuctions"
end
-- The queue may hold a request back; then the reads of the last query run on
-- while the new one waits.
local sendDelay = 0
ns.Util.WhenAuctionReady = function(action)
    if sendDelay > 0 then C_Timer.After(sendDelay, action) else action() end
end
ns.Util.GetItemLabel = function(i) return "item" .. tostring(i) end
ns.Util.FormatMoney = function(c) return tostring(c) end

assert(loadfile(lfs_cwd .. "/Logic/Profit.lua"))("Blackthornes_TS", ns)
assert(loadfile(lfs_cwd .. "/Logic/Posting.lua"))("Blackthornes_TS", ns)
assert(loadfile(lfs_cwd .. "/Data/Auctions.lua"))("Blackthornes_TS", ns)

local Posting, Auctions = ns.Posting, ns.Auctions

local failures = 0

local function check(label, got, expected)
    local ok = got == expected
    if not ok then failures = failures + 1 end
    print(("  %-58s %-8s %s"):format(label, tostring(got), ok and "ok" or
        ("FAILED, expected " .. tostring(expected))))
end

local function Said(pattern)
    for _, text in ipairs(said) do
        if tostring(text):find(pattern) then return true end
    end
    return false
end

local OIL, POTION, CLOTH, ORE, HERB, GEM, BOLT, VIAL = 20748, 929, 2589, 2770, 765, 774, 2996, 3371

local function Reset()
    clock, timers, listed, sent, said, queries, noted = 100, {}, {}, {}, {}, 0, 0
    sendDelay = 0
    Posting.pending, Posting.others = nil, nil
    Posting.manyRefused = {}
    Auctions.confirmToken, Auctions.lastRefresh = 0, nil
    ns.db.postedAuctions = nil
    bags = { [0] = {} }
    for _, id in ipairs({ OIL, POTION, CLOTH, ORE, HERB, GEM, BOLT, VIAL }) do
        maxStacks[id] = 1
        table.insert(bags[0], { itemID = id, stackCount = 1 })
    end
    -- The first reading this visit, so new listings can be told from old.
    Auctions:ReadOwned()
end

print("")
print("two items listed a second apart")

Reset()
check("the oil is listed", Posting:Post(OIL, 1, 30000), true)
check("the post kept the request spacing", noted, 1)
RunUntil(101.2)
check("a potion need not wait for the oil's check", (Posting:CanPost(POTION)), true)
check("the potion is listed", Posting:Post(POTION, 1, 1000), true)
check("both went to the auction house", #sent, 2)
check("both are being confirmed", #Posting:AllPending(), 2)

-- The auction house shows both.
Show(OIL)
Show(POTION)

-- The potion's check is due 1.2 seconds after the oil's, so the oil's
-- waits for it and one reading settles both (fast listing, 2026-10-14).
RunUntil(103.5)
check("the oil's check waits for the potion's", queries, 0)
RunUntil(110)
check("one reading went out for both", queries, 1)
check("the oil settled from it", Posting:PendingFor(OIL), nil)
check("and the potion", Posting:PendingFor(POTION), nil)
check("nothing left waiting", #Posting:AllPending(), 0)
check("the oil was reported listed", Said("^listed item" .. OIL), true)
check("the potion was reported listed", Said("^listed item" .. POTION), true)
check("nothing reported missing", Said("did not appear"), false)

print("")
print("a reading from before a listing never settles it")

Reset()
Posting:Post(OIL, 1, 30000)
Show(OIL)
RunUntil(103.0)
check("the oil's check went out", queries, 1)

-- The potion goes up while the oil's reads are still running, and does not
-- show yet. Its own check is the only one that may call it missing.
RunUntil(103.4)
Posting:Post(POTION, 1, 1000)
local potion = Posting:PendingFor(POTION)
RunUntil(106.4)
check("the potion's check is out", potion.verifying, true)
check("the oil's old reads did not settle the potion", Posting:IsPending(potion), true)
check("nor call it missing", Said("did not appear"), false)

Show(POTION)
RunUntil(115)
check("the potion settled once it showed", Posting:IsPending(potion), false)
check("reported listed", Said("^listed item" .. POTION), true)
check("still nothing reported missing", Said("did not appear"), false)

print("")
print("a check held back by the queue while older reads run on")

Reset()
Posting:Post(OIL, 1, 30000)
Show(OIL)
RunUntil(103.2)
Posting:Post(POTION, 1, 1000)
potion = Posting:PendingFor(POTION)

-- The potion's own query waits two seconds in the queue; the oil's reads go
-- on meanwhile, and the potion is not showing yet.
sendDelay = 2
RunUntil(106.3)
check("the potion is waiting for its own query", potion.awaiting, true)
RunUntil(108.0)
check("the oil's last read did not call the potion missing", Said("did not appear"), false)
check("the potion is still being confirmed", Posting:IsPending(potion), true)

Show(POTION)
RunUntil(120)
check("its own query settled it as listed", Said("^listed item" .. POTION), true)
check("nothing reported missing", Said("did not appear"), false)

print("")
print("one that genuinely did not go up")

Reset()
Posting:Post(OIL, 1, 30000)
Posting:Post(POTION, 1, 1000)
Show(POTION)
RunUntil(120)
check("the potion is reported listed", Said("^listed item" .. POTION), true)
check("the oil is reported missing", Said("^item" .. OIL .. " did not appear"), true)
check("and only the oil", Said("^item" .. POTION .. " did not appear"), false)

print("")
print("how many may be confirmed at once")

Reset()
local FIRST = { OIL, POTION, CLOTH, ORE, GEM, BOLT }
for _, id in ipairs(FIRST) do Posting:Post(id, 1, 1000) end
check("six items are being confirmed", #Posting:AllPending(), Posting.MAX_CONFIRMING)
check("a seventh waits", (Posting:CanPost(HERB)), false)
check("another oil still joins its check", (Posting:CanPost(OIL)), true)
for _, id in ipairs(FIRST) do Show(id) end
RunUntil(120)
check("all six settled", #Posting:AllPending(), 0)
check("so the seventh may go", (Posting:CanPost(HERB)), true)

Posting.pending, Posting.others = nil, nil
C_AuctionHouse, C_Timer, C_Item, C_Container, ItemLocation, maxStacks = nil, nil, nil, nil, nil, nil

print("")
if failures > 0 then
    print(("FAIL -- %d check(s) failed"):format(failures))
    os.exit(1)
end

print("PASS -- different items go up a second apart and are confirmed on their own")
