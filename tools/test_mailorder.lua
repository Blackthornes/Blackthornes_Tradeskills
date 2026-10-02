-- Look-alike mails, and each character's first reading of its own list.
--
-- The inbox lists the newest mail first, and two sales of one item share a
-- fingerprint on purpose. Walked in the inbox's order, a sale that arrived
-- while an older one of the same item still sat in the box (its gold held,
-- say) passed as the one already written down. The older one was written
-- down a second time with its own figure, and the new sale never was.
--
-- The switch to a list per character (v0.16.0) had three ways to go wrong on
-- a character's first reading: the old shared list was copied to every
-- character, so a new character's first sale of an item on it was never
-- written down; an alt's new sales were taken for sales it made weeks before,
-- by name alone; and sales written down under the old name-realm key were
-- written down again under the GUID.

-- Tests share one Lua state, so every global replaced here is put back,
-- including the ones that were not set at all.
local GLOBALS = { "GetInboxNumItems", "GetInboxHeaderInfo", "GetInboxItem", "GetInboxItemLink",
    "GetInboxInvoiceInfo", "ATTACHMENTS_MAX_RECEIVE", "AUCTION_SOLD_MAIL_SUBJECT",
    "AUCTION_EXPIRED_MAIL_SUBJECT", "AUCTION_REMOVED_MAIL_SUBJECT", "C_Item", "C_Container",
    "C_Timer", "CreateFrame", "GetTime", "time" }
local saved = {}
for _, key in ipairs(GLOBALS) do saved[key] = _G[key] end

local function noop() end

local ns = {}
ns.COLORS = setmetatable({}, { __index = function() return "ffffffff" end })
ns.NewModule = function(name) local m = {}; ns[name] = m; return m end
ns.RegisterCommand = noop
ns.RegisterEvent = function() return true end
ns.Print, ns.PrintRaw, ns.Debug, ns.Warn = noop, noop, noop, noop

local clock = 1790000000
GetTime = function() return clock end
time = function() return clock end

--------------------------------------------------------------------------------
-- A mailbox, newest first
--------------------------------------------------------------------------------

-- Each mail: { sender, subject, money, daysLeft, items = { { itemID, count } },
--              invoice = { itemName, bid, cut, deposit } }
local inbox = {}

ATTACHMENTS_MAX_RECEIVE = 16

GetInboxNumItems = function() return #inbox end

GetInboxHeaderInfo = function(index)
    local mail = inbox[index]
    if not mail then return nil end
    return nil, nil, mail.sender, mail.subject, mail.money or 0, 0, mail.daysLeft, #(mail.items or {})
end

GetInboxItem = function(index, slot)
    local item = inbox[index] and inbox[index].items and inbox[index].items[slot]
    if not item then return nil end
    return "Some Item", item.itemID, 133633, item.count, 1, true
end

GetInboxItemLink = function(index, slot)
    local item = inbox[index] and inbox[index].items and inbox[index].items[slot]
    if not item then return nil end
    return ("|cffffffff|Hitem:%d::::::::::|h[Some Item]|h|r"):format(item.itemID)
end

GetInboxInvoiceInfo = function(index)
    local mail = inbox[index]
    if not mail or not mail.invoice then return nil end
    local i = mail.invoice
    return "seller", i.itemName, "Buyer", i.bid, i.bid, i.deposit or 0, i.cut or 0, 0
end

AUCTION_SOLD_MAIL_SUBJECT = "Auction successful: %s"
AUCTION_EXPIRED_MAIL_SUBJECT = "Auction expired: %s"
AUCTION_REMOVED_MAIL_SUBJECT = "Auction cancelled: %s"

local LINEN_BAG, CLOTH = 4238, 2589
local itemNames = { [LINEN_BAG] = "Linen Bag", [CLOTH] = "Linen Cloth" }

C_Item = { GetItemInfo = function(itemID) return itemNames[itemID] end }
C_Container = { GetContainerNumSlots = function() return 0 end, GetContainerItemInfo = noop }
C_Timer = { After = noop, NewTimer = function() return { Cancel = noop } end }
CreateFrame = function()
    return setmetatable({}, { __index = function(_, key)
        if type(key) == "string" and key:match("^%u") then return noop end
    end })
end

--------------------------------------------------------------------------------
-- The addon around it
--------------------------------------------------------------------------------

local record = {}
local who, legacy = "Player-1-0001", "Tester-Testrealm"

