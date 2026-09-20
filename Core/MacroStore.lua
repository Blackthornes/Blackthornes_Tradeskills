-- Blackthornes Tradeskills -- Core/MacroStore.lua
-- Measuring whether macros can hold this addon's data across a client restart.
--
-- Why macros at all: on this build the client writes SavedVariables and never
-- reads them back, account-level and per-character alike, and registered CVars
-- live only as long as the client process. Macros are different in kind --
-- they are held server-side rather than in a file, which is why they come back
-- after a restart when nothing local does.
--
-- That is reported of this build by someone else, not measured by us, and this
-- project has been caught three times believing a capability it had not
-- observed. So this file measures first and stores nothing. `/bts macrotest`
-- writes a known payload, and after a real restart reports how much of it came
-- back, byte for byte.
--
-- The budget is the reason this needs measuring rather than estimating: a
-- macro body holds about 255 characters and a player has 120 of them account
-- wide, so the ceiling is roughly 30KB for the whole addon -- and every byte
-- of it is a macro slot taken from the player.

local _, ns = ...

local MacroStore = ns.NewModule("MacroStore")

local NAME_PREFIX = "BTSt"          -- names must fit 16 characters
local COMMAND = "/bts macrodata "   -- a real command, so clicking one is harmless
local BODY_LIMIT = 255

-- What a serialised table actually uses, minus the two characters that are
-- dangerous in a macro body: "|" starts a UI escape sequence and a newline
-- ends the command. Whether those two survive is asked separately, because
-- finding out by corrupting the payload would tell us nothing about the rest.
local ALPHABET = "0123456789,;=[]{}-. abcdefghijklmnopqrstuvwxyz"
local TRICKY = "|n|r\\ \"'%%"

