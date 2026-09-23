-- Blackthornes Tradeskills -- Data/Prices.lua
-- The price database: what an item costs, what it is worth, and how confident
-- we are about either number.
--
-- Everything here is derived from our own scans. There is no external data
-- source, so the honest thing to do is track how thin the evidence is and
-- surface that alongside the number, rather than presenting a single
-- authoritative-looking price built from three listings.

local _, ns = ...

local Prices = ns.NewModule("Prices")

local Util = ns.Util

-- How much of a new scan's value replaces the running average. Low enough that
-- one weird scan cannot swing a price, high enough to track a real move.
local EMA_ALPHA = 0.3

-- Fraction of an item's listed quantity treated as "the market" when pricing.
-- Only the cheap end of the book matters: nobody sells at the 40th percentile.
local MARKET_DEPTH = 0.25

-- Outlier guards, applied against the first-pass weighted mean.
local OUTLIER_LOW = 0.30
local OUTLIER_HIGH = 3.00

-- The most copper a price is allowed to be before it is read as junk rather
-- than as a market observation.
--
-- 2026-09-21: a full scan came back with a listing at 9,999,990,200 copper --
-- about 999,999g -- which went into the database as that item's market value
-- and minimum, and then failed the save outright, because the client's own
-- number formatting cannot write a value past the signed 32-bit range.
-- Serialize handles the writing now, but the price still had no business being
-- treated as what the item is worth: the cap on a classic-era character's purse
-- is the same 2^31 copper, so nobody can pay it, nobody buys at it, and a craft
-- priced off it goes to the top of the Profit list and never sells.
--
-- Anything at or below this is kept exactly as the client reported it. Only the
-- impossible is refused.
local MAX_CREDIBLE_COPPER = 2 ^ 31 - 1

Prices.MAX_CREDIBLE_COPPER = MAX_CREDIBLE_COPPER

--- Could this price actually be paid, and is it a number at all?
-- Nil is credible: "no price" is a real state and is not what this rejects.
function Prices.IsCredible(price)
    if price == nil then return true end

    return type(price) == "number"
        and price == price                  -- NaN fails every comparison below
        and price >= 0
        and price <= MAX_CREDIBLE_COPPER
end

-- Keeping full history for every item on the auction house would bloat
-- SavedVariables badly, so history is a short ring and stale items are pruned.
local MAX_HISTORY = 12
local PRUNE_AFTER_SECONDS = 21 * 24 * 3600

--------------------------------------------------------------------------------
-- Market value
--------------------------------------------------------------------------------

--- Collapse one item's listings into a single representative unit price.
-- @param listings array of { unitPrice = copper, quantity = n, isOwn = bool }
-- @return marketValue, minBuyout, totalQuantity, rivalMin, ownMin
function Prices:Summarise(listings)
    if not listings or #listings == 0 then
        return nil, nil, 0, nil, nil
    end

    table.sort(listings, function(a, b) return a.unitPrice < b.unitPrice end)

    local totalQuantity = 0
    for i = 1, #listings do
        totalQuantity = totalQuantity + (listings[i].quantity or 1)
    end

    local minBuyout = listings[1].unitPrice

    -- The price to undercut is the cheapest listing that is not yours.
    --
    -- Listings are sorted ascending, so this finds the cheapest rival wherever
    -- it sits relative to your own auction: if somebody has posted far below
    -- you, that is the price you have to beat to sell, and this picks it up.
    -- Skipping your own listings only stops you undercutting yourself; it never
    -- hides a cheaper competitor.
    --
    -- Market value still counts your listings: they are part of the market.
    local rivalMin, ownMin
    for i = 1, #listings do
        local listing = listings[i]

        if listing.isOwn then
            ownMin = ownMin or listing.unitPrice
        else
            rivalMin = rivalMin or listing.unitPrice
        end

        if rivalMin and ownMin then break end
    end

    -- First pass: weighted mean over the cheapest slice of the book.
    local targetQuantity = math.max(1, math.floor(totalQuantity * MARKET_DEPTH + 0.5))
    local takenQuantity, weightedSum = 0, 0

    for i = 1, #listings do
        local listing = listings[i]
        local quantity = listing.quantity or 1
        local take = math.min(quantity, targetQuantity - takenQuantity)

        if take <= 0 then break end

        weightedSum = weightedSum + listing.unitPrice * take
        takenQuantity = takenQuantity + take
    end

    if takenQuantity == 0 then
        return minBuyout, minBuyout, totalQuantity, rivalMin, ownMin
    end

    local firstPass = weightedSum / takenQuantity

    -- Second pass: drop listings that are absurd relative to the first pass.
    -- A single 1-copper troll listing should not define the market, and neither
    -- should someone's 500g fat-finger.
    local low, high = firstPass * OUTLIER_LOW, firstPass * OUTLIER_HIGH
    local keptQuantity, keptSum = 0, 0

    for i = 1, #listings do
        local listing = listings[i]
        local quantity = listing.quantity or 1

        if listing.unitPrice >= low and listing.unitPrice <= high then
            local take = math.min(quantity, targetQuantity - keptQuantity)
            if take > 0 then
                keptSum = keptSum + listing.unitPrice * take
                keptQuantity = keptQuantity + take
            end
        end
    end

    local marketValue = keptQuantity > 0 and (keptSum / keptQuantity) or firstPass

    return math.floor(marketValue + 0.5), minBuyout, totalQuantity, rivalMin, ownMin
