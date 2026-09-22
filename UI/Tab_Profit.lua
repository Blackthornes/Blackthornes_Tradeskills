-- Blackthornes Tradeskills -- UI/Tab_Profit.lua
-- The headline table: what is worth making, and why.

local _, ns = ...

local Theme = ns.Theme
local Widgets = ns.Widgets
local Util = ns.Util

local UI = ns.UI

local ROW_HEIGHT = 22
local DETAIL_WIDTH = 300

-- Room at the left of every row for the skill-up star. Always reserved, shown
-- or not, so the craft names stay in one straight line down the list -- names
-- that shuffle sideways as the marks come and go are worse than the gap.
local MARK_GUTTER = 16

-- Right-aligned numeric columns, measured from the right edge of the list.
-- Laid out right to left. WHO only earns its space when more than one
-- character is in play, so it is hidden otherwise and the craft name takes
-- the room back.
local COLUMNS = {
    { key = "age",    width = 40 },
    { key = "posted", width = 44 },
    { key = "make",   width = 40 },
    { key = "who",    width = 58, accountWideOnly = true },
    { key = "margin", width = 46 },
    { key = "profit", width = 74 },
    { key = "sells",  width = 70 },
    { key = "cost",   width = 70 },
}

-- Bumped whenever the visible column set changes, so recycled rows know to
-- re-anchor rather than keeping a stale layout.
local layoutVersion = 1

-- Forward declaration: defined below, used by the toolbar built after it.
local ApplyHeadingLayout

local state = {
    search = "",
    accountWide = false,
    ignorePostLimit = false,
    profession = nil,
    craftableOnly = false,
    includeUnpriceable = false,
    sortBy = "profit",
    selected = nil,
}

local widgets = {}

--------------------------------------------------------------------------------
-- Rows
--------------------------------------------------------------------------------

local function IsColumnVisible(column)
    if column.accountWideOnly then return state.accountWide end
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
    row.layoutVersion = layoutVersion
end

local function CreateRow(row)
    row.mark = Theme.CreateMark(row)
    row.mark:SetPoint("LEFT", 7, 0)

    row.name = Theme.CreateLabel(row, "small", "text")
    row.name:SetPoint("LEFT", 8 + MARK_GUTTER, 0)

    row.cells = {}
    for _, column in ipairs(COLUMNS) do
        row.cells[column.key] = Theme.CreateLabel(row, "small", "text", "RIGHT")
    end

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

local function UpdateRow(row, analysis)
    -- Rows are recycled, so one built under a different column set has to
    -- be re-anchored before it is filled.
    if row.layoutVersion ~= layoutVersion then
        ApplyRowLayout(row)
    end

    row.name:SetText(analysis.name or ("recipe " .. analysis.recipeID))

    local cells = row.cells

    -- All three hold whatever the row's price data looks like, so they are
    -- filled before the unpriceable case takes its early exit.
    ApplyNameColor(row, analysis)
    UpdateMakeCell(cells, analysis)

    -- The star: this craft raises your skill AND turns a profit. Set from
    -- analysis.recommended rather than from the tier alone, so an orange
    -- recipe that loses gold is not recommended by the back door.
    Theme.SetMark(row.mark, analysis.recommended
        and analysis.skillUp and analysis.skillUp.tier or nil)

    -- Only meaningful when several characters are in play.
    if state.accountWide then
        cells.who:SetText(analysis.ownerName or "")
        cells.who:SetTextColor(Theme.Unpack(analysis.isMine and "accent" or "muted"))
    else
        cells.who:SetText("")
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
        cells.margin:SetText("")
        cells.age:SetText("")

        cells.posted:SetText("")
        cells.profit:SetText(analysis.reason == "output has no price data"
            and "no sales" or "no data")
        cells.profit:SetTextColor(Theme.Unpack("dim"))
        return
    end

    cells.cost:SetText(Util.FormatMoney(analysis.totalCost, { short = true }))
    cells.cost:SetTextColor(Theme.Unpack("muted"))

    cells.sells:SetText(Util.FormatMoney(analysis.revenue, { short = true }))
    cells.sells:SetTextColor(Theme.Unpack("text"))

    cells.profit:SetText(Util.FormatMoney(analysis.profit, { short = true }))
    cells.profit:SetTextColor(Theme.ProfitColor(analysis.profit))

    cells.margin:SetText(("%d%%"):format(math.floor((analysis.margin or 0) * 100)))
    cells.margin:SetTextColor(Theme.ProfitColor(analysis.profit))

    if analysis.priceDerived then
        -- There is no scan behind this row, so an age would be a blank or a
        -- lie. The column says what the price actually is instead: the
        -- materials-plus-markup estimate, which is a different kind of
        -- number from everything else in the list.
        cells.age:SetText("estimate")
        cells.age:SetTextColor(Theme.Unpack("warn"))
    else
        cells.age:SetText(Util.FormatAge(analysis.age))
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

    GameTooltip:SetOwner(row, "ANCHOR_LEFT")
    GameTooltip:SetText(analysis.name or "craft", 1, 1, 1)

    local r, g, b = ns.SkillUp:GetTierColor(skillUp.tier)
    GameTooltip:AddDoubleLine("Skill up", ns.SkillUp:GetTierLabel(skillUp.tier),
        0.7, 0.7, 0.7, r, g, b)

    GameTooltip:AddDoubleLine("Profit each",
        Util.FormatMoney(analysis.profit, { noColor = true }), 0.7, 0.7, 0.7, 1, 1, 1)

    -- Skill only rises, so a reading taken lower down may have gone green
    -- since. Better said than quietly trusted.
    if skillUp.stale then
        GameTooltip:AddLine(("Read at skill %d, you are %d now -- open your profession to refresh."):format(
            skillUp.skill or 0, skillUp.currentSkill or 0), 0.91, 0.76, 0.35, true)
    end

    GameTooltip:AddLine("Starred: it raises your skill and it pays.", 0.5, 0.5, 0.5)
    GameTooltip:Show()
