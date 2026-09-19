-- Blackthornes Tradeskills -- Logic/Profit.lua
-- Is it worth making?
--
-- The headline number is profit per craft after the auction house takes its
-- cut. It is deliberately reported alongside confidence and liquidity, because
-- a 900% margin on an item that sells twice a month is not an opportunity, and
-- a table that ranks purely on margin will put exactly those items on top.

local _, ns = ...

local Profit = ns.NewModule("Profit")

local Util = ns.Util

--------------------------------------------------------------------------------
-- Single recipe
--------------------------------------------------------------------------------

--- How many crafts the current bags support.
--
-- Bags only, deliberately. The crafting UI cannot pull from the bank, so
-- counting bank stock here would claim you can craft things you cannot.
function Profit:GetCraftableCount(recipeID, characterKey)
    local recipe, owner = ns.Recipes:GetAny(recipeID)
    if not recipe or not recipe.reagents or #recipe.reagents == 0 then return 0 end

    characterKey = characterKey or owner

    local possible = math.huge

    for _, reagent in ipairs(recipe.reagents) do
        -- Counted against whoever would do the crafting, not against you.
        local have = ns.Inventory:GetCharacterBagCount(characterKey, reagent.itemID)
        local canMake = math.floor(have / reagent.quantity)

        if canMake < possible then possible = canMake end
        if possible == 0 then break end
    end

    return possible == math.huge and 0 or possible
end

--- Full profitability breakdown for one recipe.
function Profit:Analyse(recipeID, characterKey)
    local recipe, owner = ns.Recipes:GetAny(recipeID)
    if not recipe then return nil end

    local crafter = characterKey or owner

    local analysis = {
        recipeID = recipeID,
        name = recipe.name,
        outputItemID = recipe.outputItemID,
        skillLineID = recipe.skillLineID,
        owner = crafter,
        ownerName = ns.Recipes:GetCharacterName(crafter),
        isMine = crafter == ns.Config:GetCharacterKey(),
    }

    local cost = ns.Cost:GetCraftCost(recipeID)
    analysis.cost = cost

    if not recipe.outputItemID then
        -- Enchants and similar have no sellable output item.
        analysis.reason = "no sellable output"
        return analysis
    end

    -- Revenue is what you will actually be paid, which means undercutting the
    -- cheapest listing rather than assuming you get the market average. If
    -- nothing is listed there is no competition to undercut, so the smoothed
    -- market value is the only estimate available.
    -- "rival" excludes your own auctions. If the only listing is yours there is
    -- nobody to undercut, so we hold at market rather than walking our own
    -- price down a copper at a time.
    local competitor = ns.Prices:GetValue(recipe.outputItemID, "rival")
    local undercut = ns.Config:Get("undercutCopper") or 1

    -- Shown for context so the full picture is visible: the overall cheapest
    -- listing and your own, alongside the rival price actually being undercut.
    local priceRecord = ns.Prices:Get(recipe.outputItemID)
    analysis.overallMin = priceRecord and priceRecord.min or nil
    analysis.ownListing = priceRecord and priceRecord.ownMin or nil

    local unitRevenue
    if competitor then
        -- Never post below one copper, and never undercut past free.
        unitRevenue = math.max(1, competitor - undercut)
        analysis.competitorPrice = competitor
        analysis.undercut = true
    else
        unitRevenue = ns.Prices:GetValue(recipe.outputItemID, "market")
        analysis.undercut = false
        analysis.youHoldLowest = ns.Prices:HoldsLowest(recipe.outputItemID)
    end

    if not unitRevenue then
        analysis.reason = "output has no price data"
        return analysis
    end

    if not cost or not cost.priceable then
        analysis.reason = "a reagent has no price data"
        analysis.unpriced = cost and cost.unpriced or nil
        return analysis
    end

    local yield = cost.yield or 1

    analysis.yield = yield
    analysis.unitRevenue = unitRevenue
    analysis.revenue = unitRevenue * yield

    local auctionCut = ns.Config:Get("auctionCut") or 0.05
    analysis.cut = analysis.revenue * auctionCut
    analysis.netRevenue = analysis.revenue - analysis.cut

    analysis.totalCost = cost.total
    analysis.costPerUnit = cost.perUnit

    -- The deposit is paid up front and lost on every listing that does not
    -- sell, so it is a real cost of selling. Ignoring it overstates profit on
    -- every single craft.
    local unitDeposit = ns.Posting:GetCachedUnitDeposit(recipe.outputItemID)
    local relists = ns.Config:Get("expectedRelists") or 1

    analysis.depositKnown = unitDeposit ~= nil
    analysis.deposit = unitDeposit and (unitDeposit * yield * math.max(1, relists)) or 0

    analysis.profit = analysis.netRevenue - cost.total - analysis.deposit
    analysis.profitPerUnit = analysis.profit / yield

    -- Margin is profit against revenue; ROI is profit against the gold you must
    -- actually front. They rank very differently and both are worth seeing.
    analysis.margin = analysis.revenue > 0 and (analysis.profit / analysis.revenue) or 0
    analysis.roi = cost.total > 0 and (analysis.profit / cost.total) or 0

    analysis.confidence, analysis.confidenceReason = ns.Prices:GetConfidence(recipe.outputItemID)
    analysis.liquidity = ns.Prices:GetLiquidity(recipe.outputItemID)
    analysis.stale = ns.Prices:IsStale(recipe.outputItemID)
    analysis.age = ns.Prices:GetAge(recipe.outputItemID)

    analysis.craftableNow = self:GetCraftableCount(recipeID, crafter)
    analysis.priceable = true

    -- What you already hold, listed or otherwise. Crafting past this gets
    -- you nothing you do not already own, and ties up gold doing it.
    local room, posted, onHand, queued, limit = ns.Auctions:GetRoom(recipe.outputItemID)

    analysis.posted = posted
    analysis.onHand = onHand
    analysis.stock = posted + onHand
    analysis.queuedElsewhere = queued
    analysis.postLimit = limit
    analysis.postRoom = room
    analysis.atPostLimit = room ~= nil and room <= 0

    return analysis
