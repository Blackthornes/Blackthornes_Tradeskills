-- Blackthornes Tradeskills -- UI/Tab_Settings.lua
-- The knobs that change which crafts come out on top.
--
-- Each one shows what it actually does rather than just its name: several of
-- these silently reshuffle the whole profit table, and a setting you cannot
-- reason about is worse than no setting.
--
-- Layout rule: a row is [label ......... control] on one line. What it does
-- is the row's tooltip, or, with Show descriptions ticked, wrapped on its own
-- lines underneath spanning the full column, the row grown to fit. Rows sit
-- in two columns on one of the category pages (PAGES), picked along the top.

local _, ns = ...
local L = ns.L or setmetatable({ Format = string.format }, { __index = function(_, key) return key end })

local Theme = ns.Theme
local Widgets = ns.Widgets
local Util = ns.Util

local UI = ns.UI

local COLUMN_WIDTH = 400
local COLUMN_ONE_X = 16
local COLUMN_TWO_X = 452

-- Wide enough for the longest label ("Recommend selling at a loss"), with the
-- widest control ("Charge market price") still inside the column.
local LABEL_WIDTH = 228
local CONTROL_X = 240

local ROW_GAP = -8
local SECTION_GAP = -22

-- The category switch along the top, and the room it takes.
local BAR_HEIGHT = 34
-- Each more line the switch wraps to when its names would reach the search
-- box (seen in game 2026-11-17: ABOUT ran under it). The bar grows by it.
local LINE_HEIGHT = 26
-- Between two names on the switch, and round the search box.
local SWITCH_GAP = 22
local TOOLS_GAP = 16

-- A player's request (2026-10-07): the one long page grew crowded, so the
-- settings sit on category pages picked along the top, like Recipes /
-- Recipes to learn. Every setting kept its saved name; only its place moved.
local PAGES = {
    { key = "pricing", text = L["PRICING"],
      tip = L["Undercut, the auction house cut, markups, profit and other price addons"] },
    { key = "queue", text = L["QUEUE"],
      tip = L["What gets queued, sub-crafts, alts, ignored crafts and items, export and import"] },
    { key = "mail", text = L["MAIL & VENDORS"],
      tip = L["The mailbox, your disenchanter, selling to vendors and the mail report"] },
    { key = "auction", text = L["AUCTION HOUSE"],
      tip = L["Buying, posting and scanning"] },
    { key = "data", text = L["DATA"],
      tip = L["What is saved and clearing old prices"] },
    -- From here on, the pages every Blackthornes addon shares, in the same
    -- order in all five (the owner said build it, 2026-11-17): Tooltips,
    -- Sounds, Windows, Sharing, All Addons, About. Look and General became
    -- Tooltips and Windows (2026-11-16); a saved "look" or "general" opens
    -- the new one.
    { key = "tooltips", text = L["TOOLTIPS"],
      tip = L["What shows on item tooltips, in the profession window and in chat"] },
    { key = "sounds", text = L["SOUNDS"],
      tip = L["Every sound the addon plays, each with its own switch"] },
    { key = "windows", text = L["WINDOWS"],
      tip = L["Window look and size, what opens by itself, the small windows and the arrow"] },
    { key = "sharing", text = L["SHARING"],
      tip = L["Your other account and guild prices"] },
    -- The settings every Blackthornes addon shares (2026-11-16): reached
    -- by the one window's gear while One Window is on, so it is left off
    -- the switch then; on the switch while each addon has its own window.
    { key = "all", text = L["ALL ADDONS"] },
    { key = "about", text = L["ABOUT"],
      tip = L["How these addons are made, the version, the Discord, What's New and the other Blackthornes addons"] },
}
local DEFAULT_PAGE = "pricing"
-- Pages that were folded into others, and where their rows went.
local FORMER_PAGES = { look = "tooltips", general = "windows" }

-- "Queue From Sell List:" only means something while Craft First is on,
-- so it is greyed and takes no clicks while that is off.
local function GreyQueueFromSell(widgets, on)
    local box, row = widgets.queueFromSell, widgets.queueFromSellRow
    if not box then return end
    if row then row:SetAlpha(on and 1 or 0.4) else box:SetAlpha(on and 1 or 0.4) end
    box:EnableMouse(on and true or false)
end

-- "Prefer TSM Prices:" only means something while TSM Prices is on, so it
-- is greyed and takes no clicks while that is off.
local function GreyPreferTSM(widgets, tsmOn)
    local box, row = widgets.preferTsmPrices, widgets.preferTsmRow
    if not box then return end
    -- The row holds the label and the box, so its alpha greys both.
    if row then row:SetAlpha(tsmOn and 1 or 0.4) else box:SetAlpha(tsmOn and 1 or 0.4) end
    box:EnableMouse(tsmOn and true or false)
    -- "TSM Price Source:" greys the same way.
    local sourceRow, source = widgets.tsmSourceRow, widgets.tsmPriceSource
    if sourceRow then sourceRow:SetAlpha(tsmOn and 1 or 0.4) end
    if source then
        source.editBox:EnableMouse(tsmOn and true or false)
        if not tsmOn then source.editBox:ClearFocus() end
    end
    -- "TSM Sold a Day:" too.
    if widgets.tsmSoldRow then widgets.tsmSoldRow:SetAlpha(tsmOn and 1 or 0.4) end
    if widgets.tsmSoldPerDay then widgets.tsmSoldPerDay:EnableMouse(tsmOn and true or false) end
    -- "TSM BoE Price Source:" too.
    local gearRow, gear = widgets.tsmGearRow, widgets.tsmGearPriceSource
    if gearRow then gearRow:SetAlpha(tsmOn and 1 or 0.4) end
    if gear then
        gear.editBox:EnableMouse(tsmOn and true or false)
        if not tsmOn then gear.editBox:ClearFocus() end
    end
end

local widgets = {}

-- The Queue page's lists box, made in Build and filled in Refresh.
local ShowQueueList, FindQueueList
local IGNORED_ROW_HEIGHT = 22
local STOCK_ROW_HEIGHT = 26
-- Where Minimums by Profession's profit and margin boxes start in a row.
local MINIMUM_PROFIT_X = 150
local MINIMUM_MARGIN_X = 290
-- "Show:" is short, so the box starts early and has room for a list's name.
local LIST_BOX_X = 60

--- An Off / Shift / Always box (see the Look page) set to the saved mode,
--- without calling its onSelect.
local function ShowShiftMode(dropdown)
    local setting = dropdown.shiftSetting
    local isOn = setting == nil or ns.Config:Get(setting) ~= false
    dropdown:SetValue(ns.TooltipShift:Mode(isOn, dropdown.shiftKey), true)
end

-- The tooltip line boxes on the Tooltips page, in order, by their widgets key.
local TOOLTIP_LINES = {
    "tooltipValue", "tooltipSalesShift", "tooltipTrend", "recipeTooltips",
    "enchantTooltips", "disenchantTooltips", "crateTooltips", "boughtTooltips",
    "usedInTooltips",
}

--- "All Lines:" shows the choice every line shares, or Mixed while they
--- differ. The sales lines have no Off, so they agree with an Off.
local function ShowAllLinesMode()
    local box = widgets.tooltipAll
    if not box then return end
    local Shift = ns.TooltipShift
    local common, same = nil, true
    for _, name in ipairs(TOOLTIP_LINES) do
        local dropdown = widgets[name]
        if dropdown and dropdown.shiftSetting then
            local isOn = ns.Config:Get(dropdown.shiftSetting) ~= false
            local mode = Shift:Mode(isOn, dropdown.shiftKey)
            if common == nil then common = mode elseif common ~= mode then same = false end
        end
    end
    if same and common ~= nil then
        for _, name in ipairs(TOOLTIP_LINES) do
            local dropdown = widgets[name]
            if dropdown and not dropdown.shiftSetting and common ~= Shift.OFF
                and Shift:Mode(true, dropdown.shiftKey) ~= common then
                same = false
            end
        end
    end
    box:SetValue(same and common or nil)
end

--- "All Lines:" picked: every line takes that choice, through its own box,
--- so each line's own setting is what is saved. Off skips the sales lines,
--- which have no Off.
local function SetAllTooltipLines(mode)
    for _, name in ipairs(TOOLTIP_LINES) do
        local dropdown = widgets[name]
        if dropdown and dropdown.applyMode
            and not (mode == ns.TooltipShift.OFF and not dropdown.shiftSetting) then
            dropdown.applyMode(mode)
            dropdown:SetValue(mode)
        end
    end
    ShowAllLinesMode()
end

-- [key] = { holder, scroll, content, last = { [1], [2] }, rows }; built in Build.
local pages = {}

-- Every row and button the search looks through, in the order built.
local searchables = {}

--------------------------------------------------------------------------------
-- Layout helpers
--------------------------------------------------------------------------------

--- Put `frame` under the last thing in a page's column, or at its top, and
--- make it the new last thing there.
local function Place(page, column, frame, gap)
    local last = page.last[column]
    if last then
        frame:SetPoint("TOPLEFT", last, "BOTTOMLEFT", 0, gap or ROW_GAP)
    else
        frame:SetPoint("TOPLEFT", page.content, "TOPLEFT",
            column == 1 and COLUMN_ONE_X or COLUMN_TWO_X, -12)
    end
    page.last[column] = frame
    return frame
end

--- A soft gold frame around something the search found. Drawn on the
--- page itself, so it sits behind the row's own controls.
local function AddFoundGlow(page, frame)
    local glow = page.content:CreateTexture(nil, "BACKGROUND")
    glow:SetPoint("TOPLEFT", frame, "TOPLEFT", -6, 3)
    glow:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 6, -3)
    glow:SetColorTexture(Theme.Unpack("accent"))
    glow:SetAlpha(0.16)
    glow:Hide()
    return glow
end

