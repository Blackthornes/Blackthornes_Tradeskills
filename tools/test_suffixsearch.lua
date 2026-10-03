-- A random suffix item is priced by its own suffix (kronosbest's report,
-- 2026-10-02): "Lead Band of the Wolf" in the bags, Wolf listings at 40s,
-- and the Post tab asked 80s. The check searched by item ID alone, which
-- names no suffix, so the Wolf listings never came back.
--
-- What must hold:
--   1. The suffix is read from an item link, negative ones included.
--   2. A price check for a suffix item searches the key the auction house
--      gives that copy; an item with no suffix searches as before.
--   3. One suffix's search is never served as another's recent check.

local GLOBALS = { "time", "GetTime", "Enum", "UnitName", "GetRealmName", "C_Timer",
    "C_AuctionHouse", "C_Container", "ItemLocation" }
local saved = {}
for _, key in ipairs(GLOBALS) do saved[key] = _G[key] end

local passed, failed = 0, 0
local function check(label, condition)
    if condition then passed = passed + 1 else failed = failed + 1 end
    print(("  %s  %s"):format(condition and "ok" or "WRONG", label))
end

print("\nreading the suffix from a link")

do
    local util = {}
    util.NewModule = function(name) local m = {}; util[name] = m; return m end
    util.RegisterCommand, util.RegisterEvent = function() end, function() end
    assert(loadfile(lfs_cwd .. "/Core/Util.lua"))("Blackthornes_TS", util)
    local LinkSuffix = util.Util.LinkSuffix

    check("of the Wolf", LinkSuffix("|cff1eff00|Hitem:1076::::::612:1:60|h[Lead Band of the Wolf]|h|r") == 612)
    check("a negative suffix", LinkSuffix("|Hitem:1001::::::-12:1:60|h[x]|h") == -12)
    check("no suffix", LinkSuffix("|Hitem:2589::::::::60|h[Linen Cloth]|h") == nil)
    check("a zero suffix is none", LinkSuffix("|Hitem:2589:0:0:0:0:0:0:0:60|h[x]|h") == nil)
    check("nothing at all", LinkSuffix(nil) == nil)
end

local ns = {}
ns.COLORS = setmetatable({}, { __index = function() return "ffffffff" end })
ns.NewModule = function(name) local m = {}; ns[name] = m; return m end
ns.RegisterCommand = function() end
ns.RegisterEvent = function() return true end
ns.Print, ns.PrintRaw, ns.Debug, ns.Warn = function() end, function() end, function() end, function() end

local LEAD_BAND, CLOTH, WOLF = 1076, 2589, 612
local LINKS = {
    [1] = "|cff1eff00|Hitem:1076::::::612:1:60|h[Lead Band of the Wolf]|h|r",
    [2] = "|cffffffff|Hitem:2589::::::::60|h[Linen Cloth]|h|r",
}
local SLOTS = { [1] = LEAD_BAND, [2] = CLOTH }

