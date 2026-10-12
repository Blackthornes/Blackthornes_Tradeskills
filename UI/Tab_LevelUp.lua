-- Blackthornes Tradeskills -- UI/Tab_LevelUp.lua
-- The cheapest way up a profession: what still gives skill, cheapest first.
--
-- The ranking lives in Logic/LevelUp.lua. This file only draws it, and hands
-- anything picked here to the one craft queue the Queue tab and the craft
-- pane also show.

local _, ns = ...
local L = ns.L or setmetatable({ Format = string.format }, { __index = function(_, key) return key end })

local Theme = ns.Theme
local Widgets = ns.Widgets
local Util = ns.Util

local UI = ns.UI

local ROW_HEIGHT = 22
local DETAIL_WIDTH = 300

-- Columns, measured from the right edge of the list and laid out right to
-- left. Money sits to the right, so its coins line up; the rest is centred
-- under its heading. `width` is the least each gets: Widgets.FitColumns
-- widens it to fit the heading and a full amount.
local COLUMNS = {
    { key = "make",   label = L["MAKE"], width = 40, justify = "CENTER" },
    { key = "real",   label = L["REAL COST"], width = 74, money = true },
    { key = "via",    label = L["VIA"], width = 44, justify = "CENTER" },
    { key = "back",   label = L["GETS BACK"], width = 74, money = true },
    { key = "cost",   label = L["COST"], width = 74, money = true },
    { key = "chance", label = L["SKILL UP"], width = 80, justify = "CENTER" },
    -- Make or Buy when another craft uses the item: a button that says
    -- whether it is made as a sub-craft (2026-10-07).
    { key = "sub",    label = L["SUB-CRAFT"], width = 50, justify = "CENTER", button = true },
}

-- Any column but the recipe's name can be hidden (UI/Columns.lua).
ns.Columns:Register("levelup", L["Level Up"], COLUMNS)

-- How each way of getting gold back is named: short in the VIA column, in
-- full in the tooltip and the detail panel.
local WAY_SHORT = { vendor = L["Vendor"], auction = L["AH"], disenchant = L["DE"] }
-- In a sentence, for the note on which way the Profit tab counts.
local WAY_WORD = { vendor = L["vendor"], auction = L["auction house"], disenchant = L["disenchant"] }
local WAY_LONG = {
    vendor = L["Vendor"],
    auction = L["Auction house, after the cut"],
    disenchant = L["Disenchant, most likely result"],
}

local state = {
    search = "",
    profession = nil,       -- a profession name, or nil for all of them
    followed = nil,         -- the last-open skill line the choice was made from
    started = false,        -- a default has been picked once already
    craftableOnly = false,
    includeTrivial = false,
    subCraftsOnly = false,
    selected = nil,
}

local widgets = {}

-- The row hint, as much of it as fits beside the count on its left.
local HINT_TEXTS = {
    L["Right-click a row to queue one, Shift-click to search the auction house"],
    L["Right-click to queue, Shift-click to search"],
    L["Right-click a row to queue one"],
}

local function FitHint()
    local hint, count, list = widgets.hint, widgets.countLabel, widgets.list
    if not (hint and count and list and Theme.TextWidth and Theme.FitText) then return end
    local listWidth = list:GetWidth()
    local used = Theme.TextWidth(count) or 0
    local room = type(listWidth) == "number" and listWidth > 0 and (listWidth - used - 24) or nil
    Theme.FitText(hint, HINT_TEXTS, room)
end

-- Defined with the detail panel, used by the controls built inside it.
local UpdateCraftButton

-- Defined after Build; Sub-crafts only rebuilds the profession list with it.
local OnShow

-- Profession name -> set of skill-line IDs carrying it. Forever lists every
-- profession under two IDs and a recipe may be tagged with either, so the
-- dropdown works in names and filters by the whole set.
local skillLinesByName = {}
local nameBySkillLine = {}

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function ProfessionInfo(skillLineID)
    if not skillLineID then return nil end
    if not Util.HasFunction("C_TradeSkillUI.GetProfessionInfoBySkillLineID") then return nil end

    local ok, info = pcall(C_TradeSkillUI.GetProfessionInfoBySkillLineID, skillLineID)
    if ok and type(info) == "table" then return info end

    return nil
end

--- The game's colour for a tier, or plain text for one never read.
local function TierColor(tier)
    if not tier or tier == "unknown" then return Theme.Unpack("muted") end
    return ns.SkillUp:GetTierColor(tier)
end

-- Rounded: this client refuses a fraction for %x, and the tier colours
-- scale to 127.5 and the like.
local function ColorCode(r, g, b)
    return ("|cff%02x%02x%02x"):format(math.floor(r * 255 + 0.5),
        math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))
