-- Blackthornes -- UI/TravelCard.lua
-- "Your Way There" as a small step box (the owner said build it,
-- 2026-11-24, from the mockup, in place of the old window of every step):
-- only the step you are on, in one dark glass row. The row's first line is
-- the step, the second its small line and how far, the third "Step 2 of 4"
-- and about how long the rest takes. A small dial at the row's end turns
-- with the arrow (the same gold chevron, turned with SetRotation); on a step
-- with no way to point (a Hearthstone, a ride) it shows a still gold dot. Stop and Show on Map show while the
-- mouse is on the box.
--
-- Where it hangs, in this order:
--   under the addon's own panel, when it gives one and it shows
--     (`Travel.Host.Hang`, Equipment's small panel), as wide as it;
--   under the arrow's pill (`Travel.Host.Dial`), with the red close gem
--     in its corner;
--   else where it was dragged (`travelCardX`/`travelCardY`, account wide,
--     never rename them) or on the right shelf, with the close gem.
-- While the box shows, the arrow keeps only its name and how far: the box
-- says the step (`TravelCard:Words`).
--
-- It is always see-through (the owner, 2026-11-24): the glass is thin so the
-- world shows, every word has an outline and a black shadow so it reads on
-- any ground, and the glass comes back while the mouse is on it.
--
-- The close gem only puts the box away for this place (`TravelCard:Close`):
-- the arrow still leads the way, and the box comes back when the arrow is
-- aimed somewhere else. Stop ends the trip. Words are drawn again only when
-- they change, and the small dial only when it turns a whole step.
--
-- The same file in every addon whose arrow takes trips (a fix to it belongs
-- in all of them); the addon's own parts come through Travel.Host.

local addonName, ns = ...
local L = ns.L or setmetatable({ Format = string.format }, { __index = function(_, key) return key end })
if not L.Format then
    L.Format = function(key, ...) return string.format(L[key], ...) end
end

local TravelCard = ns.NewModule("TravelCard")

local Theme = ns.Theme
local Widgets = ns.Widgets

local function Host() return ns.Travel.Host end
local function DB() local db = Host().DB() return type(db) == "table" and db or nil end

TravelCard.WIDTH = 250
local PAD = 8
local DIAL = 26
local BUTTONS = 28
-- How much of the glass stays while the mouse is away, and on it.
TravelCard.GLASS_CLEAR = 0.35
TravelCard.GLASS_SOLID = 0.94
-- How often the mouse is looked for once it has left onto a child.
local LOOK = 0.1

local MEDIA = ([[Interface\AddOns\%s\Media\Arrow\]]):format(tostring(addonName))
-- The chevron turns in steps of 2 degrees, as on the arrow.
local TURNS = 180

--- How tall a wrapped label stands at a width, never less than its lines
--- by measure (German runs about 30% longer, so a step's words can take
--- two lines); kept here so the file stays the same in every addon.
function TravelCard.Tall(label, size, width)
    local text = label and label.GetText and label:GetText()
    if type(text) ~= "string" or text == "" then return 0 end
    local line = ((Theme.sizes and tonumber(Theme.sizes[size])) or 12) + 2
    local ok, wide = pcall(label.GetStringWidth, label)
    wide = ok and tonumber(wide) or 0
    local lines = 1
    if width and width > 0 then lines = math.max(1, math.ceil(wide / width)) end
    local _, breaks = text:gsub("\n", "")
    local tall = (lines + breaks) * line
    local got, real = pcall(label.GetStringHeight, label)
    real = got and tonumber(real) or 0
    return math.ceil(math.max(tall, real))
end

--- The step of 2 degrees nearest `turn` (radians, anticlockwise from ahead).
function TravelCard.FrameFor(turn)
    return math.floor(turn / (2 * math.pi) * TURNS + 0.5) % TURNS
end

--- An outline and a black shadow, so a word reads on thin glass.
local function Readable(label)
    pcall(function()
        local font, size = label:GetFont()
        if font and size then label:SetFont(font, size, "OUTLINE") end
    end)
    pcall(label.SetShadowColor, label, 0, 0, 0, 1)
    pcall(label.SetShadowOffset, label, 1, -1)
    return label
end

local function MouseOn(frame)
    local ok, on = pcall(frame.IsMouseOver, frame)
    return ok and on == true
end

function TravelCard:Build()
    if self.frame then return self.frame end

    local frame = CreateFrame("Frame", tostring(addonName):gsub("_", "") .. "TravelCard", UIParent)
    frame:SetSize(TravelCard.WIDTH, 60)
    frame:SetFrameStrata("MEDIUM")
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:Hide()
    self.frame = frame

    -- The glass: thin until the mouse comes.
    frame.fill = Theme.Fill(frame, "glass", 1)
    frame.edge = Theme.Border(frame, "accent", 0.9)
    self.lit = frame:CreateTexture(nil, "BORDER")
    self.lit:SetPoint("TOPLEFT", 1, -1)
    self.lit:SetPoint("BOTTOMLEFT", 1, 1)
    self.lit:SetWidth(2)
    self.lit:SetColorTexture(Theme.Unpack("accentHi"))

    frame:SetScript("OnDragStart", function(self)
        if TravelCard.hung then return end
        self:StartMoving()
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        if not TravelCard.hung then TravelCard:SavePlace() end
    end)
    frame:SetScript("OnEnter", function() TravelCard:SetSolid(true) end)
    frame:SetScript("OnLeave", function() TravelCard:Left() end)

    -- The small dial at the row's end.
    local dial = CreateFrame("Frame", nil, frame)
    dial:SetSize(DIAL, DIAL)
    dial:SetPoint("TOPRIGHT", -PAD, -PAD)
    self.dial = dial
    local well = dial:CreateTexture(nil, "BORDER")
    well:SetAllPoints()
    well:SetTexture(MEDIA .. "Well")
    local rim = dial:CreateTexture(nil, "BORDER", nil, 1)
    rim:SetAllPoints()
    rim:SetTexture(MEDIA .. "WellEdge")
    rim:SetVertexColor(0.61, 0.45, 0.15)
    self.blade = dial:CreateTexture(nil, "ARTWORK")
    self.blade:SetPoint("CENTER")
    self.blade:SetSize(DIAL - 8, DIAL - 8)
    self.blade:SetTexture(MEDIA .. "Chevron")
    self.dot = dial:CreateTexture(nil, "ARTWORK")
    self.dot:SetPoint("CENTER")
    self.dot:SetSize(12, 12)
    self.dot:SetTexture(MEDIA .. "Dot")
    pcall(self.dot.SetBlendMode, self.dot, "ADD")
    self.dot:SetVertexColor(0.95, 0.76, 0.31)
    self.dot:Hide()

    self.title = Readable(Theme.CreateLabel(frame, "normal", "accentHi"))
    self.title:SetPoint("TOPLEFT", PAD + 4, -PAD)
    self.title:SetPoint("RIGHT", dial, "LEFT", -6, 0)
    self.title:SetWordWrap(true)
    self.sub = Readable(Theme.CreateLabel(frame, "small", "text"))
    self.sub:SetPoint("TOPLEFT", self.title, "BOTTOMLEFT", 0, -2)
    self.sub:SetPoint("RIGHT", dial, "LEFT", -6, 0)
    self.sub:SetWordWrap(true)
    self.count = Readable(Theme.CreateLabel(frame, "small", "muted"))
    self.count:SetPoint("TOPLEFT", self.sub, "BOTTOMLEFT", 0, -2)
    self.count:SetPoint("RIGHT", dial, "LEFT", -6, 0)
    self.count:SetWordWrap(true)

    -- Stop and Show on Map, only while the mouse is on the box.
    self.show = Widgets.CreateButton(frame, L["Show on Map"], function() TravelCard:ShowOnMap() end,
        { primary = true })
    self.show:SetPoint("BOTTOMRIGHT", -PAD, PAD - 2)
    self.stop = Widgets.CreateButton(frame, L["Stop"], function() TravelCard:Stop() end)
    self.stop:SetPoint("RIGHT", self.show, "LEFT", -6, 0)
    for _, button in ipairs({ self.show, self.stop }) do
        button:HookScript("OnLeave", function() TravelCard:Left() end)
        button:Hide()
    end

    if ns.Titanforged and ns.Titanforged.CloseGem then
        local close = ns.Titanforged.CloseGem(frame, function() TravelCard:Close() end)
        close:SetSize(16, 16)
        close:ClearAllPoints()
        close:SetPoint("CENTER", frame, "TOPRIGHT", -2, -2)
        close:SetFrameLevel(frame:GetFrameLevel() + 5)
        close:HookScript("OnLeave", function() TravelCard:Left() end)
        self.close = close
    end

    self:SetSolid(false)
    return frame
end

--- Thin glass while the mouse is away; solid, with the buttons, on it.
function TravelCard:SetSolid(solid)
    local frame = self.frame
    if not frame then return end
    solid = solid and true or false
    if self.solid == solid then return end
    self.solid = solid
    self.glass = solid and TravelCard.GLASS_SOLID or TravelCard.GLASS_CLEAR
    frame.fill:SetAlpha(self.glass)
    self.stop:SetShown(solid)
    self.show:SetShown(solid)
    self:Fit()
    if not solid then frame:SetScript("OnUpdate", nil) end
end

--- The mouse left the box or one of its buttons: the glass thins once it is
--- off them all.
function TravelCard:Left()
    local frame = self.frame
    if not frame then return end
    if not MouseOn(frame) then
        self:SetSolid(false)
        return
    end
    local since = 0
    frame:SetScript("OnUpdate", function(_, elapsed)
        since = since + (elapsed or 0)
        if since < LOOK then return end
        since = 0
        if not MouseOn(frame) then TravelCard:SetSolid(false) end
    end)
end

--- Sizes the box to its words, and the buttons when they show.
function TravelCard:Fit()
    local frame = self.frame
    if not frame then return end
    local inner = (self.width or TravelCard.WIDTH) - PAD * 2 - 4 - DIAL - 6
    local tall = PAD + TravelCard.Tall(self.title, "normal", inner)
        + 2 + TravelCard.Tall(self.sub, "small", inner)
        + 2 + TravelCard.Tall(self.count, "small", inner) + PAD
    tall = math.max(tall, DIAL + PAD * 2)
    if self.solid then tall = tall + BUTTONS end
    frame:SetHeight(tall)
end

function TravelCard:SavePlace()
    local frame = self.frame
    local db = DB()
    if not (frame and db) then return end
    local ok, left, top = pcall(function() return frame:GetLeft(), frame:GetTop() end)
    if ok and left and top then db.travelCardX, db.travelCardY = left, top end
end

function TravelCard:RestorePlace()
    local frame = self.frame
    frame:ClearAllPoints()
    local db = DB()
    local x, y = db and tonumber(db.travelCardX), db and tonumber(db.travelCardY)
    if x and y then
        frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x, y)
        return
    end
    -- Never dragged: the next free place on the right shelf, left of the
    -- game's quest list (UI/SharedWindow.lua's shelves).
    local sw = ns.SharedWindow
    local placed = sw and sw.ShelfPlace and sw.ShelfPlace(frame, "travel.shared", {
        shelf = "right",
        free = function()
            local saved = DB()
            return not (saved and tonumber(saved.travelCardX) and tonumber(saved.travelCardY))
        end,
        place = function() if not TravelCard.hung then TravelCard:RestorePlace() end end,
    })
    if not placed then
        frame:SetPoint("RIGHT", UIParent, "RIGHT", -60, 60)
    end
