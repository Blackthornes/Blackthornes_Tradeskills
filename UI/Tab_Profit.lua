-- Blackthornes Tradeskills -- UI/Tab_Profit.lua
-- The headline table: what is worth making, and why.

local _, ns = ...

local Theme = ns.Theme
local Widgets = ns.Widgets
local Util = ns.Util

local UI = ns.UI

local ROW_HEIGHT = 22
local DETAIL_WIDTH = 300

-- The detail pane's summary lines: materials, prices, cut, profit.
local SUMMARY_ROW_HEIGHT = 17

-- Room at the left of every row for the skill-up star. Always reserved, shown
-- or not, so the craft names stay in one straight line down the list -- names
-- that shuffle sideways as the marks come and go are worse than the gap.
local MARK_GUTTER = 16

-- The made item's icon, between the star and the name.
local ICON_SIZE = 16
local ICON_GUTTER = ICON_SIZE + 4

-- The columns, measured from the right edge of the list and laid out right
-- to left. Money sits to the right, so its coins line up down the column;
-- everything else is centred under its heading. `width` is the least each
-- gets: Widgets.FitColumns widens it to fit the heading and a full amount.
-- WHO only earns its space when more than one character is in play, so it
-- is hidden otherwise and the craft name takes the room back.
local COLUMNS = {
    { key = "age",    label = "AGE",    width = 40, justify = "CENTER" },
    { key = "posted", label = "STOCK",  width = 44, justify = "CENTER" },
    -- How well it sells (Logic/Demand.lua), beside what you already hold:
    -- together they say whether to make more.
    { key = "demand", label = "DEMAND", width = 50, justify = "CENTER" },
    { key = "make",   label = "MAKE",   width = 40, justify = "CENTER" },
    { key = "who",    label = "WHO",    width = 58, justify = "CENTER", accountWideOnly = true },
    { key = "margin", label = "MARGIN", width = 46, justify = "CENTER" },
    -- Which way the profit is for (AH, Vendor, DE), when the list is
    -- ranked by whichever pays most. Ranked by one way, it says nothing.
    { key = "via",    label = "VIA",    width = 44, justify = "CENTER", bestOnly = true },
    { key = "profit", label = "PROFIT", width = 74, money = true },
    -- Beside SELLS so the two read against each other. Only shown when
    -- something in the list can be disenchanted.
    { key = "disenchant", label = "DISENCHANT", width = 62, money = true, disenchantOnly = true },
    { key = "sells",  label = "SELLS",  width = 70, money = true },
    { key = "cost",   label = "COST",   width = 70, money = true },
}

-- Bumped whenever the visible column set changes, so recycled rows know to
-- re-anchor rather than keeping a stale layout.
local layoutVersion = 1

-- Forward declaration: defined below, used by the toolbar built after it.
local ApplyHeadingLayout

local state = {
    search = "",
    accountWide = false,
    showDisenchant = false,
    ignorePostLimit = false,
    profession = nil,
    craftableOnly = false,
    includeUnpriceable = false,
    sortBy = "profit",
    selected = nil,
}

local widgets = {}

-- The row hint, as much of it as fits beside the count on its left.
local HINT_TEXTS = {
    "Right-click a row to queue one, Shift-click to search the auction house",
    "Right-click to queue, Shift-click to search",
    "Right-click a row to queue one",
}

local function FitHint()
    local hint, count, list = widgets.hint, widgets.countLabel, widgets.list
    if not (hint and count and list and Theme.TextWidth and Theme.FitText) then return end
    local listWidth = list:GetWidth()
    local used = Theme.TextWidth(count) or 0
    local room = type(listWidth) == "number" and listWidth > 0 and (listWidth - used - 124) or nil
    Theme.FitText(hint, HINT_TEXTS, room)
end

--------------------------------------------------------------------------------
-- Rows
--------------------------------------------------------------------------------

--- What the profit is for: Settings' "profitBy", "best" unless picked.
local function Method()
    return ns.Profit.GetMethod and ns.Profit:GetMethod() or nil
end

local function IsColumnVisible(column)
    if column.accountWideOnly then return state.accountWide end
    if column.bestOnly then return Method() == "best" end
    if column.disenchantOnly then return state.showDisenchant end
    return true
end

--- Position the numeric columns and give the craft name whatever is left.
local function ApplyRowLayout(row)
    local offset = -8

    for _, column in ipairs(COLUMNS) do
        local cell = row.cells[column.key]

        if IsColumnVisible(column) then
            cell:SetPoint("RIGHT", row, "RIGHT", offset, 0)
            cell:SetWidth(column.width)
            cell:Show()
            offset = offset - column.width - 6
        else
            cell:Hide()
        end
    end

    row.name:SetPoint("RIGHT", row, "RIGHT", offset - 4, 0)

    -- The margin's bar sits centred under its number.
    row.marginBar:SetPoint("TOP", row.cells.margin, "BOTTOM", 0, -1)

    row.layoutVersion = layoutVersion
end

local function CreateRow(row)
    row.mark = Theme.CreateMark(row)
    row.mark:SetPoint("LEFT", 7, 0)

    row.icon = Theme.CreateItemIcon(row, ICON_SIZE)
    row.icon:SetPoint("LEFT", 8 + MARK_GUTTER, 0)

    row.name = Theme.CreateLabel(row, "small", "text")
    row.name:SetPoint("LEFT", 8 + MARK_GUTTER + ICON_GUTTER, 0)

    row.cells = {}
    for _, column in ipairs(COLUMNS) do
        row.cells[column.key] = Theme.CreateLabel(row, "small", "text", column.justify or "RIGHT")
    end

    row.marginBar = Theme.CreateBar(row, 40, 2)

    ApplyRowLayout(row)
end

-- Item data arrives from the server on its own schedule, so the first pass
-- over a recipe whose output is not cached yet gets no colour back. Those rows
-- are drawn in the plain text colour and remembered here; GET_ITEM_INFO_RECEIVED
-- redraws them once the client has the item.
local awaitingItemData = false

--- Colour a craft's name by the rarity of the item it makes.
--
-- Rarity is what tells the player whether a craft is worth making at all, so it
-- is on every row, including ones that cannot be made or priced right now.
local function ApplyNameColor(row, analysis)
    local r, g, b = Util.GetItemQualityColor(analysis.outputItemID)

    if r then
        row.name:SetTextColor(r, g, b)
        return
    end

    row.name:SetTextColor(Theme.Unpack("text"))
    if analysis.outputItemID then awaitingItemData = true end
end

--- How many of this craft the materials on hand cover.
--
-- This column exists because the name no longer carries it: greying the name
-- out was the old "you are short of materials", and it drowned out rarity.
local function UpdateMakeCell(cells, analysis)
    local craftable = analysis.craftableNow or 0

    if craftable > 0 then
        cells.make:SetText(tostring(craftable))
        cells.make:SetTextColor(Theme.Unpack("text"))
    else
        cells.make:SetText("0")
        cells.make:SetTextColor(Theme.Unpack("loss"))
    end
end

--- What the craft is worth disenchanted. Green when that beats selling it,
--- so the rows where it does stand out down the column.
local function UpdateDisenchantCell(cells, analysis)
    local cell = cells.disenchant

    if analysis.disenchantValue then
        Theme.SetMoneyText(cell, analysis.disenchantValue, { short = true })
        cell:SetTextColor(Theme.Unpack(analysis.disenchantBeatsSale and "profit" or "muted"))
    elseif analysis.disenchantable then
        cell:SetText("no price")
        cell:SetTextColor(Theme.Unpack("dim"))
    else
        cell:SetText("")
    end
end

--- Say so on the row's tooltip when disenchanting pays more than selling.
local function AddDisenchantLine(analysis)
    if not analysis.disenchantBeatsSale or not GameTooltip:IsShown() then return end

    GameTooltip:AddLine(("Disenchanting it is worth %s more than selling it."):format(
        Util.FormatMoney(analysis.disenchantValue - (analysis.unitRevenue or 0), { noColor = true })),
        0.35, 0.85, 0.45, true)
    GameTooltip:Show()
end