end

--------------------------------------------------------------------------------
-- Rows
--------------------------------------------------------------------------------

--- Never make this craft as a sub-craft, or make it again (the row's
--- SUB-CRAFT button). Cost:SetNeverSubCraft redraws everything.
local function ToggleSubCraft(entry)
    if not entry then return end
    local never = not ns.Cost:IsNeverSubCraft(entry.recipeID)
    ns.Cost:SetNeverSubCraft(entry.recipeID, never, entry.name)
    if never then
        ns.Print(L.Format("%s is no longer made as a sub-craft: crafts that use it buy it instead.", entry.name or L["that craft"]))
    else
        ns.Print(L.Format("%s is made as a sub-craft again when that is cheaper than buying it.", entry.name or L["that craft"]))
    end
end

local function SubCraftTooltip(entry)
    local name = entry.name or L["this"]
    if entry.neverSubCraft then
        return L.Format("Buy: %s is never made to go into another craft. It is bought instead, in costs, the queue and the shopping list.\nClick to make it again when that is cheaper.", name)
    end
    local text = L.Format("Make: %s is made to go into other crafts when that is cheaper than buying it.\nClick to never make it as a sub-craft and buy it instead. Settings, Queue lists those.", name)
    if not entry.isMaterial then
        text = text .. "\n" .. L["No craft your characters know uses it yet."]
    end
    return text
end

--- The shown columns from the right edge; the name has the rest. The
--- SUB-CRAFT button sits centred in its column, or stays hidden with it.
local function PlaceRow(row)
    local offset = ns.Columns:Place("levelup", COLUMNS, row.cells, {
        place = function(column, offset, shown)
            local button = column.button and row.subButton
            if not button then return end
            row.subHidden = not shown
            if shown then
                local width = math.min(column.width, 48)
                button:ClearAllPoints()
                button:SetPoint("RIGHT", row, "RIGHT", offset - (column.width - width) / 2, 0)
            else
                button:Hide()
            end
        end,
    })
    row.name:SetPoint("RIGHT", row, "RIGHT", offset - 4, 0)
    row.columnsVersion = ns.Columns.version
end

local function CreateRow(row)
    -- The item's icon beside its name, as the bags draw it.
    row.icon = Theme.CreateItemIcon(row, 16)
    row.icon:SetPoint("LEFT", 8, 0)

    row.name = Theme.CreateLabel(row, "small", "text")
    row.name:SetPoint("LEFT", 28, 0)

    row.cells = {}
    for _, column in ipairs(COLUMNS) do
        if column.button then
            row.subButton = Widgets.CreateButton(row, L["Make"], function()
                ToggleSubCraft(row.data)
            end, { width = math.min(column.width, 48), height = 16 })
        else
            row.cells[column.key] = Theme.CreateLabel(row, "small", "text", column.justify or "RIGHT")
        end
    end

    PlaceRow(row)
end

local function UpdateRow(row, entry)
    if row.columnsVersion ~= ns.Columns.version then PlaceRow(row) end

    local cells = row.cells

    -- Coloured the way the profession window colours it, so the list reads
    -- the same as the game without being told what orange means.
    local name = entry.name or L.Format("recipe %s", entry.recipeID)
    -- A craft only another character knows (Sub-crafts only) says who.
    if entry.knownBy and ns.Recipes.GetShortCharacterName then
        name = ("%s |cff7a8089(%s)|r"):format(name, ns.Recipes:GetShortCharacterName(entry.knownBy))
    end
    Theme.SetRowName(row.name, name)
    row.name:SetTextColor(TierColor(entry.tier))
    Theme.SetItemIcon(row.icon, entry.outputItemID)

    cells.chance:SetText(ns.LevelUp.CHANCE_LABEL[entry.tier] or "")
    cells.chance:SetTextColor(TierColor(entry.tier))

    if entry.cost then
        Theme.SetMoneyText(cells.cost, entry.cost, { short = true })
        cells.cost:SetTextColor(Theme.Unpack("text"))
    else
        cells.cost:SetText(L["no price"])
        cells.cost:SetTextColor(Theme.Unpack("dim"))
    end

    if entry.back then
        Theme.SetMoneyText(cells.back, entry.back, { short = true })
        cells.via:SetText(WAY_SHORT[entry.backWay] or "")
        cells.via:SetTextColor(Theme.Unpack("muted"))
    else
        cells.back:SetText("--")
        cells.back:SetTextColor(Theme.Unpack("dim"))
        cells.via:SetText("")
    end

    -- What levelling on it really costs once it is sold back. Below nothing
    -- the craft pays for itself, shown as a gain in green.
    if entry.realCost and entry.realCost < 0 then
        -- Fitted a little narrower, so the plus sign has room too.
        local width = cells.real:GetWidth()
        cells.real:SetWidth(width - 8)
        Theme.SetMoneyText(cells.real, -entry.realCost, { short = true })
        cells.real:SetWidth(width)
        cells.real:SetText("+" .. (cells.real:GetText() or ""))
        cells.real:SetTextColor(Theme.Unpack("profit"))
    elseif entry.realCost or entry.cost then
        Theme.SetMoneyText(cells.real, entry.realCost or entry.cost, { short = true })
        cells.real:SetTextColor(Theme.Unpack("text"))
    else
        cells.real:SetText(L["no price"])
        cells.real:SetTextColor(Theme.Unpack("dim"))
    end

    local craftable = entry.craftableNow or 0
    cells.make:SetText(tostring(craftable))
    cells.make:SetTextColor(Theme.Unpack(craftable > 0 and "text" or "loss"))

    -- On every craft that makes an item (2026-10-09): only on
    -- those another known craft used, a craft whose user was never read
    -- could not be marked.
    local button = row.subButton
    if button then
        row.data = entry
        local shown = entry.outputItemID ~= nil
        button:SetShown(shown == true and not row.subHidden)
        if shown then
            button:SetText(entry.neverSubCraft and L["Buy"] or L["Make"])
            button.tooltipText = SubCraftTooltip(entry)
        end
    end
