-- Blackthornes Tradeskills -- UI/Tab_Enchanting.lua
-- What is worth more disenchanted than sold, and what the materials fetch.
--
-- Three views of one question. Crafts: which of your recipes make something
-- worth more broken down than listed, ranked on what disenchanting makes over
-- the materials. Your bags: which of the things you carry are worth more
-- disenchanted than sold. Materials: what each enchanting material is worth.
--
-- The numbers come from Logic/Disenchant.lua, which holds the built-in table
-- the game does not give addons.

local _, ns = ...

local Theme = ns.Theme
local Widgets = ns.Widgets
local Util = ns.Util

local UI = ns.UI

local ROW_HEIGHT = 22
local DETAIL_WIDTH = 300
local ICON_GUTTER = 20

-- Short enough to leave room for the bound-item warning in the bag view:
-- the longer wording filled the note's four lines and pushed that off.
local SOURCE_NOTE = "Chances come from the built-in Classic table until you have done %d disenchants like this (%d so far). Materials are priced at their lowest posting, leaving out a lone low one."

-- Right-aligned columns per view, laid out right to left.
local VIEWS = {
    craft = {
        columns = {
            { key = "gain",  label = "PROFIT",     width = 70 },
            { key = "value", label = "DISENCHANT", width = 70 },
            { key = "sells", label = "SELLS",      width = 70 },
            { key = "cost",  label = "COST",       width = 66 },
            { key = "make",  label = "MAKE",       width = 40 },
        },
        heading = "CRAFT",
    },
    bag = {
        columns = {
            { key = "gain",  label = "DIFFERENCE", width = 74 },
            { key = "value", label = "DISENCHANT", width = 70 },
            { key = "sells", label = "SELLS",      width = 70 },
            { key = "count", label = "HAVE",       width = 40 },
        },
        heading = "ITEM",
    },
    material = {
        columns = {
            { key = "age",   label = "AGE",   width = 50 },
            { key = "price", label = "PRICE", width = 80 },
            { key = "have",  label = "HAVE",  width = 40 },
        },
        heading = "MATERIAL",
    },
}

local MAX_COLUMNS = 5

local state = {
    view = "craft",
    search = "",
    beatsOnly = true,
    selected = nil,
}

local widgets = {}

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function Money(value)
    return Util.FormatMoney(value, { short = true })
end

local function SameRow(a, b)
    return a and b and a.kind == b.kind and a.itemID == b.itemID and a.recipeID == b.recipeID
end

--------------------------------------------------------------------------------
-- Rows
--------------------------------------------------------------------------------

local function ApplyRowLayout(row)
    local columns = VIEWS[state.view].columns
    local offset = -8

    for index = 1, MAX_COLUMNS do
        local cell = row.cells[index]
        local column = columns[index]

        cell:ClearAllPoints()

        if column then
            cell:SetPoint("RIGHT", row, "RIGHT", offset, 0)
            cell:SetWidth(column.width)
            cell:Show()
            offset = offset - column.width - 6
        else
            cell:Hide()
        end
    end

    row.name:SetPoint("RIGHT", row, "RIGHT", offset - 4, 0)
    row.view = state.view
end

local function CreateRow(row)
    row.icon = Theme.CreateItemIcon(row, 16)
    row.icon:SetPoint("LEFT", 8, 0)

    row.name = Theme.CreateLabel(row, "small", "text")
    row.name:SetPoint("LEFT", 8 + ICON_GUTTER, 0)

    row.cells = {}
    for index = 1, MAX_COLUMNS do
        row.cells[index] = Theme.CreateLabel(row, "small", "text", "RIGHT")
    end

    ApplyRowLayout(row)
end

