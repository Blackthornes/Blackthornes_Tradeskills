-- Blackthornes Tradeskills -- UI/DealsFavor.lua
-- The Deals tab's Merchant's Favor view: Waylaid Crates by what a favor costs.
--
-- A player's idea (2026-10-08), from their spreadsheet. Each row is a crate:
-- what it costs on the auction house, its cheapest bundle, the silver its
-- turn-in pays back, and what that makes one point of Merchant's Favor
-- cost. The sums are Logic/MerchantsFavor.lua. Tab_Deals.lua shows this in
-- place of its flips when its Show menu says so, and owns the option bar.

local _, ns = ...

local Theme = ns.Theme
local Widgets = ns.Widgets
local Util = ns.Util

local DealsFavor = ns.NewModule("DealsFavor")

local ROW_HEIGHT = 22
local DETAIL_WIDTH = 300
local ICON_GUTTER = 20
local BUNDLE_LINES = 5

-- Columns, laid out right to left, as on the flips list.
local COLUMNS = {
    { key = "perFavor",   label = "PER FAVOR", width = 70, money = true },
    { key = "total",      label = "TOTAL",     width = 66, money = true },
    { key = "bundleCost", label = "BUNDLE",    width = 66, money = true },
    { key = "cratePrice", label = "CRATE",     width = 66, money = true },
    { key = "favor",      label = "FAVOR",     width = 44, justify = "CENTER" },
}

-- Any column but the crate's name can be hidden (UI/Columns.lua).
ns.Columns:Register("favor", "Deals: Merchant's Favor", COLUMNS)

local state = {
    search = "",
    skipOverStack = nil,    -- read from Settings the first time it is asked
    selected = nil,
}

local widgets = {}

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function Money(value)
    return Util.FormatMoney(value, { short = true })
end

local function Plain(value)
    return Util.FormatMoney(value, { noColor = true })
end

--- A whole copper, for a favor's share of a crate.
local function Round(value)
    return value and math.floor(value + 0.5) or nil
end

--- The item's plain name, or "item N" until the client has it.
local function ItemName(itemID)
    if Util.HasFunction("C_Item.GetItemInfo") then
        local ok, name = pcall(C_Item.GetItemInfo, itemID)
        if ok and type(name) == "string" then return name end
        if Util.HasFunction("C_Item.RequestLoadItemDataByID") then
            pcall(C_Item.RequestLoadItemDataByID, itemID)
        end
    end
    return "item " .. tostring(itemID)
end

local function BundleText(bundle)
    return ("%d %s"):format(bundle.count, ItemName(bundle.itemID))
end

--- Where the reward came from, in a few words.
local function RewardText(row)
    if row.source == "learned" then
        local times = row.turnIns == 1 and "one turn-in" or ("%d turn-ins"):format(row.turnIns or 1)
        return ("%d favor and %s, seen paid on %s."):format(row.favor, Plain(row.money or 0), times)
    elseif row.source == "reported" then
        return ("Players report %d favor and %s. Not seen paid here yet."):format(row.favor, Plain(row.money or 0))
    end
    return "Not in the game yet, so nobody knows what it pays."
end

local function SameRow(a, b)
    return a and b and a.key == b.key
end

--- Send a search for one item, so it shows in the auction house list.
local function Search(itemID, what)
    local scanner = ns.Scanner
    if not scanner or not scanner.isAuctionHouseOpen then
        ns.Print("Open the auction house first, then search again.")
        return
    end
    if scanner.isScanning then
        ns.Print("A scan is running. Search again once it finishes.")
        return
    end
    if not itemID then
        ns.Print(("The game has not shown this addon %s yet, so type its name into the auction house search box."):format(what))
        return
    end
    ns.UI:SearchAuctionHouse(itemID)
end

local function SearchCrate(row)
    if not row then return end
    Search(row.itemID, "this crate")
end

local function SearchBundle(row)
    if not row or not row.best then return end
    Search(row.best.itemID, "this material")
end

--------------------------------------------------------------------------------
-- Rows
--------------------------------------------------------------------------------

--- The shown columns from the right edge; the name has the rest.
local function PlaceRow(row)
    local offset = ns.Columns:Place("favor", COLUMNS, row.cells, { byIndex = true })
    row.name:SetPoint("RIGHT", row, "RIGHT", offset - 4, 0)
    row.columnsVersion = ns.Columns.version
end

