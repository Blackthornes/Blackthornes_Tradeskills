-- A German client, outside WoW.
--
-- The client names professions, spells and tooltip lines in its own
-- language, so a check against the English word quietly fails there. What
-- must hold, on a German client and still on an English one:
--   1. A saved profession is Enchanting by its skill line, by the English
--      name an old record carries, or by the name this client gives.
--   2. The best enchanter among the characters is found either way.
--   3. Blizzard's test profession is left out by its skill line.
--   4. Disenchant is heard by the client's own name for it.
--   5. A recipe item's "Benötigt Lederverarbeitung (140)" is read as
--      Leatherworking's skill.
--   6. "5 Aufladungen" is read as five charges.

local failures = 0
local function check(label, got, want)
  if got ~= want then
    failures = failures + 1
    print(string.format("  FAIL  %-52s got %s, wanted %s", label, tostring(got), tostring(want)))
  else
    print(string.format("  ok    %-52s %s", label, tostring(got)))
  end
end

-- What a German client answers.
local GERMAN = {
  [2940] = "Verzauberkunst", [333] = "Verzauberkunst",
  [2945] = "Lederverarbeitung", [165] = "Lederverarbeitung",
  [2948] = "Schneiderei", [197] = "Schneiderei",
  [2933] = "Testberuf", [2934] = "Testberuf",
}
local lines = { 2940, 333, 2945, 165, 2933 }
local levels = { [2940] = 225, [333] = 225, [2945] = 150, [165] = 150, [2933] = 1 }

-- Put back afterwards: every suite runs in the same Lua.
local GLOBALS = { "C_TradeSkillUI", "C_Spell", "C_TooltipInfo", "ITEM_MIN_SKILL", "ITEM_SPELL_CHARGES",
  "CreateFrame" }
local saved = {}
for _, key in ipairs(GLOBALS) do saved[key] = _G[key] end

C_TradeSkillUI = {
  GetAllProfessionTradeSkillLines = function() return lines end,
  GetProfessionInfoBySkillLineID = function(id)
    if not GERMAN[id] then return nil end
    return { professionName = GERMAN[id], skillLevel = levels[id] or 0, maxSkillLevel = levels[id] and 300 or 0 }
  end,
}

local function NewNs()
  local ns = {}
  ns.NewModule = function(name) local m = {} ns[name] = m return m end
  ns.RegisterCommand = function() end
  ns.RegisterEvent = function() end
  ns.COLORS = setmetatable({}, { __index = function() return "ffffffff" end })
  return ns
end

--------------------------------------------------------------------------------
print("\nprofessions by skill line")

local ns = NewNs()
ns.Util = { HasFunction = function() return false end }
ns.Compat = { Get = function() return { tradeskill = { hasAllProfessionLines = true } } end }
ns.Config = { GetCharacterKey = function() return "me" end }
assert(loadfile(lfs_cwd .. "/Data/Recipes.lua"))("Blackthornes_TS", ns)
local Recipes = ns.Recipes

check("German name with its skill line", Recipes.IsEnchanting({ name = "Verzauberkunst", skillLineID = 333 }), true)
check("the modern skill line too", Recipes.IsEnchanting({ name = "Verzauberkunst", skillLineID = 2940 }), true)
check("German name alone, as the client gives it", Recipes.IsEnchanting({ name = "Verzauberkunst" }), true)
check("an English record from before", Recipes.IsEnchanting({ name = "Enchanting" }), true)
check("another profession is not", Recipes.IsEnchanting({ name = "Schneiderei", skillLineID = 197 }), false)
check("nothing is not", Recipes.IsEnchanting(nil), false)
check("the English name of a German one", Recipes.EnglishProfessionName("Lederverarbeitung"), "Leatherworking")
check("an unknown name has none", Recipes.EnglishProfessionName("Irgendwas"), nil)

