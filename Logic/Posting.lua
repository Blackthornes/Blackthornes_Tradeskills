-- Blackthornes Tradeskills -- Logic/Posting.lua
-- What to sell, at what price, and listing it.
--
-- Posting is the one part of the addon that can lose gold outright, so it is
-- deliberately the least automatic: one click per listing, the price on the
-- button before it is pressed, and a refusal to list below material cost
-- unless you allow it.
--
-- Success is verified against your actual auctions rather than assumed from
-- an event, because AUCTION_HOUSE_AUCTION_CREATED fires for anything -- a
-- listing you made by hand included -- and claiming credit for that is worse
-- than reporting nothing. The Post tab also shows the price split into
-- Blizzard's gold/silver/copper boxes, so listing by hand stays easy when the
-- auction house is misbehaving.

local _, ns = ...

local Posting = ns.NewModule("Posting")

local Util = ns.Util

local BACKPACK, LAST_BAG = 0, 4

-- How long to wait before asking the server what actually got listed. The
-- auction house is throttled and the reply can lag several seconds, so asking
-- immediately reads the state from before the listing.
local POST_VERIFY_DELAY = 3

-- How long a listing may stay unverified before we admit we do not know. Longer
-- than the request's own wait in the queue plus the reads that follow it.
local VERIFY_GIVE_UP = 15

-- Confirmed against Blizzard's own Sell tab on Forever, which offers 2, 8 and
-- 24 hours: this is a Classic auction house, not retail's 12/24/48. The choice
-- only affects the deposit estimate, since the listing is made by hand.
local DURATIONS = {
    { text = "2 hours", value = 1 },
    { text = "8 hours", value = 2 },
    { text = "24 hours", value = 3 },
}

Posting.DURATIONS = DURATIONS

--------------------------------------------------------------------------------
-- Capability
--------------------------------------------------------------------------------

--- True once this client has been *seen* refusing an addon-created auction.
--
-- Deliberately not inferred from issecurevariable: that reports whether a
-- variable is untainted, which is true of nearly every Blizzard function an
-- addon has not overwritten, and says nothing about whether calling it is
-- allowed. Reading it as proof of protection was a mistake that removed a
-- working feature.
function Posting:IsBlocked()
    return self.blocked == true
end

--- Record that the client refused an auction started from addon code.
function Posting:MarkBlocked()
    if self.blocked then return end

    self.blocked = true
    ns.Warn("this client refused an addon-created auction.")
    ns.Warn("the Post tab still shows what to list and at what price.")

    if ns.UI then ns.UI:RefreshActiveTab() end
end

--- Whether a listing can be attempted right now, and why not when it cannot.
function Posting:CanPost()
    if self:IsBlocked() then
        return false, "this client refuses addon-created auctions"
    end

    if not ns.Scanner.isAuctionHouseOpen then
        return false, "the auction house must be open"
    end

    if ns.Scanner.isScanning then
        return false, "wait for the scan to finish"
    end

    -- Restored as a real gate. It was demoted to advisory to unstick a button
    -- that never re-checked it, and the cost of that was our own traffic
    -- pushing the auction house into "You're doing that too fast" -- which
    -- blocks the player's own manual listings, not just ours. The one-second
    -- ticker now re-checks this, so a refusal here clears on its own.
    if self:IsThrottled() then
        return false, "the auction house is busy -- a moment"
    end

    return true
end

--- Is the auction house still catching up?
--
-- Advisory, not a block. A request sent while throttled can be dropped
-- silently, but this client can sit unready for a long time, and refusing to
-- even try leaves a button that never works and never says why. The listing
-- is verified against the server afterwards either way, so a dropped one is
-- reported rather than assumed successful.
function Posting:IsThrottled()
    if not Util.HasFunction("C_AuctionHouse.IsThrottledMessageSystemReady") then
        return false
    end

    local ok, ready = pcall(C_AuctionHouse.IsThrottledMessageSystemReady)
    return ok and not ready
end

--- Whether live prices and deposits are available, and why not when they are not.
function Posting:CanPrice()
    if not ns.Scanner.isAuctionHouseOpen then
        return false, "open the auction house for deposits and live prices"
    end
    return true
end

--------------------------------------------------------------------------------
-- Finding stock
--------------------------------------------------------------------------------

--- Bag slot holding an item, skipping locked slots.
-- @return bag, slot, stackCount
local function FindInBags(itemID)
    for bag = BACKPACK, LAST_BAG do
        local slotsOk, slots = pcall(C_Container.GetContainerNumSlots, bag)

        if slotsOk and slots then
            for slot = 1, slots do
                local infoOk, info = pcall(C_Container.GetContainerItemInfo, bag, slot)

                if infoOk and info and info.itemID == itemID and not info.isLocked then
                    return bag, slot, info.stackCount or 1
                end
            end
        end
    end
end

--- A validated ItemLocation for a bag slot, or nil.
--
-- IsValid matters: a location built from a slot that has since changed still
-- looks like an object but points at nothing, and the client does float maths
-- on these in CalculateItemDeposit and IsSellItemValid.
local function MakeLocation(bag, slot)
    if type(_G.ItemLocation) ~= "table" then return nil end

    local ok, location = pcall(ItemLocation.CreateFromBagAndSlot, ItemLocation, bag, slot)
    if not ok or not location then return nil end

    local validOk, valid = pcall(location.IsValid, location)
    if not validOk or not valid then return nil end

    return location
end

--- Can this item be auctioned at all, and how many of it?
--
-- These take an ItemLocation and read the auction house's sell state, which
-- was investigated as a cause of Blizzard's own Sell tab failing with
-- "Internal auction error". It was ruled out: the error occurs with this addon
-- disabled entirely, so it is a realm-side problem and these calls are safe.
-- @return sellable, postableCount
function Posting:GetSellInfo(itemID)
    local bag, slot = FindInBags(itemID)
    if not bag then return false, 0 end

    local location = MakeLocation(bag, slot)
    if not location then return false, 0 end

    local sellable = true
    if Util.HasFunction("C_AuctionHouse.IsSellItemValid") then
        local ok, valid = pcall(C_AuctionHouse.IsSellItemValid, location, false)
        if ok then sellable = valid and true or false end
    end

    local count = ns.Inventory:GetBagCount(itemID)
    if Util.HasFunction("C_AuctionHouse.GetAvailablePostCount") then
        local ok, available = pcall(C_AuctionHouse.GetAvailablePostCount, location)
        if ok and available then count = available end
    end

    return sellable, count
