-- Blackthornes Tradeskills -- UI/CraftProgress.lua
-- A craft progress bar of the addon's own, in the Queue tab and the craft pane.
--
-- The game's cast bar can end up under other windows, so the addon shows the
-- craft where the player is already looking: which item is being made, how
-- far along it is, and how many are left in the run. It reads the same cast
-- the game's bar does, so the two always agree.

local _, ns = ...

local Theme = ns.Theme

local Progress = ns.NewModule("CraftProgress")

Progress.bars = {}

local function ReadUnsafe()
    local ok, name, text, _, startMS, endMS = pcall(UnitCastingInfo, "player")
    if not ok or not name then return nil end

    local castBar = ns.CastBarOnTop
    if castBar and not castBar:IsCrafting() then return nil end

    local now = GetTime() * 1000
    local fraction, secondsLeft, castSeconds = 0, 0, 0
    if type(startMS) == "number" and type(endMS) == "number" and endMS > startMS then
        fraction = math.max(0, math.min(1, (now - startMS) / (endMS - startMS)))
        secondsLeft = math.max(0, (endMS - now) / 1000)
        castSeconds = (endMS - startMS) / 1000
    end

    local remaining
    local api = _G.C_TradeSkillUI
    if api and type(api.GetRemainingRecasts) == "function" then
        local okCount, count = pcall(api.GetRemainingRecasts)
        if okCount and type(count) == "number" and count > 0 then remaining = count end
    end

    local label = (type(text) == "string" and text ~= "") and text or name
    -- A plain string, or this raises here, inside Read's pcall, rather than
    -- later on the bar every frame.
    label = label .. ""
    return {
        name = label, fraction = fraction, secondsLeft = secondsLeft,
        castSeconds = castSeconds, remaining = remaining,
    }
end

--- What is being crafted right now.
-- @return nil when no craft is casting, else
--   { name, fraction (0..1), secondsLeft, castSeconds (one whole craft),
--     remaining (crafts after this one, or nil) }
--
-- Runs every frame while a bar shows. Anything the game will not let the addon
-- read (a cast inside a dungeon) means no bar, never an error per frame.
function Progress:Read()
    if type(UnitCastingInfo) ~= "function" then return nil end
    local ok, cast = pcall(ReadUnsafe)
    if ok then return cast end
    return nil
end

--- A whole run's time left, rounded up so it never reads 0s while crafting:
--- "45s", "1m 20s", "1h 05m".
function Progress.FormatTotal(seconds)
    seconds = math.ceil(math.max(0, seconds))
    if seconds < 60 then return ("%ds"):format(seconds) end
    if seconds < 3600 then
        return ("%dm %02ds"):format(math.floor(seconds / 60), seconds % 60)
    end
    return ("%dh %02dm"):format(math.floor(seconds / 3600), math.floor(seconds % 3600 / 60))
end

--- The text on the bar: the craft on the left, and on the right how many
--- more after this one, the time left on this craft and the time left on
--- the whole run (a player asked for the last, 2026-10-06). The count used
--- to follow the name, and in the narrow bar beside the profession window it
--- was cut off.
-- @return name, choices  -- the right-hand text, longest first; the bar uses
--   the first that leaves the name room. One choice on the last craft.
function Progress.Describe(cast)
    local time = ("%.1fs"):format(cast.secondsLeft)
    if not cast.remaining then return cast.name, { time } end

    local count = ("%d more"):format(cast.remaining)
    local total = Progress.FormatTotal(cast.secondsLeft + cast.remaining * (cast.castSeconds or 0))
    return cast.name, {
        ("%s · %s · %s left"):format(count, time, total),
        ("%s · %s left"):format(count, total),
        count,
    }
end

--- A region's text width, or nil when it cannot be measured.
local function TextWidth(region)
    local ok, width = pcall(region.GetStringWidth, region)
    if ok and type(width) == "number" then return width end
    return nil
end

--- The bar's inside width, or nil when it is not laid out yet.
local function Inside(bar)
    local ok, width = pcall(bar.GetWidth, bar)
    if ok and type(width) == "number" and width > 0 then return width - 12 end
    return nil
end

--- Whether the name runs into the right-hand text. Worked out from the bar's
--- width rather than the name's own, which reads 0 rather than less than
--- nothing once the right-hand text takes the whole bar. False when it
--- cannot be measured, so nothing is left out on a guess.
local function TooWide(bar)
    local name, right, inside = TextWidth(bar.label), TextWidth(bar.timer), Inside(bar)
    if not (name and right and inside) or name == 0 then return false end
    return name + 6 + right > inside
end

--- Whether the right-hand text alone is wider than the bar's inside.
local function RunsPastBar(bar)
    local right, inside = TextWidth(bar.timer), Inside(bar)
    return right ~= nil and inside ~= nil and right > inside
end

--- Create a bar. It shows itself while a craft casts and hides otherwise.
-- @param parent  frame to sit in
-- @param opts    { width, height, covers = a region to hide while the bar shows }
function Progress:Create(parent, opts)
    opts = opts or {}

    local bar = Theme.CreatePanel(parent, "panel")
    bar:SetSize(opts.width or 200, opts.height or 16)
    bar:Hide()

    local fill = bar:CreateTexture(nil, "ARTWORK")
    fill:SetPoint("TOPLEFT", 1, -1)
    fill:SetPoint("BOTTOMLEFT", 1, 1)
    fill:SetColorTexture(Theme.Unpack("profit", 0.55))
    fill:SetWidth(1)
    bar.fill = fill

    local timer = Theme.CreateLabel(bar, "small", "text", "RIGHT")
    timer:SetPoint("RIGHT", -6, 0)
    bar.timer = timer

    -- The name has whatever the count and the time leave it.
    local label = Theme.CreateLabel(bar, "small", "text")
    label:SetPoint("LEFT", 6, 0)
    label:SetPoint("RIGHT", timer, "LEFT", -6, 0)
    bar.label = label

    bar.covers = opts.covers
    self.bars[#self.bars + 1] = bar
    return bar
end

local function Update(bar, cast)
    if not cast then
        if bar:IsShown() then
            bar:Hide()
            if bar.covers then bar.covers:Show() end
        end
        return
    end

    if not bar:IsShown() then
        bar:Show()
        if bar.covers then bar.covers:Hide() end
    end

    local name, choices = Progress.Describe(cast)
    bar.label:SetText(name)

    -- Nothing is cut off. With too little room this craft's time goes first,
    -- as the fill shows how far it has got, then the run's time, then the
    -- name; the count stays.
    for _, right in ipairs(choices) do
        bar.timer:SetText(right)
        if not TooWide(bar) then break end
    end
    if TooWide(bar) then
        bar.label:SetText("")
        for _, right in ipairs(choices) do
            bar.timer:SetText(right)
            if not RunsPastBar(bar) then break end
        end
    end
    bar.fill:SetWidth(math.max(1, (bar:GetWidth() - 2) * cast.fraction))
end

--- Bring every bar up to date. Called every frame, but cheap: one cast read,
-- and only bars whose window is on screen are touched.
function Progress:Tick()
    local cast
    local read = false

    for _, bar in ipairs(self.bars) do
        local parent = bar:GetParent()
        if parent and parent:IsVisible() then
            if not read then cast = self:Read(); read = true end
            Update(bar, cast)
        elseif bar:IsShown() then
            Update(bar, nil)
        end
    end
end

-- A hidden bar gets no OnUpdate of its own, so one small frame drives them all.
local driver = CreateFrame("Frame")
driver:SetScript("OnUpdate", function() Progress:Tick() end)
