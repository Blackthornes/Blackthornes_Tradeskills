-- Logic/Cooldowns.lua outside WoW.
--
-- Profession cooldowns on every character (asked 2026-10-12). What must hold:
--   1. A known cooldown craft the character has learned is kept, read from
--      the spell's cooldown; one the character has not learned is not.
--   2. Crafts that share a cooldown (every transmute) show once, by group,
--      ready only when the last of them is.
--   3. A craft the game says is cooling down is kept even when it is not
--      in the known list (one Forever added), and a cast starts the read.
--   4. A ready cooldown is said in chat once, not on every read, and again
--      only after it has been used and come ready again.
--   5. The character playing writes only under its GUID; another account's
--      characters are left out; Butler gets a step per ready group, and
--      none with the setting off.
--   6. The Salt Shaker is kept while carried and dropped once it is gone.
--   7. Butler's Craft makes a ready cooldown craft that is not queued.

local now, clock = 1000000, 500
time = function() return now end
GetTime = function() return clock end
local timers = {}
C_Timer = { After = function(seconds, fn) timers[#timers + 1] = { at = seconds, fn = fn } end }
local function RunTimers()
  local list = timers
  timers = {}
  for _, timer in ipairs(list) do timer.fn() end
end
InCombatLockdown = function() return false end

local cooling = {}      -- spellID -> { start, duration }
C_Spell = {
  GetSpellCooldown = function(spellID)
    local cd = cooling[spellID]
    if cd then return { startTime = cd[1], duration = cd[2] } end
    return { startTime = 0, duration = 0 }
  end,
  GetSpellName = function(spellID) return "Spell " .. spellID end,
}
local recipeLeft = {}
C_TradeSkillUI = { GetRecipeCooldown = function(recipeID) return recipeLeft[recipeID] end }
local itemCooling, carried = {}, {}
C_Container = { GetItemCooldown = function(itemID)
  local cd = itemCooling[itemID]
  if cd then return cd[1], cd[2], 1 end
  return 0, 0, 1
end }
C_Item = {
  GetItemCount = function(itemID) return carried[itemID] or 0 end,
  GetItemNameByID = function(itemID) return itemID == 15846 and "Salt Shaker" or nil end,
}

local printed = {}
local ns = { commands = {} }
ns.NewModule = function(name) local m = {} ns[name] = m return m end
ns.RegisterCommand = function(name, _, fn) ns.commands[name] = fn end
ns.Print = function(text) printed[#printed + 1] = text end
local handlers = {}
ns.RegisterEvent = function(_, event, fn) handlers[event] = fn return true end
ns.RegisterPlayerEvent = ns.RegisterEvent

local ANA, WITHER, LINKED = "Player-1", "Player-2", "Player-3"
local settings = {}
ns.db = {
  characters = {
    [ANA] = { name = "Ana", surname = "Blackthorne", realm = "R", faction = "Alliance",
      recipes = { [17187] = { name = "Transmute: Arcanite" }, [11479] = { name = "Transmute: Iron to Gold" },
        [90001] = { name = "Forever Thing" }, [2000] = { name = "Linen Bolt" } } },
    [WITHER] = { name = "Blackthornes", surname = "Wither", realm = "R", faction = "Alliance",
      recipes = { [18560] = { name = "Mooncloth" } } },
    [LINKED] = { name = "Lin", surname = "Ked", realm = "R", faction = "Alliance", linkedFrom = ANA },
  },
}
local selfKey = ANA
ns.Config = {
  GetCharacterKey = function() return selfKey end,
  Get = function(_, key) return settings[key] end,
}
ns.Recipes = {
  GetCharacterName = function(_, key)
    local r = ns.db.characters[key]
    return r.name .. " " .. r.surname
  end,
}

assert(loadfile(lfs_cwd .. "/Logic/Cooldowns.lua"))("Blackthornes_TS", ns)
local Cooldowns = ns.Cooldowns
Cooldowns:OnEnable()

local failures = 0
local function check(label, got, want)
  if got ~= want then
    failures = failures + 1
    print(string.format("  FAIL  %-52s got %s, wanted %s", label, tostring(got), tostring(want)))
  else
    print(string.format("  ok    %-52s %s", label, tostring(got)))
  end
end

print("\nreading the character playing")
-- Arcanite was made an hour ago; its cooldown is a day, shared with Iron to Gold.
cooling[17187] = { clock - 3600, 86400 }
cooling[11479] = { clock - 3600, 86400 }
RunTimers()                     -- the login read
local groups = Cooldowns:Groups(ANA)
check("the transmutes are one group", #groups, 1)
check("named before the colon", groups[1] and groups[1].group, "Transmute")
check("not ready", groups[1] and groups[1].ready, false)
check("ready in 23 hours", groups[1] and groups[1].readyAt, now + 82800)
check("a craft with no cooldown is not kept", ns.db.professionCooldowns[ANA]["spell:2000"], nil)
check("an unknown craft not cooling down is not kept", ns.db.professionCooldowns[ANA]["spell:90001"], nil)
check("nothing said while none is ready", #printed, 0)
check("a timer waits for it", #timers, 1)
check("23 hours and a second", timers[1] and timers[1].at, 82801)

print("\nwhen it comes ready")
now, clock = now + 82801, clock + 82801
RunTimers()
check("said once", #printed, 1)
check("as here", printed[1], "cooldown ready: Transmute here.")
Cooldowns:Read()
Cooldowns:Announce()
check("not said again on the next read", #printed, 1)
check("still ready", Cooldowns:Groups(ANA)[1].ready, true)

print("\na craft Forever added")
cooling[90001] = { clock, 3 * 86400 }
handlers.UNIT_SPELLCAST_SUCCEEDED(nil, "UNIT_SPELLCAST_SUCCEEDED", "player", "cast", 90001)
handlers.UNIT_SPELLCAST_SUCCEEDED(nil, "UNIT_SPELLCAST_SUCCEEDED", "player", "cast", 90001)
check("two casts are one read", #timers, 1)
RunTimers()
check("kept once seen cooling down", ns.db.professionCooldowns[ANA]["spell:90001"] ~= nil, true)
check("by its name", ns.db.professionCooldowns[ANA]["spell:90001"].group, "Forever Thing")
handlers.UNIT_SPELLCAST_SUCCEEDED(nil, "UNIT_SPELLCAST_SUCCEEDED", "player", "cast", 6603)
check("a cast that is no recipe reads nothing", #timers, 1)   -- the next-ready timer only

print("\nfrom the profession window")
recipeLeft[17187] = nil
Cooldowns:NoteRecipe(2000, { name = "Linen Bolt" })
check("a recipe with none is not kept", ns.db.professionCooldowns[ANA]["spell:2000"], nil)
recipeLeft[2000] = 7200
Cooldowns:NoteRecipe(2000, { name = "Linen Bolt" })
check("the window saying it cools down keeps it", ns.db.professionCooldowns[ANA]["spell:2000"].readyAt, now + 7200)

print("\nother characters")
ns.db.professionCooldowns[WITHER] = { ["spell:18560"] = { name = "Mooncloth", group = "Mooncloth",
  recipeID = 18560, readyAt = now - 60 } }
ns.db.professionCooldowns[LINKED] = { ["spell:18560"] = { name = "Mooncloth", group = "Mooncloth",
  recipeID = 18560, readyAt = now - 60 } }
local all = Cooldowns:All()
check("this account's two characters", #all, 2)
check("the one playing first", all[1].key, ANA)
check("the alt by full name", all[2].name, "Blackthornes Wither")
Cooldowns:Announce()
check("the alt's ready one is said", printed[#printed], "cooldown ready: Mooncloth on Blackthornes Wither.")
local ready = Cooldowns:ReadyList()
check("Butler gets two ready steps", #ready, 2)
settings.cooldownAlerts = false
check("none with the setting off", #Cooldowns:ReadyList(), 0)
settings.cooldownAlerts = nil

print("\nnot sure who is playing")
selfKey = "Ana-R"
cooling[18560] = { clock, 86400 }
Cooldowns:Read()
check("nothing written under a name key", ns.db.professionCooldowns["Ana-R"], nil)
selfKey = ANA

print("\nthe Salt Shaker")
carried[15846] = 1
itemCooling[15846] = { clock - 60, 3 * 86400 }
Cooldowns:Read()
local shaker = ns.db.professionCooldowns[ANA]["item:15846"]
check("kept while carried", shaker and shaker.group, "Salt Shaker")
check("with its item", shaker and shaker.itemID, 15846)
carried[15846] = 0
Cooldowns:Read()
check("dropped once it is gone", ns.db.professionCooldowns[ANA]["item:15846"], nil)

print("\nReadyHere and the group's time")
check("transmute ready here", Cooldowns:ReadyHere(17187), true)
check("the Forever craft is not", Cooldowns:ReadyHere(90001), false)
check("Cooldowns.Group without a colon", Cooldowns.Group("Mooncloth"), "Mooncloth")
check("left text in days", Cooldowns.LeftText(2 * 86400 + 4 * 3600 + 5), "2d 4h")
check("left text in hours", Cooldowns.LeftText(3 * 3600 + 12 * 60), "3h 12m")

print("\nused again, ready again")
cooling[17187] = { clock, 86400 }
cooling[11479] = { clock, 86400 }
Cooldowns:Read()
check("cooling down again", Cooldowns:ReadyHere(17187), false)
local before = #printed
now, clock = now + 86401, clock + 86401
Cooldowns:Read()
Cooldowns:Announce()
check("said again once ready again", printed[#printed]:find("Transmute here") ~= nil, true)
check("one more line", #printed, before + 1)

print("")
if failures > 0 then
  error(string.format("%d cooldown check(s) failed", failures))
end
print("  all cooldown checks passed")
print("")
