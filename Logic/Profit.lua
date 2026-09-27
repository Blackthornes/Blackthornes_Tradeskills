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

-- Shown wherever an unpriceable craft says why: the Profit tab's detail
-- panel, the craft pane's tooltip and /bts why.
local SOULBOUND_REASON = "binds on pickup, so it cannot be sold"

--------------------------------------------------------------------------------
-- What to list at
--------------------------------------------------------------------------------

--- Net profit for one craft, if a unit sold at this price.
--
-- The same arithmetic Analyse does, split out so the price can be chosen by
-- asking what each candidate would actually earn.
local function ProfitAtPrice(recipe, cost, unitPrice)
    if not recipe or not cost or not cost.priceable or not unitPrice then return nil end

    local yield = cost.yield or 1
    local revenue = unitPrice * yield
    local cut = revenue * (ns.Config:Get("auctionCut") or 0.05)

    local unitDeposit = ns.Posting and ns.Posting:GetCachedUnitDeposit(recipe.outputItemID)
    local relists = ns.Config:Get("expectedRelists") or 1
    local deposit = unitDeposit and (unitDeposit * yield * math.max(1, relists)) or 0

    return (revenue - cut) - (cost.total or 0) - deposit
end

-- Used when the setting has never been written, so the rule still holds on a
-- database saved before it existed.
local DEFAULT_MARKUP_PERCENT = 50

--- What to charge when nothing is competing: what the materials are worth,
--- plus a markup.
--
-- Two situations reach this, and they are different facts about the world
-- that happen to want the same number:
--
--   * Nobody has ever listed one, so there is no market to read at all. That
--     is not the same as the craft being worthless, and returning nothing for
--     it kept the craft out of the Profit tab and unlistable from the Sell
--     tab -- exactly the position a new recipe starts in.
--   * Every listing on the book is yours. Market value then largely reflects
--     your own prices, so holding at it means charging whatever you happened
--     to charge last time, forever, with nobody undercutting you.
--
-- In both, the materials answer: whatever they are worth, plus the markup in
-- Settings. It is never written back into the price database, because a
-- number the addon worked out must not come back an hour later looking like
-- something the auction house said. A rival listing beats it outright.
--
-- @param knownCost  a costing the caller already has, used only when it is
--   for this same recipe and is already the full-value one. Analyse costs
--   every recipe before it asks for a price, and the profession panes analyse
--   hundreds of recipes at a time, so a second walk of the same tree is worth
--   avoiding.
-- @return price, why  -- nil when there is no recipe, no material price, or
--   the setting is off. why names the markup and the material value, without
--   saying why nothing is competing; the caller knows which case it is in
--   and says so.
function Profit:DeriveFromMaterials(itemID, knownCost)
    if not itemID then return nil end
    if ns.Config:Get("priceUnscannedCrafts") == false then return nil end

    local recipeID = ns.Cost:FindRecipeForItem(itemID)
    if not recipeID then return nil end

    -- Full material value, not the cash-out-of-pocket view: a craft is not
    -- worth less to sell because its reagents happen to be paid for already.
    -- The two are the same walk while materials are valued at market, which
    -- is the default, so the caller's costing can stand in for it -- but only
    -- when it is a costing of this very recipe. Two recipes can make the same
    -- item, and pricing one off the other's materials would be a wrong number
    -- presented as a right one.
    local perUnit

    if knownCost and knownCost.recipeID == recipeID and knownCost.priceable
        and knownCost.perUnit and ns.Config:Get("valueOwnedMaterials") ~= false then
        perUnit = knownCost.perUnit
    else
        perUnit = ns.Cost:GetMaterialValue(recipeID)
    end

    if not perUnit or perUnit <= 0 then return nil end

    local markup = ns.Config:Get("unscannedMarkupPercent")
    if type(markup) ~= "number" then markup = DEFAULT_MARKUP_PERCENT end

    local price = math.floor(perUnit * (1 + markup / 100))

    -- Never under what a vendor pays for it. Below that, walking to a vendor
    -- beats the listing outright, and Posting's own floor would refuse it --
    -- so the estimate would be a price nothing could be done with.
    local vendor = Util.GetVendorSellPrice(itemID)
    if vendor and vendor > price then price = vendor end

    price = math.max(1, price)

    -- Cheap reagents cannot produce an impossible price, but a restored
    -- database carrying one can, and this is a price the player may post at.
    if not ns.Prices.IsCredible(price) then return nil end

    return price, ("%d%% over the %s its materials are worth")
        :format(markup, Util.FormatMoney(perUnit, { noColor = true }))
