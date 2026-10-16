-- Blackthornes Tradeskills -- Logic/CharacterNotes.lua
-- What the Characters tab shows about each character beyond its recipes and
-- bags: race, XP into the level, rested XP, the zone it is in and how long it
-- has been played.
--
-- Written on the character's own record in `characters[guid]` while it is
-- played, as new fields (never rename them): `race`, `classFile`, `xp`,
-- `xpMax`, `restXP`, `resting`, `zone`, `played` and `seenAt`. Nothing is
-- written while the game will not give the character's GUID (a /reload
-- inside a dungeon), so a note never lands on another key.
--
-- Played time: the game says it only when asked (RequestTimePlayed), and
-- asking prints it in chat. So it is asked once, for a character that has
-- never had it read, and from then on the time is counted here: what it was
-- at login plus how long this session has run. Whenever the game says it
-- anyway (the player types /played, or another addon asks), that is taken.

local _, ns = ...

local CharacterNotes = ns.NewModule("CharacterNotes")

-- Classic's rested rule: 5% of a level every 8 hours in an inn or a city,
-- a quarter of that anywhere else, up to a level and a half.
CharacterNotes.REST_SECONDS = 8 * 60 * 60
CharacterNotes.REST_IN_INN = 5
CharacterNotes.REST_OUTSIDE = 1.25
CharacterNotes.REST_MOST = 150

-- A burst of XP and rest events is one note.
CharacterNotes.SETTLE = 1
-- How long after logging in before played time is asked, so another addon
-- that asks at login answers first.
CharacterNotes.ASK_DELAY = 8

local session = { loginAt = nil, playedAtLogin = nil, heard = false, queued = false }
CharacterNotes._session = session

local function Now()
    local ok, value = pcall(GetTime)
    return ok and type(value) == "number" and value or 0
end

