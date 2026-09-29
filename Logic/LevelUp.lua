-- Blackthornes Tradeskills -- Logic/LevelUp.lua
-- The cheapest way up a profession.
--
-- The Profit tab asks what is worth making for gold. This asks a different
-- question: which of the crafts you know will raise your skill, and which of
-- those costs least to make. So the order is the skill-up colour first
-- (orange, then yellow, then green, grey last) and material cost second,
-- cheapest first.
--
-- Nothing here prices anything on its own. The difficulty is what
-- Logic/SkillUp.lua stored when the profession window was last open, and the
-- cost is Logic/Cost.lua's, the very number the Profit tab shows, so the two
-- tabs can never disagree about what a craft costs. That includes the rule
-- that an in-between material counts at whichever is cheaper, buying it or
-- making it.
--
-- Soulbound crafts are kept. They cannot be sold, which is why the Profit
-- list drops them, but they level a profession as well as anything.

local _, ns = ...

local LevelUp = ns.NewModule("LevelUp")

-- Best chance of a point first. A recipe whose colour has never been read sits
-- after green and before grey: it may well be orange, and hiding it on a guess
-- would be worse than showing it lower down.
local BAND = { optimal = 1, medium = 2, easy = 3, unknown = 4, trivial = 5 }

LevelUp.BAND = BAND

-- Short words for the CHANCE column. SkillUp's own labels are sentences,
-- which is right for a tooltip and too long for a column.
LevelUp.CHANCE_LABEL = {
    optimal = "Guaranteed",
    medium  = "Likely",
    easy    = "Small",
    trivial = "None",
    unknown = "Not read",
}

--- Which band a row falls in.
function LevelUp.BandOf(row)
    return BAND[row and row.tier or "unknown"] or BAND.unknown
end

--- The order of the list: band, then cost, then name.
--
-- A craft whose materials have no price goes after every priced one in its
-- band. Treating a missing price as free would put it on top, and that is
-- exactly the craft you know least about.
--
-- Every tie falls through to the recipe ID. `pairs` hands recipes over in no
-- particular order, and a comparator that can call two rows equal makes the
-- list reshuffle itself on every refresh.
function LevelUp.Compare(a, b)
    local bandA, bandB = LevelUp.BandOf(a), LevelUp.BandOf(b)
    if bandA ~= bandB then return bandA < bandB end

    local costA, costB = a.cost, b.cost
    if costA and not costB then return true end
    if costB and not costA then return false end
    if costA and costB and costA ~= costB then return costA < costB end

    local nameA, nameB = a.name or "", b.name or ""
    if nameA ~= nameB then return nameA < nameB end

    return (a.recipeID or 0) < (b.recipeID or 0)
end

--- One row of the list.
--
-- @return { recipeID, name, outputItemID, skillLineID, tier, skillUp,
--           cost, costDetail, craftableNow, missing }
--   cost is the material cost of one craft in copper, or nil when a
--   material has no price. missing is how many materials are short for one
--   craft, counting the bank, the same way the Profit tab's breakdown does.
function LevelUp:BuildRow(recipeID, recipe)
    recipe = recipe or ns.Recipes:GetAny(recipeID)
    if not recipe then return nil end

    local skillUp = ns.SkillUp and ns.SkillUp:GetForRecipe(recipeID, recipe) or nil
    local costDetail = ns.Cost:GetCraftCost(recipeID)

    local missing = 0
    for _, reagent in ipairs((costDetail and costDetail.reagents) or {}) do
        if (reagent.shortfall or 0) > 0 then missing = missing + 1 end
    end

    return {
        recipeID = recipeID,
        name = recipe.name,
        outputItemID = recipe.outputItemID,
        skillLineID = recipe.skillLineID,
        tier = skillUp and skillUp.tier or "unknown",
        skillUp = skillUp,
        cost = costDetail and costDetail.priceable and costDetail.total or nil,
        costDetail = costDetail,
        craftableNow = ns.Profit:GetCraftableCount(recipeID),
        missing = missing,
    }
end

