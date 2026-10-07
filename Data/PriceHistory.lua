-- Blackthornes Tradeskills -- Data/PriceHistory.lua
-- The cheapest price, hour by hour, for the items you craft and use.
--
-- Asked 2026-10-06 (Sullivan): a price graph with 24 Hours and 7 Day views,
-- and when in the day a material is cheapest to buy and a craft dearest to
-- sell. The price table keeps only twelve smoothed readings per item, which
-- can draw neither, so this keeps its own record beside it.
--
-- What is kept, per realm and faction, in `priceHistory[realm][itemID]`: a
-- flat list of hour, price pairs (hour = time() / 3600, rounded down), one
-- pair for each hour a scan saw the item, for seven days. Only items a
-- character on the account crafts or uses as a material, and starred items,
-- so a full scan of the whole auction house does not fill the saved file.
-- Never rename it. Nothing else reads or writes it, and losing it costs only
-- the graph, which the next scans start again.
--
-- The best times are only said when the scans cover enough of the day to
-- mean something: a player who always scans at 8pm has nothing to say about
-- 4am, and saying "cheapest at 8pm" from that would be a guess dressed up.

local _, ns = ...

local PriceHistory = ns.NewModule("PriceHistory")

local DAY = 24 * 3600
local KEEP_SECONDS = 7 * DAY

-- What the best times need before they are said: scans in this many
-- different hours of the day, on this many different days, and at least
-- two days' scans in each hour compared.
PriceHistory.NEED_HOURS = 8
PriceHistory.NEED_DAYS = 5

-- Under this spread between the cheapest and dearest hour, the price holds
-- all day and no hour is named.
PriceHistory.STEADY = 0.05

-- How often the list of items worth keeping is worked out again.
local TRACKED_REFRESH = 60

--------------------------------------------------------------------------------
-- Saved data
--------------------------------------------------------------------------------

local function RealmTable(create)
    local db = ns.db
    if not db then return nil end

    if type(db.priceHistory) ~= "table" then
        if not create then return nil end
        db.priceHistory = {}
    end

    local key = ns.Config:GetRealmKey()
    local realm = db.priceHistory[key]
    if type(realm) ~= "table" then
        if not create then return nil end
        realm = {}
        db.priceHistory[key] = realm
    end
    return realm
end

--------------------------------------------------------------------------------
-- Which items
--------------------------------------------------------------------------------

--- itemID -> true for everything a character on this account crafts, the
--- materials those crafts use, and starred items. Worked out at most once a
--- minute, since a full scan asks for every item it reads.
function PriceHistory:GetTracked()
    local now = time()
    if self.tracked and self.trackedAt and now - self.trackedAt < TRACKED_REFRESH then
        return self.tracked
    end

    local tracked = {}
    local db = ns.db

    if db and type(db.characters) == "table" then
        for _, character in pairs(db.characters) do
            if type(character) == "table" and type(character.recipes) == "table" then
                for _, recipe in pairs(character.recipes) do
                    if type(recipe) == "table" then
                        if recipe.outputItemID then tracked[recipe.outputItemID] = true end
                        for _, reagent in ipairs(type(recipe.reagents) == "table" and recipe.reagents or {}) do
                            if type(reagent) == "table" and reagent.itemID then
                                tracked[reagent.itemID] = true
                            end
                        end
                    end
                end
            end
        end
    end

    if db and type(db.favouritePrices) == "table" then
        for itemID in pairs(db.favouritePrices) do tracked[itemID] = true end
    end

    self.tracked, self.trackedAt = tracked, now
    return tracked
end

--- Forget the list, so a star or a new recipe counts on the next scan.
function PriceHistory:Retrack()
    self.tracked, self.trackedAt = nil, nil
end

function PriceHistory:IsTracked(itemID)
    return itemID ~= nil and self:GetTracked()[itemID] == true
end

--------------------------------------------------------------------------------
-- Recording
--------------------------------------------------------------------------------

--- Drop pairs older than seven days from the front of a list.
local function Trim(list, now)
    local oldest = math.floor((now - KEEP_SECONDS) / 3600)
    local drop = 0
    while list[drop * 2 + 1] and list[drop * 2 + 1] < oldest do
        drop = drop + 1
    end
    if drop == 0 then return end

    local count = #list
    for index = 1, count - drop * 2 do
        list[index] = list[index + drop * 2]
    end
    for index = count, count - drop * 2 + 1, -1 do
        list[index] = nil
    end
end

