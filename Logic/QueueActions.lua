-- Blackthornes Tradeskills -- Logic/QueueActions.lua
-- What each queued craft is for once it is made: the auction house, a
-- disenchant or a vendor (Ezmode's request, 2026-10-07).
--
-- A queue row starts on whichever of the three pays most, the way the Profit
-- tab's Best works it out, and a click changes it. When the craft is made,
-- the items it made are marked with that action, per character and per item:
-- `queueMarks[characterKey][itemID] = { action, count }`. The Queue tab's
-- Disenchant next button and the vendor's Sell marked button only ever touch
-- marked items, so nothing the player looted, bought or wears is offered.
--
-- A mark never grows past what is carried. Whenever the bags change, each
-- mark is cut down to the number of that item left in the bags, so items that
-- went to the bank, the mail or the auction house take their marks with them,
-- and a copy picked up later is not marked.
--
-- Blue and better items are never offered, whatever they are marked. Nothing
-- here casts, sells or moves an item: that is the player's own click on a
-- secure button (UI/Disenchanter.lua, UI/SellMarked.lua).

local _, ns = ...

local QueueActions = ns.NewModule("QueueActions")

local Util = ns.Util

QueueActions.ORDER = { "auction", "disenchant", "vendor" }

QueueActions.SHORT = { auction = "AH", disenchant = "DE", vendor = "Vendor" }

QueueActions.LONG = {
    auction = "Sell on the auction house",
    disenchant = "Disenchant",
    vendor = "Sell to a vendor",
}

-- Greens and below. A blue or purple is never disenchanted or sold from here.
QueueActions.MAX_QUALITY = 2

-- The vendor's buyback keeps the last 12 things sold, so one visit sells no
-- more than that, and every sale can still be bought back.
QueueActions.SELL_PER_VISIT = 12

--------------------------------------------------------------------------------
-- Actions on queue entries
--------------------------------------------------------------------------------

local function OutputOf(entry)
    local recipe = entry and ns.Recipes:GetAny(entry.recipeID)
    return recipe and recipe.outputItemID or nil
end

--- Does this queue row get an action? Only crafts the player queued that
--- make an item: a sub-craft is used up in another craft, and an enchant
--- makes nothing to sell.
function QueueActions:Applies(entry)
    return entry ~= nil and not entry.isDependency and OutputOf(entry) ~= nil
end

local function Disenchantable(itemID)
    return ns.Disenchant and ns.Disenchant.IsDisenchantable
        and ns.Disenchant:IsDisenchantable(itemID) == true
end

--- The actions this craft can take, in ORDER, and the Best analysis.
-- Disenchanting is offered only for an item that can be disenchanted and,
-- when the Profit tab knows, by one of your characters. Vendor only for an
-- item a vendor buys.
function QueueActions:Choices(entry)
    local itemID = OutputOf(entry)
    if not itemID then return {}, nil end

    local analysis = ns.Profit:Analyse(entry.recipeID, nil, "best")
    local ways = analysis and analysis.ways

    local list = { "auction" }

    local de = ways and ways.disenchant
    if Disenchantable(itemID) and not (de and de.canDisenchant == false) then
        list[#list + 1] = "disenchant"
    end

    local vendor = ways and ways.vendor
    if vendor or not ways or next(ways) == nil then
        local price = Util.GetVendorSellPrice and Util.GetVendorSellPrice(itemID)
        if vendor or (price and price > 0) then list[#list + 1] = "vendor" end
    end

    return list, analysis
end

local function Contains(list, value)
    for _, item in ipairs(list) do
        if item == value then return true end
    end
    return false
end

--- What this craft will be marked when made.
-- @return action, chosen (true when picked by hand), choices, analysis
function QueueActions:Get(entry)
    if not self:Applies(entry) then return nil end

    local choices, analysis = self:Choices(entry)

    if entry.action and Contains(choices, entry.action) then
        return entry.action, true, choices, analysis
    end

    local best = analysis and analysis.via
    if best and Contains(choices, best) then return best, false, choices, analysis end
    return "auction", false, choices, analysis
end

--- Pick an action by hand. nil goes back to the best one.
function QueueActions:Set(entry, action)
    if not self:Applies(entry) then return false end
    entry.action = action
    ns.Queue:Notify()
    return true
end

--- The next action along, for a click on the row's button.
function QueueActions:Cycle(entry)
    local current, _, choices = self:Get(entry)
    if not current or #choices < 2 then return current end

    local index = 1
    for i, action in ipairs(choices) do
        if action == current then index = i end
    end

    local nextAction = choices[index % #choices + 1]
    self:Set(entry, nextAction)
    return nextAction
end

--------------------------------------------------------------------------------
-- Marks on made items
--------------------------------------------------------------------------------

local function SelfKey()
    return ns.Config.GetCharacterKey and ns.Config:GetCharacterKey() or nil
end

--- This character's marks, made when `create` is set.
function QueueActions:GetMarks(create)
    local key = SelfKey()
    if not key or not ns.db then return nil end

    local all = ns.db.queueMarks
    if type(all) ~= "table" then
        if not create then return nil end
        all = {}
        ns.db.queueMarks = all
    end

    local marks = all[key]
    if type(marks) ~= "table" then
        if not create then return nil end
        marks = {}
        all[key] = marks
    end
    return marks
end

local function Changed()
    if ns.UI and ns.UI.OnQueueMarksChanged then ns.UI:OnQueueMarksChanged() end
end

--- Items just made for a queue entry: mark them with its action.
--
-- An auction house craft is not marked; nothing here acts on those. A craft
-- marked one way and made again another way takes the new action for every
-- copy, since the copies cannot be told apart in the bags.
function QueueActions:NoteMade(entry, itemID, count)
    count = tonumber(count) or 0
    if not itemID or count <= 0 then return end

    local action = self:Get(entry)
    if action ~= "disenchant" and action ~= "vendor" then return end

    local marks = self:GetMarks(true)
    if not marks then return end

    local mark = marks[itemID]
    if mark and mark.action == action then
        mark.count = (tonumber(mark.count) or 0) + count
    else
        marks[itemID] = { action = action, count = count }
    end

    Changed()
end

--- Take the mark off an item.
function QueueActions:Unmark(itemID)
    local marks = self:GetMarks(false)
    if marks and marks[itemID] then
        marks[itemID] = nil
        Changed()
    end
end

--- Cut every mark down to what the bags hold now.
function QueueActions:Settle()
    local marks = self:GetMarks(false)
    if not marks then return end

    if ns.Inventory.InvalidateBagCounts then ns.Inventory:InvalidateBagCounts() end

    local changed = false
    for itemID, mark in pairs(marks) do
        local held = ns.Inventory:GetBagCount(itemID)
        local count = type(mark) == "table" and tonumber(mark.count) or nil

        if not count or held <= 0 then
            marks[itemID] = nil
            changed = true
        elseif count > held then
            mark.count = held
            changed = true
        end
    end

    if changed then Changed() end
end

--- An item's quality, or nil when the client has not said.
function QueueActions:Quality(itemID)
    if Util.HasFunction("C_Item.GetItemQualityByID") then
        local ok, quality = pcall(C_Item.GetItemQualityByID, itemID)
        if ok and type(quality) == "number" then return quality end
    end
    if Util.HasFunction("C_Item.GetItemInfo") then
        local ok, _, _, quality = pcall(C_Item.GetItemInfo, itemID)
        if ok and type(quality) == "number" then return quality end
    end
    return nil
end

--- Is this item one the buttons may act on? Green or below, known.
function QueueActions:SafeQuality(itemID)
    local quality = self:Quality(itemID)
    return quality ~= nil and quality <= self.MAX_QUALITY
end

-- A slot's stack size and whether it is locked (on the cursor, being cast
-- on, being sold), or nil when the client will not say.
local function SlotInfo(bag, slot)
    if not Util.HasFunction("C_Container.GetContainerItemInfo") then return 1, false end
    local ok, info = pcall(C_Container.GetContainerItemInfo, bag, slot)
    if not ok or type(info) ~= "table" then return nil end
    local count = tonumber(info.stackCount) or 1
    return count, info.isLocked == true
end

--- Marked items with this action that the buttons may act on, in item order.
-- @return list of { itemID, count }, total count
function QueueActions:List(action)
    local marks = self:GetMarks(false)
    local list, total = {}, 0
    if not marks then return list, total end

    for itemID, mark in pairs(marks) do
        local count = type(mark) == "table" and tonumber(mark.count) or 0
        if mark.action == action and count > 0 and self:SafeQuality(itemID) then
            list[#list + 1] = { itemID = itemID, count = count }
            total = total + count
        end
    end

    table.sort(list, function(a, b) return a.itemID < b.itemID end)
    return list, total
end

--- The carried bag slots holding marked items with this action, up to
--- `limit` slots. A stack bigger than what is still marked of that item is
--- left alone: selling it would sell copies the queue did not make.
-- @return list of { itemID, bag, slot, count }, total marked with this action
function QueueActions:Slots(action, limit)
    local list, total = self:List(action)
    local found = {}
    if #list == 0 or not Util.HasFunction("C_Container.GetContainerItemID") then return found, total end

    local wanted = {}
    for _, item in ipairs(list) do
        if action ~= "disenchant" or Disenchantable(item.itemID) then
            wanted[item.itemID] = item.count
        end
    end

    for _, item in ipairs(list) do
        for _, bag in ipairs(ns.Inventory:GetCarriedBags()) do
            local gotSlots, slots = pcall(C_Container.GetContainerNumSlots, bag)
            if gotSlots and type(slots) == "number" then
                for slot = 1, slots do
                    if limit and #found >= limit then return found, total end
                    local left = wanted[item.itemID]
                    local ok, id = pcall(C_Container.GetContainerItemID, bag, slot)
                    if left and left > 0 and ok and id == item.itemID then
                        local count, locked = SlotInfo(bag, slot)
                        if count and not locked and count <= left then
                            found[#found + 1] = { itemID = id, bag = bag, slot = slot, count = count }
                            wanted[id] = left - count
                        end
                    end
                end
            end
        end
    end

    return found, total
end

--- The next marked item to act on, and where it is.
-- @return itemID, bag, slot, total marked with this action; nil when none
function QueueActions:Next(action)
    local found, total = self:Slots(action, 1)
    local first = found[1]
    if first then return first.itemID, first.bag, first.slot, total, first.count end
    return nil, nil, nil, total
end

--- One marked item was used up by the player's click (cast or sold).
function QueueActions:Used(itemID, count)
    local marks = self:GetMarks(false)
    local mark = marks and marks[itemID]
    if not mark then return end

    mark.count = (tonumber(mark.count) or 0) - (tonumber(count) or 1)
    if mark.count <= 0 then marks[itemID] = nil end
    Changed()
end

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------

function QueueActions:OnEnable()
    -- One settle per burst of bag changes, a moment after the last.
    local pending = false
    ns.RegisterEvent(self, "BAG_UPDATE_DELAYED", function()
        if pending then return end
        pending = true
        C_Timer.After(0.3, function()
            pending = false
            QueueActions:Settle()
            -- Every time, not only when a mark changed: the next item to act
            -- on can move to another slot with the counts unchanged.
            Changed()
        end)
    end)

    ns.RegisterEvent(self, "PLAYER_ENTERING_WORLD", function()
        QueueActions:Settle()
    end)

    -- A Disenchant next click that finished casting uses up one mark, so a
    -- looted copy of the same item beside the crafted ones is never next.
    -- Compared inside a pcall: in an instance the spell can be a value the
    -- addon may not compare.
    -- Only the player's casts are wanted (ns.RegisterPlayerEvent).
    local RegisterForPlayer = ns.RegisterPlayerEvent or ns.RegisterEvent
    RegisterForPlayer(self, "UNIT_SPELLCAST_SUCCEEDED", function(_, _, unit, _, spellID)
        local pending = QueueActions.pendingDisenchant
        if not pending then return end

        local ok, ours = pcall(function()
            return unit == "player" and spellID == QueueActions.DISENCHANT_SPELL
        end)
        if not (ok and ours) then return end

        QueueActions.pendingDisenchant = nil
        if GetTime() - pending.at <= 15 then QueueActions:Used(pending.itemID, 1) end
    end)
end

QueueActions.DISENCHANT_SPELL = 13262

--- The Disenchant next button was clicked for this item.
function QueueActions:NoteDisenchantClick(itemID)
    self.pendingDisenchant = itemID and { itemID = itemID, at = GetTime() } or nil
end

--------------------------------------------------------------------------------
-- /bts marks
--------------------------------------------------------------------------------

ns.RegisterCommand("marks", "list the items your queue marked to disenchant or vendor", function()
    local any = false
    for _, action in ipairs({ "disenchant", "vendor" }) do
        local marks = QueueActions:GetMarks(false) or {}
        for itemID, mark in pairs(marks) do
            if type(mark) == "table" and mark.action == action then
                any = true
                local safe = QueueActions:SafeQuality(itemID)
                ns.Print(("%s: %dx %s%s"):format(QueueActions.LONG[action], tonumber(mark.count) or 0,
                    Util.GetItemLabel(itemID), safe and "" or " (blue or better, or not loaded yet: left alone)"))
            end
        end
    end
    if not any then ns.Print("nothing is marked. Crafts made from the queue on DE or Vendor are marked as they are made.") end
end)
