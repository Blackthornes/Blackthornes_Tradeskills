-- Gear for the disenchanter (2026-10-04): "Setting a disenchant
-- character to mail all BoEs to (with threshold option, like only greens, or
-- maybe only green and blues)".
--
-- Drives the real Logic/QueueMail.lua with a bag of gear: what goes on the
-- disenchanter's mail, at each quality setting, and what never does.

local ns = {}
ns.NewModule = function(name) local m = {}; ns[name] = m; return m end
ns.RegisterCommand = function() end
ns.RegisterEvent = function() end
ns.Print, ns.PrintRaw, ns.Debug, ns.Warn = function() end, function() end, function() end, function() end

local GREEN_BAND, GREEN_BOOTS, BLUE_SWORD, PURPLE_STAFF, GREY_SHIRT, BOP_GLOVES, WAND, CLOTH =
    7955, 7956, 7957, 7958, 7959, 7960, 7961, 2589

-- Other suites share this Lua state and may leave their own players behind.
local oldUnitName, oldRealmName = UnitName, GetRealmName
UnitName = function() return "Bob" end
GetRealmName = function() return "Forever" end

local settings = { disenchanterName = "Dusty", disenchanterQuality = 2 }
local currentKey = "Player-BOB"

ns.Config = {
    Get = function(_, key) return settings[key] end,
    GetCharacterKey = function() return currentKey end,
}

ns.db = {
    characters = {
        ["Player-BOB"] = { name = "Bob", realm = "Forever" },
        ["Player-DUSTY"] = { name = "Dusty", realm = "Forever" },
    },
}

ns.Util = { IsBoundOnPickup = function(itemID) return itemID == BOP_GLOVES end }

-- Gear can be disenchanted; the wand, cloth and shirt cannot.
local gear = { [GREEN_BAND] = true, [GREEN_BOOTS] = true, [BLUE_SWORD] = true,
    [PURPLE_STAFF] = true, [BOP_GLOVES] = true }
ns.Disenchant = { IsDisenchantable = function(_, itemID) return gear[itemID] == true end }

local upgrades = {}
ns.Upgrades = {
    Equipment = function()
        return { IsUpgrade = function(_, item)
            local id = type(item) == "string" and tonumber(item:match("item:(%d+)")) or item
            return upgrades[id] == true
        end }
    end,
}

ns.Inventory = { GetCarriedBags = function() return { 0 } end }

local bags
local function Item(itemID, quality, extra)
    local entry = { itemID = itemID, quality = quality, stackCount = 1,
        hyperlink = ("|Hitem:%d::::::::|h[x]|h"):format(itemID) }
    for key, value in pairs(extra or {}) do entry[key] = value end
    return entry
end

C_Container = {
    GetContainerNumSlots = function() return #bags end,
    GetContainerItemInfo = function(_, slot) return bags[slot] end,
}

local function Reset()
    settings.disenchanterName, settings.disenchanterQuality = "Dusty", 2
    currentKey = "Player-BOB"
    upgrades = {}
    bags = {
        Item(GREEN_BAND, 2), Item(GREEN_BAND, 2),
        Item(GREEN_BOOTS, 2),
        Item(BLUE_SWORD, 3),
        Item(PURPLE_STAFF, 4),
        Item(GREY_SHIRT, 0),
        Item(BOP_GLOVES, 2),
        Item(WAND, 2),
        Item(CLOTH, 1, { stackCount = 20 }),
        Item(GREEN_BOOTS, 2, { isBound = true }),
    }
end

assert(loadfile(lfs_cwd .. "/Core/Characters.lua"))("Blackthornes_TS", ns)
assert(loadfile(lfs_cwd .. "/Logic/QueueMail.lua"))("Blackthornes_TS", ns)
local QueueMail = ns.QueueMail

local failures = 0
local function check(label, got, expected)
    local ok = got == expected
    if not ok then failures = failures + 1 end
    print(("  %-56s %-8s %s"):format(label, tostring(got), ok and "ok" or
        ("FAILED, expected " .. tostring(expected))))
end

local function Count(delivery, itemID)
    for _, item in ipairs(delivery and delivery.items or {}) do
        if item.itemID == itemID then return item.count end
    end
    return 0
end

print("")
print("greens only, the default")

