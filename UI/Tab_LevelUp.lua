-- Blackthornes Tradeskills -- UI/Tab_LevelUp.lua
-- The cheapest way up a profession: what still gives skill, cheapest first.
--
-- The ranking lives in Logic/LevelUp.lua. This file only draws it, and hands
-- anything picked here to the one craft queue the Queue tab and the craft
-- pane also show.

local _, ns = ...

local Theme = ns.Theme
local Widgets = ns.Widgets
local Util = ns.Util

local UI = ns.UI

local ROW_HEIGHT = 22
local DETAIL_WIDTH = 300

-- Right-aligned columns, measured from the right edge of the list and laid
-- out right to left.
local COLUMNS = {
    { key = "make",   width = 40 },
    { key = "cost",   width = 74 },
    { key = "chance", width = 80 },
}

local state = {
    search = "",
    profession = nil,       -- a profession name, or nil for all of them
    followed = nil,         -- the last-open skill line the choice was made from
    started = false,        -- a default has been picked once already
    craftableOnly = false,
    includeTrivial = false,
    selected = nil,
}

local widgets = {}

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

local function ColorCode(r, g, b)
    return ("|cff%02x%02x%02x"):format(r * 255, g * 255, b * 255)
end

--------------------------------------------------------------------------------
-- Rows
--------------------------------------------------------------------------------

local function CreateRow(row)
    row.name = Theme.CreateLabel(row, "small", "text")
    row.name:SetPoint("LEFT", 8, 0)

    row.cells = {}

    local offset = -8
    for _, column in ipairs(COLUMNS) do
        local cell = Theme.CreateLabel(row, "small", "text", "RIGHT")
        cell:SetPoint("RIGHT", row, "RIGHT", offset, 0)
        cell:SetWidth(column.width)
        row.cells[column.key] = cell
        offset = offset - column.width - 6
    end

    row.name:SetPoint("RIGHT", row, "RIGHT", offset - 4, 0)
end

local function UpdateRow(row, entry)
    local cells = row.cells

    -- Coloured the way the profession window colours it, so the list reads
    -- the same as the game without being told what orange means.
    row.name:SetText(entry.name or ("recipe " .. entry.recipeID))
    row.name:SetTextColor(TierColor(entry.tier))

    cells.chance:SetText(ns.LevelUp.CHANCE_LABEL[entry.tier] or "")
    cells.chance:SetTextColor(TierColor(entry.tier))

    if entry.cost then
        cells.cost:SetText(Util.FormatMoney(entry.cost, { short = true }))
        cells.cost:SetTextColor(Theme.Unpack("text"))
    else
        cells.cost:SetText("no price")
        cells.cost:SetTextColor(Theme.Unpack("dim"))
    end

    local craftable = entry.craftableNow or 0
    cells.make:SetText(tostring(craftable))
    cells.make:SetTextColor(Theme.Unpack(craftable > 0 and "text" or "loss"))
end

--- A reading taken at a lower skill may have changed colour since. Said out
--- loud rather than quietly trusted.
local function StaleNote(skillUp)
    if not skillUp or not skillUp.stale then return nil end

    return ("Colour read at skill %d and you are %d now, so it may have changed. Open the profession to update it.")
        :format(skillUp.skill or 0, skillUp.currentSkill or 0)
end

