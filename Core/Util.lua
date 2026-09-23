-- Blackthornes Tradeskills -- Core/Util.lua
-- Money formatting, table helpers, and a frame-budgeted worker used to grind
-- through thousands of recipes or auction rows without stuttering the client.

local _, ns = ...

local Util = {}
ns.Util = Util

local COPPER_PER_SILVER = 100
local COPPER_PER_GOLD   = 100 * 100

--------------------------------------------------------------------------------
-- Money
--------------------------------------------------------------------------------

local GOLD_SUFFIX   = "|cffffd700g|r"
local SILVER_SUFFIX = "|cffc7c7cfs|r"
local COPPER_SUFFIX = "|cffeda55fc|r"

--- Format a copper amount as gold/silver/copper.
-- @param copper  amount in copper; nil renders as a muted dash
-- @param opts    { short = true } drops trailing silver/copper once gold is large,
--                { noColor = true } strips the colour escapes
function Util.FormatMoney(copper, opts)
    if copper == nil then
        return "|c" .. ns.COLORS.muted .. "--|r"
    end

    opts = opts or {}

    local negative = copper < 0
    local amount = math.floor(math.abs(copper) + 0.5)

    local gold   = math.floor(amount / COPPER_PER_GOLD)
    local silver = math.floor((amount % COPPER_PER_GOLD) / COPPER_PER_SILVER)
    local copperPart = amount % COPPER_PER_SILVER

    local g, s, c = GOLD_SUFFIX, SILVER_SUFFIX, COPPER_SUFFIX
    if opts.noColor then
        g, s, c = "g", "s", "c"
    end

    local parts = {}
    if gold > 0 then
        parts[#parts + 1] = Util.Comma(gold) .. g
    end

    -- Past a few hundred gold the copper column is noise, not precision.
    local suppressMinor = opts.short and gold >= 100

    if not suppressMinor then
        if silver > 0 or gold > 0 then
            parts[#parts + 1] = silver .. s
        end
        if copperPart > 0 or #parts == 0 then
            parts[#parts + 1] = copperPart .. c
        end
    end

    local text = table.concat(parts, " ")
    if negative then
        text = "-" .. text
    end
    return text
end

--- Split copper into the three fields Blizzard's auction price box wants.
-- @return gold, silver, copper
function Util.SplitMoney(amount)
    amount = math.floor(math.max(0, amount or 0))

    return math.floor(amount / COPPER_PER_GOLD),
        math.floor((amount % COPPER_PER_GOLD) / COPPER_PER_SILVER),
        amount % COPPER_PER_SILVER
end

--- Insert thousands separators into a non-negative integer.
function Util.Comma(number)
    local text = tostring(math.floor(number))
    local result = text:reverse():gsub("(%d%d%d)", "%1,"):reverse()
    return (result:gsub("^,", ""))
end

function Util.Round(value, decimals)
    local mult = 10 ^ (decimals or 0)
    return math.floor(value * mult + 0.5) / mult
end

--- Clamp helper; the client provides Clamp() on mainline but we do not rely on it.
function Util.Clamp(value, low, high)
    if value < low then return low end
    if value > high then return high end
    return value
end

--------------------------------------------------------------------------------
-- Tables
--------------------------------------------------------------------------------

function Util.CopyDeep(source)
    if type(source) ~= "table" then return source end

    local copy = {}
    for key, value in pairs(source) do
        copy[key] = Util.CopyDeep(value)
    end
    return copy
end

--- Fill in any keys present in defaults but missing from target, recursively.
-- Existing values are never overwritten, so user settings survive upgrades.
function Util.ApplyDefaults(target, defaults)
    if type(target) ~= "table" then target = {} end

    for key, value in pairs(defaults) do
        if type(value) == "table" then
            target[key] = Util.ApplyDefaults(target[key], value)
        elseif target[key] == nil then
            target[key] = value
        end
    end
    return target
end

function Util.Count(tbl)
    local n = 0
    for _ in pairs(tbl) do n = n + 1 end
    return n
end

--- Sorted array of a table's keys, for stable output in reports.
function Util.SortedKeys(tbl)
    local keys = {}
    for key in pairs(tbl) do
        keys[#keys + 1] = key
    end
    table.sort(keys, function(a, b)
        if type(a) == type(b) then return a < b end
        return tostring(a) < tostring(b)
    end)
    return keys
end

--------------------------------------------------------------------------------
-- Frame-budgeted worker
--------------------------------------------------------------------------------

-- Processing several thousand recipes in one go visibly hitches the client.
-- A worker spreads the same work across frames, spending at most `budgetMs` of
-- each frame and reporting progress so the UI can show a bar.

local workerFrame = CreateFrame("Frame", "BlackthornesTSWorkerFrame")
local activeWorkers = {}

local workerProto = {}
workerProto.__index = workerProto

--- Begin processing a list. Any in-flight run is discarded.
function workerProto:Start(items)
    self.items = items or {}
    self.index = 0
    self.running = true
    self.startedAt = GetTime()
    activeWorkers[self] = true
    workerFrame:Show()
    return self
end

function workerProto:Cancel()
    if not self.running then return end
    self.running = false
    activeWorkers[self] = nil
    if self.onCancel then
        self.onCancel(self)
    end
end

function workerProto:IsRunning()
    return self.running == true
end

--- 0..1 completion, for progress bars.
function workerProto:GetProgress()
    local total = #(self.items or {})
    if total == 0 then return 1 end
    return Util.Clamp(self.index / total, 0, 1)
end

local function StepWorker(worker)
    local deadline = debugprofilestop() + worker.budgetMs
    local items = worker.items
    local total = #items

    while worker.index < total do
        worker.index = worker.index + 1

        local ok, err = pcall(worker.onItem, items[worker.index], worker.index, worker)
        if not ok then
            geterrorhandler()(err)
        end

        -- Not worker.running: onItem may have cancelled us mid-batch.
        if not worker.running then return end

        if debugprofilestop() >= deadline then break end
    end

    if worker.onProgress then
        worker.onProgress(worker:GetProgress(), worker.index, total, worker)
    end

    if worker.index >= total then
        worker.running = false
        activeWorkers[worker] = nil
        if worker.onDone then
            worker.onDone(worker)
        end
    end
end

workerFrame:SetScript("OnUpdate", function()
    if not next(activeWorkers) then
        workerFrame:Hide()
        return
    end

    for worker in pairs(activeWorkers) do
        if worker.running then
            StepWorker(worker)
        else
            activeWorkers[worker] = nil
        end
    end
end)

workerFrame:Hide()

--- Create a worker.
-- @param opts { onItem = function(item, index, worker),
--               onProgress = function(fraction, index, total, worker),
--               onDone = function(worker),
--               onCancel = function(worker),
--               budgetMs = milliseconds of each frame to spend (default 8) }
function Util.NewWorker(opts)
    assert(type(opts) == "table" and type(opts.onItem) == "function",
        "NewWorker requires an onItem handler")

    return setmetatable({
        onItem     = opts.onItem,
        onProgress = opts.onProgress,
        onDone     = opts.onDone,
        onCancel   = opts.onCancel,
        budgetMs   = opts.budgetMs or 8,
        items      = {},
        index      = 0,
        running    = false,
    }, workerProto)
end

--------------------------------------------------------------------------------
-- Misc
--------------------------------------------------------------------------------

--- Existence check for a dotted API path, e.g. "C_AuctionHouse.SendBrowseQuery".
-- Returns the value and true when every segment resolves.
function Util.ResolvePath(path)
    local current = _G
    for segment in path:gmatch("[^%.]+") do
        if type(current) ~= "table" then return nil, false end

        local ok, value = pcall(function() return current[segment] end)
        if not ok or value == nil then return nil, false end

        current = value
    end
    return current, true
end

function Util.HasFunction(path)
    local value, found = Util.ResolvePath(path)
    return found and type(value) == "function"
end

--- What a vendor pays for one unit, or nil if the client has not cached it.
--
-- This is the floor under any listing. An auction below it is worse than
-- walking to a vendor, and that is true before the auction house takes its cut
-- or keeps the deposit, so it is a floor rather than a break-even point.
--
-- Not to be confused with Vendor:GetUnitPrice, which is what a merchant
-- *charges* for the item and is several times larger. That one answers "can I
-- buy this reagent"; this one answers "is listing this worth doing at all".
function Util.GetVendorSellPrice(itemID)
    if not itemID then return nil end
    if not Util.HasFunction("C_Item.GetItemInfo") then return nil end

    -- sellPrice is the eleventh return. Items the client has not cached yet
    -- return nothing at all, which reads the same as "no vendor value" here;
    -- GetItemLabel already asks the client to cache anything it renders, so a
    -- second look once the list refreshes has it.
    local ok, _, _, _, _, _, _, _, _, _, _, sellPrice = pcall(C_Item.GetItemInfo, itemID)

    if not ok or type(sellPrice) ~= "number" or sellPrice <= 0 then return nil end

    return sellPrice
end

--- The most of an item that can sit in one stack, or nil if uncached.
--
-- Used to tell a stack count apart from something that is not one. An auction
-- house that reports 241 of an item whose stack size is 1 is not describing a
-- stack, and a price divided by that number is not a unit price.
function Util.GetMaxStackSize(itemID)
    if not itemID then return nil end
    if not Util.HasFunction("C_Item.GetItemInfo") then return nil end

    -- maxStack is the eighth return.
    local ok, _, _, _, _, _, _, _, maxStack = pcall(C_Item.GetItemInfo, itemID)

    if not ok or type(maxStack) ~= "number" or maxStack < 1 then return nil end

    return maxStack
end

-- Enum.ItemBind values that bind an item the moment it exists: 1 is bind on
-- pickup, 4 is a quest item. Written out rather than read from Enum.ItemBind,
-- the same as Logic/Posting.lua, because this client's Enum tables have been
-- patchy. Bind on equip (2) and bind on use (3) still sell, so they are not
-- here.
local BINDS_ON_PICKUP = { [1] = true, [4] = true }

--- Does this item bind to whoever makes or loots it, so it can never be
--- auctioned?
--
-- @return true, false, or nil when the client has not cached the item yet.
--   Callers decide what unknown means; the Profit list keeps an unknown craft
--   rather than quietly dropping one that may well sell.
-- @return bindType, the raw number, for /bts soulbound to report.
function Util.IsBoundOnPickup(itemID)
    if not itemID then return nil end
    if not Util.HasFunction("C_Item.GetItemInfo") then return nil end

    -- bindType is the fourteenth return.
    local ok, _, _, _, _, _, _, _, _, _, _, _, _, _, bindType =
        pcall(C_Item.GetItemInfo, itemID)

    if not ok or type(bindType) ~= "number" then return nil end

    return BINDS_ON_PICKUP[bindType] == true, bindType
end

--- The price of one, given what a whole listing costs and how many it holds.
--
-- Item auctions quote the price of the stack, so a unit price is a division.
-- The trap is that the quantity is not always a stack count. This client has
-- been seen reporting the total available across every listing of the item
-- instead: 241 Linen Bags on offer, one 3s listing, 300 / 241 = 1, and the
-- sell list offered a bag for a copper.
--
-- Two things prove a quantity is not a stack count, and either means the price
-- is already per unit:
--
--   * it is more than the item can stack to at all -- a Linen Bag stacks to 1,
--     so 241 of them is a market, not a stack;
--   * the whole listing costs less than the number of items in it, so the
--     division would round to nothing.
--
-- When the stack size is not cached the old behaviour stands and the division
-- happens. That is the case worth watching, which is why `/bts listings`
-- prints the stack size it managed to read.
function Util.UnitPriceFromStack(itemID, totalPrice, quantity)
    if not quantity or quantity <= 1 then return totalPrice end
    if totalPrice < quantity then return totalPrice end

    local maxStack = Util.GetMaxStackSize(itemID)
    if maxStack and quantity > maxStack then return totalPrice end

    return math.floor(totalPrice / quantity)
end

--- A player-readable label for an item: its clickable link when the client has
-- the item cached, its name otherwise, and only as a last resort the raw ID.
--
-- Item data is loaded lazily, so an uncached item genuinely has no name to show
-- until something requests it.
function Util.GetItemLabel(itemID)
    if not itemID then return "?" end

    if Util.HasFunction("C_Item.GetItemInfo") then
        local ok, name, link = pcall(C_Item.GetItemInfo, itemID)
        if ok then
            if link then return link end
            if name then return name end
        end
    end

    -- Ask the client to cache it so the next render can show a real name.
    if Util.HasFunction("C_Item.RequestLoadItemDataByID") then
        pcall(C_Item.RequestLoadItemDataByID, itemID)
    end

    return ("item %d"):format(itemID)
end

--- The item's rarity colour, as the game itself draws it.
--
-- Returns nothing when the item is not in the client's cache yet, so callers
-- fall back to their own colour rather than flashing white for one frame. The
-- request below means the next render usually has it.
--
-- Cached only once a colour is actually found: a miss must stay a miss, or an
-- item looked at before it loaded would be stuck uncoloured for the session.
local qualityColors = {}

function Util.GetItemQualityColor(itemID)
    if not itemID then return end

    local cached = qualityColors[itemID]
    if cached then return cached[1], cached[2], cached[3] end

    if not Util.HasFunction("C_Item.GetItemInfo") then return end

    local ok, _, _, quality = pcall(C_Item.GetItemInfo, itemID)
    if not ok or not quality then
        if Util.HasFunction("C_Item.RequestLoadItemDataByID") then
            pcall(C_Item.RequestLoadItemDataByID, itemID)
        end
        return
    end

    -- ITEM_QUALITY_COLORS is the table the default UI itself reads, so the
    -- shades match Blizzard's exactly rather than being approximated here.
    local color = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
    local r, g, b

    if color then
        r, g, b = color.r, color.g, color.b
    elseif Util.HasFunction("C_Item.GetItemQualityColor") then
        local gotColor, cr, cg, cb = pcall(C_Item.GetItemQualityColor, quality)
        if gotColor then r, g, b = cr, cg, cb end
    end

    if not r then return end

    qualityColors[itemID] = { r, g, b }
    return r, g, b
end

--- Run something only when the auction house is ready for another request.
--
-- The auction house throttles addon traffic, and exceeding it does not just
-- drop our request: it puts the whole auction house into "You're doing that
-- too fast", which blocks the player's own manual posting too. Ours is not
-- the only traffic that matters, so every throttled call waits its turn here
-- rather than firing and hoping.
--
-- This used to poll IsThrottledMessageSystemReady on its own half-second timer
-- and call the action the first time it said yes. That check reserves nothing,
-- so two callers polling independently both saw yes in the same frame and both
-- sent -- which is how a paced-looking addon still spent the player's
-- allowance. The wait now happens in one shared queue instead.
--
-- @param action   called when it is our turn to send
-- @param onGiveUp called if that turn never comes
-- @param opts     { name, key, priority, expires }, passed to AHQueue
function Util.WhenAuctionReady(action, onGiveUp, opts)
    opts = opts or {}

    if not ns.AHQueue then
        -- Only reachable if this file is loaded on its own, as the tests do.
        action()
        return
    end

    ns.AHQueue:Request({
        name = opts.name or "auction request",
        key = opts.key,
        priority = opts.priority,
        expires = opts.expires,
        onGiveUp = onGiveUp,
        send = function()
            action()
            return true
        end,
    })
end

--- Is this table field a secure value, and therefore uncallable by addons?
--
-- Returns nil when the client cannot answer, which is different from false:
-- "not protected" and "unknown" should not be confused when comparing two
-- client builds.
function Util.IsSecure(container, field)
    if type(issecurevariable) ~= "function" or type(container) ~= "table" then
        return nil
    end

    local ok, secure = pcall(issecurevariable, container, field)
    if not ok then return nil end

    return secure == true
end

--- Seconds elapsed rendered as a compact age, e.g. "3h", "12m", "just now".
function Util.FormatAge(seconds)
    if not seconds then return "never" end
    if seconds < 60 then return "just now" end
    if seconds < 3600 then return math.floor(seconds / 60) .. "m" end
    if seconds < 86400 then return math.floor(seconds / 3600) .. "h" end
    return math.floor(seconds / 86400) .. "d"
end

--- The same age, phrased to sit in a sentence: "seen %s".
--
-- FormatAge returns "just now" and "never", which are already complete
-- phrases, so callers that appended " ago" to it produced "just now ago".
function Util.FormatAgeAgo(seconds)
    local age = Util.FormatAge(seconds)
    if age == "just now" or age == "never" then return age end
    return age .. " ago"
end

--- Round a price down to something an item auction will actually accept.
--
-- C_AuctionHouse.PostItem takes whole gold and silver only: a price carrying
-- any copper at all silently fails, which the client surfaces as an internal
-- error rather than anything readable. Commodities are unaffected and keep
-- copper precision, so this is only ever applied to item auctions.
--
-- Below a silver there is nothing to round down to, so the floor is one
-- silver. That can land above market value on a near-worthless item, but it
-- is the only price the server will take.
function Util.RoundToSilver(price)
    if type(price) ~= "number" then return nil end
    if price < COPPER_PER_SILVER then return COPPER_PER_SILVER end
    return math.floor(price / COPPER_PER_SILVER) * COPPER_PER_SILVER
end

--- Round a price UP to something an item auction will accept.
--
-- Rounding down is right when there is a rival to get beneath: the price has
-- to be below theirs to sell first. With no rival there is nothing to get
-- beneath, and rounding down instead throws away up to a silver of a price
-- that was only ever an estimate -- enough, on a cheap craft, to put it under
-- what the materials cost and have the listing refused.
function Util.CeilToSilver(price)
    if type(price) ~= "number" then return nil end
    if price <= COPPER_PER_SILVER then return COPPER_PER_SILVER end
    return math.ceil(price / COPPER_PER_SILVER) * COPPER_PER_SILVER
end

--- Is this price one an item auction will accept?
function Util.IsWholeSilver(price)
    return type(price) == "number" and price >= COPPER_PER_SILVER
        and price % COPPER_PER_SILVER == 0
end
