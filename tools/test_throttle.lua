-- Regression test for the auction house request queue.
--
-- The bug: every part of the addon called the throttled auction house APIs
-- directly, gated only by IsThrottledMessageSystemReady. That check reserves
-- nothing, so two callers polling on their own timers both saw "ready" in the
-- same frame and both sent, and browse paging fired one request per server reply
-- for as long as a sweep ran. The allowance is shared with Blizzard's own Create
-- Auction button, so the player's manual listing came back "You're doing that
-- too fast".
--
-- These tests drive Core/AHQueue.lua against a fake clock and a fake client and
-- assert the four properties the fix rests on: requests are spaced apart, they
-- are capped over a window, background work stands down while the player is
-- selling, and nothing waits for ever.

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

--------------------------------------------------------------------------------
-- Fake client
--------------------------------------------------------------------------------

local clock = 0
GetTime = function() return clock end

-- Whether the client says it is ready, and whether Blizzard's sell frame is up.
local clientReady = true
local sellFrameShown = false

C_AuctionHouse = {
    IsThrottledMessageSystemReady = function() return clientReady end,
}

_G = _G or {}
_G.AuctionHouseFrame = {
    ItemSellFrame = { IsShown = function() return sellFrameShown end },
}

-- C_Timer.NewTicker, driven by the fake clock rather than by frames.
local tickers = {}

