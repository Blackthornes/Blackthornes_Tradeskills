-- Blackthornes Tradeskills -- Logic/VendorPins.lua
-- Which vendors sell what the queue needs for less than the auction house,
-- and where they stand, for the pins on the world map (UI/VendorPins.lua).
--
-- A player asked, the owner said build it (2026-10-18). A vendor gets a pin
-- when it sells a material the queue still needs (the shopping list's
-- shortfall) and it's cheaper there than on the auction house, or nobody
-- lists it there. "Vendor Map Pins" on the Mail & Vendors page
-- (`vendorMapPins`, off unless ticked, never rename it) and /bts vendorpins.
--
-- Where vendors stand: Classic's, shipped in Data/VendorSpots.lua (vendors
-- that never run out), and every vendor the player opens, learned from its
-- window (VendorPins:Learn, from Vendor:Scan) and kept account wide in
-- `vendorSpots[npc ID] = { name, mapID, x, y, side, items, at }` (never
-- rename it). A learned vendor takes the place of the shipped one, so a
-- Forever vendor that moved, or one Forever added, shows where it is now.
-- Learn next's Show the way reads the same spots (VendorPins:SeenAt), so a
-- vendor that sells only recipes is kept too, with no materials. Between
-- the two sits Data/ForeverVendorSpots.lua (the owner's spots, folded in at
-- a release by tools/forever_vendor_spots.py): what the game showed always
-- wins over Classic's spot (the owner, 2026-10-22). Trainers the same way:
-- each trainer window keeps where it stands (VendorPins:LearnTrainer) in
-- `trainerSpots[npc ID] = { name, mapID, x, y, side, at }` (never rename
-- it), over the shipped `ns.FOREVER_TRAINER_SPOTS`.
-- One whose stock runs out is pinned only while the auction house has
-- none (limited-stock items take the auction price when listed). Only
-- vendors of the player's side, or of neither.
--
-- Smooth play: the pins are worked out only while the world map shows,
-- and again only when the map, the queue, the bags, the prices or a
-- learned vendor moved (UI/VendorPins.lua keeps the key).

local _, ns = ...

local L = ns.L or setmetatable({ Format = string.format }, { __index = function(_, key) return key end })

local VendorPins = ns.NewModule("VendorPins")

-- Moves whenever a learned vendor changes, so the map draws again.
VendorPins.version = 0
-- At most this many learned vendors are kept; the oldest seen goes first.
VendorPins.MOST_VENDORS = 300
-- At most this many items a learned vendor.
VendorPins.MOST_ITEMS = 80
-- At most this many recipes a learned vendor.
VendorPins.MOST_RECIPES = 150

local function Plain(value)
    local ok, copy = pcall(function()
        if type(value) == "string" and value ~= "" then return value .. "" end
    end)
    return ok and copy or nil
end

local function Number(value)
    local ok, copy = pcall(function() return tonumber(value) end)
    return ok and copy or nil
end

local function Read(fn, ...)
    if type(fn) ~= "function" then return nil end
    local result = { pcall(fn, ...) }
    if not result[1] then return nil end
    return unpack(result, 2)
end

function VendorPins:IsOn()
    return ns.Config ~= nil and ns.Config:Get("vendorMapPins") == true
end

function VendorPins:SetOn(on)
    ns.Config:Set("vendorMapPins", on == true)
    self.version = self.version + 1
end

--- The learned vendors, account wide.
function VendorPins:Store()
    if not ns.db then return {} end
    if type(ns.db.vendorSpots) ~= "table" then ns.db.vendorSpots = {} end
    return ns.db.vendorSpots
end

--- The trainers learned, account wide.
function VendorPins:TrainerStore()
    if not ns.db then return {} end
    if type(ns.db.trainerSpots) ~= "table" then ns.db.trainerSpots = {} end
    return ns.db.trainerSpots
end

