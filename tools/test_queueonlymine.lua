-- "Only My Crafts:" on the craft queue, outside WoW (a player asked, the
-- owner said build it, 2026-11-17).
--
-- What must hold:
--   1. Off (the default), the Queue tab and craft pane list the whole queue.
--   2. On, they list only the crafts the character playing makes, an old
--      record of that character included. The stored queue is unchanged.
--   3. When the client won't say who is playing, nothing is hidden.
--   4. The craft time adds up only the crafts shown.

local saved = { C_Timer = C_Timer }
local function noop() end
C_Timer = { After = noop, NewTicker = function() return { Cancel = noop } end }

local ns = {}
ns.NewModule = function(name) local m = {}; ns[name] = m; return m end
ns.RegisterCommand, ns.RegisterEvent = noop, noop
ns.Print, ns.PrintRaw, ns.Debug, ns.Warn = noop, noop, noop, noop
ns.Util = { HasFunction = function() return false end }
local config, selfKey = {}, "Player-1-ME"
ns.Config = { Get = function(_, key) return config[key] end,
    GetCharacterKey = function() return selfKey end }
-- "Me-Realm" is an old record of the character playing.
ns.Characters = { IsPlaying = function(_, key)
    return selfKey ~= nil and (key == selfKey or key == "Me-Realm") end }
ns.CraftTime = { GetCast = function() return 3 end }
ns.db = { queue = {
    { recipeID = 10, quantity = 2, crafter = "Player-1-ME" },
    { recipeID = 20, quantity = 5, crafter = "Player-1-ALT" },
    { recipeID = 30, quantity = 1, crafter = "Me-Realm" },
} }

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

-- 1. Off by default.
check("off: every craft shows", IDs(Queue:Shown()), "10,20,30")

-- 2. On.
config.queueOnlyMine = true
check("on: only this character's crafts", IDs(Queue:Shown()), "10,30")
check("the alt's craft stays on the queue", IDs(Queue:GetAll()), "10,20,30")
check("an old record of mine counts as mine", Queue:IsMine(ns.db.queue[3]), true)
check("the alt's craft is not mine", Queue:IsMine(ns.db.queue[2]), false)

-- 4. Craft time of what is shown: 3 crafts at 3 seconds.
check("craft time counts the shown crafts", Queue:GetCraftTime(Queue:Shown()).seconds, 9)
check("the whole queue without a list", Queue:GetCraftTime().seconds, 24)

-- 3. Not sure who is playing.
selfKey = nil
check("unsure who is playing: nothing hidden", IDs(Queue:Shown()), "10,20,30")

C_Timer = saved.C_Timer
print(string.format("\n%d passed, %d failed", passed, failed))
if failed > 0 then error(failed .. " failed") end
