-- Blackthornes Tradeskills -- Logic/VendorFlips.lua
-- Items on the auction house listed for less than a vendor pays for them.
--
-- Buy one at the cheapest listing from someone else, sell it to any vendor,
-- and keep the difference. No auction house cut comes into it, since the
-- item goes to a vendor rather than back on the auction house.
--
-- Prices are per item. A stack listed at 40c each is 40c a flip, however
-- many are in it.
--
-- What a vendor pays comes from the item facts the Disenchanting tab keeps
-- (Disenchant:GetSellPrice), read once per item and saved, never from the
-- client's item cache on a redraw: reading thousands of scanned items that
-- way pushed his bag items out and broke Ready to sell (2026-09-28).

local _, ns = ...

local Util = ns.Util

local VendorFlips = ns.NewModule("VendorFlips")

--- Every item someone else has on the auction house for less than a vendor
--- pays, with what buying one and selling it to a vendor makes.
--
-- Profit is the vendor price less the buy price. Margin is that profit over
-- the buy price. Your own listings are left out: buying back your own item
-- is not a deal.
--
-- @param opts { profitableOnly, minProfit, minMargin }
--   profitableOnly keeps rows that clear minProfit (at least 1 copper) and
--   minMargin (a percent); both default to Settings.
-- @return rows best profit first, how many flips were held back by the
--   minimums, and how many listed items are still to be read (none are read
--   while the auction house is open)
function VendorFlips:GetAuctionRows(opts)
    opts = opts or {}

    -- Counted for /bts vendordeals, which says how often this ran.
    self.rowBuilds = (self.rowBuilds or 0) + 1

    local rows, hidden, pending = {}, 0, 0
    local prices = ns.Prices and ns.Prices:GetTable() or {}
    local minProfit = opts.minProfit or (ns.Config and ns.Config:Get("minProfit")) or 0
    local minMargin = (opts.minMargin or (ns.Config and ns.Config:Get("minMarginPercent")) or 0) / 100
    local BuyPrice = ns.Disenchant._BuyPrice

    -- Only what the last scan (or a search since) actually saw. A listing
    -- missing from the last scan has sold or expired, but its record keeps
    -- the old price, so without this it stays listed as a deal for days.
    local since = ns.db and ns.db.lastFullScan

    for itemID, record in pairs(prices) do
        local buy = type(record) == "table" and BuyPrice(record)
        if buy and since and (record.seen or 0) < since then buy = nil end

        local vendor = buy and ns.Disenchant:GetSellPrice(itemID)
        if buy and vendor == nil then pending = pending + 1 end

        if vendor and vendor > buy then
            local gain = vendor - buy

            local row = {
                kind = "vendor",
                itemID = itemID,
                name = ns.Disenchant:ItemName(itemID),
                buy = buy,
                loneLow = record.ignoredLow ~= nil and buy == record.ignoredLow or nil,
                listed = record.quantity,
                vendor = vendor,
                gain = gain,
                margin = gain / buy,
                age = ns.Prices:GetAge(itemID),
                stale = ns.Prices:IsStale(itemID),
            }

            local clears = gain >= minProfit and row.margin >= minMargin

            if not opts.profitableOnly or clears then
                rows[#rows + 1] = row
            else
                hidden = hidden + 1
            end
        end
    end

    table.sort(rows, function(a, b)
        if a.gain ~= b.gain then return a.gain > b.gain end
        return a.itemID < b.itemID
    end)

    return rows, hidden, pending
end

--- After a scan: say how many flips it found and the best one, with the
--- sound of coins when there is at least one. Quiet when there are none.
function VendorFlips:AnnounceDeals()
    local ok, rows = pcall(self.GetAuctionRows, self, { profitableOnly = true })
    if not ok or type(rows) ~= "table" or #rows == 0 then return 0 end

    local best = rows[1]
    local total = 0
    for _, row in ipairs(rows) do total = total + row.gain end

    ns.Print(("Vendor flips: %d item%s on the auction house under what a vendor pays, %s together if you buy one of each. Best: %s for %s, a vendor pays %s. See the Vendor Flips tab."):format(
        #rows, #rows == 1 and "" or "s", Util.FormatMoney(total, { noColor = true }),
        Util.GetItemLabel(best.itemID), Util.FormatMoney(best.buy, { noColor = true }),
        Util.FormatMoney(best.vendor, { noColor = true })))

    if type(PlaySound) == "function" then
        local kits = type(_G.SOUNDKIT) == "table" and _G.SOUNDKIT or {}
        local sound = kits.LOOT_WINDOW_COIN_SOUND or kits.UI_EPICLOOT_TOAST
        if sound then pcall(PlaySound, sound) end
    end

    return #rows
end

--------------------------------------------------------------------------------
-- /bts vendordeals: why each flip is on the Vendor Flips tab
--------------------------------------------------------------------------------

local function Ago(stamp)
    if not stamp then return "never" end
    return Util.FormatAge(math.max(0, time() - stamp)) .. " ago"
end

ns.RegisterCommand("vendordeals", "say why each item on the Vendor Flips tab is there", function()
    local lastScan = ns.db and ns.db.lastFullScan
    ns.Print(("vendordeals: last full scan %s, price records changed %d time(s) since /reload")
        :format(Ago(lastScan), ns.Prices and ns.Prices.changes or 0))

    local shown = VendorFlips.shownRows
    if shown then
        ns.Print(("vendordeals: the tab's list was built %s, %d row(s)")
            :format(Ago(VendorFlips.shownBuiltAt), #shown))
    else
        ns.Print("vendordeals: the tab has not built its list since /reload (open the Vendor Flips tab)")
    end

    local fresh, hidden, pending = VendorFlips:GetAuctionRows({ profitableOnly = true })
    ns.Print(("vendordeals: built fresh now it would have %d flip(s), %d under your minimums, %d item(s) with no vendor price read yet")
        :format(#fresh, hidden or 0, pending or 0))

    local prices = ns.Prices and ns.Prices:GetTable() or {}
    for index, row in ipairs(shown or fresh) do
        if index > 5 then break end
        local record = prices[row.itemID] or {}
        ns.Print(("vendordeals: %s (%d): buy %s, vendor pays %s, last seen %s%s, cheapest other seller %s, lone low %s, yours %s")
            :format(row.name or "?", row.itemID,
                Util.FormatMoney(row.buy, { noColor = true }),
                Util.FormatMoney(row.vendor, { noColor = true }),
                Ago(record.seen),
                (lastScan and record.seen and record.seen < lastScan) and " (NOT in the last scan)" or "",
                record.rivalMin and Util.FormatMoney(record.rivalMin, { noColor = true }) or "none",
                record.ignoredLow and Util.FormatMoney(record.ignoredLow, { noColor = true }) or "none",
                record.ownMin and Util.FormatMoney(record.ownMin, { noColor = true }) or "none"))
    end
end)
