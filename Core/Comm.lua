-- Blackthornes Tradeskills -- Core/Comm.lua
-- Addon messages: talking to the same addon on another player's client.
--
-- Asked 2026-10-07 (on Discord, the owner agreeing): share a player's
-- characters between their own accounts, and auction prices within a guild,
-- without a desktop app. Logic/AccountLink.lua and Logic/GuildPrices.lua are
-- the two features; this file is only the wire they share.
--
-- What the client allows, as on retail (not yet measured on Forever; /bts
-- share test reports it):
--   * A message is at most 255 bytes, under a registered prefix of up to 16.
--   * Each prefix is throttled: a short burst, then about one a second. A
--     throttled send is refused, not queued, so this file queues and paces.
--   * WHISPER reaches one character on the same realm; GUILD the guild.
--
-- Everything that arrives is data from another client, and nothing here or
-- in the features ever runs it: tables come through Core/Serialize.lua,
-- which can only produce data, and every value is checked before use.

local _, ns = ...

local Comm = ns.NewModule("Comm")

Comm.PREFIX = "BTSshare"

-- 255 is the client's limit for the whole message.
Comm.MAX_MESSAGE = 255

-- A chunk header is "D" + kind + id,index,total + ":", at most 14 bytes.
local CHUNK_DATA = 236

-- What one sender may have arriving at once, and for how long a part-sent
-- table is waited on. A transfer bigger than this is dropped, not stored.
Comm.MAX_CHUNKS = 1500
Comm.MAX_PARTIAL = 8
local PARTIAL_TIMEOUT = 180

-- Pacing: a burst of this many, then one every this many seconds.
local BURST = 6
local REFILL_SECONDS = 1.2

-- Send results the client calls a throttle: tried again later.
local THROTTLE_CODES = { [3] = true, [8] = true }

--------------------------------------------------------------------------------
-- Small helpers
--------------------------------------------------------------------------------

local DIGITS = "0123456789abcdefghijklmnopqrstuvwxyz"

