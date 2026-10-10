-- The mailbox: stock you cannot see, and the record of what actually sold.
--
-- Two bugs motivate this file.
--
-- The first: an auction that expires comes back as mail, and until it is
-- collected the item is counted nowhere. It has dropped off your auctions and
-- it is not in your bags. So the Profit tab happily told you to craft more of
-- something already on its way home.
--
-- The second: nothing recorded whether a listing sold or came back. Owned
-- auctions are re-read from scratch each time, so both look identical -- the
-- listing is simply gone. The ledger here reads the mailbox and writes down
-- which it was.
--
-- The hard part of the ledger is identity. Mail has no id, indices shuffle as
-- mail is taken, and MAIL_INBOX_UPDATE fires repeatedly with a half-loaded
-- inbox. So it works by counting fingerprints rather than matching them, and
-- most of what follows is about that being right under re-reads, duplicates
-- and partial reads.

local ns = {}
ns.COLORS = setmetatable({}, {__index = function() return "ffffffff" end})
ns.NewModule = function(name) local m = {}; ns[name] = m; return m end
ns.RegisterCommand = function() end
ns.RegisterEvent = function() return true end
ns.Print, ns.PrintRaw, ns.Debug, ns.Warn = function() end, function() end, function() end, function() end

local clock = 0
GetTime = function() return clock end
local function Tick() clock = clock + 10 end

time = time or os.time

--------------------------------------------------------------------------------
-- A client with a mailbox
--------------------------------------------------------------------------------

-- Each entry: { sender, subject, money, cod, items = { { itemID, count } },
--               invoice = { ... }, declared = n }
--
-- `declared` overrides the attachment count in the header, which is how a mail
-- whose attachments have not loaded yet is simulated: the header says two
-- items, the slots hand back nothing.
local inbox = {}

ATTACHMENTS_MAX_RECEIVE = 16

GetInboxNumItems = function() return #inbox end

GetInboxHeaderInfo = function(index)
    local mail = inbox[index]
    if not mail then return nil end

    local declared = mail.declared or #(mail.items or {})

    -- packageIcon, stationeryIcon, sender, subject, money, COD, daysLeft, items
    return nil, nil, mail.sender, mail.subject,
        mail.money or 0, mail.cod or 0, 27.5, declared
end

-- The newer return shape: name, itemID, texture, count, quality, canUse.
GetInboxItem = function(index, slot)
    local mail = inbox[index]
    local item = mail and mail.items and mail.items[slot]
    if not item or item.unloaded then return nil end

    return "Some Item", item.itemID, 133633, item.count, 1, true
end

GetInboxItemLink = function(index, slot)
    local mail = inbox[index]
    local item = mail and mail.items and mail.items[slot]
    if not item or item.unloaded then return nil end

    return ("|cffffffff|Hitem:%d::::::::::|h[Some Item]|h|r"):format(item.itemID)
end

GetInboxInvoiceInfo = function(index)
    local mail = inbox[index]
    if not mail or not mail.invoice then return nil end

    local i = mail.invoice
    return i.invoiceType or "seller", i.itemName, i.buyer or "Someone",
        i.bid, i.buyout, i.deposit, i.cut, i.moneyDelay
end

-- The client's own subject formats, which is what the classifier matches
-- against rather than hardcoded English.
AUCTION_SOLD_MAIL_SUBJECT = "Auction successful: %s"
AUCTION_EXPIRED_MAIL_SUBJECT = "Auction expired: %s"
AUCTION_REMOVED_MAIL_SUBJECT = "Auction cancelled: %s"

local LINEN_BAG, CLOTH, VIAL = 4238, 2589, 3371

local itemNames = {
    [LINEN_BAG] = "Linen Bag",
    [CLOTH] = "Linen Cloth",
    [VIAL] = "Crystal Vial",
}

C_Item = {
    GetItemCount = function() return 0 end,
    GetItemInfo = function(itemID) return itemNames[itemID] end,
}

C_Container = {
    GetContainerNumSlots = function() return 0 end,
    GetContainerItemInfo = function() return nil end,
}

C_Timer = {
    After = function() end,
    NewTimer = function() return { Cancel = function() end } end,
}

CreateFrame = function()
    local frame = {}
    for _, name in ipairs({ "SetScript", "Show", "Hide", "SetPoint", "SetSize" }) do
        frame[name] = function() end
    end
    return frame
end

GetInventoryItemID = function() return nil end

--------------------------------------------------------------------------------
-- The addon around it
--------------------------------------------------------------------------------

local characterRecord = { recipes = {}, inventory = {} }
local settings = { countMailAsStock = true, stockPenalty = 1 }

ns.db = { mailLedger = {} }

ns.Config = {
    Get = function(_, key) return settings[key] end,
    GetRealmKey = function() return "Testrealm-Alliance" end,
    GetCharacterKey = function() return "Tester-Testrealm" end,
}

