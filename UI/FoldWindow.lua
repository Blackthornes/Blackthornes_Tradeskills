-- UI/FoldWindow.lua
-- The fold gem: a small gold gem beside a window's close gem that folds the
-- window down to its plate and opens it back up (a player asked for a
-- minimize button, the owner picked the mockup, 2026-10-24).
--
-- Folded, the window keeps its place, its width, its rim and its plate; the
-- rest hides and the window is a strip you can still drag. A click on the
-- gem opens it again at the same size. Closing the window, by its close gem,
-- a command or the minimap button, opens it full next time. Nothing is saved.
--
-- With the Blizzard window style the button is the game's own minimize and
-- maximize art when the client has it, else the gem.
--
-- The same file in all five Blackthornes addons (a fix to it belongs in all
-- five), as is tools/make_fold_art.py, which draws Media/Frame/FoldGem.tga.

local ADDON, ns = ...

local FoldWindow = {}
ns.FoldWindow = FoldWindow

local L = ns.L or setmetatable({}, { __index = function(_, key) return key end })

local MEDIA = ([[Interface\AddOns\%s\Media\Frame\]]):format(ADDON)

-- How tall a folded window is: the rim and the plate across its top.
FoldWindow.HEIGHT = 38

-- The gem, and how far it sits left of the close gem's middle.
local GEM = 22
local GAP = 2

-- How near an edge a piece of the window's own art must be to stay on the
-- strip: the rim bands, the fill behind the window, the halo round it.
local SLACK = 7

-- The dark bar and plus on the gem.
local INK = { 0.165, 0.110, 0.024 }
local GOLD = { 0.910, 0.784, 0.451 }

-- The game's own minimize and maximize art, for the Blizzard window style.
local ATLAS = {
    fold = { "RedButton-Condense", "RedButton-Condense-Pressed" },
    open = { "RedButton-Expand", "RedButton-Expand-Pressed" },
    highlight = "RedButton-Highlight",
}

-- Our own fields, read raw: some test frames answer any missing field with
-- a function.
local function Field(object, key)
    if type(object) ~= "table" then return nil end
    return rawget(object, key)
end

local function InCombat()
    return type(InCombatLockdown) == "function" and InCombatLockdown() == true
end

local function Call(object, method, ...)
    local fn = object and object[method]
    if type(fn) ~= "function" then return false end
    return pcall(fn, object, ...)
end

local function Number(object, method)
    local ok, value = Call(object, method)
    if ok and type(value) == "number" then return value end
    return nil
end

local function Protected(frame)
    local ok, protected = Call(frame, "IsProtected")
    return ok and protected == true
end

local function Shown(object)
    local ok, shown = Call(object, "IsShown")
    return ok and shown == true
end

--------------------------------------------------------------------------------
-- What stays on the strip
--------------------------------------------------------------------------------

--- Does a piece of the window's own art stay while it is folded? The rim
--- bands, the fill behind it and the halo round it do: they sit on its edges,
--- span its whole height or lie outside it. Everything else on the window
--- itself hides. All in the window's own units.
function FoldWindow.Keeps(rect, frame)
    if not rect or not frame then return true end
    local left, bottom, width, height = rect[1], rect[2], rect[3], rect[4]
    if type(left) ~= "number" or type(bottom) ~= "number"
        or type(width) ~= "number" or type(height) ~= "number" then
        return true
    end
    local top, right = bottom + height, left + width
    local fLeft, fBottom, fWidth, fHeight = frame[1], frame[2], frame[3], frame[4]
    local fTop, fRight = fBottom + fHeight, fLeft + fWidth

    -- Outside the window altogether: the halo.
    if left >= fRight - 0.5 or right <= fLeft + 0.5 or bottom >= fTop - 0.5 or top <= fBottom + 0.5 then
        return true
    end
    -- Its whole height: the fill behind it and the side rims.
    if top >= fTop - SLACK and bottom <= fBottom + SLACK then return true end
    -- A thin band along the top or the bottom edge: the rims.
    if height <= SLACK and (top >= fTop - SLACK or bottom <= fBottom + SLACK) then return true end
    return false
end

local function Rect(object)
    local ok, left, bottom, width, height = Call(object, "GetRect")
    if not ok then return nil end
    return { left, bottom, width, height }
end

--------------------------------------------------------------------------------
-- Folding
--------------------------------------------------------------------------------

local function State(frame)
    return Field(frame, "blackthornesFold")
end

