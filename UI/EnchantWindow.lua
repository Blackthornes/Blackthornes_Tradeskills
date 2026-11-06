-- Blackthornes -- UI/EnchantWindow.lua
-- The enchant strip (Trent picked it, 2026-11-05, option B of the mockup in
-- the project files, previews/tradeskills-enchant-integrated/): a small strip
-- at the bottom of the game's recipe pane in the Enchanting window, with the
-- item, its materials and cost, and an Enchant button. It replaced the
-- floating Enchant window, which opened behind the craft pane's drawer.
--
-- Our own frame on UIParent, anchored by position over the bottom of the
-- recipe pane and lifted above the game's Create buttons so it never covers
-- them. No Blizzard frame is hidden, shown, moved or reparented; the game's
-- recipe pick is followed with read-only hooks (and a light look while the
-- window is open, in case the client has neither hook). It shows only while
-- the recipe picked is an enchant (recipe type 3), and never in a fight.
--
-- What it reads and casts is Logic/EnchantWindow.lua. Off by default
-- (`enchantWindow`). `enchantWindowLeft`, `enchantWindowTop` and
-- `enchantWindowScale` from the floating window stay in the save, unread;
-- never rename them.
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

local HEIGHT = 64
local SLOT_ICON = 40
local INSET = 8
local LIST_ROW = 24
local LIST_HEADING = 20
-- Space kept between the strip and the game's Create buttons.
EnchantWindowUI.GAP = 4
-- A Create button counts as under the strip when its top is this close to
-- the pane's bottom (it sits in the band the strip would take).
EnchantWindowUI.BAND = HEIGHT + 40
EnchantWindowUI.MIN_WIDTH = 240
-- The picker shows at most this many rows; the wheel moves through the rest.
EnchantWindowUI.LIST_MOST = 12
EnchantWindowUI.SETTLE = 0.2
EnchantWindowUI.GLOW_LOOK = 0.25
-- How often the backup look reads the game's pick, while Enchanting is open.
EnchantWindowUI.PICK_LOOK = 0.3

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

local function Shown(frame)
    if type(frame) ~= "table" or type(frame.IsVisible) ~= "function" then return false end
    local ok, shown = pcall(frame.IsVisible, frame)
    return ok and shown and true or false
end

local function Field(frame, key)
    if type(frame) ~= "table" then return nil end
    local ok, value = pcall(function() return frame[key] end)
    return ok and type(value) == "table" and value or nil
end

--------------------------------------------------------------------------------
-- Where it sits (read only)
--------------------------------------------------------------------------------

--- The pane to sit in, first that shows wins: { name, frame, game }.
--- The name is for the probe.
function EnchantWindowUI.FindAnchor()
    local pros = _G.ProfessionsFrame
    local page = Field(pros, "CraftingPage")
    local form = Field(page, "SchematicForm")
    if Shown(form) then return { name = "ProfessionsFrame.CraftingPage.SchematicForm", frame = form, game = pros } end
    if Shown(page) then return { name = "ProfessionsFrame.CraftingPage", frame = page, game = pros } end
    local old = _G.TradeSkillFrame
    local detail = _G.TradeSkillDetailScrollFrame
    if Shown(detail) then return { name = "TradeSkillDetailScrollFrame", frame = detail, game = old } end
    if Shown(pros) then return { name = "ProfessionsFrame", frame = pros, game = pros } end
    if Shown(old) then return { name = "TradeSkillFrame", frame = old, game = old } end
    return nil
end

