-- Blackthornes Tradeskills -- Logic/TidyUp.lua
-- How big the save is, and Keep Price History For with Tidy Up.
--
-- The owner said build it (2026-11-26, idea 4, from the mockup): the game
-- reads the whole save at every login and /reload, so a smaller one loads
-- faster. Keep Price History For (`keepPriceHistoryDays`, never rename it)
-- starts at Always (0), and then nothing is ever removed. A player who
-- picks 30 days, 90 days or a year sees the Tidy Up window first, and only
-- its Confirm saves the choice and removes anything. While a choice is
-- kept, the same tidy runs again a little after each login.
--
-- What a tidy removes, for items you don't craft, star or sell only: price
-- readings older than the choice, and random suffix rows not seen for that
-- long. Never an item's own price, never anything of yours (sales, mail,
-- gold, lists, queue, settings, characters), and never an item a
-- character crafts or uses, has starred, has a price of its own, or has
-- listed.

local _, ns = ...

local TidyUp = ns.NewModule("TidyUp")

local DAY = 86400

-- The choices, in days. 0 is Always.
TidyUp.CHOICES = { 30, 90, 365, 0 }

-- How long after login the kept choice tidies again, and how many records
-- it looks at a frame.
TidyUp.LOGIN_DELAY = 45
TidyUp.BUDGET = 400

-- What one more saved line costs on top of its numbers: the game writes
-- `["key"] = value,` with a line break, one value a line.
local LINE = 4

--------------------------------------------------------------------------------
-- The choice
--------------------------------------------------------------------------------

function TidyUp.Valid(days)
    days = tonumber(days)
    for _, choice in ipairs(TidyUp.CHOICES) do
        if days == choice then return choice end
    end
    return nil
end

--- The kept choice in days, 0 for Always.
function TidyUp:Days()
    local days = ns.Config and ns.Config.Get and ns.Config:Get("keepPriceHistoryDays")
    return TidyUp.Valid(days) or 0
end

--------------------------------------------------------------------------------
-- Yours: never tidied
--------------------------------------------------------------------------------

local function AddKeys(into, tbl, depth)
    if type(tbl) ~= "table" then return end
    for key, value in pairs(tbl) do
        local id = tonumber(key)
        if depth <= 1 then
            if id then into[id] = true end
        elseif type(value) == "table" then
            AddKeys(into, value, depth - 1)
        end
    end
end

--- itemID -> true for every item that is yours: crafted or used by a
--- character, starred (PriceHistory:GetTracked), with a price of its own,
--- or listed by you, on any realm.
function TidyUp:Yours()
    local yours = {}
    if ns.PriceHistory and ns.PriceHistory.GetTracked then
        local ok, tracked = pcall(ns.PriceHistory.GetTracked, ns.PriceHistory)
        if ok and type(tracked) == "table" then
            for id in pairs(tracked) do yours[id] = true end
        end
    end
    local db = ns.db
    if type(db) == "table" then
        AddKeys(yours, db.myPrices, 2)
        AddKeys(yours, db.lastPosted, 2)
        AddKeys(yours, db.favouritePrices, 1)
    end
    return yours
end

--------------------------------------------------------------------------------
-- Finding and removing
--------------------------------------------------------------------------------

-- How many characters a number takes in the save. Whole numbers are
-- counted without making a string: a big save holds millions of them.
local function NumberSize(v)
    if type(v) == "number" then
        if v >= 0 and v < 1e9 and v % 1 == 0 then
            if v < 10 then return 1 end
            if v < 100 then return 2 end
            if v < 1000 then return 3 end
            if v < 10000 then return 4 end
            if v < 100000 then return 5 end
            if v < 1000000 then return 6 end
            if v < 10000000 then return 7 end
            if v < 100000000 then return 8 end
            return 9
        end
        return #tostring(v)
    end
    if v == false then return 5 end
    return 3
end
TidyUp.NumberSize = NumberSize

-- How long one frame's share of a long job may take (ms), and how many
-- values a frame when the client has no clock to ask.
TidyUp.FRAME_MS = 3
TidyUp.VALUES = 400

-- `Over()` says when this frame's share is spent. The clock is asked once
-- every few values, since asking it costs more than adding a value up.
local function Share()
    local clock = ns.Perf and ns.Perf.Clock
    local started = clock and clock()
    local count = 0
    return function()
        count = count + 1
        if not started then return count >= TidyUp.VALUES end
        if count % 25 ~= 0 then return false end
        return clock() - started >= TidyUp.FRAME_MS
    end
