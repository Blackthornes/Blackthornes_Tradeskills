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

-- Worn equipment, the character's bag slots included. Nothing here is stock.
local FIRST_EQUIPPED_SLOT = 1
local LAST_EQUIPPED_SLOT = 23

-- How long a single walk of the bags may be reused. Bag updates clear it
-- outright; this is only so a missed event cannot leave a stale count standing
-- for long.
local BAG_CACHE_SECONDS = 0.5

--------------------------------------------------------------------------------
-- Live bag counts
--------------------------------------------------------------------------------

--- What the client says you are holding.
--
-- Useful as one half of a subtraction and not much else -- see GetBankCount.
-- The count is not simply "in your bags": a bag the character is wearing is
-- counted as one of that bag, which is the whole reason the walk below exists.
-- @return count, or nil when the client cannot answer
local function ClientCount(itemID, includeBank)
    if not itemID then return nil end
    if not Util.HasFunction("C_Item.GetItemCount") then return nil end

    local ok, count = pcall(C_Item.GetItemCount, itemID,
        includeBank and true or false, false, includeBank and true or false)

    if ok and count then return count end
    return nil
end

--- Everything in the bags, counted in one pass.
--
-- One walk answers for every item at once, which matters because the Profit tab
-- reads a count for every recipe it analyses -- asking per item would walk the
-- bags hundreds of times per redraw.
local function WalkBags()
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

    return counts
end

local bagCounts, bagCountsAt = nil, 0

--- Throw away the cached walk. Cheap, and safe to call on any bag event.
function Inventory:InvalidateBagCounts()
    bagCounts = nil
end

--- itemID -> how many are in the bags.
function Inventory:GetBagCounts()
    local now = GetTime and GetTime() or 0

    if bagCounts and (now - bagCountsAt) < BAG_CACHE_SECONDS then
        return bagCounts
    end

    bagCounts, bagCountsAt = WalkBags(), now
    return bagCounts
end

--- How many of an item are in bags right now.
--
-- Walked rather than asked for. `C_Item.GetItemCount` counts a bag the
-- character is wearing as one of that bag, so four Linen Bags being used as
-- bags read as four Linen Bags in stock, and the Profit tab stopped
-- recommending the recipe on the grounds that the shelf was already full. The
-- same goes for a crafted weapon you are carrying in your hand rather than to
-- market.
--
-- Equipped things are not stock, and the containers are the one place that
-- cannot be confused about which is which.
function Inventory:GetBagCount(itemID)
    if not itemID then return 0 end
    return self:GetBagCounts()[itemID] or 0
end

--- How many of an item the character is wearing, bags included.
--
-- Reported so the diagnostic can name it, and so nothing else has to guess at
-- the difference between a count that includes equipment and one that does not.
function Inventory:GetEquippedCount(itemID)
    if not itemID then return 0 end
    if not Util.HasFunction("GetInventoryItemID") then return 0 end

    local total = 0

    for slot = FIRST_EQUIPPED_SLOT, LAST_EQUIPPED_SLOT do
        local ok, equipped = pcall(GetInventoryItemID, "player", slot)
        if ok and equipped == itemID then total = total + 1 end
    end

    return total
end

--- Bags plus bank and reagent bank.
function Inventory:GetTotalCount(itemID)
    return self:GetBagCount(itemID) + self:GetBankCount(itemID)
end

--- How many are sitting in the bank.
--
-- The client's own count is preferred, but it can under-report when the bank
-- has not been opened this session, so a cached snapshot taken the last time
-- you visited a bank is used as a floor.
function Inventory:GetBankCount(itemID)
    -- Both halves come from the client, on purpose. Whatever it miscounts --
    -- worn bags, anything else -- appears in both and cancels, leaving the
    -- difference the bank made. Mixing the walked bag count in here instead
    -- would leave the equipment in the answer.
    local withBank = ClientCount(itemID, true)
    local withoutBank = ClientCount(itemID, false)

    local live = 0
    if withBank and withoutBank then
        live = math.max(0, withBank - withoutBank)
    end

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
    self:InvalidateBagCounts()

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

--- Bags changed, so the walk is stale.
--
-- Kept apart from OnBagUpdate because that one coalesces into a two-second
-- snapshot timer, and a stale count must not survive that long.
function Inventory:OnBagChanged()
    self:InvalidateBagCounts()
end

--------------------------------------------------------------------------------
-- Diagnostics
--------------------------------------------------------------------------------

ns.RegisterCommand("stock", "<name or link> -- where an item's count comes from", function(args)
    local recipe, errorMessage, ambiguous = ns.Profit:Resolve(args)

    if ambiguous then
        ns.Print(("several recipes match '%s' -- try /bts why first"):format(args))
        return
    end

    if not recipe or not recipe.outputItemID then
        ns.Print(errorMessage or "give me an item name or link")
        return
    end

    local itemID = recipe.outputItemID
    local inBags = Inventory:GetBagCount(itemID)
    local client = ClientCount(itemID, false)

    ns.Print(Util.GetItemLabel(itemID))
    ns.PrintRaw(("  in bags:          %d"):format(inBags))
    ns.PrintRaw(("  equipped:         %d"):format(Inventory:GetEquippedCount(itemID)))
    ns.PrintRaw(("  in bank:          %d"):format(Inventory:GetBankCount(itemID)))
    ns.PrintRaw(("  counted as held:  %d"):format(Inventory:GetOwnedCount(itemID)))
    ns.PrintRaw(("  listed:           %d"):format(ns.Auctions:GetPostedCount(itemID)))

    -- The line that settles the argument: a client count above the walked one
    -- is equipment being counted as stock, which is what this file now avoids.
    if client then
        ns.PrintRaw(("  client's own bag count: %d%s"):format(client,
            client > inBags and "  <-- it counts equipment" or ""))
    else
        ns.PrintRaw("  client's own bag count: cannot ask")
    end
end)

function Inventory:OnEnable()
    ns.RegisterEvent(self, "BAG_UPDATE", self.OnBagChanged)
    ns.RegisterEvent(self, "PLAYER_EQUIPMENT_CHANGED", self.OnBagChanged)
    ns.RegisterEvent(self, "BAG_UPDATE_DELAYED", self.OnBagUpdate)
    ns.RegisterEvent(self, "PLAYER_MONEY", self.OnBagUpdate)

    ns.RegisterEvent(self, "BANKFRAME_OPENED", self.OnBankOpened)
    ns.RegisterEvent(self, "PLAYERBANKSLOTS_CHANGED", self.OnBankOpened)
    ns.RegisterEvent(self, "PLAYERREAGENTBANKSLOTS_CHANGED", self.OnBankOpened)

    self:Snapshot()
end
