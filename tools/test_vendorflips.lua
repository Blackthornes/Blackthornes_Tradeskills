-- The Vendor Flips tab: items on the auction house listed for less than a
-- vendor pays for them (Trent, 2026-09-28).
--
-- What this pins down:
--   * profit is the vendor price less the cheapest listing from someone
--     else, per item, with no auction house cut;
--   * a lone low listing that pricing ignores is still the price to buy at;
--   * his own listings, items worth more than a vendor pays, items a vendor
--     will not buy, and listings the last scan did not see are left out;
--   * the vendor price comes from the saved item facts: an item the client
--     has let go of stays listed and is not read again, and items saved
--     before sell prices were kept are read once more;
--   * nothing new is read while the auction house is open;
--   * the Minimum profit and margin from Settings hold rows back;
--   * the tab draws the rows, rebuilds only when prices change, and the scan
--     message names the best flip with a sound.

local ns = {}
ns.COLORS = setmetatable({}, { __index = function() return "ffffffff" end })
ns.NewModule = function(name) local m = {}; ns[name] = m; return m end
local commands = {}
ns.RegisterCommand = function(name, _, fn) commands[name] = fn end
local handlers = {}
ns.RegisterEvent = function(_, event, fn) handlers[event] = handlers[event] or {}; table.insert(handlers[event], fn) end

