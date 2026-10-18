-- Off, Shift or Always for each tooltip line (asked 2026-10-18).
--
--   1. Nobody's settings change: a line on today reads as Always, one off as
--      Off, the sales lines' old tick box reads as Shift, and nothing is
--      written for a player who never touches the boxes.
--   2. Shift writes the line's own Config key; the line is held back with
--      Shift up and shown with Shift down, and the hint goes on once.
--   3. Off and Always go back and forth through the line's own setting.
--   4. The real hooks: an item tooltip and an enchant tooltip hold their
--      lines back for Shift, and give them back on the redraw with it down.

local failures = 0
local function check(label, got, want)
  if got ~= want then
    failures = failures + 1
    print(string.format("  FAIL  %-52s got %s, wanted %s", label, tostring(got), tostring(want)))
  else
    print(string.format("  ok    %-52s %s", label, tostring(got)))
  end
end

-- The test run shares one Lua state, so the shared table and Shift start fresh.
local savedShared, savedShiftDown = _G.BlackthornesTooltipShift, IsShiftKeyDown
_G.BlackthornesTooltipShift = nil
local shift = false
IsShiftKeyDown = function() return shift end

-- Tradeskills' defaults for these lines, as Config lays them in.
local settings = {
  showValueOnItemTooltips = true, tooltipSalesShift = false, tooltipTrend = true,
  showRecipeValueOnTooltips = true, tooltipEnchantCosts = true,
  tooltipValueShift = false, tooltipTrendShift = false,
  tooltipRecipeShift = false, tooltipEnchantShift = false,
}
local writes = 0

local ns = {}
ns.NewModule = function(name) local m = ns[name] or {}; ns[name] = m; return m end
ns.Config = {
  Get = function(_, key) return settings[key] end,
  Set = function(_, key, value) writes = writes + 1; settings[key] = value end,
}
ns.COLORS = setmetatable({}, { __index = function() return "ffffffff" end })
ns.Print, ns.PrintRaw, ns.RegisterCommand = function() end, function() end, function() end
ns.Util = {
  FormatMoney = function(copper) return ("<%d>"):format(copper) end,
  FormatAgeAgo = function(seconds) return ("%dh ago"):format(seconds / 3600) end,
  HasFunction = function(path) return path == "C_Item.GetItemInfo" end,
}
ns.Prices = {
  GetValue = function() return 2300 end,
  IsStale = function() return false end,
  Get = function() return { quantity = 12, seen = 1 } end,
  GetAge = function() return 3600 end,
  GetTrend = function() return 0.2 end,
  TrendDays = function() return 7 end,
  TrendText = function(trend) return trend and "up 20%" or nil, "profit" end,
  GetUnitsSoldPerDay = function() return 5 end,
}
ns.Demand = {
  Get = function() return { level = "high", source = "market" } end,
  TooltipText = function() return "High (40%)" end,
  Label = function() return "High" end,
  Color = function() return "profit" end,
}
C_Item = { GetItemInfo = function(id) return "item", nil, 1, nil, nil, nil, nil, nil, nil, nil, nil, 7, nil, 0 end }

assert(loadfile(lfs_cwd .. "/UI/TooltipShift.lua"))("Blackthornes_TS", ns)
assert(loadfile(lfs_cwd .. "/UI/ItemTooltip.lua"))("Blackthornes_TS", ns)
local Shift, ItemTooltip = ns.TooltipShift, ns.ItemTooltip
ItemTooltip.fired, ItemTooltip.counts, ItemTooltip.seen = {}, {}, 0

local function IsOn(setting) return settings[setting] ~= false end

--------------------------------------------------------------------------------
print("\nnobody's settings change")
--------------------------------------------------------------------------------