end

--------------------------------------------------------------------------------
-- Pricing
--------------------------------------------------------------------------------

--- The price to list one unit at, and why.
-- @return price, basis  -- basis is "undercut", "market" or nil
function Posting:GetPostPrice(itemID)
    local rival = ns.Prices:GetValue(itemID, "rival")
    local undercut = ns.Config:Get("undercutCopper") or 1

    -- "rival" excludes your own auctions, so listing a second one does not
    -- undercut the first.
    if rival then
        return math.max(1, math.floor(rival - undercut)), "undercut"
    end

    local market = ns.Prices:GetValue(itemID, "market")
    if market then
        return math.max(1, math.floor(market)), "market"
    end

    return nil, nil
end

--------------------------------------------------------------------------------
-- Deposits
--------------------------------------------------------------------------------

--- Deposit per unit, remembered from the last time it could be calculated.
--
-- The client only works deposits out at the auction house, but profit has to
-- account for them everywhere.
function Posting:GetCachedUnitDeposit(itemID)
    if not ns.db or not itemID then return nil end

    local record = ns.db.deposits and ns.db.deposits[itemID]
    if not record then return nil end

    -- A deposit quoted for a different listing length is not this one.
    if record.duration ~= (ns.Config:Get("postDuration") or 2) then return nil end

    return record.unit
end

function Posting:CacheUnitDeposit(itemID, deposit, quantity, duration)
    if not ns.db or not itemID or not deposit or deposit <= 0 then return end

    ns.db.deposits = ns.db.deposits or {}
    ns.db.deposits[itemID] = {
        unit = math.floor(deposit / math.max(1, quantity or 1)),
        duration = duration,
        at = time(),
    }
end

function Posting:GetDeposit(itemID, quantity)
    -- Away from an auction house the cached figure is the only honest answer.
    if not ns.Scanner.isAuctionHouseOpen then
        local unit = self:GetCachedUnitDeposit(itemID)
        return unit and (unit * math.max(1, quantity or 1)) or nil
    end

    local duration = ns.Config:Get("postDuration") or 2

    if ns.Scanner:IsCommodity(itemID) then
        if Util.HasFunction("C_AuctionHouse.CalculateCommodityDeposit") then
            local ok, deposit = pcall(C_AuctionHouse.CalculateCommodityDeposit,
                itemID, duration, quantity)

            if ok and deposit then
                self:CacheUnitDeposit(itemID, deposit, quantity, duration)
                return deposit
            end
        end
        return nil
    end

    if Util.HasFunction("C_AuctionHouse.CalculateItemDeposit") then
        local bag, slot = FindInBags(itemID)
        local location = bag and MakeLocation(bag, slot)

        if location then
            local ok, deposit = pcall(C_AuctionHouse.CalculateItemDeposit,
                location, duration, quantity)

            if ok and deposit then
                self:CacheUnitDeposit(itemID, deposit, quantity, duration)
                return deposit
            end
        end
    end

    return nil
end

--------------------------------------------------------------------------------
-- What to list
--------------------------------------------------------------------------------

--- Everything in your bags that one of your recipes makes.
--
-- Restricted to crafted output on purpose: this is a crafting addon, and
-- offering to sell arbitrary bag contents invites expensive mistakes.
--- Items in your bags worth listing.
--
-- @param opts { includeAll } -- by default only what your recipes make.
--   includeAll covers everything sellable with a known price, which is what
--   the Post All button wants: bag clearing, not just crafted stock.
--- The lowest a listing may go before it costs the player something, and why.
--
-- Two different floors, and the higher one wins.
--
-- Material cost is the obvious one, but it only exists for things made from a
-- recipe this account knows. Everything else in a player's bags -- gathered
-- mats, drops, vendor trash -- has no cost to compare against, and that was the
-- bug: `price < unitCost` cannot be true when unitCost is nil, so those lines
-- were never flagged however little they were about to sell for.
--
-- What a vendor pays is the floor that always exists. Listing below it is worse
-- than walking to a vendor, before the auction house takes its cut or keeps the
-- deposit on a listing nobody wants at that price either.
--
-- @return floor   copper, or nil if neither is known
-- @return reason  "cost" or "vendor", naming which floor applies
-- @return vendor  the vendor price itself, for display
function Posting:GetLossFloor(itemID, unitCost)
    local vendorPrice = Util.GetVendorSellPrice(itemID)

    local floor, reason = unitCost, unitCost and "cost" or nil

    if vendorPrice and (not floor or vendorPrice > floor) then
        floor, reason = vendorPrice, "vendor"
    end

    return floor, reason, vendorPrice
end

