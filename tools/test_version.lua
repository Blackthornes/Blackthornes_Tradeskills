-- The version the addon reports (Trent, 2026-09-25: "we need to be tracking
-- versioning somehow").
--
-- The TOC says `## Version: @project-version@` and the release packager
-- rewrites that to the tag it builds, which starts with a "v". The addon shows
-- the version with its own "v" in front, so it must drop the tag's or players
-- read "vv0.2.0". Straight from the repository the keyword arrives untouched,
-- and that is a dev build, not a version.

local failures = 0
local function check(label, ok, detail)
    if not ok then
        failures = failures + 1
        print(("FAIL: version: %s  -> %s"):format(label, tostring(detail)))
    end
end

-- Just enough client for Core/Init.lua to load.
local function Frame()
    local frame = {}
    function frame.RegisterEvent() end
    function frame.UnregisterEvent() end
    function frame.SetScript(self, name, fn) self[name] = fn end
    return frame
end

--- Load Core/Init.lua with the TOC's Version field reading `value`.
local function LoadWith(value)
    local saved = { C_AddOns = C_AddOns, CreateFrame = CreateFrame,
                    BlackthornesTS = BlackthornesTS, SlashCmdList = SlashCmdList }
    C_AddOns = {
        GetAddOnMetadata = function(_, field)
            if field == "Version" then return value end
        end,
    }
    CreateFrame = Frame
    SlashCmdList = SlashCmdList or {}
    local ns = {}
    loadfile(lfs_cwd .. "/Core/Init.lua")("Blackthornes_TS", ns)
    for key, old in pairs(saved) do _G[key] = old end
    return ns
end

local ns = LoadWith("v0.2.0")
check("a tag loses its v", ns.VERSION == "0.2.0", ns.VERSION)
check("and is shown with one", ns.VersionLabel() == "v0.2.0", ns.VersionLabel())

ns = LoadWith("v0.3.0-beta1")
check("a beta tag keeps its suffix", ns.VERSION == "0.3.0-beta1", ns.VERSION)

ns = LoadWith("0.2.1")
check("a bare version is kept", ns.VERSION == "0.2.1", ns.VERSION)

ns = LoadWith("@project-version@")
check("an unpackaged checkout is a dev build", ns.VERSION == "dev", ns.VERSION)
check("and says so", ns.VersionLabel() == "dev build", ns.VersionLabel())

ns = LoadWith(nil)
check("no version at all", ns.VERSION == "0.0.0", ns.VERSION)

-- /bts help: the player commands first and short, everything with "all".
ns = LoadWith("v0.2.0")
ns.RegisterCommand("scan", "scan the auction house", function() end)
ns.RegisterCommand("taint", "check whether the game lets this addon post", function() end)
local lines = {}
ns.Print = function(text) lines[#lines + 1] = text end
ns.PrintRaw = ns.Print
local function Shown(word)
    for _, line in ipairs(lines) do
        if line:find("/bts " .. word .. "|r", 1, true) then return true end
    end
    return false
end

ns.commands.help.fn("")
check("short help lists a player command", Shown("scan"), table.concat(lines, "\n"))
check("short help leaves out developer tools", not Shown("taint"), table.concat(lines, "\n"))
check("short help ends by pointing to /bts help all",
    lines[#lines]:find("/bts help all", 1, true) ~= nil, lines[#lines])

lines = {}
ns.commands.help.fn("all")
check("help all lists developer tools too", Shown("taint") and Shown("scan"), table.concat(lines, "\n"))

-- Events: a handler that unregisters itself mid-dispatch must not make the
-- next handler for that event miss it (the old macros' one-off combat-end
-- handler used to skip the Disenchant button's).
ns = LoadWith("v0.2.0")
local ran = {}
local first, second, third = {}, {}, {}
ns.RegisterEvent(first, "PLAYER_REGEN_ENABLED", function()
    ran[#ran + 1] = "first"
    ns.UnregisterEvent(first, "PLAYER_REGEN_ENABLED")
end)
ns.RegisterEvent(second, "PLAYER_REGEN_ENABLED", function() ran[#ran + 1] = "second" end)
ns.RegisterEvent(third, "PLAYER_REGEN_ENABLED", function() ran[#ran + 1] = "third" end)
ns.eventFrame.OnEvent(ns.eventFrame, "PLAYER_REGEN_ENABLED")
check("every handler runs when one unregisters itself",
    table.concat(ran, ",") == "first,second,third", table.concat(ran, ","))
ran = {}
ns.eventFrame.OnEvent(ns.eventFrame, "PLAYER_REGEN_ENABLED")
check("and the one that left is gone next time",
    table.concat(ran, ",") == "second,third", table.concat(ran, ","))

if failures > 0 then error(("version: %d failure(s)"):format(failures), 0) end
print("  version and help: all checks passed")
