-- Logic/Welcome.lua and UI/Welcome.lua outside WoW.
--
-- The Welcome card (the owner said build it, 2026-10-20). What must hold:
--   1. It shows once per character, the first time the window opens, and
--      only once a profession it can lay a road for is known.
--   2. Not Now and Show My Road both mark it seen; it never comes back by
--      itself, but Settings can open it again.
--   3. Every profession is ticked the first time; Show My Road keeps the
--      ones ticked, in order, as roadPicks and opens Road to 300 on the
--      first.
--   4. It changes no setting.

local GLOBALS = { "CreateFrame", "UIParent", "UISpecialFrames", "tinsert", "BlackthornesTSCharDB" }
local saved = {}
for _, key in ipairs(GLOBALS) do saved[key] = _G[key] end

local failures = 0
local function check(label, got, want)
  if got == want then
    print("  ok   " .. label)
  else
    failures = failures + 1
    print(string.format("  FAIL %s: got %s, want %s", label, tostring(got), tostring(want)))
  end
end

local function Frame()
  local frame = { shown = true, height = 0, scripts = {} }
  function frame:SetScript(name, fn) self.scripts[name] = fn end
  function frame:Hide() self.shown = false end
  function frame:Show() self.shown = true end
  function frame:IsShown() return self.shown end
  function frame:SetHeight(h) self.height = h end
  function frame:GetHeight() return self.height end
  function frame:SetSize(_, h) self.height = h end
  return setmetatable(frame, { __index = function() return function() end end })
end

local function Label()
  local label = { text = "" }
  function label:SetText(text) self.text = text end
  function label:GetStringHeight() return 14 end
  return setmetatable(label, { __index = function() return function() end end })
end

CreateFrame = function() return Frame() end
UIParent = Frame()
UISpecialFrames = {}
tinsert = table.insert
BlackthornesTSCharDB = nil

local ns = {}
ns.NewModule = function(name) local m = {} ns[name] = m return m end

local labels = {}
local buttons = {}
local boxes = {}
ns.Theme = {
  Fill = function() end,
  AddGameOutline = function() end,
  CreateLabel = function() local l = Label() labels[#labels + 1] = l return l end,
}
ns.Widgets = {
  CreateButton = function(_, text, onClick)
    local b = Frame()
    b.text, b.onClick = text, onClick
    buttons[text] = b
    return b
  end,
  CreateCheckbox = function()
    local box = Frame()
    box.checked = false
    function box:SetChecked(on) self.checked = on and true or false end
    function box:GetChecked() return self.checked end
    function box:SetLabel(text) self.label = text end
    boxes[#boxes + 1] = box
    return box
  end,
}

local professions = {}
ns.RoadPlan = { Professions = function() return professions end }

local settings = {}
local settingsWritten = 0
ns.Config = {
  Get = function(_, key) return settings[key] end,
  Set = function(_, key, value) settingsWritten = settingsWritten + 1 settings[key] = value end,
}

local roadShown = "none"
ns.LevelUpTab = { ShowRoad = function(line) roadShown = line end }

ns.charDb = {}

assert(loadfile(lfs_cwd .. "/Logic/Welcome.lua"))("Blackthornes_TS", ns)
assert(loadfile(lfs_cwd .. "/UI/Welcome.lua"))("Blackthornes_TS", ns)
local Welcome, WelcomeUI = ns.Welcome, ns.WelcomeUI

print("\nonly once a profession has a road")
check("no professions, not due", Welcome:Due(), false)
check("nothing shown", WelcomeUI:MaybeShow(), false)
check("nothing marked", ns.charDb.welcomeSeen, nil)

professions = {
  { line = 164, name = "Blacksmithing", skill = 62 },
  { line = 197, name = "Tailoring", skill = 10 },
}
check("with professions, due", Welcome:Due(), true)

print("\nthe first open shows it, every profession ticked")
check("shown", WelcomeUI:MaybeShow(), true)
check("the frame is up", WelcomeUI.frame:IsShown(), true)
check("one box a profession", #boxes, 2)
check("each with its skill", boxes[1].label, "Blacksmithing  62")
check("all ticked the first time", boxes[1]:GetChecked() and boxes[2]:GetChecked(), true)
local found = false
for _, label in ipairs(labels) do
  if label.text == "You can change this any time in Settings." then found = true end
end
check("says it can be changed in Settings", found, true)
check("Not Now button", buttons["Not Now"] ~= nil, true)
check("Show My Road button", buttons["Show My Road"] ~= nil, true)

print("\nNot Now")
WelcomeUI:NotNow()
check("hidden", WelcomeUI.frame:IsShown(), false)
check("seen", ns.charDb.welcomeSeen, true)
check("no picks saved", ns.charDb.roadPicks, nil)
check("never due again", Welcome:Due(), false)
check("the next open shows nothing", WelcomeUI:MaybeShow(), false)

print("\nShow My Road from Settings")
WelcomeUI:Show()
check("Settings opens it anyway", WelcomeUI.frame:IsShown(), true)
boxes[1]:SetChecked(false)
WelcomeUI:ShowMyRoad()
check("hidden", WelcomeUI.frame:IsShown(), false)
check("the ticked kept", #Welcome:Picks(), 1)
check("in order", Welcome:Picks()[1], 197)
check("Road to 300 opens on the first pick", roadShown, 197)

print("\nthe picks stay ticked next time")
WelcomeUI:Show()
check("an unpicked one unticked", boxes[1]:GetChecked(), false)
check("a picked one ticked", boxes[2]:GetChecked(), true)
WelcomeUI:Hide()

print("\nSetPicks")
Welcome:SetPicks({ 164, 164, "x", 197 })
check("doubles and junk dropped", #Welcome:Picks(), 2)
check("order kept", Welcome:Picks()[1], 164)

print("\nno setting changed")
check("Config never written", settingsWritten, 0)

print("\na fresh character")
ns.charDb = nil
BlackthornesTSCharDB = {}
check("due again for a new character", Welcome:Due(), true)
Welcome:MarkSeen()
check("kept in the character's own save", BlackthornesTSCharDB.welcomeSeen, true)

for _, key in ipairs(GLOBALS) do _G[key] = saved[key] end

print("")
if failures > 0 then error(string.format("%d welcome check(s) failed", failures)) end
print("  all welcome checks passed")
print("")