--- Fill one cell from the row, by the column's key.
local function FillCell(cell, key, entry)
    local color = "muted"
    local text

    if key == "value" then
        if entry.value then
            text = Money(entry.value)
            color = entry.beatsSale and "profit" or "text"
        else
            text, color = "no price", "dim"
        end
    elseif key == "sells" then
        if entry.sells then
            text = Money(entry.sells)
        elseif entry.soulbound then
            text, color = "soulbound", "dim"
        else
            text, color = "no price", "dim"
        end
    elseif key == "cost" then
        if entry.cost then text = Money(entry.cost) else text, color = "no price", "dim" end
    elseif key == "gain" then
        if entry.gain then
            text = Money(entry.gain)
            cell:SetText(text)
            cell:SetTextColor(Theme.ProfitColor(entry.gain))
            return
        end
        text, color = "", "dim"
    elseif key == "make" then
        local make = entry.craftableNow or 0
        text, color = tostring(make), make > 0 and "text" or "loss"
    elseif key == "count" or key == "have" then
        local have = entry[key] or 0
        text, color = have > 0 and tostring(have) or "", "muted"
    elseif key == "price" then
        if entry.price then
            text, color = Money(entry.price), "text"
        else
            text, color = "not scanned", "dim"
        end
    elseif key == "age" then
        text = entry.price and entry.age and Util.FormatAge(entry.age) or ""
        color = entry.stale and "warn" or "dim"
    end

    cell:SetText(text or "")
    cell:SetTextColor(Theme.Unpack(color))
end

local function UpdateRow(row, entry)
    if row.view ~= state.view then ApplyRowLayout(row) end

    row.name:SetText(entry.name or ("item " .. tostring(entry.itemID)))
    -- A bag row carries its link, so the upgrade arrow judges that very copy.
    Theme.SetItemIcon(row.icon, entry.itemID, entry.link)

    local r, g, b = Util.GetItemQualityColor(entry.itemID)
    if r then
        row.name:SetTextColor(r, g, b)
    else
        row.name:SetTextColor(Theme.Unpack("text"))
    end

    local columns = VIEWS[state.view].columns
    for index, column in ipairs(columns) do
        FillCell(row.cells[index], column.key, entry)
    end
end

local function ShowRowTooltip(row, entry)
    Widgets.ShowItemTooltip(row, "ANCHOR_LEFT", entry.itemID, entry.name)

    if entry.kind ~= "material" and entry.value then
        GameTooltip:AddLine(" ")
        if entry.losesToMaterials then
            GameTooltip:AddLine(("Disenchanting beats selling, but loses %s against the materials."):format(
                Util.FormatMoney(-entry.gain, { noColor = true })), 0.9, 0.35, 0.35, true)
        elseif entry.beatsSale and entry.sells then
            GameTooltip:AddLine(("Disenchanting it is worth %s more than selling it."):format(
                Util.FormatMoney(entry.value - entry.sells, { noColor = true })), 0.35, 0.85, 0.45, true)
        elseif entry.sells then
            GameTooltip:AddLine(("Selling it is worth %s more than disenchanting it."):format(
                Util.FormatMoney(entry.sells - entry.value, { noColor = true })), 0.7, 0.7, 0.7, true)
        end
    end

    if entry.sellsAt == "vendor" then
        GameTooltip:AddLine("Its sale price is what a vendor pays.", 0.7, 0.7, 0.7, true)
    elseif entry.sellsAt == "estimate" then
        GameTooltip:AddLine("Never scanned, so its sale price is an estimate from its materials.", 0.91, 0.76, 0.35, true)
    end

    if entry.kind == "craft" then
        GameTooltip:AddLine("Right-click to queue one. Shift-click to search the auction house.", 0.5, 0.5, 0.5)
    end

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

    -- Queue controls, for crafts.
    local quantityBox = Theme.CreatePanel(detail, "row")
    quantityBox:SetSize(46, 24)
    quantityBox:SetPoint("BOTTOMLEFT", 12, 14)
    detail.quantityBox = quantityBox

    local quantity = CreateFrame("EditBox", nil, quantityBox)
    quantity:SetAllPoints(quantityBox)
    quantity:SetAutoFocus(false)
    quantity:SetNumeric(true)
    quantity:SetJustifyH("CENTER")
    quantity:SetFont(Theme.FONT, Theme.sizes.small, "")
    quantity:SetTextColor(Theme.Unpack("text"))
    quantity:SetText("1")
    quantity:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    quantity:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    detail.quantity = quantity

    local addButton = Widgets.CreateButton(detail, "Add to queue", function()
        local entry = state.selected
        if not entry or not entry.recipeID then return end

        local count = math.max(1, tonumber(quantity:GetText()) or 1)
        ns.Queue:Add(entry.recipeID, count)
        ns.Print(("queued %dx %s"):format(count, entry.name or "craft"))
    end, { width = 100, primary = true, height = 24 })
    addButton:SetPoint("BOTTOMLEFT", quantityBox, "BOTTOMRIGHT", 8, 0)
    detail.addButton = addButton

    -- Disenchant, for an item in the bags. The click itself is taken by the
    -- secure button UI/Disenchanter.lua lays over this one; this handler
    -- only runs when that button is not there, so it says why.
    local disenchantButton = Widgets.CreateButton(detail, "Disenchant", function()
        local entry = state.selected
        local check = ns.Disenchanter:Check(entry and entry.itemID)

        if not check.ok then
            ns.Print(check.why)
        else
            ns.Warn("that click missed the Disenchant button. Click it again; if it misses twice, type /bts disenchant and send the lines it prints.")
        end
    end, { width = 100, primary = true, height = 24 })
    detail.disenchantButton = disenchantButton

    local disenchantStatus = Theme.CreateLabel(detail, "tiny", "warn")
    disenchantStatus:SetPoint("LEFT", disenchantButton, "RIGHT", 8, 0)
    disenchantStatus:SetPoint("RIGHT", detail, "RIGHT", -12, 0)
    disenchantStatus:SetWordWrap(true)
    detail.disenchantStatus = disenchantStatus

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

