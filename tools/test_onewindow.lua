-- Tradeskills' tabs in the one Blackthornes window (UI/Main.lua's TSTabs,
-- the owner said build it, 2026-10-30).
--
-- What must hold:
--   1. On unless unticked; unticked, the window opens in its own place.
--   2. Ticked, opening Tradeskills opens the one window on it, with the
--      window laid into its area, bare of its own grip.
--   3. Settings and the other tabs open in the same area.
--   Swapping addons on the rail keeps the one window up.
--   4. Closing the one window gives the window back its own place.
--   5. "One Window:" on the General page writes every save.

local GLOBALS = { "CreateFrame", "UIParent", "GameTooltip", "GetCursorPosition", "C_Timer",
    "UISpecialFrames", "tinsert", "GetTime", "time" }
local saved = {}
for _, key in ipairs(GLOBALS) do saved[key] = _G[key] end

local function noop() end

local SCREEN_W, SCREEN_H = 1280, 720

-- Frames that remember their parent, size, scale, points and scripts.
local function Region(parent)
    local region = { parent = parent, shown = true, width = 0, height = 0, scale = 1,
        points = {}, scripts = {}, frameLevel = 1 }

    region.SetParent = function(self, p) self.parent = p end
    region.GetParent = function(self) return self.parent end
    region.SetSize = function(self, w, h) self.width, self.height = w, h end
    region.SetWidth = function(self, w) self.width = w end
    region.SetHeight = function(self, h) self.height = h end
    region.GetWidth = function(self) return self.width end
    region.GetHeight = function(self) return self.height end
    region.SetScale = function(self, s) self.scale = s end
    region.GetScale = function(self) return self.scale end
    region.GetEffectiveScale = function(self) return self.scale end
    region.SetPoint = function(self, point, relativeTo, relativePoint, x, y)
        if type(relativeTo) ~= "table" then
            relativeTo, relativePoint, x, y = self.parent, point, relativeTo, relativePoint
        end
        self.points = { { point, relativeTo, relativePoint, x or 0, y or 0 } }
    end
    region.SetAllPoints = function(self, other) self.points = { { "ALL", other } } end
    region.ClearAllPoints = function(self) self.points = {} end
    region.GetPoint = function(self)
        local p = self.points[1]
        if not p then return nil end
        return p[1], p[2], p[3], p[4], p[5]
    end
    region.Show = function(self) self.shown = true end
    region.Hide = function(self)
        local was = self.shown
        self.shown = false
        if was and self.scripts.OnHide then self.scripts.OnHide(self) end
    end
    region.SetShown = function(self, on) if on then self:Show() else self:Hide() end end
    region.IsShown = function(self) return self.shown end
    region.SetScript = function(self, name, fn) self.scripts[name] = fn end
    region.GetScript = function(self, name) return self.scripts[name] end
    region.HookScript = function(self, name, fn)
        local before = self.scripts[name]
        self.scripts[name] = function(...)
            if before then before(...) end
            fn(...)
        end
    end
    region.GetRegions = function() end
    region.GetFrameLevel = function(self) return self.frameLevel end
    region.SetFrameLevel = function(self, level) self.frameLevel = level end
    region.CreateTexture = function(self) return Region(self) end
    region.CreateFontString = function(self) return Region(self) end
    region.GetStringWidth = function() return 40 end
    region.GetUnboundedStringWidth = function() return 40 end
    region.GetStringHeight = function() return 12 end

    return setmetatable(region, { __index = function(_, key)
        if type(key) == "string" and key:match("^%u") then return noop end
    end })
end

CreateFrame = function(_, _, parent) return Region(parent) end
UIParent = Region()
UIParent.width, UIParent.height = SCREEN_W, SCREEN_H
GameTooltip = Region()
GetCursorPosition = function() return 0, 0 end
C_Timer = { After = noop }
UISpecialFrames = {}
tinsert = table.insert
GetTime = function() return 0 end
time = os.time

local settings = {}
local ns = {}
ns.COLORS = setmetatable({}, { __index = function() return "ffffffff" end })
ns.NewModule = function(name) local m = ns[name] or {}; ns[name] = m; return m end
ns.RegisterCommand = noop
ns.RegisterEvent = function() return true end
ns.Print, ns.PrintRaw, ns.Debug, ns.Warn = noop, noop, noop, noop
ns.db = { global = {}, settings = settings }
ns.Config = {
    DEFAULTS = { settings = { windowScale = 1 } },
    Get = function(_, key) return settings[key] end,
    Set = function(_, key, value) settings[key] = value end,
}
ns.Scanner = { isAuctionHouseOpen = false, CanFullScan = function() return true end,
    StartFullScan = noop }
