-- Logic/Butler.lua outside WoW: Advise's forEnchanting (2026-10-13).
--
-- A green this character can break, not crafted, whose likely material its
-- own Enchanting still lacks for the crafts that give a point every time,
-- is named for Butler. What must hold:
--   1. Orange recipes count up to their yellow, cheapest first, each for the
--      points the ones before do not reach.
--   2. What the character owns (bags, bank, mailbox) comes off; enough means
--      nothing is named.
--   3. Only greens, only when this character can break it, never crafted
--      gear, never a rare outcome.
--   4. The profession window's reading at this skill beats the book.

local now = 100
GetTime = function() return now end

local ns = {}
ns.NewModule = function(name) local m = {} ns[name] = m return m end

local SELF = "Player-1"
ns.db = {
  characters = {
    [SELF] = { name = "Mia", realm = "R", faction = "Alliance",
      professions = { { name = "Enchanting", skillLevel = 50 } } },
  },
}
ns.Config = { GetCharacterKey = function() return SELF end, Get = function() end }
ns.Prices = { GetValue = function() return nil end }
ns.Profit = { NetFromListing = function(_, _, unit) return unit end }
ns.Disenchanter = { Knows = function() return true end }
ns.Queue = { version = 0, GetAll = function() return {} end }
ns.QueueMail = { GetDeliveries = function() return {} end }

local DUST, ESSENCE, SHARD, ROD = 10940, 10938, 10978, 6217
local MATERIAL = { [DUST] = "Strange Dust", [ESSENCE] = "Lesser Magic Essence", [SHARD] = "Small Glimmering Shard" }

-- Items: 1 a green armour piece, 2 a green weapon, 3 a blue, 4 a crafted green,
-- 5 a green needing more skill than the character has.
local quality = { [1] = 2, [2] = 2, [3] = 3, [4] = 2, [5] = 2 }
local outcomes = {
  [1] = { { itemID = DUST, chance = 0.75, min = 1, max = 2 }, { itemID = ESSENCE, chance = 0.20, min = 1, max = 2 },
          { itemID = SHARD, chance = 0.05, min = 1, max = 1 } },
  [2] = { { itemID = ESSENCE, chance = 0.75, min = 1, max = 2 }, { itemID = DUST, chance = 0.20, min = 1, max = 2 } },
  [3] = { { itemID = SHARD, chance = 1.0, min = 1, max = 1 } },
  [4] = { { itemID = DUST, chance = 0.75, min = 1, max = 2 } },
  [5] = { { itemID = DUST, chance = 0.75, min = 1, max = 2 } },
}
ns.Disenchant = {
  GetItemFacts = function(_, itemID) return quality[itemID] and { quality = quality[itemID] } end,
  IsDisenchantable = function(_, itemID) return quality[itemID] ~= nil end,
  GetValue = function(_, itemID) return 100, nil, { facts = { skill = itemID == 5 and 100 or 1 } } end,
  GetOutcomes = function(_, itemID) return outcomes[itemID] end,
  IsMaterial = function(_, itemID) return MATERIAL[itemID] ~= nil end,
  MaterialName = function(_, itemID) return MATERIAL[itemID] end,
}

-- Known recipes: A (dust 1, rod 1) orange to 55, cheap; B (dust 2, essence 1)
-- orange to 70, dearer; C green already; D tailoring.
local recipes = {
  [101] = { name = "Enchant Bracer - Minor Health", skillLineID = 333,
    reagents = { { itemID = DUST, quantity = 1 }, { itemID = ROD, quantity = 1 } } },
  [102] = { name = "Enchant Chest - Minor Mana", skillLineID = 2940,
    reagents = { { itemID = DUST, quantity = 2 }, { itemID = ESSENCE, quantity = 1 } } },
  [103] = { name = "Enchant Boots - Minor Speed", skillLineID = 333,
    reagents = { { itemID = SHARD, quantity = 1 } } },
  [104] = { name = "Linen Bolt", skillLineID = 197,
    reagents = { { itemID = DUST, quantity = 9 } } },
}
local book = { [101] = { yellow = 55 }, [102] = { yellow = 70 }, [103] = { yellow = 40 }, [104] = { yellow = 99 } }
local crafted = { [4] = true }
ns.Recipes = {
  SKILL_LINE_PROFESSIONS = { [333] = "Enchanting", [2940] = "Enchanting", [197] = "Tailoring" },
  GetAll = function() return recipes end,
  GetShortCharacterName = function(_, key) return ns.db.characters[key].name end,
}
ns.RecipeBook = {
  Get = function(_, recipeID) return book[recipeID] end,
  IsCrafted = function(_, itemID) return crafted[itemID] == true end,
}
local costs = { [101] = 50, [102] = 900, [103] = 10 }
ns.Cost = { GetCraftCost = function(_, recipeID)
  return costs[recipeID] and { priceable = true, total = costs[recipeID] } end }
