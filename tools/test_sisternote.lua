-- Core/SisterNote.lua outside WoW. The same test is in all five addons.
--
-- What must hold:
--   1. Two addons loaded print one line between them, not one each.
--   2. Only addons that are not installed are named; one turned off is not.
--   3. Once named, never again on this account, from any of them.
--   4. A sister never named before (one released later) is named.
--   5. Off in any of them is off in all; the command writes all of them.
--   6. One timer, no ticker; a client that will not say gives no line.

local suite = { checks = 0 }
local function check(label, ok, detail)
    suite.checks = suite.checks + 1
    if not ok then
        error(("sisternote: %s%s"):format(label, detail and ("  -> " .. tostring(detail)) or ""), 0)
    end
end

local saved = {
    C_AddOns = _G.C_AddOns, C_Timer = _G.C_Timer,
    IsAddOnLoaded = _G.IsAddOnLoaded, GetAddOnInfo = _G.GetAddOnInfo,
    BlackthornesSisterNote = _G.BlackthornesSisterNote,
}

local chat, timers, tickers

-- installed[folder] = "loaded" | "off"; anything else is not installed.
local installed

local function Client(opts)
    opts = opts or {}
    _G.BlackthornesSisterNote = nil
    chat, timers, tickers = {}, {}, 0
    _G.C_Timer = {
        After = function(_, fn) timers[#timers + 1] = fn end,
        NewTicker = function() tickers = tickers + 1 end,
    }
    _G.IsAddOnLoaded, _G.GetAddOnInfo = nil, nil
    if opts.silent then
        _G.C_AddOns = nil
        return
    end
    _G.C_AddOns = {
        IsAddOnLoaded = function(folder) return installed[folder] == "loaded" end,
    }
    if opts.infoOnly then
        _G.C_AddOns.GetAddOnInfo = function(folder)
            if not installed[folder] then return nil, nil, nil, false, "MISSING" end
            return folder, folder, "", installed[folder] == "loaded",
                installed[folder] == "off" and "DISABLED" or nil
        end
    else
        _G.C_AddOns.DoesAddOnExist = function(folder) return installed[folder] ~= nil end
    end
end

--- One addon as the client loads it: the file, then ADDON_LOADED's db.
local function Addon(folder, db)
    local ns = { COLORS = { accent = "ffc8a44d", muted = "ff8b919b" }, commands = {}, modules = {} }
    function ns.NewModule(name) local m = { moduleName = name } ns[name] = m ns.modules[#ns.modules + 1] = m return m end
    function ns.RegisterCommand(name, _, fn) ns.commands[name] = fn end
    function ns.PrintRaw(line) chat[#chat + 1] = line end
    function ns.Print(line) chat[#chat + 1] = line end
    function ns.Debug() end
    assert(loadfile(lfs_cwd .. "/Core/SisterNote.lua"))(folder, ns)
    ns.db = db
    return ns
end

local function Login(list)
    for _, ns in ipairs(list) do ns.SisterNote:OnInitialize() end
    for _, ns in ipairs(list) do ns.SisterNote:OnEnable() end
end

local function Fire()
    local run = timers
    timers = {}
    for _, fn in ipairs(run) do fn() end
end

--------------------------------------------------------------------------------
-- Two installed, one turned off, two missing
--------------------------------------------------------------------------------

installed = { Blackthornes_Farmer = "loaded", Blackthornes_TS = "loaded", Blackthornes_Pets = "off" }
Client()
local farmerDB, tsDB = {}, {}
local farmer = Addon("Blackthornes_Farmer", farmerDB)
local ts = Addon("Blackthornes_TS", tsDB)
Login({ farmer, ts })

check("one timer for both", #timers == 1, #timers)
check("and no ticker", tickers == 0)
check("nothing said before it fires", #chat == 0)
Fire()
check("one line between them", #chat == 1, #chat)

local line = chat[1] or ""
check("it names Equipment", line:find("Blackthornes Equipment", 1, true), line)
check("and Butler", line:find("Blackthornes Butler", 1, true), line)
check("and what each adds", line:find("what to do with every item in your bags", 1, true), line)
check("not Pets, which is installed but off", not line:find("Blackthornes Pets", 1, true), line)
check("not Tradeskills, which is loaded", not line:find("Tradeskills", 1, true), line)
check("it says once", line:find("shows once", 1, true), line)

check("Farmer's save remembers both", farmerDB.sisterNoteTold
    and farmerDB.sisterNoteTold.Blackthornes_Equipment and farmerDB.sisterNoteTold.Blackthornes_Butler)
check("so does Tradeskills'", tsDB.sisterNoteTold and tsDB.sisterNoteTold.Blackthornes_Butler)
check("nothing written for one it did not name", not farmerDB.sisterNoteTold.Blackthornes_Pets)

--------------------------------------------------------------------------------
-- The next login, and a later one with only Tradeskills
--------------------------------------------------------------------------------

Client()
farmer = Addon("Blackthornes_Farmer", farmerDB)
ts = Addon("Blackthornes_TS", tsDB)
Login({ farmer, ts })
Fire()
check("the next login says nothing", #chat == 0, chat[1])

installed = { Blackthornes_TS = "loaded", Blackthornes_Pets = "off" }
Client()
ts = Addon("Blackthornes_TS", tsDB)
Login({ ts })
Fire()
check("one newly missing is named", #chat == 1 and chat[1]:find("Blackthornes Farmer", 1, true), chat[1])
check("alone", not chat[1]:find("Butler", 1, true), chat[1])
check("with It's for one", chat[1]:find("It's on CurseForge", 1, true), chat[1])

--------------------------------------------------------------------------------
-- A sister released later
--------------------------------------------------------------------------------

installed = { Blackthornes_TS = "loaded" }
Client()
ts = Addon("Blackthornes_TS", tsDB)
ts.SisterNote.ADDONS[#ts.SisterNote.ADDONS + 1] =
    { folder = "Blackthornes_New", title = "Blackthornes New", adds = "something new" }
Login({ ts })
Fire()
check("a sister never named before is named", #chat == 1 and chat[1]:find("Blackthornes New", 1, true), chat[1])

--------------------------------------------------------------------------------
-- Turned off
--------------------------------------------------------------------------------

installed = { Blackthornes_Equipment = "loaded", Blackthornes_Pets = "loaded" }
Client()
local eqDB, petsDB = { sisterNote = false }, {}
local eq = Addon("Blackthornes_Equipment", eqDB)
local pets = Addon("Blackthornes_Pets", petsDB)
Login({ eq, pets })
Fire()
check("off in one is off in all", #chat == 0, chat[1])
check("and nothing is marked as named", petsDB.sisterNoteTold == nil)

pets.commands.sisters("")
check("the command turns it on in both", eqDB.sisterNote == true and petsDB.sisterNote == true)
pets.commands.sisters("")
check("and off in both", eqDB.sisterNote == false and petsDB.sisterNote == false)

--------------------------------------------------------------------------------
-- Other clients
--------------------------------------------------------------------------------

installed = { Blackthornes_Butler = "loaded", Blackthornes_Farmer = "off" }
Client({ infoOnly = true })
local butlerDB = {}
local butler = Addon("Blackthornes_Butler", butlerDB)
Login({ butler })
Fire()
check("GetAddOnInfo alone still tells missing from off", #chat == 1
    and not chat[1]:find("Farmer", 1, true) and chat[1]:find("Equipment", 1, true), chat[1])

Client({ silent = true })
butler = Addon("Blackthornes_Butler", {})
Login({ butler })
Fire()
check("a client that will not say gives no line", #chat == 0, chat[1])

for key, value in pairs(saved) do _G[key] = value end
print(("  sisternote: %d checks passed"):format(suite.checks))
