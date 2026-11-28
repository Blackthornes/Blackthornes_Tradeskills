-- Crafts with a wait on the Profit tab (a Discord player, the owner said
-- build it 2026-11-28). Mooncloth can be made once every 4 days, but A DAY
-- counted it as if one could be made every time one sold, so it topped
-- My Crafts with gold nobody can make.
--
-- What must hold:
--   * A DAY counts the smaller of how many sell a day and how many can be
--     made a day: Mooncloth every 4 days is 0.25, a plain craft is untouched;
--   * the wait the game says, saved beside readyAt when the craft is cast,
--     beats Classic's lengths, which beat "a day";
--   * the row's mark says Ready, or the time left, for the character who
--     would make it, and the soonest of all who know it with All Characters;
--   * transmutes share one wait: one cast puts every transmute on hold;
--   * MAKE is 1 when ready, 0 while it waits;
--   * GOLD/HR has nothing for these crafts;
--   * the tooltip lines read in the right order.
--
-- Drives the real Cost.lua, Cooldowns.lua, CraftTime.lua and Profit.lua.

local GLOBALS = { "CreateFrame", "GetTime", "time", "C_Item", "C_Spell", "GetSpellInfo",
    "GetSpellCooldown", "C_Timer" }
local saved = {}
for _, key in ipairs(GLOBALS) do saved[key] = _G[key] end

local function noop() end

CreateFrame = function()
    return setmetatable({}, { __index = function(_, k)
        if type(k) == "string" and k:match("^%u") then return noop end
    end })
end
local NOW = 1000000
GetTime = function() return 5000 end
time = function() return NOW end
C_Spell, GetSpellInfo, GetSpellCooldown, C_Timer = nil, nil, nil, nil

local MOONCLOTH, FELCLOTH, BELT, LINEN, GOLD, IRON, ARCANITE, THORIUM = 14342, 14256, 5000, 2589,
    3577, 3575, 12360, 12359
local MOON_RECIPE, BELT_RECIPE, IRON_GOLD, ARCANITE_RECIPE = 18560, 300, 11479, 17187
local ME, ALT = "Player-ME", "Player-ALT"

C_Item = { GetItemInfo = function(itemID)
    return "item " .. itemID, "link", 2, 1, 1, "", "", 20, "", "", 0
end }

local function Recipe(id, name, output, reagent)
    return { recipeID = id, name = name, outputItemID = output, quantityMin = 1, quantityMax = 1,
        reagents = { { itemID = reagent, quantity = 2 } } }
end
local RECIPES = {
    [MOON_RECIPE] = Recipe(MOON_RECIPE, "Mooncloth", MOONCLOTH, FELCLOTH),
    [BELT_RECIPE] = Recipe(BELT_RECIPE, "Linen Belt", BELT, LINEN),
    [IRON_GOLD] = Recipe(IRON_GOLD, "Transmute: Iron to Gold", GOLD, IRON),
    [ARCANITE_RECIPE] = Recipe(ARCANITE_RECIPE, "Transmute: Arcanite", ARCANITE, THORIUM),
}

local settings = { undercutCopper = 1, auctionCut = 0.05, expectedRelists = 1, minProfit = 0,
    staleAfterSeconds = 48 * 3600, valueOwnedMaterials = true, unscannedMarkupPercent = 50,
    priceUnscannedCrafts = true }

local ns = {}
ns.COLORS = { profit = "ff4fd17a", muted = "ff857c68" }
ns.NewModule = function(name) local m = {}; ns[name] = m; return m end
ns.RegisterEvent = noop
ns.RegisterCommand = noop
ns.Print, ns.PrintRaw, ns.Debug, ns.Warn = noop, noop, noop, noop
ns.L = setmetatable({ Format = function(key, ...) return string.format(key, ...) end },
    { __index = function(_, key) return key end })

local function fresh()
    ns.db = {
        characters = {
            [ME] = { name = "Ana Lyst", recipes = { [MOON_RECIPE] = RECIPES[MOON_RECIPE],
                [BELT_RECIPE] = RECIPES[BELT_RECIPE], [IRON_GOLD] = RECIPES[IRON_GOLD],
                [ARCANITE_RECIPE] = RECIPES[ARCANITE_RECIPE] } },
            [ALT] = { name = "Bo Bbin", recipes = { [MOON_RECIPE] = RECIPES[MOON_RECIPE] } },
        },
        professionCooldowns = {},
    }
    if ns.Cost and ns.Cost.InvalidateIndex then ns.Cost:InvalidateIndex() end
end

