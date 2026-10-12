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

local L = ns.L or setmetatable({ Format = string.format }, { __index = function(_, key) return key end })

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

-- Read by Posting, which counts the gap after its confirming read into the
-- wait it shows on the buttons.
AHQueue.MIN_SPACING = MIN_SPACING

-- Two different waits, deliberately kept apart.
--
-- standDownUntil is politeness: the player just listed something, or a listing
-- of ours is settling, so our background work gets out of the way. A request the
-- player is actively waiting on is not in the way -- it is the player -- so
-- urgent work goes through it.
--
-- backoffUntil is not politeness. The client has told us a throttled message was
-- dropped, so we are already over the line, and nothing of any priority goes out
-- until it passes.
AHQueue.standDownUntil = 0
AHQueue.backoffUntil = 0

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

    if now < self.backoffUntil then
        return ("waiting %.1fs more: the auction house dropped a request"):format(
            self.backoffUntil - now)
    end

    if priority > URGENT_LIMIT and now < self.standDownUntil then
        return ("paused %.1fs more while you use the auction house"):format(self.standDownUntil - now)
    end

    if (now - self.lastSend) < MIN_SPACING then
        return "spacing out requests to the auction house"
    end

    if not self:ClientReady() then
        return "the auction house is still busy"
    end

    if self:RecentSendCount() >= BUDGET_MAX then
        return "leaving the auction house free for you"
    end

    -- Only the thing the player just clicked jumps the sell frame.
    if priority > URGENT_LIMIT and self:PlayerIsSelling() then
        return "Blizzard's Sell tab is open"
    end

    return nil
end

--- How long until a request of this priority could be sent.
--
-- The companion to WhyNotReady, which says why a request is waiting but not
-- how much longer. Nothing in game could answer that, so a paced post looked
-- like a button that had quietly stopped working.
--
-- The gates are simultaneous conditions rather than a sequence, so the wait is
-- the longest of them, not the first one found.
--
-- Two of them have no knowable end: the client's own throttle is a yes or no
-- with no duration attached, and the player's sell frame closes when they close
-- it. Those return a reason with no seconds rather than a number that would be
-- a guess. A caller showing a countdown should fall back to words when the
-- seconds run out and a reason is still coming back.
--
-- @return seconds, reason
--   0, nil       clear to send
--   n, reason    waiting, and the wait has n seconds left
--   0, reason    waiting on something with no knowable length
function AHQueue:SecondsUntilReady(priority)
    priority = priority or self.PRIORITY.normal

    local now = GetTime()
    local seconds, reason = 0, nil

    local function Consider(left, why)
        if left <= 0 then return end
        if left > seconds then seconds, reason = left, why end
    end

    if now < self.backoffUntil then
        Consider(self.backoffUntil - now, L["the auction house dropped a request"])
    end

    if priority > URGENT_LIMIT and now < self.standDownUntil then
        Consider(self.standDownUntil - now, L["your last listing is still going through"])
    end

    Consider(MIN_SPACING - (now - self.lastSend), L["spacing out requests to the auction house"])

    -- Pruned first, so entry one is the oldest send still inside the window and
    -- the moment it falls out is the moment a slot frees up.
    if self:RecentSendCount() >= BUDGET_MAX and self.sendTimes[1] then
        Consider((self.sendTimes[1] + BUDGET_WINDOW) - now,
            L["leaving the auction house free for you"])
    end

    -- No duration to offer for either of these, so they only set a reason and
    -- only when nothing with a real countdown is already waiting longer.
    if not self:ClientReady() then
        reason = reason or L["the auction house is still busy"]
    end

    if priority > URGENT_LIMIT and self:PlayerIsSelling() then
        reason = reason or L["Blizzard's Sell tab is open"]
    end

    return seconds, reason
end

--- Stand down for a while: the player needs the channel more than we do.
--
-- Background work waits; anything the player clicked still goes, paced and
-- inside the budget as always.
function AHQueue:Yield(seconds, reason)
    seconds = seconds or PLAYER_QUIET

    local until_ = GetTime() + seconds
    if until_ <= self.standDownUntil then return end

    self.standDownUntil = until_
    ns.Debug(("auction requests paused %.0fs: %s"):format(
        seconds, reason or "no reason"))
end

--- Stop sending entirely for a while: we are over the allowance rather than
--- merely sharing it, so there is no such thing as an urgent request right now.
function AHQueue:BackOff(seconds, reason)
    seconds = seconds or DROPPED_BACKOFF

    local until_ = GetTime() + seconds
    if until_ <= self.backoffUntil then return end

    self.backoffUntil = until_
    ns.Debug(("auction requests stopped %.0fs: %s"):format(
        seconds, reason or "no reason"))
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
        ns.Debug("an auction request was made with nothing to send")
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
                local replaced = self.queue[i]
                self.queue[i] = request

                -- The same key is asked for at different priorities (the owned
                -- auctions refresh is routine; the /bts auctions check is
                -- urgent), so the replacement takes the more urgent of the
                -- two. Taking its own let a routine refresh push a listing's
                -- urgent read-back to the back of the line, where it waited
                -- out the check and reported it could not tell.
                request.priority = math.min(request.priority, replaced.priority or request.priority)
                table.sort(self.queue, Compare)

                -- The replaced request will never be sent, so whatever was
                -- waiting on it hears that now. Dropping it silently is how a
                -- button ends up sitting there doing nothing for ever.
                if replaced.onGiveUp then pcall(replaced.onGiveUp) end

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

