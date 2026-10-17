-- Blackthornes Tradeskills -- UI/GoldGoal.lua
-- Goblin Gold's bar: your gold on this realm and side, a goal, and small
-- rewards on the way to it.
--
-- Asked 2026-10-17, from a mockup. A small bar that stays on screen while
-- "Gold Tracker" is ticked: the total counting up rather than jumping,
-- today's gold, a glowing fill with a tick at each tenth of the goal, and
-- the gold still to go. New gold floats up off the fill. Each tenth lights
-- its tick, bursts a few coins and plays a coin sound; the goal opens a
-- window with how long it took and a box for the next one. Today's gold
-- glows when it beats your best day. Hovering the bar lists every
-- character it counts. Drag it anywhere; the grip below its corner sizes
-- it, right-click for the normal size.
--
-- Logic/GoldGoal.lua works out the numbers and when to cheer; this only
-- draws. Nothing is built until the bar is first turned on, and nothing is
-- drawn while it is hidden. Motion follows the Window effects setting.

local ADDON, ns = ...
local L = ns.L or setmetatable({ Format = string.format }, { __index = function(_, key) return key end })

local Theme = ns.Theme
local Widgets = ns.Widgets
local Util = ns.Util

local GoldGoalUI = {}
ns.GoldGoalUI = GoldGoalUI

local COPPER_PER_GOLD = 10000

GoldGoalUI.WIDTH = 270
GoldGoalUI.HEIGHT = 78
local PAD = 10
local BAR_HEIGHT = 10
local COIN = [[Interface\Icons\INV_Misc_Coin_01]]
local EMBLEM = [[Interface\Icons\INV_Misc_Coin_02]]

-- The game's own sounds, by id: the loot window's coins for a tenth, the
-- achievement toast for the goal, the level-up chime if that one will not.
GoldGoalUI.SOUNDS = {
    step = { 120, 878 },
    goal = { 12891, 888 },
}

-- Weekday names for "Best day: Tuesday", by date("%w").
local WEEKDAYS = {
    [0] = L["Sunday"], L["Monday"], L["Tuesday"], L["Wednesday"],
    L["Thursday"], L["Friday"], L["Saturday"],
}

local function Motion() return ns.Motion end
local function Level()
    local motion = Motion()
    return motion and motion.Level and motion.Level() or "full"
end

local function Money(copper, parts)
    return Util.FormatMoney(copper, parts and { parts = parts } or { short = true })
end

--------------------------------------------------------------------------------
-- Sound
--------------------------------------------------------------------------------

--- Play a cheer's sound, unless Goblin Gold's sound is unticked.
function GoldGoalUI.Play(which)
    if ns.Config and ns.Config:Get("goldTrackerSound") == false then return false end
    if type(PlaySound) ~= "function" then return false end
    for _, id in ipairs(GoldGoalUI.SOUNDS[which] or {}) do
        local ok, willPlay = pcall(PlaySound, id, "Master")
        if ok and willPlay then return true end
    end
    return false
end

--------------------------------------------------------------------------------
-- Place and size
--------------------------------------------------------------------------------

local function Scale()
    local percent = tonumber(ns.Config and ns.Config:Get("goldTrackerScale")) or 100
    return math.max(0.5, math.min(1.5, percent / 100))
end

--- Put the bar where it was left: its top left corner, in UIParent's own
--- units, so a new size keeps it in place.
function GoldGoalUI:Place()
    local frame = self.frame
    if not frame then return end
    local scale = Scale()
    frame:SetScale(scale)
    frame:ClearAllPoints()

    local x = tonumber(ns.Config:Get("goldTrackerX"))
    local y = tonumber(ns.Config:Get("goldTrackerY"))
    if x and y then
        frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / scale, y / scale)
    else
        frame:SetPoint("TOP", UIParent, "TOP", 0, -120 / scale)
    end
end

local function SavePlace(frame)
    local scale = frame:GetScale() or 1
    local left, top = frame:GetLeft(), frame:GetTop()
    if not (left and top) then return end
    ns.Config:Set("goldTrackerX", math.floor(left * scale + 0.5))
    ns.Config:Set("goldTrackerY", math.floor(top * scale + 0.5))
end

--- Back to the top of the screen at its normal size.
function GoldGoalUI:ResetPlace()
    ns.Config:Set("goldTrackerX", nil)
    ns.Config:Set("goldTrackerY", nil)
    ns.Config:Set("goldTrackerScale", 100)
    self:Place()
