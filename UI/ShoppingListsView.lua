-- Blackthornes Tradeskills -- UI/ShoppingListsView.lua
-- The auction house drawer's Lists view: the player's named shopping lists
-- (Logic/ShoppingLists.lua), beside Sell and Buy (UI/PostPanel.lua).
--
-- A list is a row with its name, how many items, what is still to buy and a
-- gold Search that looks up every item on it the player still needs. A click
-- opens it: a row of tools (Rename, Copy, Delete), then a row per item with
-- how many are owned, the price, how many are wanted (a box to change it),
-- its own Search and an x. The first list, "From your craft queue", is the
-- Buy view's list and only offers Save as a list.
--
-- The foot holds one box that does what the moment needs: add an item to the
-- open list (type a name, or Shift-click an item anywhere while the box has
-- the keyboard), name a new list, rename one, show a list's copy line or take
-- a pasted one. Enter saves.

local _, ns = ...
local L = ns.L or setmetatable({ Format = string.format }, { __index = function(_, key) return key end })

local View = ns.NewModule("ShoppingListsView")

local Theme = ns.Theme
local Widgets = ns.Widgets
local Util = ns.Util

local ROW_HEIGHT = 30
-- At most this often the rows are worked out again while nothing moved; a
-- change to a list (ShoppingLists.version) or a click redraws at once.
local REFRESH_SECONDS = 2
-- How long Delete waits for its second click.
local ARM_SECONDS = 4
local QUEUE_KEY = "queue"

View.open = nil       -- the key of the open list: an index, or QUEUE_KEY
View.mode = nil       -- what the foot box does: add, new, rename, copy, paste
View.step = nil       -- a list searched one item at a time: { key, ids, needs, pos }
View.armed = nil      -- { key, at } while Delete waits for its second click

local function Lists() return ns.ShoppingLists end

--------------------------------------------------------------------------------
-- Building the rows
--------------------------------------------------------------------------------

local function LinesFor(key)
    if key == QUEUE_KEY then return Lists():QueueLines() end
    return Lists():Lines(key)
end

