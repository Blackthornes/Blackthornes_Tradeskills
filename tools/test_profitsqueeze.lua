-- The Profit tab with every column on (Per hour ticked) at a narrow width:
-- the columns ran over the craft names and each other (a player's
-- screenshot, 2026-10-15). The least needed are set aside until there is
-- room, and COST, SELLS, PROFIT, TIME and A DAY always stay.

-- Tests share one Lua state, so every global replaced here is put back,
-- including the ones that were not set at all.
local GLOBALS = { "CreateFrame", "UIParent", "GameTooltip", "C_Timer", "GetTime" }
local saved = {}
for _, key in ipairs(GLOBALS) do saved[key] = _G[key] end

local function noop() end

-- Frames whose methods do nothing unless named here; fields read as nil.
local function NewFrame(kind)
    local f = { kind = kind, scripts = {}, shown = true, text = "", points = {} }

    setmetatable(f, { __index = function(_, k)
        if type(k) == "string" and k:match("^%u") then return noop end
    end })

    f.SetScript = function(self, n, fn) self.scripts[n] = fn end
    f.GetScript = function(self, n) return self.scripts[n] end
    f.HookScript = function(self, n, fn)
        local old = self.scripts[n]
        self.scripts[n] = function(...) if old then old(...) end fn(...) end
    end
    f.Show = function(self) self.shown = true end
    f.Hide = function(self) self.shown = false end
    f.SetShown = function(self, v) self.shown = v and true or false end
    f.IsShown = function(self) return self.shown end
    f.IsVisible = function(self) return self.shown end
    f.SetText = function(self, t) self.text = t end
    f.GetText = function(self) return self.text end
    f.SetTextColor = function(self, color) self.color = color end
    f.SetWordWrap = function(self, wrap) self.wrap = wrap end
    f.GetStringWidth = function(self) return #tostring(self.text or "") * 6 end
    f.CreateTexture = function() return NewFrame() end
    f.CreateFontString = function() return NewFrame() end
    -- Each anchor point remembers where it was last put.
    f.SetPoint = function(self, point, ...) self.points[point] = { ... } end
    f.ClearAllPoints = function(self) self.points = {} end
    f.GetParent = function() return NewFrame() end
    f.HasFocus = function() return false end
    return f
end

CreateFrame = function(kind) return NewFrame(kind) end
UIParent = NewFrame()
GameTooltip = NewFrame()
C_Timer = { After = noop, NewTicker = function() return { Cancel = noop } end }
GetTime = function() return 1000 end

local passed, failed = 0, 0
local function check(label, got, want)
    local ok = got == want
    if ok then passed = passed + 1 else failed = failed + 1 end
    print(string.format("  %-62s %-14s %s", label, tostring(got), ok and "ok" or
        ("WRONG, wanted " .. tostring(want))))
end

