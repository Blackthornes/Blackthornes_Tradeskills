-- Blackthornes Tradeskills -- UI/Tab_Post.lua
-- What to sell, and what to charge.
--
-- One click per listing, because Blizzard requires a hardware event to post.
-- The price is on the row before you press it, and anything that would sell
-- below its material cost is marked red and refused unless allowed.
--
-- The price is also shown split into Blizzard's gold/silver/copper boxes, so
-- listing by hand stays easy when the auction house is refusing addon
-- listings -- which it has done for stretches on this beta.

local _, ns = ...

local Theme = ns.Theme
local Widgets = ns.Widgets
local Util = ns.Util

local UI = ns.UI

local ROW_HEIGHT = 26

local COLUMNS = {
    { key = "action",  label = "",        width = 56 },
    { key = "total",   label = "TOTAL",   width = 78 },
    { key = "deposit", label = "DEPOSIT", width = 62 },
    { key = "copper",  label = "C",       width = 34 },
    { key = "silver",  label = "S",       width = 34 },
    { key = "gold",    label = "G",       width = 40 },
    { key = "cost",    label = "COST",    width = 66 },
    { key = "count",   label = "HAVE",    width = 42 },
}

local widgets = {}

--------------------------------------------------------------------------------
-- Rows
--------------------------------------------------------------------------------

local function CreateRow(row)
    row.name = Theme.CreateLabel(row, "small", "text")
    row.name:SetPoint("LEFT", 10, 0)

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

    row.post = Widgets.CreateButton(row, "List", function()
        if not row.data then return end

        -- Left clickable even when it cannot list, so the click produces an
        -- explanation rather than nothing at all.
        local allowed, reason = ns.Posting:CanPost()
        if not allowed then
            ns.Print(reason or "cannot post right now")
            return
        end

        ns.Posting:Request(row.data.itemID, row.data.postQuantity, row.data.unitPrice)
        UI:RefreshActiveTab()
    end, { width = 50, height = 18, primary = true })
    row.post:SetPoint("RIGHT", -8, 0)
end

local function UpdateRow(row, line)
    row.name:SetText(line.label)

    local cells = row.cells

    cells.count:SetText(tostring(line.count))
    cells.count:SetTextColor(Theme.Unpack("text"))

    cells.cost:SetText(line.unitCost
        and Util.FormatMoney(line.unitCost, { short = true }) or "?")

    if line.unitPrice then
        -- Split into the three boxes Blizzard's Sell tab asks for, so the price
        -- can be read straight across rather than converted in your head.
        local gold, silver, copper = Util.SplitMoney(line.unitPrice)

        local priceColour = line.atALoss and "loss" or "accent"

        cells.gold:SetText(tostring(gold))
        cells.silver:SetText(tostring(silver))
        cells.copper:SetText(tostring(copper))

        for _, key in ipairs({ "gold", "silver", "copper" }) do
            cells[key]:SetTextColor(Theme.Unpack(priceColour))
        end

        cells.total:SetText(Util.FormatMoney(line.total, { short = true }))
        cells.total:SetTextColor(Theme.Unpack(line.atALoss and "loss" or "profit"))
    else
        for _, key in ipairs({ "gold", "silver", "copper" }) do
            cells[key]:SetText("-")
            cells[key]:SetTextColor(Theme.Unpack("dim"))
        end

        cells.total:SetText("no price")
        cells.total:SetTextColor(Theme.Unpack("dim"))
    end

    cells.deposit:SetText(line.deposit
        and Util.FormatMoney(line.deposit, { short = true }) or "--")

    row.name:SetTextColor(Theme.Unpack(line.unitPrice and "text" or "muted"))

    -- The G/S/C columns stay either way: when the auction house refuses a
    -- listing, typing it into Blizzard's Sell tab is the fallback.
    local allowed, reason = ns.Posting:CanPost()
    row.post:SetEnabledState(line.unitPrice ~= nil)

    if not allowed then
        row.post.tooltipText = reason
    elseif not line.unitPrice then
        row.post.tooltipText = "No price data for this item -- scan first"
    elseif line.atALoss then
        row.post.tooltipText = (line.lossReason == "vendor"
            and "This would sell for less than a vendor pays. Blocked unless you allow it in Settings."
            or "This would sell below its material cost. Blocked unless you allow it in Settings.")
    else
        row.post.tooltipText = ("List %d at %s each"):format(
            line.postQuantity, Util.FormatMoney(line.unitPrice, { noColor = true }))
    end
end

local function ShowRowTooltip(row, line)
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:SetText(line.label, 1, 1, 1)

    GameTooltip:AddDoubleLine("In bags", tostring(line.count), 0.7, 0.7, 0.7, 1, 1, 1)

    if line.unitPrice then
        GameTooltip:AddDoubleLine("List each at",
            Util.FormatMoney(line.unitPrice, { noColor = true }),
            0.7, 0.7, 0.7, 0.78, 0.64, 0.30)

        GameTooltip:AddLine(line.priceBasis == "undercut"
            and "Undercutting the cheapest listing that is not yours"
            or "Nothing listed to undercut -- using market value", 0.5, 0.5, 0.5)
    end

    if line.unitCost then
        GameTooltip:AddDoubleLine("Materials cost, each",
            Util.FormatMoney(line.unitCost, { noColor = true }), 0.7, 0.7, 0.7, 1, 1, 1)
    end

    if line.vendorPrice then
        GameTooltip:AddDoubleLine("Vendor pays, each",
            Util.FormatMoney(line.vendorPrice, { noColor = true }), 0.7, 0.7, 0.7, 1, 1, 1)
    end

    if line.atALoss then
        GameTooltip:AddLine(line.lossReason == "vendor"
            and "Would sell for less than a vendor pays"
            or "Would sell below material cost", 0.9, 0.38, 0.31)
    end

    -- Commodities sell from across the bags at once; gear goes up one at a time.
    GameTooltip:AddLine(line.isCommodity
        and ("Commodity -- all %d can go up together"):format(line.count)
        or "Item auction -- one listing at a time", 0.5, 0.5, 0.5)

    GameTooltip:Show()
