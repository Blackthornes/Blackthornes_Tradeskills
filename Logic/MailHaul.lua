-- Blackthornes Tradeskills -- Logic/MailHaul.lua
-- What you actually collected at the mailbox, and the report afterwards.
--
-- Data/Mail.lua writes a sale down the moment its mail arrives. That is the
-- right record for sell-through, but it is not the moment that feels like
-- anything: the gold lands in your pocket when you take it out of the mailbox.
-- This watches the mailbox while it is open, works out what left it between
-- one reading and the next, and when you walk away hands the whole visit to
-- UI/MailReport.lua as a haul: the gold, where it came from, the best sale,
-- what came back, and whether any of it beat your record.
--
-- How "what left" is worked out. Mail has no id and indices shuffle as mail is
-- taken (see Data/Mail.lua), so each reading is folded into buckets: one per
-- kind of mail and item name for auction mail, one per sender for anything
-- else. A bucket keeps every mail's gold as a separate amount and its items as
-- counts. Between two readings:
--
--   gold  -- every amount that was there and is not any more was collected.
--            Amounts that appear are ignored: that is new mail arriving, or a
--            sale's held gold being released, never something you took.
--   items -- a count that went down was collected. Only from a complete
--            reading: an attachment that has not loaded yet is not one you
--            took (the same rule the ledger follows).
--
-- Mail cannot be deleted while it holds gold or items, so nothing leaves the
-- mailbox without being collected.

local _, ns = ...

local MailHaul = ns.NewModule("MailHaul")

local Util = ns.Util

-- Visits kept per realm. Each is small; a hundred is months of play.
local MAX_HAULS = 100

-- How much of one haul is kept once saved. The report itself sees it all.
local KEEP_SALES = 10
local KEEP_ITEMS = 8

--------------------------------------------------------------------------------
-- Classifying mail
--------------------------------------------------------------------------------

local matchers

--- Auction mail subjects, from the client's own strings so any language
--- works. Two more kinds than the ledger knows: an auction you won (the item
--- you bought) and a bid you lost (your gold coming back).
local function GetMatchers()
    if matchers then return matchers end

    local pattern = ns.Mail and ns.Mail.SubjectPattern or function() return nil end

    matchers = {
        { kind = "sold",    pattern = pattern(_G.AUCTION_SOLD_MAIL_SUBJECT) },
        { kind = "expired", pattern = pattern(_G.AUCTION_EXPIRED_MAIL_SUBJECT) },
        { kind = "removed", pattern = pattern(_G.AUCTION_REMOVED_MAIL_SUBJECT) },
        { kind = "won",     pattern = pattern(_G.AUCTION_WON_MAIL_SUBJECT) },
        { kind = "outbid",  pattern = pattern(_G.AUCTION_OUTBID_MAIL_SUBJECT) },
    }

    return matchers
end

--- Let the tests rebuild the matchers after changing the client's globals.
function MailHaul:InvalidateMatchers()
    matchers = nil
end

--- What kind of mail this is, and the name that goes with it.
-- @return kind ("sold"|"expired"|"removed"|"won"|"outbid"|"other"), name
function MailHaul:Classify(mail)
    if type(mail.subject) == "string" then
        for _, matcher in ipairs(GetMatchers()) do
            if matcher.pattern then
                local name = mail.subject:match(matcher.pattern)
                if name then return matcher.kind, name end
            end
        end
    end

    -- A client without the subject strings still hands over a seller's
    -- invoice for a sale, which is how the ledger copes too.
    if ns.Mail and ns.Mail.ReadInvoice and mail.index then
        local invoice = ns.Mail:ReadInvoice(mail.index)
        if invoice and invoice.invoiceType == "seller" then
            return "sold", invoice.itemName
        end
        if invoice and invoice.invoiceType == "buyer" then
            return "won", invoice.itemName
        end
    end

    return "other", mail.sender
end

--------------------------------------------------------------------------------
-- Readings
--------------------------------------------------------------------------------