local ns = {}
ns.COLORS = setmetatable({}, { __index = function() return "ffffffff" end })
ns.NewModule = function(name) local m = {}; ns[name] = m; return m end
ns.RegisterCommand, ns.RegisterEvent = noop, noop
local said = {}
ns.Print = function(text) said[#said + 1] = text end
ns.PrintRaw, ns.Debug, ns.Warn = noop, noop, noop

-- Every label, with the frame it was made on; the detail pane is the one
-- panel made as a "window".
local labels, detail = {}, nil
ns.Theme = setmetatable({
    FONT = "font",
    sizes = { tiny = 10, small = 11, normal = 12, large = 14, title = 16 },
    CreateLabel = function(parent)
        local label = NewFrame("FontString")
        label.parent = parent
        labels[#labels + 1] = label
        return label
    end,
    CreatePanel = function(_, background)
        local panel = NewFrame("Frame")
        if background == "window" then detail = panel end
        return panel
    end,
    Unpack = function(key) return key end,
    ProfitColor = function(value) return (value or 0) >= 0 and "profit" or "loss" end,
    CreateHeading = function() local h = NewFrame(); h.rule = NewFrame(); return h end,
    -- Dropdown faces set their words through FitText; nothing is measured.
    FitText = function(label, texts) label:SetText(texts[1]); return texts[1] end,
    TextWidth = function() return nil end,
}, { __index = function(_, k)
    if type(k) == "string" and k:match("^%u") then return function() return NewFrame() end end
end })

local settings = { profitBy = "best", profitShowsPerHour = true }
ns.Config = { Get = function(_, key) return settings[key] end, Set = function(_, key, value) settings[key] = value end }
ns.Util = {
    GetItemQualityColor = noop,
    FormatMoney = function(copper) return tostring(copper or 0) end,
    FormatAge = function() return "1h" end,
    GetItemLabel = function(itemID) return "item" .. tostring(itemID) end,
    HasFunction = function() return false end,
}

assert(loadfile(lfs_cwd .. "/UI/Widgets.lua"))("Blackthornes_TS", ns)
-- The real Profit module, for MaxCrafts; the list and the analyses are
-- this test's own.
assert(loadfile(lfs_cwd .. "/Logic/Profit.lua"))("Blackthornes_TS", ns)

local dropdowns, buttons, list = {}, {}, nil
local realDropdown, realButton = ns.Widgets.CreateDropdown, ns.Widgets.CreateButton
ns.Widgets.CreateDropdown = function(...)
    local dropdown = realDropdown(...)
    dropdowns[#dropdowns + 1] = dropdown
    return dropdown
end
ns.Widgets.CreateButton = function(parent, text, onClick, opts)
    buttons[text] = onClick
    return realButton(parent, text, onClick, opts)
end
ns.Widgets.CreateScrollList = function(_, opts)
    list = NewFrame()
    list.opts = opts
    list.SetData = function(self, data) self.data = data end
    return list
end

-- One craft: Keep in stock 5, nothing held, materials for 10 crafts.
local LIMIT, queued = 5, 0
local extra = {}
local function Analysis(recipeID)
    local room = math.max(0, LIMIT - queued)
    local analysis = { recipeID = recipeID or 1, name = "Linen Bag", outputItemID = 11, priceable = true,
        totalCost = 90, revenue = 700, unitRevenue = 700, cut = 35, profit = 575, margin = 0.8,
        craftableNow = 10, cost = { reagents = {} }, stock = 0, posted = 0, onHand = 0, inMail = 0,
        queuedElsewhere = queued, postLimit = LIMIT, postRoom = room, roomInCrafts = room,
        atPostLimit = room <= 0, priceBasis = "market", depositKnown = true, deposit = 6 }
    for key, value in pairs(extra) do analysis[key] = value end
    return analysis
end

local tabs = {}
ns.UI = setmetatable({ RegisterTab = function(_, tab) tabs[tab.key] = tab end },
    { __index = function(_, k) if type(k) == "string" and k:match("^%u") then return noop end end })

ns.Profit.GetRanked = function() return { Analysis() } end
ns.Profit.Analyse = function(_, recipeID) return Analysis(recipeID) end
ns.Recipes = { Count = function() return 1 end, GetAll = function() return {} end,
    GetAccountWide = function() return {} end, IsDropped = function() return false end }
ns.Prices = { Count = function() return 1 end }
ns.Auctions = { SetLimit = noop }
ns.db = { characters = {} }

-- Queue:Add redraws the tab before it returns, as Logic/Queue.lua does:
-- Queue:Notify, UI:OnQueueUpdated, UI:RefreshActiveTab, the tab's refresh.
ns.Queue = { Add = function(_, _, count)
    queued = queued + count
    tabs.profit.refresh()
    return true
end }

assert(loadfile(lfs_cwd .. "/UI/Columns.lua"))("Blackthornes_TS", ns)

assert(loadfile(lfs_cwd .. "/UI/Tab_Profit.lua"))("Blackthornes_TS", ns)

tabs.profit.build(NewFrame())
tabs.profit.onShow()
tabs.profit.refresh()

local function Label(text)
    for _, label in ipairs(labels) do
        if label.text == text then return label end
    end
end

local headings = Label("CRAFT").parent
local width = 0
headings.GetWidth = function() return width end
local function Resize(to)
    width = to
    headings.scripts.OnSizeChanged()
end

local function Shown(text) return Label(text).shown end

print("")
print("columns at the list's width")

Resize(2000)
check("wide: AGE shows", Shown("AGE"), true)
check("wide: VIA shows", Shown("VIA"), true)
check("wide: A DAY shows", Shown("A DAY"), true)

Resize(800)
check("narrow: AGE is set aside", Shown("AGE"), false)
check("narrow: VIA is set aside", Shown("VIA"), false)
check("narrow: MAKE stays, it fits now", Shown("MAKE"), true)
check("narrow: TIME stays", Shown("TIME"), true)
check("narrow: A DAY stays", Shown("A DAY"), true)
check("narrow: COST stays", Shown("COST"), true)
check("narrow: PROFIT stays", Shown("PROFIT"), true)

Resize(300)
check("very narrow: COST still stays", Shown("COST"), true)
check("very narrow: A DAY still stays", Shown("A DAY"), true)
check("very narrow: MARGIN goes", Shown("MARGIN"), false)

settings.profitShowsPerHour = false
Resize(800)
check("Per hour off at the same width: AGE comes back", Shown("AGE"), true)
check("and VIA", Shown("VIA"), true)
check("and TIME is gone", Shown("TIME"), false)

Resize(0)
check("a width not known yet sets nothing aside", Shown("AGE"), true)

for _, key in ipairs(GLOBALS) do _G[key] = saved[key] end

print("")
print(string.format("%d passed, %d failed", passed, failed))
if failed > 0 then error(failed .. " check(s) failed") end
