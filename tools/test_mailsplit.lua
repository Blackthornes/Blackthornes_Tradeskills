-- Mailing part of a stack (a player's report, 2026-10-11): sub-crafts mailed
-- to an alt went as the whole stack, not the number its queue needed.
--
-- The client here behaves the way that report says: a split dropped from the
-- cursor straight into the mail attaches the stack it came from. Fill must
-- split into an empty bag slot first, wait for it to show there, attach that,
-- and take back anything that went in bigger than asked for.
--
-- Drives the real QueueMail:Fill and QueueMail:PlanStacks.

local ns = {}
ns.NewModule = function(name) local m = {}; ns[name] = m; return m end
ns.RegisterCommand = function() end
ns.RegisterEvent = function() return true end
ns.Print, ns.PrintRaw, ns.Debug, ns.Warn = function() end, function() end, function() end, function() end
ns.Util = { IsBoundOnPickup = function() return false end }
time = time or os.time

local BOLT, WOOL = 2997, 2592

--------------------------------------------------------------------------------
-- A client: two bags, a cursor, a Send Mail page and a timer queue
--------------------------------------------------------------------------------

local bags, families, cursor, mailSlots, timers

local function Reset(contents, sizes)
    bags, families, cursor, mailSlots, timers = {}, {}, nil, {}, {}
    sizes = sizes or { [0] = 4, [1] = 4 }
    for bag, size in pairs(sizes) do
        bags[bag] = { size = size }
        families[bag] = 0
    end
    for key, stack in pairs(contents) do
        local bag, slot = key:match("(%d+):(%d+)")
        bags[tonumber(bag)][tonumber(slot)] = { itemID = stack[1], count = stack[2] }
    end
end

ns.Inventory = { GetCarriedBags = function() return { 0, 1 } end }

C_Container = {
    GetContainerNumSlots = function(bag) return bags[bag] and bags[bag].size or 0 end,
    GetContainerNumFreeSlots = function(bag)
        local free = 0
        for slot = 1, bags[bag].size do if not bags[bag][slot] then free = free + 1 end end
        return free, families[bag]
    end,
    GetContainerItemInfo = function(bag, slot)
        local stack = bags[bag] and bags[bag][slot]
        if not stack then return nil end
        return { itemID = stack.itemID, stackCount = stack.count, isLocked = stack.locked, isBound = false }
    end,
    PickupContainerItem = function(bag, slot)
        local stack = bags[bag][slot]
        if cursor then
            -- Putting down: an empty slot takes what is on the cursor. A
            -- split shows up there a moment later, as the real client does.
            if stack then return end
            local placed = { itemID = cursor.itemID, count = cursor.count, locked = true }
            bags[bag][slot] = placed
            if cursor.from then
                cursor.from.count = cursor.from.count - cursor.count
                cursor.from.locked = nil
            end
            cursor = nil
            timers[#timers + 1] = function() placed.locked = nil end
        elseif stack then
            cursor = { itemID = stack.itemID, count = stack.count, bag = bag, slot = slot }
        end
    end,
    SplitContainerItem = function(bag, slot, count)
        local stack = bags[bag][slot]
        if not stack or count >= stack.count then return end
        stack.locked = true
        cursor = { itemID = stack.itemID, count = count, from = stack, bag = bag, slot = slot }
    end,
}

CursorHasItem = function() return cursor ~= nil end
ClearCursor = function()
    if cursor and cursor.from then cursor.from.locked = nil end
    cursor = nil
end
InCombatLockdown = function() return false end

ATTACHMENTS_MAX_SEND = 12
SendMailNameEditBox = { SetText = function(self, text) self.text = text end }
SendMailSubjectEditBox = { SetText = function(self, text) self.text = text end }
SendMailFrame = { IsShown = function() return true end }

-- The bug the player hit: a split dropped straight in attaches its source stack.
ClickSendMailItemButton = function(slot, clear)
    if clear then
        local item = mailSlots[slot]
        mailSlots[slot] = nil
        if item then item.source.inMail = nil end
        return
    end
    if not cursor or mailSlots[slot] then return end
    local source = cursor.from or bags[cursor.bag][cursor.slot]
    source.inMail = true
    mailSlots[slot] = { itemID = source.itemID, count = source.count, source = source }
    if cursor.from then cursor.from.locked = nil end
    cursor = nil
end

GetSendMailItem = function(slot)
    local item = mailSlots[slot]
    if not item then return nil end
    return "Item", item.itemID, 1, item.count
end

C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end }

local function RunTimers()
    local guard = 0
    while #timers > 0 do
        guard = guard + 1
        assert(guard < 1000, "timers never settled")
        table.remove(timers, 1)()
    end
end

assert(loadfile(lfs_cwd .. "/Logic/QueueMail.lua"))("Blackthornes_TS", ns)
local QueueMail = ns.QueueMail

local checks = 0
local function check(label, condition)
    checks = checks + 1
    if not condition then error(("FAILED: %s"):format(label), 2) end
    print(("  ok  %s"):format(label))
end

local function Mailed(itemID)
    local total = 0
    for _, item in pairs(mailSlots) do
        if item.itemID == itemID then total = total + item.count end
    end
    return total
end

local function Fill(items)
    local result
    local started = QueueMail:Fill({ recipient = "Bob Wither", items = items },
        function(attached, leftOver) result = { attached = attached, leftOver = leftOver } end)
    RunTimers()
    return started, result
end

print("\nthree bolts from a stack of twenty")

Reset({ ["0:1"] = { BOLT, 20 } })
local started, result = Fill({ { itemID = BOLT, count = 3 } })
check("filling started", started == true)
check("three bolts in the mail, not twenty", Mailed(BOLT) == 3)
check("seventeen stay in the bags", bags[0][1].count == 17 and not bags[0][1].inMail)
check("the three were split into a slot of their own", bags[0][2] and bags[0][2].count == 3)
check("one attached, nothing left over", result.attached == 1 and result.leftOver == 0)
check("the name went in", SendMailNameEditBox.text == "Bob Wither")

print("\nwhole stacks first, then the rest split")

Reset({ ["0:1"] = { WOOL, 20 }, ["0:2"] = { WOOL, 5 } })
Fill({ { itemID = WOOL, count = 12 } })
check("twelve wool in the mail", Mailed(WOOL) == 12)
check("the stack of five went whole", bags[0][2].inMail == true)
check("thirteen left of the twenty", bags[0][1].count == 13)

print("\nno empty bag slot to split into")

Reset({ ["0:1"] = { BOLT, 20 }, ["0:2"] = { WOOL, 1 }, ["0:3"] = { WOOL, 1 }, ["0:4"] = { WOOL, 1 },
    ["1:1"] = { WOOL, 1 }, ["1:2"] = { WOOL, 1 }, ["1:3"] = { WOOL, 1 }, ["1:4"] = { WOOL, 1 } })
started, result = Fill({ { itemID = BOLT, count = 3 } })
check("nothing is mailed", Mailed(BOLT) == 0)
check("the twenty stay whole", bags[0][1].count == 20)
check("the player is told why", QueueMail.splitBlocked == true and result.leftOver == 1)

print("\na herb bag is not split into")

Reset({ ["0:1"] = { BOLT, 20 }, ["0:2"] = { WOOL, 1 }, ["0:3"] = { WOOL, 1 }, ["0:4"] = { WOOL, 1 } })
families[1] = 32
Fill({ { itemID = BOLT, count = 3 } })
check("nothing goes in the herb bag", bags[1][1] == nil)
check("and nothing is mailed", Mailed(BOLT) == 0)

print("\nan attachment bigger than asked for is taken back")

-- A stack that grew between planning and attaching (the player looted more).
Reset({ ["0:1"] = { BOLT, 3 } })
local planned = QueueMail:PlanStacks(BOLT, 3, {})
check("planned as one whole stack", #planned == 1 and not planned[1].split)
local realPickup = C_Container.PickupContainerItem
C_Container.PickupContainerItem = function(bag, slot)
    if bags[bag][slot] and not cursor then bags[bag][slot].count = 8 end
    return realPickup(bag, slot)
end
started, result = Fill({ { itemID = BOLT, count = 3 } })
C_Container.PickupContainerItem = realPickup
check("the eight are not left in the mail", Mailed(BOLT) == 0)
check("counted as not attached", result.attached == 0 and result.leftOver == 1)

print(("\n%d passed, 0 failed"):format(checks))
