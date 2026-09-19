-- Blackthornes Tradeskills -- Data/Mail.lua
-- The mailbox: stock you own but cannot see, and the record of what sold.
--
-- Two jobs, deliberately independent of each other.
--
-- The first is stock. An auction that expires comes back as mail, and until you
-- collect it that item is counted nowhere: it has dropped off your auctions and
-- it is not in your bags yet. The Profit tab would cheerfully tell you to craft
-- more of something already on its way home. Anything sitting in the mailbox is
-- yours, so it counts.
--
-- The second is reconciliation. A listing leaves and something comes back --
-- either gold, because it sold, or the item, because it did not. Nothing in the
-- addon recorded which. Owned auctions are read fresh each time, so a sale and
-- an expiry look identical: the listing is simply gone. This keeps a ledger, so
-- "the Profit tab said 3s profit" can be checked against what the auction house
-- actually paid.
--
-- The stock half needs no interpretation at all -- an item in the mailbox is an
-- item in the mailbox. The ledger half has to work out WHY a mail arrived, and
-- that rests on the client exposing its own auction mail subjects. Where it
-- does not, the stock half still works and the ledger simply records less;
-- `/bts mail` reports which of the two you are getting.

local _, ns = ...

local Mail = ns.NewModule("Mail")

local Util = ns.Util

-- Attachment slots on one mail. Read from the client where it says, because a
-- walk that stops short silently loses stock -- the same failure the reagent
-- bag had in Data/Inventory.lua.
local MAX_ATTACHMENTS = tonumber(_G.ATTACHMENTS_MAX_RECEIVE) or 16

-- How many ledger entries to keep per realm. Long enough to see a pattern,
-- short enough not to bloat saved variables, which on this client are already
-- fragile -- see Core/Persist.lua.
local MAX_LEDGER = 400

--------------------------------------------------------------------------------
-- Storage
--------------------------------------------------------------------------------

--- Mailbox contents are per character, like bags and bank: your other
--- character's mailbox is not something you can reach.
local function GetRecord(create)
    return ns.Recipes:GetCharacterRecord(create)
end

--- The realm's ledger of what sold and what came back.
--
-- Per realm rather than per character because it is a record of the market,
-- and each entry names the character it happened to anyway.
function Mail:GetLedger()
    if not ns.db then return { entries = {}, seen = {} } end

    local realmKey = ns.Config:GetRealmKey()

    ns.db.mailLedger = ns.db.mailLedger or {}
    ns.db.mailLedger[realmKey] = ns.db.mailLedger[realmKey] or { entries = {}, seen = {} }

    local ledger = ns.db.mailLedger[realmKey]
    ledger.entries = ledger.entries or {}
    ledger.seen = ledger.seen or {}

    return ledger
end

--------------------------------------------------------------------------------
-- Counts
--------------------------------------------------------------------------------

--- itemID -> how many sit in this character's mailbox, as last read.
--
-- Cached, because the inbox is only readable while standing at a mailbox. Same
-- shape as the bank snapshot in Data/Inventory.lua and for the same reason.
function Mail:GetCounts()
    local record = GetRecord(false)
    return (record and record.mail) or {}
end

--- How many of an item are waiting in the mailbox.
--
-- Zero when the player has turned mail off as a stock source, so every caller
-- respects the setting without having to know about it.
function Mail:GetCount(itemID)
    if not itemID then return 0 end
    if ns.Config:Get("countMailAsStock") == false then return 0 end

    return self:GetCounts()[itemID] or 0
end

--- When the mailbox was last read, or nil if never.
function Mail:GetAge()
    local record = GetRecord(false)
    if not record or not record.mailAt then return nil end
    return time() - record.mailAt
end

--- Has the mailbox been opened since logging in?
--
-- A snapshot from yesterday is better than nothing, but a player deciding
-- whether to craft another twenty should know which they are looking at.
function Mail:HasReadThisSession()
    return self.readThisSession == true
end

--------------------------------------------------------------------------------
-- Reading the inbox
--------------------------------------------------------------------------------

