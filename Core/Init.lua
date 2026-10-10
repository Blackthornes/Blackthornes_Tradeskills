-- Blackthornes Tradeskills -- Core/Init.lua
-- Namespace, module registry, event dispatch and slash-command routing.
--
-- Deliberately dependency-free: Ace3/LibStub are not known to be ported to
-- WoW: Forever, and a hard dependency on somebody else's port schedule is a
-- worse trade than ~200 lines of framework we control.

local ADDON_NAME, ns = ...

_G.BlackthornesTS = ns

ns.ADDON_NAME = ADDON_NAME

local function GetMeta(field)
    if C_AddOns and C_AddOns.GetAddOnMetadata then
        local ok, value = pcall(C_AddOns.GetAddOnMetadata, ADDON_NAME, field)
        if ok then return value end
    end
    -- Bare GetAddOnMetadata is gone on mainline; kept only as a courtesy.
    if type(_G.GetAddOnMetadata) == "function" then
        local ok, value = pcall(_G.GetAddOnMetadata, ADDON_NAME, field)
        if ok then return value end
    end
    return nil
end

-- The TOC carries @project-version@, which the release packager rewrites to
-- the tag it is building, "v0.2.0" say. Running straight from the repository
-- there is no packager, so the keyword arrives unsubstituted and is shown as
-- "dev".
local function ReadVersion()
    local value = GetMeta("Version")
    if type(value) ~= "string" or value == "" then return "0.0.0" end
    if value:find("@", 1, true) then return "dev" end
    -- Tags start with a "v"; the version itself does not.
    return (value:gsub("^[vV]", ""))
end

ns.VERSION = ReadVersion()

--- The version as players see it: "v0.2.0", or "dev build" from a checkout.
function ns.VersionLabel()
    if ns.VERSION == "dev" then return "dev build" end
    return "v" .. ns.VERSION
end

--------------------------------------------------------------------------------
-- Output
--------------------------------------------------------------------------------

ns.COLORS = {
    accent = "ffc8a44d",
    profit = "ff4fd18b",
    loss   = "ffe5604f",
    muted  = "ff7a8089",
    warn   = "ffe8c15a",
    text   = "ffe6e8ec",
}

local PREFIX = "|c" .. ns.COLORS.accent .. "BTS|r "

local function Join(...)
    local n = select("#", ...)
    if n == 0 then return "" end
    local parts = {}
    for i = 1, n do
        parts[i] = tostring((select(i, ...)))
    end
    return table.concat(parts, " ")
end

-- Checks kept for Claude (the owner asked 2026-10-10): while a check such as
-- the probe runs, every line it prints is kept as well, and ns.KeepCheck
-- saves them as lastProbe in the account save, replacing the last one. The
-- game writes the save on /reload or logout, so the results can be read from
-- there instead of from screenshots.
local kept

--- A printed line as plain text: colours, links and icons taken out. A
--- secret value never reaches the save.
local function Plain(line)
    local ok, text = pcall(function()
        local isSecret = _G.issecretvalue
        if type(isSecret) == "function" and isSecret(line) then return "(secret)" end
        local plain = table.concat({ tostring(line) })
        plain = plain:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
        plain = plain:gsub("|H.-|h", ""):gsub("|h", ""):gsub("|T.-|t", "")
        return plain
    end)
    return ok and text or "(unreadable)"
end

