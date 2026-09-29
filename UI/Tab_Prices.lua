-- Blackthornes Tradeskills -- UI/Tab_Prices.lua
-- The price database, browsable.
--
-- The Profit tab tells you what to make; this tells you why it thinks so. Every
-- number the profit engine uses is visible here, including the ones that
-- undermine it: how thin the market is, how old the reading is, and how few
-- scans it rests on.

local _, ns = ...

local Theme = ns.Theme
local Widgets = ns.Widgets
local Util = ns.Util

local UI = ns.UI

local ROW_HEIGHT = 22
local DETAIL_WIDTH = 300

local COLUMNS = {
    { key = "age",       label = "AGE",    width = 44 },
    { key = "liquidity", label = "MOVES",  width = 52 },
    { key = "quantity",  label = "LISTED", width = 52 },
    { key = "min",       label = "CHEAPEST", width = 80 },
    { key = "market",    label = "MARKET", width = 80 },
}

local state = {
    search = "",
    reagentsOnly = false,
    sortBy = "market",
    selected = nil,
}

local widgets = {}

--------------------------------------------------------------------------------
-- Data
--------------------------------------------------------------------------------

--- Item IDs used as reagents by any cached recipe.
local function GetReagentSet()
    local reagents = {}

    for _, recipe in pairs(ns.Recipes:GetAll()) do
        for _, reagent in ipairs(recipe.reagents or {}) do
            reagents[reagent.itemID] = true
        end

        if recipe.outputItemID then
            reagents[recipe.outputItemID] = true
        end
    end

    return reagents
end

--- An item's plain name without fetching it: the saved facts first, then
--- the client only for an item it already holds. The whole price table is
--- thousands of items, and reading each through the client on every redraw
--- pushed bag items out of its small cache (Ready to sell then flickers).
local function PlainName(itemID)
    local name = ns.Disenchant and ns.Disenchant.KnownName and ns.Disenchant:KnownName(itemID)
    if name then return name end

    if Util.HasFunction("C_Item.IsItemDataCachedByID") then
        local ok, cached = pcall(C_Item.IsItemDataCachedByID, itemID)
        if not ok or cached ~= true then return nil end
    else
        return nil
    end

    local ok, itemName = pcall(C_Item.GetItemInfo, itemID)
    return ok and itemName or nil
end

