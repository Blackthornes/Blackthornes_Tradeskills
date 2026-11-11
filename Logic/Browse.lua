-- Blackthornes Tradeskills -- Logic/Browse.lua
-- The Browse tab of our own auction house window (UI/AuctionWindow.lua):
-- what the player asked for, the search that goes out, and the rows that
-- come back, each with its usual price from our own history.
--
-- Every search and every further page goes through ns.AHQueue, the one
-- queue the scans and the other tabs use, so browsing and scanning never
-- spend the game's allowance together. Nothing here buys or bids; that is
-- Logic/BrowseBuy.lua.
--
-- Not finished, so it does not ship yet: it sits inside the TOC's
-- do-not-package block with the window.

local _, ns = ...

local Browse = ns.NewModule("Browse")

local L = ns.L

-- The most rows one search keeps; a search for everything stops here.
Browse.MAX_ROWS = 500
-- Rows read a frame as an answer comes in.
Browse.READ_BUDGET = 150
-- How long a search waits for its first answer before it counts as empty.
Browse.ANSWER_WAIT = 10
-- How long names still loading are waited on before they are read again.
Browse.NAME_SETTLE = 0.3
Browse.MIN_LEVEL = 1
Browse.MAX_LEVEL = 60

-- Rarity choices, by the game's quality number, and their filter's name.
Browse.QUALITIES = {
    { quality = 0, filter = "PoorQuality" },
    { quality = 1, filter = "CommonQuality" },
    { quality = 2, filter = "UncommonQuality" },
    { quality = 3, filter = "RareQuality" },
    { quality = 4, filter = "EpicQuality" },
}

-- Every rarity the game can filter by, sent when none is picked but another
-- filter is.
Browse.EVERY_QUALITY = {
    "PoorQuality", "CommonQuality", "UncommonQuality", "RareQuality",
    "EpicQuality", "LegendaryQuality", "ArtifactQuality",
}

-- Item classes offered when the game's own category list can't be read.
local FALLBACK_CLASSES = { 2, 4, 1, 0, 7, 9, 12, 15 }

-- True from AUCTION_HOUSE_SHOW to AUCTION_HOUSE_CLOSED.
Browse.open = false
-- "idle" (nothing asked yet), "waiting" (queued), "searching" (sent, more
-- may come) or "done".
Browse.status = "idle"
Browse.rows = {}
-- Moves whenever the rows, the status or the query change what shows.
Browse.version = 0

local function NewQuery()
    return {
        text = "",
        minLevel = Browse.MIN_LEVEL,
        maxLevel = Browse.MAX_LEVEL,
        quality = nil,
        usable = false,
        dealsOnly = false,
        -- The picked category, as indexes down the category tree.
        path = nil,
    }
end

Browse.query = NewQuery()

local function After(seconds, fn)
    local timer = _G.C_Timer
    if timer and timer.After then timer.After(seconds, fn) else fn() end
end

local function Now()
    return type(_G.GetTime) == "function" and _G.GetTime() or 0
end

local function Api(name)
    local api = _G.C_AuctionHouse
    local fn = type(api) == "table" and api[name]
    return type(fn) == "function" and fn or nil
end

function Browse:Changed()
    self.version = self.version + 1
    self.shown = nil
    if type(self.onChange) == "function" then pcall(self.onChange) end
end

--------------------------------------------------------------------------------
-- Categories
--------------------------------------------------------------------------------

local function CleanFilters(filters)
    local out = {}
    if type(filters) ~= "table" then return out end
    for _, filter in ipairs(filters) do
        if type(filter) == "table" and type(filter.classID) == "number" then
            out[#out + 1] = {
                classID = filter.classID,
                subClassID = type(filter.subClassID) == "number" and filter.subClassID or nil,
                inventoryType = type(filter.inventoryType) == "number" and filter.inventoryType or nil,
            }
        end
    end
    return out
end

