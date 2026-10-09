-- Blackthornes Tradeskills -- UI/DealsWrits.lua
-- The Deals tab's Craftsman's Writs view: writs by what a point of
-- reputation costs, and what a reputation goal still costs.
--
-- A player's idea (2026-10-09). Each row is a writ: the writ on the auction
-- house, the item it asks for (bought, or made from bought materials), and
-- what that makes one point of reputation cost. The panel on the right reads
-- the character's standing with the trade camp, and says how many writs the
-- goal picked on the option bar still needs and what the cheapest and the
-- quickest ways cost. The sums are Logic/Writs.lua. Tab_Deals.lua shows this
-- in place of its flips when its Show menu says so, and owns the option bar.

local _, ns = ...

local Theme = ns.Theme
local Widgets = ns.Widgets
local Util = ns.Util

local DealsWrits = ns.NewModule("DealsWrits")

local ROW_HEIGHT = 22
local DETAIL_WIDTH = 300
local ICON_GUTTER = 20

-- Columns, laid out right to left, as on the flips list.
local COLUMNS = {
    { key = "perRep",    label = "PER REP", width = 66, money = true },
    { key = "total",     label = "TOTAL",   width = 66, money = true },
    { key = "itemCost",  label = "ITEM",    width = 66, money = true },
    { key = "writPrice", label = "WRIT",    width = 66, money = true },
    { key = "rep",       label = "REP",     width = 40, justify = "CENTER" },
}

