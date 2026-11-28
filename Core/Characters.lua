-- Blackthornes Tradeskills -- Core/Characters.lua
-- The one way to tell which saved record is which character.
--
-- Characters are keyed by GUID (Config:GetCharacterKey). Records from before
-- that were keyed "Name-Realm", by first name only, and one of them could be
-- left beside the GUID record of the same character. Read as two characters,
-- that sent errands to the character playing: Butler filled a mail to the
-- character the player was on, and told one to mail Medium Leather to itself
-- (2026-10-11). Config:AdoptLegacyCharacter folds such a record away at
-- login; everything that asks "is this the same character?" or "is this the
-- character playing?" asks here, so no list, mail, step or pick can tell the
-- two apart again. Equipment and Butler name characters by the same GUID.

local _, ns = ...

local Characters = ns.NewModule("Characters")

local GUID_KEY = "^Player%-"

local function Fold(text)
    if type(text) ~= "string" then return nil end
    text = text:gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s+", " ")
    if text == "" then return nil end
    return text:lower()
end

--- true or false when both are strings, nil when either is missing.
local function SameText(a, b)
    if type(a) ~= "string" or type(b) ~= "string" then return nil end
    return a:gsub("%s", ""):lower() == b:gsub("%s", ""):lower()
end
Characters.SameText = SameText

--- One record's name matches the other's: the same first name, or one
--- saved with the whole name ("Ana Blackthorne") and the other's first and
--- last name together.
local function SameName(one, two)
    local a, b = Fold(one.name), Fold(two.name)
    if not a or not b then return false end
    if a == b then return true end
    local sa, sb = Fold(one.surname), Fold(two.surname)
    return (sb ~= nil and a == b .. " " .. sb) or (sa ~= nil and b == a .. " " .. sa)
end

local function Records()
    local characters = ns.db and ns.db.characters
    return type(characters) == "table" and characters or nil
end

local function SelfKey()
    local config = ns.Config
    if not (config and config.GetCharacterKey) then return nil end
    local ok, key = pcall(config.GetCharacterKey, config)
    return ok and key or nil
end

--- The key a character goes by now: the GUID a retired record was folded
--- into (`formerCharacters[key].retiredInto`), else the key as given.
function Characters:Canonical(key)
    if key == nil then return nil end
    local records = Records()
    if records and records[key] ~= nil then return key end
    local former = ns.db and ns.db.formerCharacters
    local old = type(former) == "table" and former[key]
    if type(old) == "table" and type(old.retiredInto) == "string" then return old.retiredInto end
    return key
end

--- Are two saved keys the same character? The same key, a record stamped
--- with the other's GUID, or a key retired into the other. Two GUID keys
--- that differ are two characters, whatever their names. An old name-realm
--- record (no GUID) beside one of the same first name, realm, side and class,
--- with no last name that differs, is taken to be it: that key filed every
--- character of the first name as one, so it is never somebody to mail or
--- log out for.
function Characters:Same(a, b)
    if a == nil or b == nil then return false end
    a, b = self:Canonical(a), self:Canonical(b)
    if a == b then return true end
    local records = Records()
    if not records then return false end
    local one, two = records[a], records[b]
    if type(one) ~= "table" or type(two) ~= "table" then return false end
    if one.guid == b or two.guid == a then return true end
    if tostring(a):find(GUID_KEY) and tostring(b):find(GUID_KEY) then return false end
    if one.guid ~= nil and two.guid ~= nil and one.guid ~= two.guid then return false end
    if (one.linkedFrom ~= nil) ~= (two.linkedFrom ~= nil) then return false end
    if not SameName(one, two) then return false end
    for _, field in ipairs({ "realm", "faction", "class" }) do
        if SameText(one[field], two[field]) == false then return false end
    end
    local s1, s2 = Fold(one.surname), Fold(two.surname)
    if s1 and s2 then return s1 == s2 end
    return true
end

--- Is this saved key the character playing, under any of its records?
function Characters:IsPlaying(key)
    if key == nil then return false end
    local selfKey = SelfKey()
    if selfKey == nil then return false end
    return key == selfKey or self:Same(key, selfKey)
end

--- One key for a realm name, the same on every account of one player.
--- Forever's GetRealmName names the server behind the realm ("CAMWOW US2
--- Realm 7 PvE"), so the key drops spaces, case and the "Realm N" part.
--- The same few lines are in Queue, QueueMail, Butler, GoldGoal and GoldLog.
local function RealmKey(name)
    if type(name) ~= "string" or name == "" or name == "?" then return nil end
    local key = name:lower():gsub("%s", ""):gsub("realm%d+", "")
    if key == "" then return nil end
    return key
end

--- Can one character mail the other? The same realm, and the same side,
--- where both are known. Items never cross from Alliance to Horde, so an
--- Alliance alt's cloth is no help to a Horde crafter (a player's report,
--- 2026-11-27). A field one record lacks is taken as the same, so an old
--- record from before realm and side were saved still counts.
function Characters:CanMail(fromKey, toKey)
    if fromKey == nil or toKey == nil then return false end
    if fromKey == toKey then return true end
    local records = Records()
    local from, to = records and records[fromKey], records and records[toKey]
    if type(from) ~= "table" or type(to) ~= "table" then return false end
    local fromRealm, toRealm = RealmKey(from.realm), RealmKey(to.realm)
    if fromRealm and toRealm and fromRealm ~= toRealm then return false end
    if SameText(from.faction, to.faction) == false then return false end
    return true
end

--- Can the character playing get items from this one? Its own records
--- always; anyone else when Characters:CanMail says so. With no key for
--- the one playing (a dungeon), true, as before: this only ever hides.
function Characters:InReach(key)
    if key == nil then return false end
    local selfKey = SelfKey()
    if selfKey == nil then return true end
    if self:IsPlaying(key) then return true end
    local records = Records()
    if not (records and type(records[selfKey]) == "table") then return true end
    return self:CanMail(selfKey, key)
end
