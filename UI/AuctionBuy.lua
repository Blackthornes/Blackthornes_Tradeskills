-- Blackthornes Tradeskills -- UI/AuctionBuy.lua
-- The buy panel of our auction house window's Browse tab
-- (UI/AuctionBrowse.lua): a click on a row opens it down the right side with
-- that item's listings, how many to buy, what it costs, and the buttons.
-- Logic/BrowseBuy.lua holds the listings and does the buying; this file only
-- draws them and passes the clicks on.
--
-- Buying and bidding always take two clicks here: the first arms the button
-- (it then reads Confirm), the second pays.
--
-- Not finished, so it does not ship yet: it sits inside the TOC's
-- do-not-package block with the window.

local _, ns = ...

local AuctionBuy = ns.NewModule("AuctionBuy")

local L = ns.L
local Theme = ns.Theme
local Widgets = ns.Widgets
local Util = ns.Util

AuctionBuy.WIDTH = 300
local GAP = 8               -- between the list and the panel
local PAD = 8
local ROW_HEIGHT = 20
local FACT_ROW = 16
local FOOTER = 26           -- the Browse tab's footer, which the panel stops above
local BOTTOM = 132          -- the room under the list for totals and buttons

-- Right to left across a single auction's row.
local COLUMNS = {
    { key = "time", width = 62, label = L["TIME LEFT"] },
    { key = "buyout", width = 76, label = L["BUYOUT"] },
    { key = "bid", width = 76, label = L["BID"] },
}

local widgets = {}

local function Buy() return ns.BrowseBuy end

--------------------------------------------------------------------------------
-- Words
--------------------------------------------------------------------------------

--- How long an auction has left, in the game's own words.
function AuctionBuy.TimeLeft(band)
    if type(band) ~= "number" then return "--" end
    local text = _G["AUCTION_TIME_LEFT" .. (band + 1)]
    return type(text) == "string" and text or "--"
end

--- One price step: "40 at: 1s 12c".
function AuctionBuy.StepText(step)
    return L.Format("%d at: %s", step.count, Util.FormatMoney(step.price))
end

--- What a purchase would cost right now, for the "you need more" note.
local function Wanted(buy)
    if buy.kind == "bulk" then
        return buy.quantity and buy:Total() or nil
    end
    local listing = buy:Picked()
    if not listing or listing.own then return nil end
    if buy.amount then return buy.amount end
    if listing.mine then return listing.buyout end
    return buy:BidAmount() or listing.buyout
end

--- The one line above the buttons, and its colour.
-- @return text or nil, colorKey
function AuctionBuy.NoteText(buy)
    if not buy or not buy.item then return nil end
    if buy.note == "up" then
        return L["The price went up. Check it and confirm again."], "loss"
    end
    if buy.note == "gone" then return L["That auction is gone already."], "loss" end
    if buy.phase == "asking" or buy.phase == "paying" then
        return L["Waiting for the auction house..."], "muted"
    end
    if buy.status ~= "ready" then return nil end

    local short = buy.Short(Wanted(buy))
    if short then return L.Format("You need %s more.", Util.FormatMoney(short)), "loss" end

    local listing = buy.kind == "single" and buy:Picked()
    if listing and listing.mine then return L["You're the top bidder."], "profit" end
    if listing and listing.outbid then return L["Someone bid more than you."], "loss" end
    return nil
end

--- What the middle of the panel says while there is nothing to list.
function AuctionBuy.StatusText(buy)
    if not buy or not buy.item or buy.status == "ready" then return nil end
    if buy.status == "gone" then return L["That auction is gone already."] end
    return L["Waiting for the auction house..."]
end

--- What each button reads and whether it can be clicked.
-- @return { buy = { text, on, confirm }, bid = ..., cancel = bool }, with bid
--         nil for goods sold in bulk
function AuctionBuy.Buttons(buy)
    local state = { buy = { text = L["Buy It"], on = false }, cancel = false }
    if not buy or not buy.item then return state end
    local ready, phase = buy.status == "ready", buy.phase
    state.cancel = phase ~= nil and phase ~= "paying"

    if buy.kind == "bulk" then
        if phase == "quoted" then
            state.buy = { text = L["Confirm"], on = not buy.Short(buy.quoted), confirm = true }
        elseif phase then
            state.buy.confirm = phase == "paying"
            state.buy.text = phase == "paying" and L["Confirm"] or L["Buy It"]
        else
            state.buy.on = ready and buy.quantity ~= nil and not buy.Short(buy:Total())
        end
        return state
    end

    local listing = ready and buy:Picked() or nil
    local free = listing ~= nil and not listing.own
    state.bid = { text = L["Place Bid"], on = false }
    if phase == "bid" then
        state.bid = { text = L["Confirm"], on = not buy.Short(buy.amount), confirm = true }
        state.buy = nil
    elseif phase == "buyout" then
        state.buy = { text = L["Confirm"], on = not buy.Short(buy.amount), confirm = true }
        state.bid = nil
    elseif not phase and free then
        local bid = buy:BidAmount()
        state.bid.on = bid ~= nil and not listing.mine and not buy.Short(bid)
        state.buy.on = listing.buyout ~= nil and not buy.Short(listing.buyout)
    end
    return state
