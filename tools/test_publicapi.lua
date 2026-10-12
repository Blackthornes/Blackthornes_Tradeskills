-- The public price API for other authors' addons (2026-10-12).
--
-- What must hold:
--   1. The global is there with version 1.
--   2. GetPrice answers Prices:GetValue's market value, by item ID or link.
--   3. GetPriceAge answers Prices:GetAge.
--   4. Nothing it is given makes it raise; a bad item or an error is nil.

local saved = rawget(_G, "BlackthornesTS_API")

local ns = {}
local asked
ns.Prices = {
    GetValue = function(_, id, which) asked = which; if id == 2589 then return 1234.4 end end,
    GetAge = function(_, id) if id == 2589 then return 90 end end,
}

assert(loadfile(lfs_cwd .. "/Logic/PublicAPI.lua"))("Blackthornes_TS", ns)
local API = BlackthornesTS_API

local checks = 0
local function check(label, condition)
    checks = checks + 1
    if not condition then error(("FAILED: %s"):format(label), 2) end
    print(("  ok  %s"):format(label))
end

print("\npublic price API")

check("the global is there", type(API) == "table" and API == ns.PublicAPI)
check("version 1", API.version == 1)
check("price by item ID", API.GetPrice(2589) == 1234)
check("asks for the market value", asked == "market")
check("price by item link", API.GetPrice("|cffffffff|Hitem:2589::::::::|h[Linen Cloth]|h|r") == 1234)
check("price by an ID in a string", API.GetPrice("2589") == 1234)
check("no price is nil", API.GetPrice(2590) == nil)
check("age by item ID", API.GetPriceAge(2589) == 90)
check("no age is nil", API.GetPriceAge(2590) == nil)

for _, bad in ipairs({ { "nil" }, { -1 }, { 1.5 }, { "Linen" }, { {} }, { true }, { 1e12 } }) do
    local item = bad[1]
    if item == "nil" then item = nil end
    local ok1, a = pcall(API.GetPrice, item)
    local ok2, b = pcall(API.GetPriceAge, item)
    check("a bad item is nil, not an error: " .. tostring(bad[1]), ok1 and ok2 and a == nil and b == nil)
end

ns.Prices.GetValue = function() error("boom") end
ns.Prices.GetAge = function() error("boom") end
local ok1, a = pcall(API.GetPrice, 2589)
local ok2, b = pcall(API.GetPriceAge, 2589)
check("an error inside is nil, not an error", ok1 and ok2 and a == nil and b == nil)

ns.Prices = nil
check("with prices not loaded yet, nil", API.GetPrice(2589) == nil)

_G.BlackthornesTS_API = saved
print(("\n%d check(s) passed\n"):format(checks))
