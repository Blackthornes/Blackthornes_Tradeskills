-- The "Open <profession>" button passed between the Queue and Level Up tabs,
-- outside WoW.
--
-- One secure button covers whichever Craft button needs a profession window
-- opened, and the Craft button under it stops taking the mouse while it does.
--
-- What must hold:
--   1. When the Level Up tab takes the secure button from the Queue tab, the
--      Queue tab's Craft button takes clicks again. Only the button covered
--      last was ever given them back, so after a trip to the Level Up tab the
--      Queue tab's "Craft 3x Bolt of Linen Cloth" ignored every click until a
--      reload.
--   2. The same the other way round, for the Level Up tab's button.
--   3. Moving back and forth leaves no button without the mouse once the
--      secure button is put away.

-- Tests share one Lua state, so every global replaced here is put back,
-- including the ones that were not set at all.
local GLOBALS = { "CreateFrame", "UIParent", "InCombatLockdown", "GetTime", "C_Timer",
    "C_TradeSkillUI", "C_Spell", "GameTooltip", "GetSpellInfo" }
local saved = {}
for _, key in ipairs(GLOBALS) do saved[key] = _G[key] end

local function noop() end

local ns = {}
ns.NewModule = function(name) local m = {}; ns[name] = m; return m end
ns.Print, ns.Warn = noop, noop
ns.RegisterEvent = noop
ns.RegisterCommand = noop

local RECIPES = {
    [1] = { recipeID = 1, name = "Bolt of Linen Cloth", skillLineID = 2948 },
    [2] = { recipeID = 2, name = "Copper Chain Belt", skillLineID = 2938 },
}
ns.Recipes = { GetAny = function(_, id) return RECIPES[id] end }
ns.Crafting = { isTradeSkillOpen = false }
ns.CraftPanel = { GetOpenRecipeIDs = function() return nil end }

ns.Theme = {
    Fill = function() return { SetColorTexture = noop } end,
    Border = noop,
    CreateLabel = function()
        return { SetPoint = noop, SetWordWrap = noop, SetText = function(self, t) self.text = t end }
    end,
    Unpack = function() return 0, 0, 0, 1 end,
}

-- Frames whose methods do nothing unless named here; the mouse is what counts.
local function NewFrame()
    local f = { shown = false, mouse = true, attrs = {}, scripts = {}, hooks = {} }
    setmetatable(f, { __index = function(_, k)
        if type(k) == "string" and k:match("^%u") then return noop end
    end })
    f.Show = function(self) self.shown = true end
    f.Hide = function(self) self.shown = false end
    f.IsShown = function(self) return self.shown end
    f.IsVisible = function(self) return self.shown end
    f.EnableMouse = function(self, on) self.mouse = on end
    f.SetAttribute = function(self, k, v) self.attrs[k] = v end
    f.GetAttribute = function(self, k) return self.attrs[k] end
    f.SetScript = function(self, k, fn) self.scripts[k] = fn end
    f.HookScript = function(self, k, fn) self.hooks[k] = fn end
    f.GetFrameStrata = function() return "MEDIUM" end
    f.GetFrameLevel = function() return 3 end
    f.GetLeft = function() return 10 end
    f.GetBottom = function() return 20 end
    f.GetWidth = function() return 220 end
    f.GetHeight = function() return 26 end
    f.GetEffectiveScale = function() return 1 end
    f.CreateTexture = function() return NewFrame() end
    return f
end

CreateFrame = function() return NewFrame() end
UIParent = NewFrame()
GameTooltip = NewFrame()
InCombatLockdown = function() return false end
GetTime = function() return 100 end
C_Timer = { After = noop }
GetSpellInfo = nil
C_Spell = { GetSpellName = function() return nil end }
C_TradeSkillUI = {
    GetProfessionInfoBySkillLineID = function(id)
        if id == 2948 then return { professionName = "Tailoring" } end
        if id == 2938 then return { professionName = "Blacksmithing" } end
    end,
}

assert(loadfile(lfs_cwd .. "/UI/ProfessionOpener.lua"))("Blackthornes_TS", ns)
local Opener = ns.ProfessionOpener

local passed, failed = 0, 0

local function check(label, got, want)
    local ok = got == want
    if ok then passed = passed + 1 else failed = failed + 1 end
    print(string.format("  %-62s %-6s %s", label, tostring(got), ok and "ok" or
        ("WRONG, wanted " .. tostring(want))))
end

local tailoring, blacksmithing = Opener:ProfessionFor(1), Opener:ProfessionFor(2)

print("the Queue tab, then the Level Up tab")

do
    local queueButton, levelButton = NewFrame(), NewFrame()

    -- The Queue tab: the next craft's window is closed, so its button opens it.
    queueButton:Show()
    Opener:Arm(queueButton, tailoring, 1)
    check("the Queue tab's Craft button is covered", queueButton.mouse, false)

    -- The Level Up tab, with a recipe whose window is closed too.
    queueButton:Hide()
    levelButton:Show()
    Opener:Arm(levelButton, blacksmithing, 2)
    check("the Level Up tab's Craft button is covered now", levelButton.mouse, false)
    check("and the Queue tab's takes clicks again", queueButton.mouse, true)

    -- The window opens; the Level Up tab puts the secure button away.
    Opener:Disarm()
    check("the Level Up tab's Craft button takes clicks", levelButton.mouse, true)
    check("and the Queue tab's still does", queueButton.mouse, true)
end

print("")
print("the Level Up tab, then the Queue tab, and back")

do
    local queueButton, levelButton = NewFrame(), NewFrame()

    levelButton:Show()
    Opener:Arm(levelButton, blacksmithing, 2)
    levelButton:Hide()
    queueButton:Show()
    Opener:Arm(queueButton, tailoring, 1)
    check("the Level Up tab's Craft button takes clicks again", levelButton.mouse, true)

    Opener:Disarm()
    queueButton:Hide()
    levelButton:Show()
    check("back on Level Up, its Craft button takes clicks", levelButton.mouse, true)
    check("and the Queue tab's too", queueButton.mouse, true)
end

print("")
print("re-arming the same button")

do
    local button = NewFrame()
    button:Show()
    Opener:Arm(button, tailoring, 1)
    Opener:Arm(button, blacksmithing, 2)
    check("stays covered while it still opens a window", button.mouse, false)
    Opener:Disarm()
    check("and takes clicks once put away", button.mouse, true)
end

for _, key in ipairs(GLOBALS) do _G[key] = saved[key] end

print("")
if failed > 0 then
    error(string.format("FAIL -- %d of %d open-profession hand-over checks wrong", failed, passed + failed))
end
print(string.format("PASS -- no Craft button is left without the mouse (%d checks)", passed))
