-- Blackthornes Tradeskills -- UI/BlizzardLook.lua
-- The Blizzard window style: a choice beside Titanforged (asked 2026-10-10)
-- for players who would rather the addon's windows looked like the game's
-- own. Settings > Window style; read once at login, so a change waits for
-- /reload, as Text size does.
--
-- Titanforged stays the default. Picked, this style:
--   * swaps the palette for the game's: grey metal, the game's gold for
--     labels and headings, plain list rows with a blue bar for the one
--     picked, and no glows round windows and buttons;
--   * frames windows in a plain silver rim with a title tab across the top,
--     a silver-ringed portrait and the game's own close button
--     (UIPanelCloseButton);
--   * dresses buttons, tick boxes, the tabs below the window and scroll
--     thumbs in the game's own art (Interface\Buttons and friends).
--
-- It never touches or moves a Blizzard frame: it only uses the game's
-- templates and texture files on this addon's own frames. Each piece of
-- art is checked once (Look.HasArt); a client without it keeps that widget
-- in the house look rather than drawing it blank. /bts probe lists what the
-- client has.
--
-- The same file is in Blackthornes Farmer, Equipment and Pets (only the
-- first line differs); a fix to it belongs in all four.

local ADDON, ns = ...

local Look = {}
ns.BlizzardLook = Look

Look.STYLES = { titanforged = true, blizzard = true }

-- The game's own art. Every file here has shipped with the client since the
-- original game and is still drawn by its stock templates.
Look.ART = {
    button = [[Interface\Buttons\UI-Panel-Button-Up]],
    buttonDown = [[Interface\Buttons\UI-Panel-Button-Down]],
    buttonDisabled = [[Interface\Buttons\UI-Panel-Button-Disabled]],
    buttonHighlight = [[Interface\Buttons\UI-Panel-Button-Highlight]],
    check = [[Interface\Buttons\UI-CheckBox-Up]],
    checkHighlight = [[Interface\Buttons\UI-CheckBox-Highlight]],
    checkTick = [[Interface\Buttons\UI-CheckBox-Check]],
    close = [[Interface\Buttons\UI-Panel-MinimizeButton-Up]],
    closeDown = [[Interface\Buttons\UI-Panel-MinimizeButton-Down]],
    closeHighlight = [[Interface\Buttons\UI-Panel-MinimizeButton-Highlight]],
    tab = [[Interface\PaperDollInfoFrame\UI-Character-InActiveTab]],
    tabActive = [[Interface\PaperDollInfoFrame\UI-Character-ActiveTab]],
    tabHighlight = [[Interface\PaperDollInfoFrame\UI-Character-Tab-Highlight]],
    knob = [[Interface\Buttons\UI-ScrollBar-Knob]],
}

-- The order /bts probe lists them in.
Look.ART_ORDER = {
    "button", "buttonDown", "buttonDisabled", "buttonHighlight",
    "check", "checkHighlight", "checkTick",
    "close", "closeDown", "closeHighlight",
    "tab", "tabActive", "tabHighlight", "knob",
}

-- The game's colours, laid over the house palette when this style is on.
Look.PALETTE = {
    window      = { 0.090, 0.090, 0.098 },
    panel       = { 0.110, 0.110, 0.118 },
    header      = { 0.141, 0.141, 0.149 },
    row         = { 0.157, 0.157, 0.165 },
    rowAlt      = { 0.125, 0.125, 0.133 },
    rowHover    = { 0.220, 0.220, 0.231 },
    rowActive   = { 0.180, 0.235, 0.361 },
    -- Plain rows: no bands, the game's gold wash under the mouse and its
    -- blue bar under the row picked.
    glass       = { 0.035, 0.035, 0.039 },
    glassAlt    = { 0.035, 0.035, 0.039 },
    glassHover  = { 0.110, 0.098, 0.047 },
    glassActive = { 0.137, 0.235, 0.431 },
    border      = { 0.290, 0.290, 0.306 },
    borderLit   = { 0.471, 0.471, 0.490 },
    accent      = { 1.000, 0.820, 0.000 },   -- the game's gold (GameFontNormal)
    accentHi    = { 1.000, 1.000, 1.000 },   -- its highlight white
    gilt        = { 1.000, 0.820, 0.000 },
    well        = { 0.035, 0.035, 0.039 },
    metal       = { 0.471, 0.471, 0.490 },
    text        = { 1.000, 1.000, 1.000 },
    muted       = { 0.780, 0.780, 0.780 },
    dim         = { 0.540, 0.540, 0.540 },
    loss        = { 1.000, 0.250, 0.200 },
}

