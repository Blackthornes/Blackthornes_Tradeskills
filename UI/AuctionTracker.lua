-- Blackthornes Tradeskills -- UI/AuctionTracker.lua
-- My Auctions: the small window listing what you have up on the auction
-- house. Logic/AuctionTracker.lua knows the rows and hears the sales; this
-- only draws.
--
-- Asked 2026-11-11, from the mockup the owner approved with its words
-- (previews/ts-auction-tracker/ in the project files). Off until ticked.
--
-- When something sells (Sold Effects: Full), the row lights gold, a SOLD
-- stamp lands on it, coins burst and the gold floats up, the row slides
-- away and Sold Today counts up. Subtle lights the row and lets it fade;
-- Off takes it away at once. Effects never go past the Effects setting.
-- An auction that runs out fades away with no gold.
--
-- Smooth play: nothing is built until it is first turned on and nothing is
-- drawn while it is hidden. The rows are read again only when the logic's
-- version moves or the soonest auction runs out; once a second only the
-- LEFT words are set. A sold or faded row keeps a frame of its own while
-- it goes, so the others never jump.
--
-- Saved, account wide, never renamed: auctionTrackerX/Y (top left, screen
-- units), auctionTrackerScale (percent), auctionTrackerSeeThrough (0 to 3).

local ADDON, ns = ...
local L = ns.L or setmetatable({ Format = string.format }, { __index = function(_, key) return key end })

local Theme = ns.Theme
local Util = ns.Util

local AuctionTrackerUI = {}
ns.AuctionTrackerUI = AuctionTrackerUI

AuctionTrackerUI.WIDTH = 300
AuctionTrackerUI.ROW = 22
-- The most rows shown at once; the wheel scrolls the rest.
AuctionTrackerUI.MOST_ROWS = 8
local PAD = 8
local HEADER = 24
local ICON = 18
local LEFT_W = 52
local PRICE_W = 74
local COIN = [[Interface\Icons\INV_Misc_Coin_01]]
local GLOW = ([[Interface\AddOns\%s\Media\Frame\Glow]]):format(ADDON)

-- How long each part of a sale takes, in seconds, by Sold Effects.
AuctionTrackerUI.SOLD = {
    full = { light = 0.3, stamp = 0.4, stampAt = 0.25, burstAt = 0.6, hold = 1.5,
        slide = 0.45, collapse = 0.3, count = 0.8 },
    subtle = { light = 0.35, hold = 0.9, fade = 0.5, collapse = 0.25 },
}
-- An auction that ran out or left the list.
AuctionTrackerUI.FADE = 0.6

local function Motion() return ns.Motion end
local function Logic() return ns.AuctionTracker end
local function Now() return time() end

local function Money(copper)
    return Util.FormatMoney(copper or 0)
end

local function Get(key)
    return ns.Config and ns.Config:Get(key)
end

--------------------------------------------------------------------------------
-- Words
--------------------------------------------------------------------------------

--- Time left as the LEFT column says it: "12h", "45m", "2d". A rough end
--- (the game gave a band, not seconds) starts with "~".
function AuctionTrackerUI.LeftText(ends, rough, now)
    if not ends then return "" end
    local seconds = math.max(0, ends - (now or Now()))
    local text
    if seconds >= 86400 * 2 then
        text = L.Format("%dd", math.floor(seconds / 86400))
    elseif seconds >= 3600 then
        text = L.Format("%dh", math.floor(seconds / 3600))
    else
        text = L.Format("%dm", math.max(1, math.ceil(seconds / 60)))
    end
    if rough then text = "~" .. text end
    return text
end

local function RowName(row)
    local name = Util.GetItemName(row.itemID, row.link)
    if type(name) ~= "string" then name = "?" end
    if Util.ColorItemName then
        local ok, colored = pcall(Util.ColorItemName, row.itemID, name)
        if ok and type(colored) == "string" then return colored end
    end
    return name
end

--------------------------------------------------------------------------------
-- Place and size
--------------------------------------------------------------------------------

local function Scale()
    local percent = tonumber(Get("auctionTrackerScale")) or 100
    return math.max(0.5, math.min(1.5, percent / 100))
end

