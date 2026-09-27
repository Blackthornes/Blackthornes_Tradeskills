-- Blackthornes Tradeskills -- Logic/DisenchantLog.lua
-- What your own disenchants actually gave.
--
-- The built-in table in Logic/Disenchant.lua is the published Classic one,
-- and nothing guarantees Forever matches it. So every disenchant you do is
-- recorded here: which item went in, and what came out. Results are pooled
-- by row of the table (quality, item level band, armor or weapon), and once
-- a row has enough of them, Disenchant:GetOutcomes uses yours instead.
--
-- Knowing what came out is easy: it is the loot window that opens after the
-- cast. Knowing what went in is the hard part, because the game does not say
-- which item a Disenchant was cast on. Three ways are tried, best first:
--
--   * the loot window's source, which on a modern client names the item the
--     loot came from;
--   * the bag slot you clicked while the spell was waiting for a target;
--   * the item name the game passes with the cast, matched against the bags.
--
-- Each record notes which one found the item, and `/bts delog` shows it, so
-- the first disenchant in game says which of these this client supports.

local _, ns = ...

local DisenchantLog = ns.NewModule("DisenchantLog")

local Util = ns.Util

-- Disenchant's spell ID on Classic. The name is checked too, in case Forever
-- numbers it differently.
local DISENCHANT_SPELL = 13262
local DISENCHANT_NAME = "Disenchant"

-- How long after the cast finishes the loot window may take to open.
local LOOT_WINDOW = 5

-- How long a clicked bag slot stays the likely target.
local AIM_WINDOW = 30

-- Recent disenchants kept for /bts delog.
local RECENT_KEPT = 20

local aimed        -- { itemID, from, at }: the item the spell was pointed at
local cast         -- { itemID, from, at }: a Disenchant that just finished

--------------------------------------------------------------------------------
-- Storage
--------------------------------------------------------------------------------

--- Account wide: what an item breaks into does not depend on who breaks it.
function DisenchantLog:GetTable()
    if not ns.db then return { bands = {}, recent = {}, missed = 0 } end

    local log = ns.db.disenchantLog or {}
    ns.db.disenchantLog = log

    log.bands = log.bands or {}
    log.recent = log.recent or {}
    log.missed = log.missed or 0

    return log
end

--- The pooled results for one row of the table, or nil when there are none.
function DisenchantLog:GetBand(key)
    if not key then return nil end
    return self:GetTable().bands[key]
end

--- Add one disenchant: the item that went in and what came out.
--
-- @param results { [materialID] = count }
-- @return true when it was recorded
function DisenchantLog:Record(itemID, results, from)
    local _, facts = ns.Disenchant:GetOutcomes(itemID)
    if not facts or not facts.key then return false, "that item cannot be disenchanted" end

    local log = self:GetTable()
    local band = log.bands[facts.key] or { casts = 0, got = {} }
    log.bands[facts.key] = band

    band.casts = band.casts + 1

    for materialID, count in pairs(results) do
        local got = band.got[materialID] or { times = 0, total = 0 }
        band.got[materialID] = got

        got.times = got.times + 1
        got.total = got.total + count
        got.min = got.min and math.min(got.min, count) or count
        got.max = got.max and math.max(got.max, count) or count
    end

    table.insert(log.recent, 1, {
        itemID = itemID, results = results, from = from,
        at = time and time() or 0,
    })
    while #log.recent > RECENT_KEPT do table.remove(log.recent) end

    if ns.UI and ns.UI.RefreshActiveTab then ns.UI:RefreshActiveTab() end

    return true
end

--- A disenchant that finished but could not be recorded, and why.
function DisenchantLog:Miss(reason)
    local log = self:GetTable()
    log.missed = log.missed + 1
    log.lastMiss = reason

    ns.Print(("could not record that disenchant: %s. /bts delog has more."):format(reason))
end

--------------------------------------------------------------------------------
-- Watching
--------------------------------------------------------------------------------

local function Now()
    return GetTime and GetTime() or 0
end

--- Is this the player? Read inside a pcall: in an instance the game can hand
--- over a value that refuses to be compared.
local function IsPlayer(unit)
    local ok, yes = pcall(function() return unit == "player" end)
    return ok and yes == true
end

