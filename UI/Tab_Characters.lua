-- Blackthornes Tradeskills -- UI/Tab_Characters.lua
-- The account-wide rollup: who knows what, who is holding what, and how stale
-- each of those answers is.
--
-- Every figure here except the logged-in character's is a snapshot from the
-- last time that character was played, so the age of the data is shown next to
-- the data itself rather than left to be assumed current.

local _, ns = ...

local Theme = ns.Theme
local Widgets = ns.Widgets
local Util = ns.Util

local UI = ns.UI

local ROW_HEIGHT = 40
local DETAIL_WIDTH = 320

local state = { selected = nil, view = "characters" }
local widgets = {}

-- The tab has two views: the characters themselves, and every character's
-- bank in one list (UI/BankView.lua).
local VIEWS = {
    { key = "characters", text = "CHARACTERS" },
    { key = "bank",       text = "BANK" },
}

--------------------------------------------------------------------------------
-- Rows
--------------------------------------------------------------------------------

local function CreateRow(row)
    row.name = Theme.CreateLabel(row, "normal", "text")
    row.name:SetPoint("TOPLEFT", 10, -6)

    row.professions = Theme.CreateLabel(row, "tiny", "muted")
    row.professions:SetPoint("TOPLEFT", 10, -22)
    row.professions:SetWidth(280)

    row.gold = Theme.CreateLabel(row, "small", "text", "RIGHT")
    row.gold:SetPoint("TOPRIGHT", -12, -6)
    row.gold:SetWidth(120)

    row.freshness = Theme.CreateLabel(row, "tiny", "dim", "RIGHT")
    row.freshness:SetPoint("TOPRIGHT", -12, -23)
    row.freshness:SetWidth(160)
end

local function UpdateRow(row, entry)
    row.name:SetText(entry.name)
    row.name:SetTextColor(Theme.Unpack(entry.isCurrent and "accent" or "text"))

    local learned = {}
    for _, profession in ipairs(entry.professions or {}) do
        if profession.learned then
            learned[#learned + 1] = ("%s %d"):format(profession.name, profession.skillLevel or 0)
        end
    end

    row.professions:SetText(#learned > 0
        and table.concat(learned, "  ·  ")
        or "no professions recorded")

    row.gold:SetText(entry.gold and Util.FormatMoney(entry.gold, { short = true }) or "--")

    if entry.isCurrent then
        row.freshness:SetText("this character")
        row.freshness:SetTextColor(Theme.Unpack("profit"))
    else
        local age = entry.inventoryAt and (time() - entry.inventoryAt)
        row.freshness:SetText(age
            and ("%d recipes  ·  seen %s"):format(entry.recipeCount, Util.FormatAgeAgo(age))
            or ("%d recipes  ·  bags never read"):format(entry.recipeCount))
        row.freshness:SetTextColor(Theme.Unpack("dim"))
    end
end

--------------------------------------------------------------------------------
-- Detail
--------------------------------------------------------------------------------

local function BuildDetail(parent)
    local detail = Theme.CreatePanel(parent, "window")
    -- The gold edge every other detail pane has.
    Theme.AccentStripe(detail, 2, 0.6)
    detail:SetWidth(DETAIL_WIDTH)

    local title = Theme.CreateLabel(detail, "large", "accent")
    title:SetPoint("TOPLEFT", 12, -12)
    title:SetPoint("TOPRIGHT", -12, -12)
    detail.title = title

    local subtitle = Theme.CreateLabel(detail, "small", "muted")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    subtitle:SetPoint("TOPRIGHT", title, "BOTTOMRIGHT", 0, -4)
    detail.subtitle = subtitle

    local heading = Theme.CreateLabel(detail, "tiny", "dim")
    heading:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", 0, -14)
    heading:SetText("BEST CRAFTS ON THIS CHARACTER")
    Theme.StyleHeading(heading, detail)
    detail.heading = heading

    detail.lines = {}
    local anchor = heading

    for index = 1, 8 do
        local line = CreateFrame("Frame", nil, detail)
        line:SetHeight(16)
        line:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, index == 1 and -6 or 0)
        line:SetPoint("TOPRIGHT", detail, "TOPRIGHT", -12, 0)

        line.name = Theme.CreateLabel(line, "small", "text")
        line.name:SetPoint("LEFT", 0, 0)
        line.name:SetPoint("RIGHT", -74, 0)

        line.profit = Theme.CreateLabel(line, "small", "profit", "RIGHT")
        line.profit:SetPoint("RIGHT", 0, 0)
        line.profit:SetWidth(70)

        detail.lines[index] = line
        anchor = line
    end

    detail.dataAge = Theme.CreateLabel(detail, "tiny", "dim")
    detail.dataAge:SetPoint("BOTTOMLEFT", 12, 46)
    detail.dataAge:SetPoint("BOTTOMRIGHT", -12, 46)
    detail.dataAge:SetWordWrap(true)

    -- Removing a character is destructive, so it arms first.
    detail.forget = Widgets.CreateButton(detail, "Forget character", function()
        local button = detail.forget
        if not state.selected then return end

        -- Armed for one character only: arming on one alt and clicking again
        -- after selecting another must ask again, not delete the second.
        if button.armed and button.armed == state.selected.key then
            ns.Recipes:ForgetCharacter(state.selected.key)
            button.armed = false
            button:SetText("Forget character")
            button:SetConfirming(false)

            state.selected = nil
            UI:RefreshActiveTab()
            return
        end

        local armedFor = state.selected.key
        button.armed = armedFor
        button:SetText("Really forget?")
        -- Red while armed, like the craft pane's Clear queue.
        button:SetConfirming(true)

        C_Timer.After(4, function()
            if button.armed == armedFor then
                button.armed = false
                button:SetText("Forget character")
                button:SetConfirming(false)
            end
        end)
    end, { width = 140, height = 22,
           tooltip = "Delete this character's saved recipes and inventory" })
    detail.forget:SetPoint("BOTTOMLEFT", 12, 14)

    local empty = Theme.CreateLabel(detail, "small", "dim", "CENTER")
    empty:SetPoint("CENTER")
    empty:SetWidth(260)
    empty:SetWordWrap(true)
    empty:SetText("Select a character to see what they can make")
    detail.empty = empty

    return detail