function Posting:GetPostable(opts)
    opts = opts or {}

    local outputs = {}

    for _, recipe in pairs(ns.Recipes:GetAccountWide()) do
        if recipe.outputItemID then
            outputs[recipe.outputItemID] = recipe.recipeID
        end
    end

    -- Never offer to sell what a queued craft is waiting on. Listing your
    -- own reagents is the one mistake here that costs real work to undo.
    local reserved = {}

    if opts.includeAll then
        for _, entry in ipairs(ns.Queue:GetShoppingList() or {}) do
            if entry.itemID then reserved[entry.itemID] = true end
        end
    end

    local lines = {}
    local seen = {}

    for bag = BACKPACK, LAST_BAG do
        local slotsOk, slots = pcall(C_Container.GetContainerNumSlots, bag)

        if slotsOk and slots then
            for slot = 1, slots do
                local infoOk, info = pcall(C_Container.GetContainerItemInfo, bag, slot)
                local itemID = infoOk and info and info.itemID

                local wanted = outputs[itemID] ~= nil
                    or (opts.includeAll and not reserved[itemID])

                if itemID and wanted and not seen[itemID] then
                    seen[itemID] = true

                    local sellable, count = self:GetSellInfo(itemID)
                    local price, basis = self:GetPostPrice(itemID)

                    -- What it cost to make one, so a listing below that can be
                    -- flagged rather than quietly recommended.
                    local analysis = outputs[itemID]
                        and ns.Profit:Analyse(outputs[itemID])
                    local unitCost = analysis and analysis.costPerUnit

                    local lossFloor, lossReason, vendorPrice =
                        self:GetLossFloor(itemID, unitCost)

                    local isCommodity = ns.Scanner:IsCommodity(itemID)

                    -- Commodities sell from across the bags at once; item
                    -- auctions come from a single slot, so gear goes up one
                    -- listing at a time.
                    local _, _, slotStack = FindInBags(itemID)
                    local postQuantity = isCommodity
                        and count
                        or math.min(count, slotStack or 1)

                    -- Without a price there is nothing to list it at, and a
                    -- guess on someone's bag contents is worse than a skip.
                    if sellable and count > 0 and (price or not opts.includeAll) then
                        lines[#lines + 1] = {
                            itemID = itemID,
                            recipeID = outputs[itemID],
                            count = count,
                            unitPrice = price,
                            priceBasis = basis,
                            unitCost = unitCost,
                            vendorPrice = vendorPrice,
                            lossFloor = lossFloor,
                            lossReason = lossReason,
                            atALoss = price ~= nil and lossFloor ~= nil
                                and price < lossFloor,
                            postQuantity = postQuantity,
                            total = price and (price * count) or nil,
                            postTotal = price and (price * postQuantity) or nil,
                            deposit = self:GetDeposit(itemID, postQuantity),
                            isCommodity = isCommodity,
                            label = Util.GetItemLabel(itemID),
                        }
                    end
                end
            end
        end
    end

    table.sort(lines, function(a, b)
        return (a.total or 0) > (b.total or 0)
    end)

    return lines
end

--- The most valuable stack worth listing right now.
--
-- Skips anything unpriced, and anything that would sell below material cost
-- unless losses are explicitly allowed.
function Posting:GetNextPostable(opts)
    local allowLoss = ns.Config:Get("allowPostingAtALoss") == true

    for _, line in ipairs(self:GetPostable(opts)) do
        if line.unitPrice and (allowLoss or not line.atALoss) then
            return line
        end
    end
end

--- Count and total value of everything worth listing.
function Posting:GetSummary(opts)
    local allowLoss = ns.Config:Get("allowPostingAtALoss") == true

    local count, total = 0, 0
    for _, line in ipairs(self:GetPostable(opts)) do
        if line.unitPrice and (allowLoss or not line.atALoss) then
            count = count + 1
            total = total + (line.total or 0)
        end
    end

    return count, total
end

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------

function Posting:OnEnable()
    if self:IsBlocked() then
        ns.Debug("addon posting is blocked on this client; running as a price helper")
    end

    -- Listing something by hand changes what is left to list, and what counts
    -- against your posted-stock limits.
    ns.RegisterEvent(self, "AUCTION_HOUSE_AUCTION_CREATED", function()
        ns.Auctions:Refresh()

        if ns.UI then
            ns.UI:RefreshActiveTab()
            ns.UI:UpdatePostButton()
        end
    end)
end

--------------------------------------------------------------------------------
-- Diagnostics
--------------------------------------------------------------------------------

-- Kept because the answer is not obvious and the symptoms mislead: a protected
-- call returns without error and simply does nothing.
ns.RegisterCommand("taint", "report whether addons may call protected functions", function()
    ns.Print("protected call status")

    local secure = issecure and issecure()
    ns.PrintRaw(("  issecure() here:              %s"):format(tostring(secure)))

    if type(C_AuctionHouse) == "table" and issecurevariable then
        local ok, isSecure = pcall(issecurevariable, C_AuctionHouse, "PostItem")
        ns.PrintRaw(("  PostItem is a secure value:   %s"):format(
            ok and tostring(isSecure) or "could not check"))
    end

    if type(C_TradeSkillUI) == "table" and issecurevariable then
        local ok, isSecure = pcall(issecurevariable, C_TradeSkillUI, "CraftRecipe")
        ns.PrintRaw(("  CraftRecipe is secure:        %s"):format(
            ok and tostring(isSecure) or "could not check"))
    end

    ns.PrintRaw(("  addon posting blocked:        %s"):format(
        tostring(ns.Posting:IsBlocked())))
    ns.PrintRaw(("  addon crafting blocked:       %s"):format(
        tostring(ns.Crafting:IsBlocked())))
end)

--------------------------------------------------------------------------------
-- Listing
--------------------------------------------------------------------------------

