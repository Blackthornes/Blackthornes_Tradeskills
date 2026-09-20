-- Blackthornes Tradeskills -- Core/Durable.lua
-- What survives a client restart on a machine with no helper script.
--
-- The client writes SavedVariables and never hands them back, and the CVar
-- store in Core/Persist.lua lives only as long as the client process. The one
-- store measured to cross a full quit on this build is macros, because they
-- are held server-side rather than in a file -- 11 of 11 came back on Trent's
-- own client on 2026-09-20.
--
-- Macros are small: 120 account-wide slots of 240 usable characters, about
-- 21KB once anything arbitrary is encoded. So this does not try to store the
-- database. It stores the parts that cannot rebuild themselves:
--
--   * settings         -- small, and annoying to re-enter
--   * the craft queue  -- what you had decided to make
--   * sell-through     -- what sold and what expired, per item
--
-- Prices are deliberately left out. They are by far the largest thing here
-- (171KB for 1542) and they rebuild on their own: the auction house scan runs
-- on AUCTION_HOUSE_SHOW and fills them in again. What sold never rebuilds,
-- which is what makes it worth a macro slot.
--
-- Measured cost of the whole payload, against the real serialiser:
--
--   sell-through, 200 items    15 macro(s)   (71 through the serialiser)
--   settings                    2 macro(s)
--   craft queue, 20 entries     7 macro(s)
--
-- The sell-through rollup is packed field by field into the macro alphabet
-- rather than serialised and then re-encoded, which is the whole difference:
-- 17 characters an item against 84.

local _, ns = ...

local Durable = ns.NewModule("Durable")

local FORMAT = 1                -- bumped when the payload's shape changes
local RECORD = 17               -- itemID(3) sold(2) units(2) expired(2) lastAt(3) net(5)
local SECONDS_PER_DAY = 86400

-- Anything below this and a save is not worth the macro writes; the data is
-- still in memory and in the CVar store for the rest of the session.
local MIN_SECONDS_BETWEEN_SAVES = 60

-- Characters given to the save stamp in the payload. See Build.
local STAMP_WIDTH = 6

--------------------------------------------------------------------------------
-- The payload
--
-- version(1) then sections, each tag(1) length(4) body(length). A reader that
-- meets a tag it does not know skips the body by its length, so an older
-- client can still read what it understands out of a newer payload.
--------------------------------------------------------------------------------

local function Pack(value, width) return ns.MacroStore.Pack(value, width) end
local function Unpack(text) return ns.MacroStore.Unpack(text) end

