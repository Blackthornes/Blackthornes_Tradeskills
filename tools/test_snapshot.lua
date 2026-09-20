-- The local data addon's hand-off, and the one line that was eating it.
--
-- Blackthornes_TS_Data is a generated addon: it sets BlackthornesTSSnapshot to
-- the last session's database and BlackthornesTSSnapshotSource to a line
-- naming itself. It is an OptionalDeps of this addon, so the client loads it
-- FIRST -- and then this addon's own files run, in TOC order.
--
-- Data\Snapshot.lua is the first of those, and it used to say
-- "BlackthornesTSSnapshot = nil". That ran after the data addon had set the
-- global, so it erased the database on the way in and left the source string
-- behind. In game that reads as a contradiction: /bts persist naming the data
-- addon it loaded on one line and "this session started empty" on the next.
--
-- Every file this addon loads may read that global. None may assign it.

local failures = 0
local function Check(name, ok, detail)
    print(string.format("  %-52s %s", name, ok and "ok" or ("FAIL " .. tostring(detail))))
    if not ok then failures = failures + 1 end
end

--------------------------------------------------------------------------------
-- The TOC's load order, which is the whole point.
--------------------------------------------------------------------------------

local function TocFiles()
    local files = {}

    for line in io.lines("Blackthornes_TS.toc") do
        line = line:gsub("[\r\n]", ""):gsub("^%s+", ""):gsub("%s+$", "")

        if line ~= "" and line:sub(1, 2) ~= "##" and line:sub(1, 2) ~= "--" then
            files[#files + 1] = (line:gsub("\\", "/"))
        end
    end

    return files
end

local files = TocFiles()
Check("the TOC lists files", #files > 0, #files)
Check("Data/Snapshot.lua still loads first", files[1] == "Data/Snapshot.lua", tostring(files[1]))

--------------------------------------------------------------------------------
-- 1. The data addon hands a database over; the addon's own files must not
--    take it away again.
--------------------------------------------------------------------------------

local handed = { prices = { ["Classic Beta PvE 2-Horde"] = { [2589] = { market = 1234 } } } }

_G.BlackthornesTSSnapshot = handed
_G.BlackthornesTSSnapshotSource = "Blackthornes_TS_Data, written 2026-09-20 05:30"

local chunk = loadfile("Data/Snapshot.lua")
Check("Data/Snapshot.lua compiles", chunk ~= nil)

if chunk then
    chunk("Blackthornes_TS", {})
    Check("the handed-over database survives it", _G.BlackthornesTSSnapshot == handed,
        type(_G.BlackthornesTSSnapshot))
end

-- The two must never disagree: a source string with no table is exactly the
-- state that looked like the data addon failing when it had worked.
Check("the source and the table agree",
    (type(_G.BlackthornesTSSnapshot) == "table") ==
    (type(_G.BlackthornesTSSnapshotSource) == "string"),
    tostring(_G.BlackthornesTSSnapshot) .. " / " .. tostring(_G.BlackthornesTSSnapshotSource))

--------------------------------------------------------------------------------
-- 2. And no other file in the TOC does it either. Snapshot.lua was the one
--    that bit, but any of them would bite the same way.
--------------------------------------------------------------------------------

local assigners = {}

for _, path in ipairs(files) do
    local handle = io.open(path, "r")

    if not handle then
        Check("TOC file exists: " .. path, false, "missing")
    else
        local source = handle:read("*a")
        handle:close()

        for line in source:gmatch("[^\r\n]+") do
            -- Unindented, so this is an assignment the chunk runs the moment
            -- the client loads the file. Config:Bootstrap clears the global
            -- too, but it does it inside a function, after it has taken the
            -- database out -- which is the whole difference.
            if line:match("^BlackthornesTSSnapshot%s*=[^=]") or
               line:match("^_G%.BlackthornesTSSnapshot%s*=[^=]") then
                assigners[#assigners + 1] = path .. ": " .. line
            end
        end
    end
end

Check("no file loaded from the TOC assigns the global at load",
    #assigners == 0, table.concat(assigners, " | "))

--------------------------------------------------------------------------------
-- 3. Filling the CVar store's gaps from the data addon.
--
-- Measured in game 2026-09-20: a /reload restored 2,109 bytes from CVars --
-- the emptiness of a session that had itself started empty -- and that beat a
-- data addon holding the whole price history, because the CVar branch came
-- first and returned something. Neither store is chosen over the other now.
--------------------------------------------------------------------------------

local ns = { Util = {}, RegisterCommand = function() end }
ns.NewModule = function(name)
    ns[name] = {}
    return ns[name]
end
loadfile("Core/Config.lua")("Blackthornes_TS", ns)
local FillGaps = ns.Config.FillGaps

Check("FillGaps is reachable", type(FillGaps) == "function", type(FillGaps))

-- The shape of the failure: a store with the right keys and nothing under them.
local fromCVars = {
    schema = 1,
    prices = { ["Classic Beta PvE 2-Horde"] = {} },
    settings = { minProfit = 5000, valueOwnedMaterials = false },
    queue = {},
}

local fromAddon = {
    schema = 1,
    prices = { ["Classic Beta PvE 2-Horde"] = {
        [2589] = { market = 1234 }, [2592] = { market = 99 },
    } },
    settings = { minProfit = 100, auctionCut = 0.05 },
    ledger = { { item = 2589, sold = 1 } },
}

local filled = FillGaps(fromCVars, fromAddon)

Check("the gaps were filled", filled > 0, filled)
Check("prices came from the data addon",
    fromCVars.prices["Classic Beta PvE 2-Horde"][2589] ~= nil)
Check("both prices came, not just the first",
    fromCVars.prices["Classic Beta PvE 2-Horde"][2592] ~= nil)
Check("a whole key the store lacked came too", fromCVars.ledger ~= nil)

-- This is the half that matters more: the session's own work is not thrown
-- away to get the history back.
Check("this session's setting is kept, not overwritten",
    fromCVars.settings.minProfit == 5000, fromCVars.settings.minProfit)
Check("a false this session survives a true in the addon",
    fromCVars.settings.valueOwnedMaterials == false,
    tostring(fromCVars.settings.valueOwnedMaterials))
Check("a setting only the addon had is filled in",
    fromCVars.settings.auctionCut == 0.05, tostring(fromCVars.settings.auctionCut))

-- And the ordinary case, where the session is the fresher of the two: a real
-- price this session must not be replaced by the addon's older one.
local live = { prices = { R = { [2589] = { market = 5000 } } } }
FillGaps(live, { prices = { R = { [2589] = { market = 1 }, [2592] = { market = 7 } } } })
Check("a price this session already had is untouched",
    live.prices.R[2589].market == 5000, live.prices.R[2589].market)
Check("and one it did not have is added", live.prices.R[2592].market == 7)

Check("filling twice adds nothing the second time",
    FillGaps(fromCVars, fromAddon) == 0)

print(failures == 0 and "\nall snapshot hand-off tests passed" or ("\n" .. failures .. " failure(s)"))
if failures > 0 then error(failures .. " snapshot hand-off failure(s)") end
