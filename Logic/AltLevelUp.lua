-- Blackthornes Tradeskills -- Logic/AltLevelUp.lua
-- What the player's other characters need to level, for Butler (a player
-- asked, the owner said build it, 2026-11-27, from a mockup whose words he
-- approved).
--
-- Two answers, both read only:
--
--   AltLevelUp:Needs()       -- { [itemID] = { key, to, count, profession } }
--     The materials each alt's Road to 300 still needs (Logic/RoadPlan.lua,
--     from the recipes it knows only), less what it already has: bags,
--     bank, mail and what was mailed to it and not yet seen arrive
--     (QueueMail:InFlight). An item two alts need goes to the one that
--     needs most. Butler's "Send Level Up Materials to Alts:" mails these.
--
--   AltLevelUp:CanLearn(record)  -- { { key, name, profession, skill, short } }
--     The alts who have a recipe's profession and don't know it, the ones
--     who can learn it now first, then the highest skill. Butler's "Mail
--     Recipes to Who Can Learn Them:" and the tooltip's "Can Learn:" line.
--
-- Only characters the one playing can mail (same realm and side,
-- Characters:CanMail), never the one playing or a character from another
-- account, each once under all its records (Characters:Same). With no
-- GUID for the one playing (a dungeon) nobody is offered.
--
-- Smooth play: Needs is worked out only when asked (Butler asks only with
-- its box ticked), a few recipes priced a frame where the game runs
-- timers, and kept until its key moves (the alts' saved recipes, bags,
-- bank and mail, what was mailed, the scans, Pick By). While it is worked
-- out the last answer stands; when a new one differs, Butler is told to
-- judge again (`_G.BlackthornesButler.Verdicts:Changed()`, in a pcall).
-- Nothing is saved.

local _, ns = ...

local AltLevelUp = ns.NewModule("AltLevelUp")

-- Recipes priced a frame while Needs is worked out.
AltLevelUp.BUDGET = 12

local function Me()
    local key = ns.Config and ns.Config.GetCharacterKey and ns.Config:GetCharacterKey()
    if type(key) == "string" and key:find("^Player%-") then return key end
    return nil
end

local function Count(list, itemID)
    local n = type(list) == "table" and tonumber(list[itemID]) or 0
    return n or 0
end