Reset()
local delivery = QueueMail:GetDisenchantDelivery()
check("a delivery for the disenchanter", delivery ~= nil, true)
check("addressed as typed", delivery.recipient, "Dusty")
check("known as one of your characters", delivery.to, "Player-DUSTY")
check("both green bands", Count(delivery, GREEN_BAND), 2)
check("the unbound green boots, not the soulbound pair", Count(delivery, GREEN_BOOTS), 1)
check("no blue", Count(delivery, BLUE_SWORD), 0)
check("no purple", Count(delivery, PURPLE_STAFF), 0)
check("never gear that binds on pickup", Count(delivery, BOP_GLOVES), 0)
check("never what cannot be disenchanted", Count(delivery, WAND), 0)
check("never grey or white", Count(delivery, GREY_SHIRT) + Count(delivery, CLOTH), 0)

print("")
print("greens and blues, then up to purples")

Reset()
settings.disenchanterQuality = 3
delivery = QueueMail:GetDisenchantDelivery()
check("the blue sword goes too", Count(delivery, BLUE_SWORD), 1)
check("still no purple", Count(delivery, PURPLE_STAFF), 0)
check("best quality first", delivery.items[1].itemID, BLUE_SWORD)

settings.disenchanterQuality = 4
delivery = QueueMail:GetDisenchantDelivery()
check("and the purple staff at the top setting", Count(delivery, PURPLE_STAFF), 1)

print("")
print("what stays in the bags")

Reset()
upgrades[GREEN_BAND] = true
delivery = QueueMail:GetDisenchantDelivery()
check("an upgrade for you is kept", Count(delivery, GREEN_BAND), 0)
check("the rest still goes", Count(delivery, GREEN_BOOTS), 1)

-- Blackthornes Butler asks the same rule one item at a time.
check("Butler is told the upgrade stays", QueueMail:GoesToDisenchanter(GREEN_BAND, 2), false)
check("and the boots go", QueueMail:GoesToDisenchanter(GREEN_BOOTS, 2), true)
check("never above the quality picked", QueueMail:GoesToDisenchanter(BLUE_SWORD, 3), false)
check("never bind on pickup", QueueMail:GoesToDisenchanter(BOP_GLOVES, 2), false)
check("never what cannot be disenchanted", QueueMail:GoesToDisenchanter(WAND, 2), false)
check("never white", QueueMail:GoesToDisenchanter(CLOTH, 1), false)
check("not an item", QueueMail:GoesToDisenchanter(nil, 2), false)

-- Crafted gear stays (the owner, 2026-10-11: "non-crafted items").
ns.RecipeBook = { IsCrafted = function(_, itemID) return itemID == GREEN_BOOTS end }
check("crafted gear is never sent", QueueMail:GoesToDisenchanter(GREEN_BOOTS, 2), false)
Reset()
delivery = QueueMail:GetDisenchantDelivery()
check("nor listed on the mail", Count(delivery, GREEN_BOOTS), 0)
check("found gear still goes", Count(delivery, GREEN_BAND), 2)
ns.RecipeBook = { IsCrafted = function() error("broken") end }
check("a recipe book that raises sends it", QueueMail:GoesToDisenchanter(GREEN_BOOTS, 2), true)
ns.RecipeBook = nil

print("")
print("who it goes to")

Reset()
settings.disenchanterName = ""
check("nobody set: nothing listed", QueueMail:GetDisenchantDelivery(), nil)

settings.disenchanterName = "  bob "
check("the character playing: nothing listed", QueueMail:GetDisenchantDelivery(), nil)

-- Asked 2026-10-04: logged in on the disenchanter, nothing is offered.
settings.disenchanterName = "BOB-Forever"
check("own name and realm, any case: nothing listed", QueueMail:GetDisenchanter(), nil)

settings.disenchanterName = "bob blackthorne"
ns.db.characters["Player-BOB"].surname = "Blackthorne"
check("first and last name: nothing listed", QueueMail:GetDisenchanter(), nil)
settings.disenchanterName = "Bob  Blackthorne-Forever"
check("with the realm and a doubled space too", QueueMail:GetDisenchanter(), nil)
ns.db.characters["Player-BOB"].surname = nil

settings.disenchanterName = "Bob-OtherRealm"
check("the same name on another realm is somebody else", QueueMail:GetDisenchanter(), "Bob-OtherRealm")

-- A record the addon has not stamped yet: the game still says who is playing.
local saved = ns.db.characters["Player-BOB"]
ns.db.characters["Player-BOB"] = nil
settings.disenchanterName = "bob"
check("no saved record yet: the game's name counts", QueueMail:GetDisenchanter(), nil)
ns.db.characters["Player-BOB"] = saved

-- And with nothing from the game, the saved record still says who it is.
UnitName, GetRealmName = nil, nil
check("no name from the game: the record's counts", QueueMail:GetDisenchanter(), nil)
UnitName = function() return "Bob" end
GetRealmName = function() return "Forever" end

