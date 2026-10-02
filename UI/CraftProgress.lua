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
    local fraction, secondsLeft = 0, 0
    if type(startMS) == "number" and type(endMS) == "number" and endMS > startMS then
        fraction = math.max(0, math.min(1, (now - startMS) / (endMS - startMS)))
        secondsLeft = math.max(0, (endMS - now) / 1000)
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
    return { name = label, fraction = fraction, secondsLeft = secondsLeft, remaining = remaining }
end

--- What is being crafted right now.
-- @return nil when no craft is casting, else
--   { name, fraction (0..1), secondsLeft, remaining (crafts after this one, or nil) }
--
-- Runs every frame while a bar shows. Anything the game will not let the addon
-- read (a cast inside a dungeon) means no bar, never an error per frame.
function Progress:Read()
    if type(UnitCastingInfo) ~= "function" then return nil end
    local ok, cast = pcall(ReadUnsafe)
    if ok then return cast end
    return nil
end

--- The text on the bar: the craft on the left, and on the right how many
--- more after this one beside the time left. The count used to follow the
--- name, and in the narrow bar beside the profession window it was cut off.
-- @return name, right, shorter  -- shorter: the count without the time, for
--   a bar with no room for the name beside both; nil on the last craft
function Progress.Describe(cast)
    local time = ("%.1fs"):format(cast.secondsLeft)
    if cast.remaining then
        return cast.name, ("%d more · %s"):format(cast.remaining, time),
            ("%d more"):format(cast.remaining)
    end
    return cast.name, time
end

--- Whether a label's text runs past its width. False when it cannot be
--- measured, so nothing is left out on a guess.
local function TooWide(label)
    local ok, width = pcall(label.GetStringWidth, label)
    if not ok or type(width) ~= "number" then return false end

    local room = label.GetWidth and label:GetWidth()
    return type(room) == "number" and room > 0 and width > room
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

    local name, right, shorter = Progress.Describe(cast)
    bar.timer:SetText(right)
    bar.label:SetText(name)

    -- Nothing is cut off. With too little room the time goes first, as the
    -- fill shows how far the craft has got, then the name; the count stays.
    if shorter and TooWide(bar.label) then bar.timer:SetText(shorter) end
    if TooWide(bar.label) then
        bar.timer:SetText(right)
        bar.label:SetText("")
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
