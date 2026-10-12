-- Blackthornes Tradeskills -- Logic/Banks.lua
-- Every character's bank in one list.
--
-- Nothing new is read or saved here. Inventory already keeps a count of each
-- character's bank from the last time that character stood at one, and of
-- their bags from the last time they were played; this puts those counts side
-- by side, item by item, so "which alt has my Silk Cloth" has an answer
-- without logging round the whole account.

local _, ns = ...
local L = ns.L or setmetatable({ Format = string.format }, { __index = function(_, key) return key end })

local Banks = ns.NewModule("Banks")

local Util = ns.Util

local POOR = (Enum and Enum.ItemQuality and Enum.ItemQuality.Poor) or 0

--------------------------------------------------------------------------------
-- Item facts
--------------------------------------------------------------------------------

--- The item's name and quality from the client, as plain values, or nil.
--
-- Read and used inside the pcall, so an item the client hands back as a
-- secret value costs its name rather than raising.
local function ItemFacts(itemID)
    if not Util.HasFunction("C_Item.GetItemInfo") then return nil end

    local ok, name, quality = pcall(function()
        local itemName, _, itemQuality = C_Item.GetItemInfo(itemID)
        local plainName = type(itemName) == "string" and (itemName .. "") or nil
        local plainQuality = type(itemQuality) == "number" and (itemQuality + 0) or nil
        return plainName, plainQuality
    end)

    if not ok then return nil end
    return name, quality
end

--- A name to search and sort by: the client's, then one the addon saved
--- itself, then the ID.
--
-- `Banks.waiting` is set whenever an item the client has not loaded is met,
-- here or in UnitWorth, so the bank view knows to draw again once it loads.
function Banks:GetName(itemID)
    local name = ItemFacts(itemID)
    if name then return name end
    self.waiting = true

    if ns.Disenchant and ns.Disenchant.KnownName then
        local ok, known = pcall(ns.Disenchant.KnownName, ns.Disenchant, itemID)
        if ok and type(known) == "string" then return known end
    end

    return L.Format("item %d", itemID)
end

--- What one of an item is worth, in copper, or nil when nothing is known.
--
-- Grey items are worth what a vendor pays and nothing more; anything else is
-- the better of the auction price and the vendor price. An item the client
-- has not loaded yet has no quality to go by, so it gets no auction price
-- until it loads: a grey one was valued at whatever someone had listed it for.
function Banks:UnitWorth(itemID)
    local vendor = Util.GetVendorSellPrice(itemID)

    local _, quality = ItemFacts(itemID)
    if quality == nil then
        self.waiting = true
        return vendor
    end
    if quality == POOR then return vendor end

    local auction
    if ns.Prices and ns.Prices.GetValue then
        local ok, value = pcall(ns.Prices.GetValue, ns.Prices, itemID)
        if ok and type(value) == "number" and value > 0 then auction = value end
    end

    if auction and vendor then return math.max(auction, vendor) end
    return auction or vendor
end

--------------------------------------------------------------------------------
-- Collecting
--------------------------------------------------------------------------------

--- The saved counts for one character.
--
-- The character being played has live bags; their bank is the snapshot, which
-- is kept current while the bank is open and is the best there is once it
-- shuts. Everyone else is the snapshot from their last session.
-- @return bank, bags  (itemID -> count tables; bags nil unless asked for)
local function CountsFor(key, record, withBags)
    local bank = type(record.bank) == "table" and record.bank or {}
    if not withBags then return bank, nil end

    local bags
    if key == ns.Config:GetCharacterKey() and ns.Inventory and ns.Inventory.GetBagCounts then
        local ok, live = pcall(ns.Inventory.GetBagCounts, ns.Inventory)
        bags = ok and type(live) == "table" and live or nil
    end

    bags = bags or (type(record.inventory) == "table" and record.inventory) or {}
    return bank, bags
end

