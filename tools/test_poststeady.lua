-- A steady run of listings keeps going (the wheel, or quick clicks on
-- List Next), from the 2026-11-14 trace: about seven listings went up, then
-- every click said "still confirming the last listing" for three or four
-- seconds, over and over.
--
-- What must hold:
--   1. Twenty different items listed 0.35 seconds apart all go up: no click
--      is refused for listings still being confirmed.
--   2. Reading them back does not wait for the listing to stop: a listing
--      does not hold back the read, and one read settles every listing made
--      before it went out.
--   3. The reads stay few, so the auction house's allowance is not used up.
--   4. Every listing is settled as listed. None is called missing, and none
--      ends in "could not tell".

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
    NewTicker = function(every, fn)
        local ticker = { cancelled = false }
        function ticker:Cancel() self.cancelled = true end
        local function Tick()
            if ticker.cancelled then return end
            fn()
            if not ticker.cancelled then timers[#timers + 1] = { at = clock + every, fn = Tick } end
        end
        timers[#timers + 1] = { at = clock + every, fn = Tick }
        return ticker
    end,
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
    -- The auction house shows a listing as soon as it is sent.
    PostItem = function(location)
        sent[#sent + 1] = location
        local entry = bags[location.bag] and bags[location.bag][location.slot]
        if entry then listed[#listed + 1] = { itemID = entry.itemID } end
    end,
    GetNumOwnedAuctions = function() return #listed end,
    GetOwnedAuctionInfo = function(index)
        local entry = listed[index]
        if not entry then return nil end
        return { itemKey = { itemID = entry.itemID }, quantity = 1, status = 0 }
    end,
    QueryOwnedAuctions = function() queries = queries + 1 end,
}


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


assert(loadfile(lfs_cwd .. "/Core/Util.lua"))("Blackthornes_TS", ns)
ns.Util.HasFunction = function(path)
    return path == "C_AuctionHouse.GetNumOwnedAuctions"
        or path == "C_AuctionHouse.GetOwnedAuctionInfo"
        or path == "C_AuctionHouse.QueryOwnedAuctions"
end
ns.Util.GetItemLabel = function(i) return "item" .. tostring(i) end
ns.Util.FormatMoney = function(c) return tostring(c) end

-- The real request queue, so its spacing and allowance are the ones played.
assert(loadfile(lfs_cwd .. "/Core/AHQueue.lua"))("Blackthornes_TS", ns)
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

-- Twenty different items, one of each.
local ITEMS = 20
bags = { [0] = {} }
for id = 1, ITEMS do
    maxStacks[1000 + id] = 1
    table.insert(bags[0], { itemID = 1000 + id, stackCount = 1 })
end
Auctions:ReadOwned()

print("")
print("twenty items listed 0.35 seconds apart")

local went, refused, why = 0, 0, nil
for turn = 1, ITEMS do
    local id = 1000 + turn
    local allowed, reason = Posting:CanPost(id)
    if allowed and Posting:Post(id, 1, 1000) then
        went = went + 1
    else
        refused = refused + 1
        why = why or reason
    end
    RunUntil(clock + 0.35)
end

check("every turn listed one", went, ITEMS)
check("none was refused", refused, 0)
check("no reason given", why, nil)
check("a read went out while the listing went on", queries >= 1, true)

RunUntil(clock + 40)
check("every listing settled", #Posting:AllPending(), 0)
check("none called missing", Said("did not appear"), false)
check("none ended in could not tell", Said("could not tell"), false)
local listedSaid = 0
for _, text in ipairs(said) do
    if tostring(text):find("^listed item") then listedSaid = listedSaid + 1 end
end
check("each was reported listed", listedSaid, ITEMS)
check("with only a few reads", queries <= 6, true)

print("")
print("a pile far past that still waits")

for id = 1, Posting.MAX_CONFIRMING do
    Posting.others = Posting.others or {}
    Posting.others[5000 + id] = { itemID = 5000 + id, startedAt = clock }
end
local allowed, reason = Posting:CanPost(1)
check("the cap still holds", allowed, false)
check("and says why", reason, "still confirming the last listing")

Posting.pending, Posting.others = nil, nil
C_AuctionHouse, C_Timer, C_Item, C_Container, ItemLocation, maxStacks = nil, nil, nil, nil, nil, nil

print("")
if failures > 0 then
    error(("FAIL -- %d check(s) failed"):format(failures))
end

print("PASS -- a steady run of listings keeps going and every one is confirmed")