local function IsDisenchant(spellID)
    local ok, yes = pcall(function() return spellID == DISENCHANT_SPELL end)
    if ok and yes then return true end

    local name
    if Util.HasFunction("C_Spell.GetSpellName") then
        local gotName, value = pcall(C_Spell.GetSpellName, spellID)
        if gotName then name = value end
    elseif type(GetSpellInfo) == "function" then
        local gotName, value = pcall(GetSpellInfo, spellID)
        if gotName then name = value end
    end

    local same, match = pcall(function() return name == DISENCHANT_NAME end)
    return same and match == true
end

DisenchantLog._IsDisenchant = IsDisenchant

local function ItemAt(bag, slot)
    if not Util.HasFunction("C_Container.GetContainerItemID") then return nil end
    local ok, itemID = pcall(C_Container.GetContainerItemID, bag, slot)
    if ok and type(itemID) == "number" then return itemID end
    return nil
end

--- A bag slot was clicked. If a spell was waiting for a target, that slot's
--- item is what it was pointed at.
function DisenchantLog:OnBagClick(bag, slot)
    if type(SpellIsTargeting) ~= "function" then return end

    local ok, targeting = pcall(SpellIsTargeting)
    if not ok or not targeting then return end

    local itemID = ItemAt(bag, slot)
    if itemID then
        aimed = { itemID = itemID, from = "click", at = Now() }
    end
end

