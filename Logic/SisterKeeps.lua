-- Blackthornes Tradeskills -- Logic/SisterKeeps.lua
-- What the other Blackthornes addons want kept, so the auction house's
-- Sell list and List all never put it up (the owner said build it,
-- 2026-10-16).
--
-- Each sister already answers Butler about a bag item. The same calls are
-- read here, inside a pcall, read only, with no TOC dependency:
--
--   _G.BlackthornesFarmer.Butler:Advise(itemID)          -- { need, target, have }: a goal
--   _G.BlackthornesFarmer.Value:Contents(name)           -- a clam's worth opened, copper
--   _G.BlackthornesEquipment.Butler:Advise(link, bag, slot)
--                                                        -- { upgrade, gain, tool, alt }
--   _G.BlackthornesPets.Butler:Advise(itemID)            -- { eats, buff }
--   _G.BlackthornesButler.Verdicts:Choice(itemID)        -- "keep", "bank", "mail" (and to whom)
--   _G.BlackthornesButler.Verdicts:IsMe(name)            -- the character playing
--   _G.BlackthornesButler.Verdicts:InSet(itemID)         -- an equipment set's name
--   _G.BlackthornesButler.Quests:Reason(itemID)          -- an open quest's need
--   _G.BlackthornesButler.Ammo:Keeps(itemID)             -- a hunter's own ammo
--   _G.BlackthornesButler.Learning:Get(itemID)           -- "keep" once bought back
--   _G.BlackthornesButler.KeepHere:Count(itemID)         -- how many to keep here
--
-- What Butler says to keep is held whether or not "Keep What Other Addons
-- Need" is ticked (2026-10-17); the rest only while it is.
--
-- A sister that is not loaded, raises or answers something else is
-- skipped. Nothing is saved and nothing is written back. Answers are kept
-- per bag copy until the bags change (Inventory.changes) or KEEP seconds
-- pass, since Sell asks about every bag item once a second.

local _, ns = ...
local L = ns.L or setmetatable({ Format = string.format }, { __index = function(_, key) return key end })

local SisterKeeps = ns.NewModule("SisterKeeps")

SisterKeeps.KEEP = 10

local kept = {}
local keptAt, keptChanges

local function Now()
    return type(GetTime) == "function" and GetTime() or 0
end

function SisterKeeps:IsOn()
    return ns.Config and ns.Config.Get and ns.Config:Get("sellHoldsSisterKeeps") == true or false
end

--- Gear another character could wear is held back only while "Keep
--- Upgrades for Alts" is ticked (off unless ticked, the owner 2026-10-16).
function SisterKeeps:HoldsAltUpgrades()
    return ns.Config and ns.Config.Get and ns.Config:Get("sellHoldsAltUpgrades") == true or false
end

-- Rings and trinkets: a character wears two.
local PAIRS = { INVTYPE_FINGER = true, INVTYPE_TRINKET = true }

--- How many of a piece of gear a character wears at once.
function SisterKeeps.Wears(itemID)
    local info = C_Item and C_Item.GetItemInfoInstant or GetItemInfoInstant
    if type(info) ~= "function" then return 1 end
    local ok, _, _, _, equipLoc = pcall(info, itemID)
    return (ok and PAIRS[equipLoc]) and 2 or 1
end

function SisterKeeps:Forget()
    kept = {}
    keptAt, keptChanges = nil, nil
end

--- A sister's module, or nil.
local function Sister(global, module)
    local addon = rawget(_G, global)
    if type(addon) ~= "table" then return nil end
    local found = addon[module]
    if type(found) ~= "table" then return nil end
    return found
end

--- Call `method` on a sister's module in a pcall. nil when it is missing
--- or raises.
local function Ask(global, module, method, ...)
    local found = Sister(global, module)
    if not found or type(found[method]) ~= "function" then return nil end
    local ok, a, b = pcall(found[method], found, ...)
    if not ok then return nil end
    return a, b
end

SisterKeeps.Ask = Ask

local function Number(value)
    value = tonumber(value)
    if value and value == value and value >= 0 then return value end
    return nil
end

local function Gain(advice)
    local gain = Number(advice.gain)
    return gain and math.floor(gain + 0.5) or nil
end

local function CharacterName(key)
    if type(key) ~= "string" or key == "" then return nil end
    if ns.Recipes and ns.Recipes.GetCharacterName then
        local ok, name = pcall(ns.Recipes.GetCharacterName, ns.Recipes, key)
        if ok and type(name) == "string" and name ~= "" and name ~= "?" and name ~= key then
            return name
        end
    end
    return nil
end

--- What Equipment says about this copy: why to keep it, or nil.
local function GearReason(itemID, link, bag, slot)
    local advice = Ask("BlackthornesEquipment", "Butler", "Advise", link or itemID, bag, slot)
    if type(advice) ~= "table" then return nil end

    local gain = Gain(advice)
    if advice.upgrade == "now" or advice.upgrade == "later" then
        if gain then return L.Format("An upgrade for you, +%d%%", gain) end
        return L["An upgrade for you"]
    end

    if type(advice.alt) == "table" and SisterKeeps:HoldsAltUpgrades() then
        local name = CharacterName(advice.alt.key)
        local altGain = Gain(advice.alt)
        if name and altGain then return L.Format("An upgrade for %s, +%d%%", name, altGain) end
        if name then return L.Format("An upgrade for %s", name) end
        return L["An upgrade for one of your characters"]
    end

    if advice.tool == true then return L["A tool you use"] end
    return nil
end

