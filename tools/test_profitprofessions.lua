-- The Profit tab's profession list with "All characters" ticked.
--
-- The list was always built from this character's recipes, so with "All
-- characters" ticked an alt's profession could not be picked even though its
-- crafts were in the list. Ticking now rebuilds it from every character's
-- recipes, and unticking takes the alt's back out and clears a choice that
-- is no longer shown.

local ns = {}
ns.NewModule = function(name) local m = {}; ns[name] = m; return m end
ns.RegisterCommand = function() end
ns.RegisterEvent = function() return true end
ns.Print, ns.Debug, ns.Warn = function() end, function() end, function() end

-- Any method this test does not care about answers as a no-op.
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

CreateFrame = function() return Stub() end
C_Timer = { After = function() end, NewTicker = function() return Stub() end }

ns.Theme = setmetatable({
    FONT = "font",
    sizes = { tiny = 10, small = 11, normal = 12, large = 14, title = 16 },
    Unpack = function(key) return key end,
    ProfitColor = function() return "profit" end,
    CreateHeading = function() return Stub({ rule = Stub() }) end,
    StyleHeading = function(label) label.rule = Stub(); return label end,
}, { __index = function() return function() return Stub() end end })

-- The profession dropdown, as Widgets builds it: SetOptions keeps the
-- selection when it is still offered and otherwise falls back to the first
-- option without calling onSelect.
local professionDropdown, professionPicked
local checkboxes = {}

ns.Widgets = {
    CreateSearchBox = function() return Stub() end,
    CreateDropdown = function(_, options, onSelect)
        -- rawget: a nil selection must read as nil, not as the stub's no-op.
        local dropdown = Stub({ options = options })
        function dropdown:SetOptions(newOptions)
            self.options = newOptions
            local still = false
            for _, option in ipairs(newOptions) do
                if option.value == rawget(self, "selected") then still = true end
            end
            if not still then rawset(self, "selected", newOptions[1] and newOptions[1].value) end
        end
        function dropdown:GetValue() return rawget(self, "selected") end
        if options[1] and options[1].text == "All professions" then
            professionDropdown, professionPicked = dropdown, onSelect
        end
        return dropdown
    end,
    CreateCheckbox = function(_, text, onChange)
        local box = Stub({ onChange = onChange })
        checkboxes[text] = box
        return box
    end,
    CreateScrollList = function() return Stub({ SetData = function() end }) end,
    CreateNumberBox = function() return Stub() end,
    CreateButton = function() return Stub() end,
    ShowItemTooltip = function() return true end,
}

local TAILORING, ALCHEMY = 197, 171
local NAMES = { [TAILORING] = "Tailoring" }   -- the client names only this character's

ns.Util = {
    FormatMoney = function(copper) return tostring(copper or 0) end,
    FormatAge = function() return "1h" end,
    FormatAgeAgo = function() return "1h ago" end,
    GetItemLabel = function(itemID) return "item" .. tostring(itemID) end,
    GetItemQualityColor = function() end,
    Round = function(v) return v end,
    HasFunction = function(path) return path == "C_TradeSkillUI.GetProfessionInfoBySkillLineID" end,
}

C_TradeSkillUI = {
    GetProfessionInfoBySkillLineID = function(skillLineID)
        return { professionName = NAMES[skillLineID] or "" }
    end,
}

local mine = { [1] = { recipeID = 1, name = "Linen Bag", skillLineID = TAILORING } }
local everyone = {
    [1] = { recipeID = 1, name = "Linen Bag", skillLineID = TAILORING },
    [2] = { recipeID = 2, name = "Healing Potion", skillLineID = ALCHEMY },
}

ns.db = { characters = {
    ["Player-1"] = { professions = { { name = "Tailoring", skillLineID = TAILORING } } },
    ["Player-2"] = { professions = { { name = "Alchemy", skillLineID = ALCHEMY } } },
} }

-- Every skill line the list was asked for since the last look.
local asked = {}
ns.Profit = {
    GetRanked = function(_, opts) asked[#asked + 1] = opts.skillLineID or "all"; return {} end,
    Analyse = function() end,
}
local function AskedOnly(value)
    local ok = #asked > 0
    for _, got in ipairs(asked) do ok = ok and got == value end
    asked = {}
    return ok
end
ns.Recipes = {
    Count = function() return 1 end,
    GetAll = function() return mine end,
    GetAccountWide = function() return everyone end,
    IsDropped = function() return false end,
}
ns.Prices = { Count = function() return 1 end }
ns.Auctions = { SetLimit = function() end }
ns.Config = { Get = function() return 0 end }
ns.Queue = { Add = function() end }

local tabs = {}
ns.UI = Stub({ RegisterTab = function(_, tab) tabs[tab.key] = tab end })

assert(loadfile(lfs_cwd .. "/UI/Tab_Profit.lua"))("Blackthornes_TS", ns)

local function check(label, condition)
    if not condition then error(("FAILED: %s"):format(label), 2) end
    print(("  ok  %s"):format(label))
end

local function Offered()
    local byValue = {}
    for _, option in ipairs(professionDropdown.options) do
        if option.value then byValue[option.value] = option.text end
    end
    return byValue
end

print("")
print("the Profit tab's profession list")

local profit = tabs.profit
profit.build(Stub())
profit.onShow()

check("this character's profession is offered", Offered()[TAILORING] == "Tailoring")
check("an alt's is not, while All characters is unticked", Offered()[ALCHEMY] == nil)

checkboxes["All characters"].onChange(true)
check("ticked, the alt's profession is offered", Offered()[ALCHEMY] ~= nil)
check("named from what was saved for that character", Offered()[ALCHEMY] == "Alchemy")

-- Pick it, then untick: the choice is gone, and the filter goes with it.
professionDropdown.selected = ALCHEMY
asked = {}
professionPicked(ALCHEMY)
check("picking it filters the list to it", AskedOnly(ALCHEMY))

checkboxes["All characters"].onChange(false)
check("unticked, the alt's profession is gone again", Offered()[ALCHEMY] == nil)
check("and the list is no longer filtered to it", AskedOnly("all"))

ns.db = nil
C_TradeSkillUI = nil
print("test_profitprofessions: ok")