--- Put the window where it was left: its top left corner, in UIParent's own
--- units, so a new size keeps it in place.
function AuctionTrackerUI:Place()
    local frame = self.frame
    if not frame then return end
    local scale = Scale()
    frame:SetScale(scale)
    frame:ClearAllPoints()
    local x, y = tonumber(Get("auctionTrackerX")), tonumber(Get("auctionTrackerY"))
    if x and y then
        frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / scale, y / scale)
    else
        frame:SetPoint("RIGHT", UIParent, "RIGHT", -40 / scale, 60 / scale)
    end
end

local function SavePlace(frame)
    local scale = frame:GetScale() or 1
    local left, top = frame:GetLeft(), frame:GetTop()
    if not (left and top) then return end
    ns.Config:Set("auctionTrackerX", math.floor(left * scale + 0.5))
    ns.Config:Set("auctionTrackerY", math.floor(top * scale + 0.5))
end

--- Back to its first place at its normal size (Tracker Place: Set Default).
function AuctionTrackerUI:ResetPlace()
    ns.Config:Set("auctionTrackerX", nil)
    ns.Config:Set("auctionTrackerY", nil)
    ns.Config:Set("auctionTrackerScale", 100)
    self:Place()
end

--- The house size grip below the bottom right corner: drag to size from
--- the top left corner, right-click for the normal size.
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
            ns.Config:Set("auctionTrackerScale", 100)
            SavePlace(frame)
            AuctionTrackerUI:Place()
            return
        end
        local scale = frame:GetScale() or 1
        self.left, self.top = (frame:GetLeft() or 0) * scale, (frame:GetTop() or 0) * scale
        self:SetScript("OnUpdate", function()
            local cx = GetCursorPosition()
            local ui = UIParent:GetEffectiveScale()
            if not (cx and ui and ui > 0) then return end
            local new = math.max(0.5, math.min(1.5, (cx / ui - self.left) / AuctionTrackerUI.WIDTH))
            frame:SetScale(new)
            frame:ClearAllPoints()
            frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", self.left / new, self.top / new)
        end)
    end)
    grip:SetScript("OnMouseUp", function(self)
        if not self:GetScript("OnUpdate") then return end
        self:SetScript("OnUpdate", nil)
        ns.Config:Set("auctionTrackerScale", math.floor((frame:GetScale() or 1) * 100 + 0.5))
        SavePlace(frame)
    end)
    grip:SetScript("OnEnter", function(self)
        Theme.SetBorderColor(self, "accent")
        if GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(L["Drag to change the size. Right-click for the normal size."], 1, 1, 1, 1, true)
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
-- Rows
--------------------------------------------------------------------------------

local function Stripe(widget, index)
    widget.stripe = index
    local key = (index % 2 == 1) and "glass" or "glassAlt"
    widget.background:SetColorTexture(Theme.Unpack(key))
end

local function NewRow(self)
    local body = self.body
    local width = self.WIDTH - 2 * PAD
    local row = CreateFrame("Frame", nil, body)
    row:SetSize(width, self.ROW)
    row:EnableMouse(true)

    local background = row:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints()
    row.background = background
    self.glass[#self.glass + 1] = background

    local line = row:CreateTexture(nil, "BORDER")
    line:SetPoint("BOTTOMLEFT")
    line:SetPoint("BOTTOMRIGHT")
    line:SetHeight(1)
    line:SetColorTexture(Theme.Unpack("border", 0.6))

    local edge = row:CreateTexture(nil, "ARTWORK", nil, 2)
    edge:SetPoint("TOPLEFT")
    edge:SetPoint("BOTTOMLEFT")
    edge:SetWidth(2)
    edge:SetColorTexture(Theme.Unpack("accentHi"))
    edge:Hide()
    row.edge = edge

    -- The gold light a sale gives the row.
    local lit = row:CreateTexture(nil, "ARTWORK", nil, 1)
    lit:SetAllPoints()
    lit:SetTexture(GLOW)
    pcall(lit.SetBlendMode, lit, "ADD")
    lit:SetVertexColor(Theme.Unpack("accent", 0.85))
    lit:SetAlpha(0)
    row.lit = lit

    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetSize(ICON, ICON)
    icon:SetPoint("LEFT", 4, 0)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row.icon = icon

    local count = Theme.CreateLabel(row, "tiny", "text", "RIGHT")
    pcall(count.SetFont, count, Theme.FONT, Theme.sizes.tiny, "OUTLINE")
    count:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 2, -1)
    row.count = count

    local price = Theme.CreateLabel(row, "small", "text", "RIGHT")
    price:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    price:SetWidth(PRICE_W)
    row.price = price

    local left = Theme.CreateLabel(row, "small", "muted", "RIGHT")
    left:SetPoint("RIGHT", price, "LEFT", -6, 0)
    left:SetWidth(LEFT_W)
    row.left = left

    local name = Theme.CreateLabel(row, "small", "text", "LEFT")
    name:SetPoint("LEFT", icon, "RIGHT", 6, 0)
    name:SetPoint("RIGHT", left, "LEFT", -4, 0)
    pcall(name.SetWordWrap, name, true)
    row.name = name

    row:SetScript("OnEnter", function(widget)
        widget.background:SetColorTexture(Theme.Unpack("glassHover"))
        widget.edge:Show()
        local data = widget.data
        if GameTooltip and data then
            GameTooltip:SetOwner(widget, "ANCHOR_LEFT")
            local ok = false
            if type(data.link) == "string" then ok = pcall(GameTooltip.SetHyperlink, GameTooltip, data.link) end
            if not ok and data.itemID and GameTooltip.SetItemByID then
                pcall(GameTooltip.SetItemByID, GameTooltip, data.itemID)
            end
            GameTooltip:Show()
        end
    end)
    row:SetScript("OnLeave", function(widget)
        Stripe(widget, widget.stripe or 1)
        widget.edge:Hide()
        if GameTooltip and GameTooltip:IsOwned(widget) then GameTooltip:Hide() end
    end)
    if self.seeThroughOn then AuctionTrackerUI.ShadeAll(row, true) end
    return row
end

--- Fill a row's words from its auction.
local function FillRow(widget, data, now)
    widget.data = data
    Theme.SetItemIcon(widget.icon, data.itemID, data.link)
    local quantity = tonumber(data.quantity) or 1
    widget.count:SetText(quantity > 1 and tostring(quantity) or "")
    widget.name:SetText(RowName(data))
    widget.left:SetText(AuctionTrackerUI.LeftText(data.ends, data.roughEnd, now))
    widget.price:SetText(data.unit and Money(data.unit) or "")
end

--- How tall a row is: one line, or more when its name wraps.
local function RowHeight(self, widget)
    local ok, height = pcall(widget.name.GetStringHeight, widget.name)
    height = ok and tonumber(height) or 0
    return math.max(self.ROW, math.ceil(height) + 6)
end

--------------------------------------------------------------------------------
-- The window
--------------------------------------------------------------------------------

function AuctionTrackerUI:Build()
    if self.frame then return self.frame end
    self.glass, self.pool, self.going, self.floats, self.coins = {}, {}, {}, {}, {}
    self.offset = 0

    local frame = Theme.CreatePanel(UIParent, "window", "metal")
    frame:SetSize(self.WIDTH, 120)
    frame:SetFrameStrata("MEDIUM")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(f) f:StartMoving() end)
    frame:SetScript("OnDragStop", function(f)
        f:StopMovingOrSizing()
        SavePlace(f)
    end)
    frame:SetScript("OnShow", function() AuctionTrackerUI:Refresh(true) end)
    frame:EnableMouseWheel(true)
    frame:SetScript("OnMouseWheel", function(_, delta) AuctionTrackerUI:Scroll(delta) end)
    Theme.TopSheen(frame, 0.06)
    Theme.Halo(frame, 6, 0.16)
    self.frame = frame
    self.glass[#self.glass + 1] = frame.background
    for _, halo in ipairs(frame.haloTextures or {}) do self.glass[#self.glass + 1] = halo end

    -- The header: the name on the left, the fold and close gems on the right.
    local header = CreateFrame("Frame", nil, frame)
    header:SetPoint("TOPLEFT", 0, 0)
    header:SetPoint("TOPRIGHT", 0, 0)
    header:SetHeight(HEADER)
    self.header = header

    local title = Theme.CreateLabel(header, "small", "accent", "LEFT")
    title:SetPoint("LEFT", PAD + 2, 0)
    title:SetText(L["My Auctions"])

    local gems = ns.HouseKit and ns.HouseKit.CreatePanelGems and ns.HouseKit.CreatePanelGems(header, {
        onFold = function(folded) AuctionTrackerUI:SetFolded(folded) end,
        onClose = function() if Logic() then Logic():SetOn(false) end end,
    })
    self.gems = gems

    local rule = frame:CreateTexture(nil, "BORDER")
    rule:SetPoint("TOPLEFT", PAD, -HEADER)
    rule:SetPoint("TOPRIGHT", -PAD, -HEADER)
    rule:SetHeight(1)
    rule:SetColorTexture(Theme.Unpack("accent", 0.35))

    -- Everything under the header, hidden while folded.
    local body = CreateFrame("Frame", nil, frame)
    body:SetPoint("TOPLEFT", 0, -HEADER - 1)
    body:SetPoint("BOTTOMRIGHT", 0, 0)
    self.body = body

    local soldLabel = Theme.CreateLabel(body, "small", "muted", "LEFT")
    soldLabel:SetPoint("TOPLEFT", PAD + 2, -6)
    soldLabel:SetText(L["Sold Today:"])
    self.soldLabel = soldLabel

    local soldValue = Theme.CreateLabel(body, "small", "gilt", "LEFT")
    pcall(soldValue.SetFont, soldValue, Theme.FONT, Theme.sizes.small, "OUTLINE")
    soldValue:SetPoint("LEFT", soldLabel, "RIGHT", 6, 0)
    self.soldValue = soldValue

    local soldGlow = body:CreateTexture(nil, "BACKGROUND", nil, 4)
    soldGlow:SetPoint("LEFT", soldValue, "LEFT", -10, 0)
    soldGlow:SetSize(110, 24)
    soldGlow:SetTexture(GLOW)
    pcall(soldGlow.SetBlendMode, soldGlow, "ADD")
    soldGlow:SetVertexColor(Theme.Unpack("accentHi", 0.6))
    soldGlow:SetAlpha(0)
    self.soldGlow = soldGlow

    local headings = CreateFrame("Frame", nil, body)
    headings:SetPoint("TOPLEFT", PAD, -26)
    headings:SetPoint("TOPRIGHT", -PAD, -26)
    headings:SetHeight(14)
    local item = Theme.CreateLabel(headings, "tiny", "accent", "LEFT")
    item:SetPoint("LEFT", 4, 0)
    item:SetText(L["ITEM"])
    local price = Theme.CreateLabel(headings, "tiny", "accent", "RIGHT")
    price:SetPoint("RIGHT", -4, 0)
    price:SetWidth(PRICE_W)
    price:SetText(L["PRICE"])
    local left = Theme.CreateLabel(headings, "tiny", "accent", "RIGHT")
    left:SetPoint("RIGHT", price, "LEFT", -6, 0)
    left:SetWidth(LEFT_W)
    left:SetText(L["LEFT"])
    self.headings = headings

    local empty = Theme.CreateLabel(body, "small", "dim", "CENTER")
    empty:SetPoint("TOPLEFT", PAD, -44)
    empty:SetPoint("TOPRIGHT", -PAD, -44)
    empty:SetHeight(self.ROW + 6)
    empty:SetText(L["Nothing up right now."])
    self.empty = empty

    local footer = Theme.CreateLabel(body, "tiny", "muted", "LEFT")
    footer:SetPoint("BOTTOMLEFT", PAD + 2, 7)
    self.footer = footer

    -- The once a second clock: only the LEFT words, unless the soonest
    -- auction ran out or the logic moved on.
    local wait = 0
    frame:SetScript("OnUpdate", function(_, elapsed)
        wait = wait - (tonumber(elapsed) or 0)
        if wait > 0 then return end
        wait = 1
        AuctionTrackerUI:Tick()
    end)

    BuildGrip(frame)
    return frame
end

--- Fold to the header, or open again. Nothing is saved.
function AuctionTrackerUI:SetFolded(folded)
    self.folded = folded and true or false
    if not self.frame then return end
    if self.folded then
        self.body:Hide()
        self.frame:SetHeight(HEADER + 2)
    else
        self.body:Show()
        self:Layout()
    end
end

--- Show or hide as "Auction Tracker:" says.
function AuctionTrackerUI:Apply()
    local logic = Logic()
    if not (logic and logic:IsOn()) then
        if self.frame then self.frame:Hide() end
        return
    end
    self:Build()
    self:Place()
    self:ApplySeeThrough()
    self.frame:Show()
end

function AuctionTrackerUI:Scroll(delta)
    local most = math.max(0, #(self.list or {}) - self.MOST_ROWS)
    local offset = math.max(0, math.min(most, (self.offset or 0) - (tonumber(delta) or 0)))
    if offset == self.offset then return end
    self.offset = offset
    self:Layout()
end

--- Read the rows again when the logic moved on (or `force`), keeping each
--- going row (sold or faded) where it stood.
function AuctionTrackerUI:Refresh(force)
    local logic = Logic()
    local frame = self.frame
    if not (logic and frame and frame:IsShown()) then return end
    if not force and self.drawnVersion == logic.version then return end
    self.drawnVersion = logic.version

    local rows = logic:Rows()
    local now = Now()
    local here, soonest = {}, nil
    for _, row in ipairs(rows) do
        here[row.key] = true
        if row.ends and (not soonest or row.ends < soonest) then soonest = row.ends end
    end
    self.soonest = soonest

    -- A row shown before and gone now, not sold: it ran out, or the
    -- auction house says it is no longer up. It fades with no gold.
    for index, old in ipairs(self.list or {}) do
        if not old.going and not here[old.key] and not self.going[old.key] then
            self:Fade(old, index)
        end
    end

    -- Going rows keep their place in the list.
    local list = {}
    for _, row in ipairs(rows) do
        if not self.going[row.key] then list[#list + 1] = row end
    end
    for key, going in pairs(self.going) do
        local at = math.max(1, math.min(#list + 1, going.index or 1))
        table.insert(list, at, going.data)
        going.data.going = key
    end
    self.list = list
    self.upCount = 0
    for _, row in ipairs(list) do
        if not row.going then self.upCount = self.upCount + 1 end
    end

    if not self.counting then
        self.shownSold = logic:SoldToday()
        self.soldValue:SetText(Money(self.shownSold))
    end
    self:Layout(now)
end

--- Lay the rows out: going rows on frames of their own, the rest on the
--- pool, each as tall as it needs, and the window as tall as its rows.
function AuctionTrackerUI:Layout(now)
    if not self.frame or self.folded then return end
    now = now or Now()
    local list = self.list or {}
    local most = math.max(0, #list - self.MOST_ROWS)
    if (self.offset or 0) > most then self.offset = most end

    local used, y, shown = 0, 44, 0
    local width = self.WIDTH - 2 * PAD
    for index = (self.offset or 0) + 1, #list do
        if shown >= self.MOST_ROWS then break end
        local data = list[index]
        local widget
        if data.going then
            local going = self.going[data.going]
            widget = going and going.widget
        end
        if not widget then
            used = used + 1
            widget = self.pool[used]
            if not widget then
                widget = NewRow(self)
                self.pool[used] = widget
            end
            FillRow(widget, data, now)
            widget:SetAlpha(1)
            widget.lit:SetAlpha(0)
        end
        shown = shown + 1
        Stripe(widget, index)
        local height = RowHeight(self, widget)
        local share = data.going and self.going[data.going] and self.going[data.going].share or 1
        widget:SetHeight(math.max(1, height * share))
        widget:ClearAllPoints()
        widget:SetPoint("TOPLEFT", self.body, "TOPLEFT", PAD + (widget.slide or 0), -y)
        widget:SetWidth(width)
        widget:Show()
        y = y + height * share
    end
    for index = used + 1, #self.pool do self.pool[index]:Hide() end
    for _, going in pairs(self.going) do
        if going.widget and not going.widget:IsShown() then going.widget:Hide() end
    end

    local nothing = #list == 0
    self.empty:SetShown(nothing)
    self.headings:SetShown(not nothing)
    if nothing then y = 44 + self.ROW + 6 end
    self.footer:SetText(L.Format("%d up", self.upCount or 0))
    self.frame:SetHeight(HEADER + 1 + y + 26)
end

--- Once a second: the LEFT words only, unless something moved.
function AuctionTrackerUI:Tick()
    local logic = Logic()
    if not logic then return end
    local now = Now()
    if self.drawnVersion ~= logic.version or (self.soonest and now >= self.soonest) then
        self:Refresh(true)
        return
    end
    for _, widget in ipairs(self.pool or {}) do
        if widget:IsShown() and widget.data then
            widget.left:SetText(AuctionTrackerUI.LeftText(widget.data.ends, widget.data.roughEnd, now))
        end
    end
end

--------------------------------------------------------------------------------
-- Going: a sale or a fade
--------------------------------------------------------------------------------

--- A frame of its own for a row that is going, so the pool can move on.
local function GoingWidget(self, data, now)
    local widget = NewRow(self)
    FillRow(widget, data, now)
    widget.slide = 0
    return widget
end

--- Done with a going row: its frame is let go and the list closes up.
local function Gone(self, key)
    local going = self.going[key]
    if not going then return end
    self.going[key] = nil
    if going.widget then
        going.widget:Hide()
        going.widget:SetParent(nil)
    end
    if going.stamp then going.stamp:Hide() end
    self:Refresh(true)
end

local function Collapse(self, key, seconds, delay)
    local going = self.going[key]
    ns.Motion:Run(going, "collapse", seconds, function(p)
        going.share = 1 - p
        self:Layout()
    end, { delay = delay, done = function() Gone(self, key) end })
end

--- A row that left without a sale fades out.
function AuctionTrackerUI:Fade(data, index)
    local level = Logic() and Logic():EffectsLevel() or "full"
    if level == "off" or not data.key then return end
    local widget = GoingWidget(self, data)
    local going = { data = data, index = index, widget = widget, share = 1 }
    self.going[data.key] = going
    ns.Motion:Run(widget, "fade", self.FADE, function(p) widget:SetAlpha(1 - p) end, {
        ease = false,
        done = function() Collapse(self, data.key, 0.25) end,
    })
end

--- "+money" rising off a row and fading.
function AuctionTrackerUI:Float(widget, amount)
    local label
    for _, candidate in ipairs(self.floats) do
        if not candidate.busy then label = candidate break end
    end
    if not label then
        if #self.floats >= 6 then return end
        label = Theme.CreateLabel(self.frame, "small", "gilt", "CENTER")
        pcall(label.SetFont, label, Theme.FONT, Theme.sizes.small + 1, "OUTLINE")
        pcall(label.SetDrawLayer, label, "OVERLAY", 7)
        self.floats[#self.floats + 1] = label
    end
    label.busy = true
    label:SetText("+" .. Money(amount))
    ns.Motion:Run(label, "float", 1.4, function(p)
        label:ClearAllPoints()
        label:SetPoint("BOTTOM", widget, "TOP", 10, -8 + 30 * p)
        label:SetAlpha(1 - p * p)
    end, { done = function()
        label:SetAlpha(0)
        label.busy = false
    end, ease = false })
end

--- A handful of coins bursting out of a row.
function AuctionTrackerUI:Burst(widget, count)
    for index = 1, count do
        local coin = self.coins[index]
        if not coin then
            coin = self.frame:CreateTexture(nil, "OVERLAY", nil, 6)
            coin:SetSize(11, 11)
            coin:SetTexture(COIN)
            coin:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            coin:SetAlpha(0)
            self.coins[index] = coin
        end
        local angle = math.pi * (0.1 + 0.8 * (index - 1) / math.max(1, count - 1))
        local reach = 28 + (index % 3) * 9
        local dx, dy = math.cos(angle) * reach, math.sin(angle) * reach
        ns.Motion:Run(coin, "burst", 0.9, function(p)
            coin:ClearAllPoints()
            coin:SetPoint("CENTER", widget, "CENTER", dx * p, dy * p - 20 * p * p)
            coin:SetAlpha(p < 0.6 and 1 or (1 - p) / 0.4)
        end, { done = function() coin:SetAlpha(0) end, delay = (index % 4) * 0.03 })
    end
end

--- The SOLD stamp: big and faint, landing on the row with a bounce.
local function Stamp(self, going, timing)
    local stamp = CreateFrame("Frame", nil, going.widget)
    stamp:SetSize(70, 22)
    stamp:SetPoint("CENTER", going.widget, "CENTER", 10, 0)
    pcall(stamp.SetFrameLevel, stamp, (going.widget:GetFrameLevel() or 1) + 3)
    local plate = Theme.CreatePanel(stamp, "well", "accent")
    plate:SetAllPoints()
    pcall(plate.background.SetAlpha, plate.background, 0.7)
    local word = Theme.CreateLabel(stamp, 15, "gilt", "CENTER")
    pcall(word.SetFont, word, Theme.FONT, 15, "OUTLINE")
    word:SetPoint("CENTER", 0, 0)
    word:SetText(L["SOLD"])
    pcall(stamp.SetRotation, stamp, math.rad(-8))
    stamp:SetAlpha(0)
    going.stamp = stamp
    local back = Motion().EaseOutBack or function(p) return p end
    ns.Motion:Run(stamp, "stamp", timing.stamp, function(p)
        stamp:SetScale(math.max(0.05, 2.2 - 1.2 * back(p)))
        stamp:SetAlpha(math.min(1, p * 2))
    end, { delay = timing.stampAt, ease = false })
end

--- Sold Today counting up to the new total, with a flare behind it.
function AuctionTrackerUI:CountUp(seconds, delay)
    local logic = Logic()
    if not logic then return end
    local from, to = self.shownSold or 0, logic:SoldToday()
    self.counting = true
    ns.Motion:Run(self.soldValue, "count", seconds, function(p)
        self.shownSold = math.floor(from + (to - from) * p + 0.5)
        self.soldValue:SetText(Money(self.shownSold))
        self.soldGlow:SetAlpha(p < 0.5 and p * 2 or (1 - p) * 2)
    end, { delay = delay, done = function()
        self.counting = false
        self.shownSold = logic:SoldToday()
        self.soldValue:SetText(Money(self.shownSold))
        self.soldGlow:SetAlpha(0)
    end })
end

--- Called by the logic when a sale is heard: the row that sold, the gold,
--- whether only part of a stack went, and how many sold.
function AuctionTrackerUI:OnSold(row, net, partial)
    local frame = self.frame
    local logic = Logic()
    if not (frame and frame:IsShown() and logic and row) then return end
    local level = logic:EffectsLevel()
    local timing = self.SOLD[level]
    if not timing or self.folded then
        self:Refresh(true)
        return
    end

    -- Where it stood, so it lights up in its own place.
    local index
    for i, data in ipairs(self.list or {}) do
        if data.key == row.key then index = i break end
    end
    if not index then
        self:Refresh(true)
        return
    end
    local data = {}
    for k, v in pairs(self.list[index]) do data[k] = v end
    if self.going[row.key] then return end
    local widget = GoingWidget(self, data)
    local going = { data = data, index = index, widget = widget, share = 1 }
    self.going[row.key] = going
    -- A part of a stack: the row stays with fewer, so it only lights up.
    local stays = partial and true or false
    self:Refresh(true)

    ns.Motion:Run(widget.lit, "light", timing.light, function(p) widget.lit:SetAlpha(p) end)

    if level == "subtle" then
        local fadeAt = timing.light + timing.hold
        if stays then
            ns.Motion:Run(widget.lit, "unlight", timing.fade, function(p) widget.lit:SetAlpha(1 - p) end,
                { delay = fadeAt, done = function() Gone(self, row.key) end })
        else
            ns.Motion:Run(widget, "fade", timing.fade, function(p) widget:SetAlpha(1 - p) end,
                { delay = fadeAt, done = function() Collapse(self, row.key, timing.collapse) end })
        end
        return
    end

    -- Full.
    Stamp(self, going, timing)
    if C_Timer and C_Timer.After then
        C_Timer.After(timing.burstAt, function()
            if not widget:IsShown() then return end
            self:Burst(widget, 9)
            if net and net > 0 then self:Float(widget, net) end
        end)
    end
    local slideAt = timing.light + timing.hold
    if stays then
        ns.Motion:Run(widget.lit, "unlight", timing.slide, function(p)
            widget.lit:SetAlpha(1 - p)
            if going.stamp then going.stamp:SetAlpha(1 - p) end
        end, { delay = slideAt, done = function() Gone(self, row.key) end })
    else
        ns.Motion:Run(widget, "slide", timing.slide, function(p)
            widget.slide = 60 * p
            widget:SetAlpha(1 - p)
            self:Layout()
        end, { delay = slideAt, done = function() Collapse(self, row.key, timing.collapse) end })
    end
    if net and net > 0 then self:CountUp(timing.count, slideAt + timing.slide) end
end

--------------------------------------------------------------------------------
-- Transparent
--------------------------------------------------------------------------------

-- As Goblin Gold's bar has it: the dark glass thins so the world shows
-- through, every word gets a black shadow, and the glass comes back while
-- the mouse is on the window. "Auction Tracker:" under TRANSPARENT on the
-- General page, 0 (Off, the default) to 3.

AuctionTrackerUI.SEE_THROUGH = { 0.5, 0.3, 0.15 }
AuctionTrackerUI.SEE_THROUGH_LOOK = 0.1
AuctionTrackerUI.SEE_THROUGH_FADE = 0.2

function AuctionTrackerUI.SeeThroughLevel()
    local level = tonumber(Get("auctionTrackerSeeThrough"))
    if not level or not AuctionTrackerUI.SEE_THROUGH[level] then return 0 end
    return level
end

function AuctionTrackerUI.ShadeAll(frame, on)
    if ns.GoldGoalUI and ns.GoldGoalUI.ShadeAll then ns.GoldGoalUI.ShadeAll(frame, on) end
end

function AuctionTrackerUI:SetGlass(shown)
    self.glassShown = shown
    for _, texture in ipairs(self.glass or {}) do
        pcall(texture.SetAlpha, texture, shown)
    end
end

local function MouseOn(frame)
    if not frame or type(frame.IsMouseOver) ~= "function" then return false end
    local ok, over = pcall(frame.IsMouseOver, frame)
    return ok and over == true
end

function AuctionTrackerUI:ApplySeeThrough()
    local frame = self.frame
    if not frame then return end
    local level = AuctionTrackerUI.SeeThroughLevel()
    local on = level > 0
    self.seeThroughOn = on
    AuctionTrackerUI.ShadeAll(frame, on)
    if not on then
        if self.seeWatch then self.seeWatch:SetScript("OnUpdate", nil) end
        self:SetGlass(1)
        return
    end
    local clear = AuctionTrackerUI.SEE_THROUGH[level]
    self:SetGlass(MouseOn(frame) and 1 or clear)
    if not self.seeWatch then self.seeWatch = CreateFrame("Frame", nil, frame) end
    local wait = 0
    self.seeWatch:SetScript("OnUpdate", function(_, elapsed)
        elapsed = tonumber(elapsed) or 0
        wait = wait - elapsed
        if wait <= 0 then
            wait = AuctionTrackerUI.SEE_THROUGH_LOOK
            self.glassTarget = MouseOn(frame) and 1 or clear
        end
        local target = self.glassTarget or clear
        local shown = self.glassShown or 1
        if shown == target then return end
        local motion = Motion()
        if motion and motion.Level and motion.Level() == "off" then
            self:SetGlass(target)
            return
        end
        local step = elapsed / AuctionTrackerUI.SEE_THROUGH_FADE
        if shown < target then
            self:SetGlass(math.min(target, shown + step))
        else
            self:SetGlass(math.max(target, shown - step))
        end
    end)
end

--- Set the level, 0 (off) to 3. False for a level it lacks.
function AuctionTrackerUI:SetSeeThrough(level)
    level = tonumber(level)
    if not level or (level ~= 0 and not AuctionTrackerUI.SEE_THROUGH[level]) then return false end
    ns.Config:Set("auctionTrackerSeeThrough", level)
    self.glassTarget = nil
    self:ApplySeeThrough()
    return true
end

return AuctionTrackerUI
