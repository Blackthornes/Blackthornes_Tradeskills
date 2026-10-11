-- Items bought on the auction house to disenchant (Logic/DisenchantBuys.lua).
--
-- What must hold:
--   1. A purchase after a search from the Disenchanting tab is marked; one
--      without a search, or long after it, is not.
--   2. The mark is account wide and survives the item going to the mail, the
--      bank or another character, or being on its way to one.
--   3. It shrinks to what the account holds, and goes when none is left.
--   4. A disenchant uses one up; marking by hand never lowers a count.
--   5. Butler's Advise says how many, and Butler can mark and unmark.

local saved = { time = _G.time }

local clock = 200000
time = function() return clock end

local WAND, AXE = 11288, 15268
local SELF, ALT = "Ana Stoneheart-Realm", "Bob Ashford-Realm"

local function noop() end

local ns = {}
ns.NewModule = function(name) local m = {}; ns[name] = m; return m end
ns.RegisterCommand, ns.RegisterEvent = noop, noop
ns.Debug, ns.Warn = noop, noop
local printed = {}
ns.Print = function(text) printed[#printed + 1] = text end
ns.Util = { GetItemLabel = function(id) return "[item " .. id .. "]" end }
ns.Config = { GetCharacterKey = function() return SELF end, Get = function() return nil end }

local bags, bank = {}, {}
ns.Inventory = {
    GetBagCount = function(_, id) return bags[id] or 0 end,
    GetBankCount = function(_, id) return bank[id] or 0 end,
}

local inFlight = {}
ns.QueueMail = {
    InFlight = function(_, key, id) return (inFlight[key] and inFlight[key][id]) or 0 end,
}

ns.db = { characters = {
    [SELF] = { mail = {}, ahBuys = {} },
    [ALT] = { inventory = {}, bank = {}, mail = {} },
} }

local passed, failed = 0, 0
local function check(name, got, want)
    if got == want then
        passed = passed + 1
    else
        failed = failed + 1
        print(("  FAIL %s: got %s, want %s"):format(name, tostring(got), tostring(want)))
    end
end

local lfs_cwd = lfs_cwd or "."
assert(loadfile(lfs_cwd .. "/Logic/DisenchantBuys.lua"))("Blackthornes_TS", ns)
local Buys = ns.DisenchantBuys

-- 1. Marked only after a search from the tab.
Buys:OnBought(WAND, 3)
check("a buy with no search is not marked", Buys:Count(WAND), 0)

Buys:Intend(WAND)
clock = clock + 60
Buys:OnBought(WAND, 3)
check("a buy after a search is marked", Buys:Count(WAND), 3)
check("and chat says so", #printed, 1)
Buys:OnBought(AXE, 2)
check("another item is not", Buys:Count(AXE), 0)

Buys:Intend(AXE)
clock = clock + Buys.INTENT_SECONDS + 1
Buys:OnBought(AXE, 2)
check("a buy long after the search is not", Buys:Count(AXE), 0)

-- 2. In the mail as an auction buy: still held.
ns.db.characters[SELF].ahBuys = { { itemID = WAND, quantity = 3, at = clock } }
Buys:Settle()
check("waiting in the mail keeps the mark", Buys:Count(WAND), 3)

-- Taken into the bags.
ns.db.characters[SELF].ahBuys = {}
bags[WAND] = 3
Buys:Settle()
check("in the bags keeps it", Buys:Count(WAND), 3)

-- Mailed to the enchanter: on its way, then in its mailbox, then its bags.
bags[WAND] = 0
inFlight[ALT] = { [WAND] = 3 }
Buys:Settle()
check("on its way to an alt keeps it", Buys:Count(WAND), 3)
inFlight[ALT] = nil
ns.db.characters[ALT].mail[WAND] = 3
Buys:Settle()
check("in the alt's mailbox keeps it", Buys:Count(WAND), 3)
ns.db.characters[ALT].mail[WAND] = nil
ns.db.characters[ALT].inventory[WAND] = 3
Buys:Settle()
check("in the alt's bags keeps it", Buys:Count(WAND), 3)

-- Banked by the one playing.
ns.db.characters[ALT].inventory[WAND] = nil
bank[WAND] = 3
Buys:Settle()
check("in the bank keeps it", Buys:Count(WAND), 3)

-- 3. Sold two: the mark shrinks to what is left; none left, it goes.
bank[WAND] = 1
Buys:Settle()
check("shrinks to what the account holds", Buys:Count(WAND), 1)
bank[WAND] = 0
Buys:Settle()
check("and goes with the last one", Buys:Count(WAND), 0)
check("leaving nothing saved", ns.db.boughtToDisenchant[WAND], nil)

-- More held than marked never raises a mark.
Buys:Add(AXE, 2)
bags[AXE] = 5
Buys:Settle()
check("more held never raises it", Buys:Count(AXE), 2)

-- 4. A disenchant uses one.
Buys:Used(AXE, 1)
check("a disenchant uses one", Buys:Count(AXE), 1)
Buys:Mark(AXE, 4)
check("marking by hand raises to what is asked", Buys:Count(AXE), 4)
Buys:Mark(AXE, 2)
check("and never lowers it", Buys:Count(AXE), 4)
Buys:Unmark(AXE)
check("unmarked", Buys:Count(AXE), 0)

-- An unreadable saved entry is dropped, never read as a count.
ns.db.boughtToDisenchant[999] = "junk"
check("junk reads as none", Buys:Count(999), 0)
Buys:Settle()
check("and is cleared", ns.db.boughtToDisenchant[999], nil)

-- 5. Butler. Only the parts of Logic/Butler.lua the new field touches.
local version = Buys.version
local stubNs = setmetatable({ NewModule = function(name) local m = {}; ns[name] = m; return m end }, { __index = ns })
assert(loadfile(lfs_cwd .. "/Logic/Butler.lua"))("Blackthornes_TS", stubNs)
local Butler = ns.Butler
local done = Butler:SetBoughtToDisenchant(WAND, true, 2)
check("Butler can mark", done, true)
check("two of them", Buys:Count(WAND), 2)
check("the version moved", Buys.version > version, true)
Butler:SetBoughtToDisenchant(WAND, false)
check("Butler can unmark", Buys:Count(WAND), 0)
check("a bad item ID is refused", (Butler:SetBoughtToDisenchant("x", true)), false)

for key, value in pairs(saved) do _G[key] = value end

print("")
if failed > 0 then
    error(string.format("FAIL -- %d of %d bought-to-disenchant checks wrong", failed, passed + failed))
end
print(string.format("PASS -- items bought to disenchant keep their mark (%d checks)", passed))
