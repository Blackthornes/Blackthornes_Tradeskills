-- /bts import with the code typed after the command.
--
-- The chat box holds 255 letters, the command included, and quietly drops
-- whatever is pasted past that. A code cut there still read as a code: its
-- last number came in short ("2589:12" as "2589:1") and every section after
-- the cut was missing, with "restored" said all the same. A code that long
-- now opens the paste window instead, with a line saying why; a short one,
-- including any code from an older version, still imports from chat.

local GLOBALS = { "time" }
local saved = {}
for _, key in ipairs(GLOBALS) do saved[key] = _G[key] end

local function noop() end

local ns = {}
ns.COLORS = setmetatable({}, { __index = function() return "ff" end })
ns.PrintRaw, ns.Debug, ns.Warn = noop, noop, noop
ns.Util = { Count = function(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end }
ns.NewModule = function(name) local m = {} ns[name] = m return m end
time = os.time

local said = {}
ns.Print = function(text) said[#said + 1] = tostring(text) end

local commands = {}
ns.RegisterCommand = function(name, _, fn) commands[name] = fn end

local settings = { undercutCopper = 1, maxPostedPerItem = 0 }
ns.Config = {
    DEFAULTS = { settings = { undercutCopper = 1, maxPostedPerItem = 0 } },
    Get = function(_, key) return settings[key] end,
    Set = function(_, key, value) settings[key] = value end,
}

local queue = {}
ns.Queue = {
    GetAll = function() return queue end,
    Add = function(_, id, quantity) queue[#queue + 1] = { recipeID = id, quantity = quantity } end,
    Find = function(_, id)
        for index, entry in ipairs(queue) do
            if entry.recipeID == id then return index, entry end
        end
    end,
    RebuildDependencies = noop,
    Notify = noop,
}

local limits = {}
ns.db = { postLimits = limits }
ns.Auctions = { SetLimit = function(_, id, n) limits[id] = n end }
ns.Recipes = { GetAny = function(_, id) return { recipeID = id } end }

local dialogs = {}
ns.UI = {
    ShowTransferDialog = function(_, mode) dialogs[#dialogs + 1] = mode end,
    RefreshActiveTab = noop,
    UpdateHeader = noop,
}

assert(loadfile(lfs_cwd .. "/Logic/Transfer.lua"))("Blackthornes_TS", ns)

local passed, failed = 0, 0
local function check(label, got, expected)
    local ok = got == expected
    if ok then passed = passed + 1 else failed = failed + 1 end
    print(("  %-52s %-8s %s"):format(label, tostring(got), ok and "ok" or
        ("FAILED, expected " .. tostring(expected))))
end

local function Clear()
    for index = #queue, 1, -1 do queue[index] = nil end
    for key in pairs(limits) do limits[key] = nil end
    settings.undercutCopper, settings.maxPostedPerItem = 1, 0
    said, dialogs = {}, {}
end

local function Said(text)
    for _, line in ipairs(said) do
        if line:find(text, 1, true) then return true end
    end
    return false
end

--------------------------------------------------------------------------------
print("")
print("a short code still imports from chat")
--------------------------------------------------------------------------------

-- Written by an older version: no limits section at all.
Clear()
commands.import("BTS1~Q;1263079:5~S;undercutCopper=25")
check("its craft is queued",                           queue[1] and queue[1].quantity, 5)
check("its setting is set",                            settings.undercutCopper, 25)
check("no window opened",                              #dialogs, 0)

--------------------------------------------------------------------------------
print("")
print("a code long enough for the chat box to have cut")
--------------------------------------------------------------------------------

-- Forty crafts: far past what the chat box holds.
for index = 1, 40 do queue[index] = { recipeID = 1263000 + index, quantity = 12 } end
limits[2589] = 40
local code = ns.Transfer:Export()
check("the code is longer than the chat box",          #code > 255, true)

-- What the chat box hands over: the code cut off at its edge.
local cut = code:sub(1, 255 - #"/bts import ")
Clear()
commands.import(cut)
check("nothing is imported from it",                   #queue, 0)
check("the paste window opens instead",                dialogs[1], "import")
check("and chat says why",                             Said("too long for the chat box"), true)

-- Pasted into the window, the whole code imports.
Clear()
local ok = ns.Transfer:Import(code)
check("the window imports the whole code",             ok, true)
check("every craft",                                   #queue, 40)
check("at its own amount",                             queue[40] and queue[40].quantity, 12)
check("and the limit after them",                      limits[2589], 40)

-- Nothing after the command opens the window, as before.
Clear()
commands.import("")
check("a bare /bts import opens the window",           dialogs[1], "import")
check("and says nothing about length",                 #said, 0)

for _, key in ipairs(GLOBALS) do _G[key] = saved[key] end

print("")
print(("%d passed, %d failed"):format(passed, failed))
assert(failed == 0, "chat import checks failed")
