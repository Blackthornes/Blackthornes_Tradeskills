-- Blackthornes Tradeskills -- UI/Columns.lua
-- Which columns each list shows (a player's request, 2026-10-09).
--
-- Right-click a list's column headings for a tick list of its columns, or
-- open the same list from Settings, Look & sound. Every column shows until
-- it is unticked, and the name column on the left is never in the list, so
-- a row always says what it is. A hidden column gives its room to the name.
--
-- The choice is kept per list in one setting, `hiddenColumns`: the hidden
-- ones as "list.key" separated by commas, so an empty string (the default)
-- shows everything. Nothing else is saved or changed.
--
-- A list registers its columns when its file loads, so Settings can name
-- them before the tab has ever been opened, and is told when they change
-- (Columns:OnChange) so it can lay its headings and rows out again. Rows
-- are recycled, so each compares Columns.version with the one it was laid
-- out at.

local _, ns = ...

local Theme = ns.Theme
local Widgets = ns.Widgets

local Columns = {}
ns.Columns = Columns

-- Bumped on every change, so a row knows its layout is out of date.
Columns.version = 1

local lists = {}        -- [id] = { id, title, columns, listeners }
local order = {}        -- ids in the order registered, for Settings
local hidden = nil      -- { ["list.key"] = true }, read from the setting

--------------------------------------------------------------------------------
-- The saved choice
--------------------------------------------------------------------------------

local function Read()
    if hidden then return hidden end
    -- Before the saved data is in, everything shows and nothing is kept.
    if not ns.db then return {} end
    hidden = {}
    local saved = ns.Config and ns.Config.Get and ns.Config:Get("hiddenColumns")
    if type(saved) == "string" then
        for entry in saved:gmatch("[^,]+") do hidden[entry] = true end
    end
    return hidden
end

local function Write()
    local entries = {}
    for entry in pairs(Read()) do entries[#entries + 1] = entry end
    table.sort(entries)
    if ns.Config and ns.Config.Set then ns.Config:Set("hiddenColumns", table.concat(entries, ",")) end
end

--- Can this column be hidden? Not one without a heading (a row's buttons)
--- or one its list keeps (`keep = true`).
function Columns.Hideable(column)
    return type(column) == "table" and not column.keep
        and type(column.label) == "string" and column.label ~= ""
end

--- Is this column shown in this list?
function Columns:Shown(id, column)
    if not Columns.Hideable(column) then return true end
    return not Read()[id .. "." .. tostring(column.key)]
end

--- Show or hide one column, and tell its list.
function Columns:SetShown(id, key, shown)
    local entry = id .. "." .. tostring(key)
    local set = Read()
    if (not set[entry]) == (shown and true or false) then return end

    set[entry] = (not shown) or nil
    Write()
    self:Changed(id)
end

--- Show every column of one list, or of every list with no id.
function Columns:ShowAll(id)
    local set, any = Read(), false
    for entry in pairs(set) do
        if id == nil or entry:sub(1, #id + 1) == id .. "." then
            set[entry] = nil
            any = true
        end
    end
    if not any then return end

    Write()
    if id then
        self:Changed(id)
    else
        for _, listID in ipairs(order) do self:Changed(listID) end
    end
end

--- How many of a list's columns are hidden (every list's with no id).
function Columns:HiddenCount(id)
    local count = 0
    for _, listID in ipairs(order) do
        if id == nil or id == listID then
            for _, column in ipairs(lists[listID].columns) do
                if not self:Shown(listID, column) then count = count + 1 end
            end
        end
    end
    return count
end

--- The setting was changed from elsewhere (Settings, Reset to defaults).
function Columns:Reload()
    hidden = nil
    for _, id in ipairs(order) do self:Changed(id) end
end

function Columns:Changed(id)
    self.version = self.version + 1

    local list = lists[id]
    if list then
        for _, listener in ipairs(list.listeners) do pcall(listener) end
    end

    if self.popup and self.popup:IsShown() and self.popup.list == id then self:Fill() end
    if self.onAnyChange then pcall(self.onAnyChange) end
end

--------------------------------------------------------------------------------
-- Lists
--------------------------------------------------------------------------------

--- Make a list's columns choosable. `columns` is the list's own table; a
--- list with views of different columns registers each view.
function Columns:Register(id, title, columns)
    local list = lists[id]
    if not list then
        list = { id = id, listeners = {} }
        lists[id] = list
        order[#order + 1] = id
    end
    list.title = title
    list.columns = columns
    return list
end

--- Run `fn` whenever this list's columns are shown or hidden.
function Columns:OnChange(id, fn)
    local list = lists[id] or self:Register(id, id, {})
    list.listeners[#list.listeners + 1] = fn
end

--- The registered lists, in order: { id, title, columns }.
function Columns:Lists()
    local out = {}
    for _, id in ipairs(order) do
        local list = lists[id]
        local any = false
        for _, column in ipairs(list.columns) do
            if Columns.Hideable(column) then any = true break end
        end
        if any then out[#out + 1] = list end
    end
    return out
end

--- The columns of `columns` this list shows, in order.
function Columns:Visible(id, columns)
    local out = {}
    for _, column in ipairs(columns) do
        if self:Shown(id, column) then out[#out + 1] = column end
    end
    return out
end

--- Lay a list's cells (or its headings) out right to left, as every list
--- here does: from `start` (-8) at the right edge, `gap` (6) apart. Hidden
--- columns are hidden and take no room.
--
-- @param regions  { [key] = font string }, or by index with opts.byIndex
-- @param opts  start, gap, byIndex, visible(column) for a list's own rule
--   (Profit's WHO only with alts), place(column, offset, shown) for what
--   else a column holds (a button, a number box)
-- @return the offset left of the last column shown, for the name's edge
function Columns:Place(id, columns, regions, opts)
    opts = opts or {}
    local offset = opts.start or -8
    local gap = opts.gap or 6

    for index, column in ipairs(columns) do
        local shown = self:Shown(id, column) and (not opts.visible or opts.visible(column))
        local region = regions and regions[opts.byIndex and index or column.key]

        if region then
            if shown then
                region:ClearAllPoints()
                region:SetPoint("RIGHT", region:GetParent(), "RIGHT", offset, 0)
                region:SetWidth(column.width)
                region:Show()
            else
                region:Hide()
            end
        end

        if opts.place then opts.place(column, offset, shown) end
        if shown then offset = offset - column.width - gap end
    end

    return offset
end

--------------------------------------------------------------------------------
-- The tick list
--------------------------------------------------------------------------------

local POPUP_WIDTH = 190
local LINE_HEIGHT = 22

--- "GOLD/HR" reads as "Gold/hr" in the list: easier on the eye than capitals.
local function Words(column)
    if column.menuText then return column.menuText end
    local label = column.label
    return label:sub(1, 1) .. label:sub(2):lower()
end

local function BuildPopup()
    local popup = Theme.CreatePanel(UIParent, "panel", "borderLit")
    popup:SetFrameStrata("DIALOG")
    popup:SetClampedToScreen(true)
    popup:EnableMouse(true)
    popup:SetWidth(POPUP_WIDTH)
    popup:Hide()
    if Theme.Halo then Theme.Halo(popup, 8, 0.12) end

    popup.title = Theme.CreateLabel(popup, "tiny", "accent")
    popup.title:SetPoint("TOPLEFT", 10, -8)
    popup.title:SetWidth(POPUP_WIDTH - 20)
    -- "Disenchanting: auction house" is wider than the box: it wraps.
    popup.title:SetWordWrap(true)

    popup.note = Theme.CreateLabel(popup, "tiny", "muted")
    popup.note:SetWidth(POPUP_WIDTH - 20)
    popup.note:SetWordWrap(true)

    popup.showAll = Widgets.CreateButton(popup, "Show all", function()
        if popup.list then Columns:ShowAll(popup.list) end
    end, { width = 80, height = 20, tooltip = "Tick every column of this list again" })

    popup.done = Widgets.CreateButton(popup, "Done", function() popup:Hide() end,
        { width = 60, height = 20, primary = true })

    popup.boxes = {}

    -- A click anywhere else closes it, as the dropdown menus do. Asked for
    -- only while open, inside a pcall: a client that does not know the
    -- event leaves it open until Done.
    popup:SetScript("OnShow", function(self)
        pcall(self.RegisterEvent, self, "GLOBAL_MOUSE_DOWN")
    end)
    popup:SetScript("OnHide", function(self)
        pcall(self.UnregisterEvent, self, "GLOBAL_MOUSE_DOWN")
    end)
    popup:SetScript("OnEvent", function(self)
        if self:IsMouseOver() then return end
        if self.anchor and self.anchor.IsMouseOver and self.anchor:IsMouseOver() then return end
        self:Hide()
    end)
    return popup
end

--- Draw the open tick list again from the saved choice.
function Columns:Fill()
    local popup = self.popup
    local list = popup and lists[popup.list]
    if not list then return end

    popup.title:SetText(("COLUMNS: %s"):format(list.title:upper()))
    local titleHeight = popup.title.GetStringHeight and popup.title:GetStringHeight()

    local y = -8 - (type(titleHeight) == "number" and math.ceil(titleHeight) or 12) - 6
    local count = 0
    for _, column in ipairs(list.columns) do
        if Columns.Hideable(column) then
            count = count + 1
            local box = popup.boxes[count]
            if not box then
                box = Widgets.CreateCheckbox(popup, "", function(checked)
                    if box.column then Columns:SetShown(popup.list, box.column.key, checked) end
                end, true)
                popup.boxes[count] = box
            end
            box.column = column
            box:SetLabel(Words(column))
            box:SetChecked(self:Shown(popup.list, column))
            box:ClearAllPoints()
            box:SetPoint("TOPLEFT", 10, y)
            box:Show()
            y = y - LINE_HEIGHT
        end
    end
    for index = count + 1, #popup.boxes do popup.boxes[index]:Hide() end

    popup.note:ClearAllPoints()
    popup.note:SetPoint("TOPLEFT", 10, y - 2)
    popup.note:SetText("The name column always shows.")
    local noteHeight = popup.note.GetStringHeight and popup.note:GetStringHeight()
    y = y - 4 - (type(noteHeight) == "number" and math.ceil(noteHeight) or 12) - 8

    popup.showAll:ClearAllPoints()
    popup.showAll:SetPoint("TOPLEFT", 10, y)
    popup.done:ClearAllPoints()
    popup.done:SetPoint("TOPRIGHT", -10, y)

    popup:SetHeight(-y + 20 + 10)
end

--- Open the tick list for a list, by `anchor` (or at the mouse).
function Columns:Open(id, anchor, atCursor)
    if not lists[id] then return end

    self.popup = self.popup or BuildPopup()
    local popup = self.popup
    popup.list = id
    popup.anchor = anchor
    self:Fill()

    popup:ClearAllPoints()
    local scale = UIParent.GetEffectiveScale and UIParent:GetEffectiveScale() or 1
    if atCursor and GetCursorPosition and type(scale) == "number" and scale > 0 then
        local x, y = GetCursorPosition()
        popup:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / scale + 4, y / scale - 4)
    elseif anchor then
        popup:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -4)
    else
        popup:SetPoint("CENTER", UIParent, "CENTER")
    end
    popup:Show()
    if popup.Raise then popup:Raise() end
end

function Columns:Close()
    if self.popup then self.popup:Hide() end
end

--- Make a list's headings open its tick list on a right-click, with a
--- line saying so under the mouse. Call after its SortableHeadings, so its
--- click areas say so too.
-- @param headings  the frame holding the headings
-- @param id  the list, or a function returning it (a list whose view changes)
function Columns:Attach(headings, id, sorter)
    local function List() return type(id) == "function" and id() or id end

    local function OnMouseUp(_, button)
        if button == "RightButton" then Columns:Open(List(), headings, true) end
    end

    local function Tip(owner)
        if not GameTooltip then return end
        GameTooltip:SetOwner(owner, "ANCHOR_TOP")
        GameTooltip:SetText("Right-click to choose which columns show", 1, 1, 1)
        GameTooltip:Show()
    end
    local function Untip(owner)
        if GameTooltip and GameTooltip.IsOwned and GameTooltip:IsOwned(owner) then GameTooltip:Hide() end
    end

    headings:EnableMouse(true)
    headings:SetScript("OnMouseUp", OnMouseUp)
    headings:SetScript("OnEnter", Tip)
    headings:SetScript("OnLeave", Untip)
    -- Its tab closing takes the tick list with it.
    if headings.HookScript then
        headings:HookScript("OnHide", function()
            if Columns.popup and Columns.popup.anchor == headings then Columns.popup:Hide() end
        end)
    end

    for _, button in pairs(sorter and sorter.buttons or {}) do
        if button.HookScript then
            button:HookScript("OnMouseUp", OnMouseUp)
            button:HookScript("OnEnter", Tip)
            button:HookScript("OnLeave", Untip)
        end
    end
end
