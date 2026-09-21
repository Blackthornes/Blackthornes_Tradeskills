-- Blackthornes Tradeskills -- Core/Config.lua
-- Saved-variable bootstrap, schema versioning, and the persistence canary.
--
-- A community report on the Forever beta claims the client writes SavedVariables
-- but never reads them back. The whole price database depends on that being
-- wrong, so every login stamps a canary and reports whether the previous one
-- survived. `/bts probe` reads the answer out.

local _, ns = ...

local Config = ns.NewModule("Config")

local Util = ns.Util

Config.SCHEMA_VERSION = 1

--------------------------------------------------------------------------------
-- Defaults
--------------------------------------------------------------------------------

local DEFAULTS = {
    schema = Config.SCHEMA_VERSION,
    debug = false,

    global = {
        debug = false,
    },

    settings = {
        -- Value reagents you already own at market price (opportunity cost) or
        -- at zero (cash-out-of-pocket). Market is the honest default.
        valueOwnedMaterials = true,

        -- Auction-house cut applied to sale price. Overwritten by Compat once
        -- the probe observes the real value; never trust this literal.
        auctionCut = 0.05,

        -- How many times we assume an item is relisted before it sells, so the
        -- deposit is not silently ignored in the profit maths.
        expectedRelists = 1,

        -- Posting undercuts the cheapest listing by this much, and profit is
        -- calculated at that price. This models what you will actually receive
        -- rather than a smoothed market average you would never get.
        --
        -- Commodities only. An item auction cannot be priced in copper at all,
        -- so it steps by a whole silver or matches; see minProfit below.
        undercutCopper = 1,

        -- Stop recommending an item once this many are already listed.
        -- Zero means no limit. Per-item overrides live in db.postLimits.
        maxPostedPerItem = 0,

        -- Auction duration: 1 = 2h, 2 = 8h, 3 = 24h on this server. Only
        -- affects the deposit estimate, since listings are made by hand.
        postDuration = 2,

        -- Search the auction house for the item immediately before listing
        -- it. A full scan is a snapshot and goes stale; undercutting a price
        -- that moved ten minutes ago is how you end up listed above a rival.
        verifyPriceBeforePosting = true,

        -- Ask before each listing. Posting is irreversible without paying a
        -- second deposit, and Post All works through a whole bag, so the
        -- default is to confirm.
        confirmBeforePosting = true,

        -- Whether to recommend selling below material cost. Such items are
        -- always shown, just marked red and skipped when picking what is
        -- worth listing.
        allowPostingAtALoss = false,

        -- Hide crafts that have hit their posted limit rather than showing
        -- them greyed out.
        hideAtPostLimit = true,

        -- Count what is sitting in the mailbox as stock you own.
        --
        -- An expired auction comes back as mail, and until it is collected it
        -- is in neither your auctions nor your bags -- so without this the
        -- addon will tell you to craft more of something already on its way
        -- home. Off only if the mailbox reading ever misbehaves.
        countMailAsStock = true,

        -- How hard already owning some of an item pushes it down the Profit
        -- list. The rank is profit divided by (1 + stock * this), so 1 means a
        -- single one already held roughly halves a craft's place and 0 turns
        -- the whole thing off. Stock covers listed, bags, bank, mailbox and
        -- the craft queue.
        --
        -- There is no cap to configure anywhere: a second copy only sells once
        -- the first has, so it is genuinely worth less right now, and that is
        -- something the addon can work out for itself.
        stockPenalty = 1,

        -- Rows whose price data is older than this are rendered as stale.
        staleAfterSeconds = 48 * 3600,

        -- Hides crafts earning less than this, and does a second job on item
        -- auctions: those only take whole silver, so the smallest undercut
        -- available is a whole silver rather than a copper. That silver is
        -- only given up when the sale would still clear this. At zero, any
        -- craft still in profit undercuts.
        minProfit = 0,
        minMarginPercent = 0,

        scanBudgetMs = 8,

        -- Scan automatically when the auction house opens and the price
        -- data is missing or stale. On a client that loses saved data
        -- between sessions this is what makes the addon self-sufficient.
        autoScan = true,

        -- Read prices out of the searches the player runs in Blizzard's own
        -- auction house UI, as well as the addon's scans. The client announces
        -- every search result the same way whoever asked for it, so this costs
        -- no request and no throttle budget -- it is purely reading answers
        -- that have already arrived. Off puts the addon back to learning only
        -- from its own scans.
        learnFromSearches = true,

        -- When a reagent is cheaper to craft than to buy, queue that craft
        -- too rather than only saying so.
        autoQueueSubCrafts = true,

        -- How the mark on a craft that both skills you up and pays is drawn:
        -- "star" is the addon's own art, "raid" the game's raid-target star,
        -- "pip" a plain gold square for a client that draws neither. Switched
        -- in game with /bts star, because whether a texture resolves is the
        -- one thing that cannot be checked outside it.
        skillUpMarker = "star",
    },

    -- realmKey -> itemID -> price record
    prices = {},

    -- characterKey -> { name, realm, faction, class, professions, inventory, gold }
    characters = {},

    -- Persisted craft queue.
    queue = {},

    -- Auction deposits per item, learned at the auction house so profit can
    -- account for them anywhere.
    deposits = {},

    -- Per-item posted caps, and what is currently listed per realm.
    postLimits = {},
    postedAuctions = {},

    -- realmKey -> { entries, seen }: what sold and what came back, read out of
    -- the mailbox. See Data/Mail.lua.
    mailLedger = {},

    -- realmKey -> when the history restored from macro storage was rolled up
    -- to. Ledger entries from before that moment are already inside it. See
    -- Core/Durable.lua.
    sellThroughRolledAt = {},

    -- itemID -> true when the auction house sells it by the unit. Learned from
    -- the client when one is held and from searches otherwise; it never
    -- changes for an item, so it is kept. See Scanner:GetCommodityStatus.
    commodity = {},

    -- Written by Core/Compat.lua and Probe/Probe.lua.
    probe = {
        loadCount = 0,
        canary = nil,
        lastReport = nil,
    },
}

