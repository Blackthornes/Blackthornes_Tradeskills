-- Blackthornes Tradeskills -- Logic/MerchantsFavor.lua
-- What a point of Merchant's Favor costs, bought through Waylaid Crates.
--
-- Voldar's idea (2026-10-08): handing in a Waylaid Crate does not depend on
-- your professions, so the crate and the materials that fill it can both be
-- bought on the auction house. One crate costs
--
--     the crate + its cheapest bundle - the silver the turn-in pays back
--
-- and that over the favor it pays is the price of one favor. The crates and
-- their bundles are Data/WaylaidCrates.lua.
--
-- Rewards are learned from the game. When a filled ("Sealed") crate leaves
-- the bags and Merchant's Favor and money come in within a few seconds, that
-- is what the crate paid, kept account wide in merchantsFavor.rewards by the
-- sealed crate's item ID. Filling a crate is seen the same way (a Waylaid
-- Crate goes, a Sealed one comes), which says which sealed crate each kind
-- turns into. Until a turn-in is seen, the rewards players report stand in,
-- marked as such; Artisan crates have none. None of this has been seen in
-- game yet: Merchant's Favor may be a currency or an item, so both are
-- watched.
--
-- No character names are kept: only item IDs, amounts and when.

local _, ns = ...

local Util = ns.Util

local MerchantsFavor = ns.NewModule("MerchantsFavor")

-- A turn-in, the favor and the money it pays arrive as separate events, in
-- no promised order. Ones this close together are the same turn-in.
local MATCH_SECONDS = 5

-- How long after the last of them to wait before deciding.
local SETTLE_SECONDS = 2

local FAVOR_NAME = "merchant's favor"

--------------------------------------------------------------------------------
-- Saved data
--------------------------------------------------------------------------------

--- The account-wide store. Never rename these keys: they hold what was
--- learned in game.
--
--   crateIDs[crateKey] = itemID     a crate found in the game by its name
--   links[crateKey]    = sealedID   the sealed crate that kind fills into
--   rewards[sealedID]  = { favor, money, turnIns, at }
local function Store()
    local db = ns.db
    if not db then return nil end

    db.merchantsFavor = db.merchantsFavor or {}
    local store = db.merchantsFavor
    store.crateIDs = store.crateIDs or {}
    store.links = store.links or {}
    store.rewards = store.rewards or {}
    return store
end

--- Bumped whenever something a list shows has changed, so it rebuilds.
MerchantsFavor.version = 0

local function Changed()
    MerchantsFavor.version = MerchantsFavor.version + 1
end

local function Now()
    return GetTime and GetTime() or 0
end

--------------------------------------------------------------------------------
-- Names
--------------------------------------------------------------------------------

--- The item's name if the client has it, else asks for it and says nil.
local function ItemName(itemID)
    if not Util.HasFunction("C_Item.GetItemInfo") then return nil end

    local ok, name = pcall(C_Item.GetItemInfo, itemID)
    if ok and type(name) == "string" then return name end

    if Util.HasFunction("C_Item.RequestLoadItemDataByID") then
        pcall(C_Item.RequestLoadItemDataByID, itemID)
    end
    return nil
end

--- True when `word` stands as a whole word in `text`.
local function HasWord(text, word)
    return text:find("%f[%w]" .. word .. "%f[%W]") ~= nil
end

--- The crate a "Waylaid Crate: ..." name is, or nil.
function MerchantsFavor.CrateForName(name)
    if type(name) ~= "string" then return nil end

    local lower = name:lower()
    if not lower:find("^waylaid crate") then return nil end

    for _, crate in ipairs(ns.WAYLAID_CRATES or {}) do
        local all = true
        for _, word in ipairs(crate.words) do
            if not HasWord(lower, word) then
                all = false
                break
            end
        end
        if all then return crate end
    end
    return nil
end

--- True for a filled crate's name ("Sealed Apprentice Crate"). Players
--- call it sealed; the fill spell is "stock crate", so that word is
--- taken too.
function MerchantsFavor.IsSealedName(name)
    if type(name) ~= "string" then return false end
    local lower = name:lower()
    return (lower:find("^sealed ") ~= nil or lower:find("^stocked ") ~= nil) and HasWord(lower, "crate")