ns.db = { mailLedger = {} }
ns.Config = {
    Get = function() return nil end,
    GetRealmKey = function() return "Testrealm-Alliance" end,
    GetCharacterKey = function() return who end,
    GetLegacyCharacterKey = function() return legacy end,
}
ns.Recipes = {
    GetCharacterRecord = function() return record end,
    GetAll = function() return {} end,
    GetAccountWide = function() return { [1] = { outputItemID = LINEN_BAG } } end,
}

assert(loadfile(lfs_cwd .. "/Core/Util.lua"))("Blackthornes_TS", ns)
assert(loadfile(lfs_cwd .. "/Data/Mail.lua"))("Blackthornes_TS", ns)

local Mail = ns.Mail

--------------------------------------------------------------------------------

local passed, failed = 0, 0

local function check(label, got, expected)
    local ok = got == expected
    if ok then passed = passed + 1 else failed = failed + 1 end
    print(("  %-58s %-8s %s"):format(label, tostring(got), ok and "ok" or
        ("FAILED, expected " .. tostring(expected))))
end

--- A sale. `money` is what the mail pays now, 0 while the gold is held; the
--- invoice says what it went for. No `bid` means no invoice yet.
local function Sale(money, bid, daysLeft)
    return { sender = "Auction House", subject = "Auction successful: Linen Bag", money = money,
        daysLeft = daysLeft, invoice = bid and { itemName = "Linen Bag", bid = bid } or nil }
end

local function Reset()
    inbox = {}
    ns.db.mailLedger = {}
    who, legacy = "Player-1-0001", "Tester-Testrealm"
    Mail.inboxUpdatedThisVisit = true
    Mail.nameCache = nil
end

local function Summary() return Mail:GetSummary() end

--------------------------------------------------------------------------------
print("")
print("a sale arriving while an older one of the item waits in the box")
--------------------------------------------------------------------------------

Reset()

-- The first sale's gold is held, so its mail stays in the box.
inbox = { Sale(0, 300, 29.0) }
Mail:Read()
check("the held sale is written down from its invoice", Summary().net, 300)

-- An hour later a second sale of the same bag lands on top.
inbox = { Sale(900, 900, 29.9), Sale(0, 300, 28.9) }
Mail:Read()
check("two sales",                                      Summary().sold, 2)
check("each with its own figure",                       Summary().net, 1200)
check("only the first is still being paid",             Summary().estimated, 1)

inbox[2].money = 300
Mail:Read()
check("the held gold lands on the right sale",          Summary().estimated, 0)
check("and the total stands",                           Summary().net, 1200)

Mail:Read()
check("looking again changes nothing",                  Summary().net, 1200)

-- Both paid, the older one simply left in the box.
Reset()
inbox = { Sale(300, 300, 29.0) }
Mail:Read()
inbox = { Sale(900, 900, 29.9), Sale(300, 300, 28.9) }
Mail:Read()
check("a sale left in the box does not hide the next",  Summary().net, 1200)

--------------------------------------------------------------------------------
print("")
print("a look-alike sale that cannot be priced yet")
--------------------------------------------------------------------------------

-- The older sale has neither gold nor an invoice yet; the newer is paid.
Reset()
inbox = { Sale(700, 700, 29.9), Sale(0, nil, 29.0) }
Mail:Read()
check("nothing is written down while one cannot be priced", Summary().sold, 0)
check("and it says it is waiting",                      Mail.awaitingAmount, 1)

inbox[2].money = 450
Mail:Read()
check("both, once it can be",                           Summary().sold, 2)
check("each from its own mail",                         Summary().net, 1150)

Mail:Read()
check("and not again",                                  Summary().sold, 2)

-- The other way round: the newer one waits.
Reset()
inbox = { Sale(0, nil, 29.9), Sale(700, 700, 29.0) }
Mail:Read()
check("the paid older sale is written down",            Summary().net, 700)

inbox[1].money = 450
Mail:Read()
check("and the newer one when it can be priced",        Summary().net, 1150)
check("two sales",                                      Summary().sold, 2)

--------------------------------------------------------------------------------
print("")
print("the old shared list starts one character, not every one")
--------------------------------------------------------------------------------

