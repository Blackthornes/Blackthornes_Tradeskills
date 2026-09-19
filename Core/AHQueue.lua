-- Blackthornes Tradeskills -- Core/AHQueue.lua
-- Every auction house request the addon makes, paced through one queue.
--
-- The throttled message channel is not ours. Blizzard's Sell tab, its Create
-- Auction button and its search box send down the same pipe, and going over the
-- allowance does not merely drop our request: it puts the whole auction house
-- into "You're doing that too fast", which blocks the player's own listings.
-- Worse, browse and search results are shared state, so a dropped request
-- leaves Blizzard's searching spinner turning with nothing left to clear it.
--
-- IsThrottledMessageSystemReady is not enough on its own. It answers "may I
-- send one right now", it reserves nothing, and two callers polling on their own
-- timers both see yes in the same frame and both send. So nothing calls it
-- directly any more: requests queue here and drain one at a time, spaced apart,
-- under a budget that deliberately leaves room for the player, and stood down
-- entirely while the player is the one transacting.

local _, ns = ...

local AHQueue = ns.NewModule("AHQueue")

local Util = ns.Util

-- Seconds between two of our own sends. The client's own allowance is finer
-- than this; the extra gap is headroom for the player, who shares it with us.
local MIN_SPACING = 1.2

-- How often the queue is looked at. Only runs while something is waiting.
local DRAIN_INTERVAL = 0.25

-- Our sends are also capped over a rolling window, so a long scan cannot spend
-- the whole allowance even while obeying MIN_SPACING.
local BUDGET_WINDOW = 15
local BUDGET_MAX = 8

-- Stand-down after the player creates or cancels an auction. Their next click
-- matters more than anything of ours that is waiting.
local PLAYER_QUIET = 6

-- Stand-down after the client says a throttled message was dropped. At that
-- point we are already over the line and sending again only deepens it.
local DROPPED_BACKOFF = 10

-- A request nobody could send by now is stale: its answer would land after
-- whatever asked for it had already given up.
local DEFAULT_EXPIRY = 20

-- Lower numbers go first. `urgent` means the player clicked something and is
-- waiting on the answer, and it is the only level allowed to run while
-- Blizzard's own sell frame is open.
AHQueue.PRIORITY = {
    urgent = 10,
    normal = 50,
    scan   = 90,
}

local URGENT_LIMIT = AHQueue.PRIORITY.urgent

-- Blizzard's sell frames, by the names retail uses. Reading a frame is safe;
-- assigning to one, or to any global Blizzard reads back, is what taints. This
-- file assigns to nothing outside our own namespace.
local SELL_FRAMES = {
    "ItemSellFrame",
    "CommoditiesSellFrame",
    "ItemSellList",
    "CommoditiesSellList",
}

AHQueue.queue = {}
AHQueue.sendTimes = {}
AHQueue.lastSend = 0
AHQueue.standDownUntil = 0
AHQueue.sent = 0
AHQueue.dropped = 0

--------------------------------------------------------------------------------
-- Readiness
--------------------------------------------------------------------------------

--- Is the player part-way through Blizzard's own selling flow?
--
-- Best effort by design: if this client names its frames differently the answer
-- is "no", and pacing alone carries the load. Never guesses "yes", because that
-- would silently stall every background request.
function AHQueue:PlayerIsSelling()
    local frame = _G.AuctionHouseFrame
    if type(frame) ~= "table" then return false end

    for i = 1, #SELL_FRAMES do
        local sub = frame[SELL_FRAMES[i]]

        if type(sub) == "table" and type(sub.IsShown) == "function" then
            local ok, shown = pcall(sub.IsShown, sub)
            if ok and shown then return true end
        end
    end

    return false
end

--- Does the client itself say it is ready for another throttled message?
function AHQueue:ClientReady()
    if not Util.HasFunction("C_AuctionHouse.IsThrottledMessageSystemReady") then
        -- No throttle check on this client, so pacing is all we have. That is
        -- the reason MIN_SPACING exists rather than being an optimisation.
        return true
    end

    local ok, ready = pcall(C_AuctionHouse.IsThrottledMessageSystemReady)
    return (not ok) or (ready and true or false)
end

--- How many of our own sends fall inside the rolling budget window.
function AHQueue:RecentSendCount()
    local cutoff = GetTime() - BUDGET_WINDOW

    for i = #self.sendTimes, 1, -1 do
        if self.sendTimes[i] < cutoff then
            table.remove(self.sendTimes, i)
        end
    end

    return #self.sendTimes
