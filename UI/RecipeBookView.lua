-- Blackthornes Tradeskills -- UI/RecipeBookView.lua
-- The Profit tab's Recipes to learn view: every recipe of a profession that
-- the character playing has not learned, with what one craft costs, sells
-- and disenchants for, and what the recipe costs to get.
--
-- Asked 2026-10-05 by a player who wanted to judge "if it's worth it to get
-- a recipe or not at a glance", and "even a list of all recipes possible for
-- a profession". The numbers come from Logic/RecipeBook.lua; the pane on the
-- right says where a picked recipe is learned and what goes into it.

local _, ns = ...

local Theme = ns.Theme
local Widgets = ns.Widgets
local Util = ns.Util

local RecipeBookView = {}
ns.RecipeBookView = RecipeBookView

local ROW_HEIGHT = 22
local DETAIL_WIDTH = 300
local ALL = "all"

-- Right to left, measured from the list's right edge.
local COLUMNS = {
    { key = "learn",      label = "LEARN FROM", width = 92 },
    { key = "price",      label = "RECIPE",     width = 66 },
    { key = "profit",     label = "PROFIT",     width = 70 },
    { key = "disenchant", label = "DISENCHANT", width = 66 },
    { key = "sells",      label = "SELLS",      width = 66 },
    { key = "cost",       label = "COST",       width = 66 },
    { key = "skill",      label = "SKILL",      width = 36 },
}

local state = {
    search = "",
    profession = nil,
    includeKnown = false,
    selected = nil,
    waiting = false,
}

local widgets = {}

--------------------------------------------------------------------------------
-- Rows
--------------------------------------------------------------------------------

local function CreateRow(row)
    row.icon = Theme.CreateItemIcon(row, 16)
    row.icon:SetPoint("LEFT", 8, 0)

    row.name = Theme.CreateLabel(row, "small", "text")
    row.name:SetPoint("LEFT", 30, 0)
    row.name:SetWordWrap(false)

    row.cells = {}

    local offset, reserved = -8, 16
    for _, column in ipairs(COLUMNS) do
        local cell = Theme.CreateLabel(row, "small", "muted", "RIGHT")
        cell:SetPoint("RIGHT", offset, 0)
        cell:SetWidth(column.width)
        cell:SetWordWrap(false)
        row.cells[column.key] = cell

        offset = offset - column.width - 8
        reserved = reserved + column.width + 8
    end

    row.name:SetPoint("RIGHT", row, "RIGHT", -reserved, 0)
end

local function SetMoney(cell, copper, colorKey)
    if copper == nil then
        cell:SetText("--")
        cell:SetTextColor(Theme.Unpack("dim"))
        return
    end
    Theme.SetMoneyText(cell, copper, { short = true })
    cell:SetTextColor(Theme.Unpack(colorKey or "text"))
end

local function UpdateRow(row, entry)
    -- No item made (an enchant): the recipe item's icon stands in.
    local iconItem = entry.outputItemID or (entry.record.recipeItems and entry.record.recipeItems[1])
    Theme.SetItemIcon(row.icon, iconItem)
    if iconItem then
        local ok, name = pcall(function() return C_Item.GetItemInfo(iconItem) end)
        if not ok or not name then state.waiting = true end
    end

    row.name:SetText(entry.name)
    row.name:SetTextColor(Theme.Unpack(entry.known and "dim" or "text"))

    local cells = row.cells
    cells.skill:SetText(entry.skill and entry.skill > 0 and tostring(entry.skill) or "")
    cells.skill:SetTextColor(Theme.Unpack("muted"))

    SetMoney(cells.cost, entry.cost, "muted")

    if not entry.outputItemID then
        cells.sells:SetText("no item")
        cells.sells:SetTextColor(Theme.Unpack("dim"))
    else
        SetMoney(cells.sells, entry.auction)
    end

    if entry.disenchant then
        SetMoney(cells.disenchant, entry.disenchant)
    else
        cells.disenchant:SetText("")
    end

    if entry.profit then
        Theme.SetMoneyText(cells.profit, entry.profit, { short = true })
        cells.profit:SetTextColor(Theme.ProfitColor(entry.profit))
    else
        cells.profit:SetText("--")
        cells.profit:SetTextColor(Theme.Unpack("dim"))
    end

    SetMoney(cells.price, entry.price, "muted")

    cells.learn:SetText(entry.known and "Known" or entry.learn)
    cells.learn:SetTextColor(Theme.Unpack(entry.known and "profit" or "muted"))
