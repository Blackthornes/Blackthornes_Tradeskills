-- Thunder Bluff and Mulgore spots on Forever's own Mulgore map.
--
-- Show the way sent players to Tepa, Thunder Bluff's tailoring trainer, and
-- to other Thunder Bluff trainers, just north of the city (found 2026-11-17,
-- reported twice). Classic's spots are kept on Mulgore's map, and Forever's
-- Mulgore map covers more ground than Classic's did, so Classic's numbers
-- landed north of where they should. What must hold:
--   1. Every Mulgore spot from Classic sits where the game showed that
--      vendor (Data/ForeverVendorSpots.lua), Thunder Bluff's too.
--   2. Tepa and every trainer in the city land inside Thunder Bluff's map,
--      and count as the city when one is picked.
--   3. A spot out in Mulgore (Bloodhoof Village) is still no city.

local failures = 0
local function check(label, got, want)
  if got == want then
    print("  ok   " .. label)
  else
    failures = failures + 1
    print(string.format("  FAIL %s: got %s, want %s", label, tostring(got), tostring(want)))
  end
end

local function Load(path)
  local ns = {}
  assert(loadfile(lfs_cwd .. "/" .. path))("Blackthornes_TS", ns)
  return ns
end

local learn = Load("Data/LearnSpots.lua").LEARN_SPOTS
local classic = Load("Data/VendorSpots.lua").VENDOR_SPOTS
local seen = Load("Data/ForeverVendorSpots.lua").FOREVER_VENDOR_SPOTS

-- World bounds of each map on Forever, from the client's UiMapAssignment
-- table: { left, right, top, bottom } as world Y (east to west) and world X
-- (north to south).
local MAPS = {
  [1412] = { 2479.167, -3675.0, 266.666, -3835.416 },   -- Mulgore
  [1456] = { 516.667, -527.083, -850.0, -1545.833 },     -- Thunder Bluff
}
local function World(map, x, y)
  local b = MAPS[map]
  return b[1] - x / 100 * (b[1] - b[2]), b[3] - y / 100 * (b[3] - b[4])
end
local function OnMap(map, wy, wx)
  local b = MAPS[map]
  return (b[1] - wy) / (b[1] - b[2]) * 100, (b[3] - wx) / (b[3] - b[4]) * 100
end
local function MulgoreToBluff(x, y) return OnMap(1456, World(1412, x, y)) end

print("")
print("bluff spots")

-- 1. Classic's Mulgore spots against where the game showed the vendor.
local compared, near = 0, 0
for npc, row in pairs(classic.NPCS) do
  local s = seen[npc]
  if row[2] == "Mulgore" and s and MAPS[s[2]] then
    local x, y = OnMap(1412, World(s[2], s[3], s[4]))
    compared = compared + 1
    local off = math.max(math.abs(x - row[3]), math.abs(y - row[4]))
    if off <= 1.5 then
      near = near + 1
    else
      print(string.format("  %s: data %.1f, %.1f, game %.1f, %.1f", row[1], row[3], row[4], x, y))
    end
  end
end
check("vendors the game showed are compared", compared >= 8, true)
check("every Mulgore vendor sits where the game showed it", near, compared)

-- 2. Tepa and the city's trainers land inside Thunder Bluff.
local LearnNext = {}
do
  local ns = { LEARN_SPOTS = learn }
  ns.NewModule = function(name) ns[name] = LearnNext return LearnNext end
  ns.COLORS = setmetatable({}, { __index = function() return "ffffffff" end })
  ns.Print, ns.Debug = function() end, function() end
  assert(loadfile(lfs_cwd .. "/Logic/LearnNext.lua"))("Blackthornes_TS", ns)
  LearnNext = ns.LearnNext or LearnNext
end

local tepa
for _, row in ipairs(learn.TRAINERS[197] or {}) do
  if row[1] == "Tepa" then tepa = row end
end
check("Tepa is in the data", tepa ~= nil, true)
if tepa then
  local x, y = MulgoreToBluff(tepa[3], tepa[4])
  check("Tepa lands inside Thunder Bluff", x > 5 and x < 95 and y > 5 and y < 95, true)
  -- The game shows her by the bridge in the middle of the city, near 44, 45.
  check("Tepa lands by the city's middle", math.abs(x - 44.5) < 3 and math.abs(y - 45) < 3, true)
  check("Tepa counts as Thunder Bluff",
    LearnNext.CityOf({ zone = tepa[2], x = tepa[3], y = tepa[4] }), "Thunder Bluff")
end

local BLUFF = { Tepa = true, Vhan = true, Mak = true, Tarn = true, Una = true,
  ["Bena Winterhoof"] = true, Kray = true, ["Aska Mistrunner"] = true,
  ["Brek Stonehoof"] = true, ["Mot Dawnstrider"] = true, ["Teg Dawnstrider"] = true,
  ["Karn Stonehoof"] = true, ["Thrag Stonehoof"] = true, ["Pand Stonebinder"] = true }
local inCity, bluffCount = 0, 0
for _, list in pairs(learn.TRAINERS) do
  for _, row in ipairs(list) do
    if BLUFF[row[1]] and row[2] == "Mulgore" then
      bluffCount = bluffCount + 1
      local x, y = MulgoreToBluff(row[3], row[4])
      if x > 5 and x < 95 and y > 5 and y < 95
        and LearnNext.CityOf({ zone = row[2], x = row[3], y = row[4] }) == "Thunder Bluff" then
        inCity = inCity + 1
      else
        print(string.format("  %s lands at %.1f, %.1f on Thunder Bluff's map", row[1], x, y))
      end
    end
  end
end
check("Thunder Bluff's trainers are in the data", bluffCount >= 14, true)
check("every Thunder Bluff trainer lands in the city", inCity, bluffCount)

-- 3. Bloodhoof Village is out in Mulgore.
for _, list in pairs(learn.TRAINERS) do
  for _, row in ipairs(list) do
    if row[1] == "Chaw Stronghide" then
      check("Bloodhoof Village is no city",
        LearnNext.CityOf({ zone = row[2], x = row[3], y = row[4] }), "Mulgore")
    end
  end
end

print("")
if failures > 0 then error(string.format("%d bluff spot check(s) failed", failures)) end
print("  all bluff spot checks passed")
print("")