C_Timer = {
    NewTicker = function(interval, fn)
        local ticker = { interval = interval, fn = fn, nextAt = clock + interval }
        tickers[#tickers + 1] = ticker

        ticker.Cancel = function(self)
            self.cancelled = true
            for i = #tickers, 1, -1 do
                if tickers[i] == self then table.remove(tickers, i) end
            end
        end

        return ticker
    end,

    After = function() end,
}

--- Advance the fake clock, running any ticker that comes due.
local function Advance(seconds, step)
    step = step or 0.05
    local target = clock + seconds

    while clock < target do
        clock = math.min(target, clock + step)

        for i = #tickers, 1, -1 do
            local ticker = tickers[i]
            if ticker and not ticker.cancelled and clock >= ticker.nextAt then
                ticker.nextAt = clock + ticker.interval
                ticker.fn()
            end
        end
    end
end

--------------------------------------------------------------------------------
-- Load the queue
--------------------------------------------------------------------------------

local chunk = assert(loadfile(lfs_cwd .. "/Core/AHQueue.lua"))
chunk("Blackthornes_TS", ns)

local AHQueue = ns.AHQueue
assert(AHQueue, "AHQueue did not register itself")

local failures = 0

local function Check(label, got, expected)
    local ok = got == expected
    if not ok then failures = failures + 1 end

    print(string.format("  %-52s %-8s %s",
        label, tostring(got), ok and "ok" or ("FAIL, expected " .. tostring(expected))))
end

--- Put the queue back to a known state between tests.
local function Reset()
    AHQueue:StopDraining()
    AHQueue.queue = {}
    AHQueue.sendTimes = {}
    AHQueue.lastSend = 0
    AHQueue.standDownUntil = 0
    AHQueue.backoffUntil = 0
    AHQueue.sent = 0
    AHQueue.dropped = 0

    clientReady = true
    sellFrameShown = false
end

--- Queue `count` requests and record the clock time of each send.
local function QueueMany(count, opts)
    local sends = {}

    for i = 1, count do
        AHQueue:Request({
            name = "request " .. i,
            priority = opts and opts.priority,
            expires = (opts and opts.expires) or 600,
            send = function()
                sends[#sends + 1] = clock
                return true
            end,
            onGiveUp = function()
                sends[#sends + 1] = "gave up"
            end,
        })
    end

    return sends
end

--------------------------------------------------------------------------------

print("")
print("ten requests, sent all at once, over 30 seconds")

Reset()
local sends = QueueMany(10)

Advance(30)

-- Two properties at once: nothing sent in the same frame as anything else, and
-- the rolling budget holds even when every request is individually paced.
local minGap = math.huge
for i = 2, #sends do
    if type(sends[i]) == "number" and type(sends[i - 1]) == "number" then
        minGap = math.min(minGap, sends[i] - sends[i - 1])
    end
end

Check("requests sent", #sends, 10)
Check("smallest gap between two sends >= 1.2s", minGap >= 1.2 - 1e-9, true)
Check("sent in the first 15s is within budget", (function()
    local n = 0
    for i = 1, #sends do
        if type(sends[i]) == "number" and sends[i] <= sends[1] + 15 then n = n + 1 end
    end
    return n <= 8
end)(), true)

--------------------------------------------------------------------------------

print("")
print("the same key asked for repeatedly, as a one-second ticker would")

Reset()
local queryCount = 0
local deepestQueue = 0

for _ = 1, 20 do
    AHQueue:Request({
        name = "owned auctions",
        key = "owned-auctions",
        expires = 600,
        send = function()
            queryCount = queryCount + 1
            return true
        end,
    })

    deepestQueue = math.max(deepestQueue, AHQueue:GetPendingCount())
end

Advance(10)

-- Twenty asks for the same thing must not become twenty requests: the ticker
-- refreshing the post panel every second was one of the drains. Two sends is
-- correct rather than one, and the difference is the point: the first ask went
-- straight out because nothing was in the way, and the other nineteen collapsed
-- into the single request that followed it.
Check("requests actually sent", queryCount, 2)
Check("never more than one of them queued at a time", deepestQueue, 1)
Check("nothing left queued", AHQueue:GetPendingCount(), 0)

--------------------------------------------------------------------------------

print("")
print("a queued request replaced by a newer one with the same key")

Reset()
clientReady = false

local firstToldItFailed = false
local secondSent = false

AHQueue:Request({
    name = "price check for the first item",
    key = "item-search",
    expires = 600,
    send = function() return true end,
    onGiveUp = function() firstToldItFailed = true end,
})

AHQueue:Request({
    name = "price check for the second item",
    key = "item-search",
    expires = 600,
    send = function() secondSent = true return true end,
})

-- Clicking a second row supersedes the first click's price check. The first
-- caller has to hear that, or its button waits on an answer that is not coming.
Check("the superseded waiter was told", firstToldItFailed, true)
Check("only one request is queued", AHQueue:GetPendingCount(), 1)

clientReady = true
Advance(5)

Check("the newer request is the one that went", secondSent, true)

--------------------------------------------------------------------------------

print("")
print("background work while the player is at the sell frame")

Reset()
sellFrameShown = true

local background, urgent = 0, 0

AHQueue:Request({
    name = "auction snapshot",
    priority = AHQueue.PRIORITY.scan,
    expires = 600,
    send = function() background = background + 1 return true end,
})

AHQueue:Request({
    name = "price check",
    priority = AHQueue.PRIORITY.urgent,
    expires = 600,
    send = function() urgent = urgent + 1 return true end,
})

Advance(20)

-- The whole point of the fix: our sweep gets out of the way of the player's
-- posting, while the price check their click is waiting on still goes.
Check("the scan waited", background, 0)
Check("the player's price check went", urgent, 1)

sellFrameShown = false
Advance(10)

Check("the scan ran once the sell frame closed", background, 1)

--------------------------------------------------------------------------------

print("")
print("standing down after the player lists something")

Reset()
AHQueue:Yield(6, "an auction was just created")

local afterYield = QueueMany(1, { priority = AHQueue.PRIORITY.scan })
local urgentDuringYield = QueueMany(1, { priority = AHQueue.PRIORITY.urgent })

Advance(4)

-- Standing down is politeness towards the player, so it holds our background
-- work and lets through the request they are waiting on.
Check("the scan waited", #afterYield, 0)
Check("the player's own click went anyway", #urgentDuringYield, 1)

Advance(4)
Check("the scan went once the stand-down expired", #afterYield, 1)

--------------------------------------------------------------------------------

print("")
print("backing off after the client reports a dropped message")

Reset()
AHQueue:BackOff(10, "the client dropped a throttled message")

local duringBackoff = QueueMany(1, { priority = AHQueue.PRIORITY.urgent })

Advance(6)

-- A dropped message means we are already over the allowance, so this one holds
-- everything: there is no urgent request worth deepening it for.
Check("even an urgent request waited", #duringBackoff, 0)

Advance(8)
Check("sent once the backoff expired", #duringBackoff, 1)

--------------------------------------------------------------------------------

print("")
print("a client that never becomes ready")

Reset()
clientReady = false

local gaveUp = false

AHQueue:Request({
    name = "price check",
    expires = 6,
    send = function() return true end,
    onGiveUp = function() gaveUp = true end,
})

Advance(10)

-- Nothing may wait for ever: a caller that is never told its request failed is
-- a button that sits there doing nothing, which is what left the searching
-- indicator turning.
Check("the waiter was told it is not coming", gaveUp, true)
Check("nothing left queued", AHQueue:GetPendingCount(), 0)

--------------------------------------------------------------------------------

print("")
print("flushing when the auction house closes")

Reset()
clientReady = false

local flushed = 0

for i = 1, 3 do
    AHQueue:Request({
        name = "request " .. i,
        expires = 600,
        send = function() return true end,
        onGiveUp = function() flushed = flushed + 1 end,
    })
end

AHQueue:Flush("the auction house closed")

Check("every waiter heard about it", flushed, 3)
Check("nothing left queued", AHQueue:GetPendingCount(), 0)

--------------------------------------------------------------------------------

print("")
if failures > 0 then
    error(string.format("FAIL -- %d check(s) failed", failures), 0)
end
print("PASS -- requests are paced, capped, deferred to the player, and never orphaned")
