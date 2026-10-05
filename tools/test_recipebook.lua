-- Logic/RecipeBook.lua outside WoW: recipes nobody has learned, valued.
--
--   1. A recipe item teaches the recipe the shipped book says; one the book
--      does not list is matched by name among recipes a window has shown.
--   2. What a profession window shows is laid over the book: the game's
--      materials win, a Classic recipe under a new ID keeps its recipe
--      items, and a recipe Forever added is listed from the window alone.
--   3. A recipe is costed from its materials, though no character knows it
--      (Cost:GetCraftCost with opts.recipe), and a missing price is never
--      free.
--   4. Profit is the best return less the cost; the recipe's price is the
--      cheapest of trainer, vendor and auction; payback rounds up.
--   5. The list leaves out what the character playing knows unless asked,
--      and puts the most profit first.
--   6. The tooltip says what it teaches, who knows it, cost, sells,
--      disenchant, profit and payback; nothing for any other item; nothing
--      when switched off.
--   7. Where to learn it: trainer, vendors of the player's side, drops.

local ns = {}
ns.COLORS = setmetatable({}, { __index = function() return "ffffffff" end })
ns.NewModule = function(name) local m = {} ns[name] = m return m end

local now = 1000000
time = function() return now end
GetTime = function() return now end
UnitFactionGroup = function() return "Alliance" end

local settings = { auctionCut = 0.05, valueOwnedMaterials = true }
ns.Config = {
  Get = function(_, key) return settings[key] end,
  GetCharacterKey = function() return "me" end,
}

ns.Util = {
  FormatMoney = function(c) return tostring(c) .. "c" end,
  HasFunction = function() return false end,
}

-- Items: 2318 leather, 2320 thread, 4234 heavy leather.
local LEATHER, THREAD, HEAVY = 2318, 2320, 4234
local BOOTS, CLOAK, NEWBAG, MYSHIRT = 2307, 2308, 300001, 2587
local PATTERN_BOOTS, PATTERN_CLOAK, PATTERN_NEW = 2406, 2407, 400001

ns.RECIPE_BOOK = {
  PROFESSIONS = { [165] = "Leatherworking", [197] = "Tailoring" },
  RECIPES = {
    [2158] = { 165, 90, BOOTS, 1, 1, { LEATHER, 7, THREAD, 2 }, "Fine Leather Boots" },
    [2159] = { 165, 85, CLOAK, 1, 1, { LEATHER, 10, HEAVY, 1 }, "Fine Leather Cloak", t = 550 },
    [2160] = { 165, 50, 2300, 1, 1, { LEATHER, 8 }, "Embossed Leather Vest", t = 100 },
    [2406] = { 197, 100, MYSHIRT, 1, 1, { THREAD, 1 }, "Gray Woolen Shirt", t = 180 },
  },
  ITEMS = {
    [PATTERN_BOOTS] = { 2158, 100, d = 569 },
    [PATTERN_CLOAK] = { 2159, 400, v = { "Hordey", "Orgrimmar", "H", "Alli", "Ironforge", "A" } },
  },
}

local prices = { [LEATHER] = 10, [THREAD] = 5, [PATTERN_BOOTS] = 900, [PATTERN_CLOAK] = 300 }
ns.Prices = { GetValue = function(_, id) return prices[id] end }
ns.Vendor = {
  GetUnitPrice = function(_, id) if id == THREAD then return 5 end end,
  IsLimited = function() return false end,
  GetTable = function() return {} end,
}
ns.Inventory = {
  GetBagCount = function() return 0 end,
  GetBankCount = function() return 0 end,
}

