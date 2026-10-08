-- Blackthornes Tradeskills -- Logic/MailTake.lua
-- Taking a whole kind of mail in one go.
--
-- Ezmode (2026-10-07): "Buttons to withdraw Sales, Expired Auctions,
-- Cancelled Auctions." Four groups, one button each (UI/MailTakeBar.lua):
--
--   sales     -- the gold from "Auction successful" mail
--   expired   -- the items from "Auction expired" mail
--   cancelled -- the items from "Auction cancelled" mail
--   all       -- gold and items from every mail, the three above included
--
-- What it never does: touch mail asking for payment (COD), delete mail, or
-- send anything. An auction mail the game empties goes away by itself; a
-- letter with words in it stays.
--
-- How it takes. The server answers one take at a time, so this takes one
-- thing, then waits for the inbox to change (MAIL_INBOX_UPDATE) before
-- reading the inbox afresh and taking the next. Indices shift as mail
-- empties, so nothing is remembered between takes but what was asked for.
-- "Internal mail database error" means too fast: it waits longer and tries
-- again, and gives up after a few in a row. The bags filling stops the item
-- takes, never the gold.
--
-- The client shows 50 mails at most; the rest come in after some are taken
-- and the server refreshes, about once a minute. With nothing left to take
-- in what shows and more waiting, it asks for the inbox again and carries on
-- when it arrives, for as long as the mailbox stays open.
--
-- The sales ledger (Data/Mail.lua) writes a sale down when its mail is first
-- read, so a take starts only once the inbox has been read this visit. The
-- gold log and the haul report watch the same take calls whoever makes them,
-- which is why each is looked up on _G at the moment it is called.

local _, ns = ...

local MailTake = ns.NewModule("MailTake")

MailTake.GROUPS = { "sales", "expired", "cancelled", "all" }

-- Seconds between looks while a take waits for the server.
local TICK = 0.3
-- The least time between one take and the next.
local MIN_GAP = 0.4
-- How long to wait for the inbox to change after a take before reading it
-- anyway. A take the server refused leaves the mail as it was.
local ANSWER_WAIT = 3
-- Seconds to back off after "Internal mail database error".
local BACKOFF = 2
-- That error this many times in a row stops the run.
local MAX_ERRORS = 5
-- The same mail and slot picked this many times without leaving: skip it.
local MAX_TRIES = 3
-- A hard ceiling on take calls in one run, so a miscount can never loop.
local MAX_TAKES = 600
-- How often to ask for more mail while waiting on the server's next 50, and
-- how long to wait with nothing arriving before stopping.
local ASK_EVERY = 20
local WAIT_FOR_MORE = 180

local MAX_SLOTS = 16

local function Call(fn, ...)
    if type(fn) ~= "function" then return false end
    return pcall(fn, ...)
end

local function Now()
    if type(GetTime) == "function" then
        local ok, now = pcall(GetTime)
        if ok and type(now) == "number" then return now end
    end
    return os.time()
end

local function After(seconds, fn)
    if C_Timer and C_Timer.After then
        C_Timer.After(seconds, fn)
    else
        fn()
    end
end

local function MaxSlots()
    local max = tonumber(_G.ATTACHMENTS_MAX_RECEIVE)
    if max and max > 0 then return max end
    return MAX_SLOTS
end

--------------------------------------------------------------------------------
-- Reading the inbox
--------------------------------------------------------------------------------

--- What kind of mail this is: "sold", "expired", "removed", "won",
--- "outbid" or "other". The haul report's sorting, so the two agree.
local function Kind(mail)
    if ns.MailHaul and ns.MailHaul.Classify then
        local ok, kind = pcall(ns.MailHaul.Classify, ns.MailHaul, mail)
        if ok and kind then return kind end
    end
    if ns.Mail and ns.Mail.Classify then
        local ok, kind = pcall(ns.Mail.Classify, ns.Mail, mail)
        if ok and kind then return kind end
    end
    return "other"
end