--- What the craft makes each way it can be turned into gold, the one the
--- profit is for in gold. Returns whether it added anything.
local function AddWaysLines(analysis)
    if not ns.Profit.DescribeWays or not GameTooltip:IsShown() then return false end

    local lines = ns.Profit:DescribeWays(analysis)
    if #lines == 0 then return false end

    GameTooltip:AddLine(" ")
    for _, line in ipairs(lines) do
        local label = line.label .. (line.note and (" (" .. line.note .. ")") or "")
        local r, g, b = 0.7, 0.7, 0.7
        if line.chosen then r, g, b = Theme.Unpack("accent") end
        local vr, vg, vb = Theme.Unpack(line.profit >= 0 and "profit" or "loss")
        GameTooltip:AddDoubleLine(label, Util.FormatMoney(line.profit, { noColor = true }),
            r, g, b, vr, vg, vb)
    end
    GameTooltip:Show()
    return true
end

--- The full name of who can make it, since the WHO column shows it shortened.
local function AddOwnerLine(analysis)
    if not state.accountWide or not analysis.ownerName or not GameTooltip:IsShown() then return end

    GameTooltip:AddLine(("Crafted by %s"):format(analysis.ownerName), 0.7, 0.7, 0.7)
    GameTooltip:Show()
end

--- A cell's text, or its short form when the full one runs past the cell.
--- Measured, so a narrow column never ends in "..." on a wide font.
local function SetFitted(cell, text, short)
    cell:SetText(text)
    if not short then return end

    local ok, width = pcall(cell.GetStringWidth, cell)
    local room = cell:GetWidth()
    if ok and type(width) == "number" and type(room) == "number" and room > 0 and width > room then
        cell:SetText(short)
    end
end

local function UpdateRow(row, analysis)
    -- Rows are recycled, so one built under a different column set has to
    -- be re-anchored before it is filled.
    if row.layoutVersion ~= layoutVersion then
        ApplyRowLayout(row)
    end

    row.name:SetText(analysis.name or ("recipe " .. analysis.recipeID))
    Theme.SetItemIcon(row.icon, analysis.outputItemID)
    row.marginBar:Set(nil)

    local cells = row.cells

    -- All three hold whatever the row's price data looks like, so they are
    -- filled before the unpriceable case takes its early exit.
    ApplyNameColor(row, analysis)
    UpdateMakeCell(cells, analysis)
    UpdateDisenchantCell(cells, analysis)

    -- The star: this craft raises your skill AND turns a profit. Set from
    -- analysis.recommended rather than from the tier alone, so an orange
    -- recipe that loses gold is not recommended by the back door.
    Theme.SetMark(row.mark, analysis.recommended
        and analysis.skillUp and analysis.skillUp.tier or nil)

    -- Only meaningful when several characters are in play.
    if state.accountWide then
        cells.who:SetText(analysis.ownerShortName or analysis.ownerName or "")
        cells.who:SetTextColor(Theme.Unpack(analysis.isMine and "accent" or "muted"))
    else
        cells.who:SetText("")
    end

    -- Shown on unpriced rows too: what sold needs no price.
    local reading = ns.Demand and ns.Demand:Get(analysis.outputItemID)
    if reading then
        cells.demand:SetText(ns.Demand:Label(reading))
        cells.demand:SetTextColor(Theme.Unpack(ns.Demand:Color(reading)))
    else
        cells.demand:SetText("--")
        cells.demand:SetTextColor(Theme.Unpack("dim"))
    end

    -- Everything you already hold: listed, plus bags and bank.
    local stock = analysis.stock or 0

    if analysis.postLimit and analysis.postLimit > 0 then
        cells.posted:SetText(("%d/%d"):format(stock, analysis.postLimit))
        cells.posted:SetTextColor(Theme.Unpack(analysis.atPostLimit and "warn" or "muted"))
    elseif stock > 0 then
        cells.posted:SetText(tostring(stock))
        cells.posted:SetTextColor(Theme.Unpack("muted"))
    else
        cells.posted:SetText("")
    end

    if not analysis.priceable then
        cells.cost:SetText("--")
        cells.sells:SetText("--")
        cells.via:SetText("")
        cells.margin:SetText("")
        cells.age:SetText("")

        -- STOCK stays: what you hold needs no price, and it was blanked
        -- here on exactly the rows the Keep in stock limit still applies to.
        cells.profit:SetText(analysis.soulbound and "soulbound"
            or analysis.reason == "output has no price data" and "no price"
            or "no data")
        cells.profit:SetTextColor(Theme.Unpack("dim"))
        return
    end

    -- Measured: "12g 34s 56c" is wider than these columns and ended in
    -- "...". It drops to "12g 35s" instead.
    Theme.SetMoneyText(cells.cost, analysis.totalCost, { short = true })
    cells.cost:SetTextColor(Theme.Unpack("muted"))

    Theme.SetMoneyText(cells.sells, analysis.revenue, { short = true })
    cells.sells:SetTextColor(Theme.Unpack("text"))

    Theme.SetMoneyText(cells.profit, analysis.profit, { short = true })
    cells.profit:SetTextColor(Theme.ProfitColor(analysis.profit))

    cells.via:SetText(ns.Profit.WAY_LABELS and ns.Profit.WAY_LABELS[analysis.via] or "")
    cells.via:SetTextColor(Theme.Unpack(analysis.via == "disenchant" and "accent" or "muted"))

    cells.margin:SetText(("%d%%"):format(math.floor((analysis.margin or 0) * 100)))
    cells.margin:SetTextColor(Theme.ProfitColor(analysis.profit))

    -- Full at 100% and over; a loss draws no bar, its red number says it.
    if (analysis.profit or 0) > 0 then
        row.marginBar:Set(math.min(1, analysis.margin or 0), "profit")
    end

    if analysis.priceDerived then
        -- There is no scan behind this row, so an age would be a blank or a
        -- lie. The column says what the price actually is instead: the
        -- materials-plus-markup estimate, which is a different kind of
        -- number from everything else in the list.
        SetFitted(cells.age, "estimate", "est.")
        cells.age:SetTextColor(Theme.Unpack("warn"))
    elseif analysis.priceBasis == "vendor" then
        -- Valued at what a vendor pays, which no scan's age bears on.
        cells.age:SetText("vendor")
        cells.age:SetTextColor(Theme.Unpack("muted"))
    elseif analysis.priceBasis == "disenchant" then
        -- Valued at what it disenchants to, read off its materials' prices.
        cells.age:SetText("DE")
        cells.age:SetTextColor(Theme.Unpack("muted"))
    elseif analysis.priceBasis == "mine" or analysis.priceBasis == "floor" then
        -- Priced at what the player set on the Prices tab, not a scan.
        SetFitted(cells.age, "my price", "mine")
        cells.age:SetTextColor(Theme.Unpack("warn"))
    else
        local age = Util.FormatAge(analysis.age)
        SetFitted(cells.age, age, age == "just now" and "now" or nil)
        cells.age:SetTextColor(Theme.Unpack(analysis.stale and "warn" or "dim"))
    end
end

--- Why this row is wearing a star.
--
-- The mark is small and new, so it has to be able to explain itself; a symbol
-- nobody can interrogate is a symbol people learn to ignore.
local function ShowMarkTooltip(row, analysis)
    local skillUp = analysis.skillUp
    if not skillUp then return end

    ns.Widgets.ShowItemTooltip(row, "ANCHOR_LEFT", analysis.outputItemID, analysis.name or "craft")
    GameTooltip:AddLine(" ")

    local r, g, b = ns.SkillUp:GetTierColor(skillUp.tier)
    GameTooltip:AddDoubleLine("Skill up", ns.SkillUp:GetTierLabel(skillUp.tier),
        0.7, 0.7, 0.7, r, g, b)

    GameTooltip:AddDoubleLine("Profit each",
        Util.FormatMoney(analysis.profit, { noColor = true }), 0.7, 0.7, 0.7, 1, 1, 1)

    -- Skill only rises, so a reading taken lower down may have gone green
    -- since. Better said than quietly trusted.
    if skillUp.stale then
        GameTooltip:AddLine(("Read at skill %d, you are %d now. Open your profession to refresh."):format(
            skillUp.skill or 0, skillUp.currentSkill or 0), 0.91, 0.76, 0.35, true)
    end

    GameTooltip:AddLine("Starred: it raises your skill and it pays.", 0.5, 0.5, 0.5)
    GameTooltip:Show()
