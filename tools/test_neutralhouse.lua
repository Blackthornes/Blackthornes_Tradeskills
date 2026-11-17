-- Listings at the neutral auction house and at your own side's.
--
-- A player found that after a visit to a neutral auction house (Booty Bay,
-- Gadgetzan, Everlook), Keep in stock and Sales thought nothing was listed:
-- each visit wrote one reading over the last, so the goblins' list (often
-- empty) replaced the home house's. Each house now keeps its own reading,
-- and a visit only replaces its own house's listings.

-- Tests share one Lua state, so every global replaced here is put back,
-- including the ones that were not set at all.
local GLOBALS = { "CreateFrame", "GetTime", "time", "C_Timer", "C_AuctionHouse",
    "GetInboxNumItems", "GetInboxHeaderInfo", "GetInboxItem", "GetInboxItemLink",
    "GetInboxInvoiceInfo", "ATTACHMENTS_MAX_RECEIVE", "AUCTION_SOLD_MAIL_SUBJECT",
    "AUCTION_EXPIRED_MAIL_SUBJECT", "AUCTION_REMOVED_MAIL_SUBJECT",
    "UnitExists", "UnitFactionGroup", "UnitGUID" }
local saved = {}
for _, key in ipairs(GLOBALS) do saved[key] = _G[key] end

local function noop() end

local function Blank()
    return setmetatable({}, { __index = function(_, k)
        if type(k) == "string" and k:match("^%u") then return noop end
    end })
end

local wall = 100000
CreateFrame = function() return Blank() end
GetTime = function() return 1000 end
time = function() return wall end
C_Timer = {
    After = noop,
    NewTimer = function() return { Cancel = noop } end,
    NewTicker = function() return { Cancel = noop } end,
}

-- Your auctions, as the auction house hands them back.
local owned = {}
C_AuctionHouse = {
    GetNumOwnedAuctions = function() return #owned end,
    GetOwnedAuctionInfo = function(index) return owned[index] end,
}

-- A mailbox. Each mail: subject, items = { { itemID, count } }, daysLeft.
local inbox = {}
GetInboxNumItems = function() return #inbox end
GetInboxHeaderInfo = function(index)
    local mail = inbox[index]
    if not mail then return nil end
    -- packageIcon, stationeryIcon, sender, subject, money, COD, daysLeft, items
    return nil, nil, "Auction House", mail.subject, 0, 0, mail.daysLeft, #mail.items
end
GetInboxItem = function(index, slot)
    local item = inbox[index] and inbox[index].items[slot]
    if not item then return nil end
    return "Bolt of Linen Cloth", item[1], 0, item[2], 1, true
end
GetInboxItemLink = function(index, slot)
    local item = inbox[index] and inbox[index].items[slot]
    if not item then return nil end
    return ("|cffffffff|Hitem:%d::::::::::|h[Bolt of Linen Cloth]|h|r"):format(item[1])
end
GetInboxInvoiceInfo = nil
ATTACHMENTS_MAX_RECEIVE = 16
AUCTION_SOLD_MAIL_SUBJECT = "Auction successful: %s"
AUCTION_EXPIRED_MAIL_SUBJECT = "Auction expired: %s"
AUCTION_REMOVED_MAIL_SUBJECT = "Auction cancelled: %s"

local ns = {}
ns.COLORS = setmetatable({}, { __index = function() return "ffffffff" end })
ns.NewModule = function(name) local m = {}; ns[name] = m; return m end
ns.RegisterCommand = noop
ns.RegisterEvent = function() return true end
ns.Print, ns.PrintRaw, ns.Debug, ns.Warn = noop, noop, noop, noop

-- The auctioneer you are talking to: a side's own, or a goblin who
-- answers to no side.
local auctioneer = "Alliance"
UnitExists = function(unit) return unit == "npc" and auctioneer ~= false end
UnitFactionGroup = function(unit)
    if unit == "player" then return "Alliance" end
    if unit == "npc" and auctioneer then return auctioneer end
    return nil
end
UnitGUID = function() return nil end

local Visit

local who = "Main-TestRealm"
local characterRecord = {}
ns.db = {}
ns.Config = {
    Get = function() return nil end,
    GetRealmKey = function() return "TestRealm-Alliance" end,
    GetCharacterKey = function() return who end,
}
ns.Recipes = {
    GetCharacterRecord = function() return characterRecord end,
    GetAll = function() return {} end,
    GetAccountWide = function() return {} end,
}
ns.Scanner = { isAuctionHouseOpen = true, IsCommodity = function() return false end }

