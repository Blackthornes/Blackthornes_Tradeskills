-- The shared trim added in the visual pass, measured without a game client:
-- the thin bars, the item icons, and the lit row a list keeps for whatever
-- the detail pane is showing.

local ns = {}

-- A region that remembers what was drawn on it; anything else is a no-op.
local function Region()
    local region = { shown = true, points = {}, scripts = {}, height = 0, width = 0 }

    region.Show = function(self) self.shown = true end
    region.Hide = function(self) self.shown = false end
    region.SetShown = function(self, on) self.shown = on and true or false end
    region.IsShown = function(self) return self.shown end
    region.SetWidth = function(self, w) self.width = w end
    region.SetHeight = function(self, h) self.height = h end
    region.GetHeight = function(self) return self.height end
    region.SetSize = function(self, w, h) self.width, self.height = w, h end
    region.SetTexture = function(self, path) self.texture = path end
    region.SetColorTexture = function(self, r, g, b, a) self.color = { r, g, b, a } end
    region.SetScript = function(self, name, fn) self.scripts[name] = fn end
    region.GetScript = function(self, name) return self.scripts[name] end
    region.CreateTexture = function() return Region() end
    region.CreateFontString = function() return Region() end
    region.GetMinMaxValues = function(self) return self.min or 0, self.max or 0 end
    region.SetMinMaxValues = function(self, lo, hi) self.min, self.max = lo, hi end
    region.GetValue = function(self) return self.value or 0 end
    region.SetValue = function(self, v) self.value = v end

    return setmetatable(region, { __index = function() return function() end end })
end

CreateFrame = function() return Region() end
UIParent = Region()

local function Load(path)
    local chunk = assert(loadfile(lfs_cwd .. path))
    chunk("Blackthornes_TS", ns)
end

Load("/UI/Theme.lua")
Load("/UI/Widgets.lua")

local Theme, Widgets = ns.Theme, ns.Widgets

local passed, failed = 0, 0

local function check(label, got, want)
    local ok = got == want
    if ok then passed = passed + 1 else failed = failed + 1 end
    print(string.format("  %-58s %-10s %s", label, tostring(got), ok and "ok" or
        ("WRONG, wanted " .. tostring(want))))
end

local function Same(color, key)
    local r, g, b = Theme.Unpack(key)
    return color ~= nil and color[1] == r and color[2] == g and color[3] == b
end

print("")
print("thin bars")

local bar = Theme.CreateBar(Region(), 40, 2)
check("no value: hidden", bar.track.shown, false)

bar:Set(0.5, "profit")
check("half: half the width", bar.fill.width, 20)
check("and shown", bar.track.shown, true)
check("in the colour asked for", Same(bar.fill.color, "profit"), true)

bar:Set(3)
check("past full: stops at full", bar.fill.width, 40)

bar:Set(-1)
check("below nothing: no fill drawn", bar.fill.shown, false)

print("")
print("item icons")

ns.Util = { GetItemIcon = function(itemID) return itemID == 1 and "icon-one" or nil end }

local icon = Theme.CreateItemIcon(Region(), 16)
check("starts hidden", icon.shown, false)

Theme.SetItemIcon(icon, 1)
check("a known item: its icon", icon.texture, "icon-one")
check("and shown", icon.shown, true)

Theme.SetItemIcon(icon, 2)
check("not sent yet: the question mark", icon.texture, [[Interface\Icons\INV_Misc_QuestionMark]])

Theme.SetItemIcon(icon, nil)
check("no item at all: hidden", icon.shown, false)

print("")
print("the selected row")

local selected = 2
local clicked

local list = Widgets.CreateScrollList(Region(), {
    rowHeight = 20,
    isSelected = function(entry) return entry.id == selected end,
    onClick = function(entry) clicked = entry.id; selected = entry.id end,
})
list:SetHeight(100)
list:SetData({ { id = 1 }, { id = 2 }, { id = 3 } })

check("the selected entry's row is lit", Same(list.rows[2].background.color, "glassActive"), true)
check("with the gold edge", list.rows[2].hoverEdge.shown, true)
check("another row is not", Same(list.rows[1].background.color, "glassActive"), false)
check("and has no edge", list.rows[1].hoverEdge.shown, false)

list.rows[3].scripts.OnClick(list.rows[3], "LeftButton")
check("clicking a row selects it", clicked, 3)
check("and it lights at once", Same(list.rows[3].background.color, "glassActive"), true)
check("the old one goes back to its band", Same(list.rows[2].background.color, "glassAlt"), true)

list.rows[3].scripts.OnLeave(list.rows[3])
check("the mouse leaving keeps the selected edge", list.rows[3].hoverEdge.shown, true)

print("")
print(("%d passed, %d failed"):format(passed, failed))
assert(failed == 0, "glow up checks failed")
