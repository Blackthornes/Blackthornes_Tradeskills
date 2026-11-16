-- Blackthornes -- UI/CraftStrip.lua
-- The slim strip inside the profession window (the owner said build it,
-- 2026-11-16, recommendation 4 of Docs/handoff/ui-cleanup-tradeskills.md,
-- mockup overlap-4-strip-inside.png). When there is no room beside the
-- profession window for the craft pane, the pane used to fold under the
-- character sheet or run off the screen's edge. Now a strip sits at the foot
-- of the game's recipe pane instead, with the next craft, Craft Next and
-- Open Queue. It lifts clear of the game's Create buttons, and over the
-- enchant strip when that shows, the way EnchantWindowUI.Lift does.
--
-- Our own frame on UIParent, anchored by position. No Blizzard frame is
-- hidden, shown, moved or reparented. CraftPanel:Place decides when it
-- shows (CraftStrip.NoRoom); TSTabs:AtDock leaves the one window shut at
-- the profession window when it has no room there at a readable size
-- (CraftStrip:OneHasRoom), so the strip shows then too.

local addonName, ns = ...
local L = ns.L or setmetatable({ Format = string.format }, { __index = function(_, key) return key end })

local CraftStrip = ns.NewModule("CraftStrip")

local Theme = ns.Theme
local Widgets = ns.Widgets

CraftStrip.HEIGHT = 58
CraftStrip.INSET = 8
CraftStrip.GAP = 4
CraftStrip.MIN_WIDTH = 240
-- The smallest size, in percent, the docked one window may take and still
-- be read. Under it, Tradeskills doesn't open the one window at the
-- profession window and the strip shows instead. A number the shared
-- window gives (DOCK_SCALE_MIN) wins.
CraftStrip.READABLE = 75

--------------------------------------------------------------------------------
-- When it shows (pure)
--------------------------------------------------------------------------------

--- True when the craft pane has no room beside the profession window.
--- `place` is from CraftPanel.SheetPlace; the rest in screen pixels.
function CraftStrip.NoRoom(place, tradeRight, overhang, gap, paneWidth, screenRight)
    if place == "fold" then return true end
    if place ~= "dock" then return false end
    if type(tradeRight) ~= "number" or type(paneWidth) ~= "number" or type(screenRight) ~= "number" then
        return false
    end
    return tradeRight + (overhang or 0) + (gap or 0) + paneWidth > screenRight
end

--- True when a window `width` wide (screen pixels) fits on either side of
--- the game's window, with `gap` between. Unknown edges count as room.
function CraftStrip.Fits(gameLeft, gameRight, width, gap, screen)
    if type(gameLeft) ~= "number" or type(gameRight) ~= "number"
        or type(width) ~= "number" or type(screen) ~= "number" then
        return true
    end
    local need = width + (gap or 0)
    return screen - gameRight >= need or gameLeft >= need
end

--- The strip's line: "Next: Heavy Runecloth Bandage x5", or why there is
--- nothing to make. Pure.
function CraftStrip.LineText(state)
    state = state or {}
    if state.empty then return L["Nothing is queued"] end
    if not state.name then return L["Nothing here can be made yet"] end
    return L.Format("Next: %s x%d", state.name, state.count or 1)
end

--------------------------------------------------------------------------------
-- Room for the one window
--------------------------------------------------------------------------------

local function Number(frame, method)
    if type(frame) ~= "table" or type(frame[method]) ~= "function" then return nil end
    local ok, value = pcall(frame[method], frame)
    if ok and type(value) == "number" then return value end
    return nil
end

--- A frame's edge in screen pixels, or nil.
local function Edge(frame, method)
    local value = Number(frame, method)
    if not value then return nil end
    local scale = Number(frame, "GetEffectiveScale")
    return value * ((scale and scale > 0) and scale or 1)
end
CraftStrip.Edge = Edge

