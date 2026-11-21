-- The shopping list under the queued crafts beside the profession window.
--
-- Ranatsu32 asked for the materials the whole queue needs, in the window you
-- craft from. The list itself is the Queue tab's (Queue:GetShoppingList, tested
-- with the queue); what is tested here is how each line reads, which other
-- character it points you to, and how the column is shared with the crafts.

local ns = {}
ns.NewModule = function(name) local m = {}; ns[name] = m; return m end
ns.Theme, ns.Widgets, ns.Util = {}, {}, {}
ns.COLORS = { accent = "ffc8a44d", muted = "ff7a8089" }

local CraftPanel
do
  local realNew = ns.NewModule
  ns.NewModule = function(name) local m = realNew(name); CraftPanel = m; return m end
  assert(loadfile(lfs_cwd .. "/UI/CraftPanel.lua"))("Blackthornes_TS", ns)
  ns.NewModule = realNew
end

ns.Util.FormatMoney = function(copper) return tostring(copper) .. "c" end
ns.Util.CharacterName = function(key) return key:match("^([^%-]+)") or "" end

local SETTINGS = {}
ns.Config = {
  GetCharacterKey = function() return "Main-Realm" end,
  Get = function(_, key) return SETTINGS[key] end,
  Set = function(_, key, value) SETTINGS[key] = value end,
}

ns.db = { characters = {
  ["Main-Realm"] = { inventory = { [10] = 99 }, bank = { [10] = 99 } },
  ["Bankalt-Realm"] = { inventory = { [20] = 1 }, bank = { [20] = 4 } },
  ["Crafter-Realm"] = { inventory = { [20] = 2 } },
} }

local passed, failed = 0, 0

local function check(label, got, want)
  local ok = got == want
  if ok then passed = passed + 1 else failed = failed + 1 end
  print(string.format("  %-56s %-14s %s", label, tostring(got), ok and "ok" or
    ("WRONG, wanted " .. tostring(want))))
end

print("Shopping list lines")

do
  local look = CraftPanel:ShoppingLook({ itemID = 30, needed = 12, have = 12, shortfall = 0 })
  check("enough on you reads green", look.colour, "profit")
  check("and says so", look.tag, "have all")
  check("with a full bar", look.fraction, 1)
  check("and have over need", look.count, "12/12")

  look = CraftPanel:ShoppingLook({ itemID = 30, needed = 56, have = 58, shortfall = 0, needsBankTrip = true })
  check("enough only counting the bank reads amber", look.colour, "warn")
  check("and sends you to the bank", look.tag, "in bank")
  check("a surplus never overfills the bar", look.fraction, 1)

  look = CraftPanel:ShoppingLook({ itemID = 40, needed = 8, have = 2, shortfall = 6,
    estimatedCost = 1800, fromVendor = true })
  check("short reads red", look.colour, "loss")
  check("a quarter owned is a quarter bar", look.fraction, 0.25)
  check("a vendor material says vendor and its cost", look.tag, "|cffc8a44dvendor|r 1800c")

  look = CraftPanel:ShoppingLook({ itemID = 40, needed = 2, have = 0, shortfall = 2, estimatedCost = 500 })
  check("an auction material shows just its cost", look.tag, "500c")
  check("and an empty bar", look.fraction, 0)

  look = CraftPanel:ShoppingLook({ itemID = 40, needed = 2, have = 0, shortfall = 2 })
  check("no price says so rather than 0", look.tag, "no price")

  look = CraftPanel:ShoppingLook({ itemID = 20, needed = 4, have = 0, shortfall = 4, estimatedCost = 900 })
  check("another character holding enough reads amber", look.colour, "warn")
  check("and names the one holding most, bags and bank", look.tag, "on Bankalt")

  look = CraftPanel:ShoppingLook({ itemID = 20, needed = 9, have = 0, shortfall = 9, estimatedCost = 900 })
  check("not enough on any one character is still to buy", look.tag, "900c")

  look = CraftPanel:ShoppingLook({ itemID = 10, needed = 200, have = 0, shortfall = 200, estimatedCost = 1 })
  check("your own bank is never read as another character", look.tag, "1c")
