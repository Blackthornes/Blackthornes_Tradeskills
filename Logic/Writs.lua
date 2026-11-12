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
-- Only item IDs, amounts, when, and the character's GUID are kept; no
-- player names. The one name kept is a writ's customer, below.
--
-- Customers (a viewer's idea, the owner said build it, 2026-11-12): when a
-- writ is handed in, the NPC taking it, the zone and the spot are kept,
-- account wide, in merchantsFavor.writCustomers[item the writ asks for] =
-- { name, zone, mapID, x, y, at }. A writ taken into the quest log notes
-- the log's map spot for it first (fromLog), and the NPC's own spot
-- replaces that. Learned only from play, never from outside data. The writ
-- list groups by them (Group By: Zone), and a zone can be skipped
-- (merchantsFavor.writSkipZones[zone] = true).
--
-- Sealed writs (the owner, 2026-10-19: "we need our addons to learn how
-- these work"): mobs drop a Sealed Journeyman's or Expert's Writ, and
-- tearing it open gives one Craftsman's Writ. When a sealed writ leaves the
-- bags and a Craftsman's Writ comes in within a few seconds, that opening
-- is counted, account wide, in merchantsFavor.sealedWrits[sealedID] =
-- { opens, writs = { [item the writ asks for] = count }, name, at }. The
-- item tooltip and the Writs tab read it back. Nothing is opened for the
-- player.
--
-- Coin bags (the owner, 2026-10-24): a turn-in also gives a bag of coins,
-- one item ID for each level of writ. An item that comes into the bags with
-- a turn-in is noted as that level's bag (merchantsFavor.writBags[tier] =
-- { [itemID] = time }); when one leaves the bags and money comes in within
-- a few seconds, away from a vendor, mailbox, auction house or trade, that
-- opening is counted, account wide, in merchantsFavor.coinBags[itemID] =
-- { opens, copper, at }. The average comes off a turn-in's cost as money
-- back. Nothing is opened for the player.

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
--   writBags[tier]            = { [coin bag item ID] = time first seen }
--   coinBags[itemID]          = { opens, copper (in all), at }
--   writCustomers[itemID]     = { name, zone, mapID, x, y, at, fromLog }
--   writSkipZones[zone]       = true
local function Store()
    local db = ns.db
    if not db then return nil end

    db.merchantsFavor = db.merchantsFavor or {}
    local store = db.merchantsFavor
    store.writIDs = store.writIDs or {}
    store.writRewards = store.writRewards or {}
    store.sealedWrits = store.sealedWrits or {}
    store.writBags = store.writBags or {}
    store.coinBags = store.coinBags or {}
    store.writCustomers = store.writCustomers or {}
    store.writSkipZones = store.writSkipZones or {}
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

local byItem, byName, typedWrit

local function Index()
    if byItem then return end
    byItem, byName, typedWrit = {}, {}, {}
    for _, writ in ipairs(ns.CRAFTSMANS_WRITS or {}) do
        byItem[writ.item] = writ
        byName[writ.name:lower()] = writ
        if writ.writ then typedWrit[writ.writ] = writ end
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

--------------------------------------------------------------------------------
-- Writs in the client's language
--------------------------------------------------------------------------------
-- A Chinese client calls Craftsman's Writ: Blue Overalls "工匠文书：蓝色罩衫"
-- (a player's report, 2026-11-09), so the English names above find nothing.
-- The game names the item a writ asks for in the same words, and a writ
-- whose ID is known (typed in the data, or found before) shows what goes in
-- front of it. Both read from the client, nothing typed.

local function EnglishClient()
    local ok, locale = pcall(function() return GetLocale and GetLocale() end)
    if not ok or type(locale) ~= "string" then return true end
    return locale:sub(1, 2) == "en"
end
Writs.EnglishClient = EnglishClient

local function Trim(text)
    return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- [the client's lower-case name of the item asked for] = writ entry
local clientNames, clientPrefix, clientReady
local clientDirty = true
-- itemIDs whose names came before the client's names could judge them.
local waiting = {}

local function BuildClientNames()
    Index()
    clientDirty = false
    local names, missing = {}, false
    for _, writ in ipairs(ns.CRAFTSMANS_WRITS or {}) do
        local name = ItemName(writ.item)
        if name then names[Trim(name:lower())] = writ else missing = true end
    end

    local prefix
    local store = Store()
    for _, writ in ipairs(ns.CRAFTSMANS_WRITS or {}) do
        local writID = (store and store.writIDs[writ.item]) or writ.writ
        if writID then
            local writName, itemName = ItemName(writID), ItemName(writ.item)
            if writName and itemName then
                local whole, tail = writName:lower(), Trim(itemName:lower())
                if #whole > #tail and whole:sub(-#tail) == tail then
                    prefix = whole:sub(1, #whole - #tail)
                    break
                end
            end
        end
    end

    clientNames, clientPrefix = names, prefix
    clientReady = prefix ~= nil and not missing
end

--- The writ entry a writ's name in the client's own language is, or nil.
--- The second answer is false while the client has not given every name
--- needed to be sure.
function Writs.WritForClientName(name)
    if type(name) ~= "string" then return nil, true end
    if clientDirty then BuildClientNames() end
    if not clientPrefix then return nil, false end

    local lower = name:lower()
    if lower:sub(1, #clientPrefix) ~= clientPrefix then return nil, clientReady end
    local writ = clientNames[Trim(lower:sub(#clientPrefix + 1))]
    return writ, writ ~= nil or clientReady
end

--- Judge again the items that came before the client's names did.
function Writs:RetryWaiting()
    self.retrySoon = nil
    local list = waiting
    waiting = {}
    for itemID in pairs(list) do
        seen[itemID] = nil
        self:Classify(itemID)
    end
end

local function RetrySoon()
    if Writs.retrySoon or not next(waiting) then return end
    Writs.retrySoon = true
    if C_Timer and C_Timer.After then
        C_Timer.After(0.5, function() Writs:RetryWaiting() end)
    else
        Writs:RetryWaiting()
    end
end

function Writs:Classify(itemID)
    local known = seen[itemID]
    if known ~= nil then return known or nil end

    local name = ItemName(itemID)
    if not name then return nil end

    -- A secret value in an instance raises when read; it is no writ.
    local ok, writ = pcall(Writs.WritForName, name)
    if not ok then writ = nil end

    -- Another language names the writ in its own words. Until the client
    -- has given every name that takes, judge it again later.
    if ok and not writ and not EnglishClient() then
        local okLocal, found, ready = pcall(Writs.WritForClientName, name)
        if okLocal and found then
            writ = found
        elseif okLocal and not ready then
            waiting[itemID] = true
            return nil
        end
    end

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
    -- A name the client's own writ names are built from has come in.
    if type(itemID) == "number" and not EnglishClient() then
        Index()
        local store = Store()
        local known = byItem[itemID] or typedWrit[itemID]
        if not known and store then
            for _, writID in pairs(store.writIDs) do
                if writID == itemID then known = true break end
            end
        end
        if known then
            clientDirty = true
            RetrySoon()
        end
    end

    local range = ns.WRIT_ID_RANGE
    if not self.searched or not range or type(itemID) ~= "number" then return end
    if itemID < range[1] or itemID > range[2] or seen[itemID] ~= nil then return end
    self:Classify(itemID)
end

--------------------------------------------------------------------------------
-- Sealed writs
--------------------------------------------------------------------------------

--- True for a sealed writ's name ("Sealed Journeyman's Writ").
function Writs.IsSealedName(name)
    if type(name) ~= "string" then return false end
    local lower = name:lower()
    return lower:find("^sealed ") ~= nil and lower:find("writ$") ~= nil
end

-- itemID -> true for a sealed writ, false once its name says it is not.
local sealedSeen = {}

function Writs:IsSealed(itemID)
    local known = sealedSeen[itemID]
    if known ~= nil then return known end

    local name = ItemName(itemID)
    if not name then return false end

    local ok, sealed = pcall(Writs.IsSealedName, name)
    sealedSeen[itemID] = ok and sealed or false
    return sealedSeen[itemID]
end

--- Count one opening: the sealed writ, and the writ it gave.
function Writs:LearnOpen(sealedID, writ)
    local store = Store()
    if not store or not sealedID or not writ then return end

    local record = store.sealedWrits[sealedID] or {}
    store.sealedWrits[sealedID] = record
    record.opens = (record.opens or 0) + 1
    record.writs = record.writs or {}
    record.writs[writ.item] = (record.writs[writ.item] or 0) + 1
    record.name = ItemName(sealedID) or record.name
    record.at = time()
    Changed()
end

--- What a sealed writ has opened into, or nil before the first opening.
-- @return { opens, rows = { { writ, count } } (most first, at most `most`),
--   worth (the writ inside on average, copper; nil unless every writ it
--   gave has a price) }
function Writs:SealedInfo(sealedID, most)
    local store = Store()
    local record = store and store.sealedWrits[sealedID]
    if not record or not record.opens or record.opens <= 0 then return nil end

    local rows, total, priced = {}, 0, true
    for item, count in pairs(record.writs or {}) do
        local writ = Writs.WritForItem(item)
        if writ then
            rows[#rows + 1] = { writ = writ, count = count }
            local writID = self:GetWritID(writ)
            local price = writID and ns.Prices and ns.Prices:GetValue(writID)
            if price and price > 0 then total = total + price * count else priced = false end
        end
    end
    table.sort(rows, function(a, b)
        if a.count ~= b.count then return a.count > b.count end
        return a.writ.name < b.writ.name
    end)
    most = most or 5
    while #rows > most do table.remove(rows) end

    return {
        opens = record.opens,
        rows = rows,
        worth = (priced and #rows > 0) and math.floor(total / record.opens + 0.5) or nil,
    }
end

--- The sealed writs this writ came out of.
-- @return { { name, count, opens } }, most first
function Writs:SealedSources(writ)
    local list = {}
    local store = Store()
    if not store or not writ then return list end

    for sealedID, record in pairs(store.sealedWrits) do
        local count = record.writs and record.writs[writ.item]
        if count and count > 0 then
            list[#list + 1] = {
                name = ItemName(sealedID) or record.name or tostring(sealedID),
                count = count,
                opens = record.opens or count,
            }
        end
    end
    table.sort(list, function(a, b) return a.count > b.count end)
    return list
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

    local bag = self:BagWorth(tier) or 0
    if learned and learned.rep then
        return learned.rep, (learned.money or 0) + bag, "learned", learned.turnIns or 1
    end

    local reported = ns.WRIT_REPUTATION and ns.WRIT_REPUTATION[tier]
    if reported then return reported, bag, "reported" end
    return nil, nil, nil
end

--------------------------------------------------------------------------------
-- Coin bags
--------------------------------------------------------------------------------

--- What the coin bag a level of writ pays is worth on average, in copper,
--- or nil before one has been opened.
function Writs:BagWorth(tier)
    local store = Store()
    local bags = store and tier and store.writBags[tier]
    if not bags then return nil end

    local best
    for itemID in pairs(bags) do
        local record = store.coinBags[itemID]
        if record and (record.opens or 0) > 0 and (not best or record.opens > best.opens) then
            best = record
        end
    end
    if not best then return nil end
    return math.floor((best.copper or 0) / best.opens + 0.5)
end

--- An item that came in with a turn-in is that level's coin bag.
function Writs:NoteBag(tier, itemID)
    local store = Store()
    if not store or not tier or not itemID then return end
    store.writBags[tier] = store.writBags[tier] or {}
    if store.writBags[tier][itemID] then return end
    store.writBags[tier][itemID] = time()
    Changed()
end

--- Count one coin bag opened and the money it gave.
function Writs:LearnBag(itemID, copper)
    local store = Store()
    if not store or not itemID or type(copper) ~= "number" or copper <= 0 then return end

    local record = store.coinBags[itemID] or {}
    store.coinBags[itemID] = record
    record.opens = (record.opens or 0) + 1
    record.copper = (record.copper or 0) + copper
    record.at = time()
    Changed()
end

--- True for an item already noted as some level's coin bag.
function Writs:IsCoinBag(itemID)
    local store = Store()
    if not store then return false end
    for _, bags in pairs(store.writBags) do
        if bags[itemID] then return true end
    end
    return false
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
        recent = { turnIn = { tier = delivered.writ.tier, at = delivered.at }, arrived = recent.arrived }
        self:MatchBag()
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

--------------------------------------------------------------------------------
-- Customers: who takes each writ, and where
--------------------------------------------------------------------------------

local function Plain(value)
    if type(value) ~= "string" then return nil end
    local ok, empty = pcall(function() return value == "" end)
    if not ok or empty then return nil end
    return value
end

local function Number(value)
    if type(value) ~= "number" then return nil end
    local ok = pcall(function() return value + 0 end)
    return ok and value or nil
end

--- The writ a quest's title names, in English or the client's words.
function Writs.WritForTitle(title)
    title = Plain(title)
    if not title then return nil end
    local ok, writ = pcall(Writs.WritForName, title)
    if ok and writ then return writ end
    if not EnglishClient() then
        local okLocal, found = pcall(Writs.WritForClientName, title)
        if okLocal and found then return found end
    end
    return nil
end

--- Where the player stands: map ID, the map's name, x and y (0-100).
function Writs.PlayerSpot()
    local map = C_Map
    if type(map) ~= "table" or type(map.GetBestMapForUnit) ~= "function" then return nil end
    local ok, mapID = pcall(map.GetBestMapForUnit, "player")
    mapID = ok and Number(mapID) or nil
    if not mapID then return nil end
    local x, y
    if type(map.GetPlayerMapPosition) == "function" then
        local okPos, pos = pcall(map.GetPlayerMapPosition, mapID, "player")
        if okPos and pos then
            local okXY, px, py = pcall(function() return pos:GetXY() end)
            if okXY then x, y = Number(px), Number(py) end
        end
    end
    return mapID, Writs.MapName(mapID), x and x * 100, y and y * 100
end

function Writs.MapName(mapID)
    local map = C_Map
    if not mapID or type(map) ~= "table" or type(map.GetMapInfo) ~= "function" then return nil end
    local ok, info = pcall(map.GetMapInfo, mapID)
    if not ok or type(info) ~= "table" then return nil end
    local okName, name = pcall(function() return info.name end)
    return okName and Plain(name) or nil
end

local function Round(value)
    return value and math.floor(value * 10 + 0.5) / 10 or nil
end

--- Keep where a writ is handed in. A spot the quest log gave (fromLog)
--- never replaces one read standing at the customer.
function Writs:NoteCustomer(writ, customer)
    local store = Store()
    if not (store and writ and customer and customer.zone) then return false end
    local old = store.writCustomers[writ.item]
    if customer.fromLog and old and not old.fromLog then return false end
    local entry = {
        name = customer.name, zone = customer.zone, mapID = customer.mapID,
        x = Round(customer.x), y = Round(customer.y), at = time and time() or 0,
        fromLog = customer.fromLog or nil,
    }
    if old and old.name == entry.name and old.zone == entry.zone and old.x == entry.x
        and old.y == entry.y and not old.fromLog == not entry.fromLog then
        return false
    end
    store.writCustomers[writ.item] = entry
    Changed()
    return true
end

function Writs:GetCustomer(writ)
    local store = Store()
    return store and writ and store.writCustomers[writ.item] or nil
end

--- The writs the open quest window asks for: by its title, and by any
--- Craftsman's Writ among the items it wants.
function Writs:WindowWrits()
    local found, list = {}, {}
    local function Add(writ)
        if writ and not found[writ.item] then
            found[writ.item] = true
            list[#list + 1] = writ
        end
    end
    if type(GetTitleText) == "function" then
        local ok, title = pcall(GetTitleText)
        if ok then Add(Writs.WritForTitle(title)) end
    end
    if type(GetNumQuestItems) == "function" and type(GetQuestItemLink) == "function" then
        local ok, count = pcall(GetNumQuestItems)
        count = ok and Number(count) or 0
        for i = 1, math.min(count, 10) do
            local okLink, link = pcall(GetQuestItemLink, "required", i)
            local itemID = okLink and Plain(link) and tonumber(link:match("item:(%d+)"))
            if itemID then
                local okWrit, writ = pcall(self.Classify, self, itemID)
                if okWrit then Add(writ) end
            end
        end
    end
    return list
end

--- At the customer (the quest window asking for the writ, or handing out
--- what it pays): keep who and where.
function Writs:OnQuestWindow()
    local writs = self:WindowWrits()
    if #writs == 0 then return end
    local name
    if type(UnitName) == "function" then
        local ok, npc = pcall(UnitName, "npc")
        name = ok and Plain(npc) or nil
    end
    local mapID, zone, x, y = Writs.PlayerSpot()
    if not zone then return end
    for _, writ in ipairs(writs) do
        self:NoteCustomer(writ, { name = name, zone = zone, mapID = mapID, x = x, y = y })
    end
end

--- A writ taken into the quest log: its spot on the map, when the log
--- gives one, stands in until the customer is met.
function Writs:OnQuestAccepted(questID)
    questID = Number(questID)
    local log = C_QuestLog
    if not questID or type(log) ~= "table" then return end
    local title
    if type(log.GetTitleForQuestID) == "function" then
        local ok, text = pcall(log.GetTitleForQuestID, questID)
        title = ok and text or nil
    end
    local writ = Writs.WritForTitle(title)
    if not writ or type(log.GetNextWaypoint) ~= "function" then return end
    local ok, mapID, x, y = pcall(log.GetNextWaypoint, questID)
    mapID, x, y = ok and Number(mapID), ok and Number(x), ok and Number(y)
    local zone = mapID and Writs.MapName(mapID)
    if not (zone and x and y) then return end
    self:NoteCustomer(writ, { zone = zone, mapID = mapID, x = x * 100, y = y * 100, fromLog = true })
end

--- Skipped zones, by the zone's name.
function Writs:IsZoneSkipped(zone)
    local store = Store()
    return store and zone and store.writSkipZones[zone] == true or false
end

function Writs:SetZoneSkipped(zone, skipped)
    local store = Store()
    if not (store and Plain(zone)) then return false end
    store.writSkipZones[zone] = skipped and true or nil
    Changed()
    return true
end

-- A vendor, mailbox, auction house or trade window can move money and items
-- together; nothing is learned while one is open.
local busy = {}

local function Busy()
    for _, open in pairs(busy) do
        if open then return true end
    end
    return false
end

local function ReadMoney()
    if type(GetMoney) ~= "function" then return nil end
    local ok, money = pcall(GetMoney)
    if not ok or type(money) ~= "number" then return nil end
    -- A secret value raises when sums are done with it.
    if not pcall(function() return money + 0 end) then return nil end
    return money
end

--- Items that came in with a turn-in are that level's coin bag.
function Writs:MatchBag()
    local turnIn, arrived = recent.turnIn, recent.arrived
    if not (turnIn and arrived) then return end
    if math.abs(arrived.at - turnIn.at) > MATCH_SECONDS then return end
    for itemID in pairs(arrived.ids) do self:NoteBag(turnIn.tier, itemID) end
    recent.arrived = nil
end

--- A coin bag gone and money come in, close together, is one opening.
function Writs:MatchCoins()
    local opened, coins = recent.bagOpened, recent.coins
    if not (opened and coins) then return end
    if math.abs(opened.at - coins.at) > MATCH_SECONDS then return end
    self:LearnBag(opened.id, coins.amount)
    recent.bagOpened, recent.coins = nil, nil
end

--- Compare the whole bags with the last look, for coin bags coming in with
--- a turn-in and going out when opened.
function Writs:NoteBags(counts, skip)
    local before = self.allHeld
    self.allHeld = counts
    if not before or Busy() then return end

    local now, ids = Now(), nil
    for itemID, count in pairs(counts) do
        -- A turn-in gives one bag.
        if count - (before[itemID] or 0) == 1 and not skip[itemID] then
            ids = ids or {}
            ids[itemID] = true
        end
    end
    if ids then
        recent.arrived = { ids = ids, at = now }
        self:MatchBag()
    end

    for itemID, had in pairs(before) do
        if had > (counts[itemID] or 0) and self:IsCoinBag(itemID) then
            recent.bagOpened = { id = itemID, at = now }
        end
    end
    self:MatchCoins()
end

function Writs:OnMoney()
    local money = ReadMoney()
    local before = self.money
    self.money = money
    if not (money and before) or Busy() or money <= before then return end
    recent.coins = { amount = money - before, at = Now() }
    self:MatchCoins()
end

--- A sealed writ gone and a Craftsman's Writ come in, close together, is
--- one opening.
function Writs:NoteOpenings(sealed, writs)
    local sealedBefore, writsBefore = self.sealedHeld, self.writsHeld
    self.sealedHeld, self.writsHeld = sealed, writs
    if not sealedBefore or not writsBefore then return end

    local now = Now()
    for itemID, had in pairs(sealedBefore) do
        if had > (sealed[itemID] or 0) then recent.opened = { id = itemID, at = now } end
    end
    for itemID, count in pairs(writs) do
        if count > (writsBefore[itemID] or 0) then
            recent.unsealed = { writ = self:Classify(itemID), at = now }
        end
    end

    local opened, unsealed = recent.opened, recent.unsealed
    if opened and unsealed and unsealed.writ and math.abs(opened.at - unsealed.at) <= MATCH_SECONDS then
        self:LearnOpen(opened.id, unsealed.writ)
        recent.opened, recent.unsealed = nil, nil
    end
end

--- Compare the items writs ask for with the last look: one leaving the
--- bags, as many as its writ asks for, may be a delivery.
function Writs:OnBags()
    local counts = ns.Inventory and ns.Inventory:GetBagCounts() or {}

    local held, sealed, writs = {}, {}, {}
    for itemID, count in pairs(counts) do
        if Writs.WritForItem(itemID) then held[itemID] = count end
        if self:IsSealed(itemID) then
            sealed[itemID] = count
        elseif self:Classify(itemID) then
            writs[itemID] = count
        end
    end

    self:NoteOpenings(sealed, writs)

    -- What writs ask for, the writs and the sealed ones are no coin bags.
    local skip = {}
    for itemID in pairs(held) do skip[itemID] = true end
    for itemID in pairs(sealed) do skip[itemID] = true end
    for itemID in pairs(writs) do skip[itemID] = true end
    local all = {}
    for itemID, count in pairs(counts) do all[itemID] = count end
    self:NoteBags(all, skip)

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
            -- The client's own name for the item where it has one; search
            -- still finds the English name.
            name = (not EnglishClient() and ItemName(writ.item)) or writ.name,
            english = writ.name,
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
    self.money = ReadMoney()

    ns.RegisterEvent(self, "BAG_UPDATE_DELAYED", Quietly(self.OnBags))
    ns.RegisterEvent(self, "UPDATE_FACTION", Quietly(self.OnFaction))
    ns.RegisterEvent(self, "QUEST_TURNED_IN", Quietly(self.OnTurnIn))
    ns.RegisterEvent(self, "GET_ITEM_INFO_RECEIVED", Quietly(self.OnItemInfo))
    ns.RegisterEvent(self, "PLAYER_ENTERING_WORLD", Quietly(self.OnFaction))
    ns.RegisterEvent(self, "PLAYER_MONEY", Quietly(self.OnMoney))
    ns.RegisterEvent(self, "QUEST_PROGRESS", Quietly(self.OnQuestWindow))
    ns.RegisterEvent(self, "QUEST_COMPLETE", Quietly(self.OnQuestWindow))
    ns.RegisterEvent(self, "QUEST_ACCEPTED", Quietly(self.OnQuestAccepted))

    for _, pair in ipairs({
        { "MERCHANT_SHOW", "MERCHANT_CLOSED", "merchant" },
        { "MAIL_SHOW", "MAIL_CLOSED", "mail" },
        { "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED", "auction" },
        { "TRADE_SHOW", "TRADE_CLOSED", "trade" },
    }) do
        local key = pair[3]
        ns.RegisterEvent(self, pair[1], function() busy[key] = true end)
        ns.RegisterEvent(self, pair[2], function()
            busy[key] = false
            -- What moved while it was open is no opening.
            local counts = ns.Inventory and ns.Inventory:GetBagCounts()
            if counts then
                local copy = {}
                for itemID, count in pairs(counts) do copy[itemID] = count end
                self.allHeld = copy
            end
            self.money = ReadMoney()
        end)
    end
end