--- The itemID on an attachment, and how many of it.
--
-- The item id comes from the link rather than the return values, because
-- `GetInboxItem` has had two different shapes: the older one returns
-- (name, texture, count, ...) and the newer one (name, itemID, texture, count,
-- ...). Both are numbers in the second slot, so the returns alone cannot tell
-- you which client you are on.
--
-- The link settles it. Parse the id out of the link, then look at what the
-- second return actually is: if it equals that id, this is the newer shape and
-- the count is fourth; otherwise it is the older shape and the count is third.
-- That is a real test of which client this is rather than an assumption about
-- it, which is the whole point.
--
-- @return itemID, count -- itemID nil when the attachment is not readable yet
function Mail:ReadAttachment(index, slot)
    local itemID

    if Util.HasFunction("GetInboxItemLink") then
        local ok, link = pcall(GetInboxItemLink, index, slot)
        if ok and link then
            itemID = tonumber(link:match("item:(%d+)"))
        end
    end

    if not Util.HasFunction("GetInboxItem") then
        return itemID, itemID and 1 or nil
    end

    local ok, _, second, third, fourth = pcall(GetInboxItem, index, slot)
    if not ok then return itemID, itemID and 1 or nil end

    -- No link to check against: fall back to the newer shape, which is what
    -- this client's interface number says it should be, and record that the
    -- guess was made so the diagnostic can show it.
    if not itemID then
        if type(second) == "number" then
            self.shapeUnknown = true
            return second, tonumber(fourth) or 1
        end
        return nil, nil
    end

    if second == itemID then
        self.attachmentShape = "itemID second"
        return itemID, tonumber(fourth) or 1
    end

    self.attachmentShape = "count third"
    return itemID, tonumber(third) or 1
end

