-- Round-trip test for the export/import code.
--
-- The code is the only way settings and the queue survive a relog on this
-- client, so a format that exports something import cannot read would lose
-- exactly the data it exists to protect.

local ns = {}
ns.COLORS = setmetatable({}, { __index = function() return "ff" end })
ns.Print, ns.PrintRaw, ns.Debug, ns.Warn =
    function() end, function() end, function() end, function() end
ns.Util = { Count = function(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end }
ns.NewModule = function(name) local m = {} ns[name] = m return m end
ns.RegisterCommand = function() end
time = os.time

local settings = { undercutCopper = 1, auctionCut = 0.05, maxPostedPerItem = 0,
                   hideAtPostLimit = true, autoScan = true }
local DEFAULTS = { settings = { undercutCopper = 1, auctionCut = 0.05,
                                maxPostedPerItem = 0, hideAtPostLimit = true,
                                autoScan = true } }

ns.Config = {
    DEFAULTS = DEFAULTS,
    Get = function(_, k) return settings[k] end,
    Set = function(_, k, v) settings[k] = v end,
}

local queue = {}
ns.Queue = {
    GetAll = function() return queue end,
    Add = function(_, id, qty) queue[#queue + 1] = { recipeID = id, quantity = qty } end,
}

local limits = {}
ns.db = { postLimits = limits }
ns.Auctions = { SetLimit = function(_, id, n) limits[id] = n end }
ns.Recipes = { GetAny = function(_, id) return id ~= 999999 and { recipeID = id } or nil end }

local chunk = assert(loadfile(lfs_cwd .. "/Logic/Transfer.lua"))
chunk("Blackthornes_TS", ns)

-- A customised session.
settings.undercutCopper = 25
settings.maxPostedPerItem = 2
settings.hideAtPostLimit = false
queue[1] = { recipeID = 1263079, quantity = 5 }
queue[2] = { recipeID = 1263031, quantity = 2 }
queue[3] = { recipeID = 999999, quantity = 9 }   -- not known: must be skipped
queue[4] = { recipeID = 1229432, quantity = 1, isDependency = true }  -- derived
limits[2589] = 4

local code = ns.Transfer:Export()
print("\ncode: " .. code)

-- Wipe, as a relog would.
for i = #queue, 1, -1 do queue[i] = nil end
for k in pairs(limits) do limits[k] = nil end
settings.undercutCopper = 1
settings.maxPostedPerItem = 0
settings.hideAtPostLimit = true

local ok, message = ns.Transfer:Import(code)
print("import: " .. tostring(ok) .. " -- " .. message)

local pass = true
local function check(label, actual, expected)
    local good = actual == expected
    if not good then pass = false end
    print(string.format("  %-28s %-8s %s", label, tostring(actual),
        good and "ok" or ("EXPECTED " .. tostring(expected))))
end

print("")
check("undercutCopper", settings.undercutCopper, 25)
check("maxPostedPerItem", settings.maxPostedPerItem, 2)
check("hideAtPostLimit (false)", settings.hideAtPostLimit, false)
check("queue entries", #queue, 2)
check("first recipe", queue[1] and queue[1].recipeID, 1263079)
check("first quantity", queue[1] and queue[1].quantity, 5)
check("post limit 2589", limits[2589], 4)

print("\n" .. (pass and "PASS -- survives a wipe intact" or "FAIL"))
print("")
