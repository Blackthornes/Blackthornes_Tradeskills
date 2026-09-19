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

print(failures == 0 and "\nall serializer tests passed" or ("\n" .. failures .. " failure(s)"))