end

--------------------------------------------------------------------------------
-- Ranking
--------------------------------------------------------------------------------

--- Analyse every cached recipe.
-- @param opts { craftableOnly, minProfit, minMargin, includeUnpriceable,
--               skillLineID, sortBy = "profit"|"margin"|"roi" }
function Profit:GetRanked(opts)
    opts = opts or {}

    local minProfit = opts.minProfit or ns.Config:Get("minProfit") or 0
    local minMargin = (opts.minMargin or ns.Config:Get("minMarginPercent") or 0) / 100

    local results = {}

    -- Account-wide pulls in every character's cached recipes, each analysed
    -- against the bags of whoever actually knows it.
    local source = opts.accountWide and ns.Recipes:GetAccountWide() or ns.Recipes:GetAll()

    for recipeID in pairs(source) do
        local analysis = self:Analyse(recipeID)

        if analysis then
            local keep = true

            if not analysis.priceable then
                keep = opts.includeUnpriceable == true
            else
                if analysis.profit < minProfit then keep = false end
                if keep and analysis.margin < minMargin then keep = false end
                if keep and opts.craftableOnly and analysis.craftableNow < 1 then keep = false end

                -- Already holding as many as you want listed.
                if keep and analysis.atPostLimit
                   and ns.Config:Get("hideAtPostLimit") ~= false
                   and not opts.ignorePostLimit then
                    keep = false
                end
            end

            if keep and opts.skillLineID and analysis.skillLineID ~= opts.skillLineID then
                keep = false
            end

            if keep then
                results[#results + 1] = analysis
            end
        end
    end

    local sortBy = opts.sortBy or "profit"
    table.sort(results, function(a, b)
        local left = a[sortBy] or -math.huge
        local right = b[sortBy] or -math.huge

        if left == right then
            return (a.name or "") < (b.name or "")
        end
        return left > right
    end)

    return results
end

--------------------------------------------------------------------------------
-- Commands
--------------------------------------------------------------------------------

local function ProfitColor(value)
    return value >= 0 and ns.COLORS.profit or ns.COLORS.loss
end

-- The last list shown to the player, so they can refer to a row by its number
-- instead of hunting for an internal recipe ID.
Profit.lastListing = {}

--- Turn player input into a single recipe.
-- Accepts a row number from the last listing, a shift-clicked item link, an
-- item or recipe ID, or part of a recipe name.
-- @return recipe, errorMessage, ambiguousMatches
function Profit:Resolve(query)
    query = (query or ""):gsub("^%s+", ""):gsub("%s+$", "")

    if query == "" then
        return nil, "tell me what to look at -- a name, a shift-clicked item, or a row number from /bts top"
    end

    -- Plain small numbers are row numbers from the last listing, which is what
    -- someone reading that list will naturally type.
    local rowNumber = tonumber(query)
    if rowNumber and self.lastListing[rowNumber] then
        return self.lastListing[rowNumber]
    end

    local matches = ns.Recipes:Find(query)

    if #matches == 0 then
        return nil, ("nothing matching '%s' in your cached recipes"):format(query)
    end

    if #matches > 1 then
        -- An exact name match wins outright even if it also prefixes others.
        local needle = query:lower()
        if (matches[1].name or ""):lower() == needle then
            return matches[1]
        end
        return nil, nil, matches
    end

    return matches[1]
end

ns.RegisterCommand("top", "[count] -- most profitable crafts right now", function(args)
    local limit = tonumber(args:match("(%d+)")) or 10

    if ns.Recipes:Count() == 0 then
        ns.Print("no recipes cached yet -- open a profession window once")
        return
    end

    if ns.Prices:Count() == 0 then
        ns.Print("no price data yet -- run |cffc8a44d/bts scan|r at the auction house")
        return
    end

    local ranked = ns.Profit:GetRanked({ sortBy = "profit" })

    if #ranked == 0 then
        ns.Print("nothing is profitable with the current price data")
        return
    end

    local shown = math.min(limit, #ranked)
    ns.Print(("top %d by profit per craft"):format(shown))

    wipe(ns.Profit.lastListing)

    for i = 1, shown do
        local entry = ranked[i]
        ns.Profit.lastListing[i] = ns.Recipes:Get(entry.recipeID)

        local flags = {}
        if entry.stale then flags[#flags + 1] = "stale" end
        if entry.craftableNow > 0 then flags[#flags + 1] = ("can make %d"):format(entry.craftableNow) end
        if (entry.confidence or 0) < 0.4 then flags[#flags + 1] = entry.confidenceReason end

        ns.PrintRaw(("  |c%s%2d.|r %s  |c%s%s|r  (%d%% margin)  %s"):format(
            ns.COLORS.accent, i,
            ns.Recipes:GetDisplayLink(entry.recipeID),
            ProfitColor(entry.profit), Util.FormatMoney(entry.profit, { short = true }),
            math.floor((entry.margin or 0) * 100),
            #flags > 0 and ("|c%s[%s]|r"):format(ns.COLORS.muted, table.concat(flags, ", ")) or ""))
    end

    ns.PrintRaw(("|c%sFor detail: |r|c%s/bts why 1|r|c%s, or /bts why <name>, or shift-click an item into the command.|r")
        :format(ns.COLORS.muted, ns.COLORS.accent, ns.COLORS.muted))
end)

ns.RegisterCommand("why", "<name, link or row number> -- full cost breakdown", function(args)
    local recipe, errorMessage, ambiguous = ns.Profit:Resolve(args)

    if ambiguous then
        ns.Print(("several recipes match '%s':"):format(args))

        wipe(ns.Profit.lastListing)
        for i = 1, math.min(#ambiguous, 10) do
            ns.Profit.lastListing[i] = ambiguous[i]
            ns.PrintRaw(("  |c%s%2d.|r %s"):format(
                ns.COLORS.accent, i, ns.Recipes:GetDisplayLink(ambiguous[i].recipeID)))
        end

        ns.PrintRaw(("|c%sRun |r|c%s/bts why <number>|r|c%s to pick one.|r"):format(
            ns.COLORS.muted, ns.COLORS.accent, ns.COLORS.muted))
        return
    end

    if not recipe then
        ns.Print(errorMessage)
        return
    end

    local analysis = ns.Profit:Analyse(recipe.recipeID)
    if not analysis then
        ns.Print("that recipe is no longer cached")
        return
    end

    ns.Print(ns.Recipes:GetDisplayLink(recipe.recipeID))

    if not analysis.priceable then
        ns.PrintRaw(("  |c%s%s|r"):format(ns.COLORS.warn, analysis.reason or "cannot be priced"))

        if analysis.unpriced then
            for _, itemID in ipairs(analysis.unpriced) do
                ns.PrintRaw(("    |c%sno auction data for|r %s"):format(
                    ns.COLORS.muted, Util.GetItemLabel(itemID)))
            end
        end
        return
    end

    for _, reagent in ipairs(analysis.cost.reagents) do
        local note = reagent.crafted and "cheaper to craft" or reagent.source
        local shortfall = reagent.shortfall > 0
            and (" |c%sneed %d more|r"):format(ns.COLORS.warn, reagent.shortfall)
            or ""

        ns.PrintRaw(("  %dx %s  @ %s = %s  |c%s%s|r%s"):format(
            reagent.quantity, Util.GetItemLabel(reagent.itemID),
            Util.FormatMoney(reagent.unitCost), Util.FormatMoney(reagent.lineCost),
            ns.COLORS.muted, note or "", shortfall))
    end

    ns.PrintRaw(("  material cost   %s"):format(Util.FormatMoney(analysis.totalCost)))

    if analysis.undercut then
        ns.PrintRaw(("  cheapest rival  %s"):format(Util.FormatMoney(analysis.competitorPrice)))
        ns.PrintRaw(("  you post at     %s  (yield %.1f)"):format(
            Util.FormatMoney(analysis.unitRevenue), analysis.yield))
    elseif analysis.youHoldLowest then
        ns.PrintRaw(("  |c%syou already hold the lowest listing -- holding at market|r"):format(
            ns.COLORS.profit))
        ns.PrintRaw(("  you post at     %s  (yield %.1f)"):format(
            Util.FormatMoney(analysis.unitRevenue), analysis.yield))
    else
        ns.PrintRaw(("  none listed     posting at market %s  (yield %.1f)"):format(
            Util.FormatMoney(analysis.unitRevenue), analysis.yield))
    end
    ns.PrintRaw(("  auction cut     -%s"):format(Util.FormatMoney(analysis.cut)))

    if analysis.depositKnown then
        ns.PrintRaw(("  deposit         -%s"):format(Util.FormatMoney(analysis.deposit)))
    else
        ns.PrintRaw(("  |c%sdeposit unknown -- visit an auction house to learn it|r")
            :format(ns.COLORS.muted))
    end
    ns.PrintRaw(("  |c%sprofit          %s|r  (%d%% margin, %d%% ROI)"):format(
        ProfitColor(analysis.profit), Util.FormatMoney(analysis.profit),
        math.floor(analysis.margin * 100), math.floor(analysis.roi * 100)))
    ns.PrintRaw(("  |c%sconfidence %d%% (%s), data %s old|r"):format(
        ns.COLORS.muted, math.floor((analysis.confidence or 0) * 100),
        analysis.confidenceReason or "?", Util.FormatAge(analysis.age)))
end)