end

--- A reading taken at a lower skill may have changed colour since. Said out
--- loud rather than quietly trusted.
local function StaleNote(skillUp)
    if not skillUp or not skillUp.stale then return nil end

    return L.Format("Colour read at skill %d and you are %d now, so it may have changed. Open the profession to update it.",
        skillUp.skill or 0, skillUp.currentSkill or 0)
end

local function ShowRowTooltip(row, entry)
    ns.Widgets.ShowItemTooltip(row, "ANCHOR_LEFT", entry.outputItemID, entry.name or L["craft"])
    GameTooltip:AddLine(" ")

    local r, g, b = TierColor(entry.tier)
    local chance = entry.tier == "unknown" and L["not read yet"]
        or ns.SkillUp:GetTierLabel(entry.tier)
    GameTooltip:AddDoubleLine(L["Skill up"], chance, 0.7, 0.7, 0.7, r, g, b)

    GameTooltip:AddDoubleLine(L["Materials"], entry.cost
        and Util.FormatMoney(entry.cost, { noColor = true }) or L["no price"],
        0.7, 0.7, 0.7, 1, 1, 1)

    local returns = entry.returns
    local anyWay = returns and (returns.vendor or returns.auction or returns.disenchant)
    if anyWay then
        for _, way in ipairs({ "vendor", "auction", "disenchant" }) do
            if returns[way] then
                local r, g, b = 1, 1, 1
                if way == entry.backWay then r, g, b = Theme.Unpack("profit") end
                GameTooltip:AddDoubleLine(WAY_LONG[way], Util.FormatMoney(returns[way], { noColor = true }),
                    0.7, 0.7, 0.7, r, g, b)
            end
        end

        if entry.realCost then
            local gain = entry.realCost < 0
            local r, g, b = 1, 1, 1
            if gain then r, g, b = Theme.Unpack("profit") end
            GameTooltip:AddDoubleLine(gain and L["Pays you back"] or L["Real cost"],
                Util.FormatMoney(math.abs(entry.realCost), { noColor = true }),
                1, 0.82, 0, r, g, b)
        end

        -- The Profit tab's "Profit:" choice picks the way that counts.
        if returns.method and returns.method ~= "best" then
            local label = WAY_WORD[returns.method] or returns.method
            local text = returns.best
                and L.Format("Only the %s counts: the Profit tab is set to it.", label)
                or L.Format("Only the %s counts (the Profit tab is set to it), and it pays nothing for this.", label)
            GameTooltip:AddLine(text, 0.7, 0.7, 0.7, true)
        end
    elseif entry.outputItemID then
        GameTooltip:AddLine(L["Nothing to sell it back for yet: no vendor, auction or disenchant price."], 0.7, 0.7, 0.7, true)
    end

    local note = StaleNote(entry.skillUp)
    if note then GameTooltip:AddLine(note, 0.91, 0.76, 0.35, true) end

    if entry.neverSubCraft then
        GameTooltip:AddLine(L["Never made as a sub-craft: crafts that use it buy it instead."], 0.91, 0.76, 0.35, true)
    end

    GameTooltip:AddLine(L["Right-click to queue one. Shift-click to search the auction house."], 0.5, 0.5, 0.5)
    GameTooltip:Show()
end

--------------------------------------------------------------------------------
-- Detail panel
--------------------------------------------------------------------------------

