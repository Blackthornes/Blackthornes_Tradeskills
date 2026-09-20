-- A save asked for inside a minute of the last one.
--
-- SaveLater refused to write within sixty seconds of the last write, which
-- is right, but it dropped the request rather than deferring it. The change
-- then waited for the next thing to ask for a save, and on a disconnect
-- nothing did.

local cvars = {}
C_CVar = {
    RegisterCVar = function(name, value) if cvars[name] == nil then cvars[name] = value or "" end end,
    GetCVar = function(name) return cvars[name] end,
    SetCVar = function(name, value) cvars[name] = tostring(value) end,
}
time = os.time

local clock = 1000
GetTime = function() return clock end

local timers = {}
C_Timer = {
    NewTimer = function(delay, fn)
        local timer = { at = clock + delay, fn = fn, cancelled = false }
        timers[#timers + 1] = timer
        return { Cancel = function() timer.cancelled = true end }
    end,
}

-- Advance the clock, firing timers as their moment passes.
local function Advance(seconds)
    local target = clock + seconds
    while true do
        local nextTimer
        for _, timer in ipairs(timers) do
            if not timer.cancelled and timer.at <= target and (not nextTimer or timer.at < nextTimer.at) then
                nextTimer = timer
            end
        end
        if not nextTimer then break end
        nextTimer.cancelled = true
        clock = nextTimer.at
        nextTimer.fn()
    end
    clock = target
end

local ns = {}
ns.NewModule = function(_) return {} end
ns.Warn = function() end
ns.Print = function() end
ns.RegisterCommand = function() end
ns.RegisterEvent = function() end
ns.Util = { Comma = function(n) return tostring(n) end }
ns.Config = { GetRealmKey = function() return "TestRealm" end }

loadfile("Core/Serialize.lua")("Blackthornes_TS", ns)

local module = {}
ns.NewModule = function(_) return module end
loadfile("Core/Persist.lua")("Blackthornes_TS", ns)
local Persist = ns.Persist or module

ns.Compat = { Detect = function() return { cvars = { roundTrip = true, registerVia = "RegisterCVar" } } end }
ns.db = { settings = { minProfit = 1 }, queue = {}, prices = {} }

local writes = 0
local RealSaveAll = Persist.SaveAll
Persist.SaveAll = function(self, ...)
    writes = writes + 1
    return RealSaveAll(self, ...)
end

local failures = 0
local function Check(name, ok, detail)
    print(string.format("  %-52s %s", name, ok and "ok" or ("FAIL " .. tostring(detail))))
    if not ok then failures = failures + 1 end
end

print("\nsaving inside the minute")

-- A first write, then a change thirty seconds later.
Persist:SaveLater(5)
Advance(10)
Check("the first request writes", writes == 1, writes)

Advance(20)
Persist:SaveLater(5)
Advance(10)
Check("inside the minute nothing is written yet", writes == 1, writes)

-- Nothing else asks. The minute ends.
Advance(60)
Check("the deferred request writes when the minute is up", writes == 2, writes)
Check("and only once", writes == 2, writes)

-- Nothing pending afterwards.
Advance(600)
Check("no stray timer keeps writing", writes == 2, writes)

if failures > 0 then error(failures .. " save-later failure(s)") end
print("\nall save-later tests passed")
