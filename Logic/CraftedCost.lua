-- Blackthornes Tradeskills -- Logic/CraftedCost.lua
-- What a craft cost when you made it, and what you last listed it at.
--
-- Asked by a player on 2026-10-05: everywhere else a craft's cost is worked
-- out again from today's prices, so something made last week and listed
-- today was judged against what its materials cost now, not what was paid.
-- This keeps the cost from the moment it was made, and the price it last
-- went up at, so the two can be read beside what it would list for now.
--
-- Kept per realm, like the mail ledger: a price means something on one
-- realm's auction house only, and a craft mailed to a bank alt on the same
-- realm keeps its cost. No character names are kept, only items, prices
-- and times.
--
-- The setting "Never below what I paid" (neverBelowCraftedCost, off by
-- default) makes Post refuse any price that, after the auction house's cut,
-- brings in less than the last craft cost. It sits beside the material cost
-- guard (allowPostingAtALoss), which compares against today's prices.

local _, ns = ...
local L = ns.L or setmetatable({ Format = string.format }, { __index = function(_, key) return key end })

local CraftedCost = ns.NewModule("CraftedCost")

local Util = ns.Util

--------------------------------------------------------------------------------
-- Saved data
--------------------------------------------------------------------------------

--- This realm's table under `key` in the saved data, made on first use.
local function RealmTable(key)
    if not ns.db then return nil end
    local realmKey = ns.Config:GetRealmKey()
    ns.db[key] = ns.db[key] or {}
    ns.db[key][realmKey] = ns.db[key][realmKey] or {}
    return ns.db[key][realmKey]
end

--- The last craft of an item: { cost = copper each, at = time made }, or nil.
function CraftedCost:Get(itemID)
    local made = itemID and RealmTable("craftedCosts")
    local record = made and made[itemID]
    if type(record) ~= "table" or type(record.cost) ~= "number" then return nil end
    return record
end

--- The last listing of an item: { price = copper each, at = time posted }, or nil.
function CraftedCost:GetLastPosted(itemID)
    local posted = itemID and RealmTable("lastPosted")
    local record = posted and posted[itemID]
    if type(record) ~= "table" or type(record.price) ~= "number" then return nil end
    return record
end

--------------------------------------------------------------------------------
-- Writing it down
--------------------------------------------------------------------------------

--- A recipe was just cast: remember what one of what it makes cost.
--
-- Materials are valued at what they are worth, whatever the cash-out-of-
-- pocket setting says: they have already left the bags when the cast is
-- seen, so the cash view would count them as still to be bought. A craft
-- with any unpriced material leaves the last cost as it was rather than
-- writing down a guess.
--
-- @return the cost written, or nil when nothing was
function CraftedCost:NoteCraft(recipeID)
    if not recipeID or not ns.Recipes then return nil end

    local recipe = ns.Recipes:GetAny(recipeID)
    local itemID = recipe and recipe.outputItemID
    if not itemID then return nil end

    -- Soulbound when made, so it is never sold and its cost decides nothing.
    if Util.IsBoundOnPickup and Util.IsBoundOnPickup(itemID) then return nil end

    local ok, cost = pcall(ns.Cost.GetCraftCost, ns.Cost, recipeID, nil, nil, { valueOwned = true })
    if not ok or type(cost) ~= "table" or not cost.priceable then return nil end

    local each = cost.perUnit
    if type(each) ~= "number" or each <= 0 then return nil end

    local made = RealmTable("craftedCosts")
    if not made then return nil end

    each = math.floor(each + 0.5)
    made[itemID] = { cost = each, at = time() }
    return each
end

--- A listing went up: remember the price of one.
function CraftedCost:NotePosted(itemID, unitPrice)
    if not itemID or type(unitPrice) ~= "number" or unitPrice <= 0 then return end

    local posted = RealmTable("lastPosted")
    if not posted then return end

    posted[itemID] = { price = math.floor(unitPrice + 0.5), at = time() }
end

--------------------------------------------------------------------------------
-- What a sale made
--------------------------------------------------------------------------------

-- Asked by two players on 2026-10-06: the Sales tab said what each sale took
-- in, but not whether it made anything over what the item cost. A sale is
-- costed, best first, from:
--
--   "made"  the cost written on the sale when it was recorded, or failing
--           that the last craft cost if that craft came before the sale;
--   "est"   what the materials cost today, for something sold before its
--           craft cost was being kept (or made on a character that never
--           cast it since);
--   nil     neither: bought rather than made, or nothing to price it with.
--
-- A sale mail does not say how many were in the stack, so a sale counts as
-- one unless the ledger recorded a quantity.

