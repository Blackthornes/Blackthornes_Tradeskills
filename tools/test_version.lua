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
    function frame.SetScript() end
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

if failures > 0 then error(("version: %d failure(s)"):format(failures), 0) end
print("  version: 7 checks passed")