-- Silver metal for the window's rim, lit from the top left.
local SILVER_HI = { 0.800, 0.800, 0.820 }
local SILVER = { 0.560, 0.560, 0.580 }
local SILVER_LO = { 0.220, 0.220, 0.235 }
local EDGE = { 0.020, 0.020, 0.024 }
local GOLD = { 1.000, 0.820, 0.000 }

local RIM = 4
local TITLE_HEIGHT = 24
local PORTRAIT = 62
local PORTRAIT_OUT = 18
local EMBLEM = 36
local CLOSE = 32

--------------------------------------------------------------------------------
-- Which style
--------------------------------------------------------------------------------

local style

--- The saved choice: Tradeskills keeps it through Config, the other three in
--- their flat saved table.
local function Saved()
    if ns.Config and type(ns.Config.Get) == "function" then
        local ok, value = pcall(ns.Config.Get, ns.Config, "windowStyle")
        if ok and value ~= nil then return value end
    end
    if type(ns.db) == "table" then return rawget(ns.db, "windowStyle") end
end

--- "titanforged" or "blizzard". Read once, the first time it is asked for
--- after the saved settings are in, so what is drawn never mixes the two.
function Look.Style()
    if style then return style end
    if not ns.db then return "titanforged" end
    style = Saved() == "blizzard" and "blizzard" or "titanforged"
    if style == "blizzard" then Look.Apply() end
    return style
end

-- Read as the saved settings arrive, before any window is built, so every
-- colour drawn is the style's. The addon's own loader runs first: it
-- registered for the event before this file loaded.
do
    local ok, watcher = pcall(CreateFrame, "Frame")
    if ok and watcher and watcher.RegisterEvent then
        pcall(watcher.RegisterEvent, watcher, "ADDON_LOADED")
        watcher:SetScript("OnEvent", function(self, _, name)
            if name ~= ADDON then return end
            Look.Style()
            pcall(self.UnregisterEvent, self, "ADDON_LOADED")
        end)
    end
end

--- Is the Blizzard style on?
function Look.On()
    return Look.Style() == "blizzard"
end

--- What the saved setting says now, which may differ from what is drawn
--- until /reload.
function Look.Wanted()
    return Saved() == "blizzard" and "blizzard" or "titanforged"
end

--- Lay the game's colours over the palette and put out the glows. Runs once.
function Look.Apply()
    local Theme = ns.Theme
    if not Theme or Look.applied then return end
    Look.applied = true

    if type(Theme.colors) == "table" then
        for key, color in pairs(Look.PALETTE) do
            if Theme.colors[key] then Theme.colors[key] = { color[1], color[2], color[3] } end
        end
    end

    -- The game's windows have no glow round them or their buttons.
    if type(Theme.SetHalo) == "function" then
        local setHalo = Theme.SetHalo
        Theme.SetHalo = function(frame, _, key)
            setHalo(frame, 0, key)
        end
    end
end

--------------------------------------------------------------------------------
-- The game's art
--------------------------------------------------------------------------------

local known = {}
local tester

--- Does the client have this texture file? Asked once per file. A client
--- that cannot say is taken at its word that it has it.
function Look.HasArt(path)
    if known[path] ~= nil then return known[path] end
    local found = true
    pcall(function()
        tester = tester or CreateFrame("Frame")
        local texture = tester:CreateTexture()
        local set = texture:SetTexture(path)
        if set == false then found = false return end
        if type(texture.GetTextureFileID) == "function" then
            local id = texture:GetTextureFileID()
            if id == nil or id == 0 then found = false end
        end
        texture:SetTexture(nil)
    end)
    known[path] = found
    return found
