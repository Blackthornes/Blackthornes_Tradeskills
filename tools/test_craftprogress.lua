-- The addon's own craft progress bar: shows while a craft casts, reads the
-- same cast as the game's bar, and gives the status line back afterwards.

local ns = { Theme = {} }
ns.NewModule = function(name) local m = {}; ns[name] = m; return m end

local now = 10
function GetTime() return now end

local casting = nil
function UnitCastingInfo(unit)
  if unit ~= "player" or not casting then return nil end
  return casting.name, casting.text, nil, casting.startMS, casting.endMS, true
end

local crafting = true
ns.CastBarOnTop = { IsCrafting = function() return crafting end }

local recasts = 0
C_TradeSkillUI = { GetRemainingRecasts = function() return recasts end }

local function Region()
  local r = { shown = true, text = "", width = 0 }
  function r:SetPoint() end
  function r:SetText(t) self.text = t end
  function r:SetWidth(w) self.width = w end
  function r:SetColorTexture() end
  function r:Show() self.shown = true end
  function r:Hide() self.shown = false end
  function r:IsShown() return self.shown end
  return r
end

local parent = Region()
function parent:IsVisible() return self.shown end

ns.Theme.Unpack = function() return 1, 1, 1 end
ns.Theme.CreateLabel = function() return Region() end
ns.Theme.CreatePanel = function(p)
  local f = Region()
  f.parent = p
  function f:GetParent() return self.parent end
  function f:SetSize(w) self.w = w end
  function f:GetWidth() return self.w end
  function f:CreateTexture() return Region() end
  return f
end

local driverScript
function CreateFrame() return { SetScript = function(_, _, fn) driverScript = fn end } end

local chunk = assert(loadfile(lfs_cwd .. "/UI/CraftProgress.lua"))
chunk("Blackthornes_TS", ns)
local Progress = ns.CraftProgress

local failures = 0
local function check(ok, what)
  if not ok then failures = failures + 1; print("FAIL " .. what) end
end

local status = Region()
local bar = Progress:Create(parent, { width = 202, height = 16, covers = status })
check(not bar:IsShown(), "bar starts hidden")

-- Nothing casting: bar stays hidden, status line stays.
driverScript()
check(not bar:IsShown() and status:IsShown(), "no cast, no bar")

-- A craft a quarter of the way through, three more to go.
casting = { name = "Light Leather", text = "", startMS = 9000, endMS = 13000 }
recasts = 3
driverScript()
check(bar:IsShown(), "bar shows during a craft")
check(not status:IsShown(), "status line hidden under the bar")
-- The count sits beside this craft's time and the whole run's: this craft
-- has 3s left, then three more of 4s each.
check(bar.label.text == "Light Leather", "label: " .. bar.label.text)
check(bar.timer.text == "3 more · 3.0s · 15s left", "timer: " .. bar.timer.text)

-- Nothing is cut off in a narrower bar: this craft's time goes first, then
-- the run's, then the name, and the count stays. The name has what the
-- right-hand text leaves it, 18 pixels of padding aside.
local function Measure(region) return #region.text * 6 end
local barWidth = 260
local barGetWidth = bar.GetWidth
bar.label.GetStringWidth = Measure
bar.timer.GetStringWidth = Measure
bar.GetWidth = function() return barWidth end

driverScript()
check(bar.label.text == "Light Leather", "a wide bar shows the name: " .. bar.label.text)
check(bar.timer.text == "3 more · 3.0s · 15s left", "and everything: " .. bar.timer.text)

barWidth = 220
driverScript()
check(bar.label.text == "Light Leather", "a narrower bar keeps the name: " .. bar.label.text)
check(bar.timer.text == "3 more · 15s left", "and the run's time, without this craft's: " .. bar.timer.text)

barWidth = 150
driverScript()
check(bar.label.text == "Light Leather", "narrower still keeps the name: " .. bar.label.text)
check(bar.timer.text == "3 more", "and the count alone: " .. bar.timer.text)

barWidth = 180
driverScript()
check(bar.label.text == "Light Leather", "between the two keeps the name: " .. bar.label.text)
check(bar.timer.text == "3 more", "and the count: " .. bar.timer.text)

barWidth = 120
driverScript()
check(bar.label.text == "", "a name with no room at all is left off: " .. bar.label.text)
check(bar.timer.text == "3 more · 15s left", "and the most that fits the bar stays: " .. bar.timer.text)

barWidth = 100
driverScript()
check(bar.label.text == "", "a tiny bar leaves the name off: " .. bar.label.text)
check(bar.timer.text == "3 more", "and keeps the count: " .. bar.timer.text)

barWidth = 260
driverScript()
check(bar.label.text == "Light Leather", "with room the name is back: " .. bar.label.text)
check(bar.timer.text == "3 more · 3.0s · 15s left", "and both times: " .. bar.timer.text)
bar.GetWidth, bar.timer.GetStringWidth, bar.label.GetStringWidth = barGetWidth, nil, nil
driverScript()
check(bar.fill.width == 50, "fill a quarter of 200, got " .. tostring(bar.fill.width))

-- A long run reads in minutes.
recasts = 30
driverScript()
check(bar.timer.text == "30 more · 3.0s · 2m 03s left", "long run: " .. bar.timer.text)
recasts = 3

-- How a run's time reads.
check(Progress.FormatTotal(45) == "45s", "45s: " .. Progress.FormatTotal(45))
check(Progress.FormatTotal(0.2) == "1s", "rounds up: " .. Progress.FormatTotal(0.2))
check(Progress.FormatTotal(80) == "1m 20s", "1m 20s: " .. Progress.FormatTotal(80))
check(Progress.FormatTotal(3700) == "1h 01m", "1h 01m: " .. Progress.FormatTotal(3700))

-- An ordinary spell is not a craft.
crafting = false
driverScript()
check(not bar:IsShown() and status:IsShown(), "ordinary cast hides the bar and gives the status back")
crafting = true

-- Last craft of a run: no count.
recasts = 0
now = 12
driverScript()
check(bar.label.text == "Light Leather", "last craft label: " .. bar.label.text)
check(bar.timer.text == "1.0s", "last craft shows the time alone: " .. bar.timer.text)
check(bar.fill.width == 150, "fill three quarters, got " .. tostring(bar.fill.width))

-- Run over.
casting = nil
driverScript()
check(not bar:IsShown() and status:IsShown(), "bar hides when the run ends")

-- A window that is closed is left alone, and a bar showing there is hidden.
casting = { name = "Light Leather", startMS = 11000, endMS = 13000 }
driverScript()
parent.shown = false
driverScript()
check(not bar:IsShown() and status:IsShown(), "closed window hides its bar")

if failures > 0 then error(failures .. " craft progress check(s) failed") end
print("craft progress: all checks passed")
