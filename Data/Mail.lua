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

        -- Every slot, not the first `declared` of them. Attachments keep their
        -- slot numbers: take the first stack of three from a mail and the two
        -- left are in slots 2 and 3, so a walk of slots 1 and 2 found one,
        -- called the mail "still loading" for ever and never counted the third.
        for slot = 1, (declared > 0 and MAX_ATTACHMENTS or 0) do
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

    -- An empty list before the server has answered the mailbox's first inbox
    -- request is not an empty mailbox. Trusting it emptied the stock counts
    -- and forgot every mail already recorded, so the next update wrote each
    -- sale down a second time.
    -- The same holds when the mailbox was shut before the server answered:
    -- bumping one and pressing Escape used to land here with nothing listed.
    if #mails == 0 and not self.inboxUpdatedThisVisit then
        ns.Debug("mailbox: nothing listed yet, waiting for the inbox")
        return
    end

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

    -- What left the mailbox since the last reading is what was collected,
    -- which is what the report after a mailbox visit is made of.
    if ns.MailHaul then ns.MailHaul:Observe(mails, complete) end

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

-- Logic/MailHaul.lua classifies mail for the collection report the same way.
Mail.SubjectPattern = SubjectPattern

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

    -- Each output once.
    local outputs, seen = {}, {}
    for _, recipe in pairs(source) do
        local itemID = type(recipe) == "table" and recipe.outputItemID
        if itemID and not seen[itemID] then
            seen[itemID] = true
            outputs[#outputs + 1] = itemID
        end
    end

    -- Only items the client already holds are looked at. Asking about one it
    -- does not would fetch it into the small item cache, and a walk over
    -- hundreds of outputs for every new sale pushed bag items out of it.
    local canAsk = Util.HasFunction("C_Item.IsItemDataCachedByID")

    for _, itemID in ipairs(outputs) do
        if found then break end

        local cached = true
        if canAsk then
            local ok, answer = pcall(C_Item.IsItemDataCachedByID, itemID)
            cached = ok and answer == true
        end

        if cached then
            local ok, itemName = pcall(C_Item.GetItemInfo, itemID)
            if ok and itemName == name then found = itemID end
        end
    end

    -- Only a hit is remembered. The name of an item the client has not cached
    -- yet comes back nil, and a miss remembered for the session would leave
    -- every later sale of that item filed by name only. This runs once per
    -- new sale, not per redraw, so the walk is affordable.
    if found then self.nameCache[name] = found end

    return found
end

--- Crafted items the addon knows of, as a set. Kept for the session: it is
--- asked on every item the game loads, and walking every recipe each time
--- would be wasted work.
function Mail:OutputSet()
    if self.outputSet then return self.outputSet end

    local source = ns.Recipes and ns.Recipes.GetAccountWide
        and ns.Recipes:GetAccountWide() or (ns.Recipes and ns.Recipes:GetAll()) or {}

    local set = {}
    for _, recipe in pairs(source) do
        local itemID = type(recipe) == "table" and recipe.outputItemID
        if itemID then set[itemID] = true end
    end

    self.outputSet = set
    return set
end

--- A sale filed by name only gets its item once the game loads that item.
--
-- A sale mail names its item but has no attachment, and ResolveItemName only
-- looks at items the game already holds. So a crafted item sold before the
-- game had loaded it was filed by name. GET_ITEM_INFO_RECEIVED calls this for
-- each item the game loads for any reason (bags, tooltips, a scan), which
-- fills those sales in without asking the game to load anything itself.
function Mail:FillItemID(itemID)
    if type(itemID) ~= "number" or not ns.db then return end

    local ledger = self:GetLedger()

    -- The names still waiting, worked out again only when the ledger gains
    -- an entry. Nothing waiting is the usual case, and costs nothing.
    if self.unresolvedFor ~= ledger then
        self.unresolved = {}
        for _, entry in ipairs(ledger.entries) do
            if entry.kind == "sold" and not entry.itemID and entry.name then
                self.unresolved[entry.name] = true
            end
        end
        self.unresolvedFor = ledger
    end

    if not next(self.unresolved) or not self:OutputSet()[itemID] then return end

    -- The game just loaded this item, so reading its name asks for nothing.
    local ok, name = pcall(C_Item.GetItemInfo, itemID)
    if not ok or type(name) ~= "string" or not self.unresolved[name] then return end

    local filled = 0
    for _, entry in ipairs(ledger.entries) do
        if entry.kind == "sold" and not entry.itemID and entry.name == name then
            entry.itemID = itemID
            filled = filled + 1
        end
    end

    self.unresolved[name] = nil
    self.nameCache = self.nameCache or {}
    self.nameCache[name] = itemID
    ns.Debug(("mail: %d sale(s) of %s now know their item"):format(filled, name))
end

-- How many days the auction house's mail stays in the box. daysLeft counts
-- down from here, so it also says when the mail was sent.
local AUCTION_MAIL_DAYS = 30

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

            -- One listing can come back as several stacks in one mail. The
            -- first stack alone undercounted what came back.
            entry.quantity = 0
            for _, stack in ipairs(mail.attachments) do
                if stack.itemID == attachment.itemID then
                    entry.quantity = entry.quantity + (stack.quantity or 0)
                end
            end
        end

        -- When it was sent back, which is when the auction ended. The inbox
        -- can be read long after, and Data/Auctions.lua needs to know whether
        -- the stack was still listed when your auctions were last read.
        -- Taken off a reading that had already left it out, 5 still listed
        -- read as none.
        if mail.daysLeft then
            local sent = entry.t - math.floor((AUCTION_MAIL_DAYS - mail.daysLeft) * 86400 + 0.5)
            entry.sent = math.min(entry.t, sent)
        end
    end

    return entry
end

--- A sale recorded while its gold was held, now paid: the estimated entry
--- for this same sale takes the mail's real amount.
--
-- Every paid sale mail comes through here on each inbox read, including ones
-- that were paid when first seen. Matching on the item name alone let one of
-- those settle a different, still-held sale of the same item with its own
-- amount. So the entry must also carry this mail's invoice estimate: that is
-- what it was written down as while the gold was held.
function Mail:SettleHeldSale(mail)
    local ledger = self:GetLedger()
    if not ledger or not ledger.entries then return end

    local invoice = self:ReadInvoice(mail.index)
    if not (invoice and invoice.bid) then return end

    -- The name as Describe wrote it down: the invoice's, which has no stack
    -- size in it, ahead of the subject's.
    local kind, itemName = self:Classify(mail)
    if kind ~= "sold" and invoice.invoiceType ~= "seller" then return end
    itemName = invoice.itemName or itemName

    local estimate = invoice.bid - (invoice.cut or 0) + (invoice.deposit or 0)

    for index = #ledger.entries, 1, -1 do
        local entry = ledger.entries[index]
        if entry.kind == "sold" and entry.estimated and entry.name == itemName
            and entry.net == estimate then
            entry.net = mail.money
            entry.estimated = nil
            return
        end
    end
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
--- Which mails this character has already written down.
--
-- Kept per character. It was one list for the whole realm, and a mail
-- fingerprint does not say whose mailbox it is in: another character's
-- identical sale read as already seen and was never recorded, and a complete
-- reading by one character wiped the other's list, so its mails were written
-- down a second time on its next visit.
--
-- @return the list, and true when this character has none of its own yet
local function SeenFor(ledger, who)
    ledger.seenBy = ledger.seenBy or {}

    local seen = ledger.seenBy[who]
    if seen then return seen, false end

    -- First reading since lists were kept per character. The old shared list
    -- is the best start there is: it is right for whoever read last.
    seen = {}
    for key, count in pairs(ledger.seen or {}) do seen[key] = count end
    ledger.seenBy[who] = seen
    return seen, true
end

--- On a character's first reading with its own list, a mail missing from the
--- old shared list may still have been written down before the shared list
--- lost it. An entry this character already has for the same thing counts
--- as that mail, once each, so the switch never writes a sale down twice.
local function AlreadyWritten(entries, upTo, used, who, kind, name)
    for index = upTo, 1, -1 do
        local entry = entries[index]
        if not used[index] and entry.who == who and entry.kind == kind and entry.name == name then
            used[index] = true
            return true
        end
    end
    return false
end

--- A returned auction's mail with some of its stacks taken.
---
--- Its fingerprint lists the stacks, so taking one of three made it read as
--- a new mail, and the expiry was written down once per stack taken. It is
--- the same mail when an earlier one from the same sender with the same
--- subject held every stack this one holds and more, and that earlier one is
--- no longer in the box.
--
-- @param gone fingerprint -> how many of it were seen before but are not now
-- @return the earlier fingerprint, or nil
local function Split(key)
    local prefix, stacks = key:match("^(.*)|([^|]*)$")
    if not prefix then return nil end

    local counts = {}
    for stack in stacks:gmatch("[^,]+") do counts[stack] = (counts[stack] or 0) + 1 end
    return prefix, counts
end

local function ShrunkFrom(key, gone)
    local prefix, stacks = Split(key)
    if not prefix or next(stacks) == nil then return nil end

    for earlier, count in pairs(gone) do
        if count > 0 then
            local earlierPrefix, earlierStacks = Split(earlier)

            if earlierPrefix == prefix then
                local holdsAll, holdsMore = true, false

                for stack, n in pairs(stacks) do
                    if (earlierStacks[stack] or 0) < n then holdsAll = false break end
                end
                for stack, n in pairs(earlierStacks) do
                    if n > (stacks[stack] or 0) then holdsMore = true end
                end

                if holdsAll and holdsMore then return earlier end
            end
        end
    end

    return nil
end

Mail._ShrunkFrom = ShrunkFrom

function Mail:Reconcile(mails, complete)
    local ledger = self:GetLedger()
    local who = ns.Config:GetCharacterKey()
    local seen, firstReading = SeenFor(ledger, who)
    local used = {}
    -- Only entries from earlier visits: two identical sales in this reading
    -- are two sales.
    local earlier = #ledger.entries

    -- Counted fresh each reading, not accumulated: it answers "is anything
    -- waiting right now", which is what the diagnostic reports.
    self.awaitingAmount = 0

    local present = {}

    -- Mails seen before and missing from this reading. A returned auction
    -- with a stack taken is one of these under its old fingerprint.
    local inBox = {}
    for _, mail in ipairs(mails) do
        if not mail.pending then
            local key = Fingerprint(mail)
            inBox[key] = (inBox[key] or 0) + 1
        end
    end
    local gone = {}
    for key, count in pairs(seen) do
        if count > (inBox[key] or 0) then gone[key] = count - (inBox[key] or 0) end
    end
    -- How many of each old fingerprint turned out to be a shrunk mail.
    local shrunk = {}

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

            if occurrence > (seen[key] or 0) then
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

                elseif kind ~= "sold" and #mail.attachments == 0 and (mail.money or 0) == 0 then
                    -- An expired or cancelled auction whose item has just been
                    -- taken. The emptied mail lingers for an update or two, and
                    -- with no attachment it fingerprints as a new mail; it was
                    -- written down when it arrived, so it is not written again.
                    ns.Debug("mail already collected:", tostring(mail.subject))

                elseif kind and kind ~= "sold" and ShrunkFrom(key, gone) then
                    -- Some of its stacks were taken; written down when it
                    -- arrived, so not again.
                    local earlier = ShrunkFrom(key, gone)
                    gone[earlier] = gone[earlier] - 1
                    shrunk[earlier] = (shrunk[earlier] or 0) + 1
                    ns.Debug("mail with stacks taken:", tostring(mail.subject))

                elseif kind and firstReading and AlreadyWritten(ledger.entries, earlier, used, who, kind,
                    (kind == "sold" and invoice and invoice.itemName) or itemName) then
                    ns.Debug("mail written down before:", tostring(mail.subject))

                elseif kind then
                    ledger.entries[#ledger.entries + 1] =
                        Describe(mail, kind, itemName, invoice)
                    self.unresolvedFor = nil

                else
                    -- Ordinary mail from a person. Counted as stock above, and
                    -- deliberately not a ledger entry.
                    ns.Debug("mail not from the auction house:", tostring(mail.subject))
                end

            elseif (mail.money or 0) > 0 then
                -- A sale already written down from its invoice while its gold
                -- was held. The gold has now been released, so the entry takes
                -- the real amount and stops saying "gold still held".
                self:SettleHeldSale(mail)
            end
        end
    end

    -- Whatever is in the box now is what has been seen. Taking a mail drops the
    -- count back, so an identical one arriving later reads as new rather than
    -- as one already recorded.
    for key, count in pairs(present) do
        seen[key] = count
    end

    -- A mail that shrank lives on under its new fingerprint, so its old one
    -- is let go even on a half-loaded reading. Kept, it could pass a later,
    -- genuinely new return of the same item off as this one.
    for key, count in pairs(shrunk) do
        if not present[key] and seen[key] then
            seen[key] = seen[key] - count
            if seen[key] <= 0 then seen[key] = nil end
        end
    end

    -- Fingerprints that vanished entirely. Only safe when we saw the whole
    -- inbox: zeroing on a half-loaded reading would re-record everything.
    if complete then
        for key in pairs(seen) do
            if not present[key] then seen[key] = nil end
        end
    end

    while #ledger.entries > MAX_LEDGER do
        table.remove(ledger.entries, 1)
    end
end

--------------------------------------------------------------------------------
-- History carried over from macro storage
--------------------------------------------------------------------------------

-- Until the game kept saved data (build 1.60.1.70009, 2026-09-24), sales
-- history crossed a restart in macros as a per-item rollup: db.sellThrough,
-- with db.sellThroughRolledAt as the moment it was rolled up to. The macro
-- store is gone, but that history is in the saved file now and is still
-- counted. It is frozen: nothing writes to it any more, so every ledger entry
-- after the cutoff is new and every one before it is already inside it.

--- When the carried-over history was rolled up to, for a realm, or nil.
function Mail:LedgerCutoff(realmKey)
    if not ns.db or type(ns.db.sellThroughRolledAt) ~= "table" then return nil end
    return tonumber(ns.db.sellThroughRolledAt[realmKey or ns.Config:GetRealmKey()])
end

--- Is this ledger entry already inside the carried-over history?
function Mail:IsRolledUp(entry, realmKey)
    local cutoff = self:LedgerCutoff(realmKey)
    return cutoff ~= nil and entry.t ~= nil and entry.t <= cutoff
end

--- The carried-over per-item history for this realm, or nil.
function Mail:GetRestoredRollup()
    if not ns.db or not ns.db.sellThrough then return nil end

    local rollup = ns.db.sellThrough[ns.Config:GetRealmKey()]

    if type(rollup) ~= "table" or not next(rollup) then return nil end
    return rollup
end

--------------------------------------------------------------------------------
-- Reading the ledger back
--------------------------------------------------------------------------------

--- What the ledger says about one item, or about everything.
--
-- @param itemID optional; nil totals the lot
-- @return { sold, soldUnits, returned, returnedUnits, expired, cancelled,
--           net, gross, cut, deposit, firstAt, lastAt }
--- Item IDs by name, learned from ledger entries that carry both.
--
-- A sale mail names its item but has no attachment, so a sale gets an id only
-- when the name matches a cached recipe output. Its expiries always have one,
-- from the item that came back. Without this, anything not crafted (cloth
-- sold from the whole-bag Post tab) showed as two rows on the Sales tab, one
-- with the sales and one with the expiries, each with the wrong sell-through.
function Mail:NameIndex()
    local index = {}
    for _, entry in ipairs(self:GetLedger().entries) do
        if entry.itemID and entry.name and not index[entry.name] then
            index[entry.name] = entry.itemID
        end
    end
    return index
end

function Mail:GetSummary(itemID)
    local totals = {
        sold = 0, soldUnits = 0,
        -- `returned` is everything that came back. It is split because the two
        -- halves mean opposite things: an expiry is the auction house telling
        -- you nobody wanted it at that price, a cancellation is you changing
        -- your mind. Only the first is evidence about demand.
        returned = 0, returnedUnits = 0,
        expired = 0, cancelled = 0,
        net = 0, gross = 0, cut = 0, deposit = 0,
        -- Sales priced from the invoice because the gold had not been released
        -- when they were recorded. Real, but not yet in your pocket.
        estimated = 0,
    }

    local names = itemID and self:NameIndex() or {}

    -- An entry from before the restored history was rolled up is already in
    -- that history, added below; counting it here as well was the bug.
    for _, entry in ipairs(self:GetLedger().entries) do
        local rolled = self:IsRolledUp(entry)
        local entryItemID = entry.itemID or names[entry.name]

        if (not itemID or entryItemID == itemID) and not rolled then
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

                if entry.kind == "removed" then
                    totals.cancelled = totals.cancelled + 1
                else
                    totals.expired = totals.expired + 1
                end
            end

            if not totals.firstAt or entry.t < totals.firstAt then totals.firstAt = entry.t end
            if not totals.lastAt or entry.t > totals.lastAt then totals.lastAt = entry.t end
        end
    end

    -- History carried across a client restart in macro storage, which held a
    -- rollup rather than the entries themselves. The ledger above is
    -- everything after it; the two never overlap, because entries up to the
    -- cutoff are skipped above.
    --
    -- Only what a 17-character record can hold comes back: what sold, how
    -- many, what expired, the money, and when. Deposits, the auction house
    -- cut and cancellations are this session's alone, so `restored` is set
    -- for anything that wants to say so rather than quietly showing a gross
    -- that does not match the net.
    local restored = self:GetRestoredRollup()

    if restored then
        for id, record in pairs(restored) do
            if not itemID or id == itemID then
                totals.sold = totals.sold + (record.sold or 0)
                totals.soldUnits = totals.soldUnits + (record.soldUnits or 0)
                totals.expired = totals.expired + (record.expired or 0)
                totals.returned = totals.returned + (record.expired or 0)
                totals.net = totals.net + (record.net or 0)
                totals.restored = true

                local at = record.lastAt
                if at and at > 0 then
                    if not totals.firstAt or at < totals.firstAt then totals.firstAt = at end
                    if not totals.lastAt or at > totals.lastAt then totals.lastAt = at end
                end
            end
        end
    end

    -- The number the Profit tab is really being judged on: of everything the
    -- market got to decide on, how much of it actually sold. Cancellations are
    -- left out on purpose -- pulling a listing yourself says nothing about
    -- whether it would have sold, and counting it as a failure would make any
    -- session of relisting look like the price was wrong.
    local judged = totals.sold + totals.expired
    totals.sellThrough = judged > 0 and (totals.sold / judged) or nil

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

--- The whole ledger folded down to one row per item.
--
-- The same arithmetic GetSummary does for a single item, done once for all of
-- them. A tab drawing a list of forty items would otherwise walk four hundred
-- ledger entries forty times over, on every redraw.
--
-- An entry whose item could not be resolved from its name is still counted --
-- under its name rather than being dropped, which is the same promise
-- ResolveItemName makes.
--
-- @return array of { key, itemID, name, sold, soldUnits, expired, cancelled,
--         returned, net, gross, cut, deposit, estimated, sellThrough, lastAt,
--         restored }
function Mail:GetItems()
    local byKey = {}
    local order = {}

    local function Bucket(itemID, name)
        -- Two different unresolved names must not share a row, and an
        -- unresolved name must not collide with item 0 either, so the string
        -- key is prefixed rather than used bare.
        local key = itemID or ("?" .. tostring(name or "unknown"))
        local bucket = byKey[key]

        if not bucket then
            bucket = {
                key = key, itemID = itemID, name = name,
                sold = 0, soldUnits = 0, expired = 0, cancelled = 0,
                net = 0, gross = 0, cut = 0, deposit = 0, estimated = 0,
            }

            byKey[key] = bucket
            order[#order + 1] = bucket
        end

        -- A later entry can name an item an earlier one only had an id for.
        if not bucket.name then bucket.name = name end

        return bucket
    end

    local names = self:NameIndex()

    for _, entry in ipairs(self:GetLedger().entries) do
        local bucket = Bucket(entry.itemID or names[entry.name], entry.name)

        -- Already inside the restored history added below. The row is still
        -- made, so the item keeps its name.
        if self:IsRolledUp(entry) then
            -- nothing to add

        elseif entry.kind == "sold" then
            bucket.sold = bucket.sold + 1
            bucket.soldUnits = bucket.soldUnits + (entry.quantity or 1)
            bucket.net = bucket.net + (entry.net or 0)
            bucket.gross = bucket.gross + (entry.gross or entry.net or 0)
            bucket.cut = bucket.cut + (entry.cut or 0)
            bucket.deposit = bucket.deposit + (entry.deposit or 0)

            if entry.estimated then bucket.estimated = bucket.estimated + 1 end

        elseif entry.kind == "removed" then
            -- Kept apart from an expiry all the way through: you pulling a
            -- listing says nothing about whether it would have sold.
            bucket.cancelled = bucket.cancelled + 1

        else
            bucket.expired = bucket.expired + 1
        end

        if entry.t and (not bucket.lastAt or entry.t > bucket.lastAt) then
            bucket.lastAt = entry.t
        end
    end

    -- History from before the client was last closed. It survives as a per-item
    -- rollup rather than as entries, so it can only ever appear here and in the
    -- totals -- never in a list of individual sales. `restored` is set so a row
    -- carrying it can say where the numbers came from instead of showing a
    -- gross and a cut that do not add up to the net.
    local restored = self:GetRestoredRollup()

    if restored then
        for itemID, record in pairs(restored) do
            local bucket = Bucket(itemID, nil)

            bucket.sold = bucket.sold + (record.sold or 0)
            bucket.soldUnits = bucket.soldUnits + (record.soldUnits or 0)
            bucket.expired = bucket.expired + (record.expired or 0)
            bucket.net = bucket.net + (record.net or 0)
            bucket.restored = true

            local at = record.lastAt
            if at and at > 0 and (not bucket.lastAt or at > bucket.lastAt) then
                bucket.lastAt = at
            end
        end
    end

    for _, bucket in ipairs(order) do
        bucket.returned = bucket.expired + bucket.cancelled

        local judged = bucket.sold + bucket.expired
        bucket.sellThrough = judged > 0 and (bucket.sold / judged) or nil
    end

    return order
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
    ledger.seenBy = {}

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
        Mail.inboxUpdatedThisVisit = true
        Mail:Read()
    end) and true or false

    ns.RegisterEvent(self, "MAIL_SHOW", function()
        Mail.isOpen = true
        Mail.inboxUpdatedThisVisit = false
        -- The inbox is not ready to be read the instant the frame appears.
        C_Timer.After(0.5, function() if Mail.isOpen then Mail:Read() end end)
    end)

    ns.RegisterEvent(self, "MAIL_CLOSED", function()
        Mail.isOpen = false
    end)

    ns.RegisterEvent(self, "GET_ITEM_INFO_RECEIVED", function(_, _, itemID, success)
        if success ~= false then Mail:FillItemID(itemID) end
    end)

    -- Taking an attachment moves stock from the mailbox to the bags, and both
    -- counts have to move together or the item is briefly counted twice.
    ns.RegisterEvent(self, "MAIL_SEND_SUCCESS", function() Mail:Read() end)
end

--------------------------------------------------------------------------------
-- Diagnostics
--------------------------------------------------------------------------------

--- Every value a call handed back, counted exactly.
--
-- `{ f() }` cannot be trusted to say how many returns there were: a nil in the
-- middle leaves a hole and `#` on a table with a hole is undefined. `select`
-- counts the arguments themselves, so a nil is counted like anything else.
local function PackResults(...)
    return select("#", ...), { ... }
end

ns.RegisterCommand("mail", "[reset]: what is in the mailbox and what has sold", function(args)
    local sub = (args or ""):lower():match("^(%S*)")

    if sub == "reset" then
        local ledger = Mail:GetLedger()
        local entries = #ledger.entries

        if entries == 0 then
            ns.Print("the sales record is already empty")
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
                ns.PrintRaw(("  %d of them show no gold (recorded before an addon fix)"):format(
                    unpriced))
            end

            ns.PrintRaw(("  to go ahead: |c%s/bts mail reset confirm|r"):format(
                ns.COLORS.accent))
            return
        end

        local had = Mail:ResetLedger()
        ns.Print(("cleared %d sales record entr%s"):format(had, had == 1 and "y" or "ies"))
        ns.PrintRaw("  anything still in the mailbox is recorded again next time you open it")

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
        announces = "not in this version of the game"
    elseif (Mail.inboxEventCount or 0) > 0 then
        announces = ("yes, %d time(s) this session"):format(Mail.inboxEventCount)
    else
        announces = "listening, but it has not happened this session"
    end
    ns.PrintRaw(("  change alerts:        %s"):format(announces))

    if Mail.attachmentShape then
        ns.PrintRaw(("  attachment order:     %s"):format(Mail.attachmentShape))
    elseif Mail.shapeUnknown then
        ns.PrintRaw("  attachment order:     could not be checked (no item link)")
    end

    local age = Mail:GetAge()
    ns.PrintRaw(("  last read:            %s"):format(
        age and (Util.FormatAgeAgo(age) .. (Mail:HasReadThisSession() and "" or ", before this session"))
            or "never"))

    if not hasNum then
        ns.Warn("this version of the game does not let addons read the mailbox; mail cannot be counted as stock.")
        return
    end

    if not Mail.isOpen then
        ns.PrintRaw("  (open a mailbox to read it again)")
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
    ns.PrintRaw(("  sales record:         %d sold, %d expired, %d cancelled"):format(
        summary.sold, summary.expired, summary.cancelled))

    if summary.sold > 0 then
        ns.PrintRaw(("    taken in:           %s"):format(Util.FormatMoney(summary.net)))
    end

    if (Mail.awaitingAmount or 0) > 0 then
        ns.PrintRaw(("    gold not paid yet:  %d sale(s)"):format(Mail.awaitingAmount))
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
                    entry.estimated and "   (from the invoice, gold not paid yet)" or ""))
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
        ns.PrintRaw("  what the game says, mail by mail:")

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

            -- Everything the invoice returns past the eight ReadInvoice names.
            --
            -- A sale leaves no attachment -- the item is gone -- so nothing in
            -- the ledger knows whether a stack of twenty sold or a single
            -- item did, and the Sales tab has to leave that column blank. If
            -- this client's invoice carries a count somewhere further along,
            -- this is what will show it. Printed rather than guessed at: a
            -- quantity read out of a slot nobody has looked at would be a
            -- number the tab states with confidence and gets wrong.
            if hasInvoice then
                local count, results = PackResults(pcall(GetInboxInvoiceInfo, mail.index))

                if results[1] and count > 9 then
                    local tail = {}
                    for position = 10, count do
                        tail[#tail + 1] = ("%d=%s"):format(
                            position - 1, tostring(results[position]))
                    end
                    ns.PrintRaw(("       invoice extras: %s"):format(
                        table.concat(tail, "  ")))
                end
            end

            for _, attachment in ipairs(mail.attachments) do
                ns.PrintRaw(("       attached: %dx %s"):format(
                    attachment.quantity, Util.GetItemLabel(attachment.itemID)))
            end

            if mail.pending then
                ns.PrintRaw("       not recorded yet, still loading")
            end
        end
    end
end)

