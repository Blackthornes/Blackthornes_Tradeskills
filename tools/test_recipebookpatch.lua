-- Logic/RecipeBook.lua outside WoW: the kept book is mended, not rebuilt.
--
--   1. A profession window reading a recipe the book already has (same name,
--      item made and profession) mends that one record in place: the book
--      table stays the same, and it reads exactly as a fresh build would.
--   2. A window read that could move a recipe (new name, new item made,
--      new profession) still throws the book away, so it is built again.
--   3. A recipe item's tooltip skill mends that recipe's skill in place, and
--      the book still matches a fresh build.
--   4. During a sweep a read that can't be mended waits for the sweep's end
--      instead of building the book again for each item.
--   5. Book recipes that ask for the same item and count share one reagent
--      table, and a build reuses the ones from the last.

local ns = {}
ns.COLORS = setmetatable({}, { __index = function() return "ffffffff" end })
ns.NewModule = function(name) local m = {} ns[name] = m return m end

local now = 1000000
time = function() return now end
GetTime = function() return now end
UnitFactionGroup = function() return "Alliance" end

ns.Config = { Get = function() return nil end, GetCharacterKey = function() return "me" end }
ns.Util = { FormatMoney = function(c) return tostring(c) .. "c" end, HasFunction = function() return false end }

local LEATHER, THREAD, HEAVY = 2318, 2320, 4234
local BOOTS, CLOAK, VEST = 2307, 2308, 2300
local PATTERN_BOOTS, PATTERN_CLOAK = 2406, 2407

ns.RECIPE_BOOK = {
  PROFESSIONS = { [165] = "Leatherworking", [197] = "Tailoring" },
  RECIPES = {
    [2158] = { 165, 90, BOOTS, 1, 1, { LEATHER, 7, THREAD, 2 }, "Fine Leather Boots" },
    [2159] = { 165, 85, CLOAK, 1, 1, { LEATHER, 10, HEAVY, 1 }, "Fine Leather Cloak", t = 550 },
    [2160] = { 165, 50, VEST, 1, 1, { LEATHER, 7 }, "Embossed Leather Vest", t = 100 },
    [2406] = { 197, 100, 2587, 1, 1, { THREAD, 2 }, "Gray Woolen Shirt", t = 180 },
  },
  ITEMS = {
    [PATTERN_BOOTS] = { 2158, 100 },
    [PATTERN_CLOAK] = { 2159, 400 },
  },
}

ns.db = {}
assert(loadfile(lfs_cwd .. "/Logic/RecipeBook.lua"))("Blackthornes_TS", ns)
local Book = ns.RecipeBook

local failures = 0
local function check(label, got, want)
  if got ~= want then
    failures = failures + 1
    print(string.format("  FAIL  %-56s got %s, wanted %s", label, tostring(got), tostring(want)))
  else
    print(string.format("  ok    %-56s %s", label, tostring(got)))
  end
end

-- Same values all the way down; tables compared by what they hold.
local function Same(a, b, seen)
  if type(a) ~= "table" or type(b) ~= "table" then return a == b end
  seen = seen or {}
  if seen[a] == b then return true end
  seen[a] = b
  for k, v in pairs(a) do if not Same(v, b[k], seen) then return false, k end end
  for k in pairs(b) do if a[k] == nil then return false, k end end
  return true
end

-- The kept book against one built from scratch from the same saved data.
local function MatchesFresh()
  local kept, keptAliases = Book.merged, Book.aliases
  Book.merged = nil
  local fresh, freshAliases = Book:GetAll()
  local ok, where = Same(kept, fresh)
  local okAliases = Same(keptAliases, freshAliases)
  Book.merged, Book.aliases = kept, keptAliases
  return ok and okAliases, where
end

print("\nshared reagents")
local first = Book:GetAll()
check("boots and vest share Leather x7", first[2158].reagents[1] == first[2160].reagents[1], true)
check("different counts are different tables", first[2158].reagents[1] == first[2159].reagents[1], false)
check("the shared one reads right", first[2160].reagents[1].quantity, 7)
Book:Invalidate()
local second = Book:GetAll()
check("a new build reuses the same tables", second[2158].reagents[1] == first[2158].reagents[1], true)

print("\na window read that matches is mended in place")
local kept = Book:GetAll()
Book:NoteSeen(2158, { name = "Fine Leather Boots", outputItemID = BOOTS, quantityMin = 1, quantityMax = 2,
  reagents = { { itemID = LEATHER, quantity = 9 } }, skillLineID = 165 })
check("the book was kept", Book.merged, kept)
check("the game's materials are on the record", Book:Get(2158).reagents[1].quantity, 9)
check("and its count", Book:Get(2158).quantityMax, 2)
check("marked as seen", Book:Get(2158).seenInGame, true)
check("it matches a fresh build", (MatchesFresh()), true)