end

--------------------------------------------------------------------------------
-- Refresh
--------------------------------------------------------------------------------

local function Refresh()
    if not widgets.list then return end

    local lines = ns.Posting:GetPostable()
    widgets.list:SetData(lines)

    widgets.emptyLabel:SetShown(#lines == 0)
    if #lines == 0 then
        widgets.emptyLabel:SetText(
            "Nothing in your bags that one of your recipes makes.\nCraft something first, and it will show up here.")
    end

    local total, losses = 0, 0
    for _, line in ipairs(lines) do
        total = total + (line.total or 0)
        if line.atALoss then losses = losses + 1 end
    end

    widgets.summary:SetText(("%d stack%s worth about %s"):format(
        #lines, #lines == 1 and "" or "s", Util.FormatMoney(total, { short = true })))

    widgets.warning:SetText(losses > 0
        and ("%d item%s would sell below material cost"):format(
            losses, losses == 1 and "" or "s")
        or "")

    local allowed, reason = ns.Posting:CanPost()
    widgets.statusLabel:SetText(allowed and "" or (reason or ""))

    widgets.duration:SetValue(ns.Config:Get("postDuration") or 2)
end

--------------------------------------------------------------------------------
-- Build
--------------------------------------------------------------------------------

local function Build(container)
    local toolbar = CreateFrame("Frame", nil, container)
    toolbar:SetPoint("TOPLEFT", 8, -8)
    toolbar:SetPoint("TOPRIGHT", -8, -8)
    toolbar:SetHeight(24)

    local durationLabel = Theme.CreateLabel(toolbar, "small", "muted")
    durationLabel:SetPoint("LEFT", 2, 0)
    durationLabel:SetText("Duration")

    widgets.duration = Widgets.CreateDropdown(toolbar, ns.Posting.DURATIONS, function(value)
        ns.Config:Set("postDuration", value)
        Refresh()
    end, { width = 110 })
    widgets.duration:SetPoint("LEFT", durationLabel, "RIGHT", 8, 0)

    local durationHint = Theme.CreateLabel(toolbar, "tiny", "dim")
    durationHint:SetPoint("LEFT", widgets.duration, "RIGHT", 8, 0)
    durationHint:SetText("affects the deposit estimate only")

    widgets.statusLabel = Theme.CreateLabel(toolbar, "small", "warn", "RIGHT")
    widgets.statusLabel:SetPoint("RIGHT", 0, 0)
    widgets.statusLabel:SetWidth(340)

    -- Stated once, plainly, rather than discovered by clicking a dead button.
    local note = Theme.CreateLabel(container, "small", "warn")
    note:SetPoint("TOPLEFT", toolbar, "BOTTOMLEFT", 2, -6)
    note:SetPoint("RIGHT", toolbar, "RIGHT", 0, 0)
    note:SetWordWrap(true)
    note:SetText("List with the buttons, or type the G / S / C price into Blizzard's own Sell tab.")

    -- Column headings
    local headings = CreateFrame("Frame", nil, container)
    headings:SetPoint("TOPLEFT", note, "BOTTOMLEFT", -2, -8)
    headings:SetPoint("TOPRIGHT", toolbar, "BOTTOMRIGHT", 0, -34)
    headings:SetHeight(16)

    local nameHeading = Theme.CreateLabel(headings, "tiny", "dim")
    nameHeading:SetPoint("LEFT", 10, 0)
    nameHeading:SetText("CRAFTED ITEM")

    local offset = -8
    for _, column in ipairs(COLUMNS) do
        local heading = Theme.CreateLabel(headings, "tiny", "dim", "RIGHT")
        heading:SetPoint("RIGHT", offset, 0)
        heading:SetWidth(column.width)
        heading:SetText(column.label)

        offset = offset - column.width - 6
    end

    local divider = Theme.CreateDivider(container)
    divider:SetPoint("TOPLEFT", headings, "BOTTOMLEFT", 0, -2)
    divider:SetPoint("TOPRIGHT", headings, "BOTTOMRIGHT", 0, -2)

    local list = Widgets.CreateScrollList(container, {
        rowHeight = ROW_HEIGHT,
        createRow = CreateRow,
        updateRow = UpdateRow,
        onEnter = ShowRowTooltip,
        onLeave = function() GameTooltip:Hide() end,
    })
    list:SetPoint("TOPLEFT", divider, "BOTTOMLEFT", 0, -4)
    list:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", -8, 54)
    widgets.list = list

    local emptyLabel = Theme.CreateLabel(container, "small", "dim", "CENTER")
    emptyLabel:SetPoint("CENTER", list, "CENTER")
    emptyLabel:SetWidth(380)
    emptyLabel:SetWordWrap(true)
    widgets.emptyLabel = emptyLabel

    local footerDivider = Theme.CreateDivider(container)
    footerDivider:SetPoint("BOTTOMLEFT", 8, 46)
    footerDivider:SetPoint("BOTTOMRIGHT", -8, 46)

    widgets.summary = Theme.CreateLabel(container, "small", "text")
    widgets.summary:SetPoint("BOTTOMLEFT", 10, 28)

    widgets.warning = Theme.CreateLabel(container, "tiny", "loss")
    widgets.warning:SetPoint("BOTTOMLEFT", 10, 12)
end

UI:RegisterTab({
    key = "post",
    text = "Post",
    order = 4,
    build = Build,
    refresh = Refresh,
})
