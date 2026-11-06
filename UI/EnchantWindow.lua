-- Blackthornes -- UI/EnchantWindow.lua
-- The Enchant window (Trent said build it, 2026-11-05, from the mockup in
-- the project files, previews/tradeskills-enchant-picker/): pick an enchant,
-- pick an item, click Enchant. Our own frame, set beside the craft pane (or
-- the game's Enchanting window when the pane is shut) by anchor only; the
-- game's window is never hidden, shown or moved, and the game's own
-- "replace this enchant?" and bind boxes are never clicked.
--
-- What it reads and casts is Logic/EnchantWindow.lua. Off by default
-- (`enchantWindow`); its place is `enchantWindowLeft`/`enchantWindowTop`
-- once dragged, its size `enchantWindowScale` (account wide, never rename
-- them).
--
-- One hardware click a cast. When the client wants the item picked after
-- the cast starts, the same button turns into Put It On, a secure button
-- whose macro is `/use <slot>` or `/use <bag> <slot>`, set only out of a
-- fight. When neither works, the item glows for the player to click.

local addonName, ns = ...
local L = ns.L or setmetatable({ Format = string.format }, { __index = function(_, key) return key end })

local EnchantWindowUI = ns.NewModule("EnchantWindowUI")

local Theme = ns.Theme
local Widgets = ns.Widgets

local WIDTH = 300
local PAD = 16
local TOP = 34
local SLOT_HEIGHT = 52
local SLOT_ICON = 40
local MATERIAL_ROW = 24
local BUTTON_HEIGHT = 40
local FOOT = 30
local LIST_ROW = 24
local LIST_HEADING = 20
-- The picker shows at most this many rows; the wheel moves through the rest.
EnchantWindowUI.LIST_MOST = 12
EnchantWindowUI.SETTLE = 0.2
EnchantWindowUI.GLOW_LOOK = 0.25
EnchantWindowUI.SCALE_MIN, EnchantWindowUI.SCALE_MAX = 0.5, 1.5

local STRATA_ABOVE = {
    BACKGROUND = "LOW", LOW = "MEDIUM", MEDIUM = "HIGH", HIGH = "DIALOG",
    DIALOG = "FULLSCREEN", FULLSCREEN = "FULLSCREEN_DIALOG",
    FULLSCREEN_DIALOG = "TOOLTIP", TOOLTIP = "TOOLTIP",
}

-- The character sheet's buttons by equip slot, read only, for the glow.
EnchantWindowUI.SHEET_SLOTS = {
    [1] = "CharacterHeadSlot", [2] = "CharacterNeckSlot", [3] = "CharacterShoulderSlot",
    [5] = "CharacterChestSlot", [6] = "CharacterWaistSlot", [7] = "CharacterLegsSlot",
    [8] = "CharacterFeetSlot", [9] = "CharacterWristSlot", [10] = "CharacterHandsSlot",
    [11] = "CharacterFinger0Slot", [12] = "CharacterFinger1Slot",
    [13] = "CharacterTrinket0Slot", [14] = "CharacterTrinket1Slot",
    [15] = "CharacterBackSlot", [16] = "CharacterMainHandSlot",
    [17] = "CharacterSecondaryHandSlot",
}

local function InCombat()
    return type(InCombatLockdown) == "function" and InCombatLockdown() and true or false
end

local function Logic() return ns.EnchantWindow end

local function ItemIDOf(link)
    return type(link) == "string" and tonumber(link:match("item:(%d+)")) or nil
end

local function NameOf(link)
    return type(link) == "string" and link:match("|h%[(.-)%]|h") or link
end

--------------------------------------------------------------------------------
-- Building
--------------------------------------------------------------------------------

local function Heading(parent, text)
    local label = Theme.CreateLabel(parent, "normal", "accent")
    label:SetText(text)
    return label
end

function EnchantWindowUI:Build()
    if self.frame then return self.frame end

    local frame = CreateFrame("Frame", "BlackthornesTSEnchantWindow", UIParent)
    frame:SetSize(WIDTH, 400)
    frame:SetFrameStrata(ns.CraftPanel and ns.CraftPanel.STRATA or "HIGH")
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    -- On top of the craft pane and its queued crafts, which share its
    -- strata: a click brings it to the front (Trent, 2026-11-05: it opened
    -- behind the queued crafts and was hard to move).
    if frame.SetToplevel then frame:SetToplevel(true) end
    frame:RegisterForDrag("LeftButton")
    frame:Hide()
    self.frame = frame

    Theme.Fill(frame, "window")
    if ns.Titanforged then
        self.trim = ns.Titanforged:Dress(frame, {
            title = L["Enchant"],
            close = function() EnchantWindowUI:Close() end,
        })
        if ns.FoldWindow then
            ns.FoldWindow:Add(frame, { onToggle = function(folded)
                if folded then EnchantWindowUI:HideList() end
            end })
        end
    else
        Theme.Border(frame, "borderLit")
    end

    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        EnchantWindowUI:SavePlace()
    end)
    frame:SetScript("OnHide", function()
        EnchantWindowUI:HideList()
        EnchantWindowUI:Disarm()
        EnchantWindowUI:HideGlow()
    end)

    -- Enchant:
    self.enchantLabel = Heading(frame, L["Enchant:"])
    self.enchantLabel:SetPoint("TOPLEFT", PAD, -TOP)
    self.dropdown = Widgets.CreateDropdown(frame, {}, function(value)
        EnchantWindowUI:PickEnchant(value)
    end, { width = WIDTH - PAD * 2 })
    self.dropdown:SetPoint("TOPLEFT", self.enchantLabel, "BOTTOMLEFT", 0, -6)

    -- Item:
    self.itemLabel = Heading(frame, L["Item:"])
    self.itemLabel:SetPoint("TOPLEFT", self.dropdown, "BOTTOMLEFT", 0, -12)
    self.chip = CreateFrame("Frame", nil, frame)
    self.chip:SetHeight(18)
    Theme.Fill(self.chip, "glassAlt")
    Theme.Border(self.chip, "profit", 0.8)
    self.chip.text = Theme.CreateLabel(self.chip, "small", "profit", "CENTER")
    self.chip.text:SetPoint("CENTER")
    self.chip:SetPoint("RIGHT", frame, "RIGHT", -PAD, 0)
    self.chip:SetPoint("BOTTOM", self.itemLabel, "BOTTOM", 0, -3)
    self.chip:Hide()

    self:BuildSlot(frame)

    -- Replaces:
    self.replacesLabel = Theme.CreateLabel(frame, "normal", "accent")
    self.replacesLabel:SetText(L["Replaces:"])
    self.replacesLabel:SetPoint("TOPLEFT", self.slot, "BOTTOMLEFT", 0, -8)
    self.replaces = Theme.CreateLabel(frame, "normal", "muted", "RIGHT")
    self.replaces:SetPoint("TOPRIGHT", self.slot, "BOTTOMRIGHT", 0, -8)
    self.replaces:SetPoint("LEFT", self.replacesLabel, "RIGHT", 8, 0)
    self.replaces:SetWordWrap(true)

    -- Materials:
    self.materialsLabel = Heading(frame, L["Materials:"])
    self.materialRows = {}

    -- Cost:
    self.costLabel = Theme.CreateLabel(frame, "normal", "accent")
    self.costLabel:SetText(L["Cost:"])
    self.cost = Theme.CreateLabel(frame, "normal", "text", "RIGHT")
    self.cost:SetWidth(WIDTH / 2)

    -- Enchant
    self.button = Widgets.CreateButton(frame, L["Enchant"], function()
        EnchantWindowUI:EnchantClicked()
    end, { primary = true, width = WIDTH - PAD * 2, height = BUTTON_HEIGHT, fontSize = "large" })
    self.buttonIcon = Theme.CreateItemIcon(self.button, 26)
    self.buttonIcon:SetPoint("LEFT", 10, 0)
    self.button.label:ClearAllPoints()
    self.button.label:SetPoint("LEFT", 46, 0)
    self.button.label:SetPoint("RIGHT", -10, 0)
    self.button.label:SetJustifyH("LEFT")

    -- Footer: a count on the left, the version on the right.
    self.footLeft = Theme.CreateLabel(frame, "small", "dim")
    self.footLeft:SetPoint("BOTTOMLEFT", PAD, 12)
    self.footRight = Theme.CreateLabel(frame, "small", "dim", "RIGHT")
    self.footRight:SetPoint("BOTTOMRIGHT", -PAD, 12)
    self.footRight:SetText(ns.VersionLabel and ns.VersionLabel() or "")

    self:BuildGrip(frame)
    self:ApplyScale(ns.Config:Get("enchantWindowScale"))
    return frame
