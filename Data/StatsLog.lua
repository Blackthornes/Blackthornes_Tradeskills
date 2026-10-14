-- Blackthornes Tradeskills -- Data/StatsLog.lua
-- What the Stats tab needs that nothing else keeps.
--
-- The owner asked (2026-10-14) for a Stats tab: one item at a time, in
-- charts. Most of it comes from what is already kept (the price graph's
-- hours, the mail ledger, the price table). Three things were not:
--
--   statsDays[realm][itemID]     day, cheapest, sold: one triple a day for
--                                90 days, so the tab can look back further
--                                than the seven days the graph keeps
--   statsSellers[realm][itemID]  t, sellers, top seller's share, your share:
--                                one reading a full scan, the last 12. Only
--                                how many sell it, never who.
--   statsPosts[realm][itemID]    when your listings of it went up, oldest
--                                first, so a sale can say how long it took
--   statsSellTimes[realm][itemID] { under 2h, 2 to 8h, 8 to 24h, longer }
--                                how long your listings took to sell
--   statsCheered[realm][itemID]  the week its best week was last cheered
--
-- Only the items the price graph keeps (PriceHistory:IsTracked: what the
-- account crafts or crafts with, and starred items), so a full scan of the
-- whole auction house does not fill the saved file. Never rename any of
-- these. Losing them costs only the charts, which start again.

local _, ns = ...

local StatsLog = ns.NewModule("StatsLog")

local DAY = 24 * 3600

StatsLog.KEEP_DAYS = 90
StatsLog.KEEP_SELLERS = 12
StatsLog.KEEP_POSTS = 40
-- A listing put up longer ago than this has sold, expired or been
-- cancelled, and its mail read or gone back; it is let go.
StatsLog.POST_KEEP = 31 * DAY
-- The auction house's mail stays this many days; daysLeft counts down
-- from here, so it says when a sale happened.
StatsLog.MAIL_DAYS = 30
-- Where a sale's time falls: under 2 hours, under 8, under 24, longer.
StatsLog.BUCKETS = { 2 * 3600, 8 * 3600, 24 * 3600 }

-- Moves whenever anything here changes, so the tab redraws only then.
StatsLog.version = 0

local function Moved()
    StatsLog.version = StatsLog.version + 1
end

--- The realm's table under `root`, made when `create` is set.
local function RealmTable(root, create)
    local db = ns.db
    if not db or not ns.Config then return nil end

    if type(db[root]) ~= "table" then
        if not create then return nil end
        db[root] = {}
    end

    local key = ns.Config:GetRealmKey()
    if not key then return nil end
    local realm = db[root][key]
    if type(realm) ~= "table" then
        if not create then return nil end
        realm = {}
        db[root][key] = realm
    end
    return realm
end

StatsLog.RealmTable = RealmTable

local function Tracked(itemID)
    if not itemID then return false end
    if not ns.PriceHistory then return true end
    return ns.PriceHistory:IsTracked(itemID)
end

local function Number(value)
    return type(value) == "number" and value == value and value or nil
end

--------------------------------------------------------------------------------
-- Ninety days
--------------------------------------------------------------------------------

