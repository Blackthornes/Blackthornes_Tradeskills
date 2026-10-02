-- The last craft of a batch started here, with the profession window closed
-- during the run.
--
-- The watcher lets go of a batch on its first check after the last cast ends,
-- and its items reach the bags a moment later. With the window closed nothing
-- was reading the bags by then, so the last craft stayed on the queue for
-- good: reopening the window took the new bolt as already there.
--
-- What must hold:
--   1. The last craft of a batch is counted when its items land just after
--      the watcher has let go.
--   2. Stopping a batch with the window closed still counts the craft that
--      was under way.
--   3. Once that moment has passed, bags changing with the window closed are
--      left alone, as before.

-- Tests share one Lua state, so every global replaced here is put back,
-- including the ones that were not set at all.
local GLOBALS = { "GetTime", "time", "C_Timer", "UnitCastingInfo", "C_TradeSkillUI" }
local saved = {}
for _, key in ipairs(GLOBALS) do saved[key] = _G[key] end

local function noop() end

local now = 100
GetTime = function() return now end
time = function() return 100000 end

local ticker
C_Timer = {
    After = noop,
    NewTicker = function(_, fn)
        ticker = { fn = fn }
        ticker.Cancel = function() ticker = nil end
        return ticker
    end,
}

local casting, repeating = nil, false
UnitCastingInfo = function() return casting end
C_TradeSkillUI = {
    IsRecipeRepeating = function() return repeating end,
    StopRecipeRepeat = function() repeating = false end,
}

local BOLT, BOLT_RECIPE = 2996, 2963

local ns = {}
local handlers = {}
ns.NewModule = function(name) local m = {}; ns[name] = m; return m end
ns.RegisterCommand = noop
ns.RegisterEvent = function(owner, event, fn)
    handlers[event] = function(...) return fn(owner, event, ...) end
end
ns.Print, ns.PrintRaw, ns.Debug, ns.Warn = noop, noop, noop, noop
ns.Util = { HasFunction = function(path)
    return path == "C_TradeSkillUI.IsRecipeRepeating" or path == "C_TradeSkillUI.StopRecipeRepeat"
end }
ns.Config = { Get = function() return nil end, GetCharacterKey = function() return "me" end }

local RECIPES = {
    [BOLT_RECIPE] = { recipeID = BOLT_RECIPE, name = "Bolt of Linen Cloth", outputItemID = BOLT,
        quantityMin = 1, reagents = {} },
}
ns.Recipes = {
    GetAny = function(_, id) return RECIPES[id], "me" end,
    GetDisplayLink = function(_, id) return RECIPES[id].name end,
}

local bags = {}
ns.Inventory = {
    GetBagCount = function(_, id) return bags[id] or 0 end,
    GetOwnedCount = function(_, id) return bags[id] or 0 end,
}
ns.Cost = { GetCraftCost = function() return nil end, FindRecipeForItem = function() return nil end }
ns.db = { queue = {} }

assert(loadfile(lfs_cwd .. "/Logic/Queue.lua"))("Blackthornes_TS", ns)
assert(loadfile(lfs_cwd .. "/Logic/Crafting.lua"))("Blackthornes_TS", ns)
local Queue, Crafting = ns.Queue, ns.Crafting
Crafting:OnEnable()

local passed, failed = 0, 0

local function check(label, got, want)
    local ok = got == want
    if ok then passed = passed + 1 else failed = failed + 1 end
    print(string.format("  %-60s %-6s %s", label, tostring(got), ok and "ok" or
        ("WRONG, wanted " .. tostring(want))))
end

local function Left()
    local _, entry = Queue:Find(BOLT_RECIPE)
    return entry and entry.quantity or 0
end

--- A batch of `count` bolts started from the addon, as Crafting:Start leaves it.
local function StartBatch(count)
    ns.db.queue = { { recipeID = BOLT_RECIPE, quantity = count } }
    Crafting.isTradeSkillOpen = true
    Crafting:RememberOutputs()
    Crafting.active = { recipeID = BOLT_RECIPE, requested = count, outputItemID = BOLT,
        before = bags[BOLT] or 0, startedAt = now }
    Crafting:StartWatching()
end

--- One cast finishing; `last` when no more follow it.
local function CastEnds(last)
    casting, repeating = "Bolt of Linen Cloth", not last
    now = now + 2
    handlers.UNIT_SPELLCAST_SUCCEEDED("player", "cast", BOLT_RECIPE)
    casting = nil
end

local function BoltLands()
    bags[BOLT] = (bags[BOLT] or 0) + 1
    handlers.BAG_UPDATE_DELAYED()
end

print("the window closed during a batch of three")

do
    bags = {}
    StartBatch(3)
    Crafting:OnTradeSkillClose()

    CastEnds(false); BoltLands()
    CastEnds(false); BoltLands()
    check("two made: one left", Left(), 1)

    CastEnds(true)
    now = now + 0.2
    if ticker then ticker.fn() end
    check("the watcher has let go of the batch", Crafting.active, nil)

    BoltLands()
    check("the last bolt, landing after that, is counted", Left(), 0)
end

print("")
print("Stop with the window closed")

do
    bags = {}
    StartBatch(4)
    Crafting:OnTradeSkillClose()

    CastEnds(false); BoltLands()
    check("one made: three left", Left(), 3)

    -- Stop while the second is casting: it still finishes.
    casting, repeating = "Bolt of Linen Cloth", true
    Crafting:Stop()
    now = now + 2
    handlers.UNIT_SPELLCAST_SUCCEEDED("player", "cast", BOLT_RECIPE)
    casting = nil
    BoltLands()
    check("the craft under way when Stop was clicked counts", Left(), 2)

    -- Long after, with the window still closed: a bolt from anywhere else
    -- is not a craft.
    local before = Left()
    now = now + 60
    BoltLands()
    check("a bolt turning up later is not counted", Left(), before)
end

ns.db.queue = {}
for _, key in ipairs(GLOBALS) do _G[key] = saved[key] end

print("")
if failed > 0 then
    error(string.format("FAIL -- %d of %d last-craft checks wrong", failed, passed + failed))
end
print(string.format("PASS -- the last craft of a batch leaves the queue (%d checks)", passed))
