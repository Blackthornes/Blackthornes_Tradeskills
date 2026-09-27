-- Learning disenchant results from your own disenchants.
--
-- Trent, 2026-09-27: "yes, build it", on recording what his own disenchants
-- give and using that over the built-in table. What this pins down:
--   * each of the three ways of telling which item went in: the loot
--     window's source, the bag slot clicked, the name sent with the cast;
--   * a click aimed at some other spell is not taken for a disenchant;
--   * loot that is not enchanting materials, or an item nobody can name,
--     is counted as a miss rather than recorded wrong;
--   * after LEARN_AFTER disenchants of a kind of item, its chances and
--     counts are yours, and the value follows them.

local ns = {}
ns.COLORS = setmetatable({}, { __index = function() return "ffffffff" end })
ns.NewModule = function(name) local m = {}; ns[name] = m; return m end
ns.RegisterCommand = function() end
ns.RegisterEvent = function() end
local printed = {}
ns.Print = function(text) printed[#printed + 1] = text end
ns.PrintRaw, ns.Debug, ns.Warn = function() end, function() end, function() end

local saved = {
    C_Item = C_Item, C_Container = C_Container, GetTime = GetTime, CreateFrame = CreateFrame,
    SpellIsTargeting = SpellIsTargeting, GetNumLootItems = GetNumLootItems,
    GetLootSlotLink = GetLootSlotLink, GetLootSlotInfo = GetLootSlotInfo,
    GetLootSourceInfo = GetLootSourceInfo,
}

CreateFrame = function()
    local frame = {}
    for _, name in ipairs({ "SetScript", "Show", "Hide", "SetPoint", "SetSize" }) do
        frame[name] = function() end
    end
    return frame
end

local clock = 100
GetTime = function() return clock end
time = time or os.time

local STRANGE_DUST, LESSER_ASTRAL, SMALL_GLIMMERING = 10940, 10998, 10978
local LINEN = 2589

-- itemID -> quality, itemLevel, equipLoc, classID
local items = {
    [1001] = { 2, 22, "INVTYPE_CHEST", 4 },
    [1002] = { 2, 23, "INVTYPE_LEGS", 4 },
    [1003] = { 2, 24, "INVTYPE_WEAPON", 2 },
}

C_Item = {
    GetItemInfo = function(itemID)
        local item = items[itemID]
        if not item then return nil end
        return "item" .. itemID, nil, item[1], item[2], 1, "Armor", "Cloth", 1,
            item[3], 1, 10, item[4], 1, 2
    end,
    GetItemIDByGUID = function(guid) return tonumber(guid:match("Item%-(%d+)")) end,
}

-- Bag 0: slot 1 the chest, slot 2 the legs, slot 3 the sword.
local slots = { 1001, 1002, 1003 }
C_Container = {
    GetContainerItemID = function(_, slot) return slots[slot] end,
}

local targeting = false
SpellIsTargeting = function() return targeting end

local loot, lootSource = {}, nil
GetNumLootItems = function() return #loot end
GetLootSlotLink = function(slot) return ("|Hitem:%d::|h[x]|h"):format(loot[slot][1]) end
GetLootSlotInfo = function(slot) return "icon", "name", loot[slot][2] end
GetLootSourceInfo = function() return lootSource end

local prices = { [STRANGE_DUST] = 100, [LESSER_ASTRAL] = 1000, [SMALL_GLIMMERING] = 2000 }

assert(loadfile(lfs_cwd .. "/Core/Util.lua"))("Blackthornes_TS", ns)

ns.db = {}
ns.Prices = { GetValue = function(_, itemID) return prices[itemID] end }
ns.Inventory = { GetBagCounts = function() return { [1001] = 1, [1002] = 1, [1003] = 1 } end }

assert(loadfile(lfs_cwd .. "/Logic/Disenchant.lua"))("Blackthornes_TS", ns)
assert(loadfile(lfs_cwd .. "/Logic/DisenchantLog.lua"))("Blackthornes_TS", ns)

local Disenchant, Log = ns.Disenchant, ns.DisenchantLog

local checks = 0
local function check(label, condition)
    checks = checks + 1
    if not condition then error(("FAILED: %s"):format(label), 2) end
    print(("  ok  %s"):format(label))
end

local SPELL = 13262

--- One disenchant, the way the game plays it out.
local function Disenchantment(opts)
    clock = clock + 60

    if opts.click then
        targeting = true
        Log:OnBagClick(0, opts.click)
        targeting = false
    end

    Log:OnCastSent("UNIT_SPELLCAST_SENT", "player", opts.name or "", "cast", opts.spell or SPELL)
    clock = clock + 1.5
    Log:OnCastSucceeded("UNIT_SPELLCAST_SUCCEEDED", "player", "cast", opts.spell or SPELL)

    loot, lootSource = opts.loot or {}, opts.source
    clock = clock + 0.3
    Log:OnLootReady()
    Log:OnLootReady()   -- LOOT_OPENED follows LOOT_READY; it must not count twice
end

local function Casts(key)
    local band = Log:GetBand(key)
    return band and band.casts or 0
end

local CHEST_KEY = "2:armor:25"

print("\ntelling which item went in")

Disenchantment({ click = 1, loot = { { STRANGE_DUST, 5 } } })
check("a bag click names the item", Casts(CHEST_KEY) == 1)
check("found by the click, and counted once across both loot events", Log:GetTable().recent[1].from == "click")

Disenchantment({ loot = { { STRANGE_DUST, 4 } }, source = "Item-1002-0-ABC" })
check("the loot window's source names the item", Casts(CHEST_KEY) == 2
    and Log:GetTable().recent[1].itemID == 1002 and Log:GetTable().recent[1].from == "loot")

Disenchantment({ name = "item1001", loot = { { STRANGE_DUST, 6 } } })
check("the cast's item name finds it in the bags", Casts(CHEST_KEY) == 3
    and Log:GetTable().recent[1].from == "name")

Disenchantment({ name = "item1001 of the Bear", loot = { { STRANGE_DUST, 6 } } })
check("a random-suffix name still finds it", Casts(CHEST_KEY) == 4)

-- A click aimed at an enchant, then a Disenchant with nothing to go on.
clock = clock + 60
targeting = true
Log:OnBagClick(0, 3)
targeting = false
Log:OnCastSent("UNIT_SPELLCAST_SENT", "player", "item1003", "cast", 7418)
Disenchantment({ loot = { { STRANGE_DUST, 5 } } })
check("a click for some other spell is not taken as the target", Casts("2:weapon:25") == 0)
check("the disenchant is counted as missed instead", Log:GetTable().missed == 1)
check("and says why", Log:GetTable().lastMiss == "the game did not say which item was disenchanted")

Disenchantment({ click = 1, loot = { { LINEN, 2 } } })
check("loot that is not enchanting materials is not recorded", Casts(CHEST_KEY) == 4)
check("but counted as missed", Log:GetTable().missed == 2)

-- Any other spell's loot is none of this module's business.
Disenchantment({ click = 1, spell = 2575, loot = { { STRANGE_DUST, 5 } } })
check("loot after some other spell is ignored", Casts(CHEST_KEY) == 4 and Log:GetTable().missed == 2)

-- A value the game will not let us compare, as inside an instance.
local secret = setmetatable({}, { __eq = function() error("secret") end,
    __concat = function() error("secret") end })
local ok = pcall(Log.OnCastSent, Log, "UNIT_SPELLCAST_SENT", secret, secret, "cast", SPELL)
check("a secret unit is ignored, not an error", ok)

print("\nusing your results")

local outcomes, facts = Disenchant:GetOutcomes(1001)
check("with 4 recorded, the table is still used", facts.source == "table" and facts.casts == 4)
check("and says how many of yours there are", facts.key == CHEST_KEY)

-- Six more, one of which also gave a shard, to reach ten.
for index = 1, 6 do
    local got = { { STRANGE_DUST, 5 } }
    if index == 1 then got[2] = { SMALL_GLIMMERING, 1 } end
    Disenchantment({ click = 2, loot = got })
end

outcomes, facts = Disenchant:GetOutcomes(1002)
check("at ten, your results are used", facts.source == "yours" and facts.casts == 10)
check("dust came every time", outcomes[1].itemID == STRANGE_DUST and outcomes[1].chance == 1)
check("with the counts you saw", outcomes[1].min == 4 and outcomes[1].max == 6)
check("the shard once in ten", outcomes[2].itemID == SMALL_GLIMMERING and outcomes[2].chance == 0.1)
check("essence never, so it is not listed", #outcomes == 2)

-- Dust: 1.0 * 5.1 average * 100 = 510. Shard: 0.1 * 1 * 2000 = 200.
check("the value follows your results", Disenchant:GetValue(1002) == 710)

check("a weapon of the same level is still on the table",
    select(2, Disenchant:GetOutcomes(1003)).source == "table")

C_Item, C_Container, GetTime, CreateFrame = saved.C_Item, saved.C_Container, saved.GetTime, saved.CreateFrame
SpellIsTargeting, GetNumLootItems = saved.SpellIsTargeting, saved.GetNumLootItems
GetLootSlotLink, GetLootSlotInfo, GetLootSourceInfo =
    saved.GetLootSlotLink, saved.GetLootSlotInfo, saved.GetLootSourceInfo

print(("\n%d check(s) passed\n"):format(checks))
