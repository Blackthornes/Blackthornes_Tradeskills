-- Blackthornes Tradeskills -- Logic/ShoppingLists.lua
-- Named shopping lists (a player asked, the owner said build it, 2026-10-14).
--
-- The player makes lists, names them and puts items on them, each with how
-- many they want. At the auction house the drawer's Lists view
-- (UI/ShoppingListsView.lua) shows them; a list's Search looks up every item
-- on it the player still needs, and an item's own Search looks up that one.
-- The craft queue's shopping list is always the first list, "From your craft
-- queue", built from Queue:GetShoppingList and never saved.
--
-- Saved account wide in `shoppingLists` (never rename it):
--   { { name = "Potion herbs", items = { { id = 2447, want = 40 }, ... } }, ... }
-- in the order the player made them. Nothing else from the save goes in, and
-- a list is only ever removed by the player (Delete).
--
-- Copy and paste: Export gives one line, "BTSlist1:<name>:<id>*<want>,...",
-- items only, and Import makes a new list from one. The line is read as data:
-- numbers and a name, nothing run.

local _, ns = ...
local L = ns.L or setmetatable({ Format = string.format }, { __index = function(_, key) return key end })

local ShoppingLists = ns.NewModule("ShoppingLists")

local Util = ns.Util

ShoppingLists.MAX_LISTS = 50
ShoppingLists.MAX_ITEMS = 100
ShoppingLists.MAX_NAME = 40
ShoppingLists.MAX_WANT = 99999
ShoppingLists.PREFIX = "BTSlist1"

-- Moves on every change, so a view redraws only when something moved.
ShoppingLists.version = 0

local function Changed()
    ShoppingLists.version = ShoppingLists.version + 1
end

--------------------------------------------------------------------------------
-- Storage
--------------------------------------------------------------------------------

--- Every list the player made, in order. A broken entry in the save is
--- skipped, never deleted.
function ShoppingLists:All()
    if not ns.db then return {} end
    if type(ns.db.shoppingLists) ~= "table" then ns.db.shoppingLists = {} end
    return ns.db.shoppingLists
end

local function IsList(list)
    return type(list) == "table" and type(list.name) == "string"
end

local function Items(list)
    if type(list.items) ~= "table" then list.items = {} end
    return list.items
end

