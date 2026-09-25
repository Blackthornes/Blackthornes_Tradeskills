-- The game's cast bar is lifted above the addon's windows while a craft casts,
-- and goes back to its own layer when the craft run ends.

local ns = {}
local events, printed = {}, {}
ns.NewModule = function(name)
  local m = {}
  function m:RegisterEvent(event, fn) events[event] = fn end
  ns[name] = m
  return m
end
ns.RegisterCommand = function(name, _, fn) ns["cmd_" .. name] = fn end
ns.Print = function(msg) printed[#printed + 1] = msg end
ns.Warn = ns.Print
ns.Crafting = { isTradeSkillOpen = false }

local timers = {}
C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end }
local function RunTimers() local t = timers; timers = {}; for _, fn in ipairs(t) do fn() end end

local casting = nil   -- nil, "craft", "craft-noflag" or "other"
function UnitCastingInfo(unit)
  if unit ~= "player" or not casting then return nil end
  return "Cast", nil, nil, 0, 1, casting == "craft"
end

local bar = { strata = "MEDIUM" }
function bar:SetFrameStrata(s) self.strata = s end
function bar:GetFrameStrata() return self.strata end
PlayerCastingBarFrame = bar

local chunk = assert(loadfile(lfs_cwd .. "/UI/CastBarOnTop.lua"))
chunk("Blackthornes_TS", ns)
local CastBar = ns.CastBarOnTop

local function Fire(event, unit) events[event](CastBar, event, unit) end

-- A craft lifts the bar.
casting = "craft"
Fire("UNIT_SPELLCAST_START", "player")
assert(bar.strata == "TOOLTIP", "craft should lift the bar, got " .. bar.strata)

-- Between two crafts of a run the bar stays up.
Fire("UNIT_SPELLCAST_STOP", "player")
casting = "craft"
Fire("UNIT_SPELLCAST_START", "player")
RunTimers()
assert(bar.strata == "TOOLTIP", "bar dropped between two crafts")

-- End of the run puts it back where it was.
casting = nil
Fire("UNIT_SPELLCAST_STOP", "player")
RunTimers()
assert(bar.strata == "MEDIUM", "bar not restored, got " .. bar.strata)

-- Another unit's cast, or an ordinary spell, leaves it alone.
casting = "other"
Fire("UNIT_SPELLCAST_START", "target")
assert(bar.strata == "MEDIUM", "target cast moved the bar")
Fire("UNIT_SPELLCAST_START", "player")
assert(bar.strata == "MEDIUM", "ordinary spell lifted the bar")

-- A client that leaves isTradeSkill empty: profession window open counts.
ns.Crafting.isTradeSkillOpen = true
casting = "craft-noflag"
Fire("UNIT_SPELLCAST_START", "player")
assert(bar.strata == "TOOLTIP", "cast with profession window open should lift the bar")
casting = nil
Fire("UNIT_SPELLCAST_INTERRUPTED", "player")
RunTimers()
assert(bar.strata == "MEDIUM", "interrupted craft should restore the bar")

-- The diagnostic reports the bar's current layer.
ns.cmd_castbar()
assert(printed[1]:find("PlayerCastingBarFrame: layer MEDIUM"), printed[1])

print("test_castbar: all checks passed")