local function CleanCategory(category, depth)
    if type(category) ~= "table" or type(category.name) ~= "string" or category.name == "" then
        return nil
    end
    local node = { name = category.name, filters = CleanFilters(category.filters), children = {} }
    if depth < 3 and type(category.subCategories) == "table" then
        for _, child in ipairs(category.subCategories) do
            local kept = CleanCategory(child, depth + 1)
            if kept then node.children[#node.children + 1] = kept end
        end
    end
    -- A category that filters nothing (the game's token row) is left out.
    if #node.filters == 0 and #node.children == 0 then return nil end
    return node
end

local function ClassName(classID)
    local item = _G.C_Item
    local fn = (type(item) == "table" and item.GetItemClassInfo) or _G.GetItemClassInfo
    if type(fn) ~= "function" then return nil end
    local ok, name = pcall(fn, classID)
    if ok and type(name) == "string" and name ~= "" then return name end
    return nil
end

--- The category tree, the game's own names: { { name, filters, children } }.
function Browse:Categories()
    if self.categories and #self.categories > 0 then return self.categories end

    local tree = {}
    local ok, game = pcall(function() return _G.AuctionCategories end)
    if ok and type(game) == "table" then
        for _, category in ipairs(game) do
            local okNode, node = pcall(CleanCategory, category, 1)
            if okNode and node then tree[#tree + 1] = node end
        end
    end
    if #tree == 0 then
        for _, classID in ipairs(FALLBACK_CLASSES) do
            local name = ClassName(classID)
            if name then
                tree[#tree + 1] = { name = name, filters = { { classID = classID } }, children = {} }
            end
        end
    end

    self.categories = tree
    return tree
end

local function SamePath(a, b)
    if a == nil or b == nil then return a == b end
    if #a ~= #b then return false end
    for i = 1, #a do if a[i] ~= b[i] then return false end end
    return true
end

--- The picked category's node, or nil.
function Browse:Category()
    local path = self.query.path
    if not path then return nil end
    local nodes, node = self:Categories(), nil
    for _, index in ipairs(path) do
        node = nodes and nodes[index]
        if not node then return nil end
        nodes = node.children
    end
    return node
end

--- The category lines to draw: every top category, and under the picked
--- one's path its children. { { name, depth, path, selected } }
function Browse:CategoryLines()
    local lines = {}
    local picked = self.query.path

    local function Add(nodes, prefix, depth)
        for index, node in ipairs(nodes) do
            local path = {}
            for i = 1, #prefix do path[i] = prefix[i] end
            path[#path + 1] = index

            lines[#lines + 1] = {
                name = node.name, depth = depth, path = path,
                selected = SamePath(path, picked),
            }

            local onPath = picked ~= nil and #picked >= #path
            if onPath then
                for i = 1, #path do
                    if picked[i] ~= path[i] then onPath = false break end
                end
            end
            if onPath and #node.children > 0 then Add(node.children, path, depth + 1) end
        end
    end

    Add(self:Categories(), {}, 0)
    return lines
end

--- Pick a category; the picked one again steps back out of it.
function Browse:PickCategory(path)
    if SamePath(path, self.query.path) then
        local parent = {}
        for i = 1, #path - 1 do parent[i] = path[i] end
        self.query.path = #parent > 0 and parent or nil
    else
        self.query.path = path
    end
    self:Changed()
end

--------------------------------------------------------------------------------
-- The search
--------------------------------------------------------------------------------

--- The rarity choices this client can filter by: { { quality, name } }.
function Browse:Qualities()
    local out = {}
    local filters = type(_G.Enum) == "table" and _G.Enum.AuctionHouseFilter
    if type(filters) ~= "table" then return out end
    for _, choice in ipairs(self.QUALITIES) do
        if filters[choice.filter] ~= nil then
            local name = _G["ITEM_QUALITY" .. choice.quality .. "_DESC"]
            if type(name) == "string" and name ~= "" then
                out[#out + 1] = { quality = choice.quality, name = name }
            end
        end
    end
    return out
end

local function Level(value, fallback)
    value = tonumber(value)
    if not value then return fallback end
    value = math.floor(value)
    if value < Browse.MIN_LEVEL then return Browse.MIN_LEVEL end
    if value > Browse.MAX_LEVEL then return Browse.MAX_LEVEL end
    return value
end

--- What goes to the game for the query as it stands.
function Browse:BuildQuery()
    local query = self.query
    local low = Level(query.minLevel, self.MIN_LEVEL)
    local high = Level(query.maxLevel, self.MAX_LEVEL)
    if low > high then low, high = high, low end

    local filters = {}
    local enum = type(_G.Enum) == "table" and _G.Enum.AuctionHouseFilter
    if type(enum) == "table" then
        if query.quality ~= nil then
            for _, choice in ipairs(self.QUALITIES) do
                if choice.quality == query.quality and enum[choice.filter] ~= nil then
                    filters[#filters + 1] = enum[choice.filter]
                end
            end
        end
        if query.usable and enum.UsableOnly ~= nil then
            -- The game's own window sends every rarity it has ticked beside
            -- Usable Only. Sent with no rarity at all, gear matched none and
            -- Weapons and Armor came back empty, so every rarity goes too.
            if query.quality == nil then
                for _, name in ipairs(self.EVERY_QUALITY) do
                    if enum[name] ~= nil then filters[#filters + 1] = enum[name] end
                end
            end
            filters[#filters + 1] = enum.UsableOnly
        end
    end

    local category = self:Category()
    local classes = {}
    if category then
        for _, filter in ipairs(category.filters) do
            classes[#classes + 1] = {
                classID = filter.classID, subClassID = filter.subClassID,
                inventoryType = filter.inventoryType,
            }
        end
    end

    -- Every level asked for is no level filter at all.
    local whole = low == self.MIN_LEVEL and high == self.MAX_LEVEL
    return {
        searchString = type(query.text) == "string" and query.text or "",
        sorts = {},
        filters = filters,
        itemClassFilters = classes,
        minLevel = whole and 0 or low,
        maxLevel = whole and 0 or high,
    }
end

local function CancelQueued()
    local queue = ns.AHQueue
    if not queue then return end
    queue:Cancel("ui-browse", true)
    queue:Cancel("ui-browse-more", true)
end

local function Empty(self)
    self.rows = {}
    self.seen = 0
    self.pending = 0
    self.active = false
    self.answered = false
    self.reading = false
end

--- Send the search. It waits its turn in the shared queue.
-- @return true when it was queued
function Browse:Search()
    local queue = ns.AHQueue
    if not self.open or not queue or not Api("SendBrowseQuery") then return false end

    self.token = (self.token or 0) + 1
    local token = self.token

    CancelQueued()
    Empty(self)
    self.status = "waiting"
    self:Changed()

    local query = self:BuildQuery()
    queue:Request({
        name = "browse the auction house",
        key = "ui-browse",
        -- The player clicked Search and is watching for the answer.
        priority = queue.PRIORITY.urgent,
        expires = self.ANSWER_WAIT,

        send = function()
            if Browse.token ~= token or not Browse.open then return true end

            Browse.sending = true
            local ok = pcall(Api("SendBrowseQuery"), query)
            Browse.sending = false
            if not ok then return false end

            Browse.active = true
            Browse.status = "searching"
            Browse:Changed()

            -- No answer at all means nothing is listed for it.
            After(Browse.ANSWER_WAIT, function()
                if Browse.token == token and Browse.status == "searching" and not Browse.answered then
                    Browse:Finish()
                end
            end)
            return true
        end,

        onGiveUp = function()
            if Browse.token ~= token or Browse.status ~= "waiting" then return end
            Browse.status = "done"
            Browse:Changed()
            if not (queue.IsFlushing and queue:IsFlushing()) and ns.Warn then
                ns.Warn(L["the auction house stayed busy; that search was not sent."])
            end
        end,
    })
    return true
end

--- Back to an empty Browse tab with every filter as it starts.
function Browse:Clear()
    self.token = (self.token or 0) + 1
    CancelQueued()
    Empty(self)
    self.query = NewQuery()
    self.status = "idle"
    self:Changed()
end

--- The search has all it is going to get.
function Browse:Finish()
    self.active = false
    self.reading = false
    local queue = ns.AHQueue
    if queue then queue:Cancel("ui-browse-more", true) end
    if self.status ~= "idle" then self.status = "done" end
    self:Changed()
end

--- Someone else's search took the game's result list: keep what shows and
--- stop asking for more of ours.
function Browse:Replaced()
    if self.sending or not self.active then return end
    self:Finish()
end

--------------------------------------------------------------------------------
-- The rows
--------------------------------------------------------------------------------

local function Usual(itemID)
    local Prices = ns.Prices
    if not (Prices and Prices.GetValue) then return nil end
    local ok, value = pcall(Prices.GetValue, Prices, itemID)
    if ok and type(value) == "number" and value > 0 then return value end
    return nil
end

--- How far a price is from the usual one, in whole percent; nil unknown.
function Browse.Deal(price, usual)
    if type(price) ~= "number" or type(usual) ~= "number" or price <= 0 or usual <= 0 then
        return nil
    end
    local percent = (price - usual) / usual * 100
    if percent >= 0 then return math.floor(percent + 0.5) end
    return -math.floor(-percent + 0.5)
end

--- The Deal column's words: "-19%", "+6%", "Same", or "--" when unknown.
function Browse.DealText(deal)
    if type(deal) ~= "number" then return "--" end
    if deal == 0 then return L["Same"] end
    if deal > 0 then return ("+%d%%"):format(deal) end
    return ("%d%%"):format(deal)
end

-- Fill a row's name, rarity and icon from what the client has loaded.
-- @return true when the name is known
local function Name(row)
    local keyInfo = Api("GetItemKeyInfo")
    if keyInfo and row.itemKey then
        local ok, info = pcall(keyInfo, row.itemKey)
        if ok and type(info) == "table" and type(info.itemName) == "string" and info.itemName ~= "" then
            row.name = info.itemName
            if type(info.quality) == "number" then row.quality = info.quality end
            row.icon = info.iconFileID or row.icon
            return true
        end
    end

    local item = _G.C_Item
    if type(item) == "table" and type(item.GetItemInfo) == "function" then
        local ok, name, _, quality = pcall(item.GetItemInfo, row.itemID)
        if ok and type(name) == "string" and name ~= "" then
            row.name = name
            if type(quality) == "number" then row.quality = quality end
            return true
        end
    end
    return false
end

local function MakeRow(result)
    if type(result) ~= "table" then return nil end
    local key = result.itemKey
    local itemID = type(key) == "table" and key.itemID
    if type(itemID) ~= "number" or itemID <= 0 then return nil end

    local row = {
        itemID = itemID,
        itemKey = key,
        count = type(result.totalQuantity) == "number" and result.totalQuantity or 0,
        price = type(result.minPrice) == "number" and result.minPrice or 0,
        own = result.containsOwnerItem == true,
    }
    row.usual = Usual(itemID)
    row.deal = Browse.Deal(row.price, row.usual)

    if not Name(row) then
        row.pending = true
        local Util = ns.Util
        row.name = Util and Util.GetItemName and Util.GetItemName(itemID) or ("item %d"):format(itemID)
    end
    return row
end

--- Read the rows the game has for our search, a budget a frame.
function Browse:Read()
    if not self.active then self.reading = false return end

    local get = Api("GetBrowseResults")
    local ok, results = false, nil
    if get then ok, results = pcall(get) end
    if not ok or type(results) ~= "table" then self.reading = false return end

    -- A fresh answer (fewer rows than we read) starts the list again.
    if #results < (self.seen or 0) then
        self.rows, self.seen, self.pending = {}, 0, 0
    end

    local stop = math.min(#results, self.seen + self.READ_BUDGET)
    for index = self.seen + 1, stop do
        if #self.rows < self.MAX_ROWS then
            local okRow, row = pcall(MakeRow, results[index])
            if okRow and row then
                self.rows[#self.rows + 1] = row
                if row.pending then self.pending = self.pending + 1 end
            end
        end
    end
    self.seen = stop
    self.answered = true

    if #self.rows >= self.MAX_ROWS then
        self:Finish()
        return
    end

    if stop < #results then
        self:Changed()
        After(0, function() Browse:Read() end)
        return
    end

    self.reading = false

    local full = Api("HasFullBrowseResults")
    local okFull, whole = true, true
    if full then okFull, whole = pcall(full) end
    if not okFull or whole ~= false or not Api("RequestMoreBrowseResults") then
        self:Finish()
        return
    end

    self:Changed()
    self:AskForMore()
end

--- Queue the next page of our search, behind the player's own clicks.
function Browse:AskForMore()
    local queue = ns.AHQueue
    if not queue then self:Finish() return end

    local token = self.token
    queue:Request({
        name = "read more of the auction house list",
        key = "ui-browse-more",
        priority = queue.PRIORITY.normal,
        expires = 20,
        send = function()
            if Browse.token ~= token or not Browse.active then return true end
            local ok = pcall(Api("RequestMoreBrowseResults"))
            if not ok then return false end
            return true
        end,
        onGiveUp = function()
            if Browse.token == token and Browse.active then Browse:Finish() end
        end,
    })
end

function Browse:OnResults()
    if not self.active or self.reading then return end
    self.reading = true
    After(0, function() Browse:Read() end)
end

--- Names came in: fill the rows that waited for one.
function Browse:OnNames()
    if (self.pending or 0) <= 0 or self.naming then return end
    self.naming = true
    After(self.NAME_SETTLE, function()
        Browse.naming = false
        local left, moved = 0, false
        for _, row in ipairs(Browse.rows) do
            if row.pending then
                if Name(row) then
                    row.pending = nil
                    moved = true
                else
                    left = left + 1
                end
            end
        end
        Browse.pending = left
        if moved then Browse:Changed() end
    end)
end

--- The rows to show: Deals Only applied, by name A to Z.
function Browse:Shown()
    if self.shown then return self.shown end

    local out = {}
    local dealsOnly = self.query.dealsOnly
    for _, row in ipairs(self.rows) do
        if not dealsOnly or (row.deal ~= nil and row.deal < 0) then out[#out + 1] = row end
    end
    table.sort(out, function(a, b)
        local an, bn = (a.name or ""):lower(), (b.name or ""):lower()
        if an ~= bn then return an < bn end
        if a.price ~= b.price then return a.price < b.price end
        return a.itemID < b.itemID
    end)

    self.shown = out
    return out
end

--- Deals Only is worked out here, so it needs no new search.
function Browse:SetDealsOnly(on)
    self.query.dealsOnly = on and true or false
    self:Changed()
end

--------------------------------------------------------------------------------
-- The visit
--------------------------------------------------------------------------------

function Browse:Opened()
    self.open = true
    self.categories = nil
end

function Browse:Closed()
    self.open = false
    self.token = (self.token or 0) + 1
    CancelQueued()
    Empty(self)
    self.status = "idle"
    self:Changed()
end

function Browse:OnEnable()
    ns.RegisterEvent(self, "AUCTION_HOUSE_SHOW", function() Browse:Opened() end)
    ns.RegisterEvent(self, "AUCTION_HOUSE_CLOSED", function() Browse:Closed() end)
    ns.RegisterEvent(self, "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED", function() Browse:OnResults() end)
    ns.RegisterEvent(self, "AUCTION_HOUSE_BROWSE_RESULTS_ADDED", function() Browse:OnResults() end)
    ns.RegisterEvent(self, "ITEM_KEY_ITEM_INFO_RECEIVED", function() Browse:OnNames() end)
    ns.RegisterEvent(self, "GET_ITEM_INFO_RECEIVED", function() Browse:OnNames() end)

    -- Any search that is not ours replaces the list ours was reading.
    local api = _G.C_AuctionHouse
    if not self.hooked and type(api) == "table" and type(api.SendBrowseQuery) == "function"
        and type(_G.hooksecurefunc) == "function" then
        self.hooked = pcall(_G.hooksecurefunc, api, "SendBrowseQuery", function()
            Browse:Replaced()
        end)
    end
end