-- Who knows what: this character knows the shirt (under the book's ID).
local accountWide = { [2406] = { outputItemID = MYSHIRT, knownBy = { "me" } } }
ns.Recipes = {
  GetAny = function() return nil end,
  GetAll = function() return {} end,
  GetAccountWide = function() return accountWide end,
  GetShortCharacterName = function(_, key) return key == "alt" and "Ana" or key end,
}

-- What one craft gets back, as the Level Up tab would say.
local returns = {
  [BOOTS] = { auction = 200, disenchant = 120, vendor = 30 },
  [CLOAK] = { auction = 90, vendor = 20 },
  [NEWBAG] = { auction = 500 },
}
ns.LevelUp = {
  GetReturns = function(_, recipe)
    local r = returns[recipe.outputItemID]
    if not r then return nil end
    local copy, best, bestWay = {}, nil, nil
    for way, v in pairs(r) do copy[way] = v if not best or v > best then best, bestWay = v, way end end
    copy.best, copy.bestWay = best, bestWay
    return copy
  end,
}

local itemInfo = {
  [PATTERN_NEW] = { "Pattern: Forever Bag", 9 },
  [999] = { "Copper Ore", 7 },
  [BOOTS] = { "Fine Leather Boots", 4 }, [CLOAK] = { "Fine Leather Cloak", 4 },
  [NEWBAG] = { "Forever Bag", 1 },
}
local requested = {}
C_Item = {
  GetItemInfo = function(id)
    local i = itemInfo[id]
    if not i then return nil end
    return i[1], nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, i[2]
  end,
  RequestLoadItemDataByID = function(id) requested[id] = true end,
}

ns.db = {}

assert(loadfile(lfs_cwd .. "/Logic/Cost.lua"))("Blackthornes_TS", ns)
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

local function Line(lines, label)
  for _, line in ipairs(lines) do if line[1] == label then return line end end
end

print("\nrecipe items")
check("a pattern teaches its recipe", Book:ForItem(PATTERN_BOOTS).name, "Fine Leather Boots")
check("with the profession", Book:ForItem(PATTERN_BOOTS).profession, "Leatherworking")
check("an ordinary item teaches nothing", Book:ForItem(999), nil)
check("an unlisted pattern, nothing seen yet", Book:ForItem(PATTERN_NEW), nil)

print("\nwhat the window showed")
Book:NoteSeen(1263000, { name = "Forever Bag", outputItemID = NEWBAG, quantityMin = 1,
  reagents = { { itemID = LEATHER, quantity = 20 } }, skillLineID = 2945 })
Book:NoteSeen(1250001, { name = "Fine Leather Cloak", outputItemID = CLOAK, quantityMin = 1,
  reagents = { { itemID = LEATHER, quantity = 12 } }, skillLineID = 165 })
check("a Forever recipe is in the book", Book:Get(1263000).name, "Forever Bag")
check("its modern skill line names the profession", Book:Get(1263000).profession, "Leatherworking")
check("an unlisted pattern now matches by name", Book:ForItem(PATTERN_NEW).recipeID, 1263000)
check("a Classic recipe moved to the game's ID", Book:Get(1250001).name, "Fine Leather Cloak")
check("the old ID still finds it", Book:Get(2159).recipeID, 1250001)
check("the game's materials win", Book:Get(1250001).reagents[1].quantity, 12)
check("it keeps its pattern", Book:ForItem(PATTERN_CLOAK).recipeID, 1250001)
check("and its trainer", Book:Get(1250001).trainerCost, 550)
check("nothing about who looked is kept", ns.db.seenRecipes[1263000].learned, nil)

print("\nwhat it is worth")
local boots = Book:Value(Book:Get(2158))
check("materials cost 7x10 + 2x5", boots.cost, 80)
check("best return is the auction", boots.back, 200)
check("profit per craft", boots.profit, 120)
check("the recipe costs its auction price", boots.price, 900)
check("bought at auction", boots.priceHow, "auction")
check("pays back after 8 crafts (900/120 rounds up)", boots.payback, 8)
local cloak = Book:Value(Book:Get(1250001))
check("the cloak's price is the cheapest: auction 300 < trainer 550", cloak.price, 300)
check("cloak profit after 12 leather", cloak.profit, -30)
check("no payback when it loses", cloak.payback, nil)
prices[LEATHER] = nil
check("an unpriced material is never free", Book:Value(Book:Get(2158)).cost, nil)
check("and no profit is claimed", Book:Value(Book:Get(2158)).profit, nil)
prices[LEATHER] = 10

print("\nthe list")
local rows = Book:List({ profession = "Leatherworking" })
check("unlearned Leatherworking recipes", #rows, 4)
check("most profit first", rows[1].name, "Forever Bag")
check("then the boots", rows[2].name, "Fine Leather Boots")
check("no tailoring here", Book:List({ profession = "Tailoring" })[1], nil)
check("known ones only when asked", #Book:List({ profession = "Tailoring", includeKnown = true }), 1)
check("searching by name", #Book:List({ search = "boots" }), 1)

print("\nthe tooltip")
local lines = Book:TooltipLines(PATTERN_BOOTS)
check("teaches", Line(lines, "Teaches")[2], "Fine Leather Boots  (Leatherworking 90)")
check("known by nobody", Line(lines, "Known by")[2], "nobody on this account")
check("cost to make", Line(lines, "Cost to make")[2], "80c")
check("sells for, after the cut", Line(lines, "Sells for")[2], "200c after the cut")
check("disenchants for", Line(lines, "Disenchants for")[2], "120c")
check("profit per craft", Line(lines, "Profit per craft")[2], "120c")
check("in green", Line(lines, "Profit per craft").color, "profit")
check("pays for itself", Line(lines, "Pays for itself")[2], "after 8 crafts")
accountWide[2158] = { outputItemID = BOOTS, knownBy = { "alt" } }
Book.known = nil
check("an alt who knows it is named", Line(Book:TooltipLines(PATTERN_BOOTS), "Known by")[2], "Ana")
check("an ordinary item gets nothing", #Book:TooltipLines(999), 0)
itemInfo[BOOTS] = nil
check("an output not loaded yet says so",
  Line(Book:TooltipLines(PATTERN_BOOTS), "Sells for")[2], "loading, hover again")
check("and is asked for", requested[BOOTS], true)
itemInfo[BOOTS] = { "Fine Leather Boots", 4 }
settings.showRecipeValueOnTooltips = false
check("switched off says nothing", #Book:TooltipLines(PATTERN_BOOTS), 0)
settings.showRecipeValueOnTooltips = nil

print("\nwhere to learn it")
local short, where = Book:LearnFrom(Book:Get(1250001))
check("a trainer comes first", short, "Trainer")
check("trainer line", where[1], "Trainer, 550c")
check("only this side's vendor", where[2], "Vendor: Alli, Ironforge")
check("and no other", where[3], nil)
local dropShort, dropWhere = Book:LearnFrom(Book:Get(2158))
check("a world drop", dropShort, "Drop")
check("says how widely", dropWhere[1], "World drop (569 kinds of creature)")

if failures > 0 then error(("%d recipe book check(s) failed"):format(failures)) end
print("\n  recipe book: all checks passed")
