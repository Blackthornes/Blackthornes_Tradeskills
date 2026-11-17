-- Logic/Wishlist.lua, UI/Wishlist.lua's helpers and Butler:WishlistHere
-- outside WoW.
--
-- The recipe wishlist (the owner said build it, 2026-11-17). What must hold:
--   1. A star puts a recipe on the playing character's list, saved under
--      recipeWishlist[guid][recipeID]; a second click takes it off. Each
--      character has its own list.
--   2. With no GUID the client will read, a star does nothing and nothing
--      is written.
--   3. A starred recipe comes off once it is learned (NEW_RECIPE_LEARNED,
--      or the recipe book saying this character knows it), and chat says so.
--   4. At a vendor, its recipe items that teach a starred recipe are found
--      with their place in the list and price; a skill too low says so.
--   5. At a trainer, its lines are matched by spell ID or name; a line it
--      won't teach yet is read with its filter flipped and put back, and
--      gets no place to train by.
--   6. One chat line per vendor each login; none with the wishlist off.
--   7. Wishlist First puts starred rows first, in the order they had.
--   8. Butler:WishlistHere hands Butler a copy, nil when off or away.
--   9. Buy and Learn ask the game for one copy, by place, and only when
--      the place still holds that recipe.

-- Tests share one Lua state: every global set here is put back at the end.
local GLOBALS = { "UnitGUID", "C_Timer", "GetNumTrainerServices", "GetTrainerServiceInfo",
  "GetTrainerServiceCost", "GetTrainerServiceSkillReq", "IsTradeskillTrainer",
  "GetTrainerServiceTypeFilter", "SetTrainerServiceTypeFilter", "C_TooltipInfo",
  "BuyMerchantItem", "BuyTrainerService", "C_MerchantFrame", "C_Spell", "GetSpellInfo",
  "BlackthornesButler" }
local saved = {}
for _, key in ipairs(GLOBALS) do saved[key] = _G[key] end

local failures = 0
local function check(label, got, want)
  if got == want then
    print("  ok   " .. label)
  else
    failures = failures + 1
    print(("  FAIL %s: got %s, want %s"):format(label, tostring(got), tostring(want)))
  end
end

local ns = {}
ns.NewModule = function(name) local m = { moduleName = name } ns[name] = m return m end
local printed = {}
ns.Print = function(text) printed[#printed + 1] = text end
ns.Debug = function() end

local settings = { recipeWishlistOn = true }
ns.Config = {
  Get = function(_, key) return settings[key] end,
  Set = function(_, key, value) settings[key] = value end,
}
ns.db = {}

local guid = "Player-1-0000AAAA"
UnitGUID = function(unit)
  if unit == "player" then return guid end
  if unit == "npc" then return "Creature-0-1-2-3-4-5150-0000" end
end

-- Three recipes: two Blacksmithing ones a vendor and a trainer teach, and
-- one the book knows under its Classic ID 300 and the game as 3001.
local known = {}
local records = {
  [100] = { recipeID = 100, name = "Heavy Bronze Mace", profession = "Blacksmithing", skill = 110 },
  [200] = { recipeID = 200, name = "Patterned Bronze Bracers", profession = "Blacksmithing", skill = 120 },
  [3001] = { recipeID = 3001, name = "Golden Scale Coif", profession = "Blacksmithing", skill = 145 },
}
ns.RecipeBook = {
  Get = function(_, id)
    if id == 300 then return records[3001] end
    return records[id]
  end,
  ForItem = function(_, itemID)
    if itemID == 9100 then return records[100] end
    if itemID == 9300 then return records[3001] end
    if itemID == 9999 then return { recipeID = 777, name = "Not Starred" } end
  end,
  KnowsIt = function(_, record) return record ~= nil and known[record.recipeID] == true end,
}
local skill = 115
ns.Recipes = {
  GetLearnedProfessions = function() return { { name = "Blacksmithing", skillLevel = skill } } end,
  EnglishProfessionName = function(profession) return profession.name end,
}

local timers = {}
C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end }
local function RunTimers()
  local list = timers
  timers = {}
  for _, fn in ipairs(list) do fn() end
