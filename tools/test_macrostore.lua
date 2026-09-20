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
local MacroStore_Encode, MacroStore_Decode = Store.Encode, Store.Decode

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

-- 7. The encoding. Measured in game: the client appends a byte to every macro
--    body and eats "|" escapes, so nothing raw can be stored and exact
--    equality is the wrong test. Everything goes through the safe alphabet.
local function RoundTrip(name, data)
    local encoded = MacroStore_Encode(data)
    Check(name .. " survives the alphabet", encoded:match("^[A-Za-z0-9%-%.]*$") ~= nil, encoded)
    Check(name .. " round trips", MacroStore_Decode(encoded) == data,
        string.format("%q -> %q", data, tostring(MacroStore_Decode(encoded))))
end

RoundTrip("empty", "")
RoundTrip("one byte", "A")
RoundTrip("two bytes", "AB")
RoundTrip("three bytes", "ABC")
RoundTrip("four bytes", "ABCD")
RoundTrip("the serialiser's own punctuation", "t s4:name n1234; b1; ~ e")
RoundTrip("the characters the client mangles", "|n|r\\ \"'%")

local every = {}
for byte = 0, 255 do every[#every + 1] = string.char(byte) end
RoundTrip("every byte value", table.concat(every))

Check("corrupt text decodes to nil", MacroStore_Decode("!!!!") == nil)
Check("a lone trailing character is refused", MacroStore_Decode("AAAAA") == nil)

-- 8. A body the client came back longer than we wrote it.
Store:Write("BTSt06", MacroStore_Encode("payload"))
local index = IndexByName("BTSt06")
macros[index].body = macros[index].body .. "\n"          -- what the client does
Check("the appended byte is trimmed on read",
    MacroStore_Decode(Store:Read("BTSt06")) == "payload", tostring(Store:Read("BTSt06")))
Store:Clear()

--------------------------------------------------------------------------------
-- 9. The store: one payload across many macros, and the header that says so.
--------------------------------------------------------------------------------

time = function() return 1000 end

local Pack, Unpack = Store.Pack, Store.Unpack

Check("a number round trips", Unpack(Pack(123456, 4)) == 123456, Unpack(Pack(123456, 4)))
Check("zero round trips", Unpack(Pack(0, 3)) == 0)
Check("the width is respected", #Pack(5, 4) == 4, #Pack(5, 4))
Check("the largest value in three characters fits", Unpack(Pack(262143, 3)) == 262143)
-- Saturating rather than wrapping: a capped count is wrong by a little, a
-- wrapped one reads as a much smaller number and looks plausible.
Check("an overflowing number saturates", Unpack(Pack(262144, 3)) == 262143, Unpack(Pack(262144, 3)))
Check("text outside the alphabet unpacks to nil", Unpack("!!") == nil)

local room = 255 - #"/bts macrodata "

local function RoundTrip(name, payload)
    Check(name .. " saves", (Store:SaveData(payload)))
    local back, why = Store:LoadData()
    Check(name .. " loads back identical", back == payload, tostring(why or back))
end

RoundTrip("an empty payload", "")
RoundTrip("a short payload", "AbC123-.")
RoundTrip("exactly one full chunk", string.rep("A", room))
RoundTrip("one character more than a chunk", string.rep("B", room + 1))
RoundTrip("five chunks", string.rep("Cd9-.", room))

Check("the slot estimate matches what was written",
    Store.SlotsFor(room * 5) == select(2, Store:SaveData(string.rep("x", room * 5))) + 1,
    Store.SlotsFor(room * 5))

-- A payload that shrank must not leave the old tail behind for a later bug to
-- read as part of it.
Store:SaveData(string.rep("Q", room * 4))
Store:SaveData("short")
Check("a shrinking payload removes its old tail", Store:Read("BTSd03") == nil,
    tostring(Store:Read("BTSd03")))
Check("and still reads back correctly", Store:LoadData() == "short")

-- The header is written last precisely so a torn save is refusable. Both
-- failures below are what a half-finished write looks like from the outside.
Store:SaveData(string.rep("Zz", room))
local index = IndexByName("BTSd01")
macros[index].body = "/bts macrodata " .. string.rep("Yy", 50)
local back, why = Store:LoadData()
Check("a payload that no longer matches its header is refused", back == nil, tostring(back))
Check("and says why", type(why) == "string" and why ~= "", tostring(why))

Store:SaveData(string.rep("Ww", room))
DeleteMacro(IndexByName("BTSd02"))
back, why = Store:LoadData()
Check("a missing chunk is refused, not silently truncated", back == nil, tostring(back))

-- Same length, different content: only the checksum can catch this one.
Store:SaveData("AAAABBBB")
index = IndexByName("BTSd01")
macros[index].body = "/bts macrodata " .. "AAAABBBC"
Check("a same-length corruption is caught by the checksum", Store:LoadData() == nil)

-- A save that dies part way has already overwritten some chunks, so what is
-- stored is half one payload and half another. Loading that would hand back a
-- database made of two different saves, so it must refuse instead. The
-- checksum is what catches it: both payloads here are the same length on
-- purpose, so the length check cannot be what does the work.
Store:ClearData()
Store:SaveData(string.rep("Aa", room * 2))          -- a good payload, 4 chunks

local realEdit, realCreate = EditMacro, CreateMacro
local function FailOn(name)
    EditMacro = function(index, macroName, icon, body)
        if macroName == name then error("client refused") end
        return realEdit(index, macroName, icon, body)
    end
    CreateMacro = function(macroName, icon, body, perChar)
        if macroName == name then error("client refused") end
        return realCreate(macroName, icon, body, perChar)
    end
end

FailOn("BTSd03")
local saved, reason = Store:SaveData(string.rep("Bb", room * 2))
EditMacro, CreateMacro = realEdit, realCreate

Check("a save that dies part way reports failure", saved == false, tostring(saved))
Check("and names the chunk", type(reason) == "string" and reason:find("3") ~= nil, tostring(reason))
Check("an interrupted save never loads as a mixture", Store:LoadData() == nil,
    tostring(Store:LoadData()))

Store:ClearData()

Check("a payload outside the alphabet is refused",
    Store:SaveData("not safe!") == false)
Check("nothing stored reads as nil, with a reason",
    (Store:ClearData() >= 0) and Store:LoadData() == nil)

InCombatLockdown = function() return true end
Check("a save in combat is refused", Store:SaveData("Ab") == false)
InCombatLockdown = function() return false end

-- And through all of that, the player's own macros.
Store:SaveData(string.rep("Mm", room * 2))
Check("the player's macros survived the store entirely",
    macros[1].name == "Heal" and macros[2].name == "Pull",
    macros[1].name .. "/" .. macros[2].name)
Check("clearing removes every data macro", Store:ClearData() > 0)
Check("and leaves the player with exactly their two", #macros == 2, #macros)

print(failures == 0 and "\nall macro storage tests passed" or ("\n" .. failures .. " failure(s)"))
if failures > 0 then error(failures .. " macro storage failure(s)") end
