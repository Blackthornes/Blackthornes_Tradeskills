-- What a vendor really pays (2026-10-09).
--
-- kickemhard's report: the Deals tab listed Minor Wizard Oil at 4s to sell
-- to a vendor for 5s, when a vendor on Forever pays 1s for it. Both the
-- item info and the tooltip say 5s, and the oil has 5 charges.
--
-- What this pins down:
--   * selling at a merchant teaches what a vendor pays for one, from the
--     buyback list (the price there is for the whole stack);
--   * a payout seen on Forever beats the item info and the tooltip, in the
--     Deals tab's price and the shared vendor price alike;
--   * Minor Wizard Oil ships at 1s, and a sale of your own beats that;
--   * a charged item nobody has sold yet is not offered as a vendor flip;
--   * consumables read before charges were kept are read once more.

local ns = {}
ns.COLORS = setmetatable({}, { __index = function() return "ffffffff" end })
ns.NewModule = function(name) local m = {}; ns[name] = m; return m end
local commands = {}
ns.RegisterCommand = function(name, _, fn) commands[name] = fn end
ns.RegisterEvent = function() end
local printed = {}
ns.Print = function(text) printed[#printed + 1] = text end
ns.PrintRaw, ns.Debug, ns.Warn = function() end, function() end, function() end

local GLOBALS = { "C_Item", "GetTime", "C_TooltipInfo", "C_MerchantFrame", "GetNumBuybackItems",
                  "GetBuybackItemInfo", "GetBuybackItemLink", "C_Timer" }
local saved = {}
for _, key in ipairs(GLOBALS) do saved[key] = _G[key] end

GetTime = function() return 1 end
time = time or os.time

local OIL, LESSER_OIL, CLOTH, FLASK = 20744, 20746, 3001, 3009

-- itemID -> quality, item info sell price, class (0 = consumable)
local items = {
    [OIL] = { 1, 500, 0 },
    [LESSER_OIL] = { 1, 1000, 0 },
    [CLOTH] = { 1, 500, 7 },
    [FLASK] = { 1, 300, 0 },
}

C_Item = {
    GetItemInfo = function(itemID)
        local item = items[itemID]
        if not item then return nil end
        return "item" .. itemID, nil, item[1], 10, 1, "Type", "Sub", 20, "", 1, item[2], item[3], 1, 2
    end,
    GetItemInfoInstant = function(itemID) return itemID end,
    IsItemDataCachedByID = function() return true end,
    RequestLoadItemDataByID = function() end,
}

-- The tooltip agrees with the item info, and names the charges.
local charges = { [OIL] = 5, [LESSER_OIL] = 5 }
local tooltipReads = {}
C_TooltipInfo = {
    GetItemByID = function(itemID)
        tooltipReads[itemID] = (tooltipReads[itemID] or 0) + 1
        local lines = { { type = 0, leftText = "item" .. itemID } }
        if charges[itemID] then
            lines[#lines + 1] = { type = 0, leftText = ("%d Charges"):format(charges[itemID]) }
        end
        lines[#lines + 1] = { type = 11, price = items[itemID][2] }
        return { lines = lines }
    end,
}

assert(loadfile(lfs_cwd .. "/Core/Util.lua"))("Blackthornes_TS", ns)

local records = {
    [OIL] = { rivalMin = 400, quantity = 3 },
    [LESSER_OIL] = { rivalMin = 400, quantity = 2 },
    [CLOTH] = { rivalMin = 200, quantity = 4 },
}

ns.Config = { Get = function() return 0 end, GetCharacterKey = function() return "Tester-Realm" end }
ns.Prices = {
    GetTable = function() return records end,
    GetValue = function() return nil end,
    GetAge = function() return 600 end,
    IsStale = function() return false end,
    Count = function() return 3 end,
}
ns.Cost = { InvalidateIndex = function() end }
ns.db = { characters = {} }

assert(loadfile(lfs_cwd .. "/Data/VendorPrices.lua"))("Blackthornes_TS", ns)
assert(loadfile(lfs_cwd .. "/Data/Vendor.lua"))("Blackthornes_TS", ns)
assert(loadfile(lfs_cwd .. "/Logic/Disenchant.lua"))("Blackthornes_TS", ns)
assert(loadfile(lfs_cwd .. "/Logic/VendorFlips.lua"))("Blackthornes_TS", ns)

local Vendor, VendorFlips = ns.Vendor, ns.VendorFlips

local checks = 0
local function check(label, condition)
    checks = checks + 1
    if not condition then error(("FAILED: %s"):format(label), 2) end
    print(("  ok  %s"):format(label))
end

local function Find(rows, itemID)
    for _, row in ipairs(rows) do
        if row.itemID == itemID then return row end
    end
end

print("\nthe tooltip says how many charges")

local price, read, count = ns.Util.GetTooltipSellPrice(OIL)
check("Minor Wizard Oil's tooltip price is read", price == 500 and read == true)
check("and its 5 charges", count == 5)
check("an item without charges has none", select(3, ns.Util.GetTooltipSellPrice(CLOTH)) == nil)

print("\nMinor Wizard Oil ships at what Forever pays")

check("1s, reported", Vendor:GetPaid(OIL) == 100 and select(2, Vendor:GetPaid(OIL)) == "reported")
check("the Deals tab's price is the 1s", ns.Disenchant:GetSellPrice(OIL) == 100)
check("and so is the shared vendor price", ns.Util.GetVendorSellPrice(OIL) == 100)

local rows = VendorFlips:GetAuctionRows()
check("a 4s oil is no vendor flip", Find(rows, OIL) == nil)
check("plain cloth under its vendor price still is", Find(rows, CLOTH) and Find(rows, CLOTH).gain == 300)
check("from the game's item data", Find(rows, CLOTH).vendorFrom == nil)

print("\na charged item nobody has sold is held back")

check("Lesser Wizard Oil's item data says 10s", ns.db.itemFacts[LESSER_OIL] == nil
    or ns.db.itemFacts[LESSER_OIL].v == 1000)
check("it has charges and no payout seen", ns.Disenchant:SellPriceUnsure(LESSER_OIL))
check("so a 4s listing is not offered as a 6s flip", Find(VendorFlips:GetAuctionRows(), LESSER_OIL) == nil)

print("\nselling at a merchant teaches what a vendor pays")

-- Sold: 3 Lesser Wizard Oil for 6s (2s each) and one Minor Wizard Oil for 80c.
local buyback = {
    { LESSER_OIL, 600, 3 },
    { OIL, 80, 1 },
}
GetNumBuybackItems = function() return #buyback end
GetBuybackItemInfo = function(index)
    local entry = buyback[index]
    return "item" .. entry[1], 1, entry[2], entry[3], -1, true
end
GetBuybackItemLink = function(index) return ("|Hitem:%d::::|h[x]|h"):format(buyback[index][1]) end

check("two payouts learned", Vendor:ReadBuyback() == 2)
check("the stack price is split: 2s each", Vendor:GetPaid(LESSER_OIL) == 200)
check("a sale beats the reported price", Vendor:GetPaid(OIL) == 80
    and select(2, Vendor:GetPaid(OIL)) == "sold")
check("kept in the saved data", ns.db.vendorPaid[LESSER_OIL].pay == 200)
check("nothing new the second time", Vendor:ReadBuyback() == 0)
check("no longer unsure", not ns.Disenchant:SellPriceUnsure(LESSER_OIL))
check("the Deals tab reads the 2s", ns.Disenchant:GetSellPrice(LESSER_OIL) == 200)
check("and the shared price too", ns.Util.GetVendorSellPrice(LESSER_OIL) == 200)
check("a 4s listing is still no flip", Find(VendorFlips:GetAuctionRows(), LESSER_OIL) == nil)

records[LESSER_OIL].rivalMin = 150
local flip = Find(VendorFlips:GetAuctionRows(), LESSER_OIL)
check("at 1s 50c it is a 50c flip", flip and flip.gain == 50)
check("saying a sale of yours set the price", flip.vendorFrom == "sold")

-- The newer id lookup is used when the client has it.
C_MerchantFrame = { GetBuybackItemID = function(index) return buyback[index][1] end }
GetBuybackItemLink = nil
buyback[1] = { LESSER_OIL, 750, 3 }
check("read by item ID as well", Vendor:ReadBuyback() == 1 and Vendor:GetPaid(LESSER_OIL) == 250)

-- A value that raises when touched is skipped, never fatal.
GetBuybackItemInfo = function() error("secret") end
check("an unreadable buyback list changes nothing", Vendor:ReadBuyback() == 0
    and Vendor:GetPaid(LESSER_OIL) == 250)

print("\nconsumables read before charges were kept are read once more")

ns.db.itemFacts[FLASK] = { n = "item" .. FLASK, q = 1, l = 10, c = 0, e = "", v = 300, vt = true }
charges[FLASK] = 3
tooltipReads = {}
ns.Disenchant:GetSellPrice(FLASK)
check("read again for its charges", tooltipReads[FLASK] == 1 and ns.db.itemFacts[FLASK].ch == 3)
ns.Disenchant:GetSellPrice(FLASK)
check("and only once", tooltipReads[FLASK] == 1)

ns.db.itemFacts[CLOTH].vt = true
tooltipReads = {}
ns.Disenchant:GetSellPrice(CLOTH)
check("other items are not read again", tooltipReads[CLOTH] == nil)

print("\n/bts sellprice says what a vendor paid")

printed = {}
commands.sellprice(tostring(LESSER_OIL))
check("it names the payout and the charges", printed[1]:find("a vendor paid you") and printed[1]:find("5 charges"))

for _, key in ipairs(GLOBALS) do _G[key] = saved[key] end

print(("\n%d checks passed"):format(checks))
