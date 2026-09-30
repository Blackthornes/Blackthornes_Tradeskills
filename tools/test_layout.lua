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

-- Moved over for the character window: the main window is measured against
-- where the panel really is, not the spot beside the auction window.
ns.UI = { window = Window(1400, 4, 600, 580) }
check("panel moved right onto the main window: gives way",
  PostPanel:DesiredHeight(AH, 1250), 1091 - (584 + PANEL_GAP))

ns.UI = { window = Window(1077, 4, 1060, 580) }
check("panel moved right past a narrow main window: still clears it",
  PostPanel:DesiredHeight(AH, 2140), AH_HEIGHT)

-- The character window, where the game puts it with the auction house open:
-- in the slot to the auction window's right, which is the panel's spot.
print("")

UIParent = { GetRight = function() return 2141 end }
local character = Window(857, 579, 384, 512)
CharacterFrame = character

local host, left, fits = PostPanel:Placement(AH)
check("character window open beside the auction house: dock to it",
  host == character, true)
check("and sit just past its right edge", left, 857 + 384 + PANEL_GAP)
check("which fits on a wide screen", fits, true)

character.shown = false
host, left, fits = PostPanel:Placement(AH)
check("character window closed: back beside the auction house",
  host == AH, true)
check("with no moved edge", left, nil)

-- Dragged off somewhere else, it is not in the way.
character.shown = true
CharacterFrame = Window(1500, 100, 384, 400)
host = PostPanel:Placement(AH)
check("character window dragged clear: panel stays put", host == AH, true)

-- Found through the game's panel slot too, whatever the window is.
CharacterFrame = nil
local spellbook = Window(857, 600, 540, 480)
GetUIPanel = function(key) if key == "right" then return spellbook end end
host = PostPanel:Placement(AH)
check("any window in the right-hand slot counts", host == spellbook, true)

-- A narrow screen: the panel steps aside rather than covering the paper doll.
GetUIPanel = nil
CharacterFrame = character
UIParent = { GetRight = function() return 1366 end }
host, left, fits = PostPanel:Placement(AH)
check("no room past the character window: step aside", fits, false)

UIParent, CharacterFrame = nil, nil

print("")
if failed > 0 then
  error(string.format("FAIL -- %d of %d layout checks wrong", failed, passed + failed))
end
print(string.format("PASS -- the sell list clears the main window and the character window (%d checks)", passed))
print("")
