-- Blackthornes Tradeskills -- UI/AuctionBrowse.lua
-- The Browse tab of our auction house window (UI/AuctionWindow.lua): the
-- search bar, the categories down the left, the list of what is for sale
-- and the footer. Logic/Browse.lua holds the search and its rows; this file
-- only draws them.
--
-- Nothing here buys anything. A click on a row opens the buy panel
-- (UI/AuctionBuy.lua), which sits over the right of the list.

local _, ns = ...

local AuctionBrowse = ns.NewModule("AuctionBrowse")

local L = ns.L
local Theme = ns.Theme
local Widgets = ns.Widgets
local Util = ns.Util

local ROW_HEIGHT = 22
local BAR_ROW = 28          -- one line of the search bar
local BAR_TOP = 8
local GAP = 8               -- between two things on the bar
local TIGHT = 4             -- between a label and its own control
local CATEGORY_WIDTH = 170
local CATEGORY_ROW = 20
local FOOTER = 26

-- Right to left across a row; the name has the rest.
local COLUMNS = {
    { key = "deal", width = 56, label = L["DEAL"] },
    { key = "usual", width = 80, money = true, label = L["USUAL PRICE"] },
    { key = "price", width = 80, money = true, label = L["PRICE EACH"] },
    { key = "count", width = 64, label = L["HOW MANY"] },
}

local widgets = {}

local function Browse() return ns.Browse end

local function Number(value)
    return type(value) == "number" and value or 0
end

--------------------------------------------------------------------------------
-- Words
--------------------------------------------------------------------------------

--- How long ago, as the footer says it: "4 minutes ago".
function AuctionBrowse.Ago(seconds)
    seconds = Number(seconds)
    if seconds < 60 then return L["just now"] end
    local minutes = math.floor(seconds / 60)
    if minutes < 60 then
        return minutes == 1 and L.Format("%d minute ago", minutes) or L.Format("%d minutes ago", minutes)
    end
    local hours = math.floor(minutes / 60)
    if hours < 24 then
        return hours == 1 and L.Format("%d hour ago", hours) or L.Format("%d hours ago", hours)
    end
    local days = math.floor(hours / 24)
    return days == 1 and L.Format("%d day ago", days) or L.Format("%d days ago", days)
end

--- The footer's left side: how many results, and how old the prices are.
function AuctionBrowse.Summary(count, scannedAt, now)
    count = Number(count)
    local text = count == 1 and L.Format("%d result.", count) or L.Format("%d results.", count)
    if type(scannedAt) == "number" and scannedAt > 0 and type(now) == "number" then
        text = text .. " " .. L.Format("Prices are from a scan %s.", AuctionBrowse.Ago(now - scannedAt))
    end
    return text
end

--- What the middle of an empty list says, and whether it offers Clear Search.
-- @return text or nil, offersClear
function AuctionBrowse.EmptyText(status, count)
    if Number(count) > 0 then return nil, false end
    if status == "waiting" or status == "searching" then
        return L["Waiting for the auction house..."], false
    end
    if status == "done" then return L["Nothing found. Try other words."], true end
    return nil, false
end

--- Which colour a deal is drawn in: under the usual price is good.
function AuctionBrowse.DealColor(deal)
    if type(deal) ~= "number" or deal == 0 then return "muted" end
    return deal < 0 and "profit" or "loss"
end

--------------------------------------------------------------------------------
-- The search bar
--------------------------------------------------------------------------------

local function WidthOf(thing)
    if thing.barWidth then return thing.barWidth end
    local ok, width = pcall(thing.GetWidth, thing)
    if ok and type(width) == "number" and width > 0 then return width end
    return 60
end