local function CreateRow(row)
    row.icon = Theme.CreateItemIcon(row, 16)
    row.icon:SetPoint("LEFT", 8, 0)

    row.name = Theme.CreateLabel(row, "small", "text")
    row.name:SetPoint("LEFT", 8 + ICON_GUTTER, 0)

    row.cells = {}
    for index, column in ipairs(COLUMNS) do
        row.cells[index] = Theme.CreateLabel(row, "small", "text", column.justify or "RIGHT")
    end

    PlaceRow(row)
end

local function FillCell(cell, key, entry)
    if key == "favor" then
        cell:SetText(entry.favor and tostring(entry.favor) or "?")
        cell:SetTextColor(Theme.Unpack(entry.source == "learned" and "text"
            or entry.source == "reported" and "muted" or "warn"))
        return
    end

    local value = entry[key]
    if key == "perFavor" then value = Round(value) end
    cell:SetText(value and Money(value) or "")
    cell:SetTextColor(Theme.Unpack(key == "perFavor" and "accent" or key == "total" and "text" or "muted"))
end

local function UpdateRow(row, entry)
    if row.columnsVersion ~= ns.Columns.version then PlaceRow(row) end

    Theme.SetRowName(row.name, entry.have > 0 and ("%s  (%d)"):format(entry.name, entry.have) or entry.name)
    Theme.SetItemIcon(row.icon, entry.itemID or (entry.best and entry.best.itemID))
    row.name:SetTextColor(Theme.Unpack(entry.perFavor and "text" or "dim"))

    for index, column in ipairs(COLUMNS) do
        FillCell(row.cells[index], column.key, entry)
    end
end

local function ShowRowTooltip(row, entry)
    if entry.itemID then
        Widgets.ShowItemTooltip(row, "ANCHOR_LEFT", entry.itemID, entry.name)
    else
        GameTooltip:SetOwner(row, "ANCHOR_LEFT")
        GameTooltip:AddLine("Waylaid Crate: " .. entry.name)
    end

    GameTooltip:AddLine(" ")
    if entry.total and entry.best then
        GameTooltip:AddLine(("Crate %s + %s %s - %s back = %s."):format(
            Plain(entry.cratePrice), BundleText(entry.best), Plain(entry.best.cost),
            Plain(entry.money or 0), Plain(entry.total)), 0.85, 0.85, 0.85, true)
    end
    if entry.perFavor then
        GameTooltip:AddLine(("%s for each favor."):format(Plain(Round(entry.perFavor))), 0.35, 0.85, 0.45, true)
    end
    GameTooltip:AddLine(RewardText(entry), 0.7, 0.7, 0.7, true)
    if entry.have > 0 then
        GameTooltip:AddLine(("You carry %d."):format(entry.have), 0.85, 0.85, 0.85)
    end
    GameTooltip:AddLine("Right-click to search the auction house for the crate.", 0.5, 0.5, 0.5)
    GameTooltip:Show()
end

--------------------------------------------------------------------------------
-- Detail panel
--------------------------------------------------------------------------------

local function Lines(parent, count)
    local block = CreateFrame("Frame", nil, parent)
    block.lines = {}

    for index = 1, count do
        local label = Theme.CreateLabel(block, "small", "muted")
        label:SetPoint("TOPLEFT", 0, -(index - 1) * 17)
        label:SetPoint("RIGHT", block, "RIGHT", -84, 0)
        label:SetWordWrap(false)

        local value = Theme.CreateLabel(block, "small", "text", "RIGHT")
        value:SetPoint("TOPRIGHT", 0, -(index - 1) * 17)
        value:SetWidth(80)

        block.lines[index] = { label = label, value = value }
    end

    block:SetHeight(count * 17)
    return block
end

local function SetLine(line, label, value, labelColor, valueColor)
    line.label:SetShown(label ~= nil)
    line.value:SetShown(label ~= nil)
    if not label then return end

    -- A long material name ("16 Handful of Copper Bolts") goes smaller
    -- rather than ending in "...".
    Theme.SetRowName(line.label, label)
    line.label:SetTextColor(Theme.Unpack(labelColor or "muted"))
    line.value:SetText(value or "")
    line.value:SetTextColor(Theme.Unpack(valueColor or "text"))
end

