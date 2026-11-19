-- Forever names a random suffix two ways, and neither is the old suffix
-- field of a link (a player's report, 2026-11-19: crafted Wild Leather
-- pieces were priced as plain "Wild Leather Vest", and the Prices tab
-- listed each suffix's price with no name).
--
--   * A link carries it as a bonus ID: item:8211::::::::40:1490:::1:12731.
--     The old suffix field is empty.
--   * The auction house's item key carries another number (itemSuffix,
--     14327 and the like), and that is what the prices are kept under.
--
-- What must hold:
--   1. A link seen beside its key (a search, a bag copy) teaches the two
--      numbers go together, and the copy is then priced by its suffix.
--   2. A suffix whose name the auction house gave is matched to a link by
--      that name, with nothing else learned yet.
--   3. Each suffix on the Prices tab has its name.
--   4. A plain copy, and gear whose link has no bonus, has no suffix.
--   5. A suffix that cannot be placed yet still counts as a suffix copy,
--      but is never saved as a price of its own.

local GLOBALS = { "time", "GetTime", "C_Item", "GetItemInfo", "GetLocale", "C_AuctionHouse" }
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
GetLocale = function() return "enUS" end

local VEST, MONKEY_KEY, EAGLE_KEY, BEAR_KEY = 8211, 14327, 14304, 14310
local MONKEY_BONUS, MONKEY_BONUS_2, EAGLE_BONUS, BEAR_BONUS = 12731, 12745, 12722, 12760
local BONUS_NAME = {
    [MONKEY_BONUS] = " of the Monkey", [MONKEY_BONUS_2] = " of the Monkey",
    [EAGLE_BONUS] = " of the Eagle", [BEAR_BONUS] = " of the Bear",
}
local KEY_NAME = { [MONKEY_KEY] = " of the Monkey", [EAGLE_KEY] = " of the Eagle", [BEAR_KEY] = " of the Bear" }
local BASE = { [VEST] = "Wild Leather Vest", [8214] = "Wild Leather Helmet" }

local function Link(itemID, bonus)
    local tail = bonus and BONUS_NAME[bonus] or ""
    return ("|cff1eff00|Hitem:%d::::::::40:1490:::%s::::::|h[%s%s]|h|r"):format(
        itemID, bonus and ("1:" .. bonus) or "", BASE[itemID], tail)
end

-- The game's item names: by ID the plain name, by a link with a bonus the
-- suffixed one. The old suffix field names nothing here.
local namesLoaded = true
C_Item = {
    GetItemInfo = function(item)
        if not namesLoaded then return nil end
        if type(item) == "number" then return BASE[item] end
        local itemID = tonumber(item:match("item:(%d+)"))
        local bonus = tonumber(item:match("item:%d+::::::::[%d]*:[%d]*:::1:(%d+)"))
        return BASE[itemID] and (BASE[itemID] .. (bonus and BONUS_NAME[bonus] or "")) or nil
    end,
}
GetItemInfo = C_Item.GetItemInfo

local keyNamesLoaded = false
C_AuctionHouse = {
    GetItemKeyInfo = function(key)
        if not keyNamesLoaded then return nil end
        return { itemID = key.itemID, itemName = BASE[key.itemID] .. (KEY_NAME[key.itemSuffix] or "") }
    end,
}

local ns = {}
ns.COLORS = setmetatable({}, { __index = function() return "ffffffff" end })
ns.NewModule = function(name) local m = {}; ns[name] = m; return m end
ns.RegisterCommand = function() end
ns.RegisterEvent = function() return true end
ns.Print, ns.PrintRaw, ns.Debug, ns.Warn = function() end, function() end, function() end, function() end

assert(loadfile(lfs_cwd .. "/Core/Util.lua"))("Blackthornes_TS", ns)
local Util = ns.Util

local priceTable = {}
ns.Config = {
    Get = function() return nil end,
    GetPriceTable = function() return priceTable end,
    GetRealmKey = function() return "TestRealm" end,
}
ns.db = {}
assert(loadfile(lfs_cwd .. "/Data/Prices.lua"))("Blackthornes_TS", ns)
local Prices = ns.Prices
Prices.GetMine = function() return nil end

-- A scan saw the vest's suffixes, as the auction house keys them.
Prices:Record(VEST, 30000, 25000, 6, now, 25000, nil)
Prices:RecordSuffix(VEST, MONKEY_KEY, 90000, 85000, 85000, 2, now)
Prices:RecordSuffix(VEST, EAGLE_KEY, 12000, 11000, 11000, 4, now)

local MONKEY, EAGLE, BEAR, PLAIN = Link(VEST, MONKEY_BONUS), Link(VEST, EAGLE_BONUS), Link(VEST, BEAR_BONUS), Link(VEST)

print("\nreading a Forever link")