-- A "breaks into" line runs the width of the detail panel, less its margins.
local OUTCOME_WIDTH = DETAIL_WIDTH - 24

--- Give a "breaks into" line's name the room its price leaves, and the line
--- the height the name wraps to. With a fixed room, a long name ran under a
--- wide price ("12g 34s 56c each") or ended in "...".
local function FitOutcomeLine(line)
    local ok, priceWidth = pcall(line.value.GetStringWidth, line.value)
    if not ok or type(priceWidth) ~= "number" then priceWidth = 74 end

    line.name:SetWidth(math.max(40, OUTCOME_WIDTH - 18 - 6 - math.ceil(priceWidth)))

    local gotHeight, height = pcall(line.name.GetStringHeight, line.name)
    if not gotHeight or type(height) ~= "number" then height = 0 end
    line.frame:SetHeight(math.max(16, math.ceil(height) + 2))
end

--- Arm the Disenchant button for a bag item, or say why it cannot be.
-- @return true when the item can be disenchanted now
local function UpdateDisenchantButton(entry)
    local detail = widgets.detail
    local button = detail.disenchantButton
    local disenchanter = ns.Disenchanter

    local check = disenchanter:Check(entry and entry.itemID)

    button:SetEnabledState(check.ok)
    button.tooltipText = check.ok
        and ("Disenchant one %s from your bags."):format(entry.name or "item") or check.why
    detail.disenchantStatus:SetText(check.ok and "" or check.why)

    if check.ok then
        disenchanter:Arm(button, entry.itemID, check.bag, check.slot)
    elseif disenchanter.anchor == button then
        disenchanter:Disarm()
    end
    return check.ok
end

--- Where the Disenchant button and the line saying why it cannot be used
--- sit: bottom left for a bag item, with the line beside it, and beside the
--- queue button for a craft. There is no room for the line there, so for a
--- craft it takes the button's place, and only when the button cannot be used.
local function PlaceDisenchantButton(inBags)
    local detail = widgets.detail
    local button, status = detail.disenchantButton, detail.disenchantStatus

    button:ClearAllPoints()
    status:ClearAllPoints()
    if inBags then
        button:SetPoint("BOTTOMLEFT", detail, "BOTTOMLEFT", 12, 14)
        status:SetPoint("LEFT", button, "RIGHT", 8, 0)
    else
        button:SetPoint("BOTTOMLEFT", detail.addButton, "BOTTOMRIGHT", 8, 0)
        status:SetPoint("LEFT", button, "LEFT", 0, 0)
    end
    status:SetPoint("RIGHT", detail, "RIGHT", -12, 0)
end