local priceTable = {}
ns.Config = {
    Get = function(_, key) return settings[key] end,
    GetCharacterKey = function() return ME end,
    GetPriceTable = function() return priceTable end,
}
ns.Recipes = {
    GetAll = function() return ns.db.characters[ME].recipes end,
    Get = function(self, id) return self:GetAll()[id] end,
    GetAny = function(self, id) return self:GetAll()[id], self:GetAll()[id] and ME or nil end,
    GetAccountWide = function(self) return self:GetAll() end,
    GetCharacterName = function(_, key) return ns.db.characters[key] and ns.db.characters[key].name end,
    IsDropped = function() return false end,
    GetDisplayLink = function() return "[craft]" end,
}
ns.Inventory = {
    GetBagCount = function(_, id) return (id == FELCLOTH or id == LINEN) and 12 or 0 end,
    GetCharacterBagCount = function(_, _, id) return (id == FELCLOTH or id == LINEN) and 12 or 0 end,
    GetBankCount = function() return 0 end, GetOwnedCount = function() return 0 end,
    GetAltTotal = function() return 0 end,
}
ns.Vendor = { GetUnitPrice = function() return nil end }
ns.Scanner = { GetCommodityStatus = function() return true end }
ns.Auctions = { GetRoom = function() return nil, 0, 0, 0, 0, 0 end }
ns.Posting = { GetCachedUnitDeposit = function() return 0 end }

fresh()
assert(loadfile(lfs_cwd .. "/Core/Util.lua"))("Blackthornes_TS", ns)
assert(loadfile(lfs_cwd .. "/Data/Prices.lua"))("Blackthornes_TS", ns)
assert(loadfile(lfs_cwd .. "/Logic/Cost.lua"))("Blackthornes_TS", ns)
assert(loadfile(lfs_cwd .. "/Logic/Cooldowns.lua"))("Blackthornes_TS", ns)
assert(loadfile(lfs_cwd .. "/Logic/CraftTime.lua"))("Blackthornes_TS", ns)
assert(loadfile(lfs_cwd .. "/Logic/Profit.lua"))("Blackthornes_TS", ns)

local Profit, Cooldowns = ns.Profit, ns.Cooldowns
ns.CraftTime:OnEnable()

local auction = { [MOONCLOTH] = 20000, [FELCLOTH] = 2000, [BELT] = 3000, [LINEN] = 100,
    [GOLD] = 30000, [IRON] = 2000, [ARCANITE] = 90000, [THORIUM] = 3000 }
ns.Prices.GetValue = function(_, id) return auction[id] end
ns.Prices.GetUnitsSoldPerDay = function() return 4 end
ns.Profit.GetCraftableCount = function() return 6 end

local passed, failed = 0, 0
local function check(label, got, want)
    local ok = got == want
    if type(got) == "number" and type(want) == "number" then ok = math.abs(got - want) < 1e-6 end
    if ok then passed = passed + 1 else failed = failed + 1 end
    print(string.format("  %-62s %-12s %s", label, tostring(got), ok and "ok" or
        ("WRONG, wanted " .. tostring(want))))
end

print("")
print("A DAY counts one per wait")

local moon = Profit:Analyse(MOON_RECIPE, nil, "auction")
check("Mooncloth is a craft with a wait", type(moon.cooldown), "table")
check("its wait is Classic's 4 days", moon.cooldown.wait, 4 * 86400)
check("A DAY counts 0.25, not the 4 that sell", moon.perDaySells, 0.25)
check("A DAY is the profit each times 0.25", moon.perDay, moon.profitPerUnit * 0.25)
check("and says the wait cut it", moon.perDayByWait, true)
check("Keep in stock did not", moon.perDayCapped, false)

local belt = Profit:Analyse(BELT_RECIPE, nil, "auction")
check("a plain craft has no wait", belt.cooldown, nil)
check("and still counts the 4 that sell", belt.perDaySells, 4)
check("not cut by any wait", belt.perDayByWait, false)

ns.Prices.GetUnitsSoldPerDay = function() return 0.1 end
moon = Profit:Analyse(MOON_RECIPE, nil, "auction")
check("selling fewer than the wait allows counts what sells", moon.perDaySells, 0.1)
check("and the wait did not cut it", moon.perDayByWait, false)
ns.Prices.GetUnitsSoldPerDay = function() return 4 end

local gold = Profit:Analyse(IRON_GOLD, nil, "auction")
check("a transmute is a craft with a wait", type(gold.cooldown), "table")
check("Iron to Gold waits 2 days, so counts 0.5", gold.perDaySells, 0.5)

print("")
print("the wait the game says")

C_Spell = { GetSpellCooldown = function(id)
    if id == MOON_RECIPE then return { startTime = 5000 - 60, duration = 3 * 86400 } end
    return { startTime = 0, duration = 0 }
end }
Cooldowns:Read()
local entry = ns.db.professionCooldowns[ME]["spell:" .. MOON_RECIPE]
check("casting it saves the wait beside readyAt", entry.wait, 3 * 86400)
check("and readyAt is when it is back", entry.readyAt, NOW + 3 * 86400 - 60)
check("the saved wait beats Classic's", Cooldowns:WaitFor(MOON_RECIPE), 3 * 86400)
moon = Profit:Analyse(MOON_RECIPE, nil, "auction")
check("so A DAY counts one every 3 days", moon.perDaySells, 1 / 3)
check("a craft with no length known is one a day", Cooldowns:WaitFor(1317279), 86400)

C_Spell = { GetSpellCooldown = function() return { startTime = 4999, duration = 1.5 } end }
Cooldowns:Read()
check("the global cooldown never changes the saved wait", entry.wait, 3 * 86400)
C_Spell = nil

