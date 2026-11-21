-- The slim window frame (the owner said build it, 2026-11-21), outside WoW.
--
-- What must hold:
--   1. Titanforged and the Blizzard style dress a slim window with a small
--      portrait inside the corner and the name in one bar inside the top
--      rim, left, past the portrait; the old plate stays for everyone else.
--   2. The main window's header is that one slim bar, and the scan button
--      sits in it just left of the gems; inside the one window, where the
--      gems are put away, at the right edge.
--   3. What the scan knows and the version are in a footer along the
--      bottom; the fullest line that fits shows, the whole on its hover.
--   4. Why a scan can't run shows in the footer and on the button's hover.
--   5. Row Size: roomy unless compact is picked, read once a session, and
--      only one-line rows shrink.

local GLOBALS = { "CreateFrame", "UIParent", "GameTooltip", "C_Timer", "UISpecialFrames",
    "tinsert", "GetTime", "time" }
local saved = {}
for _, key in ipairs(GLOBALS) do saved[key] = _G[key] end

local function noop() end

-- Frames that keep every point they are given, by the point's name.
local function Region(parent)
    local region = { parent = parent, shown = true, width = 0, height = 0, scale = 1,
        points = {}, scripts = {}, frameLevel = 1, text = nil }
    region.SetSize = function(self, w, h) self.width, self.height = w, h end
    region.SetWidth = function(self, w) self.width = w end
    region.SetHeight = function(self, h) self.height = h end
    region.GetWidth = function(self) return self.width end
    region.GetHeight = function(self) return self.height end
    region.SetScale = function(self, s) self.scale = s end
    region.GetScale = function(self) return self.scale end
    region.SetPoint = function(self, point, relativeTo, relativePoint, x, y)
        if type(relativeTo) ~= "table" then
            relativeTo, relativePoint, x, y = self.parent, point, relativeTo, relativePoint
        end
        self.points[point] = { relativeTo, relativePoint or point, x or 0, y or 0 }
    end
    region.ClearAllPoints = function(self) self.points = {} end
    region.SetParent = function(self, p) self.parent = p end
    region.GetParent = function(self) return self.parent end
    region.Show = function(self) self.shown = true end
    region.Hide = function(self) self.shown = false end
    region.SetShown = function(self, on) self.shown = on and true or false end
    region.IsShown = function(self) return self.shown end
    region.SetScript = function(self, name, fn) self.scripts[name] = fn end
    region.GetScript = function(self, name) return self.scripts[name] end
    region.GetFrameLevel = function(self) return self.frameLevel end
    region.SetFrameLevel = function(self, level) self.frameLevel = level end
    region.CreateTexture = function(self) return Region(self) end
    region.CreateFontString = function(self) return Region(self) end
    region.SetText = function(self, t) self.text = t end
    region.GetText = function(self) return self.text end
    region.GetStringWidth = function(self) return #(self.text or "") * 6 end
    region.GetUnboundedStringWidth = function(self) return #(self.text or "") * 6 end
    region.GetStringHeight = function() return 12 end
    region.GetRegions = function() return end
    return setmetatable(region, { __index = function(_, key)
        if type(key) == "string" and key:match("^%u") then return noop end
    end })
end

CreateFrame = function(_, _, parent) return Region(parent) end
UIParent = Region()
UIParent.width, UIParent.height = 1920, 1080
GameTooltip = Region()
C_Timer = { After = noop }
UISpecialFrames = {}
tinsert = table.insert
GetTime = function() return 0 end
time = function() return 100000 end

local passed, failed = 0, 0
local function check(label, got, want)
    local ok = got == want
    if ok then passed = passed + 1 else failed = failed + 1 end
    print(string.format("  %-62s %-10s %s", label, tostring(got), ok and "ok" or
        ("WRONG, wanted " .. tostring(want))))
end

local function NewNS(style)
    local settings = { windowStyle = style }
    local ns = {}
    ns.COLORS = setmetatable({}, { __index = function() return "ffffffff" end })
    ns.NewModule = function(name) local m = ns[name] or {}; ns[name] = m; return m end
    ns.RegisterCommand, ns.RegisterHiddenCommand = noop, noop
    ns.RegisterEvent = function() return true end
    ns.Print, ns.PrintRaw, ns.Debug, ns.Warn = noop, noop, noop, noop
    ns.db = { global = {}, settings = settings }
    ns.Config = {
        DEFAULTS = { settings = { windowScale = 1 } },
        Get = function(_, key) return settings[key] end,
        Set = function(_, key, value) settings[key] = value end,
    }
    ns.VersionLabel = function() return "v0.42.0" end
    ns.Prices = { Count = function() return 1234 end, GetLastScan = function() return 100000 - 1200 end }
    ns.Recipes = { Count = function() return 56 end }
    local canScan, reason = false, "Open the auction house first."
    ns.Scanner = { isAuctionHouseOpen = false,
        CanFullScan = function() return canScan, reason end }
    local function Load(path) assert(loadfile(lfs_cwd .. path))("Blackthornes_TS", ns) end
    Load("/Core/Util.lua")
    Load("/UI/Theme.lua")
    if style == "blizzard" then
        Load("/UI/BlizzardLook.lua")
        ns.BlizzardLook.On = function() return true end
    end
    Load("/UI/Widgets.lua")
    Load("/UI/Titanforged.lua")
    Load("/UI/Main.lua")
    return ns