--- Every vendor (or, with kind "trainer", every trainer) the game has
--- shown: the shipped Forever spots (Data/ForeverVendorSpots.lua) with this
--- account's own over them.
--- { [npc ID] = { name, mapID, x, y, side, items } }, read only.
function VendorPins:Known(kind)
    local trainer = kind == "trainer"
    local known = {}
    for npcID, row in pairs((trainer and ns.FOREVER_TRAINER_SPOTS or ns.FOREVER_VENDOR_SPOTS) or {}) do
        if type(row) == "table" then
            known[npcID] = { name = row[1], mapID = row[2], x = row[3], y = row[4],
                side = row[5], items = type(row[6]) == "table" and row[6] or {},
                recipes = type(row[7]) == "table" and row[7] or nil, at = 0 }
        end
    end
    for npcID, record in pairs(trainer and self:TrainerStore() or self:Store()) do
        if type(record) == "table" then known[npcID] = record end
    end
    return known
end

--- "A", "H", or "" for a vendor of neither side.
function VendorPins.Side(faction)
    if faction == "Alliance" then return "A" end
    if faction == "Horde" then return "H" end
    return ""
end

--- The NPC ID inside a creature's GUID ("Creature-0-1-2-3-4-<id>-...").
function VendorPins.NpcID(guid)
    local ok, id = pcall(function()
        local kind, npc = guid:match("^(%a+)%-%d+%-%d+%-%d+%-%d+%-(%d+)")
        if kind == "Creature" or kind == "Vehicle" then return tonumber(npc) end
    end)
    return ok and id or nil
end

--- Where the player stands: the map ID and 0-100 on it.
local function PlayerSpot()
    local map = type(_G.C_Map) == "table" and _G.C_Map or nil
    if not map then return nil end
    local mapID = Number(Read(map.GetBestMapForUnit, "player"))
    if not mapID then return nil end
    local pos = Read(map.GetPlayerMapPosition, mapID, "player")
    if type(pos) ~= "table" and type(pos) ~= "userdata" then return nil end
    local ok, x, y = pcall(function() return pos:GetXY() end)
    x, y = ok and Number(x), ok and Number(y)
    if not (x and y) or (x == 0 and y == 0) then return nil end
    return mapID, math.floor(x * 1000 + 0.5) / 10, math.floor(y * 1000 + 0.5) / 10
end

