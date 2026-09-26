-- Blackthornes Tradeskills -- UI/Theme.lua
-- Palette and panel construction.
--
-- Everything is built from plain textures rather than Blizzard backdrops, which
-- keeps the look consistent, avoids depending on BackdropTemplate being present,
-- and gives crisp one-pixel borders instead of the default bevelled frames.

local ADDON, ns = ...

local Theme = {}
ns.Theme = Theme

Theme.colors = {
    window    = { 0.055, 0.063, 0.078 },   -- #0E1014 outermost shell
    panel     = { 0.086, 0.094, 0.114 },   -- #16181D
    header    = { 0.110, 0.122, 0.145 },
    row       = { 0.133, 0.145, 0.172 },   -- #22252C
    rowAlt    = { 0.106, 0.118, 0.141 },
    rowHover  = { 0.180, 0.200, 0.239 },
    rowActive = { 0.220, 0.190, 0.110 },

    border    = { 0.204, 0.224, 0.263 },
    borderLit = { 0.302, 0.333, 0.388 },

    accent    = { 0.784, 0.643, 0.302 },   -- #C8A44D
    profit    = { 0.310, 0.820, 0.545 },   -- #4FD18B
    loss      = { 0.898, 0.376, 0.310 },   -- #E5604F
    warn      = { 0.910, 0.757, 0.353 },

    text      = { 0.902, 0.910, 0.925 },   -- #E6E8EC
    muted     = { 0.478, 0.502, 0.541 },   -- #7A8089
    dim       = { 0.330, 0.350, 0.390 },

    -- Untinted, for Blizzard border textures that already carry their own
    -- gold colouring and only look muddy when tinted again.
    natural   = { 1, 1, 1 },
}

local FONT do
    local ok, path = pcall(function() return (GameFontNormal:GetFont()) end)
    FONT = (ok and path) or [[Fonts\FRIZQT__.TTF]]
end

Theme.FONT = FONT

Theme.sizes = {
    tiny = 10,
    small = 11,
    normal = 12,
    large = 14,
    title = 16,
}

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

function Theme.Unpack(key, alpha)
    local color = Theme.colors[key] or Theme.colors.text
    return color[1], color[2], color[3], alpha or 1
end

--- Colour for a gold amount: green above zero, red below, muted at exactly zero.
function Theme.ProfitColor(value)
    if not value or value == 0 then return Theme.Unpack("muted") end
    if value > 0 then return Theme.Unpack("profit") end
    return Theme.Unpack("loss")
end

--- Flat filled texture covering a frame.
function Theme.Fill(frame, key, alpha, layer)
    local texture = frame:CreateTexture(nil, layer or "BACKGROUND")
    texture:SetAllPoints(frame)
    texture:SetColorTexture(Theme.Unpack(key, alpha))
    return texture
end