end

local function Showing(frame)
    if not frame or not frame.IsShown then return false end
    local ok, shown = pcall(frame.IsShown, frame)
    return ok and shown == true
end

--- Where the box hangs now: "panel" with the panel's frame, "dial" with the
--- big arrow's dial, or "free".
function TravelCard.Where()
    local host = Host()
    local panel = host.Hang and host.Hang()
    if Showing(panel) then return "panel", panel end
    local ui = host.Dial and host.Dial()
    if type(ui) == "table" and Showing(ui.frame) and ui.dial then return "dial", ui.dial end
    return "free", nil
end

--- Hangs the box where it belongs, only when that changed.
function TravelCard:Hang()
    local frame = self.frame
    local where, anchor = TravelCard.Where()
    local width = TravelCard.WIDTH
    if where == "panel" then
        local ok, wide = pcall(anchor.GetWidth, anchor)
        if ok and tonumber(wide) and wide > 100 then width = wide end
    end
    if where == self.where and anchor == self.anchor and width == self.width then return end
    self.where, self.anchor, self.width = where, anchor, width
    self.hung = where ~= "free" and where or nil
    frame:SetWidth(width)
    frame:ClearAllPoints()
    if where == "panel" then
        -- The panel's own scale, so the two read as one.
        local ok, scale = pcall(anchor.GetScale, anchor)
        frame:SetScale(ok and tonumber(scale) or 1)
        frame:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, 1)
        frame:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, 1)
    elseif where == "dial" then
        frame:SetScale(1)
        frame:SetPoint("TOP", anchor, "BOTTOM", 0, -6)
    else
        frame:SetScale(1)
        self:RestorePlace()
    end
    if self.close then self.close:SetShown(where ~= "panel") end
    self:Fit()
