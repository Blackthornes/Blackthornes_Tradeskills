-- Where the Enchant window sits (Trent, 2026-11-05: it opened behind the
-- queued crafts, which hang off the craft pane's right edge, and was hard to
-- move). It sits beside the queued crafts when they show, else the pane.

local ns = {}
ns.NewModule = function(name) local m = {}; ns[name] = m; return m end
ns.Theme, ns.Widgets = {}, {}
assert(loadfile(lfs_cwd .. "/UI/EnchantWindow.lua"))("Blackthornes_TS", ns)
local UI = ns.EnchantWindowUI

local checks = 0
local function check(label, condition)
    checks = checks + 1
    if not condition then error(("FAILED: %s"):format(label), 2) end
    print(("  ok  %s"):format(label))
end

local function F(shown) return { IsShown = function() return shown end } end

print("\nwhat it sits beside")
local pane, queued = F(true), F(true)
check("the queued crafts when they show", UI.Beside({ frame = pane, queuedFrame = queued }) == queued)
check("the pane when they don't", UI.Beside({ frame = pane, queuedFrame = F(false) }) == pane)
check("the pane before any are queued", UI.Beside({ frame = pane }) == pane)
check("nothing with the pane shut", UI.Beside({ frame = F(false) }) == nil)
check("nothing without the pane", UI.Beside(nil) == nil)

print(("\n%d check(s) passed\n"):format(checks))