end

--- The item slot: click for the list, or drop an item on it.
function EnchantWindowUI:BuildSlot(frame)
    local slot = CreateFrame("Button", nil, frame)
    slot:SetHeight(SLOT_HEIGHT)
    slot:SetPoint("TOPLEFT", self.itemLabel, "BOTTOMLEFT", 0, -6)
    slot:SetPoint("RIGHT", frame, "RIGHT", -PAD, 0)
    slot:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    slot.fill = slot:CreateTexture(nil, "BACKGROUND")
    slot.fill:SetAllPoints()
    slot.edge = slot:CreateTexture(nil, "BORDER")
    slot.edge:SetPoint("TOPLEFT")
    slot.edge:SetPoint("BOTTOMLEFT")
    slot.edge:SetWidth(3)
    slot.edge:SetColorTexture(Theme.Unpack("accentHi"))

    slot.well = CreateFrame("Frame", nil, slot)
    slot.well:SetSize(SLOT_ICON + 4, SLOT_ICON + 4)
    slot.well:SetPoint("LEFT", 12, 0)
    Theme.Fill(slot.well, "glassAlt")
    Theme.Border(slot.well, "accent")
    slot.icon = Theme.CreateItemIcon(slot.well, SLOT_ICON)
    slot.icon:SetPoint("CENTER")

    slot.name = Theme.CreateLabel(slot, "normal", "text")
    slot.name:SetPoint("LEFT", slot.well, "RIGHT", 12, 0)
    slot.name:SetPoint("RIGHT", -10, 0)
    slot.name:SetWordWrap(true)

    slot:SetScript("OnClick", function() EnchantWindowUI:ToggleList() end)
    slot:SetScript("OnReceiveDrag", function() EnchantWindowUI:Dropped() end)
    slot:SetScript("OnMouseUp", function(_, mouse)
        if mouse == "LeftButton" and type(GetCursorInfo) == "function" and GetCursorInfo() == "item" then
            EnchantWindowUI:Dropped()
        end
    end)
    slot:SetScript("OnEnter", function(self)
        self.fill:SetColorTexture(Theme.Unpack("glassHover", 0.95))
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        local entry = EnchantWindowUI.item
        if entry and entry.link then
            pcall(GameTooltip.SetHyperlink, GameTooltip, entry.link)
            GameTooltip:AddLine(L["Click to pick an item. You can also drop one here."], 0.6, 0.6, 0.6, true)
        else
            GameTooltip:SetText(L["Click to pick an item. You can also drop one here."], 1, 1, 1, 1, true)
        end
        GameTooltip:Show()
    end)
    slot:SetScript("OnLeave", function(self)
        EnchantWindowUI:PaintSlot()
        GameTooltip:Hide()
    end)

    self.slot = slot