ns.Prices = { Count = function() return 0 end, GetLastScan = noop }
ns.Recipes = { Count = function() return 0 end }
ns.VersionLabel = function() return "v1.4.0" end

local function Load(path)
    assert(loadfile(lfs_cwd .. path))("Blackthornes_TS", ns)
end

_G.BlackthornesWindow = nil
Load("/Core/Util.lua")
Load("/UI/Theme.lua")
Load("/UI/Widgets.lua")
Load("/UI/SharedWindow.lua")
Load("/UI/Main.lua")

local UI, Tabs, SW = ns.UI, ns.TSTabs, ns.SharedWindow
ns.PostPanel = { Reflow = noop }
UI:RegisterTab({ key = "profit", text = "Profit", order = 1, build = noop })
UI:RegisterTab({ key = "settings", text = "Settings", order = 99, build = noop })

ns.SharedMinimap = { Join = noop }
UI.minimapButton = {}
UI:JoinSharedMinimap()
local hub = _G.BlackthornesWindow

local passed, failed = 0, 0
local function check(label, ok)
    if ok then passed = passed + 1 else failed = failed + 1 end
    print(string.format("  %-60s %s", label, ok and "ok" or "WRONG"))
end

print("")
check("Tradeskills joins with its tabs", hub.entries.tradeskills and hub.entries.tradeskills.host == Tabs.host)
check("the one window is Tradeskills' own copy", Tabs.One() == SW)

print("1. off")
ns.db.oneWindow = nil
check("on unless unticked", SW.On())
ns.db.oneWindow = false
UI:Show()
check("off: the window opens by itself", UI.window:IsShown() and not Tabs:Hosted())
UI:Hide()

print("2. on")
SW.SetOn(true)
UI:Show()
local area = hub.frame and hub.frame.area
check("on: the one window opens", hub.frame and hub.frame:IsShown())
check("on Tradeskills", hub.current == hub.entries.tradeskills and ns.db.oneWindowPick == "tradeskills")
check("the window is in it", Tabs:Hosted() and UI.window:GetParent() == area and UI.window:IsShown())
check("without its own size grip", UI.sizeGrip == nil or not UI.sizeGrip:IsShown())

print("3. tabs")
UI:OpenSettings()
check("Settings in the same area", UI.activeTab == "settings" and UI.window:GetParent() == area)
UI:SelectTab("profit")
check("back on Profit, still in the one window", UI.activeTab == "profit" and hub.frame:IsShown()
    and Tabs:Hosted())

-- A window built for the first time hides itself before it is laid in
-- (a player's report, 2026-10-30: picking another addon on the rail once
-- turned the one window into that addon's own window).
local fresh = { GetParent = function() return UIParent end }
Tabs:Closed(fresh)
check("a window not yet laid in hiding keeps the one window", hub.frame:IsShown() and Tabs:Hosted())

-- Swapping to another addon on the rail hands Tradeskills' window back
-- without closing the one window.
local entered, left = 0, 0
SW:Join({ key = "butler", order = 5, name = "Butler", db = function() return {} end,
    host = { enter = function() entered = entered + 1 end, leave = function() left = left + 1 end } })
SW.Pick("butler")
check("swapping keeps the one window up", hub.frame:IsShown() and hub.current == hub.entries.butler)
check("the other addon moved in", entered == 1)
check("Tradeskills went home, hidden", not Tabs:Hosted() and UI.window:GetParent() == UIParent
    and not UI.window:IsShown())
SW.Pick("tradeskills")
check("back on Tradeskills in the same window", hub.frame:IsShown()
    and hub.current == hub.entries.tradeskills and Tabs:Hosted() and left == 1)
hub.entries.butler = nil

print("4. closing")
hub.frame:Hide()
check("closing it lets Tradeskills go", not Tabs:Hosted() and hub.current == nil)
check("the window is back on its own", UI.window:GetParent() == UIParent and not UI.window:IsShown())
check("with its grip", UI.sizeGrip == nil or UI.sizeGrip:IsShown())

print("5. the setting")
local other = {}
SW:Join({ key = "pets", order = 3, name = "Pets", db = function() return other end })
Tabs:SetOneWindow(false)
check("unticked in every save", ns.db.oneWindow == false and other.oneWindow == false)
UI:Show()
check("opens on its own again", not Tabs:Hosted() and UI.window:GetParent() == UIParent)
UI:Hide()
Tabs:SetOneWindow(true)
check("ticked again in every save", ns.db.oneWindow == true and other.oneWindow == true)

SW.SetOn(false)
_G.BlackthornesWindow = nil
for _, key in ipairs(GLOBALS) do _G[key] = saved[key] end

print(string.format("\n%d passed, %d failed", passed, failed))
assert(failed == 0, "one window checks failed")
