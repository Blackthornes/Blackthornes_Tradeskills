-- Shift-click on + queues all the bags can make (a player asked, the owner
-- said build it, 2026-11-28). Both + buttons: the craft pane's row and the
-- Queue tab's row. What must hold:
--   1. A plain click still queues one more.
--   2. Shift-click sets the total to what the bags can make: 3 queued with
--      room for 10 makes 10, not 13. Never lower.
--   3. The max on hand still stops it, as + does.
--   4. With nothing to make: nothing queued, the + shakes, one chat line.
--   5. A sub-craft on the Queue tab is left alone.
--   6. The hovers say how many, or say none in grey.

local GLOBALS = { "IsShiftKeyDown" }
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

local shift = false
_G.IsShiftKeyDown = function() return shift end

-- The world: Mithril Bar (bags make 10), Gold Bar (bags make none), and a
-- sub-craft.
local MITHRIL, GOLD, BOLT = 1, 2, 3
local RECIPES = {
  [MITHRIL] = { recipeID = MITHRIL, name = "Mithril Bar", outputItemID = 3860, quantityMin = 1 },
  [GOLD] = { recipeID = GOLD, name = "Gold Bar", outputItemID = 3577, quantityMin = 1 },
  [BOLT] = { recipeID = BOLT, name = "Bolt of Silk Cloth", outputItemID = 4305, quantityMin = 1 },
}
local CRAFTABLE = { [MITHRIL] = 10, [GOLD] = 0, [BOLT] = 6 }
local LIMIT = {}   -- room left under the max on hand, by item

local queue = {}
local printed = {}

