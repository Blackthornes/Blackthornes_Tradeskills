-- An item's tooltip lines are kept while the mouse rests on it.
--
-- The game draws a bag item's tooltip again about five times a second while
-- the mouse is on it, and every draw asked every module for its lines
-- afresh. ItemTooltip:LinesFor now keeps them for a second, for the same
-- item, stack, copy and Shift key, while no price, setting or bag changed.
-- This counts the work, and checks each thing that must build them again.

local ns = {}
ns.NewModule = function(name) local m = {}; ns[name] = m; return m end
ns.COLORS = { accent = "ffc8a44d", muted = "ff7a8089", text = "ffe6e8ec" }
ns.Print, ns.PrintRaw, ns.RegisterCommand = function() end, function() end, function() end

ns.Util = {
    FormatMoney = function(copper) return ("<%d>"):format(copper) end,
    FormatAgeAgo = function(seconds) return ("%dh ago"):format(seconds / 3600) end,
    GetItemLabel = function(itemID) return ("item %d"):format(itemID) end,
    HasFunction = function(path) return path == "C_Item.GetItemInfo" end,
}

local saved = { C_Item = C_Item, GetTime = GetTime, IsShiftKeyDown = IsShiftKeyDown }

local clock = 100
GetTime = function() return clock end
local shiftDown = false
IsShiftKeyDown = function() return shiftDown end

local price = 2300
ns.Prices = {
    changes = 0,
    GetValue = function() return price end,
    IsStale = function() return false end,
    GetAge = function() return 0 end,
}
ns.Config = { changes = 0, Get = function() return nil end }
ns.Inventory = { changes = 0 }

C_Item = {
    GetItemInfo = function(itemID)
        return ("item %d"):format(itemID), nil, 1, nil, nil, nil, nil, nil, nil, nil, nil, 7, nil, 0
    end,
}

-- One module's lines stand for them all: each build asks it once.
local asked = 0
ns.UsedIn = {
    For = function()
        asked = asked + 1
        return { mine = true, counts = "Tailoring 3", professions = { { "Tailoring", "Bolt" } } }
    end,
    Wrap = function(text) return { text } end,
}

local ItemTooltip
do
    local realNew = ns.NewModule
    ns.NewModule = function(name) local m = realNew(name); ItemTooltip = m; return m end
    assert(loadfile(lfs_cwd .. "/UI/ItemTooltip.lua"))("Blackthornes_TS", ns)
    ns.NewModule = realNew
end
ItemTooltip.fired, ItemTooltip.counts, ItemTooltip.seen = {}, {}, 0

local checks = 0
local function check(label, condition)
    checks = checks + 1
    if not condition then error(("FAILED: %s"):format(label), 2) end
    print(("  ok  %s"):format(label))
end

local function Text(lines)
    local parts = {}
    for i = 1, #lines do parts[i] = tostring(lines[i][1]) .. "=" .. tostring(lines[i][2]) end
    return table.concat(parts, ";")
end

print("\nthe mouse rests on one item")

local first = ItemTooltip:LinesFor(2589, 20)
check("the first draw builds the lines", asked == 1)
check("and they hold the price", Text(first):find("<2300>", 1, true) ~= nil)

for _ = 1, 4 do
    clock = clock + 0.2
    ItemTooltip:LinesFor(2589, 20)
end
check("four more draws in the same second build nothing", asked == 1)
check("the same lines come back", Text(ItemTooltip:LinesFor(2589, 20)) == Text(first))

clock = clock + 1
ItemTooltip:LinesFor(2589, 20)
check("after a second they are built again", asked == 2)

print("\nwhat builds them again at once")

ItemTooltip:LinesFor(4306, 20)
check("another item", asked == 3)

ItemTooltip:LinesFor(4306, 5)
check("another stack size", asked == 4)

ItemTooltip:LinesFor(4306, 5, "item:4306::::::::18:1485:::1:12722")
check("a copy with a link of its own", asked == 5)
ItemTooltip:LinesFor(4306, 5, "item:4306::::::::18:1485:::1:12722")
check("the same copy again builds nothing", asked == 5)

price = 9900
ns.Prices.changes = ns.Prices.changes + 1
local repriced = ItemTooltip:LinesFor(4306, 5, "item:4306::::::::18:1485:::1:12722")
check("a price that moved", asked == 6)
check("and the new price shows", Text(repriced):find("<9900>", 1, true) ~= nil)

ns.Config.changes = ns.Config.changes + 1
ItemTooltip:LinesFor(4306, 5, "item:4306::::::::18:1485:::1:12722")
check("a setting that changed", asked == 7)

ns.Inventory.changes = ns.Inventory.changes + 1
ItemTooltip:LinesFor(4306, 5, "item:4306::::::::18:1485:::1:12722")
check("the bags changing", asked == 8)

shiftDown = true
ItemTooltip:LinesFor(4306, 5, "item:4306::::::::18:1485:::1:12722")
check("Shift going down", asked == 9)
shiftDown = false
ItemTooltip:LinesFor(4306, 5, "item:4306::::::::18:1485:::1:12722")
check("Shift coming up", asked == 10)

ItemTooltip:ForgetLines()
ItemTooltip:LinesFor(4306, 5, "item:4306::::::::18:1485:::1:12722")
check("being told to forget", asked == 11)

print("\nwhat a build leaves for Shift's redraw")

ItemTooltip:ForgetLines()
ItemTooltip.usedInHeld = nil
ItemTooltip.BuildLinesFor = function(self)
    asked = asked + 1
    self.usedInHeld = true
    return { { "a", "b" }, held = true }
end
ItemTooltip:LinesFor(2589, 1)
ItemTooltip.usedInHeld = nil
local again = ItemTooltip:LinesFor(2589, 1)
check("kept lines put the held mark back", ItemTooltip.usedInHeld == true)
check("and still say a line was held", again.held == true)

print("\nno clock, nothing kept")

ItemTooltip:ForgetLines()
GetTime = nil
local before = asked
ItemTooltip:LinesFor(2589, 1)
ItemTooltip:LinesFor(2589, 1)
check("every draw builds", asked == before + 2)

C_Item, GetTime, IsShiftKeyDown = saved.C_Item, saved.GetTime, saved.IsShiftKeyDown

print(("\n%d checks passed"):format(checks))