end

--------------------------------------------------------------------------------
-- Building
--------------------------------------------------------------------------------

local function Fact(panel, y)
    local name = Theme.CreateLabel(panel, "small", "muted")
    name:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, y)
    local value = Theme.CreateLabel(panel, "small", "text", "RIGHT")
    value:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -PAD, y)
    return { name = name, value = value }
end

local function SetFact(fact, name, copper, text)
    fact.name:SetText(name)
    if copper then
        Theme.SetMoneyText(fact.value, copper)
    else
        fact.value:SetText(text or "--")
        fact.value:SetTextColor(Theme.Unpack(text and "text" or "dim"))
    end
end

local function SmallButton(parent, text, width, onClick)
    return Widgets.CreateButton(parent, text, onClick, { width = width, height = 20 })
end

local function BuildTop(panel)
    widgets.icon = Theme.CreateItemIcon(panel, 24)
    widgets.icon:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, -PAD)

    widgets.name = Theme.CreateLabel(panel, "normal", "text")
    widgets.name:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD + 30, -PAD)
    widgets.name:SetPoint("RIGHT", panel, "RIGHT", -PAD, 0)
    widgets.name:SetWordWrap(true)

    widgets.sub = Theme.CreateLabel(panel, "small", "muted")
    widgets.sub:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, -40)
    widgets.sub:SetPoint("RIGHT", panel, "RIGHT", -PAD, 0)

    widgets.facts = {}
    for index = 1, 3 do
        widgets.facts[index] = Fact(panel, -58 - (index - 1) * FACT_ROW)
    end
end

--- How Many, its - and +, and the quick picks: only for goods sold in bulk.
local function BuildHowMany(panel)
    local holder = CreateFrame("Frame", nil, panel)
    holder:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -110)
    holder:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, -110)
    holder:SetHeight(62)
    widgets.howMany = holder

    local heading = Theme.CreateLabel(holder, "tiny", "dim")
    heading:SetPoint("TOPLEFT", holder, "TOPLEFT", PAD, 0)
    heading:SetText(L["HOW MANY:"])

    local function Step(by)
        local buy = Buy()
        if buy then buy:SetQuantity((buy.quantity or 1) + by) end
    end
    local less = SmallButton(holder, "-", 22, function() Step(-1) end)
    less:SetPoint("TOPLEFT", holder, "TOPLEFT", PAD, -16)
    local box = Widgets.CreateNumberBox(holder, {
        width = 56, height = 20, min = 1, justify = "CENTER",
        onChange = function(value)
            local buy = Buy()
            if buy then buy:SetQuantity(value) end
        end,
    })
    box:SetPoint("LEFT", less, "RIGHT", 4, 0)
    local more = SmallButton(holder, "+", 22, function() Step(1) end)
    more:SetPoint("LEFT", box, "RIGHT", 4, 0)
    widgets.quantity = box

    widgets.picks = {}
    local last = more
    for index = 1, 3 do
        local pick
        pick = SmallButton(holder, "", 44, function()
            local buy = Buy()
            if buy and pick.count then buy:SetQuantity(pick.count) end
        end)
        pick:SetPoint("LEFT", last, "RIGHT", index == 1 and 10 or 4, 0)
        widgets.picks[index] = pick
        last = pick
    end

    widgets.need = Theme.CreateLabel(holder, "small", "accent")
    widgets.need:SetPoint("TOPLEFT", holder, "TOPLEFT", PAD, -42)
    widgets.need:SetPoint("RIGHT", holder, "RIGHT", -PAD, 0)
end

local function CreateRow(row)
    row.text = Theme.CreateLabel(row, "small", "text")
    row.text:SetPoint("LEFT", 8, 0)
    row.text:SetWordWrap(false)

    row.cells = {}
    local offset = -8
    for _, column in ipairs(COLUMNS) do
        local cell = Theme.CreateLabel(row, "small", "text", "RIGHT")
        cell:SetWordWrap(false)
        cell:SetPoint("RIGHT", row, "RIGHT", offset, 0)
        cell:SetWidth(column.width)
        row.cells[column.key] = cell
        offset = offset - column.width - 6
    end