ns.RegisterCommand("sold", "<name or link>: what it really earned, next to the estimate", function(args)
    local recipe, errorMessage, ambiguous = ns.Profit:Resolve(args)

    if ambiguous then
        ns.Print(("several recipes match '%s'. Try /bts why first"):format(args))
        return
    end

    if not recipe or not recipe.outputItemID then
        ns.Print(errorMessage or "type an item name, or shift-click an item")
        return
    end

    local itemID = recipe.outputItemID
    local summary = Mail:GetSummary(itemID)

    ns.Print(Util.GetItemLabel(itemID))

    if summary.sold == 0 and summary.returned == 0 then
        ns.PrintRaw("  nothing recorded yet. Visit a mailbox after a listing ends")
        return
    end

    ns.PrintRaw(("  sold:             %d listing(s)"):format(summary.sold))
    ns.PrintRaw(("  expired:          %d listing(s)"):format(summary.expired))

    -- Shown, but kept out of the ratio below. Pulling a listing yourself is
    -- not the market turning it down.
    if summary.cancelled > 0 then
        ns.PrintRaw(("  you cancelled:    %d listing(s)"):format(summary.cancelled))
    end

    if summary.sellThrough then
        ns.PrintRaw(("  sell-through:     %d%%   (of %d that sold or expired)")
            :format(math.floor(summary.sellThrough * 100 + 0.5),
                summary.sold + summary.expired))
    end

    if summary.sold > 0 then
        ns.PrintRaw(("  taken in:         %s%s"):format(Util.FormatMoney(summary.net),
            summary.estimated > 0
                and ("   (%d still being paid out)"):format(summary.estimated) or ""))

        if summary.cut > 0 then
            ns.PrintRaw(("    auction cut:    %s"):format(Util.FormatMoney(summary.cut)))
        end

        -- Per listing sold: a sale records no quantity, so this is not a
        -- per-unit figure and is labelled so beside the estimate below.
        local perSale = summary.net / summary.sold
        ns.PrintRaw(("  average per sale: %s"):format(Util.FormatMoney(perSale)))

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
