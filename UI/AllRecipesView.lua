-- Blackthornes Tradeskills -- UI/AllRecipesView.lua
-- The All Recipes view on the Profit tab (a player asked, the owner said
-- build it from a mockup, 2026-11-17): every recipe you know in one list,
-- grey, money-losing, unpriced and ignored ones too. Keep in Stock and
-- Ignore change right in the row. Nothing new is saved: KEEP writes the
-- same number as the Profit detail pane (ns.Auctions:SetLimit) and IGNORE
-- the same list Settings shows (ns.Profit:SetIgnored).

local _, ns = ...
local L = ns.L or setmetatable({ Format = string.format }, { __index = function(_, key) return key end })

local Theme = ns.Theme
local Widgets = ns.Widgets
local Util = ns.Util

local AllRecipesView = {}
ns.AllRecipesView = AllRecipesView

local ROW_HEIGHT = 24
local DOT_SIZE = 8
local ICON_SIZE = 16
local NAME_LEFT = 8 + DOT_SIZE + 6 + ICON_SIZE + 6
local DIMMED = 0.42
local ROUND = [[Interface\CharacterFrame\TempPortraitAlphaMask]]

-- Right to left, measured from the list's right edge. `width` is the
-- least each gets: Widgets.FitColumns widens it to fit its heading.
local COLUMNS = {
    { key = "ignore",     label = L["IGNORE"],     width = 50,  justify = "CENTER" },
    { key = "profit",     label = L["PROFIT"],     width = 84,  money = true },
    { key = "keep",       label = L["KEEP"],       width = 70,  justify = "CENTER" },
    { key = "have",       label = L["HAVE"],       width = 50,  justify = "CENTER" },
    { key = "listed",     label = L["LISTED"],     width = 56,  justify = "CENTER" },
    { key = "profession", label = L["PROFESSION"], width = 110, justify = "CENTER" },
}

local state = {
    search = "",
    profession = nil,
    hideIgnored = false,
    hideGrey = false,
    accountWide = false,
}
local widgets = {}

AllRecipesView._state = state
AllRecipesView._widgets = widgets
AllRecipesView.COLUMNS = COLUMNS

local awaitingItemData = false

--------------------------------------------------------------------------------
-- Rows
--------------------------------------------------------------------------------

--- A profession's name for a skill line, as the client shows it. Forever
--- gives each profession two skill lines, so the list goes by this name,
--- never by the line.
local professionNames = {}
function AllRecipesView.ProfessionName(skillLineID)
    if skillLineID == nil then return "" end
    local known = professionNames[skillLineID]
    if known then return known end

    local name
    local lines = ns.Recipes and ns.Recipes.SKILL_LINE_PROFESSIONS
    local english = type(lines) == "table" and lines[skillLineID] or nil
    if english and ns.Auctions and ns.Auctions.ProfessionLabel then
        name = ns.Auctions:ProfessionLabel(english)
    end
    if not name and Util.HasFunction and Util.HasFunction("C_TradeSkillUI.GetProfessionInfoBySkillLineID") then
        local ok, info = pcall(C_TradeSkillUI.GetProfessionInfoBySkillLineID, skillLineID)
        if ok and type(info) == "table" and type(info.professionName) == "string" and info.professionName ~= "" then
            name = info.professionName
        end
    end
    name = name or L.Format("Skill line %s", skillLineID)
    professionNames[skillLineID] = name
    return name
end

--- The skill-up colour a recipe shows, or nil when it was never read.
local function Tier(analysis)
    return analysis.skillUp and analysis.skillUp.tier or nil
end

--- The Keep in Stock number a row stands for: its own, else the usual one.
function AllRecipesView.KeepValue(analysis)
    if not analysis.outputItemID or not ns.StockBox then return nil end
    return ns.StockBox.Own(analysis.outputItemID) or (ns.StockBox.Usual(analysis.outputItemID))
end

