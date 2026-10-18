-- Blackthornes Tradeskills -- Logic/Cooldowns.lua
-- Profession cooldowns on every character, and a word when one is ready.
--
-- Some crafts can only be made once every so often: an alchemist's
-- transmutes, a tailor's Mooncloth, the leatherworker's Salt Shaker. The
-- owner asked (2026-10-12) for these to be kept for every character, with a
-- line in chat when one comes ready and a step in Blackthornes Butler
-- ("Transmute is ready" on that character's line).
--
-- Which crafts have a cooldown:
--   * Classic's own (KNOWN below), once the character's recipes, read from
--     its profession window, include them.
--   * Any learned craft the game says is cooling down: read from the
--     profession window (C_TradeSkillUI.GetRecipeCooldown) or just after the
--     character casts it. So a cooldown Forever added is picked up the
--     first time it is used, without being listed here.
--   * The Salt Shaker, an item with its own cooldown, while it is carried
--     or banked.
--
-- What is kept, account wide, in professionCooldowns[characterKey][id] =
-- { name, group, readyAt, recipeID or itemID, told } (never rename it):
-- `id` is "spell:N" or "item:N", `readyAt` is time() when it is (or was)
-- ready, `told` the readyAt last said in chat. Crafts that share one
-- cooldown (every transmute) are shown once, as their `group`: the name
-- before the colon ("Transmute: Arcanite" is "Transmute").
--
-- One key per character: the character playing writes only under its GUID,
-- and nothing at all when the client will not say who is playing.
--
-- Smooth play: a read is a handful of calls, made a moment after the login,
-- after a cast by the character, after an item cooldown event (debounced,
-- out of combat), and from the profession window's own harvest. One timer
-- waits for the next cooldown to come ready; nothing ticks.

local _, ns = ...
local L = ns.L or setmetatable({ Format = string.format }, { __index = function(_, key) return key end })

local Cooldowns = ns.NewModule("Cooldowns")

-- Classic's crafts with a cooldown, by spell (= recipe) ID.
Cooldowns.KNOWN = {
    [11479] = true, -- Transmute: Iron to Gold
    [11480] = true, -- Transmute: Mithril to Truesilver
    [17187] = true, -- Transmute: Arcanite
    [17559] = true, -- Transmute: Air to Fire
    [17560] = true, -- Transmute: Fire to Earth
    [17561] = true, -- Transmute: Earth to Water
    [17562] = true, -- Transmute: Water to Air
    [17563] = true, -- Transmute: Undeath to Water
    [17564] = true, -- Transmute: Water to Undeath
    [17565] = true, -- Transmute: Life to Earth
    [17566] = true, -- Transmute: Earth to Life
    [25146] = true, -- Transmute: Elemental Fire
    [18560] = true, -- Mooncloth
}

-- Items with a cooldown of their own (the Salt Shaker makes Refined Deeprock
-- Salt), with the English name the data uses when the client has none yet.
Cooldowns.ITEMS = {
    [15846] = "Salt Shaker",
}

-- Shorter than this is the global cooldown or a cast, not a craft's.
Cooldowns.MIN_SECONDS = 60
-- After login, how long before the first read and word in chat: the other
-- addons' login lines (the sister note waits 8 s) come first.
Cooldowns.LOGIN_DELAY = 10
-- How long after a cast or item event before reading.
Cooldowns.READ_DELAY = 1

-- Moves whenever what is kept changes, for lists that show it.
Cooldowns.version = 0

local function Now() return time() end

local function IsOn()
    return ns.Config:Get("cooldownAlerts") ~= false
end
Cooldowns.IsOn = IsOn

local function InCombat()
    return type(InCombatLockdown) == "function" and InCombatLockdown() and true or false
end

--- The table of every character's cooldowns.
local function Store()
    if not ns.db then return nil end
    if type(ns.db.professionCooldowns) ~= "table" then ns.db.professionCooldowns = {} end
    return ns.db.professionCooldowns
end

--- The character playing's key, only when it is a GUID.
local function SelfKey()
    local config = ns.Config
    if not (config and config.GetCharacterKey) then return nil end
    local ok, key = pcall(config.GetCharacterKey, config)
    if ok and type(key) == "string" and key:find("^Player%-") then return key end
    return nil
end

--- The craft's group: what comes before a colon, else its whole name.
function Cooldowns.Group(name)
    if type(name) ~= "string" or name == "" then return nil end
    local before = name:match("^(.-)%s*[:：]")
    if before and before ~= "" then return before end
    return name
end

--------------------------------------------------------------------------------
-- Reading the client
--------------------------------------------------------------------------------

--- Seconds left, from a start and duration, or 0 when it is not cooling
--- down; nil when the client gave nothing readable (a secret value).
local function Left(start, duration)
    local ok, left = pcall(function()
        if type(start) ~= "number" or type(duration) ~= "number" then return nil end
        if start == 0 or duration < Cooldowns.MIN_SECONDS then return 0 end
        return math.max(0, start + duration - GetTime())
    end)
    if ok then return left end
    return nil
end

function Cooldowns.SpellLeft(spellID)
    local api = rawget(_G, "C_Spell")
    if type(api) == "table" and type(api.GetSpellCooldown) == "function" then
        local ok, info = pcall(api.GetSpellCooldown, spellID)
        if ok and type(info) == "table" then return Left(info.startTime, info.duration) end
    end
    local get = rawget(_G, "GetSpellCooldown")
    if type(get) == "function" then
        local ok, start, duration = pcall(get, spellID)
        if ok then return Left(start, duration) end
    end
    return nil
end

function Cooldowns.RecipeLeft(recipeID)
    local api = rawget(_G, "C_TradeSkillUI")
    if type(api) ~= "table" or type(api.GetRecipeCooldown) ~= "function" then return nil end
    local ok, left = pcall(function()
        local seconds = api.GetRecipeCooldown(recipeID)
        if type(seconds) ~= "number" then return 0 end
        return seconds > 0 and seconds or 0
    end)
    if ok then return left end
    return nil
end

function Cooldowns.ItemLeft(itemID)
    local container = rawget(_G, "C_Container")
    local get = type(container) == "table" and container.GetItemCooldown or rawget(_G, "GetItemCooldown")
    if type(get) ~= "function" then return nil end
    local ok, start, duration = pcall(get, itemID)
    if ok then return Left(start, duration) end
    return nil
end

local function ItemCount(itemID)
    local api = rawget(_G, "C_Item")
    local get = type(api) == "table" and api.GetItemCount or rawget(_G, "GetItemCount")
    if type(get) ~= "function" then return 0 end
    local ok, count = pcall(get, itemID, true)
    return ok and tonumber(count) or 0
end

local function ItemName(itemID)
    local api = rawget(_G, "C_Item")
    local get = type(api) == "table" and api.GetItemNameByID or rawget(_G, "GetItemInfo")
    if type(get) == "function" then
        local ok, name = pcall(get, itemID)
        if ok and type(name) == "string" and name ~= "" then return name end
    end
    return Cooldowns.ITEMS[itemID]
end

--------------------------------------------------------------------------------
-- Keeping
--------------------------------------------------------------------------------

--- Put what was read on the character's entry. `left` nil means unread:
--- nothing changes. A ready one keeps the moment it came ready, so it is
--- said once, not on every read.
local function Note(characterKey, id, fields, left)
    local store = Store()
    if not (store and characterKey) then return end
    local entries = store[characterKey]
    local entry = entries and entries[id]
    if not entry then
        -- Only a craft known to have a cooldown, or one seen cooling down,
        -- is kept.
        if not fields.track and not (left and left > 0) then return end
        entries = entries or {}
        store[characterKey] = entries
        entry = {}
        entries[id] = entry
    end
    entry.name = fields.name or entry.name
    entry.group = Cooldowns.Group(entry.name) or entry.group
    entry.recipeID = fields.recipeID or entry.recipeID
    entry.itemID = fields.itemID or entry.itemID
    if left ~= nil then
        local now = Now()
        local before = entry.readyAt
        if left > 0 then
            entry.readyAt = now + math.floor(left + 0.5)
        elseif not before or before > now then
            entry.readyAt = now
        end
        if entry.readyAt ~= before then Cooldowns.version = Cooldowns.version + 1 end
    end
end

local function RecipeName(record, recipeID)
    local recipe = record and record.recipes and record.recipes[recipeID]
    if recipe and type(recipe.name) == "string" then return recipe.name end
    local api = rawget(_G, "C_Spell")
    if type(api) == "table" and type(api.GetSpellName) == "function" then
        local ok, name = pcall(api.GetSpellName, recipeID)
        if ok and type(name) == "string" then return name end
    end
    return nil
end

--- From the profession window's harvest: one learned recipe and what the
--- window says of its cooldown.
function Cooldowns:NoteRecipe(recipeID, info)
    local key = SelfKey()
    if not key or type(recipeID) ~= "number" then return end
    local left = Cooldowns.RecipeLeft(recipeID)
    local known = Cooldowns.KNOWN[recipeID]
    if not known and not (left and left > 0) then
        local entries = Store() and Store()[key]
        if not (entries and entries["spell:" .. recipeID]) then return end
    end
    local name = type(info) == "table" and type(info.name) == "string" and info.name or nil
    Note(key, "spell:" .. recipeID, { name = name, recipeID = recipeID, track = known }, left)
end

--- Read every cooldown the character playing has.
function Cooldowns:Read()
    local key = SelfKey()
    local store = Store()
    if not (key and store) then return end
    local record = ns.db.characters and ns.db.characters[key]

    local wanted = {}
    for recipeID in pairs(Cooldowns.KNOWN) do
        if record and record.recipes and record.recipes[recipeID] then wanted[recipeID] = true end
    end
    for id, entry in pairs(store[key] or {}) do
        if type(entry) == "table" and entry.recipeID and tostring(id):find("^spell:") then
            wanted[entry.recipeID] = true
        end
    end
    for recipeID in pairs(wanted) do
        Note(key, "spell:" .. recipeID, { name = RecipeName(record, recipeID), recipeID = recipeID,
            track = Cooldowns.KNOWN[recipeID] }, Cooldowns.SpellLeft(recipeID))
    end

    for itemID in pairs(Cooldowns.ITEMS) do
        local id = "item:" .. itemID
        if ItemCount(itemID) > 0 then
            Note(key, id, { name = ItemName(itemID), itemID = itemID, track = true }, Cooldowns.ItemLeft(itemID))
        elseif store[key] and store[key][id] then
            -- Sold or thrown away: nothing left to wait for.
            store[key][id] = nil
            Cooldowns.version = Cooldowns.version + 1
        end
    end
    self:Schedule()
end

--- A cast by the character playing: if it is one of its recipes, read
--- whether it started a cooldown.
function Cooldowns:OnCast(spellID)
    local key = SelfKey()
    if not key or type(spellID) ~= "number" then return end
    local record = ns.db.characters and ns.db.characters[key]
    local entries = Store() and Store()[key]
    local tracked = entries and entries["spell:" .. spellID]
    if not tracked and not (record and record.recipes and record.recipes[spellID]) then return end
    self.casts = self.casts or {}
    self.casts[spellID] = true
    self:ReadSoon()
end

--- Read once, a moment from now, out of combat; many asks are one read.
function Cooldowns:ReadSoon()
    if self.readPending then return end
    self.readPending = true
    C_Timer.After(Cooldowns.READ_DELAY, function()
        Cooldowns.readPending = false
        if InCombat() then
            Cooldowns.readAfterCombat = true
            return
        end
        local key = SelfKey()
        local record = key and ns.db.characters and ns.db.characters[key]
        for spellID in pairs(Cooldowns.casts or {}) do
            Note(key, "spell:" .. spellID, { name = RecipeName(record, spellID), recipeID = spellID },
                Cooldowns.SpellLeft(spellID))
        end
        Cooldowns.casts = nil
        Cooldowns:Read()
    end)
end

--------------------------------------------------------------------------------
-- Answers
--------------------------------------------------------------------------------

--- One character's cooldowns, one per group, soonest ready first:
--- { group, name, readyAt, ready, recipeID, itemID, told }.
function Cooldowns:Groups(characterKey)
    local store = Store()
    local entries = store and store[characterKey]
    local groups, list = {}, {}
    local now = Now()
    for id, entry in pairs(type(entries) == "table" and entries or {}) do
        if type(entry) == "table" and type(entry.readyAt) == "number" then
            local name = entry.group or entry.name or tostring(id)
            local group = groups[name]
            if not group then
                group = { group = name, name = entry.name or name, readyAt = entry.readyAt,
                    recipeID = entry.recipeID, itemID = entry.itemID, told = true, ids = {} }
                groups[name] = group
                list[#list + 1] = group
            end
            -- Crafts that share a cooldown are ready when the last of them is.
            if entry.readyAt > group.readyAt then group.readyAt = entry.readyAt end
            if entry.told ~= entry.readyAt then group.told = false end
            group.ids[#group.ids + 1] = id
        end
    end
    for _, group in ipairs(list) do
        group.ready = group.readyAt <= now
        if #group.ids > 1 then Cooldowns.PickCraft(characterKey, group, entries) end
    end
    table.sort(list, function(a, b)
        if a.readyAt ~= b.readyAt then return a.readyAt < b.readyAt end
        return a.group < b.group
    end)
    return list
end

local function Makeable(characterKey, recipeID)
    if not (recipeID and ns.Profit and ns.Profit.GetCraftableCount) then return 0 end
    local ok, count = pcall(ns.Profit.GetCraftableCount, ns.Profit, recipeID, characterKey)
    return ok and type(count) == "number" and count or 0
end

--- Which craft a group that shares one cooldown names (every transmute is
--- "Transmute"): the one the character has the materials for, most crafts
--- first, else the lowest ID, so the same one is named every time rather
--- than whichever the saved table gave first.
function Cooldowns.PickCraft(characterKey, group, entries)
    local best, bestCount, bestID
    for _, id in ipairs(group.ids) do
        local entry = entries[id]
        local recipeID = entry.recipeID
        local count = Makeable(characterKey, recipeID)
        local sortID = tonumber(recipeID or entry.itemID) or math.huge
        if not best or count > bestCount or (count == bestCount and sortID < bestID) then
            best, bestCount, bestID = entry, count, sortID
        end
    end
    if best then
        group.name = best.name or group.name
        group.recipeID, group.itemID = best.recipeID, best.itemID
    end
end

local function Name(characterKey)
    if ns.Recipes and ns.Recipes.GetCharacterName then
        local ok, name = pcall(ns.Recipes.GetCharacterName, ns.Recipes, characterKey)
        if ok and type(name) == "string" then return name end
    end
    return tostring(characterKey)
end

--- Every character of this account with a cooldown kept, the character
--- playing first, then by name: { key, name, isCurrent, groups }. Another
--- account's characters and old records of one are left out.
function Cooldowns:All()
    local store = Store()
    local selfKey = SelfKey()
    local list, seen = {}, {}
    local characters = ns.db and ns.db.characters or {}
    for characterKey in pairs(store or {}) do
        local key = ns.Characters and ns.Characters:Canonical(characterKey) or characterKey
        local record = characters[key]
        -- A character forgotten on the Characters tab keeps its saved
        -- cooldowns (nothing is deleted) but is no longer named or said.
        if not seen[key] and type(record) == "table" and not record.linkedFrom then
            seen[key] = true
            local groups = self:Groups(key)
            if #groups > 0 then
                list[#list + 1] = { key = key, name = Name(key), isCurrent = key == selfKey, groups = groups }
            end
        end
    end
    table.sort(list, function(a, b)
        if a.isCurrent ~= b.isCurrent then return a.isCurrent end
        if a.name ~= b.name then return a.name < b.name end
        return tostring(a.key) < tostring(b.key)
    end)
    return list
end

--- Every ready cooldown, for Butler's step list: { key, group, name,
--- recipeID, itemID }. Empty while the setting is off.
function Cooldowns:ReadyList()
    local list = {}
    if not IsOn() then return list end
    for _, character in ipairs(self:All()) do
        for _, group in ipairs(character.groups) do
            if group.ready then
                list[#list + 1] = { key = character.key, group = group.group, name = group.name,
                    recipeID = group.recipeID, itemID = group.itemID }
            end
        end
    end
    return list
end

--- Is this craft's cooldown up for the character playing?
function Cooldowns:ReadyHere(recipeID)
    local key = SelfKey()
    if not key then return false end
    local id = "spell:" .. tostring(recipeID)
    for _, group in ipairs(self:Groups(key)) do
        if group.ready then
            -- Any craft of a group that is up: they share the one cooldown.
            for _, member in ipairs(group.ids) do
                if member == id then return true end
            end
        end
    end
    return false
end

--- "2d 4h", "3h 12m", "12m", "under a minute".
function Cooldowns.LeftText(seconds)
    seconds = math.max(0, math.floor(seconds or 0))
    local days, hours = math.floor(seconds / 86400), math.floor(seconds % 86400 / 3600)
    local minutes = math.floor(seconds % 3600 / 60)
    if days > 0 then return L.Format("%dd %dh", days, hours) end
    if hours > 0 then return L.Format("%dh %dm", hours, minutes) end
    if minutes > 0 then return L.Format("%dm", minutes) end
    return L["under a minute"]
end

--------------------------------------------------------------------------------
-- Saying so
--------------------------------------------------------------------------------

--- A group's name as chat shows it. An item's cooldown (the Salt Shaker)
--- names the item in its rarity colour; a craft's is named by its group
--- ("Transmute"), which is no item.
function Cooldowns.Shown(group)
    local Util = ns.Util
    if group.itemID and Util and Util.ColorItemName then
        return Util.ColorItemName(group.itemID, group.group)
    end
    return group.group
end

--- Say in chat, once each time it comes ready, every cooldown that is
--- ready and not yet said.
function Cooldowns:Announce()
    if not IsOn() then return end
    local store = Store()
    local parts = {}
    for _, character in ipairs(self:All()) do
        for _, group in ipairs(character.groups) do
            if group.ready and not group.told then
                parts[#parts + 1] = character.isCurrent
                    and L.Format("%s here", Cooldowns.Shown(group))
                    or L.Format("%s on %s", Cooldowns.Shown(group), character.name)
                for _, id in ipairs(group.ids) do
                    local entry = store[character.key] and store[character.key][id]
                    if entry then entry.told = entry.readyAt end
                end
            end
        end
    end
    if #parts == 0 then return end
    ns.Print(L.Format("cooldown ready: %s.", table.concat(parts, ", ")))
end

--- One timer for the next cooldown to come ready on any character.
function Cooldowns:Schedule()
    self.generation = (self.generation or 0) + 1
    if not IsOn() or not (C_Timer and C_Timer.After) then return end
    local soonest
    local now = Now()
    for _, character in ipairs(self:All()) do
        for _, group in ipairs(character.groups) do
            if group.readyAt > now and (not soonest or group.readyAt < soonest) then soonest = group.readyAt end
        end
    end
    if not soonest then return end
    local generation = self.generation
    C_Timer.After(soonest - now + 1, function()
        if Cooldowns.generation ~= generation then return end
        Cooldowns:Announce()
        Cooldowns:Schedule()
    end)
end

--- /bts cooldowns: every character's, in chat.
function Cooldowns:Report()
    self:Read()
    local all = self:All()
    if #all == 0 then
        ns.Print(L["no profession cooldowns saved yet. Open each profession once on the character that has one."])
        return
    end
    for _, character in ipairs(all) do
        local parts = {}
        for _, group in ipairs(character.groups) do
            parts[#parts + 1] = group.ready and L.Format("%s ready", Cooldowns.Shown(group))
                or L.Format("%s in %s", Cooldowns.Shown(group), Cooldowns.LeftText(group.readyAt - Now()))
        end
        ns.Print(L.Format("%s: %s.", character.isCurrent and L.Format("%s (you)", character.name) or character.name,
            table.concat(parts, ", ")))
    end
end

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------

function Cooldowns:OnEnable()
    local RegisterForPlayer = ns.RegisterPlayerEvent or ns.RegisterEvent
    RegisterForPlayer(self, "UNIT_SPELLCAST_SUCCEEDED", function(_, _, unit, _, spellID)
        if unit == "player" then Cooldowns:OnCast(spellID) end
    end)
    ns.RegisterEvent(self, "BAG_UPDATE_COOLDOWN", function()
        local key = SelfKey()
        local entries = key and Store() and Store()[key]
        for itemID in pairs(Cooldowns.ITEMS) do
            if entries and entries["item:" .. itemID] then
                Cooldowns:ReadSoon()
                return
            end
        end
    end)
    ns.RegisterEvent(self, "PLAYER_REGEN_ENABLED", function()
        if Cooldowns.readAfterCombat then
            Cooldowns.readAfterCombat = false
            Cooldowns:ReadSoon()
        end
    end)
    if C_Timer and C_Timer.After then
        C_Timer.After(Cooldowns.LOGIN_DELAY, function()
            if InCombat() then
                -- Read once the fight ends; until then the saved times still
                -- set the timer for the next to come ready.
                Cooldowns.readAfterCombat = true
                Cooldowns:Schedule()
            else
                Cooldowns:Read()
            end
            Cooldowns:Announce()
        end)
    end
end

ns.RegisterCommand("cooldowns", L["profession cooldowns on every character (transmutes, Mooncloth, Salt Shaker)"], function()
    Cooldowns:Report()
end)
