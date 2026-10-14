-- The drawer's Lists view (UI/ShoppingListsView.lua), driven as a player would.
--
-- What must hold:
--   1. The craft queue's list is first, then the player's, and only the open
--      one shows its tools and items.
--   2. The foot box makes a list, adds to it, renames it, shows its copy line
--      and takes a pasted one; Enter does each.
--   3. Delete takes a second click, and nothing else deletes.
--   4. A list's Search steps through its items when the game can only look
--      for one at a time.

local function noop() end

local ns = {}
ns.NewModule = function(name) local m = {}; ns[name] = m; return m end
ns.RegisterCommand, ns.RegisterEvent = noop, noop
ns.Debug, ns.Warn = noop, noop
local printed = {}
ns.Print = function(text) printed[#printed + 1] = text end
ns.L = setmetatable({ Format = string.format }, { __index = function(_, key) return key end })
ns.COLORS = { accent = "ffc8a44d", muted = "ff7a8089", profit = "ff4fd18b" }

local clock = 100
GetTime = function() return clock end

local function Stub(fields)
    local frame = fields or {}
    frame.shown = frame.shown ~= false
    frame.Show = function(self) self.shown = true end
    frame.Hide = function(self) self.shown = false end
    frame.SetShown = function(self, on) self.shown = on and true or false end
    frame.IsShown = function(self) return self.shown end
    frame.SetText = function(self, text) self.text = text end
    frame.GetText = function(self) return self.text end
    frame.SetFocus = function(self) self.focused = true end
    frame.ClearFocus = function(self) self.focused = false end
    frame.HasFocus = function(self) return self.focused == true end
    frame.scripts = {}
    frame.SetScript = function(self, name, fn) self.scripts[name] = fn end
    return setmetatable(frame, { __index = function(self, key)
        rawset(self, key, noop)
        return noop
    end })
end

CreateFrame = function() return Stub() end

local functions = {}
ns.Util = {
    HasFunction = function(path) return functions[path] == true end,
    GetItemLabel = function(id) return "[item " .. id .. "]" end,
    FormatMoney = function(c) return tostring(c) end,
}
ns.Theme = {
    FONT = "font", sizes = { small = 11, tiny = 10 },
    CreateLabel = function() return Stub() end,
    CreatePanel = function() return Stub() end,
    CreateItemIcon = function() return Stub() end,
    SetItemIcon = noop,
    Unpack = function() return 1, 1, 1, 1 end,
}
local buttons = {}
ns.Widgets = {
    CreateButton = function(_, text, onClick)
        local button = Stub({ text = text, click = onClick })
        buttons[text] = button
        return button
    end,
    CreateNumberBox = function()
        local box = Stub({ editBox = Stub() })
        box.SetValue = function(self, v) self.value = v end
        return box
    end,
    CreateScrollList = function(_, opts)
        local list = Stub({ opts = opts, rows = {} })
        list.SetData = function(self, data) self.data = data end
        return list
    end,
    ShowItemTooltip = noop,
}

local PEACE, SILVER = 2447, 765
ns.Inventory = { GetOwnedCount = function() return 0 end }
ns.Prices = { GetValue = function() return 30 end }
ns.Vendor = { GetUnitPrice = noop, IsLimited = noop, KeepsInStock = function() return false end }
ns.Queue = { GetShoppingList = function() return {} end }
ns.db = {}

local searched = {}
ns.UI = { SearchAuctionHouse = function(_, id) searched[#searched + 1] = id; return true end }
ns.Scanner = { isAuctionHouseOpen = true }

assert(loadfile(lfs_cwd .. "/Logic/ShoppingLists.lua"))("Blackthornes_TS", ns)
assert(loadfile(lfs_cwd .. "/UI/ShoppingListsView.lua"))("Blackthornes_TS", ns)
local Lists, View = ns.ShoppingLists, ns.ShoppingListsView

local checks = 0
local function check(label, condition)
    checks = checks + 1
    if not condition then error(("FAILED: %s"):format(label), 2) end
    print(("  ok  %s"):format(label))
end

print("\nshopping lists view")

View:Build(Stub(), Stub(), Stub(), {})
View:SetShown(true)
View:Refresh(true)
local data = View.list.data
check("the craft queue's list comes first", #data == 1 and data[1].kind == "list" and data[1].auto)
check("the foot says what to do", View.note.shown and not View.box.shown)

local function Type(text)
    View.box.edit:SetText(text)
    View.box.edit.scripts.OnEnterPressed(View.box.edit)
end

-- 2. New list, add, rename, copy, paste
buttons["New list"].click()
check("New list opens the box to name it", View.mode == "new" and View.box.shown and View.box.edit.focused)
Type("Potion herbs")
check("Enter makes the list and opens it to add", Lists:Get(1).name == "Potion herbs" and View.open == 1 and View.mode == "add")
Type("2447 40")
check("adding by item ID and how many", Lists:Get(1).items[1].id == PEACE and Lists:Get(1).items[1].want == 40)
check("the box is cleared for the next", View.box.edit.text == "")
Type("765")
data = View.list.data
check("the open list shows its tools and items", #data == 5 and data[3].kind == "tools" and data[4].itemID == PEACE
    and data[5].itemID == SILVER)
check("an unknown item is said, not added", (function() Type("Nothing here"); return #Lists:Get(1).items == 2 and #printed > 0 end)())

View:SetMode("rename", 1)
check("rename starts with the name", View.box.edit.text == "Potion herbs")
Type("Herbs")
check("Enter renames it", Lists:Get(1).name == "Herbs" and View.mode == "add")

View:SetMode("copy", 1)
local line = View.box.edit.text
check("copy shows the line to copy", line == "BTSlist1:Herbs:2447*40,765*1" and not View.save.shown)
View:SetMode("paste")
Type(line)
check("paste makes a new list and opens it", Lists:Get(2) and Lists:Get(2).name == "Herbs 2" and View.open == 2)

-- 3. Delete takes a second click
View:Refresh(true)
local row = Stub({ tools = {} })
View.list.opts.createRow(row)
row.data = { kind = "tools", key = 2 }
row.delete.click()
check("one click arms Delete", Lists:Get(2) ~= nil)
View.list.opts.updateRow(row, row.data)
check("it asks if you are sure", row.delete.text == "Sure?")
clock = clock + 10
row.delete.click()
check("a click after the wait only arms it again", Lists:Get(2) ~= nil)
row.delete.click()
check("the second click deletes", Lists:Get(2) == nil and #Lists:Readable() == 1 and View.open == nil)

-- 4. Search one at a time
View.open = nil
View:Refresh(true)
local entry = View.list.data[2]
check("the list row offers its two items", entry.kind == "list" and #entry.searchable == 2)
View:SearchList(entry)
check("first search, then Next", searched[1] == PEACE and View:SearchLabel(entry) == "Next 2/2")
View:SearchList(entry)
check("Next looks for the second and ends", searched[2] == SILVER and View:SearchLabel(entry) == "Search")

-- Opening a list by its row
View.list.opts.onClick(View.list.data[2])
check("a click opens it", View.open == 1 and View.mode == "add")
View.list.opts.onClick(View.list.data[2])
check("a second click closes it", View.open == nil and View.mode == nil)

print(("\n%d check(s) passed\n"):format(checks))