end

local function ShowRowTooltip(row, entry)
    if entry.outputItemID then
        Widgets.ShowItemOnly(row, entry.outputItemID, entry.name)
    else
        GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
        GameTooltip:SetText(entry.name, 1, 1, 1)
    end

    local _, where = ns.RecipeBook:LearnFrom(entry.record)
    if #where > 0 then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Learned from", Theme.Unpack("accent"))
        for _, line in ipairs(where) do
            GameTooltip:AddLine(line, 1, 1, 1, true)
        end
    end

    if entry.payback then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(("Pays for itself after %d craft%s"):format(
            entry.payback, entry.payback == 1 and "" or "s"), Theme.Unpack("profit"))
    end

    GameTooltip:Show()
end

--------------------------------------------------------------------------------
-- Detail pane
--------------------------------------------------------------------------------

local VALUE_LINES = 7
local MATERIAL_LINES = 5
local LEARN_LINES = 4

local function DoubleLine(parent, anchor, gap)
    local line = CreateFrame("Frame", nil, parent)
    line:SetHeight(16)
    line:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -(gap or 1))
    line:SetPoint("RIGHT", parent, "RIGHT", -12, 0)

    line.label = Theme.CreateLabel(line, "small", "muted")
    line.label:SetPoint("LEFT", 0, 0)
    line.label:SetPoint("RIGHT", line, "RIGHT", -120, 0)
    line.label:SetWordWrap(false)

    line.value = Theme.CreateLabel(line, "small", "text", "RIGHT")
    line.value:SetPoint("RIGHT", 0, 0)
    line.value:SetWidth(116)
    line.value:SetWordWrap(false)

    return line
end

local function BuildDetail(parent)
    local detail = Theme.CreatePanel(parent, "window")
    Theme.AccentStripe(detail, 2, 0.6)
    detail:SetWidth(DETAIL_WIDTH)

    detail.title = Theme.CreateLabel(detail, "normal", "accent")
    detail.title:SetPoint("TOPLEFT", 12, -12)
    detail.title:SetPoint("TOPRIGHT", -12, -12)
    detail.title:SetWordWrap(true)

    detail.subtitle = Theme.CreateLabel(detail, "tiny", "muted")
    detail.subtitle:SetPoint("TOPLEFT", detail.title, "BOTTOMLEFT", 0, -4)
    detail.subtitle:SetPoint("TOPRIGHT", detail.title, "BOTTOMRIGHT", 0, -4)
    detail.subtitle:SetWordWrap(true)

    detail.worthHeading = Theme.CreateHeading(detail, "ONE CRAFT")
    detail.worthHeading:SetPoint("TOPLEFT", detail.subtitle, "BOTTOMLEFT", 0, -10)

    detail.values = {}
    local anchor = detail.worthHeading
    for index = 1, VALUE_LINES do
        local line = DoubleLine(detail, anchor, index == 1 and 5 or 1)
        detail.values[index] = line
        anchor = line
    end

    detail.materialsHeading = Theme.CreateHeading(detail, "MATERIALS")
    detail.materialsHeading:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -8)

    detail.materials = {}
    anchor = detail.materialsHeading
    for index = 1, MATERIAL_LINES do
        local line = DoubleLine(detail, anchor, index == 1 and 5 or 1)
        detail.materials[index] = line
        anchor = line
    end

    detail.learnHeading = Theme.CreateHeading(detail, "WHERE TO LEARN IT")
    detail.learnHeading:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -8)

    detail.learn = Theme.CreateLabel(detail, "small", "text")
    detail.learn:SetPoint("TOPLEFT", detail.learnHeading, "BOTTOMLEFT", 0, -6)
    detail.learn:SetPoint("RIGHT", detail, "RIGHT", -12, 0)
    detail.learn:SetWordWrap(true)

    detail.note = Theme.CreateLabel(detail, "tiny", "dim")
    detail.note:SetPoint("BOTTOMLEFT", 12, 12)
    detail.note:SetPoint("BOTTOMRIGHT", -12, 12)
    detail.note:SetWordWrap(true)

    return detail
