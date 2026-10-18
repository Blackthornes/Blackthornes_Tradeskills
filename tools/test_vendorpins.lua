-- Logic/VendorPins.lua and UI/VendorPins.lua outside WoW.
--
-- Vendor map pins (a player asked, the owner said build it, 2026-10-18).
-- What must hold:
--   1. A vendor is pinned only for a material the queue still needs that
--      it sells for less than the auction house, or nobody lists there;
--      none once there are enough, none set to Buy on the Level Up tab.
--   2. Shipped vendors show on their zone's map, only of the player's side
--      or of neither.
--   3. A vendor opened in game is learned (where it stands, what it sells,
--      which run out) and takes the shipped one's place; one whose stock
--      runs out is pinned only while the auction house has none.
--   4. Only materials are kept, and reading the same vendor again is no news.
--   5. A click pins the game's map, or hands TomTom the place.
--   6. The hover says the approved words, and the slash command turns it
--      on and off.

-- Tests share one Lua state: every global set here is put back at the end.
local GLOBALS = { "time", "GetLocale", "UnitGUID", "UnitName", "UnitFactionGroup",
  "C_Map", "C_Item", "UiMapPoint", "C_SuperTrack", "TomTom", "CreateFrame", "C_Timer" }
local saved = {}
for _, key in ipairs(GLOBALS) do saved[key] = _G[key] end
CreateFrame, C_Timer = nil, nil

local now = 1000
time = function() return now end
GetLocale = function() return "enUS" end

