-- Logic/Butler.lua outside WoW.
--
-- Blackthornes Butler asks Butler:Advise(itemID) once per bag item. What
-- must hold:
--   1. The auction value is per unit, after the cut and the deposit; greys
--      and bind-on-pickup gear have none.
--   2. Demand "high" is fast, "low" is slow, anything else unknown.
--   3. Disenchant value, whether the character playing can break it, and
--      who can when it cannot.
--   4. The queue's need from these bags, and the alt to mail it to.
--   5. The queue, mail plan and enchanters are read once a burst, not once
--      an item.
--   6. Anything that raises gives nil, never an error.

local now = 100
GetTime = function() return now end

local ns = {}
ns.NewModule = function(name) local m = {} ns[name] = m return m end

local SELF, ALT, ALT2, OTHER = "Player-1", "Player-2", "Player-3", "Player-4"
ns.db = {
  characters = {
    [SELF] = { name = "Mia", realm = "R", faction = "Alliance", professions = {} },
    [ALT] = { name = "Ana", realm = "R", faction = "Alliance",
      professions = { { name = "Enchanting", skillLevel = 150 } } },
    [ALT2] = { name = "Bo", realm = "R", faction = "Alliance",
      professions = { { name = "Enchanting", skillLevel = 300 } }, linkedFrom = "other" },
    [OTHER] = { name = "Cy", realm = "R", faction = "Horde",
      professions = { { name = "Enchanting", skillLevel = 300 } } },
  },
}

ns.Config = {
  GetCharacterKey = function() return SELF end,
  Get = function(_, key) if key == "auctionCut" then return 0.05 end end,
}

local quality = { [1] = 2, [2] = 0, [3] = 2, [4] = 3, [5] = 2 }
local prices = { [1] = 10000, [2] = 500, [3] = 2000, [5] = 4000 }
local deposits = { [1] = 100 }
ns.Prices = { GetValue = function(_, itemID) return prices[itemID] end }
ns.Profit = {
  NetFromListing = function(_, itemID, unit) return unit * 0.95 - (deposits[itemID] or 0) end,
}
ns.Util = { IsBoundOnPickup = function(itemID) return itemID == 5 end }

local demand = { [1] = "high", [3] = "low", [5] = "some" }
ns.Demand = { Get = function(_, itemID) return demand[itemID] and { level = demand[itemID] } or nil end }

-- 1 and 4 break; 1 needs 100 Enchanting, 4 needs 200. 3 is not gear.
local skills = { [1] = 100, [4] = 200 }
ns.Disenchant = {
  GetItemFacts = function(_, itemID) return quality[itemID] and { quality = quality[itemID] } end,
  IsDisenchantable = function(_, itemID)
    if itemID == 99 then return nil end
    return skills[itemID] ~= nil
  end,
  GetValue = function(_, itemID)
    return itemID == 1 and 3000 or 7000, nil, { facts = { skill = skills[itemID] } }
  end,
}

local knows = false
ns.Disenchanter = { Knows = function() return knows end }

local plans = 0
local deliveries = {}
ns.Queue = {
  version = 0,
  GetAll = function() return {} end,
  CanMail = function(_, from, to)
    return ns.db.characters[from].faction == ns.db.characters[to].faction
  end,
}
ns.Inventory = { changes = 0, GetBankCount = function(_, itemID) return itemID == 3 and 2 or 0 end }
local typed
ns.QueueMail = {
  GetPlan = function()
    plans = plans + 1
    return { [SELF] = { [3] = 10, [1] = 1 } }, { [SELF] = { [1] = 4 } }
  end,
  GetDeliveries = function() return deliveries end,
  GetDisenchanter = function() return typed end,
  GetDisenchantQuality = function() return 2 end,
  FindCharacter = function() return nil end,
}
ns.Recipes = {
  GetShortCharacterName = function(_, key) return ns.db.characters[key].name end,
}

local chunk = assert(loadfile(lfs_cwd .. "/Logic/Butler.lua"))
chunk("Blackthornes_TS", ns)
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

print("\nauction and demand")
local a = Butler:Advise(1)
check("after the cut and the deposit, per unit", a.auction, 9400)
check("high demand is fast", a.fast, true)
check("a grey has no auction value", Butler:Advise(2).auction, nil)
check("bind on pickup has no auction value", Butler:Advise(5).auction, nil)
check("some demand is unknown", Butler:Advise(5).fast, nil)
check("low demand is slow", Butler:Advise(3).fast, false)
check("never priced has no auction value", Butler:Advise(4).auction, nil)
check("an ID as text is read", Butler:Advise("1").auction, 9400)
check("not an item gives nil", Butler:Advise(nil), nil)

print("\ndisenchanting")
check("value", a.disenchant, 3000)
check("cannot without the spell", a.canDisenchant, false)
check("the alt with enough skill on this account", a.enchanter, "Ana")
local b = Butler:Advise(4)
check("too much for every alt here: nobody", b.enchanter, nil)
check("its value still shows", b.disenchant, 7000)
check("not gear cannot be broken", Butler:Advise(3).canDisenchant, false)
check("and has no value", Butler:Advise(3).disenchant, nil)
check("not loaded yet is unknown", Butler:Advise(99).canDisenchant, nil)

typed = "Zed"
Butler:Forget()
check("the disenchanter typed in Settings comes first", Butler:Advise(1).enchanter, "Zed")
check("but not above the quality picked", Butler:Advise(4).enchanter, nil)
typed = nil

