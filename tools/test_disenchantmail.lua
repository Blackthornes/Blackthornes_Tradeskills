-- Gear for the disenchanter (Izbode, 2026-10-04): "Setting a disenchant
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
UnitName = function() return "Ana" end
GetRealmName = function() return "Forever" end

local settings = { disenchanterName = "Dusty", disenchanterQuality = 2 }
local currentKey = "Player-ANA"

ns.Config = {
    Get = function(_, key) return settings[key] end,
    GetCharacterKey = function() return currentKey end,
}

ns.db = {
    characters = {
        ["Player-ANA"] = { name = "Ana", realm = "Forever" },
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
    currentKey = "Player-ANA"
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

print("")
print("who it goes to")

Reset()
settings.disenchanterName = ""
check("nobody set: nothing listed", QueueMail:GetDisenchantDelivery(), nil)

settings.disenchanterName = "  ana "
check("the character playing: nothing listed", QueueMail:GetDisenchantDelivery(), nil)

-- 2026-10-04: logged in on the disenchanter, nothing is offered.
settings.disenchanterName = "ANA-Forever"
check("own name and realm, any case: nothing listed", QueueMail:GetDisenchanter(), nil)

settings.disenchanterName = "ana blackthorne"
ns.db.characters["Player-ANA"].surname = "Blackthorne"
check("first and last name: nothing listed", QueueMail:GetDisenchanter(), nil)
settings.disenchanterName = "Ana  Blackthorne-Forever"
check("with the realm and a doubled space too", QueueMail:GetDisenchanter(), nil)
ns.db.characters["Player-ANA"].surname = nil

settings.disenchanterName = "Ana-OtherRealm"
check("the same name on another realm is somebody else", QueueMail:GetDisenchanter(), "Ana-OtherRealm")

-- A record the addon has not stamped yet: the game still says who is playing.
local saved = ns.db.characters["Player-ANA"]
ns.db.characters["Player-ANA"] = nil
settings.disenchanterName = "ana"
check("no saved record yet: the game's name counts", QueueMail:GetDisenchanter(), nil)
ns.db.characters["Player-ANA"] = saved

-- And with nothing from the game, the saved record still says who it is.
UnitName, GetRealmName = nil, nil
check("no name from the game: the record's counts", QueueMail:GetDisenchanter(), nil)
UnitName = function() return "Ana" end
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

C_Container = nil
UnitName, GetRealmName = oldUnitName, oldRealmName

print("")
if failures > 0 then
    print(("FAIL -- %d check(s) failed"):format(failures))
    os.exit(1)
end

print("PASS -- the disenchanter gets the gear asked for and nothing else")