--- Set the Craft button for the selected recipe: craft, open its profession
--- window first, stop a craft under way, or say why it cannot.
UpdateCraftButton = function()
    local detail = widgets.detail
    local button = detail and detail.craftButton
    if not button then return end

    local entry = state.selected
    local opener = ns.ProfessionOpener
    button.opensProfession = false

    if not entry or not button:IsVisible() then
        if opener and opener.anchor == button then opener:Disarm() end
        return
    end

    local action = ns.LevelUp:CraftAction(entry.recipeID, detail.quantity:GetText())

    button:SetText(action.text)
    button:SetEnabledState(action.kind ~= "none")
    button.tooltipText = action.status
    detail.craftStatus:SetText(action.status or "")
    detail.craftStatus:SetTextColor(Theme.Unpack(action.kind == "none" and "warn" or "accent"))

    if action.kind == "open" and opener then
        button.opensProfession = true
        opener:Arm(button, action.profession, entry.recipeID)
    elseif opener and opener.anchor == button then
        -- Only our own button: the Queue tab may be holding the secure
        -- button over its Craft button.
        opener:Disarm()
    end
end

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

    local note = Theme.CreateLabel(detail, "tiny", "warn")
    note:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", 0, -4)
    note:SetPoint("RIGHT", detail, "RIGHT", -12, 0)
    note:SetWordWrap(true)
    detail.note = note

    local reagentHeading = Theme.CreateLabel(detail, "tiny", "dim")
    -- Back out under the icon, so the list of materials starts at the edge.
    reagentHeading:SetPoint("TOPLEFT", note, "BOTTOMLEFT", -38, -12)
    reagentHeading:SetText(L["MATERIALS"])
    Theme.StyleHeading(reagentHeading, detail)
    detail.reagentHeading = reagentHeading

    detail.reagentLines = {}

    local summary = CreateFrame("Frame", nil, detail)
    summary:SetPoint("BOTTOMLEFT", 12, 72)
    summary:SetPoint("BOTTOMRIGHT", -12, 72)
    summary:SetHeight(6 * 16)
    detail.summary = summary

    local function SummaryRow(index, labelText)
        local label = Theme.CreateLabel(summary, "small", "muted")
        label:SetPoint("TOPLEFT", 0, -(index - 1) * 16)
        label:SetText(labelText)

        local value = Theme.CreateLabel(summary, "small", "text", "RIGHT")
        value:SetPoint("TOPRIGHT", 0, -(index - 1) * 16)
        value:SetPoint("LEFT", label, "RIGHT", 8, 0)

        return value, label
    end

    detail.costValue = SummaryRow(1, L["Materials for one"])
    detail.wayValues = {
        vendor = SummaryRow(2, L["Vendor pays"]),
        auction = SummaryRow(3, L["Auction, after cut"]),
        disenchant = SummaryRow(4, L["Disenchant, likely"]),
    }
    detail.realValue, detail.realLabel = SummaryRow(5, L["Real cost"])
    detail.makeValue = SummaryRow(6, L["You can make now"])

    -- What the Craft button will do, or why it cannot. A craft's progress bar
    -- takes this line's place while it casts. Wrapped, growing upwards into
    -- the space under the summary: "Opens your Leatherworking window. Click
    -- again to craft." is about as wide as the pane on one line, and longer
    -- profession names ran past it.
    local craftStatus = Theme.CreateLabel(detail, "tiny", "accent")
    craftStatus:SetPoint("BOTTOMLEFT", 12, 46)
    craftStatus:SetPoint("BOTTOMRIGHT", -12, 46)
    craftStatus:SetWordWrap(true)
    detail.craftStatus = craftStatus

    detail.craftProgress = ns.CraftProgress:Create(detail, {
        width = DETAIL_WIDTH - 24, height = 18, covers = craftStatus,
    })
    detail.craftProgress:SetPoint("BOTTOMLEFT", 12, 42)

    local quantityBox = Theme.CreatePanel(detail, "row")
    quantityBox:SetSize(40, 24)
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
    -- The Craft button names the number it will make, so it follows the box.
    quantity:SetScript("OnTextChanged", function(_, userInput)
        if userInput then UpdateCraftButton() end
    end)
    detail.quantity = quantity

    local function Wanted()
        return math.max(1, tonumber(quantity:GetText()) or 1)
    end

    -- Crafting needs a real click, so this runs straight from the button.
    -- When the recipe's window is not open, the secure Open button laid over
    -- this one takes the click instead and this handler never runs.
    local craftButton = Widgets.CreateButton(detail, L["Craft"], function(button)
        local entry = state.selected
        if not entry then return end

        if ns.Crafting:IsBusy() then
            ns.Crafting:Stop()
        elseif button.opensProfession and ns.ProfessionOpener then
            ns.ProfessionOpener:MissedClick()
        else
            ns.Crafting:Start(entry.recipeID, Wanted())
        end

        UpdateCraftButton()
    end, { width = 110, primary = true, height = 24 })
    craftButton:SetPoint("BOTTOMLEFT", quantityBox, "BOTTOMRIGHT", 6, 0)
    detail.craftButton = craftButton

    local addButton = Widgets.CreateButton(detail, L["Queue"], function()
        if not state.selected then return end

        local count = Wanted()
        ns.Queue:Add(state.selected.recipeID, count)
        ns.Print(L.Format("queued %dx %s", count, state.selected.name or L["craft"]))
    end, { width = 64, height = 24, tooltip = L["Add this many to the craft queue"] })
    addButton:SetPoint("BOTTOMLEFT", craftButton, "BOTTOMRIGHT", 6, 0)
    detail.addButton = addButton

    local maxButton = Widgets.CreateButton(detail, L["Max"], function()
        if not state.selected then return end
        quantity:SetText(tostring(math.max(1, state.selected.craftableNow or 1)))
        UpdateCraftButton()
    end, { width = 40, height = 24, tooltip = L["As many as the materials in your bags make"] })
    maxButton:SetPoint("BOTTOMLEFT", addButton, "BOTTOMRIGHT", 6, 0)
    detail.maxButton = maxButton

    local empty = Theme.CreateLabel(detail, "small", "dim", "CENTER")
    empty:SetPoint("CENTER")
    empty:SetWidth(DETAIL_WIDTH - 40)
    empty:SetWordWrap(true)
    empty:SetText(L["Pick a recipe to see its materials"])
    detail.empty = empty

    return detail