--- The disenchantable item in the bags with this name, if there is one.
function DisenchantLog:FindInBags(name)
    if type(name) ~= "string" or name == "" then return nil end

    local counts = ns.Inventory and ns.Inventory:GetBagCounts() or {}

    for itemID in pairs(counts) do
        if ns.Disenchant:IsDisenchantable(itemID) then
            local itemName = ns.Disenchant:ItemName(itemID)
            -- Random-suffix items carry "of the Bear" after the base name.
            if itemName == name or name:sub(1, #itemName + 1) == itemName .. " " then
                return itemID
            end
        end
    end

    return nil
end

function DisenchantLog:OnCastSent(_, unit, target, _, spellID)
    if not IsPlayer(unit) then return end

    -- A click that aimed some other spell, an enchant say, is not this one.
    if not IsDisenchant(spellID) then
        aimed = nil
        return
    end

    local ok, name = pcall(function() return target .. "" end)
    local named = ok and self:FindInBags(name) or nil

    -- The click is the better witness, unless the name the game sends says
    -- it was some other item.
    local clicked = aimed and Now() - aimed.at < AIM_WINDOW and aimed.itemID or nil
    if clicked and (not named or named == clicked) then return end

    if named then
        aimed = { itemID = named, from = "name", at = Now() }
    end
end

function DisenchantLog:OnCastSucceeded(_, unit, _, spellID)
    if not IsPlayer(unit) or not IsDisenchant(spellID) then return end

    local fresh = aimed and Now() - aimed.at < AIM_WINDOW
    cast = {
        itemID = fresh and aimed.itemID or nil,
        from = fresh and aimed.from or nil,
        at = Now(),
    }
    aimed = nil
end

--- The item a loot slot came from, when the game says.
local function LootSourceItem(slot)
    if type(GetLootSourceInfo) ~= "function" then return nil end
    if not Util.HasFunction("C_Item.GetItemIDByGUID") then return nil end

    local ok, guid = pcall(GetLootSourceInfo, slot)
    if not ok or type(guid) ~= "string" then return nil end

    local checked, isItem = pcall(function() return guid:sub(1, 5) == "Item-" end)
    if not checked or not isItem then return nil end

    local gotID, itemID = pcall(C_Item.GetItemIDByGUID, guid)
    if gotID and type(itemID) == "number" then return itemID end

    return nil
end

--- Read the loot window, if it belongs to the Disenchant that just finished.
function DisenchantLog:OnLootReady()
    if not cast then return end

    local pending = cast
    if Now() - pending.at > LOOT_WINDOW then
        cast = nil
        return
    end

    if type(GetNumLootItems) ~= "function" then return end
    local gotCount, slots = pcall(GetNumLootItems)
    if not gotCount or type(slots) ~= "number" or slots < 1 then return end

    -- Read once: LOOT_READY and LOOT_OPENED both fire.
    cast = nil

    local results, itemID, from = {}, pending.itemID, pending.from
    local any = false

    for slot = 1, slots do
        local gotLink, link = pcall(GetLootSlotLink, slot)
        local materialID = gotLink and type(link) == "string"
            and tonumber(link:match("item:(%d+)")) or nil

        if not materialID or not ns.Disenchant:IsMaterial(materialID) then
            self:Miss("the loot was not enchanting materials")
            return
        end

        local gotInfo, _, _, quantity = pcall(GetLootSlotInfo, slot)
        quantity = gotInfo and tonumber(quantity) or 1

        results[materialID] = (results[materialID] or 0) + math.max(1, quantity)
        any = true

        local source = LootSourceItem(slot)
        if source then itemID, from = source, "loot" end
    end

    if not any then return end

    if not itemID then
        self:Miss("the game did not say which item was disenchanted")
        return
    end

    local recorded, why = self:Record(itemID, results, from)
    if not recorded then self:Miss(why or "unknown") end
end

--------------------------------------------------------------------------------
-- Command
--------------------------------------------------------------------------------

local FROM = {
    loot = "loot window",
    click = "bag click",
    name = "cast name",
}

local function Describe(results)
    local parts = {}
    for materialID, count in pairs(results or {}) do
        parts[#parts + 1] = ("%dx %s"):format(count,
            ns.Disenchant:MaterialName(materialID) or Util.GetItemLabel(materialID))
    end
    table.sort(parts)
    return table.concat(parts, ", ")
end

local function Report(input)
    local log = DisenchantLog:GetTable()

    if (input or ""):lower() == "reset" then
        ns.db.disenchantLog = nil
        ns.Print("your recorded disenchants are cleared; values use the built-in table again")
        if ns.UI and ns.UI.RefreshActiveTab then ns.UI:RefreshActiveTab() end
        return
    end

    local total, groups, trusted = 0, 0, 0
    for _, band in pairs(log.bands) do
        total = total + (band.casts or 0)
        groups = groups + 1
        if (band.casts or 0) >= ns.Disenchant.LEARN_AFTER then trusted = trusted + 1 end
    end

    ns.Print(("%d disenchant%s recorded across %d kind%s of item; %d kind%s use%s your results (after %d each)")
        :format(total, total == 1 and "" or "s", groups, groups == 1 and "" or "s",
            trusted, trusted == 1 and "" or "s", trusted == 1 and "s" or "",
            ns.Disenchant.LEARN_AFTER))

    if log.missed > 0 then
        ns.Print(("%d could not be recorded; the last because %s"):format(log.missed, log.lastMiss or "?"))
    end

    for index = 1, math.min(5, #log.recent) do
        local entry = log.recent[index]
        ns.Print(("  %s gave %s (item found by %s)"):format(Util.GetItemLabel(entry.itemID),
            Describe(entry.results), FROM[entry.from] or entry.from or "?"))
    end

    if total == 0 and log.missed == 0 then
        ns.Print("disenchant something, then run /bts delog again to see it recorded")
    end
end

DisenchantLog._Report = Report

ns.RegisterCommand("delog", "your recorded disenchants; /bts delog reset clears them", Report)

--------------------------------------------------------------------------------
-- Setup
--------------------------------------------------------------------------------

function DisenchantLog:OnEnable()
    ns.RegisterEvent(self, "UNIT_SPELLCAST_SENT", self.OnCastSent)
    ns.RegisterEvent(self, "UNIT_SPELLCAST_SUCCEEDED", self.OnCastSucceeded)
    ns.RegisterEvent(self, "LOOT_READY", self.OnLootReady)
    ns.RegisterEvent(self, "LOOT_OPENED", self.OnLootReady)

    -- Watch bag clicks without replacing them: hooksecurefunc runs after
    -- Blizzard's own call and changes nothing about it.
    if type(hooksecurefunc) == "function" and type(C_Container) == "table" then
        for _, name in ipairs({ "UseContainerItem", "PickupContainerItem" }) do
            if type(C_Container[name]) == "function" then
                pcall(hooksecurefunc, C_Container, name, function(bag, slot)
                    DisenchantLog:OnBagClick(bag, slot)
                end)
            end
        end
    end
end