end

--- Has the client every file in `names` (keys of Look.ART)?
local function HasAll(...)
    for index = 1, select("#", ...) do
        if not Look.HasArt(Look.ART[select(index, ...)]) then return false end
    end
    return true
end

--- Put a texture out of sight for good: code that shows it again (a tick
--- drawn, a light raised) leaves it see-through.
local function Quiet(texture)
    if texture and type(texture.SetAlpha) == "function" then texture:SetAlpha(0) end
end

local function QuietAll(list)
    if type(list) ~= "table" then return end
    for _, texture in ipairs(list) do Quiet(texture) end
end

--- Three pieces of one texture across `frame`: a fixed cap at each end and
--- the middle stretched, as the game's own buttons and tabs are drawn.
--- coords: { left, leftEnd, rightStart, right, top, bottom }.
local function ThreeSlice(frame, layer, sublevel, cap, coords, inset)
    inset = inset or 0
    local pieces = {}
    for index = 1, 3 do pieces[index] = frame:CreateTexture(nil, layer, nil, sublevel) end
    local left, middle, right = pieces[1], pieces[2], pieces[3]

    left:SetPoint("TOPLEFT", 0, -inset)
    left:SetPoint("BOTTOMLEFT", 0, inset)
    left:SetWidth(cap)
    right:SetPoint("TOPRIGHT", 0, -inset)
    right:SetPoint("BOTTOMRIGHT", 0, inset)
    right:SetWidth(cap)
    middle:SetPoint("TOPLEFT", left, "TOPRIGHT")
    middle:SetPoint("BOTTOMRIGHT", right, "BOTTOMLEFT")

    local slices = { pieces = pieces, coords = coords }

    function slices:SetFile(path)
        local c = self.coords
        left:SetTexture(path)
        left:SetTexCoord(c[1], c[2], c[5], c[6])
        middle:SetTexture(path)
        middle:SetTexCoord(c[2], c[3], c[5], c[6])
        right:SetTexture(path)
        right:SetTexCoord(c[3], c[4], c[5], c[6])
    end

    function slices:SetShown(on)
        for _, piece in ipairs(pieces) do piece:SetShown(on) end
    end

    function slices:SetBlend(mode)
        for _, piece in ipairs(pieces) do pcall(piece.SetBlendMode, piece, mode) end
    end

    return slices
end

-- UIPanelButtonTemplate's cut of UI-Panel-Button-*.
local BUTTON_COORDS = { 0, 0.09375, 0.53125, 0.625, 0, 0.6875 }
-- CharacterFrameTabButtonTemplate's cut of UI-Character-*Tab.
local TAB_COORDS = { 0, 0.15625, 0.84375, 1, 0, 1 }

--------------------------------------------------------------------------------
-- Buttons
--------------------------------------------------------------------------------

--- Dress a house button (Widgets.CreateButton) in UIPanelButtonTemplate's
--- red: up, down while held, grey when it cannot be pressed, and the game's
--- light under the mouse. Its label keeps the house code, now in the game's
--- gold turning white under the mouse.
function Look.Button(button)
    if not Look.On() or not button then return false end
    -- A button sitting over the game world keeps its own solid face.
    if rawget(button, "baseColor") then return false end
    if not HasAll("button", "buttonDown", "buttonDisabled", "buttonHighlight") then return false end

    Quiet(rawget(button, "background"))
    QuietAll(rawget(button, "borderTextures"))
    Quiet(rawget(button, "sheen"))
    QuietAll(rawget(button, "bevel"))

    local face = ThreeSlice(button, "BACKGROUND", 1, 12, BUTTON_COORDS)
    local light = ThreeSlice(button, "HIGHLIGHT", nil, 12, BUTTON_COORDS)
    light:SetFile(Look.ART.buttonHighlight)
    light:SetBlend("ADD")
    button.blizzardFace = face

    local function Paint(self)
        if rawget(self, "disabled") then
            face:SetFile(Look.ART.buttonDisabled)
        elseif rawget(self, "held") then
            face:SetFile(Look.ART.buttonDown)
        else
            face:SetFile(Look.ART.button)
        end
    end
    button.PaintBlizzard = Paint
    Paint(button)

    if button.HookScript then
        button:HookScript("OnMouseDown", Paint)
        button:HookScript("OnMouseUp", Paint)
        button:HookScript("OnHide", Paint)
    end

    local setEnabled = button.SetEnabledState
    if type(setEnabled) == "function" then
        function button:SetEnabledState(enabled)
            setEnabled(self, enabled)
            Paint(self)
        end
    end
    return true
