-- Logic/CraftRequests.lua outside WoW.
--
-- Craft requests in Trade (asked 2026-10-12). What must hold:
--   1. A line in Trade that asks for something a character makes (by item
--      link, enchant link or name) says so once, naming who can make it,
--      the character playing as "You", the others by full name.
--   2. A line that sells or offers ("WTS", "LFW", "can make") says nothing,
--      and neither does a line with no asking word.
--   3. The longest name wins ("Heavy Linen Bandage", not "Linen Bandage").
--   4. An enchant is found by its effect and slot.
--   5. One asker and one item are said once in REPEAT_GAP; the player's
--      own lines, other channels and the setting off say nothing.
--   6. A secret value (a raise) is swallowed.
--   7. A new recipe is found once the names are counted again.

local clock = 100
GetTime = function() return clock end
time = function() return clock end
UnitGUID = function() return "Player-1" end
UnitName = function() return "Ana" end
C_Item = { GetItemNameByID = function(itemID)
    return ({ [12360] = "Arcanite Bar", [6450] = "Silk Bandage", [6451] = "Heavy Silk Bandage" })[itemID]
end }

local printed = {}
local ns = { commands = {} }
ns.NewModule = function(name) local m = {} ns[name] = m return m end
ns.RegisterCommand = function(name, _, fn) ns.commands[name] = fn end
ns.Print = function(text) printed[#printed + 1] = text end
local handlers = {}
ns.RegisterEvent = function(_, event, fn) handlers[event] = fn return true end

local ANA, WITHER = "Player-1", "Player-2"
local settings = { tradeRequests = true }
ns.db = { characters = {
    [ANA] = { recipes = {
        [17187] = { name = "Transmute: Arcanite", outputItemID = 12360 },
        [7929] = { name = "Heavy Silk Bandage", outputItemID = 6451 },
    } },
    [WITHER] = { recipes = {
        [17187] = { name = "Transmute: Arcanite", outputItemID = 12360 },
        [7928] = { name = "Silk Bandage", outputItemID = 6450 },
        [7418] = { name = "Enchant Bracer - Minor Health" },
        [13858] = { name = "Enchant Chest - Superior Health" },
    } },
} }
ns.Config = {
    GetCharacterKey = function() return ANA end,
    Get = function(_, key) return settings[key] end,
    Set = function(_, key, value) settings[key] = value end,
}
ns.Recipes = {
    GetCharacterName = function(_, key) return key == WITHER and "Blackthornes Wither" or "Ana Blackthorne" end,
    GetDisplayLink = function(_, recipeID) return "[" .. recipeID .. "]" end,
}

assert(loadfile(lfs_cwd .. "/Logic/CraftRequests.lua"))("Blackthornes_TS", ns)
local CR = ns.CraftRequests
CR:OnEnable()

local failures = 0
local function check(label, got, want)
    if got ~= want then
        failures = failures + 1
        print(string.format("  FAIL  %-52s got %s, wanted %s", label, tostring(got), tostring(want)))
    else
        print(string.format("  ok    %-52s %s", label, tostring(got)))
    end
end

local function Trade(text, sender, guid, channelID)
    local before = #printed
    local name = channelID and "1. General - City" or "2. Trade - City"
    handlers.CHAT_MSG_CHANNEL(nil, "CHAT_MSG_CHANNEL", text, sender or "Bob-Realm", "", name, "", "",
        channelID or 2, channelID or 2, name:sub(4), 0, 1, guid or "Player-9")
    return #printed - before, printed[#printed]
end

print("\nasking by link")
local n, line = Trade("WTB |cffffffff|Hitem:12360::::|h[Arcanite Bar]|h|r pst")
check("said once", n, 1)
check("names the asker as a link", line and line:find("|Hplayer:Bob-Realm|h[Bob]|h", 1, true) ~= nil, true)
check("you and the alt by full name", line and line:find("You and Blackthornes Wither can make it.", 1, true) ~= nil, true)
n = Trade("WTB |Hitem:12360::::|h[Arcanite Bar]|h pst")
check("not again for the same asker", n, 0)
n = Trade("WTB |Hitem:12360::::|h[Arcanite Bar]|h", "Cara-Realm", "Player-8")
check("another asker is said", n, 1)

print("\nselling and offering")
check("WTS says nothing", (Trade("WTS Arcanite Bar 5g", "Dan-Realm")), 0)
check("LFW says nothing", (Trade("LFW can make arcanite bar", "Dan-Realm")), 0)
check("no asking word says nothing", (Trade("arcanite bar prices are crazy", "Dan-Realm")), 0)

print("\nasking by name")
n, line = Trade("LF someone to make heavy silk bandage x20", "Eve-Realm")
check("found by name", n, 1)
check("the longest name", line and line:find("[7929]", 1, true) ~= nil, true)
check("only you make it", line and line:find("You can make it.", 1, true) ~= nil, true)
n, line = Trade("need silk bandage", "Fay-Realm")
check("the shorter one alone", line and line:find("[7928]", 1, true) ~= nil, true)
check("the alt makes it", line and line:find("Blackthornes Wither can make it.", 1, true) ~= nil, true)

print("\nenchants")
n, line = Trade("LF enchanter for superior health chest, tips", "Gil-Realm")
check("tips is an offer word", n, 0)
n, line = Trade("LF enchanter for superior health chest", "Gil-Realm")
check("by effect and slot", line and line:find("[13858]", 1, true) ~= nil, true)
n, line = Trade("anyone |Henchant:7418|h[Enchanting: Enchant Bracer - Minor Health]|h ?", "Hal-Realm")
check("by enchant link", line and line:find("[7418]", 1, true) ~= nil, true)

print("\nwho and where")
check("your own line says nothing", (Trade("WTB arcanite bar", "Ana-Realm", "Player-1")), 0)
check("another player with your first name is heard", (Trade("WTB arcanite bar", "Ana-Otherrealm", "Player-4")), 1)
check("another channel says nothing", (Trade("WTB arcanite bar", "Ivy-Realm", "Player-7", 1)), 0)
settings.tradeRequests = false
check("off says nothing", (Trade("WTB arcanite bar", "Jo-Realm", "Player-6")), 0)
settings.tradeRequests = true
check("a secret value is swallowed", (Trade(setmetatable({}, { __index = function() error("secret") end }), "Kim-Realm")), 0)

print("\nafter a while")
clock = clock + CR.REPEAT_GAP + 1
check("the same asker again, later", (Trade("WTB |Hitem:12360::::|h[Arcanite Bar]|h pst")), 1)
ns.db.characters[ANA].recipes[3275] = { name = "Linen Bandage", outputItemID = 1251 }
clock = clock + CR.REBUILD_GAP + 1
n, line = Trade("need linen bandage", "Lou-Realm")
check("a new recipe is found", line and line:find("[3275]", 1, true) ~= nil, true)

print("\noff by default")
settings.tradeRequests = nil
clock = clock + CR.REPEAT_GAP + 1
check("unset says nothing", (Trade("WTB |Hitem:12360::::|h[Arcanite Bar]|h", "Max-Realm", "Player-5")), 0)
settings.tradeRequests = true

print("\nthe command")
ns.commands.requests("off")
check("off", settings.tradeRequests, false)
ns.commands.requests("")
check("toggled on", settings.tradeRequests, true)

print("")
if failures > 0 then error(string.format("%d craft request check(s) failed", failures)) end
print("  all craft request checks passed")
print("")
