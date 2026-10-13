-- Blackthornes Tradeskills -- UI/Tab_Disenchanting.lua
-- Items on the auction house worth buying to disenchant.
--
-- Every weapon or piece of armour someone else has listed, priced at their
-- cheapest listing from your last scan, against what it breaks into. Profit
-- is the disenchant value less the auction house cut on selling the
-- materials, less the buy price. The numbers come from Logic/Disenchant.lua,
-- the same ones the Profit tab's DISENCHANT column shows.
--
-- For a while (2026-10-07) this tab was folded into Deals. It came back on
-- its own at the owner's ask (2026-10-08): Deals sells to the auction house
-- or a vendor, and disenchanting lives here.
--
-- The addon cannot buy for you: the game wants a real click on its own Buy
-- button for every purchase. What it can do is send the search, so the item
-- is in the auction house list ready to click.
--
-- The second view lists what you carry that can be disenchanted, against what
-- it would sell for, with a Disenchant button. That button is the same secure
-- one the Profit tab and the queue use (UI/Disenchanter.lua): one disenchant
-- per click.
--
-- Items bought on the auction house to disenchant (Logic/DisenchantBuys.lua,
-- 2026-10-11) head the bags list, tagged, and are picked first, so clicking
-- on down the Disenchant button breaks them before anything else. A buy is
-- marked when it follows a search sent from here; a right-click on a bags
-- row marks or unmarks it by hand.

local _, ns = ...
local L = ns.L or setmetatable({ Format = string.format }, { __index = function(_, key) return key end })

local Theme = ns.Theme
local Widgets = ns.Widgets
local Util = ns.Util

local UI = ns.UI

local ROW_HEIGHT = 22
local DETAIL_WIDTH = 300
local ICON_GUTTER = 20

-- Columns per view, laid out right to left. Money sits to the right, so its
-- coins line up; the rest is centred under its heading. `width` is the least
-- each gets: Widgets.FitColumns widens it to fit the heading and an amount.
local VIEWS = {
    auction = {
        columns = {
            { key = "gain",   label = L["PROFIT"],     width = 66, money = true },
            -- The profit an hour of disenchanting casts (asked 2026-10-09).
            { key = "perHour", label = L["GOLD/HR"],   width = 70, money = true },
            { key = "margin", label = L["MARGIN"],     width = 50, justify = "CENTER" },
            { key = "value",  label = L["DISENCHANT"], width = 70, money = true },
            { key = "buy",    label = L["BUY"],        width = 66, money = true },
            { key = "skill",  label = L["SKILL"],      width = 40, justify = "CENTER" },
            { key = "age",    label = L["AGE"],        width = 44, justify = "CENTER" },
        },
        hint = L["Right-click an item to search the auction house for it"],
    },
    bag = {
        columns = {
            { key = "difference", label = L["DIFFERENCE"], width = 74, money = true },
            -- What disenchanting these makes an hour, at the DISENCHANT value.
            { key = "perHour",    label = L["GOLD/HR"],    width = 70, money = true },
            { key = "value",      label = L["DISENCHANT"], width = 70, money = true },
            { key = "sells",      label = L["SELLS"],      width = 70, money = true },
            { key = "count",      label = L["HAVE"],       width = 40, justify = "CENTER" },
        },
        hint = L["Pick an item, then click Disenchant. Right-click to mark it bought to disenchant"],
    },
}

local MAX_COLUMNS = 7

-- Any column but the item's name can be hidden, each view on its own
-- (UI/Columns.lua).
local LIST_IDS = { auction = "disenchant", bag = "disenchantbags" }
ns.Columns:Register("disenchant", L["Disenchanting: auction house"], VIEWS.auction.columns)
ns.Columns:Register("disenchantbags", L["Disenchanting: my bags"], VIEWS.bag.columns)

local state = {
    view = "auction",
    search = "",
    dealsOnly = true,
    hideTooHigh = false,
    beatsOnly = false,
    selected = nil,
    hidden = 0,
}

local widgets = {}

local shownColumns = {}

--- The view's columns that show, kept until the choice changes: every row
--- asks.
local function ViewColumns()
    local kept = shownColumns[state.view]
    if not kept or kept.version ~= ns.Columns.version then
        kept = { version = ns.Columns.version,
            columns = ns.Columns:Visible(LIST_IDS[state.view], VIEWS[state.view].columns) }
        shownColumns[state.view] = kept
    end
    return kept.columns
