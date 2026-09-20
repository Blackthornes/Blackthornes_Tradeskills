-- Macro storage: the round trip, the limits, and not touching anyone else's
-- macros.
--
-- The point of interest is DeleteMacro, which shifts every index above the one
-- it removes. Anything that collects indices first and deletes them afterwards
-- deletes the wrong macros -- and in this case the wrong macros belong to the
-- player. So Clear looks each name up again on every pass, and this checks
-- that it does.

local macros = {}   -- ordered list of { name, body }

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
    if not macros[index] then error("no such macro") end
    macros[index] = { name = name, body = body }
    return index
end

DeleteMacro = function(index)
    if not macros[index] then error("no such macro") end
    table.remove(macros, index)       -- everything above shifts down
end

GetMacroInfo = function(index)
    local macro = macros[index]
    if not macro then return nil end
    return macro.name, 134400, macro.body
end

GetMacroIndexByName = IndexByName
GetNumMacros = function() return #macros, 0 end
InCombatLockdown = function() return false end

local ns = {}
local module = {}

ns.NewModule = function(_) return module end
ns.Print = function() end
ns.PrintRaw = function() end
ns.Warn = function() end
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

loadfile("Core/MacroStore.lua")("Blackthornes_TS", ns)
local Store = ns.MacroStore or module

local failures = 0
local function Check(name, ok, detail)
    print(string.format("  %-46s %s", name, ok and "ok" or ("FAIL " .. tostring(detail))))
    if not ok then failures = failures + 1 end
end

--------------------------------------------------------------------------------

Check("the client's macro API is detected", Store:Detect().usable)

-- The player's own macros, which must come through all of this untouched.
CreateMacro("Heal", 1, "/cast Healing Wave")
CreateMacro("Pull", 1, "/cast Lightning Bolt")

-- 1. A round trip.
Check("a write succeeds", Store:Write("BTSt01", "hello world"))
Check("a read returns the payload alone", Store:Read("BTSt01") == "hello world", Store:Read("BTSt01"))
Check("the body is a real command", macros[IndexByName("BTSt01")].body == "/bts macrodata hello world",
    macros[IndexByName("BTSt01")].body)

-- 2. Rewriting a name must replace, not accumulate.
local before = #macros
Store:Write("BTSt01", "second")
Check("rewriting replaces in place", #macros == before, #macros)
Check("and the new value reads back", Store:Read("BTSt01") == "second")

-- 3. The body limit is 255 including the command that carries it.
local room = 255 - #"/bts macrodata "
Check("a payload that just fits is accepted", Store:Write("BTSt02", string.rep("x", room)))
Check("one byte more is refused", Store:Write("BTSt03", string.rep("x", room + 1)) == false)
Check("the refused one was not created", IndexByName("BTSt03") == 0)

-- 4. A name that was never written reads as nil, not as an empty string.
Check("an absent macro reads nil", Store:Read("BTSt09") == nil)

-- 5. Clearing takes ours and leaves the player's alone.
Store:Write("BTSt04", "a")
Store:Write("BTSt05", "b")
Store:Write("BTStX", "tricky")

local removed = Store:Clear()
Check("clear removed every one of ours", removed == 5, removed)
Check("the player's macros are untouched", #macros == 2, #macros)
Check("and they are the right two",
    macros[1].name == "Heal" and macros[2].name == "Pull",
    macros[1].name .. "/" .. macros[2].name)
Check("clearing again removes nothing", Store:Clear() == 0)

-- 6. In combat, a write is refused rather than raising.
InCombatLockdown = function() return true end
local ok, why = Store:Write("BTSt01", "x")
Check("a write in combat is refused", ok == false and why == "in combat", tostring(why))
InCombatLockdown = function() return false end

print(failures == 0 and "\nall macro storage tests passed" or ("\n" .. failures .. " failure(s)"))
if failures > 0 then error(failures .. " macro storage failure(s)") end