ns.Util = {
    Clamp = function(v, l, h) return math.max(l, math.min(h, v)) end,
    Count = function(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end,
    Comma = tostring,
    FormatMoney = function(c) return tostring(c) end,
    FormatAge = function() return "" end,
    FormatAgeAgo = function() return "" end,
    GetItemLabel = function(i) return "item" .. tostring(i) end,
    GetMaxStackSize = function() return 20 end,
    GetVendorSellPrice = function() return nil end,
    UnitPriceFromStack = function(_, buyout, quantity) return math.floor(buyout / (quantity or 1)) end,
    HasFunction = function() return false end,
    RoundToSilver = function(p) if p < 100 then return 100 end return math.floor(p / 100) * 100 end,
    IsWholeSilver = function(p) return p >= 100 and p % 100 == 0 end,
    WhenAuctionReady = function(action) action() end,
    LinkSuffix = function(link)
        local suffix = link and tonumber(link:match("item:%d*:%d*:%d*:%d*:%d*:%d*:(%-?%d+)"))
        return suffix ~= 0 and suffix or nil
    end,
}

local priceTable = {}
ns.Config = {
    Get = function(_, key)
        if key == "undercutCopper" then return 1 end
        if key == "verifyPriceBeforePosting" then return true end
        return nil
    end,
    GetPriceTable = function() return priceTable end,
    GetRealmKey = function() return "TestRealm" end,
}
ns.db = {}
ns.Cost = { FindRecipeForItem = function() return nil end }
ns.Cost.FindAnyRecipeForItem = ns.Cost.FindRecipeForItem
ns.Auctions = { GetPostedCount = function() return 0 end }
ns.AHQueue = { PRIORITY = { urgent = 10, normal = 50, scan = 90 } }
ns.Inventory = { GetCarriedBags = function() return { 0 } end }

time = os.time
GetTime = function() return 100 end
Enum = { ItemCommodityStatus = { Commodity = 2 }, BagIndex = {} }
UnitName = function() return "Tester" end
GetRealmName = function() return "TestRealm" end
C_Timer = {
    NewTimer = function() return { Cancel = function() end } end,
    After = function() end,
    NewTicker = function() return { Cancel = function() end } end,
}

C_Container = {
    GetContainerNumSlots = function(bag) return bag == 0 and 4 or 0 end,
    GetContainerItemInfo = function(bag, slot)
        if bag ~= 0 or not SLOTS[slot] then return nil end
        return { itemID = SLOTS[slot], stackCount = 1, hyperlink = LINKS[slot] }
    end,
    GetContainerItemLink = function(bag, slot) return bag == 0 and LINKS[slot] or nil end,
}

ItemLocation = {
    CreateFromBagAndSlot = function(_, bag, slot)
        return { bag = bag, slot = slot, IsValid = function() return true end }
    end,
}

local sent = {}
C_AuctionHouse = {
    MakeItemKey = function(itemID) return { itemID = itemID, itemLevel = 0, itemSuffix = 0 } end,
    GetItemKeyFromItem = function(location)
        local itemID = SLOTS[location.slot]
        return { itemID = itemID, itemLevel = 7, itemSuffix = itemID == LEAD_BAND and WOLF or 0 }
    end,
    SendSearchQuery = function(key) sent[#sent + 1] = key; return true end,
    GetNumItemSearchResults = function() return 0 end,
}

assert(loadfile(lfs_cwd .. "/Data/Prices.lua"))("Blackthornes_TS", ns)
assert(loadfile(lfs_cwd .. "/Data/Scanner.lua"))("Blackthornes_TS", ns)
assert(loadfile(lfs_cwd .. "/Logic/Profit.lua"))("Blackthornes_TS", ns)
assert(loadfile(lfs_cwd .. "/Logic/Posting.lua"))("Blackthornes_TS", ns)

local Scanner, Posting = ns.Scanner, ns.Posting
Scanner.isAuctionHouseOpen = true
Posting.Confirm = function() end

print("\nthe key a price check searches")

do
    local key = Posting:GetSearchKey(LEAD_BAND)
    check("the Lead Band in the bags gives its own key", key and key.itemSuffix == WOLF)
    check("cloth has no suffix, so no special key", Posting:GetSearchKey(CLOTH) == nil)

    Posting:CheckPrice(LEAD_BAND, function() end)
    check("the check searches for the Wolf suffix", sent[#sent] and sent[#sent].itemSuffix == WOLF)

    Scanner:ClearSearchState()
    Posting:Request(CLOTH, 1)
    check("cloth searches as it always did", sent[#sent] and sent[#sent].itemID == CLOTH
        and sent[#sent].itemLevel == 0)
end

print("\none suffix is not another's recent check")

do
    Scanner:ClearSearchState()
    Scanner.recentItemScans = {}
    local before = #sent
    Scanner:ScanItem(LEAD_BAND, nil, { itemKey = { itemID = LEAD_BAND, itemSuffix = WOLF } })
    Scanner:ClearSearchState()
    local answered
    Scanner:ScanItem(LEAD_BAND, function(_, _, _, _, _, _, status) answered = status end,
        { itemKey = { itemID = LEAD_BAND, itemSuffix = 613 } })
    check("of the Bear right after of the Wolf searches again", #sent == before + 2 and answered == nil)

    Scanner:ClearSearchState()
    Scanner:ScanItem(LEAD_BAND, function(_, _, _, _, _, _, status) answered = status end,
        { itemKey = { itemID = LEAD_BAND, itemSuffix = WOLF } })
    check("of the Wolf again is served from its own recent search", answered == "recent")
end

for _, key in ipairs(GLOBALS) do _G[key] = saved[key] end

print("")
if failed > 0 then
    error(("FAIL -- %d of %d suffix checks wrong"):format(failed, passed + failed))
end
print(("PASS -- suffix items are searched by their own suffix (%d checks)"):format(passed))
