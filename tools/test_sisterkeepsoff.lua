-- "Keep What Other Addons Need" goes off once, outside WoW.
--
-- It was on by default for a day, and the default was copied into the
-- save. Config:SisterKeepsOffOnce turns that off one time; a player who
-- ticks it again keeps it, and a new save starts off.

local function noop() end

local ns = {}
ns.COLORS = setmetatable({}, { __index = function() return "ffffffff" end })
ns.NewModule = function(name) local m = { moduleName = name }; ns[name] = m; return m end
ns.RegisterEvent = noop
ns.RegisterCommand = noop
ns.Print, ns.PrintRaw, ns.Debug, ns.Warn = noop, noop, noop, noop
ns.Util = {}

assert(loadfile(lfs_cwd .. "/Core/Config.lua"))("Blackthornes_TS", ns)
local Config = ns.Config

local passed, failed = 0, 0
local function check(label, got, want)
    local ok = got == want
    if ok then passed = passed + 1 else failed = failed + 1 end
    print(string.format("  %-58s %-6s %s", label, tostring(got), ok and "ok" or
        ("WRONG, wanted " .. tostring(want))))
end

print("")
print("keep what other addons need, off once")

check("off unless ticked", Config.DEFAULTS.settings.sellHoldsSisterKeeps, false)
check("alts' upgrades off unless ticked", Config.DEFAULTS.settings.sellHoldsAltUpgrades, false)

local db = { settings = { sellHoldsSisterKeeps = true } }
ns.db = db
Config:SisterKeepsOffOnce(db)
check("a save with it on is turned off", db.settings.sellHoldsSisterKeeps, false)
check("and remembers it did", db.sisterKeepsOffOnce, true)

Config:Set("sellHoldsSisterKeeps", true)
Config:SisterKeepsOffOnce(db)
check("ticked again, it stays on", db.settings.sellHoldsSisterKeeps, true)

local fresh = { settings = { sellHoldsSisterKeeps = false } }
ns.db = fresh
Config:SisterKeepsOffOnce(fresh)
check("a new save stays off", fresh.settings.sellHoldsSisterKeeps, false)

ns.db = nil
print(string.format("\n%d passed, %d failed", passed, failed))
if failed > 0 then error("sister keeps off once: " .. failed .. " failed") end
