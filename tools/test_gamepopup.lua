-- Asking "List It / Skip" never borrows the game's own pop-up (Trent,
-- 2026-11-19). A Spellstone from the bags was blocked with "Blackthornes_TS
-- has been blocked from an action only available to the Blizzard UI": the
-- listing question had been shown in the game's pop-up box, which left the
-- box marked as ours, and the game's next question in that box (replace the
-- weapon's enchant) could no longer do its protected step.
--
-- What must hold:
--   1. Asking about a listing never calls StaticPopup_Show or StaticPopup_Hide
--      and adds nothing to StaticPopupDialogs: it opens Tradeskills' own window.
--   2. List It in that window lists; Skip passes it over; a newer question
--      replaces an open one without listing or skipping it.
--   3. The auction house closing takes the window down and says so.
--   4. No file the game loads calls the game's pop-up functions.

-- Tests share one Lua state, so every global replaced here is put back,
-- including the ones that were not set at all.
local GLOBALS = { "CreateFrame", "C_Container", "ItemLocation", "GetTime", "time", "C_Timer",
    "StaticPopupDialogs", "StaticPopup_Show", "StaticPopup_Hide", "StaticPopup_Visible",
    "C_AuctionHouse" }
local saved = {}
for _, key in ipairs(GLOBALS) do saved[key] = _G[key] end

local function noop() end

local function Blank()
    return setmetatable({}, { __index = function(_, k)
        if type(k) == "string" and k:match("^%u") then return noop end
    end })
end

CreateFrame = function() return Blank() end
GetTime = function() return 1000 end
time = function() return 100000 end