check("value is Always", Shift:Mode(IsOn("showValueOnItemTooltips"), "value"), Shift.ALWAYS)
check("sales are Always", Shift:Mode(true, "sales"), Shift.ALWAYS)
check("trend is Always", Shift:Mode(IsOn("tooltipTrend"), "trend"), Shift.ALWAYS)
settings.showRecipeValueOnTooltips = false
check("a line turned off is Off", Shift:Mode(IsOn("showRecipeValueOnTooltips"), "recipe"), Shift.OFF)
settings.showRecipeValueOnTooltips = true
settings.tooltipSalesShift = true
check("the old sales tick box is Shift", Shift:Mode(true, "sales"), Shift.SHIFT)
settings.tooltipSalesShift = false
check("every line shows", Shift:Shows("value") and Shift:Shows("trend") and Shift:Shows("enchant"), true)
check("no line on Shift", Shift:AnyShift(), false)
check("nothing written", writes, 0)

--------------------------------------------------------------------------------
print("\nShift")
--------------------------------------------------------------------------------

local function SetOn(setting) return function(on) ns.Config:Set(setting, on) end end

Shift:Apply(Shift.SHIFT, "trend", IsOn("tooltipTrend"), SetOn("tooltipTrend"))
check("Shift is kept in its own key", settings.tooltipTrendShift, true)
check("the line stays on", settings.tooltipTrend, true)
check("held back with Shift up", Shift:Shows("trend"), false)
shift = true
check("shown with Shift down", Shift:Shows("trend"), true)
shift = false

