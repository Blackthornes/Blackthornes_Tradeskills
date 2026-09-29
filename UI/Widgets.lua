-- Blackthornes Tradeskills -- UI/Widgets.lua
-- Reusable controls, built from scratch so the addon looks like one piece of
-- software rather than a pile of Blizzard templates.
--
-- The important one is CreateScrollList: it recycles a fixed handful of row
-- frames regardless of how many rows the data has. With 600+ recipes and
-- thousands of auction items, a frame per row would stutter badly.

local _, ns = ...

local Widgets = {}
ns.Widgets = Widgets

local Theme = ns.Theme

--------------------------------------------------------------------------------
-- Button
--------------------------------------------------------------------------------

function Widgets.CreateButton(parent, text, onClick, opts)
    opts = opts or {}

    local button = CreateFrame("Button", nil, parent)
    button:SetSize(opts.width or 90, opts.height or 22)

    local baseKey = opts.primary and "rowActive" or "row"

    button.background = Theme.Fill(button, baseKey)

    -- The primary action wears a gold edge, so the one button that does the
    -- main thing on a screen stands out from the rest without shouting.
    local borderKey = opts.primary and "accent" or "border"
    local borderAlpha = opts.primary and 0.55 or nil
    Theme.Border(button, borderKey, borderAlpha)
    button.sheen = Theme.TopSheen(button)

    -- An explicit resting colour, for buttons that sit over the game world and
    -- need to stay fully opaque rather than picking up the panel palette.
    button.baseColor = opts.baseColor

    local function ApplyBaseColor(self)
        if self.disabled then
            self.background:SetColorTexture(Theme.Unpack("panel"))
        elseif self.baseColor then
            self.background:SetColorTexture(unpack(self.baseColor))
        else
            self.background:SetColorTexture(Theme.Unpack(baseKey))
        end
    end

    button.ApplyBaseColor = ApplyBaseColor

    button.label = Theme.CreateLabel(button, opts.fontSize or "small",
        opts.primary and "accent" or "text", "CENTER")
    -- Held inside the button, so a label longer than the button ends in
    -- "..." instead of spilling over whatever sits beside it. The little
    -- symbol buttons (+, -, x) stay centred: their insets would leave no
    -- room for the symbol itself.
    -- Narrow buttons ("Set goal", "Queue tab") get thinner insets, or their
    -- labels would be the ones cut short.
    if (opts.width or 90) >= 40 then
        local inset = (opts.width or 90) < 70 and 2 or 4
        button.label:SetPoint("LEFT", inset, 0)
        button.label:SetPoint("RIGHT", -inset, 0)
        button.label:SetWordWrap(false)
    else
        button.label:SetPoint("CENTER")
    end
    button.label:SetText(text)

    function button:SetText(value)
        self.label:SetText(value)
    end

    function button:SetEnabledState(enabled)
        self.disabled = not enabled

        self.label:SetTextColor(Theme.Unpack(
            enabled and (opts.primary and "accent" or "text") or "dim"))

        ApplyBaseColor(self)

        if not self.outline then
            if enabled then
                Theme.SetBorderColor(self, borderKey, borderAlpha)
            else
                Theme.SetBorderColor(self, "border", 0.6)
            end
        end
    end

    button:SetScript("OnEnter", function(self)
        if not self.disabled then
            self.background:SetColorTexture(Theme.Unpack("rowHover"))

            if not self.outline then
                Theme.SetBorderColor(self, opts.primary and "accent" or "borderLit")
            end
        end

        -- tooltipText is set at runtime, so a button can explain why it is
        -- currently unavailable rather than just looking dead.
        local text = self.tooltipText or opts.tooltip
        if text then
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(text, 1, 1, 1, 1, true)
            GameTooltip:Show()
        end
    end)

    button:SetScript("OnLeave", function(self)
        ApplyBaseColor(self)

        -- An outlined button keeps its own edge colour; resetting it here would
        -- undo the outline on the first mouseover.
        if not self.outline then
            Theme.SetBorderColor(self, borderKey, borderAlpha)
        end

        GameTooltip:Hide()
    end)

    button:SetScript("OnClick", function(self, mouseButton)
        if self.disabled then return end
        if onClick then onClick(self, mouseButton) end
    end)

    return button
