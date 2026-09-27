-- Blackthornes Tradeskills -- UI/Tab_Disenchanting.lua
-- Items on the auction house worth buying to disenchant.
--
-- Every weapon or piece of armour someone else has listed, priced at their
-- cheapest listing from your last scan, against what it breaks into. Profit
-- is the disenchant value less the auction house cut on selling the
-- materials, less the buy price. The numbers come from Logic/Disenchant.lua,
-- the same ones the Enchanting tab shows.
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

-- Right-aligned columns, laid out right to left.
local COLUMNS = {
    { key = "gain",   label = "PROFIT",     width = 66 },
    { key = "margin", label = "MARGIN",     width = 50 },
    { key = "value",  label = "DISENCHANT", width = 70 },
    { key = "buy",    label = "BUY",        width = 66 },
    { key = "skill",  label = "SKILL",      width = 40 },
    { key = "age",    label = "AGE",        width = 44 },
}

local state = {
    search = "",
    dealsOnly = true,
    hideTooHigh = false,
    selected = nil,
    hidden = 0,
}

local widgets = {}

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function Money(value)
    return Util.FormatMoney(value, { short = true })
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

    local name = ns.Disenchant:ItemName(entry.itemID)
    scanner:QueueBrowseQuery(name)

    ns.Print(("Searching the auction house for %s. Buy it in the auction house window at %s or less. If the list there does not change, type the name into its search box."):format(
        Util.GetItemLabel(entry.itemID), Util.FormatMoney(entry.buy, { noColor = true })))
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
        local cell = Theme.CreateLabel(row, "small", "text", "RIGHT")
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
        cell:SetText(Money(entry.gain))
        cell:SetTextColor(Theme.ProfitColor(entry.gain))
        return
    elseif key == "margin" then
        cell:SetText(MarginText(entry.margin))
        cell:SetTextColor(Theme.ProfitColor(entry.gain))
        return
    elseif key == "value" then
        text = Money(entry.value) .. (entry.partial and "+" or "")
        color = "text"
    elseif key == "buy" then
        text = Money(entry.buy)
    elseif key == "skill" then
        text = entry.needs and tostring(entry.needs) or ""
        -- Red when none of your characters can break it yet.
        color = entry.canDisenchant == false and "loss" or "dim"
    elseif key == "age" then
        text = entry.age and Util.FormatAge(entry.age) or ""
        color = entry.stale and "warn" or "dim"
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
    if entry.gain > 0 then
        GameTooltip:AddLine(("Buy at %s, disenchant, and sell the materials: about %s profit."):format(
            Util.FormatMoney(entry.buy, { noColor = true }),
            Util.FormatMoney(entry.gain, { noColor = true })), 0.35, 0.85, 0.45, true)
    else
        GameTooltip:AddLine(("Buying it to disenchant loses about %s."):format(
            Util.FormatMoney(-entry.gain, { noColor = true })), 0.85, 0.35, 0.35, true)
    end

    if entry.canDisenchant == false then
        GameTooltip:AddLine(("Needs Enchanting %d. Your best is %d (%s)."):format(
            entry.needs or 0, entry.enchanterSkill or 0, entry.enchanter or "?"), 0.85, 0.35, 0.35, true)
    elseif entry.canDisenchant == nil then
        GameTooltip:AddLine("None of your characters has Enchanting.", 0.85, 0.35, 0.35, true)
    end

    if entry.stale then
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

    local heading = Theme.CreateHeading(detail, "BREAKS INTO")
    heading:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", -38, -12)
    detail.heading = heading

    detail.outcomeLines = {}

    local summary = CreateFrame("Frame", nil, detail)
    summary:SetPoint("BOTTOMLEFT", 12, 110)
    summary:SetPoint("BOTTOMRIGHT", -12, 110)
    summary:SetHeight(70)
    detail.summary = summary

    local function SummaryRow(index)
        local label = Theme.CreateLabel(summary, "small", "muted")
        label:SetPoint("TOPLEFT", 0, -(index - 1) * 17)

        local value = Theme.CreateLabel(summary, "small", "text", "RIGHT")
        value:SetPoint("TOPRIGHT", 0, -(index - 1) * 17)

        return { label = label, value = value }
    end

    detail.lines = { SummaryRow(1), SummaryRow(2), SummaryRow(3), SummaryRow(4) }

    local verdict = Theme.CreateLabel(detail, "small", "profit")
    verdict:SetPoint("BOTTOMLEFT", summary, "TOPLEFT", 0, 6)
    verdict:SetPoint("BOTTOMRIGHT", summary, "TOPRIGHT", 0, 6)
    verdict:SetWordWrap(true)
    detail.verdict = verdict

    local note = Theme.CreateLabel(detail, "tiny", "dim")
    note:SetPoint("BOTTOMLEFT", 12, 44)
    note:SetPoint("BOTTOMRIGHT", -12, 44)
    note:SetWordWrap(true)
    note:SetJustifyV("BOTTOM")
    note:SetHeight(60)
    detail.note = note

    local searchButton = Widgets.CreateButton(detail, "Search the auction house", function()
        SearchAuctionHouse(state.selected)
    end, { width = 180, primary = true, height = 24 })
    searchButton:SetPoint("BOTTOMLEFT", 12, 14)
    searchButton.tooltipText = "Sends a search for this item, so it shows in the auction house list. Buying still takes your own click on the game's Buy button."
    detail.searchButton = searchButton

    local empty = Theme.CreateLabel(detail, "small", "dim", "CENTER")
    empty:SetPoint("CENTER")
    empty:SetWidth(DETAIL_WIDTH - 40)
    empty:SetWordWrap(true)
    empty:SetText("Pick a row to see what it breaks into")
    detail.empty = empty

    return detail