end

--------------------------------------------------------------------------------
-- Detail panel
--------------------------------------------------------------------------------

local function BuildDetail(parent)
    local detail = Theme.CreatePanel(parent, "window")
    detail:SetWidth(DETAIL_WIDTH)

    local title = Theme.CreateLabel(detail, "large", "accent")
    title:SetPoint("TOPLEFT", 12, -12)
    title:SetPoint("TOPRIGHT", -12, -12)
    title:SetWordWrap(true)
    detail.title = title

    local subtitle = Theme.CreateLabel(detail, "small", "muted")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    detail.subtitle = subtitle

    local reagentHeading = Theme.CreateLabel(detail, "tiny", "dim")
    reagentHeading:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", 0, -12)
    reagentHeading:SetText("MATERIALS")
    detail.reagentHeading = reagentHeading

    detail.reagentLines = {}

    -- Summary block, anchored to the bottom so it never collides with a long
    -- reagent list.
    local summary = CreateFrame("Frame", nil, detail)
    summary:SetPoint("BOTTOMLEFT", 12, 84)
    summary:SetPoint("BOTTOMRIGHT", -12, 84)
    summary:SetHeight(124)
    detail.summary = summary

    local function SummaryRow(index, labelText)
        local label = Theme.CreateLabel(summary, "small", "muted")
        label:SetPoint("TOPLEFT", 0, -(index - 1) * 17)
        label:SetText(labelText)

        local value = Theme.CreateLabel(summary, "small", "text", "RIGHT")
        value:SetPoint("TOPRIGHT", 0, -(index - 1) * 17)

        return value, label
    end

    detail.costValue = SummaryRow(1, "Materials")
    detail.rivalValue, detail.rivalLabel = SummaryRow(2, "Cheapest rival")
    detail.ownValue, detail.ownLabel = SummaryRow(3, "Your listing")
    detail.postValue, detail.postLabel = SummaryRow(4, "You post at")
    detail.cutValue = SummaryRow(5, "Auction cut")
    detail.depositValue, detail.depositLabel = SummaryRow(6, "Deposit")
    detail.profitValue = SummaryRow(7, "Profit")

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
    detail.limitHint:SetWidth(150)

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

        local count = tonumber(quantity:GetText()) or 1
        ns.Queue:Add(state.selected.recipeID, count)
        ns.Print(("queued %dx %s"):format(count, state.selected.name or "craft"))
    end, { width = 130, primary = true, height = 24 })
    addButton:SetPoint("BOTTOMLEFT", quantityBox, "BOTTOMRIGHT", 8, 0)
    detail.addButton = addButton

    local maxButton = Widgets.CreateButton(detail, "Max", function()
        if not state.selected then return end

        -- Whichever runs out first: materials, or room under the limit.
        -- Room is counted in items and this box is counted in crafts, so it
        -- is the converted figure that may be compared against a craft count.
        local most = math.max(1, state.selected.craftableNow or 1)
        local room = state.selected.roomInCrafts
        if room then
            most = math.max(1, math.min(most, room))
        end

        quantity:SetText(tostring(most))
    end, { width = 44, height = 24,
           tooltip = "As many as your materials and posted limit allow" })
    maxButton:SetPoint("BOTTOMLEFT", addButton, "BOTTOMRIGHT", 8, 0)

    local empty = Theme.CreateLabel(detail, "small", "dim", "CENTER")
    empty:SetPoint("CENTER")
    empty:SetText("Select a craft to see the breakdown")
    detail.empty = empty

    return detail
