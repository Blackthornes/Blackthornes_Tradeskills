-- Blackthornes Tradeskills -- Locale/Locale.lua
-- The words players see, in the client's language where there is a
-- translation (Locale/deDE.lua), else in English.
--
-- The English text is the key: L["Feed"] is "Feed" until a translation
-- fills it in, so a string with no translation, or a whole language with
-- none, shows the English and never an empty space. It loads before every
-- other file (the TOC lists it first), so any file can wrap its words at
-- load.
--
-- Wrap a new string in L["..."] (or L.Format("... %s ...", value)), add its
-- line to Locale/deDE.lua, and run tools/check_locale.py, which lists keys
-- with no German line and German lines no longer used.
--
-- This file is meant to be the same in every Blackthornes addon; a fix to
-- it belongs in all of them once they have it.

local _, ns = ...

local L = setmetatable({}, {
    __index = function(_, key) return key end,
})
ns.L = L

--- The translation of `key` with the values put in, as string.format does.
--- A translation may name its values by place ("%2$s ... %1$s") where its
--- word order needs them; they are put in order here, since not every Lua
--- that runs this file (the tests' Lua 5.1) reads "%1$s" itself.
function L.Format(key, ...)
    local text = L[key]
    if not text:find("%%%d+%$") then return text:format(...) end

    local values, ordered, count = { ... }, {}, 0
    local out, at, next = {}, 1, 0
    while true do
        local start = text:find("%", at, true)
        if not start then
            out[#out + 1] = text:sub(at)
            break
        end
        out[#out + 1] = text:sub(at, start - 1)
        if text:sub(start + 1, start + 1) == "%" then
            out[#out + 1] = "%%"
            at = start + 2
        else
            local place, rest = text:match("^(%d+)%$()", start + 1)
            if place then
                count = count + 1
                ordered[count] = values[tonumber(place)]
                out[#out + 1] = "%"
                at = rest
            else
                next = next + 1
                count = count + 1
                ordered[count] = values[next]
                out[#out + 1] = "%"
                at = start + 1
            end
        end
    end
    return table.concat(out):format(unpack(ordered, 1, count))
end
