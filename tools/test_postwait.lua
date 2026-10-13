-- The wait between two posts, which is not the one it looks like.
--
-- Measured in game on 2026-09-20: posting felt slow, and `/bts throttle` taken
-- during a run read `waiting: 0`, `in the last 15s: 1 of 8 allowed`,
-- `dropped messages: 0`, `backing off: no`, `your clicks: clear to send`. The
-- request queue was idle. It was idle *because* posting never got as far as
-- asking it for anything: only one listing may be in flight at a time, and the
-- next post waits for the previous one to be confirmed against the server.
--
-- Since 2026-10-13 (the owner asked whether the five seconds were still
-- needed) a listing being confirmed no longer holds the next back: each is
-- told apart by its item, so what is asserted is
--
--   1. CanPost and SecondsUntilPostable no longer wait on one listing being
--      confirmed, only on the queue's own spacing.
--   2. A pile of them (MAX_CONFIRMING items) does wait, and says so, and CanPost
--      refuses up front rather than at the last step.

local ns = {}

ns.COLORS = setmetatable({}, { __index = function() return "ffffffff" end })
ns.NewModule = function(name) local m = {}; ns[name] = m; return m end
ns.RegisterCommand = function() end
ns.RegisterEvent = function() return false end
ns.Print, ns.PrintRaw, ns.Debug, ns.Warn =
    function() end, function() end, function() end, function() end

ns.Util = setmetatable({}, { __index = function() return function() end end })

ns.Scanner = { isAuctionHouseOpen = true, isScanning = false }
ns.Config = { Get = function() return nil end }

-- The queue, stubbed so each test says what it would report on its own.
local queueSeconds, queueReason = 0, nil

ns.AHQueue = {
    PRIORITY = { urgent = 10, normal = 50, scan = 90 },
    SecondsUntilReady = function() return queueSeconds, queueReason end,
    MIN_SPACING = 1.2,
}

local clock = 100
GetTime = function() return clock end

local clientReady = true

C_Timer = { After = function() end, NewTicker = function() return { Cancel = function() end } end }
C_AuctionHouse = { IsThrottledMessageSystemReady = function() return clientReady end }
_G = _G or {}

assert(loadfile(lfs_cwd .. "/Logic/Posting.lua"))("Blackthornes_TS", ns)

local Posting = ns.Posting
assert(Posting, "Posting did not register itself")

local failures = 0

local function Check(label, got, expected)
    local ok = got == expected
    if not ok then failures = failures + 1 end

    print(string.format("  %-54s %-9s %s",
        label, tostring(got), ok and "ok" or ("FAIL, expected " .. tostring(expected))))
end

local function CheckAbout(label, got, expected)
    local ok = got and math.abs(got - expected) < 0.05
    if not ok then failures = failures + 1 end

    print(string.format("  %-54s %-9s %s",
        label, string.format("%.2f", got or -1),
        ok and "ok" or ("FAIL, expected about " .. tostring(expected))))
end

local function Reset()
    Posting.pending = nil
    Posting.others = nil
    Posting.blocked = nil
    queueSeconds, queueReason = 0, nil
    clientReady = true
    ns.Scanner.isAuctionHouseOpen = true
    ns.Scanner.isScanning = false
end

--------------------------------------------------------------------------------
print("\nnothing in flight")
--------------------------------------------------------------------------------

Reset()

local allowed, reason = Posting:CanPost()
Check("posting is allowed", allowed, true)

local seconds
seconds, reason = Posting:SecondsUntilPostable()
Check("no wait", seconds, 0)
Check("no reason", reason, nil)

--------------------------------------------------------------------------------
print("\na listing is still being confirmed")
--------------------------------------------------------------------------------

-- Since 2026-10-13 the next listing no longer waits for the last one to be
-- confirmed: each is told apart by its item. What is left is the auction
-- house's own spacing, which the queue counts.
Reset()
Posting.pending = { itemID = 1, startedAt = clock - 1 }

allowed, reason = Posting:CanPost(2)
Check("another item may be listed", allowed, true)

seconds, reason = Posting:SecondsUntilPostable(2)
Check("with nothing of its own to count down", seconds, 0)
Check("and nothing to say", reason, nil)

Reset()
queueSeconds, queueReason = 1.1, "spacing out requests to the auction house"
Posting.pending = { itemID = 1, startedAt = clock - 0.1 }

seconds, reason = Posting:SecondsUntilPostable(2)
CheckAbout("only the spacing after the listing is counted", seconds, 1.1)
Check("and named", reason, "spacing out requests to the auction house")

--------------------------------------------------------------------------------
print("\na pile of listings being confirmed")
--------------------------------------------------------------------------------

-- A burst of clicks may not pile up more checks than the auction house can
-- answer: past MAX_CONFIRMING items, a new one waits for the oldest.
Reset()
Posting.others = {}
for item = 1, Posting.MAX_CONFIRMING - 1 do
    Posting.others[item] = { itemID = item, startedAt = clock - 2 + item * 0.1 }
end
Posting.pending = { itemID = Posting.MAX_CONFIRMING, startedAt = clock }

allowed, reason = Posting:CanPost(99)
Check("a new item waits", allowed, false)
Check("and says why", reason, "still confirming the last listing")

seconds, reason = Posting:SecondsUntilPostable(99)
Check("with no seconds invented", seconds, 0)
Check("but the reason shows", reason, "still confirming the last listing")

allowed = Posting:CanPost(1)
Check("another copy of one being confirmed still goes", allowed, true)

Posting:DropPending(Posting.others[1])
allowed = Posting:CanPost(99)
Check("once the oldest settles, the new one may go", allowed, true)

Posting:DropPending(Posting.pending)
Check("the newest left takes the place of the one settled",
    Posting.pending and Posting.pending.itemID, Posting.MAX_CONFIRMING - 1)
Posting.others = nil

--------------------------------------------------------------------------------
print("\nrefusals that are not waits stay silent")
--------------------------------------------------------------------------------

-- A shut auction house is not something that counts down on its own, and a
-- countdown would imply it does.
Reset()
ns.Scanner.isAuctionHouseOpen = false

seconds, reason = Posting:SecondsUntilPostable()
Check("no seconds", seconds, 0)
Check("and no countdown reason", reason, nil)

--------------------------------------------------------------------------------
print("")
if failures > 0 then
    error(string.format("FAIL -- %d check(s) failed", failures), 0)
end
print("PASS -- the wait between posts is the auction house's spacing, and a pile of checks waits")