--- List one item. Must be called from a hardware event.
function Posting:Post(itemID, quantity, unitPrice)
    local allowed, reason = self:CanPost()
    if not allowed then
        ns.Print(reason)
        return false
    end

    if self.pending then
        ns.Print("a listing is already in flight")
        return false
    end

    local sellable, available = self:GetSellInfo(itemID)
    if not sellable then
        ns.Print(("%s cannot be auctioned"):format(Util.GetItemLabel(itemID)))
        return false
    end

    quantity = math.max(1, math.min(quantity or available, available))

    -- An item auction draws from the one slot it references, so gear goes up
    -- one listing at a time.
    if not ns.Scanner:IsCommodity(itemID) then
        local _, _, slotStack = FindInBags(itemID)
        quantity = math.min(quantity, slotStack or 1)
    end

    if available < 1 then
        ns.Print("none of that available to list")
        return false
    end

    unitPrice = math.floor(unitPrice or self:GetPostPrice(itemID) or 0)
    if unitPrice < 1 then
        ns.Print("no price data for that item -- scan the auction house first")
        return false
    end

    -- A nonsense price is caught before anything irreversible happens. This
    -- is separate from the material-cost check below: that one is about
    -- profit, this one is about the number being wrong.
    local floor, why = self:GetPriceFloor(itemID)

    if floor and unitPrice < floor then
        self.pending = nil

        ns.Warn(("refusing to list %s at %s -- %s."):format(
            Util.GetItemLabel(itemID), Util.FormatMoney(unitPrice), why or "the price looks wrong"))
        ns.Warn(("expected at least %s. Run a scan, or list it by hand."):format(
            Util.FormatMoney(floor)))
        return false
    end

    -- Refuse to list below what the materials cost. An undercut war can drive
    -- the rival price under your own cost, and following it down loses gold on
    -- every sale.
    if ns.Config:Get("allowPostingAtALoss") ~= true then
        local recipeID = ns.Cost:FindRecipeForItem(itemID)
        local analysis = recipeID and ns.Profit:Analyse(recipeID)
        local unitCost = analysis and analysis.costPerUnit

        if unitCost and unitPrice < unitCost then
            ns.Warn(("refusing to list %s at %s -- materials cost %s"):format(
                Util.GetItemLabel(itemID),
                Util.FormatMoney(unitPrice), Util.FormatMoney(unitCost)))
            ns.Warn("enable 'Recommend selling at a loss' in Settings to override.")
            return false
        end
    end

    local bag, slot = FindInBags(itemID)
    local location = bag and MakeLocation(bag, slot)

    if not location then
        ns.Warn("could not reference that bag slot")
        return false
    end

    local duration = ns.Config:Get("postDuration") or 2
    local isCommodity = ns.Scanner:IsCommodity(itemID)

    self.pending = {
        itemID = itemID,
        quantity = quantity,
        unitPrice = unitPrice,
        isCommodity = isCommodity,
        -- Measured against afterwards, so success is verified rather than
        -- inferred from an event that fires for any auction at all.
        postedBefore = ns.Auctions:GetPostedCount(itemID),
        startedAt = GetTime(),
    }

    local ok, err
    if isCommodity then
        ok, err = pcall(C_AuctionHouse.PostCommodity, location, duration, quantity, unitPrice)
    else
        -- Buyout only, with no starting bid. Blizzard's own Sell tab does this
        -- whenever Buyout Mode is ticked, and sending bid and buyout as the
        -- same value is the one place our call differed from theirs.
        --
        -- It also means nobody can win the item for less than the price you
        -- were shown, which was the point of matching them in the first place.
        ok, err = pcall(C_AuctionHouse.PostItem, location, duration, quantity,
            nil, unitPrice)
    end

    if not ok then
        self.pending = nil

        if tostring(err):lower():find("addon") then
            self:MarkBlocked()
        else
            ns.Warn(("the client refused the listing: %s"):format(
                tostring(err):gsub("^.-:%d+: ", "")))
        end
        return false
    end

    -- The return value is not a success flag. PostCommodity returns false on
    -- a listing that is genuinely created, so reading it as a refusal reports
    -- failure on every successful commodity sale. Only the server's own view
    -- settles this, which is what VerifyPending goes and asks for.
    ns.Print(("listing %dx %s at %s each"):format(
        quantity, Util.GetItemLabel(itemID), Util.FormatMoney(unitPrice)))

    -- Nothing of ours competes with a listing that is settling. Verification is
    -- urgent and still gets through; scans and bookkeeping wait.
    ns.AHQueue:Yield(POST_VERIFY_DELAY + 2, "a listing of ours is in flight")

    -- The auction house is throttled and can take several seconds to reply, so
    -- wait, then ask the server what is actually listed.
    C_Timer.After(POST_VERIFY_DELAY, function() Posting:VerifyPending() end)
    return true
end

--------------------------------------------------------------------------------
-- Price floor
--------------------------------------------------------------------------------

--- The lowest price worth listing at, below which something has gone wrong.
--
-- Exists because a bad price is silent and expensive: a scroll worth a silver
-- was once about to be listed at one copper, from an auction house search
-- whose quantity field meant something other than assumed. A guard here does
-- not need to know why the number is wrong, only that it cannot be right.
--
-- @return floor, why
function Posting:GetPriceFloor(itemID)
    local floor, why = 0, nil

    -- Below what a vendor pays, selling it to a vendor is strictly better.
    local ok, _, _, _, _, _, _, _, _, _, _, sellPrice = pcall(C_Item.GetItemInfo, itemID)
    if ok and sellPrice and sellPrice > 0 then
        floor, why = sellPrice, "a vendor pays more than that"
    end

    -- A fifth of market value. Wide enough for a real undercut war, narrow
    -- enough to catch an order of magnitude going missing.
    local market = ns.Prices:GetValue(itemID, "market")
    if market and market > 0 then
        local fraction = math.floor(market * 0.2)
        if fraction > floor then
            floor, why = fraction, "that is a fraction of what it normally sells for"
        end
    end

    if floor < 1 then return nil end
    return floor, why
end

--------------------------------------------------------------------------------
-- Confirmation
--------------------------------------------------------------------------------

-- Blizzard's own popup rather than a custom frame: it is already the thing
-- players trust for "are you sure", and its button click is a hardware event,
-- which posting requires.

-- Adding a key is fine. Assigning the global itself is not: writing
-- "StaticPopupDialogs = StaticPopupDialogs or {}" from addon code taints the
-- global variable, and then Blizzard's own popup machinery reads a tainted
-- value and gets "blocked from an action only available to the Blizzard UI"
-- the next time it shows any dialog of its own.
if type(StaticPopupDialogs) == "table" then

StaticPopupDialogs["BLACKTHORNES_TS_CONFIRM_POST"] = {
    text = "%s",
    button1 = YES or "List it",
    button2 = NO or "Skip",
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    -- Above the default dialogs, so it is not buried by the auction house.
    preferredIndex = 3,

    OnAccept = function(self)
        local data = (self and self.data) or Posting.confirming
        if not data then return end

        Posting.confirming = nil
        Posting:Post(data.itemID, data.quantity, data.unitPrice)
    end,

    OnCancel = function()
        Posting.confirming = nil
        ns.Print("skipped.")
    end,
}

