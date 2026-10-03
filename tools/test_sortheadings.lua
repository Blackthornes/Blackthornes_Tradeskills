-- Click a column heading to sort the list by it (Izbode's request,
-- 2026-10-02).
--
-- What must hold:
--   1. The first click sorts biggest first (names A to Z), the second turns
--      it round, the third gives the list back its own order.
--   2. Rows with no value go last either way round; ties keep their order.
--   3. The rows handed in are not reordered: the list keeps its own order.
--   4. A heading hidden by its tab stops sorting the list.

local saved = { CreateFrame = CreateFrame, UIParent = UIParent, GameTooltip = GameTooltip,
    C_Timer = C_Timer, GetTime = GetTime }

local function noop() end

local function NewFrame(parent)
    local f = { scripts = {}, shown = true, text = "", parent = parent }
    setmetatable(f, { __index = function(_, k)
        if type(k) == "string" and k:match("^%u") then return noop end
    end })
    f.SetScript = function(self, n, fn) self.scripts[n] = fn end
    f.Show = function(self) self.shown = true end
    f.Hide = function(self) self.shown = false end
    f.SetShown = function(self, v) self.shown = v and true or false end
    f.IsShown = function(self) return self.shown end
    f.SetText = function(self, t) self.text = t end
    f.GetParent = function(self) return self.parent end
    f.GetStringWidth = function(self) return #tostring(self.text or "") * 6 end
    f.CreateTexture = function(self) return NewFrame(self) end
    f.CreateFontString = function(self) return NewFrame(self) end
    f.SetTextColor = function(self, r, g, b) self.color = { r, g, b } end
    f.GetTextColor = function() return 0.5, 0.5, 0.5 end
    return f
end

CreateFrame = function(_, _, parent) return NewFrame(parent) end
UIParent = NewFrame()
GameTooltip = NewFrame()
C_Timer = { After = noop, NewTicker = function() return { Cancel = noop } end }
GetTime = function() return 1000 end

local ns = {}
ns.COLORS = setmetatable({}, { __index = function() return "ffffffff" end })
ns.NewModule = function(name) local m = {}; ns[name] = m; return m end
ns.RegisterCommand, ns.RegisterEvent = noop, noop
ns.Print, ns.PrintRaw, ns.Debug, ns.Warn = noop, noop, noop, noop
ns.db = {}
ns.Config = { Get = function() return nil end, Set = noop }
ns.Theme = {
    FONT = "font",
    sizes = { tiny = 10, small = 11, normal = 12, large = 14, title = 16 },
    TextWidth = function(label) return label:GetStringWidth() end,
    Unpack = function(name) return name end,
    Fill = function() return NewFrame() end,
    Border = noop, SetBorderColor = noop, TopSheen = noop,
    CreateLabel = function(parent) return NewFrame(parent) end,
}

assert(loadfile(lfs_cwd .. "/Core/Util.lua"))("Blackthornes_TS", ns)
assert(loadfile(lfs_cwd .. "/UI/Widgets.lua"))("Blackthornes_TS", ns)
local Widgets = ns.Widgets

local passed, failed = 0, 0
local function check(label, got, want)
    local ok = got == want
    if ok then passed = passed + 1 else failed = failed + 1 end
    print(string.format("  %-58s %-14s %s", label, tostring(got), ok and "ok" or
        ("WRONG, wanted " .. tostring(want))))
end

local headings = NewFrame()
local labels = { name = NewFrame(headings), profit = NewFrame(headings), stock = NewFrame(headings) }
labels.name:SetText("ITEM")
labels.profit:SetText("PROFIT")

local redrawn = 0
local sorter = Widgets.SortableHeadings(labels, {
    name = function(row) return row.name end,
    profit = function(row) return row.profit end,
}, function() redrawn = redrawn + 1 end)
sorter:SetText({ "name" })

local rows = {
    { name = "Bolt", profit = 50 },
    { name = "apron", profit = nil },
    { name = "Cloak", profit = 200 },
    { name = "Belt", profit = 50 },
}

local function Names(list)
    local out = {}
    for index, row in ipairs(list) do out[index] = row.name end
    return table.concat(out, ",")
end

local function Click(key) sorter.buttons[key].scripts.OnClick(sorter.buttons[key]) end

print("sorting by a heading")

check("nothing clicked: the list's own order", Names(sorter:Sort(rows)), "Bolt,apron,Cloak,Belt")
check("a heading with no value to sort by is not clickable", sorter.buttons.stock, nil)

Click("profit")
check("PROFIT once: biggest first, unknown last, ties in order",
    Names(sorter:Sort(rows)), "Cloak,Bolt,Belt,apron")
check("the list was redrawn", redrawn, 1)
check("PROFIT is lit", labels.profit.color and labels.profit.color[1], "accent")
check("the rows handed in kept their order", Names(rows), "Bolt,apron,Cloak,Belt")

Click("profit")
check("PROFIT twice: smallest first, unknown still last",
    Names(sorter:Sort(rows)), "Bolt,Belt,Cloak,apron")

Click("profit")
check("PROFIT a third time: the list's own order", Names(sorter:Sort(rows)), "Bolt,apron,Cloak,Belt")
check("and PROFIT goes back to its own colour", labels.profit.color and labels.profit.color[1], 0.5)

Click("name")
check("ITEM once: A to Z, whatever the case", Names(sorter:Sort(rows)), "apron,Belt,Bolt,Cloak")
Click("name")
check("ITEM twice: Z to A", Names(sorter:Sort(rows)), "Cloak,Bolt,Belt,apron")

labels.name:Hide()
sorter:Sync()
check("its heading hidden: the list's own order", Names(sorter:Sort(rows)), "Bolt,apron,Cloak,Belt")

labels.name:Show()
sorter:Sync()
Click("profit")
sorter:Reset()
check("Reset gives the list its own order", Names(sorter:Sort(rows)), "Bolt,apron,Cloak,Belt")

for key, value in pairs(saved) do _G[key] = value end

print("")
if failed > 0 then
    error(string.format("FAIL -- %d of %d heading sort checks wrong", failed, passed + failed))
end
print(string.format("PASS -- clicking a heading sorts the list (%d checks)", passed))