end

print("")
print("Sharing the column with the queued crafts")

do
  check("a short queue takes only its rows", CraftPanel.QueuedListHeight(400, 3), 90)
  check("a long queue stops at its share", CraftPanel.QueuedListHeight(400, 30), 180)
  check("a tiny column still keeps two crafts", CraftPanel.QueuedListHeight(60, 9), 60)
  check("an empty queue keeps one row of room", CraftPanel.QueuedListHeight(400, 0), 30)
end

print("")
print("Room for the queued crafts")

do
  check("room past the pane: shown", CraftPanel.QueuedFits(1500, 2000), true)
  check("no room: out of the way rather than over the pane", CraftPanel.QueuedFits(1830, 2000), false)
  check("exactly enough room", CraftPanel.QueuedFits(2000 - 254, 2000), true)
  check("not laid out yet: shown", CraftPanel.QueuedFits(nil, 2000), true)
end

print("")
print("On the one window's Crafting tab")

-- The owner asked (2026-11-18) for the drawer's queued crafts and shopping
-- list on the one window's Crafting tab, on its right. Acted out with plain
-- frames: open the profession window with the one window on, queue a craft,
-- empty the queue, then leave the one window.
do
  local function fakeFrame(width, height)
    local f = { shown = false, points = {}, width = width, height = height }
    function f:Show() self.shown = true end
    function f:Hide() self.shown = false end
    function f:IsShown() return self.shown end
    function f:SetShown(on) self.shown = on and true or false end
    function f:SetParent(p) self.parent = p end
    function f:GetParent() return self.parent end
    function f:ClearAllPoints() self.points = {} end
    function f:SetPoint(point, rel, relPoint, x, y)
      self.points[point] = { rel = rel, relPoint = relPoint, x = x or 0, y = y or 0 }
    end
    function f:SetWidth(w) self.width = w end
    function f:GetWidth() return self.width end
    function f:SetHeight(h) self.height = h end
    function f:GetHeight() return self.height end
    function f:GetRight() return 0 end
    function f:SetClampedToScreen(on) self.clamped = on end
    function f:SetText(t) self.text = t end
    function f:SetData(d) self.data = d end
    return f
  end

  local queued = 0
  local saved = { Queue = ns.Queue, Collapse = ns.Collapse, Motion = ns.Motion }
  local oldHalo = ns.Theme.SetHalo
  ns.Theme.SetHalo = function(frame, alpha) frame.halo = alpha end
  ns.Collapse = { IsCollapsed = function() return false end, CONTENT_TOP = -30 }
  ns.Motion = nil
  ns.Queue = {
    Count = function() return queued end,
    GetAll = function()
      local all = {}
      for i = 1, queued do all[i] = { recipeID = i } end
      return all
    end,
    GetShoppingList = function() return {} end,
  }
  local oldTotal, oldOpen = CraftPanel.ShoppingTotalText, CraftPanel.GetOpenRecipeIDs
  CraftPanel.ShoppingTotalText = function() return "To buy 0c" end
  CraftPanel.GetOpenRecipeIDs = function() return {} end

  local tab = fakeFrame(900, 430)
  local pane = fakeFrame(350, 430)
  pane.shown = true
  local drawer = fakeFrame(250, 430)
  drawer.titan = fakeFrame()
  drawer.titan.shown = true
  drawer.parent = pane
  CraftPanel.frame, CraftPanel.queuedFrame = pane, drawer
  CraftPanel.queuedTitle, CraftPanel.queuedList, CraftPanel.shoppingList = fakeFrame(), fakeFrame(), fakeFrame()
  CraftPanel.shoppingHeading, CraftPanel.shoppingColumns = fakeFrame(), fakeFrame()
  CraftPanel.shoppingToggle, CraftPanel.shoppingTotal = fakeFrame(), fakeFrame()
  CraftPanel.inOne, CraftPanel.oneContainer, CraftPanel.columnInOne = true, tab, nil
  CraftPanel:LayOutInOne(false)

  CraftPanel:RefreshQueued()
  check("nothing queued: no queued crafts", drawer.shown, false)
  check("and the crafts fill the tab", pane.points.BOTTOMRIGHT.x, 0)

  queued = 2
  CraftPanel:RefreshQueued()
  check("a craft queued: the queued crafts show", drawer.shown, true)
  check("inside the tab", drawer.parent, tab)
  check("on its right", drawer.points.TOPRIGHT and drawer.points.TOPRIGHT.rel, tab)
  check("the full height of the tab", drawer.points.BOTTOMRIGHT and drawer.points.BOTTOMRIGHT.rel, tab)
  check("without the drawer's own rim", drawer.titan.shown, false)
  check("the crafts make room for them", pane.points.BOTTOMRIGHT.x < -250, true)
  check("with the count in the title", CraftPanel.queuedTitle.text, "Queued crafts (2)")
  check("and the shopping list under them", CraftPanel.shoppingList.shown, true)

  local placed = 0
  local realSet = pane.SetPoint
  pane.SetPoint = function(...) placed = placed + 1; return realSet(...) end
  CraftPanel:RefreshQueued()
  check("another refresh does not move the pane again", placed, 0)
  pane.SetPoint = realSet

  check("too narrow a tab: the crafts keep the room", CraftPanel.QueuedFitsInOne(500), false)
  check("wide enough: room for both", CraftPanel.QueuedFitsInOne(900), true)
  check("not laid out yet: shown", CraftPanel.QueuedFitsInOne(nil), true)
  tab.width = 500
  CraftPanel:RefreshQueued()
  check("a narrow tab hides them", drawer.shown, false)
  check("and the crafts fill it again", pane.points.BOTTOMRIGHT.x, 0)

  -- Made wide again by the player: nothing else asks, so the tab's own
  -- size change brings them back, once the size settles.
  local timers, oldTimer = {}, C_Timer
  C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end }
  function tab:HookScript(name, fn) self.hooks = self.hooks or {}; self.hooks[name] = fn end
  CraftPanel:WatchTabSize(tab)
  CraftPanel:WatchTabSize(tab)
  tab.width = 900
  tab.hooks.OnSizeChanged(tab, 900, 430)
  tab.hooks.OnSizeChanged(tab, 901, 430)
  check("a drag's steps wait for one redraw", #timers, 1)
  timers[1]()
  check("made wide again, the queued crafts come back", drawer.shown, true)
  C_Timer = oldTimer

  CraftPanel:RefreshQueued()
  queued = 0
  CraftPanel:RefreshQueued()
  check("the queue empties: they go", drawer.shown, false)
  check("the crafts take the whole tab", pane.points.BOTTOMRIGHT.x, 0)

  queued = 1
  CraftPanel:RefreshQueued()
  CraftPanel.OutOfOne = CraftPanel.OutOfOne
  CraftPanel.inOne = true
  local oldStop = CraftPanel.StopSlicedRefresh
  CraftPanel.StopSlicedRefresh = function() end
  pane.SetToplevel = function() end
  pane.SetFrameStrata = function() end
  pane.titan = nil
  CraftPanel.ApplyBody = function() end
  CraftPanel:OutOfOne()
  check("leaving the one window: back on the pane", drawer.parent, pane)
  check("beside its right edge", drawer.points.TOPLEFT and drawer.points.TOPLEFT.relPoint, "TOPRIGHT")
  check("drawer width again", drawer.width, CraftPanel.QUEUED_WIDTH)
  check("rim back on", drawer.titan.shown, true)

  CraftPanel.StopSlicedRefresh = oldStop
  CraftPanel.ShoppingTotalText, CraftPanel.GetOpenRecipeIDs = oldTotal, oldOpen
  CraftPanel.frame, CraftPanel.queuedFrame, CraftPanel.inOne, CraftPanel.oneContainer = nil, nil, false, nil
  ns.Theme.SetHalo = oldHalo
  ns.Queue, ns.Collapse, ns.Motion = saved.Queue, saved.Collapse, saved.Motion
end

print("")
print("Showing and hiding")

do
  CraftPanel.RefreshQueued = function() end
  check("shown until hidden", CraftPanel:IsShoppingShown(), true)
  CraftPanel:SetShoppingShown(false)
  check("hiding is remembered", SETTINGS.craftPaneShoppingList, false)
  check("and read back", CraftPanel:IsShoppingShown(), false)
  CraftPanel:SetShoppingShown(true)
  check("showing again", CraftPanel:IsShoppingShown(), true)
end

print("")
print("The Buy view at the auction house")

do
  local PostPanel
  local realNew = ns.NewModule
  ns.NewModule = function(name) local m = realNew(name); PostPanel = m; return m end
  assert(loadfile(lfs_cwd .. "/UI/PostPanel.lua"))("Blackthornes_TS", ns)
  ns.NewModule = realNew

  check("opens on the sell list", PostPanel.view, "sell")

  check("a short auction material can be searched for",
    PostPanel:CanSearch({ shortfall = 2 }), true)
  check("a vendor material is never searched for",
    PostPanel:CanSearch({ shortfall = 2, fromVendor = true }), false)
  check("a vendor with limited stock can still be searched for",
    PostPanel:CanSearch({ shortfall = 2, fromVendor = true, vendorLimited = true }), true)
  check("nor one you already have",
    PostPanel:CanSearch({ shortfall = 0 }), false)

  ns.Queue = { GetShoppingTotal = function() return 4560, 0 end }
  local text, short = PostPanel:ShoppingSummary({
    { shortfall = 6 }, { shortfall = 0 }, { shortfall = 2 } })
  check("counts only what is still short", short, 2)
  check("and says what it costs", text, "2 materials to buy, about 4560c")

  text, short = PostPanel:ShoppingSummary({ { shortfall = 0 } })
  check("nothing short says so", text, "You have everything the queue needs.")

  local refreshed = 0
  PostPanel.Refresh = function() refreshed = refreshed + 1 end
  PostPanel:SetView("buy")
  check("Buy switches to the shopping list", PostPanel.view, "buy")
  check("and redraws", refreshed, 1)
  PostPanel:SetView("anything else")
  check("anything else is the sell list", PostPanel.view, "sell")

  -- The Search button: shown only on a row worth searching for.
  ns.CraftPanel = { UpdateShoppingRow = function() end }
  local row = { search = { SetShown = function(self, on) self.shown = on end } }
  PostPanel.UpdateShoppingRow(row, { shortfall = 3 })
  check("a material still to buy gets a Search button", row.search.shown, true)
  PostPanel.UpdateShoppingRow(row, { shortfall = 3, fromVendor = true })
  check("a vendor material does not", row.search.shown, false)
  PostPanel.UpdateShoppingRow(row, { shortfall = 0 })
  check("nor one you already have", row.search.shown, false)
  ns.CraftPanel = nil

  local now, built = 100, 0
  _G.GetTime = function() return now end
  ns.Queue.GetShoppingList = function() built = built + 1; return {} end
  PostPanel.shoppingAt = nil
  PostPanel:ShoppingLines(); PostPanel:ShoppingLines()
  check("the one-second ticker does not rebuild it every tick", built, 1)
  now = now + 2
  PostPanel:ShoppingLines()
  check("but it is fresh again two seconds on", built, 2)
  _G.GetTime = nil
end

print("")
if failed > 0 then
  error(string.format("FAIL -- %d of %d shopping list checks wrong", failed, passed + failed))
end
print(string.format("PASS -- the shopping list reads correctly (%d checks)", passed))
print("")
