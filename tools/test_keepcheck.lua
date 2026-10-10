-- Checks kept for Claude (the owner asked 2026-10-10): /bts probe prints to
-- chat as before, and what it printed is also saved as lastProbe in the
-- account save, so it can be read from the saved file after a /reload.

local failures = 0
local function check(label, ok, detail)
    if not ok then
        failures = failures + 1
        print(("FAIL: keepcheck: %s  -> %s"):format(label, tostring(detail)))
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

local chat = {}
local saved = { C_AddOns = C_AddOns, CreateFrame = CreateFrame, BlackthornesTS = BlackthornesTS,
                SlashCmdList = SlashCmdList, DEFAULT_CHAT_FRAME = DEFAULT_CHAT_FRAME,
                date = date, issecretvalue = issecretvalue }
C_AddOns = { GetAddOnMetadata = function(_, field) if field == "Version" then return "v1.2.3" end end }
CreateFrame = Frame
SlashCmdList = SlashCmdList or {}
DEFAULT_CHAT_FRAME = { AddMessage = function(_, message) chat[#chat + 1] = message end }
date = function() return "2026-10-10 12:00:00" end

local ns = {}
loadfile(lfs_cwd .. "/Core/Init.lua")("Blackthornes_TS", ns)
ns.db = { global = {} }

local function ChatText() return table.concat(chat, "\n") end

ns.KeepCheck("test", function()
    ns.Print("heading")
    ns.PrintRaw("  |cff7a8089has|r  a, b")
    ns.Warn("|Hitem:2589|h[Linen Cloth]|h missing")
end)

local kept = ns.db.global.lastProbe
check("the lines are saved in the account data", type(kept) == "table" and type(kept.lines) == "table")
check("with which check it was", kept.check == "test", kept.check)
check("when", kept.at == "2026-10-10 12:00:00", kept.at)
check("and the version", kept.version == "1.2.3", kept.version)
check("one line each", #kept.lines == 3, #kept.lines)
check("colours are taken out", kept.lines[1] == "BTS heading", kept.lines[1])
check("and the text kept", kept.lines[2] == "  has  a, b", kept.lines[2])
check("links keep their name", kept.lines[3]:find("[Linen Cloth] missing", 1, true), kept.lines[3])
check("chat says it was kept", ChatText():find("Saved for Claude, /reload to write it.", 1, true), ChatText())

ns.Print("after the check")
check("lines after the check are not kept", #ns.db.global.lastProbe.lines == 3)

issecretvalue = function(value) return value == "  secret" end
ns.KeepCheck("secret", function() ns.PrintRaw("  secret") end)
issecretvalue = nil
check("a secret value never reaches the save", ns.db.global.lastProbe.lines[1] == "(secret)",
    ns.db.global.lastProbe.lines[1])

local ok = pcall(ns.KeepCheck, "broken", function()
    ns.Print("half way")
    error("kaboom", 0)
end)
check("a failing check still fails", not ok)
check("and keeps what it printed and why", ns.db.global.lastProbe.lines[2] == "error: kaboom",
    ns.db.global.lastProbe.lines[2])

-- The probe command goes through it.
ns.Probe = {
    SampleTradeskill = function() end,
    SampleAuction = function() end,
    PrintReport = function() ns.Print("probe report") end,
}
local source = io.open(lfs_cwd .. "/Probe/Probe.lua"):read("*a")
local body = source:match('ns%.RegisterCommand%("probe".-\nend%)')
check("the probe command is found", body ~= nil)
if body then
    assert(loadstring("local ns = ...\n" .. body))(ns)
    ns.commands.probe.fn("")
    check("/bts probe is kept", ns.db.global.lastProbe.check == "probe", ns.db.global.lastProbe.check)
    check("with its report", ns.db.global.lastProbe.lines[1] == "BTS probe report",
        ns.db.global.lastProbe.lines[1])
end

for key, old in pairs(saved) do _G[key] = old end

if failures > 0 then error(("keepcheck: %d failure(s)"):format(failures), 0) end
print("  keepcheck: all checks passed")
