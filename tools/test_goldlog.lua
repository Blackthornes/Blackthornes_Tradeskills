-- Logic/GoldLog.lua outside WoW: gold in and out, and where it came from.
--
--   1. A change is put down to the call that caused it when one was just
--      made, else to the window that is open, else to Other.
--   2. Gold taken off an auction sale mail is an auction sale; gold mailed
--      by one of your own characters is a move, not income.
--   3. Changes add up in hour and day buckets, per realm, with no names.
--   4. A period comes back as bars, and the totals leave moves out.
--   5. Old hours and days are pruned; nothing else is touched.

local savedTime, savedDate = time, date
time = os.time
date = os.date

local ns = {}
ns.NewModule = function(name) local m = {} ns[name] = m return m end
local events = {}
ns.RegisterEvent = function(_, event, fn) events[event] = fn return true end

local realm = "Realm-A"
ns.Config = { GetRealmKey = function() return realm end }
ns.db = { characters = { ["Ana-Realm A"] = {}, ["Bob-Realm A"] = {} } }

local inbox = {}
GetInboxHeaderInfo = function(index)
  local mail = inbox[index]
  if not mail then return nil end
  return nil, nil, mail.sender, mail.subject, mail.money, mail.cod
end
ns.MailHaul = {
  Classify = function(_, mail)
    if mail.subject and mail.subject:find("^Sold") then return "sold" end
    if mail.subject and mail.subject:find("^Outbid") then return "outbid" end
    return "other"
  end,
}

local repairing = false
InRepairMode = function() return repairing end

local chunk = assert(loadfile(lfs_cwd .. "/Logic/GoldLog.lua"))
chunk("Blackthornes_TS", ns)

local GL = ns.GoldLog
local failures = 0

local function check(label, got, want)
  if got ~= want then
    failures = failures + 1
    print(string.format("  FAIL  %-56s got %s, wanted %s", label, tostring(got), tostring(want)))
  else
    print(string.format("  ok    %-56s %s", label, tostring(got)))
  end
end

-- Noon on a fixed day, so hours and days are known.
local NOW = os.time({ year = 2026, month = 10, day = 6, hour = 12 })
time = function(t) if t then return os.time(t) end return NOW end

print("\nwhy the gold moved")
GL:ResetContext()
check("nothing going on: other", GL:Classify(100, NOW), "other")
GL:SetWindow("merchant", true, NOW)
check("at a vendor, gold in: a sale", GL:Classify(100, NOW), "vendorSales")
check("at a vendor, gold out: a purchase", GL:Classify(-100, NOW), "vendorBuys")
repairing = true
check("in repair mode: a repair", GL:Classify(-100, NOW), "repairs")
repairing = false
GL:Tag("repairs", -1, NOW)
check("Repair all just pressed: a repair", GL:Classify(-500, NOW), "repairs")
check("and the tag is spent", GL:Classify(-500, NOW), "vendorBuys")
GL:SetWindow("merchant", false, NOW)
check("just after closing, still the vendor", GL:Classify(100, NOW + 2), "vendorSales")
check("a while after: other", GL:Classify(100, NOW + 30), "other")

GL:ResetContext()
GL:SetWindow("auction", true, NOW)
GL:Tag("auctionFees", -1, NOW)
check("gold in leaves a deposit tag alone", GL:Classify(100, NOW), "auctionSales")
check("a post's deposit", GL:Classify(-40, NOW), "auctionFees")
check("then buying", GL:Classify(-900, NOW), "auctionBuys")
GL:Tag("auctionFees", -1, NOW)
check("a stale tag is not used", GL:Classify(-900, NOW + 60), "auctionBuys")

GL:ResetContext()
GL:Tag("quests", 1, NOW)
check("a quest's reward", GL:Classify(250, NOW), "quests")
GL:SetWindow("trainer", true, NOW)
check("a trainer takes gold: training", GL:Classify(-1000, NOW), "training")