local function ShowRowTooltip(row, entry)
    GameTooltip:SetOwner(row, "ANCHOR_LEFT")
    GameTooltip:SetText(entry.name or "craft", 1, 1, 1)

    local r, g, b = TierColor(entry.tier)
    local chance = entry.tier == "unknown" and "not read yet"
        or ns.SkillUp:GetTierLabel(entry.tier)
    GameTooltip:AddDoubleLine("Skill up", chance, 0.7, 0.7, 0.7, r, g, b)

    GameTooltip:AddDoubleLine("Materials", entry.cost
        and Util.FormatMoney(entry.cost, { noColor = true }) or "no price",
        0.7, 0.7, 0.7, 1, 1, 1)

    local note = StaleNote(entry.skillUp)
    if note then GameTooltip:AddLine(note, 0.91, 0.76, 0.35, true) end

    GameTooltip:AddLine("Right-click to queue one.", 0.5, 0.5, 0.5)
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
    subtitle:SetPoint("RIGHT", detail, "RIGHT", -12, 0)
    subtitle:SetWordWrap(true)
    detail.subtitle = subtitle

    local note = Theme.CreateLabel(detail, "tiny", "warn")
    note:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", 0, -4)
    note:SetPoint("RIGHT", detail, "RIGHT", -12, 0)
    note:SetWordWrap(true)
    detail.note = note

    local reagentHeading = Theme.CreateLabel(detail, "tiny", "dim")
    reagentHeading:SetPoint("TOPLEFT", note, "BOTTOMLEFT", 0, -12)
    reagentHeading:SetText("MATERIALS")
    detail.reagentHeading = reagentHeading

    detail.reagentLines = {}

    local summary = CreateFrame("Frame", nil, detail)
    summary:SetPoint("BOTTOMLEFT", 12, 50)
    summary:SetPoint("BOTTOMRIGHT", -12, 50)
    summary:SetHeight(36)
    detail.summary = summary

    local function SummaryRow(index, labelText)
        local label = Theme.CreateLabel(summary, "small", "muted")
        label:SetPoint("TOPLEFT", 0, -(index - 1) * 17)
        label:SetText(labelText)

        local value = Theme.CreateLabel(summary, "small", "text", "RIGHT")
        value:SetPoint("TOPRIGHT", 0, -(index - 1) * 17)

        return value
    end

    detail.costValue = SummaryRow(1, "Materials for one")
    detail.makeValue = SummaryRow(2, "You can make now")

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
        if not state.selected then return end

        local count = math.max(1, tonumber(quantity:GetText()) or 1)
        ns.Queue:Add(state.selected.recipeID, count)
        ns.Print(("queued %dx %s"):format(count, state.selected.name or "craft"))
    end, { width = 130, primary = true, height = 24 })
    addButton:SetPoint("BOTTOMLEFT", quantityBox, "BOTTOMRIGHT", 8, 0)
    detail.addButton = addButton

    local maxButton = Widgets.CreateButton(detail, "Max", function()
        if not state.selected then return end
        quantity:SetText(tostring(math.max(1, state.selected.craftableNow or 1)))
    end, { width = 44, height = 24, tooltip = "As many as the materials in your bags make" })
    maxButton:SetPoint("BOTTOMLEFT", addButton, "BOTTOMRIGHT", 8, 0)
    detail.maxButton = maxButton

    local empty = Theme.CreateLabel(detail, "small", "dim", "CENTER")
    empty:SetPoint("CENTER")
    empty:SetWidth(DETAIL_WIDTH - 40)
    empty:SetWordWrap(true)
    empty:SetText("Pick a recipe to see its materials")
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

    for _, part in ipairs({ detail.title, detail.subtitle, detail.note, detail.reagentHeading,
                            detail.summary, detail.quantityBox, detail.addButton,
                            detail.maxButton }) do
        part:SetShown(shown)
    end

    if not shown then return end

    detail.title:SetText(entry.name or ("recipe " .. entry.recipeID))

    local r, g, b = TierColor(entry.tier)
    if entry.tier == "unknown" then
        detail.subtitle:SetText("Skill up chance not read yet. Open the profession window to read it.")
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

            local name = Theme.CreateLabel(frame, "small", "text")
            name:SetPoint("LEFT", 0, 0)
            name:SetPoint("RIGHT", -74, 0)

            local value = Theme.CreateLabel(frame, "small", "muted", "RIGHT")
            value:SetPoint("RIGHT", 0, 0)

            line = { frame = frame, name = name, value = value }
            detail.reagentLines[index] = line
        end

        line.frame:ClearAllPoints()
        line.frame:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, index == 1 and -6 or 0)
        line.frame:SetPoint("TOPRIGHT", detail, "TOPRIGHT", -12, 0)

        local label = ("%dx %s"):format(reagent.quantity, Util.GetItemLabel(reagent.itemID))
        if reagent.crafted then label = label .. " (make it)" end
        line.name:SetText(label)

        -- Have or need first: it answers "can I make this" without a second
        -- screen. Bank stock counts here, the same as on the Profit tab.
        if (reagent.shortfall or 0) > 0 then
            line.value:SetText(("need %d"):format(reagent.shortfall))
            line.value:SetTextColor(Theme.Unpack("loss"))
        elseif reagent.lineCost then
            line.value:SetText(Util.FormatMoney(reagent.lineCost, { short = true }))
            line.value:SetTextColor(Theme.Unpack("muted"))
        else
            line.value:SetText("no price")
            line.value:SetTextColor(Theme.Unpack("dim"))
        end

        line.frame:Show()
        anchor = line.frame
    end

    if entry.cost then
        detail.costValue:SetText(Util.FormatMoney(entry.cost))
    else
        detail.costValue:SetText("a material has no price")
    end

    local craftable = entry.craftableNow or 0
    detail.makeValue:SetText(tostring(craftable))
    detail.makeValue:SetTextColor(Theme.Unpack(craftable > 0 and "profit" or "loss"))

    detail.quantity:SetText(tostring(math.max(1, craftable)))
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
            label:SetText(("Skill %d / %d"):format(info.skillLevel or 0, info.maxSkillLevel))
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

    local parts = {}
    for _, tier in ipairs({ "optimal", "medium", "easy", "unknown", "trivial" }) do
        if counts[tier] then
            parts[#parts + 1] = ("%s%d %s|r"):format(ColorCode(TierColor(tier)), counts[tier],
                ns.LevelUp.CHANCE_LABEL[tier]:lower())
        end
    end
    widgets.countLabel:SetText(table.concat(parts, "   "))

    widgets.emptyLabel:SetShown(#rows == 0)

    if #rows == 0 then
        if ns.Recipes:Count() == 0 then
            widgets.emptyLabel:SetText("Open a profession window once so your recipes can be read.")
        elseif state.search ~= "" then
            widgets.emptyLabel:SetText(("Nothing matching \"%s\"."):format(state.search))
        elseif state.craftableOnly then
            widgets.emptyLabel:SetText("Nothing that gives skill can be made from your bags right now.")
        else
            widgets.emptyLabel:SetText("Nothing you know gives skill any more. Tick \"Show grey\" to see the rest, or learn new recipes.")
        end
    end

    -- Colours are only readable while the profession window is open. A
    -- list that is all "not read" is one that has never been opened since
    -- this addon was installed, and says so.
    if #rows > 0 and unread == #rows then
        widgets.countLabel:SetText("Open this profession once so the skill up colours can be read.")
    end

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
    local toolbar = CreateFrame("Frame", nil, container)
    toolbar:SetPoint("TOPLEFT", 8, -8)
    toolbar:SetPoint("TOPRIGHT", -8, -8)
    toolbar:SetHeight(24)

    local profession = Widgets.CreateDropdown(toolbar, { { text = "All professions", value = nil } },
        function(value)
            state.profession = value
            state.selected = nil
            widgets.list:ScrollToTop()
            Refresh()
        end, { width = 150 })
    profession:SetPoint("LEFT", 0, 0)
    widgets.professionDropdown = profession

    local search = Widgets.CreateSearchBox(toolbar, "Search recipes", function(text)
        state.search = text or ""
        Refresh()
    end)
    search:SetPoint("LEFT", profession, "RIGHT", 8, 0)
    search:SetWidth(170)

    local craftable = Widgets.CreateCheckbox(toolbar, "Craftable now", function(checked)
        state.craftableOnly = checked
        Refresh()
    end, false)
    craftable:SetPoint("LEFT", search, "RIGHT", 12, 0)

    local trivial = Widgets.CreateCheckbox(toolbar, "Show grey", function(checked)
        state.includeTrivial = checked
        Refresh()
    end, false)
    trivial:SetPoint("LEFT", craftable, "RIGHT", 12, 0)

    local skillLabel = Theme.CreateLabel(toolbar, "normal", "accent", "RIGHT")
    skillLabel:SetPoint("RIGHT", 0, 0)
    widgets.skillLabel = skillLabel

    -- Column headings
    local headings = CreateFrame("Frame", nil, container)
    headings:SetPoint("TOPLEFT", toolbar, "BOTTOMLEFT", 0, -8)
    headings:SetPoint("TOPRIGHT", toolbar, "BOTTOMRIGHT", -DETAIL_WIDTH - 8, -8)
    headings:SetHeight(16)

    local nameHeading = Theme.CreateLabel(headings, "tiny", "dim")
    nameHeading:SetPoint("LEFT", 8, 0)
    nameHeading:SetText("RECIPE")

    local labels = { chance = "SKILL UP", cost = "COST", make = "MAKE" }

    local offset = -8
    for _, column in ipairs(COLUMNS) do
        local heading = Theme.CreateLabel(headings, "tiny", "dim", "RIGHT")
        heading:SetText(labels[column.key])
        heading:SetPoint("RIGHT", offset, 0)
        heading:SetWidth(column.width)
        offset = offset - column.width - 6
    end

    local divider = Theme.CreateDivider(container)
    divider:SetPoint("TOPLEFT", headings, "BOTTOMLEFT", 0, -2)
    divider:SetPoint("TOPRIGHT", headings, "BOTTOMRIGHT", 0, -2)

    local list = Widgets.CreateScrollList(container, {
        rowHeight = ROW_HEIGHT,
        createRow = CreateRow,
        updateRow = UpdateRow,

        onEnter = function(row, entry) ShowRowTooltip(row, entry) end,
        onLeave = function() GameTooltip:Hide() end,

        onClick = function(entry, _, mouseButton)
            if mouseButton == "RightButton" then
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
    emptyLabel:SetWidth(340)
    emptyLabel:SetWordWrap(true)
    widgets.emptyLabel = emptyLabel

    local countLabel = Theme.CreateLabel(container, "tiny", "dim")
    countLabel:SetPoint("BOTTOMLEFT", 8, 8)
    widgets.countLabel = countLabel

    local hint = Theme.CreateLabel(container, "tiny", "dim", "RIGHT")
    hint:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", -DETAIL_WIDTH - 16, 8)
    hint:SetText("Right-click a row to queue one")

    local detail = BuildDetail(container)
    detail:SetPoint("TOPRIGHT", container, "TOPRIGHT", -8, -40)
    detail:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", -8, 8)
    widgets.detail = detail

    UpdateDetail(nil)
end

--- Rebuild the profession list, and follow the profession last opened.
local function OnShow()
    wipe(skillLinesByName)
    wipe(nameBySkillLine)

    local options = {}

    for _, recipe in pairs(ns.Recipes:GetAll()) do
        local skillLineID = recipe.skillLineID

        if skillLineID and not nameBySkillLine[skillLineID] then
            local info = ProfessionInfo(skillLineID)
            local name = (info and info.professionName) or ("Skill line " .. skillLineID)

            nameBySkillLine[skillLineID] = name

            if not skillLinesByName[name] then
                skillLinesByName[name] = {}
                options[#options + 1] = { text = name, value = name }
            end

            skillLinesByName[name][skillLineID] = true
        end
    end

    table.sort(options, function(a, b) return a.text < b.text end)
    options[#options + 1] = { text = "All professions", value = nil }

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
    elseif not state.started and options[1] then
        -- No profession opened since this was added: start on the first one
        -- rather than a mix of all of them.
        state.profession = options[1].value
    end

    state.started = true

    dropdown:SetValue(state.profession)
end

UI:RegisterTab({
    key = "levelup",
    text = "Level Up",
    order = 1.5,
    build = Build,
    refresh = Refresh,
    onShow = OnShow,
})
