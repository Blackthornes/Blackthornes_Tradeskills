-- Logic/SellOut.lua outside WoW: Keep in stock goes up by 1 when every copy
-- of a craft listed sold before its listings ran out (the owner, 2026-10-13).
--
--   1. Every copy sold, nothing back: the item's number goes up by 1, once.
--   2. Something came back expired or cancelled: nothing changes.
--   3. Nothing back and no sale seen yet: it waits for the next reading.
--   4. Before the listings run out, nothing is judged.
--   5. No limit stays no limit; an item none of your recipes make is ignored.
--   6. Unticked, nothing is watched or raised.
--   9. Three unsold rounds in a row take back one raise, never below where
--      it started; a sell out starts the count again; a number typed by
--      hand is left alone. Changed lists what it changed, Reset puts it back.
--   7. A part-read mailbox judges nothing.
--   8. Another character's listings wait for that character's mailbox.

local ns = {}
ns.NewModule = function(name) local m = {} ns[name] = m return m end

local now = 1000000
time = function() return now end

local printed = {}
ns.Print = function(line) printed[#printed + 1] = line end
local sounds = 0
PlaySound = function() sounds = sounds + 1 end

local settings = { postDuration = 2, raiseStockOnSellOut = true }
local who = "Player-1"
ns.Config = {
    Get = function(_, key) return settings[key] end,
    Set = function(_, key, value) settings[key] = value end,
    GetRealmKey = function() return "Realm-A" end,
    GetCharacterKey = function() return who end,
}
ns.Util = { GetItemLabel = function(id) return "item" .. tostring(id) end }

local POTION, SWORD, CLOTH, FREE = 100, 200, 300, 400
local crafts = { [POTION] = "Alchemy", [SWORD] = "Blacksmithing", [FREE] = "Tailoring" }
local limits = { [POTION] = 3, [SWORD] = 2, [FREE] = 0 }
ns.db = { postLimits = {} }
ns.Auctions = {
    ProfessionOf = function(_, id) return crafts[id] end,
    GetLimit = function(_, id)
        if ns.db.postLimits[id] then return ns.db.postLimits[id], "item" end
        return limits[id] or 0, "default"
    end,
    SetLimit = function(_, id, n) ns.db.postLimits[id] = n end,
}

local ledger = { entries = {} }
local heard = {}
ns.Mail = {
    GetLedger = function() return ledger end,
    GetHeardList = function() return heard end,
    NameIndex = function() return {} end,
}

assert(loadfile(lfs_cwd .. "/Logic/SellOut.lua"))("Blackthornes_TS", ns)
local S = ns.SellOut

local checks = 0
local function check(label, condition)
    checks = checks + 1
    if not condition then error(("FAILED: %s"):format(label), 2) end
    print(("  ok  %s"):format(label))
end

local function sold(itemID, character)
    ledger.entries[#ledger.entries + 1] = { t = now, kind = "sold", itemID = itemID, who = character or who }
end
local function back(itemID, sent, character)
    ledger.entries[#ledger.entries + 1] = { t = now, sent = sent, kind = "expired", itemID = itemID,
        quantity = 1, who = character or who }
end

-- 1. Three potions listed, two more joined later; all sold; mail read after.
local start = now
S:NotePosted(POTION, 3, 2)
now = now + 3600
S:NotePosted(POTION, 2, 2)
check("a listing inside the window joins it",
    #ns.db.sellOutWatch["Realm-A"][who][POTION] == 1
        and ns.db.sellOutWatch["Realm-A"][who][POTION][1].units == 5)
now = now + 1800
sold(POTION) sold(POTION)

-- 4. Not run out yet: nothing judged.
S:MailRead(true)
check("before the listings run out nothing changes", ns.db.postLimits[POTION] == nil)

now = start + 3600 + 8 * 3600 + 600
S:MailRead(true)
check("every copy sold: Keep in stock 3 becomes 4", ns.db.postLimits[POTION] == 4)
check("the player is told, once", #printed == 1 and printed[1]:find("item100", 1, true)
    and printed[1]:find("8 hours", 1, true) and printed[1]:find("4", 1, true))
check("with a little cheer", sounds == 1)
check("the raise is kept for the Profit tab", S:GetRaised(POTION).from == 3 and S:GetRaised(POTION).to == 4)
check("the window is closed", ns.db.sellOutWatch["Realm-A"][who][POTION] == nil)
S:MailRead(true)
check("once a window: reading again raises nothing more", ns.db.postLimits[POTION] == 4 and #printed == 1)

-- 2. A sword listed, one sold, one came back.
local swordFrom = now
S:NotePosted(SWORD, 2, 2)
now = now + 1000
sold(SWORD)
now = swordFrom + 8 * 3600 + 300
back(SWORD, swordFrom + 8 * 3600)
S:MailRead(true)
check("one came back: nothing changes", ns.db.postLimits[SWORD] == nil)
check("and the window is let go", ns.db.sellOutWatch["Realm-A"][who][SWORD] == nil)

-- 3. Listed, nothing back, no sale seen yet: waits.
local again = now
S:NotePosted(SWORD, 1, 1)   -- 2 hours
now = again + 2 * 3600 + 300
S:MailRead(true)
check("no sale seen yet: it waits", ns.db.postLimits[SWORD] == nil
    and #ns.db.sellOutWatch["Realm-A"][who][SWORD] == 1)
heard[#heard + 1] = { t = again + 600, itemID = SWORD, who = who }
now = now + 3600
S:MailRead(true)
check("the game's sale notice counts as a sale: 2 becomes 3", ns.db.postLimits[SWORD] == 3)
check("a 2 hour listing says 2 hours", printed[#printed]:find("2 hours", 1, true) ~= nil)

-- 7. A part-read mailbox judges nothing.
local cut = now
S:NotePosted(POTION, 1, 1)
now = cut + 2 * 3600 + 300
sold(POTION)
S:MailRead(false)
check("a part-read mailbox judges nothing", ns.db.postLimits[POTION] == 4)

-- 8. Another character's listings wait for that character's mailbox.
who = "Alt-2"
S:MailRead(true)
check("another character's mailbox does not judge them", ns.db.postLimits[POTION] == 4)
who = "Player-1"
S:MailRead(true)
check("the poster's own mailbox does: 4 becomes 5", ns.db.postLimits[POTION] == 5)

-- 5. No limit, and not a craft.
local free = now
S:NotePosted(FREE, 2, 1)
S:NotePosted(CLOTH, 2, 1)
check("an item none of your recipes make is not watched",
    ns.db.sellOutWatch["Realm-A"][who][CLOTH] == nil)
now = free + 2 * 3600 + 300
sold(FREE)
S:MailRead(true)
check("no limit stays no limit", ns.db.postLimits[FREE] == nil)

-- 6. Unticked: nothing watched, nothing raised.
settings.raiseStockOnSellOut = false
local off = now
S:NotePosted(POTION, 1, 1)
check("unticked: nothing is watched", ns.db.sellOutWatch["Realm-A"][who][POTION] == nil)
settings.raiseStockOnSellOut = nil
S:NotePosted(POTION, 1, 1)
check("off by default: nothing is watched", ns.db.sellOutWatch["Realm-A"][who][POTION] == nil)
settings.raiseStockOnSellOut = true

-- A number typed by hand starts again from there.
ns.db.postLimits[SWORD] = 7
local high = now
S:NotePosted(SWORD, 1, 1)
now = high + 2 * 3600 + 300
sold(SWORD)
S:MailRead(true)
check("a typed number is raised from there", ns.db.postLimits[SWORD] == 8
    and S:GetRaised(SWORD).base == 7)

-- 9. Unsold rounds.
local function unsold(itemID)
    local from = now
    S:NotePosted(itemID, 1, 1)
    now = from + 2 * 3600 + 300
    back(itemID, from + 2 * 3600)
    S:MailRead(true)
end
local function sellout(itemID)
    local from = now
    S:NotePosted(itemID, 1, 1)
    now = from + 600
    sold(itemID)
    now = from + 2 * 3600 + 300
    S:MailRead(true)
end
local before = #printed
unsold(SWORD) unsold(SWORD)
check("two unsold rounds change nothing", ns.db.postLimits[SWORD] == 8 and ns.db.sellOutUnsold[SWORD] == 2)
sellout(SWORD)
check("a sell out starts the count again", ns.db.postLimits[SWORD] == 9 and ns.db.sellOutUnsold[SWORD] == nil)
unsold(SWORD) unsold(SWORD) unsold(SWORD)
check("three unsold rounds in a row: 9 becomes 8", ns.db.postLimits[SWORD] == 8)
check("the player is told", printed[#printed]:find("unsold 3 times", 1, true) ~= nil)
check("the Profit tab can say it was lowered", S:GetRaised(SWORD).lowered == true
    and S:GetRaised(SWORD).from == 9 and S:GetRaised(SWORD).to == 8)
unsold(SWORD) unsold(SWORD) unsold(SWORD)
check("never below where it started: stays 7", ns.db.postLimits[SWORD] == 7)
unsold(SWORD) unsold(SWORD) unsold(SWORD)
check("and stays there", ns.db.postLimits[SWORD] == 7 and ns.db.sellOutUnsold[SWORD] == nil)
check("only two lowerings were told", #printed == before + 1 + 2)

-- A number typed by hand after a raise is left alone.
sellout(SWORD)
check("raised again to 8", ns.db.postLimits[SWORD] == 8)
ns.db.postLimits[SWORD] = 20
unsold(SWORD) unsold(SWORD) unsold(SWORD)
check("a typed number is never lowered", ns.db.postLimits[SWORD] == 20)

-- Changed and Reset.
sellout(SWORD)
local list = S:Changed()
local found
for _, entry in ipairs(list) do if entry.itemID == SWORD then found = entry end end
check("Changed lists the item with where it started", found and found.base == 20 and found.limit == 21)
check("Reset puts a typed number back", S:Reset(SWORD) and ns.db.postLimits[SWORD] == 20
    and S:GetRaised(SWORD) == nil)

-- POTION started from the usual 3 (not its own number): Reset clears it.
check("Changed lists the potion", (function()
    for _, entry in ipairs(S:Changed()) do if entry.itemID == POTION then return entry.base == 3 end end
end)())
S:Reset(POTION)
check("Reset of a raised usual number goes back to the usual", ns.db.postLimits[POTION] == nil)
check("nothing left changed", #S:Changed() == 0)

print(("test_sellout: %d checks passed"):format(checks))
