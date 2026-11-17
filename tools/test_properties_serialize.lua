-- Things about sharing (Core/Serialize.lua) that must hold for any data,
-- tried with many random tables. The same test in Farmer and Tradeskills,
-- whose Serialize.lua is the same file.
--
-- The seed is fixed so a failure comes back the same each run; the failing
-- data is printed.
--
-- What must hold:
--   1. Whatever is sent comes back the same: Decode(Encode(x)) equals x, for
--      strings holding any byte, whole and broken numbers, true and false,
--      and tables inside tables.
--   2. The canonical text reads back the same too.
--   3. The same data gives the same canonical text, whatever order its keys
--      were added in (what Comm's hash leans on).
--   4. Broken text never raises: Decode says no, it does not crash.

local ns = {}
ns.NewModule = function() return {} end
local chunk = assert(loadfile(lfs_cwd .. "/Core/Serialize.lua"))
chunk("Blackthornes_Properties", ns)
local S = ns.Serialize
assert(S and S.Encode and S.Decode, "Serialize loads")

math.randomseed(20261117)
local TRIES = 400
local checks = 0

local function RandomString()
    local n = math.random(0, 24)
    local out = {}
    for i = 1, n do out[i] = string.char(math.random(0, 255)) end
    return table.concat(out)
end

local function RandomNumber()
    local pick = math.random(1, 4)
    if pick == 1 then return math.random(-1000000, 1000000) end
    if pick == 2 then return (math.random() - 0.5) * 10 ^ math.random(-6, 9) end
    if pick == 3 then return math.random(0, 1) end
    return math.floor((math.random() - 0.5) * 2 ^ 40)
end

local RandomValue
local function RandomTable(depth)
    local t = {}
    for i = 1, math.random(0, 4) do t[i] = RandomValue(depth + 1) end
    for _ = 1, math.random(0, 4) do
        local key = math.random(1, 3) == 1 and RandomNumber() or RandomString()
        if key ~= "" or math.random(1, 2) == 1 then t[key] = RandomValue(depth + 1) end
    end
    return t
end

RandomValue = function(depth)
    local pick = math.random(1, depth >= 3 and 3 or 4)
    if pick == 1 then return RandomString() end
    if pick == 2 then return RandomNumber() end
    if pick == 3 then return math.random(1, 2) == 1 end
    return RandomTable(depth)
end

local function Show(v, depth)
    depth = depth or 0
    if type(v) == "string" then return ("%q"):format(v) end
    if type(v) ~= "table" then return tostring(v) end
    if depth > 3 then return "{...}" end
    local parts = {}
    for k, x in pairs(v) do parts[#parts + 1] = "[" .. Show(k, 4) .. "]=" .. Show(x, depth + 1) end
    return "{" .. table.concat(parts, ",") .. "}"
end

local function Same(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) == "number" then
        return a == b or math.abs(a - b) <= 1e-12 * math.max(math.abs(a), math.abs(b))
    end
    if type(a) ~= "table" then return a == b end
    for k, v in pairs(a) do if not Same(v, b[k]) then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
end

local function Copy(t, reverse)
    if type(t) ~= "table" then return t end
    local keys = {}
    for k in pairs(t) do keys[#keys + 1] = k end
    local out = {}
    local from, to, step = 1, #keys, 1
    if reverse then from, to, step = #keys, 1, -1 end
    for i = from, to, step do out[keys[i]] = Copy(t[keys[i]], not reverse) end
    return out
end

for i = 1, TRIES do
    local value = RandomTable(0)
    local text = S.Encode(value)
    local ok, back = S.Decode(text)
    assert(ok and Same(value, back), ("try %d: sent %s, came back %s"):format(i, Show(value), Show(back)))

    local canon = S.EncodeCanonical(value)
    local ok2, back2 = S.Decode(canon)
    assert(ok2 and Same(value, back2), ("try %d: canonical text reads back wrong for %s"):format(i, Show(value)))

    assert(S.EncodeCanonical(Copy(value, true)) == canon,
        ("try %d: the same data in another key order gives other text: %s"):format(i, Show(value)))

    -- 4. Cut or bent text: Decode answers, never raises.
    local cut = text:sub(1, math.random(0, #text))
    local bent = cut .. RandomString()
    for _, broken in ipairs({ cut, bent }) do
        local fine, why = pcall(S.Decode, broken)
        assert(fine, ("try %d: Decode raised on broken text: %s"):format(i, tostring(why)))
    end
    checks = checks + 4
end

print(("  properties_serialize: %d checks passed"):format(checks))
