-- Blackthornes Tradeskills -- Logic/Queue.lua
-- The craft queue and the shopping list derived from it.

local _, ns = ...

local Queue = ns.NewModule("Queue")

--------------------------------------------------------------------------------
-- Entries
--------------------------------------------------------------------------------

function Queue:GetAll()
    return (ns.db and ns.db.queue) or {}
end

function Queue:Count()
    return #self:GetAll()
end

--- @param manualOnly skip derived sub-craft entries
function Queue:Find(recipeID, manualOnly)
    local fallbackIndex, fallback

    for index, entry in ipairs(self:GetAll()) do
        if entry.recipeID == recipeID then
            -- A recipe can be both asked for and required by something
            -- else. The manual entry is the one the player controls.
            if not entry.isDependency then
                return index, entry
            end

            fallbackIndex, fallback = fallbackIndex or index, fallback or entry
        end
    end

    if manualOnly then return nil end
    return fallbackIndex, fallback
end

-- How far to chase "this reagent is cheaper to make than to buy". Matches the
-- depth the cost engine itself recurses to.
local MAX_DEPENDENCY_DEPTH = 3

--- Rebuild every sub-craft in the queue from the crafts you actually asked for.
--
-- Dependencies are derived, never stored independently. Storing them would mean
-- keeping them in step with the parents by hand: remove a parent and its
-- sub-craft is orphaned, halve a parent and the sub-craft is now wrong. Deriving
-- them makes both impossible, and handles two parents needing the same reagent
-- without double-counting.
--
-- Deeper dependencies are placed first, so the queue reads in the order you can
-- actually work through it.
function Queue:RebuildDependencies()
    local queue = self:GetAll()

    -- Everything the player asked for directly. Dependencies are discarded and
    -- recalculated from these.
    local manual = {}
    for _, entry in ipairs(queue) do
        if not entry.isDependency then
            manual[#manual + 1] = entry
        end
    end

    local derived = {}

    if ns.Config:Get("autoQueueSubCrafts") ~= false then
        local function process(entries, depth)
            if depth >= MAX_DEPENDENCY_DEPTH or #entries == 0 then return end

            -- Sum requirements across everything at this level first, so a
            -- reagent needed by two crafts is counted once, not twice.
            local needs = {}

            for _, entry in ipairs(entries) do
                local cost = ns.Cost:GetCraftCost(entry.recipeID)

                for _, reagent in ipairs((cost and cost.reagents) or {}) do
                    -- `crafted` means the cost engine found making it cheaper.
                    if reagent.crafted then
                        local need = needs[reagent.itemID]
                            or { units = 0, parents = {} }

                        need.units = need.units + (reagent.quantity * entry.quantity)
                        need.parents[entry.recipeID] = true

                        needs[reagent.itemID] = need
                    end
                end
            end

            local nextLevel = {}

            for itemID, need in pairs(needs) do
                local subRecipeID = ns.Cost:FindRecipeForItem(itemID)
                local subRecipe = subRecipeID and ns.Recipes:GetAny(subRecipeID)

                if subRecipe then
                    local short = math.max(0, need.units - ns.Inventory:GetOwnedCount(itemID))

                    if short > 0 then
                        -- Missing units become crafts, since one craft can
                        -- produce several.
                        local perCraft = math.max(1, subRecipe.quantityMin or 1)

                        local entry = {
                            recipeID = subRecipeID,
                            quantity = math.ceil(short / perCraft),
                            isDependency = true,
                            forRecipes = need.parents,
                            depth = depth,
                            addedAt = time(),
                        }

                        derived[#derived + 1] = entry
                        nextLevel[#nextLevel + 1] = entry
                    end
                end
            end

            process(nextLevel, depth + 1)
        end

        process(manual, 0)
    end

    -- Deepest first: a sub-craft's own sub-crafts have to come before it.
    table.sort(derived, function(a, b) return a.depth > b.depth end)

    for index = #queue, 1, -1 do
        queue[index] = nil
    end

    for _, entry in ipairs(derived) do
        queue[#queue + 1] = entry
    end

    for _, entry in ipairs(manual) do
        queue[#queue + 1] = entry
    end
end

--- The crafts this dependency exists to serve, for display.
function Queue:GetDependencyParents(entry)
    local names = {}

    for parentID in pairs(entry.forRecipes or {}) do
        local parent = ns.Recipes:GetAny(parentID)
        names[#names + 1] = (parent and parent.name) or "another craft"
    end

    table.sort(names)
    return names
end

--- Add crafts to the queue, merging into an existing entry for the same recipe.
--
-- The cost and profit at the moment of queueing are recorded so the queue can
-- later say "this was worth 4g when you queued it, it is worth 40s now" rather
-- than quietly re-pricing and pretending nothing changed.
--
-- @param options { depth, forRecipeID } -- internal, for dependency queueing
function Queue:Add(recipeID, quantity, options)
    quantity = math.max(1, math.floor(tonumber(quantity) or 1))
    options = options or {}

    -- GetAny: an alt's craft can be queued from the account-wide view, and
    -- the Craft button reports whose character it needs.
    local recipe = ns.Recipes:GetAny(recipeID)
    if not recipe then return false end

    local analysis = ns.Profit:Analyse(recipeID)

    local _, existing = self:Find(recipeID, true)
    if existing then
        existing.quantity = existing.quantity + quantity
    else
        local queue = self:GetAll()
        queue[#queue + 1] = {
            recipeID = recipeID,
            quantity = quantity,
            addedAt = time(),
            snapshotCost = analysis and analysis.totalCost or nil,
            snapshotProfit = analysis and analysis.profit or nil,
        }
    end

    self:RebuildDependencies()
    self:Notify()
    return true
end

function Queue:SetQuantity(recipeID, quantity)
    quantity = math.floor(tonumber(quantity) or 0)

    local index, entry = self:Find(recipeID)
    if not entry then return false end

    if quantity <= 0 then
        table.remove(self:GetAll(), index)
    else
        entry.quantity = quantity
    end

    -- Sub-crafts are sized from the parents, so any change re-derives them.
    self:RebuildDependencies()
    self:Notify()
    return true
end

function Queue:Remove(recipeID)
    local index = self:Find(recipeID)
    if not index then return false end

    table.remove(self:GetAll(), index)

    -- Removing a parent removes whatever only existed to serve it.
    self:RebuildDependencies()
    self:Notify()
    return true
end

function Queue:Clear()
    local queue = self:GetAll()
    for i = #queue, 1, -1 do
        queue[i] = nil
    end
    self:Notify()
end

function Queue:Notify()
    if ns.UI and ns.UI.OnQueueUpdated then
        ns.UI:OnQueueUpdated()
    end

    -- Get the change into macro storage, which is the only copy of the queue
    -- that survives closing the client. Saving used to wait for the CVar
    -- cadence or for PLAYER_LOGOUT, so emptying the queue and quitting inside
    -- the minute never reached it, and the next login handed the crafts back.
    -- Coalesced and skipped when nothing really changed; see Durable:SaveSoon.
    if ns.Durable and ns.Durable.SaveSoon then
        ns.Durable:SaveSoon()
    end
end

--------------------------------------------------------------------------------
-- Derived views
--------------------------------------------------------------------------------

--- Totals across the whole queue.
function Queue:GetTotals()
    local totals = { crafts = 0, cost = 0, profit = 0, priceable = true }

    for _, entry in ipairs(self:GetAll()) do
        local analysis = ns.Profit:Analyse(entry.recipeID)

        totals.crafts = totals.crafts + entry.quantity

        if analysis and analysis.priceable then
            totals.cost = totals.cost + (analysis.totalCost * entry.quantity)
            totals.profit = totals.profit + (analysis.profit * entry.quantity)
        else
            totals.priceable = false
        end
    end

    return totals
end

--- Everything the queue needs, minus what is in the bags, aggregated.
--
-- Reagents are summed across the whole queue before subtracting inventory, so
-- two recipes sharing a reagent do not each claim the same stack.
function Queue:GetShoppingList()
    local required = {}

    for _, entry in ipairs(self:GetAll()) do
        local recipe = ns.Recipes:Get(entry.recipeID)

        if recipe then
            for _, reagent in ipairs(recipe.reagents or {}) do
                required[reagent.itemID] = (required[reagent.itemID] or 0)
                    + (reagent.quantity * entry.quantity)
            end
        end
    end

    local list = {}

    for itemID, needed in pairs(required) do
        -- A shopping list asks "must I buy this", so it counts the bank: you
        -- already own it, it just needs collecting.
        local inBags = ns.Inventory:GetBagCount(itemID)
        local inBank = ns.Inventory:GetBankCount(itemID)
        local have = inBags + inBank

        local shortfall = math.max(0, needed - have)

        local auction = ns.Prices:GetValue(itemID, "min")
        local vendor = ns.Vendor:GetUnitPrice(itemID)

        -- Cheaper from a vendor means the shopping list should send you to
        -- one, not to the auction house.
        local fromVendor = vendor ~= nil and (not auction or vendor <= auction)
        local unitCost = fromVendor and vendor or auction

        -- Where to go, and what the choice is worth. Only a genuine choice
        -- when both sources actually have the item.
        local source = "unknown"
        if fromVendor then
            source = "vendor"
        elseif auction then
            source = "auction"
        end

        local savingPerUnit
        if vendor and auction then
            savingPerUnit = math.abs(auction - vendor)
        end

        list[#list + 1] = {
            itemID = itemID,
            needed = needed,
            have = have,
            inBags = inBags,
            inBank = inBank,
            -- True when you own enough only by counting the bank, so the row
            -- can say "go to the bank" rather than implying you can craft now.
            needsBankTrip = inBags < needed and have >= needed,
            shortfall = shortfall,
            unitCost = unitCost,
            estimatedCost = unitCost and (unitCost * shortfall) or nil,
            fromVendor = fromVendor,
            vendorLimited = fromVendor and ns.Vendor:IsLimited(itemID) or false,
            source = source,
            vendorUnit = vendor,
            auctionUnit = auction,
            -- Both prices known: how much choosing the cheaper one saves.
            savingPerUnit = savingPerUnit,
            savingTotal = savingPerUnit and (savingPerUnit * shortfall) or nil,
            onAlts = ns.Inventory:GetAltTotal(itemID),
        }
    end

    table.sort(list, function(a, b)
        if (a.shortfall > 0) ~= (b.shortfall > 0) then
            return a.shortfall > 0
        end
        return (a.estimatedCost or 0) > (b.estimatedCost or 0)
    end)

    return list
end

function Queue:GetShoppingTotal()
    local total, unknown = 0, 0

    for _, line in ipairs(self:GetShoppingList()) do
        if line.shortfall > 0 then
            if line.estimatedCost then
                total = total + line.estimatedCost
            else
                unknown = unknown + 1
            end
        end
    end

    return total, unknown
end

--- Shopping totals split by where you have to go to get them.
-- @return summary table keyed by source, plus grand totals
function Queue:GetGatherSummary()
    local summary = {
        vendor = { count = 0, cost = 0 },
        auction = { count = 0, cost = 0 },
        unknown = { count = 0, cost = 0 },
        total = 0,
        outstanding = 0,
        satisfied = 0,
        saving = 0,
    }

    for _, line in ipairs(self:GetShoppingList()) do
        if line.shortfall > 0 then
            summary.outstanding = summary.outstanding + 1

            local bucket = summary[line.source] or summary.unknown
            bucket.count = bucket.count + 1
            bucket.cost = bucket.cost + (line.estimatedCost or 0)

            summary.total = summary.total + (line.estimatedCost or 0)
            summary.saving = summary.saving + (line.savingTotal or 0)
        else
            summary.satisfied = summary.satisfied + 1
        end
    end

    return summary
end