end

local function UpdateDetail(entry)
    local detail = widgets.detail
    local shown = entry ~= nil

    detail.empty:SetShown(not shown)
    detail.title:SetShown(shown)
    detail.subtitle:SetShown(shown)
    detail.heading:SetShown(shown)
    detail.dataAge:SetShown(shown)

    -- Only an alt can be forgotten; you cannot discard the character you are on.
    detail.forget:SetShown(shown and not entry.isCurrent)

    -- Showing another character disarms the button.
    if detail.forget.armed and (not entry or detail.forget.armed ~= entry.key) then
        detail.forget.armed = false
        detail.forget:SetText("Forget character")
        detail.forget:SetConfirming(false)
    end

    for _, line in ipairs(detail.lines) do
        line:Hide()
    end

    if not shown then return end

    detail.title:SetText(entry.name)
    detail.subtitle:SetText(("%s  ·  %s  ·  %d recipes"):format(
        entry.realm or "?",
        entry.gold and Util.FormatMoney(entry.gold, { short = true }) or "unknown gold",
        entry.recipeCount))

    -- Rank this character's own recipes, against their own bags.
    local record = ns.db.characters[entry.key]
    local ranked = {}

    for recipeID in pairs((record and record.recipes) or {}) do
        local analysis = ns.Profit:Analyse(recipeID, entry.key)
        if analysis and analysis.priceable then
            ranked[#ranked + 1] = analysis
        end
    end

    table.sort(ranked, function(a, b) return a.profit > b.profit end)

    if #ranked == 0 then
        detail.lines[1]:Show()
        -- A character with no recipes read needs a profession window
        -- opened, not a scan.
        detail.lines[1].name:SetText((entry.recipeCount or 0) == 0
            and "No recipes read. Open a profession."
            or "Nothing with a price yet")
        detail.lines[1].name:SetTextColor(Theme.Unpack("dim"))
        detail.lines[1].profit:SetText("")
    else
        for index = 1, math.min(#detail.lines, #ranked) do
            local analysis = ranked[index]
            local line = detail.lines[index]

            line.name:SetText(analysis.name or "?")
            line.name:SetTextColor(Theme.Unpack(
                analysis.craftableNow > 0 and "text" or "muted"))

            line.profit:SetText(Util.FormatMoney(analysis.profit, { short = true }))
            line.profit:SetTextColor(Theme.ProfitColor(analysis.profit))
            line:Show()
        end
    end

    if entry.isCurrent then
        detail.dataAge:SetText("Live data for the character you are playing.")
    else
        local inventoryAge = entry.inventoryAt and (time() - entry.inventoryAt)
        local bankAge = entry.bankAt and (time() - entry.bankAt)

        detail.dataAge:SetText(("Bags read %s. Bank read %s. Figures are from the last time this character was played."):format(
            Util.FormatAgeAgo(inventoryAge),
            Util.FormatAgeAgo(bankAge)))
    end
end

--------------------------------------------------------------------------------
-- Refresh
--------------------------------------------------------------------------------

local function RefreshCharacters()
    if not widgets.list then return end

    local characters = ns.Recipes:GetCharacters()
    widgets.list:SetData(characters)

    widgets.emptyLabel:SetShown(#characters == 0)
    if #characters == 0 then
        widgets.emptyLabel:SetText("No characters recorded yet.")
    end

    local totalGold, totalRecipes = 0, 0
    for _, entry in ipairs(characters) do
        totalGold = totalGold + (entry.gold or 0)
        totalRecipes = totalRecipes + entry.recipeCount
    end

    widgets.summary:SetText(("%d character%s  ·  %s recipes known  ·  %s total"):format(
        #characters, #characters == 1 and "" or "s",
        Util.Comma(totalRecipes), Util.FormatMoney(totalGold, { short = true })))

    -- Keep the detail on the same character across refreshes.
    if state.selected then
        for _, entry in ipairs(characters) do
            if entry.key == state.selected.key then
                state.selected = entry
                UpdateDetail(entry)
                return
            end
        end
        state.selected = nil
    end

    UpdateDetail(nil)
end

--------------------------------------------------------------------------------
-- Build
--------------------------------------------------------------------------------

local function Refresh()
    if state.view == "bank" then
        if ns.BankView then ns.BankView.Refresh() end
    else
        RefreshCharacters()
    end
end

--- Show one of the two views and paint the switch to match.
local function ShowView(key)
    if not widgets.views then
        state.view = key
        return
    end

    state.view = widgets.views[key] and key or "characters"

    for viewKey, view in pairs(widgets.views) do
        view:SetShown(viewKey == state.view)
    end

    for _, button in ipairs(widgets.switch) do
        local active = button.key == state.view
        button.label:SetTextColor(Theme.Unpack(active and "accent" or "muted"))
        button.underline:SetShown(active)
    end

    Refresh()
end

ns.CharactersTab = { ShowView = ShowView }

--- CHARACTERS | BANK, drawn as the tab's heading: the view showing is lit
--- gold and underlined, the other waits in grey.
local function BuildSwitch(container)
    local buttons = {}
    local previous

    for _, definition in ipairs(VIEWS) do
        local button = CreateFrame("Button", nil, container)
        button:SetHeight(18)
        button:SetFrameLevel(container:GetFrameLevel() + 5)

        button.label = Theme.CreateLabel(button, "tiny", "muted")
        button.label:SetPoint("LEFT", 0, 0)
        button.label:SetText(definition.text)
        button:SetWidth(button.label:GetStringWidth() + 4)

        button.underline = button:CreateTexture(nil, "OVERLAY")
        button.underline:SetPoint("BOTTOMLEFT", 0, 1)
        button.underline:SetPoint("BOTTOMRIGHT", -4, 1)
        button.underline:SetHeight(1)
        button.underline:SetColorTexture(Theme.Unpack("accent"))
        button.underline:Hide()

        button.key = definition.key

        if previous then
            button:SetPoint("LEFT", previous, "RIGHT", 14, 0)
        else
            button:SetPoint("TOPLEFT", 8, -5)
        end

        button:SetScript("OnClick", function(self) ShowView(self.key) end)
        button:SetScript("OnEnter", function(self)
            if self.key ~= state.view then
                self.label:SetTextColor(Theme.Unpack("text"))
            end
        end)
        button:SetScript("OnLeave", function(self)
            if self.key ~= state.view then
                self.label:SetTextColor(Theme.Unpack("muted"))
            end
        end)

        buttons[#buttons + 1] = button
        previous = button
    end

    local rule = container:CreateTexture(nil, "ARTWORK")
    rule:SetColorTexture(Theme.Unpack("border"))
    rule:SetHeight(1)
    rule:SetPoint("LEFT", previous, "RIGHT", 6, 0)
    rule:SetPoint("RIGHT", container, "RIGHT", -DETAIL_WIDTH - 16, 0)

    return buttons
end

local function BuildCharacters(container)
    local divider = Theme.CreateDivider(container)
    divider:SetPoint("TOPLEFT", 8, -26)
    divider:SetPoint("TOPRIGHT", container, "TOPRIGHT", -DETAIL_WIDTH - 16, -26)
    -- Kept as the list's anchor; the view switch carries the house rule.
    divider:Hide()

    local list = Widgets.CreateScrollList(container, {
        rowHeight = ROW_HEIGHT,
        createRow = CreateRow,
        updateRow = UpdateRow,
        -- The row the detail pane is showing stays lit.
        isSelected = function(entry)
            return state.selected ~= nil and entry.key == state.selected.key
        end,

        onClick = function(entry)
            state.selected = entry
            UpdateDetail(entry)
        end,
    })
    list:SetPoint("TOPLEFT", divider, "BOTTOMLEFT", 0, -4)
    list:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", -DETAIL_WIDTH - 16, 28)
    widgets.list = list

    local emptyLabel = Theme.CreateLabel(container, "small", "dim", "CENTER")
    emptyLabel:SetPoint("CENTER", list, "CENTER")
    emptyLabel:SetWidth(320)
    emptyLabel:SetWordWrap(true)
    widgets.emptyLabel = emptyLabel

    local summary = Theme.CreateLabel(container, "small", "text")
    summary:SetPoint("BOTTOMLEFT", 8, 10)
    widgets.summary = summary

    local detail = BuildDetail(container)
    detail:SetPoint("TOPRIGHT", container, "TOPRIGHT", -8, -8)
    detail:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", -8, 8)
    widgets.detail = detail

    UpdateDetail(nil)
end

local function Build(container)
    local views = {}

    for _, definition in ipairs(VIEWS) do
        local view = CreateFrame("Frame", nil, container)
        view:SetAllPoints(container)
        view:Hide()
        views[definition.key] = view
    end

    BuildCharacters(views.characters)
    if ns.BankView then ns.BankView.Build(views.bank) end

    widgets.views = views
    widgets.switch = BuildSwitch(container)

    ShowView(state.view)
end

UI:RegisterTab({
    key = "characters",
    text = "Characters",
    order = 7,
    build = Build,
    refresh = Refresh,
})