local function UpdateDetail(entry)
    local detail = widgets.detail
    local shown = entry ~= nil

    detail.empty:SetShown(not shown)

    for _, line in ipairs(detail.outcomeLines) do
        line.frame:Hide()
    end

    for _, part in ipairs({ detail.icon, detail.title, detail.subtitle, detail.heading,
                            detail.summary, detail.verdict, detail.note }) do
        part:SetShown(shown)
    end

    local isCraft = shown and entry.kind == "craft"
    detail.quantityBox:SetShown(isCraft)
    detail.addButton:SetShown(isCraft)

    -- Disenchant: always for a bag item, and for a craft while one is in
    -- the bags, beside its queue button. Hiding the button takes the secure
    -- button away with it.
    local isBag = shown and entry.kind == "bag"
    local carried = isCraft and ns.Disenchanter:FindSlot(entry.itemID) ~= nil
    local button = detail.disenchantButton

    PlaceDisenchantButton(isBag)
    button:SetShown(isBag or carried)
    detail.disenchantStatus:SetShown(isBag or carried)

    -- A craft's Disenchant button that cannot be used gives way to the
    -- reason. There is no room beside it for both, and greyed out with
    -- nothing said, it looked broken.
    local usable = (isBag or carried) and UpdateDisenchantButton(entry)
    if carried and not usable then button:Hide() end

    if not shown then return end

    detail.title:SetText(entry.name or ("item " .. tostring(entry.itemID)))
    Theme.SetItemIcon(detail.icon, entry.itemID, entry.link)

    local lines = detail.lines

    if entry.kind == "material" then
        detail.heading:Hide()
        detail.subtitle:SetText("Enchanting material")
        detail.verdict:SetText("")

        SetLine(lines[1], "Lowest posting",
            entry.price and Util.FormatMoney(entry.price) or "not scanned yet",
            entry.price and "text" or "dim")
        SetLine(lines[2], "Last scanned",
            entry.age and Util.FormatAgeAgo(entry.age) or "never", entry.stale and "warn" or "muted")
        SetLine(lines[3], "In your bags", tostring(entry.have or 0), "muted")
        SetLine(lines[4], (entry.have or 0) > 0 and entry.price and "Bags worth" or nil,
            entry.price and Util.FormatMoney(entry.price * (entry.have or 0)) or nil)

        detail.note:SetText("Priced at the lowest posting from your last scan, leaving out a lone one far below the rest.")
        return
    end

    local breakdown = entry.breakdown or {}
    local facts = breakdown.facts or {}

    detail.subtitle:SetText(("Item level %d %s %s. Needs Enchanting about %d."):format(
        facts.itemLevel or 0, facts.qualityName or "", facts.isWeapon and "weapon" or "armor",
        facts.skill or 0))

    -- One line per material it can give: the chance, how many, and what that
    -- adds to the average.
    local anchor = detail.heading
    for index, outcome in ipairs(breakdown.outcomes or {}) do
        local line = detail.outcomeLines[index]

        if not line then
            local frame = CreateFrame("Frame", nil, detail)
            frame:SetHeight(16)

            local icon = Theme.CreateItemIcon(frame, 14)
            icon:SetPoint("LEFT", 0, 0)

            -- Its width is set to what the price leaves, see FitOutcomeLine.
            local name = Theme.CreateLabel(frame, "small", "text")
            name:SetPoint("LEFT", 18, 0)
            name:SetWordWrap(true)

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
        local chance = Util.Round(outcome.chance * 100, 1)

        -- Only the most likely outcome is the value; the rest are a bonus.
        line.name:SetText(("%s%%  %sx %s%s"):format(chance, count,
            outcome.name or Util.GetItemLabel(outcome.itemID),
            outcome.counted == false and "  (bonus)" or ""))
        Theme.SetItemIcon(line.icon, outcome.itemID)

        if outcome.price then
            line.value:SetText(Util.FormatMoney(outcome.price, { short = true }) .. " each")
            line.value:SetTextColor(Theme.Unpack("muted"))
        else
            line.value:SetText("no price")
            line.value:SetTextColor(Theme.Unpack("dim"))
        end

        FitOutcomeLine(line)
        line.frame:Show()
        anchor = line.frame
    end

    if entry.value then
        SetLine(lines[1], "Disenchant value",
            Util.FormatMoney(entry.value) .. (entry.partial and "  or more" or ""),
            entry.beatsSale and "profit" or "text")
    else
        SetLine(lines[1], "Disenchant value", "materials not scanned", "dim")
    end

    if entry.sells then
        SetLine(lines[2], entry.sellsAt == "vendor" and "Vendor pays"
            or entry.sellsAt == "estimate" and "Sells for (estimate)" or "Sells for",
            Util.FormatMoney(entry.sells), "muted")
    else
        SetLine(lines[2], "Sells for", entry.soulbound and "soulbound, no vendor price" or "no price", "dim")
    end

    if entry.kind == "craft" then
        SetLine(lines[3], "Materials", entry.cost and Util.FormatMoney(entry.cost) or "no price",
            entry.cost and "muted" or "dim")
        SetLine(lines[4], entry.gain and "Profit after the auction cut" or nil,
            entry.gain and Util.FormatMoney(entry.gain) or nil,
            entry.gain and (entry.gain > 0 and "profit" or "loss") or nil)
    else
        SetLine(lines[3], "In your bags", tostring(entry.count or 0), "muted")
        SetLine(lines[4], nil)
    end

    -- The answer, in words.
    if entry.losesToMaterials then
        detail.verdict:SetText(("Disenchanting beats selling, but loses %s against the materials."):format(
            Util.FormatMoney(-entry.gain, { noColor = true })))
        detail.verdict:SetTextColor(Theme.Unpack("loss"))
    elseif entry.value and entry.sells then
        if entry.beatsSale then
            detail.verdict:SetText(("Disenchanting pays %s more than selling."):format(
                Util.FormatMoney(entry.value - entry.sells, { noColor = true })))
            detail.verdict:SetTextColor(Theme.Unpack("profit"))
        else
            detail.verdict:SetText(("Selling pays %s more than disenchanting."):format(
                Util.FormatMoney(entry.sells - entry.value, { noColor = true })))
            detail.verdict:SetTextColor(Theme.Unpack("muted"))
        end
    elseif entry.value then
        detail.verdict:SetText("Nothing to compare it with: it has no sale price.")
        detail.verdict:SetTextColor(Theme.Unpack("muted"))
    else
        detail.verdict:SetText("Scan the auction house to price its materials.")
        detail.verdict:SetTextColor(Theme.Unpack("warn"))
    end

    local note
    if facts.source == "yours" then
        note = ("Chances come from your own %d disenchants of items like this. Materials are priced at their lowest auction posting, leaving out a lone one far below the rest.")
            :format(facts.casts or 0)
    else
        note = SOURCE_NOTE:format(ns.Disenchant.LEARN_AFTER or 10, facts.casts or 0)
    end
    if entry.kind == "bag" and not entry.soulbound then
        note = note .. " If it is already bound to you, only a vendor will buy it."
    end
    detail.note:SetText(note)

    if entry.kind == "craft" and detail.shownRecipeID ~= entry.recipeID then
        detail.shownRecipeID = entry.recipeID
        detail.quantity:SetText(tostring(math.max(1, entry.craftableNow or 1)))
    end