end

--------------------------------------------------------------------------------
-- Tick boxes
--------------------------------------------------------------------------------

--- Dress a house tick box (Widgets.CreateCheckbox) in UICheckButtonTemplate's
--- box and tick. `box` is the small square, `tick` the house tick.
function Look.Checkbox(checkbox, box, tick)
    if not Look.On() or not (checkbox and box) then return false end
    if not HasAll("check", "checkTick", "checkHighlight") then return false end

    for _, region in ipairs({ box:GetRegions() }) do Quiet(region) end
    QuietAll(rawget(box, "haloTextures"))
    Quiet(tick)

    local size = 24
    local frame = box
    local well = frame:CreateTexture(nil, "ARTWORK", nil, 3)
    well:SetSize(size, size)
    well:SetPoint("CENTER")
    well:SetTexture(Look.ART.check)

    local check = frame:CreateTexture(nil, "OVERLAY", nil, 3)
    check:SetSize(size, size)
    check:SetPoint("CENTER")
    check:SetTexture(Look.ART.checkTick)

    local light = frame:CreateTexture(nil, "OVERLAY", nil, 2)
    light:SetSize(size, size)
    light:SetPoint("CENTER")
    light:SetTexture(Look.ART.checkHighlight)
    pcall(light.SetBlendMode, light, "ADD")
    light:Hide()

    local function Paint()
        check:SetShown(checkbox.checked and true or false)
    end
    Paint()

    local setChecked = checkbox.SetChecked
    function checkbox:SetChecked(value)
        setChecked(self, value)
        Paint()
    end

    if checkbox.HookScript then
        checkbox:HookScript("OnEnter", function() light:Show() end)
        checkbox:HookScript("OnLeave", function() light:Hide() end)
    end
    return true
end

--------------------------------------------------------------------------------
-- Tabs below the window
--------------------------------------------------------------------------------

--- Dress one hanging tab (Widgets.CreateTabStrip, hanging) in the
--- character window's tab art. The strip calls Look.SelectTab as it picks.
function Look.Tab(button)
    if not Look.On() or not button then return false end
    if not HasAll("tab", "tabActive", "tabHighlight") then return false end

    Quiet(rawget(button, "background"))
    Quiet(rawget(button, "hover"))
    Quiet(rawget(button, "lit"))
    Quiet(rawget(button, "underline"))
    QuietAll(rawget(button, "edges"))
    QuietAll(rawget(button, "haloTextures"))

    local face = ThreeSlice(button, "BACKGROUND", 1, 20, TAB_COORDS)
    face:SetFile(Look.ART.tab)

    local light = ThreeSlice(button, "HIGHLIGHT", nil, 20, TAB_COORDS, 4)
    light:SetFile(Look.ART.tabHighlight)
    light:SetBlend("ADD")

    button.blizzardFace = face
    return true
end

--- The tab showing wears the active art and a white label; the others the
--- resting art and the game's gold.
function Look.SelectTab(button, active)
    local face = button and rawget(button, "blizzardFace")
    if not face then return end
    face:SetFile(active and Look.ART.tabActive or Look.ART.tab)
    if button.label then
        if active then button.label:SetTextColor(1, 1, 1, 1)
        else button.label:SetTextColor(GOLD[1], GOLD[2], GOLD[3], 1) end
    end
end

--- The strip's gliding gold line belongs to the house look.
function Look.TabStrip(strip)
    if not Look.On() or not strip then return end
    Quiet(rawget(strip, "line"))
    Quiet(rawget(strip, "lineGlow"))