end

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function Money(value)
    return Util.FormatMoney(value, { short = true })
end

--- The item's rarity in words, as players read it.
local function QualityWord(name)
    local words = ns.Disenchant and ns.Disenchant.QUALITY_WORDS
    return words and name and words[name] or name or ""
end

local function MarginText(margin)
    return ("%d%%"):format(math.floor((margin or 0) * 100))
end

--- The time now, or nil without a clock (a test's).
local function Now()
    return type(time) == "function" and time() or nil
end

--- The row's rarity, from the item facts kept in the saved data, or nil.
local function KnownQuality(entry)
    local facts = entry.breakdown and entry.breakdown.facts
    if facts and facts.quality then return facts.quality end
    local known = ns.Disenchant and ns.Disenchant.GetItemFacts and ns.Disenchant:GetItemFacts(entry.itemID)
    return known and known.quality
end

--- Gold an hour of disenchanting casts: a bought item's profit, or what a
--- carried one breaks into. Nil until a Disenchant cast's length is known.
local function PerHour(entry)
    local CraftTime = ns.CraftTime
    if not CraftTime then return nil end
    local seconds = CraftTime:GetCast(CraftTime.DISENCHANT_SPELL)
    local amount = entry.kind == "bag" and entry.value or entry.gain
    return CraftTime.PerHour(amount, seconds)
end

-- The tag on a bags row bought to disenchant.
local BOUGHT_TAG = L["  |cffb98cff(bought to DE)|r"]

--- Mark or unmark a bags row as bought to disenchant (its right-click).
local function ToggleBought(entry)
    local buys = ns.DisenchantBuys
    if not (buys and entry and entry.itemID) then return end
    if buys:Count(entry.itemID) > 0 then
        buys:Unmark(entry.itemID)
        ns.Print(L.Format("%s is no longer marked bought to disenchant.", Util.GetItemLabel(entry.itemID)))
    else
        buys:Mark(entry.itemID, entry.count or 1)
        ns.Print(L.Format("marked %d %s bought to disenchant.", entry.count or 1, Util.GetItemLabel(entry.itemID)))
    end
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

--- Send a search for this item, so it shows in the auction house list ready
--- to buy. Your own click on the game's Buy button still does the buying.
local function SearchAuctionHouse(entry)
    if not entry then return end

    local scanner = ns.Scanner
    if not scanner or not scanner.isAuctionHouseOpen then
        ns.Print(L["Open the auction house first, then search again."])
        return
    end

    if scanner.isScanning then
        ns.Print(L["A scan is running. Search again once it finishes."])
        return
    end

    -- The same search as the rest of the addon's item clicks: its own slot
    -- in the queue, at click priority. The scan's slot was shared, so this
    -- could replace a waiting scan (or a scan could drop this search).
    if not ns.UI:SearchAuctionHouse(entry.itemID) then return end

    -- What is bought of it now is marked to disenchant.
    if ns.DisenchantBuys then ns.DisenchantBuys:Intend(entry.itemID) end

    ns.Print(L.Format("Searching the auction house for %s. Buy it in the auction house window at %s or less, and it is marked to disenchant. If the list there does not change, type the name into its search box.",
        Util.GetItemLabel(entry.itemID), Util.FormatMoney(entry.buy, { noColor = true })))
end

--------------------------------------------------------------------------------
-- Rows
--------------------------------------------------------------------------------

local function ApplyRowLayout(row)
    local columns = ViewColumns()
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
    row.columnsVersion = ns.Columns.version
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
    elseif key == "perHour" then
        local perHour = PerHour(entry)
        if perHour then
            cell:SetText(Money(perHour))
            cell:SetTextColor(Theme.ProfitColor(perHour))
        else
            cell:SetText(entry.kind == "bag" and not entry.value and "" or "?")
            cell:SetTextColor(Theme.Unpack("dim"))
        end
        return
    elseif key == "margin" then
        cell:SetText(MarginText(entry.margin))
        cell:SetTextColor(Theme.ProfitColor(entry.gain))
        return
    elseif key == "value" then
        if entry.value then
            text = Money(entry.value) .. (entry.partial and "+" or "")
            color = entry.kind == "bag" and entry.beatsSale and "profit" or "text"
        else
            text, color = L["no price"], "dim"
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
            text, color = L["soulbound"], "dim"
        else
            text, color = L["no price"], "dim"
        end
    elseif key == "count" then
        text = tostring(entry.count or 0)
    elseif key == "buy" then
        text = Money(entry.buy)
    elseif key == "skill" then
        text = entry.needs and tostring(entry.needs) or ""
        -- Red when none of your characters can break it yet.
        color = entry.canDisenchant == false and "loss" or "dim"
    elseif key == "age" then
        -- Read now, as the list itself can be kept for a while.
        local age = ns.Prices:GetAge(entry.itemID) or entry.age
        text = age and Util.FormatAge(age) or ""
        color = ns.Prices:IsStale(entry.itemID) and "warn" or "dim"
    end

    cell:SetText(text or "")
    cell:SetTextColor(Theme.Unpack(color))
end

local function UpdateRow(row, entry)
    if row.view ~= state.view or row.columnsVersion ~= ns.Columns.version then ApplyRowLayout(row) end

    Theme.SetRowName(row.name, (entry.name or L.Format("item %s", tostring(entry.itemID)))
        .. (entry.bought and BOUGHT_TAG or ""))
    -- A bag row carries its link, so the upgrade arrow judges that very copy.
    Theme.SetItemIcon(row.icon, entry.itemID, entry.link)

    -- Coloured by rarity from the facts kept in the saved data: most rows
    -- are items the client's cache no longer holds, which drew white.
    local r, g, b = Util.GetItemQualityColor(entry.itemID, KnownQuality(entry))
    if r then
        row.name:SetTextColor(r, g, b)
    else
        row.name:SetTextColor(Theme.Unpack("text"))
    end

    for index, column in ipairs(ViewColumns()) do
        FillCell(row.cells[index], column.key, entry)
    end
end

--- How long a disenchant takes and what that makes an hour.
local function AddPerHourLine(entry)
    local CraftTime = ns.CraftTime
    if not CraftTime then return end
    local seconds = CraftTime:GetCast(CraftTime.DISENCHANT_SPELL)
    if not seconds then
        GameTooltip:AddLine(L["Disenchant once and its cast time is kept for gold per hour."], 0.5, 0.5, 0.5, true)
        return
    end
    local perHour = PerHour(entry)
    if perHour then
        GameTooltip:AddLine(L.Format("About %s an hour, at %s a disenchant.",
            Util.FormatMoney(perHour, { noColor = true, short = true }), CraftTime.Format(seconds)),
            0.7, 0.7, 0.7, true)
    end
end

local function ShowBagTooltip(entry)
    if entry.value and entry.sells then
        GameTooltip:AddLine(" ")
        if entry.beatsSale then
            GameTooltip:AddLine(L.Format("Disenchanting it is worth %s more than selling it.",
                Util.FormatMoney(entry.value - entry.sells, { noColor = true })), 0.35, 0.85, 0.45, true)
        else
            GameTooltip:AddLine(L.Format("Selling it is worth %s more than disenchanting it.",
                Util.FormatMoney(entry.sells - entry.value, { noColor = true })), 0.7, 0.7, 0.7, true)
        end
    end

    if entry.sellsAt == "vendor" then
        GameTooltip:AddLine(L["Its sale price is what a vendor pays."], 0.7, 0.7, 0.7, true)
    end

    AddPerHourLine(entry)

    if entry.bought then
        GameTooltip:AddLine(L.Format("%d bought on the auction house to disenchant.", entry.bought),
            0.73, 0.55, 1, true)
    end

    GameTooltip:AddLine(L["Click to pick it, then click Disenchant."], 0.5, 0.5, 0.5)
    GameTooltip:AddLine(entry.bought and L["Right-click to unmark it."] or L["Right-click to mark it bought to disenchant."],
        0.5, 0.5, 0.5)
    GameTooltip:Show()
end

local function ShowRowTooltip(row, entry)
    Widgets.ShowItemTooltip(row, "ANCHOR_LEFT", entry.itemID, entry.name)

    if entry.kind == "bag" then return ShowBagTooltip(entry) end

    GameTooltip:AddLine(" ")
    if entry.gain > 0 then
        GameTooltip:AddLine(L.Format("Buy at %s, disenchant, and sell the materials: about %s profit.",
            Util.FormatMoney(entry.buy, { noColor = true }),
            Util.FormatMoney(entry.gain, { noColor = true })), 0.35, 0.85, 0.45, true)
    else
        GameTooltip:AddLine(L.Format("Buying it to disenchant loses about %s.",
            Util.FormatMoney(-entry.gain, { noColor = true })), 0.85, 0.35, 0.35, true)
    end

    if entry.canDisenchant == false then
        GameTooltip:AddLine(L.Format("Needs Enchanting %d. Your best is %d (%s).",
            entry.needs or 0, entry.enchanterSkill or 0, entry.enchanter or "?"), 0.85, 0.35, 0.35, true)
    elseif entry.canDisenchant == nil then
        GameTooltip:AddLine(L["None of your characters has Enchanting."], 0.85, 0.35, 0.35, true)
    end

    if entry.stale then
        GameTooltip:AddLine(L["Scanned a while ago, so it may have sold."], 0.91, 0.76, 0.35, true)
    end

    AddPerHourLine(entry)

    GameTooltip:AddLine(L["Right-click to search the auction house for it. What you buy then is marked to disenchant."],
        0.5, 0.5, 0.5, true)
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
    if Widgets.ItemHotspot then Widgets.ItemHotspot(icon) end

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

    local heading = Theme.CreateHeading(detail, L["BREAKS INTO"])
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

    local searchButton = Widgets.CreateButton(detail, L["Search the auction house"], function()
        SearchAuctionHouse(state.selected)
    end, { width = 180, primary = true, height = 24 })
    searchButton:SetPoint("BOTTOMLEFT", 12, 14)
    searchButton.tooltipText = L["Sends a search for this item, so it shows in the auction house list. Buying still takes your own click on the game's Buy button."]
    detail.searchButton = searchButton

    -- Disenchant, for an item in the bags. The click itself is taken by the
    -- secure button UI/Disenchanter.lua lays over this one; this handler
    -- only runs when that button is not there, so it says why.
    local disenchantButton = Widgets.CreateButton(detail, L["Disenchant"], function()
        local entry = state.selected
        local check = ns.Disenchanter:Check(entry and entry.itemID)

        if not check.ok then
            ns.Print(check.why)
        else
            ns.Warn(L["that click missed the Disenchant button. Click it again; if it misses twice, type /bts disenchant and send the lines it prints."])
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
    empty:SetText(L["Pick a row to see what it breaks into"])
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

--- Arm the Disenchant button for a bag item, or say why it cannot be.
local function UpdateDisenchantButton(entry)
    local detail = widgets.detail
    local button = detail.disenchantButton
    local disenchanter = ns.Disenchanter

    local check = disenchanter:Check(entry and entry.itemID)

    button:SetEnabledState(check.ok)
    button.tooltipText = check.ok
        and L.Format("Disenchant one %s from your bags.", entry.name or L["item"]) or check.why
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
            if Widgets.ItemHotspot then Widgets.ItemHotspot(icon, frame) end

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
            outcome.counted == false and L["  (bonus)"] or ""))
        Theme.SetItemIcon(line.icon, outcome.itemID)

        if outcome.price then
            line.value:SetText(L.Format("%s each", Money(outcome.price)))
            line.value:SetTextColor(Theme.Unpack("muted"))
        else
            line.value:SetText(L["no price"])
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
    local breakdown = entry.breakdown or {}
    local facts = breakdown.facts or {}

    detail.subtitle:SetText(L.Format(facts.isWeapon and L["Item level %d %s weapon. Needs Enchanting about %d."]
            or L["Item level %d %s armor. Needs Enchanting about %d."],
        facts.itemLevel or 0, QualityWord(facts.qualityName), facts.skill or 0))
    detail.subtitle:SetTextColor(Theme.Unpack("muted"))

    DrawOutcomes(detail, breakdown)

    local lines = detail.lines
    if entry.value then
        SetLine(lines[1], L["Disenchant value"],
            entry.partial and L.Format("%s  or more", Util.FormatMoney(entry.value)) or Util.FormatMoney(entry.value),
            entry.beatsSale and "profit" or "text")
    else
        SetLine(lines[1], L["Disenchant value"], L["materials not scanned"], "dim")
    end

    if entry.sells then
        SetLine(lines[2], entry.sellsAt == "vendor" and L["Vendor pays"] or L["Sells for"],
            Util.FormatMoney(entry.sells), "muted")
    else
        SetLine(lines[2], L["Sells for"], entry.soulbound and L["soulbound, no vendor price"] or L["no price"], "dim")
    end

    if entry.bought then
        SetLine(lines[3], L["In your bags"], L.Format("%d, %d bought to disenchant", entry.count or 0, entry.bought), "muted")
    else
        SetLine(lines[3], L["In your bags"], tostring(entry.count or 0), "muted")
    end

    -- A running total that grows with every click.
    local count, worth = Session()
    if count > 0 then
        SetLine(lines[4], L["Disenchanted this session"], L.Format("%d, worth %s", count,
            Util.FormatMoney(worth, { noColor = true, short = true })), "profit")
    else
        SetLine(lines[4], nil)
    end

    if entry.bought then
        detail.verdict:SetText(L["You bought it to disenchant. Right-click its row to unmark it."])
        detail.verdict:SetTextColor(0.73, 0.55, 1)
    elseif entry.value and entry.sells then
        if entry.beatsSale then
            detail.verdict:SetText(L.Format("Disenchanting pays %s more than selling.",
                Util.FormatMoney(entry.value - entry.sells, { noColor = true })))
            detail.verdict:SetTextColor(Theme.Unpack("profit"))
        else
            detail.verdict:SetText(L.Format("Selling pays %s more than disenchanting.",
                Util.FormatMoney(entry.sells - entry.value, { noColor = true })))
            detail.verdict:SetTextColor(Theme.Unpack("muted"))
        end
    elseif entry.value then
        detail.verdict:SetText(L["Nothing to compare it with: it has no sale price."])
        detail.verdict:SetTextColor(Theme.Unpack("muted"))
    else
        detail.verdict:SetText(L["Scan the auction house to price its materials."])
        detail.verdict:SetTextColor(Theme.Unpack("warn"))
    end

    local note
    if facts.source == "yours" then
        note = L.Format("Chances come from %s.", ns.Disenchant:YoursPhrase(facts))
    else
        note = L["Chances come from the Classic table built into the addon until you have done enough disenchants of your own."]
    end
    if not entry.soulbound then
        note = note .. L[" If it is already bound to you, only a vendor will buy it."]
    end
    detail.note:SetText(note)

    UpdateDisenchantButton(entry)