end

--------------------------------------------------------------------------------
-- Detail panel
--------------------------------------------------------------------------------

-- Defined below; the Price graph button redraws the pane with it.
local UpdateDetail

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
    -- Held inside the pane and wrapped there. On one line, "You have 12 and
    -- 4 more queued, your limit" ended in "..."; the materials below move
    -- down to make room.
    subtitle:SetPoint("RIGHT", detail, "RIGHT", -12, 0)
    subtitle:SetWordWrap(true)
    detail.subtitle = subtitle

    local reagentHeading = Theme.CreateHeading(detail, "MATERIALS")
    -- Back out under the icon, so the list of materials starts at the edge.
    reagentHeading:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", -38, -12)
    detail.reagentHeading = reagentHeading

    -- The price graph (Sullivan, 2026-10-06) goes where the materials list
    -- does, for the craft and each material, hour by hour. This swaps the
    -- two; which one shows is remembered.
    if ns.PriceGraph then
        local graphButton = Widgets.CreateButton(detail, "Price graph", function()
            ns.Config:Set("profitShowsGraph", not ns.Config:Get("profitShowsGraph"))
            UpdateDetail(state.selected)
        end, { width = 76, height = 16, fontSize = "tiny" })
        graphButton:SetPoint("TOPRIGHT", detail, "TOPRIGHT", -12, 0)
        graphButton:SetPoint("TOP", reagentHeading, "TOP", 0, 4)
        detail.graphButton = graphButton
        if reagentHeading.rule then
            reagentHeading.rule:ClearAllPoints()
            reagentHeading.rule:SetPoint("LEFT", reagentHeading, "RIGHT", 6, 0)
            reagentHeading.rule:SetPoint("RIGHT", graphButton, "LEFT", -6, 0)
        end

        local graph = ns.PriceGraph.Create(detail, { picker = true, ticks = true })
        graph:SetPoint("TOPLEFT", reagentHeading, "BOTTOMLEFT", 0, -6)
        graph:SetPoint("BOTTOMRIGHT", detail, "BOTTOMRIGHT", -12, 84 + 170 + 6)
        graph:Hide()
        detail.graph = graph
    end

    detail.reagentLines = {}

    -- The last line when the materials do not all fit above the summary. The
    -- whole list is in its tooltip.
    local more = CreateFrame("Frame", nil, detail)
    more:SetHeight(16)
    more:EnableMouse(true)
    more.label = Theme.CreateLabel(more, "small", "muted")
    more.label:SetPoint("LEFT", 18, 0)
    more:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("Materials", 1, 1, 1)
        for _, reagent in ipairs(self.reagents or {}) do
            GameTooltip:AddDoubleLine(
                ("%dx %s"):format(reagent.quantity, Util.GetItemLabel(reagent.itemID)),
                reagent.shortfall > 0 and ("need %d"):format(reagent.shortfall)
                    or Util.FormatMoney(reagent.lineCost, { short = true }),
                1, 1, 1, 1, 1, 1)
        end
        GameTooltip:Show()
    end)
    more:SetScript("OnLeave", function() GameTooltip:Hide() end)
    more:Hide()
    detail.moreLine = more

    -- Summary block, anchored to the bottom so it never collides with a long
    -- reagent list.
    local summary = CreateFrame("Frame", nil, detail)
    summary:SetPoint("BOTTOMLEFT", 12, 84)
    summary:SetPoint("BOTTOMRIGHT", -12, 84)
    -- Ten rows of 17: the sale, then what each way makes.
    summary:SetHeight(170)
    detail.summary = summary
    detail.summaryRows = {}

    local function SummaryRow(index, labelText)
        local label = Theme.CreateLabel(summary, "small", "muted")
        label:SetPoint("TOPLEFT", 0, -(index - 1) * SUMMARY_ROW_HEIGHT)
        label:SetText(labelText)

        local value = Theme.CreateLabel(summary, "small", "text", "RIGHT")
        value:SetPoint("TOPRIGHT", 0, -(index - 1) * SUMMARY_ROW_HEIGHT)

        detail.summaryRows[index] = { label = label, value = value }
        return value, label
    end

    detail.costValue = SummaryRow(1, "Materials")
    detail.rivalValue, detail.rivalLabel = SummaryRow(2, "Cheapest rival")
    detail.ownValue, detail.ownLabel = SummaryRow(3, "Your listing")
    detail.postValue, detail.postLabel = SummaryRow(4, "You post at")
    detail.cutValue = SummaryRow(5, "Auction cut")
    detail.depositValue, detail.depositLabel = SummaryRow(6, "Deposit")
    detail.profitValue = SummaryRow(7, "Profit")
    -- What each way makes, when there is more than one. The one the
    -- profit above is for is lit.
    detail.wayRows = {
        auction = { SummaryRow(8, "If sold at AH") },
        vendor = { SummaryRow(9, "If vendored") },
        disenchant = { SummaryRow(10, "If disenchanted") },
    }

    -- Per-item posted limit. Sits with the queue controls because it is the
    -- thing that decides how many you should be adding.
    local limitLabel = Theme.CreateLabel(detail, "small", "muted")
    limitLabel:SetPoint("BOTTOMLEFT", 12, 46)
    limitLabel:SetText("Keep in stock")
    detail.limitLabel = limitLabel

    detail.limitBox = Widgets.CreateNumberBox(detail, {
        width = 46, min = 0, max = 999,
        onChange = function(value)
            if not state.selected or not state.selected.outputItemID then return end
            -- Zero means "use the account-wide default", which is what
            -- clearing the override does.
            ns.Auctions:SetLimit(state.selected.outputItemID,
                value > 0 and value or nil)
        end,
    })
    detail.limitBox:SetPoint("BOTTOMLEFT", 92, 42)

    detail.limitHint = Theme.CreateLabel(detail, "tiny", "dim")
    detail.limitHint:SetPoint("LEFT", detail.limitBox, "RIGHT", 6, 0)
    -- Out to the pane's edge and onto a second line: "3 listed, 1 in mail,
    -- room for 2" is wider than the 144 there, and ended in "..." just
    -- where the room left was. Two lines, centred on the box, clear both
    -- the buttons below and the summary above; a third would not.
    detail.limitHint:SetPoint("RIGHT", detail, "RIGHT", -12, 0)
    detail.limitHint:SetWordWrap(true)
    if detail.limitHint.SetMaxLines then detail.limitHint:SetMaxLines(2) end

    -- Queue controls
    local quantityBox = Theme.CreatePanel(detail, "row")
    quantityBox:SetSize(46, 24)
    quantityBox:SetPoint("BOTTOMLEFT", 12, 14)

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
        if not state.selected then return end

        -- Whole crafts, one at least: Queue:Add clamps the same way, and the
        -- line printed should say what was queued.
        local count = math.max(1, math.floor(tonumber(quantity:GetText()) or 1))

        -- Max writes 0 when the stock limit leaves no room. Queue:Add would
        -- still make that one craft, which is not what the box says.
        if tonumber(quantity:GetText()) == 0 then
            ns.Print(("nothing queued: the amount for %s is 0"):format(
                state.selected.name or "that craft"))
            return
        end

        local recipeID, name = state.selected.recipeID, state.selected.name
        ns.Queue:Add(recipeID, count)
        ns.Print(("queued %dx %s"):format(count, name or "craft"))
        if ns.Demand then ns.Demand:WarnIfLow(state.selected.outputItemID, name) end

        -- Suggest again from what is now queued, as Max would. Left as it
        -- was, a second click queued the full amount again over the limit.
        -- Set here rather than by the redraw Queue:Add makes, which has
        -- already run by now and keeps the box as it was for the same craft.
        local fresh = ns.Profit:Analyse(recipeID, nil, Method())
        if fresh then
            quantity:SetText(tostring(ns.Profit.MaxCrafts(fresh.craftableNow, fresh.roomInCrafts)))
        end
    end, { width = 100, primary = true, height = 24 })
    addButton:SetPoint("BOTTOMLEFT", quantityBox, "BOTTOMRIGHT", 8, 0)
    detail.addButton = addButton

    local maxButton = Widgets.CreateButton(detail, "Max", function()
        if not state.selected then return end

        -- Whichever runs out first: materials, or room under the limit.
        -- Room is counted in items and this box is counted in crafts, so it
        -- is the converted figure that may be compared against a craft count.
        local most = ns.Profit.MaxCrafts(state.selected.craftableNow,
            state.selected.roomInCrafts)
        if most == 0 then
            ns.Print(("no room for more %s: you already hold your Max on hand (Keep in stock in Settings)")
                :format(state.selected.name or "of that craft"))
        end

        quantity:SetText(tostring(most))
    end, { width = 44, height = 24,
           tooltip = "As many as your materials and stock limit allow" })
    maxButton:SetPoint("BOTTOMLEFT", addButton, "BOTTOMRIGHT", 8, 0)
    detail.maxButton = maxButton

    -- Takes the craft off this list for good, on every character. Settings
    -- lists what is ignored, with a Restore button for each.
    local ignoreButton = Widgets.CreateButton(detail, "Ignore", function()
        local analysis = state.selected
        if not analysis then return end

        -- Cleared first: SetIgnored redraws the tab, and the pane should
        -- not go on showing a craft the list no longer has.
        state.selected = nil
        ns.Profit:SetIgnored(analysis.recipeID, true, analysis.name)
        ns.Print(("ignored %s: it no longer shows on the Profit tab. Restore it under Ignored crafts in Settings.")
            :format(analysis.name or "that craft"))
    end, { width = 60, height = 24,
           tooltip = "Stop recommending this craft. Settings lists ignored crafts, each with a Restore button." })
    ignoreButton:SetPoint("BOTTOMLEFT", maxButton, "BOTTOMRIGHT", 8, 0)
    detail.ignoreButton = ignoreButton

    local empty = Theme.CreateLabel(detail, "small", "dim", "CENTER")
    empty:SetPoint("CENTER")
    empty:SetText("Select a craft to see the breakdown")
    detail.empty = empty

    return detail
