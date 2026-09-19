-- Blackthornes Tradeskills -- Data/Auctions.lua
-- What you already have listed.
--
-- Crafting more of something you have sitting unsold on the auction house is
-- how you end up undercutting yourself and tying up gold. This reads your own
-- auctions and caches them per realm, so the profit table can stop recommending
-- an item once you are holding as many as you want listed.

local _, ns = ...

local Auctions = ns.NewModule("Auctions")

local Util = ns.Util

-- Enum.AuctionStatus.Active. A sold auction is no longer competing for a buyer,
-- so it must not count toward your posted limit.
local STATUS_ACTIVE = (Enum and Enum.AuctionStatus and Enum.AuctionStatus.Active) or 0

--------------------------------------------------------------------------------
-- Storage
--------------------------------------------------------------------------------

function Auctions:GetTable()
    if not ns.db then return {} end

    local realmKey = ns.Config:GetRealmKey()

    ns.db.postedAuctions = ns.db.postedAuctions or {}
    ns.db.postedAuctions[realmKey] = ns.db.postedAuctions[realmKey] or { items = {} }

    return ns.db.postedAuctions[realmKey]
end

--- How many units of an item you currently have listed.
function Auctions:GetPostedCount(itemID)
    if not itemID then return 0 end
    return self:GetTable().items[itemID] or 0
end

--- When your auctions were last read, or nil if never.
function Auctions:GetAge()
    local updatedAt = self:GetTable().updatedAt
    if not updatedAt then return nil end
    return time() - updatedAt
end

--------------------------------------------------------------------------------
-- Limits
--------------------------------------------------------------------------------

--- The cap for one item: its own override, else the account-wide default.
-- Zero means no limit.
function Auctions:GetLimit(itemID)
    if not ns.db then return 0 end

    ns.db.postLimits = ns.db.postLimits or {}

    local override = ns.db.postLimits[itemID]
    if override ~= nil then return override end

    return ns.Config:Get("maxPostedPerItem") or 0
end

--- Set a per-item cap. Passing nil clears the override back to the default.
function Auctions:SetLimit(itemID, limit)
    if not ns.db or not itemID then return end

    ns.db.postLimits = ns.db.postLimits or {}
    ns.db.postLimits[itemID] = limit and math.max(0, math.floor(limit)) or nil

    if ns.UI then ns.UI:RefreshActiveTab() end
end

function Auctions:HasOverride(itemID)
    return ns.db and ns.db.postLimits and ns.db.postLimits[itemID] ~= nil
end

--- How many more you could usefully make.
--
-- The limit covers everything you already have, because an item sitting in your
-- bags is no different from one on the auction house: making another does not
-- get you anything you do not already own. Three sources count against it:
--
--   posted  units listed on the auction house
--   onHand  units in bags and bank (equipped gear is not counted -- it is in
--           use, not stock)
--   queued  units the craft queue will produce, so queueing 2 and looking again
--           does not then suggest 2 more
--
-- @return remaining, posted, onHand, queued, limit
--         remaining is nil when uncapped
function Auctions:GetRoom(itemID, ignoreRecipeID)
    local limit = self:GetLimit(itemID)
    local posted = self:GetPostedCount(itemID)
    local onHand = ns.Inventory:GetOwnedCount(itemID)

    local queued = 0
    for _, entry in ipairs(ns.Queue:GetAll()) do
        if entry.recipeID ~= ignoreRecipeID then
            local recipe = ns.Recipes:GetAny(entry.recipeID)

            if recipe and recipe.outputItemID == itemID then
                local perCraft = math.max(1, recipe.quantityMin or 1)
                queued = queued + (entry.quantity * perCraft)
            end
        end
    end

    if limit <= 0 then
        return nil, posted, onHand, queued, 0
    end

    return math.max(0, limit - posted - onHand - queued), posted, onHand, queued, limit
end

--- Everything you already hold of an item: listed plus in bags and bank.
function Auctions:GetStock(itemID)
    return self:GetPostedCount(itemID) + ns.Inventory:GetOwnedCount(itemID)
end

--------------------------------------------------------------------------------
-- Reading owned auctions
--------------------------------------------------------------------------------