end

--- The grip below the bottom right corner: drag to size the bar from its
--- top left corner, right-click for the normal size.
local function BuildGrip(frame)
    local grip = Theme.CreatePanel(frame, "panel", "borderLit")
    grip:SetSize(14, 14)
    grip:SetPoint("TOPRIGHT", frame, "BOTTOMRIGHT", -4, -3)
    grip:EnableMouse(true)

    for row = 0, 2 do
        for column = 2 - row, 2 do
            local dot = grip:CreateTexture(nil, "ARTWORK")
            dot:SetSize(2, 2)
            dot:SetPoint("BOTTOMRIGHT", grip, "BOTTOMRIGHT", -3 - (2 - column) * 3, 3 + (2 - row) * 3)
            dot:SetColorTexture(Theme.Unpack("accent"))
        end
    end

    grip:SetScript("OnMouseDown", function(self, button)
        if button == "RightButton" then
            ns.Config:Set("goldTrackerScale", 100)
            SavePlace(frame)
            GoldGoalUI:Place()
            return
        end
        local scale = frame:GetScale() or 1
        self.left, self.top = (frame:GetLeft() or 0) * scale, (frame:GetTop() or 0) * scale
        self:SetScript("OnUpdate", function()
            local cx = GetCursorPosition()
            local ui = UIParent:GetEffectiveScale()
            if not (cx and ui and ui > 0) then return end
            local new = math.max(0.5, math.min(1.5, (cx / ui - self.left) / GoldGoalUI.WIDTH))
            frame:SetScale(new)
            frame:ClearAllPoints()
            frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", self.left / new, self.top / new)
        end)
    end)
    grip:SetScript("OnMouseUp", function(self)
        if not self:GetScript("OnUpdate") then return end
        self:SetScript("OnUpdate", nil)
        ns.Config:Set("goldTrackerScale", math.floor((frame:GetScale() or 1) * 100 + 0.5))
        SavePlace(frame)
    end)
    grip:SetScript("OnEnter", function(self)
        Theme.SetBorderColor(self, "accent")
        if GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(L["Drag to change the size. Right-click for the normal size."], 1, 1, 1, true)
            GameTooltip:Show()
        end
    end)
    grip:SetScript("OnLeave", function(self)
        Theme.SetBorderColor(self, "borderLit")
        if GameTooltip and GameTooltip:IsOwned(self) then GameTooltip:Hide() end
    end)
    return grip
end

--------------------------------------------------------------------------------
-- The bar
--------------------------------------------------------------------------------

