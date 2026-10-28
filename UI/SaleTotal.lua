-- The Sale Total on the auction house drawer's Sell view (the owner said
-- build it, 2026-10-28, from a mockup whose words he approved; on unless
-- unticked). A band under the summary line holds what everything on the
-- Sell list would bring in at today's prices, after the auction house cut,
-- the same total the drawer's title carried.
--
-- While a scan runs, a meter fills and the band says "Pricing 7 of 12".
-- A quick scan writes every price at its end (Prices:CommitScan), so the
-- count-up is played just after: each item whose worth rose sends coins
-- from its row to the total, which rolls up, pops and glows, a few items a
-- beat, never longer than REVEAL_MOST seconds in all. Each round number
-- passed (MilestoneStep) pops a chip; the end pops the total once more and
-- says how far it moved since the last scan, with New Best when it beats
-- the best kept. Effects Subtle keeps the rolling number and the meter
-- only; Off shows the new total at once. A change that is not a scan (a
-- listing, the bags) rolls the number quietly.
--
-- Saved, account wide, never rename them: `saleTotal` (the switch, nil
-- reads as on), `saleTotalBest` and `saleTotalLast` (copper, the best total
-- and the one at the last scan, for the hover and "since last scan").
-- Nothing is drawn or run while the band is hidden.

local _, ns = ...
local L = ns.L or setmetatable({ Format = string.format }, { __index = function(_, key) return key end })

local SaleTotal = ns.NewModule("SaleTotal")

SaleTotal.HEIGHT = 50          -- the band, with its gap above
SaleTotal.BEAT = 0.3           -- seconds between reveal steps
SaleTotal.REVEAL_MOST = 6      -- the whole count-up, at most
SaleTotal.LEAST_A_BEAT = 2     -- items revealed a step, at least
SaleTotal.SCAN_WINDOW = 60     -- a finished scan waits this long for the drawer
SaleTotal.COINS = 20           -- coin textures kept for flights
SaleTotal.COIN_TEXTURE = [[Interface\MoneyFrame\UI-GoldIcon]]

local COPPER_PER_GOLD = 10000

local function Now()
    return type(GetTime) == "function" and GetTime() or 0
end

local function Level()
    return ns.Motion and ns.Motion.Level() or "full"
end

--------------------------------------------------------------------------------
-- Working it out (no frames, so the tests read these straight)
--------------------------------------------------------------------------------

--- Whether the band is wanted at all.
function SaleTotal:IsOn()
    return not (ns.Config and ns.Config:Get("saleTotal") == false)
end

--- What each item on the list is worth now, by item ID, and the total.
-- Held lines (kept for the other addons) count for nothing.
function SaleTotal.Worths(lines)
    local worths, total = {}, 0
    for _, line in ipairs(lines or {}) do
        if not line.held and line.itemID then
            local value = tonumber(line.postTotal) or 0
            worths[line.itemID] = (worths[line.itemID] or 0) + value
            total = total + value
        end
    end
    return worths, total
end

