-- Keep Salvager Results Apart goes on once, outside WoW.
--
-- It was off unless ticked for its first day, and the default was copied
-- into the save. Config:SalvagerApartOnOnce turns it on one time; a player
-- who unticks it after that keeps it off, and a new save starts on.

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
print("keep salvager results apart, on once")

check("on to start with", Config.DEFAULTS.settings.salvagerApart, true)

local db = { settings = { salvagerApart = false } }
ns.db = db
Config:SalvagerApartOnOnce(db)
check("a save with the old false is turned on", db.settings.salvagerApart, true)
check("and remembers it did", db.salvagerApartOnOnce, true)

Config:Set("salvagerApart", false)
Config:SalvagerApartOnOnce(db)
check("unticked after that, it stays off", db.settings.salvagerApart, false)

local fresh = { settings = { salvagerApart = true } }
ns.db = fresh
Config:SalvagerApartOnOnce(fresh)
check("a new save stays on", fresh.settings.salvagerApart, true)

ns.db = nil
print(string.format("\n%d passed, %d failed", passed, failed))
if failed > 0 then error("salvager apart on once: " .. failed .. " failed") end
