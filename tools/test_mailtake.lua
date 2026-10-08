-- Take sales, expired, cancelled or all at the mailbox (Ezmode, 2026-10-07).
--
-- One take at a time, waiting for the inbox to change between takes; never
-- COD mail; bags filling stops the items and not the gold; the server's
-- "Internal mail database error" backs off and tries again; mail beyond the
-- 50 the client shows is waited for.

local ns = {}
ns.Print, ns.PrintRaw, ns.Debug, ns.Warn =
    function() end, function() end, function() end, function() end
ns.NewModule = function(name) local m = {}; ns[name] = m; return m end
local handlers = {}
ns.RegisterEvent = function(_, event, fn) handlers[event] = fn; return true end

local passed, failed = 0, 0
local function expect(label, got, want)
    if got == want then
        passed = passed + 1
        print(("  ok    %s"):format(label))
    else
        failed = failed + 1
        print(("  FAIL  %s: expected %s, got %s"):format(label, tostring(want), tostring(got)))
    end
end

-- A clock and timers the test drives.
local clock = 0
GetTime = function() return clock end
local timers = {}
C_Timer = { After = function(seconds, fn) timers[#timers + 1] = { at = clock + seconds, fn = fn } end }

AUCTION_SOLD_MAIL_SUBJECT = "Auction successful: %s"
AUCTION_EXPIRED_MAIL_SUBJECT = "Auction expired: %s"
AUCTION_REMOVED_MAIL_SUBJECT = "Auction cancelled: %s"
ERR_MAIL_DATABASE_ERROR = "Internal mail database error"
ERR_INV_FULL = "Inventory is full."
ATTACHMENTS_MAX_RECEIVE = 16

-- The server's mail; the client shows the first SHOW_MAX.
local SHOW_MAX = 50
local server, shown = {}, 0
local function Sold(name, money) return { subject = "Auction successful: " .. name, money = money, items = {} } end
local function Expired(name, id) return { subject = "Auction expired: " .. name, money = 0, items = { { itemID = id, count = 1 } } } end
local function Cancelled(name, id) return { subject = "Auction cancelled: " .. name, money = 0, items = { { itemID = id, count = 5 } } } end
local function Letter(money, id) return { subject = "Hi", sender = "Bob", money = money, items = id and { { itemID = id, count = 1 } } or {} } end
local function Cod(id) return { subject = "Pay me", sender = "Stranger", money = 0, cod = 1000, items = { { itemID = id, count = 1 } } } end

local function Refresh() shown = math.min(#server, SHOW_MAX) end

local function ItemCount(mail)
    local n = 0
    for _ in pairs(mail.items) do n = n + 1 end
    return n
end

GetInboxNumItems = function() return shown, #server end
GetInboxHeaderInfo = function(index)
    local mail = server[index]
    if not mail or index > shown then return end
    return nil, nil, mail.sender or "Auction House", mail.subject, mail.money, mail.cod or 0, 30, ItemCount(mail)
end

ns.Mail = {
    isOpen = true,
    inboxUpdatedThisVisit = true,
    reads = 0,
    Read = function(self) self.reads = self.reads + 1 end,
    ReadAttachment = function(_, index, slot)
        local mail = index <= shown and server[index]
        local item = mail and mail.items[slot]
        if item then return item.itemID, item.count end
    end,
    Classify = function(_, mail)
        for kind, prefix in pairs({ sold = "Auction successful: ", expired = "Auction expired: ",
            removed = "Auction cancelled: " }) do
            if type(mail.subject) == "string" and mail.subject:sub(1, #prefix) == prefix then
                return kind, mail.subject:sub(#prefix + 1)
            end
        end
    end,
}

local free = 100
ns.BagsFull = { CountFree = function() return free end }

local purse, bag = 0, {}
local pendingInbox = false
local refuseNext = false

-- An auction mail emptied goes away; a letter stays.
local function Tidy(index)
    local mail = server[index]
    if mail.money == 0 and next(mail.items) == nil and mail.subject ~= "Hi" then
        table.remove(server, index)
        shown = shown - 1
    end
    pendingInbox = true
end

local takeLog = {}
TakeInboxMoney = function(index)
    takeLog[#takeLog + 1] = "money"
    if refuseNext then
        refuseNext = false
        handlers.UI_ERROR_MESSAGE(nil, "UI_ERROR_MESSAGE", 1, ERR_MAIL_DATABASE_ERROR)
        return
    end
    local mail = server[index]
    purse = purse + mail.money
    mail.money = 0
    Tidy(index)
end
TakeInboxItem = function(index, slot)
    takeLog[#takeLog + 1] = "item"
    local mail = server[index]
    if free <= 0 then
        handlers.UI_ERROR_MESSAGE(nil, "UI_ERROR_MESSAGE", 2, ERR_INV_FULL)
        return
    end
    local item = mail.items[slot]
    bag[item.itemID] = (bag[item.itemID] or 0) + item.count
    mail.items[slot] = nil
    free = free - 1
    Tidy(index)
end
local checks = 0
CheckInbox = function() checks = checks + 1 end

assert(loadfile(lfs_cwd .. "/Logic/MailTake.lua"))("Blackthornes_TS", ns)
local MailTake = ns.MailTake
MailTake:OnEnable()

-- Run the clock until nothing is left to do, the server answering each take
-- a moment after it is made.
local function Pump(limit)
    for _ = 1, limit or 5000 do
        if #timers == 0 then return end
        table.sort(timers, function(a, b) return a.at < b.at end)
        local timer = table.remove(timers, 1)
        clock = math.max(clock, timer.at)
        if pendingInbox then
            pendingInbox = false
            handlers.MAIL_INBOX_UPDATE()
        end
        timer.fn()
    end
end

local function Reset(list)
    server, purse, bag, free, takeLog, timers = list, 0, {}, 100, {}, {}
    Refresh()
end

--------------------------------------------------------------------------------
print("")
print("Counting")

Reset({ Sold("Linen Cloth (20)", 500), Sold("Copper Bar", 300), Expired("Copper Bar", 2840),
    Cancelled("Wool Cloth", 2592), Letter(100, 4306), Cod(2840) })

local sales = MailTake:Count("sales")
expect("two sales", sales.mails, 2)
expect("their gold", sales.gold, 800)
expect("one expired", MailTake:Count("expired").mails, 1)
expect("one cancelled", MailTake:Count("cancelled").mails, 1)
local all = MailTake:Count("all")
expect("all: everything but the COD mail", all.mails, 5)
expect("all: gold includes the letter's", all.gold, 900)

--------------------------------------------------------------------------------
print("")
print("Take sales")

local done
local run = MailTake:Start("sales", { onDone = function(r) done = r end })
expect("it starts", run ~= nil, true)
expect("the ledger reads the inbox first", ns.Mail.reads, 1)
expect("one take before the server answers", #takeLog, 1)
Pump()
expect("finished", done and done.why, "done")
expect("all the sale gold", purse, 800)
expect("counted", done.gold, 800)
expect("only gold was taken", bag[2840], nil)
expect("the sale mails are gone", #server, 4)
expect("the COD mail is still there", server[#server].cod, 1000)

--------------------------------------------------------------------------------
print("")
print("Take expired, then cancelled")

done = nil
MailTake:Start("expired", { onDone = function(r) done = r end })
Pump()
expect("expired item taken", bag[2840], 1)
expect("one stack", done.stacks, 1)
expect("the COD mail's item stays", server[#server].items[1] ~= nil, true)

done = nil
MailTake:Start("cancelled", { onDone = function(r) done = r end })
Pump()
expect("cancelled stack taken", bag[2592], 5)
expect("the letter is untouched by cancelled", server[1].money, 100)

--------------------------------------------------------------------------------
print("")
print("Take all")

done = nil
MailTake:Start("all", { onDone = function(r) done = r end })
Pump()
expect("the letter's gold", purse, 900)
expect("the letter's item", bag[4306], 1)
expect("the letter stays, empty", server[1].subject, "Hi")
expect("COD never taken", server[2].cod, 1000)
expect("COD item still there", server[2].items[1] ~= nil, true)
expect("done", done.why, "done")

--------------------------------------------------------------------------------
print("")
print("Waiting for the server between takes")

Reset({ Sold("A", 1), Sold("B", 2), Sold("C", 3) })
local gaps = {}
local lastAt
local inner = TakeInboxMoney
TakeInboxMoney = function(index)
    if lastAt then gaps[#gaps + 1] = clock - lastAt end
    lastAt = clock
    inner(index)
end
MailTake:Start("sales")
Pump()
expect("three takes", #gaps, 2)
local spaced = true
for _, gap in ipairs(gaps) do if gap < 0.4 then spaced = false end end
expect("never closer than the gap", spaced, true)
TakeInboxMoney = inner

--------------------------------------------------------------------------------
print("")
print("A watcher put on the call later still sees it")

Reset({ Sold("A", 10) })
local watched = 0
local original = TakeInboxMoney
TakeInboxMoney = function(...) watched = watched + 1; return original(...) end
MailTake:Start("sales")
Pump()
expect("the call went through the watcher", watched, 1)
TakeInboxMoney = original

--------------------------------------------------------------------------------
print("")
print("Mail database error")

Reset({ Sold("A", 10), Sold("B", 20) })
refuseNext = true
done = nil
MailTake:Start("sales", { onDone = function(r) done = r end })
Pump()
expect("backed off and took it all", purse, 30)
expect("gold counted once", done.gold, 30)

--------------------------------------------------------------------------------
print("")
print("Bags full")

Reset({ Expired("X", 1), Expired("Y", 2), Sold("Z", 50), Expired("W", 3) })
free = 1
done = nil
MailTake:Start("all", { onDone = function(r) done = r end })
Pump()
expect("one item fitted", bag[1], 1)
expect("the gold still came", purse, 50)
expect("stopped for the bags", done.why, "bags")
expect("one stack counted", done.stacks, 1)

--------------------------------------------------------------------------------
print("")
print("More than the client shows")

local many = {}
for i = 1, 70 do many[i] = Sold("S" .. i, 1) end
Reset(many)
expect("shows 50", shown, 50)
done = nil
MailTake:Start("sales", { onDone = function(r) done = r end })
-- The server sends the rest when asked.
CheckInbox = function()
    checks = checks + 1
    Refresh()
    pendingInbox = true
end
Pump(20000)
expect("all 70 taken", purse, 70)
expect("asked for more", checks > 0, true)
expect("done", done and done.why, "done")

--------------------------------------------------------------------------------
print("")
print("Identical sales, and a mail that will not come out")

Reset({ Sold("Linen Cloth (20)", 100), Sold("Linen Cloth (20)", 100), Sold("Linen Cloth (20)", 100) })
done = nil
MailTake:Start("sales", { onDone = function(r) done = r end })
Pump()
expect("three alike, all taken", purse, 300)
expect("counted", done.gold, 300)

Reset({ Sold("Stuck", 100) })
local stuck = TakeInboxMoney
TakeInboxMoney = function() takeLog[#takeLog + 1] = "money" end
done = nil
MailTake:Start("sales", { onDone = function(r) done = r end })
Pump()
expect("gives up on it", done and done.why, "done")
expect("after a few tries", #takeLog, 3)
expect("nothing counted", done.gold, 0)
TakeInboxMoney = stuck

--------------------------------------------------------------------------------
print("")
print("Refusing to start")

Reset({ Sold("A", 1) })
ns.Mail.inboxUpdatedThisVisit = false
local none, why = MailTake:Start("sales")
expect("not before the inbox is read", none, nil)
expect("says why", why, "the mailbox is still loading")
ns.Mail.inboxUpdatedThisVisit = true

ns.QueueMail = { taking = true }
none = MailTake:Start("sales")
expect("not while the queue takes", none, nil)
ns.QueueMail = nil

MailTake:Start("sales")
none = MailTake:Start("all")
expect("one run at a time", none, nil)
Pump()

--------------------------------------------------------------------------------
print("")
print("Stop and close")

Reset({ Sold("A", 1), Sold("B", 2), Sold("C", 3) })
done = nil
MailTake:Start("sales", { onDone = function(r) done = r end })
MailTake:Stop()
Pump()
expect("stopped", done.why, "stopped")
expect("only the first was taken", purse, 1)

Reset({ Sold("A", 1), Sold("B", 2) })
done = nil
MailTake:Start("sales", { onDone = function(r) done = r end })
ns.Mail.isOpen = false
handlers.MAIL_CLOSED()
Pump()
expect("closing the mailbox stops it", done.why == "stopped" or done.why == "closed", true)
expect("nothing more taken", purse, 1)
ns.Mail.isOpen = true

print("")
print(("%d passed, %d failed"):format(passed, failed))
if failed > 0 then error("mail take tests failed") end