end

--------------------------------------------------------------------------------
-- Item tooltip
--------------------------------------------------------------------------------

--- Start a tooltip for an item row with the game's own tooltip for the item,
--- the one the bags show, so hovering a name inside the addon shows the item
--- itself (Trent, 2026-09-26). The addon's value lines join it the same way
--- they join any item tooltip. Falls back to the plain name when the game
--- cannot draw the item.
--
-- The caller adds its own lines after this and calls GameTooltip:Show().
function Widgets.ShowItemTooltip(owner, anchor, itemID, fallback)
    GameTooltip:SetOwner(owner, anchor or "ANCHOR_RIGHT")

    local shown = false
    if itemID and GameTooltip.SetItemByID then
        shown = pcall(GameTooltip.SetItemByID, GameTooltip, itemID)
    end

    local ok, count = pcall(GameTooltip.NumLines, GameTooltip)
    if not shown or not ok or (tonumber(count) or 0) == 0 then
        GameTooltip:SetText(fallback or "item", 1, 1, 1)
        return false
    end

    return true
end

--- A row whose whole tooltip is the item's own.
function Widgets.ShowItemOnly(owner, itemID, fallback)
    if not itemID then return end
    Widgets.ShowItemTooltip(owner, "ANCHOR_RIGHT", itemID, fallback)
    GameTooltip:Show()
end

--------------------------------------------------------------------------------
-- Checkbox
--------------------------------------------------------------------------------

function Widgets.CreateCheckbox(parent, text, onToggle, initial)
    local checkbox = CreateFrame("Button", nil, parent)
    checkbox:SetHeight(18)

    local box = CreateFrame("Frame", nil, checkbox)
    box:SetSize(14, 14)
    box:SetPoint("LEFT")
    Theme.Fill(box, "row")
    Theme.Border(box, "border")
    Theme.TopSheen(box)

    local tick = box:CreateTexture(nil, "OVERLAY")
    tick:SetPoint("CENTER")
    tick:SetSize(8, 8)
    tick:SetColorTexture(Theme.Unpack("accent"))

    local label = Theme.CreateLabel(checkbox, "small", "text")
    label:SetPoint("LEFT", box, "RIGHT", 6, 0)
    label:SetText(text)

    checkbox:SetWidth(label:GetStringWidth() + 24)
    checkbox.checked = initial and true or false

    local function PaintBox(hovered)
        tick:SetShown(checkbox.checked)
        Theme.SetBorderColor(box, checkbox.checked and "accent"
            or hovered and "borderLit" or "border")
    end

    PaintBox(false)

    function checkbox:SetChecked(value)
        self.checked = value and true or false
        PaintBox(false)
    end

    function checkbox:GetChecked()
        return self.checked
    end

    checkbox:SetScript("OnClick", function(self)
        self:SetChecked(not self.checked)
        if onToggle then onToggle(self.checked) end
    end)

    checkbox:SetScript("OnEnter", function()
        label:SetTextColor(Theme.Unpack("accent"))
        PaintBox(true)
    end)
    checkbox:SetScript("OnLeave", function()
        label:SetTextColor(Theme.Unpack("text"))
        PaintBox(false)
    end)

    return checkbox
end

--------------------------------------------------------------------------------
-- Search box
--------------------------------------------------------------------------------

