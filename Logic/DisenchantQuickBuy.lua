-- Blackthornes Tradeskills -- Logic/DisenchantQuickBuy.lua
-- Buy One on the Disenchanting tab's side pane (the owner said build it,
-- 2026-11-24, from a mockup). Buying a pile of one deal took Buyout and
-- Accept for every listing. Now, once "Search the auction house" has sent
-- its search, the same button buys the cheapest listing on each click, with
-- no Accept pop-up, and readies the next one.
--
-- The game lets an addon buy only inside the player's own click or key
-- press, one listing at a time, so: one PlaceBid per click, never a loop or
-- a timer that buys. Snipe buys the same way (Logic/Snipe.lua AskItem,
-- ItemResults, Pay); this is that path cut down to one item, with the
-- Disenchanting minimums as the limit instead of Snipe's settings, so the
-- Snipe tab need not be on.
--
-- What holds:
--   * Only listings at or under the highest price that still meets the
--     Disenchanting minimums (MostToPay). Your own listings are skipped.
--   * A buy at or over Double Check Over (snipeConfirmOver, Snipe's own
--     setting, 10g unless changed) asks for a second click (Confirm).
--   * Each buy is marked to disenchant (DisenchantBuys:Intend); AHBuys
--     records the PlaceBid itself.
--   * One search when the player clicks Search, and none after. The list is
--     read again only when the game sends its own update, so selling at the
--     auction house is never held up.

local _, ns = ...

local L = ns.L or setmetatable({ Format = string.format }, { __index = function(_, key) return key end })

local QuickBuy = ns.NewModule("DisenchantQuickBuy")

local Util = ns.Util

-- Seconds a buy may wait on the game's answer before it is let go.
QuickBuy.BUY_WAIT = 15
-- Seconds the second click (Confirm) stays armed.
QuickBuy.CONFIRM_FOR = 5
-- Seconds the item search may wait in the queue.
QuickBuy.QUOTE_WAIT = 10
-- Seconds after the search to look at the game's list again, in case no
-- update came (reading only, never a search or a buy). After the last look
-- with nothing there, the button goes back to Search.
QuickBuy.LOOKS = { 1, 3, 6, 10 }
-- Double Check Over when Snipe isn't loaded (10g).
QuickBuy.CONFIRM_OVER = 100000

-- The item being bought, or nil:
-- { itemID, key, most, phase = "asking" | "ready" | "done", listings,
--   tried = { [auctionID] = true }, bought, spent, armed,
--   waiting = { buys sent, no answer yet }, moneyStart, paid }
QuickBuy.current = nil
QuickBuy.version = 0
-- Called with no arguments when what the button shows has changed.
QuickBuy.onChange = nil

local function Now() return (GetTime and GetTime()) or 0 end

local function After(seconds, fn)
    if C_Timer and C_Timer.After then C_Timer.After(seconds, fn) end
end

local function Moved()
    QuickBuy.version = QuickBuy.version + 1
    if QuickBuy.onChange then pcall(QuickBuy.onChange) end
end

--------------------------------------------------------------------------
-- The price limit
--------------------------------------------------------------------------

--- Does buying at `price` meet the minimums? The same test the tab's list
--- uses (Disenchant:AuctionRow): profit over 0, at least minProfit, and a
--- margin (profit over price) of at least minMargin percent.
function QuickBuy.Clears(price, net, minProfit, minMarginPercent)
    if type(price) ~= "number" or price <= 0 or type(net) ~= "number" then return false end
    local gain = net - price
    return gain > 0 and gain >= (minProfit or 0) and gain / price >= (minMarginPercent or 0) / 100
end

--- The highest price in copper that still meets the minimums, or nil.
function QuickBuy.MostToPay(net, minProfit, minMarginPercent)
    if type(net) ~= "number" or net <= 1 then return nil end
    local most = net - math.max(1, minProfit or 0)
    local margin = (minMarginPercent or 0) / 100
    if margin > 0 then most = math.min(most, math.floor(net / (1 + margin))) end
    most = math.floor(most)
    -- Rounding can leave it a copper over; step down until it clears.
    while most > 0 and not QuickBuy.Clears(most, net, minProfit, minMarginPercent) do most = most - 1 end
    return most > 0 and most or nil
end

local function Minimums()
    if ns.Profit and ns.Profit.DisenchantMinimums then
        local ok, profit, margin = pcall(ns.Profit.DisenchantMinimums, ns.Profit)
        if ok and profit then return profit, margin or 0 end
    end
    local ok, profit, margin = pcall(function()
        return ns.Config:Get("minProfit"), ns.Config:Get("minMarginPercent")
    end)
    if ok then return profit or 0, margin or 0 end
    return 0, 0
end