end

local redraws = 0
ns.UI = { RefreshActiveTab = function() redraws = redraws + 1 end }

assert(loadfile(lfs_cwd .. "/Logic/Wishlist.lua"))("Blackthornes_TS", ns)
local Wishlist = ns.Wishlist

print("\nstars")
check("nothing starred to start", Wishlist:Has(100), false)
check("a star goes on", Wishlist:Set(100, true), true)
check("and is saved under the GUID", ns.db.recipeWishlist[guid][100], true)
check("it reads back", Wishlist:Has(100), true)
check("the lists redraw", redraws > 0, true)
check("starring twice changes nothing", Wishlist:Set(100, true), false)
check("toggling takes it off", Wishlist:Toggle(100), true)
check("so it is gone", Wishlist:Has(100), false)
check("and gone from the save", ns.db.recipeWishlist[guid][100], nil)
Wishlist:Set(300, true)
check("a book ID is kept under the game's", ns.db.recipeWishlist[guid][3001], true)
check("and found by either", Wishlist:Has(300) and Wishlist:Has(3001), true)
Wishlist:Set(3001, false)

print("\none list per character")
Wishlist:Set(100, true)
guid = "Player-1-0000BBBB"
check("another character has its own list", Wishlist:Has(100), false)
guid = "Player-1-0000AAAA"
check("and the first keeps its own", Wishlist:Has(100), true)

print("\nno GUID, nothing written")
guid = nil
check("a star does nothing", Wishlist:Set(200, true), false)
check("nothing is read either", Wishlist:Has(100), false)
UnitGUID = function() error("secret") end
check("a GUID that raises writes nothing", Wishlist:Set(200, true), false)
UnitGUID = function(unit)
  if unit == "player" then return guid end
  if unit == "npc" then return "Creature-0-1-2-3-4-5150-0000" end
end
guid = "Player-1-0000AAAA"
check("so the list never got it", ns.db.recipeWishlist[guid][200], nil)

