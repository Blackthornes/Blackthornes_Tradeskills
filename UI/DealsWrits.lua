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
local L = ns.L or setmetatable({ Format = string.format }, { __index = function(_, key) return key end })

local Theme = ns.Theme
local Widgets = ns.Widgets
local Util = ns.Util

local DealsWrits = ns.NewModule("DealsWrits")

local ROW_HEIGHT = 22
local DETAIL_WIDTH = 300
local ICON_GUTTER = 20

-- Columns, laid out right to left, as on the flips list.
local COLUMNS = {
    { key = "perRep",    label = L["PER REP"], width = 66, money = true },
    { key = "total",     label = L["TOTAL"], width = 66, money = true },
    { key = "itemCost",  label = L["ITEM"], width = 66, money = true },
    { key = "writPrice", label = L["WRIT"], width = 66, money = true },
    { key = "rep",       label = L["REP"], width = 40, justify = "CENTER" },
}

-- Any column but the item's name can be hidden (UI/Columns.lua).
ns.Columns:Register("writs", L["Deals: Craftsman's Writs"], COLUMNS)

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
        if row.turnIns == 1 then
            return L.Format("Pays %d reputation, seen on one turn-in.", row.rep)
        end
        return L.Format("Pays %d reputation, seen on %d turn-ins.", row.rep, row.turnIns or 1)
    elseif row.source == "reported" then
        return L.Format("Guides report %d reputation. Not seen on a turn-in here yet.", row.rep)
    end
    return L["Nobody knows what it pays yet."]
end

local function Search(itemID, what)
    local scanner = ns.Scanner
    if not scanner or not scanner.isAuctionHouseOpen then
        ns.Print(L["Open the auction house first, then search again."])
        return
    end
    if scanner.isScanning then
        ns.Print(L["A scan is running. Search again once it finishes."])
        return
    end
    if not itemID then
        if what == "writ" then
            ns.Print(L["The game hasn't shown this writ to the addon yet, so type its name into the auction house search box."])
        else
            ns.Print(L["The game hasn't shown this item to the addon yet, so type its name into the auction house search box."])
        end
        return
    end
    ns.UI:SearchAuctionHouse(itemID)
end

local function SearchWrit(row)
    if row then Search(row.writID, "writ") end
end

local function SearchItem(row)
    if row then Search(row.itemID, "item") end
end

--------------------------------------------------------------------------------
-- Rows
--------------------------------------------------------------------------------

--- The shown columns from the right edge; the name has the rest.
local function PlaceRow(row)
    local offset = ns.Columns:Place("writs", COLUMNS, row.cells, { byIndex = true })
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
    if row.columnsVersion ~= ns.Columns.version then PlaceRow(row) end

    Theme.SetRowName(row.name, NameText(entry))
    Theme.SetItemIcon(row.icon, entry.itemID)
    -- In its rarity colour, faded while it has no price.
    local r, g, b = Util.GetItemQualityColor(entry.itemID)
    if r then
        row.name:SetTextColor(r, g, b, entry.perRep and 1 or 0.55)
    else
        row.name:SetTextColor(Theme.Unpack(entry.perRep and "text" or "dim"))
    end

    for index, column in ipairs(COLUMNS) do
        FillCell(row.cells[index], column.key, entry)
    end
end

local function ItemLine(entry)
    if not entry.itemCost then return nil end
    local cost = Plain(entry.itemCost)
    local name = Util.ColorItemName(entry.itemID, entry.name)
    if entry.how == "make" then
        if entry.count > 1 then
            return L.Format("%d %s, made from materials: %s", entry.count, name, cost)
        end
        return L.Format("%s, made from materials: %s", name, cost)
    end
    if entry.count > 1 then
        return L.Format("%d %s, bought: %s", entry.count, name, cost)
    end
    return L.Format("%s, bought: %s", name, cost)
end