end

local function UpdateDetail(entry)
    local detail = widgets.detail
    local shown = entry ~= nil

    detail.empty:SetShown(not shown)

    for _, line in ipairs(detail.reagentLines) do
        line.frame:Hide()
    end

    detail.icon:SetShown(shown)

    for _, part in ipairs({ detail.title, detail.subtitle, detail.note, detail.reagentHeading,
                            detail.summary, detail.quantityBox, detail.addButton,
                            detail.maxButton, detail.craftButton }) do
        part:SetShown(shown)
    end

    if not shown then
        detail.shownRecipeID = nil
        -- Emptied rather than hidden: the progress bar hides and shows this
        -- line itself while a craft casts.
        detail.craftStatus:SetText("")
        UpdateCraftButton()
        return
    end

    detail.title:SetText(entry.name or L.Format("recipe %s", entry.recipeID))
    Theme.SetItemIcon(detail.icon, entry.outputItemID)

    local r, g, b = TierColor(entry.tier)
    if entry.tier == "unknown" then
        detail.subtitle:SetText(L["Skill up chance not read yet. Open the profession window to read it."])
    else
        local text = ns.SkillUp:GetTierLabel(entry.tier)
        detail.subtitle:SetText(text:sub(1, 1):upper() .. text:sub(2))
    end
    detail.subtitle:SetTextColor(r, g, b)

    detail.note:SetText(StaleNote(entry.skillUp) or "")

    local anchor = detail.reagentHeading
    local reagents = (entry.costDetail and entry.costDetail.reagents) or {}

    for index, reagent in ipairs(reagents) do
        local line = detail.reagentLines[index]

        if not line then
            local frame = CreateFrame("Frame", nil, detail)
            frame:SetHeight(16)

            local icon = Theme.CreateItemIcon(frame, 14)
            icon:SetPoint("LEFT", 0, 0)
            if Widgets.ItemHotspot then Widgets.ItemHotspot(icon, frame) end

            local name = Theme.CreateLabel(frame, "small", "text")
            name:SetPoint("LEFT", 18, 0)
            name:SetPoint("RIGHT", -74, 0)

            local value = Theme.CreateLabel(frame, "small", "muted", "RIGHT")
            value:SetPoint("RIGHT", 0, 0)

            line = { frame = frame, icon = icon, name = name, value = value }
            detail.reagentLines[index] = line
        end

        line.frame:ClearAllPoints()
        line.frame:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, index == 1 and -6 or 0)
        line.frame:SetPoint("TOPRIGHT", detail, "TOPRIGHT", -12, 0)

        local label = ("%dx %s"):format(reagent.quantity, Util.GetItemLabel(reagent.itemID))
        if reagent.crafted then
            label = L.Format("%s (make it)", label)
        elseif ns.Cost.NeverMadeRecipeFor and ns.Cost:NeverMadeRecipeFor(reagent.itemID) then
            -- Marked never to make as a sub-craft, so it is bought.
            label = L.Format("%s (bought, never made)", label)
        end
        line.name:SetText(label)
        Theme.SetItemIcon(line.icon, reagent.itemID)

        -- Have or need first: it answers "can I make this" without a second
        -- screen. Bank stock counts here, the same as on the Profit tab.
        if (reagent.shortfall or 0) > 0 then
            line.value:SetText(L.Format("need %d", reagent.shortfall))
            line.value:SetTextColor(Theme.Unpack("loss"))
        elseif reagent.lineCost then
            line.value:SetText(Util.FormatMoney(reagent.lineCost, { short = true }))
            line.value:SetTextColor(Theme.Unpack("muted"))
        else
            line.value:SetText(L["no price"])
            line.value:SetTextColor(Theme.Unpack("dim"))
        end

        line.frame:Show()
        anchor = line.frame
    end

    if entry.cost then
        detail.costValue:SetText(Util.FormatMoney(entry.cost))
    else
        detail.costValue:SetText(L["a material has no price"])
    end

    -- Each way back, the one the list counts in green.
    local returns = entry.returns or {}
    for way, label in pairs(detail.wayValues) do
        if returns[way] then
            label:SetText(Util.FormatMoney(returns[way]))
            if way == entry.backWay then
                label:SetTextColor(Theme.Unpack("profit"))
            else
                label:SetTextColor(Theme.Unpack("text"))
            end
        else
            label:SetText("--")
            label:SetTextColor(Theme.Unpack("dim"))
        end
    end

    if entry.realCost and entry.realCost < 0 then
        detail.realLabel:SetText(L["Pays you back"])
        detail.realValue:SetText(Util.FormatMoney(-entry.realCost))
        detail.realValue:SetTextColor(Theme.Unpack("profit"))
    else
        detail.realLabel:SetText(L["Real cost"])
        local real = entry.realCost or entry.cost
        detail.realValue:SetText(real and Util.FormatMoney(real) or "--")
        detail.realValue:SetTextColor(Theme.Unpack(real and "text" or "dim"))
    end

    local craftable = entry.craftableNow or 0
    detail.makeValue:SetText(tostring(craftable))
    detail.makeValue:SetTextColor(Theme.Unpack(craftable > 0 and "profit" or "loss"))

    -- Only when a different recipe is picked. The list refreshes on every
    -- bag change, and a number the player typed must survive that.
    if detail.shownRecipeID ~= entry.recipeID then
        detail.shownRecipeID = entry.recipeID
        detail.quantity:SetText(tostring(math.max(1, craftable)))
    end

    UpdateCraftButton()