Config.DEFAULTS = DEFAULTS

--------------------------------------------------------------------------------
-- Keys
--------------------------------------------------------------------------------

local function SafeUnitName()
    local ok, name = pcall(UnitName, "player")
    if ok and name then return name end
    return "Unknown"
end

local function SafeRealmName()
    if type(GetRealmName) == "function" then
        local ok, realm = pcall(GetRealmName)
        if ok and realm then return realm end
    end
    return "UnknownRealm"
end

local function SafeFaction()
    local ok, faction = pcall(UnitFactionGroup, "player")
    if ok and faction then return faction end
    return "Neutral"
end

--- Prices are per realm AND per faction: a neutral AH still prices differently
--- across factions on split-auction realms, and merging them would be wrong.
function Config:GetRealmKey()
    if not self.realmKey then
        self.realmKey = SafeRealmName() .. "-" .. SafeFaction()
    end
    return self.realmKey
end

function Config:GetCharacterKey()
    if not self.characterKey then
        self.characterKey = SafeUnitName() .. "-" .. SafeRealmName()
    end
    return self.characterKey
end

--------------------------------------------------------------------------------
-- Bootstrap
--------------------------------------------------------------------------------

--- Copy across only what the target does not have, recursing into tables.
--
-- Two stores can both be real and neither complete. The CVar store belongs to
-- this client process, so on a /reload it holds this session's work and is
-- usually the fresher of the two. Usually is not always: a session that
-- started empty saves its emptiness, and that then beats a data addon holding
-- a real price history -- which is exactly what happened on 2026-09-20, with
-- a 2,109-byte CVar store winning over the whole database.
--
-- So neither store is chosen over the other. Anything already present wins,
-- because it is this session's, and everything absent is filled from the
-- other. Nothing is ever overwritten.
local function FillGaps(target, source, depth)
    depth = depth or 0
    if depth > 8 then return 0 end      -- serialised data is a tree; belt and braces

    local filled = 0

    for key, value in pairs(source) do
        local mine = target[key]

        if mine == nil then
            target[key] = value
            filled = filled + 1
        elseif type(mine) == "table" and type(value) == "table" then
            filled = filled + FillGaps(mine, value, depth + 1)
        end
    end

    return filled
