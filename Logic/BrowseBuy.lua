-- Blackthornes Tradeskills -- Logic/BrowseBuy.lua
-- The buy panel of our own auction house window's Browse tab: the listings
-- of the row picked, how many to buy and what that costs, and the two
-- clicks that buy or bid. UI/AuctionBuy.lua draws it.
--
-- Nothing is ever bought or bid without two clicks on the panel: the first
-- only arms (and, for goods sold in bulk, asks the game its price), the
-- second pays. Each call that spends money runs straight from that second
-- click. The listings search goes through ns.AHQueue with every other
-- search and scan. Logic/AHBuys.lua notes what was bought by itself.
--
-- Not finished, so it does not ship yet: it sits inside the TOC's
-- do-not-package block with the window.
--
-- Not yet seen in game: which of a listing's bid fields the client fills
-- (see Listing below).

local _, ns = ...

local BrowseBuy = ns.NewModule("BrowseBuy")

-- How long the listings are waited for before the item counts as gone.
BrowseBuy.ANSWER_WAIT = 10
-- How long the game may take to say its price after the first click.
BrowseBuy.QUOTE_WAIT = 10
-- How long a purchase or bid may take to answer after the second click.
BrowseBuy.BUY_WAIT = 15
-- The most listings read for one item.
BrowseBuy.MAX_READ = 200
-- The quick picks beside How Many, with the craft queue's need between.
BrowseBuy.PICKS = { 20, 200 }

-- The row picked: { itemID, itemKey, name, quality, usual, need }, or nil
-- while the panel is closed.
BrowseBuy.item = nil
-- "bulk" (goods sold by the unit) or "single" (one auction at a time).
BrowseBuy.kind = nil
-- "waiting" (asked), "ready", "gone" (nothing for sale) or "busy" (the
-- auction house would not take the search).
BrowseBuy.status = nil
-- Moves whenever what the panel shows changes.
BrowseBuy.version = 0
-- Bids placed this session, by auction, to say when one was passed.
BrowseBuy.bids = {}

local token, asked, act = 0, 0, 0

local function After(seconds, fn)
    local timer = _G.C_Timer
    if timer and timer.After then timer.After(seconds, fn) else fn() end
end

local function Api(name)
    local api = _G.C_AuctionHouse
    local fn = type(api) == "table" and api[name]
    return type(fn) == "function" and fn or nil
end

local function Whole(value)
    return type(value) == "number" and value > 0 and math.floor(value) or nil
end

local function Money()
    local get = _G.GetMoney
    if type(get) ~= "function" then return nil end
    local ok, money = pcall(get)
    return ok and type(money) == "number" and money or nil
end

function BrowseBuy:Changed()
    self.version = self.version + 1
    if type(self.onChange) == "function" then pcall(self.onChange) end
end

--------------------------------------------------------------------------------
-- Opening and closing
--------------------------------------------------------------------------------

local function SameKey(a, b)
    if a == b then return true end
    if type(a) ~= "table" or type(b) ~= "table" then return false end
    return a.itemID == b.itemID and (a.itemLevel or 0) == (b.itemLevel or 0)
        and (a.itemSuffix or 0) == (b.itemSuffix or 0)
end

--- How many of an item the craft queue is still short of, or nil.
function BrowseBuy.QueueNeed(itemID)
    local Queue = ns.Queue
    if not (Queue and Queue.GetShoppingList) then return nil end
    local ok, lines = pcall(Queue.GetShoppingList, Queue)
    if not ok or type(lines) ~= "table" then return nil end
    for _, line in pairs(lines) do
        if type(line) == "table" and line.itemID == itemID then
            return Whole(line.shortfall)
        end
    end
    return nil
end

--- How many the character carries.
function BrowseBuy.Have(itemID)
    local get = (_G.C_Item and _G.C_Item.GetItemCount) or _G.GetItemCount
    if type(get) ~= "function" then return 0 end
    local ok, count = pcall(get, itemID)
    return ok and type(count) == "number" and count or 0
end

local function KindOf(itemID)
    local status = Api("GetItemCommodityStatus")
    if not status then return nil end
    local ok, answer = pcall(status, itemID)
    if not ok then return nil end
    if answer == 2 then return "bulk" end
    if answer == 1 then return "single" end
    return nil
end

local function Forget(self)
    self.steps, self.forSale, self.quantity = nil, nil, nil
    self.listings, self.pick, self.bid = nil, nil, nil
    self.phase, self.note, self.quoted, self.amount, self.expected = nil, nil, nil, nil, nil
    self.moneyBefore, self.acting = nil, nil