--- Double Check Over: Snipe's setting, read the same way.
function QuickBuy:ConfirmOver()
    if ns.Snipe and ns.Snipe.ConfirmOver then
        local ok, over = pcall(ns.Snipe.ConfirmOver, ns.Snipe)
        if ok and type(over) == "number" then return over end
    end
    local ok, over = pcall(function() return ns.Config:Get("snipeConfirmOver") end)
    over = ok and tonumber(over) or self.CONFIRM_OVER
    return math.max(0, math.floor(over))
end

--------------------------------------------------------------------------
-- Asking for the listings
--------------------------------------------------------------------------

local function PriceSort()
    local enum = Enum and Enum.AuctionHouseSortOrder
    local price = enum and enum.Price or 0
    return { { sortOrder = price, reverseSort = false } }
end

--- Is this item the one being bought?
function QuickBuy:IsFor(itemID)
    local cur = self.current
    return cur ~= nil and itemID ~= nil and cur.itemID == itemID
end

--- Ask the auction house for this deal's listings, cheapest first. Called
--- right after the Search button's own search. `entry` is the tab's row
--- (itemID, net). Nothing is bought here.
function QuickBuy:Start(entry)
    if not (entry and entry.itemID) then return false end
    local q = ns.AHQueue
    if not (Util.HasFunction("C_AuctionHouse.MakeItemKey")
        and Util.HasFunction("C_AuctionHouse.SendSearchQuery") and q and q.Request) then
        return false
    end
    local ok, key = pcall(C_AuctionHouse.MakeItemKey, entry.itemID)
    if not (ok and key) then return false end
    local minProfit, minMargin = Minimums()
    local mine = {
        itemID = entry.itemID, key = key, net = entry.net,
        minProfit = minProfit, minMargin = minMargin,
        most = QuickBuy.MostToPay(entry.net, minProfit, minMargin),
        phase = "asking", listings = {}, tried = {}, bought = 0, spent = 0,
    }
    self.current = mine
    Moved()
    q:Request({
        name = "disenchanting buy one",
        key = "de-quickbuy",
        priority = q.PRIORITY and q.PRIORITY.urgent or 10,
        expires = self.QUOTE_WAIT,
        send = function()
            if QuickBuy.current ~= mine then return false end
            -- Gear is filed under a key with its item level, which the
            -- item's row in the Search button's browse results carries.
            mine.key = QuickBuy.BrowseKey(mine.itemID) or mine.key
            local sent = pcall(C_AuctionHouse.SendSearchQuery, mine.key, PriceSort(), true)
            if sent then
                mine.sent = Now()
                QuickBuy:LookLater(mine)
            end
            return sent
        end,
        onGiveUp = function()
            -- Busy: the button goes back to Search for another try.
            if QuickBuy.current == mine and mine.phase == "asking" then
                QuickBuy.current = nil
                Moved()
            end
        end,
    })
    return true
end

--- The item's own key from the browse results, or nil. For gear it names
--- the item level, and only that key reads its listings.
function QuickBuy.BrowseKey(itemID)
    if not Util.HasFunction("C_AuctionHouse.GetBrowseResults") then return nil end
    local ok, rows = pcall(C_AuctionHouse.GetBrowseResults)
    if not (ok and type(rows) == "table") then return nil end
    for _, row in ipairs(rows) do
        local key = type(row) == "table" and row.itemKey
        if type(key) == "table" and key.itemID == itemID then return key end
    end
    return nil
end

--- Look at the game's list a few times after the search, in case its
--- update never came or named another key. Reading only. With nothing
--- there after the last look, the button goes back to Search.
function QuickBuy:LookLater(mine)
    local looks = self.LOOKS
    for i, seconds in ipairs(looks) do
        After(seconds, function()
            if QuickBuy.current ~= mine or mine.phase ~= "asking" then return end
            QuickBuy:Read(true)
            if i == #looks and QuickBuy.current == mine and mine.phase == "asking" then
                QuickBuy.current = nil
                Moved()
            end
        end)
    end
end