end

-- Exposed so tools/test_snapshot.lua can exercise it against real shapes.
Config.FillGaps = FillGaps

--- Like FillGaps, but a value that still equals its default counts as absent.
--
-- FillGaps alone cannot restore a setting. Bootstrap applies DEFAULTS before
-- anything late runs, so by the time Durable reads macro storage at
-- PLAYER_LOGIN every settings key already holds something and there is no gap
-- left to fill. A stored setting was therefore shadowed by its own default on
-- every restart -- silently, and in a way that would have looked correct for
-- weeks before anyone noticed a setting reverting.
--
-- A value still equal to its default has never been deliberately set, so it is
-- indistinguishable from absent and the stored one may take its place. A value
-- that differs came from somewhere real -- this session, or the CVar store
-- carrying this session across a reload -- and still wins.
local function FillOverDefaults(target, source, defaults, depth)
    depth = depth or 0
    if depth > 8 then return 0 end

    local filled = 0

    for key, value in pairs(source) do
        local mine = target[key]

        -- Not `defaults[key] or nil`: a default of false is a default, and
        -- that idiom turned it into "no default", so a setting that is off by
        -- default and stored as on was read as deliberately chosen and never
        -- restored. Measured with allowPostingAtALoss.
        local fallback, hasDefault
        if type(defaults) == "table" then
            fallback = defaults[key]
            hasDefault = fallback ~= nil
        end

        if type(mine) == "table" and type(value) == "table" then
            filled = filled + FillOverDefaults(mine, value, fallback, depth + 1)

        elseif mine == nil or (hasDefault and mine == fallback) then
            -- Writing the same value back is not a restore; only a real change
            -- is worth counting, so the report cannot overstate what happened.
            if mine ~= value then
                target[key] = value
                filled = filled + 1
            end
        end
    end

    return filled
end

Config.FillOverDefaults = FillOverDefaults