end

local function UpdateDetail(analysis)
    local detail = widgets.detail

    local hasSelection = analysis ~= nil
    detail.empty:SetShown(not hasSelection)

    for _, line in ipairs(detail.reagentLines) do
        line.frame:Hide()
    end

    detail.title:SetShown(hasSelection)
    detail.subtitle:SetShown(hasSelection)
    detail.reagentHeading:SetShown(hasSelection)
    detail.summary:SetShown(hasSelection)
    detail.addButton:SetShown(hasSelection)
    detail.limitLabel:SetShown(hasSelection)
    detail.limitBox:SetShown(hasSelection)
    detail.limitHint:SetShown(hasSelection)
    detail.quantity:GetParent():SetShown(hasSelection)

    if not hasSelection then return end

    detail.title:SetText(analysis.name or ("recipe " .. analysis.recipeID))

    -- The skill-up clause is coloured inline rather than by the whole label,
    -- because the line already carries a colour of its own for materials.
    local skillUpText = ""
    local skillUp = analysis.skillUp

    if skillUp and skillUp.tier ~= "trivial" then
        local r, g, b = ns.SkillUp:GetTierColor(skillUp.tier)
        skillUpText = ("  |cff%02x%02x%02x%s|r"):format(
            r * 255, g * 255, b * 255, ns.SkillUp:GetTierLabel(skillUp.tier))
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

    -- Reagent lines
    local y = -12
    local anchor = detail.reagentHeading

    for index, reagent in ipairs((analysis.cost and analysis.cost.reagents) or {}) do
        local line = detail.reagentLines[index]

        if not line then
            local frame = CreateFrame("Frame", nil, detail)
            frame:SetHeight(16)

            local name = Theme.CreateLabel(frame, "small", "text")
            name:SetPoint("LEFT", 0, 0)
            name:SetPoint("RIGHT", -70, 0)

            local value = Theme.CreateLabel(frame, "small", "muted", "RIGHT")
            value:SetPoint("RIGHT", 0, 0)

            line = { frame = frame, name = name, value = value }
            detail.reagentLines[index] = line
        end

        line.frame:ClearAllPoints()
        line.frame:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, index == 1 and -6 or 0)
        line.frame:SetPoint("TOPRIGHT", detail, "TOPRIGHT", -12, 0)

        local label = Util.GetItemLabel(reagent.itemID)

        -- Showing have/need inline is the whole point: it answers "can I make
        -- this" without a second screen.
        if reagent.shortfall > 0 then
            line.name:SetText(("%dx %s"):format(reagent.quantity, label))
            line.value:SetText(("need %d"):format(reagent.shortfall))
            line.value:SetTextColor(Theme.Unpack("loss"))
        else
            line.name:SetText(("%dx %s"):format(reagent.quantity, label))
            line.value:SetText(Util.FormatMoney(reagent.lineCost, { short = true }))
            line.value:SetTextColor(Theme.Unpack("muted"))
        end

        line.frame:Show()
        anchor = line.frame
        y = y - 16
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

        detail.postValue:SetText(Util.FormatMoney(analysis.unitRevenue))
        detail.postValue:SetTextColor(Theme.Unpack("accent"))

        detail.cutValue:SetText("-" .. Util.FormatMoney(analysis.cut))

        -- Only known once the item has been priced at an auction house.
        if analysis.depositKnown then
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
    end

    -- Limit control reflects the override if there is one, else the default.
    if analysis.outputItemID then
        detail.limitLabel:Show()
        detail.limitBox:Show()
        detail.limitHint:Show()

        detail.limitBox:SetValue(analysis.postLimit or 0, true)

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

    -- Crafts, not items: see the Max button above.
    local suggested = math.max(1, analysis.craftableNow or 1)
    local suggestedRoom = analysis.roomInCrafts
    if suggestedRoom then
        suggested = math.max(1, math.min(suggested, suggestedRoom))
    end
    detail.quantity:SetText(tostring(suggested))

    if analysis.atPostLimit then
        detail.subtitle:SetText(("You already have %d -- at your limit"):format(
            analysis.stock or 0))
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
end