--- Note a scan's cheapest price and the day's sales so far.
-- @param cheapest copper, the cheapest listing the scan saw (nil when none)
-- @param sold     how many left the auction house today by the scans, or nil
function StatsLog:NoteDay(itemID, cheapest, sold, at)
    at = Number(at) or time()
    cheapest, sold = Number(cheapest), Number(sold)
    if cheapest and cheapest <= 0 then cheapest = nil end
    if not cheapest and not sold then return end
    if not Tracked(itemID) then return end

    local realm = RealmTable("statsDays", true)
    if not realm then return end
    local list = realm[itemID]
    if type(list) ~= "table" then
        list = {}
        realm[itemID] = list
    end

    local day = math.floor(at / DAY)
    local count = #list
    local lastDay = count >= 3 and list[count - 2] or nil

    if lastDay and lastDay > day then return end

    if lastDay == day then
        -- The cheapest of the day, and the newest count of its sales.
        local had = list[count - 1]
        if cheapest and (had == 0 or cheapest < had) then list[count - 1] = math.floor(cheapest + 0.5) end
        if sold then list[count] = math.max(list[count] or 0, math.floor(sold)) end
    else
        list[count + 1] = day
        list[count + 2] = cheapest and math.floor(cheapest + 0.5) or 0
        list[count + 3] = sold and math.floor(sold) or 0
    end

    -- Let go of days past the keep.
    local oldest = day - self.KEEP_DAYS + 1
    local drop = 0
    while list[drop * 3 + 1] and list[drop * 3 + 1] < oldest do drop = drop + 1 end
    if drop > 0 then
        local total = #list
        for index = 1, total - drop * 3 do list[index] = list[index + drop * 3] end
        for index = total, total - drop * 3 + 1, -1 do list[index] = nil end
    end

    Moved()
end

--- The days kept, oldest first: { day, cheapest (nil when none listed),
--- sold }. `day` is time() / 86400, rounded down.
function StatsLog:GetDays(itemID)
    local realm = RealmTable("statsDays")
    local list = realm and realm[itemID]
    local out = {}
    if type(list) ~= "table" then return out end

    for index = 1, #list - 2, 3 do
        local day, cheapest, sold = list[index], list[index + 1], list[index + 2]
        if type(day) == "number" then
            out[#out + 1] = { day = day, cheapest = (Number(cheapest) or 0) > 0 and cheapest or nil,
                sold = Number(sold) or 0 }
        end
    end
    return out
end

--------------------------------------------------------------------------------
-- Who sells it
--------------------------------------------------------------------------------