end

--- The house size grip below the bottom right corner: drag to change the
--- window's size, right-click for the normal size.
function EnchantWindowUI:BuildGrip(frame)
    local grip = Theme.CreatePanel(frame, "panel", "borderLit")
    grip:SetSize(16, 16)
    grip:SetPoint("TOPRIGHT", frame, "BOTTOMRIGHT", -6, -3)
    grip:SetFrameLevel((frame:GetFrameLevel() or 0) + 20)
    grip:EnableMouse(true)
    for row = 0, 2 do
        for column = 2 - row, 2 do
            local dot = grip:CreateTexture(nil, "ARTWORK")
            dot:SetSize(3, 3)
            dot:SetPoint("BOTTOMRIGHT", grip, "BOTTOMRIGHT", -3 - (2 - column) * 5, 3 + (2 - row) * 5)
            dot:SetColorTexture(Theme.Unpack("accent"))
        end
    end
    grip:SetScript("OnMouseDown", function(self, mouse)
        if mouse == "RightButton" then
            EnchantWindowUI:SetScale(1)
            return
        end
        local x = GetCursorPosition()
        self.startX, self.startScale = x, frame:GetScale() or 1
        self:SetScript("OnUpdate", function(grip)
            local now = GetCursorPosition()
            local uiScale = UIParent:GetEffectiveScale()
            if not now or not uiScale or uiScale <= 0 then return end
            local grown = (now - grip.startX) / uiScale / WIDTH
            EnchantWindowUI:ApplyScale(grip.startScale + grown, true)
        end)
    end)
    grip:SetScript("OnMouseUp", function(self)
        self:SetScript("OnUpdate", nil)
        if self.startX then
            self.startX = nil
            EnchantWindowUI:SetScale(frame:GetScale())
        end
    end)
    self.grip = grip
end

function EnchantWindowUI.ClampScale(value)
    value = tonumber(value) or 1
    return math.max(EnchantWindowUI.SCALE_MIN, math.min(EnchantWindowUI.SCALE_MAX, value))
end

--- Scale from the top left corner, so the window grows down and right.
function EnchantWindowUI:ApplyScale(value, keepCorner)
    local frame = self.frame
    if not frame then return end
    local scale = EnchantWindowUI.ClampScale(value)
    local left, top = frame:GetLeft(), frame:GetTop()
    local old = frame:GetScale() or 1
    frame:SetScale(scale)
    if keepCorner and left and top then
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left * old / scale, top * old / scale)
    end
end

function EnchantWindowUI:SetScale(value)
    local scale = EnchantWindowUI.ClampScale(value)
    ns.Config:Set("enchantWindowScale", scale ~= 1 and scale or nil)
    self:ApplyScale(scale, true)
    if ns.Config:Get("enchantWindowLeft") then self:SavePlace() end
end

--------------------------------------------------------------------------------
-- Place
--------------------------------------------------------------------------------

function EnchantWindowUI:SavePlace()
    local frame = self.frame
    if not frame then return end
    local left, top = frame:GetLeft(), frame:GetTop()
    if not left or not top then return end
    local scale = frame:GetScale() or 1
    ns.Config:Set("enchantWindowLeft", left * scale)
    ns.Config:Set("enchantWindowTop", top * scale)
end

--- What to sit beside: the queued crafts when they show (they hang off the
--- craft pane's right edge), else the craft pane, else nil.
function EnchantWindowUI.Beside(panel)
    if not panel then return nil end
    local queued, pane = panel.queuedFrame, panel.frame
    if queued and queued:IsShown() then return queued end
    if pane and pane:IsShown() then return pane end
    return nil
end

--- Above the craft pane and the queued crafts, so neither covers it.
function EnchantWindowUI:LiftAbove()
    local frame = self.frame
    local panel = ns.CraftPanel
    if not frame or not panel then return end
    local top = 0
    for _, other in ipairs({ panel.frame, panel.queuedFrame }) do
        if other and other.GetFrameLevel then top = math.max(top, other:GetFrameLevel() or 0) end
    end
    if (frame:GetFrameLevel() or 0) <= top + 10 then pcall(frame.SetFrameLevel, frame, top + 20) end
    if frame.Raise then pcall(frame.Raise, frame) end
end

--- Placed again when the queued crafts come or go, unless dragged.
function EnchantWindowUI:WatchQueued()
    local queued = ns.CraftPanel and ns.CraftPanel.queuedFrame
    if not queued or self.watchingQueued or type(queued.HookScript) ~= "function" then return end
    self.watchingQueued = true
    local again = function()
        local frame = EnchantWindowUI.frame
        if frame and frame:IsShown() and not ns.Config:Get("enchantWindowLeft") then
            EnchantWindowUI:Place()
            EnchantWindowUI:LiftAbove()
        end
    end
    pcall(queued.HookScript, queued, "OnShow", again)
    pcall(queued.HookScript, queued, "OnHide", again)
end

--- A dragged place wins; else beside the craft pane, else beside the
--- game's window, by anchor only.
function EnchantWindowUI:Place()
    local frame = self.frame
    if not frame then return end
    frame:ClearAllPoints()
    local scale = frame:GetScale() or 1
    local left, top = tonumber(ns.Config:Get("enchantWindowLeft")), tonumber(ns.Config:Get("enchantWindowTop"))
    if left and top then
        frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left / scale, top / scale)
        return
    end
    local pane = EnchantWindowUI.Beside(ns.CraftPanel)
    local gap = ns.CraftPanel and ns.CraftPanel.PANEL_GAP or 6
    if pane then
        frame:SetPoint("TOPLEFT", pane, "TOPRIGHT", gap, 0)
        return
    end
    local game = ns.CraftPanel and ns.CraftPanel:FindTradeSkillFrame()
    if game then
        local overhang = ns.CraftPanel:RightOverhang(game) or 0
        frame:SetPoint("TOPLEFT", game, "TOPRIGHT", overhang + gap, 0)
        return
    end
    frame:SetPoint("RIGHT", UIParent, "RIGHT", -60, 0)