--- Every known recipe, with the filters above, as Profit analyses with a
--- few more fields: ignored, grey, professionName and have.
-- @return rows, how many of them are ignored, every profession name seen
function AllRecipesView.Rows()
    local Profit = ns.Profit
    local ranked = Profit:GetRanked({
        accountWide = state.accountWide,
        includeIgnored = true,
        includeUnpriceable = true,
        ignorePostLimit = true,
        ignoreStock = true,
        minProfit = -math.huge,
        minMargin = -math.huge,
        sortBy = "profit",
        method = Profit.GetMethod and Profit:GetMethod() or nil,
    })

    local needle = (state.search or ""):lower()
    local rows, ignored, professions = {}, 0, {}

    for _, analysis in ipairs(ranked) do
        analysis.ignored = Profit:IsIgnored(analysis.recipeID) or nil
        analysis.grey = Tier(analysis) == "trivial" or nil
        analysis.professionName = AllRecipesView.ProfessionName(analysis.skillLineID)
        analysis.have = analysis.outputItemID and ((analysis.onHand or 0) + (analysis.inMail or 0)) or nil
        -- Each name seen, with its English name for the shared pick.
        professions[analysis.professionName] = professions[analysis.professionName]
            or (Profit.ProfessionOfLine and Profit.ProfessionOfLine(analysis.skillLineID)) or true
    end

    -- A profession with no recipes here (picked on another view, or gone
    -- with All Characters unticked) shows them all.
    if state.profession and not professions[state.profession] then state.profession = nil end

    for _, analysis in ipairs(ranked) do
        local keep = true
        if state.profession and analysis.professionName ~= state.profession then keep = false end
        if keep and state.hideIgnored and analysis.ignored then keep = false end
        if keep and state.hideGrey and analysis.grey then keep = false end
        if keep and needle ~= "" and not (analysis.name or ""):lower():find(needle, 1, true) then keep = false end

        if keep then
            rows[#rows + 1] = analysis
            if analysis.ignored then ignored = ignored + 1 end
        end
    end

    return rows, ignored, professions
end

local function ShowKeepTip(owner)
    local row = owner.row
    local analysis = row and row.data
    if not (GameTooltip and analysis and analysis.outputItemID and ns.StockBox) then return end
    GameTooltip:SetOwner(owner, "ANCHOR_TOP")
    GameTooltip:SetText(L["Keep in Stock"], Theme.Unpack("accent"))
    GameTooltip:AddLine(ns.StockBox.SourceTip(analysis.outputItemID), 1, 1, 1, true)
    GameTooltip:AddLine(L["Enter saves. Esc puts it back."], Theme.Unpack("dim"))
    GameTooltip:Show()
end

local function HideTip()
    if GameTooltip then GameTooltip:Hide() end
end

local function PlaceRow(row)
    local offset = -8
    for _, column in ipairs(COLUMNS) do
        local cell = row.cells[column.key]
        cell:ClearAllPoints()
        cell:SetPoint("RIGHT", row, "RIGHT", offset, 0)
        cell:SetWidth(column.width)
        if column.key == "keep" then
            row.keep:ClearAllPoints()
            row.keep:SetPoint("CENTER", cell, "CENTER", 0, 0)
        elseif column.key == "ignore" then
            row.ignore:ClearAllPoints()
            row.ignore:SetPoint("CENTER", cell, "CENTER", 7, 0)
        end
        offset = offset - column.width - 6
    end
    row.name:SetPoint("RIGHT", row, "RIGHT", offset - 4, 0)
end

local function CreateRow(row)
    row.dot = row:CreateTexture(nil, "ARTWORK")
    row.dot:SetSize(DOT_SIZE, DOT_SIZE)
    row.dot:SetPoint("LEFT", 8, 0)
    pcall(row.dot.SetTexture, row.dot, ROUND)

    row.icon = Theme.CreateItemIcon(row, ICON_SIZE)
    row.icon:SetPoint("LEFT", 8 + DOT_SIZE + 6, 0)

    row.name = Theme.CreateLabel(row, "small", "text")
    row.name:SetPoint("LEFT", NAME_LEFT, 0)
    row.name:SetJustifyH("LEFT")

    row.cells = {}
    for _, column in ipairs(COLUMNS) do
        local cell = Theme.CreateLabel(row, "small", "text", column.justify or "RIGHT")
        cell:SetWordWrap(false)
        row.cells[column.key] = cell
    end

    -- KEEP: the item's own number in gold, else empty with the usual
    -- number greyed in it. Enter saves, Esc puts it back.
    row.keep = Widgets.CreateNumberBox(row, {
        width = 40, height = 18, min = 0, max = 999, justify = "CENTER",
        allowEmpty = true, placeholder = "",
        onChange = function(value)
            local analysis = row.data
            if analysis and analysis.outputItemID and ns.StockBox then
                ns.StockBox.Write(analysis.outputItemID, value)
            end
        end,
    })
    row.keep.row = row
    row.keep.editBox.row = row
    for _, target in ipairs({ row.keep, row.keep.editBox }) do
        if target.HookScript then
            target:HookScript("OnEnter", ShowKeepTip)
            target:HookScript("OnLeave", HideTip)
        end
    end

    -- The x beside an item's own number puts the usual one back.
    row.keepClear = Widgets.CreateButton(row, "x", function()
        local analysis = row.data
        if analysis and analysis.outputItemID and ns.StockBox then
            ns.StockBox.Write(analysis.outputItemID, nil)
        end
    end, { width = 14, height = 14, tooltip = L["Use the usual number again"] })
    row.keepClear:SetPoint("LEFT", row.keep, "RIGHT", 2, 0)
    row.keepClear:Hide()

    row.ignore = Widgets.CreateCheckbox(row, "", function(checked)
        local analysis = row.data
        if analysis then ns.Profit:SetIgnored(analysis.recipeID, checked, analysis.name) end
    end, false)
    row.ignore:SetWidth(18)
    if row.ignore.HookScript then
        row.ignore:HookScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(L["Ticked: you won't see it on My Crafts or in the craft pane. Untick to bring it back."], 1, 1, 1, 1, true)
            GameTooltip:Show()
        end)
        row.ignore:HookScript("OnLeave", HideTip)
    end

    PlaceRow(row)
