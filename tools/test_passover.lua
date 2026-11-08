-- A stack whose listing is refused, or skipped in the box, is passed over
-- for the rest of the visit, so List Next and the mouse wheel move on.
--
-- The owner's report (2026-11-08): wheel up "still breaks and stops
-- working". The stack on top of the Sell list was refused at the price the
-- check found (or asked about, far under its usual price), and it stayed on
-- top: every click and every wheel turn hit it again and nothing after it
-- was ever listed.
--
-- What must hold:
--   1. A refused stack (under the floor, under its cost) is no longer next;
--      the stack after it is.
--   2. Skip in the box passes it over too; the game replacing the box with
--      the next one ("override") does not.
--   3. It no longer counts toward List all.
--   4. Setting its price by hand, or leaving the auction house, gives it
--      another go.
--   5. Nothing transient passes over: a busy auction house, a throttle or a
--      full queue of listings leaves the stack where it is.


local GLOBALS = { "CreateFrame", "C_Container", "ItemLocation", "GetTime", "time", "C_Timer",
    "StaticPopupDialogs", "StaticPopup_Show", "StaticPopup_Hide", "StaticPopup_Visible",
    "C_AuctionHouse" }
local saved = {}
for _, key in ipairs(GLOBALS) do saved[key] = _G[key] end

local function noop() end

local function Blank()
    return setmetatable({}, { __index = function(_, k)
        if type(k) == "string" and k:match("^%u") then return noop end
    end })
end

local clock = 1000
CreateFrame = function() return Blank() end
GetTime = function() return clock end
time = function() return 100000 end

