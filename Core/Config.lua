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

        -- What to list a craft at when nothing is competing with it: what
        -- its materials are worth, plus this much. Two cases reach it --
        -- no scan has ever priced the output, or every listing on the book
        -- is yours. Neither has a competitor's price to read, and holding at
        -- market value in the second means charging whatever you charged
        -- last time for as long as nobody turns up.
        --
        -- Only ever upwards: a market value above this is a real observation
        -- and keeps the price. It is labelled everywhere it appears, and is
        -- never written into the price database, because a number we worked
        -- out must not come back later looking like something the auction
        -- house said.
        unscannedMarkupPercent = 50,

        -- Turns the above off entirely: unscanned crafts go back to having
        -- no price at all, and an uncontested one back to market value.
        priceUnscannedCrafts = true,

        -- Stop recommending an item once this many are already listed.
        -- Zero means no limit. Per-item overrides live in db.postLimits.
        maxPostedPerItem = 0,

        -- Auction duration: 1 = 2h, 2 = 8h, 3 = 24h on this server. Only
        -- affects the deposit estimate, since listings are made by hand.
        postDuration = 2,

        -- Whether the Post tab lists everything in the bags or only what
        -- one of this account's recipes makes. A view, not a safety rail:
        -- nothing is ever listed without a click on its own row, and the
        -- bar's Post Crafted button stays crafted-only either way.
        postShowAllItems = true,

        -- Search the auction house for the item immediately before listing
        -- it. A full scan is a snapshot and goes stale; undercutting a price
        -- that moved ten minutes ago is how you end up listed above a rival.
        verifyPriceBeforePosting = true,

        -- Ask before each listing. Posting is irreversible without paying a
        -- second deposit, and listing can work through a whole bag, so the
        -- default is to confirm.
        confirmBeforePosting = true,

        -- Whether to recommend selling below material cost. Such items are
        -- always shown, just marked red and skipped when picking what is
        -- worth listing.
        allowPostingAtALoss = false,

        -- Hide crafts that have hit their posted limit rather than showing
        -- them greyed out.
        hideAtPostLimit = true,

        -- The craft pane's "Ignore max on hand" box: list every craft and let
        -- Add queue past the Keep in stock limit, without changing the limit.
        craftPaneIgnoreLimit = false,

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

        -- Write what one of each recipe sells for into Blizzard's own
        -- profession window, beside the recipe's name. Off leaves that window
        -- exactly as the client draws it.
        showValueInProfessionWindow = true,

        -- Put what an item is worth on the auction house onto the item's
        -- own tooltip, wherever the game draws one. Off leaves every
        -- tooltip exactly as the client writes it.
        showValueOnItemTooltips = true,

        -- Play a sound the moment the game says one of your auctions has
        -- sold, wherever you are. See Logic/SaleAlarm.lua.
        saleAlarm = true,

        -- When a reagent is cheaper to craft than to buy, queue that craft
        -- too rather than only saying so.
        autoQueueSubCrafts = true,

        -- Point out a material another of your characters can make for less
        -- than it costs to buy. Only a suggestion; the queue still buys it, so
        -- it is on by default. Named anew when the default changed, so a false
        -- the old default wrote into saved settings does not keep it off.
        suggestOtherCharacters = true,

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
    -- Mail:GetRestoredRollup.
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

-- A plain, non-empty string, or nil. The test and the copy happen inside the
-- pcall: logging in or reloading inside a dungeon can hand back a name the
-- addon may not compare or join, and the character key would raise forever.
local function PlainString(fn, ...)
    local ok, value = pcall(function(...)
        local v = fn(...)
        if type(v) == "string" and v ~= "" then return v .. "" end
    end, ...)
    if ok then return value end
    return nil
end

local function SafeUnitName()
    return PlainString(UnitName, "player") or "Unknown"
end

local function SafeRealmName()
    if type(GetRealmName) == "function" then
        return PlainString(GetRealmName) or "UnknownRealm"
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

-- Checked and copied inside the pcall for the same dungeon reason as the name.
local function SafeGUID()
    local ok, guid = pcall(function()
        local v = UnitGUID("player")
        if type(v) == "string" and v ~= "" then return v .. "" end
    end)
    if ok then return guid end
    return nil
end

--- How characters used to be filed: first name and realm. Saved data from
--- then stays under this key until its character next logs in.
function Config:GetLegacyCharacterKey()
    return SafeUnitName() .. "-" .. SafeRealmName()
