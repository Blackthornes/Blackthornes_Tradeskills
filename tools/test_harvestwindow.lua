-- Skill-up colours read only from the window they belong to.
--
-- A player saw the Level Up tab's colours vanish and come back on their own
-- (2026-10-09). Recipes are read a few at a time, so a harvest could outlive
-- its profession window and keep asking GetRecipeInfo about recipes the
-- client no longer shows, saving whatever difficulty came back. Now a
-- harvest stops when the window opens, closes or changes profession, and
-- waits (a little, never for good) while the window is still settling.

local checks = 0
local function check(label, condition)
    checks = checks + 1
    if not condition then error(("FAILED: %s"):format(label), 2) end
    print(("  ok  %s"):format(label))
end

UnitName = function() return "Ana" end
UnitGUID = function() return "Player-1-A" end
UnitClass = function() return "Mage", "MAGE" end
UnitLevel = function() return 30 end
UnitFactionGroup = function() return "Horde" end
GetRealmName = function() return "Forever PvE" end
time = time or os.time

Enum = { TradeskillRelativeDifficulty = { Optimal = 0, Medium = 1, Easy = 2, Trivial = 3 } }

-- What the client answers about each recipe right now.
local difficulty = { [10] = 0, [20] = 1, [30] = 2 }
local ready, changing = true, false
C_TradeSkillUI = {
    GetAllRecipeIDs = function() return { 10, 20, 30 } end,
    GetRecipeInfo = function(id)
        return { name = "Recipe " .. id, learned = true, relativeDifficulty = difficulty[id], skillLineID = 197 }
    end,
    GetRecipeSchematic = function(id)
        return { outputItemID = id * 10, quantityMin = 1,
                 reagentSlotSchematics = { { reagentType = 1, quantityRequired = 1, reagents = { { itemID = 1 } } } } }
    end,
    IsTradeSkillReady = function() return ready end,
    IsDataSourceChanging = function() return changing end,
}

-- Timers run when the test says so.
local timers = {}
C_Timer = {
    NewTimer = function(_, fn)
        local t = { fn = fn, Cancel = function(self) self.cancelled = true end }
        timers[#timers + 1] = t
        return t
    end,
    NewTicker = function() return { Cancel = function() end } end,
}
local function RunTimers()
    local due = timers
    timers = {}
    for _, t in ipairs(due) do
        if not t.cancelled then t.fn() end
    end
end

-- A worker the test steps by hand, one recipe at a time.
local worker
local ns = {}
ns.NewModule = function(name) local m = {}; ns[name] = m; return m end
ns.RegisterCommand = function() end
local handlers = {}
ns.RegisterEvent = function(owner, event, fn)
    handlers[event] = handlers[event] or {}
    table.insert(handlers[event], function(...) fn(owner, event, ...) end)
    return true
end
local function Fire(event)
    for _, fn in ipairs(handlers[event] or {}) do fn() end
end
ns.Warn, ns.Print, ns.PrintRaw, ns.Debug = function() end, function() end, function() end, function() end
ns.COLORS = setmetatable({}, { __index = function() return "ffffffff" end })
ns.Util = {
    Count = function(t) local n = 0 for _ in pairs(t or {}) do n = n + 1 end return n end,
    CopyDeep = function(t) local c = {} for k, v in pairs(t) do c[k] = v end return c end,
    HasFunction = function(path) return path:match("^C_TradeSkillUI%.") ~= nil
        and C_TradeSkillUI[path:match("%.(.+)$")] ~= nil end,
    NewWorker = function(opts)
        worker = { opts = opts, items = {}, index = 0, running = false }
        function worker:Start(items) self.items, self.index, self.running = items, 0, true return self end
        function worker:Cancel()
            if not self.running then return end
            self.running = false
            if self.opts.onCancel then self.opts.onCancel(self) end
        end
        function worker:Step()
            if not self.running then return end
            self.index = self.index + 1
            self.opts.onItem(self.items[self.index], self.index, self)
            if self.running and self.index >= #self.items then
                self.running = false
                if self.opts.onDone then self.opts.onDone(self) end
            end
        end
        return worker
    end,
}
ns.Compat = { Get = function() return { tradeskill = { mode = "modern" } } end }

assert(loadfile(lfs_cwd .. "/Core/Config.lua"))("Blackthornes_TS", ns)
ns.Config.Get = function() return nil end
assert(loadfile(lfs_cwd .. "/Data/Recipes.lua"))("Blackthornes_TS", ns)
assert(loadfile(lfs_cwd .. "/Logic/SkillUp.lua"))("Blackthornes_TS", ns)

local SELF = "Player-1-A"
ns.db = { characters = { [SELF] = { name = "Ana", recipes = {}, inventory = {} } } }
ns.Config.characterKey = SELF

local Recipes = ns.Recipes
Recipes.RefreshProfessions = function() end
Recipes:OnEnable()

local function Tier(id)
    local recipe = ns.db.characters[SELF].recipes[id]
    return recipe and recipe.skillUp and recipe.skillUp.tier
end

print("\na harvest that finishes in its own window")
Fire("TRADE_SKILL_SHOW")
RunTimers()
check("a harvest started", worker and worker.running)
worker:Step() worker:Step() worker:Step()
check("every colour read", Tier(10) == "optimal" and Tier(20) == "medium" and Tier(30) == "easy")

print("\nthe window closes partway through a harvest")
Fire("TRADE_SKILL_LIST_UPDATE")
RunTimers()
worker:Step()
-- Gone: what the client says now is not this character's colour.
difficulty = { [10] = 3, [20] = 3, [30] = 3 }
Fire("TRADE_SKILL_CLOSE")
worker:Step()
check("the harvest stopped", not worker.running and not Recipes.harvesting)
check("the colours read before are kept", Tier(20) == "medium" and Tier(30) == "easy")

print("\nanother profession opened partway through")
difficulty = { [10] = 0, [20] = 1, [30] = 2 }
Fire("TRADE_SKILL_SHOW")
RunTimers()
local first = worker
first:Step()
difficulty = { [10] = 3, [20] = 3, [30] = 3 }
Fire("TRADE_SKILL_DATA_SOURCE_CHANGED")
first:Step()
check("the old harvest stopped", not first.running)
check("its unread recipes keep their colour", Tier(20) == "medium" and Tier(30) == "easy")
check("a fresh read of the new window is on its way", #timers > 0)
timers = {}

print("\na window still settling is waited for")
difficulty = { [10] = 0, [20] = 1, [30] = 2 }
ready = false
worker = nil
Fire("TRADE_SKILL_SHOW")
RunTimers()
check("no harvest while it is not ready", worker == nil)
ready = true
RunTimers()
check("read once it is", worker and worker.running)
worker:Step() worker:Step() worker:Step()
check("with the right colours", Tier(10) == "optimal" and Tier(30) == "easy")

print("\na client that never says ready is still read")
ready = false
worker = nil
Fire("TRADE_SKILL_LIST_UPDATE")
for _ = 1, 10 do RunTimers() end
check("after a few tries it reads anyway", worker ~= nil)
ready = true

print(("\n%d checks passed"):format(checks))