end

--- Show the confirmation for a listing whose price is already settled.
--
-- @param check what the price check found, or nil when there was none:
--   { state, previousPrice, basis }. state is "fresh" (the auction house
--   answered and had listings), "recent" (answered moments ago), "empty"
--   (answered, nothing listed) or "unavailable" (no answer).
function Posting:Confirm(itemID, quantity, unitPrice, check)
    check = check or {}

    local deposit = self:GetDeposit(itemID, quantity)

    local text = ("List |cffffffff%d x %s|r\n\nat %s each, %s total%s?"):format(
        quantity, Util.GetItemLabel(itemID),
        Util.FormatMoney(unitPrice, { noColor = true }),
        Util.FormatMoney(unitPrice * quantity, { noColor = true }),
        deposit and (", deposit " .. Util.FormatMoney(deposit, { noColor = true })) or "")

    -- Say so when the check moved the price, rather than quietly listing at
    -- something different from what the row showed a moment ago.
    if check.previousPrice and check.previousPrice ~= unitPrice then
        text = text .. ("\n\n|cffC8A44DPrice checked just now: was %s.|r"):format(
            Util.FormatMoney(check.previousPrice, { noColor = true }))
    end

    -- An empty auction house is the case this check exists for. Before, the
    -- last scan's rival price survived and the listing undercut somebody who
    -- was no longer selling; now there is nobody to undercut and the number
    -- above means something different, so it says which.
    if check.state == "empty" then
        text = text .. ("\n\n|cffC8A44D%s|r"):format(
            check.basis == "market"
                and "Nothing else is listed right now, so this is market value rather than an undercut."
                or "Nothing else is listed right now, and there is no market value to go on -- check this price yourself.")

    elseif check.state == "unavailable" then
        text = text .. "\n\n|cffE5604FThe price check did not come back. This is the last price we saw, which may be out of date.|r"
    end

    local recipeID = ns.Cost:FindRecipeForItem(itemID)
    local analysis = recipeID and ns.Profit:Analyse(recipeID)
    local unitCost = analysis and analysis.costPerUnit

    if unitCost and unitPrice < unitCost then
        text = text .. ("\n\n|cffE5604FThis is below the %s it cost to make.|r"):format(
            Util.FormatMoney(unitCost, { noColor = true }))
    end

    self.confirming = { itemID = itemID, quantity = quantity, unitPrice = unitPrice }

    local dialog = StaticPopup_Show("BLACKTHORNES_TS_CONFIRM_POST", text)
    if dialog then
        dialog.data = self.confirming
    else
        self.confirming = nil
        ns.Warn("could not open the confirmation dialog; nothing was listed.")
    end
end

--- Check the current price, then ask, then post. This is what the buttons call.
--
-- The price check is a real auction house search for this one item, not a
-- reading of the last full scan. A snapshot is minutes old by the time you
-- act on it, and undercutting a price that has since moved lists you above
-- the rival you were trying to beat.
--
-- The search is asynchronous and posting needs a hardware event, so the
-- confirmation click is what actually creates the listing. That ordering is
-- deliberate: search, show the fresh number, and let the click commit it.
function Posting:Request(itemID, quantity, unitPrice)
    local allowed, reason = self:CanPost()
    if not allowed then
        ns.Print(reason or "cannot post right now")
        return false
    end

    quantity = quantity or 1
    unitPrice = unitPrice or self:GetPostPrice(itemID) or 0

    local verify = ns.Config:Get("verifyPriceBeforePosting") ~= false

    if not verify or not ns.Scanner.isAuctionHouseOpen then
        self:Confirm(itemID, quantity, unitPrice)
        return true
    end

    ns.Print(("checking the current price of %s..."):format(Util.GetItemLabel(itemID)))

    -- A search that never answers must not leave the click doing nothing, so
    -- fall back to the price we already had and say that is what happened.
    local settled = false

    local function Proceed(state)
        if settled then return end
        settled = true

        -- Read the price back after the check, never before. A search that
        -- found nothing has just cleared the rival price, and this is where
        -- that becomes a listing at market value instead of an undercut of
        -- a seller who is not there.
        local price, basis = self:GetPostPrice(itemID)
        price = price or unitPrice

        self:Confirm(itemID, quantity, price, {
            state = state,
            basis = basis,
            -- Only meaningful when something was actually checked.
            previousPrice = state ~= "unavailable" and unitPrice or nil,
        })
    end

    C_Timer.After(5, function()
        if settled then return end

        ns.Warn("the price check did not come back; using the last known price.")
        Proceed("unavailable")
    end)

    local started = ns.Scanner:ScanItem(itemID, function(_, _, _, _, _, _, status)
        Proceed(status or "fresh")
    end)

    if not started then
        Proceed("unavailable")
    end

    return true
end

--------------------------------------------------------------------------------
-- Verification
--------------------------------------------------------------------------------

--- Ask what we actually own, rather than guessing from the absence of an event.
function Posting:VerifyPending()
    if not self.pending or self.pending.verifying then return end

    -- An attempt older than this has already given up; leaving it in place lets
    -- an unrelated auction be mistaken for it.
    if (GetTime() - (self.pending.startedAt or 0)) > 60 then
        self.pending = nil
        return
    end

    self.pending.verifying = true
    ns.Auctions:Refresh({ priority = ns.AHQueue.PRIORITY.urgent, force = true })

    -- Refresh reads the answer back itself once the query goes out, so this is
    -- no longer the thing that settles a listing: it is the backstop for a query
    -- that never went out at all, which is the one case where "could not tell"
    -- is the honest answer. It has to outlast the queue's own wait, or a slow
    -- send gets reported as a failure while the reading is still on its way.
    C_Timer.After(VERIFY_GIVE_UP, function()
        if Posting.pending and Posting.pending.verifying then
            Posting:ResolvePending(nil)
        end
    end)
end

