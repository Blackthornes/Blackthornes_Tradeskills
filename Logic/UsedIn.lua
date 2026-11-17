-- Blackthornes Tradeskills -- Logic/UsedIn.lua
-- Which professions use a material, for the item tooltip's "Used in" line
-- (asked 2026-11-17, from a player's idea).
--
-- Two lookups, both built over frames by a worker and never on hover:
--   book   [itemID] = { record, ... }  every recipe in the shipped book with
--          what profession windows showed laid over it (RecipeBook:GetAll).
--   known  [itemID] = { [profession] = { [recipeID] = recipe } }  the
--          recipes the account's characters know, leaving out professions a
--          character dropped and a material that is also what the recipe
--          makes (as Butler's reagent index does).
-- The known one is marked stale only when a harvest saves new recipes, a
-- character is forgotten, or a profession is dropped, and is then built
-- again over frames. A tooltip reads two tables and a kept answer per item;
-- until a lookup is ready, the line is left out.
--
-- Nothing about who knows a recipe leaves this file: only professions,
-- counts and recipe names reach the tooltip.

local _, ns = ...
local L = ns.L or setmetatable({ Format = string.format }, { __index = function(_, key) return key end })

local UsedIn = ns.NewModule("UsedIn")

local Util = ns.Util

-- Recipe names shown for each profession while Shift is held.
UsedIn.NAMES = 3

-- Recipes a frame's worker reads before it checks the clock is the worker's
-- own business; this is its share of each frame.
UsedIn.BUDGET_MS = 4

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

--- The English profession name the addon keeps, from a skill line or a
--- book record.
local function ProfessionOf(recipe, recipeID)
    local recipes = ns.Recipes
    local lines = recipes and recipes.SKILL_LINE_PROFESSIONS
    local skillLineID = type(recipe) == "table" and recipe.skillLineID or nil
    if lines and skillLineID and lines[skillLineID] then return lines[skillLineID] end
    if type(recipe) == "table" and type(recipe.profession) == "string" then return recipe.profession end
    local book = ns.RecipeBook
    if book and book.ProfessionName and skillLineID then
        local ok, name = pcall(book.ProfessionName, book, skillLineID)
        if ok and type(name) == "string" then return name end
    end
    if book and book.Get and recipeID then
        local ok, record = pcall(book.Get, book, recipeID)
        if ok and type(record) == "table" and type(record.profession) == "string" then
            return record.profession
        end
    end
    return nil
end

--- A profession's name as the client shows it.
local function ProfessionLabel(profession)
    local auctions = ns.Auctions
    if auctions and auctions.ProfessionLabel then
        local ok, label = pcall(auctions.ProfessionLabel, auctions, profession)
        if ok and type(label) == "string" and label ~= "" then return label end
    end
    return L[profession] or profession
end

--- The skill a known recipe needs, or nil when nothing says.
local function SkillOf(recipeID, recipe)
    if type(recipe) == "table" and type(recipe.skill) == "number" then return recipe.skill end
    local book = ns.RecipeBook
    if book and book.GetSkill then
        local ok, skill = pcall(book.GetSkill, book, recipeID)
        if ok and type(skill) == "number" then return skill end
    end
    return nil
end

--- Easiest first; a recipe with no known skill after the rest, then by name.
local function Easier(a, b)
    if a.skill ~= b.skill then
        if a.skill == nil then return false end
        if b.skill == nil then return true end
        return a.skill < b.skill
    end
    return (a.name or "") < (b.name or "")
end

--- Most recipes first, then by name.
local function Busier(a, b)
    if a.count ~= b.count then return a.count > b.count end
    return a.label < b.label
end

--- Every material of a recipe that is not also what it makes.
local function EachMaterial(recipe, fn)
    local reagents = type(recipe) == "table" and recipe.reagents
    if type(reagents) ~= "table" then return end
    local made = recipe.outputItemID
    for _, reagent in ipairs(reagents) do
        local id = type(reagent) == "table" and tonumber(reagent.itemID)
        if id and id ~= made then fn(id) end
    end
end

--------------------------------------------------------------------------------
-- Building the lookups
--------------------------------------------------------------------------------

function UsedIn:Forget()
    self.answers = {}
end

--- Build the book lookup over frames, once a session (and again when new
--- recipes are seen).
function UsedIn:BuildBook()
    if self.bookWorker then self.bookWorker:Cancel() end
    local book = ns.RecipeBook
    if not (book and book.GetAll) then return end
    local ok, merged = pcall(book.GetAll, book)
    if not ok or type(merged) ~= "table" then return end

    local records = {}
    for _, record in pairs(merged) do
        if type(record) == "table" and record.profession then records[#records + 1] = record end
    end

    local index = {}
    local worker
    worker = Util.NewWorker({
        budgetMs = UsedIn.BUDGET_MS,
        onItem = function(record)
            EachMaterial(record, function(id)
                local list = index[id]
                if not list then list = {}; index[id] = list end
                list[#list + 1] = record
            end)
        end,
        onDone = function()
            if UsedIn.bookWorker ~= worker then return end
            UsedIn.bookWorker = nil
            UsedIn.book = index
            UsedIn:Forget()
        end,
        onCancel = function()
            if UsedIn.bookWorker == worker then UsedIn.bookWorker = nil end
        end,
    })
    self.bookWorker = worker
    self.builds = (self.builds or 0) + 1
    worker:Start(records)
end

--- Build the known lookup over frames. The old one keeps answering until
--- the new one is done.
function UsedIn:BuildKnown()
    if self.knownWorker then self.knownWorker:Cancel() end
    self.knownStale = nil
    local recipes = ns.Recipes
    local characters = ns.db and ns.db.characters
    if type(characters) ~= "table" then return end

    local entries = {}
    for characterKey, record in pairs(characters) do
        if type(record) == "table" and type(record.recipes) == "table" then
            for recipeID, recipe in pairs(record.recipes) do
                if type(recipe) == "table"
                    and not (recipes and recipes.IsDropped and recipes:IsDropped(recipe, characterKey)) then
                    entries[#entries + 1] = { recipeID, recipe }
                end
            end
        end
    end

    local index = {}
    local worker
    worker = Util.NewWorker({
        budgetMs = UsedIn.BUDGET_MS,
        onItem = function(entry)
            local recipeID, recipe = entry[1], entry[2]
            local profession = ProfessionOf(recipe, recipeID)
            if not profession then return end
            EachMaterial(recipe, function(id)
                local byProfession = index[id]
                if not byProfession then byProfession = {}; index[id] = byProfession end
                local list = byProfession[profession]
                if not list then list = {}; byProfession[profession] = list end
                list[recipeID] = recipe
            end)
        end,
        onDone = function()
            if UsedIn.knownWorker ~= worker then return end
            UsedIn.knownWorker = nil
            UsedIn.known = index
            UsedIn:Forget()
        end,
        onCancel = function()
            if UsedIn.knownWorker == worker then UsedIn.knownWorker = nil end
        end,
    })
    self.knownWorker = worker
    self.builds = (self.builds or 0) + 1
    worker:Start(entries)
end

--- New recipes were saved, a character was forgotten or a profession was
--- dropped: build the known lookup again, over frames. Only once it was
--- built at all; otherwise the first tooltip builds it.
function UsedIn:Stale(bookToo)
    if bookToo and (self.book or self.bookWorker) then self:BuildBook() end
    if self.known or self.knownWorker then self:BuildKnown() end
end

--- Start whichever lookup is missing. Starting a worker is all that happens
--- here; the work runs over the next frames.
function UsedIn:Ensure()
    if not self.book and not self.bookWorker then self:BuildBook() end
    if not self.known and not self.knownWorker then self:BuildKnown() end
end

function UsedIn:IsReady()
    return self.book ~= nil and self.known ~= nil
end

--------------------------------------------------------------------------------
-- The answer for one item
--------------------------------------------------------------------------------

local function JoinNames(list)
    local names = {}
    for i = 1, math.min(#list, UsedIn.NAMES) do names[#names + 1] = list[i].name or "?" end
    local text = table.concat(names, ", ")
    local more = #list - UsedIn.NAMES
    if more > 0 then text = text .. " " .. L.Format("and %d more", more) end
    return text
end

--- What the tooltip says about an item, kept until a lookup is rebuilt.
-- @return nil while the lookups are being built or no recipe uses it, else
--   { mine = true, counts = "First Aid (2), Tailoring (1)",
--     professions = { { label, names }, ... } }
--   or { mine = false, list = "Blacksmithing, Engineering",
--     example = "Iron Fists (Blacksmithing 130)" }
function UsedIn:For(itemID)
    itemID = tonumber(itemID)
    if not itemID then return nil end
    self:Ensure()
    if not self:IsReady() then return nil end

    self.answers = self.answers or {}
    local kept = self.answers[itemID]
    if kept ~= nil then return kept or nil end

    local answer = self:Work(itemID)
    self.answers[itemID] = answer or false
    return answer
end

function UsedIn:Work(itemID)
    local byProfession = self.known[itemID]
    if byProfession and next(byProfession) then
        local professions = {}
        for profession, list in pairs(byProfession) do
            local recipes = {}
            for recipeID, recipe in pairs(list) do
                recipes[#recipes + 1] = { name = recipe.name, skill = SkillOf(recipeID, recipe) }
            end
            table.sort(recipes, Easier)
            professions[#professions + 1] = { label = ProfessionLabel(profession), count = #recipes, recipes = recipes }
        end
        table.sort(professions, Busier)

        local counts, lines = {}, {}
        for _, profession in ipairs(professions) do
            counts[#counts + 1] = L.Format("%s (%d)", profession.label, profession.count)
            lines[#lines + 1] = { profession.label, JoinNames(profession.recipes) }
        end
        return { mine = true, counts = table.concat(counts, ", "), professions = lines }
    end

    local list = self.book[itemID]
    if not list or #list == 0 then return nil end

    local byName = {}
    for _, record in ipairs(list) do
        local group = byName[record.profession]
        if not group then group = {}; byName[record.profession] = group end
        group[#group + 1] = { name = record.name, skill = record.skill }
    end
    local professions = {}
    for profession, recipes in pairs(byName) do
        table.sort(recipes, Easier)
        professions[#professions + 1] = { label = ProfessionLabel(profession), count = #recipes, recipes = recipes }
    end
    table.sort(professions, Busier)

    local labels = {}
    for _, profession in ipairs(professions) do labels[#labels + 1] = profession.label end

    local top = professions[1]
    local easiest = top.recipes[1]
    local example
    if easiest.skill then
        example = L.Format("%s (%s %d)", easiest.name or "?", top.label, easiest.skill)
    else
        example = L.Format("%s (%s)", easiest.name or "?", top.label)
    end
    return { mine = false, list = table.concat(labels, ", "), example = example }
end

--------------------------------------------------------------------------------
-- Tooltip width
--------------------------------------------------------------------------------

-- Characters on one tooltip line before the rest goes on the next. The
-- tooltip's right side never wraps by itself, so a long list would stretch
-- it across the screen; it is broken here instead, never cut.
UsedIn.WIDTH = 44

--- Letters, not bytes (Russian and Chinese take two or three bytes each).
local function Length(text)
    local _, count = text:gsub("[^\128-\191]", "")
    return count
end

--- Break a list into lines of about WIDTH characters, at a ", " or a space.
function UsedIn.Wrap(text, width)
    width = width or UsedIn.WIDTH
    local out = {}
    if type(text) ~= "string" then return out end
    local line = ""
    for word in text:gmatch("%S+") do
        local joined = line == "" and word or (line .. " " .. word)
        if Length(joined) > width and line ~= "" then
            out[#out + 1] = line
            line = word
        else
            line = joined
        end
    end
    if line ~= "" then out[#out + 1] = line end
    return out
end