end

local function SetLine(line, label, value, color)
    line.label:SetShown(label ~= nil)
    line.value:SetShown(label ~= nil)
    if not label then return end

    line.label:SetText(label)
    line.value:SetText(value or "")
    line.value:SetTextColor(Theme.Unpack(color or "text"))
end

local function UpdateDetail(entry)
    local detail = widgets.detail
    local shown = entry ~= nil

    detail.empty:SetShown(not shown)

    for _, line in ipairs(detail.outcomeLines) do
        line.frame:Hide()
    end

    for _, part in ipairs({ detail.icon, detail.title, detail.subtitle, detail.heading,
                            detail.summary, detail.verdict, detail.note, detail.searchButton }) do
        part:SetShown(shown)
    end

    if not shown then return end

    detail.title:SetText(entry.name or ("item " .. tostring(entry.itemID)))
    Theme.SetItemIcon(detail.icon, entry.itemID)

    local breakdown = entry.breakdown or {}
    local facts = breakdown.facts or {}

    local who
    if entry.canDisenchant == nil then
        who = "None of your characters has Enchanting."
    else
        who = ("Your best is %d (%s)."):format(entry.enchanterSkill or 0, entry.enchanter or "?")
    end

    detail.subtitle:SetText(("Item level %d %s %s. Needs Enchanting about %d. %s"):format(
        facts.itemLevel or 0, facts.qualityName or "", facts.isWeapon and "weapon" or "armor",
        facts.skill or 0, who))
    detail.subtitle:SetTextColor(Theme.Unpack(entry.canDisenchant == true and "muted" or "loss"))

    local anchor = detail.heading
    for index, outcome in ipairs(breakdown.outcomes or {}) do
        local line = detail.outcomeLines[index]

        if not line then
            local frame = CreateFrame("Frame", nil, detail)
            frame:SetHeight(16)

            local icon = Theme.CreateItemIcon(frame, 14)
            icon:SetPoint("LEFT", 0, 0)

            local name = Theme.CreateLabel(frame, "small", "text")
            name:SetPoint("LEFT", 18, 0)
            name:SetPoint("RIGHT", -74, 0)

            local value = Theme.CreateLabel(frame, "small", "muted", "RIGHT")
            value:SetPoint("RIGHT", 0, 0)

            line = { frame = frame, icon = icon, name = name, value = value }
            detail.outcomeLines[index] = line
        end

        line.frame:ClearAllPoints()
        line.frame:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, index == 1 and -6 or 0)
        line.frame:SetPoint("TOPRIGHT", detail, "TOPRIGHT", -12, 0)

        local count = outcome.min == outcome.max and tostring(outcome.min)
            or ("%d-%d"):format(outcome.min, outcome.max)

        line.name:SetText(("%s%%  %sx %s"):format(Util.Round(outcome.chance * 100, 1), count,
            outcome.name or Util.GetItemLabel(outcome.itemID)))
        Theme.SetItemIcon(line.icon, outcome.itemID)

        if outcome.price then
            line.value:SetText(Money(outcome.price) .. " each")
            line.value:SetTextColor(Theme.Unpack("muted"))
        else
            line.value:SetText("no price")
            line.value:SetTextColor(Theme.Unpack("dim"))
        end

        line.frame:Show()
        anchor = line.frame
    end

    local lines = detail.lines
    SetLine(lines[1], entry.loneLow and "Buy for (a lone low listing)" or "Buy for",
        Util.FormatMoney(entry.buy), "text")
    SetLine(lines[2], "Disenchant value",
        Util.FormatMoney(entry.value) .. (entry.partial and "  or more" or ""), "text")
    SetLine(lines[3], "After the auction house cut", Util.FormatMoney(entry.net), "muted")
    SetLine(lines[4], "Profit", ("%s  (%s)"):format(Util.FormatMoney(entry.gain), MarginText(entry.margin)),
        entry.gain > 0 and "profit" or "loss")

    if entry.gain > 0 then
        detail.verdict:SetText(("Buying one to disenchant makes about %s."):format(
            Util.FormatMoney(entry.gain, { noColor = true })))
        detail.verdict:SetTextColor(Theme.Unpack("profit"))
    else
        detail.verdict:SetText(("Buying one to disenchant loses about %s."):format(
            Util.FormatMoney(-entry.gain, { noColor = true })))
        detail.verdict:SetTextColor(Theme.Unpack("loss"))
    end

    local note
    if facts.source == "yours" then
        note = ("Chances come from your own %d disenchants of items like this."):format(facts.casts or 0)
    else
        note = "Chances come from the Classic table built into the addon. It is an average: any one disenchant can give more or less."
    end
    note = note .. (" The buy price is the cheapest listing when last scanned (%s)."):format(
        entry.age and Util.FormatAgeAgo(entry.age) or "never")
    if entry.stale then note = note .. " That was a while ago, so it may have sold." end
    detail.note:SetText(note)