--- Called from the ADDON_LOADED handler before any module initialises.
function Config:Bootstrap()
    -- First, before Compat's capability detection registers and writes CVars
    -- of its own: this records the client's state at login rather than the
    -- state we left it in on the way past.
    if ns.Persist then ns.Persist:Peek() end

    -- Recorded before anything is touched, so a failure to load can be told
    -- apart from a failure to save. Without this the two look identical
    -- from the outside.
    local existing = type(_G.BlackthornesTSDB)

    self.loadDiagnostics = {
        globalType = existing,
        hadProbe = existing == "table" and type(_G.BlackthornesTSDB.probe) == "table",
        loadCountSeen = existing == "table"
            and _G.BlackthornesTSDB.probe
            and _G.BlackthornesTSDB.probe.loadCount or nil,
    }

    -- Recorded whichever way the rest goes. On a login where the CVar store
    -- wins, this is the only line that says whether the data addon handed a
    -- database over at all -- and "it named the file but restored nothing"
    -- was the shape of the bug that cost a morning.
    self.loadDiagnostics.snapshotSeen = type(_G.BlackthornesTSSnapshot) == "table"

    if existing ~= "table" then
        -- The client handed back nothing. On the Forever beta that is the norm
        -- rather than a first run, so recover from the CVar store first: this
        -- build persists CVars even though it loses saved variables.
        local stored = ns.Persist and ns.Persist:LoadAll()
        local snapshot = self.loadDiagnostics.snapshotSeen
            and _G.BlackthornesTSSnapshot or nil

        if stored then
            _G.BlackthornesTSDB = stored

            self.restoredFromCVars = true
            self.loadDiagnostics.restoredFromCVars = true

            -- Both stores can be real and neither complete; see FillGaps.
            if snapshot then
                local filled = FillGaps(stored, snapshot)

                if filled > 0 then
                    self.restoredFromSnapshot = true
                    self.loadDiagnostics.filledFromSnapshot = filled
                    self.loadDiagnostics.snapshotSource = _G.BlackthornesTSSnapshotSource
                end
            end

        elseif snapshot then
            _G.BlackthornesTSDB = snapshot

            self.restoredFromSnapshot = true
            self.loadDiagnostics.restored = true
            self.loadDiagnostics.snapshotSource = _G.BlackthornesTSSnapshotSource
        else
            _G.BlackthornesTSDB = {}
            self.freshDatabase = true
        end

        -- Taken either way, so nothing downstream seeds from it twice.
        _G.BlackthornesTSSnapshot = nil
    end

    -- Per-character saved variables are a separate file and a separate code
    -- path in the client. The account-level one demonstrably does not load
    -- on this build; whether this one does is worth knowing, because the
    -- queue and settings could live here instead.
    local existingChar = type(_G.BlackthornesTSCharDB)

    self.loadDiagnostics.charGlobalType = existingChar
    self.loadDiagnostics.charCanarySeen =
        existingChar == "table" and _G.BlackthornesTSCharDB.canary or nil

    if existingChar ~= "table" then
        _G.BlackthornesTSCharDB = {}
    end

    -- Stamped every login so the next one can tell whether it survived.
    _G.BlackthornesTSCharDB.canary = (_G.BlackthornesTSCharDB.canary or 0) + 1

    local db = _G.BlackthornesTSDB

    self:Migrate(db)
    Util.ApplyDefaults(db, DEFAULTS)

    ns.db = db
    ns.charDb = _G.BlackthornesTSCharDB

    -- Kept so OnEnable can tell whether the client replaced the global after
    -- we installed ours. One report from another addon on this build has the
    -- saved table arriving late rather than never; if that happens here, this
    -- is what notices instead of quietly running on an empty database beside
    -- a full one.
    self.installedDB = db

    self:StampCanary(db)
    self:StampCVarCanary()

    -- After the defaults are in place, so a mirrored value wins over its
    -- default, and after the canary, which establishes whether CVars work.
    if ns.Persist then
        ns.Persist:RestoreSettings()
        ns.Persist:CheckSoak()
    end
end

--- Seed from the local data addon if it loaded after we did.
--
-- Blackthornes_TS.toc lists Blackthornes_TS_Data as an optional dependency,
-- which should make the client load it first. "Should" is doing a lot of work
-- there, and a price history is not the thing to bet on this client honouring
-- a load-order hint. Checking again costs one type() call.
function Config:OnEnable()
    self:CheckLateSavedVariables()

    if not self.freshDatabase then return end
    if type(_G.BlackthornesTSSnapshot) ~= "table" then return end

    local db = ns.db
    if not db then return end

    -- Mutated in place: modules that initialised before this hold a reference
    -- to the same table, and swapping it would leave them writing to an
    -- orphan that nothing ever saves.
    for key, value in pairs(_G.BlackthornesTSSnapshot) do
        if key ~= "probe" and key ~= "schema" then
            db[key] = value
        end
    end

    self.loadDiagnostics.snapshotSource = _G.BlackthornesTSSnapshotSource
    _G.BlackthornesTSSnapshot = nil

    self.freshDatabase = false
    self.restoredFromSnapshot = true
    self.loadDiagnostics.restored = true
    self.loadDiagnostics.restoredLate = true

    self:Migrate(db)
    Util.ApplyDefaults(db, DEFAULTS)

    -- Last, so a setting mirrored into a CVar this session still wins over the
    -- copy frozen into the snapshot, which is as old as the last restore.
    if ns.Persist then ns.Persist:RestoreSettings() end

    ns.Print("seeded the database from the local data addon.")
end