local function BuildList()
    local ranked = ns.Profit:GetRanked({
        accountWide = state.accountWide,
        ignorePostLimit = state.ignorePostLimit,
        sortBy = state.sortBy,
        craftableOnly = state.craftableOnly,
        includeUnpriceable = state.includeUnpriceable,
        skillLineID = state.profession,
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

    return ranked
end

local function Refresh()
    if not widgets.list then return end

    local data = BuildList()

    -- Rows set this again while they draw if an item is still uncached.
    awaitingItemData = false
    widgets.list:SetData(data)

    widgets.emptyLabel:SetShown(#data == 0)
    widgets.emptyScan:Hide()

    if #data == 0 then
        if ns.Recipes:Count() == 0 then
            widgets.emptyLabel:SetText("Open a profession window once so I can read your recipes.")
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
                minProfit = 0,
                minMargin = 0,
            })

            local minProfit = ns.Config:Get("minProfit") or 0
            local minMargin = ns.Config:Get("minMarginPercent") or 0

            if #hidden > 0 and (minProfit > 0 or minMargin > 0) then
                local best = hidden[1]

                widgets.emptyLabel:SetText((
                    "%d craft%s hidden by your minimums in Settings (%s profit, %d%% margin).\nThe best right now makes %s."):format(
                    #hidden, #hidden == 1 and "" or "s",
                    Util.FormatMoney(minProfit, { noColor = true, short = true }),
                    minMargin,
                    Util.FormatMoney(best.profit or 0, { noColor = true, short = true })))

            elseif state.search ~= "" then
                widgets.emptyLabel:SetText(("Nothing matching \"%s\"."):format(state.search))
            else
                widgets.emptyLabel:SetText("Nothing matches these filters.")
            end
        end
    end

    -- Keep the detail panel in step with the refreshed numbers.
    if state.selected then
        UpdateDetail(ns.Profit:Analyse(state.selected.recipeID))
    else
        UpdateDetail(nil)
    end

    widgets.countLabel:SetText(("%d craft%s"):format(#data, #data == 1 and "" or "s"))
end

--------------------------------------------------------------------------------
-- Build
--------------------------------------------------------------------------------

local function Build(container)
    -- Toolbar
    local toolbar = CreateFrame("Frame", nil, container)
    toolbar:SetPoint("TOPLEFT", 8, -8)
    toolbar:SetPoint("TOPRIGHT", -8, -8)
    toolbar:SetHeight(24)

    local search = Widgets.CreateSearchBox(toolbar, "Search crafts", function(text)
        state.search = text or ""
        Refresh()
    end)
    search:SetPoint("LEFT", 0, 0)
    search:SetWidth(190)

    local profession = Widgets.CreateDropdown(toolbar, { { text = "All professions", value = nil } },
        function(value)
            state.profession = value
            Refresh()
        end, { width = 150 })
    profession:SetPoint("LEFT", search, "RIGHT", 8, 0)
    widgets.professionDropdown = profession

    local craftable = Widgets.CreateCheckbox(toolbar, "Craftable now", function(checked)
        state.craftableOnly = checked
        Refresh()
    end, false)
    craftable:SetPoint("LEFT", profession, "RIGHT", 12, 0)

    local unpriceable = Widgets.CreateCheckbox(toolbar, "Show unpriced", function(checked)
        state.includeUnpriceable = checked
        Refresh()
    end, false)
    unpriceable:SetPoint("LEFT", craftable, "RIGHT", 12, 0)

    local accountWide = Widgets.CreateCheckbox(toolbar, "All characters", function(checked)
        state.accountWide = checked

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

    local sort = Widgets.CreateDropdown(toolbar, {
        { text = "Sort: Profit", value = "profit" },
        { text = "Sort: Margin", value = "margin" },
        { text = "Sort: ROI", value = "roi" },
    }, function(value)
        state.sortBy = value
        Refresh()
    end, { width = 110 })
    sort:SetPoint("RIGHT", 0, 0)
    sort:SetValue("profit")

    -- Column headings
    local headings = CreateFrame("Frame", nil, container)
    headings:SetPoint("TOPLEFT", toolbar, "BOTTOMLEFT", 0, -8)
    headings:SetPoint("TOPRIGHT", toolbar, "BOTTOMRIGHT", -DETAIL_WIDTH - 8, -8)
    headings:SetHeight(16)

    local nameHeading = Theme.CreateLabel(headings, "tiny", "dim")
    nameHeading:SetPoint("LEFT", 8 + MARK_GUTTER, 0)
    nameHeading:SetText("CRAFT")

    local labels = { cost = "COST", sells = "SELLS", profit = "PROFIT",
                     margin = "MARGIN", age = "AGE", who = "WHO", posted = "STOCK",
                     make = "MAKE" }

    widgets.headings = {}
    for _, column in ipairs(COLUMNS) do
        local heading = Theme.CreateLabel(headings, "tiny", "dim", "RIGHT")
        heading:SetText(labels[column.key])
        widgets.headings[column.key] = heading
    end

    ApplyHeadingLayout()

    local divider = Theme.CreateDivider(container)
    divider:SetPoint("TOPLEFT", headings, "BOTTOMLEFT", 0, -2)
    divider:SetPoint("TOPRIGHT", headings, "BOTTOMRIGHT", 0, -2)

    -- List
    local list = Widgets.CreateScrollList(container, {
        rowHeight = ROW_HEIGHT,
        createRow = CreateRow,
        updateRow = UpdateRow,

        -- Only starred rows get a tooltip, and it exists to explain the star.
        -- Everything else about a row is already on the row or one click away
        -- in the detail panel, and a tooltip over every line of a long table
        -- is noise.
        onEnter = function(row, analysis)
            if not analysis.recommended then return end
            ShowMarkTooltip(row, analysis)
        end,

        onLeave = function() GameTooltip:Hide() end,

        onClick = function(analysis, _, mouseButton)
            if mouseButton == "RightButton" then
                -- Right-click is the fast path: queue one without leaving the list.
                ns.Queue:Add(analysis.recipeID, 1)
                ns.Print(("queued 1x %s"):format(analysis.name or "craft"))
                return
            end

            state.selected = analysis
            UpdateDetail(ns.Profit:Analyse(analysis.recipeID))
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

    local hint = Theme.CreateLabel(container, "tiny", "dim", "RIGHT")
    hint:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", -DETAIL_WIDTH - 16, 8)
    hint:SetText("Right-click a row to queue one")

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

local function OnShow()
    -- Built from the skill lines the cached recipes actually carry, not from
    -- the profession list. Forever reports each profession under two skill-line
    -- IDs (Leatherworking is both 2945 and 165) and a recipe may be tagged with
    -- either, so matching the two lists against each other drops entries.
    local options = { { text = "All professions", value = nil } }

    local seen = {}
    for _, recipe in pairs(ns.Recipes:GetAll()) do
        local skillLineID = recipe.skillLineID

        if skillLineID and not seen[skillLineID] then
            seen[skillLineID] = true

            local name
            if ns.Util.HasFunction("C_TradeSkillUI.GetProfessionInfoBySkillLineID") then
                local ok, info = pcall(C_TradeSkillUI.GetProfessionInfoBySkillLineID, skillLineID)
                if ok and info then name = info.professionName end
            end

            options[#options + 1] = {
                text = name or ("Skill line " .. skillLineID),
                value = skillLineID,
            }
        end
    end

    table.sort(options, function(a, b)
        if a.value == nil then return true end
        if b.value == nil then return false end
        return a.text < b.text
    end)

    widgets.professionDropdown:SetOptions(options)
end

UI:RegisterTab({
    key = "profit",
    text = "Profit",
    order = 1,
    build = Build,
    refresh = Refresh,
    onShow = OnShow,
})