--- Let the search find `frame` by its words, on `page`.
--- `onFound()`, when given, is called when the search shows this one (the
--- Queue page's lists: it picks the list the words belong to).
local function Searchable(page, frame, words, onFound)
    searchables[#searchables + 1] = {
        page = page.key,
        frame = frame,
        words = (words or ""):lower(),
        glow = AddFoundGlow(page, frame),
        onFound = onFound,
    }
end

--- Section heading with a rule underneath, next in a page's column.
local function CreateSection(page, column, text)
    local section = CreateFrame("Frame", nil, page.content)
    section:SetSize(COLUMN_WIDTH, 20)
    Place(page, column, section, page.last[column] and SECTION_GAP)

    local heading = Theme.CreateLabel(section, "tiny", "accent")
    heading:SetPoint("TOPLEFT", 0, 0)
    heading:SetText(text)

    local divider = Theme.CreateDivider(section)
    divider:SetPoint("TOPLEFT", 0, -14)
    divider:SetWidth(COLUMN_WIDTH)

    return section
end

--- The tooltip a row shows under the mouse: its name, then what it does,
--- in white so it reads easily.
local function ShowRowTip(row)
    if not (row.description and GameTooltip) then return end
    if ns.Config:Get("settingsDescriptions") == true then return end

    GameTooltip:SetOwner(row, "ANCHOR_NONE")
    GameTooltip:ClearAllPoints()
    GameTooltip:SetPoint("TOPLEFT", row, "BOTTOMLEFT", 0, -2)
    GameTooltip:SetText(row.labelText, Theme.Unpack("accent"))
    GameTooltip:AddLine(row.description, 1, 1, 1, true)
    GameTooltip:Show()
end

--- Light a row while the mouse is over it or any control on it. Its
--- controls take the mouse from it, so it checks each frame until the
--- mouse has left the whole row rather than trusting OnLeave.
local function LightRow(row)
    row.hover:Show()
    ShowRowTip(row)
    row:SetScript("OnUpdate", function(self)
        if self:IsMouseOver() then return end
        self:SetScript("OnUpdate", nil)
        self.hover:Hide()
        if GameTooltip and GameTooltip:IsOwned(self) then GameTooltip:Hide() end
    end)
end

--- How tall a row is with its description shown, or without.
local function FitRow(row, showDescription)
    row.hint:SetShown(showDescription)
    row:SetHeight(showDescription and row.fullHeight or row.compactHeight)
end

--- One setting: label and control on a line. What it does is a tooltip on
--- the row, or the line beneath it with Show descriptions ticked.
-- Returns the row frame; anchor the control at CONTROL_X inside it.
local function CreateRow(page, column, labelText, description)
    -- No description (nil or "") means no tooltip and nothing under the
    -- row with Show descriptions ticked.
    if description == "" then description = nil end

    local row = CreateFrame("Frame", nil, page.content)
    row:SetSize(COLUMN_WIDTH, 24)
    Place(page, column, row)

    -- Wrapped rather than cut off should a label still outgrow its room at
    -- the player's font; the description then starts under its last line.
    local label = Theme.CreateLabel(row, "small", "text")
    label:SetPoint("TOPLEFT", 0, -4)
    label:SetWidth(LABEL_WIDTH)
    label:SetWordWrap(true)
    label:SetText(labelText)

    local top = 24
    local labelHeight = label.GetStringHeight and label:GetStringHeight() or 0
    if type(labelHeight) == "number" and labelHeight > 16 then
        top = math.ceil(4 + labelHeight + 6)
    end
    row.compactHeight = top
    row.fullHeight = top

    -- Lit under the mouse, so it is plain the row has more to say.
    row.hover = row:CreateTexture(nil, "BACKGROUND")
    row.hover:SetPoint("TOPLEFT", -6, 2)
    row.hover:SetPoint("BOTTOMRIGHT", 6, -2)
    row.hover:SetColorTexture(Theme.Unpack("accent"))
    row.hover:SetAlpha(0.1)
    row.hover:Hide()

    row.labelText = labelText
    row.description = description
    row:EnableMouse(true)
    row:SetScript("OnEnter", LightRow)

    if description then
        -- "muted" rather than "dim": the small print says what each setting
        -- does, and "dim" was hard to read on the panel.
        local hint = Theme.CreateLabel(row, "tiny", "muted")
        hint:SetPoint("TOPLEFT", 0, -top)
        hint:SetWidth(COLUMN_WIDTH)
        -- Wrapped, with the row grown to fit: on one line the longer ones
        -- (Undercut by, Minimum profit) were cut off halfway with "...".
        hint:SetWordWrap(true)
        hint:SetText(description)
        row.hint = hint

        local height = hint.GetStringHeight and hint:GetStringHeight() or 0
        row.fullHeight = math.max(40, top + (type(height) == "number" and math.ceil(height) or 14) + 2)
        FitRow(row, ns.Config:Get("settingsDescriptions") == true)
    else
        row:SetHeight(top)
    end

    page.rows = page.rows or {}
    page.rows[#page.rows + 1] = row
    Searchable(page, row, labelText .. " " .. (description or ""))

    return row
end

--- Small unit label sitting to the right of a control.
local function AddUnit(row, control, text)
    local unit = Theme.CreateLabel(row, "small", "muted")
    unit:SetPoint("LEFT", control, "RIGHT", 6, 0)
    unit:SetText(text)
    return unit
end

--- Put a row's Reload button under its control, lined up with the
--- control's right edge, the row a line taller for it. Every Reload in
--- Settings sits the same way, as in the other Blackthornes addons.
local function ReloadUnder(row, control, reload)
    reload:ClearAllPoints()
    reload:SetPoint("TOPRIGHT", control, "BOTTOMRIGHT", 0, -4)
    row.compactHeight = row.compactHeight + 24
    row.fullHeight = row.fullHeight + 24
    if row.hint then
        row.hint:ClearAllPoints()
        row.hint:SetPoint("TOPLEFT", 0, -row.compactHeight)
    end
    row:SetHeight(row.compactHeight)
end

--- Widen a button to its label when the label, measured at the player's
--- font, needs more room than the button was given: "Remove old prices"
--- and "Reset to defaults" ended in "..." on 140-pixel buttons.
local function FitButton(button)
    local width = Theme.TextWidth(button.label)
    local have = button:GetWidth()
    if width and type(have) == "number" and width + 16 > have then
        button:SetWidth(math.ceil(width) + 16)
    end
end

--------------------------------------------------------------------------------
-- Pages, the switch along the top, and the search
--------------------------------------------------------------------------------

--- The page showing now: the one saved, or Pricing.
local function CurrentPage()
    local saved = ns.Config:Get("settingsPage")
    saved = FORMER_PAGES[saved] or saved
    return pages[saved] and saved or DEFAULT_PAGE
end

--- Size a page's scrolling area to what is on it, once it has real
--- coordinates.
--
-- On the first build the frames have not been laid out yet, so GetTop() is
-- nil and there is nothing to measure. Retrying on the next frame costs one
-- timer and avoids a page that cannot scroll until you click away and back.
local function FitScroll(key)
    local page = pages[key or CurrentPage()]
    if not page then return end

    if not page.scroll:FitContent() then
        C_Timer.After(0, function() page.scroll:FitContent() end)
    end
end

--- Light the switch: the page showing gold and underlined, a page the
--- search found nothing on dimmed, the rest grey until hovered.
local function PaintSwitch()
    local current = CurrentPage()
    for _, part in ipairs(widgets.switch or {}) do
        local active = part.key == current
        local color = active and "accent"
            or (widgets.query and not part.found) and "dim"
            or part.hovered and "text"
            or "muted"
        part.label:SetTextColor(Theme.Unpack(color))
        part.underline:SetShown(active)
    end
end

--- Lay the switch out left to right, each part as wide as its name.
--- True while the one window is on: All Addons is behind its gear then.
local function AllAddonsHidden()
    local tabs = ns.TSTabs
    local One = tabs and tabs.One and tabs.One()
    return One ~= nil and One.On() == true
end

--- How tall the bar stands: one line, and a line more for each the switch
--- wraps to.
local function BarHeight()
    return BAR_HEIGHT + ((widgets.switchLines or 1) - 1) * LINE_HEIGHT
end

--- The room the search box and Show Descriptions take at the bar's right.
local function ToolsWidth()
    local describe = widgets.describe
    local tick = describe and Theme.TextWidth and describe.label and Theme.TextWidth(describe.label)
    tick = (type(tick) == "number" and tick or 110) + 24
    local find = widgets.find and widgets.find:GetWidth()
    find = (type(find) == "number" and find > 0) and find or (Widgets.SEARCH_WIDTH or 170)
    return TOOLS_GAP + find + TOOLS_GAP + tick + 16
end

--- Lay the switch out left to right, each part as wide as its name. All
--- Addons is left off while the one window is on (its gear opens it). A
--- name that would reach the search box starts a new line under the first,
--- and the bar and the pages under it move down by a line.
local function LayoutSwitch()
    local bar = widgets.bar
    if not bar then return end
    local width = bar:GetWidth()
    local room = (type(width) == "number" and width > 0)
        and (width - COLUMN_ONE_X - ToolsWidth()) or math.huge
    local previous, x, line = nil, 0, 1
    for _, part in ipairs(widgets.switch or {}) do
        local hidden = part.key == "all" and AllAddonsHidden()
        part.button:SetShown(not hidden)
        if not hidden then
            local measured = Theme.TextWidth and Theme.TextWidth(part.label)
            local w = (type(measured) == "number" and measured or 100) + 4
            part.button:SetWidth(w)
            part.button:ClearAllPoints()
            if previous and x + SWITCH_GAP + w > room then
                line = line + 1
                previous, x = nil, 0
            end
            if previous then
                part.button:SetPoint("LEFT", previous, "RIGHT", SWITCH_GAP, 0)
                x = x + SWITCH_GAP + w
            else
                part.button:SetPoint("LEFT", bar, "TOPLEFT", COLUMN_ONE_X,
                    -BAR_HEIGHT / 2 - (line - 1) * LINE_HEIGHT)
                x = w
            end
            previous = part.button
        end
    end
    local changed = (widgets.switchLines or 1) ~= line
    widgets.switchLines = line
    if bar:GetHeight() ~= BarHeight() then bar:SetHeight(BarHeight()) end
    if changed then
        for _, page in pairs(pages) do
            page.holder:SetPoint("TOPLEFT", 0, -BarHeight() - 2)
        end
        if widgets.shownPage then FitScroll(widgets.shownPage) end
    end
end

--- Show one page and remember it.
local function ShowPage(key)
    if not pages[key] then key = DEFAULT_PAGE end
    -- Only written when it changes: every setting write is mirrored out at
    -- once (Persist), and a page being redrawn is not a change.
    if ns.Config:Get("settingsPage") ~= key then ns.Config:Set("settingsPage", key) end
    for pageKey, page in pairs(pages) do
        page.holder:SetShown(pageKey == key)
    end
    widgets.shownPage = key
    PaintSwitch()
    FitScroll(key)
end

--- Scroll a page so `frame` is in view, near the top.
local function ScrollTo(key, frame)
    local page = pages[key]
    local top, at = page.content:GetTop(), frame:GetTop()
    if type(top) ~= "number" or type(at) ~= "number" then return end
    page.scroll:UpdateRange()
    local bar = page.scroll.scrollbar
    local _, range = bar:GetMinMaxValues()
    bar:SetValue(math.max(0, math.min(range or 0, top - at - 12)))
end

--- Find settings by their words. Each one found glows, each page with
--- none dims on the switch, and when the page showing has none, the first
--- page that does is shown.
local function Search(text)
    local query = (text or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    widgets.query = query ~= "" and query or nil

    local counts, firstFound, onFound = {}, {}, {}
    for _, entry in ipairs(searchables) do
        local found = widgets.query and entry.words:find(widgets.query, 1, true) ~= nil
        -- One glow on a frame several entries share (the lists' Show: row).
        local lit = found and not (entry.onFound and onFound[entry.page])
        entry.glow:SetShown(lit and true or false)
        if found then
            counts[entry.page] = (counts[entry.page] or 0) + 1
            firstFound[entry.page] = firstFound[entry.page] or entry.frame
            if entry.onFound then onFound[entry.page] = onFound[entry.page] or entry.onFound end
        end
    end
    if widgets.queueListFound and not onFound.queue then
        widgets.queueListFound = nil
        ShowQueueList()
    end

    -- No counts beside the names: the switch has to stay clear of the
    -- search box at the player's font.
    for _, part in ipairs(widgets.switch or {}) do
        part.found = (counts[part.key] or 0) > 0
    end

    local show = CurrentPage()
    if widgets.query and not counts[show] then
        for _, definition in ipairs(PAGES) do
            if counts[definition.key] then show = definition.key break end
        end
    end
    if show ~= CurrentPage() then ShowPage(show) else PaintSwitch() end
    if onFound[show] then onFound[show]() end
    if widgets.query and firstFound[show] then ScrollTo(show, firstFound[show]) end
end

--- Show or hide the line under every setting, and fit each page to it.
local function ShowDescriptions(show)
    for _, page in pairs(pages) do
        for _, row in ipairs(page.rows or {}) do
            if row.hint then FitRow(row, show) end
        end
    end
    FitScroll()
end

local function BuildBar(outer)
    local bar = CreateFrame("Frame", nil, outer)
    bar:SetPoint("TOPLEFT", 0, 0)
    bar:SetPoint("TOPRIGHT", 0, 0)
    bar:SetHeight(BAR_HEIGHT)
    widgets.bar = bar

    local rule = Theme.CreateDivider(bar)
    rule:SetPoint("BOTTOMLEFT", COLUMN_ONE_X, 0)
    rule:SetPoint("BOTTOMRIGHT", -16, 0)

    widgets.switch = {}
    for _, definition in ipairs(PAGES) do
        local button = CreateFrame("Button", nil, bar)
        button:SetHeight(22)

        local part = { key = definition.key, button = button }
        part.label = Theme.CreateLabel(button, "small", "muted")
        part.label:SetPoint("LEFT", 0, 0)
        part.label:SetText(definition.text)

        part.underline = button:CreateTexture(nil, "ARTWORK")
        part.underline:SetColorTexture(Theme.Unpack("accent"))
        part.underline:SetHeight(2)
        part.underline:SetPoint("TOPLEFT", button, "BOTTOMLEFT", 0, 1)
        part.underline:SetPoint("TOPRIGHT", button, "BOTTOMRIGHT", 0, 1)
        part.underline:Hide()

        button:SetScript("OnClick", function() ShowPage(definition.key) end)
        button:SetScript("OnEnter", function(self)
            part.hovered = true
            PaintSwitch()
            if definition.tip then
                GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
                GameTooltip:SetText(definition.tip, 1, 1, 1, 1, true)
                GameTooltip:Show()
            end
        end)
        button:SetScript("OnLeave", function()
            part.hovered = false
            PaintSwitch()
            GameTooltip:Hide()
        end)

        widgets.switch[#widgets.switch + 1] = part
    end

    -- The house order for an option bar: search, then tick boxes.
    widgets.describe = Widgets.CreateCheckbox(bar, L["Show Descriptions"], function(checked)
        ns.Config:Set("settingsDescriptions", checked)
        ShowDescriptions(checked)
    end, false)
    -- Held to the first line, so a switch that wraps leaves them in place.
    widgets.describe:SetPoint("RIGHT", bar, "TOPRIGHT", -16, -BAR_HEIGHT / 2)

    widgets.find = Widgets.CreateSearchBox(bar, L["Find a setting"], Search)
    widgets.find:SetWidth(Widgets.SEARCH_WIDTH or 170)
    widgets.find:SetPoint("RIGHT", widgets.describe, "LEFT", -TOOLS_GAP, 0)

    LayoutSwitch()
    -- The bar's width comes from the window: lay the switch out again
    -- whenever it changes (a resize, the one window, a bigger font).
    bar:SetScript("OnSizeChanged", function()
        if widgets.laying then return end
        widgets.laying = true
        LayoutSwitch()
        widgets.laying = false
    end)
end

--------------------------------------------------------------------------------
-- Build
--------------------------------------------------------------------------------

--- While the Disenchanter box is empty, the name picked for the player
--- shows where "Character name" sits, and the row's tooltip says so. A whole
--- name too wide for the box is never cut: the box then says "Picked for
--- you" and the tooltip names them.
local DISENCHANTER_HINT_ROOM = 124
local function ShowPickedDisenchanter()
    local box = widgets.disenchanter
    if not (box and box.hint) then return end
    local picked
    if ns.QueueMail and ns.QueueMail.GuessDisenchanter then
        local ok, name = pcall(ns.QueueMail.GuessDisenchanter, ns.QueueMail)
        picked = ok and name or nil
    end
    box.hint:SetText(picked or L["Character name"])
    if picked and (box.hint:GetStringWidth() or 0) > DISENCHANTER_HINT_ROOM then
        box.hint:SetText(L["Picked for you"])
    end
    local row = widgets.disenchanterRow
    if row then
        row.description = picked
            and L.Format("%s Picked for you now: %s.", widgets.disenchanterTip, picked)
            or widgets.disenchanterTip
    end
end

local function Build(outer)
    local Config = ns.Config

    BuildBar(outer)

    -- Each page scrolls on its own, should one outgrow the window (a long
    -- ignored list, or every description shown). The holder carries the
    -- scrollbar, which sits beside the scrolling area rather than in it, so
    -- hiding a page hides its bar too.
    for _, definition in ipairs(PAGES) do
        local holder = CreateFrame("Frame", nil, outer)
        holder:SetPoint("TOPLEFT", 0, -BarHeight() - 2)
        holder:SetPoint("BOTTOMRIGHT", 0, 0)
        holder:Hide()

        local scroll = Widgets.CreateScrollFrame(holder, { step = 40 })
        scroll:SetPoint("TOPLEFT", 0, 0)
        scroll:SetPoint("BOTTOMRIGHT", -14, 0)

        pages[definition.key] = {
            key = definition.key, holder = holder, scroll = scroll,
            content = scroll.content, last = {},
        }
    end


    CreateSection(pages.pricing, 1, L["AUCTION PRICES"])

    local undercutRow = CreateRow(pages.pricing, 1, L["Undercut By:"],
        L["How far under the cheapest listing you post. Set 0 to match it."])

    widgets.undercut = Widgets.CreateNumberBox(undercutRow, {
        width = 70, min = 0, max = 1000000,
        onChange = function(value)
            Config:Set("undercutCopper", value)
            UI:RefreshActiveTab()
        end,
    })
    widgets.undercut:SetPoint("TOPLEFT", CONTROL_X, 0)
    AddUnit(undercutRow, widgets.undercut, L["copper"])

    -- No Undercutting on/off button (the owner, 2026-10-15): 0 in the box
    -- matches the cheapest price, and any other number can be typed there.

    -- Overcutting (the owner, 2026-10-15): post just under the big stack
    -- when a few cheap ones below it should sell first. Off unless ticked.
    local overcutRow = CreateRow(pages.pricing, 1, L["Overcutting:"], ns.Profit.OVERCUT_HELP)

    widgets.overcutting = Widgets.CreateCheckbox(overcutRow, L["On"], function(checked)
        Config:Set("overcutting", checked)
        UI:RefreshActiveTab()
        if ns.PostPanel and ns.PostPanel.Refresh then ns.PostPanel:Refresh() end
    end, false)
    widgets.overcutting:SetPoint("TOPLEFT", CONTROL_X, -2)

    local cutRow = CreateRow(pages.pricing, 1, L["Auction House Cut:"],
        L["The share of each sale the auction house keeps."])

    widgets.cut = Widgets.CreateNumberBox(cutRow, {
        width = 70, min = 0, max = 100, decimals = 1,
        onChange = function(value)
            Config:Set("auctionCut", value / 100)
            UI:RefreshActiveTab()
        end,
    })
    widgets.cut:SetPoint("TOPLEFT", CONTROL_X, 0)
    AddUnit(cutRow, widgets.cut, "%")

    local depositRow = CreateRow(pages.pricing, 1, L["Ignore Deposit:"],
        L["Leaves the deposit out of profit and selling advice."])
    widgets.ignoreDeposit = Widgets.CreateCheckbox(depositRow, L["On"], function(checked)
        Config:Set("ignoreDeposit", checked)
        UI:RefreshActiveTab()
    end, false)
    widgets.ignoreDeposit:SetPoint("TOPLEFT", CONTROL_X, -2)

    local unscannedRow = CreateRow(pages.pricing, 1, L["Markup With No Rivals:"],
        L["When nobody else sells it, your price is the material cost plus this."])

    widgets.unscannedMarkup = Widgets.CreateNumberBox(unscannedRow, {
        width = 70, min = 0, max = 1000,
        onChange = function(value)
            Config:Set("unscannedMarkupPercent", value)
            UI:RefreshActiveTab()
        end,
    })
    widgets.unscannedMarkup:SetPoint("TOPLEFT", CONTROL_X, 0)
    AddUnit(unscannedRow, widgets.unscannedMarkup, L["% markup"])

    local unscannedOnRow = CreateRow(pages.pricing, 1, L["Use That Markup:"],
        L["When off, crafts nobody else sells have no price."])

    widgets.priceUnscanned = Widgets.CreateCheckbox(unscannedOnRow, L["On"], function(checked)
        Config:Set("priceUnscannedCrafts", checked)
        UI:RefreshActiveTab()
    end, true)
    widgets.priceUnscanned:SetPoint("TOPLEFT", CONTROL_X, -2)

    local ownedRow = CreateRow(pages.pricing, 1, L["Charge for Own Materials:"],
        L["When off, materials you already have count as free."])

    widgets.valueOwned = Widgets.CreateCheckbox(ownedRow, L["On"], function(checked)
        Config:Set("valueOwnedMaterials", checked)
        UI:RefreshActiveTab()
    end, true)
    widgets.valueOwned:SetPoint("TOPLEFT", CONTROL_X, -2)

    -- The Queue page in three groups (the owner said build it, 2026-11-16,
    -- from a mockup): how many to keep, sub-crafts and alts, the list.
    CreateSection(pages.queue, 1, L["RESTOCKING"])
    local postedRow = CreateRow(pages.queue, 1, L["Keep in Stock:"],
        L["The most of each craft to keep. Listings, bags, bank, mail and queue all count. At 0 it keeps about two days of your sales. Set one per profession below or per item on the Profit tab."])

    widgets.maxPosted = Widgets.CreateNumberBox(postedRow, {
        width = 70, min = 0, max = 999,
        onChange = function(value)
            Config:Set("maxPostedPerItem", value)
            UI:RefreshActiveTab()
        end,
    })
    widgets.maxPosted:SetPoint("TOPLEFT", CONTROL_X, 0)

    widgets.maxPostedHint = Theme.CreateLabel(postedRow, "small", "muted")
    widgets.maxPostedHint:SetPoint("LEFT", widgets.maxPosted, "RIGHT", 6, 0)
    widgets.maxPostedHint:SetWidth(120)

    local soldRow = CreateRow(pages.queue, 1, L["Restock What Sells:"],
        L["When an auction sells, another goes in the queue. Never a craft that loses money."])

    widgets.restockOnSale = Widgets.CreateCheckbox(soldRow, L["On"], function(checked)
        Config:Set("restockOnSale", checked)
    end, true)
    widgets.restockOnSale:SetPoint("TOPLEFT", CONTROL_X, -2)

    -- Stock From Sales and Raise When Sold Out in one box (the owner said
    -- build it, 2026-11-16, from a mockup). Each keeps its own saved key,
    -- learnStockFromSales and raiseStockOnSellOut, and every player's pair
    -- shows as one of the four choices; only a key that changes is written.
    local fromSalesRow = CreateRow(pages.queue, 1, L["Stock From Sales:"],
        L["Follow Sales: at 0, Keep in Stock follows about two days of your sales. Without it, crafts with no number are never queued. Raise When Sold Out: when every copy you listed sells, Keep in Stock goes up by 1. After 3 unsold in a row it goes down by 1, never below where it started."])

    widgets.stockFromSales = Widgets.CreateDropdown(fromSalesRow, {
        { text = L["Off"], value = "off" },
        { text = L["Follow Sales"], value = "sales" },
        { text = L["Raise When Sold Out"], value = "sellout" },
        { text = L["Both"], value = "both" },
    }, function(value)
        local learn = value == "sales" or value == "both"
        local raise = value == "sellout" or value == "both"
        if (Config:Get("learnStockFromSales") ~= false) ~= learn then
            Config:Set("learnStockFromSales", learn)
        end
        if (Config:Get("raiseStockOnSellOut") == true) ~= raise then
            Config:Set("raiseStockOnSellOut", raise)
        end
        UI:RefreshActiveTab()
    end, { width = COLUMN_WIDTH - CONTROL_X })
    widgets.stockFromSales:SetPoint("TOPLEFT", CONTROL_X, 0)

    -- One row each (the owner, 2026-10-15): the number, and beside it the
    -- tick box that turns it on. Same saved keys as the two rows before.
    local restockRow = CreateRow(pages.queue, 1, L["Restock When Down To:"],
        L["Waits until you're down to this many, then makes it back up. Off tops it up right away."])

    widgets.restockAt = Widgets.CreateNumberBox(restockRow, {
        width = 70, min = 0, max = 999,
        onChange = function(value)
            Config:Set("restockAt", value)
            UI:RefreshActiveTab()
        end,
    })
    widgets.restockAt:SetPoint("TOPLEFT", CONTROL_X, 0)

    widgets.restockWhenLow = Widgets.CreateCheckbox(restockRow, L["On"], function(checked)
        Config:Set("restockWhenLow", checked)
        UI:RefreshActiveTab()
    end, true)
    widgets.restockWhenLow:SetPoint("TOPLEFT", CONTROL_X + 82, -2)

    local extraRow = CreateRow(pages.queue, 1, L["Extra for Fast Sellers:"],
        L["Items that sell fast for you can go over Keep in Stock by this many."])

    widgets.fastSellerExtra = Widgets.CreateNumberBox(extraRow, {
        width = 70, min = 0, max = 999,
        onChange = function(value)
            Config:Set("fastSellerExtra", value)
            UI:RefreshActiveTab()
        end,
    })
    widgets.fastSellerExtra:SetPoint("TOPLEFT", CONTROL_X, 0)

    widgets.fastSellerBoost = Widgets.CreateCheckbox(extraRow, L["On"], function(checked)
        Config:Set("fastSellerBoost", checked)
        UI:RefreshActiveTab()
    end, true)
    widgets.fastSellerBoost:SetPoint("TOPLEFT", CONTROL_X + 82, -2)

    CreateSection(pages.queue, 1, L["SUB-CRAFTS AND ALTS"])
    local subCraftRow = CreateRow(pages.queue, 1, L["Queue Sub-Crafts:"],
        L["Also queues materials that are cheaper to make than buy."])

    widgets.subCrafts = Widgets.CreateCheckbox(subCraftRow, L["On"], function(checked)
        Config:Set("autoQueueSubCrafts", checked)

        -- Sub-crafts are only worked out when the queue changes, so unticking
        -- this left them queued (and ticking it queued none) until then.
        ns.Queue:RebuildDependencies()
        ns.Queue:Notify()
    end, true)
    widgets.subCrafts:SetPoint("TOPLEFT", CONTROL_X, -2)

    local shareRow = CreateRow(pages.queue, 1, L["Alts Make Sub-Crafts:"],
        L["Puts a sub-craft on the alt who can make it, and the mailbox lists what to send."])

    widgets.shareQueue = Widgets.CreateCheckbox(shareRow, L["On"], function(checked)
        Config:Set("queueAltCrafting", checked)
        -- Who makes each sub-craft is worked out when the queue is rebuilt,
        -- and a part an alt makes is priced at its materials only while on.
        if ns.Cost.Changed then
            ns.Cost:Changed()
        else
            ns.Queue:RebuildDependencies()
            ns.Queue:Notify()
        end
    end, false)
    widgets.shareQueue:SetPoint("TOPLEFT", CONTROL_X, -2)

    local altCraftRow = CreateRow(pages.queue, 1, L["Suggest Other Characters:"],
        L["Points out materials an alt can make for less."])

    widgets.altCrafts = Widgets.CreateCheckbox(altCraftRow, L["On"], function(checked)
        Config:Set("suggestOtherCharacters", checked)
        UI:RefreshActiveTab()
    end, true)
    widgets.altCrafts:SetPoint("TOPLEFT", CONTROL_X, -2)

    CreateSection(pages.queue, 1, L["THE LIST"])
    local hideMaxedRow = CreateRow(pages.queue, 1, L["Hide Maxed Crafts:"],
        L["Hides crafts at their limit."])

    widgets.hideMaxed = Widgets.CreateCheckbox(hideMaxedRow, L["On"], function(checked)
        Config:Set("hideAtPostLimit", checked)
        UI:RefreshActiveTab()
    end, true)
    widgets.hideMaxed:SetPoint("TOPLEFT", CONTROL_X, -2)

    local onlyMineRow = CreateRow(pages.queue, 1, L["Only My Crafts:"],
        L["Shows only the crafts this character makes. Crafts for your other characters stay in the queue and show when you log in on them."])

    widgets.onlyMine = Widgets.CreateCheckbox(onlyMineRow, L["On"], function(checked)
        Config:Set("queueOnlyMine", checked)
        UI:RefreshActiveTab()
        if ns.CraftPanel and ns.CraftPanel.OnQueueChanged then ns.CraftPanel:OnQueueChanged() end
    end, true)
    widgets.onlyMine:SetPoint("TOPLEFT", CONTROL_X, -2)

    local freeSpaceRow = CreateRow(pages.queue, 1, L["Free Bag Space First:"],
        L["Craft Next picks the craft that frees the most bag slots."])

    widgets.freeSpaceFirst = Widgets.CreateCheckbox(freeSpaceRow, L["On"], function(checked)
        Config:Set("craftFreesSpaceFirst", checked)
        UI:RefreshActiveTab()
        if ns.CraftPanel and ns.CraftPanel.UpdateCraftButton then ns.CraftPanel:UpdateCraftButton() end
    end, true)
    widgets.freeSpaceFirst:SetPoint("TOPLEFT", CONTROL_X, -2)

    local followRow = CreateRow(pages.queue, 1, L["Goals Follow the Queue:"],
        L["With Farmer, goals from Set Goal change with the queue."])

    widgets.followGoals = Widgets.CreateCheckbox(followRow, L["On"], function(checked)
        Config:Set("farmerGoalsFollowQueue", checked)
        if checked then ns.FarmerGoals:Follow() end
    end, true)
    widgets.followGoals:SetPoint("TOPLEFT", CONTROL_X, -2)

    CreateSection(pages.mail, 1, L["AT THE MAILBOX"])
    local queueMailRow = CreateRow(pages.mail, 1, L["Queue Mail:"],
        L["At the mailbox, lists what to send your alts with a button that fills in the mail."])

    widgets.queueMail = Widgets.CreateCheckbox(queueMailRow, L["Show"], function(checked)
        Config:Set("queueMailPanel", checked)
        if ns.QueueMailPanel then ns.QueueMailPanel:Refresh() end
    end, true)
    widgets.queueMail:SetPoint("TOPLEFT", CONTROL_X, -2)

    -- Asked 2026-10-04: a character to mail gear to for disenchanting.
    -- Typed rather than picked, so one on another account works too.
    local disenchanterRow = CreateRow(pages.mail, 1, L["Disenchanter:"],
        L["The character you mail gear to for disenchanting. Leave it empty to pick your alt with the most Enchanting."])
    widgets.disenchanterRow = disenchanterRow
    widgets.disenchanterTip = disenchanterRow.description

    widgets.disenchanter = Widgets.CreateSearchBox(disenchanterRow, L["Character name"], function(text)
        local trimmed = (text or ""):gsub("^%s+", ""):gsub("%s+$", "")
        Config:Set("disenchanterName", trimmed)
        if ns.QueueMailPanel then ns.QueueMailPanel:Refresh() end
    end)
    widgets.disenchanter:SetWidth(150)
    widgets.disenchanter:SetPoint("TOPLEFT", CONTROL_X, 0)
    -- A letter where the search box has its magnifier: this is a name.
    if widgets.disenchanter.icon then
        widgets.disenchanter.icon:SetTexture([[Interface\Minimap\Tracking\Mailbox]])
        widgets.disenchanter.icon:SetSize(14, 14)
    end
    -- Escape puts the saved name back rather than clearing it.
    widgets.disenchanter.editBox:SetScript("OnEscapePressed", function(self)
        self:SetText(Config:Get("disenchanterName") or "")
        self:ClearFocus()
    end)

    -- Asked 2026-10-11 (the owner: the addons should do the work).
    local guessRow = CreateRow(pages.mail, 1, L["Pick One for Me:"],
        L["When the box is empty, picks your best enchanter."])

    widgets.disenchanterGuess = Widgets.CreateCheckbox(guessRow, L["On"], function(checked)
        Config:Set("disenchanterGuess", checked)
        if ns.QueueMailPanel then ns.QueueMailPanel:Refresh() end
        ShowPickedDisenchanter()
    end, true)
    widgets.disenchanterGuess:SetPoint("TOPLEFT", CONTROL_X, -2)

    local disenchantQualityRow = CreateRow(pages.mail, 1, L["Mail Gear Up To:"],
        L["The best quality that goes to your disenchanter."])

    widgets.disenchantQuality = Widgets.CreateDropdown(disenchantQualityRow, {
        { text = L["Greens only"], value = 2 },
        { text = L["Greens and blues"], value = 3 },
        { text = L["Up to purples"], value = 4 },
    }, function(value)
        Config:Set("disenchanterQuality", value)
        if ns.QueueMailPanel then ns.QueueMailPanel:Refresh() end
    end, { width = 150 })
    widgets.disenchantQuality:SetPoint("TOPLEFT", CONTROL_X, 0)

    -- Asked 2026-10-05: big shuffles taken from the mail a bagful at a time.
    local spareRow = CreateRow(pages.mail, 1, L["Bag Slots Kept Free:"],
        L["Take Next Batch leaves this many slots empty."])

    widgets.bagSpare = Widgets.CreateNumberBox(spareRow, {
        width = 70, min = 0, max = 50,
        onChange = function(value)
            Config:Set("bagSpareSlots", value)
            if ns.QueueMailPanel then ns.QueueMailPanel:Refresh() end
        end,
    })
    widgets.bagSpare:SetPoint("TOPLEFT", CONTROL_X, 0)

    local mailBatchRow = CreateRow(pages.mail, 1, L["Take Mail in Batches:"],
        L["A button at the mailbox takes the queue's materials, as much as fits. Never COD mail."])

    widgets.mailBatch = Widgets.CreateCheckbox(mailBatchRow, L["Show"], function(checked)
        Config:Set("mailBatchTake", checked)
        if ns.QueueMailPanel then ns.QueueMailPanel:Refresh() end
    end, false)
    widgets.mailBatch:SetPoint("TOPLEFT", CONTROL_X, -2)

    -- Asked 2026-10-07: each queue row says AH, DE or Vendor, and what the
    -- queue made on DE or Vendor can be disenchanted or sold from here.
    local deNextRow = CreateRow(pages.queue, 1, L["Disenchant Next Button:"],
        L["A button that disenchants the next item your queue marked DE, one per click."])

    widgets.deNext = Widgets.CreateCheckbox(deNextRow, L["On"], function(checked)
        Config:Set("queueDisenchantNext", checked)
        UI:RefreshActiveTab()
    end, false)
    widgets.deNext:SetPoint("TOPLEFT", CONTROL_X, -2)

    CreateSection(pages.mail, 2, L["AT VENDORS"])
    local sellMarkedRow = CreateRow(pages.mail, 2, L["Sell Marked Items:"],
        L["A button at vendors sells what your queue marked Vendor, up to 12 a visit."])

    widgets.sellMarked = Widgets.CreateCheckbox(sellMarkedRow, L["Show"], function(checked)
        Config:Set("sellMarkedButton", checked)
        if ns.SellMarked then ns.SellMarked:Update() end
    end, true)
    widgets.sellMarked:SetPoint("TOPLEFT", CONTROL_X, -2)

    -- Logic/VendorPins.lua (asked 2026-10-18): gold pins on the world map
    -- at vendors that sell what the queue needs for less.
    local vendorPinsRow = CreateRow(pages.mail, 2, L["Vendor Map Pins:"],
        L["Pins vendors on your world map that sell what your queue needs for less than the auction house."])

    widgets.vendorMapPins = Widgets.CreateCheckbox(vendorPinsRow, L["On"], function(checked)
        if ns.VendorPins then ns.VendorPins:SetOn(checked) else Config:Set("vendorMapPins", checked) end
    end, false)
    widgets.vendorMapPins:SetPoint("TOPLEFT", CONTROL_X, -2)

    -- The recipe wishlist (the owner said build it, 2026-11-17): stars on
    -- recipes to learn, and a note at a vendor or trainer that teaches one.
    -- Off to start; off, nothing of it shows. See Logic/Wishlist.lua.
    CreateSection(pages.mail, 2, L["RECIPES"])
    local wishlistRow = CreateRow(pages.mail, 2, L["Recipe Wishlist:"],
        L["Star recipes you want to learn. A vendor or trainer that teaches one will tell you."])

    widgets.recipeWishlist = Widgets.CreateCheckbox(wishlistRow, L["On"], function(checked)
        if ns.Wishlist then ns.Wishlist:SetOn(checked) else Config:Set("recipeWishlistOn", checked) end
    end, false)
    widgets.recipeWishlist:SetPoint("TOPLEFT", CONTROL_X, -2)

    -- Asked 2026-10-06: the buy window opened at 1 after a Buy list search.
    CreateSection(pages.auction, 1, L["BUYING AND POSTING"])
    local fillBuyRow = CreateRow(pages.auction, 1, L["Fill In Buy Amount:"],
        L["Fills the quantity box with how many the queue still needs."])

    widgets.fillBuy = Widgets.CreateCheckbox(fillBuyRow, L["On"], function(checked)
        Config:Set("fillBuyQuantity", checked)
    end, true)
    widgets.fillBuy:SetPoint("TOPLEFT", CONTROL_X, -2)

    -- The owner, 2026-10-13: Red Dye was sent to the auction house.
    local vendorAuctionRow = CreateRow(pages.auction, 1, L["AH for Vendor Items:"],
        L["Sends you to the auction house for vendor items when they're cheaper there."])

    widgets.vendorAuction = Widgets.CreateCheckbox(vendorAuctionRow, L["On"], function(checked)
        Config:Set("vendorItemsOnAuction", checked)
        if ns.Queue and ns.Queue.Notify then ns.Queue:Notify() end
        UI:RefreshActiveTab()
    end, false)
    widgets.vendorAuction:SetPoint("TOPLEFT", CONTROL_X, -2)

    -- Asked 2026-10-11: the real cost of many could run far past the estimate.
    local buyWarnRow = CreateRow(pages.auction, 1, L["Warn When Price Is Higher:"],
        L["Warns under Buy Now when a material costs this much more than expected. 0 turns it off."])

    widgets.buyWarn = Widgets.CreateNumberBox(buyWarnRow, {
        width = 70, min = 0, max = 500,
        onChange = function(value)
            Config:Set("buyWarnPercent", value)
            if ns.BuyQuantity then ns.BuyQuantity:CheckCostSoon() end
        end,
    })
    widgets.buyWarn:SetPoint("TOPLEFT", CONTROL_X, 0)
    local buyWarnUnit = Theme.CreateLabel(buyWarnRow, "small", "muted")
    buyWarnUnit:SetPoint("LEFT", widgets.buyWarn, "RIGHT", 6, 0)
    buyWarnUnit:SetText(L["% over"])

    CreateSection(pages.pricing, 1, L["WHEN TO SELL"])
    local lossRow = CreateRow(pages.pricing, 1, L["Sell at a Loss:"],
        L["When off, losses show in red but aren't listed."])

    widgets.allowLoss = Widgets.CreateCheckbox(lossRow, L["On"], function(checked)
        Config:Set("allowPostingAtALoss", checked)
        UI:RefreshActiveTab()
    end, true)
    widgets.allowLoss:SetPoint("TOPLEFT", CONTROL_X, -2)

    -- Asked by a player on 2026-10-05: the guard above compares with what the
    -- materials cost today; this one with what the last craft actually cost.
    local paidRow = CreateRow(pages.pricing, 1, L["Never Below What I Paid:"],
        L["Won't list a craft for less than it cost to make."])

    widgets.neverBelowPaid = Widgets.CreateCheckbox(paidRow, L["On"], function(checked)
        Config:Set("neverBelowCraftedCost", checked)
        UI:RefreshActiveTab()
        if ns.PostPanel and ns.PostPanel.Refresh then ns.PostPanel:Refresh() end
    end, false)
    widgets.neverBelowPaid:SetPoint("TOPLEFT", CONTROL_X, -2)

    -- The owner asked (2026-11-16): crafts list at the least that still
    -- makes Minimum Profit when others sell for less (Logic/Profit.lua).
    local minProfitPostRow = CreateRow(pages.pricing, 1, L["Post at Minimum Profit:"],
        L["When others sell for less, your crafts list at the lowest price that still makes your Minimum Profit for their profession."])

    widgets.postAtMinProfit = Widgets.CreateCheckbox(minProfitPostRow, L["On"], function(checked)
        Config:Set("postAtMinProfit", checked)
        UI:RefreshActiveTab()
        if ns.PostPanel and ns.PostPanel.Refresh then ns.PostPanel:Refresh() end
    end, false)
    widgets.postAtMinProfit:SetPoint("TOPLEFT", CONTROL_X, -2)

    -- Logic/SisterKeeps.lua (2026-10-16): what the other Blackthornes
    -- addons want kept stays off List all.
    local sisterKeepsRow = CreateRow(pages.pricing, 1, L["Keep What Other Addons Need:"],
        L["Goal items, your upgrades and pet food stay off List all. What Butler keeps always does."])

    widgets.sisterKeeps = Widgets.CreateCheckbox(sisterKeepsRow, L["On"], function(checked)
        Config:Set("sellHoldsSisterKeeps", checked)
        if ns.SisterKeeps then ns.SisterKeeps:Forget() end
        UI:RefreshActiveTab()
        if ns.PostPanel and ns.PostPanel.Refresh then ns.PostPanel:Refresh() end
    end, false)
    widgets.sisterKeeps:SetPoint("TOPLEFT", CONTROL_X, -2)

    -- Off unless ticked (the owner, 2026-10-16): gear for another
    -- character goes up with everything else.
    local altKeepsRow = CreateRow(pages.pricing, 1, L["Keep Upgrades for Alts:"],
        L["Gear your other characters could wear stays off List all."])

    widgets.altKeeps = Widgets.CreateCheckbox(altKeepsRow, L["On"], function(checked)
        Config:Set("sellHoldsAltUpgrades", checked)
        if ns.SisterKeeps then ns.SisterKeeps:Forget() end
        UI:RefreshActiveTab()
        if ns.PostPanel and ns.PostPanel.Refresh then ns.PostPanel:Refresh() end
    end, false)
    widgets.altKeeps:SetPoint("TOPLEFT", CONTROL_X, -2)

    -- Off unless ticked (a player asked, the owner said build it
    -- 2026-11-17): what a known craft makes worth more stays off List all.
    local craftFirstRow = CreateRow(pages.pricing, 1, L["Craft First:"],
        L["Keeps items in your bags when a craft you know makes them worth more."])

    widgets.craftFirst = Widgets.CreateCheckbox(craftFirstRow, L["On"], function(checked)
        Config:Set("sellHoldsCraftFirst", checked)
        if ns.SisterKeeps then ns.SisterKeeps:Forget() end
        GreyQueueFromSell(widgets, checked)
        UI:RefreshActiveTab()
        if ns.PostPanel and ns.PostPanel.Refresh then ns.PostPanel:Refresh() end
    end, false)
    widgets.craftFirst:SetPoint("TOPLEFT", CONTROL_X, -2)

    -- Off unless ticked (the owner said build it, 2026-11-23): a row Craft
    -- First keeps back gets a Queue button, and Queue All shows by List
    -- Next. Greyed while Craft First is off, since nothing is kept to queue.
    local queueFromSellRow = CreateRow(pages.pricing, 1, L["Queue From Sell List:"],
        L["Adds a Queue button to items worth more crafted, and a Queue All button above the list."])
    widgets.queueFromSellRow = queueFromSellRow

    widgets.queueFromSell = Widgets.CreateCheckbox(queueFromSellRow, L["On"], function(checked)
        Config:Set("sellQueueFromList", checked)
        if ns.PostPanel and ns.PostPanel.Refresh then ns.PostPanel:Refresh() end
    end, false)
    widgets.queueFromSell:SetPoint("TOPLEFT", CONTROL_X, -2)

    -- The old "Confirm before each listing" switch (confirmBeforePosting)
    -- never did anything and its saved value is left where it is. The Yes/No
    -- box is "Ask Before Listing" below, a key of its own.
    local verifyRow = CreateRow(pages.auction, 1, L["Check Price First:"],
        L["Searches for the item first so your price is current."])

    widgets.verifyPrice = Widgets.CreateCheckbox(verifyRow, L["On"], function(checked)
        Config:Set("verifyPriceBeforePosting", checked)
    end, true)
    widgets.verifyPrice:SetPoint("TOPLEFT", CONTROL_X, -2)

    -- Fast listing (the owner, 2026-10-14): a fresh price lists on the
    -- click, with no Yes/No box. Unticked, every listing asks first.
    local fastRow = CreateRow(pages.auction, 1, L["Fast Listing:"],
        L["List All checks every price at once, then each click lists one with no Yes or No."])

    widgets.fastListing = Widgets.CreateCheckbox(fastRow, L["On"], function(checked)
        Config:Set("fastListing", checked)
    end, true)
    widgets.fastListing:SetPoint("TOPLEFT", CONTROL_X, -2)

    -- Ask before listing (the owner, 2026-10-28): off unless ticked. Off, a
    -- checked price lists on the click; one not checked yet is checked
    -- first and the next click lists it.
    local askRow = CreateRow(pages.auction, 1, L["Ask Before Listing:"],
        L["Shows a Yes or No box with the prices before each listing."])

    widgets.askBeforeListing = Widgets.CreateCheckbox(askRow, L["On"], function(checked)
        Config:Set("askBeforeListing", checked)
    end, false)
    widgets.askBeforeListing:SetPoint("TOPLEFT", CONTROL_X, -2)

    -- Bypass Disallowed Postings (the owner, 2026-10-31): off unless ticked.
    -- Ticked, a List click lists whatever this addon or its sisters would
    -- hold back or refuse (Posting:PostsAnyway).
    local anywayRow = CreateRow(pages.auction, 1, L["Bypass Disallowed Postings:"],
        L["List items even when it would normally wait or be held back."])

    widgets.postAnyway = Widgets.CreateCheckbox(anywayRow, L["On"], function(checked)
        Config:Set("postAnyway", checked)
        if ns.PostPanel and ns.PostPanel.Refresh then ns.PostPanel:Refresh() end
    end, false)
    widgets.postAnyway:SetPoint("TOPLEFT", CONTROL_X, -2)

    -- The mouse wheel (a player asked, the owner said build it, 2026-10-16):
    -- off unless ticked, and only while the auction house is open.
    local wheelRow = CreateRow(pages.auction, 1, L["Mouse Wheel:"],
        L["At the auction house, the wheel lists your next stack on Sell and cancels your next undercut auction on Auctions."])

    widgets.mouseWheel = Widgets.CreateCheckbox(wheelRow, L["On"], function(checked)
        Config:Set("mouseWheelListing", checked)
        if ns.AuctionWheel then ns.AuctionWheel:Update() end
    end, false)
    widgets.mouseWheel:SetPoint("TOPLEFT", CONTROL_X, -2)

    -- The Snipe tab (off unless ticked) and wheel buying inside it.
    local snipeRow = CreateRow(pages.auction, 1, L["Snipe Tab:"], nil)
    widgets.snipeTab = Widgets.CreateCheckbox(snipeRow, L["On"], function(checked)
        Config:Set("snipeTab", checked)
        if ns.PostPanel and ns.PostPanel.LayTabs then ns.PostPanel:LayTabs() end
        if ns.PostPanel and ns.PostPanel.Refresh then ns.PostPanel:Refresh() end
    end, false)
    widgets.snipeTab:SetPoint("TOPLEFT", CONTROL_X, -2)

    -- The crate list on Buy (the owner said build it, 2026-11-16).
    local crateListRow = CreateRow(pages.auction, 1, L["Crate Shopping List:"],
        L["Shows what your Waylaid Crates need on the Buy list at the auction house."])
    widgets.crateShoppingList = Widgets.CreateCheckbox(crateListRow, L["On"], function(checked)
        Config:Set("crateShoppingList", checked)
        if ns.PostPanel and ns.PostPanel.Refresh then
            ns.PostPanel.crateAt = nil
            ns.PostPanel:Refresh()
        end
    end, false)
    widgets.crateShoppingList:SetPoint("TOPLEFT", CONTROL_X, -2)

    local snipeWheelRow = CreateRow(pages.auction, 1, L["Wheel Buys:"],
        L["On the Snipe tab, wheel up buys the best find."])
    widgets.snipeWheel = Widgets.CreateCheckbox(snipeWheelRow, L["On"], function(checked)
        Config:Set("snipeWheel", checked)
        if ns.AuctionWheel then ns.AuctionWheel:Update() end
    end, false)
    widgets.snipeWheel:SetPoint("TOPLEFT", CONTROL_X, -2)

    -- The sale alarm and the scan chime moved down to SOUNDS, with a switch
    -- for every other sound (2026-10-02).
    CreateSection(pages.mail, 2, L["AFTER A SALE"])
    local mailReportRow = CreateRow(pages.mail, 2, L["Mail Report:"],
        L["Shows what you collected when you leave the mailbox."])

    widgets.mailReport = Widgets.CreateCheckbox(mailReportRow, L["On"], function(checked)
        Config:Set("mailReport", checked)
    end, true)
    widgets.mailReport:SetPoint("TOPLEFT", CONTROL_X, -2)

    local mailPreviewRow = CreateRow(pages.mail, 2, L["Sample Mail Report:"])

    local mailReportTest = Widgets.CreateButton(mailPreviewRow, L["Preview"], function()
        if ns.MailReport and ns.MailHaul then ns.MailReport:Show(ns.MailHaul:Sample()) end
    end, { width = 70, height = 20 })
    mailReportTest:SetPoint("TOPLEFT", CONTROL_X, -2)
    FitButton(mailReportTest)

    -- Requested by a player whose chat filled with sale lines: the Sales tab
    -- keeps every sale, so the chat copy can go.
    local saleChatRow = CreateRow(pages.mail, 2, L["Hide Sale Messages:"],
        L["Keeps \"A buyer has been found\" out of chat."])

    widgets.hideSaleChat = Widgets.CreateCheckbox(saleChatRow, L["On"], function(checked)
        Config:Set("hideSaleChat", checked)
        if checked and ns.SaleAlarm then ns.SaleAlarm:InstallChatHider() end
    end, false)
    widgets.hideSaleChat:SetPoint("TOPLEFT", CONTROL_X, -2)

    CreateSection(pages.pricing, 2, L["WHAT COUNTS AS PROFIT"])

    local profitRow = CreateRow(pages.pricing, 2, L["Minimum Profit:"],
        L["Crafts that make less than this are hidden on the Profit tab. Set your own for a profession below."])

    widgets.minProfit = Widgets.CreateNumberBox(profitRow, {
        width = 70, min = 0, max = 1000000,
        onChange = function(value)
            -- Entered in silver: copper is unusable at realistic values.
            Config:Set("minProfit", value * 100)
            widgets.minProfitPreview:SetText(Util.FormatMoney(value * 100, { short = true }))
            UI:RefreshActiveTab()
        end,
    })
    widgets.minProfit:SetPoint("TOPLEFT", CONTROL_X, 0)

    widgets.minProfitPreview = Theme.CreateLabel(profitRow, "small", "muted")
    widgets.minProfitPreview:SetPoint("LEFT", widgets.minProfit, "RIGHT", 6, 0)
    widgets.minProfitPreview:SetWidth(100)

    local marginRow = CreateRow(pages.pricing, 2, L["Minimum Margin:"],
        L["Profit as a share of the sale price."])

    widgets.minMargin = Widgets.CreateNumberBox(marginRow, {
        width = 70, min = 0, max = 100,
        onChange = function(value)
            Config:Set("minMarginPercent", value)
            UI:RefreshActiveTab()
        end,
    })
    widgets.minMargin:SetPoint("TOPLEFT", CONTROL_X, 0)
    AddUnit(marginRow, widgets.minMargin, "%")

    -- Minimums by profession (the owner said build it, 2026-11-17, from a
    -- mockup): a profit and a margin box per profession, empty for the
    -- numbers above (Profit:MinimumsFor). Rows made in Refresh, as the
    -- Keep in Stock by Profession list's are.
    local minimums = CreateFrame("Frame", nil, pages.pricing.content)
    minimums:SetSize(COLUMN_WIDTH, 1)
    Place(pages.pricing, 2, minimums)

    local minimumsLabel = Theme.CreateLabel(minimums, "small", "text")
    minimumsLabel:SetPoint("TOPLEFT", 0, -4)
    minimumsLabel:SetWidth(COLUMN_WIDTH)
    minimumsLabel:SetWordWrap(true)
    minimumsLabel:SetText(L["Minimums by Profession:"])

    local minimumsHint = Theme.CreateLabel(minimums, "tiny", "muted")
    minimumsHint:SetPoint("TOPLEFT", minimumsLabel, "BOTTOMLEFT", 0, -4)
    minimumsHint:SetWidth(COLUMN_WIDTH)
    minimumsHint:SetWordWrap(true)
    minimumsHint:SetText(L["Leave a box empty to use Minimum Profit and Minimum Margin above."])

    local minimumsHeads = CreateFrame("Frame", nil, minimums)
    minimumsHeads:SetSize(COLUMN_WIDTH, 16)
    minimumsHeads:SetPoint("TOPLEFT", minimumsHint, "BOTTOMLEFT", 0, -6)
    for _, head in ipairs({
        { L["PROFESSION"], 8 }, { L["PROFIT"], MINIMUM_PROFIT_X }, { L["MARGIN"], MINIMUM_MARGIN_X },
    }) do
        local text = Theme.CreateLabel(minimumsHeads, "tiny", "dim")
        text:SetPoint("LEFT", head[2], 0)
        text:SetText(head[1])
    end

    local minimumsEmpty = Theme.CreateLabel(minimums, "small", "dim")
    minimumsEmpty:SetPoint("TOPLEFT", minimumsHeads, "BOTTOMLEFT", 0, -4)
    minimumsEmpty:SetWidth(COLUMN_WIDTH)
    minimumsEmpty:SetWordWrap(true)
    minimumsEmpty:SetText(L["None yet. Open a profession window on each character once, and its professions show here."])

    widgets.minimums, widgets.minimumsLabel, widgets.minimumsHint = minimums, minimumsLabel, minimumsHint
    widgets.minimumsHeads, widgets.minimumsEmpty, widgets.minimumRows = minimumsHeads, minimumsEmpty, {}
    Searchable(pages.pricing, minimums, L["Minimums by Profession:"] .. " "
        .. L["minimum profit margin by profession per profession alchemy blacksmithing tailoring leatherworking"])

    -- Gold an hour, buy the parts or make them (a Discord player, the
    -- owner said build it 2026-11-12, casting time only). Off unless ticked.
    local hourRow = CreateRow(pages.pricing, 2, L["Gold an Hour:"],
        L["Shows whether buying the parts or making them earns more an hour. Only crafting time counts, not buying or selling."])

    widgets.goldAnHour = Widgets.CreateCheckbox(hourRow, L["On"], function(checked)
        UI:SetGoldAnHour(checked == true)
    end, false)
    widgets.goldAnHour:SetPoint("TOPLEFT", CONTROL_X, -2)

    CreateSection(pages.pricing, 2, L["PRICE AGE"])
    local staleRow = CreateRow(pages.pricing, 2, L["Prices Go Stale After:"],
        L["Older prices are greyed out but still used."])

    widgets.stale = Widgets.CreateDropdown(staleRow, {
        { text = L["12 hours"], value = 12 * 3600 },
        { text = L["24 hours"], value = 24 * 3600 },
        { text = L["2 days"], value = 48 * 3600 },
        { text = L["7 days"], value = 7 * 24 * 3600 },
    }, function(value)
        Config:Set("staleAfterSeconds", value)
        UI:RefreshActiveTab()
    end, { width = 110 })
    widgets.stale:SetPoint("TOPLEFT", CONTROL_X, 0)

    -- Six lists in one box (the owner said build it, 2026-11-16, from a
    -- mockup): "Show:" picks the list drawn, each name with how many are in
    -- it. Each list keeps its own hint, rows and buttons in a holder of its
    -- own, and only the one picked shows (ShowQueueList). The pick is kept
    -- in `settingsQueueList`, as the page is in settingsPage.
    CreateSection(pages.queue, 2, L["YOUR LISTS"])
    local listRow = CreateRow(pages.queue, 2, L["Show:"], nil)
    widgets.queueList = Widgets.CreateDropdown(listRow, {}, function(key)
        Config:Set("settingsQueueList", key)
        widgets.queueListFound = nil
        ShowQueueList()
    end, { width = COLUMN_WIDTH - LIST_BOX_X })
    widgets.queueList:SetPoint("TOPLEFT", LIST_BOX_X, 0)
    widgets.queueLists = {}

    --- One list's holder: its hint (or a line to hang rows on), and the
    --- words for when it is empty.
    local function ListGroup(key, title, hintText, emptyText, words, step)
        local holder = CreateFrame("Frame", nil, pages.queue.content)
        holder:SetPoint("TOPLEFT", listRow, "BOTTOMLEFT", 0, -8)
        holder:SetSize(COLUMN_WIDTH, 1)
        holder:Hide()

        local hint
        if hintText then
            hint = Theme.CreateLabel(holder, "tiny", "muted")
            hint:SetPoint("TOPLEFT", 0, 0)
            hint:SetWidth(COLUMN_WIDTH)
            hint:SetWordWrap(true)
            hint:SetText(hintText)
        else
            -- Rows hang 6 under their hint; this one sits 6 up so they start at the top.
            hint = CreateFrame("Frame", nil, holder)
            hint:SetSize(COLUMN_WIDTH, 1)
            hint:SetPoint("TOPLEFT", 0, 7)
        end

        local empty = Theme.CreateLabel(holder, "small", "dim")
        empty:SetWidth(COLUMN_WIDTH)
        empty:SetWordWrap(true)
        empty:SetText(emptyText)

        local group = { key = key, title = title, holder = holder, hint = hint,
            empty = empty, count = 0, shown = 0, step = step or (IGNORED_ROW_HEIGHT + 2) }
        widgets.queueLists[#widgets.queueLists + 1] = group
        widgets.queueLists[key] = group
        Searchable(pages.queue, listRow, words, function() FindQueueList(key) end)
        return group
    end

    -- Keep in stock by profession (a player asked, the owner agreeing
    -- 2026-10-13): one box per profession your characters craft with,
    -- empty for the usual number. Rows made in Refresh, as the lists are.
    local stock = ListGroup("stock", L["Keep in Stock by Profession"],
        L["Leave a box empty to use Keep in Stock. A number on one item in the Profit tab still wins."],
        L["None yet. Open a profession window on each character once, and its professions show here."],
        L["Keep in stock by profession per profession alchemy blacksmithing tailoring leatherworking stock limit"],
        STOCK_ROW_HEIGHT)
    widgets.stockHint, widgets.stockEmpty, widgets.stockRows = stock.hint, stock.empty, {}

    -- Items Raise When Sold Out changed (the owner, 2026-10-16), with
    -- Reset to put each back.
    local changed = ListGroup("changed", L["Changed When Sold Out"],
        L["Keep in Stock numbers that Raise When Sold Out changed. Click Reset to put one back."],
        L["None yet."],
        L["Changed when sold out raise when sold out keep in stock reset"])
    widgets.changedHint, widgets.changedEmpty, widgets.changedRows = changed.hint, changed.empty, {}

    -- Crafts never made to go into another craft (2026-10-07), marked from
    -- the Level Up tab or the x on a queued sub-craft.
    local never = ListGroup("never", L["Never Made as Sub-Crafts"],
        L["These are bought, not made, when another craft needs them. Click Allow to put one back."],
        L["None. Click Make beside a craft on the Level Up tab (tick Sub-crafts only), or the x on a sub-craft in the queue."],
        L["Never made as sub-crafts bought instead intermediates allow light leather"])
    widgets.neverHint, widgets.neverEmpty, widgets.neverRows = never.hint, never.empty, {}

    -- Crafts taken off the Profit tab with its Ignore button.
    local ignored = ListGroup("ignored", L["Ignored Crafts"],
        L["These never show on the Profit tab, on any character. Click Restore to bring one back."],
        L["None. Pick a craft on the Profit tab and click Ignore."],
        L["Ignored crafts Restore puts one back on the Profit tab"])
    widgets.ignoredHint, widgets.ignoredEmpty, widgets.ignoredRows = ignored.hint, ignored.empty, {}

    -- Items taken off Ready to sell at the auction house with the x on
    -- their row (2026-10-04).
    local ignoredItems = ListGroup("items", L["Ignored Items"],
        L["These are never offered for sale on Ready to sell, on any character. Click Restore to bring one back."],
        L["None. Click the x on an item in Ready to sell at the auction house."],
        L["Ignored items Restore puts one back on Ready to sell"])
    widgets.ignoredItemsHint, widgets.ignoredItemsEmpty, widgets.ignoredItemsRows =
        ignoredItems.hint, ignoredItems.empty, {}

    -- What this character keeps back from the Sell list (Logic/KeepHere.lua,
    -- a player asked, the owner said build it 2026-10-18). Set by
    -- right-clicking a Sell list row; Clear takes one off.
    local keepHere = ListGroup("keep", L["Keep on This Character"], nil,
        L["Right-click an item on the Sell list to keep some on this character."],
        L["Keep on this character Sell list right-click"])
    widgets.keepHereSection, widgets.keepHereEmpty, widgets.keepHereRows = keepHere.hint, keepHere.empty, {}

    local data = CreateSection(pages.data, 1, L["SAVED DATA"])

    -- All four wrap: "last scan 3h ago (stopped at the page limit)" and the
    -- bank and auction warnings are longer than the column, and were cut
    -- off. Refresh measures the page after setting them.
    widgets.dataSummary = Theme.CreateLabel(pages.data.content, "small", "text")
    widgets.dataSummary:SetPoint("TOPLEFT", data, "BOTTOMLEFT", 0, -6)
    widgets.dataSummary:SetWidth(COLUMN_WIDTH)
    widgets.dataSummary:SetWordWrap(true)

    widgets.recipeSummary = Theme.CreateLabel(pages.data.content, "small", "text")
    widgets.recipeSummary:SetPoint("TOPLEFT", widgets.dataSummary, "BOTTOMLEFT", 0, -4)
    widgets.recipeSummary:SetWidth(COLUMN_WIDTH)
    widgets.recipeSummary:SetWordWrap(true)

    widgets.bankSummary = Theme.CreateLabel(pages.data.content, "tiny", "dim")
    widgets.bankSummary:SetPoint("TOPLEFT", widgets.recipeSummary, "BOTTOMLEFT", 0, -6)
    widgets.bankSummary:SetWidth(COLUMN_WIDTH)
    widgets.bankSummary:SetWordWrap(true)

    widgets.auctionSummary = Theme.CreateLabel(pages.data.content, "tiny", "dim")
    widgets.auctionSummary:SetPoint("TOPLEFT", widgets.bankSummary, "BOTTOMLEFT", 0, -4)
    widgets.auctionSummary:SetWidth(COLUMN_WIDTH)
    widgets.auctionSummary:SetWordWrap(true)

    widgets.loadWarning = Theme.CreateLabel(pages.data.content, "tiny", "warn")
    widgets.loadWarning:SetPoint("TOPLEFT", widgets.auctionSummary, "BOTTOMLEFT", 0, -6)
    widgets.loadWarning:SetWidth(COLUMN_WIDTH)
    widgets.loadWarning:SetWordWrap(true)

    pages.data.last[1] = widgets.loadWarning
    local pruneRow = CreateRow(pages.data, 1, L["Remove Old Prices:"],
        L["Drops items not seen at the auction house for 21 days."])
    pruneRow:ClearAllPoints()
    pruneRow:SetPoint("TOPLEFT", widgets.loadWarning, "BOTTOMLEFT", 0, -18)
    local pruneButton = Widgets.CreateButton(pruneRow, L["Remove"], function()
        local removed = ns.Prices:Prune()
        ns.Print(L.Format("removed %d old price(s)", removed))
        UI:RefreshActiveTab()
    end, { width = 80, height = 20 })
    pruneButton:SetPoint("TOPLEFT", CONTROL_X, -2)
    FitButton(pruneButton)

    -- A lighter save (the owner said build it, 2026-11-26, from the
    -- mockup): how big the save is, Tidy Up, and Keep Price History For.
    -- Logic/TidyUp.lua and UI/TidyUpBox.lua; nothing is removed until the
    -- Tidy Up window's Confirm.
    local sizeRow = CreateRow(pages.data, 1, L["Saved Data:"],
        L["A smaller save makes logging in and /reload faster."])
    widgets.saveSize = Theme.CreateLabel(sizeRow, "small", "text")
    widgets.saveSize:SetPoint("TOPLEFT", CONTROL_X, -5)
    widgets.saveSize:SetText("...")
    widgets.tidyUp = Widgets.CreateButton(sizeRow, L["Tidy Up"], function(self)
        if self.disabled or not ns.TidyUpBox then return end
        ns.TidyUpBox:Open(ns.TidyUp:Days(), nil, function()
            if ns.TidyUp then ns.TidyUp:Measure() end
            UI:RefreshActiveTab()
        end)
    end, { width = 80, height = 20 })
    widgets.tidyUp:SetPoint("LEFT", widgets.saveSize, "RIGHT", 10, 0)
    FitButton(widgets.tidyUp)

    local keepRow = CreateRow(pages.data, 1, L["Keep Price History For:"],
        L["For items you don't craft, star or sell. Yours are always kept in full."])
    widgets.keepHistory = Widgets.CreateDropdown(keepRow, {
        { text = L["30 Days"], value = 30 },
        { text = L["90 Days"], value = 90 },
        { text = L["A Year"], value = 365 },
        { text = L["Always"], value = 0 },
    }, function(days)
        if not ns.TidyUp then return end
        if days == 0 then
            ns.TidyUp:KeepAlways()
            UI:RefreshActiveTab()
            return
        end
        -- Ask first: the choice is saved only by Confirm.
        ns.TidyUpBox:Open(days, function()
            widgets.keepHistory:SetValue(ns.TidyUp:Days())
            UI:RefreshActiveTab()
        end, function()
            ns.TidyUp:Measure()
            UI:RefreshActiveTab()
        end)
    end, { width = 110 })
    widgets.keepHistory:SetPoint("TOPLEFT", CONTROL_X, 0)

    -- Clear price data and Reset to defaults are typed commands now (the
    -- owner, 2026-10-15): /bts clearprices confirm and /bts reset confirm.
    -- Settings never deletes data.

    CreateSection(pages.queue, 1, L["EXPORT AND IMPORT"])
    local exportButton = Widgets.CreateButton(pages.queue.content, L["Export"], function()
        UI:ShowTransferDialog("export")
    end, { width = 100, height = 22,
           tooltip = L["Copy your queue, settings and stock limits as a code."] })
    Place(pages.queue, 1, exportButton, -8)
    FitButton(exportButton)

    local importButton = Widgets.CreateButton(pages.queue.content, L["Import"], function()
        UI:ShowTransferDialog("import")
    end, { width = 100, height = 22,
           tooltip = L["Load a code."] })
    FitButton(importButton)
    importButton:SetPoint("LEFT", exportButton, "RIGHT", 8, 0)

    local exportPrices = Widgets.CreateButton(pages.queue.content, L["Export Prices"], function()
        UI:ShowTransferDialog("exportPrices")
    end, { width = 100, height = 22,
           tooltip = L["Copy your recent auction prices as a code to use on another computer."] })
    Place(pages.queue, 1, exportPrices, -8)
    FitButton(exportPrices)

    local importPrices = Widgets.CreateButton(pages.queue.content, L["Import Prices"], function()
        UI:ShowTransferDialog("importPrices")
    end, { width = 100, height = 22,
           tooltip = L["Load a prices code. Only prices newer than yours are used."] })
    FitButton(importPrices)
    importPrices:SetPoint("LEFT", exportPrices, "RIGHT", 8, 0)

    CreateSection(pages.auction, 2, L["SCANNING"])

    local budgetRow = CreateRow(pages.auction, 2, L["Scan Speed:"],
        L["Higher is faster, but the game can stutter."])

    widgets.budget = Widgets.CreateNumberBox(budgetRow, {
        width = 60, min = 2, max = 16,
        onChange = function(value) Config:Set("scanBudgetMs", value) end,
    })
    widgets.budget:SetPoint("TOPLEFT", CONTROL_X, 0)
    AddUnit(budgetRow, widgets.budget, L["ms"])

    local autoScanRow = CreateRow(pages.auction, 2, L["Auto Scan:"],
        L["Does one quick scan when you open the auction house, if you haven't scanned in the last 15 minutes."])

    widgets.autoScan = Widgets.CreateCheckbox(autoScanRow, L["On"], function(checked)
        Config:Set("autoScan", checked)
    end, true)
    widgets.autoScan:SetPoint("TOPLEFT", CONTROL_X, -2)

    local saleTotalRow = CreateRow(pages.auction, 2, L["Potential Sale Total:"],
        L["What everything ready to sell should bring in, at the prices on the list. It stays the same as you list things, and follows the prices as a scan runs."])

    widgets.saleTotal = Widgets.CreateCheckbox(saleTotalRow, L["On"], function(checked)
        Config:Set("saleTotal", checked)
        if ns.PostPanel and ns.PostPanel.Refresh then ns.PostPanel:Refresh() end
    end, true)
    widgets.saleTotal:SetPoint("TOPLEFT", CONTROL_X, -2)

    local learnRow = CreateRow(pages.auction, 2, L["Learn From Searches:"],
        L["Also takes prices from your own searches."])

    widgets.learnFromSearches = Widgets.CreateCheckbox(learnRow, L["On"], function(checked)
        Config:Set("learnFromSearches", checked)
    end, true)
    widgets.learnFromSearches:SetPoint("TOPLEFT", CONTROL_X, -2)

    -- The Tooltips page (the owner said build it, 2026-11-16, from a mockup):
    -- one box on top sets every tooltip line at once, and each line keeps a
    -- box of its own. Nothing new is saved: All Lines writes each line's own
    -- setting, and shows Mixed while the lines differ.
    CreateSection(pages.tooltips, 1, L["ON ITEM TOOLTIPS"])
    local allLinesRow = CreateRow(pages.tooltips, 1, L["All Lines:"],
        L["Sets every line below at once. You can still change each one after."])
    widgets.tooltipAll = Widgets.CreateDropdown(allLinesRow, {
        { text = ns.TooltipShift.NAMES[ns.TooltipShift.OFF], value = ns.TooltipShift.OFF },
        { text = ns.TooltipShift.NAMES[ns.TooltipShift.SHIFT], value = ns.TooltipShift.SHIFT },
        { text = ns.TooltipShift.NAMES[ns.TooltipShift.ALWAYS], value = ns.TooltipShift.ALWAYS },
    }, function(mode)
        SetAllTooltipLines(mode)
    end, { width = 110, placeholder = L["Mixed"] })
    widgets.tooltipAll:SetPoint("TOPLEFT", CONTROL_X, 0)

    -- Off, Shift or Always for each tooltip line (asked 2026-10-18, see
    -- UI/TooltipShift.lua). Whether the line is on stays in its own
    -- setting; Shift is kept beside it. The sales lines have no Off.
    local function ShiftDropdown(row, key, setting, onChange)
        local Shift = ns.TooltipShift
        local options = {}
        if setting then options[#options + 1] = { text = Shift.NAMES[Shift.OFF], value = Shift.OFF } end
        options[#options + 1] = { text = Shift.NAMES[Shift.SHIFT], value = Shift.SHIFT }
        options[#options + 1] = { text = Shift.NAMES[Shift.ALWAYS], value = Shift.ALWAYS }

        local function ApplyMode(mode)
            local isOn = setting == nil or Config:Get(setting) ~= false
            Shift:Apply(mode, key, isOn, setting and function(on)
                Config:Set(setting, on)
                if onChange then onChange() end
            end or nil)
        end
        local dropdown = Widgets.CreateDropdown(row, options, function(mode)
            ApplyMode(mode)
            ShowAllLinesMode()
        end, { width = 110 })
        dropdown:SetPoint("TOPLEFT", CONTROL_X, 0)
        dropdown.shiftKey, dropdown.shiftSetting = key, setting
        dropdown.applyMode = ApplyMode
        return dropdown
    end

    local tooltipValueRow = CreateRow(pages.tooltips, 1, L["Value on Tooltips:"])

    widgets.tooltipValue = ShiftDropdown(tooltipValueRow, "value", "showValueOnItemTooltips")

    -- Asked 2026-10-13: the sales lines under Demand, kept for Shift.
    local salesShiftRow = CreateRow(pages.tooltips, 1, L["Sales Details:"],
        L["The sales lines under Demand."])

    widgets.tooltipSalesShift = ShiftDropdown(salesShiftRow, "sales", nil)

    -- Asked 2026-10-14: the Prices tab's trend on the tooltip too.
    local trendRow = CreateRow(pages.tooltips, 1, L["Price Trend on Tooltips:"],
        L["How much the price moved from its 7 or 14 day average."])

    widgets.tooltipTrend = ShiftDropdown(trendRow, "trend", "tooltipTrend")

    -- Asked 2026-10-05: is a recipe worth buying, at a glance. The button
    -- is /bts recipes.
    local recipeTipRow = CreateRow(pages.tooltips, 1, L["Recipe Value on Tooltips:"],
        L["On a recipe, shows its cost, what it sells for, and how many crafts pay it back."])

    widgets.recipeTooltips = ShiftDropdown(recipeTipRow, "recipe", "showRecipeValueOnTooltips")

    -- Asked 2026-10-14: what an enchant's materials cost, on its tooltip.
    local enchantTipRow = CreateRow(pages.tooltips, 1, L["Enchant Costs on Tooltips:"],
        L["On an enchant, shows what each material costs and who knows it."])

    widgets.enchantTooltips = ShiftDropdown(enchantTipRow, "enchant", "tooltipEnchantCosts", function()
        if ns.EnchantTooltip and ns.EnchantTooltip.Forget then ns.EnchantTooltip:Forget() end
    end)

    -- Asked 2026-10-29: what gear can break into, and the chance of each.
    local disenchantTipRow = CreateRow(pages.tooltips, 1, L["Disenchant Results on Tooltips:"],
        L["On gear you can disenchant, shows what it can break into and the chance of each."])

    widgets.disenchantTooltips = ShiftDropdown(disenchantTipRow, "disenchant", "tooltipDisenchantResults")

    -- Asked 2026-10-20: what a Waylaid Crate costs to fill, on its tooltip.
    local crateTipRow = CreateRow(pages.tooltips, 1, L["Crate Costs:"])

    widgets.crateTooltips = ShiftDropdown(crateTipRow, "crate", "tooltipCrateCosts")

    -- A player asked (2026-11-12): what you paid on the auction house.
    local boughtTipRow = CreateRow(pages.tooltips, 1, L["Bought For on Tooltips:"],
        L["What you last paid for an item on the auction house. Hold Shift for the average."])

    widgets.boughtTooltips = ShiftDropdown(boughtTipRow, "bought", "tooltipBoughtFor")

    -- Asked 2026-11-17: which professions use a material.
    local usedInTipRow = CreateRow(pages.tooltips, 1, L["Used In Recipes:"],
        L["Shows which professions use a material and how many of your recipes need it. Hold Shift for the recipe names."])

    widgets.usedInTooltips = ShiftDropdown(usedInTipRow, "usedin", "tooltipUsedIn")

    CreateSection(pages.tooltips, 2, L["IN THE PROFESSION WINDOW"])
    local professionValueRow = CreateRow(pages.tooltips, 2, L["Value in Profession Window:"],
        L["Shows what each recipe sells for beside its name."])

    widgets.professionValue = Widgets.CreateCheckbox(professionValueRow, L["On"], function(checked)
        Config:Set("showValueInProfessionWindow", checked)
        if ns.RecipeValue then ns.RecipeValue:Refresh() end
    end, true)
    widgets.professionValue:SetPoint("TOPLEFT", CONTROL_X, -2)

    local craftProfitRow = CreateRow(pages.tooltips, 2, L["Craft Cost and Profit:"],
        L["Show the profit beside each recipe in the game's profession window, and what the mats cost when you pick one."])

    widgets.craftProfit = Widgets.CreateCheckbox(craftProfitRow, L["On"], function(checked)
        Config:Set("craftProfitInProfessionWindow", checked)
        if ns.RecipeValue then ns.RecipeValue:Refresh() end
        if ns.CraftProfitCard then ns.CraftProfitCard:Refresh() end
    end, true)
    widgets.craftProfit:SetPoint("TOPLEFT", CONTROL_X, -2)

    -- Enchant window (the owner said build it, 2026-11-05): since 2026-11-06 a
    -- strip under the recipe in the Enchanting window. Off unless ticked (Logic/EnchantWindow.lua).
    local enchantRow = CreateRow(pages.tooltips, 2, L["Enchant Window:"], nil)
    widgets.enchantWindow = Widgets.CreateCheckbox(enchantRow, L["On"], function(checked)
        if ns.EnchantWindow then ns.EnchantWindow:SetOn(checked) else Config:Set("enchantWindow", checked) end
    end, false)
    widgets.enchantWindow:SetPoint("TOPLEFT", CONTROL_X, -2)

    CreateSection(pages.tooltips, 2, L["SHOWN IN THE GAME"])
    local upgradeRow = CreateRow(pages.tooltips, 2, L["Upgrade Arrows:"],
        L["A green arrow on gear that's an upgrade for you. Needs Blackthornes Equipment."])

    widgets.upgradeArrows = Widgets.CreateCheckbox(upgradeRow, L["On"], function(checked)
        Config:Set("showUpgradeArrows", checked)
        if ns.Upgrades then ns.Upgrades:Forget() end
        UI:RefreshActiveTab()
    end, true)
    widgets.upgradeArrows:SetPoint("TOPLEFT", CONTROL_X, -2)

    -- Logic/Cooldowns.lua (asked 2026-10-12): a line in chat when a
    -- transmute, Mooncloth or the Salt Shaker is ready on any character,
    -- and a step for it in Blackthornes Butler. The list stays typed:
    -- /bts cooldowns (the owner, 2026-10-15).
    local cooldownRow = CreateRow(pages.tooltips, 2, L["Profession Cooldowns:"],
        L["Says in chat when a transmute, Mooncloth or the Salt Shaker is ready."])

    widgets.cooldownAlerts = Widgets.CreateCheckbox(cooldownRow, L["On"], function(checked)
        Config:Set("cooldownAlerts", checked)
        if ns.Cooldowns then ns.Cooldowns:Schedule() end
    end, true)
    widgets.cooldownAlerts:SetPoint("TOPLEFT", CONTROL_X, -2)

    -- Logic/CraftRequests.lua (asked 2026-10-12): a line in chat when
    -- someone in Trade asks for something one of your characters makes.
    local requestsRow = CreateRow(pages.tooltips, 2, L["Trade Requests:"],
        L["Says in chat when someone in Trade asks for something you can make."])

    widgets.tradeRequests = Widgets.CreateCheckbox(requestsRow, L["On"], function(checked)
        Config:Set("tradeRequests", checked)
    end, false)
    widgets.tradeRequests:SetPoint("TOPLEFT", CONTROL_X, -2)

    -- What each disenchant gave, in chat (a player asked, 2026-11-13).
    local deChatRow = CreateRow(pages.tooltips, 2, L["Disenchant Results:"],
        L["Says in chat what each disenchant gave."])
    widgets.disenchantChat = Widgets.CreateCheckbox(deChatRow, L["Show"], function(checked)
        if ns.DisenchantLog then ns.DisenchantLog:SetChat(checked) else Config:Set("disenchantChat", checked) end
    end, true)
    widgets.disenchantChat:SetPoint("TOPLEFT", CONTROL_X, -2)

    -- Disenchants at an Arcane Salvager in their own record (the owner said
    -- build it, 2026-11-24; Logic/DisenchantLog.lua, `salvagerApart`).
    local salvagerRow = CreateRow(pages.tooltips, 2, L["Keep Salvager Results Apart:"],
        L["Disenchants you do at an Arcane Salvager go in their own record, so you can see how much more they give. Your other disenchants and their chances stay the same."])
    widgets.salvagerApart = Widgets.CreateCheckbox(salvagerRow, L["On"], function(checked)
        Config:Set("salvagerApart", checked)
        if not checked and ns.DisenchantLog then ns.DisenchantLog:StopSalvager() end
        if ns.UI and ns.UI.RefreshActiveTab then pcall(ns.UI.RefreshActiveTab, ns.UI) end
    end, true)
    widgets.salvagerApart:SetPoint("TOPLEFT", CONTROL_X, -2)

    -- Old plain results (a player asked, the owner said build it,
    -- 2026-11-25): disenchants from before Keep Salvager Results Apart all
    -- sit in the plain record. Move them into the Salvager one, or clear
    -- them, each after a Confirm. Logic/DisenchantLog.lua does the work.
    local plainRow = CreateRow(pages.tooltips, 2, L["Plain Disenchant Results:"],
        L["If you did your old disenchants at an Arcane Salvager, move them there. Or clear them to start fresh. Your Salvager results stay as they are."])
    local function AskPlain(title, text, act, done)
        local log = ns.DisenchantLog
        local count = log and log:PlainCount() or 0
        if count == 0 or not ns.PostConfirm then return end
        ns.PostConfirm:Show({
            title = title, text = L.Format(text, count), yes = L["Confirm"], no = L["Cancel"], noIcon = true,
            accept = function()
                local n = log[act](log)
                if n > 0 then ns.Print(done(n)) end
                UI:RefreshSettingsPlain()
            end,
        })
    end
    widgets.plainMove = Widgets.CreateButton(plainRow, L["Move to Salvager"], function()
        AskPlain(L["Move to Salvager"],
            L["Move all %d plain disenchants into your Salvager results. Do this only if you did them at an Arcane Salvager."],
            "MovePlainToSalvager",
            function(n) return L.Format(L["Moved %d disenchants to your Salvager results."], n) end)
    end, { width = 60, height = 20 })
    widgets.plainMove:SetPoint("TOPLEFT", CONTROL_X, -2)
    FitButton(widgets.plainMove)
    widgets.plainClear = Widgets.CreateButton(plainRow, L["Clear"], function()
        AskPlain(L["Clear Plain Results"],
            L["Clear all %d plain disenchants. Values use the built-in table until you disenchant more. This can't be undone."],
            "ClearPlain",
            function() return L["Your plain disenchant results are cleared."] end)
    end, { width = 40, height = 20 })
    widgets.plainClear:SetPoint("LEFT", widgets.plainMove, "RIGHT", 4, 0)
    FitButton(widgets.plainClear)

    -- The "made 1 of X, 4 left" lines while crafting from the queue (a
    -- player asked, the owner said build it, 2026-11-17).
    local craftChatRow = CreateRow(pages.tooltips, 2, L["Craft Messages:"],
        L["Says in chat each time you make something from your queue."])
    widgets.craftChat = Widgets.CreateCheckbox(craftChatRow, L["On"], function(checked)
        Config:Set("craftChat", checked)
    end, true)
    widgets.craftChat:SetPoint("TOPLEFT", CONTROL_X, -2)

    -- All Addons: the rows every Blackthornes addon shares, shown once in
    -- the one window behind its gear (the owner said build it,
    -- 2026-11-16). Windows keeps Tradeskills' own: Window Size, what opens
    -- by itself, the small windows and the sounds. No setting was renamed
    -- and no saved choice changed.
    CreateSection(pages.all, 1, L["ALL BLACKTHORNES ADDONS"])
    CreateSection(pages.windows, 1, L["WINDOWS"])
    -- Asked 2026-10-10: the game's own look for players who would rather
    -- the windows matched the rest of their screen. Read at login, so it
    -- waits for /reload as Text size does. See UI/BlizzardLook.lua.
    local styleRow = CreateRow(pages.all, 1, L["Window Style:"])

    widgets.windowStyle = Widgets.CreateDropdown(styleRow, {
        { text = "Titanforged", value = "titanforged" },
        { text = "Blizzard", value = "blizzard" },
    }, function(value)
        Config:Set("windowStyle", value)
        local Look = ns.BlizzardLook
        widgets.styleReload:SetShown(Look and Look.Style() ~= value or false)
    end, { width = 110 })
    widgets.windowStyle:SetPoint("TOPLEFT", CONTROL_X, 0)

    widgets.styleReload = Widgets.CreateButton(styleRow, L["Reload"], function()
        if ReloadUI then ReloadUI() end
    end, { width = 90, height = 20 })
    FitButton(widgets.styleReload)
    ReloadUnder(styleRow, widgets.windowStyle, widgets.styleReload)
    widgets.styleReload:Hide()

    -- Asked 2026-10-07 ("I'm getting old"): bigger letters in the same
    -- window. Every size is read as text is drawn, so it waits for /reload.
    local textRow = CreateRow(pages.all, 1, L["Text Size:"])

    widgets.textSize = Widgets.CreateDropdown(textRow, {
        { text = L["Normal"], value = "normal" },
        { text = L["Large"], value = "large" },
        { text = L["Larger"], value = "larger" },
    }, function(value)
        Config:Set("textSize", value)
        local now = Theme.TextStep and Theme.TextStep() or 0
        local wanted = Theme.TEXT_STEPS and Theme.TEXT_STEPS[value] or 0
        widgets.textReload:SetShown(now ~= wanted)
    end, { width = 110 })
    widgets.textSize:SetPoint("TOPLEFT", CONTROL_X, 0)

    -- ReloadUI is allowed from a click, and saves everything first.
    widgets.textReload = Widgets.CreateButton(textRow, L["Reload"], function()
        if ReloadUI then ReloadUI() end
    end, { width = 90, height = 20 })
    FitButton(widgets.textReload)
    ReloadUnder(textRow, widgets.textSize, widgets.textReload)
    widgets.textReload:Hide()

    -- Look choices (the owner said build it, 2026-11-26): the same three
    -- rows in every Blackthornes addon, picked once for all of them. Font
    -- and Colors are read at login, so they wait for /reload. See
    -- UI/SharedChoices.lua.
    local Shared = ns.SharedChoices
    -- "Clear" is a button's word elsewhere, so the font names carry
    -- "##font" (as "Queue##sell"), shown without it where no translation.
    local function FontWord(english, word)
        if word:find("##", 1, true) then return english end
        return word
    end
    widgets.look = {}
    local LOOK_ROWS = {
        { kind = "font", label = L["Font:"],
          tip = L["House, Game or Clear. Clear is plain and easy to read, and it has Russian letters."],
          names = { house = FontWord("House", L["House##font"]), game = FontWord("Game", L["Game##font"]), clear = FontWord("Clear", L["Clear##font"]) } },
        { kind = "colors", label = L["Colors:"],
          tip = L["Warm is the look today. Darker takes the warm tint out of the glass."],
          names = { warm = L["Warm"], darker = L["Darker"] } },
        { kind = "fold", label = L["Fold Gem:"],
          tip = L["What a folded window turns into: the round button, or a small bar with its title."],
          names = { round = L["Round Button"], bar = L["Small Bar"] } },
    }
    for _, look in ipairs(Shared and Shared.LOOKS and LOOK_ROWS or {}) do
        local kind = look.kind
        local row = CreateRow(pages.all, 1, look.label, look.tip)
        local items = {}
        for _, value in ipairs(Shared.LOOKS[kind]) do
            items[#items + 1] = { text = look.names[value], value = value }
        end
        local entry = {}
        entry.dropdown = Widgets.CreateDropdown(row, items, function(value)
            Shared:SetLook(kind, value)
            if entry.reload then entry.reload:SetShown(Shared:NeedsReload(kind)) end
        end, { width = 130 })
        entry.dropdown:SetPoint("TOPLEFT", CONTROL_X, 0)
        if kind ~= "fold" then
            entry.reload = Widgets.CreateButton(row, L["Reload"], function()
                if ReloadUI then ReloadUI() end
            end, { width = 90, height = 20 })
            FitButton(entry.reload)
            ReloadUnder(row, entry.dropdown, entry.reload)
            entry.reload:Hide()
        end
        widgets.look[kind] = entry
    end

    -- A player's request (2026-10-07): the window was too big on a 4K
    -- screen. The grip below its bottom right corner does the same, to any
    -- size; one dragged to shows in the box as its percent.
    local sizeRow = CreateRow(pages.windows, 1, L["Window Size:"])

    widgets.windowSize = Widgets.CreateDropdown(sizeRow, {}, function(value)
        UI:SetWindowScale(value)
    end, { width = 150 })
    widgets.windowSize:SetPoint("TOPLEFT", CONTROL_X, 0)

    -- Row Size (the owner said build it, 2026-11-21): roomy rows as always,
    -- or the game's tighter ones so more fit. Read once, so it waits for
    -- /reload as Text Size does. See Widgets.RowHeight.
    local rowSizeRow = CreateRow(pages.windows, 1, L["Row Size:"],
        L["Compact fits more rows in each list. Type /reload to see it."])
    widgets.rowSize = Widgets.CreateDropdown(rowSizeRow, {
        { text = L["Roomy"], value = "roomy" },
        { text = L["Compact"], value = "compact" },
    }, function(value)
        Config:Set("rowSize", value)
        widgets.rowSizeReload:SetShown((value == "compact") ~= (Widgets.Compact and Widgets.Compact() or false))
    end, { width = 110 })
    widgets.rowSize:SetPoint("TOPLEFT", CONTROL_X, 0)
    widgets.rowSizeReload = Widgets.CreateButton(rowSizeRow, L["Reload"], function()
        if ReloadUI then ReloadUI() end
    end, { width = 90, height = 20 })
    FitButton(widgets.rowSizeReload)
    ReloadUnder(rowSizeRow, widgets.rowSize, widgets.rowSizeReload)
    widgets.rowSizeReload:Hide()

    local effectsRow = CreateRow(pages.all, 1, L["Effects:"])

    widgets.effects = Widgets.CreateDropdown(effectsRow, {
        { text = L["Full"], value = "full" },
        { text = L["Subtle"], value = "subtle" },
        { text = L["Off"], value = "off" },
    }, function(value)
        Config:Set("windowEffects", value)
        -- Anything moving now lands at once rather than finishing slowly.
        if value == "off" and ns.Motion then ns.Motion:FinishAll() end
    end, { width = 110 })
    widgets.effects:SetPoint("TOPLEFT", CONTROL_X, 0)

    -- A player asked (2026-10-28): one minimap button for every Blackthornes
    -- addon loaded. Ticked unless unticked; see UI/SharedMinimap.lua.
    local combineRow = CreateRow(pages.all, 1, L["Combine Addon Buttons:"])
    widgets.combineButtons = Widgets.CreateCheckbox(combineRow, L["On"], function(checked)
        if ns.SharedMinimap then ns.SharedMinimap.SetCombined(checked) end
    end, true)
    widgets.combineButtons:SetPoint("TOPLEFT", CONTROL_X, -2)

    -- The one Blackthornes window (the owner, 2026-10-30): every addon's tabs
    -- in one window with a rail. Ticked unless unticked; see UI/SharedWindow.lua.
    local oneRow = CreateRow(pages.all, 1, L["One Window:"])
    widgets.oneWindow = Widgets.CreateCheckbox(oneRow, L["On"], function(checked)
        if ns.TSTabs then ns.TSTabs:SetOneWindow(checked) end
    end, true)
    widgets.oneWindow:SetPoint("TOPLEFT", CONTROL_X, -2)

    -- How Tradeskills opens in each place (the owner said build it from a
    -- mockup, 2026-11-26): Full Window, Slim Panel, Round Button or Stay
    -- Closed. Each row shows what the older settings give until a choice
    -- is picked (UI.WindowAt in UI/Main.lua). These took over the Auction
    -- House and Professions ticks of "Open By Itself At:" and the "Small
    -- Craft Queue:" box; their saved keys are still read, never changed.
    local windowChoices = {
        { text = L["Full Window"], value = "full" },
        { text = L["Slim Panel"], value = "slim" },
        { text = L["Round Button"], value = "button" },
        { text = L["Stay Closed"], value = "closed" },
    }
    widgets.windowAt = {}
    for _, place in ipairs({
        { "auction", L["At The Auction House:"], L["What opens when you talk to an auctioneer."] },
        { "profession", L["At A Profession:"], L["What opens with a profession window."] },
        { "mail", L["At The Mailbox:"], L["What opens at a mailbox."] },
    }) do
        local key = UI.WINDOW_AT[place[1]]
        local row = CreateRow(pages.windows, 1, place[2], place[3])
        local dropdown = Widgets.CreateDropdown(row, windowChoices, function(value)
            Config:Set(key, value)
        end, { width = 150 })
        dropdown:SetPoint("TOPLEFT", CONTROL_X, 0)
        widgets.windowAt[place[1]] = dropdown
    end

    -- What comes up by itself (a player's request, 2026-11-05). The
    -- auction house and professions moved to the rows above; vendors stay
    -- here (`openWithShops`, off unless ticked).
    local openRow = CreateRow(pages.windows, 1, L["Open By Itself At:"],
        L["Opens Tradeskills by itself at each place you tick."])
    widgets.openWithShops = Widgets.CreateCheckbox(openRow, L["Vendors"], function(checked)
        Config:Set("openWithShops", checked and true or false)
    end, false)
    widgets.openWithShops:SetPoint("TOPLEFT", CONTROL_X, -2)

    -- A window dragged off the screen comes back (a player's report, 2026-11-11).
    local windowPlacesRow = CreateRow(pages.all, 1, L["Window Locations:"],
        L["Puts every Blackthornes window back where it started. Your settings and data stay the same."])
    local windowPlaces = Widgets.CreateButton(windowPlacesRow, L["Set Default"], function()
        UI:ResetAllWindows()
    end, { width = 60, height = 20 })
    windowPlaces:SetPoint("TOPLEFT", CONTROL_X, -2)
    FitButton(windowPlaces)

    -- Tradeskills Settings: Set Default (the owner said build it,
    -- 2026-11-23): a red Confirm first, then every setting back.
    local restoreRow = CreateRow(pages.all, 1, L["Tradeskills Settings:"],
        L["Puts every Tradeskills setting back to how it started. Your prices, queue, sales and recipes stay. So do your window locations and the choices on this page."])
    local restore
    restore = Widgets.CreateButton(restoreRow, L["Set Default"], function()
        local now = GetTime and GetTime() or 0
        if restore.armedUntil and now <= restore.armedUntil then
            restore.armedUntil = nil
            restore:SetText(L["Set Default"])
            if restore.SetConfirming then restore:SetConfirming(false) end
            UI:ResetSettings()
            return
        end
        restore.armedUntil = now + UI.RESTORE_CONFIRM_SECONDS
        restore:SetText(L["Confirm"])
        if restore.SetConfirming then restore:SetConfirming(true) end
        if C_Timer and C_Timer.After then
            C_Timer.After(UI.RESTORE_CONFIRM_SECONDS, function()
                if restore.armedUntil and (GetTime and GetTime() or 0) >= restore.armedUntil then
                    restore.armedUntil = nil
                    restore:SetText(L["Set Default"])
                    if restore.SetConfirming then restore:SetConfirming(false) end
                end
            end)
        end
    end, { width = 60, height = 20 })
    restore:SetPoint("TOPLEFT", CONTROL_X, -2)
    -- As wide as the longer of its two words.
    restore:SetText(L["Confirm"])
    FitButton(restore)
    restore:SetText(L["Set Default"])
    FitButton(restore)
    widgets.restoreDefaults = restore

    -- My Auctions (the owner said build it, 2026-11-11, from a mockup whose
    -- words he approved): a small window of what you have up. Off unless
    -- ticked. See Logic/AuctionTracker.lua and UI/AuctionTracker.lua.
    CreateSection(pages.windows, 1, L["AUCTION TRACKER"])
    local trackerRow = CreateRow(pages.windows, 1, L["Auction Tracker:"], nil)
    widgets.auctionTracker = Widgets.CreateCheckbox(trackerRow, L["On"], function(checked)
        if ns.AuctionTracker then ns.AuctionTracker:SetOn(checked) else Config:Set("auctionTracker", checked) end
    end, false)
    widgets.auctionTracker:SetPoint("TOPLEFT", CONTROL_X, -2)

    local soldFxRow = CreateRow(pages.windows, 1, L["Sold Effects:"], nil)
    widgets.auctionTrackerEffects = Widgets.CreateDropdown(soldFxRow, {
        { text = L["Full"], value = "full" },
        { text = L["Subtle"], value = "subtle" },
        { text = L["Off"], value = "off" },
    }, function(value)
        Config:Set("auctionTrackerEffects", value)
    end, { width = 110 })
    widgets.auctionTrackerEffects:SetPoint("TOPLEFT", CONTROL_X, 0)

    local trackerClearRow = CreateRow(pages.windows, 1, L["Transparent:"], nil)
    widgets.auctionTrackerSeeThrough = Widgets.CreateDropdown(trackerClearRow, {
        { text = L["Off"], value = 0 },
        { text = L["Some"], value = 1 },
        { text = L["More"], value = 2 },
        { text = L["Most"], value = 3 },
    }, function(value)
        if ns.AuctionTrackerUI then
            ns.AuctionTrackerUI:SetSeeThrough(value)
        else
            Config:Set("auctionTrackerSeeThrough", value)
        end
    end, { width = 110 })
    widgets.auctionTrackerSeeThrough:SetPoint("TOPLEFT", CONTROL_X, 0)

    -- Goblin Gold (asked 2026-10-17): the gold on every character of this
    -- realm and side, on a small bar, with a goal. Off unless ticked; its
    -- sound is under SOUNDS. Logic/GoldGoal.lua, UI/GoldGoal.lua. The
    -- buttons are /bts gold on, off, goal and reset.
    CreateSection(pages.windows, 1, L["GOBLIN GOLD"])
    local goldRow = CreateRow(pages.windows, 1, L["Gold Tracker:"],
        L["A small bar with the gold on all your characters on this realm and side."])

    widgets.goldTracker = Widgets.CreateCheckbox(goldRow, L["On"], function(checked)
        if ns.GoldGoal then ns.GoldGoal:SetOn(checked) end
    end, false)
    widgets.goldTracker:SetPoint("TOPLEFT", CONTROL_X, -2)

    -- Count Gold On (asked 2026-10-21): every character, or only the one
    -- playing, with a goal of its own (Logic/GoldGoal.lua).
    local countRow = CreateRow(pages.windows, 1, L["Count Gold On:"])
    widgets.goldCount = Widgets.CreateDropdown(countRow, {
        { text = L["All Characters"], value = "all" },
        { text = L["This Character"], value = "character" },
    }, function(value)
        if ns.GoldGoal then
            ns.GoldGoal:SetCount(value)
        else
            Config:Set("goldTrackerCount", value)
        end
        -- The goal box shows the goal of what is counted now.
        local goal = ns.GoldGoal and ns.GoldGoal:Goal()
        widgets.goldGoal:SetValue(goal and math.floor(goal / 10000) or nil, true)
    end, { width = 130 })
    widgets.goldCount:SetPoint("TOPLEFT", CONTROL_X, 0)

    local goalRow = CreateRow(pages.windows, 1, L["Gold Goal:"],
        L["Each tenth of the way gets a cheer. Leave it empty for no goal."])

    widgets.goldGoal = Widgets.CreateNumberBox(goalRow, {
        width = 80, min = 1, max = 99999999, allowEmpty = true, placeholder = L["None"],
        onChange = function(value)
            if not ns.GoldGoal then return end
            local goal = ns.GoldGoal:Goal()
            if value and goal and math.floor(goal / 10000) == value then return end
            ns.GoldGoal:SetGoalGold(value)
        end,
    })
    widgets.goldGoal:SetPoint("TOPLEFT", CONTROL_X, 0)
    AddUnit(goalRow, widgets.goldGoal, "g")

    -- Transparent (asked 2026-10-19), as Farmer's panels have it: the
    -- bar's glass thins out and comes back under the mouse. Off by default.
    local goldClearRow = CreateRow(pages.windows, 1, L["Transparent:"])
    widgets.goldSeeThrough = Widgets.CreateDropdown(goldClearRow, {
        { text = L["Off"], value = 0 },
        { text = L["Some"], value = 1 },
        { text = L["More"], value = 2 },
        { text = L["Most"], value = 3 },
    }, function(value)
        if ns.GoldGoalUI then
            ns.GoldGoalUI:SetSeeThrough(value)
        else
            Config:Set("goldTrackerSeeThrough", value)
        end
    end, { width = 110 })
    widgets.goldSeeThrough:SetPoint("TOPLEFT", CONTROL_X, 0)

    CreateSection(pages.windows, 1, L["ARROW"])
    -- Show the way aims the arrow (Logic/WayArrow.lua); with TomTom
    -- installed, its arrow instead while this is ticked (Logic/TomTom.lua,
    -- the same file in every addon with an arrow). On unless unticked.
    local tomtomRow = CreateRow(pages.windows, 1, L["Use TomTom:"],
        L["With TomTom installed, its arrow shows the way instead."])
    widgets.useTomTom = Widgets.CreateCheckbox(tomtomRow, L["On"], function(checked)
        if ns.TomTom then ns.TomTom:SetOn(checked) end
    end, true)
    widgets.useTomTom:SetPoint("TOPLEFT", CONTROL_X, -2)

    -- Show the way to a trainer or vendor far away step by step
    -- (Logic/Travel.lua, the same in every addon). On unless unticked.
    local guideRow = CreateRow(pages.windows, 1, L["Guide Me:"],
        L["When the place is in another zone or across the sea, the arrow leads you there step by step."])
    widgets.arrowRoute = Widgets.CreateCheckbox(guideRow, L["On"], function(checked)
        if ns.Travel then ns.Travel:SetOn(checked) end
    end, true)
    widgets.arrowRoute:SetPoint("TOPLEFT", CONTROL_X, -2)

    -- How big the whole arrow is drawn, 100% unless picked (the owner,
    -- 2026-10-26). The arrow keeps its spot.
    local arrowSizeRow = CreateRow(pages.windows, 1, L["Arrow Size:"])
    widgets.arrowSize = Widgets.CreateDropdown(arrowSizeRow, {
        { text = "50%", value = 50 },
        { text = "75%", value = 75 },
        { text = "100%", value = 100 },
    }, function(value)
        if ns.WayArrowUI then ns.WayArrowUI:SetSize(value) end
    end, { width = 80 })
    widgets.arrowSize:SetPoint("TOPLEFT", CONTROL_X, 0)

    -- Every sound the addon plays, each with its own switch, all on to start
    -- with. The one sound not here is the warning that saved data failed to
    -- load, which is about losing data rather than an effect.
    -- They have their own page since 2026-11-17, with Mute All Sounds on
    -- top: the same switch as on All Addons, so ticking one ticks both.
    CreateSection(pages.sounds, 1, L["SOUNDS"])
    widgets.sounds = {}

    local muteHereRow = CreateRow(pages.sounds, 1, L["Mute All Sounds:"], nil)
    widgets.muteSoundsHere = Widgets.CreateCheckbox(muteHereRow, L["On"], function(checked)
        UI:SetMuteSounds(checked)
    end, false)
    widgets.muteSoundsHere:SetPoint("TOPLEFT", CONTROL_X, -2)

    local function SoundRow(key, label, description, test)
        local row = CreateRow(pages.sounds, 1, label, description)
        local box = Widgets.CreateCheckbox(row, L["On"], function(checked)
            Config:Set(key, checked)
        end, key ~= "queueDoneSound")
        box:SetPoint("TOPLEFT", CONTROL_X, -2)
        widgets.sounds[key] = box

        if test then
            local button = Widgets.CreateButton(row, L["Test"], test,
                { width = 60, height = 20, tooltip = L["Play it now"] })
            button:SetPoint("TOPLEFT", CONTROL_X + 100, -2)
        end

        return box
    end

    -- One box quiets every sound every Blackthornes addon plays, this
    -- warning about saved data included (UI/SharedChoices.lua).
    local muteRow = CreateRow(pages.all, 1, L["Mute All Sounds:"], nil)
    widgets.muteSounds = Widgets.CreateCheckbox(muteRow, L["On"], function(checked)
        UI:SetMuteSounds(checked)
    end, false)
    widgets.muteSounds:SetPoint("TOPLEFT", CONTROL_X, -2)

    -- The sale alarm picks its sound (asked 2026-10-11: players found the
    -- raid warning too much and asked for an old cash register). Off is the
    -- saleAlarm switch; the sound is saleSound. Picking one plays it.
    local saleRow = CreateRow(pages.sounds, 1, L["An Auction Sells:"],
        L["Plays a sound when one of your auctions sells."])

    local function SaleSound()
        if Config:Get("saleAlarm") == false then return "off" end
        return ns.SaleAlarm and ns.SaleAlarm:Sound() or "register"
    end

    widgets.saleAlarm = Widgets.CreateDropdown(saleRow, {
        { text = L["Cash register"], value = "register" },
        { text = L["Coins"], value = "coins" },
        { text = L["Raid warning"], value = "raid" },
        { text = L["Off"], value = "off" },
    }, function(value)
        if value == "off" then
            Config:Set("saleAlarm", false)
            return
        end
        Config:Set("saleAlarm", true)
        Config:Set("saleSound", value)
        if ns.SaleAlarm then ns.SaleAlarm:Play(value) end
    end, { width = 100 })
    widgets.saleAlarm:SetPoint("TOPLEFT", CONTROL_X, 0)

    widgets.saleAlarmPlay = Widgets.CreateButton(saleRow, L["Play"], function()
        local value = SaleSound()
        if ns.SaleAlarm then ns.SaleAlarm:Play(value ~= "off" and value or nil) end
    end, { width = 50, height = 20, tooltip = L["Play the sale sound now"] })
    widgets.saleAlarmPlay:SetPoint("LEFT", widgets.saleAlarm, "RIGHT", 6, 0)
    FitButton(widgets.saleAlarmPlay)
    widgets.saleAlarm.Refresh = function(self) self:SetValue(SaleSound()) end

    widgets.scanSounds = SoundRow("scanSounds", L["A Scan Finishes:"],
        L["A chime when a scan finishes, and another when it finds disenchant or vendor deals."])
    SoundRow("mailReportSound", L["Mail Report:"],
        L["The coins as the mail report counts up, and the fanfare on a new record."])
    SoundRow("craftDoneSound", L["Crafting Finishes:"],
        L["A chime when a run of two or more crafts is done."])
    -- Our own chime at the queue's last craft (2026-11-26), off unless ticked.
    SoundRow("queueDoneSound", L["Queue Done Sound:"],
        L["Plays a short sound when the last craft in the queue is made."],
        function()
            if ns.Crafting then pcall(ns.PlaySoundFile, ns.Crafting.QUEUE_DONE_SOUND, "Master") end
        end)
    SoundRow("bagsFullSound", L["Bags Are Full:"],
        L["A warning the moment your last free bag slot fills."])
    SoundRow("disenchantSound", L["Disenchant Finds:"],
        L["A chime when a disenchant turns up something new or lucky."])
    SoundRow("altCraftSound", L["Cheaper on an Alt:"],
        L["A coin when another of your characters can make a material for less."])
    SoundRow("goalSound", L["Farmer Goal Set:"],
        L["A cheer when Set goal on the Gather tab makes a Farmer goal."])
    SoundRow("goldTrackerSound", L["Goblin Gold:"],
        L["Coins at each tenth of your gold goal, and a cheer when you reach it."],
        function() if ns.GoldGoalUI then ns.GoldGoalUI.Play("step") end end)
    SoundRow("statsCheer", L["Best Week of Sales:"],
        L["A cheer on the Stats tab when an item has its best week of sales yet, once a week."],
        function()
            local kit = type(SOUNDKIT) == "table" and SOUNDKIT.IG_QUEST_LIST_COMPLETE or 878
            pcall(ns.PlaySound or PlaySound, kit, "Master")
        end)

    -- Which columns each list shows (asked 2026-10-09). The same tick list
    -- a right-click on a list's headings opens. See UI/Columns.lua.
    CreateSection(pages.windows, 2, L["COLUMNS"])
    local columnsRow = CreateRow(pages.windows, 2, L["Columns Shown:"],
        L["Pick a list to choose its columns. Right-click a list's headings does the same."])

    local listOptions = {}
    for _, list in ipairs(ns.Columns:Lists()) do
        listOptions[#listOptions + 1] = { text = list.title, value = list.id }
    end
    -- Picking a list opens its tick list under the box.
    widgets.columnsList = Widgets.CreateDropdown(columnsRow, listOptions, function(id)
        if id then ns.Columns:Open(id, widgets.columnsList) end
    end, { width = 160 })
    widgets.columnsList:SetPoint("TOPLEFT", CONTROL_X, 0)
    if listOptions[1] then widgets.columnsList:SetValue(listOptions[1].value) end

    local showAllRow = CreateRow(pages.windows, 2, L["Hidden Columns:"])
    widgets.columnsHidden = Theme.CreateLabel(showAllRow, "small", "muted")
    widgets.columnsHidden:SetPoint("TOPLEFT", CONTROL_X, -4)

    widgets.columnsShowAll = Widgets.CreateButton(showAllRow, L["Show All"], function()
        ns.Columns:ShowAll()
    end, { width = 80, height = 20 })
    widgets.columnsShowAll:SetPoint("TOPLEFT", CONTROL_X + 70, 0)
    FitButton(widgets.columnsShowAll)

    local function PaintHiddenCount()
        local count = ns.Columns:HiddenCount()
        widgets.columnsHidden:SetText(count == 0 and L["None"] or tostring(count))
        widgets.columnsHidden:SetTextColor(Theme.Unpack(count == 0 and "muted" or "accent"))
        widgets.columnsShowAll:SetEnabledState(count > 0)
    end
    widgets.paintHiddenColumns = PaintHiddenCount
    ns.Columns.onAnyChange = PaintHiddenCount
    PaintHiddenCount()

    -- Debug, the client check and the speed check are typed only (/bts
    -- debug, probe, perf; the owner, 2026-10-23): players don't need them.

    -- Sharing (asked 2026-10-07): your characters on another account of
    -- yours, and prices within your guild. Logic/AccountLink.lua and
    -- Logic/GuildPrices.lua; every /bts share command has a control here.
    CreateSection(pages.sharing, 1, L["ACCOUNT LINK"])

    local linkRow = CreateRow(pages.sharing, 1, L["Your Other Account:"],
        L["Type your other account's characters, first and last name, with commas. Type this character's name over there too."])

    widgets.linkNames = Widgets.CreateSearchBox(linkRow, L["Character names"], function(text)
        if ns.AccountLink then ns.AccountLink:SetNames(text) end
    end)
    widgets.linkNames:SetWidth(150)
    widgets.linkNames:SetPoint("TOPLEFT", CONTROL_X, 0)
    if widgets.linkNames.icon then
        widgets.linkNames.icon:SetTexture([[Interface\FriendsFrame\UI-Toast-FriendOnlineIcon]])
        widgets.linkNames.icon:SetSize(14, 14)
    end
    widgets.linkNames.editBox:SetScript("OnEscapePressed", function(self)
        self:SetText(Config:Get("linkNames") or "")
        self:ClearFocus()
    end)
    -- Saved as typed; the hello waits for Enter, so half a name is never
    -- whispered.
    widgets.linkNames.editBox:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        if ns.AccountLink then ns.AccountLink:Check() end
        UI:RefreshActiveTab()
    end)

    widgets.linkShares = {}
    local function ShareRow(key, label, description, offByDefault)
        local row = CreateRow(pages.sharing, 1, label, description)
        local box = Widgets.CreateCheckbox(row, L["On"], function(checked)
            Config:Set(key, checked)
            if key == "linkShareSales" and checked and ns.AccountLink then ns.AccountLink:AskAgain() end
            if key == "linkShareLists" and ns.AccountLink then ns.AccountLink:ListsTicked(checked) end
        end, not offByDefault)
        box:SetPoint("TOPLEFT", CONTROL_X, -2)
        widgets.linkShares[key] = box
    end

    ShareRow("linkShareRecipes", L["Share Recipes:"], L["Your characters' professions and recipes."])
    ShareRow("linkShareBags", L["Share Bags, Bank and Mail:"], L["What your characters carry, bank and have in the mail."])
    ShareRow("linkShareGold", L["Share Gold:"], L["How much gold each of your characters has."])
    ShareRow("linkShareAuctions", L["Share Auctions:"], L["What your characters have listed, so Keep in stock counts it."])
    -- Off unless ticked (the owner, 2026-11-07): see Logic/AccountLink.lua.
    ShareRow("linkShareQueue", L["Share Craft Queue:"],
        L["What your queued crafts still need, so your other account knows what to mail."], true)
    ShareRow("linkShareSales", L["Share Sales:"],
        L["What your other account sold, so your Sales tab shows both."], true)
    ShareRow("linkShareLists", L["Share Shopping Lists:"],
        L["Your shopping lists, so your other account can buy for you."], true)

    local syncButton = Widgets.CreateButton(pages.sharing.content, L["Sync"], function()
        if ns.AccountLink then ns.AccountLink:Check() end
        ns.Print(L["asked your other account for anything new"])
        C_Timer.After(3, function() UI:RefreshActiveTab() end)
    end, { width = 80, height = 22, tooltip = L["Contact your other account now and swap anything that changed"] })
    Place(pages.sharing, 1, syncButton, -10)
    FitButton(syncButton)

    -- The whisper test is typed only (/bts share test; the owner, 2026-10-23).

    -- Forget their characters is a typed command now (the owner,
    -- 2026-10-15): /bts forgetlinked confirm. Settings never deletes data.

    widgets.linkSynced = Theme.CreateLabel(pages.sharing.content, "tiny", "text")
    Place(pages.sharing, 1, widgets.linkSynced, -8)
    widgets.linkSynced:SetWidth(COLUMN_WIDTH)
    widgets.linkSynced:SetWordWrap(true)

    widgets.linkStatus = Theme.CreateLabel(pages.sharing.content, "tiny", "muted")
    Place(pages.sharing, 1, widgets.linkStatus, -8)
    widgets.linkStatus:SetWidth(COLUMN_WIDTH)
    widgets.linkStatus:SetWordWrap(true)

    CreateSection(pages.sharing, 2, L["GUILD"])
    local guildRow = CreateRow(pages.sharing, 2, L["Guild Prices:"],
        L["Swaps scans with guildmates who use Tradeskills. The newest scan is used, yours or theirs."])
    widgets.guildPrices = Widgets.CreateCheckbox(guildRow, L["On"], function(checked)
        Config:Set("guildPrices", checked)
        UI:RefreshActiveTab()
    end, false)
    widgets.guildPrices:SetPoint("TOPLEFT", CONTROL_X, -2)

    CreateRow(pages.sharing, 2, L["Guild Status:"], nil)
    widgets.guildStatus = Theme.CreateLabel(pages.sharing.content, "tiny", "muted")
    Place(pages.sharing, 2, widgets.guildStatus, -2)
    widgets.guildStatus:SetWidth(COLUMN_WIDTH)
    widgets.guildStatus:SetWordWrap(true)

    local craftersRow = CreateRow(pages.sharing, 2, L["Guild Crafters:"],
        L["Shows guildmates online who can make a craft. Your guild sees which recipes you know."])
    widgets.guildCrafters = Widgets.CreateCheckbox(craftersRow, L["On"], function(checked)
        if ns.GuildCrafters then ns.GuildCrafters:SetOn(checked) else Config:Set("guildCrafters", checked) end
        UI:RefreshActiveTab()
    end, false)
    widgets.guildCrafters:SetPoint("TOPLEFT", CONTROL_X, -2)

    CreateSection(pages.sharing, 2, L["YOUR REALM"])
    local realmRow = CreateRow(pages.sharing, 2, L["Realm Prices:"],
        L["Swaps auction prices with players on your realm who use Tradeskills. Only prices are sent, never names. Your own scans always win."])
    widgets.realmPrices = Widgets.CreateCheckbox(realmRow, L["On"], function(checked)
        if ns.RealmPrices then ns.RealmPrices:SetOn(checked) else Config:Set("realmPrices", checked) end
        UI:RefreshActiveTab()
    end, true)
    widgets.realmPrices:SetPoint("TOPLEFT", CONTROL_X, -2)

    widgets.realmStatus = Theme.CreateLabel(pages.sharing.content, "tiny", "muted")
    Place(pages.sharing, 2, widgets.realmStatus, -4)
    widgets.realmStatus:SetWidth(COLUMN_WIDTH)
    widgets.realmStatus:SetWordWrap(true)

    -- Chat Notice (2026-11-18): GuildPrices:NoteHeard, RealmPrices:NoteHeard.
    local noticeRow = CreateRow(pages.sharing, 2, L["Chat Notice:"],
        L["Says in chat when prices come in from your guild or realm."])
    widgets.sharedChatNotice = Widgets.CreateCheckbox(noticeRow, L["On"], function(checked)
        Config:Set("sharedChatNotice", checked)
    end, false)
    widgets.sharedChatNotice:SetPoint("TOPLEFT", CONTROL_X, -2)

    CreateSection(pages.pricing, 2, L["OTHER PRICE ADDONS"])
    local tsmRow = CreateRow(pages.pricing, 2, L["TSM Prices:"],
        L["Uses TradeSkillMaster prices for items you haven't priced."])
    widgets.tsmPrices = Widgets.CreateCheckbox(tsmRow, L["On"], function(checked)
        Config:Set("tsmPrices", checked)
        if ns.TSMPrices then ns.TSMPrices:Forget() end
        GreyPreferTSM(widgets, checked)
        UI:RefreshActiveTab()
    end, false)
    widgets.tsmPrices:SetPoint("TOPLEFT", CONTROL_X, -2)

    widgets.tsmStatus = Theme.CreateLabel(pages.pricing.content, "tiny", "muted")
    Place(pages.pricing, 2, widgets.tsmStatus, -4)
    widgets.tsmStatus:SetWidth(COLUMN_WIDTH)
    widgets.tsmStatus:SetWordWrap(true)

    -- TSM's price over your own once your scan is an hour old (the owner,
    -- 2026-11-12). Off unless ticked, greyed while TSM Prices is off.
    -- `preferTsmPrices`, account wide; never rename it. See Prices:PreferredTSM.
    local preferRow = CreateRow(pages.pricing, 2, L["Prefer TSM Prices:"],
        L["Uses TSM's price once your own scan is more than 1 hour old. Posting prices still come from your scans."])
    widgets.preferTsmPrices = Widgets.CreateCheckbox(preferRow, L["On"], function(checked)
        Config:Set("preferTsmPrices", checked)
        if ns.TSMPrices then ns.TSMPrices:Forget() end
        UI:RefreshActiveTab()
    end, false)
    widgets.preferTsmPrices:SetPoint("TOPLEFT", CONTROL_X, -2)
    widgets.preferTsmRow = preferRow

    -- The TSM price to read (a player asked, the owner said build it,
    -- 2026-11-13): DBRecent unless the player types another, or one of
    -- their own TSM custom prices. `tsmPriceSource`, account wide; never
    -- rename it. Saved on Enter or leaving the box. See TSMPrices:MarketSource.
    local sourceRow = CreateRow(pages.pricing, 2, L["TSM Price Source:"],
        L["The TSM price to use, like DBRecent or DBMarket. You can also type one of your own TSM custom prices."])
    widgets.tsmPriceSource = Widgets.CreateSearchBox(sourceRow, "DBRecent")
    widgets.tsmPriceSource:SetWidth(150)
    widgets.tsmPriceSource:SetPoint("TOPLEFT", CONTROL_X, 0)
    if widgets.tsmPriceSource.icon then
        widgets.tsmPriceSource.icon:Hide()
        widgets.tsmPriceSource.editBox:SetPoint("TOPLEFT", 6, 0)
        widgets.tsmPriceSource.hint:SetPoint("LEFT", 6, 0)
    end
    widgets.tsmSourceRow = sourceRow
    local function SaveSource(editBox)
        local text = (editBox:GetText() or ""):match("^%s*(.-)%s*$")
        local was = Config:Get("tsmPriceSource") or ""
        if text == was then return end
        Config:Set("tsmPriceSource", text ~= "" and text or nil)
        if ns.TSMPrices then ns.TSMPrices:Forget() end
        UI:RefreshActiveTab()
    end
    widgets.tsmPriceSource.editBox:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
    end)
    widgets.tsmPriceSource.editBox:HookScript("OnEditFocusLost", SaveSource)
    widgets.tsmPriceSource.editBox:SetScript("OnEscapePressed", function(self)
        self:SetText(Config:Get("tsmPriceSource") or "")
        self:ClearFocus()
    end)

    widgets.tsmSourceNote = Theme.CreateLabel(pages.pricing.content, "tiny", "warn")
    Place(pages.pricing, 2, widgets.tsmSourceNote, -4)
    widgets.tsmSourceNote:SetWidth(COLUMN_WIDTH)
    widgets.tsmSourceNote:SetWordWrap(true)

    -- A second TSM price for gear that binds when worn (a player asked, the
    -- owner said build it, 2026-11-14). `tsmGearPriceSource`, account wide,
    -- nil or empty reads the TSM Price Source; never rename it. See
    -- TSMPrices:GearSource.
    local gearRow = CreateRow(pages.pricing, 2, L["TSM BoE Price Source:"],
        L["Used for gear that binds when worn. Leave it empty to use your TSM Price Source."])
    widgets.tsmGearPriceSource = Widgets.CreateSearchBox(gearRow, "DBRecent")
    widgets.tsmGearPriceSource:SetWidth(150)
    widgets.tsmGearPriceSource:SetPoint("TOPLEFT", CONTROL_X, 0)
    if widgets.tsmGearPriceSource.icon then
        widgets.tsmGearPriceSource.icon:Hide()
        widgets.tsmGearPriceSource.editBox:SetPoint("TOPLEFT", 6, 0)
        widgets.tsmGearPriceSource.hint:SetPoint("LEFT", 6, 0)
    end
    widgets.tsmGearRow = gearRow
    local function SaveGearSource(editBox)
        local text = (editBox:GetText() or ""):match("^%s*(.-)%s*$")
        local was = Config:Get("tsmGearPriceSource") or ""
        if text == was then return end
        Config:Set("tsmGearPriceSource", text ~= "" and text or nil)
        if ns.TSMPrices then ns.TSMPrices:Forget() end
        UI:RefreshActiveTab()
    end
    widgets.tsmGearPriceSource.editBox:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
    end)
    widgets.tsmGearPriceSource.editBox:HookScript("OnEditFocusLost", SaveGearSource)
    widgets.tsmGearPriceSource.editBox:SetScript("OnEscapePressed", function(self)
        self:SetText(Config:Get("tsmGearPriceSource") or "")
        self:ClearFocus()
    end)

    widgets.tsmGearNote = Theme.CreateLabel(pages.pricing.content, "tiny", "warn")
    Place(pages.pricing, 2, widgets.tsmGearNote, -4)
    widgets.tsmGearNote:SetWidth(COLUMN_WIDTH)
    widgets.tsmGearNote:SetWordWrap(true)

    -- The tooltip's "Sold a day" from TSM (a player asked, the owner said
    -- build it, 2026-11-16). Off unless ticked, greyed while TSM Prices is
    -- off. `tsmSoldPerDay`, account wide; never rename it. See
    -- TSMPrices:SoldPerDay.
    local soldRow = CreateRow(pages.pricing, 2, L["TSM Sold a Day:"],
        L["Takes the Sold a day number on item tooltips from TSM."])
    widgets.tsmSoldPerDay = Widgets.CreateCheckbox(soldRow, L["On"], function(checked)
        Config:Set("tsmSoldPerDay", checked)
        if ns.TSMPrices then ns.TSMPrices:Forget() end
        UI:RefreshActiveTab()
    end, false)
    widgets.tsmSoldPerDay:SetPoint("TOPLEFT", CONTROL_X, -2)
    widgets.tsmSoldRow = soldRow

    local auctionatorRow = CreateRow(pages.pricing, 2, L["Auctionator Prices:"],
        L["Uses Auctionator prices for items nothing else has priced, or when its price is newer than your old one."])
    widgets.auctionatorPrices = Widgets.CreateCheckbox(auctionatorRow, L["On"], function(checked)
        Config:Set("auctionatorPrices", checked)
        if ns.AuctionatorPrices then ns.AuctionatorPrices:Forget() end
        UI:RefreshActiveTab()
    end, false)
    widgets.auctionatorPrices:SetPoint("TOPLEFT", CONTROL_X, -2)

    widgets.auctionatorStatus = Theme.CreateLabel(pages.pricing.content, "tiny", "muted")
    Place(pages.pricing, 2, widgets.auctionatorStatus, -4)
    widgets.auctionatorStatus:SetWidth(COLUMN_WIDTH)
    widgets.auctionatorStatus:SetWordWrap(true)

    -- Which of the two is asked first (the owner, 2026-10-26).
    local orderRow = CreateRow(pages.pricing, 2, L["Price Order:"],
        L["Which one to ask first for items nothing else has priced."])
    local orderOptions = {
        { text = L["TSM First"], value = "tsm" },
        { text = L["Auctionator First"], value = "auctionator" },
    }
    widgets.priceOrder = Widgets.CreateDropdown(orderRow, orderOptions, function(value)
        Config:Set("priceOrder", value)
        if ns.TSMPrices then ns.TSMPrices:Forget() end
        if ns.AuctionatorPrices then ns.AuctionatorPrices:Forget() end
        UI:RefreshActiveTab()
    end, { width = 150 })
    widgets.priceOrder:SetPoint("TOPLEFT", CONTROL_X, 0)

    -- The buttons standing on their own, so the search finds them too.
    Searchable(pages.queue, exportButton, L["Export queue Copy your queue, settings and stock limits as a code"])
    Searchable(pages.queue, importButton, L["Import Load a code"])
    Searchable(pages.queue, exportPrices, L["Export Prices Copy your recent auction prices to use on another computer"])
    Searchable(pages.queue, importPrices, L["Import Prices Load prices from another computer, newer ones only"])
    Searchable(pages.sharing, syncButton, L["Sync now Contact your other account now and swap anything that changed"])

    -- About (UI/About.lua): the note on how the addons are made, then the
    -- version, the Discord and the other Blackthornes addons.
    if ns.About then
        CreateSection(pages.about, 1, L["HOW THESE ADDONS ARE MADE"])
        local note = Place(pages.about, 1, ns.About:Note(pages.about.content, COLUMN_WIDTH))
        Searchable(pages.about, note, note.words)
        CreateSection(pages.about, 2, L["ABOUT"])
        local info = Place(pages.about, 2, ns.About:Info(pages.about.content, COLUMN_WIDTH))
        Searchable(pages.about, info, info.words)
    end

    -- Sending your own disenchants and recipe skills to the addon's maker
    -- (Logic/Contribute.lua, the owner 2026-10-18). Off unless ticked, and
    -- offered only where it can send (North America). Its words wrap under
    -- the box, since they run long.
    if ns.Contribute and ns.Contribute:InRegion() then
        local text = L["Share your data with Blackthornes to improve the Tradeskills AddOn."]
        local holder = CreateFrame("Frame", nil, pages.about.content)
        holder:SetSize(COLUMN_WIDTH, 36)
        local box = Widgets.CreateCheckbox(holder, text, function(checked)
            ns.Contribute:SetOn(checked)
        end, Config:Get("shareData") == true)
        box:SetPoint("TOPLEFT", 0, -2)
        box:SetWidth(COLUMN_WIDTH)
        box.box:ClearAllPoints()
        box.box:SetPoint("TOPLEFT", box, "TOPLEFT", 0, -1)
        box.label:ClearAllPoints()
        box.label:SetPoint("TOPLEFT", box.box, "TOPRIGHT", 6, 1)
        box.label:SetWidth(COLUMN_WIDTH - 24)
        box.label:SetJustifyH("LEFT")
        if box.label.SetWordWrap then box.label:SetWordWrap(true) end
        local ok, tall = pcall(box.label.GetStringHeight, box.label)
        tall = ok and tonumber(tall) or 0
        if tall < 14 then tall = 28 end
        box:SetHeight(math.max(18, tall + 2))
        holder:SetHeight(math.max(18, tall + 2) + 6)
        Place(pages.about, 2, holder, -14)
        Searchable(pages.about, holder, text)
        widgets.shareData = box
    end

    -- Core/SisterNote.lua: one chat line, once, naming the Blackthornes
    -- addons the player does not have. Off here is off in all of them.
    local sistersRow = CreateRow(pages.all, 1, L["Sister Addons:"],
        L["Says once in chat which Blackthornes addons you don't have."])

    widgets.sisters = Widgets.CreateCheckbox(sistersRow, L["On"], function(checked)
        ns.SisterNote:SetOn(checked)
    end, true)
    widgets.sisters:SetPoint("TOPLEFT", CONTROL_X, -2)

    -- UI/WhatsNew.lua: one window after an update for every Blackthornes
    -- addon. Off here is off in all of them, as the sister note is.
    CreateSection(pages.all, 2, L["WHAT'S NEW"])
    local whatsNewRow = CreateRow(pages.all, 2, L["What's New:"])
    widgets.whatsnew = Widgets.CreateButton(whatsNewRow, L["Open"], function()
        ns.WhatsNew:Toggle()
    end, { width = 60, height = 20 })
    FitButton(widgets.whatsnew)
    widgets.whatsnew:SetPoint("TOPLEFT", CONTROL_X, 0)

    -- One drop-down for the two What's New boxes: Off, Show, or Show With
    -- Motion, over the same two saved choices (Off leaves motion as it was).
    local afterRow = CreateRow(pages.all, 2, L["After Updates:"],
        L["Opens What's New the first time you play after an update."])
    widgets.whatsNewAfter = Widgets.CreateDropdown(afterRow, {
        { text = L["Off"], value = "off" },
        { text = L["Show"], value = "show" },
        { text = L["Show With Motion"], value = "motion" },
    }, function(value)
        if not ns.WhatsNew then return end
        ns.WhatsNew:SetOn(value ~= "off")
        if value ~= "off" then ns.WhatsNew:SetMotionOn(value == "motion") end
    end, { width = 170 })
    widgets.whatsNewAfter:SetPoint("TOPLEFT", CONTROL_X, 0)

    -- The Welcome card (2026-10-20): which professions' roads come first on
    -- the Level Up tab's Road to 300. Opens the card again.
    local roadRow = CreateRow(pages.about, 2, L["Road to 300:"])
    local roadOpen = Widgets.CreateButton(roadRow, L["Open"], function()
        if ns.WelcomeUI then ns.WelcomeUI:Show() end
    end, { width = 60, height = 20 })
    roadOpen:SetPoint("TOPLEFT", CONTROL_X, -2)
    FitButton(roadOpen)

    widgets.describe:SetChecked(Config:Get("settingsDescriptions") == true)
    ShowPage(CurrentPage())
end

--------------------------------------------------------------------------------
-- Refresh
--------------------------------------------------------------------------------

--- Write a stored value back into its box, unless the player is typing in
--- it. Bag, mail and auction events redraw this page every few seconds at
--- the auction house, and each redraw put the stored number back over the
--- one being typed, so Enter then saved the old number (or a mix of both).
local function Put(box, value)
    local editBox = box.editBox
    if editBox and editBox.HasFocus and editBox:HasFocus() then return end
    box:SetValue(value, true)
end

local RESTORE_WIDTH = 70

--- One line per ignored craft or item: its name, and Restore at the
--- column's edge. `rows` is the list's own row table, `hint` the label the
--- rows hang under, `onRestore(key)` puts one back.
local function IgnoredRow(rows, hint, index, onRestore, restoreTip, buttonText)
    local row = rows[index]
    if row then return row end

    row = CreateFrame("Frame", nil, hint:GetParent())
    row:SetSize(COLUMN_WIDTH, IGNORED_ROW_HEIGHT)
    row:SetPoint("TOPLEFT", hint, "BOTTOMLEFT", 0,
        -6 - (index - 1) * (IGNORED_ROW_HEIGHT + 2))

    row.label = Theme.CreateLabel(row, "small", "text")
    row.label:SetPoint("LEFT", 0, 0)
    row.label:SetPoint("RIGHT", row, "RIGHT", -RESTORE_WIDTH - 8, 0)
    row.label:SetWordWrap(false)

    row.restore = Widgets.CreateButton(row, buttonText or L["Restore"], function()
        if row.key then onRestore(row.key) end
    end, { width = RESTORE_WIDTH, height = 20, tooltip = restoreTip })
    row.restore:SetPoint("RIGHT", 0, 0)
    FitButton(row.restore)

    rows[index] = row
    return row
end

--- Fill one ignored list; returns the last line drawn, for what follows.
local function FillIgnored(list, rows, hint, empty, onRestore, restoreTip, color, buttonText)
    for index, entry in ipairs(list) do
        local row = IgnoredRow(rows, hint, index, onRestore, restoreTip, buttonText)
        row.key = entry.key
        row.label:SetText(entry.name)
        if color then
            local r, g, b = color(entry.key)
            if r then row.label:SetTextColor(r, g, b)
            else row.label:SetTextColor(Theme.Unpack("text")) end
        end
        row:Show()
    end
    for index = #list + 1, #rows do
        rows[index].key = nil
        rows[index]:Hide()
    end

    empty:ClearAllPoints()
    empty:SetPoint("TOPLEFT", hint, "BOTTOMLEFT", 0, -6)
    empty:SetShown(#list == 0)

    return #list > 0 and rows[#list] or empty
end

--- One never-made sub-craft's line: its name in its item's colour, then
--- what buying the item costs, or that nobody sells it.
local function NeverLine(entry)
    local name = entry.name
    local r, g, b = Util.GetItemQualityColor(entry.outputItemID)
    if r then
        name = ("|cff%02x%02x%02x%s|r"):format(math.floor(r * 255 + 0.5),
            math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5), name)
    end

    if not entry.outputItemID then
        return L.Format("%s |cff857c68· no character knows it|r", name)
    end
    local buy = ns.Cost:GetReagentUnitCost(entry.outputItemID)
    if not buy then
        return L.Format("%s |cff857c68·|r |c%sno price to buy it|r", name, ns.COLORS.warn)
    end
    return L.Format("%s |cff857c68· buy %s each|r", name,
        Util.FormatMoney(buy, { noColor = true, short = true }))
end

--- One always-made sub-craft's line: its name in its item's colour, then
--- that it is always made.
local function AlwaysLine(entry)
    local name = entry.name
    local r, g, b = Util.GetItemQualityColor(entry.outputItemID)
    if r then
        name = ("|cff%02x%02x%02x%s|r"):format(math.floor(r * 255 + 0.5),
            math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5), name)
    end
    return L.Format("%s |cff857c68· always made|r", name)
end

local function RefreshNeverSubCrafts()
    if not widgets.neverHint or not (ns.Cost and ns.Cost.GetNeverSubCrafts) then return end

    local list = {}
    for _, entry in ipairs(ns.Cost:GetNeverSubCrafts()) do
        list[#list + 1] = { key = entry.recipeID, name = NeverLine(entry) }
    end
    -- Those set to Make on the Level Up tab follow (2026-10-13), and Allow
    -- puts them back to the usual too.
    if ns.Cost.GetAlwaysSubCrafts then
        for _, entry in ipairs(ns.Cost:GetAlwaysSubCrafts()) do
            list[#list + 1] = { key = entry.recipeID, name = AlwaysLine(entry) }
        end
    end

    local last = FillIgnored(list, widgets.neverRows, widgets.neverHint, widgets.neverEmpty,
        function(recipeID)
            if ns.Cost.SetSubCraftChoice then ns.Cost:SetSubCraftChoice(recipeID, nil)
            else ns.Cost:SetNeverSubCraft(recipeID, false) end
        end,
        L["Make it as a sub-craft again whenever that is cheaper than buying it"],
        nil, L["Allow"])

    widgets.queueLists.never.count, widgets.queueLists.never.shown = #list, #list
end

--- One profession's line: dark glass by place, its name, its number box
--- (empty for the usual number) and an x while it has one of its own.
local function StockRow(index)
    local row = widgets.stockRows[index]
    if row then return row end

    row = CreateFrame("Frame", nil, widgets.stockHint:GetParent())
    row:SetSize(COLUMN_WIDTH, STOCK_ROW_HEIGHT)
    row:SetPoint("TOPLEFT", widgets.stockHint, "BOTTOMLEFT", 0,
        -6 - (index - 1) * STOCK_ROW_HEIGHT)

    row.band = row:CreateTexture(nil, "BACKGROUND")
    row.band:SetAllPoints(row)
    row.band:SetColorTexture(Theme.Unpack(index % 2 == 1 and "glass" or "glassAlt"))

    row.line = row:CreateTexture(nil, "BORDER")
    row.line:SetPoint("BOTTOMLEFT", 0, 0)
    row.line:SetPoint("BOTTOMRIGHT", 0, 0)
    row.line:SetHeight(1)
    row.line:SetColorTexture(Theme.Unpack("border"))
    row.line:SetAlpha(0.6)

    row.label = Theme.CreateLabel(row, "small", "text")
    row.label:SetPoint("LEFT", 8, 0)
    row.label:SetPoint("RIGHT", row, "LEFT", CONTROL_X - 8, 0)
    row.label:SetWordWrap(false)

    row.box = Widgets.CreateNumberBox(row, {
        width = 56, min = 0, max = 999, allowEmpty = true,
        onChange = function(value)
            if row.profession then ns.Auctions:SetProfessionLimit(row.profession, value) end
        end,
    })
    row.box:SetPoint("LEFT", row, "LEFT", CONTROL_X, 0)

    row.usual = Theme.CreateLabel(row, "tiny", "dim")
    row.usual:SetPoint("LEFT", row.box, "RIGHT", 6, 0)
    row.usual:SetText(L["usual"])

    row.clear = Widgets.CreateButton(row, "x", function()
        if row.profession then ns.Auctions:SetProfessionLimit(row.profession, nil) end
    end, { width = 20, height = 20, tooltip = L["Use Keep in Stock for this profession again"] })
    row.clear:SetPoint("RIGHT", row, "RIGHT", -6, 0)

    widgets.stockRows[index] = row
    return row
end

local function RefreshStockProfessions()
    if not widgets.stockHint or not (ns.Auctions and ns.Auctions.StockProfessions) then return end

    local professions = ns.Auctions:StockProfessions()
    local usual = ns.Config:Get("maxPostedPerItem") or 0
    local usualText = usual > 0 and tostring(usual) or "0"

    for index, profession in ipairs(professions) do
        local row = StockRow(index)
        row.profession = profession
        row.label:SetText(ns.Auctions:ProfessionLabel(profession))

        local own = ns.Auctions:GetProfessionLimit(profession)
        row.box:SetPlaceholder(usualText)
        local typing = row.box.editBox.HasFocus and row.box.editBox:HasFocus()
        if not typing then row.box:SetValue(own, true) end
        row.usual:SetShown(own == nil)
        row.clear:SetShown(own ~= nil)
        row:Show()
    end
    for index = #professions + 1, #widgets.stockRows do
        widgets.stockRows[index].profession = nil
        widgets.stockRows[index]:Hide()
    end

    widgets.stockEmpty:ClearAllPoints()
    widgets.stockEmpty:SetPoint("TOPLEFT", widgets.stockHint, "BOTTOMLEFT", 0, -6)
    widgets.stockEmpty:SetShown(#professions == 0)

    -- Counted by the professions with a number of their own.
    local own = 0
    for _, profession in ipairs(professions) do
        if ns.Auctions:GetProfessionLimit(profession) ~= nil then own = own + 1 end
    end
    widgets.queueLists.stock.count, widgets.queueLists.stock.shown = own, #professions
end

--- The professions the Minimums by Profession list offers: those your
--- characters craft with, and any already given a number of its own.
local function MinimumProfessions()
    local seen, list = {}, {}
    local function Add(name)
        if type(name) == "string" and not seen[name] then
            seen[name] = true
            list[#list + 1] = name
        end
    end
    if ns.Auctions and ns.Auctions.StockProfessions then
        for _, name in ipairs(ns.Auctions:StockProfessions()) do Add(name) end
    end
    for name in pairs(ns.db and ns.db.professionMinimums or {}) do Add(name) end
    -- Buying gear to disenchant (2026-11-22): always offered.
    if ns.Profit and ns.Profit.DISENCHANTING then Add(ns.Profit.DISENCHANTING) end
    table.sort(list)
    return list
end

--- The row's tooltip: what its numbers hide, in the profession's name.
local function ShowMinimumTip(row)
    row.band:SetColorTexture(Theme.Unpack("glassHover"))
    row.edge:Show()
    if not (row.profession and GameTooltip) then return end
    local profit, margin = ns.Profit:MinimumsFor(row.profession)
    GameTooltip:SetOwner(row, "ANCHOR_NONE")
    GameTooltip:ClearAllPoints()
    GameTooltip:SetPoint("TOPLEFT", row, "BOTTOMLEFT", 0, -2)
    GameTooltip:SetText(row.label:GetText() or row.profession, Theme.Unpack("accent"))
    if row.profession == ns.Profit.DISENCHANTING then
        profit, margin = ns.Profit:DisenchantMinimums()
        GameTooltip:AddLine(L.Format("Items on the auction house that make less than %s or %d%% when you buy and disenchant them are hidden on the Disenchanting tab.",
            Util.FormatMoney(profit or 0, { noColor = true, short = true }), margin or 0), 1, 1, 1, true)
        GameTooltip:Show()
        return
    end
    GameTooltip:AddLine(L.Format("%s crafts that make less than %s or %d%% are hidden on the Profit tab, and Queue All skips them.",
        row.label:GetText() or row.profession,
        Util.FormatMoney(profit or 0, { noColor = true, short = true }), margin or 0), 1, 1, 1, true)
    GameTooltip:Show()
end

local function HideMinimumTip(row)
    row.band:SetColorTexture(Theme.Unpack(row.index % 2 == 1 and "glass" or "glassAlt"))
    row.edge:Hide()
    if GameTooltip and GameTooltip:IsOwned(row) then GameTooltip:Hide() end
end

--- One profession's line on the Pricing page: dark glass by place, its
--- name, a profit box in silver with what it means in g, s and c, a margin
--- box, and an x while it has a number of its own.
local function MinimumRow(index)
    local row = widgets.minimumRows[index]
    if row then return row end

    row = CreateFrame("Frame", nil, widgets.minimums)
    row.index = index
    row:SetSize(COLUMN_WIDTH, STOCK_ROW_HEIGHT)
    row:SetPoint("TOPLEFT", widgets.minimumsHeads, "BOTTOMLEFT", 0,
        -2 - (index - 1) * STOCK_ROW_HEIGHT)

    row.band = row:CreateTexture(nil, "BACKGROUND")
    row.band:SetAllPoints(row)
    row.band:SetColorTexture(Theme.Unpack(index % 2 == 1 and "glass" or "glassAlt"))

    row.line = row:CreateTexture(nil, "BORDER")
    row.line:SetPoint("BOTTOMLEFT", 0, 0)
    row.line:SetPoint("BOTTOMRIGHT", 0, 0)
    row.line:SetHeight(1)
    row.line:SetColorTexture(Theme.Unpack("border"))
    row.line:SetAlpha(0.6)

    row.edge = row:CreateTexture(nil, "ARTWORK")
    row.edge:SetPoint("TOPLEFT")
    row.edge:SetPoint("BOTTOMLEFT")
    row.edge:SetWidth(2)
    row.edge:SetColorTexture(Theme.Unpack("accentHi"))
    row.edge:Hide()

    row:EnableMouse(true)
    row:SetScript("OnEnter", ShowMinimumTip)
    row:SetScript("OnLeave", HideMinimumTip)

    row.label = Theme.CreateLabel(row, "small", "text")
    row.label:SetPoint("LEFT", 8, 0)
    row.label:SetPoint("RIGHT", row, "LEFT", MINIMUM_PROFIT_X - 6, 0)
    row.label:SetWordWrap(false)

    -- Typed in silver, as Minimum Profit is.
    row.profit = Widgets.CreateNumberBox(row, {
        width = 56, min = 0, max = 1000000, allowEmpty = true,
        onChange = function(value)
            if row.profession then
                ns.Profit:SetProfessionMinimum(row.profession, "profit", value and value * 100)
            end
        end,
    })
    row.profit:SetPoint("LEFT", row, "LEFT", MINIMUM_PROFIT_X, 0)

    row.preview = Theme.CreateLabel(row, "tiny", "dim")
    row.preview:SetPoint("LEFT", row.profit, "RIGHT", 6, 0)
    row.preview:SetPoint("RIGHT", row, "LEFT", MINIMUM_MARGIN_X - 4, 0)
    row.preview:SetWordWrap(false)

    row.margin = Widgets.CreateNumberBox(row, {
        width = 40, min = 0, max = 100, allowEmpty = true,
        onChange = function(value)
            if row.profession then ns.Profit:SetProfessionMinimum(row.profession, "margin", value) end
        end,
    })
    row.margin:SetPoint("LEFT", row, "LEFT", MINIMUM_MARGIN_X, 0)

    row.percent = Theme.CreateLabel(row, "small", "muted")
    row.percent:SetPoint("LEFT", row.margin, "RIGHT", 4, 0)
    row.percent:SetText("%")

    row.clear = Widgets.CreateButton(row, "x", function()
        if row.profession then ns.Profit:ClearProfessionMinimums(row.profession) end
    end, { width = 20, height = 20, tooltip = L["Use the usual minimums for this profession again"] })
    row.clear:SetPoint("RIGHT", row, "RIGHT", -6, 0)

    widgets.minimumRows[index] = row
    return row
end

local function RefreshProfessionMinimums()
    if not widgets.minimums or not (ns.Profit and ns.Profit.GetProfessionMinimums) then return end

    local professions = MinimumProfessions()
    local usualProfit = ns.Config:Get("minProfit") or 0
    local usualMargin = ns.Config:Get("minMarginPercent") or 0

    for index, profession in ipairs(professions) do
        local row = MinimumRow(index)
        row.profession = profession
        row.label:SetText(ns.Auctions and ns.Auctions.ProfessionLabel
            and ns.Auctions:ProfessionLabel(profession) or profession)

        local profit, margin = ns.Profit:GetProfessionMinimums(profession)
        row.profit:SetPlaceholder(tostring(math.floor(usualProfit / 100)))
        row.margin:SetPlaceholder(tostring(usualMargin))
        if not (row.profit.editBox.HasFocus and row.profit.editBox:HasFocus()) then
            row.profit:SetValue(profit and profit / 100, true)
        end
        if not (row.margin.editBox.HasFocus and row.margin.editBox:HasFocus()) then
            row.margin:SetValue(margin, true)
        end

        if profit then
            row.preview:SetText(Util.FormatMoney(profit, { short = true }))
        elseif margin == nil then
            row.preview:SetText(L["usual"])
        else
            row.preview:SetText("")
        end
        row.clear:SetShown(profit ~= nil or margin ~= nil)
        row:Show()
    end
    for index = #professions + 1, #widgets.minimumRows do
        widgets.minimumRows[index].profession = nil
        widgets.minimumRows[index]:Hide()
    end
    widgets.minimumsEmpty:SetShown(#professions == 0)

    -- The box grows with its rows, so what sits under it moves down.
    local function Tall(text, fallback)
        local height = text.GetStringHeight and text:GetStringHeight()
        return type(height) == "number" and math.ceil(height) or fallback
    end
    local top = 4 + Tall(widgets.minimumsLabel, 14) + 4 + Tall(widgets.minimumsHint, 12) + 6 + 16
    local body = #professions > 0 and (2 + #professions * STOCK_ROW_HEIGHT)
        or (4 + Tall(widgets.minimumsEmpty, 14))
    local height = top + body + 4
    if widgets.minimums:GetHeight() ~= height then
        widgets.minimums:SetHeight(height)
        FitScroll("pricing")
    end
end

local function RefreshChangedStock()
    if not widgets.changedHint or not (ns.SellOut and ns.SellOut.Changed) then return end

    local list = {}
    for _, entry in ipairs(ns.SellOut:Changed()) do
        list[#list + 1] = { key = entry.itemID,
            name = L.Format("%s: %d to %d", entry.name, entry.base, entry.limit) }
    end

    local last = FillIgnored(list, widgets.changedRows, widgets.changedHint,
        widgets.changedEmpty,
        function(itemID) ns.SellOut:Reset(itemID) end,
        L["Put Keep in Stock back to where it started"],
        function(itemID) return Util.GetItemQualityColor(itemID) end,
        L["Reset"])

    widgets.queueLists.changed.count, widgets.queueLists.changed.shown = #list, #list
end

local function RefreshIgnored()
    RefreshStockProfessions()
    RefreshProfessionMinimums()
    RefreshChangedStock()
    RefreshNeverSubCrafts()
    if not widgets.ignoredHint or not ns.Profit.GetIgnored then return end

    local crafts = {}
    for _, entry in ipairs(ns.Profit:GetIgnored()) do
        crafts[#crafts + 1] = { key = entry.recipeID, name = entry.name }
    end

    local last = FillIgnored(crafts, widgets.ignoredRows, widgets.ignoredHint,
        widgets.ignoredEmpty,
        function(recipeID) ns.Profit:SetIgnored(recipeID, false) end,
        L["Show this craft on the Profit tab again"],
        function(recipeID)
            -- In the rarity colour of what the craft makes.
            local recipe = ns.Recipes and ((ns.Recipes.Get and ns.Recipes:Get(recipeID))
                or (ns.Recipes.GetAny and ns.Recipes:GetAny(recipeID)))
            local itemID = recipe and recipe.outputItemID
            if itemID then return Util.GetItemQualityColor(itemID) end
        end)

    widgets.queueLists.ignored.count, widgets.queueLists.ignored.shown = #crafts, #crafts

    if not widgets.ignoredItemsHint or not (ns.Posting and ns.Posting.GetIgnored) then return end

    local items = {}
    for _, entry in ipairs(ns.Posting:GetIgnored()) do
        items[#items + 1] = { key = entry.itemID, name = entry.name }
    end

    -- In the item's rarity colour, as Ready to sell draws it.
    local lastIgnored = FillIgnored(items, widgets.ignoredItemsRows, widgets.ignoredItemsHint,
        widgets.ignoredItemsEmpty,
        function(itemID) ns.Posting:SetIgnored(itemID, false) end,
        L["Offer this item on Ready to sell again"],
        function(itemID) return Util.GetItemQualityColor(itemID) end)

    widgets.queueLists.items.count, widgets.queueLists.items.shown = #items, #items

    if not widgets.keepHereSection or not ns.KeepHere then return end
    local keeps = {}
    for _, entry in ipairs(ns.KeepHere:Items()) do
        keeps[#keeps + 1] = { key = entry.itemID,
            name = L.Format("%s  |cff857c68Keep: %s|r", entry.name, ns.KeepHere.Shown(entry.count)) }
    end
    FillIgnored(keeps, widgets.keepHereRows, widgets.keepHereSection, widgets.keepHereEmpty,
        function(itemID) ns.KeepHere:Set(itemID, 0) end, nil,
        function(itemID) return Util.GetItemQualityColor(itemID) end,
        L["Clear"])
    widgets.queueLists.keep.count, widgets.queueLists.keep.shown = #keeps, #keeps
end

--- The list the box shows: one the search found, the one picked, else the
--- first with something in it, else the first.
local function QueueListShown()
    local lists = widgets.queueLists
    local key = widgets.queueListFound or ns.Config:Get("settingsQueueList")
    if lists[key] then return key end
    for _, group in ipairs(lists) do
        if group.count > 0 then return group.key end
    end
    return lists[1].key
end

--- Show the list picked, size its holder to what it holds so the page
--- scrolls to its foot, and name each list in the box with its count.
ShowQueueList = function()
    local lists = widgets.queueLists
    if not (lists and lists[1]) then return end
    local key = QueueListShown()

    local options = {}
    for _, group in ipairs(lists) do
        options[#options + 1] = { text = L.Format("%s (%d)", group.title, group.count), value = group.key }
    end
    widgets.queueList:SetOptions(options)
    widgets.queueList:SetValue(key)

    for _, group in ipairs(lists) do
        local on = group.key == key
        group.holder:SetShown(on)
        if on then
            local top = 0
            if group.hint.GetStringHeight then
                local height = group.hint:GetStringHeight()
                top = (type(height) == "number" and math.ceil(height) or 14) + 6
            end
            local body
            if group.shown > 0 then
                body = group.shown * group.step
            else
                local height = group.empty.GetStringHeight and group.empty:GetStringHeight()
                body = type(height) == "number" and math.ceil(height) or 14
            end
            group.holder:SetHeight(math.max(1, top + body))
        end
    end
    FitScroll("queue")
end

--- The search found one of the lists: show it, without keeping the pick.
FindQueueList = function(key)
    widgets.queueListFound = key
    ShowQueueList()
end

local function Refresh()
    if not widgets.undercut then return end

    RefreshIgnored()
    ShowQueueList()

    -- One Window may have been ticked or unticked since: All Addons comes
    -- off or back on the switch.
    LayoutSwitch()
    if widgets.shownPage ~= CurrentPage() then ShowPage(CurrentPage()) end

    if widgets.paintHiddenColumns then widgets.paintHiddenColumns() end

    -- Reset to defaults can turn the descriptions back off.
    local describe = ns.Config:Get("settingsDescriptions") == true
    if widgets.describe:GetChecked() ~= describe then
        widgets.describe:SetChecked(describe)
        ShowDescriptions(describe)
    end

    local Config = ns.Config

    -- silent = true (inside Put): writing a stored value back into its own
    -- box must not fire the change handler and write it straight back to
    -- the database.
    Put(widgets.undercut, Config:Get("undercutCopper") or 0)
    Put(widgets.cut, (Config:Get("auctionCut") or 0.05) * 100)
    Put(widgets.minProfit, (Config:Get("minProfit") or 0) / 100)
    Put(widgets.minMargin, Config:Get("minMarginPercent") or 0)
    Put(widgets.budget, Config:Get("scanBudgetMs") or 8)

    local markup = Config:Get("unscannedMarkupPercent")
    Put(widgets.unscannedMarkup, type(markup) == "number" and markup or 50)
    widgets.priceUnscanned:SetChecked(Config:Get("priceUnscannedCrafts") ~= false)

    widgets.minProfitPreview:SetText(
        Util.FormatMoney(Config:Get("minProfit") or 0, { short = true }))

    Put(widgets.maxPosted, Config:Get("maxPostedPerItem") or 0)

    local overrides = 0
    for _ in pairs(ns.db.postLimits or {}) do overrides = overrides + 1 end
    widgets.maxPostedHint:SetText(overrides > 0
        -- Short enough for the 120 pixels beside the box; the longer wording
        -- was cut off with "...".
        and L.Format("%d set per item", overrides)
        or "")

    widgets.restockWhenLow:SetChecked(Config:Get("restockWhenLow") == true)
    widgets.restockOnSale:SetChecked(Config:Get("restockOnSale") ~= false)
    do
        local learn = Config:Get("learnStockFromSales") ~= false
        local raise = Config:Get("raiseStockOnSellOut") == true
        widgets.stockFromSales:SetValue(learn and (raise and "both" or "sales") or (raise and "sellout" or "off"))
    end
    Put(widgets.restockAt, Config:Get("restockAt") or 0)
    widgets.fastSellerBoost:SetChecked(Config:Get("fastSellerBoost") == true)
    local extra = Config:Get("fastSellerExtra")
    Put(widgets.fastSellerExtra, type(extra) == "number" and extra or 2)
    widgets.hideMaxed:SetChecked(Config:Get("hideAtPostLimit") ~= false)
    widgets.onlyMine:SetChecked(Config:Get("queueOnlyMine") == true)
    widgets.allowLoss:SetChecked(Config:Get("allowPostingAtALoss") == true)
    widgets.ignoreDeposit:SetChecked(Config:Get("ignoreDeposit") == true)
    widgets.neverBelowPaid:SetChecked(Config:Get("neverBelowCraftedCost") == true)
    widgets.postAtMinProfit:SetChecked(Config:Get("postAtMinProfit") == true)
    widgets.sisterKeeps:SetChecked(Config:Get("sellHoldsSisterKeeps") == true)
    widgets.altKeeps:SetChecked(Config:Get("sellHoldsAltUpgrades") == true)
    widgets.craftFirst:SetChecked(Config:Get("sellHoldsCraftFirst") == true)
    widgets.queueFromSell:SetChecked(Config:Get("sellQueueFromList") == true)
    GreyQueueFromSell(widgets, Config:Get("sellHoldsCraftFirst") == true)
    widgets.verifyPrice:SetChecked(Config:Get("verifyPriceBeforePosting") ~= false)
    widgets.fastListing:SetChecked(Config:Get("fastListing") ~= false)
    widgets.askBeforeListing:SetChecked(Config:Get("askBeforeListing") == true)
    widgets.postAnyway:SetChecked(Config:Get("postAnyway") == true)
    widgets.mouseWheel:SetChecked(Config:Get("mouseWheelListing") == true)
    widgets.snipeTab:SetChecked(Config:Get("snipeTab") == true)
    widgets.crateShoppingList:SetChecked(Config:Get("crateShoppingList") == true)
    widgets.snipeWheel:SetChecked(Config:Get("snipeWheel") == true)
    widgets.overcutting:SetChecked(Config:Get("overcutting") == true)
    widgets.subCrafts:SetChecked(Config:Get("autoQueueSubCrafts") ~= false)
    widgets.freeSpaceFirst:SetChecked(Config:Get("craftFreesSpaceFirst") ~= false)
    widgets.altCrafts:SetChecked(Config:Get("suggestOtherCharacters") ~= false)
    widgets.followGoals:SetChecked(Config:Get("farmerGoalsFollowQueue") ~= false)
    widgets.shareQueue:SetChecked(Config:Get("queueAltCrafting") == true)
    widgets.queueMail:SetChecked(Config:Get("queueMailPanel") ~= false)
    local spare = Config:Get("bagSpareSlots")
    Put(widgets.bagSpare, type(spare) == "number" and spare or 5)
    widgets.mailBatch:SetChecked(Config:Get("mailBatchTake") == true)
    widgets.deNext:SetChecked(Config:Get("queueDisenchantNext") == true)
    widgets.sellMarked:SetChecked(Config:Get("sellMarkedButton") ~= false)
    widgets.fillBuy:SetChecked(Config:Get("fillBuyQuantity") ~= false)
    widgets.vendorAuction:SetChecked(Config:Get("vendorItemsOnAuction") == true)
    local buyWarn = Config:Get("buyWarnPercent")
    Put(widgets.buyWarn, type(buyWarn) == "number" and buyWarn or 25)
    local disenchanterBox = widgets.disenchanter.editBox
    if not (disenchanterBox.HasFocus and disenchanterBox:HasFocus()) then
        local saved = Config:Get("disenchanterName") or ""
        if widgets.disenchanter:GetText() ~= saved then widgets.disenchanter:SetText(saved) end
    end
    widgets.disenchanterGuess:SetChecked(Config:Get("disenchanterGuess") ~= false)
    ShowPickedDisenchanter()
    widgets.disenchantQuality:SetValue(ns.QueueMail and ns.QueueMail:GetDisenchantQuality()
        or Config:Get("disenchanterQuality") or 2, true)
    widgets.valueOwned:SetChecked(Config:Get("valueOwnedMaterials") ~= false)
    widgets.autoScan:SetChecked(Config:Get("autoScan") ~= false)
    widgets.saleTotal:SetChecked(Config:Get("saleTotal") ~= false)
    widgets.learnFromSearches:SetChecked(Config:Get("learnFromSearches") ~= false)
    widgets.professionValue:SetChecked(Config:Get("showValueInProfessionWindow") == true)
    widgets.craftProfit:SetChecked(Config:Get("craftProfitInProfessionWindow") == true)
    ShowShiftMode(widgets.tooltipValue)
    ShowShiftMode(widgets.tooltipSalesShift)
    ShowShiftMode(widgets.tooltipTrend)
    widgets.upgradeArrows:SetChecked(Config:Get("showUpgradeArrows") ~= false)
    widgets.sisters:SetChecked(ns.SisterNote:IsOn())
    if ns.WhatsNew then
        local after = "show"
        if not ns.WhatsNew:IsOn() then after = "off"
        elseif ns.WhatsNew:IsMotionOn() then after = "motion" end
        widgets.whatsNewAfter:SetValue(after)
    end
    ShowShiftMode(widgets.recipeTooltips)
    ShowShiftMode(widgets.enchantTooltips)
    ShowShiftMode(widgets.disenchantTooltips)
    ShowShiftMode(widgets.crateTooltips)
    ShowShiftMode(widgets.boughtTooltips)
    ShowShiftMode(widgets.usedInTooltips)
    ShowAllLinesMode()
    for place, dropdown in pairs(widgets.windowAt) do
        dropdown:SetValue(UI.WindowAt(place))
    end
    widgets.openWithShops:SetChecked(Config:Get("openWithShops") == true)
    widgets.effects:SetValue(ns.Motion and ns.Motion.Level() or "full")
    local textSize = Config:Get("textSize")
    widgets.textSize:SetValue(Theme.TEXT_STEPS[textSize] and textSize or "normal", true)
    widgets.textReload:SetShown((Theme.TEXT_STEPS[textSize] or 0) ~= Theme.TextStep())
    local Look = ns.BlizzardLook
    if Look then
        widgets.windowStyle:SetValue(Look.Wanted(), true)
        widgets.styleReload:SetShown(Look.Wanted() ~= Look.Style())
    end
    local Shared = ns.SharedChoices
    for kind, entry in pairs(widgets.look or {}) do
        entry.dropdown:SetValue(Shared:Look(kind), true)
        if entry.reload then entry.reload:SetShown(Shared:NeedsReload(kind)) end
    end
    widgets.combineButtons:SetChecked(not ns.SharedMinimap or ns.SharedMinimap.Combined())
    if widgets.rowSize then
        local rowSize = Config:Get("rowSize") == "compact" and "compact" or "roomy"
        widgets.rowSize:SetValue(rowSize, true)
        widgets.rowSizeReload:SetShown((rowSize == "compact") ~= (Widgets.Compact and Widgets.Compact() or false))
    end
    if widgets.oneWindow then
        widgets.oneWindow:SetChecked(ns.SharedWindow and ns.SharedWindow.On() or false)
    end

    -- The three sizes, and the one dragged to when it is none of them.
    local scale = UI.GetWindowScale and UI:GetWindowScale() or 1
    local sizes, shown = {}, nil
    for _, size in ipairs(UI.SIZES or {}) do
        sizes[#sizes + 1] = { text = UI.ScaleText(size.scale), value = size.scale }
        if math.abs(size.scale - scale) < 0.005 then shown = size.scale end
    end
    if not shown then
        sizes[#sizes + 1] = { text = UI.ScaleText(scale), value = scale }
        shown = scale
    end
    widgets.windowSize:SetOptions(sizes)
    widgets.windowSize:SetValue(shown)
    widgets.mailReport:SetChecked(Config:Get("mailReport") ~= false)
    widgets.hideSaleChat:SetChecked(Config:Get("hideSaleChat") == true)
    widgets.goldAnHour:SetChecked(Config:Get("profitGoldAnHour") == true)
    for key, box in pairs(widgets.sounds) do
        -- Queue Done Sound is off unless ticked; the rest on unless unticked.
        if key == "queueDoneSound" then
            box:SetChecked(Config:Get(key) == true)
        else
            box:SetChecked(Config:Get(key) ~= false)
        end
    end
    widgets.muteSounds:SetChecked(ns.Muted and ns.Muted() or false)
    widgets.muteSoundsHere:SetChecked(ns.Muted and ns.Muted() or false)
    widgets.saleAlarm:Refresh()
    widgets.cooldownAlerts:SetChecked(Config:Get("cooldownAlerts") ~= false)
    widgets.tradeRequests:SetChecked(Config:Get("tradeRequests") == true)
    widgets.vendorMapPins:SetChecked(Config:Get("vendorMapPins") == true)
    widgets.recipeWishlist:SetChecked(Config:Get("recipeWishlistOn") == true)
    widgets.arrowRoute:SetChecked(type(ns.db) == "table" and ns.db.arrowRoute ~= false)
    widgets.useTomTom:SetChecked(type(ns.db) ~= "table" or ns.db.useTomTom ~= false)
    widgets.arrowSize:SetValue(ns.WayArrowUI and ns.WayArrowUI.Size() or 100, true)
    widgets.goldTracker:SetChecked(Config:Get("goldTracker") == true)
    widgets.goldCount:SetValue(Config:Get("goldTrackerCount") == "character" and "character" or "all", true)
    local goldGoal = ns.GoldGoal and ns.GoldGoal:Goal()
    widgets.goldSeeThrough:SetValue(ns.GoldGoalUI and ns.GoldGoalUI.SeeThroughLevel()
        or tonumber(Config:Get("goldTrackerSeeThrough")) or 0, true)
    widgets.goldGoal:SetValue(goldGoal and math.floor(goldGoal / 10000) or nil, true)
    widgets.auctionTracker:SetChecked(Config:Get("auctionTracker") == true)
    do
        local fx = Config:Get("auctionTrackerEffects")
        if fx ~= "subtle" and fx ~= "off" then fx = "full" end
        widgets.auctionTrackerEffects:SetValue(fx, true)
    end
    widgets.auctionTrackerSeeThrough:SetValue(ns.AuctionTrackerUI and ns.AuctionTrackerUI.SeeThroughLevel()
        or tonumber(Config:Get("auctionTrackerSeeThrough")) or 0, true)
    widgets.stale:SetValue(Config:Get("staleAfterSeconds") or (48 * 3600), true)

    local linkBox = widgets.linkNames.editBox
    if not (linkBox.HasFocus and linkBox:HasFocus()) then
        local saved = Config:Get("linkNames") or ""
        if widgets.linkNames:GetText() ~= saved then widgets.linkNames:SetText(saved) end
    end
    for key, box in pairs(widgets.linkShares) do
        if key == "linkShareQueue" or key == "linkShareSales" or key == "linkShareLists" then
            box:SetChecked(Config:Get(key) == true)
        else
            box:SetChecked(Config:Get(key) ~= false)
        end
    end
    widgets.linkSynced:SetText(ns.AccountLink and ns.AccountLink:LastSyncedText() or "")
    widgets.linkStatus:SetText(ns.AccountLink and ns.AccountLink:Describe() or "")
    widgets.guildPrices:SetChecked(Config:Get("guildPrices") == true)
    widgets.guildCrafters:SetChecked(Config:Get("guildCrafters") == true)
    if widgets.shareData then widgets.shareData:SetChecked(Config:Get("shareData") == true) end
    widgets.guildStatus:SetText(ns.GuildPrices and ns.GuildPrices:Status() or "")
    widgets.realmPrices:SetChecked(Config:Get("realmPrices") ~= false)
    widgets.sharedChatNotice:SetChecked(Config:Get("sharedChatNotice") == true)
    if widgets.enchantWindow then widgets.enchantWindow:SetChecked(Config:Get("enchantWindow") == true) end
    if widgets.disenchantChat then widgets.disenchantChat:SetChecked(Config:Get("disenchantChat") ~= false) end
    if widgets.salvagerApart then widgets.salvagerApart:SetChecked(Config:Get("salvagerApart") == true) end
    UI:RefreshSettingsPlain()
    if widgets.craftChat then widgets.craftChat:SetChecked(Config:Get("craftChat") ~= false) end
    widgets.realmStatus:SetText(ns.RealmPrices and ns.RealmPrices:Describe() or "")
    widgets.tsmPrices:SetChecked(Config:Get("tsmPrices") ~= false)
    widgets.tsmStatus:SetText(ns.TSMPrices and ns.TSMPrices:Describe() or "")
    widgets.preferTsmPrices:SetChecked(Config:Get("preferTsmPrices") == true)
    widgets.tsmSoldPerDay:SetChecked(Config:Get("tsmSoldPerDay") == true)
    GreyPreferTSM(widgets, Config:Get("tsmPrices") ~= false)
    local sourceBox = widgets.tsmPriceSource.editBox
    if not (sourceBox.HasFocus and sourceBox:HasFocus()) then
        local saved = Config:Get("tsmPriceSource") or ""
        if widgets.tsmPriceSource:GetText() ~= saved then widgets.tsmPriceSource:SetText(saved) end
    end
    local refused = ns.TSMPrices and ns.TSMPrices:SourceRefused()
    widgets.tsmSourceNote:SetText(refused and L["TSM doesn't know that price. Using DBRecent."] or "")
    local gearBox = widgets.tsmGearPriceSource.editBox
    if not (gearBox.HasFocus and gearBox:HasFocus()) then
        local saved = Config:Get("tsmGearPriceSource") or ""
        if widgets.tsmGearPriceSource:GetText() ~= saved then widgets.tsmGearPriceSource:SetText(saved) end
    end
    if widgets.tsmGearPriceSource.hint and ns.TSMPrices then
        widgets.tsmGearPriceSource.hint:SetText(ns.TSMPrices:MarketSource())
    end
    local gearRefused = ns.TSMPrices and ns.TSMPrices:GearSourceRefused()
    widgets.tsmGearNote:SetText(gearRefused and L["TSM doesn't know that price. Using your TSM Price Source."] or "")
    widgets.auctionatorPrices:SetChecked(Config:Get("auctionatorPrices") ~= false)
    widgets.auctionatorStatus:SetText(ns.AuctionatorPrices and ns.AuctionatorPrices:Describe() or "")
    widgets.priceOrder:SetValue(Config:Get("priceOrder") == "auctionator" and "auctionator" or "tsm")

    if widgets.keepHistory and ns.TidyUp then
        local days = ns.TidyUp:Days()
        widgets.keepHistory:SetValue(days)
        widgets.tidyUp:SetEnabledState(days > 0)
        widgets.tidyUp.tooltipText = days == 0 and L["Pick how long to keep price history first."] or nil
        local function ShowSize(bytes)
            widgets.saveSize:SetText(L.Format("%s on this account", ns.TidyUp.FormatSize(bytes)))
        end
        if ns.TidyUp.bytes and time() - (ns.TidyUp.measuredAt or 0) < 600 then
            ShowSize(ns.TidyUp.bytes)
        else
            -- The last size stays up while it is measured again.
            if ns.TidyUp.bytes then ShowSize(ns.TidyUp.bytes) else widgets.saveSize:SetText("...") end
            ns.TidyUp:Measure(ShowSize)
        end
    end

    local lastScan, capped = ns.Prices:GetLastScan()

    widgets.dataSummary:SetText(L.Format("%s items priced on %s",
        Util.Comma(ns.Prices:Count()), Config:GetRealmKey()))

    local lastText = L["never"]
    if lastScan then
        local age = Util.FormatAgeAgo(time() - lastScan)
        lastText = capped and L.Format("%s (stopped at the page limit)", age) or age
    end
    widgets.recipeSummary:SetText(L.Format("%s recipes saved  ·  last scan %s",
        Util.Comma(ns.Recipes:Count()), lastText))

    -- The beta can start a session with nothing. Say so where the data
    -- counts are shown, rather than leaving it looking like the addon
    -- forgot everything on its own.
    local diagnostics = ns.Config:GetLoadDiagnostics()
    widgets.loadWarning:SetTextColor(Theme.Unpack("warn"))
    if ns.Config:IsFirstRun() then
        widgets.loadWarning:SetTextColor(Theme.Unpack("text"))
        widgets.loadWarning:SetText(
            L["This is the first time the addon has run here, so there is no saved data yet."])
    elseif diagnostics.restoredFromCVars then
        widgets.loadWarning:SetText(
            L["The game did not load your saved data at login, so it was recovered from the backup in CVars."])
    elseif diagnostics.globalType ~= "table" and not diagnostics.restored then
        widgets.loadWarning:SetText(
            L["The game did not load your saved data at login, so this session started fresh."])
    else
        widgets.loadWarning:SetText("")
    end

    local auctionAge = ns.Auctions:GetAge()
    widgets.auctionSummary:SetText(auctionAge
        and L.Format("Your auctions last read %s.", Util.FormatAgeAgo(auctionAge))
        or L["Your auctions have never been read. Open the auction house once."])

    local bankAge = ns.Inventory:GetBankAge()
    widgets.bankSummary:SetText(bankAge
        and L.Format("Bank contents last read %s.", Util.FormatAgeAgo(bankAge))
        or L["Bank never read. Visit a bank so material counts include it."])

    -- Last: the warnings above wrap to different heights depending on what
    -- they say, so the page's total height is only known once they are set.
    FitScroll()
end

--------------------------------------------------------------------------------
-- Clear price data and Reset to defaults, typed (the owner, 2026-10-15)
--------------------------------------------------------------------------------

--- Delete every stored price for this realm. The other realms keep their
--- prices, so they keep their scan times and sizes too.
-- Mute All Sounds: kept in this addon's settings and told to every sister.
function UI:SetMuteSounds(on)
    on = on == true
    local at = ns.SharedChoices and ns.SharedChoices:SetMute(on) or nil
    if ns.Config then
        ns.Config:Set("muteSounds", on)
        ns.Config:Set("muteSoundsAt", at)
    end
    if widgets and widgets.muteSounds then widgets.muteSounds:SetChecked(on) end
    if widgets and widgets.muteSoundsHere then widgets.muteSoundsHere:SetChecked(on) end
end

function UI:ClearPriceData()
    local realmKey = ns.Config:GetRealmKey()
    ns.db.prices[realmKey] = {}
    ns.db.lastFullScan = nil
    -- The page-limit stamp too: a big auction house only ever has that one,
    -- and left behind it went on saying "scanned 3h ago" over no prices.
    for _, field in ipairs({ "lastFullScanByRealm", "lastCappedScanByRealm",
                             "sweepSeenByRealm", "sweepRefusedByRealm" }) do
        if ns.db[field] then ns.db[field][realmKey] = nil end
    end
    ns.Print(L["price data cleared for this realm"])
    if UI.RefreshActiveTab then UI:RefreshActiveTab() end
    if UI.UpdateHeader then UI:UpdateHeader() end
end

--- Settings a reset leaves alone (the owner said build Tradeskills Settings:
--- Set Default, 2026-11-23): the ALL ADDONS choices, shared by all five and
--- changed in the others too when changed here; small windows' spots; and
--- the characters and account names picked, which are kept like data.
UI.RESET_KEEPS = {
    textSize = true, windowStyle = true, windowEffects = true,
    goldTrackerX = true, goldTrackerY = true,
    auctionTrackerX = true, auctionTrackerY = true,
    disenchanterName = true, disenchanterGuess = true, linkNames = true,
}

--- Settings with no entry in the defaults (nil is how they start), put back
--- with the rest.
UI.RESET_ALSO = { "tsmPriceSource", "tsmGearPriceSource", "snipeConfirmOver" }

--- Put every setting back to how it started.
function UI:ResetSettings()
    -- Through Config:Set, as every other setting change is, so a session
    -- keeping its settings in the backup store saves these too.
    for key, value in pairs(ns.Config.DEFAULTS.settings) do
        if not UI.RESET_KEEPS[key] then
            if type(value) == "table" then value = CopyTable and CopyTable(value) or value end
            ns.Config:Set(key, value)
        end
    end
    for _, key in ipairs(UI.RESET_ALSO) do
        ns.Config:Set(key, nil)
    end

    -- What each control does on a change, done for the reset too. Only the
    -- values moved before: queued sub-crafts stayed as they were, the
    -- profession window kept its old values, and a folded side panel grew
    -- to full height with nothing in it.
    ns.Queue:RebuildDependencies()
    ns.Queue:Notify()
    if ns.RecipeValue then ns.RecipeValue:Refresh() end
    if ns.Columns then ns.Columns:Reload() end
    if UI.ApplyScale then UI:ApplyScale() end
    for _, panel in ipairs({ ns.PostPanel, ns.CraftPanel }) do
        if panel and panel.frame then
            ns.Collapse.Apply(panel.frame)
            panel:ApplyHeight()
            panel:Refresh()
        end
    end

    ns.Print(L["Every Tradeskills setting is back to how it started."])
    if UI.RefreshActiveTab then UI:RefreshActiveTab() end
end

--- How long the red Confirm waits for the second click, in seconds.
UI.RESTORE_CONFIRM_SECONDS = 4

--- Grey the old disenchant results buttons when there is nothing to move.
function UI:RefreshSettingsPlain()
    local any = ns.DisenchantLog ~= nil and ns.DisenchantLog:PlainCount() > 0
    for _, button in ipairs({ widgets.plainMove, widgets.plainClear }) do
        if button and button.SetEnabledState then button:SetEnabledState(any) end
    end
end

--- True when the typed words are "confirm".
local function Confirmed(args)
    return (args or ""):lower():match("^%s*confirm%s*$") ~= nil
end

--- Turns "Gold an Hour:" on or off and redraws what shows it.
function UI:SetGoldAnHour(on)
    ns.Config:Set("profitGoldAnHour", on == true)
    if widgets.goldAnHour then widgets.goldAnHour:SetChecked(on == true) end
    if UI.RefreshActiveTab then UI:RefreshActiveTab() end
end

ns.RegisterCommand("goldhour", L["show gold an hour for buying the parts or making them (on/off)"], function(args)
    local argument = (args or ""):lower():match("^%s*(.-)%s*$")
    local on
    if argument == "on" then on = true
    elseif argument == "off" then on = false
    else on = ns.Config:Get("profitGoldAnHour") ~= true end
    UI:SetGoldAnHour(on)
    ns.Print(on and L["Gold an hour is on. The Profit tab shows whether buying the parts or making them earns more."]
        or L["Gold an hour is off."])
end)

-- These delete data, so they are typed and never a Settings button.
ns.RegisterCommand("mute", L["turn every Blackthornes sound off or back on (on/off)"], function(args)
    local argument = (args or ""):lower():match("^%s*(.-)%s*$")
    local on
    if argument == "on" then on = true
    elseif argument == "off" then on = false
    else on = not (ns.Muted and ns.Muted()) end
    UI:SetMuteSounds(on)
    ns.Print(on and L["All Blackthornes sounds are off. /bts mute off turns them back on."]
        or L["Blackthornes sounds are back on."])
end)

ns.RegisterCommand("clearprices", L["delete every saved price on this realm (add confirm)"], function(args)
    if not Confirmed(args) then
        ns.Print(L["This deletes every saved price on this realm. Type /bts clearprices confirm to do it."])
        return
    end
    UI:ClearPriceData()
end)

ns.RegisterCommand("reset", L["put every setting back to how it started (add confirm)"], function(args)
    if not Confirmed(args) then
        ns.Print(L["This puts every setting back to how it started. Type /bts reset confirm to do it."])
        return
    end
    UI:ResetSettings()
end)

UI:RegisterTab({
    key = "settings",
    text = L["Settings"],
    order = 12,
    build = Build,
    refresh = Refresh,
    onShow = Refresh,
})

--------------------------------------------------------------------------------
-- Choices every Blackthornes addon shares (UI/SharedChoices.lua): a change
-- made in a sister is written here the way this addon writes it itself.
--------------------------------------------------------------------------------

if ns.SharedChoices then
    ns.SharedChoices:Join("Tradeskills", function(choice, value)
        if not ns.db then return end
        if choice == "textSize" then
            if ns.Theme.TEXT_STEPS and ns.Theme.TEXT_STEPS[value] then ns.Config:Set("textSize", value) end
        elseif choice == "windowStyle" then
            if value == "titanforged" or value == "blizzard" then ns.Config:Set("windowStyle", value) end
        elseif choice == "effects" then
            if value == "full" or value == "subtle" or value == "off" then ns.Config:Set("windowEffects", value) end
        elseif choice == "useTomTom" then
            if ns.TomTom then ns.TomTom:SetOn(value and true or false) end
        elseif choice == "arrowRoute" then
            if ns.Travel then ns.Travel:SetOn(value and true or false) end
        elseif choice == "arrowSize" then
            if ns.WayArrowUI then ns.WayArrowUI:SetSize(value) end
        elseif choice == "muteSounds" then
            ns.Config:Set("muteSounds", value == true)
            ns.Config:Set("muteSoundsAt", ns.SharedChoices.board.mute and ns.SharedChoices.board.mute.at)
        end
        if ns.UI and ns.UI.RefreshActiveTab then pcall(ns.UI.RefreshActiveTab, ns.UI) end
    end, function()
        if not ns.db or not ns.db.settings then return nil end
        return ns.db.settings.muteSounds == true, ns.db.settings.muteSoundsAt
    end)
end

--- Settings on the All Addons page (the one window's gear): the page is
--- saved as the one to show, then the Settings tab opens on it.
function UI:OpenAllAddons()
    ns.Config:Set("settingsPage", "all")
    if self.window and self.window:IsShown() and self.activeTab == "settings" then
        if pages.all then ShowPage("all") end
        return
    end
    self:OpenSettings()
    if pages.all and widgets.bar then ShowPage("all") end
end