assert(loadfile(lfs_cwd .. "/Core/Util.lua"))("Blackthornes_TS", ns)
assert(loadfile(lfs_cwd .. "/Data/Auctions.lua"))("Blackthornes_TS", ns)
assert(loadfile(lfs_cwd .. "/Data/Mail.lua"))("Blackthornes_TS", ns)
assert(loadfile(lfs_cwd .. "/Logic/AuctionTracker.lua"))("Blackthornes_TS", ns)

local Auctions, Mail = ns.Auctions, ns.Mail

local passed, failed = 0, 0
local function check(label, got, expected)
    if got == expected then
        passed = passed + 1
        print(("  ok    %s"):format(label))
    else
        failed = failed + 1
        print(("  FAIL  %s: %s, expected %s"):format(label, tostring(got), tostring(expected)))
    end
end

local BOLT = 2996
local HOUR, DAY = 3600, 86400


Visit = function(kind)
    auctioneer = kind
    -- Leaving and coming back: the house is read again at the next visit.
    Auctions:OnHouseClosed()
    Auctions:ReadOwned()
end

local function Stack(auctionID, itemID, quantity)
    return { auctionID = auctionID, itemKey = { itemID = itemID or BOLT }, quantity = quantity or 5,
        buyoutAmount = 5000,
        itemLink = ("|cffffffff|Hitem:%d::::::::::|h[Bolt of Linen Cloth]|h|r"):format(itemID or BOLT) }
end

local WOOL = 2592

print("")
print("a visit to the neutral house keeps the home listings")

owned = { Stack(1), Stack(2) }
Visit("Alliance")
check("two stacks at home", Auctions:GetPostedCount(BOLT), 10)
check("the home house is yours", Auctions:CurrentHouse(), "home")

wall = wall + 60
owned = {}
Visit(nil)
check("a goblin auctioneer is the neutral house", Auctions:CurrentHouse(), "neutral")
check("nothing listed there leaves the home stacks counted", Auctions:GetPostedCount(BOLT), 10)
check("and nothing of yours is up at this house", Auctions:GetOwnPostedCount(BOLT), 0)

wall = wall + 60
owned = { Stack(7, WOOL, 3) }
Visit(nil)
check("a listing at the neutral house counts too", Auctions:GetPostedCount(WOOL), 3)
check("the home stacks still count", Auctions:GetPostedCount(BOLT), 10)

local listings = Auctions:GetListings()
local home, neutral = 0, 0
for _, listing in ipairs(listings) do
    if listing.house == "neutral" then neutral = neutral + 1 else home = home + 1 end
end
check("Still listed shows both home stacks", home, 2)
check("and the neutral one, marked as the neutral house's", neutral, 1)
local named
for _, listing in ipairs(listings) do
    if listing.itemID == WOOL then named = listing.link end
end
check("a listing keeps its link, so its name reads without the item cache", named ~= nil, true)

-- The auction tracker, standing at the neutral house: what is up there is
-- read live, and the home stacks are still on its list.
local function TrackerCount(itemID)
    local n = 0
    for _, row in ipairs(ns.AuctionTracker:Rows()) do
        if row.itemID == itemID then n = n + 1 end
    end
    return n
end
check("the tracker lists the neutral listing", TrackerCount(WOOL), 1)
check("and keeps the two home stacks", TrackerCount(BOLT), 2)

wall = wall + 60
owned = { Stack(1) }
Visit("Alliance")
check("back home the tracker lists one home stack", TrackerCount(BOLT), 1)
check("and still the neutral listing", TrackerCount(WOOL), 1)
check("back home, the home reading is replaced", Auctions:GetPostedCount(BOLT), 5)
check("the neutral listing stays", Auctions:GetPostedCount(WOOL), 3)
check("verifying a new listing reads this house only", Auctions:GetOwnPostedCount(WOOL), 0)

print("")
print("an auctioneer that cannot be read")

wall = wall + 60
owned = { Stack(1) }
auctioneer = false
Auctions:OnHouseClosed()
check("reads as home, as it always did", Auctions:CurrentHouse(), "home")

print("")
print("saved before the houses were kept apart")

ns.db.postedAuctions = nil
local record = Auctions:GetTable()
record.byCharacter = { [who] = { items = { [BOLT] = 5 }, updatedAt = wall - 60,
    listings = { { itemID = BOLT, quantity = 5 } } } }
record.items = { [BOLT] = 5 }
record.updatedAt = wall - 60
check("an old reading counts as the home house's", Auctions:GetPostedCount(BOLT), 5)
owned = {}
Visit(nil)
check("and a neutral visit leaves it alone", Auctions:GetPostedCount(BOLT), 5)
check("the old key is where it was", record.byCharacter[who].items[BOLT], 5)

for _, key in ipairs(GLOBALS) do _G[key] = saved[key] end

print("")
print(("%d passed, %d failed"):format(passed, failed))
assert(failed == 0, "neutral auction house checks failed")