local function ShowRowTooltip(row, entry)
    GameTooltip:SetOwner(row, "ANCHOR_LEFT")
    GameTooltip:AddLine(L.Format("Craftsman's Writ: %s", Util.ColorItemName(entry.itemID, entry.name)))
    GameTooltip:AddLine(L.Format("%s %s, skill %d", TierName(entry.tier), entry.prof, entry.writ.skill),
        0.7, 0.7, 0.7)

    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(L.Format("Writ: %s", entry.writPrice and Plain(entry.writPrice)
        or (entry.noneListed and L["none listed"] or L["not priced"])),
        0.85, 0.85, 0.85)
    GameTooltip:AddLine(ItemLine(entry) or L["Item: not priced"], 0.85, 0.85, 0.85, true)
    if entry.perRep then
        GameTooltip:AddLine(L.Format("%s for each reputation.", Plain(Round(entry.perRep))), 0.35, 0.85, 0.45, true)
    end
    GameTooltip:AddLine(RewardText(entry), 0.7, 0.7, 0.7, true)
    if entry.haveWrits > 0 then
        GameTooltip:AddLine(L.Format("You carry %d of these writs.", entry.haveWrits), 0.85, 0.85, 0.85)
    end
    GameTooltip:AddLine(L["Right-click to search the auction house for the writ."], 0.5, 0.5, 0.5)
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

    detail.routeHeading = Theme.CreateHeading(detail, L["BUYING WRITS AND ITEMS"])
    detail.routeHeading:SetPoint("TOPLEFT", detail.goal, "BOTTOMLEFT", 0, -12)

    detail.route = Lines(detail, 2)
    detail.route:SetPoint("TOPLEFT", detail.routeHeading, "BOTTOMLEFT", 0, -8)
    detail.route:SetPoint("RIGHT", detail, "RIGHT", -12, 0)

    detail.writHeading = Theme.CreateHeading(detail, L["PICK A WRIT"])
    detail.writHeading:SetPoint("TOPLEFT", detail.route, "BOTTOMLEFT", 0, -12)

    detail.writ = Lines(detail, 4)
    detail.writ:SetPoint("TOPLEFT", detail.writHeading, "BOTTOMLEFT", 0, -8)
    detail.writ:SetPoint("RIGHT", detail, "RIGHT", -12, 0)

    detail.note = Theme.CreateLabel(detail, "tiny", "dim")
    detail.note:SetPoint("TOPLEFT", detail.writ, "BOTTOMLEFT", 0, -10)
    detail.note:SetPoint("RIGHT", detail, "RIGHT", -12, 0)
    detail.note:SetWordWrap(true)
    detail.note:SetJustifyV("TOP")

    detail.writButton = Widgets.CreateButton(detail, L["Search writ"], function()
        SearchWrit(state.selected)
    end, { width = 134, primary = true, height = 24 })
    detail.writButton:SetPoint("BOTTOMLEFT", 12, 14)
    detail.writButton.tooltipText = L["Finds this writ on the auction house. You click Buy yourself."]

    detail.itemButton = Widgets.CreateButton(detail, L["Search item"], function()
        SearchItem(state.selected)
    end, { width = 134, height = 24 })
    detail.itemButton:SetPoint("LEFT", detail.writButton, "RIGHT", 8, 0)
    detail.itemButton.tooltipText = L["Finds the item the writ asks for on the auction house."]

    return detail
end