--- Lay the bar's pieces left to right, on a new line when one will not fit.
--- A piece glued to the next stays on its line.
-- @return how many lines it took
function AuctionBrowse.Flow(items, room, place)
    local x, line = 0, 0
    local index = 1
    while index <= #items do
        -- A label and what it names move together.
        local last, width = index, 0
        while true do
            local item = items[last]
            width = width + item.width
            if not item.glue or last == #items then break end
            width = width + TIGHT
            last = last + 1
        end

        if x > 0 and x + width > room then
            x, line = 0, line + 1
        end
        for at = index, last do
            local item = items[at]
            place(item, x, line)
            x = x + item.width + (item.glue and TIGHT or GAP)
        end
        index = last + 1
    end
    return line + 1
end

function AuctionBrowse:LayBar()
    local well = widgets.well
    if not well then return end
    local ok, width = pcall(well.GetWidth, well)
    if not ok or type(width) ~= "number" or width <= 0 then width = 800 end
    local inset = widgets.inset or 0
    local key = width .. ":" .. inset
    if key == widgets.barRoom then return end
    widgets.barRoom = key

    for _, item in ipairs(widgets.bar) do item.width = WidthOf(item.thing) end
    local lines = self.Flow(widgets.bar, width - 16, function(item, x, line)
        item.thing:ClearAllPoints()
        item.thing:SetPoint("LEFT", well, "TOPLEFT", 8 + x, -(BAR_TOP + line * BAR_ROW + 11))
    end)

    local top = -(BAR_TOP + lines * BAR_ROW + 2)
    widgets.top = top
    widgets.categories:ClearAllPoints()
    widgets.categories:SetPoint("TOPLEFT", well, "TOPLEFT", 8, top)
    widgets.categories:SetPoint("BOTTOMLEFT", well, "BOTTOMLEFT", 8, FOOTER)
    self:PlaceHeadings(widgets.scrollbar)
    widgets.list:ClearAllPoints()
    widgets.list:SetPoint("TOPLEFT", well, "TOPLEFT", 8 + CATEGORY_WIDTH + 8, top - 16)
    widgets.list:SetPoint("BOTTOMRIGHT", well, "BOTTOMRIGHT", -8 - inset, FOOTER)
end

--- Leave room on the right for the buy panel (0 gives it back).
function AuctionBrowse:SetInset(inset)
    inset = tonumber(inset) or 0
    if inset == (widgets.inset or 0) then return end
    widgets.inset = inset
    widgets.barRoom = nil
    self:LayBar()
end

function AuctionBrowse:PlaceHeadings(scrollbar)
    local headings, well = widgets.headings, widgets.well
    if not headings then return end
    widgets.scrollbar = scrollbar and true or false
    headings:ClearAllPoints()
    headings:SetPoint("TOPLEFT", well, "TOPLEFT", 8 + CATEGORY_WIDTH + 8, widgets.top or -38)
    headings:SetPoint("TOPRIGHT", well, "TOPRIGHT", -8 - (widgets.inset or 0) - (scrollbar and 10 or 0), widgets.top or -38)
end

--- Put the bar's controls back to what the query says.
function AuctionBrowse:SyncBar()
    local browse = Browse()
    if not browse then return end
    local query = browse.query
    if widgets.search and widgets.search:GetText() ~= (query.text or "") then
        widgets.search:SetText(query.text or "")
    end
    widgets.low:SetValue(query.minLevel or browse.MIN_LEVEL, true)
    widgets.high:SetValue(query.maxLevel or browse.MAX_LEVEL, true)
    widgets.rarity:SetValue(query.quality == nil and "any" or query.quality)
    widgets.usable:SetChecked(query.usable == true)
    widgets.deals:SetChecked(query.dealsOnly == true)
end

function AuctionBrowse:Search()
    local browse = Browse()
    if not browse then return end
    browse.query.minLevel = widgets.low:GetValue()
    browse.query.maxLevel = widgets.high:GetValue()
    if widgets.sorter then widgets.sorter:Reset() end
    if ns.AuctionBuy then ns.AuctionBuy:Close() end
    browse:Search()
    if widgets.list then widgets.list:ScrollToTop() end
