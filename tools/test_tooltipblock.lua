-- One tidy block for every Blackthornes line on an item tooltip (2026-11-21).
--
--   1. Lines come out in the block's order (price, source, advice, holders)
--      whatever order the addons signed up in, under one blank row with the
--      gold line on it, with no blank rows between addons.
--   2. Two-part lines go on as a yellow name and a white answer; a line on
--      its own keeps its wrap.
--   3. "Hold Shift for more." goes on once, last, and only the hint when
--      every line was held back.
--   4. A second call for the same showing adds nothing; a clear lets the
--      next showing have the block again, with the gold line hidden between.
--   5. A part that raises, or a tooltip whose item can't be read, costs its
--      lines and never a Lua error.
--   6. The newest copy's writer wins whatever order the copies load in.
--   7. Lines shown only because Shift is held (`shift = true`) go after
--      every other line, under a second gold line, so nothing above them
--      moves when Shift goes down (2026-11-26).

local failures = 0
local function check(label, got, want)
  if got ~= want then
    failures = failures + 1
    print(string.format("  FAIL  %-52s got %s, wanted %s", label, tostring(got), tostring(want)))
  else
    print(string.format("  ok    %-52s %s", label, tostring(got)))
  end
end

local savedBlock, savedShift = _G.BlackthornesTooltipBlock, _G.BlackthornesTooltipShift
_G.BlackthornesTooltipBlock = nil
_G.BlackthornesTooltipShift = { hinted = setmetatable({}, { __mode = "k" }) }

