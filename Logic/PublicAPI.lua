-- Blackthornes Tradeskills -- Logic/PublicAPI.lua
-- Prices for other authors' addons.
--
-- The owner said yes (2026-10-12) to a small, documented price call other
-- addons can rely on, the way Tradeskills reads TradeSkillMaster's and
-- Auctionator's. The README's "For addon authors" section documents it.
--
--   BlackthornesTS_API.version                   -- 1; raised only when a call is added
--   BlackthornesTS_API.GetPrice(item)             -- copper for one, or nil
--   BlackthornesTS_API.GetPriceAge(item)          -- seconds since this account's own scan saw it, or nil
--
-- `item` is an item ID or an item link. GetPrice is the price the
-- Blackthornes addons use (Prices:GetValue's market value: your own scans,
-- then guild prices, then any price addon filling a gap). Neither call ever
-- raises; anything wrong answers nil. Never rename the global or these
-- calls, and never change what they return: other people's addons read them.

local _, ns = ...

local API = { version = 1 }

local MAX_ITEM_ID = 10000000

local function ReadItemID(item)
    if type(item) == "number" then
        if item >= 1 and item < MAX_ITEM_ID and item == math.floor(item) then return item end
        return nil
    end
    if type(item) == "string" then
        local id = tonumber(item:match("item:(%d+)") or item:match("^%s*(%d+)%s*$"))
        if id and id >= 1 and id < MAX_ITEM_ID then return id end
    end
    return nil
end

-- A link or ID read from the client inside an instance can be secret, and
-- comparing one raises; the whole read is in a pcall so a caller never sees it.
local function ItemID(item)
    local ok, id = pcall(ReadItemID, item)
    if ok then return id end
    return nil
end

local function Number(ok, value)
    if not ok or type(value) ~= "number" or value ~= value or value < 0 then return nil end
    return math.floor(value + 0.5)
end

function API.GetPrice(item)
    local id = ItemID(item)
    local prices = ns.Prices
    if not id or type(prices) ~= "table" or type(prices.GetValue) ~= "function" then return nil end
    local value = Number(pcall(prices.GetValue, prices, id, "market"))
    if value == 0 then return nil end
    return value
end

function API.GetPriceAge(item)
    local id = ItemID(item)
    local prices = ns.Prices
    if not id or type(prices) ~= "table" or type(prices.GetAge) ~= "function" then return nil end
    return Number(pcall(prices.GetAge, prices, id))
end

ns.PublicAPI = API
_G.BlackthornesTS_API = API
