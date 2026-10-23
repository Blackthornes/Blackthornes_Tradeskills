-- Road to 300's buttons grow to fit their words (UI/RoadView.lua).
--
-- "Show the Way" ended in "..." in game (2026-10-23): the fit looked for
-- the button's GetFontString, which the house button does not have, so it
-- never grew. What must hold:
--   1. A button with its words in `label` grows to the words plus room.
--   2. A button already wide enough keeps its width.

local lfs_cwd = os.getenv("PWD") or "."
local failures = 0
local function check(name, got, want)
  if got == want then print("  ok   " .. name)
  else failures = failures + 1 print(string.format("  FAIL %s: got %s, want %s", name, tostring(got), tostring(want))) end
end

local ns = {}
ns.NewModule = function(name) local m = {} ns[name] = m return m end
local PER_LETTER = 7
ns.Theme = {
  -- A fixed-width label reports only what it draws, as the game's does.
  TextWidth = function(label) return math.min(#label.text * PER_LETTER, label.room or 1e9) end,
  MeasureText = function(_, text) return #text * PER_LETTER end,
}
ns.Widgets = {}
assert(loadfile(lfs_cwd .. "/UI/RoadView.lua"))("Blackthornes_TS", ns)

local function Button(text, width)
  local button = { width = width }
  button.label = { text = text, room = width - 8 }
  function button.label:GetText() return self.text end
  function button:GetWidth() return self.width end
  function button:SetWidth(w) self.width = w end
  return button
end

print("\nroad to 300 buttons fit their words")
local way = Button("Show the Way", 80)
ns.RoadView.Fit(way)
check("Show the Way grows to its words", way.width, #"Show the Way" * PER_LETTER + 20)
local queue = Button("Queue", 80)
ns.RoadView.Fit(queue)
check("a wide enough button keeps its width", queue.width, 80)

print("")
if failures > 0 then error(string.format("%d road button check(s) failed", failures)) end
print("  all road button checks passed")
print("")
