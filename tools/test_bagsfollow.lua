-- The windows follow the bags soon after they settle.
--
-- A bag change reached the windows two seconds later, whatever it was, so
-- materials just bought or a craft just made took two seconds to show.
-- Inventory:OnBagUpdate now waits half a second, and no more often than
-- once every two seconds. What must hold:
--   1. One change after a quiet time is followed half a second later.
--   2. A burst of changes is still one look.
--   3. A change soon after a look waits until two seconds have gone by
--      since that look, so a run of crafts redraws no more often than it did.
--   4. The look tells the queue what moved and the windows to redraw.

-- Tests share one Lua state, so every global replaced here is put back,
-- including the ones that were not set at all.
local GLOBALS = { "GetTime", "time", "C_Timer", "C_Container", "GetMoney" }
local saved = {}
for _, key in ipairs(GLOBALS) do saved[key] = _G[key] end

local function noop() end

local clock = 1000
GetTime = function() return clock end
time = function() return 100000 end
GetMoney = function() return 0 end

local timers = {}
C_Timer = {
    After = noop,
    NewTimer = function(seconds, fn)
        local timer = { seconds = seconds, fn = fn, Cancel = noop }
        timers[#timers + 1] = timer
        return timer
    end,
}

local bag = { { itemID = 2589, stackCount = 20 } }
C_Container = {
    GetContainerNumSlots = function(index) return index == 0 and #bag or 0 end,
    GetContainerItemInfo = function(index, slot)
        local entry = index == 0 and bag[slot]
        return entry and { itemID = entry.itemID, stackCount = entry.stackCount } or nil
    end,
}

local ns = {}
ns.COLORS = setmetatable({}, { __index = function() return "ffffffff" end })
ns.NewModule = function(name) local m = {}; ns[name] = m; return m end
ns.RegisterCommand, ns.RegisterEvent = noop, noop
ns.Print, ns.PrintRaw, ns.Debug, ns.Warn = noop, noop, noop, noop

local record = { inventory = { [2589] = 20 } }
ns.Recipes = { GetCharacterRecord = function() return record end }
ns.Config = { Get = function() return nil end }

local redraws, moved = 0, nil
ns.UI = { OnInventoryUpdated = function() redraws = redraws + 1 end }
ns.Queue = { HoldingsChanged = function(_, changed) moved = changed end }

assert(loadfile(lfs_cwd .. "/Core/Util.lua"))("Blackthornes_TS", ns)
assert(loadfile(lfs_cwd .. "/Data/Inventory.lua"))("Blackthornes_TS", ns)
local Inventory = ns.Inventory

local passed, failed = 0, 0
local function check(label, got, want)
    local ok = got == want
    if ok then passed = passed + 1 else failed = failed + 1 end
    print(string.format("  %-62s %-6s %s", label, tostring(got), ok and "ok" or
        ("WRONG, wanted " .. tostring(want))))
end

--- Run the one timer waiting, as the game would after its wait.
local function RunTimer()
    local timer = table.remove(timers, 1)
    clock = clock + timer.seconds
    timer.fn()
end

print("")
print("the windows follow the bags")

bag[2] = { itemID = 2592, stackCount = 5 }
Inventory:OnBagUpdate()
check("one change asks for one look", #timers, 1)
check("half a second later", timers[1].seconds, Inventory.SNAPSHOT_SOON)
check("nothing is redrawn in the event itself", redraws, 0)

Inventory:OnBagUpdate()
Inventory:OnBagUpdate()
check("a burst of changes is still one look", #timers, 1)

RunTimer()
check("the look redraws the windows once", redraws, 1)
check("and tells the queue what moved", moved ~= nil and moved[2592] == true and moved[2589] == nil, true)
check("the count is saved for the other characters", record.inventory[2592], 5)

clock = clock + 0.25
Inventory:OnBagUpdate()
check("a change right after a look waits out the two seconds", timers[1].seconds, Inventory.SNAPSHOT_GAP - 0.25)
RunTimer()
check("then redraws", redraws, 2)

clock = clock + 30
Inventory:OnBagUpdate()
check("after a quiet time it is half a second again", timers[1].seconds, Inventory.SNAPSHOT_SOON)
RunTimer()
check("and redraws", redraws, 3)

for _, key in ipairs(GLOBALS) do _G[key] = saved[key] end

print("")
print(("%d passed, %d failed"):format(passed, failed))
assert(failed == 0, "bags follow checks failed")
