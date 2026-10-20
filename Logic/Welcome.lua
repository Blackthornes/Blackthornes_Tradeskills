-- Blackthornes Tradeskills -- Logic/Welcome.lua
-- The Welcome card (the owner said build it, 2026-10-20, from a mockup):
-- the first time a character opens the window, a card asks which of its
-- professions to level, and Show My Road opens the Level Up tab's Road to
-- 300 (Logic/RoadPlan.lua) on the first one picked. Once per character,
-- existing players too. It changes no setting: the picks only decide which
-- roads come first.
--
-- Saved per character in BlackthornesTSCharDB, never renamed:
--   welcomeSeen  true once the card was shown and closed either way
--   roadPicks    { Classic skill line, ... } in the order picked

local _, ns = ...

local Welcome = ns.NewModule("Welcome")

local function CharDb()
    local db = ns.charDb
    if type(db) == "table" then return db end
    db = rawget(_G, "BlackthornesTSCharDB")
    return type(db) == "table" and db or nil
end

--- The professions picked, as Classic skill lines in order; empty when none.
function Welcome:Picks()
    local db = CharDb()
    local picks = db and db.roadPicks
    local list = {}
    if type(picks) ~= "table" then return list end
    for _, line in ipairs(picks) do
        if type(line) == "number" then list[#list + 1] = line end
    end
    return list
end

--- Keep the picks, in order.
function Welcome:SetPicks(lines)
    local db = CharDb()
    if not db then return false end
    local list, seen = {}, {}
    for _, line in ipairs(lines or {}) do
        if type(line) == "number" and not seen[line] then
            seen[line] = true
            list[#list + 1] = line
        end
    end
    db.roadPicks = list
    return true
end

--- Is the card still to show for this character? Only once a profession
--- it can lay a road for is known, so a character with none sees it later.
function Welcome:Due()
    local db = CharDb()
    if not db or db.welcomeSeen then return false end
    local ok, list = pcall(function() return ns.RoadPlan and ns.RoadPlan:Professions() end)
    return ok and type(list) == "table" and #list > 0 or false
end

--- The card was shown: it never comes back by itself.
function Welcome:MarkSeen()
    local db = CharDb()
    if db then db.welcomeSeen = true end
end