--- Every row to draw, in order: each list, and the open one's tools and items.
function View:Entries()
    local entries = {}
    local function AddList(key, name, lines, auto)
        local total, unpriced = Lists().Total(lines)
        local open = self.open == key
        entries[#entries + 1] = {
            kind = "list", key = key, name = name, auto = auto, open = open,
            count = #lines, total = total, unpriced = unpriced,
            searchable = Lists().Searchable(lines), lines = lines,
        }
        if not open then return end
        entries[#entries + 1] = { kind = "tools", key = key, auto = auto }
        for _, line in ipairs(lines) do
            entries[#entries + 1] = { kind = "item", key = key, auto = auto, line = line, itemID = line.itemID }
        end
    end

    AddList(QUEUE_KEY, L["From your craft queue"], LinesFor(QUEUE_KEY), true)
    for _, held in ipairs(Lists():Readable()) do
        AddList(held.index, held.list.name, LinesFor(held.index), false)
    end
    return entries
end

--------------------------------------------------------------------------------
-- Searching
--------------------------------------------------------------------------------

local function NeedOf(lines, itemID)
    for _, line in ipairs(lines or {}) do
        if line.itemID == itemID then return line.need end
    end
end

--- Search a list: every item at once where the game allows it, else one at
--- a time, the button reading "Next 2/5" until the last.
function View:SearchList(entry)
    local step = self.step
    if step and step.key == entry.key and step.pos <= #step.ids then
        local id = step.ids[step.pos]
        if ns.UI:SearchAuctionHouse(id, NeedOf(entry.lines, id)) then step.pos = step.pos + 1 end
        if step.pos > #step.ids then self.step = nil end
        self:Refresh(true)
        return
    end

    local ids = entry.searchable
    if #ids == 0 then
        ns.Print(L["Nothing on this list to look for on the auction house."])
        return
    end
    local ok, why = Lists():SearchMany(ids)
    if ok then
        self.step = nil
    elseif why == "single" then
        if ns.UI:SearchAuctionHouse(ids[1], NeedOf(entry.lines, ids[1])) and #ids > 1 then
            self.step = { key = entry.key, ids = ids, pos = 2 }
        end
    elseif why then
        ns.Print(why)
    end
    self:Refresh(true)
end

function View:SearchLabel(entry)
    local step = self.step
    if step and step.key == entry.key and step.pos <= #step.ids then
        return L.Format("Next %d/%d", step.pos, #step.ids)
    end
    return L["Search"]
end

--------------------------------------------------------------------------------
-- Rows
--------------------------------------------------------------------------------

local function Arm(key)
    View.armed = { key = key, at = GetTime() }
end

local function Armed(key)
    local armed = View.armed
    return armed and armed.key == key and GetTime() - armed.at <= ARM_SECONDS
end

local function CreateRow(row)
    row.chevron = Theme.CreateLabel(row, "small", "accent", "CENTER")
    row.chevron:SetPoint("LEFT", 4, 0)
    row.chevron:SetWidth(12)

    row.icon = Theme.CreateItemIcon(row, 14)
    row.icon:SetPoint("TOPLEFT", 20, -4)

    row.listSearch = Widgets.CreateButton(row, L["Search"], function()
        if row.data and row.data.kind == "list" then View:SearchList(row.data) end
    end, { width = 66, height = 20, primary = true,
        tooltip = L["Search the auction house for everything on this list you still need."] })
    row.listSearch:SetPoint("RIGHT", row, "RIGHT", -6, 0)

    row.total = Theme.CreateLabel(row, "small", "text", "RIGHT")
    row.total:SetPoint("RIGHT", row.listSearch, "LEFT", -6, 0)

    row.remove = Widgets.CreateButton(row, "x", function()
        local data = row.data
        if data and data.kind == "item" and not data.auto then
            Lists():Remove(data.key, data.itemID)
            View:Refresh(true)
        end
    end, { width = 18, height = 18, danger = true, tooltip = L["Take this off the list."] })
    row.remove:SetPoint("RIGHT", row, "RIGHT", -6, 0)

    row.itemSearch = Widgets.CreateButton(row, L["Search"], function()
        local data = row.data
        if data and data.kind == "item" and Lists().CanSearch(data.line) then
            ns.UI:SearchAuctionHouse(data.itemID, data.line.need)
        end
    end, { width = 50, height = 18,
        tooltip = L["Search the auction house for this. Pick it in the results and the quantity is filled in with how many you still need."] })
    row.itemSearch:SetPoint("RIGHT", row.remove, "LEFT", -4, 0)

    row.want = Widgets.CreateNumberBox(row, { width = 46, height = 18, min = 1, max = Lists().MAX_WANT,
        onChange = function(value)
            local data = row.data
            if data and data.kind == "item" and not data.auto and value then
                Lists():SetWant(data.key, data.itemID, value)
                View:Refresh(true)
            end
        end })
    row.want:SetPoint("RIGHT", row.itemSearch, "LEFT", -4, 0)

    row.name = Theme.CreateLabel(row, "small", "text")
    row.name:SetPoint("TOPLEFT", 20, -4)
    row.name:SetPoint("RIGHT", row.total, "LEFT", -6, 0)
    row.name:SetWordWrap(false)

    row.sub = Theme.CreateLabel(row, "tiny", "muted")
    row.sub:SetPoint("TOPLEFT", 40, -17)
    row.sub:SetPoint("RIGHT", row.want, "LEFT", -6, 0)
    row.sub:SetWordWrap(false)

    -- The tools under an open list.
    row.tools = {}
    local function Tool(text, width, onClick, opts)
        opts = opts or {}
        opts.width, opts.height = width, 20
        local button = Widgets.CreateButton(row, text, onClick, opts)
        row.tools[#row.tools + 1] = button
        return button
    end
    row.rename = Tool(L["Rename"], 70, function() View:SetMode("rename", row.data.key) end)
    row.rename:SetPoint("LEFT", row, "LEFT", 22, 0)
    row.copy = Tool(L["Copy"], 60, function() View:SetMode("copy", row.data.key) end,
        { tooltip = L["Gives a line of text to paste in chat or Discord. Paste a list makes a list from one."] })
    row.copy:SetPoint("LEFT", row.rename, "RIGHT", 6, 0)
    row.delete = Tool(L["Delete"], 70, function()
        local key = row.data.key
        if Armed(key) then
            -- The lists after it move up a place, so nothing keeps a key.
            View.armed, View.open, View.step = nil, nil, nil
            Lists():Delete(key)
            View:SetMode(nil)
        else
            Arm(key)
        end
        View:Refresh(true)
    end, { danger = true, tooltip = L["Deletes this list. Click again to be sure."] })
    row.delete:SetPoint("LEFT", row.copy, "RIGHT", 6, 0)
    row.saveQueue = Tool(L["Save as a list"], 110, function()
        local index, why = Lists():SaveQueue()
        if index then
            View.open = index
            View:SetMode("rename", index)
        elseif why then
            ns.Print(why)
        end
        View:Refresh(true)
    end, { tooltip = L["Keeps a copy of what the queue needs now, as a list you can change."] })
    row.saveQueue:SetPoint("LEFT", row, "LEFT", 22, 0)
end

local function HideAll(row)
    for _, part in ipairs({ row.chevron, row.icon, row.listSearch, row.total, row.remove,
        row.itemSearch, row.want, row.name, row.sub }) do
        part:Hide()
    end
    for _, tool in ipairs(row.tools) do tool:Hide() end
end

local function Money(copper)
    return Util.FormatMoney(copper or 0, { short = true })
end

local function UpdateRow(row, entry)
    HideAll(row)

    if entry.kind == "list" then
        row.chevron:SetText(entry.open and "-" or "+")
        row.chevron:Show()
        row.name:ClearAllPoints()
        row.name:SetPoint("LEFT", 20, 0)
        row.name:SetPoint("RIGHT", row.total, "LEFT", -6, 0)
        local count = entry.count == 1 and L["1 item"] or L.Format("%d items", entry.count)
        row.name:SetText(("|c%s%s|r  |c%s%s|r"):format(ns.COLORS.accent, entry.name, ns.COLORS.muted, count))
        row.name:Show()
        row.total:SetText(entry.total > 0 and Money(entry.total) or "")
        row.total:Show()
        row.listSearch:SetText(View:SearchLabel(entry))
        row.listSearch:SetEnabledState(#entry.searchable > 0)
        row.listSearch:Show()
        return
    end

    if entry.kind == "tools" then
        if entry.auto then
            row.saveQueue:Show()
        else
            row.rename:Show()
            row.copy:Show()
            row.delete:SetText(Armed(entry.key) and L["Sure?"] or L["Delete"])
            row.delete:SetConfirming(Armed(entry.key))
            row.delete:Show()
        end
        return
    end

    local line = entry.line
    Theme.SetItemIcon(row.icon, line.itemID)
    row.icon:Show()
    row.name:ClearAllPoints()
    row.name:SetPoint("TOPLEFT", 40, -3)
    row.name:SetPoint("RIGHT", row.want, "LEFT", -6, 0)
    row.name:SetText(Util.GetItemLabel(line.itemID))
    row.name:Show()

    local have = line.need > 0 and L.Format("You have %d, need %d", line.have, line.need)
        or L.Format("You have %d", line.have)
    local price
    if line.fromVendor and line.unit then
        price = L.Format("|c%svendor|r %s each", ns.COLORS.profit, Money(line.unit))
    elseif line.unit then
        price = L.Format("%s each", Money(line.unit))
    else
        price = L["no price"]
    end
    row.sub:SetText(have .. "  ·  " .. price)
    row.sub:SetTextColor(Theme.Unpack(line.need > 0 and "muted" or "profit"))
    row.sub:Show()

    if entry.auto then
        -- The queue's own list: how many it needs, nothing to change here.
        row.want:SetValue(line.want, true)
        row.want:Hide()
    else
        if not (row.want.editBox.HasFocus and row.want.editBox:HasFocus()) then
            row.want:SetValue(line.want, true)
        end
        row.want:Show()
        row.remove:Show()
    end
    row.itemSearch:SetShown(Lists().CanSearch(line))
    if entry.auto then
        row.itemSearch:ClearAllPoints()
        row.itemSearch:SetPoint("RIGHT", row, "RIGHT", -6, 0)
    else
        row.itemSearch:ClearAllPoints()
        row.itemSearch:SetPoint("RIGHT", row.remove, "LEFT", -4, 0)
    end
end

local function ShowTooltip(row, entry)
    if entry.kind == "item" then
        Widgets.ShowItemTooltip(row, "ANCHOR_LEFT", entry.itemID)
    elseif entry.kind == "list" then
        GameTooltip:SetOwner(row, "ANCHOR_LEFT")
        GameTooltip:SetText(entry.name)
        if entry.auto then
            GameTooltip:AddLine(L["What your craft queue still needs. It changes with the queue."], 1, 1, 1, true)
        end
        if entry.unpriced > 0 then
            GameTooltip:AddLine(L.Format("%d without a price yet.", entry.unpriced), 0.6, 0.6, 0.6, true)
        end
        GameTooltip:AddLine(entry.open and L["Click to close it."] or L["Click to open it."], 0.78, 0.64, 0.30)
        GameTooltip:Show()
    end
end

--------------------------------------------------------------------------------
-- The foot box
--------------------------------------------------------------------------------

local HINTS = {
    add = L["Add an item: type its name or Shift-click it"],
    new = L["Name the new list"],
    rename = L["A new name for the list"],
    copy = L["Press Ctrl+C to copy, then Escape"],
    paste = L["Paste a copied list here"],
}

--- Set what the foot box does. key is the list it acts on, where it needs one.
function View:SetMode(mode, key)
    self.mode, self.modeKey = mode, key
    local box = self.box
    if not box then return end
    box.edit:SetText("")
    if mode == "rename" then
        local list = Lists():Get(key)
        box.edit:SetText(list and list.name or "")
    elseif mode == "copy" then
        box.edit:SetText(Lists():Export(key) or "")
    end
    self:UpdateFoot()
    if mode and mode ~= "add" then
        box.edit:SetFocus()
        if mode == "copy" or mode == "rename" then box.edit:HighlightText() end
    end
end

--- The mode the box falls back to: adding to the open list, or nothing.
function View:RestingMode()
    if type(self.open) == "number" and Lists():Get(self.open) then return "add", self.open end
    return nil
end

function View:UpdateFoot()
    local box = self.box
    if not box then return end
    local mode = self.mode
    box:SetShown(mode ~= nil)
    box.hint:SetText(mode and HINTS[mode] or "")
    box.hint:SetShown(mode ~= nil and (box.edit:GetText() or "") == "")
    self.save:SetShown(mode ~= nil and mode ~= "copy")
    self.save:SetText(mode == "add" and L["Add"] or L["Save"])
    self.note:SetShown(mode == nil)
    self.note:SetText(#Lists():Readable() == 0
        and L["Make a list, then add items to it."]
        or L["Click a list to open it."])
end

--- An item from the text typed, with how many: "Peacebloom 40", "40
--- Peacebloom", a link or an item ID.
function View.ParseAdd(text)
    if type(text) ~= "string" then return nil end
    text = text:gsub("^%s+", ""):gsub("%s+$", "")
    local id = Lists().ResolveItem(text)
    if id then return id, 1 end
    local name, count = text:match("^(.-)%s+[xX%*]?(%d+)$")
    if name then
        id = Lists().ResolveItem(name)
        if id then return id, tonumber(count) end
    end
    count, name = text:match("^(%d+)%s*[xX%*]?%s+(.+)$")
    if name then
        id = Lists().ResolveItem(name)
        if id then return id, tonumber(count) end
    end
    return nil
end

--- Enter in the foot box: do what it is there for.
function View:Submit()
    local text = self.box and self.box.edit:GetText() or ""
    local mode, key = self.mode, self.modeKey
    local ok, why

    if mode == "add" then
        local id, count = View.ParseAdd(text)
        if not id then
            ns.Print(L["The game does not know that item. Shift-click it, or hover over it once and try again."])
            return
        end
        ok, why = Lists():Add(key, id, count)
        if ok then self.box.edit:SetText("") end
    elseif mode == "new" then
        local index
        index, why = Lists():Make(text)
        ok = index ~= nil
        if ok then
            self.open = index
            self:SetMode("add", index)
            self.box.edit:SetFocus()
        end
    elseif mode == "rename" then
        ok, why = Lists():Rename(key, text)
        if ok then self:SetMode(self:RestingMode()) end
    elseif mode == "paste" then
        local index
        index, why = Lists():Import(text)
        ok = index ~= nil
        if ok then
            self.open = index
            self:SetMode("add", index)
        end
    end

    if not ok and why then ns.Print(why) end
    self:Refresh(true)
end

--- A Shift-click on an item while the box is adding to a list puts the item
--- on it. Called from the game's own modified click and from every item the
--- addon shows (Widgets.ItemShiftClick).
-- @return true when the item was taken
function View:TakeItem(itemID)
    if self.mode ~= "add" or not self.box or not self.box:IsShown() then return false end
    local edit = self.box.edit
    if not (edit.HasFocus and edit:HasFocus()) then return false end
    itemID = tonumber(itemID)
    if not itemID then return false end
    local ok, why = Lists():Add(self.modeKey, itemID, 1)
    if not ok and why then ns.Print(why) end
    self:Refresh(true)
    return true
end

function View:HookShiftClick()
    if self.hooked or type(hooksecurefunc) ~= "function" or type(_G.HandleModifiedItemClick) ~= "function" then
        return
    end
    self.hooked = true
    hooksecurefunc("HandleModifiedItemClick", function(link)
        if not (IsShiftKeyDown and IsShiftKeyDown()) then return end
        local ok, id = pcall(function() return tonumber(link:match("item:(%d+)")) end)
        if ok and id then View:TakeItem(id) end
    end)
end

--------------------------------------------------------------------------------
-- Building and drawing
--------------------------------------------------------------------------------

--- Make the view inside the drawer. topAnchor is the frame the list hangs
--- under; the foot sits in the drawer's foot.
function View:Build(body, frame, topAnchor, opts)
    if self.list then return end
    opts = opts or {}

    local list = Widgets.CreateScrollList(body, {
        rowHeight = ROW_HEIGHT,
        createRow = CreateRow,
        updateRow = UpdateRow,
        onEnter = ShowTooltip,
        onLeave = function() GameTooltip:Hide() end,
        isSelected = function(entry) return entry.kind == "list" and entry.open end,
        onClick = function(entry)
            if entry.kind ~= "list" then return end
            View.open = (View.open ~= entry.key) and entry.key or nil
            View.armed = nil
            View:SetMode(View:RestingMode())
            View:Refresh(true)
        end,
    })
    list:SetPoint("TOPLEFT", topAnchor, "BOTTOMLEFT", 0, -4)
    list:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -14, opts.bottom or 49)
    list:Hide()
    self.list = list

    local pad = opts.edge or 11
    local footMiddle = pad + (opts.footHeight or 34) / 2

    local newList = Widgets.CreateButton(body, L["New list"], function()
        View:SetMode("new")
    end, { width = 86, height = 22, primary = true })
    newList:SetPoint("RIGHT", frame, "BOTTOMRIGHT", -(pad + 6), footMiddle)
    self.newList = newList

    local save = Widgets.CreateButton(body, L["Save"], function() View:Submit() end, { width = 50, height = 22 })
    save:SetPoint("RIGHT", newList, "LEFT", -6, 0)
    self.save = save

    local box = Theme.CreatePanel(body, "row")
    box:SetHeight(22)
    box:SetPoint("LEFT", frame, "BOTTOMLEFT", pad + 8, footMiddle)
    box:SetPoint("RIGHT", save, "LEFT", -6, 0)
    if Theme.Recess then Theme.Recess(box) end
    local edit = CreateFrame("EditBox", nil, box)
    edit:SetPoint("TOPLEFT", 6, 0)
    edit:SetPoint("BOTTOMRIGHT", -6, 0)
    edit:SetAutoFocus(false)
    edit:SetFont(Theme.FONT, Theme.sizes.small, "")
    edit:SetTextColor(Theme.Unpack("text"))
    edit:SetMaxLetters(4000)
    local hint = Theme.CreateLabel(box, "small", "dim")
    hint:SetPoint("LEFT", 6, 0)
    hint:SetPoint("RIGHT", -6, 0)
    hint:SetWordWrap(false)
    box.edit, box.hint = edit, hint
    edit:SetScript("OnTextChanged", function(self)
        hint:SetShown(View.mode ~= nil and (self:GetText() or "") == "")
    end)
    edit:SetScript("OnEnterPressed", function() View:Submit() end)
    edit:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
        View:SetMode(View:RestingMode())
    end)
    box:Hide()
    self.box = box

    local note = Theme.CreateLabel(body, "tiny", "muted")
    note:SetPoint("LEFT", frame, "BOTTOMLEFT", pad + 8, footMiddle)
    note:SetPoint("RIGHT", save, "LEFT", -6, 0)
    note:SetWordWrap(true)
    self.note = note

    local paste = Widgets.CreateButton(body, L["Paste a list"], function()
        View:SetMode("paste")
    end, { width = 90, height = 20, tooltip = L["Makes a new list from a line someone copied with Copy."] })
    self.paste = paste

    self.parts = { list, newList, save, box, note, paste }
    self:HookShiftClick()
    self:SetShown(false)
end

function View:SetShown(on)
    for _, part in ipairs(self.parts or {}) do
        if part == self.box or part == self.save or part == self.note then
            if not on then part:Hide() end
        else
            part:SetShown(on)
        end
    end
    self.shown = on
    if on then self:UpdateFoot() end
end

--- Draw the rows again: at once when forced or a list changed, otherwise at
--- most every REFRESH_SECONDS (the drawer redraws every second).
function View:Refresh(force)
    if not (self.list and self.shown) then return end
    local now = GetTime()
    local version = Lists().version
    if not force and self.drawnVersion == version and self.drawnAt and now - self.drawnAt < REFRESH_SECONDS then
        return
    end
    -- Never under a box being typed in: rows are reused, and the number would
    -- land on another item.
    for _, row in ipairs(self.list.rows or {}) do
        if row:IsShown() and row.want and row.want:IsShown()
            and row.want.editBox.HasFocus and row.want.editBox:HasFocus() then
            return
        end
    end
    self.drawnVersion, self.drawnAt = version, now

    if type(self.open) == "number" and not Lists():Get(self.open) then self.open = nil end
    local entries = self:Entries()
    self.entries = entries
    self.list:SetData(entries)
    self:UpdateFoot()
end

--- What the drawer's summary line says on Lists.
function View:Summary()
    local count = #Lists():Readable()
    if count == 0 then return L["Your own lists of things to buy."] end
    return count == 1 and L["1 list of your own"] or L.Format("%d lists of your own", count)
end
