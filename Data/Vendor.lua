-- Blackthornes Tradeskills -- Data/Vendor.lua
-- What a vendor will sell you, and for how much.
--
-- On a Classic-era realm this matters more than it looks. Thread, vials, and
-- similar reagents cost a few copper from any trade goods vendor, and people
-- routinely list them on the auction house for many times that. Pricing those
-- reagents from auction data alone either inflates the craft cost or, when
-- nothing is listed at all, marks the recipe unpriceable and hides it.
--
-- Prices are learned by watching merchants rather than shipped as a table: this
-- is a beta, and guessing at prices that may have changed would be worse than
-- having none.

local _, ns = ...

local Vendor = ns.NewModule("Vendor")

local Util = ns.Util

--------------------------------------------------------------------------------
-- Storage
--------------------------------------------------------------------------------

-- Vendor prices are fixed and identical everywhere, so this is account-wide
-- rather than per realm.
function Vendor:GetTable()
    if not ns.db then return {} end

    ns.db.vendorPrices = ns.db.vendorPrices or {}
    return ns.db.vendorPrices
end

--- Copper for one unit, or nil if no vendor has been seen selling it.
function Vendor:GetUnitPrice(itemID)
    local record = self:GetTable()[itemID]
    if not record then return nil end

    -- Items bought with honour, tokens or similar are not purchasable with
    -- gold, so they have no meaningful cash price.
    if record.extendedCost then return nil end

    return record.price
end

function Vendor:IsLimited(itemID)
    local record = self:GetTable()[itemID]
    return record ~= nil and record.limited == true
end

function Vendor:Count()
    return Util.Count(self:GetTable())
end

--------------------------------------------------------------------------------
-- Reading a merchant
--------------------------------------------------------------------------------

--- Resolve the item behind a merchant slot.
--
-- C_MerchantFrame.GetItemInfo does not carry an item ID on this client, so the
-- link is the reliable source. Name lookup is a last resort, since it only
-- works for items already cached.
local function GetMerchantItemID(index, info)
    if info and info.itemID then return info.itemID, "info" end

    if Util.HasFunction("GetMerchantItemLink") then
        local ok, link = pcall(GetMerchantItemLink, index)
        if ok and link then
            local itemID = tonumber(link:match("item:(%d+)"))
            if itemID then return itemID, "link" end
        end
    end

    if info and info.name and Util.HasFunction("C_Item.GetItemInfoInstant") then
        local ok, itemID = pcall(C_Item.GetItemInfoInstant, info.name)
        if ok and itemID then return itemID, "name" end
    end

    return nil, "unresolved"
end

function Vendor:Scan()
    if not Util.HasFunction("C_MerchantFrame.GetItemInfo") then return 0 end

    -- Rebuilt every scan: merchant slot indices are only valid for the vendor
    -- currently open.
    self.merchantItems = {}

    local countOk, numItems
    if Util.HasFunction("GetMerchantNumItems") then
        countOk, numItems = pcall(GetMerchantNumItems)
    end

    if not countOk or not numItems or numItems == 0 then
        ns.Debug("merchant has no readable items")
        return 0
    end

    local prices = self:GetTable()
    local learned, unresolved = 0, 0

    for index = 1, numItems do
        local ok, info = pcall(C_MerchantFrame.GetItemInfo, index)

        if ok and info and info.price and info.price > 0 then
            local itemID, method = GetMerchantItemID(index, info)

            if itemID then
                -- Vendors sell in stacks; we want the price of one unit.
                local stack = math.max(1, info.stackCount or 1)

                prices[itemID] = {
                    price = math.floor(info.price / stack),
                    stack = stack,
                    -- numAvailable is -1 for unlimited stock. A limited item
                    -- cannot be relied on for bulk crafting.
                    limited = (info.numAvailable or -1) >= 0,
                    extendedCost = info.hasExtendedCost == true,
                    seenAt = time(),
                    method = method,
                }

                self.merchantItems[itemID] = {
                    index = index,
                    price = math.floor(info.price / stack),
                    stack = stack,
                    numAvailable = info.numAvailable or -1,
                    extendedCost = info.hasExtendedCost == true,
                }

                learned = learned + 1
            else
                unresolved = unresolved + 1
            end
        end
    end

    if learned > 0 then
        ns.Debug(("learned %d vendor price(s), %d unresolved"):format(learned, unresolved))

        ns.Cost:InvalidateIndex()
        if ns.UI then ns.UI:RefreshActiveTab() end
    end

    self.lastUnresolved = unresolved
    return learned