end

--- Why a request of this priority cannot be sent right now, or nil if it can.
function AHQueue:WhyNotReady(priority)
    priority = priority or self.PRIORITY.normal

    local now = GetTime()

    if now < self.standDownUntil then
        return ("standing down for another %.1fs"):format(self.standDownUntil - now)
    end

    if (now - self.lastSend) < MIN_SPACING then
        return "pacing our own requests"
    end

    if not self:ClientReady() then
        return "the auction house is still catching up"
    end

    if self:RecentSendCount() >= BUDGET_MAX then
        return "holding back to leave the player room"
    end

    -- Only the thing the player just clicked jumps the sell frame.
    if priority > URGENT_LIMIT and self:PlayerIsSelling() then
        return "Blizzard's sell frame is open"
    end

    return nil
end

--- Stand down for a while: the player, or the client, needs the channel.
function AHQueue:Yield(seconds, reason)
    seconds = seconds or PLAYER_QUIET

    local until_ = GetTime() + seconds
    if until_ <= self.standDownUntil then return end

    self.standDownUntil = until_
    ns.Debug(("auction queue standing down %.0fs: %s"):format(
        seconds, reason or "no reason given"))
end

--------------------------------------------------------------------------------
-- Queueing
--------------------------------------------------------------------------------

local function Compare(a, b)
    if a.priority ~= b.priority then return a.priority < b.priority end
    return a.queuedAt < b.queuedAt
end

