-- Logic/Butler.lua's NextSkillUp and QueueSkillUp outside WoW.
--
-- Butler's "Cheapest Skill-Up" line (2026-10-19) shows the Level Up tab's
-- top pick for each profession. What must hold:
--   1. One entry a profession, the first fitting row in the Level Up order.
--   2. A profession at its max, or with only green or unread crafts, has none.
--   3. A craft with no price is passed over for the next one.
--   4. The cost is the real cost when there is one, so a craft that pays
--      comes back below 0.
--   5. queued follows the queue, and QueueSkillUp adds one.
--   6. Without Level Up, or when it raises, the answer is nil.
--   7. A recipe tagged with the skill-line ID that carries no levels still
--      finds its profession: through the other ID, or the last good read
--      Recipes keeps (Forever lists each profession under two IDs).

local ns = {}
ns.NewModule = function(name) local m = {} ns[name] = m return m end

local INFO = {
  [129] = { professionName = "First Aid", skillLevel = 52, maxSkillLevel = 75 },
  [197] = { professionName = "Tailoring", skillLevel = 61, maxSkillLevel = 75 },
  [186] = { professionName = "Mining", skillLevel = 75, maxSkillLevel = 75 },
  [164] = { professionName = "Blacksmithing", skillLevel = 10, maxSkillLevel = 75 },
}
C_TradeSkillUI = { GetProfessionInfoBySkillLineID = function(id) return INFO[id] end }
GetTime = function() return 100 end

local rows = {
  { recipeID = 1, skillLineID = 129, tier = "optimal", cost = nil, name = "Unpriced" },
  { recipeID = 2, skillLineID = 129, tier = "optimal", cost = 18, name = "Linen Bandage", outputItemID = 1251 },
  { recipeID = 3, skillLineID = 197, tier = "optimal", cost = 90, realCost = -35, name = "Brown Linen Pants", outputItemID = 4343 },
  { recipeID = 4, skillLineID = 129, tier = "optimal", cost = 5, name = "Later bandage" },
  { recipeID = 5, skillLineID = 186, tier = "optimal", cost = 1, name = "Smelt Copper" },
  { recipeID = 6, skillLineID = 164, tier = "easy", cost = 1, name = "Rough Sharpening Stone" },
}
ns.LevelUp = { GetRanked = function() return rows end }

local queued, added = {}, {}
ns.Queue = {
  version = 1,
  Find = function(_, id) if queued[id] then return 1, {} end end,
  Ensure = function(_, id, n) added[#added + 1] = id .. "x" .. n queued[id] = true return true end,
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

-- 1.
local list = Butler:NextSkillUp()
check("two professions", list and #list, 2)
check("by profession name", list[1].profession .. "," .. list[2].profession, "First Aid,Tailoring")
check("the top priced pick", list[1].name, "Linen Bandage")
check("its skill and max", list[1].skill .. "/" .. list[1].max, "52/75")
check("its item", list[1].itemID, 1251)

-- 2. Mining is maxed, Blacksmithing only has a green: neither shows.
local names = {}
for _, entry in ipairs(list) do names[entry.profession] = true end
check("a maxed profession has none", names.Mining, nil)
check("a green craft is not offered", names.Blacksmithing, nil)

-- 3.
check("an unpriced craft is passed over", list[1].recipeID, 2)

-- 4.
check("real cost below 0 when it pays", list[2].cost, -35)
check("plain cost otherwise", list[1].cost, 18)

-- 5.
check("not queued yet", list[1].queued, false)
check("queue one", Butler:QueueSkillUp(2), true)
check("one was asked for", added[1], "2x1")
check("queued now", Butler:NextSkillUp()[1].queued, true)
check("a bad recipe is refused", (Butler:QueueSkillUp("x")), false)

-- A fresh table each time.
Butler:NextSkillUp()[1].name = "changed"
check("a fresh table each time", Butler:NextSkillUp()[1].name, "Linen Bandage")

-- 7. Tailoring's 2948 and Enchanting's 333 read as not learned; 197 has
-- Tailoring's levels and Enchanting is only in the saved read.
INFO[2948] = { professionName = "Tailoring", skillLevel = 0, maxSkillLevel = 0 }
INFO[333] = { professionName = "Enchanting", skillLevel = 0, maxSkillLevel = 0 }
INFO[2940] = { professionName = "Enchanting", skillLevel = 0, maxSkillLevel = 0 }
ns.Recipes = {
  SKILL_LINE_PROFESSIONS = { [2948] = "Tailoring", [197] = "Tailoring", [2940] = "Enchanting", [333] = "Enchanting" },
  GetLearnedProfessions = function()
    return { { name = "Enchanting", skillLineID = 2940, skillLevel = 12, maxSkillLevel = 75, learned = true } }
  end,
}
rows = {
  { recipeID = 7, skillLineID = 2948, tier = "medium", cost = 40, name = "Enchanted Mageweave Pouch", outputItemID = 22246 },
  { recipeID = 8, skillLineID = 333, tier = "optimal", cost = 30, name = "Minor Mana Oil", outputItemID = 20745 },
}
ns.Queue.version = 10
list = Butler:NextSkillUp()
check("both professions found", list and #list, 2)
check("Enchanting from the saved read", list[1].profession .. " " .. list[1].skill .. "/" .. list[1].max, "Enchanting 12/75")
check("Tailoring through its other ID", list[2].profession .. " " .. list[2].skill .. "/" .. list[2].max, "Tailoring 61/75")
check("Tailoring's likely pick", list[2].name, "Enchanted Mageweave Pouch")
ns.Recipes = nil

-- 6.
ns.Queue.version = 2
ns.LevelUp.GetRanked = function() error("broken") end
check("a raising Level Up gives nil", Butler:NextSkillUp(), nil)
ns.LevelUp = nil
ns.Queue.version = 3
check("no Level Up gives nil", Butler:NextSkillUp(), nil)

if failures > 0 then
  error(("%d check(s) failed"):format(failures))
end
print("butlerskillup: all checks passed")