function GoldGoalUI:Build()
    if self.frame then return self.frame end

    local frame = Theme.CreatePanel(UIParent, "window", "metal")
    frame:SetSize(self.WIDTH, self.HEIGHT)
    frame:SetFrameStrata("MEDIUM")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SavePlace(self)
    end)
    frame:SetScript("OnEnter", function() GoldGoalUI:ShowCard() end)
    frame:SetScript("OnLeave", function() GoldGoalUI:HideCard() end)
    frame:SetScript("OnShow", function() GoldGoalUI:Refresh(true) end)
    Theme.TopSheen(frame, 0.06)
    Theme.Halo(frame, 6, 0.10)
    self.frame = frame

    -- The emblem: a gold coin in a gold ring.
    local ring = Theme.CreatePanel(frame, "well", "accent")
    ring:SetSize(34, 34)
    ring:SetPoint("TOPLEFT", PAD, -PAD)
    local emblem = ring:CreateTexture(nil, "ARTWORK")
    emblem:SetPoint("TOPLEFT", 2, -2)
    emblem:SetPoint("BOTTOMRIGHT", -2, 2)
    emblem:SetTexture(EMBLEM)
    emblem:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    self.emblem = ring

    local title = Theme.CreateLabel(frame, "tiny", "accent")
    title:SetPoint("TOPLEFT", ring, "TOPRIGHT", 8, 0)
    title:SetText(L["Goblin Gold"])

    local total = Theme.CreateLabel(frame, 17, "text")
    pcall(total.SetFont, total, Theme.FONT, 17, "OUTLINE")
    total:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -3)
    self.total = total

    local todayValue = Theme.CreateLabel(frame, "small", "profit", "RIGHT")
    todayValue:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PAD, -PAD - 13)
    self.todayValue = todayValue

    local todayLabel = Theme.CreateLabel(frame, "tiny", "muted", "RIGHT")
    todayLabel:SetPoint("BOTTOMRIGHT", todayValue, "TOPRIGHT", 0, 2)
    todayLabel:SetText(L["Today"])

    -- A soft gold glow behind Today's number when it beats your best day.
    local todayGlow = frame:CreateTexture(nil, "BACKGROUND", nil, 3)
    todayGlow:SetPoint("TOPLEFT", todayValue, "TOPLEFT", -10, 6)
    todayGlow:SetPoint("BOTTOMRIGHT", todayValue, "BOTTOMRIGHT", 10, -6)
    pcall(todayGlow.SetBlendMode, todayGlow, "ADD")
    todayGlow:SetColorTexture(Theme.Unpack("accent", 0.18))
    todayGlow:Hide()
    self.todayGlow = todayGlow

    -- The bar: a dark well, a gold fill with a light along its top, and a
    -- tick at each tenth.
    local track = Theme.CreatePanel(frame, "well", "border")
    track:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", PAD, PAD + 14)
    track:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -PAD, PAD + 14)
    track:SetHeight(BAR_HEIGHT)
    self.track = track
    self.trackWidth = self.WIDTH - 2 * PAD

    local fill = track:CreateTexture(nil, "ARTWORK")
    fill:SetPoint("TOPLEFT", 1, -1)
    fill:SetPoint("BOTTOMLEFT", 1, 1)
    fill:SetWidth(1)
    fill:SetColorTexture(Theme.Unpack("accent"))
    Theme.SetGradientAlpha(fill, "HORIZONTAL", "accent", 0.75, 1)
    self.fill = fill

    local shine = track:CreateTexture(nil, "OVERLAY")
    shine:SetPoint("TOPLEFT", fill, "TOPLEFT")
    shine:SetPoint("TOPRIGHT", fill, "TOPRIGHT")
    shine:SetHeight(2)
    shine:SetColorTexture(Theme.Unpack("accentHi", 0.7))
    self.shine = shine

    local glow = track:CreateTexture(nil, "OVERLAY", nil, 2)
    glow:SetPoint("TOPLEFT", -3, 3)
    glow:SetPoint("BOTTOMRIGHT", 3, -3)
    pcall(glow.SetBlendMode, glow, "ADD")
    glow:SetColorTexture(Theme.Unpack("accentHi", 0.35))
    glow:SetAlpha(0)
    self.barGlow = glow

    self.ticks = {}
    for step = 1, ns.GoldGoal.STEPS - 1 do
        local tick = track:CreateTexture(nil, "OVERLAY", nil, 3)
        tick:SetSize(1, BAR_HEIGHT + 4)
        tick:SetPoint("CENTER", track, "LEFT", self.trackWidth * step / ns.GoldGoal.STEPS, 0)
        tick:SetColorTexture(Theme.Unpack("border"))
        self.ticks[step] = tick
    end

    local share = Theme.CreateLabel(frame, "tiny", "muted")
    share:SetPoint("TOPLEFT", track, "BOTTOMLEFT", 0, -3)
    self.share = share

    local togo = Theme.CreateLabel(frame, "tiny", "muted", "RIGHT")
    togo:SetPoint("TOPRIGHT", track, "BOTTOMRIGHT", 0, -3)
    self.togo = togo

    -- The line that says a tenth was reached, above the bar.
    local cheer = Theme.CreateLabel(frame, "normal", "gilt", "CENTER")
    pcall(cheer.SetFont, cheer, Theme.FONT, Theme.sizes.normal, "OUTLINE")
    cheer:SetPoint("BOTTOM", frame, "TOP", 0, 6)
    cheer:SetAlpha(0)
    self.cheerLine = cheer

    self.grip = BuildGrip(frame)
    self.floats, self.coins = {}, {}

    frame:Hide()
    self:Place()
    return frame
end

--- Show or hide the bar as the setting says.
function GoldGoalUI:Apply()
    local on = ns.GoldGoal and ns.GoldGoal:IsOn()
    if not on then
        if self.frame then self.frame:Hide() end
        self:HideCard()
        return
    end
    self:Build()
    self:Place()
    self.frame:Show()
end

local function FillWidth(self, total, goal)
    if not (goal and goal > 0) then return 0 end
    return math.max(0, math.min(1, total / goal)) * (self.trackWidth - 2)
