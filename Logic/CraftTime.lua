-- Blackthornes Tradeskills -- Logic/CraftTime.lua
-- How long a craft takes, and what it makes an hour.
--
-- Asked by two players on 2026-10-09: the time to make one of an item,
-- counting the sub-crafts the addon would make for it, and gold per hour
-- for crafts and for disenchanting.
--
-- A cast's length comes, best first, from:
--
--   "seen"  the player casting it: every craft or disenchant cast keeps its
--           length, account wide in `castTimes[spellID]` = seconds. What the
--           Forever client really does beats anything else.
--   "game"  the client's own spell data (C_Spell.GetSpellInfo's castTime,
--           or GetSpellInfo's fourth return, in milliseconds).
--   nil     neither: the time is unknown, and nothing is guessed.
--
-- Only casting is counted: the moment between one craft and the next, and
-- buying or looting, are not. Recipe IDs are spell IDs.

local _, ns = ...

local CraftTime = ns.NewModule("CraftTime")

CraftTime.DISENCHANT_SPELL = 13262

--------------------------------------------------------------------------------
-- One cast
--------------------------------------------------------------------------------

--- What the client's spell data says a cast takes, in seconds, or nil.
local function FromGame(spellID)
    local api = _G.C_Spell
    if api and type(api.GetSpellInfo) == "function" then
        local ok, info = pcall(api.GetSpellInfo, spellID)
        if ok and type(info) == "table" then
            local okTime, seconds = pcall(function() return info.castTime / 1000 end)
            if okTime and type(seconds) == "number" and seconds > 0 then return seconds end
        end
    end

    if type(_G.GetSpellInfo) == "function" then
        local ok, seconds = pcall(function()
            local _, _, _, castTime = _G.GetSpellInfo(spellID)
            return castTime / 1000
        end)
        if ok and type(seconds) == "number" and seconds > 0 then return seconds end
    end

    return nil
end

--- How long one cast of a spell takes.
-- @return seconds, source ("seen" or "game"), or nil when unknown
function CraftTime:GetCast(spellID)
    if not spellID then return nil end

    local seen = ns.db and ns.db.castTimes and ns.db.castTimes[spellID]
    if type(seen) == "number" and seen > 0 then return seen, "seen" end

    local game = FromGame(spellID)
    if game then return game, "game" end
    return nil
end

--- Keep a cast's length. Rounded to a tenth of a second.
function CraftTime:NoteCast(spellID, seconds)
    if not ns.db or not spellID or type(seconds) ~= "number" then return end
    if seconds <= 0 or seconds > 600 then return end

    ns.db.castTimes = ns.db.castTimes or {}
    ns.db.castTimes[spellID] = math.floor(seconds * 10 + 0.5) / 10
end

--------------------------------------------------------------------------------
-- A whole craft
--------------------------------------------------------------------------------

--- The time to make one craft from its costing (ns.Cost:GetCraftCost): its
--- own cast, plus every sub-craft that costing makes, as many times as the
--- materials need (a sub-craft making two at a time is cast half as often).
-- @return { seconds, casts, known, source } -- seconds is nil when any cast
--   in the tree is unknown; casts counts them all; source is "seen" only
--   when every cast in it was.
function CraftTime:ForCost(recipeID, cost)
    local result = { seconds = 0, casts = 0, known = true, source = "seen" }

    local function Walk(id, costing, times)
        local cast, source = self:GetCast(id)
        result.casts = result.casts + times
        if cast then
            result.seconds = result.seconds + cast * times
            if source ~= "seen" then result.source = "game" end
        else
            result.known = false
        end

        for _, reagent in ipairs((costing and costing.reagents) or {}) do
            local sub = reagent.subCost
            if sub and (reagent.toMake or 0) > 0 and sub.recipeID then
                local yield = (sub.yield and sub.yield > 0) and sub.yield or 1
                Walk(sub.recipeID, sub, times * reagent.toMake / yield)
            end
        end
    end

    Walk(recipeID, cost, 1)

    if not result.known then
        result.seconds, result.source = nil, nil
    end
    return result
end

--- Gold an hour, in copper, for `profit` made in `seconds`; nil when the
--- time is unknown.
function CraftTime.PerHour(profit, seconds)
    if type(profit) ~= "number" or type(seconds) ~= "number" or seconds <= 0 then return nil end
    return profit * 3600 / seconds
end

--- A craft's time, short: "3s", "1.5s", "45s", "1m 05s", "1h 05m".
function CraftTime.Format(seconds)
    if type(seconds) ~= "number" then return "?" end
    if seconds < 10 then
        local tenths = math.floor(seconds * 10 + 0.5) / 10
        if tenths == math.floor(tenths) then return ("%ds"):format(tenths) end
        return ("%.1fs"):format(tenths)
    end
    seconds = math.floor(seconds + 0.5)
    if seconds < 60 then return ("%ds"):format(seconds) end
    if seconds < 3600 then
        return ("%dm %02ds"):format(math.floor(seconds / 60), seconds % 60)
    end
    return ("%dh %02dm"):format(math.floor(seconds / 3600), math.floor(seconds % 3600 / 60))
end

--------------------------------------------------------------------------------
-- Watching casts
--------------------------------------------------------------------------------

--- Whether a spell is a recipe some character knows, or Disenchant.
local function Worth(spellID)
    if spellID == CraftTime.DISENCHANT_SPELL then return true end
    return ns.Recipes ~= nil and ns.Recipes.GetAny ~= nil and ns.Recipes:GetAny(spellID) ~= nil
end

--- A cast started: if it is a craft or a disenchant, keep its length. All of
--- it inside a pcall: in an instance the game hands out values that raise
--- when touched, and then nothing is kept.
function CraftTime:OnCastStart(_, unit, _, spellID)
    pcall(function()
        if unit ~= "player" then return end
        local id = spellID + 0
        if not Worth(id) then return end

        local _, _, _, startMS, endMS = UnitCastingInfo("player")
        local seconds = (endMS - startMS) / 1000
        self:NoteCast(id, seconds)
    end)
end

function CraftTime:OnEnable()
    ns.RegisterEvent(self, "UNIT_SPELLCAST_START", self.OnCastStart)
end
