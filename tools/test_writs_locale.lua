-- Craftsman's Writs on a client in another language (a player's report,
-- 2026-11-09): a Chinese client names Craftsman's Writ: Blue Overalls
-- "工匠文书：蓝色罩衫", so the English names found nothing and the writ
-- showed no price.
--
-- What this pins down:
--   * a writ named in the client's language is found by the client's name
--     for the item it asks for, after the prefix a known writ shows;
--   * a name seen before the client has given every name it needs is
--     judged again when the names come in;
--   * the list shows the client's item names and search still finds the
--     English ones;
--   * an English client is untouched.

local ns = {}
ns.COLORS = setmetatable({}, { __index = function() return "ffffffff" end })
ns.NewModule = function(name) local m = {}; ns[name] = m; return m end
ns.RegisterCommand = function() end
local handlers = {}
ns.RegisterEvent = function(_, event, fn) handlers[event] = handlers[event] or {}; table.insert(handlers[event], fn) end
local function Fire(event, ...)
    for _, fn in ipairs(handlers[event] or {}) do fn(nil, event, ...) end
end
ns.Print, ns.PrintRaw, ns.Debug, ns.Warn = function() end, function() end, function() end

-- Put back at the end: every suite shares one Lua runtime.
local saved = { C_Item = C_Item, GetTime = GetTime, C_Timer = C_Timer, GetLocale = GetLocale,
                UnitFactionGroup = UnitFactionGroup }

GetTime = function() return 100 end
local later = {}
C_Timer = { After = function(_, fn) later[#later + 1] = fn end }
local function Flush()
    local run = later
    later = {}
    for _, fn in ipairs(run) do fn() end
end

local locale = "zhCN"
GetLocale = function() return locale end

local OVERALLS, ARTHAS = 6263, 9088
local ARTHAS_WRIT, OVERALLS_WRIT, OTHER = 264120, 264150, 264151

-- Names the client has given so far; the rest are still loading.
local items = {
    [ARTHAS] = "阿尔萨斯的礼物",
    [ARTHAS_WRIT] = "工匠文书：阿尔萨斯的礼物",
    [OVERALLS_WRIT] = "工匠文书：蓝色罩衫",
    [OTHER] = "某个永恒物品",
}
C_Item = {
    GetItemInfo = function(itemID) return items[itemID] end,
    RequestLoadItemDataByID = function() end,
}

assert(loadfile(lfs_cwd .. "/Core/Util.lua"))("Blackthornes_TS", ns)
ns.Config = {
    Get = function() return nil end,
    Set = function() end,
    GetCharacterKey = function() return "Player-1-0001" end,
}
ns.Prices = {
    GetValue = function(_, itemID) return itemID == OVERALLS_WRIT and 700 or nil end,
    ListedNow = function(_, itemID) return itemID == OVERALLS_WRIT and 700 or nil, false end,
    ListedCounts = function() return nil, nil end,
    Count = function() return 0 end,
}
ns.Cost = {
    GetReagentUnitCost = function() return nil end,
    FindAnyRecipeForItem = function() return nil end,
    GetMaterialValue = function() return nil end,
}
ns.Inventory = {
    GetBagCounts = function() return {} end,
    GetBagCount = function() return 0 end,
    GetOwnedCount = function() return 0 end,
}
ns.db = {}

assert(loadfile(lfs_cwd .. "/Data/CraftsmansWrits.lua"))("Blackthornes_TS", ns)
assert(loadfile(lfs_cwd .. "/Logic/Writs.lua"))("Blackthornes_TS", ns)
local Writs = ns.Writs
UnitFactionGroup = UnitFactionGroup or function() return "Alliance" end
Writs:OnEnable()

local checks = 0
local function check(label, condition)
    checks = checks + 1
    if not condition then error(("FAILED: %s"):format(label), 2) end
    print(("  ok  %s"):format(label))
end

local overalls = Writs.WritForItem(OVERALLS)

--------------------------------------------------------------------------------
print("\nnames still loading")

check("the English names find nothing", Writs.WritForName(items[OVERALLS_WRIT]) == nil)
check("Blue Overalls' own name is not in yet, so the writ waits",
    Writs:Classify(OVERALLS_WRIT) == nil and Writs:GetWritID(overalls) == nil)

items[OVERALLS] = "蓝色罩衫"
for _, writ in ipairs(ns.CRAFTSMANS_WRITS) do
    items[writ.item] = items[writ.item] or ("物品" .. writ.item)
end
Fire("GET_ITEM_INFO_RECEIVED", OVERALLS)
Flush()

--------------------------------------------------------------------------------
print("\nnames in")

check("the writ is found by the client's name", Writs:GetWritID(overalls) == OVERALLS_WRIT)
check("and kept in the save", ns.db.merchantsFavor.writIDs[OVERALLS] == OVERALLS_WRIT)
check("another item is no writ", Writs:Classify(OTHER) == nil)
check("a name the prefix fits but no writ asks for is none either",
    Writs.WritForClientName("工匠文书：不存在") == nil)

local rows = Writs:GetRows()
local row
for _, r in ipairs(rows) do if r.itemID == OVERALLS then row = r end end
check("its row has the writ's price", row and row.writID == OVERALLS_WRIT and row.writPrice == 700)
check("the row shows the client's name", row.name == "蓝色罩衫" and row.english == "Blue Overalls")

--------------------------------------------------------------------------------
print("\nan English client")

locale = "enUS"
check("an English client reads only English names", Writs.EnglishClient() == true
    and Writs:Classify(264152) == nil)
items[264152] = "Craftsman's Writ: Golden Rod"
check("and finds them as before", Writs.WritForName(items[264152]).item == 11128)

for _, key in ipairs({ "C_Item", "GetTime", "C_Timer", "GetLocale", "UnitFactionGroup" }) do
    _G[key] = saved[key]
end

print(("\n%d checks passed"):format(checks))