end

-- How many material lines fit between the MATERIALS heading and the summary.
-- Six always fit, which is what is assumed when the pane has not been laid
-- out yet; a seventh ran into the summary.
local REAGENT_LINE_HEIGHT = 16
local REAGENT_LINES_FALLBACK = 6

local function ReagentRoom(detail)
    local ok, top, bottom = pcall(function()
        return detail.reagentHeading:GetBottom(), detail.summary:GetTop()
    end)
    if not (ok and type(top) == "number" and type(bottom) == "number") then
        return REAGENT_LINES_FALLBACK
    end

    -- 6 above the first line (its anchor offset) and a little air above the
    -- summary.
    return math.max(2, math.floor((top - bottom - 6 - 4) / REAGENT_LINE_HEIGHT))
end

--- Close the summary up around the rows that are hidden. "Your listing" with
--- nothing listed left a blank line between the prices; now a hidden row's
--- space goes to the top of the block, and the rows shown stay together just
--- above the queue controls, in their order.
local function LayoutSummary(detail)
    local rows = detail.summaryRows
    local shown = {}

    for _, row in ipairs(rows) do
        if row.label:IsShown() then shown[#shown + 1] = row end
    end

    local skipped = #rows - #shown
    for position, row in ipairs(shown) do
        local y = -(skipped + position - 1) * SUMMARY_ROW_HEIGHT
        row.label:SetPoint("TOPLEFT", 0, y)
        row.value:SetPoint("TOPRIGHT", 0, y)
    end
end

--- Show the price graph or the materials list, and fit the graph above the
--- summary rows that are shown.
local function UpdateGraph(detail, analysis)
    -- rawget: a test's stand-in frame answers any field with a function.
    if type(rawget(detail, "graph")) ~= "table" then return false end
    local showGraph = analysis ~= nil and ns.Config:Get("profitShowsGraph") == true

    detail.graphButton:SetShown(analysis ~= nil)
    detail.graphButton:SetText(showGraph and "Materials" or "Price graph")
    detail.graphButton.tooltipText = showGraph
        and "Show the materials list again"
        or "The cheapest price hour by hour, for this craft and its materials, and when in the day each is cheapest and dearest"
    detail.reagentHeading:SetText(showGraph and "PRICE HISTORY" or "MATERIALS")
    detail.graph:SetShown(showGraph)
    if not showGraph then return false end

    -- Hidden summary rows leave their room at the top of the block.
    local skipped = 0
    for _, row in ipairs(detail.summaryRows) do
        if not row.label:IsShown() then skipped = skipped + 1 end
    end
    if not detail.summary:IsShown() then skipped = #detail.summaryRows end

    detail.graph:ClearAllPoints()
    detail.graph:SetPoint("TOPLEFT", detail.reagentHeading, "BOTTOMLEFT", 0, -8)
    detail.graph:SetPoint("BOTTOMRIGHT", detail.summary, "TOPRIGHT", 0,
        6 - skipped * SUMMARY_ROW_HEIGHT)

    -- The craft first, then its materials, dearest line first.
    local items = {}
    if analysis.outputItemID then items[1] = analysis.outputItemID end
    for _, reagent in ipairs((analysis.cost and analysis.cost.reagents) or {}) do
        if reagent.itemID then items[#items + 1] = reagent.itemID end
    end
    detail.graph:SetItems(items, analysis.outputItemID)
    return true
end

function UpdateDetail(analysis)
    local detail = widgets.detail

    local hasSelection = analysis ~= nil
    detail.empty:SetShown(not hasSelection)

    -- A new craft starts the box at a suggestion; the same craft redrawn
    -- (a bag change, an auction update) keeps what was typed there.
    local newCraft = not analysis or detail.shownRecipeID ~= analysis.recipeID
    detail.shownRecipeID = analysis and analysis.recipeID or nil

    for _, line in ipairs(detail.reagentLines) do
        line.frame:Hide()
    end
    detail.moreLine:Hide()

    detail.title:SetShown(hasSelection)
    detail.subtitle:SetShown(hasSelection)
    detail.reagentHeading:SetShown(hasSelection)
    detail.maxButton:SetShown(hasSelection)
    detail.ignoreButton:SetShown(hasSelection)
    detail.icon:SetShown(hasSelection)
    detail.summary:SetShown(hasSelection)
    detail.addButton:SetShown(hasSelection)
    detail.limitLabel:SetShown(hasSelection)
    detail.limitBox:SetShown(hasSelection)
    detail.limitHint:SetShown(hasSelection)
    detail.quantity:GetParent():SetShown(hasSelection)

    if not hasSelection then
        UpdateGraph(detail, nil)
        return
    end

    detail.title:SetText(analysis.name or ("recipe " .. analysis.recipeID))
    Theme.SetItemIcon(detail.icon, analysis.outputItemID)

    -- The skill-up clause is coloured inline rather than by the whole label,
    -- because the line already carries a colour of its own for materials.
    local skillUpText = ""
    local skillUp = analysis.skillUp

    if skillUp and skillUp.tier ~= "trivial" then
        skillUpText = ("  %s%s|r"):format(
            ns.SkillUp:GetTierColorCode(skillUp.tier), ns.SkillUp:GetTierLabel(skillUp.tier))
    end

    if analysis.craftableNow and analysis.craftableNow > 0 then
        detail.subtitle:SetText(("You can make %d now"):format(analysis.craftableNow) .. skillUpText)
        detail.subtitle:SetTextColor(Theme.Unpack("profit"))
    else
        detail.subtitle:SetText("Missing materials" .. skillUpText)
        detail.subtitle:SetTextColor(Theme.Unpack("muted"))
    end

    if not analysis.priceable then
        detail.summary:Hide()
        detail.subtitle:SetText(analysis.reason or "cannot be priced")
        detail.subtitle:SetTextColor(Theme.Unpack("warn"))
    end

    -- Reagent lines. When there are more than fit, the last line that fits
    -- says how many more there are instead.
    local y = -12
    local anchor = detail.reagentHeading

    local reagents = (analysis.cost and analysis.cost.reagents) or {}
    local shownCount = #reagents
    local room = ReagentRoom(detail)
    if shownCount > room then shownCount = room - 1 end

    for index = 1, shownCount do
        local reagent = reagents[index]
        local line = detail.reagentLines[index]

        if not line then
            local frame = CreateFrame("Frame", nil, detail)
            frame:SetHeight(16)

            local icon = Theme.CreateItemIcon(frame, 14)
            icon:SetPoint("LEFT", 0, 0)

            local name = Theme.CreateLabel(frame, "small", "text")
            name:SetPoint("LEFT", 18, 0)
            name:SetPoint("RIGHT", -70, 0)

            local value = Theme.CreateLabel(frame, "small", "muted", "RIGHT")
            value:SetPoint("RIGHT", 0, 0)

            line = { frame = frame, icon = icon, name = name, value = value }
            detail.reagentLines[index] = line
        end

        line.frame:ClearAllPoints()
        line.frame:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, index == 1 and -6 or 0)
        line.frame:SetPoint("TOPRIGHT", detail, "TOPRIGHT", -12, 0)

        local label = Util.GetItemLabel(reagent.itemID)
        Theme.SetItemIcon(line.icon, reagent.itemID)

        -- Showing have/need inline is the whole point: it answers "can I make
        -- this" without a second screen.
        if reagent.shortfall > 0 then
            line.name:SetText(("%dx %s"):format(reagent.quantity, label))
            line.value:SetText(("need %d"):format(reagent.shortfall))
            line.value:SetTextColor(Theme.Unpack("loss"))
        elseif reagent.source == "mine" then
            -- Costed at the player's own price from the Prices tab.
            line.name:SetText(("%dx %s |c%s(my price)|r"):format(reagent.quantity, label, ns.COLORS.warn))
            line.value:SetText(Util.FormatMoney(reagent.lineCost, { short = true }))
            line.value:SetTextColor(Theme.Unpack("warn"))
        else
            line.name:SetText(("%dx %s"):format(reagent.quantity, label))
            line.value:SetText(Util.FormatMoney(reagent.lineCost, { short = true }))
            line.value:SetTextColor(Theme.Unpack("muted"))
        end

        line.frame:Show()
        anchor = line.frame
        y = y - 16
    end

    if shownCount < #reagents then
        local more = detail.moreLine
        more:ClearAllPoints()
        more:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, shownCount == 0 and -6 or 0)
        more:SetPoint("TOPRIGHT", detail, "TOPRIGHT", -12, 0)
        more.label:SetText(("+%d more materials"):format(#reagents - shownCount))
        more.reagents = reagents
        more:Show()
    end

    if analysis.priceable then
        detail.summary:Show()
        detail.costValue:SetText(Util.FormatMoney(analysis.totalCost))

        if analysis.undercut then
            -- An item auction that cannot be undercut by less than a silver is
            -- matched instead, and the label says so rather than implying a
            -- price below the rival's.
            detail.rivalLabel:SetText(analysis.matchedRival
                and "Matching rival" or "Cheapest rival")
            detail.rivalValue:SetText(Util.FormatMoney(analysis.competitorPrice))
            detail.rivalValue:SetTextColor(Theme.Unpack("muted"))
        elseif analysis.priceUncontested then
            -- Nobody is competing, so the price above is the markup over
            -- materials rather than anything the book says. Checked before
            -- "You hold lowest" below, which is the same situation described
            -- less usefully: what matters is where the price came from.
            detail.rivalLabel:SetText("No competition")
            detail.rivalValue:SetText("materials + markup")
            detail.rivalValue:SetTextColor(Theme.Unpack("profit"))
        elseif analysis.youHoldLowest then
            -- Your own auction is the cheapest. Undercutting it would just walk
            -- your own price down, so we hold at market and say so.
            detail.rivalLabel:SetText("You hold lowest")
            detail.rivalValue:SetText("no rival")
            detail.rivalValue:SetTextColor(Theme.Unpack("profit"))
        elseif analysis.priceDerived then
            -- No scan has ever priced this one, so the sale price above is
            -- the material value plus the markup in Settings. Named
            -- differently from "None listed" below, which is an item the
            -- auction house has seen and simply has none of right now.
            detail.rivalLabel:SetText("Never scanned")
            detail.rivalValue:SetText("from materials")
            detail.rivalValue:SetTextColor(Theme.Unpack("warn"))
        elseif analysis.priceBasis == "vendor" then
            -- Nothing listed, and the price below is what a vendor pays:
            -- not an estimate, as "None listed" below would call it.
            detail.rivalLabel:SetText("None listed")
            detail.rivalValue:SetText("no rival")
            detail.rivalValue:SetTextColor(Theme.Unpack("muted"))
        else
            -- Nothing listed means no competition to undercut, so the number
            -- shown is an estimate rather than an observed price.
            detail.rivalLabel:SetText("None listed")
            detail.rivalValue:SetText("estimate")
            detail.rivalValue:SetTextColor(Theme.Unpack("warn"))
        end

        -- Your own listing, shown whenever you have one, so it is obvious
        -- whether the rival price above sits below or above where you already
        -- are. Hidden entirely when you have nothing listed.
        if analysis.ownListing then
            detail.ownLabel:Show()
            detail.ownValue:Show()
            detail.ownValue:SetText(Util.FormatMoney(analysis.ownListing))

            -- Undercut by a rival: your listing is not the one that sells.
            local beaten = analysis.competitorPrice
                and analysis.competitorPrice < analysis.ownListing
            detail.ownValue:SetTextColor(Theme.Unpack(beaten and "loss" or "profit"))
        else
            detail.ownLabel:Hide()
            detail.ownValue:Hide()
        end

        -- Valued at what a vendor pays when that beats the listing, which
        -- then takes no cut and no deposit. Disenchanted, the cut is the
        -- one on selling the materials, and there is no deposit.
        local toVendor = analysis.priceBasis == "vendor"
        local toEnchanter = analysis.priceBasis == "disenchant"

        detail.postLabel:SetText(toVendor and "Vendor pays"
            or toEnchanter and "Disenchants to" or "You post at")
        detail.postValue:SetText(Util.FormatMoney(analysis.unitRevenue))
        detail.postValue:SetTextColor(Theme.Unpack("accent"))

        if toVendor then
            detail.cutValue:SetText("none")
            detail.cutValue:SetTextColor(Theme.Unpack("dim"))
        else
            detail.cutValue:SetText("-" .. Util.FormatMoney(analysis.cut))
            detail.cutValue:SetTextColor(Theme.Unpack("text"))
        end

        -- Only known once the item has been priced at an auction house.
        if toVendor or toEnchanter then
            detail.depositLabel:SetText("Deposit")
            detail.depositValue:SetText("none")
            detail.depositValue:SetTextColor(Theme.Unpack("dim"))
        elseif analysis.depositKnown then
            detail.depositLabel:SetText("Deposit")
            detail.depositValue:SetText("-" .. Util.FormatMoney(analysis.deposit))
            detail.depositValue:SetTextColor(Theme.Unpack("muted"))
        else
            detail.depositLabel:SetText("Deposit")
            detail.depositValue:SetText("unknown")
            detail.depositValue:SetTextColor(Theme.Unpack("dim"))
        end

        detail.profitValue:SetText(Util.FormatMoney(analysis.profit))
        detail.profitValue:SetTextColor(Theme.ProfitColor(analysis.profit))

        -- What each way makes, when there is more than one to compare.
        -- Something that can be disenchanted but whose materials have no
        -- price yet says so on its row.
        local lines = ns.Profit.DescribeWays and ns.Profit:DescribeWays(analysis) or {}
        local byWay = {}
        for _, line in ipairs(lines) do byWay[line.way] = line end

        for way, pair in pairs(detail.wayRows) do
            local value, label = pair[1], pair[2]
            local line = byWay[way]
            local unscanned = way == "disenchant" and analysis.disenchantable == true
                and not analysis.disenchantValue

            label:SetShown(line ~= nil or unscanned)
            value:SetShown(line ~= nil or unscanned)

            if line then
                local text = Util.FormatMoney(line.profit, { short = true })
                if line.note then text = text .. "  " .. line.note end
                value:SetText(text)
                value:SetTextColor(Theme.ProfitColor(line.profit))
                label:SetTextColor(Theme.Unpack(line.chosen and "accent" or "muted"))
            elseif unscanned then
                value:SetText("materials not scanned")
                value:SetTextColor(Theme.Unpack("dim"))
                label:SetTextColor(Theme.Unpack("muted"))
            end
        end

        LayoutSummary(detail)
    end

    -- After the summary, which decides how much room the graph has.
    if UpdateGraph(detail, analysis) then
        for _, line in ipairs(detail.reagentLines) do line.frame:Hide() end
        detail.moreLine:Hide()
    end

    -- Limit control reflects the override if there is one, else the default.
    if analysis.outputItemID then
        detail.limitLabel:Show()
        detail.limitBox:Show()
        detail.limitHint:Show()

        -- Not over a number being typed: a bag update mid-typing put the
        -- old limit back and the next key landed after it (1, then 5 from
        -- the redraw, then 2, saved as 52). A different craft does replace
        -- it, and drops the half-typed number with it.
        local box = detail.limitBox
        local typing = box.editBox.HasFocus and box.editBox:HasFocus()
        if not typing then
            box:SetValue(analysis.postLimit or 0, true)
        elseif newCraft then
            box:SetValue(analysis.postLimit or 0, true)
            box.editBox:ClearFocus()
        end

        -- Spell out where the stock is, so a hidden craft is explicable.
        local parts = {}
        if (analysis.posted or 0) > 0 then
            parts[#parts + 1] = ("%d listed"):format(analysis.posted)
        end
        if (analysis.onHand or 0) > 0 then
            parts[#parts + 1] = ("%d held"):format(analysis.onHand)
        end
        -- Named separately from "held": an item in the mailbox is one that came
        -- back from a listing that did not sell, which is worth knowing.
        if (analysis.inMail or 0) > 0 then
            parts[#parts + 1] = ("%d in mail"):format(analysis.inMail)
        end
        if (analysis.queuedElsewhere or 0) > 0 then
            parts[#parts + 1] = ("%d queued"):format(analysis.queuedElsewhere)
        end

        local where = #parts > 0 and table.concat(parts, ", ") or "none yet"

        if analysis.postLimit and analysis.postLimit > 0 then
            detail.limitHint:SetText(("%s, room for %d"):format(where, analysis.postRoom or 0))
            detail.limitHint:SetTextColor(Theme.Unpack(
                analysis.atPostLimit and "warn" or "dim"))
        elseif (analysis.stockDivisor or 1) > 1 then
            -- Say out loud that the list order is not pure profit. A craft
            -- sitting lower than its profit suggests, with no explanation, is
            -- exactly the sort of thing that reads as a bug.
            detail.limitHint:SetText(("%s, so ranked as %s"):format(
                where, Util.FormatMoney(
                    (analysis.profit or 0) > 0
                        and (analysis.profit / analysis.stockDivisor)
                        or analysis.profit)))
            detail.limitHint:SetTextColor(Theme.Unpack("dim"))
        elseif #parts > 0 then
            detail.limitHint:SetText(where)
            detail.limitHint:SetTextColor(Theme.Unpack("dim"))
        else
            detail.limitHint:SetText("none on hand")
            detail.limitHint:SetTextColor(Theme.Unpack("dim"))
        end
    else
        detail.limitLabel:Hide()
        detail.limitBox:Hide()
        detail.limitHint:Hide()
    end

    -- Crafts, not items, and what Max would write: 0 once the limit is
    -- reached. Floored at 1, the box said 1 at "room for 0" and Add queued
    -- one past the limit.
    local suggested = ns.Profit.MaxCrafts(analysis.craftableNow, analysis.roomInCrafts)
    if newCraft then detail.quantity:SetText(tostring(suggested)) end

    if analysis.atPostLimit then
        -- Queued crafts count toward the limit too, and "You already have 0,
        -- your limit" read as nonsense when they were all that filled it.
        local queued = analysis.queuedElsewhere or 0
        if queued > 0 then
            detail.subtitle:SetText(("You have %d and %d more queued, your limit"):format(
                analysis.stock or 0, queued))
        else
            detail.subtitle:SetText(("You already have %d, your limit"):format(
                analysis.stock or 0))
        end
        detail.subtitle:SetTextColor(Theme.Unpack("warn"))
    end
end

--------------------------------------------------------------------------------
-- Filtering
--------------------------------------------------------------------------------

--- Mirror the row layout onto the column headings.
ApplyHeadingLayout = function()
    if not widgets.headings then return end

    local offset = -8
    for _, column in ipairs(COLUMNS) do
        local heading = widgets.headings[column.key]

        if IsColumnVisible(column) then
            heading:SetPoint("RIGHT", offset, 0)
            heading:SetWidth(column.width)
            heading:Show()
            offset = offset - column.width - 6
        else
            heading:Hide()
        end
    end

    if widgets.sorter then widgets.sorter:Sync() end
end

--- What the list's order was worked out for. While it stays the same, rows
--- keep their places: queueing a craft counts it as stock you will have and
--- ranks it lower, so a right-click to queue dropped the row from under the
--- cursor and the next click queued a different craft. The order is worked
--- out afresh when a filter, the sort or the search changes, or when the tab
--- is opened again.
local function OrderKey()
    return table.concat({ tostring(state.accountWide), tostring(state.ignorePostLimit),
        tostring(state.sortBy), tostring(state.craftableOnly),
        tostring(state.includeUnpriceable), tostring(state.profession),
        tostring(Method()), state.search or "" }, "|")
end

local function BuildList()
    local key = OrderKey()
    if key ~= state.orderKey then
        state.orderKey, state.heldOrder = key, nil
    end

    local ranked = ns.Profit:GetRanked({
        accountWide = state.accountWide,
        ignorePostLimit = state.ignorePostLimit,
        sortBy = state.sortBy,
        craftableOnly = state.craftableOnly,
        includeUnpriceable = state.includeUnpriceable,
        skillLineID = state.profession,
        method = Method(),
        keepOrder = state.heldOrder,
    })

    if state.search ~= "" then
        local needle = state.search:lower()
        local filtered = {}

        for _, analysis in ipairs(ranked) do
            if (analysis.name or ""):lower():find(needle, 1, true) then
                filtered[#filtered + 1] = analysis
            end
        end
        ranked = filtered
    end

    state.heldOrder = {}
    for index, analysis in ipairs(ranked) do
        state.heldOrder[analysis.recipeID] = index
    end

    return ranked
end

local function Refresh()
    if not widgets.list then return end

    local data = BuildList()

    -- A clicked heading's order over the ranking's.
    if widgets.sorter then data = widgets.sorter:Sort(data) end

    -- The DISENCHANT column earns its space only when something listed can
    -- be disenchanted: an alchemist's list would otherwise carry an empty one.
    local anyDisenchantable = false
    for _, analysis in ipairs(data) do
        if analysis.disenchantable then
            anyDisenchantable = true
            break
        end
    end

    if anyDisenchantable ~= state.showDisenchant then
        state.showDisenchant = anyDisenchantable
        layoutVersion = layoutVersion + 1
        ApplyHeadingLayout()
    end

    -- Rows set this again while they draw if an item is still uncached.
    awaitingItemData = false
    widgets.list:SetData(data)

    widgets.emptyLabel:SetShown(#data == 0)
    widgets.emptyScan:Hide()

    if #data == 0 then
        if ns.Recipes:Count() == 0 then
            widgets.emptyLabel:SetText("Open a profession window once so your recipes can be read.")
        elseif ns.Prices:Count() == 0 then
            widgets.emptyLabel:SetText("No auction data yet.")
            widgets.emptyScan:Show()
        else
            -- "Nothing matches these filters" is true and useless. A threshold
            -- set once and forgotten now survives logout, so the message says
            -- which one is doing the hiding and what it would take to see them.
            local hidden = ns.Profit:GetRanked({
                accountWide = state.accountWide,
                ignorePostLimit = state.ignorePostLimit,
                craftableOnly = state.craftableOnly,
                includeUnpriceable = state.includeUnpriceable,
                skillLineID = state.profession,
                method = Method(),
                minProfit = 0,
                minMargin = 0,
            })

            local minProfit = ns.Config:Get("minProfit") or 0
            local minMargin = ns.Config:Get("minMarginPercent") or 0

            -- A search that matches nothing says so first: the minimums
            -- message would be about crafts the search never named.
            if state.search ~= "" then
                widgets.emptyLabel:SetText(("Nothing matching \"%s\"."):format(state.search))
            elseif #hidden > 0 and (minProfit > 0 or minMargin > 0) then
                local best = hidden[1]

                widgets.emptyLabel:SetText((
                    "%d craft%s hidden by your minimums in Settings (%s profit, %d%% margin).\nThe best right now makes %s."):format(
                    #hidden, #hidden == 1 and "" or "s",
                    Util.FormatMoney(minProfit, { noColor = true, short = true }),
                    minMargin,
                    Util.FormatMoney(best.profit or 0, { noColor = true, short = true })))

            else
                widgets.emptyLabel:SetText("Nothing matches these filters.")
            end
        end
    end

    -- Keep the detail panel in step with the refreshed numbers.
    if state.selected then
        -- Written back, so Max reads what can be made now and not what could
        -- be made when the row was clicked.
        local fresh = ns.Profit:Analyse(state.selected.recipeID, nil, Method())
        if fresh then state.selected = fresh end
        UpdateDetail(fresh)
    else
        UpdateDetail(nil)
    end

    local ignored = ns.Profit.GetIgnored and #ns.Profit:GetIgnored() or 0
    widgets.countLabel:SetText(("%d craft%s"):format(#data, #data == 1 and "" or "s")
        .. (ignored > 0 and (", %d ignored"):format(ignored) or ""))
    FitHint()
end

--------------------------------------------------------------------------------
-- Build
--------------------------------------------------------------------------------

--- Fill the profession dropdown from the skill lines the listed recipes carry.
--
-- Built from the recipes themselves, not from the profession list. Forever
-- reports each profession under two skill-line IDs (Leatherworking is both
-- 2945 and 165) and a recipe may be tagged with either, so matching the two
-- lists against each other drops entries.
--
-- With "All characters" ticked the list shows every character's recipes, so
-- the choices come from all of them too; otherwise an alt's profession could
-- not be picked at all.
local function RefreshProfessionOptions()
    local dropdown = widgets.professionDropdown
    if not dropdown then return end

    local recipes = state.accountWide and ns.Recipes:GetAccountWide(true) or ns.Recipes:GetAll()

    -- Names the characters' own profession reads saved, for a skill line the
    -- client will not name for this character.
    local savedNames = {}
    for _, record in pairs(ns.db and ns.db.characters or {}) do
        if type(record) == "table" and type(record.professions) == "table" then
            for _, profession in ipairs(record.professions) do
                if type(profession) == "table" and profession.skillLineID and profession.name then
                    savedNames[profession.skillLineID] = profession.name
                end
            end
        end
    end

    local options = { { text = "All professions", value = nil } }

    local seen = {}
    for _, recipe in pairs(recipes) do
        local skillLineID = recipe.skillLineID

        -- A dropped profession has no crafts left to list. The account-wide
        -- list has already left out each character's own dropped ones.
        if not state.accountWide and ns.Recipes:IsDropped(recipe) then skillLineID = nil end

        if skillLineID and not seen[skillLineID] then
            seen[skillLineID] = true

            local name
            if ns.Util.HasFunction("C_TradeSkillUI.GetProfessionInfoBySkillLineID") then
                local ok, info = pcall(C_TradeSkillUI.GetProfessionInfoBySkillLineID, skillLineID)
                if ok and info and info.professionName ~= "" then name = info.professionName end
            end

            options[#options + 1] = {
                text = name or savedNames[skillLineID] or ("Skill line " .. skillLineID),
                value = skillLineID,
            }
        end
    end

    table.sort(options, function(a, b)
        if a.value == nil then return true end
        if b.value == nil then return false end
        return a.text < b.text
    end)

    dropdown:SetOptions(options)

    -- Unticking can take away the profession that was picked. The dropdown
    -- falls back to "All professions" on its own, and the filter has to
    -- follow it or the list would stay filtered to a choice no longer shown.
    state.profession = dropdown:GetValue()

    -- And named on its face. The dropdown writes that only when the choice
    -- changes, and "All professions" is already the choice when the tab
    -- first opens, so the face stayed blank until something was picked.
    dropdown:SetValue(state.profession)
end

local function BuildCrafts(container)
    -- Before any row or heading is laid out: they read these widths.
    if Widgets.FitColumns then Widgets.FitColumns(COLUMNS) end

    -- Toolbar
    local toolbar = CreateFrame("Frame", nil, container)
    toolbar:SetPoint("TOPLEFT", 8, -8)
    toolbar:SetPoint("TOPRIGHT", -8, -8)
    toolbar:SetHeight(24)

    -- Every tab's option bar runs dropdowns, then search, then tick boxes
    -- (Ezmode's request, 2026-10-06). The headings do the sorting.
    local profession = Widgets.CreateDropdown(toolbar, { { text = "All professions", value = nil } },
        function(value)
            state.profession = value
            Refresh()
        end, { width = 150 })
    profession:SetPoint("LEFT", 0, 0)
    widgets.professionDropdown = profession

    -- What the profit is for (Sullivan, 2026-10-06): whichever way pays
    -- most, or one way alone. Kept in Settings, so /bts top and /bts why
    -- rank the same way.
    local labels = ns.Profit.WAY_LABELS or {}
    local methodOptions = { { text = "Profit: Best", value = "best" } }
    for _, method in ipairs(ns.Profit.METHODS or {}) do
        if labels[method] then
            methodOptions[#methodOptions + 1] = { text = "Profit: " .. labels[method], value = method }
        end
    end

    local method = Widgets.CreateDropdown(toolbar, methodOptions, function(value)
        ns.Config:Set("profitBy", value)

        -- VIA shows only when ranked by whichever pays most.
        layoutVersion = layoutVersion + 1
        ApplyHeadingLayout()

        Refresh()
    end, { width = 140 })
    method:SetPoint("LEFT", profession, "RIGHT", 8, 0)
    method:SetValue(Method() or "best")
    widgets.methodDropdown = method

    local search = Widgets.CreateSearchBox(toolbar, "Search crafts", function(text)
        state.search = text or ""
        Refresh()
    end)
    search:SetPoint("LEFT", method, "RIGHT", 8, 0)
    search:SetWidth(Widgets.SEARCH_WIDTH)

    local craftable = Widgets.CreateCheckbox(toolbar, "Craftable now", function(checked)
        state.craftableOnly = checked
        Refresh()
    end, false)
    craftable:SetPoint("LEFT", search, "RIGHT", 12, 0)

    local unpriceable = Widgets.CreateCheckbox(toolbar, "Show unpriced", function(checked)
        state.includeUnpriceable = checked
        Refresh()
    end, false)
    unpriceable:SetPoint("LEFT", craftable, "RIGHT", 12, 0)

    local accountWide = Widgets.CreateCheckbox(toolbar, "All characters", function(checked)
        state.accountWide = checked
        RefreshProfessionOptions()

        -- The WHO column appears or disappears with this.
        layoutVersion = layoutVersion + 1
        ApplyHeadingLayout()

        Refresh()
    end, false)
    accountWide:SetPoint("LEFT", unpriceable, "RIGHT", 12, 0)

    local showMaxed = Widgets.CreateCheckbox(toolbar, "Show maxed", function(checked)
        state.ignorePostLimit = checked
        Refresh()
    end, false)
    showMaxed:SetPoint("LEFT", accountWide, "RIGHT", 12, 0)

    -- Column headings
    local headings = CreateFrame("Frame", nil, container)
    headings:SetPoint("TOPLEFT", toolbar, "BOTTOMLEFT", 0, -8)
    headings:SetPoint("TOPRIGHT", toolbar, "BOTTOMRIGHT", -DETAIL_WIDTH - 8, -8)
    headings:SetHeight(16)

    local nameHeading = Theme.CreateLabel(headings, "tiny", "muted")
    nameHeading:SetPoint("LEFT", 8 + MARK_GUTTER + ICON_GUTTER, 0)
    nameHeading:SetText("CRAFT")

    widgets.headings = {}
    for _, column in ipairs(COLUMNS) do
        local heading = Theme.CreateLabel(headings, "tiny", "muted", column.justify or "RIGHT")
        heading:SetText(column.label)
        widgets.headings[column.key] = heading
    end

    -- Click a heading to sort by it.
    local sortLabels = { name = nameHeading }
    for key, heading in pairs(widgets.headings) do sortLabels[key] = heading end
    widgets.sorter = Widgets.SortableHeadings and Widgets.SortableHeadings(sortLabels, {
        name = function(a) return a.name end,
        cost = function(a) return a.costPerUnit end,
        sells = function(a) return a.unitRevenue end,
        profit = function(a) return a.profit end,
        margin = function(a) return a.margin end,
        age = function(a) return a.age end,
        posted = function(a) return a.stock end,
        make = function(a) return a.craftableNow end,
        who = function(a) return a.ownerName end,
        disenchant = function(a) return a.disenchantValue end,
        via = function(a) return a.via end,
        demand = function(a)
            return ns.Demand and ns.Demand:Rank(ns.Demand:Get(a.outputItemID)) or 0
        end,
    }, function() Refresh() end)
    if widgets.sorter then widgets.sorter:SetText({ "name", "who", "via" }) end

    ApplyHeadingLayout()

    local divider = Theme.CreateDivider(container, "borderLit")
    divider:SetPoint("TOPLEFT", headings, "BOTTOMLEFT", 0, -2)
    divider:SetPoint("TOPRIGHT", headings, "BOTTOMRIGHT", 0, -2)

    -- List
    local list = Widgets.CreateScrollList(container, {
        -- The headings move in with the rows when the scrollbar takes its room.
        onScrollbarShown = function(shown)
            headings:SetPoint("TOPRIGHT", toolbar, "BOTTOMRIGHT", -DETAIL_WIDTH - 8 - (shown and 10 or 0), -8)
        end,
        rowHeight = ROW_HEIGHT,
        createRow = CreateRow,
        updateRow = UpdateRow,

        -- Every row shows the item it makes, as the bags would. A starred
        -- row adds why it wears the star underneath.
        onEnter = function(row, analysis)
            if analysis.recommended and analysis.skillUp then
                ShowMarkTooltip(row, analysis)
            else
                Widgets.ShowItemOnly(row, analysis.outputItemID, analysis.name)
            end
            if not AddWaysLines(analysis) then AddDisenchantLine(analysis) end
            AddOwnerLine(analysis)
        end,

        onLeave = function() GameTooltip:Hide() end,

        -- The row the detail pane is showing stays lit.
        isSelected = function(entry)
            return state.selected ~= nil and entry.recipeID == state.selected.recipeID
        end,

        onClick = function(analysis, _, mouseButton)
            if mouseButton == "RightButton" then
                -- Right-click is the fast path: queue one without leaving the list.
                ns.Queue:Add(analysis.recipeID, 1)
                ns.Print(("queued 1x %s"):format(analysis.name or "craft"))
                if ns.Demand then ns.Demand:WarnIfLow(analysis.outputItemID, analysis.name) end
                return
            end

            state.selected = analysis
            UpdateDetail(ns.Profit:Analyse(analysis.recipeID, nil, Method()))
        end,
    })

    list:SetPoint("TOPLEFT", divider, "BOTTOMLEFT", 0, -4)
    list:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", -DETAIL_WIDTH - 16, 24)
    widgets.list = list

    local emptyLabel = Theme.CreateLabel(container, "small", "dim", "CENTER")
    emptyLabel:SetPoint("CENTER", list, "CENTER", 0, 10)
    emptyLabel:SetWidth(320)
    emptyLabel:SetWordWrap(true)
    widgets.emptyLabel = emptyLabel

    -- When there is simply no data, the fix is one click away; put it here
    -- rather than making the player go hunting for the header.
    local emptyScan = Widgets.CreateButton(container, "Scan auctions", function()
        UI:TriggerScan()
    end, { width = 130, height = 26, primary = true })
    emptyScan:SetPoint("TOP", emptyLabel, "BOTTOM", 0, -12)
    emptyScan:Hide()
    widgets.emptyScan = emptyScan

    local countLabel = Theme.CreateLabel(container, "tiny", "dim")
    countLabel:SetPoint("BOTTOMLEFT", 8, 8)
    widgets.countLabel = countLabel

    -- Queues every row on screen, so the filters and search above decide
    -- what it covers. Each craft goes up to its Max on hand, less what is
    -- already held, listed, in the mail or queued.
    local queueAll = Widgets.CreateButton(container, "Queue All", function()
        local rows = BuildList()
        local crafts, items, noLimit = ns.Queue:AddUpToLimit(rows)

        if crafts > 0 then
            ns.Print(("queued %d craft%s (%d item%s) from %d listed"):format(
                crafts, crafts == 1 and "" or "s",
                items, items == 1 and "" or "s", #rows))
        elseif #rows == 0 then
            ns.Print("nothing listed to queue")
        elseif noLimit == #rows then
            ns.Print("nothing queued: set Keep in stock per item in Settings first")
        else
            ns.Print("nothing queued: every listed craft is already at its Max on hand")
        end
    end, { width = 90, height = 20,
           tooltip = "Queue every craft in this list up to your Max on hand (Keep in stock per item in Settings), less what you already have or have queued" })
    queueAll:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", -DETAIL_WIDTH - 16, 2)
    widgets.queueAll = queueAll

    local hint = Theme.CreateLabel(container, "tiny", "dim", "RIGHT")
    hint:SetPoint("RIGHT", queueAll, "LEFT", -10, 0)
    hint:SetText(HINT_TEXTS[1])
    widgets.hint = hint

    -- Detail panel
    local detail = BuildDetail(container)
    detail:SetPoint("TOPRIGHT", container, "TOPRIGHT", -8, -40)
    detail:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", -8, 8)
    widgets.detail = detail

    UpdateDetail(nil)

    -- A rarity colour needs the client to have the item, and it may not when
    -- the list is first drawn. Redraw once the missing ones arrive, coalescing
    -- a burst of arrivals into a single pass and doing nothing at all unless a
    -- visible row is actually waiting.
    local redrawQueued = false

    ns.RegisterEvent(UI, "GET_ITEM_INFO_RECEIVED", function()
        if redrawQueued or not awaitingItemData then return end
        if not widgets.list:IsVisible() then return end

        redrawQueued = true
        C_Timer.After(0.2, function()
            redrawQueued = false
            Refresh()
        end)
    end)
end

--------------------------------------------------------------------------------
-- Views: your crafts, and recipes to learn
--------------------------------------------------------------------------------

-- Recipes to learn (UI/RecipeBookView.lua) was asked for 2026-10-05: every
-- recipe of a profession you have not learned, and whether it is worth
-- getting. It is the same question as this tab's, asked before the recipe
-- is bought, so it lives here behind a switch like the Characters tab's.
-- Without that file (the tests load this one alone) the tab is the crafts.
local switch = ns.RecipeBookView and ns.RecipeBookView.WithSwitch({
    mainKey = "crafts",
    mainText = "MY CRAFTS",
    mainTip = "The crafts you know, by profit",
    buildMain = BuildCrafts,
    refreshMain = Refresh,
})

local Build = switch and switch.Build or BuildCrafts
local RefreshView = switch and switch.Refresh or Refresh
local ShowView = switch and switch.ShowView or function() end

local function OnShow()
    -- Opening the tab again sorts afresh.
    state.orderKey, state.heldOrder = nil, nil

    RefreshProfessionOptions()
end

--- /bts recipes and the Settings button: the window, on this tab, on
--- Recipes to learn, optionally on one profession.
ns.ProfitTab = {
    ShowView = ShowView,
    ShowRecipesToLearn = function(profession)
        if not (ns.UI and ns.UI.Show) then
            ns.Print("the window is not ready yet, try again in a moment")
            return
        end
        if profession and ns.RecipeBookView then ns.RecipeBookView.SetProfession(profession) end
        ns.UI:Show()
        if ns.UI.SelectTab then ns.UI:SelectTab("profit") end
        ShowView("learn")
    end,
}

UI:RegisterTab({
    key = "profit",
    text = "Profit",
    order = 1,
    build = Build,
    refresh = RefreshView,
    onShow = OnShow,
})
