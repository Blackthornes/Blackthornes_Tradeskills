-- Blackthornes Tradeskills -- Logic/Cost.lua
-- What it costs to make one of something.
--
-- Two rules drive everything here:
--   * A missing price is never treated as a free reagent. A recipe with an
--     unpriced reagent is reported as unpriceable, not as wildly profitable.
--   * Reagents you already own still cost what they are worth, unless you
--     explicitly switch to the cash-out-of-pocket view. Ignoring opportunity
--     cost is the single easiest way to talk yourself into a bad craft.

local _, ns = ...

local Cost = ns.NewModule("Cost")

-- How deep to chase "should I craft this reagent instead of buying it".
local MAX_SUBCRAFT_DEPTH = 3

--------------------------------------------------------------------------------
-- Reagent pricing
--------------------------------------------------------------------------------

--- What one unit of a reagent costs to buy, whatever is already owned.
--
-- The cash-out-of-pocket view is applied in GetCraftCost, where the quantity
-- is known. Applied here, one unit in the bags made the whole line free: one
-- bolt held, and all three a bag needs cost nothing. A bolt could then never
-- be cheaper to make than to buy, so once the first queued bolt was made,
-- the rest of them dropped off the queue.
--
-- @return copper, source  -- source is "vendor", "buy" or nil when unknown
function Cost:GetReagentUnitCost(itemID)
    -- Buying means paying the asking price, not the smoothed market average.
    -- A lone listing far below the rest is left out, as the undercut rule
    -- leaves it out (Trent, 2026-09-26): one seller's single cheap unit is
    -- gone after one purchase and cannot supply a run of crafts, so pricing
    -- every craft off it overstated profit and the only-seller price.
    local auction = ns.Prices:GetValue(itemID, "lowest")
    local vendor = ns.Vendor:GetUnitPrice(itemID)

    -- A vendor caps what any reagent can cost you. People routinely list
    -- vendor-sold thread and vials on the auction house for many times the
    -- shop price, and paying that is a choice, not a cost.
    if vendor and (not auction or vendor <= auction) then
        return vendor, "vendor"
    end

    if auction then
        return auction, "buy"
    end

    return nil, nil
end

--------------------------------------------------------------------------------
-- Craft cost
--------------------------------------------------------------------------------

--- Which cached recipe, if any, produces this item.
function Cost:FindRecipeForItem(itemID)
    if self.recipeByOutput == nil or self.recipeIndexStale then
        self:RebuildOutputIndex()
    end
    return self.recipeByOutput[itemID]
end

