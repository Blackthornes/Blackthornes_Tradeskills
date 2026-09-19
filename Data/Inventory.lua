-- Blackthornes Tradeskills -- Data/Inventory.lua
-- What you actually hold, per character.
--
-- Counts from bags are live. Bank counts are only readable while the bank is
-- open, so they are cached and clearly labelled as a snapshot rather than
-- silently folded into "you have enough".

local _, ns = ...

local Inventory = ns.NewModule("Inventory")

local Util = ns.Util

local BACKPACK = 0
local LAST_BAG = 4

-- Bank containers. The main bank window is a single pseudo-bag, with the
-- purchased bank bags after it, and the reagent bank separate again.
local BANK_CONTAINER = (Enum and Enum.BagIndex and Enum.BagIndex.Bank) or -1
local REAGENT_BANK = (Enum and Enum.BagIndex and Enum.BagIndex.Reagentbank) or -3
local FIRST_BANK_BAG = (Enum and Enum.BagIndex and Enum.BagIndex.BankBag_1) or 6
local LAST_BANK_BAG = FIRST_BANK_BAG + 6

--------------------------------------------------------------------------------
-- Live bag counts
--------------------------------------------------------------------------------

--- How many of an item are in bags right now.
function Inventory:GetBagCount(itemID)
    -- C_Item.GetItemCount is the modern replacement for GetItemCount and is the
    -- cheapest correct answer for bags.
    if Util.HasFunction("C_Item.GetItemCount") then
        local ok, count = pcall(C_Item.GetItemCount, itemID, false, false, false)
        if ok and count then return count end
    end

    -- Fall back to walking the containers.
    local total = 0
    for bag = BACKPACK, LAST_BAG do
        local slotsOk, slots = pcall(C_Container.GetContainerNumSlots, bag)
        if slotsOk and slots then
            for slot = 1, slots do
                local infoOk, info = pcall(C_Container.GetContainerItemInfo, bag, slot)
                if infoOk and info and info.itemID == itemID then
                    total = total + (info.stackCount or 1)
                end
            end
        end
    end
    return total
end

--- Bags plus bank and reagent bank, as the client reports it.
function Inventory:GetTotalCount(itemID)
    if Util.HasFunction("C_Item.GetItemCount") then
        local ok, count = pcall(C_Item.GetItemCount, itemID, true, false, true)
        if ok and count then return count end
    end
    return self:GetBagCount(itemID)
end

--- How many are sitting in the bank.
--
-- The client's own count is preferred, but it can under-report when the bank
-- has not been opened this session, so a cached snapshot taken the last time
-- you visited a bank is used as a floor.
function Inventory:GetBankCount(itemID)
    local live = math.max(0, self:GetTotalCount(itemID) - self:GetBagCount(itemID))

    local record = ns.Recipes:GetCharacterRecord(false)
    local cached = record and record.bank and record.bank[itemID] or 0

    return math.max(live, cached)
end

--- Everything this character owns: bags plus bank.
--
-- This is the right number for "do I need to buy this", because you already
-- own it. It is deliberately NOT the number used for "can I craft this right
-- now" -- the crafting UI cannot reach into the bank.
function Inventory:GetOwnedCount(itemID)
    return self:GetBagCount(itemID) + self:GetBankCount(itemID)
end

--------------------------------------------------------------------------------
-- Cached snapshot
--------------------------------------------------------------------------------

local function GetRecord(create)
    return ns.Recipes:GetCharacterRecord(create)
end

--- Store a full count of everything in bags, so alts can be consulted later.
function Inventory:Snapshot()
    local record = GetRecord(true)
    if not record then return end

    local counts = {}

    for bag = BACKPACK, LAST_BAG do
        local slotsOk, slots = pcall(C_Container.GetContainerNumSlots, bag)
        if slotsOk and slots then
            for slot = 1, slots do
                local infoOk, info = pcall(C_Container.GetContainerItemInfo, bag, slot)
                if infoOk and info and info.itemID then
                    counts[info.itemID] = (counts[info.itemID] or 0) + (info.stackCount or 1)
                end
            end
        end
    end

    record.inventory = counts
    record.inventoryAt = time()

    local ok, money = pcall(GetMoney)
    if ok then record.gold = money end

    return counts
