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

-- The ordinary bag slots on the character portrait. A reagent bag, where the
-- client has one, sits past these and is found rather than assumed -- see
-- DetectReagentBag.
local LAST_NORMAL_BAG = tonumber(_G.NUM_BAG_SLOTS) or 4

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

--- The reagent bag's container index, or nil on a client without that slot.
--
-- A reagent bag is a sixth equipped container sitting past the four ordinary
-- ones, so a walk that stops at the fourth never sees inside it: reagents kept
-- where the game most encourages you to keep them read as reagents you do not
-- own.
--
-- Found rather than assumed, because the index is not the same everywhere. On
-- a client laid out the older way the first bank bag sits exactly where a
-- reagent bag would, and counting the bank as bags would say you can craft
-- things you cannot reach -- so the answer is bounded below the bank and
-- dropped when nothing confirms it.
local function DetectReagentBag()
    local index = Enum and Enum.BagIndex
        and (Enum.BagIndex.ReagentBag or Enum.BagIndex.Reagentbag)

    if type(index) ~= "number" then
        -- No enum to read. The client still says how many bag slots it equips
        -- altogether, and a total above the ordinary bags is that extra slot.
        local total = tonumber(_G.NUM_TOTAL_EQUIPPED_BAG_SLOTS)
        if total and total > LAST_NORMAL_BAG then
            index = LAST_NORMAL_BAG + 1
        end
    end

    if type(index) ~= "number" then return nil end
    if index <= LAST_NORMAL_BAG or index >= FIRST_BANK_BAG then return nil end

    return index
end

local carriedBags, reagentBagIndex

