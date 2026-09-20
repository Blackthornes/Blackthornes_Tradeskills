-- What the craft pane beside the profession window puts in front of you, and
-- in what order, measured without a game client.
--
-- Two things here are easy to get wrong and invisible until you are standing
-- at an anvil. The list must be restricted to the profession actually open,
-- or a blacksmith is offered tailoring; and its order must be total, because
-- recipes come out of `pairs` in an arbitrary order and a comparator that
-- calls two rows equal produces a list that reshuffles itself on every
-- refresh while you are trying to click a row in it.

local ns = {}
ns.NewModule = function(name) local m = {}; ns[name] = m; return m end
ns.Theme, ns.Widgets, ns.Util = {}, {}, {}

local CraftPanel
do
  local realNew = ns.NewModule
  ns.NewModule = function(name) local m = realNew(name); CraftPanel = m; return m end
  local chunk = assert(loadfile(lfs_cwd .. "/UI/CraftPanel.lua"))
  chunk("Blackthornes_TS", ns)
  ns.NewModule = realNew
end

--------------------------------------------------------------------------------
-- The world the pane reads from
--------------------------------------------------------------------------------

-- Two blacksmithing recipes and one tailoring recipe, so "only what this
-- window is showing" has something to actually exclude.
local RECIPES = {
  [101] = { recipeID = 101, name = "Copper Chain Belt",   outputItemID = 2853 },
  [102] = { recipeID = 102, name = "Rough Sharpening Stone", outputItemID = 2862 },
  [103] = { recipeID = 103, name = "Brown Linen Shirt",   outputItemID = 2575 },
}

local ANALYSIS = {
  [101] = { priceable = true,  profit = 5000 },
  [102] = { priceable = true,  profit = 12000 },
  [103] = { priceable = false, reason = "output has no price data" },
}

local CRAFTABLE = { [101] = 3, [102] = 0, [103] = 7 }
local QUEUED = {}

ns.Recipes = { GetAll = function() return RECIPES end }

-- The real one, copied rather than stubbed: how stock drags a craft down the
-- order is the thing under test here, and a stub would only test the stub.
local function RankValue(analysis, field)
  local value = analysis[field]
  if value == nil then return -math.huge end
  if value > 0 then return value / (analysis.stockDivisor or 1) end
  return value
end

ns.Profit = {
  Analyse = function(_, recipeID) return ANALYSIS[recipeID] end,
  GetCraftableCount = function(_, recipeID) return CRAFTABLE[recipeID] or 0 end,
  _RankValue = RankValue,
}

local SETTINGS = { hideAtPostLimit = true }

ns.Config = { Get = function(_, key) return SETTINGS[key] end }

-- The queue in the order it would actually be worked through.
local QUEUE_ORDER = {}

ns.Queue = {
  Find = function(_, recipeID)
    local entry = QUEUED[recipeID]
    if not entry then return nil end
    return 1, entry
  end,
  GetAll = function() return QUEUE_ORDER end,
}

-- Ready means "this character has the materials", which is all the crafting
-- engine knows. Whether the open window can make it is the pane's problem.
local READY = {}

ns.Crafting = {
  GetReadiness = function(_, recipeID) return READY[recipeID] == true end,
}

--------------------------------------------------------------------------------
-- Harness
--------------------------------------------------------------------------------

local passed, failed = 0, 0

local function check(label, got, want)
  local ok = got == want
  if ok then passed = passed + 1 else failed = failed + 1 end
  print(string.format("  %-56s %-10s %s", label, tostring(got), ok and "ok" or
    ("WRONG, wanted " .. tostring(want))))
end

local function names(rows)
  local out = {}
  for index, row in ipairs(rows) do out[index] = row.name end
  return table.concat(out, ", ")
end

print("")

--------------------------------------------------------------------------------
-- Which recipes appear
--------------------------------------------------------------------------------

