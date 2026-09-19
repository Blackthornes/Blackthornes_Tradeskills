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

local function EncodeValue(value, out, seen)
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

        elseif value == math.floor(value) and math.abs(value) < 2 ^ 53 then
            -- Item IDs and copper amounts are nearly all of this data, and
            -- %d keeps them as short as they look.
            out[#out + 1] = "n" .. ("%d"):format(value) .. ";"

        else
            -- 17 significant digits is what it takes for a double to survive
            -- the trip exactly; 14 quietly rounds ratios like a moving average.
            out[#out + 1] = "n" .. ("%.17g"):format(value) .. ";"
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
        for k, v in pairs(value) do
            -- Functions and userdata have no meaning once stored, so they are
            -- skipped rather than failing the whole save.
            local vk, vv = type(k), type(v)
            if (vk == "number" or vk == "string")
                and (vv ~= "function" and vv ~= "userdata" and vv ~= "thread") then
                EncodeValue(k, out, seen)
                EncodeValue(v, out, seen)
            end
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
        if not length then error("malformed string length") end

        local first = colon + 1
        return text:sub(first, first + length - 1), first + length

    elseif tag == "t" then
        local result = {}
        position = position + 1

        while true do
            if text:sub(position, position) == "e" then
                return result, position + 1
            end

            local key, value
            key, position = DecodeValue(text, position)
            value, position = DecodeValue(text, position)

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
