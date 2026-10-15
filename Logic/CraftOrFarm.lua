-- Blackthornes Tradeskills -- Logic/CraftOrFarm.lua
-- Craft or farm: gold an hour of your own time (the owner said yes,
-- 2026-10-15, from a mockup).
--
-- For each craft the character playing knows, three ways to get the gold:
--
--   farm + craft     farm the materials yourself, craft, sell what it makes
--   farm + sell      farm the materials and sell them as they are
--   buy + craft      buy the materials and craft (the Profit tab's profit)
--
-- The first two are gold an hour of your time: farming time comes from
-- Blackthornes Farmer, which times your own kills, skins and gathers
-- (its Logic/Pace.lua), read inside a pcall and read only:
--
--     _G.BlackthornesFarmer.Pace:ForItem(itemID)
--       -- { seconds, kind, source, zone, samples, perAction }, or nil and
--       -- { samples } while your own farming of it is too little to time
--
-- and crafting time from your own casts (Logic/CraftTime.lua). Buy + craft
-- stays a profit for one craft, not an hour: a craft takes seconds, so any
-- profit looks huge an hour, and that number means little.
--
-- Materials a vendor keeps in stock (vials, thread) are bought on every
-- way. A material a craft of yours makes, and that you have no farming pace
-- for itself, is followed down to what it is made from (a Bolt of Silk
-- Cloth to its Silk Cloth), and those casts count as crafting time.
-- Walking to the spot and selling are not counted. Without Farmer, or
-- before your own farming of a material is enough, the farm ways are
-- unknown, never guessed from drop tables.
--
-- Worked out only while asked: the Your time view (UI/YourTimeView.lua)
-- and Farmer's item tooltip, through
--
--     _G.BlackthornesTS.CraftOrFarm:ForMaterial(itemID)
--       -- { name, recipeID, perHour, rawPerHour } for the craft that makes
--       -- the most an hour from farming it, when that beats selling it;
--       -- nil otherwise, and nil until the list is built
--
-- A build goes through the crafts a few a frame (BUDGET) and is kept KEEP
-- seconds. Nothing is saved.

local _, ns = ...
local L = ns.L or setmetatable({ Format = string.format }, { __index = function(_, key) return key end })

local CraftOrFarm = ns.NewModule("CraftOrFarm")

-- Crafts worked out a frame.
CraftOrFarm.BUDGET = 8
-- Seconds a built list is kept.
CraftOrFarm.KEEP = 60
-- How deep a material is followed into the crafts that make it.
CraftOrFarm.DEPTH = 3

CraftOrFarm.version = 0

local function Clock()
    return type(GetTime) == "function" and GetTime() or 0
end

--------------------------------------------------------------------------------
-- What Farmer says
--------------------------------------------------------------------------------

--- Farmer's pace call, or nil without Farmer.
function CraftOrFarm:Farmer()
    local farmer = rawget(_G, "BlackthornesFarmer")
    local pace = type(farmer) == "table" and farmer.Pace
    if type(pace) ~= "table" or type(pace.ForItem) ~= "function" then return nil end
    return pace
end

function CraftOrFarm:HasFarmer()
    return self:Farmer() ~= nil
end

--- How long you take to farm one of `itemID`: a pace table, or nil and how
--- many kills or gathers are behind it so far.
function CraftOrFarm:PaceOf(itemID, cache)
    if cache and cache[itemID] ~= nil then
        local kept = cache[itemID]
        if kept.pace then return kept.pace end
        return nil, kept.samples
    end

    local pace, samples
    local farmer = self:Farmer()
    if farmer then
        local ok, found, short = pcall(farmer.ForItem, farmer, itemID)
        if ok and type(found) == "table" and type(found.seconds) == "number" and found.seconds > 0 then
            pace = found
        elseif ok and type(short) == "table" then
            samples = tonumber(short.samples)
        end
    end

    if cache then cache[itemID] = { pace = pace or false, samples = samples or 0 } end
    if pace then return pace end
    return nil, samples or 0
end

--------------------------------------------------------------------------------
-- Prices
--------------------------------------------------------------------------------

local function Quality(itemID)
    local getInfo = (type(C_Item) == "table" and C_Item.GetItemInfo) or rawget(_G, "GetItemInfo")
    if type(getInfo) ~= "function" then return nil end
    local ok, quality = pcall(function() return select(3, getInfo(itemID)) end)
    return ok and tonumber(quality) or nil
end

--- What one of a material sells for as it is, in copper: the auction house
--- after the cut and the deposit, or a vendor, whichever is more. A grey
--- item is the vendor's price only.
function CraftOrFarm:SellValue(itemID)
    local vendor = ns.Util and ns.Util.GetVendorSellPrice and ns.Util.GetVendorSellPrice(itemID) or nil
    vendor = tonumber(vendor)
    if vendor and vendor <= 0 then vendor = nil end
    if Quality(itemID) == 0 then return vendor end

    local auction
    local market = ns.Prices and ns.Prices:GetValue(itemID)
    if type(market) == "number" and market > 0 then
        local ok, net = pcall(ns.Profit.NetFromListing, ns.Profit, itemID, market)
        auction = ok and type(net) == "number" and math.max(0, net) or nil
    end

    if auction and vendor then return math.max(auction, vendor) end
    return auction or vendor
end

--- Copper for one from a vendor that keeps it in stock, or nil.
local function Bought(itemID)
    local Vendor = ns.Vendor
    if not Vendor then return nil end
    local keeps = Vendor.KeepsInStock and Vendor:KeepsInStock(itemID)
    if not keeps then return nil end
    return Vendor:GetUnitPrice(itemID)
end

--------------------------------------------------------------------------------
-- One craft
--------------------------------------------------------------------------------

local function YieldOf(recipe)
    local low, high = tonumber(recipe.quantityMin) or 1, tonumber(recipe.quantityMax) or 1
    local yield = (low + high) / 2
    return yield > 0 and yield or 1
end

--- The materials of one craft as you would get them: bought from a vendor,
--- or farmed, with the crafts that make the rest followed down. Returns
--- { farm = { [itemID] = count }, buy = { [itemID] = count }, casts =
--- { [recipeID] = count } }.
function CraftOrFarm:Materials(recipeID, cache)
    local result = { farm = {}, buy = {}, casts = {} }
    local visited = {}

    local function Walk(id, times, depth)
        local recipe = ns.Recipes:GetAny(id)
        if not recipe then return end
        visited[id] = true
        result.casts[id] = (result.casts[id] or 0) + times

        for _, reagent in ipairs(recipe.reagents or {}) do
            local itemID, count = reagent.itemID, (tonumber(reagent.quantity) or 0) * times
            if itemID and count > 0 then
                if Bought(itemID) then
                    result.buy[itemID] = (result.buy[itemID] or 0) + count
                else
                    local sub = not self:PaceOf(itemID, cache) and depth < CraftOrFarm.DEPTH
                        and ns.Cost and ns.Cost:FindRecipeForItem(itemID) or nil
                    local subRecipe = sub and not visited[sub] and ns.Recipes:GetAny(sub)
                    if subRecipe then
                        Walk(sub, count / YieldOf(subRecipe), depth + 1)
                    else
                        result.farm[itemID] = (result.farm[itemID] or 0) + count
                    end
                end
            end
        end
        visited[id] = nil
    end

    Walk(recipeID, 1, 0)
    return result
end

--- The three ways for one craft, from its Profit analysis. Nil for a craft
--- with nothing to farm, or one that sells for nothing.
function CraftOrFarm:Work(analysis, cache)
    if type(analysis) ~= "table" or not analysis.priceable or not analysis.profit then return nil end
    local total = tonumber(analysis.totalCost) or 0
    -- What one craft brings in once sold, whoever paid for its materials.
    local made = analysis.profit + total

    local materials = self:Materials(analysis.recipeID, cache)
    if not next(materials.farm) then return nil end

    local row = {
        recipeID = analysis.recipeID,
        name = analysis.name,
        outputItemID = analysis.outputItemID,
        yield = analysis.yield or 1,
        via = analysis.via,
        made = made,
        buyProfit = analysis.profit,
        bought = 0,
        raw = 0,
        farmSeconds = 0,
        mats = {},
    }

    for itemID, count in pairs(materials.buy) do
        local unit = Bought(itemID) or 0
        row.bought = row.bought + unit * count
        row.mats[#row.mats + 1] = { itemID = itemID, count = count, bought = unit * count }
    end

    local farmKnown, rawKnown = true, true
    for itemID, count in pairs(materials.farm) do
        local pace, samples = self:PaceOf(itemID, cache)
        local value = self:SellValue(itemID)
        local mat = { itemID = itemID, count = count, pace = pace, samples = samples,
            value = value and value * count or nil }
        row.mats[#row.mats + 1] = mat

        if pace then
            mat.seconds = pace.seconds * count
            row.farmSeconds = row.farmSeconds + mat.seconds
        else
            farmKnown = false
            if not row.missing or (samples or 0) < (row.missing.samples or 0) then
                row.missing = { itemID = itemID, samples = samples or 0 }
            end
        end
        if value then row.raw = row.raw + value * count else rawKnown = false end
    end

    table.sort(row.mats, function(a, b)
        if (a.bought ~= nil) ~= (b.bought ~= nil) then return a.bought == nil end
        if (a.seconds or 0) ~= (b.seconds or 0) then return (a.seconds or 0) > (b.seconds or 0) end
        return a.itemID < b.itemID
    end)

    -- Crafting time: every cast in the tree, each at its own length.
    local craftSeconds = 0
    for id, casts in pairs(materials.casts) do
        local cast = ns.CraftTime and ns.CraftTime:GetCast(id)
        if not cast then
            craftSeconds = nil
            break
        end
        craftSeconds = craftSeconds + cast * casts
    end
    row.craftSeconds = craftSeconds

    if not farmKnown then row.farmSeconds = nil end
    if not rawKnown then row.raw = nil end

    local PerHour = ns.CraftTime and ns.CraftTime.PerHour
    if row.farmSeconds and row.farmSeconds > 0 and PerHour then
        if craftSeconds then
            row.farmCraft = PerHour(made - row.bought, row.farmSeconds + craftSeconds)
        end
        if row.raw then row.farmSell = PerHour(row.raw, row.farmSeconds) end
    end

    if row.farmCraft and (not row.farmSell or row.farmCraft >= row.farmSell) then
        row.best, row.bestValue = "craft", row.farmCraft
    elseif row.farmSell then
        row.best, row.bestValue = "raw", row.farmSell
    end

    return row
end

--------------------------------------------------------------------------------
-- The whole list, a few crafts a frame
--------------------------------------------------------------------------------

--- The crafts to weigh: those the character playing knows, in a profession
--- it still has, not ignored.
function CraftOrFarm:Crafts()
    local list = {}
    for recipeID, recipe in pairs(ns.Recipes:GetAll() or {}) do
        local dropped = ns.Recipes.IsDropped and ns.Recipes:IsDropped(recipe)
        local ignored = ns.Profit.IsIgnored and ns.Profit:IsIgnored(recipeID)
        if not dropped and not ignored and recipe.outputItemID then list[#list + 1] = recipeID end
    end
    table.sort(list)
    return list
end

local function Method()
    return ns.Profit.GetMethod and ns.Profit:GetMethod() or nil
end

--- Start a build unless one is running. `done(rows)` is called when it is
--- built (at once when `now` is true, as the tests do).
function CraftOrFarm:Build(done, now)
    if done then
        self.waiting = self.waiting or {}
        self.waiting[#self.waiting + 1] = done
    end
    if self.building then return end

    local crafts, index, rows, cache = self:Crafts(), 0, {}, {}
    local method = Method()
    self.building = true

    local function Finish()
        self.building = false
        self.rows, self.builtAt = rows, Clock()
        self.version = self.version + 1

        local byMaterial = {}
        for _, row in ipairs(rows) do
            if row.best == "craft" and row.farmCraft then
                for _, mat in ipairs(row.mats) do
                    if not mat.bought then
                        local held = byMaterial[mat.itemID]
                        if not held or row.farmCraft > held.perHour then
                            byMaterial[mat.itemID] = { name = row.name, recipeID = row.recipeID,
                                perHour = row.farmCraft, rawPerHour = row.farmSell }
                        end
                    end
                end
            end
        end
        self.byMaterial = byMaterial

        local waiting = self.waiting or {}
        self.waiting = nil
        for _, callback in ipairs(waiting) do pcall(callback, rows) end
    end

    local function Step()
        local stop = index + CraftOrFarm.BUDGET
        while index < #crafts and (now or index < stop) do
            index = index + 1
            local ok, analysis = pcall(ns.Profit.Analyse, ns.Profit, crafts[index], nil, method)
            if ok and analysis then
                local fine, row = pcall(self.Work, self, analysis, cache)
                if fine and row then rows[#rows + 1] = row end
            end
        end
        if index >= #crafts then
            Finish()
        elseif type(C_Timer) == "table" and C_Timer.After then
            C_Timer.After(0, Step)
        else
            now = true
            Step()
        end
    end

    Step()
end

--- The rows as last built, or nil; and whether they are older than KEEP.
function CraftOrFarm:Rows()
    if not self.rows then return nil, true end
    local age = Clock() - (self.builtAt or 0)
    return self.rows, age > CraftOrFarm.KEEP or age < 0
end

--- Forget the list, so the next ask builds it again.
function CraftOrFarm:Forget()
    self.builtAt = nil
end

--- For Farmer's item tooltip: the craft that makes the most an hour from
--- farming `itemID`, when crafting beats selling it. Never raises, never
--- builds in a fight; a stale or missing list is built in the background.
function CraftOrFarm:ForMaterial(itemID)
    itemID = tonumber(itemID)
    if not itemID then return nil end
    local ok, answer = pcall(function()
        local rows, stale = self:Rows()
        local fighting = type(InCombatLockdown) == "function" and InCombatLockdown()
        if stale and not self.building and not fighting then self:Build() end
        local held = rows and self.byMaterial and self.byMaterial[itemID]
        if not held then return nil end
        return { name = held.name, recipeID = held.recipeID, perHour = held.perHour,
            rawPerHour = held.rawPerHour }
    end)
    return ok and answer or nil
end