--- The lists that can be read, in order, with their place in the save.
-- @return { { index, list } ... }
function ShoppingLists:Readable()
    local out = {}
    for index, list in ipairs(self:All()) do
        if IsList(list) then out[#out + 1] = { index = index, list = list } end
    end
    return out
end

function ShoppingLists:Get(index)
    local list = self:All()[tonumber(index) or 0]
    return IsList(list) and list or nil
end

--- A name as kept: trimmed, no line breaks or the two marks the copy line
--- uses, and no longer than MAX_NAME.
function ShoppingLists.CleanName(name)
    if type(name) ~= "string" then return nil end
    name = name:gsub("[\r\n\t:,|]", " "):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
    if #name > ShoppingLists.MAX_NAME then name = name:sub(1, ShoppingLists.MAX_NAME):gsub("%s+$", "") end
    if name == "" then return nil end
    return name
end

local function NameTaken(name, except)
    local lower = name:lower()
    for index, list in ipairs(ShoppingLists:All()) do
        if index ~= except and IsList(list) and list.name:lower() == lower then return true end
    end
    return false
end

--- The name given, or with a number after it when another list has it.
local function FreeName(name, except)
    if not NameTaken(name, except) then return name end
    for n = 2, ShoppingLists.MAX_LISTS + 1 do
        local tried = ShoppingLists.CleanName(("%s %d"):format(name, n))
        if tried and not NameTaken(tried, except) then return tried end
    end
    return name
end

--- Make a new empty list.
-- @return its index, or nil and why
function ShoppingLists:Make(name)
    name = self.CleanName(name)
    if not name then return nil, L["Give the list a name."] end
    local lists = self:All()
    if #self:Readable() >= self.MAX_LISTS then
        return nil, L.Format("You have %d lists, the most there can be.", self.MAX_LISTS)
    end
    lists[#lists + 1] = { name = FreeName(name), items = {} }
    Changed()
    return #lists
end

function ShoppingLists:Rename(index, name)
    local list = self:Get(index)
    if not list then return nil, L["That list is gone."] end
    name = self.CleanName(name)
    if not name then return nil, L["Give the list a name."] end
    list.name = FreeName(name, tonumber(index))
    Changed()
    return true
end

--- Remove a list. Only ever the player's own click (a second one, in the
--- view), so a list never goes by itself.
function ShoppingLists:Delete(index)
    index = tonumber(index)
    if not self:Get(index) then return false end
    table.remove(self:All(), index)
    Changed()
    return true
end

local function CleanWant(want)
    want = math.floor(tonumber(want) or 1)
    return math.max(1, math.min(ShoppingLists.MAX_WANT, want))
end

--- Put an item on a list, or add to how many are wanted when it is there.
-- @return true, or nil and why
function ShoppingLists:Add(index, itemID, want)
    local list = self:Get(index)
    if not list then return nil, L["That list is gone."] end
    itemID = math.floor(tonumber(itemID) or 0)
    if itemID <= 0 then return nil, L["That is not an item."] end

    local items = Items(list)
    for _, item in ipairs(items) do
        if type(item) == "table" and item.id == itemID then
            item.want = CleanWant((tonumber(item.want) or 0) + CleanWant(want))
            Changed()
            return true
        end
    end
    if #items >= self.MAX_ITEMS then
        return nil, L.Format("A list holds at most %d items.", self.MAX_ITEMS)
    end
    items[#items + 1] = { id = itemID, want = CleanWant(want) }
    Changed()
    return true
end

function ShoppingLists:Remove(index, itemID)
    local list = self:Get(index)
    if not list then return false end
    local items = Items(list)
    for i, item in ipairs(items) do
        if type(item) == "table" and item.id == itemID then
            table.remove(items, i)
            Changed()
            return true
        end
    end
    return false
end

function ShoppingLists:SetWant(index, itemID, want)
    local list = self:Get(index)
    if not list then return false end
    for _, item in ipairs(Items(list)) do
        if type(item) == "table" and item.id == itemID then
            local clean = CleanWant(want)
            if item.want ~= clean then
                item.want = clean
                Changed()
            end
            return true
        end
    end
    return false
end

--------------------------------------------------------------------------------
-- Reading a list
--------------------------------------------------------------------------------

--- Can the auction house help with this line? Still short, and not from a
--- vendor that never runs out (the Buy list's own rule).
function ShoppingLists.CanSearch(line)
    return type(line) == "table" and (line.need or 0) > 0
        and (not line.fromVendor or line.vendorLimited == true)
end

--- One item of a list as a row: how many are wanted, owned (bags, bank and
--- mail, as the craft queue counts) and still needed, and what one costs.
function ShoppingLists:Line(itemID, want)
    local have = 0
    if ns.Inventory and ns.Inventory.GetOwnedCount then
        local ok, owned = pcall(ns.Inventory.GetOwnedCount, ns.Inventory, itemID)
        if ok and type(owned) == "number" then have = owned end
    end

    local vendor = ns.Vendor and ns.Vendor:GetUnitPrice(itemID) or nil
    local auction = ns.Prices and ns.Prices:GetValue(itemID, "lowest") or nil
    local keeps = vendor ~= nil and ns.Vendor:KeepsInStock(itemID)
    local fromVendor = vendor ~= nil and (keeps or not auction or vendor <= auction)

    local need = math.max(0, want - have)
    local unit = fromVendor and vendor or auction
    return {
        itemID = itemID,
        want = want,
        have = have,
        need = need,
        unit = unit,
        cost = unit and unit * need or nil,
        fromVendor = fromVendor,
        vendorLimited = fromVendor and ns.Vendor:IsLimited(itemID) or false,
    }
end

--- Every item on a list as rows, in the list's order.
function ShoppingLists:Lines(index)
    local list = self:Get(index)
    local lines = {}
    if not list then return lines end
    for _, item in ipairs(Items(list)) do
        local id = type(item) == "table" and tonumber(item.id)
        if id then lines[#lines + 1] = self:Line(id, CleanWant(item.want)) end
    end
    return lines
end

--- The craft queue's shopping list as the same rows: what it still needs.
function ShoppingLists:QueueLines()
    local lines = {}
    if not (ns.Queue and ns.Queue.GetShoppingList) then return lines end
    local ok, shopping = pcall(ns.Queue.GetShoppingList, ns.Queue)
    if not ok or type(shopping) ~= "table" then return lines end
    for _, line in ipairs(shopping) do
        if (line.shortfall or 0) > 0 then
            lines[#lines + 1] = {
                itemID = line.itemID,
                want = line.needed or line.shortfall,
                have = line.have or 0,
                need = line.shortfall,
                unit = line.unitCost,
                cost = line.estimatedCost,
                fromVendor = line.fromVendor,
                vendorLimited = line.vendorLimited,
            }
        end
    end
    return lines
end

--- What the items still needed cost, and whether any had no price.
function ShoppingLists.Total(lines)
    local total, unpriced = 0, 0
    for _, line in ipairs(lines) do
        if (line.need or 0) > 0 then
            if line.cost then total = total + line.cost else unpriced = unpriced + 1 end
        end
    end
    return total, unpriced
end

--- The items of these rows worth searching the auction house for.
function ShoppingLists.Searchable(lines)
    local ids = {}
    for _, line in ipairs(lines) do
        if ShoppingLists.CanSearch(line) then ids[#ids + 1] = line.itemID end
    end
    return ids
end

--- Save the craft queue's list as a list of the player's own, to change.
function ShoppingLists:SaveQueue(name)
    local lines = self:QueueLines()
    if #lines == 0 then return nil, L["The craft queue needs nothing right now."] end
    local index, why = self:Make(name or L["From your craft queue"])
    if not index then return nil, why end
    for _, line in ipairs(lines) do self:Add(index, line.itemID, line.want) end
    return index
end

--------------------------------------------------------------------------------
-- Finding an item from what the player typed
--------------------------------------------------------------------------------

--- An item from a link, an item ID or a name the client knows.
function ShoppingLists.ResolveItem(text)
    if type(text) ~= "string" then return tonumber(text) end
    local id = tonumber(text:match("item:(%d+)")) or tonumber(text:match("^%s*(%d+)%s*$"))
    if id then return id end

    local name = text:gsub("^%s+", ""):gsub("%s+$", "")
    if name == "" then return nil end
    for _, path in ipairs({ "C_Item.GetItemInfoInstant", "C_Item.GetItemInfo" }) do
        if Util.HasFunction(path) then
            local fn = path == "C_Item.GetItemInfoInstant" and C_Item.GetItemInfoInstant or C_Item.GetItemInfo
            local ok, a, b = pcall(fn, name)
            if ok then
                if type(a) == "number" then return a end
                if type(b) == "string" then
                    local found = tonumber(b:match("item:(%d+)"))
                    if found then return found end
                end
            end
        end
    end
    return nil
end

--------------------------------------------------------------------------------
-- Copy and paste
--------------------------------------------------------------------------------

function ShoppingLists:Export(index)
    local list = self:Get(index)
    if not list then return nil end
    local parts = {}
    for _, item in ipairs(Items(list)) do
        local id = type(item) == "table" and tonumber(item.id)
        if id then parts[#parts + 1] = ("%d*%d"):format(id, CleanWant(item.want)) end
    end
    return ("%s:%s:%s"):format(self.PREFIX, self.CleanName(list.name) or "", table.concat(parts, ","))
end

--- Make a new list from a copied line.
-- @return its index, or nil and why
function ShoppingLists:Import(text)
    if type(text) ~= "string" then return nil, L["That is not a copied list."] end
    local name, body = text:match("^%s*" .. self.PREFIX .. ":([^:]*):([%d%*,]*)%s*$")
    if not name then return nil, L["That is not a copied list."] end

    local items = {}
    for id, want in body:gmatch("(%d+)%*(%d+)") do
        if #items >= self.MAX_ITEMS then break end
        items[#items + 1] = { tonumber(id), tonumber(want) }
    end
    if #items == 0 then return nil, L["That list has no items."] end

    local index, why = self:Make(self.CleanName(name) or L["Pasted list"])
    if not index then return nil, why end
    for _, item in ipairs(items) do self:Add(index, item[1], item[2]) end
    return index
end

--------------------------------------------------------------------------------
-- Searching
--------------------------------------------------------------------------------

--- Look up several items at once in the game's own results, where the
--- client offers it; through the same throttled queue as every other search,
--- so it never costs the player a listing.
-- @return true when the search was queued, or false and why
function ShoppingLists:SearchMany(itemIDs)
    if type(itemIDs) ~= "table" or #itemIDs == 0 then
        return false, L["Nothing on this list to look for on the auction house."]
    end
    local scanner = ns.Scanner
    if not (scanner and scanner.isAuctionHouseOpen) then
        return false, L["open the auction house first"]
    end
    if scanner.isScanning then
        return false, L["a scan is running; search again once it finishes"]
    end

    -- One item: the ordinary search, which also fills the quantity.
    if #itemIDs == 1 or not (Util.HasFunction("C_AuctionHouse.SearchForItemKeys")
            and Util.HasFunction("C_AuctionHouse.MakeItemKey")) then
        return false, "single"
    end

    local keys = {}
    for _, id in ipairs(itemIDs) do
        local ok, key = pcall(C_AuctionHouse.MakeItemKey, id)
        if ok and key then keys[#keys + 1] = key end
    end
    if #keys == 0 then return false, "single" end

    ns.AHQueue:Request({
        name = ("search the auction house for %d items"):format(#keys),
        key = "ui-search",
        priority = ns.AHQueue.PRIORITY.urgent,
        expires = 8,
        send = function()
            local ok = pcall(C_AuctionHouse.SearchForItemKeys, keys, {})
            if not ok then
                ns.Warn(L["the game refused that search"])
                return false
            end
            return true
        end,
        onGiveUp = function()
            if not (ns.AHQueue.IsFlushing and ns.AHQueue:IsFlushing()) then
                ns.Warn(L["the auction house stayed busy; that search was not sent."])
            end
        end,
    })
    return true
end