local function Section(tag, body)
    return tag .. Pack(#body, 4) .. body
end

--- Arbitrary Lua value -> safe alphabet, via the addon's own serialiser.
local function EncodeValue(value)
    local text = ns.Serialize.Encode(value)
    if type(text) ~= "string" then return nil end
    return ns.MacroStore.Encode(text)
end

local function DecodeValue(text)
    local bytes = ns.MacroStore.Decode(text)
    if not bytes then return nil end

    local ok, value = ns.Serialize.Decode(bytes)
    if not ok then return nil end
    return value
end

--- Do two queues hold the same crafts in the same order?
--
-- Only so a restore that changes nothing is not counted as having restored
-- something: "restored 1 value(s)" every login, for a queue that was already
-- identical, is the kind of line that teaches you to stop reading them.
local function SameQueue(a, b)
    a, b = a or {}, b or {}
    if #a ~= #b then return false end

    for index = 1, #a do
        local left, right = a[index], b[index]

        if type(left) ~= "table" or type(right) ~= "table" then return false end
        if left.recipeID ~= right.recipeID then return false end
        if left.quantity ~= right.quantity then return false end
    end

    return true
end

--------------------------------------------------------------------------------
-- Sell-through
--------------------------------------------------------------------------------

--- When the restored history was rolled up to, for a realm, or nil.
--
-- Every ledger entry from before this moment is already inside the restored
-- history, so it must not be added again. Written by Restore from the
-- payload's own save stamp, and read by everything that adds the ledger to
-- the history: BuildRollup here, and the Sales tab's totals in Data/Mail.lua.
function Durable:LedgerCutoff(realmKey)
    if not ns.db or type(ns.db.sellThroughRolledAt) ~= "table" then return nil end
    return tonumber(ns.db.sellThroughRolledAt[realmKey or ns.Config:GetRealmKey()])
end

--- Is this ledger entry already inside the restored history?
function Durable:IsRolledUp(entry, realmKey)
    local cutoff = self:LedgerCutoff(realmKey)
    return cutoff ~= nil and entry.t ~= nil and entry.t <= cutoff
end

--- Everything the market has judged, per item, for this realm.
--
-- The restored history and this session's ledger entries are added together
-- here, in Mail:GetSummary and in Mail:GetItems, and nowhere else.
-- db.sellThrough holds only what was restored and is never written to during
-- a session, so building the payload twice in one session cannot count the
-- same sale twice.
--
-- Across a /reload it could, and did: the CVar store carried the ledger over,
-- and Restore then filled the history from a payload that already had those
-- same entries rolled into it. One sale read as two, and the doubled figure
-- was what the next logout wrote. So the payload carries the moment it was
-- rolled up to, Restore records it, and a ledger entry from before that
-- moment is skipped here.
--
-- @param upTo  count ledger entries up to this time() only. Build passes the
--   save stamp so that an entry recorded in the same second, after the
--   payload was built, still counts next time.
function Durable:BuildRollup(realmKey, upTo)
    local rollup = {}
    local cutoff = self:LedgerCutoff(realmKey)

    local function Entry(itemID)
        rollup[itemID] = rollup[itemID]
            or { sold = 0, soldUnits = 0, expired = 0, lastAt = 0, net = 0 }
        return rollup[itemID]
    end

    local restored = ns.db and ns.db.sellThrough and ns.db.sellThrough[realmKey]

    if type(restored) == "table" then
        for itemID, record in pairs(restored) do
            if type(record) == "table" then
                local into = Entry(itemID)
                into.sold = into.sold + (record.sold or 0)
                into.soldUnits = into.soldUnits + (record.soldUnits or 0)
                into.expired = into.expired + (record.expired or 0)
                into.net = into.net + (record.net or 0)
                into.lastAt = math.max(into.lastAt, record.lastAt or 0)
            end
        end
    end

    local ledger = ns.db and ns.db.mailLedger and ns.db.mailLedger[realmKey]
    local entries = (type(ledger) == "table" and ledger.entries) or {}

    for _, entry in ipairs(entries) do
        local rolled = cutoff ~= nil and entry.t ~= nil and entry.t <= cutoff
        local later = upTo ~= nil and entry.t ~= nil and entry.t > upTo

        if entry.itemID and not rolled and not later then
            local into = Entry(entry.itemID)

            if entry.kind == "sold" then
                into.sold = into.sold + 1
                into.soldUnits = into.soldUnits + (entry.quantity or 1)
                into.net = into.net + (entry.net or 0)
            elseif entry.kind == "expired" then
                -- A cancellation is deliberately not counted: pulling a
                -- listing yourself says nothing about whether it would have
                -- sold, and counting it as a failure makes a session of
                -- relisting look like the price was wrong.
                into.expired = into.expired + 1
            end

            if entry.t then into.lastAt = math.max(into.lastAt, entry.t) end
        end
    end

    return rollup
end

local function PackRollup(rollup)
    local out = {}

    for itemID, record in pairs(rollup) do
        -- Whole days: the hour a sale landed is not worth a character, and
        -- staleness is the only question this answers.
        local days = math.floor((record.lastAt or 0) / SECONDS_PER_DAY)

        out[#out + 1] = Pack(itemID, 3) .. Pack(record.sold, 2)
            .. Pack(record.soldUnits, 2) .. Pack(record.expired, 2)
            .. Pack(days, 3) .. Pack(record.net, 5)
    end

    return table.concat(out)
end

local function UnpackRollup(text)
    if #text % RECORD ~= 0 then return nil end

    local rollup = {}

    for position = 1, #text, RECORD do
        local itemID = Unpack(text:sub(position, position + 2))
        local sold = Unpack(text:sub(position + 3, position + 4))
        local units = Unpack(text:sub(position + 5, position + 6))
        local expired = Unpack(text:sub(position + 7, position + 8))
        local days = Unpack(text:sub(position + 9, position + 11))
        local net = Unpack(text:sub(position + 12, position + 16))

        if not itemID or not sold or not units or not expired or not days or not net then
            return nil
        end

        rollup[itemID] = {
            sold = sold, soldUnits = units, expired = expired, net = net,
            lastAt = days * SECONDS_PER_DAY,
        }
    end

    return rollup
end

Durable.PackRollup, Durable.UnpackRollup = PackRollup, UnpackRollup

-- Exposed for tools/test_durable.lua, so a test can read a section back out of
-- a real payload rather than trusting what the module says it wrote.
Durable.DecodeForTest = DecodeValue

--------------------------------------------------------------------------------
-- Building and reading the whole payload
--------------------------------------------------------------------------------

--- The payload.
--
-- @param stamp  when this is being saved, as time(). Left out when the payload
--   is only being built to compare against the stored one -- a stamp inside
--   the compared text would differ every call and rewrite every macro on every
--   cadence tick, which the player can see happen.
function Durable:Build(stamp)
    if not ns.db then return nil end

    local realmKey = ns.Config:GetRealmKey()
    local parts = { Pack(FORMAT, 1) }

    -- Six characters: base 64, so 68 billion, where a whole-second clock is
    -- 1.8 billion. Four would have wrapped in 1970 and saturated ever since.
    if stamp then parts[#parts + 1] = Section("t", Pack(stamp, STAMP_WIDTH)) end

    local key = ns.MacroStore.Encode(realmKey)
    if key then parts[#parts + 1] = Section("k", key) end

    local settings = EncodeValue(ns.db.settings or {})
    if settings then parts[#parts + 1] = Section("s", settings) end

    local queue = EncodeValue(ns.db.queue or {})
    if queue then parts[#parts + 1] = Section("q", queue) end

    local rollup = PackRollup(self:BuildRollup(realmKey, stamp))
    if rollup ~= "" then parts[#parts + 1] = Section("r", rollup) end

    return table.concat(parts)
end

--- Take a payload apart. Returns a table of sections, or nil and why.
function Durable:Parse(text)
    if type(text) ~= "string" or text == "" then return nil, "empty" end

    local version = Unpack(text:sub(1, 1))
    if not version then return nil, "unreadable version" end
    if version > FORMAT then return nil, ("written by a newer version (%d)"):format(version) end

    local found = { version = version }
    local position = 2

    while position <= #text do
        local tag = text:sub(position, position)
        local length = Unpack(text:sub(position + 1, position + 4))

        if not length then return nil, "unreadable section length" end

        local from = position + 5
        local body = text:sub(from, from + length - 1)

        if #body ~= length then return nil, ("section '%s' is truncated"):format(tag) end

        found[tag] = body
        position = from + length
    end

    return found
end

--------------------------------------------------------------------------------
-- Saving and restoring
--------------------------------------------------------------------------------

--- Write the payload, unless it is the same one already stored.
-- @return true when something was written
function Durable:SaveIfChanged(force)
    if not ns.MacroStore or not ns.MacroStore:Detect().usable then return false, "no macro API" end

    local now = time()

    if not force and self.lastSaveAt and (now - self.lastSaveAt) < MIN_SECONDS_BETWEEN_SAVES then
        return false, "saved recently"
    end

    -- Built without the stamp first: that is the text worth comparing, since
    -- a stamp differs on every call and would make every payload look changed.
    local body = self:Build()
    if not body then return false, "nothing to save" end

    -- Macro writes are the expensive part and the player can see them happen,
    -- so an unchanged payload is not rewritten.
    if body == self.lastPayload then
        self.lastSaveAt = now
        return false, "unchanged"
    end

    local ok, detail = ns.MacroStore:SaveData(self:Build(now))

    if ok then
        self.lastPayload = body
        self.lastSaveAt = now
        self.lastResult = ("%d macro(s), %d characters"):format(detail, #body)

        -- Written into the database as well, so the two can be compared on a
        -- later login. The database travels by a different road -- the CVar
        -- store, or the generated data addon -- and either can arrive older
        -- than the macros. See the queue rule in Restore.
        ns.db.durableSavedAt = now
    else
        self.lastResult = tostring(detail)
    end

    return ok, detail
end

--- Write shortly after something changed, rather than waiting for the cadence.
--
-- The craft queue is the one stored thing that changes while you play, and
-- macros are the only copy of it that crosses a restart. Saving was tied to
-- the CVar cadence and to PLAYER_LOGOUT, which meant emptying the queue and
-- quitting inside the minute never reached the macros at all -- and the next
-- login restored the crafts you had just made, from a payload that had simply
-- never been told.
--
-- Forced past the minimum gap, because this fires on a real change rather than
-- on a timer. SaveIfChanged still skips an unchanged payload, so a burst of
-- edits collapses into one write and a no-op change costs nothing.
function Durable:SaveSoon(delay)
    if self.soonTimer then return end
    if not ns.MacroStore or not ns.MacroStore:Detect().usable then return end

    self.soonTimer = C_Timer.NewTimer(delay or 8, function()
        Durable.soonTimer = nil
        Durable:SaveIfChanged(true)
    end)
end

--- Read the payload back and fill in anything this session does not have.
--
-- Filling rather than replacing, for the same reason Config.FillGaps does:
-- the CVar store may already have carried this session's own work across a
-- reload, and it is fresher than a payload written at the last logout.
function Durable:Restore()
    if not ns.db then return false, "no database" end
    if not ns.MacroStore then return false, "no macro store" end

    local text, why = ns.MacroStore:LoadData()
    if not text then return false, why or "nothing stored" end

    local found, problem = self:Parse(text)
    if not found then return false, problem end

    self.restoredFrom = { characters = #text, version = found.version }

    local realmKey = found.k and ns.MacroStore.Decode(found.k) or ns.Config:GetRealmKey()
    local filled = 0

    if found.s then
        local settings = DecodeValue(found.s)
        if type(settings) == "table" then
            ns.db.settings = ns.db.settings or {}

            -- Not FillGaps: Bootstrap has already applied every default, so
            -- there is no gap left for a stored setting to fill. See the note
            -- on Config.FillOverDefaults.
            filled = filled + ns.Config.FillOverDefaults(ns.db.settings, settings,
                ns.Config.DEFAULTS and ns.Config.DEFAULTS.settings)
        end
    end

    if found.q then
        local queue = DecodeValue(found.q)

        if type(queue) == "table" then
            -- The queue is not gap-fillable data, and this is where that bit.
            --
            -- An empty queue is a real state -- you made everything on it --
            -- not an absence waiting to be filled. And a queue already sitting
            -- in memory at this point is NOT necessarily this session's work:
            -- Bootstrap ran back at ADDON_LOADED and loaded a whole database
            -- from the CVar store or, on a cold start, from the generated data
            -- addon, which is frozen until tools/restore.ps1 runs again. So
            -- "there are entries in memory, leave them alone" handed the stale
            -- copy the win on every single login, and the crafts you had
            -- already made came back every time.
            --
            -- Macros are written at PLAYER_LOGOUT, so on a cold start they are
            -- the freshest queue that exists. The stamps settle which is which
            -- rather than assuming: whichever was saved later wins, and when
            -- the payload wins it wins outright, empty included.
            local storedAt = found.t and Unpack(found.t) or nil
            local loadedAt = tonumber(ns.db.durableSavedAt)

            if storedAt and (not loadedAt or storedAt > loadedAt) then
                if not SameQueue(queue, ns.db.queue) then
                    ns.db.queue = queue
                    filled = filled + 1
                end

                self.queueAuthoritative = true

            -- No stamp means a payload written before saves carried one. Fall
            -- back to the old rule, which is safe where it is not helpful:
            -- seed an empty queue, never merge two lists of things to craft.
            elseif next(queue) and not next(ns.db.queue or {}) then
                ns.db.queue = queue
                filled = filled + 1
            end
        end
    end

    if found.r then
        local rollup = UnpackRollup(found.r)
        if rollup then
            ns.db.sellThrough = ns.db.sellThrough or {}
            ns.db.sellThroughRolledAt = ns.db.sellThroughRolledAt or {}

            self.restoredItems = 0
            for _ in pairs(rollup) do self.restoredItems = self.restoredItems + 1 end

            -- The payload's history is everything up to its save stamp: what
            -- was restored before it plus the ledger entries since, rolled
            -- in when it was written. So a payload saved after the history
            -- this database already carries replaces that history outright,
            -- and the stamp becomes the line the ledger is counted from.
            -- Filling gaps was wrong here: an item's old record stayed while
            -- its newer ledger entries were counted again on top.
            local storedAt = found.t and Unpack(found.t) or nil
            local rolledAt = self:LedgerCutoff(realmKey)

            if storedAt and (not rolledAt or storedAt > rolledAt) then
                ns.db.sellThrough[realmKey] = rollup
                ns.db.sellThroughRolledAt[realmKey] = storedAt
                filled = filled + self.restoredItems

            elseif not storedAt then
                -- A payload from before saves carried a stamp. Nothing says
                -- what it covers, so fill gaps as before.
                ns.db.sellThrough[realmKey] = ns.db.sellThrough[realmKey] or {}
                filled = filled + ns.Config.FillGaps(ns.db.sellThrough[realmKey], rollup)
            end
            -- Otherwise the database already holds this history or a newer
            -- one, carried across a /reload by the CVar store.
        end
    end

    self.restoredFrom.filled = filled

    return true, filled
end

--- The history restored from macro storage, for this realm, or nil.
--
-- Read-only by contract: nothing writes to it during a session, which is what
-- lets BuildRollup add it to the session's ledger without counting a sale
-- twice however many times a payload gets built.
function Durable:GetRestoredRollup()
    if not ns.db or not ns.db.sellThrough then return nil end

    local realmKey = ns.Config:GetRealmKey()
    local rollup = ns.db.sellThrough[realmKey]

    if type(rollup) ~= "table" or not next(rollup) then return nil end
    return rollup
end

--------------------------------------------------------------------------------
-- When
--------------------------------------------------------------------------------

function Durable:OnEnable()
    -- Not at ADDON_LOADED: the client is not reliably willing to talk about
    -- macros that early, and a restore that silently reads nothing is exactly
    -- the failure this project keeps finding. PLAYER_LOGIN is where
    -- Config:OnEnable does its late seeding for the same reason.
    local ok, detail = self:Restore()

    if ok and detail and detail > 0 then
        ns.Print(("restored %d value(s) from macro storage."):format(detail))

        -- After the fill, so a restored setting is mirrored into its CVar and
        -- the defaults cover anything neither store had.
        if ns.Config then ns.Config:ReapplyAfterRestore() end
    end

    ns.RegisterEvent(self, "PLAYER_LOGOUT", function()
        -- Whether a macro write is even allowed this late has never been
        -- proven on this client, which is why nothing may rely on it alone.
        -- SaveSoon is what actually keeps the stored queue current; this stays
        -- as the last chance to catch a change made in the final few seconds.
        Durable:SaveIfChanged(true)
    end)
end

--------------------------------------------------------------------------------
-- Reporting
--------------------------------------------------------------------------------

local function Line(label, value)
    ns.PrintRaw(("  |c%s%-18s|r %s"):format(ns.COLORS.muted, label, value))
end

--- How long ago, in words. The same shape Persist:Report uses, so the two
--- commands read alike when they are being compared line against line.
local function Ago(stamp)
    if not stamp then return "never" end

    local seconds = time() - stamp
    if seconds < 90 then return ("%d seconds ago"):format(math.max(0, seconds)) end
    if seconds < 5400 then return ("%d minutes ago"):format(math.floor(seconds / 60)) end
    if seconds < 172800 then return ("%d hours ago"):format(math.floor(seconds / 3600)) end

    return ("%d days ago"):format(math.floor(seconds / 86400))
end

--- What is in macro storage and what it cost, in game, where it can be
--- checked rather than reasoned about.
function Durable:Report()
    ns.Print("macro storage")

    if not ns.MacroStore or not ns.MacroStore:Detect().usable then
        ns.PrintRaw("  this client does not expose enough of the macro API.")
        return
    end

    local free, used = ns.MacroStore:FreeSlots()
    Line("macro slots", ("%s used, %s free of 120")
        :format(tostring(used or "?"), tostring(free or "?")))

    local stored, why = ns.MacroStore:LoadData()

    local found, queueEntries

    if stored then
        found = self:Parse(stored)

        if found and found.q then
            local queue = DecodeValue(found.q)
            if type(queue) == "table" then queueEntries = #queue end
        end

        local sections = {}

        for _, tag in ipairs({ "k", "t", "s", "q", "r" }) do
            local name = ({ k = "realm", t = "save time", s = "settings",
                            q = "queue", r = "sell-through" })[tag]
            if found and found[tag] then
                sections[#sections + 1] = tag == "r"
                    and ("%s (%d item(s))"):format(name, math.floor(#found[tag] / RECORD))
                    or name
            end
        end

        Line("stored", ("%s characters across %d macro(s)")
            :format(ns.Util.Comma(#stored), ns.MacroStore.SlotsFor(#stored)))
        Line("holding", #sections > 0 and table.concat(sections, ", ") or "nothing readable")
    else
        Line("stored", "|c" .. ns.COLORS.warn .. tostring(why or "nothing") .. "|r")
    end

    if self.restoredFrom then
        Line("restored", ("%d value(s) at login, %d item(s) of history")
            :format(self.restoredFrom.filled or 0, self.restoredItems or 0))
    else
        Line("restored", "nothing this session")
    end

    -- An outcome, not an attempt. The line above counts what the restore put
    -- into the database; this counts what is in there now, after everything
    -- else has had its turn. They disagreed once, and the attempt was the
    -- line that looked healthy.
    local differ, defaults = 0, ns.Config.DEFAULTS and ns.Config.DEFAULTS.settings

    if defaults and ns.db and ns.db.settings then
        for key, value in pairs(defaults) do
            if ns.db.settings[key] ~= nil and ns.db.settings[key] ~= value then
                differ = differ + 1
            end
        end
    end

    Line("settings now", ("%d differ from their defaults"):format(differ))

    -- The same outcome test for the history: what the restore holds, what
    -- the ledger adds on top, and the line between them. A sale counted on
    -- both sides of that line is the bug this exists to make visible.
    local realmKey = ns.Config:GetRealmKey()
    local cutoff = self:LedgerCutoff(realmKey)
    local restoredSales, restored = 0, ns.db and ns.db.sellThrough and ns.db.sellThrough[realmKey]

    if type(restored) == "table" then
        for _, record in pairs(restored) do
            restoredSales = restoredSales + (record.sold or 0)
        end
    end

    local ledger = ns.db and ns.db.mailLedger and ns.db.mailLedger[realmKey]
    local counted, skipped = 0, 0

    for _, entry in ipairs((type(ledger) == "table" and ledger.entries) or {}) do
        if entry.kind == "sold" then
            if cutoff and entry.t and entry.t <= cutoff then
                skipped = skipped + 1
            else
                counted = counted + 1
            end
        end
    end

    Line("history now", ("%d sale(s) restored, plus %d from this session's ledger; %d ledger sale(s) already inside the restored history%s")
        :format(restoredSales, counted, skipped,
            cutoff and (", rolled up " .. ns.Util.FormatAgeAgo(time() - cutoff)) or ""))

    -- The queue, reported as an outcome. Its two clocks are what decide
    -- whether a stale database or the macros win at login, and when they are
    -- wrong the symptom is crafts you already made coming back -- which looks
    -- nothing like a clock problem from the chat frame.
    Line("queue now", ("%d entr(ies)"):format(#((ns.db and ns.db.queue) or {})))

    local storedAt = found and found.t and Unpack(found.t) or nil
    local loadedAt = ns.db and tonumber(ns.db.durableSavedAt)

    Line("queue in macros", ("%d entr(ies), saved %s"):format(
        queueEntries or 0, Ago(storedAt)))
    Line("database saved", Ago(loadedAt))
    Line("which won", self.queueAuthoritative
        and "the macros, as the later save"
        or (storedAt and "the database, as the later save" or "no stamp stored yet"))

    local payload = self:Build()
    if payload then
        Line("next save", ("%s characters, %d macro(s)")
            :format(ns.Util.Comma(#payload), ns.MacroStore.SlotsFor(#payload)))
    end

    Line("last save", self.lastResult or "nothing written yet this session")
end

ns.RegisterCommand("durable", "what survives a restart: /bts durable [save|clear]", function(args)
    args = (args or ""):lower()

    if args == "save" then
        local ok, detail = ns.Durable:SaveIfChanged(true)
        ns.Print(ok and ("wrote %d macro(s)."):format(detail)
            or ("nothing written: %s."):format(tostring(detail)))
        return
    end

    if args == "clear" then
        ns.Print(("removed %d macro(s) of stored data."):format(ns.MacroStore:ClearData()))
        ns.Durable.lastPayload = nil
        return
    end

    ns.Durable:Report()
end)
