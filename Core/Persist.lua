-- Blackthornes Tradeskills -- Core/Persist.lua
-- Keeping settings across sessions on a client that loses SavedVariables.
--
-- This build writes SavedVariables at logout and never reads them back, so
-- every session starts empty.
--
-- CVars do NOT cover that. They survive a /reload and a trip to character
-- select, and nothing further: neither ends the client process, so a value
-- that never leaves memory is indistinguishable from one the client keeps.
-- The wiki says as much of C_CVar.RegisterCVar -- registered CVars "persist
-- after relogging/reloading but not after closing the game" -- and an
-- independent measurement on this build found they never reach
-- config-cache.wtf at all. The session counter that once read as proof of
-- persistence had only ever been read inside one process.
--
-- So this file is the within-session cache, and it is genuinely worth having:
-- a /reload is the common case and it keeps a scan. What crosses a restart is
-- the generated Blackthornes_TS_Data addon; see Data/Snapshot.lua.
--
-- One hazard, for whoever revisits the chunk size. On a client that does
-- persist registered CVars, Blizzard's own writer corrupts Config.wtf from
-- about 3KB per value upward -- the value is truncated unterminated and the
-- following entries merge onto its line (WoWUIBugs #410, acknowledged). This
-- store writes 8 x 60KB. That is harmless only for as long as these CVars
-- never reach disk on this client. If that ever changes, cap the chunk well
-- below 3KB or drop the mechanism; do not raise it.
--
-- Only keys in Config.DEFAULTS.settings are mirrored. A CVar is global client
-- state that outlives the addon, so writing arbitrary keys into it would leave
-- rubbish behind that nothing ever cleans up.

local _, ns = ...

local Persist = ns.NewModule("Persist")

local PREFIX = "BTS_"

--------------------------------------------------------------------------------
-- Reading before registering
--------------------------------------------------------------------------------

-- Every CVar read here used to happen after a RegisterCVar call carrying a
-- default. Inside one client process that is harmless: the name already
-- exists, registering is a no-op, and the stored value comes straight back.
-- That is the only case /reload and a logout to character select ever
-- exercise, because neither of them restarts the process.
--
-- A cold start is the case that matters, and it is the one where registering
-- first can lose the value: whatever the client read out of its config at
-- launch is attached to a name this addon has not claimed yet, and claiming
-- it with a default is indistinguishable from writing the default over it.
--
-- So read raw first, register second, and put back anything registration
-- swallowed. If the value was never on disk, none of this changes a thing --
-- which is why Persist.recovered is counted and reported rather than assumed.

--- Read a CVar without registering it. nil for absent or empty.
local function ReadRaw(name)
    if type(C_CVar) ~= "table" or type(C_CVar.GetCVar) ~= "function" then return nil end

    local ok, text = pcall(C_CVar.GetCVar, name)
    if not ok or type(text) ~= "string" or text == "" then return nil end

    return text
end

Persist.ReadRaw = ReadRaw

--- Wall-clock second at which this client process started, or nil.
--
-- GetTime counts up from launch, so time() - GetTime() is the same number all
-- session and a different one after a restart. That is what tells a /reload
-- apart from a cold start without anyone having to remember which they did --
-- and telling those two apart is the whole question here.
local function ProcessStart()
    local ok, uptime = pcall(GetTime)
    if not ok or type(uptime) ~= "number" then return nil end

    return math.floor(time() - uptime)
end

Persist.ProcessStart = ProcessStart

--------------------------------------------------------------------------------
-- Encoding
--------------------------------------------------------------------------------

-- A CVar holds a string. The default's type decides how it reads back, so a
-- setting keeps the type the rest of the addon expects rather than turning
-- into a string the first time it round-trips.

local function Encode(value)
    if type(value) == "boolean" then
        return value and "1" or "0"
    end
    return tostring(value)
end

local function Decode(text, default)
    if text == nil or text == "" then return nil end

    if type(default) == "boolean" then
        return text == "1" or text == "true"
    elseif type(default) == "number" then
        return tonumber(text)
    end

    return text
end

--------------------------------------------------------------------------------
-- Availability
--------------------------------------------------------------------------------

--- Is the CVar mechanism usable, and how does this build register one?
-- @return available, capabilities
function Persist:IsAvailable()
    local cvars = ns.Compat and ns.Compat:Detect().cvars
    if not cvars or not cvars.roundTrip then return false end
    return true, cvars
end

--- Register once per session, before reading or writing.
--
-- Registering does not clobber a stored value: the probe's canary registers
-- with a default of "0" every login and still reads back the previous count.
function Persist:RegisterOne(name, default, cvars)
    self.registered = self.registered or {}
    if self.registered[name] then return end

    local before = ReadRaw(name)

    if cvars.registerVia == "RegisterCVar" then
        pcall(C_CVar.RegisterCVar, name, default)
    elseif cvars.registerVia == "RegisterAddonCVar" then
        pcall(C_CVar.RegisterAddonCVar, name)
    end

    self.registered[name] = true

    -- Registration swallowed a value the client had already loaded. Put it
    -- back. If this ever counts above zero on a cold start, it is the bug.
    if before and ReadRaw(name) ~= before then
        pcall(C_CVar.SetCVar, name, before)

        self.recovered = (self.recovered or 0) + 1
        self.recoveredNames = self.recoveredNames or {}
        self.recoveredNames[#self.recoveredNames + 1] = name
    end
end

--------------------------------------------------------------------------------
-- Settings
--------------------------------------------------------------------------------

--- Load mirrored settings over the defaults. Called from Config:Bootstrap.
-- @return how many differed from their default
function Persist:RestoreSettings()
    local available, cvars = self:IsAvailable()

    self.restored = 0
    self.available = available

    if not available or not ns.db or not ns.db.settings then return 0 end

    for key, default in pairs(ns.Config.DEFAULTS.settings) do
        local name = PREFIX .. key

        self:RegisterOne(name, Encode(default), cvars)

        local ok, text = pcall(C_CVar.GetCVar, name)
        if ok then
            local value = Decode(text, default)

            -- nil means the CVar was never written, so the default stands.
            if value ~= nil then
                ns.db.settings[key] = value

                if value ~= default then
                    self.restored = self.restored + 1
                end
            end
        end
    end

    return self.restored
end

--- Mirror one setting out. Called from Config:Set.
function Persist:SaveSetting(key, value)
    local available, cvars = self:IsAvailable()
    if not available then return false end

    local default = ns.Config.DEFAULTS.settings[key]
    if default == nil then return false end

    local name = PREFIX .. key

    self:RegisterOne(name, Encode(default), cvars)

    return (pcall(C_CVar.SetCVar, name, Encode(value)))
end

--- { available, restored }
function Persist:GetStatus()
    return self.available == true, self.restored or 0
end

--------------------------------------------------------------------------------
-- The whole database
--------------------------------------------------------------------------------

-- Settings fit in one CVar. Everything else -- prices, recipes, the queue --
-- is serialised and split across numbered CVars. 8 x 64KB was measured to
-- survive a logout intact on this client, so that is the budget, and going
-- over it prunes rather than failing.

local STORE_PREFIX = "BTS_store"
local STORE_COUNT = "BTS_storeCount"
local SESSION_CVAR = "BTS_session"
local CHUNK_BYTES = 60000
local MAX_CHUNKS = 8

--------------------------------------------------------------------------------
-- What was there before we touched anything
--------------------------------------------------------------------------------

--- Read the whole store's shape without registering or writing a single CVar.
--
-- This runs as the first thing Config:Bootstrap does, so what it reports is
-- the client's own state at login rather than anything this session caused.
-- Without it there is no way to tell "the client handed back nothing" from
-- "we overwrote it on the way in", and those two have identical symptoms.
function Persist:Peek()
    if self.peeked then return self.peeked end

    local peek = { chunks = {}, bytes = 0, present = 0 }

    peek.count = tonumber(ReadRaw(STORE_COUNT) or "") or 0

    for index = 1, MAX_CHUNKS do
        local text = ReadRaw(STORE_PREFIX .. index)

        peek.chunks[index] = text and #text or 0

        if text then
            peek.present = peek.present + 1
            peek.bytes = peek.bytes + #text
        end
    end

    -- The session line records which client process wrote the store. Same
    -- number means this login is a /reload or a trip to character select;
    -- a different one means the client was actually restarted, which is the
    -- only path that has ever lost the data.
    local session = ReadRaw(SESSION_CVAR)
    local now = ProcessStart()

    peek.processStart = now

    if session then
        local was, at = session:match("^(%-?%d+),(%d+)$")

        peek.savedProcess = tonumber(was)
        peek.savedAt = tonumber(at)
    end

    if peek.savedProcess and now then
        -- A second either side: time() ticks in whole seconds and GetTime
        -- does not, so the difference wobbles by one within a session.
        peek.coldStart = math.abs(now - peek.savedProcess) > 2
    end

    self.peeked = peek
    return peek
end

--- Everything worth keeping, minus what is cheap to rebuild.
local function Snapshot(db)
    local snapshot = {}

    for key, value in pairs(db) do
        snapshot[key] = value
    end

    -- The stored probe report is a diagnostic of a session that has ended,
    -- and it is large. The canary is not: it is how the next login knows
    -- whether any of this worked.
    if db.probe then
        snapshot.probe = { canary = db.probe.canary, loadCount = db.probe.loadCount }
    end

    return snapshot
end

--- Drop the least useful prices until the payload fits the budget.
--
-- Oldest first: a price nobody has seen in days is the one worth losing, and
-- auto-scan replaces it on the next auction house visit anyway.
local function TrimToFit(snapshot, budget)
    local realmKey = ns.Config:GetRealmKey()
    local prices = snapshot.prices and snapshot.prices[realmKey]
    if not prices then return nil end

    local order = {}
    for itemID, record in pairs(prices) do
        order[#order + 1] = { itemID = itemID, seen = record.lastSeen or 0 }
    end
    table.sort(order, function(a, b) return a.seen < b.seen end)

    -- A handful of attempts rather than one per item: each re-encode costs
    -- real time, and this runs while the player is logging out.
    for _, share in ipairs({ 0.25, 0.5, 0.75 }) do
        local trimmed = {}
        for key, value in pairs(prices) do trimmed[key] = value end

        local drop = math.floor(#order * share)
        for index = 1, drop do
            trimmed[order[index].itemID] = nil
        end

        local copy = {}
        for key, value in pairs(snapshot) do copy[key] = value end

        copy.prices = {}
        for key, value in pairs(snapshot.prices) do copy.prices[key] = value end
        copy.prices[realmKey] = trimmed

        local text = ns.Serialize.Encode(copy)
        if #text <= budget then return text, drop end
    end

    return nil
end

--- Write the database out. Called at logout and after a scan.
function Persist:SaveAll()
    local available, cvars = self:IsAvailable()
    if not available or not ns.db then return false end

    local ok, text = pcall(ns.Serialize.Encode, Snapshot(ns.db))
    if not ok then
        ns.Warn("could not serialise the database: " .. tostring(text))
        return false
    end

    local budget = CHUNK_BYTES * MAX_CHUNKS
    local dropped = 0

    if #text > budget then
        local trimmed, count = TrimToFit(Snapshot(ns.db), budget)
        if not trimmed then
            ns.Warn("too much data to store in CVars; nothing was saved.")
            return false
        end
        text, dropped = trimmed, count or 0
    end

    local chunks = math.max(1, math.ceil(#text / CHUNK_BYTES))

    for index = 1, chunks do
        local name = STORE_PREFIX .. index
        local first = (index - 1) * CHUNK_BYTES + 1

        self:RegisterOne(name, "", cvars)
        pcall(C_CVar.SetCVar, name, text:sub(first, first + CHUNK_BYTES - 1))
    end

    -- A shorter save than last time would otherwise leave old chunks behind
    -- for the loader to concatenate onto the end of the new data.
    for index = chunks + 1, MAX_CHUNKS do
        local name = STORE_PREFIX .. index
        self:RegisterOne(name, "", cvars)
        pcall(C_CVar.SetCVar, name, "")
    end

    self:RegisterOne(STORE_COUNT, "0", cvars)
    pcall(C_CVar.SetCVar, STORE_COUNT, tostring(chunks))

    -- Stamped with this process, so the next login can say whether the client
    -- restarted in between rather than taking anyone's word for it.
    local started = ProcessStart()
    if started then
        self:RegisterOne(SESSION_CVAR, "", cvars)
        pcall(C_CVar.SetCVar, SESSION_CVAR, ("%d,%d"):format(started, time()))
    end

    self.lastSave = { bytes = #text, chunks = chunks, dropped = dropped, at = time() }
    return true, dropped
end

--- Read the database back. Called from Config:Bootstrap.
-- @return database or nil
function Persist:LoadAll()
    -- Before IsAvailable, which detects capabilities by registering and
    -- writing CVars of its own.
    local peek = self:Peek()

    local available, cvars = self:IsAvailable()
    if not available then return nil end

    self:RegisterOne(STORE_COUNT, "0", cvars)

    local ok, count = pcall(C_CVar.GetCVar, STORE_COUNT)
    count = ok and tonumber(count) or 0

    -- The peek is the honest reading: if registering lost the count, take the
    -- number the client actually had rather than concluding there was none.
    if count < 1 and peek.count > 0 then count = peek.count end

    if count < 1 then return nil end

    local parts = {}
    for index = 1, math.min(count, MAX_CHUNKS) do
        local name = STORE_PREFIX .. index

        self:RegisterOne(name, "", cvars)

        local got, text = pcall(C_CVar.GetCVar, name)
        if not got or type(text) ~= "string" or text == "" then
            -- A missing chunk means the rest cannot be parsed anyway.
            ns.Warn(("stored data is incomplete (chunk %d of %d missing); starting fresh.")
                :format(index, count))
            return nil
        end

        parts[#parts + 1] = text
    end

    local decoded, value = ns.Serialize.Decode(table.concat(parts))
    if not decoded or type(value) ~= "table" then
        ns.Warn("stored data could not be read; starting fresh.")
        return nil
    end

    self.loadedBytes = #table.concat(parts)
    return value
end

--- Save soon, but not now, and not too often.
--
-- Writing the database is tens of milliseconds of serialisation plus several
-- large CVar writes. That is fine occasionally and bad in a tight loop, so
-- callers that fire on activity use this rather than SaveAll.
function Persist:SaveLater(delay)
    if self.saveTimer then return end

    self.saveTimer = C_Timer.NewTimer(delay or 5, function()
        Persist.saveTimer = nil

        -- Never while a scan is running: that is the busiest the client gets,
        -- and the data is about to change again anyway.
        if ns.Scanner and ns.Scanner.isScanning then
            Persist:SaveLater(15)
            return
        end

        local since = Persist.lastSaveAt and (GetTime() - Persist.lastSaveAt)
        if since and since < 60 then return end

        Persist.lastSaveAt = GetTime()
        Persist:SaveAll()
    end)
end

ns.RegisterCommand("save", "write the database to CVars now", function()
    local ok, dropped = ns.Persist:SaveAll()
    local last = ns.Persist.lastSave

    if ok and last then
        ns.Print(("saved %s bytes across %d CVar(s)%s."):format(
            ns.Util.Comma(last.bytes), last.chunks,
            (dropped or 0) > 0 and (", dropping %d stale prices to fit"):format(dropped) or ""))
    end
end)

--------------------------------------------------------------------------------
-- Capacity
--------------------------------------------------------------------------------

-- Settings fit in a CVar trivially. Whether prices, recipes and the queue fit
-- depends on how long a string this client will store, which is documented
-- nowhere -- so measure it instead of designing around a guess.
--
-- The payload uses the characters a serialised table would actually use: a
-- client that survives 64KB of "x" but strips semicolons would otherwise look
-- like a pass right up until real data went in.

local ALPHABET = "0123456789,;=|[]{}-. abcdefghijklmnopqrstuvwxyz"
local PROBE_CVAR = "BTS_capacityProbe"

local function Payload(length)
    local pattern = ALPHABET:rep(math.ceil(length / #ALPHABET))
    return pattern:sub(1, length)
end

--- Can a string of this length be written and read back byte for byte?
function Persist:TryLength(length, cvars)
    self:RegisterOne(PROBE_CVAR, "", cvars)

    local text = Payload(length)

    local setOk = pcall(C_CVar.SetCVar, PROBE_CVAR, text)
    if not setOk then return false, 0 end

    local getOk, got = pcall(C_CVar.GetCVar, PROBE_CVAR)
    if not getOk or type(got) ~= "string" then return false, 0 end

    return got == text, #got
end

--- The largest string this client stores intact, found by doubling then
--- bisecting. Reports as it goes, because a client that dislikes a large
--- CVar may not survive being asked.
function Persist:MeasureCapacity()
    local available, cvars = self:IsAvailable()
    if not available then
        ns.Print("CVars are not usable on this client; nothing to measure.")
        return
    end

    local good, bad = 0, nil

    for _, length in ipairs({ 256, 1024, 4096, 16384, 65536, 262144, 1048576 }) do
        local ok, stored = self:TryLength(length, cvars)

        ns.Print(("  %8d bytes -- %s"):format(length,
            ok and "ok" or ("truncated to " .. stored)))

        if ok then
            good = length
        else
            bad = length
            break
        end
    end

    -- Between the last success and the first failure, so the answer is a real
    -- number rather than "somewhere between 16K and 64K".
    if bad then
        local low, high = good, bad

        while high - low > 64 do
            local mid = math.floor((low + high) / 2)
            if (self:TryLength(mid, cvars)) then low = mid else high = mid end
        end

        good = low
    end

    -- Left behind, a megabyte of filler would sit in the client config for
    -- good. Clearing it is the polite half of asking the question.
    pcall(C_CVar.SetCVar, PROBE_CVAR, "")

    self.capacity = good

    ns.Print(("largest CVar this client holds in memory: |c%s%s bytes|r")
        :format(ns.COLORS.accent, ns.Util.Comma(good)))

    -- In memory only. Nothing written here has survived a logout yet, and
    -- these CVars are nowhere in the WTF folder, which points at server-side
    -- account data and its own much smaller limits. /bts cvarsoak answers
    -- the question this one cannot.
    ns.Print("that is in-session only -- run |cffffffff/bts cvarsoak|r to test what survives a logout.")

    return good
end

ns.RegisterCommand("cvarsize", "measure how much a CVar can hold", function()
    ns.Print("measuring CVar capacity...")
    ns.Persist:MeasureCapacity()
end)

--------------------------------------------------------------------------------
-- Soak test
--------------------------------------------------------------------------------

-- A CVar holding a megabyte in memory says nothing about what comes back after
-- a cold start. The only way to find that limit is to write a known payload,
-- restart, and see what returns.
--
-- "Restart" means closing the game, not logging out to character select. That
-- distinction is the whole reason this file exists: character select does not
-- end the client process, so a CVar that never leaves memory looks exactly
-- like one that persists. This test used to ask for character select, which
-- is why it passed while the data was being lost. It now records which
-- process wrote the payload and refuses to call a result a pass unless the
-- process actually changed.

local SOAK_CVAR = "BTS_soakTest"

--- How many leading bytes match what we wrote?
local function IntactPrefix(text)
    if type(text) ~= "string" or text == "" then return 0 end

    local expected = Payload(#text)
    if expected == text then return #text end

    -- Truncation is the expected failure, so report where it stopped rather
    -- than just "corrupt".
    local low, high = 0, #text
    while high - low > 1 do
        local mid = math.floor((low + high) / 2)
        if text:sub(1, mid) == expected:sub(1, mid) then low = mid else high = mid end
    end
    return low
end

--- Read back whatever the last soak test left behind. Called at bootstrap.
function Persist:CheckSoak()
    local available, cvars = self:IsAvailable()
    if not available then return end

    -- Read before registering: on the cold start this test exists to measure,
    -- registering the plan first would erase the plan.
    local plan = ReadRaw(SOAK_CVAR .. "Plan")
    if not plan then return end

    local bytes, chunks, written = plan:match("^(%d+),(%d+),(%-?%d+)$")
    if not bytes then
        bytes, chunks = plan:match("^(%d+),(%d+)$")
    end

    bytes, chunks, written = tonumber(bytes), tonumber(chunks), tonumber(written)
    if not bytes then return end

    local now = ProcessStart()

    local result = {
        bytes = bytes, chunks = chunks, intact = 0, returned = 0, survived = 0,
        coldStart = (written and now) and math.abs(now - written) > 2 or nil,
    }

    for index = 1, chunks do
        local name = SOAK_CVAR .. index
        local text = ReadRaw(name)

        self:RegisterOne(name, "", cvars)

        if text then
            local intact = IntactPrefix(text)

            result.returned = result.returned + #text
            result.intact = result.intact + intact

            if intact == bytes then result.survived = result.survived + 1 end
        end
    end

    self.soak = result
end

--- Write payloads, to be checked after the next real logout.
--
-- Several chunks rather than one, because 64KB per CVar and 64KB in total are
-- very different budgets and they look identical from inside a single test.
-- If the limit is a total, the later chunks come back empty -- which is the
-- failure that would otherwise lose data silently.
function Persist:StartSoak(bytes, chunks)
    local available, cvars = self:IsAvailable()
    if not available then
        ns.Print("CVars are not usable on this client.")
        return
    end

    bytes = math.max(64, math.min(bytes or 65536, 1048576))
    chunks = math.max(1, math.min(chunks or 1, 16))

    for index = 1, chunks do
        local name = SOAK_CVAR .. index

        self:RegisterOne(name, "", cvars)

        if not pcall(C_CVar.SetCVar, name, Payload(bytes)) then
            ns.Print(("the client refused chunk %d."):format(index))
            break
        end
    end

    -- Recorded so the next login knows what it is checking against, and which
    -- client process wrote it.
    self:RegisterOne(SOAK_CVAR .. "Plan", "", cvars)
    pcall(C_CVar.SetCVar, SOAK_CVAR .. "Plan",
        ("%d,%d,%d"):format(bytes, chunks, ProcessStart() or 0))

    ns.Print(("wrote %d x %s bytes. Now |cffffffffquit the game completely|r -- not to character select -- start it again, and run |cffffffff/bts cvarsoak|r.")
        :format(chunks, ns.Util.Comma(bytes)))
end

ns.RegisterCommand("cvarsoak", "test how much survives a logout: /bts cvarsoak [bytes] [chunks]", function(args)
    local bytes, chunks = (args or ""):match("^(%d+)%s+(%d+)$")
    if not bytes then bytes = (args or ""):match("^(%d+)$") end

    local result = ns.Persist.soak

    if result then
        ns.Print(("soak result: %d of %d chunks survived intact (%s of %s bytes)."):format(
            result.survived, result.chunks,
            ns.Util.Comma(result.intact), ns.Util.Comma(result.bytes * result.chunks)))

        if result.coldStart == false then
            ns.Warn("this is the same client process that wrote the payload, so it proves nothing about a restart. Quit the game fully and run it again.")
        elseif result.coldStart == nil then
            ns.Print("  (could not tell whether the client restarted in between)")
        else
            ns.Print("  the client did restart in between, so this is the real answer.")
        end

        if result.survived < result.chunks then
            ns.Print(("|c%sthe limit is a total, not per CVar -- budget is about %s bytes.|r"):format(
                ns.COLORS.warn, ns.Util.Comma(result.intact)))
        end

        if not bytes then return end
    end

    ns.Persist:StartSoak(tonumber(bytes), tonumber(chunks))
end)

--------------------------------------------------------------------------------
-- Diagnostic
--------------------------------------------------------------------------------

-- One command for the whole chain, because the failure is somewhere along it
-- and the symptom -- an empty database -- looks the same wherever it broke.
-- Each line is an observation, not a conclusion.

local function Ago(stamp)
    if not stamp then return "never" end

    local seconds = time() - stamp
    if seconds < 90 then return ("%d seconds ago"):format(math.max(0, seconds)) end
    if seconds < 5400 then return ("%d minutes ago"):format(math.floor(seconds / 60)) end
    if seconds < 172800 then return ("%d hours ago"):format(math.floor(seconds / 3600)) end

    return ("%d days ago"):format(math.floor(seconds / 86400))
end

local function Line(label, text)
    ns.PrintRaw(("  |c%s%-18s|r %s"):format(ns.COLORS.muted, label, text))
end

function Persist:Report()
    local peek = self:Peek()
    local diagnostics = (ns.Config and ns.Config.GetLoadDiagnostics)
        and ns.Config:GetLoadDiagnostics() or {}

    ns.Print("persistence")

    Line("saved variables", ("account %s, per-character %s"):format(
        diagnostics.globalType or "nil", diagnostics.charGlobalType or "nil"))

    if diagnostics.lateSavedVariables then
        Line("", "|c" .. ns.COLORS.warn .. "the client handed the saved table back after login|r")
    end

    if peek.coldStart == true then
        Line("this login", "|c" .. ns.COLORS.warn .. "cold start -- the client restarted since the last save|r")
    elseif peek.coldStart == false then
        Line("this login", "same client process as the last save (a /reload or character select)")
    else
        Line("this login", "no session stamp from a previous save to compare against")
    end

    Line("store at login", ("%d of %d chunk(s), %s bytes, count reads %d"):format(
        peek.present, MAX_CHUNKS, ns.Util.Comma(peek.bytes), peek.count))

    -- The one line that would name registration as the culprit.
    local recovered = self.recovered or 0
    Line("registration", recovered > 0
        and (("|c%sput back %d value(s) that registering had cleared|r"):format(ns.COLORS.warn, recovered))
        or "cleared nothing that was already there")

    if ns.Config and ns.Config.restoredFromCVars then
        Line("restored from", ("CVars, %s bytes"):format(ns.Util.Comma(self.loadedBytes or 0)))
    elseif ns.Config and ns.Config.restoredFromSnapshot then
        Line("restored from", "the local data addon")
    elseif ns.Config and ns.Config.freshDatabase then
        Line("restored from", "|c" .. ns.COLORS.warn .. "nothing -- this session started empty|r")
    else
        Line("restored from", "the client's own saved variables")
    end

    Line("local data addon", type(_G.BlackthornesTSSnapshotSource) == "string"
        and _G.BlackthornesTSSnapshotSource
        or (_G.BlackthornesTSSnapshot ~= nil and "loaded" or "not installed"))

    local last = self.lastSave
    Line("last save", last
        and ("%s bytes across %d CVar(s), %s"):format(
            ns.Util.Comma(last.bytes), last.chunks, Ago(last.at))
        or ("nothing written yet this session; the previous one wrote %s"):format(Ago(peek.savedAt)))

    if peek.coldStart == true and peek.present == 0 then
        ns.Print("|c" .. ns.COLORS.warn ..
            "the store was empty after a restart: the client is not keeping these CVars across a quit. " ..
            "Check WTF\\Config.wtf for lines starting BTS_ -- if they are absent, nothing was ever written to disk.|r")
    end
end

ns.RegisterCommand("persist", "report every step of how data is kept between sessions", function()
    ns.Persist:Report()
end)

--------------------------------------------------------------------------------
-- When to write
--------------------------------------------------------------------------------

function Persist:OnEnable()
    -- The last moment the client gives us, and the one that matters: this is
    -- where SavedVariables would have been written if they worked.
    ns.RegisterEvent(self, "PLAYER_LOGOUT", function()
        Persist:SaveAll()
    end)

    -- A scan is minutes of waiting and the most expensive thing here to
    -- rebuild, so it is written out as soon as it lands rather than being
    -- held until logout and lost to a crash. Scanner calls this directly;
    -- there is no internal event bus to route it through.
end