local timers = {}
C_Timer = {
    After = function(seconds, fn) timers[#timers + 1] = { seconds = seconds, fn = fn } end,
    NewTicker = function() return { Cancel = noop } end,
    NewTimer = function() return { Cancel = noop } end,
}

local POTION, OIL, RING, CLOAK = 929, 20748, 1500, 1501

local bags
local function FillBags()
    bags = { [0] = {
        { itemID = POTION, stackCount = 5 },
        { itemID = OIL, stackCount = 3 },
        { itemID = RING, stackCount = 1 },
        { itemID = CLOAK, stackCount = 1 },
    } }
end
FillBags()

C_Container = {
    GetContainerNumSlots = function(bag) return bags[bag] and #bags[bag] or 0 end,
    GetContainerItemInfo = function(bag, slot)
        local e = bags[bag] and bags[bag][slot]
        if e then return { itemID = e.itemID, stackCount = e.stackCount, isLocked = e.locked == true } end
    end,
    GetContainerItemLink = function() return nil end,
}
ItemLocation = { CreateFromBagAndSlot = function() return { IsValid = function() return true end } end }

local popup
StaticPopupDialogs = {}
StaticPopup_Show = function(which, text, _, data)
    popup = Blank()
    popup.which, popup.text, popup.data = which, text, data
    return popup
end
StaticPopup_Visible = function(which) return popup and popup.which == which and popup or nil end
StaticPopup_Hide = function(which) if popup and popup.which == which then popup = nil end end

local said = {}
local ns = {}
ns.COLORS = setmetatable({}, { __index = function() return "ffffffff" end })
ns.NewModule = function(name) local m = {}; ns[name] = m; return m end
ns.RegisterCommand = noop

local handlers = {}
ns.RegisterEvent = function(_, event, fn)
    handlers[event] = handlers[event] or {}
    table.insert(handlers[event], fn)
    return true
end
local function Fire(event, ...)
    for _, fn in ipairs(handlers[event] or {}) do fn(event, ...) end
end

ns.Print = function(text) said[#said + 1] = text end
ns.Warn = function(text) said[#said + 1] = "WARN " .. text end
ns.PrintRaw, ns.Debug = noop, noop

local settings = { postDuration = 2, verifyPriceBeforePosting = true, askBeforeListing = true }
ns.db = {}
ns.Config = {
    Get = function(_, k) return settings[k] end,
    Set = function(_, k, v) settings[k] = v end,
    GetRealmKey = function() return "Realm-Alliance" end,
    GetCharacterKey = function() return "Player-1" end,
}

-- Searches for one item: counted, answered by the test.
local searches, recorded = {}, {}
ns.Scanner = {
    isAuctionHouseOpen = true, isScanning = false,
    IsCommodity = function() return true end,
    ScanItem = function(_, itemID, cb)
        searches[#searches + 1] = { itemID = itemID, cb = cb }
        return true
    end,
    AbandonItemScan = noop,
    RecordPassive = function(_, itemID, market, minBuyout, quantity, rival)
        recorded[itemID] = rival
        return true
    end,
}

local MARKET = { [POTION] = 300, [OIL] = 1000, [RING] = 5000, [CLOAK] = 800 }
ns.Prices = {
    GetValue = function(_, itemID, key)
        if key == "market" then return MARKET[itemID] end
        if key == "rival" then return recorded[itemID] end
    end,
    GetScanValue = function(_, itemID, key) if key == "market" then return MARKET[itemID] end end,
    Get = function() return {} end,
    IsCredible = function(price) return type(price) == "number" and price > 0 end,
}
ns.Inventory = {
    GetCarriedBags = function() return { 0 } end,
    GetBagCount = function(_, itemID)
        for _, e in ipairs(bags[0]) do if e.itemID == itemID then return e.stackCount end end
        return 0
    end,
}
ns.Recipes = { GetAccountWide = function() return {} end }
ns.Queue = { GetReservedItems = function() return {} end }
local costs = {}
ns.Cost = { FindAnyRecipeForItem = function(_, itemID) return costs[itemID] and itemID or nil end }
ns.Profit = {
    ChoosePostPrice = function(_, itemID) return recorded[itemID] or MARKET[itemID], "undercut" end,
    Analyse = function(_, recipeID) return { costPerUnit = costs[recipeID] } end,
}

-- The queue: requests are kept, and sent when the test says.
local queued = {}
ns.AHQueue = {
    Yield = noop, NoteSend = noop, PRIORITY = { urgent = 10 }, MIN_SPACING = 1.2,
    SecondsUntilReady = function() return 1.2, "spacing out requests to the auction house" end,
    Request = function(_, request) queued[#queued + 1] = request; return true end,
}
local function SendQueued()
    local list = queued
    queued = {}
    for _, request in ipairs(list) do request.send() end
end

local posted, keysSearched, browseRows = {}, nil, {}
C_AuctionHouse = {
    PostCommodity = function(_, _, quantity, price) posted[#posted + 1] = { quantity = quantity, price = price } end,
    MakeItemKey = function(itemID) return { itemID = itemID, itemSuffix = 0 } end,
    SearchForItemKeys = function(keys) keysSearched = keys end,
    GetBrowseResults = function() return browseRows end,
}

ns.UI = { RefreshActiveTab = noop, UpdatePostButton = noop }

assert(loadfile(lfs_cwd .. "/Core/Util.lua"))("Blackthornes_TS", ns)
assert(loadfile(lfs_cwd .. "/Logic/Posting.lua"))("Blackthornes_TS", ns)
assert(loadfile(lfs_cwd .. "/Data/Auctions.lua"))("Blackthornes_TS", ns)

local Posting = ns.Posting
Posting:OnEnable()

local passed, failed = 0, 0
local function check(label, got, want)
    local ok = got == want
    if ok then passed = passed + 1 else failed = failed + 1 end
    print(string.format("  %-62s %-8s %s", label, tostring(got), ok and "ok" or
        ("WRONG, wanted " .. tostring(want))))
end

-- Floors by item: { floor, why, kind }. "market" alone is asked about;
-- anything else refuses. A typed price (byHand) has no market floor.
local floors = {}
Posting.GetPriceFloor = function(_, itemID, byHand)
    local f = floors[itemID]
    if not f or (byHand and f[3] == "market") then return nil end
    return f[1], f[2], f[3]
end

local function Lines()
    return {
        { itemID = POTION, unitPrice = 300, postQuantity = 5, total = 1500 },
        { itemID = OIL, unitPrice = 1000, postQuantity = 3, total = 3000 },
    }
end

local function NextID()
    local line = Posting:GetNextPostable(nil, Lines())
    return line and line.itemID
end

local function Reset()
    said, popup, searches, posted, queued, recorded, costs, floors = {}, nil, {}, {}, {}, {}, {}, {}
    Posting.confirming, Posting.pending, Posting.others, Posting.requesting = nil, nil, nil, {}
    Posting.chosenPrice = {}
    Posting:ForgetChecks()
    ns.Scanner.isAuctionHouseOpen, ns.Scanner.isScanning = true, false
    settings.askBeforeListing = nil
    FillBags()
end

print("")
print("a stack refused at the checked price")

Reset()
check("the potion is next to start with", NextID(), POTION)
floors[POTION] = { 200, "under what a vendor pays", "vendor" }
recorded[POTION] = 150
Posting:NoteChecked(POTION)
Posting:Request(POTION, 5, 300)
check("it is not listed", #posted, 0)
check("it is passed over", Posting:IsPassedOver(POTION), true)
check("the oil is next now", NextID(), OIL)
check("List all counts only the oil", (Posting:GetSummary(nil, Lines())), 1)

print("")
print("setting its price by hand, or leaving, gives it another go")

Posting:SetChosenPrice(POTION, 250)
check("a typed price brings it back", NextID(), POTION)
Posting:PassOver(POTION)
Fire("AUCTION_HOUSE_CLOSED")
check("leaving the auction house brings it back", NextID(), POTION)

print("")
print("far under the usual price, asked in the box")

Reset()
floors[POTION] = { 200, "far under the usual price", "market" }
recorded[POTION] = 150
Posting:NoteChecked(POTION)
Posting:Request(POTION, 5, 300)
check("the box asks", popup ~= nil, true)
local dialog = StaticPopupDialogs["BLACKTHORNES_TS_CONFIRM_POST"]
dialog.OnCancel(popup, nil, "override")
check("the box replaced by the next is not a skip", Posting:IsPassedOver(POTION), false)
dialog.OnCancel(popup, nil, "clicked")
check("Skip passes it over", Posting:IsPassedOver(POTION), true)
check("the oil is next now", NextID(), OIL)

print("")
print("nothing transient passes over")

Reset()
ns.Scanner.isScanning = true
Posting:NoteChecked(POTION)
Posting:Request(POTION, 5, 300)
check("a scan running refuses it for now", #posted, 0)
check("but leaves it next", Posting:IsPassedOver(POTION), false)
ns.Scanner.isScanning = false
recorded[POTION] = 290
Posting:Request(POTION, 5, 290)
check("and it lists on the next click", #posted, 1)

for _, key in ipairs(GLOBALS) do _G[key] = saved[key] end

print("")
print(("%d passed, %d failed"):format(passed, failed))
assert(failed == 0, "pass over checks failed")
