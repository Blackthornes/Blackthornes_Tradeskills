-- Merchant's Favor on the Deals tab: Waylaid Crates by what a point of
-- favor costs bought on the auction house (a player's idea, 2026-10-08).
--
-- What this pins down:
--   * crate names are read whole word by whole word, whatever the order;
--   * a favor costs the crate + its cheapest bundle - the silver back, over
--     the favor it pays, and a bundle over one stack is left out when asked;
--   * the rewards players report stand in until a turn-in is seen, and
--     Artisan crates, which nobody has handed in, have none and sort last;
--   * filling a crate says which sealed crate it becomes, and a sealed crate
--     leaving the bags with favor and money coming in is what it paid; the
--     smallest favor seen is kept, as a perk doubles some turn-ins;
--   * a bundle is priced as the rest of the addon prices a material, except
--     that a shop with limited stock gives way to an auction listing, and a
--     vendor price is marked;
--   * the game's item ID for a crate beats the typed one;
--   * the Deals tab's Show menu swaps in the view, which lists, sorts and
--     explains the crates, and its tick box is kept in Settings.

local ns = {}
ns.COLORS = setmetatable({}, { __index = function() return "ffffffff" end })
ns.NewModule = function(name) local m = {}; ns[name] = m; return m end
ns.RegisterCommand = function() end
local handlers = {}
ns.RegisterEvent = function(_, event, fn) handlers[event] = handlers[event] or {}; table.insert(handlers[event], fn) end
local function Fire(event, ...)
    for _, fn in ipairs(handlers[event] or {}) do fn(nil, event, ...) end
end

local printed = {}
ns.Print = function(text) printed[#printed + 1] = text end
ns.PrintRaw, ns.Debug, ns.Warn = function() end, function() end, function() end

-- Put back at the end: every suite shares one Lua runtime.
local saved = { C_Item = C_Item, GetTime = GetTime, CreateFrame = CreateFrame, GameTooltip = GameTooltip,
                C_Timer = C_Timer, C_CurrencyInfo = C_CurrencyInfo, GetMoney = GetMoney }

local clock = 100
GetTime = function() return clock end
time = time or os.time

local later = {}
C_Timer = { After = function(_, fn) later[#later + 1] = fn end }
local function Flush()
    local run = later
    later = {}
    for _, fn in ipairs(run) do fn() end
end

local LINEN, LEATHER, PEACEBLOOM, SILVERLEAF = 2589, 2318, 2447, 765
local TEXTILES, HERBS, SEALED, SOMETHING = 248684, 248690, 249000, 248600

-- itemID -> name, max stack
local items = {
    [TEXTILES] = { "Waylaid Crate: Apprentice Textiles", 5 },
    [HERBS] = { "Waylaid Crate: Apprentice Herbs", 5 },
    [SOMETHING] = { "Some Other Forever Item", 1 },
    [SEALED] = { "Sealed Apprentice Crate", 5 },
    [LINEN] = { "Linen Cloth", 20 },
    [LEATHER] = { "Light Leather", 20 },
    [PEACEBLOOM] = { "Peacebloom", 20 },
    [SILVERLEAF] = { "Silverleaf", 20 },
}

local asked = {}
C_Item = {
    GetItemInfo = function(itemID)
        local item = items[itemID]
        if not item then return nil end
        return item[1], "link" .. itemID, 1, 10, 1, "Trade Goods", "Cloth", item[2]
    end,
    RequestLoadItemDataByID = function(itemID) asked[itemID] = true end,
}

assert(loadfile(lfs_cwd .. "/Core/Util.lua"))("Blackthornes_TS", ns)

-- Copper for one, the cheapest listing.
local prices = {
    [TEXTILES] = 2000,
    [HERBS] = 1000,
    [LINEN] = 30,
    [LEATHER] = 80,
    [PEACEBLOOM] = 10,
    [SILVERLEAF] = 5,
}

local config = {}
ns.Config = {
    Get = function(_, key) return config[key] end,
    Set = function(_, key, value) config[key] = value end,
}
-- Items whose record says none are listed now.
local noneListed = {}
ns.Prices = {
    GetValue = function(_, itemID) return prices[itemID] end,
    ListedNow = function(_, itemID)
        if noneListed[itemID] then return nil, true end
        return prices[itemID], false
    end,
    Count = function() return 6 end,
}
-- Shops, as Cost prices them: a vendor's price beats the auction house's.
-- itemID -> { price, limited }
local shops = {}
ns.Cost = {
    GetReagentUnitCost = function(_, itemID)
        if shops[itemID] then return shops[itemID][1], "vendor" end
        return prices[itemID], "buy"
    end,
}
ns.Vendor = { IsLimited = function(_, itemID) return shops[itemID] ~= nil and shops[itemID][2] == true end }

local bags = {}
ns.Inventory = {
    GetBagCounts = function() return bags end,
    GetBagCount = function(_, itemID) return bags[itemID] or 0 end,
}

ns.db = {}

assert(loadfile(lfs_cwd .. "/Data/WaylaidCrates.lua"))("Blackthornes_TS", ns)
assert(loadfile(lfs_cwd .. "/Logic/MerchantsFavor.lua"))("Blackthornes_TS", ns)

local MerchantsFavor = ns.MerchantsFavor

local checks = 0
local function check(label, condition)
    checks = checks + 1
    if not condition then error(("FAILED: %s"):format(label), 2) end
    print(("  ok  %s"):format(label))
end

local function Row(rows, key)
    for _, row in ipairs(rows) do
        if row.key == key then return row end
    end
end

local function Crate(key)
    for _, crate in ipairs(ns.WAYLAID_CRATES) do
        if crate.key == key then return crate end
    end
end

--------------------------------------------------------------------------------
print("\nthe typed rewards")

check("Journeyman Textiles pays 10 favor and 5s", Crate("journeyman-textiles").favor == 10
    and Crate("journeyman-textiles").silver == 500)
check("plain goods pay 5, 10 or 15 by tier, crafted goods 10, 20 or 30", (function()
    local plain = { curiosities = true, herbs = true, earthly = true, flowering = true, ore = true, textiles = true }
    for _, crate in ipairs(ns.WAYLAID_CRATES) do
        if crate.favor then
            local kind = crate.key:match("%-(%a+)$")
            local want = (plain[kind] and 5 or 10) * crate.tier
            if crate.favor ~= want or crate.silver ~= crate.favor * 50 then return false end
        end
    end
    return true
end)())
check("every crate has its item ID", (function()
    for _, crate in ipairs(ns.WAYLAID_CRATES) do
        if type(crate.id) ~= "number" then return false end
    end
    return true
end)())

local function Takes(key, itemID, count)
    for _, bundle in ipairs(Crate(key).bundles) do
        if bundle[1] == itemID then return bundle[2] == count end
    end
    return false
end
check("Artisan Ore takes Truesilver Ore", Takes("artisan-ore", 7911, 10))
check("Artisan Earthly Herbs takes Sungrass", Takes("artisan-earthly", 8838, 20))
check("Artisan Textiles takes Thick Leather", Takes("artisan-textiles", 4304, 20))
check("Artisan Ingots takes Truesilver Bar", Takes("artisan-ingots", 6037, 10))
check("Artisan Parts takes Truesilver Transformer", Takes("artisan-parts", 18631, 5))
check("Artisan Parts takes 2 Thorium Tube", Takes("artisan-parts", 16000, 2))

-- The checks below find crates by name, as for a crate the game names
-- under another ID, so these start without a typed one.
Crate("apprentice-herbs").id = nil
Crate("expert-ore").id = nil
Crate("artisan-ore").id = nil

--------------------------------------------------------------------------------
print("\nreading crate names")

local function Key(name)
    local crate = MerchantsFavor.CrateForName(name)
    return crate and crate.key
end

check("a crate's name finds it", Key("Waylaid Crate: Journeyman Ore") == "journeyman-ore")
check("whatever the case", Key("WAYLAID CRATE: apprentice herbs") == "apprentice-herbs")
check("in either word order", Key("Waylaid Crate: Earthly Expert") == "expert-earthly"
    and Key("Waylaid Crate: Expert Flowering Herbs") == "expert-flowering")
check("whole words only: Curiosities holds no ore", Key("Waylaid Crate: Apprentice Curiosities")
    == "apprentice-curiosities")
check("other items are not crates", Key("Iron Ore") == nil and Key(nil) == nil)
check("a filled crate is sealed", MerchantsFavor.IsSealedName("Sealed Apprentice Crate")
    and MerchantsFavor.IsSealedName("Stocked Journeyman Crate")
    and not MerchantsFavor.IsSealedName("Waylaid Crate: Apprentice Ore"))

--------------------------------------------------------------------------------
print("\nwhat a favor costs")

local rows = MerchantsFavor:GetRows({ skipOverStack = true })
check("every crate is a row", #rows == #ns.WAYLAID_CRATES)

local textiles = Row(rows, "apprentice-textiles")
check("the crate is priced from the auction house", textiles.cratePrice == 2000)
check("40 Linen Cloth is over a stack", textiles.bundles[1].overStack == true and textiles.bundles[1].cost == 1200)
check("so the cheapest bundle is the leather", textiles.best.itemID == LEATHER and textiles.bundleCost == 1600)
check("with the reported 5 favor and 2s 50c", textiles.favor == 5 and textiles.money == 250
    and textiles.source == "reported")
check("total is crate + bundle - silver back", textiles.total == 2000 + 1600 - 250)
check("and a favor is a fifth of that", textiles.perFavor == 670)

-- None on the auction house: no crate to buy, so no price (a player asked,
-- 2026-10-11, for the column to go blank rather than show the average).
noneListed[textiles.itemID] = true
local gone = Row(MerchantsFavor:GetRows({ skipOverStack = true }), "apprentice-textiles")
check("with none listed the crate column is blank", gone.cratePrice == nil and gone.noneListed == true
    and gone.total == nil and gone.perFavor == nil)
check("but its bundle is still worked out", gone.bundleCost == 1600)
noneListed[textiles.itemID] = nil

local herbs = Row(rows, "apprentice-herbs")
check("a crate the game has not shown yet has no price", herbs.itemID == nil and herbs.cratePrice == nil
    and herbs.perFavor == nil)
check("but its cheapest bundle is still worked out", herbs.bundleCost == 100 and herbs.best.itemID == SILVERLEAF)

local artisan = Row(rows, "artisan-ore")
check("Artisan crates have no reward", artisan.favor == nil and artisan.source == nil)
check("unknown and unpriced crates sort after priced ones", rows[1].key == "apprentice-textiles"
    and rows[#rows].tier == 4)

rows = MerchantsFavor:GetRows({ skipOverStack = false })
textiles = Row(rows, "apprentice-textiles")
check("counting over-stack bundles, the linen is cheapest", textiles.best.itemID == LINEN
    and textiles.perFavor == (2000 + 1200 - 250) / 5)

--------------------------------------------------------------------------------
print("\nvendor prices in a bundle")

-- Reported 2026-10-09: 20 Heavy Leather read 20s, 1s each, while the
-- auction house wanted 10s 58c.
shops[SILVERLEAF] = { 1, true }
shops[PEACEBLOOM] = { 2, false }
herbs = Row(MerchantsFavor:GetRows({ skipOverStack = true }), "apprentice-herbs")
local silverleaf, peacebloom = herbs.bundles[2], herbs.bundles[1]
check("a shop with limited stock gives way to the auction house", silverleaf.itemID == SILVERLEAF
    and silverleaf.unit == 5 and silverleaf.cost == 100 and not silverleaf.vendor)
check("a shop that never runs out keeps its price, marked", peacebloom.itemID == PEACEBLOOM
    and peacebloom.unit == 2 and peacebloom.vendor == true and herbs.best == peacebloom)

prices[SILVERLEAF] = nil
herbs = Row(MerchantsFavor:GetRows({ skipOverStack = true }), "apprentice-herbs")
check("with nothing listed, the limited shop is all there is", herbs.bundles[2].unit == 1
    and herbs.bundles[2].vendor == true)

prices[SILVERLEAF] = 5
shops[SILVERLEAF], shops[PEACEBLOOM] = nil, nil

--------------------------------------------------------------------------------
print("\nfinding crates in the game")

MerchantsFavor:FindCrates()
check("a crate in Forever's item IDs is found by name", MerchantsFavor:GetCrateID(ns.WAYLAID_CRATES[2]) == HERBS
    and ns.db.merchantsFavor.crateIDs["apprentice-herbs"] == HERBS)
check("unknown item IDs are asked for", asked[248541] == true)

items[248541] = { "Waylaid Crate: Expert Ore", 5 }
MerchantsFavor:OnItemInfo(248541)
check("and read when they arrive", ns.db.merchantsFavor.crateIDs["expert-ore"] == 248541)

ns.db.merchantsFavor.crateIDs["apprentice-textiles"] = 248699
check("the game's item ID beats the typed one", MerchantsFavor:GetCrateID(ns.WAYLAID_CRATES[4]) == 248699)
ns.db.merchantsFavor.crateIDs["apprentice-textiles"] = nil

rows = MerchantsFavor:GetRows({ skipOverStack = true })
herbs = Row(rows, "apprentice-herbs")
check("found, it is priced", herbs.cratePrice == 1000 and herbs.total == 1000 + 100 - 250 and herbs.perFavor == 170)
check("and now the cheapest favor", rows[1].key == "apprentice-herbs")

--------------------------------------------------------------------------------
print("\nlearning what a turn-in pays")

local money = 1000
GetMoney = function() return money end
C_CurrencyInfo = {
    GetCurrencyInfo = function(id)
        if id == 3001 then return { name = "Merchant's Favor" } end
        return { name = "Honor" }
    end,
}

bags = { [HERBS] = 2, [SOMETHING] = 1, [LINEN] = 40 }
MerchantsFavor:OnEnable()
check("the bags are looked at once to start", MerchantsFavor.held[HERBS] == 2 and MerchantsFavor.held[LINEN] == nil)

-- Filling: one crate goes, a sealed one comes.
bags = { [HERBS] = 1, [SEALED] = 1 }
Fire("BAG_UPDATE_DELAYED")
check("filling a crate says which sealed crate it is", ns.db.merchantsFavor.links["apprentice-herbs"] == SEALED)

-- Handing it in: the favor, then the money, then the bags.
clock = 200
Fire("CURRENCY_DISPLAY_UPDATE", 3001, 5, 5)
Fire("CURRENCY_DISPLAY_UPDATE", 1792, 10, 10)
money = 1250
Fire("PLAYER_MONEY")
clock = 201
bags = { [HERBS] = 1 }
Fire("BAG_UPDATE_DELAYED")
Flush()

local learned = ns.db.merchantsFavor.rewards[SEALED]
check("the turn-in's favor and money are kept", learned and learned.favor == 5 and learned.money == 250
    and learned.turnIns == 1)

herbs = Row(MerchantsFavor:GetRows({}), "apprentice-herbs")
check("the crate now says it was seen paid", herbs.source == "learned" and herbs.turnIns == 1)

-- A turn-in the perk doubled.
bags = { [SEALED] = 1 }
Fire("BAG_UPDATE_DELAYED")
clock = 300
bags = {}
Fire("BAG_UPDATE_DELAYED")
Fire("CURRENCY_DISPLAY_UPDATE", 3001, 15, 10)
money = 1500
Fire("PLAYER_MONEY")
Flush()
check("a doubled turn-in is counted, the smaller favor kept", learned.favor == 5 and learned.turnIns == 2)

-- A sealed crate thrown away, with no favor coming in.
bags = { [SEALED] = 1 }
Fire("BAG_UPDATE_DELAYED")
clock = 400
bags = {}
Fire("BAG_UPDATE_DELAYED")
clock = 420
Flush()
Fire("CURRENCY_DISPLAY_UPDATE", 3001, 20, 5)
Flush()
check("favor long after a crate went is not put down to it", learned.turnIns == 2)

-- Raising client values in an instance are no error.
local raising = C_CurrencyInfo.GetCurrencyInfo
C_CurrencyInfo.GetCurrencyInfo = function() error("secret") end
local ok = pcall(Fire, "CURRENCY_DISPLAY_UPDATE", 9999, 1, 1)
check("a secret currency is ignored, not an error", ok)
C_CurrencyInfo.GetCurrencyInfo = raising

--------------------------------------------------------------------------------
print("\nthe view on the Deals tab")

bags = { [HERBS] = 1 }

local function Stub(fields)
    local frame = fields or {}
    frame.IsVisible = frame.IsVisible or function() return true end
    frame.SetShown = frame.SetShown or function(self, value) rawset(self, "shown", value) end
    frame.Hide = frame.Hide or function(self) rawset(self, "shown", false) end
    return setmetatable(frame, { __index = function(self, key)
        local noop = function() end
        rawset(self, key, noop)
        return noop
    end })
end

local labels = {}
local function Label()
    local label = Stub({
        text = "",
        SetText = function(self, value) self.text = tostring(value) end,
        GetText = function(self) return self.text end,
        SetTextColor = function(self, a) self.color = a end,
    })
    labels[#labels + 1] = label
    return label
end

CreateFrame = function() return Stub() end
GameTooltip = Stub({ lines = {}, AddLine = function(self, text) self.lines[#self.lines + 1] = text end })

ns.Theme = {
    SetRowName = function(label, text) label:SetText(text) end,
    SetItemNameColor = function() return false end,
    CreateLabel = function() return Label() end,
    CreatePanel = function() return Stub() end,
    CreateDivider = function() return Stub() end,
    Unpack = function(key) return key end,
    ProfitColor = function(value) return (value or 0) >= 0 and "profit" or "loss" end,
    AccentStripe = function() return Stub() end,
    CreateItemIcon = function() return Stub() end,
    SetItemIcon = function() end,
    CreateHeading = function(_, text) local label = Label(); label.text = text; return label end,
    CreateBar = function() return Stub({ track = Stub() }) end,
    FitText = function(label, texts) label:SetText(texts[1]); return texts[1] end,
}

local checkboxes, lists, dropdowns, buttons = {}, {}, {}, {}
local searched
ns.Widgets = {
    CreateDropdown = function(_, options, onSelect, opts)
        local dropdown = Stub({ options = options, onSelect = onSelect, opts = opts })
        dropdowns[#dropdowns + 1] = dropdown
        return dropdown
    end,
    CreateSearchBox = function(_, _, onChange) searched = onChange; return Stub() end,
    CreateCheckbox = function(_, text, onToggle, initial)
        local box = Stub({ onToggle = onToggle, initial = initial })
        checkboxes[text] = box
        return box
    end,
    CreateButton = function(_, text, onClick) local button = Stub({ onClick = onClick }); buttons[text] = button; return button end,
    ShowItemTooltip = function() return true end,
    CreateScrollList = function(_, opts)
        local list = Stub({ opts = opts, SetData = function(self, data) self.data = data end })
        lists[#lists + 1] = list
        return list
    end,
}

local sent = {}
ns.Scanner = { isAuctionHouseOpen = true }
local tabs = {}
ns.UI = Stub({
    RegisterTab = function(_, tab) tabs[tab.key] = tab end,
    SearchAuctionHouse = function(_, itemID) sent[#sent + 1] = itemID; return true end,
})
ns.Disenchant = { factsVersion = 0, WasRequested = function() return false end }
ns.VendorFlips = {
    GetAuctionRows = function() return {}, 0, 0 end,
    GetResaleRows = function() return {}, 0, 0 end,
    MIN_RESALE_SCANS = 3,
}
ns.Demand = { TooltipText = function() return nil end }

assert(loadfile(lfs_cwd .. "/UI/Columns.lua"))("Blackthornes_TS", ns)

assert(loadfile(lfs_cwd .. "/UI/DealsFavor.lua"))("Blackthornes_TS", ns)
ns.DEALS_FLIPS = true  -- the flips, put away for now, are still tested
assert(loadfile(lfs_cwd .. "/UI/Tab_Deals.lua"))("Blackthornes_TS", ns)

local tab = tabs.deals
tab.build(Stub())

local show = dropdowns[2]
check("the Deals tab has a Show menu", show and #show.options == 3 and show.options[2].value == "favor")
check("the flips stay the first view", #lists == 1)
check("the tick box starts ticked, as Settings has nothing yet", checkboxes["Skip bundles over a stack"].initial == true)

show.onSelect("favor")
local list = lists[#lists]
check("Merchant's Favor builds its own list", #lists == 2 and list.data and #list.data == #ns.WAYLAID_CRATES)
check("cheapest favor first", list.data[1].key == "apprentice-herbs")

local row = Stub()
list.opts.createRow(row)
list.opts.updateRow(row, list.data[1])
-- Right to left: PER FAVOR, TOTAL, BUNDLE, CRATE, FAVOR.
check("PER FAVOR shows a price", row.cells[1].text ~= "" and row.cells[1].color == "accent")
check("FAVOR shows what it pays", row.cells[5].text == "5")
check("the name says how many are carried", row.name.text == "Apprentice Herbs  (1)")

local unknown = Row(list.data, "artisan-ore")
list.opts.updateRow(row, unknown)
check("an Artisan crate's favor is a question mark", row.cells[5].text == "?" and row.cells[5].color == "warn"
    and row.cells[1].text == "")

local function Showing(pattern)
    for _, label in ipairs(labels) do
        if label.text:find(pattern) then return label.text end
    end
end

list.opts.onClick(Row(list.data, "apprentice-textiles"), 1, "LeftButton")
check("the detail says the reward is reported", Showing("^Players report 5 favor") ~= nil)
check("and lists the bundles, the over-stack one marked", Showing("^40 Linen Cloth %*$") ~= nil
    and Showing("^20 Light Leather$") ~= nil)
check("and says why it is left out", Showing("Needs more than one stack") ~= nil)

list.opts.onClick(Row(list.data, "apprentice-herbs"), 1, "LeftButton")
check("a learned reward says how often it was seen", Showing("seen on 2 turn%-ins") ~= nil)

buttons["Search bundle"].onClick()
check("the bundle button searches for its material", sent[#sent] == SILVERLEAF)
list.opts.onClick(Row(list.data, "apprentice-herbs"), 1, "RightButton")
check("right-click searches for the crate", sent[#sent] == HERBS)

list.opts.onClick(Row(list.data, "artisan-ore"), 1, "LeftButton")
printed = {}
buttons["Search crate"].onClick()
check("a crate never seen says to type its name", #printed == 1 and printed[1]:find("type its name") ~= nil)

checkboxes["Skip bundles over a stack"].onToggle(false)
check("unticking is kept in Settings", config.favorSkipOverStack == false)
check("and counts the linen", Row(list.data, "apprentice-textiles").best.itemID == LINEN)

searched("textiles")
check("search narrows the crates", #list.data == 4)
searched("")

show.onSelect("flips")
check("back to the flips, the favor list is left alone", #lists == 2)

print("\nwith the flips put away (the owner, 2026-10-13)")
ns.DEALS_FLIPS = nil
for key in pairs(dropdowns) do dropdowns[key] = nil end
for key in pairs(lists) do lists[key] = nil end
assert(loadfile(lfs_cwd .. "/UI/Tab_Deals.lua"))("Blackthornes_TS", ns)
tab = tabs.deals
check("the tab is Favors and Writs", tab.text == "Favors and Writs")
tab.build(Stub())
show = dropdowns[2]
check("the Show menu has no Flips", #show.options == 2 and show.options[1].value == "favor"
    and show.options[2].value == "writs")
check("it opens on Merchant's Favor", #lists == 2
    and lists[2].data and #lists[2].data == #ns.WAYLAID_CRATES)
check("the flips' menus stay hidden", dropdowns[1].shown == false)
ns.UI.DealsSetView("flips")
check("asking for the flips still shows the favor", dropdowns[1].shown == false and #lists == 2)

for _, key in ipairs({ "C_Item", "GetTime", "CreateFrame", "GameTooltip", "C_Timer", "C_CurrencyInfo", "GetMoney" }) do
    _G[key] = saved[key]
end

print(("\n%d checks passed"):format(checks))
