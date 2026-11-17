-- Logic/Butler.lua's LevelUpMaterials outside WoW.
--
-- Butler's "Keep Level Up Materials:" (2026-11-17) asks which bag items
-- the Level Up list still needs. What must hold:
--   1. Materials of orange and yellow crafts, named by profession.
--   2. Green, grey and unread crafts add nothing.
--   3. A dropped profession adds nothing.
--   4. Cooking and First Aid, which only the Professions book lists, are
--      named from there.
--   5. An item two professions use is named the same way every time.
--   6. A fresh table each time; a new read of the recipes is seen.
--   7. Without Recipes, or when it raises, the answer is nil.

local ns = {}
ns.NewModule = function(name) local m = {} ns[name] = m return m end

local INFO = {
  [164] = { professionName = "Blacksmithing", skillLevel = 40, maxSkillLevel = 75 },
  [197] = { professionName = "Tailoring", skillLevel = 40, maxSkillLevel = 75 },
}
C_TradeSkillUI = { GetProfessionInfoBySkillLineID = function(id) return INFO[id] end }
GetTime = function() return 100 end
GetProfessions = function() return nil, nil, nil, nil, 5, 6 end
GetProfessionInfo = function(index)
  if index == 5 then return "Cooking", nil, 30, 75, nil, nil, 185 end
  if index == 6 then return "First Aid", nil, 20, 75, nil, nil, 129 end
end

local function recipe(line, tier, ...)
  local reagents = {}
  for _, id in ipairs({ ... }) do reagents[#reagents + 1] = { itemID = id, count = 1 } end
  return { skillLineID = line, skillUp = tier and { tier = tier } or nil, reagents = reagents }
end

local record = { recipesCachedAt = 1, recipes = {
  [1] = recipe(164, "optimal", 2840, 2835),       -- Copper Bar, Rough Stone
  [2] = recipe(164, "easy", 2842),                -- green: Silver Bar
  [3] = recipe(185, "medium", 769),               -- Cooking: Chunk of Boar Meat
  [4] = recipe(129, "optimal", 2589),             -- First Aid: Linen Cloth
  [5] = recipe(197, "optimal", 2589, 2320),       -- Tailoring: Linen Cloth, Coarse Thread
  [6] = recipe(202, "optimal", 4359),             -- dropped Engineering
  [7] = recipe(164, "trivial", 3576),             -- grey
  [8] = recipe(164, nil, 2770),                   -- never read
} }
ns.db = { characters = { me = record } }
ns.Config = { GetCharacterKey = function() return "me" end, Get = function() return nil end }
ns.Recipes = {
  SKILL_LINE_PROFESSIONS = {},
  GetAll = function() return record.recipes end,
  IsDropped = function(_, r) return r.skillLineID == 202 end,
}
ns.SkillUp = {
  GetForRecipe = function(_, _, r) return r.skillUp and { tier = r.skillUp.tier } or nil end,
}

local chunk = assert(loadfile(lfs_cwd .. "/Logic/Butler.lua"))
chunk("Blackthornes_TS", ns)
local Butler = ns.Butler

local failures = 0
local function check(label, got, want)
  if got == want then
    print("  ok   " .. label)
  else
    failures = failures + 1
    print(("  FAIL %s: got %s, want %s"):format(label, tostring(got), tostring(want)))
  end
end

local mats = Butler:LevelUpMaterials()
-- 1.
check("an orange craft's materials", mats and mats[2840], "Blacksmithing")
check("every material of it", mats and mats[2835], "Blacksmithing")
-- 2.
check("a green craft adds nothing", mats[2842], nil)
check("a grey craft adds nothing", mats[3576], nil)
check("an unread craft adds nothing", mats[2770], nil)
-- 3.
check("a dropped profession adds nothing", mats[4359], nil)
-- 4.
check("Cooking from the book", mats[769], "Cooking")
check("Tailoring's own material", mats[2320], "Tailoring")
-- 5.
check("shared cloth is named the same way", mats[2589], "First Aid")
-- 6.
mats[2840] = "changed"
check("a fresh table each time", Butler:LevelUpMaterials()[2840], "Blacksmithing")
record.recipes[1].skillUp.tier = "easy"
check("cached until the recipes are read again", Butler:LevelUpMaterials()[2840], "Blacksmithing")
record.recipesCachedAt = 2
check("a new read is seen", Butler:LevelUpMaterials()[2840], nil)
-- 7.
ns.Recipes.GetAll = function() error("boom") end
record.recipesCachedAt = 3
check("nil when it raises", Butler:LevelUpMaterials(), nil)
ns.Recipes = nil
check("nil without Recipes", Butler:LevelUpMaterials(), nil)

if failures > 0 then error(failures .. " check(s) failed") end
print("All LevelUpMaterials checks passed.")