--- Read the listings the game holds for the item, cheapest first: someone
--- else's, priced at or under the limit, and not tried on this run.
--- `looking` (a look after the search, not the game's update) changes
--- nothing while the list is still empty and not complete.
function QuickBuy:Read(looking)
    local cur = self.current
    if not cur then return end
    if not (Util.HasFunction("C_AuctionHouse.GetNumItemSearchResults")
        and Util.HasFunction("C_AuctionHouse.GetItemSearchResultInfo")) then return end
    local okN, count = pcall(C_AuctionHouse.GetNumItemSearchResults, cur.key)
    if not (okN and type(count) == "number") then return end
    if looking and cur.phase == "asking" and count == 0 then
        local okF, full = false, false
        if Util.HasFunction("C_AuctionHouse.HasFullItemSearchResults") then
            okF, full = pcall(C_AuctionHouse.HasFullItemSearchResults, cur.key)
        end
        if not (okF and full == true) then return end
    end
    local listings = {}
    for i = 1, count do
        local ok, info = pcall(C_AuctionHouse.GetItemSearchResultInfo, cur.key, i)
        if ok and type(info) == "table" and info.auctionID and not info.containsOwnerItem
            and not cur.tried[info.auctionID] then
            local buyout, qty = info.buyoutAmount, info.quantity or 1
            if type(buyout) == "number" and buyout > 0 and qty > 0
                and cur.most and buyout / qty <= cur.most then
                listings[#listings + 1] = { auctionID = info.auctionID, total = buyout }
            end
        end
    end
    table.sort(listings, function(a, b)
        if a.total ~= b.total then return a.total < b.total end
        return a.auctionID < b.auctionID
    end)
    cur.listings = listings
    cur.phase = #listings > 0 and "ready" or "done"
    if cur.armed and (not listings[1] or listings[1].auctionID ~= cur.armed) then cur.armed = nil end
    Moved()
end

--- The game's item listings changed: read them again if they are ours.
function QuickBuy:OnResults(itemKey)
    local cur = self.current
    if not (cur and cur.sent) then return end
    local named = type(itemKey) == "table" and itemKey.itemID or nil
    if named and named ~= cur.itemID then return end
    -- Read under the key the game filed them by (gear names its level).
    if named then cur.key = itemKey end
    self:Read()
end

--------------------------------------------------------------------------
-- What the button shows
--------------------------------------------------------------------------

--- The cheapest listing still to buy, or nil.
function QuickBuy:Next()
    local cur = self.current
    if not cur then return nil end
    for _, listing in ipairs(cur.listings) do
        if not cur.tried[listing.auctionID] then return listing end
    end
    return nil
end

--- How many listings are left after the next one.
function QuickBuy:MoreAfterNext()
    local cur = self.current
    if not cur then return 0 end
    local left = 0
    for _, listing in ipairs(cur.listings) do
        if not cur.tried[listing.auctionID] then left = left + 1 end
    end
    return math.max(0, left - 1)
end

--- What the button is for this item: nil (Search), "asking", "ready",
--- "confirm" or "done".
function QuickBuy:StateFor(itemID)
    if not self:IsFor(itemID) then return nil end
    local cur = self.current
    if cur.phase == "asking" then return "asking" end
    local nextOne = self:Next()
    if not nextOne then return "done" end
    if cur.armed == nextOne.auctionID then return "confirm" end
    return "ready"
end

--------------------------------------------------------------------------
-- Buying
--------------------------------------------------------------------------

--- Is the game's auction channel free to take a buy right now? A buy sent
--- while it is busy is dropped by the game with no answer at all.
local function ChannelReady()
    if not Util.HasFunction("C_AuctionHouse.IsThrottledMessageSystemReady") then return true end
    local ok, ready = pcall(C_AuctionHouse.IsThrottledMessageSystemReady)
    return not ok or ready ~= false
end

local function ReadMoney()
    if type(GetMoney) ~= "function" then return nil end
    local ok, money = pcall(GetMoney)
    if ok and type(money) == "number" then return money end
    return nil
end

--- The player's click (or the Disenchanting: Buy Next key): buy the
--- cheapest listing, one PlaceBid. Returns true when a buy was sent,
--- "confirm" when it waits for a second click, "busy" when the game's
--- channel was busy (nothing sent, the same listing stays next), else false.
---
--- A buy sent is not waited on (seen in game 2026-11-24: the button sat
--- for about 15 seconds after each buy while it waited on the game's
--- answer). The next click buys the next listing at once; the game's
--- answers only keep the count of what was bought.
function QuickBuy:Click()
    local cur = self.current
    if not (cur and cur.phase == "ready") then return false end
    if not (ns.Scanner and ns.Scanner.isAuctionHouseOpen) then return false end
    local listing = self:Next()
    if not listing then
        cur.phase = "done"
        Moved()
        return false
    end

    local money = ReadMoney()
    if money and money < listing.total then
        ns.Print(L.Format("You need %s for that.", Util.FormatMoney(listing.total, { noColor = true })))
        return false
    end

    if listing.total >= self:ConfirmOver() and cur.armed ~= listing.auctionID then
        cur.armed = listing.auctionID
        Moved()
        After(self.CONFIRM_FOR, function()
            if QuickBuy.current == cur and cur.armed == listing.auctionID then
                cur.armed = nil
                Moved()
            end
        end)
        return "confirm"
    end

    if not ChannelReady() then
        if ns.Debug then ns.Debug("Buy One: the auction house is busy, click again") end
        return "busy"
    end

    if ns.DisenchantBuys and ns.DisenchantBuys.Intend then
        pcall(ns.DisenchantBuys.Intend, ns.DisenchantBuys, cur.itemID)
    end

    -- Noted before PlaceBid: the game can take the money (and send
    -- PLAYER_MONEY) inside the call itself.
    cur.waiting = cur.waiting or {}
    cur.paid = cur.paid or 0
    if money and not cur.moneyStart then cur.moneyStart = money end
    local buy = { auctionID = listing.auctionID, total = listing.total, at = Now() }
    cur.waiting[#cur.waiting + 1] = buy
    cur.armed = nil
    -- Tried either way: a listing the game refused is not offered again.
    cur.tried[listing.auctionID] = true
    local ok = Util.HasFunction("C_AuctionHouse.PlaceBid")
        and pcall(C_AuctionHouse.PlaceBid, listing.auctionID, listing.total)
    if not ok then
        self:Forget(buy)
        ns.Print(L["That buy didn't go through. Try it again."])
        if not self:Next() then cur.phase = "done" end
        Moved()
        return false
    end
    if ns.Debug then ns.Debug("Buy One: sent", listing.auctionID, listing.total) end

    if not self:Next() then cur.phase = "done" end
    Moved()
    -- No answer in time: stop waiting on it (the count only).
    After(self.BUY_WAIT, function()
        if QuickBuy.current == cur then QuickBuy:Forget(buy) end
    end)
    return true
end

--- Stop waiting on a buy; true when it was still waited on.
function QuickBuy:Forget(buy)
    local cur = self.current
    if not (cur and cur.waiting) then return false end
    for i, waiting in ipairs(cur.waiting) do
        if waiting == buy then
            table.remove(cur.waiting, i)
            return true
        end
    end
    return false
end

local function Count(cur, buy)
    cur.bought = cur.bought + 1
    cur.spent = cur.spent + buy.total
    cur.paid = (cur.paid or 0) + buy.total
end

--- The buy went through. An event that names no auction counts the oldest.
function QuickBuy:Bought(auctionID)
    local cur = self.current
    if not (cur and cur.waiting and cur.waiting[1]) then return end
    local index
    if type(auctionID) == "number" then
        for i, buy in ipairs(cur.waiting) do
            if buy.auctionID == auctionID then index = i; break end
        end
        -- Another buy (the game's own window, Snipe) finished, not ours.
        if not index then return end
    else
        index = 1
    end
    local buy = table.remove(cur.waiting, index)
    Count(cur, buy)
    if ns.Debug then ns.Debug("Buy One: bought", buy.auctionID) end
    if not self:Next() then cur.phase = "done" end
    Moved()
end

--- Money left the purse: count the waiting buys it covers, oldest first.
function QuickBuy:MoneyMoved()
    local cur = self.current
    if not (cur and cur.waiting and cur.waiting[1] and cur.moneyStart) then return end
    local money = ReadMoney()
    if not money then return end
    local gone = cur.moneyStart - money
    local counted = false
    while cur.waiting[1] and (cur.paid or 0) + cur.waiting[1].total <= gone do
        Count(cur, table.remove(cur.waiting, 1))
        counted = true
    end
    if counted then
        if not self:Next() then cur.phase = "done" end
        Moved()
    end
end

--- The game said no (gone already, or not enough money): the oldest buy
--- waited on failed. The next listing is already offered.
function QuickBuy:BuyError()
    local cur = self.current
    if not (cur and cur.waiting and cur.waiting[1]) then return end
    table.remove(cur.waiting, 1)
    if not self:Next() then cur.phase = "done" end
    Moved()
end

function QuickBuy:Closed()
    if self.current then
        self.current = nil
        Moved()
    end
end

--- The key binding: the same as a click on the button.
function QuickBuy:BuyNext()
    return self:Click()
end

function QuickBuy:Init()
    ns.RegisterEvent(self, "ITEM_SEARCH_RESULTS_UPDATED", function(_, _, itemKey) QuickBuy:OnResults(itemKey) end)
    ns.RegisterEvent(self, "AUCTION_HOUSE_PURCHASE_COMPLETED", function(_, _, auctionID) QuickBuy:Bought(auctionID) end)
    ns.RegisterEvent(self, "PLAYER_MONEY", function() QuickBuy:MoneyMoved() end)
    ns.RegisterEvent(self, "AUCTION_HOUSE_SHOW_ERROR", function() QuickBuy:BuyError() end)
    ns.RegisterEvent(self, "AUCTION_HOUSE_CLOSED", function() QuickBuy:Closed() end)
end
