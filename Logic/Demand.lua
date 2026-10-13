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
--   market -- how fast the auction house's stock of it shrinks, per day
--             (Prices:GetSalesPerDay), so scanning every minute or every day
--             reads the same. It under-reports, because a restock hides
--             sales, so its bar for "high" is lower.
--
-- The answer is one of three levels, "high", "some" or "low", with a line
-- saying what it was worked out from. Nothing is answered without data: an
-- item never listed and not watched for at least an hour has no demand reading,
-- and says so rather than guessing.

local _, ns = ...
local L = ns.L or setmetatable({ Format = string.format }, { __index = function(_, key) return key end })

local Demand = ns.NewModule("Demand")

-- Ended listings (sold plus expired) before your own record is trusted over
-- the market's.
local MIN_OWN = 3

-- Sold out of ended: at or above HIGH sells well, below SOME rarely sells.
local OWN_HIGH, OWN_SOME = 0.6, 0.3

-- Share of the listed stock gone per day.
local MARKET_HIGH, MARKET_SOME = 0.30, 0.10

local LEVELS = {
    high = { label = L["High"], color = "profit", rank = 3 },
    some = { label = L["Some"], color = "warn",   rank = 2 },
    low  = { label = L["Low"], color = "loss",   rank = 1 },
}

--------------------------------------------------------------------------------
-- Your own sales, by item
--------------------------------------------------------------------------------

local ownCache, ownKey
local weekCache, weekKey

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
    weekCache, weekKey = nil, nil
end

--------------------------------------------------------------------------------
-- Your own sales this week
--------------------------------------------------------------------------------

local WEEK = 7 * 86400

--- Each item's sales (units) and expiries over the last seven days, from the
-- ledger. Worked out again when the ledger or the hour changes.
local function WeekByItem()
    if not (ns.Mail and ns.Mail.GetLedger) then return {} end

    local entries = ns.Mail:GetLedger().entries
    local last = entries[#entries]
    local now = time()
    local key = ("%d:%s:%d"):format(#entries, tostring(last and last.t), math.floor(now / 3600))
    if weekCache and weekKey == key then return weekCache end

    local names = ns.Mail.NameIndex and ns.Mail:NameIndex() or {}
    local byItem = {}
    local since = now - WEEK

    for _, entry in ipairs(entries) do
        local itemID = entry.itemID or names[entry.name]
        if itemID and type(entry.t) == "number" and entry.t >= since
            and not (ns.Mail.IsRolledUp and ns.Mail:IsRolledUp(entry)) then
            local week = byItem[itemID]
            if not week then
                week = { sold = 0, expired = 0 }
                byItem[itemID] = week
            end
            if entry.kind == "sold" then
                week.sold = week.sold + (entry.quantity or 1)
            elseif entry.kind ~= "removed" then
                week.expired = week.expired + 1
            end
        end
    end

    weekCache, weekKey = byItem, key
    return byItem
end

--- How many you sold of an item in the last seven days, and how many
--- listings of it expired. nil when neither happened.
-- @return { sold = units, expired = listings } or nil
function Demand:Week(itemID)
    if not itemID then return nil end
    return WeekByItem()[itemID]
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

    if not ns.Prices.GetSalesPerDay then return nil end

    local ok, rate = pcall(ns.Prices.GetSalesPerDay, ns.Prices, itemID)
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
        return L.Format("you sold %d of %d listed", reading.sold or 0, reading.ended or 0)
    end

    return L.Format("%d%% of its stock sells a day", math.floor((reading.rate or 0) * 100 + 0.5))
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
    if name then
        ns.Warn(L.Format("%s rarely sells: %s. Check the Sales tab before making many.", name, self:Describe(reading)))
    else
        ns.Warn(L.Format("This rarely sells: %s. Check the Sales tab before making many.", self:Describe(reading)))
    end
    return true
end

--- Forget which items were warned about. Tests call it.
function Demand:ForgetWarnings()
    warned = {}
end