local printed = {}
ns.Print = function(text) printed[#printed + 1] = text end
ns.PrintRaw, ns.Debug, ns.Warn = function() end, function() end, function() end

-- Put back at the end: every suite shares one Lua runtime.
local saved = { C_Item = C_Item, GetTime = GetTime, CreateFrame = CreateFrame,
                PlaySound = PlaySound, SOUNDKIT = SOUNDKIT, GameTooltip = GameTooltip,
                C_Timer = C_Timer }

CreateFrame = function()
    local frame = {}
    for _, name in ipairs({ "SetScript", "Show", "Hide", "SetPoint", "SetSize" }) do
        frame[name] = function() end
    end
    return frame
end

GetTime = function() return 1 end
time = time or os.time

-- itemID -> quality, vendor sell price
local items = {
    [3001] = { 1, 500 },    -- listed at 200: a 300 flip
    [3002] = { 1, 500 },    -- only his own listing
    [3003] = { 2, 1000 },   -- a lone low listing at 100
    [3004] = { 1, 50 },     -- listed above what a vendor pays
    [3005] = { 1, 0 },      -- a vendor will not buy it
    [3006] = { 0, 30 },     -- a grey at 29: one copper
}

local reads, loads, evicted = {}, {}, {}

C_Item = {
    GetItemInfo = function(itemID)
        reads[itemID] = (reads[itemID] or 0) + 1
        local item = items[itemID]
        if not item or evicted[itemID] then return nil end
        return "item" .. itemID, nil, item[1], 10, 1, "Trade Goods", "Cloth", 20,
            "", 1, item[2], 7, 1, 2
    end,
    GetItemInfoInstant = function(itemID)
        return itemID, "Trade Goods", "Cloth", "", 1, 7, 1
    end,
    RequestLoadItemDataByID = function(itemID) loads[itemID] = (loads[itemID] or 0) + 1 end,
}

assert(loadfile(lfs_cwd .. "/Core/Util.lua"))("Blackthornes_TS", ns)

local records = {
    [3001] = { rivalMin = 200, quantity = 12 },
    [3002] = { ownMin = 100, quantity = 1 },
    [3003] = { rivalMin = 900, ignoredLow = 100, quantity = 2 },
    [3004] = { rivalMin = 80, quantity = 5 },
    [3005] = { rivalMin = 1, quantity = 5 },
    [3006] = { rivalMin = 29, quantity = 1 },
}

local config = { auctionCut = 0.05, minProfit = 0, minMarginPercent = 0 }

ns.Config = {
    Get = function(_, key) return config[key] end,
    GetCharacterKey = function() return "Tester-Realm" end,
}
ns.Prices = {
    GetTable = function() return records end,
    GetValue = function() return nil end,
    GetAge = function() return 600 end,
    IsStale = function(_, itemID) return itemID == 3003 end,
    Count = function() return 6 end,
}
ns.Recipes = {
    GetCharacterName = function(_, key) return (key:match("^([^-]+)")) end,
}

ns.db = { characters = {} }

assert(loadfile(lfs_cwd .. "/Logic/Disenchant.lua"))("Blackthornes_TS", ns)
assert(loadfile(lfs_cwd .. "/Logic/VendorFlips.lua"))("Blackthornes_TS", ns)

local VendorFlips = ns.VendorFlips

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

print("\nwhich auctions are listed")

local rows = VendorFlips:GetAuctionRows()

local first = Find(rows, 3001)
check("an item under vendor price is listed", first ~= nil)
check("bought at the cheapest rival listing", first.buy == 200)
check("a vendor pays 500", first.vendor == 500)
check("profit is 500 - 200 = 300, no auction cut", first.gain == 300)
check("margin is profit over the buy price", math.abs(first.margin - 1.5) < 1e-9)
check("it says how many are listed", first.listed == 12)

check("his own listing is not a flip", Find(rows, 3002) == nil)

local lone = Find(rows, 3003)
check("a lone low listing is the one to buy", lone and lone.buy == 100 and lone.loneLow and lone.gain == 900)
check("and an old scan is marked stale", lone.stale == true)

check("an item over vendor price is left out", Find(rows, 3004) == nil)
check("an item a vendor will not buy is left out", Find(rows, 3005) == nil)
check("a grey one copper under vendor counts", Find(rows, 3006) and Find(rows, 3006).gain == 1)

check("best profit first", rows[1].itemID == 3003 and rows[2].itemID == 3001)

print("\nonly deals, and the minimums from Settings")

local deals, hidden = VendorFlips:GetAuctionRows({ profitableOnly = true })
check("nothing held back with no minimums", #deals == 3 and hidden == 0)

config.minProfit = 50
deals, hidden = VendorFlips:GetAuctionRows({ profitableOnly = true })
check("Minimum profit holds the one copper grey back", Find(deals, 3006) == nil)
check("the others clear it", Find(deals, 3001) ~= nil and Find(deals, 3003) ~= nil)
check("and it says how many were held back", hidden == 1)
config.minProfit = 0

config.minMarginPercent = 200
deals = VendorFlips:GetAuctionRows({ profitableOnly = true })
check("Minimum margin holds the 150% flip back", Find(deals, 3001) == nil)
check("the 900% one clears it", Find(deals, 3003) ~= nil)
config.minMarginPercent = 0

print("\nonly what the last scan saw")

ns.db.lastFullScan = 1000
records[3001].seen = 999
check("a listing the last scan did not see is not a flip", Find(VendorFlips:GetAuctionRows(), 3001) == nil)
records[3001].seen = 1200
check("one a later search saw is", Find(VendorFlips:GetAuctionRows(), 3001) ~= nil)
records[3001].seen, ns.db.lastFullScan = nil, nil

print("\nvendor prices come from the saved item facts")

check("the sell price is kept in the saved data", ns.db.itemFacts[3001] and ns.db.itemFacts[3001].v == 500)
check("a vendor that buys nothing is kept as 0", ns.db.itemFacts[3005].v == 0)

evicted[3001] = true
reads = {}
for _ = 1, 3 do VendorFlips:GetAuctionRows() end
check("the item stays listed after the client lets it go", Find(VendorFlips:GetAuctionRows(), 3001) ~= nil)
check("and is not read from the client again", reads[3001] == nil)
evicted[3001] = nil

-- Items the Disenchanting tab remembered before sell prices were kept.
ns.db.itemFacts[3001] = { n = "item3001", q = 1, l = 10, c = 7, e = "" }
C_Item.IsItemDataCachedByID = function() return true end
check("an item saved without a sell price is read again", Find(VendorFlips:GetAuctionRows(), 3001) ~= nil)
check("and now has it", ns.db.itemFacts[3001].v == 500)
C_Item.IsItemDataCachedByID = nil

check("the disenchant facts still read the same", ns.Disenchant:GetItemFacts(3001).quality == 1)

print("\nnothing new is read while the auction house is open")

ns.Disenchant:_ForgetItems()
VendorFlips:GetAuctionRows()          -- the known items, read while it is shut
local knownCount = #VendorFlips:GetAuctionRows()

ns.Scanner = { isAuctionHouseOpen = true }
items[3007] = { 1, 900 }
records[3007] = { rivalMin = 10, quantity = 1 }
loads, reads = {}, {}
local openRows, _, pending = VendorFlips:GetAuctionRows()
check("items already known still list at the auction house", #openRows == knownCount)
check("a new item is not read or fetched while it is open", reads[3007] == nil and loads[3007] == nil)
check("and is counted as waiting", pending == 1)

ns.Scanner.isAuctionHouseOpen = false
check("it is listed once the auction house closes", Find(VendorFlips:GetAuctionRows(), 3007) ~= nil)
records[3007], items[3007] = nil, nil
ns.Scanner = nil

print("\n/bts vendordeals")

printed = {}
commands.vendordeals()
local said = table.concat(printed, "\n")
check("it says when the last scan was", said:find("last full scan", 1, true) ~= nil)
check("and what a fresh build would show", said:find("built fresh now", 1, true) ~= nil)
check("and what a vendor pays for each", said:find("vendor pays", 1, true) ~= nil)

print("\nthe scan message")

local chimed
SOUNDKIT = { LOOT_WINDOW_COIN_SOUND = 7, UI_EPICLOOT_TOAST = 1 }
PlaySound = function(kit) chimed = kit end

printed = {}
local count = VendorFlips:AnnounceDeals()
check("it counts the flips", count == 3)
check("it names the best one", printed[1] and printed[1]:find("Vendor flips", 1, true)
    and printed[1]:find("item3003", 1, true))
check("with the sound of coins", chimed == 7)

-- Settings: Sound when a scan finishes, turned off. The message still shows.
config.scanSounds = false
printed, chimed = {}, nil
VendorFlips:AnnounceDeals()
check("with scan sounds off, the message and no sound", #printed == 1 and chimed == nil)
config.scanSounds = nil

local backup = records
records = { [3004] = { rivalMin = 80 } }
printed, chimed = {}, nil
check("no flips, no message", VendorFlips:AnnounceDeals() == 0 and #printed == 0 and chimed == nil)
records = backup

--------------------------------------------------------------------------------
-- The tab
--------------------------------------------------------------------------------

print("\nthe Vendor Flips tab")

local function Stub(fields)
    local frame = fields or {}
    frame.IsVisible = frame.IsVisible or function() return true end
    return setmetatable(frame, { __index = function(self, key)
        local noop = function() end
        rawset(self, key, noop)
        return noop
    end })
end

local function Label()
    return Stub({
        text = "",
        SetText = function(self, value) self.text = tostring(value) end,
        GetText = function(self) return self.text end,
        SetTextColor = function(self, a) self.color = a end,
        SetShown = function(self, value) self.shown = value end,
    })
end

CreateFrame = function() return Stub() end
C_Timer = { After = function() end }
GameTooltip = Stub()

local bars = {}
ns.Theme = {
    CreateLabel = function() return Label() end,
    CreatePanel = function() return Stub() end,
    CreateDivider = function() return Stub() end,
    Unpack = function(key) return key end,
    ProfitColor = function(value) return (value or 0) >= 0 and "profit" or "loss" end,
    AccentStripe = function() return Stub() end,
    CreateItemIcon = function() return Stub() end,
    SetItemIcon = function() end,
    CreateHeading = function() return Stub() end,
    CreateBar = function()
        local bar = Stub({ track = Stub(), Set = function(self, value) self.value = value end })
        bars[#bars + 1] = bar
        return bar
    end,
}

local checkboxes, lists = {}, {}
ns.Widgets = {
    CreateSearchBox = function() return Stub() end,
    CreateCheckbox = function(_, text, onToggle) local box = Stub({ onToggle = onToggle }); checkboxes[text] = box; return box end,
    CreateButton = function() return Stub() end,
    ShowItemTooltip = function() return true end,
    CreateScrollList = function(_, opts)
        local list = Stub({ opts = opts, SetData = function(self, data) self.data = data end })
        lists[#lists + 1] = list
        return list
    end,
}

local sent = {}
ns.Scanner = { isAuctionHouseOpen = true, QueueBrowseQuery = function(_, text) sent[#sent + 1] = text end }

local tabs = {}
ns.UI = Stub({ RegisterTab = function(_, tab) tabs[tab.key] = tab end })

assert(loadfile(lfs_cwd .. "/UI/Tab_VendorFlips.lua"))("Blackthornes_TS", ns)

local tab = tabs.vendorflips
check("the tab registers as Vendor Flips", tab and tab.text == "Vendor Flips")
check("it sits after Disenchanting", tab.order > 1.8 and tab.order < 2)

tab.build(Stub())
tab.refresh()

local list = lists[#lists]
check("the flips are listed", list.data and #list.data == 3 and Find(list.data, 3001) ~= nil)

local row = Stub()
list.opts.createRow(row)
list.opts.updateRow(row, Find(list.data, 3001))

-- Right to left: PROFIT, MARGIN, VENDOR, BUY, LISTED, AGE.
check("PROFIT shows the gain in green", row.cells[1].text ~= "" and row.cells[1].color == "profit")
check("MARGIN shows 150%", row.cells[2].text == "150%")
check("VENDOR and BUY show prices", row.cells[3].text ~= "" and row.cells[4].text ~= "")
check("LISTED shows how many", row.cells[5].text == "12")

list.opts.onClick(Find(list.data, 3001), 1, "LeftButton")
check("picking a row fills the profit bar", bars[1] and math.abs(bars[1].value - 0.6) < 1e-9)

list.opts.onClick(Find(list.data, 3003), 1, "RightButton")
check("right-click searches the auction house for it", sent[#sent] == "item3003")

config.minProfit = 50
tab.refresh()
check("Settings minimums hold the grey back", Find(list.data, 3006) == nil)
checkboxes["Only deals over my minimums"].onToggle(false)
check("unticking shows it", Find(list.data, 3006) ~= nil)
checkboxes["Only deals over my minimums"].onToggle(true)
config.minProfit = 0

-- Redraws for bag changes and auction events reuse the list; walking every
-- scanned item each time pushed bag items out of the client's memory.
tab.refresh()
local builds = VendorFlips.rowBuilds
tab.refresh()
tab.refresh()
check("a redraw with nothing changed does not walk every item again", VendorFlips.rowBuilds == builds)
ns.Prices.changes = 1
tab.refresh()
check("new prices do", VendorFlips.rowBuilds == builds + 1)
ns.Prices.changes = nil

-- Items that waited while the auction house was open are read once it shuts.
local later = {}
C_Timer.After = function(_, fn) later[#later + 1] = fn end
builds = VendorFlips.rowBuilds
ns.Scanner.isAuctionHouseOpen = false
for _, fn in ipairs(handlers.AUCTION_HOUSE_CLOSED or {}) do fn(nil, "AUCTION_HOUSE_CLOSED") end
for _, fn in ipairs(later) do fn() end
check("closing the auction house rebuilds the list", VendorFlips.rowBuilds == builds + 1)
C_Timer.After = function() end

records = {}
ns.Prices.Count = function() return 0 end
ns.Prices.changes = 2
tab.refresh()
check("with no scan it says to scan", list.data and #list.data == 0)

for _, key in ipairs({ "C_Item", "GetTime", "CreateFrame", "PlaySound", "SOUNDKIT",
                      "GameTooltip", "C_Timer" }) do
    _G[key] = saved[key]
end

print(("\n%d checks passed"):format(checks))