end

local function Money(cell, copper, dim)
    if copper then
        Theme.SetMoneyText(cell, copper)
    else
        cell:SetText("--")
        cell:SetTextColor(Theme.Unpack("dim"))
    end
    if cell.SetAlpha then cell:SetAlpha(dim and 0.5 or 1) end
end

local function UpdateRow(row, entry)
    if not entry.auctionID then
        row.text:SetText(AuctionBuy.StepText(entry))
        for _, cell in pairs(row.cells) do cell:SetText("") end
        return
    end
    row.text:SetText(entry.count > 1 and ("x" .. Util.Comma(entry.count)) or "")
    Money(row.cells.bid, entry.bid, entry.own)
    Money(row.cells.buyout, entry.buyout, entry.own)
    row.cells.time:SetText(AuctionBuy.TimeLeft(entry.timeLeft))
    row.cells.time:SetTextColor(Theme.Unpack(entry.own and "dim" or "muted"))
end

local function BuildList(panel)
    local headings = CreateFrame("Frame", nil, panel)
    headings:SetPoint("TOPLEFT", panel, "TOPLEFT", 4, -112)
    headings:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -4, -112)
    headings:SetHeight(14)
    local offset = -8
    for _, column in ipairs(COLUMNS) do
        local cell = Theme.CreateLabel(headings, "tiny", "dim", "RIGHT")
        cell:SetPoint("RIGHT", headings, "RIGHT", offset, 0)
        cell:SetWidth(column.width)
        cell:SetText(column.label)
        offset = offset - column.width - 6
    end
    widgets.headings = headings

    widgets.list = Widgets.CreateScrollList(panel, {
        rowHeight = ROW_HEIGHT,
        createRow = CreateRow,
        updateRow = UpdateRow,
        isSelected = function(entry)
            local buy = Buy()
            return entry.auctionID ~= nil and buy ~= nil and entry.auctionID == buy.pick
        end,
        onClick = function(entry)
            local buy = Buy()
            if buy and entry.auctionID then buy:Pick(entry.auctionID) end
        end,
    })

    local status = Theme.CreateLabel(panel, "small", "dim", "CENTER")
    status:SetPoint("CENTER", widgets.list, "CENTER")
    status:SetWidth(AuctionBuy.WIDTH - 40)
    status:SetWordWrap(true)
    widgets.status = status
end

local function Place(button, slot)
    local panel = widgets.panel
    button:ClearAllPoints()
    if slot == "full" then
        button:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", PAD, 40)
        button:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -PAD, 40)
    elseif slot == "left" then
        button:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", PAD, 40)
        button:SetPoint("BOTTOMRIGHT", panel, "BOTTOM", -3, 40)
    else
        button:SetPoint("BOTTOMLEFT", panel, "BOTTOM", 3, 40)
        button:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -PAD, 40)
    end
end

local function BuildBottom(panel)
    widgets.total = Fact(panel, 0)
    widgets.saves = Fact(panel, 0)
    for index, fact in ipairs({ widgets.total, widgets.saves }) do
        local y = BOTTOM - 8 - (index - 1) * FACT_ROW
        fact.name:ClearAllPoints()
        fact.name:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", PAD, y - FACT_ROW)
        fact.value:ClearAllPoints()
        fact.value:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -PAD, y - FACT_ROW)
    end

    -- Your Bid: its own frame, so the boxes and their marks hide together.
    local holder = CreateFrame("Frame", nil, panel)
    holder:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 0, BOTTOM - 30)
    holder:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", 0, BOTTOM - 30)
    holder:SetHeight(22)
    local label = Theme.CreateLabel(holder, "small", "muted")
    label:SetPoint("LEFT", holder, "LEFT", PAD, 0)
    label:SetText(L["Your Bid:"])
    local make = ns.PriceEditor and ns.PriceEditor.MoneyBoxes
    if make then
        local boxes = make(holder, function(copper)
            local buy = Buy()
            if buy then buy:SetBid(copper) end
        end)
        local width = Theme.TextWidth(label)
        boxes:SetPoint("LEFT", holder, "LEFT",
            PAD + (type(width) == "number" and width > 0 and math.ceil(width) or 60) + 8, 0)
        widgets.bidBoxes = boxes
    end
    widgets.yourBid = holder

    widgets.note = Theme.CreateLabel(panel, "small", "muted")
    widgets.note:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", PAD, 66)
    widgets.note:SetPoint("RIGHT", panel, "RIGHT", -PAD, 0)
    widgets.note:SetWordWrap(true)

    widgets.buy = Widgets.CreateButton(panel, L["Buy It"], function()
        local buy = Buy()
        if not buy then return end
        if buy.phase == "quoted" or buy.phase == "buyout" then
            buy:Confirm()
        elseif buy.kind == "bulk" then
            buy:Start()
        else
            buy:ArmBuyout()
        end
    end, { primary = true, height = 22 })
    widgets.bid = Widgets.CreateButton(panel, L["Place Bid"], function()
        local buy = Buy()
        if not buy then return end
        if buy.phase == "bid" then buy:Confirm() else buy:ArmBid() end
    end, { height = 22 })
    widgets.cancel = Widgets.CreateButton(panel, L["Cancel"], function()
        local buy = Buy()
        if buy then buy:Cancel() end
    end, { height = 22 })

    local fine = Theme.CreateLabel(panel, "tiny", "dim")
    fine:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", PAD, 8)
    fine:SetPoint("RIGHT", panel, "RIGHT", -PAD, 0)
    fine:SetWordWrap(true)
    fine:SetText(L["Buying always takes two clicks. Nothing is ever bought or posted for you."])
