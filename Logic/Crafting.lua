-- Blackthornes Tradeskills -- Logic/Crafting.lua
-- What you can make, and starting it.
--
-- Blizzard requires a hardware event to begin a craft, so one click runs one
-- queue entry; within an entry the client repeats the craft itself. If this
-- client refuses an addon-started craft outright, that is noticed on the
-- first attempt and the queue falls back to being a work list.
--
-- Either way the queue reconciles itself from your bags rather than from
-- counting casts, so crafting by hand in Blizzard's window works the same.

local _, ns = ...

local Crafting = ns.NewModule("Crafting")

Crafting.isTradeSkillOpen = false

--------------------------------------------------------------------------------
-- Capability
--------------------------------------------------------------------------------

--- True once this client has been *seen* refusing an addon-started craft.
--
-- Deliberately not inferred from issecurevariable. That reports whether a
-- variable is untainted, which is true of nearly every Blizzard function an
-- addon has not overwritten -- it says nothing about whether calling it from
-- addon code is allowed. Reading it as proof of protection was a mistake.
--
-- The only reliable evidence is the client refusing a real attempt, so this
-- stays false until that happens.
function Crafting:IsBlocked()
    return self.blocked == true
end

--- Record that the client refused a craft started from addon code.
function Crafting:MarkBlocked()
    if self.blocked then return end

    self.blocked = true
    ns.Warn("this client refused an addon-started craft; use Blizzard's own window.")

    if ns.UI then ns.UI:RefreshActiveTab() end
end

--------------------------------------------------------------------------------
-- Readiness
--------------------------------------------------------------------------------

--- Can this be made right now, and if not why not?
-- @return ready, reason
function Crafting:GetReadiness(recipeID)
    if self:IsBlocked() then
        return false, "blocked by client"
    end

    local recipe, owner = ns.Recipes:GetAny(recipeID)
    if not recipe then
        return false, "not cached"
    end

    -- Queued from the account-wide view: this character simply cannot make it.
    if owner ~= ns.Config:GetCharacterKey() then
        return false, ("on %s"):format(ns.Recipes:GetCharacterName(owner))
    end

    if ns.Profit:GetCraftableCount(recipeID) < 1 then
        return false, "need materials"
    end

    if not self.isTradeSkillOpen then
        return true, "open your profession"
    end

    return true
end

--- How many queued entries you could make right now.
-- @return ready, total
function Crafting:GetQueueReadiness()
    local ready, total = 0, 0

    for _, entry in ipairs(ns.Queue:GetAll()) do
        total = total + 1
        if self:GetReadiness(entry.recipeID) then
            ready = ready + 1
        end
    end

    return ready, total
end

--- The first queued craft you could make right now.
function Crafting:GetNextReady()
    for _, entry in ipairs(ns.Queue:GetAll()) do
        if self:GetReadiness(entry.recipeID) then
            return entry
        end
    end
end

--------------------------------------------------------------------------------
-- Following along
--------------------------------------------------------------------------------

-- However a craft was started -- from here or from Blizzard's own window --
-- the queue reconciles from what appears in your bags. That keeps the list
-- honest whichever way you work, and survives interrupts and partial runs.

function Crafting:OnBagUpdate()
    if ns.Queue:Count() == 0 then return end

    for _, entry in ipairs(ns.Queue:GetAll()) do
        local recipe = ns.Recipes:GetAny(entry.recipeID)

        if recipe and recipe.outputItemID then
            local held = ns.Inventory:GetBagCount(recipe.outputItemID)
            local previous = self.seen and self.seen[recipe.outputItemID]

            if previous and held > previous then
                local perCraft = math.max(1, recipe.quantityMin or 1)

                -- A variable-yield recipe can produce more than its minimum,
                -- which would otherwise read as extra crafts completed.
                local made = math.min(
                    math.floor((held - previous) / perCraft),
                    entry.quantity)

                if made > 0 then
                    ns.Queue:SetQuantity(entry.recipeID, entry.quantity - made)

                    ns.Print(("made %d of %s"):format(made,
                        ns.Recipes:GetDisplayLink(entry.recipeID)))
                end
            end
        end
    end

    self:RememberOutputs()
end

--- Snapshot the queue's output items, so the next bag change can be compared.
function Crafting:RememberOutputs()
    self.seen = {}

    for _, entry in ipairs(ns.Queue:GetAll()) do
        local recipe = ns.Recipes:GetAny(entry.recipeID)

        if recipe and recipe.outputItemID then
            self.seen[recipe.outputItemID] = ns.Inventory:GetBagCount(recipe.outputItemID)
        end
    end
