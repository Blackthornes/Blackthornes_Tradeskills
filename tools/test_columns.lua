-- Choose which columns each list shows (a player's request, 2026-10-09).
--
-- What must hold:
--   1. Every column shows until it is unticked; a column with no heading
--      (a row's buttons) or one its list keeps can never be hidden.
--   2. The choice is one string setting, "list.key" by commas, and hiding
--      one list's column leaves every other list alone.
--   3. A hidden column takes no room: the ones left of it move right, and
--      the name's edge moves with them.
--   4. Show all puts one list's columns back, or every list's.
--   5. Entries the addon does not know (a list from a newer version) are
--      kept when the setting is written again.
--   6. Each list is told when its columns change, and the version moves on.

local saved = { CreateFrame = CreateFrame, UIParent = UIParent, GameTooltip = GameTooltip }

local function noop() end

local function NewFrame(parent)
    local f = { scripts = {}, shown = true, parent = parent }
    setmetatable(f, { __index = function(_, k)
        if type(k) == "string" and k:match("^%u") then return noop end
    end })
    f.Show = function(self) self.shown = true end
    f.Hide = function(self) self.shown = false end
    f.IsShown = function(self) return self.shown end
    f.GetParent = function(self) return self.parent end
    f.ClearAllPoints = function(self) self.point = nil end
    f.SetPoint = function(self, _, _, _, x) self.point = x end
    f.SetWidth = function(self, w) self.width = w end
    return f
end

CreateFrame = function(_, _, parent) return NewFrame(parent) end
UIParent = NewFrame()
GameTooltip = NewFrame()

local settings = { hiddenColumns = "future.list,prices.age" }
local ns = {}
ns.db = { settings = settings }
ns.Config = {
    Get = function(_, key) return settings[key] end,
    Set = function(_, key, value) settings[key] = value end,
}
ns.Theme = {}
ns.Widgets = {}

assert(loadfile(lfs_cwd .. "/UI/Columns.lua"))("Blackthornes_TS", ns)
local Columns = ns.Columns

local passed, failed = 0, 0
local function check(label, got, want)
    local ok = got == want
    if ok then passed = passed + 1 else failed = failed + 1 end
    print(string.format("  %-58s %-24s %s", label, tostring(got), ok and "ok" or
        ("WRONG, wanted " .. tostring(want))))
end

local PRICES = {
    { key = "age",    label = "AGE",    width = 40 },
    { key = "listed", label = "LISTED", width = 50 },
    { key = "market", label = "MARKET", width = 80 },
}
local POST = {
    { key = "action", label = "",     width = 56 },
    { key = "qty",    label = "LIST", width = 44, keep = true },
    { key = "total",  label = "TOTAL", width = 78 },
}

Columns:Register("prices", "Prices", PRICES)
Columns:Register("post", "Post", POST)

local told = 0
Columns:OnChange("prices", function() told = told + 1 end)

print("which columns show")

check("a saved hidden column is hidden", Columns:Shown("prices", PRICES[1]), false)
check("the rest show", Columns:Shown("prices", PRICES[2]), true)
check("a column with no heading always shows", Columns:Shown("post", POST[1]), true)
check("a kept column always shows", Columns.Hideable(POST[2]), false)
check("only hideable columns are counted", Columns:HiddenCount("post"), 0)
check("one hidden in all", Columns:HiddenCount(), 1)

local version = Columns.version
Columns:SetShown("prices", "market", false)
check("unticking MARKET hides it", Columns:Shown("prices", PRICES[3]), false)
check("the list was told", told, 1)
check("the version moved on", Columns.version > version, true)
check("saved as one string, unknown entries kept", settings.hiddenColumns,
    "future.list,prices.age,prices.market")

Columns:SetShown("prices", "market", false)
check("unticking it again changes nothing", told, 1)

local visible = Columns:Visible("prices", PRICES)
check("Visible leaves out hidden columns", #visible, 1)
check("and keeps the order", visible[1].key, "listed")

print("")
print("laying a row out")

local row = NewFrame()
local cells = {}
for _, column in ipairs(PRICES) do cells[column.key] = NewFrame(row) end
local offset = Columns:Place("prices", PRICES, cells)
check("AGE is hidden", cells.age.shown, false)
check("MARKET is hidden", cells.market.shown, false)
check("LISTED moves to the right edge", cells.listed.point, -8)
check("and the name gets the rest", offset, -8 - 50 - 6)

local placed = {}
Columns:Place("post", POST, {}, { place = function(column, x, shown) placed[column.key] = shown and x end })
check("a heading-less column still takes its room", placed.qty, -8 - 56 - 6)

print("")
print("showing them again")

Columns:ShowAll("prices")
check("Show all for Prices", Columns:HiddenCount("prices"), 0)
check("the other list's entry stays", settings.hiddenColumns, "future.list")
check("the list was told", told, 2)

settings.hiddenColumns = "prices.listed"
Columns:Reload()
check("a reset or reload reads the setting again", Columns:Shown("prices", PRICES[2]), false)
Columns:ShowAll()
check("Show all for every list", settings.hiddenColumns, "")

print("")
print("too narrow for every column")

-- Level Up's Learn next columns ran over the names on the window's own
-- width: columns that do not fit are set aside, least needed first, so
-- the name keeps its room. The saved choice is not touched.
local WIDE = {
    { key = "a", label = "A", width = 100 },
    { key = "b", label = "B", width = 100 },
    { key = "c", label = "C", width = 100 },
    { key = "d", label = "D", width = 100, extra = true },
}
local function Keys(set)
    local keys = {}
    for key in pairs(set) do keys[#keys + 1] = key end
    table.sort(keys)
    return table.concat(keys, ",")
end
local opts = { order = { "b", "c" }, nameMin = 150, left = 32 }
-- 8 + 32 + 150 = 190 before the columns, 106 each with its gap.
check("all fit, none set aside", Keys(Columns:Squeeze("wide", WIDE, 190 + 4 * 106, opts)), "")
check("one short, the first in the order goes", Keys(Columns:Squeeze("wide", WIDE, 190 + 4 * 106 - 1, opts)), "b")
check("two short, the next goes too", Keys(Columns:Squeeze("wide", WIDE, 190 + 2 * 106, opts)), "b,c")
check("never more than the order names", Keys(Columns:Squeeze("wide", WIDE, 100, opts)), "b,c")
check("a width not known yet sets nothing aside", Keys(Columns:Squeeze("wide", WIDE, 0, opts)), "")
opts.visible = function(column) return not column.extra end
check("a column the list hides takes no room", Keys(Columns:Squeeze("wide", WIDE, 190 + 3 * 106, opts)), "")

CreateFrame, UIParent, GameTooltip = saved.CreateFrame, saved.UIParent, saved.GameTooltip

print(string.format("\n%d passed, %d failed", passed, failed))
assert(failed == 0, "column choice tests failed")
