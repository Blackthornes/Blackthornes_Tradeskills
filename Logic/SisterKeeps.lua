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
--   _G.BlackthornesButler.Verdicts:Waiting(itemID, bag, slot)
--                                                        -- { short, reason, cost, now, usual }
--   _G.BlackthornesButler.Verdicts:SellAnyway(itemID)    -- the drawer's Sell Anyway
--   _G.BlackthornesButler.Verdicts:AltLevelUpOn()        -- "Send Level Up Materials to Alts:"
--   _G.BlackthornesButler.Verdicts:AltRecipesOn()        -- "Mail Recipes to Who Can Learn Them:"
--
-- Butler's Wait for a Better Price (2026-11-14): a waiting item stays on
-- the drawer with a Butler Says Wait tag and a Sell Anyway button, and
-- List Next passes it over (Posting:GetNextPostable).
--
-- Tradeskills' own "Keep on This Character" (Logic/KeepHere.lua) is read
-- with Butler's, the bigger number winning.
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

--- "Craft First" (a player asked, the owner said build it 2026-11-17,
--- off unless ticked): an item a known craft makes worth more stays off
--- List all. Never rename `sellHoldsCraftFirst`.
function SisterKeeps:CraftFirst()
    return ns.Config and ns.Config.Get and ns.Config:Get("sellHoldsCraftFirst") == true or false
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

--- Why Butler says to wait for a better price on this bag copy, or nil.
--- `held` is Posting's bag entry ({ bag, slot, link }).
function SisterKeeps:ButlerWait(itemID, held)
    if not itemID or type(held) ~= "table" or not held.bag or not held.slot then return nil end
    local wait = Ask("BlackthornesButler", "Verdicts", "Waiting", itemID, held.bag, held.slot)
    if type(wait) ~= "table" then return nil end
    local short = type(wait.short) == "string" and wait.short or nil
    local reason = type(wait.reason) == "string" and wait.reason or short
    if not short and not reason then return nil end
    return {
        short = short or reason,
        reason = reason,
        cost = tonumber(wait.cost),
        now = tonumber(wait.now),
        usual = tonumber(wait.usual),
    }
end

--- Tell Butler to sell it anyway for this auction house visit. True when
--- Butler took it.
function SisterKeeps:SellAnyway(itemID)
    if not itemID then return false end
    local found = Sister("BlackthornesButler", "Verdicts")
    if not found or type(found.SellAnyway) ~= "function" then return false end
    local ok = pcall(found.SellAnyway, found, itemID)
    return ok and true or false
end

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

--- Where the game keeps a set's piece: { bags, bag, slot }, or nil when
--- the client won't say. Read through whichever helper this client has.
local function SetSpot(location)
    location = tonumber(location)
    if not location or location < 2 then return nil end
    local data = rawget(_G, "EquipmentManager_GetLocationData")
    if type(data) == "function" then
        local ok, found = pcall(data, location)
        if ok and type(found) == "table" then
            return { bags = found.isBags == true, bag = found.bag, slot = found.slot }
        end
    end
    local unpack = rawget(_G, "EquipmentManager_UnpackLocation")
    if type(unpack) ~= "function" then return nil end
    local ok, r = pcall(function() return { unpack(location) } end)
    if not ok or type(r) ~= "table" or r[3] == nil then return nil end
    -- Newer clients put a void storage flag before the slot.
    if #r >= 6 then return { bags = r[3] == true, bag = r[6], slot = r[5] } end
    return { bags = r[3] == true, bag = r[5], slot = r[4] }
end

