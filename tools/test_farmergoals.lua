-- Logic/FarmerGoals.lua outside WoW.
--
-- The Gather tab's "Set goal" button hands a material to Blackthornes Farmer.
-- What must hold:
--   1. Without Farmer (or a Farmer too old to have goals) it is not offered,
--      and a click says so instead of throwing.
--   2. With Farmer, Farmer's own Goals:Set gets the item's plain name (no
--      colour codes, no link) and the amount the row needs.
--   3. Farmer's refusal is passed on in chat; a Farmer that throws does not
--      break Tradeskills.
--   4. Success prints, opens Farmer's Goals panel and plays a sound.

local printed = {}
local sounds = {}
PlaySound = function(kit) sounds[#sounds + 1] = kit end
SOUNDKIT = { IG_QUEST_LIST_COMPLETE = 878 }

local names = { [2770] = "Copper Ore" }
C_Item = { GetItemNameByID = function(id) return names[id] end }

local ns = {}
ns.COLORS = setmetatable({}, { __index = function() return "ffffffff" end })
ns.NewModule = function(name) local m = {} ns[name] = m return m end
ns.Print = function(text) printed[#printed + 1] = text end

local chunk = assert(loadfile(lfs_cwd .. "/Logic/FarmerGoals.lua"))
chunk("Blackthornes_TS", ns)

local FarmerGoals = ns.FarmerGoals
local failures = 0

local function check(label, got, want)
  if got ~= want then
    failures = failures + 1
    print(string.format("  FAIL  %-52s got %s, wanted %s",
      label, tostring(got), tostring(want)))
  else
    print(string.format("  ok    %-52s %s", label, tostring(got)))
  end
end

local function last() return printed[#printed] or "" end

print("\nwithout Farmer")
BlackthornesFarmer = nil
check("not offered", FarmerGoals:Available(), false)
check("a click does not throw", (FarmerGoals:SetGoal(2770, 40)), false)
check("and says why", last():find("not loaded", 1, true) ~= nil, true)

BlackthornesFarmer = { Goals = {} }
check("a Farmer with no goals is not offered", FarmerGoals:Available(), false)

print("\nwith Farmer")
local calls = {}
local shown = 0
local goals = {}
BlackthornesFarmer = {
  Goals = {
    Find = function(_, name) return goals[name] end,
    Set = function(_, name, amount)
      calls[#calls + 1] = { name = name, amount = amount }
      if amount < 1 then return nil, "the amount has to be 1 or more" end
      goals[name] = { item = name, target = amount, have = 6 }
      return goals[name]
    end,
  },
  GoalsUI = { Show = function() shown = shown + 1 end },
}
check("offered", FarmerGoals:Available(), true)

check("set", (FarmerGoals:SetGoal(2770, 40)), true)
check("Farmer got the plain name", calls[1].name, "Copper Ore")
check("and the amount needed", calls[1].amount, 40)
check("chat says set", last():find("Farmer goal set", 1, true) ~= nil, true)
check("chat says how many to go", last():find("You have 6, 34 to go", 1, true) ~= nil, true)
check("Goals panel opened", shown, 1)
check("sound played", sounds[#sounds], 878)

FarmerGoals:SetGoal(2770, 50)
check("second time says updated", last():find("Farmer goal updated", 1, true) ~= nil, true)

local before = #sounds
check("Farmer's refusal is a no", (FarmerGoals:SetGoal(2770, 0)), false)
check("and is passed on", last():find("amount has to be 1 or more", 1, true) ~= nil, true)
check("no sound for a refusal", #sounds, before)

check("an item the game has not named yet", (FarmerGoals:SetGoal(9999, 5)), false)
check("does not reach Farmer", #calls, 3)

print("\nset all goals at once")
names[2589] = "Linen Cloth"
names[2318] = "Light Leather"
calls, shown = {}, 0
before = #sounds
local count = FarmerGoals:SetGoals({
  { itemID = 2770, needed = 20 },
  { itemID = 2589, needed = 0 },     -- Farmer refuses this one
  { itemID = 2318, needed = 12 },
  { itemID = 9999, needed = 3 },     -- no name yet
})
check("two set", count, 2)
check("Farmer asked for the three it could name", #calls, 3)
check("in list order", calls[3].name, "Light Leather")
local all = table.concat(printed, "\n", #printed - 1)
check("summary names them", all:find("2 Farmer goals set:|r Copper Ore, Light Leather", 1, true) ~= nil, true)
check("and says what was not set, and why", all:find("Linen Cloth (the amount has to be 1 or more)", 1, true) ~= nil, true)
check("one sound for the lot", #sounds, before + 1)
check("Goals panel opened once", shown, 1)

before = #sounds
check("an empty list sets nothing", FarmerGoals:SetGoals({}), 0)
check("and says so", last():find("Nothing still needed", 1, true) ~= nil, true)
check("no sound for nothing", #sounds, before)

BlackthornesFarmer.Goals.Set = function() error("boom") end
check("a Farmer that throws is a no", (FarmerGoals:SetGoal(2770, 5)), false)
check("and a no for all", FarmerGoals:SetGoals({ { itemID = 2770, needed = 5 } }), 0)

BlackthornesFarmer = nil
check("set all without Farmer sets nothing", FarmerGoals:SetGoals({ { itemID = 2770, needed = 5 } }), 0)

print("")
if failures > 0 then
  error(string.format("%d Farmer goal check(s) failed", failures))
end
print("  all Farmer goal checks passed")
print("")
