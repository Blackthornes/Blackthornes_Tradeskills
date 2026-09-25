-- The Queue tab's "Open <profession>" button, measured without a game client.
--
-- What matters here: the right spell is cast for the right recipe (Mining is
-- opened by Smelting, gathering skills have nothing to open), the secure
-- button is never touched in combat, and a click is only ever reported as a
-- success once a window has really opened.

local ns = {}
local printed, warned = {}, {}
local events = {}

ns.NewModule = function(name) local m = {}; ns[name] = m; return m end
ns.Print = function(msg) printed[#printed + 1] = msg end
ns.Warn = function(msg) warned[#warned + 1] = msg end
ns.RegisterEvent = function(_, event, fn) events[event] = fn end
ns.RegisterCommand = function(name, _, fn) ns["cmd_" .. name] = fn end

local RECIPES = {
  [1] = { recipeID = 1, name = "Bolt of Linen Cloth", skillLineID = 2948 },
  [2] = { recipeID = 2, name = "Smelt Copper",        skillLineID = 186 },
  [3] = { recipeID = 3, name = "Mystery",             skillLineID = 99999 },
  [4] = { recipeID = 4, name = "Skinning thing",      skillLineID = 393 },
  [5] = { recipeID = 5, name = "No line" },
  [6] = { recipeID = 6, name = "Classic sub-line",    skillLineID = 2827 },
}
ns.Recipes = { GetAny = function(_, id) return RECIPES[id] end }
ns.Crafting = { isTradeSkillOpen = false }

local openSet = nil
ns.CraftPanel = { GetOpenRecipeIDs = function() return openSet end }

-- The client
local inCombat = false
function InCombatLockdown() return inCombat end
function GetCVarBool() return false end
function GetTime() return 100 end

local timers = {}
C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end }

C_TradeSkillUI = {
  GetProfessionInfoBySkillLineID = function(id)
    if id == 2948 then return { professionName = "Tailoring" } end
    if id == 2827 then return { professionName = "Classic Tailoring", parentProfessionName = "Tailoring" } end
    return nil
  end,
}
C_Spell = { GetSpellName = function(id) if id == 2656 then return "Smelting" end end }

local function NewFrame()
  local f = { shown = false, attrs = {}, scripts = {}, hooks = {} }
  function f:Show() if inCombat then error("protected: Show in combat") end; self.shown = true end
  function f:Hide() if inCombat then error("protected: Hide in combat") end; self.shown = false end
  function f:IsShown() return self.shown end
  function f:IsVisible() return self.shown end
  function f:SetAttribute(k, v) if inCombat then error("protected") end; self.attrs[k] = v end
  function f:GetAttribute(k) return self.attrs[k] end
  function f:SetScript(k, fn) self.scripts[k] = fn end
  function f:GetScript(k) return self.scripts[k] end
  function f:HookScript(k, fn) self.hooks[k] = fn end
  function f:RegisterForClicks(d) self.clicks = d end
  f.strata, f.level = "MEDIUM", 3
  function f:SetFrameStrata(v) self.strata = v end
  function f:GetFrameStrata() return self.strata end
  function f:SetFrameLevel(v) self.level = v end
  function f:GetFrameLevel() return self.level end
  function f:ClearAllPoints() end
  function f:SetPoint(...) self.point = { ... } end
  function f:SetSize(w, h) self.w, self.h = w, h end
  function f:GetLeft() return 10 end
  function f:GetBottom() return 20 end
  function f:GetWidth() return 220 end
  function f:GetHeight() return 26 end
  function f:GetEffectiveScale() return 1 end
  return f
end

UIParent = NewFrame()
local created = {}
function CreateFrame(kind, name, parent, template)
  local f = NewFrame()
  f.kind, f.name, f.parent, f.template = kind, name, parent, template
  created[#created + 1] = f
  return f
end

local chunk = assert(loadfile(lfs_cwd .. "/UI/ProfessionOpener.lua"))
chunk("Blackthornes_TS", ns)
local Opener = ns.ProfessionOpener
Opener:OnEnable()

local function check(cond, msg) if not cond then error(msg, 2) end end

-- Which profession ------------------------------------------------------------

local p = Opener:ProfessionFor(1)
check(p and p.name == "Tailoring" and p.spell == "Tailoring", "tailoring recipe should cast Tailoring")

p = Opener:ProfessionFor(2)
check(p and p.name == "Mining" and p.spell == "Smelting", "mining recipe should cast Smelting, got " .. tostring(p and p.spell))

p = Opener:ProfessionFor(6)
check(p and p.name == "Tailoring", "a sub-line should use its parent profession's name")

check(Opener:ProfessionFor(3) == nil, "an unknown skill line has nothing to open")
check(Opener:ProfessionFor(4) == nil, "skinning has no window")
check(Opener:ProfessionFor(5) == nil, "no skill line, no guess")

-- Is the right window open ----------------------------------------------------

check(Opener:WindowShowsRecipe(1) == false, "closed window shows nothing")
ns.Crafting.isTradeSkillOpen = true
openSet = nil
check(Opener:WindowShowsRecipe(1) == true, "open window the client will not describe gets the benefit of the doubt")
openSet = { [2] = true }
check(Opener:WindowShowsRecipe(1) == false, "smelting window open does not make tailoring")
check(Opener:WindowShowsRecipe(2) == true, "smelting window makes smelting")
ns.Crafting.isTradeSkillOpen = false

-- Arming ----------------------------------------------------------------------

local craftButton = NewFrame()
craftButton.shown = true

check(Opener:Arm(craftButton, Opener:ProfessionFor(1), 1), "arm out of combat")
local overlay = Opener.overlay
check(overlay.template == "SecureActionButtonTemplate", "overlay must be a secure action button")
check(overlay.parent == UIParent, "overlay must not be parented to the addon window (it would protect it)")
check(overlay.attrs.type == "spell" and overlay.attrs.spell == "Tailoring", "overlay casts Tailoring")
check(overlay.clicks == "AnyUp", "one click direction only, or the second cast closes the window")
check(overlay.shown, "overlay shows over a visible button")
check(overlay.point and overlay.point[4] == 10 and overlay.point[5] == 20, "overlay placed on the craft button")
check(Opener:IsArmed(), "IsArmed")

-- Our window is top-level: clicking it raises its level. The secure button
-- must follow, or it sits under the craft button and the click misses it
-- (the first in-game try did exactly this).
craftButton.strata, craftButton.level = "HIGH", 40
craftButton.hooks.OnUpdate(craftButton)
check(overlay.strata == "HIGH" and overlay.level > 40,
  "overlay must stay above a raised craft button, got " .. overlay.strata .. " " .. overlay.level)

-- Moving to a mining recipe re-targets the same button.
Opener:Arm(craftButton, Opener:ProfessionFor(2), 2)
check(overlay.attrs.spell == "Smelting", "re-arm changes the spell")
check(#created == 1, "one secure button, reused")

-- Combat: nothing protected is touched, and the wish is remembered.
events.PLAYER_REGEN_DISABLED()
check(not overlay.shown, "hidden as combat starts")
inCombat = true
check(Opener:Arm(craftButton, Opener:ProfessionFor(1), 1) == false, "arm refuses in combat")
check(Opener:Disarm() == false, "disarm refuses in combat")
check(overlay.attrs.spell == "Smelting", "spell untouched in combat")
craftButton.hooks.OnHide(craftButton) -- must not error in combat
inCombat = false

check(Opener:Disarm(), "disarm out of combat")
check(not overlay.shown and not Opener:IsArmed(), "disarmed overlay is hidden")

-- Reporting -------------------------------------------------------------------

Opener:Arm(craftButton, Opener:ProfessionFor(1), 1)
overlay.scripts.PostClick(overlay)
check(#printed == 0 and #warned == 0, "a click alone reports nothing yet")
events.TRADE_SKILL_SHOW()
check(printed[1] and printed[1]:find("opened your Tailoring window"), "window opening is reported")
timers[#timers]()
check(#warned == 0, "the timeout after a success stays quiet")

overlay.scripts.PostClick(overlay)
timers[#timers]()
check(warned[1] and warned[1]:find("no profession window opened"), "a click that opened nothing is reported as a miss")

-- A click that reaches the craft button out of combat is a miss, not combat.
local w = #warned
Opener:MissedClick()
check(#warned == w + 1 and warned[#warned]:find("missed"), "a missed click out of combat says so")
inCombat = true
Opener:MissedClick()
check(printed[#printed]:find("combat"), "a missed click in combat names combat")
inCombat = false

-- A window opening with no click pending is not claimed as ours.
local before = #printed
events.TRADE_SKILL_SHOW()
check(#printed == before, "unrelated window opening is not reported")

print("profession opener: all checks passed")