end

--- What the second line says when the arrow gives nothing.
function TravelCard.SubLine(step)
    if step.kind == "fly" then return L["Talk to the flight master"] end
    if step.kind == "boat" or step.kind == "zeppelin" then return L["Get on when it stops"] end
    if step.kind == "hearth" then
        return L.Format("It takes you to %s", ns.Travel.ShortName(step.to and step.to.name) or "?")
    end
    return step.to and step.to.zone and Host().Show(step.to.zone) or ""
end

--- "About 6 minutes".
function TravelCard.TimeText(plan)
    local minutes = ns.Travel.Minutes(plan)
    if minutes == 1 then return L["About 1 minute"] end
    return L.Format("About %d minutes", minutes)
end

--- The box's three lines for the dial's state: the step, its small line
--- (with how far, from the arrow), and "Step 2 of 4 · About 10 minutes".
function TravelCard.Lines(state)
    local trip = state.trip
    local plan = trip.plan
    local step = trip.step or (plan.steps and plan.steps[1]) or {}
    local title = state.place
    if type(title) ~= "string" or title == "" then title = trip.line or (ns.Travel.StepWords(step)) end
    local sub = state.note
    if type(sub) ~= "string" or sub == "" then sub = trip.small end
    if type(sub) ~= "string" or sub == "" then sub = TravelCard.SubLine(step) end
    local index = trip.index or ((plan.done or 0) + 1)
    local count = trip.count or ((plan.done or 0) + #(plan.steps or {}))
    local where = L.Format("Step %d of %d", index, count) .. " · " .. TravelCard.TimeText(plan)
    return title, sub or "", where
end

--- Shows the box for the dial's state, or hides it.
function TravelCard:Update(state)
    local trip = type(state) == "table" and state.trip
    if not trip or not trip.plan then
        self:Hide()
        return
    end
    local plan = trip.plan
    if self.closedKey then
        if self.closedKey == plan.key then
            if self.frame then self.frame:Hide() end
            return
        end
        self.closedKey = nil
    end
    self.shownPlan = plan.key
    local frame = self:Build()
    self:Hang()

    local title, sub, where = TravelCard.Lines(state)
    local key = title .. "\n" .. sub .. "\n" .. where
    if key ~= self.drawnKey then
        self.drawnKey = key
        self.title:SetText(title)
        self.sub:SetText(sub)
        self.count:SetText(where)
        self:Fit()
    end

    -- The small dial turns with the arrow; a still gold dot when there
    -- is no way to point.
    local pointing = state.mode == "point" and type(state.turn) == "number"
    self.blade:SetShown(pointing)
    self.dot:SetShown(not pointing)
    if pointing then
        local index = TravelCard.FrameFor(state.turn)
        if index ~= self.shownFrame then
            self.shownFrame = index
            pcall(self.blade.SetRotation, self.blade, index / TURNS * 2 * math.pi)
        end
    end
    frame:Show()
end

--- The arrow's words while the box shows: only its name stays, since the
--- box says the step. Nil when the arrow should say them itself.
function TravelCard:Words(state)
    if type(state) ~= "table" or not state.trip then return nil end
    if not Showing(self.frame) then return nil end
    return "", "", "", "muted"
end

function TravelCard:Hide()
    if self.frame then self.frame:Hide() end
    self.drawnKey = nil
end

--- The close gem: only the box goes, for this place. The arrow keeps
--- leading the way step by step.
function TravelCard:Close()
    self.closedKey = self.shownPlan or self.closedKey
    self:Hide()
end

--- Stop: the trip ends and the arrow points straight again, as before.
function TravelCard:Stop()
    if ns.Travel then ns.Travel:StopTrip() end
    self:Hide()
end

--- Opens the world map, on the whole world when the trip crosses the sea.
function TravelCard:ShowOnMap()
    if type(InCombatLockdown) == "function" and InCombatLockdown() then return end
    local state = Host().State()
    local trip = type(state) == "table" and state.trip
    local here = Host().Here()
    local mapID
    local plan = trip and trip.plan
    if plan and here and plan.place and plan.place.continent ~= here.continent then
        mapID = ns.TravelMap and ns.TravelMap.WORLD
    elseif here then
        mapID = ns.Travel.ContinentOf(here.map)
    end
    if type(OpenWorldMap) == "function" then
        pcall(OpenWorldMap, mapID)
    elseif type(ToggleWorldMap) == "function" then
        pcall(ToggleWorldMap)
    end
    return trip
end
