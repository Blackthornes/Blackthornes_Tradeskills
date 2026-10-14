-- The sizzle on the scan line (Widgets.AddSizzle, 2026-10-14 test): it lights
-- only while given some strength, crackles along the bar's lit part or the
-- whole line, dies away when asked to fade, keeps to the line's reach, and
-- stays dark with window effects off.

local ns = {}

local function Region()
    local region = { shown = true, points = {}, scripts = {}, height = 0, width = 0, alpha = 1 }

    region.Show = function(self) self.shown = true end
    region.Hide = function(self) self.shown = false; local f = self.scripts.OnHide; if f then f(self) end end
    region.SetShown = function(self, on) if on then self:Show() else self:Hide() end end
    region.IsShown = function(self) return self.shown end
    region.SetWidth = function(self, w) self.width = w end
    region.GetWidth = function(self) return self.width end
    region.SetHeight = function(self, h) self.height = h end
    region.GetHeight = function(self) return self.height end
    region.SetSize = function(self, w, h) self.width, self.height = w, h end
    region.SetAlpha = function(self, a) self.alpha = a end
    region.GetAlpha = function(self) return self.alpha end
    region.SetColorTexture = function(self, r, g, b, a) self.color = { r, g, b, a } end
    region.ClearAllPoints = function(self) self.points = {} end
    region.SetPoint = function(self, ...) self.points[#self.points + 1] = { ... } end
    region.SetScript = function(self, name, fn) self.scripts[name] = fn end
    region.GetScript = function(self, name) return self.scripts[name] end
    region.CreateTexture = function() return Region() end
    region.CreateFontString = function() return Region() end

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

local Widgets = ns.Widgets
local effects = "full"
ns.Config = { Get = function(_, key) if key == "windowEffects" then return effects end end }

local passed, failed = 0, 0
local function check(label, got, want)
    local ok = got == want
    if ok then passed = passed + 1 else failed = failed + 1 end
    print(string.format("  %-58s %-8s %s", label, tostring(got), ok and "ok" or
        ("WRONG, wanted " .. tostring(want))))
end

math.randomseed(7)

local track = Region()
track:SetWidth(200)
track.fill = Region()
track.fill:SetWidth(60)

local sizzle = Widgets.AddSizzle(track)
local frame = sizzle.frame

local function Run(seconds)
    local onUpdate = frame.scripts.OnUpdate
    local t = 0
    while t < seconds do
        if frame.shown then onUpdate(frame, 1 / 60) end
        t = t + 1 / 60
    end
end

local function Lit(list)
    local count = 0
    for _, item in ipairs(list) do if item.texture.shown then count = count + 1 end end
    return count
end

local function FarthestBit()
    local most = 0
    for _, bit in ipairs(sizzle.bits) do
        local p = bit.texture.points[1]
        if bit.texture.shown and p then most = math.max(most, p[4] + bit.texture.width) end
    end
    return most
end

print("")
print("out until it is given strength")
Run(0.5)
check("nothing drawn", frame.shown, false)
check("no dashes", Lit(sizzle.bits), 0)

print("")
print("burning along the lit part")
sizzle:Set(1)
check("its frame shows", frame.shown, true)
local sawDash, sawSpark, past = false, false, false
for _ = 1, 60 do
    Run(1 / 30)
    if Lit(sizzle.bits) > 0 then sawDash = true end
    if Lit(sizzle.sparks) > 0 then sawSpark = true end
    if FarthestBit() > 62 then past = true end
end
check("dashes crackle on it", sawDash, true)
check("sparks spit from it", sawSpark, true)
check("no dash runs past the lit part", past, false)
check("the glow is as long as the lit part", sizzle.glow.width, 60)

print("")
print("along the whole line")
sizzle:Set(0.45, true)
Run(0.1)
check("the glow runs the whole line", sizzle.glow.width, 198)

print("")
print("dying away")
sizzle:Set(1, true, 1)
Run(0.5)
check("still burning halfway", frame.shown, true)
Run(0.6)
check("out once the fade is over", frame.shown, false)
check("and nothing left lit", Lit(sizzle.bits) + Lit(sizzle.sparks), 0)

print("")
print("put out")
sizzle:Set(1)
Run(0.2)
sizzle:Set(0)
check("its frame hides", frame.shown, false)
check("nothing left lit", Lit(sizzle.bits) + Lit(sizzle.sparks), 0)

print("")
print("window effects off")
effects = "off"
sizzle:Set(1)
check("it never lights", frame.shown, false)

print("")
print("window effects subtle")
effects = "subtle"
sizzle:Set(1)
local most, sparked = 0, false
for _ = 1, 60 do
    Run(1 / 30)
    most = math.max(most, Lit(sizzle.bits))
    if Lit(sizzle.sparks) > 0 then sparked = true end
end
check("a few dashes only", most <= 3, true)
check("no sparks", sparked, false)

print("")
print(("%d passed, %d failed"):format(passed, failed))
assert(failed == 0, "sizzle checks failed")
