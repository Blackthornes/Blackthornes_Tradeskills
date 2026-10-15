-- Random suffixes keep a price of their own (asked 2026-10-15): "Lead Band
-- of the Monkey" can sell for far more than "Lead Band of the Spirit", and
-- the item's one price mixed them together.
--
-- What must hold:
--   1. A suffix's reading sits beside the item's price, which is unchanged.
--   2. A copy's link is priced by its suffix when one is kept and recent,
--      else by the item; a price the player set still wins.
--   3. At most SUFFIX_MOST suffixes are kept, the oldest going first.
--   4. Browse rows for one suffix keep that suffix's cheapest.
--   5. Only green or better weapons and armour are asked for their link.

local GLOBALS = { "time", "GetTime", "C_Item", "GetItemInfoInstant" }
local saved = {}
for _, key in ipairs(GLOBALS) do saved[key] = _G[key] end

local passed, failed = 0, 0
local function check(label, condition)
    if condition then passed = passed + 1 else failed = failed + 1 end
    print(("  %s  %s"):format(condition and "ok" or "WRONG", label))
end

local now = 1000000
time = function() return now end
GetTime = function() return now end

local ns = {}
ns.COLORS = setmetatable({}, { __index = function() return "ffffffff" end })
ns.NewModule = function(name) local m = {}; ns[name] = m; return m end
ns.RegisterCommand = function() end
ns.RegisterEvent = function() return true end
ns.Print, ns.PrintRaw, ns.Debug, ns.Warn = function() end, function() end, function() end, function() end

assert(loadfile(lfs_cwd .. "/Core/Util.lua"))("Blackthornes_TS", ns)

local priceTable, mine = {}, {}
ns.Config = {
    Get = function() return nil end,
    GetPriceTable = function() return priceTable end,
    GetRealmKey = function() return "TestRealm" end,
}
ns.db = {}
assert(loadfile(lfs_cwd .. "/Data/Prices.lua"))("Blackthornes_TS", ns)
local Prices = ns.Prices
Prices.GetMine = function(_, itemID) local m = mine[itemID]; if m then return m.price, m.mode end end

local BAND, MONKEY, SPIRIT = 1076, 612, 650
local MONKEY_LINK = "|cff1eff00|Hitem:1076::::::612:1:60|h[Lead Band of the Monkey]|h|r"
local SPIRIT_LINK = "|cff1eff00|Hitem:1076::::::650:1:60|h[Lead Band of the Spirit]|h|r"
local OTHER_LINK = "|cff1eff00|Hitem:1076::::::700:1:60|h[Lead Band of the Owl]|h|r"
local PLAIN_LINK = "|cff1eff00|Hitem:1076::::::::60|h[Lead Band]|h|r"

print("\na suffix's price beside the item's")

check("nothing kept without the item's own price", Prices:RecordSuffix(BAND, MONKEY, 9000, 9000, 9000, 1, now) == nil)
Prices:Record(BAND, 3000, 2500, 6, now, 2500, nil)
check("kept once the item has one", Prices:RecordSuffix(BAND, MONKEY, 9000, 8500, 8500, 2, now) ~= nil)
Prices:RecordSuffix(BAND, SPIRIT, 1200, 1100, 1100, 4, now)
check("the item's price is unchanged", Prices:GetValue(BAND, "market") == 3000)
check("Monkey's own price", Prices:GetSuffixValue(BAND, MONKEY, "market") == 9000)
check("Monkey's cheapest", Prices:GetSuffixValue(BAND, MONKEY, "min") == 8500)
check("Spirit's rival", Prices:GetSuffixValue(BAND, SPIRIT, "rival") == 1100)
check("a suffix never seen has none", Prices:GetSuffixValue(BAND, 700, "market") == nil)
check("no suffix is none", Prices:GetSuffixValue(BAND, 0, "market") == nil)
check("a junk price is refused", Prices:RecordSuffix(BAND, 701, 2 ^ 40, nil, nil, 1, now) == nil)
check("no price is refused", Prices:RecordSuffix(BAND, 701, nil, nil, nil, 1, now) == nil)

Prices:RecordSuffix(BAND, MONKEY, 10000, 10000, 10000, 1, now)
check("a second reading is smoothed", Prices:GetSuffixValue(BAND, MONKEY, "market") == 9300)

print("\npricing a copy by its link")

local value, own = Prices:GetLinkValue(MONKEY_LINK, "market")
check("Monkey is worth Monkey's price", value == 9300 and own == true)
value, own = Prices:GetLinkValue(SPIRIT_LINK, "market")
check("Spirit is worth Spirit's price", value == 1200 and own == true)
value, own = Prices:GetLinkValue(OTHER_LINK, "market")
check("a suffix with no price takes the item's", value == 3000 and own == false)
check("a plain copy takes the item's", Prices:GetLinkValue(PLAIN_LINK, "market") == 3000)
check("an item ID takes the item's", Prices:GetLinkValue(BAND, "market") == 3000)
check("rival by suffix", Prices:GetLinkValue(SPIRIT_LINK, "rival") == 1100)
check("nothing at all is nil", Prices:GetLinkValue(nil, "market") == nil)