local hints = 0
local tip = { lines = {} }
function tip:AddLine(text) self.lines[#self.lines + 1] = text; if text == "Hold Shift for more." then hints = hints + 1 end end
function tip:HookScript(_, fn) self.cleared = fn end
function tip:IsShown() return true end
function tip:Show() end
Shift:Held(tip)
Shift:Held(tip)
check("the hint goes on once", hints, 1)
tip.cleared(tip)
Shift:Held(tip)
check("and again once cleared", hints, 2)

-- The sales lines: Shift is the old key itself, and they have no Off.
Shift:Apply(Shift.SHIFT, "sales", true, nil)
check("sales Shift is tooltipSalesShift", settings.tooltipSalesShift, true)
Shift:Apply(Shift.ALWAYS, "sales", true, nil)
check("Always clears it", settings.tooltipSalesShift, false)

--------------------------------------------------------------------------------
print("\nOff and Always")
--------------------------------------------------------------------------------

Shift:Apply(Shift.OFF, "trend", IsOn("tooltipTrend"), SetOn("tooltipTrend"))
check("Off turns its own setting off", settings.tooltipTrend, false)
check("and reads Off", Shift:Mode(IsOn("tooltipTrend"), "trend"), Shift.OFF)
Shift:Apply(Shift.ALWAYS, "trend", IsOn("tooltipTrend"), SetOn("tooltipTrend"))
check("Always turns it back on", settings.tooltipTrend, true)
check("not on Shift", settings.tooltipTrendShift, false)
check("and reads Always", Shift:Mode(IsOn("tooltipTrend"), "trend"), Shift.ALWAYS)

--------------------------------------------------------------------------------
print("\nan item tooltip")
--------------------------------------------------------------------------------

local function Tooltip(itemID)
  local t = { lines = {}, hint = 0 }
  function t:AddDoubleLine(left, right) self.lines[#self.lines + 1] = { left, right } end
  function t:AddLine(text) if text == "Hold Shift for more." then self.hint = self.hint + 1 end end
  function t:NumLines() return 3 + #self.lines + self.hint end
  function t:Show() end
  function t:IsShown() return true end
  function t:HookScript(_, fn) self.cleared = fn end
  function t:GetItem() return "item", ("|cffffffff|Hitem:%d:0|h[x]|h|r"):format(itemID) end
  -- What the client does on a redraw (RefreshData): clear, then the hooks run.
  function t:Redraw()
    self.lines, self.hint = {}, 0
    ItemTooltip.Forget(self)
    if self.cleared then self.cleared(self) end
    return ItemTooltip:Decorate(self)
  end
  return t
end

local function Has(t, label)
  for _, line in ipairs(t.lines) do if line[1] == label then return true end end
  return false
end

local item = Tooltip(2589)
ItemTooltip:Decorate(item)
check("value shows", Has(item, "Auction value"), true)
check("trend shows", Has(item, "Trend (7 days)"), true)
check("no hint", item.hint, 0)

Shift:Apply(Shift.SHIFT, "trend", true, SetOn("tooltipTrend"))
item:Redraw()
check("trend held back with Shift up", Has(item, "Trend (7 days)"), false)
check("the value still shows", Has(item, "Auction value"), true)
check("one hint", item.hint, 1)
ItemTooltip:Decorate(item)
check("a second hook adds no second hint", item.hint, 1)
shift = true
item:Redraw()
check("Shift down: the trend comes back", Has(item, "Trend (7 days)"), true)
check("and no hint", item.hint, 0)
shift = false

Shift:Apply(Shift.SHIFT, "value", true, SetOn("showValueOnItemTooltips"))
item:Redraw()
check("every value line held back", #item.lines, 0)
check("just the hint", item.hint, 1)
shift = true
item:Redraw()
check("Shift down: the value comes back", Has(item, "Auction value"), true)
shift = false
Shift:Apply(Shift.ALWAYS, "value", true, SetOn("showValueOnItemTooltips"))
Shift:Apply(Shift.ALWAYS, "trend", true, SetOn("tooltipTrend"))

-- The Shift key itself redraws the tooltip, only while a line is on Shift.
local refreshed = 0
local savedGameTooltip = _G.GameTooltip
_G.GameTooltip = { IsShown = function() return true end, RefreshData = function() refreshed = refreshed + 1 end }
Shift.shared.OnModifier("LSHIFT")
check("no line on Shift: no redraw", refreshed, 0)
Shift:Apply(Shift.SHIFT, "recipe", true, SetOn("showRecipeValueOnTooltips"))
Shift.shared.OnModifier("LSHIFT")
Shift.shared.OnModifier("LCTRL")
check("a line on Shift: Shift redraws, Ctrl doesn't", refreshed, 1)
Shift:Apply(Shift.ALWAYS, "recipe", true, SetOn("showRecipeValueOnTooltips"))
_G.GameTooltip = savedGameTooltip

--------------------------------------------------------------------------------
print("\nan enchant tooltip")
--------------------------------------------------------------------------------

assert(loadfile(lfs_cwd .. "/UI/EnchantTooltip.lua"))("Blackthornes_TS", ns)
local EnchantTooltip = ns.EnchantTooltip
EnchantTooltip.cache, EnchantTooltip.fired = {}, {}
local built = 0
EnchantTooltip.LinesFor = function() built = built + 1; return { { "Materials", "<500>" } } end

local spell = Tooltip(0)
EnchantTooltip:Decorate(spell, nil, 7857)
check("the costs show", Has(spell, "Materials"), true)
Shift:Apply(Shift.SHIFT, "enchant", true, SetOn("tooltipEnchantCosts"))
spell.lines, spell.hint = {}, 0
check("held back with Shift up", EnchantTooltip:Decorate(spell, nil, 7857), "held")
check("no lines, one hint", #spell.lines .. "/" .. spell.hint, "0/1")
shift = true
-- The redraw clears the tooltip, the hint with it.
spell.lines, spell.hint = {}, 0
if spell.cleared then spell.cleared(spell) end
EnchantTooltip:Decorate(spell, nil, 7857)
check("Shift down: the costs come back", Has(spell, "Materials"), true)
check("from the kept lines, not built again", built, 1)
shift = false

_G.BlackthornesTooltipShift, IsShiftKeyDown = savedShared, savedShiftDown
if failures > 0 then error(("%d check(s) failed"):format(failures)) end
print("\ntest_tooltipshift: ok")
