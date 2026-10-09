-- The CVar store no longer writes the database (turned off 2026-10-09: big
-- CVars can corrupt Config.wtf). SaveAll must write nothing in any case and
-- empty what an older version left; LoadAll still reads such leftovers once.
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

--- Lay down chunks the way versions before 2026-10-09 wrote them.
local function WriteOldStore(db)
    local text = ns.Serialize.Encode(db)
    local chunks = math.max(1, math.ceil(#text / 60000))
    for index = 1, chunks do
        cvars["BTS_store" .. index] = text:sub((index - 1) * 60000 + 1, index * 60000)
    end
    cvars["BTS_storeCount"] = tostring(chunks)
    return chunks
end

local function Written()
    local bytes = 0
    for name, value in pairs(cvars) do
        if name:find("^BTS_store%d") then bytes = bytes + #value end
    end
    return bytes
end

-- 1. The game lost the saved file: still nothing written.
ns.Config.loadDiagnostics = { globalType = "nil" }
ns.db = BuildDB(1000)
local saved = Persist:SaveAll()
Check("save reports success", saved, "SaveAll returned false")
Check("no database chunks written", Written() == 0, Written())
Check("no session stamp written", cvars["BTS_session"] == nil, cvars["BTS_session"])
Check("no save recorded", Persist.lastSave == nil)

-- 2. The game kept the file: nothing written either.
ns.Config.loadDiagnostics = { globalType = "table" }
Persist.storeCleared = nil
Persist:SaveAll()
Check("still no chunks when the game keeps data", Written() == 0, Written())

-- 3. Chunks an older version left still load once.
local old = BuildDB(1000)
local chunks = WriteOldStore(old)
Check("old store spans more than one chunk", chunks > 1, chunks)
local restored = Persist:LoadAll()
Check("old store loads", type(restored) == "table")
Check("prices survived", restored and DeepEqual(old.prices, restored.prices, "prices"))
Check("queue survived", restored and DeepEqual(old.queue, restored.queue, "queue"))

-- 4. And the next save empties them.
Persist.storeCleared = nil
Persist:SaveAll()
Check("old chunks emptied", Written() == 0, Written())
Check("store count reset", cvars["BTS_storeCount"] == "0", cvars["BTS_storeCount"])
Check("nothing loads afterwards", Persist:LoadAll() == nil)

-- 5. A missing chunk must be refused, not half-loaded.
WriteOldStore(BuildDB(1000))
cvars["BTS_store2"] = ""
warnings = {}
local broken = Persist:LoadAll()
Check("missing chunk refuses to load", broken == nil, "returned data anyway")
Check("missing chunk warns", #warnings > 0)

print(failures == 0 and "\nall persistence tests passed" or ("\n" .. failures .. " failure(s)"))
if failures > 0 then error(failures .. " persistence failure(s)") end
