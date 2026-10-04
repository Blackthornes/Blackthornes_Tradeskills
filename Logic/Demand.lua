-- Blackthornes Tradeskills -- Logic/Demand.lua
-- How well an item sells, so you do not craft forty of something nobody buys.
--
-- Two sources, best first:
--
--   yours  -- your own listings that ended, from the Sales tab's ledger
--             (Data/Mail.lua): how many sold out of those that sold or
--             expired. Cancelled ones are left out, as the Sales tab leaves
--             them out: pulling a listing says nothing about whether it
--             would have sold. Used once MIN_OWN listings have ended.
--   market -- how fast the auction house's stock of it shrinks between your
--             scans (Prices:GetLiquidity). It under-reports, because a
--             restock hides sales, so its bar for "high" is lower.
--
-- The answer is one of three levels, "high", "some" or "low", with a line
-- saying what it was worked out from. Nothing is answered without data: an
-- item never listed and seen in fewer than three scans has no demand reading,
-- and says so rather than guessing.

local _, ns = ...

local Demand = ns.NewModule("Demand")

-- Ended listings (sold plus expired) before your own record is trusted over
-- the market's.
local MIN_OWN = 3

-- Scans of an item before its market movement means anything.
local MIN_SCANS = 3

-- Sold out of ended: at or above HIGH sells well, below SOME rarely sells.
local OWN_HIGH, OWN_SOME = 0.6, 0.3

-- Share of the listed stock gone per scan. The Prices tab draws MOVES green
-- from 15%, and this follows it.
local MARKET_HIGH, MARKET_SOME = 0.15, 0.05

local LEVELS = {
    high = { label = "High", color = "profit", rank = 3 },
    some = { label = "Some", color = "warn",   rank = 2 },
    low  = { label = "Low",  color = "loss",   rank = 1 },
}

--------------------------------------------------------------------------------
-- Your own sales, by item
--------------------------------------------------------------------------------

local ownCache, ownKey

--- The ledger folded per item, worked out again only when the ledger changes.
-- The Profit tab asks once per row, and each fold walks the whole ledger.
local function OwnByItem()
    if not (ns.Mail and ns.Mail.GetItems) then return {} end

    local entries = ns.Mail:GetLedger().entries
    local last = entries[#entries]
    local key = ("%d:%s:%s"):format(#entries, tostring(last and last.t),
        tostring(ns.Mail.LedgerCutoff and ns.Mail:LedgerCutoff() or ""))

    if ownCache and ownKey == key then return ownCache end

    local byItem = {}
    local ok, items = pcall(ns.Mail.GetItems, ns.Mail)
    if ok and type(items) == "table" then
        for _, item in ipairs(items) do
            if item.itemID then byItem[item.itemID] = item end
        end
    end

    ownCache, ownKey = byItem, key
    return byItem
end

--- Forget the cached fold. Tests call it; the cache key catches real changes.
function Demand:Forget()
    ownCache, ownKey = nil, nil
end

--------------------------------------------------------------------------------
-- The reading
--------------------------------------------------------------------------------

--- How well an item sells.
-- @return nil when there is nothing to go on, else
--         { level, source = "yours"|"market", rate, sold, ended }
function Demand:Get(itemID)
    if not itemID then return nil end

    local own = OwnByItem()[itemID]
    if own then
        local ended = (own.sold or 0) + (own.expired or 0)
        if ended >= MIN_OWN then
            local rate = own.sold / ended
            return {
                level = rate >= OWN_HIGH and "high" or rate >= OWN_SOME and "some" or "low",
                source = "yours",
                rate = rate,
                sold = own.sold,
                ended = ended,
            }
        end
    end

    if not ns.Prices then return nil end

    local record = ns.Prices.Get and ns.Prices:Get(itemID)
    if not record or type(record.history) ~= "table" or #record.history < MIN_SCANS then
        return nil
    end

    local ok, rate = pcall(ns.Prices.GetLiquidity, ns.Prices, itemID)
    if not ok or not rate then return nil end

    return {
        level = rate >= MARKET_HIGH and "high" or rate >= MARKET_SOME and "some" or "low",
        source = "market",
        rate = rate,
    }
end

--- "High", "Some" or "Low".
function Demand:Label(reading)
    return reading and LEVELS[reading.level] and LEVELS[reading.level].label or nil
end

--- The ns.COLORS / Theme colour key for a reading.
function Demand:Color(reading)
    return reading and LEVELS[reading.level] and LEVELS[reading.level].color or "muted"
end

--- A number to sort by: higher sells better. Nothing known sorts lowest.
function Demand:Rank(reading)
    if not reading or not LEVELS[reading.level] then return 0 end
    return LEVELS[reading.level].rank + (reading.rate or 0) / 10
end

--- What the reading was worked out from, in a few words.
function Demand:Describe(reading)
    if not reading then return nil end

    if reading.source == "yours" then
        return ("you sold %d of %d listed"):format(reading.sold or 0, reading.ended or 0)
    end

    return ("%d%% of its stock sells between scans"):format(math.floor((reading.rate or 0) * 100 + 0.5))
end

--- The tooltip line: "High (you sold 7 of 9 listed)".
function Demand:TooltipText(reading)
    local label = self:Label(reading)
    if not label then return nil end
    return ("%s (%s)"):format(label, self:Describe(reading))
end

--------------------------------------------------------------------------------
-- A word when queueing something that rarely sells
--------------------------------------------------------------------------------

local warned = {}

--- Say once a session, per item, that a craft being queued rarely sells.
-- Returns whether it said so.
function Demand:WarnIfLow(itemID, name)
    if not itemID or warned[itemID] then return false end

    local reading = self:Get(itemID)
    if not reading or reading.level ~= "low" then return false end

    warned[itemID] = true
    ns.Warn(("%s rarely sells: %s. Check the Sales tab before making many."):format(
        name or "This", self:Describe(reading)))
    return true
end

--- Forget which items were warned about. Tests call it.
function Demand:ForgetWarnings()
    warned = {}
end
