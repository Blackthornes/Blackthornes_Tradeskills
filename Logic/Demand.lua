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
-- Listings gone from the auction house before the market's reading says
-- anything. With one or two up, one going away (sold, expired or pulled)
-- read as "100% of stock sells daily" (a player's report, 2026-11-22; the
-- owner said build it from a mockup).
local MARKET_MIN_GONE = 3
Demand.MARKET_MIN_GONE = MARKET_MIN_GONE

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
    if ns.Prices.GetListingsGone then
        local okGone, gone = pcall(ns.Prices.GetListingsGone, ns.Prices, itemID)
        if not okGone or (tonumber(gone) or 0) < MARKET_MIN_GONE then return nil end
    end

    return {
        level = Demand.MarketLevel(rate, itemID),
        source = "market",
        rate = rate,
    }
end

--------------------------------------------------------------------------------
-- High among its own kind
--------------------------------------------------------------------------------

-- A player asked (2026-11-16) why every potion read High. Potions, food and
-- bandages sell in many small stacks, so nearly all of them clear the one
-- market bar, and gear seldom does. So a market High also has to be in the
-- top KIND_TOP of its own kind (consumables against consumables, gear
-- against gear, trade goods against trade goods); the rest of the old Highs
-- read Some. Low and your own sales record are untouched, so the queue's
-- "rarely sells" warning and the Sell list's checks stay as they were. A
-- kind with fewer than KIND_MIN items read keeps the plain bar.
local KIND_TOP = 1 / 3
local KIND_MIN = 8
local KINDS = { [0] = "consumable", [2] = "gear", [4] = "gear", [5] = "goods", [7] = "goods" }

local kindOf = {}

--- "consumable", "gear", "goods" or "other", from the item's class. nil
--- when the game won't say yet (not cached, so it is asked again later).
function Demand.Kind(itemID)
    local known = kindOf[itemID]
    if known then return known end

    local instant = _G.C_Item and _G.C_Item.GetItemInfoInstant
    if type(instant) ~= "function" then return nil end
    local ok, _, _, _, _, _, classID = pcall(instant, itemID)
    if not ok or type(classID) ~= "number" then return nil end

    local kind = KINDS[classID] or "other"
    kindOf[itemID] = kind
    return kind
end

-- Each kind's bar: the share an item must reach to be in its kind's top
-- KIND_TOP. Worked out again when a scan finishes or the hour turns, over
-- frames (the smooth play rule: the price table holds thousands of items);
-- the last bars stand until the new ones are done.
local cutoffs, cutoffKey, building

local function CutoffsFrom(shares)
    local result = {}
    for kind, list in pairs(shares) do
        if #list >= KIND_MIN then
            table.sort(list)
            local index = math.max(1, #list - math.floor(#list * KIND_TOP) + 1)
            result[kind] = list[index]
        end
    end
    return result
end

local function ReadShare(shares, itemID)
    local kind = Demand.Kind(itemID)
    if not kind then return end
    local ok, share = pcall(ns.Prices.GetSalesPerDay, ns.Prices, itemID)
    if not ok or type(share) ~= "number" then return end
    local list = shares[kind]
    if not list then
        list = {}
        shares[kind] = list
    end
    list[#list + 1] = share
end

local function Cutoffs()
    if not (ns.Prices and ns.Prices.GetTable and ns.Prices.GetSalesPerDay) then return nil end

    local key = ("%s:%d"):format(tostring(ns.Prices.scanCount or 0), math.floor(time() / 3600))
    if cutoffKey == key or building == key then return cutoffs end

    local ok, priceTable = pcall(ns.Prices.GetTable, ns.Prices)
    if not ok or type(priceTable) ~= "table" then return cutoffs end

    local itemIDs = {}
    for itemID in pairs(priceTable) do
        if type(itemID) == "number" then itemIDs[#itemIDs + 1] = itemID end
    end

    local Util = ns.Util
    if not (Util and Util.NewWorker) then
        local shares = {}
        for _, itemID in ipairs(itemIDs) do ReadShare(shares, itemID) end
        cutoffs, cutoffKey = CutoffsFrom(shares), key
        return cutoffs
    end

    local shares = {}
    building = key
    local worker = Util.NewWorker({
        budgetMs = 2,
        onItem = function(itemID) ReadShare(shares, itemID) end,
        onDone = function()
            cutoffs, cutoffKey, building = CutoffsFrom(shares), key, nil
        end,
        onCancel = function() building = nil end,
    })
    worker:Start(itemIDs)
    return cutoffs
end

--- The level for a share of the listed stock gone each day. With an item,
--- High also needs the item to be in the top of its own kind.
function Demand.MarketLevel(share, itemID)
    if share < MARKET_SOME then return "low" end
    if share < MARKET_HIGH then return "some" end
    if itemID then
        local bars = Cutoffs()
        local kind = bars and Demand.Kind(itemID)
        local bar = kind and bars[kind]
        if bar and share < bar then return "some" end
    end
    return "high"
end

--- Forget the kinds' bars. Tests call it; a scan or the hour redoes them.
function Demand:ForgetKinds()
    cutoffs, cutoffKey, building = nil, nil, nil
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
