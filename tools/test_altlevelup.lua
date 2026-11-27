-- Logic/AltLevelUp.lua and Butler:AltLevelUp, :RecipeFor outside WoW.
--
-- Butler's "Send Level Up Materials to Alts:" and "Mail Recipes to Who Can
-- Learn Them:" (the owner said build it, 2026-11-27). What must hold:
--   1. An alt's road to 300, from the recipes it knows, names what it
--      still needs and for which profession.
--   2. What the alt has (bags, bank, mail, on its way) comes off.
--   3. Only alts the one playing can mail: never itself, another realm,
--      the other side or another account's character.
--   4. With no GUID for the one playing, nobody.
--   5. An item two alts need goes to the one that needs most.
--   6. Kept until its key moves; a fresh table each time.
--   7. Can Learn: has the profession, doesn't know it; can learn now
--      first, then the higher skill; short when the skill is low.
--   8. RecipeFor: nobody on the account knows it, the one playing can't
--      learn it now, the alt doesn't already hold it.

local ns = {}
ns.NewModule = function(name) local m = {} ns[name] = m return m end
GetTime = function() return 100 end
time = function() return 1000 end
C_Timer = nil

local LINEN, WOOL, BAG = 2589, 2592, 5762
local ME, MIRA, TORV, HORDE, FAR, LINKED =
  "Player-1-ME", "Player-1-MIRA", "Player-1-TORV", "Player-1-HORDE", "Player-2-FAR", "Player-1-LINK"

local function prof(name, line, skill, max)
  return { name = name, skillLineID = line, skillLevel = skill, maxSkillLevel = max or 75, learned = true }
end

local records = {
  [ME] = { name = "Mae", realm = "Stone", faction = "Alliance", professions = { prof("Mining", 186, 120) }, recipes = {} },
  [MIRA] = { name = "Mira", surname = "Ashvale", realm = "Stone", faction = "Alliance", level = 20,
    professions = { prof("Tailoring", 197, 40) }, recipes = { [100] = {}, [101] = {} } },
  [TORV] = { name = "Torvek", surname = "Stonebrew", realm = "Stone", faction = "Alliance", level = 30,
    professions = { prof("Tailoring", 197, 162, 225) }, recipes = { [101] = {} } },
  [HORDE] = { name = "Grosh", realm = "Stone", faction = "Horde", professions = { prof("Tailoring", 197, 40) },
    recipes = { [100] = {} } },
  [FAR] = { name = "Far", realm = "Other", faction = "Alliance", professions = { prof("Tailoring", 197, 40) },
    recipes = { [100] = {} } },
  [LINKED] = { name = "Lin", realm = "Stone", faction = "Alliance", linkedFrom = "Mae",
    professions = { prof("Tailoring", 197, 40) }, recipes = { [100] = {} } },
}
local me = ME
ns.db = { characters = records, queueMail = { sent = {} } }
ns.Config = { GetCharacterKey = function() return me end, Get = function() return nil end }
ns.Characters = {
  IsPlaying = function(_, key) return key == me end,
  Same = function(_, a, b) return a == b end,
  CanMail = function(_, a, b)
    local x, y = records[a], records[b]
    return x.realm == y.realm and x.faction == y.faction
  end,
}
ns.Recipes = {
  EnglishProfessionName = function(p) return type(p) == "table" and p.name or p end,
  GetShortCharacterName = function(_, key)
    local r = records[key]
    return r.surname and (r.name .. " " .. r.surname) or r.name
  end,
  IsDropped = function() return false end,
  GetLearnedProfessions = function() return records[me].professions end,
  SKILL_LINE_PROFESSIONS = {},
}
local inFlight = {}
ns.QueueMail = { InFlight = function(_, key, itemID) return (inFlight[key] or {})[itemID] or 0 end }

-- Bolt of Linen Cloth: orange to 50, grey at 80. Wool bolt: 75 to 125.
local BOOK = {
  [100] = { recipeID = 100, skillLineID = 197, profession = "Tailoring", skill = 1, yellow = 50, grey = 80,
    name = "Bolt of Linen Cloth", bookName = "Bolt of Linen Cloth", reagents = { { itemID = LINEN, quantity = 2 } } },
  [101] = { recipeID = 101, skillLineID = 197, profession = "Tailoring", skill = 75, yellow = 100, grey = 125,
    name = "Bolt of Woolen Cloth", bookName = "Bolt of Woolen Cloth", reagents = { { itemID = WOOL, quantity = 3 } } },
  [200] = { recipeID = 200, skillLineID = 197, profession = "Tailoring", skill = 115,
    name = "Red Woolen Bag", reagents = { { itemID = WOOL, quantity = 3 } } },
}
local knownBy = {}
ns.RecipeBook = {
  ClassicLine = function(id) return id end,
  GetAll = function() return BOOK end,
  WhoKnows = function(_, r) return knownBy[r.recipeID] or {} end,
  KnowsIt = function(_, r) for _, k in ipairs(knownBy[r.recipeID] or {}) do if k == me then return true end end return false end,
  ForItem = function(_, itemID) if itemID == BAG then return BOOK[200] end end,
}

