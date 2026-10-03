-- Blackthornes Tradeskills -- Logic/BagsFull.lua
-- A warning the moment your bags fill up.
--
-- Asked for by a player (Izbode, 2026-10-02) for long crafting and
-- disenchanting runs, where the game stops the run quietly when there is
-- nowhere to put the next item. Only the ordinary bags count: a full herb
-- bag still leaves room for everything else. The warning sounds when the
-- last free slot goes, not while the bags stay full, and never at login.

local _, ns = ...

local BagsFull = ns.NewModule("BagsFull")

-- ALARM_CLOCK_WARNING_2: short and plain, unlike the sale alarm's raid
-- warning. Read from the game's own table when it has one.
local WARNING_SOUND = 12867

--- Free slots in the ordinary bags, or nil when the game will not say.
function BagsFull:CountFree()
    if not (C_Container and C_Container.GetContainerNumFreeSlots) then return nil end

    local free, read = 0, false
    for _, bag in ipairs(ns.Inventory:GetCarriedBags()) do
        local ok, slots, family = pcall(C_Container.GetContainerNumFreeSlots, bag)
        if ok and type(slots) == "number" and (family == nil or family == 0) then
            free = free + slots
            read = true
        end
    end

    return read and free or nil
end

function BagsFull:Check()
    local free = self:CountFree()
    if free == nil then return end

    local before = self.lastFree
    self.lastFree = free

    if before and before > 0 and free == 0 then
        self:Warn()
    end
end

function BagsFull:Warn()
    ns.Print("your bags are full")

    -- Settings: SOUNDS, Bags are full.
    if ns.Config:Get("bagsFullSound") == false or type(PlaySound) ~= "function" then return end

    local kits = type(_G.SOUNDKIT) == "table" and _G.SOUNDKIT or {}
    pcall(PlaySound, kits.ALARM_CLOCK_WARNING_2 or WARNING_SOUND, "Master")
end

function BagsFull:OnEnable()
    ns.RegisterEvent(self, "BAG_UPDATE_DELAYED", function() self:Check() end)
    ns.RegisterEvent(self, "PLAYER_ENTERING_WORLD", function()
        -- A fresh reading, so bags already full at login stay quiet.
        self.lastFree = nil
        self:Check()
    end)
end
