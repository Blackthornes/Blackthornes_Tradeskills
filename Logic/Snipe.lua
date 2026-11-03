-- Blackthornes Tradeskills -- Logic/Snipe.lua
-- The auction house drawer's Snipe tab (the owner approved the mockup and
-- its words, 2026-11-03). While a session runs it asks the auction house for
-- the cheapest listings of items worth sniping, a few items at a time, and
-- keeps the ones priced well under what they are worth. Nothing starts by
-- itself: Start is a click, Stop (or the auction house closing, or the
-- Spending Cap) ends it and clears the list.
--
-- Two ways to watch:
--   "priced"  every item with a price of ours, against that price.
--   "disenchant"  green or better gear the character (or the disenchanter
--                 picked on the Mail page) can break, against what the
--                 materials sell for after the cut.
-- A find is a deal when its price is at or under worth * Snipe Below.
--
-- Gentle by design: one small search at a time at scan priority (AHQueue
-- holds it while the player sells or buys), the cheapest page only, and the
-- next one only after the last answered. Buying is one click a listing; a
-- big one asks for a second click (Click Again). Nothing here touches a
-- Blizzard frame.

local _, ns = ...

local L = ns.L or setmetatable({ Format = string.format }, { __index = function(_, key) return key end })

local Snipe = ns.NewModule("Snipe")

local Util = ns.Util

-- Item keys in one search, and the pause between searches.
Snipe.BATCH = 10
Snipe.REST = 1.5
-- Nothing below this worth (copper) is watched.
Snipe.MIN_WORTH = 5000
-- A buy at or over this asks twice.
Snipe.CONFIRM_OVER = 100000
Snipe.CONFIRM_FOR = 5
-- Waits, in seconds.
Snipe.REPLY_WAIT = 12
Snipe.QUOTE_WAIT = 10
Snipe.BUY_WAIT = 15
-- Most of a stack bought in one click.
Snipe.MOST_UNITS = 20
-- An average more than this many times the last scan's cheapest is left out.
Snipe.SILLY_OVER = 10
-- A scan stamp is when the scan started; records seen a little before count.
Snipe.SCAN_SLACK = 3600
-- Pool building: items looked at a frame.
Snipe.SLICE = 300

Snipe.SOUND = [[Interface\AddOns\]] .. (ns.ADDON_NAME or "Blackthornes_TS") .. [[\Media\Sounds\snipe-bell-single.ogg]]

Snipe.running = false
Snipe.spent = 0
Snipe.finds = {}
Snipe.version = 0
Snipe.pending = nil
Snipe.armed = nil

local pool, cursor, waiting, building, session = {}, 1, nil, false, 0

local function Now() return (GetTime and GetTime()) or 0 end

local function After(seconds, fn)
    if C_Timer and C_Timer.After then C_Timer.After(seconds, fn) else fn() end
end

local function Moved()
    Snipe.version = Snipe.version + 1
    if ns.SnipeView and ns.SnipeView.Changed then pcall(ns.SnipeView.Changed, ns.SnipeView) end
end

local function Get(key, default)
    local ok, value = pcall(function() return ns.Config:Get(key) end)
    if ok and value ~= nil then return value end
    return default
end

--- What the player set: Spending Cap (copper), Snipe Below (percent).
function Snipe:Cap() return tonumber(Get("snipeCap", 0)) or 0 end
function Snipe:Percent()
    local pct = tonumber(Get("snipePct", 70)) or 70
    return math.max(10, math.min(95, pct))
end
function Snipe:Watch() return Get("snipeWatch", "priced") == "disenchant" and "disenchant" or "priced" end
function Snipe:Enabled() return Get("snipeTab", false) == true end

function Snipe:IsRunning() return self.running end
function Snipe:Spent() return self.spent end
function Snipe:Finds() return self.finds end

--- Remaining under the cap.
function Snipe:Left() return math.max(0, self:Cap() - self.spent) end

local function Say(text)
    if ns.Notice and ns.Notice.Show then
        local ok = pcall(ns.Notice.Show, ns.Notice, text, { hold = 5, key = "snipe" })
        if ok then return end
    end
    ns.Print(text)
end

--------------------------------------------------------------------------
-- What an item is worth, and who may be watched
--------------------------------------------------------------------------

local function ItemClass(itemID)
    if not (C_Item and C_Item.GetItemInfoInstant) then return nil end
    local ok, _, _, _, _, _, classID = pcall(C_Item.GetItemInfoInstant, itemID)
    if ok then return classID end
