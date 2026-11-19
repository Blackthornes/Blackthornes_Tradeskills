-- Blackthornes Tradeskills -- Logic/TrainerRecipes.lua
-- What a profession trainer teaches, read from the trainer's own window
-- (a player's report, the owner chose it 2026-11-19: Road to 300 never
-- offered Forever's new trainer recipes, like First Aid's Lesser Healing
-- Potion, since the book had no trainer price for any recipe Forever
-- added). Each line the trainer lists, learned or not, is kept by recipe
-- ID with its price and the skill it asks for:
--
--   ns.db.trainerRecipes[recipeID] = { cost = copper, skill = N, at = time }
--
-- account wide (never rename it). The owner's saves fold into the shipped
-- table at each release (Data/ForeverTrainerRecipes.lua, written by
-- tools/forever_trainer_recipes.py), so players get them before they visit.
-- The recipe book reads both (RecipeBook:GetAll), what this character saw
-- winning, and Road to 300 and Learn Next then treat the recipe as taught
-- by that profession's trainers.

local _, ns = ...

local TrainerRecipes = ns.NewModule("TrainerRecipes")

-- Bumped whenever a read finds something new, so a kept plan works itself
-- out again (RoadPlan's key).
TrainerRecipes.version = 0

local function Lookup(name)
    local fn = _G
    for part in name:gmatch("[^%.]+") do
        if type(fn) ~= "table" then return nil end
        fn = rawget(fn, part)
    end
    return type(fn) == "function" and fn or nil
end

local function Call(name, ...)
    local fn = Lookup(name)
    if not fn then return nil end
    local function Pass(ok, ...)
        if not ok then return nil end
        return ...
    end
    return Pass(pcall(fn, ...))
end

local function Plain(value)
    local ok, copy = pcall(function()
        if type(value) == "string" and value ~= "" then return value .. "" end
    end)
    return ok and copy or nil
end

local function Number(value)
    local ok, copy = pcall(function()
        local n = tonumber(value)
        if n and n == n and n ~= math.huge and n ~= -math.huge then return math.floor(n) end
    end)
    return ok and copy or nil
end

--- The saved table, made when asked to.
function TrainerRecipes:Store(create)
    if not ns.db then return nil end
    if create and type(ns.db.trainerRecipes) ~= "table" then ns.db.trainerRecipes = {} end
    return type(ns.db.trainerRecipes) == "table" and ns.db.trainerRecipes or nil
end

--- What is known about a recipe's trainer: { cost, skill } from this
--- account's own visits, else the shipped table; nil when neither has it.
function TrainerRecipes:Get(recipeID)
    local mine = self:Store(false)
    local row = mine and mine[recipeID]
    if type(row) == "table" and (row.cost or row.skill) then return row end
    local shipped = ns.FOREVER_TRAINER_RECIPES and ns.FOREVER_TRAINER_RECIPES[recipeID]
    if type(shipped) == "table" then return { skill = shipped[1], cost = shipped[2] } end
    return nil
end

--- Every recipe ID either table knows.
function TrainerRecipes:All()
    local ids = {}
    for id in pairs(ns.FOREVER_TRAINER_RECIPES or {}) do ids[id] = true end
    for id, row in pairs(self:Store(false) or {}) do
        if type(row) == "table" then ids[id] = true end
    end
    return ids
end

-- The recipe a trainer's line teaches: the tooltip's spell ID when the
-- client gives one the book knows, else the one recipe in the book with
-- that name.
local function RecordFor(index, name, byName)
    local book = ns.RecipeBook
    local data = Call("C_TooltipInfo.GetTrainerService", index)
    local id = type(data) == "table" and Number(data.id) or nil
    if id and book and book.Get then
        local ok, record = pcall(book.Get, book, id)
        if ok and type(record) == "table" then return record end
    end
    name = Plain(name)
    if not name then return nil end
    local found = byName[name:lower()]
    return found ~= false and found or nil
end

--- Read the open trainer, if it teaches a profession. Lines the trainer
--- hides until the skill is high enough are read with its filter flipped
--- on and then put back, as the Wishlist does.
-- @return how many lines were new or changed
function TrainerRecipes:Read()
    if Lookup("IsTradeskillTrainer") and not Call("IsTradeskillTrainer") then return 0 end
    local book = ns.RecipeBook
    if not (book and book.GetAll) then return 0 end
    local ok, all = pcall(book.GetAll, book)
    if not ok or type(all) ~= "table" then return 0 end
    -- Names that more than one recipe has are left to the tooltip's ID.
    local byName = {}
    for _, record in pairs(all) do
        if type(record.name) == "string" then
            local key = record.name:lower()
            byName[key] = byName[key] == nil and record or false
        end
    end

    local store = self:Store(true)
    if not store then return 0 end
    local changed = 0
    local function Lines()
        local count = Number(Call("GetNumTrainerServices")) or 0
        for index = 1, count do
            local name, _, kind = Call("GetTrainerServiceInfo", index)
            kind = Plain(kind)
            if kind and kind ~= "header" then
                local record = RecordFor(index, name, byName)
                local recipeID = record and Number(record.recipeID)
                local cost = Number((Call("GetTrainerServiceCost", index)))
                local skill = Number((Call("GetTrainerServiceSkillReq", index)))
                if recipeID and (cost or skill) then
                    local had = store[recipeID]
                    if type(had) ~= "table" or had.cost ~= cost or had.skill ~= skill then
                        changed = changed + 1
                    end
                    store[recipeID] = { cost = cost, skill = skill and skill > 0 and skill or nil, at = time() }
                end
            end
        end
    end

    Lines()
    local hidden = Lookup("GetTrainerServiceTypeFilter") and Lookup("SetTrainerServiceTypeFilter")
        and not Call("GetTrainerServiceTypeFilter", "unavailable")
    if hidden then
        self.flipping = true
        Call("SetTrainerServiceTypeFilter", "unavailable", 1)
        Lines()
        Call("SetTrainerServiceTypeFilter", "unavailable", 0)
        self.flipping = false
    end

    if changed > 0 then
        self.version = self.version + 1
        if book.Invalidate then pcall(book.Invalidate, book) end
    end
    return changed
end

function TrainerRecipes:OnEnable()
    if not ns.RegisterEvent then return end
    ns.RegisterEvent(self, "TRAINER_SHOW", function()
        -- The list fills a moment after the window opens.
        if C_Timer and C_Timer.After then
            C_Timer.After(0.2, function() pcall(TrainerRecipes.Read, TrainerRecipes) end)
        else
            pcall(TrainerRecipes.Read, TrainerRecipes)
        end
    end)
end