Book:NoteSeen(2158, { name = "Fine Leather Boots", outputItemID = BOOTS, quantityMin = 1,
  reagents = { { itemID = LEATHER, quantity = 8 }, { itemID = THREAD, quantity = 1 } }, skillLineID = 165 })
check("read again, still kept", Book.merged, kept)
check("and still matches a fresh build", (MatchesFresh()), true)

print("\na window read that could move a recipe rebuilds")
Book:NoteSeen(2159, { name = "Fine Leather Cloak", outputItemID = 9999, quantityMin = 1,
  reagents = { { itemID = LEATHER, quantity = 12 } }, skillLineID = 165 })
check("a new item made throws the book away", Book.merged, nil)
check("and the rebuilt one has it", Book:Get(2159).outputItemID, 9999)
kept = Book:GetAll()
Book:NoteSeen(2406, { name = "Grey Woolen Shirt", outputItemID = 2587, quantityMin = 1,
  reagents = { { itemID = THREAD, quantity = 3 } }, skillLineID = 197 })
check("a new name throws the book away", Book.merged, nil)
kept = Book:GetAll()
Book:NoteSeen(1263000, { name = "Forever Bag", outputItemID = 300001, quantityMin = 1,
  reagents = { { itemID = LEATHER, quantity = 20 } }, skillLineID = 2945 })
check("a recipe the book lacks throws it away", Book.merged, nil)
check("and the rebuilt one lists it", Book:Get(1263000).name, "Forever Bag")
kept = Book:GetAll()
Book:NoteSeen(2160, { name = "Embossed Leather Vest", outputItemID = VEST, quantityMin = 1,
  reagents = {}, skillLineID = 165 })
check("a read with no materials throws it away", Book.merged, nil)
check("and the book's materials stay", Book:Get(2160).reagents[1].quantity, 7)

print("\na recipe item's skill is mended in place")
local tooltips = {
  [PATTERN_BOOTS] = { lines = { { leftText = "Requires Leatherworking (75)" } } },
  [PATTERN_CLOAK] = { lines = { { leftText = "Requires Leatherworking (95)" } } },
}
local oldItem, oldTooltip, oldHas = C_Item, C_TooltipInfo, ns.Util.HasFunction
C_TooltipInfo = { GetItemByID = function(id) return tooltips[id] end }
C_Item = {
  GetItemInfo = function(id) return "Pattern: " .. id, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, 9 end,
  IsItemDataCachedByID = function(id) return tooltips[id] ~= nil end,
  RequestLoadItemDataByID = function() end,
}
ns.Util.HasFunction = function(path)
  return path == "C_TooltipInfo.GetItemByID" or path == "C_Item.IsItemDataCachedByID"
end
kept = Book:GetAll()
check("the tooltip is read", Book:LearnSkill(PATTERN_BOOTS), true)
check("the book was kept", Book.merged, kept)
check("the boots ask for 75", Book:Get(2158).skill, 75)
check("it matches a fresh build", (MatchesFresh()), true)

print("\na sweep waits to rebuild")
Book.merged = nil
Book.sweeping = true
Book.rebuildAfterSweep = false
check("with no book there is nothing to mend", Book:LearnSkill(PATTERN_CLOAK), true)
check("and no rebuild is owed", Book.rebuildAfterSweep, false)
Book.sweeping = nil
check("the cloak asks for 95 once built", Book:Get(2159).skill, 95)

-- A skill with no record to land on can't be mended: the sweep owes a rebuild.
kept = Book:GetAll()
ns.RECIPE_BOOK.ITEMS[400005] = { 777777, 100 }
tooltips[400005] = { lines = { { leftText = "Requires Leatherworking (120)" } } }
Book.sweeping = true
Book.rebuildAfterSweep = false
Book:LearnSkill(400005)
check("mid-sweep the book is kept", Book.merged, kept)
check("and a rebuild is owed", Book.rebuildAfterSweep, true)
Book.sweeping = nil
Book.rebuildAfterSweep = false
Book.sweeping = false
ns.RECIPE_BOOK.ITEMS[400006] = { 777778, 100 }
tooltips[400006] = { lines = { { leftText = "Requires Leatherworking (125)" } } }
Book:LearnSkill(400006)
check("out of a sweep it rebuilds at once", Book.merged, nil)

C_TooltipInfo, C_Item, ns.Util.HasFunction = oldTooltip, oldItem, oldHas

if failures > 0 then error(("%d recipe book patch check(s) failed"):format(failures)) end
print("\n  recipe book patch: all checks passed")