--- True when the one window fits beside the profession window at a size
--- that can still be read. Read only; true when anything can't be read.
function CraftStrip:OneHasRoom(One)
    local panel = ns.CraftPanel
    local trade = panel and panel.FindTradeSkillFrame and panel:FindTradeSkillFrame()
    if not trade then return true end
    One = type(One) == "table" and One or {}
    local hub = rawget(_G, "BlackthornesWindow")
    local frame = type(hub) == "table" and hub.frame or nil

    local width = tonumber(One.WIDTH) or 860
    if frame and type(One.FullSize) == "function" then
        local ok, w = pcall(One.FullSize, frame)
        if ok and type(w) == "number" and w > 0 then width = w end
    end
    if not (type(hub) == "table" and hub.docked) then
        width = width - (tonumber(One.RAIL_WIDTH) or 84) - 8
    end

    local least = tonumber(One.DOCK_SCALE_MIN) or CraftStrip.READABLE
    least = math.max(least, tonumber(One.SCALE_MIN) or 0)
    local base = Number(UIParent, "GetEffectiveScale") or 1
    local screen = Edge(UIParent, "GetRight")
    return CraftStrip.Fits(Edge(trade, "GetLeft"), Edge(trade, "GetRight"),
        width * base * least / 100, tonumber(One.DOCK_GAP) or 6, screen)
end

--------------------------------------------------------------------------------
-- Building
--------------------------------------------------------------------------------

local function Busy()
    return ns.Crafting and ns.Crafting.IsBusy and ns.Crafting:IsBusy() and true or false
end

function CraftStrip:Build()
    if self.frame then return self.frame end

    local frame = CreateFrame("Frame", "BlackthornesTSCraftStrip", UIParent)
    frame:SetSize(320, CraftStrip.HEIGHT)
    frame:EnableMouse(true)
    frame:Hide()
    self.frame = frame

    Theme.Fill(frame, "window")
    Theme.Border(frame, "accentHi")
    if Theme.Halo then Theme.Halo(frame, 6, 0.35, "accent") end

    local craft = Widgets.CreateButton(frame, L["Craft Next"], function()
        CraftStrip:CraftClicked()
    end, { primary = true, height = 22 })
    local wide = 90
    for _, word in ipairs({ L["Craft Next"], L["Stop crafting"] }) do
        craft.label:SetText(word)
        wide = math.max(wide, (Theme.TextWidth(craft.label) or 60) + 24)
    end
    craft.label:SetText(L["Craft Next"])
    craft:SetWidth(wide)
    craft:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 10, 8)
    self.button = craft

    local open = Widgets.CreateButton(frame, L["Open Queue"], function()
        if ns.Queue and ns.Queue.ShowQueue then ns.Queue:ShowQueue() end
    end, { height = 22 })
    open:SetWidth(math.max(90, (Theme.TextWidth(open.label) or 60) + 24))
    open:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -10, 8)
    open.tooltipText = L["Opens your whole craft queue."]
    self.open = open

    local line = Theme.CreateLabel(frame, "small", "text")
    line:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -7)
    line:SetPoint("RIGHT", frame, "RIGHT", -10, 0)
    line:SetJustifyH("LEFT")
    line:SetWordWrap(false)
    self.line = line
    return frame
end

--- Same as the pane's Craft next: one click runs one queue entry.
function CraftStrip:CraftClicked()
    local panel = ns.CraftPanel
    if Busy() then
        ns.Crafting:Stop()
    elseif panel and panel.GetNextReadyHere then
        local entry = panel:GetNextReadyHere()
        if entry then ns.Crafting:Start(entry.recipeID, entry.quantity) end
    end
    self:Update()
end

--------------------------------------------------------------------------------
-- Place
--------------------------------------------------------------------------------

