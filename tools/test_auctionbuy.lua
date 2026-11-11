-- The buy panel of our auction house window (Logic/BrowseBuy.lua,
-- UI/AuctionBuy.lua), without a game client.
--
-- What matters most: nothing is bought or bid on without two clicks, the
-- listings search waits its turn in the shared queue, a price that went up
-- needs Confirm again, and nothing happens while the auction house is
-- closed. Then the panel's words and buttons, and a build of the panel over
-- a widget layer that only remembers what was written to it.

local failures = 0
local function check(name, ok)
    if ok then print("  ok   " .. name) else failures = failures + 1; print("  FAIL " .. name) end
end

--------------------------------------------------------------------------------
-- The pretend game and queue
--------------------------------------------------------------------------------

local timers = {}
_G.C_Timer = { After = function(seconds, fn) timers[#timers + 1] = { seconds, fn } end }
local function Tick(upTo)
    upTo = upTo or 1
    local ran = true
    while ran do
        ran = false
        for index, timer in ipairs(timers) do
            if timer[1] <= upTo then
                table.remove(timers, index)
                timer[2]()
                ran = true
                break
            end
        end
    end
end
local function DropTimers() timers = {} end

local money = 100000
_G.GetMoney = function() return money end
_G.UnitGUID = function() return "Player-1" end
_G.AUCTION_TIME_LEFT1, _G.AUCTION_TIME_LEFT2 = "Short", "Medium"
_G.AUCTION_TIME_LEFT3, _G.AUCTION_TIME_LEFT4 = "Long", "Very Long"

-- Item 10 is sold in bulk, item 20 one auction at a time.
local kinds = { [10] = 2, [20] = 1 }
local searches, started, paid, bids, cancelled = {}, {}, {}, {}, 0
local bulk, singles = {}, {}
_G.C_AuctionHouse = {
    GetItemCommodityStatus = function(itemID) return kinds[itemID] or 0 end,
    SendSearchQuery = function(itemKey) searches[#searches + 1] = itemKey end,
    GetNumCommoditySearchResults = function() return #bulk end,
    GetCommoditySearchResultInfo = function(_, index) return bulk[index] end,
    GetNumItemSearchResults = function() return #singles end,
    GetItemSearchResultInfo = function(_, index) return singles[index] end,
    StartCommoditiesPurchase = function(itemID, count) started[#started + 1] = { itemID, count } end,
    ConfirmCommoditiesPurchase = function(itemID, count) paid[#paid + 1] = { itemID, count } end,
    CancelCommoditiesPurchase = function() cancelled = cancelled + 1 end,
    PlaceBid = function(auctionID, amount) bids[#bids + 1] = { auctionID, amount } end,
}

local events = {}
local ns = {}
ns.NewModule = function(name) local m = {}; ns[name] = m; return m end
ns.RegisterEvent = function(_, event, fn) events[event] = fn return true end
ns.L = setmetatable({ Format = function(key, ...) return key:format(...) end },
    { __index = function(_, key) return key end })
ns.Util = { FormatMoney = function(copper) return copper .. "c" end, Comma = function(n) return tostring(n) end }
local function Fire(event, ...)
    if events[event] then events[event](nil, event, ...) end
end

local queued, dropped = {}, {}
ns.AHQueue = {
    PRIORITY = { urgent = 1, normal = 2, scan = 3 },
    Request = function(_, request) queued[request.key] = request end,
    Cancel = function(_, key) queued[key] = nil; dropped[key] = true end,
}
local function Run(key)
    local request = queued[key]
    queued[key] = nil
    return request and request.send()
end

local need
ns.Queue = { GetShoppingList = function() return { { itemID = 10, shortfall = need } } end }
ns.Browse = { open = false }

assert(loadfile("Logic/BrowseBuy.lua"))("Blackthornes_TS", ns)
local Buy = ns.BrowseBuy
Buy:OnEnable()

local wool = { itemID = 10, itemKey = { itemID = 10 }, name = "Wool Cloth", quality = 1, usual = 120 }
local sword = { itemID = 20, itemKey = { itemID = 20 }, name = "Old Sword", quality = 2 }

print("")
print("opening the buy panel")

check("nothing opens while the auction house is closed",
    Buy:Open(wool) == false and not Buy:IsOpen() and queued["ui-buy"] == nil)
ns.Browse.open = true
check("a row with no item opens nothing", Buy:Open({ name = "x" }) == false and not Buy:IsOpen())

need = 30
check("a row opens the panel", Buy:Open(wool) == true and Buy:IsOpenFor(wool) and not Buy:IsOpenFor(sword))
check("its listings wait in the shared queue, ahead of scans",
    queued["ui-buy"] ~= nil and queued["ui-buy"].priority == 1 and #searches == 0)
check("it knows goods sold in bulk, and what the craft queue needs",
    Buy.kind == "bulk" and Buy.status == "waiting" and Buy.item.need == 30)
Run("ui-buy")
check("the queue sends the search once", #searches == 1 and searches[1] == wool.itemKey)

--------------------------------------------------------------------------------
-- Goods sold in bulk
--------------------------------------------------------------------------------

print("")
print("buying in bulk")

bulk = {
    { unitPrice = 110, quantity = 25 },
    { unitPrice = 100, quantity = 10 },
    { unitPrice = 100, quantity = 12, numOwnerItems = 2 },
    { unitPrice = 150, quantity = 5, numOwnerItems = 5 },
}
Fire("COMMODITY_SEARCH_RESULTS_UPDATED", 99)
check("another item's answer is not read", Buy.status == "waiting")
Fire("COMMODITY_SEARCH_RESULTS_UPDATED", 10)
check("the price steps are cheapest first, equal prices joined, your own left out",
    Buy.status == "ready" and #Buy.steps == 2 and Buy.steps[1].price == 100
    and Buy.steps[1].count == 20 and Buy.steps[2].count == 25 and Buy.forSale == 45)
check("How Many starts at what the craft queue needs", Buy.quantity == 30)
local taken, total = Buy:Steps()
check("the total walks the steps", #taken == 2 and taken[2].count == 10 and total == 20 * 100 + 10 * 110)
check("it says what that saves against the usual price", Buy:Saves() == 30 * 120 - 3100)
Buy:SetQuantity(999)
check("How Many never passes what is for sale", Buy.quantity == 45)
Buy:SetQuantity(0)
check("and never drops under one", Buy.quantity == 1)
local picks = Buy.QuickPicks(45, 30)
check("the quick picks are 20 and the queue's need, none over what is for sale",
    #picks == 2 and picks[1] == 20 and picks[2] == 30)
picks = Buy.QuickPicks(500, 20)
check("a need of 20 shows once", #picks == 2 and picks[1] == 20 and picks[2] == 200)

Buy:SetQuantity(30)
check("Confirm before Buy It pays nothing", Buy:Confirm() == false and #paid == 0 and #started == 0)
check("the first click only asks the game its price",
    Buy:Start() == true and Buy.phase == "asking" and #started == 1 and started[1][2] == 30 and #paid == 0)
check("Confirm while the price is still coming pays nothing", Buy:Confirm() == false and #paid == 0)
check("a second Buy It does not ask again", Buy:Start() == false and #started == 1)
Fire("COMMODITY_PRICE_UPDATED", 103, 3100)
check("the game's price arms Confirm", Buy.phase == "quoted" and Buy:Total() == 3100 and Buy.note == nil)
check("the second click pays, once",
    Buy:Confirm() == true and Buy.phase == "paying" and #paid == 1 and paid[1][1] == 10 and paid[1][2] == 30)
check("a third click pays nothing more", Buy:Confirm() == false and #paid == 1)
Fire("COMMODITY_PURCHASE_SUCCEEDED")
check("once it goes through the panel is unarmed and looks again",
    Buy.phase == nil and queued["ui-buy"] ~= nil and Buy.status == "ready")
DropTimers()
Run("ui-buy")
Fire("COMMODITY_SEARCH_RESULTS_UPDATED", 10)
DropTimers()

Buy:SetQuantity(10)
Buy:Start()
Fire("COMMODITY_PRICE_UPDATED", 120, 1200)
check("a price that went up says so and waits for Confirm",
    Buy.phase == "quoted" and Buy.note == "up" and Buy:Total() == 1200 and #paid == 1)
Buy:Confirm()
Fire("COMMODITY_PRICE_UPDATED", 130, 1300)
check("a price that moves while paying needs Confirm again",
    Buy.phase == "quoted" and Buy.note == "up" and Buy:Total() == 1300)
local before = cancelled
Buy:Cancel()
check("Cancel lets go and tells the game", Buy.phase == nil and Buy.note == nil and cancelled == before + 1)
DropTimers()

Buy:Start()
Tick(Buy.QUOTE_WAIT)
check("no price from the game in time lets go and says it is gone",
    Buy.phase == nil and Buy.note == "gone")

Buy:Start()
Fire("COMMODITY_PRICE_UPDATED", 100, 1000)
Buy:SetQuantity(5)
check("changing How Many unarms it", Buy.phase == nil and Buy.quantity == 5)
DropTimers()

Buy:Start()
Fire("COMMODITY_PRICE_UPDATED", 100, 500)
local sentBefore = #paid
Buy:Confirm()
Tick(Buy.BUY_WAIT)
check("a purchase with no answer lets go and looks again",
    #paid == sentBefore + 1 and Buy.phase == nil and Buy.note == "gone" and queued["ui-buy"] ~= nil)
queued["ui-buy"] = nil
DropTimers()

Buy:Start()
Fire("COMMODITY_PRICE_UPDATED", 100, 500)
Buy:Confirm()
money = money - 500
Fire("PLAYER_MONEY")
check("gold leaving the purse counts as bought", Buy.phase == nil and Buy.note == nil)
queued["ui-buy"] = nil
DropTimers()

money = 300
Buy:SetQuantity(5)
check("short of gold, Buy It asks nothing",
    Buy.Short(500) == 200 and Buy:Start() == false and Buy.phase == nil)
money = 100000

bulk = {}
Buy:Start()
Fire("COMMODITY_SEARCH_RESULTS_UPDATED", 10)
check("everything sold out from under an armed buy lets go",
    Buy.status == "gone" and Buy.phase == nil and Buy.note == "gone")
DropTimers()

Fire("AUCTION_HOUSE_CLOSED")
check("closing the auction house closes the panel and drops its search",
    not Buy:IsOpen() and Buy.status == nil and dropped["ui-buy"] == true)

--------------------------------------------------------------------------------
-- One auction at a time
--------------------------------------------------------------------------------

print("")
print("bids and buyouts")

Buy:Open(sword)
Run("ui-buy")
Tick(Buy.ANSWER_WAIT)
check("no answer in time reads as gone", Buy.status == "gone")

singles = {
    { auctionID = 3, buyoutAmount = 900, minBid = 400, timeLeft = 2, quantity = 1 },
    { auctionID = 1, buyoutAmount = 500, minBid = 200, timeLeft = 0, containsOwnerItem = true },
    { auctionID = 2, buyoutAmount = 700, minBid = 300, bidAmount = 250, timeLeft = 1 },
    { auctionID = 4, minBid = 100, timeLeft = 3 },
    { auctionID = 5 },
}
Fire("ITEM_SEARCH_RESULTS_UPDATED", { itemID = 99 })
check("another item's auctions are not read", Buy.status == "gone")
Fire("ITEM_SEARCH_RESULTS_UPDATED", { itemID = 20 })
check("auctions list cheapest buyout first, bid-only ones last, empty ones left out",
    Buy.status == "ready" and #Buy.listings == 4 and Buy.listings[1].auctionID == 1
    and Buy.listings[2].auctionID == 2 and Buy.listings[4].auctionID == 4)
check("the first one that is not yours is picked", Buy.pick == 2 and Buy:Picked().buyout == 700)
check("a bid starts at the least it takes", Buy:BidAmount() == 300)
Buy:SetBid(50)
check("and never goes under it", Buy:BidAmount() == 300)
Buy:SetBid(5000)
check("or over the buyout", Buy:BidAmount() == 700)
Buy:SetBid(350)

check("Confirm before a first click pays nothing", Buy:Confirm() == false and #bids == 0)
check("Place Bid only arms", Buy:ArmBid() == true and Buy.phase == "bid" and Buy.amount == 350 and #bids == 0)
check("Buy It can't be armed over it", Buy:ArmBuyout() == false and Buy.phase == "bid")
check("Confirm places the bid, once",
    Buy:Confirm() == true and #bids == 1 and bids[1][1] == 2 and bids[1][2] == 350
    and Buy:Confirm() == false and #bids == 1)
singles[3].bidAmount, singles[3].minBid, singles[3].bidder = 350, 370, "Player-1"
Fire("BID_ADDED")
check("a bid that went through is remembered", Buy.phase == nil and Buy.bids[2] == 350)
DropTimers()
Run("ui-buy")
Fire("ITEM_SEARCH_RESULTS_UPDATED", { itemID = 20 })
DropTimers()
check("you show as the top bidder and can't bid against yourself",
    Buy:Picked().mine == true and Buy:ArmBid() == false and #bids == 1)

singles[3].bidder, singles[3].bidAmount, singles[3].minBid = "Player-2", 400, 420
Fire("ITEM_SEARCH_RESULTS_UPDATED", { itemID = 20 })
check("someone bidding more shows as outbid", Buy:Picked().outbid == true and Buy:Picked().mine == false)

Buy:Pick(3)
check("picking another auction moves the pick", Buy.pick == 3 and Buy.phase == nil)
check("Buy It only arms", Buy:ArmBuyout() == true and Buy.phase == "buyout" and Buy.amount == 900 and #bids == 1)
Buy:Pick(2)
check("picking another auction unarms it", Buy.phase == nil and Buy.pick == 2)
Buy:Pick(3)
Buy:ArmBuyout()
check("Confirm buys it out, once",
    Buy:Confirm() == true and #bids == 2 and bids[2][1] == 3 and bids[2][2] == 900
    and Buy:Confirm() == false and #bids == 2)
Fire("AUCTION_HOUSE_PURCHASE_COMPLETED", 3)
check("a buyout is not kept as a bid", Buy.phase == nil and Buy.bids[3] == nil)
DropTimers()
queued["ui-buy"] = nil

Buy:Pick(1)
check("your own auction can't be bought or bid on",
    Buy:ArmBuyout() == false and Buy:ArmBid() == false and Buy.phase == nil)

Buy:Pick(4)
check("an auction with no buyout can't be bought out",
    Buy:ArmBuyout() == false and Buy:ArmBid() == true and Buy.amount == 100)
table.remove(singles, 4)
Fire("ITEM_SEARCH_RESULTS_UPDATED", { itemID = 20 })
check("an armed auction that sold lets go and says it is gone",
    Buy.phase == nil and Buy.note == "gone" and Buy.pick == 2 and #bids == 2)

money = 50
Buy:Pick(3)
check("short of gold, nothing arms", Buy:ArmBuyout() == false and Buy:ArmBid() == false)
money = 100000
Buy:ArmBuyout()
money = 50
check("gold that ran out before Confirm pays nothing", Buy:Confirm() == false and #bids == 2 and Buy.phase == nil)
money = 100000

--------------------------------------------------------------------------------
-- The panel's words
--------------------------------------------------------------------------------

local function Stub(fields)
    local frame = fields or {}
    return setmetatable(frame, { __index = function(self, key)
        local noop = function() end
        rawset(self, key, noop)
        return noop
    end })
end
local function Label()
    return Stub({
        text = "",
        SetText = function(self, value) self.text = tostring(value) end,
        SetShown = function(self, on) self.shown = on and true or false end,
    })
end
local function Frame()
    return Stub({
        Show = function(self) self.shown = true end,
        Hide = function(self) self.shown = false end,
        SetShown = function(self, on) self.shown = on and true or false end,
        IsShown = function(self) return self.shown == true end,
        GetWidth = function() return 300 end,
        GetHeight = function() return 400 end,
    })
end
ns.Theme = setmetatable({
    CreateLabel = function() return Label() end,
    TextWidth = function() return 50 end,
    Unpack = function() return 1, 1, 1, 1 end,
    SetMoneyText = function(label, copper) label.text = copper .. "c" end,
}, { __index = function() return function() return Frame() end end })
local listOpts = {}
ns.Widgets = setmetatable({
    CreateScrollList = function(_, opts)
        listOpts[#listOpts + 1] = opts
        return Stub({ data = {}, SetData = function(self, data) self.data = data end })
    end,
    CreateButton = function(_, text, onClick)
        local button = Frame()
        button.label, button.onClick = Label(), onClick
        button.label.text = tostring(text)
        button.SetText = function(self, value) self.label.text = tostring(value) end
        button.SetEnabled = function(self, on) self.enabled = on and true or false end
        return button
    end,
    SortableHeadings = function() return Stub({ Sort = function(_, rows) return rows end }) end,
}, { __index = function() return function() return Frame() end end })
_G.CreateFrame = function() return Frame() end

local insets, redraws = {}, 0
ns.AuctionBrowse = {
    widgets = { well = Frame() },
    SetInset = function(_, inset) insets[#insets + 1] = inset end,
    RefreshSoon = function() redraws = redraws + 1 end,
}

assert(loadfile("UI/AuctionBuy.lua"))("Blackthornes_TS", ns)
local Panel = ns.AuctionBuy
Panel:OnEnable()

print("")
print("the buy panel's words")

check("a price step reads count and price", Panel.StepText({ count = 40, price = 112 }) == "40 at: 112c")
check("time left is the game's own words",
    Panel.TimeLeft(0) == "Short" and Panel.TimeLeft(3) == "Very Long" and Panel.TimeLeft(nil) == "--")

local buttons = Panel.Buttons(Buy)
check("an auction offers Place Bid and Buy It",
    buttons.bid.text == "Place Bid" and buttons.bid.on and buttons.buy.text == "Buy It" and buttons.buy.on
    and buttons.cancel == false)
Buy:ArmBid()
buttons = Panel.Buttons(Buy)
check("armed, the one button left reads Confirm and Cancel shows",
    buttons.bid.text == "Confirm" and buttons.bid.confirm and buttons.buy == nil and buttons.cancel == true)
Buy:Cancel()
Buy:Pick(1)
buttons = Panel.Buttons(Buy)
check("your own auction has both buttons off", buttons.bid.on == false and buttons.buy.on == false)
Buy:Pick(2)
check("being outbid is said", Panel.NoteText(Buy) == "Someone bid more than you.")
money = 50
local note, color = Panel.NoteText(Buy)
check("short of gold says how much more", note == "You need 370c more." and color == "loss")
buttons = Panel.Buttons(Buy)
check("and turns both buttons off", buttons.bid.on == false and buttons.buy.on == false)
money = 100000
Buy.note = "gone"
check("a gone auction is said", Panel.NoteText(Buy) == "That auction is gone already.")
Buy.note = "up"
check("a price that went up is said", Panel.NoteText(Buy) == "The price went up. Check it and confirm again.")
Buy.note = nil
Buy:Close()
check("a closed panel says nothing and offers nothing",
    Panel.NoteText(Buy) == nil and Panel.StatusText(Buy) == nil and Panel.Buttons(Buy).buy.on == false)

--------------------------------------------------------------------------------
-- The panel itself
--------------------------------------------------------------------------------

print("")
print("the buy panel")

bulk = { { unitPrice = 100, quantity = 40 } }
Panel:Toggle(wool)
check("a click on a row opens the panel beside the list",
    Buy:IsOpenFor(wool) and Panel.widgets.panel.shown == true
    and insets[#insets] == Panel.WIDTH + 8 and queued["ui-buy"] ~= nil)
check("waiting says so", Panel.StatusText(Buy) == "Waiting for the auction house...")
Run("ui-buy")
Fire("COMMODITY_SEARCH_RESULTS_UPDATED", 10)
Tick(0)
buttons = Panel.Buttons(Buy)
check("goods sold in bulk offer only Buy It", buttons.bid == nil and buttons.buy.text == "Buy It" and buttons.buy.on)
Buy:Start()
buttons = Panel.Buttons(Buy)
check("while the price comes the button waits",
    buttons.buy.on == false and Panel.NoteText(Buy) == "Waiting for the auction house...")
Fire("COMMODITY_PRICE_UPDATED", 100, 3000)
buttons = Panel.Buttons(Buy)
check("then it reads Confirm", buttons.buy.text == "Confirm" and buttons.buy.on and buttons.buy.confirm)
check("drawing the panel bought nothing", (function()
    local count = #paid
    Tick(0)
    Panel:Refresh()
    return #paid == count
end)())
DropTimers()

Panel:Toggle(wool)
check("the same row again closes it and gives the list its room back",
    not Buy:IsOpen() and Panel.widgets.panel.shown == false and insets[#insets] == 0)
ns.Browse.open = false
local opened = #insets
Panel:Toggle(wool)
check("with the auction house closed a click opens nothing",
    not Buy:IsOpen() and #insets == opened)

print("")
if failures > 0 then
    print(failures .. " failure(s)")
    os.exit(1)
end
print("all checks passed")