--- Is a copy of this item that an equipment set uses in the bags? Butler
--- answers by item, so a new crafted copy read as the set's while the set's
--- own copy was worn (a player's Toughened Leather Gloves, 2026-11-27).
--- False only when the client shows every set copy is somewhere else (worn
--- or in the bank); true when one is in the bags or the client won't say.
function SisterKeeps.SetCopyInBags(itemID)
    local sets = rawget(_G, "C_EquipmentSet")
    if type(sets) ~= "table" or type(sets.GetEquipmentSetIDs) ~= "function"
        or type(sets.GetItemIDs) ~= "function" or type(sets.GetItemLocations) ~= "function" then
        return true
    end
    local ok, setIDs = pcall(sets.GetEquipmentSetIDs)
    if not ok or type(setIDs) ~= "table" then return true end
    local found = false
    for _, setID in ipairs(setIDs) do
        local fine, ids = pcall(sets.GetItemIDs, setID)
        local good, locations = pcall(sets.GetItemLocations, setID)
        if not fine or type(ids) ~= "table" then return true end
        for slot, id in pairs(ids) do
            if tonumber(id) == itemID then
                found = true
                local spot = good and type(locations) == "table" and SetSpot(locations[slot])
                if not spot or spot.bags then return true end
            end
        end
    end
    -- Not in any set the client lists: Butler knows something we don't.
    if not found then return true end
    return false
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
    if type(set) == "string" and set ~= "" and SisterKeeps.SetCopyInBags(itemID) then
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

--- How many to keep on the character playing ("Keep on This Character",
--- Butler's or Tradeskills' own, Logic/KeepHere.lua), and why; or nil.
--- Where both have a number, the bigger one wins (the owner, 2026-10-18).
local function KeepHereHold(itemID, count)
    local butler = Number((Ask("BlackthornesButler", "KeepHere", "Count", itemID)))
    local keepHere = Sister("BlackthornesButler", "KeepHere")
    local all = butler and butler > 0 and keepHere and type(keepHere.IsAll) == "function"
        and select(2, pcall(keepHere.IsAll, butler)) == true
    local own = ns.KeepHere and ns.KeepHere:Count(itemID)
    if own and ns.KeepHere.IsAll(own) then all = true end
    local keep = math.max(butler or 0, own or 0)
    if keep <= 0 then return nil end
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
        .. ":" .. tostring(self:CraftFirst())
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
    -- The third answer says which keep it was: "craft" for Craft First,
    -- so the Sell list knows the row can be queued.
    return answer[1], answer[2], answer[3]
end

--- Why to craft it first, or nil: a recipe the character playing knows
--- (Butler:CraftFor, the check Butler's Craft group uses) makes one of it
--- worth more than one listed at `price` brings after the cut. Only while
--- "Craft First" is ticked.
function SisterKeeps:CraftReason(itemID, count, price)
    if not self:CraftFirst() then return nil end
    price = tonumber(price)
    local butler = ns.Butler
    if not (price and price > 0 and butler and butler.CraftFor) then return nil end
    local ok, craft = pcall(butler.CraftFor, butler, itemID, count)
    if not ok or type(craft) ~= "table" then return nil end
    local perItem = Number(craft.perItem)
    if not perItem or perItem <= 0 then return nil end
    local net = price * 0.95
    if ns.Profit and ns.Profit.NetFromListing then
        local fine, value = pcall(ns.Profit.NetFromListing, ns.Profit, itemID, price)
        if fine and type(value) == "number" then net = value end
    end
    if perItem <= net then return nil end
    local name = craft.itemID and ns.Util and ns.Util.GetItemName
        and ns.Util.GetItemName(craft.itemID, craft.name) or craft.name
    if type(name) ~= "string" or name == "" then return nil end
    local copper = math.floor(perItem + 0.5)
    local money = ns.Util and ns.Util.FormatMoney and ns.Util.FormatMoney(copper) or tostring(copper)
    return L.Format("Worth more as %s: %s each", name, money)
end

--- What an alt needs mailed (2026-11-27), while Butler's "Send Level Up
--- Materials to Alts:" or "Mail Recipes to Who Can Learn Them:" is ticked:
--- how many to hold back, and why; or nil. The rest still sells.
function SisterKeeps.AltHold(itemID, count)
    local butler = ns.Butler
    if not butler then return nil end
    if Ask("BlackthornesButler", "Verdicts", "AltRecipesOn") == true and butler.RecipeFor then
        local ok, recipe = pcall(butler.RecipeFor, butler, itemID)
        if ok and type(recipe) == "table" and type(recipe.to) == "string" then
            return 1, recipe.now and L.Format("%s can learn this", recipe.to)
                or L.Format("%s can learn this at %s %d", recipe.to, tostring(recipe.profession), recipe.skill or 0)
        end
    end
    if Ask("BlackthornesButler", "Verdicts", "AltLevelUpOn") == true and butler.AltLevelUp then
        local ok, needs = pcall(butler.AltLevelUp, butler)
        local need = ok and type(needs) == "table" and needs[itemID]
        if need and (need.count or 0) > 0 then
            return math.min(count, need.count),
                L.Format("Used to level %s's %s. Needs %d more.", need.to, tostring(need.profession), need.count)
        end
    end
    return nil
end

function SisterKeeps:Work(itemID, held, count, price)
    local butler, butlerWhy = ButlerHold(itemID, count)
    if butler and butler >= count then return count, butlerWhy end
    -- The player's own pick in Butler: held whether or not "Keep What
    -- Other Addons Need" is ticked, as Butler's lists are.
    local alt, altWhy = SisterKeeps.AltHold(itemID, count)
    if alt and alt > (butler or 0) then butler, butlerWhy = alt, altWhy end
    if butler and butler >= count then return count, butlerWhy end

    local craftWhy = self:CraftReason(itemID, count, price)
    if craftWhy then return count, craftWhy, "craft" end
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