end

local function UpdateDetail(entry)
    local detail = widgets.detail
    local shown = entry ~= nil
    local isBag = shown and entry.kind == "bag"

    detail.empty:SetShown(not shown)

    for _, line in ipairs(detail.outcomeLines) do
        line.frame:Hide()
    end

    for _, part in ipairs({ detail.icon, detail.title, detail.subtitle, detail.heading,
                            detail.summary, detail.verdict, detail.note }) do
        part:SetShown(shown)
    end

    detail.searchButton:SetShown(shown and not isBag)

    -- Hiding the button takes the secure button away with it.
    detail.disenchantButton:SetShown(isBag)
    detail.disenchantStatus:SetShown(isBag)

    if not shown then return end

    detail.title:SetText(entry.name or L.Format("item %s", tostring(entry.itemID)))
    Theme.SetItemIcon(detail.icon, entry.itemID, entry.link)

    if isBag then return UpdateBagDetail(entry) end

    local breakdown = entry.breakdown or {}
    local facts = breakdown.facts or {}

    local who
    if entry.canDisenchant == nil then
        who = L["None of your characters has Enchanting."]
    else
        who = L.Format("Your best is %d (%s).", entry.enchanterSkill or 0, entry.enchanter or "?")
    end

    detail.subtitle:SetText(L.Format(facts.isWeapon and L["Item level %d %s weapon. Needs Enchanting about %d. %s"]
            or L["Item level %d %s armor. Needs Enchanting about %d. %s"],
        facts.itemLevel or 0, QualityWord(facts.qualityName), facts.skill or 0, who))
    detail.subtitle:SetTextColor(Theme.Unpack(entry.canDisenchant == true and "muted" or "loss"))

    DrawOutcomes(detail, breakdown)

    local lines = detail.lines
    SetLine(lines[1], entry.loneLow and L["Buy for (a lone low listing)"] or L["Buy for"],
        Util.FormatMoney(entry.buy), "text")
    SetLine(lines[2], L["Disenchant value"],
        entry.partial and L.Format("%s  or more", Util.FormatMoney(entry.value)) or Util.FormatMoney(entry.value), "text")
    SetLine(lines[3], L["After the auction house cut"], Util.FormatMoney(entry.net), "muted")
    SetLine(lines[4], L["Profit"], ("%s  (%s)"):format(Util.FormatMoney(entry.gain), MarginText(entry.margin)),
        entry.gain > 0 and "profit" or "loss")

    if entry.gain > 0 then
        detail.verdict:SetText(L.Format("Buying one to disenchant makes about %s.",
            Util.FormatMoney(entry.gain, { noColor = true })))
        detail.verdict:SetTextColor(Theme.Unpack("profit"))
    else
        detail.verdict:SetText(L.Format("Buying one to disenchant loses about %s.",
            Util.FormatMoney(-entry.gain, { noColor = true })))
        detail.verdict:SetTextColor(Theme.Unpack("loss"))
    end

    local note
    if facts.source == "yours" then
        note = L.Format("Chances come from %s.", ns.Disenchant:YoursPhrase(facts))
    else
        note = L["Chances come from the Classic table built into the addon. It is an average: any one disenchant can give more or less."]
    end
    note = note .. L.Format(" The buy price is the cheapest listing when last scanned (%s).",
        entry.age and Util.FormatAgeAgo(entry.age) or L["never"])
    if entry.stale then note = note .. L[" That was a while ago, so it may have sold."] end
    detail.note:SetText(note)