--- Settle the database again after something was restored into it late.
--
-- Durable restores at PLAYER_LOGIN, after Bootstrap has already applied
-- defaults and read the CVar store. A value filled in after that needs the
-- defaults run again for keys neither store had, and needs mirroring into its
-- CVar so the rest of the session agrees with it.
--
-- **The mirroring goes OUT, and only out.** `Persist:RestoreSettings` reads
-- CVars into the database, and on a cold start those CVars do not exist yet:
-- `RegisterOne` creates each one at its default and the read hands that
-- default straight back, over the top of whatever macro storage had just
-- restored. Calling it here undid the entire settings restore a few
-- milliseconds after it happened. Measured in game 2026-09-20 -- `/bts
-- durable` reported three values restored and the settings panel still showed
-- every default, because the report counted the fill and not the outcome.
function Config:ReapplyAfterRestore()
    local db = ns.db
    if not db then return end

    self:Migrate(db)
    Util.ApplyDefaults(db, DEFAULTS)

    if ns.Persist and db.settings then
        for key, value in pairs(db.settings) do
            ns.Persist:SaveSetting(key, value)
        end
    end
end

--- Did the client hand the saved table back after ADDON_LOADED?
--
-- Worth a look because it would change everything: if the saved variables are
-- late rather than absent, none of the rest of this is needed. It is reported
-- and never acted on -- swapping the live database out from under modules
-- that already hold a reference would be a worse bug than the one it fixes.
function Config:CheckLateSavedVariables()
    local current = _G.BlackthornesTSDB

    if type(current) == "table" and self.installedDB and current ~= self.installedDB then
        self.loadDiagnostics.lateSavedVariables = true

        ns.Warn("the client handed back its saved database after login, not at load. That is worth reporting -- run /bts persist.")
    end
end

--- Schema migrations. Each step upgrades one version to the next.
function Config:Migrate(db)
    local from = db.schema

    if from == nil then
        -- Either a brand new database or a pre-versioning one. Nothing to move.
        db.schema = Config.SCHEMA_VERSION
        return
    end

    if from > Config.SCHEMA_VERSION then
        ns.Warn(("saved data is from a newer version (schema %d > %d); leaving it alone")
            :format(from, Config.SCHEMA_VERSION))
        return
    end

    -- Future migrations land here as: if db.schema == 1 then ... db.schema = 2 end

    db.schema = Config.SCHEMA_VERSION
end

--------------------------------------------------------------------------------
-- Persistence canary
--------------------------------------------------------------------------------

--- Record whether the previous session's write survived, then stamp a new one.
function Config:StampCanary(db)
    local probe = db.probe or {}
    db.probe = probe

    local previous = probe.canary

    self.persistenceResult = {
        sawPrevious = previous ~= nil,
        previousStamp = previous and previous.stamp or nil,
        previousSession = previous and previous.session or nil,
        loadCountBefore = probe.loadCount or 0,
    }

    probe.loadCount = (probe.loadCount or 0) + 1
    probe.canary = {
        stamp = time(),
        session = probe.loadCount,
        version = ns.VERSION,
    }
end

--- The same canary again, but in a CVar rather than a saved variable.
--
-- Run because the two persist by different paths in the client: this build
-- writes SavedVariables and never reads them back, and if CVars survive a
-- logout they are somewhere to keep settings. Reading the old value before
-- writing the new one is what makes the answer meaningful.
local CVAR_CANARY = "BTS_sessionCount"

function Config:StampCVarCanary()
    local capable = ns.Compat and ns.Compat:Detect().cvars
    self.cvarResult = { supported = false }

    if not capable or not capable.roundTrip then return end

    self.cvarResult.supported = true

    -- Read before registering. Registering a name the client has not seen
    -- since launch can write the default over whatever it loaded, and this
    -- canary is precisely the thing that would then read as "never survived"
    -- when it had. See the note at the top of Core/Persist.lua.
    local raw = ns.Persist and ns.Persist.ReadRaw and ns.Persist.ReadRaw(CVAR_CANARY)
    local count = tonumber(raw or "") or 0

    if capable.registerVia == "RegisterAddonCVar" then
        pcall(C_CVar.RegisterAddonCVar, CVAR_CANARY)
    elseif capable.registerVia == "RegisterCVar" then
        pcall(C_CVar.RegisterCVar, CVAR_CANARY, "0")
    end

    if count == 0 then
        local ok, previous = pcall(C_CVar.GetCVar, CVAR_CANARY)
        count = (ok and tonumber(previous)) or 0
    end

    -- Zero means either a first run or a value that did not survive; those
    -- are the same observation from here, and the probe says so rather than
    -- claiming the mechanism is broken on the strength of one login.
    self.cvarResult.previousCount = count
    self.cvarResult.persisted = count > 0

    pcall(C_CVar.SetCVar, CVAR_CANARY, tostring(count + 1))
