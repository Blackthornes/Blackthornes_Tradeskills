-- Blackthornes Tradeskills -- Logic/BuyLog.lua
-- Every auction house buy, for the Sales tab's Bought view.
--
-- A player asked for a list of what they bought (2026-11-14, the owner said
-- build it from a mockup). MethodProfit already keeps the last few buys of
-- each item (`methodLog[realm].buys`), with no character. From now on each
-- buy is also written here, with the character who bought it:
--
--   buyLog[realm] = { since = time first written,
--                     buys = { { id, n, paid, at, who }, ... } }
--
-- The view reads both: this log, and the older buys from before `since`
-- (shown with no character), so nothing is counted twice. Never rename
-- `buyLog`; nothing here rewrites MethodProfit's records.

local _, ns = ...

local BuyLog = ns.NewModule("BuyLog")

--- At most this many buys a realm; the oldest go first.
BuyLog.MAX = 2000

--- Moves on every buy written, so a view knows to read again.
BuyLog.version = 0

local function Now() return time() end

local function CharacterKey()
    local ok, key = pcall(function() return ns.Config:GetCharacterKey() end)
    if ok and type(key) == "string" and key ~= "" then return key end
    return nil
end

--- This realm's log, made when first needed.
function BuyLog:Get()
    if not ns.db then return { buys = {} } end
    ns.db.buyLog = type(ns.db.buyLog) == "table" and ns.db.buyLog or {}
    local realm = ns.Config:GetRealmKey()
    local log = ns.db.buyLog[realm]
    if type(log) ~= "table" then
        log = {}
        ns.db.buyLog[realm] = log
    end
    if type(log.buys) ~= "table" then log.buys = {} end
    return log
end

--- Write one buy down, from MethodProfit:NoteBought.
function BuyLog:Note(itemID, quantity, paid, at)
    itemID, quantity, paid = tonumber(itemID), tonumber(quantity), tonumber(paid)
    if not itemID or not quantity or quantity <= 0 or not paid or paid <= 0 then return end
    local log = self:Get()
    at = at or Now()
    if not log.since or at < log.since then log.since = at end
    log.buys[#log.buys + 1] = { id = itemID, n = quantity, paid = paid, at = at, who = CharacterKey() }
    while #log.buys > self.MAX do table.remove(log.buys, 1) end
    self.version = self.version + 1
end

--- Every buy between from and to (to not included), newest first.
-- @param who  a character key, or nil or "all" for everyone
-- @return { { id, n, paid, at, who } } fresh tables
function BuyLog:Rows(from, to, who)
    from, to = from or 0, to or math.huge
    if who == "all" then who = nil end
    local rows = {}
    local log = self:Get()
    local since = log.since

    for _, buy in ipairs(log.buys) do
        if type(buy) == "table" and tonumber(buy.at) and buy.at >= from and buy.at < to
            and (not who or buy.who == who) then
            rows[#rows + 1] = { id = buy.id, n = buy.n, paid = buy.paid, at = buy.at, who = buy.who }
        end
    end

    -- Older buys have no character, so they only show for everyone.
    if not who and ns.MethodProfit then
        local old = ns.MethodProfit:GetLog().buys
        for itemID, list in pairs(old) do
            if type(list) == "table" then
                for _, buy in ipairs(list) do
                    local at = type(buy) == "table" and tonumber(buy.at)
                    if at and (not since or at < since) and at >= from and at < to
                        and tonumber(buy.n) and tonumber(buy.paid) then
                        rows[#rows + 1] = { id = tonumber(itemID) or itemID, n = buy.n, paid = buy.paid, at = at }
                    end
                end
            end
        end
    end

    table.sort(rows, function(a, b)
        if a.at ~= b.at then return a.at > b.at end
        return (tonumber(a.id) or 0) < (tonumber(b.id) or 0)
    end)
    return rows
end

--- The characters this log has buys for, as keys, in no set order.
function BuyLog:Characters()
    local seen, keys = {}, {}
    for _, buy in ipairs(self:Get().buys) do
        if type(buy) == "table" and type(buy.who) == "string" and not seen[buy.who] then
            seen[buy.who] = true
            keys[#keys + 1] = buy.who
        end
    end
    return keys
end

--- Totals for a list of rows: spent, items, buys, and the item bought most.
function BuyLog.Totals(rows)
    local spent, items, perItem = 0, 0, {}
    for _, row in ipairs(rows) do
        spent = spent + (row.paid or 0)
        items = items + (row.n or 0)
        perItem[row.id] = (perItem[row.id] or 0) + (row.n or 0)
    end
    local top, topCount
    for id, count in pairs(perItem) do
        if not topCount or count > topCount or (count == topCount and (tonumber(id) or 0) < (tonumber(top) or 0)) then
            top, topCount = id, count
        end
    end
    return { spent = spent, items = items, buys = #rows, top = top, topCount = topCount or 0 }
end

--- Every buy of one item in the rows: how many in all, how many buys and
--- what one cost on average (copper).
function BuyLog.ItemTotals(rows, itemID)
    local n, paid, buys = 0, 0, 0
    for _, row in ipairs(rows) do
        if row.id == itemID then
            n, paid, buys = n + row.n, paid + row.paid, buys + 1
        end
    end
    return { n = n, buys = buys, each = n > 0 and paid / n or 0 }
end