end

--------------------------------------------------------------------------------
-- List
--------------------------------------------------------------------------------

-- The last full list and what it was built from. Walking every scanned item
-- is only done again when something it depends on has changed: a redraw for
-- a bag change or an auction event reuses it. At the auction house those
-- redraws come often, and walking thousands of items each time pushed bag
-- items out of the client's memory, so Ready to sell kept losing them.
--
-- A price that moved for a few items (a buy, a search that found none, a
-- price read from a search) redoes only their rows (PatchAuctionRows), so
-- the list never walks every item for one listing.
local built = { key = nil, rows = nil, hidden = 0, pending = 0, places = nil, changes = nil }

local function BuildKey()
    local skill = ns.Disenchant:GetBestEnchanter()

    return table.concat({
        tostring(ns.Prices and ns.Prices:Count() or 0),
        tostring(ns.Prices and ns.Prices.GetLastScan and ns.Prices:GetLastScan() or 0),
        tostring(ns.Disenchant.factsVersion or 0),
        -- Your own disenchants taking over from the built-in table.
        tostring(ns.DisenchantLog and ns.DisenchantLog.version or 0),
        tostring(state.dealsOnly),
        tostring(ns.Config:Get("minProfit")),
        tostring(ns.Config:Get("minMarginPercent")),
        tostring(ns.Config:Get("auctionCut")),
        tostring(skill),
        tostring(ns.Scanner and ns.Scanner.isAuctionHouseOpen and true or false),
    }, "|")
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
    local changes = ns.Prices and ns.Prices.changes or 0
    local opts = { profitableOnly = state.dealsOnly }

    local patched = false
    if key == built.key and changes ~= built.changes and built.places then
        local items = ns.Prices.TouchedSince and ns.Prices:TouchedSince(built.changes)
        patched = items ~= nil and ns.Disenchant.PatchAuctionRows ~= nil
            and ns.Disenchant:PatchAuctionRows(built, items, opts)
        if patched then built.changes = changes end
    end

    if not patched and (key ~= built.key or changes ~= built.changes) then
        local rows, hidden, pending, places = ns.Disenchant:GetAuctionRows(opts)
        built.key, built.rows, built.hidden, built.pending = key, rows, hidden or 0, pending or 0
        built.places, built.changes = places, changes

        -- For /bts dedeals: what the tab is showing and when it was built.
        ns.Disenchant.shownRows, ns.Disenchant.shownBuiltAt = rows, Now()
    end

    local rows = built.rows
    state.hidden = built.hidden
    state.pending = built.pending

    if state.search == "" and not state.hideTooHigh then return rows end

    local needle = state.search:lower()
    local filtered = {}

    for _, row in ipairs(rows) do
        local matches = needle == "" or (row.name or ""):lower():find(needle, 1, true)
        local canDo = not state.hideTooHigh or row.canDisenchant == true

        if matches and canDo then filtered[#filtered + 1] = row end
    end

    return filtered
end

local function EmptyText()
    if state.search ~= "" then
        return L.Format("Nothing matching \"%s\".", state.search)
    end

    if state.view == "bag" then
        local count, worth = Session()
        if count > 0 then
            local money = Util.FormatMoney(worth, { noColor = true, short = true })
            return (count == 1 and L.Format("Done. You disenchanted %d item this session, worth about %s.", count, money)
                or L.Format("Done. You disenchanted %d items this session, worth about %s.", count, money))
                .. (state.beatsOnly and L[" Untick \"Only where disenchanting pays more\" to see the rest."] or "")
        end

        if state.beatsOnly then
            return L["Nothing in your bags is worth more disenchanted than sold. Untick \"Only where disenchanting pays more\" to see them all."]
        end
        return L["Nothing in your bags can be disenchanted."]
    end

    if (ns.Prices and ns.Prices:Count() or 0) == 0 then
        return L["Scan the auction house to find items worth buying to disenchant."]
    end

    -- Items were found, and "Only ones I can disenchant" hid all of them.
    -- Said first: the text below names the other tick box, and unticking
    -- that one showed nothing new.
    local found = built.rows and #built.rows or 0
    if state.hideTooHigh and found > 0 then
        if found == 1 then
            return L.Format("None of your characters can disenchant the %d item found yet. Untick \"Only ones I can disenchant\" to see it.", found)
        end
        return L.Format("None of your characters can disenchant the %d items found yet. Untick \"Only ones I can disenchant\" to see them.", found)
    end

    if state.dealsOnly then
        local text = L["Nothing on the auction house is worth buying to disenchant right now."]

        if state.hidden > 0 then
            text = text .. L.Format(" %d more would make a profit, but less than your minimums in Settings (%s profit, %d%% margin).",
                state.hidden,
                Util.FormatMoney(ns.Config:Get("minProfit") or 0, { noColor = true, short = true }),
                ns.Config:Get("minMarginPercent") or 0)
        end

        return text .. L[" Untick \"Only deals over my minimums\" to see them all."]
    end

    if state.hideTooHigh then
        return L["Nothing listed that your enchanters can disenchant yet."]
    end

    return L["No weapons or armor from other sellers in your last scan."]
end

-- Beside the Disenchant button when the bags list has items but none is worth
-- more disenchanted than sold, so none was picked.
local NOTHING_PICKED = L["Nothing here is worth more disenchanted than sold. Click one to disenchant it anyway."]

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
    local beats, bought = 0, 0
    for _, row in ipairs(rows) do
        if row.beatsSale then beats = beats + 1 end
        bought = bought + (row.bought or 0)
    end

    local text = #rows == 1 and L.Format("%d item, %d worth more disenchanted", #rows, beats)
        or L.Format("%d items, %d worth more disenchanted", #rows, beats)
    if bought > 0 then text = text .. L.Format("  ·  %d bought to disenchant", bought) end
    local count, worth = Session()
    if count > 0 then
        text = text .. L.Format("  ·  %d disenchanted this session, worth %s", count,
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
    -- What was bought to disenchant is picked first, whatever it sells for.
    if not fresh then
        for _, row in ipairs(rows) do
            if row.bought then
                fresh = row
                break
            end
        end
    end
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

local function Refresh()
    if not widgets.list then return end

    local rows = BuildRows()
    -- A clicked heading's order over the list's own.
    if widgets.sorter then rows = widgets.sorter:Sort(rows) end
    widgets.list:SetData(rows)

    widgets.emptyLabel:SetShown(#rows == 0)
    if #rows == 0 then widgets.emptyLabel:SetText(EmptyText()) end

    if state.view == "bag" then return RefreshBags(rows) end

    local deals, total = 0, 0
    for _, row in ipairs(rows) do
        if row.gain > 0 then
            deals = deals + 1
            total = total + row.gain
        end
    end

    if deals > 0 then
        local money = Util.FormatMoney(total, { noColor = true, short = true })
        widgets.countLabel:SetText(deals == 1 and L.Format("%d deal, about %s if you buy them all", deals, money)
            or L.Format("%d deals, about %s if you buy them all", deals, money))
    else
        widgets.countLabel:SetText(#rows == 1 and L.Format("%d item", #rows) or L.Format("%d items", #rows))
    end

    -- Items not read yet wait for the auction house to close, so reading
    -- them cannot upset Ready to sell. Say so, or the list looks short.
    if (state.pending or 0) > 0 then
        local waiting = ns.Scanner and ns.Scanner.isAuctionHouseOpen
            and L["they are read once the auction house is closed"]
            or L["reading them now"]
        widgets.countLabel:SetText(L.Format("%s  ·  %d more listed items not checked yet, %s",
            widgets.countLabel:GetText() or "", state.pending, waiting))
    end

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
        local column = ViewColumns()[index]

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
    widgets.hideTooHigh:SetShown(not isBag)
    widgets.beatsOnly:SetShown(isBag)
    widgets.hint:SetText(view.hint)
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

    -- Search first, then the tick boxes, as on every tab
    -- (2026-10-06). The view stays a tick box rather than a menu (a player's
    -- request, 2026-10-02): one click between the auction house deals and
    -- disenchanting from the bags.
    local search = Widgets.CreateSearchBox(toolbar, L["Search items"], function(text)
        state.search = text or ""
        Refresh()
    end)
    search:SetPoint("LEFT", 0, 0)
    search:SetWidth(Widgets.SEARCH_WIDTH)

    local view = Widgets.CreateCheckbox(toolbar, L["Items in my bags"], function(checked)
        state.view = checked and "bag" or "auction"
        state.selected = nil
        ApplyView()
        widgets.list:ScrollToTop()
        Refresh()
    end, state.view == "bag")
    view:SetPoint("LEFT", search, "RIGHT", 12, 0)
    widgets.view = view

    local dealsOnly = Widgets.CreateCheckbox(toolbar, L["Only deals over my minimums"], function(checked)
        state.dealsOnly = checked
        Refresh()
    end, state.dealsOnly)
    dealsOnly:SetPoint("LEFT", view, "RIGHT", 12, 0)
    widgets.dealsOnly = dealsOnly

    local hideTooHigh = Widgets.CreateCheckbox(toolbar, L["Only ones I can disenchant"], function(checked)
        state.hideTooHigh = checked
        Refresh()
    end, state.hideTooHigh)
    hideTooHigh:SetPoint("LEFT", dealsOnly, "RIGHT", 12, 0)
    widgets.hideTooHigh = hideTooHigh

    -- In the bags list: off by default, so everything that can be broken is
    -- there to break, best first.
    local beatsOnly = Widgets.CreateCheckbox(toolbar, L["Only where disenchanting pays more"], function(checked)
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
    nameHeading:SetText(L["ITEM"])

    widgets.headings = {}
    for index = 1, MAX_COLUMNS do
        widgets.headings[index] = Theme.CreateLabel(headings, "tiny", "muted", "RIGHT")
    end

    -- Click a heading to sort by it. The headings change with the view, so
    -- each one reads whatever column the view puts there.
    local FIELDS = {
        difference = function(row) return row.value and row.sells and (row.value - row.sells) or nil end,
        skill = function(row) return row.needs end,
        perHour = PerHour,
    }
    local sortLabels, values = { name = nameHeading }, {
        name = function(row) return row.name end,
    }
    for index = 1, MAX_COLUMNS do
        sortLabels[index] = widgets.headings[index]
        values[index] = function(row)
            local column = ViewColumns()[index]
            if not column then return nil end
            local field = FIELDS[column.key]
            if field then return field(row) end
            return row[column.key]
        end
    end
    widgets.sorter = Widgets.SortableHeadings and Widgets.SortableHeadings(sortLabels, values,
        function() Refresh() end)
    if widgets.sorter then widgets.sorter:SetText({ "name" }) end

    -- Right-click the headings to choose the columns of the view showing.
    ns.Columns:Attach(headings, function() return LIST_IDS[state.view] end, widgets.sorter)
    local function ColumnsChanged()
        if not widgets.list then return end
        ApplyView()
        widgets.list:Refresh()
    end
    ns.Columns:OnChange("disenchant", ColumnsChanged)
    ns.Columns:OnChange("disenchantbags", ColumnsChanged)

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

            if mouseButton == "RightButton" then
                if entry.kind == "bag" then ToggleBought(entry) else SearchAuctionHouse(entry) end
            end
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
    -- and ran under this hint. It stops short of it now and ends in "...".
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
    key = "disenchanting",
    text = L["Disenchanting"],
    order = 1.8,
    build = Build,
    refresh = Refresh,
})
