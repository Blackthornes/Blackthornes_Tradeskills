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
-- @return copper, source  -- source is "vendor", "buy", "mine" (the player's
--   own price, from the Prices tab) or nil when unknown
function Cost:GetReagentUnitCost(itemID)
    -- A price the player set wins (Ponyboy, 2026-10-06). "use" is the cost,
    -- whoever sells it; "floor" is the least it costs, vendor or auction.
    local mine, mode
    if ns.Prices.GetMine then mine, mode = ns.Prices:GetMine(itemID) end
    if mine and mode == "use" then return mine, "mine" end

    -- Buying means paying the asking price, not the smoothed market average.
    -- A lone listing far below the rest is left out, as the undercut rule
    -- leaves it out (2026-09-26): one seller's single cheap unit is
    -- gone after one purchase and cannot supply a run of crafts, so pricing
    -- every craft off it overstated profit and the only-seller price.
    local auction = ns.Prices:GetValue(itemID, "lowest")
    local vendor = ns.Vendor:GetUnitPrice(itemID)

    -- Anything a vendor sells costs the vendor price (2026-10-02).
    -- People list vendor-sold thread and vials on the auction house for many
    -- times the shop price, and paying that is a choice, not a cost. The one
    -- exception is a shop seen with limited stock: it cannot supply a run of
    -- crafts, so a cheaper auction price still wins there.
    local limited = ns.Vendor.IsLimited and ns.Vendor:IsLimited(itemID)
    if vendor and not (limited and auction and auction < vendor) then
        if mine and vendor < mine then return mine, "mine" end
        return vendor, "vendor"
    end

    -- GetValue has already lifted the auction price to a floor.
    if mine and auction == mine then return auction, "mine" end

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
        -- A dropped profession's crafts are not offered as sub-crafts, nor
        -- is one the player said never to make as a sub-craft.
        local dropped = ns.Recipes.IsDropped and ns.Recipes:IsDropped(recipe)
        if recipe.outputItemID and not dropped and not self:IsNeverSubCraft(recipeID) then
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

--------------------------------------------------------------------------------
-- Never made as a sub-craft
--------------------------------------------------------------------------------

-- Voldar on Discord (2026-10-07): scraps to light leather to medium to heavy
-- costs more crafting time than it saves, and "Queue sub-crafts" is all or
-- nothing. A craft marked here is never made to go into another one: its
-- item is bought instead, in every cost, the queue and the shopping list.
-- It can still be queued and sold as itself. Separate from the Profit tab's
-- Ignore, which is about what to sell, not how to make it.
--
-- Saved account wide in `neverSubCrafts`, recipeID -> the craft's name, so
-- Settings can list one the character playing does not know.

function Cost:IsNeverSubCraft(recipeID)
    local marked = recipeID ~= nil and ns.db ~= nil and ns.db.neverSubCrafts
    return marked and marked[recipeID] ~= nil or false
end

--- Never make this craft as a sub-craft (never = true), or allow it again.
-- Everything worked out from sub-crafts is worked out again at once: the
-- queue's sub-crafts, its costs and every tab showing them.
function Cost:SetNeverSubCraft(recipeID, never, name)
    if not ns.db or not recipeID then return end
    ns.db.neverSubCrafts = ns.db.neverSubCrafts or {}

    if never then
        local known = ns.Recipes and ns.Recipes.GetAny and ns.Recipes:GetAny(recipeID)
        ns.db.neverSubCrafts[recipeID] = name or (known and known.name)
            or ("recipe " .. tostring(recipeID))
    else
        ns.db.neverSubCrafts[recipeID] = nil
    end

    self:InvalidateIndex()

    if ns.Queue and ns.Queue.RebuildDependencies then
        ns.Queue:RebuildDependencies()
        ns.Queue:Notify()
    end
    if ns.UI and ns.UI.RefreshActiveTab then ns.UI:RefreshActiveTab() end
end

--- The crafts never made as sub-crafts, A to Z:
--- { { recipeID, name, outputItemID }, ... }. outputItemID is nil for a
--- craft no character on record knows any more.
function Cost:GetNeverSubCrafts()
    local list = {}
    for recipeID, name in pairs(ns.db and ns.db.neverSubCrafts or {}) do
        local known = ns.Recipes and ns.Recipes.GetAny and ns.Recipes:GetAny(recipeID)
        list[#list + 1] = {
            recipeID = recipeID,
            name = type(name) == "string" and name or ("recipe " .. tostring(recipeID)),
            outputItemID = known and known.outputItemID or nil,
        }
    end
    table.sort(list, function(a, b)
        local left, right = a.name:lower(), b.name:lower()
        if left ~= right then return left < right end
        return a.recipeID < b.recipeID
    end)
    return list
end

--- The craft a material would be made with, had it not been marked never
--- to make as a sub-craft. For saying "bought, never made" beside it.
function Cost:NeverMadeRecipeFor(itemID)
    if not itemID or not (ns.db and ns.db.neverSubCrafts and next(ns.db.neverSubCrafts)) then
        return nil
    end
    for recipeID in pairs(ns.db.neverSubCrafts) do
        local recipe = ns.Recipes:GetAny(recipeID)
        if recipe and recipe.outputItemID == itemID then return recipeID end
    end
    return nil
end

--- Total reagent cost for one craft of a recipe.
--
-- @param opts.valueOwned  force the market-price view even when the player
--   has chosen cash-out-of-pocket. Pricing something off its materials needs
--   what they are worth, not what is left to pay for them. Carried down
--   through sub-crafts so the whole tree is valued the same way.
--
-- @param opts.made  { [itemID] = true } for the materials the queue is making.
--   Given, a material is priced as made when it is in the set and as bought
--   when it is not, whatever is cheaper today, so a queued craft costs
--   what the queue will actually do. Carried down through sub-crafts.
--
-- @param opts.recipe  cost this recipe record instead of looking the ID up
--   among the recipes characters know: a recipe nobody has learned yet
--   (Logic/RecipeBook.lua). Not carried down to sub-crafts, which are
--   always ones this character can make.
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
    local recipe
    if opts and opts.recipe then
        recipe = opts.recipe
        opts = { valueOwned = opts.valueOwned, made = opts.made }
    else
        recipe = ns.Recipes:GetAny(recipeID)
    end
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

            local made = opts and opts.made
            if made and not made[itemID] then subRecipeID = nil end

            -- Not over a price the player chose to use for it.
            if subRecipeID and not visited[subRecipeID] and source ~= "mine" then
                local subResult = self:GetCraftCost(subRecipeID, depth + 1, visited, opts)

                if subResult and subResult.priceable and subResult.perUnit then
                    if not unitCost or made or subResult.perUnit < unitCost then
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
            -- Priced as GetReagentUnitCost prices it: the vendor price for
            -- what a vendor sells, else the auction price, lone low listing
            -- aside.
            local unitCost = self:GetReagentUnitCost(reagent.itemID)

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
