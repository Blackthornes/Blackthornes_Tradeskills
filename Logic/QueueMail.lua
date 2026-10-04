-- Blackthornes Tradeskills -- Logic/QueueMail.lua
-- What to mail to your other characters for the shared craft queue.
--
-- The queue gives each craft to a character (Logic/Queue.lua, "Who makes
-- what"). The tailor makes the bolts for Ana's bag, so the tailor needs
-- the wool, and Ana needs the bolts once they are made. At a mailbox this
-- works out what the character logged in holds that another one needs, and
-- UI/QueueMailPanel.lua offers to fill a mail with it.
--
-- Nothing is ever sent from here. The panel fills in the name and the
-- attachments, and the player presses Send: postage costs money, and a mail
-- cannot be taken back once sent.
--
-- What has been mailed is written down (`BlackthornesTSDB.queueMail.sent`),
-- because the other character's bags are only known as they were when it
-- last logged out. Without it, every visit to the mailbox would offer the
-- same wool again until the tailor logged in.
--
-- Crafts made for someone else are written down too (`queueMail.owed`): a
-- craft you queued that only an alt can make is taken off the queue as the
-- alt makes it, and the record is what says the result still has to go back.

local _, ns = ...

local QueueMail = ns.NewModule("QueueMail")

-- How many items one mail carries. The client's own number where it has one.
local function MaxAttachments()
    local max = tonumber(_G.ATTACHMENTS_MAX_SEND)
    if max and max > 0 then return max end
    return 12
end
QueueMail.MaxAttachments = MaxAttachments

-- A mail between characters can take an hour to arrive. Until the one it
-- went to has looked in its mailbox after that, what was sent counts as
-- theirs, on its way.
local DELIVERY_WAIT = 3600

-- Records of what was sent are let go after this, whatever happened.
local KEEP_SENT = 3 * 24 * 3600

--------------------------------------------------------------------------------
-- Storage
--------------------------------------------------------------------------------

local function Store()
    if not ns.db then return nil end
    local store = ns.db.queueMail
    if type(store) ~= "table" then
        store = {}
        ns.db.queueMail = store
    end
    if type(store.sent) ~= "table" then store.sent = {} end
    if type(store.owed) ~= "table" then store.owed = {} end
    return store
end

local function SelfKey()
    return ns.Config:GetCharacterKey()
end

local function CharacterRecord(characterKey)
    local record = ns.db and ns.db.characters and ns.db.characters[characterKey]
    if type(record) == "table" then return record end
end

local function Now()
    return (type(time) == "function" and time()) or 0
end

--- Is a record of something sent to this character still on its way?
local function StillComing(sent, record)
    if Now() - (sent.at or 0) > KEEP_SENT then return false end
    local mailAt = record and record.mailAt
    if mailAt and mailAt > (sent.at or 0) + DELIVERY_WAIT then return false end
    return true
end

--- How many of an item have been mailed to a character and not yet seen
--- arrive. Logic/Queue.lua counts these as the character's own.
function QueueMail:InFlight(characterKey, itemID)
    local store = Store()
    local list = store and store.sent[characterKey]
    if type(list) ~= "table" then return 0 end

    local record = CharacterRecord(characterKey)
    local total = 0
    for _, sent in ipairs(list) do
        if sent.itemID == itemID and StillComing(sent, record) then
            total = total + (sent.count or 0)
        end
    end
    return total
end

--- Forget what has arrived or is too old to matter.
function QueueMail:Prune()
    local store = Store()
    if not store then return end

    for characterKey, list in pairs(store.sent) do
        if type(list) == "table" then
            local record = CharacterRecord(characterKey)
            local kept = {}
            for _, sent in ipairs(list) do
                if type(sent) == "table" and StillComing(sent, record) then
                    kept[#kept + 1] = sent
                end
            end
            store.sent[characterKey] = #kept > 0 and kept or nil
        end
    end
end

--- A craft was made for another character. Logic/Crafting.lua calls this.
function QueueMail:NoteMadeFor(toKey, itemID, count)
    local store = Store()
    if not (store and toKey and itemID and count and count > 0) then return end

    local fromKey = SelfKey()
    if toKey == fromKey then return end

    local mine = store.owed[fromKey] or {}
    store.owed[fromKey] = mine
    local theirs = mine[toKey] or {}
    mine[toKey] = theirs
    theirs[itemID] = (theirs[itemID] or 0) + count
end

--- What this character still owes another: { [itemID] = count }.
function QueueMail:GetOwed(toKey)
    local store = Store()
    local mine = store and store.owed[SelfKey()]
    return (mine and mine[toKey]) or {}
end

--- Mail went out. Writes down what it carried, and takes it off what was owed.
-- @param items list of { itemID, count }
function QueueMail:NoteSent(toKey, items)
    local store = Store()
    if not (store and toKey) then return end

    local list = store.sent[toKey] or {}
    store.sent[toKey] = list

    local owed = self:GetOwed(toKey)
    local at = Now()

    for _, item in ipairs(items or {}) do
        if item.itemID and (item.count or 0) > 0 then
            list[#list + 1] = { itemID = item.itemID, count = item.count, at = at, from = SelfKey() }

            if owed[item.itemID] then
                local left = owed[item.itemID] - item.count
                owed[item.itemID] = left > 0 and left or nil
            end
        end
    end
end

--------------------------------------------------------------------------------
-- What to send
--------------------------------------------------------------------------------

--- The materials each character's queued crafts use, and what each makes.
-- @return uses { [key] = { [itemID] = units } }, makes { [key] = { [itemID] = units } }
function QueueMail:GetPlan()
    local uses, makes = {}, {}
    local Queue = ns.Queue

    for _, entry in ipairs(Queue:GetAll()) do
        local recipe = ns.Recipes:GetAny(entry.recipeID)
        if recipe then
            local crafter = Queue:GetCrafter(entry)

            local used = uses[crafter] or {}
            uses[crafter] = used
            for _, reagent in ipairs(recipe.reagents or {}) do
                used[reagent.itemID] = (used[reagent.itemID] or 0) + reagent.quantity * entry.quantity
            end

            if entry.isDependency and recipe.outputItemID then
                local made = makes[crafter] or {}
                makes[crafter] = made
                made[recipe.outputItemID] = (made[recipe.outputItemID] or 0)
                    + entry.quantity * math.max(1, recipe.quantityMin or 1)
            end
        end
    end

    return uses, makes
end

local function Bound(itemID)
    return ns.Util and ns.Util.IsBoundOnPickup and ns.Util.IsBoundOnPickup(itemID) == true
end

--- What the character logged in can send to whom, right now.
--
-- For each other character the queue gives crafts to: what those crafts
-- use, less what that character makes itself, holds, or has on its way.
-- Then the crafts made here for them that are still owed. Each is limited
-- to what is in these bags (only the bags can go in a mail) beyond what
-- this character's own crafts use.
--
-- @return list of { to = key, name, items = { { itemID, count, made } } },
--   by name, items by item
function QueueMail:GetDeliveries()
    local deliveries = {}
    local Queue = ns.Queue
    if not (ns.db and Queue and Queue.SharesWithAlts and Queue:SharesWithAlts()) then
        return deliveries
    end

    local selfKey = SelfKey()
    local uses, makes = self:GetPlan()
    local myUse, myMake = uses[selfKey] or {}, makes[selfKey] or {}

    -- What these bags can spare, item by item, worked out as it is asked for.
    local spare = {}
    local function Spare(itemID)
        if spare[itemID] == nil then
            local bags = ns.Inventory:GetBagCount(itemID)
            -- Your own crafts come first, and use the bank before the bags.
            local own = math.max(0, (myUse[itemID] or 0) - (myMake[itemID] or 0)
                - ns.Inventory:GetBankCount(itemID))
            spare[itemID] = math.max(0, bags - own)
        end
        return spare[itemID]
    end

    local byKey = {}
    local function Give(toKey, itemID, count, made)
        if count <= 0 or Bound(itemID) then return end
        local give = math.min(count, Spare(itemID))
        if give <= 0 then return end
        spare[itemID] = spare[itemID] - give

        local delivery = byKey[toKey]
        if not delivery then
            delivery = { to = toKey, name = ns.Recipes:GetCharacterName(toKey), items = {} }
            byKey[toKey] = delivery
            deliveries[#deliveries + 1] = delivery
        end

        for _, item in ipairs(delivery.items) do
            if item.itemID == itemID then
                item.count = item.count + give
                item.made = item.made or made
                return
            end
        end
        delivery.items[#delivery.items + 1] = { itemID = itemID, count = give, made = made }
    end

    local others = {}
    for characterKey in pairs(uses) do
        if characterKey ~= selfKey and Queue:CanMail(selfKey, characterKey) then
            others[#others + 1] = characterKey
        end
    end
    table.sort(others)

    for _, toKey in ipairs(others) do
        local theirMake = makes[toKey] or {}
        local items = {}
        for itemID in pairs(uses[toKey]) do items[#items + 1] = itemID end
        table.sort(items)

        for _, itemID in ipairs(items) do
            local left = uses[toKey][itemID] - (theirMake[itemID] or 0)
                - Queue:HeldBy(toKey, itemID)
            Give(toKey, itemID, left, (myMake[itemID] or 0) > 0)
        end
    end

    -- Finished crafts for whoever queued them.
    local store = Store()
    local owedByMe = store and store.owed[selfKey] or {}
    local owedTo = {}
    for toKey in pairs(owedByMe) do
        if toKey ~= selfKey and Queue:CanMail(selfKey, toKey) then owedTo[#owedTo + 1] = toKey end
    end
    table.sort(owedTo)

    for _, toKey in ipairs(owedTo) do
        local items = {}
        for itemID in pairs(owedByMe[toKey]) do items[#items + 1] = itemID end
        table.sort(items)
        for _, itemID in ipairs(items) do
            Give(toKey, itemID, owedByMe[toKey][itemID], true)
        end
    end

    table.sort(deliveries, function(a, b)
        if a.name ~= b.name then return a.name < b.name end
        return a.to < b.to
    end)

    return deliveries
end

--------------------------------------------------------------------------------
-- Gear for the disenchanter
--------------------------------------------------------------------------------

-- Izbode, 2026-10-04: "Setting a disenchant character to mail all BoEs to
-- (with threshold option, like only greens, or maybe only green and blues)".
-- The name is typed in Settings, so it can be any character, one on another
-- account included. What goes: green and better armour and weapons that can
-- be disenchanted, up to the quality picked, never a soulbound copy, never
-- gear that binds when picked up, and never an upgrade for the character
-- carrying it (when Equipment is loaded to say so). Like the queue's mail,
-- nothing is sent from here: the panel fills the mail and the player
-- presses Send.

local GREEN, PURPLE = 2, 4

--- A name for comparing: lower case, spaces between words kept single.
local function Fold(text)
    if type(text) ~= "string" then return nil end
    text = text:gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s+", " ")
    if text == "" then return nil end
    return text:lower()
end

--- A plain string from the client, or nil: read in a pcall and copied, since
--- the client can hand out values that raise when touched.
local function ClientString(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, value = pcall(fn, ...)
    if not ok or type(value) ~= "string" then return nil end
    local copied, text = pcall(function() return value .. "" end)
    return copied and text or nil
end

--- Is the typed name the character playing? Trent (2026-10-04): the
--- disenchanter is never offered gear to mail to itself. Matched without
--- regard to case, by first name or by first and last name (Forever's
--- characters have both), with or without the realm. The name is read from
--- the game, falling back to the saved record, so a record not yet stamped
--- this session still counts.
local function IsCharacterPlaying(typed)
    local name, realm = typed:match("^(.-)%-([^%-]+)$")
    name = Fold(name or typed)
    if not name then return false end

    local record = CharacterRecord(SelfKey()) or {}
    local first = Fold(ClientString(UnitName, "player")) or Fold(record.name)
    if not first then return false end

    local surname = Fold(record.surname)
    if not surname and ns.Config.ReadSurname then
        local ok, found = pcall(ns.Config.ReadSurname, ns.Config)
        surname = ok and Fold(found) or nil
    end

    if name ~= first and not (surname and name == first .. " " .. surname) then
        return false
    end

    -- A realm that is not this one is somebody else of the same name.
    local here = ClientString(GetRealmName) or record.realm
    if realm and type(here) == "string" then
        return realm:gsub("%s", ""):lower() == here:gsub("%s", ""):lower()
    end
    return true
end

--- The disenchanter's name as typed, trimmed, or nil when there is none
--- (or it is the character playing).
function QueueMail:GetDisenchanter()
    local typed = ns.Config:Get("disenchanterName")
    if type(typed) ~= "string" then return nil end
    typed = typed:gsub("^%s+", ""):gsub("%s+$", "")
    if typed == "" then return nil end

    if IsCharacterPlaying(typed) then return nil end
    return typed
end

--- The best quality mailed to the disenchanter: 2 to 4.
function QueueMail:GetDisenchantQuality()
    local quality = tonumber(ns.Config:Get("disenchanterQuality")) or GREEN
    return math.max(GREEN, math.min(PURPLE, math.floor(quality)))
end

--- Is this copy an upgrade for the character carrying it? Asked of
--- Equipment directly, whether or not the arrows are switched on: the
--- answer here decides what leaves the bags.
local function UpgradeForMe(itemID, link)
    local compare = ns.Upgrades and ns.Upgrades.Equipment and ns.Upgrades:Equipment()
    if not compare then return false end
    local ok, result = pcall(compare.IsUpgrade, compare, link or itemID)
    return ok and result == true
end

--- What the bags hold for the disenchanter, as a delivery the panel can
--- draw and Fill can attach, or nil when there is nobody or nothing.
-- @return { to, name, recipient, subject, disenchant = true,
--   items = { { itemID, count, quality } } }
function QueueMail:GetDisenchantDelivery()
    local recipient = self:GetDisenchanter()
    if not recipient then return nil end

    local Disenchant = ns.Disenchant
    if not (Disenchant and Disenchant.IsDisenchantable) then return nil end
    if not (C_Container and ns.Inventory and ns.Inventory.GetCarriedBags) then return nil end

    local best = self:GetDisenchantQuality()
    local counts, order, qualities, refused = {}, {}, {}, {}

    -- Read and copied inside a pcall: the client can hand out values that
    -- raise when compared.
    local function Read(bag, slot)
        local info = C_Container.GetContainerItemInfo(bag, slot)
        if type(info) ~= "table" or info.isBound then return nil end
        local itemID, quality = tonumber(info.itemID), tonumber(info.quality)
        local link = type(info.hyperlink) == "string" and (info.hyperlink .. "") or nil
        return itemID, quality, tonumber(info.stackCount) or 1, link
    end

    for _, bag in ipairs(ns.Inventory:GetCarriedBags()) do
        local okSlots, slots = pcall(C_Container.GetContainerNumSlots, bag)
        for slot = 1, (okSlots and tonumber(slots)) or 0 do
            local ok, itemID, quality, stack, link = pcall(Read, bag, slot)

            if ok and itemID and quality and quality >= GREEN and quality <= best
                and not refused[itemID] then
                -- One copy an upgrade keeps them all: the mail is filled by
                -- item, and could take that copy rather than another.
                if Disenchant:IsDisenchantable(itemID) ~= true or Bound(itemID)
                    or UpgradeForMe(itemID, link) then
                    refused[itemID] = true
                else
                    if not counts[itemID] then
                        order[#order + 1] = itemID
                        qualities[itemID] = quality
                    end
                    counts[itemID] = (counts[itemID] or 0) + stack
                end
            end
        end
    end

    local kept = {}
    for _, itemID in ipairs(order) do
        if not refused[itemID] then kept[#kept + 1] = itemID end
    end
    order = kept
    if #order == 0 then return nil end

    -- Best quality first.
    table.sort(order, function(a, b)
        if qualities[a] ~= qualities[b] then return qualities[a] > qualities[b] end
        return a < b
    end)

    local items = {}
    for _, itemID in ipairs(order) do
        items[#items + 1] = { itemID = itemID, count = counts[itemID], quality = qualities[itemID] }
    end

    return {
        to = self:FindCharacter(recipient),
        name = recipient,
        recipient = recipient,
        subject = "Gear to disenchant",
        disenchant = true,
        items = items,
    }
end

--------------------------------------------------------------------------------
-- Filling a mail
--------------------------------------------------------------------------------

-- Seconds between one attachment and the next. A split stack is locked until
-- the game has moved it, and the next pick-up from the bags waits for that.
local ATTACH_STEP = 0.2

local function Call(fn, ...)
    if type(fn) ~= "function" then return false end
    return pcall(fn, ...)
end

--- Which mail slots already hold something.
local function UsedSlots()
    local used, count = {}, 0
    for slot = 1, MaxAttachments() do
        local ok, name = Call(_G.GetSendMailItem, slot)
        if ok and name ~= nil then
            used[slot] = true
            count = count + 1
        end
    end
    return used, count
end

local function FreeSlot()
    local used = UsedSlots()
    for slot = 1, MaxAttachments() do
        if not used[slot] then return slot end
    end
end

--- The bag stacks to take for `count` of an item: whole stacks first, the
--- biggest first, and one split for the rest.
-- @return list of { bag, slot, count, split }
function QueueMail:PlanStacks(itemID, count, taken)
    local stacks = {}
    local bags = ns.Inventory.GetCarriedBags and ns.Inventory:GetCarriedBags() or {}

    for _, bag in ipairs(bags) do
        local okSlots, slots = Call(C_Container and C_Container.GetContainerNumSlots, bag)
        for slot = 1, (okSlots and tonumber(slots)) or 0 do
            local ok, info = Call(C_Container.GetContainerItemInfo, bag, slot)
            local key = bag .. ":" .. slot
            if ok and type(info) == "table" and info.itemID == itemID
                and not info.isBound and not info.isLocked and not taken[key] then
                stacks[#stacks + 1] = { bag = bag, slot = slot, size = info.stackCount or 1, key = key }
            end
        end
    end

    table.sort(stacks, function(a, b)
        if a.size ~= b.size then return a.size > b.size end
        if a.bag ~= b.bag then return a.bag < b.bag end
        return a.slot < b.slot
    end)

    local steps, left = {}, count
    -- Whole stacks that fit, then one split from a stack bigger than what is left.
    for _, stack in ipairs(stacks) do
        if left <= 0 then break end
        if stack.size <= left then
            steps[#steps + 1] = { bag = stack.bag, slot = stack.slot, count = stack.size }
            taken[stack.key] = true
            left = left - stack.size
        end
    end
    if left > 0 then
        for index = #stacks, 1, -1 do
            local stack = stacks[index]
            if not taken[stack.key] and stack.size > left then
                steps[#steps + 1] = { bag = stack.bag, slot = stack.slot, count = left, split = true }
                taken[stack.key] = true
                left = 0
                break
            end
        end
    end

    return steps
end

--- Open the Send Mail page and fill it in for one delivery.
--
-- The name and subject go in at once, the items one at a time after. As many
-- stacks as one mail holds; what is left stays on the list for the next mail.
-- @param onDone function(attached, leftOver) when the last item is in
-- @return true when it started, or false and why
function QueueMail:Fill(delivery, onDone)
    if self.filling then return false, "still filling the last mail" end
    if InCombatLockdown and InCombatLockdown() then return false, "not in combat" end

    local nameBox = _G.SendMailNameEditBox
    if not nameBox then return false, "the mailbox is not open" end

    -- The Send Mail tab. Its own click handler where the client has it.
    if _G.MailFrameTab2 and _G.MailFrameTab_OnClick then
        Call(_G.MailFrameTab_OnClick, _G.MailFrameTab2, 2)
    elseif _G.MailFrameTab2 and _G.MailFrameTab2.Click then
        Call(_G.MailFrameTab2.Click, _G.MailFrameTab2)
    end

    local record = delivery.to and CharacterRecord(delivery.to)
    local name = delivery.recipient or (record and record.name) or delivery.name
    Call(nameBox.SetText, nameBox, name)
    local subject = _G.SendMailSubjectEditBox
    if subject then Call(subject.SetText, subject, delivery.subject or "Materials for the craft queue") end

    local _, alreadyIn = UsedSlots()
    local room = MaxAttachments() - alreadyIn

    local steps, taken = {}, {}
    for _, item in ipairs(delivery.items) do
        for _, step in ipairs(self:PlanStacks(item.itemID, item.count, taken)) do
            step.itemID = item.itemID
            steps[#steps + 1] = step
        end
    end

    local leftOver = math.max(0, #steps - room)
    while #steps > room do steps[#steps] = nil end

    if #steps == 0 then
        if onDone then onDone(0, leftOver) end
        return true
    end

    self.filling = true
    local attached = 0

    local function Finish()
        QueueMail.filling = false
        if CursorHasItem and CursorHasItem() then Call(ClearCursor) end
        if onDone then onDone(attached, leftOver) end
    end

    local index = 0
    local function Next()
        index = index + 1
        local step = steps[index]
        if not step or not (_G.SendMailFrame and _G.SendMailFrame:IsShown()) then
            return Finish()
        end

        local slot = FreeSlot()
        if not slot then return Finish() end

        if CursorHasItem and CursorHasItem() then Call(ClearCursor) end

        local picked
        if step.split then
            picked = Call(C_Container.SplitContainerItem, step.bag, step.slot, step.count)
        else
            picked = Call(C_Container.PickupContainerItem, step.bag, step.slot)
        end

        if picked and CursorHasItem and CursorHasItem() then
            Call(_G.ClickSendMailItemButton, slot)
            if CursorHasItem() then
                -- The mail would not take it: put it back and stop.
                Call(ClearCursor)
                leftOver = leftOver + (#steps - index + 1)
                return Finish()
            end
            attached = attached + 1
        end

        C_Timer.After(ATTACH_STEP, Next)
    end

    Next()
    return true
end

--------------------------------------------------------------------------------
-- Writing down what was sent
--------------------------------------------------------------------------------

--- Which of your characters a typed name means: one on this realm with that
--- first name, and only when exactly one is.
function QueueMail:FindCharacter(typed)
    if type(typed) ~= "string" or typed == "" then return nil end

    local selfRecord = CharacterRecord(SelfKey())
    local realm = selfRecord and selfRecord.realm
    local wanted, wantedRealm = typed:match("^([^-]+)-?(.*)$")
    wanted = (wanted or typed):lower()
    if wantedRealm ~= nil and wantedRealm ~= "" then realm = wantedRealm end

    local found
    for characterKey, record in pairs((ns.db and ns.db.characters) or {}) do
        if type(record) == "table" and type(record.name) == "string"
            and record.name:lower() == wanted
            and (not realm or not record.realm or record.realm:gsub("%s", "") == realm:gsub("%s", "")) then
            if found then return nil end
            found = characterKey
        end
    end

    if found == SelfKey() then return nil end
    return found
end

--- What is attached to the mail being written: list of { itemID, count }.
local function ReadAttachments()
    local items = {}
    for slot = 1, MaxAttachments() do
        local ok, name, itemID, _, count = Call(_G.GetSendMailItem, slot)
        if ok and name ~= nil then
            local okCopy, id, n = pcall(function() return itemID + 0, (count or 1) + 0 end)
            if okCopy and id then items[#items + 1] = { itemID = id, count = n } end
        end
    end
    return items
end

--- SendMail was called. What it carries is written down once the game says
--- it went (MAIL_SEND_SUCCESS); a failed send is forgotten.
function QueueMail:OnSendMail(recipient)
    local ok, copied = pcall(function() return recipient .. "" end)
    local toKey = ok and self:FindCharacter(copied) or nil
    if not toKey then
        self.pending = nil
        return
    end
    -- Read as the mail goes. Should the game have emptied the page first,
    -- the last reading taken while it was being filled stands in.
    local items = ReadAttachments()
    if #items == 0 and self.lastAttachments then items = self.lastAttachments end
    self.pending = { to = toKey, items = items }
end

function QueueMail:OnSendSuccess()
    local pending = self.pending
    self.pending = nil
    if not pending or #pending.items == 0 then return end

    self:NoteSent(pending.to, pending.items)
    self.lastAttachments = nil
    if ns.QueueMailPanel and ns.QueueMailPanel.OnSent then ns.QueueMailPanel:OnSent(pending.to) end
    if ns.Queue then
        ns.Queue:RebuildDependencies()
        ns.Queue:Notify()
    end
end

function QueueMail:OnEnable()
    self:Prune()

    if type(hooksecurefunc) == "function" and type(_G.SendMail) == "function" then
        pcall(hooksecurefunc, "SendMail", function(recipient)
            QueueMail:OnSendMail(recipient)
        end)
    end

    ns.RegisterEvent(self, "MAIL_SEND_SUCCESS", function() QueueMail:OnSendSuccess() end)
    ns.RegisterEvent(self, "MAIL_FAILED", function() QueueMail.pending = nil end)

    -- What is attached, each time it changes, for OnSendMail.
    ns.RegisterEvent(self, "MAIL_SEND_INFO_UPDATE", function()
        QueueMail.lastAttachments = ReadAttachments()
    end)
    ns.RegisterEvent(self, "MAIL_CLOSED", function() QueueMail.lastAttachments = nil end)
end
