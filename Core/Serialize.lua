-- Blackthornes Tradeskills -- Core/Serialize.lua
-- Turning the database into a string and back.
--
-- Deliberately not Lua source run through loadstring. That is the usual trick
-- and it is faster to write, but it means executing whatever is in a CVar as
-- code, and a CVar is global client state that anything can write to. A parser
-- that can only ever produce data cannot be talked into doing anything else.
--
-- The format is unambiguous without whitespace or escaping, because strings
-- carry their own length:
--
--   nil      ~
--   boolean  b1;  b0;
--   number   n<value>;
--   string   s<length>:<bytes>
--   table    t <key><value> ... e

local _, ns = ...

local Serialize = {}
ns.Serialize = Serialize

--------------------------------------------------------------------------------
-- Encode
--------------------------------------------------------------------------------

-- %d is the natural way to write the item IDs and copper amounts that are
-- nearly all of this data, and it keeps them as short as they look -- but this
-- client's string.format converts a %d argument to a signed 32-bit integer and
-- throws past its range. On 2026-09-21 a browse row came back priced at
-- 9,999,990,200 copper (about 999,999g), "integer overflow attempting to store
-- 9999990200" came out of format, and the whole database save was lost with it.
--
-- So %d is used only where it is certainly safe, and anything larger goes
-- through %.0f, which hands the double straight to the float formatter with no
-- integer conversion anywhere: exact for whole numbers up to 2^53, and plain
-- digits rather than an exponent, so tonumber reads back the same value.
local SAFE_INTEGER_FORMAT = 2 ^ 31

local function FormatNumber(value)
    if value == math.floor(value) then
        if math.abs(value) < SAFE_INTEGER_FORMAT then
            return ("%d"):format(value)
        elseif math.abs(value) < 2 ^ 53 then
            return ("%.0f"):format(value)
        end
    end

    -- 17 significant digits is what it takes for a double to survive the trip
    -- exactly; 14 quietly rounds ratios like a moving average.
    return ("%.17g"):format(value)
end

-- One unformattable number must never cost the whole database, which is what
-- the failure above did: Persist wraps Encode in a pcall, so the throw came out
-- as "nothing was saved" rather than as one bad field. The paths above cannot
-- throw any more, and this makes sure no future one can either.
local function SafeFormatNumber(value)
    local ok, text = pcall(FormatNumber, value)
    if ok and type(text) == "string" then return text end

    local fallbackOk, fallback = pcall(string.format, "%.17g", value)
    if fallbackOk and type(fallback) == "string" then return fallback end

    return "0"
end

-- Keys in a fixed order, for EncodeCanonical: numbers first, then strings.
local function KeyOrder(a, b)
    local ta, tb = type(a), type(b)
    if ta ~= tb then return ta == "number" end
    return a < b
end

local function EncodeValue(value, out, seen, sorted)
    local kind = type(value)

    if value == nil then
        out[#out + 1] = "~"

    elseif kind == "boolean" then
        out[#out + 1] = value and "b1;" or "b0;"

    elseif kind == "number" then
        -- Infinities and NaN have no text form that reads back, and writing
        -- one is exactly how a saved file becomes unparseable. Dropped rather
        -- than stored as a number that lies.
        if value ~= value or value == math.huge or value == -math.huge then
            out[#out + 1] = "~"

        else
            out[#out + 1] = "n" .. SafeFormatNumber(value) .. ";"
        end

    elseif kind == "string" then
        out[#out + 1] = "s" .. #value .. ":" .. value

    elseif kind == "table" then
        -- Cheaper than tracking every table: this data is a tree, and a cycle
        -- would mean a bug elsewhere. Better to refuse than to hang.
        if seen[value] then
            error("cannot serialise a table that contains itself")
        end
        seen[value] = true

        out[#out + 1] = "t"

        local keys
        if sorted then
            keys = {}
            for k in pairs(value) do
                local vk = type(k)
                if vk == "number" or vk == "string" then keys[#keys + 1] = k end
            end
            table.sort(keys, KeyOrder)
        end

        local function One(k, v)
            -- Functions and userdata have no meaning once stored, so they are
            -- skipped rather than failing the whole save.
            local vk, vv = type(k), type(v)
            if (vk == "number" or vk == "string")
                and (vv ~= "function" and vv ~= "userdata" and vv ~= "thread") then
                EncodeValue(k, out, seen, sorted)
                EncodeValue(v, out, seen, sorted)
            end
        end

        if keys then
            for i = 1, #keys do One(keys[i], value[keys[i]]) end
        else
            for k, v in pairs(value) do One(k, v) end
        end
        out[#out + 1] = "e"

        seen[value] = nil
    else
        error("cannot serialise a " .. kind)
    end
end

function Serialize.Encode(value)
    local out = {}
    EncodeValue(value, out, {})
    return table.concat(out)
end

--- Encode with every table's keys in a fixed order, so the same data always
--- gives the same text. Slower; for comparing data (Core/Comm.lua's Hash),
--- where pairs' order changing between sessions would make it differ.
function Serialize.EncodeCanonical(value)
    local out = {}
    EncodeValue(value, out, {}, true)
    return table.concat(out)
end

--------------------------------------------------------------------------------
-- Decode
--------------------------------------------------------------------------------

local DecodeValue

--- @return value, nextPosition
DecodeValue = function(text, position)
    local tag = text:sub(position, position)

    if tag == "" then
        error("unexpected end of data")

    elseif tag == "~" then
        return nil, position + 1

    elseif tag == "b" then
        return text:sub(position + 1, position + 1) == "1", position + 3

    elseif tag == "n" then
        local stop = text:find(";", position + 1, true)
        if not stop then error("unterminated number") end

        local number = tonumber(text:sub(position + 1, stop - 1))
        if not number then error("malformed number") end

        return number, stop + 1

    elseif tag == "s" then
        local colon = text:find(":", position + 1, true)
        if not colon then error("unterminated string") end

        local length = tonumber(text:sub(position + 1, colon - 1))
        local first = colon + 1
        -- A negative length stepped back through the text, and a table being
        -- read then never reached its end: one bad message from anyone froze
        -- the game. A length past the end is as broken.
        if not length or length < 0 or length % 1 ~= 0 or first + length - 1 > #text then
            error("malformed string length")
        end
        return text:sub(first, first + length - 1), first + length

    elseif tag == "t" then
        local result = {}
        position = position + 1

        while true do
            if text:sub(position, position) == "e" then
                return result, position + 1
            end

            if position > #text then error("unterminated table") end

            local key, value, before = nil, nil, position
            key, position = DecodeValue(text, position)
            value, position = DecodeValue(text, position)
            -- Every pair moves on, or the stream is corrupt.
            if position <= before then error("malformed table") end

            -- A nil key would be a corrupt stream rather than real data.
            if key ~= nil then result[key] = value end
        end
    end

    error("unknown tag '" .. tag .. "'")
end

--- Parse a string produced by Encode.
-- @return ok, value|error
function Serialize.Decode(text)
    if type(text) ~= "string" or text == "" then
        return false, "empty"
    end
    return pcall(function()
        local value = DecodeValue(text, 1)
        return value
    end)
end
