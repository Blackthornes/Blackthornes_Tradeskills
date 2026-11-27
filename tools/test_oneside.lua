-- Materials on characters of the other side (a player's report, 2026-11-27).
--
-- A Horde character was told cloth on the player's Alliance character, on
-- the same realm, was there to use for a craft. Items never cross sides.
-- What must hold:
--   1. Characters:CanMail and :InReach say no for another side or realm,
--      and yes where a record does not say (old records stay counted).
--   2. The craft pane's "on <name>" never names a character of the other
--      side or realm, and picks the one on this side that holds it.
--   3. "On other characters" in the queue and gather lists
--      (Inventory:GetAltCounts and :GetAltTotal) counts only this side.

local GLOBALS = { "CreateFrame", "C_TradeSkillUI" }
local saved = {}
for _, key in ipairs(GLOBALS) do saved[key] = _G[key] end

local function noop() end
CreateFrame = function()
    return setmetatable({}, { __index = function() return noop end })
end
C_TradeSkillUI = nil

local CLOTH = 2589
local ME, ALLY, HORDE_ALT, OTHER_REALM, OLD = "Player-1-ME", "Player-1-ALLY", "Player-1-HALT",
    "Player-2-FAR", "Old-R"

local function Load()
    local ns = {}
    ns.NewModule = function(name) local m = {}; ns[name] = m; return m end
    ns.COLORS = setmetatable({}, { __index = function() return "ffffffff" end })
    ns.RegisterCommand, ns.RegisterEvent = noop, noop
    ns.Print, ns.Warn, ns.Debug = noop, noop, noop
    assert(loadfile(lfs_cwd .. "/Core/Util.lua"))("Blackthornes_TS", ns)
    ns.Theme = { Unpack = function(key) return key end, SetItemIcon = noop, SetMark = noop }
    ns.Widgets = {}
    ns.Config = { Get = function() return nil end, GetCharacterKey = function() return ME end }
    ns.db = { characters = {
        [ME] = { name = "Grosh", realm = "Forever PvE", faction = "Horde", inventory = {} },
        [ALLY] = { name = "Ana", realm = "Forever PvE", faction = "Alliance", inventory = { [CLOTH] = 80 } },
        [HORDE_ALT] = { name = "Zug", realm = "Forever PvE", faction = "Horde", inventory = { [CLOTH] = 30 } },
        [OTHER_REALM] = { name = "Far", realm = "Elsewhere", faction = "Horde", inventory = { [CLOTH] = 90 } },
    } }
    ns.Recipes = {
        GetCharacterName = function(_, key) return ns.db.characters[key].name end,
        GetShortCharacterName = function(_, key) return ns.db.characters[key].name end,
    }
    assert(loadfile(lfs_cwd .. "/Core/Characters.lua"))("Blackthornes_TS", ns)
    assert(loadfile(lfs_cwd .. "/Data/Inventory.lua"))("Blackthornes_TS", ns)
    local CraftPanel
    local realNew = ns.NewModule
    ns.NewModule = function(name) local m = realNew(name); CraftPanel = m; return m end
    assert(loadfile(lfs_cwd .. "/UI/CraftPanel.lua"))("Blackthornes_TS", ns)
    ns.NewModule = realNew
    return ns, CraftPanel
end

local failures = 0
local function check(label, got, want)
    if got ~= want then
        failures = failures + 1
        print(string.format("  FAIL  %-56s got %s, wanted %s", label, tostring(got), tostring(want)))
    else
        print(string.format("  ok    %-56s %s", label, tostring(got)))
    end
end

local ns, CraftPanel = Load()
local C = ns.Characters

print("\nwho can mail whom")
check("the other side can't", C:CanMail(ME, ALLY), false)
check("this side can", C:CanMail(ME, HORDE_ALT), true)
check("another realm can't", C:CanMail(ME, OTHER_REALM), false)
check("the Alliance alt is out of reach", C:InReach(ALLY), false)
check("the Horde alt is in reach", C:InReach(HORDE_ALT), true)
check("the one playing is in reach", C:InReach(ME), true)
ns.db.characters[OLD] = { name = "Old", inventory = {} }
check("a record with no realm or side still counts", C:InReach(OLD), true)
ns.db.characters[OLD] = nil
check("\"Realm 7\" and \"Realm 3\" are one realm", (function()
    ns.db.characters[ME].realm = "CAMWOW US2 Realm 7 PvE"
    ns.db.characters[HORDE_ALT].realm = "CAMWOW US2 Realm 3 PvE"
    local ok = C:CanMail(ME, HORDE_ALT)
    ns.db.characters[ME].realm, ns.db.characters[HORDE_ALT].realm = "Forever PvE", "Forever PvE"
    return ok
end)(), true)

print("\nthe craft pane's \"on <name>\"")
local name, count = CraftPanel:AltHolder(CLOTH)
check("names the Horde alt, not the Alliance one", name, "Zug")
check("with its 30", count, 30)
ns.db.characters[HORDE_ALT].inventory = {}
check("no one on this side has it: nobody named", (CraftPanel:AltHolder(CLOTH)), nil)
ns.db.characters[HORDE_ALT].inventory = { [CLOTH] = 30 }

print("\n\"On other characters\" in the lists")
local counts = ns.Inventory:GetAltCounts(CLOTH)
check("the Alliance alt is left out", counts[ALLY], nil)
check("another realm is left out", counts[OTHER_REALM], nil)
check("the Horde alt counts", counts[HORDE_ALT], 30)
check("the total is this side's only", ns.Inventory:GetAltTotal(CLOTH), 30)

print("\nnot sure who's playing (a dungeon)")
ns.Config.GetCharacterKey = function() return nil end
check("nothing is hidden", C:InReach(ALLY), true)
ns.Config.GetCharacterKey = function() return ME end

for _, key in ipairs(GLOBALS) do _G[key] = saved[key] end

if failures > 0 then error(("%d one side check(s) failed"):format(failures)) end
print("one side: all checks passed")