-- No profession window answering: every cached recipe, rather than nothing.
-- An empty pane would read as broken, and the cache is the best guess there is.
check("client will not say which recipes: show them all",
  #CraftPanel:GetRows({}), 3)

-- The open window answering is the normal case, and the tailoring recipe has
-- no business on a pane docked to the blacksmithing window.
_G.C_TradeSkillUI = { GetAllRecipeIDs = function() return { 101, 102 } end }

check("blacksmithing open: the tailoring recipe is left out",
  names(CraftPanel:GetRows({ sortBy = "name" })),
  "Copper Chain Belt, Rough Sharpening Stone")

-- An empty answer is the profession window still loading, not a profession
-- with no recipes, so it falls back rather than blanking the pane.
_G.C_TradeSkillUI = { GetAllRecipeIDs = function() return {} end }
check("empty answer reads as 'no opinion', not 'nothing'",
  #CraftPanel:GetRows({}), 3)

-- Guarded because this client has API gaps, and an error here would take the
-- whole pane down rather than one row.
_G.C_TradeSkillUI = { GetAllRecipeIDs = function() error("not while closed") end }
check("client raising an error is survivable",
  #CraftPanel:GetRows({}), 3)

_G.C_TradeSkillUI = nil

--------------------------------------------------------------------------------
-- Search
--------------------------------------------------------------------------------

check("search matches on a fragment, whatever the case",
  names(CraftPanel:GetRows({ search = "LINEN" })), "Brown Linen Shirt")

check("padding either side of the search text is ignored",
  names(CraftPanel:GetRows({ search = "  copper  " })), "Copper Chain Belt")

check("no match is an empty list, not everything",
  #CraftPanel:GetRows({ search = "thorium" }), 0)

-- A plain substring, not a Lua pattern: "-" is a valid pattern character and
-- a name containing one would otherwise match nothing at all.
RECIPES[104] = { recipeID = 104, name = "Gold-Plated Buckler", outputItemID = 2866 }
ANALYSIS[104] = { priceable = true, profit = 100 }

check("a hyphen in the search is a hyphen, not a pattern",
  names(CraftPanel:GetRows({ search = "gold-plated" })), "Gold-Plated Buckler")

RECIPES[104], ANALYSIS[104] = nil, nil

--------------------------------------------------------------------------------
-- Order
--------------------------------------------------------------------------------

check("profit order puts the best-paying craft first",
  names(CraftPanel:GetRows({ sortBy = "profit" })),
  "Rough Sharpening Stone, Copper Chain Belt, Brown Linen Shirt")

check("an unpriced craft sorts last rather than as zero profit",
  CraftPanel:GetRows({ sortBy = "profit" })[3].name, "Brown Linen Shirt")

check("name order is alphabetical",
  names(CraftPanel:GetRows({ sortBy = "name" })),
  "Brown Linen Shirt, Copper Chain Belt, Rough Sharpening Stone")

check("an unrecognised order falls back to profit rather than erroring",
  names(CraftPanel:GetRows({ sortBy = "sideways" })),
  "Rough Sharpening Stone, Copper Chain Belt, Brown Linen Shirt")

-- Every tie falls through to the recipe ID, so the same data always sorts the
-- same way however `pairs` happened to hand it over.
do
  local tied = {
    [201] = { recipeID = 201, name = "Same Name", outputItemID = 1 },
    [202] = { recipeID = 202, name = "Same Name", outputItemID = 2 },
    [203] = { recipeID = 203, name = "Same Name", outputItemID = 3 },
  }

  local realRecipes, realAnalyse = ns.Recipes.GetAll, ns.Profit.Analyse

  ns.Recipes.GetAll = function() return tied end
  ns.Profit.Analyse = function() return { priceable = true, profit = 700 } end

  local first = CraftPanel:GetRows({ sortBy = "profit" })
  local second = CraftPanel:GetRows({ sortBy = "profit" })

  local stable = true
  for index = 1, #first do
    if first[index].recipeID ~= second[index].recipeID then stable = false end
  end

  check("identically priced crafts keep one fixed order", stable, true)
  check("and that order is by recipe ID", first[1].recipeID, 201)

  ns.Recipes.GetAll, ns.Profit.Analyse = realRecipes, realAnalyse
end

--------------------------------------------------------------------------------
-- Stock you already hold
--------------------------------------------------------------------------------

-- The bug this pane shipped with: it read `profit` and nothing else, so nine
-- of something already sitting on the auction house changed neither its place
-- in the list nor whether it was offered at all.
do
  -- Copper Chain Belt pays less than the sharpening stone, but the stone is
  -- one you already hold twenty of. Ranked on profit per unit of time rather
  -- than profit, the belt is the better use of the next ten minutes.
  ANALYSIS[102].stockDivisor = 21
  ANALYSIS[102].stock, ANALYSIS[102].posted = 20, 18

  check("stock you already hold sinks a craft down the order",
    names(CraftPanel:GetRows({ sortBy = "profit" })),
    "Copper Chain Belt, Rough Sharpening Stone, Brown Linen Shirt")

  local row
  for _, line in ipairs(CraftPanel:GetRows({})) do
    if line.recipeID == 102 then row = line end
  end

  check("and the row carries it, so nothing is hidden by the order alone",
    row.stock, 20)
  check("with listings counted apart from the rest", row.posted, 18)

  -- Name order is the escape hatch for finding one specific recipe, and it
  -- must stay alphabetical whatever the stock penalty is doing.
  check("name order is untouched by stock",
    names(CraftPanel:GetRows({ sortBy = "name" })),
    "Brown Linen Shirt, Copper Chain Belt, Rough Sharpening Stone")

  ANALYSIS[102].stockDivisor, ANALYSIS[102].stock, ANALYSIS[102].posted = nil, nil, nil
end

-- A loss must not be promoted by already owning a pile of it. Dividing a
-- negative by a larger divisor moves it toward zero, which would float the
-- worst overstocked craft in the list to the top.
do
  ANALYSIS[101].profit = -5000
  ANALYSIS[101].stockDivisor = 21

  check("a loss is not promoted by holding a pile of it",
    names(CraftPanel:GetRows({ sortBy = "profit" })),
    "Rough Sharpening Stone, Copper Chain Belt, Brown Linen Shirt")

  ANALYSIS[101].profit, ANALYSIS[101].stockDivisor = 5000, nil
end

--------------------------------------------------------------------------------
-- The limit set in Settings
--------------------------------------------------------------------------------

do
  ANALYSIS[102].atPostLimit = true
  ANALYSIS[102].stock, ANALYSIS[102].postLimit, ANALYSIS[102].postRoom = 10, 10, 0

  check("a craft at its limit is not suggested",
    names(CraftPanel:GetRows({ sortBy = "profit" })),
    "Copper Chain Belt, Brown Linen Shirt")

  -- Searching for a recipe by name is not asking for a suggestion, and a pane
  -- that swallowed the very thing you just typed would read as broken.
  check("but searching for it by name still finds it",
    names(CraftPanel:GetRows({ search = "sharpening" })), "Rough Sharpening Stone")

  -- Turning the setting off is meant to show them marked, not hide them.
  SETTINGS.hideAtPostLimit = false

  check("with hiding turned off it is shown instead",
    names(CraftPanel:GetRows({ sortBy = "profit" })),
    "Rough Sharpening Stone, Copper Chain Belt, Brown Linen Shirt")

  local row
  for _, line in ipairs(CraftPanel:GetRows({})) do
    if line.recipeID == 102 then row = line end
  end

  check("and marked, so it is obvious why it sits there", row.atPostLimit, true)
  check("with no room left to queue into", row.roomInCrafts, 0)

  SETTINGS.hideAtPostLimit = true

  -- Room is in items but this pane queues crafts, and one craft can make
  -- several. Twelve items of room on a recipe yielding five is two crafts,
  -- not twelve -- that arithmetic is what turns a limit of 10 into 50.
  ANALYSIS[102].atPostLimit = false
  ANALYSIS[102].postRoom = 12
  RECIPES[102].quantityMin = 5

  local stone
  for _, line in ipairs(CraftPanel:GetRows({})) do
    if line.recipeID == 102 then stone = line end
  end

  check("room is converted from items into crafts", stone.roomInCrafts, 2)

  -- Rounded down, but never to nothing: room left over should not refuse the
  -- smallest thing you can actually make.
  ANALYSIS[102].postRoom = 3

  for _, line in ipairs(CraftPanel:GetRows({})) do
    if line.recipeID == 102 then stone = line end
  end

  check("a part-craft of room still allows one", stone.roomInCrafts, 1)

  -- No limit set at all is the default, and must stay entirely out of the way.
  ANALYSIS[102].postRoom = nil
  RECIPES[102].quantityMin = nil

  for _, line in ipairs(CraftPanel:GetRows({})) do
    if line.recipeID == 102 then stone = line end
  end

  check("no limit set means no clamp at all", stone.roomInCrafts, nil)

  ANALYSIS[102].atPostLimit, ANALYSIS[102].stock = nil, nil
  ANALYSIS[102].postLimit = nil
end

--------------------------------------------------------------------------------
-- What a row carries
--------------------------------------------------------------------------------

QUEUED[101] = { recipeID = 101, quantity = 4 }

do
  local rows = CraftPanel:GetRows({ search = "copper" })
  local row = rows[1]

  check("a queued craft reports how many are already on the queue",
    row.queued, 4)
  check("and how many the materials in the bags still cover",
    row.craftable, 3)
  check("and what one is worth", row.profit, 5000)

  -- Nothing queued must read as zero rather than nil: the row text formats it.
  local stone = CraftPanel:GetRows({ search = "sharpening" })[1]
  check("an unqueued craft reports zero rather than nothing", stone.queued, 0)

  -- The reason is what the row says instead of a price, so it has to survive.
  local shirt = CraftPanel:GetRows({ search = "shirt" })[1]
  check("an unpriced craft carries the reason it has no price",
    shirt.reason, "output has no price data")
  check("and is not claimed to be priceable", shirt.priceable, false)
end

QUEUED[101] = nil

--------------------------------------------------------------------------------
-- Craft next is scoped to the window you are standing at
--------------------------------------------------------------------------------

-- This is the bug the first in-game screenshot caught: Enchanting open, and
-- the button offering "Craft 24x Bolt of Linen Cloth". CraftRecipe on a recipe
-- the open window does not have fails silently on this client, so the button
-- would have done nothing at all and looked identical to a dead one.
do
  -- 101 and 102 are the open profession's; 501 is another profession's.
  QUEUE_ORDER = {
    { recipeID = 501, quantity = 24 },
    { recipeID = 102, quantity = 2 },
  }
  READY = { [501] = true, [102] = true }

  _G.C_TradeSkillUI = { GetAllRecipeIDs = function() return { 101, 102 } end }

  local entry, elsewhere = CraftPanel:GetNextReadyHere()

  check("skips a ready craft belonging to another profession",
    entry and entry.recipeID, 102)
  check("and counts the one it skipped, so the button can say why",
    elsewhere, 1)

  -- Nothing here to make, but the queue is not idle either. Saying "need
  -- materials" would be a lie about a craft whose materials are in the bags.
  QUEUE_ORDER = { { recipeID = 501, quantity = 24 } }

  entry, elsewhere = CraftPanel:GetNextReadyHere()
  check("nothing ready at this window offers nothing", entry, nil)
  check("but reports that the queue is not idle", elsewhere, 1)

  -- A craft that is not ready anywhere is not counted as ready elsewhere.
  READY = {}
  entry, elsewhere = CraftPanel:GetNextReadyHere()
  check("a craft short of materials is not 'ready elsewhere'", elsewhere, 0)

  -- Order is the queue's, not the recipe list's: the first workable entry wins.
  QUEUE_ORDER = {
    { recipeID = 102, quantity = 1 },
    { recipeID = 101, quantity = 1 },
  }
  READY = { [101] = true, [102] = true }

  check("takes the first workable entry in queue order",
    CraftPanel:GetNextReadyHere().recipeID, 102)

  -- No open set means the client would not say. Falling back to the first
  -- ready craft matches what the Queue tab does, rather than refusing to work.
  _G.C_TradeSkillUI = nil
  QUEUE_ORDER = { { recipeID = 501, quantity = 24 } }
  READY = { [501] = true }

  check("client will not say which profession: offers it anyway",
    CraftPanel:GetNextReadyHere().recipeID, 501)

  QUEUE_ORDER, READY = {}, {}
end

--------------------------------------------------------------------------------
-- Docking
--------------------------------------------------------------------------------

-- The pane is as tall as the window it is docked to.
local function Frame(bottom, height)
  return {
    GetTop = function() return bottom + height end,
    GetBottom = function() return bottom end,
  }
end

check("the pane takes the profession window's height",
  CraftPanel:DesiredHeight(Frame(200, 540)), 540)

-- A window shorter than the floor would leave a pane with no usable rows.
check("a short profession window does not squeeze it to nothing",
  CraftPanel:DesiredHeight(Frame(200, 90)), 220)

-- A frame that has never been laid out reports no coordinates. No answer is
-- the right answer there: Attach falls back rather than setting a height of nil.
check("a frame with no coordinates yet gets no answer, not a wrong one",
  CraftPanel:DesiredHeight({
    GetTop = function() return nil end,
    GetBottom = function() return nil end,
  }), nil)

print("")
if failed > 0 then
  error(string.format("FAIL -- %d of %d craft pane checks wrong", failed, passed + failed))
end
print(string.format("PASS -- the craft pane lists and orders correctly (%d checks)", passed))
print("")
