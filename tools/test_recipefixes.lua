-- Classic recipes put right from the Forever client's game tables
-- (2026-11-16, a player's report: Blacksmithing amounts were off).
--
--   1. Changed amounts read the client's materials.
--   2. A recipe Forever moved to another profession sits under it.
--   3. A recipe the client agrees with is untouched.

local failures = 0
local function check(label, got, want)
  if got ~= want then
    failures = failures + 1
    print(string.format("  FAIL  %-60s got %s, wanted %s", label, tostring(got), tostring(want)))
  else
    print(string.format("  ok    %-60s %s", label, tostring(got)))
  end
end

local function mats(row)
  local out = {}
  for i = 1, #row[6], 2 do out[#out + 1] = row[6][i] .. "x" .. row[6][i + 1] end
  return table.concat(out, " ")
end

local ns = {}
assert(loadfile(lfs_cwd .. "/Data/RecipeBook.lua"))("Blackthornes_TS", ns)
local book = ns.RECIPE_BOOK
local untouched = book.RECIPES[2660] and mats(book.RECIPES[2660])
assert(loadfile(lfs_cwd .. "/Data/ForeverRecipes.lua"))("Blackthornes_TS", ns)

print("\nchanged amounts")
check("Rough Weightstone takes one Rough Stone", mats(book.RECIPES[3115]), "2835x1")
check("Runed Copper Pants takes 3 Copper Bars", mats(book.RECIPES[3324]):find("2320x3") ~= nil, true)

print("\nmoved profession")
check("Wildthorn Mail sits under Leatherworking", book.RECIPES[16650][1], 165)

print("\nuntouched")
check("Rough Sharpening Stone keeps its materials", book.RECIPES[2660] and mats(book.RECIPES[2660]), untouched)

if failures > 0 then error(("%d recipe fix check(s) failed"):format(failures)) end
print("\n  Recipe fixes: all checks passed")