settings.disenchanterName = "Shardy-OtherRealm"
delivery = QueueMail:GetDisenchantDelivery()
check("a name from another account still gets a mail", delivery and delivery.recipient, "Shardy-OtherRealm")
check("though it is not one of yours", delivery and delivery.to, nil)

Reset()
bags = { Item(CLOTH, 1, { stackCount = 20 }) }
check("nothing to send: no row", QueueMail:GetDisenchantDelivery(), nil)

print("")
print("quality setting kept in range")

settings.disenchanterQuality = 9
check("above purple reads as purple", QueueMail:GetDisenchantQuality(), 4)
settings.disenchanterQuality = nil
check("unset reads as greens only", QueueMail:GetDisenchantQuality(), 2)

print("")
print("picked for you while the box is empty")

local function Enchanting(skill) return { { name = "Enchanting", skillLevel = skill } } end
Reset()
settings.disenchanterName = ""
check("no enchanter on the account: nobody", QueueMail:GetDisenchanter(), nil)
ns.db.characters["Player-DUSTY"].professions = Enchanting(120)
ns.db.characters["Player-DUSTY"].surname = "Dustwhisper"
ns.db.characters["Player-ENZO"] = { name = "Enzo", surname = "Sparks", realm = "Forever",
    professions = Enchanting(200) }
local name, picked = QueueMail:GetDisenchanter()
check("the most Enchanting is picked, whole name", name, "Enzo Sparks")
check("and said to be picked", picked, true)
check("the delivery goes to them", (QueueMail:GetDisenchantDelivery() or {}).recipient, "Enzo Sparks")
ns.db.characters["Player-ENZO"].linkedFrom = "Player-OTHER"
check("a character from another account is never picked", QueueMail:GetDisenchanter(), "Dusty Dustwhisper")
ns.db.characters["Player-ENZO"].linkedFrom = nil
ns.Queue = { CanMail = function(_, _, to) return to ~= "Player-ENZO" end }
check("nor one that can't be mailed", QueueMail:GetDisenchanter(), "Dusty Dustwhisper")
ns.Queue = nil
ns.db.characters["Player-BOB"].professions = Enchanting(250)
check("nobody when you out-enchant them all", QueueMail:GetDisenchanter(), nil)
ns.db.characters["Player-BOB"].professions = Enchanting(150)
check("but one with more still is", QueueMail:GetDisenchanter(), "Enzo Sparks")
ns.db.characters["Player-BOB"].professions = nil
settings.disenchanterName = "Dusty"
name, picked = QueueMail:GetDisenchanter()
check("a typed name wins", name, "Dusty")
check("and is not picked", picked, false)
settings.disenchanterName = ""
settings.disenchanterGuess = false
check("Pick one for me unticked: nobody", QueueMail:GetDisenchanter(), nil)
settings.disenchanterGuess = nil

print("")
print("is the character playing the disenchanter?")

-- For Butler's "Disenchant greens here" (the owner asked 2026-10-14).
settings.disenchanterName = "Bob"
check("typed as the character playing: yes", QueueMail:IsDisenchanterPlaying(), true)
settings.disenchanterName = "Dusty"
check("typed as someone else: no", QueueMail:IsDisenchanterPlaying(), false)
settings.disenchanterName = ""
check("box empty, an alt out-enchants you: no", QueueMail:IsDisenchanterPlaying(), false)
ns.db.characters["Player-BOB"].professions = Enchanting(250)
check("box empty, you out-enchant them all: yes", QueueMail:IsDisenchanterPlaying(), true)
settings.disenchanterGuess = false
check("but not with Pick one for me unticked", QueueMail:IsDisenchanterPlaying(), false)
settings.disenchanterGuess = nil
ns.db.characters["Player-BOB"].professions = nil
ns.db.characters["Player-DUSTY"].professions, ns.db.characters["Player-ENZO"] = nil, nil
check("nobody with Enchanting: no", QueueMail:IsDisenchanterPlaying(), false)

ns.db.characters["Player-DUSTY"].professions, ns.db.characters["Player-DUSTY"].surname = nil, nil
ns.db.characters["Player-ENZO"] = nil

C_Container = nil
UnitName, GetRealmName = oldUnitName, oldRealmName

print("")
if failures > 0 then
    print(("FAIL -- %d check(s) failed"):format(failures))
    os.exit(1)
end

print("PASS -- the disenchanter gets the gear asked for and nothing else")