function Widgets.CreateSearchBox(parent, placeholder, onChange)
    local container = Theme.CreatePanel(parent, "row")
    container:SetHeight(22)

    local editBox = CreateFrame("EditBox", nil, container)
    editBox:SetPoint("TOPLEFT", 6, 0)
    editBox:SetPoint("BOTTOMRIGHT", -20, 0)
    editBox:SetAutoFocus(false)
    editBox:SetFont(Theme.FONT, Theme.sizes.small, "")
    editBox:SetTextColor(Theme.Unpack("text"))

    local hint = Theme.CreateLabel(container, "small", "dim")
    hint:SetPoint("LEFT", 6, 0)
    hint:SetText(placeholder or "Search")

    local clear = CreateFrame("Button", nil, container)
    clear:SetSize(14, 14)
    clear:SetPoint("RIGHT", -4, 0)

    local clearLabel = Theme.CreateLabel(clear, "small", "muted", "CENTER")
    clearLabel:SetPoint("CENTER")
    clearLabel:SetText("x")
    clear:Hide()

    local function Update()
        local text = editBox:GetText()
        hint:SetShown(text == "")
        clear:SetShown(text ~= "")
        if onChange then onChange(text) end
    end

    -- Gold edge while typing, lit on hover, so it is clear where the keys go.
    local function PaintEdge()
        Theme.SetBorderColor(container, editBox:HasFocus() and "accent"
            or container:IsMouseOver() and "borderLit" or "border")
    end

    editBox:SetScript("OnEditFocusGained", PaintEdge)
    editBox:SetScript("OnEditFocusLost", PaintEdge)
    container:SetScript("OnEnter", PaintEdge)
    container:SetScript("OnLeave", PaintEdge)
    editBox:SetScript("OnEnter", PaintEdge)
    editBox:SetScript("OnLeave", PaintEdge)
    container:EnableMouse(true)

    editBox:SetScript("OnTextChanged", Update)
    editBox:SetScript("OnEscapePressed", function(self)
        self:SetText("")
        self:ClearFocus()
    end)
    editBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)

    clear:SetScript("OnClick", function()
        editBox:SetText("")
        editBox:ClearFocus()
    end)

    container.editBox = editBox

    function container:GetText() return editBox:GetText() end
    function container:SetText(value) editBox:SetText(value or "") end

    return container
end

--------------------------------------------------------------------------------
-- Number box
--------------------------------------------------------------------------------

--- A small numeric field that validates on focus loss.
--
-- Values are clamped rather than rejected: silently refusing input leaves the
-- player wondering what they typed wrong.
-- @param opts { width, height, background, min, max, decimals,
--   onChange = function(value) }
function Widgets.CreateNumberBox(parent, opts)
    opts = opts or {}

    local container = Theme.CreatePanel(parent, opts.background or "row")
    container:SetSize(opts.width or 60, opts.height or 22)

    -- The bounds live on the container, not in opts, so a box reused across
    -- the rows of a list can take the limits of whatever it is showing.
    container.min, container.max = opts.min, opts.max

    local editBox = CreateFrame("EditBox", nil, container)
    editBox:SetPoint("TOPLEFT", 5, 0)
    editBox:SetPoint("BOTTOMRIGHT", -5, 0)
    editBox:SetAutoFocus(false)
    editBox:SetJustifyH(opts.justify or "RIGHT")
    editBox:SetFont(Theme.FONT, Theme.sizes.small, "")
    editBox:SetTextColor(Theme.Unpack("text"))

    local decimals = opts.decimals or 0

    local function Format(value)
        if decimals > 0 then
            return string.format("%." .. decimals .. "f", value)
        end
        return tostring(math.floor(value + 0.5))
    end

    function container:GetValue()
        return tonumber(editBox:GetText())
    end

    --- Change the bounds, clamping what is already in the box to fit them.
    function container:SetLimits(min, max)
        self.min, self.max = min, max
        if self.value then self:SetValue(self.value, true) end
    end

    function container:SetValue(value, silent)
        value = tonumber(value) or self.min or 0

        -- A whole-number box stores a whole number. Typing 5.5 used to show
        -- 6 but hand 5.5 to the setting behind it, and a limit of 5.5 then
        -- broke every "%d" that printed it.
        if (opts.decimals or 0) == 0 then value = math.floor(value + 0.5) end

        if self.min and value < self.min then value = self.min end
        if self.max and value > self.max then value = self.max end

        local changed = value ~= self.value
        self.value = value
        editBox:SetText(Format(value))

        -- Only a change is reported. Clicking into a box and away again is
        -- not a decision, and a per-item box that reported its unchanged
        -- default wrote that default down as an override for the item.
        if changed and not silent and opts.onChange then
            opts.onChange(value)
        end
    end

    local function Commit()
        -- ClearFocus fires OnEditFocusLost, which calls back here; without this
        -- guard the change handler runs twice per edit.
        if container.committing then return end
        container.committing = true

        -- Reverting to the last good value beats leaving unparsable text on
        -- screen that looks like it was accepted.
        container:SetValue(container:GetValue() or container.value or 0)
        editBox:ClearFocus()

        container.committing = false
    end

    editBox:SetScript("OnEnterPressed", Commit)
    editBox:SetScript("OnEditFocusLost", Commit)
    editBox:SetScript("OnEscapePressed", function(self)
        container:SetValue(container.value, true)
        self:ClearFocus()
    end)

    container:SetScript("OnEnter", function(self) Theme.SetBorderColor(self, "borderLit") end)
    container:SetScript("OnLeave", function(self) Theme.SetBorderColor(self, "border") end)
    container:EnableMouse(true)

    container.editBox = editBox
    return container