ns.Recipes = {
    GetCharacterRecord = function(_, create)
        if create then return characterRecord end
        return characterRecord
    end,
    GetAll = function() return {} end,
    GetAccountWide = function()
        return { [1] = { outputItemID = LINEN_BAG }, [2] = { outputItemID = VIAL } }
    end,
}

ns.Queue = { GetAll = function() return {} end }

assert(loadfile(lfs_cwd .. "/Core/Util.lua"))("Blackthornes_TS", ns)
assert(loadfile(lfs_cwd .. "/Data/Inventory.lua"))("Blackthornes_TS", ns)
assert(loadfile(lfs_cwd .. "/Data/Mail.lua"))("Blackthornes_TS", ns)

local Inventory, Mail = ns.Inventory, ns.Mail

-- Inventory and Auctions lean on each other; Auctions is not under test here.
ns.Auctions = { GetPostedCount = function(_, itemID)
    return ({ [LINEN_BAG] = 3 })[itemID] or 0
end }

--------------------------------------------------------------------------------

local failures = 0

local function check(label, got, expected)
    local ok = got == expected
    if not ok then failures = failures + 1 end
    print(("  %-54s %-10s %s"):format(label, tostring(got), ok and "ok" or
        ("FAILED, expected " .. tostring(expected))))
end

--- Start again with an empty mailbox and an empty ledger.
local function Reset()
    inbox = {}
    characterRecord.mail = nil
    characterRecord.mailAt = nil
    ns.db.mailLedger = {}
    Mail.nameCache = nil
    -- These reads stand for ones made after the server has answered, as the
    -- addon's own are. An empty box before that is not trusted (Mail:Read).
    Mail.inboxUpdatedThisVisit = true
    Tick()
end

--------------------------------------------------------------------------------
print("")
print("what is in the mailbox is stock you own")
--------------------------------------------------------------------------------

Reset()

check("nothing read yet, so nothing held",     Inventory:GetMailCount(LINEN_BAG), 0)
check("and no age to report",                  Mail:GetAge(), nil)

inbox = {
    { sender = "Auction House", subject = "Auction expired: Linen Bag",
      items = { { itemID = LINEN_BAG, count = 2 } } },
}
Mail:Read()

check("two came back from a dead listing",     Inventory:GetMailCount(LINEN_BAG), 2)
check("and they count as owned",               Inventory:GetOwnedCount(LINEN_BAG), 2)
check("the total agrees",                      Inventory:GetTotalCount(LINEN_BAG), 2)
check("bags are untouched by any of it",       Inventory:GetBagCount(LINEN_BAG), 0)
check("something else is still nowhere",       Inventory:GetMailCount(CLOTH), 0)

-- The point of the whole exercise: before this, two Linen Bags on their way
-- home counted as zero, and the Profit tab said make more.
check("mail is read this session",             Mail:HasReadThisSession(), true)

--------------------------------------------------------------------------------
print("")
print("stacks across several mails add up")
--------------------------------------------------------------------------------

Reset()

inbox = {
    { sender = "Auction House", subject = "Auction expired: Linen Cloth",
      items = { { itemID = CLOTH, count = 20 } } },
    { sender = "Auction House", subject = "Auction expired: Linen Cloth",
      items = { { itemID = CLOTH, count = 12 } } },
    { sender = "Alt", subject = "here you go",
      items = { { itemID = CLOTH, count = 5 }, { itemID = VIAL, count = 1 } } },
}
Mail:Read()

check("every stack of it, wherever it came from", Inventory:GetMailCount(CLOTH), 37)
check("and the second item on that mail",          Inventory:GetMailCount(VIAL), 1)

--------------------------------------------------------------------------------
print("")
print("the setting turns it off without anything else knowing")
--------------------------------------------------------------------------------

settings.countMailAsStock = false

check("mail is not counted",                   Inventory:GetMailCount(CLOTH), 0)
check("nor owned",                             Inventory:GetOwnedCount(CLOTH), 0)

settings.countMailAsStock = true
check("and back again",                        Inventory:GetMailCount(CLOTH), 37)

--------------------------------------------------------------------------------
print("")
print("an attachment that has not loaded yet is not an empty mail")
--------------------------------------------------------------------------------

Reset()

-- The header says one item; the slot hands back nothing. Treating that as a
-- mail with no attachment would undercount stock AND write a ledger entry with
-- no item on it, which is the worse of the two.
inbox = {
    { sender = "Auction House", subject = "Auction expired: Linen Bag",
      declared = 1, items = { { itemID = LINEN_BAG, count = 2, unloaded = true } } },
}
Mail:Read()

