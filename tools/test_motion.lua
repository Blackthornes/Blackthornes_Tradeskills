-- The windows' motion and glow, outside WoW: Farmer's tweens brought over, so
-- the two addons move alike (asked for: "next-gen, neon glow, dopamine hits").
--
-- What must hold:
--   1. Tweens land where they were headed, a new one in the same slot
--      replaces the old, an error inside one is dropped, and with Window
--      effects off everything lands at once.
--   2. A window opening fades up and its glow flares, then settles, and its
--      saved spot is exactly where it was before.
--   3. Hover washes on list rows and menu entries really show. They were
--      drawn with a colour alpha of 0, which no SetAlpha can lift.
--   4. Buttons ease into their hover colour, an armed button stays red, and
--      the label dips while held and goes back to exactly where it was.
--   5. The gold line under the tabs lands under the tab picked.
--   6. A progress bar glides up and jumps back down.

local ns = {}

-- Tests share one Lua state, so the globals replaced here are put back.
local saved = { CreateFrame = CreateFrame, UIParent = UIParent, CreateColor = CreateColor,
    GameTooltip = GameTooltip }

local function Region(parent)
    local region = { shown = true, parent = parent, scripts = {}, points = {}, alpha = 1,
        width = 0, height = 0, events = {}, children = {} }

    region.Show = function(self)
        local was = self.shown
        self.shown = true
        if not was and self.scripts.OnShow then self.scripts.OnShow(self) end
    end
    region.Hide = function(self)
        local was = self.shown
        self.shown = false
        if was and self.scripts.OnHide then self.scripts.OnHide(self) end
    end
    region.SetShown = function(self, on) if on then self:Show() else self:Hide() end end
    region.IsShown = function(self) return self.shown end
    region.IsVisible = function(self) return self.shown end
    region.SetAlpha = function(self, a) self.alpha = a end
    region.GetAlpha = function(self) return self.alpha end
    region.SetWidth = function(self, w) self.width = w end
    region.SetHeight = function(self, h) self.height = h end
    region.GetWidth = function(self) return self.width end
    region.GetHeight = function(self) return self.height end
    region.SetSize = function(self, w, h) self.width, self.height = w, h end
    region.SetColorTexture = function(self, r, g, b, a) self.color = { r, g, b, a or 1 } end
    region.SetGradient = function(self, orientation, from, to)
        self.gradient = { orientation, from, to }
    end
    region.SetTextColor = function(self, r, g, b, a) self.textColor = { r, g, b, a } end
    region.SetText = function(self, text) self.text = text end
    region.GetText = function(self) return self.text end
    region.GetStringWidth = function(self) return #(self.text or "") * 6 end
    region.SetScript = function(self, name, fn) self.scripts[name] = fn end
    region.GetScript = function(self, name) return self.scripts[name] end
    region.HookScript = function(self, name, fn)
        local old = self.scripts[name]
        self.scripts[name] = function(...)
            if old then old(...) end
            fn(...)
        end
    end

    -- As the game does: the short forms fill in the parent and the same
    -- point, and setting a point the region already has moves that one.
    region.SetPoint = function(self, point, a, b, c, d)
        local relativeTo, relativePoint, x, y
        if a == nil or type(a) == "number" then
            relativeTo, relativePoint, x, y = self.parent, point, a or 0, b or 0
        elseif type(b) == "string" then
            relativeTo, relativePoint, x, y = a, b, c or 0, d or 0
        else
            relativeTo, relativePoint, x, y = a, point, b or 0, c or 0
        end

        local anchor = { point, relativeTo, relativePoint, x, y }
        for index, existing in ipairs(self.points) do
            if existing[1] == point then
                self.points[index] = anchor
                return
            end
        end
        self.points[#self.points + 1] = anchor
    end
    region.ClearAllPoints = function(self) self.points = {} end
    region.GetNumPoints = function(self) return #self.points end
    region.GetPoint = function(self, index)
        local p = self.points[index or 1]
        if not p then return nil end
        return p[1], p[2], p[3], p[4], p[5]
    end
    region.IsMouseOver = function(self) return self.mouseOver == true end
    region.RegisterEvent = function(self, event) self.events[event] = true end
    region.UnregisterEvent = function(self, event) self.events[event] = nil end
    region.CreateTexture = function(self) return Region(self) end
    region.CreateFontString = function(self) return Region(self) end
    region.GetParent = function(self) return self.parent end
    region.SetParent = function(self, parent) self.parent = parent end
    region.SetScale = function(self, scale) self.scale = scale end
    region.GetEffectiveScale = function(self) return self.effectiveScale or 1 end
    region.GetTop = function(self) return self.top end
    region.GetMinMaxValues = function(self) return self.min or 0, self.max or 0 end
    region.SetMinMaxValues = function(self, lo, hi) self.min, self.max = lo, hi end
    region.GetValue = function(self) return self.value or 0 end
    region.SetValue = function(self, v) self.value = v end

    -- Any other method does nothing. Fields read as nil, as on a real frame,
    -- so a button no one disabled is not taken for a disabled one.
    return setmetatable(region, { __index = function(_, key)
        if type(key) == "string" and key:match("^%u") then return function() end end
    end })
end

-- Frames remember their children, so a test can find the ones a widget keeps
-- to itself (a menu's entries).
CreateFrame = function(_, _, parent)
    local frame = Region(parent)
    if type(parent) == "table" and rawget(parent, "children") then
        parent.children[#parent.children + 1] = frame
    end
    return frame
end
UIParent = Region()
CreateColor = function(r, g, b, a) return { r = r, g = g, b = b, a = a } end
GameTooltip = Region()

local settings = {}
ns.Config = {
    Get = function(_, key) return settings[key] end,
    Set = function(_, key, value) settings[key] = value end,
}

local function Load(path)
    local chunk = assert(loadfile(lfs_cwd .. path))
    chunk("Blackthornes_TS", ns)
end

Load("/UI/Theme.lua")
Load("/UI/Widgets.lua")

local Theme, Widgets, Motion = ns.Theme, ns.Widgets, ns.Motion

local passed, failed = 0, 0

local function check(label, got, want)
    local ok = got == want
    if ok then passed = passed + 1 else failed = failed + 1 end
    print(string.format("  %-62s %-10s %s", label, tostring(got), ok and "ok" or
        ("WRONG, wanted " .. tostring(want))))
end

local function near(a, b) return type(a) == "number" and math.abs(a - b) < 1e-6 end

local function Same(color, key)
    local r, g, b = Theme.Unpack(key)
    return color ~= nil and near(color[1], r) and near(color[2], g) and near(color[3], b)
end

print("")
print("the clock")

local owner = {}
local seen = {}
Motion:Run(owner, "a", 1, function(p) seen[#seen + 1] = p end, { ease = false })
check("a tween draws its start at once", seen[1], 0)
check("and is running", Motion:Running(owner, "a"), true)
Motion:Step(0.5)
check("half way through, half way", near(seen[#seen], 0.5), true)
Motion:Step(0.6)
check("it lands at its end", seen[#seen], 1)
check("and stops", Motion:Running(owner, "a"), false)

local first, second = 0, 0
Motion:Run(owner, "b", 1, function(p) first = p end)
Motion:Run(owner, "b", 1, function(p) second = p end)
Motion:Step(2)
check("a replaced tween stops where it was", first, 0)
check("its replacement runs to the end", second, 1)

local other
Motion:Run(owner, "bad", 1, function(p) if p > 0 then error("boom") end end)
Motion:Run(owner, "good", 1, function(p) other = p end)
check("a failing tween does not raise", pcall(Motion.Step, Motion, 0.5), true)
check("and is dropped", Motion:Running(owner, "bad"), false)
Motion:Step(1)
check("the others carry on", other, 1)

local value
Motion:Blend(owner, "hover", 1, 1, function(v) value = v end)
Motion:Step(0.5)
check("a blend moves toward its target", near(value, 0.5), true)
Motion:Blend(owner, "hover", 0, 1, function(v) value = v end)
check("turning back starts from where it was", near(value, 0.5), true)
Motion:Step(1)
check("and lands", value, 0)

settings.windowEffects = "off"
local instant
Motion:Run(owner, "off", 5, function(p) instant = p end)
check("with Window effects off a tween lands at once", instant, 1)
check("and nothing is left running", Motion:Running(owner, "off"), false)
settings.windowEffects = nil
check("anything else reads as full", Motion.Level(), "full")

print("")
print("a window opening")

local window = Region(UIParent)
window:SetPoint("CENTER", UIParent, "CENTER", 120, -40)
Theme.Halo(window, 10, 0.10)
check("the glow has four sides", #window.haloTextures, 4)
check("resting faintly", window.haloRest, 0.10)

local top = window.haloTextures[1]
Motion:Open(window)
check("it starts clear", window.alpha, 0)
local _, _, _, _, startY = window:GetPoint(1)
check("and a little low", startY < -40, true)
Motion:Step(0.1)
local flared = top.gradient and top.gradient[2].a
check("its glow flares brighter than at rest", (flared or 0) > 0.10, true)
Motion:Step(1)
local _, relativeTo, _, x, y = window:GetPoint(1)
check("it ends drawn in full", window.alpha, 1)
check("exactly where it was", x == 120 and y == -40 and relativeTo == UIParent, true)
check("with its glow back at rest", near(top.gradient[2].a, 0.10), true)

-- Opened again mid-opening: it must not settle lower each time.
Motion:Open(window)
Motion:Step(0.05)
Motion:Open(window)
Motion:Step(1)
local _, _, _, _, againY = window:GetPoint(1)
check("opened twice quickly, still where it was", againY, -40)

settings.windowEffects = "subtle"
Motion:Open(window)
local _, _, _, _, subtleY = window:GetPoint(1)
check("subtle fades without rising", subtleY, -40)
Motion:FinishAll()
settings.windowEffects = nil

print("")
print("hover washes that show")

local list = Widgets.CreateScrollList(Region(), {
    rowHeight = 20,
    isSelected = function(entry) return entry.id == 2 end,
})
list:SetHeight(100)
list:SetData({ { id = 1 }, { id = 2 }, { id = 3 } })

local row = list.rows[1]
check("a row's wash is drawn at full strength", row.highlight.color[4], 1)
check("and hidden by its alpha", row.highlight.alpha, 0)
-- The gold wash and edge glow hide at rest rather than trusting SetAlpha,
-- which left every row lit gold on Forever (2026-10-10).
check("the gold wash is hidden at rest", row.hoverWash.shown, false)
check("so is the edge glow", row.edgeGlow.shown, false)
check("and on every other row", list.rows[3].hoverWash.shown, false)
row.scripts.OnEnter(row)
Motion:Step(1)
check("under the mouse it shows", row.highlight.alpha, 1)
check("with its gold wash", row.hoverWash.shown, true)
check("and edge glow", row.edgeGlow.shown, true)
check("but not on the row beside it", list.rows[3].hoverWash.shown, false)
row.scripts.OnLeave(row)
Motion:Step(1)
check("and fades when the mouse leaves", row.highlight.alpha, 0)
check("its gold wash goes dark again", row.hoverWash.shown, false)
check("and its edge glow", row.edgeGlow.shown, false)
check("the selected row sits in a gold light", list.rows[2].glowBand.shown, true)
check("the others do not", list.rows[1].glowBand.shown, false)

local picked
local holder = Region()
local dropdown = Widgets.CreateDropdown(holder, {
    { text = "Full", value = "full" }, { text = "Off", value = "off" },
}, function(v) picked = v end)
check("the first option is picked to begin with", dropdown:GetValue(), "full")
dropdown.scripts.OnMouseDown(dropdown)
Motion:Step(1)
check("the menu opens", dropdown.menu.shown, true)
check("and listens for clicks elsewhere", dropdown.menu.events.GLOBAL_MOUSE_DOWN, true)

-- The menu's entries are its children: "Full", then "Off".
local menuEntry = dropdown.menu.children[2]

check("a menu entry's wash is drawn at full strength", menuEntry.highlight.color[4], 1)
check("hidden until hovered", menuEntry.highlight.alpha, 0)
menuEntry.scripts.OnEnter(menuEntry)
Motion:Step(1)
check("and shows under the mouse", menuEntry.highlight.alpha, 1)
menuEntry.scripts.OnLeave(menuEntry)
Motion:Step(1)
check("then fades", menuEntry.highlight.alpha, 0)
menuEntry.scripts.OnClick(menuEntry)
check("picking it says so", picked, "off")
check("and closes the menu", dropdown.menu.shown, false)
dropdown.scripts.OnMouseDown(dropdown)
check("opened again, the picked option wears the gold edge", menuEntry.mark.shown, true)
check("and the other does not", dropdown.menu.children[1].mark.shown, false)
dropdown.scripts.OnMouseDown(dropdown)
check("a second click on the box closes it", dropdown.menu.shown, false)

dropdown.scripts.OnMouseDown(dropdown)
dropdown.menu.scripts.OnEvent(dropdown.menu, "GLOBAL_MOUSE_DOWN")
check("a click elsewhere closes the menu", dropdown.menu.shown, false)
check("and it stops listening", dropdown.menu.events.GLOBAL_MOUSE_DOWN, nil)

dropdown.scripts.OnMouseDown(dropdown)
dropdown.menu.mouseOver = true
dropdown.menu.scripts.OnEvent(dropdown.menu, "GLOBAL_MOUSE_DOWN")
check("a click on the menu itself leaves it open", dropdown.menu.shown, true)
dropdown.menu.mouseOver = false
dropdown.scripts.OnHide(dropdown)
check("its tab closing takes the menu with it", dropdown.menu.shown, false)

-- A list that scrolls (Settings' pages) cut the menu off at its foot, so it
-- opens on UIParent at the box's size, and closes once the box scrolls away.
holder.effectiveScale = 1.2
dropdown.effectiveScale = 1.2
dropdown.top = 300
dropdown.scripts.OnMouseDown(dropdown)
check("the menu opens on UIParent", dropdown.menu.parent == UIParent, true)
check("at the box's own size", dropdown.menu.scale, 1.2)
dropdown.menu.scripts.OnUpdate(dropdown.menu)
check("it stays open while the box stays put", dropdown.menu.shown, true)
dropdown.top = 260
dropdown.menu.scripts.OnUpdate(dropdown.menu)
check("and closes when the box scrolls away", dropdown.menu.shown, false)

print("")
print("buttons")

local button = Widgets.CreateButton(Region(), "Scan auctions", function() end, { primary = true })
button.scripts.OnEnter(button)
Motion:Step(0.06)
local mid = button.background.color
check("a button eases toward its hover colour",
    not Same(mid, "accent") and not Same(mid, "accentHi"), true)
Motion:Step(1)
check("and gets there", Same(button.background.color, "accentHi"), true)
check("a primary button glows under the mouse", button.haloTextures[1].shown, true)
button.scripts.OnLeave(button)
Motion:Step(1)
check("and goes back to rest", Same(button.background.color, "accent"), true)
check("its glow settles to a faint light", button.haloTextures[1].shown, true)
check("a primary button's label is dark on its gold", Same(button.label.textColor, "ink"), true)

-- Every kind of button keeps its label readable on its own face, at rest and
-- under the mouse: the auction house's Scan and Post Crafted once drew dark
-- lettering on a dark face and read as empty boxes.
local function Luminance(c)
    local function lin(v) v = v or 0; return v <= 0.03928 and v / 12.92 or ((v + 0.055) / 1.055) ^ 2.4 end
    return 0.2126 * lin(c[1]) + 0.7152 * lin(c[2]) + 0.0722 * lin(c[3])
end
local function Contrast(a, b)
    local la, lb = Luminance(a), Luminance(b)
    if la < lb then la, lb = lb, la end
    return (la + 0.05) / (lb + 0.05)
end

local kinds = {
    { "a plain button", {}, 4.5 },
    { "a primary button", { primary = true }, 4.5 },
    -- Red on dark metal reads as a warning first; it only needs to stand out.
    { "a danger button", { danger = true }, 3.5 },
    { "a primary button with its own dark face", { primary = true, baseColor = { 0.06, 0.07, 0.09, 1 } }, 4.5 },
}
for _, kind in ipairs(kinds) do
    local b = Widgets.CreateButton(Region(), "Scan", function() end, kind[2])
    b:ApplyBaseColor()
    b:SetEnabledState(true)
    check(kind[1] .. " is readable at rest",
        Contrast(b.label.textColor, b.background.color) >= kind[3], true)
    b.scripts.OnEnter(b)
    Motion:Step(1)
    check(kind[1] .. " is readable under the mouse",
        Contrast(b.label.textColor, b.background.color) >= kind[3], true)
    b.scripts.OnLeave(b)
    Motion:Step(1)
end

local plain = Widgets.CreateButton(Region(), "Clear", function() end)
plain:SetConfirming(true)
plain.scripts.OnEnter(plain)
Motion:Step(1)
check("an armed button stays red under the mouse", Same(plain.borderTextures[1].color, "loss"), true)
plain:SetConfirming(false)
check("and its edge is lit once disarmed", Same(plain.borderTextures[1].color, "accentHi"), true)
plain.scripts.OnLeave(plain)
Motion:Step(1)
check("then rests", Same(plain.borderTextures[1].color, "metal"), true)

local _, _, _, _, labelY = plain.label:GetPoint(1)
plain.scripts.OnMouseDown(plain)
local _, _, _, _, pressedY = plain.label:GetPoint(1)
local _, _, _, _, pressedY2 = plain.label:GetPoint(2)
check("the label dips a pixel while held", pressedY, labelY - 1)
check("every point of it", pressedY2, labelY - 1)
plain.scripts.OnMouseUp(plain)
local _, _, _, _, backY = plain.label:GetPoint(1)
check("and goes back exactly", backY, labelY)
check("with the same number of points", plain.label:GetNumPoints(), 2)

local off = Widgets.CreateButton(Region(), "Buy", function() end)
off:SetEnabledState(false)
off.scripts.OnEnter(off)
Motion:Step(1)
check("a disabled button never lights", Same(off.background.color, "panel"), true)

print("")
print("the tab line")

local strip = Widgets.CreateTabStrip(Region(), {
    { key = "a", text = "Profit", width = 90 },
    { key = "b", text = "Queue", width = 90 },
    { key = "c", text = "Post", width = 60 },
})
strip:Select("a")
check("the line is under the first tab", strip.line.points[1][2], strip.tabs[1])
check("as wide as it", strip.line.width, 90)
check("which sits in a gold light", strip.tabs[1].lit.shown, true)

strip:Select("c")
Motion:Step(0.05)
local _, _, _, sliding = strip.line:GetPoint(1)
check("it slides from the old tab", sliding < 0, true)
Motion:Step(1)
local _, anchor, _, landedX = strip.line:GetPoint(1)
check("and lands under the new one", anchor == strip.tabs[3] and near(landedX, 0), true)
check("as wide as that one", near(strip.line.width, 60), true)
check("the old tab's light goes out", strip.tabs[1].lit.shown, false)
check("the label picked is gold", Same(strip.tabs[3].label.textColor, "accent"), true)

strip:Select("a")
Motion:Step(0.08)
local _, _, _, midway = strip.line:GetPoint(1)
local midwayX = midway + strip.tabs[1].left
strip:Select("b")
local _, _, _, turned = strip.line:GetPoint(1)
check("picked again mid-slide, it turns from where it is", near(turned + strip.tabs[2].left, midwayX), true)
Motion:Step(1)
local _, anchorB, _, landedB = strip.line:GetPoint(1)
check("and lands under that tab", anchorB == strip.tabs[2] and near(landedB, 0), true)

local tab = strip.tabs[3]
tab.scripts.OnEnter(tab)
Motion:Step(1)
check("another tab lights under the mouse", tab.hover.alpha, 1)
tab.scripts.OnLeave(tab)
Motion:Step(1)
check("and fades after", tab.hover.alpha, 0)

print("")
print("progress")

local bar = Widgets.CreateProgressBar(Region())
bar:SetWidth(102)
bar:SetProgress(0.5)
check("it glides up rather than jumping", bar.fill.width < 50, true)
Motion:Step(0.1)
check("on its way", bar.fill.width > 1 and bar.fill.width < 50, true)
check("with a spark at its leading edge", bar.spark.shown, true)
Motion:Step(1)
check("and lands where it was sent", bar.fill.width, 50)
bar:SetProgress(0.1)
check("going back down is a jump, not a slide", bar.fill.width, 10)
check("with nothing left running", Motion:Running(bar, "fill"), false)
bar:SetProgress(1)
Motion:Step(1)
check("full, the spark goes out", bar.spark.shown, false)
bar:SetProgress(0.6, true)
check("asked to, it jumps at once", bar.fill.width, 60)

print("")
print("the tick")

local toggled
local box = Widgets.CreateCheckbox(Region(), "Enabled", function(on) toggled = on end, false)
check("unticked to begin with", box.tick.shown, false)
box.scripts.OnClick(box)
check("ticked by hand", box:GetChecked(), true)
check("and told", toggled, true)
check("the tick starts small", box.tick.width < 8, true)
Motion:Step(0.11)
check("pops a little past its size", box.tick.width > 8, true)
Motion:Step(1)
check("and settles at it", near(box.tick.width, 8), true)
box.scripts.OnClick(box)
check("unticked, it is gone", box.tick.shown, false)
box:SetChecked(true)
check("ticked from code it is simply there", Motion:Running(box.tick, "pop"), false)

Motion:FinishAll()

for key, value in pairs(saved) do _G[key] = value end

print("")
print(("%d passed, %d failed"):format(passed, failed))
assert(failed == 0, "motion checks failed")