--- The recipes a vendor window offers, cleaned for the save:
--- { [itemID] = { gold, costs = { { name, amount, currency, item } },
---   faction, standing } }, and a key that says whether they changed.
local function CleanRecipes(recipes)
    local kept, count, keys = {}, 0, {}
    if type(recipes) ~= "table" then return kept, "" end
    for itemID, offer in pairs(recipes) do
        if count >= VendorPins.MOST_RECIPES then break end
        if type(itemID) == "number" and type(offer) == "table" then
            local row = { gold = Number(offer.gold), faction = Plain(offer.faction),
                standing = Plain(offer.standing) }
            local key = { itemID, row.gold or 0, row.faction or "", row.standing or "" }
            for _, cost in ipairs(type(offer.costs) == "table" and offer.costs or {}) do
                local name, amount = Plain(cost.name), Number(cost.amount)
                if name and amount then
                    row.costs = row.costs or {}
                    row.costs[#row.costs + 1] = { name = name, amount = amount,
                        currency = Number(cost.currency), item = Number(cost.item) }
                    key[#key + 1] = name .. "=" .. amount
                end
            end
            kept[itemID] = row
            keys[#keys + 1] = table.concat(key, ":")
            count = count + 1
        end
    end
    table.sort(keys)
    return kept, table.concat(keys, ";")
end

local function RecipesKey(recipes)
    local _, key = CleanRecipes(recipes)
    return key
end

--- Kept from a vendor window: which items it sells for gold and where it
--- stands. Only materials (reagents and trade goods, or what the shipped
--- vendor prices know), so the save holds no gear or food lists, and the
--- recipes it sells whatever they cost (the trade camps' cost Merchant's
--- Favor), so a recipe can say where it's learned.
-- @param items    Vendor.merchantItems: { [itemID] = { price, numAvailable, extendedCost } }
-- @param recipes  optional, Vendor.merchantRecipes: { [itemID] = { gold, costs, faction, standing } }
-- @return true when kept
function VendorPins:Learn(items, recipes)
    if type(items) ~= "table" then return false end
    local npcID = self.NpcID(Read(_G.UnitGUID, "npc"))
    local name = Plain(Read(_G.UnitName, "npc"))
    if not (npcID and name) then return false end
    local mapID, x, y = PlayerSpot()
    if not mapID then return false end

    local sells, count, recipeVendor = {}, 0, false
    for itemID, item in pairs(items) do
        if count >= self.MOST_ITEMS then break end
        if type(item) == "table" and not item.extendedCost and (item.price or 0) > 0 then
            local material = ns.VENDOR_PRICES ~= nil and ns.VENDOR_PRICES[itemID] ~= nil
            if not material and type(_G.C_Item) == "table" then
                local classID = select(6, Read(_G.C_Item.GetItemInfoInstant, itemID))
                material = classID == 5 or classID == 7
                recipeVendor = recipeVendor or classID == 9
            end
            if material then
                sells[itemID] = (item.numAvailable or -1) < 0
                count = count + 1
            end
        end
    end
    local offers, offersKey = CleanRecipes(recipes)
    if next(offers) ~= nil then recipeVendor = true end
    -- A vendor of recipes alone is kept for where it stands (Show the way).
    if count == 0 and not recipeVendor then return false end

    local store = self:Store()
    local was = store[npcID]
    local side = self.Side(Plain(Read(_G.UnitFactionGroup, "npc")))
    store[npcID] = { name = name, mapID = mapID, x = x, y = y, side = side, items = sells, at = time(),
        recipes = next(offers) ~= nil and offers or nil }

    -- The same vendor read again (every buy scans it) is no news.
    local same = type(was) == "table" and was.mapID == mapID and was.side == side
        and math.abs((was.x or 0) - x) < 1 and math.abs((was.y or 0) - y) < 1
        and type(was.items) == "table" and RecipesKey(was.recipes) == offersKey
    if same then
        for itemID, unlimited in pairs(sells) do
            if was.items[itemID] ~= unlimited then same = false break end
        end
        for itemID in pairs(was.items) do
            if sells[itemID] == nil then same = false break end
        end
    end
    if not same then self.version = self.version + 1 end

    self:Trim(store)
    return true
end

--- Where the game saw a vendor (or, with kind "trainer", a trainer) stand,
--- by the name and zone the shipped data gives it: { mapID, x, y } from the
--- last time its window was opened, or nil. On the zone's own map when that
--- map is known, so a namesake elsewhere is never taken for it.
function VendorPins:SeenAt(name, zone, kind)
    if type(name) ~= "string" or name == "" then return nil end
    local want = name:lower()
    local zoneMap = zone and zone ~= "" and self:MapOf(zone) or nil
    local best
    for _, record in pairs(self:Known(kind)) do
        if type(record) == "table" and type(record.name) == "string" and record.name:lower() == want
            and record.mapID and record.x and record.y
            and (not zoneMap or record.mapID == zoneMap)
            and (not best or (record.at or 0) > (best.at or 0)) then
            best = record
        end
    end
    if not best then return nil end
    return { mapID = best.mapID, x = best.x, y = best.y }
end

--- The vendors the game showed selling a recipe item, of the player's side
--- (or neither): { { npcID, name, mapID, x, y, side, gold, costs, faction,
--- standing } }, the newest seen first. Read only.
function VendorPins:RecipeSellers(itemID)
    local sellers = {}
    if not itemID then return sellers end
    local mine = self.Side(Plain(Read(_G.UnitFactionGroup, "player")))
    if mine == "" then mine = nil end
    for npcID, record in pairs(self:Known()) do
        local offer = type(record) == "table" and type(record.recipes) == "table" and record.recipes[itemID]
        local side = record and record.side
        if type(offer) == "table" and record.mapID and record.x and record.y
            and (side == nil or side == "" or mine == nil or side == mine) then
            sellers[#sellers + 1] = {
                npcID = npcID, name = record.name, mapID = record.mapID, x = record.x, y = record.y,
                side = side, at = record.at or 0, gold = offer.gold, costs = offer.costs,
                faction = offer.faction, standing = offer.standing,
            }
        end
    end
    table.sort(sellers, function(a, b)
        if a.at ~= b.at then return a.at > b.at end
        return (a.npcID or 0) < (b.npcID or 0)
    end)
    return sellers
end

--- What a recipe costs at a vendor, in words: "50 Merchant's Favor", or
--- gold and the rest joined. The game's own name for a currency where it
--- gives one, so it reads in the player's language.
function VendorPins.CostText(offer)
    if type(offer) ~= "table" then return nil end
    local parts = {}
    if offer.gold and offer.gold > 0 and ns.Util and ns.Util.FormatMoney then
        parts[#parts + 1] = ns.Util.FormatMoney(offer.gold, { noColor = true })
    end
    for _, cost in ipairs(offer.costs or {}) do
        local name = cost.name
        local currencies = rawget(_G, "C_CurrencyInfo")
        if cost.currency and type(currencies) == "table" and type(currencies.GetCurrencyInfo) == "function" then
            local info = Read(currencies.GetCurrencyInfo, cost.currency)
            local ok, shown = pcall(function() return type(info) == "table" and info.name end)
            name = (ok and Plain(shown)) or name
        end
        if type(cost.amount) == "number" and type(name) == "string" and name ~= "" then
            parts[#parts + 1] = L.Format("%d %s", cost.amount, name)
        end
    end
    if #parts == 0 then return nil end
    return table.concat(parts, ", ")
end

--- Kept from a trainer window: where the trainer stands, so Show the way
--- goes where the game showed it rather than Classic's spot.
-- @return true when kept
function VendorPins:LearnTrainer()
    local npcID = self.NpcID(Read(_G.UnitGUID, "npc"))
    local name = Plain(Read(_G.UnitName, "npc"))
    if not (npcID and name) then return false end
    local mapID, x, y = PlayerSpot()
    if not mapID then return false end
    local store = self:TrainerStore()
    store[npcID] = { name = name, mapID = mapID, x = x, y = y,
        side = self.Side(Plain(Read(_G.UnitFactionGroup, "npc"))), at = time() }
    self:Trim(store)
    return true
end

function VendorPins:OnEnable()
    if ns.RegisterEvent then
        ns.RegisterEvent(self, "TRAINER_SHOW", function() VendorPins:LearnTrainer() end)
    end
end

--- Let the oldest seen go once there are more than MOST_VENDORS.
function VendorPins:Trim(store)
    local ids = {}
    for npcID, record in pairs(store) do
        ids[#ids + 1] = { npcID, type(record) == "table" and record.at or 0 }
    end
    if #ids <= self.MOST_VENDORS then return end
    table.sort(ids, function(a, b) return a[2] < b[2] end)
    for i = 1, #ids - self.MOST_VENDORS do store[ids[i][1]] = nil end
end

--- What the queue still needs that a vendor sells for less than the
--- auction house (or that nobody lists there):
--- { [itemID] = { need, vendor (copper each), auction (copper each or nil) } }
function VendorPins:Wanted()
    local wanted = {}
    if not (ns.Queue and ns.Queue.GetShoppingList) then return wanted end
    local ok, list = pcall(ns.Queue.GetShoppingList, ns.Queue)
    if not ok or type(list) ~= "table" then return wanted end
    for _, line in ipairs(list) do
        local vendor, auction = line.vendorUnit, line.auctionUnit
        local skip = ns.Cost and ns.Cost.SkipsVendor and auction and ns.Cost:SkipsVendor(line.itemID)
        if (line.shortfall or 0) > 0 and vendor and vendor > 0 and not skip
            and (not auction or vendor < auction) then
            wanted[line.itemID] = { need = line.shortfall, vendor = vendor, auction = auction }
        end
    end
    return wanted
end

--- A shipped zone's map ID: Classic's (Forever's match it), else the
--- client's by name. Kept once found.
function VendorPins:MapOf(zone)
    self.zoneMaps = self.zoneMaps or {}
    local known = self.zoneMaps[zone]
    if known ~= nil then return known or nil end
    local waypoints = ns.Waypoints
    local mapID = waypoints and waypoints.ZONE_MAPS and waypoints.ZONE_MAPS[zone]
    if not mapID and waypoints and waypoints.MapFor then mapID = waypoints:MapFor(zone) end
    -- Only a find is kept: on a loading screen the client knows no maps yet.
    if mapID then self.zoneMaps[zone] = mapID end
    return mapID
end

local function Allowed(side, mine)
    return side == nil or side == "" or mine == nil or side == mine
end

--- The vendors to pin on one map: { { npcID, name, mapID, x, y, items =
--- { { itemID, count, cost, saving } }, saving } }, the biggest saving first.
-- @param wanted  optional, VendorPins:Wanted()
function VendorPins:For(mapID, wanted)
    local vendors = {}
    if not mapID then return vendors end
    wanted = wanted or self:Wanted()
    if next(wanted) == nil then return vendors end

    local playerSide = Plain(Read(_G.UnitFactionGroup, "player"))
    local mine = playerSide and self.Side(playerSide) or nil
    if mine == "" then mine = nil end

    local function Add(npcID, name, x, y, sells, zone)
        local entry = { npcID = npcID, name = name, mapID = mapID, zone = zone, x = x, y = y,
            items = {}, saving = 0 }
        for _, itemID in ipairs(sells) do
            local want = wanted[itemID]
            local saving = want.auction and (want.auction - want.vendor) * want.need or nil
            entry.items[#entry.items + 1] = { itemID = itemID, count = want.need,
                cost = want.vendor * want.need, saving = saving }
            entry.saving = entry.saving + (saving or 0)
        end
        if #entry.items == 0 then return end
        table.sort(entry.items, function(a, b)
            if a.cost ~= b.cost then return a.cost > b.cost end
            return a.itemID < b.itemID
        end)
        vendors[#vendors + 1] = entry
    end

    local store = self:Known()
    for npcID, record in pairs(store) do
        if type(record) == "table" and record.mapID == mapID and record.x and record.y
            and Allowed(record.side, mine) and type(record.items) == "table" then
            local sells = {}
            for itemID, unlimited in pairs(record.items) do
                local want = wanted[itemID]
                if want and (unlimited or not want.auction) then sells[#sells + 1] = itemID end
            end
            table.sort(sells)
            Add(npcID, record.name, record.x, record.y, sells)
        end
    end

    local spots = ns.VENDOR_SPOTS
    if spots and spots.ITEMS and spots.NPCS then
        local byNpc = {}
        for itemID in pairs(wanted) do
            for _, npcID in ipairs(spots.ITEMS[itemID] or {}) do
                if store[npcID] == nil then
                    byNpc[npcID] = byNpc[npcID] or {}
                    table.insert(byNpc[npcID], itemID)
                end
            end
        end
        for npcID, sells in pairs(byNpc) do
            local npc = spots.NPCS[npcID]
            if npc and Allowed(npc[5], mine) and self:MapOf(npc[2]) == mapID then
                table.sort(sells)
                Add(npcID, npc[1], npc[3], npc[4], sells, npc[2])
            end
        end
    end

    table.sort(vendors, function(a, b)
        if a.saving ~= b.saving then return a.saving > b.saving end
        return a.npcID < b.npcID
    end)
    return vendors
end

local WHY = {
    nospot = L["no exact spot is known for them"],
    noclient = L["this client cannot put a pin on the map"],
    nomap = L["the map for that zone could not be found"],
}

--- The zone a vendor stands in, for the chat line: the client's name for
--- its map, else the shipped zone.
function VendorPins.ZoneName(vendor)
    local map = type(_G.C_Map) == "table" and _G.C_Map or nil
    local info = map and vendor.mapID and Read(map.GetMapInfo, vendor.mapID)
    if type(info) == "table" then
        local ok, name = pcall(function() return info.name end)
        name = ok and Plain(name)
        if name then return name end
    end
    return vendor.zone
end

--- What the vendor has for the queue, for the chat line: its first item.
local function WhatFor(vendor)
    local first = vendor.items and vendor.items[1]
    local util = ns.Util
    if not (first and util and util.GetItemLabel) then return vendor.name end
    local name = util.GetItemLabel(first.itemID)
    if util.Uncolored then name = util.Uncolored(name) end
    if type(name) == "string" and name ~= "" then return name end
    return vendor.name
end

--- Aim the arrow at a vendor, else put TomTom's arrow on it when TomTom is
--- installed, else (or when TomTom says no) the game's map pin, and say
--- which in chat. A click must never go by with nothing to show for it.
-- @return true, or false and why
function VendorPins:ShowTheWay(vendor)
    local waypoints = ns.Waypoints
    if not (waypoints and vendor) then return false, "nospot" end
    local place = { mapID = vendor.mapID, x = vendor.x, y = vendor.y }
    local who, what, zone = vendor.name or L["them"], WhatFor(vendor), VendorPins.ZoneName(vendor)
    -- Our own marker always goes on the map (the game's pin often won't).
    local marked = waypoints.Mark and waypoints:Mark(place, who) or false

    -- The arrow first (Logic/WayArrow.lua), as Show the way on the Level Up
    -- tab: TomTom's arrow takes over from it when "Use TomTom:" is ticked.
    local arrow = ns.WayArrow
    if arrow and arrow.AimAt then
        local aimed, took = pcall(arrow.AimAt, arrow, { mapID = vendor.mapID, zone = zone,
            x = vendor.x, y = vendor.y }, ("%s (%s)"):format(who, what))
        if aimed and took then
            self.pinned = vendor.npcID
            self.version = self.version + 1
            ns.Print(L.Format("The arrow shows the way to %s (%s).", who, what))
            return true
        end
    end

    local ok, why
    if waypoints:HasTomTom() then ok, why = waypoints:TomTom(place, vendor.name) end
    if not ok then
        ok, why = waypoints:Pin(place)
        -- With the game's pin on, the marker goes when the pin does.
        if ok and marked then waypoints:Mark(place, who, true) end
    end
    if not ok and marked then ok, why = true, nil end

    if ok then
        self.pinned = vendor.npcID
        self.version = self.version + 1
        ns.Print(L.Format("Pinned %s (%s) on your map, %s %s, %s.", who, what,
            zone or "?", vendor.x, vendor.y))
    elseif zone then
        ns.Print(L.Format("Can't pin %s (%s): %s. They are in %s.", who, what,
            WHY[why] or WHY.nospot, zone))
    else
        ns.Print(L.Format("Can't pin %s (%s): %s.", who, what, WHY[why] or WHY.nospot))
    end
    return ok == true, why
end

ns.RegisterCommand("vendorpins", L["Vendor Map Pins (on or off)"], function(args)
    local word = (args or ""):lower():match("^%s*(%a+)")
    local on
    if word == "on" then
        on = true
    elseif word == "off" then
        on = false
    else
        on = not VendorPins:IsOn()
    end
    VendorPins:SetOn(on)
    ns.Print(on and L["Vendor Map Pins: on."] or L["Vendor Map Pins: off."])
    if ns.UI and ns.UI.RefreshActiveTab then ns.UI:RefreshActiveTab() end
end)