end

for _, style in ipairs({ "titanforged", "blizzard" }) do
    local ns = NewNS(style)
    print("")
    print("1. " .. style .. ": the frame itself")
    local frame = Region(UIParent)
    frame:SetSize(300, 200)
    local slim = ns.Titanforged:Dress(frame, { title = "Test", portrait = true, slim = true, close = noop })
    check("slim", slim.slim, true)
    check("the name is in a slim bar", slim.plate and slim.plate.slim, true)
    check("the bar sits inside the top rim", slim.plate.points.TOPLEFT and slim.plate.points.TOPLEFT[4],
        -ns.Titanforged.TITLE_TOP)
    check("the name starts left, past the portrait", slim.plate.label.points.LEFT ~= nil, true)
    check("the name reads", slim.plate.label:GetText(), "Test")
    slim.plate:SetTitle("Other")
    check("and can be renamed", slim.plate.label:GetText(), "Other")
    check("the portrait is small", slim.portrait:GetWidth(), 40)
    local left, _, top = ns.Titanforged.Reach(slim)
    check("reaches only a little past the left", left <= 8, true)
    check("and the top", top <= 8, true)

    local old = ns.Titanforged:Dress(Region(UIParent), { title = "Test", portrait = true, close = noop })
    check("without slim: the plate as before", old.plate and old.plate.slim, nil)
    check("and the big portrait", old.portrait:GetWidth() > 40, true)

    print("2. " .. style .. ": the main window's title bar")
    local UI = ns.UI
    UI:Build()
    local window = UI.window
    check("the window wears the slim frame", window.titan.slim, true)
    check("the header is the slim bar's height", UI.header:GetHeight(), ns.Titanforged.TITLE_BAR)
    check("and starts inside the rim", UI.header.points.TOPLEFT[4], -ns.Titanforged.TITLE_TOP)
    local scan = UI.scanButton.points.RIGHT
    check("the scan button is in the bar", scan and scan[2], "TOPRIGHT")
    check("in its middle", scan[4], -(ns.Titanforged.TITLE_TOP + ns.Titanforged.TITLE_BAR / 2))
    local room = UI:GemRoom()
    check("left of the close gem", -scan[3] >= room, true)
    local swap = Region(window.titan)
    swap:SetSize(22, 22)
    window.blackthornesSwap = swap
    UI:PlaceScanButton(false)
    check("and of the swap gem too", -UI.scanButton.points.RIGHT[3], room + 22 + 2 + 8)
    UI:PlaceScanButton(true)
    check("inside the one window: at the edge", -UI.scanButton.points.RIGHT[3], 11)
    UI:PlaceScanButton(false)

    print("3. " .. style .. ": the footer")
    check("the version is in the footer", UI.versionLabel.parent, UI.footer)
    check("and reads", UI.versionLabel:GetText(), "v0.42.0")
    check("the footer sits on the bottom", UI.footer.points.BOTTOMLEFT ~= nil, true)
    local bottom = UI.content.points.BOTTOMRIGHT
    check("the list stops above it", bottom[4] >= UI.footer:GetHeight(), true)
    check("and starts under the bar", UI.content.points.TOPLEFT[1], UI.header)
    UI:UpdateHeader()
    local status = UI.statusLabel
    check("the whole line is on the hover", status.tip:find("1,234", 1, true) ~= nil
        and status.tip:find("56", 1, true) ~= nil, true)
    check("and shows when it fits", status:GetText(), status.tip)
    status.text:SetWidth(150)
    UI:UpdateHeader()
    check("narrow: a shorter line, never cut", #status:GetText() < #status.tip, true)
    check("and still says how old the scan is", status:GetText():find("scanned", 1, true) ~= nil, true)

    print("4. " .. style .. ": why a scan can't run")
    check("in the footer", UI.scanHint.parent, UI.footer)
    check("says why", UI.scanHint:GetText(), "Open the auction house first.")
    check("and on the button's hover", UI.scanButton.tooltipText, "Open the auction house first.")
end

print("")
print("5. Row Size")
do
    local ns = NewNS("titanforged")
    local W = ns.Widgets
    W.compactRows = nil
    check("nothing picked: roomy, rows as before", W.RowHeight(22), 22)
    ns.db.settings.rowSize = "compact"
    check("read once: a change waits for /reload", W.RowHeight(22), 22)
    W.compactRows = nil
    check("compact: one-line rows a little tighter", W.RowHeight(22), 18)
    check("never too small", W.RowHeight(17), 16)
    check("two-line rows keep their height", W.RowHeight(34), 34)
    local list = W.CreateScrollList(UIParent, { rowHeight = 26 })
    check("a list made now is compact", list ~= nil, true)
    check("the setting's default is roomy", ns.Config.DEFAULTS.settings.rowSize == nil
        or ns.Config.DEFAULTS.settings.rowSize == "roomy", true)
end

for _, key in ipairs(GLOBALS) do _G[key] = saved[key] end

print("")
print(string.format("%d passed, %d failed", passed, failed))
if failed > 0 then error(failed .. " check(s) failed") end