end

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------

function Crafting:OnTradeSkillShow()
    self.isTradeSkillOpen = true
    self:RememberOutputs()

    if ns.UI then ns.UI:RefreshActiveTab() end
end

function Crafting:OnTradeSkillClose()
    self.isTradeSkillOpen = false
    if ns.UI then ns.UI:RefreshActiveTab() end
end

function Crafting:OnEnable()
    ns.RegisterEvent(self, "TRADE_SKILL_SHOW", self.OnTradeSkillShow)
    ns.RegisterEvent(self, "TRADE_SKILL_CLOSE", self.OnTradeSkillClose)

    -- Only while a profession window is open: bags change constantly otherwise,
    -- and a looted item is not a completed craft.
    ns.RegisterEvent(self, "BAG_UPDATE_DELAYED", function()
        if Crafting.isTradeSkillOpen then
            Crafting:OnBagUpdate()
        end
    end)

    self:RememberOutputs()
end

--------------------------------------------------------------------------------
-- Starting a craft
--------------------------------------------------------------------------------

--- Begin crafting a queued entry. Must be called from a hardware event.
--
-- Blizzard requires a real click to start a craft, so one click runs one queue
-- entry. Within an entry the client repeats the craft itself, so queueing 20 of
-- something genuinely is a single click.
function Crafting:Start(recipeID, count)
    local ready, reason = self:GetReadiness(recipeID)
    if not ready then
        ns.Print(reason or "cannot craft that")
        return false
    end

    if self.active then
        ns.Print("already crafting")
        return false
    end

    local recipe = ns.Recipes:GetAny(recipeID)

    -- Never ask for more than the bags support: the client would stop partway
    -- and the queue would be left guessing what happened.
    local craftable = ns.Profit:GetCraftableCount(recipeID)
    count = math.max(1, math.min(count or 1, craftable))

    self.active = {
        recipeID = recipeID,
        requested = count,
        outputItemID = recipe.outputItemID,
        -- Measured from what actually appears, not from counting spell casts.
        before = recipe.outputItemID and ns.Inventory:GetBagCount(recipe.outputItemID) or 0,
        startedAt = GetTime(),
    }

    local ok, err = pcall(C_TradeSkillUI.CraftRecipe, recipeID, count)
    if not ok then
        self.active = nil

        -- "Interface action failed because of an AddOn" means the client will
        -- not accept a craft from addon code at all.
        if tostring(err):lower():find("addon") then
            self:MarkBlocked()
        else
            ns.Warn(("the client refused the craft: %s"):format(
                tostring(err):gsub("^.-:%d+: ", "")))
        end
        return false
    end

    ns.Print(("crafting %dx %s..."):format(count, ns.Recipes:GetDisplayLink(recipeID)))

    self:StartWatching()
    return true
end

function Crafting:Stop()
    if ns.Util.HasFunction("C_TradeSkillUI.StopRecipeRepeat") then
        pcall(C_TradeSkillUI.StopRecipeRepeat)
    end

    self.active = nil
    self:StopWatching()

    if ns.UI then ns.UI:RefreshActiveTab() end
end

function Crafting:IsBusy()
    return self.active ~= nil
end

--- Watch for the craft loop ending.
--
-- Counting UNIT_SPELLCAST_SUCCEEDED is unreliable: the recipe ID is not always
-- the spell ID, and an interrupted run would desync the queue. The bag-watching
-- in OnBagUpdate does the actual reconciliation; this just clears the busy flag.
function Crafting:StartWatching()
    if self.ticker then self.ticker:Cancel() end

    self.ticker = C_Timer.NewTicker(0.5, function()
        if not Crafting.active then
            Crafting:StopWatching()
            return
        end

        if Crafting:IsStillCrafting() then return end

        Crafting.active = nil
        Crafting:StopWatching()

        if ns.UI then ns.UI:RefreshActiveTab() end
    end)
end

function Crafting:StopWatching()
    if self.ticker then
        self.ticker:Cancel()
        self.ticker = nil
    end
end

function Crafting:IsStillCrafting()
    if ns.Util.HasFunction("C_TradeSkillUI.IsRecipeRepeating") then
        local ok, repeating = pcall(C_TradeSkillUI.IsRecipeRepeating)
        if ok and repeating then return true end
    end

    local castOk, castName = pcall(UnitCastingInfo, "player")
    if castOk and castName then return true end

    -- A craft takes a moment to begin; do not declare it finished instantly.
    if self.active and (GetTime() - self.active.startedAt) < 1.5 then
        return true
    end

    return false
end
