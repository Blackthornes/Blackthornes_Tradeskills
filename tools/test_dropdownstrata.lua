-- A drop-down's menu opens over the window it sits in.
--
-- Opening a menu moves it onto UIParent, and that set its strata to DIALOG,
-- the same as the Rules and Settings windows. So in those windows the menu
-- opened behind the rows under it, whose boxes took the clicks: Lowest
-- Price, When Cheaper and Post For looked like they did nothing. A menu now
-- opens at FULLSCREEN_DIALOG, and a strata a caller set higher is kept.

local ns = {}
ns.Theme = {
    Fill = function() return { SetColorTexture = function() end, SetAlpha = function() end } end,
    Unpack = function() return 0, 0, 0, 1 end,
    Border = function() end,
    SetBorderColor = function() end,
    FONT = "font",
    sizes = { small = 10, normal = 12, tiny = 9 },
    TextWidth = function() return 40 end,
}

local Frame
function Frame()
    local frame = { scripts = {}, text = "", strata = "MEDIUM", shown = false }
    frame.SetScript = function(self, name, fn) self.scripts[name] = fn end
    frame.GetScript = function(self, name) return self.scripts[name] end
    frame.SetText = function(self, text) self.text = text end
    frame.GetText = function(self) return self.text end
    frame.SetFrameStrata = function(self, s) self.strata = s end
    frame.GetFrameStrata = function(self) return self.strata end
    frame.SetParent = function(self, p) self.parent = p end
    frame.GetParent = function(self) return self.parent end
    frame.GetEffectiveScale = function() return 1 end
    frame.Show = function(self) self.shown = true end
    frame.Hide = function(self) self.shown = false end
    frame.IsShown = function(self) return self.shown end
    frame.GetWidth = function() return 100 end
    frame.GetHeight = function() return 20 end
    frame.GetStringWidth = function() return 40 end
    frame.CreateTexture = function() return Frame() end
    frame.CreateFontString = function() return Frame() end
    -- Only a method (a capital first letter) is a do-nothing stand-in.
    return setmetatable(frame, { __index = function(_, key)
        if type(key) == "string" and key:match("^%u") then return function() end end
    end })
end

CreateFrame = function() return Frame() end
UIParent = Frame()
ns.Theme.CreatePanel = function() return Frame() end
ns.Theme.CreateLabel = function() return Frame() end
-- Any other look call hands back a plain piece and does nothing else.
setmetatable(ns.Theme, { __index = function() return function() return Frame() end end })

assert(loadfile(lfs_cwd .. "/UI/Widgets.lua"))("Blackthornes_TS", ns)
local Widgets = ns.Widgets

local passed, failed = 0, 0
local function check(label, got, want)
    local ok = got == want
    if ok then passed = passed + 1 else failed = failed + 1 end
    print(string.format("  %-56s %-18s %s", label, tostring(got), ok and "ok" or
        ("WRONG, wanted " .. tostring(want))))
end

local OPTIONS = { { text = "Set Price", value = "set" }, { text = "% of Market", value = "market" } }

print("")
print("a drop-down's menu")

local box = Widgets.CreateDropdown(Frame(), OPTIONS, function() end)
check("starts above a DIALOG window",           box.menu.strata, "FULLSCREEN_DIALOG")
box.scripts.OnMouseDown(box)
check("opened, it stays above a DIALOG window", box.menu.strata, "FULLSCREEN_DIALOG")
check("and moves onto UIParent",                box.menu.parent, UIParent)

local high = Widgets.CreateDropdown(Frame(), OPTIONS, function() end)
high.menu:SetFrameStrata("TOOLTIP")
high.scripts.OnMouseDown(high)
check("a higher strata a caller set is kept",   high.menu.strata, "TOOLTIP")

local low = Widgets.CreateDropdown(Frame(), OPTIONS, function() end)
low.menu:SetFrameStrata("DIALOG")
low.scripts.OnMouseDown(low)
check("a lower one is raised when it opens",    low.menu.strata, "FULLSCREEN_DIALOG")

print("")
if failed > 0 then error(("%d check(s) failed"):format(failed), 0) end
print(("all %d drop-down strata checks passed"):format(passed))