--- Is this window folded down to its plate?
function FoldWindow:IsFolded(frame)
    local state = State(frame)
    return state ~= nil and state.folded == true
end

-- Hide a piece while folded, and keep it hidden if the window shows it
-- again; remember it, so opening the window brings it back. A piece the
-- window hides itself while folded stays hidden.
local function Watch(state, piece, isFrame)
    if state.watched[piece] then return end
    state.watched[piece] = true

    local function Again(self)
        if state.folded and not state.busy and (not isFrame or Call(self, "GetParent") and self:GetParent() == state.frame) then
            if isFrame and Protected(self) and InCombat() then return end
            state.hidden[self] = isFrame and "frame" or "region"
            state.busy = true
            Call(self, "Hide")
            state.busy = false
        end
    end
    local function Gone(self)
        if state.folded and not state.busy then state.hidden[self] = nil end
    end

    if isFrame and type(piece.HookScript) == "function" then
        pcall(piece.HookScript, piece, "OnShow", Again)
    elseif type(hooksecurefunc) == "function" then
        pcall(hooksecurefunc, piece, "Show", Again)
    end
    if type(hooksecurefunc) == "function" then
        pcall(hooksecurefunc, piece, "Hide", Gone)
        pcall(hooksecurefunc, piece, "SetShown", function(self, on)
            if on then Again(self) else Gone(self) end
        end)
    end
end

local function HideFor(state, piece, isFrame)
    Watch(state, piece, isFrame)
    if not Shown(piece) then return end
    state.hidden[piece] = isFrame and "frame" or "region"
    state.busy = true
    Call(piece, "Hide")
    state.busy = false
end

local function Corners(frame, shown)
    local corners = Field(Field(frame, "titan"), "corners")
    if type(corners) ~= "table" then return end
    -- The bottom two would lie over the top two on a strip this short.
    for index = 3, 4 do
        local corner = corners[index]
        if corner then Call(corner, shown and "Show" or "Hide") end
    end
end