--- Called once the owned-auction list has been re-read.
-- @param posted number now listed, or nil if that could not be determined
function Posting:ResolvePending(posted)
    local pending = self.pending
    if not pending then return end

    self.pending = nil

    if posted and posted > (pending.postedBefore or 0) then
        ns.Print(("listed %s"):format(Util.GetItemLabel(pending.itemID)))

    elseif posted then
        -- The server answered and it is not there: it genuinely did not go up.
        ns.Warn(("%s did not appear in your auctions."):format(
            Util.GetItemLabel(pending.itemID)))
        ns.Warn("the auction house may be refusing listings; try Blizzard's Sell tab.")
    else
        ns.Warn("could not tell whether that listing went up -- check your Auctions tab")
    end

    if ns.UI then
        ns.UI:RefreshActiveTab()
        ns.UI:UpdatePostButton()
    end
end

--- Sample the auction house throttle over a few seconds.
--
-- Posting blocks while the throttle says it is busy, so if this client never
-- reports ready that block is a bug on our side rather than a real wait.
ns.RegisterCommand("throttle", "watch the auction house throttle", function()
    ns.AHQueue:Report()

    if not ns.Util.HasFunction("C_AuctionHouse.IsThrottledMessageSystemReady") then
        ns.Print("this client has no throttle check; requests are paced by time alone.")
        return
    end

    ns.Print("sampling the client's throttle for 10s...")

    local samples, ready = 0, 0

    local ticker
    ticker = C_Timer.NewTicker(0.5, function()
        samples = samples + 1

        local ok, isReady = pcall(C_AuctionHouse.IsThrottledMessageSystemReady)
        if ok and isReady then ready = ready + 1 end

        if samples >= 20 then
            ticker:Cancel()

            ns.Print(("throttle ready on %d of %d samples over 10s."):format(ready, samples))

            if ready == 0 then
                ns.Warn("never ready -- posting would always be blocked. Tell me and I will stop gating on it.")
            end
        end
    end)
end)