end

--- Forever lets any number of characters share a first name; only the first
--- and last name together are unique. Name and realm therefore filed
--- "Voldar Ash" and "Voldar Stone" as one character. The character's GUID is
--- unique and never changes, so it is the key now.
---
--- The game has always handed the GUID over by PLAYER_LOGIN. Asked any
--- earlier, this answers with the old key and does not remember it.
function Config:GetCharacterKey()
    if self.characterKey then return self.characterKey end

    local guid = SafeGUID()
    if not guid or not ns.db then
        return self:GetLegacyCharacterKey()
    end

    self.characterKey = guid
    self:AdoptLegacyCharacter(guid)
    return guid
end

--- Move this character's saved record from the old name-realm key to its GUID.
---
--- Nothing is deleted or merged. An old record already claimed by a different
--- character is left for that character, and if this one already has a record
--- under its GUID the old one stays where it is.
function Config:AdoptLegacyCharacter(guid)
    local characters = ns.db and ns.db.characters
    if type(characters) ~= "table" then return end

    local legacy = self:GetLegacyCharacterKey()
    local old = characters[legacy]

    if type(old) ~= "table" then return end
    if old.guid and old.guid ~= guid then return end
    if characters[guid] ~= nil then return end

    old.guid = guid
    characters[guid] = old
    characters[legacy] = nil

    self.adoptedFrom = legacy
end

--- The last name, when the game will say what it is.
---
--- Nothing documents how Forever hands a last name to addons, so this looks
--- in the likely places: any name the unit functions return that starts with
--- the first name and a space, then any getter whose name mentions a last,
--- secondary or surname. `/bts whoami` shows what each of them said.
local SURNAME_PATTERNS = { "surname", "secondaryname", "lastname" }

