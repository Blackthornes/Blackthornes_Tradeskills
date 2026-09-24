-- Blackthornes Tradeskills -- Core/OldMacros.lua
-- Removes the macros the old macro store left behind.
--
-- Until build 1.60.1.70009 (2026-09-24) the game lost saved data on every
-- restart, so settings, the craft queue and sales history were kept in macros
-- named BTSd00 and up, and /bts macrotest wrote BTSt01 and up. The game keeps
-- saved data now and that store is gone, so its macros are removed.
--
-- Only on a login where the game really did hand the saved data back: on any
-- other login they may be the last copy, and they are left alone. Only these
-- names are ever touched. Each is looked up again before deleting, because
-- DeleteMacro shifts every index above the one it removes.

local _, ns = ...

local OldMacros = ns.NewModule("OldMacros")

local function Names()
    local names = {}
    for index = 60, 0, -1 do names[#names + 1] = ("BTSd%02d"):format(index) end
    for index = 40, 1, -1 do names[#names + 1] = ("BTSt%02d"):format(index) end
    names[#names + 1] = "BTStX"
    return names
end

local function Find(name)
    local ok, index = pcall(GetMacroIndexByName, name)
    return ok and type(index) == "number" and index > 0 and index or nil
end

--- Delete the old storage macros.
-- @return removed, remaining -- or nil and a reason when it did not try
function OldMacros:Remove()
    if not (ns.Persist and ns.Persist:GameKeepsSavedData()) then
        return nil, "the game did not load your saved data this session"
    end
    if type(GetMacroIndexByName) ~= "function" or type(DeleteMacro) ~= "function" then
        return nil, "this version of the game has no macro functions"
    end
    if InCombatLockdown and InCombatLockdown() then
        return nil, "in combat"
    end

    local removed, remaining = 0, 0

    for _, name in ipairs(Names()) do
        local index = Find(name)
        if index then pcall(DeleteMacro, index) end
    end

    -- The outcome, not the attempt: count what is actually gone.
    for _, name in ipairs(Names()) do
        if Find(name) then remaining = remaining + 1 end
    end

    removed = self.foundBefore - remaining
    return removed, remaining
end

function OldMacros:Run()
    self.foundBefore = 0
    for _, name in ipairs(Names()) do
        if Find(name) then self.foundBefore = self.foundBefore + 1 end
    end

    if self.foundBefore == 0 then return end

    local removed, remaining = self:Remove()

    if removed == nil then
        if remaining == "in combat" then
            -- Macros cannot be edited in combat. Try again once it ends.
            ns.RegisterEvent(self, "PLAYER_REGEN_ENABLED", function()
                ns.UnregisterEvent(self, "PLAYER_REGEN_ENABLED")
                OldMacros:Run()
            end)
        end
        return
    end

    if remaining > 0 then
        ns.Warn(("removed %d old storage macro(s) (BTSd...), but %d could not be removed."):format(removed, remaining))
    else
        ns.Print(("removed %d old storage macro(s) (BTSd...); the game keeps your data now."):format(removed))
    end
end

function OldMacros:OnEnable()
    self:Run()
end