end

--------------------------------------------------------------------------------
-- Buying what the queue needs
--------------------------------------------------------------------------------

Vendor.isMerchantOpen = false

function Vendor:CanBuy()
    if not self.isMerchantOpen then
        return false, "no vendor is open"
    end
    if not Util.HasFunction("BuyMerchantItem") then
        return false, "this client does not let addons buy from vendors"
    end
    return true
end

--- Queue shortfalls that this vendor can actually supply.
-- @return lines, totalCost
function Vendor:GetNeeded()
    local lines, total = {}, 0

    if not self.isMerchantOpen or not self.merchantItems then
        return lines, 0
    end

    for _, line in ipairs(ns.Queue:GetShoppingList()) do
        local stock = self.merchantItems[line.itemID]

        -- Items bought with tokens or honour cannot be paid for in gold.
        if line.shortfall > 0 and stock and not stock.extendedCost then
            local affordable = line.shortfall

            -- Limited stock: never ask for more than the vendor has.
            if stock.numAvailable >= 0 then
                affordable = math.min(affordable, stock.numAvailable * stock.stack)
            end

            if affordable > 0 then
                local cost = affordable * stock.price

                lines[#lines + 1] = {
                    itemID = line.itemID,
                    index = stock.index,
                    amount = affordable,
                    unitPrice = stock.price,
                    cost = cost,
                    stack = stock.stack,
                    short = affordable < line.shortfall,
                }

                total = total + cost
            end
        end
    end

    return lines, total
end