end

--------------------------------------------------------------------------------
-- List
--------------------------------------------------------------------------------

local function BuildRows()
    local rows

    if state.view == "craft" then
        rows = ns.Disenchant:GetCraftRows({ beatsOnly = state.beatsOnly })
    elseif state.view == "bag" then
        rows = ns.Disenchant:GetBagRows({ beatsOnly = state.beatsOnly })
    else
        rows = ns.Disenchant:GetMaterialRows()
    end

    if state.search ~= "" then
        local needle = state.search:lower()
        local filtered = {}

        for _, row in ipairs(rows) do
            if (row.name or ""):lower():find(needle, 1, true) then
                filtered[#filtered + 1] = row
            end
        end
        rows = filtered
    end

    return rows
end

local function EmptyText()
    if state.search ~= "" then
        return ("Nothing matching \"%s\"."):format(state.search)
    end

    if state.view == "craft" then
        if ns.Recipes:Count() == 0 then
            return "Open a profession window once so your recipes can be read."
        elseif state.beatsOnly then
            return "None of your crafts are worth more disenchanted than sold. Untick \"Only where disenchanting pays more\" to see them all."
        end
        return "None of your crafts make something that can be disenchanted."
    end

    if state.beatsOnly then
        return "Nothing in your bags is worth more disenchanted than sold. Untick \"Only where disenchanting pays more\" to see them all."
    end
    return "Nothing in your bags can be disenchanted."
end

local function ApplyHeadings()
    local view = VIEWS[state.view]
    widgets.nameHeading:SetText(view.heading)

    local offset = -8
    for index = 1, MAX_COLUMNS do
        local heading = widgets.headings[index]
        local column = view.columns[index]

        heading:ClearAllPoints()

        if column then
            heading:SetText(column.label)
            heading:SetPoint("RIGHT", offset, 0)
            heading:SetWidth(column.width)
            heading:Show()
            offset = offset - column.width - 6
        else
            heading:Hide()
        end
    end

    -- The columns now hold other things, so a clicked heading no longer
    -- means what it did.
    if widgets.sorter then
        widgets.sorter:Reset()
        widgets.sorter:Sync()
    end

    widgets.beatsOnly:SetShown(state.view ~= "material")
    widgets.hint:SetShown(state.view ~= "material")
    widgets.hint:SetText(state.view == "craft" and "Right-click a craft to queue one"
        or "Pick an item, then click Disenchant")
end

-- Beside the Disenchant button when the bags list has items but none is worth
-- more disenchanted than sold, so none was picked.
local NOTHING_PICKED = "Nothing here is worth more disenchanted than sold. Click one to disenchant it anyway."

--- No item picked in a bags list that has some: the Disenchant button shows
--- unset, and the line beside it says why.
local function ShowNothingPicked()
    local detail = widgets.detail
    local button = detail.disenchantButton

    PlaceDisenchantButton(true)
    button:SetShown(true)
    button:SetEnabledState(false)
    button.tooltipText = NOTHING_PICKED
    detail.disenchantStatus:SetText(NOTHING_PICKED)
    detail.disenchantStatus:SetShown(true)

    if ns.Disenchanter.anchor == button then ns.Disenchanter:Disarm() end
end

local function Refresh()
    if not widgets.list then return end

    local rows = BuildRows()
    -- A clicked heading's order over the list's own.
    if widgets.sorter then rows = widgets.sorter:Sort(rows) end
    widgets.list:SetData(rows)

    local isList = state.view ~= "material"
    widgets.emptyLabel:SetShown(isList and #rows == 0)
    if isList and #rows == 0 then widgets.emptyLabel:SetText(EmptyText()) end

    if state.view == "material" then
        local priced = 0
        for _, row in ipairs(rows) do
            if row.price then priced = priced + 1 end
        end

        widgets.countLabel:SetText(priced == 0
            and "No enchanting materials scanned yet. Scan the auction house to price them."
            or ("%d of %d materials priced"):format(priced, #rows))
    else
        local beats = 0
        for _, row in ipairs(rows) do
            if row.beatsSale then beats = beats + 1 end
        end

        local noun = state.view == "craft" and "craft" or "item"
        widgets.countLabel:SetText(("%d %s%s, %d worth more disenchanted"):format(
            #rows, noun, #rows == 1 and "" or "s", beats))
    end

    -- Keep the detail panel on the same row with fresh numbers, or clear it
    -- when that row has left the list.
    local before = state.selected
    local fresh
    if state.selected then
        for _, row in ipairs(rows) do
            if SameRow(row, state.selected) then
                fresh = row
                break
            end
        end
    end

    -- In the bags list, the best item worth more disenchanted than sold is
    -- picked when nothing else is, so the Disenchant button is ready on it.
    -- After a disenchant the item leaves the list and the next one takes its
    -- place. One that sells for more is never picked for you; a click on it
    -- still picks it.
    if not fresh and state.view == "bag" then
        for _, row in ipairs(rows) do
            if row.beatsSale then
                fresh = row
                break
            end
        end
    end

    state.selected = fresh
    UpdateDetail(fresh)

    if not fresh and state.view == "bag" and #rows > 0 then ShowNothingPicked() end

    -- The rows were drawn before this pick, so light the picked one now.
    if fresh and not SameRow(fresh, before) then widgets.list:Refresh() end
end

--------------------------------------------------------------------------------
-- Build
--------------------------------------------------------------------------------

local function Build(container)
    local toolbar = CreateFrame("Frame", nil, container)
    toolbar:SetPoint("TOPLEFT", 8, -8)
    toolbar:SetPoint("TOPRIGHT", -8, -8)
    toolbar:SetHeight(24)

    local view = Widgets.CreateDropdown(toolbar, {
        { text = "Show: Your crafts", value = "craft" },
        { text = "Show: Items in your bags", value = "bag" },
        { text = "Show: Enchanting materials", value = "material" },
    }, function(value)
        state.view = value or "craft"
        state.selected = nil
        ApplyHeadings()
        widgets.list:ScrollToTop()
        Refresh()
    end, { width = 200 })
    view:SetPoint("LEFT", 0, 0)
    view:SetValue(state.view)

    local search = Widgets.CreateSearchBox(toolbar, "Search", function(text)
        state.search = text or ""
        Refresh()
    end)
    search:SetPoint("LEFT", view, "RIGHT", 8, 0)
    search:SetWidth(Widgets.SEARCH_WIDTH)

    local beatsOnly = Widgets.CreateCheckbox(toolbar, "Only where disenchanting pays more", function(checked)
        state.beatsOnly = checked
        Refresh()
    end, state.beatsOnly)
    beatsOnly:SetPoint("LEFT", search, "RIGHT", 12, 0)
    widgets.beatsOnly = beatsOnly

    -- Column headings
    local headings = CreateFrame("Frame", nil, container)
    headings:SetPoint("TOPLEFT", toolbar, "BOTTOMLEFT", 0, -8)
    headings:SetPoint("TOPRIGHT", toolbar, "BOTTOMRIGHT", -DETAIL_WIDTH - 8, -8)
    headings:SetHeight(16)

    local nameHeading = Theme.CreateLabel(headings, "tiny", "muted")
    nameHeading:SetPoint("LEFT", 8 + ICON_GUTTER, 0)
    widgets.nameHeading = nameHeading

    widgets.headings = {}
    for index = 1, MAX_COLUMNS do
        widgets.headings[index] = Theme.CreateLabel(headings, "tiny", "muted", "RIGHT")
    end

    -- Click a heading to sort by it. The headings change with the view, so
    -- each one reads whatever column the view puts there.
    local FIELDS = {
        make = function(row) return row.craftableNow end,
        age = function(row) return row.price and row.age or nil end,
    }
    local sortLabels, values = { name = nameHeading }, {
        name = function(row) return row.name end,
    }
    for index = 1, MAX_COLUMNS do
        sortLabels[index] = widgets.headings[index]
        values[index] = function(row)
            local column = VIEWS[state.view].columns[index]
            if not column then return nil end
            local field = FIELDS[column.key]
            if field then return field(row) end
            return row[column.key]
        end
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
            return SameRow(entry, state.selected)
        end,

        onClick = function(entry, _, mouseButton)
            if mouseButton == "RightButton" and entry.kind == "craft" then
                ns.Queue:Add(entry.recipeID, 1)
                ns.Print(("queued 1x %s"):format(entry.name or "craft"))
                return
            end

            state.selected = entry
            UpdateDetail(entry)
        end,
    })

    list:SetPoint("TOPLEFT", divider, "BOTTOMLEFT", 0, -4)
    list:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", -DETAIL_WIDTH - 16, 24)
    widgets.list = list

    local emptyLabel = Theme.CreateLabel(container, "small", "dim", "CENTER")
    emptyLabel:SetPoint("CENTER", list, "CENTER", 0, 10)
    emptyLabel:SetWidth(360)
    emptyLabel:SetWordWrap(true)
    widgets.emptyLabel = emptyLabel

    local countLabel = Theme.CreateLabel(container, "tiny", "dim")
    countLabel:SetPoint("BOTTOMLEFT", 8, 8)
    widgets.countLabel = countLabel

    local hint = Theme.CreateLabel(container, "tiny", "dim", "RIGHT")
    hint:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", -DETAIL_WIDTH - 16, 8)
    hint:SetText("Right-click a craft to queue one")
    widgets.hint = hint

    local detail = BuildDetail(container)
    detail:SetPoint("TOPRIGHT", container, "TOPRIGHT", -8, -40)
    detail:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", -8, 8)
    widgets.detail = detail

    ApplyHeadings()
    UpdateDetail(nil)

    -- Items the client had not cached are left out until it has them, since
    -- their level and quality decide everything. Redraw once they arrive,
    -- coalescing a burst of arrivals into one pass.
    local redrawQueued = false

    ns.RegisterEvent(UI, "GET_ITEM_INFO_RECEIVED", function(_, _, itemID)
        if redrawQueued or not widgets.list:IsVisible() then return end

        -- Only items this addon asked for. At the auction house, Ready to
        -- sell reloads bag items all the time, and redrawing for each of
        -- those re-read every recipe a few times a second.
        if itemID and ns.Disenchant.WasRequested and not ns.Disenchant:WasRequested(itemID) then return end

        redrawQueued = true
        C_Timer.After(0.3, function()
            redrawQueued = false
            -- Not once the player has moved to another tab. Redrawn hidden,
            -- this tab took the Disenchant button from the Disenchanting tab
            -- on screen and aimed it at its own item. It redraws when shown.
            if widgets.list:IsVisible() then Refresh() end
        end)
    end)
end

UI:RegisterTab({
    key = "enchanting",
    text = "Enchanting",
    order = 1.7,
    build = Build,
    refresh = Refresh,
})