end

--- { supported, persisted, previousCount }
function Config:GetCVarResult()
    return self.cvarResult or { supported = false }
end

--- { sawPrevious, previousStamp, previousSession, loadCountBefore }
function Config:GetPersistenceResult()
    return self.persistenceResult
end

--- What the saved-variable global looked like at load time.
function Config:GetLoadDiagnostics()
    return self.loadDiagnostics or {}
end

--------------------------------------------------------------------------------
-- Accessors
--------------------------------------------------------------------------------

function Config:Get(key)
    return ns.db and ns.db.settings and ns.db.settings[key]
end

function Config:Set(key, value)
    if not ns.db then return end
    ns.db.settings[key] = value

    -- Mirrored out immediately rather than at logout: this client loses the
    -- saved file, and a setting only survives if the CVar is already written
    -- by the time the session ends.
    if ns.Persist then ns.Persist:SaveSetting(key, value) end
end

function Config:GetPriceTable()
    local realmKey = self:GetRealmKey()

    local prices = ns.db.prices
    if not prices[realmKey] then
        prices[realmKey] = {}
    end
    return prices[realmKey]
end

--------------------------------------------------------------------------------
-- Commands
--------------------------------------------------------------------------------

ns.RegisterCommand("db", "report what loaded from saved variables", function()
    local diagnostics = ns.Config:GetLoadDiagnostics()

    ns.Print("saved data")
    local source = ""
    if diagnostics.restoredFromCVars then
        source = "  (restored from CVars)"
    elseif diagnostics.restored then
        source = "  (restored from snapshot)"
    end

    ns.PrintRaw(("  global at load:  %s%s"):format(
        tostring(diagnostics.globalType), source))
    ns.PrintRaw(("  loadCount found: %s"):format(tostring(diagnostics.loadCountSeen)))
    ns.PrintRaw(("  loadCount now:   %s"):format(tostring(ns.db.probe.loadCount)))
    ns.PrintRaw(("  prices:          %d item(s)"):format(ns.Prices:Count()))
    ns.PrintRaw(("  recipes:         %d"):format(ns.Recipes:Count()))
    ns.PrintRaw(("  queue:           %d entr(ies)"):format(ns.Queue:Count()))
    ns.PrintRaw(("  characters:      %d"):format(ns.Util.Count(ns.db.characters)))

    ns.PrintRaw(("  per-character:   %s, canary %s"):format(
        tostring(diagnostics.charGlobalType),
        tostring(diagnostics.charCanarySeen or "none")))

    if diagnostics.globalType ~= "table" then
        -- This client loses saved variables every session, so saying so on its
        -- own reads as data loss when the fallback has in fact just done its
        -- job. Say which of the three sources the database came from, because
        -- "nothing was handed back" and "nothing was recovered" are very
        -- different situations and only the second one is a problem.
        if diagnostics.restoredFromCVars then
            ns.Print("the client lost your saved data; recovered it from CVars.")
        elseif diagnostics.restored then
            ns.Warn("the client lost your saved data; restored from the snapshot.")
            ns.Warn("run tools/restore.ps1 after this session to keep it current.")
        else
            ns.Warn("the client did not hand back any saved data this session,")
            ns.Warn("and nothing was recovered. This session starts empty.")
        end

        if diagnostics.charCanarySeen then
            ns.Print("|cff4fd18bper-character saved data DID load|r -- the queue can live there.")
        end
    end
end)

ns.RegisterCommand("debug", "toggle debug output", function()
    if not ns.db then return end

    ns.db.global.debug = not ns.db.global.debug
    ns.Print("debug output " .. (ns.db.global.debug and "on" or "off"))
end)
