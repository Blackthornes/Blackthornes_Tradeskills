-- Blackthornes Tradeskills -- Data/Scanner.lua
-- Auction house scanning.
--
-- Forever exposes C_AuctionHouse.ReplicateItems, retail's bulk snapshot call,
-- so a full sweep is one request plus a read loop rather than hundreds of
-- throttled browse pages. The read loop is still tens of thousands of rows, so
-- it runs through a frame-budgeted worker instead of blocking the client.

local _, ns = ...

local Scanner = ns.NewModule("Scanner")

local Util = ns.Util

-- Blizzard rate-limits the bulk snapshot hard. Asking more often than this just
-- returns the same cached data and wastes the allowance.
local REPLICATE_COOLDOWN = 15 * 60

-- A browse sweep that never reports itself complete would otherwise page for
-- ever, one throttled request at a time.
local MAX_BROWSE_PAGES = 40

-- How long to wait for a targeted search to answer before deciding it never
-- will. Leaving the wait open is what left the searching indicator turning.
local SEARCH_TIMEOUT = 8

-- Enum.ItemCommodityStatus.Commodity, hardcoded only as a fallback.
local COMMODITY_STATUS = (Enum and Enum.ItemCommodityStatus and Enum.ItemCommodityStatus.Commodity) or 2

Scanner.isAuctionHouseOpen = false
Scanner.isScanning = false

--------------------------------------------------------------------------------
-- Identity
--------------------------------------------------------------------------------

-- Undercutting the cheapest listing is only correct when that listing belongs
-- to somebody else. Beating your own auction by a copper just walks your own
-- price down, which on a quiet realm compounds with every relist.

local function GetPlayerIdentity()
    if Scanner.playerName then
        return Scanner.playerName, Scanner.playerFullName
    end

    local ok, name = pcall(UnitName, "player")
    Scanner.playerName = (ok and name) or "?"

    local realmOk, realm = pcall(GetRealmName)
    if realmOk and realm then
        -- ownerFullName arrives as Name-Realm with spaces stripped.
        Scanner.playerFullName = Scanner.playerName .. "-" .. realm:gsub("%s", "")
    end

    return Scanner.playerName, Scanner.playerFullName
end

function Scanner:IsOwnAuction(owner, ownerFullName)
    local name, fullName = GetPlayerIdentity()

    if ownerFullName and fullName and ownerFullName == fullName then return true end
    if owner and owner == name then return true end

    return false
end

--------------------------------------------------------------------------------
-- Commodity status cache
--------------------------------------------------------------------------------

-- Whether an item is a commodity decides how to read its price, and the answer
-- never changes, so it is memoised for the session.
local commodityCache = {}

--- Find an item in the bags, as an ItemLocation.
--
-- GetItemCommodityStatus wants a location rather than an ID, so commodity
-- status can only be determined for something you are actually holding.
local function LocateInBags(itemID)
    if type(_G.ItemLocation) ~= "table" then return nil end

    -- Every container being carried, not the four ordinary bags: an item held
    -- only in a reagent bag would otherwise have no commodity status, and
    -- commodity status is what decides how the thing is priced and listed.
    for _, bag in ipairs(ns.Inventory:GetCarriedBags()) do
        local slotsOk, slots = pcall(C_Container.GetContainerNumSlots, bag)

        if slotsOk and slots then
            for slot = 1, slots do
                local infoOk, info = pcall(C_Container.GetContainerItemInfo, bag, slot)

                if infoOk and info and info.itemID == itemID then
                    -- A colon method: ItemLocation has to be passed as self.
                    local ok, location =
                        pcall(ItemLocation.CreateFromBagAndSlot, ItemLocation, bag, slot)

                    if ok and location then
                        local validOk, valid = pcall(location.IsValid, location)
                        if validOk and valid then return location end
                    end
                end
            end
        end
    end
end

--- Does the auction house sell this by the stack rather than as one listing?
--
-- This decides whether posting uses PostCommodity or PostItem, and getting it
-- wrong means the auction house declines the listing with no explanation.
--
-- On this client GetItemCommodityStatus takes an ItemLocation. An item ID, an
-- item link and an item key are all rejected with "bad argument #1", which a
-- pcall turns into a silent "not a commodity" for everything.
function Scanner:IsCommodity(itemID)
    local cached = commodityCache[itemID]
    if cached ~= nil then return cached end

    if not Util.HasFunction("C_AuctionHouse.GetItemCommodityStatus") then
        return false
    end

    local location = LocateInBags(itemID)
    if not location then
        -- Not held, so there is nothing to ask about. Deliberately not cached:
        -- the answer becomes available as soon as one is in your bags.
        return false
    end

    local ok, status = pcall(C_AuctionHouse.GetItemCommodityStatus, location)
    if not ok then
        ns.Warn("this client would not report commodity status; posting may use the wrong call.")
        return false
    end

    local result = (status == COMMODITY_STATUS)

    commodityCache[itemID] = result
    return result
end

--------------------------------------------------------------------------------
-- Full scan
--------------------------------------------------------------------------------

--- Whether a scan of any kind can run.
--
-- The bulk snapshot being rate limited is not a reason to refuse: browsing
-- is slower but always available, so the button should still work.
function Scanner:CanFullScan()
    if not self.isAuctionHouseOpen then
        return false, "the auction house must be open"
    end
    if self.isScanning then
        return false, "a scan is already running"
    end
    if self.scanQueued or self.browseQueued then
        return false, "a scan is already waiting its turn"
    end

    local caps = ns.Compat:Get().auction
    if not caps.hasReplicate and not caps.hasBrowseQuery then
        return false, "this client cannot scan the auction house"
    end

    return true
