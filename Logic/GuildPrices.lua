-- Blackthornes Tradeskills -- Logic/GuildPrices.lua
-- Auction prices shared within a guild.
--
-- Asked 2026-10-07 (on Discord, a player: "this would make the Price
-- History Chart wildly more useful"). The owner chose the guild rather than
-- the whole server: a guild is a smaller, known group, so there is far less
-- traffic and far less room for someone to feed in made-up prices.
--
-- On by default (the owner, 2026-10-07); Settings, Sharing: `guildPrices`.
-- When on:
--   * After a scan, its prices go to the guild, at most once an hour, and not
--     at all when a guildmate shared a scan from about the same time.
--   * Guildmates' prices are kept apart from yours, in
--     `guildPrices[realm][itemID]` (never rename it), and only fill gaps:
--     an item you have never priced, or whose price has gone stale while
--     theirs is newer. Your own scans always win.
--   * Each item keeps the last price from up to three guildmates, and the
--     middle one is used, so one wrong price is outvoted. A price far from a
--     fresh one of your own is not taken at all.
--   * The price graph gets the hours you did not scan yourself.
--   * Kept a week, then dropped.

local _, ns = ...

local GuildPrices = ns.NewModule("GuildPrices")

local Comm = ns.Comm

local HOUR = 3600
GuildPrices.SHARE_EVERY = HOUR
GuildPrices.SCAN_FRESH = 30 * 60      -- only a scan this recent is shared
GuildPrices.HEARD_COVERS = 30 * 60    -- a guildmate's scan this close covers yours
GuildPrices.KEEP = 7 * 24 * HOUR
GuildPrices.USE_FOR = 3 * 24 * HOUR   -- a guild price older than this is not used
GuildPrices.MAX_ITEMS = 5000
GuildPrices.SENDERS_PER_ITEM = 3
GuildPrices.FAR = 10                  -- 10x from a fresh price of yours is refused
GuildPrices.MAX_PER_SENDER_HOUR = 6000
GuildPrices.MAX_ITEM_ID = 10000000      -- an item ID past this is not an item
GuildPrices.MAX_STORED = 4 * GuildPrices.MAX_ITEMS  -- items kept for a realm

--------------------------------------------------------------------------------
-- Saved data
--------------------------------------------------------------------------------

function GuildPrices:IsOn()
    return ns.Config and ns.Config:Get("guildPrices") == true
end

local function RealmTable(create)
    local db = ns.db
    if not db then return nil end
    if type(db.guildPrices) ~= "table" then
        if not create then return nil end
        db.guildPrices = {}
    end
    local key = ns.Config:GetRealmKey()
    local realm = db.guildPrices[key]
    if type(realm) ~= "table" then
        if not create then return nil end
        realm = {}
        db.guildPrices[key] = realm
    end
    return realm
end

-- An item's entry is a flat list, four values per guildmate:
-- name, when their scan was, market value, cheapest listing.
local STRIDE = 4

--- Keep one guildmate's price for an item: replaces their last one, else the
--- oldest when the item already has SENDERS_PER_ITEM.
function GuildPrices:Store(itemID, sender, at, market, lowest)
    local realm = RealmTable(true)
    if not realm then return end

    local list = realm[itemID]
    if type(list) ~= "table" then
        -- A guildmate could send item IDs no one has, without end, and the
        -- save would grow with them. A realm keeps so many items and no more;
        -- the count is taken once a session and kept up from there.
        if type(self.stored) ~= "number" then self.stored = self:Count() end
        if self.stored >= self.MAX_STORED then return end
        self.stored = self.stored + 1
        list = {}
        realm[itemID] = list
    end

    local slot, oldest, oldestAt
    for index = 1, #list, STRIDE do
        if list[index] == sender then slot = index break end
        if not oldestAt or (list[index + 1] or 0) < oldestAt then oldest, oldestAt = index, list[index + 1] or 0 end
    end
    if not slot then
        if #list / STRIDE < self.SENDERS_PER_ITEM then
            slot = #list + 1
        else
            slot = oldest
        end
    end
    if slot ~= #list + 1 and (list[slot + 1] or 0) > at then return end

    list[slot], list[slot + 1], list[slot + 2], list[slot + 3] = sender, at, market, lowest or market
end

local function Median(values)
    table.sort(values)
    local count = #values
    if count == 0 then return nil end
    if count % 2 == 1 then return values[(count + 1) / 2] end
    return math.floor((values[count / 2] + values[count / 2 + 1]) / 2 + 0.5)
end

--- What guildmates say an item is worth: the middle of their last prices.
-- `which` as Prices:GetValue: "market" (default), "min" or "lowest" read
-- the cheapest listing, "rival" is never answered.
-- @return copper, and when the newest of those scans was; nil without
function GuildPrices:GetValue(itemID, which, now)
    if which == "rival" then return nil end
    local realm = RealmTable(false)
    local list = realm and realm[itemID]
    if type(list) ~= "table" then return nil end

    now = now or time()
    local values, newest = {}, nil
    for index = 1, #list, STRIDE do
        local at = list[index + 1]
        local value = (which == "min" or which == "lowest") and list[index + 3] or list[index + 2]
        if type(at) == "number" and type(value) == "number" and now - at <= self.USE_FOR then
            values[#values + 1] = value
            if not newest or at > newest then newest = at end
        end
    end
    return Median(values), newest
end

--- Drop prices older than KEEP, and items left with none.
function GuildPrices:Prune(now)
    now = now or time()
    local removed = 0
    self.stored = nil
    for _, realm in pairs((ns.db and ns.db.guildPrices) or {}) do
        if type(realm) == "table" then
            for itemID, list in pairs(realm) do
                local kept = {}
                if type(list) == "table" then
                    for index = 1, #list, STRIDE do
                        if type(list[index + 1]) == "number" and now - list[index + 1] <= self.KEEP then
                            for offset = 0, STRIDE - 1 do kept[#kept + 1] = list[index + offset] end
                        end
                    end
                end
                if #kept == 0 then
                    realm[itemID] = nil
                    removed = removed + 1
                elseif #kept < #list then
                    realm[itemID] = kept
                end
            end
        end
    end
    return removed
end

function GuildPrices:Count()
    local realm = RealmTable(false)
    local count = 0
    for _ in pairs(realm or {}) do count = count + 1 end
    return count
end

--------------------------------------------------------------------------------
-- Sending
--------------------------------------------------------------------------------
-- S<scan time>: "I am about to share a scan from then".
-- P<scan time>:<id>,<market>[,<lowest>];...  one message of prices, numbers in
-- base 36, the lowest left out when it is the market value. Each message
-- stands alone, so a lost one only loses its own prices.

--- The prices from the last scan, as message bodies.
function GuildPrices:Batches(scanAt)
    local prices = ns.Prices:GetTable()
    local ids = {}
    for itemID, record in pairs(prices) do
        -- An item searched with nothing listed and never priced keeps a
        -- fresh seen time but no market value (Prices:RecordEmpty), and
        -- IsCredible lets nil through, so the number is checked here. A sold
        -- out item (quantity 0) keeps its old market value with a fresh seen
        -- time; sent, guildmates stored it as a listing seen this hour.
        if type(itemID) == "number" and type(record) == "table" and type(record.seen) == "number"
            and record.seen >= scanAt - self.SCAN_FRESH and type(record.market) == "number"
            and ns.Prices.IsCredible(record.market) and (tonumber(record.quantity) or 1) > 0 then
            ids[#ids + 1] = itemID
        end
    end
    table.sort(ids)

    local head = "P" .. Comm.ToBase36(scanAt) .. ":"
    local batches, parts, length = {}, {}, #head
    for index = 1, math.min(#ids, self.MAX_ITEMS) do
        local record = prices[ids[index]]
        local market = math.floor(record.market + 0.5)
        local lowest = ns.Prices.LowestListed(record)
        local entry = Comm.ToBase36(ids[index]) .. "," .. Comm.ToBase36(market)
        if lowest and ns.Prices.IsCredible(lowest) and math.floor(lowest + 0.5) ~= market then
            entry = entry .. "," .. Comm.ToBase36(math.floor(lowest + 0.5))
        end
        entry = entry .. ";"
        if length + #entry > Comm.MAX_MESSAGE then
            batches[#batches + 1] = table.concat(parts)
            parts, length = {}, #head
        end
        parts[#parts + 1] = entry
        length = length + #entry
    end
    if #parts > 0 then batches[#batches + 1] = table.concat(parts) end
    return batches, head, #ids
end

--- When this realm's prices were last shared: { at, scanAt }, or nil.
function GuildPrices:LastSent()
    local sent = ns.db and ns.db.guildPricesSent
    local mine = type(sent) == "table" and sent[ns.Config:GetRealmKey()]
    return type(mine) == "table" and mine or nil
end

local function InGuild()
    local ok, yes = pcall(IsInGuild)
    return ok and yes == true
end

--- Why the last scan is not being shared now, or nil when it should be.
function GuildPrices:WhyNotShare(now)
    now = now or time()
    if not self:IsOn() then return "off" end
    if not InGuild() then return "not in a guild" end

    local scanAt = ns.Prices:GetLastScan()
    if not scanAt or now - scanAt > self.SCAN_FRESH then return "no recent scan" end

    local realmKey = ns.Config:GetRealmKey()
    local mine = self:LastSent()
    if mine and mine.scanAt and mine.scanAt >= scanAt then return "already shared" end
    if mine and mine.at and now - mine.at < self.SHARE_EVERY then return "shared within the hour" end

    local heard = self.heard and self.heard[realmKey]
    if heard and heard >= scanAt - self.HEARD_COVERS then return "a guildmate shared one" end
    return nil, scanAt
end

function GuildPrices:Share(now)
    now = now or time()
    local why, scanAt = self:WhyNotShare(now)
    if why then return false, why end

    local batches, head, count = self:Batches(scanAt)
    if #batches == 0 then return false, "nothing priced" end

    -- Saved, so a /reload does not send the same scan again.
    ns.db.guildPricesSent = type(ns.db.guildPricesSent) == "table" and ns.db.guildPricesSent or {}
    ns.db.guildPricesSent[ns.Config:GetRealmKey()] = { at = now, scanAt = scanAt }

    Comm:Send("S", Comm.ToBase36(scanAt), "GUILD")
    for _, body in ipairs(batches) do
        -- The head starts with the kind letter, "P".
        Comm:Send("P", head:sub(2) .. body, "GUILD")
    end
    ns.Debug(("guild prices: sharing %d price(s) in %d message(s)"):format(count, #batches))
    return true, count
end

--------------------------------------------------------------------------------
-- Receiving
--------------------------------------------------------------------------------

local function IsMe(sender)
    return Comm.IsMe(sender)
end

function GuildPrices:OnAnnounce(sender, body, channel)
    if channel ~= "GUILD" or IsMe(sender) then return end
    local at = Comm.FromBase36(body)
    if not at or at > time() + HOUR then return end
    self.heard = self.heard or {}
    local realmKey = ns.Config:GetRealmKey()
    if not self.heard[realmKey] or at > self.heard[realmKey] then self.heard[realmKey] = at end
end

--- How far from your own fresh price a guildmate's may be.
local function TooFar(itemID, value)
    local own = ns.Prices:GetTable()[itemID]
    if type(own) ~= "table" or type(own.market) ~= "number" or ns.Prices:IsStale(itemID) then return false end
    return value > own.market * GuildPrices.FAR or value * GuildPrices.FAR < own.market
end

function GuildPrices:OnPrices(sender, body, channel)
    if channel ~= "GUILD" or IsMe(sender) or not self:IsOn() then return end
    local who = Comm.NameKey(sender)
    if not who then return end

    local atText, list = body:match("^(%w+):(.*)$")
    local at = Comm.FromBase36(atText)
    local now = time()
    if not at or at > now + HOUR or now - at > self.USE_FOR then return end

    -- A guildmate sending far more than one scan an hour is ignored for the
    -- rest of that hour.
    self.counts = self.counts or {}
    local tally = self.counts[who]
    if not tally or now - tally.from > HOUR then
        tally = { from = now, items = 0 }
        self.counts[who] = tally
    end

    local taken, refused = 0, 0
    for idText, marketText, lowestText in list:gmatch("(%w+),(%w+),?(%w*);") do
        if tally.items >= self.MAX_PER_SENDER_HOUR then break end
        tally.items = tally.items + 1

        local itemID, market = Comm.FromBase36(idText), Comm.FromBase36(marketText)
        local lowest = lowestText ~= "" and Comm.FromBase36(lowestText) or market
        if itemID and itemID > 0 and itemID <= self.MAX_ITEM_ID and itemID == math.floor(itemID)
            and ns.Prices.IsCredible(market) and ns.Prices.IsCredible(lowest)
            and not TooFar(itemID, market) then
            self:Store(itemID, who, at, market, lowest)
            if ns.PriceHistory and ns.PriceHistory.Fill then ns.PriceHistory:Fill(itemID, lowest, at) end
            taken = taken + 1
        else
            refused = refused + 1
        end
    end

    if taken > 0 then ns.Prices.changes = (ns.Prices.changes or 0) + 1 end
    if taken > 0 then self.lastHeard = { who = sender:match("^[^%-]+") or sender, at = now } end
    if refused > 0 then self.refused = (self.refused or 0) + refused end
end

--------------------------------------------------------------------------------
-- Status and lifecycle
--------------------------------------------------------------------------------

function GuildPrices:Describe()
    if not self:IsOn() then return "Guild prices are off." end
    local parts = { ("%s guild price%s kept."):format(ns.Util and ns.Util.Comma and ns.Util.Comma(self:Count())
        or tostring(self:Count()), self:Count() == 1 and "" or "s") }
    local mine = self:LastSent()
    if mine and mine.at and ns.Util and ns.Util.FormatAgeAgo then
        parts[#parts + 1] = "You last shared " .. ns.Util.FormatAgeAgo(time() - mine.at) .. "."
    end
    if self.lastHeard and ns.Util and ns.Util.FormatAgeAgo then
        parts[#parts + 1] = ("Last heard from %s %s."):format(
            self.lastHeard.who, ns.Util.FormatAgeAgo(time() - self.lastHeard.at))
    end
    return table.concat(parts, "  ")
end

function GuildPrices:OnEnable()
    self:Prune()
    Comm:On("S", function(...) GuildPrices:OnAnnounce(...) end)
    Comm:On("P", function(...) GuildPrices:OnPrices(...) end)

    -- Looked at once a minute; Share decides whether anything goes.
    self.ticker = C_Timer.NewTicker(60, function() GuildPrices:Share() end)
end
