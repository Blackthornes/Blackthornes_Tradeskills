-- Blackthornes Tradeskills -- Data/Prices.lua
-- The price database: what an item costs, what it is worth, and how confident
-- we are about either number.
--
-- Everything here is derived from our own scans. There is no external data
-- source, so the honest thing to do is track how thin the evidence is and
-- surface that alongside the number, rather than presenting a single
-- authoritative-looking price built from three listings.

local _, ns = ...
local L = ns.L or setmetatable({ Format = string.format }, { __index = function(_, key) return key end })

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

-- How many price steps of the book are kept for buying many at once. A craft
-- that needs 20 of something cannot all be bought at the cheapest listing
-- when only 3 are listed there (a player asked, the owner agreeing 2026-10-11),
-- so the cost of N walks up these steps. A handful covers a run of crafts;
-- past the last step, what is left is priced at it.
local LADDER_STEPS = 5

Prices.LADDER_STEPS = LADDER_STEPS

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

--- The cheap end of the book as it can be bought: other sellers' listings,
--- cheapest first, one step per price, kept flat as { price, count, price,
--- count, ... } so the saved data stays small. Your own listings cannot be
--- bought, so they are left out.
-- @param listings sorted cheapest first, the lone low listing already out
local function BuildLadder(listings)
    local ladder = {}
    for i = 1, #listings do
        local listing = listings[i]
        if not listing.isOwn then
            local n = #ladder
            local quantity = listing.quantity or 1
            if n > 0 and ladder[n - 1] == listing.unitPrice then
                ladder[n] = ladder[n] + quantity
            elseif n >= LADDER_STEPS * 2 then
                break
            else
                ladder[n + 1] = listing.unitPrice
                ladder[n + 2] = quantity
            end
        end
    end
    return ladder
end

--- Collapse one item's listings into a single representative unit price.
-- @param listings array of { unitPrice = copper, quantity = n, isOwn = bool }
-- @param reference the item's stored market value, when known. Only used to
--   decide whether the cheapest listing is a lone low one.
-- @return marketValue, minBuyout, totalQuantity, rivalMin, ownMin, ignoredLow,
--   ladder
--   ignoredLow is the price of a lone low listing left out of rivalMin and
--   market value, or nil. ladder is the first price steps of other sellers'
--   listings (BuildLadder), empty when none are listed.
function Prices:Summarise(listings, reference)
    if not listings or #listings == 0 then
        return nil, nil, 0, nil, nil, nil, nil
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
    local ladder = BuildLadder(listings)

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
        return minBuyout, minBuyout, totalQuantity, rivalMin, ownMin, ignoredLow, ladder
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

    return math.floor(marketValue + 0.5), minBuyout, totalQuantity, rivalMin, ownMin, ignoredLow, ladder
end

--------------------------------------------------------------------------------
-- Recording
--------------------------------------------------------------------------------

function Prices:GetTable()
    return ns.Config:GetPriceTable()
end

-- Which item each recent change was about, so a list can redo only the rows
-- those items fill rather than rebuild itself for one price (the owner's
-- smooth play rule). Keyed by the change's number: an item ID, or false for
-- a change that touched no one item. Only the last TOUCH_KEPT are kept.
Prices.touched = {}
local TOUCH_KEPT = 32

--- Count a change to the prices, and remember which item it was about.
function Prices:Touch(itemID)
    Prices.changes = (Prices.changes or 0) + 1
    Prices.touched[Prices.changes] = itemID or false
    Prices.touched[Prices.changes - TOUCH_KEPT] = nil
end

