-- The Sales tab's Bought view, outside WoW.
--
-- A player asked for a list of what they bought. Each buy is now written
-- with the character who bought it (Logic/BuyLog.lua); older buys come from
-- MethodProfit's own record, shown with no character, and are never counted
-- twice.

local now = 1000000
local savedTime = time
time = function() return now end

local function Words()
    local L = setmetatable({}, { __index = function(_, k) return k end })
    L.Format = function(key, ...) return string.format(L[key], ...) end
    return L
end

local characterKey = "Player-1"
local ns = {
    L = Words(),
    db = {},
    NewModule = function(name) local m = {}; return m end,
    RegisterEvent = function() end,
}
ns.Config = {
    GetRealmKey = function() return "Realm-Alliance" end,
    GetCharacterKey = function() return characterKey end,
}
ns.Util = {
    FormatAgeAgo = function(seconds)
        if seconds < 3600 then return math.floor(seconds / 60) .. "m ago" end
        if seconds < 86400 then return math.floor(seconds / 3600) .. "h ago" end
        return math.floor(seconds / 86400) .. "d ago"
    end,
    CharacterName = function(key)
        local names = { ["Player-1"] = "Ana Stormwind", ["Player-2"] = "Bob Wither" }
        return names[key] or ""
    end,
    GetItemLabel = function(id)
        return "|cff1eff00|Hitem:" .. id .. "::::|h[Item " .. id .. "]|h|r"
    end,
    Uncolored = function(text)
        return (text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
    end,
}
local oldBuys = {}
ns.MethodProfit = { GetLog = function() return { buys = oldBuys } end }

local function Load(path, name)
    local chunk = assert(loadfile(path))
    local module
    ns.NewModule = function(n) module = {}; ns[n] = module; return module end
    chunk("Blackthornes_TS", ns)
    return module
end

local BuyLog = Load("Logic/BuyLog.lua")
local SalesBought = Load("UI/SalesBought.lua")

local failures = 0
local function check(cond, what)
    if not cond then
        failures = failures + 1
        print("FAIL: " .. what)
    end
end

-- A buy from before the log, then two written with their character.
oldBuys[2589] = { { n = 20, paid = 4000, at = now - 5 * 86400 } }
BuyLog:Note(2589, 10, 2500, now - 3600)
characterKey = "Player-2"
BuyLog:Note(2592, 4, 4000, now - 30 * 3600)
-- The same buy MethodProfit also kept after the log began: not counted again.
oldBuys[2592] = { { n = 4, paid = 4000, at = now - 30 * 3600 } }

local log = BuyLog:Get()
check(#log.buys == 2, "two buys written")
check(log.buys[1].who == "Player-1", "first buy keeps its character")
check(log.buys[2].who == "Player-2", "second buy keeps its character")
check(log.since == now - 30 * 3600, "the log begins at its oldest buy")

-- Bad buys are skipped.
BuyLog:Note(nil, 1, 1)
BuyLog:Note(2589, 0, 100)
BuyLog:Note(2589, 1, 0)
check(#BuyLog:Get().buys == 2, "bad buys are not written")

local rows = BuyLog:Rows()
check(#rows == 3, "every buy once: two logged and one from before, got " .. #rows)
check(rows[1].at == now - 3600, "newest first")
check(rows[3].who == nil, "an older buy has no character")

local mine = BuyLog:Rows(nil, nil, "Player-1")
check(#mine == 1 and mine[1].id == 2589, "the character filter keeps that character's buys")
check(#BuyLog:Rows(nil, nil, "all") == 3, "all characters shows everything")

local week = BuyLog:Rows(now - 2 * 86400, now + 1)
check(#week == 2, "the period leaves out older buys")

local totals = BuyLog.Totals(rows)
check(totals.spent == 10500, "spent adds every buy")
check(totals.items == 34, "items bought adds every count")
check(totals.buys == 3, "three buys")
check(totals.top == 2589 and totals.topCount == 30, "most bought is the item bought most")

local item = BuyLog.ItemTotals(rows, 2589)
check(item.n == 30 and item.buys == 2, "item totals count every buy of it")
check(math.abs(item.each - 6500 / 30) < 0.001, "average paid is copper for one")

local chars = BuyLog:Characters()
check(#chars == 2, "two characters have buys")

-- Words.
check(SalesBought.WhenText(now - 3600, now) == "1h ago", "an hour ago")
check(SalesBought.WhenText(now - 30 * 3600, now) == "yesterday", "yesterday")
check(SalesBought.WhenText(now - 3 * 86400, now) == "3d ago", "days ago")
check(SalesBought.WhoText("Player-2") == "Bob Wither", "the whole name")
check(SalesBought.WhoText(nil) == "-", "a dash for older buys")
check(SalesBought.WhoText("Player-9") == "-", "a dash for a character not known")
check(SalesBought.NameOf(2589) == "Item 2589", "the plain name, no link")
check(SalesBought.Matches({ id = 2589 }, "item 25"), "search by name")
check(SalesBought.Matches({ id = 2589 }, "2589"), "search by item ID")
check(not SalesBought.Matches({ id = 2589 }, "hitem"), "search never matches the link's insides")

-- The log keeps at most MAX buys, the oldest going first.
local max = BuyLog.MAX
BuyLog.MAX = 3
for i = 1, 5 do BuyLog:Note(100 + i, 1, 10, now + i) end
local kept = BuyLog:Get().buys
check(#kept == 3 and kept[1].id == 103, "the oldest buys go first")
BuyLog.MAX = max

time = savedTime
if failures > 0 then
    print(failures .. " failure(s)")
    error("test_boughtlist failed")
end
print("test_boughtlist: all passed")