end

--- Round a no-competition price for the kind of auction it will be listed as.
--
-- Upwards on an item auction, unlike an undercut. There is no rival to get
-- beneath, and rounding down by up to a silver can put a cheap craft under
-- what its materials cost, which Posting would then refuse to list.
local function RoundForSale(price, isCommodity)
    if isCommodity then return price end
    return Util.CeilToSilver(price)
end

--- The unit price to list an item at, and why.
--
-- Commodities take any price down to the copper, so undercutting works the way
-- it always has. Item auctions only take whole gold and silver, which makes
-- the smallest undercut available a whole silver rather than a copper. On a
-- cheap item that is a large fraction of the price to give away in order to
-- beat sellers you could simply have matched.
--
-- So an item auction matches the cheapest rival at the silver it is listed at,
-- and only drops the extra silver when the sale would still clear the minimum
-- profit setting. Anything the profit cannot be worked out for matches, since
-- the unknown case is the one where giving gold away is least defensible.
--
-- @return price, basis, why, uncertain  -- basis is "undercut", "match",
--   "market", "derived" or "uncontested", and nil price when there is
--   nothing to go on. "derived" (never scanned) and "uncontested" (scanned,
--   but every listing is yours) are both the material-value figure from
--   DeriveFromMaterials above, and are the two bases that are not evidence
--   of what anybody else is charging. why is a sentence explaining a match
--   or either of those, since none of those words says on its own where the
--   number came from. uncertain is true when the item's commodity status is
--   not known, see below.
-- @param knownCost  optional, passed straight to DeriveFromMaterials; see
--   there for when it is used and when it is ignored.
function Profit:ChoosePostPrice(itemID, knownCost)
    if not itemID then return nil, nil end

    -- "rival" excludes your own auctions, so listing a second one does not
    -- undercut the first.
    local rival = ns.Prices:GetValue(itemID, "rival")

    -- true, false or nil. Nil is something never held and never searched
    -- for, which is most crafts not yet made, and it is priced WITHOUT the
    -- whole-silver step: the step floors anything under a silver up to one,
    -- so guessing "item auction" overstated a cheap commodity's revenue by
    -- up to double, while guessing "commodity" only understates an item
    -- auction's by the silver it would be rounded to.
    local status
    if ns.Scanner.GetCommodityStatus then
        status = ns.Scanner:GetCommodityStatus(itemID)
    else
        status = ns.Scanner:IsCommodity(itemID)
    end

    local isCommodity = status ~= false
    local uncertain = status == nil

    -- Nobody to undercut, so nothing is holding the price down to what the
    -- competition charges. What the materials are worth plus the markup is
    -- the answer in both the cases below.
    if not rival then
        local market = ns.Prices:GetValue(itemID, "market")
        local materials, markup = self:DeriveFromMaterials(itemID, knownCost)

        -- Nothing scanned, ever. Not the same as an empty auction house: an
        -- item seen before keeps its market value through an empty search, so
        -- this is only reached by something the addon has never had a price
        -- for. A stale price is still evidence and is left alone.
        if not market then
            if not materials then return nil, nil end

            return RoundForSale(materials, isCommodity), "derived",
                ("no scan has priced this, so it is %s"):format(markup), uncertain
        end

        market = math.max(1, math.floor(market))

        -- Scanned, and every listing on the book is yours. Market value is
        -- then mostly a reflection of your own prices, so holding at it means
        -- charging roughly what you charged last time for as long as nobody
        -- turns up to compete. With no competition the markup over materials
        -- is what the craft is worth selling at.
        --
        -- Only ever upwards. A market value already above the markup is a
        -- real observation of what these have sold for, and giving that up
        -- would be cutting your own price for no reason.
        --
        -- That also settles this rather than letting it run: listing at the
        -- markup pulls market value towards it over the next few scans,
        -- since your listings are the only ones in it, until market reaches
        -- the markup and holds there. The price stops moving; only the label
        -- changes, from "no competition" back to market value.
        if materials and materials > market then
            return RoundForSale(materials, isCommodity), "uncontested",
                ("nothing else is listed, so it is %s"):format(markup), uncertain
        end

        if isCommodity then return market, "market", nil, uncertain end

        return Util.RoundToSilver(market), "market"
    end

    local undercut = ns.Config:Get("undercutCopper") or 1

    if isCommodity then
        return math.max(1, math.floor(rival - undercut)), "undercut", nil, uncertain
    end

    local matchPrice = Util.RoundToSilver(rival)
    local underPrice = Util.RoundToSilver(math.max(1, math.floor(rival - undercut)))

    -- A rival already sitting at the lowest price the server allows leaves
    -- nothing below it, so matching is the only move.
    if underPrice >= matchPrice then
        return matchPrice, "match", "the game allows no lower price than the rival's"
    end

    local recipeID = ns.Cost:FindRecipeForItem(itemID)
    local recipe = recipeID and ns.Recipes:GetAny(recipeID)
    local cost = recipeID and ns.Cost:GetCraftCost(recipeID)
    local profit = ProfitAtPrice(recipe, cost, underPrice)

    if not profit then
        return matchPrice, "match",
            ("the cost to make this is unknown, so dropping %s was not worth the risk"):format(
                Util.FormatMoney(matchPrice - underPrice, { noColor = true }))
    end

    local minProfit = ns.Config:Get("minProfit") or 0

    if profit >= minProfit then return underPrice, "undercut" end

    return matchPrice, "match",
        ("undercutting to %s leaves %s profit, below your %s minimum"):format(
            Util.FormatMoney(underPrice, { noColor = true }),
            Util.FormatMoney(profit, { noColor = true }),
            Util.FormatMoney(minProfit, { noColor = true }))
