-- Blackthornes Tradeskills -- Logic/Upgrades.lua
-- Is this item an upgrade for the character playing? Asked of Blackthornes
-- Equipment, so the green arrow on an icon here means exactly what the arrow
-- in the bags means (Trent, 2026-09-30).
--
-- Equipment is optional. Without it every answer is "no" and nothing is
-- drawn; Tradeskills works as before. With it, Equipment's own
-- Compare:IsUpgrade(itemID) decides: gear the character can wear now that
-- beats what is worn, for the spec Equipment judges them as.
--
-- Read through `_G.BlackthornesEquipment`, inside a pcall. Equipment's
-- CLAUDE.md asks its side to keep that global, `Compare` and
-- `Compare:IsUpgrade(item)` stable.
--
-- Answers are kept per item ID, since a list redraws its rows often and each
-- answer weighs the worn gear too. They are forgotten whenever the answer
-- could change: new gear on, a level, talents, or an item's details arriving.

local _, ns = ...

local Upgrades = ns.NewModule("Upgrades")

local known = {}

--- Equipment's Compare module, or nil when Equipment is not loaded (or too
--- old to answer).
function Upgrades:Equipment()
    local equipment = rawget(_G, "BlackthornesEquipment")
    if type(equipment) ~= "table" then return nil end

    local compare = equipment.Compare
    if type(compare) ~= "table" or type(compare.IsUpgrade) ~= "function" then return nil end
    return compare
end

function Upgrades:IsEnabled()
    return not (ns.Config and ns.Config:Get("showUpgradeArrows") == false)
end

--- True when the item is an upgrade the character can wear now. False for
--- everything else, including when Equipment is not there. Never raises.
function Upgrades:IsUpgrade(itemID)
    itemID = tonumber(itemID)
    if not itemID or not self:IsEnabled() then return false end

    local compare = self:Equipment()
    if not compare then return false end

    local answer = known[itemID]
    if answer == nil then
        local ok, result = pcall(compare.IsUpgrade, compare, itemID)
        answer = ok and result == true
        known[itemID] = answer
    end
    return answer
end

--- Forget every answer, so the next draw asks again.
function Upgrades:Forget()
    known = {}
end

--- Forget, and redraw the open tab, the craft pane and the sell list once
--- things settle, so a burst of events (a whole outfit swapped) costs one
--- redraw.
function Upgrades:RedrawSoon()
    self:Forget()
    if self.pending then return end
    self.pending = true

    local function Redraw()
        Upgrades.pending = false
        if ns.UI and ns.UI.RefreshActiveTab then pcall(ns.UI.RefreshActiveTab, ns.UI) end

        -- The craft pane and the sell list draw item icons too, outside the
        -- main window, so its redraw left their arrows as they were.
        local craft, post = ns.CraftPanel, ns.PostPanel
        if craft and craft.IsShown and craft:IsShown() then pcall(craft.RequestRefresh, craft) end
        if post and post.IsShown and post:IsShown() then pcall(post.Refresh, post) end
    end

    if type(C_Timer) == "table" and type(C_Timer.After) == "function" then
        C_Timer.After(0.3, Redraw)
    else
        Redraw()
    end
end

-- What can change which items are upgrades.
local CHANGES = { "PLAYER_EQUIPMENT_CHANGED", "PLAYER_LEVEL_UP", "TRAIT_CONFIG_UPDATED" }

function Upgrades:OnEnable()
    for _, event in ipairs(CHANGES) do
        ns.RegisterEvent(self, event, self.RedrawSoon)
    end

    -- An item's stats arriving, or the worn gear's, can turn a "no" into a
    -- "yes". The tabs already redraw for this event, so answers are only
    -- forgotten here.
    ns.RegisterEvent(self, "GET_ITEM_INFO_RECEIVED", function() Upgrades:Forget() end)
end
