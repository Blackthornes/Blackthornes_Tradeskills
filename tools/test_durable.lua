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
local configNS = { Util = ns.Util, RegisterCommand = function() end }
configNS.NewModule = function(name)
    configNS[name] = {}
    return configNS[name]
end
loadfile("Core/Config.lua")("Blackthornes_TS", configNS)
ns.Config.FillGaps = configNS.Config.FillGaps

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
Check("and reads back", ns.MacroStore:LoadData() == full)

print(failures == 0 and "\nall durable storage tests passed" or ("\n" .. failures .. " failure(s)"))
if failures > 0 then error(failures .. " durable storage failure(s)") end