end

--- Seconds until the bulk snapshot is usable again, or nil if it is ready.
function Scanner:GetSnapshotCooldown()
    if not ns.Compat:Get().auction.hasReplicate then return nil end

    local last = ns.db and ns.db.lastReplicateRequest or 0
    local remaining = REPLICATE_COOLDOWN - (time() - last)

    return remaining > 0 and remaining or nil
end

function Scanner:StartFullScan()
    local allowed, reason = self:CanFullScan()
    if not allowed then
        ns.Print(reason)
        return false
    end

    self.scanStartedAt = GetTime()

    -- Snapshot when it is available, browse when it is not. Both end up in
    -- the same price database.
    local cooldown = self:GetSnapshotCooldown()
    if cooldown then
        ns.Print(("snapshot is rate limited for another %s -- browsing instead")
            :format(Util.FormatAge(cooldown)))
        return self:StartBrowseScan()
    end

    ns.db.lastReplicateRequest = time()

    ns.Print("requesting auction snapshot...")

    -- Queued rather than sent. A scan is the addon's heaviest use of a channel
    -- the player is also posting on, so it waits behind anything they clicked
    -- and behind Blizzard's own sell frame. isScanning is set when the request
    -- actually goes out, so a queued scan does not grey out the Post button.
    self.scanQueued = true

    ns.AHQueue:Request({
        name = "auction snapshot",
        key = "scan",
        priority = ns.AHQueue.PRIORITY.scan,
        expires = 60,

        send = function()
            Scanner.scanQueued = false
            Scanner.isScanning = true

            if not pcall(C_AuctionHouse.ReplicateItems) then
                ns.Print("the client refused the snapshot -- browsing instead")
                Scanner:StartBrowseScan()
                return true
            end

            -- ReplicateItems is throttled server-side to roughly once every
            -- fifteen minutes, and when it is on cooldown it does not answer at
            -- all -- no event, no error. Our own cooldown record can also be
            -- lost, so silence here is expected rather than exceptional. Fall
            -- back to browsing instead of leaving the player watching nothing.
            Scanner.timeoutHandle = C_Timer.NewTimer(6, function()
                if Scanner.isScanning and not Scanner.isReading then
                    ns.Print("snapshot did not answer (it is rate limited) -- browsing instead")
                    Scanner:StartBrowseScan()
                end
            end)

            return true
        end,

        onGiveUp = function()
            Scanner.scanQueued = false

            if not Scanner.isScanning then
                ns.Print("the auction house stayed busy; the scan was not sent.")
                if ns.UI then ns.UI:OnScanComplete() end
            end
        end,
    })

    return true
end

--------------------------------------------------------------------------------
-- Browse scan
--------------------------------------------------------------------------------

-- The paged fallback. It returns less per item than the bulk snapshot -- the
-- cheapest listing and the total quantity, rather than the whole order book --
-- but it is not rate limited, so it always works. Exact rival prices come from
-- the targeted search done before posting anyway.

function Scanner:StartBrowseScan()
    if self.isBrowsing or self.browseQueued then return false end

    if not Util.HasFunction("C_AuctionHouse.SendBrowseQuery") then
        self.isScanning = false
        ns.Warn("this client cannot browse the auction house either")
        return false
    end

    self.browsePages = 0
    self.browseRowsSeen = nil
    self.scanStartedAt = self.scanStartedAt or GetTime()

    -- isBrowsing is deliberately not set yet. It means "our browse query is out
    -- and the next results event is ours", and setting it while the request is
    -- still waiting its turn would make us read the player's own search as a
    -- scan -- and then page through it, one throttled request at a time.
    self.browseQueued = true

    ns.Print("browsing the auction house...")

    if self.verbose then
        -- A rejected event registration is silent and looks exactly like a
        -- hung scan, so state it up front.
        local unknown = ns.GetUnknownEvents()
        for _, event in ipairs({
            "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED",
            "AUCTION_HOUSE_BROWSE_RESULTS_ADDED",
        }) do
            ns.PrintRaw(("  %s: %s"):format(event,
                unknown[event] and "|cffe5604fREJECTED|r" or "|cff4fd18bregistered|r"))
        end
    end

    self:QueueBrowseQuery("", {
        onSend = function()
            Scanner.browseQueued = false
            Scanner.isScanning = true
            Scanner.isBrowsing = true
        end,

        onGiveUp = function()
            Scanner.browseQueued = false
            Scanner.isScanning = false
            Scanner.isBrowsing = false

            ns.Warn("the auction house stayed busy; the browse scan was not sent.")
            if ns.UI then ns.UI:OnScanComplete() end
        end,
    })

    return true
end

--- Send one browse query, paced, and start the no-answer timer when it goes.
--
-- The timeout is armed on send rather than on queue: a request still waiting its
-- turn has not failed to answer, and warning about it was how a polite wait
-- looked like a hung scan.
function Scanner:QueueBrowseQuery(searchString, opts)
    opts = opts or {}

    ns.AHQueue:Request({
        name = "browse query",
        key = "browse",
        priority = ns.AHQueue.PRIORITY.scan,
        expires = 60,
        onGiveUp = opts.onGiveUp,

        send = function()
            if opts.onSend then opts.onSend() end

            local ok = pcall(C_AuctionHouse.SendBrowseQuery, {
                searchString = searchString or "",
                sorts = {},
                filters = {},
                itemClassFilters = {},
                minLevel = 0,
                maxLevel = 0,
            })

            if not ok then
                ns.Warn("the client refused the browse query")
                return false
            end

            if Scanner.browseTimeout then Scanner.browseTimeout:Cancel() end

            Scanner.browseTimeout = C_Timer.NewTimer(15, function()
                Scanner.browseTimeout = nil

                if Scanner.isBrowsing then
                    Scanner.isScanning = false
                    Scanner.isBrowsing = false
                    Scanner.verbose = false

                    ns.Warn(("no browse response after 15s (%d page(s) seen)")
                        :format(Scanner.browsePages or 0))

                    -- Blizzard's own list is waiting on the same results we are,
                    -- so a query that never answered leaves its spinner turning.
                    Scanner:SettleSearchDisplay("the browse query did not answer")
                end
            end)

            return true
        end,
    })
