-- The craft queue keeps to this realm and side (a player's report,
-- 2026-11-28). The queue is shared by every character on the account, and
-- a player with an Alliance and a Horde character on one realm was shown
-- the other side's crafts, asked to buy their materials, and told the
-- other side would make a craft. Items never cross sides. What must hold:
--   1. The Queue tab and craft pane list only crafts made by a character
--      the one playing can mail. The stored queue is unchanged.
--   2. The materials list and the items kept off the sell list leave out
--      the other side's crafts.
--   3. Who makes a craft: never a character that can't mail it back, even
--      when nobody on this side knows it.
--   4. When the client won't say who is playing, nothing is hidden.

local saved = { C_Timer = C_Timer }
local function noop() end
C_Timer = { After = noop, NewTicker = function() return { Cancel = noop } end }

local ME, HALT, ALLY, FAR = "Player-1-ME", "Player-1-HALT", "Player-1-ALLY", "Player-2-FAR"
local CLOTH, SILK = 2589, 4306

local ns = {}
ns.NewModule = function(name) local m = {}; ns[name] = m; return m end
ns.RegisterCommand, ns.RegisterEvent = noop, noop
ns.Print, ns.PrintRaw, ns.Debug, ns.Warn = noop, noop, noop, noop
ns.Util = { HasFunction = function() return false end }
local config, selfKey = {}, ME
ns.Config = { Get = function(_, key) return config[key] end,
    GetCharacterKey = function() return selfKey end }

local BOLT = { name = "Bolt", outputItemID = 1, reagents = { { itemID = CLOTH, quantity = 2 } } }
local SILKBOLT = { name = "Silk Bolt", outputItemID = 2, reagents = { { itemID = SILK, quantity = 4 } } }
ns.db = {
    characters = {
        [ME] = { name = "Grosh", realm = "Forever PvE", faction = "Horde", recipes = { [10] = BOLT } },
        [HALT] = { name = "Zug", realm = "Forever PvE", faction = "Horde", recipes = {} },
        [ALLY] = { name = "Ana", realm = "Forever PvE", faction = "Alliance", recipes = { [20] = SILKBOLT } },
        [FAR] = { name = "Far", realm = "Elsewhere", faction = "Horde", recipes = { [20] = SILKBOLT } },
    },
    queue = {
        { recipeID = 10, quantity = 3, owner = ME },
        -- Queued on the Alliance character, for itself.
        { recipeID = 20, quantity = 5, owner = ALLY },
    },
}
ns.Recipes = {
    GetAny = function(_, recipeID)
        for key, record in pairs(ns.db.characters) do
            local recipe = record.recipes and record.recipes[recipeID]
            if recipe then return recipe, key end
        end
    end,
    IsDropped = function() return false end,
}

assert(loadfile(lfs_cwd .. "/Core/Characters.lua"))("Blackthornes_TS", ns)
assert(loadfile(lfs_cwd .. "/Logic/Queue.lua"))("Blackthornes_TS", ns)
local Queue = ns.Queue

local passed, failed = 0, 0
local function check(label, got, want)
    local ok = got == want
    if ok then passed = passed + 1 else failed = failed + 1 end
    print(string.format("  %-60s %-24s %s", label, tostring(got), ok and "ok" or
        ("WRONG, wanted " .. tostring(want))))
end
local function IDs(list)
    local ids = {}
    for i, entry in ipairs(list) do ids[i] = tostring(entry.recipeID) end
    return table.concat(ids, ",")
end

-- 1. What the Queue tab lists.
check("the Alliance craft is not listed on a Horde one", IDs(Queue:Shown()), "10")
check("it stays on the stored queue", IDs(Queue:GetAll()), "10,20")
check("it is out of reach", Queue:InReach(ns.db.queue[2]), false)
check("this side's craft is in reach", Queue:InReach(ns.db.queue[1]), true)
config.queueOnlyMine = true
check("Only My Crafts still lists mine", IDs(Queue:Shown()), "10")
config.queueOnlyMine = nil

-- 2. The items kept off the sell list.
local reserved = Queue:GetReservedItems()
check("cloth for this side's craft is kept", reserved[CLOTH], 6)
check("silk for the other side's craft is not", reserved[SILK], nil)

-- 3. Who makes a craft.
local oldStyle = { recipeID = 20, quantity = 1 }
check("an old craft nobody here knows is not the Alliance one's",
    Queue:GetCrafter(oldStyle) == ALLY, false)
check("nor the other realm's", Queue:GetCrafter(oldStyle) == FAR, false)
local forZug = { recipeID = 20, quantity = 1, owner = HALT }
check("Zug's craft nobody on his side knows stays Zug's", Queue:GetCrafter(forZug), HALT)
ns.db.characters[HALT].recipes = { [20] = SILKBOLT }
check("once Zug knows it, Zug makes it", Queue:GetCrafter(forZug), HALT)
ns.db.characters[HALT].recipes = {}

-- 4. Not sure who is playing.
selfKey = nil
check("unsure who is playing: nothing hidden", IDs(Queue:Shown()), "10,20")
selfKey = ME

-- Seen from the Alliance side, the Horde craft is the one left out.
selfKey = ALLY
check("from the Alliance side, only its own craft", IDs(Queue:Shown()), "20")
selfKey = ME

C_Timer = saved.C_Timer
print(string.format("\n%d passed, %d failed", passed, failed))
if failed > 0 then error(failed .. " failed") end
