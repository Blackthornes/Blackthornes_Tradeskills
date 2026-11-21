-- Tradeskills in the game's Options, AddOns list (the owner, 2026-11-21, UI
-- pass: keys and Options line), outside WoW. Like the other four addons, a
-- small line there with a button that opens Tradeskills' Settings tab.
--
-- What must hold:
--   1. At login the line is added to the game's AddOns list, named
--      Blackthornes Tradeskills, once.
--   2. Its button opens the window on the Settings tab; a second press with
--      Settings already up leaves it open.
--   3. With only the older options call, that one is used.
--   4. With neither, or one that raises, login goes on as before.

local GLOBALS = { "CreateFrame", "UIParent", "C_Timer", "Minimap", "GetTime", "time",
    "Settings", "InterfaceOptions_AddCategory" }
local saved = {}
for _, key in ipairs(GLOBALS) do saved[key] = _G[key] end

local function noop() end
local function NewFrame()
    return setmetatable({}, { __index = function(_, k)
        if type(k) == "string" and k:match("^%u") then return noop end
    end })
end
CreateFrame = function() return NewFrame() end
UIParent = NewFrame()
Minimap = nil
GetTime = function() return 0 end
time = function() return 100000 end
C_Timer = { After = noop, NewTicker = function() return { Cancel = noop } end }

local ns = {}
ns.COLORS = setmetatable({}, { __index = function() return "ffffffff" end })
ns.NewModule = function(name) local m = {}; ns[name] = m; return m end
ns.RegisterCommand = noop
ns.RegisterEvent = function() return true end
ns.Print, ns.PrintRaw, ns.Debug, ns.Warn = noop, noop, noop, noop
ns.Config = { Get = noop, Set = noop }
ns.db = {}
ns.Scanner = { isAuctionHouseOpen = false }
ns.PostPanel = { Refresh = noop, Place = noop, Hide = noop }
ns.Crafting = {}

local texts, buttons = {}, {}
ns.Theme = {
    CreateLabel = function()
        local label = NewFrame()
        label.SetText = function(_, text) texts[#texts + 1] = text end
        return label
    end,
}
ns.Widgets = {
    CreateButton = function(_, text, onClick)
        local button = NewFrame()
        buttons[#buttons + 1] = { text = text, onClick = onClick }
        return button
    end,
}

assert(loadfile(lfs_cwd .. "/Core/Util.lua"))("Blackthornes_TS", ns)
assert(loadfile(lfs_cwd .. "/UI/Main.lua"))("Blackthornes_TS", ns)

local UI = ns.UI
for _, name in ipairs({ "Build", "BuildMinimapButton", "HookAltClickSearch", "UpdateHeader",
    "RestorePosition", "RefreshActiveTab", "RepositionMinimapButton", "UpdatePostButton" }) do
    UI[name] = noop
end
local opened = 0
UI.OpenSettings = function(self)
    opened = opened + 1
    self.window = { IsShown = function() return true end }
    self.activeTab = "settings"
end

local passed, failed = 0, 0
local function check(label, got, want)
    local ok = got == want
    if ok then passed = passed + 1 else failed = failed + 1 end
    print(string.format("  %-58s %-6s %s", label, tostring(got), ok and "ok" or
        ("WRONG, wanted " .. tostring(want))))
end

-- 1. The game's own list.
local made, added = {}, {}
Settings = {
    RegisterCanvasLayoutCategory = function(panel, name)
        local category = { panel = panel, name = name }
        made[#made + 1] = category
        return category
    end,
    RegisterAddOnCategory = function(category) added[#added + 1] = category end,
}
local older = 0
InterfaceOptions_AddCategory = function() older = older + 1 end

print("")
print("in the game's AddOns list")
UI:OnEnable()
check("one line is added", #added, 1)
check("named Blackthornes Tradeskills", added[1] and added[1].name, "Blackthornes Tradeskills")
check("the panel carries the name too", added[1] and added[1].panel.name, "Blackthornes Tradeskills")
check("the older call is left alone", older, 0)
check("the button reads as in the other addons", buttons[1] and buttons[1].text, "Open Tradeskills settings")
check("the line says where the settings are", texts[2], "Tradeskills' settings have a window of their own.")
UI:RegisterGameOptions()
check("asked again, nothing is added twice", #added, 1)

-- 2. The button.
print("")
print("the button")
buttons[1].onClick()
check("it opens the Settings tab", opened, 1)
buttons[1].onClick()
check("Settings already up: it stays open", opened, 1)
UI.window = { IsShown = function() return false end }
buttons[1].onClick()
check("window shut: it opens again", opened, 2)

-- 3. Only the older call.
print("")
print("an older client")
UI.optionsPanel = nil
Settings = nil
UI:RegisterGameOptions()
check("the older call is used", older, 1)

-- 4. Neither, or one that raises.
print("")
print("no options list")
UI.optionsPanel = nil
InterfaceOptions_AddCategory = nil
check("nothing to join: no error", (pcall(UI.RegisterGameOptions, UI)), true)
UI.optionsPanel = nil
Settings = { RegisterCanvasLayoutCategory = function() error("no") end, RegisterAddOnCategory = noop }
check("the call raises: login goes on", (pcall(UI.OnEnable, UI)), true)

for _, key in ipairs(GLOBALS) do _G[key] = saved[key] end

print("")
if failed > 0 then
    error(string.format("%d check(s) failed", failed))
end
print("all checks passed")
