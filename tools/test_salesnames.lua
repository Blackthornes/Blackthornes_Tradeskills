-- Sales of things you don't craft showed as plain white names with no icon,
-- and By item split each one into two rows: the sales under a name only, the
-- expired and cancelled stacks under the item. Sell-through on both was
-- wrong. A stack's mail names it with its count ("Silk Cloth (20)") and the
-- sale's invoice may not, so the two never matched; and a sale was given its
-- item only when it was a crafted one. Reported on Large Glimmering Shard,
-- Silk Cloth, Wool Cloth, Tin Bar and Rage Potion.

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
local SHARD, SILK, TIN = 11084, 4306, 3576

local itemNames = {
    [LINEN_BAG] = "Linen Bag",
    [CLOTH] = "Linen Cloth",
    [VIAL] = "Crystal Vial",
    [SHARD] = "Large Glimmering Shard",
    [SILK] = "Silk Cloth",
    [TIN] = "Tin Bar",
}

-- The game knows an item by name once it is in its item cache.
local cachedByName = {}

C_Item = {
    GetItemCount = function() return 0 end,
    GetItemInfo = function(item)
        if type(item) == "number" then return itemNames[item] end
        local itemID = cachedByName[item]
        if not itemID then return nil end
        return item, ("|cffffffff|Hitem:%d::::::::::|h[%s]|h|r"):format(itemID, item)
    end,
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
print("a stack's sale and its expiry land on one row")
--------------------------------------------------------------------------------

Reset()
inbox = {
    { sender = "Auction House", subject = "Auction successful: Large Glimmering Shard (5)",
      money = 5000, invoice = { itemName = "Large Glimmering Shard (5)", bid = 5250, deposit = 0, cut = 250 } },
    { sender = "Auction House", subject = "Auction expired: Large Glimmering Shard",
      items = { { itemID = SHARD, count = 5 } } },
}
Mail.isOpen = true
Mail.inboxUpdatedThisVisit = true
Mail:Read()

local rows = Mail:GetItems()
check("one row for the shard",                    #rows, 1)
check("filed under the item",                     rows[1] and rows[1].itemID, SHARD)
check("with its sale",                            rows[1] and rows[1].sold, 1)
check("and its expiry",                           rows[1] and rows[1].expired, 1)
local sale
for _, entry in ipairs(Mail:GetLedger().entries) do
    if entry.kind == "sold" then sale = entry end
end
check("the sale now knows its item",              sale.itemID, SHARD)
check("and keeps the name it was written with",   sale.name, "Large Glimmering Shard (5)")
check("and its gold",                             sale.net, 5000)

--------------------------------------------------------------------------------
print("")
print("the other way round: the return names the stack")
--------------------------------------------------------------------------------

Reset()
inbox = {
    { sender = "Auction House", subject = "Auction successful: Silk Cloth",
      money = 900, invoice = { itemName = "Silk Cloth", bid = 950, deposit = 0, cut = 50 } },
    { sender = "Auction House", subject = "Auction cancelled: Silk Cloth (20)",
      items = { { itemID = SILK, count = 20 } } },
}
Mail.isOpen = true
Mail.inboxUpdatedThisVisit = true
Mail:Read()

rows = Mail:GetItems()
check("one row for the cloth",                    #rows, 1)
check("filed under the item",                     rows[1] and rows[1].itemID, SILK)
check("with its sale and its cancel",             rows[1] and (rows[1].sold .. "/" .. rows[1].cancelled), "1/1")

--------------------------------------------------------------------------------
print("")
print("a sale that never came back gets its item from the game")
--------------------------------------------------------------------------------

Reset()
cachedByName["Tin Bar"] = TIN
inbox = {
    { sender = "Auction House", subject = "Auction successful: Tin Bar (10)",
      money = 300, invoice = { itemName = "Tin Bar (10)", bid = 320, deposit = 0, cut = 20 } },
}
Mail.isOpen = true
Mail.inboxUpdatedThisVisit = true
Mail:Read()
check("filed under the item",                     Mail:GetLedger().entries[1].itemID, TIN)
cachedByName["Tin Bar"] = nil

--------------------------------------------------------------------------------
print("")
print("sales saved by name only before are folded in")
--------------------------------------------------------------------------------

Reset()
Mail.isOpen = false
local ledger = Mail:GetLedger()
ledger.entries = {
    { t = 100, kind = "sold", name = "Silk Cloth (20)", net = 800, who = "x" },
    { t = 110, kind = "sold", name = "Mystery Thing", net = 50, who = "x" },
    { t = 120, kind = "expired", name = "Silk Cloth", itemID = SILK, quantity = 20, who = "x" },
    { t = 130, kind = "sold", name = "Tin Bar", net = 30, who = "x" },
}
-- The index answers a stack's name even before the fold.
check("the index knows a stack by its plain name", Mail:NameIndex()["Silk Cloth (20)"], SILK)

cachedByName["Tin Bar"] = TIN
local filled = Mail:FoldNamedSales()
check("two old sales get their item",              filled, 2)
check("the cloth from its expiry",                 ledger.entries[1].itemID, SILK)
check("the bar from the game",                     ledger.entries[4].itemID, TIN)
check("a name nothing knows is left as it was",    ledger.entries[2].itemID, nil)
check("nothing is removed",                        #ledger.entries, 4)
check("and the gold is untouched",                 ledger.entries[1].net, 800)
check("a second fold changes nothing",             Mail:FoldNamedSales(), 0)
rows = Mail:GetItems()
check("three rows: cloth, mystery, bar",           #rows, 3)

--------------------------------------------------------------------------------
print("")
print("a sale filed by name gets its item when the game loads it, crafted or not")
--------------------------------------------------------------------------------

Reset()
cachedByName = {}
itemNames[SHARD] = nil
inbox = {
    { sender = "Auction House", subject = "Auction successful: Large Glimmering Shard (2)",
      money = 500, invoice = { itemName = "Large Glimmering Shard (2)", bid = 500, deposit = 0, cut = 25 } },
}
Mail.isOpen = true
Mail.inboxUpdatedThisVisit = true
Mail:Read()
local nameOnly = Mail:GetLedger().entries[1]
check("filed by name while the item is not loaded", nameOnly and nameOnly.itemID, nil)
itemNames[SHARD] = "Large Glimmering Shard"
Mail:FillItemID(SHARD)
check("the game loading it fills in the item",    nameOnly.itemID, SHARD)
Mail.isOpen = false

--------------------------------------------------------------------------------

print("")
if failures > 0 then
    error(("%d check(s) failed"):format(failures), 0)
end
print("all sales name checks passed")
