-- The cold-start half of the CVar store.
--
-- test_persist.lua covers the round trip against a client whose RegisterCVar
-- leaves an existing value alone. That is the well-behaved case, and it is
-- also the only case a /reload or a trip to character select can ever
-- exercise, because neither ends the client process and the name is therefore
-- already registered.
--
-- This one models the other client: one where registering a name writes the
-- default over whatever was loaded at launch. Under that client the old code
-- erased the store on the way in and then reported it as absent, which is
-- indistinguishable from never having saved it. The fix is to read before
-- registering and put back what registration swallowed.

local cvars = {}
local clobberOnRegister = false

local function MakeCVarAPI()
    return {
        RegisterCVar = function(name, value)
            if clobberOnRegister then
                -- What a client does when it has no record of the name from
                -- its config file: create it, at the default.
                cvars[name] = value or ""
            elseif cvars[name] == nil then
                cvars[name] = value or ""
            end
        end,
        GetCVar = function(name) return cvars[name] end,
        SetCVar = function(name, value) cvars[name] = tostring(value) end,
    }
end

C_CVar = MakeCVarAPI()

local clock = { now = 1000000, uptime = 500 }

time = function() return clock.now end
GetTime = function() return clock.uptime end

local ns = {}
local module = {}

ns.NewModule = function(_) return module end
ns.Warn = function() end
ns.Print = function() end
ns.PrintRaw = function() end
ns.RegisterCommand = function() end
ns.RegisterEvent = function() end
ns.COLORS = { muted = "ff000000", warn = "ff000000" }
ns.Util = { Comma = function(n) return tostring(n) end }
ns.Config = { GetRealmKey = function() return "Classic Beta PvE 2-Horde" end }

loadfile("Core/Serialize.lua")("Blackthornes_TS", ns)
loadfile("Core/Persist.lua")("Blackthornes_TS", ns)

local Persist = ns.Persist or module

ns.Compat = { Detect = function()
    return { cvars = { roundTrip = true, registerVia = "RegisterCVar" } }
end }

local failures = 0
local function Check(name, ok, detail)
    print(string.format("  %-44s %s", name, ok and "ok" or ("FAIL " .. tostring(detail))))
    if not ok then failures = failures + 1 end
end

local function BuildDB(priceCount)
    local db = { prices = { ["Classic Beta PvE 2-Horde"] = {} }, queue = {}, settings = {} }
    for i = 1, priceCount do
        db.prices["Classic Beta PvE 2-Horde"][2000 + i] =
            { market = 1234 + i, lastSeen = 1000000 + i }
    end
    return db
end

--- Everything a new client process forgets, and nothing it does not: the
--- addon's Lua state goes, the CVars stay.
local function NewSession()
    Persist.registered = nil
    Persist.peeked = nil
    Persist.recovered = nil
    Persist.recoveredNames = nil
end

--------------------------------------------------------------------------------

-- 1. Save from one process.
ns.db = BuildDB(200)
Check("save succeeds", Persist:SaveAll())
Check("session stamp written", cvars["BTS_session"] == "999500,1000000", cvars["BTS_session"])

-- 2. A /reload: same process, so the clock agrees.
NewSession()
clock.uptime = 900
clock.now = 1000400

local peek = Persist:Peek()
Check("reload is not reported as a cold start", peek.coldStart == false, tostring(peek.coldStart))
Check("reload sees the stored chunks", peek.present > 0 and peek.bytes > 0, peek.present)

-- 3. A restart: new process, and a client that clobbers on register.
NewSession()
clock.now = 1010000
clock.uptime = 100
clobberOnRegister = true

peek = Persist:Peek()
Check("restart is reported as a cold start", peek.coldStart == true, tostring(peek.coldStart))
Check("peek reads the count before registering", peek.count > 0, peek.count)

local restored = Persist:LoadAll()
Check("data survives a clobbering register", type(restored) == "table",
    "LoadAll returned " .. type(restored))

if type(restored) == "table" then
    local count = 0
    for _ in pairs(restored.prices["Classic Beta PvE 2-Horde"]) do count = count + 1 end
    Check("every price came back", count == 200, count)
end

Check("recovery was counted, not silent", (Persist.recovered or 0) > 0, Persist.recovered)

-- 4. The same client, once the store really is empty: no false positives, and
--    no claim that anything was recovered.
NewSession()
cvars = {}
C_CVar = MakeCVarAPI()
clock.now = 1020000

peek = Persist:Peek()
Check("an empty store reports no chunks", peek.present == 0, peek.present)
Check("an empty store cannot judge cold start", peek.coldStart == nil, tostring(peek.coldStart))
Check("nothing loads from nothing", Persist:LoadAll() == nil)
Check("nothing was claimed as recovered", (Persist.recovered or 0) == 0, Persist.recovered)

print(failures == 0 and "\nall cold-start tests passed" or ("\n" .. failures .. " failure(s)"))
if failures > 0 then error(failures .. " cold-start failure(s)") end