local function Keep(line)
    if kept then kept[#kept + 1] = Plain(line) end
end

function ns.Print(...)
    local frame = DEFAULT_CHAT_FRAME
    if frame then
        local line = PREFIX .. Join(...)
        frame:AddMessage(line)
        Keep(line)
    end
end

-- Raw line with no prefix, for multi-line reports where the prefix is noise.
function ns.PrintRaw(...)
    local frame = DEFAULT_CHAT_FRAME
    if frame then
        local line = Join(...)
        frame:AddMessage(line)
        Keep(line)
    end
end

function ns.Debug(...)
    if ns.db and ns.db.global and ns.db.global.debug then
        ns.PrintRaw("|c" .. ns.COLORS.muted .. "BTS debug|r " .. Join(...))
    end
end

function ns.Warn(...)
    -- An item link or a coloured amount inside the message ends with |r,
    -- which would turn the rest of the line white; pick the colour up again.
    local text = Join(...):gsub("|r", "|r|c" .. ns.COLORS.warn)
    ns.Print("|c" .. ns.COLORS.warn .. text .. "|r")
end

--- Runs fn, a check that prints to chat, and saves what it printed as
--- lastProbe: which check, when, the addon version and the lines. Chat shows
--- the same as before, plus one line saying it was kept.
function ns.KeepCheck(name, fn, ...)
    kept = {}
    local ok, err = pcall(fn, ...)
    local lines = kept
    kept = nil
    if not ok then lines[#lines + 1] = "error: " .. Plain(err) end

    local db = ns.db and ns.db.global
    if type(db) == "table" then
        db.lastProbe = {
            check = name,
            at = type(date) == "function" and date("%Y-%m-%d %H:%M:%S") or nil,
            version = ns.VERSION,
            lines = lines,
        }
        ns.Print("Saved for Claude, /reload to write it.")
    end
    if not ok then error(err, 0) end
end

--------------------------------------------------------------------------------
-- Module registry
--------------------------------------------------------------------------------

ns.modules = {}
ns.moduleOrder = {}

local moduleProto = {}
moduleProto.__index = moduleProto

--- Register an event for this module.
-- @param event  event name
-- @param fn     handler, or nil to use self[event]
-- @return true if the client accepted the registration
function moduleProto:RegisterEvent(event, fn)
    return ns.RegisterEvent(self, event, fn or self[event])
end

function moduleProto:UnregisterEvent(event)
    return ns.UnregisterEvent(self, event)
end

function ns.NewModule(name)
    assert(type(name) == "string", "module name must be a string")
    assert(not ns.modules[name], "duplicate module: " .. name)

    local module = setmetatable({ moduleName = name }, moduleProto)
    ns.modules[name] = module
    ns.moduleOrder[#ns.moduleOrder + 1] = module
    ns[name] = module
    return module
end

--------------------------------------------------------------------------------
-- Event dispatch
--------------------------------------------------------------------------------

local eventFrame = CreateFrame("Frame", "BlackthornesTSEventFrame")
ns.eventFrame = eventFrame

local handlers = {}   -- event -> array of { owner = module, fn = function }
local unknownEvents = {}
-- Events asked for with the player as the only unit (RegisterPlayerEvent).
local playerOnly = {}

--- Register an event handler.
-- On Forever, registering an event the client does not know about raises a Lua
-- error rather than failing quietly, so every registration goes through pcall.
local function Register(owner, event, fn, playerOnlyWanted)
    if type(fn) ~= "function" then
        ns.Debug("RegisterEvent: no handler for", event)
        return false
    end

    local list = handlers[event]
    if not list then
        if unknownEvents[event] then return false end

        local ok, err = pcall(eventFrame.RegisterEvent, eventFrame, event)
        if not ok then
            unknownEvents[event] = err or true
            ns.Debug("event not in this version of the game:", event)
            return false
        end
        list = {}
        handlers[event] = list
    end

    -- Someone wants this event for every unit: lift the player-only filter.
    if playerOnly[event] and not playerOnlyWanted then
        playerOnly[event] = nil
        pcall(eventFrame.RegisterEvent, eventFrame, event)
    end

    list[#list + 1] = { owner = owner, fn = fn }
    return true
end

function ns.RegisterEvent(owner, event, fn)
    return Register(owner, event, fn, false)
end

--- Register a UNIT_ event handler that only cares about the player.
-- The game sends these for every unit near you (party, raid, nameplates), and
-- each one used to go through the dispatch only to be thrown away. While every
-- handler of the event is player-only, the client is asked to send the
-- player's alone. Handlers still check the unit themselves, so a client
-- without unit filtering, or a later handler that wants every unit, behaves
-- exactly as before.
function ns.RegisterPlayerEvent(owner, event, fn)
    local fresh = handlers[event] == nil
    if not Register(owner, event, fn, true) then return false end
    if fresh and type(eventFrame.RegisterUnitEvent) == "function"
        and pcall(eventFrame.RegisterUnitEvent, eventFrame, event, "player") then
        playerOnly[event] = true
    end
    return true
end

function ns.UnregisterEvent(owner, event)
    local old = handlers[event]
    if not old then return false end

    -- A new list rather than removing from the old one. A handler that
    -- unregisters itself does it while the old list is being walked, and
    -- removing from under the walk skipped the handler after it: the
    -- Disenchant button was not set up again after a fight that began at
    -- login, because the old macros' one-off handler came first.
    local list = {}
    for i = 1, #old do
        if old[i].owner ~= owner then
            list[#list + 1] = old[i]
        end
    end
    handlers[event] = list

    if #list == 0 then
        handlers[event] = nil
        playerOnly[event] = nil
        pcall(eventFrame.UnregisterEvent, eventFrame, event)
    end
    return true
end

--- Events the client rejected, so the probe can report them.
function ns.GetUnknownEvents()
    return unknownEvents
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
    local list = handlers[event]
    if not list then return end

    -- One handler erroring must not swallow the rest.
    for i = 1, #list do
        local entry = list[i]
        if entry then
            local ok, err = pcall(entry.fn, entry.owner, event, ...)
            if not ok then
                geterrorhandler()(err)
            end
        end
    end
end)

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

-- OnInitialize: saved variables are loaded and Config has run. Set up state.
-- OnEnable:     the world is loaded. Touch game data and build UI.

local initialized = false
local enabled = false

local function RunLifecycle(method)
    for i = 1, #ns.moduleOrder do
        local module = ns.moduleOrder[i]
        local fn = module[method]
        if type(fn) == "function" then
            local ok, err = pcall(fn, module)
            if not ok then
                ns.Warn(("module %s:%s failed"):format(module.moduleName, method))
                geterrorhandler()(err)
            end
        end
    end
end

local bootstrap = ns.NewModule("Bootstrap")

function bootstrap:ADDON_LOADED(_, loadedAddon)
    if loadedAddon ~= ADDON_NAME or initialized then return end
    initialized = true

    -- Config installs ns.db before anything else looks at saved variables.
    if ns.Config and ns.Config.Bootstrap then
        ns.Config:Bootstrap()
    end

    RunLifecycle("OnInitialize")
end

function bootstrap:PLAYER_LOGIN()
    if enabled then return end
    enabled = true
    RunLifecycle("OnEnable")
end

ns.RegisterEvent(bootstrap, "ADDON_LOADED", bootstrap.ADDON_LOADED)
ns.RegisterEvent(bootstrap, "PLAYER_LOGIN", bootstrap.PLAYER_LOGIN)

--------------------------------------------------------------------------------
-- Slash commands
--------------------------------------------------------------------------------

ns.commands = {}
ns.commandOrder = {}

--- Register a `/bts <name>` subcommand.
-- @param name  subcommand keyword (lowercase)
-- @param usage short description shown by `/bts help`
-- @param fn    function(argsString)
function ns.RegisterCommand(name, usage, fn)
    ns.commands[name] = { usage = usage, fn = fn }
    ns.commandOrder[#ns.commandOrder + 1] = name
end

-- The commands a player uses day to day, in the order /bts help shows them.
-- Everything else is a check or a developer tool, listed by /bts help all.
local PLAYER_COMMANDS = {
    "scan", "cancel", "top", "why", "price", "stock", "sold", "de",
    "haul", "mail", "salealarm", "pane", "professions", "size", "export", "import", "share",
}

local function HelpLine(name)
    local command = ns.commands[name]
    if not command then return end
    ns.PrintRaw(("  |c%s/bts %s|r  |c%s%s|r"):format(
        ns.COLORS.accent, name, ns.COLORS.muted, command.usage or ""))
end

local function ShowHelp(args)
    ns.Print(("|c%sBlackthornes Tradeskills|r %s"):format(ns.COLORS.accent, ns.VersionLabel()))

    if (args or ""):lower():match("^%s*all") then
        for i = 1, #ns.commandOrder do HelpLine(ns.commandOrder[i]) end
        return
    end

    ns.PrintRaw(("  |c%s/bts|r  |c%sopen or close the window|r"):format(ns.COLORS.accent, ns.COLORS.muted))
    for _, name in ipairs(PLAYER_COMMANDS) do HelpLine(name) end
    ns.PrintRaw(("  |c%s/bts help all|r shows more, including checks and developer tools."):format(
        ns.COLORS.accent))
end

ns.RegisterCommand("help", "show the main commands (/bts help all: every command)", ShowHelp)

SLASH_BLACKTHORNESTS1 = "/bts"
SLASH_BLACKTHORNESTS2 = "/blackthorne"

SlashCmdList["BLACKTHORNESTS"] = function(input)
    input = (input or ""):gsub("^%s+", ""):gsub("%s+$", "")

    local keyword, rest = input:match("^(%S+)%s*(.*)$")
    if not keyword then
        -- Bare /bts opens the window once the UI exists; until then, help.
        if ns.UI and ns.UI.Toggle then
            ns.UI:Toggle()
        else
            ShowHelp()
        end
        return
    end

    local command = ns.commands[keyword:lower()]
    if not command then
        ns.Print(("unknown command '%s'. Try |c%s/bts help|r."):format(keyword, ns.COLORS.accent))
        return
    end

    -- Wrapped because a command that errors is otherwise completely silent:
    -- this client does not show Lua errors unless scriptErrors is on, so a
    -- broken command and a command that did nothing look identical from the
    -- chat frame. "It isn't doing anything" is not a diagnosis anyone can act
    -- on, so say which of the two it was.
    local ok, err = pcall(command.fn, rest or "")

    if not ok then
        ns.Warn(("/bts %s failed: %s"):format(keyword, tostring(err)))
        geterrorhandler()(err)
    end
end