knows = true
ns.db.characters[SELF].professions = { { name = "Enchanting", skillLevel = 150 } }
Butler:Forget()
local c = Butler:Advise(1)
check("knows it and has the skill", c.canDisenchant, true)
check("then no alt is named", c.enchanter, nil)
check("short of the skill", Butler:Advise(4).canDisenchant, false)

print("\nthe queue")
check("own crafts use less what it makes", Butler:Advise(1).need, nil)
check("own crafts use less what is in the bank", Butler:Advise(3).need, 8)

deliveries = {
  { to = ALT2, items = { { itemID = 3, count = 2 } } },
  { to = ALT, items = { { itemID = 3, count = 5 }, { itemID = 4, count = 1 } } },
}
-- The bags moved, so the lookup is built again.
ns.Inventory.changes = 1
local d = Butler:Advise(3)
check("mail to the alt that takes the most", d.mailTo, "Ana")
check("and how many", d.mailCount, 5)
check("nothing to mail", Butler:Advise(1).mailTo, nil)

print("\nonce a burst")
local before = plans
for itemID = 1, 100 do Butler:Advise(itemID) end
check("a hundred questions, no new plan", plans, before)
ns.Queue.version = 1
Butler:Advise(1)
check("the queue changed: one new plan", plans, before + 1)
now = now + 5
Butler:Advise(1)
check("kept too long: one new plan", plans, before + 2)

print("\nevery character's holdings")
ns.db.characters[SELF].inventory = { [1] = 99 }
ns.db.characters[SELF].bank = { [3] = 4, [7] = 0 }
ns.db.characters[ALT].inventory = { [1] = 2, ["x"] = 5 }
ns.db.characters[ALT].inventoryAt = 50
ns.db.characters[ALT].mail = { [4] = 1 }
ns.db.characters[ALT].mailAt = 60
ns.Inventory.GetBagCounts = function() return { [1] = 3, [5] = 1 } end
ns.Recipes.GetCharacters = function()
  return {
    { key = SELF, name = "Mia", isCurrent = true },
    { key = ALT, name = "Ana", isCurrent = false },
    { key = ALT2, name = "Bo", isCurrent = false, linkedFrom = "other" },
    { key = "Gone-1", name = "Gone", isCurrent = false },
  }
end
local held = Butler:Holdings()
check("one entry per character on record", #held, 3)
check("the character playing first", held[1].key, SELF)
check("its bags are read live", held[1].bags[1], 3)
check("its bank is the snapshot", held[1].bank[3], 4)
check("empty counts are left out", held[1].bank[7], nil)
check("an alt's bags are its snapshot", held[2].bags[1], 2)
check("a key that is not an item is left out", held[2].bags["x"], nil)
check("when the bags were read", held[2].bagsAt, 50)
check("its mail", held[2].mail[4], 1)
check("when the mail was read", held[2].mailAt, 60)
check("never read is nil", held[2].bankAt, nil)
check("another account's character says so", held[3].linked, "other")
check("the short name", held[2].short, "Ana")
held[2].bags[1] = 1000
check("a copy: the save is untouched", ns.db.characters[ALT].inventory[1], 2)
ns.Recipes.GetCharacters = function() error("boom") end
check("an error gives nil", Butler:Holdings(), nil)

print("\nfilling mail and taking from the bank")
local filled
ns.QueueMail.Fill = function(_, delivery) filled = delivery return true end
ns.QueueMail.FindCharacter = function(_, typed) return typed == "Ana" and ALT or nil end
ns.QueueMail.MailName = function(record) return record.name .. " Smith" end
local started = Butler:FillMail("Ana", { { itemID = 3, count = 5 }, { itemID = "x" }, { itemID = 4, count = 0 } })
check("filling starts", started, true)
check("to the character's full mail name", filled and filled.recipient, "Ana Smith")
check("only real counts go in", filled and #filled.items, 1)
Butler:FillMail("Zed", { { itemID = 3, count = 1 } })
check("a name not on record is used as typed", filled.recipient, "Zed")
local none, why = Butler:FillMail("Ana", {})
check("nothing to mail", none, false)
check("and says why", why, "nothing to mail")
ns.QueueMail.Fill = function() return false, "the mailbox is not open" end
local _, whyNot = Butler:FillMail("Ana", { { itemID = 3, count = 1 } })
check("the mailbox shut", whyNot, "the mailbox is not open")
ns.QueueMail.Fill = function() error("boom") end
check("an error inside is false", (Butler:FillMail("Ana", { { itemID = 3, count = 1 } })), false)

-- The plan uses 10 of item 3 and 1 of item 1 (makes 4 of item 1); the bank
-- holds 2 of item 3.
ns.Inventory.GetBagCount = function(_, itemID) return itemID == 3 and 3 or 0 end
local wants = Butler:FromBank()
check("what the bank should give: no more than it holds", wants[3], 2)
check("nothing for what it makes", wants[1], nil)
ns.Inventory.GetBankCount = function(_, itemID) return itemID == 3 and 20 or 0 end
check("up to what the crafts are short", Butler:FromBank()[3], 7)
ns.Inventory.GetBagCount = function() return 10 end
check("carried enough: nothing", Butler:FromBank()[3], nil)
ns.QueueMail.GetPlan = function() error("boom") end
check("an error gives nil", Butler:FromBank(), nil)

print("\nnever raises")
ns.Prices.GetValue = function() error("boom") end
check("an error inside gives nil", Butler:Advise(1), nil)

print("")
if failures > 0 then
  error(string.format("%d Butler check(s) failed", failures))
end
print("  all Butler checks passed")
print("")