end

--- Fill the KEEP cell. A number being typed is left alone: a redraw
--- mid-typing would put the old number back under the next key.
local function UpdateKeep(row, analysis)
    local cell, box = row.cells.keep, row.keep
    local itemID = analysis.outputItemID
    if not itemID or not ns.StockBox then
        box:Hide()
        row.keepClear:Hide()
        cell:SetText(L["No Item"])
        cell:SetTextColor(Theme.Unpack("dim"))
        row.keepFor = nil
        return
    end

    cell:SetText("")
    box:Show()
    local own = ns.StockBox.Own(itemID)
    local typing = box.editBox.HasFocus and box.editBox:HasFocus()
    if not (typing and row.keepFor == itemID) then
        box:SetPlaceholder(tostring(ns.StockBox.Usual(itemID)))
        box:SetValue(own, true)
    end
    row.keepFor = itemID
    box.editBox:SetTextColor(Theme.Unpack(own and "accentHi" or "dim"))
    Theme.SetBorderColor(box, own and "accent" or "border")
    row.keepClear:SetShown(own ~= nil)
end

local function UpdateRow(row, analysis)
    local name = analysis.name or L.Format("recipe %s", analysis.recipeID)
    Theme.SetRowName(row.name, name)
    Theme.SetItemIcon(row.icon, analysis.outputItemID)

    local r, g, b = Util.GetItemQualityColor(analysis.outputItemID)
    if r then
        row.name:SetTextColor(r, g, b)
    else
        row.name:SetTextColor(Theme.Unpack("text"))
        if analysis.outputItemID then awaitingItemData = true end
    end

    -- The skill-up colour, as the profession window shows it.
    local tier = Tier(analysis)
    if tier and ns.SkillUp and ns.SkillUp.GetTierColor then
        row.dot:SetVertexColor(ns.SkillUp:GetTierColor(tier))
        row.dot:Show()
    else
        row.dot:Hide()
    end

    local cells = row.cells
    cells.profession:SetText(analysis.professionName or "")
    cells.profession:SetTextColor(Theme.Unpack("text"))

    if analysis.outputItemID then
        cells.listed:SetText(tostring(analysis.posted or 0))
        cells.have:SetText(tostring(analysis.have or 0))
        cells.listed:SetTextColor(Theme.Unpack("text"))
        cells.have:SetTextColor(Theme.Unpack("text"))
    else
        cells.listed:SetText("-")
        cells.have:SetText("-")
        cells.listed:SetTextColor(Theme.Unpack("dim"))
        cells.have:SetTextColor(Theme.Unpack("dim"))
    end

    UpdateKeep(row, analysis)

    if analysis.priceable then
        Theme.SetMoneyText(cells.profit, analysis.profit, { short = true })
        cells.profit:SetTextColor(Theme.ProfitColor(analysis.profit))
    else
        cells.profit:SetText(analysis.soulbound and L["soulbound"] or L["No Price"])
        cells.profit:SetTextColor(Theme.Unpack("dim"))
    end

    row.ignore:SetChecked(analysis.ignored)

    -- An ignored recipe is dimmed, all but its tick box.
    local alpha = analysis.ignored and DIMMED or 1
    row.name:SetAlpha(alpha)
    row.icon:SetAlpha(alpha)
    row.dot:SetAlpha(alpha)
    row.keep:SetAlpha(alpha)
    row.keepClear:SetAlpha(alpha)
    for _, cell in pairs(cells) do cell:SetAlpha(alpha) end
    row.ignore:SetAlpha(1)