local function Payload(length)
    local pattern = ALPHABET:rep(math.ceil(length / #ALPHABET))
    return pattern:sub(1, length)
end

--------------------------------------------------------------------------------
-- The client's macro API
--------------------------------------------------------------------------------

--- Which of the macro functions this build has, and whether they are usable.
function MacroStore:Detect()
    if self.caps then return self.caps end

    local caps = {
        create = ns.Util.HasFunction("CreateMacro"),
        edit = ns.Util.HasFunction("EditMacro"),
        delete = ns.Util.HasFunction("DeleteMacro"),
        getInfo = ns.Util.HasFunction("GetMacroInfo"),
        getIndex = ns.Util.HasFunction("GetMacroIndexByName"),
        getCount = ns.Util.HasFunction("GetNumMacros"),
    }

    caps.usable = caps.create and caps.getInfo and caps.getIndex and caps.delete

    self.caps = caps
    return caps
end

--- Free account-wide macro slots, or nil when the client will not say.
function MacroStore:FreeSlots()
    if not self:Detect().getCount then return nil end

    local ok, general = pcall(GetNumMacros)
    if not ok or type(general) ~= "number" then return nil end

    return 120 - general, general
end

local function BodyOf(index)
    local ok, _, _, body = pcall(GetMacroInfo, index)
    if not ok or type(body) ~= "string" then return nil end
    return body
end

--- Read back what one of our macros holds, or nil if it is not there.
function MacroStore:Read(name)
    local ok, index = pcall(GetMacroIndexByName, name)
    if not ok or type(index) ~= "number" or index == 0 then return nil end

    local body = BodyOf(index)
    if not body then return nil end

    -- Only the payload, never the command that carries it.
    local data = body:match("^" .. COMMAND:gsub("%-", "%%-") .. "(.*)$")
    return data
end

--- Write one macro, replacing any of ours already under that name.
-- @return true when the client accepted it
function MacroStore:Write(name, data)
    if InCombatLockdown and InCombatLockdown() then return false, "in combat" end

    local body = COMMAND .. data
    if #body > BODY_LIMIT then return false, "body too long" end

    local ok, index = pcall(GetMacroIndexByName, name)

    if ok and type(index) == "number" and index > 0 then
        return (pcall(EditMacro, index, name, nil, body))
    end

    -- A fileID rather than a texture path: this build takes either from some
    -- callers and only the ID from others, and a refused icon fails the whole
    -- call rather than just looking wrong.
    local made = pcall(CreateMacro, name, 134400, body, false)
    if not made then
        made = pcall(CreateMacro, name, "INV_Misc_QuestionMark", body, false)
    end

    return made
end

--- Remove every macro this addon made. Ours are the only ones touched.
function MacroStore:Clear()
    local removed = 0

    for index = 40, 1, -1 do
        local name = ("%s%02d"):format(NAME_PREFIX, index)
        local ok, found = pcall(GetMacroIndexByName, name)

        if ok and type(found) == "number" and found > 0 then
            if pcall(DeleteMacro, found) then removed = removed + 1 end
        end
    end

    local ok, found = pcall(GetMacroIndexByName, NAME_PREFIX .. "X")
    if ok and type(found) == "number" and found > 0 then
        if pcall(DeleteMacro, found) then removed = removed + 1 end
    end

    return removed
end

--------------------------------------------------------------------------------
-- The test
--------------------------------------------------------------------------------

local DATA_BYTES = BODY_LIMIT - #COMMAND

--- Write the payload, to be read back after a restart.
function MacroStore:StartTest(count)
    local caps = self:Detect()

    if not caps.usable then
        ns.Print("this client does not expose enough of the macro API to store anything.")
        return
    end

    count = math.max(1, math.min(count or 10, 40))

    local free = self:FreeSlots()
    if free and free < count + 1 then
        ns.Warn(("only %d macro slot(s) free; asking for %d."):format(free, count + 1))
        return
    end

    local written = 0

    for index = 1, count do
        local name = ("%s%02d"):format(NAME_PREFIX, index)
        local ok = self:Write(name, Payload(DATA_BYTES))

        if not ok then
            ns.Print(("the client refused macro %d."):format(index))
            break
        end

        written = written + 1
    end

    -- Asked separately: a character that a macro body mangles would otherwise
    -- look like the store failing rather than like an encoding that needs
    -- escaping before it goes in.
    self:Write(NAME_PREFIX .. "X", TRICKY)

    ns.Print(("wrote %d macro(s) of %d bytes, plus one of awkward characters.")
        :format(written, DATA_BYTES))
    ns.Print("Now |cffffffffquit the game completely|r, start it again, and run |cffffffff/bts macrotest|r.")
    ns.Print("|cffffffff/bts macrotest clear|r removes them all afterwards.")
end

--- Report what came back.
function MacroStore:Report()
    local caps = self:Detect()

    ns.Print("macro storage")

    if not caps.usable then
        ns.PrintRaw("  the client does not expose enough of the macro API.")
        return
    end

    local free, used = self:FreeSlots()
    ns.PrintRaw(("  slots:    %s used, %s free of 120"):format(
        tostring(used or "?"), tostring(free or "?")))

    local expected = Payload(DATA_BYTES)
    local found, intact, returned = 0, 0, 0

    for index = 1, 40 do
        local data = self:Read(("%s%02d"):format(NAME_PREFIX, index))

        if data then
            found = found + 1
            returned = returned + #data
            if data == expected then intact = intact + 1 end
        end
    end

    if found == 0 then
        ns.PrintRaw("  no test macros found. Run |cffffffff/bts macrotest 10|r to write some.")
        return
    end

    ns.PrintRaw(("  payload:  %d of %d macro(s) came back byte for byte (%s of %s bytes)")
        :format(intact, found, ns.Util.Comma(returned), ns.Util.Comma(found * DATA_BYTES)))

    local tricky = self:Read(NAME_PREFIX .. "X")
    ns.PrintRaw(("  awkward characters: %s"):format(
        tricky == TRICKY and "survived" or
        (tricky and ("mangled -- came back as " .. tricky) or "did not come back")))

    -- The session stamp from Core/Persist.lua, so this says whether the client
    -- actually restarted rather than trusting anyone to remember.
    local peek = ns.Persist and ns.Persist:Peek()

    if peek and peek.coldStart == true then
        ns.PrintRaw("  the client did restart in between, so this is the real answer.")
    elseif peek and peek.coldStart == false then
        ns.Warn("this is the same client process that wrote them, so it proves nothing. Quit fully and run it again.")
    end

    if intact > 0 then
        ns.PrintRaw(("  budget:   about %s bytes across all 120 slots")
            :format(ns.Util.Comma(120 * DATA_BYTES)))
    end
end

--------------------------------------------------------------------------------
-- Commands
--------------------------------------------------------------------------------

-- The body of every macro this addon writes, so that clicking one does
-- nothing but say what it is.
ns.RegisterCommand("macrodata", "(stored data; nothing to run)", function()
    ns.Print("that macro is storage for this addon, not a command to run.")
end)

ns.RegisterCommand("macrotest", "test what macros keep across a restart: /bts macrotest [n|clear]", function(args)
    args = (args or ""):lower()

    if args == "clear" then
        ns.Print(("removed %d test macro(s)."):format(ns.MacroStore:Clear()))
        return
    end

    local count = tonumber(args:match("^(%d+)$"))

    if count then
        ns.MacroStore:StartTest(count)
    else
        ns.MacroStore:Report()
    end
end)