end

local function DrawTotal(self, total, goal)
    self.total:SetText(Money(total))
    local width = FillWidth(self, total, goal)
    self.fill:SetWidth(math.max(1, width))
    self.fill:SetShown(width >= 1)
    self.shine:SetShown(width >= 1)
end

--- Draw what moved. `force` draws even when nothing did.
function GoldGoalUI:Refresh(force)
    local frame = self.frame
    if not (frame and frame:IsShown()) then return end

    local GoldGoal = ns.GoldGoal
    local now = time()
    local key = GoldGoal.version .. ":" .. tostring(ns.GoldLog and ns.GoldLog.DayKey and ns.GoldLog.DayKey(now))
    if key == self.drawnKey and not force then return end
    self.drawnKey = key

    local total = GoldGoal:Total(now)
    local goal = GoldGoal:Goal()
    local record = GoldGoal:Record(false)
    local step = GoldGoal.Step(total, goal)

    -- The total counts up from what was shown, and the fill with it.
    local from = self.shownTotal
    self.shownTotal = total
    local motion = Motion()
    if from and from ~= total and motion and Level() ~= "off" then
        motion:Run(self, "count", 0.8, function(p)
            DrawTotal(self, from + (total - from) * p, goal)
        end)
    else
        if motion then motion:Stop(self, "count") end
        DrawTotal(self, total, goal)
    end

    -- Ticks reached glow gold.
    for index, tick in ipairs(self.ticks) do
        local lit = goal and index <= step
        tick:SetColorTexture(Theme.Unpack(lit and "accentHi" or "border"))
        tick:SetWidth(lit and 2 or 1)
    end

    -- Today, glowing past your best day.
    local today = GoldGoal:Today()
    if today then
        self.todayValue:SetText((today > 0 and "+" or "") .. Money(today, 1))
        self.todayValue:SetTextColor(Theme.Unpack(today >= 0 and "profit" or "loss"))
    else
        self.todayValue:SetText("")
    end
    local best = GoldGoal:BestDay(now)
    local beats = today and best and best > 0 and today > best
    self.todayGlow:SetShown(beats and true or false)
    if beats then self.todayValue:SetTextColor(Theme.Unpack("accentHi")) end

    if goal then
        local percent = math.floor(math.min(1, total / goal) * 100)
        self.share:SetText(L.Format("%d%% of %s", percent, Money(goal, 1)))
        if total >= goal then
            self.togo:SetText(L["Goal reached!"])
            self.togo:SetTextColor(Theme.Unpack("accentHi"))
        else
            self.togo:SetText(L.Format("%s to go", Money(goal - total, 1)))
            self.togo:SetTextColor(Theme.Unpack("muted"))
        end
        self.track:Show()
    else
        self.share:SetText(L["No goal yet. Set one in Settings."])
        self.togo:SetText("")
        self.track:Show()
    end

    if self.card and self.card:IsShown() then self:ShowCard() end
    return record
end

--------------------------------------------------------------------------------
-- Rewards
--------------------------------------------------------------------------------

--- Where the fill ends, from the bar's left edge.
local function TipX(self)
    local goal = ns.GoldGoal:Goal()
    local width = FillWidth(self, self.shownTotal or 0, goal)
    return math.max(8, math.min(self.trackWidth - 8, width))
end