end

--------------------------------------------------------------------------------
-- Refresh
--------------------------------------------------------------------------------

--- Take the profession picked on My Crafts or Recipes to Learn
--- (Profit.PickProfession), once per pick, by the name this list shows.
local function AdoptPickedProfession()
    local Profit = ns.Profit
    if not (Profit and Profit.PickedProfession) then return end
    local version, english = Profit.PickedProfession()
    if version == (state.pickSeen or 0) then return end
    state.pickSeen = version

    local name
    local lines = english and ns.Recipes and ns.Recipes.SKILL_LINE_PROFESSIONS
    if type(lines) == "table" then
        for skillLineID, line in pairs(lines) do
            if line == english then name = AllRecipesView.ProfessionName(skillLineID); break end
        end
    end
    state.profession = name
    if widgets.professionDropdown then widgets.professionDropdown:SetValue(name) end
end

local function RefreshProfessions(professions)
    local dropdown = widgets.professionDropdown
    if not dropdown then return end

    local names = {}
    for name in pairs(professions) do names[#names + 1] = name end
    table.sort(names)

    local key = table.concat(names, "|")
    if key ~= widgets.professionKey then
        widgets.professionKey = key
        local options = { { text = L["All professions"], value = nil } }
        for _, name in ipairs(names) do options[#options + 1] = { text = name, value = name } end
        dropdown:SetOptions(options)
        if state.profession and not professions[state.profession] then state.profession = nil end
        dropdown:SetValue(state.profession)
    elseif dropdown:GetValue() ~= state.profession then
        dropdown:SetValue(state.profession)
    end
end

function AllRecipesView.Refresh()
    if not widgets.list then return end

    AdoptPickedProfession()
    local rows, ignored, professions = AllRecipesView.Rows()
    widgets.professionEnglish = professions
    RefreshProfessions(professions)

    if widgets.sorter then rows = widgets.sorter:Sort(rows) end

    awaitingItemData = false
    widgets.list:SetData(rows)

    widgets.emptyLabel:SetShown(#rows == 0)
    if Widgets.EmptyAction then Widgets.EmptyAction(widgets.emptyLabel, nil) end
    if #rows == 0 then
        if ns.Recipes:Count() == 0 then
            widgets.emptyLabel:SetText(L["Open a profession window once so your recipes can be read."])
        elseif state.search ~= "" then
            widgets.emptyLabel:SetText(L.Format("Nothing matching \"%s\".", state.search))
            if Widgets.EmptyAction then
                Widgets.EmptyAction(widgets.emptyLabel, L["Clear Search"], function() widgets.search:SetText("") end)
            end
        else
            widgets.emptyLabel:SetText(L["Nothing matches these filters."])
        end
    end

    widgets.countLabel:SetText(L.Format("%d recipes. %d ignored. Click a heading to sort.", #rows, ignored))
end

--------------------------------------------------------------------------------
-- Build
--------------------------------------------------------------------------------

function AllRecipesView.Build(container)
    if Widgets.FitColumns then Widgets.FitColumns(COLUMNS) end

    -- Dropdowns, then search, then tick boxes (the house option bar).
    local toolbar = CreateFrame("Frame", nil, container)
    toolbar:SetPoint("TOPLEFT", 8, -8)
    toolbar:SetPoint("TOPRIGHT", -8, -8)
    toolbar:SetHeight(24)

    local profession = Widgets.CreateDropdown(toolbar, { { text = L["All professions"], value = nil } },
        function(value)
            state.profession = value
            -- My Crafts and Recipes to Learn follow (2026-11-27).
            local Profit = ns.Profit
            local english = value and widgets.professionEnglish and widgets.professionEnglish[value]
            if Profit and Profit.PickProfession and (value == nil or type(english) == "string") then
                Profit.PickProfession(english)
                state.pickSeen = (Profit.PickedProfession())
            end
            AllRecipesView.Refresh()
        end)
    profession:SetPoint("LEFT", 0, 0)
    widgets.professionDropdown = profession

    local search = Widgets.CreateSearchBox(toolbar, L["Search recipes"], function(text)
        state.search = text or ""
        AllRecipesView.Refresh()
    end)
    search:SetPoint("LEFT", profession, "RIGHT", 8, 0)
    search:SetWidth(Widgets.SEARCH_WIDTH)
    widgets.search = search

    local hideIgnored = Widgets.CreateCheckbox(toolbar, L["Hide Ignored:"], function(checked)
        state.hideIgnored = checked
        AllRecipesView.Refresh()
    end, false)
    hideIgnored:SetPoint("LEFT", search, "RIGHT", 12, 0)

    local hideGrey = Widgets.CreateCheckbox(toolbar, L["Hide Grey:"], function(checked)
        state.hideGrey = checked
        AllRecipesView.Refresh()
    end, false)
    hideGrey:SetPoint("LEFT", hideIgnored, "RIGHT", 12, 0)

    local accountWide = Widgets.CreateCheckbox(toolbar, L["All characters"], function(checked)
        state.accountWide = checked
        AllRecipesView.Refresh()
    end, false)
    accountWide:SetPoint("RIGHT", toolbar, "RIGHT", 0, 0)

    -- Headings
    local headings = CreateFrame("Frame", nil, container)
    headings:SetPoint("TOPLEFT", toolbar, "BOTTOMLEFT", 0, -8)
    headings:SetPoint("TOPRIGHT", toolbar, "BOTTOMRIGHT", 0, -8)
    headings:SetHeight(16)

    local nameHeading = Theme.CreateLabel(headings, "tiny", "muted")
    nameHeading:SetPoint("LEFT", NAME_LEFT, 0)
    nameHeading:SetText(L["RECIPE"])

    local labels = { name = nameHeading }
    local offset = -8
    for _, column in ipairs(COLUMNS) do
        local heading = Theme.CreateLabel(headings, "tiny", "muted", column.justify or "RIGHT")
        heading:SetText(column.label)
        heading:SetPoint("RIGHT", headings, "RIGHT", offset, 0)
        heading:SetWidth(column.width)
        labels[column.key] = heading
        offset = offset - column.width - 6
    end

    widgets.sorter = Widgets.SortableHeadings and Widgets.SortableHeadings(labels, {
        name = function(a) return a.name end,
        profession = function(a) return a.professionName end,
        listed = function(a) return a.outputItemID and (a.posted or 0) or nil end,
        have = function(a) return a.have end,
        keep = function(a) return AllRecipesView.KeepValue(a) end,
        profit = function(a) return a.priceable and a.profit or nil end,
        ignore = function(a) return a.ignored and 1 or 0 end,
    }, function() AllRecipesView.Refresh() end)
    if widgets.sorter then
        widgets.sorter:SetText({ "name", "profession" })
        -- Best profit first, as the mockup opens.
        widgets.sorter.key, widgets.sorter.ascending = "profit", false
        if widgets.sorter.Sync then widgets.sorter:Sync() end
    end

    local divider = Theme.CreateDivider(container, "borderLit")
    divider:SetPoint("TOPLEFT", headings, "BOTTOMLEFT", 0, -2)
    divider:SetPoint("TOPRIGHT", headings, "BOTTOMRIGHT", 0, -2)

    local list = Widgets.CreateScrollList(container, {
        onScrollbarShown = function(shown)
            headings:SetPoint("TOPRIGHT", toolbar, "BOTTOMRIGHT", shown and -10 or 0, -8)
        end,
        rowHeight = ROW_HEIGHT,
        createRow = CreateRow,
        updateRow = UpdateRow,
        onEnter = function(row, analysis)
            Widgets.ShowItemOnly(row, analysis.outputItemID, analysis.name)
        end,
        onLeave = HideTip,
        clickHint = L["Right-click for more."],
        menu = function(analysis)
            return ns.ProfitTab and ns.ProfitTab.RowMenu and ns.ProfitTab.RowMenu(analysis) or {}
        end,
    })
    list:SetPoint("TOPLEFT", divider, "BOTTOMLEFT", 0, -4)
    list:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", -8, 24)
    widgets.list = list

    local emptyLabel = Theme.CreateLabel(container, "small", "dim", "CENTER")
    emptyLabel:SetPoint("CENTER", list, "CENTER", 0, 10)
    emptyLabel:SetWidth(320)
    emptyLabel:SetWordWrap(true)
    emptyLabel:Hide()
    widgets.emptyLabel = emptyLabel
    if Widgets.DressEmpty then Widgets.DressEmpty(emptyLabel) end

    local countLabel = Theme.CreateLabel(container, "tiny", "dim")
    countLabel:SetPoint("BOTTOMLEFT", 8, 8)
    widgets.countLabel = countLabel

    local colors = Theme.CreateLabel(container, "tiny", "dim", "RIGHT")
    colors:SetPoint("BOTTOMRIGHT", -8, 8)
    colors:SetText(L["Grey, yellow, green and orange dots are skill-up colors."])
    widgets.colorsLabel = colors

    -- A rarity colour needs the item, which may come later: redraw the rows
    -- on screen once, after a burst of arrivals, and only while waiting.
    local redrawQueued = false
    ns.RegisterEvent(container, "GET_ITEM_INFO_RECEIVED", function()
        if redrawQueued or not awaitingItemData then return end
        if not (list.IsVisible and list:IsVisible()) then return end
        redrawQueued = true
        C_Timer.After(0.2, function()
            redrawQueued = false
            awaitingItemData = false
            if list.Refresh then list:Refresh() end
        end)
    end)
end
