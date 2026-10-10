-- Crafts of a profession the character has dropped.
--
-- Recipes are cached for good, so dropping Tailoring left its crafts in
-- Profit, Level Up and the sub-craft suggestions. They are now hidden once a
-- reliable read of the character's professions says the skill line is not
-- learned. Nothing is deleted, a read taken before skill levels load (when
-- everything looks unlearned) is ignored, and learning it again brings the
-- crafts back.

local checks = 0
local function check(label, condition)
    checks = checks + 1
    if not condition then error(("FAILED: %s"):format(label), 2) end
    print(("  ok  %s"):format(label))
end

UnitName = function() return "Bob" end
UnitGUID = function() return "Player-1-A" end
UnitClass = function() return "Mage", "MAGE" end
UnitLevel = function() return 40 end
UnitFactionGroup = function() return "Horde" end
GetRealmName = function() return "Forever PvE" end
time = time or os.time

-- The client's profession list: both of Forever's IDs for each profession.
-- maxSkillLevel 0 is unlearned, or not loaded yet.
local levels = { [197] = 0, [2942] = 0, [186] = 0, [2950] = 0 }
C_TradeSkillUI = {
    GetAllProfessionTradeSkillLines = function() return { 2942, 197, 2950, 186 } end,
    GetProfessionInfoBySkillLineID = function(id)
        local names = { [197] = "Tailoring", [2942] = "Tailoring", [186] = "Mining", [2950] = "Mining" }
        return { professionName = names[id], skillLevel = levels[id], maxSkillLevel = levels[id] }
    end,
}

local ns = {}
ns.NewModule = function(name) local m = {}; ns[name] = m; return m end
ns.RegisterCommand = function() end
ns.RegisterEvent = function() end
ns.Warn, ns.Print, ns.PrintRaw, ns.Debug = function() end, function() end, function() end, function() end
ns.COLORS = {}
ns.Util = {
    Count = function(t) local n = 0 for _ in pairs(t or {}) do n = n + 1 end return n end,
    CopyDeep = function(t) local c = {} for k, v in pairs(t) do c[k] = v end return c end,
}
ns.Compat = { Get = function() return { tradeskill = { hasAllProfessionLines = true } } end }

assert(loadfile(lfs_cwd .. "/Core/Config.lua"))("Blackthornes_TS", ns)
assert(loadfile(lfs_cwd .. "/Data/Recipes.lua"))("Blackthornes_TS", ns)
assert(loadfile(lfs_cwd .. "/Logic/Cost.lua"))("Blackthornes_TS", ns)

local SELF, ALT = "Player-1-A", "Player-1-B"
local robe = { recipeID = 10, name = "Robe", outputItemID = 100, skillLineID = 197 }
local bar = { recipeID = 20, name = "Bar", outputItemID = 200, skillLineID = 2950 }
local mystery = { recipeID = 30, name = "Mystery", outputItemID = 300 }
local odd = { recipeID = 40, name = "Odd", outputItemID = 400, skillLineID = 9999 }

ns.db = { characters = {
    [SELF] = { name = "Bob", recipes = { [10] = robe, [20] = bar, [30] = mystery, [40] = odd },
               professions = { { name = "Tailoring", skillLineID = 2942, learned = true } } },
    [ALT] = { name = "Mirel", recipes = { [10] = { recipeID = 10, name = "Robe", skillLineID = 2942 } } },
} }
ns.Config.characterKey = SELF

local Recipes = ns.Recipes

print("\nbefore any read of the professions")
check("nothing is hidden", not Recipes:IsDropped(robe) and not Recipes:IsDropped(bar))
check("the robe is offered as a sub-craft", ns.Cost:FindRecipeForItem(100) == 10)

print("\na read at login, before skill levels arrive")
Recipes:RefreshProfessions()
check("everything reading unlearned hides nothing", not Recipes:IsDropped(robe))

print("\nTailoring dropped, Mining kept")
levels[186], levels[2950] = 150, 150
Recipes:RefreshProfessions()
check("the dropped profession's craft is hidden", Recipes:IsDropped(robe))
check("the kept profession's craft is not", not Recipes:IsDropped(bar))
check("a craft with no skill line is kept", not Recipes:IsDropped(mystery))
check("a craft whose skill line was not listed is kept", not Recipes:IsDropped(odd))
check("nothing was deleted", ns.db.characters[SELF].recipes[10] == robe)
check("it is not offered as a sub-craft", ns.Cost:FindRecipeForItem(100) == nil)
check("the kept one still is", ns.Cost:FindRecipeForItem(200) == 20)

-- The alt still has Tailoring (no read says otherwise), so it makes the robe.
local _, owner = Recipes:GetAny(10)
check("an alt who still has it is the one who can make it", owner == ALT)
local wide = Recipes:GetAccountWide(true)
check("all characters lists the robe under the alt only",
    wide[10] and #wide[10].knownBy == 1 and wide[10].knownBy[1] == ALT)
check("without the flag the list is as before", #Recipes:GetAccountWide()[10].knownBy == 2)

print("\na later read at login, before skill levels arrive")
levels[186], levels[2950] = 0, 0
Recipes:RefreshProfessions()
check("an all-unlearned read does not undo the last good one", Recipes:IsDropped(robe))

print("\nTailoring learned again")
levels[197], levels[2942], levels[186], levels[2950] = 1, 1, 150, 150
Recipes:RefreshProfessions()
check("its crafts come back", not Recipes:IsDropped(robe))
_, owner = Recipes:GetAny(10)
check("and this character makes it again", owner == SELF)

print("\nlearning or dropping a profession is read at once")
local handlers = {}
ns.RegisterEvent = function(_, event, fn) handlers[event] = fn; return true end
local savedTimer = C_Timer
C_Timer = { NewTicker = function() return { Cancel = function() end } end }
Recipes:OnEnable()
check("the skill lines changing is listened for", handlers.SKILL_LINES_CHANGED ~= nil)
levels[197], levels[2942] = 0, 0
handlers.SKILL_LINES_CHANGED()
check("and a drop hides the crafts", Recipes:IsDropped(robe))
check("and takes them out of the sub-crafts", ns.Cost:FindRecipeForItem(100) == nil)
-- A client without the event: RegisterEvent says no, and nothing breaks.
ns.RegisterEvent = function() return false end
check("a client without the event is fine", pcall(Recipes.OnEnable, Recipes))
C_Timer = savedTimer

print(("\n%d check(s) passed\n"):format(checks))
