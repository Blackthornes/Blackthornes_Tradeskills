-- Picking a sale on the Sales tab, outside WoW.
--
-- A sale mail carries no item, only its name, so a sale of something no
-- recipe makes is recorded by name. By item files it under the id another
-- entry gave that name (an expiry comes back as the item itself). Clicking
-- the sale built a "?name" key instead: nothing was selected, and the item's
-- sales were never lit when it was picked from By item.

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

local detailTitle
ns.Theme = setmetatable({
    Unpack = function() return 1, 1, 1, 1 end,
    CreateLabel = function(_, size)
        local label = Frame()
        if size == "large" then detailTitle = label end
        return label
    end,
}, { __index = function() return function() return Frame() end end })

local LINEN = 2589
ns.db = { mailLedger = { ["Realm-Alliance"] = { seen = {}, entries = {
    { t = 90000, kind = "expired", who = "Player-1", name = "Linen Cloth", itemID = LINEN, quantity = 20 },
    { t = 95000, kind = "sold", who = "Player-1", name = "Linen Cloth", net = 570, cut = 30 },
} } } }

assert(loadfile(lfs_cwd .. "/Core/Util.lua"))("Blackthornes_TS", ns)
assert(loadfile(lfs_cwd .. "/Data/Mail.lua"))("Blackthornes_TS", ns)

local listOpts, listData
ns.Widgets = {
    CreateSearchBox = function() return Frame() end,
    CreateDropdown = function() return Frame() end,
    CreateTabStrip = function() local strip = Frame() strip.Select = function() end return strip end,
    CreateScrollList = function(_, opts)
        listOpts = opts
        local list = Frame()
        list.SetData = function(_, data) listData = data end
        return list
    end,
}

local tab
ns.UI = { RegisterTab = function(_, def) tab = def end }
ns.MailHaul = { GetHistory = function() return {} end, Records = function() return 0 end }
-- Gold in and out draws in its own frames, never asserted on here.
ns.GoldChart = { CreateChart = function() return Frame() end, CreateLegend = function() return Frame() end }

assert(loadfile(lfs_cwd .. "/UI/Tab_Sales.lua"))("Blackthornes_TS", ns)
tab.build(Frame())
tab.refresh()

local passed, failed = 0, 0

local function check(label, got, want)
    local ok = got == want
    if ok then passed = passed + 1 else failed = failed + 1 end
    print(string.format("  %-56s %-8s %s", label, tostring(got), ok and "ok" or
        ("WRONG, wanted " .. tostring(want))))
end

print("")
print("a sale recorded by name only")

local sale = listData[1]
check("the newest row is the sale", sale.kind, "sold")
check("which has no item id", sale.itemID, nil)

listOpts.onClick(sale)
check("clicking it selects it", listOpts.isSelected(sale), true)
check("and the pane shows its item", detailTitle and detailTitle:GetText() ~= "Everything", true)

listOpts.onClick(sale)
check("clicking again lets it go", listOpts.isSelected(sale), false)

for _, item in ipairs(ns.Mail:GetItems()) do listOpts.onClick(item) end
check("picked from By item, its sale is lit", listOpts.isSelected(sale), true)

for _, key in ipairs(GLOBALS) do _G[key] = saved[key] end

print("")
print(("%d passed, %d failed"):format(passed, failed))
assert(failed == 0, "sales selection checks failed")