end

function MerchantsFavor.IsFavorName(name)
    return type(name) == "string" and name:lower() == FAVOR_NAME
end

-- itemID -> { kind = "crate" | "sealed" | "favor", crate } or false, once
-- its name is known.
local kinds = {}

--- What an item is to this module, from its name: a Waylaid Crate (and
--- which), a sealed crate, Merchant's Favor, or nil.
function MerchantsFavor:Classify(itemID)
    local known = kinds[itemID]
    if known ~= nil then return known or nil end

    local name = ItemName(itemID)
    if not name then return nil end

    -- A secret value in an instance raises when read; it is no crate.
    local ok, kind = pcall(function()
        local crate = MerchantsFavor.CrateForName(name)
        if crate then return { kind = "crate", crate = crate } end
        if MerchantsFavor.IsSealedName(name) then return { kind = "sealed" } end
        if MerchantsFavor.IsFavorName(name) then return { kind = "favor" } end
        return false
    end)
    if not ok then kind = false end

    kinds[itemID] = kind
    if kind and kind.kind == "crate" then self:NoteCrateID(kind.crate, itemID) end
    return kind or nil
end

--- Keep the item ID the game gave a crate. The game's beats the typed one.
function MerchantsFavor:NoteCrateID(crate, itemID)
    local store = Store()
    if not store or store.crateIDs[crate.key] == itemID then return end
    store.crateIDs[crate.key] = itemID
    Changed()
end

function MerchantsFavor:GetCrateID(crate)
    local store = Store()
    return (store and store.crateIDs[crate.key]) or crate.id
end

--- Look through the item IDs where Forever's new items sit for crates not
--- found yet. Once a session; names the client does not have yet are asked
--- for and read as they arrive (OnItemInfo).
function MerchantsFavor:FindCrates()
    if self.searched then return end
    self.searched = true

    local range = ns.WAYLAID_CRATE_ID_RANGE
    if not range then return end

    for itemID = range[1], range[2] do self:Classify(itemID) end
end

function MerchantsFavor:OnItemInfo(itemID)
    local range = ns.WAYLAID_CRATE_ID_RANGE
    if not self.searched or not range or type(itemID) ~= "number" then return end
    if itemID < range[1] or itemID > range[2] or kinds[itemID] ~= nil then return end
    self:Classify(itemID)
end

--------------------------------------------------------------------------------
-- Rewards
--------------------------------------------------------------------------------

--- What handing in this crate pays.
--
-- @return favor, money (copper), source, turnIns
--   source is "learned" (seen paid, turnIns times), "reported" (what players
--   say, not seen here yet) or nil when nobody knows (Artisan crates).
function MerchantsFavor:GetReward(crate)
    local store = Store()
    local sealed = store and store.links[crate.key]
    local learned = sealed and store.rewards[sealed]

    if learned and learned.favor then
        return learned.favor, learned.money or 0, "learned", learned.turnIns or 1
    end

    if crate.favor then return crate.favor, crate.silver or 0, "reported" end
    return nil, nil, nil
end

--- Keep one turn-in's reward.
--
-- The smallest favor seen is the crate's: the Performance Bonus perk now and
-- then doubles a turn-in, and the first crate a character hands in is said
-- to bring a one-off bonus too.
function MerchantsFavor:Learn(sealedID, favor, money)
    local store = Store()
    if not store or not sealedID or not favor or favor <= 0 then return end

    local reward = store.rewards[sealedID] or {}
    store.rewards[sealedID] = reward

    reward.turnIns = (reward.turnIns or 0) + 1
    if not reward.favor or favor < reward.favor then
        reward.favor = favor
        reward.money = money or 0
    end
    reward.at = time()
    Changed()
end

-- What has come in and gone out lately, waiting to be put together.
local recent = {}

