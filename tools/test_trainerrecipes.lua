-- Logic/TrainerRecipes.lua outside WoW (a player's report, 2026-11-19:
-- Road to 300 never offered Forever's new trainer recipes). What must hold:
--   1. Before a trainer is read, a Forever recipe with no trainer price is
--      not on the road (how the game failed).
--   2. A trainer's lines are kept by recipe ID, the tooltip's ID first,
--      else the one recipe with that name; hidden lines are read with the
--      filter flipped and put back.
--   3. The recipe book takes the trainer's price and skill; the road then
--      offers the recipe, learned from that profession's trainer.
--   4. The shipped table fills in for a character who never visited, and
--      the character's own visit wins.
--   5. Only a profession trainer is read.

local GLOBALS = { "time", "GetTime", "UnitFactionGroup", "GetRealZoneText", "GetLocale", "UnitLevel",
  "C_Timer", "C_Map", "C_TooltipInfo", "IsTradeskillTrainer", "GetNumTrainerServices",
  "GetTrainerServiceInfo", "GetTrainerServiceCost", "GetTrainerServiceSkillReq",
  "GetTrainerServiceTypeFilter", "SetTrainerServiceTypeFilter" }
local saved = {}
for _, key in ipairs(GLOBALS) do saved[key] = _G[key] end

local failures = 0
local function check(label, got, want)
  if got ~= want then
    failures = failures + 1
    print(string.format("  FAIL  %-58s got %s, wanted %s", label, tostring(got), tostring(want)))
  else
    print(string.format("  ok    %-58s %s", label, tostring(got)))
  end
end

local function Fresh()
  local ns = {}
  ns.COLORS = setmetatable({}, { __index = function() return "ffffffff" end })
  ns.NewModule = function(name) local m = {} ns[name] = m return m end
  ns.Print = function() end
  ns.Debug = function() end
  ns.Config = { Get = function(_, k) return ({ auctionCut = 0.05, valueOwnedMaterials = true })[k] end,
    GetCharacterKey = function() return "me" end }
  ns.Util = { FormatMoney = tostring, HasFunction = function() return false end,
    GetItemLabel = function(id) return "item " .. id end, Uncolored = function(t) return t end,
    GetVendorSellPrice = function() return nil end }
  for _, f in ipairs({ "Data/RecipeBook.lua", "Data/ForeverRecipes.lua", "Data/LearnSpots.lua",
      "Data/ForeverTrainerRecipes.lua" }) do
    assert(loadfile(lfs_cwd .. "/" .. f))("Blackthornes_TS", ns)
  end
  ns.Prices = { GetValue = function() return 5 end, scanCount = 1 }
  ns.Vendor = { GetUnitPrice = function() return nil end, IsLimited = function() return false end,
    GetTable = function() return {} end }
  ns.Inventory = { changes = 1, GetBagCount = function() return 0 end, GetBankCount = function() return 0 end,
    GetCharacterBagCount = function() return 0 end }
  ns.Recipes = { GetAny = function() return nil end, GetAll = function() return {} end,
    GetAccountWide = function() return { [3275] = { knownBy = { "me" } } } end,
    GetShortCharacterName = function(_, k) return k end, GetLearnedProfessions = function() return {} end }
  ns.db = { characters = { me = { recipesCachedAt = 5 } } }
  ns.charDb = {}
  for _, f in ipairs({ "Logic/Cost.lua", "Logic/RecipeBook.lua", "Logic/TrainerRecipes.lua",
      "Logic/Waypoints.lua", "Logic/LearnNext.lua", "Logic/RoadPlan.lua" }) do
    assert(loadfile(lfs_cwd .. "/" .. f))("Blackthornes_TS", ns)
  end
  ns.LevelUp = { GetReturns = function() return nil end }
  return ns
end

time = function() return 1000 end
GetTime = time
UnitFactionGroup = function() return "Alliance" end
GetRealZoneText = function() return "Dun Morogh" end
GetLocale = function() return "enUS" end
UnitLevel = function() return 20 end
C_Timer = nil
C_Map = nil

local LESSER, POULTICE, HEAVY = 1244432, 1259342, 3276
local function OnRoad(ns, id)
  for _, c in ipairs(ns.RoadPlan:Candidates(129)) do
    if c.record.recipeID == id then return c end
  end
end

print("\nbefore a trainer is read")
local ns = Fresh()
check("the shipped table has Lesser Healing Potion", ns.FOREVER_TRAINER_RECIPES[LESSER] ~= nil, true)
-- As the game was before: nothing shipped, no trainer visited.
for id in pairs(ns.FOREVER_TRAINER_RECIPES) do ns.FOREVER_TRAINER_RECIPES[id] = nil end
ns.RecipeBook:Invalidate()
check("Lesser Healing Potion is not on the road", OnRoad(ns, LESSER), nil)
check("Heavy Linen Bandage is (the book has its price)", OnRoad(ns, HEAVY) ~= nil, true)

print("\nreading the trainer")
-- Thamner Pol's First Aid list: a header, Heavy Linen Bandage by name only,
-- Lesser Healing Potion by its tooltip ID, and Simple Poultice hidden
-- until the filter shows "unavailable" lines.
local filter = 0
local flips = {}
local lines = {
  { "Bandages", "header" },
  { "Heavy Linen Bandage", "available", 100, 40 },
  { "Lesser Healing Potion", "available", 150, 55, LESSER },
}
local hiddenLine = { "Simple Poultice", "unavailable", 250, 90, POULTICE }
local function Shown()
  local list = {}
  for _, l in ipairs(lines) do list[#list + 1] = l end
  if filter == 1 then list[#list + 1] = hiddenLine end
  return list
end
IsTradeskillTrainer = function() return true end
GetNumTrainerServices = function() return #Shown() end
GetTrainerServiceInfo = function(i) local l = Shown()[i] return l[1], nil, l[2] end
GetTrainerServiceCost = function(i) return Shown()[i][3] end
-- The game gives the skill's name first, then the skill asked for, then
-- whether it is met (a player's report, 2026-11-21: Road to 300 offered
-- Rugged Armor Kit at 211 while the trainer asked 225, since the name was
-- read as the skill and nothing was kept).
GetTrainerServiceSkillReq = function(i) return "Alchemy", Shown()[i][4], false end
GetTrainerServiceTypeFilter = function() return filter == 1 end
SetTrainerServiceTypeFilter = function(_, on) filter = on; flips[#flips + 1] = on end
C_TooltipInfo = { GetTrainerService = function(i) local id = Shown()[i][5] return id and { id = id } or nil end }

local changed = ns.TrainerRecipes:Read()
check("three lines kept", changed, 3)
check("the filter flipped on and back", table.concat(flips, ","), "1,0")
check("the filter is left as it was", filter, 0)
local store = ns.db.trainerRecipes
check("Lesser Healing Potion's price", store[LESSER] and store[LESSER].cost, 150)
check("Lesser Healing Potion's skill", store[LESSER] and store[LESSER].skill, 55)
check("Heavy Linen Bandage matched by name", store[HEAVY] and store[HEAVY].cost, 100)
check("Simple Poultice read from the hidden lines", store[POULTICE] and store[POULTICE].skill, 90)
check("the header is not kept", store[0], nil)
check("the plan's key moves", ns.TrainerRecipes.version, 1)
check("reading again changes nothing", ns.TrainerRecipes:Read(), 0)

print("\nthe book and the road")
local record = ns.RecipeBook:Get(LESSER)
check("the book takes the trainer's price", record.trainerCost, 150)
check("the book takes the trainer's skill", record.skill, 55)
local candidate = OnRoad(ns, LESSER)
check("Lesser Healing Potion is on the road", candidate ~= nil, true)
check("learned from a First Aid trainer", candidate and candidate.place and candidate.place.kind, "trainer")
check("at the trainer's price", candidate and candidate.place and candidate.place.price, 150)
check("orange from 55", ns.RoadPlan.Band(record, 55), "optimal")
check("Simple Poultice is on the road", OnRoad(ns, POULTICE) ~= nil, true)
local cands = ns.RoadPlan:Candidates(129)
for _, c in ipairs(cands) do c.price = ns.RoadPlan.Price(c.record) end
local plan = ns.RoadPlan:Plan({ line = 129, skill = 30, max = 150, level = 20, candidates = cands, owned = {} })
check("the road reaches 300", plan.stuck, nil)

print("\nthe shipped table")
local ns2 = Fresh()
for id in pairs(ns2.FOREVER_TRAINER_RECIPES) do ns2.FOREVER_TRAINER_RECIPES[id] = nil end
ns2.FOREVER_TRAINER_RECIPES[LESSER] = { 55, 160 }
ns2.RecipeBook:Invalidate()
check("a character who never visited gets it", ns2.RecipeBook:Get(LESSER).trainerCost, 160)
check("and it is on the road", OnRoad(ns2, LESSER) ~= nil, true)
ns2.db.trainerRecipes = { [LESSER] = { cost = 150, skill = 55 } }
ns2.RecipeBook:Invalidate()
check("the character's own visit wins", ns2.RecipeBook:Get(LESSER).trainerCost, 150)

print("\nrecipes a First Aid or Cooking window showed")
-- A player's report (2026-11-20): First Aid stopped at 82 with nothing
-- after it. Forever's window lists First Aid under a second skill line
-- (2942, Cooking 2939), and every recipe it showed kept that line, so no
-- trainer was found to teach Wool Bandage or Lesser Healing Potion.
local ns4 = Fresh()
ns4.Recipes.SKILL_LINE_PROFESSIONS = { [129] = "First Aid", [185] = "Cooking" }
ns4.Recipes.EnglishProfessionName = function(p) return type(p) == "table" and p.name or p end
ns4.db.seenRecipes = {
  [3277] = { name = "Wool Bandage", skillLineID = 2942, outputItemID = 3530, profession = "First Aid" },
  [LESSER] = { name = "Lesser Healing Potion", skillLineID = 2942, outputItemID = 858, profession = "First Aid" },
  [2546] = { name = "Dry Pork Ribs", skillLineID = 2939, outputItemID = 2687, profession = "Cooking" },
}
ns4.RecipeBook:Invalidate()
check("First Aid's second line is First Aid", ns4.RecipeBook.ClassicLine(2942), 129)
check("Cooking's second line is Cooking", ns4.RecipeBook.ClassicLine(2939), 185)
local wool = OnRoad(ns4, 3277)
check("Wool Bandage is on the road", wool ~= nil, true)
check("learned from a First Aid trainer", wool and wool.place and wool.place.kind, "trainer")
check("Lesser Healing Potion is on the road", OnRoad(ns4, LESSER) ~= nil, true)
local cands4 = ns4.RoadPlan:Candidates(129)
for _, c in ipairs(cands4) do c.price = ns4.RoadPlan.Price(c.record) end
local plan4 = ns4.RoadPlan:Plan({ line = 129, skill = 82, max = 150, level = 20, candidates = cands4, owned = {} })
local learnsWool = false
for _, step in ipairs(plan4.steps) do
  if not step.done and step.recipeID == 3277 and step.learn then learnsWool = true end
end
check("the road goes on past 82", plan4.stuck, nil)
check("and learns Wool Bandage on the way", learnsWool, true)
local ribs = ns4.RecipeBook:Get(2546)
check("a Cooking recipe has a trainer", ribs and ns4.LearnNext:Place(ribs) ~= nil, true)

print("\nRugged Armor Kit at 211 (a player's report, 2026-11-21)")
-- Forever's client tables say 205; the Feralas trainer asks 225. Once a
-- trainer line was read, the road waits for 225.
local ns5 = Fresh()
local RUGGED = 19058
check("the book alone says 205", ns5.RecipeBook:Get(RUGGED).skill, 205)
check("so it gives a point at 211", ns5.RoadPlan.Chance(ns5.RecipeBook:Get(RUGGED), 211) > 0, true)
IsTradeskillTrainer = function() return true end
GetNumTrainerServices = function() return 1 end
GetTrainerServiceInfo = function() return "Rugged Armor Kit", nil, "unavailable" end
GetTrainerServiceCost = function() return 5000 end
GetTrainerServiceSkillReq = function() return "Leatherworking", 225, false end
GetTrainerServiceTypeFilter = function() return true end
C_TooltipInfo = { GetTrainerService = function() return { id = RUGGED } end }
check("the trainer line is kept", ns5.TrainerRecipes:Read(), 1)
check("with the skill the trainer asks", ns5.db.trainerRecipes[RUGGED].skill, 225)
local rugged = ns5.RecipeBook:Get(RUGGED)
check("the book takes 225", rugged.skill, 225)
check("no point from it at 211", ns5.RoadPlan.Chance(rugged, 211), 0)
check("a point from it at 225", ns5.RoadPlan.Chance(rugged, 225) > 0, true)

print("\nonly a profession trainer")
local ns3 = Fresh()
IsTradeskillTrainer = function() return false end
check("a class trainer is not read", ns3.TrainerRecipes:Read(), 0)
check("nothing saved", ns3.db.trainerRecipes, nil)

for _, key in ipairs(GLOBALS) do _G[key] = saved[key] end
if failures > 0 then error(("%d trainer recipe check(s) failed"):format(failures)) end
print("\n  Trainer recipes: all checks passed")
