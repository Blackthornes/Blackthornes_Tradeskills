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

-- A player's request (2026-10-07): the one long page grew crowded, so the
-- settings sit on category pages picked along the top, like Recipes /
-- Recipes to learn. Every setting kept its saved name; only its place moved.
local PAGES = {
    { key = "pricing", text = L["PRICING"],
      tip = L["Undercut, the auction house cut, markups and what counts as profit"] },
    { key = "queue", text = L["QUEUE"],
      tip = L["What gets queued, sub-crafts, alts, ignored crafts and items, export and import"] },
    { key = "mail", text = L["MAIL & VENDORS"],
      tip = L["The mailbox, your disenchanter, selling to vendors and the mail report"] },
    { key = "auction", text = L["AUCTION HOUSE"],
      tip = L["Buying, posting and scanning"] },
    { key = "look", text = L["LOOK & SOUND"],
      tip = L["Window size and effects, values on tooltips, and every sound"] },
    { key = "sharing", text = L["SHARING"],
      tip = L["Your other account and guild prices"] },
    { key = "data", text = L["DATA"],
      tip = L["What is saved, clearing old prices, debug output and Reset to defaults"] },
}
local DEFAULT_PAGE = "pricing"

local widgets = {}

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
local function Searchable(page, frame, words)
    searchables[#searchables + 1] = {
        page = page.key,
        frame = frame,
        words = (words or ""):lower(),
        glow = AddFoundGlow(page, frame),
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
local function LayoutSwitch()
    local previous
    for _, part in ipairs(widgets.switch or {}) do
        local width = Theme.TextWidth and Theme.TextWidth(part.label)
        part.button:SetWidth((type(width) == "number" and width or 100) + 4)
        part.button:ClearAllPoints()
        if previous then
            part.button:SetPoint("LEFT", previous, "RIGHT", 22, 0)
        else
            part.button:SetPoint("LEFT", widgets.bar, "LEFT", COLUMN_ONE_X, 0)
        end
        previous = part.button
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

    local counts, firstFound = {}, {}
    for _, entry in ipairs(searchables) do
        local found = widgets.query and entry.words:find(widgets.query, 1, true) ~= nil
        entry.glow:SetShown(found and true or false)
        if found then
            counts[entry.page] = (counts[entry.page] or 0) + 1
            firstFound[entry.page] = firstFound[entry.page] or entry.frame
        end
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
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
            GameTooltip:SetText(definition.tip, 1, 1, 1, 1, true)
            GameTooltip:Show()
        end)
        button:SetScript("OnLeave", function()
            part.hovered = false
            PaintSwitch()
            GameTooltip:Hide()
        end)

        widgets.switch[#widgets.switch + 1] = part
    end
    LayoutSwitch()

    -- The house order for an option bar: search, then tick boxes.
    widgets.describe = Widgets.CreateCheckbox(bar, L["Show descriptions"], function(checked)
        ns.Config:Set("settingsDescriptions", checked)
        ShowDescriptions(checked)
    end, false)
    widgets.describe:SetPoint("RIGHT", bar, "RIGHT", -16, 0)

    widgets.find = Widgets.CreateSearchBox(bar, L["Find a setting"], Search)
    widgets.find:SetWidth(Widgets.SEARCH_WIDTH or 170)
    widgets.find:SetPoint("RIGHT", widgets.describe, "LEFT", -16, 0)
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
        holder:SetPoint("TOPLEFT", 0, -BAR_HEIGHT - 2)
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

    local undercutRow = CreateRow(pages.pricing, 1, L["Undercut by"],
        L["Your posting price is the cheapest rival listing minus this. Set it to 0 to stop undercutting and match the cheapest listing instead. Stackable goods only: gear and bags can only be priced in whole silver, so those match the cheapest rival unless dropping a full silver still leaves the minimum profit below."])

    widgets.undercut = Widgets.CreateNumberBox(undercutRow, {
        width = 70, min = 0, max = 1000000,
        onChange = function(value)
            Config:Set("undercutCopper", value)
            UI:RefreshActiveTab()
            if widgets.undercutSwitch then widgets.undercutSwitch:Update() end
        end,
    })
    widgets.undercut:SetPoint("TOPLEFT", CONTROL_X, 0)
    AddUnit(undercutRow, widgets.undercut, L["copper"])

    -- Undercutting on or off in one click (asked on Discord, 2026-10-09).
    -- Off is the same setting at 0c; on puts back what it was before this
    -- session, or 1c, so no second saved switch can disagree with the number.
    local undercutSwitchRow = CreateRow(pages.pricing, 1, L["Undercutting"],
        L["Off lists at the cheapest rival's own price instead of going under it. It is the same as Undercut by 0c, and turning it back on puts back what you had."])

    local lastUndercut
    widgets.undercutSwitch = Widgets.CreateButton(undercutSwitchRow, L["Turn undercut off"], function()
        local now = Config:Get("undercutCopper") or 1
        if now > 0 then
            lastUndercut = now
            Config:Set("undercutCopper", 0)
        else
            Config:Set("undercutCopper", lastUndercut or 1)
        end
        widgets.undercut:SetValue(Config:Get("undercutCopper"), true)
        widgets.undercutSwitch:Update()
        UI:RefreshActiveTab()
    end, { width = 140, height = 20 })
    widgets.undercutSwitch:SetPoint("TOPLEFT", CONTROL_X, -2)

    function widgets.undercutSwitch:Update()
        local off = (Config:Get("undercutCopper") or 1) <= 0
        self:SetText(off and L.Format("Turn on, %s", Util.FormatMoney(lastUndercut or 1, { noColor = true }))
            or L["Turn undercut off"])
        self.tooltipText = off
            and L["Undercutting is off: you list at the cheapest rival's price. Click to undercut it again."]
            or L["Match the cheapest rival's price instead of going under it (sets Undercut by to 0c)."]
        FitButton(self)
    end
    widgets.undercutSwitch:Update()

    local cutRow = CreateRow(pages.pricing, 1, L["Auction house cut"],
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

    local unscannedRow = CreateRow(pages.pricing, 1, L["Markup with no competition"],
        L["When nobody else is listing one (never scanned, or every listing is yours), the price is your material cost plus this, never below market value. It is shown as an estimate and never saved as a real price."])

    widgets.unscannedMarkup = Widgets.CreateNumberBox(unscannedRow, {
        width = 70, min = 0, max = 1000,
        onChange = function(value)
            Config:Set("unscannedMarkupPercent", value)
            UI:RefreshActiveTab()
        end,
    })
    widgets.unscannedMarkup:SetPoint("TOPLEFT", CONTROL_X, 0)
    AddUnit(unscannedRow, widgets.unscannedMarkup, L["% markup"])

    local unscannedOnRow = CreateRow(pages.pricing, 1, L["Use that markup"],
        L["Off: crafts with no scanned price have no price at all, and your own listings hold at market value."])

    widgets.priceUnscanned = Widgets.CreateCheckbox(unscannedOnRow, L["Enabled"], function(checked)
        Config:Set("priceUnscannedCrafts", checked)
        UI:RefreshActiveTab()
    end, true)
    widgets.priceUnscanned:SetPoint("TOPLEFT", CONTROL_X, -2)

    local ownedRow = CreateRow(pages.pricing, 1, L["Materials you already own"],
        L["On: they still cost market price. Off: they count as free."])

    widgets.valueOwned = Widgets.CreateCheckbox(ownedRow, L["Charge market price"], function(checked)
        Config:Set("valueOwnedMaterials", checked)
        UI:RefreshActiveTab()
    end, true)
    widgets.valueOwned:SetPoint("TOPLEFT", CONTROL_X, -2)

    CreateSection(pages.queue, 1, L["WHAT GETS QUEUED"])
    local postedRow = CreateRow(pages.queue, 1, L["Keep in stock per item"],
        L["The most to hold of each craft. Counts listings, bags, bank, mail and the queue together. 0 = no limit, though Queue All and Restock what sells then keep about two days of what sold for you this week. Equipped gear is not counted."])

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

    local soldRow = CreateRow(pages.queue, 1, L["Restock what sells"],
        L["When one of your auctions sells, queue another of it while there is room under Keep in stock (or about two days of what sold for you this week, when that is 0). Never for a craft that loses money."])

    widgets.restockOnSale = Widgets.CreateCheckbox(soldRow, L["On"], function(checked)
        Config:Set("restockOnSale", checked)
    end, true)
    widgets.restockOnSale:SetPoint("TOPLEFT", CONTROL_X, -2)

    local lowRow = CreateRow(pages.queue, 1, L["Wait until it runs low"],
        L["On: a craft is only suggested again once what you hold drops to the number below, then it is made back up to Keep in stock. Off: it is topped up whenever you hold fewer than Keep in stock."])

    widgets.restockWhenLow = Widgets.CreateCheckbox(lowRow, L["Wait for it"], function(checked)
        Config:Set("restockWhenLow", checked)
        UI:RefreshActiveTab()
    end, true)
    widgets.restockWhenLow:SetPoint("TOPLEFT", CONTROL_X, -2)

    local restockRow = CreateRow(pages.queue, 1, L["Restock when down to"],
        L["Used with Wait until it runs low. 0 = only when you have none left. Queued crafts count as held."])

    widgets.restockAt = Widgets.CreateNumberBox(restockRow, {
        width = 70, min = 0, max = 999,
        onChange = function(value)
            Config:Set("restockAt", value)
            UI:RefreshActiveTab()
        end,
    })
    widgets.restockAt:SetPoint("TOPLEFT", CONTROL_X, 0)

    local fastRow = CreateRow(pages.queue, 1, L["Fast sellers keep more"],
        L["Lets items that sell well for you go past Keep in stock by the number below. Sells well means at least 3 of your own listings have ended and 6 in 10 of them sold (High demand from your Sales tab). The market alone never counts."])

    widgets.fastSellerBoost = Widgets.CreateCheckbox(fastRow, L["Keep more"], function(checked)
        Config:Set("fastSellerBoost", checked)
        UI:RefreshActiveTab()
    end, true)
    widgets.fastSellerBoost:SetPoint("TOPLEFT", CONTROL_X, -2)

    local extraRow = CreateRow(pages.queue, 1, L["Extra for fast sellers"],
        L["How many more a fast seller may be held, on top of Keep in stock."])

    widgets.fastSellerExtra = Widgets.CreateNumberBox(extraRow, {
        width = 70, min = 0, max = 999,
        onChange = function(value)
            Config:Set("fastSellerExtra", value)
            UI:RefreshActiveTab()
        end,
    })
    widgets.fastSellerExtra:SetPoint("TOPLEFT", CONTROL_X, 0)

    local hideMaxedRow = CreateRow(pages.queue, 1, L["Hide maxed crafts"],
        L["Off: they still appear, marked as at their limit."])

    widgets.hideMaxed = Widgets.CreateCheckbox(hideMaxedRow, L["Hide them"], function(checked)
        Config:Set("hideAtPostLimit", checked)
        UI:RefreshActiveTab()
    end, true)
    widgets.hideMaxed:SetPoint("TOPLEFT", CONTROL_X, -2)

    local subCraftRow = CreateRow(pages.queue, 1, L["Queue sub-crafts"],
        L["Also queue materials that are cheaper to make than to buy."])

    widgets.subCrafts = Widgets.CreateCheckbox(subCraftRow, L["Queue them"], function(checked)
        Config:Set("autoQueueSubCrafts", checked)

        -- Sub-crafts are only worked out when the queue changes, so unticking
        -- this left them queued (and ticking it queued none) until then.
        ns.Queue:RebuildDependencies()
        ns.Queue:Notify()
    end, true)
    widgets.subCrafts:SetPoint("TOPLEFT", CONTROL_X, -2)

    local altCraftRow = CreateRow(pages.queue, 1, L["Suggest other characters"],
        L["Point out materials one of your other characters can make for less than buying them."])

    widgets.altCrafts = Widgets.CreateCheckbox(altCraftRow, L["Suggest swapping"], function(checked)
        Config:Set("suggestOtherCharacters", checked)
        UI:RefreshActiveTab()
    end, true)
    widgets.altCrafts:SetPoint("TOPLEFT", CONTROL_X, -2)

    local followRow = CreateRow(pages.queue, 1, L["Goals follow the queue"],
        L["With Blackthornes Farmer: a goal made with Set goal on the Gather tab changes when the queue does, and goes when nothing queued needs it. A goal you change yourself in Farmer is left alone."])

    widgets.followGoals = Widgets.CreateCheckbox(followRow, L["Follow it"], function(checked)
        Config:Set("farmerGoalsFollowQueue", checked)
        if checked then ns.FarmerGoals:Follow() end
    end, true)
    widgets.followGoals:SetPoint("TOPLEFT", CONTROL_X, -2)

    local shareRow = CreateRow(pages.queue, 1, L["Let alts make sub-crafts"],
        L["Off: the shopping list only recommends making it on the other character. On: it goes on that character's queue, marked who it is for, and the mailbox lists what to send."])

    widgets.shareQueue = Widgets.CreateCheckbox(shareRow, L["Hand them over"], function(checked)
        Config:Set("queueAltCrafting", checked)
        -- Who makes each sub-craft is worked out when the queue is rebuilt.
        ns.Queue:RebuildDependencies()
        ns.Queue:Notify()
    end, false)
    widgets.shareQueue:SetPoint("TOPLEFT", CONTROL_X, -2)

    CreateSection(pages.mail, 1, L["AT THE MAILBOX"])
    local queueMailRow = CreateRow(pages.mail, 1, L["Queue mail at the mailbox"],
        L["With alts making sub-crafts, lists what to send them for the queue, with a button that fills in the mail. You press Send."])

    widgets.queueMail = Widgets.CreateCheckbox(queueMailRow, L["Show it"], function(checked)
        Config:Set("queueMailPanel", checked)
        if ns.QueueMailPanel then ns.QueueMailPanel:Refresh() end
    end, true)
    widgets.queueMail:SetPoint("TOPLEFT", CONTROL_X, -2)

    -- Asked 2026-10-04: a character to mail gear to for disenchanting.
    -- Typed rather than picked, so one on another account works too.
    local disenchanterRow = CreateRow(pages.mail, 1, L["Disenchanter"],
        L["At the mailbox, lists gear in your bags to mail this character for disenchanting, with a button that fills in the mail. Never soulbound gear, crafted gear or an upgrade for you. Left empty, your alt with the most Enchanting is picked for you."])
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
    local guessRow = CreateRow(pages.mail, 1, L["Pick one for me"],
        L["While the Disenchanter box is empty, your alt with more Enchanting than the character you're on gets the gear. Untick for nobody."])

    widgets.disenchanterGuess = Widgets.CreateCheckbox(guessRow, L["Pick"], function(checked)
        Config:Set("disenchanterGuess", checked)
        if ns.QueueMailPanel then ns.QueueMailPanel:Refresh() end
        ShowPickedDisenchanter()
    end, true)
    widgets.disenchanterGuess:SetPoint("TOPLEFT", CONTROL_X, -2)

    local disenchantQualityRow = CreateRow(pages.mail, 1, L["Mail gear up to"],
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
    local spareRow = CreateRow(pages.mail, 1, L["Bag slots kept free"],
        L["Left empty by each Take next batch at the mailbox, for what you craft and anything you pick up."])

    widgets.bagSpare = Widgets.CreateNumberBox(spareRow, {
        width = 70, min = 0, max = 50,
        onChange = function(value)
            Config:Set("bagSpareSlots", value)
            if ns.QueueMailPanel then ns.QueueMailPanel:Refresh() end
        end,
    })
    widgets.bagSpare:SetPoint("TOPLEFT", CONTROL_X, 0)

    local mailBatchRow = CreateRow(pages.mail, 1, L["Take queue mail in batches"],
        L["At the mailbox, a Take next batch button takes the queue's materials from your mail, as much as fits in your bags. Never mail asking for payment (COD)."])

    widgets.mailBatch = Widgets.CreateCheckbox(mailBatchRow, L["Show it"], function(checked)
        Config:Set("mailBatchTake", checked)
        if ns.QueueMailPanel then ns.QueueMailPanel:Refresh() end
    end, false)
    widgets.mailBatch:SetPoint("TOPLEFT", CONTROL_X, -2)

    -- Asked 2026-10-07: each queue row says AH, DE or Vendor, and what the
    -- queue made on DE or Vendor can be disenchanted or sold from here.
    local deNextRow = CreateRow(pages.queue, 1, L["Disenchant next on the Queue tab"],
        L["A button that disenchants the next item your queue made on DE, one click each. Never blue or better, anything worn, or anything the queue did not make."])

    widgets.deNext = Widgets.CreateCheckbox(deNextRow, L["Show it"], function(checked)
        Config:Set("queueDisenchantNext", checked)
        UI:RefreshActiveTab()
    end, false)
    widgets.deNext:SetPoint("TOPLEFT", CONTROL_X, -2)

    CreateSection(pages.mail, 2, L["AT VENDORS"])
    local sellMarkedRow = CreateRow(pages.mail, 2, L["Sell marked at vendors"],
        L["A button on the vendor window that sells what your queue made on Vendor, up to 12 a visit so buyback can undo any sale."])

    widgets.sellMarked = Widgets.CreateCheckbox(sellMarkedRow, L["Show it"], function(checked)
        Config:Set("sellMarkedButton", checked)
        if ns.SellMarked then ns.SellMarked:Update() end
    end, true)
    widgets.sellMarked:SetPoint("TOPLEFT", CONTROL_X, -2)

    -- Buttons beside a tick box ran past the column's edge (2026-10-09), so
    -- each has its own row now.
    local sellTestRow = CreateRow(pages.mail, 2, L["Test vendor selling"],
        L["At a vendor: sells your cheapest grey item from the addon, to see whether one click can sell what is marked. Also /bts selltest."])

    local sellTest = Widgets.CreateButton(sellTestRow, L["Test selling"], function()
        if ns.SellMarked then ns.SellMarked:Test() end
    end, { width = 96, height = 20,
        tooltip = L["At a vendor: sells your cheapest grey item from the addon, to see whether the game allows it (/bts selltest)"] })
    sellTest:SetPoint("TOPLEFT", CONTROL_X, -2)
    FitButton(sellTest)

    -- Asked 2026-10-06: the buy window opened at 1 after a Buy list search.
    CreateSection(pages.auction, 1, L["BUYING AND POSTING"])
    local fillBuyRow = CreateRow(pages.auction, 1, L["Fill in how many to buy"],
        L["Search from the Buy list, the Queue tab or the Gather tab, pick the item in the auction house's results, and its quantity box shows how many the queue still needs. You still click Buy Now."])

    widgets.fillBuy = Widgets.CreateCheckbox(fillBuyRow, L["Enabled"], function(checked)
        Config:Set("fillBuyQuantity", checked)
    end, true)
    widgets.fillBuy:SetPoint("TOPLEFT", CONTROL_X, -2)

    -- Asked 2026-10-11: the real cost of many could run far past the estimate.
    local buyWarnRow = CreateRow(pages.auction, 1, L["Warn when buying costs more"],
        L["On the auction house's buy window, a line under Buy Now when that many of a queue material costs this many percent more than the shopping list said, with both amounts and the difference. 0 turns it off."])

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
    local lossRow = CreateRow(pages.pricing, 1, L["Recommend selling at a loss"],
        L["Off: the Post tab shows them in red but will not list them."])

    widgets.allowLoss = Widgets.CreateCheckbox(lossRow, L["Recommend anyway"], function(checked)
        Config:Set("allowPostingAtALoss", checked)
        UI:RefreshActiveTab()
    end, false)
    widgets.allowLoss:SetPoint("TOPLEFT", CONTROL_X, -2)

    -- Asked by a player on 2026-10-05: the guard above compares with what the
    -- materials cost today; this one with what the last craft actually cost.
    local paidRow = CreateRow(pages.pricing, 1, L["Never below what I paid"],
        L["Won't list a crafted item for less than its last craft cost, after the auction house's cut."])

    widgets.neverBelowPaid = Widgets.CreateCheckbox(paidRow, L["Enabled"], function(checked)
        Config:Set("neverBelowCraftedCost", checked)
        UI:RefreshActiveTab()
        if ns.PostPanel and ns.PostPanel.Refresh then ns.PostPanel:Refresh() end
    end, false)
    widgets.neverBelowPaid:SetPoint("TOPLEFT", CONTROL_X, -2)

    -- No "Confirm before each listing" switch: the confirmation's Yes is the
    -- click that lists. Posting needs a real click, and after the price
    -- check (an auction house search, answered later) there is no other.
    -- The switch never did anything; its saved value is left where it is.
    local verifyRow = CreateRow(pages.auction, 1, L["Check price before listing"],
        L["Searches the auction house for that one item first, so you undercut the price as it is now."])

    widgets.verifyPrice = Widgets.CreateCheckbox(verifyRow, L["Check first"], function(checked)
        Config:Set("verifyPriceBeforePosting", checked)
    end, true)
    widgets.verifyPrice:SetPoint("TOPLEFT", CONTROL_X, -2)

    -- The sale alarm and the scan chime moved down to SOUNDS, with a switch
    -- for every other sound (2026-10-02).
    CreateSection(pages.mail, 2, L["AFTER A SALE"])
    local mailReportRow = CreateRow(pages.mail, 2, L["Report after collecting mail"],
        L["Counts up what you collected at the mailbox and shows it when you walk away, with your best sale."])

    widgets.mailReport = Widgets.CreateCheckbox(mailReportRow, L["Enabled"], function(checked)
        Config:Set("mailReport", checked)
    end, true)
    widgets.mailReport:SetPoint("TOPLEFT", CONTROL_X, -2)

    local mailPreviewRow = CreateRow(pages.mail, 2, L["Sample mail report"],
        L["Shows the report with made-up mail, so you can see what it looks like."])

    local mailReportTest = Widgets.CreateButton(mailPreviewRow, L["Preview"], function()
        if ns.MailReport and ns.MailHaul then ns.MailReport:Show(ns.MailHaul:Sample()) end
    end, { width = 70, height = 20, tooltip = L["Show a sample report"] })
    mailReportTest:SetPoint("TOPLEFT", CONTROL_X, -2)
    FitButton(mailReportTest)

    -- Requested by a player whose chat filled with sale lines: the Sales tab
    -- keeps every sale, so the chat copy can go.
    local saleChatRow = CreateRow(pages.mail, 2, L["Hide sale messages in chat"],
        L["Keeps \"A buyer has been found\" out of chat. Every sale is still on the Sales tab."])

    widgets.hideSaleChat = Widgets.CreateCheckbox(saleChatRow, L["Hide them"], function(checked)
        Config:Set("hideSaleChat", checked)
        if checked and ns.SaleAlarm then ns.SaleAlarm:InstallChatHider() end
    end, false)
    widgets.hideSaleChat:SetPoint("TOPLEFT", CONTROL_X, -2)

    CreateSection(pages.pricing, 2, L["WHAT COUNTS AS PROFIT"])

    local profitRow = CreateRow(pages.pricing, 2, L["Minimum profit"],
        L["Crafts that make less than this are hidden from the Profit tab. For gear and bags, which are priced in whole silver, it also decides whether to undercut by a silver or just match the cheapest rival."])

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

    local marginRow = CreateRow(pages.pricing, 2, L["Minimum margin"],
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

    CreateSection(pages.pricing, 2, L["PRICE AGE"])
    local staleRow = CreateRow(pages.pricing, 2, L["Prices go stale after"],
        L["Older prices are greyed out, but still used."])

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

    -- Crafts never made to go into another craft (2026-10-07),
    -- marked from the Level Up tab or the x on a queued sub-craft. Laid out
    -- as Ignored crafts below is, rows made in Refresh.
    widgets.ignoredParent = pages.queue.content
    local never = CreateSection(pages.queue, 2, L["NEVER MADE AS SUB-CRAFTS"])
    widgets.neverSection = never
    Searchable(pages.queue, never, L["Never made as sub-crafts bought instead intermediates allow light leather"])

    local neverHint = Theme.CreateLabel(pages.queue.content, "tiny", "muted")
    neverHint:SetPoint("TOPLEFT", never, "BOTTOMLEFT", 0, ROW_GAP)
    neverHint:SetWidth(COLUMN_WIDTH)
    neverHint:SetWordWrap(true)
    neverHint:SetText(L["Bought instead of made whenever another craft needs them, in costs, the queue and the shopping list, on every character. They can still be queued on their own. Allow makes one again when that is cheaper."])
    widgets.neverHint = neverHint

    widgets.neverEmpty = Theme.CreateLabel(pages.queue.content, "small", "dim")
    widgets.neverEmpty:SetWidth(COLUMN_WIDTH)
    widgets.neverEmpty:SetWordWrap(true)
    widgets.neverEmpty:SetText(L["None. Click Make beside a craft on the Level Up tab (tick Sub-crafts only), or the x on a sub-craft in the queue."])
    widgets.neverRows = {}

    local neverEnd = CreateFrame("Frame", nil, pages.queue.content)
    neverEnd:SetSize(COLUMN_WIDTH, 1)
    neverEnd:SetPoint("TOPLEFT", widgets.neverEmpty, "BOTTOMLEFT", 0, 0)
    widgets.neverEnd = neverEnd
    pages.queue.last[2] = neverEnd

    -- Crafts taken off the Profit tab with its Ignore button. The rows are
    -- made in Refresh, one per craft, since the list grows and shrinks.
    local ignored = CreateSection(pages.queue, 2, L["IGNORED CRAFTS"])
    widgets.ignoredSection = ignored
    Searchable(pages.queue, ignored, L["Ignored crafts Restore puts one back on the Profit tab"])

    local ignoredHint = Theme.CreateLabel(pages.queue.content, "tiny", "muted")
    ignoredHint:SetPoint("TOPLEFT", ignored, "BOTTOMLEFT", 0, ROW_GAP)
    ignoredHint:SetWidth(COLUMN_WIDTH)
    ignoredHint:SetWordWrap(true)
    ignoredHint:SetText(L["Never shown on the Profit tab, on any character. Restore puts one back."])
    widgets.ignoredHint = ignoredHint

    widgets.ignoredEmpty = Theme.CreateLabel(pages.queue.content, "small", "dim")
    widgets.ignoredEmpty:SetWidth(COLUMN_WIDTH)
    widgets.ignoredEmpty:SetWordWrap(true)
    widgets.ignoredEmpty:SetText(L["None. Pick a craft on the Profit tab and click Ignore."])
    widgets.ignoredRows = {}

    -- Where the ignored crafts end, moved under the last of them in Refresh,
    -- so the section below follows the list as it grows and shrinks.
    local ignoredEnd = CreateFrame("Frame", nil, pages.queue.content)
    ignoredEnd:SetSize(COLUMN_WIDTH, 1)
    ignoredEnd:SetPoint("TOPLEFT", widgets.ignoredEmpty, "BOTTOMLEFT", 0, 0)
    widgets.ignoredEnd = ignoredEnd

    -- Items taken off Ready to sell at the auction house with the x on
    -- their row (2026-10-04). Laid out as Ignored crafts is.
    pages.queue.last[2] = ignoredEnd
    local ignoredItems = CreateSection(pages.queue, 2, L["IGNORED ITEMS"])
    widgets.ignoredItemsSection = ignoredItems
    Searchable(pages.queue, ignoredItems, L["Ignored items Restore puts one back on Ready to sell"])

    local ignoredItemsHint = Theme.CreateLabel(pages.queue.content, "tiny", "muted")
    ignoredItemsHint:SetPoint("TOPLEFT", ignoredItems, "BOTTOMLEFT", 0, ROW_GAP)
    ignoredItemsHint:SetWidth(COLUMN_WIDTH)
    ignoredItemsHint:SetWordWrap(true)
    ignoredItemsHint:SetText(L["Never offered for sale on Ready to sell or the Post tab, on any character. Restore puts one back."])
    widgets.ignoredItemsHint = ignoredItemsHint

    widgets.ignoredItemsEmpty = Theme.CreateLabel(pages.queue.content, "small", "dim")
    widgets.ignoredItemsEmpty:SetWidth(COLUMN_WIDTH)
    widgets.ignoredItemsEmpty:SetWordWrap(true)
    widgets.ignoredItemsEmpty:SetText(L["None. Click the x on an item in Ready to sell at the auction house."])
    widgets.ignoredItemsRows = {}

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

    local pruneButton = Widgets.CreateButton(pages.data.content, L["Remove old prices"], function()
        local removed = ns.Prices:Prune()
        ns.Print(L.Format("removed %d old price(s)", removed))
        UI:RefreshActiveTab()
    end, { width = 150, height = 22, tooltip = L["Drop items not seen on the auction house for 21 days"] })
    pages.data.last[1] = widgets.loadWarning
    Place(pages.data, 1, pruneButton, -18)
    FitButton(pruneButton)

    -- Destructive, so it arms first rather than wiping a long price history on
    -- a misclick.
    widgets.clearButton = Widgets.CreateButton(pages.data.content, L["Clear price data"], function()
        local button = widgets.clearButton

        if button.armed then
            -- This realm only: the other realms keep their prices, so they
            -- keep their scan times and sizes too.
            local realmKey = ns.Config:GetRealmKey()
            ns.db.prices[realmKey] = {}
            ns.db.lastFullScan = nil
            -- The page-limit stamp too: a big auction house only ever has
            -- that one, and left behind it went on saying "scanned 3h ago"
            -- over no prices at all.
            for _, field in ipairs({ "lastFullScanByRealm", "lastCappedScanByRealm",
                                     "sweepSeenByRealm", "sweepRefusedByRealm" }) do
                if ns.db[field] then ns.db[field][realmKey] = nil end
            end

            button.armed = false
            button:SetText(L["Clear price data"])
            button:SetConfirming(false)

            ns.Print(L["price data cleared for this realm"])
            UI:RefreshActiveTab()
            UI:UpdateHeader()
            return
        end

        button.armed = true
        button:SetText(L["Really clear?"])
        -- Red while armed, like the craft pane's Clear queue.
        button:SetConfirming(true)

        C_Timer.After(4, function()
            if button.armed then
                button.armed = false
                button:SetText(L["Clear price data"])
                button:SetConfirming(false)
            end
        end)
    end, { width = 150, height = 22, tooltip = L["Delete every stored price for this realm"] })
    widgets.clearButton:SetPoint("LEFT", pruneButton, "RIGHT", 8, 0)
    FitButton(widgets.clearButton)

    CreateSection(pages.queue, 1, L["EXPORT AND IMPORT"])
    local exportButton = Widgets.CreateButton(pages.queue.content, L["Export queue"], function()
        UI:ShowTransferDialog("export")
    end, { width = 150, height = 22,
           tooltip = L["Copy your queue, settings and stock limits to a code"] })
    Place(pages.queue, 1, exportButton, -8)
    FitButton(exportButton)

    local importButton = Widgets.CreateButton(pages.queue.content, L["Import"], function()
        UI:ShowTransferDialog("import")
    end, { width = 150, height = 22,
           tooltip = L["Restore from a code"] })
    importButton:SetPoint("LEFT", exportButton, "RIGHT", 8, 0)

    CreateSection(pages.auction, 2, L["SCANNING"])

    local budgetRow = CreateRow(pages.auction, 2, L["Scan speed"],
        L["How long each screen refresh spends reading auction data. Higher scans faster but can make the game stutter."])

    widgets.budget = Widgets.CreateNumberBox(budgetRow, {
        width = 60, min = 2, max = 16,
        onChange = function(value) Config:Set("scanBudgetMs", value) end,
    })
    widgets.budget:SetPoint("TOPLEFT", CONTROL_X, 0)
    AddUnit(budgetRow, widgets.budget, L["ms"])

    local autoScanRow = CreateRow(pages.auction, 2, L["Scan automatically"],
        L["Scans again when the auction house opens and prices are missing or out of date."])

    widgets.autoScan = Widgets.CreateCheckbox(autoScanRow, L["Enabled"], function(checked)
        Config:Set("autoScan", checked)
    end, true)
    widgets.autoScan:SetPoint("TOPLEFT", CONTROL_X, -2)

    local learnRow = CreateRow(pages.auction, 2, L["Learn from searches"],
        L["Also takes prices from searches you run in the auction house yourself."])

    widgets.learnFromSearches = Widgets.CreateCheckbox(learnRow, L["Enabled"], function(checked)
        Config:Set("learnFromSearches", checked)
    end, true)
    widgets.learnFromSearches:SetPoint("TOPLEFT", CONTROL_X, -2)

    CreateSection(pages.look, 1, L["SHOWN IN THE GAME"])
    local professionValueRow = CreateRow(pages.look, 1, L["Value in profession window"],
        L["Shows what one of each recipe sells for beside its name in Blizzard's own window."])

    widgets.professionValue = Widgets.CreateCheckbox(professionValueRow, L["Enabled"], function(checked)
        Config:Set("showValueInProfessionWindow", checked)
        if ns.RecipeValue then ns.RecipeValue:Refresh() end
    end, true)
    widgets.professionValue:SetPoint("TOPLEFT", CONTROL_X, -2)

    local tooltipValueRow = CreateRow(pages.look, 1, L["Value on item tooltips"],
        L["Adds what an item sells for to its tooltip, wherever the game shows one."])

    widgets.tooltipValue = Widgets.CreateCheckbox(tooltipValueRow, L["Enabled"], function(checked)
        Config:Set("showValueOnItemTooltips", checked)
    end, true)
    widgets.tooltipValue:SetPoint("TOPLEFT", CONTROL_X, -2)

    -- Asked 2026-10-05: is a recipe worth buying, at a glance. The button
    -- is /bts recipes.
    local recipeTipRow = CreateRow(pages.look, 1, L["Recipe value on tooltips"],
        L["On a Pattern, Plans, Formula or Recipe: what it teaches, the cost to make, what it sells and disenchants for, and how many crafts pay it back."])

    widgets.recipeTooltips = Widgets.CreateCheckbox(recipeTipRow, L["Enabled"], function(checked)
        Config:Set("showRecipeValueOnTooltips", checked)
    end, true)
    widgets.recipeTooltips:SetPoint("TOPLEFT", CONTROL_X, -2)

    -- Its own row (a player's report, 2026-10-09): beside the tick box it
    -- started 340 pixels in and ran past the column into the next one.
    local recipeListRow = CreateRow(pages.look, 1, L["Recipes to learn"],
        L["Every recipe of your professions you have not learned, with what each is worth. Also /bts recipes."])

    local recipeList = Widgets.CreateButton(recipeListRow, L["Show list"], function()
        if ns.ProfitTab and ns.ProfitTab.ShowRecipesToLearn then ns.ProfitTab.ShowRecipesToLearn() end
    end, { width = 110, height = 20,
           tooltip = L["Every recipe of your professions you have not learned, with what each is worth"] })
    recipeList:SetPoint("TOPLEFT", CONTROL_X, -2)
    FitButton(recipeList)

    local upgradeRow = CreateRow(pages.look, 1, L["Upgrade arrows on gear"],
        L["A green arrow on the icon of gear that is an upgrade for you. Needs Blackthornes Equipment."])

    widgets.upgradeArrows = Widgets.CreateCheckbox(upgradeRow, L["Enabled"], function(checked)
        Config:Set("showUpgradeArrows", checked)
        if ns.Upgrades then ns.Upgrades:Forget() end
        UI:RefreshActiveTab()
    end, true)
    widgets.upgradeArrows:SetPoint("TOPLEFT", CONTROL_X, -2)

    -- Core/SisterNote.lua: one chat line, once, naming the Blackthornes
    -- addons the player does not have. Off here is off in all of them.
    local sistersRow = CreateRow(pages.look, 1, L["Sister addons"],
        L["Once, a few seconds after login, says in chat which Blackthornes addons you don't have and what each adds. Turning it off here turns it off in all of them. Also /bts sisters."])

    widgets.sisters = Widgets.CreateCheckbox(sistersRow, L["Mention them"], function(checked)
        ns.SisterNote:SetOn(checked)
    end, true)
    widgets.sisters:SetPoint("TOPLEFT", CONTROL_X, -2)

    local shopsRow = CreateRow(pages.auction, 1, L["Open with the auction house"],
        L["Opens this window when the auction house or a vendor opens, and closes it with them."])

    widgets.openWithShops = Widgets.CreateCheckbox(shopsRow, L["Enabled"], function(checked)
        Config:Set("openWithShops", checked)
    end, false)
    widgets.openWithShops:SetPoint("TOPLEFT", CONTROL_X, -2)

    -- A player's request (2026-10-07): the window was too big on a 4K
    -- screen. The grip below its bottom right corner does the same, to any
    -- size; one dragged to shows in the box as its percent.
    CreateSection(pages.look, 1, L["THIS WINDOW"])
    local sizeRow = CreateRow(pages.look, 1, L["Window size"],
        L["How big this window is drawn. Drag the gold corner below its bottom right for any size, or right-click it for Normal. Also /bts size."])

    widgets.windowSize = Widgets.CreateDropdown(sizeRow, {}, function(value)
        UI:SetWindowScale(value)
    end, { width = 150 })
    widgets.windowSize:SetPoint("TOPLEFT", CONTROL_X, 0)

    -- Asked 2026-10-07 ("I'm getting old"): bigger letters in the same
    -- window. Every size is read as text is drawn, so it waits for /reload.
    local textRow = CreateRow(pages.look, 1, L["Text size"],
        L["Large and Larger add a point or two to all of this addon's text, in a window the same size. Works with Window size. Takes effect after /reload."])

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
    widgets.textReload = Widgets.CreateButton(textRow, L["Reload now"], function()
        if ReloadUI then ReloadUI() end
    end, { width = 90, height = 20, tooltip = L["Reload the interface so the new text size shows (/reload)"] })
    FitButton(widgets.textReload)
    ReloadUnder(textRow, widgets.textSize, widgets.textReload)
    widgets.textReload:Hide()

    -- Asked 2026-10-10: the game's own look for players who would rather
    -- the windows matched the rest of their screen. Read at login, so it
    -- waits for /reload as Text size does. See UI/BlizzardLook.lua.
    local styleRow = CreateRow(pages.look, 1, L["Window style"],
        L["Titanforged is the house look, with a gold rim and glowing edges. Blizzard uses the game's own frames, red buttons, tabs and tick boxes. Takes effect after /reload."])

    widgets.windowStyle = Widgets.CreateDropdown(styleRow, {
        { text = "Titanforged", value = "titanforged" },
        { text = "Blizzard", value = "blizzard" },
    }, function(value)
        Config:Set("windowStyle", value)
        local Look = ns.BlizzardLook
        widgets.styleReload:SetShown(Look and Look.Style() ~= value or false)
    end, { width = 110 })
    widgets.windowStyle:SetPoint("TOPLEFT", CONTROL_X, 0)

    widgets.styleReload = Widgets.CreateButton(styleRow, L["Reload now"], function()
        if ReloadUI then ReloadUI() end
    end, { width = 90, height = 20, tooltip = L["Reload the interface so the new window style shows (/reload)"] })
    FitButton(widgets.styleReload)
    ReloadUnder(styleRow, widgets.windowStyle, widgets.styleReload)
    widgets.styleReload:Hide()

    local effectsRow = CreateRow(pages.look, 1, L["Window effects"],
        L["Full: windows fade up and glow as they open, and buttons ease into their colours. Subtle: shorter, and nothing rises. Off: no movement at all."])

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

    -- Which columns each list shows (asked 2026-10-09). The same tick list
    -- a right-click on a list's headings opens. See UI/Columns.lua.
    CreateSection(pages.look, 1, L["COLUMNS"])
    local columnsRow = CreateRow(pages.look, 1, L["Columns shown"],
        L["Pick a list to tick the columns it shows. Right-clicking a list's column headings does the same. The name column always shows."])

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

    local showAllRow = CreateRow(pages.look, 1, L["Hidden columns"],
        L["How many columns are hidden across every list. Show all puts every one back."])
    widgets.columnsHidden = Theme.CreateLabel(showAllRow, "small", "muted")
    widgets.columnsHidden:SetPoint("TOPLEFT", CONTROL_X, -4)

    widgets.columnsShowAll = Widgets.CreateButton(showAllRow, L["Show all"], function()
        ns.Columns:ShowAll()
    end, { width = 80, height = 20, tooltip = L["Show every column of every list again"] })
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

    CreateSection(pages.data, 1, L["TROUBLESHOOTING"])
    local debugRow = CreateRow(pages.data, 1, L["Debug output"],
        L["Extra messages in chat, to help track down problems."])

    widgets.debug = Widgets.CreateCheckbox(debugRow, L["Enabled"], function(checked)
        ns.db.global.debug = checked
    end, false)
    widgets.debug:SetPoint("TOPLEFT", CONTROL_X, -2)

    -- The probe as a button (asked 2026-10-10); what it finds is also kept
    -- in the saved data for Claude to read after a /reload.
    local probeRow = CreateRow(pages.data, 1, L["Client check"],
        L["Lists in chat what this version of the game supports and whether your data is kept. It only reads. Same as /bts probe."])

    widgets.probe = Widgets.CreateButton(probeRow, L["Check"], function()
        local command = ns.commands and ns.commands.probe
        if command then command.fn("") end
    end, { width = 80, height = 20,
           tooltip = L["Lists in chat what this version of the game supports. Same as /bts probe"] })
    widgets.probe:SetPoint("TOPLEFT", CONTROL_X, -2)
    FitButton(widgets.probe)

    -- /bts perf and /bts perf clear as buttons; what Show lists is kept for
    -- Claude too.
    local perfRow = CreateRow(pages.data, 1, L["Speed check"],
        L["Lists in chat the slowest things Tradeskills did since you logged in or last cleared, to find a hitch. Same as /bts perf."])

    local function Perf(rest)
        local command = ns.commands and ns.commands.perf
        if command then command.fn(rest) end
    end
    widgets.perfShow = Widgets.CreateButton(perfRow, L["Show"], function() Perf("") end,
        { width = 60, height = 20, tooltip = L["Lists in chat what took longest. Same as /bts perf"] })
    widgets.perfShow:SetPoint("TOPLEFT", CONTROL_X, -2)
    FitButton(widgets.perfShow)
    widgets.perfClear = Widgets.CreateButton(perfRow, L["Clear"], function() Perf("clear") end,
        { width = 60, height = 20, tooltip = L["Starts the speed check over. Same as /bts perf clear"] })
    widgets.perfClear:SetPoint("LEFT", widgets.perfShow, "RIGHT", 6, 0)
    FitButton(widgets.perfClear)

    -- Every sound the addon plays, each with its own switch, all on to start
    -- with. The one sound not here is the warning that saved data failed to
    -- load, which is about losing data rather than an effect.
    CreateSection(pages.look, 2, L["SOUNDS"])
    widgets.sounds = {}

    local function SoundRow(key, label, description, test)
        local row = CreateRow(pages.look, 2, label, description)
        local box = Widgets.CreateCheckbox(row, L["Enabled"], function(checked)
            Config:Set(key, checked)
        end, true)
        box:SetPoint("TOPLEFT", CONTROL_X, -2)
        widgets.sounds[key] = box

        if test then
            local button = Widgets.CreateButton(row, L["Test"], test,
                { width = 60, height = 20, tooltip = L["Play it now"] })
            button:SetPoint("TOPLEFT", CONTROL_X + 100, -2)
        end

        return box
    end

    -- The sale alarm picks its sound (asked 2026-10-11: players found the
    -- raid warning too much and asked for an old cash register). Off is the
    -- saleAlarm switch; the sound is saleSound. Picking one plays it.
    local saleRow = CreateRow(pages.look, 2, L["An auction sells"],
        L["A sound as soon as one of your auctions sells, wherever you are: an old cash register, coins, or the raid warning. Press Play to hear it."])

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

    widgets.scanSounds = SoundRow("scanSounds", L["A scan finishes"],
        L["A chime when a scan finishes, and another when it finds disenchant or vendor deals."])
    SoundRow("mailReportSound", L["Mail report"],
        L["The coins as the mail report counts up, and the fanfare on a new record."])
    SoundRow("craftDoneSound", L["Crafting finishes"],
        L["A chime when a run of two or more crafts is done."])
    SoundRow("bagsFullSound", L["Bags are full"],
        L["A warning the moment your last free bag slot fills."])
    SoundRow("disenchantSound", L["Disenchant finds"],
        L["A chime when a disenchant turns up something new or lucky."])
    SoundRow("altCraftSound", L["Cheaper on an alt"],
        L["A coin when another of your characters can make a material for less."])
    SoundRow("goalSound", L["Farmer goal set"],
        L["A cheer when Set goal on the Gather tab makes a Farmer goal."])

    -- Sharing (asked 2026-10-07): your characters on another account of
    -- yours, and prices within your guild. Logic/AccountLink.lua and
    -- Logic/GuildPrices.lua; every /bts share command has a control here.
    CreateSection(pages.sharing, 1, L["ACCOUNT LINK"])

    local linkRow = CreateRow(pages.sharing, 1, L["Your other account"],
        L["Full names (first and last) of characters on another account of yours, separated by commas. Add this character's full name on that side too. While both are logged in on the same realm, each sends the other its characters."])

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
    local function ShareRow(key, label, description)
        local row = CreateRow(pages.sharing, 1, label, description)
        local box = Widgets.CreateCheckbox(row, L["Send"], function(checked)
            Config:Set(key, checked)
        end, true)
        box:SetPoint("TOPLEFT", CONTROL_X, -2)
        widgets.linkShares[key] = box
    end

    ShareRow("linkShareRecipes", L["Share recipes"], L["Your characters' professions and recipes."])
    ShareRow("linkShareBags", L["Share bags, bank and mail"], L["What your characters carry, bank and have in the mail."])
    ShareRow("linkShareGold", L["Share gold"], L["How much gold each of your characters has."])
    ShareRow("linkShareAuctions", L["Share auctions"], L["What your characters have listed, so Keep in stock counts it."])

    local syncButton = Widgets.CreateButton(pages.sharing.content, L["Sync now"], function()
        if ns.AccountLink then ns.AccountLink:Check() end
        ns.Print(L["asked your other account for anything new"])
        C_Timer.After(3, function() UI:RefreshActiveTab() end)
    end, { width = 110, height = 22, tooltip = L["Say hello to your other account now and swap anything that changed"] })
    Place(pages.sharing, 1, syncButton, -10)
    FitButton(syncButton)

    local testButton = Widgets.CreateButton(pages.sharing.content, L["Test messages"], function()
        if ns.Comm then ns.Comm:Test() end
    end, { width = 120, height = 22, tooltip = L["Whisper yourself a few addon messages and say in chat what the game did with them"] })
    testButton:SetPoint("LEFT", syncButton, "RIGHT", 8, 0)
    FitButton(testButton)

    -- Removes only copies from the other account, never your own
    -- characters; still arms first.
    widgets.forgetLinked = Widgets.CreateButton(pages.sharing.content, L["Forget their characters"], function()
        local button = widgets.forgetLinked
        if not button.armed then
            button.armed = true
            button:SetText(L["Really forget?"])
            button:SetConfirming(true)
            C_Timer.After(4, function()
                if button.armed then
                    button.armed = false
                    button:SetText(L["Forget their characters"])
                    button:SetConfirming(false)
                end
            end)
            return
        end
        button.armed = false
        button:SetText(L["Forget their characters"])
        button:SetConfirming(false)
        local count = ns.AccountLink and ns.AccountLink:Forget() or 0
        ns.Print(count == 1
            and L.Format("forgot %d character from your other account", count)
            or L.Format("forgot %d characters from your other account", count))
        UI:RefreshActiveTab()
    end, { width = 170, height = 22,
           tooltip = L["Remove the copies of your other account's characters. Your own characters are never touched. Asks you to click again first."] })
    Place(pages.sharing, 1, widgets.forgetLinked, -8)
    FitButton(widgets.forgetLinked)

    widgets.linkStatus = Theme.CreateLabel(pages.sharing.content, "tiny", "muted")
    Place(pages.sharing, 1, widgets.linkStatus, -8)
    widgets.linkStatus:SetWidth(COLUMN_WIDTH)
    widgets.linkStatus:SetWordWrap(true)

    CreateSection(pages.sharing, 2, L["GUILD"])
    local guildRow = CreateRow(pages.sharing, 2, L["Guild prices"],
        L["Shares your scans with guildmates who use this addon, at most once an hour, and fills gaps in your prices with theirs. Your own scans always win."])
    widgets.guildPrices = Widgets.CreateCheckbox(guildRow, L["Enabled"], function(checked)
        Config:Set("guildPrices", checked)
        UI:RefreshActiveTab()
    end, false)
    widgets.guildPrices:SetPoint("TOPLEFT", CONTROL_X, -2)

    widgets.guildStatus = Theme.CreateLabel(pages.sharing.content, "tiny", "muted")
    Place(pages.sharing, 2, widgets.guildStatus, -4)
    widgets.guildStatus:SetWidth(COLUMN_WIDTH)
    widgets.guildStatus:SetWordWrap(true)

    CreateSection(pages.sharing, 2, L["TRADESKILLMASTER"])
    local tsmRow = CreateRow(pages.sharing, 2, L["TSM prices"],
        L["When TradeSkillMaster is loaded, its prices fill in items that neither you nor your guildmates have priced. Your own scans always win."])
    widgets.tsmPrices = Widgets.CreateCheckbox(tsmRow, L["Enabled"], function(checked)
        Config:Set("tsmPrices", checked)
        if ns.TSMPrices then ns.TSMPrices:Forget() end
        UI:RefreshActiveTab()
    end, false)
    widgets.tsmPrices:SetPoint("TOPLEFT", CONTROL_X, -2)

    widgets.tsmStatus = Theme.CreateLabel(pages.sharing.content, "tiny", "muted")
    Place(pages.sharing, 2, widgets.tsmStatus, -4)
    widgets.tsmStatus:SetWidth(COLUMN_WIDTH)
    widgets.tsmStatus:SetWordWrap(true)

    -- Every setting at once, so it arms first like Clear price data.
    local resetButton
    resetButton = Widgets.CreateButton(pages.data.content, L["Reset to defaults"], function()
        if not resetButton.armed then
            resetButton.armed = true
            resetButton:SetText(L["Really reset?"])
            resetButton:SetConfirming(true)

            C_Timer.After(4, function()
                if resetButton.armed then
                    resetButton.armed = false
                    resetButton:SetText(L["Reset to defaults"])
                    resetButton:SetConfirming(false)
                end
            end)
            return
        end

        resetButton.armed = false
        resetButton:SetText(L["Reset to defaults"])
        resetButton:SetConfirming(false)

        -- Through Config:Set, as every other setting change is, so a session
        -- keeping its settings in the backup store saves these too.
        for key, value in pairs(ns.Config.DEFAULTS.settings) do
            ns.Config:Set(key, value)
        end

        -- What each control does on a change, done for the reset too. Only
        -- the values moved before: queued sub-crafts stayed as they were,
        -- the profession window kept its old values, and a folded side
        -- panel grew to full height with nothing in it.
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

        ns.Print(L["settings reset to defaults"])
        UI:RefreshActiveTab()
    end, { width = 150, height = 22, tooltip = L["Put every setting back to how it started. Asks you to click again first."] })
    -- Under the last setting rather than pinned to the page's bottom edge:
    -- measured from there, the page grew 4 pixels taller every time it was
    -- drawn, and left more empty space to scroll into each time.
    Place(pages.data, 1, resetButton, -18)
    FitButton(resetButton)

    -- The buttons standing on their own, so the search finds them too.
    Searchable(pages.data, pruneButton, L["Remove old prices Drop items not seen on the auction house for 21 days"])
    Searchable(pages.data, widgets.clearButton, L["Clear price data Delete every stored price for this realm"])
    Searchable(pages.data, resetButton, L["Reset to defaults Put every setting back to how it started"])
    Searchable(pages.queue, exportButton, L["Export queue Copy your queue, settings and stock limits to a code"])
    Searchable(pages.queue, importButton, L["Import Restore from a code"])
    Searchable(pages.sharing, syncButton, L["Sync now Say hello to your other account now and swap anything that changed"])
    Searchable(pages.sharing, testButton, L["Test messages Whisper yourself a few addon messages"])
    Searchable(pages.sharing, widgets.forgetLinked, L["Forget their characters Remove the copies of your other account's characters"])

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

local IGNORED_ROW_HEIGHT = 22
local RESTORE_WIDTH = 70

--- One line per ignored craft or item: its name, and Restore at the
--- column's edge. `rows` is the list's own row table, `hint` the label the
--- rows hang under, `onRestore(key)` puts one back.
local function IgnoredRow(rows, hint, index, onRestore, restoreTip, buttonText)
    local row = rows[index]
    if row then return row end

    row = CreateFrame("Frame", nil, widgets.ignoredParent)
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
        return L.Format("%s |cff7a8089· no character knows it|r", name)
    end
    local buy = ns.Cost:GetReagentUnitCost(entry.outputItemID)
    if not buy then
        return L.Format("%s |cff7a8089·|r |c%sno price to buy it|r", name, ns.COLORS.warn)
    end
    return L.Format("%s |cff7a8089· buy %s each|r", name,
        Util.FormatMoney(buy, { noColor = true, short = true }))
end

local function RefreshNeverSubCrafts()
    if not widgets.neverHint or not (ns.Cost and ns.Cost.GetNeverSubCrafts) then return end

    local list = {}
    for _, entry in ipairs(ns.Cost:GetNeverSubCrafts()) do
        list[#list + 1] = { key = entry.recipeID, name = NeverLine(entry) }
    end

    local last = FillIgnored(list, widgets.neverRows, widgets.neverHint, widgets.neverEmpty,
        function(recipeID) ns.Cost:SetNeverSubCraft(recipeID, false) end,
        L["Make it as a sub-craft again whenever that is cheaper than buying it"],
        nil, L["Allow"])

    widgets.neverEnd:ClearAllPoints()
    widgets.neverEnd:SetPoint("TOPLEFT", last, "BOTTOMLEFT", 0, 0)
end

local function RefreshIgnored()
    RefreshNeverSubCrafts()
    if not widgets.ignoredHint or not ns.Profit.GetIgnored then return end

    local crafts = {}
    for _, entry in ipairs(ns.Profit:GetIgnored()) do
        crafts[#crafts + 1] = { key = entry.recipeID, name = entry.name }
    end

    local last = FillIgnored(crafts, widgets.ignoredRows, widgets.ignoredHint,
        widgets.ignoredEmpty,
        function(recipeID) ns.Profit:SetIgnored(recipeID, false) end,
        L["Show this craft on the Profit tab again"])

    widgets.ignoredEnd:ClearAllPoints()
    widgets.ignoredEnd:SetPoint("TOPLEFT", last, "BOTTOMLEFT", 0, 0)

    if not widgets.ignoredItemsHint or not (ns.Posting and ns.Posting.GetIgnored) then return end

    local items = {}
    for _, entry in ipairs(ns.Posting:GetIgnored()) do
        items[#items + 1] = { key = entry.itemID, name = entry.name }
    end

    -- In the item's rarity colour, as Ready to sell draws it.
    FillIgnored(items, widgets.ignoredItemsRows, widgets.ignoredItemsHint,
        widgets.ignoredItemsEmpty,
        function(itemID) ns.Posting:SetIgnored(itemID, false) end,
        L["Offer this item on Ready to sell again"],
        function(itemID) return Util.GetItemQualityColor(itemID) end)
end

local function Refresh()
    if not widgets.undercut then return end

    RefreshIgnored()

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
    Put(widgets.undercut, Config:Get("undercutCopper") or 1)
    widgets.undercutSwitch:Update()
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
    Put(widgets.restockAt, Config:Get("restockAt") or 0)
    widgets.fastSellerBoost:SetChecked(Config:Get("fastSellerBoost") == true)
    local extra = Config:Get("fastSellerExtra")
    Put(widgets.fastSellerExtra, type(extra) == "number" and extra or 2)
    widgets.hideMaxed:SetChecked(Config:Get("hideAtPostLimit") ~= false)
    widgets.allowLoss:SetChecked(Config:Get("allowPostingAtALoss") == true)
    widgets.neverBelowPaid:SetChecked(Config:Get("neverBelowCraftedCost") == true)
    widgets.verifyPrice:SetChecked(Config:Get("verifyPriceBeforePosting") ~= false)
    widgets.subCrafts:SetChecked(Config:Get("autoQueueSubCrafts") ~= false)
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
    widgets.debug:SetChecked(ns.db.global.debug == true)
    widgets.autoScan:SetChecked(Config:Get("autoScan") ~= false)
    widgets.learnFromSearches:SetChecked(Config:Get("learnFromSearches") ~= false)
    widgets.professionValue:SetChecked(Config:Get("showValueInProfessionWindow") ~= false)
    widgets.tooltipValue:SetChecked(Config:Get("showValueOnItemTooltips") ~= false)
    widgets.upgradeArrows:SetChecked(Config:Get("showUpgradeArrows") ~= false)
    widgets.sisters:SetChecked(ns.SisterNote:IsOn())
    widgets.recipeTooltips:SetChecked(Config:Get("showRecipeValueOnTooltips") ~= false)
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
    for key, box in pairs(widgets.sounds) do
        box:SetChecked(Config:Get(key) ~= false)
    end
    widgets.saleAlarm:Refresh()
    widgets.stale:SetValue(Config:Get("staleAfterSeconds") or (48 * 3600), true)

    local linkBox = widgets.linkNames.editBox
    if not (linkBox.HasFocus and linkBox:HasFocus()) then
        local saved = Config:Get("linkNames") or ""
        if widgets.linkNames:GetText() ~= saved then widgets.linkNames:SetText(saved) end
    end
    for key, box in pairs(widgets.linkShares) do
        box:SetChecked(Config:Get(key) ~= false)
    end
    widgets.linkStatus:SetText(ns.AccountLink and ns.AccountLink:Describe() or "")
    widgets.guildPrices:SetChecked(Config:Get("guildPrices") == true)
    widgets.guildStatus:SetText(ns.GuildPrices and ns.GuildPrices:Describe() or "")
    widgets.tsmPrices:SetChecked(Config:Get("tsmPrices") ~= false)
    widgets.tsmStatus:SetText(ns.TSMPrices and ns.TSMPrices:Describe() or "")

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
            L["Welcome! This is the first time the addon has run here, so there is no saved data yet."])
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

UI:RegisterTab({
    key = "settings",
    text = L["Settings"],
    order = 8,
    build = Build,
    refresh = Refresh,
    onShow = Refresh,
})
