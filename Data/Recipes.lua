-- Blackthornes Tradeskills -- Data/Recipes.lua
-- Recipe discovery and caching.
--
-- GetAllRecipeIDs only returns anything while a profession window is open, so
-- recipes are harvested opportunistically when that window appears and served
-- from cache forever after. That is what makes the profit table work while you
-- are standing at the auction house with no profession open.

local _, ns = ...

local Recipes = ns.NewModule("Recipes")

local Util = ns.Util

-- Blizzard ships an internal test profession on the Forever beta. It has no
-- recipes and no business appearing in anyone's profession list.
local IGNORED_PROFESSION_PATTERN = "%[DNT%]"

--------------------------------------------------------------------------------
-- Professions
--------------------------------------------------------------------------------

--- The character's professions, deduplicated.
--
-- GetAllProfessionTradeSkillLines returns each profession twice on Forever,
-- once under a modern skill-line ID and once under the classic one (e.g.
-- Leatherworking is both 2945 and 165). Both report identical skill levels, so
-- we keep the first sighting per name and drop the rest.
function Recipes:GetProfessions()
    local trade = ns.Compat:Get().tradeskill
    if not trade.hasAllProfessionLines then return {} end

    local ok, skillLines = pcall(C_TradeSkillUI.GetAllProfessionTradeSkillLines)
    if not ok or type(skillLines) ~= "table" then return {} end

    local seen, professions = {}, {}

    for _, skillLineID in ipairs(skillLines) do
        local infoOk, info = pcall(C_TradeSkillUI.GetProfessionInfoBySkillLineID, skillLineID)

        if infoOk and info and info.professionName then
            local name = info.professionName

            if not seen[name] and not name:find(IGNORED_PROFESSION_PATTERN) then
                seen[name] = true

                professions[#professions + 1] = {
                    name = name,
                    skillLineID = skillLineID,
                    skillLevel = info.skillLevel or 0,
                    maxSkillLevel = info.maxSkillLevel or 0,
                    -- Levels of zero mean the profession is listed but unlearned.
                    learned = (info.maxSkillLevel or 0) > 0,
                }
            end
        end
    end

    table.sort(professions, function(a, b) return a.name < b.name end)
    return professions
end

