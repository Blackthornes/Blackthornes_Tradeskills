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

--------------------------------------------------------------------------------
-- Sell-through
--------------------------------------------------------------------------------

--- Everything the market has judged, per item, for this realm.
--
-- The restored history and this session's ledger entries are added together
-- here and nowhere else. db.sellThrough holds only what was restored and is
-- never written to during a session, so building the payload twice in one
-- session cannot count the same sale twice.
function Durable:BuildRollup(realmKey)
    local rollup = {}

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
        if entry.itemID then
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

--------------------------------------------------------------------------------
-- Building and reading the whole payload
--------------------------------------------------------------------------------

function Durable:Build()
    if not ns.db then return nil end

    local realmKey = ns.Config:GetRealmKey()
    local parts = { Pack(FORMAT, 1) }

    local key = ns.MacroStore.Encode(realmKey)
    if key then parts[#parts + 1] = Section("k", key) end

    local settings = EncodeValue(ns.db.settings or {})
    if settings then parts[#parts + 1] = Section("s", settings) end

    local queue = EncodeValue(ns.db.queue or {})
    if queue then parts[#parts + 1] = Section("q", queue) end

    local rollup = PackRollup(self:BuildRollup(realmKey))
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

    local payload = self:Build()
    if not payload then return false, "nothing to save" end

    -- Macro writes are the expensive part and the player can see them happen,
    -- so an unchanged payload is not rewritten.
    if payload == self.lastPayload then
        self.lastSaveAt = now
        return false, "unchanged"
    end

    local ok, detail = ns.MacroStore:SaveData(payload)

    if ok then
        self.lastPayload = payload
        self.lastSaveAt = now
        self.lastResult = ("%d macro(s), %d characters"):format(detail, #payload)
    else
        self.lastResult = tostring(detail)
    end

    return ok, detail
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
            filled = filled + ns.Config.FillGaps(ns.db.settings, settings)
        end
    end

    if found.q then
        local queue = DecodeValue(found.q)
        -- An empty queue in memory is the normal case after a restart, and a
        -- queue with entries in it is this session's -- so only seed the
        -- empty one rather than merging two lists of things to craft.
        if type(queue) == "table" and next(queue) and not next(ns.db.queue or {}) then
            ns.db.queue = queue
            filled = filled + 1
        end
    end

    if found.r then
        local rollup = UnpackRollup(found.r)
        if rollup then
            ns.db.sellThrough = ns.db.sellThrough or {}
            ns.db.sellThrough[realmKey] = ns.db.sellThrough[realmKey] or {}
            filled = filled + ns.Config.FillGaps(ns.db.sellThrough[realmKey], rollup)
            self.restoredItems = 0
            for _ in pairs(rollup) do self.restoredItems = self.restoredItems + 1 end
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
        Durable:SaveIfChanged(true)
    end)
end

--------------------------------------------------------------------------------
-- Reporting
--------------------------------------------------------------------------------

local function Line(label, value)
    ns.PrintRaw(("  |c%s%-18s|r %s"):format(ns.COLORS.muted, label, value))
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

    if stored then
        local found = self:Parse(stored)
        local sections = {}

        for _, tag in ipairs({ "k", "s", "q", "r" }) do
            local name = ({ k = "realm", s = "settings", q = "queue", r = "sell-through" })[tag]
            if found and found[tag] then
                sections[#sections + 1] = tag == "r"
                    and ("%s (%d item(s))"):format(name, math.floor(#found[tag] / RECORD))
                    or name
            end
        end

        Line("stored", ("%s characters across %d macro(s)")
            :format(ns.Util.Comma(#stored), ns.MacroStore.SlotsFor(#stored) - 1))
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
