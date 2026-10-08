-- Text size, outside WoW (a player's request, 2026-10-07: "I'm getting old").
--
-- What must hold:
--   1. Before the saved settings are in, every size is the normal one.
--   2. Large adds a point to every size and Larger two; a value the addon
--      does not know reads as Normal.
--   3. The step is read once: a change in the session leaves the text as it
--      is until /reload, so old and new text never mix.

local function noop() end

local function Fresh(settings, withDb)
    local ns = {}
    ns.COLORS = setmetatable({}, { __index = function() return "ffffffff" end })
    ns.NewModule = function(name) local m = ns[name] or {}; ns[name] = m; return m end
    ns.RegisterCommand, ns.RegisterEvent = noop, function() return true end
    ns.Print, ns.PrintRaw, ns.Debug, ns.Warn = noop, noop, noop, noop
    if withDb then ns.db = { global = {}, settings = settings } end
    ns.Config = { Get = function(_, key) return settings[key] end }
    assert(loadfile(lfs_cwd .. "/Core/Util.lua"))("Blackthornes_TS", ns)
    assert(loadfile(lfs_cwd .. "/UI/Theme.lua"))("Blackthornes_TS", ns)
    return ns.Theme, ns
end

local passed, failed = 0, 0
local function check(label, got, want)
    local ok = got == want
    if ok then passed = passed + 1 else failed = failed + 1 end
    print(string.format("  %-56s %-8s %s", label, tostring(got), ok and "ok" or ("WRONG, wanted " .. tostring(want))))
end

print("1. before the saved settings")
local Theme, ns = Fresh({ textSize = "larger" }, false)
check("small is 11", Theme.sizes.small, 11)
ns.db = { global = {}, settings = { textSize = "larger" } }
check("and the step is read once they are in", Theme.sizes.small, 13)

print("2. the steps")
Theme = Fresh({}, true)
check("Normal by default: tiny", Theme.sizes.tiny, 10)
check("title", Theme.sizes.title, 16)
Theme = Fresh({ textSize = "large" }, true)
check("Large: small", Theme.sizes.small, 12)
check("Large: large", Theme.sizes.large, 15)
Theme = Fresh({ textSize = "larger" }, true)
check("Larger: normal", Theme.sizes.normal, 14)
check("a size name it does not know is nil", Theme.sizes.huge, nil)
Theme = Fresh({ textSize = "giant" }, true)
check("an unknown text size reads as Normal", Theme.sizes.small, 11)

print("3. read once")
local settings = { textSize = "normal" }
Theme = Fresh(settings, true)
check("Normal", Theme.sizes.small, 11)
settings.textSize = "larger"
check("a change waits for /reload", Theme.sizes.small, 11)

print(string.format("\n%d passed, %d failed", passed, failed))
assert(failed == 0, "text size checks failed")