end

--------------------------------------------------------------------------------
-- List
--------------------------------------------------------------------------------

local function BuildRows()
    local rows, hidden = ns.Disenchant:GetAuctionRows({ profitableOnly = state.dealsOnly })
    state.hidden = hidden or 0

    if state.search == "" and not state.hideTooHigh then return rows end

    local needle = state.search:lower()
    local filtered = {}

    for _, row in ipairs(rows) do
        local matches = needle == "" or (row.name or ""):lower():find(needle, 1, true)
        local canDo = not state.hideTooHigh or row.canDisenchant == true

        if matches and canDo then filtered[#filtered + 1] = row end
    end

    return filtered
end

local function EmptyText()
    if state.search ~= "" then
        return ("Nothing matching \"%s\"."):format(state.search)
    end

    if (ns.Prices and ns.Prices:Count() or 0) == 0 then
        return "Scan the auction house to find items worth buying to disenchant."
    end

    if state.dealsOnly then
        local text = "Nothing on the auction house is worth buying to disenchant right now."

        if state.hidden > 0 then
            text = text .. (" %d more would make a little, but not enough for your minimums in Settings (%s profit, %d%% margin)."):format(
                state.hidden,
                Util.FormatMoney(ns.Config:Get("minProfit") or 0, { noColor = true, short = true }),
                ns.Config:Get("minMarginPercent") or 0)
        end

        return text .. " Untick \"Only deals over my minimums\" to see them all."
    end

    if state.hideTooHigh then
        return "Nothing listed that your enchanters can disenchant yet."
    end

    return "No weapons or armor from other sellers in your last scan."
end

local function Refresh()
    if not widgets.list then return end

    local rows = BuildRows()
    widgets.list:SetData(rows)

    widgets.emptyLabel:SetShown(#rows == 0)
    if #rows == 0 then widgets.emptyLabel:SetText(EmptyText()) end

    local deals, total = 0, 0
    for _, row in ipairs(rows) do
        if row.gain > 0 then
            deals = deals + 1
            total = total + row.gain
        end
    end

    if deals > 0 then
        widgets.countLabel:SetText(("%d deal%s, about %s if you buy them all"):format(
            deals, deals == 1 and "" or "s", Util.FormatMoney(total, { noColor = true, short = true })))
    else
        widgets.countLabel:SetText(("%d item%s"):format(#rows, #rows == 1 and "" or "s"))
    end

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
    local toolbar = CreateFrame("Frame", nil, container)
    toolbar:SetPoint("TOPLEFT", 8, -8)
    toolbar:SetPoint("TOPRIGHT", -8, -8)
    toolbar:SetHeight(24)

    local search = Widgets.CreateSearchBox(toolbar, "Search items", function(text)
        state.search = text or ""
        Refresh()
    end)
    search:SetPoint("LEFT", 0, 0)
    search:SetWidth(180)

    local dealsOnly = Widgets.CreateCheckbox(toolbar, "Only deals over my minimums", function(checked)
        state.dealsOnly = checked
        Refresh()
    end, state.dealsOnly)
    dealsOnly:SetPoint("LEFT", search, "RIGHT", 12, 0)
    widgets.dealsOnly = dealsOnly

    local hideTooHigh = Widgets.CreateCheckbox(toolbar, "Only ones I can disenchant", function(checked)
        state.hideTooHigh = checked
        Refresh()
    end, state.hideTooHigh)
    hideTooHigh:SetPoint("LEFT", dealsOnly, "RIGHT", 12, 0)
    widgets.hideTooHigh = hideTooHigh

    -- Column headings
    local headings = CreateFrame("Frame", nil, container)
    headings:SetPoint("TOPLEFT", toolbar, "BOTTOMLEFT", 0, -8)
    headings:SetPoint("TOPRIGHT", toolbar, "BOTTOMRIGHT", -DETAIL_WIDTH - 8, -8)
    headings:SetHeight(16)

    local nameHeading = Theme.CreateLabel(headings, "tiny", "muted")
    nameHeading:SetPoint("LEFT", 8 + ICON_GUTTER, 0)
    nameHeading:SetText("ITEM")

    local offset = -8
    for _, column in ipairs(COLUMNS) do
        local heading = Theme.CreateLabel(headings, "tiny", "muted", "RIGHT")
        heading:SetText(column.label)
        heading:SetPoint("RIGHT", offset, 0)
        heading:SetWidth(column.width)
        offset = offset - column.width - 6
    end

    local divider = Theme.CreateDivider(container, "borderLit")
    divider:SetPoint("TOPLEFT", headings, "BOTTOMLEFT", 0, -2)
    divider:SetPoint("TOPRIGHT", headings, "BOTTOMRIGHT", 0, -2)

    local list = Widgets.CreateScrollList(container, {
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

    local hint = Theme.CreateLabel(container, "tiny", "dim", "RIGHT")
    hint:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", -DETAIL_WIDTH - 16, 8)
    hint:SetText("Right-click an item to search the auction house for it")
    widgets.hint = hint

    local detail = BuildDetail(container)
    detail:SetPoint("TOPRIGHT", container, "TOPRIGHT", -8, -40)
    detail:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", -8, 8)
    widgets.detail = detail

    UpdateDetail(nil)

    -- Scanned items the client has not cached are left out until it has
    -- them. Redraw once they arrive, coalescing a burst into one pass.
    local redrawQueued = false

    ns.RegisterEvent(UI, "GET_ITEM_INFO_RECEIVED", function()
        if redrawQueued or not widgets.list:IsVisible() then return end

        redrawQueued = true
        C_Timer.After(1, function()
            redrawQueued = false
            Refresh()
        end)
    end)
end

UI:RegisterTab({
    key = "disenchanting",
    text = "Disenchanting",
    order = 1.8,
    build = Build,
    refresh = Refresh,
})