--- A plain copy of a string the client gives, or nil. Inside a dungeon a
--- name can come back as a value that raises when kept or compared.
local function Plain(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, value = pcall(function(...)
        local v = fn(...)
        if type(v) == "string" and v ~= "" then return v .. "" end
    end, ...)
    return ok and value or nil
end

local function Number(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, value = pcall(function(...)
        local v = fn(...)
        if type(v) == "number" then return v + 0 end
    end, ...)
    return ok and value or nil
end

--- The character's own record, only once its GUID is known.
local function Record()
    if not (ns.Config and ns.Config.characterKey and ns.Recipes) then return nil end
    local ok, record = pcall(ns.Recipes.GetCharacterRecord, ns.Recipes, true)
    if ok and type(record) == "table" then return record end
    return nil
end

--- The highest level a character can reach: the game's, else 60.
function CharacterNotes.MaxLevel()
    for _, name in ipairs({ "GetMaxLevelForPlayerExpansion", "GetMaxPlayerLevel" }) do
        local level = Number(rawget(_G, name))
        if level and level > 0 then return level end
    end
    local level = rawget(_G, "MAX_PLAYER_LEVEL")
    if type(level) == "number" and level > 0 then return level end
    return 60
end

--- Played time now, in seconds, for the character playing.
function CharacterNotes:SessionPlayed()
    if not (session.playedAtLogin and session.loginAt) then return nil end
    return math.floor(session.playedAtLogin + math.max(0, Now() - session.loginAt))
end

--- Note what the game says about the character now.
function CharacterNotes:Note()
    local record = Record()
    if not record then return end

    local race = Plain(UnitRace, "player")
    if race then record.race = race end

    local okClass, _, classFile = pcall(UnitClass, "player")
    if okClass and type(classFile) == "string" and classFile ~= "" then record.classFile = classFile .. "" end

    local level = Number(UnitLevel, "player")
    if level then record.level = level end

    local xp, xpMax = Number(UnitXP, "player"), Number(UnitXPMax, "player")
    if xp and xpMax and xpMax > 0 then
        record.xp, record.xpMax = xp, xpMax
        -- None rested comes back as nil, which is 0 here.
        record.restXP = Number(GetXPExhaustion) or 0
    end

    if type(IsResting) == "function" then
        local ok, resting = pcall(IsResting)
        if ok then record.resting = resting and true or false end
    end

    local zone = Plain(rawget(_G, "GetRealZoneText")) or Plain(rawget(_G, "GetZoneText"))
    if zone then record.zone = zone end

    local played = self:SessionPlayed()
    if played then record.played = played end

    record.seenAt = time()
end

function CharacterNotes:NoteSoon()
    if session.queued then return end
    session.queued = true
    C_Timer.After(self.SETTLE, function()
        session.queued = false
        self:Note()
    end)
end

--- The game said how long the character has been played.
function CharacterNotes:Heard(total)
    total = tonumber(total)
    if not total or total < 0 then return end
    session.heard = true
    session.loginAt = session.loginAt or Now()
    session.playedAtLogin = total - math.max(0, Now() - session.loginAt)
    self:Note()
end

--- Login, reload or a loading screen.
function CharacterNotes:EnteredWorld()
    session.loginAt = session.loginAt or Now()
    local record = Record()

    -- Counted on from what was kept at the last logout. The GUID can come
    -- in after the first loading screen, so this is looked at again.
    if record and not session.playedAtLogin and type(record.played) == "number" then
        session.playedAtLogin = record.played
    end
    self:Note()

    -- Asked only for a character never read, and only once a session.
    if not record or session.playedAtLogin or session.asked then return end
    session.asked = true
    C_Timer.After(self.ASK_DELAY, function()
        if session.heard or session.playedAtLogin then return end
        if type(RequestTimePlayed) == "function" then pcall(RequestTimePlayed) end
    end)
end

--------------------------------------------------------------------------------
-- Reading the notes, for the Characters tab
--------------------------------------------------------------------------------

--- Rested XP as a share of a level (0 to 150), or nil when not known or at
--- the level cap. For a character not playing it grows from when it was
--- last seen, by Classic's rule, so it says what is waiting now.
-- @return percent, estimated (true when grown since it was last seen)
function CharacterNotes.Rested(record, isCurrent, now)
    if type(record) ~= "table" then return nil end
    if type(record.level) == "number" and record.level >= CharacterNotes.MaxLevel() then return nil end
    local xpMax, rest = tonumber(record.xpMax), tonumber(record.restXP)
    if not xpMax or xpMax <= 0 or not rest then return nil end

    local percent = rest / xpMax * 100
    local estimated = false
    local seenAt = tonumber(record.seenAt)
    if not isCurrent and seenAt then
        local elapsed = math.max(0, (now or time()) - seenAt)
        local rate = record.resting and CharacterNotes.REST_IN_INN or CharacterNotes.REST_OUTSIDE
        local gained = elapsed / CharacterNotes.REST_SECONDS * rate
        if gained > 0 and percent < CharacterNotes.REST_MOST then estimated = true end
        percent = percent + gained
    end

    return math.min(CharacterNotes.REST_MOST, math.floor(percent + 0.5)), estimated
end

--- XP into the level as a share (0 to 1), or nil.
function CharacterNotes.LevelShare(record)
    if type(record) ~= "table" then return nil end
    if type(record.level) == "number" and record.level >= CharacterNotes.MaxLevel() then return nil end
    local xp, xpMax = tonumber(record.xp), tonumber(record.xpMax)
    if not xp or not xpMax or xpMax <= 0 then return nil end
    return math.max(0, math.min(1, xp / xpMax))
end

--- Seconds played, live for the character playing.
function CharacterNotes.Played(record, isCurrent)
    if isCurrent then
        local live = CharacterNotes:SessionPlayed()
        if live then return live end
    end
    return type(record) == "table" and tonumber(record.played) or nil
end

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------

ns.RegisterEvent(CharacterNotes, "PLAYER_ENTERING_WORLD", function() CharacterNotes:EnteredWorld() end)
ns.RegisterEvent(CharacterNotes, "TIME_PLAYED_MSG", function(_, _, total) CharacterNotes:Heard(total) end)
ns.RegisterEvent(CharacterNotes, "PLAYER_LOGOUT", function() CharacterNotes:Note() end)
for _, event in ipairs({ "PLAYER_XP_UPDATE", "UPDATE_EXHAUSTION", "PLAYER_UPDATE_RESTING",
                         "PLAYER_LEVEL_UP", "ZONE_CHANGED_NEW_AREA" }) do
    ns.RegisterEvent(CharacterNotes, event, function() CharacterNotes:NoteSoon() end)
end