-- A fake tooltip: lines as written, a clear script, its own textures.
local function FakeTooltip(name)
  local tip = { lines = {}, scripts = {}, textures = {}, shown = true, item = "id:2589" }
  function tip:GetName() return name end
  function tip:NumLines() return #self.lines end
  function tip:AddLine(text, r, g, b, wrap)
    self.lines[#self.lines + 1] = { left = text, lr = r, lg = g, lb = b, wrap = wrap }
    _G[name .. "TextLeft" .. #self.lines] = { line = #self.lines }
  end
  function tip:AddDoubleLine(left, right, lr, lg, lb, rr, rg, rb)
    self.lines[#self.lines + 1] = { left = left, right = right, lr = lr, lg = lg, lb = lb, rr = rr, rg = rg, rb = rb }
    _G[name .. "TextLeft" .. #self.lines] = { line = #self.lines }
  end
  function tip:HookScript(script, fn) self.scripts[script] = fn end
  function tip:IsShown() return self.shown end
  function tip:Show() self.showCalls = (self.showCalls or 0) + 1 end
  function tip:GetItem() return "Linen Cloth", self.item end
  function tip:CreateTexture()
    local tex = { visible = false }
    function tex:ClearAllPoints() self.points = {} end
    function tex:SetColorTexture(r, g, b, a) self.color = { r, g, b, a } end
    function tex:SetHeight(h) self.height = h end
    function tex:SetPoint(point, rel) self.points[#self.points + 1] = { point, rel } end
    function tex:Show() self.visible = true end
    function tex:Hide() self.visible = false end
    self.textures[#self.textures + 1] = tex
    return tex
  end
  function tip:Clear()
    self.lines = {}
    if self.scripts.OnTooltipCleared then self.scripts.OnTooltipCleared(self) end
  end
  -- The game's own lines come first.
  tip:AddLine("Linen Cloth", 1, 1, 1)
  tip:AddLine("Max Stack: 20", 1, 1, 1)
  return tip
end

local function Load(name)
  local ns = {}
  assert(loadfile(lfs_cwd .. "/UI/TooltipBlock.lua"))(name, ns)
  return ns.TooltipBlock
end

local Block = Load("Blackthornes_TS")

-- Signed up out of order, as addons load by name.
local butlerHeld = false
Block:Provide("Butler:holders", "holders", 1, function()
  return { { "You Have:", "150 (bags)" } }
end)
Block:Provide("Butler:advice", "advice", 2, function()
  return { { "Butler Says:", "Sell, 12s each" }, { "With Thread.", nil, leftColor = { 0.7, 0.7, 0.7 }, wrap = true } },
    butlerHeld
end)
Block:Provide("Butler:price", "price", 2, function()
  return { { "Vendor Pays:", "1s each" } }
end)
Block:Provide("Equipment:source", "source", 2, function()
  return { { "Drops From:", "Edwin VanCleef, The Deadmines" } }
end)
Block:Provide("Farmer:source", "source", 1, function()
  return { { "Farm At:", "Defias Pillager (14-15), Westfall, 12%" } }
end)
Block:Provide("Tradeskills:price", "price", 1, function()
  return { { "Auction Value:", "2s 30c" }, { "Lowest Posting:", "2s 10c" } }
end)

--------------------------------------------------------------------------------
print("\nthe block's order")
--------------------------------------------------------------------------------

local tip = FakeTooltip("FakeTip")
check("adds the block", Block.Write(tip, { id = 2589 }), "added")
local want = { "Linen Cloth", "Max Stack: 20", " ", "Auction Value:", "Lowest Posting:", "Vendor Pays:",
  "Farm At:", "Drops From:", "Butler Says:", "With Thread.", "You Have:" }
check("line count", #tip.lines, #want)
for i, left in ipairs(want) do check("line " .. i, tip.lines[i] and tip.lines[i].left, left) end
check("no blank row after the first", (function()
  for i = 4, #tip.lines do if tip.lines[i].left == " " then return false end end
  return true
end)(), true)

--------------------------------------------------------------------------------
print("\nthe gold line and the colors")
--------------------------------------------------------------------------------

local rule = tip.textures[1]
check("one texture made", #tip.textures, 1)
check("gold line shown", rule.visible, true)
check("gold line 1 px", rule.height, 1)
check("gold line sits on the blank row", rule.points[1][2].line, 3)
check("name is yellow", tip.lines[4].lg, 0.82)
check("answer is white", tip.lines[4].rg, 1)
check("answer text", tip.lines[4].right, "2s 30c")
check("line on its own keeps its wrap", tip.lines[10].wrap, true)
check("line on its own keeps its grey", tip.lines[10].lr, 0.7)
check("tooltip resized", tip.showCalls, 1)

--------------------------------------------------------------------------------
print("\nonce a showing")
--------------------------------------------------------------------------------

check("second call adds nothing", Block.Write(tip, { id = 2589 }), "duplicate")
check("still the same lines", #tip.lines, #want)
tip:Clear()
check("clear hides the gold line", rule.visible, false)
tip:AddLine("Linen Cloth", 1, 1, 1)
check("next showing gets it again", Block.Write(tip, { id = 2589 }), "added")
check("same texture used again", #tip.textures, 1)
check("gold line back", rule.visible, true)

--------------------------------------------------------------------------------
print("\nHold Shift for more.")
--------------------------------------------------------------------------------

butlerHeld = true
tip:Clear()
tip:AddLine("Linen Cloth", 1, 1, 1)
Block.Write(tip, { id = 2589 })
check("hint is last", tip.lines[#tip.lines].left, "Hold Shift for more.")
local hints = 0
for _, line in ipairs(tip.lines) do if line.left == "Hold Shift for more." then hints = hints + 1 end end
check("hint once", hints, 1)
check("Shift board told", _G.BlackthornesTooltipShift.hinted[tip], true)

-- Every line held: only the hint, no gold line.
local held = Load("Blackthornes_Held")
_G.BlackthornesTooltipBlock = nil
held = Load("Blackthornes_Held")
held:Provide("Only:price", "price", 1, function() return {}, true end)
local tip2 = FakeTooltip("FakeTip2")
check("only the hint", held.Write(tip2, { id = 1 }), "held")
check("hint line", tip2.lines[3] and tip2.lines[3].left, "Hold Shift for more.")
check("no blank row", #tip2.lines, 3)
check("no gold line", #tip2.textures, 0)

--------------------------------------------------------------------------------
print("\nShift lines open at the bottom")
--------------------------------------------------------------------------------

_G.BlackthornesTooltipBlock = nil
local low = Load("Blackthornes_Low")
low:Provide("Tradeskills:price", "price", 1, function()
  return { { "Auction Value:", "3g" }, { "Sold a Day:", "6", shift = true }, { "Costs Now:", "2g" } }
end)
low:Provide("Farmer:source", "source", 1, function()
  return { { "Farm At:", "Westfall", shift = true } }
end)
low:Provide("Butler:advice", "advice", 1, function()
  return { { "Butler Says:", "Keep" } }
end)
local tipS = FakeTooltip("FakeTipS")
check("Shift lines: block added", low.Write(tipS, { id = 3 }), "added")
local wantS = { "Linen Cloth", "Max Stack: 20", " ", "Auction Value:", "Costs Now:", "Butler Says:",
  " ", "Sold a Day:", "Farm At:" }
check("Shift lines: line count", #tipS.lines, #wantS)
for i, left in ipairs(wantS) do check("Shift lines: line " .. i, tipS.lines[i] and tipS.lines[i].left, left) end
check("Shift lines: two gold lines", #tipS.textures, 2)
check("Shift lines: second gold line shown", tipS.textures[2].visible, true)
check("Shift lines: second sits on its blank row", tipS.textures[2].points[1][2].line, 7)
tipS:Clear()
check("Shift lines: clear hides the second", tipS.textures[2].visible, false)

-- Shift lines only: one gold line, no second blank row.
_G.BlackthornesTooltipBlock = nil
local only = Load("Blackthornes_OnlyShift")
only:Provide("Farmer:source", "source", 1, function() return { { "Farm At:", "Westfall", shift = true } } end)
local tipO = FakeTooltip("FakeTipO")
only.Write(tipO, { id = 4 })
check("Shift only: one blank row", #tipO.lines, 4)
check("Shift only: line under the gold line", tipO.lines[4].left, "Farm At:")
check("Shift only: one gold line", #tipO.textures, 1)

-- A showing without Shift lines after one with them hides the second line.
_G.BlackthornesTooltipBlock = nil
local again = Load("Blackthornes_Again")
local withShift = true
again:Provide("Tradeskills:price", "price", 1, function()
  local out = { { "Auction Value:", "3g" } }
  if withShift then out[2] = { "Sold a Day:", "6", shift = true } end
  return out
end)
local tipA = FakeTooltip("FakeTipA")
again.Write(tipA, { id = 5 })
check("again: second gold line on", tipA.textures[2] and tipA.textures[2].visible, true)
withShift = false
tipA.lines = {}
tipA:AddLine("Linen Cloth", 1, 1, 1)
again.Write(tipA, { id = 6 })
check("again: second gold line hidden", tipA.textures[2].visible, false)

--------------------------------------------------------------------------------
print("\nnothing raises")
--------------------------------------------------------------------------------

held:Provide("Broken:source", "source", 1, function() error("secret value") end)
held:Provide("Fine:advice", "advice", 1, function() return { { "Butler Says:", "Keep" } } end)
local tip3 = FakeTooltip("FakeTip3")
_G.BlackthornesTooltipShift.hinted[tip3] = nil
check("a part that raises costs only its lines", held.Write(tip3, { id = 2 }), "added")
check("the rest still on", tip3.lines[4] and tip3.lines[4].left, "Butler Says:")
local tip4 = FakeTooltip("FakeTip4")
tip4.item = nil
check("no item, nothing added", held.Write(tip4, nil), "noitem")
check("no lines added", #tip4.lines, 2)
local tip5 = FakeTooltip("FakeTip5")
function tip5:GetItem() error("secret value") end
check("unreadable item, nothing added", held.Write(tip5, nil), "noitem")
check("nothing on a tooltip with nothing to say", Load("Blackthornes_Empty") and true, true)

--------------------------------------------------------------------------------
print("\nthe newest copy wins")
--------------------------------------------------------------------------------

_G.BlackthornesTooltipBlock = nil
local older = Load("Older")
older.FILE_VERSION = 1
local shared = _G.BlackthornesTooltipBlock
local first = shared.handlers.Write
check("first copy installs its writer", first, older.Write)
local newer = { }
-- A later file version, loaded after: its writer takes over.
shared.handlers.version = 0
local second = Load("Newer")
check("a newer copy takes over", shared.handlers.Write, second.Write)
shared.handlers.version = 99
local third = Load("Oldest")
check("an older copy can't put its own back", shared.handlers.Write, second.Write)

-- The hook is put on once, through the post-call where there is one.
local calls = {}
_G.TooltipDataProcessor = { AddTooltipPostCall = function(kind, fn) calls[#calls + 1] = { kind, fn } end }
_G.Enum = _G.Enum or {}
local savedEnum = _G.Enum.TooltipDataType
_G.Enum.TooltipDataType = { Item = 0 }
check("install takes", second:Install(), true)
check("install again does nothing", third:Install(), true)
check("one hook", #calls, 1)
_G.TooltipDataProcessor = nil
_G.Enum.TooltipDataType = savedEnum

_G.BlackthornesTooltipBlock, _G.BlackthornesTooltipShift = savedBlock, savedShift

print(string.format("\n%d failure(s)", failures))
if failures > 0 then error(failures .. " check(s) failed") end
