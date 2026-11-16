-- The travel map's driver rests while no trip is set, outside WoW.
--
-- What must hold:
--   1. With no trip, the driver's frame hides after its first look, so
--      nothing runs each frame.
--   2. One look a second while resting; a trip set brings the driver back.
--   3. In a fight it keeps looking, so old lines clear when the fight ends.

local GLOBALS = { "CreateFrame", "UIParent", "C_Timer", "InCombatLockdown", "WorldMapFrame" }
local saved = {}
for _, key in ipairs(GLOBALS) do saved[key] = rawget(_G, key) end

local failures = 0
local function check(label, got, want)
    local ok = got == want
    if not ok then failures = failures + 1 end
    print(("  %-4s  %-52s %s"):format(ok and "ok" or "FAIL", label,
        ok and tostring(got) or ("got " .. tostring(got) .. ", wanted " .. tostring(want))))
end

local driver
CreateFrame = function()
    driver = { shown = false }
    function driver:SetScript(_, fn) self.onUpdate = fn end
    function driver:Show() self.shown = true end
    function driver:Hide() self.shown = false end
    return driver
end
UIParent = {}
WorldMapFrame = nil
local fighting = false
InCombatLockdown = function() return fighting end
local waiting = {}
C_Timer = { After = function(_, fn) waiting[#waiting + 1] = fn end }
local function RunTimers()
    local due = waiting
    waiting = {}
    for _, fn in ipairs(due) do fn() end
end

local state = {}
local TravelMap = {}
local ns = {
    NewModule = function() return TravelMap end,
    Travel = { Host = { State = function() return state end, Here = function() return nil end } },
}
local chunk = assert(loadfile(lfs_cwd .. "/UI/TravelMap.lua"))
chunk("Blackthornes_TS", ns)

print("\ntravel map: resting with no trip")
TravelMap:OnEnable()
check("the driver starts awake", driver.shown, true)
driver.onUpdate(driver, 0.1)
check("a short step changes nothing", driver.shown, true)
driver.onUpdate(driver, 0.5)
check("no trip: the driver rests after its look", driver.shown, false)
check("with one look waiting", #waiting, 1)
RunTimers()
check("still no trip: still resting", driver.shown, false)
check("and one look waiting again", #waiting, 1)

print("\ntravel map: a trip wakes it")
state.trip = { plan = { key = "a", steps = {} } }
RunTimers()
check("the driver is back", driver.shown, true)
check("with no look left waiting", #waiting, 0)
driver.onUpdate(driver, 0.6)
check("and stays up while the trip is set", driver.shown, true)

print("\ntravel map: a fight keeps it looking")
state.trip = nil
fighting = true
driver.onUpdate(driver, 0.6)
check("no trip, in a fight: still awake", driver.shown, true)
fighting = false
driver.onUpdate(driver, 0.6)
check("the fight over: it rests", driver.shown, false)

for _, key in ipairs(GLOBALS) do _G[key] = saved[key] end

print(("\n%s"):format(failures == 0 and "all checks passed" or (failures .. " failure(s)")))
if failures > 0 then error(("%d check(s) failed"):format(failures)) end
