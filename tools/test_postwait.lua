-- The wait between two posts, which is not the one it looks like.
--
-- Measured in game on 2026-09-20: posting felt slow, and `/bts throttle` taken
-- during a run read `waiting: 0`, `in the last 15s: 1 of 8 allowed`,
-- `dropped messages: 0`, `backing off: no`, `your clicks: clear to send`. The
-- request queue was idle. It was idle *because* posting never got as far as
-- asking it for anything: only one listing may be in flight at a time, and the
-- next post waits for the previous one to be confirmed against the server.
--
-- Two things are asserted:
--
--   1. CanPost refuses while a listing is still being confirmed. It used to be
--      checked in Post alone, the very last step, so a click spent a live price
--      check and raised a confirmation dialog before anything mentioned it.
--   2. SecondsUntilPostable counts that wait down, so the button shows it. The
--      queue cannot report it, because the queue does not know about it.

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

-- Posted one second ago. The confirming read goes out three seconds after
-- the post, and the next post must wait the usual 1.2s after that read, so
-- 3.2 seconds are left and they are one real, countable wait: the button
-- used to count 3, 2, 1, say "wait", then count 2, 1 again.
Reset()
Posting.pending = { startedAt = clock - 1 }

allowed, reason = Posting:CanPost()
Check("posting is refused", allowed, false)
Check("and says why", reason, "still confirming the last listing")

seconds, reason = Posting:SecondsUntilPostable()
CheckAbout("counts the remaining 3.2s down as one wait", seconds, 3.2)
Check("naming the listing being confirmed", reason, "still confirming the last listing")

--------------------------------------------------------------------------------
print("\nthe read has gone out and we are waiting on the server")
--------------------------------------------------------------------------------

-- The spacing after the read is the queue's to count, and it carries on the
-- same countdown; past it there is no honest number, it clears when the
-- server answers.
Reset()
queueSeconds, queueReason = 0.9, "spacing out requests to the auction house"
Posting.pending = { startedAt = clock - 3.3, verifying = true }

seconds, reason = Posting:SecondsUntilPostable()
CheckAbout("the spacing after the read carries the count on", seconds, 0.9)
Check("still named as the listing being confirmed", reason, "still confirming the last listing")

Reset()
Posting.pending = { startedAt = clock - 4.5, verifying = true }

seconds, reason = Posting:SecondsUntilPostable()
Check("no seconds invented once that has passed", seconds, 0)
Check("but the reason still shows", reason, "still confirming the last listing")

--------------------------------------------------------------------------------
print("\nthe longer of the two waits wins")
--------------------------------------------------------------------------------

-- The queue and the in-flight listing are independent. Whichever runs longer
-- is the one the player actually serves.
Reset()
queueSeconds, queueReason = 9, "leaving the auction house free for you"
Posting.pending = { startedAt = clock - 1 }

seconds, reason = Posting:SecondsUntilPostable()
CheckAbout("the 9s queue wait beats the 3.2s confirmation", seconds, 9)
Check("and it is what gets named", reason, "leaving the auction house free for you")

Reset()
queueSeconds, queueReason = 0.5, "spacing out requests to the auction house"
Posting.pending = { startedAt = clock - 1 }

seconds, reason = Posting:SecondsUntilPostable()
CheckAbout("the 3.2s confirmation beats the 0.5s pacing gap", seconds, 3.2)
Check("and it is what gets named", reason, "still confirming the last listing")

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
print("PASS -- the wait between posts is the listing being confirmed, and it is reported")
