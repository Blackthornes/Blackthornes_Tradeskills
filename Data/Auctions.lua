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

function Auctions:OnOwnedAuctionsUpdated()
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
    record.items = items
    record.updatedAt = time()
    record.auctionCount = count

    ns.Debug(("read %d owned auction(s) covering %d item(s)"):format(
        count, Util.Count(items)))

    -- A listing waiting to be verified is resolved by this answer, which is
    -- authoritative in a way that event timing is not.
    local pending = ns.Posting and ns.Posting.pending
    if pending and pending.verifying then
        ns.Posting:ResolvePending(items[pending.itemID] or 0)
    end

    if ns.UI then
        ns.UI:RefreshActiveTab()
        ns.UI:UpdateHeader()
    end
end

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------

function Auctions:OnEnable()
    ns.RegisterEvent(self, "OWNED_AUCTIONS_UPDATED", self.OnOwnedAuctionsUpdated)

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
    if hasQuery then
        ns.PrintRaw("  re-querying...")

        pcall(C_AuctionHouse.QueryOwnedAuctions, {})

        C_Timer.After(2, function()
            local ok, count = pcall(C_AuctionHouse.GetNumOwnedAuctions)
            ns.Print(("after querying: %s auction(s)"):format(
                ok and tostring(count) or "call failed"))
        end)
    end
end)