end

local function Quality(itemID)
    if not (C_Item and C_Item.GetItemQualityByID) then return nil end
    local ok, quality = pcall(C_Item.GetItemQualityByID, itemID)
    if ok then return quality end
end

local function CanBreak()
    local d = ns.Disenchanter
    if d and d.Knows then
        local ok, knows = pcall(d.Knows, d)
        if ok and knows then return true end
    end
    local mail = ns.QueueMail
    if mail and mail.GetDisenchanter then
        local ok, name = pcall(mail.GetDisenchanter, mail)
        if ok and name and name ~= "" then return true end
    end
    return false
end

local function AfterCut(copper)
    if ns.Profit and ns.Profit.NetFromListing then
        local ok, net = pcall(ns.Profit.NetFromListing, ns.Profit, 0, copper)
        if ok and type(net) == "number" and net > 0 then return net end
    end
    local cut = tonumber(Get("auctionCut", 0.05)) or 0.05
    return math.floor(copper * (1 - cut))
end

--- Worth of one unit, or nil when it is not watched. kind: priced, disenchant.
function Snipe:WorthOf(itemID, mode)
    mode = mode or self:Watch()
    if mode == "disenchant" then
        local class = ItemClass(itemID)
        if class ~= 2 and class ~= 4 then return nil end
        local quality = Quality(itemID)
        if not quality or quality < 2 then return nil end
        if not (ns.Disenchant and ns.Disenchant.IsDisenchantable) then return nil end
        local ok, can = pcall(ns.Disenchant.IsDisenchantable, ns.Disenchant, itemID)
        if not (ok and can == true) then return nil end
        local okv, value = pcall(ns.Disenchant.GetValue, ns.Disenchant, itemID)
        if not (okv and type(value) == "number" and value > 0) then return nil end
        return AfterCut(value)
    end
    if not (ns.Prices and ns.Prices.GetValue) then return nil end
    -- Greys are worth their vendor price only, never a snipe.
    if Quality(itemID) == 0 then return nil end
    local ok, value = pcall(ns.Prices.GetValue, ns.Prices, itemID)
    if not (ok and type(value) == "number") then return nil end
    if value < self.MIN_WORTH then return nil end
    if ns.Prices.IsCredible and not ns.Prices.IsCredible(value) then return nil end
    -- A silly average (68,000g for a grey) made every listing look 100%
    -- under. One far above the cheapest listing the last scan saw is left out.
    local low = Snipe.LastLow(itemID)
    if low and value > low * self.SILLY_OVER then return nil end
    return value
end

--- The cheapest listing the last scan saw, or nil.
function Snipe.LastLow(itemID)
    local record = ns.Prices and ns.Prices.Get and ns.Prices:Get(itemID)
    if type(record) ~= "table" then return nil end
    local low = ns.Prices.LowestListed and ns.Prices.LowestListed(record) or record.min
    if type(low) == "number" and low > 0 then return low end
end

--- Was it for sale in the last scan?
function Snipe.InLastScan(itemID, since)
    local record = ns.Prices and ns.Prices.Get and ns.Prices:Get(itemID)
    if type(record) ~= "table" or (record.quantity or 0) <= 0 then return false end
    if since and (record.seen or 0) < since then return false end
    return true
end

--- Is this price a deal against its worth?
function Snipe.IsDeal(price, worth, percent)
    if type(price) ~= "number" or type(worth) ~= "number" or worth <= 0 then return false end
    return price <= worth * (percent or 70) / 100
end

--- Percent under worth, for sorting and showing.
function Snipe.Deal(price, worth)
    if not worth or worth <= 0 then return 0 end
    return math.floor((1 - price / worth) * 100 + 0.5)
end

--------------------------------------------------------------------------
-- The pool: what a session looks at, laid out a slice a frame
--------------------------------------------------------------------------