local ns = {}
ns.NewModule = function(name) local m = {} ns[name] = m return m end
ns.Debug = function() end
local printed = {}
ns.Print = function(text) printed[#printed + 1] = text end
local commands = {}
ns.RegisterCommand = function(name, _, fn) commands[name] = fn end

local settings = { vendorMapPins = false }
ns.Config = {
  Get = function(_, key) return settings[key] end,
  Set = function(_, key, value) settings[key] = value end,
}
ns.db = {}

local THREAD, VIAL, FLUX, DYE, SALT = 2320, 3371, 2880, 2324, 4289
ns.VENDOR_PRICES = { [THREAD] = 10, [VIAL] = 4, [FLUX] = 100, [DYE] = 25, [SALT] = 50 }

-- Elwynn Forest is 1429 and Stormwind City 1453 in Waypoints.ZONE_MAPS.
ns.VENDOR_SPOTS = {
  NPCS = {
    [101] = { "Alliance Supplier", "Stormwind City", 60, 70, "A" },
    [102] = { "Horde Supplier", "Stormwind City", 20, 30, "H" },
    [103] = { "Goblin Supplier", "Stormwind City", 40, 40, "" },
    [104] = { "Elwynn Supplier", "Elwynn Forest", 50, 50, "A" },
  },
  ITEMS = {
    [THREAD] = { 101, 102, 104 },
    [VIAL] = { 101 },
    [FLUX] = { 103 },
  },
}

local shopping = {}
ns.Queue = { version = 1, GetShoppingList = function() return shopping end }
local skips = {}
ns.Cost = { SkipsVendor = function(_, id) return skips[id] == true end }

local playerSide = "Alliance"
local npc = { guid = nil, name = nil, faction = nil }
UnitGUID = function(unit) if unit == "npc" then return npc.guid end end
UnitName = function(unit) if unit == "npc" then return npc.name end end
UnitFactionGroup = function(unit)
  if unit == "player" then return playerSide end
  if unit == "npc" then return npc.faction end
end
local spot = { map = 1453, x = 0.4512, y = 0.3349 }
local pinned
C_Map = {
  GetBestMapForUnit = function() return spot.map end,
  GetPlayerMapPosition = function() return { GetXY = function() return spot.x, spot.y end } end,
  SetUserWaypoint = function(point) pinned = point end,
  GetMapInfo = function() return nil end,
}
UiMapPoint = { CreateFromCoordinates = function(map, x, y) return { map = map, x = x, y = y } end }
C_SuperTrack = { SetSuperTrackedUserWaypoint = function() end }
-- Class 7 trade goods, 5 reagents, 4 armour.
local CLASSES = { [THREAD] = 7, [VIAL] = 7, [DYE] = 7, [9001] = 7, [9002] = 4, [SALT] = 7 }
C_Item = { GetItemInfoInstant = function(id) return id, nil, nil, nil, nil, CLASSES[id] end }

assert(loadfile(lfs_cwd .. "/Logic/Waypoints.lua"))("Blackthornes_TS", ns)
assert(loadfile(lfs_cwd .. "/Logic/VendorPins.lua"))("Blackthornes_TS", ns)

local VP = ns.VendorPins
local failures = 0
local function check(label, got, want)
  if got ~= want then
    failures = failures + 1
    print(string.format("  FAIL  %-56s got %s, wanted %s", label, tostring(got), tostring(want)))
  else
    print(string.format("  ok    %-56s %s", label, tostring(got)))
  end
end

local function Names(vendors)
  local names = {}
  for _, v in ipairs(vendors) do names[#names + 1] = v.name end
  return table.concat(names, ", ")
end

local function Line(itemID, shortfall, vendor, auction)
  return { itemID = itemID, shortfall = shortfall, vendorUnit = vendor, auctionUnit = auction }
end

print("\nwhat the queue wants")
shopping = {
  Line(THREAD, 20, 10, 25),   -- cheaper at a vendor
  Line(VIAL, 10, 4, nil),     -- nobody lists it
  Line(FLUX, 5, 100, 80),     -- cheaper on the auction house
  Line(DYE, 0, 25, 60),       -- already enough
}
local wanted = VP:Wanted()
check("thread, cheaper at a vendor", wanted[THREAD] ~= nil, true)
check("vials, none on the auction house", wanted[VIAL] ~= nil, true)
check("flux, cheaper on the auction house", wanted[FLUX], nil)
check("dye, already enough", wanted[DYE], nil)
skips[THREAD] = true
check("set to Buy on the Level Up tab", VP:Wanted()[THREAD], nil)
skips[THREAD] = nil

print("\nshipped vendors")
local vendors = VP:For(1453)
check("Stormwind, Alliance side or neither", Names(vendors), "Alliance Supplier")
check("the goblin has only flux, not wanted", #vendors, 1)
local first = vendors[1]
check("items, the dearest first", first.items[1].itemID, THREAD)
check("thread for 20", first.items[1].count, 20)
check("costs 20 x 10c", first.items[1].cost, 200)
check("saves (25 - 10) x 20", first.saving, 300)
check("vials have no auction price to save on", first.items[2].saving, nil)
check("Elwynn Forest", Names(VP:For(1429)), "Elwynn Supplier")
playerSide = "Horde"
check("a Horde character", Names(VP:For(1453)), "Horde Supplier")
playerSide = "Alliance"
shopping = { Line(THREAD, 20, 10, 25), Line(FLUX, 5, 50, 80) }
check("the goblin, once flux is cheaper there", Names(VP:For(1453)), "Alliance Supplier, Goblin Supplier")
shopping = {}
check("nothing wanted, no pins", #VP:For(1453), 0)

print("\nlearned at the vendor window")
shopping = { Line(THREAD, 20, 10, 25), Line(DYE, 4, 25, 60), Line(SALT, 2, 50, 70) }
npc.guid, npc.name, npc.faction = "Creature-0-1-2-3-101-0000ABCD", "Alliance Supplier", "Alliance"
local items = {
  [THREAD] = { price = 10, numAvailable = -1 },
  [DYE] = { price = 25, numAvailable = 5 },        -- runs out
  [9002] = { price = 500, numAvailable = -1 },     -- armour, not a material
  [9003] = { price = 0, numAvailable = -1, extendedCost = true },
}
local before = VP.version
check("learned", VP:Learn(items), true)
local kept = ns.db.vendorSpots[101]
check("kept by NPC ID", kept ~= nil, true)
check("where it stands", kept and (kept.mapID .. " " .. kept.x .. " " .. kept.y), "1453 45.1 33.5")
check("its side", kept and kept.side, "A")
check("thread never runs out", kept and kept.items[THREAD], true)
check("dye runs out", kept and kept.items[DYE], false)
check("armour is not kept", kept and kept.items[9002], nil)
check("the map draws again", VP.version > before, true)
before = VP.version
VP:Learn(items)
check("read again, no news", VP.version, before)

vendors = VP:For(1453)
check("the learned one takes the shipped one's place", Names(vendors), "Alliance Supplier")
check("at the spot it was seen", vendors[1].x, 45.1)
check("dye runs out and the auction house has it", #vendors[1].items, 1)
shopping = { Line(THREAD, 20, 10, 25), Line(DYE, 4, 25, nil) }
check("dye runs out, none on the auction house", #VP:For(1453)[1].items, 2)

npc.guid, npc.name, npc.faction = "Creature-0-1-2-3-555-0000ABCD", "Forever Trader", nil
spot.map, spot.x, spot.y = 1429, 0.2, 0.8
VP:Learn({ [THREAD] = { price = 10, numAvailable = -1 } })
check("a vendor of neither side", ns.db.vendorSpots[555].side, "")
check("one the data never had", Names(VP:For(1429)), "Elwynn Supplier, Forever Trader")
check("a player's GUID is no vendor", VP.NpcID("Player-1-0000ABCD"), nil)
npc.guid = nil
check("no vendor targeted, nothing kept", VP:Learn(items), false)

print("\nonly so many kept")
VP.MOST_VENDORS = 2
npc.guid, npc.name = "Creature-0-1-2-3-777-0000ABCD", "Newest"
now = 2000
VP:Learn({ [THREAD] = { price = 10, numAvailable = -1 } })
local count = 0
for _ in pairs(ns.db.vendorSpots) do count = count + 1 end
check("the oldest seen goes", count, 2)
check("the newest stays", ns.db.vendorSpots[777] ~= nil, true)
VP.MOST_VENDORS = 300

print("\nshow the way")
local tomtomPlace
local ok = VP:ShowTheWay({ name = "Forever Trader", mapID = 1429, x = 20, y = 80 })
check("pins the game's map", ok, true)
check("on its map", pinned and pinned.map, 1429)
check("at its spot", pinned and pinned.x, 0.2)
TomTom = {
  AddWaypoint = function(_, map, x, y, opts) tomtomPlace = { map = map, x = x, title = opts.title } return 1 end,
  RemoveWaypoint = function() end,
}
VP:ShowTheWay({ name = "Forever Trader", mapID = 1429, x = 20, y = 80 })
check("hands TomTom the place", tomtomPlace and tomtomPlace.map, 1429)
check("TomTom's arrow names the vendor", tomtomPlace and tomtomPlace.title, "Forever Trader")
TomTom = nil

print("\nthe hover")
ns.Util = {
  GetItemLabel = function(id) return "item " .. id end,
  FormatMoney = function(c) return tostring(c) .. "c" end,
}
ns.Theme = { Unpack = function() return 1, 1, 1, 1 end }
assert(loadfile(lfs_cwd .. "/UI/VendorPins.lua"))("Blackthornes_TS", ns)
local lines = ns.VendorPinsUI.TooltipLines({ name = "Lucan Cordell", saving = 240,
  items = { { itemID = VIAL, count = 10, cost = 40 } } }, false)
check("the vendor's name", lines[1][1], "Lucan Cordell")
check("then what it has", lines[2][1], "Has what your queue needs:")
check("each item and how many", lines[3][1], "item 3371 x10")
check("and what they cost", lines[3][2], "40c")
check("what it saves", lines[4][1], "Saves you 240c over the auction house.")
check("click", lines[5][1], "Click to set a map pin.")
lines = ns.VendorPinsUI.TooltipLines({ name = "X", saving = 0, items = {} }, true)
check("nothing saved, no savings line", lines[3][1], "Click for a TomTom arrow.")

print("\n/bts vendorpins")
commands.vendorpins("on")
check("on", settings.vendorMapPins, true)
check("says so", printed[#printed], "Vendor Map Pins: on.")
commands.vendorpins("off")
check("off", settings.vendorMapPins, false)
commands.vendorpins("")
check("alone, it turns it round", settings.vendorMapPins, true)

for _, key in ipairs(GLOBALS) do _G[key] = saved[key] end

print("")
if failures > 0 then error(string.format("%d vendor pin check(s) failed", failures)) end
print("  all vendor pin checks passed")
print("")