--- Re-read what this character has listed.
-- @param opts { priority, force } -- raise the priority when a click is waiting
--   on the answer, as verifying a listing is, and force past the coalescing
--   window when that answer is the only thing that settles whether a listing
--   went up. Without force, the refresh fired half a second after an auction
--   was created swallowed the verification refresh three seconds later, and a
--   listing that went up perfectly well was reported as "could not tell".
function Auctions:Refresh(opts)
    opts = opts or {}

    if not ns.Scanner.isAuctionHouseOpen then return false end
    if not Util.HasFunction("C_AuctionHouse.QueryOwnedAuctions") then return false end

    -- Several things want this at once after a listing, and each one is a
    -- throttled request. Coalesce them.
    local now = GetTime()
    if not opts.force and self.lastRefresh and (now - self.lastRefresh) < 5 then
        return false
    end
    self.lastRefresh = now

    Util.WhenAuctionReady(function()
        pcall(C_AuctionHouse.QueryOwnedAuctions, {})

        -- The reply may or may not be announced, so go and read it either way.
        Auctions:ScheduleConfirm()
    end, nil, {
        name = "owned auctions",
        key = "owned-auctions",
        -- Bookkeeping, so it waits behind anything the player clicked. It is
        -- also what settles whether a listing went up, so it must not be
        -- starved: a generous expiry rather than a high priority.
        priority = opts.priority or ns.AHQueue.PRIORITY.normal,
        expires = 30,
    })

    return true
end

-- How long after a query goes out we look for the answer ourselves, in seconds.
--
-- Forever has OWNED_AUCTIONS_UPDATED and does fire it -- measured in game, four
-- times in one session -- but not when a listing needs confirming. Waiting five
-- seconds to be told meant a listing that went up perfectly well was reported as
-- "could not tell whether that listing went up" on every single post.
--
-- The reads themselves work: `/bts auctions` returns the right count and item
-- straight after a query. So the answer is read directly rather than waited for,
-- several times, because the server's reply lands some unpredictable moment
-- after the query rather than at a knowable one.
local CONFIRM_DELAYS = { 0.6, 1.4, 2.4, 3.6, 4.8 }

--- Do two itemID -> quantity maps hold the same thing?
--
-- Reading is cheap but redrawing the UI is not, and these reads now happen on a
-- timer rather than only when something changed.
local function SameCounts(a, b)
    if not a then return false end

    for itemID, quantity in pairs(a) do
        if b[itemID] ~= quantity then return false end
    end

    for itemID in pairs(b) do
        if a[itemID] == nil then return false end
    end

    return true
end

--- Read what the client says we have listed right now, and store it.
--
-- Local reads only. Nothing here is throttled, so it is safe to call repeatedly
-- while waiting for a reply to land.
--
-- @param opts.final  settle a pending listing with whatever is read, even if the
--   item is not there. A read that has not seen the server's reply yet must not
--   be allowed to say a listing failed, so only the last read of a sequence --
--   or the client's own announcement, where there is one -- may do that.
function Auctions:ReadOwned(opts)
    opts = opts or {}

    if not Util.HasFunction("C_AuctionHouse.GetNumOwnedAuctions") then return end

    local ok, count = pcall(C_AuctionHouse.GetNumOwnedAuctions)
    if not ok or not count then return end

    local items = {}

    for index = 1, count do
        local infoOk, info = pcall(C_AuctionHouse.GetOwnedAuctionInfo, index)

        if infoOk and info then
            local itemID = info.itemKey and info.itemKey.itemID

            -- status is nil on some clients; treat only an explicit non-active
            -- status as sold rather than discarding everything.
            local active = info.status == nil or info.status == STATUS_ACTIVE

            if itemID and active then
                items[itemID] = (items[itemID] or 0) + (info.quantity or 1)
            end
        end
    end

    local record = self:GetTable()
    local changed = record.auctionCount ~= count or not SameCounts(record.items, items)

    record.items = items
    record.updatedAt = time()
    record.auctionCount = count

    if changed then
        ns.Debug(("read %d owned auction(s) covering %d item(s)"):format(
            count, Util.Count(items)))
    end

    -- A listing waiting to be verified is settled by what we actually hold,
    -- which is authoritative in a way that event timing is not.
    local pending = ns.Posting and ns.Posting.pending
    if pending and pending.verifying then
        local posted = items[pending.itemID] or 0

        if posted > (pending.postedBefore or 0) or opts.final then
            ns.Posting:ResolvePending(posted)
        end
    end

    if changed and ns.UI then
        ns.UI:RefreshActiveTab()
        ns.UI:UpdateHeader()
    end
end

--- The client announcing that owned auctions changed, where it does so.
function Auctions:OnOwnedAuctionsUpdated()
    -- Counted, because registering this event and actually receiving it are two
    -- different things on this client and only the second one is any use.
    -- Reading registration as proof of delivery is what had the addon waiting
    -- on an announcement that did not come, and a successful listing reporting
    -- "could not tell".
    self.ownedEventCount = (self.ownedEventCount or 0) + 1

    -- The server has answered, so this reading is as good as it is going to get.
    self:ReadOwned({ final = true })
end