--- Fold the window down to its plate. False when it cannot be now: a
--- button the game guards is showing and a fight is on.
function FoldWindow:Fold(frame)
    local state = State(frame)
    if not state or state.folded or not Shown(frame) then return false end
    if state.canFold and not state.canFold() then return false end

    -- Still rising into place as it opened: land it first, so the place kept
    -- is where it settles.
    local motion = ns.Motion
    if motion and type(motion.Stop) == "function" then pcall(motion.Stop, motion, frame, "open", true) end

    local children = { Call(frame, "GetChildren") }
    table.remove(children, 1)
    if InCombat() then
        for _, child in ipairs(children) do
            if child ~= Field(frame, "titan") and Shown(child) and Protected(child) then return false end
        end
    end

    local left, top = Number(frame, "GetLeft"), Number(frame, "GetTop")
    local width, height = Number(frame, "GetWidth"), Number(frame, "GetHeight")
    if not (left and top and width and height) then return false end

    state.full, state.width = height, width
    state.points = {}
    for index = 1, Number(frame, "GetNumPoints") or 0 do
        state.points[#state.points + 1] = { frame:GetPoint(index) }
    end
    state.hidden = {}

    -- The window's own art, judged where it lies before the window shrinks.
    local frameRect = Rect(frame) or { left, top - height, width, height }
    local regions = { Call(frame, "GetRegions") }
    table.remove(regions, 1)
    for _, region in ipairs(regions) do
        if Shown(region) and not FoldWindow.Keeps(Rect(region), frameRect) then
            HideFor(state, region, false)
        end
    end
    for _, child in ipairs(children) do
        if child ~= Field(frame, "titan") then HideFor(state, child, true) end
    end

    state.folded = true
    state.busy = true
    Call(frame, "ClearAllPoints")
    Call(frame, "SetPoint", "TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
    Call(frame, "SetWidth", width)
    Call(frame, "SetHeight", FoldWindow.HEIGHT)
    state.busy = false
    state.left, state.top = left, top
    Corners(frame, false)

    FoldWindow.Update(state)
    if state.onToggle then pcall(state.onToggle, true) end
    return true
end

--- Open a folded window back up, at the size and place it had, or where it
--- was dragged to while folded.
function FoldWindow:Unfold(frame)
    local state = State(frame)
    if not state or not state.folded then return false end

    local left, top = Number(frame, "GetLeft"), Number(frame, "GetTop")
    local moved = not (left and top and state.left and state.top
        and math.abs(left - state.left) < 0.5 and math.abs(top - state.top) < 0.5)

    state.busy = true
    if not moved and #state.points > 0 then
        Call(frame, "ClearAllPoints")
        for _, point in ipairs(state.points) do Call(frame, "SetPoint", unpack(point)) end
    elseif moved and left and top then
        -- Dragged: the game may have pinned it by another corner, so pin it by
        -- its top left again, or it would grow upwards.
        Call(frame, "ClearAllPoints")
        Call(frame, "SetPoint", "TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
    end
    Call(frame, "SetWidth", state.width)
    Call(frame, "SetHeight", state.full)
    state.folded = false

    for piece, kind in pairs(state.hidden) do
        local isFrame = kind == "frame"
        local stillOurs = not isFrame or (Call(piece, "GetParent") and piece:GetParent() == frame)
        if stillOurs then
            if isFrame and Protected(piece) and InCombat() then
                FoldWindow.waiting[piece] = frame
            else
                Call(piece, "Show")
            end
        end
    end
    state.hidden = {}
    state.busy = false
    Corners(frame, true)

    FoldWindow.Update(state)
    if state.onToggle then pcall(state.onToggle, false) end
    return true
end

function FoldWindow:Toggle(frame)
    if self:IsFolded(frame) then return self:Unfold(frame) end
    return self:Fold(frame)
end

-- Buttons the game guards that a fight kept hidden come back once it ends.
FoldWindow.waiting = {}

--------------------------------------------------------------------------------
-- The gem
--------------------------------------------------------------------------------

local function HasAtlas(name)
    local textures = C_Texture
    if type(textures) ~= "table" or type(textures.GetAtlasInfo) ~= "function" then return false end
    local ok, info = pcall(textures.GetAtlasInfo, name)
    return ok and info ~= nil
end

local function Bar(button, layer)
    local bar = button:CreateTexture(nil, layer or "OVERLAY", nil, 2)
    bar:SetColorTexture(INK[1], INK[2], INK[3], 1)
    return bar
end

--- The gold gem with its glow, a lit copy for the mouse, and a bar (open)
--- or a plus (folded) drawn from plain colour on its face.
local function Gem(button)
    local glow = button:CreateTexture(nil, "BACKGROUND")
    glow:SetTexture(MEDIA .. "Glow")
    glow:SetPoint("CENTER")
    glow:SetSize(GEM * 2.2, GEM * 2.2)
    glow:SetVertexColor(GOLD[1], GOLD[2], GOLD[3], 1)
    pcall(glow.SetBlendMode, glow, "ADD")

    local gem = button:CreateTexture(nil, "ARTWORK")
    gem:SetTexture(MEDIA .. "FoldGem")
    gem:SetAllPoints(button)

    local lit = button:CreateTexture(nil, "ARTWORK", nil, 1)
    lit:SetTexture(MEDIA .. "FoldGem")
    lit:SetAllPoints(button)
    pcall(lit.SetBlendMode, lit, "ADD")

    local across = Bar(button)
    across:SetSize(10, 3)
    across:SetPoint("CENTER", 0, 0)
    local down = Bar(button)
    down:SetSize(3, 10)
    down:SetPoint("CENTER", 0, 0)

    local function Light(p)
        glow:SetAlpha(0.25 + 0.55 * p)
        lit:SetAlpha(0.45 * p)
    end
    Light(0)

    button.Light = Light
    button.glyph = { across = across, down = down }
end

local function Atlas(button)
    for _, name in ipairs({ ATLAS.fold[1], ATLAS.fold[2], ATLAS.open[1], ATLAS.open[2], ATLAS.highlight }) do
        if not HasAtlas(name) then return false end
    end
    if not (Call(button, "SetNormalAtlas", ATLAS.fold[1])
        and Call(button, "SetPushedAtlas", ATLAS.fold[2])
        and Call(button, "SetHighlightAtlas", ATLAS.highlight, "ADD")) then
        return false
    end
    button.atlas = true
    return true
end

--- Show the gem as the window stands: a bar while open, a plus while folded.
function FoldWindow.Update(state)
    local button = state and state.button
    if not button then return end
    if Field(button, "atlas") then
        local art = state.folded and ATLAS.open or ATLAS.fold
        Call(button, "SetNormalAtlas", art[1])
        Call(button, "SetPushedAtlas", art[2])
    elseif Field(button, "glyph") then
        Call(button.glyph.down, state.folded and "Show" or "Hide")
    end
    if Field(button, "hovered") and GameTooltip then FoldWindow.Tooltip(button, state) end
end

function FoldWindow.Tooltip(button, state)
    if not GameTooltip then return end
    GameTooltip:SetOwner(button, "ANCHOR_TOP")
    GameTooltip:SetText(state.folded and L["Expand this window"] or L["Collapse this window"], 1, 1, 1)
    GameTooltip:Show()
end

--- Give a dressed window (Titanforged:Dress, or the Blizzard style's) its
--- fold gem, left of its close gem.
--
-- opts:
--   onToggle  called with true as it folds and false as it opens, so the
--             window can stop or start drawing its lists
--   canFold   a function; while it answers false the gem does nothing
--
-- Returns the button.
function FoldWindow:Add(frame, opts)
    local trim = Field(frame, "titan")
    if not trim or State(frame) then return State(frame) and State(frame).button end
    opts = opts or {}

    local state = {
        frame = frame, folded = false, hidden = {}, watched = {}, points = {},
        onToggle = opts.onToggle, canFold = opts.canFold,
    }
    frame.blackthornesFold = state

    local button = CreateFrame("Button", nil, trim)
    state.button = button

    local close = Field(trim, "closeButton")
    local size = GEM
    if Field(trim, "blizzard") then
        local closeSize = close and Number(close, "GetWidth")
        if closeSize and closeSize > 0 then size = closeSize end
    end
    button:SetSize(size, size)
    if close then
        local closeSize = Number(close, "GetWidth") or 26
        button:SetPoint("CENTER", close, "CENTER", -(closeSize / 2 + size / 2 + GAP), 0)
    else
        button:SetPoint("CENTER", trim, "TOPRIGHT", -8, -8)
    end

    if not (Field(trim, "blizzard") and Atlas(button)) then Gem(button) end

    button:SetScript("OnEnter", function(self)
        self.hovered = true
        if Field(self, "Light") then
            if ns.Motion and type(ns.Motion.Blend) == "function" then ns.Motion:Blend(self, "hover", 1, 0.12, self.Light) else self.Light(1) end
        end
        FoldWindow.Tooltip(self, state)
    end)
    button:SetScript("OnLeave", function(self)
        self.hovered = false
        if Field(self, "Light") then
            if ns.Motion and type(ns.Motion.Blend) == "function" then ns.Motion:Blend(self, "hover", 0, 0.18, self.Light) else self.Light(0) end
        end
        if GameTooltip then GameTooltip:Hide() end
    end)
    button:SetScript("OnClick", function() FoldWindow:Toggle(frame) end)

    -- The window's own code may size it while it is folded (a tab that needs
    -- more room): that is the size it opens back up to.
    if type(hooksecurefunc) == "function" then
        pcall(hooksecurefunc, frame, "SetHeight", function(self, height)
            if state.folded and not state.busy and type(height) == "number" then
                state.full = height
                state.busy = true
                Call(self, "SetHeight", FoldWindow.HEIGHT)
                state.busy = false
            end
        end)
        pcall(hooksecurefunc, frame, "SetWidth", function(_, width)
            if state.folded and not state.busy and type(width) == "number" then state.width = width end
        end)
        pcall(hooksecurefunc, frame, "SetSize", function(self, width, height)
            if state.folded and not state.busy and type(width) == "number" then
                state.width, state.full = width, height or width
                state.busy = true
                Call(self, "SetHeight", FoldWindow.HEIGHT)
                state.busy = false
            end
        end)
    end

    -- Closed while folded, it opens full next time. Only a close (a Hide
    -- call: the close gem, Escape, a command), never the whole interface
    -- going out of sight, and not lost if the window sets its own OnHide.
    if type(hooksecurefunc) == "function" then
        pcall(hooksecurefunc, frame, "Hide", function(self) FoldWindow:Unfold(self) end)
    end

    FoldWindow.Update(state)
    return button
end

-- One listener for the end of a fight, for guarded buttons it held back.
if type(CreateFrame) == "function" then
    local ok, listener = pcall(CreateFrame, "Frame")
    if ok and listener and listener.RegisterEvent then
        pcall(listener.RegisterEvent, listener, "PLAYER_REGEN_ENABLED")
        listener:SetScript("OnEvent", function()
            for piece, frame in pairs(FoldWindow.waiting) do
                FoldWindow.waiting[piece] = nil
                if not FoldWindow:IsFolded(frame) and Call(piece, "GetParent") and piece:GetParent() == frame then
                    Call(piece, "Show")
                end
            end
        end)
    end
end
