-- Mail sent back at the mailbox, and the report's rows fitting their room.
--
-- Return sends a letter back with its gold and items still on it. The visit
-- read the letter leaving the box as collected: "Mail collected: 100g" for
-- gold that never reached the purse, a COD parcel's items listed as taken,
-- and a haul saved to the history that set records and swelled the day's
-- and week's totals.
--
-- And the report: the Items row cut its names off with "...", losing the
-- "3 more" at the end; the BEST EVER tag squeezed the best sale's name; a
-- stack's sale ("Linen Cloth (20)") found no item for its icon and colour.

local GLOBALS = { "GetMoney", "time", "date", "GetTime", "GetInboxNumItems", "GetInboxHeaderInfo",
    "GetInboxItem", "GetInboxItemLink", "GetInboxInvoiceInfo", "ATTACHMENTS_MAX_RECEIVE",
    "AUCTION_SOLD_MAIL_SUBJECT", "AUCTION_EXPIRED_MAIL_SUBJECT", "AUCTION_REMOVED_MAIL_SUBJECT",
    "AUCTION_WON_MAIL_SUBJECT", "AUCTION_OUTBID_MAIL_SUBJECT", "C_Item", "C_Timer", "CreateFrame",
    "UIParent", "UISpecialFrames", "tinsert", "GameTooltip", "PlaySoundFile", "PlaySound",
    "hooksecurefunc", "ReturnInboxItem", "InboxItemCanDelete", "MailFrame" }
local saved = {}
for _, key in ipairs(GLOBALS) do saved[key] = _G[key] end

local function noop() end

local ns = {}
ns.COLORS = setmetatable({}, { __index = function() return "ffffffff" end })
ns.NewModule = function(name) local m = {}; ns[name] = m; return m end
ns.RegisterCommand = noop
ns.RegisterEvent = function() return true end
ns.Debug, ns.Warn = noop, noop

