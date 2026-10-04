-- Copies of one item, listed back to back.
--
-- Trent, 2026-10-04: "if i have multiples of the same crafted item, the addon
-- should allow me to post all of them rapidly, but have it post them one at a
-- time, just like the Blizzard AH UI does ... right now i have to wait 5
-- seconds between each". Each listing used to be confirmed against the server
-- before the next could start. Another copy of the same item now joins the
-- listing being confirmed, and one check a few seconds after the last click
-- counts them all. A different item still waits, because its listing could
-- not be told apart from the first.

local ns = {}
ns.COLORS = setmetatable({}, {__index = function() return "ffffffff" end})
ns.NewModule = function(name) local m = {}; ns[name] = m; return m end
ns.RegisterCommand = function() end
ns.RegisterEvent = function() end
local said = {}
ns.Print = function(text) said[#said + 1] = text end
ns.Warn = ns.Print
ns.PrintRaw, ns.Debug = function() end, function() end

--------------------------------------------------------------------------------
-- A player with bags
--------------------------------------------------------------------------------

-- bags[bag][slot] = { itemID, stackCount }
local bags = {}
local commodities = {}
local prices = {}

maxStacks = {}
C_Item = {
    GetItemInfo = function(itemID)
        return "item", nil, 2, 1, 1, "Consumable", "", maxStacks[itemID] or 20
    end,
}

C_Container = {
    GetContainerItemLink = function(bag, slot)
        local entry = bags[bag] and bags[bag][slot]
        return entry and entry.link or nil
    end,
    GetContainerNumSlots = function(bag) return bags[bag] and #bags[bag] or 0 end,
    GetContainerItemInfo = function(bag, slot)
        local entry = bags[bag] and bags[bag][slot]
        if not entry then return nil end
        return { itemID = entry.itemID, stackCount = entry.stackCount, isLocked = false, hyperlink = entry.link }
    end,
}

-- MakeLocation only needs something that answers IsValid.
ItemLocation = {
    CreateFromBagAndSlot = function(_, bag, slot)
        return { bag = bag, slot = slot, IsValid = function() return true end }
    end,
}

ns.Util = {
    Clamp = function(v, l, h) return math.max(l, math.min(h, v)) end,
    Count = function(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end,
    FormatMoney = function(c) return tostring(c) end,
    FormatAge = function() return "" end,
    GetItemLabel = function(i) return "item" .. tostring(i) end,
    -- Nothing from C_AuctionHouse: the postable count then comes from the bags
    -- and the deposit is unknown, which is the away-from-the-auction-house case
    -- and the one that keeps this test about quantities.
    HasFunction = function() return false end,
}

-- Core/Util.lua builds a worker frame at load time. Nothing here drives it.
CreateFrame = function()
    local frame = {}
    for _, name in ipairs({ "SetScript", "Show", "Hide", "SetPoint", "SetSize" }) do
        frame[name] = function() end
    end
    return frame
end

local clock = 100
GetTime = function() return clock end
time = time or os.time

ns.db = {}
ns.Config = {
    Get = function(_, k)
        if k == "undercutCopper" then return 1 end
        if k == "staleAfterSeconds" then return 48 * 3600 end
        if k == "postDuration" then return 2 end
        return nil
    end,
    GetPriceTable = function() return {} end,
}

ns.Scanner = {
    isAuctionHouseOpen = true,
    isScanning = false,
    IsCommodity = function(_, itemID) return commodities[itemID] == true end,
}

ns.Prices = {
    GetValue = function(_, itemID, key)
        local entry = prices[itemID]
        return entry and entry[key] or nil
    end,
}

ns.Inventory = {
    -- The containers the character carries, reagent bag last. Posting walks
    -- whatever this returns rather than keeping a range of its own, which is
    -- how a reagent bag came to be invisible to the sell list.
    GetCarriedBags = function() return { 0, 1, 2, 3, 4, 5 } end,

    GetBagCount = function(_, itemID)
        local total = 0
        for _, slots in pairs(bags) do
            for _, entry in ipairs(slots) do
                if entry.itemID == itemID then total = total + entry.stackCount end
            end
        end
        return total
    end,
}

ns.Recipes = { GetAccountWide = function() return {} end }
ns.Queue = { GetShoppingList = function() return {} end }

-- Nothing here is craftable, so the profit side stays out of the way and the
-- prices are whatever the price table says.
ns.Cost = { FindRecipeForItem = function() return nil end }
ns.Cost.FindAnyRecipeForItem = ns.Cost.FindRecipeForItem

-- The auction house: what was sent, what a refusal looks like, and the
-- owned-auction reading the check is measured against.
local sent, refuse = {}, false
C_AuctionHouse = {
    PostItem = function(location, duration, quantity)
        if refuse then error("item not found") end
        sent[#sent + 1] = quantity
    end,
}

local timers = {}
C_Timer = {
    After = function(seconds, fn) timers[#timers + 1] = { at = clock + seconds, fn = fn } end,
    NewTicker = function() return { Cancel = function() end } end,
}

--- Move the clock on, running the timers that come due.
local function Advance(seconds)
    clock = clock + seconds
    local due = {}
    for i = #timers, 1, -1 do
        if timers[i].at <= clock then
            table.insert(due, 1, timers[i])
            table.remove(timers, i)
        end
    end
    table.sort(due, function(a, b) return a.at < b.at end)
    for _, timer in ipairs(due) do timer.fn() end
end

local owned, refreshes = 0, 0
ns.Auctions = {
    confirmToken = 0,
    GetOwnPostedCount = function() return owned end,
    GetOwnedIDs = function() return {} end,
    Refresh = function() refreshes = refreshes + 1 end,
}

ns.AHQueue = {
    PRIORITY = { urgent = 10 },
    MIN_SPACING = 1.2,
    SecondsUntilReady = function() return 0, nil end,
    Yield = function() end,
}

assert(loadfile(lfs_cwd .. "/Core/Util.lua"))("Blackthornes_TS", ns)
assert(loadfile(lfs_cwd .. "/Logic/Profit.lua"))("Blackthornes_TS", ns)
assert(loadfile(lfs_cwd .. "/Logic/Posting.lua"))("Blackthornes_TS", ns)

local Posting = ns.Posting

local failures = 0

local function check(label, got, expected)
    local ok = got == expected
    if not ok then failures = failures + 1 end
    print(("  %-56s %-8s %s"):format(label, tostring(got), ok and "ok" or
        ("FAILED, expected " .. tostring(expected))))
end

local function Said(pattern)
    for _, text in ipairs(said) do
        if tostring(text):find(pattern) then return true end
    end
    return false
end

local OIL, POTION = 20748, 929

local function Reset()
    Posting.pending = nil
    Posting.manyRefused = true
    maxStacks = { [OIL] = 1, [POTION] = 5 }
    prices = { [OIL] = { market = 30000 }, [POTION] = { market = 1000 } }
    bags = {
        [0] = {
            { itemID = OIL, stackCount = 1 },
            { itemID = OIL, stackCount = 1 },
            { itemID = OIL, stackCount = 1 },
            { itemID = POTION, stackCount = 5 },
        },
    }
    sent, refuse, timers, said = {}, false, {}, {}
    owned, refreshes = 4, 0
    ns.Auctions.confirmToken = 0
end

print("")
print("a second copy goes up without waiting for the first")

Reset()
check("the first oil is listed", Posting:Post(OIL, 1, 30000), true)
check("another oil may follow straight away", (Posting:CanPost(OIL)), true)
check("with nothing to count down", (Posting:SecondsUntilPostable(OIL)), 0)
check("a different item still waits for the check", (Posting:CanPost(POTION)), false)
check("and so does a button that names no item", (Posting:CanPost()), false)
check("the different item counts the wait down", Posting:SecondsUntilPostable(POTION) > 0, true)

Advance(1)
check("the second oil is listed a second later", Posting:Post(OIL, 1, 30000), true)
check("both went to the auction house", #sent, 2)
check("one check for both", Posting.pending.quantity, 2)
check("measured from before the first", Posting.pending.postedBefore, 4)
check("a different item is still refused at the last step", Posting:Post(POTION, 1, 1000), false)

Advance(2.1)
check("the first oil's timer does not check early", Posting.pending.verifying, nil)
check("so nothing is asked yet", refreshes, 0)

Advance(1)
check("the second oil's timer checks both", Posting.pending.verifying, true)
check("with one reading", refreshes, 1)

print("")
print("a copy listed while the check is out")

Advance(0.5)
check("a third oil while the check is out", Posting:Post(OIL, 1, 30000), true)
check("the reading already out is dropped", ns.Auctions.confirmToken, 2)
check("and a fresh check waits for the third", Posting.pending.verifying, nil)
check("all three counted", Posting.pending.quantity, 3)

Advance(3)
check("checked again after the third", refreshes, 2)
Posting:ResolvePending(7, true)
check("all three reported together", Said("^listed 3 x "), true)
check("nothing reported missing", Said("did not appear"), false)
check("the next click may list again", (Posting:CanPost(POTION)), true)

print("")
print("when the auction house takes fewer")

Reset()
Posting:Post(OIL, 1, 30000)
Posting:Post(OIL, 1, 30000)
Posting:ResolvePending(5, true)
check("one of two is said plainly", Said("^listed 1 of 2 x "), true)

Reset()
Posting.manyRefused = false
Posting.pending = { itemID = OIL, quantity = 3, many = true, joined = true,
    postedBefore = 0, idsBefore = {}, startedAt = clock }
Posting:ResolvePending(2, true)
check("copies listed one by one never turn off listing together", Posting.manyRefused, false)

print("")
print("when the game refuses the second copy")

Reset()
Posting:Post(OIL, 1, 30000)
local first = Posting.pending
refuse = true
check("the second is refused", Posting:Post(OIL, 1, 30000), false)
check("the first is still checked", Posting.pending, first)
check("on its own", Posting.pending.quantity, 1)

Posting.pending = nil
C_AuctionHouse, C_Timer, C_Item, C_Container, ItemLocation, maxStacks = nil, nil, nil, nil, nil, nil

print("")
if failures > 0 then
    print(("FAIL -- %d check(s) failed"):format(failures))
    os.exit(1)
end

print("PASS -- copies of one item go up back to back and are checked together")