--- Count the sellers in one item's listings from a full scan. Each listing
--- may carry `seller`, a name the scan read, used here to count and then
--- dropped: no name is kept. Nothing is noted when the scan gave no names.
function StatsLog:NoteSellers(itemID, listings, at)
    if type(listings) ~= "table" or #listings == 0 then return end
    if not Tracked(itemID) then return end

    local by, total, yours, named = {}, 0, 0, false
    for _, listing in ipairs(listings) do
        local quantity = Number(listing.quantity) or 1
        total = total + quantity
        if listing.isOwn then
            yours = yours + quantity
            by["\1you"] = (by["\1you"] or 0) + quantity
            named = true
        elseif type(listing.seller) == "string" and listing.seller ~= "" then
            by[listing.seller] = (by[listing.seller] or 0) + quantity
            named = true
        end
    end
    if not named or total <= 0 then return end

    local sellers, top = 0, 0
    for _, quantity in pairs(by) do
        sellers = sellers + 1
        if quantity > top then top = quantity end
    end

    local realm = RealmTable("statsSellers", true)
    if not realm then return end
    local list = realm[itemID]
    if type(list) ~= "table" then
        list = {}
        realm[itemID] = list
    end

    list[#list + 1] = math.floor(Number(at) or time())
    list[#list + 1] = sellers
    list[#list + 1] = math.floor(top / total * 100 + 0.5)
    list[#list + 1] = math.floor(yours / total * 100 + 0.5)

    while #list > self.KEEP_SELLERS * 4 do
        for _ = 1, 4 do table.remove(list, 1) end
    end

    Moved()
end

--- The readings kept, oldest first: { t, sellers, top, yours } with the
--- shares in whole percent.
function StatsLog:GetSellers(itemID)
    local realm = RealmTable("statsSellers")
    local list = realm and realm[itemID]
    local out = {}
    if type(list) ~= "table" then return out end

    for index = 1, #list - 3, 4 do
        out[#out + 1] = { t = list[index], sellers = list[index + 1],
            top = list[index + 2], yours = list[index + 3] }
    end
    return out
end

--------------------------------------------------------------------------------
-- How fast yours sell
--------------------------------------------------------------------------------

--- Your listings of an item went up (Logic/Posting.lua, once confirmed).
function StatsLog:NotePosted(itemID, count, at)
    count = math.floor(Number(count) or 0)
    if count <= 0 or not Tracked(itemID) then return end
    at = math.floor(Number(at) or time())

    local realm = RealmTable("statsPosts", true)
    if not realm then return end
    local list = realm[itemID]
    if type(list) ~= "table" then
        list = {}
        realm[itemID] = list
    end

    for _ = 1, math.min(count, self.KEEP_POSTS) do list[#list + 1] = at end

    while #list > self.KEEP_POSTS do table.remove(list, 1) end
    while list[1] and at - list[1] > self.POST_KEEP do table.remove(list, 1) end
end

--- Take the oldest posting at or before `at` off the list; its time, or nil.
local function TakePosting(itemID, at)
    local realm = RealmTable("statsPosts")
    local list = realm and realm[itemID]
    if type(list) ~= "table" then return nil end

    for index = 1, #list do
        local posted = list[index]
        if type(posted) == "number" and posted <= at then
            table.remove(list, index)
            if #list == 0 then realm[itemID] = nil end
            return posted
        end
    end
    return nil
end

--- Which bucket a sale `seconds` after its posting falls in, 1 to 4.
function StatsLog.Bucket(seconds)
    for index, limit in ipairs(StatsLog.BUCKETS) do
        if seconds < limit then return index end
    end
    return #StatsLog.BUCKETS + 1
end

--- A new mail ledger entry (Data/Mail.lua): a sale is matched to your
--- oldest posting of the item and its time counted; an expiry or a
--- cancellation only takes the posting off the list.
-- @param entry the ledger entry just written ({ t, kind, itemID })
-- @param mail  the mail it came from, for daysLeft
function StatsLog:NoteLedger(entry, mail)
    if type(entry) ~= "table" or not entry.itemID then return end
    local readAt = Number(entry.t) or time()

    -- When it happened, from how long the mail has left.
    local at = readAt
    local daysLeft = type(mail) == "table" and Number(mail.daysLeft)
    if daysLeft then
        at = math.min(readAt, readAt - math.floor((self.MAIL_DAYS - daysLeft) * DAY + 0.5))
    end

    if entry.kind ~= "sold" then
        TakePosting(entry.itemID, readAt)
        return
    end

    local posted = TakePosting(entry.itemID, at)
    if not posted then return end

    local seconds = at - posted
    if seconds < 0 or seconds > 3 * DAY then return end

    local realm = RealmTable("statsSellTimes", true)
    if not realm then return end
    local counts = realm[entry.itemID]
    if type(counts) ~= "table" then
        counts = { 0, 0, 0, 0 }
        realm[entry.itemID] = counts
    end
    local bucket = self.Bucket(seconds)
    counts[bucket] = (Number(counts[bucket]) or 0) + 1

    Moved()
end

--- { under 2h, 2 to 8h, 8 to 24h, longer }, or nil when none were timed.
function StatsLog:GetSellTimes(itemID)
    local realm = RealmTable("statsSellTimes")
    local counts = realm and realm[itemID]
    if type(counts) ~= "table" then return nil end

    local out, any = {}, false
    for index = 1, #self.BUCKETS + 1 do
        out[index] = Number(counts[index]) or 0
        if out[index] > 0 then any = true end
    end
    return any and out or nil
end

--------------------------------------------------------------------------------
-- The best week's cheer
--------------------------------------------------------------------------------

--- Whether the best week was already cheered for this item this `week`.
function StatsLog:Cheered(itemID, week)
    local realm = RealmTable("statsCheered")
    return realm ~= nil and realm[itemID] == week
end

function StatsLog:SetCheered(itemID, week)
    local realm = RealmTable("statsCheered", true)
    if realm then realm[itemID] = week end
end
