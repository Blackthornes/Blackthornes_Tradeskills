-- When the game hands SavedVariables back, the CVar store must stand down.
--
-- The bug this holds down: on a cold start RegisterOne creates each settings
-- CVar at its default, and RestoreSettings read that default over the value
-- the saved file had just handed back. Only macro storage put it right again.

local cvars = {}
C_CVar = {
    RegisterCVar = function(name, value) if cvars[name] == nil then cvars[name] = value or "" end end,
    GetCVar = function(name) return cvars[name] end,
    SetCVar = function(name, value) cvars[name] = tostring(value) end,
}
time = os.time

local ns = {}
ns.Warn = function() end
ns.Print = function() end
ns.RegisterCommand = function() end
ns.RegisterEvent = function() end
ns.Util = { Comma = function(n) return tostring(n) end }

loadfile("Core/Serialize.lua")("Blackthornes_TS", ns)

local module = {}
ns.NewModule = function() return module end
loadfile("Core/Persist.lua")("Blackthornes_TS", ns)
local Persist = ns.Persist or module

ns.Compat = { Detect = function() return { cvars = { roundTrip = true, registerVia = "RegisterCVar" } } end }

local function Fresh(globalType)
    for k in pairs(cvars) do cvars[k] = nil end
    Persist.registered, Persist.storeCleared, Persist.clearedChunks = nil, nil, nil
    ns.Config = {
        GetRealmKey = function() return "Realm" end,
        DEFAULTS = { settings = { undercutCopper = 1, soundOnSale = true } },
        loadDiagnostics = { globalType = globalType },
    }
    -- What the saved file handed back: both settings changed from default.
    ns.db = { settings = { undercutCopper = 50, soundOnSale = false }, prices = {}, queue = {} }
end

-- Control: with the game losing the file, the old behaviour stands, and on a
-- cold start it does read the defaults back. This is the bug, reproduced.
Fresh("nil")
Persist:RestoreSettings()
assert(ns.db.settings.undercutCopper == 1,
    "control: expected the cold-start read to hand back the default")

-- 1. The game kept the data: the settings it handed back survive.
Fresh("table")
Persist:RestoreSettings()
assert(ns.db.settings.undercutCopper == 50, "saved setting was overwritten: " .. tostring(ns.db.settings.undercutCopper))
assert(ns.db.settings.soundOnSale == false, "saved boolean setting was overwritten")
assert(cvars.BTS_undercutCopper == nil, "a settings CVar was created")

-- 2. Nor is a changed setting mirrored out.
assert(Persist:SaveSetting("undercutCopper", 70) == false, "SaveSetting wrote while standing down")
assert(cvars.BTS_undercutCopper == nil, "SaveSetting created a CVar")

-- 3. Saving writes no database chunks, and empties old ones.
cvars.BTS_store1 = string.rep("x", 60000)
cvars.BTS_store2 = string.rep("y", 1000)
cvars.BTS_storeCount = "2"
local ok = Persist:SaveAll()
assert(ok, "SaveAll reported failure")
assert(cvars.BTS_store1 == "" and cvars.BTS_store2 == "", "old chunks were not emptied")
assert(cvars.BTS_storeCount == "0", "store count not reset")
assert(cvars.BTS_store3 == nil, "a new chunk was written")
assert(Persist.clearedChunks == 2, "expected 2 chunks emptied, got " .. tostring(Persist.clearedChunks))
assert(Persist.lastSave == nil, "a CVar save was recorded")

-- 4. Nothing to clear on a second save.
Persist:SaveAll()
assert(Persist.clearedChunks == 2, "second save misbehaved")

-- 5. With the game losing the file, the database is still not written:
--    big CVars can corrupt Config.wtf (turned off 2026-10-09).
Fresh("nil")
assert(Persist:SaveAll(), "fallback save failed")
assert(cvars.BTS_store1 == nil, "the database was written to CVars")
assert(cvars.BTS_session == nil, "a session stamp was written")

print("all CVar stand-down tests passed")