--- Note what an item cost at a scan. One pair an hour: a second scan in the
--- same hour replaces the first, so the newest price stands for the hour.
-- @param price copper, the cheapest listing the scan saw
function PriceHistory:Note(itemID, price, at)
    if not itemID or type(price) ~= "number" or price <= 0 or price ~= price then return end
    if not self:IsTracked(itemID) then return end

    at = at or time()
    local realm = RealmTable(true)
    if not realm then return end

    local list = realm[itemID]
    if type(list) ~= "table" then
        list = {}
        realm[itemID] = list
    end

    local hour = math.floor(at / 3600)
    local count = #list
    price = math.floor(price + 0.5)

    if count >= 2 and list[count - 1] == hour then
        list[count] = price
    elseif count >= 2 and list[count - 1] > hour then
        -- Older than the newest pair (a clock change, or a scan read late):
        -- left out rather than written out of order.
        return
    else
        list[count + 1] = hour
        list[count + 2] = price
    end

    Trim(list, at)
    PriceHistory.changes = (PriceHistory.changes or 0) + 1
end

--- A guildmate's price for an hour this account did not scan
--- (Logic/GuildPrices.lua). Put in its place in time; an hour that already
--- has a price, yours or a guildmate's, keeps it.
function PriceHistory:Fill(itemID, price, at)
    if not itemID or type(price) ~= "number" or price <= 0 or price ~= price then return end
    if type(at) ~= "number" or not self:IsTracked(itemID) then return end

    local now = time()
    if at > now + 3600 or now - at > KEEP_SECONDS then return end

    local realm = RealmTable(true)
    if not realm then return end
    local list = realm[itemID]
    if type(list) ~= "table" then
        list = {}
        realm[itemID] = list
    end

    local hour = math.floor(at / 3600)
    local position = #list + 1
    for index = 1, #list - 1, 2 do
        if list[index] == hour then return end
        if list[index] > hour then position = index break end
    end

    table.insert(list, position, math.floor(price + 0.5))
    table.insert(list, position, hour)
    Trim(list, now)
    PriceHistory.changes = (PriceHistory.changes or 0) + 1
end

--------------------------------------------------------------------------------
-- Reading
--------------------------------------------------------------------------------