local names = {}
for _, profession in ipairs(Recipes:GetProfessions()) do names[#names + 1] = profession.name end
check("the test profession is left out by skill line", table.concat(names, ","), "Lederverarbeitung,Verzauberkunst")

--------------------------------------------------------------------------------
print("\nthe best enchanter")

ns.db = { characters = {
  me = { name = "Mia", professions = { { name = "Schneiderei", skillLineID = 197, skillLevel = 300 } } },
  de = { name = "Ana", professions = { { name = "Verzauberkunst", skillLineID = 333, skillLevel = 225 } } },
  old = { name = "Bo", professions = { { name = "Enchanting", skillLevel = 100 } } },
} }
ns.Util = { HasFunction = function() return false end }
assert(loadfile(lfs_cwd .. "/Logic/Disenchant.lua"))("Blackthornes_TS", ns)
local best, who = ns.Disenchant:GetBestEnchanter()
check("a German record counts", best, 225)
check("and is named", who, "Ana")
ns.db.characters.de = nil
best = ns.Disenchant:GetBestEnchanter()
check("an English record still counts", best, 100)

--------------------------------------------------------------------------------
print("\nDisenchant by the client's name")

local spellNames = { [13262] = "Entzaubern", [99999] = "Entzaubern", [133] = "Feuerball" }
C_Spell = { GetSpellName = function(id) return spellNames[id] end }
local logNs = NewNs()
logNs.Util = { HasFunction = function(path) return path == "C_Spell.GetSpellName" end }
assert(loadfile(lfs_cwd .. "/Logic/DisenchantLog.lua"))("Blackthornes_TS", logNs)
local IsDisenchant = logNs.DisenchantLog._IsDisenchant
check("the spell ID", IsDisenchant(13262), true)
check("another ID with the client's name", IsDisenchant(99999), true)
check("another spell is not", IsDisenchant(133), false)
spellNames[99998] = "Disenchant"
check("the English name still counts", IsDisenchant(99998), true)

--------------------------------------------------------------------------------
print("\na recipe item's skill")

ITEM_MIN_SKILL = "Benötigt %s (%d)"
local tooltips = { [2406] = { lines = {
  { leftText = "Muster: Feine Lederstiefel" },
  { leftText = "Benötigt Schneiderei (50)" },
  { leftText = "|cffff2020Benötigt Lederverarbeitung (140)|r" },
} } }
C_TooltipInfo = { GetItemByID = function(id) return tooltips[id] end }
local bookNs = NewNs()
bookNs.Recipes = Recipes
bookNs.Util = { HasFunction = function(path) return path == "C_TooltipInfo.GetItemByID" end }
bookNs.RECIPE_BOOK = {
  PROFESSIONS = { [165] = "Leatherworking", [197] = "Tailoring" },
  RECIPES = {}, ITEMS = {},
}
assert(loadfile(lfs_cwd .. "/Logic/RecipeBook.lua"))("Blackthornes_TS", bookNs)
local skill, profession = bookNs.RecipeBook:ReadSkill(2406, "Leatherworking")
check("the German line is read", skill, 140)
check("as the book's profession", profession, "Leatherworking")
ITEM_MIN_SKILL = "Requires %s (%d)"
tooltips[2406].lines[3].leftText = "Requires Leatherworking (75)"
skill = bookNs.RecipeBook:ReadSkill(2406, "Leatherworking")
check("an English line still is", skill, 75)

--------------------------------------------------------------------------------
print("\ncharges")

-- Util makes a worker frame as it loads.
CreateFrame = function()
  return setmetatable({}, { __index = function() return function() end end })
end

local function SellPriceWith(chargesLine, format)
  ITEM_SPELL_CHARGES = format
  local utilNs = NewNs()
  assert(loadfile(lfs_cwd .. "/Core/Util.lua"))("Blackthornes_TS", utilNs)
  C_TooltipInfo = { GetItemByID = function() return { lines = {
    { leftText = chargesLine }, { type = 11, price = 500 },
  } } end }
  local _, _, charges = utilNs.Util.GetTooltipSellPrice(1)
  return charges
end
check("German plural", SellPriceWith("5 Aufladungen", "%d |4Aufladung:Aufladungen;"), 5)
check("German singular", SellPriceWith("1 Aufladung", "%d |4Aufladung:Aufladungen;"), 1)
check("English with the client's format", SellPriceWith("3 Charges", "%d |4Charge:Charges;"), 3)
check("English without it", SellPriceWith("2 Charges", nil), 2)
check("not a charges line", SellPriceWith("Benötigt Stufe 5", "%d |4Aufladung:Aufladungen;"), nil)

for _, key in ipairs(GLOBALS) do _G[key] = saved[key] end

if failures > 0 then error(("%d German client check(s) failed"):format(failures)) end
print("\n  German client: all checks passed")
