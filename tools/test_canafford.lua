-- "Can afford" on the Level Up tab and its red note, outside WoW.
--
-- A player asked (2026-10-22, the owner said build it): the Level Up tab
-- picked the cheapest way up even when it cost more than the gold carried.
-- What must hold:
--   1. ToBuy is the cost of only the materials short, bank counted as owned;
--      0 when the bags and bank hold them all; nil when one short has no price.
--   2. ShortNote says how much is needed and how much is carried, only when
--      the missing materials cost more than the purse.
--   3. GetRanked with canAfford leaves out crafts the purse can't buy for, and
--      keeps one made from what is owned and one whose cost is not known.
--   4. Butler's NextSkillUp follows the box and passes toBuy on.

local ns = {}
ns.NewModule = function(name) local m = {} ns[name] = m return m end
ns.RegisterEvent = function() end
ns.Debug = function() end
ns.Util = { FormatMoney = function(c) return tostring(c) .. "c" end, HasFunction = function() return false end }

local config = {}
ns.Config = {
  Get = function(_, key) return config[key] end,
  GetCharacterKey = function() return "me" end,
}

local purse = 500
GetMoney = function() return purse end

local recipes = {
  [1] = { recipeID = 1, name = "Pricey", skillLineID = 1, outputItemID = 11, tier = "optimal" },
  [2] = { recipeID = 2, name = "Owned", skillLineID = 1, outputItemID = 12, tier = "optimal" },
  [3] = { recipeID = 3, name = "Unknown", skillLineID = 1, outputItemID = 13, tier = "optimal" },
  [4] = { recipeID = 4, name = "Cheap", skillLineID = 1, outputItemID = 14, tier = "optimal" },
}
local details = {
  -- 2 short at 400 each, 1 owned at 9999: 800 to buy.
  [1] = { priceable = true, total = 100, reagents = {
    { itemID = 101, quantity = 3, unitCost = 400, shortfall = 2, lineCost = 1200 },
    { itemID = 102, quantity = 1, unitCost = 9999, shortfall = 0, lineCost = 0 } } },
  -- Everything owned, worth a lot.
  [2] = { priceable = true, total = 5000, reagents = {
    { itemID = 103, quantity = 5, unitCost = 1000, shortfall = 0, lineCost = 5000 } } },
  -- Short of one with no price.
  [3] = { priceable = false, reagents = {
    { itemID = 104, quantity = 1, shortfall = 1 } } },
  -- 1 short at 300.
  [4] = { priceable = true, total = 300, reagents = {
    { itemID = 105, quantity = 1, unitCost = 300, shortfall = 1, lineCost = 300 } } },
}
ns.Recipes = {
  GetAll = function() return recipes end,
  GetAny = function(_, id) return recipes[id] end,
}
ns.Cost = { GetCraftCost = function(_, id) return details[id] end }
ns.SkillUp = { GetForRecipe = function(_, _, recipe) return { tier = recipe.tier } end }
ns.Profit = { GetCraftableCount = function() return 0 end }
ns.Prices = { GetValue = function() return nil end }
ns.Vendor = { GetUnitPrice = function() return nil end, GetSellPrice = function() return nil end }

assert(loadfile(lfs_cwd .. "/Logic/LevelUp.lua"))("Blackthornes_TS", ns)
local LevelUp = ns.LevelUp

local failures = 0
local function check(label, got, want)
  if got == want then
    print("  ok   " .. label)
  else
    failures = failures + 1
    print(("  FAIL %s: got %s, want %s"):format(label, tostring(got), tostring(want)))
  end
end

print("\nwhat buying the missing materials costs")
check("only what is short", LevelUp.ToBuy(details[1]), 800)
check("nothing short", LevelUp.ToBuy(details[2]), 0)
check("a short one with no price", LevelUp.ToBuy(details[3]), nil)
check("no detail", LevelUp.ToBuy(nil), nil)

print("\nthe red note")
local row = LevelUp:BuildRow(1)
check("the row carries it", row.toBuy, 800)
check("says need and have", LevelUp:ShortNote(row),
  "You need about 800c to buy what's missing. You have 500c.")
check("nothing when the purse covers it", LevelUp:ShortNote(LevelUp:BuildRow(4)), nil)
check("nothing when all is owned", LevelUp:ShortNote(LevelUp:BuildRow(2)), nil)
check("nothing when not known", LevelUp:ShortNote(LevelUp:BuildRow(3)), nil)
purse = 900
check("nothing once there's enough gold", LevelUp:ShortNote(row), nil)
purse = 500

print("\nCan afford")
local function Names(opts)
  local names = {}
  for _, r in ipairs(LevelUp:GetRanked(opts)) do names[r.name] = true end
  return names
end
local all = Names({})
check("off: the pricey one shows", all.Pricey, true)
local fits = Names({ canAfford = true })
check("on: the pricey one is left out", fits.Pricey, nil)
check("on: one made from what you own stays", fits.Owned, true)
check("on: one not known stays", fits.Unknown, true)
check("on: one you can pay for stays", fits.Cheap, true)

print("\nButler's Cheapest Skill-Up follows it")
C_TradeSkillUI = { GetProfessionInfoBySkillLineID = function()
  return { professionName = "Tailoring", skillLevel = 10, maxSkillLevel = 75 } end }
GetTime = function() return 100 end
ns.Queue = { version = 1, Find = function() return nil end }
assert(loadfile(lfs_cwd .. "/Logic/Butler.lua"))("Blackthornes_TS", ns)
-- Ranked by cost: Cheap (300) first, then Pricey's real cost 100 sorts first.
local first = ns.Butler:NextSkillUp()[1]
check("off: the cheapest pick", first.name, "Pricey")
check("its toBuy is passed on", first.toBuy, 800)
config.levelUpCanAfford = true
first = ns.Butler:NextSkillUp()[1]
check("on: a pick the purse covers", first.name ~= "Pricey", true)

if failures > 0 then error(failures .. " check(s) failed") end
print("\nall Can afford checks passed")
