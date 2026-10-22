-- Blackthornes Tradeskills -- UI/Titanforged.lua
-- The house window frame: the game's own window shape with the light turned
-- up (picked from the mockups, 2026-10-04, "Titanforged").
--
-- A gold metal rim with corner gems, a round portrait holding the addon's
-- emblem in the top left, the window's name on a plate across the top edge
-- and a red close gem in the top right. A glint slides along the rim now and
-- then, and a light runs round the portrait as the window opens.
--
-- The straight edges are colour gradients, so they stay sharp at any size;
-- the shapes are Media/Frame/*.tga, drawn by tools/make_frame_art.py. The
-- "Window effects" setting holds the movement: Subtle keeps the portrait's
-- light and drops the glint, Off keeps both still.
--
-- Shared with Blackthornes Farmer, Equipment and Pets: they copy this file,
-- the art and the tool, and change only the emblem the tool draws.

local ADDON, ns = ...

local Titanforged = {}
ns.Titanforged = Titanforged

local Theme = ns.Theme

-- The words through the addon's translation table where it has one (ns.L,
-- Locale/Locale.lua), else in English, so this file stays the same in all.
local L = ns.L or setmetatable({}, { __index = function(_, key) return key end })

local MEDIA = ([[Interface\AddOns\%s\Media\Frame\]]):format(ADDON)
Titanforged.MEDIA = MEDIA

-- Sizes, in the window's own units.
local RIM = 4              -- the metal band inside the window's edge
local CORNER = 32          -- a corner piece, reaching CORNER_OUT past the edge
local CORNER_OUT = 3
local PORTRAIT = 68        -- the round portrait, reaching PORTRAIT_OUT past the corner
local PORTRAIT_OUT = 20
local EMBLEM = 36
local PLATE_HEIGHT = 30    -- the title plate, centred on the top edge
local PLATE_CAP = 15       -- each pointed end of the plate, kept unstretched
local CLOSE = 26           -- the close gem, centred near the top right corner
local CLOSE_OUT = 8

-- How long the glint takes to cross, and the pause before the next one.
local GLINT_TIME = 1.6
local GLINT_REST = 7

-- Metal, lit from the top left.
local METAL_HI = { 0.984, 0.902, 0.651 }   -- #FBE6A6
local METAL = { 0.784, 0.643, 0.302 }      -- #C8A44D
local METAL_MID = { 0.690, 0.545, 0.235 }  -- #B08B3C
local METAL_LO = { 0.357, 0.267, 0.086 }   -- #5B4416
local EDGE = { 0.020, 0.024, 0.031 }       -- #050608
local LIGHT = { 0.945, 0.831, 0.533 }      -- #F1D488

--- Shade a texture from one colour to another ("VERTICAL" runs bottom to
--- top, "HORIZONTAL" left to right). The middle of the two where the client
--- draws no gradient.
function Titanforged.Gradient(texture, orientation, from, to, fromAlpha, toAlpha)
    texture:SetColorTexture(1, 1, 1, 1)
    local ok = false
    if type(CreateColor) == "function" and type(texture.SetGradient) == "function" then
        ok = pcall(texture.SetGradient, texture, orientation,
            CreateColor(from[1], from[2], from[3], fromAlpha or 1),
            CreateColor(to[1], to[2], to[3], toAlpha or 1))
    end
    if not ok then
        texture:SetColorTexture((from[1] + to[1]) / 2, (from[2] + to[2]) / 2,
            (from[3] + to[3]) / 2, ((fromAlpha or 1) + (toAlpha or 1)) / 2)
    end
    return ok
end

local Gradient = Titanforged.Gradient

local function Additive(texture)
    pcall(texture.SetBlendMode, texture, "ADD")
end

local function Art(parent, file, layer, sublevel)
    local texture = parent:CreateTexture(nil, layer or "ARTWORK", nil, sublevel)
    texture:SetTexture(MEDIA .. file)
    return texture
end

--------------------------------------------------------------------------------
-- The rim
--------------------------------------------------------------------------------

--- One side of the rim: a black hairline at the window's edge, the metal
--- band, a black line inside it and a thin gold light inside that.
local function Side(frame, side)
    local bands = {}

    local function Band(offset, thickness, sublevel)
        local band = frame:CreateTexture(nil, "BORDER", nil, sublevel)
        if side == "TOP" or side == "BOTTOM" then
            local y = side == "TOP" and -offset or offset
            band:SetPoint(side .. "LEFT", offset, y)
            band:SetPoint(side .. "RIGHT", -offset, y)
            band:SetHeight(thickness)
        else
            local x = side == "LEFT" and offset or -offset
            band:SetPoint("TOP" .. side, x, -offset)
            band:SetPoint("BOTTOM" .. side, x, offset)
            band:SetWidth(thickness)
        end
        bands[#bands + 1] = band
        return band
    end

    Band(0, 1, 1):SetColorTexture(EDGE[1], EDGE[2], EDGE[3], 1)

    local metal = Band(1, RIM - 1, 2)
    if side == "TOP" then
        Gradient(metal, "VERTICAL", METAL, METAL_HI)
    elseif side == "BOTTOM" then
        Gradient(metal, "VERTICAL", METAL_LO, METAL_MID)
    elseif side == "LEFT" then
        Gradient(metal, "HORIZONTAL", METAL_HI, METAL_MID)
    else
        Gradient(metal, "HORIZONTAL", METAL_MID, METAL_LO)
    end

    Band(RIM, 1, 3):SetColorTexture(EDGE[1], EDGE[2], EDGE[3], 1)
    Band(RIM + 1, 1, 4):SetColorTexture(LIGHT[1], LIGHT[2], LIGHT[3], 0.45)

    return bands
end

-- Each corner is the top left piece turned by its texture coordinates:
-- left, right, top, bottom.
local CORNERS = {
    { "TOPLEFT", -1, 1, { 0, 1, 0, 1 } },
    { "TOPRIGHT", 1, 1, { 1, 0, 0, 1 } },
    { "BOTTOMRIGHT", 1, -1, { 1, 0, 1, 0 } },
    { "BOTTOMLEFT", -1, -1, { 0, 1, 1, 0 } },
}

--------------------------------------------------------------------------------
-- The pieces on top
--------------------------------------------------------------------------------

local function Plate(trim, title)
    local plate = CreateFrame("Frame", nil, trim)
    plate:SetHeight(PLATE_HEIGHT)
    plate:SetPoint("CENTER", trim, "TOP", 0, 0)

    local left = Art(plate, "TitlePlate", "ARTWORK")
    left:SetPoint("TOPLEFT")
    left:SetPoint("BOTTOMLEFT")
    left:SetWidth(PLATE_CAP)
    left:SetTexCoord(0, 40 / 256, 0, 1)

    local right = Art(plate, "TitlePlate", "ARTWORK")
    right:SetPoint("TOPRIGHT")
    right:SetPoint("BOTTOMRIGHT")
    right:SetWidth(PLATE_CAP)
    right:SetTexCoord(216 / 256, 1, 0, 1)

    local middle = Art(plate, "TitlePlate", "ARTWORK")
    middle:SetPoint("TOPLEFT", left, "TOPRIGHT")
    middle:SetPoint("BOTTOMRIGHT", right, "BOTTOMLEFT")
    middle:SetTexCoord(40 / 256, 216 / 256, 0, 1)

    -- A soft gold light behind the name; the game cannot make text glow.
    local glow = Art(plate, "Glow", "ARTWORK", 1)
    glow:SetPoint("TOPLEFT", 10, -4)
    glow:SetPoint("BOTTOMRIGHT", -10, 4)
    glow:SetVertexColor(Theme.Unpack("accent"))
    glow:SetAlpha(0.35)
    Additive(glow)

    local label = Theme.CreateLabel(plate, "title", "accent", "CENTER")
    label:SetPoint("CENTER", 0, 0)
    label:SetTextColor(LIGHT[1], LIGHT[2], LIGHT[3], 1)
    pcall(label.SetShadowColor, label, 0, 0, 0, 1)
    pcall(label.SetShadowOffset, label, 1, -1)
    plate.label = label

    --- Name the window, sizing the plate to the name.
    function plate:SetTitle(text)
        label:SetText(text or "")
        local width = Theme.TextWidth(label) or (#(text or "") * 8)
        self:SetWidth(math.max(120, math.ceil(width) + 2 * PLATE_CAP + 28))
    end

    plate:SetTitle(title)
    return plate
end

local function Portrait(trim)
    local portrait = CreateFrame("Frame", nil, trim)
    portrait:SetSize(PORTRAIT, PORTRAIT)
    portrait:SetPoint("TOPLEFT", trim, "TOPLEFT", -PORTRAIT_OUT, PORTRAIT_OUT)

    local halo = Art(portrait, "Glow", "BACKGROUND")
    halo:SetPoint("CENTER")
    halo:SetSize(PORTRAIT * 1.6, PORTRAIT * 1.6)
    halo:SetVertexColor(Theme.Unpack("accent"))
    halo:SetAlpha(0.45)
    Additive(halo)

    local ring = Art(portrait, "Portrait", "ARTWORK")
    ring:SetAllPoints(portrait)

    local emblem = Art(portrait, "Emblem", "ARTWORK", 2)
    emblem:SetSize(EMBLEM, EMBLEM)
    emblem:SetPoint("CENTER", 0, 1)

    local sweep = Art(portrait, "PortraitSweep", "OVERLAY")
    sweep:SetAllPoints(portrait)
    Additive(sweep)
    sweep:SetAlpha(0)

    portrait.halo, portrait.sweep = halo, sweep
    return portrait
end

local function CloseGem(trim, onClick)
    local close = CreateFrame("Button", nil, trim)
    close:SetSize(CLOSE, CLOSE)
    close:SetPoint("CENTER", trim, "TOPRIGHT", -CLOSE_OUT, -CLOSE_OUT)

    local glow = Art(close, "Glow", "BACKGROUND")
    glow:SetPoint("CENTER")
    glow:SetSize(CLOSE * 2.2, CLOSE * 2.2)
    glow:SetVertexColor(Theme.Unpack("loss"))
    Additive(glow)

    close.glow = glow

    local gem = Art(close, "CloseGem", "ARTWORK")
    gem:SetAllPoints(close)

    -- The same gem again, added over itself: it brightens under the mouse.
    local lit = Art(close, "CloseGem", "ARTWORK", 1)
    lit:SetAllPoints(close)
    Additive(lit)

    local function Light(p)
        glow:SetAlpha(0.25 + 0.55 * p)
        lit:SetAlpha(0.45 * p)
    end
    Light(0)

    close:SetScript("OnEnter", function(self)
        if ns.Motion then ns.Motion:Blend(self, "hover", 1, 0.12, Light) else Light(1) end
        if GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(L["Close"], 1, 1, 1)
            GameTooltip:Show()
        end
    end)
    close:SetScript("OnLeave", function(self)
        if ns.Motion then ns.Motion:Blend(self, "hover", 0, 0.18, Light) else Light(0) end
        if GameTooltip then GameTooltip:Hide() end
    end)
    close:SetScript("OnClick", function() if onClick then onClick() end end)

    return close
end

-- Pets' and Equipment's arrows wear the same gem beside their plates.
Titanforged.CloseGem = CloseGem

--------------------------------------------------------------------------------
-- Dressing a frame
--------------------------------------------------------------------------------

--- Put the frame on `frame`.
--
-- opts:
--   title    the window's name, on the plate across the top (none: no plate)
--   portrait true for the round portrait with the emblem
--   close    a function: the red close gem, which calls it
--   level    how far above `frame` the corners and portrait sit (default 20)
--
-- Returns the trim: a frame over the window holding the pieces, with
-- .plate, .portrait and .closeButton when made. The rim and the soft light
-- along the top are drawn on `frame` itself.
function Titanforged:Dress(frame, opts)
    -- The Blizzard window style (UI/BlizzardLook.lua) frames it instead,
    -- with the same trim, so callers never need to know which is on.
    local Look = ns.BlizzardLook
    if Look and Look.On() then return Look.Dress(frame, opts) end

    opts = opts or {}

    for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do Side(frame, side) end

    -- A soft gold light falling from the top, as from the plate.
    local light = frame:CreateTexture(nil, "BACKGROUND", nil, 2)
    light:SetPoint("TOPLEFT", RIM + 2, -(RIM + 2))
    light:SetPoint("TOPRIGHT", -(RIM + 2), -(RIM + 2))
    light:SetHeight(90)
    Theme.SetGradientAlpha(light, "VERTICAL", "accent", 0, 0.10)

    -- The pieces ride on a frame of their own, above the window's contents,
    -- and take no clicks except the close gem's.
    local trim = CreateFrame("Frame", nil, frame)
    trim:SetAllPoints(frame)
    local ok, level = pcall(frame.GetFrameLevel, frame)
    if ok and type(level) == "number" then trim:SetFrameLevel(level + (opts.level or 20)) end
    pcall(trim.EnableMouse, trim, false)

    trim.corners = {}
    for _, spec in ipairs(CORNERS) do
        local corner = Art(trim, "Corner", "ARTWORK")
        corner:SetSize(CORNER, CORNER)
        corner:SetPoint(spec[1], frame, spec[1], spec[2] * CORNER_OUT, spec[3] * CORNER_OUT)
        corner:SetTexCoord(unpack(spec[4]))
        trim.corners[#trim.corners + 1] = corner
    end

    -- The glint, waiting at the left end of the top edge.
    local glint = Art(trim, "Glow", "OVERLAY")
    glint:SetSize(150, 8)
    glint:SetVertexColor(LIGHT[1], LIGHT[2], LIGHT[3], 1)
    Additive(glint)
    glint:SetAlpha(0)
    trim.glint = glint

    if opts.title then trim.plate = Plate(trim, opts.title) end
    if opts.portrait then trim.portrait = Portrait(trim) end
    if opts.close then trim.closeButton = CloseGem(trim, opts.close) end

    frame.titan = trim

    -- The glint comes and goes with the window.
    if frame.HookScript then
        frame:HookScript("OnShow", function(self) Titanforged:StartGlint(self) end)
        frame:HookScript("OnHide", function(self) Titanforged:StopGlint(self) end)
    end

    return trim
end

--- How far out a dressed frame's pieces reach past its edges, for
--- SetClampRectInsets: left, right, top, bottom.
function Titanforged.Reach(trim)
    local left = trim and trim.portrait and PORTRAIT_OUT or CORNER_OUT
    local top = trim and (trim.portrait and PORTRAIT_OUT or trim.plate and PLATE_HEIGHT / 2) or CORNER_OUT
    return left, CORNER_OUT + (trim and trim.closeButton and CLOSE / 2 or 0), top, CORNER_OUT
end

--------------------------------------------------------------------------------
-- Movement
--------------------------------------------------------------------------------

--- The light round the portrait as the window opens. Call as it opens.
function Titanforged:Opened(frame)
    local trim = frame and frame.titan
    local sweep = trim and trim.portrait and trim.portrait.sweep
    local Motion = ns.Motion
    if not sweep or not Motion then return end

    if Motion.Level() == "off" then
        sweep:SetAlpha(0)
        return
    end

    Motion:Run(sweep, "sweep", 1.1, function(p)
        pcall(sweep.SetRotation, sweep, -p * 2 * math.pi)
        -- In fast, out slowly as it comes round.
        sweep:SetAlpha(p < 0.15 and p / 0.15 or (1 - p) / 0.85)
    end, { ease = Motion.EaseOut, done = function() sweep:SetAlpha(0) end })

    local halo = trim.portrait.halo
    Motion:Run(halo, "flare", 0.9, function(p) halo:SetAlpha(0.9 - 0.45 * p) end)
end

--- Send a glint along the top edge, then another after a rest, while the
--- frame shows and the window effects are Full.
function Titanforged:StartGlint(frame, delay)
    local trim = frame and frame.titan
    local glint = trim and trim.glint
    local Motion = ns.Motion
    if not glint or not Motion or Motion.Level() ~= "full" then return end

    local width = frame:GetWidth()
    if type(width) ~= "number" or width <= 0 then return end

    Motion:Run(glint, "glint", GLINT_TIME, function(p)
        glint:ClearAllPoints()
        glint:SetPoint("CENTER", frame, "TOPLEFT", -40 + (width + 80) * p, -RIM / 2)
        glint:SetAlpha(math.sin(math.pi * p) * 0.9)
    end, {
        delay = delay or 1.2,
        ease = false,
        done = function()
            glint:SetAlpha(0)
            if frame:IsShown() then Titanforged:StartGlint(frame, GLINT_REST) end
        end,
    })
end

function Titanforged:StopGlint(frame)
    local glint = frame and frame.titan and frame.titan.glint
    if not glint or not ns.Motion then return end
    ns.Motion:Stop(glint, "glint")
    glint:SetAlpha(0)
end
