-- The Titanforged window frame (Trent's pick, 2026-10-04), outside WoW.
--
-- What must hold:
--   1. A dressed window gets its rim, four corner gems turned to their
--      corners, the name on a plate wide enough for it, the portrait with
--      the emblem, and a close gem that closes.
--   2. Its art comes from this addon's own Media\Frame folder.
--   3. The light round the portrait runs once as the window opens and goes
--      out; with Window effects off it never shows.
--   4. The glint runs along the top edge and comes round again while the
--      window shows, never with effects Subtle or Off, and stops when the
--      window hides.
--   5. Hanging tabs: the one showing is taller and reaches up over the rim.

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
    region.GetMinMaxValues = function(self) return self.min or 0, self.max or 0 end
    region.SetMinMaxValues = function(self, lo, hi) self.min, self.max = lo, hi end
    region.GetValue = function(self) return self.value or 0 end
    region.SetValue = function(self, v) self.value = v end
    region.SetTexture = function(self, path) self.texture = path end
    region.SetTexCoord = function(self, ...) self.coords = { ... } end
    region.SetRotation = function(self, radians) self.rotation = radians end
    region.SetBlendMode = function(self, mode) self.blend = mode end
    region.SetFrameLevel = function(self, level) self.level = level end
    region.GetFrameLevel = function(self) return self.level or 1 end

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
Load("/UI/Titanforged.lua")

local Theme, Widgets, Motion, Titanforged = ns.Theme, ns.Widgets, ns.Motion, ns.Titanforged

local passed, failed = 0, 0

local function check(label, got, want)
    local ok = got == want
    if ok then passed = passed + 1 else failed = failed + 1 end
    print(string.format("  %-58s %-10s %s", label, tostring(got), ok and "ok" or
        ("WRONG, wanted " .. tostring(want))))
end

local function near(a, b) return type(a) == "number" and math.abs(a - b) < 0.01 end

print("")
print("dressing a window")

local window = Region()
window:SetSize(1060, 548)
local closed = false
local trim = Titanforged:Dress(window, {
    title = "Blackthornes Tradeskills", portrait = true,
    close = function() closed = true end,
})

check("the trim is kept on the window", window.titan, trim)
check("four corner gems", #trim.corners, 4)
check("from this addon's art", trim.corners[1].texture, [[Interface\AddOns\Blackthornes_TS\Media\Frame\Corner]])
check("the top left one unturned", trim.corners[1].coords[1] == 0 and trim.corners[1].coords[2] == 1, true)
check("the top right one turned to face it", trim.corners[2].coords[1] == 1 and trim.corners[2].coords[2] == 0, true)
check("the bottom right one upside down too", trim.corners[3].coords[3] == 1 and trim.corners[3].coords[4] == 0, true)
check("the name on the plate", trim.plate.label.text, "Blackthornes Tradeskills")
check("which is wide enough for it", trim.plate.width >= #"Blackthornes Tradeskills" * 6 + 30, true)
check("sat on the top edge", trim.plate.points[1][3], "TOP")
check("a portrait", trim.portrait ~= nil, true)
check("its light starts out", trim.portrait.sweep.alpha, 0)
check("drawn added, as light", trim.portrait.sweep.blend, "ADD")
check("the trim sits above the window's contents", trim.level, 21)

trim.closeButton.scripts.OnClick(trim.closeButton)
check("the close gem closes", closed, true)
trim.closeButton.scripts.OnEnter(trim.closeButton)
Motion:Step(1)
check("and glows red under the mouse", trim.closeButton.glow.alpha > 0.7, true)

local left, right, top, bottom = Titanforged.Reach(trim)
check("it reaches out past the top left for the portrait", left == 20 and top == 20, true)
check("and a little past the right for the gem", right > 3, true)

local plain = Titanforged:Dress(Region())
check("a side panel gets no plate", plain.plate, nil)
check("or portrait", plain.portrait, nil)
local pl, _, pt = Titanforged.Reach(plain)
check("so it reaches out only by its corners", pl == 3 and pt == 3, true)

print("")
print("opening")

Titanforged:Opened(window)
Motion:Step(0.1)
check("the light runs round the portrait", trim.portrait.sweep.alpha > 0, true)
check("turning as it goes", trim.portrait.sweep.rotation < 0, true)
Motion:Step(2)
check("and goes out when it has been round", trim.portrait.sweep.alpha, 0)

ns.Config:Set("windowEffects", "off")
Titanforged:Opened(window)
check("with effects off it never shows", trim.portrait.sweep.alpha, 0)
check("and nothing is left running", Motion:Running(trim.portrait.sweep), false)
ns.Config:Set("windowEffects", nil)

print("")
print("the glint")

window.shown = true
Titanforged:StartGlint(window, 0)
Motion:Step(0.8)
check("it runs along the top edge", trim.glint.alpha > 0.5, true)
local _, _, _, x = trim.glint:GetPoint(1)
check("about halfway along at halfway", x > 400 and x < 700, true)
Motion:Step(1)
check("then it is gone", trim.glint.alpha, 0)
check("and another is on its way", Motion:Running(trim.glint, "glint"), true)

Titanforged:StopGlint(window)
check("hidden, the window stops it", Motion:Running(trim.glint, "glint"), false)

ns.Config:Set("windowEffects", "subtle")
Titanforged:StartGlint(window, 0)
check("with effects subtle there is none", Motion:Running(trim.glint, "glint"), false)
ns.Config:Set("windowEffects", nil)

Titanforged:StartGlint(window, 0)
window.shown = false
Motion:Step(2)
check("one finishing on a hidden window sends no other", Motion:Running(trim.glint, "glint"), false)

print("")
print("hanging tabs")

local strip = Widgets.CreateTabStrip(Region(), {
    { key = "a", text = "Profit", width = 90 },
    { key = "b", text = "Queue", width = 90 },
}, nil, { hanging = true })
strip:Select("a")
check("the tab showing is taller", strip.tabs[1].height > strip.tabs[2].height, true)
local _, _, _, _, raised = strip.tabs[1]:GetPoint(1)
check("reaching up over the rim", raised > 0, true)
local _, _, _, _, level = strip.tabs[2]:GetPoint(1)
check("the others hang from the edge", level, 0)
check("its name lit gold", strip.tabs[1].label.textColor[1] == Theme.colors.accentHi[1], true)
strip:Select("b")
check("picking another swaps them", strip.tabs[2].height > strip.tabs[1].height, true)

Motion:FinishAll()

for key, value in pairs(saved) do _G[key] = value end

print("")
print(("%d passed, %d failed"):format(passed, failed))
assert(failed == 0, "titanforged checks failed")
