-- Simulate the CVar store across a logout: save, wipe memory, load, compare.
local cvars = {}
C_CVar = {
    RegisterCVar = function(name, value) if cvars[name] == nil then cvars[name] = value or "" end end,
    GetCVar = function(name) return cvars[name] end,
    SetCVar = function(name, value) cvars[name] = tostring(value) end,
}
time = os.time
math.huge = math.huge

local ns = {}
ns.NewModule = function(_, name) return {} end
local warnings = {}
ns.Warn = function(...) warnings[#warnings + 1] = table.concat({...}, " ") end
ns.Print = function() end
ns.RegisterCommand = function() end
ns.RegisterEvent = function() end
ns.Util = { Comma = function(n) return tostring(n) end }
ns.Config = { GetRealmKey = function() return "Classic Beta PvE 2-Horde" end }

loadfile("Core/Serialize.lua")("Blackthornes_TS", ns)

-- Persist calls ns.NewModule("Persist") and expects the module table back.
local module = {}
ns.NewModule = function(_) return module end
loadfile("Core/Persist.lua")("Blackthornes_TS", ns)
local Persist = ns.Persist or module

-- Pretend the probe already proved CVars work.
ns.Compat = { Detect = function() return { cvars = { roundTrip = true, registerVia = "RegisterCVar" } } end }

local function BuildDB(priceCount)
    local db = { prices = { ["Classic Beta PvE 2-Horde"] = {} }, queue = {}, settings = { undercutCopper = 1 },
                 probe = { loadCount = 3, canary = { stamp = 1, session = 3 }, lastReport = { huge = string.rep("x", 50000) } } }
    for i = 1, priceCount do
        db.prices["Classic Beta PvE 2-Horde"][2000 + i] = {
            market = 1234 + i, min = 1200 + i, rivalMin = 1198 + i,
            quantity = i % 97, lastSeen = 1000000 + i, scanCount = i % 13,
        }
    end
    db.queue[1] = { recipeID = 2152, quantity = 5, isDependency = false }
    return db
end

local function DeepEqual(a, b, path)
    if type(a) ~= type(b) then return false, path .. ": type mismatch" end
    if type(a) ~= "table" then
        if a ~= b then return false, path .. ": " .. tostring(a) .. " vs " .. tostring(b) end
        return true
    end
    for k, v in pairs(a) do
        local ok, why = DeepEqual(v, b[k], path .. "." .. tostring(k))
        if not ok then return false, why end
    end
    return true
end

local failures = 0
local function Check(name, ok, detail)
    print(string.format("  %-38s %s", name, ok and "ok" or ("FAIL " .. tostring(detail))))
    if not ok then failures = failures + 1 end
end

-- 1. Normal round trip.
ns.db = BuildDB(1000)
local saved = Persist:SaveAll()
Check("save 1000 prices", saved, "SaveAll returned false")
Check("chunks used <= 8", Persist.lastSave.chunks <= 8, Persist.lastSave.chunks)

local restored = Persist:LoadAll()
Check("load returns a table", type(restored) == "table")
Check("prices survived", restored and DeepEqual(ns.db.prices, restored.prices, "prices"))
Check("queue survived", restored and DeepEqual(ns.db.queue, restored.queue, "queue"))
Check("probe report excluded", restored and restored.probe and restored.probe.lastReport == nil)
Check("canary kept", restored and restored.probe and restored.probe.canary.session == 3)

-- 2. A shorter save must not leave old chunks behind.
local bigChunks = Persist.lastSave.chunks
ns.db = BuildDB(5)
Persist:SaveAll()
Check("shorter save uses fewer chunks", Persist.lastSave.chunks < bigChunks,
    Persist.lastSave.chunks .. " vs " .. bigChunks)
local small = Persist:LoadAll()
local count = 0
for _ in pairs(small.prices["Classic Beta PvE 2-Horde"]) do count = count + 1 end
Check("stale chunks did not corrupt load", count == 5, count)

-- 3. Over budget: must prune, not fail.
ns.db = BuildDB(12000)
warnings = {}
local ok2 = Persist:SaveAll()
Check("over-budget save still succeeds", ok2, table.concat(warnings, "; "))
if ok2 then
    Check("pruned to fit budget", Persist.lastSave.chunks <= 8, Persist.lastSave.chunks)
    Check("reported dropping prices", (Persist.lastSave.dropped or 0) > 0, Persist.lastSave.dropped)
    local trimmed = Persist:LoadAll()
    Check("pruned data still loads", type(trimmed) == "table" and trimmed.queue[1].quantity == 5)
end

-- 4. A missing chunk must be refused, not half-loaded.
cvars["BTS_store2"] = ""
warnings = {}
local broken = Persist:LoadAll()
Check("missing chunk refuses to load", broken == nil, "returned data anyway")
Check("missing chunk warns", #warnings > 0)

print(failures == 0 and "\nall persistence tests passed" or ("\n" .. failures .. " failure(s)"))
