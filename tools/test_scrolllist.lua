-- The scroll list must not draw a row past its own bottom edge.
--
-- The bug the owner saw on the Prices tab: the "N items priced" line peeking out
-- from under the last row. The list is a plain frame that clips nothing, and
-- it rounded its visible row count UP, so a list 100 pixels tall with 22
-- pixel rows drew five of them and the fifth hung ten pixels below the list,
-- over the footer. Every tab built on this widget had the same overhang.
--
-- Rows are recycled frames positioned by hand, so this measures where the
-- widget puts them against how tall it is, with the frame API stubbed.

local ns = {}
ns.Theme = {
    Fill = function() return { SetColorTexture = function() end, SetAlpha = function() end } end,
    Unpack = function() return 0, 0, 0, 1 end,
    Border = function() end,
    CreateLabel = function() return {} end,
    AccentStripe = function(frame) return frame:CreateTexture() end,
}

-- A frame that remembers its size, its points and its scripts, and answers
-- everything else with a harmless no-op.
local function Frame()
    local frame = { points = {}, scripts = {}, shown = true, height = 0, min = 0, max = 0, value = 0 }

    frame.SetHeight = function(self, h) self.height = h end
    frame.GetHeight = function(self) return self.height end
    frame.SetPoint = function(self, point, ...)
        local args = { ... }
        -- Either (point, x, y) or (point, relativeTo, relativePoint, x, y).
        if type(args[1]) == "table" then
            self.points[point] = { x = args[3], y = args[4] }
        else
            self.points[point] = { x = args[1], y = args[2] }
        end
    end
    frame.Show = function(self) self.shown = true end
    frame.Hide = function(self) self.shown = false end
    frame.IsShown = function(self) return self.shown end
    frame.SetShown = function(self, on) self.shown = on and true or false end
    frame.SetScript = function(self, name, fn) self.scripts[name] = fn end
    frame.SetMinMaxValues = function(self, lo, hi) self.min, self.max = lo, hi end
    frame.GetMinMaxValues = function(self) return self.min, self.max end
    frame.SetValue = function(self, v)
        self.value = v
        if self.scripts.OnValueChanged then self.scripts.OnValueChanged(self, v) end
    end
    frame.GetValue = function(self) return self.value end
    frame.CreateTexture = function() return Frame() end

    return setmetatable(frame, { __index = function() return function() end end })
end

CreateFrame = function() return Frame() end

local Widgets
do
    local chunk = assert(loadfile(lfs_cwd .. "/UI/Widgets.lua"))
    chunk("Blackthornes_TS", ns)
    Widgets = ns.Widgets
end

local passed, failed = 0, 0

local function check(label, got, want)
    local ok = got == want
    if ok then passed = passed + 1 else failed = failed + 1 end
    print(string.format("  %-56s %-8s %s", label, tostring(got), ok and "ok" or
        ("WRONG, wanted " .. tostring(want))))
end

local ROW = 22

local function Rows(list)
    local shown, lowest = 0, 0
    for _, row in ipairs(list.rows) do
        if row.shown then
            shown = shown + 1
            local top = -(row.points.TOPLEFT and row.points.TOPLEFT.y or 0)
            if top + ROW > lowest then lowest = top + ROW end
        end
    end
    return shown, lowest
end

local function Data(n)
    local data = {}
    for i = 1, n do data[i] = { name = "row " .. i } end
    return data
end

print("")
print("a list that does not divide into whole rows")

local list = Widgets.CreateScrollList(Frame(), { rowHeight = ROW })
list:SetHeight(100)
list:SetData(Data(10))

local shown, lowest = Rows(list)
check("only whole rows are drawn",                 shown, 4)
check("the lowest row ends inside the list",       lowest <= 100, true)
check("the scrollbar reaches the rest",            select(2, list.scrollbar:GetMinMaxValues()), 6)

list.scrollbar:SetValue(6)
check("scrolled to the end, the last row is shown", list.rows[4].data and list.rows[4].data.name, "row 10")
check("and nothing hangs below it",                select(2, Rows(list)) <= 100, true)

print("")
print("a list that divides exactly")

list = Widgets.CreateScrollList(Frame(), { rowHeight = ROW })
list:SetHeight(88)
list:SetData(Data(10))

shown, lowest = Rows(list)
check("four rows fill 88 pixels",                  shown, 4)
check("to the pixel",                              lowest, 88)

print("")
print("fewer rows than fit")

list:SetData(Data(2))
shown = Rows(list)
check("only the rows with data show",              shown, 2)
check("and there is nothing to scroll",            select(2, list.scrollbar:GetMinMaxValues()), 0)

print("")
print("a long name that wraps onto three lines (the Profit tab, 2026-10-13)")

-- Theme.SetRowName keeps how tall a wrapped name is in `rowNeed`; here the
-- rows' name labels are given it by hand, for the entries marked tall.
local function NameLabel()
    local label = { text = "" }
    label.SetText = function(self, t) self.text = t end
    label.GetText = function(self) return self.text end
    return label
end

list = Widgets.CreateScrollList(Frame(), {
    rowHeight = ROW,
    createRow = function(row) row.name = NameLabel() end,
    updateRow = function(row, entry)
        row.name:SetText(entry.name)
        if entry.tall then
            row.name.rowNeed, row.name.rowNeedText = 36, entry.name
        else
            row.name.rowNeed, row.name.rowNeedText = nil, nil
        end
    end,
})
list:SetHeight(100)
local data = Data(6)
data[2].tall = true
list:SetData(data)

local function Spans(list)
    local spans = {}
    for _, row in ipairs(list.rows) do
        if row.shown then
            local top = -(row.points.TOPLEFT and row.points.TOPLEFT.y or 0)
            spans[#spans + 1] = { top = top, bottom = top + row.height }
        end
    end
    return spans
end

local spans = Spans(list)
check("the tall row grows to hold its name",       list.rows[2].height, 40)
check("the row under it starts below it",          spans[3] and spans[3].top, spans[2] and spans[2].bottom)
local lowestBottom = 0
for _, span in ipairs(spans) do if span.bottom > lowestBottom then lowestBottom = span.bottom end end
check("and nothing hangs below the list",          lowestBottom <= 100, true)
check("three rows fit beside the tall one",        #spans, 3)

-- A name set some other way since leaves its row the usual height.
list.rows[2].name:SetText("changed")
check("a name changed some other way needs no room", (function()
    data[2].tall = false
    list:Refresh()
    return list.rows[2].height
end)(), ROW)

-- Every entry tall: the scrollbar must still reach the last one.
data = Data(6)
for _, entry in ipairs(data) do entry.tall = true end
list:SetData(data)
local max = select(2, list.scrollbar:GetMinMaxValues())
list.scrollbar:SetValue(max)
max = select(2, list.scrollbar:GetMinMaxValues())
list.scrollbar:SetValue(max)
local last
for _, row in ipairs(list.rows) do if row.shown and row.data then last = row.data end end
check("scrolled to the end, the last tall row shows", last and last.name, "row 6")

print("")
if failed > 0 then
    error(("%d scroll list check(s) failed"):format(failed))
end
print("  scroll list: all checks passed")
