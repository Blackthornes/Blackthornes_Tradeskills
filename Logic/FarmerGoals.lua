-- Blackthornes Tradeskills -- Logic/FarmerGoals.lua
-- Hands a material from the Gather tab to Blackthornes Farmer as a gathering
-- goal (Trent, 2026-09-27).
--
-- Farmer is optional. Without it nothing here shows and nothing is called.
-- With it, Farmer's own Goals:Set does the work, so the goal is exactly what
-- "/farm goal Copper Ore 40" would make: counted from the bags, shown on
-- Farmer's Goals panel, with its milestones and finish fanfare.
--
-- Read through `_G.BlackthornesFarmer`, inside a pcall. Farmer's CLAUDE.md
-- asks its side to keep that global, `Goals`, `Goals:Set(name, amount)` and
-- `GoalsUI:Show()` stable.

local _, ns = ...

local FarmerGoals = ns.NewModule("FarmerGoals")

--- Farmer's Goals module, or nil when Farmer is not loaded (or too old to
--- have goals).
function FarmerGoals:Farmer()
    local farmer = rawget(_G, "BlackthornesFarmer")
    if type(farmer) ~= "table" then return nil end

    local goals = farmer.Goals
    if type(goals) ~= "table" or type(goals.Set) ~= "function" then return nil end
    return farmer
end

function FarmerGoals:Available()
    return self:Farmer() ~= nil
end

--- The plain name of an item (no colour, no brackets), or nil until the
--- client has it.
local function ItemName(itemID)
    if type(C_Item) == "table" then
        if type(C_Item.GetItemNameByID) == "function" then
            local ok, name = pcall(C_Item.GetItemNameByID, itemID)
            if ok and type(name) == "string" and name ~= "" then return name end
        end
        if type(C_Item.GetItemInfo) == "function" then
            local ok, name = pcall(C_Item.GetItemInfo, itemID)
            if ok and type(name) == "string" and name ~= "" then return name end
        end
    end
    if type(GetItemInfo) == "function" then
        local ok, name = pcall(GetItemInfo, itemID)
        if ok and type(name) == "string" and name ~= "" then return name end
    end
    return nil
end

FarmerGoals.ItemName = ItemName

local function Cheer()
    if type(PlaySound) ~= "function" then return end
    local kits = type(_G.SOUNDKIT) == "table" and _G.SOUNDKIT or {}
    pcall(PlaySound, kits.IG_QUEST_LIST_COMPLETE or 878)
end

--- Hand one goal to Farmer. Returns the goal and whether it already
--- existed, or nil and why not. Prints nothing.
local function Apply(farmer, itemID, amount)
    local name = ItemName(itemID)
    if not name then return nil, "the game has not sent its name yet" end

    amount = math.floor(tonumber(amount) or 0)

    local Goals = farmer.Goals
    local existed = false
    if type(Goals.Find) == "function" then
        local ok, found = pcall(Goals.Find, Goals, name)
        existed = ok and found ~= nil
    end

    local ok, goal, why = pcall(Goals.Set, Goals, name, amount)
    if not ok then return nil, "Farmer could not make it. It may need updating" end
    if type(goal) ~= "table" then return nil, tostring(why or "Farmer said no"), name end

    return goal, existed
end

local function ShowPanel(farmer)
    local ui = farmer.GoalsUI
    if type(ui) == "table" and type(ui.Show) == "function" then
        pcall(ui.Show, ui)
    end
end

--- Make (or change) a Farmer goal to have `amount` of `itemID`.
-- Returns true, or false and why not. Says the outcome in chat either way.
function FarmerGoals:SetGoal(itemID, amount)
    local farmer = self:Farmer()
    if not farmer then
        ns.Print("Blackthornes Farmer is not loaded, so there is nowhere to put a goal.")
        return false, "no farmer"
    end

    local goal, existed = Apply(farmer, itemID, amount)
    if not goal then
        ns.Print(("No Farmer goal set: %s."):format(existed))
        return false, existed
    end

    local target = tonumber(goal.target) or amount
    local have = tonumber(goal.have) or 0
    ns.Print(("|c%sFarmer goal %s:|r %d %s. You have %d, %d to go."):format(
        ns.COLORS.profit or ns.COLORS.accent, existed and "updated" or "set",
        target, tostring(goal.item), have, math.max(0, target - have)))

    ShowPanel(farmer)
    Cheer()
    return true
end

--- A goal for every line in `lines` ({ itemID, needed }), in order.
-- Farmer holds only so many goals at once; the rest are named as not set.
-- One summary in chat and one sound, however many there are.
-- Returns how many were set.
function FarmerGoals:SetGoals(lines)
    local farmer = self:Farmer()
    if not farmer then
        ns.Print("Blackthornes Farmer is not loaded, so there is nowhere to put goals.")
        return 0
    end

    local set, missed = {}, {}
    for _, line in ipairs(lines or {}) do
        local goal, existed, name = Apply(farmer, line.itemID, line.needed)
        if goal then
            set[#set + 1] = tostring(goal.item)
        else
            missed[#missed + 1] = ("%s (%s)"):format(
                name or ItemName(line.itemID) or ("item " .. tostring(line.itemID)), existed)
        end
    end

    if #set == 0 and #missed == 0 then
        ns.Print("Nothing still needed, so no Farmer goals to set.")
        return 0
    end

    if #set > 0 then
        ns.Print(("|c%s%d Farmer goal%s set:|r %s."):format(
            ns.COLORS.profit or ns.COLORS.accent, #set, #set == 1 and "" or "s",
            table.concat(set, ", ")))
        ShowPanel(farmer)
        Cheer()
    end

    if #missed > 0 then
        ns.Print(("Not set: %s."):format(table.concat(missed, "; ")))
    end

    return #set
end