--- A lookup kept for one pass over the ledger: which recipe makes an item,
--- and today's estimate for it, worked out once however many sales it has.
function CraftedCost:NewSaleCache()
    return { estimates = {} }
end

--- The recipe that makes `itemID`, from every character's recipes.
local function RecipeFor(cache, itemID)
    if not cache.recipeByItem then
        cache.recipeByItem = {}
        cache.skillByItem = {}
        for _, record in pairs((ns.db and ns.db.characters) or {}) do
            for recipeID, recipe in pairs(type(record) == "table" and record.recipes or {}) do
                local output = type(recipe) == "table" and recipe.outputItemID
                if output and not cache.recipeByItem[output] then
                    cache.recipeByItem[output] = recipe.recipeID or recipeID
                end
                if output and not cache.skillByItem[output] and type(recipe.skillLineID) == "number" then
                    cache.skillByItem[output] = recipe.skillLineID
                end
            end
        end
    end
    return cache.recipeByItem[itemID]
end

--- The profession that makes `itemID`, by the English name the addon keeps
--- (Data/Recipes.lua's SKILL_LINE_PROFESSIONS), or nil when no recipe of
--- yours makes it or its skill line is not known. Worked out as it is read,
--- nothing saved. `cache` is a NewSaleCache, so one pass looks once.
function CraftedCost:ProfessionOf(itemID, cache)
    if not itemID then return nil end
    cache = cache or self:NewSaleCache()
    cache.professions = cache.professions or {}
    local known = cache.professions[itemID]
    if known ~= nil then return known or nil end

    local lines = ns.Recipes and ns.Recipes.SKILL_LINE_PROFESSIONS or {}
    local english
    local recipeID = RecipeFor(cache, itemID)
    if recipeID then
        english = lines[cache.skillByItem[itemID]]
        -- A recipe saved without its skill line: the account's recipe book
        -- may know it.
        if not english and ns.RecipeBook and ns.RecipeBook.Get then
            local ok, record = pcall(ns.RecipeBook.Get, ns.RecipeBook, recipeID)
            if ok and type(record) == "table" then english = lines[record.skillLineID] end
        end
    end

    cache.professions[itemID] = english or false
    return english
end

--- Today's material cost of one `itemID`, or false when it cannot be priced.
local function Estimate(cache, itemID)
    local known = cache.estimates[itemID]
    if known ~= nil then return known end

    local each = false
    local recipeID = RecipeFor(cache, itemID)

    if recipeID and ns.Cost then
        local ok, cost = pcall(ns.Cost.GetCraftCost, ns.Cost, recipeID, nil, nil, { valueOwned = true })
        if ok and type(cost) == "table" and cost.priceable
            and type(cost.perUnit) == "number" and cost.perUnit > 0 then
            each = math.floor(cost.perUnit + 0.5)
        end
    end

    cache.estimates[itemID] = each
    return each
end

--------------------------------------------------------------------------------
-- Bought or made
--------------------------------------------------------------------------------

-- A player's report (2026-11-26): Medium Leather bought on the auction house
-- at 1s 15c and sold at 1s 52c showed as a Leatherworking loss, costed at
-- the 4s 60c of a craft made days before. Something you can make may also
-- be bought, so whichever came last is what the stock in your bags cost:
-- a buy after the last craft makes it bought stock, costed at what you paid.

--- A sale written down before the craft's time was kept on it, from after
--- a later craft: the craft behind its cost came at some unknown time before
--- it. A buy this close before the sale is taken as the newer of the two.
CraftedCost.FLIP_WINDOW = 3 * 86400

--- What one cost on the auction house, when a buy of `itemID` at or before
--- `at` came after the craft at `madeAt` (nil: never made). nil otherwise.
function CraftedCost:BoughtCost(itemID, at, madeAt)
    local profit = ns.MethodProfit
    if not (itemID and profit and profit.BuyBefore) then return nil end
    local boughtAt, each = profit:BuyBefore(itemID, at or time())
    if not boughtAt then return nil end
    if madeAt == nil or boughtAt > madeAt then return each end
    return nil
end

--- The last craft of the stock you hold now: Get's record, or nil when the
--- item was bought on the auction house since (or never made).
function CraftedCost:ForStock(itemID)
    local record = self:Get(itemID)
    if not record then return nil end
    if self:BoughtCost(itemID, time(), tonumber(record.at) or 0) then return nil end
    return record
end

--- Write on a sale, as it is read from the mail, what one cost then: the
--- last craft, or what was paid on the auction house when that came later
--- (`bought` set). `madeAt` keeps the craft's time, so a later read agrees.
function CraftedCost:CostTheSale(entry)
    if type(entry) ~= "table" or not entry.itemID then return end
    local made = self:Get(entry.itemID)
    local paid = self:BoughtCost(entry.itemID, entry.t, made and (tonumber(made.at) or 0) or nil)
    if paid then
        entry.cost = paid
        entry.bought = true
    elseif made then
        entry.cost = made.cost
        entry.madeAt = tonumber(made.at)
    end
end

--- When the craft behind a sale's written cost was made, as best known.
local function MadeAtFor(self, entry, itemID)
    if tonumber(entry.madeAt) then return tonumber(entry.madeAt) end
    local record = self:Get(itemID)
    local at, t = record and tonumber(record.at), tonumber(entry.t)
    if not t then return at or 0 end
    if at and at <= t then return at end
    -- Crafted again since: the craft behind it is older than we can say.
    return t - self.FLIP_WINDOW
end

--- What one of a sold item cost, and where that figure came from.
-- @param itemID  the sale's item, resolved by the caller when the entry has none
-- @return each, source ("made" | "bought" | "est"), or nil when it cannot be costed
function CraftedCost:SaleCost(entry, itemID, cache)
    if type(entry) ~= "table" then return nil end

    itemID = itemID or entry.itemID

    if type(entry.cost) == "number" then
        if entry.bought then return entry.cost, "bought" end
        -- Written down as a craft. A sale from before buys were weighed
        -- against crafts may have been bought stock after all.
        local paid = itemID and self:BoughtCost(itemID, entry.t, MadeAtFor(self, entry, itemID))
        if paid then return paid, "bought" end
        return entry.cost, "made"
    end

    if not itemID then return nil end

    local record = self:Get(itemID)
    local usable = record and (not record.at or not entry.t or record.at <= entry.t)
    local paid = self:BoughtCost(itemID, entry.t, usable and (tonumber(record.at) or 0) or nil)
    if paid then return paid, "bought" end
    if usable then return record.cost, "made" end

    local each = Estimate(cache or self:NewSaleCache(), itemID)
    if each then return each, "est" end

    return nil
end

--- What a sale made over what the item cost.
--
-- What came in is the sale less the auction house's cut. The deposit handed
-- back with it is left out: it was paid when listing, so getting it back
-- earns nothing.
--
-- @return profit, cost, source -- all nil when the sale cannot be costed
function CraftedCost:SaleProfit(entry, itemID, cache)
    if type(entry) ~= "table" or entry.kind ~= "sold" then return nil end

    local each, source = self:SaleCost(entry, itemID, cache)
    if not each then return nil end

    local cost = each * math.max(1, tonumber(entry.quantity) or 1)
    local income = (entry.net or 0) - (entry.deposit or 0)

    return income - cost, cost, source
end

--------------------------------------------------------------------------------
-- Reading it
--------------------------------------------------------------------------------

--- What a listing at `price` puts in your pocket, after the auction house's
--- cut. The deposit is left out: it comes back when the item sells.
function CraftedCost:NetOf(price)
    local cut = ns.Config:Get("auctionCut") or 0.05
    return math.floor(price * (1 - cut))
end

--- What one sale at `price` makes over the last craft cost, after the cut.
-- @return profit (copper, negative for a loss), or nil when either is unknown
function CraftedCost:ProfitAt(itemID, price)
    local record = self:Get(itemID)
    if not record or type(price) ~= "number" then return nil end
    return self:NetOf(price) - record.cost
end

--- The last craft cost when the setting is on and `price` brings in less
--- than it after the cut; nil when the listing may go ahead, or when the
--- stock was bought on the auction house after it was last made.
-- @return cost, net
function CraftedCost:Refuses(itemID, price)
    if ns.Config:Get("neverBelowCraftedCost") ~= true then return nil end
    if type(price) ~= "number" then return nil end

    -- A craft guard: stock bought on the auction house since is no craft.
    local record = self:ForStock(itemID)
    if not record then return nil end

    local net = self:NetOf(price)
    if net < record.cost then return record.cost, net end
    return nil
end

--- The chat line for a refused listing.
function CraftedCost:RefusalText(itemID, price, cost, net)
    return L.Format("not listing %s at %s: you paid %s to make one, and after the auction house's cut it brings in %s",
        Util.GetItemLabel(itemID), Util.FormatMoney(price), Util.FormatMoney(cost), Util.FormatMoney(net))
end

--- What one costs to make today, at today's material prices and the
--- player's own "Charge for Own Materials" choice, as the craft queue
--- prices a craft: copper each, or nil when no character's recipe makes it,
--- it binds when made, or a material has no price.
function CraftedCost:CostNow(itemID)
    if not (itemID and ns.Cost and ns.Cost.GetCraftCost) then return nil end
    if Util.IsBoundOnPickup and Util.IsBoundOnPickup(itemID) then return nil end
    local find = ns.Cost.FindAnyRecipeForItem or ns.Cost.FindRecipeForItem
    local recipeID = find and find(ns.Cost, itemID)
    if not recipeID then return nil end
    local ok, cost = pcall(ns.Cost.GetCraftCost, ns.Cost, recipeID)
    if not ok or type(cost) ~= "table" or not cost.priceable then return nil end
    local each = cost.perUnit
    if type(each) ~= "number" or each <= 0 then return nil end
    return math.floor(each + 0.5)
end

--- What one sale at `price` makes over what one costs to make today, after
--- the cut. The owner (2026-11-25): Profit Now always shows the current
--- amount, so it agrees with the craft queue, not with the last craft.
-- @return profit (copper, negative for a loss), or nil when either is unknown
function CraftedCost:ProfitNowAt(itemID, price)
    if type(price) ~= "number" then return nil end
    local cost = self:CostNow(itemID)
    if not cost then return nil end
    return self:NetOf(price) - cost
end

--- Lines for a tooltip, each { label, value, color }: what it cost the last
--- time you made one, what it last went up at, what one costs to make today,
--- and what a listing now makes over that. The first two only for an item
--- crafted since this was kept; the profit for anything a recipe makes.
--
-- @param price  what it would list at now; looked up when not given
function CraftedCost:Lines(itemID, price)
    local lines = {}

    local record = self:Get(itemID)

    local function Ago(at)
        if type(at) ~= "number" then return "" end
        return "  (" .. Util.FormatAgeAgo(math.max(0, time() - at)) .. ")"
    end

    if record then
        lines[#lines + 1] = { L["Made for"], Util.FormatMoney(record.cost, { short = true }) .. Ago(record.at) }

        local posted = self:GetLastPosted(itemID)
        if posted then
            lines[#lines + 1] = { L["Last posted"], Util.FormatMoney(posted.price, { short = true }) .. Ago(posted.at) }
        end
    end

    -- Nothing to make it from today: no profit line, and no price looked up.
    local costNow = self:CostNow(itemID)
    if not costNow then return lines end

    -- An estimate from the materials is not a price anyone pays, so no
    -- profit is worked out on it.
    -- The market's price, not Post at Minimum Profit's, so this says what
    -- others pay now.
    -- When every listing is yours ("uncontested") the price is that same
    -- materials-plus-markup estimate, so the market value stands instead,
    -- as on Level Up (a player's report, 2026-11-22: 8g shown, 5g paid).
    if not price and ns.Profit and ns.Profit.ChoosePostPrice then
        local ok, chosen, basis = pcall(ns.Profit.ChoosePostPrice, ns.Profit, itemID)
        if ok and basis == "uncontested" then
            local okMarket, market = false, nil
            if ns.Prices and ns.Prices.GetValue then
                okMarket, market = pcall(ns.Prices.GetValue, ns.Prices, itemID, "market")
            end
            price = okMarket and type(market) == "number" and market > 0 and math.floor(market) or nil
        elseif ok and basis ~= "derived" then
            price = chosen
        end
    end

    local profit = price and self:ProfitNowAt(itemID, price)
    if profit then
        -- Today's cost on its own line, the one Profit Now takes off, so
        -- the sum can be checked by eye (a player's report, 2026-11-26:
        -- Made For under the price, yet Profit Now a loss).
        lines[#lines + 1] = { L["Costs now"], Util.FormatMoney(costNow, { short = true }) }
        local sign = profit > 0 and "+" or (profit < 0 and "-" or "")
        lines[#lines + 1] = {
            L["Profit now"],
            L.Format("%s%s at %s", sign,
                Util.FormatMoney(math.abs(profit), { short = true, noColor = true }),
                Util.FormatMoney(price, { short = true, noColor = true })),
            color = profit < 0 and "loss" or "profit",
        }
    end

    return lines
end