end

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

--- How much having some already drags a craft down the ranking.
--
-- There is no cap to configure and deliberately so. The reason a craft you
-- already hold ten of is a worse use of the next hour than an equally
-- profitable one you hold none of is not a rule about inventory -- it is that
-- the eleventh only sells once the other ten have, so the gold comes back
-- roughly ten times slower. Profit per unit of time, not profit.
--
-- Hence dividing rather than filtering: hold none and nothing changes at all,
-- hold some and the craft slides down by about as much as it deserves. Nothing
-- is ever hidden by this, so a craft cannot silently vanish from the list.
local function StockDivisor(pipeline)
    local weight = ns.Config:Get("stockPenalty")
    if weight == nil then weight = 1 end

    if weight <= 0 or not pipeline or pipeline <= 0 then return 1 end

    return 1 + (pipeline * weight)
end

--- The value a craft is ranked on: its profit, set against what you already
--- have of it.
--
-- A loss is left alone. Dividing a negative number by a larger divisor moves it
-- closer to zero, which would promote the worst crafts in the list for the sole
-- reason that you are already sitting on a pile of them.
local function RankValue(analysis, field)
    local value = analysis[field]
    if value == nil then return -math.huge end

    if value > 0 then
        return value / (analysis.stockDivisor or 1)
    end

    return value
end

