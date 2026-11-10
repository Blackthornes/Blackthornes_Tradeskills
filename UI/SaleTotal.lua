-- The Sale Total in the auction house drawer's header, left of Scan (the
-- owner said build it, 2026-10-28, from a mockup; on unless unticked; moved
-- into the header 2026-10-29, from a mockup whose words he approved).
--
-- Since 2026-11-10 (the owner: "show the potential sale value of all items
-- that are in the current list that can be posted. It does not change as you
-- post items") it shows, from the moment the drawer opens, what everything on
-- the Sell list should bring in: each line's own total as its row shows it
-- (`postTotal`, "12 @ 12s16c = 1g45s92c"), leaving out lines held for the
-- other addons and lines with a note, so it follows the list's filters
-- (Hidden, Hide losses). As a listing goes up its worth moves from the list
-- into `listed`, so the number holds still; while a listing is still being
-- confirmed (Posting:AllPending) the bags may not have caught up yet, so
-- the number waits. Prices that move as a scan runs roll it to the new total
-- (PostPanel:Refresh calls Update whenever UI.SellListKey moves, and that
-- key follows Prices.changes). It reads "Potential Sale Total:" with the
-- number and no line under it. Effects Off shows the new total at once.
--
-- Saved, account wide, never rename it: `saleTotal` (the switch, nil reads
-- as on). `saleTotalBest` and `saleTotalLast` stay in the save, unread.
-- What was listed is kept for the visit only. Nothing is drawn or run while
-- the counter is hidden.

local _, ns = ...
local L = ns.L or setmetatable({ Format = string.format }, { __index = function(_, key) return key end })

local SaleTotal = ns.NewModule("SaleTotal")

SaleTotal.GAP = 8               -- between the counter and the button right of it

local COPPER_PER_GOLD = 10000

local function Level()
    return ns.Motion and ns.Motion.Level() or "full"
end

--------------------------------------------------------------------------------
-- Working it out (no frames, so the tests read these straight)
--------------------------------------------------------------------------------

--- Whether the counter is wanted at all.
function SaleTotal:IsOn()
    return not (ns.Config and ns.Config:Get("saleTotal") == false)
end

--- What one listing of `quantity` at `unitPrice` comes to, as a row shows it.
function SaleTotal.Worth(unitPrice, quantity)
    unitPrice, quantity = tonumber(unitPrice) or 0, tonumber(quantity) or 1
    if unitPrice <= 0 or quantity <= 0 then return 0 end
    return unitPrice * quantity
end

--- What the lines on the Sell list that can go up come to, and how many
--- there are. Held lines (kept for the other addons) and lines with a note
--- (not now) count for nothing.
function SaleTotal.Left(lines)
    local total, count = 0, 0
    for _, line in ipairs(lines or {}) do
        if not line.held and not line.noted and line.itemID then
            count = count + 1
            local worth = tonumber(line.postTotal)
            if not worth then worth = SaleTotal.Worth(line.unitPrice, line.postQuantity) end
            total = total + math.max(0, worth)
        end
    end
    return total, count
end

--- Whether a listing is still being confirmed, when the bags may not yet
--- show it gone.
function SaleTotal.Confirming()
    local Posting = ns.Posting
    if not (Posting and Posting.AllPending) then return false end
    local ok, list = pcall(Posting.AllPending, Posting)
    return ok and type(list) == "table" and #list > 0
end

--- Whole gold, "1,234".
function SaleTotal.Gold(copper)
    local gold = math.floor((tonumber(copper) or 0) / COPPER_PER_GOLD + 0.5)
    local Util = ns.Util
    if Util and Util.Comma then return Util.Comma(gold) end
    return tostring(gold)
end

--- Money as the counter shows it: gold with its coins in their colours,
--- silver and copper only while it is under 100g, and "0g" for nothing.
function SaleTotal.MoneyText(copper)
    local Util = ns.Util
    copper = math.max(0, math.floor((copper or 0) + 0.5))
    if not Util or not Util.FormatMoney then return tostring(copper) end
    if copper == 0 then
        -- "0g" in the gold coin's colour, as the mockup has it.
        return (Util.FormatMoney(COPPER_PER_GOLD, { short = true }):gsub("^1", "0", 1))
    end
    return Util.FormatMoney(copper, { short = true })
end

--------------------------------------------------------------------------------
-- What the list and this visit come to
--------------------------------------------------------------------------------

SaleTotal.listed = 0        -- copper listed this visit
SaleTotal.listings = 0      -- listings that went up, this visit
SaleTotal.left = 0          -- copper still on the Sell list
SaleTotal.count = 0         -- lines still on the Sell list

--- What the counter should read: what went up this visit and what is left.
function SaleTotal:Total()
    return (self.listed or 0) + (self.left or 0)
end

--- The auction house opened: nothing listed yet this visit.
function SaleTotal:NewVisit()
    self.listed, self.listings = 0, 0
    if self.counter then
        self:Settle()
        self:SetNumber(self:Total())
    end
end

--- A listing went up (Posting:ResolvePending). Its worth joins what was
--- listed; the list it left is read again on the next Update (the drawer
--- refreshes once the listing stops being confirmed), so the number holds
--- still and only glows.
function SaleTotal:NoteListed(itemID, quantity, unitPrice)
    local amount = SaleTotal.Worth(unitPrice, quantity)
    if amount <= 0 then return end
    self.listed = (self.listed or 0) + amount
    self.listings = (self.listings or 0) + 1
    if self:Showing() then self:Pop(0.06, 0.25) end
end

--------------------------------------------------------------------------------
-- The counter
--------------------------------------------------------------------------------

--- Build the counter on the drawer's header, once. UI:AttachPostButton
--- calls it with the button the counter sits left of.
function SaleTotal:Attach(bar, rightOf)
    if not bar then return end
    if not self.counter then self:Build(bar) end
    local counter = self.counter
    counter:ClearAllPoints()
    if rightOf then
        counter:SetPoint("RIGHT", rightOf, "LEFT", -SaleTotal.GAP, 0)
    else
        counter:SetPoint("RIGHT", bar, "RIGHT", -10, 0)
    end
    counter:SetShown(self:IsOn())
    self:Fit()
end

function SaleTotal:Build(bar)
    local Theme = ns.Theme
    local counter = CreateFrame("Frame", nil, bar)
    counter:SetHeight((bar.GetHeight and bar:GetHeight()) or 44)
    counter:SetWidth(60)
    counter:EnableMouse(true)
    self.counter = counter
    self.bar = bar

    -- The light behind the number: brighter the more it has been fed.
    local glow = counter:CreateTexture(nil, "BACKGROUND", nil, 3)
    glow:SetPoint("TOPLEFT", -14, -2)
    glow:SetPoint("BOTTOMRIGHT", 4, 2)
    glow:Hide()
    self.glow = glow

    local label = Theme.CreateLabel(counter, "tiny", "accent", "RIGHT")
    label:SetPoint("TOPRIGHT", counter, "TOPRIGHT", 0, -3)
    label:SetText(L["Potential Sale Total:"])
    self.label = label

    -- The number sits on its own frame, so a pop scales it alone.
    local holder = CreateFrame("Frame", nil, counter)
    holder:SetSize(60, 18)
    holder:SetPoint("RIGHT", counter, "RIGHT", 0, 0)
    self.holder = holder

    local number = holder:CreateFontString(nil, "OVERLAY")
    number:SetFont(Theme.FONT, (Theme.sizes.title or 16) + 2, "OUTLINE")
    number:SetTextColor(Theme.Unpack("accentHi"))
    number:SetJustifyH("RIGHT")
    number:SetPoint("RIGHT", holder, "RIGHT", 0, 0)
    self.number = number

    counter:SetScript("OnEnter", function(owner) SaleTotal:ShowTooltip(owner) end)
    counter:SetScript("OnLeave", function() GameTooltip:Hide() end)
    counter:SetScript("OnHide", function() SaleTotal:Settle() end)

    self.shown = self:Total()
    self:SetNumber(self.shown)
    return counter
end

--- Whether the counter shows now.
function SaleTotal:Showing()
    return self.counter ~= nil and self.counter:IsShown()
end

--- How much of the header the counter takes, with its gap.
function SaleTotal:Width()
    if not self:Showing() then return 0 end
    return (self.counterWidth or 0) + SaleTotal.GAP
end

--- As wide as its widest line, measured. The header's words give way when
--- it grows (UI:FitAuctionText).
function SaleTotal:Fit()
    if not self.counter then return end
    local Theme = ns.Theme
    local widest = 0
    for _, text in ipairs({ self.label, self.number }) do
        local width = (Theme.TextWidth and Theme.TextWidth(text)) or 0
        if type(width) == "number" and width > widest then widest = width end
    end
    widest = math.ceil(widest) + 2
    if self.holder then self.holder:SetWidth(widest) end
    if widest ~= self.counterWidth then
        self.counterWidth = widest
        self.counter:SetWidth(widest)
        if ns.UI and ns.UI.FitAuctionText then ns.UI:FitAuctionText() end
    end
end

function SaleTotal:SetNumber(copper)
    self.shown = copper or 0
    if self.number then
        self.number:SetText(SaleTotal.MoneyText(self.shown))
        self:Fit()
    end
end


--- Light the glow behind the number to `p` of its strength.
function SaleTotal:Light(p)
    if self.glow and ns.Theme and ns.Theme.LightGradient then
        ns.Theme.LightGradient(self.glow, "HORIZONTAL", "accent", 0, 0.30, p)
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
    if not Motion or Level() ~= "full" or not self.holder then return end
    size = size or 0.12
    local holder = self.holder
    Motion:Run(self, "pop", 0.32, function(p)
        holder:SetScale(1 + math.sin(p * math.pi) * size)
    end, { ease = false, done = function() holder:SetScale(1) end })

    self.heat = math.min(1, (self.heat or 0) + (glow or 0.25))
    local from = self.heat
    Motion:Run(self, "glow", 1.2, function(p)
        SaleTotal.heat = from * (1 - p)
        SaleTotal:Light(SaleTotal.heat)
    end)
end

--- Land everything at once: the counter went away mid roll.
function SaleTotal:Settle()
    if ns.Motion then ns.Motion:Stop(self, nil, true) end
    if self.holder then self.holder:SetScale(1) end
    if self.number and self.shown ~= self:Total() then self:SetNumber(self:Total()) end
    self:Light(0)
end

--------------------------------------------------------------------------------
-- What the drawer calls
--------------------------------------------------------------------------------

--- Show or hide the counter by the setting. Returns whether it shows.
function SaleTotal:SetShown(show)
    if not self.counter then return false end
    show = show ~= false and self:IsOn() or false
    if show ~= self.counter:IsShown() then
        self.counter:SetShown(show)
        if ns.UI and ns.UI.FitAuctionText then ns.UI:FitAuctionText() end
    end
    return show
end

--- What is still on the Sell list. From PostPanel:Refresh on Sell, which
--- runs again whenever the list, the bags or the prices move. The number
--- rolls to the new total, unless a listing is still being confirmed: then
--- the bags may not show it gone yet, and the number waits.
-- @param lines the lines Sell shows; held and noted ones count for nothing
-- @param heldBack how many were kept for the other addons
function SaleTotal:Update(lines, heldBack)
    self.left, self.count = SaleTotal.Left(lines)
    self.heldBack = heldBack or 0
    if not self.number or SaleTotal.Confirming() then return end
    local total = self:Total()
    if math.floor(total + 0.5) == math.floor((self.shown or 0) + 0.5) then return end
    if self:Showing() then
        self:Roll(total, 0.35)
    else
        self:SetNumber(total)
    end
end

function SaleTotal:ShowTooltip(owner)
    if not GameTooltip then return end
    local Theme = ns.Theme
    GameTooltip:SetOwner(owner, "ANCHOR_BOTTOM")
    GameTooltip:SetText(L["Potential Sale Total"], Theme.Unpack("accentHi"))
    GameTooltip:AddLine(L["What everything ready to sell should bring in, at the prices on the list. It stays the same as you list things, and follows the prices as a scan runs."],
        1, 1, 1, true)
    GameTooltip:AddLine(" ")
    local r, g, b = Theme.Unpack("muted")
    local listings = self.listings or 0
    GameTooltip:AddDoubleLine(L["Listed:"], L.Format("%d of %d", listings, listings + (self.count or 0)),
        r, g, b, 1, 1, 1)
    GameTooltip:AddDoubleLine(L["Still to List:"], SaleTotal.MoneyText(self.left or 0), r, g, b, 1, 1, 1)
    if (self.heldBack or 0) > 0 then
        GameTooltip:AddDoubleLine(L["Held Back:"], L.Format("%d (not counted)", self.heldBack), r, g, b, 1, 1, 1)
    end
    GameTooltip:Show()
end

--- Each visit to the auction house starts with nothing listed.
function SaleTotal:OnInitialize()
    if ns.RegisterEvent then
        ns.RegisterEvent(self, "AUCTION_HOUSE_SHOW", function() SaleTotal:NewVisit() end)
    end
end
