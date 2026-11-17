-- Crafting with "Craft Cost and Profit:" ticked stuttered (a player's report,
-- 2026-11-17): Tradeskills took 18 to 25% of the game's time while crafting,
-- worst when a craft finished, and under 2% with the box off.
--
-- What each step did, and what it must do now (the smooth play rule):
--   1. A finished craft makes the game redraw the recipe list several times
--      in one go. Each redraw refreshed every row there and then. Now a burst
--      of redraws is one refresh on the next frame.
--   2. Every refresh asked each text region on each row where it sat, which
--      makes the game lay the row out there and then. Now an unchanged row
--      reads no region's edges.
--   3. Every refresh spelled each row's profit again. Now once per figures.
--   4. A price arriving made every row work its figures out in one frame.
--      Now a few a frame; the rest keep theirs a moment.
--   5. The card under the reagents was re-anchored twice a second. Now only
--      when what it sits on changes.

local ns = {}
ns.NewModule = function(name) local m = {}; ns[name] = m; return m end
ns.L = setmetatable({ Format = string.format }, { __index = function(_, key) return key end })
ns.COLORS = { profit = "ffPROFIT", loss = "ffLOSS", muted = "ffMUTED" }

local spelled = 0
ns.Util = {
  FormatMoney = function(copper) spelled = spelled + 1; return ("<%d>"):format(math.floor(copper + 0.5)) end,
  IsBoundOnPickup = function() return false end,
  GetVendorSellPrice = function() return nil end,
}
ns.Theme = {}

local saved = { C_Timer = _G.C_Timer, GetTime = _G.GetTime, C_Item = _G.C_Item, hooksecurefunc = _G.hooksecurefunc }