local timers = {}
C_Timer = {
    After = function(seconds, fn) timers[#timers + 1] = { seconds = seconds, fn = fn } end,
    NewTicker = function() return { Cancel = noop } end,
    NewTimer = function() return { Cancel = noop } end,
}

local ITEM, LINEN = 4321, 2589

-- One stack of 5 of the crafted item and 200 Linen Cloth.
local bags = { [0] = { { itemID = ITEM, stackCount = 5 }, { itemID = LINEN, stackCount = 200 } } }
C_Container = {
    GetContainerNumSlots = function(bag) return bags[bag] and #bags[bag] or 0 end,
    GetContainerItemInfo = function(bag, slot)
        local e = bags[bag] and bags[bag][slot]
        if e then return { itemID = e.itemID, stackCount = e.stackCount, isLocked = false } end
    end,
}
ItemLocation = { CreateFromBagAndSlot = function() return { IsValid = function() return true end } end }

-- The game's pop-ups: any touch is recorded, and none is allowed.
local touched = {}
StaticPopupDialogs = setmetatable({}, { __newindex = function(t, k, v)
    touched[#touched + 1] = "StaticPopupDialogs." .. tostring(k)
    rawset(t, k, v)
end })
StaticPopup_Show = function(which) touched[#touched + 1] = "StaticPopup_Show " .. tostring(which) end
StaticPopup_Hide = function(which) touched[#touched + 1] = "StaticPopup_Hide " .. tostring(which) end
StaticPopup_Visible = function() return nil end

local said = {}
local ns = {}
ns.COLORS = setmetatable({}, { __index = function() return "ffffffff" end })
ns.NewModule = function(name) local m = {}; ns[name] = m; return m end
ns.RegisterCommand = noop

local handlers = {}
ns.RegisterEvent = function(owner, event, fn)
    handlers[event] = handlers[event] or {}
    table.insert(handlers[event], fn)
    return true
end
local function Fire(event, ...)
    for _, fn in ipairs(handlers[event] or {}) do fn(event, ...) end
end

ns.Print = function(text) said[#said + 1] = text end
ns.Warn = function(text) said[#said + 1] = "WARN " .. text end
ns.PrintRaw, ns.Debug = noop, noop

local settings = { postDuration = 2, verifyPriceBeforePosting = true, askBeforeListing = true }
ns.db = {}
ns.Config = {
    Get = function(_, k) return settings[k] end,
    Set = function(_, k, v) settings[k] = v end,
    GetRealmKey = function() return "Realm-Alliance" end,
    GetCharacterKey = function() return "Player-1" end,
}

-- The price check: the next answer is handed over by the test.
local checks = {}
ns.Scanner = {
    isAuctionHouseOpen = true, isScanning = false,
    IsCommodity = function() return true end,
    ScanItem = function(_, itemID, cb)
        -- A newer search for the same thing replaces the older one.
        for _, check in ipairs(checks) do
            if not check.done then
                check.done = true
                check.cb(itemID, nil, nil, nil, nil, nil, "superseded")
            end
        end
        checks[#checks + 1] = { itemID = itemID, cb = cb }
        return true
    end,
    AbandonItemScan = noop,
}
local function Answer(status)
    local check = checks[#checks]
    check.done = true
    check.cb(check.itemID, 300, 300, 5, true, {}, status or "fresh")
end

ns.Prices = {
    GetValue = function(_, _, key) if key == "market" then return 600 end if key == "rival" then return 301 end end,
    Get = function() return {} end,
}
ns.Inventory = {
    GetCarriedBags = function() return { 0 } end,
    GetBagCount = function(_, itemID) return itemID == LINEN and 200 or 5 end,
}
ns.Recipes = { GetAccountWide = function() return { [77] = { recipeID = 77, outputItemID = ITEM } } end }
ns.Queue = { GetReservedItems = function() return { [LINEN] = 6 } end }
ns.Cost = { FindRecipeForItem = function(_, itemID) return itemID == ITEM and 77 or nil end }
ns.Cost.FindAnyRecipeForItem = ns.Cost.FindRecipeForItem
ns.Profit = {
    ChoosePostPrice = function() return 300, "undercut" end,      -- 3s each
    Analyse = function() return { costPerUnit = 500 } end,         -- 5s to make
}
ns.AHQueue = { Yield = noop, PRIORITY = { urgent = 10 }, MIN_SPACING = 1.2,
    SecondsUntilReady = function() return 0 end }

C_AuctionHouse = { PostCommodity = function() said[#said + 1] = "POSTED" end }

assert(loadfile(lfs_cwd .. "/Core/Util.lua"))("Blackthornes_TS", ns)
assert(loadfile(lfs_cwd .. "/Logic/Posting.lua"))("Blackthornes_TS", ns)
assert(loadfile(lfs_cwd .. "/Data/Auctions.lua"))("Blackthornes_TS", ns)

local Posting = ns.Posting
Posting:OnEnable()

local passed, failed = 0, 0

local function check(label, got, want)
    local ok = got == want
    if ok then passed = passed + 1 else failed = failed + 1 end
    print(string.format("  %-62s %-8s %s", label, tostring(got), ok and "ok" or
        ("WRONG, wanted " .. tostring(want))))
end

local function Said(fragment)
    for _, line in ipairs(said) do
        if line:find(fragment, 1, true) then return true end
    end
    return false
end


-- Tradeskills' own question window, as far as Posting uses it.
local asked
ns.PostConfirm = {
    Show = function(_, ask) asked = ask; return true end,
    IsShown = function() return asked ~= nil end,
    Close = function() asked = nil end,
}

local function Reset()
    said, asked, checks, touched = {}, nil, {}, {}
    Posting.confirming, Posting.pending, Posting.requesting = nil, nil, {}
    ns.Scanner.isAuctionHouseOpen = true
end

-- What the window's buttons do.
local function ListIt() local a = asked; asked = nil; a.accept(a.data) end
local function SkipIt() local a = asked; asked = nil; a.skip(a.data) end

print("")
print("asking leaves the game's pop-up alone")

check("loading the addon adds nothing to the game's pop-ups", #touched, 0)

Reset()
settings.allowPostingAtALoss = true
Posting:Request(ITEM, 5, 300)
Answer("fresh")
check("the question is asked", asked ~= nil, true)
check("in our own window, not the game's pop-up", touched[1], nil)
check("with the item for its icon", asked and asked.itemID, ITEM)
check("and the four lines", asked and asked.text and asked.text:find("Posting at:", 1, true) ~= nil, true)
ListIt()
check("List It lists", Said("POSTED"), true)

Reset()
Posting:Request(ITEM, 5, 300)
Answer("fresh")
SkipIt()
check("Skip lists nothing", Said("POSTED"), false)
check("and says skipped", Said("skipped."), true)
check("and passes it over", Posting:IsPassedOver(ITEM), true)
Posting:ForgetChecks()
if Posting.passedOver then Posting.passedOver = {} end

Reset()
Posting:Confirm(ITEM, 5, 300)
local first = asked
Posting:Confirm(ITEM, 3, 300)
check("a newer question replaces the open one", asked ~= first and asked.data.quantity, 3)
check("without skipping the first", Said("skipped."), false)
ListIt()
check("and its List It lists the newer one", Said("POSTED"), true)

Reset()
Posting:Request(ITEM, 5, 300)
Answer("fresh")
ns.Scanner.isAuctionHouseOpen = false
Fire("AUCTION_HOUSE_CLOSED")
check("the auction house closing takes it down", asked, nil)
check("and says so", Said("was not listed"), true)
check("still without the game's pop-up", touched[1], nil)
settings.allowPostingAtALoss = nil

print("")
print("no file calls the game's pop-up")

do
    local toc = assert(io.open(lfs_cwd .. "/Blackthornes_TS.toc")):read("*a")
    local found = {}
    for path in toc:gmatch("[^\r\n]+%.lua") do
        path = path:gsub("\\", "/")
        local file = io.open(lfs_cwd .. "/" .. path)
        if file then
            local text = file:read("*a")
            file:close()
            for line in text:gmatch("[^\n]+") do
                local code = line:gsub("%-%-.*$", "")
                if code:find("StaticPopup_Show", 1, true) or code:find("StaticPopup_Hide", 1, true)
                    or code:find("StaticPopupDialogs%s*%[") then
                    found[#found + 1] = path
                end
            end
        end
    end
    check("files that call the game's pop-up", table.concat(found, ", "), "")
end

for _, key in ipairs(GLOBALS) do _G[key] = saved[key] end

print("")
print(("%d passed, %d failed"):format(passed, failed))
assert(failed == 0, "game pop-up checks failed")
