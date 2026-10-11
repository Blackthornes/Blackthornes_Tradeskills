-- Core/SisterNote.lua
-- One chat line, once per account, naming the Blackthornes addons the
-- player does not have yet and what each adds (the owner asked 2026-10-11).
--
-- This file is the same in all five addons (Farmer, Tradeskills, Equipment,
-- Pets and Butler); a fix to it belongs in all five.
--
-- How it stays to one line when several are installed: every copy signs up
-- in one global table, _G.BlackthornesSisterNote, as it loads. The first
-- copy to reach PLAYER_LOGIN starts the only timer; when it fires, every
-- copy has signed up, and that one check speaks for all of them.
--
-- Once per account: the addons it named are kept in each loaded addon's
-- account save (sisterNoteTold[folder] = true), so whichever of them is
-- installed later still knows. The line comes back only for an addon it has
-- never named, one released later, say. An addon that is installed but
-- turned off is left alone: the player turned it off on purpose.
--
-- "Sister addons" in Settings (sisterNote, account wide, on unless
-- unticked). Off in any of them is off in all, and changing it writes all.
-- Never rename sisterNote or sisterNoteTold.

local ADDON_NAME, ns = ...

local Note = ns.NewModule("SisterNote")

-- Seconds after login, so the line lands under the game's own login chat
-- rather than in the middle of it.
Note.DELAY = 8

-- Every sister, by folder name, with the words players see.
Note.ADDONS = {
    { folder = "Blackthornes_Farmer", title = "Blackthornes Farmer",
      adds = "where to farm any material" },
    { folder = "Blackthornes_TS", title = "Blackthornes Tradeskills",
      adds = "auction prices, crafting profits and a craft queue" },
    { folder = "Blackthornes_Equipment", title = "Blackthornes Equipment",
      adds = "which gear is an upgrade for you, and where to get it" },
    { folder = "Blackthornes_Pets", title = "Blackthornes Pets",
      adds = "feeding and taming for hunter and warlock pets" },
    { folder = "Blackthornes_Butler", title = "Blackthornes Butler",
      adds = "what to do with every item in your bags" },
}

local shared = _G.BlackthornesSisterNote
if type(shared) ~= "table" then
    shared = {}
    _G.BlackthornesSisterNote = shared
end
if type(shared.members) ~= "table" then shared.members = {} end
Note.shared = shared

--- This addon's account save, or nil before it is loaded.
local function Store()
    local db = ns.db
    if type(db) == "table" then return db end
    return nil
end

--- Every loaded sister's account save, this one's included.
function Note:Stores()
    local stores, seen = {}, {}
    local function Add(db)
        if type(db) == "table" and not seen[db] then
            seen[db] = true
            stores[#stores + 1] = db
        end
    end
    Add(Store())
    for _, read in pairs(shared.members) do
        local ok, db = pcall(read)
        if ok then Add(db) end
    end
    return stores
end

function Note:IsOn()
    for _, db in ipairs(self:Stores()) do
        if db.sisterNote == false then return false end
    end
    return true
end

function Note:SetOn(on)
    for _, db in ipairs(self:Stores()) do
        db.sisterNote = on and true or false
    end
end

--- "loaded", "off" (installed but not loaded), "missing", or nil when the
--- client will not say.
function Note.State(folder)
    local api = _G.C_AddOns
    local ok, answer = pcall(function()
        local isLoaded = api and api.IsAddOnLoaded or _G.IsAddOnLoaded
        if type(isLoaded) == "function" and isLoaded(folder) then return "loaded" end

        local exists = api and api.DoesAddOnExist
        if type(exists) == "function" then
            return exists(folder) and "off" or "missing"
        end

        local getInfo = api and api.GetAddOnInfo or _G.GetAddOnInfo
        if type(getInfo) == "function" then
            local name, _, _, _, reason = getInfo(folder)
            if reason == "MISSING" then return "missing" end
            if name then return "off" end
        end
        return nil
    end)
    if ok then return answer end
    return nil
end

--- The sisters to name now: not installed, and never named before.
function Note:ToName()
    local told = {}
    for _, db in ipairs(self:Stores()) do
        if type(db.sisterNoteTold) == "table" then
            for folder in pairs(db.sisterNoteTold) do told[folder] = true end
        end
    end

    local list = {}
    for _, entry in ipairs(self.ADDONS) do
        if not told[entry.folder] and Note.State(entry.folder) == "missing" then
            list[#list + 1] = entry
        end
    end
    return list
end

--- "A", "A and B", "A, B and C".
local function Join(parts)
    if #parts <= 1 then return parts[1] or "" end
    return table.concat(parts, ", ", 1, #parts - 1) .. " and " .. parts[#parts]
end

--- The one line, for the addon saying it.
function Note:Line(list)
    local own = ADDON_NAME
    for _, entry in ipairs(self.ADDONS) do
        if entry.folder == ADDON_NAME then own = entry.title end
    end

    local accent = ns.COLORS and ns.COLORS.accent or "ffc8a44d"
    local muted = ns.COLORS and ns.COLORS.muted or "ff8b919b"

    local named = {}
    for i, entry in ipairs(list) do
        named[i] = ("|c%s%s|r (%s)"):format(accent, entry.title, entry.adds)
    end

    return ("|c%s%s|r has sister addons that share what they know: %s. %s on CurseForge. "
        .. "|c%sThis note shows once.|r"):format(accent, own, Join(named),
        #list == 1 and "It's" or "They're", muted)
end

function Note:Check()
    if shared.checked then return end
    shared.checked = true

    if not self:IsOn() then return end
    local list = self:ToName()
    if #list == 0 then return end

    ns.PrintRaw(self:Line(list))

    for _, db in ipairs(self:Stores()) do
        if db.sisterNoteTold == nil then db.sisterNoteTold = {} end
        if type(db.sisterNoteTold) == "table" then
            for _, entry in ipairs(list) do db.sisterNoteTold[entry.folder] = true end
        end
    end
end

function Note:OnInitialize()
    shared.members[ADDON_NAME] = Store
end

function Note:OnEnable()
    -- One timer for all five, started by whichever logs in first. No ticker.
    if shared.scheduled then return end
    shared.scheduled = true

    local timer = _G.C_Timer
    if not (timer and type(timer.After) == "function") then return end
    timer.After(self.DELAY, function()
        local ok, err = pcall(Note.Check, Note)
        if not ok then ns.Debug("sister note:", tostring(err)) end
    end)
end

ns.RegisterCommand("sisters", "turn the once-only note about the other Blackthornes addons on or off", function()
    local on = not Note:IsOn()
    Note:SetOn(on)
    if on then
        ns.Print("the note about the other Blackthornes addons is on. It shows once for any you don't have.")
    else
        ns.Print("the note about the other Blackthornes addons is off, in all of them.")
    end
end)
