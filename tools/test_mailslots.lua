-- The mailbox after the player has been at it: mail half taken, mail
-- emptied, and the box read before the server has listed anything.
--
-- Four things that went wrong, each with the ledger or the stock count:
-- a mail's attachments keep their slot numbers after a partial take, so a
-- walk of the first N slots missed the rest and called the mail "still
-- loading" for ever; an emptied "Auction expired" mail lingers for an update
-- and, with no attachment, fingerprinted as a new mail and was recorded a
-- second time; an inbox read before the server answered was trusted as empty
-- and forgot every recorded mail, so each was recorded again a moment later;
-- and an item name the client had not cached yet was remembered as "no such
-- item" for the rest of the session.

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
    Mail.isOpen = false
    Mail.inboxUpdatedThisVisit = nil
    Tick()
end

--------------------------------------------------------------------------------
print("")
print("a mail with one of three stacks already taken")
--------------------------------------------------------------------------------

Reset()

-- Slots 2 and 3 are left; the header says two items.
inbox = {
    { sender = "Tester", subject = "cloth",
      items = { [2] = { itemID = CLOTH, count = 20 }, [3] = { itemID = CLOTH, count = 20 } },
      declared = 2 },
}
Mail:Read()

check("both stacks left are counted",           Inventory:GetMailCount(CLOTH), 40)
check("and the mail is not called still loading", Mail.lastComplete, true)

--------------------------------------------------------------------------------
print("")
print("an expired auction whose item has just been taken")
--------------------------------------------------------------------------------

Reset()

inbox = {
    { sender = "Auction House", subject = "Auction expired: Linen Bag",
      items = { { itemID = LINEN_BAG, count = 1 } } },
}
Mail:Read()
check("the expiry is written down once",        Mail:GetSummary().expired, 1)

-- The item is taken. The emptied mail is still listed for an update.
inbox[1].items = {}
Mail:Read()
check("taking the item does not write it again", Mail:GetSummary().expired, 1)
check("and the item has left the mailbox",      Inventory:GetMailCount(LINEN_BAG), 0)

--------------------------------------------------------------------------------
print("")
print("the mailbox read before the server has listed anything")
--------------------------------------------------------------------------------

Reset()

inbox = {
    { sender = "Auction House", subject = "Auction successful: Crystal Vial",
      money = 500, invoice = { itemName = "Crystal Vial", bid = 500, deposit = 0, cut = 25 } },
}
Mail.isOpen = true
Mail.inboxUpdatedThisVisit = true
Mail:Read()
check("a sale still in the box is recorded",    Mail:GetSummary().sold, 1)

-- Next visit: the frame opens, the timed read runs, the list is still empty.
local full = inbox
inbox = {}
Mail.inboxUpdatedThisVisit = false
Mail:Read()
check("an empty list before the inbox arrives changes nothing", Mail:GetSummary().sold, 1)

-- The inbox arrives, with the same uncollected mail in it.
inbox = full
Mail.inboxUpdatedThisVisit = true
Mail:Read()
check("so the sale is not recorded a second time", Mail:GetSummary().sold, 1)

-- Whereas a genuinely empty inbox, once listed, is believed.
inbox = {}
Mail:Read()
check("an empty inbox once listed is believed",  Mail.lastComplete, true)

--------------------------------------------------------------------------------
print("")
print("a sold item whose name the client had not cached")
--------------------------------------------------------------------------------

Reset()

local vialName = itemNames[VIAL]
itemNames[VIAL] = nil
check("the name cannot be resolved yet",        Mail:ResolveItemName("Crystal Vial"), nil)
itemNames[VIAL] = vialName
check("and is resolved once the client has it", Mail:ResolveItemName("Crystal Vial"), VIAL)

--------------------------------------------------------------------------------

print("")
if failures > 0 then
    error(("%d check(s) failed"):format(failures), 0)
end
print("all mailbox slot checks passed")