--- What moved since `seen`: the items whose worth rose, biggest first, and
--- what all the rest moved by together (drops, and items gone).
-- @return rises { { itemID, amount } }, rest (copper, may be negative)
function SaleTotal.Changes(seen, worths)
    seen = seen or {}
    local rises, rest = {}, 0
    for itemID, value in pairs(worths) do
        local before = seen[itemID] or 0
        if value > before then
            rises[#rises + 1] = { itemID = itemID, amount = value - before }
        elseif value < before then
            rest = rest + (value - before)
        end
    end
    for itemID, before in pairs(seen) do
        if worths[itemID] == nil then rest = rest - before end
    end
    table.sort(rises, function(a, b)
        if a.amount ~= b.amount then return a.amount > b.amount end
        return a.itemID < b.itemID
    end)
    return rises, rest
end

--- The round number milestones fall on near `copper`: 10g, 100g, 1,000g
--- and so on, the power of ten below the total, never under 10g.
function SaleTotal.MilestoneStep(copper)
    local gold = (tonumber(copper) or 0) / COPPER_PER_GOLD
    if gold < 100 then return 10 * COPPER_PER_GOLD end
    local power = math.floor(math.log10(gold) + 1e-9)
    return (10 ^ power) * COPPER_PER_GOLD
end

--- The milestone passed going from `from` to `to`, or nil.
function SaleTotal.Crossed(from, to)
    from, to = tonumber(from) or 0, tonumber(to) or 0
    if to <= from then return nil end
    local step = SaleTotal.MilestoneStep(to)
    local mark = math.floor(to / step) * step
    if mark > from and mark > 0 then return mark end
    return nil
end

--- Items to reveal a step, so `count` of them take REVEAL_MOST at most.
function SaleTotal.PerStep(count)
    local steps = math.max(1, math.floor(SaleTotal.REVEAL_MOST / SaleTotal.BEAT))
    return math.max(SaleTotal.LEAST_A_BEAT, math.ceil((count or 0) / steps))
end

--- Whole gold as the band shows it, "1,234".
function SaleTotal.Gold(copper)
    local gold = math.floor((tonumber(copper) or 0) / COPPER_PER_GOLD + 0.5)
    local Util = ns.Util
    if Util and Util.Comma then return Util.Comma(gold) end
    return tostring(gold)
end

--- The words under the meter: "Up 12g since last scan", or nil when it
--- moved by less than a gold.
function SaleTotal.DeltaText(before, after)
    if not before or not after then return nil end
    local gold = math.floor(math.abs(after - before) / COPPER_PER_GOLD + 0.5)
    if gold < 1 then return nil end
    local text = SaleTotal.Gold(gold * COPPER_PER_GOLD)
    if after > before then return L.Format("Up %sg since last scan", text), true end
    return L.Format("Down %sg since last scan", text), false
end

--------------------------------------------------------------------------------
-- The band
--------------------------------------------------------------------------------

local function Money(copper)
    local Util = ns.Util
    if not Util or not Util.FormatMoney then return tostring(copper) end
    return Util.FormatMoney(copper or 0)
end

--- The total as the big number shows it: gold with its coins in their
--- colours, silver and copper only while it is under 100g.
function SaleTotal.BigText(copper)
    local Util = ns.Util
    copper = math.max(0, math.floor((copper or 0) + 0.5))
    if not Util or not Util.FormatMoney then return tostring(copper) end
    return Util.FormatMoney(copper, { short = true })
end

--- Build the band inside the drawer's body. Called once by PostPanel.
function SaleTotal:Build(parent, below, frame)
    local Theme = ns.Theme
    local band = CreateFrame("Frame", nil, parent)
    band:SetPoint("TOPLEFT", below, "BOTTOMLEFT", 0, -6)
    band:SetPoint("RIGHT", frame, "RIGHT", -14, 0)
    band:SetHeight(SaleTotal.HEIGHT - 6)
    band:EnableMouse(true)
    self.band = band

    band.background = Theme.Fill(band, "glassActive", 0.9)
    Theme.Border(band, "accent", 0.55)
    self.stripe = Theme.AccentStripe(band, 3, 0.9)

    -- The light behind the number: brighter the more it has been fed.
    local glow = band:CreateTexture(nil, "BACKGROUND", nil, 3)
    glow:SetPoint("TOPLEFT", 3, -1)
    glow:SetPoint("BOTTOMLEFT", 3, 1)
    glow:SetWidth(220)
    Theme.SetGradientAlpha(glow, "HORIZONTAL", "accent", 0.30, 0)
    glow:Hide()
    self.glow = glow

    local label = Theme.CreateLabel(band, "tiny", "accent")
    label:SetPoint("TOPLEFT", 12, -5)
    label:SetText(L["Sale Total"])
    self.label = label

    -- The number sits on its own frame, so a pop scales it alone.
    local holder = CreateFrame("Frame", nil, band)
    holder:SetSize(200, 24)
    holder:SetPoint("LEFT", band, "TOPLEFT", 12, -29)
    self.holder = holder

    local number = holder:CreateFontString(nil, "OVERLAY")
    number:SetFont(Theme.FONT, (Theme.sizes.title or 16) + 6, "OUTLINE")
    number:SetTextColor(Theme.Unpack("accentHi"))
    number:SetJustifyH("LEFT")
    number:SetPoint("LEFT", holder, "LEFT", 0, 0)
    self.number = number

    local status = Theme.CreateLabel(band, "tiny", "muted", "RIGHT")
    status:SetPoint("TOPRIGHT", -10, -6)
    self.status = status

    local delta = Theme.CreateLabel(band, "tiny", "muted", "RIGHT")
    delta:SetPoint("TOPRIGHT", status, "BOTTOMRIGHT", 0, -4)
    self.delta = delta

    -- New Best: a small gold tag that pops in beside the number.
    local best = CreateFrame("Frame", nil, band)
    best:SetSize(60, 14)
    best:SetPoint("LEFT", number, "RIGHT", 8, 1)
    Theme.Fill(best, "accent", 1)
    local bestText = Theme.CreateLabel(best, "tiny", "ink", "CENTER")
    bestText:SetPoint("CENTER")
    bestText:SetText(L["New Best"])
    best:SetWidth(math.max(44, (Theme.TextWidth and Theme.TextWidth(bestText) or 40) + 10))
    best:Hide()
    self.best = best

    -- A milestone passed: the round number, rising off the total.
    local chip = CreateFrame("Frame", nil, band)
    chip:SetSize(60, 16)
    chip:SetFrameLevel(band:GetFrameLevel() + 6)
    Theme.Fill(chip, "ink", 0.95)
    Theme.Border(chip, "accentHi", 1)
    local chipText = Theme.CreateLabel(chip, "tiny", "accentHi", "CENTER")
    chipText:SetPoint("CENTER")
    chip.text = chipText
    chip:Hide()
    self.chip = chip

    -- The meter along the foot: the scan's progress, then how much is priced.
    local track = band:CreateTexture(nil, "BORDER")
    track:SetPoint("BOTTOMLEFT", 4, 3)
    track:SetPoint("BOTTOMRIGHT", -4, 3)
    track:SetHeight(3)
    track:SetColorTexture(0, 0, 0, 0.55)
    self.track = track
    local meter = band:CreateTexture(nil, "ARTWORK")
    meter:SetPoint("BOTTOMLEFT", track, "BOTTOMLEFT")
    meter:SetHeight(3)
    meter:SetColorTexture(Theme.Unpack("accent"))
    meter:SetWidth(1)
    self.meter = meter

    -- Coins for the flights, made once and reused.
    self.coins, self.free = {}, {}
    local layer = CreateFrame("Frame", nil, band)
    layer:SetAllPoints(frame)
    layer:SetFrameLevel(band:GetFrameLevel() + 8)
    self.coinLayer = layer
    for index = 1, SaleTotal.COINS do
        local coin = layer:CreateTexture(nil, "OVERLAY")
        coin:SetTexture(SaleTotal.COIN_TEXTURE)
        coin:SetSize(12, 12)
        coin:Hide()
        self.coins[index] = coin
        self.free[#self.free + 1] = coin
    end

    band:SetScript("OnEnter", function(owner) SaleTotal:ShowTooltip(owner) end)
    band:SetScript("OnLeave", function() GameTooltip:Hide() end)
    band:SetScript("OnHide", function() SaleTotal:Settle() end)

    self.shown = 0
    self:SetNumber(0)
    band:Hide()
    return band
end

--- Whether the band takes room in the drawer now.
function SaleTotal:Showing()
    return self.band ~= nil and self.band:IsShown()
end

function SaleTotal:SetNumber(copper)
    self.shown = copper or 0
    if self.number then self.number:SetText(SaleTotal.BigText(self.shown)) end
end

function SaleTotal:SetMeter(fraction)
    if not (self.meter and self.track) then return end
    fraction = math.max(0, math.min(1, tonumber(fraction) or 0))
    local width = (self.track.GetWidth and self.track:GetWidth()) or 0
    if not width or width <= 0 then width = 320 end
    self.meter:SetWidth(math.max(1, width * fraction))
    self.meter:SetShown(fraction > 0)
end

--- Light the glow behind the number to `p` of its strength.
function SaleTotal:Light(p)
    if self.glow and ns.Theme and ns.Theme.LightGradient then
        ns.Theme.LightGradient(self.glow, "HORIZONTAL", "accent", 0.30, 0, p)
    end
end

--- Roll the number to `target` over `duration`.
function SaleTotal:Roll(target, duration)
    local Motion = ns.Motion
    if not Motion or Level() == "off" then
        self:SetNumber(target)
        return
    end
    Motion:SetValue(self, "value", self.shown or 0)
    Motion:Blend(self, "value", target, duration or 0.35, function(value)
        SaleTotal:SetNumber(value)
    end)
end

--- The number grows and settles, its glow flaring and fading.
function SaleTotal:Pop(size, glow)
    local Motion = ns.Motion
    if not Motion or Level() == "off" or not self.holder then return end
    size = size or 0.12
    local holder = self.holder
    Motion:Run(self, "pop", 0.32, function(p)
        local swell = math.sin(p * math.pi) * size
        holder:SetScale(1 + swell)
    end, { ease = false, done = function() holder:SetScale(1) end })

    self.heat = math.min(1, (self.heat or 0) + (glow or 0.25))
    local from = self.heat
    Motion:Run(self, "glow", 1.2, function(p)
        SaleTotal.heat = from * (1 - p)
        SaleTotal:Light(SaleTotal.heat)
    end)
end

--- A coin flies from `fromX, fromY` (offsets in the drawer) to the number.
function SaleTotal:Fly(fromX, fromY, delay, done)
    local Motion = ns.Motion
    local coin = table.remove(self.free or {})
    if not coin or not Motion or not self.holder or not self.coinLayer then
        if done then done() end
        return
    end
    local layer = self.coinLayer
    local lx, ly = layer:GetLeft() or 0, layer:GetBottom() or 0
    local hx, hy = self.holder:GetLeft(), self.holder:GetBottom()
    local toX = hx and (hx - lx + 20) or 40
    local toY = hy and (hy - ly + 12) or 40
    local lift = 30 + math.random(0, 20)

    coin:ClearAllPoints()
    coin:SetPoint("CENTER", layer, "BOTTOMLEFT", fromX, fromY)
    coin:SetAlpha(1)
    coin:Show()
    Motion:Run(coin, "fly", 0.5, function(p)
        local x = fromX + (toX - fromX) * p
        local y = fromY + (toY - fromY) * p + math.sin(p * math.pi) * lift
        coin:ClearAllPoints()
        coin:SetPoint("CENTER", layer, "BOTTOMLEFT", x, y)
        coin:SetAlpha(p > 0.85 and (1 - p) / 0.15 or 1)
    end, { delay = delay, ease = Motion.EaseOut, done = function()
        coin:Hide()
        local free = SaleTotal.free
        free[#free + 1] = coin
        if done then done() end
    end })
end

--- Where an item's row stands in the drawer, as offsets from its bottom
--- left, or the number's left when the row is scrolled out of sight.
function SaleTotal:RowSpot(itemID)
    local PostPanel = ns.PostPanel
    local layer = self.coinLayer
    local lx, ly = layer and layer:GetLeft() or 0, layer and layer:GetBottom() or 0
    local rows = PostPanel and PostPanel.list and PostPanel.list.rows
    for _, row in ipairs(rows or {}) do
        local data = row.data
        if data and data.itemID == itemID and row.IsShown and row:IsShown() then
            local right, bottom, top = row:GetRight(), row:GetBottom(), row:GetTop()
            if right and bottom and top then
                return right - lx - 40, (bottom + top) / 2 - ly
            end
        end
    end
    return nil
end

--- Pop the chip for a milestone passed.
function SaleTotal:Milestone(copper)
    local chip, Motion = self.chip, ns.Motion
    if not chip or not Motion or Level() ~= "full" then return end
    chip.text:SetText(SaleTotal.Gold(copper) .. "g")
    chip:SetWidth(math.max(40, ((ns.Theme.TextWidth and ns.Theme.TextWidth(chip.text)) or 30) + 14))
    chip:ClearAllPoints()
    chip:SetPoint("BOTTOMLEFT", self.number, "TOPRIGHT", 6, -6)
    chip:Show()
    Motion:Run(chip, "rise", 1.4, function(p)
        chip:ClearAllPoints()
        chip:SetPoint("BOTTOMLEFT", SaleTotal.number, "TOPRIGHT", 6, -6 + p * 14)
        chip:SetScale(p < 0.2 and (0.6 + 2 * p) or 1)
        chip:SetAlpha(p > 0.7 and (1 - p) / 0.3 or 1)
    end, { ease = false, done = function() chip:Hide() end })
    self:Pop(0.2, 0.6)
    self:Shower(6)
end

--- A few coins burst up off the number and fall away.
function SaleTotal:Shower(count)
    local Motion, layer = ns.Motion, self.coinLayer
    if not Motion or Level() ~= "full" or not layer or not self.holder then return end
    local lx, ly = layer:GetLeft() or 0, layer:GetBottom() or 0
    local hx, hy = self.holder:GetLeft(), self.holder:GetBottom()
    if not hx or not hy then return end
    local x0, y0 = hx - lx + 30, hy - ly + 12
    for index = 1, count or 8 do
        local coin = table.remove(self.free)
        if not coin then return end
        local dx = (math.random() - 0.5) * 140
        local up = 30 + math.random() * 30
        coin:Show()
        Motion:Run(coin, "fly", 0.9, function(p)
            coin:ClearAllPoints()
            coin:SetPoint("CENTER", layer, "BOTTOMLEFT", x0 + dx * p, y0 + up * 4 * p * (1 - p) - 20 * p)
            coin:SetAlpha(1 - p)
        end, { delay = index * 0.03, ease = false, done = function()
            coin:Hide()
            local free = SaleTotal.free
            free[#free + 1] = coin
        end })
    end
end

--------------------------------------------------------------------------------
-- What the drawer calls
--------------------------------------------------------------------------------

--- The scan's progress, from UI:SetScanProgress.
function SaleTotal:Progress(fraction)
    self.scanning = true
    self.scanFraction = tonumber(fraction) or 0
    if self:Showing() then self:DrawStatus() end
end

--- A scan was cancelled or gave up: nothing to reveal.
function SaleTotal:ScanStopped()
    self.scanning = false
    if self:Showing() then self:DrawStatus() end
end

--- A scan wrote its prices: the next look plays the count-up.
function SaleTotal:ScanFinished()
    self.scanning = false
    self.revealAt = Now()
end

--- The status line and meter, from what is known now.
function SaleTotal:DrawStatus()
    if not self.status then return end
    local count = self.count or 0
    if self.scanning then
        local fraction = self.scanFraction or 0
        self.status:SetText(L.Format("Pricing %d of %d", math.floor(fraction * count + 0.5), count))
        self:SetMeter(fraction)
    elseif count == 0 then
        self.status:SetText(L["Nothing to sell"])
        self:SetMeter(0)
    else
        local revealed = math.max(0, count - #(self.queue or {}))
        self.status:SetText(L.Format("%d of %d priced", revealed, count))
        self:SetMeter(revealed / count)
    end
end

--- Bring the band up to date with the Sell list. From PostPanel:Refresh.
-- @param lines the lines Sell shows; held ones count for nothing
-- @param heldBack how many were kept for the other addons
function SaleTotal:Update(lines, heldBack)
    if not self.band then return end
    local worths, total = SaleTotal.Worths(lines)
    self.total, self.heldBack = total, heldBack or 0
    local count = 0
    for _, line in ipairs(lines or {}) do if not line.held then count = count + 1 end end
    self.count = count

    local reveal = self.revealAt and (Now() - self.revealAt) <= SaleTotal.SCAN_WINDOW
    self.revealAt = nil

    if not self.seen then
        -- First look this session: the total as it stands, unless a scan
        -- just finished, which counts it all up from nothing.
        self.seen = reveal and {} or worths
        if not reveal then
            self:SetNumber(total)
            self:DrawStatus()
            return
        end
        self:SetNumber(0)
    end

    local rises, rest = SaleTotal.Changes(self.seen, worths)
    self.seen = worths

    -- A change mid count-up (a listing, the bags) moves only what has
    -- landed; the rest of the count-up goes on and ends on the true total.
    if self.ticking and not reveal then
        local moved = rest
        for _, rise in ipairs(rises) do moved = moved + rise.amount end
        self.landed = (self.landed or self.shown or 0) + moved
        self:Roll(math.max(0, self.landed), 0.25)
        self:DrawStatus()
        return
    end

    if not reveal or Level() == "off" then
        if reveal then self:Finished() end
        self:Roll(total, 0.35)
        self:DrawStatus()
        return
    end

    -- Drops roll quietly at once; rises wait their turn in the count-up.
    self.landed = (self.landed or self.shown or 0) + rest
    if rest ~= 0 then self:Roll(math.max(0, self.landed), 0.25) end
    self.before = ns.Config and ns.Config:Get("saleTotalLast")
    self:Queue(rises)
end

--- Line the rises up and start the beats.
function SaleTotal:Queue(rises)
    self.queue = self.queue or {}
    for _, rise in ipairs(rises) do self.queue[#self.queue + 1] = rise end
    self.perStep = SaleTotal.PerStep(#self.queue)
    self.finishing = true
    self:DrawStatus()
    if self.band and not self.ticking then
        self.ticking = true
        self.wait = 0
        self.band:SetScript("OnUpdate", function(_, elapsed) SaleTotal:Tick(elapsed) end)
    end
end

function SaleTotal:Tick(elapsed)
    self.wait = (self.wait or 0) - (tonumber(elapsed) or 0)
    if self.wait > 0 then return end
    self.wait = SaleTotal.BEAT
    self:Beat()
end

--- One step of the count-up: the next few items fly in.
function SaleTotal:Beat()
    local queue = self.queue or {}
    if #queue == 0 then
        self:StopTicking()
        if self.finishing then self:Finished() end
        return
    end
    local full = Level() == "full"
    for index = 1, math.min(self.perStep or 2, #queue) do
        local rise = table.remove(queue, 1)
        local land = function() SaleTotal:Land(rise.amount) end
        local x, y = nil, nil
        if full then x, y = self:RowSpot(rise.itemID) end
        if x then
            self:Fly(x, y, (index - 1) * 0.05, land)
            if rise.amount >= 2 * COPPER_PER_GOLD then self:Fly(x - 6, y + 4, (index - 1) * 0.05 + 0.08) end
        else
            land()
        end
    end
    self:DrawStatus()
end

--- A coin landed: the total rolls up by the item's rise.
function SaleTotal:Land(amount)
    local from = self.landed or self.shown or 0
    self.landed = from + (amount or 0)
    local target = math.max(self.landed, 0)
    self:Roll(target, 0.3)
    if Level() == "full" then self:Pop(0.08, 0.2) end
    local mark = SaleTotal.Crossed(from, target)
    if mark then self:Milestone(mark) end
end

function SaleTotal:StopTicking()
    self.ticking = false
    if self.band then self.band:SetScript("OnUpdate", nil) end
end

--- The count-up is done: the true total, one more pop, and how far it
--- moved since the last scan.
function SaleTotal:Finished()
    self.finishing = false
    self.queue, self.landed = {}, nil
    local total = self.total or 0
    self:Roll(total, 0.4)

    local before = self.before or (ns.Config and ns.Config:Get("saleTotalLast"))
    local text, up = SaleTotal.DeltaText(before, total)
    self.lastDelta = before and (total - before) or nil
    if self.delta then
        self.delta:SetText(text or "")
        if text then self.delta:SetTextColor(ns.Theme.Unpack(up and "profit" or "loss")) end
    end

    local Config = ns.Config
    local bestBefore = Config and Config:Get("saleTotalBest")
    local newBest = bestBefore ~= nil and total > bestBefore
    if Config then
        Config:Set("saleTotalLast", total)
        if bestBefore == nil or total > bestBefore then Config:Set("saleTotalBest", total) end
    end
    self.before = nil

    if self.best then
        self.best:SetShown(newBest)
        if newBest and ns.Motion and Level() ~= "off" then
            local best = self.best
            ns.Motion:Run(best, "pop", 0.4, function(p) best:SetScale(0.5 + 0.5 * p) end,
                { ease = ns.Motion.EaseOutBack, done = function() best:SetScale(1) end })
        end
    end

    if Level() == "full" then
        self:Pop(newBest and 0.3 or 0.2, 1)
        self:Shower(newBest and 14 or 8)
    end
    self:DrawStatus()
end

--- Land everything at once: the drawer went away mid count-up.
function SaleTotal:Settle()
    if self.ticking then
        self:StopTicking()
        if self.finishing then self:Finished() end
    end
    if ns.Motion then ns.Motion:Stop(self, nil, true) end
    for _, coin in ipairs(self.coins or {}) do
        if ns.Motion then ns.Motion:Stop(coin, nil) end
        coin:Hide()
    end
    self.free = {}
    for index, coin in ipairs(self.coins or {}) do self.free[index] = coin end
    if self.chip then self.chip:Hide() end
    if self.holder then self.holder:SetScale(1) end
    self:Light(0)
end

--- Show or hide the band. Returns whether it shows.
function SaleTotal:SetShown(show)
    if not self.band then return false end
    show = show and self:IsOn() or false
    if show ~= self.band:IsShown() then self.band:SetShown(show) end
    return show
end

function SaleTotal:ShowTooltip(owner)
    if not GameTooltip then return end
    local Theme = ns.Theme
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetText(L["Sale Total"], Theme.Unpack("accentHi"))
    GameTooltip:AddLine(L["What everything on your Sell list would bring in at today's prices, after the auction house cut."],
        1, 1, 1, true)
    GameTooltip:AddLine(" ")
    local r, g, b = Theme.Unpack("muted")
    GameTooltip:AddDoubleLine(L["Priced:"], tostring(self.count or 0), r, g, b, 1, 1, 1)
    if (self.heldBack or 0) > 0 then
        GameTooltip:AddDoubleLine(L["Held Back:"], L.Format("%d (not counted)", self.heldBack), r, g, b, 1, 1, 1)
    end
    if self.lastDelta then
        GameTooltip:AddDoubleLine(L["Since Last Scan:"], Money(self.lastDelta), r, g, b, 1, 1, 1)
    end
    local best = ns.Config and ns.Config:Get("saleTotalBest")
    if best then GameTooltip:AddDoubleLine(L["Best Yet:"], Money(best), r, g, b, 1, 1, 1) end
    GameTooltip:Show()
end