--- What Butler's own lists say: why to keep it, or nil.
local function ButlerReason(itemID)
    local choice, mailTo = Ask("BlackthornesButler", "Verdicts", "Choice", itemID)
    if choice == "keep" then return L["On your Always keep list"] end
    if choice == "bank" then return L["On your Always bank list"] end
    -- Mailed to the character playing, it has arrived where it was going,
    -- so it sells here like anything else (the owner, 2026-10-18).
    if choice == "mail" and Ask("BlackthornesButler", "Verdicts", "IsMe", mailTo) ~= true then
        return L["On your Always mail list"]
    end

    local set = Ask("BlackthornesButler", "Verdicts", "InSet", itemID)
    if type(set) == "string" and set ~= "" then
        return L.Format("In your %s equipment set", set)
    end

    local quest = Ask("BlackthornesButler", "Quests", "Reason", itemID)
    if type(quest) == "string" and quest ~= "" then return quest end

    -- A hunter's own arrows or bullets (a player saw Razor Arrow offered
    -- while Butler said Keep, 2026-10-17).
    local ammo = Ask("BlackthornesButler", "Ammo", "Keeps", itemID)
    if type(ammo) == "string" and ammo ~= "" then return ammo end

    -- Sold by Butler and bought back, so Butler keeps it from then on.
    if Ask("BlackthornesButler", "Learning", "Get", itemID) == "keep" then
        return L["You bought this back, so Butler keeps it"]
    end
    return nil
end

--- How many Butler keeps on the character playing ("Keep on This
--- Character"), and why; or nil.
local function KeepHereHold(itemID, count)
    local keep = Number((Ask("BlackthornesButler", "KeepHere", "Count", itemID)))
    if not keep or keep <= 0 then return nil end
    local keepHere = Sister("BlackthornesButler", "KeepHere")
    local all = keepHere and type(keepHere.IsAll) == "function" and select(2, pcall(keepHere.IsAll, keep)) == true
    if all or keep >= count then
        return count, all and L["Keeping all on this character"] or L.Format("Keeping %d on this character", keep)
    end
    return keep, L.Format("Keeping %d on this character", keep)
end

--- What Butler itself says to keep, and how many. Asked whether or not
--- "Keep What Other Addons Need" is ticked: these are the player's own
--- picks in Butler, and the Sell list should never offer what Butler
--- says to keep.
local function ButlerHold(itemID, count)
    local whole = ButlerReason(itemID)
    if whole then return count, whole end
    return KeepHereHold(itemID, count)
end

--- How many to hold back for a Farmer goal, and why; or nil.
local function GoalHold(itemID, count)
    local advice = Ask("BlackthornesFarmer", "Butler", "Advise", itemID)
    if type(advice) ~= "table" then return nil end

    local target = Number(advice.target)
    if not target or target <= 0 then return nil end

    local need = Number(advice.need) or 0
    local reason = need > 0 and L.Format("Your goal needs %d more", need) or L["For your goal"]
    return math.min(count, target), reason
end

--- What one opening of a clam or sack is worth to Farmer, copper, or nil.
function SisterKeeps:OpenedWorth(itemID)
    local name = ns.FarmerGoals and ns.FarmerGoals.ItemName and ns.FarmerGoals.ItemName(itemID)
    if not name then return nil end
    return Number((Ask("BlackthornesFarmer", "Value", "Contents", name)))
end

--- How many of a bag item to hold back from the Sell list, and why.
--
-- `held` is Posting's bag entry ({ bag, slot, link }), `count` how many it
-- would list, `price` its listing price. Returns 0 and nil when nothing
-- holds it.
function SisterKeeps:Hold(itemID, held, count, price)
    count = tonumber(count) or 0
    if not itemID or count <= 0 then return 0, nil end

    local changes = ns.Inventory and ns.Inventory.changes
    if keptChanges ~= changes or not keptAt or Now() - keptAt > self.KEEP then
        kept, keptAt, keptChanges = {}, Now(), changes
    end

    local link = held and held.link
    local key = itemID .. ":" .. count .. ":" .. tostring(price or "") .. ":" .. tostring(self:IsOn())
    if type(link) == "string" then
        local ok, itemString = pcall(function()
            local found = string.match(link, "item[%-?%d:]+")
            return found and found .. ""
        end)
        if ok and type(itemString) == "string" then key = itemString .. ":" .. key end
    end

    local answer = kept[key]
    if not answer then
        answer = { self:Work(itemID, held, count, price) }
        kept[key] = answer
    end
    return answer[1], answer[2]
end

function SisterKeeps:Work(itemID, held, count, price)
    local butler, butlerWhy = ButlerHold(itemID, count)
    if butler and butler >= count then return count, butlerWhy end
    if not self:IsOn() then
        if butler and butler > 0 then return butler, butlerWhy end
        return 0, nil
    end

    local pet = Ask("BlackthornesPets", "Butler", "Advise", itemID)
    if type(pet) == "table" and pet.eats == true and pet.buff ~= true then
        return count, L["Your pet eats this"]
    end

    -- An upgrade is held only as many as a character wears: one, two rings
    -- or trinkets; the spare copies sell (a player's five robes, 2026-10-18).
    local gear = GearReason(itemID, held and held.link, held and held.bag, held and held.slot)
    if gear then
        local wear = math.min(count, SisterKeeps.Wears(itemID))
        if butler and butler > wear then return butler, butlerWhy end
        return wear, gear
    end

    local goal, why = GoalHold(itemID, count)
    if goal and goal > 0 and (not butler or goal > butler) then return goal, why end

    local opened = self:OpenedWorth(itemID)
    if opened and price and opened > price then
        local money = ns.Util and ns.Util.FormatMoney and ns.Util.FormatMoney(math.floor(opened + 0.5))
            or tostring(math.floor(opened + 0.5))
        return count, L.Format("Worth more opened (%s)", money)
    end

    if butler and butler > 0 then return butler, butlerWhy end
    return 0, nil
end