end

function Scanner:Report(...)
    if self.verbose then
        ns.Print(...)
    else
        ns.Debug(...)
    end
end

function Scanner:OnBrowseResults()
    if not self.isBrowsing then
        -- Somebody else's query filled the shared results -- the player's own
        -- search, most likely. There is nothing of ours to page or to finish,
        -- but the rows are real prices and reading them is free.
        local learned = self:CapturePassiveBrowse()

        self:Report(("browse event arrived with no browse of ours running; learned %d price(s)")
            :format(learned))
        return
    end

    local ok, results = pcall(C_AuctionHouse.GetBrowseResults)
    if not ok or type(results) ~= "table" then
        self:Report("browse results could not be read")
        return
    end

    self:Report(("browse page %d: %d row(s)"):format(self.browsePages + 1, #results))

    -- Browse results accumulate across the pages of one query, so a set that has
    -- shrunk is not our sweep any more: a different query -- the player's own
    -- search, most likely -- has taken the shared results over. Paced paging made
    -- a sweep long enough for that to be likely, so take the smaller set as the
    -- end of ours rather than paging through somebody else's search.
    if self.browseRowsSeen and #results < self.browseRowsSeen then
        self:Report("browse results were replaced by another search; committing what we have")
        self:CommitBrowseResults(results)
        return
    end

    self.browseRowsSeen = #results
    self.browsePages = self.browsePages + 1

    local full = true
    if Util.HasFunction("C_AuctionHouse.HasFullBrowseResults") then
        local fullOk, hasFull = pcall(C_AuctionHouse.HasFullBrowseResults)
        full = (not fullOk) or hasFull
    end

    if not full and self.browsePages < MAX_BROWSE_PAGES then
        -- Results accumulate, so simply ask for the next page.
        if ns.UI and ns.UI.SetScanProgress then
            ns.UI:SetScanProgress(math.min(0.95, self.browsePages / 20))
        end

        -- Paced like everything else. This used to fire the instant each page
        -- landed, which is a request per server reply for as long as the sweep
        -- ran -- the single largest drain on an allowance the player's own
        -- posting needs a share of.
        ns.AHQueue:Request({
            name = "browse page",
            key = "browse-more",
            priority = ns.AHQueue.PRIORITY.scan,
            expires = 60,

            send = function()
                if not Scanner.isBrowsing then return true end
                return pcall(C_AuctionHouse.RequestMoreBrowseResults) and true or false
            end,

            onGiveUp = function()
                -- Commit what we have rather than abandon the sweep: a partial
                -- price update beats none, and it releases the shared results.
                if not Scanner.isBrowsing then return end

                local okResults, partial = pcall(C_AuctionHouse.GetBrowseResults)
                Scanner:CommitBrowseResults((okResults and type(partial) == "table") and partial or {})
            end,
        })
        return
    end

    self:CommitBrowseResults(results)
end

function Scanner:CommitBrowseResults(results)
    if self.browseTimeout then
        self.browseTimeout:Cancel()
        self.browseTimeout = nil
    end

    self.isBrowsing = false
    self.isScanning = false

    local recorded, skipped = 0, 0
    local now = time()

    for _, result in ipairs(results) do
        local itemID = result.itemKey and result.itemKey.itemID
        local price = result.minPrice

        if itemID and price and price > 0 then
            -- A browse row is one price, not a book, so market and minimum are
            -- the same figure here. containsOwnerItem is the only clue about
            -- whose listing it is: when it is yours, the cheapest rival is
            -- genuinely unknown rather than equal to this.
            --
            -- Spelled out in an if rather than `mine and nil or price`, which
            -- was here and does not work: `and` returning nil falls straight
            -- through to the `or`, so every row of your own recorded YOU as
            -- the cheapest rival -- and the next listing undercut it.
            local rivalMin, ownMin

            if result.containsOwnerItem == true then
                ownMin = price
            else
                rivalMin = price
            end

            ns.Prices:Record(itemID, price, price, result.totalQuantity or 0, now,
                rivalMin, ownMin)

            recorded = recorded + 1
        else
            skipped = skipped + 1
        end
    end

    if skipped > 0 then
        self:Report(("%d row(s) had no item id or price"):format(skipped))
    end

    self.verbose = false
    ns.db.lastFullScan = now

    local elapsed = GetTime() - (self.scanStartedAt or GetTime())
    ns.Print(("scan complete: %s items in %.1fs"):format(Util.Comma(recorded), elapsed))

    if ns.UI and ns.UI.OnScanComplete then
        ns.UI:OnScanComplete()
    end

    -- Written out rather than held until logout, because this client loses
    -- saved variables and a crash would cost the scan. Deferred, though:
    -- serialising the database and writing several large CVars in the frame
    -- a scan completes puts that work right where the client is busiest.
    if ns.Persist then ns.Persist:SaveLater() end
end

function Scanner:REPLICATE_ITEM_LIST_UPDATE()
    if not self.isScanning or self.isReading then return end

    if self.timeoutHandle then
        self.timeoutHandle:Cancel()
        self.timeoutHandle = nil
    end

    local ok, numItems = pcall(C_AuctionHouse.GetNumReplicateItems)
    if not ok or not numItems or numItems == 0 then
        ns.Print("snapshot came back empty -- browsing instead")
        self:StartBrowseScan()
        return
    end

    self:ReadReplicateResults(numItems)
end

--- Walk the snapshot, accumulating per-item listings.
function Scanner:ReadReplicateResults(numItems)
    self.isReading = true

    local observations = {}
    local skipped = 0

    -- GetReplicateItemInfo is 0-based.
    local indices = {}
    for i = 0, numItems - 1 do
        indices[i + 1] = i
    end

    local worker = Util.NewWorker({
        budgetMs = ns.Config:Get("scanBudgetMs") or 8,

        onItem = function(index)
            -- GetReplicateItemInfo returns, in order: name, texture, count,
            -- qualityID, usable, level, levelColHeader, minBid, minIncrement,
            -- buyoutPrice, bidAmount, highBidder, bidderFullName, owner,
            -- ownerFullName, saleStatus, itemID, hasAllInfo.
            local ok, _, _, count, _, _, _, _, _, _, buyoutPrice,
                  _, _, _, owner, ownerFullName, saleStatus, itemID =
                      pcall(C_AuctionHouse.GetReplicateItemInfo, index)

            if not ok or not itemID or not buyoutPrice or buyoutPrice <= 0 then
                skipped = skipped + 1
                return
            end

            -- saleStatus 1 means the auction already sold; it is not on offer.
            if saleStatus == 1 then
                skipped = skipped + 1
                return
            end

            local quantity = count or 1

            -- Commodities are priced per unit; item auctions quote the whole
            -- stack. Getting this backwards would scale every reagent cost by
            -- the stack size, so /bts verify cross-checks it against a targeted
            -- search rather than trusting the assumption.
            local unitPrice
            if self:IsCommodity(itemID) then
                unitPrice = buyoutPrice
            else
                unitPrice = Util.UnitPriceFromStack(itemID, buyoutPrice, quantity)
            end

            if unitPrice <= 0 then
                skipped = skipped + 1
                return
            end

            local listings = observations[itemID]
            if not listings then
                listings = {}
                observations[itemID] = listings
            end

            listings[#listings + 1] = {
                unitPrice = unitPrice,
                quantity = quantity,
                isOwn = self:IsOwnAuction(owner, ownerFullName),
            }
        end,

        onProgress = function(fraction)
            if ns.UI and ns.UI.SetScanProgress then
                ns.UI:SetScanProgress(fraction)
            end
        end,

        onDone = function()
            local recorded = ns.Prices:CommitScan(observations)
            local elapsed = GetTime() - (self.scanStartedAt or GetTime())

            self.isScanning = false
            self.isReading = false

            ns.Print(("scan complete: %s listings across %s items in %.1fs%s"):format(
                Util.Comma(numItems - skipped), Util.Comma(recorded), elapsed,
                skipped > 0 and (" (%s skipped)"):format(Util.Comma(skipped)) or ""))

            if ns.UI and ns.UI.OnScanComplete then
                ns.UI:OnScanComplete()
            end
        end,

        onCancel = function()
            self.isScanning = false
            self.isReading = false
            ns.Print("scan cancelled")

            if ns.UI and ns.UI.OnScanComplete then
                ns.UI:OnScanComplete()
            end
        end,
    })

    self.worker = worker
    worker:Start(indices)

    ns.Print(("reading %s listings..."):format(Util.Comma(numItems)))
end

function Scanner:CancelScan()
    if self.browseTimeout then
        self.browseTimeout:Cancel()
        self.browseTimeout = nil
    end

    if self.timeoutHandle then
        self.timeoutHandle:Cancel()
        self.timeoutHandle = nil
    end

    self.isBrowsing = false
    self.scanQueued = false
    self.browseQueued = false

    self:ClearSearchState()

    -- Anything of ours still waiting for a turn is no longer wanted, and a
    -- request sent after the player cancelled spends their allowance for nothing.
    if ns.AHQueue then
        ns.AHQueue:Cancel("scan", true)
        ns.AHQueue:Cancel("browse", true)
        ns.AHQueue:Cancel("browse-more", true)
    end

    if self.worker and self.worker:IsRunning() then
        self.worker:Cancel()
    else
        self.isScanning = false
        self.isReading = false

        if ns.UI then ns.UI:OnScanComplete() end
    end
end

function Scanner:GetProgress()
    if self.worker and self.worker:IsRunning() then
        return self.worker:GetProgress()
    end
    return nil
end

--------------------------------------------------------------------------------
-- Targeted scan
--------------------------------------------------------------------------------

-- A full snapshot gives breadth but only shallow depth per item. Before acting
-- on a specific item it is worth asking for its real order book.

function Scanner:ScanItem(itemID, callback)
    if not self.isAuctionHouseOpen then
        ns.Print("the auction house must be open")
        return false
    end

    local keyOk, itemKey = pcall(C_AuctionHouse.MakeItemKey, itemID)
    if not keyOk or not itemKey then
        ns.Warn(("could not build an item key for %s"):format(tostring(itemID)))
        return false
    end

    -- Asking again about something we just looked at spends throttle budget
    -- for an answer that has not changed.
    self.recentItemScans = self.recentItemScans or {}

    local last = self.recentItemScans[itemID]
    if last and (GetTime() - last) < 20 then
        -- Answered from a search made moments ago. That is still a checked
        -- price, not a check that failed to happen, and the caller is told
        -- which so it does not warn about a stale number that is not stale.
        if callback then callback(itemID, nil, nil, nil, nil, nil, "recent") end
        return true
    end

    -- A new search supersedes the old one, timer and all.
    self:ClearSearchState()

    self.pendingItem = { itemID = itemID, itemKey = itemKey, callback = callback }

    -- Urgent priority: this is only reached because the player clicked something
    -- and is waiting on the price, so it goes ahead of any background sweep, and
    -- it is the one kind of request allowed out while Blizzard's sell frame is
    -- open.
    Util.WhenAuctionReady(function()
        if not Scanner.pendingItem or Scanner.pendingItem.itemID ~= itemID then return end

        Scanner.recentItemScans[itemID] = GetTime()

        if not pcall(C_AuctionHouse.SendSearchQuery, itemKey, {}, true) then
            local refused = Scanner.pendingItem
            Scanner.pendingItem = nil

            ns.Warn("the client refused the search query")

            -- Say so now rather than leaving the caller to time out. A button
            -- that sits doing nothing for five seconds before admitting the
            -- check never happened reads as a broken button.
            if refused and refused.callback then
                refused.callback(itemID, nil, nil, nil, nil, nil, "unavailable")
            end
            return
        end

        -- Search results are one slot of client state shared with Blizzard's own
        -- lists, and nothing fires when a request is dropped. Without this the
        -- pending search stayed here for the rest of the session, and whatever
        -- was waiting on that state kept waiting with it.
        Scanner.searchTimeout = C_Timer.NewTimer(SEARCH_TIMEOUT, function()
            Scanner.searchTimeout = nil

            local pending = Scanner.pendingItem
            if not pending or pending.itemID ~= itemID then return end

            Scanner.pendingItem = nil

            -- Ask again next time rather than serving this silence as a checked
            -- price for the next twenty seconds.
            Scanner.recentItemScans[itemID] = nil

            ns.Warn("the auction house did not answer that search; using the last known price.")
            Scanner:SettleSearchDisplay("a search did not answer")

            if pending.callback then
                pending.callback(itemID, nil, nil, nil, nil, nil, "unavailable")
            end
        end)
    end, function()
        -- Never got a turn. Hand back what we already know rather than leaving
        -- the caller waiting forever.
        local pending = Scanner.pendingItem
        Scanner.pendingItem = nil

        ns.Warn("the auction house stayed busy; using the last known price.")
        if pending and pending.callback then
            pending.callback(itemID, nil, nil, nil, nil, nil, "unavailable")
        end
    end, {
        name = ("price check for %s"):format(Util.GetItemLabel(itemID)),
        key = "item-search",
        priority = ns.AHQueue.PRIORITY.urgent,
        expires = 6,
    })

    return true
end

--------------------------------------------------------------------------------
-- Passive capture
--------------------------------------------------------------------------------

-- Auction house results are one piece of shared client state, and the events
-- that announce them are not addressed to whoever asked. When the player types
-- into Blizzard's own search box, or clicks a row in its list, exactly the same
-- events fire and exactly the same getters answer -- so the prices they found
-- can be read straight out, for no request and no throttle budget at all.
--
-- The addon used to drop all of that on the floor, because the handlers began
-- by checking the results were its own. They still do; this is what happens
-- instead of the early return.
--
-- Two rules keep it safe:
--
--  * It never sends anything. Paging through somebody else's search is what
--    the old early returns were really guarding against, and passive capture
--    reads whatever has already arrived and stops there.
--  * It never records an empty answer. A targeted search of ours coming back
--    empty is information -- nothing is listed, so there is nobody to undercut
--    -- but an empty shared results set is just as likely to be a set that was
--    cleared for the next query. Clearing a real rival price on that guess is
--    how the addon would talk itself into listing far under value, so a
--    passive observation may only ever add a price, never remove one.

-- The same rows arrive several times over as a search fills in, and a browse
-- of the whole house repeats every item the player scrolls past. Recording a
-- price we already hold at the same figure only pushes the moving average
-- toward a number it is already at and fills the history with copies, so the
-- same price for the same item is ignored for this long.
local PASSIVE_REPEAT_SECONDS = 60

-- How many of the most recent captures `/bts learned` shows.
local PASSIVE_RECENT = 8

function Scanner:PassiveCaptureEnabled()
    return ns.Config:Get("learnFromSearches") ~= false
end

--- Record one price observed from a search the addon did not make.
--
-- Returns true only when the database actually changed, so callers can report
-- what happened rather than what was attempted.
function Scanner:RecordPassive(itemID, marketValue, minBuyout, quantity, rivalMin, ownMin)
    if not itemID or not marketValue or marketValue <= 0 then return false end

    self.passiveSeen = self.passiveSeen or {}

    local now = GetTime()
    local seen = self.passiveSeen[itemID]

    if seen and seen.price == marketValue and (now - seen.at) < PASSIVE_REPEAT_SECONDS then
        return false
    end

    self.passiveSeen[itemID] = { at = now, price = marketValue }

    ns.Prices:Record(itemID, marketValue, minBuyout, quantity or 0, time(), rivalMin, ownMin)

    self.passiveCount = (self.passiveCount or 0) + 1

    self.passiveItems = self.passiveItems or {}
    if not self.passiveItems[itemID] then
        self.passiveItems[itemID] = true
        self.passiveItemCount = (self.passiveItemCount or 0) + 1
    end

    self.passiveRecent = self.passiveRecent or {}
    table.insert(self.passiveRecent, 1, {
        itemID = itemID,
        price = minBuyout or marketValue,
        at = time(),
    })
    while #self.passiveRecent > PASSIVE_RECENT do
        table.remove(self.passiveRecent)
    end

    return true
end

--- Read the shared browse results after somebody else's query filled them.
function Scanner:CapturePassiveBrowse()
    if not self:PassiveCaptureEnabled() then return 0 end
    if not Util.HasFunction("C_AuctionHouse.GetBrowseResults") then return 0 end

    local ok, results = pcall(C_AuctionHouse.GetBrowseResults)
    if not ok or type(results) ~= "table" then return 0 end

    local learned = 0

    for _, result in ipairs(results) do
        local itemID = result.itemKey and result.itemKey.itemID
        local price = result.minPrice

        if itemID and price and price > 0 then
            -- One price per row, not a book, so market and minimum are the
            -- same figure -- the same reading CommitBrowseResults makes of the
            -- same rows, ownership included.
            local rivalMin, ownMin

            if result.containsOwnerItem == true then
                ownMin = price
            else
                rivalMin = price
            end

            if self:RecordPassive(itemID, price, price, result.totalQuantity or 0,
                rivalMin, ownMin) then
                learned = learned + 1
            end
        end
    end

    if learned > 0 and ns.Persist then ns.Persist:SaveLater() end

    return learned
end

--- Record the order book of a search the player ran on a single item.
function Scanner:CapturePassiveListings(itemID, listings)
    if not self:PassiveCaptureEnabled() then return false end

    -- Empty is not recorded; see the rules above.
    if not listings or #listings == 0 then return false end

    local marketValue, minBuyout, quantity, rivalMin, ownMin = ns.Prices:Summarise(listings)
    if not marketValue then return false end

    local learned = self:RecordPassive(itemID, marketValue, minBuyout, quantity, rivalMin, ownMin)

    if learned and ns.Persist then ns.Persist:SaveLater() end

    return learned
end

--------------------------------------------------------------------------------
-- Shared search state
--------------------------------------------------------------------------------

-- Browse and search results are one set of client state, shared with Blizzard's
-- auction house frame. Whichever query was sent last owns it, so our price check
-- and Blizzard's sell-tab search overwrite each other -- and a query dropped by
-- the throttle leaves whatever was waiting on that state waiting for ever. Hence
-- both halves of this: never leave a request of ours pending, and when one does
-- go missing, settle the shared state on the way out.

--- Forget any search of ours that is in flight, timer included.
function Scanner:ClearSearchState()
    if self.searchTimeout then
        self.searchTimeout:Cancel()
        self.searchTimeout = nil
    end

    self.pendingItem = nil
end

--- What the player has typed into Blizzard's search box, if it can be read.
local function GetBlizzardSearchText()
    local frame = _G.AuctionHouseFrame
    if type(frame) ~= "table" then return nil end

    local bar = frame.SearchBar
    local box = type(bar) == "table" and bar.SearchBox

    if type(box) ~= "table" or type(box.GetText) ~= "function" then return nil end

    local ok, text = pcall(box.GetText, box)
    return ok and text or nil
end

--- Put the shared browse state back into a finished condition.
--
-- Blizzard's list shows its searching indicator for exactly as long as
-- HasFullBrowseResults reports false, and nothing else will ever set that true
-- if the query it was waiting on got dropped. So when the auction house is open
-- and that state is still unfinished after a request of ours went missing, send
-- one more query -- the player's own search text where it can be read -- so a
-- results event actually arrives and the indicator clears.
--
-- Once per visit to the auction house: this is a repair, and a repair that
-- retries is just the loop that caused the problem.
function Scanner:SettleSearchDisplay(reason)
    if not self.isAuctionHouseOpen then return false end
    if self.settledSearchDisplay then return false end

    if not Util.HasFunction("C_AuctionHouse.HasFullBrowseResults") then return false end

    local ok, hasFull = pcall(C_AuctionHouse.HasFullBrowseResults)
    if not ok or hasFull then return false end

    self.settledSearchDisplay = true

    ns.Debug(("settling the auction house search display: %s"):format(
        reason or "no reason given"))

    -- No onSend, so isBrowsing stays false and OnBrowseResults treats what
    -- comes back as somebody else's results rather than a page of a sweep. That
    -- is the intent: this query exists to let the client finish a search it is
    -- stuck on, and it must not restart paging. Passive capture will read the
    -- rows it returns, which is a bonus and not the reason for sending it.
    self:QueueBrowseQuery(GetBlizzardSearchText() or "")

    return true
end

function Scanner:COMMODITY_SEARCH_RESULTS_UPDATED(_, itemID)
    if not itemID then return end

    local pending = self.pendingItem
    local ours = pending ~= nil and pending.itemID == itemID

    -- Not ours, and not wanted: leave the results alone exactly as before.
    if not ours and not self:PassiveCaptureEnabled() then return end

    local listings = {}
    local ok, count = pcall(C_AuctionHouse.GetNumCommoditySearchResults, itemID)

    if ok and count then
        for i = 1, count do
            local infoOk, info = pcall(C_AuctionHouse.GetCommoditySearchResultInfo, itemID, i)
            if infoOk and info and info.unitPrice then
                listings[#listings + 1] = {
                    unitPrice = info.unitPrice,
                    quantity = info.quantity or 1,
                    isOwn = info.containsOwnerItem == true,
                }
            end
        end
    end

    if not ours then
        self:CapturePassiveListings(itemID, listings)
        return
    end

    self:FinishItemScan(itemID, listings, true)
end

function Scanner:ITEM_SEARCH_RESULTS_UPDATED(_, itemKey)
    local pending = self.pendingItem

    -- An event with no key at all can only be read as an answer to whatever we
    -- asked about last; one that carries a key speaks for itself.
    local ours = pending ~= nil
        and (type(itemKey) ~= "table" or itemKey.itemID == nil or itemKey.itemID == pending.itemID)

    -- Read the book with the key that describes it: ours when it is our search,
    -- the event's own otherwise. The getters take the key, not the item id, so
    -- without one there is nothing to read.
    local key = ours and pending.itemKey or itemKey
    if type(key) ~= "table" then return end

    local itemID = key.itemID or (ours and pending.itemID)
    if not itemID then return end

    if not ours and not self:PassiveCaptureEnabled() then return end

    local listings = {}
    local raw = {}

    local ok, count = pcall(C_AuctionHouse.GetNumItemSearchResults, key)

    if ok and count then
        for i = 1, count do
            local infoOk, info = pcall(C_AuctionHouse.GetItemSearchResultInfo, key, i)
            if infoOk and info and info.buyoutAmount and info.buyoutAmount > 0 then
                local quantity = info.quantity or 1
                local unitPrice = Util.UnitPriceFromStack(itemID, info.buyoutAmount, quantity)

                -- Kept as the client gave them, so `/bts listings` can show
                -- what was read rather than what was concluded from it.
                raw[#raw + 1] = {
                    buyoutAmount = info.buyoutAmount,
                    quantity = quantity,
                    maxStack = Util.GetMaxStackSize(itemID),
                    unitPrice = unitPrice,
                }

                listings[#listings + 1] = {
                    unitPrice = unitPrice,
                    quantity = quantity,
                    isOwn = info.containsOwnerItem == true,
                }
            end
        end
    end

    self.lastItemListings = { itemID = itemID, raw = raw }

    if not ours then
        self:CapturePassiveListings(itemID, listings)
        return
    end

    self:FinishItemScan(itemID, listings, false)
end

function Scanner:FinishItemScan(itemID, listings, isCommodity)
    local pending = self.pendingItem
    self.pendingItem = nil

    local marketValue, minBuyout, quantity, rivalMin, ownMin = ns.Prices:Summarise(listings)

    -- "fresh" and "empty" both mean the auction house answered. They are told
    -- apart because an empty answer is information -- there is nothing listed
    -- -- while no answer at all leaves us on old data.
    local status = "fresh"

    if marketValue then
        ns.Prices:Record(itemID, marketValue, minBuyout, quantity, nil, rivalMin, ownMin)
    else
        -- The search came back with nothing in it. Recording that is the whole
        -- point of asking: it clears the rival price, so the next listing
        -- cannot undercut a seller who has already sold out or expired.
        status = "empty"
        ns.Prices:RecordEmpty(itemID)
    end

    if pending and pending.callback then
        pending.callback(itemID, marketValue, minBuyout, quantity, isCommodity,
            listings, status)
    end
end

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------

function Scanner:AUCTION_HOUSE_SHOW()
    self.isAuctionHouseOpen = true
    self.settledSearchDisplay = false

    -- Give the auction house a moment to be ready for queries. Longer than it
    -- strictly needs, on purpose: the player often opens the house to post
    -- something, and a sweep starting underneath their first click is how their
    -- own listing ended up refused for going too fast.
    C_Timer.After(3, function() Scanner:ConsiderAutoScan() end)
end

--- Scan without being asked when there is nothing useful to work from.
--
-- The Forever beta can start a session with no saved data at all. Rather
-- than leave the addon looking broken until the player finds the Scan
-- button, rebuild the price database on the spot. A full sweep is one
-- request and a read loop, so this costs seconds, not minutes.
function Scanner:ConsiderAutoScan(attempt)
    if ns.Config:Get("autoScan") == false then return end
    if self.isScanning or self.scanQueued then return end

    -- Queueing behind the sell frame would also work, but then a scan nobody
    -- asked for sits in the queue until it expires. Come back later instead, and
    -- give up quietly if the player is selling the whole time.
    attempt = attempt or 1

    if ns.AHQueue:PlayerIsSelling() then
        if attempt > 4 then return end

        ns.Debug("deferring the automatic scan: the sell frame is open")
        C_Timer.After(20, function() Scanner:ConsiderAutoScan(attempt + 1) end)
        return
    end

    local allowed = self:CanFullScan()
    if not allowed then return end

    local count = ns.Prices:Count()
    local lastScan = ns.db and ns.db.lastFullScan
    local stale = not lastScan
        or (time() - lastScan) > (ns.Config:Get("staleAfterSeconds") or 172800)

    if count > 0 and not stale then return end

    ns.Print(count == 0
        and "no price data -- scanning automatically"
        or "price data is stale -- scanning automatically")

    self:StartFullScan()
end

function Scanner:AUCTION_HOUSE_CLOSED()
    self.isAuctionHouseOpen = false
    self.settledSearchDisplay = false
    self:CancelScan()
end

function Scanner:OnEnable()
    ns.RegisterEvent(self, "AUCTION_HOUSE_SHOW", self.AUCTION_HOUSE_SHOW)
    ns.RegisterEvent(self, "AUCTION_HOUSE_CLOSED", self.AUCTION_HOUSE_CLOSED)
    ns.RegisterEvent(self, "REPLICATE_ITEM_LIST_UPDATE", self.REPLICATE_ITEM_LIST_UPDATE)

    -- Browse results arrive as either event depending on whether this is a
    -- fresh query or another page of one.
    ns.RegisterEvent(self, "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED", self.OnBrowseResults)
    ns.RegisterEvent(self, "AUCTION_HOUSE_BROWSE_RESULTS_ADDED", self.OnBrowseResults)
    ns.RegisterEvent(self, "COMMODITY_SEARCH_RESULTS_UPDATED", self.COMMODITY_SEARCH_RESULTS_UPDATED)
    ns.RegisterEvent(self, "ITEM_SEARCH_RESULTS_UPDATED", self.ITEM_SEARCH_RESULTS_UPDATED)
end

--------------------------------------------------------------------------------
-- Commands
--------------------------------------------------------------------------------

ns.RegisterCommand("scan", "scan the auction house (open it first)", function()
    ns.Scanner:StartFullScan()
end)

ns.RegisterCommand("cancel", "stop the running scan", function()
    ns.Scanner:CancelScan()
end)

-- Forces the paged path, skipping the rate-limited snapshot entirely. Useful
-- when the snapshot is unavailable and for testing the fallback on its own.
ns.RegisterCommand("browse", "scan by browsing, skipping the bulk snapshot", function()
    if not ns.Scanner.isAuctionHouseOpen then
        ns.Print("the auction house must be open")
        return
    end

    ns.Scanner:CancelScan()
    ns.Scanner.scanStartedAt = GetTime()
    ns.Scanner.verbose = true
    ns.Scanner:StartBrowseScan()
end)

-- Proves, rather than assumes, that the bulk snapshot's prices are being read
-- with the right units: a targeted search is authoritative, so if the two
-- disagree the snapshot maths is wrong.
ns.RegisterCommand("listings", "what the last price check actually read back", function()
    local last = ns.Scanner.lastItemListings

    if not last or not last.raw or #last.raw == 0 then
        ns.Print("no item search has come back yet -- click List on something first")
        return
    end

    ns.Print(("what the auction house said about %s"):format(Util.GetItemLabel(last.itemID)))

    for i = 1, math.min(#last.raw, 10) do
        local entry = last.raw[i]

        -- A quantity above the stack size is the misreport worth seeing: it is
        -- the total on offer, not this listing's stack, and dividing by it is
        -- what priced a Linen Bag at one copper.
        local suspect = entry.maxStack and entry.quantity > entry.maxStack

        ns.PrintRaw(("  %2d. buyout %s  qty %d  stacks to %s  -> %s each%s"):format(
            i,
            Util.FormatMoney(entry.buyoutAmount, { noColor = true }),
            entry.quantity,
            entry.maxStack and tostring(entry.maxStack) or "unknown",
            Util.FormatMoney(entry.unitPrice, { noColor = true }),
            suspect and "  <-- qty is not a stack, so not divided" or ""))
    end

    if #last.raw > 10 then
        ns.PrintRaw(("  ... and %d more"):format(#last.raw - 10))
    end
end)

ns.RegisterCommand("verify", "<itemID> -- cross-check snapshot price against a live search", function(args)
    local itemID = tonumber(args:match("(%d+)"))
    if not itemID then
        ns.Print("usage: /bts verify <itemID>")
        return
    end

    local before = ns.Prices:Get(itemID)
    local snapshotMarket = before and before.market
    local snapshotMin = before and before.min

    ns.Print(("verifying item %d against a live search..."):format(itemID))

    ns.Scanner:ScanItem(itemID, function(_, marketValue, minBuyout, quantity, isCommodity)
        if not marketValue then
            ns.Warn("no live listings found for that item")
            return
        end

        ns.PrintRaw(("  live:     market %s   min %s   qty %d   %s"):format(
            Util.FormatMoney(marketValue), Util.FormatMoney(minBuyout), quantity or 0,
            isCommodity and "commodity" or "item auction"))

        if snapshotMin then
            ns.PrintRaw(("  snapshot: market %s   min %s"):format(
                Util.FormatMoney(snapshotMarket), Util.FormatMoney(snapshotMin)))

            local ratio = minBuyout > 0 and (snapshotMin / minBuyout) or 0
            if ratio > 0.9 and ratio < 1.1 then
                ns.PrintRaw(("  |c%sunits agree|r"):format(ns.COLORS.profit))
            else
                ns.PrintRaw(("  |c%sMISMATCH -- snapshot is %.2fx the live price|r"):format(
                    ns.COLORS.loss, ratio))
            end
        else
            ns.PrintRaw("  no snapshot data yet; run /bts scan first to compare")
        end
    end)
end)

-- Reports the OUTCOME of passive capture, not that it is switched on: how many
-- prices this session actually took from searches the addon did not make, and
-- which items they were. A diagnostic that says "enabled" would have been true
-- the whole time the handlers were dropping every row on the floor.
ns.RegisterCommand("learned", "prices picked up from your own auction house searches", function()
    local Scanner = ns.Scanner

    if not Scanner:PassiveCaptureEnabled() then
        ns.Print("learning from your searches is turned off in Settings -> Advanced")
        return
    end

    local count = Scanner.passiveCount or 0

    if count == 0 then
        ns.Print("no prices learned from your searches yet this session")

        if not Scanner.isAuctionHouseOpen then
            ns.PrintRaw("  the auction house is closed; search for something with it open")
        else
            ns.PrintRaw("  type in the auction house search box and run this again")
        end
        return
    end

    ns.Print(("%s price update%s from %s item%s, learned from your own searches"):format(
        Util.Comma(count), count == 1 and "" or "s",
        Util.Comma(Scanner.passiveItemCount or 0),
        (Scanner.passiveItemCount or 0) == 1 and "" or "s"))

    for _, entry in ipairs(Scanner.passiveRecent or {}) do
        ns.PrintRaw(("  %s  %s  %s"):format(
            Util.GetItemLabel(entry.itemID),
            Util.FormatMoney(entry.price, { noColor = true }),
            Util.FormatAgeAgo(time() - entry.at)))
    end
end)
