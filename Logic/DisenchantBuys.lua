-- Blackthornes Tradeskills -- Logic/DisenchantBuys.lua
-- Items bought on the auction house to disenchant (the owner asked,
-- 2026-10-11).
--
-- A buy is marked when it follows a search sent from the Disenchanting tab:
-- the tab's Search button or a right-click on one of its rows says what the
-- player means to buy (Intend), and an auction house purchase of that item
-- within INTENT_SECONDS is marked (AHBuys:Confirm calls OnBought). The player
-- can also mark or unmark any item by hand: a right-click on the tab's bags
-- list, or Butler's menu (Logic/Butler.lua, Butler:SetBoughtToDisenchant).
--
-- Marks are kept for the whole account, by item and count, in
-- `boughtToDisenchant[itemID] = { count, at }` (never rename it), because a
-- purchase lands in the mailbox and is often mailed to the enchanter or put
-- in the bank. Copies of an item cannot be told apart, so the mark is a
-- count, never a slot. It only ever shrinks:
--
--   * a disenchant of the item (DisenchantLog:Record calls Used), and
--   * the account holding fewer than are marked (Settle): every character's
--     bags, bank and mail, mail on its way to one of them, and auction buys
--     not yet taken from the mail. So an item sold, posted or worn takes its
--     mark with it, and one mailed or banked keeps it.
--
-- Settle runs once per burst of bag changes, a moment after the last, and
-- never while the mailbox is open: an item on the Send Mail page has left
-- the bags without being anywhere else yet. It looks only at marked items.
--
-- Nothing here casts or moves anything. Disenchanting is the player's own
-- click on a secure button (UI/Disenchanter.lua, or Butler's).

local _, ns = ...

local DisenchantBuys = ns.NewModule("DisenchantBuys")

local Util = ns.Util

-- How long after a search from the Disenchanting tab a purchase of that item
-- counts as bought to disenchant.
DisenchantBuys.INTENT_SECONDS = 15 * 60

-- Moves each time a mark changes, for anything that keeps an answer.
DisenchantBuys.version = 0

-- [itemID] = time() of the last search sent from the Disenchanting tab.
-- Not saved: a search is only meant for this visit to the auction house.
DisenchantBuys.intents = {}

local function Now()
    return type(time) == "function" and time() or 0
end

--------------------------------------------------------------------------------
-- Storage
--------------------------------------------------------------------------------

--- Every mark, account wide: { [itemID] = { count, at } }.
function DisenchantBuys:GetMarks(create)
    if not ns.db then return nil end
    local marks = ns.db.boughtToDisenchant
    if type(marks) ~= "table" then
        if not create then return nil end
        marks = {}
        ns.db.boughtToDisenchant = marks
    end
    return marks
end

local function Changed()
    DisenchantBuys.version = DisenchantBuys.version + 1
    if ns.UI and ns.UI.RefreshActiveTab then
        pcall(ns.UI.RefreshActiveTab, ns.UI)
    end
end

--- How many of an item are marked bought to disenchant, account wide.
function DisenchantBuys:Count(itemID)
    local marks = self:GetMarks(false)
    local mark = marks and itemID and marks[tonumber(itemID)]
    local count = type(mark) == "table" and tonumber(mark.count) or 0
    return count > 0 and count or 0
end

--- When the item was last marked, or nil.
function DisenchantBuys:MarkedAt(itemID)
    local marks = self:GetMarks(false)
    local mark = marks and itemID and marks[tonumber(itemID)]
    return type(mark) == "table" and tonumber(mark.at) or nil
end

--- Add `count` to an item's mark.
function DisenchantBuys:Add(itemID, count)
    itemID, count = tonumber(itemID), tonumber(count)
    if not itemID or not count or count <= 0 then return end
    local marks = self:GetMarks(true)
    if not marks then return end
    local mark = marks[itemID]
    if type(mark) ~= "table" then
        mark = { count = 0 }
        marks[itemID] = mark
    end
    mark.count = (tonumber(mark.count) or 0) + count
    mark.at = Now()
    Changed()
end

--- Mark at least `count` of an item (a right-click on the bags list: what
--- is carried). An item already marked for more keeps its count.
function DisenchantBuys:Mark(itemID, count)
    itemID, count = tonumber(itemID), tonumber(count)
    if not itemID or not count or count <= 0 then return end
    local have = self:Count(itemID)
    if have >= count then return end
    self:Add(itemID, count - have)
end

--- Take the mark off an item.
function DisenchantBuys:Unmark(itemID)
    local marks = self:GetMarks(false)
    itemID = tonumber(itemID)
    if marks and itemID and marks[itemID] ~= nil then
        marks[itemID] = nil
        Changed()
    end
end

--- One (or `count`) of a marked item was disenchanted.
function DisenchantBuys:Used(itemID, count)
    local marks = self:GetMarks(false)
    itemID = tonumber(itemID)
    local mark = marks and itemID and marks[itemID]
    if type(mark) ~= "table" then return end
    mark.count = (tonumber(mark.count) or 0) - (tonumber(count) or 1)
    if mark.count <= 0 then marks[itemID] = nil end
    Changed()
end

--- Marked items, by item ID: list of { itemID, count }.
function DisenchantBuys:List()
    local list = {}
    local marks = self:GetMarks(false)
    if not marks then return list end
    for itemID, mark in pairs(marks) do
        local count = type(mark) == "table" and tonumber(mark.count) or 0
        if type(itemID) == "number" and count > 0 then
            list[#list + 1] = { itemID = itemID, count = count }
        end
    end
    table.sort(list, function(a, b) return a.itemID < b.itemID end)
    return list
end

--------------------------------------------------------------------------------
-- Buying
--------------------------------------------------------------------------------

--- The Disenchanting tab sent a search for this item.
function DisenchantBuys:Intend(itemID)
    itemID = tonumber(itemID)
    if itemID then self.intents[itemID] = Now() end
end

--- Was a search for this item sent from the Disenchanting tab lately?
function DisenchantBuys:Intended(itemID)
    local at = itemID and self.intents[itemID]
    return at ~= nil and Now() - at <= self.INTENT_SECONDS
end

--- The auction house said a purchase went through (AHBuys:Confirm).
function DisenchantBuys:OnBought(itemID, quantity)
    itemID, quantity = tonumber(itemID), tonumber(quantity)
    if not itemID or not quantity or quantity <= 0 then return end
    if not self:Intended(itemID) then return end

    self:Add(itemID, quantity)
    ns.Print(("marked %d %s bought to disenchant. Right-click it on the Disenchanting tab to unmark it."):format(
        quantity, Util.GetItemLabel(itemID)))
end

--------------------------------------------------------------------------------
-- Keeping marks to what the account holds
--------------------------------------------------------------------------------

local function Number(value)
    return type(value) == "number" and value > 0 and value or 0
end

local function CountIn(counts, itemID)
    return type(counts) == "table" and Number(counts[itemID]) or 0
end

--- Auction buys of an item a character has not taken from the mail yet.
local function PendingIn(list, itemID)
    if type(list) ~= "table" then return 0 end
    local total = 0
    for _, buy in ipairs(list) do
        if type(buy) == "table" and buy.itemID == itemID then total = total + Number(buy.quantity) end
    end
    return total
end

--- How many of an item the whole account holds: the character playing's
--- bags and bank as the client says, every other character's as last seen,
--- everyone's mail, mail on its way to them and auction buys still in the
--- mail. Mail counts whatever "count mail as stock" says: a bought item
--- waiting there is still held.
function DisenchantBuys:Held(itemID)
    local inventory = ns.Inventory
    local total = 0
    if inventory then
        total = total + Number(inventory:GetBagCount(itemID)) + Number(inventory:GetBankCount(itemID))
    end

    local selfKey = ns.Config and ns.Config.GetCharacterKey and ns.Config:GetCharacterKey()
    local characters = ns.db and ns.db.characters
    local mail = ns.QueueMail

    for key, record in pairs(type(characters) == "table" and characters or {}) do
        if type(record) == "table" then
            if key ~= selfKey then
                total = total + CountIn(record.inventory, itemID) + CountIn(record.bank, itemID)
            end
            total = total + CountIn(record.mail, itemID) + PendingIn(record.ahBuys, itemID)
            if mail and mail.InFlight then
                local ok, coming = pcall(mail.InFlight, mail, key, itemID)
                if ok then total = total + Number(coming) end
            end
        end
    end
    return total
end

--- Cut every mark down to what the account holds now.
function DisenchantBuys:Settle()
    local marks = self:GetMarks(false)
    if not marks or next(marks) == nil then return end

    if ns.Inventory and ns.Inventory.InvalidateBagCounts then ns.Inventory:InvalidateBagCounts() end

    local changed = false
    for itemID, mark in pairs(marks) do
        local count = type(mark) == "table" and tonumber(mark.count) or nil
        if not count or count <= 0 or type(itemID) ~= "number" then
            marks[itemID] = nil
            changed = true
        else
            local held = self:Held(itemID)
            if held <= 0 then
                marks[itemID] = nil
                changed = true
            elseif count > held then
                mark.count = held
                changed = true
            end
        end
    end

    if changed then Changed() end
end

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------

function DisenchantBuys:OnEnable()
    local mailboxOpen = false
    local pending = false

    local function SettleSoon(delay)
        if pending then return end
        pending = true
        C_Timer.After(delay or 0.5, function()
            pending = false
            if not mailboxOpen then DisenchantBuys:Settle() end
        end)
    end

    -- One settle per burst of bag changes, a moment after the last.
    ns.RegisterEvent(self, "BAG_UPDATE_DELAYED", function()
        if mailboxOpen or not DisenchantBuys:GetMarks(false) then return end
        SettleSoon(0.5)
    end)

    local function Left()
        if not mailboxOpen then return end
        mailboxOpen = false
        -- After the mail sent here is written down as on its way.
        SettleSoon(1)
    end

    ns.RegisterEvent(self, "MAIL_SHOW", function() mailboxOpen = true end)
    ns.RegisterEvent(self, "MAIL_CLOSED", Left)
    -- Walking away from the mailbox, in case the client says only this.
    ns.RegisterEvent(self, "PLAYER_INTERACTION_MANAGER_FRAME_HIDE", function(_, _, kind)
        local types = rawget(_G, "Enum") and rawget(Enum, "PlayerInteractionType")
        local mailType = type(types) == "table" and rawget(types, "MailInfo") or 17
        if kind == mailType then Left() end
    end)
end