--- The game's Create buttons and count box, those that show.
function EnchantWindowUI.CreateButtons()
    local page = Field(_G.ProfessionsFrame, "CraftingPage")
    local found = {}
    for _, frame in ipairs({
        Field(page, "CreateButton"), Field(page, "CreateAllButton"), Field(page, "CreateMultipleInputBox"),
        _G.TradeSkillCreateButton, _G.TradeSkillCreateAllButton, _G.TradeSkillInputBox,
    }) do
        if Shown(frame) then found[#found + 1] = frame end
    end
    return found
end

--- How far up from the pane's bottom the strip goes so it clears every
--- button in `rects` ({ top, bottom }, screen units) under it. Pure.
function EnchantWindowUI.Lift(paneBottom, rects)
    local lift = 0
    for _, rect in ipairs(rects or {}) do
        local top, bottom = tonumber(rect.top), tonumber(rect.bottom)
        if top and bottom and bottom < paneBottom + EnchantWindowUI.BAND and top > paneBottom then
            lift = math.max(lift, top - paneBottom + EnchantWindowUI.GAP)
        end
    end
    return lift
end

--- A frame's edges in UIParent's units, or nil.
local function Rect(frame)
    local ok, top, bottom, left, right, scale = pcall(function()
        return frame:GetTop(), frame:GetBottom(), frame:GetLeft(), frame:GetRight(), frame:GetEffectiveScale()
    end)
    if not ok or not top or not bottom or not left or not right then return nil end
    local base = UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale() or 1
    local k = (tonumber(scale) or 1) / (base > 0 and base or 1)
    return { top = top * k, bottom = bottom * k, left = left * k, right = right * k }
end
EnchantWindowUI.Rect = Rect

--------------------------------------------------------------------------------
-- The words on the strip
--------------------------------------------------------------------------------

--- "Strange Dust 26/1 · Soul Dust 0/2 · 75c": each material with have/need
--- in green or red, then the cost. Pure, given the rows and a name lookup.
function EnchantWindowUI.InfoLine(rows, cost, nameOf)
    local parts = {}
    local colors = ns.COLORS or {}
    for _, data in ipairs(rows or {}) do
        local name = nameOf and nameOf(data.itemID) or tostring(data.itemID)
        local hex = (data.short or 0) > 0 and (colors.loss or "ffe5604f") or (colors.profit or "ff4fd18b")
        parts[#parts + 1] = ("%s |c%s%d/%d|r"):format(name or "?", hex, math.min(data.have or 0, 9999), data.need or 0)
    end
    if cost and cost > 0 and ns.Util and ns.Util.FormatMoney then
        parts[#parts + 1] = ns.Util.FormatMoney(cost)
    end
    return table.concat(parts, " · ")
end

local function MaterialName(itemID)
    local name = ns.Util.GetItemName and ns.Util.GetItemName(itemID)
    if type(name) ~= "string" then name = NameOf(ns.Util.GetItemLabel and ns.Util.GetItemLabel(itemID)) end
    return name
end

--------------------------------------------------------------------------------
-- Building
--------------------------------------------------------------------------------

function EnchantWindowUI:Build()
    if self.frame then return self.frame end

    local frame = CreateFrame("Frame", "BlackthornesTSEnchantStrip", UIParent)
    frame:SetSize(320, HEIGHT)
    frame:EnableMouse(true)
    frame:Hide()
    self.frame = frame

    Theme.Fill(frame, "window")
    Theme.Border(frame, "accentHi")
    if Theme.Halo then Theme.Halo(frame, 6, 0.35, "accent") end

    frame:SetScript("OnHide", function()
        EnchantWindowUI:HideList()
        EnchantWindowUI:Disarm()
        EnchantWindowUI:HideGlow()
    end)

    self:BuildSlot(frame)

    -- Enchant, or Put It On: as wide as the longer of the two.
    self.button = Widgets.CreateButton(frame, L["Enchant"], function()
        EnchantWindowUI:EnchantClicked()
    end, { primary = true, height = 30 })
    local wide = 90
    for _, word in ipairs({ L["Enchant"], L["Put It On"] }) do
        self.button.label:SetText(word)
        wide = math.max(wide, (Theme.TextWidth(self.button.label) or 60) + 28)
    end
    self.button.label:SetText(L["Enchant"])
    self.button:SetWidth(wide)
    self.button:SetPoint("RIGHT", frame, "RIGHT", -10, 0)

    -- Item name (and the gain), then the materials and cost under it.
    self.name = Theme.CreateLabel(frame, "normal", "text")
    self.name:SetPoint("TOPLEFT", self.slot, "TOPRIGHT", 10, -1)
    self.name:SetPoint("RIGHT", self.button, "LEFT", -10, 0)
    self.name:SetWordWrap(true)
    self.info = Theme.CreateLabel(frame, "small", "muted")
    self.info:SetPoint("TOPLEFT", self.name, "BOTTOMLEFT", 0, -3)
    self.info:SetPoint("RIGHT", self.button, "LEFT", -10, 0)
    self.info:SetWordWrap(true)
    return frame
end

--- The item slot: click for the list, or drop an item on it.
function EnchantWindowUI:BuildSlot(frame)
    local slot = CreateFrame("Button", nil, frame)
    slot:SetSize(SLOT_ICON + 6, SLOT_ICON + 6)
    slot:SetPoint("LEFT", 10, 0)
    slot:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    slot.fill = slot:CreateTexture(nil, "BACKGROUND")
    slot.fill:SetAllPoints()
    Theme.Border(slot, "accent")
    slot.edge = slot:CreateTexture(nil, "BORDER")
    slot.edge:SetPoint("TOPLEFT")
    slot.edge:SetPoint("BOTTOMLEFT")
    slot.edge:SetWidth(3)
    slot.edge:SetColorTexture(Theme.Unpack("accentHi"))
    slot.icon = Theme.CreateItemIcon(slot, SLOT_ICON)
    slot.icon:SetPoint("CENTER")

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
            if (entry.gain or 0) > 0 then
                GameTooltip:AddLine(L.Format(L["+%d%% for you"], entry.gain), 0.31, 0.82, 0.55)
            end
            GameTooltip:AddDoubleLine(L["Replaces:"], entry.current or L["Nothing"], 1, 0.82, 0, 0.7, 0.7, 0.7)
            GameTooltip:AddLine(L["Click to pick an item. You can also drop one here."], 0.6, 0.6, 0.6, true)
        else
            GameTooltip:SetText(L["Click to pick an item. You can also drop one here."], 1, 1, 1, 1, true)
        end
        GameTooltip:Show()
    end)
    slot:SetScript("OnLeave", function()
        EnchantWindowUI:PaintSlot()
        GameTooltip:Hide()
    end)

    self.slot = slot
end

--------------------------------------------------------------------------------
-- Place
--------------------------------------------------------------------------------

--- Over the bottom of the recipe pane, above the Create buttons, by anchor.
--- Returns true when it found a pane.
function EnchantWindowUI:Place()
    local frame = self.frame
    if not frame then return false end
    local anchor = EnchantWindowUI.FindAnchor()
    self.anchor = anchor
    if not anchor then return false end
    local pane = Rect(anchor.frame)
    local lift = 0
    if pane then
        local rects = {}
        for _, button in ipairs(EnchantWindowUI.CreateButtons()) do
            local rect = Rect(button)
            if rect and rect.right > pane.left and rect.left < pane.right then rects[#rects + 1] = rect end
        end
        lift = EnchantWindowUI.Lift(pane.bottom, rects)
        local width = math.max(EnchantWindowUI.MIN_WIDTH, (pane.right - pane.left) - INSET * 2)
        frame:SetWidth(width)
    end
    self.lift = lift
    frame:ClearAllPoints()
    frame:SetPoint("BOTTOM", anchor.frame, "BOTTOM", 0, INSET + lift)

    local game = anchor.game or anchor.frame
    local okStrata, strata = pcall(game.GetFrameStrata, game)
    local okLevel, level = pcall(anchor.frame.GetFrameLevel, anchor.frame)
    if okStrata and strata then pcall(frame.SetFrameStrata, frame, strata) end
    if okLevel and level then pcall(frame.SetFrameLevel, frame, level + 30) end
    if self.list then pcall(self.list.SetFrameStrata, self.list, STRATA_ABOVE[frame:GetFrameStrata()] or "DIALOG") end
    self:PlaceOverlay()
    return true
end

--- For /bts probe: which frame it anchored to and how far it was lifted.
function EnchantWindowUI:ProbeLines()
    local anchor = self.anchor or EnchantWindowUI.FindAnchor()
    local shown = self.frame and self.frame:IsShown()
    return {
        { "enchant strip", (shown and "showing" or "hidden") .. ", anchored to "
            .. (anchor and anchor.name or "nothing found") },
        { "enchant strip lift", ("%d over the Create buttons (%d found)"):format(
            math.floor((self.lift or 0) + 0.5), #EnchantWindowUI.CreateButtons()) },
        { "enchant strip pick", ("recipe %s, hook %s"):format(tostring(self.recipeID),
            self.hooked or "none, looks every " .. EnchantWindowUI.PICK_LOOK .. "s") },
    }
end

--------------------------------------------------------------------------------
-- Following the game's pick (read only)
--------------------------------------------------------------------------------

function EnchantWindowUI:Hook()
    if self.hooked then return end
    local page = Field(_G.ProfessionsFrame, "CraftingPage")
    local form = Field(page, "SchematicForm")
    local again = function() EnchantWindowUI:Soon(true) end
    if form and type(hooksecurefunc) == "function" and type(form.Init) == "function" then
        if pcall(hooksecurefunc, form, "Init", again) then self.hooked = "SchematicForm.Init" end
    end
    local registry = _G.EventRegistry
    if type(registry) == "table" and type(registry.RegisterCallback) == "function" then
        local ok = pcall(registry.RegisterCallback, registry,
            "ProfessionsRecipeListMixin.Event.OnRecipeSelected", again, self)
        if ok then self.hooked = (self.hooked and self.hooked .. ", " or "") .. "OnRecipeSelected" end
    end
end

--- A light look at the game's pick while Enchanting is open, for clients
--- without the hooks; reads one value and does nothing when it is the same.
function EnchantWindowUI:WatchPick()
    local watcher = self.pickWatch or CreateFrame("Frame")
    self.pickWatch = watcher
    local elapsed = 0
    watcher:SetScript("OnUpdate", function(_, step)
        elapsed = elapsed + step
        if elapsed < EnchantWindowUI.PICK_LOOK then return end
        elapsed = 0
        if not EnchantWindowUI.open then
            watcher:SetScript("OnUpdate", nil)
            return
        end
        local pick = Logic():GamePick()
        if pick ~= EnchantWindowUI.seenPick then EnchantWindowUI:Update() end
    end)
end

--------------------------------------------------------------------------------
-- Showing
--------------------------------------------------------------------------------

--- Should the strip be up for this recipe? Pure on what it is given.
function EnchantWindowUI.ShouldShow(state)
    return state.on and state.open and state.enchanting and not state.combat
        and state.enchant ~= nil and true or false
end

--- Show, hide or redraw for how things stand.
function EnchantWindowUI:Update()
    local logic = Logic()
    if not logic then return end
    local on, open = logic:IsOn(), self.open
    local enchanting = on and open and logic:EnchantingOpen() or false
    if enchanting then self:Hook() end
    if enchanting and not logic.enchants and not self.loading then
        self:LoadEnchants()
    end
    local pick = enchanting and logic:GamePick() or nil
    self.seenPick = pick
    local enchant = pick and logic:Find(pick) or nil

    if not EnchantWindowUI.ShouldShow({ on = on, open = open, enchanting = enchanting,
        combat = InCombat(), enchant = enchant }) then
        if self.frame then self.frame:Hide() end
        self.recipeID = enchant and enchant.recipeID or nil
        return
    end
    local frame = self:Build()
    if pick ~= self.recipeID then
        self.recipeID = pick
        self.item, self.itemsKey = nil, nil
        self:HideList()
        logic:Remember(pick)
    end
    if not self:Place() then
        frame:Hide()
        return
    end
    frame:Show()
    self:Refresh()
end

--- Read the enchants a few a frame, then look again.
function EnchantWindowUI:LoadEnchants()
    self.loading = true
    Logic():ReadEnchants(function()
        EnchantWindowUI.loading = nil
        EnchantWindowUI.itemsKey = nil
        EnchantWindowUI:Update()
    end)
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

    -- The slot and the name.
    if entry then
        Theme.SetItemIcon(self.slot.icon, ItemIDOf(entry.link), entry.link)
        local name = NameOf(entry.link) or ""
        if (entry.gain or 0) > 0 then
            name = name .. " |c" .. ((ns.COLORS or {}).profit or "ff4fd18b") .. ("+%d%%"):format(entry.gain) .. "|r"
        end
        self.name:SetText(name)
        Theme.SetItemNameColor(self.name, ItemIDOf(entry.link))
    else
        Theme.SetItemIcon(self.slot.icon, nil)
        if enchant and #items == 0 and not self.loading then
            self.name:SetText(L["Nothing you have can take this enchant."])
        else
            self.name:SetText(L["Pick an Item"])
        end
        self.name:SetTextColor(Theme.Unpack("muted"))
    end
    self:PaintSlot()

    -- Materials and cost.
    local rows, _, _, cost = logic:MaterialState(enchant)
    self.info:SetText(EnchantWindowUI.InfoLine(rows, cost, MaterialName))

    self:PaintButton(enchant, entry)

    -- Tall enough for a name that wraps.
    local used = (self.name:GetStringHeight() or 14) + 3 + (self.info:GetStringHeight() or 12) + 14
    frame:SetHeight(math.max(HEIGHT, math.ceil(used)))
    self:PlaceOverlay()

    if self.list and self.list:IsShown() then self:DrawList() end
end

function EnchantWindowUI:PaintButton(enchant, entry)
    local logic = Logic()
    local button = self.button

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
    -- It opens upward, over the recipe, so the game's Create buttons
    -- under the strip stay clear.
    list:SetPoint("BOTTOMLEFT", self.frame, "TOPLEFT", 0, 2)
    list:SetPoint("BOTTOMRIGHT", self.frame, "TOPRIGHT", 0, 2)
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

--- Bags, gear and the game's pick come in bursts: one look after they
--- settle. A new pick can show or hide the strip; bags only redraw it.
function EnchantWindowUI:Soon(pickChanged)
    if pickChanged then
        self.pickMoved = true
    else
        self.bagsVersion = (self.bagsVersion or 0) + 1
        if not (self.frame and self.frame:IsShown()) then return end
    end
    if self.waiting then return end
    self.waiting = true
    C_Timer.After(EnchantWindowUI.SETTLE, function()
        EnchantWindowUI.waiting = nil
        if EnchantWindowUI.pickMoved then
            EnchantWindowUI.pickMoved = nil
            EnchantWindowUI:Update()
        else
            EnchantWindowUI:Refresh()
        end
    end)
end

function EnchantWindowUI:OnEnable()
    ns.RegisterEvent(self, "TRADE_SKILL_SHOW", function()
        EnchantWindowUI.open = true
        if Logic():IsOn() then
            EnchantWindowUI:Hook()
            EnchantWindowUI:WatchPick()
        end
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
        -- Nothing happens in a fight: the strip steps away until it ends.
        EnchantWindowUI:Update()
    end)
    ns.RegisterEvent(self, "PLAYER_REGEN_ENABLED", function() EnchantWindowUI:Update() end)
end