function Snipe:BuildPool(done)
    local mine = session
    local mode = self:Watch()
    local ids = {}
    local table_ = ns.Prices and ns.Prices.GetTable and ns.Prices:GetTable() or {}
    for id in pairs(table_) do
        if type(id) == "number" then ids[#ids + 1] = id end
    end
    table.sort(ids)
    pool, cursor, building = {}, 1, true
    if mode == "disenchant" and not CanBreak() then
        building = false
        return done()
    end
    local lastScan = ns.Prices and ns.Prices.GetLastScan and ns.Prices:GetLastScan()
    local since = lastScan and (lastScan - self.SCAN_SLACK) or nil
    local at = 1
    local function Step()
        if mine ~= session or not self.running then return end
        local last = math.min(#ids, at + self.SLICE - 1)
        for i = at, last do
            local worth = self:WorthOf(ids[i], mode)
            if worth then
                pool[#pool + 1] = { id = ids[i], worth = worth, listed = Snipe.InLastScan(ids[i], since) }
            end
        end
        at = last + 1
        if at > #ids then
            building = false
            Snipe.OrderPool(pool)
            return done()
        end
        After(0, Step)
    end
    Step()
end

--- What was for sale in the last scan first, most valuable first.
function Snipe.OrderPool(list)
    table.sort(list, function(a, b)
        if (a.listed and true or false) ~= (b.listed and true or false) then return a.listed and true or false end
        if a.worth ~= b.worth then return a.worth > b.worth end
        return a.id < b.id
    end)
    return list
end

--------------------------------------------------------------------------
-- Start and Stop
--------------------------------------------------------------------------

local function AuctionOpen()
    if AuctionHouseFrame and AuctionHouseFrame.IsShown then
        local ok, shown = pcall(AuctionHouseFrame.IsShown, AuctionHouseFrame)
        return ok and shown and true or false
    end
    return true
end

function Snipe:Start()
    if self.running then return end
    if self:Cap() <= 0 then
        Say(L["Set a Spending Cap first."])
        return
    end
    if not AuctionOpen() then return end
    session = session + 1
    self.running, self.spent, self.finds = true, 0, {}
    self.dinged = {}
    self.pending, self.armed, waiting = nil, nil, nil
    Moved()
    self:BuildPool(function() Snipe:Next() end)
end

function Snipe:Stop(reason)
    if not self.running then return end
    session = session + 1
    self.running = false
    self.finds, self.pending, self.armed, waiting = {}, nil, nil, nil
    pool, building = {}, false
    if ns.AHQueue and ns.AHQueue.Cancel then pcall(ns.AHQueue.Cancel, ns.AHQueue, "snipe") end
    if reason then Say(reason) end
    Moved()
end

function Snipe:CapReached()
    self:Stop(L["You've reached your Spending Cap. Snipe stopped."])
end

--------------------------------------------------------------------------
-- Searching, one small batch at a time
--------------------------------------------------------------------------

local function Busy()
    if Snipe.pending then return true end
    if ns.AHQueue and ns.AHQueue.PlayerIsSelling then
        local ok, selling = pcall(ns.AHQueue.PlayerIsSelling, ns.AHQueue)
        if ok and selling then return true end
    end
    return false
end

function Snipe:Next()
    if not self.running or waiting or building then return end
    if #pool == 0 then
        -- Nothing to watch: say so once and stop.
        self:Stop(L["Nothing to snipe yet. Scan the auction house first."])
        return
    end
    if cursor > #pool then cursor = 1 end
    if Busy() then
        After(self.REST * 2, function() Snipe:Next() end)
        return
    end
    if not (Util.HasFunction("C_AuctionHouse.MakeItemKey") and ns.AHQueue and ns.AHQueue.Request) then return end

    local batch, keys = {}, {}
    local last = math.min(#pool, cursor + self.BATCH - 1)
    for i = cursor, last do
        local row = pool[i]
        local ok, key = pcall(C_AuctionHouse.MakeItemKey, row.id)
        if ok and key then
            keys[#keys + 1] = key
            batch[row.id] = row.worth
        end
    end
    cursor = last + 1
    if #keys == 0 then return After(self.REST, function() Snipe:Next() end) end

    local mine = { batch = batch, at = Now() }
    waiting = mine
    local mineSession = session
    ns.AHQueue:Request({
        name = "snipe",
        key = "snipe",
        priority = ns.AHQueue.PRIORITY and ns.AHQueue.PRIORITY.scan or 90,
        expires = self.REPLY_WAIT,
        send = function()
            if mineSession ~= session or not Snipe.running then return false end
            local ok = pcall(C_AuctionHouse.SearchForItemKeys, keys, {})
            if ok then mine.sent = Now() end
            return ok
        end,
        onGiveUp = function()
            if waiting == mine then waiting = nil; Snipe:Later() end
        end,
    })
    After(self.REPLY_WAIT + 3, function()
        if waiting == mine then waiting = nil; Snipe:Later() end
    end)
end

function Snipe:Later()
    local mineSession = session
    After(self.REST, function()
        if mineSession == session then Snipe:Next() end
    end)
end

--- Are these rows our own search's? A search the player made (or another
--- addon made) lists items outside our batch; those rows are left alone, so
--- a find is never dropped and found again because of them.
function Snipe.OwnResults(rows, batch)
    if type(batch) ~= "table" then return false end
    for _, row in ipairs(rows) do
        local id = row.itemKey and row.itemKey.itemID
        if not (id and batch[id]) then return false end
    end
    return true
end

--- The scanner's browse hook: the rows of our search are ready.
function Snipe:OnBrowseResults()
    local mine = waiting
    if not (self.running and mine and mine.sent) then return end
    if not (C_AuctionHouse and C_AuctionHouse.GetBrowseResults) then return end
    local ok, rows = pcall(C_AuctionHouse.GetBrowseResults)
    if not (ok and type(rows) == "table") then return end
    if not Snipe.OwnResults(rows, mine.batch) then return end

    local cheapest = {}
    for _, row in ipairs(rows) do
        local key = row.itemKey
        local id = key and key.itemID
        if id and mine.batch[id] and (key.itemSuffix or 0) == 0 then
            local price = ns.Posting and ns.Posting.RivalFromRow
                and ns.Posting.RivalFromRow(id, row.minPrice, row.containsOwnerItem)
                or row.minPrice
            if type(price) == "number" and price > 0
                and not (ns.Prices and ns.Prices.IsCredible and not ns.Prices.IsCredible(price)) then
                local have = cheapest[id]
                if not have or price < have.price then
                    cheapest[id] = { price = price, qty = row.totalQuantity or 1 }
                end
            end
        end
    end

    waiting = nil
    local pct = self:Percent()
    local kind = self:Watch()
    local kept, fresh = {}, false
    for _, find in ipairs(self.finds) do
        if not mine.batch[find.itemID] then kept[#kept + 1] = find end
    end
    for id, hit in pairs(cheapest) do
        local worth = mine.batch[id]
        if Snipe.IsDeal(hit.price, worth, pct) then
            kept[#kept + 1] = {
                itemID = id, price = hit.price, qty = hit.qty, worth = worth,
                deal = Snipe.Deal(hit.price, worth), kind = kind,
            }
            -- One ding a new item, and again only when it gets cheaper.
            local rang = self.dinged and self.dinged[id]
            if not rang or hit.price < rang then
                fresh = true
                if self.dinged then self.dinged[id] = hit.price end
            end
        end
    end
    table.sort(kept, function(a, b)
        if a.deal ~= b.deal then return a.deal > b.deal end
        return a.itemID < b.itemID
    end)
    self.finds = kept
    if fresh then self:Chime() end
    Moved()
    self:Later()
end

function Snipe:Chime()
    if Get("snipeSound", true) ~= true then return end
    if InCombatLockdown and InCombatLockdown() then return end
    if PlaySoundFile then pcall(PlaySoundFile, self.SOUND, "Master") end
end

--------------------------------------------------------------------------
-- Buying: one listing a click
--------------------------------------------------------------------------

local function Drop(itemID)
    local kept = {}
    for _, find in ipairs(Snipe.finds) do
        if find.itemID ~= itemID then kept[#kept + 1] = find end
    end
    Snipe.finds = kept
end

local function IsStack(itemID)
    if not Util.HasFunction("C_AuctionHouse.GetItemCommodityStatus") then return false end
    local ok, status = pcall(function()
        local value = C_AuctionHouse.GetItemCommodityStatus(itemID)
        if type(value) == "number" then return value end
        local enum = rawget(_G, "Enum") and Enum.ItemCommodityStatus
        if enum and value == enum.Item then return 1 end
        return nil
    end)
    -- 1 is an item sold one at a time; anything else the game says is a stack.
    return ok and status ~= nil and status ~= 1
end

--- Units to ask for: the listing, the cap and the most-at-once allow.
function Snipe:UnitsFor(find)
    local left = self:Left()
    local units = math.min(find.qty or 1, self.MOST_UNITS)
    if find.price > 0 then units = math.min(units, math.floor(left / find.price)) end
    return math.max(0, units)
end

function Snipe:Buy(find)
    if not (self.running and find) or self.pending then return end
    local units = self:UnitsFor(find)
    if units < 1 then return self:CapReached() end

    if find.kind == "disenchant" and ns.DisenchantBuys and ns.DisenchantBuys.Intend then
        pcall(ns.DisenchantBuys.Intend, ns.DisenchantBuys, find.itemID)
    end

    if not IsStack(find.itemID) then
        -- Sold one at a time: the game's own search, the player buys there.
        if ns.UI and ns.UI.SearchAuctionHouse then ns.UI:SearchAuctionHouse(find.itemID, 1) end
        return
    end
    if not Util.HasFunction("C_AuctionHouse.StartCommoditiesPurchase") then return end
    local ok = pcall(C_AuctionHouse.StartCommoditiesPurchase, find.itemID, units)
    if not ok then return end
    local mine = { itemID = find.itemID, count = units, phase = "asking", find = find }
    self.pending = mine
    Moved()
    After(self.QUOTE_WAIT, function()
        if Snipe.pending == mine and mine.phase == "asking" then Snipe:CancelBuy() end
    end)
end

function Snipe:CancelBuy()
    local pending = self.pending
    self.pending, self.armed = nil, nil
    if pending and Util.HasFunction("C_AuctionHouse.CancelCommoditiesPurchase") then
        pcall(C_AuctionHouse.CancelCommoditiesPurchase)
    end
    Moved()
end

--- The game answered with the real total.
function Snipe:PriceUpdated(total)
    local pending = self.pending
    if not (pending and pending.phase == "asking") then return end
    if type(total) ~= "number" or total <= 0 then return self:CancelBuy() end
    -- The real price must still be a deal; if not, let it go.
    local each = total / pending.count
    if not Snipe.IsDeal(each, pending.find.worth, self:Percent()) or total > self:Left() then
        Drop(pending.itemID)
        return self:CancelBuy()
    end
    pending.phase, pending.total = "quoted", total
    Moved()
end

--- Pay: spend the quoted total. A big one needs a second click.
function Snipe:Pay()
    local pending = self.pending
    if not (pending and pending.phase == "quoted") then return false end
    if type(GetMoney) == "function" then
        local ok, money = pcall(GetMoney)
        if ok and type(money) == "number" and money < pending.total then
            ns.Print(L.Format("You need %s for that.", Util.FormatMoney(pending.total, { noColor = true })))
            return false
        end
    end
    if pending.total >= self.CONFIRM_OVER and self.armed ~= pending then
        self.armed = pending
        Moved()
        After(self.CONFIRM_FOR, function()
            if Snipe.armed == pending then Snipe.armed = nil; Moved() end
        end)
        return "confirm"
    end
    local ok = Util.HasFunction("C_AuctionHouse.ConfirmCommoditiesPurchase")
        and pcall(C_AuctionHouse.ConfirmCommoditiesPurchase, pending.itemID, pending.count)
    if not ok then self:CancelBuy(); return false end
    pending.phase, self.armed = "buying", nil
    Moved()
    After(self.BUY_WAIT, function()
        if Snipe.pending == pending and pending.phase == "buying" then
            Snipe.pending = nil
            Moved()
        end
    end)
    return true
end

function Snipe:Bought()
    local pending = self.pending
    if not pending then return end
    self.pending, self.armed = nil, nil
    self.spent = self.spent + (pending.total or 0)
    Drop(pending.itemID)
    if ns.AHBuys and ns.AHBuys.Record then pcall(ns.AHBuys.Record, ns.AHBuys, pending.itemID, pending.count) end
    Moved()
    if self.running and self:Left() <= 0 then self:CapReached() end
end

--- The wheel (or any one-click caller): buy the best find, or pay a quote.
function Snipe:BuyNext()
    if not self.running then return end
    if self.pending then
        if self.pending.phase == "quoted" then return self:Pay() end
        return
    end
    local best = self.finds[1]
    if best then self:Buy(best) end
end

--------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------

function Snipe:Init()
    ns.RegisterEvent(self, "COMMODITY_PRICE_UPDATED", function(_, _, _, total) Snipe:PriceUpdated(total) end)
    ns.RegisterEvent(self, "COMMODITY_PRICE_UNAVAILABLE", function() Snipe:CancelBuy() end)
    ns.RegisterEvent(self, "COMMODITY_PURCHASE_SUCCEEDED", function() Snipe:Bought() end)
    ns.RegisterEvent(self, "COMMODITY_PURCHASE_FAILED", function() Snipe:CancelBuy() end)
    ns.RegisterEvent(self, "AUCTION_HOUSE_CLOSED", function() Snipe:Stop() end)
end