end

-- A guess at what one table costs in the save, the way the game writes it.
local function Size(value, depth)
    if type(value) == "string" then return #value + 2 end
    if type(value) ~= "table" then return NumberSize(value) end
    if depth > 6 then return 16 end
    local size = 2
    for key, child in pairs(value) do
        size = size + Size(key, 99) + 4 + Size(child, depth + 1) + LINE
    end
    return size
end
TidyUp.Size = Size

-- The oldest reading's time, read cheaply: the first number of a packed
-- history, or of a flat one.
local function OldestTime(history)
    if type(history) == "string" then return tonumber(history:match("^([^,;]*)")) end
    if type(history) == "table" then
        local first = history[1]
        if type(first) == "table" then return tonumber(first.t) end
        return tonumber(first)
    end
    return nil
end

-- What a missing value is kept as, so later readings keep their place
-- (`x == nil and false or x` gives nil back). The same as Data/Prices.lua.
local function Kept(v)
    if v == nil then return false end
    return v
end

-- Readings in a history older than `cutoff`: how many, and the history
-- with them left out (nil when none are old).
local function OldReadings(entry, cutoff)
    local oldest = OldestTime(entry.history)
    if not oldest or oldest >= cutoff then return 0, nil end
    local P = ns.Prices
    local kept, old = {}, 0
    for _, t, m, q in P.EachReading(entry.history) do
        if type(t) == "number" and t < cutoff then
            old = old + 1
        else
            kept[#kept + 1] = Kept(t)
            kept[#kept + 1] = Kept(m)
            kept[#kept + 1] = Kept(q)
        end
    end
    if old == 0 then return 0, nil end
    return old, kept
end

-- Every price record on every realm that is not yours.
local function Others(yours)
    local list = {}
    local db = ns.db
    if type(db) ~= "table" or type(db.prices) ~= "table" then return list end
    for _, realm in pairs(db.prices) do
        if type(realm) == "table" then
            for itemID, record in pairs(realm) do
                if type(record) == "table" and not yours[tonumber(itemID) or itemID] then
                    list[#list + 1] = record
                end
            end
        end
    end
    return list
end

-- Look at one record: count, and with `apply` remove, what is older than
-- `cutoff`. Adds to `tally`.
local function TidyRecord(record, cutoff, apply, tally)
    local old, kept = OldReadings(record, cutoff)
    if old > 0 then
        tally.readings = tally.readings + old
        tally.bytes = tally.bytes + old * 16
        if apply then record.history = kept end
    end
    local suffixes = record.suffixes
    if type(suffixes) ~= "table" then return end
    local gone
    for suffix, entry in pairs(suffixes) do
        if type(entry) == "table" then
            if (tonumber(entry.seen) or 0) < cutoff then
                tally.rows = tally.rows + 1
                tally.bytes = tally.bytes + Size(suffix, 99) + 4 + Size(entry, 1) + LINE
                if apply then
                    gone = gone or {}
                    gone[#gone + 1] = suffix
                end
            else
                local oldRow, keptRow = OldReadings(entry, cutoff)
                if oldRow > 0 then
                    tally.readings = tally.readings + oldRow
                    tally.bytes = tally.bytes + oldRow * 16
                    if apply then entry.history = keptRow end
                end
            end
        end
    end
    if gone then
        for _, suffix in ipairs(gone) do suffixes[suffix] = nil end
    end
end

-- Find or remove, a frame's share of records at a time (FRAME_MS, and
-- never more than BUDGET records). `done(tally)` at the end; with no timer
-- (tests) it all runs at once.
local function Run(days, now, apply, done)
    local tally = { readings = 0, rows = 0, bytes = 0 }
    days = TidyUp.Valid(days) or 0
    if days == 0 then
        if done then done(tally) end
        return tally
    end
    local cutoff = (now or time()) - days * DAY
    local list = Others(TidyUp:Yours())
    local at = 0
    local timer = type(C_Timer) == "table" and C_Timer.After
    local function Step()
        local stop = timer and math.min(#list, at + TidyUp.BUDGET) or #list
        local Over = timer and Share()
        while at < stop do
            at = at + 1
            TidyRecord(list[at], cutoff, apply, tally)
            if Over and Over() then break end
        end
        if at < #list then
            C_Timer.After(0, Step)
            return
        end
        if apply and (tally.rows > 0 or tally.readings > 0) and ns.Prices and ns.Prices.Touch then
            ns.Prices:Touch()
        end
        if done then pcall(done, tally) end
    end
    Step()
    return tally
end

--- What a tidy at `days` would remove: `done({ readings, rows, bytes })`.
--- Nothing is changed. Always (0) finds nothing.
function TidyUp:Find(days, now, done)
    return Run(days, now, false, done)
end

--- Remove what Find at `days` names; `done` gets the same counts.
function TidyUp:Apply(days, now, done)
    return Run(days, now, true, done)
end

--------------------------------------------------------------------------------
-- How big the save is
--------------------------------------------------------------------------------

--- Walks the save one value at a time, so it can stop anywhere and go on
--- next frame. `Step(Over)` adds values up until `Over()` says stop;
--- true and the size once the whole save is counted. The sum is the one
--- Size gives: each top table from depth 1, and the price table realm by
--- realm, each record from depth 1.
local function Walker(db)
    local stack = { { tbl = db, depth = 1, root = true } }
    local total = 32
    return function(Over)
        while #stack > 0 do
            local top = stack[#stack]
            -- A table changed under the walk (a scan saved a price): its
            -- rest is left out. The size is a guess either way.
            local ok, key, value = pcall(next, top.tbl, top.key)
            if not ok or key == nil then
                stack[#stack] = nil
            else
                top.key = key
                if top.root and key == "prices" and type(value) == "table" then
                    stack[#stack + 1] = { tbl = value, realms = true }
                elseif top.realms then
                    if type(value) == "table" then
                        total = total + Size(key, 99) + 8
                        stack[#stack + 1] = { tbl = value, depth = 1 }
                    end
                else
                    total = total + Size(key, 99) + 4 + LINE
                    if type(value) ~= "table" then
                        total = total + Size(value, 0)
                    elseif top.depth > 6 then
                        total = total + 16
                    else
                        total = total + 2
                        stack[#stack + 1] = { tbl = value, depth = top.depth + 1 }
                    end
                end
            end
            if Over and Over() then return false end
        end
        return true, total
    end
end

--- About how many bytes the account save takes, worked out over frames so
--- a big save never stalls the game: each frame adds values up for
--- FRAME_MS and no longer. `done(bytes)` is called at the end. A measure
--- already under way is not started twice. With no timer (tests) it all
--- runs at once.
function TidyUp:Measure(done)
    self.waiting = self.waiting or {}
    if done then self.waiting[#self.waiting + 1] = done end
    if self.measuring then return end
    local db = ns.db
    if type(db) ~= "table" then return end
    self.measuring = true

    local Walk = Walker(db)
    local timer = type(C_Timer) == "table" and C_Timer.After
    local function Step()
        local finished, total = Walk(timer and Share() or nil)
        if not finished then
            C_Timer.After(0, Step)
            return
        end
        TidyUp.measuring = false
        TidyUp.bytes, TidyUp.measuredAt = total, time()
        local waiting = TidyUp.waiting or {}
        TidyUp.waiting = {}
        for _, fn in ipairs(waiting) do pcall(fn, total) end
    end
    Step()
end

--- "about 21 MB", "about 840 KB": a size as the window shows it.
function TidyUp.FormatSize(bytes)
    bytes = tonumber(bytes) or 0
    if bytes >= 1024 * 1024 then
        local mb = bytes / (1024 * 1024)
        return mb >= 10 and ("%d MB"):format(math.floor(mb + 0.5)) or ("%.1f MB"):format(mb)
    end
    return ("%d KB"):format(math.max(0, math.floor(bytes / 1024 + 0.5)))
end

--------------------------------------------------------------------------------
-- Picking and confirming
--------------------------------------------------------------------------------

--- Confirm in the Tidy Up window: keep `days` and tidy now.
function TidyUp:Confirm(days, now, done)
    days = TidyUp.Valid(days) or self:Days()
    if ns.Config and ns.Config.Set then ns.Config:Set("keepPriceHistoryDays", days) end
    self.bytes = nil
    return self:Apply(days, now, done)
end

--- Always needs no asking: nothing is removed.
function TidyUp:KeepAlways()
    if ns.Config and ns.Config.Set then ns.Config:Set("keepPriceHistoryDays", 0) end
end

function TidyUp:OnEnable()
    -- The player picked a choice and confirmed it: keep to it.
    if self:Days() > 0 and type(C_Timer) == "table" and C_Timer.After then
        C_Timer.After(TidyUp.LOGIN_DELAY, function()
            pcall(TidyUp.Apply, TidyUp, TidyUp:Days())
        end)
    end
end