--- The characters the one playing can mail, each { key, record, name },
--- in a fixed order. Empty when the one playing can't be told.
function AltLevelUp.Alts()
    local list = {}
    local records = ns.db and ns.db.characters
    local me = Me()
    if type(records) ~= "table" or not me then return list end
    local chars = ns.Characters
    local keys = {}
    for key in pairs(records) do keys[#keys + 1] = key end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    -- GUID records first, so an old name-realm record of the same
    -- character is the one passed over.
    table.sort(keys, function(a, b)
        local ga, gb = tostring(a):find("^Player%-") ~= nil, tostring(b):find("^Player%-") ~= nil
        if ga ~= gb then return ga end
        return tostring(a) < tostring(b)
    end)
    local counted = {}
    for _, key in ipairs(keys) do
        local record = records[key]
        local ok, skip = pcall(function()
            if type(record) ~= "table" or record.linkedFrom ~= nil then return true end
            if key == me or (chars and chars:IsPlaying(key)) then return true end
            if chars and chars.CanMail and not chars:CanMail(me, key) then return true end
            for _, other in ipairs(counted) do
                if chars and chars:Same(key, other) then return true end
            end
            return false
        end)
        if ok and not skip then
            counted[#counted + 1] = key
            local name = ns.Recipes and ns.Recipes.GetShortCharacterName
                and ns.Recipes:GetShortCharacterName(key) or tostring(key)
            list[#list + 1] = { key = key, record = record, name = name }
        end
    end
    return list
end

--- How many of an item an alt has: bags, bank, mail, and what was mailed
--- to it and not yet seen arrive.
function AltLevelUp.Has(alt, itemID)
    local record = alt.record
    local held = Count(record.inventory, itemID) + Count(record.bank, itemID) + Count(record.mail, itemID)
    local mail = ns.QueueMail
    if mail and mail.InFlight then
        local ok, coming = pcall(mail.InFlight, mail, alt.key, itemID)
        if ok and type(coming) == "number" then held = held + coming end
    end
    return held
end

-- The recipes an alt knows, in professions it still has: [recipeID] = true.
local function Knows(alt)
    local knows = {}
    local recipes = ns.Recipes
    for recipeID, recipe in pairs(type(alt.record.recipes) == "table" and alt.record.recipes or {}) do
        local dropped = recipes and recipes.IsDropped and recipes:IsDropped(recipe, alt.key)
        if not dropped then knows[recipeID] = true end
    end
    return knows
end

-- The professions an alt has learned, as saved.
local function Professions(alt)
    local list = {}
    for _, profession in ipairs(type(alt.record.professions) == "table" and alt.record.professions or {}) do
        if type(profession) == "table" and profession.learned ~= false and profession.name then
            list[#list + 1] = profession
        end
    end
    return list
end

local function English(profession)
    local recipes = ns.Recipes
    if not (recipes and recipes.EnglishProfessionName) then return nil end
    local ok, name = pcall(recipes.EnglishProfessionName, profession)
    return ok and name or nil
end

--------------------------------------------------------------------------------
-- Needs: the materials each alt's road still wants
--------------------------------------------------------------------------------

local kept         -- { key, answer }
local job          -- the one being worked out

-- What moves the answer.
local function Key(alts)
    local parts = {
        tostring(ns.Prices and ns.Prices.scanCount or 0),
        tostring(ns.RoadPlan and ns.RoadPlan.PickBy and ns.RoadPlan.PickBy() or ""),
        tostring(ns.RoadPlan and ns.RoadPlan.skipVersion or 0),
        tostring(ns.Queue and ns.Queue.version or 0),
    }
    local sent = ns.db and type(ns.db.queueMail) == "table" and type(ns.db.queueMail.sent) == "table"
        and ns.db.queueMail.sent or {}
    for _, alt in ipairs(alts) do
        local r = alt.record
        parts[#parts + 1] = table.concat({ tostring(alt.key), tostring(r.recipesCachedAt or 0),
            tostring(r.inventoryAt or 0), tostring(r.bankAt or 0), tostring(r.mailAt or 0),
            tostring(r.level or 0), tostring(type(sent[alt.key]) == "table" and #sent[alt.key] or 0) }, ":")
        for _, profession in ipairs(Professions(alt)) do
            parts[#parts + 1] = tostring(profession.skillLevel or 0) .. "/" .. tostring(profession.maxSkillLevel or 0)
        end
    end
    return table.concat(parts, "|")
end

-- Every road to work out: one an alt and profession under 300.
local function Tasks(alts)
    local road = ns.RoadPlan
    local tasks = {}
    if not (road and road.LineFor and road.KnownCandidates) then return tasks end
    for _, alt in ipairs(alts) do
        local knows
        for _, profession in ipairs(Professions(alt)) do
            local line = road.LineFor(profession)
            local skill = tonumber(profession.skillLevel) or 0
            if line and line ~= road.FISHING and road.RANKS[line] and skill > 0 and skill < road.TARGET then
                knows = knows or Knows(alt)
                tasks[#tasks + 1] = { alt = alt, profession = profession, line = line, skill = skill,
                    max = tonumber(profession.maxSkillLevel) or skill,
                    candidates = road:KnownCandidates(line, knows) }
            end
        end
    end
    return tasks
end

-- One alt's road: what it still needs, less what it has.
local function Walk(task)
    local road = ns.RoadPlan
    local owned = {}
    for _, candidate in ipairs(task.candidates) do
        for _, reagent in ipairs(candidate.price and candidate.price.reagents or {}) do
            if not owned[reagent.itemID] then
                owned[reagent.itemID] = { 0, AltLevelUp.Has(task.alt, reagent.itemID), 0 }
            end
        end
    end
    local ok, plan = pcall(road.Plan, road, {
        line = task.line, skill = task.skill, max = task.max, level = tonumber(task.alt.record.level) or 0,
        candidates = task.candidates, owned = owned, pickBy = road.PickBy(), stop = road.TARGET,
        valueOwned = true,
    })
    local needs = {}
    if not ok or type(plan) ~= "table" then return needs end
    for _, step in ipairs(plan.steps or {}) do
        if not step.done and step.kind == "craft" and not step.learn then
            for _, need in ipairs(step.needs or {}) do
                if (need.buy or 0) > 0 then needs[need.itemID] = (needs[need.itemID] or 0) + need.buy end
            end
        end
    end
    return needs
end

-- All the roads' needs, each item to the alt that needs most.
local function Gather(tasks)
    local answer = {}
    for _, task in ipairs(tasks) do
        for itemID, count in pairs(Walk(task)) do
            local best = answer[itemID]
            local name = task.alt.name
            if not best or count > best.count or (count == best.count and name < best.to) then
                answer[itemID] = { key = task.alt.key, to = name, count = count,
                    profession = task.profession.name }
            end
        end
    end
    return answer
end

local function Differs(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then return a ~= b end
    for itemID, one in pairs(a) do
        local two = b[itemID]
        if not two or two.key ~= one.key or two.count ~= one.count then return true end
    end
    for itemID in pairs(b) do
        if not a[itemID] then return true end
    end
    return false
end

-- Tell Butler a new answer is in, so its rows follow.
local function TellButler()
    local butler = rawget(_G, "BlackthornesButler")
    local verdicts = type(butler) == "table" and rawget(butler, "Verdicts")
    if type(verdicts) == "table" and type(verdicts.Changed) == "function" then
        pcall(verdicts.Changed, verdicts)
    end
end

local function Copy(answer)
    local copy = {}
    for itemID, need in pairs(answer or {}) do
        copy[itemID] = { key = need.key, to = need.to, count = need.count, profession = need.profession }
    end
    return copy
end

--- { [itemID] = { key, to, count, profession } }: what the alts' roads to
--- 300 still need, less what they have; nil while the first answer is
--- worked out. Never raises, writes nothing; a fresh table each time.
function AltLevelUp:Needs()
    local ok, answer = pcall(function()
        local alts = AltLevelUp.Alts()
        local key = Key(alts)
        if kept and kept.key == key then return kept.answer end
        if job and job.key == key then return kept and kept.answer or nil end

        local tasks = Tasks(alts)
        local road = ns.RoadPlan
        local after = rawget(_G, "C_Timer") and C_Timer.After
        if type(after) ~= "function" then
            for _, task in ipairs(tasks) do
                for _, candidate in ipairs(task.candidates) do candidate.price = road.Price(candidate.record) end
            end
            kept = { key = key, answer = Gather(tasks) }
            return kept.answer
        end

        local this = { key = key, task = 1, index = 0 }
        job = this
        local function Slice()
            if job ~= this then return end
            local priced = 0
            while priced < AltLevelUp.BUDGET do
                local task = tasks[this.task]
                if not task then
                    job = nil
                    local fine, fresh = pcall(Gather, tasks)
                    if not fine then return end
                    local old = kept and kept.answer
                    kept = { key = key, answer = fresh }
                    if Differs(old, fresh) then TellButler() end
                    return
                end
                this.index = this.index + 1
                local candidate = task.candidates[this.index]
                if candidate then
                    candidate.price = road.Price(candidate.record)
                    priced = priced + 1
                else
                    this.task, this.index = this.task + 1, 0
                end
            end
            after(0, Slice)
        end
        after(0, Slice)
        return kept and kept.answer or nil
    end)
    if not ok or type(answer) ~= "table" then return nil end
    return Copy(answer)
end

--- Forget the kept answer (a test).
function AltLevelUp:Forget()
    kept, job = nil, nil
end

--------------------------------------------------------------------------------
-- CanLearn: the alts who could learn a recipe
--------------------------------------------------------------------------------

--- The alts who have `record`'s profession and don't know it, each { key,
--- name, profession (the client's name), skill, short (true while the
--- skill is below what it needs) }: those who can learn it now first,
--- then the highest skill, then by name. Never raises.
function AltLevelUp:CanLearn(record)
    local list = {}
    if type(record) ~= "table" or type(record.profession) ~= "string" then return list end
    local ok = pcall(function()
        local book = ns.RecipeBook
        local knownBy = book and book.WhoKnows and book:WhoKnows(record) or {}
        local chars = ns.Characters
        local need = tonumber(record.skill) or 0
        for _, alt in ipairs(AltLevelUp.Alts()) do
            local knows = type(alt.record.recipes) == "table" and alt.record.recipes[record.recipeID] ~= nil
            for _, key in ipairs(knownBy) do
                if key == alt.key or (chars and chars:Same(key, alt.key)) then knows = true end
            end
            if not knows then
                for _, profession in ipairs(Professions(alt)) do
                    if English(profession) == record.profession then
                        local skill = tonumber(profession.skillLevel) or 0
                        list[#list + 1] = { key = alt.key, name = alt.name, profession = profession.name,
                            skill = skill, short = skill < need or nil }
                        break
                    end
                end
            end
        end
        table.sort(list, function(a, b)
            if (a.short or false) ~= (b.short or false) then return not a.short end
            if a.skill ~= b.skill then return a.skill > b.skill end
            return a.name < b.name
        end)
    end)
    if not ok then return {} end
    return list
end

--- Can the character playing learn it now itself: the profession, the
--- skill, and not known? Then Butler keeps it here.
function AltLevelUp:PlayingCanLearn(record)
    if type(record) ~= "table" then return false end
    local ok, can = pcall(function()
        local book = ns.RecipeBook
        if book and book.KnowsIt and book:KnowsIt(record) then return false end
        local learned = ns.Recipes and ns.Recipes.GetLearnedProfessions and ns.Recipes:GetLearnedProfessions() or {}
        for _, profession in ipairs(learned) do
            if English(profession) == record.profession then
                return (tonumber(profession.skillLevel) or 0) >= (tonumber(record.skill) or 0)
            end
        end
        return false
    end)
    return ok and can == true
end
