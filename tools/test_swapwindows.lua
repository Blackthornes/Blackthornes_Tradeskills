-- The swap gem on Tradeskills' window and the one window (UI/SharedWindow.lua
-- AddSwap and Swap, TSTabs' tab, show and hide; the owner said build it,
-- 2026-11-19).
--
-- What must hold:
--   1. Tradeskills' window carries a join gem; the one window a split gem.
--   2. Split from the one window on Profit: the one window closes and
--      Tradeskills opens on its own on Profit, with its rim.
--   3. Join from the own window on Settings: the one window opens on
--      Tradeskills, still on Settings; Butler's own window closes.
--   4. Split at the auction house on its tab: the drawer goes back beside
--      the auction house and the own window stays shut.

local GLOBALS = { "ProfessionsFrame", "MailFrame", "CreateFrame", "UIParent", "GameTooltip", "GetCursorPosition", "C_Timer",
    "UISpecialFrames", "tinsert", "GetTime", "time", "AuctionHouseFrame" }
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

-- The house frame, as UI/Titanforged.lua dresses a window: a trim with its
-- close gem, and the fold gem left of it (UI/FoldWindow.lua).
ns.Titanforged = {
    Dress = function(_, frame)
        local trim = Region(frame)
        trim.closeButton = Region(trim)
        trim.closeButton:SetSize(26, 26)
        frame.titan = trim
        return trim
    end,
    Reach = function() return 0, 0, 0, 0 end,
    Opened = noop,
}
ns.FoldWindow = {
    Add = function(_, frame)
        local button = Region(frame.titan)
        button:SetSize(22, 22)
        frame.blackthornesFold = { button = button }
        return button
    end,
    Unfold = noop,
}

_G.BlackthornesWindow = nil
Load("/Core/Util.lua")
Load("/UI/Theme.lua")
Load("/UI/Widgets.lua")
Load("/UI/SharedWindow.lua")
Load("/UI/Main.lua")

local UI, Tabs, SW = ns.UI, ns.TSTabs, ns.SharedWindow
local panel = { into = 0, outOf = 0, attach = 0 }
ns.PostPanel = {
    Reflow = noop,
    IntoOne = function(_, container) panel.into = panel.into + 1; panel.container = container end,
    OutOfOne = function() panel.outOf = panel.outOf + 1 end,
    Attach = function() panel.attach = panel.attach + 1 end,
}
for index, key in ipairs({ "profit", "queue", "gather", "disenchanting", "levelup", "deals",
        "prices", "sales", "characters" }) do
    UI:RegisterTab({ key = key, text = key, order = index, build = noop })
end
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

-- Butler, with its own window open.
local butlerOwn, butlerDb = Region(), {}
SW:Join({ key = "butler", order = 5, name = "Butler", db = function() return butlerDb end,
    host = { enter = noop, leave = noop, hide = function() butlerOwn:Hide() end } })

print("1. the gems")
SW.SetOn(true)
UI:Show()
UI:SelectTab("profit")
local oneGem = rawget(hub.frame, "blackthornesSwap")
check("the one window has the split gem", oneGem and rawget(oneGem, "join") == false)
local ownGem = rawget(UI.window, "blackthornesSwap")
check("Tradeskills' window has the join gem", ownGem and rawget(ownGem, "join") == true
    and rawget(ownGem, "swapKey") == "tradeskills")
check("on the window's trim, so it hides inside the one window", ownGem and ownGem.parent == UI.window.titan
    and not UI.window.titan:IsShown())

print("2. split")
oneGem.scripts.OnClick(oneGem)
check("the choice is off in every save", not SW.On() and ns.db.oneWindow == false and butlerDb.oneWindow == false)
check("the one window closed", not hub.frame:IsShown())
check("Tradeskills opens on its own", not Tabs:Hosted() and UI.window:IsShown()
    and UI.window:GetParent() == UIParent)
check("on the same tab", UI.activeTab == "profit")
check("with its rim and gems", UI.window.titan:IsShown())

print("3. join")
UI:OpenSettings()
butlerOwn:Show()
ownGem.scripts.OnClick(ownGem)
check("the choice is on in every save", SW.On() and ns.db.oneWindow == true and butlerDb.oneWindow == true)
check("the one window opens on Tradeskills", hub.frame:IsShown() and hub.current == hub.entries.tradeskills
    and Tabs:Hosted() and UI.window:GetParent() == hub.frame.area)
check("still on Settings", UI.activeTab == "settings")
check("Butler's own window closed", not butlerOwn:IsShown())

print("4. split at the auction house")
UI:SelectTab("queue")
_G.AuctionHouseFrame = Region()
_G.AuctionHouseFrame.GetRight = function() return 600 end
_G.AuctionHouseFrame.GetTop = function() return 650 end
hub.place = "auction"
Tabs:AtAuctionHouse()
check("on the Auction House tab, docked", SW.Docked() and UI.activeTab == "auctionhouse")
local outBefore = panel.outOf
oneGem.scripts.OnClick(oneGem)
check("the choice is off", not SW.On())
check("the drawer goes back beside the auction house", panel.outOf == outBefore + 1 and not Tabs.atAuction)
check("the own window stays shut", not UI.window:IsShown())
SW.Left("auction")
_G.AuctionHouseFrame = nil

SW.SetOn(false)
_G.BlackthornesWindow = nil
for _, key in ipairs(GLOBALS) do _G[key] = saved[key] end

print(string.format("\n%d passed, %d failed", passed, failed))
assert(failed == 0, "swap gem checks failed")
