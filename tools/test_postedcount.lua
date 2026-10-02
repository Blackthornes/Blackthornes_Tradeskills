-- How many you still have listed, between visits to the auction house.
--
--  * A stack cancelled or expired before your auctions were last read is
--    already missing from that reading. Its mail, opened later, was taken
--    off a second time: 10 listed, one stack of 5 cancelled, and the count
--    read none with 5 still up. What counts is when the mail was sent, which
--    its days left say, not when the inbox was read.
--  * A stack that came back after the reading still comes off it.
--  * A character's reading older than the longest auction (24 hours here)
--    counts nothing. An alt whose listings sold and who never went back kept
--    them counted for good: a sale sends gold, not the item.

-- Tests share one Lua state, so every global replaced here is put back,
-- including the ones that were not set at all.
local GLOBALS = { "CreateFrame", "GetTime", "time", "C_Timer", "C_AuctionHouse",
    "GetInboxNumItems", "GetInboxHeaderInfo", "GetInboxItem", "GetInboxItemLink",
    "GetInboxInvoiceInfo", "ATTACHMENTS_MAX_RECEIVE", "AUCTION_SOLD_MAIL_SUBJECT",
    "AUCTION_EXPIRED_MAIL_SUBJECT", "AUCTION_REMOVED_MAIL_SUBJECT" }
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

-- A listed stack of 5. No status reads as still for sale.
local function Stack(auctionID)
    return { auctionID = auctionID, itemKey = { itemID = BOLT }, quantity = 5, buyoutAmount = 5000 }
end

--- A returned stack's mail, read `ago` seconds after it was sent.
local function Returned(subject, ago)
    return { subject = subject, items = { { BOLT, 5 } }, daysLeft = 30 - ago / DAY }
end

local function LastEntry()
    local entries = Mail:GetLedger().entries
    return entries[#entries]
end

print("")
print("a stack that came back before the reading")

owned = { Stack(1), Stack(2) }
Auctions:ReadOwned()
check("both stacks are listed", Auctions:GetPostedCount(BOLT), 10)

-- One is cancelled, and the read after the cancel no longer has it.
wall = wall + 100
local cancelledAt = wall
owned = { Stack(1) }
wall = wall + 7
Auctions:ReadOwned()
check("the read after the cancel shows the other", Auctions:GetPostedCount(BOLT), 5)

-- Half an hour later, at the mailbox.
wall = wall + 1800
inbox = { Returned("Auction cancelled: Bolt of Linen Cloth", wall - cancelledAt) }
Mail:Read()
check("the mail is written down", LastEntry() and LastEntry().kind, "removed")
check("with when it was sent", LastEntry() and LastEntry().sent, cancelledAt)
check("and when it was read", LastEntry() and LastEntry().t, wall)
check("the stack still up is still counted", Auctions:GetPostedCount(BOLT), 5)

print("")
print("a stack that came back after the reading")

-- The other stack expires two hours after the last read, and its mail is
-- read an hour after that.
wall = wall + 2 * HOUR
local expiredAt = wall
wall = wall + HOUR
inbox[#inbox + 1] = Returned("Auction expired: Bolt of Linen Cloth", wall - expiredAt)
Mail:Read()
check("its mail says when it was sent", LastEntry() and LastEntry().sent, expiredAt)
check("it comes off the reading", Auctions:GetPostedCount(BOLT), 0)

-- Entries written before the send time was kept go by when they were read.
ns.db.mailLedger = nil
ns.db.postedAuctions = nil
owned = { Stack(1), Stack(2) }
Auctions:ReadOwned()
local readAt = wall
Mail:GetLedger().entries = {
    { t = readAt + 60, kind = "expired", who = who, itemID = BOLT, quantity = 5 },
}
check("one written before send times were kept still comes off", Auctions:GetPostedCount(BOLT), 5)

print("")
print("a reading older than the longest auction")

ns.db.mailLedger = nil
ns.db.postedAuctions = nil

who = "Alt-TestRealm"
owned = { Stack(1) }
Auctions:ReadOwned()

who = "Main-TestRealm"
owned = {}
Auctions:ReadOwned()

check("an alt's listing counts while it could still be up", Auctions:GetPostedCount(BOLT), 5)
wall = wall + 23 * HOUR
check("23 hours on, it still counts", Auctions:GetPostedCount(BOLT), 5)
wall = wall + 2 * HOUR
check("past 24 hours it counts nothing", Auctions:GetPostedCount(BOLT), 0)

-- Saved before readings were kept per character.
local record = Auctions:GetTable()
record.byCharacter = nil
record.items = { [BOLT] = 5 }
record.updatedAt = wall - HOUR
check("an old shared reading counts while it could still be up", Auctions:GetPostedCount(BOLT), 5)
record.updatedAt = wall - 2 * DAY
check("and not once it is older than any auction", Auctions:GetPostedCount(BOLT), 0)

for _, key in ipairs(GLOBALS) do _G[key] = saved[key] end

print("")
print(("%d passed, %d failed"):format(passed, failed))
assert(failed == 0, "posted count checks failed")