--- Every recipe this character knows, in levelling order.
--
-- @param opts.skillLines  a set { [skillLineID] = true } to keep, or nil for
--   every profession. A set rather than one ID because Forever lists each
--   profession under two skill-line IDs and a recipe may carry either.
-- @param opts.includeTrivial  keep grey recipes (always last)
-- @param opts.craftableOnly   keep only what the bags cover right now
-- @param opts.search          part of a name, any case
function LevelUp:GetRanked(opts)
    opts = opts or {}

    local needle = opts.search and opts.search ~= "" and opts.search:lower() or nil
    local rows = {}

    for recipeID, recipe in pairs(ns.Recipes:GetAll()) do
        local keep = not opts.skillLines or opts.skillLines[recipe.skillLineID]

        -- Not a profession this character has dropped.
        if keep and ns.Recipes.IsDropped and ns.Recipes:IsDropped(recipe) then keep = false end

        if keep and needle then
            keep = (recipe.name or ""):lower():find(needle, 1, true) ~= nil
        end

        if keep then
            local row = self:BuildRow(recipeID, recipe)

            if row then
                if row.tier == "trivial" and not opts.includeTrivial then row = nil end
                if row and opts.craftableOnly and row.craftableNow < 1 then row = nil end
            end

            if row then rows[#rows + 1] = row end
        end
    end

    table.sort(rows, LevelUp.Compare)

    return rows
end

--------------------------------------------------------------------------------
-- The Craft button
--------------------------------------------------------------------------------

--- What the Craft button should do for this recipe right now.
--
-- The same rules the Queue tab's Craft button follows, so the two never
-- disagree: a craft only starts from its own profession window, so when that
-- window is not the one open the click opens it instead (through
-- ProfessionOpener's secure button, since addon code may not cast); a craft
-- never asks for more than the bags make, or the game stops partway.
--
-- @param wanted  how many the player typed
-- @return { kind = "stop"|"open"|"craft"|"none", text, status, count, profession }
function LevelUp:CraftAction(recipeID, wanted)
    local Crafting = ns.Crafting

    if Crafting:IsBusy() then
        return { kind = "stop", text = "Stop", status = "Crafting. Click Stop to end after this one." }
    end

    local ready, reason = Crafting:GetReadiness(recipeID)

    if not ready then
        local status = reason == "need materials"
            and "You are short of materials for this one."
            or ("Cannot craft: %s."):format(reason or "unknown reason")
        return { kind = "none", text = "Craft", status = status }
    end

    local craftable = ns.Profit:GetCraftableCount(recipeID)
    local count = math.max(1, math.min(tonumber(wanted) or 1, craftable))

    local opener = ns.ProfessionOpener
    if opener and not opener:WindowShowsRecipe(recipeID) then
        local profession = opener:ProfessionFor(recipeID)

        if profession then
            return {
                kind = "open",
                text = ("Open %s"):format(profession.name),
                status = ("Opens your %s window. Click again to craft."):format(profession.name),
                count = count,
                profession = profession,
            }
        end
    end

    local status = ("Makes %d now."):format(count)
    if (tonumber(wanted) or 1) > craftable then
        status = ("Your bags only have materials for %d."):format(craftable)
    end

    return { kind = "craft", text = ("Craft %d"):format(count), status = status, count = count }
end

--------------------------------------------------------------------------------
-- The profession last open
--------------------------------------------------------------------------------

--- Which skill line the open profession window is showing.
--
-- Worked out from the recipes it lists rather than from a profession API, so
-- the answer is always an ID that the cached recipes actually carry. The
-- window can show a few recipes from elsewhere, so the most common skill line
-- wins.
function LevelUp:ReadOpenSkillLine()
    if not ns.Util.HasFunction("C_TradeSkillUI.GetAllRecipeIDs") then return nil end

    local ok, recipeIDs = pcall(C_TradeSkillUI.GetAllRecipeIDs)
    if not ok or type(recipeIDs) ~= "table" then return nil end

    local counts, best, bestCount = {}, nil, 0

    for _, recipeID in ipairs(recipeIDs) do
        local recipe = ns.Recipes:Get(recipeID)
        local skillLineID = recipe and recipe.skillLineID

        if skillLineID then
            counts[skillLineID] = (counts[skillLineID] or 0) + 1

            if counts[skillLineID] > bestCount then
                best, bestCount = skillLineID, counts[skillLineID]
            end
        end
    end

    return best
end

--- Remember the profession that was open, per character, so the tab opens on
--- it even at the auction house with no profession window up.
function LevelUp:NoteOpenProfession()
    local skillLineID = self:ReadOpenSkillLine()
    if not skillLineID then return end

    local record = ns.Recipes:GetCharacterRecord(true)
    if record then record.lastSkillLine = skillLineID end
end

function LevelUp:GetLastSkillLine()
    local record = ns.Recipes:GetCharacterRecord(false)
    return record and record.lastSkillLine or nil
end

function LevelUp:OnEnable()
    -- After Recipes has had a chance to harvest, so a first visit to a
    -- profession still finds its recipes in the cache. The list event fires
    -- in bursts while the window settles, so the reads are coalesced.
    local function Later()
        if LevelUp.noteTimer then LevelUp.noteTimer:Cancel() end
        LevelUp.noteTimer = C_Timer.NewTimer(1.5, function()
            LevelUp.noteTimer = nil
            LevelUp:NoteOpenProfession()
        end)
    end

    ns.RegisterEvent(self, "TRADE_SKILL_SHOW", Later)
    ns.RegisterEvent(self, "TRADE_SKILL_LIST_UPDATE", Later)
end