local state = {
    search = "",
    goal = nil,         -- read from Settings the first time it is asked
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

local function Round(value)
    return value and math.floor(value + 0.5) or nil
end

local function TierName(tier)
    return ns.WRIT_TIERS and ns.WRIT_TIERS[tier] or "?"
end

local function SameRow(a, b)
    return a and b and a.key == b.key
end

--- Where the reputation figure came from, in a few words.
local function RewardText(row)
    if row.source == "learned" then
        local times = row.turnIns == 1 and "one turn-in" or ("%d turn-ins"):format(row.turnIns or 1)
        return ("%d reputation, seen paid on %s."):format(row.rep, times)
    elseif row.source == "reported" then
        return ("Guides report %d reputation. Not seen paid here yet."):format(row.rep)
    end
    return "Nobody knows what it pays yet."
end

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

local function SearchWrit(row)
    if row then Search(row.writID, "this writ") end
end

local function SearchItem(row)
    if row then Search(row.itemID, "this item") end
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
        cell:SetJustifyH(column.justify or "RIGHT")
        offset = offset - column.width - 6
        row.cells[index] = cell
    end

    row.name:SetPoint("RIGHT", row, "RIGHT", offset - 4, 0)
end

local function FillCell(cell, key, entry)
    if key == "rep" then
        cell:SetText(entry.rep and tostring(entry.rep) or "?")
        cell:SetTextColor(Theme.Unpack(entry.source == "learned" and "text"
            or entry.source == "reported" and "muted" or "warn"))
        return
    end

    local value = entry[key]
    if key == "perRep" then value = Round(value) end
    cell:SetText(value and Money(value) or "")
    cell:SetTextColor(Theme.Unpack(key == "perRep" and "accent" or key == "total" and "text" or "muted"))
end

local function NameText(entry)
    local text = entry.count > 1 and ("%d %s"):format(entry.count, entry.name) or entry.name
    if entry.haveWrits > 0 then text = ("%s  (%d)"):format(text, entry.haveWrits) end
    return text
end

local function UpdateRow(row, entry)
    Theme.SetRowName(row.name, NameText(entry))
    Theme.SetItemIcon(row.icon, entry.itemID)
    row.name:SetTextColor(Theme.Unpack(entry.perRep and "text" or "dim"))

    for index, column in ipairs(COLUMNS) do
        FillCell(row.cells[index], column.key, entry)
    end
end

local function ItemLine(entry)
    if not entry.itemCost then return nil end
    local made = entry.how == "make" and "made from materials" or "bought"
    if entry.count > 1 then
        return ("%d %s, %s: %s"):format(entry.count, entry.name, made, Plain(entry.itemCost))
    end
    return ("%s, %s: %s"):format(entry.name, made, Plain(entry.itemCost))
end

local function ShowRowTooltip(row, entry)
    GameTooltip:SetOwner(row, "ANCHOR_LEFT")
    GameTooltip:AddLine("Craftsman's Writ: " .. entry.name)
    GameTooltip:AddLine(("%s %s, skill %d"):format(TierName(entry.tier), entry.prof, entry.writ.skill),
        0.7, 0.7, 0.7)

    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(("Writ: %s"):format(entry.writPrice and Plain(entry.writPrice) or "not priced"),
        0.85, 0.85, 0.85)
    GameTooltip:AddLine(ItemLine(entry) or "Item: not priced", 0.85, 0.85, 0.85, true)
    if entry.perRep then
        GameTooltip:AddLine(("%s for each reputation."):format(Plain(Round(entry.perRep))), 0.35, 0.85, 0.45, true)
    end
    GameTooltip:AddLine(RewardText(entry), 0.7, 0.7, 0.7, true)
    if entry.haveWrits > 0 then
        GameTooltip:AddLine(("You carry %d of these writs."):format(entry.haveWrits), 0.85, 0.85, 0.85)
    end
    GameTooltip:AddLine("Right-click to search the auction house for the writ.", 0.5, 0.5, 0.5)
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

    Theme.SetRowName(line.label, label)
    line.label:SetTextColor(Theme.Unpack(labelColor or "muted"))
    line.value:SetText(value or "")
    line.value:SetTextColor(Theme.Unpack(valueColor or "text"))
end

local function BuildDetail(parent)
    local detail = Theme.CreatePanel(parent, "window")
    detail:SetWidth(DETAIL_WIDTH)
    Theme.AccentStripe(detail, 2, 0.6)

    detail.title = Theme.CreateLabel(detail, "large", "accent")
    detail.title:SetPoint("TOPLEFT", 12, -12)
    detail.title:SetPoint("TOPRIGHT", -12, -12)
    detail.title:SetWordWrap(true)

    detail.goal = Lines(detail, 5)
    detail.goal:SetPoint("TOPLEFT", detail.title, "BOTTOMLEFT", 0, -10)
    detail.goal:SetPoint("RIGHT", detail, "RIGHT", -12, 0)

    detail.routeHeading = Theme.CreateHeading(detail, "BUYING WRITS AND ITEMS")
    detail.routeHeading:SetPoint("TOPLEFT", detail.goal, "BOTTOMLEFT", 0, -12)

    detail.route = Lines(detail, 2)
    detail.route:SetPoint("TOPLEFT", detail.routeHeading, "BOTTOMLEFT", 0, -8)
    detail.route:SetPoint("RIGHT", detail, "RIGHT", -12, 0)

    detail.writHeading = Theme.CreateHeading(detail, "PICK A WRIT")
    detail.writHeading:SetPoint("TOPLEFT", detail.route, "BOTTOMLEFT", 0, -12)

    detail.writ = Lines(detail, 4)
    detail.writ:SetPoint("TOPLEFT", detail.writHeading, "BOTTOMLEFT", 0, -8)
    detail.writ:SetPoint("RIGHT", detail, "RIGHT", -12, 0)

    detail.note = Theme.CreateLabel(detail, "tiny", "dim")
    detail.note:SetPoint("TOPLEFT", detail.writ, "BOTTOMLEFT", 0, -10)
    detail.note:SetPoint("RIGHT", detail, "RIGHT", -12, 0)
    detail.note:SetWordWrap(true)
    detail.note:SetJustifyV("TOP")

    detail.writButton = Widgets.CreateButton(detail, "Search writ", function()
        SearchWrit(state.selected)
    end, { width = 134, primary = true, height = 24 })
    detail.writButton:SetPoint("BOTTOMLEFT", 12, 14)
    detail.writButton.tooltipText = "Sends a search for this writ, so it shows in the auction house list. Buying still takes your own click on the game's Buy button."

    detail.itemButton = Widgets.CreateButton(detail, "Search item", function()
        SearchItem(state.selected)
    end, { width = 134, height = 24 })
    detail.itemButton:SetPoint("LEFT", detail.writButton, "RIGHT", 8, 0)
    detail.itemButton.tooltipText = "Sends a search for the item the writ asks for."

    return detail
end

local function UpdateGoal(plan)
    local detail = widgets.detail
    local faction = plan.faction
    local lines = detail.goal.lines

    if not faction then
        detail.title:SetText(plan.goal.text)
        SetLine(lines[1], "Writs pay reputation with your side's trade camp.", "")
        for index = 2, 5 do SetLine(lines[index], nil) end
        return
    end

    detail.title:SetText(("%s with %s"):format(plan.goal.text, faction.name))

    if plan.standing then
        SetLine(lines[1], ("Now (%s)"):format(ns.Writs.StandingText(plan.standing)), tostring(plan.standing))
    else
        SetLine(lines[1], "The game did not say your standing", "?", "warn", "warn")
    end

    if plan.need == 0 then
        SetLine(lines[2], "Goal reached", "", "profit")
        for index = 3, 5 do SetLine(lines[index], nil) end
    else
        SetLine(lines[2], "Still to go", tostring(plan.need), "text", "accent")
        for tier = 1, 3 do
            local entry = plan.perTier[tier]
            if entry and entry.writs then
                local marked = entry.source == "reported" and "*" or ""
                SetLine(lines[tier + 2], ("%s writs (%d each%s)"):format(TierName(tier), entry.rep, marked),
                    tostring(entry.writs))
            else
                SetLine(lines[tier + 2], nil)
            end
        end
    end

    local route = detail.route.lines
    if plan.cheapest then
        local cheapest = plan.cheapest
        SetLine(route[1], ("Cheapest: %d %s, one a day"):format(cheapest.writs, cheapest.row.name),
            Plain(Round(cheapest.cost)), "text", "accent")
        local quickest = plan.quickest
        local days = quickest.days == 1 and "1 day" or ("%d days"):format(quickest.days)
        SetLine(route[2], ("Quickest: %d writs over %s"):format(quickest.writs, days), Plain(Round(quickest.cost)))
    elseif plan.need > 0 then
        SetLine(route[1], "No writ is fully priced yet", "")
        SetLine(route[2], nil)
    else
        SetLine(route[1], nil)
        SetLine(route[2], nil)
    end
    detail.routeHeading:SetShown(plan.need > 0)
end

local function UpdateWrit(entry)
    local detail = widgets.detail
    local lines = detail.writ.lines

    detail.writButton:SetShown(entry ~= nil)
    detail.itemButton:SetShown(entry ~= nil)

    if not entry then
        detail.writHeading:SetText("PICK A WRIT")
        SetLine(lines[1], "Click a row for its sums.", "")
        for index = 2, 4 do SetLine(lines[index], nil) end
    else
        detail.writHeading:SetText(("%s %s"):format(TierName(entry.tier), entry.prof):upper())
        SetLine(lines[1], "Writ on the AH", entry.writPrice and Plain(entry.writPrice) or "not priced")
        local what = entry.count > 1 and ("%d %s"):format(entry.count, entry.name) or entry.name
        SetLine(lines[2], what .. (entry.how == "make" and " (made)" or ""),
            entry.itemCost and Plain(entry.itemCost) or "not priced")
        SetLine(lines[3], "Money back", entry.money and entry.money > 0 and Plain(entry.money) or "none known")
        SetLine(lines[4], entry.rep and ("Each of %d reputation"):format(entry.rep) or "Each reputation",
            entry.perRep and Plain(Round(entry.perRep)) or "not known", "text", "accent")
    end

    local parts = {}
    if entry then
        parts[#parts + 1] = RewardText(entry)
        if entry.how == "make" and entry.buy then
            parts[#parts + 1] = ("Bought, it would be %s."):format(Plain(entry.buy))
        end
        if entry.haveWrits > 0 then
            parts[#parts + 1] = ("You carry %d of these writs."):format(entry.haveWrits)
        end
        if not entry.writID then
            parts[#parts + 1] = "This writ has not been seen in the game yet, so it has no auction house price."
        end
    else
        parts[#parts + 1] = "* As the guides report it, until a turn-in is seen here."
    end
    parts[#parts + 1] = "Each order can be done once a day. The coin pouch a turn-in gives is not counted."
    detail.note:SetText(table.concat(parts, " "))
end

--------------------------------------------------------------------------------
-- List
--------------------------------------------------------------------------------

local function CountText(rows)
    local priced, cheapest = 0, nil
    for _, row in ipairs(rows) do
        if row.perRep then
            priced = priced + 1
            if not cheapest or row.perRep < cheapest.perRep then cheapest = row end
        end
    end

    if not cheapest then
        if (ns.Prices and ns.Prices:Count() or 0) == 0 then
            return { "Scan the auction house to price the writs and what they ask for." }
        end
        return { "No writ is fully priced yet. Scan again once some are listed." }
    end

    local plural = priced == 1 and "" or "s"
    local money = Util.FormatMoney(Round(cheapest.perRep), { noColor = true, short = true })
    return {
        ("%d writ%s priced, cheapest reputation %s each (%s)"):format(priced, plural, money, cheapest.name),
        ("%d writ%s priced, cheapest reputation %s"):format(priced, plural, money),
        ("%d writ%s priced"):format(priced, plural),
    }
end

local function Matches(row, needle)
    return row.name:lower():find(needle, 1, true) or row.prof:lower():find(needle, 1, true)
        or TierName(row.tier):lower():find(needle, 1, true)
end

function DealsWrits:Refresh()
    if not widgets.list then return end

    local all = ns.Writs:GetRows()
    local rows = all

    if state.search ~= "" then
        local needle = state.search:lower()
        rows = {}
        for _, row in ipairs(all) do
            if Matches(row, needle) then rows[#rows + 1] = row end
        end
    end

    if widgets.sorter then rows = widgets.sorter:Sort(rows) end
    widgets.list:SetData(rows)

    widgets.emptyLabel:SetShown(#rows == 0)
    if #rows == 0 then widgets.emptyLabel:SetText(("No writ matching \"%s\"."):format(state.search)) end

    local texts = CountText(rows)
    if Theme.FitText then Theme.FitText(widgets.countLabel, texts) else widgets.countLabel:SetText(texts[1]) end

    -- The goal is worked out over every writ, whatever the search shows.
    UpdateGoal(ns.Writs:GetPlan(DealsWrits:GetGoal(), all))

    local fresh
    for _, row in ipairs(rows) do
        if SameRow(row, state.selected) then fresh = row break end
    end
    state.selected = fresh
    UpdateWrit(fresh)
end

function DealsWrits:SetSearch(text)
    state.search = text or ""
end

function DealsWrits:SetGoal(key)
    state.goal = ns.Writs.GoalFor(key).key
end

function DealsWrits:GetGoal()
    if state.goal == nil then
        state.goal = ns.Writs.GoalFor(ns.Config:Get("writGoal")).key
    end
    return state.goal
end

function DealsWrits:ScrollToTop()
    if widgets.list then widgets.list:ScrollToTop() end
end

--------------------------------------------------------------------------------
-- Build
--------------------------------------------------------------------------------

--- Lay the view out in `view`, under the tab's option bar `toolbar`.
function DealsWrits:Build(view, toolbar)
    if Widgets.FitColumns then Widgets.FitColumns(COLUMNS) end

    local headings = CreateFrame("Frame", nil, view)
    headings:SetPoint("TOPLEFT", toolbar, "BOTTOMLEFT", 0, -8)
    headings:SetPoint("TOPRIGHT", toolbar, "BOTTOMRIGHT", -DETAIL_WIDTH - 8, -8)
    headings:SetHeight(16)

    local nameHeading = Theme.CreateLabel(headings, "tiny", "muted")
    nameHeading:SetPoint("LEFT", 8 + ICON_GUTTER, 0)
    nameHeading:SetText("WRIT ASKS FOR")

    local labels = { name = nameHeading }
    local values = { name = function(row) return row.name end }
    local offset = -8
    for index, column in ipairs(COLUMNS) do
        local heading = Theme.CreateLabel(headings, "tiny", "muted", "RIGHT")
        heading:SetText(column.label)
        heading:SetPoint("RIGHT", offset, 0)
        heading:SetWidth(column.width)
        heading:SetJustifyH(column.justify or "RIGHT")
        offset = offset - column.width - 6
        labels[index] = heading
        values[index] = function(row) return row[column.key] end
    end

    -- Click a heading to sort by it; until then, cheapest reputation first.
    widgets.sorter = Widgets.SortableHeadings and Widgets.SortableHeadings(labels, values,
        function() DealsWrits:Refresh() end)
    if widgets.sorter then widgets.sorter:SetText({ "name" }) end

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
            UpdateWrit(entry)
            if mouseButton == "RightButton" then SearchWrit(entry) end
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
    hint:SetText("Right-click a row to search for the writ")

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

    -- Writs and items the client had not cached arrive a few at a time,
    -- and a turn-in moves the standing; one redraw for a burst.
    local queued = false
    local function Soon()
        if queued or not list:IsVisible() then return end
        queued = true
        C_Timer.After(1, function()
            queued = false
            if list:IsVisible() then DealsWrits:Refresh() end
        end)
    end
    ns.RegisterEvent(widgets, "GET_ITEM_INFO_RECEIVED", Soon)
    ns.RegisterEvent(widgets, "UPDATE_FACTION", Soon)

    ns.Writs:FindWrits()
end