--- How many CRAFTS fit in the room left under the posted limit.
--
-- The limit and the room under it are counted in ITEMS, because that is what
-- goes up for sale. Every queue is counted in CRAFTS. A recipe that yields
-- five per craft makes those two numbers differ by five, so clamping a craft
-- count straight against the item room lets a limit of ten become fifty items
-- on the auction house.
--
-- quantityMin rather than the average yield, matching Logic/Queue.lua,
-- Logic/Crafting.lua and Data/Auctions.lua: the panes must agree with each
-- other on the same recipe, and a fraction of a craft is not a thing.
--
-- Any room at all allows one craft. You cannot make part of one, and refusing
-- the craft outright would stall a queue on a recipe that still has shelf
-- space.
local function RoomInCrafts(room, recipe)
    if room == nil then return nil end
    if room <= 0 then return 0 end

    local perCraft = math.max(1, (recipe and recipe.quantityMin) or 1)

    return math.max(1, math.floor(room / perCraft))
end

-- Exposed for tools/test_mail.lua. These two decide the order of the list the
-- player actually reads, and they are the part most likely to want tuning, so
-- they are testable without standing up the whole analysis.
Profit._StockDivisor = StockDivisor
Profit._RankValue = RankValue

-- Exposed for tools/test_craftroom.lua, and called directly by the panes
-- when they hold a recipe but no analysis.
Profit.RoomInCrafts = RoomInCrafts

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

    -- Read before the early exits below, so a craft that cannot be priced can
    -- still say it would raise your skill.
    analysis.skillUp = ns.SkillUp and ns.SkillUp:GetForRecipe(recipeID, recipe) or nil

    if not recipe.outputItemID then
        -- Enchants and similar have no sellable output item.
        analysis.reason = "makes nothing that can be sold"
        return analysis
    end

    -- What the craft is worth disenchanted, read before the early exits
    -- below: a craft that cannot be sold may still be worth breaking down.
    -- Shown beside the sale price, never ranked on.
    if ns.Disenchant then
        analysis.disenchantable = ns.Disenchant:IsDisenchantable(recipe.outputItemID) or nil
        if analysis.disenchantable then
            analysis.disenchantValue, analysis.disenchantPartial =
                ns.Disenchant:GetValue(recipe.outputItemID)
        end
    end

    -- Binds on pickup: the thing made is soulbound the moment it exists, so
    -- there is no sale to cost and no profit to rank on. Out of the list the
    -- same way an unpriced craft is, which keeps it off the skill-up star too,
    -- while "Show unpriced" and the craft pane still show it with its skill-up
    -- colour for anyone levelling on it. Unknown (not cached yet) is kept: the
    -- tab redraws when the item arrives, and a craft that may well sell should
    -- not vanish on a guess.
    if Util.IsBoundOnPickup and Util.IsBoundOnPickup(recipe.outputItemID) then
        analysis.soulbound = true
        analysis.reason = SOULBOUND_REASON
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

    -- Shown for context so the full picture is visible: the overall cheapest
    -- listing and your own, alongside the rival price actually being undercut.
    local priceRecord = ns.Prices:Get(recipe.outputItemID)
    analysis.overallMin = priceRecord and priceRecord.min or nil
    analysis.ownListing = priceRecord and priceRecord.ownMin or nil

    -- Priced through the same chooser the Sell tab posts at, so the profit
    -- shown here is the profit of the listing that would actually be made.
    -- On an item auction that may be a match rather than an undercut, because
    -- the server will not take a price with copper in it.
    local unitRevenue, basis, _, uncertain =
        self:ChoosePostPrice(recipe.outputItemID, cost)

    analysis.priceBasis = basis
    -- Set when the price above is the materials-plus-markup estimate rather
    -- than anything the auction house said. Every display of the number
    -- checks this: an estimate presented as a market price is how you end up
    -- crafting for a demand that was never measured.
    analysis.priceDerived = basis == "derived" or nil
    -- Set when the item is scanned but every listing is yours, so the price
    -- above is the markup over materials rather than what anyone else
    -- charges. Told apart from priceDerived because there IS scan data here,
    -- and the age and confidence beside it are real.
    analysis.priceUncontested = basis == "uncontested" or nil
    -- Set when nobody has been able to say whether the output sells as a
    -- commodity or an item auction, so the price above is the plain undercut
    -- and may round to a silver when it is actually listed.
    analysis.priceUncertain = uncertain or nil

    if competitor then
        analysis.competitorPrice = competitor
        analysis.undercut = true
        analysis.matchedRival = basis == "match"
    else
        analysis.undercut = false
        analysis.youHoldLowest = ns.Prices:HoldsLowest(recipe.outputItemID)
    end

    if not unitRevenue then
        -- A craft can land here with priced materials when the estimate is
        -- switched off, and with unpriced ones either way; the reason below
        -- covers both, since the output is what has no price in each.
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

    -- One item disenchanted against one item sold at the price above.
    if analysis.disenchantValue and analysis.disenchantValue > unitRevenue then
        analysis.disenchantBeatsSale = true
    end
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
    local room, posted, onHand, queued, limit, inMail =
        ns.Auctions:GetRoom(recipe.outputItemID)

    analysis.posted = posted
    analysis.onHand = onHand
    analysis.inMail = inMail or 0
    analysis.stock = posted + onHand + analysis.inMail
    analysis.queuedElsewhere = queued
    analysis.postLimit = limit
    analysis.postRoom = room
    analysis.roomInCrafts = RoomInCrafts(room, recipe)
    analysis.atPostLimit = room ~= nil and room <= 0

    -- Everything already committed to this item: what you hold, plus what the
    -- queue is about to make. This is what pushes a craft down the list.
    analysis.pipeline = analysis.stock + queued
    analysis.stockDivisor = StockDivisor(analysis.pipeline)

    -- Worth a star: it raises your skill and it pays. Only a mark -- the
    -- ranking is untouched, so nothing moves up the list for being a skill up
    -- and nothing is hidden for not being one.
    analysis.recommended = ns.SkillUp and ns.SkillUp:IsWorthIt(analysis) or false

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

    -- Ranked on profit adjusted for what you already hold; the columns still
    -- show the real figure, because that is the number you are deciding on.
    -- opts.ignoreStock is for callers that want the raw order, such as the
    -- tests and anything reporting on the market rather than on your shelf.
    table.sort(results, function(a, b)
        local left = opts.ignoreStock and (a[sortBy] or -math.huge) or RankValue(a, sortBy)
        local right = opts.ignoreStock and (b[sortBy] or -math.huge) or RankValue(b, sortBy)

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
        return nil, "type a name, shift-click an item, or give a row number from /bts top"
    end

    -- Plain small numbers are row numbers from the last listing, which is what
    -- someone reading that list will naturally type.
    local rowNumber = tonumber(query)
    if rowNumber and self.lastListing[rowNumber] then
        return self.lastListing[rowNumber]
    end

    local matches = ns.Recipes:Find(query)

    if #matches == 0 then
        return nil, ("none of your recipes match '%s'"):format(query)
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

ns.RegisterCommand("top", "[count]: most profitable crafts right now", function(args)
    local limit = tonumber(args:match("(%d+)")) or 10

    if ns.Recipes:Count() == 0 then
        ns.Print("no recipes read yet. Open a profession window once")
        return
    end

    if ns.Prices:Count() == 0 then
        ns.Print("no price data yet. Run |cffc8a44d/bts scan|r at the auction house")
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
        if (entry.confidence or 0) < 0.4 and entry.confidenceReason then
            flags[#flags + 1] = entry.confidenceReason
        end

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

ns.RegisterCommand("why", "<name, link or row number>: full cost breakdown", function(args)
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
        ns.Print("that recipe is no longer saved")
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
        ns.PrintRaw(("  you post at     %s  (makes %.1f)"):format(
            Util.FormatMoney(analysis.unitRevenue), analysis.yield))
    elseif analysis.priceUncontested then
        -- Said before the number: nobody is competing, so this price is your
        -- own materials plus the markup, not what the market is doing.
        ns.PrintRaw(("  |c%snobody else is listing one, so this is priced off your materials|r"):format(
            ns.COLORS.profit))
        ns.PrintRaw(("  you post at     %s  (makes %.1f)"):format(
            Util.FormatMoney(analysis.unitRevenue), analysis.yield))
    elseif analysis.youHoldLowest then
        ns.PrintRaw(("  |c%syou already have the cheapest listing, so staying at market price|r"):format(
            ns.COLORS.profit))
        ns.PrintRaw(("  you post at     %s  (makes %.1f)"):format(
            Util.FormatMoney(analysis.unitRevenue), analysis.yield))
    elseif analysis.priceDerived then
        -- Said before the number, not after it: this one is the addon's own
        -- estimate and reading it as a market price is the mistake to avoid.
        ns.PrintRaw(("  |c%snever scanned, so estimated from material value|r"):format(
            ns.COLORS.warn))
        ns.PrintRaw(("  estimate at     %s  (makes %.1f)"):format(
            Util.FormatMoney(analysis.unitRevenue), analysis.yield))
    else
        ns.PrintRaw(("  none listed     posting at market %s  (makes %.1f)"):format(
            Util.FormatMoney(analysis.unitRevenue), analysis.yield))
    end
    ns.PrintRaw(("  auction cut     -%s"):format(Util.FormatMoney(analysis.cut)))

    if analysis.depositKnown then
        ns.PrintRaw(("  deposit         -%s"):format(Util.FormatMoney(analysis.deposit)))
    else
        ns.PrintRaw(("  |c%sdeposit unknown until you visit an auction house|r")
            :format(ns.COLORS.muted))
    end
    ns.PrintRaw(("  |c%sprofit          %s|r  (%d%% margin, %d%% return on cost)"):format(
        ProfitColor(analysis.profit), Util.FormatMoney(analysis.profit),
        math.floor(analysis.margin * 100), math.floor(analysis.roi * 100)))
    ns.PrintRaw(("  |c%sconfidence %d%%%s, data %s old|r"):format(
        ns.COLORS.muted, math.floor((analysis.confidence or 0) * 100),
        analysis.confidenceReason and (" (" .. analysis.confidenceReason .. ")") or "",
        Util.FormatAge(analysis.age)))
end)

--- What the client says about binding, for every cached recipe's output.
--
-- The Profit list drops a craft on the strength of one number out of
-- GetItemInfo. This is how to see that number rather than trust it: how many
-- outputs read as bound, how many as sellable, how many the client has not
-- cached yet, and which crafts were taken out.
ns.RegisterCommand("soulbound", "which crafts are left out of the Profit list for binding on pickup",
function()
    local bound, free, unknown = {}, 0, 0
    local byType = {}

    for recipeID, recipe in pairs(ns.Recipes:GetAll()) do
        if recipe.outputItemID then
            local isBound, bindType = Util.IsBoundOnPickup(recipe.outputItemID)

            if bindType then
                byType[bindType] = (byType[bindType] or 0) + 1
            end

            if isBound == nil then
                unknown = unknown + 1
            elseif isBound then
                bound[#bound + 1] = recipeID
            else
                free = free + 1
            end
        end
    end

    ns.Print(("|c%sSoulbound crafts|r"):format(ns.COLORS.accent))
    ns.PrintRaw(("  %d bind on pickup (left out), %d can be sold, %d not loaded by the game yet"):format(
        #bound, free, unknown))

    local types = {}
    for bindType, count in pairs(byType) do
        types[#types + 1] = ("type %d: %d"):format(bindType, count)
    end
    table.sort(types)
    ns.PrintRaw(("  |c%sbind type the game gave: %s  (1 pickup, 2 equip, 3 use, 4 quest)|r"):format(
        ns.COLORS.muted, #types > 0 and table.concat(types, ", ") or "nothing answered"))

    table.sort(bound, function(a, b)
        local left, right = ns.Recipes:GetAny(a), ns.Recipes:GetAny(b)
        return ((left and left.name) or "") < ((right and right.name) or "")
    end)

    for i = 1, math.min(#bound, 15) do
        ns.PrintRaw("    " .. ns.Recipes:GetDisplayLink(bound[i]))
    end

    if #bound > 15 then
        ns.PrintRaw(("    |c%s...and %d more|r"):format(ns.COLORS.muted, #bound - 15))
    end
end)