--- Drop a queued request without sending it.
--
-- The give-up callback runs unless `silent`, which is for a caller that is
-- already tearing the same state down itself -- otherwise cancelling a scan
-- reports it as "the auction house stayed busy" when the player simply clicked
-- Cancel.
function AHQueue:Cancel(key, silent)
    if not key then return false end

    for i = #self.queue, 1, -1 do
        local request = self.queue[i]

        if request.key == key then
            table.remove(self.queue, i)
            if not silent and request.onGiveUp then pcall(request.onGiveUp) end
            return true
        end
    end

    return false
end

--- Abandon everything queued, telling each waiter it is not coming.
function AHQueue:Flush(reason)
    if #self.queue == 0 then return end

    ns.Debug(("dropped %d waiting auction request(s): %s"):format(
        #self.queue, reason or "no reason"))

    local queued = self.queue
    self.queue = {}

    -- Waiters still tidy up, but say nothing: a request dropped because the
    -- auction house closed was not refused for being busy, and a string of
    -- "stayed busy" warnings on walking away read as something going wrong.
    self.flushing = reason or true
    for i = 1, #queued do
        if queued[i].onGiveUp then pcall(queued[i].onGiveUp) end
    end
    self.flushing = nil
end

--- True while Flush is telling waiters their request is not coming, so a
--- give-up can keep quiet about a window the player closed.
function AHQueue:IsFlushing()
    return self.flushing ~= nil
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

            ns.Debug(("gave up on %s: not sent after %.0fs"):format(
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

    ns.Debug(("sending %s (%d still waiting)"):format(request.name, #self.queue))

    local ok, result = pcall(request.send)

    if not ok then
        ns.Debug(("%s failed: %s"):format(request.name, tostring(result)))
        if request.onGiveUp then pcall(request.onGiveUp) end
        return
    end

    -- A send function returning false means the client refused the call, which
    -- is a failure the caller has to hear about rather than a silent no-op.
    if result == false then
        ns.Debug(("the game refused %s"):format(request.name))
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
        AHQueue:Yield(PLAYER_QUIET, "you just listed an auction")
    end)

    ns.RegisterEvent(self, "AUCTION_CANCELED", function()
        AHQueue:Yield(PLAYER_QUIET, "you just cancelled an auction")
    end)

    -- Both of these may be absent on this client; RegisterEvent handles that.
    ns.RegisterEvent(self, "AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED", function()
        AHQueue.dropped = AHQueue.dropped + 1
        AHQueue:BackOff(DROPPED_BACKOFF, "the auction house dropped a request (too many sent)")
    end)

    ns.RegisterEvent(self, "AUCTION_HOUSE_THROTTLED_SYSTEM_READY", function()
        -- Saves waiting out the rest of a drain interval after a long block.
        if #AHQueue.queue > 0 then AHQueue:Drain() end
    end)

    ns.RegisterEvent(self, "AUCTION_HOUSE_CLOSED", function()
        -- Said closed before the flush, not after: the flush runs each
        -- request's give-up, and a price check giving up with the auction
        -- house still marked open went on to show a listing confirmation out
        -- in the world. The scanner's own handler only runs after this one.
        if ns.Scanner then ns.Scanner.isAuctionHouseOpen = false end

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
    ns.Print("auction house requests")

    ns.PrintRaw(("  waiting:            %d"):format(#self.queue))
    ns.PrintRaw(("  sent this session:  %d"):format(self.sent))
    ns.PrintRaw(("  in the last %ds:    %d of %d allowed"):format(
        BUDGET_WINDOW, self:RecentSendCount(), BUDGET_MAX))
    ns.PrintRaw(("  auction house:      %s"):format(
        self:ClientReady() and "ready" or "busy"))
    ns.PrintRaw(("  Sell tab open:      %s"):format(
        self:PlayerIsSelling() and "yes" or "no"))
    ns.PrintRaw(("  dropped requests:   %d"):format(self.dropped))

    local now = GetTime()
    ns.PrintRaw(("  paused for you:     %s"):format(
        now < self.standDownUntil
            and ("%.1fs left"):format(self.standDownUntil - now) or "no"))
    ns.PrintRaw(("  paused after drop:  %s"):format(
        now < self.backoffUntil
            and ("%.1fs left"):format(self.backoffUntil - now) or "no"))

    local why = self:WhyNotReady(self.PRIORITY.normal)
    ns.PrintRaw(("  background work:    %s"):format(why or "can send now"))

    local urgentWhy = self:WhyNotReady(self.PRIORITY.urgent)
    ns.PrintRaw(("  your clicks:        %s"):format(urgentWhy or "can send now"))

    for i = 1, #self.queue do
        local request = self.queue[i]
        ns.PrintRaw(("    %d. %s (priority %d, %.1fs waiting)"):format(
            i, request.name, request.priority, GetTime() - request.queuedAt))
    end
end
