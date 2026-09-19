-- Where the sell list ends up next to the auction house, measured without a
-- game client. The panel, Blizzard's auction window and the main window come
-- to more than the width of most screens, so the panel gives way: this checks
-- that it gives way only when it has to, and never past its floor.

local ns = {}
ns.NewModule = function(name) local m = {}; ns[name] = m; return m end
ns.Theme, ns.Widgets, ns.Util = {}, {}, {}

local PostPanel
do
  local realNew = ns.NewModule
  ns.NewModule = function(name) local m = realNew(name); PostPanel = m; return m end
  local chunk = assert(loadfile(lfs_cwd .. "/UI/PostPanel.lua"))
  chunk("Blackthornes_TS", ns)
end

-- Numbers taken off the screenshot that started this: a 2141-wide UIParent,
-- Blizzard's auction window down the left, the 1060x580 main window parked in
-- the bottom right corner.
local AH = {
  GetTop = function() return 1091 end,
  GetBottom = function() return 551 end,
  GetRight = function() return 851 end,
}

local AH_HEIGHT = 1091 - 551
local PANEL_GAP = 6

local function Window(left, bottom, width, height)
  return {
    shown = true,
    IsShown = function(self) return self.shown end,
    GetLeft = function() return left end,
    GetRight = function() return left + width end,
    GetBottom = function() return bottom end,
    GetTop = function() return bottom + height end,
  }
end

local passed, failed = 0, 0

local function check(label, got, want)
  local ok = got == want
  if ok then passed = passed + 1 else failed = failed + 1 end
  print(string.format("  %-52s %-8s %s", label, tostring(got), ok and "ok" or
    ("WRONG, wanted " .. tostring(want))))
end

print("")

ns.UI = { window = nil }
check("no main window: the auction window's full height",
  PostPanel:DesiredHeight(AH), AH_HEIGHT)

ns.UI = { window = Window(1077, 4, 1060, 580) }
check("main window in the corner: stops above it",
  PostPanel:DesiredHeight(AH), 1091 - (584 + PANEL_GAP))

check("and that is shorter than the auction window",
  PostPanel:DesiredHeight(AH) < AH_HEIGHT, true)

ns.UI.window.shown = false
check("main window closed: full height again",
  PostPanel:DesiredHeight(AH), AH_HEIGHT)

-- Clear to the right of the panel, whatever its width is today.
ns.UI = { window = Window(1400, 4, 600, 580) }
check("main window past the panel's right edge: no giving way",
  PostPanel:DesiredHeight(AH), AH_HEIGHT)

ns.UI = { window = Window(1077, 4, 1060, 500) }
check("main window too short to reach the panel: no giving way",
  PostPanel:DesiredHeight(AH), AH_HEIGHT)

ns.UI = { window = Window(100, 4, 1060, 580) }
check("main window off to the left but still under the panel: gives way",
  PostPanel:DesiredHeight(AH), 1091 - (584 + PANEL_GAP))

-- A main window dragged up over the panel leaves no room at all. The panel
-- stops shrinking rather than vanishing, and the click-to-raise handles it.
ns.UI = { window = Window(1077, 620, 1060, 580) }
check("main window over the panel: floors instead of vanishing",
  PostPanel:DesiredHeight(AH), 200)

ns.UI = { window = nil }
check("auction window not laid out yet: no answer rather than a wrong one",
  PostPanel:DesiredHeight({
    GetTop = function() return nil end,
    GetBottom = function() return nil end,
    GetRight = function() return nil end,
  }), nil)

print("")
if failed > 0 then
  error(string.format("FAIL -- %d of %d layout checks wrong", failed, passed + failed))
end
print(string.format("PASS -- the sell list clears the main window (%d checks)", passed))
print("")