--- One-pixel border drawn as four edge textures, so it stays crisp at any size.
function Theme.Border(frame, key, alpha)
    local r, g, b, a = Theme.Unpack(key or "border", alpha)
    local edges = {}

    for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
        local edge = frame:CreateTexture(nil, "BORDER")
        edge:SetColorTexture(r, g, b, a)

        if side == "TOP" then
            edge:SetPoint("TOPLEFT")
            edge:SetPoint("TOPRIGHT")
            edge:SetHeight(1)
        elseif side == "BOTTOM" then
            edge:SetPoint("BOTTOMLEFT")
            edge:SetPoint("BOTTOMRIGHT")
            edge:SetHeight(1)
        elseif side == "LEFT" then
            edge:SetPoint("TOPLEFT")
            edge:SetPoint("BOTTOMLEFT")
            edge:SetWidth(1)
        else
            edge:SetPoint("TOPRIGHT")
            edge:SetPoint("BOTTOMRIGHT")
            edge:SetWidth(1)
        end

        edges[#edges + 1] = edge
    end

    frame.borderTextures = edges
    return edges
end

function Theme.SetBorderColor(frame, key, alpha)
    if not frame.borderTextures then return end

    local r, g, b, a = Theme.Unpack(key, alpha)
    for _, edge in ipairs(frame.borderTextures) do
        edge:SetColorTexture(r, g, b, a)
    end
end

--- A panel: filled background plus a border.
function Theme.CreatePanel(parent, backgroundKey, borderKey)
    local panel = CreateFrame("Frame", nil, parent)
    panel.background = Theme.Fill(panel, backgroundKey or "panel")

    if borderKey ~= false then
        Theme.Border(panel, borderKey or "border")
    end

    return panel
end

--- A text label.
function Theme.CreateLabel(parent, size, colorKey, justify)
    local label = parent:CreateFontString(nil, "OVERLAY")
    label:SetFont(FONT, Theme.sizes[size] or size or Theme.sizes.normal, "")
    label:SetTextColor(Theme.Unpack(colorKey or "text"))
    label:SetJustifyH(justify or "LEFT")
    label:SetWordWrap(false)
    return label
end

--- Wrap a frame in Blizzard's classic bevelled tooltip border.
--
-- Used for controls that sit out in the game world rather than inside our own
-- window: the flat one-pixel border reads well against a dark panel but
-- disappears against terrain, bags and Blizzard's own art. The chunky gold
-- edge is instantly recognisable as an interactive UI element.
--
-- The overlay is mouse-transparent, so it decorates without stealing clicks.
-- Border presets. `edge` is the texture ring's thickness.
--
-- A backdrop edge draws *inside* its own rectangle, and these Blizzard textures
-- are authored to sit ON the frame edge with content padded inward -- that is
-- why every Blizzard panel has a wide margin. So the overlay matches the frame
-- exactly (expand = 0) and callers pad their contents by `pad`. Pushing the
-- overlay outward instead leaves the ring floating with a visible gap.
Theme.outlines = {
    tooltip = { file = [[Interface\Tooltips\UI-Tooltip-Border]], edge = 16, pad = 5 },
    dialog  = { file = [[Interface\DialogFrame\UI-DialogBox-Border]], edge = 32, pad = 11 },
}

function Theme.AddGameOutline(frame, opts)
    opts = opts or {}

    local preset = Theme.outlines[opts.style or "tooltip"] or Theme.outlines.tooltip

    local edgeSize = opts.edgeSize or preset.edge

    -- How far the overlay reaches beyond the frame. Zero keeps the bevel flush
    -- against the edge, which is what these textures expect.
    local expand = opts.expand or 0

    local created, overlay = pcall(CreateFrame, "Frame", nil, frame, "BackdropTemplate")

    if created and overlay and overlay.SetBackdrop then
        overlay:SetPoint("TOPLEFT", -expand, expand)
        overlay:SetPoint("BOTTOMRIGHT", expand, -expand)
        overlay:EnableMouse(false)

        -- Above the frame's own art but below its children, so the bevel never
        -- draws across the title or the tabs.
        overlay:SetFrameLevel(math.max(0, frame:GetFrameLevel()))

        -- Edge only: the frame keeps its own dark fill.
        local applied = pcall(overlay.SetBackdrop, overlay, {
            edgeFile = preset.file,
            edgeSize = edgeSize,
        })

        if applied then
            pcall(overlay.SetBackdropBorderColor, overlay, Theme.Unpack(opts.color or "accent"))
            frame.outline = overlay
            return overlay
        end

        overlay:Hide()
    end

    -- BackdropTemplate is unavailable or refused: fall back to a hand-drawn
    -- double ring, which still separates the frame from whatever is behind it.
    local outer = CreateFrame("Frame", nil, frame)
    outer:SetPoint("TOPLEFT", -2, 2)
    outer:SetPoint("BOTTOMRIGHT", 2, -2)
    outer:SetFrameLevel(frame:GetFrameLevel() + 1)
    outer:EnableMouse(false)

    Theme.Border(outer, "window")
    Theme.Border(frame, opts.color or "accent")

    frame.outline = outer
    return outer
end

--- Thin horizontal rule.
function Theme.CreateDivider(parent, key)
    local divider = parent:CreateTexture(nil, "ARTWORK")
    divider:SetColorTexture(Theme.Unpack(key or "border"))
    divider:SetHeight(1)
    return divider
end

--------------------------------------------------------------------------------
-- The skill-up mark
--------------------------------------------------------------------------------

--- Where the addon's own art lives.
--
-- Built from the folder name the client hands us rather than written out, so
-- the texture still resolves if the addon is installed under another name.
local MEDIA = ([[Interface\AddOns\%s\Media\]]):format(ADDON)

-- How the mark on a recommended craft is drawn. Three of them because this is
-- the one part of the addon that cannot be checked outside the game: a texture
-- path that does not resolve draws nothing at all and looks exactly like a
-- feature that failed. `/bts star` switches between them in the moment rather
-- than waiting on another build.
--
--   star -- this addon's own gold star, generated by tools/make_star.py
--   raid -- the game's raid-target star, which every client has had for years
--   pip  -- a plain gold square, drawn from a colour texture, which cannot fail
Theme.marks = {
    star = { file = "SkillUpStar", size = 13 },
    raid = { blizzard = [[Interface\TargetingFrame\UI-RaidTargetingIcons]],
             coords = { 0, 0.25, 0, 0.25 }, size = 14 },
    pip  = { size = 7 },
}

-- How loudly the mark is drawn per tier. Orange is a point for certain and
-- gets the full star; yellow is very likely and gets a smaller, quieter one.
-- Size and weight rather than colour, because the art is already gold and
-- tinting gold orange only makes it muddy.
local MARK_TIERS = {
    optimal = { scale = 1.00, alpha = 1.00 },
    medium  = { scale = 0.80, alpha = 0.75 },

    -- Green: a skill up is possible but not likely. Only the craft pane draws
    -- it, since that pane marks every recipe that can still level you; the
    -- Profit tab only ever asks for the two tiers above.
    easy    = { scale = 0.65, alpha = 0.55 },
}

function Theme.CurrentMarkStyle()
    local style = ns.Config and ns.Config:Get("skillUpMarker")
    if style and Theme.marks[style] then return style end
    return "star"
end

function Theme.ApplyMarkStyle(mark, style)
    style = style or Theme.CurrentMarkStyle()

    local preset = Theme.marks[style] or Theme.marks.star

    mark.baseSize = preset.size
    mark:SetSize(preset.size, preset.size)

    if preset.file then
        mark:SetTexture(MEDIA .. preset.file)
        mark:SetTexCoord(0, 1, 0, 1)
        mark:SetVertexColor(1, 1, 1)
    elseif preset.blizzard then
        mark:SetTexture(preset.blizzard)
        mark:SetTexCoord(unpack(preset.coords))
        mark:SetVertexColor(1, 1, 1)
    else
        mark:SetColorTexture(Theme.Unpack("accent"))
        mark:SetTexCoord(0, 1, 0, 1)
    end

    mark.style = style
end

--- The mark a row wears when a craft both raises your skill and pays.
function Theme.CreateMark(parent)
    local mark = parent:CreateTexture(nil, "OVERLAY")
    Theme.ApplyMarkStyle(mark)
    mark:Hide()
    return mark
end

--- Show the mark for a tier, or hide it when there is nothing to say.
--
-- Rows are recycled and the style can change under them, so the style is
-- checked here rather than only when the row was built.
function Theme.SetMark(mark, tier)
    if not mark then return end

    local shape = tier and MARK_TIERS[tier]

    if not shape then
        mark:Hide()
        return
    end

    if mark.style ~= Theme.CurrentMarkStyle() then
        Theme.ApplyMarkStyle(mark)
    end

    local size = math.max(4, math.floor((mark.baseSize or 13) * shape.scale + 0.5))
    mark:SetSize(size, size)
    mark:SetAlpha(shape.alpha)
    mark:Show()
end