end

--------------------------------------------------------------------------------
-- Scroll thumbs
--------------------------------------------------------------------------------

--- Dress a scroll bar's thumb in the game's knob. Returns true when it did,
--- so the bar lights it by tint rather than by colour.
function Look.Thumb(thumb)
    if not Look.On() or not thumb then return false end
    if not HasAll("knob") then return false end
    thumb:SetTexture(Look.ART.knob)
    pcall(thumb.SetTexCoord, thumb, 0.2, 0.8, 0.125, 0.875)
    thumb:SetVertexColor(1, 1, 1, 1)
    thumb.blizzard = true
    return true
end

--- Light a thumb under the mouse: the knob a touch gold, or the house
--- colour.
function Look.LightThumb(thumb, lit)
    if rawget(thumb, "blizzard") then
        if lit then thumb:SetVertexColor(1, 0.9, 0.6, 1) else thumb:SetVertexColor(1, 1, 1, 1) end
        return true
    end
    return false
end

--------------------------------------------------------------------------------
-- The window frame
--------------------------------------------------------------------------------

local function Gradient(texture, orientation, from, to)
    texture:SetColorTexture(1, 1, 1, 1)
    local ok = type(CreateColor) == "function" and type(texture.SetGradient) == "function"
        and pcall(texture.SetGradient, texture, orientation,
            CreateColor(from[1], from[2], from[3], 1), CreateColor(to[1], to[2], to[3], 1))
    if not ok then
        texture:SetColorTexture((from[1] + to[1]) / 2, (from[2] + to[2]) / 2, (from[3] + to[3]) / 2, 1)
    end
end

--- One side of the rim: a black hairline, the silver band, a black line
--- inside it.
local function Side(frame, side)
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
        return band
    end

    Band(0, 1, 1):SetColorTexture(EDGE[1], EDGE[2], EDGE[3], 1)
    local metal = Band(1, RIM - 1, 2)
    if side == "TOP" then
        Gradient(metal, "VERTICAL", SILVER, SILVER_HI)
    elseif side == "BOTTOM" then
        Gradient(metal, "VERTICAL", SILVER_LO, SILVER)
    elseif side == "LEFT" then
        Gradient(metal, "HORIZONTAL", SILVER_HI, SILVER)
    else
        Gradient(metal, "HORIZONTAL", SILVER, SILVER_LO)
    end
    Band(RIM, 1, 3):SetColorTexture(EDGE[1], EDGE[2], EDGE[3], 1)
end