end

--------------------------------------------------------------------------------
-- Dropdown
--------------------------------------------------------------------------------

--- Minimal dropdown. options is an array of { text, value }.
function Widgets.CreateDropdown(parent, options, onSelect, opts)
    opts = opts or {}

    local dropdown = Theme.CreatePanel(parent, "row")
    dropdown:SetSize(opts.width or 140, 22)
    dropdown:EnableMouse(true)
    Theme.TopSheen(dropdown)

    local label = Theme.CreateLabel(dropdown, "small", "text")
    label:SetPoint("LEFT", 6, 0)
    label:SetPoint("RIGHT", -18, 0)

    local arrow = Theme.CreateLabel(dropdown, "tiny", "muted", "CENTER")
    arrow:SetPoint("RIGHT", -6, 0)
    arrow:SetText("v")

    local menu = Theme.CreatePanel(parent, "panel", "borderLit")
    menu:SetFrameStrata("DIALOG")
    menu:SetPoint("TOPLEFT", dropdown, "BOTTOMLEFT", 0, -2)
    menu:SetPoint("TOPRIGHT", dropdown, "BOTTOMRIGHT", 0, -2)
    menu:Hide()

    dropdown.options = options or {}
    dropdown.selected = nil

    local entries = {}

    local function Rebuild()
        for _, entry in ipairs(entries) do
            entry:Hide()
        end

        local y = -4
        for index, option in ipairs(dropdown.options) do
            local entry = entries[index]

            if not entry then
                entry = CreateFrame("Button", nil, menu)
                entry:SetHeight(20)
                entry.highlight = Theme.Fill(entry, "rowHover", 0, "ARTWORK")
                entry.label = Theme.CreateLabel(entry, "small", "text")
                entry.label:SetPoint("LEFT", 8, 0)
                entry.label:SetPoint("RIGHT", -8, 0)

                entry:SetScript("OnEnter", function(self) self.highlight:SetAlpha(1) end)
                entry:SetScript("OnLeave", function(self) self.highlight:SetAlpha(0) end)

                entries[index] = entry
            end

            entry:SetPoint("TOPLEFT", 1, y)
            entry:SetPoint("TOPRIGHT", -1, y)
            entry.label:SetText(option.text)
            entry.label:SetTextColor(Theme.Unpack(
                option.value == dropdown.selected and "accent" or "text"))
            entry:Show()

            entry:SetScript("OnClick", function()
                dropdown:SetValue(option.value)
                menu:Hide()
                if onSelect then onSelect(option.value, option) end
            end)

            y = y - 20
        end

        menu:SetHeight(math.max(8, (#dropdown.options * 20) + 8))
    end

    function dropdown:SetOptions(newOptions)
        self.options = newOptions or {}
        Rebuild()

        -- Keep the current selection if it still exists, else fall back.
        local stillValid = false
        for _, option in ipairs(self.options) do
            if option.value == self.selected then stillValid = true break end
        end

        if not stillValid then
            self:SetValue(self.options[1] and self.options[1].value)
        end
    end

    function dropdown:SetValue(value)
        self.selected = value

        for _, option in ipairs(self.options) do
            if option.value == value then
                label:SetText(option.text)
                return
            end
        end

        label:SetText(opts.placeholder or "")
    end

    function dropdown:GetValue()
        return self.selected
    end

    dropdown:SetScript("OnMouseDown", function()
        if menu:IsShown() then
            menu:Hide()
        else
            Rebuild()
            menu:Show()
            menu:Raise()
        end
    end)

    dropdown:SetScript("OnEnter", function(self)
        Theme.SetBorderColor(self, "borderLit")
        arrow:SetTextColor(Theme.Unpack("accent"))
    end)
    dropdown:SetScript("OnLeave", function(self)
        Theme.SetBorderColor(self, "border")
        arrow:SetTextColor(Theme.Unpack("muted"))
    end)

    dropdown.menu = menu
    dropdown:SetOptions(options)

    return dropdown
end

--------------------------------------------------------------------------------
-- Progress bar
--------------------------------------------------------------------------------

function Widgets.CreateProgressBar(parent)
    local bar = Theme.CreatePanel(parent, "panel")
    bar:SetHeight(4)

    local fill = bar:CreateTexture(nil, "ARTWORK")
    fill:SetPoint("TOPLEFT", 1, -1)
    fill:SetPoint("BOTTOMLEFT", 1, 1)
    fill:SetColorTexture(Theme.Unpack("accent"))
    fill:SetWidth(1)

    -- A brighter sliver at the leading edge, so the bar reads as moving.
    local tip = bar:CreateTexture(nil, "OVERLAY")
    tip:SetPoint("TOPRIGHT", fill, "TOPRIGHT")
    tip:SetPoint("BOTTOMRIGHT", fill, "BOTTOMRIGHT")
    tip:SetWidth(2)
    tip:SetColorTexture(1, 0.92, 0.65, 0.9)

    function bar:SetProgress(fraction)
        fraction = math.max(0, math.min(1, fraction or 0))
        local width = math.max(1, (self:GetWidth() - 2) * fraction)
        fill:SetWidth(width)
        tip:SetShown(fraction > 0 and fraction < 1)
    end

    bar:SetProgress(0)
    return bar
end

--------------------------------------------------------------------------------
-- Tab strip
--------------------------------------------------------------------------------

function Widgets.CreateTabStrip(parent, tabs, onSelect)
    local strip = CreateFrame("Frame", nil, parent)
    strip:SetHeight(28)

    strip.tabs = {}
    strip.selected = nil

    local x = 0
    for index, tab in ipairs(tabs) do
        local button = CreateFrame("Button", nil, strip)
        button:SetPoint("BOTTOMLEFT", x, 0)
        button:SetSize(tab.width or 96, 28)

        button.background = Theme.Fill(button, "panel")
        button.hover = Theme.Fill(button, "rowHover", 0.45, "BORDER")
        button.hover:Hide()

        -- A step smaller once the tabs get narrow, so "Disenchanting" stays
        -- inside its own tab.
        local labelSize = (tab.width or 96) < 90 and "small" or "normal"
        button.label = Theme.CreateLabel(button, labelSize, "muted", "CENTER")
        button.label:SetPoint("CENTER", 0, 0)
        button.label:SetText(tab.text)

        button.underline = button:CreateTexture(nil, "OVERLAY")
        button.underline:SetPoint("BOTTOMLEFT", 0, 0)
        button.underline:SetPoint("BOTTOMRIGHT", 0, 0)
        button.underline:SetHeight(2)
        button.underline:SetColorTexture(Theme.Unpack("accent"))
        button.underline:Hide()

        button.key = tab.key

        button:SetScript("OnClick", function(self)
            strip:Select(self.key)
            if onSelect then onSelect(self.key) end
        end)

        button:SetScript("OnEnter", function(self)
            if strip.selected ~= self.key then
                self.label:SetTextColor(Theme.Unpack("text"))
                self.hover:Show()
            end
        end)

        button:SetScript("OnLeave", function(self)
            self.hover:Hide()
            if strip.selected ~= self.key then
                self.label:SetTextColor(Theme.Unpack("muted"))
            end
        end)

        strip.tabs[index] = button
        x = x + (tab.width or 96)
    end

    strip:SetWidth(math.max(x, 1))

    function strip:Select(key)
        self.selected = key

        for _, button in ipairs(self.tabs) do
            local active = button.key == key
            button.underline:SetShown(active)
            button.hover:Hide()
            button.label:SetTextColor(Theme.Unpack(active and "accent" or "muted"))
            button.background:SetColorTexture(Theme.Unpack(active and "header" or "panel"))
        end
    end

    return strip
end

--------------------------------------------------------------------------------
-- Virtualized scroll list
--------------------------------------------------------------------------------

--- A list that recycles row frames.
--
-- @param opts
--   rowHeight  pixel height of one row
--   createRow  function(row) -- build the row's children once
--   updateRow  function(row, data, index) -- fill a row with data
--   onClick    function(data, index, mouseButton)
--   onEnter / onLeave  function(row, data)
--   isSelected function(data) -- true for the row the detail pane is showing,
--              which is then drawn lit with a gold edge
--- Light a scrollbar's thumb gold while the mouse is over the bar.
function Widgets.LightThumb(bar, thumb)
    bar:EnableMouse(true)
    bar:HookScript("OnEnter", function() thumb:SetColorTexture(Theme.Unpack("accent")) end)
    bar:HookScript("OnLeave", function() thumb:SetColorTexture(Theme.Unpack("borderLit")) end)
end

--------------------------------------------------------------------------------
-- Scroll frame
--------------------------------------------------------------------------------

--- A plain scrolling container for a laid-out panel.
--
-- Distinct from CreateScrollList, which recycles rows for a long uniform list.
-- This one scrolls a fixed set of real frames, which is what a settings page
-- needs: every control exists at once and keeps its own anchors.
--
-- Build into `scroll.content` rather than into the frame itself.
function Widgets.CreateScrollFrame(parent, opts)
    opts = opts or {}

    local scroll = CreateFrame("ScrollFrame", nil, parent)

    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(1, 1)
    scroll:SetScrollChild(content)
    scroll.content = content

    -- Parented to `parent`, not to the scroll child: anything inside the child
    -- scrolls with it, and a scrollbar that slides itself off the screen is a
    -- memorable bug to chase.
    local bar = CreateFrame("Slider", nil, parent)
    bar:SetOrientation("VERTICAL")
    bar:SetWidth(8)
    bar:SetPoint("TOPRIGHT", scroll, "TOPRIGHT", 8, 0)
    bar:SetPoint("BOTTOMRIGHT", scroll, "BOTTOMRIGHT", 8, 0)
    bar:SetValueStep(1)
    bar:SetObeyStepOnDrag(true)
    bar:SetValue(0)
    bar:Hide()

    local track = bar:CreateTexture(nil, "BACKGROUND")
    track:SetAllPoints(bar)
    track:SetColorTexture(Theme.Unpack("panel"))

    local thumb = bar:CreateTexture(nil, "ARTWORK")
    thumb:SetColorTexture(Theme.Unpack("borderLit"))
    thumb:SetSize(8, 40)
    bar:SetThumbTexture(thumb)
    Widgets.LightThumb(bar, thumb)

    scroll.scrollbar = bar

    bar:SetScript("OnValueChanged", function(_, value)
        scroll:SetVerticalScroll(value)
    end)

    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(_, delta)
        bar:SetValue(bar:GetValue() - delta * (opts.step or 40))
    end)

    --- Recompute how far there is to scroll, and show the bar only if there is.
    function scroll:UpdateRange()
        local view = self:GetHeight() or 0
        local height = content:GetHeight() or 0
        local range = math.max(0, height - view)

        bar:SetMinMaxValues(0, range)

        -- Shrinking content can leave the view scrolled past the end.
        if bar:GetValue() > range then bar:SetValue(range) end

        bar:SetShown(range > 0)

        if range > 0 and view > 0 then
            -- Thumb length tracks the visible fraction, so the bar says how
            -- much more there is rather than just that there is more.
            thumb:SetHeight(math.max(20, view * (view / height)))
        end
    end

    --- Size the content to whatever was built into it.
    --
    -- Measured from the children rather than tracked by hand: this panel is a
    -- chain of anchors, so nothing here knows the total height, and a guessed
    -- one is either a dead region at the bottom or content you cannot reach.
    function scroll:FitContent(padding)
        local top = content:GetTop()
        if not top then return false end

        local lowest = top

        for _, child in ipairs({ content:GetChildren() }) do
            local bottom = child:IsShown() and child:GetBottom()
            if bottom and bottom < lowest then lowest = bottom end
        end

        for _, region in ipairs({ content:GetRegions() }) do
            local bottom = region.GetBottom and region:GetBottom()
            if bottom and bottom < lowest then lowest = bottom end
        end

        content:SetHeight(math.max(1, top - lowest + (padding or 16)))
        self:UpdateRange()
        return true
    end

    scroll:SetScript("OnSizeChanged", function(self, width)
        content:SetWidth(width)
        self:UpdateRange()
    end)

    return scroll
end

function Widgets.CreateScrollList(parent, opts)
    local list = CreateFrame("Frame", nil, parent)

    local rowHeight = opts.rowHeight or 22

    list.data = {}
    list.rows = {}
    list.offset = 0

    local scrollbar = CreateFrame("Slider", nil, list)
    scrollbar:SetOrientation("VERTICAL")
    scrollbar:SetWidth(8)
    scrollbar:SetPoint("TOPRIGHT", 0, 0)
    scrollbar:SetPoint("BOTTOMRIGHT", 0, 0)
    scrollbar:SetValueStep(1)
    scrollbar:SetObeyStepOnDrag(true)

    local track = scrollbar:CreateTexture(nil, "BACKGROUND")
    track:SetAllPoints(scrollbar)
    track:SetColorTexture(Theme.Unpack("panel"))

    local thumb = scrollbar:CreateTexture(nil, "ARTWORK")
    thumb:SetColorTexture(Theme.Unpack("borderLit"))
    thumb:SetSize(8, 40)
    scrollbar:SetThumbTexture(thumb)
    Widgets.LightThumb(scrollbar, thumb)

    list.scrollbar = scrollbar

    -- Whole rows only. This used to round up, so the last row was drawn with
    -- its bottom hanging past the list's edge: the list is a plain frame that
    -- clips nothing, and that overhang is what sat on top of the footer line
    -- under the Prices and Profit tabs. Rounding down also matches how far
    -- the scrollbar lets the list go, which was already counted in whole rows.
    local function VisibleRowCount()
        local height = list:GetHeight()
        if not height or height <= 0 then return 0 end
        return math.floor(height / rowHeight)
    end

    local function AcquireRow(index)
        local row = list.rows[index]
        if row then return row end

        row = CreateFrame("Button", nil, list)
        row:SetHeight(rowHeight)
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")

        row.background = Theme.Fill(row, "row")
        row.highlight = Theme.Fill(row, "rowHover", 0, "BORDER")

        -- A gold edge on the row under the mouse, as Farmer's lists do, so the
        -- eye can follow a row across a wide table.
        row.hoverEdge = Theme.AccentStripe(row, 2)
        row.hoverEdge:SetDrawLayer("OVERLAY")
        row.hoverEdge:Hide()

        if opts.createRow then
            opts.createRow(row)
        end

        row:SetScript("OnEnter", function(self)
            self.highlight:SetAlpha(1)
            self.hoverEdge:Show()
            if opts.onEnter and self.data then opts.onEnter(self, self.data) end
        end)

        row:SetScript("OnLeave", function(self)
            self.highlight:SetAlpha(0)
            self.hoverEdge:SetShown(self.selected and true or false)
            if opts.onLeave then opts.onLeave(self, self.data) end
        end)

        row:SetScript("OnClick", function(self, mouseButton)
            if self.data and opts.onClick then
                opts.onClick(self.data, self.dataIndex, mouseButton, self)

                -- A click may have changed which row is selected.
                if opts.isSelected then list:Refresh() end
            end
        end)

        list.rows[index] = row
        return row
    end

    function list:Refresh()
        local total = #self.data
        local visible = VisibleRowCount()

        local maxOffset = math.max(0, total - math.floor(self:GetHeight() / rowHeight))
        if self.offset > maxOffset then self.offset = maxOffset end

        scrollbar:SetMinMaxValues(0, maxOffset)
        scrollbar:SetShown(maxOffset > 0)

        -- Rows give up 10px to the scrollbar while it shows. A table whose
        -- column headings sit outside the list is told, so its headings can
        -- move in step; otherwise every right-aligned value sat 10px left of
        -- its heading whenever the list scrolled.
        local hasScrollbar = maxOffset > 0
        if opts.onScrollbarShown and self.hadScrollbar ~= hasScrollbar then
            self.hadScrollbar = hasScrollbar
            opts.onScrollbarShown(hasScrollbar)
        end
        if scrollbar:GetValue() ~= self.offset then
            scrollbar:SetValue(self.offset)
        end

        for index = 1, math.max(visible, #self.rows) do
            local row = self.rows[index]

            if index <= visible then
                row = AcquireRow(index)
                row:SetPoint("TOPLEFT", 0, -((index - 1) * rowHeight))
                row:SetPoint("TOPRIGHT", maxOffset > 0 and -10 or 0, -((index - 1) * rowHeight))

                local dataIndex = index + self.offset
                local entry = self.data[dataIndex]

                if entry then
                    row.data = entry
                    row.dataIndex = dataIndex

                    -- Alternating bands make a dense table far easier to track
                    -- across, and must follow the data row, not the frame.
                    row.selected = opts.isSelected and opts.isSelected(entry) or false

                    if row.selected then
                        row.background:SetColorTexture(Theme.Unpack("rowActive"))
                    else
                        row.background:SetColorTexture(Theme.Unpack(
                            dataIndex % 2 == 0 and "rowAlt" or "row"))
                    end

                    row.hoverEdge:SetShown(row.selected or row:IsMouseOver())

                    if opts.updateRow then
                        opts.updateRow(row, entry, dataIndex)
                    end
                    row:Show()
                else
                    row.data = nil
                    row:Hide()
                end
            elseif row then
                row.data = nil
                row:Hide()
            end
        end
    end

    --- Replace the rows, keeping the reader where they were.
    --
    -- The scroll position used to reset here. Nothing noticed while the lists
    -- were short, but the Post tab rebuilds itself once a second at the
    -- auction house, and once it started showing a whole bagful that meant a
    -- list that snapped back to the top every second and could not be
    -- scrolled at all. Refresh already clamps the offset to what the new data
    -- allows, so keeping it is safe; a caller showing a genuinely different
    -- list asks for the top with ScrollToTop.
    function list:SetData(data)
        self.data = data or {}
        self:Refresh()
    end

    function list:ScrollToTop()
        self.offset = 0
        self:Refresh()
    end

    function list:GetData()
        return self.data
    end

    scrollbar:SetScript("OnValueChanged", function(_, value)
        local newOffset = math.floor(value + 0.5)
        if newOffset ~= list.offset then
            list.offset = newOffset
            list:Refresh()
        end
    end)

    list:EnableMouseWheel(true)
    list:SetScript("OnMouseWheel", function(self, delta)
        local _, maxOffset = scrollbar:GetMinMaxValues()
        local newOffset = math.max(0, math.min(maxOffset, self.offset - (delta * 3)))

        if newOffset ~= self.offset then
            self.offset = newOffset
            self:Refresh()
        end
    end)

    list:SetScript("OnSizeChanged", function(self)
        self:Refresh()
    end)

    return list
end