local now = 100
_G.GetTime = function() return now end
local timers = {}
_G.C_Timer = {
  After = function(_, fn) timers[#timers + 1] = fn end,
  NewTicker = function() return { Cancel = function() end } end,
}
local function NextFrame()
  now = now + 0.016
  local due = timers
  timers = {}
  for _, fn in ipairs(due) do fn() end
end
_G.C_Item = {
  GetItemQualityByID = function() return 1 end,
  GetItemInfo = function() return nil end,
  GetItemInfoInstant = function() return nil end,
}

-- Twenty recipes, each made from one mat, all for sale.
local RECIPES, worked = {}, 0
for id = 1, 20 do
  RECIPES[id] = { recipeID = id, name = "Recipe " .. id, outputItemID = 1000 + id,
    reagents = { { itemID = 10, quantity = 2 } } }
end
ns.Recipes = {
  GetAny = function(_, id) worked = worked + 1; return RECIPES[id] end,
  GetAll = function() return RECIPES end,
  Count = function() return 20 end,
}
ns.Cost = {
  GetReagentUnitCost = function() return 100, "auction" end,
  CostOfMany = function(_, _, qty, unit) return unit * qty end,
}
ns.Profit = {
  ChoosePostPrice = function() return 1000 end,
  NetFromListing = function(_, _, price) return price end,
}
ns.Prices = { changes = 0 }
ns.settings = { craftProfitInProfessionWindow = true }
ns.Config = { changes = 0, Get = function(_, key) return ns.settings[key] end }

local function Load(path)
  local chunk = assert(loadfile(lfs_cwd .. "/" .. path))
  chunk("Blackthornes_TS", ns)
end
Load("Logic/CraftProfit.lua")
Load("UI/RecipeValue.lua")
Load("UI/CraftProfitCard.lua")
local CP, RV, Card = ns.CraftProfit, ns.RecipeValue, ns.CraftProfitCard

local failures = 0
local function check(label, got, want)
  if got ~= want then
    failures = failures + 1
    print(("FAIL %s: got %s, want %s"):format(label, tostring(got), tostring(want)))
  end
end

--------------------------------------------------------------------------------
-- 1. A burst of list redraws is one refresh
--------------------------------------------------------------------------------

do
  local refreshes = 0
  local realRefresh = RV.Refresh
  RV.Refresh = function(self, ...) refreshes = refreshes + 1; return { rows = 0 } end

  local list = { Update = function() end }
  _G.hooksecurefunc = function(target, method, after)
    local before = target[method]
    target[method] = function(...) before(...); after(...) end
  end
  check("the list's redraw is followed", RV:HookContainer(list), true)

  for _ = 1, 6 do list:Update() end    -- one finished craft
  check("no refresh inside the redraws", refreshes, 0)
  NextFrame()
  check("six redraws, one refresh", refreshes, 1)
  NextFrame()
  check("and nothing after", refreshes, 1)

  RV.Refresh = realRefresh
end

--------------------------------------------------------------------------------
-- 2 and 3. An unchanged row reads no region's edges and spells nothing
--------------------------------------------------------------------------------

local edges = 0
local function Region(text)
  return {
    text = text,
    GetText = function(self) return self.text end,
    GetStringWidth = function(self) return #(self.text or "") * 6 end,
    GetUnboundedStringWidth = function(self) return #(self.text or "") * 6 end,
    GetJustifyH = function() return "LEFT" end,
    GetLeft = function() edges = edges + 1; return 20 end,
    GetRight = function() edges = edges + 1; return 300 end,
    GetWidth = function() edges = edges + 1; return 280 end,
    IsShown = function() return true end,
    SetWidth = function() end,
  }
end
local function Label()
  local label = Region("")
  label.shown = false
  label.SetText = function(self, t) self.text = t end
  label.Show = function(self) self.shown = true end
  label.Hide = function(self) self.shown = false end
  label.IsShown = function(self) return self.shown end
  label.ClearAllPoints = function() end
  label.SetPoint = function() end
  label.SetJustifyH = function() end
  return label
end
local function Row(id)
  local row = { recipeInfo = { recipeID = id } }
  row.Text = Region("Recipe " .. id .. " [3]")
  row.GetLeft = function() return 10 end
  row.GetRight = function() return 310 end
  row.IsShown = function() return true end
  row.GetRegions = function(self) return self.Text end
  row.CreateFontString = function() return Label() end
  row.HookScript = function() end
  return row
end

do
  local rows = {}
  for id = 1, 15 do rows[id] = Row(id) end
  RV.FindRows = function() return rows, "test" end

  RV:Refresh()
  check("rows get their profit", rows[1].Text and RV.lastReport.valued, 15)

  edges, spelled = 0, 0
  NextFrame()
  RV:Refresh()
  check("unchanged rows read no region's edges", edges, 0)
  check("unchanged rows spell no money", spelled, 0)

  -- A craft lowers a count: only that row is placed again.
  rows[4].Text.text = "Recipe 4 [2]"
  edges = 0
  NextFrame()
  RV:Refresh()
  check("a changed count is measured again", edges > 0, true)
end

--------------------------------------------------------------------------------
-- 4. A price arriving redoes a few figures a frame, never all at once
--------------------------------------------------------------------------------

do
  CP:Forget()
  for id = 1, 20 do CP:For(id) end
  check("first look works every recipe out", worked >= 20, true)

  local before = CP:For(20)
  ns.Prices.changes = ns.Prices.changes + 1
  NextFrame()
  worked = 0
  for id = 1, 20 do CP:For(id) end
  check("a frame redoes at most a few", worked <= (CP.PER_FRAME or 0), true)
  check("the rest keep their figures meanwhile", CP:For(19) ~= nil, true)

  for _ = 1, 10 do
    NextFrame()
    for id = 1, 20 do CP:For(id) end
  end
  worked = 0
  NextFrame()
  for id = 1, 20 do CP:For(id) end
  check("all caught up after a few frames", worked, 0)
  check("caught up with the new price", CP:For(20) ~= before, true)

  -- A recipe never seen is worked out at once, budget or not.
  RECIPES[21] = { recipeID = 21, outputItemID = 1021, reagents = { { itemID = 10, quantity = 1 } } }
  ns.Prices.changes = ns.Prices.changes + 1
  NextFrame()
  for id = 1, 20 do CP:For(id) end
  check("a new row still gets figures", CP:For(21) ~= nil, true)
end

--------------------------------------------------------------------------------
-- 5. The card is anchored once, not twice a second
--------------------------------------------------------------------------------

do
  local anchors, levels = 0, 0
  local reagents = {
    GetFrameLevel = function() return 5 end,
    GetFrameStrata = function() return "MEDIUM" end,
    GetTop = function() return 400 end, GetBottom = function() return 300 end,
    GetLeft = function() return 100 end, GetRight = function() return 400 end,
    GetEffectiveScale = function() return 1 end,
  }
  Card.FindAnchor = function() return { frame = reagents, under = true, game = reagents } end
  Card.frame = {
    GetWidth = function(self) return self.width or 0 end,
    SetWidth = function(self, w) self.width = w end,
    ClearAllPoints = function() anchors = anchors + 1 end,
    SetPoint = function() end,
    SetFrameStrata = function() end,
    SetFrameLevel = function() levels = levels + 1 end,
  }
  for _ = 1, 10 do Card:Place() end
  check("ten looks, anchored once", anchors, 1)
  check("ten looks, level set once", levels, 1)

  reagents.GetFrameLevel = function() return 9 end
  Card:Place()
  check("placed again when the reagents move up", anchors, 2)
end

_G.C_Timer, _G.GetTime, _G.C_Item, _G.hooksecurefunc = saved.C_Timer, saved.GetTime, saved.C_Item, saved.hooksecurefunc

if failures > 0 then error(("test_craftstutter: %d failure(s)"):format(failures)) end
print("test_craftstutter: ok")