--- Put a turn-in together with the favor and money that came with it.
function MerchantsFavor:Resolve()
    local now = Now()
    local turnIn, favor, money = recent.turnIn, recent.favor, recent.money

    if turnIn and favor and math.abs(favor.at - turnIn.at) <= MATCH_SECONDS then
        local paid = (money and math.abs(money.at - turnIn.at) <= MATCH_SECONDS) and money.amount or 0
        self:Learn(turnIn.id, favor.amount, paid)
        recent = {}
        return
    end

    -- A sealed crate sold or thrown away, or favor from something else.
    for key, event in pairs(recent) do
        if now - event.at > MATCH_SECONDS * 2 then recent[key] = nil end
    end
end

local function Settle()
    if C_Timer and C_Timer.After then
        C_Timer.After(SETTLE_SECONDS, function() MerchantsFavor:Resolve() end)
    else
        MerchantsFavor:Resolve()
    end
end

function MerchantsFavor:NoteFavor(amount)
    if type(amount) ~= "number" or amount <= 0 then return end
    recent.favor = { amount = amount, at = Now() }
    Settle()
end

function MerchantsFavor:NoteMoney(amount)
    if type(amount) ~= "number" or amount <= 0 then return end
    recent.money = { amount = amount, at = Now() }
    if recent.turnIn or recent.favor then Settle() end
end

function MerchantsFavor:NoteTurnIn(sealedID)
    recent.turnIn = { id = sealedID, at = Now() }
    Settle()
end

--- Compare the crates and favor in the bags with the last look.
function MerchantsFavor:OnBags()
    local counts = ns.Inventory and ns.Inventory:GetBagCounts() or {}

    local held = {}
    for itemID, count in pairs(counts) do
        if self:Classify(itemID) then held[itemID] = count end
    end

    local before = self.held
    self.held = held
    if not before then return end

    local seen, emptied, filled, handed = {}, nil, nil, nil
    local function Look(itemID)
        if seen[itemID] then return end
        seen[itemID] = true

        local change = (held[itemID] or 0) - (before[itemID] or 0)
        if change == 0 then return end

        local kind = self:Classify(itemID)
        if kind.kind == "crate" and change < 0 then
            emptied = kind.crate
        elseif kind.kind == "sealed" and change > 0 then
            filled = itemID
        elseif kind.kind == "sealed" and change < 0 then
            handed = itemID
        elseif kind.kind == "favor" and change > 0 then
            self:NoteFavor(change)
        end
    end
    for itemID in pairs(held) do Look(itemID) end
    for itemID in pairs(before) do Look(itemID) end

    local store = Store()
    if emptied and filled and store and store.links[emptied.key] ~= filled then
        store.links[emptied.key] = filled
        Changed()
    end

    if handed then self:NoteTurnIn(handed) end
end

function MerchantsFavor:OnCurrency(currencyID, _, change)
    if not currencyID or not Util.HasFunction("C_CurrencyInfo.GetCurrencyInfo") then return end

    self.currencyNames = self.currencyNames or {}
    local name = self.currencyNames[currencyID]
    if name == nil then
        local ok, info = pcall(C_CurrencyInfo.GetCurrencyInfo, currencyID)
        name = ok and type(info) == "table" and info.name or false
        self.currencyNames[currencyID] = name
    end

    if MerchantsFavor.IsFavorName(name or nil) then self:NoteFavor(change) end
end

function MerchantsFavor:OnMoney()
    if type(GetMoney) ~= "function" then return end
    local money = GetMoney()
    if self.money and money > self.money then self:NoteMoney(money - self.money) end
    self.money = money
end

--------------------------------------------------------------------------------
-- Rows
--------------------------------------------------------------------------------