--- Every item in the chosen banks, one entry per item.
--
-- @param opts { character = key (nil for everyone), bags = true to add bags,
--               search = text to match names against }
-- @return list of { itemID, name, total, bank, bags, worth, unit,
--                   holders = { { key, bank, bags }, ... } }
function Banks:Collect(opts)
    opts = opts or {}

    local items = {}
    local characters = ns.db and ns.db.characters or {}

    for key, record in pairs(characters) do
        if type(record) == "table" and (not opts.character or key == opts.character) then
            local bank, bags = CountsFor(key, record, opts.bags)

            local function Add(counts, field)
                for itemID, count in pairs(counts or {}) do
                    if type(itemID) == "number" and type(count) == "number" and count > 0 then
                        local entry = items[itemID]
                        if not entry then
                            entry = { itemID = itemID, total = 0, bank = 0, bags = 0, holders = {}, byKey = {} }
                            items[itemID] = entry
                        end

                        local holder = entry.byKey[key]
                        if not holder then
                            holder = { key = key, bank = 0, bags = 0 }
                            entry.byKey[key] = holder
                            entry.holders[#entry.holders + 1] = holder
                        end

                        holder[field] = holder[field] + count
                        entry[field] = entry[field] + count
                        entry.total = entry.total + count
                    end
                end
            end

            Add(bank, "bank")
            Add(bags, "bags")
        end
    end

    local needle = type(opts.search) == "string" and opts.search:lower() or ""

    local list = {}
    for itemID, entry in pairs(items) do
        entry.byKey = nil
        entry.name = self:GetName(itemID)

        if needle == "" or entry.name:lower():find(needle, 1, true) then
            entry.unit = self:UnitWorth(itemID)
            entry.worth = entry.unit and entry.unit * entry.total or nil

            table.sort(entry.holders, function(a, b)
                local left, right = a.bank + a.bags, b.bank + b.bags
                if left ~= right then return left > right end
                return a.key < b.key
            end)

            list[#list + 1] = entry
        end
    end

    return list
end

--- Sort a collected list in place: "worth" (default), "count" or "name".
function Banks:Sort(list, by)
    table.sort(list, function(a, b)
        if by == "name" then
            if a.name ~= b.name then return a.name < b.name end
        elseif by == "count" then
            if a.total ~= b.total then return a.total > b.total end
        else
            local left, right = a.worth or -1, b.worth or -1
            if left ~= right then return left > right end
        end

        return a.itemID < b.itemID
    end)

    return list
end

--- Each character's bank at a glance, for the overview.
-- @return list of { key, name, isCurrent, bankAt, kinds, count, worth },
--         in the Characters tab's order (the one you are playing first)
function Banks:Overview()
    local rows = {}
    if not ns.db or not ns.Recipes then return rows end

    for _, character in ipairs(ns.Recipes:GetCharacters()) do
        local record = ns.db.characters[character.key]
        local bank = type(record) == "table" and type(record.bank) == "table" and record.bank or nil

        local row = {
            key = character.key,
            name = character.name,
            isCurrent = character.isCurrent,
            bankAt = character.bankAt,
            kinds = 0,
            count = 0,
            worth = 0,
        }

        for itemID, count in pairs(bank or {}) do
            if type(itemID) == "number" and type(count) == "number" and count > 0 then
                row.kinds = row.kinds + 1
                row.count = row.count + count
                row.worth = row.worth + (self:UnitWorth(itemID) or 0) * count
            end
        end

        rows[#rows + 1] = row
    end

    return rows
end

--------------------------------------------------------------------------------
-- Command
--------------------------------------------------------------------------------

ns.RegisterCommand("bank", L["see what is in every character's bank"], function()
    if ns.UI and ns.UI.Show then
        ns.UI:Show()
        if ns.UI.SelectTab then ns.UI:SelectTab("characters") end
        if ns.CharactersTab and ns.CharactersTab.ShowView then
            ns.CharactersTab.ShowView("bank")
        end
        return
    end

    ns.Print(L["the window is not ready yet, try again in a moment"])
end)