end

function AuctionBuy:Build()
    if widgets.panel then return true end
    local browse = ns.AuctionBrowse and ns.AuctionBrowse.widgets
    local well = browse and browse.well
    if not well then return false end

    local panel = Theme.CreatePanel(well, "panel", "border")
    panel:SetWidth(self.WIDTH)
    panel:SetPoint("TOPRIGHT", well, "TOPRIGHT", -8, browse.top or -38)
    panel:SetPoint("BOTTOMRIGHT", well, "BOTTOMRIGHT", -8, FOOTER)
    panel:Hide()
    widgets.panel = panel

    BuildTop(panel)
    BuildHowMany(panel)
    BuildList(panel)
    BuildBottom(panel)
    return true
end

--------------------------------------------------------------------------------
-- Drawing
--------------------------------------------------------------------------------

local function Subtype(itemID)
    local info = (_G.C_Item and _G.C_Item.GetItemInfoInstant) or _G.GetItemInfoInstant
    if type(info) ~= "function" then return nil end
    local ok, _, kind, subtype = pcall(info, itemID)
    if not ok then return nil end
    if type(subtype) == "string" and subtype ~= "" then return subtype end
    return type(kind) == "string" and kind ~= "" and kind or nil
end

local function Dress(button, state)
    if not state then
        button:Hide()
        return false
    end
    button:SetText(state.text)
    button:SetEnabledState(state.on and true or false)
    if button.SetConfirming then button:SetConfirming(state.confirm and true or false) end
    button:Show()
    return true
end

local function LayList(kind)
    if widgets.laid == kind then return end
    widgets.laid = kind
    local panel, list = widgets.panel, widgets.list
    list:ClearAllPoints()
    list:SetPoint("TOPLEFT", panel, "TOPLEFT", 4, kind == "bulk" and -174 or -128)
    list:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -4, BOTTOM)
end

