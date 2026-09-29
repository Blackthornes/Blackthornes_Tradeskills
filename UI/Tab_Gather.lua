-- Blackthornes Tradeskills -- UI/Tab_Gather.lua
-- The materials gathering queue.
--
-- Everything the craft queue needs, in one list, grouped by where you have to
-- go to get it. The vendor-versus-auction choice is made explicit rather than
-- resolved silently inside the cost engine: on a Classic realm people list
-- vendor-sold thread for many times the shop price, and knowing that is worth
-- more than a slightly cheaper total.
--
-- There is no manual "tick off" state. Items leave the list when you actually
-- own them, which is the only definition of gathered that cannot go stale.

local _, ns = ...

local Theme = ns.Theme
local Widgets = ns.Widgets
local Util = ns.Util

local UI = ns.UI

local ROW_HEIGHT = 24

local COLUMNS = {
    { key = "action", label = "",       width = 30 },
    { key = "cost",   label = "COST",   width = 74 },
    { key = "unit",   label = "EACH",   width = 64 },
    { key = "source", label = "BUY AT", width = 76 },
    { key = "have",   label = "HAVE",   width = 42 },
    { key = "need",   label = "NEED",   width = 42 },
}

local SOURCE_LABELS = {
    vendor  = "Vendor",
    auction = "Auction",
    unknown = "no data",
}

local state = { hideSatisfied = true, sortBy = "source" }
local widgets = {}

--------------------------------------------------------------------------------
-- Data
--------------------------------------------------------------------------------

local SOURCE_ORDER = { vendor = 1, auction = 2, unknown = 3 }