-- Saved before the lists were per character: the main read last, with two
-- of its Linen Bag sales still in its box.
Reset()
who = "Player-main"
inbox = { Sale(300, 300, 29.5), Sale(400, 400, 29.0) }
Mail:Read()
local ledger = Mail:GetLedger()
ledger.seen, ledger.seenBy, ledger.seenSeeded = ledger.seenBy[who], nil, nil
check("two sales on the books",                         #ledger.entries, 2)

Mail:Read()
check("the main's first reading writes nothing again",  #ledger.entries, 2)

-- Months later a new character sells a Linen Bag of its own.
who = "Player-new"
inbox = { Sale(500, 500, 29.9) }
Mail:Read()
check("a new character's first sale is written down",   #ledger.entries, 3)
Mail:Read()
check("once",                                           #ledger.entries, 3)

--------------------------------------------------------------------------------
print("")
print("an alt's first reading since the switch")
--------------------------------------------------------------------------------

-- The alt sold two Linen Bags weeks ago, all collected. Another character
-- has read since the switch, so the shared list is spent.
Reset()
ledger = Mail:GetLedger()
ledger.entries = {
    { t = 1, kind = "sold", who = who, name = "Linen Bag", net = 250 },
    { t = 2, kind = "sold", who = who, name = "Linen Bag", net = 260 },
}
ledger.seenBy = { ["Player-main"] = {} }
inbox = { Sale(650, 650, 29.9), Sale(700, 700, 29.0) }
Mail:Read()
check("two new sales are not taken for the old ones",   #ledger.entries, 4)
check("and their gold is counted",                      Summary().net, 250 + 260 + 650 + 700)

-- Written down before the GUID keys, still in the box.
Reset()
ledger = Mail:GetLedger()
ledger.entries = {
    { t = 1, kind = "sold", who = legacy, name = "Linen Bag", net = 300 },
    { t = 2, kind = "sold", who = legacy, name = "Linen Bag", net = 400 },
}
ledger.seenBy = { ["Player-main"] = {} }
inbox = { Sale(400, 400, 29.5), Sale(300, 300, 29.0) }
Mail:Read()
check("sales under the old key are not written again",  #ledger.entries, 2)
check("so the gold is not doubled",                     Summary().net, 700)

-- A sale written down from its invoice while the gold was held.
Reset()
ledger = Mail:GetLedger()
ledger.entries = { { t = 1, kind = "sold", who = who, name = "Linen Bag", net = 325, estimated = true } }
ledger.seenBy = { ["Player-main"] = {} }
inbox = { { sender = "Auction House", subject = "Auction successful: Linen Bag", money = 0, daysLeft = 29,
    invoice = { itemName = "Linen Bag", bid = 300, cut = 15, deposit = 40 } } }
Mail:Read()
check("a held sale matches its estimate",               #ledger.entries, 1)

-- A returned listing with a stack already taken before the switch.
Reset()
ledger = Mail:GetLedger()
ledger.entries = { { t = 1, kind = "expired", who = who, name = "Linen Cloth", itemID = CLOTH, quantity = 60 } }
ledger.seenBy = { ["Player-main"] = {} }
inbox = { { sender = "Auction House", subject = "Auction expired: Linen Cloth", daysLeft = 29,
    items = { { itemID = CLOTH, count = 20 }, { itemID = CLOTH, count = 20 } } } }
Mail:Read()
check("a part-taken return is not written again",       #ledger.entries, 1)

-- Written down before 0.16.0, when a return's entry counted its first stack.
Reset()
ledger = Mail:GetLedger()
ledger.entries = { { t = 1, kind = "expired", who = who, name = "Linen Cloth", itemID = CLOTH, quantity = 20 } }
ledger.seenBy = { ["Player-main"] = {} }
inbox = { { sender = "Auction House", subject = "Auction expired: Linen Cloth", daysLeft = 29,
    items = { { itemID = CLOTH, count = 20 }, { itemID = CLOTH, count = 20 } } } }
Mail:Read()
check("a return counted by its first stack is not written again", #ledger.entries, 1)

-- A return of another size than the one written down is a new one.
Reset()
ledger = Mail:GetLedger()
ledger.entries = { { t = 1, kind = "expired", who = who, name = "Linen Cloth", itemID = CLOTH, quantity = 10 } }
ledger.seenBy = { ["Player-main"] = {} }
inbox = { { sender = "Auction House", subject = "Auction expired: Linen Cloth", daysLeft = 29,
    items = { { itemID = CLOTH, count = 20 } } } }
Mail:Read()
check("a new return of another size is written down",   #ledger.entries, 2)

--------------------------------------------------------------------------------

for _, key in ipairs(GLOBALS) do _G[key] = saved[key] end

print("")
print(("%d passed, %d failed"):format(passed, failed))
assert(failed == 0, "look-alike mail checks failed")