--- Buy everything the queue needs from the open vendor.
--
-- Purchases are chunked and re-checked against your actual bags between each
-- one, rather than fired blindly in a loop: if a purchase silently fails, or
-- you already had more than expected, this stops instead of over-buying.
function Vendor:BuyNeeded()
    local allowed, reason = self:CanBuy()
    if not allowed then
        ns.Print(reason)
        return false
    end

    if self.buying then
        ns.Print("already buying")
        return false
    end

    local lines, total = self:GetNeeded()
    if #lines == 0 then
        ns.Print("this vendor has nothing the queue needs")
        return false
    end

    local moneyOk, money = pcall(GetMoney)
    if moneyOk and money and money < total then
        ns.Warn(("that would cost %s and you have %s"):format(
            Util.FormatMoney(total), Util.FormatMoney(money)))
        return false
    end

    self.buying = true
    self.buyIndex = 1
    self.buySpent = 0
    self.buyLines = lines
    self.buySteps = 0
    self.buyPurchased = {}

    ns.Print(("buying %d material(s) for %s..."):format(#lines, Util.FormatMoney(total)))

    self:BuyStep()
    return true
end

-- A hard ceiling on purchase calls, so a miscount can never spend
-- unbounded gold in a runaway loop.
local MAX_BUY_STEPS = 60

function Vendor:BuyStep()
    if not self.buying then return end

    self.buySteps = self.buySteps + 1
    if self.buySteps > MAX_BUY_STEPS then
        ns.Warn("stopped buying after too many purchases; run it again if needed")
        self:FinishBuying()
        return
    end

    local line = self.buyLines[self.buyIndex]
    if not line then
        self:FinishBuying()
        return
    end

    -- How much of this item this run has already bought.
    --
    -- This tally, not the live bag count, is what stops the purchase. Bag
    -- updates are asynchronous: checking GetItemCount a fraction of a second
    -- after buying can still return the pre-purchase number, and deciding from
    -- that buys the same item twice.
    local purchased = self.buyPurchased[line.itemID] or 0
    local remaining = line.amount - purchased

    -- Live shortfall is still consulted, but only ever to buy LESS. If bag
    -- counts have caught up and show the need already met, stop early; if they
    -- lag, the tally above has already capped us.
    local liveShortfall
    for _, current in ipairs(ns.Queue:GetShoppingList()) do
        if current.itemID == line.itemID then
            liveShortfall = current.shortfall
            break
        end
    end

    if liveShortfall then
        remaining = math.min(remaining, liveShortfall)
    end

    if remaining <= 0 then
        self.buyIndex = self.buyIndex + 1
        C_Timer.After(0.1, function() Vendor:BuyStep() end)
        return
    end

    -- One merchant stack per call is the reliable maximum.
    local amount = math.min(remaining, math.max(1, line.stack))

    local ok = pcall(BuyMerchantItem, line.index, amount)
    if not ok then
        ns.Warn(("could not buy %s"):format(Util.GetItemLabel(line.itemID)))
        self.buyIndex = self.buyIndex + 1
    else
        self.buyPurchased[line.itemID] = purchased + amount
        self.buySpent = self.buySpent + (amount * line.unitPrice)
    end

    -- Long enough for BAG_UPDATE to land, so the live check above is meaningful
    -- rather than always reading stale counts.
    C_Timer.After(0.35, function() Vendor:BuyStep() end)
end

function Vendor:FinishBuying()
    if not self.buying then return end

    self.buying = false
    self.buyLines = nil
    self.buyPurchased = nil

    ns.Print(("done buying (about %s spent)"):format(Util.FormatMoney(self.buySpent or 0)))

    if ns.UI then
        ns.UI:UpdateMerchantButton()
        ns.UI:RefreshActiveTab()
    end
end

function Vendor:IsBuying()
    return self.buying == true
end

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------

function Vendor:OnEnable()
    ns.RegisterEvent(self, "MERCHANT_SHOW", function()
        Vendor.isMerchantOpen = true

        -- The merchant list is not always populated on the event itself.
        C_Timer.After(0.2, function()
            Vendor:Scan()
            if ns.UI then ns.UI:AttachToMerchant() end
        end)
    end)

    ns.RegisterEvent(self, "MERCHANT_UPDATE", function()
        C_Timer.After(0.2, function()
            Vendor:Scan()
            if ns.UI then ns.UI:UpdateMerchantButton() end
        end)
    end)

    ns.RegisterEvent(self, "MERCHANT_CLOSED", function()
        Vendor.isMerchantOpen = false
        Vendor.merchantItems = nil

        -- Walking away mid-purchase must not leave a timer buying things.
        if Vendor.buying then Vendor:FinishBuying() end

        if ns.UI and ns.UI.merchantButton then
            ns.UI.merchantButton:Hide()
        end
    end)
end

--------------------------------------------------------------------------------
-- Commands
--------------------------------------------------------------------------------

ns.RegisterCommand("vendor", "show learned vendor prices", function()
    local count = ns.Vendor:Count()

    if count == 0 then
        ns.Print("no vendor prices learned yet -- open a trade goods vendor once")
        return
    end

    ns.Print(("%d vendor price(s) learned"):format(count))

    local shown = 0
    for itemID, record in pairs(ns.Vendor:GetTable()) do
        if shown < 15 then
            ns.PrintRaw(("  %s  %s%s"):format(
                Util.GetItemLabel(itemID),
                Util.FormatMoney(record.price),
                record.limited and "  |cff7a8089(limited stock)|r" or ""))
            shown = shown + 1
        end
    end
end)
