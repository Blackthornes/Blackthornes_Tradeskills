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

-- A lone listing this far under everything else is not the price to beat.
-- Asked 2026-09-26: "make undercut ignore a lone low posting".
local LONE_LOW = 1 / 3

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

--- Is the cheapest listing a lone one far below the rest of the book?
--
-- Someone else's single listing under a third of the next listing up, and
-- under a third of what the item has been selling for when that is known.
-- Following it down would list well under value to chase one seller, and
-- anyone buying clears it in one purchase anyway. Two listings down there
-- are a real price drop and are left alone, as is a listing with nothing
-- above it to compare against.
--
-- So is one that holds half or more of everything listed. Nobody clears
-- that in one purchase: 1000 Linen at 10c, with 60 more at 50c, is where
-- Linen sells now. Skipped, it left the price to beat at 50c while the 1000
-- sat at 10c. A stack among several, the usual lone listing, is still
-- skipped.
--
-- @param listings sorted cheapest first
-- @param reference the item's stored market value, or nil
-- @param totalQuantity units across the whole book
local function IsLoneLow(listings, reference, totalQuantity)
    local first, second = listings[1], listings[2]
    if not first or not second or first.isOwn then return false end

    local quantity = first.quantity or 1
    if quantity > 1 and quantity * 2 >= (totalQuantity or quantity) then return false end

    if first.unitPrice >= second.unitPrice * LONE_LOW then return false end
    if reference and reference > 0 and first.unitPrice >= reference * LONE_LOW then return false end

    return true
end

--- Collapse one item's listings into a single representative unit price.
-- @param listings array of { unitPrice = copper, quantity = n, isOwn = bool }
-- @param reference the item's stored market value, when known. Only used to
--   decide whether the cheapest listing is a lone low one.
-- @return marketValue, minBuyout, totalQuantity, rivalMin, ownMin, ignoredLow
--   ignoredLow is the price of a lone low listing left out of rivalMin and
--   market value, or nil.
function Prices:Summarise(listings, reference)
    if not listings or #listings == 0 then
        return nil, nil, 0, nil, nil, nil
    end

    table.sort(listings, function(a, b) return a.unitPrice < b.unitPrice end)

    local totalQuantity = 0
    for i = 1, #listings do
        totalQuantity = totalQuantity + (listings[i].quantity or 1)
    end

    -- What it costs to buy one right now is still the true cheapest.
    local minBuyout = listings[1].unitPrice

    -- Everything below works on the book without the lone low listing, so it
    -- is neither undercut nor allowed to drag market value down. The caller's
    -- table is left as it was.
    local ignoredLow
    if IsLoneLow(listings, reference, totalQuantity) then
        ignoredLow = listings[1].unitPrice

        local rest = {}
        for i = 2, #listings do rest[#rest + 1] = listings[i] end
        listings = rest
    end

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
        return minBuyout, minBuyout, totalQuantity, rivalMin, ownMin, ignoredLow
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

    return math.floor(marketValue + 0.5), minBuyout, totalQuantity, rivalMin, ownMin, ignoredLow
end

--------------------------------------------------------------------------------
-- Recording
--------------------------------------------------------------------------------

function Prices:GetTable()
    return ns.Config:GetPriceTable()
end

--- Fold one item's scan result into the database.
function Prices:Record(itemID, marketValue, minBuyout, quantity, scannedAt, rivalMin, ownMin, ignoredLow)
    -- Lets a list know prices moved without comparing every record.
    Prices.changes = (Prices.changes or 0) + 1

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
    if not Prices.IsCredible(ignoredLow) then ignoredLow = nil end

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
    record.ignoredLow = ignoredLow
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
    -- Lets a list know prices moved without comparing every record.
    Prices.changes = (Prices.changes or 0) + 1

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
    record.ignoredLow = nil
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