--- A whole, non-negative number in base 36: "1a2b". Shorter than decimal on
--- the wire, which is what decides how many prices fit in a message.
function Comm.ToBase36(number)
    number = math.floor(tonumber(number) or 0)
    if number <= 0 then return "0" end
    local out = {}
    while number > 0 do
        local digit = number % 36
        out[#out + 1] = DIGITS:sub(digit + 1, digit + 1)
        number = (number - digit) / 36
    end
    return string.reverse(table.concat(out))
end

function Comm.FromBase36(text)
    if type(text) ~= "string" or text == "" or #text > 12 or text:find("[^0-9a-z]") then return nil end
    return tonumber(text, 36)
end

--- A 32-bit hash of a string, the same on every client. For telling
--- whether a character changed since it was last sent, never for security.
function Comm.Hash(text)
    local hash = 5381
    for i = 1, #text do
        hash = (hash * 33 + text:byte(i)) % 4294967296
    end
    return Comm.ToBase36(hash)
end

-- Bytes a message must not carry: the client refuses a NUL, and a pipe or a
-- line break has a meaning in chat text. \001 is the escape itself.
local ESCAPES = { ["\001"] = "\001\001", ["\000"] = "\001\002", ["|"] = "\001\003",
                  ["\n"] = "\001\004", ["\r"] = "\001\005" }
local UNESCAPES = { ["\001"] = "\001", ["\002"] = "\000", ["\003"] = "|",
                    ["\004"] = "\n", ["\005"] = "\r" }

function Comm.Escape(text)
    return (text:gsub("[%z\001|\n\r]", ESCAPES))
end

function Comm.Unescape(text)
    return (text:gsub("\001(.)", UNESCAPES))
end

--- A plain copy of a string the client handed over, or nil. Inside a
--- dungeon the client can hand addons names that raise when compared, so
--- the test and the copy happen inside the pcall.
local function CopyPlain(value)
    if type(value) ~= "string" or value == "" then return nil end
    return value .. ""
end

function Comm.Plain(value)
    -- A named function, not a new one per call: every addon's messages
    -- come through here, hundreds a second in a raid.
    local ok, copy = pcall(CopyPlain, value)
    return ok and copy or nil
end

--- "Ana-Realm" -> "ana": how two names are compared. Realms are dropped,
--- since a whisper only ever reaches the same realm.
function Comm.NameKey(name)
    if type(name) ~= "string" then return nil end
    local short = name:match("^([^%-]+)") or name
    short = short:gsub("^%s+", ""):gsub("%s+$", "")
    if short == "" then return nil end
    return short:lower()
end

local function FirstName()
    local ok, name = pcall(function() return UnitName("player") .. "" end)
    return ok and name or nil
end

local surname, surnameAsked
--- This character's last name, when the game will say it (Config:ReadSurname).
local function Surname()
    if surnameAsked then return surname end
    local config = ns.Config
    if config and config.ReadSurname then
        local ok, found = pcall(config.ReadSurname, config)
        -- A read that raised (a name the game would not let the addon see
        -- just then) is asked again next time, not remembered as "none".
        if not ok then return nil end
        surnameAsked = true
        if type(found) == "string" and found ~= "" then surname = found end
    end
    return surname
end

--- The name whispers reach this character by. Forever lets characters share
--- a first name, so a whisper needs the first and last name together, and
--- an addon message's sender reads that way too: "Ana Smith", no realm
--- (seen 2026-10-07: a whisper to the first name alone found nobody).
local function PlayerName()
    local first = FirstName()
    local last = first and Surname()
    if last then return first .. " " .. last end
    return first
end
Comm.PlayerName = PlayerName

--- Did this character send it? By the whole name when the last name is
--- known; by the first word when the game would not say the last name.
function Comm.IsMe(sender)
    local key = Comm.NameKey(sender)
    if not key then return false end
    if key == Comm.NameKey(PlayerName()) then return true end
    if Surname() then return false end
    return key:match("^(%S+)") == Comm.NameKey(FirstName())
end

--------------------------------------------------------------------------------
-- Sending
--------------------------------------------------------------------------------

Comm.queue = {}
Comm.sent, Comm.refused, Comm.retried = 0, 0, 0
local tokens, lastRefill = BURST, nil
-- Started from the clock, not 0: after a /reload the first transfer reused
-- the last session's ID, and a partner still holding half of that one merged
-- the old parts with the new.
local nextTransfer = math.floor((type(time) == "function" and time() or 0) % 1296)

local function Now()
    local ok, now = pcall(GetTime)
    return ok and now or 0
end

--- Hand one message to the client. "sent", "throttled", or "failed" and why.
function Comm.RawSend(text, channel, target)
    local ok, result
    if type(C_ChatInfo) == "table" and type(C_ChatInfo.SendAddonMessage) == "function" then
        ok, result = pcall(C_ChatInfo.SendAddonMessage, Comm.PREFIX, text, channel, target)
    elseif type(SendAddonMessage) == "function" then
        ok, result = pcall(SendAddonMessage, Comm.PREFIX, text, channel, target)
    else
        return "failed", "no SendAddonMessage"
    end

    if not ok then return "failed", tostring(result) end
    -- Older clients return nothing; newer ones true/false or a result code.
    if result == nil or result == true or result == 0 then return "sent" end
    if type(result) == "number" and THROTTLE_CODES[result] then return "throttled", result end
    if result == false then return "throttled", false end
    return "failed", result
end

local function InCombat()
    local ok, inCombat = pcall(InCombatLockdown)
    return ok and inCombat == true
end

--- Send what the pacing allows. Waits out combat: nothing here is urgent,
--- and a fight is no time to spend the frame on it.
function Comm:Pump()
    if #self.queue == 0 then
        if self.ticker then self.ticker:Cancel() self.ticker = nil end
        return
    end
    if InCombat() then return end

    local now = Now()
    if lastRefill then
        tokens = math.min(BURST, tokens + (now - lastRefill) / REFILL_SECONDS)
    end
    lastRefill = now

    while tokens >= 1 and #self.queue > 0 do
        local message = self.queue[1]
        local outcome, why = Comm.RawSend(message.text, message.channel, message.target)

        if outcome == "throttled" then
            -- Left at the front; the bucket starts again from empty.
            tokens = 0
            message.tries = (message.tries or 0) + 1
            self.retried = self.retried + 1
            if message.tries > 10 then
                table.remove(self.queue, 1)
                self.refused = self.refused + 1
            end
            return
        end

        table.remove(self.queue, 1)
        tokens = tokens - 1
        if outcome == "sent" then
            self.sent = self.sent + 1
            if message.channel == "WHISPER" and message.target then
                self:NoteWhisper(message.target)
            end
        else
            self.refused = self.refused + 1
            self.lastRefusal = why
        end
    end
end

local function StartPump()
    if Comm.ticker or type(C_Timer) ~= "table" then return end
    Comm.ticker = C_Timer.NewTicker(0.25, function() Comm:Pump() end)
end

--- Queue one message: a kind letter and its text, escaped already.
function Comm:Send(kind, text, channel, target)
    local message = kind .. (text or "")
    if #message > Comm.MAX_MESSAGE then return false end
    self.queue[#self.queue + 1] = { text = message, channel = channel, target = target }
    self:Pump()
    StartPump()
    return true
end

--- Queue a whole table, cut into as many messages as it takes.
-- @return how many messages it took
function Comm:SendTable(kind, value, channel, target)
    local ok, encoded = pcall(ns.Serialize.Encode, value)
    if not ok or type(encoded) ~= "string" then return 0 end

    local text = Comm.Escape(encoded)
    local total = math.max(1, math.ceil(#text / CHUNK_DATA))
    if total > Comm.MAX_CHUNKS then return 0 end

    nextTransfer = (nextTransfer + 1) % 1296
    local id = Comm.ToBase36(nextTransfer)
    local count = Comm.ToBase36(total)

    for index = 1, total do
        local part = text:sub((index - 1) * CHUNK_DATA + 1, index * CHUNK_DATA)
        self:Send("D", kind .. id .. "," .. Comm.ToBase36(index) .. "," .. count .. ":" .. part,
            channel, target)
    end
    return total
end

--- Is anything still waiting to go out?
function Comm:Pending()
    return #self.queue
end

--------------------------------------------------------------------------------
-- Receiving
--------------------------------------------------------------------------------

Comm.handlers = {}
Comm.tableHandlers = {}
Comm.received = 0
local partial = {}

--- fn(sender, text, channel) for a one-message kind.
function Comm:On(kind, fn) self.handlers[kind] = fn end

--- fn(sender, value, channel) for a kind sent with SendTable.
function Comm:OnTable(kind, fn) self.tableHandlers[kind] = fn end

local function Dispatch(fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then ns.Debug("share: a message could not be read:", tostring(err)) end
end

--- Drops the transfers that went quiet; answers how many of `sender`'s
--- are still in flight, so one sender's stuck transfers cap only theirs.
local function DropExpired(now, sender)
    local count = 0
    local prefix = sender .. "\001"
    for key, entry in pairs(partial) do
        if now - entry.at > PARTIAL_TIMEOUT then
            partial[key] = nil
        elseif key:sub(1, #prefix) == prefix then
            count = count + 1
        end
    end
    return count
end

local function ReceiveChunk(sender, body, channel)
    local kind, id, index, total, data = body:match("^(%a)(%w+),(%w+),(%w+):(.*)$")
    index, total = Comm.FromBase36(index), Comm.FromBase36(total)
    if not kind or not index or not total or total < 1 or total > Comm.MAX_CHUNKS
        or index < 1 or index > total then return end
    if not Comm.tableHandlers[kind] then return end

    local now = Now()
    local key = sender .. "\001" .. channel .. "\001" .. kind .. id
    local entry = partial[key]
    if not entry then
        if DropExpired(now, sender) >= Comm.MAX_PARTIAL then return end
        entry = { parts = {}, have = 0, total = total, at = now }
        partial[key] = entry
    end
    if entry.total ~= total then partial[key] = nil return end

    entry.at = now
    if not entry.parts[index] then
        entry.parts[index] = data
        entry.have = entry.have + 1
    end
    if entry.have < total then return end

    partial[key] = nil
    local text = Comm.Unescape(table.concat(entry.parts, "", 1, total))
    local ok, value = ns.Serialize.Decode(text)
    if ok and type(value) == "table" then
        Dispatch(Comm.tableHandlers[kind], sender, value, channel)
    end
end

--- One addon message arrived. Everything about it is read as plain data.
function Comm:CHAT_MSG_ADDON(_, prefix, text, channel, sender)
    -- The prefix first: most messages are other addons', and theirs are
    -- dropped before anything else of them is copied.
    prefix = Comm.Plain(prefix)
    if prefix ~= Comm.PREFIX then return end
    text, channel, sender = Comm.Plain(text), Comm.Plain(channel), Comm.Plain(sender)
    if not text or not channel or not sender then return end
    if #text > Comm.MAX_MESSAGE then return end

    self.received = self.received + 1
    if self.testing then self:NoteTestEcho(text, sender) end

    local kind, body = text:sub(1, 1), text:sub(2)
    if kind == "D" then
        ReceiveChunk(sender, body, channel)
    elseif self.handlers[kind] then
        Dispatch(self.handlers[kind], sender, body, channel)
    end
end

--------------------------------------------------------------------------------
-- Whispers to someone not playing
--------------------------------------------------------------------------------

-- Whispering a character who is not logged in puts "No player named X is
-- currently playing" in chat. Saying hello to a partner who is offline is
-- normal here, so that line is kept out of chat for names just whispered,
-- and tells the features the partner is away.
local whispered = {}

function Comm:NoteWhisper(name)
    local key = Comm.NameKey(name)
    if key then whispered[key] = Now() end
end

local notFoundPattern
local function NotFoundName(message)
    if not notFoundPattern then
        local format = type(ERR_CHAT_PLAYER_NOT_FOUND_S) == "string" and ERR_CHAT_PLAYER_NOT_FOUND_S
            or "No player named '%s' is currently playing."
        notFoundPattern = "^" .. format:gsub("([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1"):gsub("%%s", "(.+)") .. "$"
    end
    return message:match(notFoundPattern)
end

function Comm.FilterNotFound(_, _, message)
    -- Nobody whispered lately: no line to hide, and nothing to read.
    if next(whispered) == nil then return false end
    local plain = Comm.Plain(message)
    if not plain then return false end
    local name = NotFoundName(plain)
    local key = name and Comm.NameKey(name)
    local at = key and whispered[key]
    if not at or Now() - at > 10 then return false end

    if Comm.onOffline then pcall(Comm.onOffline, key) end
    return true
end

--------------------------------------------------------------------------------
-- The test (/bts share test)
--------------------------------------------------------------------------------

--- Whisper this character a few messages and report what the client did:
--- whether the prefix registered, what each send returned, whether they
--- came back, how the sender's name reads, and where pacing starts.
function Comm:Test()
    local me = PlayerName()
    if not me then ns.Print("share test: the game would not say this character's name") return end

    local registered = self.registered
    ns.Print(("share test: prefix %s registered: %s, whispering \"%s\""):format(
        Comm.PREFIX, tostring(registered), me))
    -- Keeps "No player named" out of chat if the name is still wrong.
    self:NoteWhisper(me)

    self.testing = { at = Now(), echoes = 0, sender = nil }

    local full = ("T"):rep(Comm.MAX_MESSAGE)
    local outcome, why = Comm.RawSend(full, "WHISPER", me)
    ns.PrintRaw(("  a 255-byte whisper to yourself: %s %s"):format(outcome, tostring(why or "")))
    local tooLong, whyLong = Comm.RawSend(full .. "T", "WHISPER", me)
    ns.PrintRaw(("  a 256-byte one (should be refused): %s %s"):format(tooLong, tostring(whyLong or "")))

    local results = {}
    for i = 1, 12 do
        local burst = Comm.RawSend("t" .. i, "WHISPER", me)
        results[#results + 1] = burst
    end
    ns.PrintRaw("  12 in a row: " .. table.concat(results, ", "))

    local inGuild = false
    pcall(function() inGuild = IsInGuild() == true end)
    if inGuild then
        local guildOutcome = Comm.RawSend("tguild", "GUILD")
        ns.PrintRaw("  one to your guild: " .. guildOutcome)
    else
        ns.PrintRaw("  not in a guild, so guild messages were not tried")
    end

    C_Timer.After(3, function()
        local test = Comm.testing
        Comm.testing = nil
        if not test then return end
        ns.PrintRaw(("  came back: %d message(s), sender read as \"%s\""):format(
            test.echoes, tostring(test.sender or "nothing arrived")))
        ns.PrintRaw("  Paste these lines in the thread so the sharing can be checked against them.")
    end)
end

function Comm:NoteTestEcho(text, sender)
    local first = text:sub(1, 1)
    if first ~= "T" and first ~= "t" then return end
    self.testing.echoes = self.testing.echoes + 1
    self.testing.sender = sender
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

function Comm:Register()
    if self.registered ~= nil then return self.registered end

    local ok, result
    if type(C_ChatInfo) == "table" and type(C_ChatInfo.RegisterAddonMessagePrefix) == "function" then
        ok, result = pcall(C_ChatInfo.RegisterAddonMessagePrefix, Comm.PREFIX)
    elseif type(RegisterAddonMessagePrefix) == "function" then
        ok, result = pcall(RegisterAddonMessagePrefix, Comm.PREFIX)
    end
    -- true, nil (older clients) or result code 0 all mean it took.
    self.registered = ok == true and (result == nil or result == true or result == 0)
    return self.registered
end

function Comm:OnEnable()
    self:Register()
    ns.RegisterEvent(self, "CHAT_MSG_ADDON", self.CHAT_MSG_ADDON)
    if type(ChatFrame_AddMessageEventFilter) == "function" then
        pcall(ChatFrame_AddMessageEventFilter, "CHAT_MSG_SYSTEM", Comm.FilterNotFound)
    end
end