--- Attempt one listing and report every step, including the raw return value.
--
-- Exists because "prints a message but nothing happens" has several different
-- causes that look identical from the chat frame: the call being refused, the
-- call succeeding but the server dropping it, or the listing genuinely being
-- created and the addon failing to notice.
ns.RegisterCommand("posttest", "attempt one listing and report every step: /bts posttest [name]", function(args)
    local line

    if args and args ~= "" then
        local needle = args:lower()

        for _, candidate in ipairs(ns.Posting:GetPostable({ includeAll = true })) do
            if (candidate.label or ""):lower():find(needle, 1, true) then
                line = candidate
                break
            end
        end

        if not line then
            ns.Print(("nothing sellable matching '%s'."):format(args))
            return
        end
    else
        line = ns.Posting:GetNextPostable({ includeAll = true })
    end

    if not line then
        ns.Print("nothing in your bags with a known price to test with.")
        return
    end

    local itemID, quantity, unitPrice = line.itemID, line.postQuantity, line.unitPrice

    ns.Print("posttest build 3")
    ns.Print(("posttest: %s x%d at %s"):format(
        Util.GetItemLabel(itemID), quantity, Util.FormatMoney(unitPrice)))

    local allowed, reason = ns.Posting:CanPost()
    ns.PrintRaw(("  can post: %s%s"):format(tostring(allowed),
        allowed and "" or (" (" .. tostring(reason) .. ")")))
    ns.PrintRaw(("  throttled: %s"):format(tostring(ns.Posting:IsThrottled())))

    local sellable, available = ns.Posting:GetSellInfo(itemID)
    ns.PrintRaw(("  sellable: %s, available: %s"):format(
        tostring(sellable), tostring(available)))

    local isCommodity = ns.Scanner:IsCommodity(itemID)
    ns.PrintRaw(("  commodity: %s"):format(tostring(isCommodity)))

    -- The value we compare against. A status that reads 2 while the enum
    -- calls Commodity something else would classify everything wrongly.
    if Enum and Enum.ItemCommodityStatus then
        local names = {}
        for key, value in pairs(Enum.ItemCommodityStatus) do
            names[#names + 1] = ("%s=%s"):format(tostring(key), tostring(value))
        end
        table.sort(names)
        ns.PrintRaw(("  enum: %s"):format(table.concat(names, " ")))
    else
        ns.PrintRaw("  enum: Enum.ItemCommodityStatus missing")
    end

    -- Where that answer comes from. If these functions are missing, every
    -- item reads as "not a commodity" and the wrong post call gets used.
    -- The usage message says this takes an "item", which could be an ID, a
    -- link, or an ItemLocation. Rather than guess again, try each and report
    -- which one the client accepts.
    if Util.HasFunction("C_AuctionHouse.GetItemCommodityStatus") then
        local bagID, slotID = FindInBags(itemID)

        local candidates = {
            { "itemID", itemID },
            { "link", select(2, pcall(C_Item.GetItemInfo, itemID)) },
            { "location", bagID and MakeLocation(bagID, slotID) },
            { "itemKey", Util.HasFunction("C_AuctionHouse.MakeItemKey")
                and select(2, pcall(C_AuctionHouse.MakeItemKey, itemID)) or nil },
        }

        for _, candidate in ipairs(candidates) do
            local label, value = candidate[1], candidate[2]

            if value == nil then
                ns.PrintRaw(("  status(%s): not available"):format(label))
            else
                local statusOk, status = pcall(C_AuctionHouse.GetItemCommodityStatus, value)

                ns.PrintRaw(("  status(%s): ok=%s value=%s"):format(
                    label, tostring(statusOk),
                    tostring(status):gsub("Usage:.*", "Usage omitted")))
            end
        end
    end

    local bag, slot = FindInBags(itemID)
    local location = bag and MakeLocation(bag, slot)
    ns.PrintRaw(("  bag %s slot %s, location: %s"):format(
        tostring(bag), tostring(slot), location and "made" or "nil"))

    if not location then return end

    -- What the auction house itself says about this exact slot, before we
    -- ask it to list anything.
    if Util.HasFunction("C_AuctionHouse.IsSellItemValid") then
        local validOk, valid, err = pcall(C_AuctionHouse.IsSellItemValid, location, true)
        ns.PrintRaw(("  IsSellItemValid: ok=%s valid=%s err=%s"):format(
            tostring(validOk), tostring(valid), tostring(err)))
    end

    if Util.HasFunction("C_AuctionHouse.GetAvailablePostCount") then
        local countOk, postable = pcall(C_AuctionHouse.GetAvailablePostCount, location)
        ns.PrintRaw(("  GetAvailablePostCount: ok=%s value=%s"):format(
            tostring(countOk), tostring(postable)))
    end

    -- The two deposit calls do not agree on their first argument: the
    -- commodity one takes an item ID, the item one takes a location.
    local depositFn = isCommodity and "CalculateCommodityDeposit" or "CalculateItemDeposit"
    if Util.HasFunction("C_AuctionHouse." .. depositFn) then
        local subject = isCommodity and itemID or location

        local depOk, deposit = pcall(C_AuctionHouse[depositFn], subject,
            ns.Config:Get("postDuration") or 2, quantity)

        ns.PrintRaw(("  %s: ok=%s value=%s"):format(
            depositFn, tostring(depOk),
            tostring(deposit):gsub("Usage:.*", "Usage omitted")))
    end

    local before = ns.Auctions:GetPostedCount(itemID)
    ns.PrintRaw(("  listed before: %d"):format(before))

    local duration = ns.Config:Get("postDuration") or 2

    local ok, returned
    if isCommodity then
        ok, returned = pcall(C_AuctionHouse.PostCommodity, location, duration, quantity, unitPrice)
    else
        ok, returned = pcall(C_AuctionHouse.PostItem, location, duration, quantity, unitPrice, unitPrice)
    end

    -- The distinction that matters: an error means the call was refused, a
    -- false return means the auction house declined, and nil usually means
    -- it accepted.
    ns.PrintRaw(("  call: ok=%s  returned=%s (%s)"):format(
        tostring(ok), tostring(returned), type(returned)))

    C_Timer.After(4, function()
        ns.Auctions:Refresh()

        C_Timer.After(2, function()
            local after = ns.Auctions:GetPostedCount(itemID)

            ns.PrintRaw(("  listed after: %d"):format(after))

            if after > before then
                ns.Print("|cff4FD18Bthe listing was created.|r")
            else
                ns.Print("|cffE5604Fnothing was listed -- the server refused it.|r")
            end
        end)
    end)
end)

--- Ask the client what arguments its auction functions expect.
--
-- A call with no arguments fails with a usage string naming the real
-- signature. That is how the commodity-status call was found to want an
-- ItemLocation rather than an item ID, after three wrong guesses.
--
-- Creates nothing: every call here is designed to fail.
ns.RegisterCommand("sig", "print the auction API signatures this client expects", function()
    -- PostItem and PostCommodity are deliberately absent. Calling them at all
    -- outside a real click trips "Interface action failed because of an
    -- AddOn", so probing their signature costs a scary red error for a string
    -- we already have: PostItem(item, duration, quantity [, bid, buyout]).
    local names = {
        "CalculateItemDeposit", "CalculateCommodityDeposit",
        "GetItemCommodityStatus", "IsSellItemValid", "GetAvailablePostCount",
        "MakeItemKey", "IsThrottledMessageSystemReady",
    }

    ns.Print("auction API signatures")

    -- The Classic posting path, which may be what item auctions still want.
    local legacy = {}
    for _, name in ipairs({ "StartAuction", "ClickAuctionSellItemButton",
        "GetAuctionSellItemInfo", "CalculateAuctionDeposit", "PickupContainerItem" }) do
        local present = type(_G[name]) == "function"
            or (name == "PickupContainerItem" and C_Container
                and type(C_Container.PickupContainerItem) == "function")

        legacy[#legacy + 1] = ("%s=%s"):format(name, present and "yes" or "no")
    end
    ns.PrintRaw(("  |cffC8A44Dlegacy|r %s"):format(table.concat(legacy, " ")))

    for _, name in ipairs(names) do
        if not Util.HasFunction("C_AuctionHouse." .. name) then
            ns.PrintRaw(("  %s: |cffE5604Fmissing|r"):format(name))
        else
            local ok, err = pcall(C_AuctionHouse[name])

            if ok then
                ns.PrintRaw(("  %s: accepted no arguments"):format(name))
            else
                -- The usage line is the part worth reading; the file and line
                -- prefix is noise.
                local usage = tostring(err)
                    :gsub("^.-Usage:%s*", "")
                    :gsub("^.-:%d+:%s*", "")

                ns.PrintRaw(("  |cffC8A44D%s|r: %s"):format(name, usage))
            end
        end
    end
end)

--- Try one specific PostItem argument shape, and report whether it listed.
--
-- Blizzard's own Sell tab lists this item; our call with apparently the same
-- data is refused. So the difference is in how the arguments are passed, and
-- guessing has already been wrong twice. This walks the plausible shapes one
-- click at a time.
--
-- A slash command counts as a hardware event, which is why this can post at
-- all. It stops as soon as one works.
local POST_VARIANTS = {
    { name = "bid nil, buyout set",
      build = function(price) return nil, price end },

    { name = "bid = buyout",
      build = function(price) return price, price end },

    { name = "bid only, no buyout",
      build = function(price) return price, nil end },

    { name = "bid 1c under buyout",
      build = function(price) return math.max(1, price - 1), price end },

    { name = "no prices at all",
      build = function() return nil, nil end },

    { name = "the Classic path: sell slot then StartAuction",
      legacy = true,
      build = function(price) return price, price end },
}

--- The Classic way: put the item in the auction slot, then start the auction.
--
-- Forever is Classic content on the modern API, and the two posting paths may
-- not have been unified. Commodities demonstrably work through PostCommodity;
-- item auctions may still expect this.
local function TryLegacyPost(bagID, slotID, bid, buyout, duration)
    local missing = {}

    for _, name in ipairs({ "ClickAuctionSellItemButton", "StartAuction" }) do
        if type(_G[name]) ~= "function" then missing[#missing + 1] = name end
    end

    local pickup = C_Container and C_Container.PickupContainerItem or _G.PickupContainerItem
    if type(pickup) ~= "function" then missing[#missing + 1] = "PickupContainerItem" end

    if #missing > 0 then
        return false, "this client has no " .. table.concat(missing, ", ")
    end

    -- Anything already on the cursor would be put into the slot instead.
    pcall(ClearCursor)

    local pickedUp = pcall(pickup, bagID, slotID)
    if not pickedUp then
        pcall(ClearCursor)
        return false, "could not pick the item up"
    end

    local clicked = pcall(ClickAuctionSellItemButton)
    if not clicked then
        pcall(ClearCursor)
        return false, "could not place it in the auction slot"
    end

    local ok, err = pcall(StartAuction, bid, buyout, duration)

    -- Whatever happened, do not leave the item stuck to the cursor.
    pcall(ClearCursor)

    if not ok then
        return false, tostring(err):gsub("^.-:%d+: ", "")
    end

    return true
end

ns.RegisterCommand("posttry", "try one PostItem argument shape: /bts posttry <n> [name]", function(args)
    local index, needle = (args or ""):match("^(%d+)%s*(.*)$")
    index = tonumber(index)

    if not index or not POST_VARIANTS[index] then
        ns.Print("argument shapes to try:")
        for i, variant in ipairs(POST_VARIANTS) do
            ns.PrintRaw(("  |cffC8A44D/bts posttry %d|r  %s"):format(i, variant.name))
        end
        ns.PrintRaw("  add part of an item name to choose what to list.")
        return
    end

    local line
    for _, candidate in ipairs(ns.Posting:GetPostable({ includeAll = true })) do
        if needle == "" or (candidate.label or ""):lower():find(needle:lower(), 1, true) then
            if not ns.Scanner:IsCommodity(candidate.itemID) then
                line = candidate
                break
            end
        end
    end

    if not line then
        ns.Print("no item auction in your bags matching that -- commodities already work.")
        return
    end

    local itemID, quantity, price = line.itemID, line.postQuantity, line.unitPrice

    local bagID, slotID = FindInBags(itemID)
    local location = bagID and MakeLocation(bagID, slotID)
    if not location then
        ns.Warn("could not reference that bag slot")
        return
    end

    local variant = POST_VARIANTS[index]
    local bid, buyout = variant.build(price)
    local duration = ns.Config:Get("postDuration") or 2

    ns.Print(("posttry %d (%s): %s x%d, bid=%s buyout=%s duration=%s"):format(
        index, variant.name, Util.GetItemLabel(itemID), quantity,
        tostring(bid), tostring(buyout), tostring(duration)))

    local before = ns.Auctions:GetPostedCount(itemID)

    if variant.legacy then
        local worked, why = TryLegacyPost(bagID, slotID, bid, buyout, duration)
        ns.PrintRaw(("  legacy call: %s%s"):format(
            tostring(worked), why and (" -- " .. why) or ""))
    else
        local ok, returned = pcall(C_AuctionHouse.PostItem, location, duration, quantity, bid, buyout)
        ns.PrintRaw(("  call: ok=%s returned=%s"):format(tostring(ok), tostring(returned)))
    end

    C_Timer.After(4, function()
        ns.Auctions:Refresh()

        C_Timer.After(2, function()
            local after = ns.Auctions:GetPostedCount(itemID)

            if after > before then
                ns.Print(("|cff4FD18Bshape %d worked: %s.|r"):format(index, variant.name))
                ns.Print("tell me which number worked and I will make it the default.")
            else
                ns.Print(("|cffE5604Fshape %d did not list.|r Try the next one."):format(index))
            end
        end)
    end)
end)

--- Watch what Blizzard's own Sell tab passes when a listing succeeds.
--
-- Six argument shapes have now failed while the default UI lists the same item
-- without complaint, so the difference is something not being guessed. Rather
-- than try a seventh, hook the call and read the arguments off a posting that
-- actually works.
--
-- hooksecurefunc observes without replacing, so Blizzard's call is unaffected
-- and nothing here can taint it.
ns.RegisterCommand("watchpost", "log what Blizzard's Sell tab passes when you post", function()
    if Posting.watching then
        ns.Print("already watching -- post something with Blizzard's Sell tab.")
        return
    end

    local function Describe(value)
        if type(value) ~= "table" then return tostring(value) end

        -- An ItemLocation prints as a table; the bag and slot are the point.
        local ok, bagID, slotID = pcall(value.GetBagAndSlot, value)
        if ok and bagID then
            return ("location(bag %s slot %s)"):format(tostring(bagID), tostring(slotID))
        end

        local keyOk, itemID = pcall(function() return value.itemID end)
        if keyOk and itemID then
            return ("itemKey(%s)"):format(tostring(itemID))
        end

        return "table"
    end

    local function Log(label, ...)
        local parts = {}
        for i = 1, select("#", ...) do
            parts[#parts + 1] = ("%d=%s"):format(i, Describe((select(i, ...))))
        end

        ns.Print(("|cff4FD18B%s|r %s"):format(label, table.concat(parts, "  ")))
    end

    local hooked = {}

    if C_AuctionHouse then
        for _, name in ipairs({ "PostItem", "PostCommodity", "SetSellItem" }) do
            if type(C_AuctionHouse[name]) == "function" then
                hooksecurefunc(C_AuctionHouse, name, function(...)
                    Log("C_AuctionHouse." .. name, ...)
                end)
                hooked[#hooked + 1] = name
            end
        end
    end

    for _, name in ipairs({ "StartAuction", "ClickAuctionSellItemButton" }) do
        if type(_G[name]) == "function" then
            hooksecurefunc(name, function(...) Log(name, ...) end)
            hooked[#hooked + 1] = name
        end
    end

    if #hooked == 0 then
        ns.Warn("nothing to hook; this client exposes none of the posting calls.")
        return
    end

    Posting.watching = true

    ns.Print(("watching: %s"):format(table.concat(hooked, ", ")))
    ns.Print("now post the scroll with Blizzard's own Sell tab, and tell me what prints.")
end)
