-- A list's rows stay where they are when a redraw moves nothing.
--
-- Every redraw of every list took each row off the list and pinned it back
-- where it already was, and painted its band again. In the game that lays
-- the row and everything on it out again, for every row on show, on every
-- refresh. Now a row is placed only when it moved and painted only when its
-- band or the look changed. What must hold:
--   1. A second draw of the same list places and paints nothing.
--   2. Scrolling keeps each row frame where it is and still shows new data.
--   3. A scrollbar coming or going places the rows again (they give it room).
--   4. Picking a row paints that row and the one let go, no others.
--   5. New colours in the table (the Blizzard window style) paint every row.

local saved = { CreateFrame = CreateFrame, UIParent = UIParent, GameTooltip = GameTooltip,
    C_Timer = C_Timer, GetTime = GetTime }

local function noop() end

-- Frames whose methods do nothing unless named here; fields read as nil. Edit
-- boxes keep focus the game's way: only SetFocus, ClearFocus and hiding
-- change it, and losing it runs OnEditFocusLost.
local function NewFrame()
    local f = { scripts = {}, shown = true, text = "", height = 0, width = 0, points = {} }

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
    f.Hide = function(self)
        self.shown = false
        if self.focus then self:ClearFocus() end
    end
    f.SetShown = function(self, v) if v then self:Show() else self:Hide() end end
    f.IsShown = function(self) return self.shown end
    f.IsVisible = function(self) return self.shown end
    f.SetText = function(self, t) self.text = t end
    f.GetText = function(self) return self.text end
    f.SetHeight = function(self, h) self.height = h end
    f.GetHeight = function(self) return self.height end
    f.SetWidth = function(self, w) self.width = w end
    f.GetWidth = function(self) return self.width end
    f.SetSize = function(self, w, h) self.width, self.height = w, h end
    f.GetStringWidth = function(self) return #tostring(self.text or "") * 6 end
    f.CreateTexture = function() return NewFrame() end
    f.CreateFontString = function() return NewFrame() end
    f.SetMinMaxValues = function(self, a, b) self.minv, self.maxv = a, b end
    f.GetMinMaxValues = function(self) return self.minv or 0, self.maxv or 0 end
    f.SetValue = function(self, v) self.value = v end
    f.GetValue = function(self) return self.value or 0 end
    f.IsMouseOver = function() return false end
    f.SetPoint = function(self, ...) self.points[#self.points + 1] = { ... } end
    f.ClearAllPoints = function(self) self.points = {} end
    f.GetNumPoints = function(self) return #self.points end
    f.SetFocus = function(self) self.focus = true end
    f.HasFocus = function(self) return self.focus == true end
    f.ClearFocus = function(self)
        if self.focus then
            self.focus = false
            if self.scripts.OnEditFocusLost then self.scripts.OnEditFocusLost(self) end
        end
    end

    return f
end

CreateFrame = function() return NewFrame() end
UIParent = NewFrame()
GameTooltip = NewFrame()
C_Timer = { After = noop, NewTicker = function() return { Cancel = noop } end }
GetTime = function() return 1000 end

local function Theme()
    return {
        FONT = "font",
        sizes = { tiny = 10, small = 11, normal = 12, large = 14, title = 16 },
        -- The dropdowns fit their words with these; the full wording here.
        FitText = function(label, texts) label:SetText(texts[1]); return texts[1] end,
        -- Measured as the real one measures: unbounded first.
        TextWidth = function(label)
            for _, method in ipairs({ "GetUnboundedStringWidth", "GetStringWidth" }) do
                local ok, width = pcall(label[method], label)
                if ok and type(width) == "number" and width > 0 then return width end
            end
        end,
        Fill = function() return NewFrame() end,
        Unpack = function() return 1, 1, 1, 1 end,
        Border = noop, SetBorderColor = noop, TopSheen = noop, AddGameOutline = noop,
        Halo = noop, SetHalo = noop, HeaderGlow = noop, SetGradientAlpha = noop,
        GlowBand = function() return NewFrame() end,
        AccentStripe = function() return NewFrame() end,
        CreatePanel = function() return NewFrame() end,
        CreateLabel = function() return NewFrame() end,
        CreateDivider = function() return NewFrame() end,
        CreateItemIcon = function() return NewFrame() end,
        SetItemIcon = noop,
        SetMoneyText = function(label, copper) label:SetText(tostring(copper)) end,
        SetRowName = function(label, text) label:SetText(text) end,
        CreateHeading = function() local h = NewFrame(); h.rule = NewFrame(); return h end,
        ProfitColor = function() return 1, 1, 1, 1 end,
    }
end

local function NewNamespace()
    local ns = {}
    ns.COLORS = setmetatable({}, { __index = function() return "ffffffff" end })
    ns.NewModule = function(name) local m = {}; ns[name] = m; return m end
    ns.RegisterCommand = noop
    ns.RegisterEvent = noop
    ns.Print, ns.PrintRaw, ns.Debug, ns.Warn = noop, noop, noop, noop

    ns.db = {}
    ns.Config = { Get = function(_, k) if k == "postDuration" then return 2 end end, Set = noop }
    ns.Scanner = { isAuctionHouseOpen = true, isScanning = false, IsCommodity = function() return true end }
    ns.Prices = { GetValue = function() return nil end }
    ns.Inventory = { GetCarriedBags = function() return {} end, GetBagCount = function() return 0 end }
    ns.Recipes = { GetAccountWide = function() return {} end }
    ns.Queue = { GetShoppingList = function() return {} end }
    ns.Cost = { FindRecipeForItem = function() return nil end }
    ns.Cost.FindAnyRecipeForItem = ns.Cost.FindRecipeForItem
    ns.Theme = Theme()
    return ns
end

local function Load(ns, path)
    assert(loadfile(lfs_cwd .. path))("Blackthornes_TS", ns)
end

local passed, failed = 0, 0

local function check(label, got, want)
    local ok = got == want
    if ok then passed = passed + 1 else failed = failed + 1 end
    print(string.format("  %-58s %-8s %s", label, tostring(got), ok and "ok" or
        ("WRONG, wanted " .. tostring(want))))
end


print("")
print("Rows stay put when nothing moved")

do
    local ns = NewNamespace()
    ns.Theme.colors = { glass = { 0, 0, 0 }, glassAlt = { 0.1, 0.1, 0.1 }, glassActive = { 0.2, 0.2, 0.2 } }
    Load(ns, "/Core/Util.lua")
    Load(ns, "/UI/Widgets.lua")

    local places, paints, updates = 0, 0, 0
    local picked
    local list = ns.Widgets.CreateScrollList(NewFrame(), {
        rowHeight = 20,
        isSelected = function(entry) return entry == picked end,
        createRow = function(row)
            local clear = row.ClearAllPoints
            row.ClearAllPoints = function(self) places = places + 1; clear(self) end
            row.background.SetColorTexture = function() paints = paints + 1 end
        end,
        updateRow = function() updates = updates + 1 end,
    })
    list.height = 100

    local data = {}
    for i = 1, 5 do data[i] = { id = i } end
    list:SetData(data)
    check("five rows fit and are placed once each", places, 5)
    check("and painted once each", paints, 5)
    check("each row is pinned by two points", list.rows[3]:GetNumPoints(), 2)

    places, paints, updates = 0, 0, 0
    list:Refresh()
    check("a second draw places nothing", places, 0)
    check("and paints nothing", paints, 0)
    check("but every row is still filled in", updates, 5)

    -- 4. Picking a row.
    picked = data[2]
    list:Refresh()
    check("picking a row paints only that row", paints, 1)
    picked = data[4]
    paints = 0
    list:Refresh()
    check("picking another paints the two that changed", paints, 2)
    check("and still places nothing", places, 0)

    -- 5. The look changed: new colour tables under the same names.
    paints = 0
    ns.Theme.colors.glass = { 0.3, 0.3, 0.3 }
    ns.Theme.colors.glassAlt = { 0.4, 0.4, 0.4 }
    list:Refresh()
    check("new colours paint the rows that wear them", paints, 4)

    -- 3 and 2. More entries than fit: a scrollbar shows, then scrolling.
    for i = 6, 30 do data[i] = { id = i } end
    places = 0
    list:SetData(data)
    check("a scrollbar coming places the rows again", places, 5)

    places = 0
    list.scrollbar:SetValue(3)
    check("scrolled, the first row shows the fourth entry", list.rows[1].data, data[4])
    check("and no row frame was placed again", places, 0)

    places = 0
    list:SetData({ data[1], data[2] })
    check("the scrollbar going places the rows again", places, 2)
    check("and the spare rows are hidden", list.rows[3]:IsShown(), false)
end

for name, value in pairs(saved) do _G[name] = value end
for _, name in ipairs({ "CreateFrame", "UIParent", "GameTooltip", "C_Timer", "GetTime" }) do
    if saved[name] == nil then _G[name] = nil end
end

print("")
print(string.format("%d passed, %d failed", passed, failed))
if failed > 0 then error(failed .. " check(s) failed") end
