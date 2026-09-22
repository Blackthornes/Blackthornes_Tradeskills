-- What survives a client restart, and what it costs.
--
-- The whole point of Core/Durable.lua is that it runs once, at a moment
-- nobody is watching, and is only ever found to have been wrong a day later
-- when the data is gone. So the round trip is exercised here end to end:
-- build a payload, put it through the real macro store against a fake client,
-- throw the database away, and read it back.

local macros = {}

local function IndexByName(name)
    for i = 1, #macros do
        if macros[i].name == name then return i end
    end
    return 0
end

CreateMacro = function(name, _, body)
    if #macros >= 120 then error("too many macros") end
    macros[#macros + 1] = { name = name, body = body }
    return #macros
end
EditMacro = function(index, name, _, body)
    macros[index] = { name = name, body = body }
    return index
end
DeleteMacro = function(index) table.remove(macros, index) end
GetMacroInfo = function(index)
    local macro = macros[index]
    if not macro then return nil end
    return macro.name, 134400, macro.body
end
GetMacroIndexByName = IndexByName
GetNumMacros = function() return #macros, 0 end
InCombatLockdown = function() return false end

-- Timers are run by hand, so a coalesced save can be observed rather than
-- waited for. RunTimers fires everything currently pending, once.
local timers = {}
C_Timer = {
    NewTimer = function(delay, fn)
        local timer = { delay = delay, fn = fn, cancelled = false }
        timers[#timers + 1] = timer
        return { Cancel = function() timer.cancelled = true end }
    end,
}

local function RunTimers()
    local pending = timers
    timers = {}
    for _, timer in ipairs(pending) do
        if not timer.cancelled then timer.fn() end
    end
    return #pending
end

local clock = 1758000000
time = function() return clock end
GetTime = function() return 500 end

local ns = {}
ns.NewModule = function(name) ns[name] = ns[name] or {}; return ns[name] end
ns.Print = function() end
ns.PrintRaw = function() end
ns.Warn = function() end
ns.Debug = function() end
ns.RegisterCommand = function() end
ns.RegisterEvent = function() end
ns.COLORS = { muted = "ff000000", warn = "ff000000" }

local function ResolvePath(path)
    local current = _G
    for segment in path:gmatch("[^%.]+") do
        if type(current) ~= "table" then return nil, false end
        local value = current[segment]
        if value == nil then return nil, false end
        current = value
    end
    return current, true
end

ns.Util = {
    Comma = function(n) return tostring(n) end,
    HasFunction = function(path)
        local value, found = ResolvePath(path)
        return found and type(value) == "function"
    end,
}

local REALM = "Classic Beta PvE 2-Horde"
ns.Config = { GetRealmKey = function() return REALM end }

loadfile("Core/Serialize.lua")("Blackthornes_TS", ns)
loadfile("Core/MacroStore.lua")("Blackthornes_TS", ns)

-- The real FillGaps, because Durable leans on its never-overwrite promise.
local configNS = { RegisterCommand = function() end }
configNS.NewModule = function(name)
    configNS[name] = {}
    return configNS[name]
end

-- Core/Util.lua builds a worker frame at load time. Nothing here drives it;
-- it only has to exist so the file loads outside the client.
CreateFrame = function()
    local frame = {}
    for _, name in ipairs({ "SetScript", "Show", "Hide", "SetPoint", "SetSize" }) do
        frame[name] = function() end
    end
    return frame
end

-- The real Util, because ReapplyAfterRestore runs ApplyDefaults and a stub of
-- that is exactly the kind of modelling this suite exists to avoid.
loadfile("Core/Util.lua")("Blackthornes_TS", configNS)
configNS.Util.HasFunction = ns.Util.HasFunction
loadfile("Core/Config.lua")("Blackthornes_TS", configNS)
ns.Config.FillGaps = configNS.Config.FillGaps
ns.Config.FillOverDefaults = configNS.Config.FillOverDefaults
ns.Config.DEFAULTS = configNS.Config.DEFAULTS

loadfile("Core/Durable.lua")("Blackthornes_TS", ns)
local Durable = ns.Durable

local failures = 0
local function Check(name, ok, detail)
    print(string.format("  %-52s %s", name, ok and "ok" or ("FAIL " .. tostring(detail))))
    if not ok then failures = failures + 1 end
end

local function Count(t)
    local n = 0
    for _ in pairs(t or {}) do n = n + 1 end
    return n
end

--------------------------------------------------------------------------------
-- 1. The rollup's own packing.
--------------------------------------------------------------------------------

local rollup = {
    [2589] = { sold = 12, soldUnits = 240, expired = 3, lastAt = 1757000000, net = 4500000 },
    [2592] = { sold = 0, soldUnits = 0, expired = 7, lastAt = 1750000000, net = 0 },
    [158188] = { sold = 1, soldUnits = 1, expired = 0, lastAt = 1758000000, net = 99 },
}

local packed = Durable.PackRollup(rollup)
Check("the rollup packs into the safe alphabet",
    packed:match("^[A-Za-z0-9%-%.]*$") ~= nil, packed)
Check("17 characters an item", #packed == 17 * 3, #packed)

local back = Durable.UnpackRollup(packed)
Check("it unpacks to the same items", Count(back) == 3, Count(back))

for itemID, record in pairs(rollup) do
    local got = back[itemID]
    Check(("item %d keeps its counts"):format(itemID),
        got and got.sold == record.sold and got.soldUnits == record.soldUnits
            and got.expired == record.expired and got.net == record.net,
        got and (got.sold .. "/" .. got.soldUnits .. "/" .. got.expired .. "/" .. got.net))
    -- Whole days: the time of day is deliberately not kept.
    Check(("item %d keeps its date to the day"):format(itemID),
        got and math.abs(got.lastAt - record.lastAt) < 86400,
        got and (got.lastAt - record.lastAt))
end

Check("a truncated rollup is refused", Durable.UnpackRollup(packed:sub(1, #packed - 1)) == nil)
Check("an empty rollup round trips", Count(Durable.UnpackRollup("")) == 0)

--------------------------------------------------------------------------------
-- 2. Building it from the ledger, and not counting a sale twice.
--------------------------------------------------------------------------------

ns.db = {
    settings = { minProfit = 5000, valueOwnedMaterials = false },
    queue = { { itemID = 2589, count = 4 } },
    mailLedger = { [REALM] = { entries = {
        { itemID = 2589, kind = "sold", quantity = 20, net = 130000, t = 1757900000 },
        { itemID = 2589, kind = "sold", quantity = 20, net = 125000, t = 1757950000 },
        { itemID = 2589, kind = "expired", quantity = 20, t = 1757960000 },
        -- A cancellation says nothing about demand and must not count.
        { itemID = 2589, kind = "removed", quantity = 20, t = 1757970000 },
        { itemID = 2592, kind = "expired", quantity = 5, t = 1757980000 },
    }, seen = {} } },
}

local built = Durable:BuildRollup(REALM)
Check("sales are counted", built[2589].sold == 2, built[2589].sold)
Check("units are counted", built[2589].soldUnits == 40, built[2589].soldUnits)
Check("expiries are counted", built[2589].expired == 1, built[2589].expired)
Check("a cancellation is not counted as an expiry", built[2589].expired == 1)
Check("money is totalled", built[2589].net == 255000, built[2589].net)
Check("an item that only ever expired is kept", built[2592].expired == 1)

-- Restored history plus this session, added once.
ns.db.sellThrough = { [REALM] = { [2589] = { sold = 10, soldUnits = 200, expired = 5,
    lastAt = 1750000000, net = 1000000 } } }

local combined = Durable:BuildRollup(REALM)
Check("restored history is added to this session", combined[2589].sold == 12, combined[2589].sold)
Check("and its money too", combined[2589].net == 1255000, combined[2589].net)

local again = Durable:BuildRollup(REALM)
Check("building twice does not count anything twice",
    again[2589].sold == 12 and again[2589].net == 1255000,
    again[2589].sold .. "/" .. again[2589].net)

--------------------------------------------------------------------------------
-- 3. The payload, and a reader meeting something it does not know.
--------------------------------------------------------------------------------

local payload = Durable:Build()
Check("the payload is in the safe alphabet", payload:match("^[A-Za-z0-9%-%.]*$") ~= nil)

local parsed = Durable:Parse(payload)
Check("it parses", parsed ~= nil)
Check("it carries the realm", parsed and ns.MacroStore.Decode(parsed.k) == REALM,
    parsed and tostring(ns.MacroStore.Decode(parsed.k)))
Check("and settings, queue and history", parsed and parsed.s and parsed.q and parsed.r)

-- A section from a future version: skipped by its length, not choked on.
local withExtra = payload .. "z" .. ns.MacroStore.Pack(4, 4) .. "AbCd"
local extended = Durable:Parse(withExtra)
Check("an unknown section is skipped, not fatal", extended ~= nil and extended.s == parsed.s,
    tostring(extended))

Check("a truncated section is refused",
    Durable:Parse(payload:sub(1, #payload - 3)) == nil)
Check("a payload from a newer format is refused",
    Durable:Parse(ns.MacroStore.Pack(9, 1)) == nil)

--------------------------------------------------------------------------------
-- 4. The whole journey: save, lose everything, come back.
--------------------------------------------------------------------------------

Check("saving writes macros", (Durable:SaveIfChanged(true)))

local expectedSold = combined[2589].sold
local expectedNet = combined[2589].net

-- A restart: the addon's Lua state goes, the macros stay.
ns.db = { settings = {}, queue = {} }
Durable.lastPayload, Durable.lastSaveAt, Durable.restoredFrom = nil, nil, nil

local restored, filled = Durable:Restore()
Check("the payload comes back", restored, tostring(filled))
Check("settings came back", ns.db.settings.minProfit == 5000, ns.db.settings.minProfit)
Check("a false setting survives as false, not as missing",
    ns.db.settings.valueOwnedMaterials == false,
    tostring(ns.db.settings.valueOwnedMaterials))
Check("the craft queue came back", ns.db.queue[1] and ns.db.queue[1].itemID == 2589,
    ns.db.queue[1] and ns.db.queue[1].itemID)
Check("the sell-through history came back",
    ns.db.sellThrough[REALM][2589].sold == expectedSold,
    ns.db.sellThrough[REALM][2589] and ns.db.sellThrough[REALM][2589].sold)
Check("with the money", ns.db.sellThrough[REALM][2589].net == expectedNet,
    ns.db.sellThrough[REALM][2589].net)

-- And the sell-through figure itself, which is the number all of this exists
-- to keep: 12 sold against 6 expired.
local record = ns.db.sellThrough[REALM][2589]
Check("sell-through is computable from what came back",
    math.abs(record.sold / (record.sold + record.expired) - 12 / 18) < 0.001,
    record.sold .. "/" .. record.expired)

--------------------------------------------------------------------------------
-- 5. A restore must never overwrite what this session already has.
--------------------------------------------------------------------------------

ns.db = { settings = { minProfit = 99 }, queue = { { itemID = 1, count = 1 } } }
Durable:Restore()
Check("a setting changed this session is kept", ns.db.settings.minProfit == 99,
    ns.db.settings.minProfit)
Check("a queue with something in it is left alone",
    #ns.db.queue == 1 and ns.db.queue[1].itemID == 1, ns.db.queue[1].itemID)

--------------------------------------------------------------------------------
-- 5b. Settings, which defaults were quietly eating.
--
-- Measured in game 2026-09-20: /bts durable reported "restored 1 value(s)"
-- after a restart, and that one value was the history, not the settings.
-- Bootstrap applies every default before the restore runs at PLAYER_LOGIN, so
-- FillGaps found no gap and the stored settings were shadowed on every
-- restart. It looked like it worked.
--------------------------------------------------------------------------------

local DEFAULTS = ns.Config.DEFAULTS.settings

local function WithDefaults(extra)
    local settings = {}
    for key, value in pairs(DEFAULTS) do settings[key] = value end
    for key, value in pairs(extra or {}) do settings[key] = value end
    return settings
end

-- A session where the player has chosen two things, then saved.
ns.MacroStore:ClearData()
ns.db = {
    settings = WithDefaults({ minProfit = 5000, countMailAsStock = false }),
    queue = {},
}
Durable.lastPayload, Durable.lastSaveAt = nil, nil
Check("a session with chosen settings saves", (Durable:SaveIfChanged(true)))

-- A restart: Bootstrap has applied every default before the restore runs.
ns.db = { settings = WithDefaults(), queue = {} }
Durable.restoredFrom = nil
local _, settingsFilled = Durable:Restore()

Check("a chosen number beats its default", ns.db.settings.minProfit == 5000,
    ns.db.settings.minProfit)
Check("a chosen false beats a default of true",
    ns.db.settings.countMailAsStock == false,
    tostring(ns.db.settings.countMailAsStock))
Check("and the restore says it did something", settingsFilled >= 2, settingsFilled)
Check("a setting nobody touched is still its default",
    ns.db.settings.auctionCut == DEFAULTS.auctionCut, ns.db.settings.auctionCut)

-- The other half, and the reason this is not just "overwrite settings": a
-- value that differs from its default came from somewhere real -- this
-- session, or the CVar store carrying it across a reload -- and must survive.
ns.db = { settings = WithDefaults({ minProfit = 77 }), queue = {} }
Durable:Restore()
Check("a setting this session changed is not overwritten",
    ns.db.settings.minProfit == 77, ns.db.settings.minProfit)

-- The honest edge of the rule, written down rather than hidden: setting a
-- value back to its own default is indistinguishable from never having set
-- it, so the stored value would win. What closes that in practice is the
-- save, which runs on the ordinary cadence and at logout -- so by the time
-- anything is read back, the stored value is the default too. That is the
-- sequence tested here, because it is the one that actually happens.
ns.db = { settings = WithDefaults({ countMailAsStock = false }), queue = {} }
Durable.lastPayload, Durable.lastSaveAt = nil, nil
Durable:SaveIfChanged(true)

ns.db.settings.countMailAsStock = DEFAULTS.countMailAsStock    -- changed back
Durable.lastPayload, Durable.lastSaveAt = nil, nil
Durable:SaveIfChanged(true)

ns.db = { settings = WithDefaults(), queue = {} }
Durable:Restore()
Check("a setting put back to its default stays there after a restart",
    ns.db.settings.countMailAsStock == DEFAULTS.countMailAsStock,
    tostring(ns.db.settings.countMailAsStock))

--------------------------------------------------------------------------------
-- 5c. What happens straight after the restore, which is where it was undone.
--
-- Measured in game 2026-09-20: /bts durable reported "restored 3 value(s)"
-- and the settings panel still showed every default. The fill had worked and
-- something put the defaults back milliseconds later.
--
-- That something was Config:ReapplyAfterRestore calling
-- Persist:RestoreSettings, which reads CVars INTO the database. On a cold
-- start those CVars do not exist: registering each one creates it at its
-- default and the read hands that default straight back. The mirroring after
-- a restore has to go the other way.
--------------------------------------------------------------------------------

local Config = configNS.Config
local pulled, pushed

local function StubPersist(pullsBack)
    pulled, pushed = false, {}

    configNS.Persist = {
        SaveSetting = function(_, key, value) pushed[key] = value; return true end,
        -- What the real one does on a cold start: every CVar is created at its
        -- default and read straight back.
        RestoreSettings = function()
            pulled = true
            for key, value in pairs(Config.DEFAULTS.settings) do
                configNS.db.settings[key] = value
            end
            return 0
        end,
    }

    if pullsBack == false then configNS.Persist.RestoreSettings = nil end
end

StubPersist()
configNS.db = { settings = WithDefaults({ minProfit = 5000 }), queue = {} }
Config:ReapplyAfterRestore()

Check("a restored setting is still there afterwards",
    configNS.db.settings.minProfit == 5000, configNS.db.settings.minProfit)
Check("and it was mirrored out to its CVar", pushed.minProfit == 5000, pushed.minProfit)
Check("settings were not read back in from CVars", pulled == false, pulled)

--------------------------------------------------------------------------------
-- 6. What it costs, at the size that matters. A regression here is a bug.
--------------------------------------------------------------------------------

local big = { sellThrough = { [REALM] = {} }, settings = ns.db.settings, queue = {} }
for i = 1, 200 do
    big.sellThrough[REALM][2500 + i * 37] =
        { sold = i % 60, soldUnits = i * 3, expired = i % 20, lastAt = 1757000000, net = i * 9000 }
end
for i = 1, 20 do big.queue[i] = { itemID = 2500 + i, count = 5, recipeID = 3000 + i } end
ns.db = big

local full = Durable:Build()
local slots = ns.MacroStore.SlotsFor(#full)
print(("\n  200 items of history, settings and a 20-entry queue: %d characters, %d macro(s)")
    :format(#full, slots))
Check("the whole payload fits well inside a player's macro bar", slots <= 30, slots)
Check("and it still saves", (Durable:SaveIfChanged(true)))

-- What is written is the stamped build, not the bare one. The bare build is
-- what gets compared between saves, so that a stamp does not make an unchanged
-- payload look changed and rewrite every macro on every cadence tick.
Check("and reads back as the stamped payload", ns.MacroStore:LoadData() == Durable:Build(clock))
Check("which is longer than the bare one by one section",
    #Durable:Build(clock) - #full == 11, #Durable:Build(clock) - #full)
Check("while the comparison text stays stamp-free", Durable.lastPayload == full)

--------------------------------------------------------------------------------
-- 7. The queue coming back from the dead.
--
-- Reported 2026-09-20: "The Queue keeps refilling with things i've already
-- crafted each time i login to a character."
--
-- Bootstrap runs at ADDON_LOADED and loads a whole database -- from the CVar
-- store, or on a cold start from the generated data addon, which is frozen
-- until tools/restore.ps1 runs again. Durable then restores at PLAYER_LOGIN,
-- by which time ns.db.queue is already full of that older copy. The old rule
-- read "entries in memory means this session's work, leave it alone", so the
-- stale copy won every login and crafts already made came back each time.
--------------------------------------------------------------------------------

print("\n\na queue that was emptied stays emptied")

local function StoreQueue(queue, at)
    ns.MacroStore:ClearData()
    Durable.lastPayload, Durable.lastSaveAt = nil, nil
    ns.db = { settings = WithDefaults({}), queue = queue, sellThrough = {} }
    clock = at
    Durable:SaveIfChanged(true)
end

--- Come back on a later login with `loaded` as the database Bootstrap produced.
local function LoginWith(loaded, at)
    clock = at
    Durable.queueAuthoritative = nil
    ns.db = loaded
    return select(2, Durable:Restore())
end

local MADE = { { recipeID = 3001, quantity = 4 } }

-- Yesterday's database, carrying yesterday's queue. This is the frozen data
-- addon: it is not wrong, it is simply older than the macros.
local function STALE()
    return { settings = WithDefaults({}), queue = { { recipeID = 3001, quantity = 4 } },
             sellThrough = {}, durableSavedAt = 1758000000 }
end

-- He queued four, made all four, and logged out. The macros hold the empty
-- queue, saved an hour after that stale database was.
StoreQueue({}, 1758003600)
LoginWith(STALE(), 1758007200)

Check("an emptied queue is not refilled from an older database",
    #ns.db.queue == 0, #ns.db.queue)
Check("and the later save is the one that won",
    Durable.queueAuthoritative == true, Durable.queueAuthoritative)

-- The other direction must still work, or queueing something and quitting
-- would lose it.
StoreQueue({ { recipeID = 3001, quantity = 4 } }, 1758003600)
LoginWith({ settings = WithDefaults({}), queue = {}, sellThrough = {} }, 1758007200)

Check("a queue saved into macros comes back on a cold start",
    #ns.db.queue == 1, #ns.db.queue)
Check("with the craft intact", ns.db.queue[1].recipeID == 3001, ns.db.queue[1].recipeID)

-- A database saved AFTER the macros is the fresher one -- a reload, where the
-- CVar store carried this session's work across. It must not be rolled back.
StoreQueue({}, 1758003600)
LoginWith({ settings = WithDefaults({}), queue = { { recipeID = 3002, quantity = 2 } },
            sellThrough = {}, durableSavedAt = 1758005000 }, 1758007200)

Check("a database saved later than the macros is left alone",
    #ns.db.queue == 1, #ns.db.queue)
Check("and it is still this session's craft",
    ns.db.queue[1].recipeID == 3002, ns.db.queue[1].recipeID)
Check("with the macros not claimed as the winner",
    Durable.queueAuthoritative ~= true, Durable.queueAuthoritative)

-- An identical queue must not be reported as having restored anything. A
-- "restored 1 value(s)" on every login, for a list that never changed, is how
-- a real message stops being read.
StoreQueue(MADE, 1758003600)
local filled = LoginWith({ settings = WithDefaults({}), queue = { { recipeID = 3001, quantity = 4 } },
                           sellThrough = {}, durableSavedAt = 1758000000 }, 1758007200)

Check("an unchanged queue restores nothing", filled == 0, filled)
Check("but the queue is still there", #ns.db.queue == 1, #ns.db.queue)

--------------------------------------------------------------------------------
-- 8. Emptying the queue has to reach the macros before the client closes.
--
-- Reported 2026-09-20 with a screenshot: a queue emptied before a restart came
-- back, and `/bts durable` showed the macros themselves holding the old seven
-- entries. The login rule was doing its job -- the macros won -- but the
-- macros had never been told. Saving rode the CVar cadence and PLAYER_LOGOUT,
-- so emptying the queue and quitting inside the minute wrote nothing at all.
--------------------------------------------------------------------------------

print("\n\na queue change reaches storage without waiting for the cadence")

ns.MacroStore:ClearData()
Durable.lastPayload, Durable.lastSaveAt, Durable.soonTimer = nil, nil, nil
ns.db = { settings = WithDefaults({}), sellThrough = {},
          queue = { { recipeID = 3001, quantity = 4 } } }

clock = 1758000000
Durable:SaveIfChanged(true)

local function StoredQueueCount()
    local found = Durable:Parse(ns.MacroStore:LoadData() or "")
    if not found or not found.q then return nil end
    local queue = Durable.DecodeForTest(found.q)
    return type(queue) == "table" and #queue or nil
end

Check("the craft is in the macros to begin with", StoredQueueCount() == 1, StoredQueueCount())

-- He empties it, and quits well inside the save cadence.
ns.Queue = ns.Queue or {}
clock = 1758000005
ns.db.queue = {}
Durable:SaveSoon()

Check("emptying schedules a write rather than waiting", Durable.soonTimer ~= nil,
    Durable.soonTimer)

RunTimers()

Check("and the macros are told the queue is empty", StoredQueueCount() == 0, StoredQueueCount())
Check("so the next login has nothing to hand back",
    (Durable.lastPayload or ""):find("q") ~= nil, "no queue section")

-- A burst of edits must not mean a burst of macro writes: the player can see
-- them happen, and ten of them for one click reads as the addon misbehaving.
Durable.soonTimer = nil
ns.db.queue = { { recipeID = 3002, quantity = 1 } }

Durable:SaveSoon()
local first = Durable.soonTimer
Durable:SaveSoon()
Durable:SaveSoon()

Check("repeated changes coalesce into one pending write", Durable.soonTimer == first,
    "a second timer was scheduled")
Check("and only one timer is pending", RunTimers() == 1, "more than one")
Check("which wrote the newer queue", StoredQueueCount() == 1, StoredQueueCount())

--------------------------------------------------------------------------------
-- 8. A setting that is off by default and was turned on.
--
-- FillOverDefaults read the default with `defaults[key] or nil`, which turns a
-- default of false into "no default". A value still at false then looked
-- deliberately chosen and the stored true never went in. Measured with
-- allowPostingAtALoss on 2026-09-20; section 5b only ever checked the other
-- direction.
--------------------------------------------------------------------------------

ns.MacroStore:ClearData()
ns.db = { settings = WithDefaults({ allowPostingAtALoss = true }), queue = {}, sellThrough = {} }
Durable.lastPayload, Durable.lastSaveAt = nil, nil
Check("a session that turned a default-off setting on saves", (Durable:SaveIfChanged(true)))

ns.db = { settings = WithDefaults(), queue = {}, sellThrough = {} }
Durable.restoredFrom = nil
Durable:Restore()
Check("a chosen true beats a default of false",
    ns.db.settings.allowPostingAtALoss == true, tostring(ns.db.settings.allowPostingAtALoss))

--------------------------------------------------------------------------------
-- 9. One sale, one /reload, counted once.
--
-- The CVar store carries the ledger across a /reload, and Restore runs again
-- at PLAYER_LOGIN with a payload that already has that sale rolled into it.
-- Before the cutoff stamp, the sale was counted on both sides: sold 1 became
-- sold 2 after the reload, and 2 was what the next logout wrote.
--------------------------------------------------------------------------------

ns.MacroStore:ClearData()
clock = 1758000000
ns.db = { settings = WithDefaults(), queue = {}, sellThrough = {},
    mailLedger = { [REALM] = { entries = {
        { kind = "sold", itemID = 2589, quantity = 20, net = 5000, t = clock - 100 },
    }, seen = {} } } }
Durable.lastPayload, Durable.lastSaveAt = nil, nil
Check("session with one sale saves", (Durable:SaveIfChanged(true)))
Check("before the reload: sold once", Durable:BuildRollup(REALM)[2589].sold == 1)

-- /reload: same database back, Restore runs again.
Durable.restoredFrom = nil
Durable:Restore()
local after = Durable:BuildRollup(REALM)[2589]
Check("after the reload: still sold once", after.sold == 1 and after.soldUnits == 20,
    ("sold=%d units=%d"):format(after.sold, after.soldUnits))
Check("the ledger entry is known to be inside the restored history",
    Durable:IsRolledUp(ns.db.mailLedger[REALM].entries[1], REALM))

-- A second sale after the reload, then a logout save and a cold start where
-- the data addon hands the ledger back too.
clock = clock + 600
ns.db.mailLedger[REALM].entries[2] =
    { kind = "sold", itemID = 2589, quantity = 20, net = 5000, t = clock - 10 }
Check("a sale after the reload counts", Durable:BuildRollup(REALM)[2589].sold == 2)
Durable.lastPayload = nil
Check("logout save", (Durable:SaveIfChanged(true)))

local snapshotLedger = ns.db.mailLedger
local snapshotHistory = ns.db.sellThrough
local snapshotRolledAt = ns.db.sellThroughRolledAt
ns.db = { settings = WithDefaults(), queue = {}, sellThrough = snapshotHistory,
    sellThroughRolledAt = snapshotRolledAt, mailLedger = snapshotLedger }
Durable.restoredFrom = nil
Durable:Restore()
local cold = Durable:BuildRollup(REALM)[2589]
Check("a cold start with the ledger handed back still says two",
    cold.sold == 2 and cold.soldUnits == 40, ("sold=%d units=%d"):format(cold.sold, cold.soldUnits))

-- A sale recorded in the same second as the save, after the payload was built,
-- is not lost: the payload counts entries up to its stamp only, and the stamp
-- is the line, so an entry stamped one second later still counts next time.
clock = clock + 600
Durable.lastPayload = nil
Durable:SaveIfChanged(true)
ns.db.mailLedger[REALM].entries[3] =
    { kind = "sold", itemID = 2589, quantity = 1, net = 100, t = clock + 1 }
Durable.restoredFrom = nil
Durable:Restore()
Check("a sale just after a save is counted once, not lost",
    Durable:BuildRollup(REALM)[2589].sold == 3, Durable:BuildRollup(REALM)[2589].sold)

--------------------------------------------------------------------------------
-- 9. Swapping characters, which is a login the data addon hands its frozen
--    database over on all over again.
--
-- Reported 2026-09-22: "The crafting queue tab is resetting to some old saved
-- list each time i swap characters. it wipes out whatever i was last working
-- on."
--
-- A trip to character select keeps the client process alive, so the CVar store
-- still carries this session's real queue -- but every addon reloads, so
-- Blackthornes_TS_Data sets its global again and Bootstrap merges the two with
-- FillGaps. The queue was merged index by index like everything else, and an
-- ordered list of decisions has no meaningful join: a list of one merged into a
-- frozen list of three keeps your craft at index 1, takes entries 2 and 3 from
-- the frozen list, and silently drops that list's own first entry. The result
-- is neither list, and it is the one Durable then measures its stamps against.
--------------------------------------------------------------------------------

print("\n\nswapping characters does not merge a frozen queue into this one")

local FillGaps = ns.Config.FillGaps

-- What the CVar store carries across the swap: what he was working on.
local fromCVars = {
    settings = WithDefaults({}),
    queue = { { recipeID = 4001, quantity = 2 } },
    prices = { [REALM] = {} },
    durableSavedAt = 1758003600,
}

-- Blackthornes_TS_Data, generated days ago by tools/restore.ps1 and frozen
-- since. Its prices are worth having; its queue is not.
local frozen = {
    settings = WithDefaults({}),
    queue = {
        { recipeID = 3001, quantity = 4 },
        { recipeID = 3002, quantity = 4 },
        { recipeID = 3003, quantity = 4 },
    },
    prices = { [REALM] = { [2589] = { market = 1234 } } },
    deposits = { [2589] = 55 },
}

FillGaps(fromCVars, frozen)

Check("his queue is the whole queue after the merge",
    #fromCVars.queue == 1, #fromCVars.queue)
Check("and it is still his craft",
    fromCVars.queue[1] and fromCVars.queue[1].recipeID == 4001,
    fromCVars.queue[1] and fromCVars.queue[1].recipeID)

-- The rest of the hand-off is the reason FillGaps exists and must still work.
Check("prices still come from the data addon",
    fromCVars.prices[REALM][2589] ~= nil)
Check("and a whole key the store lacked still comes too",
    fromCVars.deposits ~= nil)

-- An emptied queue is a real state -- he made everything on it -- not a gap
-- waiting for a frozen list to fill.
local emptied = { settings = WithDefaults({}), queue = {}, durableSavedAt = 1758003600 }
FillGaps(emptied, frozen)
Check("an emptied queue is not refilled by the data addon",
    #emptied.queue == 0, #emptied.queue)

-- A genuine cold start has no queue at all, and must still be seeded: this is
-- the case the merge was doing a rough job of covering.
local coldStart = { settings = WithDefaults({}) }
FillGaps(coldStart, frozen)
Check("a database with no queue is still seeded whole",
    coldStart.queue and #coldStart.queue == 3, coldStart.queue and #coldStart.queue)

-- End to end, in the order a swap runs them: Bootstrap merges, then Durable
-- restores at PLAYER_LOGIN. The macros hold the same queue the CVar store
-- does, saved at the same moment, so neither stamp beats the other and
-- whatever Bootstrap left behind is what he sees in the Queue tab.
StoreQueue({ { recipeID = 4001, quantity = 2 } }, 1758003600)

local swapped = {
    settings = WithDefaults({}),
    queue = { { recipeID = 4001, quantity = 2 } },
    sellThrough = {},
    durableSavedAt = 1758003600,
}
FillGaps(swapped, frozen)
LoginWith(swapped, 1758007200)

Check("after a swap the Queue tab still holds only his craft",
    #ns.db.queue == 1, #ns.db.queue)
Check("and it is the one he was working on",
    ns.db.queue[1] and ns.db.queue[1].recipeID == 4001,
    ns.db.queue[1] and ns.db.queue[1].recipeID)

print(failures == 0 and "\nall durable storage tests passed" or ("\n" .. failures .. " failure(s)"))
if failures > 0 then error(failures .. " durable storage failure(s)") end