print("")
print("Ready, or the time left")

fresh()
moon = Profit:Analyse(MOON_RECIPE, nil, "auction")
check("never cast: ready", Profit.CooldownReadyAt(moon), nil)
check("MAKE is 1 when ready, though 6 could be made", Profit.MakeNow(moon), 1)
check("the mark says Ready",
    Profit.WithCooldownMark("Mooncloth", moon):find("|cff4fd17aReady|r", 1, true) ~= nil, true)
check("a plain craft's name has no mark", Profit.WithCooldownMark("Linen Belt", belt), "Linen Belt")
check("a plain craft's MAKE is its count", Profit.MakeNow(belt), 6)

ns.db.professionCooldowns[ME] = { ["spell:" .. MOON_RECIPE] = { name = "Mooncloth", group = "Mooncloth",
    recipeID = MOON_RECIPE, readyAt = NOW + 2 * 86400 + 6 * 3600, seen = true } }
moon = Profit:Analyse(MOON_RECIPE, nil, "auction")
check("waiting: ready at the saved time", Profit.CooldownReadyAt(moon), NOW + 2 * 86400 + 6 * 3600)
check("MAKE is 0 while it waits", Profit.MakeNow(moon), 0)
check("the mark shows the time left, muted",
    Profit.WithCooldownMark("Mooncloth", moon):find("|cff857c682d 6h|r", 1, true) ~= nil, true)

ns.db.professionCooldowns[ALT] = { ["spell:" .. MOON_RECIPE] = { name = "Mooncloth", group = "Mooncloth",
    recipeID = MOON_RECIPE, readyAt = NOW + 3600, seen = true } }
check("All Characters: the soonest who knows it", Profit.CooldownReadyAt(moon, true), NOW + 3600)
ns.db.professionCooldowns[ALT]["spell:" .. MOON_RECIPE].readyAt = NOW - 10
check("All Characters: ready when any one has it ready", Profit.CooldownReadyAt(moon, true), nil)
check("without All Characters: still the one who would make it",
    Profit.CooldownReadyAt(moon), NOW + 2 * 86400 + 6 * 3600)

print("")
print("transmutes share one wait")

ns.db.professionCooldowns[ME]["spell:" .. ARCANITE_RECIPE] = { name = "Transmute: Arcanite",
    group = "Transmute", recipeID = ARCANITE_RECIPE, readyAt = NOW + 5 * 3600, seen = true }
gold = Profit:Analyse(IRON_GOLD, nil, "auction")
check("Arcanite cast: Iron to Gold waits too", Profit.CooldownReadyAt(gold), NOW + 5 * 3600)
check("and shows the same time left",
    Profit.WithCooldownMark("Transmute: Iron to Gold", gold):find("5h 0m", 1, true) ~= nil, true)
check("each counts its own length: Iron to Gold 0.5 a day", gold.perDaySells, 0.5)

print("")
print("GOLD/HR")

ns.HourPlans = { IsOn = function() return true end, For = function() return { best = { perHour = 5000 } } end }
moon = Profit:Analyse(MOON_RECIPE, nil, "auction")
check("a craft with a wait has no gold an hour", moon.hourPlans, nil)
belt = Profit:Analyse(BELT_RECIPE, nil, "auction")
check("a plain craft keeps its gold an hour", belt.hourPlans and belt.hourPlans.best.perHour, 5000)
ns.HourPlans = nil

print("")
print("the tooltip lines")

check("every 4 days", Profit.CooldownWaitText(4 * 86400), "You can make one every 4 days.")
check("a day", Profit.CooldownWaitText(86400), "You can make one a day.")
check("every 20 hours", Profit.CooldownWaitText(20 * 3600), "You can make one a day.")
check("every 8 hours", Profit.CooldownWaitText(8 * 3600), "You can make one every 8 hours.")
check("0.25 written short", Profit.CountText(0.25), "0.25")
check("0.5 written short", Profit.CountText(0.5), "0.5")
check("1 written short", Profit.CountText(1), "1")

ns.db.professionCooldowns[ALT] = nil
moon = Profit:Analyse(MOON_RECIPE, nil, "auction")
local lines = Profit.CooldownLines(moon, false, true)
check("first how often", lines[1] and lines[1].text, "You can make one every 4 days.")
check("then what A DAY counts", lines[2] and lines[2].text, "So it counts 0.25 a day.")
check("then the time left", lines[3] and lines[3].text, "Ready in 2d 6h")
ns.db.professionCooldowns[ME] = nil
lines = Profit.CooldownLines(Profit:Analyse(MOON_RECIPE, nil, "auction"), false, true)
check("ready: the last line says Ready", lines[3] and lines[3].text, "Ready")
check("in green", lines[3] and lines[3].ready, true)
check("a plain craft has no lines", #Profit.CooldownLines(belt, false, true), 0)

for _, key in ipairs(GLOBALS) do _G[key] = saved[key] end

print("")
print(string.format("  %d passed, %d failed", passed, failed))
if failed > 0 then error(failed .. " cooldown craft check(s) failed") end