end

--------------------------------------------------------------------------------
-- Recording
--------------------------------------------------------------------------------

function Prices:GetTable()
    return ns.Config:GetPriceTable()
end

--- Fold one item's scan result into the database.
function Prices:Record(itemID, marketValue, minBuyout, quantity, scannedAt, rivalMin, ownMin)
    if not itemID or not marketValue then return end

    -- Every path that learns a price ends up here -- browse rows, the full
    -- replicate scan, targeted searches and the passive capture of the
    -- player's own searches -- so this is the one place that has to hold. A
    -- junk price is refused rather than stored; the item keeps whatever it
    -- already had, which is worth more than a number nobody can pay.
    if not Prices.IsCredible(marketValue) then
        Prices.implausible = (Prices.implausible or 0) + 1
        Prices.lastImplausible = { itemID = itemID, price = marketValue, at = time() }
        return nil, "implausible"
    end

    -- The book's own figures are dropped individually: an item can have one
    -- absurd listing above a shelf of sane ones, and losing the sane market
    -- value with it would be the worse trade.
    if not Prices.IsCredible(minBuyout) then minBuyout = nil end
    if not Prices.IsCredible(rivalMin) then rivalMin = nil end
    if not Prices.IsCredible(ownMin) then ownMin = nil end

    scannedAt = scannedAt or time()

    local prices = self:GetTable()
    local record = prices[itemID]

    if not record then
        record = { scans = 0, history = {} }
        prices[itemID] = record
    end

    -- EMA, seeded on first sight so a brand new item is not anchored to zero.
    if record.market then
        record.market = math.floor(record.market * (1 - EMA_ALPHA) + marketValue * EMA_ALPHA + 0.5)
    else
        record.market = marketValue
    end

    record.min = minBuyout
    -- nil when every listing is yours, which is a real and meaningful state:
    -- there is nobody to undercut.
    record.rivalMin = rivalMin
    record.ownMin = ownMin
    record.quantity = quantity
    record.seen = scannedAt
    record.scans = (record.scans or 0) + 1

    local history = record.history
    history[#history + 1] = { t = scannedAt, m = record.market, q = quantity }
    while #history > MAX_HISTORY do
        table.remove(history, 1)
    end

    return record
end

--- Record that a search came back with nothing listed at all.
--
-- An empty order book is an observation, not a failed scan, and the two have
-- to be told apart. Recording nothing leaves the last scan's rivalMin in
-- place, and the next listing then undercuts a seller who has already sold
-- out or expired -- which is the exact mistake a fresh price check exists to
-- prevent.
--
-- The smoothed market value survives on purpose: what an item is worth does
-- not become unknown the moment nobody happens to be selling one. What does
-- go is everything that describes the current book, because there isn't one.
function Prices:RecordEmpty(itemID, scannedAt)
    if not itemID then return end

    scannedAt = scannedAt or time()

    local prices = self:GetTable()
    local record = prices[itemID]

    if not record then
        record = { scans = 0, history = {} }
        prices[itemID] = record
    end

    record.min = nil
    -- nil rivalMin is already the understood "nobody to undercut" state, so
    -- pricing needs no new case for this: GetPostPrice falls through to
    -- market value on its own.
    record.rivalMin = nil
    record.ownMin = nil
    record.quantity = 0
    record.seen = scannedAt
    record.scans = (record.scans or 0) + 1

    record.history = record.history or {}

    local history = record.history
    history[#history + 1] = { t = scannedAt, m = record.market, q = 0 }
    while #history > MAX_HISTORY do
        table.remove(history, 1)
    end

    return record
end

--- Commit a whole scan at once: { [itemID] = { {unitPrice, quantity}, ... } }.
-- Returns the number of items recorded.
function Prices:CommitScan(observations, scannedAt)
    scannedAt = scannedAt or time()

    local recorded = 0
    for itemID, listings in pairs(observations) do
        local marketValue, minBuyout, quantity, rivalMin, ownMin = self:Summarise(listings)
        if marketValue then
            self:Record(itemID, marketValue, minBuyout, quantity, scannedAt, rivalMin, ownMin)
            recorded = recorded + 1
        end
    end

    ns.db.lastFullScan = scannedAt
    return recorded
end

--------------------------------------------------------------------------------
-- Reading
--------------------------------------------------------------------------------

function Prices:Get(itemID)
    return self:GetTable()[itemID]
end

--- Best estimate of what one unit is worth.
--
-- `which` is one of:
--   "market" (default) smoothed value, for valuing what you already own
--   "min"              cheapest listing, what it costs you to buy right now
--   "rival"            cheapest listing that is not yours, the price to undercut
--
-- "rival" deliberately does not fall back to `min`: if the only listing is
-- yours, there is nobody to undercut, and pretending otherwise would have you
-- undercut yourself.
function Prices:GetValue(itemID, which)
    local record = self:GetTable()[itemID]
    if not record then return nil end

    if which == "min" then
        return record.min or record.market
    elseif which == "rival" then
        return record.rivalMin
    end

    return record.market or record.min
end

--- True when your own auction is currently the cheapest listing.
function Prices:HoldsLowest(itemID)
    local record = self:GetTable()[itemID]
    if not record or not record.ownMin then return false end

    return record.rivalMin == nil or record.ownMin < record.rivalMin
end

function Prices:GetAge(itemID)
    local record = self:GetTable()[itemID]
    if not record or not record.seen then return nil end
    return time() - record.seen
end

function Prices:IsStale(itemID)
    local age = self:GetAge(itemID)
    if not age then return true end
    return age > (ns.Config:Get("staleAfterSeconds") or (48 * 3600))
end

--- Rough sale velocity, 0..1.
--
-- Quantity shrinking between scans implies sales; quantity growing implies
-- restocking. Restocking masks sales, so this systematically under-reports and
-- is only ever presented as a confidence hint, never as a sale rate.
function Prices:GetLiquidity(itemID)
    local record = self:GetTable()[itemID]
    if not record or not record.history or #record.history < 2 then
        return nil
    end

    local history = record.history
    local drops, total = 0, 0

    for i = 2, #history do
        local previous = history[i - 1].q or 0
        local current = history[i].q or 0

        if previous > 0 then
            if current < previous then
                drops = drops + (previous - current)
            end
            total = total + previous
        end
    end

    if total == 0 then return nil end
    return Util.Clamp(drops / total, 0, 1)
end

--- How much to trust this item's price: scan count, recency and depth.
-- Returns 0..1 and a short reason for the weakest factor.
-- Above this, a component is not worth calling out as a weakness.
local WEAKNESS_THRESHOLD = 0.8

function Prices:GetConfidence(itemID)
    local record = self:GetTable()[itemID]
    if not record then return 0, "never seen" end

    local scanScore = Util.Clamp((record.scans or 0) / 5, 0, 1)
    local depthScore = Util.Clamp((record.quantity or 0) / 20, 0, 1)

    local age = self:GetAge(itemID) or math.huge
    local staleAfter = ns.Config:Get("staleAfterSeconds") or (48 * 3600)
    local ageScore = Util.Clamp(1 - (age / staleAfter), 0, 1)

    local score = (scanScore * 0.3) + (depthScore * 0.3) + (ageScore * 0.4)

    -- Name what is holding the number down, and only when something is.
    --
    -- This used to pick a weakest link unconditionally, off a <= comparison
    -- that resolves ties in favour of the first branch. An item scanned
    -- seconds ago, deep and seen often, has all three scores at 1, so every
    -- one of those ties went to age and it reported "99% (stale data)" about
    -- data that could not have been fresher. A diagnostic that confidently
    -- names the wrong cause is worse than one that says nothing.
    local weakest = math.min(scanScore, depthScore, ageScore)
    if weakest >= WEAKNESS_THRESHOLD then return score, nil end

    local reason
    if ageScore == weakest then
        reason = "stale data"
    elseif depthScore == weakest then
        reason = "few listed"
    else
        reason = "few scans"
    end

    return score, reason
end

--------------------------------------------------------------------------------
-- Maintenance
--------------------------------------------------------------------------------

--- Drop items nobody has listed in weeks, so the database does not grow forever.
function Prices:Prune()
    local prices = self:GetTable()
    local cutoff = time() - PRUNE_AFTER_SECONDS

    local removed = 0
    for itemID, record in pairs(prices) do
        if (record.seen or 0) < cutoff then
            prices[itemID] = nil
            removed = removed + 1
        end
    end

    if removed > 0 then
        ns.Debug(("removed %d old price(s)"):format(removed))
    end
    return removed
end

function Prices:Count()
    return Util.Count(self:GetTable())
end

--- Clear out prices a restored database is already carrying that nothing can
--- pay. One such record is what broke the save on 2026-09-21, and a database
--- that came back from macro storage or the data addon with one in it would
--- otherwise keep pricing off it for weeks. The per-field figures go one at a
--- time; only a record whose market value itself is impossible is dropped.
-- @return recordsDropped, fieldsCleared
function Prices:Scrub()
    local prices = self:GetTable()
    local dropped, cleared = 0, 0

    for itemID, record in pairs(prices) do
        if not Prices.IsCredible(record.market) then
            prices[itemID] = nil
            dropped = dropped + 1
        else
            for _, field in ipairs({ "min", "rivalMin", "ownMin" }) do
                if not Prices.IsCredible(record[field]) then
                    record[field] = nil
                    cleared = cleared + 1
                end
            end
        end
    end

    if dropped > 0 or cleared > 0 then
        ns.Warn(("removed %d price(s) and %d figure(s) above %s -- nobody could pay that much"):format(
            dropped, cleared, Util.FormatMoney(MAX_CREDIBLE_COPPER, { noColor = true, short = true })))
    end

    return dropped, cleared
end

--- How many prices have been refused since the count was last taken, and the
--- last one refused. Reset by reading, so a scan reports its own tally.
function Prices:TakeImplausibleCount()
    local count, last = Prices.implausible or 0, Prices.lastImplausible
    Prices.implausible, Prices.lastImplausible = 0, nil
    return count, last
end

function Prices:OnEnable()
    self:Scrub()
    self:Prune()
end

--------------------------------------------------------------------------------
-- Commands
--------------------------------------------------------------------------------

ns.RegisterCommand("price", "<item link or name> -- what the auction house says", function(args)
    -- Shift-clicking an item into chat is the natural way to name one.
    local itemID = tonumber(args:match("item:(%d+)")) or tonumber(args:match("^%s*(%d+)%s*$"))

    if not itemID then
        local name = args:gsub("^%s+", ""):gsub("%s+$", "")
        if name ~= "" and Util.HasFunction("C_Item.GetItemInfoInstant") then
            local ok, resolved = pcall(C_Item.GetItemInfoInstant, name)
            if ok then itemID = resolved end
        end
    end

    if not itemID then
        ns.Print("usage: /bts price <shift-clicked item, or exact item name>")
        return
    end

    local record = ns.Prices:Get(itemID)
    if not record then
        ns.Print(("no auction data for %s -- run |cffc8a44d/bts scan|r at the auction house")
            :format(Util.GetItemLabel(itemID)))
        return
    end

    local confidence, reason = ns.Prices:GetConfidence(itemID)
    local liquidity = ns.Prices:GetLiquidity(itemID)

    ns.Print(Util.GetItemLabel(itemID))
    ns.PrintRaw(("  market %s   min %s   qty %d"):format(
        Util.FormatMoney(record.market), Util.FormatMoney(record.min), record.quantity or 0))

    if record.rivalMin then
        -- Asked of the chooser rather than worked out again here, so this
        -- cannot drift from the price the Sell tab would actually use.
        local postPrice, basis, why = ns.Profit:ChoosePostPrice(itemID)

        ns.PrintRaw(("  cheapest rival %s   you would post at %s (%s)"):format(
            Util.FormatMoney(record.rivalMin),
            Util.FormatMoney(postPrice or record.rivalMin),
            basis or "no price"))

        -- "match" on its own does not say whether undercutting was rejected
        -- on the numbers or never costed at all, and those want different
        -- things from you.
        if why then ns.PrintRaw(("    %s"):format(why)) end
    elseif ns.Prices:HoldsLowest(itemID) then
        ns.PrintRaw(("  |c%syou hold the lowest listing|r"):format(ns.COLORS.profit))
    end
    ns.PrintRaw(("  seen %s over %d scan(s)"):format(
        Util.FormatAgeAgo(ns.Prices:GetAge(itemID)), record.scans or 0))
    ns.PrintRaw(("  confidence %d%%%s   stock moving %s"):format(
        math.floor(confidence * 100), reason and (" (" .. reason .. ")") or "",
        liquidity and ("%d%%"):format(math.floor(liquidity * 100)) or "unknown"))
end)