local function BuildList()
    local lines = {}

    for _, line in ipairs(ns.Queue:GetShoppingList()) do
        if line.shortfall > 0 or not state.hideSatisfied then
            line.label = Util.GetItemLabel(line.itemID)
            lines[#lines + 1] = line
        end
    end

    table.sort(lines, function(a, b)
        -- Outstanding first: satisfied rows are reference, not work.
        local aDone, bDone = a.shortfall <= 0, b.shortfall <= 0
        if aDone ~= bDone then return bDone end

        if state.sortBy == "source" then
            -- Grouped by where you go, so the list reads as a route: clear the
            -- vendor in one trip, then the auction house.
            local aOrder = SOURCE_ORDER[a.source] or 9
            local bOrder = SOURCE_ORDER[b.source] or 9
            if aOrder ~= bOrder then return aOrder < bOrder end

        elseif state.sortBy == "cost" then
            local aCost, bCost = a.estimatedCost or 0, b.estimatedCost or 0
            if aCost ~= bCost then return aCost > bCost end

        elseif state.sortBy == "name" then
            -- By the name inside the link: the link itself opens with a
            -- colour code, which sorted by rarity instead.
            local aName = (a.label or ""):match("%[(.-)%]") or a.label or ""
            local bName = (b.label or ""):match("%[(.-)%]") or b.label or ""
            if aName ~= bName then return aName < bName end
        end

        -- A last tie-break, so equal rows (every "no data" one at 0) keep
        -- their places between refreshes instead of swapping.
        if (a.estimatedCost or 0) ~= (b.estimatedCost or 0) then
            return (a.estimatedCost or 0) > (b.estimatedCost or 0)
        end
        return (a.itemID or 0) < (b.itemID or 0)
    end)

    return lines
end

--------------------------------------------------------------------------------
-- Rows
--------------------------------------------------------------------------------

local function CreateRow(row)
    -- The item's icon beside its name, as the bags draw it.
    row.icon = Theme.CreateItemIcon(row, 16)
    row.icon:SetPoint("LEFT", 10, 0)

    row.name = Theme.CreateLabel(row, "small", "text")
    row.name:SetPoint("LEFT", 30, 0)

    row.cells = {}

    local offset = -8
    local reserved = 18

    for _, column in ipairs(COLUMNS) do
        if column.key ~= "action" then
            local cell = Theme.CreateLabel(row, "small", "muted", "RIGHT")
            cell:SetPoint("RIGHT", offset, 0)
            cell:SetWidth(column.width)
            row.cells[column.key] = cell
        end

        offset = offset - column.width - 6
        reserved = reserved + column.width + 6
    end

    row.name:SetPoint("RIGHT", row, "RIGHT", -reserved, 0)

    row.search = Widgets.CreateButton(row, "AH", function()
        if row.data then UI:SearchAuctionHouse(row.data.itemID) end
    end, { width = 26, height = 16, tooltip = "Search the auction house for this" })
    row.search:SetPoint("RIGHT", -8, 0)

    -- With Blackthornes Farmer loaded: turn the shortfall into a Farmer
    -- gathering goal, shown on Farmer's Goals panel.
    row.goal = Widgets.CreateButton(row, "Set goal", function()
        local line = row.data
        if line then ns.FarmerGoals:SetGoal(line.itemID, line.needed) end
    end, { width = 52, height = 16,
        tooltip = "Make a Blackthornes Farmer goal to gather what you need of this" })
    row.goal:SetPoint("RIGHT", -38, 0)
    row.goal:Hide()
end

local function UpdateRow(row, line)
    row.name:SetText(line.label)
    Theme.SetItemIcon(row.icon, line.itemID)

    local cells = row.cells
    local done = line.shortfall <= 0

    cells.need:SetText(tostring(line.needed))
    cells.have:SetText(tostring(line.have))
    cells.have:SetTextColor(Theme.Unpack(done and "profit" or "loss"))

    if done then
        row.name:SetTextColor(Theme.Unpack("muted"))

        cells.source:SetText("have it")
        cells.source:SetTextColor(Theme.Unpack("dim"))
        cells.unit:SetText("")
        cells.cost:SetText("")

        row.search:Hide()
        row.goal:Hide()
        return
    end

    row.name:SetTextColor(Theme.Unpack("text"))

    cells.source:SetText(SOURCE_LABELS[line.source] or "?")
    cells.source:SetTextColor(Theme.Unpack(
        line.source == "vendor" and "accent"
        or line.source == "auction" and "text"
        or "dim"))

    cells.unit:SetText(line.unitCost and Util.FormatMoney(line.unitCost, { short = true }) or "?")
    cells.cost:SetText(line.estimatedCost
        and Util.FormatMoney(line.estimatedCost, { short = true }) or "?")
    cells.cost:SetTextColor(Theme.Unpack("text"))

    -- No auction search for something a vendor sells cheaper: following it
    -- would be acting against the recommendation the row just made.
    row.search:SetShown(line.source == "auction")
    row.goal:SetShown(ns.FarmerGoals:Available())
end

local function ShowRowTooltip(row, line)
    ns.Widgets.ShowItemTooltip(row, "ANCHOR_RIGHT", line.itemID, line.label)
    GameTooltip:AddLine(" ")

    GameTooltip:AddDoubleLine("Required", tostring(line.needed), 0.7, 0.7, 0.7, 1, 1, 1)
    GameTooltip:AddDoubleLine("In bags", tostring(line.inBags or 0), 0.7, 0.7, 0.7, 1, 1, 1)

    if (line.inBank or 0) > 0 then
        GameTooltip:AddDoubleLine("In bank", tostring(line.inBank),
            0.7, 0.7, 0.7, 0.91, 0.76, 0.35)
    end

    if line.shortfall > 0 then
        GameTooltip:AddDoubleLine("Still needed", tostring(line.shortfall),
            0.7, 0.7, 0.7, 0.9, 0.38, 0.31)
    end

    GameTooltip:AddLine(" ")

    -- The whole point of the tab: show both prices, not just the winner.
    if line.vendorUnit then
        GameTooltip:AddDoubleLine("Vendor, each",
            Util.FormatMoney(line.vendorUnit, { noColor = true }),
            0.7, 0.7, 0.7, 0.78, 0.64, 0.30)
    else
        GameTooltip:AddLine("No vendor known to sell this", 0.5, 0.5, 0.5)
    end

    if line.auctionUnit then
        GameTooltip:AddDoubleLine("Auction, each",
            Util.FormatMoney(line.auctionUnit, { noColor = true }),
            0.7, 0.7, 0.7, 1, 1, 1)
    else
        GameTooltip:AddLine("Not seen on the auction house", 0.5, 0.5, 0.5)
    end

    if line.savingTotal and line.savingTotal > 0 then
        GameTooltip:AddDoubleLine(
            ("Saved by buying from the %s"):format(
                line.source == "auction" and "auction house" or line.source),
            Util.FormatMoney(line.savingTotal, { noColor = true }),
            0.7, 0.7, 0.7, 0.31, 0.82, 0.55)
    end

    if line.vendorLimited then
        GameTooltip:AddLine("Vendor stock is limited", 0.91, 0.76, 0.35)
    end

    if (line.onAlts or 0) > 0 then
        GameTooltip:AddDoubleLine("On other characters", tostring(line.onAlts),
            0.7, 0.7, 0.7, 0.91, 0.76, 0.35)
    end

    GameTooltip:Show()
end

--------------------------------------------------------------------------------
-- Refresh
--------------------------------------------------------------------------------

local function Refresh()
    if not widgets.list then return end

    local lines = BuildList()
    widgets.list:SetData(lines)

    widgets.emptyLabel:SetShown(#lines == 0)
    if #lines == 0 then
        widgets.emptyLabel:SetText(ns.Queue:Count() == 0
            and "Nothing queued.\nAdd crafts on the Profit tab and their materials appear here."
            or "You already have everything the queue needs.")
    end

    local summary = ns.Queue:GetGatherSummary()

    widgets.progress:SetText(("%d of %d materials still needed"):format(
        summary.outstanding, summary.outstanding + summary.satisfied))

    -- Split by destination, because that is how you actually do the errand.
    widgets.vendorTotal:SetText(summary.vendor.count > 0
        and ("Vendor  %s   (%d item%s)"):format(
            Util.FormatMoney(summary.vendor.cost, { short = true }),
            summary.vendor.count, summary.vendor.count == 1 and "" or "s")
        or "Vendor  --")

    widgets.auctionTotal:SetText(summary.auction.count > 0
        and ("Auction  %s   (%d item%s)"):format(
            Util.FormatMoney(summary.auction.cost, { short = true }),
            summary.auction.count, summary.auction.count == 1 and "" or "s")
        or "Auction  --")

    widgets.grandTotal:SetText(("Total  %s"):format(
        Util.FormatMoney(summary.total, { short = true })))

    if summary.saving > 0 then
        widgets.savingLabel:SetText(("Buying from the cheaper source saves %s"):format(
            Util.FormatMoney(summary.saving, { short = true })))
    else
        widgets.savingLabel:SetText("")
    end

    -- Unknown prices make the total an understatement, so say so.
    widgets.unknownLabel:SetText(summary.unknown.count > 0
        and ("%d material%s with no price data, so the real total is higher"):format(
            summary.unknown.count, summary.unknown.count == 1 and "" or "s")
        or "")

    if ns.Vendor:Count() == 0 then
        widgets.vendorNote:SetText("No vendor prices learned yet. Open a trade goods vendor once so vendor options can be compared.")
    else
        widgets.vendorNote:SetText("")
    end
end

--------------------------------------------------------------------------------
-- Build
--------------------------------------------------------------------------------

local function Build(container)
    -- Room for the Set goal button beside AH, only when Farmer is there to take it.
    COLUMNS[1].width = ns.FarmerGoals:Available() and 88 or 30

    local toolbar = CreateFrame("Frame", nil, container)
    toolbar:SetPoint("TOPLEFT", 8, -8)
    toolbar:SetPoint("TOPRIGHT", -8, -8)
    toolbar:SetHeight(24)

    local hideSatisfied = Widgets.CreateCheckbox(toolbar, "Hide what I have", function(checked)
        state.hideSatisfied = checked
        Refresh()
    end, true)
    hideSatisfied:SetPoint("LEFT", 0, 0)

    local sort = Widgets.CreateDropdown(toolbar, {
        { text = "Group: Where to buy", value = "source" },
        { text = "Sort: Cost", value = "cost" },
        { text = "Sort: Name", value = "name" },
    }, function(value)
        state.sortBy = value
        Refresh()
    end, { width = 150 })
    sort:SetPoint("RIGHT", 0, 0)
    sort:SetValue("source")

    -- With Blackthornes Farmer loaded: every material still needed becomes a
    -- Farmer goal in one click, in the order the list shows them.
    if ns.FarmerGoals:Available() then
        local setAll = Widgets.CreateButton(toolbar, "Set all goals", function()
            local needed = {}
            for _, line in ipairs(BuildList()) do
                if line.shortfall > 0 then needed[#needed + 1] = line end
            end
            ns.FarmerGoals:SetGoals(needed)
        end, { width = 100, height = 22,
            tooltip = "Make a Blackthornes Farmer goal for every material you still need" })
        setAll:SetPoint("RIGHT", sort, "LEFT", -8, 0)
    end

    -- Column headings
    local headings = CreateFrame("Frame", nil, container)
    headings:SetPoint("TOPLEFT", toolbar, "BOTTOMLEFT", 0, -8)
    headings:SetPoint("TOPRIGHT", toolbar, "BOTTOMRIGHT", 0, -8)
    headings:SetHeight(16)

    local nameHeading = Theme.CreateLabel(headings, "tiny", "muted")
    nameHeading:SetPoint("LEFT", 30, 0)
    nameHeading:SetText("MATERIAL")

    local offset = -8
    for _, column in ipairs(COLUMNS) do
        if column.label ~= "" then
            local heading = Theme.CreateLabel(headings, "tiny", "muted", "RIGHT")
            heading:SetPoint("RIGHT", offset, 0)
            heading:SetWidth(column.width)
            heading:SetText(column.label)
        end
        offset = offset - column.width - 6
    end

    local divider = Theme.CreateDivider(container, "borderLit")
    divider:SetPoint("TOPLEFT", headings, "BOTTOMLEFT", 0, -2)
    divider:SetPoint("TOPRIGHT", headings, "BOTTOMRIGHT", 0, -2)

    local list = Widgets.CreateScrollList(container, {
        -- The headings move in with the rows when the scrollbar takes its room.
        onScrollbarShown = function(shown)
            headings:SetPoint("TOPRIGHT", toolbar, "BOTTOMRIGHT", -(shown and 10 or 0), -8)
        end,
        rowHeight = ROW_HEIGHT,
        createRow = CreateRow,
        updateRow = UpdateRow,
        onEnter = ShowRowTooltip,
        onLeave = function() GameTooltip:Hide() end,
    })
    list:SetPoint("TOPLEFT", divider, "BOTTOMLEFT", 0, -4)
    list:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", -8, 86)
    widgets.list = list

    local emptyLabel = Theme.CreateLabel(container, "small", "dim", "CENTER")
    emptyLabel:SetPoint("CENTER", list, "CENTER")
    emptyLabel:SetWidth(360)
    emptyLabel:SetWordWrap(true)
    widgets.emptyLabel = emptyLabel

    -- Footer
    local footerDivider = Theme.CreateDivider(container)
    footerDivider:SetPoint("BOTTOMLEFT", 8, 78)
    footerDivider:SetPoint("BOTTOMRIGHT", -8, 78)

    widgets.progress = Theme.CreateLabel(container, "small", "text")
    widgets.progress:SetPoint("BOTTOMLEFT", 10, 58)

    widgets.vendorTotal = Theme.CreateLabel(container, "small", "accent")
    widgets.vendorTotal:SetPoint("BOTTOMLEFT", 10, 38)

    widgets.auctionTotal = Theme.CreateLabel(container, "small", "text")
    widgets.auctionTotal:SetPoint("BOTTOMLEFT", 220, 38)

    -- In gold, like the other headline figures: it is the answer here.
    widgets.grandTotal = Theme.CreateLabel(container, "small", "accent")
    widgets.grandTotal:SetPoint("BOTTOMLEFT", 430, 38)

    widgets.savingLabel = Theme.CreateLabel(container, "tiny", "profit")
    widgets.savingLabel:SetPoint("BOTTOMLEFT", 10, 22)

    widgets.unknownLabel = Theme.CreateLabel(container, "tiny", "warn")
    widgets.unknownLabel:SetPoint("BOTTOMLEFT", 10, 8)

    widgets.vendorNote = Theme.CreateLabel(container, "tiny", "dim")
    widgets.vendorNote:SetPoint("BOTTOMLEFT", 430, 22)
    widgets.vendorNote:SetPoint("BOTTOMRIGHT", -10, 22)
end

UI:RegisterTab({
    key = "gather",
    text = "Gather",
    order = 3,
    build = Build,
    refresh = Refresh,
})