local function UpdateGoal(plan)
    local detail = widgets.detail
    local faction = plan.faction
    local lines = detail.goal.lines

    if not faction then
        detail.title:SetText(plan.goal.text)
        SetLine(lines[1], L["Writs pay reputation with your side's trade camp."], "")
        for index = 2, 5 do SetLine(lines[index], nil) end
        return
    end

    detail.title:SetText(L.Format("%s with %s", plan.goal.text, faction.name))

    if plan.standing then
        SetLine(lines[1], L.Format("Now (%s)", ns.Writs.StandingText(plan.standing)), tostring(plan.standing))
    else
        SetLine(lines[1], L["Your standing isn't known yet"], "?", "warn", "warn")
    end

    if plan.need == 0 then
        SetLine(lines[2], L["Goal reached"], "", "profit")
        for index = 3, 5 do SetLine(lines[index], nil) end
    else
        SetLine(lines[2], L["Still to go"], tostring(plan.need), "text", "accent")
        for tier = 1, 3 do
            local entry = plan.perTier[tier]
            if entry and entry.writs then
                local marked = entry.source == "reported" and "*" or ""
                SetLine(lines[tier + 2], L.Format("%s writs (%d each%s)", TierName(tier), entry.rep, marked),
                    tostring(entry.writs))
            else
                SetLine(lines[tier + 2], nil)
            end
        end
    end

    local route = detail.route.lines
    if plan.cheapest then
        local cheapest = plan.cheapest
        SetLine(route[1], L.Format("Cheapest: %d %s, one a day", cheapest.writs,
            Util.ColorItemName(cheapest.row.itemID, cheapest.row.name)),
            Plain(Round(cheapest.cost)), "text", "accent")
        local quickest = plan.quickest
        local text = quickest.days == 1 and L.Format("Quickest: %d writs over 1 day", quickest.writs)
            or L.Format("Quickest: %d writs over %d days", quickest.writs, quickest.days)
        SetLine(route[2], text, Plain(Round(quickest.cost)))
    elseif plan.need > 0 then
        SetLine(route[1], L["No writ is fully priced yet"], "")
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
        detail.writHeading:SetText(L["PICK A WRIT"])
        SetLine(lines[1], L["Click a row to see how it adds up."], "")
        for index = 2, 4 do SetLine(lines[index], nil) end
    else
        detail.writHeading:SetText(("%s %s"):format(TierName(entry.tier), entry.prof):upper())
        SetLine(lines[1], L["Writ on the AH"], entry.writPrice and Plain(entry.writPrice)
            or (entry.noneListed and L["none listed"] or L["not priced"]))
        local named = Util.ColorItemName(entry.itemID, entry.name)
        local what = entry.count > 1 and ("%d %s"):format(entry.count, named) or named
        SetLine(lines[2], entry.how == "make" and L.Format("%s (made)", what) or what,
            entry.itemCost and Plain(entry.itemCost) or L["not priced"])
        SetLine(lines[3], L["Money back"], entry.money and entry.money > 0 and Plain(entry.money) or L["none known"])
        SetLine(lines[4], entry.rep and L.Format("Each of %d reputation", entry.rep) or L["Each reputation"],
            entry.perRep and Plain(Round(entry.perRep)) or L["not known"], "text", "accent")
    end

    local parts = {}
    if entry then
        parts[#parts + 1] = RewardText(entry)
        if entry.how == "make" and entry.buy then
            parts[#parts + 1] = L.Format("Bought, it would be %s.", Plain(entry.buy))
        end
        if entry.haveWrits > 0 then
            parts[#parts + 1] = L.Format("You carry %d of these writs.", entry.haveWrits)
        end
        if not entry.writID then
            parts[#parts + 1] = L["This writ has not been seen in the game yet, so it has no auction house price."]
        end
    else
        parts[#parts + 1] = L["* From guides, until you turn one in."]
    end
    parts[#parts + 1] = L["Each order can be done once a day. The coin pouch a turn-in gives is not counted."]
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
            return { L["Scan the auction house to price the writs and what they ask for."] }
        end
        return { L["No writ is fully priced yet. Scan again once some are listed."] }
    end

    local money = Util.FormatMoney(Round(cheapest.perRep), { noColor = true, short = true })
    if priced == 1 then
        return {
            L.Format("%d writ priced, cheapest reputation %s each (%s)", priced, money, cheapest.name),
            L.Format("%d writ priced, cheapest reputation %s", priced, money),
            L.Format("%d writ priced", priced),
        }
    end
    return {
        L.Format("%d writs priced, cheapest reputation %s each (%s)", priced, money, cheapest.name),
        L.Format("%d writs priced, cheapest reputation %s", priced, money),
        L.Format("%d writs priced", priced),
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
    if #rows == 0 then widgets.emptyLabel:SetText(L.Format("No writ matching \"%s\".", state.search)) end

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
    nameHeading:SetText(L["WRIT ASKS FOR"])

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
    ns.Columns:Place("writs", COLUMNS, cells, { byIndex = true })

    -- Click a heading to sort by it; until then, cheapest reputation first.
    widgets.sorter = Widgets.SortableHeadings and Widgets.SortableHeadings(labels, values,
        function() DealsWrits:Refresh() end)
    if widgets.sorter then widgets.sorter:SetText({ "name" }) end

    -- Right-click the headings to choose the columns.
    ns.Columns:Attach(headings, "writs", widgets.sorter)
    ns.Columns:OnChange("writs", function()
        ns.Columns:Place("writs", COLUMNS, cells, { byIndex = true })
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
    hint:SetText(L["Right-click a row to search for the writ"])

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
