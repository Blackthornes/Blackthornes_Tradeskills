-- A worker may start other workers from its own handlers.
--
-- A player saw "invalid key to 'next'" from Core/Util.lua (2026-11-16). The
-- worker frame walked its list of running workers with pairs(), and a
-- worker's onDone or onItem started another worker, adding a key to that
-- list mid-walk. Now each frame steps a copy of the list.

local checks = 0
local function check(label, condition)
    checks = checks + 1
    if not condition then error(("FAILED: %s"):format(label), 2) end
    print(("  ok  %s"):format(label))
end

local onUpdate
local savedCreateFrame, savedProfile, savedGetTime, savedHandler =
    CreateFrame, debugprofilestop, GetTime, geterrorhandler
CreateFrame = function()
    return {
        SetScript = function(_, _, fn) onUpdate = fn end,
        Show = function() end,
        Hide = function() end,
    }
end
local clock = 0
debugprofilestop = function() clock = clock + 1; return clock end
GetTime = function() return 1 end
geterrorhandler = function() return function(err) error(err, 0) end end

local ns = {}
assert(loadfile(lfs_cwd .. "/Core/Util.lua"))("Blackthornes_TS", ns)
local Util = ns.Util

local done, started = 0, {}
local first
first = Util.NewWorker({
    budgetMs = 1000,
    onItem = function() end,
    onDone = function()
        if #started > 0 then return end
        -- Many new workers at once, so the table grows mid-walk.
        for i = 1, 64 do
            local w = Util.NewWorker({ budgetMs = 1000, onItem = function() end,
                onDone = function() done = done + 1 end })
            started[i] = w
            w:Start({ 1, 2 })
        end
    end,
})
first:Start({ 1, 2, 3 })

local ok, err = pcall(function()
    for _ = 1, 5 do onUpdate() end
end)
check("starting workers from onDone raises nothing (" .. tostring(err) .. ")", ok)
check("every worker started from onDone finished", done == 64)

-- A worker that starts itself again from its own onDone.
local again = 0
local loop
loop = Util.NewWorker({ budgetMs = 1000, onItem = function() end,
    onDone = function()
        again = again + 1
        if again < 3 then loop:Start({ 1 }) end
    end })
loop:Start({ 1 })
ok, err = pcall(function() for _ = 1, 5 do onUpdate() end end)
check("a worker can start itself again from onDone", ok and again == 3)

local cancelled = Util.NewWorker({ onItem = function() end })
local killer = Util.NewWorker({ budgetMs = 1000,
    onItem = function() cancelled:Cancel() end })
cancelled:Start({ 1, 2, 3 })
killer:Start({ 1 })
ok, err = pcall(function() for _ = 1, 3 do onUpdate() end end)
check("cancelling another worker mid-frame raises nothing", ok)
check("the cancelled worker stays stopped", not cancelled:IsRunning())

CreateFrame, debugprofilestop, GetTime, geterrorhandler =
    savedCreateFrame, savedProfile, savedGetTime, savedHandler
print(("worker start: %d checks passed"):format(checks))
