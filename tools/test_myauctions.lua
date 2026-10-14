-- The auction house drawer's Auctions view (Logic/MyAuctions.lua,
-- UI/AuctionsView.lua; a player asked, the owner agreeing 2026-10-14).
--
-- What must hold:
--   1. An auction is undercut only when a fresh scan has someone else's
--      listing below it; an old scan says unknown rather than guess.
--   2. Undercut auctions come first, the most money under at the top, and
--      other characters' auctions last, never this character's twice.
--   3. Cancel calls the game once for that one auction, only at the auction
--      house, never for another character's, and is read back: gone means
--      cancelled, still there after the wait means it did not go through.
--   4. Each row knows about what listing it again costs, the game's own
--      cancel cost first.
--   5. Cancel next takes the undercut auction with the most money under.

local ns = {}
ns.NewModule = function(name) local m = {}; ns[name] = m; return m end
local said = {}
ns.Print = function(text) said[#said + 1] = text end
ns.Debug = function() end
ns.COLORS = { loss = "ffe5604f", accent = "ffc8a44d" }

local clock, wall = 100, 50000
GetTime = function() return clock end
time = function() return wall end
C_Timer = { After = function() end }

ns.Util = {
    HasFunction = function(path) return path == "C_AuctionHouse.CancelAuction" end,
    GetItemLabel = function(id) return "Item " .. id end,
    FormatMoney = function(c) return tostring(c) .. "c" end,
    FormatAge = function(s) return tostring(s) .. "s" end,
}
ns.Config = { GetCharacterKey = function() return "Player-1" end }
ns.Characters = { IsPlaying = function(_, key) return key == "Player-1" end }
ns.Scanner = { isAuctionHouseOpen = true }
ns.Posting = { IsThrottled = function() return false end }

-- Prices: item 1 undercut (rival 40 under your 48), item 2 you are cheapest,
-- item 3 scanned two hours ago, item 4 undercut by 1 on a stack of 20.
local ages = { [1] = 60, [2] = 60, [3] = 7200, [4] = 60, [5] = 60 }
local rivals = { [1] = 40, [2] = 30, [3] = 1, [4] = 30, [5] = 300 }
ns.Prices = {
    GetAge = function(_, id) return ages[id] end,
    GetScanValue = function(_, id, which) assert(which == "rival"); return rivals[id] end,
}

ns.Auctions = {
    live = {
        { auctionID = 11, itemID = 1, quantity = 5, unit = 48 },
        { auctionID = 12, itemID = 2, quantity = 10, unit = 22 },
        { auctionID = 13, itemID = 3, quantity = 4, unit = 112 },
        { auctionID = 14, itemID = 4, quantity = 20, unit = 31 },
    },
    GetListings = function()
        return {
            -- This character's own saved reading: already shown live.
            { itemID = 1, quantity = 5, unit = 48, who = "Player-1" },
            { itemID = 5, quantity = 1, unit = 350, who = "Alt-2", ends = wall + 3600 },
            { itemID = 5, quantity = 1, unit = 350, who = "Alt-2", ended = true },
        }
    end,
}

local cancelled = {}
local cancelCost = {}
C_AuctionHouse = {
    CancelAuction = function(id) cancelled[#cancelled + 1] = id end,
    GetCancelCost = function(id) return cancelCost[id] end,
}

ns.db = { deposits = { [1] = { unit = 2.4 }, [4] = { unit = 3 } } }

assert(loadfile(lfs_cwd .. "/Logic/MyAuctions.lua"))("Blackthornes_TS", ns)
local MyAuctions = ns.MyAuctions

local checks = 0
local function check(label, condition)
    checks = checks + 1
    if not condition then error(("FAILED: %s"):format(label), 2) end
    print(("  ok  %s"):format(label))
end

-- 1
local state, rival, gap = MyAuctions:Judge(1, 48)
check("a fresh lower rival is an undercut, by how much", state == "undercut" and rival == 40 and gap == 8)
check("matching the rival is not an undercut", (MyAuctions:Judge(1, 40)) == "cheapest")
check("you cheapest is cheapest", (MyAuctions:Judge(2, 22)) == "cheapest")
check("an old scan says unknown", (MyAuctions:Judge(3, 112)) == "unknown")
rivals[2] = nil
check("nobody else listed is cheapest", (MyAuctions:Judge(2, 22)) == "cheapest")
rivals[2] = 30

-- 2
local rows, summary = MyAuctions:Rows()
check("four of yours and one alt's still up", #rows == 5 and summary.up == 4 and summary.alts == 1)
check("two undercut", summary.undercut == 2)
check("the most money under comes first", rows[1].itemID == 1 and rows[2].itemID == 4)
check("then the cheapest, then unknown", rows[3].state == "cheapest" and rows[4].state == "unknown")
check("the alt's comes last", rows[5].alt and rows[5].who == "Alt-2")

-- Your alt's cheaper auction is not someone undercutting you.
rivals[5] = 320
ns.Auctions.live[#ns.Auctions.live + 1] = { auctionID = 15, itemID = 5, quantity = 1, unit = 400 }
do
    local altRows, altSummary = MyAuctions:Rows()
    local mine
    for _, row in ipairs(altRows) do if row.auctionID == 15 then mine = row end end
    check("someone else cheaper than your alt is still an undercut", mine and mine.state == "undercut")
    rivals[5] = 350
    altRows, altSummary = MyAuctions:Rows()
    for _, row in ipairs(altRows) do if row.auctionID == 15 then mine = row end end
    check("the alt's listing as the cheapest: yours is not undercut by you", mine and mine.state == "cheapest")
    check("and the count leaves it out", altSummary.undercut == 2)
end
table.remove(ns.Auctions.live)
rivals[5] = 300

-- 4
local deposit, rough = MyAuctions:Deposit(rows[1])
check("the remembered deposit is an estimate", deposit == 12 and rough == true)
cancelCost[11] = 25
deposit, rough = MyAuctions:Deposit(rows[1])
check("the game's cancel cost wins", deposit == 25 and rough == false)
check("a 1c gap on 20 is less than a 60c deposit", MyAuctions:GapSmallerThanDeposit(rows[2]))
check("an 8c gap on 5 is more than nothing", not MyAuctions:GapSmallerThanDeposit({ gap = 8, quantity = 5, itemID = 9 }))

-- 3
local ok, why = MyAuctions:Cancel(rows[5])
check("another character's auction is never cancelled here", not ok and #cancelled == 0 and why ~= nil)

ns.Scanner.isAuctionHouseOpen = false
ok = MyAuctions:Cancel(rows[2])
check("nothing is cancelled away from the auction house", not ok and #cancelled == 0)
ns.Scanner.isAuctionHouseOpen = true

ns.Posting.IsThrottled = function() return true end
ok = MyAuctions:Cancel(rows[2])
check("nothing is cancelled while the auction house is busy", not ok and #cancelled == 0)
ns.Posting.IsThrottled = function() return false end

ok = MyAuctions:Cancel({ mine = true, auctionID = 99, itemID = 1 })
check("an auction no longer up is not cancelled", not ok and #cancelled == 0)

-- 5
ok = MyAuctions:CancelNext()
check("cancel next takes the most money under", ok and #cancelled == 1 and cancelled[1] == 11)
check("the row then shows as cancelling", MyAuctions:Rows()[1].cancelling == true)
ok, why = MyAuctions:Cancel({ mine = true, auctionID = 11, itemID = 1 })
check("a second click on it does nothing", not ok and #cancelled == 1)
ok = MyAuctions:CancelNext()
check("the next click takes the next one", ok and cancelled[2] == 14)

-- 3, read back
table.remove(ns.Auctions.live, 1)  -- 11 went
MyAuctions:OnRead(ns.Auctions.live, false)
check("a cancel that went says so", said[#said]:find("Item 1") ~= nil and MyAuctions.cancelling[11] == nil)
MyAuctions:OnRead(ns.Auctions.live, true)
check("one still up waits out the read-back", MyAuctions.cancelling[14] ~= nil)
clock = clock + MyAuctions.CANCEL_WAIT + 1
MyAuctions:OnRead(ns.Auctions.live, true)
check("still up after the wait: it did not go through", MyAuctions.cancelling[14] == nil
    and said[#said]:find("did not go through") ~= nil)
check("the probe counts them", MyAuctions:ProbeText():find("tried 2, went 1") ~= nil)

-- The view lays headings over the groups.
ns.Theme = {}
ns.Widgets = {}
assert(loadfile(lfs_cwd .. "/UI/AuctionsView.lua"))("Blackthornes_TS", ns)
local laid = ns.AuctionsView.Lay(MyAuctions:Rows())
local headings = {}
for _, entry in ipairs(laid) do if entry.heading then headings[#headings + 1] = entry.heading end end
check("one heading a group, in order", #headings == 4 and headings[1] == "UNDERCUT"
    and headings[4] == "ON YOUR OTHER CHARACTERS")
local texts = ns.AuctionsView.DetailTexts({ state = "undercut", quantity = 5, unit = 48, rival = 40, gap = 8, left = 60 })
check("the detail line has shorter wordings to fall back on", #texts >= 3 and #texts[1] > #texts[#texts])

print(("%d checks passed"):format(checks))