assert(loadfile(lfs_cwd .. "/Logic/RoadPlan.lua"))("Blackthornes_TS", ns)
ns.RoadPlan.Price = function(record)
  local reagents, cost = {}, 0
  for _, r in ipairs(record.reagents) do
    reagents[#reagents + 1] = { itemID = r.itemID, quantity = r.quantity, unit = 10 }
    cost = cost + 10 * r.quantity
  end
  return { cost = cost, reagents = reagents, materials = 1 }
end
assert(loadfile(lfs_cwd .. "/Logic/AltLevelUp.lua"))("Blackthornes_TS", ns)
assert(loadfile(lfs_cwd .. "/Logic/Butler.lua"))("Blackthornes_TS", ns)
local Alt, Butler = ns.AltLevelUp, ns.Butler

local failures = 0
local function check(label, got, want)
  if got == want then
    print("  ok   " .. label)
  else
    failures = failures + 1
    print(("  FAIL %s: got %s, want %s"):format(label, tostring(got), tostring(want)))
  end
end

-- 3.
local names = {}
for _, alt in ipairs(Alt.Alts()) do names[#names + 1] = alt.name end
table.sort(names)
check("only alts on this realm and side, not linked", table.concat(names, ","), "Mira Ashvale,Torvek Stonebrew")

-- 1.
local needs = Butler:AltLevelUp()
local linen = needs and needs[LINEN]
check("Mira's road needs Linen", linen and linen.to, "Mira Ashvale")
check("for Tailoring", linen and linen.profession, "Tailoring")
local full = linen and linen.count or 0
check("a real number of it", full > 20, true)

-- 5. Wool: Mira needs some at 75 to 125, Torvek is past 125 (grey).
check("Wool to the one who needs most", needs and needs[WOOL] and needs[WOOL].to, "Mira Ashvale")

-- 6.
needs[LINEN].count = 1
check("a fresh table each time", Butler:AltLevelUp()[LINEN].count, full)

-- 2.
records[MIRA].inventory = { [LINEN] = 10 }
records[MIRA].inventoryAt = 2
check("bags come off", Butler:AltLevelUp()[LINEN].count, full - 10)
records[MIRA].bank, records[MIRA].mail = { [LINEN] = 4 }, { [LINEN] = 1 }
records[MIRA].bankAt = 2
check("bank and mail come off", Butler:AltLevelUp()[LINEN].count, full - 15)
inFlight[MIRA] = { [LINEN] = 5 }
ns.db.queueMail.sent[MIRA] = { { itemID = LINEN, count = 5 } }
check("what is on its way comes off", Butler:AltLevelUp()[LINEN].count, full - 20)
records[MIRA].inventory = { [LINEN] = 999 }
records[MIRA].inventoryAt = 3
check("nothing once it has enough", Butler:AltLevelUp()[LINEN], nil)

-- 4.
me = "Mae-Stone"
check("no GUID, nobody", next(Butler:AltLevelUp()), nil)
me = ME

-- 7.
local can = Alt:CanLearn(BOOK[200])
check("two alts can learn the bag", #can, 2)
check("the one who can learn it now first", can[1] and can[1].name, "Torvek Stonebrew")
check("with its skill", can[1] and can[1].skill, 162)
check("the other is short", can[2] and can[2].short, true)
records[TORV].recipes[200] = {}
can = Alt:CanLearn(BOOK[200])
check("an alt who knows it is left out", #can == 1 and can[1].name, "Mira Ashvale")
records[TORV].recipes[200] = nil

-- 8.
local recipe = Butler:RecipeFor(BAG)
check("the bag goes to Torvek", recipe and recipe.to, "Torvek Stonebrew")
check("who can learn it now", recipe and recipe.now, true)
records[TORV].inventory = { [BAG] = 1 }
recipe = Butler:RecipeFor(BAG)
check("an alt holding one already is passed over", recipe and recipe.to, "Mira Ashvale")
check("Mira must wait", recipe and recipe.now, false)
check("at the skill it needs", recipe and recipe.skill, 115)
records[TORV].inventory = nil
knownBy[200] = { TORV }
check("someone on the account knows it: left alone", Butler:RecipeFor(BAG), nil)
knownBy[200] = nil
records[ME].professions = { prof("Tailoring", 197, 120) }
check("the one playing can learn it now: kept here", Butler:RecipeFor(BAG), nil)
records[ME].professions = { prof("Mining", 186, 120) }
check("not a recipe: nothing", Butler:RecipeFor(LINEN), nil)

-- Smooth play: with timers, the first answer is nil and comes a few
-- recipes a frame; Butler is told once a new one is in.
local queued, told = {}, 0
C_Timer = { After = function(_, fn) queued[#queued + 1] = fn end }
_G.BlackthornesButler = { Verdicts = { Changed = function() told = told + 1 end } }
Alt:Forget()
Alt.BUDGET = 1
check("nil while it is worked out", Butler:AltLevelUp(), nil)
check("asked again, still one job", #queued, 1)
Butler:AltLevelUp()
check("no second job for the same key", #queued, 1)
local runs = 0
while #queued > 0 and runs < 100 do
  local fn = table.remove(queued, 1)
  fn()
  runs = runs + 1
end
check("worked out over a few frames", runs > 1, true)
check("Butler was told", told, 1)
check("the answer is in", Butler:AltLevelUp()[WOOL] ~= nil, true)
C_Timer, _G.BlackthornesButler = nil, nil

if failures > 0 then error(failures .. " check(s) failed") end
print("All AltLevelUp checks passed.")