function Recipes:GetLearnedProfessions()
    local learned = {}
    for _, profession in ipairs(self:GetProfessions()) do
        if profession.learned then
            learned[#learned + 1] = profession
        end
    end
    return learned
end

--------------------------------------------------------------------------------
-- Cache access
--------------------------------------------------------------------------------

local function GetCharacterRecord(create)
    if not ns.db then return nil end

    local key = ns.Config:GetCharacterKey()
    local characters = ns.db.characters

    local record = characters[key]
    if not record and create then
        -- Plain copies: inside a dungeon the client can hand back names
        -- that raise when compared, and a stored one would raise forever.
        local Plain = ns.Config.PlainString
        record = {
            name = Plain and Plain(UnitName, "player") or "Unknown",
            realm = GetRealmName and Plain and Plain(GetRealmName) or "?",
            recipes = {},
            inventory = {},
        }
        characters[key] = record
    end

    if record and not Recipes.identityStamped and key == ns.Config.characterKey then
        -- Protected: a name the client will not let us compare must not stop
        -- the recipe cache from loading.
        pcall(Recipes.StampIdentity, Recipes, record)
    end

    return record
end

Recipes.GetCharacterRecord = function(_, create) return GetCharacterRecord(create) end

--- Cached recipes for the logged-in character.
function Recipes:GetAll()
    local record = GetCharacterRecord(false)
    return record and record.recipes or {}
end

function Recipes:Get(recipeID)
    return self:GetAll()[recipeID]
end

--- A recipe from any character's cache, preferring the logged-in one.
--
-- Lets the cost and profit engines reason about crafts that live on an alt,
-- without every caller having to know which character owns what.
-- @return recipe, characterKey
function Recipes:GetAny(recipeID)
    local mine = self:GetAll()[recipeID]
    if mine then
        return mine, ns.Config:GetCharacterKey()
    end

    if not ns.db then return nil end

    for characterKey, record in pairs(ns.db.characters) do
        local recipe = record.recipes and record.recipes[recipeID]
        if recipe then
            return recipe, characterKey
        end
    end
end

--- Who a record belongs to, written once a session so that characters
--- sharing a first name can be told apart on screen.
function Recipes:StampIdentity(record)
    self.identityStamped = true

    local guid = ns.Config.characterKey
    if guid then record.guid = guid end

    local name = ns.Config.PlainString and ns.Config.PlainString(UnitName, "player")
    if name then record.name = name end

    local surname = ns.Config:ReadSurname()
    if surname then record.surname = surname end

    local classOk, className = pcall(UnitClass, "player")
    if classOk and type(className) == "string" then record.class = className end

    local levelOk, level = pcall(UnitLevel, "player")
    if levelOk and tonumber(level) then record.level = tonumber(level) end
end

--- The character's name, for display: first and last name when the last one
--- is known. Old keys are "Name-Realm"; new ones are the character's GUID.
function Recipes:GetCharacterName(characterKey)
    if not characterKey then return "?" end

    local record = ns.db and ns.db.characters[characterKey]
    if type(record) == "table" and type(record.name) == "string" then
        if record.surname then
            return record.name .. " " .. record.surname
        end
        return record.name
    end

    return (characterKey:match("^([^-]+)")) or characterKey
end

--- What to add after a name that another character also has.
local function Distinguish(record)
    if type(record) ~= "table" then return nil end

    if record.level and record.class then
        return ("level %d %s"):format(record.level, record.class)
    end
    if record.class then return record.class end
    if not record.guid then return "saved before last names" end
end

--- Every known character, newest data first.
function Recipes:GetCharacters()
    local characters = {}
    if not ns.db then return characters end

    local selfKey = ns.Config:GetCharacterKey()

    for characterKey, record in pairs(ns.db.characters) do
        characters[#characters + 1] = {
            key = characterKey,
            name = self:GetCharacterName(characterKey),
            realm = record.realm,
            gold = record.gold,
            professions = record.professions,
            recipeCount = record.recipes and Util.Count(record.recipes) or 0,
            inventoryAt = record.inventoryAt,
            bankAt = record.bankAt,
            isCurrent = characterKey == selfKey,
        }
    end

    -- Two characters showing the same name get told apart by level and class.
    local seen = {}
    for _, entry in ipairs(characters) do
        seen[entry.name] = (seen[entry.name] or 0) + 1
    end

    for _, entry in ipairs(characters) do
        if seen[entry.name] > 1 then
            local extra = Distinguish(ns.db.characters[entry.key])
            if extra then
                entry.name = ("%s (%s)"):format(entry.name, extra)
            end
        end
    end

    table.sort(characters, function(a, b)
        if a.isCurrent ~= b.isCurrent then return a.isCurrent end
        if a.name ~= b.name then return a.name < b.name end
        return a.key < b.key
    end)

    return characters
end

function Recipes:ForgetCharacter(characterKey)
    if not ns.db or characterKey == ns.Config:GetCharacterKey() then return false end

    ns.db.characters[characterKey] = nil
    ns.Cost:InvalidateIndex()
    return true
end

function Recipes:Count()
    return Util.Count(self:GetAll())
end

--- Every cached recipe across all characters, tagged with who knows it.
function Recipes:GetAccountWide()
    local results = {}
    if not ns.db then return results end

    for characterKey, record in pairs(ns.db.characters) do
        for recipeID, recipe in pairs(record.recipes or {}) do
            local existing = results[recipeID]
            if existing then
                existing.knownBy[#existing.knownBy + 1] = characterKey
            else
                local copy = Util.CopyDeep(recipe)
                copy.knownBy = { characterKey }
                results[recipeID] = copy
            end
        end
    end

    return results
end

--- Which skill line a recipe belongs to.
--
-- GetRecipeInfo does not carry skillLineID on Forever -- it comes back nil for
-- every recipe, which silently empties the profession filter. These two calls
-- do report it.
local function GetRecipeSkillLine(recipeID, info)
    if info and info.skillLineID then return info.skillLineID end

    if Util.HasFunction("C_TradeSkillUI.GetTradeSkillLineForRecipe") then
        local ok, skillLineID = pcall(C_TradeSkillUI.GetTradeSkillLineForRecipe, recipeID)
        if ok and skillLineID then return skillLineID end
    end

    if Util.HasFunction("C_TradeSkillUI.GetProfessionInfoByRecipeID") then
        local ok, professionInfo = pcall(C_TradeSkillUI.GetProfessionInfoByRecipeID, recipeID)
        if ok and professionInfo and professionInfo.professionID then
            return professionInfo.professionID
        end
    end

    return nil
end

--------------------------------------------------------------------------------
-- Lookup
--------------------------------------------------------------------------------

--- A clickable link for a recipe's output, falling back to its plain name.
-- Players recognise the item, not the recipe ID, so this is what gets shown.
function Recipes:GetDisplayLink(recipeID)
    local recipe = self:Get(recipeID)

    if Util.HasFunction("C_TradeSkillUI.GetRecipeItemLink") then
        local ok, link = pcall(C_TradeSkillUI.GetRecipeItemLink, recipeID)
        if ok and link then return link end
    end

    if recipe and recipe.outputItemID and Util.HasFunction("C_Item.GetItemInfo") then
        local ok, _, link = pcall(C_Item.GetItemInfo, recipe.outputItemID)
        if ok and link then return link end
    end

    return (recipe and recipe.name) or ("recipe " .. tostring(recipeID))
end

--- Resolve whatever the player typed into matching recipes.
--
-- Accepts a shift-clicked item link, a recipe or item ID, or any part of a
-- recipe name. Returns an array of matches, best first.
function Recipes:Find(query)
    query = (query or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if query == "" then return {} end

    local all = self:GetAll()

    -- A shift-clicked link carries the item ID, which is the exact answer.
    local linkedItemID = tonumber(query:match("item:(%d+)"))
    if linkedItemID then
        for recipeID, recipe in pairs(all) do
            if recipe.outputItemID == linkedItemID then
                return { recipe }
            end
        end
        return {}
    end

    -- A bare number is either a recipe ID or an output item ID.
    local number = tonumber(query)
    if number then
        if all[number] then return { all[number] } end

        for _, recipe in pairs(all) do
            if recipe.outputItemID == number then
                return { recipe }
            end
        end
        return {}
    end

    -- Otherwise match on name. Exact beats prefix beats substring, so typing
    -- "bolt of linen" does not lose to "bolt of linen cloth bandage".
    local needle = query:lower()
    local exact, prefix, substring = {}, {}, {}

    for _, recipe in pairs(all) do
        local name = (recipe.name or ""):lower()

        if name == needle then
            exact[#exact + 1] = recipe
        elseif name:sub(1, #needle) == needle then
            prefix[#prefix + 1] = recipe
        elseif name:find(needle, 1, true) then
            substring[#substring + 1] = recipe
        end
    end

    local matches = {}
    for _, list in ipairs({ exact, prefix, substring }) do
        table.sort(list, function(a, b) return (a.name or "") < (b.name or "") end)
        for _, recipe in ipairs(list) do
            matches[#matches + 1] = recipe
        end
    end

    return matches
end

--------------------------------------------------------------------------------
-- Harvesting
--------------------------------------------------------------------------------

--- Read every recipe the open profession window exposes into the cache.
function Recipes:Harvest()
    local trade = ns.Compat:Get().tradeskill
    if trade.mode ~= "modern" then return false end
    if self.harvesting then return false end

    local ok, recipeIDs = pcall(C_TradeSkillUI.GetAllRecipeIDs)
    if not ok or type(recipeIDs) ~= "table" or #recipeIDs == 0 then
        return false
    end

    local record = GetCharacterRecord(true)
    if not record then return false end

    self.harvesting = true

    -- Difficulties are only readable while this window is open, so they are
    -- collected alongside the recipes rather than looked up later.
    if ns.SkillUp then ns.SkillUp:BeginCapture() end

    local added, updated = 0, 0

    local worker = Util.NewWorker({
        budgetMs = ns.Config:Get("scanBudgetMs") or 8,

        onItem = function(recipeID)
            local infoOk, info = pcall(C_TradeSkillUI.GetRecipeInfo, recipeID)
            if not infoOk or not info then return end

            -- Recipes the character has not learned cannot be crafted, so they
            -- have no place in a "what should I make" table.
            if info.learned == false then return end

            local schematicOk, schematic = pcall(C_TradeSkillUI.GetRecipeSchematic, recipeID, false)
            if not schematicOk or not schematic then return end

            local reagents = {}
            for _, slot in ipairs(schematic.reagentSlotSchematics or {}) do
                -- reagentType 1 is a required basic reagent. Optional and
                -- finishing slots are not part of the base cost.
                local isRequired = (slot.reagentType == nil or slot.reagentType == 1)
                local first = slot.reagents and slot.reagents[1]

                if isRequired and first and first.itemID and (slot.quantityRequired or 0) > 0 then
                    reagents[#reagents + 1] = {
                        itemID = first.itemID,
                        quantity = slot.quantityRequired,
                    }
                end
            end

            if #reagents == 0 then return end

            local existing = record.recipes[recipeID]
            if existing then updated = updated + 1 else added = added + 1 end

            local skillLineID = GetRecipeSkillLine(recipeID, info)

            -- Whether this still skills you up, kept with the recipe so the
            -- Profit tab can say so at the auction house, where no profession
            -- window is open to ask.
            local skillUp = existing and existing.skillUp or nil
            if ns.SkillUp then
                skillUp = ns.SkillUp:Capture(recipeID, info, skillLineID, skillUp)
            end

            record.recipes[recipeID] = {
                recipeID = recipeID,
                name = info.name or schematic.name,
                outputItemID = schematic.outputItemID,
                quantityMin = schematic.quantityMin or 1,
                quantityMax = schematic.quantityMax or schematic.quantityMin or 1,
                skillLineID = skillLineID,
                skillUp = skillUp,
                reagents = reagents,
                cachedAt = time(),
            }
        end,

        onDone = function()
            self.harvesting = false
            record.recipesCachedAt = time()

            if ns.SkillUp then ns.SkillUp:EndCapture() end

            if added > 0 or updated > 0 then
                ns.Debug(("saved %d new and %d updated recipe(s)"):format(added, updated))
            end

            if ns.UI and ns.UI.OnRecipesUpdated then
                ns.UI:OnRecipesUpdated()
            end
        end,

        onCancel = function()
            self.harvesting = false
            if ns.SkillUp then ns.SkillUp:EndCapture() end
        end,
    })

    worker:Start(recipeIDs)
    return true
end

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------

function Recipes:OnTradeSkillUpdate()
    -- A profession window is open, so skill levels are certainly loaded now.
    -- This is the read that fixes a zeroed one from login.
    self:RefreshProfessions()

    -- The list fires repeatedly while a profession window settles; coalesce.
    if self.harvestTimer then
        self.harvestTimer:Cancel()
    end

    self.harvestTimer = C_Timer.NewTimer(0.5, function()
        Recipes.harvestTimer = nil
        Recipes:Harvest()
    end)
end

--- Re-read professions into the cache, refusing to make things worse.
--
-- At PLAYER_LOGIN the profession list is already enumerable but the skill
-- levels are not loaded yet, so every profession reads as maxSkillLevel 0 and
-- therefore unlearned. That was harmless while the database was rebuilt each
-- session; now that it persists, a bad read at login would stick.
--
-- So a read with nothing learned is only accepted when there is nothing
-- better already stored.
-- @return true if the cache now holds a learned profession
-- @return true if this read itself found one (the login retry waits for that)
function Recipes:RefreshProfessions()
    local record = GetCharacterRecord(true)
    if not record then return false end

    local fresh = self:GetProfessions()

    local function AnyLearned(list)
        for _, profession in ipairs(list or {}) do
            if profession.learned then return true end
        end
        return false
    end

    if AnyLearned(fresh) or not AnyLearned(record.professions) then
        record.professions = fresh
    end

    return AnyLearned(record.professions), AnyLearned(fresh)
end

function Recipes:OnEnable()
    ns.RegisterEvent(self, "TRADE_SKILL_LIST_UPDATE", self.OnTradeSkillUpdate)
    ns.RegisterEvent(self, "TRADE_SKILL_SHOW", self.OnTradeSkillUpdate)

    -- Skill levels arrive after login, so the first read is usually zeroes.
    -- Retried a few times rather than once: how long it takes varies, and
    -- the cost of asking again is a single API call.
    self:RefreshProfessions()

    local attempts = 0
    self.professionTimer = C_Timer.NewTicker(3, function()
        attempts = attempts + 1

        -- Stopped on a fresh read that found something: the saved list
        -- already holds last session's professions, so it proves nothing
        -- about whether this session's skill levels have arrived yet.
        local _, freshLearned = Recipes:RefreshProfessions()
        if freshLearned or attempts >= 5 then
            if Recipes.professionTimer then
                Recipes.professionTimer:Cancel()
                Recipes.professionTimer = nil
            end
        end
    end)
end

--------------------------------------------------------------------------------
-- Commands
--------------------------------------------------------------------------------

ns.RegisterCommand("professions", "list this character's professions", function()
    local professions = ns.Recipes:GetProfessions()
    if #professions == 0 then
        ns.Print("no professions found")
        return
    end

    ns.Print("professions")
    for _, profession in ipairs(professions) do
        if profession.learned then
            ns.PrintRaw(("  |c%s%s|r %d/%d"):format(
                ns.COLORS.accent, profession.name, profession.skillLevel, profession.maxSkillLevel))
        else
            ns.PrintRaw(("  |c%s%s (not learned)|r"):format(ns.COLORS.muted, profession.name))
        end
    end

    ns.PrintRaw(("  |c%s%d recipe(s) saved|r"):format(ns.COLORS.muted, ns.Recipes:Count()))
end)