--- One reading of the inbox, folded into buckets.
-- @return key -> { kind, name, monies = { amount, ... }, items = { itemID = count } }
function MailHaul:Snapshot(mails)
    local buckets = {}

    for _, mail in ipairs(mails) do
        local kind, name = self:Classify(mail)
        local key = kind .. ":" .. tostring(name or "?")

        local bucket = buckets[key]
        if not bucket then
            bucket = { kind = kind, name = name, monies = {}, items = {} }
            buckets[key] = bucket
        end

        local money = tonumber(mail.money) or 0
        if money > 0 then bucket.monies[#bucket.monies + 1] = money end

        for _, attachment in ipairs(mail.attachments or {}) do
            bucket.items[attachment.itemID] =
                (bucket.items[attachment.itemID] or 0) + (attachment.quantity or 1)
        end
    end

    return buckets
end

--- The amounts in `before` that are not in `after`, matching equal amounts
--- one for one so two sales of the same price are told apart.
local function Removed(before, after)
    local left = {}
    for _, amount in ipairs(after) do left[amount] = (left[amount] or 0) + 1 end

    local gone = {}
    for _, amount in ipairs(before) do
        if (left[amount] or 0) > 0 then
            left[amount] = left[amount] - 1
        else
            gone[#gone + 1] = amount
        end
    end

    return gone
end

--- What was collected between two readings.
-- @return array of { kind, name, monies = { amount, ... }, items = { itemID = count } }
function MailHaul:Diff(before, after, itemsReliable)
    local taken = {}

    for key, old in pairs(before) do
        local new = after[key] or { monies = {}, items = {} }
        local event = { kind = old.kind, name = old.name, monies = Removed(old.monies, new.monies), items = {} }
        local any = #event.monies > 0

        if itemsReliable then
            for itemID, count in pairs(old.items) do
                local fewer = count - (new.items[itemID] or 0)
                if fewer > 0 then
                    event.items[itemID] = fewer
                    any = true
                end
            end
        end

        if any then taken[#taken + 1] = event end
    end

    return taken
end

--------------------------------------------------------------------------------
-- A visit
--------------------------------------------------------------------------------

local function NewVisit()
    return {
        startedAt = time(),
        gold = { sold = 0, outbid = 0, other = 0 },
        total = 0,
        sales = {},        -- { name, amount }
        items = {},        -- kind -> itemID -> count
        senders = {},      -- sender -> gold, for mail from people
        letters = 0,       -- people whose mail held gold or items
    }
end

--- Start watching the mailbox. MAIL_SHOW calls it; Observe does too, in case
--- the first reading came before the event.
function MailHaul:BeginVisit()
    self.visit = NewVisit()
    self.baseline = nil
end

--- Is there a visit being watched?
function MailHaul:InVisit()
    return self.visit ~= nil
end

--- The visit so far, for the live tally beside the mailbox.
function MailHaul:Current()
    return self.visit
end

--- Fold what was collected into the visit.
-- @return gold collected by these events
function MailHaul:Record(events)
    local visit = self.visit
    local gained = 0

    for _, event in ipairs(events) do
        local bucket = (event.kind == "sold" or event.kind == "outbid") and event.kind or "other"
        local eventGold = 0

        for _, amount in ipairs(event.monies) do
            eventGold = eventGold + amount

            if event.kind == "sold" then
                visit.sales[#visit.sales + 1] = { name = event.name, amount = amount }
            end
        end

        visit.gold[bucket] = visit.gold[bucket] + eventGold
        gained = gained + eventGold

        local itemKind = (event.kind == "sold" or event.kind == "outbid") and "other" or event.kind
        local hadItems = false

        for itemID, count in pairs(event.items) do
            visit.items[itemKind] = visit.items[itemKind] or {}
            visit.items[itemKind][itemID] = (visit.items[itemKind][itemID] or 0) + count
            hadItems = true
        end

        -- Counted by sender: taking the gold and then the item off one
        -- letter is two collections but still one letter.
        if event.kind == "other" and (eventGold > 0 or hadItems) then
            local sender = tostring(event.name or "?")
            if not visit.senders[sender] then visit.letters = visit.letters + 1 end
            visit.senders[sender] = (visit.senders[sender] or 0) + eventGold
        end
    end

    visit.total = visit.total + gained
    return gained
end

--- A new reading of the inbox. Data/Mail.lua calls this every time it reads.
function MailHaul:Observe(mails, complete)
    if not self.visit then
        -- Only while the mailbox is open: a reading at any other time is
        -- stock bookkeeping, not a visit.
        if not (ns.Mail and ns.Mail.isOpen) then return end
        self:BeginVisit()
    end

    local now = self:Snapshot(mails)

    if not self.baseline then
        self.baseline = now
        return
    end

    local events = self:Diff(self.baseline, now, complete)

    -- Items only move on from a complete reading, so one still loading is
    -- compared with the last reading that could be trusted.
    if not complete then
        for key, bucket in pairs(now) do
            local old = self.baseline[key]
            bucket.items = old and old.items or {}
        end
    end

    self.baseline = now

    if #events == 0 then return end

    local gained = self:Record(events)

    if ns.MailReport and ns.MailReport.OnCollected then
        local ok, err = pcall(ns.MailReport.OnCollected, ns.MailReport, self.visit, gained, events)
        if not ok then ns.Debug("mail tally:", tostring(err)) end
    end
end

--------------------------------------------------------------------------------
-- The haul
--------------------------------------------------------------------------------

--- The realm's saved visits, oldest first.
function MailHaul:GetHistory()
    if not ns.db then return {} end

    local realmKey = ns.Config:GetRealmKey()
    ns.db.mailHauls = ns.db.mailHauls or {}
    ns.db.mailHauls[realmKey] = ns.db.mailHauls[realmKey] or {}
    return ns.db.mailHauls[realmKey]
end

--- Item names to ids, from what the sales ledger already resolved. Cheap: no
--- item lookups at all, which matters because the game's item cache is small
--- and flooding it makes bag items read as unsellable.
local function NameIndex()
    local index = {}
    if not (ns.Mail and ns.Mail.GetLedger) then return index end

    for _, entry in ipairs(ns.Mail:GetLedger().entries) do
        if entry.name and entry.itemID then index[entry.name] = entry.itemID end
    end

    return index
end

--- An item-count table as a sorted list, most first.
local function ItemList(counts)
    local list = {}
    for itemID, count in pairs(counts or {}) do
        list[#list + 1] = { itemID = itemID, count = count }
    end
    table.sort(list, function(a, b)
        if a.count ~= b.count then return a.count > b.count end
        return a.itemID < b.itemID
    end)
    return list
end

local function Sum(list)
    local n = 0
    for _, entry in ipairs(list) do n = n + entry.count end
    return n
end

--- What the items that came back are worth at today's prices, where known.
local function ItemsValue(list)
    if not (ns.Prices and ns.Prices.GetValue) then return 0 end

    local value = 0
    for _, entry in ipairs(list) do
        local ok, each = pcall(ns.Prices.GetValue, ns.Prices, entry.itemID)
        if ok and type(each) == "number" then value = value + each * entry.count end
    end
    return value
end

--- The best haul and best single sale before this one.
function MailHaul:Records(history)
    local bestHaul, bestSale = 0, 0

    for _, haul in ipairs(history or self:GetHistory()) do
        if (haul.total or 0) > bestHaul then bestHaul = haul.total end
        if haul.best and (haul.best.amount or 0) > bestSale then bestSale = haul.best.amount end
    end

    return bestHaul, bestSale
end

--- Gold collected since `since` (a time()), across saved visits.
function MailHaul:TotalSince(since)
    local total = 0
    for _, haul in ipairs(self:GetHistory()) do
        if (haul.t or 0) >= since then total = total + (haul.total or 0) end
    end
    return total
end

--- Seconds since local midnight, so "today" means the player's day.
local function StartOfToday(now)
    local ok, parts = pcall(date, "*t", now)
    if not ok or type(parts) ~= "table" then return now - 86400 end
    return now - ((parts.hour or 0) * 3600 + (parts.min or 0) * 60 + (parts.sec or 0))
end

--- Turn a visit into a haul: sorted, trimmed, compared with the records.
-- @return haul, or nil when nothing was collected
function MailHaul:Finish(visit, history)
    if not visit then return nil end

    local items = {}
    local itemCount = 0
    for kind, counts in pairs(visit.items) do
        items[kind] = ItemList(counts)
        itemCount = itemCount + Sum(items[kind])
    end

    if visit.total <= 0 and itemCount == 0 then return nil end

    local names = NameIndex()
    local sales = {}
    for _, sale in ipairs(visit.sales) do
        sales[#sales + 1] = { name = sale.name, amount = sale.amount, itemID = names[sale.name or ""] }
    end
    table.sort(sales, function(a, b) return a.amount > b.amount end)

    history = history or self:GetHistory()
    local bestHaul, bestSale = self:Records(history)
    local now = time()

    local haul = {
        t = now,
        who = ns.Config:GetCharacterKey(),
        total = visit.total,
        gold = { sold = visit.gold.sold, outbid = visit.gold.outbid, other = visit.gold.other },
        salesCount = #sales,
        sales = sales,
        best = sales[1],
        items = items,
        itemCount = itemCount,
        letters = visit.letters,
        returnedValue = ItemsValue(items.expired or {}) + ItemsValue(items.removed or {}),
    }

    -- A record only counts against something: the first visit ever is its
    -- own moment, not a record.
    haul.first = #history == 0
    haul.recordHaul = not haul.first and haul.total > bestHaul
    haul.recordSale = not haul.first and haul.best ~= nil and haul.best.amount > bestSale
    haul.previousBest = bestHaul

    -- The day and week so far, this haul included.
    local today = StartOfToday(now)
    haul.today = self:TotalSince(today) + haul.total
    haul.week = self:TotalSince(now - 7 * 86400) + haul.total

    return haul
end

--- The copy that goes into saved data: the same, trimmed.
local function Trimmed(haul)
    local copy = {}
    for key, value in pairs(haul) do copy[key] = value end

    copy.sales = {}
    for index = 1, math.min(KEEP_SALES, #haul.sales) do copy.sales[index] = haul.sales[index] end

    copy.items = {}
    for kind, list in pairs(haul.items) do
        copy.items[kind] = {}
        for index = 1, math.min(KEEP_ITEMS, #list) do copy.items[kind][index] = list[index] end
    end

    return copy
end

--- The mailbox closed. Save the visit and show the report.
-- @return the haul, or nil when nothing was collected
function MailHaul:EndVisit()
    local visit = self.visit
    self.visit = nil
    self.baseline = nil

    local haul = self:Finish(visit)
    if not haul then return nil end

    local history = self:GetHistory()
    history[#history + 1] = Trimmed(haul)
    while #history > MAX_HAULS do table.remove(history, 1) end

    self.last = haul
    self:Announce(haul)

    if ns.Config:Get("mailReport") ~= false and ns.MailReport then
        local ok, err = pcall(ns.MailReport.Show, ns.MailReport, haul)
        if not ok then ns.Debug("mail report:", tostring(err)) end
    end

    return haul
end

--- One line in chat, so the haul is on record even with the window off.
function MailHaul:Announce(haul)
    local parts = { ("Mail collected: %s"):format(Util.FormatMoney(haul.total)) }

    if haul.salesCount > 0 then
        parts[#parts + 1] = ("%d sale%s"):format(haul.salesCount, haul.salesCount == 1 and "" or "s")
    end

    if haul.best then
        parts[#parts + 1] = ("best was %s for %s"):format(haul.best.name or "an item",
            Util.FormatMoney(haul.best.amount))
    end

    ns.Print(table.concat(parts, ", ") .. ".")

    if haul.recordHaul then
        ns.PrintRaw(("  |c%sNew best haul!|r Your old best was %s."):format(
            ns.COLORS.accent, Util.FormatMoney(haul.previousBest)))
    elseif haul.recordSale then
        ns.PrintRaw(("  |c%sYour best sale ever!|r"):format(ns.COLORS.accent))
    end
end

--------------------------------------------------------------------------------
-- Events and commands
--------------------------------------------------------------------------------

function MailHaul:OnEnable()
    ns.RegisterEvent(self, "MAIL_SHOW", function()
        MailHaul:BeginVisit()
        if ns.MailReport and ns.MailReport.OnMailboxOpened then
            pcall(ns.MailReport.OnMailboxOpened, ns.MailReport)
        end
    end)

    ns.RegisterEvent(self, "MAIL_CLOSED", function()
        if ns.MailReport and ns.MailReport.OnMailboxClosed then
            pcall(ns.MailReport.OnMailboxClosed, ns.MailReport)
        end
        -- The game can send this twice; the second finds no visit.
        if MailHaul.visit then MailHaul:EndVisit() end
    end)
end

--- A made-up haul, for seeing the report without a trip to the mailbox.
function MailHaul:Sample()
    local history = self:GetHistory()
    local bestHaul = self:Records(history)
    local total = math.max(bestHaul + 12345, 482650)

    return {
        t = time(),
        who = ns.Config:GetCharacterKey(),
        total = total,
        gold = { sold = total - 51500, outbid = 41500, other = 10000 },
        salesCount = 7,
        sales = {
            { name = "Runecloth Bag", amount = 185000 },
            { name = "Mooncloth", amount = 92000 },
            { name = "Heavy Silk Bandage", amount = 48000 },
            { name = "Bolt of Silk Cloth", amount = 36500 },
            { name = "Linen Bag", amount = 21000 },
            { name = "Wool Bandage", amount = 12400 },
        },
        best = { name = "Runecloth Bag", amount = 185000 },
        items = {
            expired = { { itemID = 2589, count = 20 } },
            won = { { itemID = 2592, count = 40 } },
        },
        itemCount = 60,
        letters = 1,
        returnedValue = 3400,
        recordHaul = true,
        recordSale = true,
        previousBest = bestHaul,
        today = total + 150000,
        week = total + 980000,
        sample = true,
    }
end

ns.RegisterCommand("haul", "[test]: show the report from your last mailbox visit (test: a made-up one)", function(args)
    local word = (args or ""):lower():match("^%s*(%S*)")

    if not ns.MailReport then return end

    if word == "test" then
        ns.MailReport:Show(MailHaul:Sample())
        return
    end

    local haul = MailHaul.last
    if not haul then
        local history = MailHaul:GetHistory()
        haul = history[#history]
    end

    if not haul then
        ns.Print("no mailbox visits recorded yet. Collect some mail and the report opens when you walk away. /bts haul test shows a sample.")
        return
    end

    ns.MailReport:Show(haul, { replay = true })
end)
