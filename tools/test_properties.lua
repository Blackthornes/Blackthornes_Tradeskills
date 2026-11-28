-- Things about telling characters apart that must hold for any saved
-- characters, tried with many random ones (Core/Characters.lua). A property
-- test states something that can never be false and throws hundreds of
-- made-up cases at it. The seed is fixed so a failure comes back the same
-- each run; the failing case is printed. (The other always-true tests:
-- tools/test_properties_window.lua and tools/test_properties_serialize.lua.)
--
-- What must hold, for any characters on the account:
--   1. Every key is the same character as itself.
--   2. Same(a, b) and Same(b, a) always agree.
--   3. Two different GUID records are never the same character, whatever
--      their names.
--   4. A retired key is the character it went into, and Canonical gives
--      the same answer when asked twice.
--   5. IsPlaying is true for the one playing and for its retired keys, and
--      never for another GUID record.

local ns = {}
ns.NewModule = function(name) local m = { moduleName = name } ns[name] = m return m end
assert(loadfile("Core/Characters.lua"))("Blackthornes_TS", ns)
local Characters = ns.Characters
local playing
ns.Config = { GetCharacterKey = function() return playing end }

math.randomseed(20261117)
local TRIES = 300
local checks = 0
local function Check(ok, what)
    checks = checks + 1
    if not ok then error("properties: " .. what, 0) end
end

local FIRST = { "Ana", "Bob", "Cor", "Dax" }
local LAST = { "Stone", "Blackthorne", "Reed" }
local CLASS = { "Mage", "Rogue", "Hunter" }

local function Pick(list) return list[math.random(#list)] end

for i = 1, TRIES do
    local characters, former, guids, keys = {}, {}, {}, {}
    for j = 1, math.random(1, 6) do
        local guid = ("Player-1-%04d%02d"):format(i, j)
        characters[guid] = { name = Pick(FIRST), surname = math.random(1, 4) > 1 and Pick(LAST) or nil,
            realm = "Forever PvE", faction = "Horde", class = Pick(CLASS), guid = guid }
        guids[#guids + 1] = guid
        keys[#keys + 1] = guid
    end
    -- Old name-realm records, some stamped with a GUID, some not.
    for j = 1, math.random(0, 3) do
        local key = Pick(FIRST) .. "-Forever PvE" .. j
        characters[key] = { name = key:match("^(%a+)"), realm = "Forever PvE", faction = "Horde",
            class = Pick(CLASS), guid = math.random(1, 2) == 1 and Pick(guids) or nil }
        keys[#keys + 1] = key
    end
    -- Retired keys, folded into a GUID record.
    local retired = {}
    for j = 1, math.random(0, 3) do
        local key = "Old-" .. i .. "-" .. j
        local into = Pick(guids)
        former[key] = { retiredInto = into }
        retired[key] = into
        keys[#keys + 1] = key
    end
    ns.db = { characters = characters, formerCharacters = former }
    playing = Pick(guids)

    local case = ("try %d (%d keys)"):format(i, #keys)
    for _, a in ipairs(keys) do
        Check(Characters:Same(a, a), case .. ": " .. a .. " is itself")
        local canon = Characters:Canonical(a)
        Check(Characters:Canonical(canon) == canon, case .. ": Canonical twice changes " .. a)
        for _, b in ipairs(keys) do
            Check(Characters:Same(a, b) == Characters:Same(b, a),
                case .. ": Same(" .. a .. ", " .. b .. ") and Same(" .. b .. ", " .. a .. ") differ")
        end
    end
    for _, a in ipairs(guids) do
        for _, b in ipairs(guids) do
            if a ~= b then
                Check(not Characters:Same(a, b), case .. ": two GUID records taken as one: " .. a .. ", " .. b)
            end
        end
        Check(Characters:IsPlaying(a) == (a == playing), case .. ": IsPlaying wrong for " .. a)
    end
    for key, into in pairs(retired) do
        Check(Characters:Same(key, into), case .. ": " .. key .. " is the character it went into")
        Check(Characters:IsPlaying(key) == (into == playing), case .. ": IsPlaying wrong for retired " .. key)
    end
end

print(("  properties: %d checks passed"):format(checks))
