-- Blackthornes Tradeskills -- Logic/ListRules.lua
-- Rules for a whole list (the owner said build it, 2026-10-19, from a
-- mockup): a list on the Lists view (Logic/ShoppingLists.lua) can carry a
-- few rules that every item on it follows, so a rule is set once for a
-- whole list instead of item by item.
--
-- Kept on the list itself, `shoppingLists[i].rules` (never rename it):
--   floor    copper: List all and List never go under it (Lowest Price)
--   listed   stacks: no more than this many up at a time (Keep Listed)
--   duration 1, 2 or 3, as postDuration: how long it goes up (Post For)
--   bags     units: this many stay in the bags (Keep in Bags)
--   maxPay   copper: the buy box fills only with what costs this or less
--            each (Most I'll Pay)
-- A field left out has no rule. A new list has none, so nothing changes
-- until the player sets one.
--
-- An item's own setting always wins: its own price on the Prices tab beats
-- Lowest Price, and the bigger keep wins (Butler's, Tradeskills' own, the
-- list's). On two lists, the one higher up on the Lists view wins.
--
-- Each list also gets a stable `id` (a number, made once, never renamed),
-- so Butler can keep its own rules for a list by id when it is renamed.

local _, ns = ...

local ListRules = ns.NewModule("ListRules")

ListRules.FIELDS = { "floor", "listed", "duration", "bags", "maxPay" }
ListRules.MAX_LISTED = 99
ListRules.MAX_BAGS = 99999
-- The most the gold box takes (214748g), as the price editor.
ListRules.MAX_MONEY = 214748 * 10000 + 9999

local LIMITS = {
    floor = { 1, ListRules.MAX_MONEY },
    listed = { 1, ListRules.MAX_LISTED },
    duration = { 1, 3 },
    bags = { 1, ListRules.MAX_BAGS },
    maxPay = { 1, ListRules.MAX_MONEY },
}

local function Lists() return ns.ShoppingLists end

--- A rule's value as kept: a whole number in range, or nil for no rule.
function ListRules.Clean(field, value)
    local limit = LIMITS[field]
    value = tonumber(value)
    if not limit or not value then return nil end
    value = math.floor(value)
    if value < limit[1] then return nil end
    return math.min(limit[2], value)
end

--- The list's rules, cleaned: a fresh table holding only the rules set.
function ListRules.Of(list)
    local out = {}
    local rules = type(list) == "table" and list.rules
    if type(rules) ~= "table" then return out end
    for _, field in ipairs(ListRules.FIELDS) do
        out[field] = ListRules.Clean(field, rules[field])
    end
    return out
end

--- How many rules a list has.
function ListRules.Count(list)
    local count = 0
    for _ in pairs(ListRules.Of(list)) do count = count + 1 end
    return count
end

--- Set one rule on the list at `index`; nil or 0 takes it off.
-- @return true when the list is there
function ListRules:Set(index, field, value)
    local list = Lists() and Lists():Get(index)
    if not list or not LIMITS[field] then return false end
    if type(list.rules) ~= "table" then list.rules = {} end
    local clean = ListRules.Clean(field, value)
    if list.rules[field] ~= clean then
        list.rules[field] = clean
        if next(list.rules) == nil then list.rules = nil end
        Lists():Touch()
    end
    return true
end

--- Take every rule off a list.
function ListRules:Clear(index)
    local list = Lists() and Lists():Get(index)
    if not list then return false end
    if list.rules ~= nil then
        list.rules = nil
        Lists():Touch()
    end
    return true
end

-- [itemID] = { name, index, id, rules }, laid out once per lists version.
local lookup, lookupVersion

--- The list whose rules an item follows: the first on the Lists view that
--- holds it and has any rule, or nil.
-- @return { name, index, id, rules } (do not change it)
function ListRules:For(itemID)
    local lists = Lists()
    itemID = tonumber(itemID)
    if not lists or not itemID or not ns.db then return nil end
    if lookup == nil or lookupVersion ~= lists.version then
        lookup, lookupVersion = {}, lists.version
        for _, held in ipairs(lists:Readable()) do
            local rules = ListRules.Of(held.list)
            if next(rules) ~= nil then
                local entry = { name = held.list.name, index = held.index, id = held.list.id, rules = rules }
                for _, item in ipairs(type(held.list.items) == "table" and held.list.items or {}) do
                    local id = type(item) == "table" and tonumber(item.id)
                    if id and lookup[id] == nil then lookup[id] = entry end
                end
            end
        end
    end
    return lookup[itemID]
end

--- One rule for an item: its value and the list's name, or nil.
function ListRules:Rule(itemID, field)
    local entry = self:For(itemID)
    local value = entry and entry.rules[field]
    if value then return value, entry.name end
    return nil
end

--- The least an item may be listed at by its list, unless the Prices tab
--- has a price of its own for it (that wins).
-- @return copper, the list's name; or nil
function ListRules:Floor(itemID)
    local floor, name = self:Rule(itemID, "floor")
    if not floor then return nil end
    if ns.Prices and ns.Prices.GetMine and ns.Prices:GetMine(itemID) then return nil end
    return floor, name
end

--- True when the item is on a list with Lowest Price but its own price on
--- the Prices tab wins, with the list's name.
function ListRules:OwnPriceWins(itemID)
    local floor, name = self:Rule(itemID, "floor")
    if floor and ns.Prices and ns.Prices.GetMine and ns.Prices:GetMine(itemID) then return true, name end
    return false
end

--- How long an item goes up for: its list's Post For, else the setting.
function ListRules:Duration(itemID)
    local duration = itemID and self:Rule(itemID, "duration")
    if duration then return duration end
    return (ns.Config and ns.Config:Get("postDuration")) or 2
end

--- How big one stack of the item is, as the game says (1 when it won't).
function ListRules.StackSize(itemID)
    local size
    if C_Item and type(C_Item.GetItemMaxStackSizeByID) == "function" then
        local ok, value = pcall(C_Item.GetItemMaxStackSizeByID, itemID)
        size = ok and tonumber(value) or nil
    end
    if not size and type(GetItemInfo) == "function" then
        local ok, value = pcall(function() return select(8, GetItemInfo(itemID)) end)
        size = ok and tonumber(value) or nil
    end
    return math.max(1, math.floor(size or 1))
end

--- Keep Listed for an item: how many more units may go up, and how many
--- stacks are up now.
-- @return room (units, 0 when full), stacksUp; or nil when no rule
function ListRules:ListedRoom(itemID)
    local stacks = self:Rule(itemID, "listed")
    if not stacks then return nil end
    local size = ListRules.StackSize(itemID)
    local up = 0
    if ns.Auctions and ns.Auctions.GetOwnPostedCount then
        local ok, count = pcall(ns.Auctions.GetOwnPostedCount, ns.Auctions, itemID)
        up = ok and tonumber(count) or 0
    end
    return math.max(0, stacks * size - up), math.ceil(up / size)
end