local function BuildDetail(parent)
    local detail = Theme.CreatePanel(parent, "window")
    detail:SetWidth(DETAIL_WIDTH)
    Theme.AccentStripe(detail, 2, 0.6)

    detail.icon = Theme.CreateItemIcon(detail, 30)
    detail.icon:SetPoint("TOPLEFT", 12, -12)

    detail.title = Theme.CreateLabel(detail, "large", "accent")
    detail.title:SetPoint("TOPLEFT", 50, -12)
    detail.title:SetPoint("TOPRIGHT", -12, -12)
    detail.title:SetWordWrap(true)

    detail.subtitle = Theme.CreateLabel(detail, "small", "muted")
    detail.subtitle:SetPoint("TOPLEFT", detail.title, "BOTTOMLEFT", 0, -4)
    detail.subtitle:SetPoint("RIGHT", detail, "RIGHT", -12, 0)
    detail.subtitle:SetWordWrap(true)

    detail.bundleHeading = Theme.CreateHeading(detail, "FILL IT WITH ONE OF")
    detail.bundleHeading:SetPoint("TOPLEFT", detail.subtitle, "BOTTOMLEFT", -38, -12)

    detail.bundles = Lines(detail, BUNDLE_LINES)
    detail.bundles:SetPoint("TOPLEFT", detail.bundleHeading, "BOTTOMLEFT", 0, -8)
    detail.bundles:SetPoint("RIGHT", detail, "RIGHT", -12, 0)

    detail.costHeading = Theme.CreateHeading(detail, "ONE FAVOR")
    detail.costHeading:SetPoint("TOPLEFT", detail.bundles, "BOTTOMLEFT", 0, -12)

    detail.sums = Lines(detail, 4)
    detail.sums:SetPoint("TOPLEFT", detail.costHeading, "BOTTOMLEFT", 0, -8)
    detail.sums:SetPoint("RIGHT", detail, "RIGHT", -12, 0)

    detail.note = Theme.CreateLabel(detail, "tiny", "dim")
    detail.note:SetPoint("TOPLEFT", detail.sums, "BOTTOMLEFT", 0, -10)
    detail.note:SetPoint("RIGHT", detail, "RIGHT", -12, 0)
    detail.note:SetWordWrap(true)
    detail.note:SetJustifyV("TOP")

    detail.crateButton = Widgets.CreateButton(detail, "Search crate", function()
        SearchCrate(state.selected)
    end, { width = 134, primary = true, height = 24 })
    detail.crateButton:SetPoint("BOTTOMLEFT", 12, 14)
    detail.crateButton.tooltipText = "Sends a search for this crate, so it shows in the auction house list. Buying still takes your own click on the game's Buy button."

    detail.bundleButton = Widgets.CreateButton(detail, "Search bundle", function()
        SearchBundle(state.selected)
    end, { width = 134, height = 24 })
    detail.bundleButton:SetPoint("LEFT", detail.crateButton, "RIGHT", 8, 0)
    detail.bundleButton.tooltipText = "Sends a search for the cheapest bundle's material."

    detail.empty = Theme.CreateLabel(detail, "small", "dim", "CENTER")
    detail.empty:SetPoint("CENTER")
    detail.empty:SetWidth(DETAIL_WIDTH - 40)
    detail.empty:SetWordWrap(true)
    detail.empty:SetText("Pick a crate to see what fills it and what a favor costs")

    return detail
end