end

local function SetLine(line, label, value, colorKey)
    if not label then
        line:Hide()
        return
    end
    line.label:SetText(label)
    line.value:SetText(value or "")
    line.value:SetTextColor(Theme.Unpack(colorKey or "text"))
    line:Show()
end

local function Money(copper)
    return Util.FormatMoney(copper, { short = true })
end

local PRICE_HOW = { trainer = "at a trainer", vendor = "from a vendor", auction = "on the auction house" }

local function ShowNothing(detail)
    detail.title:SetText("Recipes to learn")
    detail.subtitle:SetText("Pick a recipe to see what goes into it and where to learn it.")
    for _, line in ipairs(detail.values) do line:Hide() end
    for _, line in ipairs(detail.materials) do line:Hide() end
    detail.worthHeading:Hide()
    detail.materialsHeading:Hide()
    detail.learnHeading:Hide()
    detail.learn:SetText("")
    detail.note:SetText("Values use the prices you have scanned. Recipes come from Classic's data, "
        .. "corrected by what your profession windows show.")
end

local function ShowEntry(detail, entry)
    local record = entry.record
    local value = ns.RecipeBook:Value(record)
    local returns = value.returns or {}

    detail.title:SetText(entry.name)

    local parts = {}
    if record.profession then
        parts[#parts + 1] = record.skill and record.skill > 0
            and ("%s %d"):format(record.profession, record.skill) or record.profession
    end
    local knownBy = ns.RecipeBook:KnownByText(record)
    parts[#parts + 1] = knownBy and ("known by " .. knownBy) or "nobody on this account knows it"
    detail.subtitle:SetText(table.concat(parts, "  ·  "))

    detail.worthHeading:Show()
    local rows = {}
    rows[#rows + 1] = { "Cost to make", value.cost and Money(value.cost) or "not scanned",
        value.cost and "text" or "dim" }
    if record.outputItemID then
        rows[#rows + 1] = { "Sells for, after the cut",
            returns.auction and Money(returns.auction) or "not scanned", returns.auction and "text" or "dim" }
        if returns.disenchant then rows[#rows + 1] = { "Disenchants for", Money(returns.disenchant) } end
        if returns.vendor then rows[#rows + 1] = { "Vendors for", Money(returns.vendor) } end
        if value.profit then
            rows[#rows + 1] = { value.backWay and value.backWay ~= "auction"
                    and ("Profit, by %s"):format(value.backWay) or "Profit",
                Money(value.profit), value.profit >= 0 and "profit" or "loss" }
        end
    else
        rows[#rows + 1] = { "Makes", "no item to sell", "dim" }
    end
    if value.price then
        rows[#rows + 1] = { "Recipe, " .. (PRICE_HOW[value.priceHow] or ""), Money(value.price) }
    end
    if value.payback then
        rows[#rows + 1] = { "Pays for itself after", ("%d craft%s"):format(value.payback,
            value.payback == 1 and "" or "s"), "profit" }
    elseif value.profit and value.profit <= 0 then
        rows[#rows + 1] = { "Pays for itself", "not at today's prices", "warn" }
    end
    for index, line in ipairs(detail.values) do
        local row = rows[index]
        SetLine(line, row and row[1], row and row[2], row and row[3])
    end

    detail.materialsHeading:Show()
    local reagents = (value.costDetail and value.costDetail.reagents) or {}
    for index, line in ipairs(detail.materials) do
        local reagent = reagents[index]
        if reagent then
            local name = Util.GetItemLabel(reagent.itemID)
            if index == MATERIAL_LINES and #reagents > MATERIAL_LINES then
                SetLine(line, ("and %d more"):format(#reagents - MATERIAL_LINES + 1), "", "dim")
            else
                SetLine(line, ("%dx %s"):format(reagent.quantity, Util.Uncolored(name)),
                    reagent.lineCost and Money(reagent.lineCost) or "not scanned",
                    reagent.lineCost and "text" or "dim")
            end
        else
            line:Hide()
        end
    end

    detail.learnHeading:Show()
    local _, where = ns.RecipeBook:LearnFrom(record)
    local shown = {}
    for index = 1, math.min(#where, LEARN_LINES) do shown[index] = where[index] end
    if #where > LEARN_LINES then
        shown[LEARN_LINES] = ("and %d more places"):format(#where - LEARN_LINES + 1)
    end
    detail.learn:SetText(#shown > 0 and table.concat(shown, "\n") or "Not known yet.")
    detail.note:SetText("")
end

--------------------------------------------------------------------------------
-- Refresh
--------------------------------------------------------------------------------

--- The professions to offer: those of the character playing first, so the
--- view opens on one of them, then the rest.
local function ProfessionOptions()
    local options = { { value = ALL, text = "All professions" } }
    local mine, first = {}, nil

    if ns.Recipes and ns.Recipes.GetLearnedProfessions then
        for _, profession in ipairs(ns.Recipes:GetLearnedProfessions()) do
            mine[profession.name] = true
        end
    end

    for _, name in ipairs(ns.RecipeBook:GetProfessions()) do
        if mine[name] then
            options[#options + 1] = { value = name, text = name }
            first = first or name
        end
    end
    for _, name in ipairs(ns.RecipeBook:GetProfessions()) do
        if not mine[name] then options[#options + 1] = { value = name, text = name } end
    end

    return options, first
end

function RecipeBookView.Refresh()
    if not widgets.list or not ns.RecipeBook then return end

    local options, first = ProfessionOptions()
    widgets.profession:SetOptions(options)
    if state.profession == nil then state.profession = first or ALL end
    widgets.profession:SetValue(state.profession)

    state.waiting = false

    local rows = ns.RecipeBook:List({
        profession = state.profession ~= ALL and state.profession or nil,
        includeKnown = state.includeKnown,
        search = state.search,
    })
    if widgets.sorter then rows = widgets.sorter:Sort(rows) end

    widgets.list:SetData(rows)

    widgets.empty:SetShown(#rows == 0)
    if #rows == 0 then
        if state.search ~= "" then
            widgets.empty:SetText(("Nothing matching \"%s\"."):format(state.search))
        else
            widgets.empty:SetText("You know every recipe of this profession.")
        end
    end

    local paying = 0
    for _, entry in ipairs(rows) do
        if entry.profit and entry.profit > 0 then paying = paying + 1 end
    end
    widgets.summary:SetText(("%d recipe%s  ·  %d make a profit at today's prices"):format(
        #rows, #rows == 1 and "" or "s", paying))

    local selected
    if state.selected then
        for _, entry in ipairs(rows) do
            if entry.recipeID == state.selected then selected = entry break end
        end
        if not selected then state.selected = nil end
    end

    if selected then
        ShowEntry(widgets.detail, selected)
    else
        ShowNothing(widgets.detail)
    end
end

--- Open on a profession, by name (any case) or part of one.
function RecipeBookView.SetProfession(name)
    if not name then return end
    local needle = name:lower()
    for _, profession in ipairs(ns.RecipeBook:GetProfessions()) do
        if profession:lower():find(needle, 1, true) then
            state.profession = profession
            state.selected = nil
            return
        end
    end
end

--------------------------------------------------------------------------------
-- Build
--------------------------------------------------------------------------------

--- Fill `view`, a frame covering the Profit tab below its view switch.
function RecipeBookView.Build(view)
    local right = -DETAIL_WIDTH - 16

    local search = Widgets.CreateSearchBox(view, "Search recipes", function(text)
        state.search = text or ""
        RecipeBookView.Refresh()
    end)
    search:SetPoint("TOPLEFT", 8, -8)
    search:SetWidth(190)

    local profession = Widgets.CreateDropdown(view, { { value = ALL, text = "All professions" } },
        function(value)
            state.profession = value
            state.selected = nil
            RecipeBookView.Refresh()
        end, { width = 150 })
    profession:SetPoint("LEFT", search, "RIGHT", 8, 0)
    widgets.profession = profession

    local known = Widgets.CreateCheckbox(view, "Show learned too", function(checked)
        state.includeKnown = checked and true or false
        RecipeBookView.Refresh()
    end, false)
    known:SetPoint("LEFT", profession, "RIGHT", 12, 0)

    local headings = CreateFrame("Frame", nil, view)
    headings:SetHeight(16)
    headings:SetPoint("TOPLEFT", 8, -40)
    headings:SetPoint("TOPRIGHT", view, "TOPRIGHT", right, -40)

    local nameHeading = Theme.CreateLabel(headings, "tiny", "muted")
    nameHeading:SetPoint("LEFT", 30, 0)
    nameHeading:SetText("RECIPE")

    headings.cells = {}
    local offset = -8
    for _, column in ipairs(COLUMNS) do
        local cell = Theme.CreateLabel(headings, "tiny", "muted", "RIGHT")
        cell:SetPoint("RIGHT", offset, 0)
        cell:SetWidth(column.width)
        cell:SetText(column.label)
        headings.cells[column.key] = cell
        offset = offset - column.width - 8
    end

    local sortLabels = { name = nameHeading }
    for key, cell in pairs(headings.cells) do sortLabels[key] = cell end
    widgets.sorter = Widgets.SortableHeadings and Widgets.SortableHeadings(sortLabels, {
        name = function(entry) return entry.name end,
        skill = function(entry) return entry.skill end,
        cost = function(entry) return entry.cost end,
        sells = function(entry) return entry.auction end,
        disenchant = function(entry) return entry.disenchant end,
        profit = function(entry) return entry.profit end,
        price = function(entry) return entry.price end,
        learn = function(entry) return entry.known and "Known" or entry.learn end,
    }, function() RecipeBookView.Refresh() end)
    if widgets.sorter then widgets.sorter:SetText({ "name", "learn" }) end

    local divider = Theme.CreateDivider(view, "borderLit")
    divider:SetPoint("TOPLEFT", headings, "BOTTOMLEFT", 0, -2)
    divider:SetPoint("TOPRIGHT", headings, "BOTTOMRIGHT", 0, -2)

    local list = Widgets.CreateScrollList(view, {
        rowHeight = ROW_HEIGHT,
        createRow = CreateRow,
        updateRow = UpdateRow,

        isSelected = function(entry)
            return state.selected ~= nil and entry.recipeID == state.selected
        end,

        onClick = function(entry)
            state.selected = state.selected ~= entry.recipeID and entry.recipeID or nil
            RecipeBookView.Refresh()
        end,

        onEnter = ShowRowTooltip,
        onLeave = function() GameTooltip:Hide() end,

        onScrollbarShown = function(shown)
            headings:SetPoint("TOPRIGHT", view, "TOPRIGHT", right - (shown and 10 or 0), -40)
        end,
    })
    list:SetPoint("TOPLEFT", divider, "BOTTOMLEFT", 0, -4)
    list:SetPoint("BOTTOMRIGHT", view, "BOTTOMRIGHT", right, 24)
    widgets.list = list

    local empty = Theme.CreateLabel(view, "small", "dim", "CENTER")
    empty:SetPoint("CENTER", list, "CENTER")
    empty:SetWidth(320)
    empty:SetWordWrap(true)
    widgets.empty = empty

    local summary = Theme.CreateLabel(view, "tiny", "dim")
    summary:SetPoint("BOTTOMLEFT", 8, 8)
    widgets.summary = summary

    local detail = BuildDetail(view)
    detail:SetPoint("TOPRIGHT", view, "TOPRIGHT", -8, -8)
    detail:SetPoint("BOTTOMRIGHT", view, "BOTTOMRIGHT", -8, 8)
    widgets.detail = detail
    ShowNothing(detail)

    -- Items the client has not loaded draw without an icon or a sell price;
    -- drawn again once they arrive, a burst of them as one redraw.
    local redrawQueued = false
    ns.RegisterEvent(RecipeBookView, "GET_ITEM_INFO_RECEIVED", function(_, _, _, success)
        if success == false then return end
        if redrawQueued or not state.waiting then return end
        if not list:IsVisible() then return end

        redrawQueued = true
        C_Timer.After(0.3, function()
            redrawQueued = false
            RecipeBookView.Refresh()
        end)
    end)
end

--- For the tests.
RecipeBookView._state = state
RecipeBookView._widgets = widgets