--- Everything the inbox is showing right now.
--
-- @return mails, complete
--   mails    array of { index, sender, subject, money, cod, daysLeft,
--                       attachments = { {itemID, count}, ... }, pending }
--   complete false when an attachment has not loaded yet, so the caller knows
--            this reading is not the final word on what is there
function Mail:ReadInbox()
    local mails, complete = {}, true

    if not Util.HasFunction("GetInboxNumItems") then return mails, false end

    local ok, count = pcall(GetInboxNumItems)
    if not ok or not count then return mails, false end

    for index = 1, count do
        local mail = { index = index, attachments = {} }

        if Util.HasFunction("GetInboxHeaderInfo") then
            local infoOk, _, _, sender, subject, money, cod, daysLeft, itemCount =
                pcall(GetInboxHeaderInfo, index)

            if infoOk then
                mail.sender = sender
                mail.subject = subject
                mail.money = tonumber(money) or 0
                mail.cod = tonumber(cod) or 0
                mail.daysLeft = tonumber(daysLeft)
                mail.itemCount = tonumber(itemCount) or 0
            end
        end

        local declared = mail.itemCount or 0

        for slot = 1, math.min(MAX_ATTACHMENTS, math.max(declared, 0)) do
            local itemID, quantity = self:ReadAttachment(index, slot)

            if itemID then
                mail.attachments[#mail.attachments + 1] =
                    { itemID = itemID, quantity = quantity or 1 }
            end
        end

        -- The client loads attachments lazily. A mail whose attachments are
        -- declared but not yet readable is not "a mail with no items" -- it is
        -- a mail we cannot see into yet, and treating the two the same would
        -- both undercount stock and write a wrong ledger entry.
        if declared > 0 and #mail.attachments < declared then
            mail.pending = true
            complete = false
        end

        mails[#mails + 1] = mail
    end

    return mails, complete
end

--- Read the mailbox and store what it holds.
--
-- Local reads only, nothing throttled, safe to call on every inbox update.
function Mail:Read()
    if not Util.HasFunction("GetInboxNumItems") then return end

    local mails, complete = self:ReadInbox()

    local counts = {}
    for _, mail in ipairs(mails) do
        for _, attachment in ipairs(mail.attachments) do
            counts[attachment.itemID] =
                (counts[attachment.itemID] or 0) + attachment.quantity
        end
    end

    local record = GetRecord(true)
    if not record then return end

    record.mail = counts
    record.mailAt = time()
    self.readThisSession = true
    self.lastComplete = complete

    self:Reconcile(mails, complete)

    ns.Debug(("mailbox: %d mail(s), %d item stack(s)%s"):format(
        #mails, Util.Count(counts), complete and "" or " (still loading)"))

    if ns.UI then
        ns.UI:RefreshActiveTab()
        if ns.UI.OnInventoryUpdated then ns.UI:OnInventoryUpdated() end
    end
end

--------------------------------------------------------------------------------
-- Classifying auction mail
--------------------------------------------------------------------------------

--- Turn one of the client's own mail subject formats into a Lua pattern.
--
-- The subjects are localised, so the English strings are no use. The client
-- carries its own -- AUCTION_SOLD_MAIL_SUBJECT and friends -- in whatever
-- language it is running, and matching against those works everywhere and
-- breaks nowhere. Where the global is missing the matcher is simply absent and
-- that kind of mail goes unclassified rather than being guessed at.
local function SubjectPattern(format)
    if type(format) ~= "string" then return nil end

    -- Escape everything the pattern language would otherwise read, then put the
    -- item name capture back where the %s was.
    local escaped = format:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
    local pattern = escaped:gsub("%%%%s", "(.+)")

    return "^" .. pattern
end

local subjectMatchers

--- Matchers for the three ways an auction ends, built once from the client.
local function GetMatchers()
    if subjectMatchers then return subjectMatchers end

    subjectMatchers = {
        { kind = "sold",     pattern = SubjectPattern(_G.AUCTION_SOLD_MAIL_SUBJECT) },
        { kind = "expired",  pattern = SubjectPattern(_G.AUCTION_EXPIRED_MAIL_SUBJECT) },
        { kind = "removed",  pattern = SubjectPattern(_G.AUCTION_REMOVED_MAIL_SUBJECT) },
    }

    return subjectMatchers
end

--- Let the tests rebuild the matchers after changing the client's globals.
function Mail:InvalidateMatchers()
    subjectMatchers = nil
end

--- What kind of auction mail this is, and the item name in its subject.
-- @return kind ("sold"|"expired"|"removed"), itemName -- both nil if it is not
--         auction mail, or if this client does not expose the subjects
function Mail:Classify(mail)
    if not mail or type(mail.subject) ~= "string" then return nil end

    for _, matcher in ipairs(GetMatchers()) do
        if matcher.pattern then
            local name = mail.subject:match(matcher.pattern)
            if name then return matcher.kind, name end
        end
    end

    return nil
end

--- The seller's invoice, where the client has one.
--
-- This is the honest source for a sale: the amount actually bid, the deposit
-- handed back and the cut the auction house took, rather than a single lump of
-- gold that has to be guessed apart.
-- @return table or nil
function Mail:ReadInvoice(index)
    if not Util.HasFunction("GetInboxInvoiceInfo") then return nil end

    local ok, invoiceType, itemName, playerName, bid, buyout, deposit, consignment,
        moneyDelay = pcall(GetInboxInvoiceInfo, index)

    if not ok or not invoiceType then return nil end

    return {
        invoiceType = invoiceType,
        itemName = itemName,
        buyer = playerName,
        bid = tonumber(bid),
        buyout = tonumber(buyout),
        deposit = tonumber(deposit),
        cut = tonumber(consignment),
        -- How long the auction house is still holding the gold for. While that
        -- runs, the mail's own money field reads zero.
        moneyDelay = tonumber(moneyDelay),
    }
end

--- What a sale actually put in your pocket.
--
-- The header's money is the ground truth once it is there, so it wins. But a
-- sale whose gold is still being held reads zero in the header while the
-- invoice already knows the numbers, and recording that as a sale for nothing
-- is how the ledger came to say "sold Linen Reagent Bag for 0c".
--
-- So fall back to the invoice arithmetic: what the buyer bid, less the cut the
-- auction house takes, plus the deposit handed back because it sold.
--
-- @return amount, estimated -- amount nil when neither source can say yet
local function SaleAmount(mail, invoice)
    local money = tonumber(mail.money) or 0
    if money > 0 then return money, false end

    if invoice and invoice.bid then
        return invoice.bid - (invoice.cut or 0) + (invoice.deposit or 0), true
    end

    return nil, false
end

--------------------------------------------------------------------------------
-- The ledger
--------------------------------------------------------------------------------

--- A stable identity for one mail.
--
-- Mail has no id, and indices shuffle as mail is taken, so identity has to be
-- built out of what a mail is rather than where it sits. Two genuinely
-- identical mails collide on purpose: they are counted rather than matched, so
-- a collision is handled by arithmetic instead of being a bug.
-- Money is deliberately NOT part of this. It was, and that was a bug: the gold
-- on a sale is held for a while and the header reads zero until it is released,
-- so the same mail fingerprinted one way before the payout and another way
-- after, and the ledger wrote the sale down twice. Identity has to be the
-- things about a mail that cannot change while it sits in the box.
local function Fingerprint(mail)
    local parts = {
        tostring(mail.sender or "?"),
        tostring(mail.subject or "?"),
        tostring(mail.cod or 0),
    }

    -- Attachments in a fixed order, so the same mail fingerprints the same way
    -- however the client happens to hand back its slots.
    local stacks = {}
    for _, attachment in ipairs(mail.attachments) do
        stacks[#stacks + 1] = ("%d:%d"):format(attachment.itemID, attachment.quantity)
    end
    table.sort(stacks)

    parts[#parts + 1] = table.concat(stacks, ",")

    return table.concat(parts, "|")
end

--- An itemID for a name the auction house gave us.
--
-- A sale leaves no attachment -- the item is gone -- so the invoice's item name
-- is all there is to go on. Resolved against what the addon already knows
-- about, which is every recipe output it has cached. An unresolved name is
-- still recorded, by name, rather than dropped.
function Mail:ResolveItemName(name)
    if not name or name == "" then return nil end

    self.nameCache = self.nameCache or {}
    if self.nameCache[name] ~= nil then
        return self.nameCache[name] or nil
    end

    local found

    local source = ns.Recipes and ns.Recipes.GetAccountWide
        and ns.Recipes:GetAccountWide() or (ns.Recipes and ns.Recipes:GetAll()) or {}

    for _, recipe in pairs(source) do
        local itemID = recipe.outputItemID

        if itemID and not found then
            local ok, itemName = pcall(C_Item.GetItemInfo, itemID)
            if ok and itemName == name then found = itemID end
        end
    end

    -- false rather than nil, so a miss is remembered and the whole recipe list
    -- is not walked again for every redraw.
    self.nameCache[name] = found or false

    return found
end

--- Record what a new mail tells us, if anything.
local function Describe(mail, kind, itemName, invoice)
    local entry = {
        t = time(),
        kind = kind,
        who = ns.Config:GetCharacterKey(),
        name = itemName,
    }

    if kind == "sold" then
        local amount, estimated = SaleAmount(mail, invoice)

        entry.net = amount
        entry.estimated = estimated or nil

        if invoice then
            entry.gross = invoice.bid
            entry.deposit = invoice.deposit
            entry.cut = invoice.cut
            entry.name = invoice.itemName or entry.name
            entry.buyer = invoice.buyer
        end

        entry.itemID = ns.Mail:ResolveItemName(entry.name)
    else
        -- An expired or cancelled auction comes back as the item itself, so
        -- the attachment is the authority and the subject is only a label.
        local attachment = mail.attachments[1]

        if attachment then
            entry.itemID = attachment.itemID
            entry.quantity = attachment.quantity
        end
    end

    return entry
end

--- Fold a reading of the inbox into the ledger.
--
-- Works by difference, not by presence: for each fingerprint we hold the number
-- currently in the inbox, and record only the increase. Taking a mail drops the
-- count back, so an identical mail arriving later is recorded properly instead
-- of being mistaken for the one already seen.
--
-- The upshot is that re-reading the same inbox any number of times changes
-- nothing, which matters because MAIL_INBOX_UPDATE fires repeatedly and a
-- half-loaded inbox is a normal thing to be handed.
function Mail:Reconcile(mails, complete)
    local ledger = self:GetLedger()

    -- Counted fresh each reading, not accumulated: it answers "is anything
    -- waiting right now", which is what the diagnostic reports.
    self.awaitingAmount = 0

    local present = {}

    -- Each mail is recorded from its own reading rather than from whichever
    -- one of a matching pair happened to be walked first. Two sales of the same
    -- item share a fingerprint on purpose, and they can still have landed
    -- different amounts of gold -- one paid out, one still being held -- so
    -- describing both from the first mail would have put the wrong figure on
    -- one of them.
    for _, mail in ipairs(mails) do
        -- A mail whose attachments have not arrived yet would fingerprint as a
        -- different mail than the same one fully loaded, so it waits.
        if not mail.pending then
            local key = Fingerprint(mail)
            local occurrence = (present[key] or 0) + 1
            present[key] = occurrence

            if occurrence > (ledger.seen[key] or 0) then
                local kind, itemName = self:Classify(mail)
                local invoice = self:ReadInvoice(mail.index)

                -- Some clients do not carry the subject globals. An invoice
                -- marked "seller" is a sale whatever the subject says, so it
                -- is still recorded; everything else stays unclassified rather
                -- than being guessed at.
                if not kind and invoice and invoice.invoiceType == "seller" then
                    kind = "sold"
                    itemName = invoice.itemName
                end

                if kind == "sold" and SaleAmount(mail, invoice) == nil then
                    -- Neither the header nor an invoice can say what this sale
                    -- paid yet. Writing it down as nothing is worse than
                    -- writing it down later, so it waits like an unloaded
                    -- attachment does.
                    mail.pending = true
                    present[key] = occurrence - 1
                    self.awaitingAmount = (self.awaitingAmount or 0) + 1

                elseif kind then
                    ledger.entries[#ledger.entries + 1] =
                        Describe(mail, kind, itemName, invoice)

                else
                    -- Ordinary mail from a person. Counted as stock above, and
                    -- deliberately not a ledger entry.
                    ns.Debug("mail not from the auction house:", tostring(mail.subject))
                end
            end
        end
    end

    -- Whatever is in the box now is what has been seen. Taking a mail drops the
    -- count back, so an identical one arriving later reads as new rather than
    -- as one already recorded.
    for key, count in pairs(present) do
        ledger.seen[key] = count
    end

    -- Fingerprints that vanished entirely. Only safe when we saw the whole
    -- inbox: zeroing on a half-loaded reading would re-record everything.
    if complete then
        for key in pairs(ledger.seen) do
            if not present[key] then ledger.seen[key] = nil end
        end
    end

    while #ledger.entries > MAX_LEDGER do
        table.remove(ledger.entries, 1)
    end
end

--------------------------------------------------------------------------------
-- Reading the ledger back
--------------------------------------------------------------------------------

--- What the ledger says about one item, or about everything.
--
-- @param itemID optional; nil totals the lot
-- @return { sold, soldUnits, returned, returnedUnits, net, gross, cut, deposit,
--           firstAt, lastAt }
function Mail:GetSummary(itemID)
    local totals = {
        sold = 0, soldUnits = 0,
        returned = 0, returnedUnits = 0,
        net = 0, gross = 0, cut = 0, deposit = 0,
        -- Sales priced from the invoice because the gold had not been released
        -- when they were recorded. Real, but not yet in your pocket.
        estimated = 0,
    }

    for _, entry in ipairs(self:GetLedger().entries) do
        if not itemID or entry.itemID == itemID then
            if entry.kind == "sold" then
                totals.sold = totals.sold + 1
                totals.soldUnits = totals.soldUnits + (entry.quantity or 1)
                totals.net = totals.net + (entry.net or 0)
                if entry.estimated then totals.estimated = totals.estimated + 1 end
                totals.gross = totals.gross + (entry.gross or entry.net or 0)
                totals.cut = totals.cut + (entry.cut or 0)
                totals.deposit = totals.deposit + (entry.deposit or 0)
            else
                totals.returned = totals.returned + 1
                totals.returnedUnits = totals.returnedUnits + (entry.quantity or 1)
            end

            if not totals.firstAt or entry.t < totals.firstAt then totals.firstAt = entry.t end
            if not totals.lastAt or entry.t > totals.lastAt then totals.lastAt = entry.t end
        end
    end

    -- The number the Profit tab is really being judged on: of everything that
    -- left your hands, how much of it actually sold.
    local finished = totals.sold + totals.returned
    totals.sellThrough = finished > 0 and (totals.sold / finished) or nil

    return totals
end

--- The most recent ledger entries, newest first.
function Mail:GetRecent(limit, itemID)
    local entries = self:GetLedger().entries
    local out = {}

    for i = #entries, 1, -1 do
        local entry = entries[i]
        if not itemID or entry.itemID == itemID then
            out[#out + 1] = entry
            if #out >= (limit or 10) then break end
        end
    end

    return out
end

--- How many recorded sales carry no gold.
--
-- Only rows written before the payout-delay fix can look like this: a sale is
-- now priced from the invoice when the header's money is still zero, and one
-- that neither source can price is not recorded at all. So this counts history
-- rather than anything the addon would write today.
function Mail:CountUnpriced()
    local n = 0

    for _, entry in ipairs(self:GetLedger().entries) do
        if entry.kind == "sold" and (entry.net or 0) <= 0 then n = n + 1 end
    end

    return n
end

--- Throw away this realm's ledger.
--
-- `seen` goes with the entries on purpose. It is the record of which mails have
-- already been written down, and keeping it would mean anything sitting in the
-- mailbox right now never gets recorded again.
function Mail:ResetLedger()
    local ledger = self:GetLedger()
    local had = #ledger.entries

    ledger.entries = {}
    ledger.seen = {}

    return had
end

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------

function Mail:OnEnable()
    -- Registering is not receiving -- see Data/Auctions.lua -- so the count is
    -- kept and reported by `/bts mail` rather than assumed either way.
    self.inboxEventCount = 0

    self.hasInboxEvent = ns.RegisterEvent(self, "MAIL_INBOX_UPDATE", function()
        Mail.inboxEventCount = (Mail.inboxEventCount or 0) + 1
        Mail:Read()
    end) and true or false

    ns.RegisterEvent(self, "MAIL_SHOW", function()
        Mail.isOpen = true
        -- The inbox is not ready to be read the instant the frame appears.
        C_Timer.After(0.5, function() Mail:Read() end)
    end)

    ns.RegisterEvent(self, "MAIL_CLOSED", function()
        Mail.isOpen = false
    end)

    -- Taking an attachment moves stock from the mailbox to the bags, and both
    -- counts have to move together or the item is briefly counted twice.
    ns.RegisterEvent(self, "MAIL_SEND_SUCCESS", function() Mail:Read() end)
end

--------------------------------------------------------------------------------
-- Diagnostics
--------------------------------------------------------------------------------

ns.RegisterCommand("mail", "[reset] -- what the mailbox holds and what it says sold", function(args)
    local sub = (args or ""):lower():match("^(%S*)")

    if sub == "reset" then
        local ledger = Mail:GetLedger()
        local entries = #ledger.entries

        if entries == 0 then
            ns.Print("the ledger is already empty")
            return
        end

        -- Clearing it is not undoable and it is the only record of what sold,
        -- so it takes a second word rather than happening on a typo.
        if not (args or ""):lower():match("^reset%s+confirm") then
            ns.Print(("this will delete %d recorded sale(s) and return(s) for %s"):format(
                entries, ns.Config:GetRealmKey()))
            ns.PrintRaw(("  taken in so far: %s"):format(
                Util.FormatMoney(Mail:GetSummary().net)))

            local unpriced = Mail:CountUnpriced()
            if unpriced > 0 then
                ns.PrintRaw(("  %d of them show no gold, from before the payout fix"):format(
                    unpriced))
            end

            ns.PrintRaw(("  to go ahead: |c%s/bts mail reset confirm|r"):format(
                ns.COLORS.accent))
            return
        end

        local had = Mail:ResetLedger()
        ns.Print(("cleared %d ledger entr%s"):format(had, had == 1 and "y" or "ies"))
        ns.PrintRaw("  anything still in the mailbox is recorded again on the next read")

        -- Whatever is in the box is unrecorded again, so read it now if we can.
        if Mail.isOpen then Mail:Read() end

        return
    end

    local hasNum = Util.HasFunction("GetInboxNumItems")
    local hasHeader = Util.HasFunction("GetInboxHeaderInfo")
    local hasItem = Util.HasFunction("GetInboxItem")
    local hasLink = Util.HasFunction("GetInboxItemLink")
    local hasInvoice = Util.HasFunction("GetInboxInvoiceInfo")

    ns.Print("mailbox")
    ns.PrintRaw(("  GetInboxNumItems:     %s"):format(hasNum and "yes" or "no"))
    ns.PrintRaw(("  GetInboxHeaderInfo:   %s"):format(hasHeader and "yes" or "no"))
    ns.PrintRaw(("  GetInboxItem:         %s"):format(hasItem and "yes" or "no"))
    ns.PrintRaw(("  GetInboxItemLink:     %s"):format(hasLink and "yes" or "no"))
    ns.PrintRaw(("  GetInboxInvoiceInfo:  %s"):format(hasInvoice and "yes" or "no"))

    -- Whether this client names its own auction mail decides whether the ledger
    -- can tell a sale from an expiry at all. It is the single most useful line
    -- here, so it is spelled out rather than left to be inferred.
    local subjects = {}
    for _, pair in ipairs({
        { "sold",      _G.AUCTION_SOLD_MAIL_SUBJECT },
        { "expired",   _G.AUCTION_EXPIRED_MAIL_SUBJECT },
        { "cancelled", _G.AUCTION_REMOVED_MAIL_SUBJECT },
    }) do
        subjects[#subjects + 1] = ("%s=%s"):format(
            pair[1], type(pair[2]) == "string" and "yes" or "no")
    end
    ns.PrintRaw(("  auction subjects:     %s"):format(table.concat(subjects, "  ")))

    local announces
    if not Mail.hasInboxEvent then
        announces = "not supported by this client"
    elseif (Mail.inboxEventCount or 0) > 0 then
        announces = ("yes, %d time(s) this session"):format(Mail.inboxEventCount)
    else
        announces = "registered, but never fired this session"
    end
    ns.PrintRaw(("  announces changes:    %s"):format(announces))

    if Mail.attachmentShape then
        ns.PrintRaw(("  attachment returns:   %s"):format(Mail.attachmentShape))
    elseif Mail.shapeUnknown then
        ns.PrintRaw("  attachment returns:   could not be checked (no item link)")
    end

    local age = Mail:GetAge()
    ns.PrintRaw(("  last read:            %s"):format(
        age and (Util.FormatAgeAgo(age) .. (Mail:HasReadThisSession() and "" or ", before this session"))
            or "never"))

    if not hasNum then
        ns.Warn("this client does not expose the inbox; mail cannot be counted as stock.")
        return
    end

    if not Mail.isOpen then
        ns.PrintRaw("  (stand at a mailbox for a fresh reading)")
    end

    local counts = Mail:GetCounts()
    local itemIDs = Util.SortedKeys(counts)

    if #itemIDs == 0 then
        ns.PrintRaw("  holding:              nothing")
    else
        ns.PrintRaw("  holding:")
        for _, itemID in ipairs(itemIDs) do
            ns.PrintRaw(("    %dx %s"):format(counts[itemID], Util.GetItemLabel(itemID)))
        end
    end

    local summary = Mail:GetSummary()
    ns.PrintRaw(("  ledger:               %d sold, %d returned"):format(
        summary.sold, summary.returned))

    if summary.sold > 0 then
        ns.PrintRaw(("    taken in:           %s"):format(Util.FormatMoney(summary.net)))
    end

    if (Mail.awaitingAmount or 0) > 0 then
        ns.PrintRaw(("    waiting on payout:  %d sale(s)"):format(Mail.awaitingAmount))
    end

    local recent = Mail:GetRecent(6)
    if #recent > 0 then
        ns.PrintRaw("  recent:")
        for _, entry in ipairs(recent) do
            local label = entry.itemID and Util.GetItemLabel(entry.itemID)
                or (entry.name or "?")

            if entry.kind == "sold" then
                ns.PrintRaw(("    sold %s for %s%s"):format(
                    label, Util.FormatMoney(entry.net),
                    entry.estimated and "   (from the invoice, gold still held)" or ""))
            else
                ns.PrintRaw(("    %s came back (%s)"):format(label, entry.kind))
            end
        end
    end

    -- What the client actually said, mail by mail.
    --
    -- The ledger once recorded a Linen Reagent Bag as having sold for nothing,
    -- and working out why from the outside was guesswork: the header's money,
    -- the invoice's figures and how they relate are exactly the things that
    -- cannot be seen from a summary. So they are printed raw.
    local mails = Mail:ReadInbox()

    if #mails > 0 then
        ns.PrintRaw("  what the client says, mail by mail:")

        for _, mail in ipairs(mails) do
            local kind = Mail:Classify(mail)

            ns.PrintRaw(("    %d: %s"):format(mail.index, tostring(mail.subject)))
            ns.PrintRaw(("       from=%s  read as=%s  money=%s"):format(
                tostring(mail.sender), kind or "not auction mail",
                Util.FormatMoney(mail.money, { noColor = true })))

            local invoice = Mail:ReadInvoice(mail.index)

            if invoice then
                ns.PrintRaw(("       invoice %s: bid=%s cut=%s deposit=%s held=%s"):format(
                    tostring(invoice.invoiceType),
                    Util.FormatMoney(invoice.bid, { noColor = true }),
                    Util.FormatMoney(invoice.cut, { noColor = true }),
                    Util.FormatMoney(invoice.deposit, { noColor = true }),
                    tostring(invoice.moneyDelay)))
            else
                ns.PrintRaw("       invoice: none")
            end

            for _, attachment in ipairs(mail.attachments) do
                ns.PrintRaw(("       attached: %dx %s"):format(
                    attachment.quantity, Util.GetItemLabel(attachment.itemID)))
            end

            if mail.pending then
                ns.PrintRaw("       not recorded yet -- still loading")
            end
        end
    end
end)

ns.RegisterCommand("sold", "<name or link> -- what it actually earned, against the estimate", function(args)
    local recipe, errorMessage, ambiguous = ns.Profit:Resolve(args)

    if ambiguous then
        ns.Print(("several recipes match '%s' -- try /bts why first"):format(args))
        return
    end

    if not recipe or not recipe.outputItemID then
        ns.Print(errorMessage or "give me an item name or link")
        return
    end

    local itemID = recipe.outputItemID
    local summary = Mail:GetSummary(itemID)

    ns.Print(Util.GetItemLabel(itemID))

    if summary.sold == 0 and summary.returned == 0 then
        ns.PrintRaw("  nothing recorded yet -- visit a mailbox after a listing ends")
        return
    end

    ns.PrintRaw(("  sold:             %d listing(s)"):format(summary.sold))
    ns.PrintRaw(("  came back:        %d listing(s)"):format(summary.returned))

    if summary.sellThrough then
        ns.PrintRaw(("  sell-through:     %d%%"):format(
            math.floor(summary.sellThrough * 100 + 0.5)))
    end

    if summary.sold > 0 then
        ns.PrintRaw(("  taken in:         %s%s"):format(Util.FormatMoney(summary.net),
            summary.estimated > 0
                and ("   (%d still being paid out)"):format(summary.estimated) or ""))

        if summary.cut > 0 then
            ns.PrintRaw(("    auction cut:    %s"):format(Util.FormatMoney(summary.cut)))
        end

        local perSale = summary.net / summary.sold
        ns.PrintRaw(("  average sale:     %s"):format(Util.FormatMoney(perSale)))

        -- The comparison worth having: what the Profit tab promised against
        -- what the auction house paid. Deposits lost on listings that came
        -- back are part of that answer and are easy to forget.
        local analysis = ns.Profit:Analyse(recipe.recipeID or recipe.id)

        if analysis and analysis.priceable then
            ns.PrintRaw(("  estimated at:     %s per unit"):format(
                Util.FormatMoney(analysis.unitRevenue)))
        end
    end
end)