--- The kept prices for an item, oldest first, as { t = time(), p = copper },
--- from `since` seconds ago until now (all seven days when not given).
function PriceHistory:GetPoints(itemID, since, now)
    now = now or time()
    local realm = RealmTable(false)
    local list = realm and itemID and realm[itemID]
    if type(list) ~= "table" then return {} end

    local from = since and (now - since) or (now - KEEP_SECONDS)
    local points = {}

    for index = 1, #list - 1, 2 do
        local hour, price = list[index], list[index + 1]
        if type(hour) == "number" and type(price) == "number" then
            local t = hour * 3600
            if t + 3600 > from and t <= now then
                points[#points + 1] = { t = t, p = price }
            end
        end
    end

    return points
end

--- An hour of the day as it reads on a clock: "4am", "12pm", "8pm".
function PriceHistory.HourText(hour)
    local suffix = hour < 12 and "am" or "pm"
    local twelve = hour % 12
    if twelve == 0 then twelve = 12 end
    return twelve .. suffix
end

--- When in the day an item is cheapest and dearest, from the last seven days.
--
-- Each price is compared with that day's own average, so a price falling all
-- week does not make the morning look cheap just because mornings came
-- later. Only days scanned in two or more hours count. An hour is compared
-- once it was scanned on two of those days.
--
-- @return a table:
--   ready      true when the scans cover enough of the day to say
--   hours      different hours of the day scanned (on counted days)
--   days       days counted
--   steady     ready, and no hour is more than STEADY from another
--   buyHour, buyBelow     cheapest hour (0..23), and how far under its
--                         day's average it runs (0.08 = 8%)
--   sellHour, sellAbove   dearest hour, and how far over
function PriceHistory:GetBestTimes(itemID, now)
    local points = self:GetPoints(itemID, KEEP_SECONDS, now)

    -- Group by the day on the player's clock.
    local byDay = {}
    for _, point in ipairs(points) do
        local stamp = date("*t", point.t)
        local dayKey = stamp.year * 10000 + stamp.month * 100 + stamp.day
        local day = byDay[dayKey]
        if not day then
            day = { sum = 0, count = 0, hours = {} }
            byDay[dayKey] = day
        end
        day.sum = day.sum + point.p
        day.count = day.count + 1
        day.hours[#day.hours + 1] = { hour = stamp.hour, p = point.p }
    end

    local sums, counts = {}, {}
    local seenHours, hours, days = {}, 0, 0

    for _, day in pairs(byDay) do
        if day.count >= 2 and day.sum > 0 then
            days = days + 1
            local average = day.sum / day.count
            for _, entry in ipairs(day.hours) do
                local h = entry.hour
                sums[h] = (sums[h] or 0) + entry.p / average
                counts[h] = (counts[h] or 0) + 1
                if not seenHours[h] then
                    seenHours[h] = true
                    hours = hours + 1
                end
            end
        end
    end

    local result = { ready = false, hours = hours, days = days }
    if hours < self.NEED_HOURS or days < self.NEED_DAYS then return result end

    local low, high, compared = nil, nil, 0
    for h = 0, 23 do
        if (counts[h] or 0) >= 2 then
            compared = compared + 1
            local average = sums[h] / counts[h]
            if not low or average < low.v then low = { h = h, v = average } end
            if not high or average > high.v then high = { h = h, v = average } end
        end
    end

    -- Two hours to compare at least; every hour alike is steady, not unknown.
    if not low or not high or compared < 2 then return result end

    result.ready = true
    result.buyHour, result.buyBelow = low.h, math.max(0, 1 - low.v)
    result.sellHour, result.sellAbove = high.h, math.max(0, high.v - 1)
    result.steady = (high.v - low.v) < self.STEADY
    return result
end

--- The best times in words, longest first, for Theme.FitText; and a longer
--- explanation for a tooltip.
function PriceHistory:DescribeBestTimes(itemID, now)
    local best = self:GetBestTimes(itemID, now)

    if not best.ready then
        local hoursLeft = math.max(0, self.NEED_HOURS - best.hours)
        local daysLeft = math.max(0, self.NEED_DAYS - best.days)
        local texts = {
            ("Best times: learning (%d of %d hours, %d of %d days)"):format(
                math.min(best.hours, self.NEED_HOURS), self.NEED_HOURS,
                math.min(best.days, self.NEED_DAYS), self.NEED_DAYS),
            "Best times: still learning",
        }
        local why = ("Scan at different times of day to learn when it is cheapest and dearest. "
            .. "It needs scans in %d different hours, on %d days in the last week, "
            .. "with each hour scanned on two of those days.\n\nSo far: %d hour%s and %d day%s.")
            :format(self.NEED_HOURS, self.NEED_DAYS,
                best.hours, best.hours == 1 and "" or "s", best.days, best.days == 1 and "" or "s")
        if hoursLeft == 0 and daysLeft == 0 then
            why = why .. "\n\nScan again at hours you have seen before, so they can be compared."
        end
        return texts, why, best
    end

    if best.steady then
        return {
            "Best times: none, it costs about the same all day",
            "Steady all day",
        }, ("Over the last week no hour ran more than %d%% from another, so it does not matter when you buy or sell.")
            :format(math.floor(self.STEADY * 100)), best
    end

    local buy, sell = self.HourText(best.buyHour), self.HourText(best.sellHour)
    local below = math.floor(best.buyBelow * 100 + 0.5)
    local above = math.floor(best.sellAbove * 100 + 0.5)

    return {
        ("Cheapest around %s (-%d%%), dearest around %s (+%d%%)"):format(buy, below, sell, above),
        ("Cheapest around %s, dearest around %s"):format(buy, sell),
        ("Buy ~%s, sell ~%s"):format(buy, sell),
    }, ("From %d days of scans in %d different hours. Around %s it ran %d%% under that day's average, "
        .. "and around %s %d%% over. A pattern, not a promise: a big seller can change it any day.")
        :format(best.days, best.hours, buy, below, sell, above), best
end

--------------------------------------------------------------------------------
-- Upkeep
--------------------------------------------------------------------------------

--- Drop items with nothing left in the last seven days.
function PriceHistory:Prune(now)
    now = now or time()
    local realm = RealmTable(false)
    if not realm then return 0 end

    local removed = 0
    for itemID, list in pairs(realm) do
        if type(list) == "table" then
            Trim(list, now)
            if #list == 0 then
                realm[itemID] = nil
                removed = removed + 1
            end
        end
        -- Anything else is left as it is: never delete what cannot be read.
    end
    return removed
end

--- How many items have a history on this realm.
function PriceHistory:Count()
    local realm = RealmTable(false)
    local count = 0
    for _ in pairs(realm or {}) do count = count + 1 end
    return count
end

function PriceHistory:OnEnable()
    self:Prune()
end