--- The window's name in the game's gold on a dark tab across the top edge,
--- where the house plate sits, so nothing inside the window moves.
local function Title(trim, text)
    local plate = CreateFrame("Frame", nil, trim)
    plate:SetHeight(TITLE_HEIGHT)
    plate:SetPoint("CENTER", trim, "TOP", 0, 0)

    local fill = plate:CreateTexture(nil, "BACKGROUND")
    fill:SetAllPoints(plate)
    Gradient(fill, "VERTICAL", { 0.055, 0.055, 0.060 }, { 0.150, 0.150, 0.160 })

    for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do Side(plate, side) end

    local label = plate:CreateFontString(nil, "OVERLAY")
    local Theme = ns.Theme
    local font = (Theme and Theme.FONT) or [[Fonts\FRIZQT__.TTF]]
    local size = Theme and Theme.sizes and Theme.sizes.normal or 12
    pcall(label.SetFont, label, font, size + 1, "")
    label:SetPoint("CENTER", 0, 0)
    label:SetTextColor(GOLD[1], GOLD[2], GOLD[3], 1)
    pcall(label.SetShadowColor, label, 0, 0, 0, 1)
    pcall(label.SetShadowOffset, label, 1, -1)
    plate.label = label

    function plate:SetTitle(words)
        label:SetText(words or "")
        local ok, width = pcall(label.GetStringWidth, label)
        width = ok and type(width) == "number" and width or (#(words or "") * 8)
        self:SetWidth(math.max(120, math.ceil(width) + 48))
    end

    plate:SetTitle(text)
    return plate
end

--- The round portrait: the addon's emblem on a dark disc in a silver ring.
local function Portrait(trim)
    local portrait = CreateFrame("Frame", nil, trim)
    portrait:SetSize(PORTRAIT, PORTRAIT)
    portrait:SetPoint("TOPLEFT", trim, "TOPLEFT", -PORTRAIT_OUT, PORTRAIT_OUT)

    local media = ns.Titanforged and ns.Titanforged.MEDIA
        or ([[Interface\AddOns\%s\Media\Frame\]]):format(ADDON)

    local ring = portrait:CreateTexture(nil, "ARTWORK")
    ring:SetAllPoints(portrait)
    ring:SetTexture(media .. "Portrait")
    -- The house ring in silver, the colour of the game's portrait rings.
    if not pcall(ring.SetDesaturated, ring, true) then ring:SetVertexColor(0.75, 0.75, 0.78) end

    local emblem = portrait:CreateTexture(nil, "ARTWORK", nil, 2)
    emblem:SetSize(EMBLEM, EMBLEM)
    emblem:SetPoint("CENTER", 0, 1)
    emblem:SetTexture(media .. "Emblem")
    return portrait
end

--- The game's own close button (UIPanelCloseButton), or its art on a plain
--- button when the template is not there.
local function CloseButton(trim, onClick)
    local ok, close = pcall(CreateFrame, "Button", nil, trim, "UIPanelCloseButton")
    if not ok or not close then
        close = CreateFrame("Button", nil, trim)
        close:SetNormalTexture(Look.ART.close)
        close:SetPushedTexture(Look.ART.closeDown)
        close:SetHighlightTexture(Look.ART.closeHighlight, "ADD")
    end
    close:SetSize(CLOSE, CLOSE)
    close:ClearAllPoints()
    close:SetPoint("CENTER", trim, "TOPRIGHT", -6, -6)
    close:SetScript("OnClick", function() if onClick then onClick() end end)
    return close
end

--- Frame `frame` in the Blizzard style: the same options and the same trim
--- as Titanforged:Dress, so a window built for one wears the other.
function Look.Dress(frame, opts)
    opts = opts or {}

    for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do Side(frame, side) end

    local trim = CreateFrame("Frame", nil, frame)
    trim:SetAllPoints(frame)
    local ok, level = pcall(frame.GetFrameLevel, frame)
    if ok and type(level) == "number" then trim:SetFrameLevel(level + (opts.level or 20)) end
    pcall(trim.EnableMouse, trim, false)
    trim.corners = {}

    if opts.title then trim.plate = Title(trim, opts.title) end
    if opts.portrait then trim.portrait = Portrait(trim) end
    if opts.close then trim.closeButton = CloseButton(trim, opts.close) end

    trim.blizzard = true
    frame.titan = trim
    return trim
end

--------------------------------------------------------------------------------
-- What the client has
--------------------------------------------------------------------------------

--- Lines for the probe: the style on, and each piece of art the client has
--- or lacks.
function Look.ProbeLines()
    local lines = {}
    local wanted, drawn = Look.Wanted(), Look.Style()
    lines[#lines + 1] = ("Window style: %s%s"):format(drawn,
        wanted ~= drawn and (" (" .. wanted .. " after /reload)") or "")

    local missing = {}
    for _, name in ipairs(Look.ART_ORDER) do
        if not Look.HasArt(Look.ART[name]) then missing[#missing + 1] = name end
    end
    if #missing == 0 then
        lines[#lines + 1] = ("Blizzard style art: all %d pieces found"):format(#Look.ART_ORDER)
    else
        lines[#lines + 1] = ("Blizzard style art missing: %s"):format(table.concat(missing, ", "))
    end

    local made, close = pcall(CreateFrame, "Button", nil, UIParent, "UIPanelCloseButton")
    if made and close then close:Hide() end
    lines[#lines + 1] = "UIPanelCloseButton template: " .. ((made and close) and "yes" or "no")
    return lines
end