end

function BrowseBuy:IsOpen()
    return self.item ~= nil
end

function BrowseBuy:IsOpenFor(row)
    return self.item ~= nil and type(row) == "table" and SameKey(self.item.itemKey, row.itemKey)
end

--- Open the panel on a Browse row and ask for its listings.
function BrowseBuy:Open(row)
    local browse = ns.Browse
    if type(row) ~= "table" or type(row.itemID) ~= "number" or type(row.itemKey) ~= "table" then
        return false
    end
    if browse and not browse.open then return false end
    if self.item then self:Close(true) end

    token = token + 1
    Forget(self)
    self.item = {
        itemID = row.itemID,
        itemKey = row.itemKey,
        name = row.name,
        quality = row.quality,
        usual = Whole(row.usual),
        need = self.QueueNeed(row.itemID),
    }
    self.kind = KindOf(row.itemID)
    self.status = "waiting"
    self:Ask()
    self:Changed()
    return true
end

function BrowseBuy:Close(quiet)
    if not self.item then return end
    token = token + 1
    self:Cancel(true)
    local queue = ns.AHQueue
    if queue and queue.Cancel then queue:Cancel("ui-buy", true) end
    Forget(self)
    self.item, self.kind, self.status = nil, nil, nil
    if not quiet then self:Changed() end
end

--------------------------------------------------------------------------------
-- The listings
--------------------------------------------------------------------------------

--- Ask the auction house what is listed. `keep` leaves what shows in place
--- until the answer comes, for a look again after a buy.
function BrowseBuy:Ask(keep)
    local item, queue = self.item, ns.AHQueue
    if not item then return end
    asked = asked + 1
    local mine, opened = asked, token
    if not keep then self.status = "waiting" end

    local function Stale() return opened ~= token or mine ~= asked end
    local function Busy()
        if Stale() then return end
        if self.status == "waiting" then
            self.status = "busy"
            self:Changed()
        end
    end

    if not (queue and queue.Request) then return Busy() end
    queue:Request({
        name = "buy panel",
        key = "ui-buy",
        priority = queue.PRIORITY.urgent,
        expires = 20,
        send = function()
            if Stale() then return true end
            local search = Api("SendSearchQuery")
            if not search then return false end
            local order = _G.Enum and _G.Enum.AuctionHouseSortOrder
            local sorts = { { sortOrder = order and order.Price or 0, reverseSort = false } }
            if not pcall(search, item.itemKey, sorts, false) then return false end
            After(self.ANSWER_WAIT, function()
                if Stale() or self.status ~= "waiting" then return end
                self.status = "gone"
                self:Changed()
            end)
            return true
        end,
        onGiveUp = Busy,
    })
end

local function Disarm(self)
    act = act + 1
    self.phase, self.quoted, self.amount, self.expected = nil, nil, nil, nil
    self.moneyBefore, self.acting = nil, nil
end

