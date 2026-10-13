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

assert(loadfile(lfs_cwd .. "/Core/Characters.lua"))("Blackthornes_TS", ns)
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

print("\nherbs in a herb bag split there when the other bags are full")

-- A herbalist's mail left two herbs out (2026-10-13): the split could only
-- go to an ordinary bag, and those were full.
local HERB = 2452
Reset({ ["0:1"] = { BOLT, 20 }, ["0:2"] = { WOOL, 1 }, ["0:3"] = { WOOL, 1 }, ["0:4"] = { WOOL, 1 },
    ["1:1"] = { HERB, 20 } })
families[1] = 32
started, result = Fill({ { itemID = HERB, count = 6 } })
check("six herbs in the mail", Mailed(HERB) == 6)
check("split into the herb bag itself", bags[1][2] and bags[1][2].count == 6)
check("nothing left over", result.leftOver == 0 and not QueueMail.splitBlocked)

print("\na herb from an ordinary bag may split into the herb bag")

C_Item = { GetItemFamily = function(itemID) return itemID == HERB and 32 or 0 end }
Reset({ ["0:1"] = { HERB, 20 }, ["0:2"] = { WOOL, 1 }, ["0:3"] = { WOOL, 1 }, ["0:4"] = { WOOL, 1 } })
families[1] = 32
Fill({ { itemID = HERB, count = 6 } })
check("six herbs in the mail", Mailed(HERB) == 6)
check("split into the herb bag, which takes herbs", bags[1][1] and bags[1][1].count == 6)
Reset({ ["0:1"] = { BOLT, 20 }, ["0:2"] = { WOOL, 1 }, ["0:3"] = { WOOL, 1 }, ["0:4"] = { WOOL, 1 } })
families[1] = 32
Fill({ { itemID = BOLT, count = 3 } })
check("cloth still never goes in the herb bag", bags[1][1] == nil and Mailed(BOLT) == 0)
C_Item = nil

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

print("\ngold in the mail (Butler's gold top-ups)")

local purse = 100000
GetMoney = function() return purse end
local codChecked = false
SendMailCODButton = { GetChecked = function() return codChecked end }
SendMailMoney = {}
local boxes = {}
for _, key in ipairs({ "Gold", "Silver", "Copper" }) do
    boxes[key] = { SetText = function(self, text) self.text = text end }
    _G["SendMailMoney" .. key] = boxes[key]
end

Reset({})
started = QueueMail:Fill({ recipient = "Bob Wither", items = {}, money = 52307 }, function() end)
check("gold alone fills a mail", started == true)
check("in the gold, silver and copper boxes",
    boxes.Gold.text == "5" and boxes.Silver.text == "23" and boxes.Copper.text == "7")
local setTo
MoneyInputFrame_SetCopper = function(frame, copper) setTo = { frame, copper } end
QueueMail:Fill({ recipient = "Bob Wither", items = {}, money = 500 }, function() end)
check("through the game's own money boxes where it has them", setTo and setTo[1] == SendMailMoney and setTo[2] == 500)
MoneyInputFrame_SetCopper = nil
local ok, why = QueueMail:Fill({ recipient = "Bob Wither", items = {}, money = purse }, function() end)
check("never more than the purse less postage", ok == false and why == "not enough gold on you")
codChecked = true
ok, why = QueueMail:Fill({ recipient = "Bob Wither", items = {}, money = 100 }, function() end)
check("never into a COD mail", ok == false and why == "the mail is set to COD")
GetMoney, SendMailCODButton, SendMailMoney = nil, nil, nil
SendMailMoneyGold, SendMailMoneySilver, SendMailMoneyCopper = nil, nil, nil

print(("\n%d passed, 0 failed"):format(checks))
