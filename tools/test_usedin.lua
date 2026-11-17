-- The "Used in" tooltip line (Logic/UsedIn.lua, UI/ItemTooltip.lua).
--
-- Walks what a player sees: hover a material your characters use, hold
-- Shift, hover one none of them use, hover one no recipe uses, drop a
-- profession, learn a recipe. And that a tooltip never builds a lookup:
-- the work runs in the worker, between tooltips.

local ns = {}
ns.NewModule = function(name) local m = { moduleName = name }; ns[name] = m; return m end
ns.COLORS = { accent = "ffc8a44d", muted = "ff7a8089", text = "ffe6e8ec" }
ns.Print = function() end

-- A worker that holds its items until the test steps it, as the game's
-- frames would.
local workers = {}
local function Pump()
    while #workers > 0 do
        local worker = table.remove(workers, 1)
        if not worker.cancelled then
            for i, item in ipairs(worker.items) do worker.onItem(item, i, worker) end
            if not worker.cancelled and worker.onDone then worker.onDone(worker) end
        end
    end
end
ns.Util = {
    FormatMoney = function(copper) return ("<%d>"):format(copper) end,
    FormatAgeAgo = function(seconds) return ("%dh ago"):format(seconds / 3600) end,
    HasFunction = function() return false end,
    NewWorker = function(opts)
        local worker = { onItem = opts.onItem, onDone = opts.onDone, onCancel = opts.onCancel }
        function worker:Start(items) self.items = items; workers[#workers + 1] = self end
        function worker:Cancel() self.cancelled = true; if self.onCancel then self.onCancel(self) end end
        return worker
    end,
}

local check_count = 0
local function check(label, got, want)
    check_count = check_count + 1
    if got ~= want then
        error(("%s: expected %s, got %s"):format(label, tostring(want), tostring(got)), 2)
    end
end

--------------------------------------------------------------------------------
-- The world
--------------------------------------------------------------------------------

local SILK, IRON_BAR, LINEN, BOLT_SILK, OBSIDIAN = 4306, 3575, 2589, 4305, 99999

ns.settings = {}
ns.Config = {
    Get = function(_, key) return ns.settings[key] end,
    GetCharacterKey = function() return "Player-1" end,
}

ns.Recipes = {
    SKILL_LINE_PROFESSIONS = { [129] = "First Aid", [197] = "Tailoring", [164] = "Blacksmithing",
        [202] = "Engineering", [171] = "Alchemy", [186] = "Mining" },
    IsDropped = function(_, recipe, key)
        local record = ns.db.characters[key]
        local lines = record and record.professionLines
        return lines ~= nil and lines[recipe.skillLineID] == false
    end,
}

local function R(id, line, name, made, mats)
    local reagents = {}
    for i = 1, #mats, 2 do reagents[#reagents + 1] = { itemID = mats[i], quantity = mats[i + 1] } end
    return { recipeID = id, skillLineID = line, name = name, outputItemID = made, reagents = reagents }
end

ns.db = { characters = {
    ["Player-1"] = { recipes = {
        [7928] = R(7928, 129, "Silk Bandage", 6450, { SILK, 1 }),
        [7929] = R(7929, 129, "Heavy Silk Bandage", 6451, { SILK, 2 }),
    } },
    ["Player-2"] = { recipes = {
        [3865] = R(3865, 197, "Bolt of Silk Cloth", BOLT_SILK, { SILK, 4 }),
        -- The same recipe on two characters counts once.
        [7928] = R(7928, 129, "Silk Bandage", 6450, { SILK, 1 }),
        -- A recipe that makes what it uses never says it uses it.
        [9999] = R(9999, 197, "Silk Again", SILK, { SILK, 1 }),
    } },
} }

-- The book: Iron Bar is used by four professions, none of them known.
local SKILLS = { [7928] = 115, [7929] = 145, [3865] = 125 }
local merged = {}
local function B(id, profession, name, skill, mats)
    merged[id] = { recipeID = id, profession = profession, name = name, skill = skill,
        reagents = R(id, 0, name, nil, mats).reagents }
end
B(7928, "First Aid", "Silk Bandage", 115, { SILK, 1 })
B(3865, "Tailoring", "Bolt of Silk Cloth", 125, { SILK, 4 })
B(8367, "Blacksmithing", "Iron Fists", 130, { IRON_BAR, 4 })
B(3495, "Blacksmithing", "Iron Buckle", 150, { IRON_BAR, 1 })
B(3501, "Blacksmithing", "Green Iron Bracers", 165, { IRON_BAR, 6 })
B(3958, "Engineering", "Iron Strut", 160, { IRON_BAR, 2 })
B(3961, "Engineering", "Gyrochronatom", 170, { IRON_BAR, 1 })
B(3452, "Alchemy", "Mighty Troll's Blood", 180, { IRON_BAR, 1 })
B(2657, "Mining", "Smelt Iron", 125, { IRON_BAR, 0 })
B(4444, "Mining", "Smelt Steel", 165, { IRON_BAR, 1 })
-- Mining's two would tie Engineering; Engineering sorts first by name.

ns.RecipeBook = {
    GetAll = function() return merged, {} end,
    GetSkill = function(_, id) return SKILLS[id] end,
    Get = function(_, id) return merged[id] end,
}

C_Item = { GetItemInfo = function() return "item", nil, 1 end }

loadfile("Logic/UsedIn.lua")("Blackthornes_TS", ns)
loadfile("UI/ItemTooltip.lua")("Blackthornes_TS", ns)
local UsedIn, ItemTooltip = ns.UsedIn, ns.ItemTooltip
ns.TooltipShift = nil

local shiftDown = false
local shows = {}
ns.TooltipShift = {
    Shows = function(_, key) return shows[key] ~= false end,
    ShiftDown = function() return shiftDown end,
}

local function Lines(itemID)
    local lines = {}
    ItemTooltip:AddUsedInLines(lines, itemID)
    return lines
end
local function Find(lines, label)
    for i, line in ipairs(lines) do if line[1] == label then return line, i end end
end

--------------------------------------------------------------------------------
-- Before the lookups are built, nothing; the tooltip only starts them.
--------------------------------------------------------------------------------

local lines = Lines(SILK)
check("left out until ready", #lines, 0)
check("the tooltip started the work", #workers, 2)
check("but did none of it", UsedIn:IsReady(), false)
Pump()
check("ready once the worker ran", UsedIn:IsReady(), true)

--------------------------------------------------------------------------------
-- Your characters use it
--------------------------------------------------------------------------------

lines = Lines(SILK)
check("used in, most recipes first", Find(lines, "Used in")[2], "First Aid (2), Tailoring (1)")
check("in white", Find(lines, "Used in")[3], nil)
check("names wait for Shift", #lines, 1)
check("says to hold Shift", lines.held, true)
check("so Shift redraws it", ItemTooltip.usedInHeld, true)

shiftDown = true
lines = Lines(SILK)
check("Shift: a line per profession", #lines, 3)
check("first aid names, easiest first", Find(lines, "   First Aid")[2], "Silk Bandage, Heavy Silk Bandage")
check("tailoring names", Find(lines, "   Tailoring")[2], "Bolt of Silk Cloth")
check("Shift held needs no hint", lines.held, nil)
shiftDown = false

-- No rebuild on hover: the answer is kept.
local builds = UsedIn.builds
for _ = 1, 20 do Lines(SILK) end
check("hovering builds nothing", UsedIn.builds, builds)
check("and starts no worker", #workers, 0)

--------------------------------------------------------------------------------
-- None of your characters use it
--------------------------------------------------------------------------------

lines = Lines(IRON_BAR)
check("the professions that could, most first",
    Find(lines, "Used in")[2], "Blacksmithing, Engineering, Mining, Alchemy")
check("in grey", Find(lines, "Used in")[3], true)
check("then says yours don't", lines[2][2], "Your characters don't use it yet.")
check("in grey too", lines[2][3], true)
check("no example without Shift", Find(lines, "For example"), nil)
shiftDown = true
lines = Lines(IRON_BAR)
check("Shift: the easiest from the busiest", Find(lines, "For example")[2], "Iron Fists (Blacksmithing 130)")
shiftDown = false

check("nothing for an item no recipe uses", #Lines(OBSIDIAN), 0)
check("nor a lone made item", #Lines(BOLT_SILK), 0)

--------------------------------------------------------------------------------
-- Off and Shift
--------------------------------------------------------------------------------

ns.settings.tooltipUsedIn = false
check("turned off, nothing", #Lines(SILK), 0)
ns.settings.tooltipUsedIn = nil
shows.usedin = false
lines = Lines(SILK)
check("on Shift, waits", #lines, 0)
check("and is held", lines.held, true)
shows.usedin = nil

--------------------------------------------------------------------------------
-- A dropped profession leaves; a new recipe joins. Only after a rebuild.
--------------------------------------------------------------------------------

ns.db.characters["Player-2"].professionLines = { [197] = false }
UsedIn:Stale()
check("a rebuild is a worker", #workers, 1)
check("the old answer stands meanwhile", Find(Lines(SILK), "Used in")[2], "First Aid (2), Tailoring (1)")
Pump()
check("dropped tailoring is left out", Find(Lines(SILK), "Used in")[2], "First Aid (2)")
ns.db.characters["Player-2"].professionLines = nil

ns.db.characters["Player-1"].recipes[3866] = R(3866, 197, "Silk Headband", 4307, { SILK, 3 })
UsedIn:Stale(true)
Pump()
check("a new recipe counts", Find(Lines(SILK), "Used in")[2], "First Aid (2), Tailoring (2)")

--------------------------------------------------------------------------------
-- Wrapping
--------------------------------------------------------------------------------

local parts = UsedIn.Wrap("Embossed Leather Gloves, Fine Leather Belt, Dark Leather Boots and 4 more")
check("a long list wraps", #parts, 2)
check("at a space", parts[1], "Embossed Leather Gloves, Fine Leather Belt,")
check("a word longer than a line stays whole", UsedIn.Wrap(("x"):rep(60))[1], ("x"):rep(60))
check("letters, not bytes", #UsedIn.Wrap("Кожевничество (2), Портняжное дело (1), Кулинария (3)"), 2)

print(("test_usedin: ok (%d checks)"):format(check_count))