end

--- Record bank contents. Only possible while the bank window is open, so this
--- is cached and reused afterwards rather than re-read on demand.
function Inventory:SnapshotBank()
    local record = GetRecord(true)
    if not record then return end

    local counts = {}

    local containers = { BANK_CONTAINER, REAGENT_BANK }
    for bag = FIRST_BANK_BAG, LAST_BANK_BAG do
        containers[#containers + 1] = bag
    end

    local sawAnything = false

    for _, bag in ipairs(containers) do
        local slotsOk, slots = pcall(C_Container.GetContainerNumSlots, bag)

        if slotsOk and slots and slots > 0 then
            sawAnything = true

            for slot = 1, slots do
                local infoOk, info = pcall(C_Container.GetContainerItemInfo, bag, slot)
                if infoOk and info and info.itemID then
                    counts[info.itemID] = (counts[info.itemID] or 0) + (info.stackCount or 1)
                end
            end
        end
    end

    -- Only overwrite when the bank was genuinely readable. Otherwise an empty
    -- read would wipe a good snapshot and silently tell you to buy things you
    -- already own.
    if sawAnything then
        record.bank = counts
        record.bankAt = time()

        -- Distinct from bankAt, which persists: this tracks whether the bank
        -- has been opened since logging in. A snapshot from last week is better
        -- than nothing, but the player should know it is not current.
        self.readThisSession = true
    end

    return counts
end

--- Has the bank been opened since this session started?
function Inventory:HasReadBankThisSession()
    return self.readThisSession == true
end

--- When the cached bank snapshot was taken, or nil if never.
function Inventory:GetBankAge()
    local record = ns.Recipes:GetCharacterRecord(false)
    if not record or not record.bankAt then return nil end
    return time() - record.bankAt
end

--- What a specific character carries in their bags.
--
-- Live for the logged-in character; the cached snapshot for anyone else, which
-- is only as fresh as the last time they logged out.
function Inventory:GetCharacterBagCount(characterKey, itemID)
    if not characterKey or characterKey == ns.Config:GetCharacterKey() then
        return self:GetBagCount(itemID)
    end

    local record = ns.db and ns.db.characters[characterKey]
    if not record then return 0 end

    return (record.inventory and record.inventory[itemID]) or 0
end

--- Cached counts held by other characters, as { characterKey = count }.
-- Never merged into the local count: "you have 40, but 30 are on an alt" is a
-- materially different situation from "you have 40".
function Inventory:GetAltCounts(itemID)
    local results = {}
    if not ns.db then return results end

    local selfKey = ns.Config:GetCharacterKey()

    for characterKey, record in pairs(ns.db.characters) do
        if characterKey ~= selfKey then
            local count = record.inventory and record.inventory[itemID]
            if count and count > 0 then
                results[characterKey] = count
            end
        end
    end

    return results
end

function Inventory:GetAltTotal(itemID)
    local total = 0
    for _, count in pairs(self:GetAltCounts(itemID)) do
        total = total + count
    end
    return total
end

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------

function Inventory:OnBagUpdate()
    -- Bag events fire in bursts while looting or moving stacks; coalesce them.
    if self.snapshotTimer then return end

    self.snapshotTimer = C_Timer.NewTimer(2, function()
        Inventory.snapshotTimer = nil
        Inventory:Snapshot()

        if ns.UI and ns.UI.OnInventoryUpdated then
            ns.UI:OnInventoryUpdated()
        end
    end)
end

function Inventory:OnBankOpened()
    self:SnapshotBank()

    if ns.UI and ns.UI.OnInventoryUpdated then
        ns.UI:OnInventoryUpdated()
    end
end

function Inventory:OnEnable()
    ns.RegisterEvent(self, "BAG_UPDATE_DELAYED", self.OnBagUpdate)
    ns.RegisterEvent(self, "PLAYER_MONEY", self.OnBagUpdate)

    ns.RegisterEvent(self, "BANKFRAME_OPENED", self.OnBankOpened)
    ns.RegisterEvent(self, "PLAYERBANKSLOTS_CHANGED", self.OnBankOpened)
    ns.RegisterEvent(self, "PLAYERREAGENTBANKSLOTS_CHANGED", self.OnBankOpened)

    self:Snapshot()
end