check("the bonus is read", Util.LinkBonuses(MONKEY)[1] == MONKEY_BONUS and #Util.LinkBonuses(MONKEY) == 1)
check("a plain copy has none", #Util.LinkBonuses(PLAIN) == 0)
check("numbers after the bonuses are not bonuses",
    #Util.LinkBonuses("|Hitem:15222::::::::14:1484::1:1:12719:1:28:5240:::::|h[x]|h") == 1)
check("gear with no bonus has none", #Util.LinkBonuses("|Hitem:10413::::::::14:1484::1::1:28:5254:::::|h[x]|h") == 0)
check("the old suffix field still reads", Util.LinkSuffix("|Hitem:1076::::::612:1:60|h[Lead Band of the Wolf]|h") == 612)
check("a plain copy has no suffix", Util.LinkSuffix(PLAIN) == nil)

print("\nbefore anything is learned")

local suffix, sure = Util.LinkSuffix(MONKEY)
check("the copy still counts as a suffix copy", suffix ~= nil and sure == false)
check("but is not placed", suffix ~= MONKEY_KEY)
check("and is priced as the item", Prices:GetLinkValue(MONKEY, "market") == 30000)

print("\nthe bag copy beside its auction house key")

Prices:LearnSuffix(MONKEY, MONKEY_KEY)
suffix, sure = Util.LinkSuffix(MONKEY)
check("the crafted vest is of the Monkey", suffix == MONKEY_KEY and sure == true)
local value, own = Prices:GetLinkValue(MONKEY, "market")
check("and worth Monkey's price", value == 90000 and own == true)
check("Monkey's rival, not the item's", Prices:GetLinkValue(MONKEY, "rival") == 85000)
check("a plain vest keeps the item's price", Prices:GetLinkValue(PLAIN, "market") == 30000)
check("it is saved for next time", ns.db.suffixWords.bonuses[MONKEY_BONUS] == MONKEY_KEY)

print("\nmatched by name")

check("another Monkey bonus is placed by its name", Util.LinkSuffix(Link(VEST, MONKEY_BONUS_2)) == MONKEY_KEY)
check("and on another item too", Util.LinkSuffix(Link(8214, MONKEY_BONUS)) == MONKEY_KEY)
check("Eagle's name is not known yet", select(2, Util.LinkSuffix(EAGLE)) == false)

keyNamesLoaded = true
Prices:LearnKeyName({ itemID = VEST, itemSuffix = EAGLE_KEY, itemLevel = 40 })
suffix, sure = Util.LinkSuffix(EAGLE)
check("a browse row's name places the Eagle copy", suffix == EAGLE_KEY and sure == true)
check("and it is worth Eagle's price", Prices:GetLinkValue(EAGLE, "market") == 12000)
check("the match is saved by its bonus", ns.db.suffixWords.bonuses[EAGLE_BONUS] == EAGLE_KEY)
keyNamesLoaded = false

print("\nnames on the Prices tab")

local rows = Prices:SuffixRows(VEST)
check("both suffixes listed", #rows == 2)
check("Monkey has its name", rows[1] and rows[1].name == "Wild Leather Vest of the Monkey")
check("Eagle has its name", rows[2] and rows[2].name == "Wild Leather Vest of the Eagle")

-- A suffix only the auction house can name, asked for when the row is drawn.
Prices:RecordSuffix(VEST, BEAR_KEY, 20000, 20000, 20000, 1, now)
check("no name while the game has none", Prices.SuffixName(VEST, BEAR_KEY) == nil)
keyNamesLoaded = true
check("named once the game gives it", Prices.SuffixName(VEST, BEAR_KEY) == "Wild Leather Vest of the Bear")
keyNamesLoaded = false
check("and kept after", Prices.SuffixName(VEST, BEAR_KEY) == "Wild Leather Vest of the Bear")
check("the Bear copy is placed by that name", Util.LinkSuffix(BEAR) == BEAR_KEY)

print("\nnames the game has not loaded")

ns.db.suffixWords = nil
namesLoaded = false
check("nothing raises", pcall(Util.LinkSuffix, MONKEY))
check("a link whose item has no name yet is left alone", Util.LinkSuffix(MONKEY) == nil)
check("no name is made up", Prices.SuffixName(VEST, MONKEY_KEY) == nil)
namesLoaded = true

print("\na scan never saves a suffix it cannot place")

ns.Scanner, ns.Inventory = nil, nil
ns.Compat = { Get = function() return { auction = {} } end }
local scannerOk = pcall(function()
    assert(loadfile(lfs_cwd .. "/Data/Scanner.lua"))("Blackthornes_TS", ns)
end)
check("the scanner loads", scannerOk and ns.Scanner ~= nil)
C_AuctionHouse.GetReplicateItemLink = function(index) return index == 1 and MONKEY or EAGLE end
Util.HasFunction = function() return true end
check("a copy not placed yet is passed over", ns.Scanner.ReplicateSuffix(1) == nil)
Prices:LearnSuffix(EAGLE, EAGLE_KEY)
check("a placed one is read", ns.Scanner.ReplicateSuffix(2) == EAGLE_KEY)

for _, key in ipairs(GLOBALS) do _G[key] = saved[key] end

print(("\n%d passed, %d failed"):format(passed, failed))
if failed > 0 then error(("%d check(s) failed"):format(failed)) end
