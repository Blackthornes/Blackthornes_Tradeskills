-- Hide losses on the Ready to sell list at the auction house.
--
-- Asked 2026-10-11: a small box that hides the items not worth selling right
-- now, judged by auction value against what they cost. The rows it hides are
-- the ones already drawn red (atALoss). Off by default, kept in settings.

local ns = {}
ns.NewModule = function(name) local m = {}; ns[name] = m; return m end
ns.RegisterCommand = function() end
ns.Print, ns.Debug, ns.Warn = function() end, function() end, function() end

local registeredEvents = {}
ns.RegisterEvent = function(_, event, fn)
    registeredEvents[event] = fn
    return true
end

--------------------------------------------------------------------------------
-- A widget layer that only remembers what was written to it
--------------------------------------------------------------------------------

-- Any method this test does not care about answers as a no-op, so the tab can
-- build its toolbar, headings and detail panel undisturbed.
local function Stub(fields)
    local frame = fields or {}

    frame.GetParent = frame.GetParent or function() return Stub() end
    frame.IsVisible = frame.IsVisible or function() return true end

    return setmetatable(frame, { __index = function(self, key)
        local noop = function() end
        rawset(self, key, noop)
        return noop
    end })
end

local function Label()
    return Stub({
        text = "",
        color = nil,
        SetText = function(self, value) self.text = tostring(value) end,
        SetTextColor = function(self, a, b, c) self.color = { a, b, c } end,
    })
end

CreateFrame = function() return Stub() end
C_Timer = { After = function() end, NewTicker = function() return Stub() end }

ns.Theme = {
    FONT = "font",
    sizes = { tiny = 10, small = 11, normal = 12, large = 14, title = 16 },
    CreateLabel = function() return Label() end,
    CreatePanel = function() return Stub() end,
    CreateDivider = function() return Stub() end,

    -- Palette entries come back as their own name, so an assertion can say
    -- which one a cell was painted with.
    Unpack = function(key) return key end,
    ProfitColor = function(value) return (value or 0) >= 0 and "profit" or "loss" end,

    -- The skill-up star. It remembers the tier it was last set to, so a row
    -- can be asked whether it is wearing one -- false rather than nil, because
    -- the stub answers a missing field with a no-op function.
    CreateMark = function() return Stub({ tier = false }) end,
    SetMark = function(mark, tier) mark.tier = tier or false end,

    -- The house trim: drawn, never asserted on.
    AccentStripe = function() return Stub() end,
    CreateItemIcon = function() return Stub() end,
    SetItemIcon = function() end,
    CreateBar = function() return Stub() end,
    CreateHeading = function() return Stub({ rule = Stub() }) end,
    StyleHeading = function(label) label.rule = Stub(); return label end,
}

ns.Widgets = {
    CreateSearchBox = function() return Stub() end,
    CreateDropdown = function() return Stub() end,
    CreateCheckbox = function() return Stub() end,
    CreateNumberBox = function() return Stub() end,
    CreateButton = function() return Stub() end,
}


ns.Util = { GetItemQualityColor = function() end, FormatMoney = function(c) return tostring(c) end }
ns.COLORS = { profit = "ff4fd18b" }

local values = {}
ns.Disenchant = { GetValue = function(_, itemID) return values[itemID] end }
local known = true
ns.Disenchanter = { Knows = function() return known end }

local PostPanel
local realNew = ns.NewModule
ns.NewModule = function(name) local m = realNew(name); PostPanel = m; return m end
assert(loadfile(lfs_cwd .. "/UI/PostPanel.lua"))("Blackthornes_TS", ns)

local checks = 0
local function check(label, condition)
    checks = checks + 1
    if not condition then error(("FAILED: %s"):format(label), 2) end
    print(("  ok  %s"):format(label))
end

local lines = {
    { itemID = 1, atALoss = false },
    { itemID = 2, atALoss = true },
    { itemID = 3 },
    { itemID = 4, atALoss = true },
}
local kept, hidden = PostPanel.WithoutLosses(lines)
check("rows at a loss are left out", #kept == 2 and kept[1].itemID == 1 and kept[2].itemID == 3)
check("and counted", hidden == 2)
check("the list handed in is untouched", #lines == 4)

kept, hidden = PostPanel.WithoutLosses({})
check("an empty list stays empty", #kept == 0 and hidden == 0)

local settings = {}
ns.Config = { Get = function(_, key) return settings[key] end }
check("off until ticked", PostPanel:HidingLosses() == false)
settings.postHideLosses = true
check("on once ticked", PostPanel:HidingLosses() == true)
settings.postHideLosses = false
check("off again when unticked", PostPanel:HidingLosses() == false)

-- The default is in Config.DEFAULTS, so the CVar mirror keeps it too.
local config = assert(io.open(lfs_cwd .. "/Core/Config.lua")):read("*a")
check("the setting has a default of off", config:find("postHideLosses = false", 1, true) ~= nil)

print(("\n%d check(s) passed\n"):format(checks))