--- What one of an item costs to buy for a bundle: the reagent price the
--- rest of the addon uses (a vendor's price where one sells it, else the
--- cheapest listing), and "vendor" when a shop sets it.
--
-- A shop seen with limited stock sells a few at a time, never a bundle's
-- twenty, so here it gives way to the auction house whenever there is a
-- listing. A bundle of 20 Heavy Leather read 20s, 1s each, against 10s 58c
-- on the auction house (2026-10-09); a shop is the likeliest source, and
-- the panel now marks a bundle a vendor priced, so it shows if not.
local function UnitCost(itemID)
    if not (ns.Cost and ns.Cost.GetReagentUnitCost) then
        return ns.Prices and ns.Prices:GetValue(itemID, "lowest"), nil
    end

    local cost, source = ns.Cost:GetReagentUnitCost(itemID)
    if source == "vendor" and ns.Vendor and ns.Vendor.IsLimited and ns.Vendor:IsLimited(itemID) then
        local auction = ns.Prices and ns.Prices:GetValue(itemID, "lowest")
        if auction then return auction, nil end
    end
    return cost, source == "vendor" and "vendor" or nil
end

--- Every crate, with what it costs to buy and fill and what a favor costs.
--
-- A bundle needing more than one stack of its material is marked overStack:
-- the game cannot fill a crate from more than one stack (a known Forever
-- issue, 2026-09-18), so with opts.skipOverStack it is never the cheapest.
--
-- @param opts { skipOverStack }
-- @return rows, cheapest favor first; crates nobody knows the reward for,
--   or that are not priced, come last
function MerchantsFavor:GetRows(opts)
    opts = opts or {}
    local rows = {}

    for _, crate in ipairs(ns.WAYLAID_CRATES or {}) do
        local itemID = self:GetCrateID(crate)
        local cratePrice = itemID and ns.Prices and ns.Prices:GetValue(itemID, "lowest") or nil

        local bundles, best = {}, nil
        for _, bundle in ipairs(crate.bundles) do
            local materialID, count = bundle[1], bundle[2]
            local unit, from = UnitCost(materialID)
            local stack = Util.GetMaxStackSize(materialID)

            local entry = {
                itemID = materialID,
                count = count,
                unit = unit,
                cost = unit and unit * count or nil,
                vendor = from == "vendor",
                overStack = (stack ~= nil and count > stack) or false,
            }
            bundles[#bundles + 1] = entry

            local usable = not (entry.overStack and opts.skipOverStack)
            if entry.cost and usable and (not best or entry.cost < best.cost) then best = entry end
        end
        if best then best.best = true end

        local favor, money, source, turnIns = self:GetReward(crate)

        local total
        if cratePrice and best then total = cratePrice + best.cost - (money or 0) end

        local perFavor
        if total and favor and favor > 0 then perFavor = total / favor end

        rows[#rows + 1] = {
            key = crate.key,
            crate = crate,
            itemID = itemID,
            name = crate.label,
            tier = crate.tier,
            cratePrice = cratePrice,
            bundles = bundles,
            best = best,
            bundleCost = best and best.cost,
            favor = favor,
            money = money,
            source = source,
            turnIns = turnIns,
            total = total,
            perFavor = perFavor,
            have = itemID and ns.Inventory and ns.Inventory:GetBagCount(itemID) or 0,
        }
    end

    table.sort(rows, function(a, b)
        if (a.perFavor ~= nil) ~= (b.perFavor ~= nil) then return a.perFavor ~= nil end
        if a.perFavor and a.perFavor ~= b.perFavor then return a.perFavor < b.perFavor end
        if a.tier ~= b.tier then return a.tier < b.tier end
        return a.name < b.name
    end)

    return rows
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

--- Run an event's work, quietly: an instance hands out secret values that
--- raise when compared, and a crate count is never worth an error box.
local function Quietly(fn)
    return function(_, _, ...)
        pcall(fn, MerchantsFavor, ...)
    end
end

function MerchantsFavor:OnEnable()
    self:OnMoney()
    self:OnBags()

    ns.RegisterEvent(self, "BAG_UPDATE_DELAYED", Quietly(self.OnBags))
    ns.RegisterEvent(self, "PLAYER_MONEY", Quietly(self.OnMoney))
    ns.RegisterEvent(self, "CURRENCY_DISPLAY_UPDATE", Quietly(self.OnCurrency))
    ns.RegisterEvent(self, "GET_ITEM_INFO_RECEIVED", Quietly(self.OnItemInfo))
end