local function BuildList()
    local rows = {}
    local reagents = state.reagentsOnly and GetReagentSet() or nil

    -- Names are only needed to search or sort by; the label itself is read
    -- for the rows on screen, in UpdateRow.
    local wantNames = state.search ~= "" or state.sortBy == "name"

    for itemID, record in pairs(ns.Prices:GetTable()) do
        if not reagents or reagents[itemID] then
            rows[#rows + 1] = {
                itemID = itemID,
                record = record,
                market = record.market or 0,
                min = record.min or 0,
                quantity = record.quantity or 0,
                age = ns.Prices:GetAge(itemID) or math.huge,
                liquidity = ns.Prices:GetLiquidity(itemID),
                name = wantNames and (PlainName(itemID) or ("~item %d"):format(itemID)) or "",
            }
        end
    end

    if state.search ~= "" then
        local needle = state.search:lower()
        local filtered = {}

        for _, row in ipairs(rows) do
            if row.name:lower():find(needle, 1, true) then
                filtered[#filtered + 1] = row
            end
        end
        rows = filtered
    end

    local sortBy = state.sortBy

    table.sort(rows, function(a, b)
        -- Age sorts ascending: freshest first is the useful direction.
        if sortBy == "age" then
            return a.age < b.age
        end

        if sortBy == "name" then
            if a.name ~= b.name then return a.name < b.name end
            return a.itemID < b.itemID
        end

        local left = a[sortBy] or 0
        local right = b[sortBy] or 0

        if left == right then return a.itemID < b.itemID end
        return left > right
    end)

    return rows
end

--------------------------------------------------------------------------------
-- Rows
--------------------------------------------------------------------------------

local function CreateRow(row)
    -- The item's icon beside its name, as the bags draw it.
    row.icon = Theme.CreateItemIcon(row, 16)
    row.icon:SetPoint("LEFT", 8, 0)

    row.name = Theme.CreateLabel(row, "small", "text")
    row.name:SetPoint("LEFT", 28, 0)

    row.cells = {}

    local offset = -8
    local reserved = 16

    for _, column in ipairs(COLUMNS) do
        local cell = Theme.CreateLabel(row, "small", "muted", "RIGHT")
        cell:SetPoint("RIGHT", offset, 0)
        cell:SetWidth(column.width)

        row.cells[column.key] = cell

        offset = offset - column.width - 6
        reserved = reserved + column.width + 6
    end

    row.name:SetPoint("RIGHT", row, "RIGHT", -reserved, 0)
end

local function UpdateRow(row, entry)
    entry.label = Util.GetItemLabel(entry.itemID)
    row.name:SetText(entry.label)
    Theme.SetItemIcon(row.icon, entry.itemID)

    local stale = ns.Prices:IsStale(entry.itemID)
    row.name:SetTextColor(Theme.Unpack(stale and "muted" or "text"))

    local cells = row.cells

    cells.market:SetText(Util.FormatMoney(entry.record.market, { short = true }))
    cells.market:SetTextColor(Theme.Unpack("text"))

    cells.min:SetText(Util.FormatMoney(entry.record.min, { short = true }))

    cells.quantity:SetText(Util.Comma(entry.quantity))

    if entry.liquidity then
        cells.liquidity:SetText(("%d%%"):format(math.floor(entry.liquidity * 100)))
        cells.liquidity:SetTextColor(Theme.Unpack(entry.liquidity > 0.15 and "profit" or "muted"))
    else
        -- One scan cannot show movement; say so rather than implying zero sales.
        cells.liquidity:SetText("--")
        cells.liquidity:SetTextColor(Theme.Unpack("dim"))
    end

    cells.age:SetText(Util.FormatAge(entry.record.seen and (time() - entry.record.seen)))
    cells.age:SetTextColor(Theme.Unpack(stale and "warn" or "dim"))
end

--------------------------------------------------------------------------------
-- History chart
--------------------------------------------------------------------------------

--- Bar chart of recorded market values.
--
-- Deliberately unscaled from zero: these are relative moves, and anchoring to
-- zero would flatten every real change on a realm where things cost coppers.
local function UpdateChart(detail, record)
    local history = record and record.history or {}

    for _, bar in ipairs(detail.bars) do
        bar:Hide()
    end

    if #history < 2 then
        detail.chartEmpty:Show()
        -- Or the last item's price range stays under "needs two scans".
        detail.chartRange:SetText("")
        return
    end

    detail.chartEmpty:Hide()

    local low, high = math.huge, 0
    for _, point in ipairs(history) do
        local value = point.m or 0
        if value < low then low = value end
        if value > high then high = value end
    end

    local span = math.max(1, high - low)

    local width = detail.chart:GetWidth()
    local height = detail.chart:GetHeight()
    local barWidth = math.max(2, (width / #history) - 2)

    for index, point in ipairs(history) do
        local bar = detail.bars[index]

        if not bar then
            bar = detail.chart:CreateTexture(nil, "ARTWORK")
            detail.bars[index] = bar
        end

        -- Floor at 2px so a flat series still reads as data rather than a gap.
        local fraction = ((point.m or 0) - low) / span
        local barHeight = math.max(2, fraction * (height - 2))

        bar:SetColorTexture(Theme.Unpack(index == #history and "accent" or "border"))
        bar:ClearAllPoints()
        bar:SetPoint("BOTTOMLEFT", detail.chart, "BOTTOMLEFT",
            (index - 1) * (barWidth + 2), 0)
        bar:SetSize(barWidth, barHeight)
        bar:Show()
    end

    detail.chartRange:SetText(("%s  to  %s"):format(
        Util.FormatMoney(low, { short = true }), Util.FormatMoney(high, { short = true })))
end

--------------------------------------------------------------------------------
-- Detail panel
--------------------------------------------------------------------------------

local function BuildDetail(parent)
    local detail = Theme.CreatePanel(parent, "window")
    detail:SetWidth(DETAIL_WIDTH)

    Theme.AccentStripe(detail, 2, 0.6)

    -- The item's icon beside its name, as on the other detail panes.
    local icon = Theme.CreateItemIcon(detail, 30)
    icon:SetPoint("TOPLEFT", 12, -12)
    detail.icon = icon

    local title = Theme.CreateLabel(detail, "large", "accent")
    title:SetPoint("TOPLEFT", 50, -12)
    title:SetPoint("TOPRIGHT", -12, -12)
    title:SetWordWrap(true)
    detail.title = title

    -- Rows start under the icon or the title, whichever is lower, back at
    -- the pane's left edge.
    local titleBlock = CreateFrame("Frame", nil, detail)
    titleBlock:SetPoint("TOPLEFT", 12, -12)
    titleBlock:SetPoint("RIGHT", detail, "RIGHT", -12, 0)
    titleBlock:SetHeight(30)
    detail.titleBlock = titleBlock

    local rowsAnchor = titleBlock

    detail.values = {}

    local function AddRow(key, labelText)
        local label = Theme.CreateLabel(detail, "small", "muted")
        label:SetPoint("TOPLEFT", rowsAnchor, "BOTTOMLEFT", 0, -8)

        local value = Theme.CreateLabel(detail, "small", "text", "RIGHT")
        value:SetPoint("TOPRIGHT", detail, "TOPRIGHT", -12, 0)
        value:SetPoint("TOP", label, "TOP", 0, 0)

        label:SetText(labelText)

        detail.values[key] = value
        detail.labels = detail.labels or {}
        detail.labels[key] = label
        rowsAnchor = label
        return value
    end

    AddRow("market", "Market value")
    AddRow("min", "Cheapest listing")
    AddRow("rival", "Cheapest rival")
    AddRow("own", "Your listing")
    AddRow("quantity", "Listed quantity")
    AddRow("scans", "Times scanned")
    AddRow("confidence", "Confidence")
    AddRow("liquidity", "Stock movement")

    -- Chart
    local chartHeading = Theme.CreateLabel(detail, "tiny", "dim")
    chartHeading:SetPoint("TOPLEFT", rowsAnchor, "BOTTOMLEFT", 0, -16)
    chartHeading:SetText("MARKET VALUE HISTORY")
    Theme.StyleHeading(chartHeading, detail)
    detail.historyHeading = chartHeading

    local chart = CreateFrame("Frame", nil, detail)
    chart:SetPoint("TOPLEFT", chartHeading, "BOTTOMLEFT", 0, -6)
    chart:SetPoint("RIGHT", detail, "RIGHT", -12, 0)
    chart:SetHeight(54)
    detail.chart = chart
    detail.bars = {}

    local chartEmpty = Theme.CreateLabel(chart, "tiny", "dim")
    chartEmpty:SetPoint("LEFT", 0, 0)
    chartEmpty:SetText("Needs at least two scans")
    detail.chartEmpty = chartEmpty

    local chartRange = Theme.CreateLabel(detail, "tiny", "dim")
    chartRange:SetPoint("TOPLEFT", chart, "BOTTOMLEFT", 0, -4)
    detail.chartRange = chartRange

    -- Actions
    detail.deepScan = Widgets.CreateButton(detail, "Deep scan", function()
        if not state.selected then return end

        local itemID = state.selected.itemID
        ns.Print(("scanning %s..."):format(Util.GetItemLabel(itemID)))

        ns.Scanner:ScanItem(itemID, function()
            UI:RefreshActiveTab()
        end)
    end, { width = 110, height = 24, primary = true,
           tooltip = "Read every listing of this item from the auction house" })
    detail.deepScan:SetPoint("BOTTOMLEFT", 12, 14)

    detail.searchAH = Widgets.CreateButton(detail, "Search AH", function()
        if not state.selected then return end
        UI:SearchAuctionHouse(state.selected.itemID)
    end, { width = 110, height = 24, tooltip = "Search the auction house for this item" })
    detail.searchAH:SetPoint("LEFT", detail.deepScan, "RIGHT", 8, 0)

    local empty = Theme.CreateLabel(detail, "small", "dim", "CENTER")
    empty:SetPoint("CENTER")
    empty:SetWidth(240)
    empty:SetWordWrap(true)
    empty:SetText("Select an item to see its price history")
    detail.empty = empty

    return detail
end

local function UpdateDetail(entry)
    local detail = widgets.detail
    local shown = entry ~= nil

    detail.empty:SetShown(not shown)
    detail.title:SetShown(shown)
    detail.icon:SetShown(shown)
    detail.chart:SetShown(shown)
    detail.chartRange:SetShown(shown)
    detail.deepScan:SetShown(shown)
    detail.searchAH:SetShown(shown)

    for _, value in pairs(detail.values) do
        value:SetShown(shown)
    end

    -- The labels go with their values: left up with nothing selected, they
    -- stood around the "Select an item" line saying nothing.
    for _, label in pairs(detail.labels or {}) do
        label:SetShown(shown)
    end
    if detail.historyHeading then detail.historyHeading:SetShown(shown) end

    if not shown then
        for _, bar in ipairs(detail.bars) do bar:Hide() end
        detail.chartEmpty:Hide()
        return
    end

    local record = ns.Prices:Get(entry.itemID) or entry.record

    detail.title:SetText(Util.GetItemLabel(entry.itemID))
    Theme.SetItemIcon(detail.icon, entry.itemID)

    -- A name that wraps to two lines pushes the rows down with it.
    local titleHeight = detail.title.GetStringHeight and detail.title:GetStringHeight() or 0
    detail.titleBlock:SetHeight(math.max(30, tonumber(titleHeight) or 0))

    detail.values.market:SetText(Util.FormatMoney(record.market))
    detail.values.min:SetText(Util.FormatMoney(record.min))

    if record.rivalMin then
        detail.values.rival:SetText(Util.FormatMoney(record.rivalMin))
        detail.values.rival:SetTextColor(Theme.Unpack("text"))
    else
        detail.values.rival:SetText("none listed")
        detail.values.rival:SetTextColor(Theme.Unpack("dim"))
    end

    if record.ownMin then
        detail.values.own:SetText(Util.FormatMoney(record.ownMin))
        detail.values.own:SetTextColor(Theme.Unpack(
            ns.Prices:HoldsLowest(entry.itemID) and "profit" or "loss"))
    else
        detail.values.own:SetText("none")
        detail.values.own:SetTextColor(Theme.Unpack("dim"))
    end

    detail.values.quantity:SetText(Util.Comma(record.quantity or 0))
    detail.values.scans:SetText(tostring(record.scans or 0))

    local confidence, reason = ns.Prices:GetConfidence(entry.itemID)
    -- No reason means nothing is holding the number down, so nothing is named.
    detail.values.confidence:SetText(("%d%%%s"):format(math.floor(confidence * 100),
        reason and ("  (" .. reason .. ")") or ""))
    detail.values.confidence:SetTextColor(Theme.Unpack(confidence > 0.6 and "profit" or "warn"))

    local liquidity = ns.Prices:GetLiquidity(entry.itemID)
    if liquidity then
        detail.values.liquidity:SetText(("%d%% per scan"):format(math.floor(liquidity * 100)))
        detail.values.liquidity:SetTextColor(Theme.Unpack("text"))
    else
        detail.values.liquidity:SetText("not enough scans")
        detail.values.liquidity:SetTextColor(Theme.Unpack("dim"))
    end

    detail.deepScan:SetEnabledState(ns.Scanner.isAuctionHouseOpen)
    detail.deepScan.tooltipText = ns.Scanner.isAuctionHouseOpen
        and "Read every listing of this item from the auction house"
        or "The auction house must be open"

    UpdateChart(detail, record)
end

--------------------------------------------------------------------------------
-- Refresh
--------------------------------------------------------------------------------

local function Refresh()
    if not widgets.list then return end

    local data = BuildList()
    widgets.list:SetData(data)

    widgets.emptyLabel:SetShown(#data == 0)
    if #data == 0 then
        widgets.emptyLabel:SetText(ns.Prices:Count() == 0
            and "No auction data yet. Open the auction house and press Scan."
            or "Nothing matches these filters.")
    end

    widgets.countLabel:SetText(("%s item%s priced"):format(
        Util.Comma(#data), #data == 1 and "" or "s"))

    UpdateDetail(state.selected)
end

--------------------------------------------------------------------------------
-- Build
--------------------------------------------------------------------------------

local function Build(container)
    local toolbar = CreateFrame("Frame", nil, container)
    toolbar:SetPoint("TOPLEFT", 8, -8)
    toolbar:SetPoint("TOPRIGHT", -8, -8)
    toolbar:SetHeight(24)

    local search = Widgets.CreateSearchBox(toolbar, "Search items", function(text)
        state.search = text or ""
        Refresh()
    end)
    search:SetPoint("LEFT", 0, 0)
    search:SetWidth(190)

    local reagentsOnly = Widgets.CreateCheckbox(toolbar, "Only what I craft with", function(checked)
        state.reagentsOnly = checked
        Refresh()
    end, false)
    reagentsOnly:SetPoint("LEFT", search, "RIGHT", 12, 0)

    local sort = Widgets.CreateDropdown(toolbar, {
        { text = "Sort: Market", value = "market" },
        { text = "Sort: Cheapest", value = "min" },
        { text = "Sort: Listed", value = "quantity" },
        { text = "Sort: Freshest", value = "age" },
        { text = "Sort: Name", value = "name" },
    }, function(value)
        state.sortBy = value
        Refresh()
    end, { width = 120 })
    sort:SetPoint("RIGHT", 0, 0)
    sort:SetValue("market")

    -- Column headings
    local headings = CreateFrame("Frame", nil, container)
    headings:SetPoint("TOPLEFT", toolbar, "BOTTOMLEFT", 0, -8)
    headings:SetPoint("TOPRIGHT", toolbar, "BOTTOMRIGHT", -DETAIL_WIDTH - 8, -8)
    headings:SetHeight(16)

    local nameHeading = Theme.CreateLabel(headings, "tiny", "muted")
    nameHeading:SetPoint("LEFT", 28, 0)
    nameHeading:SetText("ITEM")

    local offset = -8
    for _, column in ipairs(COLUMNS) do
        local heading = Theme.CreateLabel(headings, "tiny", "muted", "RIGHT")
        heading:SetPoint("RIGHT", offset, 0)
        heading:SetWidth(column.width)
        heading:SetText(column.label)
        offset = offset - column.width - 6
    end

    local divider = Theme.CreateDivider(container, "borderLit")
    divider:SetPoint("TOPLEFT", headings, "BOTTOMLEFT", 0, -2)
    divider:SetPoint("TOPRIGHT", headings, "BOTTOMRIGHT", 0, -2)

    local list = Widgets.CreateScrollList(container, {
        -- The headings move in with the rows when the scrollbar takes its room.
        onScrollbarShown = function(shown)
            headings:SetPoint("TOPRIGHT", toolbar, "BOTTOMRIGHT", -DETAIL_WIDTH - 8 - (shown and 10 or 0), -8)
        end,
        rowHeight = ROW_HEIGHT,
        createRow = CreateRow,
        updateRow = UpdateRow,
        onEnter = function(row, entry) Widgets.ShowItemOnly(row, entry.itemID, entry.label) end,
        onLeave = function() GameTooltip:Hide() end,
        -- The row the detail pane is showing stays lit.
        isSelected = function(entry)
            return state.selected ~= nil and entry.itemID == state.selected.itemID
        end,

        onClick = function(entry)
            state.selected = entry
            UpdateDetail(entry)
        end,
    })
    list:SetPoint("TOPLEFT", divider, "BOTTOMLEFT", 0, -4)
    list:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", -DETAIL_WIDTH - 16, 24)
    widgets.list = list

    local emptyLabel = Theme.CreateLabel(container, "small", "dim", "CENTER")
    emptyLabel:SetPoint("CENTER", list, "CENTER")
    emptyLabel:SetWidth(320)
    emptyLabel:SetWordWrap(true)
    widgets.emptyLabel = emptyLabel

    local countLabel = Theme.CreateLabel(container, "tiny", "dim")
    countLabel:SetPoint("BOTTOMLEFT", 8, 8)
    widgets.countLabel = countLabel

    local detail = BuildDetail(container)
    detail:SetPoint("TOPRIGHT", container, "TOPRIGHT", -8, -40)
    detail:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", -8, 8)
    widgets.detail = detail

    UpdateDetail(nil)
end

UI:RegisterTab({
    key = "prices",
    text = "Prices",
    order = 5,
    build = Build,
    refresh = Refresh,
})