end

function AuctionBrowse:Clear()
    local browse = Browse()
    if not browse then return end
    if widgets.sorter then widgets.sorter:Reset() end
    if ns.AuctionBuy then ns.AuctionBuy:Close() end
    browse:Clear()
    self:SyncBar()
end

local function BarLabel(parent, text)
    local label = Theme.CreateLabel(parent, "small", "muted")
    label:SetText(text)
    local width = Theme.TextWidth(label)
    label.barWidth = type(width) == "number" and width > 0 and math.ceil(width) or 40
    return label
end

local function BarButton(parent, text, onClick, primary)
    local button = Widgets.CreateButton(parent, text, onClick, { primary = primary, height = 22 })
    local label = rawget(button, "label")
    local width = label and Theme.TextWidth(label)
    if type(width) == "number" and width > 0 then button:SetWidth(math.max(64, math.ceil(width) + 24)) end
    return button
end

local function BuildBar(well)
    local browse = Browse()
    local bar = {}
    local function Add(thing, glue) bar[#bar + 1] = { thing = thing, glue = glue } return thing end

    local search = Widgets.CreateSearchBox(well, L["Search by Name"], function(text)
        browse.query.text = text or ""
    end)
    search:SetWidth(Widgets.SEARCH_WIDTH)
    local editBox = rawget(search, "editBox")
    if editBox and editBox.HookScript then
        editBox:HookScript("OnEnterPressed", function() AuctionBrowse:Search() end)
    end
    widgets.search = Add(search)

    Add(BarLabel(well, L["Level:"]), true)
    local levels = { width = 34, min = browse.MIN_LEVEL, max = browse.MAX_LEVEL, justify = "CENTER" }
    widgets.low = Add(Widgets.CreateNumberBox(well, levels), true)
    Add(BarLabel(well, L["to"]), true)
    widgets.high = Add(Widgets.CreateNumberBox(well, levels))

    Add(BarLabel(well, L["Rarity:"]), true)
    local options = { { text = L["Any"], value = "any" } }
    for _, choice in ipairs(browse:Qualities()) do
        options[#options + 1] = { text = choice.name, value = choice.quality }
    end
    widgets.rarity = Add(Widgets.CreateDropdown(well, options, function(value)
        browse.query.quality = value ~= "any" and value or nil
    end, { width = 110 }))

    widgets.usable = Add(Widgets.CreateCheckbox(well, L["Usable Only"], function(checked)
        browse.query.usable = checked and true or false
    end, false))
    widgets.deals = Add(Widgets.CreateCheckbox(well, L["Deals Only"], function(checked)
        browse:SetDealsOnly(checked)
    end, false))

    Add(BarButton(well, L["Search"], function() AuctionBrowse:Search() end, true))
    Add(BarButton(well, L["Clear"], function() AuctionBrowse:Clear() end))

    widgets.bar = bar
end

--------------------------------------------------------------------------------
-- Categories
--------------------------------------------------------------------------------

local function BuildCategories(well)
    local browse = Browse()
    local list = Widgets.CreateScrollList(well, {
        rowHeight = CATEGORY_ROW,
        createRow = function(row)
            row.name = Theme.CreateLabel(row, "small", "text")
            row.name:SetPoint("RIGHT", row, "RIGHT", -6, 0)
            row.name:SetWordWrap(false)
        end,
        updateRow = function(row, entry)
            row.name:ClearAllPoints()
            row.name:SetPoint("LEFT", row, "LEFT", 8 + entry.depth * 12, 0)
            row.name:SetPoint("RIGHT", row, "RIGHT", -6, 0)
            row.name:SetText(entry.name)
            row.name:SetTextColor(Theme.Unpack(entry.selected and "accent"
                or entry.depth > 0 and "muted" or "text"))
        end,
        isSelected = function(entry) return entry.selected end,
        onClick = function(entry)
            browse:PickCategory(entry.path)
            AuctionBrowse:Search()
        end,
    })
    list:SetWidth(CATEGORY_WIDTH)
    widgets.categories = list
end

--------------------------------------------------------------------------------
-- The list
--------------------------------------------------------------------------------

local function PlaceCells(owner, cells)
    local offset = -8
    for _, column in ipairs(COLUMNS) do
        local cell = cells[column.key]
        cell:ClearAllPoints()
        cell:SetPoint("RIGHT", owner, "RIGHT", offset, 0)
        cell:SetWidth(column.width)
        offset = offset - column.width - 8
    end
    return offset
end

local function CreateRow(row)
    row.icon = Theme.CreateItemIcon(row, 18)
    row.icon:SetPoint("LEFT", 8, 0)

    row.name = Theme.CreateLabel(row, "small", "text")
    row.name:SetPoint("LEFT", 32, 0)
    row.name:SetWordWrap(false)

    row.cells = {}
    for _, column in ipairs(COLUMNS) do
        local cell = Theme.CreateLabel(row, "small", "text", "RIGHT")
        cell:SetWordWrap(false)
        row.cells[column.key] = cell
    end
    local offset = PlaceCells(row, row.cells)
    row.name:SetPoint("RIGHT", row, "RIGHT", offset, 0)
end

local function UpdateRow(row, entry)
    Theme.SetItemIcon(row.icon, entry.itemID)
    Theme.SetRowName(row.name, entry.name)
    Theme.SetItemNameColor(row.name, entry.itemID, nil, entry.quality)

    row.cells.count:SetText(Util.Comma(entry.count))
    Theme.SetMoneyText(row.cells.price, entry.price)
    if entry.usual then
        Theme.SetMoneyText(row.cells.usual, entry.usual)
    else
        row.cells.usual:SetText("--")
        row.cells.usual:SetTextColor(Theme.Unpack("dim"))
    end
    row.cells.deal:SetText(ns.Browse.DealText(entry.deal))
    row.cells.deal:SetTextColor(Theme.Unpack(AuctionBrowse.DealColor(entry.deal)))
end

local function BuildList(well)
    Widgets.FitColumns(COLUMNS)

    local headings = CreateFrame("Frame", nil, well)
    headings:SetHeight(14)
    widgets.headings = headings

    local itemHeading = Theme.CreateLabel(headings, "tiny", "dim")
    itemHeading:SetPoint("LEFT", 32, 0)
    itemHeading:SetText(L["ITEM"])

    headings.cells = {}
    for _, column in ipairs(COLUMNS) do
        local cell = Theme.CreateLabel(headings, "tiny", "dim", "RIGHT")
        cell:SetText(column.label)
        headings.cells[column.key] = cell
    end
    PlaceCells(headings, headings.cells)

    local labels = { name = itemHeading }
    for key, cell in pairs(headings.cells) do labels[key] = cell end
    widgets.sorter = Widgets.SortableHeadings(labels, {
        name = function(entry) return entry.name end,
        count = function(entry) return entry.count end,
        price = function(entry) return entry.price end,
        usual = function(entry) return entry.usual end,
        -- The best deal first on the first click.
        deal = function(entry) return entry.deal and -entry.deal or nil end,
    }, function() AuctionBrowse:Refresh() end)
    if widgets.sorter and widgets.sorter.SetText then widgets.sorter:SetText({ "name" }) end

    widgets.list = Widgets.CreateScrollList(well, {
        rowHeight = ROW_HEIGHT,
        createRow = CreateRow,
        updateRow = UpdateRow,
        onEnter = function(row, entry)
            Widgets.ShowItemTooltip(row, "ANCHOR_RIGHT", entry.itemID, entry.name)
            GameTooltip:Show()
        end,
        onLeave = function() GameTooltip:Hide() end,
        -- A click opens the buy panel for that row; the same row again closes it.
        onClick = function(entry)
            if ns.AuctionBuy then ns.AuctionBuy:Toggle(entry) end
        end,
        isSelected = function(entry)
            return ns.BrowseBuy ~= nil and ns.BrowseBuy:IsOpenFor(entry)
        end,
        onScrollbarShown = function(shown) AuctionBrowse:PlaceHeadings(shown) end,
    })

    local empty = Theme.CreateLabel(well, "small", "dim", "CENTER")
    empty:SetPoint("CENTER", widgets.list, "CENTER")
    empty:SetWidth(360)
    empty:SetWordWrap(true)
    Widgets.DressEmpty(empty)
    empty:Hide()
    widgets.empty = empty
end

--------------------------------------------------------------------------------
-- Drawing
--------------------------------------------------------------------------------

function AuctionBrowse:Gold()
    if not widgets.gold then return end
    local money = type(_G.GetMoney) == "function" and _G.GetMoney() or 0
    widgets.gold:SetText(L.Format("Your Gold: %s", Util.FormatMoney(Number(money))))
end

function AuctionBrowse:Refresh()
    local browse = Browse()
    if not widgets.well or not browse then return end
    self:LayBar()

    widgets.categories:SetData(browse:CategoryLines())

    local rows = browse:Shown()
    if widgets.sorter then rows = widgets.sorter:Sort(rows) end
    widgets.list:SetData(rows)

    local text, offersClear = self.EmptyText(browse.status, #rows)
    widgets.empty:SetText(text or "")
    Widgets.EmptyAction(widgets.empty, offersClear and L["Clear Search"] or nil,
        offersClear and function() AuctionBrowse:Clear() end or nil)
    widgets.empty:SetShown(text ~= nil)

    local scanned
    local Prices = ns.Prices
    if Prices and Prices.GetLastScan then
        local ok, at = pcall(Prices.GetLastScan, Prices)
        if ok then scanned = at end
    end
    widgets.summary:SetText(browse.status == "idle" and "" or self.Summary(#rows, scanned, time()))
    self:Gold()
end

--- One redraw a frame, however many times the rows moved in it.
function AuctionBrowse:RefreshSoon()
    if self.pending then return end
    self.pending = true
    local function Run()
        AuctionBrowse.pending = false
        local well = widgets.well
        if well and well.IsVisible and well:IsVisible() == false then return end
        AuctionBrowse:Refresh()
    end
    local timer = _G.C_Timer
    if timer and timer.After then timer.After(0, Run) else Run() end
end

--- Build the tab into the window's well. Safe to call again.
function AuctionBrowse:Build(well)
    if widgets.well or not well or not Browse() then return end
    widgets.well = well

    BuildBar(well)
    BuildCategories(well)
    BuildList(well)

    local summary = Theme.CreateLabel(well, "small", "muted")
    summary:SetPoint("BOTTOMLEFT", well, "BOTTOMLEFT", 8, 8)
    widgets.summary = summary

    local gold = Theme.CreateLabel(well, "small", "text", "RIGHT")
    gold:SetPoint("BOTTOMRIGHT", well, "BOTTOMRIGHT", -8, 8)
    widgets.gold = gold

    if well.HookScript then
        well:HookScript("OnSizeChanged", function() AuctionBrowse:RefreshSoon() end)
        well:HookScript("OnShow", function() AuctionBrowse:RefreshSoon() end)
    end

    Browse().onChange = function() AuctionBrowse:RefreshSoon() end
    self:SyncBar()
    self:Refresh()
end

function AuctionBrowse:OnEnable()
    ns.RegisterEvent(self, "PLAYER_MONEY", function()
        local well = widgets.well
        if well and well.IsVisible and well:IsVisible() then AuctionBrowse:Gold() end
    end)
end

-- For the tests.
AuctionBrowse.widgets = widgets
AuctionBrowse.COLUMNS = COLUMNS