--- New gold rising off the end of the fill and fading.
function GoldGoalUI:Float(amount)
    local frame = self.frame
    if not (frame and frame:IsShown()) or Level() ~= "full" then return end

    local label
    for _, candidate in ipairs(self.floats) do
        if not candidate.busy then label = candidate break end
    end
    if not label then
        if #self.floats >= 6 then return end
        label = Theme.CreateLabel(frame, "small", "gilt", "CENTER")
        pcall(label.SetFont, label, Theme.FONT, Theme.sizes.small, "OUTLINE")
        self.floats[#self.floats + 1] = label
    end

    label.busy = true
    label:SetText("+" .. Money(amount, 1))
    local x = TipX(self)
    ns.Motion:Run(label, "float", 1.4, function(p)
        label:ClearAllPoints()
        label:SetPoint("BOTTOM", self.track, "TOPLEFT", x, 4 + 26 * p)
        label:SetAlpha(1 - p * p)
    end, { done = function()
        label:SetAlpha(0)
        label.busy = false
    end, ease = false })
end

--- A handful of coins bursting from a point on the bar.
local function Burst(self, x, count)
    if Level() ~= "full" then return end
    for index = 1, count do
        local coin = self.coins[index]
        if not coin then
            coin = self.frame:CreateTexture(nil, "OVERLAY", nil, 5)
            coin:SetSize(10, 10)
            coin:SetTexture(COIN)
            coin:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            coin:SetAlpha(0)
            self.coins[index] = coin
        end
        local angle = math.pi * (0.15 + 0.7 * (index - 1) / math.max(1, count - 1))
        local reach = 26 + (index % 3) * 8
        local dx, dy = math.cos(angle) * reach, math.sin(angle) * reach
        ns.Motion:Run(coin, "burst", 0.9, function(p)
            coin:ClearAllPoints()
            -- Out and up, then falling a little as it fades.
            coin:SetPoint("CENTER", self.track, "LEFT", x + dx * p, dy * p - 18 * p * p)
            coin:SetAlpha(p < 0.6 and 1 or (1 - p) / 0.4)
        end, { done = function() coin:SetAlpha(0) end, delay = (index % 4) * 0.03 })
    end
end

--- The bar flares and the line above it says how far you are.
local function StepCheer(self, cheer)
    local x = self.trackWidth * cheer.step / ns.GoldGoal.STEPS
    Burst(self, x, 8)

    self.cheerLine:SetText(L.Format("%d%% there!", math.floor(cheer.step * 100 / ns.GoldGoal.STEPS + 0.5)))
    local motion = ns.Motion
    motion:Run(self.cheerLine, "cheer", 3, function(p)
        self.cheerLine:SetAlpha(p < 0.1 and p * 10 or p > 0.75 and (1 - p) * 4 or 1)
    end, { ease = false })
    motion:Run(self.barGlow, "flare", 1.2, function(p)
        self.barGlow:SetAlpha(math.sin(p * math.pi))
    end, { ease = false })
    motion:Run(self.frame, "halo", 1.2, function(p)
        Theme.SetHalo(self.frame, 0.10 + 0.35 * math.sin(p * math.pi))
    end, { ease = false })

    local tick = self.ticks[cheer.step]
    if tick then
        motion:Run(tick, "pop", 0.6, function(p)
            tick:SetHeight(BAR_HEIGHT + 4 + 8 * math.sin(p * math.pi))
        end, { ease = false })
    end
end

--- A cheer from Logic/GoldGoal.lua.
function GoldGoalUI:Cheer(cheer)
    if not cheer then return end
    self:Apply()
    if not (self.frame and self.frame:IsShown()) then return end
    self:Refresh(true)

    if cheer.kind == "goal" then
        GoldGoalUI.Play("goal")
        Burst(self, self.trackWidth - 8, 12)
        self:ShowGoalWindow(cheer)
    else
        GoldGoalUI.Play("step")
        StepCheer(self, cheer)
    end
end

--------------------------------------------------------------------------------
-- Words
--------------------------------------------------------------------------------

--- "Took 11 days", "Took 3 hours", "Took under an hour".
function GoldGoalUI.TookText(seconds)
    seconds = tonumber(seconds)
    if not seconds then return nil end
    local days = math.floor(seconds / 86400)
    if days >= 2 then return L.Format("Took %d days", days) end
    if days == 1 then return L["Took 1 day"] end
    local hours = math.floor(seconds / 3600)
    if hours >= 2 then return L.Format("Took %d hours", hours) end
    if hours == 1 then return L["Took 1 hour"] end
    return L["Took under an hour"]
end

--- "Tuesday, 612g" for a day this week, "612g, 12 days ago" before it.
function GoldGoalUI.BestDayText(net, day, now)
    if not (net and day and ns.GoldLog and ns.GoldLog.KeyStart) then return nil end
    now = now or time()
    local start = ns.GoldLog.KeyStart(day)
    local ago = math.floor((ns.GoldLog.DayStart(now) - start) / 86400 + 0.5)
    if ago <= 6 then
        local weekday = WEEKDAYS[tonumber(date("%w", start))] or ""
        return L.Format("%s, %s", weekday, Money(net, 1))
    end
    return L.Format("%s, %d days ago", Money(net, 1), ago)
end

--------------------------------------------------------------------------------
-- The hover card
--------------------------------------------------------------------------------

local CARD_ROW = 20

local function CardRow(card, index)
    local row = card.rows[index]
    if row then return row end

    row = CreateFrame("Frame", nil, card)
    row:SetHeight(CARD_ROW)
    row.band = row:CreateTexture(nil, "BACKGROUND")
    row.band:SetAllPoints(row)
    row.line = row:CreateTexture(nil, "BORDER")
    row.line:SetPoint("BOTTOMLEFT", 0, 0)
    row.line:SetPoint("BOTTOMRIGHT", 0, 0)
    row.line:SetHeight(1)
    row.line:SetColorTexture(Theme.Unpack("border", 0.6))
    row.left = Theme.CreateLabel(row, "small", "text")
    row.left:SetPoint("LEFT", 8, 0)
    row.note = Theme.CreateLabel(row, "tiny", "muted")
    row.note:SetPoint("LEFT", row.left, "RIGHT", 6, 0)
    row.right = Theme.CreateLabel(row, "small", "text", "RIGHT")
    row.right:SetPoint("RIGHT", -8, 0)
    card.rows[index] = row
    return row
end

local function Width(label)
    return Theme.TextWidth(label) or 0
end

--- The card under the bar: every character counted, then the week, the
--- best day and how long to the goal.
function GoldGoalUI:ShowCard()
    local frame = self.frame
    if not (frame and frame:IsShown()) then return end

    local card = self.card
    if not card then
        card = Theme.CreatePanel(frame, "glassAlt", "metal")
        card:SetFrameStrata("TOOLTIP")
        card.rows = {}
        self.card = card
    end

    local GoldGoal = ns.GoldGoal
    local now = time()
    local members = GoldGoal:Members(now)
    local total = 0
    for _, member in ipairs(members) do total = total + member.gold end
    local goal = GoldGoal:Goal()

    local lines = {}
    for _, member in ipairs(members) do
        local note
        if member.isCurrent then
            note = L["Playing now"]
        elseif member.at then
            note = L.Format("Seen %s", Util.FormatAgeAgo(math.max(0, now - member.at)))
        end
        lines[#lines + 1] = { left = member.name, note = note,
            right = member.known and Money(member.gold, 2) or "--" }
    end

    lines[#lines + 1] = { left = members[2] and L.Format("All %d", #members) or L["All"],
        right = Money(total, 2), strong = true }

    local week = GoldGoal:Week()
    if week then
        lines[#lines + 1] = { left = L["This week"],
            right = (week > 0 and "+" or "") .. Money(week, 1), color = week >= 0 and "profit" or "loss" }
    end
    local bestText = GoldGoalUI.BestDayText(GoldGoal:BestDay(now))
    if bestText then lines[#lines + 1] = { left = L["Best day"], right = bestText } end
    if goal and total < goal then
        local days = GoldGoal:DaysToGo(total, goal)
        if days then
            lines[#lines + 1] = { left = L["At this week's pace"],
                right = days == 1 and L["about 1 day to go"] or L.Format("about %d days to go", days) }
        end
    end

    -- Wide enough for its longest line, measured, so nothing is cut short.
    local width = 220
    for index, line in ipairs(lines) do
        local row = CardRow(card, index)
        row.left:SetText(line.left)
        row.left:SetTextColor(Theme.Unpack(line.strong and "accentHi" or "text"))
        row.note:SetText(line.note or "")
        row.right:SetText(line.right or "")
        row.right:SetTextColor(Theme.Unpack(line.color or (line.strong and "accentHi" or "text")))
        local need = 16 + Width(row.left) + (line.note and 6 + Width(row.note) or 0) + 18 + Width(row.right)
        width = math.max(width, math.ceil(need))
    end

    for index, line in ipairs(lines) do
        local row = card.rows[index]
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", card, "TOPLEFT", 1, -1 - (index - 1) * CARD_ROW)
        row:SetWidth(width)
        row.band:SetColorTexture(Theme.Unpack(index % 2 == 1 and "glass" or "glassAlt"))
        row:Show()
    end
    for index = #lines + 1, #card.rows do card.rows[index]:Hide() end

    card:SetSize(width + 2, #lines * CARD_ROW + 2)
    card:ClearAllPoints()
    local below = (frame:GetBottom() or 0) * (frame:GetEffectiveScale() or 1) > 240
    if below then
        card:SetPoint("TOP", frame, "BOTTOM", 0, -20)
    else
        card:SetPoint("BOTTOM", frame, "TOP", 0, 24)
    end
    card:Show()
end

function GoldGoalUI:HideCard()
    if self.card then self.card:Hide() end
end

--------------------------------------------------------------------------------
-- The goal reached
--------------------------------------------------------------------------------

local function BuildGoalWindow()
    local window = Theme.CreatePanel(UIParent, "window", "accent")
    window:SetSize(300, 210)
    window:SetFrameStrata("DIALOG")
    window:SetPoint("TOP", UIParent, "TOP", 0, -150)
    window:EnableMouse(true)
    window:SetMovable(true)
    window:RegisterForDrag("LeftButton")
    window:SetScript("OnDragStart", window.StartMoving)
    window:SetScript("OnDragStop", window.StopMovingOrSizing)
    Theme.TopSheen(window, 0.08)
    Theme.Halo(window, 10, 0.30)

    _G.BlackthornesTSGoldGoalReached = window
    if type(UISpecialFrames) == "table" and type(tinsert) == "function" then
        tinsert(UISpecialFrames, "BlackthornesTSGoldGoalReached")
    end

    window.title = Theme.CreateLabel(window, 20, "gilt", "CENTER")
    pcall(window.title.SetFont, window.title, Theme.FONT, 20, "OUTLINE")
    window.title:SetPoint("TOP", 0, -16)
    window.title:SetText(L["Goal reached!"])

    window.amount = Theme.CreateLabel(window, "large", "text", "CENTER")
    window.amount:SetPoint("TOP", window.title, "BOTTOM", 0, -6)

    window.lines = {}
    for index = 1, 3 do
        local line = Theme.CreateLabel(window, "small", "muted", "CENTER")
        line:SetPoint("TOP", window.amount, "BOTTOM", 0, -8 - (index - 1) * 16)
        window.lines[index] = line
    end

    local nextLabel = Theme.CreateLabel(window, "small", "text")
    nextLabel:SetText(L["Next Goal:"])

    window.box = Widgets.CreateNumberBox(window, { width = 80, min = 1, max = 99999999 })
    local unit = Theme.CreateLabel(window, "small", "muted")
    unit:SetText("g")

    -- Lined up across the middle, measured.
    local rowWidth = Width(nextLabel) + 6 + 80 + 4 + Width(unit)
    nextLabel:SetPoint("BOTTOMLEFT", window, "BOTTOM", -rowWidth / 2, 50)
    window.box:SetPoint("LEFT", nextLabel, "RIGHT", 6, 0)
    unit:SetPoint("LEFT", window.box, "RIGHT", 4, 0)

    window.set = Widgets.CreateButton(window, L["Set"], function()
        local gold = window.box:GetValue()
        if gold and gold > 0 then ns.GoldGoal:SetGoalGold(gold) end
        window:Hide()
    end, { width = 90, height = 22, primary = true })
    window.done = Widgets.CreateButton(window, L["Done"], function() window:Hide() end,
        { width = 90, height = 22 })
    window.set:SetPoint("BOTTOMRIGHT", window, "BOTTOM", -4, 14)
    window.done:SetPoint("BOTTOMLEFT", window, "BOTTOM", 4, 14)

    window:Hide()
    return window
end

function GoldGoalUI:ShowGoalWindow(cheer)
    local window = self.goalWindow or BuildGoalWindow()
    self.goalWindow = window

    local GoldGoal = ns.GoldGoal
    window.amount:SetText(Money(cheer.goal, 1))

    local texts = {}
    texts[#texts + 1] = GoldGoalUI.TookText(cheer.took)
    local bestText = GoldGoalUI.BestDayText(GoldGoal:BestDay())
    if bestText then texts[#texts + 1] = L.Format("Best day: %s", bestText) end
    local from = GoldGoal:MostlyFrom()
    if from then texts[#texts + 1] = L.Format("Mostly from %s", from) end
    for index, line in ipairs(window.lines) do line:SetText(texts[index] or "") end

    local suggest = GoldGoal.NextGoal(GoldGoal:Total())
    window.box:SetValue(math.floor(suggest / COPPER_PER_GOLD))
    window:Show()

    local motion = ns.Motion
    if motion and Level() == "full" then
        motion:Run(window, "rise", 0.5, function(p)
            window:SetAlpha(p)
            pcall(window.SetScale, window, 0.9 + 0.1 * (ns.Motion.EaseOutBack and ns.Motion.EaseOutBack(p) or p))
        end, { ease = false })
    end
end
