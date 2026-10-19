-- Blackthornes Tradeskills -- Logic/Writs.lua
-- What reaching a reputation goal with the trade camp costs, bought through
-- Craftsman's Writs.
--
-- A player's idea (2026-10-09): a writ and the item it asks for can both be
-- bought on the auction house, so one turn-in costs
--
--     the writ + the item it asks for (bought, or made from bought
--     materials, whichever is cheaper) - any money the turn-in pays
--
-- and that over the reputation it pays is the price of one point. With the
-- character's standing read from the game, that says how many writs a goal
-- (Honored, say) still needs and what they cost. The writs are
-- Data/CraftsmansWrits.lua.
--
-- Reputation is learned from the game. When the item a writ asks for leaves
-- the bags and the trade camp's standing goes up within a few seconds, that
-- is what that level of writ paid, kept per character (a racial bonus can
-- make one character's turn-ins pay more) in merchantsFavor.writRewards.
-- Until a turn-in is seen, what the guides report stands in, marked as
-- such. None of this has been seen in game yet.
--
-- Only item IDs, amounts, when, and the character's GUID are kept; no names.

local _, ns = ...
local L = ns.L or setmetatable({ Format = string.format }, { __index = function(_, key) return key end })

local Util = ns.Util

local Writs = ns.NewModule("Writs")

-- A delivery and the standing it raises arrive as separate events. Ones
-- this close together are the same turn-in.
local MATCH_SECONDS = 5

-- How long after the last of them to wait before deciding.
local SETTLE_SECONDS = 2

local WRIT_PREFIX = "craftsman's writ:"

--- Reputation goals, by the standing's raw value (Neutral starts at 0).
Writs.GOALS = {
    { key = "friendly", text = L["Friendly"], value = 3000 },
    { key = "honored",  text = L["Honored"], value = 9000 },
    { key = "revered",  text = L["Revered"], value = 21000 },
    { key = "exalted",  text = L["Exalted"], value = 42000 },
}

Writs.DEFAULT_GOAL = "honored"

--------------------------------------------------------------------------------
-- Saved data
--------------------------------------------------------------------------------

--- The account-wide store, beside the Waylaid Crates'. Never rename these
--- keys: they hold what was learned in game.
--
--   writIDs[itemID]           = writ item ID found in the game by its name
--   writRewards[guid][tier]   = { rep, money, turnIns, at }
local function Store()
    local db = ns.db
    if not db then return nil end

    db.merchantsFavor = db.merchantsFavor or {}
    local store = db.merchantsFavor
    store.writIDs = store.writIDs or {}
    store.writRewards = store.writRewards or {}
    return store
end

--- Bumped whenever something a list shows has changed, so it rebuilds.
Writs.version = 0

local function Changed()
    Writs.version = Writs.version + 1
end

local function Now()
    return GetTime and GetTime() or 0
end

local function CharacterKey()
    local ok, key = pcall(function() return ns.Config:GetCharacterKey() end)
    return ok and key or nil
end

--------------------------------------------------------------------------------
-- Writs by name
--------------------------------------------------------------------------------

local byItem, byName

local function Index()
    if byItem then return end
    byItem, byName = {}, {}
    for _, writ in ipairs(ns.CRAFTSMANS_WRITS or {}) do
        byItem[writ.item] = writ
        byName[writ.name:lower()] = writ
    end
end

--- The writ entry a "Craftsman's Writ: ..." name is, or nil.
function Writs.WritForName(name)
    if type(name) ~= "string" then return nil end
    Index()

    local lower = name:lower()
    if lower:sub(1, #WRIT_PREFIX) ~= WRIT_PREFIX then return nil end
    local wanted = lower:sub(#WRIT_PREFIX + 1):gsub("^%s+", ""):gsub("%s+$", "")
    return byName[wanted]
end

--- The writ entry that asks for this item, or nil.
function Writs.WritForItem(itemID)
    Index()
    return byItem[itemID]
end

local function ItemName(itemID)
    if not Util.HasFunction("C_Item.GetItemInfo") then return nil end

    local ok, name = pcall(C_Item.GetItemInfo, itemID)
    if ok and type(name) == "string" then return name end

    if Util.HasFunction("C_Item.RequestLoadItemDataByID") then
        pcall(C_Item.RequestLoadItemDataByID, itemID)
    end
    return nil
end

-- itemID -> writ entry, or false once its name is known and is no writ.
local seen = {}

function Writs:Classify(itemID)
    local known = seen[itemID]
    if known ~= nil then return known or nil end

    local name = ItemName(itemID)
    if not name then return nil end

    -- A secret value in an instance raises when read; it is no writ.
    local ok, writ = pcall(Writs.WritForName, name)
    if not ok then writ = nil end

    seen[itemID] = writ or false
    if writ then self:NoteWritID(writ, itemID) end
    return writ
end

--- Keep the item ID the game gave a writ. The game's beats the typed one.
function Writs:NoteWritID(writ, itemID)
    local store = Store()
    if not store or store.writIDs[writ.item] == itemID then return end
    store.writIDs[writ.item] = itemID
    Changed()
end

function Writs:GetWritID(writ)
    local store = Store()
    return (store and store.writIDs[writ.item]) or writ.writ
end

--- Look through Forever's new item IDs for writs not found yet. Once a
--- session; names the client does not have yet are read as they arrive.
function Writs:FindWrits()
    if self.searched then return end
    self.searched = true

    local range = ns.WRIT_ID_RANGE
    if not range then return end
    for itemID = range[1], range[2] do self:Classify(itemID) end
end

function Writs:OnItemInfo(itemID)
    local range = ns.WRIT_ID_RANGE
    if not self.searched or not range or type(itemID) ~= "number" then return end
    if itemID < range[1] or itemID > range[2] or seen[itemID] ~= nil then return end
    self:Classify(itemID)
end

--------------------------------------------------------------------------------
-- Standing
--------------------------------------------------------------------------------

--- The trade camp for the character's side, and where they stand with it.
--
-- @return { name, id, standing } or nil off either side; standing is the
--   raw value (Neutral starts at 0, Honored at 9000) or nil when the game
--   would not say.
function Writs:Faction()
    local result = self:ReadFaction()
    -- In an instance the game can hand out a secret value that raises when
    -- sums are done with it; then the standing is not known.
    if result and result.standing and not pcall(function() return result.standing + 0 end) then
        result.standing = nil
    end
    return result
end

function Writs:ReadFaction()
    local ok, group = pcall(UnitFactionGroup, "player")
    local camp = ok and ns.WRIT_FACTIONS and ns.WRIT_FACTIONS[group]
    if not camp then return nil end

    local result = { name = camp.name, id = camp.id }

    if Util.HasFunction("C_Reputation.GetFactionDataByID") then
        local got, data = pcall(C_Reputation.GetFactionDataByID, camp.id)
        if got and type(data) == "table" and type(data.currentStanding) == "number" then
            result.standing = data.currentStanding
            if type(data.name) == "string" then result.name = data.name end
            return result
        end
    end

    if type(GetFactionInfoByID) == "function" then
        local got, name, _, _, _, _, value = pcall(GetFactionInfoByID, camp.id)
        if got and type(value) == "number" then
            result.standing = value
            if type(name) == "string" then result.name = name end
            return result
        end
    end

    -- The ID may differ on Forever: look for the camp by name.
    if type(GetNumFactions) == "function" and type(GetFactionInfo) == "function" then
        local got, count = pcall(GetNumFactions)
        for index = 1, (got and type(count) == "number") and count or 0 do
            local read, name, _, _, _, _, value = pcall(GetFactionInfo, index)
            if read and name == camp.name and type(value) == "number" then
                result.standing = value
                return result
            end
        end
    end

    return result
end

function Writs.GoalFor(key)
    for _, goal in ipairs(Writs.GOALS) do
        if goal.key == key then return goal end
    end
    return Writs.GoalFor(Writs.DEFAULT_GOAL)
end

--- The goal reached at this standing, for "you are Friendly".
function Writs.StandingText(standing)
    if not standing then return nil end
    local text = standing < 0 and L["Unfriendly"] or L["Neutral"]
    for _, goal in ipairs(Writs.GOALS) do
        if standing >= goal.value then text = goal.text end
    end
    return text
end

--------------------------------------------------------------------------------
-- Rewards
--------------------------------------------------------------------------------

--- What a turn-in of this level pays the character playing.
--
-- @return rep, money (copper), source, turnIns
--   source is "learned" (seen paid, turnIns times) or "reported".
function Writs:GetReward(tier)
    local store = Store()
    local key = CharacterKey()
    local mine = store and key and store.writRewards[key]
    local learned = mine and mine[tier]

    if learned and learned.rep then
        return learned.rep, learned.money or 0, "learned", learned.turnIns or 1
    end

    local reported = ns.WRIT_REPUTATION and ns.WRIT_REPUTATION[tier]
    if reported then return reported, 0, "reported" end
    return nil, nil, nil
end

--- Keep one turn-in's reward. The smallest seen is kept, in case a first
--- turn-in or a buff ever pays extra.
function Writs:Learn(tier, rep, money)
    local store = Store()
    local key = CharacterKey()
    if not store or not key or not tier or not rep or rep <= 0 then return end

    store.writRewards[key] = store.writRewards[key] or {}
    local reward = store.writRewards[key][tier] or {}
    store.writRewards[key][tier] = reward

    reward.turnIns = (reward.turnIns or 0) + 1
    if not reward.rep or rep < reward.rep then
        reward.rep = rep
        reward.money = money or 0
    end
    reward.at = time()
    Changed()
end

-- What has happened lately, waiting to be put together.
local recent = {}

function Writs:Resolve()
    local delivered, rep, paid = recent.delivered, recent.rep, recent.paid

    if delivered and rep and math.abs(rep.at - delivered.at) <= MATCH_SECONDS then
        local money = (paid and math.abs(paid.at - delivered.at) <= MATCH_SECONDS) and paid.amount or 0
        self:Learn(delivered.writ.tier, rep.amount, money)
        recent = {}
        return
    end

    local now = Now()
    for key, event in pairs(recent) do
        if now - event.at > MATCH_SECONDS * 2 then recent[key] = nil end
    end
end

local function Settle()
    if C_Timer and C_Timer.After then
        C_Timer.After(SETTLE_SECONDS, function() Writs:Resolve() end)
    else
        Writs:Resolve()
    end
end

--- Read the standing again; a rise is noted.
function Writs:OnFaction()
    local faction = self:Faction()
    local standing = faction and faction.standing
    if not standing then return end

    if self.standing and standing > self.standing then
        recent.rep = { amount = standing - self.standing, at = Now() }
        Settle()
    end
    self.standing = standing
end

function Writs:OnTurnIn(_, _, money)
    recent.paid = { amount = type(money) == "number" and money or 0, at = Now() }
    -- The standing may move before or after this; look now and once more.
    self:OnFaction()
    if C_Timer and C_Timer.After then
        C_Timer.After(1, function() pcall(Writs.OnFaction, Writs) end)
    end
end

--- Compare the items writs ask for with the last look: one leaving the
--- bags, as many as its writ asks for, may be a delivery.
function Writs:OnBags()
    local counts = ns.Inventory and ns.Inventory:GetBagCounts() or {}

    local held = {}
    for itemID, count in pairs(counts) do
        if Writs.WritForItem(itemID) then held[itemID] = count end
    end

    local before = self.held
    self.held = held
    if not before then return end

    for itemID, had in pairs(before) do
        local writ = Writs.WritForItem(itemID)
        if had - (held[itemID] or 0) >= (writ.count or 1) then
            recent.delivered = { writ = writ, at = Now() }
            Settle()
        end
    end
end

--------------------------------------------------------------------------------
-- Rows
--------------------------------------------------------------------------------

--- What one of the item costs bought, and made from bought materials.
local function ItemCosts(itemID)
    local buy
    if ns.Cost and ns.Cost.GetReagentUnitCost then
        buy = ns.Cost:GetReagentUnitCost(itemID)
    elseif ns.Prices then
        buy = ns.Prices:GetValue(itemID, "lowest")
    end

    local make, recipeID
    if ns.Cost and ns.Cost.FindAnyRecipeForItem and ns.Cost.GetMaterialValue then
        recipeID = ns.Cost:FindAnyRecipeForItem(itemID)
        if recipeID then make = ns.Cost:GetMaterialValue(recipeID) end
    end
    return buy, make, make and recipeID or nil
end

local function BagCount(itemID)
    return itemID and ns.Inventory and ns.Inventory:GetBagCount(itemID) or 0
end

--- Bags, bank and mail on this character.
local function OwnedCount(itemID)
    local inventory = ns.Inventory
    if not (itemID and inventory) then return 0 end
    if inventory.GetOwnedCount then return inventory:GetOwnedCount(itemID) or 0 end
    return BagCount(itemID)
end

--- Every writ, with what a turn-in costs and what a point of reputation
--- costs. Cheapest reputation first; writs not fully priced come last.
function Writs:GetRows()
    local rows = {}

    for _, writ in ipairs(ns.CRAFTSMANS_WRITS or {}) do
        local writID = self:GetWritID(writ)
        -- Only what is listed now: with none on the auction house there is
        -- no writ to buy, so no price and no total (Prices:ListedNow).
        local writPrice, noneListed
        if writID and ns.Prices then writPrice, noneListed = ns.Prices:ListedNow(writID) end
        -- How many are listed at that price, and in all.
        local onAHAtPrice, onAHTotal
        if writID and ns.Prices and ns.Prices.ListedCounts then
            onAHAtPrice, onAHTotal = ns.Prices:ListedCounts(writID, writPrice)
        end

        local count = writ.count or 1
        local buy, make, recipeID = ItemCosts(writ.item)
        local unit, how = buy, buy and "buy" or nil
        if make and (not unit or make < unit) then unit, how = make, "make" end
        local itemCost = unit and unit * count or nil

        local rep, money, source, turnIns = self:GetReward(writ.tier)

        local total
        if writPrice and itemCost then total = writPrice + itemCost - (money or 0) end

        local perRep
        if total and rep and rep > 0 then perRep = total / rep end

        rows[#rows + 1] = {
            key = writ.item,
            writ = writ,
            name = writ.name,
            prof = writ.prof,
            tier = writ.tier,
            itemID = writ.item,
            writID = writID,
            count = count,
            writPrice = writPrice,
            noneListed = noneListed or nil,
            buy = buy and buy * count or nil,
            make = make and make * count or nil,
            how = how,
            recipeID = recipeID,
            itemCost = itemCost,
            rep = rep,
            money = money,
            source = source,
            turnIns = turnIns,
            total = total,
            perRep = perRep,
            haveWrits = OwnedCount(writID),
            onAHAtPrice = onAHAtPrice,
            onAHTotal = onAHTotal,
            haveItems = BagCount(writ.item),
        }
    end

    table.sort(rows, function(a, b)
        if (a.perRep ~= nil) ~= (b.perRep ~= nil) then return a.perRep ~= nil end
        if a.perRep and a.perRep ~= b.perRep then return a.perRep < b.perRep end
        if a.tier ~= b.tier then return a.tier < b.tier end
        return a.name < b.name
    end)

    return rows
end

--------------------------------------------------------------------------------
-- Plan
--------------------------------------------------------------------------------

--- How far a goal is and what reaching it costs.
--
-- Each order can be handed in once a day, so the cheapest way is the
-- cheapest order once a day until the goal is reached, and the quickest is
-- every priced order each day, cheapest first.
--
-- @return {
--   faction, standing, goal, need,
--   perTier = { [tier] = { rep, source, writs } },
--   cheapest = { row, writs, days, cost },
--   quickest = { writs, days, cost },
-- }
function Writs:GetPlan(goalKey, rows)
    local goal = Writs.GoalFor(goalKey)
    local faction = self:Faction()
    local standing = faction and faction.standing

    local plan = {
        faction = faction,
        standing = standing,
        goal = goal,
        need = math.max(0, goal.value - (standing or 0)),
        perTier = {},
    }

    for tier = 1, #(ns.WRIT_TIERS or {}) do
        local rep, _, source = self:GetReward(tier)
        plan.perTier[tier] = {
            rep = rep,
            source = source,
            writs = (rep and rep > 0) and math.ceil(plan.need / rep) or nil,
        }
    end

    if plan.need == 0 then return plan end

    local priced = {}
    for _, row in ipairs(rows or self:GetRows()) do
        if row.perRep and row.rep and row.rep > 0 then priced[#priced + 1] = row end
    end
    if #priced == 0 then return plan end
    table.sort(priced, function(a, b) return a.perRep < b.perRep end)

    local best = priced[1]
    local writs = math.ceil(plan.need / best.rep)
    plan.cheapest = { row = best, writs = writs, days = writs, cost = writs * best.total }

    local dayRep, dayCost = 0, 0
    for _, row in ipairs(priced) do
        dayRep = dayRep + row.rep
        dayCost = dayCost + row.total
    end

    local fullDays = math.floor(plan.need / dayRep)
    local left = plan.need - fullDays * dayRep
    local quick = { writs = fullDays * #priced, days = fullDays, cost = fullDays * dayCost }
    if left > 0 then
        quick.days = quick.days + 1
        for _, row in ipairs(priced) do
            quick.writs = quick.writs + 1
            quick.cost = quick.cost + row.total
            left = left - row.rep
            if left <= 0 then break end
        end
    end
    plan.quickest = quick

    return plan
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

local function Quietly(fn)
    return function(_, _, ...)
        pcall(fn, Writs, ...)
    end
end

function Writs:OnEnable()
    pcall(self.OnBags, self)
    pcall(self.OnFaction, self)

    ns.RegisterEvent(self, "BAG_UPDATE_DELAYED", Quietly(self.OnBags))
    ns.RegisterEvent(self, "UPDATE_FACTION", Quietly(self.OnFaction))
    ns.RegisterEvent(self, "QUEST_TURNED_IN", Quietly(self.OnTurnIn))
    ns.RegisterEvent(self, "GET_ITEM_INFO_RECEIVED", Quietly(self.OnItemInfo))
    ns.RegisterEvent(self, "PLAYER_ENTERING_WORLD", Quietly(self.OnFaction))
end
