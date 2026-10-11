-- UI/BuyQuantity.lua: a warning line on the auction house's buy window when
-- buying that many of a queue material costs well over the shopping list's
-- estimate (a player asked, the owner agreeing 2026-10-11).
--
-- What must hold:
--   1. The live cost walks up the listings, past the player's own units, and
--      is unknown when the listings hold too few.
--   2. The line shows only past the set percent, and not for a few copper.
--   3. 0 percent turns it off.
--   4. Only queue materials, only while the buy window shows.
--   5. The auction house's own quote beats the listings counted up.
--   6. The words carry the live cost, the estimate and the difference.

local GLOBALS = { "AuctionHouseFrame", "hooksecurefunc", "C_Timer", "C_AuctionHouse",
    "CreateFrame", "UIParent" }
local saved = {}
for _, key in ipairs(GLOBALS) do saved[key] = _G[key] end

local ns = {}
ns.NewModule = function(name) local m = {} ns[name] = m return m end
local events = {}
ns.RegisterEvent = function(owner, event, fn) events[event] = function(...) fn(owner, event, ...) end end
ns.COLORS = { warn = "ffe8c15a" }
ns.Util = { FormatMoney = function(c) return tostring(c) .. "c" end }

local settings = { buyWarnPercent = 25 }
ns.Config = { Get = function(_, key) return settings[key] end }

local CLOTH, OTHER = 2589, 4306
ns.Queue = {
    GetShoppingList = function() return { { itemID = CLOTH, shortfall = 20 } } end,
}

-- The shopping list said 10c each.
local estimates = {}
ns.AHBuys = { Estimate = function(_, itemID, quantity)
    if estimates[itemID] then return estimates[itemID] * quantity end
end }

-- The warning frame, faked.
local shown
ns.Theme = {
    CreatePanel = function()
        local f = { visible = false }
        function f:SetFrameStrata() end
        function f:Hide() self.visible = false; shown = nil end
        function f:Show() self.visible = true end
        function f:ClearAllPoints() end
        function f:SetPoint() end
        function f:SetWidth() end
        function f:SetHeight() end
        return f
    end,
    CreateLabel = function()
        local l = {}
        function l:SetPoint() end
        function l:SetWordWrap() end
        function l:SetText(t) self.text = t; shown = t end
        function l:GetStringHeight() return 24 end
        return l
    end,
}
CreateFrame = function() end
UIParent = {}

local timers = {}
C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end }
local function RunTimers()
    local due = timers
    timers = {}
    for _, fn in ipairs(due) do fn() end
end
hooksecurefunc = function() end

local display = { itemID = CLOTH, quantity = 20, BuyButton = {} }
function display:GetItemID() return self.itemID end
function display:GetQuantitySelected() return self.quantity end
function display:GetWidth() return 300 end
local visible = true
local frame = { BuyDisplay = display }
function frame:IsVisible() return visible end
AuctionHouseFrame = { CommoditiesBuyFrame = frame }

local listings = {}
C_AuctionHouse = {
    GetNumCommoditySearchResults = function() return #listings end,
    GetCommoditySearchResultInfo = function(_, i) return listings[i] end,
}

assert(loadfile(lfs_cwd .. "/UI/BuyQuantity.lua"))("Blackthornes_TS", ns)
local BQ = ns.BuyQuantity
BQ:OnEnable()
-- Small numbers below; the copper floor has its own check.
BQ.WARN_MIN_COPPER = 10

-- 1. Up the listings, past your own.
assert(BQ.CostUp({ { unitPrice = 10, quantity = 3 }, { unitPrice = 14, quantity = 50 } }, 20) == 3 * 10 + 17 * 14)
assert(BQ.CostUp({ { unitPrice = 10, quantity = 5, own = 5 }, { unitPrice = 14, quantity = 50 } }, 20) == 20 * 14,
    "your own units are not bought")
assert(BQ.CostUp({ { unitPrice = 10, quantity = 3 } }, 20) == nil, "too few listed: unknown")
assert(BQ.CostUp({}, 0) == nil)

-- 2. 20 at 10c expected 200c. Listed 3 at 10 and the rest at 14: 268c, 34% over.
estimates[CLOTH] = 10
listings = { { unitPrice = 10, quantity = 3 }, { unitPrice = 14, quantity = 50, numOwnerItems = 0 } }
BQ:CheckCost()
assert(BQ.warnFrame and BQ.warnFrame.visible, "34% over shows the line")
assert(shown:find("Buying 20 costs", 1, true) and shown:find("268c", 1, true)
    and shown:find("200c", 1, true) and shown:find("68c", 1, true) and shown:find("34%% over"),
    "6. both amounts, the difference and the percent: " .. tostring(shown))

-- Under the percent: 20% over hides it.
listings = { { unitPrice = 12, quantity = 50 } }
BQ:CheckCost()
assert(not BQ.warnFrame.visible, "20% over is under 25%")

-- A few copper is not worth a warning, however many percent.
BQ.WARN_MIN_COPPER = 100
estimates[CLOTH] = 1
listings = { { unitPrice = 3, quantity = 50 } }
BQ:CheckCost()
assert(not BQ.warnFrame.visible, "40c more stays quiet")
BQ.WARN_MIN_COPPER = 10

-- 3. 0 turns it off.
estimates[CLOTH] = 10
listings = { { unitPrice = 30, quantity = 50 } }
settings.buyWarnPercent = 0
BQ:CheckCost()
assert(not BQ.warnFrame.visible)
settings.buyWarnPercent = 25
BQ:CheckCost()
assert(BQ.warnFrame.visible)

-- 4. Not a queue material: nothing.
display.itemID = OTHER
estimates[OTHER] = 10
BQ:CheckCost()
assert(not BQ.warnFrame.visible)
display.itemID = CLOTH

-- The window closed: nothing.
visible = false
BQ:CheckCost()
assert(not BQ.warnFrame.visible)
visible = true

-- Updates come together: a burst of results looks once, a moment later.
events.COMMODITY_SEARCH_RESULTS_UPDATED(CLOTH)
events.COMMODITY_SEARCH_RESULTS_UPDATED(CLOTH)
assert(#timers == 1, "coalesced")
RunTimers()
assert(BQ.warnFrame.visible)
-- Another item's results are not looked at.
events.COMMODITY_SEARCH_RESULTS_UPDATED(OTHER)
assert(#timers == 0)

-- 5. Buy Now's quote beats the listings: the house says 210c for 20.
ns.AHBuys.quote = { itemID = CLOTH, quantity = 20 }
events.COMMODITY_PRICE_UPDATED(10, 210)
RunTimers()
assert(not BQ.warnFrame.visible, "the quote is 5% over")

-- Closing the auction house hides it and forgets the quote.
BQ.quoted = nil
BQ:CheckCost()
assert(BQ.warnFrame.visible)
events.AUCTION_HOUSE_CLOSED()
assert(not BQ.warnFrame.visible and BQ.quoted == nil)

-- A buy window whose parts raise: no error, no line.
AuctionHouseFrame = setmetatable({}, { __index = function() error("secret") end })
BQ:CheckCost()
assert(not BQ.warnFrame.visible)

for _, key in ipairs(GLOBALS) do _G[key] = saved[key] end
print("test_buywarn: ok")