local owned = {}
ns.Inventory = { changes = 0,
  GetOwnedCount = function(_, itemID) return owned[itemID] or 0 end,
  GetBankCount = function() return 0 end }

assert(loadfile(lfs_cwd .. "/Core/Characters.lua"))("Blackthornes_TS", ns)
assert(loadfile(lfs_cwd .. "/Logic/Butler.lua"))("Blackthornes_TS", ns)
local Butler = ns.Butler

local failures = 0
local function check(label, got, want)
  if got ~= want then
    failures = failures + 1
    print(string.format("  FAIL  %-52s got %s, wanted %s", label, tostring(got), tostring(want)))
  else
    print(string.format("  ok    %-52s %s", label, tostring(got)))
  end
end

local function For(itemID)
  local answer = Butler:Advise(itemID)
  return answer and answer.forEnchanting
end

print("\nwhat the next sure points still lack")
-- A: 50 to 55 is 5 crafts, 5 dust. B: 55 to 70 is 15 crafts, 30 dust and 15
-- essence. 35 dust in all.
local f = For(1)
check("armour gives dust, the likely outcome", f and f.material, DUST)
check("dust short: 5 for A, 30 for B", f and f.short, 35)
check("named for the cheapest orange craft using it", f and f.recipe, "Enchant Bracer - Minor Health")
check("the material's name", f and f.materialName, "Strange Dust")
check("about how many a disenchant gives", f and f.yield, 0.75 * 1.5)
local w = For(2)
check("a weapon gives essence first", w and w.material, ESSENCE)
check("essence short: 15 for B", w and w.short, 15)
check("named for B", w and w.recipe, "Enchant Chest - Minor Mana")

print("\nonly what it can count on")
check("a blue is not named", For(3), nil)
check("crafted gear is not named", For(4), nil)
check("needs more skill than the character has", For(5), nil)

print("\nwhat is owned comes off")
owned[DUST] = 35
Butler:Forget()
check("enough dust: armour still helps with its essence", For(1) and For(1).material, ESSENCE)
check("but the weapon still helps with essence", For(2) and For(2).material, ESSENCE)
owned[ESSENCE] = 20
Butler:Forget()
check("enough of both: nothing", For(2), nil)
check("nor for armour", For(1), nil)
owned[DUST], owned[ESSENCE] = 30, 20
Butler:Forget()
check("weapon's dust is only 20%: still counts", For(2) and For(2).material, DUST)

print("\nthe profession window's own reading")
owned = {}
recipes[101].skillUp = { tier = "medium", skill = 50 }
Butler:Forget()
-- A is yellow by the window's reading, so B covers 50 to 70: 20 crafts, 40 dust.
f = For(1)
check("A read yellow at this skill: only B", f and f.recipe, "Enchant Chest - Minor Mana")
check("B from the skill up: 40 dust", f and f.short, 40)
recipes[101].skillUp = { tier = "medium", skill = 30 }
Butler:Forget()
check("a reading at a lower skill gives way to the book", For(1) and For(1).short, 35)
recipes[101].skillUp = nil

print("\nnobody to level")
ns.db.characters[SELF].professions = {}
Butler:Forget()
check("no Enchanting: nothing", For(1), nil)
ns.db.characters[SELF].professions = { { name = "Enchanting", skillLevel = 70 } }
Butler:Forget()
check("every recipe yellow: nothing", For(1), nil)
ns.db.characters[SELF].professions = { { name = "Enchanting", skillLevel = 50 } }
ns.Disenchanter.Knows = function() return false end
Butler:Forget()
check("can't disenchant: nothing", For(1), nil)

print("")
if failures > 0 then
  error(string.format("%d forEnchanting check(s) failed", failures))
end
print("  all forEnchanting checks passed")
print("")