function AuctionBuy:Refresh()
    local buy, panel = Buy(), widgets.panel
    if not panel then return end
    local browseTab = ns.AuctionBrowse
    if not (buy and buy:IsOpen()) then
        if panel:IsShown() then
            panel:Hide()
            if browseTab then
                browseTab:SetInset(0)
                browseTab:RefreshSoon()
            end
        end
        return
    end

    local item, bulk = buy.item, buy.kind == "bulk"
    local top = browseTab and browseTab.widgets.top
    if top and top ~= widgets.top then
        widgets.top = top
        panel:ClearAllPoints()
        panel:SetPoint("TOPRIGHT", widgets.well or panel:GetParent(), "TOPRIGHT", -8, top)
        panel:SetPoint("BOTTOMRIGHT", widgets.well or panel:GetParent(), "BOTTOMRIGHT", -8, FOOTER)
    end

    Theme.SetItemIcon(widgets.icon, item.itemID)
    Theme.SetRowName(widgets.name, item.name)
    Theme.SetItemNameColor(widgets.name, item.itemID, nil, item.quality)
    local subtype = Subtype(item.itemID)
    widgets.sub:SetText(subtype and L.Format("%s. You have %d.", subtype, buy.Have(item.itemID)) or "")

    local picked = not bulk and buy:Picked() or nil
    if bulk then
        local first = buy.steps and buy.steps[1]
        SetFact(widgets.facts[1], L["Cheapest Now:"], first and first.price)
        SetFact(widgets.facts[2], L["Usual Price:"], item.usual)
        SetFact(widgets.facts[3], L["For Sale:"], nil, buy.forSale and Util.Comma(buy.forSale))
    else
        SetFact(widgets.facts[1], L["Bid:"], picked and picked.bid)
        SetFact(widgets.facts[2], L["Buyout:"], picked and picked.buyout)
        SetFact(widgets.facts[3], L["Time Left:"], nil, picked and self.TimeLeft(picked.timeLeft))
    end

    -- How many
    local ready = buy.status == "ready"
    widgets.howMany:SetShown(bulk and ready)
    widgets.headings:SetShown(not bulk and ready)
    if bulk and ready then
        widgets.quantity:SetLimits(1, buy.forSale)
        widgets.quantity:SetValue(buy.quantity or 1, true)
        local picks = buy.QuickPicks(buy.forSale, item.need)
        for index, button in ipairs(widgets.picks) do
            local count = picks[index]
            button.count = count
            if count then button:SetText(Util.Comma(count)) end
            button:SetShown(count ~= nil)
        end
        widgets.need:SetText(item.need and L.Format("Your craft queue needs %d.", item.need) or "")
    end

    -- The listings
    LayList(bulk and "bulk" or "single")
    local rows = {}
    if ready then rows = bulk and (buy:Steps()) or buy.listings or {} end
    widgets.list:SetData(rows)
    local status = self.StatusText(buy)
    widgets.status:SetText(status or "")
    widgets.status:SetShown(status ~= nil)

    -- Totals
    local showTotals = bulk and ready
    widgets.total.name:SetShown(showTotals)
    widgets.total.value:SetShown(showTotals)
    local saves = showTotals and buy:Saves() or nil
    widgets.saves.name:SetShown(saves ~= nil)
    widgets.saves.value:SetShown(saves ~= nil)
    if showTotals then SetFact(widgets.total, L["Total:"], buy:Total()) end
    if saves then
        SetFact(widgets.saves, L["You Save:"], saves)
    end
    local bidding = not bulk and ready and picked ~= nil and not picked.own
    widgets.yourBid:SetShown(bidding)
    if bidding and widgets.bidBoxes then widgets.bidBoxes:Set(buy:BidAmount() or 0) end

    local text, color = self.NoteText(buy)
    widgets.note:SetText(text or "")
    widgets.note:SetTextColor(Theme.Unpack(color or "muted"))

    -- Buttons
    local state = self.Buttons(buy)
    local hasBuy = Dress(widgets.buy, state.buy)
    local hasBid = Dress(widgets.bid, state.bid)
    widgets.cancel:SetShown(state.cancel)
    if state.cancel then
        Place(hasBid and widgets.bid or widgets.buy, "left")
        Place(widgets.cancel, "right")
    elseif hasBuy and hasBid then
        Place(widgets.bid, "left")
        Place(widgets.buy, "right")
    else
        Place(hasBid and widgets.bid or widgets.buy, "full")
    end
end

--- One redraw a frame, however many times the listings moved in it.
function AuctionBuy:RefreshSoon()
    if self.pending then return end
    self.pending = true
    local function Run()
        AuctionBuy.pending = false
        AuctionBuy:Refresh()
    end
    local timer = _G.C_Timer
    if timer and timer.After then timer.After(0, Run) else Run() end
end

--------------------------------------------------------------------------------
-- Opening and closing
--------------------------------------------------------------------------------

--- A click on a Browse row: open the panel on it, or close it when it is
--- the row already open.
function AuctionBuy:Toggle(entry)
    local buy, browseTab = Buy(), ns.AuctionBrowse
    if not (buy and browseTab) then return end
    if buy:IsOpenFor(entry) then return self:Close() end
    if not self:Build() then return end
    buy.onChange = function() AuctionBuy:RefreshSoon() end
    if not buy:Open(entry) then return end
    widgets.well = browseTab.widgets.well
    widgets.panel:Show()
    browseTab:SetInset(self.WIDTH + GAP)
    self:Refresh()
    browseTab:RefreshSoon()
end

function AuctionBuy:Close()
    local buy = Buy()
    if buy then buy:Close(true) end
    self:Refresh()
end

function AuctionBuy:OnEnable()
    ns.RegisterEvent(self, "PLAYER_MONEY", function()
        local buy = Buy()
        if widgets.panel and buy and buy:IsOpen() then AuctionBuy:RefreshSoon() end
    end)
end

-- For the tests.
AuctionBuy.widgets = widgets
AuctionBuy.COLUMNS = COLUMNS