check("nothing claimed while it is loading",   Inventory:GetMailCount(LINEN_BAG), 0)
check("and nothing written down",              #Mail:GetLedger().entries, 0)

inbox[1].items[1].unloaded = nil
Mail:Read()

check("counted once it arrives",               Inventory:GetMailCount(LINEN_BAG), 2)
check("and recorded exactly once",             #Mail:GetLedger().entries, 1)

--------------------------------------------------------------------------------
print("")
print("telling a sale from a return")
--------------------------------------------------------------------------------

Reset()

inbox = {
    { sender = "Auction House", subject = "Auction successful: Linen Bag",
      money = 285,
      invoice = { invoiceType = "seller", itemName = "Linen Bag",
                  bid = 300, buyout = 300, deposit = 40, cut = 15 } },
    { sender = "Auction House", subject = "Auction expired: Crystal Vial",
      items = { { itemID = VIAL, count = 1 } } },
    { sender = "Alt", subject = "some cloth for you",
      items = { { itemID = CLOTH, count = 20 } } },
}
Mail:Read()

local ledger = Mail:GetLedger()
check("the sale and the return, and not the gift", #ledger.entries, 2)

local summary = Mail:GetSummary()
check("one sold",                              summary.sold, 1)
check("one came back",                         summary.returned, 1)
check("what actually landed in the pocket",    summary.net, 285)
check("what the buyer paid",                   summary.gross, 300)
check("and the auction house's cut",           summary.cut, 15)
check("half of what went out came back",       summary.sellThrough, 0.5)
check("the return is filed as an expiry",      summary.expired, 1)
check("and nothing was cancelled",             summary.cancelled, 0)

-- A sale leaves no attachment, so the item has to be recovered from the
-- invoice's name against the recipes the addon knows about.
local bagSummary = Mail:GetSummary(LINEN_BAG)
check("the sale is filed under the right item", bagSummary.sold, 1)
check("with the gold against it",               bagSummary.net, 285)

check("the gift is still stock though",         Inventory:GetMailCount(CLOTH), 20)

--------------------------------------------------------------------------------
print("")
print("reading the same inbox again changes nothing")
--------------------------------------------------------------------------------

-- MAIL_INBOX_UPDATE fires repeatedly. If a re-read recorded the same sale
-- again, a morning at the mailbox would invent a fortune.
Mail:Read()
Mail:Read()
Mail:Read()

check("still two entries after three re-reads", #Mail:GetLedger().entries, 2)
check("and the gold has not multiplied",        Mail:GetSummary().net, 285)

--------------------------------------------------------------------------------
print("")
print("two identical sales are two sales")
--------------------------------------------------------------------------------

Reset()

local function SoldBag()
    return { sender = "Auction House", subject = "Auction successful: Linen Bag",
             money = 285,
             invoice = { invoiceType = "seller", itemName = "Linen Bag",
                         bid = 300, deposit = 40, cut = 15 } }
end

inbox = { SoldBag(), SoldBag() }
Mail:Read()

-- Identical mails fingerprint the same, on purpose: they are counted rather
-- than matched, so a collision is arithmetic instead of a lost sale.
check("both are recorded",                      Mail:GetSummary().sold, 2)
check("and both lots of gold",                  Mail:GetSummary().net, 570)

Mail:Read()
check("re-reading still leaves two",            Mail:GetSummary().sold, 2)

--------------------------------------------------------------------------------
print("")
print("an identical sale after collecting the first is a new sale")
--------------------------------------------------------------------------------

-- The failure this guards: remembering "seen it" rather than "there are two of
-- it" means the next identical sale is silently dropped, and the ledger quietly
-- under-reports the best-selling item you have.
inbox = {}
Mail:Read()

check("nothing left in the box",                #Mail:ReadInbox(), 0)
check("the ledger keeps what happened",         Mail:GetSummary().sold, 2)

inbox = { SoldBag() }
Mail:Read()

check("the next one counts too",                Mail:GetSummary().sold, 3)
check("and its gold",                           Mail:GetSummary().net, 855)

--------------------------------------------------------------------------------
print("")
print("a half-loaded inbox does not double-record")
--------------------------------------------------------------------------------

Reset()

-- The client hands back three mails but only the first has its attachment yet.
inbox = {
    { sender = "Auction House", subject = "Auction expired: Linen Bag",
      items = { { itemID = LINEN_BAG, count = 1 } } },
    { sender = "Auction House", subject = "Auction expired: Crystal Vial",
      declared = 1, items = { { itemID = VIAL, count = 1, unloaded = true } } },
    { sender = "Auction House", subject = "Auction expired: Linen Cloth",
      declared = 1, items = { { itemID = CLOTH, count = 20, unloaded = true } } },
}
Mail:Read()

check("only the one that loaded",               #Mail:GetLedger().entries, 1)

inbox[2].items[1].unloaded = nil
Mail:Read()
check("the second one, once it lands",          #Mail:GetLedger().entries, 2)

inbox[3].items[1].unloaded = nil
Mail:Read()
check("and the third",                          #Mail:GetLedger().entries, 3)

Mail:Read()
check("with no repeats from the settled ones",  #Mail:GetLedger().entries, 3)
check("stock adds up across all three",         Inventory:GetMailCount(CLOTH), 20)

--------------------------------------------------------------------------------
print("")
print("the subjects come from the client, so localisation works")
--------------------------------------------------------------------------------

Reset()

-- A French client, with a bracket in the format. If the format were dropped
-- into a pattern unescaped the brackets would be read as a character class and
-- nothing would ever match.
AUCTION_SOLD_MAIL_SUBJECT = "Vente r\195\169ussie (%s)"
AUCTION_EXPIRED_MAIL_SUBJECT = "Ench\195\168re expir\195\169e [%s]"
AUCTION_REMOVED_MAIL_SUBJECT = "Ench\195\168re annul\195\169e [%s]"
Mail:InvalidateMatchers()

inbox = {
    { sender = "H\195\180tel des ventes", subject = "Vente r\195\169ussie (Linen Bag)",
      money = 285 },
    { sender = "H\195\180tel des ventes", subject = "Ench\195\168re expir\195\169e [Crystal Vial]",
      items = { { itemID = VIAL, count = 1 } } },
}
Mail:Read()

check("the French sale is read as a sale",      Mail:GetSummary().sold, 1)
check("and the French expiry as a return",      Mail:GetSummary().returned, 1)

local kind, name = Mail:Classify({ subject = "Vente r\195\169ussie (Linen Bag)" })
check("the kind comes back",                    kind, "sold")
check("and the item name out of the subject",   name, "Linen Bag")

AUCTION_SOLD_MAIL_SUBJECT = "Auction successful: %s"
AUCTION_EXPIRED_MAIL_SUBJECT = "Auction expired: %s"
AUCTION_REMOVED_MAIL_SUBJECT = "Auction cancelled: %s"
Mail:InvalidateMatchers()

--------------------------------------------------------------------------------
print("")
print("a client with no subject strings still records sales")
--------------------------------------------------------------------------------

Reset()

-- Forever is a beta and may simply not carry these. An invoice marked "seller"
-- is a sale whatever the subject says, so that much survives; an expiry without
-- a subject to read cannot be told from a friend posting you an item, and is
-- deliberately left alone rather than guessed at.
AUCTION_SOLD_MAIL_SUBJECT = nil
AUCTION_EXPIRED_MAIL_SUBJECT = nil
AUCTION_REMOVED_MAIL_SUBJECT = nil
Mail:InvalidateMatchers()

inbox = {
    { sender = "Auction House", subject = "???", money = 285,
      invoice = { invoiceType = "seller", itemName = "Linen Bag", bid = 300, cut = 15 } },
    { sender = "Auction House", subject = "???",
      items = { { itemID = VIAL, count = 1 } } },
}
Mail:Read()

check("the invoice alone is enough for a sale", Mail:GetSummary().sold, 1)
check("the unreadable return is not invented",  Mail:GetSummary().returned, 0)
check("but it is still stock",                  Inventory:GetMailCount(VIAL), 1)

AUCTION_SOLD_MAIL_SUBJECT = "Auction successful: %s"
AUCTION_EXPIRED_MAIL_SUBJECT = "Auction expired: %s"
AUCTION_REMOVED_MAIL_SUBJECT = "Auction cancelled: %s"
Mail:InvalidateMatchers()

--------------------------------------------------------------------------------
print("")
print("which shape of GetInboxItem this client has")
--------------------------------------------------------------------------------

Reset()

-- Two clients exist: (name, itemID, texture, count, ...) and the older
-- (name, texture, count, ...). Both have a number in the second slot, so the
-- returns alone cannot tell them apart -- the item link can, and does.
local itemID, count = Mail:ReadAttachment(1, 1)
check("no mail, no attachment",                 itemID, nil)

inbox = { { sender = "Auction House", subject = "Auction expired: Linen Bag",
            items = { { itemID = LINEN_BAG, count = 7 } } } }

itemID, count = Mail:ReadAttachment(1, 1)
check("the item is read from the link",         itemID, LINEN_BAG)
check("and the count from the right slot",      count, 7)
check("the shape is worked out, not assumed",   Mail.attachmentShape, "itemID second")

-- The older client: texture second, count third.
local newer = GetInboxItem
GetInboxItem = function(index, slot)
    local item = inbox[index] and inbox[index].items[slot]
    if not item then return nil end
    return "Some Item", 133633, item.count, 1, true
end

itemID, count = Mail:ReadAttachment(1, 1)
check("the older shape is spotted",             Mail.attachmentShape, "count third")
check("the item still comes from the link",     itemID, LINEN_BAG)
check("and the count from the third slot",      count, 7)

GetInboxItem = newer

--------------------------------------------------------------------------------
print("")
print("a client with no mailbox API at all")
--------------------------------------------------------------------------------

Reset()

local saved = GetInboxNumItems
GetInboxNumItems = nil

Mail:Read()
check("nothing blows up",                       Inventory:GetMailCount(LINEN_BAG), 0)
check("and no phantom entries",                 #Mail:GetLedger().entries, 0)

GetInboxNumItems = saved

--------------------------------------------------------------------------------
print("")
print("what you already hold pushes a craft down the list")
--------------------------------------------------------------------------------

-- The owner does not want a cap to configure. So holding stock does not hide a
-- craft, it demotes it: the eleventh of something only sells once the other ten
-- have, so the gold comes back that much slower.
ns.Prices = { Count = function() return 0 end }
ns.Cost = {}
ns.Posting = { GetCachedUnitDeposit = function() return 0 end }
ns.Scanner = {}

assert(loadfile(lfs_cwd .. "/Logic/Profit.lua"))("Blackthornes_TS", ns)

local Profit = ns.Profit
local Divisor, RankValue = Profit._StockDivisor, Profit._RankValue

check("holding none changes nothing",           Divisor(0), 1)
check("one already out roughly halves it",      Divisor(1), 2)
check("nine out, a tenth of the place",         Divisor(9), 10)
check("nil is the same as none",                Divisor(nil), 1)

settings.stockPenalty = 0
check("and it can be turned off outright",      Divisor(5), 1)
settings.stockPenalty = 1

settings.stockPenalty = 0.5
check("a gentler setting is gentler",           Divisor(2), 2)
settings.stockPenalty = 1

check("a craft you hold none of keeps its profit",
    RankValue({ profit = 500, stockDivisor = 1 }, "profit"), 500)
check("one you hold three of ranks a quarter as high",
    RankValue({ profit = 500, stockDivisor = 4 }, "profit"), 125)

-- A loss divided by a bigger number gets closer to zero, which would promote
-- the worst crafts in the list purely for being overstocked.
check("a loss is never improved by holding more",
    RankValue({ profit = -200, stockDivisor = 10 }, "profit"), -200)
check("and a missing figure sorts last",
    RankValue({ stockDivisor = 1 }, "profit"), -math.huge)

--------------------------------------------------------------------------------
print("")
print("and that is the order the list comes out in")
--------------------------------------------------------------------------------

-- Analysis is stubbed: the sort is what is under test, not the costing.
local canned = {
    [1] = { name = "Overstocked",  profit = 1000, margin = 0.5, priceable = true,
            stock = 9, pipeline = 9, stockDivisor = 10 },
    [2] = { name = "Fresh",        profit = 400,  margin = 0.4, priceable = true,
            stock = 0, pipeline = 0, stockDivisor = 1 },
    [3] = { name = "One out",      profit = 600,  margin = 0.3, priceable = true,
            stock = 1, pipeline = 1, stockDivisor = 2 },
}

Profit.Analyse = function(_, recipeID) return canned[recipeID] end
ns.Recipes.GetAll = function() return { [1] = true, [2] = true, [3] = true } end

settings.minProfit, settings.minMarginPercent = 0, 0

local ranked = Profit:GetRanked({})

check("the one with none out leads",            ranked[1].name, "Fresh")
check("then the one with a single one out",     ranked[2].name, "One out")
check("the pile of nine is last, at 100 each",  ranked[3].name, "Overstocked")

-- Nothing vanished. That matters: a craft dropping off the list entirely is
-- how a player stops trusting it.
check("and all three are still there",          #ranked, 3)

local raw = Profit:GetRanked({ ignoreStock = true })
check("the raw order is still available",       raw[1].name, "Overstocked")

--------------------------------------------------------------------------------
print("")
print("a sale whose gold is still being held")
--------------------------------------------------------------------------------

-- The bug this is here for, seen in game on 2026-09-19: two Linen Reagent Bags
-- sold and the ledger read "sold Linen Reagent Bag for 0c" against one of them.
-- The auction house holds the gold for a while after a sale, and the mail's own
-- money field reads zero for as long as it does -- but the invoice already
-- knows what the thing went for.
Reset()

inbox = {
    { sender = "Auction House", subject = "Auction successful: Linen Bag",
      money = 0,
      invoice = { invoiceType = "seller", itemName = "Linen Bag",
                  bid = 300, deposit = 40, cut = 15, moneyDelay = 3600 } },
}
Mail:Read()

check("the sale is recorded, not skipped",      Mail:GetSummary().sold, 1)
check("priced from the invoice, not as nothing", Mail:GetSummary().net, 325)
check("and flagged as not yet in the pocket",   Mail:GetSummary().estimated, 1)
check("nothing is waiting once it is priced",   Mail.awaitingAmount, 0)

--------------------------------------------------------------------------------
print("")
print("and the payout landing is not a second sale")
--------------------------------------------------------------------------------

-- This is what made the old code dangerous rather than merely wrong. Money used
-- to be part of a mail's fingerprint, so the same sale looked like a different
-- mail before and after the gold was released, and a second visit to the
-- mailbox wrote it down again. The ledger inflated every time you looked at it.
inbox[1].money = 325
Mail:Read()

check("still one sale",                         Mail:GetSummary().sold, 1)
check("and still one lot of gold",              Mail:GetSummary().net, 325)

Mail:Read()
Mail:Read()
check("however many times you look",            Mail:GetSummary().sold, 1)

--------------------------------------------------------------------------------
print("")
print("two sales of one item, paid out at different times")
--------------------------------------------------------------------------------

-- Exactly the owner's case: two of the same bag sold, one paid, one still held.
-- These share a fingerprint deliberately, so each has to be described from its
-- own mail. Describing both from whichever was walked first is how one of them
-- would end up wearing the other's figure.
Reset()

inbox = {
    { sender = "Auction House", subject = "Auction successful: Linen Bag",
      money = 800,
      invoice = { invoiceType = "seller", itemName = "Linen Bag", bid = 800 } },
    { sender = "Auction House", subject = "Auction successful: Linen Bag",
      money = 0,
      invoice = { invoiceType = "seller", itemName = "Linen Bag",
                  bid = 300, deposit = 40, cut = 15, moneyDelay = 3600 } },
}
Mail:Read()

check("both sales are there",                   Mail:GetSummary().sold, 2)
check("each carries its own figure",            Mail:GetSummary().net, 1125)
check("one of them is still being paid",        Mail:GetSummary().estimated, 1)

local amounts = {}
for _, entry in ipairs(Mail:GetRecent(10)) do amounts[entry.net] = true end
check("the paid one kept its amount",           amounts[800], true)
check("and the held one kept its own",          amounts[325], true)

-- Looking again. The paid mail is re-read every time, and it once settled the
-- held sale with its own 800c because the two share an item name.
Mail:Read()
check("a second look leaves the held one alone", Mail:GetSummary().net, 1125)
check("and it is still being paid",             Mail:GetSummary().estimated, 1)

inbox[2].money = 325
Mail:Read()
check("its own gold settles it",                Mail:GetSummary().estimated, 0)
check("at its own amount",                      Mail:GetSummary().net, 1125)

--------------------------------------------------------------------------------
print("")
print("a sale nothing can price yet waits rather than reading as free")
--------------------------------------------------------------------------------

Reset()

-- No money and no invoice. A zero here is not a fact about the sale, it is the
-- absence of one, and "sold for 0c" in the ledger is worse than a sale that
-- shows up a minute later.
inbox = {
    { sender = "Auction House", subject = "Auction successful: Linen Bag", money = 0 },
}
Mail:Read()

check("nothing invented",                       Mail:GetSummary().sold, 0)
check("and it says it is waiting",              Mail.awaitingAmount, 1)

inbox[1].money = 285
Mail:Read()

check("recorded once it can be priced",         Mail:GetSummary().sold, 1)
check("at the real amount",                     Mail:GetSummary().net, 285)
check("and nothing waiting any more",           Mail.awaitingAmount, 0)

Mail:Read()
check("and not again on the next look",         Mail:GetSummary().sold, 1)

--------------------------------------------------------------------------------
print("")
print("throwing the ledger away")
--------------------------------------------------------------------------------

-- The owner's ledger carried rows written before the payout fix, reading "sold
-- Linen Reagent Bag for 0c". Entries are never rewritten, so the only way to be
-- rid of them is to clear the lot and start again.
Reset()

inbox = {
    { sender = "Auction House", subject = "Auction successful: Linen Bag",
      money = 285,
      invoice = { invoiceType = "seller", itemName = "Linen Bag", bid = 300 } },
    { sender = "Auction House", subject = "Auction expired: Crystal Vial",
      items = { { itemID = VIAL, count = 1 } } },
}
Mail:Read()

check("two entries to start with",              #Mail:GetLedger().entries, 2)

-- A row with no gold on it cannot be written by the current code at all: a sale
-- is priced from the invoice when the header is still zero, and one nothing can
-- price is deferred. So a zero row is always history.
check("and none of them looks unpriced",        Mail:CountUnpriced(), 0)

table.insert(Mail:GetLedger().entries,
    { t = 1, kind = "sold", name = "Linen Reagent Bag", net = 0 })
check("an old zero row is spotted",             Mail:CountUnpriced(), 1)

check("clearing says how much it threw away",   Mail:ResetLedger(), 3)
check("the entries are gone",                   #Mail:GetLedger().entries, 0)
check("and so is the summary",                  Mail:GetSummary().sold, 0)

-- The record of what has already been written down goes with them, or the mail
-- still sitting in the box would never be recorded again.
Mail:Read()

check("what is still there is recorded afresh", #Mail:GetLedger().entries, 2)
check("with its gold intact",                   Mail:GetSummary().net, 285)

Mail:Read()
check("and still not twice",                    #Mail:GetLedger().entries, 2)

--------------------------------------------------------------------------------
print("")
print("a cancelled listing is not a failure to sell")
--------------------------------------------------------------------------------

-- The owner cancelled nine listings to test something, and the sell-through number
-- counted them as nine the market had turned down. Pulling a listing yourself
-- is not the market's verdict, so cancellations are counted and shown but kept
-- out of the ratio.

Reset()

inbox = {
    { sender = "Auction House", subject = "Auction successful: Linen Bag",
      money = 285,
      invoice = { invoiceType = "seller", itemName = "Linen Bag",
                  bid = 300, buyout = 300, deposit = 40, cut = 15 } },
    { sender = "Auction House", subject = "Auction cancelled: Linen Bag",
      items = { { itemID = LINEN_BAG, count = 1 } } },
    { sender = "Auction House", subject = "Auction cancelled: Linen Bag",
      items = { { itemID = LINEN_BAG, count = 1 } } },
    { sender = "Auction House", subject = "Auction cancelled: Linen Bag",
      items = { { itemID = LINEN_BAG, count = 1 } } },
}
Mail:Read()

local pulled = Mail:GetSummary(LINEN_BAG)
check("all four ends are on the books",         pulled.sold + pulled.returned, 4)
check("three came back",                        pulled.returned, 3)
check("all three as cancellations",             pulled.cancelled, 3)
check("none of them as an expiry",              pulled.expired, 0)
check("so the one sale is the whole story",     pulled.sellThrough, 1)

-- With nothing but cancellations there is no ratio to report at all, rather
-- than a 0% that reads as a pricing problem.
Reset()

inbox = {
    { sender = "Auction House", subject = "Auction cancelled: Linen Bag",
      items = { { itemID = LINEN_BAG, count = 1 } } },
    { sender = "Auction House", subject = "Auction cancelled: Crystal Vial",
      items = { { itemID = VIAL, count = 1 } } },
}
Mail:Read()

local onlyPulled = Mail:GetSummary()
check("both cancellations are recorded",        onlyPulled.cancelled, 2)
check("and no sell-through is claimed",         onlyPulled.sellThrough, nil)

-- An expiry alongside them does give a ratio, over the expiry alone.
inbox[#inbox + 1] = {
    sender = "Auction House", subject = "Auction expired: Linen Bag",
    items = { { itemID = LINEN_BAG, count = 1 } },
}
Mail:Read()

local withExpiry = Mail:GetSummary()
check("the expiry is told apart from them",     withExpiry.expired, 1)
check("they still are not in the ratio",        withExpiry.sellThrough, 0)

--------------------------------------------------------------------------------
print("")
print("a mailbox shut before the server answered")
--------------------------------------------------------------------------------

-- Bump a mailbox and press Escape: the delayed read finds nothing listed.
-- It used to take that as an empty box and forget every mail on record, so
-- the next real visit wrote each one down again.
Reset()
inbox = {
    { sender = "Auction House", subject = "Auction successful: Linen Bag",
      money = 285, invoice = { invoiceType = "seller", itemName = "Linen Bag", bid = 300 } },
}
Mail:Read()
check("the sale is recorded once",              Mail:GetSummary().sold, 1)

local held = inbox
inbox = {}
Mail.inboxUpdatedThisVisit = false
Mail:Read()

inbox = held
Mail.inboxUpdatedThisVisit = true
Mail:Read()
check("and not again on the next visit",        Mail:GetSummary().sold, 1)

--------------------------------------------------------------------------------
print("")
print("sales and expiries of an uncrafted item share one row")
--------------------------------------------------------------------------------

-- Cloth sold from the whole-bag Post tab: the sale mail names it but has no
-- item, and no recipe makes it, so the sale had no id. Its expiry has one.
-- The Sales tab showed them as two items, each with the wrong sell-through.
Reset()
inbox = {
    { sender = "Auction House", subject = "Auction successful: Linen Cloth",
      money = 90, invoice = { invoiceType = "seller", itemName = "Linen Cloth", bid = 100 } },
    { sender = "Auction House", subject = "Auction expired: Linen Cloth",
      items = { { itemID = CLOTH, count = 20 } } },
}
Mail:Read()

local clothRows = 0
for _, bucket in ipairs(Mail:GetItems()) do
    if bucket.name == "Linen Cloth" or bucket.itemID == CLOTH then clothRows = clothRows + 1 end
end
check("one row for the cloth",                  clothRows, 1)
check("its summary counts the sale too",        Mail:GetSummary(CLOTH).sold, 1)

--------------------------------------------------------------------------------
print("")
print("two characters with the same kind of mail")
--------------------------------------------------------------------------------

-- The list of mails already written down was shared by every character on
-- the realm, and a fingerprint does not say whose mailbox it is in. The alt's
-- identical sale read as already seen and was never written down.
Reset()
local whoIsOn = "Main-Testrealm"
ns.Config.GetCharacterKey = function() return whoIsOn end

inbox = { SoldBag() }
Mail:Read()
check("the main's sale is written down",        #Mail:GetLedger().entries, 1)

whoIsOn = "Alt-Testrealm"
inbox = { SoldBag() }
Mail:Read()
check("the alt's identical sale is too",        #Mail:GetLedger().entries, 2)

-- And the alt's complete reading no longer wipes the main's list, so the
-- main's sale still in its box is not written down a second time.
whoIsOn = "Main-Testrealm"
inbox = { SoldBag() }
Mail:Read()
check("going back to the main adds nothing",    #Mail:GetLedger().entries, 2)

-- Saved before the lists were per character: a sale the main wrote down,
-- missing from the old shared list because another character read last.
Reset()
ns.db.mailLedger["Testrealm-Alliance"] = {
    entries = { { t = 1, kind = "sold", who = "Main-Testrealm", name = "Linen Bag", net = 285 } },
    seen = {},
}
inbox = { SoldBag() }
Mail:Read()
check("the switch does not write it down twice", #Mail:GetLedger().entries, 1)

ns.Config.GetCharacterKey = function() return "Tester-Testrealm" end

--------------------------------------------------------------------------------

print("")
print("a returned listing in several stacks is written down once")
--------------------------------------------------------------------------------

Reset()

local function ExpiredCloth(stacks)
    local items = {}
    for i = 1, stacks do items[i] = { itemID = CLOTH, count = 20 } end
    return { sender = "Auction House", subject = "Auction expired: Linen Cloth", items = items }
end

inbox = { ExpiredCloth(3) }
Mail:Read()
check("the expiry is written down",             #Mail:GetLedger().entries, 1)
check("with all three stacks",                  Mail:GetLedger().entries[1].quantity, 60)

-- Take the stacks one at a time.
inbox = { ExpiredCloth(2) }
Tick()
Mail:Read()
check("taking a stack writes nothing new",      #Mail:GetLedger().entries, 1)

inbox = { ExpiredCloth(1) }
Tick()
Mail:Read()
check("nor does taking the next one",           #Mail:GetLedger().entries, 1)
check("still one expiry",                       Mail:GetSummary().expired, 1)

-- A fresh return of the same item later is a new expiry.
inbox = {}
Tick()
Mail:Read()
inbox = { ExpiredCloth(2) }
Tick()
Mail:Read()
check("a new return after that is new",         Mail:GetSummary().expired, 2)

print("")
print("a heard sale is not swept while the box holds mail back")
--------------------------------------------------------------------------------

-- The box shows 50 at most. With more on the server, a sale's mail can be in
-- the part not shown yet, so not seeing it says nothing about it.
Reset()
Mail.awaitingAmount = 0
ns.db.heardSales = { ["Testrealm-Alliance"] = {
    { t = time() - 3 * 3600, name = "Runecloth", who = "Tester-Testrealm" },
} }

local shown = GetInboxNumItems
GetInboxNumItems = function() return #inbox, #inbox + 12 end
inbox = { ExpiredCloth(1) }
Mail:Read()
check("more mail on the server: still waiting",  ns.db.heardSales["Testrealm-Alliance"][1].collected, nil)

GetInboxNumItems = function() return #inbox, #inbox end
Tick()
Mail:Read()
check("every mail shown: it stops waiting",      ns.db.heardSales["Testrealm-Alliance"][1].collected ~= nil, true)
check("and is kept",                             #ns.db.heardSales["Testrealm-Alliance"], 1)

GetInboxNumItems = shown
ns.db.heardSales = nil

print("")
print("inbox events in a burst")

-- Taking mail fires one or more inbox events a mail, and each used to walk
-- the whole box and redraw the open tab.
local handlers = {}
ns.RegisterEvent = function(_, event, fn) handlers[event] = fn return true end
local due
C_Timer.NewTimer = function(_, fn) due = fn return { Cancel = function() due = nil end } end
Mail:OnEnable()
local reads = 0
local realRead = Mail.Read
Mail.Read = function(self) reads = reads + 1 end
handlers.MAIL_INBOX_UPDATE(nil, "MAIL_INBOX_UPDATE")
handlers.MAIL_INBOX_UPDATE(nil, "MAIL_INBOX_UPDATE")
handlers.MAIL_INBOX_UPDATE(nil, "MAIL_INBOX_UPDATE")
check("three events, no read yet",               reads, 0)
local fn = due
due = nil
fn()
check("one read once they stop",                 reads, 1)
handlers.MAIL_INBOX_UPDATE(nil, "MAIL_INBOX_UPDATE")
handlers.MAIL_CLOSED(nil, "MAIL_CLOSED")
check("a read still waiting is taken as the box shuts", reads, 2)
check("and nothing waits after",                 due, nil)
Mail.Read = realRead
C_Timer.NewTimer = function() return { Cancel = function() end } end

print("")
print("a sale filed by name learns its item after a new recipe")

check("a craft the addon has not seen is not an output", Mail:OutputSet()[9999], nil)
local realWide = ns.Recipes.GetAccountWide
ns.Recipes.GetAccountWide = function() return { [3] = { outputItemID = 9999 } } end
check("the set is kept for the session",         Mail:OutputSet()[9999], nil)
Mail:ForgetOutputSet()
check("until recipes are added",                 Mail:OutputSet()[9999], true)
ns.Recipes.GetAccountWide = realWide
Mail:ForgetOutputSet()

print("")
if failures > 0 then
    error(("%d check(s) failed"):format(failures), 0)
end
print("all mailbox checks passed")
