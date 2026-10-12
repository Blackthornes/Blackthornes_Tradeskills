-- Blackthornes Tradeskills -- UI/Tab_Characters.lua
-- The account-wide rollup: who knows what, who is holding what, and how stale
-- each of those answers is.
--
-- Every figure here except the logged-in character's is a snapshot from the
-- last time that character was played, so the age of the data is shown next to
-- the data itself rather than left to be assumed current.

local _, ns = ...
local L = ns.L or setmetatable({ Format = string.format }, { __index = function(_, key) return key end })

local Theme = ns.Theme
local Widgets = ns.Widgets
local Util = ns.Util

local UI = ns.UI

local ROW_HEIGHT = 40
local DETAIL_WIDTH = 300

local state = { selected = nil, view = "characters" }
local widgets = {}

-- The tab has two views: the characters themselves, and every character's
-- bank in one list (UI/BankView.lua).
local VIEWS = {
    { key = "characters", text = L["CHARACTERS"] },
    { key = "bank",       text = L["BANK"] },
}

--------------------------------------------------------------------------------
-- Rows
--------------------------------------------------------------------------------

local function CreateRow(row)
    row.name = Theme.CreateLabel(row, "normal", "text")
    row.name:SetPoint("TOPLEFT", 10, -6)

    -- The two lines under the name share the row: professions on the left,
    -- how fresh the figures are on the right, each fitted to its own width.
    row.professions = Theme.CreateLabel(row, "tiny", "muted")
    row.professions:SetPoint("TOPLEFT", 10, -22)
    row.professions:SetWidth(420)

    row.gold = Theme.CreateLabel(row, "small", "text", "RIGHT")
    row.gold:SetPoint("TOPRIGHT", -12, -6)
    row.gold:SetWidth(120)

    row.freshness = Theme.CreateLabel(row, "tiny", "dim", "RIGHT")
    row.freshness:SetPoint("TOPRIGHT", -12, -23)
    row.freshness:SetWidth(220)
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

    -- Every profession when they fit, else the first few and how many more
    -- (the row's tooltip lists them all), rather than a line cut off.
    local texts = {}
    for count = #learned, 1, -1 do
        local shown = table.concat(learned, "  ·  ", 1, count)
        texts[#texts + 1] = count < #learned
            and L.Format("%s  ·  +%d more", shown, #learned - count) or shown
    end

    local professions = Theme.FitText(row.professions, #texts > 0 and texts or { L["no professions recorded"] })
    row.professionsCut = #learned > 0 and professions ~= texts[1] and learned or nil

    row.gold:SetText(entry.gold and Util.FormatMoney(entry.gold, { short = true }) or "--")

    if entry.isCurrent then
        row.freshness:SetText(L["this character"])
        row.freshness:SetTextColor(Theme.Unpack("profit"))
    else
        local age = entry.inventoryAt and (time() - entry.inventoryAt)
        local seen = age and L.Format("seen %s", Util.FormatAgeAgo(age)) or L["bags never read"]
        -- Shared from another account of yours (Settings, Sharing).
        if entry.linkedFrom then seen = L.Format("other account  ·  %s", seen) end
        Theme.FitText(row.freshness, { L.Format("%d recipes  ·  %s", entry.recipeCount, seen), seen })
        row.freshness:SetTextColor(Theme.Unpack("dim"))
    end
end

--- A row whose professions did not all fit lists every one of them.
local function ShowRowTooltip(row, entry)
    local learned = rawget(row, "professionsCut")
    if not learned then return end

    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:SetText(entry.name or "", 1, 1, 1)
    for _, line in ipairs(learned) do
        GameTooltip:AddLine(line, 0.7, 0.7, 0.7)
    end
    GameTooltip:Show()
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

    -- Realm, gold and recipes can be wider than the pane; it wraps to a
    -- second line rather than being cut off, and the list below moves down.
    local subtitle = Theme.CreateLabel(detail, "small", "muted")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    subtitle:SetPoint("TOPRIGHT", title, "BOTTOMRIGHT", 0, -4)
    subtitle:SetWordWrap(true)
    detail.subtitle = subtitle

    local heading = Theme.CreateLabel(detail, "tiny", "dim")
    heading:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", 0, -14)
    heading:SetText(L["BEST CRAFTS ON THIS CHARACTER"])
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

    -- Profession cooldowns (Logic/Cooldowns.lua): what is ready, and when
    -- the rest will be. Shown only for a character that has one.
    local cooldownHeading = Theme.CreateLabel(detail, "tiny", "dim")
    cooldownHeading:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -12)
    cooldownHeading:SetText(L["COOLDOWNS"])
    Theme.StyleHeading(cooldownHeading, detail)
    detail.cooldownHeading = cooldownHeading

    detail.cooldowns = {}
    anchor = cooldownHeading
    for index = 1, 3 do
        local line = CreateFrame("Frame", nil, detail)
        line:SetHeight(16)
        line:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, index == 1 and -6 or 0)
        line:SetPoint("TOPRIGHT", detail, "TOPRIGHT", -12, 0)

        line.name = Theme.CreateLabel(line, "small", "text")
        line.name:SetPoint("LEFT", 0, 0)
        line.name:SetPoint("RIGHT", -96, 0)

        line.when = Theme.CreateLabel(line, "small", "muted", "RIGHT")
        line.when:SetPoint("RIGHT", 0, 0)
        line.when:SetWidth(92)

        detail.cooldowns[index] = line
        anchor = line
    end

    detail.dataAge = Theme.CreateLabel(detail, "tiny", "dim")
    detail.dataAge:SetPoint("BOTTOMLEFT", 12, 46)
    detail.dataAge:SetPoint("BOTTOMRIGHT", -12, 46)
    detail.dataAge:SetWordWrap(true)

    -- Removing a character is destructive, so it arms first.
    detail.forget = Widgets.CreateButton(detail, L["Forget character"], function()
        local button = detail.forget
        if not state.selected then return end

        -- Armed for one character only: arming on one alt and clicking again
        -- after selecting another must ask again, not delete the second.
        if button.armed and button.armed == state.selected.key then
            ns.Recipes:ForgetCharacter(state.selected.key)
            button.armed = false
            button:SetText(L["Forget character"])
            button:SetConfirming(false)

            state.selected = nil
            UI:RefreshActiveTab()
            return
        end

        local armedFor = state.selected.key
        button.armed = armedFor
        button:SetText(L["Really forget?"])
        -- Red while armed, like the craft pane's Clear queue.
        button:SetConfirming(true)

        C_Timer.After(4, function()
            if button.armed == armedFor then
                button.armed = false
                button:SetText(L["Forget character"])
                button:SetConfirming(false)
            end
        end)
    end, { width = 140, height = 22,
           tooltip = L["Delete this character's saved recipes and inventory"] })
    detail.forget:SetPoint("BOTTOMLEFT", 12, 14)

    local empty = Theme.CreateLabel(detail, "small", "dim", "CENTER")
    empty:SetPoint("CENTER")
    empty:SetWidth(260)
    empty:SetWordWrap(true)
    empty:SetText(L["Select a character to see what they can make"])
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
        detail.forget:SetText(L["Forget character"])
        detail.forget:SetConfirming(false)
    end

    for _, line in ipairs(detail.lines) do
        line:Hide()
    end
    for _, line in ipairs(detail.cooldowns) do
        line:Hide()
    end
    detail.cooldownHeading:Hide()

    if not shown then return end

    -- Cooldowns take the place of the last crafts, so the pane never grows
    -- into the lines at its foot.
    local cooldowns = ns.Cooldowns and ns.Cooldowns:Groups(entry.key) or {}
    local craftLines = #detail.lines
    if #cooldowns > 0 then
        craftLines = #detail.lines - math.min(#cooldowns, #detail.cooldowns) - 1
    end
    detail.cooldownHeading:SetShown(#cooldowns > 0)
    for index = 1, math.min(#detail.cooldowns, #cooldowns) do
        local group, line = cooldowns[index], detail.cooldowns[index]
        line.name:SetText(group.group)
        if group.ready then
            line.when:SetText(L["Ready"])
            line.when:SetTextColor(Theme.Unpack("profit"))
        else
            line.when:SetText(ns.Cooldowns.LeftText(group.readyAt - time()))
            line.when:SetTextColor(Theme.Unpack("muted"))
        end
        line:Show()
    end

    detail.title:SetText(entry.name)
    detail.subtitle:SetText(L.Format("%s  ·  %s  ·  %d recipes",
        entry.realm or "?",
        entry.gold and Util.FormatMoney(entry.gold, { short = true }) or L["unknown gold"],
        entry.recipeCount))

    -- Rank this character's own recipes, against their own bags.
    local record = ns.db.characters[entry.key]
    local ranked = {}

    -- Crafts of a profession the character dropped are left out, as the
    -- Profit tab leaves them out: kept in the saved data, but not makeable.
    for recipeID, recipe in pairs((record and record.recipes) or {}) do
        if not ns.Recipes:IsDropped(recipe, entry.key) then
            local analysis = ns.Profit:Analyse(recipeID, entry.key)
            if analysis and analysis.priceable then
                ranked[#ranked + 1] = analysis
            end
        end
    end

    -- Ties settled by name, then recipe: crafts with equal profit swapped
    -- places on every redraw.
    table.sort(ranked, function(a, b)
        if a.profit ~= b.profit then return a.profit > b.profit end
        if (a.name or "") ~= (b.name or "") then return (a.name or "") < (b.name or "") end
        return (a.recipeID or 0) < (b.recipeID or 0)
    end)

    if #ranked == 0 then
        detail.lines[1]:Show()
        -- A character with no recipes read needs a profession window
        -- opened, not a scan.
        detail.lines[1].name:SetText((entry.recipeCount or 0) == 0
            and L["No recipes read. Open a profession."]
            or L["Nothing with a price yet"])
        detail.lines[1].name:SetTextColor(Theme.Unpack("dim"))
        detail.lines[1].profit:SetText("")
    else
        for index = 1, math.min(craftLines, #ranked) do
            local analysis = ranked[index]
            local line = detail.lines[index]

            line.name:SetText(analysis.name or "?")
            line.name:SetTextColor(Theme.Unpack(
                analysis.craftableNow > 0 and "text" or "muted"))

            -- Measured into its narrow column, which "4g 12s 38c" overran.
            Theme.SetMoneyText(line.profit, analysis.profit, { short = true })
            line.profit:SetTextColor(Theme.ProfitColor(analysis.profit))
            line:Show()
        end
    end

    -- Under the last craft shown.
    local shownCrafts = 1
    for index, line in ipairs(detail.lines) do
        if line:IsShown() then shownCrafts = index end
    end
    detail.cooldownHeading:ClearAllPoints()
    detail.cooldownHeading:SetPoint("TOPLEFT", detail.lines[shownCrafts], "BOTTOMLEFT", 0, -12)

    if entry.isCurrent then
        detail.dataAge:SetText(L["Live data for the character you are playing."])
    else
        local inventoryAge = entry.inventoryAt and (time() - entry.inventoryAt)
        local bankAge = entry.bankAt and (time() - entry.bankAt)

        detail.dataAge:SetText(L.Format("Bags read %s. Bank read %s. Figures are from the last time this character was played.",
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
        widgets.emptyLabel:SetText(L["No characters recorded yet."])
    end

    local totalGold, totalRecipes = 0, 0
    for _, entry in ipairs(characters) do
        totalGold = totalGold + (entry.gold or 0)
        totalRecipes = totalRecipes + entry.recipeCount
    end

    if #characters == 1 then
        widgets.summary:SetText(L.Format("%d character  ·  %s recipes known  ·  %s total",
            #characters, Util.Comma(totalRecipes), Util.FormatMoney(totalGold, { short = true })))
    else
        widgets.summary:SetText(L.Format("%d characters  ·  %s recipes known  ·  %s total",
            #characters, Util.Comma(totalRecipes), Util.FormatMoney(totalGold, { short = true })))
    end

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
    -- Across the top like every tab's option bar, over the detail panel.
    rule:SetPoint("RIGHT", container, "RIGHT", -8, 0)

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

        onEnter = ShowRowTooltip,
        onLeave = function() GameTooltip:Hide() end,
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
    detail:SetPoint("TOPRIGHT", container, "TOPRIGHT", -8, -40)
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
    text = L["Characters"],
    order = 7,
    build = Build,
    refresh = Refresh,
})