print("\nmail")
GL:ResetContext()
GL:SetWindow("mail", true, NOW)
inbox[1] = { sender = "Auction House", subject = "Sold: Bolt", money = 900 }
inbox[2] = { sender = "Bob", subject = "gold", money = 5000 }
inbox[3] = { sender = "Stranger", subject = "hi", money = 70 }
inbox[4] = { sender = "Stranger", subject = "an item", money = 0 }
inbox[5] = { sender = "Stranger", subject = "pay me", money = 0, cod = 300 }
inbox[6] = { sender = "Auction House", subject = "Outbid: Bolt", money = 400 }
check("an auction sale's gold", GL:MailSource(1), "auctionSales")
check("one of your characters", GL:MailSource(2), "transfer")
check("anyone else", GL:MailSource(3), "mail")
check("a lost bid's gold back", GL:MailSource(6), "auctionBuys")
check("own character by name and realm", GL:IsOwnCharacter("Ana-RealmA"), true)
check("another realm's Ana is not", GL:IsOwnCharacter("Ana-Elsewhere"), false)
GL:NoteTakeMail(4)
GL:NoteTakeMail(1)
check("an item-only mail leaves no tag", GL:Classify(900, NOW), "auctionSales")
GL:NoteTakeMail(5)
check("cash on delivery goes out as mail", GL:Classify(-300, NOW), "mail")

print("\nwritten down")
GL:ResetContext()
GL.session = {}
GL.sessionStart = NOW - 1800
GL:Record("auctionSales", 10000, NOW - 600)
GL:Record("repairs", -2000, NOW - 300)
GL:Record("transfer", 50000, NOW - 200)
GL:Record("nonsense", 5, NOW - 100)
GL:Record("loot", 300, NOW - 86400 * 2)
GL:Record("loot", 0, NOW)

local log = ns.db.goldLog[realm]
local hour = NOW - (NOW % 3600)
check("an hour bucket", log.hours[hour - 3600].auctionSales.i, 10000)
check("gold out is kept as out", log.hours[hour - 3600].repairs.o, 2000)
check("a day bucket", log.days[20261006].auctionSales.i, 10000)
check("an unknown source is other", log.days[20261006].other.i, 5)
check("two days back", log.days[20261004].loot.i, 300)
check("nothing for no change", #GL.session, 5)

print("\nperiods")
local today = GL:Bins("today", nil, nil, NOW)
check("today is 24 hours", #today, 24)
local totals = GL:Totals(today)
check("income leaves moves out", totals.income, 10005)
check("spending", totals.spending, 2000)
check("net", totals.net, 8005)
check("moves kept apart", totals.moved, 50000)

local week = GL:Bins("week", nil, nil, NOW)
check("a week is 7 days", #week, 7)
check("with two days back in it", GL:Totals(week).income, 10305)
check("labelled by day of month", week[7].label, "06")

local session = GL:Bins("session", nil, nil, NOW)
check("half an hour is six five-minute bars", #session, 6)
check("the session holds what it saw", GL:Totals(session).income, 10305)

local picked = GL:Bins("pick", 20261006, 20261004, NOW)
check("picked days either way round", #picked, 3)
check("cover what they hold", GL:Totals(picked).income, 10305)

local long = GL:Bins("pick", 20260101, 20261006, NOW)
check("a long stretch goes a bar a week", #long <= 42 and #long >= 39, true)
check("and still adds up", GL:Totals(long).income, 10305)

check("days logged, newest first", GL:Days()[1], 20261006)

print("\nthe purse")
GL:ResetContext()
local money = 1000
GetMoney = function() return money end
GL.lastMoney = nil
GL.ready = false
GL:OnMoney(NOW)
check("the first reading writes nothing", GL.lastMoney, 1000)
money = 900000
GL:OnMoney(NOW)
check("nor does a change before the world loads", ns.db.goldLog[realm].days[20261006].other.i, 5)
money = 1000
GL.lastMoney = 1000
GL.ready = true
money = 1600
GL:SetWindow("loot", true, NOW)
GL:OnMoney(NOW)
check("looted coins", ns.db.goldLog[realm].hours[hour].loot.i, 600)
GetMoney = function() error("secret value") end
GL:OnMoney(NOW)
check("a purse the game will not read is skipped", GL.lastMoney, 1600)
GetMoney = nil

print("\nper realm, and pruning")
realm = "Realm-B"
check("another realm has nothing", next(GL:GetLog().days), nil)
realm = "Realm-A"
log = GL:GetLog()
log.hours[NOW - 86400 * 20] = { loot = { i = 1, o = 0 } }
log.days[20240101] = { loot = { i = 1, o = 0 } }
GL:Prune(NOW)
check("old hours folded away", log.hours[NOW - 86400 * 20], nil)
check("this hour kept", log.hours[hour] ~= nil, true)
check("days past 400 dropped", log.days[20240101], nil)
check("recent days kept", log.days[20261004] ~= nil, true)

GetInboxHeaderInfo, InRepairMode = nil, nil
time, date = savedTime, savedDate
if failures > 0 then error(failures .. " failure(s)") end