--- Go and look for the reply, rather than trusting it to be announced.
--
-- Each query supersedes the last, so a sequence still running when a newer query
-- goes out stops rather than resolving a listing against a stale reading.
function Auctions:ScheduleConfirm()
    local token = (self.confirmToken or 0) + 1
    self.confirmToken = token

    for i = 1, #CONFIRM_DELAYS do
        local isLast = (i == #CONFIRM_DELAYS)

        C_Timer.After(CONFIRM_DELAYS[i], function()
            if Auctions.confirmToken ~= token then return end

            Auctions:ReadOwned({ final = isLast })
        end)
    end
end

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------

function Auctions:OnEnable()
    -- This client accepts the registration. Whether it ever sends the event is
    -- a separate question, and the answer appears to be no -- which is not
    -- something a registration check can tell you, so both are recorded and
    -- `/bts auctions` reports them separately. Verification depends on neither.
    self.ownedEventCount = 0
    self.hasOwnedEvent = ns.RegisterEvent(
        self, "OWNED_AUCTIONS_UPDATED", self.OnOwnedAuctionsUpdated) and true or false

    ns.RegisterEvent(self, "AUCTION_HOUSE_SHOW", function()
        -- Slight delay: the auction house is not ready to answer queries the
        -- instant it opens.
        C_Timer.After(0.5, function() Auctions:Refresh() end)
    end)

    -- Posting or cancelling changes the count, so re-read rather than drift.
    ns.RegisterEvent(self, "AUCTION_HOUSE_AUCTION_CREATED", function()
        C_Timer.After(0.5, function() Auctions:Refresh() end)
    end)

    ns.RegisterEvent(self, "AUCTION_CANCELED", function()
        C_Timer.After(0.5, function() Auctions:Refresh() end)
    end)
end

--------------------------------------------------------------------------------
-- Diagnostics
--------------------------------------------------------------------------------

-- Verification of a listing rests entirely on being able to read your own
-- auctions. If that reading is broken, a successful post looks like a failure,
-- so it needs to be checkable on its own.
ns.RegisterCommand("auctions", "list what the client says you have listed", function()
    if not ns.Scanner.isAuctionHouseOpen then
        ns.Print("the auction house must be open")
        return
    end

    local hasQuery = Util.HasFunction("C_AuctionHouse.QueryOwnedAuctions")
    local hasCount = Util.HasFunction("C_AuctionHouse.GetNumOwnedAuctions")
    local hasInfo = Util.HasFunction("C_AuctionHouse.GetOwnedAuctionInfo")

    ns.Print("owned auctions")
    ns.PrintRaw(("  QueryOwnedAuctions:   %s"):format(hasQuery and "yes" or "no"))
    ns.PrintRaw(("  GetNumOwnedAuctions:  %s"):format(hasCount and "yes" or "no"))
    ns.PrintRaw(("  GetOwnedAuctionInfo:  %s"):format(hasInfo and "yes" or "no"))
    local announces
    if not Auctions.hasOwnedEvent then
        announces = "not supported by this client"
    elseif (Auctions.ownedEventCount or 0) > 0 then
        announces = ("yes, %d time(s) this session"):format(Auctions.ownedEventCount)
    else
        announces = "registered, but never fired this session"
    end

    ns.PrintRaw(("  announces changes:    %s"):format(announces))

    if hasCount then
        local ok, count = pcall(C_AuctionHouse.GetNumOwnedAuctions)
        ns.PrintRaw(("  count right now:      %s"):format(
            ok and tostring(count) or "call failed"))

        if ok and count and count > 0 and hasInfo then
            for index = 1, math.min(count, 8) do
                local infoOk, info = pcall(C_AuctionHouse.GetOwnedAuctionInfo, index)

                if infoOk and info then
                    ns.PrintRaw(("    %d: item=%s qty=%s status=%s"):format(
                        index,
                        tostring(info.itemKey and info.itemKey.itemID),
                        tostring(info.quantity),
                        tostring(info.status)))
                else
                    ns.PrintRaw(("    %d: could not be read"):format(index))
                end
            end
        end
    end

    -- Re-query, then report again: the count above may predate any reply.
    --
    -- Paced like every other request even though this is a diagnostic run by
    -- hand. A command that quietly spends the player's allowance is a poor thing
    -- to reach for when the complaint is that the allowance ran out.
    if hasQuery then
        ns.PrintRaw("  re-querying...")

        Util.WhenAuctionReady(function()
            pcall(C_AuctionHouse.QueryOwnedAuctions, {})

            C_Timer.After(2, function()
                local ok, count = pcall(C_AuctionHouse.GetNumOwnedAuctions)
                ns.Print(("after querying: %s auction(s)"):format(
                    ok and tostring(count) or "call failed"))
            end)
        end, function()
            ns.Warn("the auction house stayed busy; the re-query was not sent.")
        end, {
            name = "owned auctions (diagnostic)",
            key = "owned-auctions",
            priority = ns.AHQueue.PRIORITY.urgent,
            expires = 10,
        })
    end
end)