end

--- Under the character sheet while it shows, as the craft pane is.
function EnchantWindowUI:FitStrata()
    local frame, pane = self.frame, ns.CraftPanel
    if not frame or not pane then return end
    local want = pane.StrataFor(pane:SheetShown())
    if frame:GetFrameStrata() ~= want then pcall(frame.SetFrameStrata, frame, want) end
    if self.list then pcall(self.list.SetFrameStrata, self.list, STRATA_ABOVE[want] or "DIALOG") end
    self:PlaceOverlay()
end

function EnchantWindowUI:WatchSheets()
    self.watched = self.watched or {}
    for _, name in ipairs(ns.CraftPanel and ns.CraftPanel.SHEETS or {}) do
        local sheet = _G[name]
        if not self.watched[name] and type(sheet) == "table" and type(sheet.HookScript) == "function" then
            self.watched[name] = true
            local refit = function() EnchantWindowUI:FitStrata() end
            pcall(sheet.HookScript, sheet, "OnShow", refit)
            pcall(sheet.HookScript, sheet, "OnHide", refit)
        end
    end
end

--------------------------------------------------------------------------------
-- Showing
--------------------------------------------------------------------------------

--- Should the window be up now?
function EnchantWindowUI:Wanted()
    local logic = Logic()
    return logic and logic:IsOn() and self.open and not self.closed and logic:EnchantingOpen() and true or false
end

--- Show, hide or redraw for how things stand.
function EnchantWindowUI:Update()
    if not self:Wanted() then
        if self.frame then self.frame:Hide() end
        return
    end
    local frame = self:Build()
    if not frame:IsShown() then
        self:Place()
        self:WatchSheets()
        frame:Show()
        self:LiftAbove()
        if ns.Titanforged then ns.Titanforged:Opened(frame) end
        self:LoadEnchants()
    end
    self:WatchQueued()
    self:FitStrata()
    self:Refresh()
end

function EnchantWindowUI:Close()
    self.closed = true
    if self.frame then self.frame:Hide() end
end

