-- Recipes Forever took out of the game (2026-11-07, a player's report):
-- Forever moved the healing potions from Alchemy to First Aid, so the
-- Classic Alchemy rows must not stay in the book, or Road to 300 sends
-- an alchemist to make a potion the game won't let them learn.
--
--   1. The real book plus the shipped Forever file has none of the
--      Classic healing potion recipes, nor the recipe items that taught them.
--   2. Forever's First Aid healing potions are there, under First Aid.
--   3. Recipes and items Forever kept are untouched.

local failures = 0
local function check(label, got, want)
  if got ~= want then
    failures = failures + 1
    print(string.format("  FAIL  %-60s got %s, wanted %s", label, tostring(got), tostring(want)))
  else
    print(string.format("  ok    %-60s %s", label, tostring(got)))
  end
end

local ns = {}
assert(loadfile(lfs_cwd .. "/Data/RecipeBook.lua"))("Blackthornes_TS", ns)
local book = ns.RECIPE_BOOK
check("the Classic book has Minor Healing Potion first", type(book.RECIPES[2330]), "table")
assert(loadfile(lfs_cwd .. "/Data/ForeverRecipes.lua"))("Blackthornes_TS", ns)

print("\nClassic healing potions are gone")
local GONE = {
  [2330] = "Minor Healing Potion", [2337] = "Lesser Healing Potion",
  [3447] = "Healing Potion", [7181] = "Greater Healing Potion",
  [11457] = "Superior Healing Potion", [17556] = "Major Healing Potion",
}
for id, name in pairs(GONE) do
  check(name .. " (Alchemy) left the book", book.RECIPES[id], nil)
end
for itemID, row in pairs(book.ITEMS) do
  if type(row) == "table" and GONE[row[1]] then
    check("recipe item " .. itemID .. " for a gone recipe left", nil, "gone")
  end
end

local alchemyHealing = 0
for _, row in pairs(book.RECIPES) do
  if type(row) == "table" and row[1] == 171 and type(row[7]) == "string"
      and row[7]:find("Healing Potion") and not row[7]:find("Discolored") then
    alchemyHealing = alchemyHealing + 1
  end
end
check("no Alchemy healing potion left at all", alchemyHealing, 0)

print("\nForever's First Aid potions")
local firstAid = 0
for id = 1244431, 1244436 do
  local row = book.RECIPES[id]
  if type(row) == "table" and row[1] == 129 and row[7]:find("Healing Potion") then
    firstAid = firstAid + 1
  end
end
check("six healing potions under First Aid", firstAid, 6)

print("\nwhat Forever kept")
local alchemy, others = 0, 0
for id, row in pairs(book.RECIPES) do
  if type(row) == "table" and id < 1000000 then
    if row[1] == 171 then alchemy = alchemy + 1 else others = others + 1 end
  end
end
check("Classic Alchemy recipes still listed", alchemy > 80, true)
check("Classic recipes of other professions still listed", others > 500, true)

if failures > 0 then error(("%d gone recipe check(s) failed"):format(failures)) end
print("\n  Gone recipes: all checks passed")