--- Goods sold by the unit: the price steps, cheapest first.
function BrowseBuy:ReadBulk(itemID)
    local item = self.item
    if not item or item.itemID ~= itemID then return end
    local count, info = Api("GetNumCommoditySearchResults"), Api("GetCommoditySearchResultInfo")
    if not (count and info) then return end
    local ok, total = pcall(count, itemID)
    if not ok or type(total) ~= "number" then return end

    local steps, forSale = {}, 0
    for index = 1, math.min(total, self.MAX_READ) do
        local okInfo, result = pcall(info, itemID, index)
        if okInfo and type(result) == "table" then
            local price = Whole(result.unitPrice)
            local quantity = (Whole(result.quantity) or 0) - (Whole(result.numOwnerItems) or 0)
            if price and quantity > 0 then
                local last = steps[#steps]
                if last and last.price == price then
                    last.count = last.count + quantity
                else
                    steps[#steps + 1] = { price = price, count = quantity }
                end
                forSale = forSale + quantity
            end
        end
    end
    table.sort(steps, function(a, b) return a.price < b.price end)

    self.kind = "bulk"
    self.steps, self.forSale = steps, forSale
    if forSale > 0 then
        self.status = "ready"
        local want = self.quantity or item.need or 1
        self.quantity = math.max(1, math.min(want, forSale))
    else
        self.status = "gone"
        self.quantity = nil
        if self.phase then
            self:Cancel(true)
            self.note = "gone"
        end
    end
    self:Changed()
end

--- One auction as the panel shows it.
-- `least` is the least the next bid may be and `bid` what shows as the bid.
-- Not yet seen in game: the client is read as giving minBid for the next
-- bid and bidAmount for the one standing, each standing in for the other.
function BrowseBuy.Listing(result, player, bids)
    if type(result) ~= "table" or type(result.auctionID) ~= "number" then return nil end
    local buyout = Whole(result.buyoutAmount)
    local least = Whole(result.minBid) or Whole(result.bidAmount)
    if not (buyout or least) then return nil end
    local mine = player ~= nil and result.bidder == player
    return {
        auctionID = result.auctionID,
        count = Whole(result.quantity) or 1,
        buyout = buyout,
        bid = Whole(result.bidAmount) or Whole(result.minBid),
        least = least,
        timeLeft = type(result.timeLeft) == "number" and result.timeLeft or nil,
        own = result.containsOwnerItem == true,
        mine = mine,
        outbid = (bids and bids[result.auctionID] ~= nil and not mine) or false,
    }
end

local function ByPrice(a, b)
    if (a.buyout ~= nil) ~= (b.buyout ~= nil) then return a.buyout ~= nil end
    if a.buyout and a.buyout ~= b.buyout then return a.buyout < b.buyout end
    if (a.least or 0) ~= (b.least or 0) then return (a.least or 0) < (b.least or 0) end
    return a.auctionID < b.auctionID
end

--- Single auctions: each with its bid, buyout and time left.
function BrowseBuy:ReadSingle(itemKey)
    local item = self.item
    if not item or type(itemKey) ~= "table" or itemKey.itemID ~= item.itemID then return end
    local count, info = Api("GetNumItemSearchResults"), Api("GetItemSearchResultInfo")
    if not (count and info) then return end
    local ok, total = pcall(count, item.itemKey)
    if not ok or type(total) ~= "number" then return end

    local player
    if type(_G.UnitGUID) == "function" then
        local okGuid, guid = pcall(_G.UnitGUID, "player")
        if okGuid and type(guid) == "string" then player = guid end
    end

    local listings = {}
    for index = 1, math.min(total, self.MAX_READ) do
        local okInfo, result = pcall(info, item.itemKey, index)
        if okInfo then
            -- A hidden bidder can't be compared, so the whole row is read in a pcall.
            local okRow, listing = pcall(self.Listing, result, player, self.bids)
            if okRow and listing then listings[#listings + 1] = listing end
        end
    end
    table.sort(listings, ByPrice)

    self.kind = "single"
    self.listings = listings
    local kept
    for _, listing in ipairs(listings) do
        if listing.auctionID == self.pick then kept = listing break end
    end
    if not kept then
        if self.phase then
            Disarm(self)
            self.note = "gone"
        end
        self.pick, self.bid = nil, nil
        for _, listing in ipairs(listings) do
            if not listing.own then self.pick = listing.auctionID break end
        end
    end
    self.status = #listings > 0 and "ready" or "gone"
    self:Changed()
end

--- The auction picked, or nil.
function BrowseBuy:Picked()
    for _, listing in ipairs(self.listings or {}) do
        if listing.auctionID == self.pick then return listing end
    end
    return nil
end

function BrowseBuy:Pick(auctionID)
    if self.phase == "paying" or auctionID == self.pick then return end
    for _, listing in ipairs(self.listings or {}) do
        if listing.auctionID == auctionID then
            Disarm(self)
            self.pick, self.bid, self.note = auctionID, nil, nil
            self:Changed()
            return
        end
    end
end

--------------------------------------------------------------------------------
-- How many, and what it costs
--------------------------------------------------------------------------------

function BrowseBuy:SetQuantity(count)
    if self.kind ~= "bulk" or not self.forSale or self.forSale < 1 then return end
    if self.phase == "paying" then return end
    count = math.max(1, math.min(Whole(count) or 1, self.forSale))
    if count == self.quantity and not self.phase then return end
    if self.phase then self:Cancel(true) end
    self.quantity, self.note = count, nil
    self:Changed()
end

--- The price steps the picked number takes: { { price, count } }, and the total.
function BrowseBuy:Steps()
    local taken, total, left = {}, 0, self.quantity or 0
    for _, step in ipairs(self.steps or {}) do
        if left <= 0 then break end
        local count = math.min(left, step.count)
        taken[#taken + 1] = { price = step.price, count = count }
        total = total + count * step.price
        left = left - count
    end
    return taken, total
end

function BrowseBuy:Total()
    if self.quoted then return self.quoted end
    local _, total = self:Steps()
    return total
end

--- What the picked number saves against the usual price, or nil.
function BrowseBuy:Saves()
    local usual = self.item and self.item.usual
    if not usual or not self.quantity then return nil end
    local saved = usual * self.quantity - self:Total()
    return saved > 0 and saved or nil
end

--- How much more gold an amount needs, or nil when there is enough.
function BrowseBuy.Short(amount)
    local money = Money()
    if not money or type(amount) ~= "number" then return nil end
    return amount > money and amount - money or nil
end

--- The quick picks: 20, what the craft queue needs and 200, none over what
--- is for sale.
function BrowseBuy.QuickPicks(forSale, need)
    local picks, seen = {}, {}
    local function Add(count)
        count = Whole(count)
        if count and count <= (forSale or 0) and not seen[count] then
            seen[count] = true
            picks[#picks + 1] = count
        end
    end
    Add(BrowseBuy.PICKS[1])
    Add(need)
    Add(BrowseBuy.PICKS[2])
    table.sort(picks)
    return picks
end

--------------------------------------------------------------------------------
-- Buying in bulk: Buy It, then Confirm
--------------------------------------------------------------------------------

--- First click: ask the game what this many cost right now. Pays nothing.
function BrowseBuy:Start()
    local item = self.item
    if not item or self.kind ~= "bulk" or self.status ~= "ready" or self.phase then return false end
    local count = self.quantity
    if not count or count < 1 then return false end
    local _, total = self:Steps()
    if self.Short(total) then return false end
    local start = Api("StartCommoditiesPurchase")
    if not start or not pcall(start, item.itemID, count) then
        self.note = "gone"
        self:Changed()
        return false
    end

    act = act + 1
    local mine = act
    self.phase, self.expected, self.quoted, self.note = "asking", total, nil, nil
    After(self.QUOTE_WAIT, function()
        if mine ~= act or self.phase ~= "asking" then return end
        self:Cancel(true)
        self.note = "gone"
        self:Changed()
    end)
    self:Changed()
    return true
end

--- The game's price for the purchase under way.
function BrowseBuy:OnQuote(_, total)
    total = Whole(total)
    if not total then return end
    if self.phase == "asking" then
        self.phase, self.quoted = "quoted", total
        self.note = total > (self.expected or total) and "up" or nil
        self:Changed()
    elseif self.phase == "paying" and self.kind == "bulk" and total > (self.quoted or total) then
        -- It moved while paying: nothing was bought, so it is confirmed again.
        act = act + 1
        self.phase, self.quoted, self.note = "quoted", total, "up"
        self:Changed()
    end
end

--------------------------------------------------------------------------------
-- One auction: Place Bid or Buy It, then Confirm
--------------------------------------------------------------------------------

function BrowseBuy:SetBid(amount)
    if self.phase == "paying" then return end
    amount = Whole(amount)
    if amount == self.bid then return end
    if self.phase == "bid" then Disarm(self) end
    self.bid = amount
    self:Changed()
end

--- What a bid on the picked auction would be: what was typed, never under
--- the least it takes and never over its buyout.
function BrowseBuy:BidAmount()
    local listing = self:Picked()
    if not listing or not listing.least then return nil end
    local amount = math.max(self.bid or listing.least, listing.least)
    if listing.buyout then amount = math.min(amount, listing.buyout) end
    return amount
end

local function Arm(self, phase, amount)
    local listing = self:Picked()
    if self.kind ~= "single" or self.status ~= "ready" or self.phase then return false end
    if not listing or listing.own or not amount or BrowseBuy.Short(amount) then return false end
    act = act + 1
    self.phase, self.amount, self.note = phase, amount, nil
    self:Changed()
    return true
end

--- First click of a bid. Pays nothing.
function BrowseBuy:ArmBid()
    local listing = self:Picked()
    if listing and listing.mine then return false end
    return Arm(self, "bid", self:BidAmount())
end

--- First click of a buyout. Pays nothing.
function BrowseBuy:ArmBuyout()
    local listing = self:Picked()
    return Arm(self, "buyout", listing and listing.buyout)
end

--------------------------------------------------------------------------------
-- The second click
--------------------------------------------------------------------------------

local function Wait(self)
    act = act + 1
    local mine = act
    After(self.BUY_WAIT, function()
        if mine ~= act or self.phase ~= "paying" then return end
        Disarm(self)
        self.note = "gone"
        self:Ask(true)
        self:Changed()
    end)
end

--- Second click: pay. Only ever called from the Confirm button.
function BrowseBuy:Confirm()
    local item = self.item
    if not item then return false end

    if self.phase == "quoted" and self.kind == "bulk" then
        local total, count = self.quoted, self.quantity
        if not (total and count) or self.Short(total) then return false end
        local confirm = Api("ConfirmCommoditiesPurchase")
        self.moneyBefore = Money()
        if not confirm or not pcall(confirm, item.itemID, count) then
            self:Cancel(true)
            self.note = "gone"
            self:Changed()
            return false
        end
        self.phase, self.note = "paying", nil
        Wait(self)
        self:Changed()
        return true
    end

    if self.phase == "bid" or self.phase == "buyout" then
        local listing, amount = self:Picked(), self.amount
        if not listing or not amount or self.Short(amount) then
            Disarm(self)
            self.note = not listing and "gone" or nil
            self:Changed()
            return false
        end
        local place = Api("PlaceBid")
        self.moneyBefore = Money()
        if not place or not pcall(place, listing.auctionID, amount) then
            Disarm(self)
            self.note = "gone"
            self:Changed()
            return false
        end
        self.acting = { auctionID = listing.auctionID, bid = self.phase == "bid", amount = amount }
        self.phase, self.note = "paying", nil
        Wait(self)
        self:Changed()
        return true
    end
    return false
end

--- Let go of whatever is armed. Nothing was bought.
function BrowseBuy:Cancel(quiet)
    if not self.phase then return end
    if self.kind == "bulk" and self.phase ~= "paying" then
        local cancel = Api("CancelCommoditiesPurchase")
        if cancel then pcall(cancel) end
    end
    Disarm(self)
    self.note = nil
    if not quiet then self:Changed() end
end

--- It went through: look at the listings again.
function BrowseBuy:Bought()
    if self.phase ~= "paying" then return end
    local acting = self.acting
    if acting and acting.bid then self.bids[acting.auctionID] = acting.amount end
    Disarm(self)
    self.note, self.bid = nil, nil
    self:Ask(true)
    self:Changed()
end

--- The auction house said no.
function BrowseBuy:Failed()
    if not self.phase or self.phase == "bid" or self.phase == "buyout" then return end
    self:Cancel(true)
    self.note = "gone"
    self:Ask(true)
    self:Changed()
end

function BrowseBuy:MoneyMoved()
    if self.phase ~= "paying" or not self.moneyBefore then return end
    local spent = self.acting and self.acting.amount or self.quoted
    local money = Money()
    if money and spent and self.moneyBefore - money >= spent then self:Bought() end
end

function BrowseBuy:OnEnable()
    ns.RegisterEvent(self, "AUCTION_HOUSE_CLOSED", function() BrowseBuy:Close() end)
    ns.RegisterEvent(self, "COMMODITY_SEARCH_RESULTS_UPDATED", function(_, _, itemID)
        BrowseBuy:ReadBulk(itemID)
    end)
    ns.RegisterEvent(self, "ITEM_SEARCH_RESULTS_UPDATED", function(_, _, itemKey)
        BrowseBuy:ReadSingle(itemKey)
    end)
    ns.RegisterEvent(self, "ITEM_SEARCH_RESULTS_ADDED", function(_, _, itemKey)
        BrowseBuy:ReadSingle(itemKey)
    end)
    ns.RegisterEvent(self, "COMMODITY_PRICE_UPDATED", function(_, _, unit, total)
        BrowseBuy:OnQuote(unit, total)
    end)
    ns.RegisterEvent(self, "COMMODITY_PRICE_UNAVAILABLE", function() BrowseBuy:Failed() end)
    ns.RegisterEvent(self, "COMMODITY_PURCHASE_SUCCEEDED", function()
        if BrowseBuy.kind == "bulk" then BrowseBuy:Bought() end
    end)
    ns.RegisterEvent(self, "COMMODITY_PURCHASE_FAILED", function()
        if BrowseBuy.kind == "bulk" then BrowseBuy:Failed() end
    end)
    ns.RegisterEvent(self, "AUCTION_HOUSE_PURCHASE_COMPLETED", function(_, _, auctionID)
        local acting = BrowseBuy.acting
        if acting and (auctionID == nil or auctionID == acting.auctionID) then BrowseBuy:Bought() end
    end)
    ns.RegisterEvent(self, "BID_ADDED", function()
        if BrowseBuy.acting and BrowseBuy.acting.bid then BrowseBuy:Bought() end
    end)
    ns.RegisterEvent(self, "AUCTION_HOUSE_SHOW_ERROR", function()
        if BrowseBuy.phase == "paying" then BrowseBuy:Failed() end
    end)
    ns.RegisterEvent(self, "PLAYER_MONEY", function() BrowseBuy:MoneyMoved() end)
end
