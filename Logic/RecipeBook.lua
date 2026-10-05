-- Blackthornes Tradeskills -- Logic/RecipeBook.lua
-- Every recipe, learned or not, and what each is worth making.
--
-- Asked 2026-10-05 by a player: "is there a way to see make costs and
-- disenchants for a recipe you haven't learnt yet? Would love to know if
-- it's worth it to get a recipe or not at a glance", at the auction house
-- and as a list of every recipe a profession has.
--
-- The rest of the addon only knows recipes a character has learned, read
-- from the profession window (Data/Recipes.lua). A recipe item at the auction
-- house is just an item to the game: nothing says what it teaches. So two
-- sources are laid together here:
--
--   * Data/RecipeBook.lua, generated from Classic 1.12 data: every recipe of
--     every crafting profession, what it makes and from what, and which
--     recipe item teaches it, with who sells or drops that item.
--   * What profession windows have shown on this account, learned or not
--     (`seenRecipes`, written by Recipes:Harvest). Where Forever differs
--     from Classic, the game wins, and recipes Forever added are listed from
--     here alone.
--
-- Values follow the house rules: materials at what they cost to buy (a
-- vendor's price for what a vendor sells), what one craft gets back the way
-- the Level Up tab works it out (LevelUp:GetReturns: a grey item at vendor
-- only, a disenchant at its most likely result), and nothing is ever priced
-- from a missing number.

local _, ns = ...

local RecipeBook = ns.NewModule("RecipeBook")

local Util = ns.Util

-- Forever lists each profession under a second, modern skill line as well
-- (docs/FOREVER_API_FINDINGS.md). Recipes the game shows may carry either.
local MODERN_SKILL_LINES = {
    [2937] = 171, [2938] = 164, [2940] = 333, [2941] = 202,
    [2945] = 165, [2946] = 186, [2948] = 197,
}

-- The game's item class for recipes.
local CLASS_RECIPE = 9

-- How long a read of who knows what is reused. Hovering down a column of
-- recipe items at the auction house asks once, not once per row.
local KNOWN_TTL = 5

local function Book()
    return ns.RECIPE_BOOK or { PROFESSIONS = {}, RECIPES = {}, ITEMS = {} }
end

local function SeenTable(create)
    if not ns.db then return nil end
    if create and type(ns.db.seenRecipes) ~= "table" then ns.db.seenRecipes = {} end
    return ns.db.seenRecipes
end

--- A plain, non-empty string from a client call, or nil. Copied inside the
--- pcall: in a dungeon the client can hand back one that raises when used.
local function PlainString(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, value = pcall(function(...)
        local v = fn(...)
        if type(v) == "string" and v ~= "" then return v .. "" end
    end, ...)
    if ok then return value end
    return nil
end

local function Now()
    return (type(GetTime) == "function" and GetTime()) or time()
end

--------------------------------------------------------------------------------
-- Professions
--------------------------------------------------------------------------------

--- A profession's name from a skill line, either of Forever's two.
function RecipeBook:ProfessionName(skillLineID)
    if type(skillLineID) ~= "number" then return nil end

    local professions = Book().PROFESSIONS
    local name = professions[MODERN_SKILL_LINES[skillLineID] or skillLineID]
    if name then return name end

    local get = C_TradeSkillUI and C_TradeSkillUI.GetProfessionInfoBySkillLineID
    if type(get) == "function" then
        local ok, info = pcall(get, skillLineID)
        if ok and type(info) == "table" then
            return PlainString(function() return info.professionName end)
        end
    end

    return nil
end

--------------------------------------------------------------------------------
-- What the profession window shows
--------------------------------------------------------------------------------

--- Remember a recipe a profession window showed, learned or not.
--- Called by Recipes:Harvest. Nothing about who was looking is kept.
function RecipeBook:NoteSeen(recipeID, data)
    if type(recipeID) ~= "number" or type(data) ~= "table" then return end

    local seen = SeenTable(true)
    if not seen then return end

    local reagents = {}
    for _, reagent in ipairs(data.reagents or {}) do
        reagents[#reagents + 1] = { itemID = reagent.itemID, quantity = reagent.quantity }
    end

    local old = seen[recipeID]
    seen[recipeID] = {
        name = data.name or (old and old.name),
        outputItemID = data.outputItemID,
        quantityMin = data.quantityMin or 1,
        quantityMax = data.quantityMax or data.quantityMin or 1,
        skillLineID = data.skillLineID,
        profession = self:ProfessionName(data.skillLineID) or (old and old.profession),
        reagents = reagents,
        seenAt = time(),
    }

    self.merged = nil
end

--------------------------------------------------------------------------------
-- The merged book
--------------------------------------------------------------------------------

--- Every recipe, the shipped book with what the game showed laid over it.
--
-- @return merged  { [recipeID] = record } in Data/Recipes.lua's shape plus
--   profession, skill, trainerCost, starter, recipeItems, seenInGame
-- @return aliases { [book recipe ID] = game recipe ID } where the game listed
--   a Classic recipe under an ID of its own
function RecipeBook:GetAll()
    if self.merged then return self.merged, self.aliases end

    local book = Book()
    local merged, aliases, byOutput, byName = {}, {}, {}, {}

    local itemsFor = {}
    for itemID, row in pairs(book.ITEMS) do
        local list = itemsFor[row[1]]
        if not list then list = {}; itemsFor[row[1]] = list end
        list[#list + 1] = itemID
    end
    for _, list in pairs(itemsFor) do table.sort(list) end

    for recipeID, row in pairs(book.RECIPES) do
        local reagents = {}
        local materials = row[6] or {}
        for i = 1, #materials - 1, 2 do
            reagents[#reagents + 1] = { itemID = materials[i], quantity = materials[i + 1] }
        end

        local record = {
            recipeID = recipeID,
            name = row[7],
            skillLineID = row[1],
            profession = book.PROFESSIONS[row[1]],
            skill = row[2],
            outputItemID = (row[3] or 0) ~= 0 and row[3] or nil,
            quantityMin = row[4] or 1,
            quantityMax = row[5] or row[4] or 1,
            reagents = reagents,
            trainerCost = row.t,
            starter = row.s == 1,
            recipeItems = itemsFor[recipeID],
        }

        merged[recipeID] = record
        if record.outputItemID then byOutput[record.outputItemID] = record end
        if record.name then byName[record.name:lower()] = record end
    end

    for recipeID, seen in pairs(SeenTable(false) or {}) do
        if type(seen) == "table" then
            local target = merged[recipeID]
                or (seen.outputItemID and byOutput[seen.outputItemID])
                or (not seen.outputItemID and seen.name and byName[seen.name:lower()])

            if target and target.recipeID ~= recipeID then
                -- The same Classic recipe under the game's own ID: kept under
                -- the game's, which is what characters' recipes use.
                merged[target.recipeID] = nil
                aliases[target.recipeID] = recipeID
                target.recipeID = recipeID
                merged[recipeID] = target
            end

            local record = target or { recipeID = recipeID }
            merged[recipeID] = record

            record.name = seen.name or record.name
            record.outputItemID = seen.outputItemID or record.outputItemID
            record.quantityMin = seen.quantityMin or record.quantityMin or 1
            record.quantityMax = seen.quantityMax or record.quantityMax or record.quantityMin
            record.skillLineID = seen.skillLineID or record.skillLineID
            record.profession = record.profession or seen.profession
                or self:ProfessionName(seen.skillLineID)
            if type(seen.reagents) == "table" and #seen.reagents > 0 then
                record.reagents = seen.reagents
            end
            record.seenInGame = true
        end
    end

    self.merged, self.aliases = merged, aliases
    return merged, aliases
end

function RecipeBook:Invalidate()
    self.merged = nil
    self.known = nil
end

--- One recipe by ID, or nil.
function RecipeBook:Get(recipeID)
    local merged, aliases = self:GetAll()
    return merged[recipeID] or merged[aliases[recipeID] or false]
end

--- Every profession the book has recipes for, sorted.
function RecipeBook:GetProfessions()
    local seen, names = {}, {}
    for _, record in pairs((self:GetAll())) do
        local name = record.profession
        if name and not seen[name] then
            seen[name] = true
            names[#names + 1] = name
        end
    end
    table.sort(names)
    return names
end

--------------------------------------------------------------------------------
-- Recipe items
--------------------------------------------------------------------------------

local function ItemInfo(itemID)
    if not (C_Item and type(C_Item.GetItemInfo) == "function") then return nil end
    local ok, name, classID = pcall(function()
        local n, _, _, _, _, _, _, _, _, _, _, c = C_Item.GetItemInfo(itemID)
        if type(n) == "string" then n = n .. "" else n = nil end
        if type(c) == "number" then c = c + 0 else c = nil end
        return n, c
    end)
    if not ok then return nil end
    return name, classID
end

--- The recipe a recipe item teaches.
--
-- By the shipped table first. A recipe item it does not list (one Forever
-- added) is matched by name: "Pattern: Fine Leather Boots" teaches the recipe
-- called Fine Leather Boots, among those a profession window has shown.
--
-- @return recipe record or nil
function RecipeBook:ForItem(itemID)
    if type(itemID) ~= "number" then return nil end

    local row = Book().ITEMS[itemID]
    if row then return self:Get(row[1]) end

    local name, classID = ItemInfo(itemID)
    if not name or classID ~= CLASS_RECIPE then return nil end

    local taught = name:match("^[^:]+:%s*(.+)$")
    if not taught then return nil end
    taught = taught:lower()

    for _, record in pairs((self:GetAll())) do
        if record.name and record.name:lower() == taught then return record end
    end

    return nil
end

--- The recipe items that teach a recipe: the shipped ones, and the item a
--- tooltip was showing when it is one the table does not list.
function RecipeBook:RecipeItemsFor(record, extraItemID)
    local items = {}
    for _, itemID in ipairs(record and record.recipeItems or {}) do items[#items + 1] = itemID end
    if extraItemID then
        local listed = false
        for _, itemID in ipairs(items) do if itemID == extraItemID then listed = true end end
        if not listed then items[#items + 1] = extraItemID end
    end
    return items
end

--------------------------------------------------------------------------------
-- Who knows it
--------------------------------------------------------------------------------

--- { byRecipe = { [recipeID] = keys }, byOutput = { [itemID] = keys } },
--- read from every character's recipes and reused for a few seconds.
local function KnownIndex()
    local self = RecipeBook
    local known = self.known
    if known and Now() - known.at < KNOWN_TTL then return known end

    known = { at = Now(), byRecipe = {}, byOutput = {} }

    if ns.Recipes and ns.Recipes.GetAccountWide then
        for recipeID, recipe in pairs(ns.Recipes:GetAccountWide(true)) do
            known.byRecipe[recipeID] = recipe.knownBy
            if recipe.outputItemID then known.byOutput[recipe.outputItemID] = recipe.knownBy end
        end
    end

    self.known = known
    return known
end

--- The characters on the account who know a recipe; an empty list for none.
function RecipeBook:WhoKnows(record)
    if not record then return {} end
    local known = KnownIndex()
    return known.byRecipe[record.recipeID]
        or (record.outputItemID and known.byOutput[record.outputItemID])
        or {}
end

--- Does the character playing know it?
function RecipeBook:KnowsIt(record, knownBy)
    local me = ns.Config and ns.Config:GetCharacterKey()
    for _, key in ipairs(knownBy or self:WhoKnows(record)) do
        if key == me then return true end
    end
    return false
end

--- "you", "Ana", "Ana, Bob" or "you and Ana"; nil when nobody does.
function RecipeBook:KnownByText(record)
    local knownBy = self:WhoKnows(record)
    if #knownBy == 0 then return nil end

    local me = ns.Config and ns.Config:GetCharacterKey()
    local mine, others = false, {}
    for _, key in ipairs(knownBy) do
        if key == me then
            mine = true
        else
            others[#others + 1] = ns.Recipes:GetShortCharacterName(key)
        end
    end
    table.sort(others)

    if mine and #others == 0 then return "you" end
    if mine then return "you and " .. table.concat(others, ", ") end
    return table.concat(others, ", ")
end

--------------------------------------------------------------------------------
-- Where it is learned
--------------------------------------------------------------------------------

local function PlayerFaction()
    local faction = PlainString(UnitFactionGroup, "player")
    if faction == "Alliance" then return "A" end
    if faction == "Horde" then return "H" end
    return nil
end

--- Vendors of a recipe item on the player's side: { { name, zone }, ... }.
local function VendorsOf(itemID)
    local row = Book().ITEMS[itemID]
    local list = row and row.v
    if not list then return {} end

    local side = PlayerFaction()
    local vendors = {}
    for i = 1, #list - 2, 3 do
        local fac = list[i + 2] or ""
        if not side or fac == "" or fac:find(side, 1, true) then
            vendors[#vendors + 1] = { name = list[i], zone = list[i + 1] }
        end
    end
    return vendors
end

--- How a recipe is learned.
--
-- @return short, lines  short is one word for a list cell ("Trainer",
--   "Vendor", "Drop", "Quest or other", "Starter" or "Unknown"); lines are
--   the whole story for a tooltip or the detail pane, most useful first.
function RecipeBook:LearnFrom(record)
    local short, lines = nil, {}
    if not record then return "Unknown", lines end

    if record.starter then
        short = "Starter"
        lines[#lines + 1] = "Comes with the profession"
    end

    if record.trainerCost then
        short = short or "Trainer"
        lines[#lines + 1] = record.trainerCost > 0
            and ("Trainer, " .. Util.FormatMoney(record.trainerCost, { noColor = true }))
            or "Trainer"
    end

    local drops, named, otherItem = 0, nil, false
    for _, itemID in ipairs(record.recipeItems or {}) do
        local row = Book().ITEMS[itemID]
        local vendors = VendorsOf(itemID)
        for _, vendor in ipairs(vendors) do
            short = short or "Vendor"
            lines[#lines + 1] = vendor.zone ~= "" and ("Vendor: %s, %s"):format(vendor.name, vendor.zone)
                or ("Vendor: " .. vendor.name)
        end
        if row and (row.d or 0) > drops then drops, named = row.d, row.n end
        if #vendors == 0 and not (row and row.d) then otherItem = true end
    end

    if drops > 0 then
        short = short or "Drop"
        if named then
            lines[#lines + 1] = "Drops from " .. table.concat(named, ", ")
        else
            lines[#lines + 1] = ("World drop (%d kinds of creature)"):format(drops)
        end
    end

    if otherItem then
        short = short or "Quest or other"
        lines[#lines + 1] = "Recipe item from a quest, reputation or the other faction"
    end

    if not short and record.seenInGame and not record.recipeItems then
        lines[#lines + 1] = "Seen in a profession window; where it is learned is not known yet"
    end

    return short or "Unknown", lines
end

--------------------------------------------------------------------------------
-- What it is worth
--------------------------------------------------------------------------------

--- The cheapest way to get a recipe: a trainer, a vendor or the auction
--- house. Prices for recipe items come from scans and vendors seen in game,
--- then the shipped vendor price.
--
-- @return price, how ("trainer", "vendor" or "auction"), itemID
function RecipeBook:GetRecipePrice(record, extraItemID)
    local best, how, which

    local function Offer(price, way, itemID)
        if price and price > 0 and (not best or price < best) then
            best, how, which = price, way, itemID
        end
    end

    if record and record.trainerCost and record.trainerCost > 0 then
        Offer(record.trainerCost, "trainer")
    end

    for _, itemID in ipairs(self:RecipeItemsFor(record, extraItemID)) do
        local row = Book().ITEMS[itemID]
        local seenAtVendor = ns.Vendor and ns.Vendor.GetTable and ns.Vendor:GetTable()[itemID]
        if seenAtVendor then
            Offer(ns.Vendor:GetUnitPrice(itemID), "vendor", itemID)
        elseif row and row.v and #VendorsOf(itemID) > 0 then
            Offer(row[2], "vendor", itemID)
        end
        Offer(ns.Prices and ns.Prices:GetValue(itemID, "lowest"), "auction", itemID)
    end

    return best, how, which
end

--- Everything a recipe is worth, for one craft.
--
-- @return {
--   cost        materials for one craft, or nil when one has no price
--   costDetail  Cost:GetCraftCost's breakdown
--   returns     LevelUp:GetReturns: vendor, auction, disenchant, best, bestWay
--   back, backWay  the most one craft gets back, and how
--   profit      back less cost, nil when either is unknown
--   price, priceHow  the cheapest way to get the recipe
--   payback     crafts until the profit has paid for the recipe
-- }
function RecipeBook:Value(record, extraItemID)
    if not record then return nil end

    local costDetail = ns.Cost:GetCraftCost(record.recipeID, nil, nil,
        { valueOwned = true, recipe = record })
    local cost = costDetail and costDetail.priceable and costDetail.total or nil

    local returns
    if record.outputItemID and ns.LevelUp and ns.LevelUp.GetReturns then
        local ok, result = pcall(ns.LevelUp.GetReturns, ns.LevelUp, record, costDetail)
        if ok then returns = result end
    end

    local back = returns and returns.best or nil
    local profit = (cost and back) and (back - cost) or nil

    local price, priceHow = self:GetRecipePrice(record, extraItemID)
    local payback
    if price and profit and profit > 0 then
        payback = math.max(1, math.ceil(price / profit))
    end

    return {
        cost = cost,
        costDetail = costDetail,
        returns = returns,
        back = back,
        backWay = returns and returns.bestWay or nil,
        profit = profit,
        price = price,
        priceHow = priceHow,
        payback = payback,
    }
end

--------------------------------------------------------------------------------
-- The list
--------------------------------------------------------------------------------

--- Recipes of one profession (or all), valued, for the Profit tab's
--- Recipes to learn view.
--
-- @param opts.profession  a profession's name, or nil for every one
-- @param opts.includeKnown  keep recipes the character playing knows
-- @param opts.search  part of the recipe's name
-- @return rows { recipeID, record, name, profession, skill, outputItemID,
--   value fields..., learn, known, knownBy }
function RecipeBook:List(opts)
    opts = opts or {}
    local needle = opts.search and opts.search ~= "" and opts.search:lower() or nil

    local rows = {}
    for recipeID, record in pairs((self:GetAll())) do
        if (not opts.profession or record.profession == opts.profession)
            and (not needle or (record.name or ""):lower():find(needle, 1, true)) then
            local knownBy = self:WhoKnows(record)
            local known = self:KnowsIt(record, knownBy)

            if opts.includeKnown or not known then
                local value = self:Value(record)
                local learn = self:LearnFrom(record)

                rows[#rows + 1] = {
                    recipeID = recipeID,
                    record = record,
                    name = record.name or ("recipe " .. recipeID),
                    profession = record.profession,
                    skill = record.skill,
                    outputItemID = record.outputItemID,
                    cost = value.cost,
                    back = value.back,
                    backWay = value.backWay,
                    returns = value.returns,
                    auction = value.returns and value.returns.auction or nil,
                    disenchant = value.returns and value.returns.disenchant or nil,
                    profit = value.profit,
                    price = value.price,
                    priceHow = value.priceHow,
                    payback = value.payback,
                    learn = learn,
                    known = known,
                    knownBy = knownBy,
                }
            end
        end
    end

    -- Most profit first; recipes that cannot be valued go last, by skill.
    table.sort(rows, function(a, b)
        if (a.profit ~= nil) ~= (b.profit ~= nil) then return a.profit ~= nil end
        if a.profit and b.profit and a.profit ~= b.profit then return a.profit > b.profit end
        if (a.skill or 0) ~= (b.skill or 0) then return (a.skill or 0) < (b.skill or 0) end
        return a.name < b.name
    end)

    return rows
end

--------------------------------------------------------------------------------
-- The tooltip
--------------------------------------------------------------------------------

function RecipeBook:TooltipEnabled()
    if not ns.Config then return true end
    return ns.Config:Get("showRecipeValueOnTooltips") ~= false
end

local function Money(copper)
    return Util.FormatMoney(copper, { short = true })
end

local WAY_NAMES = { vendor = "vendor", auction = "auction", disenchant = "disenchant" }

--- Lines for a recipe item's tooltip, in ItemTooltip's `{ label, value }`
--- shape. Nothing for an item that teaches no recipe the book knows.
function RecipeBook:TooltipLines(itemID)
    local lines = {}
    if not self:TooltipEnabled() then return lines end

    local record = self:ForItem(itemID)
    if not record then return lines end

    -- An unlearned recipe's item has usually never been in the bags, so the
    -- client has not loaded it. Asking now means the next hover can say
    -- what it sells and disenchants for.
    if record.outputItemID and C_Item and type(C_Item.RequestLoadItemDataByID) == "function" then
        if not ItemInfo(record.outputItemID) then
            pcall(C_Item.RequestLoadItemDataByID, record.outputItemID)
        end
    end

    local needs = record.profession and record.skill and record.skill > 0
        and ("%s %d"):format(record.profession, record.skill) or record.profession
    lines[#lines + 1] = { "Teaches", (record.name or "?") .. (needs and ("  (" .. needs .. ")") or "") }

    local knownBy = self:KnownByText(record)
    if knownBy then
        lines[#lines + 1] = { "Known by", knownBy, color = knownBy:find("^you") and "profit" or "text" }
    else
        lines[#lines + 1] = { "Known by", "nobody on this account", color = "warn" }
    end

    local value = self:Value(record, itemID)

    lines[#lines + 1] = { "Cost to make", value.cost and Money(value.cost) or "materials not scanned",
        not value.cost }

    if not record.outputItemID then
        lines[#lines + 1] = { "Makes", "no item to sell", true }
        return lines
    end

    if not ItemInfo(record.outputItemID) then
        lines[#lines + 1] = { "Sells for", "loading, hover again", true }
        return lines
    end

    local returns = value.returns or {}
    lines[#lines + 1] = { "Sells for", returns.auction and (Money(returns.auction) .. " after the cut")
        or "not scanned yet", not returns.auction }
    if returns.disenchant then
        lines[#lines + 1] = { "Disenchants for", Money(returns.disenchant) }
    end
    if returns.vendor and value.backWay == "vendor" then
        lines[#lines + 1] = { "Vendors for", Money(returns.vendor) }
    end

    if value.profit then
        local text = Money(value.profit)
        if value.backWay and value.backWay ~= "auction" then
            text = ("%s  (by %s)"):format(text, WAY_NAMES[value.backWay] or value.backWay)
        end
        lines[#lines + 1] = { "Profit per craft", text, color = value.profit >= 0 and "profit" or "loss" }

        if value.payback then
            lines[#lines + 1] = { "Pays for itself", value.payback == 1 and "after 1 craft"
                or ("after %d crafts"):format(value.payback), color = "profit" }
        elseif value.profit <= 0 then
            lines[#lines + 1] = { "Pays for itself", "not at today's prices", color = "warn" }
        end
    end

    return lines
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

function RecipeBook:OnEnable()
    ns.RegisterCommand("recipes", "list recipes you have not learned, with what each is worth",
        function(input)
            input = (input or ""):gsub("^%s+", ""):gsub("%s+$", "")
            if ns.ProfitTab and ns.ProfitTab.ShowRecipesToLearn then
                ns.ProfitTab.ShowRecipesToLearn(input ~= "" and input or nil)
            end
        end)
end