--- At the foot of the game's recipe pane, over the Create buttons and the
--- enchant strip. True when it found a pane.
function CraftStrip:Place()
    local frame = self.frame
    local Enchant = ns.EnchantWindowUI
    if not (frame and Enchant and Enchant.FindAnchor) then return false end
    local anchor = Enchant.FindAnchor()
    self.anchor = anchor
    if not anchor then return false end
    local pane = Enchant.Rect and Enchant.Rect(anchor.frame)
    local lift = 0
    if pane then
        local rects = {}
        for _, button in ipairs(Enchant.CreateButtons and Enchant.CreateButtons() or {}) do
            local rect = Enchant.Rect(button)
            if rect and rect.right > pane.left and rect.left < pane.right then rects[#rects + 1] = rect end
        end
        lift = Enchant.Lift(pane.bottom, rects)
        frame:SetWidth(math.max(CraftStrip.MIN_WIDTH, (pane.right - pane.left) - CraftStrip.INSET * 2))
    end
    -- Over the enchant strip when it shows there too.
    local enchant = Enchant.frame
    if enchant and enchant:IsShown() then
        lift = (Enchant.lift or lift) + (enchant:GetHeight() or 0) + CraftStrip.GAP
    end
    self.lift = lift
    frame:ClearAllPoints()
    frame:SetPoint("BOTTOM", anchor.frame, "BOTTOM", 0, CraftStrip.INSET + lift)

    local game = anchor.game or anchor.frame
    local okStrata, strata = pcall(game.GetFrameStrata, game)
    local okLevel, level = pcall(anchor.frame.GetFrameLevel, anchor.frame)
    if okStrata and strata then pcall(frame.SetFrameStrata, frame, strata) end
    if okLevel and level then pcall(frame.SetFrameLevel, frame, level + 30) end
    return true
end

--------------------------------------------------------------------------------
-- Showing
--------------------------------------------------------------------------------

--- What the line and button say now.
function CraftStrip:State()
    local panel = ns.CraftPanel
    if not (ns.Queue and ns.Queue.Count) or ns.Queue:Count() == 0 then return { empty = true } end
    local entry, _, slots = panel and panel.GetNextReadyHere and panel:GetNextReadyHere()
    if not entry then return {} end
    local recipe = ns.Recipes and ns.Recipes.GetAny and ns.Recipes:GetAny(entry.recipeID)
    local count = entry.quantity or 1
    if ns.Profit and ns.Profit.GetCraftableCount then
        count = math.min(count, ns.Profit:GetCraftableCount(entry.recipeID) or count)
    end
    return { name = (recipe and recipe.name) or L["item"], count = count, slots = slots, entry = entry }
end

--- Redraw the line and the button. Cheap: one queue walk.
function CraftStrip:Update()
    local frame = self.frame
    if not (frame and frame:IsShown()) then return end
    local state = self:State()
    self.line:SetText(CraftStrip.LineText(state))
    local button = self.button
    if Busy() then
        button:SetText(L["Stop crafting"])
        button:SetEnabledState(true)
        button.tooltipText = L["Stop after the current craft"]
    else
        button:SetText(L["Craft Next"])
        button:SetEnabledState(state.entry ~= nil)
        button.tooltipText = state.entry and L["Makes every craft in this entry"] or CraftStrip.LineText(state)
    end
end

function CraftStrip:Show()
    local frame = self:Build()
    if not self:Place() then
        frame:Hide()
        return false
    end
    frame:Show()
    self:Update()
    return true
end

function CraftStrip:Hide()
    if self.frame then self.frame:Hide() end
end

function CraftStrip:IsShown()
    return self.frame ~= nil and self.frame:IsShown()
end

--- For /bts probe.
function CraftStrip:ProbeLines()
    return {
        { "craft strip", (self:IsShown() and "showing" or "hidden") .. ", anchored to "
            .. (self.anchor and self.anchor.name or "nothing") .. (", lift %d"):format(math.floor((self.lift or 0) + 0.5)) },
    }
end