--- After a complete full scan, mark every item it did not see as sold out.
--
-- A full scan used to update only the items it found. Anything that had sold
-- out or expired since the last scan kept its old listing on record, so the
-- tabs went on showing a cheapest price nobody was selling at, and the next
-- listing undercut a seller who was already gone.
--
-- Only a scan that read the whole auction house may do this. A scan cut
-- short (page cap, timeout, another search taking the results over) did not
-- look everywhere, so what it missed is unknown, not sold out. Records
-- written since the scan started are left alone too: a search made during
-- the scan is newer than anything the scan read.
--
-- @param seen      { [itemID] = true } for every item the scan read a row of
-- @param startedAt time() when the scan began
-- @return how many items were marked sold out
function Prices:ClearMissing(seen, startedAt, scannedAt)
    scannedAt = scannedAt or time()
    startedAt = startedAt or scannedAt

    local gone = {}
    for itemID, record in pairs(self:GetTable()) do
        local listed = (record.quantity or 0) > 0 or record.min or record.rivalMin or record.ownMin
        if listed and not seen[itemID] and (record.seen or 0) < startedAt then
            gone[#gone + 1] = itemID
        end
    end

    for _, itemID in ipairs(gone) do
        self:RecordEmpty(itemID, scannedAt)
    end

    return #gone
end

--- When this realm and faction last had a full scan.
--
-- Prices are kept per realm and faction, so the stamp is too. One stamp for
-- the whole account made an Alliance scan at 10:00 read as "scanned 5m ago"
-- on a Horde character with two-day-old prices, hid that character's deals
-- (they looked older than the scan) and skipped its automatic scan. The old
-- account-wide stamp is read only until the first scan after the update:
-- after that it belongs to whichever realm wrote it last, not to this one.
function Prices:GetLastFullScan()
    local db = ns.db
    if not db then return nil end
    local byRealm = db.lastFullScanByRealm
    if not byRealm then return db.lastFullScan end
    local key = ns.Config and ns.Config.GetRealmKey and ns.Config:GetRealmKey()
    return key and byRealm[key] or nil
end

--- When this realm and faction last had a scan of any kind: a full one, or a
--- sweep that stopped at the page limit.
--
-- On a big auction house every sweep stops at the page limit, so it never
-- gets a full scan stamp. Deal lists judged by the full scan stamp alone
-- kept days-old listings, and the header said "never scanned". Only clearing
-- sold-out items needs a real full scan; that still reads GetLastFullScan.
-- The second value is true when the newest scan is the one that stopped at
-- the page limit.
function Prices:GetLastScan()
    local full = self:GetLastFullScan()
    local db = ns.db
    local key = ns.Config and ns.Config.GetRealmKey and ns.Config:GetRealmKey()
    local capped = db and key and db.lastCappedScanByRealm and db.lastCappedScanByRealm[key]
    if capped and (not full or capped > full) then return capped, true end
    return full, false
end
function Prices:SetLastFullScan(at)

    local db = ns.db
    if not db then return end
    local key = ns.Config and ns.Config.GetRealmKey and ns.Config:GetRealmKey()
    if key then
        db.lastFullScanByRealm = db.lastFullScanByRealm or {}
        db.lastFullScanByRealm[key] = at
    end
end

--- ClearMissing, for a scan that believes it read the whole auction house.
--
-- The last line of defence for the player's prices. A scan that saw far
-- fewer items than the last whole one on this realm is not trusted to say
-- what sold out: that is what a stray search looks like. Unlike a fixed
-- share of the book, the check heals itself: a market that really did
-- shrink is refused once, and accepted when the next scan finds about the
-- same smaller number. One small stray search is not taken as the new size,
-- so it cannot open the way for the next one.
--
-- With no whole scan remembered yet on this realm, what the saved prices
-- say is listed stands in for it.
--
-- @return how many items were marked sold out, and why none were if so
function Prices:ClearMissingIfWhole(seen, startedAt, scannedAt)
    local count = 0
    for _ in pairs(seen) do count = count + 1 end

    local db = ns.db or {}
    local key = ns.Config and ns.Config.GetRealmKey and ns.Config:GetRealmKey() or "?"
    db.sweepSeenByRealm = db.sweepSeenByRealm or {}
    db.sweepRefusedByRealm = db.sweepRefusedByRealm or {}

    local last = db.sweepSeenByRealm[key]
    if not last then
        last = 0
        for _, record in pairs(self:GetTable()) do
            if (record.quantity or 0) > 0 or record.min or record.rivalMin or record.ownMin then
                last = last + 1
            end
        end
    end

    if count < last / 2 then
        local refused = db.sweepRefusedByRealm[key]
        local agrees = refused and math.abs(count - refused) <= refused * 0.1
        if not agrees then
            db.sweepRefusedByRealm[key] = count
            return 0, ("the scan saw %d items against %d last time"):format(count, last)
        end
    end

    db.sweepSeenByRealm[key] = count
    db.sweepRefusedByRealm[key] = nil
    return self:ClearMissing(seen, startedAt, scannedAt)
end

--- Commit a whole scan at once: { [itemID] = { {unitPrice, quantity}, ... } }.
-- Returns the number of items recorded.
function Prices:CommitScan(observations, scannedAt)
    scannedAt = scannedAt or time()

    local recorded = 0
    for itemID, listings in pairs(observations) do
        local marketValue, minBuyout, quantity, rivalMin, ownMin, ignoredLow =
            self:Summarise(listings, self:GetValue(itemID, "market"))
        if marketValue then
            self:Record(itemID, marketValue, minBuyout, quantity, scannedAt, rivalMin, ownMin, ignoredLow)
            recorded = recorded + 1
        end
    end

    self:SetLastFullScan(scannedAt)
    return recorded
end

--------------------------------------------------------------------------------
-- Reading
--------------------------------------------------------------------------------

function Prices:Get(itemID)
    return self:GetTable()[itemID]
end

--- The cheapest posting at the last look, yours included, leaving out a lone
--- one far below the rest (see IsLoneLow). nil when nothing was listed.
--
-- The one reading of "what does it cost" that material cost, the tooltip and
-- the Enchanting tab share, so a single troll listing cannot make a craft
-- look cheap to make in one place and not in another. Two or more low
-- listings are a real price and count.
function Prices.LowestListed(record)
    if type(record) ~= "table" then return nil end

    local lowest = record.rivalMin
    if record.ownMin and (not lowest or record.ownMin < lowest) then lowest = record.ownMin end
    if not lowest and not record.ignoredLow then lowest = record.min end
    return lowest
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
    elseif which == "lowest" then
        -- The cheapest posting, leaving out a lone one far below the rest.
        -- With nothing listed at the last look, the market value is the best
        -- there is.
        return Prices.LowestListed(record) or record.market
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
-- Favourites
--------------------------------------------------------------------------------

-- Asked 2026-10-06 (Voldar): star the items you keep an eye on, like Spider
-- Silk, and show only those on the Prices tab. Kept for the whole account in
-- `favouritePrices`, by item, with the item's name so a search still finds
-- one the game has not loaded. Separate from the price table, so a price
-- pruned for age never takes a favourite with it.

function Prices:IsFavourite(itemID)
    return itemID ~= nil and ns.db ~= nil and type(ns.db.favouritePrices) == "table"
        and ns.db.favouritePrices[itemID] ~= nil
end

--- Star an item (on = true) or take its star off (false).
function Prices:SetFavourite(itemID, on, name)
    if not ns.db or not itemID then return end
    if type(ns.db.favouritePrices) ~= "table" then ns.db.favouritePrices = {} end

    if on then
        if type(name) ~= "string" or name == "" then
            name = ns.db.favouritePrices[itemID]
            if type(name) ~= "string" then name = true end
        end
        ns.db.favouritePrices[itemID] = name
    else
        ns.db.favouritePrices[itemID] = nil
    end
end

--- itemID -> saved name (or true when none was known).
function Prices:GetFavourites()
    return ns.db and type(ns.db.favouritePrices) == "table" and ns.db.favouritePrices or {}
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
        ns.Warn(("removed %d price(s) and %d figure(s) above %s, which nobody could pay"):format(
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

ns.RegisterCommand("price", "<item link or name>: what the auction house says", function(args)
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
        ns.Print(("no auction data for %s. Run |cffc8a44d/bts scan|r at the auction house")
            :format(Util.GetItemLabel(itemID)))

        -- There may still be a price to give: something this account can make
        -- is valued off its materials until a scan finds a real one. Asked of
        -- the chooser, so this cannot quote a different number from the one
        -- the Sell tab would list at.
        local estimate, basis, why = ns.Profit:ChoosePostPrice(itemID)

        if estimate and basis == "derived" then
            ns.PrintRaw(("  |c%syou would list at %s (an estimate, not a market price)|r"):format(
                ns.COLORS.warn, Util.FormatMoney(estimate)))
            if why then ns.PrintRaw(("    %s"):format(why)) end
        end
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
    else
        -- No rival on record. Asked of the chooser for the same reason as
        -- above: this must not drift from the price the Sell tab would use.
        local postPrice, basis, why = ns.Profit:ChoosePostPrice(itemID)

        if ns.Prices:HoldsLowest(itemID) then
            ns.PrintRaw(("  |c%syou hold the lowest listing|r"):format(ns.COLORS.profit))
        end

        if postPrice then
            ns.PrintRaw(("  no rival listed   you would post at %s (%s)"):format(
                Util.FormatMoney(postPrice), basis or "no price"))
            if why then ns.PrintRaw(("    %s"):format(why)) end
        end
    end
    ns.PrintRaw(("  seen %s over %d scan(s)"):format(
        Util.FormatAgeAgo(ns.Prices:GetAge(itemID)), record.scans or 0))
    ns.PrintRaw(("  confidence %d%%%s   stock moving %s"):format(
        math.floor(confidence * 100), reason and (" (" .. reason .. ")") or "",
        liquidity and ("%d%%"):format(math.floor(liquidity * 100)) or "unknown"))
end)