mine[BAND] = { price = 5000, mode = "floor" }
check("the player's floor lifts a cheap suffix", Prices:GetLinkValue(SPIRIT_LINK, "market") == 5000)
check("and leaves a dear one", Prices:GetLinkValue(MONKEY_LINK, "market") == 9300)
mine[BAND] = { price = 4000, mode = "use" }
check("the player's own price wins", Prices:GetLinkValue(MONKEY_LINK, "market") == 4000)
mine[BAND] = nil

now = now + Prices.SUFFIX_KEEP + 1
check("an old suffix price is not used", Prices:GetSuffixValue(BAND, MONKEY, "market") == nil)
check("and the item's stands in", Prices:GetLinkValue(MONKEY_LINK, "market") == 3000)

print("\nkeeping at most SUFFIX_MOST")

for i = 1, Prices.SUFFIX_MOST + 5 do
    now = now + 1
    Prices:RecordSuffix(BAND, 1000 + i, 500 + i, nil, nil, 1, now)
end
local count = 0
for _ in pairs(priceTable[BAND].suffixes) do count = count + 1 end
check("no more than the most", count == Prices.SUFFIX_MOST)
check("the oldest went first", priceTable[BAND].suffixes[MONKEY] == nil and priceTable[BAND].suffixes[1001] == nil)
check("the newest stayed", priceTable[BAND].suffixes[1000 + Prices.SUFFIX_MOST + 5] ~= nil)

print("\nlistings by suffix from a scan")

priceTable[BAND].suffixes = nil
local kept = Prices:CommitSuffixes(BAND, {
    [MONKEY] = { { unitPrice = 8000, quantity = 1 }, { unitPrice = 9000, quantity = 1 } },
    [SPIRIT] = { { unitPrice = 1500, quantity = 1, isOwn = true } },
}, now)
check("both suffixes kept", kept == 2)
check("Monkey's cheapest from its listings", Prices:GetSuffixValue(BAND, MONKEY, "min") == 8000)
check("Spirit is all yours: no rival", Prices:GetSuffixValue(BAND, SPIRIT, "rival") == nil)

print("\nscrubbing a junk suffix price")

priceTable[BAND].suffixes[999] = { market = 2 ^ 40, seen = now }
Prices:Scrub()
check("the junk one went", priceTable[BAND].suffixes[999] == nil)
check("the rest stayed", priceTable[BAND].suffixes[MONKEY] ~= nil)

print("\nbrowse rows and which rows are asked for a link")

ns.Scanner = nil
ns.Inventory = nil
ns.Compat = { Get = function() return { auction = {} } end }
local scannerOk = pcall(function()
    assert(loadfile(lfs_cwd .. "/Data/Scanner.lua"))("Blackthornes_TS", ns)
end)
check("the scanner loads", scannerOk and ns.Scanner ~= nil)
local Scanner = ns.Scanner

local recorded = {}
local realRecord = Prices.RecordSuffix
Prices.RecordSuffix = function(_, itemID, suffix, market, min, rival, quantity)
    recorded[suffix] = { itemID = itemID, market = market, rival = rival, quantity = quantity }
end
Scanner.RecordRowSuffixes({ itemID = BAND, suffixes = {
    [MONKEY] = { price = 8000, quantity = 2, rival = 8000 },
    [SPIRIT] = { price = 1000, quantity = 5 },
} }, now)
check("each suffix row recorded", recorded[MONKEY] and recorded[MONKEY].market == 8000 and recorded[SPIRIT].quantity == 5)
check("a row with no suffixes records nothing", pcall(Scanner.RecordRowSuffixes, { itemID = BAND }, now))
Prices.RecordSuffix = realRecord

local CLASS = { [BAND] = 4, [2589] = 7, [25] = 2 }
C_Item = { GetItemInfoInstant = function(id) return id, nil, nil, nil, nil, CLASS[id] end }
local memo = {}
check("green armour is asked", Scanner.MayHaveSuffix(BAND, 2, memo) == true)
check("a green weapon is asked", Scanner.MayHaveSuffix(25, 2, memo) == true)
check("white gear is not", Scanner.MayHaveSuffix(BAND, 1, {}) == false)
check("cloth is not", Scanner.MayHaveSuffix(2589, 3, memo) == false)
C_Item = { GetItemInfoInstant = function() error("not now") end }
check("the answer is kept per item", Scanner.MayHaveSuffix(BAND, 2, memo) == true)
check("an error asks for nothing", Scanner.MayHaveSuffix(26, 2, {}) == false)

for _, key in ipairs(GLOBALS) do _G[key] = saved[key] end

print(("\n%d passed, %d failed"):format(passed, failed))
if failed > 0 then error(("%d check(s) failed"):format(failed)) end