function Config:FindSurnameFunctions()
    local found = {}

    local function Consider(label, name, fn)
        if type(fn) ~= "function" or type(name) ~= "string" then return end
        local lower = name:lower()
        if not (lower:find("^get") or lower:find("^unit")) then return end
        for _, pattern in ipairs(SURNAME_PATTERNS) do
            if lower:find(pattern, 1, true) then
                found[#found + 1] = { label = label, fn = fn }
                return
            end
        end
    end

    pcall(function()
        for name, value in pairs(_G) do
            Consider(name, name, value)
        end
        if type(C_PlayerInfo) == "table" then
            for name, value in pairs(C_PlayerInfo) do
                Consider("C_PlayerInfo." .. name, name, value)
            end
        end
    end)

    table.sort(found, function(a, b) return a.label < b.label end)
    return found
end

local function SurnameFrom(first, value)
    if type(value) ~= "string" or value == "" then return nil end
    local rest = value:match("^" .. first:gsub("%p", "%%%0") .. " (.+)$")
    if rest and rest ~= "" then return rest end
end

--- @return surname or nil, and a list of { label, values } describing what was asked
function Config:ReadSurname()
    local first = SafeUnitName()
    local asked, surname = {}, nil

    local function Ask(label, fn, ...)
        if type(fn) ~= "function" then
            asked[#asked + 1] = { label = label, missing = true }
            return
        end
        local results = { pcall(fn, ...) }
        local values = {}
        for i = 2, #results do
            values[#values + 1] = tostring(results[i])
        end
        asked[#asked + 1] = { label = label, ok = results[1], values = values }

        if not results[1] or surname then return end
        for i = 2, #results do
            local found = SurnameFrom(first, results[i])
            if found then surname = found return end
        end
    end

    Ask("UnitName", UnitName, "player")
    Ask("UnitFullName", UnitFullName, "player")
    Ask("GetUnitName", GetUnitName, "player", true)

    for _, candidate in ipairs(self:FindSurnameFunctions()) do
        local before = surname
        Ask(candidate.label, candidate.fn, "player")

        -- A getter named for the last name may return it bare.
        local last = asked[#asked]
        if not before and not surname and last.ok then
            local value = last.values[1]
            if value and value ~= "nil" and value ~= first and not value:find("[%s%-]") then
                surname = value
            end
        end
    end

    return surname, asked
end

--------------------------------------------------------------------------------
-- Bootstrap
--------------------------------------------------------------------------------

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

    if existing ~= "table" then
        -- The client handed back nothing: a first run, or a client that loses
        -- the saved file. Since build 1.60.1.70009 the game keeps it, so this
        -- is the rare case. The CVar store still covers a /reload on a client
        -- that does lose it.
        local stored = ns.Persist and ns.Persist:LoadAll()

        if stored then
            _G.BlackthornesTSDB = stored

            self.restoredFromCVars = true
            self.loadDiagnostics.restoredFromCVars = true
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

function Config:OnEnable()
    self:CheckLateSavedVariables()
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

        ns.Warn("the game loaded your saved data late, after login instead of at load. Please report this, then run /bts persist.")
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
        ns.Warn(("your saved data is from a newer version of the addon (format %d, this version reads %d); leaving it alone")
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

ns.RegisterCommand("db", "show what saved data loaded", function()
    local diagnostics = ns.Config:GetLoadDiagnostics()

    ns.Print("saved data")
    local source = ""
    if diagnostics.restoredFromCVars then
        source = "  (recovered from CVars)"
    end

    ns.PrintRaw(("  saved data type: %s%s"):format(
        tostring(diagnostics.globalType), source))
    ns.PrintRaw(("  loads before:    %s"):format(tostring(diagnostics.loadCountSeen)))
    ns.PrintRaw(("  loads now:       %s"):format(tostring(ns.db.probe.loadCount)))
    ns.PrintRaw(("  prices:          %d item(s)"):format(ns.Prices:Count()))
    ns.PrintRaw(("  recipes:         %d"):format(ns.Recipes:Count()))
    ns.PrintRaw(("  queue:           %d craft(s)"):format(ns.Queue:Count()))
    ns.PrintRaw(("  characters:      %d"):format(ns.Util.Count(ns.db.characters)))

    ns.PrintRaw(("  per-character:   %s, test value %s"):format(
        tostring(diagnostics.charGlobalType),
        tostring(diagnostics.charCanarySeen or "none")))

    if diagnostics.globalType ~= "table" then
        -- This client loses saved variables every session, so saying so on its
        -- own reads as data loss when the fallback has in fact just done its
        -- job. Say which of the three sources the database came from, because
        -- "nothing was handed back" and "nothing was recovered" are very
        -- different situations and only the second one is a problem.
        if diagnostics.restoredFromCVars then
            ns.Print("the game lost your saved data; it was recovered from CVars.")
        else
            ns.Warn("the game did not load any saved data this session,")
            ns.Warn("and nothing was recovered. This session starts empty.")
        end

        if diagnostics.charCanarySeen then
            ns.Print("|cff4fd18bper-character saved data DID load|r, so the queue could be kept there.")
        end
    end
end)

ns.RegisterCommand("whoami", "show what the game says this character is called", function()
    local Config = ns.Config
    local key = Config:GetCharacterKey()
    local surname, asked = Config:ReadSurname()

    ns.Print("this character")
    ns.PrintRaw(("  saved as:        %s"):format(key))
    ns.PrintRaw(("  old style key:   %s"):format(Config:GetLegacyCharacterKey()))
    ns.PrintRaw(("  last name found: %s"):format(surname or "none"))

    if Config.adoptedFrom then
        ns.PrintRaw(("  moved saved data from %s this session"):format(Config.adoptedFrom))
    end

    local realmOk, realm = pcall(GetRealmName)
    ns.PrintRaw(("  GetRealmName:    %s"):format(realmOk and tostring(realm) or "error"))

    for _, entry in ipairs(asked) do
        local answer
        if entry.missing then
            answer = "not in this client"
        elseif not entry.ok then
            answer = "error"
        elseif #entry.values == 0 then
            answer = "nothing"
        else
            answer = table.concat(entry.values, ", ")
        end
        ns.PrintRaw(("  %s: %s"):format(entry.label, answer))
    end

    local sameName = 0
    local first = key and ns.db.characters[key] and ns.db.characters[key].name
    for _, record in pairs(ns.db.characters) do
        if first and record.name == first then sameName = sameName + 1 end
    end
    ns.PrintRaw(("  saved characters with this first name: %d"):format(sameName))
end)

ns.RegisterCommand("debug", "turn extra chat detail on or off", function()
    if not ns.db then return end

    ns.db.global.debug = not ns.db.global.debug
    ns.Print("extra chat detail " .. (ns.db.global.debug and "on" or "off"))
end)