--- Every container the character is carrying, in order, backpack first.
--
-- One list so the bag walk, the snapshot and the sell list all agree on what
-- counts as "in your bags". They disagreed before, which is how a reagent bag
-- could be invisible to the count and to the seller at the same time.
function Inventory:GetCarriedBags()
    if carriedBags then return carriedBags end

    local bags = {}
    for bag = BACKPACK, LAST_NORMAL_BAG do
        bags[#bags + 1] = bag
    end

    reagentBagIndex = DetectReagentBag()
    if reagentBagIndex then bags[#bags + 1] = reagentBagIndex end

    carriedBags = bags
    return carriedBags
end

--- Which of the carried containers is the reagent bag, or nil if there is none.
function Inventory:GetReagentBag()
    self:GetCarriedBags()
    return reagentBagIndex
end

--- Re-read which containers the character carries.
--
-- The layout does not change while logged in, so this is only for enable time
-- and for the tests.
function Inventory:InvalidateBagLayout()
    carriedBags, reagentBagIndex = nil, nil
    self:InvalidateBagCounts()
end

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

    for _, bag in ipairs(Inventory:GetCarriedBags()) do
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

--- How many of an item sit in one container, and how big that container is.
--
-- The whole-bag walk folds every container into one number, which is exactly
-- the shape that let a missing container hide. This reports them apart so the
-- diagnostic can show its working.
-- @return count, slots
function Inventory:CountInBag(bag, itemID)
    local slotsOk, slots = pcall(C_Container.GetContainerNumSlots, bag)
    if not slotsOk or not slots then return 0, 0 end

    local total = 0

    for slot = 1, slots do
        local infoOk, info = pcall(C_Container.GetContainerItemInfo, bag, slot)
        if infoOk and info and info.itemID == itemID then
            total = total + (info.stackCount or 1)
        end
    end

    return total, slots
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

--- How many are waiting in the mailbox.
--
-- Asked through Mail so the "count mail as stock" setting is honoured in one
-- place, and so this still answers 0 before Mail has loaded.
function Inventory:GetMailCount(itemID)
    if not ns.Mail then return 0 end
    return ns.Mail:GetCount(itemID)
end

--- Bags plus bank and reagent bank.
function Inventory:GetTotalCount(itemID)
    return self:GetBagCount(itemID) + self:GetBankCount(itemID) + self:GetMailCount(itemID)
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

--- Everything this character owns: bags, bank and mailbox.
--
-- This is the right number for "do I need to buy this", because you already
-- own it. It is deliberately NOT the number used for "can I craft this right
-- now" -- the crafting UI cannot reach into the bank, let alone the mailbox.
--
-- The mailbox is in here because an auction that expires comes back as mail,
-- and an item halfway home is still an item you own. Leaving it out meant the
-- Profit tab recommended crafting replacements for things that had not
-- actually sold.
function Inventory:GetOwnedCount(itemID)
    return self:GetBagCount(itemID) + self:GetBankCount(itemID) + self:GetMailCount(itemID)
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

    for _, bag in ipairs(self:GetCarriedBags()) do
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
    self.bankOpen = true
    self:SnapshotBank()

    if ns.UI and ns.UI.OnInventoryUpdated then
        ns.UI:OnInventoryUpdated()
    end
end

function Inventory:OnBankClosed()
    self.bankOpen = false
    if self.bankTimer then
        self.bankTimer:Cancel()
        self.bankTimer = nil
    end
end

--- A bank slot changed. Only a bank window that is open now is worth reading.
--
-- On Forever these also fire with no banker in sight. They used to count as
-- opening the bank: the snapshot was retaken from a shut bank, which reads as
-- slots with nothing in them, and the time stamped on it said the bank had
-- been seen minutes ago when it had not been opened in days.
function Inventory:OnBankSlotsChanged()
    if not self.bankOpen then return end
    self:ReadBankSoon()
end

--- The bank changed while open: read it again once the burst is over.
--
-- Putting a stack of reagents away fires one of these a slot, and dragging
-- a few stacks fires dozens inside a frame or two. Each used to walk the
-- whole bank and redraw the open tab on its own; now they share one read,
-- a moment after the last of them, and the counts are stale for that long.
function Inventory:ReadBankSoon()
    self:InvalidateBagCounts()
    if self.bankTimer then return end
    self.bankTimer = C_Timer.NewTimer(0.3, function()
        Inventory.bankTimer = nil
        if Inventory.bankOpen then Inventory:OnBankOpened() end
    end)
end

--- Is this container one of the bank's?
local function IsBankContainer(bag)
    if type(bag) ~= "number" then return false end
    if bag == BANK_CONTAINER or bag == REAGENT_BANK then return true end
    return bag >= FIRST_BANK_BAG and bag <= LAST_BANK_BAG
end

Inventory.IsBankContainer = IsBankContainer

--- Bags changed, so the walk is stale.
--
-- Kept apart from OnBagUpdate because that one coalesces into a two-second
-- snapshot timer, and a stale count must not survive that long.
--
-- Taking something out of a purchased bank bag announces itself only as a
-- BAG_UPDATE for that bag: PLAYERBANKSLOTS_CHANGED covers the main bank
-- window and nothing else. The snapshot used to be taken when the bank
-- opened and never again, so twenty bolts moved from a bank bag to the
-- backpack stayed in the snapshot and were counted twice -- once in the bags
-- and once in a bank they had already left -- until the next visit. So a
-- bank container changing while the bank is open takes the snapshot again.
function Inventory:OnBagChanged(event, bag)
    self:InvalidateBagCounts()
    -- Counted, so a list built from the bags can tell nothing moved.
    self.changes = (self.changes or 0) + 1

    if event == "BAG_UPDATE" and self.bankOpen and IsBankContainer(bag) then
        self:ReadBankSoon()
    end
end

--------------------------------------------------------------------------------
-- Diagnostics
--------------------------------------------------------------------------------

ns.RegisterCommand("stock", "<name or link>: how many of an item you have, and where", function(args)
    local recipe, errorMessage, ambiguous = ns.Profit:Resolve(args)

    if ambiguous then
        ns.Print(("several recipes match '%s'. Try /bts why first"):format(args))
        return
    end

    if not recipe or not recipe.outputItemID then
        ns.Print(errorMessage or "type an item name, or shift-click an item")
        return
    end

    local itemID = recipe.outputItemID
    local inBags = Inventory:GetBagCount(itemID)
    local worn = Inventory:GetEquippedCount(itemID)
    local client = ClientCount(itemID, false)

    ns.Print(Util.GetItemLabel(itemID))
    ns.PrintRaw(("  in bags:          %d"):format(inBags))
    ns.PrintRaw(("  equipped:         %d"):format(worn))
    ns.PrintRaw(("  in bank:          %d"):format(Inventory:GetBankCount(itemID)))
    ns.PrintRaw(("  in mailbox:       %d%s"):format(
        Inventory:GetMailCount(itemID),
        ns.Config:Get("countMailAsStock") == false and "   (not counted)" or ""))
    ns.PrintRaw(("  counted as held:  %d"):format(Inventory:GetOwnedCount(itemID)))
    ns.PrintRaw(("  listed:           %d"):format(ns.Auctions:GetPostedCount(itemID)))

    -- Which containers were actually opened, and what each held. A bag missing
    -- from this list is a bag whose contents the addon does not believe you
    -- own, which is the failure this reports rather than reasons about.
    local reagentBag = Inventory:GetReagentBag()

    ns.PrintRaw("  bags checked:")

    for _, bag in ipairs(Inventory:GetCarriedBags()) do
        local count, slots = Inventory:CountInBag(bag, itemID)
        ns.PrintRaw(("    bag %d (%d slots):  %d%s"):format(bag, slots, count,
            bag == reagentBag and "   reagent bag" or ""))
    end

    if not reagentBag then
        ns.PrintRaw("    no reagent bag slot in this version of the game")
    end

    -- The line that settles the argument. A client count above the walked one
    -- used to mean equipment, which is why the walk exists at all; above the
    -- walk and the equipment together it means a container nobody opened, and
    -- that is a bug in the list above rather than in the client.
    if client then
        local note = ""

        if client > inBags + worn then
            note = "  <-- more than bags and equipment: a bag the addon is not checking"
        elseif client > inBags then
            note = "  <-- the game counts equipped items too"
        end

        ns.PrintRaw(("  the game's own count: %d%s"):format(client, note))
    else
        ns.PrintRaw("  the game's own count: not available")
    end
end)

function Inventory:OnEnable()
    self:InvalidateBagLayout()

    ns.RegisterEvent(self, "BAG_UPDATE", self.OnBagChanged)
    ns.RegisterEvent(self, "PLAYER_EQUIPMENT_CHANGED", self.OnBagChanged)
    ns.RegisterEvent(self, "BAG_UPDATE_DELAYED", self.OnBagUpdate)
    ns.RegisterEvent(self, "PLAYER_MONEY", self.OnBagUpdate)

    ns.RegisterEvent(self, "BANKFRAME_OPENED", self.OnBankOpened)
    ns.RegisterEvent(self, "BANKFRAME_CLOSED", self.OnBankClosed)
    ns.RegisterEvent(self, "PLAYERBANKSLOTS_CHANGED", self.OnBankSlotsChanged)
    ns.RegisterEvent(self, "PLAYERREAGENTBANKSLOTS_CHANGED", self.OnBankSlotsChanged)

    self:Snapshot()
end