--- Queue one throttled auction house request.
--
-- @param opts.send      function that makes the call. Return false to report
--                       that the client refused it.
-- @param opts.name      what it is, for `/bts throttle` and debug output
-- @param opts.key       dedupe key: a second request with the same key replaces
--                       the queued one rather than stacking behind it
-- @param opts.priority  one of AHQueue.PRIORITY, default normal
-- @param opts.expires   seconds before the request is abandoned
-- @param opts.onGiveUp  called if it is never sent, so nothing waits forever
-- @return true if the request was queued
function AHQueue:Request(opts)
    if type(opts) ~= "table" or type(opts.send) ~= "function" then
        ns.Debug("AHQueue:Request called without a send function")
        return false
    end

    local request = {
        send = opts.send,
        name = opts.name or "auction request",
        key = opts.key,
        priority = opts.priority or self.PRIORITY.normal,
        onGiveUp = opts.onGiveUp,
        queuedAt = GetTime(),
        expiresAt = GetTime() + (opts.expires or DEFAULT_EXPIRY),
    }

    -- Replace rather than stack: the UI's one-second ticker and repeated clicks
    -- both ask for the same thing again, and queueing each one is how an
    -- allowance gets spent on answers nobody is waiting for any more.
    if request.key then
        for i = 1, #self.queue do
            if self.queue[i].key == request.key then
                self.queue[i] = request
                self:StartDraining()
                return true
            end
        end
    end

    self.queue[#self.queue + 1] = request
    table.sort(self.queue, Compare)

    self:StartDraining()
    return true
end

--- Drop a queued request without sending it. Its give-up callback still runs.
function AHQueue:Cancel(key)
    if not key then return false end

    for i = #self.queue, 1, -1 do
        local request = self.queue[i]

        if request.key == key then
            table.remove(self.queue, i)
            if request.onGiveUp then pcall(request.onGiveUp) end
            return true
        end
    end

    return false
end

--- Abandon everything queued, telling each waiter it is not coming.
function AHQueue:Flush(reason)
    if #self.queue == 0 then return end

    ns.Debug(("auction queue flushed (%d waiting): %s"):format(
        #self.queue, reason or "no reason given"))

    local queued = self.queue
    self.queue = {}

    for i = 1, #queued do
        if queued[i].onGiveUp then pcall(queued[i].onGiveUp) end
    end
end

function AHQueue:GetPendingCount()
    return #self.queue
end

--------------------------------------------------------------------------------
-- Draining
--------------------------------------------------------------------------------

function AHQueue:StartDraining()
    if self.ticker or #self.queue == 0 then return end

    -- Drain on the spot when nothing is in the way, so a click does not always
    -- pay a quarter second it did not need to.
    self:Drain()

    if #self.queue == 0 or self.ticker then return end

    self.ticker = C_Timer.NewTicker(DRAIN_INTERVAL, function()
        AHQueue:Drain()
    end)
end

function AHQueue:StopDraining()
    if not self.ticker then return end

    self.ticker:Cancel()
    self.ticker = nil
end

--- Send at most one request, if anything is allowed through right now.
function AHQueue:Drain()
    local now = GetTime()

    -- Expire first, so a stale request cannot hold the front of the queue and
    -- keep a live one waiting behind it.
    for i = #self.queue, 1, -1 do
        local request = self.queue[i]

        if now >= request.expiresAt then
            table.remove(self.queue, i)

            ns.Debug(("gave up on %s after %.0fs unsent"):format(
                request.name, now - request.queuedAt))

            if request.onGiveUp then pcall(request.onGiveUp) end
        end
    end

    if #self.queue == 0 then
        self:StopDraining()
        return
    end

    -- The queue is priority-ordered, but a low-priority request may be allowed
    -- through while a high-priority one is not, so walk it rather than looking
    -- only at the front.
    for i = 1, #self.queue do
        local request = self.queue[i]

        if not self:WhyNotReady(request.priority) then
            table.remove(self.queue, i)
            self:Dispatch(request)
            return
        end
    end
end

--- Actually make the call, and record that we spent a send on it.
function AHQueue:Dispatch(request)
    local now = GetTime()

    self.lastSend = now
    self.sendTimes[#self.sendTimes + 1] = now
    self.sent = self.sent + 1

    ns.Debug(("sending %s (%d still queued)"):format(request.name, #self.queue))

    local ok, result = pcall(request.send)

    if not ok then
        ns.Debug(("%s errored: %s"):format(request.name, tostring(result)))
        if request.onGiveUp then pcall(request.onGiveUp) end
        return
    end

    -- A send function returning false means the client refused the call, which
    -- is a failure the caller has to hear about rather than a silent no-op.
    if result == false then
        ns.Debug(("%s was refused by the client"):format(request.name))
        if request.onGiveUp then pcall(request.onGiveUp) end
    end
end

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------

function AHQueue:OnEnable()
    -- The player listing or cancelling something by hand is the clearest signal
    -- that the channel is theirs for the moment.
    ns.RegisterEvent(self, "AUCTION_HOUSE_AUCTION_CREATED", function()
        AHQueue:Yield(PLAYER_QUIET, "an auction was just created")
    end)

    ns.RegisterEvent(self, "AUCTION_CANCELED", function()
        AHQueue:Yield(PLAYER_QUIET, "an auction was just cancelled")
    end)

    -- Both of these may be absent on this client; RegisterEvent handles that.
    ns.RegisterEvent(self, "AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED", function()
        AHQueue.dropped = AHQueue.dropped + 1
        AHQueue:Yield(DROPPED_BACKOFF, "the client dropped a throttled message")
    end)

    ns.RegisterEvent(self, "AUCTION_HOUSE_THROTTLED_SYSTEM_READY", function()
        -- Saves waiting out the rest of a drain interval after a long block.
        if #AHQueue.queue > 0 then AHQueue:Drain() end
    end)

    ns.RegisterEvent(self, "AUCTION_HOUSE_CLOSED", function()
        AHQueue:Flush("the auction house closed")
        AHQueue:StopDraining()
    end)
end

--------------------------------------------------------------------------------
-- Diagnostics
--------------------------------------------------------------------------------

--- One line per queued request, plus why nothing is moving. Used by the
--- `/bts throttle` report, which is the only view into this from in game.
function AHQueue:Report()
    ns.Print("auction request queue")

    ns.PrintRaw(("  waiting:            %d"):format(#self.queue))
    ns.PrintRaw(("  sent this session:  %d"):format(self.sent))
    ns.PrintRaw(("  in the last %ds:    %d of %d allowed"):format(
        BUDGET_WINDOW, self:RecentSendCount(), BUDGET_MAX))
    ns.PrintRaw(("  client reports:     %s"):format(
        self:ClientReady() and "ready" or "busy"))
    ns.PrintRaw(("  sell frame open:    %s"):format(
        self:PlayerIsSelling() and "yes" or "no"))
    ns.PrintRaw(("  dropped messages:   %d"):format(self.dropped))

    local why = self:WhyNotReady(self.PRIORITY.normal)
    ns.PrintRaw(("  background work:    %s"):format(why or "clear to send"))

    local urgentWhy = self:WhyNotReady(self.PRIORITY.urgent)
    ns.PrintRaw(("  your clicks:        %s"):format(urgentWhy or "clear to send"))

    for i = 1, #self.queue do
        local request = self.queue[i]
        ns.PrintRaw(("    %d. %s (priority %d, %.1fs waiting)"):format(
            i, request.name, request.priority, GetTime() - request.queuedAt))
    end
end