local function UpdateDetail(entry)
    local detail = widgets.detail
    local shown = entry ~= nil

    detail.empty:SetShown(not shown)
    for _, part in ipairs({ detail.icon, detail.title, detail.subtitle, detail.bundleHeading, detail.bundles,
            detail.costHeading, detail.sums, detail.note, detail.crateButton, detail.bundleButton }) do
        part:SetShown(shown)
    end
    if not shown then return end

    detail.title:SetText(entry.name)
    Theme.SetItemIcon(detail.icon, entry.itemID or (entry.best and entry.best.itemID))
    detail.subtitle:SetText(RewardText(entry))
    detail.subtitle:SetTextColor(Theme.Unpack(entry.source == "learned" and "text"
        or entry.source == "reported" and "muted" or "warn"))

    local overStack = false
    for index = 1, BUNDLE_LINES do
        local bundle = entry.bundles[index]
        local line = detail.bundles.lines[index]
        if bundle then
            local label = BundleText(bundle)
            local labelColor, valueColor = "muted", "muted"
            if bundle.best then
                labelColor, valueColor = "text", "profit"
            elseif bundle.overStack then
                labelColor, valueColor = "dim", "dim"
            end
            if bundle.vendor then label = label .. " (vendor)" end
            if bundle.overStack then
                label = label .. " *"
                overStack = true
            end
            SetLine(line, label, bundle.cost and Plain(bundle.cost) or "not priced", labelColor, valueColor)
        else
            SetLine(line, nil)
        end
    end

    local sums = detail.sums.lines
    SetLine(sums[1], "Crate on the AH", entry.cratePrice and Plain(entry.cratePrice) or "not priced")
    SetLine(sums[2], "Cheapest bundle", entry.bundleCost and Plain(entry.bundleCost) or "not priced")
    SetLine(sums[3], "Silver back", entry.money and Plain(entry.money) or "not known")
    SetLine(sums[4], entry.favor and ("Each of %d favor"):format(entry.favor) or "Each favor",
        entry.perFavor and Plain(Round(entry.perFavor)) or "not known", "text", "accent")

    local parts = {}
    if overStack then
        parts[#parts + 1] = DealsFavor:GetSkipOverStack()
            and "* Needs more than one stack. Forever could not fill a crate from more than one stack when last reported, so it is left out."
            or "* Needs more than one stack, which Forever could not fill a crate from when last reported."
    end
    if entry.have > 0 then
        parts[#parts + 1] = ("You carry %d of these crates."):format(entry.have)
    end
    if not entry.itemID then
        parts[#parts + 1] = "Not seen in the game yet, so it has no auction house price."
    end
    parts[#parts + 1] = "Prices are the cheapest listings from your last scan, or a vendor's where one sells it."
    detail.note:SetText(table.concat(parts, " "))
end

--------------------------------------------------------------------------------
-- List
--------------------------------------------------------------------------------

local function CountText(rows)
    local priced, cheapest = 0, nil
    for _, row in ipairs(rows) do
        if row.perFavor then
            priced = priced + 1
            if not cheapest or row.perFavor < cheapest.perFavor then cheapest = row end
        end
    end

    if not cheapest then
        if (ns.Prices and ns.Prices:Count() or 0) == 0 then
            return { "Scan the auction house to price the crates and their bundles." }
        end
        return { "No crate is fully priced yet. Scan again once some are listed." }
    end

    local plural = priced == 1 and "" or "s"
    local money = Util.FormatMoney(Round(cheapest.perFavor), { noColor = true, short = true })
    return {
        ("%d crate%s priced, cheapest favor %s each (%s)"):format(priced, plural, money, cheapest.name),
        ("%d crate%s priced, cheapest favor %s"):format(priced, plural, money),
        ("%d crate%s priced"):format(priced, plural),
    }
end

function DealsFavor:Refresh()
    if not widgets.list then return end

    local rows = ns.MerchantsFavor:GetRows({ skipOverStack = DealsFavor:GetSkipOverStack() })

    if state.search ~= "" then
        local needle = state.search:lower()
        local filtered = {}
        for _, row in ipairs(rows) do
            if row.name:lower():find(needle, 1, true) then filtered[#filtered + 1] = row end
        end
        rows = filtered
    end

    if widgets.sorter then rows = widgets.sorter:Sort(rows) end
    widgets.list:SetData(rows)

    widgets.emptyLabel:SetShown(#rows == 0)
    if #rows == 0 then widgets.emptyLabel:SetText(("No crate matching \"%s\"."):format(state.search)) end

    local texts = CountText(rows)
    if Theme.FitText then Theme.FitText(widgets.countLabel, texts) else widgets.countLabel:SetText(texts[1]) end

    local fresh
    for _, row in ipairs(rows) do
        if SameRow(row, state.selected) then fresh = row break end
    end
    state.selected = fresh
    UpdateDetail(fresh)
end

function DealsFavor:SetSearch(text)
    state.search = text or ""
end

function DealsFavor:SetSkipOverStack(on)
    state.skipOverStack = on and true or false
end

function DealsFavor:GetSkipOverStack()
    if state.skipOverStack == nil then
        state.skipOverStack = ns.Config:Get("favorSkipOverStack") ~= false
    end
    return state.skipOverStack
end

function DealsFavor:ScrollToTop()
    if widgets.list then widgets.list:ScrollToTop() end
end

--------------------------------------------------------------------------------
-- Build
--------------------------------------------------------------------------------

--- Lay the view out in `view`, under the tab's option bar `toolbar`.
function DealsFavor:Build(view, toolbar)
    if Widgets.FitColumns then Widgets.FitColumns(COLUMNS) end

    local headings = CreateFrame("Frame", nil, view)
    headings:SetPoint("TOPLEFT", toolbar, "BOTTOMLEFT", 0, -8)
    headings:SetPoint("TOPRIGHT", toolbar, "BOTTOMRIGHT", -DETAIL_WIDTH - 8, -8)
    headings:SetHeight(16)

    local nameHeading = Theme.CreateLabel(headings, "tiny", "muted")
    nameHeading:SetPoint("LEFT", 8 + ICON_GUTTER, 0)
    nameHeading:SetText("WAYLAID CRATE")

    local labels = { name = nameHeading }
    local values = { name = function(row) return row.name end }
    local cells = {}
    for index, column in ipairs(COLUMNS) do
        local heading = Theme.CreateLabel(headings, "tiny", "muted", "RIGHT")
        heading:SetText(column.label)
        heading:SetJustifyH(column.justify or "RIGHT")
        labels[index] = heading
        cells[index] = heading
        values[index] = function(row) return row[column.key] end
    end
    ns.Columns:Place("favor", COLUMNS, cells, { byIndex = true })

    -- Click a heading to sort by it; until then, cheapest favor first.
    widgets.sorter = Widgets.SortableHeadings and Widgets.SortableHeadings(labels, values,
        function() DealsFavor:Refresh() end)
    if widgets.sorter then widgets.sorter:SetText({ "name" }) end

    -- Right-click the headings to choose the columns.
    ns.Columns:Attach(headings, "favor", widgets.sorter)
    ns.Columns:OnChange("favor", function()
        ns.Columns:Place("favor", COLUMNS, cells, { byIndex = true })
        if widgets.sorter then widgets.sorter:Sync() end
        if widgets.list then widgets.list:Refresh() end
    end)

    local divider = Theme.CreateDivider(view, "borderLit")
    divider:SetPoint("TOPLEFT", headings, "BOTTOMLEFT", 0, -2)
    divider:SetPoint("TOPRIGHT", headings, "BOTTOMRIGHT", 0, -2)

    local list = Widgets.CreateScrollList(view, {
        onScrollbarShown = function(shown)
            headings:SetPoint("TOPRIGHT", toolbar, "BOTTOMRIGHT", -DETAIL_WIDTH - 8 - (shown and 10 or 0), -8)
        end,
        rowHeight = ROW_HEIGHT,
        createRow = CreateRow,
        updateRow = UpdateRow,
        onEnter = function(row, entry) ShowRowTooltip(row, entry) end,
        onLeave = function() GameTooltip:Hide() end,
        isSelected = function(entry) return SameRow(entry, state.selected) end,
        onClick = function(entry, _, mouseButton)
            state.selected = entry
            UpdateDetail(entry)
            if mouseButton == "RightButton" then SearchCrate(entry) end
        end,
    })
    list:SetPoint("TOPLEFT", divider, "BOTTOMLEFT", 0, -4)
    list:SetPoint("BOTTOMRIGHT", view, "BOTTOMRIGHT", -DETAIL_WIDTH - 16, 24)
    widgets.list = list

    local emptyLabel = Theme.CreateLabel(view, "small", "dim", "CENTER")
    emptyLabel:SetPoint("CENTER", list, "CENTER", 0, 10)
    emptyLabel:SetWidth(380)
    emptyLabel:SetWordWrap(true)
    widgets.emptyLabel = emptyLabel

    local hint = Theme.CreateLabel(view, "tiny", "dim", "RIGHT")
    hint:SetPoint("BOTTOMRIGHT", view, "BOTTOMRIGHT", -DETAIL_WIDTH - 16, 8)
    hint:SetText("Right-click a row to search for the crate")

    local countLabel = Theme.CreateLabel(view, "tiny", "dim")
    countLabel:SetPoint("BOTTOMLEFT", 8, 8)
    countLabel:SetPoint("RIGHT", hint, "LEFT", -12, 0)
    countLabel:SetJustifyH("LEFT")
    countLabel:SetWordWrap(false)
    widgets.countLabel = countLabel

    local detail = BuildDetail(view)
    detail:SetPoint("TOPRIGHT", view, "TOPRIGHT", -8, -40)
    detail:SetPoint("BOTTOMRIGHT", view, "BOTTOMRIGHT", -8, 8)
    widgets.detail = detail
    UpdateDetail(nil)

    -- Crates and materials the client had not cached arrive by name a few
    -- at a time; one redraw for a burst.
    local queued = false
    ns.RegisterEvent(widgets, "GET_ITEM_INFO_RECEIVED", function()
        if queued or not list:IsVisible() then return end
        queued = true
        C_Timer.After(1, function()
            queued = false
            if list:IsVisible() then DealsFavor:Refresh() end
        end)
    end)

    ns.MerchantsFavor:FindCrates()
end