--- The items changed since change number `since`, as { [itemID] = true },
--- or nil when that cannot be told: too many changes, one that touched no
--- one item, or one counted without Touch (a guild's prices). nil means
--- build again from scratch.
function Prices:TouchedSince(since)
    local now = Prices.changes or 0
    if type(since) ~= "number" or since > now or now - since > TOUCH_KEPT then return nil end
    local items = {}
    for change = since + 1, now do
        local itemID = Prices.touched[change]
        if not itemID then return nil end
        items[itemID] = true
    end
    return items
end

--- Is this a ladder that can be walked: pairs of a credible price and a
--- count above 0, cheapest first?
local function ValidLadder(ladder)
    if type(ladder) ~= "table" or #ladder < 2 or #ladder % 2 ~= 0 then return false end
    local last = -1
    for i = 1, #ladder, 2 do
        local price, count = ladder[i], ladder[i + 1]
        if type(price) ~= "number" or not Prices.IsCredible(price) or price < last then return false end
        if type(count) ~= "number" or count <= 0 then return false end
        last = price
    end
    return true
end

Prices.ValidLadder = ValidLadder

--- Fold one item's scan result into the database.
-- @param ladder the book's first price steps (Summarise), when this reading
--   saw the listings. nil from a reading that saw only the cheapest price (a
--   browse row): the ladder on record is kept while its first step is still
--   the cheapest rival, and dropped when it is not.
function Prices:Record(itemID, marketValue, minBuyout, quantity, scannedAt, rivalMin, ownMin, ignoredLow, ladder)
    -- Lets a list know prices moved without comparing every record.
    Prices:Touch(itemID)

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

    if ladder ~= nil then
        record.ladder = ValidLadder(ladder) and ladder or nil
    elseif record.ladder and not (rivalMin and record.ladder[1] == rivalMin) then
        record.ladder = nil
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

    -- The hour by hour graph keeps the cheapest posting, as buying sees it.
    if ns.PriceHistory then
        ns.PriceHistory:Note(itemID, Prices.LowestListed(record), scannedAt)
        ns.PriceHistory:NoteListed(itemID, quantity, scannedAt)
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
    Prices:Touch(itemID)

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
    record.ladder = nil
    record.quantity = 0
    record.seen = scannedAt
    record.scans = (record.scans or 0) + 1

    record.history = record.history or {}

    local history = record.history
    history[#history + 1] = { t = scannedAt, m = record.market, q = 0 }
    while #history > MAX_HISTORY do
        table.remove(history, 1)
    end

    -- Sold out counts on the volume bars: none listed this hour.
    if ns.PriceHistory then ns.PriceHistory:NoteListed(itemID, 0, scannedAt) end

    return record
end

--- You bought from this item's listings: what you bought is no longer there.
--
-- A player found the Disenchanting tab still offering an item at the price
-- of the listing they had just bought, the last one at that price, until
-- the next scan. The client may or may not show the listings again after a
-- buy, so the record is put right here, from what was paid.
--
-- The units bought come off the cheapest on record, and anything on record
-- under the price paid goes too: you would have bought the cheapest, so a
-- cheaper one had already gone. The rest of the ladder stays; with no ladder to
-- say what comes next, the cheapest rival is unknown (nil) until the next
-- look, so nothing is offered at a price nobody is selling at. No price
-- history is written: nothing was scanned, and your own buy says nothing
-- about Demand.
--
-- @param unitPrice what one listing's unit cost, or nil for a commodity,
--   where one buy takes the cheapest units whatever their price
-- @param quantity  how many were bought
-- @param askedAt   time() the buy was asked for. A record read after that
--   already saw the book without it, and is left alone.
-- @return true when the record changed
function Prices:NoteBought(itemID, unitPrice, quantity, askedAt)
    local record = itemID and self:GetTable()[itemID]
    if type(record) ~= "table" then return false end
    if askedAt and (record.seen or 0) > askedAt then return false end

    quantity = math.max(1, math.floor(tonumber(quantity) or 1))
    local paid = tonumber(unitPrice)

    local cheapest = record.rivalMin
    if record.ignoredLow and (not cheapest or record.ignoredLow < cheapest) then cheapest = record.ignoredLow end
    if not cheapest then return false end
    if paid and paid < cheapest - 1 then return false end
    local unitPrice = paid or cheapest

    local left = quantity

    -- The lone low listing first: it is the cheapest of all, and one unit.
    if record.ignoredLow and record.ignoredLow <= unitPrice + 1 then
        record.ignoredLow = nil
        left = left - 1
    end

    if ValidLadder(record.ladder) then
        local kept = {}
        for i = 1, #record.ladder, 2 do
            local price, count = record.ladder[i], record.ladder[i + 1]
            -- Under the price paid had already gone (a copper either way is
            -- the same listing: a stack's unit price is rounded). The units
            -- bought come off the cheapest of the rest.
            if paid and price < paid - 1 then
                count = 0
            elseif left > 0 then
                local take = math.min(left, count)
                count, left = count - take, left - take
            end
            if count > 0 then
                kept[#kept + 1] = price
                kept[#kept + 1] = count
            end
        end
        record.ladder = #kept >= 2 and kept or nil
        record.rivalMin = record.ladder and record.ladder[1] or nil
    else
        record.ladder = nil
        if left > 0 and record.rivalMin and record.rivalMin <= unitPrice + 1 then record.rivalMin = nil end
    end

    record.quantity = math.max(0, (tonumber(record.quantity) or 0) - quantity)

    local min = record.rivalMin
    for _, price in ipairs({ record.ignoredLow or false, record.ownMin or false }) do
        if price and (not min or price < min) then min = price end
    end
    record.min = min

    self:Touch(itemID)
    return true
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
            return 0, L.Format("the scan saw %d items against %d last time", count, last)
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
        local marketValue, minBuyout, quantity, rivalMin, ownMin, ignoredLow, ladder =
            self:Summarise(listings, self:GetValue(itemID, "market"))
        if marketValue then
            self:Record(itemID, marketValue, minBuyout, quantity, scannedAt, rivalMin, ownMin, ignoredLow, ladder)
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

--- What buying one costs on the auction house now: the cheapest posting at
--- the last look (LowestListed, or a lone low listing when it is all there
--- is). A record that says nothing is listed answers nil and true, so a
--- list can show it blank rather than at its average (a player asked,
--- 2026-10-11, for the Waylaid crate and writ columns). An item never read
--- at all falls back to GetValue's "lowest", the best guess there is.
-- @return copper or nil, and true when none are listed
function Prices:ListedNow(itemID)
    local record = itemID and self:GetTable()[itemID]
    if type(record) ~= "table" then return self:GetValue(itemID, "lowest"), false end

    local lowest = Prices.LowestListed(record) or record.ignoredLow
    if lowest then return lowest, false end
    return nil, true
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
--
-- A price the player set on the Prices tab (see My prices below) wins over
-- all but "rival": "use" replaces the scanned price, "floor" lifts it.
-- Rival stays the auction house's own, since it is the price to undercut.
-- An item nobody has priced may take TradeSkillMaster's (Logic/TSMPrices.lua),
-- then Auctionator's (Logic/AuctionatorPrices.lua).
-- GetScanValue answers from the scans alone.
function Prices:GetValue(itemID, which)
    local scanned = self:GetScanValue(itemID, which)
    if which == "rival" then return scanned end

    -- Guildmates' prices (Logic/GuildPrices.lua, off unless the player turns
    -- it on) fill a gap: an item never priced here, or one whose price has
    -- gone stale while theirs is newer. A fresh scan of your own always wins.
    -- Only asked when it could be used: their answer is sorted out of every
    -- guildmate's, and prices are read many times a redraw.
    local guild = ns.GuildPrices
    if guild and guild.IsOn and guild:IsOn() and (not scanned or self:IsStale(itemID)) then
        local shared, sharedAt = guild:GetValue(itemID, which)
        if shared then
            local record = self:GetTable()[itemID]
            local seen = type(record) == "table" and record.seen or 0
            if not scanned or (self:IsStale(itemID) and sharedAt > seen) then scanned = shared end
        end
    end

    -- TradeSkillMaster's price (Logic/TSMPrices.lua, on unless unticked)
    -- only for an item neither you nor your guildmates have priced.
    if not scanned then
        local tsm = ns.TSMPrices
        if tsm and tsm.GetValue then
            scanned = tsm:GetValue(itemID, which)
            if scanned and tsm.Used then tsm:Used() end
        end
    end
    -- Then Auctionator's (Logic/AuctionatorPrices.lua, on unless unticked).
    if not scanned then
        local auctionator = ns.AuctionatorPrices
        if auctionator and auctionator.GetValue then
            scanned = auctionator:GetValue(itemID, which)
            if scanned and auctionator.Used then auctionator:Used() end
        end
    end

    local mine, mode = self:GetMine(itemID)
    if not mine then return scanned end

    if mode == "use" then return mine end
    if not scanned or scanned < mine then return mine end
    return scanned
end

--- What the scans alone say an item is worth, leaving out any price the
--- player set. Same `which` as GetValue.
function Prices:GetScanValue(itemID, which)
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

--------------------------------------------------------------------------------
-- Buying many
--------------------------------------------------------------------------------

--- What buying `count` costs walking up a ladder, after the first `skip`
--- units (already bought since it was read) are passed over. Past the last
--- step, the rest are priced at it. Each step is lifted to `floor` when one
--- is given.
local function Walk(ladder, count, skip, floor)
    local total, left, last = 0, count, nil
    skip = skip or 0
    for i = 1, #ladder, 2 do
        local price, units = ladder[i], ladder[i + 1]
        if floor and price < floor then price = floor end
        last = price
        if skip >= units then
            skip = skip - units
        else
            local take = math.min(units - skip, left)
            skip = 0
            total = total + price * take
            left = left - take
            if left <= 0 then return total end
        end
    end
    return total + last * left
end

Prices.Walk = Walk

--- What buying `count` of an item costs on the auction house, going up the
--- listings from the last scan rather than paying the cheapest price for all
--- of them.
--
-- Answers as GetValue(itemID, "lowest") does for one: the player's own "use"
-- price is the price of every one, a "floor" lifts every step, and with no
-- book to walk (a stale scan, a guildmate's price, one browse row) it is that
-- one price times the count.
--
-- @param skip units bought since the scan, whose listings are gone
-- @param record a record to read instead of the one on file (CostBeforeLook)
-- @return copper, or nil when the item has no auction price
function Prices:GetCostFor(itemID, count, skip, record)
    count = math.floor(tonumber(count) or 0)
    if count <= 0 then return 0 end

    local mine, mode = self:GetMine(itemID)
    if mine and mode == "use" then return mine * count end

    local current = record == nil
    record = record or self:GetTable()[itemID]
    local ladder = type(record) == "table" and record.ladder
    local stale = type(record) ~= "table" or not record.seen
        or time() - record.seen > (ns.Config:Get("staleAfterSeconds") or (48 * 3600))
    if ValidLadder(ladder) and not stale then
        return Walk(ladder, count, skip, mode == "floor" and mine or nil)
    end

    local unit
    if current then
        unit = self:GetValue(itemID, "lowest")
    else
        unit = Prices.LowestListed(record) or (type(record) == "table" and record.market) or nil
        if unit and mine and mode == "floor" and unit < mine then unit = mine end
    end
    return unit and unit * count or nil
end

-- The book as it stood before the player looked an item up at this visit to
-- the auction house, by item. The player's own search records the listings
-- they are about to buy from, so what the shopping list said beforehand
-- would be gone by the time they pay. Not saved; emptied each visit.
Prices.beforeLook = {}

--- Keep the item's book as it is, once a visit, before a search of the
--- player's own records over it.
function Prices:KeepBeforeLook(itemID)
    if not itemID or self.beforeLook[itemID] ~= nil then return end
    local record = self:GetTable()[itemID]
    if type(record) ~= "table" then
        self.beforeLook[itemID] = false
        return
    end
    self.beforeLook[itemID] = {
        ladder = record.ladder, rivalMin = record.rivalMin, ownMin = record.ownMin,
        min = record.min, ignoredLow = record.ignoredLow, market = record.market,
        seen = record.seen,
    }
end

function Prices:ForgetBeforeLook()
    self.beforeLook = {}
end

--- What buying `count` was estimated at before the player looked it up:
--- the book kept by KeepBeforeLook, else the one on file.
-- @param boughtSince function(seen) -> units bought since a scan at `seen`
function Prices:CostBeforeLook(itemID, count, boughtSince)
    local kept = self.beforeLook[itemID]
    local record = kept or self:GetTable()[itemID]
    local seen = type(record) == "table" and record.seen or nil
    local skip = (seen and boughtSince) and boughtSince(seen) or 0
    return self:GetCostFor(itemID, count, skip, kept or nil)
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

-- Scans closer together than this are one look at the book for Demand, so
-- scanning every minute neither waters the reading down nor lets listings
-- that come and go inflate it.
local SALES_GAP = 15 * 60

-- Time the readings must span before the stock's movement says anything.
local SALES_MIN_SPAN = 3600

Prices.SALES_GAP = SALES_GAP
Prices.SALES_MIN_SPAN = SALES_MIN_SPAN

--- Share of an item's listed stock that goes per day, 0..1, however often it
-- was scanned.
--
-- GetLiquidity counts per scan, so the same item reads quieter the more often
-- it is scanned. This one spaces the readings by the clock: looks less than
-- SALES_GAP apart count once, the drops in stock are added up, and the total is
-- divided by the average stock and by the days the readings span. An empty
-- answer is left out (it cannot say whether the stock sold or expired), and
-- nothing is answered for under SALES_MIN_SPAN of readings. Like GetLiquidity
-- it under-reports, because a restock hides sales.
-- @return nil when there is not enough time or stock to go on
function Prices:GetSalesPerDay(itemID)
    local record = self:GetTable()[itemID]
    if not record or type(record.history) ~= "table" then return nil end

    local kept = {}
    for _, point in ipairs(record.history) do
        local q = point.q
        if type(point.t) == "number" and type(q) == "number" and q > 0 then
            local last = kept[#kept]
            if not last or point.t - last.t >= SALES_GAP then
                kept[#kept + 1] = point
            end
        end
    end

    if #kept < 2 then return nil end

    local span = kept[#kept].t - kept[1].t
    if span < SALES_MIN_SPAN then return nil end

    local drops, stock = 0, 0
    for i = 2, #kept do
        local previous, current = kept[i - 1].q, kept[i].q
        if current < previous then drops = drops + (previous - current) end
        stock = stock + previous
    end

    if stock == 0 then return nil end

    local average = stock / (#kept - 1)
    return Util.Clamp(drops / average / (span / 86400), 0, 1)
end

--- How much to trust this item's price: scan count, recency and depth.
-- Returns 0..1 and a short reason for the weakest factor.
-- Above this, a component is not worth calling out as a weakness.
local WEAKNESS_THRESHOLD = 0.8

function Prices:GetConfidence(itemID)
    local record = self:GetTable()[itemID]
    if not record then return 0, L["never seen"] end

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
        reason = L["stale data"]
    elseif depthScore == weakest then
        reason = L["few listed"]
    else
        reason = L["few scans"]
    end

    return score, reason
end

--------------------------------------------------------------------------------
-- Favourites
--------------------------------------------------------------------------------

-- Asked 2026-10-06 (a player): star the items you keep an eye on, like Spider
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

    -- A starred item keeps an hour by hour price history from the next scan.
    if ns.PriceHistory then ns.PriceHistory:Retrack() end
end

--- itemID -> saved name (or true when none was known).
function Prices:GetFavourites()
    return ns.db and type(ns.db.favouritePrices) == "table" and ns.db.favouritePrices or {}
end

--------------------------------------------------------------------------------
-- My prices
--------------------------------------------------------------------------------

-- Asked 2026-10-06 (a player): set your own price on an item. Two kinds:
--   "use"    this price instead of the auction price, everywhere: a reagent
--            you make for less than the auction house asks.
--   "floor"  the auction price, but never below this: a craft worth more
--            to you than the auction house is paying right now.
-- Kept per realm, like the price table, in `myPrices[realm][itemID] =
-- { price, mode, name }`. Never rename it. Apart from the price table, so
-- pruning old prices never takes a player's own price with it.

local MY_MODES = { use = true, floor = true }

local function MyPrices(create)
    if not ns.db then return nil end

    if type(ns.db.myPrices) ~= "table" then
        if not create then return nil end
        ns.db.myPrices = {}
    end

    local realmKey = ns.Config:GetRealmKey()
    local realm = ns.db.myPrices[realmKey]
    if type(realm) ~= "table" then
        if not create then return nil end
        realm = {}
        ns.db.myPrices[realmKey] = realm
    end
    return realm
end

--- The price the player set on an item, and its kind ("use" or "floor").
--- nil when none is set. A saved entry this cannot read is left alone.
function Prices:GetMine(itemID)
    local realm = itemID and MyPrices(false)
    local entry = realm and realm[itemID]
    if type(entry) ~= "table" then return nil end

    local price = tonumber(entry.price)
    if not price or price < 1 or not MY_MODES[entry.mode] then return nil end
    return math.floor(price), entry.mode
end

--- Set the player's price on an item. A price of nil or 0 clears it.
-- @return true when saved or cleared, false when the price was refused
function Prices:SetMine(itemID, price, mode, name)
    if not itemID then return false end
    price = tonumber(price)

    if not price or price < 1 then
        local realm = MyPrices(false)
        if realm and realm[itemID] ~= nil then
            realm[itemID] = nil
            Prices:Touch(itemID)
        end
        return true
    end

    if not Prices.IsCredible(price) then return false end
    if not MY_MODES[mode] then mode = "use" end

    local realm = MyPrices(true)
    if not realm then return false end

    local old = realm[itemID]
    if type(name) ~= "string" or name == "" then
        name = type(old) == "table" and type(old.name) == "string" and old.name or nil
    end

    realm[itemID] = { price = math.floor(price), mode = mode, name = name }
    Prices:Touch(itemID)
    return true
end

--- itemID -> { price, mode, name } for this realm.
function Prices:GetAllMine()
    return MyPrices(false) or {}
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
        ns.Warn(L.Format("removed %d price(s) and %d figure(s) above %s, which nobody could pay",
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

ns.RegisterCommand("price", L["<item link or name>: what the auction house says"], function(args)
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
        ns.Print(L["usage: /bts price <shift-clicked item, or exact item name>"])
        return
    end

    local record = ns.Prices:Get(itemID)
    if not record then
        ns.Print(L.Format("no auction data for %s. Run |cffc8a44d/bts scan|r at the auction house",
            Util.GetItemLabel(itemID)))

        -- There may still be a price to give: something this account can make
        -- is valued off its materials until a scan finds a real one. Asked of
        -- the chooser, so this cannot quote a different number from the one
        -- the Sell tab would list at.
        local estimate, basis, why = ns.Profit:ChoosePostPrice(itemID)

        if estimate and basis == "derived" then
            ns.PrintRaw(L.Format("  |c%syou would list at %s (an estimate, not a market price)|r",
                ns.COLORS.warn, Util.FormatMoney(estimate)))
            if why then ns.PrintRaw(("    %s"):format(why)) end
        end
        return
    end

    local confidence, reason = ns.Prices:GetConfidence(itemID)
    local liquidity = ns.Prices:GetLiquidity(itemID)

    ns.Print(Util.GetItemLabel(itemID))
    ns.PrintRaw(L.Format("  market %s   min %s   qty %d",
        Util.FormatMoney(record.market), Util.FormatMoney(record.min), record.quantity or 0))

    if record.rivalMin then
        -- Asked of the chooser rather than worked out again here, so this
        -- cannot drift from the price the Sell tab would actually use.
        local postPrice, basis, why = ns.Profit:ChoosePostPrice(itemID)

        ns.PrintRaw(L.Format("  cheapest rival %s   you would post at %s (%s)",
            Util.FormatMoney(record.rivalMin),
            Util.FormatMoney(postPrice or record.rivalMin),
            basis or L["no price"]))

        -- "match" on its own does not say whether undercutting was rejected
        -- on the numbers or never costed at all, and those want different
        -- things from you.
        if why then ns.PrintRaw(("    %s"):format(why)) end
    else
        -- No rival on record. Asked of the chooser for the same reason as
        -- above: this must not drift from the price the Sell tab would use.
        local postPrice, basis, why = ns.Profit:ChoosePostPrice(itemID)

        if ns.Prices:HoldsLowest(itemID) then
            ns.PrintRaw(L.Format("  |c%syou hold the lowest listing|r", ns.COLORS.profit))
        end

        if postPrice then
            ns.PrintRaw(L.Format("  no rival listed   you would post at %s (%s)",
                Util.FormatMoney(postPrice), basis or L["no price"]))
            if why then ns.PrintRaw(("    %s"):format(why)) end
        end
    end
    ns.PrintRaw(L.Format("  seen %s over %d scan(s)",
        Util.FormatAgeAgo(ns.Prices:GetAge(itemID)), record.scans or 0))
    ns.PrintRaw(L.Format("  confidence %d%%%s   stock moving %s",
        math.floor(confidence * 100), reason and (" (" .. reason .. ")") or "",
        liquidity and ("%d%%"):format(math.floor(liquidity * 100)) or L["unknown"]))
end)
