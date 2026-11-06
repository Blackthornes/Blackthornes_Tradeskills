-- Blackthornes Tradeskills -- Logic/EnchantWindow.lua
-- What the Enchant window shows and how it casts (Trent asked 2026-11-05,
-- from a mockup: Retail's enchanting window brought to Forever).
--
-- The window (UI/EnchantWindow.lua) sits beside the game's Enchanting window
-- while it is open and "Enchant Window:" is on. Pick an enchant, pick an item
-- you wear or carry, click Enchant. This file knows:
--   * which learned recipes are enchants (`Enchants`, read a few a frame);
--   * which of your items one fits, worn first, then bags (`Items`);
--   * what each item has on it now (`CurrentEnchant`);
--   * what the materials are, how many you have and what they cost;
--   * Equipment's "+3% for you" and its best pick, inside a pcall;
--   * how a click casts it. There are three ways, tried in order, and the
--     probe says which this client takes:
--       one   C_TradeSkillUI.CraftEnchant with the item: one click;
--       two   CraftRecipe, then "Put It On", a secure /use on the item while
--             the spell waits for a target (the PreClick checks it waits);
--       glow  the item's own slot glows while the spell waits, and the
--             player clicks it themselves.
--
-- Never in a fight. The game's own replace and bind boxes still show, and
-- nothing here ever clicks them. Nothing is saved but the setting, the
-- window's place and size, the last enchant picked and what each way did
-- (for the probe).

local _, ns = ...
local L = ns.L or setmetatable({ Format = string.format }, { __index = function(_, key) return key end })

local EnchantWindow = ns.NewModule("EnchantWindow")

local Util = ns.Util

-- Enum.TradeskillRecipeType.Enchant on the retail engine.
EnchantWindow.RECIPE_TYPE_ENCHANT = 3
-- How long after a click the first way is judged (seconds). A replace box
-- the game shows first counts as waiting on the player, never as failed.
EnchantWindow.JUDGE_AFTER = 1.5
-- Gear slots an enchant can go on (no shirt, tabard or ranged: scopes are
-- Engineering's).
EnchantWindow.WORN_SLOTS = { 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17 }
-- The game's own boxes that ask before an enchant goes on. Read only, to
-- tell "waiting on you" from "nothing happened". Never clicked.
EnchantWindow.ASK_BOXES = { "REPLACE_ENCHANT", "BIND_ENCHANT", "TRADE_REPLACE_ENCHANT",
    "ACTION_WILL_BIND_ITEM", "REPLACE_TRADESKILL_ENCHANT" }

-- English slot words in a recipe's name, for a client that will not list
-- the items an enchant fits. "2H Weapon" before "Weapon".
EnchantWindow.SLOT_WORDS = {
    { "2H Weapon", { INVTYPE_2HWEAPON = true } },
    { "Bracer", { INVTYPE_WRIST = true } },
    { "Chest", { INVTYPE_CHEST = true, INVTYPE_ROBE = true } },
    { "Cloak", { INVTYPE_CLOAK = true } },
    { "Boots", { INVTYPE_FEET = true } },
    { "Gloves", { INVTYPE_HAND = true } },
    { "Shield", { INVTYPE_SHIELD = true } },
    { "Weapon", { INVTYPE_WEAPON = true, INVTYPE_WEAPONMAINHAND = true,
        INVTYPE_WEAPONOFFHAND = true, INVTYPE_2HWEAPON = true } },
}

-- Worn slot ID to the equip spots that sit there, for Equipment's slotID.
EnchantWindow.SLOT_SPOTS = {
    [5] = { INVTYPE_CHEST = true, INVTYPE_ROBE = true },
    [8] = { INVTYPE_FEET = true },
    [9] = { INVTYPE_WRIST = true },
    [10] = { INVTYPE_HAND = true },
    [15] = { INVTYPE_CLOAK = true },
    [16] = { INVTYPE_WEAPON = true, INVTYPE_WEAPONMAINHAND = true, INVTYPE_2HWEAPON = true },
    [17] = { INVTYPE_SHIELD = true, INVTYPE_WEAPON = true, INVTYPE_WEAPONOFFHAND = true },
}

local function InCombat()
    return type(InCombatLockdown) == "function" and InCombatLockdown() and true or false
end

local function Call(path, ...)
    if not Util.HasFunction(path) then return false end
    local fn = Util.ResolvePath(path)
    return pcall(fn, ...)
end

local function Settings()
    return ns.db and ns.db.settings
end

--------------------------------------------------------------------------------
-- The setting
--------------------------------------------------------------------------------

function EnchantWindow:IsOn()
    return ns.Config:Get("enchantWindow") == true
end

function EnchantWindow:SetOn(on)
    ns.Config:Set("enchantWindow", on and true or false)
    if ns.EnchantWindowUI then ns.EnchantWindowUI:Update() end
end

--------------------------------------------------------------------------------
-- What the client gives (the probe's lines)
--------------------------------------------------------------------------------

function EnchantWindow:Caps()
    local enum = type(Enum) == "table" and type(Enum.TradeskillRecipeType) == "table"
        and Enum.TradeskillRecipeType.Enchant or nil
    return {
        craftEnchant = Util.HasFunction("C_TradeSkillUI.CraftEnchant"),
        craftRecipe = Util.HasFunction("C_TradeSkillUI.CraftRecipe"),
        enchantItems = Util.HasFunction("C_TradeSkillUI.GetEnchantItems"),
        itemLocation = Util.HasFunction("C_Item.GetItemLocation")
            or (type(ItemLocation) == "table" and type(ItemLocation.CreateFromBagAndSlot) == "function"),
        targeting = type(SpellIsTargeting) == "function",
        recipeType = enum,
    }
end

local function Yes(value) return value and "yes" or "no" end

--- The way a click casts: Trent's pick (`/bts enchant way`), else what this
--- client was seen to take, else the first one it has.
function EnchantWindow:Way()
    local settings = Settings() or {}
    local forced = settings.enchantWindowWay
    if forced == "one" or forced == "two" or forced == "glow" then return forced end

    local seen = type(settings.enchantWindowSeen) == "table" and settings.enchantWindowSeen or {}
    local caps = self:Caps()
    if caps.craftEnchant and caps.itemLocation and seen.one ~= "failed" and not self.oneFailed then
        return "one"
    end
    if caps.craftRecipe and caps.targeting and seen.two ~= "failed" then return "two" end
    return "glow"
end

--- Note what a way did, for the probe and the next click.
function EnchantWindow:Saw(way, result)
    local settings = Settings()
    if not settings then return end
    if type(settings.enchantWindowSeen) ~= "table" then settings.enchantWindowSeen = {} end
    settings.enchantWindowSeen[way] = result
    if way == "one" and result == "failed" then self.oneFailed = true end
end

function EnchantWindow:ProbeLines()
    local caps = self:Caps()
    local settings = Settings() or {}
    local seen = type(settings.enchantWindowSeen) == "table" and settings.enchantWindowSeen or {}
    local lines = {
        { "enchant window", self:IsOn() and "on" or "off" },
        { "enchant one click", ("CraftEnchant %s, item locations %s, seen %s"):format(
            Yes(caps.craftEnchant), Yes(caps.itemLocation), tostring(seen.one or "not tried")) },
        { "enchant two clicks", ("CraftRecipe %s, SpellIsTargeting %s, seen %s"):format(
            Yes(caps.craftRecipe), Yes(caps.targeting), tostring(seen.two or "not tried")) },
        { "enchant glow", tostring(seen.glow or "not tried") },
        { "enchant fits list", ("GetEnchantItems %s, recipe type enum %s"):format(
            Yes(caps.enchantItems), tostring(caps.recipeType)) },
        { "enchant way", self:Way() .. (settings.enchantWindowWay and " (picked)" or "") },
    }
    -- Where the strip sits under the recipe pane, and what it follows.
    local ui = ns.EnchantWindowUI
    if ui and type(ui.ProbeLines) == "function" then
        local ok, more = pcall(ui.ProbeLines, ui)
        if ok and type(more) == "table" then
            for _, line in ipairs(more) do lines[#lines + 1] = line end
        end
    end
    return lines
end

--------------------------------------------------------------------------------
-- The enchants this character knows
--------------------------------------------------------------------------------

--- Is the game's open profession window Enchanting?
function EnchantWindow:EnchantingOpen()
    local ok, info = Call("C_TradeSkillUI.GetBaseProfessionInfo")
    if ok and type(info) == "table" and (info.professionID or info.professionName) then
        return ns.Recipes.IsEnchanting({ skillLineID = info.professionID, name = info.professionName })
    end
    local okLine, lineID, name = Call("C_TradeSkillUI.GetTradeSkillLine")
    if okLine and (lineID or name) then
        return ns.Recipes.IsEnchanting({ skillLineID = type(lineID) == "number" and lineID or nil,
            name = type(name) == "string" and name or (type(lineID) == "string" and lineID or nil) })
    end
    return false
end

--- "Enchant Bracer - Lesser Stamina" reads "Bracer: Lesser Stamina".
function EnchantWindow.ShortName(name)
    if type(name) ~= "string" then return name end
    local rest = name:match("^Enchant%s+(.+)$")
    if not rest then return name end
    local slot, what = rest:match("^(.-)%s+%-%s+(.+)$")
    if slot and what then return slot .. ": " .. what end
    return rest
end

--- Is this recipe an enchant that goes on an item?
function EnchantWindow.IsEnchantRecipe(info, schematic)
    if type(schematic) == "table" and schematic.recipeType ~= nil then
        return schematic.recipeType == EnchantWindow.RECIPE_TYPE_ENCHANT
    end
    if type(info) == "table" and info.isEnchantingRecipe ~= nil then
        return info.isEnchantingRecipe == true
    end
    -- No type given: an Enchanting recipe that makes no item.
    return type(schematic) == "table" and not schematic.outputItemID
end

--- The materials of one recipe: { { itemID, need } }.
function EnchantWindow.Materials(schematic)
    local list = {}
    for _, slot in ipairs(type(schematic) == "table" and schematic.reagentSlotSchematics or {}) do
        local required = slot.reagentType == nil or slot.reagentType == 1
        local first = slot.reagents and slot.reagents[1]
        if required and first and first.itemID and (slot.quantityRequired or 0) > 0 then
            list[#list + 1] = { itemID = first.itemID, need = slot.quantityRequired }
        end
    end
    return list
end

--- Read the enchants a few a frame. `done(list)` hears when it is finished.
function EnchantWindow:ReadEnchants(done)
    if self.worker then self.worker:Cancel() end
    local ok, ids = Call("C_TradeSkillUI.GetAllRecipeIDs")
    if not ok or type(ids) ~= "table" then
        self.enchants = {}
        if done then done(self.enchants) end
        return
    end

    local found = {}
    self.generation = (self.generation or 0) + 1
    local generation = self.generation

    self.worker = Util.NewWorker({
        budgetMs = 4,
        onItem = function(recipeID, _, worker)
            if EnchantWindow.generation ~= generation then worker:Cancel() return end
            local okInfo, info = Call("C_TradeSkillUI.GetRecipeInfo", recipeID)
            if not okInfo or type(info) ~= "table" or info.learned == false then return end
            local okSchematic, schematic = Call("C_TradeSkillUI.GetRecipeSchematic", recipeID, false)
            if not okSchematic or type(schematic) ~= "table" then return end
            if not EnchantWindow.IsEnchantRecipe(info, schematic) then return end
            local name = info.name or schematic.name
            found[#found + 1] = {
                recipeID = recipeID,
                name = name,
                shown = EnchantWindow.ShortName(name),
                icon = info.icon,
                materials = EnchantWindow.Materials(schematic),
            }
        end,
        onDone = function()
            if EnchantWindow.generation ~= generation then return end
            table.sort(found, function(a, b) return tostring(a.shown) < tostring(b.shown) end)
            EnchantWindow.enchants = found
            EnchantWindow.worker = nil
            if done then done(found) end
        end,
    })
    self.worker:Start(ids)
end

function EnchantWindow:Find(recipeID)
    for _, enchant in ipairs(self.enchants or {}) do
        if enchant.recipeID == recipeID then return enchant end
    end
    return nil
end

--- The recipe picked in the game's window, read only, or nil.
function EnchantWindow:GamePick()
    local frame = _G.ProfessionsFrame
    local ok, recipeID = pcall(function()
        local form = frame and frame.CraftingPage and frame.CraftingPage.SchematicForm
        local info = form and form.GetRecipeInfo and form:GetRecipeInfo()
        if type(info) == "table" then return info.recipeID end
        return form and form.currentRecipeInfo and form.currentRecipeInfo.recipeID
    end)
    if ok and type(recipeID) == "number" then return recipeID end
    local okSel, selected = Call("C_TradeSkillUI.GetSelectedRecipeID")
    if okSel and type(selected) == "number" and selected > 0 then return selected end
    return nil
end

--- The enchant to start on: the game's pick, else the last one used.
function EnchantWindow:StartPick()
    local pick = self:GamePick()
    if pick and self:Find(pick) then return pick end
    local last = Settings() and Settings().enchantWindowLast
    if last and self:Find(last) then return last end
    local first = self.enchants and self.enchants[1]
    return first and first.recipeID or nil
end

function EnchantWindow:Remember(recipeID)
    local settings = Settings()
    if settings then settings.enchantWindowLast = recipeID end
end

--------------------------------------------------------------------------------
-- Items an enchant fits
--------------------------------------------------------------------------------

local function EquipSpot(link)
    if not link then return nil end
    if Util.HasFunction("C_Item.GetItemInfoInstant") then
        local ok, _, _, _, spot = pcall(C_Item.GetItemInfoInstant, link)
        if ok then return spot end
    end
    if type(GetItemInfoInstant) == "function" then
        local ok, _, _, _, spot = pcall(GetItemInfoInstant, link)
        if ok then return spot end
    end
    return nil
end
EnchantWindow.EquipSpot = EquipSpot

--- The equip spots a recipe fits, from its English name or Equipment's slot.
function EnchantWindow:SpotsFor(enchant)
    local name = enchant and enchant.name
    if type(name) == "string" then
        for _, entry in ipairs(self.SLOT_WORDS) do
            if name:find(entry[1], 1, true) then return entry[2] end
        end
    end
    local advice = self:Advice(enchant and enchant.recipeID)
    if advice and advice.slotID and self.SLOT_SPOTS[advice.slotID] then
        return self.SLOT_SPOTS[advice.slotID]
    end
    return nil
end

--- Equipment's word on a recipe for the gear worn: { slot, slotID, gain,
--- current, best }, or nil. Read through Upgrades, inside a pcall.
function EnchantWindow:Advice(recipeID)
    if not recipeID then return nil end
    local upgrades = ns.Upgrades
    if upgrades and type(upgrades.EnchantFor) == "function" then
        local ok, advice = pcall(upgrades.EnchantFor, upgrades, recipeID)
        if ok and type(advice) == "table" then return advice end
    end
    return nil
end

local function WornEntry(slot)
    if type(GetInventoryItemLink) ~= "function" then return nil end
    local ok, link = pcall(GetInventoryItemLink, "player", slot)
    if not ok or type(link) ~= "string" then return nil end
    return { worn = true, slot = slot, link = link, spot = EquipSpot(link) }
end

local function BagEntry(bag, slot)
    local ok, link = Call("C_Container.GetContainerItemLink", bag, slot)
    if not ok or type(link) ~= "string" then return nil end
    return { bag = bag, slot = slot, link = link, spot = EquipSpot(link) }
end

local function Key(entry)
    if entry.worn then return "w" .. entry.slot end
    return entry.bag .. ":" .. entry.slot
end
EnchantWindow.Key = Key

--- From the game's own list, when this client gives one.
function EnchantWindow:ItemsFromGame(recipeID)
    local ok, guids = Call("C_TradeSkillUI.GetEnchantItems", recipeID)
    if not ok or type(guids) ~= "table" or not Util.HasFunction("C_Item.GetItemLocation") then
        return nil
    end
    local list = {}
    for _, guid in ipairs(guids) do
        local okLoc, location = pcall(C_Item.GetItemLocation, guid)
        if okLoc and type(location) == "table" then
            local entry
            local okWorn, isWorn = pcall(function() return location:IsEquipmentSlot() end)
            if okWorn and isWorn then
                local okSlot, slot = pcall(function() return location:GetEquipmentSlot() end)
                entry = okSlot and WornEntry(slot)
            else
                local okBag, bag, slot = pcall(function() return location:GetBagAndSlot() end)
                entry = okBag and bag and BagEntry(bag, slot)
            end
            if entry then list[#list + 1] = entry end
        end
    end
    return list
end

--- Every item this enchant fits, worn first, then bags. Each entry:
--- { worn, slot, bag, link, spot, enchantID, current, gain }.
function EnchantWindow:Items(recipeID)
    local enchant = self:Find(recipeID)
    if not enchant then return {} end

    local list = self:ItemsFromGame(recipeID)
    if not list then
        list = {}
        local spots = self:SpotsFor(enchant)
        if spots then
            for _, slot in ipairs(self.WORN_SLOTS) do
                local entry = WornEntry(slot)
                if entry and spots[entry.spot] then list[#list + 1] = entry end
            end
            for _, bag in ipairs(ns.Inventory:GetCarriedBags()) do
                local okSlots, slots = Call("C_Container.GetContainerNumSlots", bag)
                if okSlots and type(slots) == "number" then
                    for slot = 1, slots do
                        local entry = BagEntry(bag, slot)
                        if entry and spots[entry.spot] then list[#list + 1] = entry end
                    end
                end
            end
        end
    end

    local advice = self:Advice(recipeID)
    for _, entry in ipairs(list) do
        entry.enchantID = self.EnchantID(entry.link)
        entry.current = self:CurrentEnchant(entry, advice)
        if entry.worn and advice and advice.slotID == entry.slot and (advice.gain or 0) > 0 then
            entry.gain = advice.gain
        end
    end

    table.sort(list, function(a, b)
        if (a.worn and true or false) ~= (b.worn and true or false) then return a.worn and true or false end
        return (a.gain or 0) > (b.gain or 0)
    end)
    return list
end

--- The item to start on: the piece Equipment says gains most, else the one
--- picked before when it still fits, else the first.
function EnchantWindow.StartItem(items, keep)
    if keep then
        for _, entry in ipairs(items) do
            if Key(entry) == keep then return entry end
        end
    end
    local best
    for _, entry in ipairs(items) do
        if (entry.gain or 0) > 0 and (not best or entry.gain > best.gain) then best = entry end
    end
    return best
end

--- The enchant ID in an item link, 0 for none.
function EnchantWindow.EnchantID(link)
    if type(link) ~= "string" then return 0 end
    local enchant = link:match("item:%-?%d+:(%-?%d*)")
    return tonumber(enchant) or 0
end

local enchantedPattern
local function EnchantedPattern()
    if enchantedPattern ~= nil then return enchantedPattern end
    local template = rawget(_G, "ENCHANTED_TOOLTIP_LINE")
    if type(template) ~= "string" then template = "Enchanted: %s" end
    local escaped = template:gsub("([%%%(%)%.%+%-%*%?%[%]%^%$])", "%%%1")
    enchantedPattern = "^" .. escaped:gsub("%%%%s", "(.+)") .. "$"
    return enchantedPattern
end
EnchantWindow.EnchantedPattern = EnchantedPattern

--- The name of what is on an item now, or nil when nothing is.
function EnchantWindow:CurrentEnchant(entry, advice)
    if (entry.enchantID or self.EnchantID(entry.link)) == 0 then return nil end
    local ok, data
    if entry.worn then
        ok, data = Call("C_TooltipInfo.GetInventoryItem", "player", entry.slot)
    else
        ok, data = Call("C_TooltipInfo.GetBagItem", entry.bag, entry.slot)
    end
    if ok and type(data) == "table" and type(data.lines) == "table" then
        local pattern = EnchantedPattern()
        for _, line in ipairs(data.lines) do
            local text = line.leftText
            if type(text) == "string" then
                local name = text:match(pattern)
                if name then return name end
            end
        end
    end
    if entry.worn and advice and advice.slotID == entry.slot and type(advice.current) == "string" then
        return advice.current
    end
    return L["An enchant"]
end

--- Does this slot still hold this item?
function EnchantWindow:StillThere(entry)
    if not entry then return false end
    local now = entry.worn and WornEntry(entry.slot) or BagEntry(entry.bag, entry.slot)
    return now ~= nil and now.link == entry.link
end

--------------------------------------------------------------------------------
-- Materials and cost
--------------------------------------------------------------------------------

--- { { itemID, need, have, short } }, how many casts the bags allow, the
--- first material short, and the cost of one cast in copper (nil if unknown).
function EnchantWindow:MaterialState(enchant)
    local rows, ready, short, cost = {}, math.huge, nil, 0
    for _, material in ipairs(enchant and enchant.materials or {}) do
        local have = ns.Inventory:GetBagCount(material.itemID) or 0
        local row = { itemID = material.itemID, need = material.need, have = have }
        row.short = math.max(0, material.need - have)
        if row.short > 0 and not short then short = row end
        ready = math.min(ready, math.floor(have / material.need))
        if cost then
            local okCost, copper = pcall(ns.Cost.GetReagentCost, ns.Cost, material.itemID, material.need)
            if okCost and type(copper) == "number" then cost = cost + copper else cost = nil end
        end
        rows[#rows + 1] = row
    end
    if #rows == 0 then ready, cost = 0, nil end
    return rows, ready, short, cost
end

--- Why the Enchant button can't go now, or nil when it can.
function EnchantWindow:Blocked(enchant, entry)
    if InCombat() then return L["Wait until the fight ends."] end
    if not entry then return L["Pick an item first."] end
    local _, _, short = self:MaterialState(enchant)
    if short then
        local name = Util.GetItemLabel(short.itemID, true) or ("item " .. short.itemID)
        return L.Format(L["You need %d more %s."], short.short, name)
    end
    return nil
end

--------------------------------------------------------------------------------
-- Casting
--------------------------------------------------------------------------------

local function Location(entry)
    if type(ItemLocation) ~= "table" then return nil end
    local ok, location
    if entry.worn then
        ok, location = pcall(ItemLocation.CreateFromEquipmentSlot, ItemLocation, entry.slot)
    else
        ok, location = pcall(ItemLocation.CreateFromBagAndSlot, ItemLocation, entry.bag, entry.slot)
    end
    return ok and location or nil
end

--- Is the game waiting for the player to pick the item?
function EnchantWindow.Targeting()
    if type(SpellIsTargeting) ~= "function" then return false end
    local ok, waiting = pcall(SpellIsTargeting)
    return ok and waiting and true or false
end

--- Is one of the game's own ask boxes up?
function EnchantWindow.Asking()
    if type(StaticPopup_Visible) ~= "function" then return false end
    for _, name in ipairs(EnchantWindow.ASK_BOXES) do
        local ok, shown = pcall(StaticPopup_Visible, name)
        if ok and shown then return true end
    end
    return false
end

--- The Enchant button's click, from the player's own click.
-- @return "cast" (one click went), "target" (Put It On next), or nil, why
function EnchantWindow:Cast(enchant, entry)
    local why = self:Blocked(enchant, entry)
    if why then return nil, why end
    if not self:StillThere(entry) then return nil, L["Pick an item first."] end

    self:Remember(enchant.recipeID)
    self.pending = { recipeID = enchant.recipeID, entry = entry, at = GetTime(), way = self:Way() }

    if self.pending.way == "one" then
        local location = Location(entry)
        local ok = location and pcall(C_TradeSkillUI.CraftEnchant, enchant.recipeID, 1, nil, location)
        if ok then
            self:WatchCast()
            return "cast"
        end
        self:Saw("one", "failed")
        self.pending.way = self:Way()
    end

    local ok = pcall(C_TradeSkillUI.CraftRecipe, enchant.recipeID, 1)
    if not ok then return nil, nil end
    self:WatchCast()
    return "target"
end

--- After a click: did the cast start, does it wait for an item, or did
--- nothing happen? Judged once, `JUDGE_AFTER` seconds on.
function EnchantWindow:WatchCast()
    local pending = self.pending
    if not pending or not C_Timer then return end
    C_Timer.After(self.JUDGE_AFTER, function()
        if EnchantWindow.pending ~= pending then return end
        if pending.casting then return end
        if EnchantWindow.Targeting() then
            if pending.way == "one" then EnchantWindow:Saw("one", "asks for the item") end
            if ns.EnchantWindowUI then ns.EnchantWindowUI:Update() end
            return
        end
        if EnchantWindow.Asking() then return end
        EnchantWindow:Saw(pending.way, "failed")
        EnchantWindow.pending = nil
        if ns.EnchantWindowUI then ns.EnchantWindowUI:Update() end
    end)
end

function EnchantWindow:OnSpellcast(event, unit, _, spellID)
    if unit ~= "player" then return end
    local pending = self.pending
    if not pending or spellID ~= pending.recipeID then return end
    if event == "UNIT_SPELLCAST_START" then
        pending.casting = true
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        self:Saw(pending.putOn and (pending.glow and "glow" or "two") or pending.way, "worked")
        self.pending = nil
    elseif event == "UNIT_SPELLCAST_FAILED" or event == "UNIT_SPELLCAST_INTERRUPTED" then
        self.pending = nil
    end
    if ns.EnchantWindowUI then ns.EnchantWindowUI:Update() end
end

--- The item a waiting spell should go on, for Put It On's macro, or nil.
function EnchantWindow:PutOnTarget()
    local pending = self.pending
    if not pending or not EnchantWindow.Targeting() or InCombat() then return nil end
    if not self:StillThere(pending.entry) then return nil end
    return pending.entry
end

--- The secure macro that puts a waiting spell on an item.
function EnchantWindow.PutOnMacro(entry)
    if not entry then return nil end
    if entry.worn then return "/use " .. entry.slot end
    return ("/use %d %d"):format(entry.bag, entry.slot)
end

function EnchantWindow:OnEnable()
    for _, event in ipairs({ "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_SUCCEEDED",
        "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_INTERRUPTED" }) do
        ns.RegisterEvent(self, event, self.OnSpellcast)
    end
end

--------------------------------------------------------------------------------
-- /bts enchant
--------------------------------------------------------------------------------

ns.RegisterCommand("enchant", L["turn the Enchant window on or off"], function(args)
    local word, way = tostring(args or ""):lower():match("^(%S*)%s*(%S*)")
    if word == "on" or word == "off" then
        EnchantWindow:SetOn(word == "on")
        ns.Print(word == "on" and L["Enchant window on."] or L["Enchant window off."])
    elseif word == "way" then
        local settings = Settings()
        if settings then
            settings.enchantWindowWay = (way == "one" or way == "two" or way == "glow") and way or nil
        end
        ns.Print("Enchant way: " .. EnchantWindow:Way())
    else
        for _, line in ipairs(EnchantWindow:ProbeLines()) do ns.Print(line[1] .. ": " .. line[2]) end
    end
end)

-- A one-time What's New card while the window is off (asked with the build,
-- 2026-11-05). Looked at once either way, so it never comes back.
ns.WHATS_NEW_TIPS = ns.WHATS_NEW_TIPS or {}
table.insert(ns.WHATS_NEW_TIPS, {
    key = "enchantWindow",
    title = L["Enchant Window"],
    icon = [[Interface\Icons\Trade_Engraving]],
    paragraphs = { L["Pick an item, then click Enchant. It sits under the recipe in your Enchanting window."] },
    button = L["Turn It On"],
    due = function() return not EnchantWindow:IsOn() end,
    run = function() EnchantWindow:SetOn(true) end,
})
