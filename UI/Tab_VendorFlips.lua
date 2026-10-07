-- Blackthornes Tradeskills -- UI/Tab_VendorFlips.lua
-- Items on the auction house listed for less than a vendor pays, or, with
-- Sell to: Auction house, for well under what they usually sell for, to
-- buy and list again (Voldar's idea, 2026-10-06).
--
-- Every item someone else has listed, priced at their cheapest listing from
-- your last scan, against what any vendor gives for it. Profit is the vendor
-- price less the buy price, per item; there is no auction house cut, as the
-- item goes to a vendor. The numbers come from Logic/VendorFlips.lua.
--
-- The addon cannot buy for you: the game wants a real click on its own Buy
-- button for every purchase. What it can do is send the search, so the item
-- is in the auction house list ready to click.

local _, ns = ...

local Theme = ns.Theme
local Widgets = ns.Widgets
local Util = ns.Util

local UI = ns.UI

local ROW_HEIGHT = 22
local DETAIL_WIDTH = 300
local ICON_GUTTER = 20

-- Columns, laid out right to left. "sell" is what a vendor pays or what it
-- lists again for, and "extra" how many are listed or how well it sells, by
-- the Sell to menu. Money sits to the right, so its coins line up; the rest
-- is centred under its heading. `width` is the least each gets:
-- Widgets.FitColumns widens it to fit either heading and a full amount.
local COLUMNS = {
    { key = "gain",   label = "PROFIT", width = 66, money = true },
    { key = "margin", label = "MARGIN", width = 50, justify = "CENTER" },
    { key = "sell",   label = "VENDOR", auction = "RESELL", width = 66, money = true },
    { key = "buy",    label = "BUY",    width = 66, money = true },
    { key = "extra",  label = "LISTED", auction = "DEMAND", width = 44, justify = "CENTER" },
    { key = "age",    label = "AGE",    width = 44, justify = "CENTER" },
}

local SELL_TO = {
    { text = "Sell to: Vendor",       value = "vendor" },
    { text = "Sell to: Auction house", value = "auction" },
}

local state = {
    sellTo = "vendor",
    search = "",
    dealsOnly = true,
    selected = nil,
    hidden = 0,
    pending = 0,
    thin = 0,
}

local function Resale()
    return state.sellTo == "auction"
end

local widgets = {}

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

--- A price in a money column, measured into the cell: "1g 23s 45c" is wider
--- than the column and was cut off. It drops to the two largest coins, then
--- one, rounded.
local function SetMoney(cell, value)
    Theme.SetMoneyText(cell, value, { short = true })
end

local function MarginText(margin)
    return ("%d%%"):format(math.floor((margin or 0) * 100))
end

--- Send a search for this item, so it shows in the auction house list ready
--- to buy. Your own click on the game's Buy button still does the buying.
local function SearchAuctionHouse(entry)
    if not entry then return end

    local scanner = ns.Scanner
    if not scanner or not scanner.isAuctionHouseOpen then
        ns.Print("Open the auction house first, then search again.")
        return
    end

    if scanner.isScanning then
        ns.Print("A scan is running. Search again once it finishes.")
        return
    end

    -- The same search as the rest of the addon's item clicks: its own slot
    -- in the queue, at click priority. The scan's slot was shared, so this
    -- could replace a waiting scan (or a scan could drop this search).
    if not ns.UI:SearchAuctionHouse(entry.itemID) then return end

    if entry.kind == "auction" then
        ns.Print(("Searching the auction house for %s. Anything under %s each pays to list again at %s. If the list there does not change, type the name into its search box."):format(
            Util.GetItemLabel(entry.itemID), Util.FormatMoney(math.floor(entry.net), { noColor = true }),
            Util.FormatMoney(entry.resell, { noColor = true })))
        return
    end

    ns.Print(("Searching the auction house for %s. Anything at %s each or less is a vendor flip. If the list there does not change, type the name into its search box."):format(
        Util.GetItemLabel(entry.itemID), Util.FormatMoney(entry.vendor - 1, { noColor = true })))
end

--------------------------------------------------------------------------------
-- Rows
--------------------------------------------------------------------------------

local function CreateRow(row)
    row.icon = Theme.CreateItemIcon(row, 16)
    row.icon:SetPoint("LEFT", 8, 0)

    row.name = Theme.CreateLabel(row, "small", "text")
    row.name:SetPoint("LEFT", 8 + ICON_GUTTER, 0)

    row.cells = {}
    local offset = -8
    for index, column in ipairs(COLUMNS) do
        local cell = Theme.CreateLabel(row, "small", "text", column.justify or "RIGHT")
        cell:SetPoint("RIGHT", row, "RIGHT", offset, 0)
        cell:SetWidth(column.width)
        row.cells[index] = cell
        offset = offset - column.width - 6
    end

    row.name:SetPoint("RIGHT", row, "RIGHT", offset - 4, 0)
end

local function FillCell(cell, key, entry)
    local color = "muted"
    local text

    if key == "gain" then
        SetMoney(cell, entry.gain)
        cell:SetTextColor(Theme.ProfitColor(entry.gain))
        return
    elseif key == "margin" then
        cell:SetText(MarginText(entry.margin))
        cell:SetTextColor(Theme.ProfitColor(entry.gain))
        return
    elseif key == "sell" then
        SetMoney(cell, entry.sell)
        cell:SetTextColor(Theme.Unpack("text"))
        return
    elseif key == "buy" then
        SetMoney(cell, entry.buy)
        cell:SetTextColor(Theme.Unpack("muted"))
        return
    elseif key == "extra" and entry.kind == "auction" then
        text = ns.Demand:Label(entry.demand) or ""
        color = ns.Demand:Color(entry.demand)
    elseif key == "extra" then
        text = entry.listed and tostring(entry.listed) or ""
        color = "dim"
    elseif key == "age" then
        -- Read now, as the list itself can be kept for a while. "now"
        -- rather than "just now", which is wider than the column.
        local age = ns.Prices:GetAge(entry.itemID) or entry.age
        text = age and Util.FormatAge(age) or ""
        if text == "just now" then text = "now" end
        color = ns.Prices:IsStale(entry.itemID) and "warn" or "dim"
    end

    cell:SetText(text or "")
    cell:SetTextColor(Theme.Unpack(color))
end

local function UpdateRow(row, entry)
    row.name:SetText(entry.name or ("item " .. tostring(entry.itemID)))
    Theme.SetItemIcon(row.icon, entry.itemID)

    local r, g, b = Util.GetItemQualityColor(entry.itemID)
    if r then
        row.name:SetTextColor(r, g, b)
    else
        row.name:SetTextColor(Theme.Unpack("text"))
    end

    for index, column in ipairs(COLUMNS) do
        FillCell(row.cells[index], column.key, entry)
    end
end

local function ShowRowTooltip(row, entry)
    Widgets.ShowItemTooltip(row, "ANCHOR_LEFT", entry.itemID, entry.name)

    GameTooltip:AddLine(" ")
    if entry.kind == "auction" then
        GameTooltip:AddLine(("Buy at %s, list it again at %s: %s profit each after the cut."):format(
            Util.FormatMoney(entry.buy, { noColor = true }),
            Util.FormatMoney(entry.resell, { noColor = true }),
            Util.FormatMoney(entry.gain, { noColor = true })), 0.35, 0.85, 0.45, true)
        GameTooltip:AddLine(("Usually sells for %s (middle of %d scans)."):format(
            Util.FormatMoney(entry.usual, { noColor = true }), entry.scans - 1), 0.85, 0.85, 0.85, true)
        local demand = ns.Demand:TooltipText(entry.demand)
        if demand then GameTooltip:AddLine("Demand: " .. demand, 0.85, 0.85, 0.85, true) end
    else
        GameTooltip:AddLine(("Buy at %s, sell to any vendor for %s: %s profit each."):format(
            Util.FormatMoney(entry.buy, { noColor = true }),
            Util.FormatMoney(entry.vendor, { noColor = true }),
            Util.FormatMoney(entry.gain, { noColor = true })), 0.35, 0.85, 0.45, true)
    end

    -- Read now, as the AGE column is: the list can be kept for hours, and
    -- the warning it was built with never came on as the scan aged.
    if ns.Prices:IsStale(entry.itemID) then
        GameTooltip:AddLine("Scanned a while ago, so it may have sold.", 0.91, 0.76, 0.35, true)
    end

    GameTooltip:AddLine("Right-click to search the auction house for it.", 0.5, 0.5, 0.5)
    GameTooltip:Show()
end

--------------------------------------------------------------------------------
-- Detail panel
--------------------------------------------------------------------------------

local function BuildDetail(parent)
    local detail = Theme.CreatePanel(parent, "window")
    detail:SetWidth(DETAIL_WIDTH)

    Theme.AccentStripe(detail, 2, 0.6)

    local icon = Theme.CreateItemIcon(detail, 30)
    icon:SetPoint("TOPLEFT", 12, -12)
    detail.icon = icon

    local title = Theme.CreateLabel(detail, "large", "accent")
    title:SetPoint("TOPLEFT", 50, -12)
    title:SetPoint("TOPRIGHT", -12, -12)
    title:SetWordWrap(true)
    detail.title = title

    local subtitle = Theme.CreateLabel(detail, "small", "muted")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    subtitle:SetPoint("RIGHT", detail, "RIGHT", -12, 0)
    subtitle:SetWordWrap(true)
    detail.subtitle = subtitle

    local heading = Theme.CreateHeading(detail, "THE FLIP")
    heading:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", -38, -12)
    detail.heading = heading

    local summary = CreateFrame("Frame", nil, detail)
    summary:SetPoint("TOPLEFT", heading, "BOTTOMLEFT", 0, -8)
    summary:SetPoint("RIGHT", detail, "RIGHT", -12, 0)
    summary:SetHeight(69)
    detail.summary = summary

    local function SummaryRow(index)
        local label = Theme.CreateLabel(summary, "small", "muted")
        label:SetPoint("TOPLEFT", 0, -(index - 1) * 17)

        local value = Theme.CreateLabel(summary, "small", "text", "RIGHT")
        value:SetPoint("TOPRIGHT", 0, -(index - 1) * 17)

        return { label = label, value = value }
    end

    detail.lines = { SummaryRow(1), SummaryRow(2), SummaryRow(3), SummaryRow(4) }

    -- How much of what a vendor pays (or a resale pays) is profit: full
    -- when the item is free. Under the last summary line in use.
    local bar = Theme.CreateBar(detail, DETAIL_WIDTH - 24, 3)
    bar:SetPoint("TOPLEFT", summary, "TOPLEFT", 0, -54)
    detail.bar = bar

    local verdict = Theme.CreateLabel(detail, "small", "profit")
    verdict:SetPoint("TOPLEFT", bar.track, "BOTTOMLEFT", 0, -10)
    verdict:SetPoint("RIGHT", detail, "RIGHT", -12, 0)
    verdict:SetWordWrap(true)
    detail.verdict = verdict

    -- Under the verdict, as tall as its words. A box of fixed height pinned
    -- to the bottom had room for five lines, and the warning that the scan
    -- is old made six, so the warning itself was the line cut off.
    local note = Theme.CreateLabel(detail, "tiny", "dim")
    note:SetPoint("TOPLEFT", verdict, "BOTTOMLEFT", 0, -10)
    note:SetPoint("RIGHT", detail, "RIGHT", -12, 0)
    note:SetWordWrap(true)
    note:SetJustifyV("TOP")
    detail.note = note

    local searchButton = Widgets.CreateButton(detail, "Search the auction house", function()
        SearchAuctionHouse(state.selected)
    end, { width = 200, primary = true, height = 24 })
    searchButton:SetPoint("BOTTOMLEFT", 12, 14)
    searchButton.tooltipText = "Sends a search for this item, so it shows in the auction house list. Buying still takes your own click on the game's Buy button."
    detail.searchButton = searchButton

    local empty = Theme.CreateLabel(detail, "small", "dim", "CENTER")
    empty:SetPoint("CENTER")
    empty:SetWidth(DETAIL_WIDTH - 40)
    empty:SetWordWrap(true)
    empty:SetText("Pick a row to see the flip")
    detail.empty = empty

    return detail
end

local function SetLine(line, label, value, color)
    line.label:SetText(label)
    line.value:SetText(value or "")
    line.value:SetTextColor(Theme.Unpack(color or "text"))
end

--- The detail panel for a row bought to list again.
local function UpdateResaleDetail(detail, entry)
    local fourth = detail.lines[4]
    fourth.label:Show()
    fourth.value:Show()

    if entry.listed and entry.listed > 1 then
        detail.subtitle:SetText(("%d listed. Only the cheapest is sure to be at this price."):format(entry.listed))
    else
        detail.subtitle:SetText("One listed.")
    end

    local lines = detail.lines
    SetLine(lines[1], entry.loneLow and "Buy for (lone low)" or "Buy for",
        Util.FormatMoney(entry.buy), "text")
    SetLine(lines[2], "Usually sells for", Util.FormatMoney(entry.usual), "text")
    SetLine(lines[3], entry.capped and "List again at (next listing)" or "List again at",
        Util.FormatMoney(entry.resell), "text")
    SetLine(lines[4], "Profit each", ("%s  (%s)"):format(Util.FormatMoney(entry.gain), MarginText(entry.margin)),
        "profit")

    detail.bar:SetPoint("TOPLEFT", detail.summary, "TOPLEFT", 0, -71)
    detail.bar:Set(entry.resell > 0 and entry.gain / entry.resell or 0, "profit")

    local cut = math.floor((ns.Config:Get("auctionCut") or 0.05) * 100 + 0.5)
    local paid = entry.depositKnown and ("the %d%% cut and the deposit"):format(cut)
        or ("the %d%% cut"):format(cut)
    detail.verdict:SetText(("Buy it, list it again at %s, and keep about %s each after %s."):format(
        Util.FormatMoney(entry.resell, { noColor = true }), Util.FormatMoney(entry.gain, { noColor = true }), paid))

    local parts = {
        ("The usual price is the middle of the %d scans before the last one, so the cheap listing does not drag it down."):format(entry.scans - 1),
    }
    local demand = ns.Demand:TooltipText(entry.demand)
    if demand then parts[#parts + 1] = ("Demand: %s."):format(demand) end
    if not entry.depositKnown then
        parts[#parts + 1] = "The deposit is not known until you have listed one, so it is not counted yet."
    end
    parts[#parts + 1] = "Your gold is tied up until it sells."
    local age = ns.Prices:GetAge(entry.itemID) or entry.age
    parts[#parts + 1] = ("Scanned %s."):format(age and Util.FormatAgeAgo(age) or "never")
    if ns.Prices:IsStale(entry.itemID) then parts[#parts + 1] = "That was a while ago, so it may have sold." end
    detail.note:SetText(table.concat(parts, " "))
end

local function UpdateDetail(entry)
    local detail = widgets.detail
    local shown = entry ~= nil

    detail.empty:SetShown(not shown)

    for _, part in ipairs({ detail.icon, detail.title, detail.subtitle, detail.heading, detail.summary,
                            detail.verdict, detail.note, detail.searchButton }) do
        part:SetShown(shown)
    end

    if not shown then
        detail.bar:Set(nil)
        return
    end

    detail.title:SetText(entry.name or ("item " .. tostring(entry.itemID)))
    Theme.SetItemIcon(detail.icon, entry.itemID)

    if entry.kind == "auction" then
        UpdateResaleDetail(detail, entry)
        return
    end

    detail.lines[4].label:Hide()
    detail.lines[4].value:Hide()
    detail.bar:SetPoint("TOPLEFT", detail.summary, "TOPLEFT", 0, -54)

    if entry.listed and entry.listed > 1 then
        detail.subtitle:SetText(("%d listed. Only the cheapest is sure to be at this price."):format(entry.listed))
    else
        detail.subtitle:SetText("One listed.")
    end

    -- Short enough to stay clear of the price on its right; the longer
    -- "(a lone low listing)" ran over it.
    local lines = detail.lines
    SetLine(lines[1], entry.loneLow and "Buy for (lone low)" or "Buy for",
        Util.FormatMoney(entry.buy), "text")
    SetLine(lines[2], "A vendor pays", Util.FormatMoney(entry.vendor), "text")
    SetLine(lines[3], "Profit each", ("%s  (%s)"):format(Util.FormatMoney(entry.gain), MarginText(entry.margin)),
        "profit")

    detail.bar:Set(entry.vendor > 0 and entry.gain / entry.vendor or 0, "profit")

    detail.verdict:SetText(("Buy it, sell it to any vendor, and keep about %s each. No auction house cut."):format(
        Util.FormatMoney(entry.gain, { noColor = true })))

    -- The scan's age read now, as the AGE column reads it: the list can be
    -- kept for hours, and the age it was built with went on saying "2m ago".
    local age = ns.Prices:GetAge(entry.itemID) or entry.age
    local note = ("The buy price is the cheapest listing from another seller when last scanned (%s). Prices are per item, so a stack pays the same on every one in it."):format(
        age and Util.FormatAgeAgo(age) or "never")
    if ns.Prices:IsStale(entry.itemID) then note = note .. " That was a while ago, so it may have sold." end
    detail.note:SetText(note)
end

--------------------------------------------------------------------------------
-- List
--------------------------------------------------------------------------------

-- The last full list and what it was built from. Walking every scanned item
-- is only done again when something it depends on has changed: a redraw for
-- a bag change or an auction event reuses it (the lesson the Disenchanting
-- tab paid for with Ready to sell).
local built = { key = nil, rows = nil, hidden = 0, pending = 0 }

local function BuildKey()
    return table.concat({
        tostring(ns.Prices and ns.Prices.changes or 0),
        tostring(ns.Prices and ns.Prices:Count() or 0),
        tostring(ns.Disenchant.factsVersion or 0),
        tostring(state.dealsOnly),
        state.sellTo,
        tostring(ns.Config:Get("minProfit")),
        tostring(ns.Config:Get("minMarginPercent")),
        tostring(ns.Scanner and ns.Scanner.isAuctionHouseOpen and true or false),
    }, "|")
end

local function BuildRows()
    local key = BuildKey()

    if key ~= built.key then
        local rows, hidden, pending, thin
        if Resale() then
            rows, hidden, thin = ns.VendorFlips:GetResaleRows({ profitableOnly = state.dealsOnly })
        else
            rows, hidden, pending = ns.VendorFlips:GetAuctionRows({ profitableOnly = state.dealsOnly })
        end
        built.key, built.rows, built.hidden, built.pending, built.thin =
            key, rows, hidden or 0, pending or 0, thin or 0

        -- For /bts vendordeals: what the tab is showing and when it was built.
        ns.VendorFlips.shownRows, ns.VendorFlips.shownBuiltAt = rows, time()
    end

    local rows = built.rows
    state.hidden = built.hidden
    state.pending = built.pending
    state.thin = built.thin

    if state.search == "" then return rows end

    local needle = state.search:lower()
    local filtered = {}

    for _, row in ipairs(rows) do
        if (row.name or ""):lower():find(needle, 1, true) then filtered[#filtered + 1] = row end
    end

    return filtered
end

local function EmptyText()
    if state.search ~= "" then
        return ("Nothing matching \"%s\"."):format(state.search)
    end

    if (ns.Prices and ns.Prices:Count() or 0) == 0 then
        return Resale() and "Scan the auction house to find items listed well under their usual price."
            or "Scan the auction house to find items listed for less than a vendor pays."
    end

    if state.dealsOnly and state.hidden > 0 then
        return ("Nothing clears your minimums in Settings (%s profit, %d%% margin). %d more would make a little. Untick \"Only deals over my minimums\" to see them."):format(
            Util.FormatMoney(ns.Config:Get("minProfit") or 0, { noColor = true, short = true }),
            ns.Config:Get("minMarginPercent") or 0, state.hidden)
    end

    if Resale() then
        local text = "Nothing on the auction house is under its usual price by more than the cut right now."
        if (state.thin or 0) > 0 then
            text = text .. (" %d more are cheap, but have fewer than %d scans, little demand, or are grey. Scan again over the next days to build up their history.")
                :format(state.thin, ns.VendorFlips.MIN_RESALE_SCANS)
        end
        return text
    end

    return "Nothing on the auction house is listed for less than a vendor pays right now."
end

local function Refresh()
    if not widgets.list then return end

    if widgets.headingLabels then
        for _, column in ipairs(COLUMNS) do
            widgets.headingLabels[column.key]:SetText(Resale() and column.auction or column.label)
        end
        -- The arrow sits beside the words, which may just have changed.
        if widgets.sorter then widgets.sorter:Sync() end
    end

    local rows = BuildRows()
    -- A clicked heading's order over the list's own.
    if widgets.sorter then rows = widgets.sorter:Sort(rows) end
    widgets.list:SetData(rows)

    widgets.emptyLabel:SetShown(#rows == 0)
    if #rows == 0 then widgets.emptyLabel:SetText(EmptyText()) end

    local total = 0
    for _, row in ipairs(rows) do total = total + row.gain end

    -- Each part of the count line from its full wording to its shortest.
    -- The line takes the first whole wording that fits beside the hint,
    -- rather than running on and ending in "...".
    local flips
    if #rows > 0 then
        local plural = #rows == 1 and "" or "s"
        local money = Util.FormatMoney(total, { noColor = true, short = true })
        flips = {
            ("%d flip%s, about %s if you buy one of each"):format(#rows, plural, money),
            ("%d flip%s, about %s for one of each"):format(#rows, plural, money),
            ("%d flip%s"):format(#rows, plural),
        }
    end

    -- Items whose vendor price is not read yet wait for the auction house to
    -- close, so reading them cannot upset Ready to sell. Say so, or the list
    -- looks short.
    local pending
    if Resale() and (state.thin or 0) > 0 then
        pending = {
            ("%d more held back: few scans or little demand"):format(state.thin),
            ("%d held back"):format(state.thin),
        }
    elseif (state.pending or 0) > 0 then
        local waiting = ns.Scanner and ns.Scanner.isAuctionHouseOpen
            and "read once the auction house is closed"
            or "reading them now"
        pending = {
            ("%d listed items with no vendor price yet, %s"):format(state.pending, waiting),
            ("%d waiting for a vendor price"):format(state.pending),
        }
    end

    local texts = { "" }
    if flips and pending then
        local sep = "  ·  "
        texts = { flips[1] .. sep .. pending[1], flips[1] .. sep .. pending[2],
            flips[2] .. sep .. pending[2], flips[3] .. sep .. pending[2] }
    elseif flips or pending then
        texts = flips or pending
    end
    Theme.FitText(widgets.countLabel, texts)

    local fresh
    if state.selected then
        for _, row in ipairs(rows) do
            if row.itemID == state.selected.itemID then
                fresh = row
                break
            end
        end
    end

    state.selected = fresh
    UpdateDetail(fresh)
end

--------------------------------------------------------------------------------
-- Build
--------------------------------------------------------------------------------

local function Build(container)
    -- Before any row or heading is laid out: they read these widths. Each
    -- column fits whichever heading the Sell to menu gives it.
    if Widgets.FitColumns then
        Widgets.FitColumns(COLUMNS, function(column) return { column.label, column.auction } end)
    end

    local toolbar = CreateFrame("Frame", nil, container)
    toolbar:SetPoint("TOPLEFT", 8, -8)
    toolbar:SetPoint("TOPRIGHT", -8, -8)
    toolbar:SetHeight(24)

    -- A new search or filter is a different list, so it starts at the top.
    -- The list keeps its place on the redraws that bag and auction events
    -- cause, which left a new search showing its results part way down.
    local function ShowFromTop()
        Refresh()
        if widgets.list then widgets.list:ScrollToTop() end
    end

    -- Option bar: the menu, then search, then the tick box (Ezmode,
    -- 2026-10-06).
    local sellTo = Widgets.CreateDropdown(toolbar, SELL_TO, function(value)
        state.sellTo = value
        state.selected = nil
        ShowFromTop()
    end, { width = 180 })
    sellTo:SetPoint("LEFT", 0, 0)
    sellTo:SetValue(state.sellTo, true)
    widgets.sellTo = sellTo

    local search = Widgets.CreateSearchBox(toolbar, "Search items", function(text)
        state.search = text or ""
        ShowFromTop()
    end)
    search:SetPoint("LEFT", sellTo, "RIGHT", 8, 0)
    search:SetWidth(Widgets.SEARCH_WIDTH)

    local dealsOnly = Widgets.CreateCheckbox(toolbar, "Only deals over my minimums", function(checked)
        state.dealsOnly = checked
        ShowFromTop()
    end, state.dealsOnly)
    dealsOnly:SetPoint("LEFT", search, "RIGHT", 12, 0)
    widgets.dealsOnly = dealsOnly

    -- Column headings
    local headings = CreateFrame("Frame", nil, container)
    headings:SetPoint("TOPLEFT", toolbar, "BOTTOMLEFT", 0, -8)
    headings:SetPoint("TOPRIGHT", toolbar, "BOTTOMRIGHT", -DETAIL_WIDTH - 8, -8)
    headings:SetHeight(16)

    local nameHeading = Theme.CreateLabel(headings, "tiny", "muted")
    nameHeading:SetPoint("LEFT", 8 + ICON_GUTTER, 0)
    nameHeading:SetText("ITEM")

    local sortLabels, values = { name = nameHeading }, {}
    local offset = -8
    for _, column in ipairs(COLUMNS) do
        local heading = Theme.CreateLabel(headings, "tiny", "muted", column.justify or "RIGHT")
        heading:SetText(column.label)
        heading:SetPoint("RIGHT", offset, 0)
        heading:SetWidth(column.width)
        sortLabels[column.key] = heading
        offset = offset - column.width - 6
    end
    widgets.headingLabels = {}
    for _, column in ipairs(COLUMNS) do widgets.headingLabels[column.key] = sortLabels[column.key] end

    -- Click a heading to sort by it; each column shows the row field it is
    -- named for.
    for key in pairs(sortLabels) do
        values[key] = function(row) return row[key] end
    end
    widgets.sorter = Widgets.SortableHeadings and Widgets.SortableHeadings(sortLabels, values,
        function() Refresh() end)
    if widgets.sorter then widgets.sorter:SetText({ "name" }) end

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

        onEnter = function(row, entry) ShowRowTooltip(row, entry) end,
        onLeave = function() GameTooltip:Hide() end,

        isSelected = function(entry)
            return state.selected and entry.itemID == state.selected.itemID
        end,

        onClick = function(entry, _, mouseButton)
            state.selected = entry
            UpdateDetail(entry)

            if mouseButton == "RightButton" then SearchAuctionHouse(entry) end
        end,
    })

    list:SetPoint("TOPLEFT", divider, "BOTTOMLEFT", 0, -4)
    list:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", -DETAIL_WIDTH - 16, 24)
    widgets.list = list

    local emptyLabel = Theme.CreateLabel(container, "small", "dim", "CENTER")
    emptyLabel:SetPoint("CENTER", list, "CENTER", 0, 10)
    emptyLabel:SetWidth(380)
    emptyLabel:SetWordWrap(true)
    widgets.emptyLabel = emptyLabel

    local countLabel = Theme.CreateLabel(container, "tiny", "dim")
    countLabel:SetPoint("BOTTOMLEFT", 8, 8)
    widgets.countLabel = countLabel

    -- Short, to leave the count line room; each row's tooltip says the same
    -- at length.
    local hint = Theme.CreateLabel(container, "tiny", "dim", "RIGHT")
    hint:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", -DETAIL_WIDTH - 16, 8)
    hint:SetText("Right-click a row to search for it")
    widgets.hint = hint

    -- The count line grows a long "not checked yet" note while items load,
    -- and ran under this hint. It stops short of it now, and Refresh picks
    -- a wording that fits.
    countLabel:SetPoint("RIGHT", hint, "LEFT", -12, 0)
    countLabel:SetJustifyH("LEFT")
    countLabel:SetWordWrap(false)

    local detail = BuildDetail(container)
    detail:SetPoint("TOPRIGHT", container, "TOPRIGHT", -8, -40)
    detail:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", -8, 8)
    widgets.detail = detail

    UpdateDetail(nil)

    -- Vendor prices not read yet are asked for a few dozen a second. Redraw
    -- as they arrive, coalescing a burst into one pass.
    local redrawQueued = false

    ns.RegisterEvent(widgets, "GET_ITEM_INFO_RECEIVED", function(_, _, itemID)
        if redrawQueued or not widgets.list:IsVisible() then return end

        -- Only for items the addon asked for, not every item any window loads.
        if itemID and not ns.Disenchant:WasRequested(itemID) then return end

        redrawQueued = true
        C_Timer.After(1, function()
            redrawQueued = false
            Refresh()
        end)
    end)

    -- Items new to the tab wait while the auction house is open. Read them
    -- as soon as it closes rather than whenever something next redraws.
    ns.RegisterEvent(widgets, "AUCTION_HOUSE_CLOSED", function()
        if not widgets.list:IsVisible() then return end
        C_Timer.After(0.5, Refresh)
    end)
end

UI:RegisterTab({
    key = "vendorflips",
    text = "Vendor Flips",
    order = 1.9,
    build = Build,
    refresh = Refresh,
})
