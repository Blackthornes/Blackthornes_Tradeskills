-- Round-trip the serializer against the real saved database.
local ns = { }
local function NewModule() return {} end
ns.NewModule = NewModule

local chunk = loadfile("Core/Serialize.lua")
chunk("Blackthornes_TS", ns)

local S = ns.Serialize

local function DeepEqual(a, b, path)
    if type(a) ~= type(b) then return false, path .. ": type " .. type(a) .. " vs " .. type(b) end
    if type(a) ~= "table" then
        if a ~= b then return false, path .. ": " .. tostring(a) .. " vs " .. tostring(b) end
        return true
    end
    for k, v in pairs(a) do
        local ok, why = DeepEqual(v, b[k], path .. "." .. tostring(k))
        if not ok then return false, why end
    end
    for k in pairs(b) do
        if a[k] == nil then return false, path .. "." .. tostring(k) .. ": extra key" end
    end
    return true
end

local cases = {
    { name = "scalars", value = { 1, -2, 0.05, "text", true, false } },
    { name = "empty table", value = {} },
    { name = "nested", value = { a = { b = { c = { 1, 2, 3 } } } } },
    { name = "sparse numeric keys", value = { [2589] = 17, [286176] = 1 } },
    { name = "string with delimiters", value = { ["a;b:c~t"] = "s5:fake" } },
    { name = "float precision", value = { cut = 0.05, ema = 1/3, third = 2/3 } },
    { name = "non-finite dropped", value = { ok = 1 } },
    { name = "negative and big", value = { -123456789, 2147483647 } },

    -- The price that broke a whole save in game on 2026-09-21: 9,999,990,200
    -- copper, read off a browse row, past the signed 32-bit range the client's
    -- %d conversion can take.
    { name = "past 32-bit copper", value = { 9999990200, -9999990200 } },
    { name = "whole numbers to 2^53", value = { 2 ^ 31, 2 ^ 31 - 1, 2 ^ 53 - 1, -(2 ^ 53 - 1) } },
}

local failures = 0
for _, case in ipairs(cases) do
    local encoded = S.Encode(case.value)
    local ok, decoded = S.Decode(encoded)
    local same, why = false, "decode failed: " .. tostring(decoded)
    if ok then same, why = DeepEqual(case.value, decoded, "") end
    print(string.format("  %-26s %s", case.name, same and "ok" or ("FAIL " .. tostring(why))))
    if not same then failures = failures + 1 end
end

-- Realistic scale: the saved file was ~215KB with 984 priced items, so build
-- one the same shape and check both the size and the time it costs at logout.
local db = { prices = { ["Classic Beta PvE 2-Horde"] = {} }, characters = {}, queue = {} }
local realm = db.prices["Classic Beta PvE 2-Horde"]

for i = 1, 3000 do
    realm[2000 + i] = {
        market = 1234 + i, min = 1200 + i, rivalMin = 1198 + i, ownMin = 1400 + i,
        quantity = i % 97, lastSeen = 1789770722 + i, scanCount = i % 13,
        qtyHistory = { i, i + 1, i + 2, i + 3, i + 4 },
    }
end

local character = { name = "Blackthornes Wither", gold = 269, recipes = {}, inventory = {} }
for i = 1, 300 do
    character.recipes[9000 + i] = {
        name = "Handstitched Leather Cloak " .. i, outputItemID = 7276 + i,
        skillLineID = 2945, quantityMin = 1, quantityMax = 1,
        reagents = { { itemID = 2318, quantity = 2 }, { itemID = 2320, quantity = 1 } },
    }
end
db.characters["Blackthornes Wither-Classic Beta PvE 2"] = character
db.settings = { auctionCut = 0.05, undercutCopper = 1, valueOwnedMaterials = true }

local t0 = os.clock()
local encoded = S.Encode(db)
local encodeMs = (os.clock() - t0) * 1000

local t1 = os.clock()
local ok, decoded = S.Decode(encoded)
local decodeMs = (os.clock() - t1) * 1000

