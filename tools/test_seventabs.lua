-- Seven tabs in place of eleven (the owner said build it, 2026-11-26, from
-- the mockup ts-improve-9).
--
-- What must hold:
--   1. The usual row is Today, Make, Sell, Learn, Prices, Characters,
--      Settings.
--   2. A tab picked by its old key (a /bts command, another addon's call,
--      the saved last tab, a moved tab) lights its group and shows the
--      group's own row with that tab picked, under which the tab sits.
--   3. A group remembers the tab last picked in it.
--   4. A tab with no group shows no group row and takes the whole room.
--   5. At the auction house the row stays flat: no group row, and the tab
--      takes the whole room again.

local GLOBALS = { "CreateFrame", "UIParent", "GameTooltip", "GetCursorPosition", "C_Timer",
    "UISpecialFrames", "tinsert", "GetTime", "time", "BlackthornesWindow" }
local saved = {}
for _, key in ipairs(GLOBALS) do saved[key] = _G[key] end

local function noop() end

local passed, failed = 0, 0
local function check(label, got, want)
    local ok = got == want
    if ok then passed = passed + 1 else failed = failed + 1 end
    print(string.format("  %-64s %-10s %s", label, tostring(got), ok and "ok" or
        ("WRONG, wanted " .. tostring(want))))
end

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
        self.points[#self.points + 1] = { point, relativeTo, relativePoint, x or 0, y or 0 }
    end
    region.ClearAllPoints = function(self) self.points = {} end
    region.GetPoint = function(self, index)
        local p = self.points[index or 1]
        if not p then return nil end
        return p[1], p[2], p[3], p[4], p[5]
    end
    region.Show = function(self) self.shown = true end
    region.Hide = function(self) self.shown = false end
    region.SetShown = function(self, on) self.shown = on and true or false end
    region.IsShown = function(self) return self.shown end
    region.SetScript = function(self, name, fn) self.scripts[name] = fn end
    region.GetScript = function(self, name) return self.scripts[name] end
    region.HookScript = function(self, name, fn) self.scripts[name] = fn end
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
UIParent.width, UIParent.height = 1280, 720
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
ns.Scanner = { isAuctionHouseOpen = false, CanFullScan = function() return true end, StartFullScan = noop }
ns.Prices = { Count = function() return 0 end, GetLastScan = noop }
ns.Recipes = { Count = function() return 0 end }
ns.VersionLabel = function() return "v1.4.0" end
ns.Titanforged = {
    Dress = function(_, frame)
        local trim = Region(frame)
        trim.closeButton = Region(trim)
        frame.titan = trim
        return trim
    end,
    Reach = function() return 0, 0, 0, 0 end,
    Opened = noop,
}
ns.FoldWindow = {
    Add = function(_, frame)
        local button = Region(frame.titan)
        frame.blackthornesFold = { button = button }
        return button
    end,
    Unfold = noop,
}

local function Load(path) assert(loadfile(lfs_cwd .. path))("Blackthornes_TS", ns) end
_G.BlackthornesWindow = nil
Load("/Core/Util.lua")
Load("/UI/Theme.lua")
Load("/UI/Widgets.lua")
Load("/UI/SharedWindow.lua")
Load("/UI/Main.lua")

local UI = ns.UI
-- The tabs as each file registers them.
local TABS = { today = 0, profit = 1, queue = 2, gather = 3, disenchanting = 5, levelup = 6,
    deals = 7, prices = 8, sales = 10, characters = 11, settings = 12 }
for key, order in pairs(TABS) do
    UI:RegisterTab({ key = key, text = key, order = order, build = noop })
end
UI:Show()

local function Offset(key)
    local _, _, _, _, y = UI.tabs[key].container:GetPoint(1)
    return y
end

print("1. the usual row")
do
    local keys = {}
    for _, entry in ipairs(UI:MainEntries()) do keys[#keys + 1] = entry.key end
    check("seven tabs, in the mockup's order", table.concat(keys, ","),
        "today,make,sell,learn,prices,characters,settings")
end

print("2. old keys land in their group")
do
    UI:SelectTab("disenchanting")
    check("the tab shows", UI.tabs.disenchanting.container:IsShown(), true)
    check("its group is lit on the row", UI.tabStrip.selected, "make")
    check("the group's row shows", UI.groupStrips.make:IsShown(), true)
    check("with the tab picked", UI.groupStrips.make.selected, "disenchanting")
    check("the other groups' rows stay hidden", UI.groupStrips.sell:IsShown(), false)
    check("the tab sits under the group's row", Offset("disenchanting"), -34)

    UI:SelectTab("enchanting")   -- folded into Profit long ago
    check("a moved tab still lands", UI.activeTab, "profit")
    check("in its group", UI.tabStrip.selected, "make")
    UI:SelectTab("stats")
    check("Stats lands on Prices", UI.activeTab, "prices")
end

print("3. a group remembers its tab")
do
    UI:SelectTab("gather")
    UI:SelectTab("queue")
    UI:SelectTab("learn")
    check("Learn opens on the tab last picked there", UI.activeTab, "gather")
    UI:SelectTab("make")
    check("Make opens on Queue", UI.activeTab, "queue")
end

print("4. a tab with no group")
do
    UI:SelectTab("characters")
    check("lights itself", UI.tabStrip.selected, "characters")
    check("no group row shows", UI.groupStrips.make:IsShown() or UI.groupStrips.sell:IsShown()
        or UI.groupStrips.learn:IsShown(), false)
    check("and takes the whole room", Offset("characters"), -1)
end

print("5. at the auction house")
do
    ns.TSTabs.atAuction = true
    UI:SelectTab("queue")
    check("the flat row picks the tab", UI.ahTabStrip.selected, "queue")
    check("no group row shows there", UI.groupStrips.make:IsShown(), false)
    check("and the tab takes the whole room", Offset("queue"), -1)
    ns.TSTabs.atAuction = false
    UI:SelectTab("queue")
    check("back on the usual row the group row returns", UI.groupStrips.make:IsShown(), true)
    check("and makes room again", Offset("queue"), -34)
end

for _, key in ipairs(GLOBALS) do _G[key] = saved[key] end

print(string.format("\n%d passed, %d failed", passed, failed))
if failed > 0 then error(failed .. " check(s) failed") end
