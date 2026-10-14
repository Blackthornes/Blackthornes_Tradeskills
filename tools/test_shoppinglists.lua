-- Named shopping lists (Logic/ShoppingLists.lua, UI/ShoppingListsView.lua).
--
-- What must hold:
--   1. Lists are made, renamed and deleted only when asked, names kept clean
--      and never two alike.
--   2. Items are added (a second add raises how many), changed within limits
--      and taken off.
--   3. Each item says how many are owned and needed and what it costs; a
--      vendor that never runs out is never searched on the auction house.
--   4. The craft queue's list reads as the same rows and can be saved.
--   5. A copied line gives the same list back, and anything else is refused.
--   6. Typed text finds an item with how many: a link, an ID, "Name 40".
--   7. A list's Search asks for every item at once where the game allows.
--   8. A Shift-click goes on the open list only while its box is typing.

local function noop() end

local ns = {}
ns.NewModule = function(name) local m = {}; ns[name] = m; return m end
ns.RegisterCommand, ns.RegisterEvent = noop, noop
ns.Debug, ns.Warn = noop, noop
local printed = {}
ns.Print = function(text) printed[#printed + 1] = text end
ns.L = setmetatable({ Format = string.format }, { __index = function(_, key) return key end })

local functions = {}
ns.Util = {
    HasFunction = function(path) return functions[path] == true end,
    GetItemLabel = function(id) return "[item " .. id .. "]" end,
    FormatMoney = function(c) return tostring(c) end,
}

local PEACE, SILVER, VIAL, DYE = 2447, 765, 3371, 4340
local owned = { [PEACE] = 12, [VIAL] = 50 }
ns.Inventory = { GetOwnedCount = function(_, id) return owned[id] or 0 end }
local auction = { [PEACE] = 31, [SILVER] = 28, [DYE] = 900 }
ns.Prices = { GetValue = function(_, id) return auction[id] end }
local vendor = { [VIAL] = 4, [DYE] = 50 }
local limited = {}
ns.Vendor = {
    GetUnitPrice = function(_, id) return vendor[id] end,
    IsLimited = function(_, id) return limited[id] == true end,
    KeepsInStock = function(_, id) return vendor[id] ~= nil and not limited[id] end,
}
ns.db = {}

assert(loadfile(lfs_cwd .. "/Logic/ShoppingLists.lua"))("Blackthornes_TS", ns)
local Lists = ns.ShoppingLists

local checks = 0
local function check(label, condition)
    checks = checks + 1
    if not condition then error(("FAILED: %s"):format(label), 2) end
    print(("  ok  %s"):format(label))
end

print("\nshopping lists")

-- 1. Making, naming, deleting
local herbs = Lists:Make("  Potion   herbs ")
check("a list is made", herbs == 1 and Lists:Get(1).name == "Potion herbs")
check("saved account wide as shoppingLists", ns.db.shoppingLists[1] == Lists:Get(1))
check("no empty name", Lists:Make("   ") == nil)
local dupe = Lists:Make("potion herbs")
check("a name in use gets a number", Lists:Get(dupe).name == "potion herbs 2")
check("the copy line's marks are taken out", Lists:Rename(dupe, "Ore: bars, all|r") and Lists:Get(dupe).name == "Ore bars all r")
check("a long name is cut", #Lists.CleanName(("x"):rep(80)) == Lists.MAX_NAME)
local version = Lists.version
check("delete removes it", Lists:Delete(dupe) and Lists:Get(dupe) == nil and #ns.db.shoppingLists == 1)
check("a change moves the version", Lists.version > version)
check("deleting what is not there does nothing", Lists:Delete(9) == false)
ns.db.shoppingLists[3] = "broken"
check("a broken entry is skipped, not deleted", #Lists:Readable() == 1 and ns.db.shoppingLists[3] == "broken")
ns.db.shoppingLists[3] = nil

-- 2. Items
check("an item goes on", Lists:Add(herbs, PEACE, 40))
check("a second add raises how many", Lists:Add(herbs, PEACE, 5) and Lists:Get(herbs).items[1].want == 45)
Lists:Add(herbs, SILVER, 40)
Lists:Add(herbs, VIAL, 40)
check("not an item", Lists:Add(herbs, 0) == nil)
check("how many is kept in bounds", Lists:SetWant(herbs, PEACE, -3) and Lists:Get(herbs).items[1].want == 1)
Lists:SetWant(herbs, PEACE, 40)
check("an item comes off", Lists:Add(herbs, DYE, 2) and Lists:Remove(herbs, DYE) and #Lists:Get(herbs).items == 3)

-- 3. Rows
local lines = Lists:Lines(herbs)
check("owned and needed", lines[1].have == 12 and lines[1].need == 28)
check("cost of what is needed", lines[1].unit == 31 and lines[1].cost == 31 * 28)
check("an auction item can be searched", Lists.CanSearch(lines[1]))
check("a vendor item that never runs out is not searched", lines[3].fromVendor and lines[3].need == 0
    and not Lists.CanSearch(lines[3]))
owned[VIAL] = 0
lines = Lists:Lines(herbs)
check("still not searched when short", lines[3].need == 40 and not Lists.CanSearch(lines[3]))
limited[VIAL] = true
lines = Lists:Lines(herbs)
check("a vendor with limited stock is searched", Lists.CanSearch(lines[3]))
limited[VIAL] = nil
local total, unpriced = Lists.Total(Lists:Lines(herbs))
check("the total adds what is still to buy", total == 31 * 28 + 28 * 40 + 4 * 40 and unpriced == 0)
local ids = Lists.Searchable(Lists:Lines(herbs))
check("the searchable items", #ids == 2 and ids[1] == PEACE and ids[2] == SILVER)
Lists:Add(herbs, DYE, 1)
check("a vendor item dearer at a vendor that keeps it still goes to the vendor",
    Lists:Lines(herbs)[4].fromVendor == true)
Lists:Remove(herbs, DYE)

-- 4. The craft queue
ns.Queue = { GetShoppingList = function() return {
    { itemID = SILVER, needed = 10, have = 2, shortfall = 8, unitCost = 30, estimatedCost = 240 },
    { itemID = PEACE, needed = 5, have = 9, shortfall = 0 },
} end }
local queue = Lists:QueueLines()
check("the queue's list is what it still needs", #queue == 1 and queue[1].need == 8 and queue[1].cost == 240)
local saved = Lists:SaveQueue()
check("saved as a list of your own", saved and Lists:Get(saved).items[1].id == SILVER
    and Lists:Get(saved).items[1].want == 10)
Lists:Delete(saved)

-- 5. Copy and paste
local line = Lists:Export(herbs)
check("the copy line", line == "BTSlist1:Potion herbs:2447*40,765*40,3371*40")
local pasted = Lists:Import(line)
check("pasting gives the same list back", pasted and Lists:Get(pasted).name == "Potion herbs 2"
    and #Lists:Get(pasted).items == 3 and Lists:Get(pasted).items[2].want == 40)
for _, bad in ipairs({ "hello", "BTSlist1:x:", "BTSlist1:x:abc", "BTSlist1:x:1*2;os.exit()", 7 }) do
    check("refused: " .. tostring(bad), Lists:Import(bad) == nil)
end
Lists:Delete(pasted)

-- 6. Typed text
assert(loadfile(lfs_cwd .. "/UI/ShoppingListsView.lua"))("Blackthornes_TS", ns)
local View = ns.ShoppingListsView
functions["C_Item.GetItemInfoInstant"] = true
C_Item = { GetItemInfoInstant = function(name) if name == "Peacebloom" then return PEACE end end }
local id, count = View.ParseAdd("|cffffffff|Hitem:765::::::::|h[Silverleaf]|h|r")
check("a link", id == SILVER and count == 1)
id, count = View.ParseAdd("2447")
check("an item ID", id == PEACE and count == 1)
id, count = View.ParseAdd("Peacebloom 40")
check("a name and how many", id == PEACE and count == 40)
id, count = View.ParseAdd("20x Peacebloom")
check("how many first", id == PEACE and count == 20)
check("an unknown name", View.ParseAdd("Nothing at all") == nil)

-- 7. Searching a list
local sent
ns.AHQueue = { PRIORITY = { urgent = 1 }, Request = function(_, request) sent = request; return true end }
ns.Scanner = { isAuctionHouseOpen = false }
check("needs the auction house", Lists:SearchMany({ PEACE, SILVER }) == false)
ns.Scanner.isAuctionHouseOpen = true
local ok, why = Lists:SearchMany({ PEACE, SILVER })
check("without the game's call, one at a time", ok == false and why == "single")
local keys
functions["C_AuctionHouse.SearchForItemKeys"], functions["C_AuctionHouse.MakeItemKey"] = true, true
C_AuctionHouse = {
    MakeItemKey = function(itemID) return { itemID = itemID } end,
    SearchForItemKeys = function(k) keys = k end,
}
check("every item at once", Lists:SearchMany({ PEACE, SILVER }) == true and sent and sent.send() and #keys == 2)
ns.Scanner.isScanning = true
check("never over a scan", Lists:SearchMany({ PEACE, SILVER }) == false)

-- 8. Shift-click
local focus = false
View.mode, View.modeKey = "add", herbs
View.box = { IsShown = function() return true end, edit = { HasFocus = function() return focus end } }
View.list, View.shown = nil, false
check("not taken without the keyboard", View:TakeItem(DYE) == false)
focus = true
check("taken while the box types", View:TakeItem(DYE) == true and Lists:Lines(herbs)[4].itemID == DYE)
View.mode = "rename"
check("not taken while renaming", View:TakeItem(DYE) == false)

C_Item, C_AuctionHouse = nil, nil
print(("\n%d check(s) passed\n"):format(checks))
