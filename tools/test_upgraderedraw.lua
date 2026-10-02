-- Upgrades:RedrawSoon, outside WoW.
--
-- Blackthornes Equipment calls it when a player changes a stat weight, and
-- the gear and talent events call it here. What must hold:
--   1. Besides the main window's open tab, the craft pane and the sell list
--      are redrawn when they are showing. Both draw item icons, and the
--      main window's redraw alone left their arrows as they were.
--   2. A panel that is not showing is left alone.
--   3. A burst of calls costs one redraw, and one panel raising does not
--      stop the other.

-- Tests share one Lua state, so every global replaced here is put back,
-- including the ones that were not set at all.
local GLOBALS = { "C_Timer" }
local saved = {}
for _, key in ipairs(GLOBALS) do saved[key] = _G[key] end

local function noop() end

local timers = {}
C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end }
local function RunTimers()
    local due = timers
    timers = {}
    for _, fn in ipairs(due) do fn() end
end

local ns = {}
ns.NewModule = function(name) local m = {}; ns[name] = m; return m end
ns.RegisterEvent = noop
ns.Config = { Get = noop }

assert(loadfile(lfs_cwd .. "/Logic/Upgrades.lua"))("Blackthornes_TS", ns)
local Upgrades = ns.Upgrades

local count = { tab = 0, craft = 0, post = 0 }
local craftShown, postShown = true, true
local craftRaises = false

ns.UI = { RefreshActiveTab = function() count.tab = count.tab + 1 end }
ns.CraftPanel = {
    IsShown = function() return craftShown end,
    RequestRefresh = function()
        if craftRaises then error("craft pane broke") end
        count.craft = count.craft + 1
    end,
}
ns.PostPanel = {
    IsShown = function() return postShown end,
    Refresh = function() count.post = count.post + 1 end,
}

local passed, failed = 0, 0
local function check(label, got, want)
    local ok = got == want
    if ok then passed = passed + 1 else failed = failed + 1 end
    print(string.format("  %-58s %-6s %s", label, tostring(got), ok and "ok" or
        ("WRONG, wanted " .. tostring(want))))
end

local function Reset()
    count.tab, count.craft, count.post = 0, 0, 0
end

print("")
print("what is redrawn")

Upgrades:RedrawSoon()
check("nothing before things settle", count.tab + count.craft + count.post, 0)
RunTimers()
check("the open tab", count.tab, 1)
check("the craft pane", count.craft, 1)
check("the sell list", count.post, 1)

Reset()
craftShown, postShown = false, false
Upgrades:RedrawSoon()
RunTimers()
check("hidden panels are left alone", count.craft + count.post, 0)
check("the open tab still is", count.tab, 1)
craftShown, postShown = true, true

print("")
print("bursts and breakage")

Reset()
Upgrades:RedrawSoon()
Upgrades:RedrawSoon()
Upgrades:RedrawSoon()
RunTimers()
check("three calls, one redraw of the craft pane", count.craft, 1)
check("and of the sell list", count.post, 1)

Reset()
craftRaises = true
Upgrades:RedrawSoon()
local ok = pcall(RunTimers)
check("a craft pane that raises raises nothing here", ok, true)
check("and the sell list is still redrawn", count.post, 1)
craftRaises = false

Reset()
ns.CraftPanel, ns.PostPanel = nil, nil
Upgrades:RedrawSoon()
ok = pcall(RunTimers)
check("without the panels it still redraws the tab", ok and count.tab, 1)

for _, key in ipairs(GLOBALS) do _G[key] = saved[key] end

print("")
print(("%d passed, %d failed"):format(passed, failed))
assert(failed == 0, "upgrade redraw checks failed")
