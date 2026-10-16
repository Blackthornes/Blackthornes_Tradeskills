-- Blackthornes Tradeskills -- Logic/MaterialFinder.lua
-- Where to get one enchanting material (the owner said build it,
-- 2026-10-16, after a player asked what to break for Large Radiant Shards).
--
-- The Disenchanting tab's Find a material view picks a material and lists
-- two things, both worked out here from what the addon already keeps:
--
--   * what you've gotten it from: every item your own disenchants broke
--     that gave it (DisenchantLog's per item results), with how many you
--     broke and how many times it came out;
--   * the ways to get one: break what you carry (GetBagRows), buy and break
--     from the last scan (GetAuctionRows), make and break with a craft this
--     character knows (GetCraftRows), and farm and break, from Farmer when
--     it is loaded.
--
-- Each way carries its odds (how often one disenchant gives it, from the
-- same chances the rest of the tab uses, yours once you've broken enough)
-- and what one of the material costs that way: the item's price or the
-- craft's materials, over how many one gives on average.
--
-- Farmer is asked inside a pcall and read only:
--
--     _G.BlackthornesFarmer.DisenchantFarm:Best(gives, max)
--     _G.BlackthornesFarmer.DisenchantFarm:DroppedBy(itemID)
--     _G.BlackthornesFarmer.DisenchantFarm:Show(mob)
--
-- with `gives(itemID)` answering how many of the material breaking one gives
-- on average. Only Farmer's records of your own kills are used.
--
-- Smooth play: the auction rows walk every scanned price, so they are built
-- once and kept until a scan or your disenchants move, and shared by
-- every material. The ways are worked out only while the view shows, kept
-- per material until something they read moves or KEEP passes.

local _, ns = ...
local L = ns.L or setmetatable({ Format = string.format }, { __index = function(_, key) return key end })

local MaterialFinder = ns.NewModule("MaterialFinder")

-- How long a material's ways are kept, in seconds, when nothing moved.
MaterialFinder.KEEP = 60
-- Farmer's mobs listed at most.
MaterialFinder.FARM_MOST = 3
-- Rows of each way listed at most.
MaterialFinder.PER_WAY = 5

local function Number(value)
    return type(value) == "number" and value or tonumber(value)
end

local function Clock()
    return type(GetTime) == "function" and GetTime() or 0
end

--------------------------------------------------------------------------------
-- Odds
--------------------------------------------------------------------------------

--- From a list of outcomes ({ itemID, chance, min, max, average }), the
--- chance one disenchant gives `materialID`, how many it gives when it does,
--- and how many it gives on average.
function MaterialFinder.Odds(outcomes, materialID)
    for _, outcome in ipairs(type(outcomes) == "table" and outcomes or {}) do
        if outcome.itemID == materialID then
            local chance = Number(outcome.chance) or 0
            local each = Number(outcome.average)
                or ((Number(outcome.min) or 1) + (Number(outcome.max) or Number(outcome.min) or 1)) / 2
            if chance > 0 and each > 0 then return chance, each, chance * each end
        end
    end
    return nil
end

--- How many of `materialID` breaking one `itemID` gives on average, or 0.
function MaterialFinder:Gives(itemID, materialID)
    local Disenchant = ns.Disenchant
    if not (Disenchant and itemID and materialID) then return 0 end
    local ok, outcomes = pcall(Disenchant.GetOutcomes, Disenchant, itemID)
    if not ok or type(outcomes) ~= "table" then return 0 end
    local _, _, expected = MaterialFinder.Odds(outcomes, materialID)
    return expected or 0
end

--- "Every time", or "1 in N" for one disenchant's chance.
function MaterialFinder.OddsText(chance)
    chance = Number(chance)
    if not chance or chance <= 0 then return "" end
    if chance >= 0.995 then return L["Every time"] end
    return L.Format("1 in %d", math.max(2, math.floor(1 / chance + 0.5)))
end

--- "1 in N kills", or "N a kill" when it is more than one.
function MaterialFinder.KillText(perKill)
    perKill = Number(perKill)
    if not perKill or perKill <= 0 then return "" end
    if perKill >= 0.995 then
        return L.Format("%s a kill", tostring(math.floor(perKill * 10 + 0.5) / 10))
    end
    return L.Format("1 in %d kills", math.max(2, math.floor(1 / perKill + 0.5)))
end

--------------------------------------------------------------------------------
-- What you've gotten it from
--------------------------------------------------------------------------------

--- Farmer's call, or nil when it is not loaded.
local function Farmer()
    local farmer = _G.BlackthornesFarmer
    local farm = type(farmer) == "table" and farmer.DisenchantFarm
    return type(farm) == "table" and farm or nil
end

--- Item IDs one of your characters' crafts make: { [itemID] = true }.
local function MadeByYou()
    local made = {}
    local Recipes = ns.Recipes
    if not (Recipes and Recipes.GetAccountWideOutputs) then return made end
    local ok, list = pcall(Recipes.GetAccountWideOutputs, Recipes)
    if not ok or type(list) ~= "table" then return made end
    for _, recipe in ipairs(list) do
        if type(recipe) == "table" and recipe.outputItemID then made[recipe.outputItemID] = true end
    end
    return made
end

--- Every item your disenchants broke that gave `materialID`, most often
--- first: { itemID, name, casts, times, total, how, mob }.
-- Kept per material until your disenchants move or KEEP passes, since
-- asking Farmer where each item dropped walks its records.
local had = {}

function MaterialFinder:Had(materialID)
    local rows = {}
    local log = ns.DisenchantLog
    if not (log and log.GetTable and materialID) then return rows end

    local key = tostring(log.version or 0) .. "|" .. tostring(Farmer() ~= nil)
    local now = Clock()
    local entry = had[materialID]
    if entry and entry.key == key and now >= entry.at and now - entry.at < MaterialFinder.KEEP then
        return entry.rows
    end
    had[materialID] = { key = key, at = now, rows = rows }

    local made
    local farm = Farmer()

    for itemID, record in pairs(log:GetTable().items or {}) do
        local got = type(record) == "table" and type(record.got) == "table" and record.got[materialID]
        if got and (Number(got.times) or 0) > 0 then
            made = made or MadeByYou()
            local row = {
                kind = "had",
                itemID = itemID,
                name = ns.Disenchant:ItemName(itemID),
                casts = Number(record.casts) or 0,
                times = Number(got.times) or 0,
                total = Number(got.total) or 0,
            }
            if made[itemID] then
                row.how = "made"
            elseif farm and farm.DroppedBy then
                local ok, mob = pcall(farm.DroppedBy, farm, itemID)
                if ok and type(mob) == "string" then row.how, row.mob = "looted", mob end
            end
            rows[#rows + 1] = row
        end
    end

    table.sort(rows, function(a, b)
        if a.times ~= b.times then return a.times > b.times end
        if a.casts ~= b.casts then return a.casts < b.casts end
        return (a.name or "") < (b.name or "")
    end)

    return rows
end

--------------------------------------------------------------------------------
-- The ways to get one
--------------------------------------------------------------------------------

-- Every listing from the last scan, kept until a scan or your disenchants
-- move. Not for each price that moves: at the auction house prices move
-- with every search, and this walks every scanned item.
local auction = { key = nil, rows = nil }

local function AuctionKey()
    local Prices = ns.Prices
    return table.concat({
        tostring(Prices and Prices:Count() or 0),
        tostring(Prices and Prices.GetLastScan and Prices:GetLastScan() or 0),
        tostring(ns.Disenchant.factsVersion or 0),
        tostring(ns.DisenchantLog and ns.DisenchantLog.version or 0),
    }, "|")
end

local function AuctionRows()
    local key = AuctionKey()
    if auction.key ~= key then
        local ok, rows = pcall(ns.Disenchant.GetAuctionRows, ns.Disenchant, { profitableOnly = false })
        auction.key, auction.rows = key, ok and type(rows) == "table" and rows or {}
    end
    return auction.rows
end

--- A row of a way from one of the tab's rows (bag, auction or craft).
local function FromRow(kind, source, materialID, price)
    local breakdown = source.breakdown or {}
    local chance, each, expected = MaterialFinder.Odds(breakdown.outcomes, materialID)
    if not chance then return nil end

    local row = {
        kind = kind,
        itemID = source.itemID,
        recipeID = source.recipeID,
        name = source.name,
        link = source.link,
        breakdown = breakdown,
        chance = chance,
        each = each,
        expected = expected,
        count = source.count,
        buy = source.buy,
        cost = source.cost,
        canDisenchant = source.canDisenchant,
        needs = source.needs,
        enchanter = source.enchanter,
        enchanterSkill = source.enchanterSkill,
        bought = source.bought,
        craftableNow = source.craftableNow,
        -- The tab's own row, so its detail panel can show it as it does.
        source = source,
    }
    if price and price > 0 then row.costEach = math.floor(price / expected + 0.5) end
    return row
end

--- Cheapest a material first; one with no cost after those that have one.
local function Cheapest(a, b)
    local left, right = a.costEach or math.huge, b.costEach or math.huge
    if left ~= right then return left < right end
    if a.chance ~= b.chance then return a.chance > b.chance end
    return (a.name or "") < (b.name or "")
end

local function Keep(list, most)
    for index = #list, most + 1, -1 do list[index] = nil end
    return list
end

--- Break what you carry: best odds first.
function MaterialFinder:FromBags(materialID)
    local rows = {}
    local ok, bag = pcall(ns.Disenchant.GetBagRows, ns.Disenchant, {})
    for _, source in ipairs(ok and bag or {}) do
        local row = FromRow("bag", source, materialID)
        if row then rows[#rows + 1] = row end
    end
    table.sort(rows, function(a, b)
        if a.expected ~= b.expected then return a.expected > b.expected end
        return (a.name or "") < (b.name or "")
    end)
    return Keep(rows, MaterialFinder.PER_WAY)
end

--- Buy and break, from the last scan: cheapest a material first.
function MaterialFinder:FromAuctions(materialID)
    local rows = {}
    for _, source in ipairs(AuctionRows()) do
        local row = FromRow("auction", source, materialID, source.buy)
        if row then rows[#rows + 1] = row end
    end
    table.sort(rows, Cheapest)
    return Keep(rows, MaterialFinder.PER_WAY)
end

--- Make and break, with a craft this character knows: cheapest a material
--- first.
function MaterialFinder:FromCrafts(materialID)
    local rows = {}
    local ok, crafts = pcall(ns.Disenchant.GetCraftRows, ns.Disenchant, {})
    for _, source in ipairs(ok and crafts or {}) do
        local row = FromRow("craft", source, materialID, source.cost)
        if row then rows[#rows + 1] = row end
    end
    table.sort(rows, Cheapest)
    return Keep(rows, MaterialFinder.PER_WAY)
end

--- Farm and break, from Farmer: the mobs that give the most a kill.
function MaterialFinder:FromFarming(materialID)
    local farm = Farmer()
    if not (farm and farm.Best) then return {} end

    local function gives(itemID) return MaterialFinder:Gives(itemID, materialID) end
    local ok, list = pcall(farm.Best, farm, gives, MaterialFinder.FARM_MOST)
    if not ok or type(list) ~= "table" then return {} end

    local rows = {}
    for _, mob in ipairs(list) do
        if type(mob) == "table" and type(mob.mob) == "string" and Number(mob.perKill) then
            local items = {}
            for _, item in ipairs(type(mob.items) == "table" and mob.items or {}) do
                if type(item) == "table" and Number(item.id) then
                    items[#items + 1] = { id = Number(item.id), name = item.name, corpses = Number(item.corpses) }
                end
            end
            rows[#rows + 1] = {
                kind = "farm",
                mob = mob.mob,
                name = mob.mob,
                zone = type(mob.zone) == "string" and mob.zone or nil,
                -- The zone as the player's client names it, for showing.
                shownZone = type(mob.shownZone) == "string" and mob.shownZone or nil,
                kills = Number(mob.kills) or 0,
                perKill = Number(mob.perKill),
                perHour = Number(mob.perHour),
                items = items,
            }
        end
    end
    return rows
end

-- Kept per material: { key, at, ways }.
local kept = {}

local function WaysKey(materialID)
    return table.concat({
        tostring(materialID),
        AuctionKey(),
        tostring(ns.Inventory and ns.Inventory.changes or 0),
        tostring(ns.Queue and ns.Queue.version or 0),
        tostring(ns.Recipes and ns.Recipes.Count and ns.Recipes:Count() or 0),
        tostring(Farmer() ~= nil),
    }, "|")
end

--- Every way to get one, by kind: { bag, auction, craft, farm }.
function MaterialFinder:Ways(materialID)
    if not materialID then return { bag = {}, auction = {}, craft = {}, farm = {} } end

    local key, now = WaysKey(materialID), Clock()
    local entry = kept[materialID]
    if entry and entry.key == key and now >= entry.at and now - entry.at < MaterialFinder.KEEP then
        return entry.ways
    end

    local ways = {
        bag = self:FromBags(materialID),
        auction = self:FromAuctions(materialID),
        craft = self:FromCrafts(materialID),
        farm = self:FromFarming(materialID),
    }
    kept[materialID] = { key = key, at = now, ways = ways }
    return ways
end

--- Forget what is kept, so the next question works it out again.
function MaterialFinder:Forget()
    kept = {}
    had = {}
    auction.key, auction.rows = nil, nil
end

--------------------------------------------------------------------------------
-- The material picked first
--------------------------------------------------------------------------------

--- The material the view opens on: the highest one your disenchants have
--- given you, else Strange Dust.
function MaterialFinder:FirstPick()
    local materials = ns.Disenchant and ns.Disenchant.MATERIALS or {}
    local log = ns.DisenchantLog
    local items = log and log.GetTable and log:GetTable().items or {}

    for index = #materials, 1, -1 do
        local materialID = materials[index].itemID
        for _, record in pairs(items) do
            if type(record) == "table" and type(record.got) == "table" and record.got[materialID] then
                return materialID
            end
        end
    end
    return materials[1] and materials[1].itemID or nil
end
