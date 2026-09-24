-- The old storage macros are removed only when the game kept the saved data,
-- only ours are touched, and the report counts what is really gone.

local macros
local function Reset(list)
    macros = {}
    for _, name in ipairs(list) do macros[#macros + 1] = name end
end

GetMacroIndexByName = function(name)
    for index, existing in ipairs(macros) do
        if existing == name then return index end
    end
    return 0
end
DeleteMacro = function(index) table.remove(macros, index) end   -- shifts, like the client

local inCombat = false
InCombatLockdown = function() return inCombat end

local ns = {}
local printed, warned = {}, {}
ns.Print = function(text) printed[#printed + 1] = text end
ns.Warn = function(text) warned[#warned + 1] = text end
local events = {}
ns.RegisterEvent = function(owner, event, fn) events[event] = fn end
ns.UnregisterEvent = function(owner, event) events[event] = nil end
ns.NewModule = function(name) local m = {}; ns[name] = m; return m end

local keeps = true
ns.Persist = { GameKeepsSavedData = function() return keeps end }

loadfile("Core/OldMacros.lua")("Blackthornes_TS", ns)
local OldMacros = ns.OldMacros

local function Has(name)
    for _, existing in ipairs(macros) do if existing == name then return true end end
    return false
end

-- 1. Saved data loaded: ours go, the player's stay, in any order.
Reset({ "Heal", "BTSd00", "BTSd01", "Mount", "BTSd02", "BTSt01", "BTStX", "BTSdX" })
printed, warned = {}, {}
OldMacros:Run()
assert(not Has("BTSd00") and not Has("BTSd01") and not Has("BTSd02"), "a BTSd macro survived")
assert(not Has("BTSt01") and not Has("BTStX"), "a BTSt macro survived")
assert(Has("Heal") and Has("Mount") and Has("BTSdX"), "a macro that is not ours was removed")
assert(#printed == 1 and printed[1]:find("removed 5 "), "report: " .. tostring(printed[1]))

-- 2. Saved data did not load: nothing is touched, nothing said.
Reset({ "BTSd00", "BTSd01" })
keeps, printed = false, {}
OldMacros:Run()
assert(Has("BTSd00") and Has("BTSd01"), "removed macros that may be the last copy")
assert(#printed == 0, "spoke when it did nothing")
keeps = true

-- 3. In combat: waits, then removes once combat ends.
Reset({ "BTSd00" })
inCombat, printed = true, {}
OldMacros:Run()
assert(Has("BTSd00"), "edited macros in combat")
assert(events.PLAYER_REGEN_ENABLED, "did not wait for combat to end")
inCombat = false
events.PLAYER_REGEN_ENABLED()
assert(not Has("BTSd00"), "did not remove after combat")
assert(events.PLAYER_REGEN_ENABLED == nil, "left the combat handler registered")

-- 4. A delete that does nothing is reported, not claimed.
Reset({ "BTSd00", "BTSd01" })
local realDelete = DeleteMacro
DeleteMacro = function() end
printed, warned = {}, {}
OldMacros:Run()
assert(#warned == 1 and warned[1]:find("2 could not"), "failed delete: " .. tostring(warned[1]))
DeleteMacro = realDelete

-- 5. Nothing there: silent.
Reset({ "Heal" })
printed, warned = {}, {}
OldMacros:Run()
assert(#printed == 0 and #warned == 0, "spoke with nothing to remove")

print("all old-macro tests passed")
