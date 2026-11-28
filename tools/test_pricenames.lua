-- The Prices tab puts an item's name in by itself once the game sends it
-- (a player's report, 2026-11-19): moving between tabs during a scan, rows
-- read "item 1234" until the player clicked one or changed tabs again.
--
-- What must hold:
--   1. A row drawn before its item loaded remembers it is waiting.
--   2. When the game sends that item, the rows on screen are drawn again,
--      and the row shows the name.
--   3. An item no row on screen waits for draws nothing (a scan loads
--      thousands), and a burst of names is drawn in one pass.
--   4. Nothing is drawn while the tab is hidden; it redraws when shown.

local SILK, IRON, OTHER = 4306, 2772, 9999

local loaded = {}           -- itemID -> name, what the game holds
local timers = {}
C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end }
local function RunTimers()
    local due = timers
    timers = {}
    for _, fn in ipairs(due) do fn() end
end
time = time or os.time

local ns = {
    Theme = {
        SetRowName = function(label, text) label:SetText(text) end,
        SetItemIcon = function() end,
        Unpack = function() return 1, 1, 1 end,
        SetMoneyText = function(label, value) label:SetText(tostring(value)) end,
    },
    Widgets = {},
    Util = {
        HasFunction = function() return false end,
        GetItemLabel = function(itemID) return loaded[itemID] or ("item %d"):format(itemID) end,
        Comma = function(n) return tostring(n) end,
        FormatAge = function() return "1m" end,
    },
    UI = { RegisterTab = function() end },
    Prices = {
        GetTable = function() return {} end,
        IsStale = function() return false end,
    },
    db = { characters = {} },
}

assert(loadfile(lfs_cwd .. "/UI/Columns.lua"))("Blackthornes_TS", ns)
assert(loadfile(lfs_cwd .. "/UI/Tab_Prices.lua"))("Blackthornes_TS", ns)

local failures = 0
local function check(label, got, expected)
    local ok = got == expected
    if not ok then failures = failures + 1 end
    print(("  %-52s %-14s %s"):format(label, tostring(got), ok and "ok" or ("FAILED, expected " .. tostring(expected))))
end

local function Label()
    return { text = "", SetText = function(self, t) self.text = t end, SetTextColor = function() end }
end

local function Row()
    local function Shown() return { SetShown = function() end } end
    local row = { name = Label(), icon = Shown(), star = Shown(), cells = {} }
    row.star.SetItem = function() end
    row.name.SetPoint = function() end
    row.fold = Shown()
    row.fold.text = Label()
    for _, key in ipairs({ "market", "min", "quantity", "liquidity", "trend", "age" }) do
        row.cells[key] = Label()
    end
    row.columnsVersion = ns.Columns and ns.Columns.version
    row.IsShown = function() return true end
    return row
end

local NameArrived = ns.UI._PricesNameArrived
check("the tab listens for names", type(NameArrived), "function")
if type(NameArrived) ~= "function" then
    error("price names: the tab never draws a name the game sends late")
end

local widgets, _, updateRow = ns.UI._PricesWidgets()

local shown = true
local redraws = 0
local list = { rows = {} }
function list:IsVisible() return shown end
function list:Refresh()
    redraws = redraws + 1
    for _, row in ipairs(self.rows) do updateRow(row, row.data) end
end
widgets.list = list

local silkRow, ironRow = Row(), Row()
silkRow.data = { itemID = SILK, record = { market = 100 } }
ironRow.data = { itemID = IRON, record = { market = 50 } }
list.rows = { silkRow, ironRow }
list:Refresh()
redraws = 0

print("a row drawn before its item loaded")
check("reads its number", silkRow.name.text, "item 4306")
check("and remembers it waits for it", silkRow.waitsFor, SILK)

print("the game sends an item nobody on screen waits for")
NameArrived(OTHER, true)
RunTimers()
check("nothing is drawn", redraws, 0)

print("the game sends Silk and Iron in one burst")
loaded[SILK], loaded[IRON] = "Silk Cloth", "Iron Ore"
NameArrived(SILK, true)
NameArrived(IRON, true)
check("waits a moment to gather the burst", redraws, 0)
RunTimers()
check("then draws the rows once", redraws, 1)
check("Silk shows its name", silkRow.name.text, "Silk Cloth")
check("Iron shows its name", ironRow.name.text, "Iron Ore")
check("and no longer waits", silkRow.waitsFor, nil)

print("while the tab is hidden")
redraws = 0
silkRow.data = { itemID = OTHER, record = { market = 1 } }
updateRow(silkRow, silkRow.data)
shown = false
loaded[OTHER] = "Mystery Box"
NameArrived(OTHER, true)
RunTimers()
check("nothing is drawn", redraws, 0)

if failures > 0 then error(("%d price name check(s) failed"):format(failures)) end
print("  price names: all checks passed")