local printed = {}
ns.Print = function(text) printed[#printed + 1] = tostring(text) end
ns.PrintRaw = ns.Print

local now = 1790000000
time = function() return now end
date = os.date
GetTime = function() return now end

local purse = 1000000
GetMoney = function() return purse end

--------------------------------------------------------------------------------
-- A mailbox
--------------------------------------------------------------------------------

local inbox = {}

ATTACHMENTS_MAX_RECEIVE = 16

GetInboxNumItems = function() return #inbox end

GetInboxHeaderInfo = function(index)
    local mail = inbox[index]
    if not mail then return nil end
    return nil, nil, mail.sender, mail.subject, mail.money or 0, mail.cod or 0,
        mail.daysLeft or 27.5, #(mail.items or {})
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
    return "seller", i.itemName, "Buyer", i.bid, i.bid, 0, 0, 0
end

AUCTION_SOLD_MAIL_SUBJECT = "Auction successful: %s"
AUCTION_EXPIRED_MAIL_SUBJECT = "Auction expired: %s"
AUCTION_REMOVED_MAIL_SUBJECT = "Auction cancelled: %s"
AUCTION_WON_MAIL_SUBJECT = "Auction won: %s"
AUCTION_OUTBID_MAIL_SUBJECT = "Outbid on %s"

-- Return, as the game has it: the request goes off, and the mail leaves the
-- list only when the server answers. Auction house mail cannot go back.
local sentBack = {}
ReturnInboxItem = function(index) sentBack[#sentBack + 1] = index end
InboxItemCanDelete = function(index)
    return inbox[index] ~= nil and inbox[index].sender == "Auction House"
end

-- Watching without replacing: the game's hooksecurefunc, as far as this goes.
hooksecurefunc = function(name, hook)
    local original = _G[name]
    _G[name] = function(...)
        original(...)
        hook(...)
    end
end

local CLOTH, WOOL, BAG, BRACER, GLOVES, VIAL, SHIRT =
    2589, 2592, 4238, 11202, 4310, 3371, 2575
local names = {
    [CLOTH] = "Linen Cloth", [WOOL] = "Wool Cloth", [BAG] = "Linen Bag",
    [BRACER] = "Formula: Enchant Bracer - Superior Stamina", [GLOVES] = "Heavy Linen Gloves",
    [VIAL] = "Crystal Vial", [SHIRT] = "Brown Linen Shirt",
}

C_Item = { GetItemInfo = function(itemID)
    local name = names[itemID]
    if not name then return nil end
    return name, ("|cffffffff|Hitem:%d::::|h[%s]|h|r"):format(itemID, name), 1
end }
C_Timer = { After = noop }

--------------------------------------------------------------------------------
-- A screen whose text has a width
--------------------------------------------------------------------------------

--- Text as it shows on screen, without colour or link codes.
local function Plain(text)
    return (tostring(text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|H.-|h(.-)|h", "%1"))
end

local frames = {}

local function Region()
    local region = { shown = false, scripts = {}, alpha = 1, width = 0, height = 0, size = 12, wrap = true }
    region.Show = function(self) self.shown = true end
    region.Hide = function(self)
        self.shown = false
        if self.scripts.OnHide then self.scripts.OnHide(self) end
    end
    region.IsShown = function(self) return self.shown end
    region.SetShown = function(self, on) self.shown = on and true or false end
    region.SetText = function(self, text) self.text = text end
    region.GetText = function(self) return self.text end
    region.SetAlpha = function(self, a) self.alpha = a end
    region.SetHeight = function(self, h) self.height = h end
    region.GetHeight = function(self) return self.height end
    region.GetWidth = function(self) return self.width end
    region.SetWidth = function(self, w) self.width = w end
    region.SetScript = function(self, name, fn) self.scripts[name] = fn end
    region.CreateTexture = function() return Region() end
    region.CreateFontString = function() return Region() end
    region.SetFont = function(self, _, size) self.size = size end
    region.SetWordWrap = function(self, on) self.wrap = on and true or false end
    -- Half the font size a letter, on one line however long.
    region.GetStringWidth = function(self) return #Plain(self.text) * self.size * 0.5 end
    region.GetStringHeight = function(self)
        local lines = 1
        if self.wrap and self.width > 0 then
            lines = math.max(1, math.ceil(self:GetStringWidth() / self.width))
        end
        return lines * (self.size + 2)
    end
    return setmetatable(region, { __index = function() return noop end })
end

CreateFrame = function()
    local frame = Region()
    frames[#frames + 1] = frame
    return frame
end
UIParent = Region()
UISpecialFrames = {}
tinsert = table.insert
GameTooltip = Region()
PlaySoundFile = function() return true end
PlaySound = function() return true end
MailFrame = nil

--------------------------------------------------------------------------------
-- The addon around it
--------------------------------------------------------------------------------

local settings = { mailReport = true }
local record = {}

ns.db = { mailLedger = {} }
ns.Config = {
    Get = function(_, key) return settings[key] end,
    GetRealmKey = function() return "Testrealm-Alliance" end,
    GetCharacterKey = function() return "Player-1-0001" end,
}
ns.Recipes = {
    GetCharacterRecord = function() return record end,
    GetAll = function() return {} end,
    GetAccountWide = function() return { [1] = { outputItemID = BAG } } end,
}
ns.Prices = { GetValue = function() return nil end }

for _, path in ipairs({ "Core/Util.lua", "UI/Theme.lua", "UI/Widgets.lua", "Logic/Banks.lua",
    "Data/Mail.lua", "Logic/MailHaul.lua", "UI/MailReport.lua" }) do
    assert(loadfile(lfs_cwd .. "/" .. path))("Blackthornes_TS", ns)
end

local Mail, MailHaul, MailReport = ns.Mail, ns.MailHaul, ns.MailReport

MailHaul:OnEnable()

local passed, failed = 0, 0
local function check(label, got, expected)
    local ok = got == expected
    if ok then passed = passed + 1 else failed = failed + 1 end
    print(("  %-56s %-12s %s"):format(label, tostring(got), ok and "ok" or
        ("FAILED, expected " .. tostring(expected))))
end

local function Open()
    Mail.isOpen = true
    Mail.inboxUpdatedThisVisit = true
    MailHaul:BeginVisit()
    MailReport:OnMailboxOpened()
    Mail:Read()
end

local function Close()
    Mail.isOpen = false
    MailReport:OnMailboxClosed()
    if MailHaul.visit then return MailHaul:EndVisit() end
end

--- What the game does after Return: the mail goes when the server answers.
local function SendBack(index)
    ReturnInboxItem(index)
    table.remove(inbox, index)
    Mail:Read()
end

local function Take(index, gold)
    purse = purse + (gold or 0)
    table.remove(inbox, index)
    Mail:Read()
end

local function Sold(name, money)
    return { sender = "Auction House", subject = "Auction successful: " .. name, money = money,
        invoice = { itemName = name, bid = money } }
end

--------------------------------------------------------------------------------
print("")
print("a letter sent back with Return is not mail collected")
--------------------------------------------------------------------------------

check("Return is watched",                             MailHaul.watchingReturns, true)

local historyBefore = #MailHaul:GetHistory()
inbox = {
    Sold("Linen Bag", 5000),
    { sender = "Guildmate", subject = "for the raid", money = 1000000 },
}
Open()
SendBack(2)
check("the game was asked to send it back",            sentBack[1], 2)
check("its gold is not counted",                       MailHaul:Current().total, 0)
check("nor the letter",                                MailHaul:Current().letters, 0)
check("walking away makes no haul",                    Close(), nil)
check("and saves nothing",                             #MailHaul:GetHistory(), historyBefore)

-- A parcel asking for payment, sent back rather than paid for.
inbox = { { sender = "Trader", subject = "cloth", cod = 5000, items = { { itemID = CLOTH, count = 20 } } } }
Open()
SendBack(1)
check("its items are not counted",                     MailHaul:Current().items.other, nil)
check("so walking away makes no haul either",          Close(), nil)

-- One letter taken, another sent back, in the same visit.
inbox = {
    { sender = "Alt", subject = "gold", money = 20000 },
    { sender = "Guildmate", subject = "for the raid", money = 1000000 },
}
Open()
SendBack(2)
Take(1, 20000)
local mixed = Close()
check("only the gold taken is counted",                mixed and mixed.total, 20000)
check("from one letter",                               mixed and mixed.letters, 1)

--------------------------------------------------------------------------------
print("")
print("what is not known to be going back is left alone")
--------------------------------------------------------------------------------

-- Auction house mail cannot be sent back, so a call for it changes nothing.
inbox = { Sold("Linen Bag", 7000) }
Open()
ReturnInboxItem(1)
Take(1, 7000)
check("a sale is still collected",                     MailHaul:Current().total, 7000)
Close()

-- A list that has changed since the last reading, or an index with no mail.
inbox = { { sender = "Alt", subject = "gold", money = 3000 } }
Open()
table.insert(inbox, 1, { sender = "Other", subject = "new", money = 500 })
ReturnInboxItem(2)
ReturnInboxItem(9)
Mail:Read()
Take(2, 3000)
check("the letter taken still counts",                 MailHaul:Current().total, 3000)
Close()

-- The purse is the truth even when nothing watched the letter go.
inbox = { { sender = "Guildmate", subject = "for the raid", money = 50000 } }
Open()
table.remove(inbox, 1)
Mail:Read()
check("gold that never reached the purse is not counted", MailHaul:Current().total, 0)
Close()

--------------------------------------------------------------------------------
print("")
print("a stack's sale finds its item")
--------------------------------------------------------------------------------

local ledger = Mail:GetLedger()
ledger.entries[#ledger.entries + 1] = { t = 1, kind = "sold", name = "Linen Cloth", itemID = CLOTH, net = 1 }

inbox = { Sold("Linen Cloth (20)", 900) }
Open()
Take(1, 900)
local stack = Close()
check("named with its size, found by the item",        stack and stack.best.itemID, CLOTH)

--------------------------------------------------------------------------------
print("")
print("the report's rows fit")
--------------------------------------------------------------------------------

local function Row(predicate)
    for _, row in ipairs(MailReport.frame.rows) do
        if row.shown and predicate(row) then return row end
    end
end

-- Five kinds of item from letters, the first two with long names.
local haul = {
    t = now, who = "Player-1-0001", total = 90000, gold = { sold = 90000, outbid = 0, other = 0 },
    salesCount = 2, recordSale = true,
    sales = {
        { name = "Formula: Enchant Bracer - Superior Stamina", amount = 90000, itemID = BRACER },
        { name = "Linen Cloth (20)", amount = 900, itemID = CLOTH },
    },
    items = { other = {
        { itemID = GLOVES, count = 1 }, { itemID = CLOTH, count = 20 }, { itemID = WOOL, count = 5 },
        { itemID = VIAL, count = 2 }, { itemID = SHIRT, count = 1 },
    } },
    itemCount = 29,
}
haul.best = haul.sales[1]
MailReport:Show(haul)

local items = Row(function(row) return Plain(row.label.text):find("Items from letters", 1, true) end)
local itemsText = items and Plain(items.value.text) or ""
check("the items row says how many more",              itemsText:match("(%d+ more)$") ~= nil, true)
check("and fits its room",                             items and items.value:GetStringWidth() <= items.value.width, true)
check("on one line",                                   items and items.value.wrap, false)

local heading = Row(function(row) return Plain(row.label.text) == "BEST SALE" end)
check("BEST EVER sits on the heading",                 heading and heading.tag.shown and Plain(heading.tag.text), "BEST EVER")

local best = Row(function(row) return Plain(row.label.text):find("Formula", 1, true) end)
check("not on the best sale's row",                    best and best.tag.shown, false)
check("whose long name takes a second line",           best and best.label.wrap, true)
check("in a row tall enough for it",                   best and best.height > 24, true)

local cloth = Row(function(row) return Plain(row.label.text):find("[Linen Cloth]", 1, true) == 1 end)
check("a stack's sale shows the item and its size",    cloth and Plain(cloth.label.text), "[Linen Cloth] x20")

-- A single item whose name alone does not fit takes two lines.
haul.recordSale = nil
haul.items = { other = { { itemID = BRACER, count = 1 } } }
MailReport:Show(haul)
items = Row(function(row) return Plain(row.label.text):find("Items from letters", 1, true) end)
check("a name too long for one line wraps",            items and items.value.wrap, true)
check("and its row grows",                             items and items.height > 20, true)
heading = Row(function(row) return Plain(row.label.text) == "BEST SALE" end)
check("no tag without a record",                       heading and heading.tag.shown, false)

MailReport.frame:Hide()
MailHaul:InvalidateMatchers()
Mail:InvalidateMatchers()

for _, key in ipairs(GLOBALS) do _G[key] = saved[key] end

print("")
print(("%d passed, %d failed"):format(passed, failed))
assert(failed == 0, "mail return and report checks failed")