--- Read the enchants, then start on the game's pick or the last one used.
function EnchantWindowUI:LoadEnchants()
    local logic = Logic()
    self.loading = true
    logic:ReadEnchants(function(list)
        EnchantWindowUI.loading = nil
        local options = {}
        for _, enchant in ipairs(list) do
            options[#options + 1] = { text = enchant.shown or enchant.name, value = enchant.recipeID }
        end
        EnchantWindowUI.dropdown:SetOptions(options)
        local start = logic:StartPick()
        EnchantWindowUI.recipeID = start
        EnchantWindowUI.dropdown:SetValue(start)
        EnchantWindowUI.item = nil
        EnchantWindowUI.itemsKey = nil
        EnchantWindowUI:Refresh(true)
    end)
end

function EnchantWindowUI:PickEnchant(recipeID)
    if recipeID == self.recipeID then return end
    self.recipeID = recipeID
    self.item = nil
    self.itemsKey = nil
    self:HideList()
    self:Refresh(true)
end

--- The items this enchant fits, read again only when the bags, the gear
--- or the enchant moved.
function EnchantWindowUI:ReadItems(fresh)
    local key = tostring(self.recipeID) .. ":" .. tostring(self.bagsVersion or 0)
    if not fresh and key == self.itemsKey and self.items then return self.items end
    self.itemsKey = key
    self.items = self.recipeID and Logic():Items(self.recipeID) or {}

    local keep = self.item and Logic().Key(self.item)
    local start = Logic().StartItem(self.items, keep)
    if not start and keep then self.item = nil end
    self.item = start or self.item
    if self.item and not Logic():StillThere(self.item) then self.item = nil end
    return self.items
end

--------------------------------------------------------------------------------
-- Drawing
--------------------------------------------------------------------------------

function EnchantWindowUI:PaintSlot()
    local slot = self.slot
    if not slot then return end
    local picked = self.item ~= nil
    slot.fill:SetColorTexture(Theme.Unpack(picked and "glassActive" or "glassAlt", 0.95))
    slot.edge:SetShown(picked)
end

function EnchantWindowUI:Refresh(fresh)
    local frame = self.frame
    if not frame or not frame:IsShown() then return end
    local logic = Logic()
    local enchant = self.recipeID and logic:Find(self.recipeID)
    local items = enchant and self:ReadItems(fresh) or {}
    local entry = self.item

    -- The slot.
    local slot = self.slot
    if entry then
        Theme.SetItemIcon(slot.icon, ItemIDOf(entry.link), entry.link)
        slot.name:SetText(NameOf(entry.link) or "")
        Theme.SetItemNameColor(slot.name, ItemIDOf(entry.link))
    else
        Theme.SetItemIcon(slot.icon, nil)
        if enchant and #items == 0 and not self.loading then
            slot.name:SetText(L["Nothing you have can take this enchant."])
        else
            slot.name:SetText(L["Pick an Item"])
        end
        slot.name:SetTextColor(Theme.Unpack("muted"))
    end
    self:PaintSlot()

    -- The chip: Equipment's gain for the piece picked.
    if entry and (entry.gain or 0) > 0 then
        self.chip.text:SetText(L.Format(L["+%d%% for you"], entry.gain))
        self.chip:SetWidth((self.chip.text:GetStringWidth() or 60) + 16)
        self.chip:Show()
    else
        self.chip:Hide()
    end

    -- Replaces:
    if entry and entry.current then
        self.replaces:SetText(entry.current)
        self.replaces:SetTextColor(Theme.Unpack("warn"))
    else
        self.replaces:SetText(L["Nothing"])
        self.replaces:SetTextColor(Theme.Unpack("muted"))
    end

    -- Materials:
    local y = self:LayMaterials(enchant)

    -- Cost:
    local _, ready, _, cost = logic:MaterialState(enchant)
    local showCost = enchant and cost and cost > 0
    self.costLabel:ClearAllPoints()
    self.cost:ClearAllPoints()
    if showCost then
        self.costLabel:SetPoint("TOPLEFT", self.materialsLabel, "BOTTOMLEFT", 0, -y - 6)
        self.cost:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PAD, 0)
        self.cost:SetPoint("TOP", self.costLabel, "TOP", 0, 0)
        Theme.SetMoneyText(self.cost, cost)
        self.costLabel:Show()
        self.cost:Show()
    else
        self.costLabel:Hide()
        self.cost:Hide()
    end

    -- Enchant, or Put It On.
    self.button:ClearAllPoints()
    local above = showCost and self.costLabel or self.materialsLabel
    local gap = showCost and -12 or (-y - 12)
    self.button:SetPoint("TOPLEFT", above, "BOTTOMLEFT", 0, gap)
    self:PaintButton(enchant, entry)

    -- Footer.
    if not entry and #items > 0 then
        self.footLeft:SetText(#items == 1 and L["1 item fits"] or L.Format(L["%d items fit"], #items))
    elseif enchant and ready and ready > 0 and ready < math.huge then
        self.footLeft:SetText(ready == 1 and L["1 enchant ready"] or L.Format(L["%d enchants ready"], ready))
    else
        self.footLeft:SetText("")
    end

    -- Height: everything laid out, then the foot.
    local top, bottom = frame:GetTop(), self.button:GetBottom()
    if top and bottom then
        frame:SetHeight(math.max(260, (top - bottom) + FOOT))
    else
        frame:SetHeight(TOP + 6 + 22 + 12 + 20 + SLOT_HEIGHT + 30 + 20 + y + 30 + BUTTON_HEIGHT + FOOT)
    end

    if self.list and self.list:IsShown() then self:DrawList() end
end

--- The materials, one row each, have/need in green or red. Returns the
--- height they take.
function EnchantWindowUI:LayMaterials(enchant)
    local frame = self.frame
    self.materialsLabel:ClearAllPoints()
    self.materialsLabel:SetPoint("TOPLEFT", self.replacesLabel, "BOTTOMLEFT", 0, -12)
    local rows = Logic():MaterialState(enchant)
    for index, data in ipairs(rows) do
        local row = self.materialRows[index]
        if not row then
            row = CreateFrame("Frame", nil, frame)
            row:SetHeight(MATERIAL_ROW - 2)
            Theme.Fill(row, "glassAlt")
            Theme.Border(row, "border", 0.6)
            row.icon = Theme.CreateItemIcon(row, 18)
            row.icon:SetPoint("LEFT", 3, 0)
            row.name = Theme.CreateLabel(row, "normal", "text")
            row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
            row.count = Theme.CreateLabel(row, "normal", "profit")
            row.count:SetPoint("LEFT", row.name, "RIGHT", 6, 0)
            row:EnableMouse(true)
            row:SetScript("OnEnter", function(self)
                if self.itemID then Widgets.ShowItemOnly(self, self.itemID) end
            end)
            row:SetScript("OnLeave", function() GameTooltip:Hide() end)
            self.materialRows[index] = row
        end
        row.itemID = data.itemID
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", self.materialsLabel, "BOTTOMLEFT", 0, -6 - (index - 1) * MATERIAL_ROW)
        Theme.SetItemIcon(row.icon, data.itemID)
        local name = ns.Util.GetItemName and ns.Util.GetItemName(data.itemID)
        if type(name) ~= "string" then name = NameOf(ns.Util.GetItemLabel(data.itemID)) end
        row.name:SetText(name or "?")
        row.count:SetText(("%d/%d"):format(math.min(data.have, 9999), data.need))
        row.count:SetTextColor(Theme.Unpack(data.short > 0 and "loss" or "profit"))
        local wide = 3 + 18 + 6 + (row.name:GetStringWidth() or 60) + 6 + (row.count:GetStringWidth() or 24) + 10
        row:SetWidth(math.min(WIDTH - PAD * 2, wide))
        row:Show()
    end
    for index = #rows + 1, #self.materialRows do self.materialRows[index]:Hide() end
    return 6 + #rows * MATERIAL_ROW
end

function EnchantWindowUI:PaintButton(enchant, entry)
    local logic = Logic()
    local button = self.button
    Theme.SetItemIcon(self.buttonIcon, entry and ItemIDOf(entry.link), entry and entry.link)

    if logic:PutOnTarget() and logic.pending and logic.pending.way == "two" then
        button:SetText(L["Put It On"])
        button.tooltipText = nil
        button:SetEnabledState(true)
        self:Arm(logic:PutOnTarget())
        return
    end
    self:Disarm()
    button:SetText(L["Enchant"])

    local why = enchant and logic:Blocked(enchant, entry) or (not enchant and L["Pick an item first."]) or nil
    if logic.pending and logic.pending.glow then why = nil end
    button.tooltipText = why
    button:SetEnabledState(why == nil and not (logic.pending and logic.pending.glow))
end

--------------------------------------------------------------------------------
-- The picker list
--------------------------------------------------------------------------------

function EnchantWindowUI:BuildList()
    if self.list then return self.list end
    local list = CreateFrame("Frame", nil, self.frame)
    list:SetPoint("TOPLEFT", self.slot, "BOTTOMLEFT", 0, -2)
    list:SetPoint("TOPRIGHT", self.slot, "BOTTOMRIGHT", 0, -2)
    list:SetFrameStrata(STRATA_ABOVE[self.frame:GetFrameStrata()] or "DIALOG")
    list:EnableMouse(true)
    list:EnableMouseWheel(true)
    Theme.Fill(list, "glassAlt")
    Theme.Border(list, "accent")
    list:SetScript("OnMouseWheel", function(_, delta)
        EnchantWindowUI.listFirst = math.max(1, (EnchantWindowUI.listFirst or 1) - delta)
        EnchantWindowUI:DrawList()
    end)
    list.lines = {}
    list:Hide()
    self.list = list
    return list
end

function EnchantWindowUI:ToggleList()
    if self.list and self.list:IsShown() then
        self:HideList()
        return
    end
    if not self.recipeID then return end
    self:BuildList()
    self.listFirst = 1
    self.list:Show()
    self:DrawList()
end

function EnchantWindowUI:HideList()
    if self.list then self.list:Hide() end
end

local function ListLine(list, index)
    local line = list.lines[index]
    if line then return line end
    line = CreateFrame("Button", nil, list)
    line:SetPoint("LEFT", 2, 0)
    line:SetPoint("RIGHT", -2, 0)
    line.fill = line:CreateTexture(nil, "BACKGROUND")
    line.fill:SetAllPoints()
    line.edge = line:CreateTexture(nil, "BORDER")
    line.edge:SetPoint("TOPLEFT")
    line.edge:SetPoint("BOTTOMLEFT")
    line.edge:SetWidth(3)
    line.edge:SetColorTexture(Theme.Unpack("accentHi"))
    line.rule = line:CreateTexture(nil, "BORDER")
    line.rule:SetPoint("BOTTOMLEFT")
    line.rule:SetPoint("BOTTOMRIGHT")
    line.rule:SetHeight(1)
    line.rule:SetColorTexture(Theme.Unpack("border", 0.6))
    line.icon = Theme.CreateItemIcon(line, 18)
    line.icon:SetPoint("LEFT", 8, 0)
    line.right = Theme.CreateLabel(line, "small", "muted", "RIGHT")
    line.right:SetPoint("RIGHT", -8, 0)
    line.name = Theme.CreateLabel(line, "normal", "text")
    line.name:SetPoint("LEFT", line.icon, "RIGHT", 8, 0)
    line.name:SetPoint("RIGHT", line.right, "LEFT", -6, 0)
    line:SetScript("OnEnter", function(self)
        if not self.entry then return end
        self.fill:SetColorTexture(Theme.Unpack("glassHover", 0.95))
        self.edge:Show()
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        pcall(GameTooltip.SetHyperlink, GameTooltip, self.entry.link)
        GameTooltip:Show()
    end)
    line:SetScript("OnLeave", function(self)
        if self.paint then self.paint() end
        GameTooltip:Hide()
    end)
    line:SetScript("OnClick", function(self)
        if not self.entry then return end
        EnchantWindowUI.item = self.entry
        EnchantWindowUI:HideList()
        EnchantWindowUI:Refresh()
    end)
    list.lines[index] = line
    return line
end

--- WORN, then IN YOUR BAGS, each item with its gain or the enchant on it.
function EnchantWindowUI:DrawList()
    local list = self.list
    if not list then return end
    local items = self.items or {}

    local rows = {}
    local worn, bags = {}, {}
    for _, entry in ipairs(items) do
        if entry.worn then worn[#worn + 1] = entry else bags[#bags + 1] = entry end
    end
    if #worn > 0 then
        rows[#rows + 1] = { heading = L["WORN"] }
        for _, entry in ipairs(worn) do rows[#rows + 1] = { entry = entry } end
    end
    if #bags > 0 then
        rows[#rows + 1] = { heading = L["IN YOUR BAGS"] }
        for _, entry in ipairs(bags) do rows[#rows + 1] = { entry = entry } end
    end
    if #rows == 0 then rows[1] = { empty = true } end

    local most = EnchantWindowUI.LIST_MOST
    local first = math.max(1, math.min(self.listFirst or 1, #rows - most + 1))
    self.listFirst = first

    local y, shown, band = 2, 0, 0
    for index = first, math.min(#rows, first + most - 1) do
        local data = rows[index]
        shown = shown + 1
        local line = ListLine(list, shown)
        local height = data.heading and LIST_HEADING or LIST_ROW
        line:ClearAllPoints()
        line:SetPoint("TOPLEFT", 2, -y)
        line:SetPoint("TOPRIGHT", -2, -y)
        line:SetHeight(height)
        line.entry = data.entry
        line.edge:Hide()
        if data.heading or data.empty then
            line.icon:Hide()
            line.name:SetText(data.heading or L["Nothing you have can take this enchant."])
            line.name:SetTextColor(Theme.Unpack(data.heading and "accent" or "muted"))
            line.right:SetText("")
            line.fill:SetColorTexture(Theme.Unpack("glassAlt", 0.95))
            line.rule:Hide()
            line.paint = nil
            band = 0
        else
            band = band + 1
            local entry = data.entry
            Theme.SetItemIcon(line.icon, ItemIDOf(entry.link), entry.link)
            line.name:SetText(NameOf(entry.link) or "")
            Theme.SetItemNameColor(line.name, ItemIDOf(entry.link))
            if (entry.gain or 0) > 0 then
                line.right:SetText(("+%d%%"):format(entry.gain))
                line.right:SetTextColor(Theme.Unpack("profit"))
            elseif entry.current then
                line.right:SetText(L.Format(L["Has %s"], entry.current))
                line.right:SetTextColor(Theme.Unpack("muted"))
            else
                line.right:SetText("")
            end
            local picked = self.item and Logic().Key(self.item) == Logic().Key(entry)
            local glass = picked and "glassActive" or (band % 2 == 0 and "glassAlt" or "glass")
            line.paint = function()
                line.fill:SetColorTexture(Theme.Unpack(glass, 0.95))
                line.edge:SetShown(picked)
            end
            line.paint()
            line.rule:Show()
        end
        line:Show()
        y = y + height
    end
    for index = shown + 1, #list.lines do list.lines[index]:Hide() end
    list:SetHeight(y + 2)
end

--- An item dropped on the slot: taken when this enchant fits it.
function EnchantWindowUI:Dropped()
    if type(GetCursorInfo) ~= "function" then return end
    local kind, _, link = GetCursorInfo()
    if kind ~= "item" then return end
    for _, entry in ipairs(self.items or {}) do
        if entry.link == link then
            self.item = entry
            if type(ClearCursor) == "function" then ClearCursor() end
            self:HideList()
            self:Refresh()
            return
        end
    end
end

--------------------------------------------------------------------------------
-- Enchant, Put It On and the glow
--------------------------------------------------------------------------------

function EnchantWindowUI:EnchantClicked()
    local logic = Logic()
    local enchant = self.recipeID and logic:Find(self.recipeID)
    if not enchant then return end
    self:HideList()
    local result, why = logic:Cast(enchant, self.item)
    if not result then
        if why then ns.Print(why) end
        self:Refresh()
        return
    end
    if result == "target" and logic.pending and logic.pending.way == "glow" then
        logic.pending.putOn, logic.pending.glow = true, true
        self:ShowGlow(logic.pending.entry)
    end
    -- The game shows the enchant hand a moment after the click.
    if C_Timer then C_Timer.After(0.2, function() EnchantWindowUI:Refresh() end) end
    self:Refresh()
end

--- The secure Put It On button, over Enchant, made once.
function EnchantWindowUI:BuildOverlay()
    if self.overlay then return self.overlay end
    local overlay = CreateFrame("Button", "BlackthornesTSEnchantPutOn", UIParent, "SecureActionButtonTemplate")
    overlay:Hide()
    overlay:EnableMouse(true)
    overlay:RegisterForClicks("AnyUp")
    overlay:SetAttribute("useOnKeyDown", false)
    overlay:SetScript("PreClick", function(button)
        if InCombat() then return end
        local entry = Logic():PutOnTarget()
        if not entry then
            button:SetAttribute("type", nil)
            return
        end
        button:SetAttribute("type", "macro")
        button:SetAttribute("macrotext", Logic().PutOnMacro(entry))
        if Logic().pending then Logic().pending.putOn = true end
    end)
    overlay:SetScript("PostClick", function()
        if C_Timer then C_Timer.After(0.2, function() EnchantWindowUI:Refresh() end) end
    end)
    overlay:SetScript("OnEnter", function()
        local onEnter = EnchantWindowUI.button:GetScript("OnEnter")
        if onEnter then onEnter(EnchantWindowUI.button) end
    end)
    overlay:SetScript("OnLeave", function()
        local onLeave = EnchantWindowUI.button:GetScript("OnLeave")
        if onLeave then onLeave(EnchantWindowUI.button) end
    end)
    self.overlay = overlay
    return overlay
end

--- Lay Put It On over the Enchant button by screen position.
function EnchantWindowUI:PlaceOverlay()
    local overlay, anchor = self.overlay, self.button
    if not overlay or not overlay:IsShown() or not anchor or InCombat() then return end
    local left, bottom = anchor:GetLeft(), anchor:GetBottom()
    if not left or not bottom then return end
    local scale = anchor:GetEffectiveScale() / UIParent:GetEffectiveScale()
    overlay:SetFrameStrata(STRATA_ABOVE[anchor:GetFrameStrata()] or "DIALOG")
    overlay:SetFrameLevel(anchor:GetFrameLevel() + 5)
    overlay:ClearAllPoints()
    overlay:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left * scale, bottom * scale)
    overlay:SetSize(anchor:GetWidth() * scale, anchor:GetHeight() * scale)
end

function EnchantWindowUI:Arm(entry)
    if InCombat() or not entry then return end
    local overlay = self:BuildOverlay()
    overlay:SetAttribute("type", "macro")
    overlay:SetAttribute("macrotext", Logic().PutOnMacro(entry))
    overlay:Show()
    self:PlaceOverlay()
    self.button:EnableMouse(false)
end

function EnchantWindowUI:Disarm()
    if self.button then self.button:EnableMouse(true) end
    local overlay = self.overlay
    if not overlay or InCombat() then return end
    overlay:SetAttribute("type", nil)
    overlay:SetAttribute("macrotext", nil)
    overlay:Hide()
end

--- The game's own button holding an item, read only, or nil.
function EnchantWindowUI.ButtonFor(entry)
    if not entry then return nil end
    if entry.worn then
        local button = _G[EnchantWindowUI.SHEET_SLOTS[entry.slot] or ""]
        if type(button) == "table" and button.IsVisible and button:IsVisible() then return button end
        return nil
    end
    local frames = { _G.ContainerFrameCombinedBags }
    for index = 1, 13 do frames[#frames + 1] = _G["ContainerFrame" .. index] end
    for _, container in ipairs(frames) do
        local items = type(container) == "table" and rawget(container, "Items")
        if type(items) == "table" then
            for _, button in ipairs(items) do
                local ok, bag, slot = pcall(function() return button:GetBagID(), button:GetID() end)
                if ok and bag == entry.bag and slot == entry.slot and button:IsVisible() then return button end
            end
        end
    end
    return nil
end

--- A gold ring on the item to click, while the enchant waits for it. Our
--- own frame, laid on the game's button by anchor; nothing on it changes.
function EnchantWindowUI:ShowGlow(entry)
    local glow = self.glow
    if not glow then
        glow = CreateFrame("Frame", nil, UIParent)
        glow:EnableMouse(false)
        for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
            local edge = glow:CreateTexture(nil, "OVERLAY")
            edge:SetColorTexture(Theme.Unpack("accentHi"))
            if side == "TOP" or side == "BOTTOM" then
                edge:SetPoint(side .. "LEFT")
                edge:SetPoint(side .. "RIGHT")
                edge:SetHeight(2)
            else
                edge:SetPoint("TOP" .. side)
                edge:SetPoint("BOTTOM" .. side)
                edge:SetWidth(2)
            end
        end
        if Theme.Halo then Theme.Halo(glow, 8, 0.5, "accent") end
        self.glow = glow
    end
    self.glowEntry = entry
    glow:Hide()
    local elapsed = 0
    glow:SetScript("OnUpdate", nil)
    -- The slot in this window glows too, so something always shows.
    self.slot.edge:SetColorTexture(Theme.Unpack("accentHi"))
    local watcher = self.glowWatch or CreateFrame("Frame")
    self.glowWatch = watcher
    watcher:SetScript("OnUpdate", function(_, step)
        elapsed = elapsed + step
        if elapsed < EnchantWindowUI.GLOW_LOOK then return end
        elapsed = 0
        local pending = Logic().pending
        if not pending or not pending.glow or not Logic().Targeting() then
            EnchantWindowUI:HideGlow()
            EnchantWindowUI:Refresh()
            return
        end
        local button = EnchantWindowUI.ButtonFor(EnchantWindowUI.glowEntry)
        if button then
            glow:ClearAllPoints()
            glow:SetPoint("TOPLEFT", button, "TOPLEFT", -2, 2)
            glow:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 2, -2)
            glow:SetFrameStrata(STRATA_ABOVE[button:GetFrameStrata()] or "DIALOG")
            glow:Show()
        else
            glow:Hide()
        end
    end)
end

function EnchantWindowUI:HideGlow()
    if self.glowWatch then self.glowWatch:SetScript("OnUpdate", nil) end
    if self.glow then self.glow:Hide() end
    self.glowEntry = nil
end

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------

--- Bags and gear come in bursts: one redraw after they settle, and only
--- while the window shows.
function EnchantWindowUI:Soon()
    self.bagsVersion = (self.bagsVersion or 0) + 1
    if self.waiting or not (self.frame and self.frame:IsShown()) then return end
    self.waiting = true
    C_Timer.After(EnchantWindowUI.SETTLE, function()
        EnchantWindowUI.waiting = nil
        EnchantWindowUI:Refresh()
    end)
end

function EnchantWindowUI:OnEnable()
    ns.RegisterEvent(self, "TRADE_SKILL_SHOW", function()
        EnchantWindowUI.open = true
        EnchantWindowUI.closed = nil
        EnchantWindowUI:Update()
        -- The game's window can arrive a moment after the event.
        C_Timer.After(0.5, function() EnchantWindowUI:Update() end)
    end)
    ns.RegisterEvent(self, "TRADE_SKILL_CLOSE", function()
        EnchantWindowUI.open = nil
        EnchantWindowUI:Update()
    end)
    ns.RegisterEvent(self, "BAG_UPDATE_DELAYED", function() EnchantWindowUI:Soon() end)
    ns.RegisterEvent(self, "PLAYER_EQUIPMENT_CHANGED", function() EnchantWindowUI:Soon() end)
    ns.RegisterEvent(self, "GET_ITEM_INFO_RECEIVED", function()
        if EnchantWindowUI.frame and EnchantWindowUI.frame:IsShown() then EnchantWindowUI:Soon() end
    end)
    ns.RegisterEvent(self, "PLAYER_REGEN_DISABLED", function()
        -- Put It On goes before the fight locks it.
        local overlay = EnchantWindowUI.overlay
        if overlay then
            overlay:SetAttribute("type", nil)
            overlay:SetAttribute("macrotext", nil)
            overlay:Hide()
        end
        if EnchantWindowUI.button then EnchantWindowUI.button:EnableMouse(true) end
        EnchantWindowUI:Refresh()
    end)
    ns.RegisterEvent(self, "PLAYER_REGEN_ENABLED", function() EnchantWindowUI:Refresh() end)
end
