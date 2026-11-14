-- The Sales tab's footer while a search is typed, outside WoW.
--
-- A player searched one item and the footer still said "102 sold" with the
-- sell-through of everything, while the item's tooltip said 58. The footer
-- and the Everything panel now count only what the search shows.

local GLOBALS = { "CreateFrame", "UIParent", "GameTooltip", "C_Timer", "GetTime", "time" }
local saved = {}
for _, key in ipairs(GLOBALS) do saved[key] = _G[key] end

local function noop() end

local function Frame()
    local f = { text = "" }
    f.SetText = function(self, t) self.text = t end
    f.GetText = function(self) return self.text end
    return setmetatable(f, { __index = function(_, k)
        if type(k) == "string" and k:match("^%u") then return noop end
    end })
end

CreateFrame = function() return Frame() end
UIParent, GameTooltip = Frame(), Frame()
C_Timer = { After = noop, NewTicker = function() return { Cancel = noop } end }
GetTime = function() return 1000 end
time = function() return 100000 end

local ns = {}
ns.COLORS = setmetatable({}, { __index = function() return "ffffffff" end })
ns.NewModule = function(name) local m = {}; ns[name] = m; return m end
ns.RegisterCommand, ns.RegisterEvent = noop, noop
ns.Print, ns.PrintRaw, ns.Debug, ns.Warn = noop, noop, noop, noop
ns.Config = {
    GetRealmKey = function() return "Realm-Alliance" end,
    GetCharacterKey = function() return "Player-1" end,
    Get = noop,
}
ns.Recipes = { GetAccountWide = function() return {} end, GetAll = function() return {} end,
    GetCharacterRecord = noop }

local labels = {}
ns.Theme = setmetatable({
    Unpack = function() return 1, 1, 1, 1 end,
    CreateLabel = function()
        local label = Frame()
        labels[#labels + 1] = label
        return label
    end,
}, { __index = function() return function() return Frame() end end })

local LINEN, WOOL = 2589, 2592
local entries = {}
local function add(kind, name, id, t)
    entries[#entries + 1] = { t = t, kind = kind, who = "Player-1", name = name, itemID = id,
        quantity = 1, net = kind == "sold" and 100 or nil, cut = kind == "sold" and 5 or nil }
end
-- Linen: 3 sold, 1 expired. Wool: 1 sold, 3 expired.
for i = 1, 3 do add("sold", "Linen Cloth", LINEN, 90000 + i) end
add("expired", "Linen Cloth", LINEN, 90010)
add("sold", "Wool Cloth", WOOL, 91000)
for i = 1, 3 do add("expired", "Wool Cloth", WOOL, 91010 + i) end
ns.db = { mailLedger = { ["Realm-Alliance"] = { seen = {}, entries = entries } } }

assert(loadfile(lfs_cwd .. "/Core/Util.lua"))("Blackthornes_TS", ns)
assert(loadfile(lfs_cwd .. "/Data/Mail.lua"))("Blackthornes_TS", ns)

local onSearch
ns.Widgets = {
    CreateSearchBox = function(_, _, fn) onSearch = fn return Frame() end,
    CreateDropdown = function() return Frame() end,
    CreateTabStrip = function() local strip = Frame() strip.Select = function() end return strip end,
    CreateButton = function() return Frame() end,
    CreateScrollList = function() local list = Frame() list.SetData = noop return list end,
}

local tab
ns.UI = { RegisterTab = function(_, def) tab = def end }
ns.MailHaul = { GetHistory = function() return {} end, Records = function() return 0 end }
ns.GoldChart = { CreateChart = function() return Frame() end, CreateLegend = function() return Frame() end }

assert(loadfile(lfs_cwd .. "/UI/Tab_Sales.lua"))("Blackthornes_TS", ns)
tab.build(Frame())
tab.refresh()

local function footer()
    for _, label in ipairs(labels) do
        local text = label:GetText() or ""
        if text:match("^%d+ sold") then return text end
    end
end

local passed, failed = 0, 0
local function check(label, got, want)
    local ok = got == want
    if ok then passed = passed + 1 else failed = failed + 1 end
    print(string.format("  %-46s %-10s %s", label, tostring(got), ok and "ok" or
        ("WRONG, wanted " .. tostring(want))))
end

print("")
print("the footer follows the search")

local text = footer() or ""
check("no search: every sale", text:match("^(%d+) sold"), "4")
check("no search: 50% sell-through", text:match("(%d+)%% sell") , "50")

onSearch("linen")
text = footer() or ""
check("searching linen: its 3 sales", text:match("^(%d+) sold"), "3")
check("searching linen: 75% sell-through", text:match("(%d+)%% sell"), "75")

onSearch("wool")
text = footer() or ""
check("searching wool: its 1 sale", text:match("^(%d+) sold"), "1")
check("searching wool: 25% sell-through", text:match("(%d+)%% sell"), "25")

onSearch("")
text = footer() or ""
check("search cleared: every sale again", text:match("^(%d+) sold"), "4")

for _, key in ipairs(GLOBALS) do _G[key] = saved[key] end

print("")
print(("%d passed, %d failed"):format(passed, failed))
assert(failed == 0, "sales search checks failed")