print("\nlearned comes off")
Wishlist:Set(200, true)
printed = {}
check("learning a starred recipe takes it off", Wishlist:OnLearned(200), true)
check("so it is gone", Wishlist:Has(200), false)
check("and chat says so", printed[1], "You learned Patterned Bronze Bracers. It's off your wishlist now.")
check("an unstarred one changes nothing", Wishlist:OnLearned(999), false)
Wishlist:Set(200, true)
known[200] = true
printed = {}
check("the book knowing it takes it off too", Wishlist:Prune(), 1)
check("and chat says so", #printed, 1)
known[200] = nil

print("\nat a vendor")
ns.Vendor = {
  isMerchantOpen = true,
  merchantRecipes = {
    [9300] = { gold = 5000, index = 7 },
    [9100] = { gold = 8000, index = 2 },
    [9999] = { gold = 100, index = 4 },
  },
  GetMerchantItemID = function(index)
    return ({ [2] = 9100, [7] = 9300, [4] = 9999 })[index]
  end,
}
Wishlist:Set(300, true)
printed = {}
Wishlist.told = {}
local here = Wishlist:ReadHere()
check("two starred recipes found", #here, 2)
check("in the vendor's order", here[1].itemID, 9100)
check("with its place", here[1].index, 2)
check("and its price", here[1].price, 8000)
check("it is a vendor's", here[1].kind, "vendor")
check("a skill high enough is not short", here[1].short, nil)
check("one too high says the skill", here[2].short, 145)
check("chat says how many", printed[1], "This vendor sells 2 recipes on your wishlist.")
Wishlist:ReadHere()
check("but only once a login", #printed, 1)
check("Here hands the list back", select(2, Wishlist:Here()), "vendor")

print("\nbuying one")
local boughtAt, boughtCount
BuyMerchantItem = function(index, count) boughtAt, boughtCount = index, count end
C_MerchantFrame = { GetItemInfo = function() return {} end }
check("Buy asks for one copy", Wishlist:Buy(here[1]), true)
check("at its place", boughtAt, 2)
check("just one", boughtCount, 1)
boughtAt = nil
ns.Vendor.GetMerchantItemID = function() return 1234 end
check("a list that moved buys nothing", Wishlist:Buy(here[1]), false)
check("so nothing was bought", boughtAt, nil)

print("\nButler's copy")
assert(loadfile(lfs_cwd .. "/Logic/Butler.lua"))("Blackthornes_TS", ns)
local copy = ns.Butler:WishlistHere()
check("Butler gets the list", copy and #copy, 2)
check("as a copy", copy and copy[1] ~= Wishlist.here[1], true)
check("with what it needs to buy", copy and copy[1].index, 2)
settings.recipeWishlistOn = false
check("off, Butler gets nil", ns.Butler:WishlistHere(), nil)
settings.recipeWishlistOn = true
ns.Vendor.isMerchantOpen = false
Wishlist:ReadHere()
check("away from a vendor, nil", ns.Butler:WishlistHere(), nil)
local realHere = Wishlist.Here
Wishlist.Here = function() error("boom") end
check("never raises", ns.Butler:WishlistHere(), nil)
Wishlist.Here = realHere

print("\nat a trainer")
Wishlist:Set(200, true)
local filterOn = false
local lines = {
  -- shown: index 1 header, 2 Bronze Mace (not starred), 3 Patterned Bronze Bracers
  shown = { { "Blacksmithing", nil, "header" }, { "Bronze Mace", nil, "available" },
    { "Patterned Bronze Bracers", nil, "available" } },
  -- with the filter on, Golden Scale Coif shows too, first
  all = { { "Blacksmithing", nil, "header" }, { "Golden Scale Coif", nil, "unavailable" },
    { "Bronze Mace", nil, "available" }, { "Patterned Bronze Bracers", nil, "available" } },
}
local function Lines() return filterOn and lines.all or lines.shown end
IsTradeskillTrainer = function() return true end
GetNumTrainerServices = function() return #Lines() end
GetTrainerServiceInfo = function(index) local l = Lines()[index] return l[1], l[2], l[3] end
GetTrainerServiceCost = function(index) return index * 1000 end
GetTrainerServiceTypeFilter = function(kind) return kind == "unavailable" and filterOn end
local flips = 0
SetTrainerServiceTypeFilter = function(kind, on) flips = flips + 1 filterOn = on == 1 end
C_TooltipInfo = { GetTrainerService = function() return nil end }
skill = 125
Wishlist.trainerOpen = true
printed = {}
here = Wishlist:ReadHere()
check("both starred lines found", #here, 2)
check("the teachable one first", here[1].name, "Patterned Bronze Bracers")
check("with its place as shown", here[1].index, 3)
check("and its cost", here[1].price, 3000)
check("the hidden one has no place to train by", here[2].index, nil)
check("and says the skill it needs", here[2].short, 145)
check("the filter was put back", filterOn, false)
check("flipped once each way", flips, 2)
check("chat says a trainer teaches it",
  printed[1], "This trainer teaches 2 recipes on your wishlist.")
check("a class trainer is left alone", (function()
  IsTradeskillTrainer = function() return false end
  local list = Wishlist:ReadTrainer()
  IsTradeskillTrainer = function() return true end
  return #list
end)(), 0)

print("\nby spell ID")
C_TooltipInfo = { GetTrainerService = function(index) if index == 2 then return { id = 200 } end end }
lines.shown[2] = { "Bronzene Armschienen", nil, "available" }
here = Wishlist:ReadTrainer()
check("a line in another language is found by its spell", here[1].index, 2)
lines.shown[2] = { "Bronze Mace", nil, "available" }
C_TooltipInfo = { GetTrainerService = function() return nil end }

print("\nlearning one")
here = Wishlist:ReadTrainer()
local trainedAt
BuyTrainerService = function(index) trainedAt = index end
check("Learn trains it", Wishlist:Learn(here[1]), true)
check("at its place", trainedAt, 3)
trainedAt = nil
check("a line it can't teach yet is not tried", Wishlist:Learn(here[2]), false)
lines.shown[3] = { "Something Else", nil, "available" }
check("a list that moved trains nothing", Wishlist:Learn(here[1]), false)
check("so nothing was trained", trainedAt, nil)
Wishlist.trainerOpen = false

print("\nWishlist First and the card's words")
assert(loadfile(lfs_cwd .. "/UI/Wishlist.lua"))("Blackthornes_TS", ns)
local UI = ns.WishlistUI
local rows = { { recipeID = 1 }, { recipeID = 100 }, { recipeID = 5 }, { recipeID = 200 } }
local sorted = UI.StarredFirst(rows)
check("starred first", sorted[1].recipeID, 100)
check("in the order they had", sorted[2].recipeID, 200)
check("the rest after, as they were", sorted[3].recipeID .. "," .. sorted[4].recipeID, "1,5")
settings.recipeWishlistOn = false
check("off, the order is left alone", UI.StarredFirst(rows)[1].recipeID, 1)
check("off, no menu line", UI.MenuLine(100), nil)
settings.recipeWishlistOn = true
check("the menu offers to take it off", UI.MenuLine(100).text, "Take Off Wishlist")
check("or to add it", UI.MenuLine(5).text, "Add to Wishlist")
local Card = ns.WishlistCard
check("too low says the skill", Card.RightText({ short = 145, price = 10 }), "Learn at 145")
check("a vendor sells it anyway", Card.CanClick({ kind = "vendor", index = 4, short = 145 }), true)
check("a trainer won't teach it yet", Card.CanClick({ kind = "trainer", index = 4, short = 145 }), false)
check("one recipe reads as one", ns.Wishlist.CountText("vendor", 1), "This vendor sells a recipe on your wishlist.")
_G.BlackthornesButler = nil
check("without Butler the card shows", Card.ButlerShows(), false)
_G.BlackthornesButler = {}
check("an older Butler without the row leaves it showing", Card.ButlerShows(), false)
_G.BlackthornesButler = { Wishlist = {} }
check("Butler with the row takes over", Card.ButlerShows(), true)

print("\nchat with the wishlist off")
settings.recipeWishlistOn = false
Wishlist.told = {}
ns.Vendor.isMerchantOpen = true
ns.Vendor.GetMerchantItemID = function() return 9100 end
printed = {}
check("off, nothing is read", Wishlist:ReadHere(), nil)
check("and nothing said", #printed, 0)
settings.recipeWishlistOn = true

print("\nthe recipe's tooltip")
assert(loadfile(lfs_cwd .. "/UI/ItemTooltip.lua"))("Blackthornes_TS", ns)
local tip = ns.ItemTooltip
local shiftAllows = true
ns.TooltipShift = { Shows = function(_, key) return key ~= "recipe" or shiftAllows end }
local tipLines = {}
tip:AddWishlistLine(tipLines, 9100)
check("a starred recipe's item says so", tipLines[1] and tipLines[1][1], "On your wishlist")
tipLines = {}
tip:AddWishlistLine(tipLines, 9999)
check("an unstarred one says nothing", #tipLines, 0)
shiftAllows = false
tipLines = {}
tip:AddWishlistLine(tipLines, 9100)
check("it follows the recipe lines' Shift", #tipLines == 0 and tipLines.held, true)
shiftAllows = true
settings.recipeWishlistOn = false
tipLines = {}
tip:AddWishlistLine(tipLines, 9100)
check("off, no line", #tipLines, 0)
settings.recipeWishlistOn = true

for _, key in ipairs(GLOBALS) do _G[key] = saved[key] end

print("")
if failures > 0 then
  error(string.format("%d wishlist check(s) failed", failures))
end
print("  all wishlist checks passed")
