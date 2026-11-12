-- Blackthornes Tradeskills -- Logic/ListSets.lua
-- Buy Sets (a player asked, the owner approved the mockup and its words,
-- 2026-11-12): a shopping list's want amounts are a ratio, 2 of this to 1 of
-- that, and Buy Sets buys as many whole sets as fit under the gold the
-- player typed in "Spend Up To:".
--
-- How it goes:
--   1. Start reads each item's listings on the auction house, one item at a
--      time, through the AH queue (cheapest first).
--   2. Fit works out the sets: listings over a row's Most I'll Pay (its own,
--      else the list rule's) and the player's own listings don't count, and
--      when one item runs short every row drops to match it.
--   3. Each row is then bought with two clicks, as Snipe buys a stack: Buy
--      asks the game for the real price, Confirm pays it. If the real price
--      would take the run past what the player set to spend, the run stops
--      and says so, and nothing is paid.
-- Nothing is bought without a click. Stop, or the auction house closing,
-- ends the run. Nothing is saved: the run lives in memory only.

local _, ns = ...
local L = ns.L or setmetatable({ Format = string.format }, { __index = function(_, key) return key end })

local ListSets = ns.NewModule("ListSets")
local Util = ns.Util

ListSets.QUOTE_WAIT = 10   -- seconds to wait for the game's price
ListSets.BUY_WAIT = 15     -- seconds to wait for a buy to go through
ListSets.READ_WAIT = 13    -- seconds to wait for one item's listings

ListSets.run = nil
ListSets.version = 0

local function Lists() return ns.ShoppingLists end

local function After(seconds, fn)
    if C_Timer and C_Timer.After then C_Timer.After(seconds, fn) else fn() end
end

local function Changed()
    ListSets.version = ListSets.version + 1
    local view = ns.ShoppingListsView
    if view and view.Refresh then pcall(view.Refresh, view, true) end
end

local function Say(text)
    if ns.Notice and ns.Notice.Show then
        local ok = pcall(ns.Notice.Show, ns.Notice, text, { hold = 5, key = "listsets" })
        if ok then return end
    end
    if ns.Print then ns.Print(text) end
end

--------------------------------------------------------------------------
-- The math
--------------------------------------------------------------------------

--- What the cheapest `units` of an item cost, read off its listings. Units
--- past what is listed cost the last price seen (for working out whether
--- supply or gold holds a run back), or nil when nothing is listed.
local function CostOf(rows, units, stretch)
    local cost, left, last = 0, units, nil
    for _, row in ipairs(rows) do
        if left <= 0 then break end
        local take = math.min(left, row.quantity)
        cost, left, last = cost + take * row.unitPrice, left - take, row.unitPrice
    end
    if left > 0 then
        if not stretch or not last then return nil end
        cost = cost + left * last
    end
    return cost
end

--- The listings that count for an item: at or under its Most I'll Pay, the
--- player's own left out, cheapest first.
function ListSets.Usable(listings, maxPay)
    local rows, avail = {}, 0
    for _, row in ipairs(type(listings) == "table" and listings or {}) do
        local price = tonumber(row.unitPrice)
        local qty = math.max(0, (tonumber(row.quantity) or 0) - (tonumber(row.own) or 0))
        if price and price > 0 and qty > 0 and not (maxPay and maxPay > 0 and price > maxPay) then
            rows[#rows + 1] = { unitPrice = price, quantity = qty }
            avail = avail + qty
        end
    end
    table.sort(rows, function(a, b) return a.unitPrice < b.unitPrice end)
    return rows, avail
end

--- How many whole sets fit, and what each row buys.
-- @param items { { itemID, ratio, maxPay }, ... }
-- @param listings { [itemID] = { { unitPrice, quantity, own }, ... } }
-- @param limit copper the player set to spend
-- @return { sets, total, rows = { { itemID, ratio, buy, cost, avail, short } } }
function ListSets.Fit(items, listings, limit)
    limit = math.max(0, math.floor(tonumber(limit) or 0))
    local usable, rows = {}, {}
    local cap = math.huge
    for i, item in ipairs(items or {}) do
        local ratio = math.max(1, math.floor(tonumber(item.ratio) or 1))
        local got, avail = ListSets.Usable((listings or {})[item.itemID], item.maxPay)
        usable[i] = got
        rows[i] = { itemID = item.itemID, ratio = ratio, buy = 0, cost = 0, avail = avail, short = false }
        cap = math.min(cap, math.floor(avail / ratio))
    end
    if #rows == 0 then return { sets = 0, total = 0, rows = rows } end

    local function Cost(n, stretch)
        local total = 0
        for i, row in ipairs(rows) do
            local cost = CostOf(usable[i], row.ratio * n, stretch)
            if not cost then return nil end
            total = total + cost
        end
        return total
    end

    -- The most sets the gold covers: cost only grows with n, so halve.
    local function Most(top, stretch)
        local low, high = 0, top
        while low < high do
            local mid = math.floor((low + high + 1) / 2)
            local cost = Cost(mid, stretch)
            if cost and cost <= limit then low = mid else high = mid - 1 end
        end
        return low
    end

    local sets = Most(cap, false)
    -- An item holds the run back when the gold would buy more sets than it
    -- has up. Gold for a set past what is listed is worked out at the last
    -- price seen; an item with nothing up is short whenever there is gold.
    local cheapest = 0
    for i in ipairs(rows) do
        local first = usable[i][1]
        cheapest = cheapest + (first and first.unitPrice or 0) * rows[i].ratio
    end
    local reach = cheapest > 0 and math.floor(limit / cheapest) or 0
    local byGold = sets
    if sets == cap and reach > cap then
        local stretched = true
        for i in ipairs(rows) do if not usable[i][1] then stretched = false end end
        byGold = stretched and Most(reach, true) or (limit > 0 and cap + 1 or cap)
    end
    local total = 0
    for i, row in ipairs(rows) do
        row.buy = row.ratio * sets
        row.cost = CostOf(usable[i], row.buy, false) or 0
        total = total + row.cost
        row.short = byGold > sets and math.floor(row.avail / row.ratio) == sets
    end
    return { sets = sets, total = total, rows = rows }
end

--------------------------------------------------------------------------
-- Reading the listings
--------------------------------------------------------------------------

local PRICE_SORT

local function PriceSort()
    if PRICE_SORT then return PRICE_SORT end
    local enum = rawget(_G, "Enum") and Enum.AuctionHouseSortOrder
    PRICE_SORT = { { sortOrder = enum and enum.Price or 0, reverseSort = false } }
    return PRICE_SORT
end

local function AuctionOpen()
    return ns.Scanner ~= nil and ns.Scanner.isAuctionHouseOpen == true
end

--- Sold one at a time (not a stack): Buy Sets can't buy it by the unit.
local function IsStack(itemID)
    if not Util.HasFunction("C_AuctionHouse.GetItemCommodityStatus") then return true end
    local ok, status = pcall(function()
        local value = C_AuctionHouse.GetItemCommodityStatus(itemID)
        if type(value) == "number" then return value end
        local enum = rawget(_G, "Enum") and Enum.ItemCommodityStatus
        if enum and value == enum.Item then return 1 end
        return nil
    end)
    return not (ok and status == 1)
end

local function ReadListings(itemID)
    local okN, count = pcall(C_AuctionHouse.GetNumCommoditySearchResults, itemID)
    if not (okN and type(count) == "number") then return nil end
    local out = {}
    for i = 1, count do
        local ok, row = pcall(C_AuctionHouse.GetCommoditySearchResultInfo, itemID, i)
        if ok and type(row) == "table" then
            local price = tonumber(row.unitPrice)
            if price and not (ns.Prices and ns.Prices.IsCredible and not ns.Prices.IsCredible(price)) then
                out[#out + 1] = { unitPrice = price, quantity = tonumber(row.quantity) or 0,
                    own = tonumber(row.numOwnerItems) or 0 }
            end
        end
    end
    return out
end

--- The items of a list as Fit wants them: the want amounts are the ratio.
function ListSets.ItemsOf(key)
    local items = {}
    if not Lists() then return items end
    local list = Lists():Get(key)
    if not list then return items end
    local rule
    if ns.ListRules and ns.ListRules.Of then
        local ok, rules = pcall(ns.ListRules.Of, list)
        rule = ok and type(rules) == "table" and tonumber(rules.maxPay) or nil
    end
    for _, line in ipairs(Lists():Lines(key)) do
        if line.itemID and (line.want or 0) > 0 then
            items[#items + 1] = { itemID = line.itemID, ratio = line.want,
                maxPay = line.maxPay or (rule and rule > 0 and rule or nil) }
        end
    end
    return items
end

function ListSets:RunFor(key)
    local run = self.run
    if run and run.key == key then return run end
end

--- Snipe is waiting on the game for a price or a buy: wait for it.
function ListSets:Busy()
    local p = ns.Snipe and ns.Snipe.pending
    return p ~= nil and (p.phase == "asking" or p.phase == "quoted" or p.phase == "buying"
        or p.phase == "listing")
end

--- Read the list's listings, then work out the sets.
function ListSets:Start(key, limit)
    limit = math.floor(tonumber(limit) or 0)
    if limit <= 0 then return end
    if not AuctionOpen() then
        Say(L["Open the auction house first, then search again."])
        return
    end
    local q = ns.AHQueue
    if not (q and q.Request and Util.HasFunction("C_AuctionHouse.MakeItemKey")
        and Util.HasFunction("C_AuctionHouse.SendSearchQuery")
        and Util.HasFunction("C_AuctionHouse.GetNumCommoditySearchResults")
        and Util.HasFunction("C_AuctionHouse.GetCommoditySearchResultInfo")) then
        return
    end
    local items = ListSets.ItemsOf(key)
    if #items == 0 then
        Say(L["Nothing on this list to look for on the auction house."])
        return
    end
    if self.run then self:Stop() end
    self.run = { key = key, limit = limit, phase = "reading", items = items,
        listings = {}, pos = 0, spent = 0 }
    Changed()
    self:ReadNext()
end

function ListSets:ReadNext()
    local run = self.run
    if not (run and run.phase == "reading") then return end
    run.pos = run.pos + 1
    local item = run.items[run.pos]
    if not item then return self:Fitted() end
    if not IsStack(item.itemID) then
        run.listings[item.itemID] = {}
        return self:ReadNext()
    end
    local ok, key = pcall(C_AuctionHouse.MakeItemKey, item.itemID)
    if not (ok and key) then
        run.listings[item.itemID] = {}
        return self:ReadNext()
    end
    local q = ns.AHQueue
    local reading = { itemID = item.itemID }
    run.reading = reading
    q:Request({
        name = "buy sets",
        key = "listsets",
        priority = q.PRIORITY and q.PRIORITY.urgent or 10,
        expires = self.QUOTE_WAIT,
        send = function()
            if ListSets.run ~= run or run.reading ~= reading then return false end
            local sent = pcall(C_AuctionHouse.SendSearchQuery, key, PriceSort(), true)
            if sent then reading.sent = true end
            return sent
        end,
        onGiveUp = function()
            if ListSets.run == run and run.reading == reading then
                ListSets:Stop()
                Say(L["the auction house is busy, try again in a moment"])
            end
        end,
    })
    After(self.READ_WAIT, function()
        if ListSets.run == run and run.reading == reading then
            ListSets:Stop()
            Say(L["the auction house is busy, try again in a moment"])
        end
    end)
end

--- One item's listings came in.
function ListSets:Results(itemID)
    local run = self.run
    local reading = run and run.reading
    if not (reading and reading.sent) then return end
    if itemID and itemID ~= reading.itemID then return end
    run.listings[reading.itemID] = ReadListings(reading.itemID) or {}
    run.reading = nil
    self:ReadNext()
end

function ListSets:Fitted()
    local run = self.run
    if not run then return end
    local fit = ListSets.Fit(run.items, run.listings, run.limit)
    run.phase, run.sets, run.total, run.rows = "ready", fit.sets, fit.total, fit.rows
    for _, row in ipairs(run.rows) do row.state = row.buy > 0 and "todo" or nil end
    Changed()
end

--------------------------------------------------------------------------
-- Buying
--------------------------------------------------------------------------

--- The row to do next: the one being bought, else the first not got.
function ListSets:Active()
    local run = self.run
    if not (run and run.phase == "ready") then return nil end
    for i, row in ipairs(run.rows) do
        if row.state and row.state ~= "todo" and row.state ~= "got" then return i end
    end
    for i, row in ipairs(run.rows) do
        if row.state == "todo" then return i end
    end
end

--- What the rows not got yet still cost, leaving out row `skip`.
local function StillToPay(run, skip)
    local cost = 0
    for i, row in ipairs(run.rows) do
        if i ~= skip and row.state == "todo" then cost = cost + (row.cost or 0) end
    end
    return cost
end

--- Buy: ask the game for the real price of row i.
function ListSets:Buy(i)
    local run = self.run
    local row = run and run.phase == "ready" and run.rows[i]
    if not (row and row.state == "todo") then return end
    if self:Asking() or self:Busy() then
        Say(L["the auction house is busy, try again in a moment"])
        return
    end
    if not AuctionOpen() then return self:Stop() end
    if not Util.HasFunction("C_AuctionHouse.StartCommoditiesPurchase") then return end
    local ok = pcall(C_AuctionHouse.StartCommoditiesPurchase, row.itemID, row.buy)
    if not ok then return end
    row.state, row.quote = "asking", nil
    Changed()
    After(self.QUOTE_WAIT, function()
        if ListSets.run == run and row.state == "asking" then ListSets:Let(row) end
    end)
end

--- Is a row waiting on the game?
function ListSets:Asking()
    local run = self.run
    if not run or not run.rows then return nil end
    for i, row in ipairs(run.rows) do
        if row.state == "asking" or row.state == "quoted" or row.state == "buying" then return i, row end
    end
end

--- Give a row back to Buy, letting the game's price go.
function ListSets:Let(row)
    if row.state == "asking" or row.state == "quoted" then
        if Util.HasFunction("C_AuctionHouse.CancelCommoditiesPurchase") then
            pcall(C_AuctionHouse.CancelCommoditiesPurchase)
        end
    end
    row.state, row.quote = "todo", nil
    Changed()
end

--- The game answered with the real price.
function ListSets:PriceUpdated(total)
    local run = self.run
    local i, row = self:Asking()
    if not (row and row.state == "asking") then return end
    if type(total) ~= "number" or total <= 0 then return self:Let(row) end
    -- The rest of the sets must still fit what the player set to spend.
    if run.spent + total + StillToPay(run, i) > run.limit then
        self:Let(row)
        self:Stop()
        Say(L["Prices went up past what you set to spend, so Buy Sets stopped."])
        return
    end
    row.state, row.quote = "quoted", total
    Changed()
    After(self.QUOTE_WAIT, function()
        if ListSets.run == run and row.state == "quoted" then ListSets:Let(row) end
    end)
end

--- Confirm: pay the price the game gave.
function ListSets:Confirm(i)
    local run = self.run
    local row = run and run.rows and run.rows[i]
    if not (row and row.state == "quoted" and row.quote) then return end
    if type(GetMoney) == "function" then
        local ok, money = pcall(GetMoney)
        if ok and type(money) == "number" and money < row.quote then
            ns.Print(L.Format("You need %s for that.", Util.FormatMoney(row.quote, { noColor = true })))
            return
        end
    end
    local ok = Util.HasFunction("C_AuctionHouse.ConfirmCommoditiesPurchase")
        and pcall(C_AuctionHouse.ConfirmCommoditiesPurchase, row.itemID, row.buy)
    if not ok then return self:Let(row) end
    row.state = "buying"
    Changed()
    After(self.BUY_WAIT, function()
        if ListSets.run == run and row.state == "buying" then row.state = "todo"; Changed() end
    end)
end

function ListSets:Bought()
    local run = self.run
    local _, row = self:Asking()
    if not (row and row.state == "buying") then return end
    row.state = "got"
    run.spent = run.spent + (row.quote or row.cost or 0)
    Changed()
end

function ListSets:Failed()
    local _, row = self:Asking()
    if row and row.state ~= "todo" then self:Let(row) end
end

--- The button on a row: Buy, or Confirm once the price is in.
function ListSets:Press(i)
    local run = self.run
    local row = run and run.rows and run.rows[i]
    if not row then return end
    if row.state == "quoted" then return self:Confirm(i) end
    if row.state == "todo" then return self:Buy(i) end
end

--- Stop the run. Anything bought stays bought.
function ListSets:Stop()
    local run = self.run
    if not run then return end
    self.run = nil
    if run.reading and ns.AHQueue and ns.AHQueue.Cancel then
        pcall(ns.AHQueue.Cancel, ns.AHQueue, "listsets", true)
    end
    for _, row in ipairs(run.rows or {}) do
        if row.state == "asking" or row.state == "quoted" then
            if Util.HasFunction("C_AuctionHouse.CancelCommoditiesPurchase") then
                pcall(C_AuctionHouse.CancelCommoditiesPurchase)
            end
        end
    end
    Changed()
end

function ListSets:Init()
    ns.RegisterEvent(self, "COMMODITY_SEARCH_RESULTS_UPDATED", function(_, _, itemID) ListSets:Results(itemID) end)
    ns.RegisterEvent(self, "COMMODITY_PRICE_UPDATED", function(_, _, _, total) ListSets:PriceUpdated(total) end)
    ns.RegisterEvent(self, "COMMODITY_PRICE_UNAVAILABLE", function() ListSets:Failed() end)
    ns.RegisterEvent(self, "COMMODITY_PURCHASE_SUCCEEDED", function() ListSets:Bought() end)
    ns.RegisterEvent(self, "COMMODITY_PURCHASE_FAILED", function() ListSets:Failed() end)
    ns.RegisterEvent(self, "AUCTION_HOUSE_CLOSED", function() ListSets:Stop() end)
end

-- The events go in when the world loads (the lifecycle in Core/Init.lua).
function ListSets:OnEnable() self:Init() end