end

--------------------------------------------------------------------------------
-- List
--------------------------------------------------------------------------------

local function UpdateSkillLabel()
    local skillLines = state.profession and skillLinesByName[state.profession]
    local label = widgets.skillLabel

    if not skillLines then
        label:SetText("")
        return
    end

    for skillLineID in pairs(skillLines) do
        local info = ProfessionInfo(skillLineID)

        if info and (info.maxSkillLevel or 0) > 0 then
            label:SetText(L.Format("Skill %d / %d", info.skillLevel or 0, info.maxSkillLevel))
            return
        end
    end

    label:SetText("")
end

local function Refresh()
    if not widgets.list then return end

    local rows = ns.LevelUp:GetRanked({
        skillLines = state.profession and skillLinesByName[state.profession] or nil,
        includeTrivial = state.includeTrivial,
        craftableOnly = state.craftableOnly,
        subCraftsOnly = state.subCraftsOnly,
        search = state.search,
    })

    widgets.list:SetData(rows)
    UpdateSkillLabel()

    -- How many of each colour, so the footer says at a glance how much
    -- levelling is left in what you know.
    local counts, unread = {}, 0
    for _, row in ipairs(rows) do
        counts[row.tier] = (counts[row.tier] or 0) + 1
        if row.tier == "unknown" then unread = unread + 1 end
    end

    -- Its own words: the CHANCE column's "Small" and "None" read as "25
    -- small  200 none" down here.
    local FOOTER_WORDS = {
        optimal = L["guaranteed"], medium = L["likely"], easy = L["small chance"],
        unknown = L["not read"], trivial = L["no skill-up"],
    }

    local parts = {}
    for _, tier in ipairs({ "optimal", "medium", "easy", "unknown", "trivial" }) do
        if counts[tier] then
            parts[#parts + 1] = ("%s%d %s|r"):format(ColorCode(TierColor(tier)), counts[tier],
                FOOTER_WORDS[tier] or ns.LevelUp.CHANCE_LABEL[tier]:lower())
        end
    end
    widgets.countLabel:SetText(table.concat(parts, "   "))

    widgets.emptyLabel:SetShown(#rows == 0)

    if #rows == 0 then
        if ns.Recipes:Count() == 0 then
            widgets.emptyLabel:SetText(L["Open a profession window once so your recipes can be read."])
        elseif state.search ~= "" then
            widgets.emptyLabel:SetText(L.Format("Nothing matching \"%s\".", state.search))
        elseif state.subCraftsOnly then
            widgets.emptyLabel:SetText(L["Nothing you know here makes a material for another craft."])
        elseif state.craftableOnly then
            widgets.emptyLabel:SetText(L["Nothing that gives skill can be made from your bags right now."])
        else
            widgets.emptyLabel:SetText(L["Nothing you know gives skill any more. Tick \"Show grey\" to see the rest, or learn new recipes."])
        end
    end

    -- Colours are only readable while the profession window is open. A
    -- list that is all "not read" is one that has never been opened since
    -- this addon was installed, and says so.
    if #rows > 0 and unread == #rows then
        widgets.countLabel:SetText(L["Open this profession once so the skill up colours can be read."])
    end
    FitHint()

    -- Keep the detail panel in step with the fresh numbers.
    if state.selected then
        local fresh = ns.LevelUp:BuildRow(state.selected.recipeID)
        state.selected = fresh
        UpdateDetail(fresh)
    else
        UpdateDetail(nil)
    end
end

--------------------------------------------------------------------------------
-- Build
--------------------------------------------------------------------------------

local function Build(container)
    -- Before any row or heading is laid out: they read these widths.
    if Widgets.FitColumns then Widgets.FitColumns(COLUMNS) end

    local toolbar = CreateFrame("Frame", nil, container)
    toolbar:SetPoint("TOPLEFT", 8, -8)
    toolbar:SetPoint("TOPRIGHT", -8, -8)
    toolbar:SetHeight(24)

    local profession = Widgets.CreateDropdown(toolbar, { { text = L["All professions"], value = nil } },
        function(value)
            state.profession = value
            state.selected = nil
            widgets.list:ScrollToTop()
            Refresh()
        end, { width = 150 })
    profession:SetPoint("LEFT", 0, 0)
    widgets.professionDropdown = profession

    local search = Widgets.CreateSearchBox(toolbar, L["Search recipes"], function(text)
        state.search = text or ""
        Refresh()
    end)
    search:SetPoint("LEFT", profession, "RIGHT", 8, 0)
    search:SetWidth(Widgets.SEARCH_WIDTH)

    local craftable = Widgets.CreateCheckbox(toolbar, L["Craftable now"], function(checked)
        state.craftableOnly = checked
        Refresh()
    end, false)
    craftable:SetPoint("LEFT", search, "RIGHT", 12, 0)

    local trivial = Widgets.CreateCheckbox(toolbar, L["Show grey"], function(checked)
        state.includeTrivial = checked
        Refresh()
    end, false)
    trivial:SetPoint("LEFT", craftable, "RIGHT", 12, 0)

    -- Asked 2026-10-07: the crafts that make another's materials, grey
    -- ones too, to choose which to make and which to buy.
    local subCrafts = Widgets.CreateCheckbox(toolbar, L["Sub-crafts only"], function(checked)
        state.subCraftsOnly = checked
        state.selected = nil
        -- Other characters' professions join the menu, or leave it.
        OnShow()
        widgets.list:ScrollToTop()
        Refresh()
    end, false)
    subCrafts:SetPoint("LEFT", trivial, "RIGHT", 12, 0)
    subCrafts:HookScript("OnEnter", function(box)
        GameTooltip:SetOwner(box, "ANCHOR_BOTTOM")
        GameTooltip:SetText(L["Sub-crafts only"], 1, 1, 1)
        GameTooltip:AddLine(L["Only crafts whose item goes into another craft, grey ones too, on all your characters. Their SUB-CRAFT button picks Make or Buy."], 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    subCrafts:HookScript("OnLeave", function() GameTooltip:Hide() end)

    local skillLabel = Theme.CreateLabel(toolbar, "normal", "accent", "RIGHT")
    skillLabel:SetPoint("RIGHT", 0, 0)
    widgets.skillLabel = skillLabel

    -- Column headings
    local headings = CreateFrame("Frame", nil, container)
    headings:SetPoint("TOPLEFT", toolbar, "BOTTOMLEFT", 0, -8)
    headings:SetPoint("TOPRIGHT", toolbar, "BOTTOMRIGHT", -DETAIL_WIDTH - 8, -8)
    headings:SetHeight(16)

    local nameHeading = Theme.CreateLabel(headings, "tiny", "muted")
    nameHeading:SetPoint("LEFT", 28, 0)
    nameHeading:SetText(L["RECIPE"])

    local cells = {}
    for _, column in ipairs(COLUMNS) do
        local heading = Theme.CreateLabel(headings, "tiny", "muted", column.justify or "RIGHT")
        heading:SetText(column.label)
        cells[column.key] = heading
    end
    ns.Columns:Place("levelup", COLUMNS, cells)

    -- Right-click the headings to choose the columns.
    ns.Columns:Attach(headings, "levelup")
    ns.Columns:OnChange("levelup", function()
        ns.Columns:Place("levelup", COLUMNS, cells)
        if widgets.list then widgets.list:Refresh() end
    end)

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

        -- The row the detail pane is showing stays lit.
        isSelected = function(entry)
            return state.selected ~= nil and entry.recipeID == state.selected.recipeID
        end,

        onClick = function(entry, _, mouseButton)
            if mouseButton == "RightButton" then
                ns.Queue:Add(entry.recipeID, 1)
                ns.Print(L.Format("queued %dx %s", 1, entry.name or L["craft"]))
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
    emptyLabel:SetWidth(340)
    emptyLabel:SetWordWrap(true)
    widgets.emptyLabel = emptyLabel

    local countLabel = Theme.CreateLabel(container, "tiny", "dim")
    countLabel:SetPoint("BOTTOMLEFT", 8, 8)
    widgets.countLabel = countLabel

    local hint = Theme.CreateLabel(container, "tiny", "dim", "RIGHT")
    hint:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", -DETAIL_WIDTH - 16, 8)
    hint:SetText(HINT_TEXTS[1])
    widgets.hint = hint

    local detail = BuildDetail(container)
    detail:SetPoint("TOPRIGHT", container, "TOPRIGHT", -8, -40)
    detail:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", -8, 8)
    widgets.detail = detail

    UpdateDetail(nil)
end

--- Rebuild the profession list, and follow the profession last opened.
OnShow = function()
    wipe(skillLinesByName)
    wipe(nameBySkillLine)

    local options = {}

    -- With Sub-crafts only, every character's professions, so an alt's
    -- alchemy or engineering can be picked too.
    local alts = state.subCraftsOnly
    local recipes = ns.LevelUp.ListedRecipes and ns.LevelUp:ListedRecipes(alts) or ns.Recipes:GetAll()

    for _, recipe in pairs(recipes) do
        local skillLineID = recipe.skillLineID

        -- A dropped profession has no crafts left to list. ListedRecipes
        -- has already left those out of every character's.
        if not alts and ns.Recipes.IsDropped and ns.Recipes:IsDropped(recipe) then skillLineID = nil end

        if skillLineID and not nameBySkillLine[skillLineID] then
            local info = ProfessionInfo(skillLineID)
            local name = (info and info.professionName) or L.Format("Skill line %s", skillLineID)

            nameBySkillLine[skillLineID] = name

            if not skillLinesByName[name] then
                skillLinesByName[name] = {}
                options[#options + 1] = { text = name, value = name }
            end

            skillLinesByName[name][skillLineID] = true
        end
    end

    -- "All professions" first, as in every profession menu (it sat last
    -- here, first on the Profit tab).
    table.sort(options, function(a, b) return a.text < b.text end)
    table.insert(options, 1, { text = L["All professions"], value = nil })

    local dropdown = widgets.professionDropdown
    dropdown:SetOptions(options)

    -- Open on the profession you last had open. Only when that changes,
    -- though: a choice made in the dropdown sticks until you open a different
    -- profession window.
    local last = ns.LevelUp:GetLastSkillLine()
    local lastName = last and nameBySkillLine[last]

    if lastName and last ~= state.followed then
        state.followed = last
        state.profession = lastName
        state.selected = nil
    elseif state.profession and not skillLinesByName[state.profession] then
        state.profession = nil
    elseif not state.started and options[2] then
        -- No profession opened since this was added: start on the first one
        -- rather than a mix of all of them.
        state.profession = options[2].value
    end

    state.started = true

    dropdown:SetValue(state.profession)
end

-- Recipes to learn here too (2026-10-05: "recipes to learn should be under
-- level up as well"), its own copy listed by the skill each recipe needs, so
-- the next recipe to get on the way up is near the top. Without
-- UI/RecipeBookView.lua (the tests load this file alone) the tab is the list.
local switch = ns.RecipeBookView and ns.RecipeBookView.WithSwitch({
    mainKey = "recipes",
    mainText = L["MY RECIPES"],
    mainTip = L["The recipes you know, cheapest way up first"],
    buildMain = Build,
    refreshMain = Refresh,
    learn = ns.RecipeBookView.New({ order = "skill" }),
})

UI:RegisterTab({
    key = "levelup",
    text = L["Level Up"],
    order = 1.5,
    build = switch and switch.Build or Build,
    refresh = switch and switch.Refresh or Refresh,
    onShow = OnShow,
})
