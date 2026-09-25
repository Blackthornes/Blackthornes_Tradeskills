-- Tests for the wait shown on the posting buttons.
--
-- The bug this closes: posting is paced on purpose, but nothing in game said
-- how long a wait had left. A button that refused for a few seconds and gave no
-- sign of why was indistinguishable from one that had stopped working, and the
-- only way to find out was to keep clicking it.
--
-- Two things are asserted here, and the second is the one that was got wrong in
-- conversation before it was checked in code:
--
--   1. AHQueue:SecondsUntilReady reports the LONGEST wait, not the first gate
--      it happens to look at, because the gates are simultaneous conditions.
--   2. Urgent priority -- which is what the player's own click runs at -- is
--      exempt from the stand-down, so the six second courtesy after a listing
--      does NOT delay the next post. Reporting it would have shown the player a
--      countdown they never actually serve.

local ns = {}

ns.COLORS = setmetatable({}, { __index = function() return "ffffffff" end })
ns.Print, ns.PrintRaw, ns.Debug, ns.Warn =
    function() end, function() end, function() end, function() end

ns.Util = {
    HasFunction = function(path)
        return path == "C_AuctionHouse.IsThrottledMessageSystemReady"
    end,
}

ns.NewModule = function(name)
    local m = {}
    ns[name] = m
    return m
end
ns.RegisterCommand = function() end
ns.RegisterEvent = function() end

local clock = 0
GetTime = function() return clock end

local clientReady = true
local sellFrameShown = false

C_AuctionHouse = {
    IsThrottledMessageSystemReady = function() return clientReady end,
}

_G = _G or {}
_G.AuctionHouseFrame = {
    ItemSellFrame = { IsShown = function() return sellFrameShown end },
}

C_Timer = {
    NewTicker = function() return { Cancel = function() end } end,
    After = function() end,
}

local chunk = assert(loadfile(lfs_cwd .. "/Core/AHQueue.lua"))
chunk("Blackthornes_TS", ns)

local AHQueue = ns.AHQueue
assert(AHQueue, "AHQueue did not register itself")

local URGENT = AHQueue.PRIORITY.urgent
local SCAN = AHQueue.PRIORITY.scan

local failures = 0

local function Check(label, got, expected)
    local ok = got == expected
    if not ok then failures = failures + 1 end

    print(string.format("  %-54s %-9s %s",
        label, tostring(got), ok and "ok" or ("FAIL, expected " .. tostring(expected))))
end

--- Compare a float against an expected value, to one decimal place.
local function CheckAbout(label, got, expected)
    local ok = got and math.abs(got - expected) < 0.05
    if not ok then failures = failures + 1 end

    print(string.format("  %-54s %-9s %s",
        label, string.format("%.2f", got or -1),
        ok and "ok" or ("FAIL, expected about " .. tostring(expected))))
end

local function Reset()
    AHQueue.queue = {}
    AHQueue.sendTimes = {}
    AHQueue.lastSend = -1000
    AHQueue.standDownUntil = 0
    AHQueue.backoffUntil = 0
    AHQueue.sent = 0
    AHQueue.dropped = 0

    clientReady = true
    sellFrameShown = false
end

--------------------------------------------------------------------------------
print("\nnothing in the way")
--------------------------------------------------------------------------------

Reset()

local seconds, reason = AHQueue:SecondsUntilReady(URGENT)
Check("no wait", seconds, 0)
Check("no reason", reason, nil)

--------------------------------------------------------------------------------
print("\nthe longest gate wins, not the first one looked at")
--------------------------------------------------------------------------------

-- A short back-off and a long stand-down at once. Back-off is checked first in
-- the source, so a version that returned early would report 1s.
Reset()
AHQueue.backoffUntil = clock + 1
AHQueue.standDownUntil = clock + 8

seconds, reason = AHQueue:SecondsUntilReady(SCAN)
CheckAbout("reports the 8s stand-down, not the 1s back-off", seconds, 8)
Check("and names it", reason, "your last listing is still going through")

--------------------------------------------------------------------------------
print("\nthe player's own click is exempt from the stand-down")
--------------------------------------------------------------------------------

-- This is the property the countdown depends on being right. A listing was just
-- created, so background work stands down for six seconds -- but the next post
-- is urgent and goes as soon as the pacing gap allows.
Reset()
AHQueue.standDownUntil = clock + 6
AHQueue.lastSend = clock - 5

seconds, reason = AHQueue:SecondsUntilReady(URGENT)
Check("urgent waits not at all", seconds, 0)
Check("and has nothing to report", reason, nil)

seconds, reason = AHQueue:SecondsUntilReady(SCAN)
CheckAbout("while background work waits the full 6s", seconds, 6)

--------------------------------------------------------------------------------
print("\nthe pacing gap between two of our own sends")
--------------------------------------------------------------------------------

Reset()
AHQueue.lastSend = clock - 0.4

seconds = AHQueue:SecondsUntilReady(URGENT)
CheckAbout("1.2s spacing, 0.4s served, 0.8s left", seconds, 0.8)

--------------------------------------------------------------------------------
print("\nthe rolling budget, once it is spent")
--------------------------------------------------------------------------------

-- Eight sends inside the window, the oldest of them four seconds ago. A slot
-- frees up when that one falls out, eleven seconds from now.
Reset()
for i = 1, 8 do
    AHQueue.sendTimes[i] = clock - 4 + ((i - 1) * 0.1)
end
AHQueue.lastSend = clock - 4

seconds, reason = AHQueue:SecondsUntilReady(URGENT)
CheckAbout("waits for the oldest send to age out", seconds, 11)
Check("and says why", reason, "leaving the auction house free for you")

--------------------------------------------------------------------------------
print("\na wait with no knowable end")
--------------------------------------------------------------------------------

-- The client's throttle is a yes or no. Inventing a number here would be a
-- guess, so it reports a reason and no seconds.
Reset()
clientReady = false

seconds, reason = AHQueue:SecondsUntilReady(URGENT)
Check("no seconds offered", seconds, 0)
Check("but a reason is", reason, "the auction house is still busy")

--------------------------------------------------------------------------------
print("\na real countdown outranks a reason with no number")
--------------------------------------------------------------------------------

Reset()
clientReady = false
AHQueue.lastSend = clock - 0.2

seconds, reason = AHQueue:SecondsUntilReady(URGENT)
CheckAbout("the 1s pacing gap is still counted down", seconds, 1.0)
Check("and it is what gets named", reason, "spacing out requests to the auction house")

--------------------------------------------------------------------------------
print("")
if failures > 0 then
    error(string.format("FAIL -- %d check(s) failed", failures), 0)
end
print("PASS -- the wait is reported as the longest real gate, and never guessed")
