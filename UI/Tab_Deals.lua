-- Blackthornes Tradeskills -- UI/Tab_Deals.lua
-- Items on the auction house worth buying, and what to do with them.
--
-- The Disenchanting and Vendor Flips tabs made into one (Ezmode's idea,
-- 2026-10-07). Every item someone else has listed, priced at their cheapest
-- listing from your last scan, against the ways it can be turned into gold:
--
--   AH      list it again under its usual price (Logic/VendorFlips.lua,
--           Voldar's idea, 2026-10-06)
--   DE      disenchant it and sell the materials (Logic/Disenchant.lua)
--   Vendor  sell it to any vendor for more than it cost (Logic/VendorFlips.lua)
--
-- The Sell to menu ticks which ways count. An item shows once, on the way
-- that pays most, and the VIA column says which. A disenchant none of your
-- characters can do yet gives way to any other way that pays. The detail
-- pane says what the other ways would make.
--
-- The addon cannot buy for you: the game wants a real click on its own Buy
-- button for every purchase. What it can do is send the search, so the item
-- is in the auction house list ready to click.
--
-- "Items in my bags" lists what you carry that can be disenchanted, against
-- what it would sell for, with a Disenchant button. That button is the
-- secure one in UI/Disenchanter.lua: one disenchant per click.

local _, ns = ...

local Theme = ns.Theme
local Widgets = ns.Widgets
local Util = ns.Util

local UI = ns.UI

local ROW_HEIGHT = 22
local DETAIL_WIDTH = 300
local ICON_GUTTER = 20

-- The ways to sell, in the Sell to menu's order, with the VIA column's word
-- for each. The same words as the Profit tab's VIA and the queue's marks.
local ROUTES = {
    { key = "auction",    via = "AH",     text = "Auction house" },
    { key = "disenchant", via = "DE",     text = "Disenchant" },
    { key = "vendor",     via = "Vendor", text = "Vendor" },
}

local VIA = {}
for _, route in ipairs(ROUTES) do VIA[route.key] = route.via end

-- Columns per view, laid out right to left, so VIA sits next to the item's
-- name. Money sits to the right, so its coins line up; the rest is centred
-- under its heading. `width` is the least each gets: Widgets.FitColumns
-- widens it to fit the heading and an amount.
local VIEWS = {
    auction = {
        columns = {
            { key = "gain",   label = "PROFIT", width = 66, money = true },
            { key = "margin", label = "MARGIN", width = 50, justify = "CENTER" },
            { key = "gets",   label = "GETS",   width = 70, money = true },
            { key = "buy",    label = "BUY",    width = 66, money = true },
            { key = "age",    label = "AGE",    width = 44, justify = "CENTER" },
            { key = "via",    label = "VIA",    width = 44, justify = "CENTER" },
        },
        hint = "Right-click a row to search for it",
    },
    bag = {
        columns = {
            { key = "difference", label = "DIFFERENCE", width = 74, money = true },
            { key = "value",      label = "DISENCHANT", width = 70, money = true },
            { key = "sells",      label = "SELLS",      width = 70, money = true },
            { key = "count",      label = "HAVE",       width = 40, justify = "CENTER" },
            { key = "via",        label = "VIA",        width = 44, justify = "CENTER" },
        },
        hint = "Pick an item, then click Disenchant",
    },
}

local MAX_COLUMNS = 6

local state = {
    view = "auction",
    routes = { auction = true, disenchant = true, vendor = true },
    search = "",
    dealsOnly = true,
    hideTooHigh = false,
    beatsOnly = false,
    selected = nil,
    hidden = 0,
    pending = 0,
    thin = 0,
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

local function MarginText(margin)
    return ("%d%%"):format(math.floor((margin or 0) * 100))
end

local function SameRow(a, b)
    return a and b and a.kind == b.kind and a.itemID == b.itemID
end

--- How many disenchants this session and what they gave, or 0 before the first.
local function Session()
    local log = ns.DisenchantLog
    if not log or not log.GetSession then return 0, 0 end

    local count, worth = log:GetSession()
    return count or 0, worth or 0
end

--- The time now, or nil without a clock (a test's).
local function Now()
    return type(time) == "function" and time() or nil
end

--- Any way ticked in the Sell to menu?
local function AnyRoute()
    return next(state.routes) ~= nil
end

--- What the VIA column says for an item in the bags: DE when disenchanting
--- pays more than selling it, else where it sells.
local function BagVia(entry)
    if entry.beatsSale or (entry.value and not entry.sells) then return VIA.disenchant end
    if entry.sells then return entry.sellsAt == "vendor" and VIA.vendor or VIA.auction end
    return ""
end

--- One way's profit in words, for a line on what the other ways make.
local function OtherWay(row)
    local how = row.route == "disenchant" and "disenchanted"
        or row.route == "vendor" and "sold to a vendor" or "listed again"
    return ("%s, %s"):format(how, Util.FormatMoney(row.gain, { noColor = true, short = true }))
end

--- "Other ways: ..." for a row that more than one way pays on, or nil.
local function OthersText(entry)
    if not entry.others or #entry.others == 0 then return nil end

    local parts = {}
    for _, other in ipairs(entry.others) do parts[#parts + 1] = OtherWay(other) end
    return ("Other ways: %s."):format(table.concat(parts, "; "))
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

    -- The same search as the rest of the addon's item clicks: its own slot
    -- in the queue, at click priority. The scan's slot was shared, so this
    -- could replace a waiting scan (or a scan could drop this search).
    if not ns.UI:SearchAuctionHouse(entry.itemID) then return end

    local label = Util.GetItemLabel(entry.itemID)

    if entry.route == "auction" then
        ns.Print(("Searching the auction house for %s. Anything under %s each pays to list again at %s. If the list there does not change, type the name into its search box."):format(
            label, Plain(math.floor(entry.net)), Plain(entry.resell)))
    elseif entry.route == "vendor" then
        ns.Print(("Searching the auction house for %s. Anything at %s each or less is a vendor flip. If the list there does not change, type the name into its search box."):format(
            label, Plain(entry.vendor - 1)))
    else
        ns.Print(("Searching the auction house for %s. Buy it in the auction house window at %s or less. If the list there does not change, type the name into its search box."):format(
            label, Plain(entry.buy)))
    end
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
            cell:SetJustifyH(column.justify or "RIGHT")
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
    elseif key == "via" then
        text = entry.kind == "bag" and BagVia(entry) or entry.via or ""
        color = text == VIA.disenchant and "accent" or "muted"
    elseif key == "gets" then
        text = Money(entry.gets) .. (entry.route == "disenchant" and entry.partial and "+" or "")
        color = "text"
    elseif key == "value" then
        if entry.value then
            text = Money(entry.value) .. (entry.partial and "+" or "")
            color = entry.beatsSale and "profit" or "text"
        else
            text, color = "no price", "dim"
        end
    elseif key == "difference" then
        -- How much more disenchanting pays than selling, or less.
        if entry.value and entry.sells then
            cell:SetText(Money(entry.value - entry.sells))
            cell:SetTextColor(Theme.ProfitColor(entry.value - entry.sells))
            return
        end
        text, color = "", "dim"
    elseif key == "sells" then
        if entry.sells then
            text = Money(entry.sells)
        elseif entry.soulbound then
            text, color = "soulbound", "dim"
        else
            text, color = "no price", "dim"
        end
    elseif key == "count" then
        text = tostring(entry.count or 0)
    elseif key == "buy" then
        text = Money(entry.buy)
    elseif key == "age" then
        -- Read now, as the list itself can be kept for a while. "now"
        -- rather than "just now", which is wider than the column.
        local age = ns.Prices:GetAge(entry.itemID) or entry.age
        text = age and Util.FormatAge(age) or ""
        if text == "just now" then text = "now" end
        color = ns.Prices:IsStale(entry.itemID) and "warn" or "dim"
    end

    cell:SetText(text or "")
    cell:SetTextColor(Theme.Unpack(color))
end

local function UpdateRow(row, entry)
    if row.view ~= state.view then ApplyRowLayout(row) end

    Theme.SetRowName(row.name, entry.name or ("item " .. tostring(entry.itemID)))
    -- A bag row carries its link, so the upgrade arrow judges that very copy.
    Theme.SetItemIcon(row.icon, entry.itemID, entry.link)

    local r, g, b = Util.GetItemQualityColor(entry.itemID)
    if r then
        row.name:SetTextColor(r, g, b)
    else
        row.name:SetTextColor(Theme.Unpack("text"))
    end

    for index, column in ipairs(VIEWS[state.view].columns) do
        FillCell(row.cells[index], column.key, entry)
    end
end

local function ShowBagTooltip(entry)
    if entry.value and entry.sells then
        GameTooltip:AddLine(" ")
        if entry.beatsSale then
            GameTooltip:AddLine(("Disenchanting it is worth %s more than selling it."):format(
                Plain(entry.value - entry.sells)), 0.35, 0.85, 0.45, true)
        else
            GameTooltip:AddLine(("Selling it is worth %s more than disenchanting it."):format(
                Plain(entry.sells - entry.value)), 0.7, 0.7, 0.7, true)
        end
    end

    if entry.sellsAt == "vendor" then
        GameTooltip:AddLine("Its sale price is what a vendor pays.", 0.7, 0.7, 0.7, true)
    end

    GameTooltip:AddLine("Click to pick it, then click Disenchant.", 0.5, 0.5, 0.5)
    GameTooltip:Show()
end

local function ShowRowTooltip(row, entry)
    Widgets.ShowItemTooltip(row, "ANCHOR_LEFT", entry.itemID, entry.name)

    if entry.kind == "bag" then return ShowBagTooltip(entry) end

    GameTooltip:AddLine(" ")

    if entry.route == "auction" then
        GameTooltip:AddLine(("Buy at %s, list it again at %s: %s profit each after the cut."):format(
            Plain(entry.buy), Plain(entry.resell), Plain(entry.gain)), 0.35, 0.85, 0.45, true)
        GameTooltip:AddLine(("Usually sells for %s (middle of %d scans)."):format(
            Plain(entry.usual), entry.scans - 1), 0.85, 0.85, 0.85, true)
        local demand = ns.Demand:TooltipText(entry.demand)
        if demand then GameTooltip:AddLine("Demand: " .. demand, 0.85, 0.85, 0.85, true) end
    elseif entry.route == "vendor" then
        GameTooltip:AddLine(("Buy at %s, sell to any vendor for %s: %s profit each."):format(
            Plain(entry.buy), Plain(entry.vendor), Plain(entry.gain)), 0.35, 0.85, 0.45, true)
    elseif entry.gain > 0 then
        GameTooltip:AddLine(("Buy at %s, disenchant, and sell the materials: about %s profit."):format(
            Plain(entry.buy), Plain(entry.gain)), 0.35, 0.85, 0.45, true)
    else
        GameTooltip:AddLine(("Buying it to disenchant loses about %s."):format(
            Plain(-entry.gain)), 0.85, 0.35, 0.35, true)
    end

    if entry.listed then
        GameTooltip:AddLine(("%d listed."):format(entry.listed), 0.85, 0.85, 0.85, true)
    end

    if entry.route == "disenchant" then
        if entry.canDisenchant == false then
            GameTooltip:AddLine(("Needs Enchanting %d. Your best is %d (%s)."):format(
                entry.needs or 0, entry.enchanterSkill or 0, entry.enchanter or "?"), 0.85, 0.35, 0.35, true)
        elseif entry.canDisenchant == nil then
            GameTooltip:AddLine("None of your characters has Enchanting.", 0.85, 0.35, 0.35, true)
        elseif entry.needs then
            GameTooltip:AddLine(("Needs Enchanting %d."):format(entry.needs), 0.7, 0.7, 0.7, true)
        end
    end

    local others = OthersText(entry)
    if others then GameTooltip:AddLine(others, 0.7, 0.7, 0.7, true) end

    -- Read now, as the AGE column is: the list can be kept for hours, and
    -- the warning it was built with never came on as the scan aged.
    if ns.Prices:IsStale(entry.itemID) then
        GameTooltip:AddLine("Scanned a while ago, so it may have sold.", 0.91, 0.76, 0.35, true)
    end

    GameTooltip:AddLine("Right-click to search the auction house for it.", 0.5, 0.5, 0.5)
    GameTooltip:Show()
end

--------------------------------------------------------------------------------
-- Detail panel
--------------------------------------------------------------------------------

--- Four label and value lines in a frame.
local function SummaryBlock(detail)
    local summary = CreateFrame("Frame", nil, detail)

    local function SummaryRow(index)
        local label = Theme.CreateLabel(summary, "small", "muted")
        label:SetPoint("TOPLEFT", 0, -(index - 1) * 17)

        local value = Theme.CreateLabel(summary, "small", "text", "RIGHT")
        value:SetPoint("TOPRIGHT", 0, -(index - 1) * 17)

        return { label = label, value = value }
    end

    summary.lines = { SummaryRow(1), SummaryRow(2), SummaryRow(3), SummaryRow(4) }
    return summary
end

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

    -- "BREAKS INTO" for a disenchant, "THE FLIP" for the other ways.
    local heading = Theme.CreateHeading(detail, "BREAKS INTO")
    heading:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", -38, -12)
    detail.heading = heading

    detail.outcomeLines = {}

    -- A disenchant: what it breaks into runs down from the heading, and the
    -- sums sit at the bottom, clear of a long list.
    local breaks = SummaryBlock(detail)
    breaks:SetPoint("BOTTOMLEFT", 12, 110)
    breaks:SetPoint("BOTTOMRIGHT", -12, 110)
    breaks:SetHeight(70)

    breaks.verdict = Theme.CreateLabel(detail, "small", "profit")
    breaks.verdict:SetPoint("BOTTOMLEFT", breaks, "TOPLEFT", 0, 6)
    breaks.verdict:SetPoint("BOTTOMRIGHT", breaks, "TOPRIGHT", 0, 6)
    breaks.verdict:SetWordWrap(true)

    breaks.note = Theme.CreateLabel(detail, "tiny", "dim")
    breaks.note:SetPoint("BOTTOMLEFT", 12, 44)
    breaks.note:SetPoint("BOTTOMRIGHT", -12, 44)
    breaks.note:SetWordWrap(true)
    breaks.note:SetJustifyV("BOTTOM")
    breaks.note:SetHeight(60)
    detail.breaks = breaks

    -- A flip to a vendor or back onto the auction house: the sums under the
    -- heading, a bar for how much of the sale is profit, then the words.
    local flip = SummaryBlock(detail)
    flip:SetPoint("TOPLEFT", heading, "BOTTOMLEFT", 0, -8)
    flip:SetPoint("RIGHT", detail, "RIGHT", -12, 0)
    flip:SetHeight(69)

    flip.bar = Theme.CreateBar(detail, DETAIL_WIDTH - 24, 3)
    flip.bar:SetPoint("TOPLEFT", flip, "TOPLEFT", 0, -54)

    flip.verdict = Theme.CreateLabel(detail, "small", "profit")
    flip.verdict:SetPoint("TOPLEFT", flip.bar.track, "BOTTOMLEFT", 0, -10)
    flip.verdict:SetPoint("RIGHT", detail, "RIGHT", -12, 0)
    flip.verdict:SetWordWrap(true)

    -- Under the verdict, as tall as its words. A box of fixed height pinned
    -- to the bottom had room for five lines, and the warning that the scan
    -- is old made six, so the warning itself was the line cut off.
    flip.note = Theme.CreateLabel(detail, "tiny", "dim")
    flip.note:SetPoint("TOPLEFT", flip.verdict, "BOTTOMLEFT", 0, -10)
    flip.note:SetPoint("RIGHT", detail, "RIGHT", -12, 0)
    flip.note:SetWordWrap(true)
    flip.note:SetJustifyV("TOP")
    detail.flip = flip

    local searchButton = Widgets.CreateButton(detail, "Search the auction house", function()
        SearchAuctionHouse(state.selected)
    end, { width = 200, primary = true, height = 24 })
    searchButton:SetPoint("BOTTOMLEFT", 12, 14)
    searchButton.tooltipText = "Sends a search for this item, so it shows in the auction house list. Buying still takes your own click on the game's Buy button."
    detail.searchButton = searchButton

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
    end, { width = 120, primary = true, height = 24 })
    disenchantButton:SetPoint("BOTTOMLEFT", 12, 14)
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
    empty:SetText("Pick a row to see the deal")
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

--- Show one of the two blocks, or neither.
local function ShowBlock(detail, which)
    for _, name in ipairs({ "breaks", "flip" }) do
        local block = detail[name]
        local shown = which == name
        block:SetShown(shown)
        block.verdict:SetShown(shown)
        block.note:SetShown(shown)
        -- rawget: only the flip block has a bar, and a test's stand-in
        -- frame answers any missing field with a function.
        local bar = rawget(block, "bar")
        if type(bar) == "table" then
            bar:SetShown(shown)
            if not shown then bar:Set(nil) end
        end
    end
end

--- Arm the Disenchant button for a bag item, or say why it cannot be.
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

--- Draw what the chances and prices are for one outcome list, under the heading.
local function DrawOutcomes(detail, breakdown)
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

        -- Only the most likely outcome is the value; the rest are a bonus.
        line.name:SetText(("%s%%  %sx %s%s"):format(Util.Round(outcome.chance * 100, 1), count,
            outcome.name or Util.GetItemLabel(outcome.itemID),
            outcome.counted == false and "  (bonus)" or ""))
        Theme.SetItemIcon(line.icon, outcome.itemID)

        if outcome.price then
            line.value:SetText(Money(outcome.price) .. " each")
            line.value:SetTextColor(Theme.Unpack("muted"))
        else
            line.value:SetText("no price")
            line.value:SetTextColor(Theme.Unpack("dim"))
        end

        FitOutcomeLine(line)
        line.frame:Show()
        anchor = line.frame
    end
end

--- The detail panel for an item in the bags.
local function UpdateBagDetail(entry)
    local detail = widgets.detail
    local block = detail.breaks
    local breakdown = entry.breakdown or {}
    local facts = breakdown.facts or {}

    ShowBlock(detail, "breaks")
    detail.heading:SetText("BREAKS INTO")

    detail.subtitle:SetText(("Item level %d %s %s. Needs Enchanting about %d."):format(
        facts.itemLevel or 0, facts.qualityName or "", facts.isWeapon and "weapon" or "armor",
        facts.skill or 0))
    detail.subtitle:SetTextColor(Theme.Unpack("muted"))

    DrawOutcomes(detail, breakdown)

    local lines = block.lines
    if entry.value then
        SetLine(lines[1], "Disenchant value",
            Util.FormatMoney(entry.value) .. (entry.partial and "  or more" or ""),
            entry.beatsSale and "profit" or "text")
    else
        SetLine(lines[1], "Disenchant value", "materials not scanned", "dim")
    end

    if entry.sells then
        SetLine(lines[2], entry.sellsAt == "vendor" and "Vendor pays" or "Sells for",
            Util.FormatMoney(entry.sells), "muted")
    else
        SetLine(lines[2], "Sells for", entry.soulbound and "soulbound, no vendor price" or "no price", "dim")
    end

    SetLine(lines[3], "In your bags", tostring(entry.count or 0), "muted")

    -- A running total that grows with every click.
    local count, worth = Session()
    if count > 0 then
        SetLine(lines[4], "Disenchanted this session", ("%d, worth %s"):format(count,
            Util.FormatMoney(worth, { noColor = true, short = true })), "profit")
    else
        SetLine(lines[4], nil)
    end

    if entry.value and entry.sells then
        if entry.beatsSale then
            block.verdict:SetText(("Disenchanting pays %s more than selling."):format(
                Plain(entry.value - entry.sells)))
            block.verdict:SetTextColor(Theme.Unpack("profit"))
        else
            block.verdict:SetText(("Selling pays %s more than disenchanting."):format(
                Plain(entry.sells - entry.value)))
            block.verdict:SetTextColor(Theme.Unpack("muted"))
        end
    elseif entry.value then
        block.verdict:SetText("Nothing to compare it with: it has no sale price.")
        block.verdict:SetTextColor(Theme.Unpack("muted"))
    else
        block.verdict:SetText("Scan the auction house to price its materials.")
        block.verdict:SetTextColor(Theme.Unpack("warn"))
    end

    local note
    if facts.source == "yours" then
        note = ("Chances come from %s."):format(ns.Disenchant:YoursPhrase(facts))
    else
        note = "Chances come from the Classic table built into the addon until you have done enough disenchants of your own."
    end
    if not entry.soulbound then
        note = note .. " If it is already bound to you, only a vendor will buy it."
    end
    block.note:SetText(note)

    UpdateDisenchantButton(entry)
end

--- The detail panel for an auction house item bought to disenchant.
local function UpdateDisenchantDetail(detail, entry)
    local block = detail.breaks
    local breakdown = entry.breakdown or {}
    local facts = breakdown.facts or {}

    ShowBlock(detail, "breaks")
    detail.heading:SetText("BREAKS INTO")

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

    DrawOutcomes(detail, breakdown)

    local lines = block.lines
    SetLine(lines[1], entry.loneLow and "Buy for (a lone low listing)" or "Buy for",
        Util.FormatMoney(entry.buy), "text")
    SetLine(lines[2], "Disenchant value",
        Util.FormatMoney(entry.value) .. (entry.partial and "  or more" or ""), "text")
    SetLine(lines[3], "After the auction house cut", Util.FormatMoney(entry.net), "muted")
    SetLine(lines[4], "Profit", ("%s  (%s)"):format(Util.FormatMoney(entry.gain), MarginText(entry.margin)),
        entry.gain > 0 and "profit" or "loss")

    if entry.gain > 0 then
        block.verdict:SetText(("Buying one to disenchant makes about %s."):format(Plain(entry.gain)))
        block.verdict:SetTextColor(Theme.Unpack("profit"))
    else
        block.verdict:SetText(("Buying one to disenchant loses about %s."):format(Plain(-entry.gain)))
        block.verdict:SetTextColor(Theme.Unpack("loss"))
    end

    local parts = {}
    parts[#parts + 1] = OthersText(entry)
    if facts.source == "yours" then
        parts[#parts + 1] = ("Chances come from %s."):format(ns.Disenchant:YoursPhrase(facts))
    else
        parts[#parts + 1] = "Chances come from the Classic table built into the addon. It is an average: any one disenchant can give more or less."
    end
    local age = ns.Prices:GetAge(entry.itemID) or entry.age
    parts[#parts + 1] = ("The buy price is the cheapest listing when last scanned (%s)."):format(
        age and Util.FormatAgeAgo(age) or "never")
    if ns.Prices:IsStale(entry.itemID) then parts[#parts + 1] = "That was a while ago, so it may have sold." end
    block.note:SetText(table.concat(parts, " "))
end

--- How many are listed, for the top of a flip's detail.
local function ListedText(entry)
    if entry.listed and entry.listed > 1 then
        return ("%d listed. Only the cheapest is sure to be at this price."):format(entry.listed)
    end
    return "One listed."
end

--- The detail panel for a row bought to list again.
local function UpdateResaleDetail(detail, entry)
    local block = detail.flip

    ShowBlock(detail, "flip")
    detail.heading:SetText("THE FLIP")
    detail.subtitle:SetText(ListedText(entry))
    detail.subtitle:SetTextColor(Theme.Unpack("muted"))

    local lines = block.lines
    SetLine(lines[1], entry.loneLow and "Buy for (lone low)" or "Buy for", Util.FormatMoney(entry.buy), "text")
    SetLine(lines[2], "Usually sells for", Util.FormatMoney(entry.usual), "text")
    SetLine(lines[3], entry.capped and "List again at (next listing)" or "List again at",
        Util.FormatMoney(entry.resell), "text")
    SetLine(lines[4], "Profit each", ("%s  (%s)"):format(Util.FormatMoney(entry.gain), MarginText(entry.margin)),
        "profit")

    block.bar:SetPoint("TOPLEFT", block, "TOPLEFT", 0, -71)
    block.bar:Set(entry.resell > 0 and entry.gain / entry.resell or 0, "profit")

    local cut = math.floor((ns.Config:Get("auctionCut") or 0.05) * 100 + 0.5)
    local paid = entry.depositKnown and ("the %d%% cut and the deposit"):format(cut)
        or ("the %d%% cut"):format(cut)
    block.verdict:SetText(("Buy it, list it again at %s, and keep about %s each after %s."):format(
        Plain(entry.resell), Plain(entry.gain), paid))
    block.verdict:SetTextColor(Theme.Unpack("profit"))

    local parts = { OthersText(entry) }
    parts[#parts + 1] = ("The usual price is the middle of the %d scans before the last one, so the cheap listing does not drag it down."):format(entry.scans - 1)
    local demand = ns.Demand:TooltipText(entry.demand)
    if demand then parts[#parts + 1] = ("Demand: %s."):format(demand) end
    if not entry.depositKnown then
        parts[#parts + 1] = "The deposit is not known until you have listed one, so it is not counted yet."
    end
    parts[#parts + 1] = "Your gold is tied up until it sells."
    local age = ns.Prices:GetAge(entry.itemID) or entry.age
    parts[#parts + 1] = ("Scanned %s."):format(age and Util.FormatAgeAgo(age) or "never")
    if ns.Prices:IsStale(entry.itemID) then parts[#parts + 1] = "That was a while ago, so it may have sold." end
    block.note:SetText(table.concat(parts, " "))
end

--- The detail panel for a row bought to sell to a vendor.
local function UpdateVendorDetail(detail, entry)
    local block = detail.flip

    ShowBlock(detail, "flip")
    detail.heading:SetText("THE FLIP")
    detail.subtitle:SetText(ListedText(entry))
    detail.subtitle:SetTextColor(Theme.Unpack("muted"))

    -- Short enough to stay clear of the price on its right; the longer
    -- "(a lone low listing)" ran over it.
    local lines = block.lines
    SetLine(lines[1], entry.loneLow and "Buy for (lone low)" or "Buy for", Util.FormatMoney(entry.buy), "text")
    SetLine(lines[2], "A vendor pays", Util.FormatMoney(entry.vendor), "text")
    SetLine(lines[3], "Profit each", ("%s  (%s)"):format(Util.FormatMoney(entry.gain), MarginText(entry.margin)),
        "profit")
    SetLine(lines[4], nil)

    block.bar:SetPoint("TOPLEFT", block, "TOPLEFT", 0, -54)
    block.bar:Set(entry.vendor > 0 and entry.gain / entry.vendor or 0, "profit")

    block.verdict:SetText(("Buy it, sell it to any vendor, and keep about %s each. No auction house cut."):format(
        Plain(entry.gain)))
    block.verdict:SetTextColor(Theme.Unpack("profit"))

    -- The scan's age read now, as the AGE column reads it: the list can be
    -- kept for hours, and the age it was built with went on saying "2m ago".
    local age = ns.Prices:GetAge(entry.itemID) or entry.age
    local parts = { OthersText(entry) }
    parts[#parts + 1] = ("The buy price is the cheapest listing from another seller when last scanned (%s). Prices are per item, so a stack pays the same on every one in it."):format(
        age and Util.FormatAgeAgo(age) or "never")
    if ns.Prices:IsStale(entry.itemID) then parts[#parts + 1] = "That was a while ago, so it may have sold." end
    block.note:SetText(table.concat(parts, " "))
end

local function UpdateDetail(entry)
    local detail = widgets.detail
    local shown = entry ~= nil
    local isBag = shown and entry.kind == "bag"

    detail.empty:SetShown(not shown)

    for _, line in ipairs(detail.outcomeLines) do
        line.frame:Hide()
    end

    for _, part in ipairs({ detail.icon, detail.title, detail.subtitle, detail.heading }) do
        part:SetShown(shown)
    end

    detail.searchButton:SetShown(shown and not isBag)

    -- Hiding the button takes the secure button away with it.
    detail.disenchantButton:SetShown(isBag)
    detail.disenchantStatus:SetShown(isBag)

    if not shown then
        ShowBlock(detail, nil)
        return
    end

    detail.title:SetText(entry.name or ("item " .. tostring(entry.itemID)))
    Theme.SetItemIcon(detail.icon, entry.itemID, entry.link)

    if isBag then return UpdateBagDetail(entry) end
    if entry.route == "auction" then return UpdateResaleDetail(detail, entry) end
    if entry.route == "vendor" then return UpdateVendorDetail(detail, entry) end
    return UpdateDisenchantDetail(detail, entry)
end

--------------------------------------------------------------------------------
-- List
--------------------------------------------------------------------------------

-- The last full list and what it was built from. Walking every scanned item
-- is only done again when something it depends on has changed: a redraw for
-- a bag change or an auction event reuses it. At the auction house those
-- redraws come often, and walking thousands of items each time pushed bag
-- items out of the client's memory, so Ready to sell kept losing them.
local built = { key = nil, rows = nil, hidden = 0, pending = 0, thin = 0, disenchant = 0 }

local function BuildKey()
    local skill = ns.Disenchant:GetBestEnchanter()

    return table.concat({
        tostring(ns.Prices and ns.Prices.changes or 0),
        tostring(ns.Prices and ns.Prices:Count() or 0),
        tostring(ns.Disenchant.factsVersion or 0),
        -- Your own disenchants taking over from the built-in table.
        tostring(ns.DisenchantLog and ns.DisenchantLog.version or 0),
        tostring(state.dealsOnly),
        tostring(state.routes.auction), tostring(state.routes.disenchant), tostring(state.routes.vendor),
        tostring(ns.Config:Get("minProfit")),
        tostring(ns.Config:Get("minMarginPercent")),
        tostring(ns.Config:Get("auctionCut")),
        tostring(skill),
        tostring(ns.Scanner and ns.Scanner.isAuctionHouseOpen and true or false),
    }, "|")
end

--- Which of two ways on the same item wins: a disenchant none of your
--- characters can do yet loses to any other way, else the bigger profit.
local function Beats(a, b)
    local aBlocked = a.route == "disenchant" and a.canDisenchant ~= true
    local bBlocked = b.route == "disenchant" and b.canDisenchant ~= true
    if aBlocked ~= bBlocked then return bBlocked end
    return a.gain > b.gain
end

--- Every ticked way's rows, one per item on its best way.
local function MergeRoutes()
    local byItem, order = {}, {}
    local hidden, pending, thin = 0, 0, 0
    local deFound = 0

    local function Take(rows, route, gets)
        for _, row in ipairs(rows or {}) do
            row.route, row.via, row.gets = route, VIA[route], gets(row)
            row.others = nil

            local best = byItem[row.itemID]
            if not best then
                byItem[row.itemID] = row
                order[#order + 1] = row.itemID
            elseif Beats(row, best) then
                row.others = best.others or {}
                best.others = nil
                table.insert(row.others, best)
                byItem[row.itemID] = row
            else
                best.others = best.others or {}
                best.others[#best.others + 1] = row
            end
        end
    end

    if state.routes.disenchant then
        local rows, held, waiting = ns.Disenchant:GetAuctionRows({ profitableOnly = state.dealsOnly })
        hidden, pending, deFound = hidden + (held or 0), math.max(pending, waiting or 0), #(rows or {})
        -- For /bts dedeals: what the tab is showing and when it was built.
        ns.Disenchant.shownRows, ns.Disenchant.shownBuiltAt = rows, Now()
        Take(rows, "disenchant", function(row) return row.value end)
    end

    if state.routes.vendor then
        local rows, held, waiting = ns.VendorFlips:GetAuctionRows({ profitableOnly = state.dealsOnly })
        hidden, pending = hidden + (held or 0), math.max(pending, waiting or 0)
        -- For /bts vendordeals.
        ns.VendorFlips.shownRows, ns.VendorFlips.shownBuiltAt = rows, Now()
        Take(rows, "vendor", function(row) return row.vendor end)
    end

    if state.routes.auction then
        local rows, held, few = ns.VendorFlips:GetResaleRows({ profitableOnly = state.dealsOnly })
        hidden, thin = hidden + (held or 0), few or 0
        Take(rows, "auction", function(row) return row.resell end)
    end

    local rows = {}
    for _, itemID in ipairs(order) do rows[#rows + 1] = byItem[itemID] end

    table.sort(rows, function(a, b)
        if a.gain ~= b.gain then return a.gain > b.gain end
        return a.itemID < b.itemID
    end)

    return rows, hidden, pending, thin, deFound
end

--- Everything in the bags that can be disenchanted. Only a bagful, and
--- facts are cached per item, so this is cheap to build on every redraw.
local function BuildBagRows()
    local rows = ns.Disenchant:GetBagRows({ beatsOnly = state.beatsOnly })
    if state.search == "" then return rows end

    local needle = state.search:lower()
    local filtered = {}

    for _, row in ipairs(rows) do
        if (row.name or ""):lower():find(needle, 1, true) then filtered[#filtered + 1] = row end
    end

    return filtered
end

local function BuildRows()
    if state.view == "bag" then return BuildBagRows() end

    local key = BuildKey()

    if key ~= built.key then
        local rows, hidden, pending, thin, deFound = MergeRoutes()
        built.key, built.rows = key, rows
        built.hidden, built.pending, built.thin, built.disenchant = hidden, pending, thin, deFound
    end

    local rows = built.rows
    state.hidden = built.hidden
    state.pending = built.pending
    state.thin = built.thin

    if state.search == "" and not state.hideTooHigh then return rows end

    local needle = state.search:lower()
    local filtered = {}

    for _, row in ipairs(rows) do
        local matches = needle == "" or (row.name or ""):lower():find(needle, 1, true)
        local canDo = not state.hideTooHigh or row.route ~= "disenchant" or row.canDisenchant == true

        if matches and canDo then filtered[#filtered + 1] = row end
    end

    return filtered
end

local function EmptyText()
    if state.search ~= "" then
        return ("Nothing matching \"%s\"."):format(state.search)
    end

    if state.view == "bag" then
        local count, worth = Session()
        if count > 0 then
            return ("All done! You disenchanted %d item%s this session, worth about %s."):format(
                count, count == 1 and "" or "s", Util.FormatMoney(worth, { noColor = true, short = true }))
                .. (state.beatsOnly and " Untick \"Only where disenchanting pays more\" to see the rest." or "")
        end

        if state.beatsOnly then
            return "Nothing in your bags is worth more disenchanted than sold. Untick \"Only where disenchanting pays more\" to see them all."
        end
        return "Nothing in your bags can be disenchanted."
    end

    if not AnyRoute() then
        return "Tick at least one way to sell in the Sell to menu."
    end

    if (ns.Prices and ns.Prices:Count() or 0) == 0 then
        return "Scan the auction house to find items worth buying."
    end

    -- Items were found, and "Only ones I can disenchant" hid all of them.
    -- Said first: the text below names the other tick box, and unticking
    -- that one showed nothing new.
    local found = built.rows and #built.rows or 0
    if state.hideTooHigh and found > 0 then
        return ("None of your characters can disenchant the %d item%s found yet. Untick \"Only ones I can disenchant\" to see %s."):format(
            found, found == 1 and "" or "s", found == 1 and "it" or "them")
    end

    local text = "Nothing on the auction house is worth buying right now."

    if state.dealsOnly and state.hidden > 0 then
        return text .. (" %d more would make a little, but not enough for your minimums in Settings (%s profit, %d%% margin). Untick \"Only deals over my minimums\" to see them."):format(
            state.hidden,
            Util.FormatMoney(ns.Config:Get("minProfit") or 0, { noColor = true, short = true }),
            ns.Config:Get("minMarginPercent") or 0)
    end

    if state.routes.auction and (state.thin or 0) > 0 then
        text = text .. (" %d more are cheap, but have fewer than %d scans, little demand, or are grey. Scan again over the next days to build up their history.")
            :format(state.thin, ns.VendorFlips.MIN_RESALE_SCANS)
    end

    return text
end

-- Beside the Disenchant button when the bags list has items but none is worth
-- more disenchanted than sold, so none was picked.
local NOTHING_PICKED = "Nothing here is worth more disenchanted than sold. Click one to disenchant it anyway."

--- No item picked in a bags list that has some: the Disenchant button shows
--- unset, and the line beside it says why.
local function ShowNothingPicked()
    local detail = widgets.detail
    local button = detail.disenchantButton

    button:SetShown(true)
    button:SetEnabledState(false)
    button.tooltipText = NOTHING_PICKED
    detail.disenchantStatus:SetText(NOTHING_PICKED)
    detail.disenchantStatus:SetShown(true)

    if ns.Disenchanter.anchor == button then ns.Disenchanter:Disarm() end
end

--- The count line and the picked row, for the bags list.
local function RefreshBags(rows)
    local beats = 0
    for _, row in ipairs(rows) do
        if row.beatsSale then beats = beats + 1 end
    end

    local text = ("%d item%s, %d worth more disenchanted"):format(#rows, #rows == 1 and "" or "s", beats)
    local count, worth = Session()
    if count > 0 then
        text = text .. ("  ·  %d disenchanted this session, worth %s"):format(count,
            Util.FormatMoney(worth, { noColor = true, short = true }))
    end
    widgets.countLabel:SetText(text)

    local before = state.selected
    local fresh
    for _, row in ipairs(rows) do
        if SameRow(row, state.selected) then
            fresh = row
            break
        end
    end

    -- When nothing is picked, the best item worth more disenchanted than sold
    -- is picked for you, so the Disenchant button is ready on it. After a
    -- disenchant the item leaves the list and the next one takes its place
    -- under the same button. One that sells for more is never picked for you,
    -- or clicking on down the list broke things worth more sold; a click on
    -- it still picks it.
    if not fresh then
        for _, row in ipairs(rows) do
            if row.beatsSale then
                fresh = row
                break
            end
        end
    end

    state.selected = fresh
    UpdateDetail(fresh)

    if not fresh and #rows > 0 then ShowNothingPicked() end

    -- The rows were drawn before this pick, so light the picked one now.
    if fresh and not SameRow(fresh, before) then widgets.list:Refresh() end
end

--- The count line for the auction house list, in the first whole wording
--- that fits beside the hint rather than one ending in "...".
local function SetDealsCount(rows)
    local deals, total = 0, 0
    for _, row in ipairs(rows) do
        if row.gain > 0 then
            deals = deals + 1
            total = total + row.gain
        end
    end

    local found
    if deals > 0 then
        local plural = deals == 1 and "" or "s"
        local money = Util.FormatMoney(total, { noColor = true, short = true })
        found = {
            ("%d deal%s, about %s if you buy one of each"):format(deals, plural, money),
            ("%d deal%s, about %s for one of each"):format(deals, plural, money),
            ("%d deal%s"):format(deals, plural),
        }
    elseif #rows > 0 then
        found = { ("%d item%s"):format(#rows, #rows == 1 and "" or "s") }
    end

    -- Items not read yet wait for the auction house to close, so reading
    -- them cannot upset Ready to sell. Say so, or the list looks short.
    local waiting
    if (state.pending or 0) > 0 then
        local when = ns.Scanner and ns.Scanner.isAuctionHouseOpen
            and "read once the auction house is closed" or "reading them now"
        waiting = {
            ("%d more listed items not checked yet, %s"):format(state.pending, when),
            ("%d not checked yet"):format(state.pending),
        }
    elseif state.routes.auction and (state.thin or 0) > 0 then
        waiting = {
            ("%d more held back: few scans or little demand"):format(state.thin),
            ("%d held back"):format(state.thin),
        }
    end

    local texts = { "" }
    if found and waiting then
        local sep = "  ·  "
        texts = {}
        for _, first in ipairs(found) do
            texts[#texts + 1] = first .. sep .. waiting[1]
            texts[#texts + 1] = first .. sep .. waiting[2]
        end
    elseif found or waiting then
        texts = found or waiting
    end

    if Theme.FitText then
        Theme.FitText(widgets.countLabel, texts)
    else
        widgets.countLabel:SetText(texts[1])
    end
end

local function Refresh()
    if not widgets.list then return end

    local rows = BuildRows()
    -- A clicked heading's order over the list's own.
    if widgets.sorter then rows = widgets.sorter:Sort(rows) end
    widgets.list:SetData(rows)

    widgets.emptyLabel:SetShown(#rows == 0)
    if #rows == 0 then widgets.emptyLabel:SetText(EmptyText()) end

    if state.view == "bag" then return RefreshBags(rows) end

    SetDealsCount(rows)

    local fresh
    if state.selected then
        for _, row in ipairs(rows) do
            if SameRow(row, state.selected) then
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

--- Headings, tick boxes and hint for the view being shown.
local function ApplyView()
    local view = VIEWS[state.view]

    local offset = -8
    for index = 1, MAX_COLUMNS do
        local heading = widgets.headings[index]
        local column = view.columns[index]

        heading:ClearAllPoints()

        if column then
            heading:SetText(column.label)
            heading:SetPoint("RIGHT", offset, 0)
            heading:SetWidth(column.width)
            heading:SetJustifyH(column.justify or "RIGHT")
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

    local isBag = state.view == "bag"
    widgets.dealsOnly:SetShown(not isBag)
    widgets.hideTooHigh:SetShown(not isBag and state.routes.disenchant == true)
    widgets.beatsOnly:SetShown(isBag)
    widgets.hint:SetText(view.hint)
end

--- The Sell to box's words: "All" with every way ticked, else their short names.
local function SellToSummary(set)
    local names, all = {}, true
    for _, route in ipairs(ROUTES) do
        if set[route.key] then names[#names + 1] = route.via else all = false end
    end
    if all then return "Sell to: All" end
    if #names == 0 then return "Sell to: none" end
    return "Sell to: " .. table.concat(names, ", ")
end

local function Build(container)
    -- Before any row or heading is laid out: they read these widths.
    if Widgets.FitColumns then
        for _, view in pairs(VIEWS) do Widgets.FitColumns(view.columns) end
    end

    local toolbar = CreateFrame("Frame", nil, container)
    toolbar:SetPoint("TOPLEFT", 8, -8)
    toolbar:SetPoint("TOPRIGHT", -8, -8)
    toolbar:SetHeight(24)

    -- A new search or filter is a different list, so it starts at the top.
    -- The list keeps its place on the redraws that bag and auction events
    -- cause, which left a new search showing its results part way down.
    local function ShowFromTop()
        Refresh()
        if widgets.list then widgets.list:ScrollToTop() end
    end

    -- Option bar: the menu, then search, then the tick boxes, as on every
    -- tab (Ezmode, 2026-10-06). The bags list stays a tick box rather than a
    -- menu (Izbode's request, 2026-10-02): one click between the auction
    -- house deals and disenchanting from the bags.
    local options = {}
    for _, route in ipairs(ROUTES) do
        options[#options + 1] = { text = route.text, value = route.key }
    end

    local sellTo = Widgets.CreateDropdown(toolbar, options, function(set)
        state.routes = set or {}
        state.selected = nil
        ApplyView()
        ShowFromTop()
    end, { width = 140, multi = true, summary = SellToSummary })
    sellTo:SetPoint("LEFT", 0, 0)
    sellTo:SetValue(state.routes)
    sellTo.tooltipText = "Tick the ways you will sell what you buy. Each item shows on the one that pays most."
    widgets.sellTo = sellTo

    local search = Widgets.CreateSearchBox(toolbar, "Search items", function(text)
        state.search = text or ""
        ShowFromTop()
    end)
    search:SetPoint("LEFT", sellTo, "RIGHT", 8, 0)
    search:SetWidth(Widgets.SEARCH_WIDTH)

    local view = Widgets.CreateCheckbox(toolbar, "Items in my bags", function(checked)
        state.view = checked and "bag" or "auction"
        state.selected = nil
        sellTo:SetShown(not checked)
        ApplyView()
        ShowFromTop()
    end, state.view == "bag")
    view:SetPoint("LEFT", search, "RIGHT", 12, 0)
    widgets.view = view

    local dealsOnly = Widgets.CreateCheckbox(toolbar, "Only deals over my minimums", function(checked)
        state.dealsOnly = checked
        ShowFromTop()
    end, state.dealsOnly)
    dealsOnly:SetPoint("LEFT", view, "RIGHT", 12, 0)
    widgets.dealsOnly = dealsOnly

    local hideTooHigh = Widgets.CreateCheckbox(toolbar, "Only ones I can disenchant", function(checked)
        state.hideTooHigh = checked
        ShowFromTop()
    end, state.hideTooHigh)
    hideTooHigh:SetPoint("LEFT", dealsOnly, "RIGHT", 12, 0)
    widgets.hideTooHigh = hideTooHigh

    -- In the bags list: off by default, so everything that can be broken is
    -- there to break, best first.
    local beatsOnly = Widgets.CreateCheckbox(toolbar, "Only where disenchanting pays more", function(checked)
        state.beatsOnly = checked
        Refresh()
    end, state.beatsOnly)
    beatsOnly:SetPoint("LEFT", view, "RIGHT", 12, 0)
    widgets.beatsOnly = beatsOnly

    -- Column headings
    local headings = CreateFrame("Frame", nil, container)
    headings:SetPoint("TOPLEFT", toolbar, "BOTTOMLEFT", 0, -8)
    headings:SetPoint("TOPRIGHT", toolbar, "BOTTOMRIGHT", -DETAIL_WIDTH - 8, -8)
    headings:SetHeight(16)

    local nameHeading = Theme.CreateLabel(headings, "tiny", "muted")
    nameHeading:SetPoint("LEFT", 8 + ICON_GUTTER, 0)
    nameHeading:SetText("ITEM")

    widgets.headings = {}
    for index = 1, MAX_COLUMNS do
        widgets.headings[index] = Theme.CreateLabel(headings, "tiny", "muted", "RIGHT")
    end

    -- Click a heading to sort by it. The headings change with the view, so
    -- each one reads whatever column the view puts there.
    local FIELDS = {
        difference = function(row) return row.value and row.sells and (row.value - row.sells) or nil end,
        via = function(row) return row.kind == "bag" and BagVia(row) or row.via end,
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
            state.selected = entry
            UpdateDetail(entry)

            if mouseButton == "RightButton" and entry.kind ~= "bag" then SearchAuctionHouse(entry) end
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
    widgets.hint = hint

    -- The count line grows a long "not checked yet" note while items load,
    -- and ran under this hint. It stops short of it now, and SetDealsCount
    -- picks a wording that fits.
    countLabel:SetPoint("RIGHT", hint, "LEFT", -12, 0)
    countLabel:SetJustifyH("LEFT")
    countLabel:SetWordWrap(false)

    local detail = BuildDetail(container)
    detail:SetPoint("TOPRIGHT", container, "TOPRIGHT", -8, -40)
    detail:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", -8, 8)
    widgets.detail = detail

    ApplyView()
    UpdateDetail(nil)

    -- Scanned items the client has not cached are left out until it has
    -- them, and are asked for a few dozen a second. Redraw as they arrive,
    -- coalescing a burst into one pass.
    local redrawQueued = false

    ns.RegisterEvent(UI, "GET_ITEM_INFO_RECEIVED", function(_, _, itemID)
        if redrawQueued or not widgets.list:IsVisible() then return end

        -- Only for items this tab asked for, not every item any window loads.
        if itemID and not ns.Disenchant:WasRequested(itemID) then return end

        redrawQueued = true
        C_Timer.After(1, function()
            redrawQueued = false
            -- Not once the player has moved to another tab. Redrawn hidden,
            -- this tab took the Disenchant button from the Profit tab on
            -- screen and aimed it at its own item. It redraws when shown.
            if widgets.list:IsVisible() then Refresh() end
        end)
    end)
    -- Items new to the tab wait while the auction house is open. Read them
    -- as soon as it closes rather than whenever something next redraws.
    ns.RegisterEvent(UI, "AUCTION_HOUSE_CLOSED", function()
        if not widgets.list:IsVisible() then return end
        C_Timer.After(0.5, function()
            if widgets.list:IsVisible() then Refresh() end
        end)
    end)
end

UI:RegisterTab({
    key = "deals",
    text = "Deals",
    order = 1.8,
    build = Build,
    refresh = Refresh,
})