--- The first slot with something in it, or nil when none has loaded.
local function FirstSlot(index)
    for slot = 1, MaxSlots() do
        local itemID
        if ns.Mail and ns.Mail.ReadAttachment then
            local ok, id = pcall(ns.Mail.ReadAttachment, ns.Mail, index, slot)
            if ok then itemID = id end
        end
        if itemID then return slot, itemID end
    end
end

--- Every mail the client shows, plain values only.
-- @return list of { index, sender, subject, money, cod, itemCount, kind },
--         how many the server holds (nil when the client does not say)
function MailTake:ReadInbox()
    local mails = {}
    local okCount, shown, total = Call(_G.GetInboxNumItems)
    if not okCount then return mails, nil end

    shown = tonumber(shown) or 0
    for index = 1, shown do
        local ok, mail = pcall(function()
            local _, _, sender, subject, money, cod, _, itemCount = GetInboxHeaderInfo(index)
            return {
                index = index,
                sender = type(sender) == "string" and sender or nil,
                subject = type(subject) == "string" and subject or nil,
                money = tonumber(money) or 0,
                cod = tonumber(cod) or 0,
                itemCount = tonumber(itemCount) or 0,
            }
        end)
        if ok and mail then
            mail.kind = Kind(mail)
            mails[#mails + 1] = mail
        end
    end

    local okTotal, server = pcall(function() return tonumber(total) end)
    return mails, okTotal and server or nil, shown
end

--- Does this mail belong to the group, and what can be taken from it?
-- @return wantsGold, wantsItems
function MailTake.Wants(group, mail, run)
    if (mail.cod or 0) > 0 then return false, false end
    local gold, items = (mail.money or 0) > 0, (mail.itemCount or 0) > 0

    -- One mail (the Tradeskills mailbox, UI/MailWindow.lua): known by its
    -- place, sender and subject, so a mail sliding into that place after
    -- the one above empties is not taken by mistake.
    if group == "one" then
        local mine = run and mail.index == run.index
            and mail.sender == run.sender and mail.subject == run.subject
        return mine and gold or false, mine and items or false
    end

    if group == "sales" then return mail.kind == "sold" and gold, false end
    if group == "expired" then return false, mail.kind == "expired" and items end
    if group == "cancelled" then return false, mail.kind == "removed" and items end
    if group == "all" then return gold, items end
    return false, false
end

--- What a group would take from the mail showing now.
-- @return { mails, gold, items, more } (items counts mails' attachments)
function MailTake:Count(group, mails)
    local summary = { mails = 0, gold = 0, items = 0 }
    local total, shown
    if not mails then mails, total, shown = self:ReadInbox() end

    for _, mail in ipairs(mails) do
        local gold, items = MailTake.Wants(group, mail)
        if gold or items then
            summary.mails = summary.mails + 1
            if gold then summary.gold = summary.gold + mail.money end
            if items then summary.items = summary.items + mail.itemCount end
        end
    end

    if total and shown and total > shown then summary.more = total - shown end
    return summary
end

--------------------------------------------------------------------------------
-- Taking
--------------------------------------------------------------------------------

local function BagsHaveRoom()
    if not (ns.BagsFull and ns.BagsFull.CountFree) then return true end
    local ok, free = pcall(ns.BagsFull.CountFree, ns.BagsFull)
    if not ok or type(free) ~= "number" then return true end
    return free > 0
end

--- The next thing the run should take, read from the inbox as it is now.
local function Signature(mail)
    return table.concat({ tostring(mail.subject), tostring(mail.sender), mail.money, mail.itemCount }, "|")
end

--- Did the last take land? It did when the mail it took from changed or
--- left. Counted only then, so a take the server refused (too fast, bags
--- full) is neither counted nor lost: the mail is still there to pick.
local function Settle(run, mails)
    local pending = run.pending
    if not pending then return end
    run.pending = nil

    local mail = mails[pending.pick.index]
    if #mails ~= pending.shown or not mail or Signature(mail) ~= pending.signature then
        run.tries[pending.pick.key] = nil
        run.errors = 0
        if pending.pick.money then
            run.gold = run.gold + pending.pick.money
        else
            run.stacks = run.stacks + 1
        end
    end
end

--- The next thing the run should take, read from the inbox as it is now.
local function Pick(run, mails)
    for _, mail in ipairs(mails) do
        local gold, items = MailTake.Wants(run.group, mail, run)
        if gold then
            local key = "gold:" .. mail.index
            if (run.tries[key] or 0) < MAX_TRIES then
                return { index = mail.index, money = mail.money, key = key }, mail
            end
        end
        if items and not run.bagsFull then
            local slot, itemID = FirstSlot(mail.index)
            if slot then
                local key = "item:" .. mail.index .. ":" .. slot
                if (run.tries[key] or 0) < MAX_TRIES then
                    return { index = mail.index, slot = slot, itemID = itemID, key = key }, mail
                end
            else
                -- Declared but not loaded yet: worth waiting for.
                run.loading = true
            end
        end
    end
end

local function Finish(run, why)
    if MailTake.run ~= run then return end
    if run.pending and ns.Mail and ns.Mail.isOpen then
        Settle(run, (MailTake:ReadInbox()))
    end
    MailTake.run = nil
    run.done = true
    run.why = why
    if run.onDone then pcall(run.onDone, run) end
    if run.onChange then pcall(run.onChange, run) end
end

local Step

local function Later(run, seconds)
    After(seconds, function() Step(run) end)
end

Step = function(run)
    if MailTake.run ~= run then return end
    if run.stopped then return Finish(run, run.why or "stopped") end
    if not (ns.Mail and ns.Mail.isOpen) then return Finish(run, "closed") end

    local now = Now()

    -- Backing off after the server said slow down.
    if run.holdUntil and now < run.holdUntil then return Later(run, TICK) end
    run.holdUntil = nil

    -- After a take, wait for the inbox to change, or long enough that it
    -- is not going to.
    if run.lastTake then
        local since = now - run.lastTake
        if since < MIN_GAP or (not run.answered and since < ANSWER_WAIT) then
            return Later(run, TICK)
        end
    end

    if run.takes >= MAX_TAKES then return Finish(run, "limit") end

    local mails, total, shown = MailTake:ReadInbox()
    Settle(run, mails)
    run.more = (total and shown and total > shown) and (total - shown) or nil

    run.loading = false
    local pick, mail = Pick(run, mails)

    if not pick then
        if run.loading then
            -- Attachments still loading: give them a moment.
            run.waitingSince = run.waitingSince or now
            if now - run.waitingSince < ANSWER_WAIT * 2 then return Later(run, TICK * 2) end
        end
        if run.more then
            -- The server holds more than the client shows. Ask again now
            -- and then, and carry on when the inbox grows.
            run.waitingSince = run.waitingSince or now
            if now - run.waitingSince > WAIT_FOR_MORE then return Finish(run, "more") end
            if not run.askedAt or now - run.askedAt >= ASK_EVERY then
                run.askedAt = now
                Call(_G.CheckInbox)
            end
            if not run.waiting then
                run.waiting = true
                if run.onChange then pcall(run.onChange, run) end
            end
            return Later(run, 1)
        end
        return Finish(run, run.bagsFull and "bags" or "done")
    end

    run.waitingSince, run.waiting = nil, false

    if pick.slot and not BagsHaveRoom() then
        run.bagsFull = true
        return Step(run)
    end

    run.tries[pick.key] = (run.tries[pick.key] or 0) + 1
    run.lastTake = now
    run.answered = false
    run.pending = { pick = pick, shown = #mails, signature = Signature(mail) }

    -- Looked up now, not cached: the gold log watches these calls.
    local ok
    if pick.money then
        ok = Call(_G.TakeInboxMoney, pick.index)
    else
        ok = Call(_G.TakeInboxItem, pick.index, pick.slot)
    end
    if not ok then
        run.pending = nil
        return Finish(run, "refused")
    end

    run.takes = run.takes + 1
    if run.onChange then pcall(run.onChange, run) end

    Later(run, MIN_GAP)
end

--- Is a run going?
function MailTake:IsRunning()
    return self.run ~= nil
end

--- Why a group can't start now, or nil when it can.
function MailTake:CannotStart()
    if self.run then return "already taking mail" end
    if not (ns.Mail and ns.Mail.isOpen) then return "the mailbox is not open" end
    if type(_G.TakeInboxMoney) ~= "function" or type(_G.TakeInboxItem) ~= "function" then
        return "this version of the game does not let addons take mail"
    end
    if ns.QueueMail and (ns.QueueMail.taking or ns.QueueMail.filling) then
        return "still busy with the queue's mail"
    end
    if not ns.Mail.inboxUpdatedThisVisit then return "the mailbox is still loading" end
    return nil
end

--- Take every mail of a group.
-- @param group "sales" | "expired" | "cancelled" | "all"
-- @param opts { onChange = function(run), onDone = function(run) }
--        run carries gold (copper taken), stacks, waiting, more, and when
--        done, why: "done" | "bags" | "more" | "stopped" | "closed" |
--        "errors" | "refused" | "limit"
-- @return run, or nil and why not
function MailTake:Start(group, opts)
    local valid = false
    for _, name in ipairs(self.GROUPS) do
        if name == group then valid = true end
    end
    if not valid then return nil, "no such kind of mail" end

    local why = self:CannotStart()
    if why then return nil, why end

    -- The ledger reads the inbox before anything leaves it, so every sale
    -- is written down first.
    if ns.Mail and ns.Mail.Read then pcall(ns.Mail.Read, ns.Mail) end

    opts = opts or {}
    local run = {
        group = group, gold = 0, stacks = 0, takes = 0, errors = 0, tries = {},
        onChange = opts.onChange, onDone = opts.onDone,
    }
    self.run = run
    Step(run)
    return run
end

--- Take everything from one mail (not COD), as the inbox shows it now.
-- @param index the mail's place in the inbox
-- @return run, or nil and why not
function MailTake:StartOne(index, opts)
    local why = self:CannotStart()
    if why then return nil, why end

    local target
    for _, mail in ipairs((self:ReadInbox())) do
        if mail.index == index then target = mail end
    end
    if not target then return nil, "that mail is gone" end
    if target.cod > 0 then return nil, "it asks for payment (COD)" end

    if ns.Mail and ns.Mail.Read then pcall(ns.Mail.Read, ns.Mail) end

    opts = opts or {}
    local run = {
        group = "one", index = index, sender = target.sender, subject = target.subject,
        gold = 0, stacks = 0, takes = 0, errors = 0, tries = {},
        onChange = opts.onChange, onDone = opts.onDone,
    }
    self.run = run
    Step(run)
    return run
end

--- Stop the run after the take in flight.
function MailTake:Stop()
    if self.run then self.run.stopped = true end
end

--------------------------------------------------------------------------------
-- What the game says back
--------------------------------------------------------------------------------

function MailTake:OnInboxUpdate()
    local run = self.run
    if run then run.answered = true end
end

function MailTake:OnError(message)
    local run = self.run
    if not run or type(message) ~= "string" then return end

    -- The take that drew it is left uncounted by Settle, since its mail
    -- did not change, and is picked again after the wait.
    if _G.ERR_MAIL_DATABASE_ERROR and message == _G.ERR_MAIL_DATABASE_ERROR then
        run.errors = run.errors + 1
        if run.errors >= MAX_ERRORS then
            run.stopped = true
            run.why = "errors"
            return
        end
        run.holdUntil = Now() + BACKOFF * run.errors
        run.answered = true
        return
    end

    if (_G.ERR_INV_FULL and message == _G.ERR_INV_FULL)
        or (_G.ERR_BAG_FULL and message == _G.ERR_BAG_FULL) then
        run.bagsFull = true
        run.answered = true
    end
end

function MailTake:OnEnable()
    ns.RegisterEvent(self, "MAIL_INBOX_UPDATE", function() MailTake:OnInboxUpdate() end)
    -- Errors come as (type, message) on this engine, (message) on old ones.
    ns.RegisterEvent(self, "UI_ERROR_MESSAGE", function(_, _, first, second)
        local message = type(second) == "string" and second or first
        MailTake:OnError(message)
    end)
    ns.RegisterEvent(self, "MAIL_CLOSED", function()
        if MailTake.run then MailTake:Stop() end
    end)
end