local same, why = false, tostring(decoded)
if ok then same, why = DeepEqual(db, decoded, "db") end

print(string.format("\n  3000 prices + 300 recipes: %d bytes", #encoded))
print(string.format("  encode %.0fms, decode %.0fms, round-trip %s",
    encodeMs, decodeMs, same and "ok" or ("FAIL " .. tostring(why))))
print(string.format("  chunks at 60000 bytes: %d  (8 x 64KB proven to persist)",
    math.ceil(#encoded / 60000)))
if not same then failures = failures + 1 end


--------------------------------------------------------------------------------
-- The client's own %d limit
--------------------------------------------------------------------------------
--
-- This test exists because the real failure cannot happen on the Lua this
-- runner uses: on 64-bit Linux a %d argument is a long and 9,999,990,200 fits,
-- so the encoder that broke in game passes here unchanged. Standing the check
-- up means breaking what it checks -- string.format is replaced with one that
-- refuses a %d past the signed 32-bit range the way the client does, and the
-- encoder is then asked to do the thing that failed.
--
-- Confirmed to fail against the encoder as it was before this fix.

local realFormat = string.format

local function StrictFormat(fmt, ...)
    if select("#", ...) == 1 and fmt:find("%%d") then
        local value = ...
        if type(value) == "number" and math.abs(value) >= 2 ^ 31 then
            error("integer overflow attempting to store " .. realFormat("%.0f", value), 2)
        end
    end
    return realFormat(fmt, ...)
end

local strictCase = {
    prices = {
        [2589] = { market = 12, min = 9 },
        [3371] = { market = 9999990200, min = 9999990200 },
    },
    sold = { 4294967296, 1.5, -(2 ^ 40) },
}

string.format = StrictFormat
getmetatable("").__index.format = StrictFormat

local strictOk, strictEncoded = pcall(S.Encode, strictCase)

string.format = realFormat
getmetatable("").__index.format = realFormat

if not strictOk then
    print("\n  client-strict %d:            FAIL encode threw: " .. tostring(strictEncoded))
    failures = failures + 1
else
    local decodeOk, decoded = S.Decode(strictEncoded)
    local same, why = false, tostring(decoded)
    if decodeOk then same, why = DeepEqual(strictCase, decoded, "strict") end
    print("\n  client-strict %d:            " .. (same and "ok" or ("FAIL " .. tostring(why))))
    if not same then failures = failures + 1 end
end

-- A number no format can write must cost only itself, never the whole save.
local resilient = { keep = 41, huge = math.huge, nan = 0 / 0, alsoKeep = "yes" }
local resilientOk, resilientText = pcall(S.Encode, resilient)
local resilientDecoded
if resilientOk then
    local decodeOk, value = S.Decode(resilientText)
    resilientDecoded = decodeOk and value or nil
end
local survived = type(resilientDecoded) == "table"
    and resilientDecoded.keep == 41
    and resilientDecoded.alsoKeep == "yes"
print("  one bad field keeps the rest: " .. (survived and "ok" or "FAIL"))
if not survived then failures = failures + 1 end

-- A message from anyone can carry a bad length. A negative one used to step
-- back through the text, and the table around it never ended: the game froze.
local function Refused(text)
    local ok = S.Decode(text)
    return ok == false
end
for _, bad in ipairs({ "ts-4:", "ts-1:x", "ts99:ab", "ts1.5:ab", "tn1;" }) do
    local refused = Refused(bad)
    print(("  %-10s refused: %s"):format(bad, refused and "ok" or "FAIL"))
    if not refused then failures = failures + 1 end
end

print(failures == 0 and "\nall serializer tests passed" or ("\n" .. failures .. " failure(s)"))

-- Reported and nothing more, until now: this suite printed FAIL and still let
-- the run pass, so the encoder bug above would have reached `testing` through a
-- green CI. A suite fails by raising; that is what the runner counts.
if failures > 0 then
    error(failures .. " serializer failure(s)")
end
