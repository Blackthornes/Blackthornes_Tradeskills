-- Blackthornes Tradeskills -- Logic/AuctionatorPrices.lua
-- Auctionator's prices, after TradeSkillMaster's.
--
-- The owner said yes (2026-10-12) to Auctionator as a price source, named
-- in public like TSM. Read only, inside a pcall, through Auctionator's own
-- addon API, with no TOC dependency:
--
--   Auctionator.API.v1.GetAuctionPriceByItemID(callerID, itemID)   -- copper, or nil
--
-- Auctionator's price is the cheapest listing from the player's own scans,
-- so unlike TSM's it has Forever prices. It raises when called wrongly, hence
-- the pcall. Prices:GetValue asks here only when your scans, your guildmates'
-- and TSM have no price; "rival" never asks (it is this auction house now).
--
-- On unless unticked (`auctionatorPrices`, Settings, Sharing; never rename
-- it). Prices are read many times a redraw, so each answer is kept CACHE_FOR
-- seconds.

local _, ns = ...
local L = ns.L or setmetatable({ Format = string.format }, { __index = function(_, key) return key end })

local AuctionatorPrices = ns.NewModule("AuctionatorPrices")

AuctionatorPrices.CALLER = "Blackthornes_TS"
AuctionatorPrices.CACHE_FOR = 60
AuctionatorPrices.MAX_PRICE = 1e11    -- above this is not a price (10 million gold)
AuctionatorPrices.ASKS = { market = true, min = true, lowest = true }

local cache = {}                      -- [itemID] = { value or false, at }
AuctionatorPrices.used = 0            -- prices taken from Auctionator this session

function AuctionatorPrices:IsOn()
    return not (ns.Config and ns.Config:Get("auctionatorPrices") == false)
end

--- Auctionator's price call, or nil when Auctionator is not loaded.
function AuctionatorPrices.Call()
    local addon = rawget(_G, "Auctionator")
    local api = type(addon) == "table" and type(addon.API) == "table" and addon.API.v1
    if type(api) ~= "table" or type(api.GetAuctionPriceByItemID) ~= "function" then return nil end
    return api.GetAuctionPriceByItemID
end

function AuctionatorPrices:Loaded()
    return self.Call() ~= nil
end

local function Read(call, itemID)
    local ok, value = pcall(call, AuctionatorPrices.CALLER, itemID)
    if not ok or type(value) ~= "number" then return nil end
    if value ~= value or value <= 0 or value > AuctionatorPrices.MAX_PRICE then return nil end
    return math.floor(value + 0.5)
end

--- Auctionator's price for one, in copper, or nil. Same `which` as
--- Prices:GetValue; Auctionator keeps one price, so every `which` it
--- answers gets the same one.
function AuctionatorPrices:GetValue(itemID, which)
    if type(itemID) ~= "number" or not self:IsOn() then return nil end
    if not self.ASKS[which or "market"] then return nil end
    local call = self.Call()
    if not call then return nil end

    local now = GetTime and GetTime() or 0
    local entry = cache[itemID]
    if entry and now - entry[2] < self.CACHE_FOR then
        return entry[1] or nil
    end

    local value = Read(call, itemID)
    cache[itemID] = { value or false, now }
    return value
end

--- Forget kept answers (the setting was changed).
function AuctionatorPrices:Forget()
    cache = {}
end

--- Called by Prices:GetValue when it hands out an Auctionator price.
function AuctionatorPrices:Used()
    self.used = self.used + 1
end

function AuctionatorPrices:Describe()
    if not self:IsOn() then return L["Auctionator prices are off."] end
    if not self:Loaded() then return L["Auctionator isn't loaded, so nothing changes."] end
    if self.used == 0 then
        return L["Auctionator is loaded. It hasn't filled any gaps yet this session."]
    end
    return L["Auctionator is loaded and is filling gaps in your prices."]
end
