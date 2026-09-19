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

        -- When a reagent is cheaper to craft than to buy, queue that craft
        -- too rather than only saying so.
        autoQueueSubCrafts = true,
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

--- Called from the ADDON_LOADED handler before any module initialises.
function Config:Bootstrap()
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

    if existing ~= "table" then
        -- The client handed back nothing. On the Forever beta that is the norm
        -- rather than a first run, so recover from the CVar store first: this
        -- build persists CVars even though it loses saved variables.
        local stored = ns.Persist and ns.Persist:LoadAll()

        if stored then
            _G.BlackthornesTSDB = stored

            self.restoredFromCVars = true
            self.loadDiagnostics.restoredFromCVars = true

        elseif type(_G.BlackthornesTSSnapshot) == "table" then
            _G.BlackthornesTSDB = _G.BlackthornesTSSnapshot
            _G.BlackthornesTSSnapshot = nil

            self.restoredFromSnapshot = true
            self.loadDiagnostics.restored = true
        else
            _G.BlackthornesTSDB = {}
            self.freshDatabase = true
        end
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

    self:StampCanary(db)
    self:StampCVarCanary()

    -- After the defaults are in place, so a mirrored value wins over its
    -- default, and after the canary, which establishes whether CVars work.
    if ns.Persist then
        ns.Persist:RestoreSettings()
        ns.Persist:CheckSoak()
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

    if capable.registerVia == "RegisterAddonCVar" then
        pcall(C_CVar.RegisterAddonCVar, CVAR_CANARY)
    elseif capable.registerVia == "RegisterCVar" then
        pcall(C_CVar.RegisterCVar, CVAR_CANARY, "0")
    end

    local ok, previous = pcall(C_CVar.GetCVar, CVAR_CANARY)
    local count = (ok and tonumber(previous)) or 0

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
