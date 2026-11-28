-- Bartering, a Legacy perk (the owner said yes, 2026-11-26): vendors charge
-- 5% less a rank, 10% at its 2 ranks. Shop prices follow only the ranks
-- spent; none spent changes nothing. A price seen at a merchant already had
-- the discount of that moment, so it is moved to today's, never cut twice.
-- What vendors pay for what you sell does not change.

local GLOBALS = { "C_Traits", "C_ClassTalents", "C_Spell", "C_Timer", "Enum",
    "C_MerchantFrame", "GetMerchantNumItems", "time" }
local saved = {}
for _, key in ipairs(GLOBALS) do saved[key] = _G[key] end

local passed, failed = 0, 0
local function check(label, got, want)
    local ok = got == want
    if ok then passed = passed + 1 else failed = failed + 1 end
    print(string.format("  %-58s %-10s %s", label, tostring(got), ok and "ok" or
        ("WRONG, wanted " .. tostring(want))))
end

local function noop() end
local ns = {}
ns.NewModule = function(name) local m = {}; ns[name] = m; return m end
ns.RegisterEvent, ns.RegisterCommand = noop, noop
ns.Print, ns.PrintRaw, ns.Debug, ns.Warn = noop, noop, noop, noop
ns.Util = {
    HasFunction = function(path) return path == "C_MerchantFrame.GetItemInfo" or path == "GetMerchantNumItems" end,
    Count = function(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end,
}
local invalidated = 0
ns.Cost = { InvalidateIndex = function() invalidated = invalidated + 1 end }
ns.db = {}

local VIAL, THREAD, DYE = 3371, 2320, 2324
ns.VENDOR_PRICES = { [VIAL] = 20, [THREAD] = 10, [DYE] = 25 }

-- The Legacy config (42), with Bartering's node found by its spell ID.
local BARTER_NODE = 110291
local barterRank = 0
C_ClassTalents = { GetActiveConfigID = function() return 7 end }
C_Traits = {
    GetConfigIDBySystemID = function(id) if id == 5 then return 42 end end,
    GetConfigIDByTreeID = function() return nil end,
    GetConfigInfo = function(configID)
        if configID == 42 then return { ID = 42, name = "", treeIDs = { 900 } } end
    end,
    GetTreeNodes = function() return { BARTER_NODE } end,
    GetNodeInfo = function(configID, nodeID)
        if configID ~= 42 or nodeID ~= BARTER_NODE then return { ID = 0 } end
        return { ID = nodeID, ranksPurchased = barterRank, maxRanks = 2, entryIDs = { 1 } }
    end,
    GetEntryInfo = function() return { definitionID = 2 } end,
    GetDefinitionInfo = function() return { spellID = 1225459, overrideName = "Tauschhandel" } end,
}
C_Spell = { GetSpellName = function() return "Tauschhandel" end, RequestLoadSpellData = noop }
C_Timer, Enum = nil, nil
time = function() return 1000 end

assert(loadfile(lfs_cwd .. "/Logic/Legacy.lua"))("Blackthornes_TS", ns)
assert(loadfile(lfs_cwd .. "/Data/Vendor.lua"))("Blackthornes_TS", ns)
local Legacy, Vendor = ns.Legacy, ns.Vendor

-- One merchant: vials at what it charges now.
local merchantVial = 20
C_MerchantFrame = { GetItemInfo = function(index)
    if index == 1 then return { itemID = VIAL, price = merchantVial, stackCount = 1, numAvailable = -1 } end
end }
GetMerchantNumItems = function() return 1 end

print("")
print("before the perks are read")
check("shipped vial price is full price", Vendor:GetUnitPrice(VIAL), 20)
Vendor:Scan()
check("a price seen now keeps no discount mark", ns.db.vendorPrices[VIAL].off, nil)
ns.db.vendorPrices[VIAL] = nil
invalidated = 0

print("")
print("no Bartering spent")
Legacy:Search()
check("the config is found", Legacy.configID, 42)
check("no ranks: no discount", Legacy:VendorDiscount(), 0)
check("no ranks: thread stays 10c", Vendor:GetUnitPrice(THREAD), 10)
check("no ranks and nothing changed: costs kept", invalidated, 0)

print("")
print("Bartering 2 of 2, found by spell ID in any language")
barterRank = 2
Legacy:Changed()
check("10% off", math.abs(Legacy:VendorDiscount() - 0.1) < 1e-9, true)
check("found by spell ID, not the name", Legacy:PerkNode("bartering"), BARTER_NODE)
check("costs are worked out again", invalidated, 1)
check("shipped dye 25c is 23c (rounded)", Vendor:GetUnitPrice(DYE), 23)
check("shipped thread 10c is 9c", Vendor:GetUnitPrice(THREAD), 9)
check("a 1c item never drops to 0", Vendor:Discounted(1), 1)

merchantVial = 18
Vendor:Scan()
check("seen at the merchant: 18c, marked 10% off", ns.db.vendorPrices[VIAL].price, 18)
check("seen at 10% with 10% now: not cut twice", Vendor:GetUnitPrice(VIAL), 18)

print("")
print("down to rank 1")
barterRank = 1
Legacy:Changed()
check("5% off", math.abs(Legacy:VendorDiscount() - 0.05) < 1e-9, true)
check("the 18c seen at 10% off moves to 19c", Vendor:GetUnitPrice(VIAL), 19)
check("thread at 5% off is 10c (rounded)", Vendor:GetUnitPrice(THREAD), 10)

print("")
print("reset to none")
barterRank = 0
Legacy:Changed()
check("seen at 10% off, now full: 20c again", Vendor:GetUnitPrice(VIAL), 20)
check("shipped dye full again", Vendor:GetUnitPrice(DYE), 25)

print("")
print("an older price, kept before the mark")
barterRank = 2
Legacy:Changed()
ns.db.vendorPrices[THREAD] = { price = 9, stack = 1 }
check("left as seen, never cut twice", Vendor:GetUnitPrice(THREAD), 9)
ns.db.vendorPrices[THREAD] = { price = 9, stack = 1, extendedCost = true }
check("token items still have no gold price", Vendor:GetUnitPrice(THREAD), nil)

print("")
print("what vendors pay is not changed")
ns.FOREVER_SELL_PRICES[20744] = 100
check("a payout stays as seen", Vendor:GetPaid(20744), 100)

print("")
print("nothing read")
Legacy.configID, Legacy.searched, Legacy.searching = nil, nil, nil
Legacy:Forget()
check("perks not read yet: shipped price full", Vendor:GetUnitPrice(DYE), 25)
check("and a marked price as seen", Vendor:GetUnitPrice(VIAL), 18)
check("no Legacy file: full price", (function()
    local keep = ns.Legacy; ns.Legacy = nil
    local p = Vendor:GetUnitPrice(DYE); ns.Legacy = keep; return p end)(), 25)

for _, key in ipairs(GLOBALS) do _G[key] = saved[key] end

print("")
print(("%d passed, %d failed"):format(passed, failed))
assert(failed == 0, "bartering checks failed")