local ns = {}
ns.NewModule = function(name) local m = {}; ns[name] = m; return m end
ns.Theme, ns.Widgets, ns.Util = {}, {}, {}
ns.Print = function(text) printed[#printed + 1] = text end
ns.Warn = ns.Print
ns.Recipes = {
  GetAny = function(_, id) return RECIPES[id] end,
  GetAll = function() return RECIPES end,
}
ns.Profit = { GetCraftableCount = function(_, id) return CRAFTABLE[id] or 0 end }
local settings = {}
ns.Config = { Get = function(_, key) return settings[key] end }
ns.Queue = {
  Find = function(_, id) local e = queue[id]; if e then return 1, e end end,
  Add = function(_, id, n)
    queue[id] = queue[id] or { recipeID = id, quantity = 0 }
    queue[id].quantity = queue[id].quantity + n
  end,
  SetQuantity = function(_, id, n)
    if n <= 0 then queue[id] = nil return end
    queue[id] = queue[id] or { recipeID = id, quantity = 0 }
    queue[id].quantity = n
  end,
  GetAll = function() return {} end,
}
-- The real limit is read by item; queued crafts count against it.
ns.Auctions = {
  GetRoom = function(_, itemID)
    local room = LIMIT[itemID]
    if room == nil then return nil, 0, 0, 0, 0, 0 end
    local queued = 0
    for _, e in pairs(queue) do
      if RECIPES[e.recipeID].outputItemID == itemID then queued = queued + e.quantity end
    end
    return math.max(0, room - queued), 0, 2, queued, room + 2, 0, false
  end,
  GetRestockAt = function() return nil end,
}

local CraftPanel
do
  local chunk = assert(loadfile(lfs_cwd .. "/UI/CraftPanel.lua"))
  chunk("Blackthornes_TS", ns)
  CraftPanel = ns.CraftPanel
end

-- A button that counts its shakes.
local function Button()
  local shakes = 0
  local group = {
    Stop = function() end,
    Play = function() shakes = shakes + 1 end,
    CreateAnimation = function()
      return { SetOffset = function() end, SetDuration = function() end, SetOrder = function() end }
    end,
  }
  local b = { CreateAnimationGroup = function() return group end }
  b.Shakes = function() return shakes end
  return b
end

-- The craft pane's + goes through these two, the same as its click.
local function PaneClick(id, button)
  local line = { recipeID = id, name = RECIPES[id].name, outputItemID = RECIPES[id].outputItemID,
    craftable = CRAFTABLE[id] }
  if CraftPanel.ShiftDown() then return CraftPanel:QueueAll(line, button) end
  ns.Queue:Add(id, 1)
end

print("\n1. craft pane: plain click still queues one")
PaneClick(MITHRIL, Button())
check("one queued", queue[MITHRIL] and queue[MITHRIL].quantity, 1)

print("\n2. craft pane: Shift-click sets the total to what the bags make")
shift = true
queue = {}
ns.Queue:Add(MITHRIL, 3)
PaneClick(MITHRIL, Button())
check("3 becomes 10, not 13", queue[MITHRIL].quantity, 10)
PaneClick(MITHRIL, Button())
check("a second Shift-click adds nothing", queue[MITHRIL].quantity, 10)
ns.Queue:SetQuantity(MITHRIL, 14)
PaneClick(MITHRIL, Button())
check("more than that queued is left alone", queue[MITHRIL].quantity, 14)

print("\n3. the max on hand still stops it")
queue, printed = {}, {}
LIMIT[3860] = 4
local line = { recipeID = MITHRIL, name = "Mithril Bar", outputItemID = 3860, roomInCrafts = 4, postLimit = 6, stock = 2 }
CraftPanel:QueueAll(line, Button())
check("stops at the limit", queue[MITHRIL] and queue[MITHRIL].quantity, 4)
check("and says so", printed[1] ~= nil and printed[1]:find("fills your limit", 1, true) ~= nil, true)
settings.craftPaneIgnoreLimit = true
queue = {}
line.roomInCrafts = 4
CraftPanel:QueueAll(line, Button())
check("Ignore max on hand lets it make all 10", queue[MITHRIL].quantity, 10)
settings.craftPaneIgnoreLimit = nil
LIMIT[3860] = nil

print("\n4. nothing to make: nothing queued, a shake and one chat line")
queue, printed = {}, {}
local button = Button()
local added = PaneClick(GOLD, button)
check("nothing queued", queue[GOLD], nil)
check("reports none", added, 0)
check("the + shakes", button.Shakes(), 1)
check("one chat line", #printed, 1)
check("names the craft", printed[1], "Your bags don't have the materials for any Gold Bar.")

print("\n5. Queue tab +")
-- The real Queue tab code, loaded on stubs for everything it draws.
local function Stub()
  return setmetatable({}, { __call = function() return Stub() end, __index = function() return Stub() end })
end
do
  local realL = ns.L
  ns.L = false
  local chunk = assert(loadfile(lfs_cwd .. "/UI/Tab_Queue.lua"))
  local okLoad, err = pcall(chunk, "Blackthornes_TS", setmetatable(ns, { __index = function(_, key)
    if key == "CraftPanel" or key == "Profit" or key == "Queue" or key == "ADDON_NAME" then return nil end
    return Stub()
  end }))
  setmetatable(ns, nil)
  ns.L = realL
  if not okLoad and not ns.QueuePlus then print("  load stopped: " .. tostring(err)) end
end
local Plus = ns.QueuePlus
check("the Queue tab + loaded", type(Plus) == "table", true)
if type(Plus) == "table" then
  queue, printed = {}, {}
  shift = false
  ns.Queue:Add(MITHRIL, 3)
  local row = { data = queue[MITHRIL], plus = Button() }
  Plus.Click(row)
  check("plain click adds one", queue[MITHRIL].quantity, 4)
  shift = true
  row.data = queue[MITHRIL]
  Plus.Click(row)
  check("Shift-click: 4 becomes 10", queue[MITHRIL].quantity, 10)

  LIMIT[3860] = 7
  ns.Queue:SetQuantity(MITHRIL, 3)
  row.data = queue[MITHRIL]
  Plus.Click(row)
  check("Shift-click stops at the max on hand", queue[MITHRIL].quantity, 7)
  LIMIT[3860] = nil

  ns.Queue:Add(GOLD, 2)
  local goldRow = { data = queue[GOLD], plus = Button() }
  printed = {}
  Plus.Click(goldRow)
  check("none to make: unchanged", queue[GOLD].quantity, 2)
  check("none to make: shakes", goldRow.plus.Shakes(), 1)
  check("none to make: chat line", printed[1], "Your bags don't have the materials for any Gold Bar.")

  local sub = { recipeID = BOLT, quantity = 2, isDependency = true }
  queue[BOLT] = sub
  Plus.Click({ data = sub, plus = Button() })
  check("a sub-craft is left alone", sub.quantity, 2)

  print("\n6. the hovers")
  local said
  local tip = { SetText = function(_, text) said = text end }
  Plus.Tooltip({ data = queue[MITHRIL] }, tip)
  check("Queue tab + with some", said, "Add one more.\nShift-click to queue all 10 your bags can make.")
  Plus.Tooltip({ data = queue[GOLD] }, tip)
  check("Queue tab + with none, greyed", said,
    "Add one more.\n|cff9a9a9aShift-click queues all you can make. Your bags have the materials for none right now.|r")
  check("a sub-craft has no hover", Plus.Tooltip({ data = sub }, tip), false)
end
check("craft pane line with some", CraftPanel.ShiftClickLine(10),
  "Shift-click to queue all 10 your bags can make.")

print("\n7. both + buttons are wired to Shift")
local function Source(path)
  local file = assert(io.open(lfs_cwd .. path))
  local text = file:read("*a")
  file:close()
  return text
end
local pane = Source("/UI/CraftPanel.lua")
check("craft pane + asks for Shift", pane:find("if ShiftDown() then\n            CraftPanel:QueueAll(row.data, row.add)", 1, true) ~= nil, true)
check("craft pane hover adds the line", pane:find(".. \"\\n\" .. CraftPanel.ShiftClickLine(line.craftable)", 1, true) ~= nil, true)
local tab = Source("/UI/Tab_Queue.lua")
check("Queue tab + clicks through QueuePlus", tab:find("function() QueuePlus.Click(row) end", 1, true) ~= nil, true)
check("Queue tab + hover through QueuePlus", tab:find("return QueuePlus.Tooltip(row, tooltip)", 1, true) ~= nil, true)

for _, key in ipairs(GLOBALS) do _G[key] = saved[key] end

if failures > 0 then error(failures .. " check(s) failed") end
print("\nall Shift-click queue checks passed")
