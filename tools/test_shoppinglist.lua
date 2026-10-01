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
if failed > 0 then
  error(string.format("FAIL -- %d of %d shopping list checks wrong", failed, passed + failed))
end
print(string.format("PASS -- the shopping list reads correctly (%d checks)", passed))
print("")
