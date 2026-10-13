-- A list that draws again while it draws, outside WoW.
--
-- On the Level Up tab (2026-10-13) the list's Refresh read its height,
-- the game settled its layout right there and ran OnSizeChanged, which
-- called Refresh again, whose rows laid their columns out again, and so on
-- until "C stack overflow". What must hold:
--   1. A Refresh that comes while one is drawing does not draw inside it;
--      it gets one more pass after, a few at most, and the rows are drawn.
--   2. An error while drawing still lets the next Refresh draw.
--   3. OnSizeChanged for the size already drawn does nothing.

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
print("A list that draws again while it draws")

do
    local ns = NewNamespace()
    Load(ns, "/Core/Util.lua")
    Load(ns, "/UI/Widgets.lua")

    local list
    local updates, raise = 0, false
    list = ns.Widgets.CreateScrollList(NewFrame(), {
        rowHeight = 20,
        -- Each row's mouse check settles the layout, as IsMouseOver does.
        createRow = function(row)
            row.IsMouseOver = function() list:GetHeight(); return false end
        end,
        updateRow = function(row, entry)
            updates = updates + 1
            if raise then error("broken row") end
            -- Laying a row out leaves the list's layout to settle again,
            -- as anchoring did in the game, and the next row's mouse check
            -- settles it.
            list.dirty = true
        end,
    })

    -- The game's way: reading the height of a list whose layout moved
    -- runs OnSizeChanged there and then, before the read returns, and a
    -- layout that keeps moving gives a slightly different size each time.
    local depth, deepest, flip = 0, 0, false
    list.height = 200
    list.GetHeight = function(self)
        if self.dirty then
            depth = depth + 1
            if depth > deepest then deepest = depth end
            flip = not flip
            self.scripts.OnSizeChanged(self, 300, flip and 200 or 201)
            self.dirty = false
            depth = depth - 1
        end
        return self.height
    end

    local data = {}
    for i = 1, 30 do data[i] = { id = i } end
    local ok, err = pcall(list.SetData, list, data)
    check("SetData finishes without running out of stack", ok, true)
    if not ok then print("    " .. tostring(err)) end
    check("drawing never starts inside a draw", deepest <= 1, true)
    check("a few passes at most", updates <= 10 * 3, true)
    check("the first row is drawn", list.rows[1] and list.rows[1].data == data[1], true)
    check("and not left marked as drawing", list:IsDrawing(), false)

    -- 2. A row that raises: the error comes out, and the next draw runs.
    raise = true
    list.dirty = false
    local raised = not pcall(list.Refresh, list)
    check("an error while drawing comes out", raised, true)
    check("and leaves the list free to draw", list:IsDrawing(), false)
    raise = false
    updates = 0
    list.dirty = false
    list:Refresh()
    check("so the next Refresh draws the rows", updates > 0, true)

    -- 3. The same size twice: drawn once.
    list.GetHeight = function(self) return self.height end
    list.scripts.OnSizeChanged(list, 300, 200)
    updates = 0
    list.scripts.OnSizeChanged(list, 300, 200)
    check("the same size again draws nothing", updates, 0)
    list.scripts.OnSizeChanged(list, 310, 200)
    check("a new size draws", updates > 0, true)
end

for key, value in pairs(saved) do _G[key] = value end

print("")
print(("%d passed, %d failed"):format(passed, failed))
assert(failed == 0, "list redraw checks failed")