--- Which recipe, known by any character on the account, produces this item.
--- The logged-in character's own comes first.
--
-- For pricing, where what an item sells for does not depend on who is logged
-- in. FindRecipeForItem stays with this character's crafts, because it is
-- what offers sub-crafts, and only those can be made here. Priced through it,
-- a bank alt posting what the crafter mailed it never undercut ("the cost to
-- make this is unknown") and got no markup over materials.
function Cost:FindAnyRecipeForItem(itemID)
    local own = self:FindRecipeForItem(itemID)
    if own then return own end
    return self.anyRecipeByOutput and self.anyRecipeByOutput[itemID]
end

function Cost:RebuildOutputIndex()
    local index = {}

    for recipeID, recipe in pairs(ns.Recipes:GetAll()) do
        -- A dropped profession's crafts are not offered as sub-crafts.
        local dropped = ns.Recipes.IsDropped and ns.Recipes:IsDropped(recipe)
        if recipe.outputItemID and not dropped then
            index[recipe.outputItemID] = recipeID
        end
    end

    -- Every character's crafts, for FindAnyRecipeForItem, leaving out each
    -- one's dropped professions as above.
    local anywhere = {}

    if ns.Recipes.GetAccountWide then
        for recipeID, recipe in pairs(ns.Recipes:GetAccountWide(true)) do
            if recipe.outputItemID then
                anywhere[recipe.outputItemID] = recipeID
            end
        end
    end

    self.recipeByOutput = index
    self.anyRecipeByOutput = anywhere
    self.recipeIndexStale = false
end

function Cost:InvalidateIndex()
    self.recipeIndexStale = true
end

--- Total reagent cost for one craft of a recipe.
--
-- @param opts.valueOwned  force the market-price view even when the player
--   has chosen cash-out-of-pocket. Pricing something off its materials needs
--   what they are worth, not what is left to pay for them. Carried down
--   through sub-crafts so the whole tree is valued the same way.
--
-- @return result table:
--   total        copper cost of a single craft, or nil when unpriceable
--   perUnit      cost per output item
--   reagents     array of { itemID, quantity, unitCost, lineCost, source,
--                           have, shortfall, crafted }
--   unpriced     array of itemIDs with no price data
--   priceable    false when any reagent has no price
function Cost:GetCraftCost(recipeID, depth, visited, opts)
    depth = depth or 0
    visited = visited or {}

    -- GetAny, so a craft that lives on an alt can still be costed. Material
    -- cost is realm-wide regardless of who does the crafting.
    local recipe = ns.Recipes:GetAny(recipeID)
    if not recipe then return nil end

    -- A recipe whose reagent is made by a recipe that needs the first item
    -- would otherwise recurse forever.
    if visited[recipeID] then return nil end
    visited[recipeID] = true

    local result = {
        recipeID = recipeID,
        reagents = {},
        unpriced = {},
        priceable = true,
        total = 0,
    }

    local valueOwned = (opts and opts.valueOwned) or ns.Config:Get("valueOwnedMaterials")

    for _, reagent in ipairs(recipe.reagents or {}) do
        local itemID, quantity = reagent.itemID, reagent.quantity

        local unitCost, source = self:GetReagentUnitCost(itemID)
        local crafted = false

        -- If we know how to make this reagent and making it is cheaper than
        -- buying it, price it at the cheaper option and flag it as a sub-craft
        -- so the queue can sequence it first.
        if depth < MAX_SUBCRAFT_DEPTH then
            local subRecipeID = self:FindRecipeForItem(itemID)

            if subRecipeID and not visited[subRecipeID] then
                local subResult = self:GetCraftCost(subRecipeID, depth + 1, visited, opts)

                if subResult and subResult.priceable and subResult.perUnit then
                    if not unitCost or subResult.perUnit < unitCost then
                        unitCost = subResult.perUnit
                        source = "craft"
                        crafted = true
                    end
                end
            end
        end

        -- Owned, not just carried: the breakdown answers "do I have this",
        -- and bank stock counts. Whether you can craft right now is a separate
        -- question, answered by Profit:GetCraftableCount using bags alone.
        local inBags = ns.Inventory:GetBagCount(itemID)
        local have = inBags + ns.Inventory:GetBankCount(itemID)

        -- Cash-out-of-pocket view: what is in the bags is already paid for,
        -- but only that many. The rest of the line is still bought or made.
        local free = (not valueOwned) and math.min(quantity, inBags) or 0
        local lineCost = unitCost and (unitCost * (quantity - free)) or nil
        if free > 0 and free >= quantity then
            unitCost, source, lineCost = 0, "owned", 0
        end

        local entry = {
            itemID = itemID,
            quantity = quantity,
            unitCost = unitCost,
            lineCost = lineCost,
            source = source,
            crafted = crafted,
            have = have,
            inBags = inBags,
            shortfall = math.max(0, quantity - have),
        }

        result.reagents[#result.reagents + 1] = entry

        if unitCost then
            result.total = result.total + entry.lineCost
        else
            result.priceable = false
            result.unpriced[#result.unpriced + 1] = itemID
        end
    end

    visited[recipeID] = nil

    if not result.priceable then
        result.total = nil
        result.perUnit = nil
        return result
    end

    -- Recipes with a variable yield are valued at the average, which is the
    -- honest expectation over many crafts even though any single craft differs.
    local averageYield = ((recipe.quantityMin or 1) + (recipe.quantityMax or 1)) / 2
    if averageYield <= 0 then averageYield = 1 end

    result.yield = averageYield
    result.perUnit = result.total / averageYield

    return result
end

--- What the materials for one unit of a recipe's output are worth.
--
-- Deliberately not the same question as "what will this craft cost me now":
-- reagents already in the bags count at market price here however the
-- cash-out-of-pocket setting is set, because a craft does not become worth
-- less to sell because the materials are already paid for.
--
-- @return perUnit copper, or nil when any reagent has no price at all
function Cost:GetMaterialValue(recipeID)
    local cost = self:GetCraftCost(recipeID, nil, nil, { valueOwned = true })

    if not cost or not cost.priceable then return nil end

    return cost.perUnit, cost
end

--------------------------------------------------------------------------------
-- Shortfalls
--------------------------------------------------------------------------------

--- Reagents missing for N crafts, aggregated and priced.
function Cost:GetShortfall(recipeID, craftCount)
    craftCount = craftCount or 1

    local recipe = ns.Recipes:GetAny(recipeID)
    if not recipe then return nil end

    local missing = {}

    for _, reagent in ipairs(recipe.reagents or {}) do
        local needed = reagent.quantity * craftCount
        local have = ns.Inventory:GetOwnedCount(reagent.itemID)
        local short = math.max(0, needed - have)

        if short > 0 then
            -- Priced as GetReagentUnitCost prices it, lone low listing aside.
            local unitCost = ns.Prices:GetValue(reagent.itemID, "lowest")

            missing[#missing + 1] = {
                itemID = reagent.itemID,
                needed = needed,
                have = have,
                shortfall = short,
                unitCost = unitCost,
                estimatedCost = unitCost and (unitCost * short) or nil,
                onAlts = ns.Inventory:GetAltTotal(reagent.itemID),
            }
        end
    end

    return missing
end

function Cost:OnEnable()
    self:InvalidateIndex()
end
