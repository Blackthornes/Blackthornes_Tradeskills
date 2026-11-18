-- Blackthornes Tradeskills -- Logic/LearnNext.lua
-- Learn next (the owner said build it, 2026-10-12): the recipes the
-- character playing has not learned that would raise their skill now, with
-- where to learn each, so the Level Up tab keeps going past what they know.
--
-- Only recipes a trainer or a vendor teaches by default: a drop or a quest
-- cannot be shown the way to. "Learn From:" on the LEARN NEXT line
-- (2026-11-17) can list those too, with no Show the Way. The skill each needs and when it turns yellow and grey
-- are Forever's (Data/LearnSpots.lua, laid over the book in
-- Logic/RecipeBook.lua); a recipe still a few points out of reach is listed
-- after the rest, "At 120". The trainer or vendor picked is on the player's
-- side, in the zone they are in when one is, else in a city of theirs.
-- A trainer or vendor stands where the game saw it, when its window has
-- been opened or the shipped Forever spots have it (VendorPins:SeenAt),
-- else at Classic's spot.
-- Show the way aims the arrow at them (Logic/WayArrow.lua), or, where the
-- arrow can't find the map, puts the game's own map pin on them, or
-- TomTom's arrow when TomTom is installed (Logic/Waypoints.lua).

local _, ns = ...
local L = ns.L or setmetatable({ Format = string.format }, { __index = function(_, key) return key end })

local LearnNext = ns.NewModule("LearnNext")

-- How many points out of reach a recipe is still listed, greyed.
LearnNext.REACH = 15

-- How far past a recipe's skill one with no yellow and grey known stops
-- being listed.
LearnNext.UNKNOWN_GREY = 75

-- A city of each side, where a trainer is likeliest to be found by a player
-- who is out in a zone that has none.
local CITIES = {
    A = { ["Stormwind City"] = true, ["Ironforge"] = true, ["Darnassus"] = true },
    H = { ["Orgrimmar"] = true, ["Thunder Bluff"] = true, ["Undercity"] = true },
}

-- Thunder Bluff and Darnassus trainers are kept under the zone around them
-- (Mulgore, Teldrassil) with that zone's map spot, so a spot inside the
-- city's box counts as the city when picking one. The zone itself stays as
-- it is, since the map pin reads the spot on that zone's map. Thunder
-- Bluff's box is where the city's own map sits on Forever's Mulgore map
-- (the client's UiMapAssignment table), which reaches further than
-- Classic's (tools/classic_maps.py).
local CITY_BOXES = {
    { zone = "Mulgore", city = "Thunder Bluff", x1 = 31, x2 = 49, y1 = 27, y2 = 45 },
    { zone = "Teldrassil", city = "Darnassus", x1 = 22, x2 = 43, y1 = 38, y2 = 64 },
    -- The Apothecarium's trainers are placed on Silverpine's map.
    { zone = "Silverpine Forest", city = "Undercity", x1 = 70, x2 = 76, y1 = 6, y2 = 12 },
}

local function CityOf(place)
    local x, y = tonumber(place.x), tonumber(place.y)
    if x and y then
        for _, box in ipairs(CITY_BOXES) do
            if place.zone == box.zone and x >= box.x1 and x <= box.x2
                and y >= box.y1 and y <= box.y2 then
                return box.city
            end
        end
    end
    return place.zone
end
LearnNext.CityOf = CityOf

local function Spots()
    return ns.LEARN_SPOTS or {}
end

local function Plain(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, value = pcall(function(...)
        local v = fn(...)
        if type(v) == "string" and v ~= "" then return v .. "" end
    end, ...)
    return ok and value or nil
end

local function Side()
    local faction = Plain(rawget(_G, "UnitFactionGroup"), "player")
    if faction == "Alliance" then return "A" end
    if faction == "Horde" then return "H" end
    return nil
end

local function OnSide(fac, side)
    return not side or not fac or fac == "" or fac:find(side, 1, true) ~= nil
end

--- The zone the character is in, in the data's English name where the
--- client names it so, else as the client names it.
local function HereZone()
    local name = Plain(rawget(_G, "GetRealZoneText")) or Plain(rawget(_G, "GetZoneText"))
    -- A client in another language names the zone in its own words ("Wald
    -- von Elwynn"); the map the character is on says which of the data's
    -- English zones that is.
    local Waypoints = ns.Waypoints
    if Waypoints and Waypoints.English and not Waypoints.English() and Waypoints.ZONE_MAPS then
        local map = rawget(_G, "C_Map")
        local ok, mapID = pcall(function()
            local id = map and map.GetBestMapForUnit and map.GetBestMapForUnit("player")
            if type(id) == "number" then return id + 0 end
        end)
        if ok and mapID then
            for zone, id in pairs(Waypoints.ZONE_MAPS) do
                if id == mapID then return zone end
            end
        end
    end
    return name
end

-- Kalimdor's zones and cities. Every other zone in the data is on the
-- Eastern Kingdoms; a zone in neither list (an island) prefers nothing.
local KALIMDOR = {
    ["Durotar"] = true, ["Mulgore"] = true, ["The Barrens"] = true,
    ["Teldrassil"] = true, ["Darkshore"] = true, ["Ashenvale"] = true,
    ["Thousand Needles"] = true, ["Stonetalon Mountains"] = true,
    ["Desolace"] = true, ["Feralas"] = true, ["Dustwallow Marsh"] = true,
    ["Tanaris"] = true, ["Azshara"] = true, ["Felwood"] = true,
    ["Un'Goro Crater"] = true, ["Moonglade"] = true, ["Silithus"] = true,
    ["Winterspring"] = true, ["Orgrimmar"] = true, ["Thunder Bluff"] = true,
    ["Darnassus"] = true, ["Mount Hyjal"] = true,
}
local EASTERN = {
    ["Alterac Mountains"] = true, ["Arathi Highlands"] = true,
    ["Badlands"] = true, ["Blasted Lands"] = true, ["Tirisfal Glades"] = true,
    ["Silverpine Forest"] = true, ["Western Plaguelands"] = true,
    ["Eastern Plaguelands"] = true, ["Hillsbrad Foothills"] = true,
    ["The Hinterlands"] = true, ["Dun Morogh"] = true,
    ["Searing Gorge"] = true, ["Burning Steppes"] = true,
    ["Elwynn Forest"] = true, ["Deadwind Pass"] = true, ["Duskwood"] = true,
    ["Loch Modan"] = true, ["Redridge Mountains"] = true,
    ["Stranglethorn Vale"] = true, ["Swamp of Sorrows"] = true,
    ["Westfall"] = true, ["Wetlands"] = true, ["Stormwind City"] = true,
    ["Ironforge"] = true, ["Undercity"] = true,
}

local function ContinentOf(zone)
    if KALIMDOR[zone] then return "K" end
    if EASTERN[zone] then return "E" end
    return nil
end
LearnNext.ContinentOf = ContinentOf

--- The best of a list of places { zone, ... }: the zone the character is in,
--- then one of their side's cities on their continent, then any place on
--- their continent, then one of their side's cities, then the first. A
--- trainer the cities near you don't have is looked for on your own side of
--- the sea before the list's order sends you over it (2026-11-14: Thunder
--- Bluff's Artisan Leatherworking pointed at Arathi, not Feralas).
local function Nearest(places, side)
    local here = HereZone()
    local home = here and ContinentOf(here)
    local cities = side and CITIES[side] or {}
    local city, homeCity, homeAny
    for _, place in ipairs(places) do
        local where = CityOf(place)
        if here and (place.zone == here or where == here) then return place end
        local near = home and ContinentOf(place.zone) == home
        if cities[where] then
            if not city then city = place end
            if near and not homeCity then homeCity = place end
        end
        if near and not homeAny then homeAny = place end
    end
    return homeCity or homeAny or city or places[1]
end

--- Where the game saw a vendor or trainer stand (Logic/VendorPins.lua), or nil.
local function SeenAt(name, zone, kind)
    local pins = ns.VendorPins
    if not (pins and pins.SeenAt) then return nil end
    local ok, seen = pcall(pins.SeenAt, pins, name, zone, kind)
    return ok and type(seen) == "table" and seen or nil
end

--- Trainers who stand inside a dungeon, by Classic skill line: the data's
--- spots leave them out, since a dungeon has no outdoor spot (2026-11-16:
--- Road to 300's Artisan Enchanting step named no trainer, as Annora in
--- Uldaman is the only one). Same shape as a TRAINERS row, plus the
--- dungeon's name; the spot is its entrance in the zone outside, so the pin
--- and the arrow lead to the door. Used only when no outdoor trainer of the
--- player's side teaches that high.
-- { name, zone outside, x, y, faction, highest Classic skill, dungeon }
LearnNext.INSIDE_TRAINERS = {
    [333] = { { "Annora", "Badlands", 44.4, 12.2, "", 300, "Uldaman" } },
}

--- Trainers who teach a rank, by Classic skill line and the rank's cap
--- (150 Journeyman, 225 Expert, 300 Artisan). A trainer's number in the
--- data is the highest recipe it teaches, which also counts specialty
--- trainers who teach no rank at all (2026-11-18: Expert Leatherworking
--- sent players to Brumn Winterhoof in Arathi, an Elemental trainer, and
--- Artisan Tailoring to Josephine Lister in Undercity, a Shadoweave one).
--- Checked against Forever's trainer lists. A line with no list here
--- (Mining) still goes by the highest recipe.
local function Set(...)
    local set = {}
    for _, name in ipairs({ ... }) do set[name] = true end
    return set
end
LearnNext.RANK_TRAINERS = {
    [164] = {                                            -- Blacksmithing
        [150] = Set("Snarl", "Karn Stonehoof", "James Van Brunt", "Traugh",
                    "Rotgath Stonebeard", "Therum Deepforge", "Clarise Gnarltree"),
        [225] = Set("Saru Steelfury", "Bengus Deepforge"),
        [300] = Set("Brikk Keencraft"),
    },
    [165] = {                                            -- Leatherworking
        [150] = Set("Karolek", "Tarn", "Arthur Moore", "Brawn", "Krulmoo Fullmoon",
                    "Faldron", "Fimble Finespindle", "Simon Tanner", "Aayndia Floralwind"),
        [225] = Set("Una", "Telonis"),
        [300] = Set("Hahrana Ironhide", "Drakk Stonehand"),
    },
    [171] = {                                            -- Alchemy
        [150] = Set("Yelmak", "Bena Winterhoof", "Doctor Marsh", "Serge Hinott", "Jaxin Chong",
                    "Sylvanna Forestmoon", "Tally Berryfizz", "Lilyssia Nightbreeze", "Kylanna",
                    "Alchemist Narett"),
        [225] = Set("Doctor Herbert Halsey", "Ainethil"),
        [300] = Set("Rogvar", "Kylanna Windwhisper"),
    },
    [197] = {                                            -- Tailoring
        [150] = Set("Magar", "Tepa", "Rhiannon Davis", "Mahani", "Grarnik Goodstitch",
                    "Me'lynn", "Jormund Stonebrow", "Sellandus"),
        [225] = Set("Josef Gregorian", "Georgio Bolero"),
        [300] = Set("Daryl Stack", "Timothy Worthington"),
    },
    [202] = {                                            -- Engineering
        [150] = Set("Nogg", "Franklin Lloyd", "Trixie Quikswitch", "Lilliam Sparkspindle",
                    "Finbus Geargrind"),
        [225] = Set("Roxxik", "Springspindle Fizzlegear"),
        [300] = Set("Buzzek Bracketswing"),
    },
    [333] = {                                            -- Enchanting
        [150] = Set("Godan", "Teg Dawnstrider", "Lavinia Crowe", "Taladan", "Gimble Thistlefuzz",
                    "Lucan Cordell", "Xylinnia Starshine"),
        [225] = Set("Hgarth", "Kitta Firewind"),
        [300] = Set("Annora"),
    },
}

--- Specialty trainers, by Classic skill line: they teach only their
--- specialty's recipes. A recipe goes to them only when no other trainer
--- of the player's side teaches that high, or when its name is one of
--- theirs (the pattern, where there is one).
LearnNext.SPECIALISTS = {
    [164] = { ["Grumnus Steelshaper"] = false, ["Okothos Ironrager"] = false,
              ["Ironus Coldsteel"] = false, ["Borgosh Corebender"] = false },
    [165] = { ["Brumn Winterhoof"] = false, ["Sarah Tanner"] = false,
              ["Peter Galen"] = false, ["Thorkaf Dragoneye"] = false,
              ["Caryssia Moonhunter"] = false, ["Se'Jib"] = false },
    [197] = { ["Josephine Lister"] = "^Shadoweave", ["Jalane Ayrole"] = "^Shadoweave" },
    [202] = { ["Tinkmaster Overspark"] = false, ["Oglethorpe Obnoticus"] = false,
              ["Nixx Sprocketspring"] = false, ["Vazario Linkgrease"] = false },
}

--- A trainer row as a place to go: its spot where the game saw it stand,
--- else the data's; a dungeon's trainer carries `inside`.
local function TrainerPlace(row)
    local seen = not row[7] and SeenAt(row[1], row[2], "trainer")
    return {
        kind = "trainer", name = row[1], zone = row[2], inside = row[7],
        x = seen and seen.x or row[3], y = seen and seen.y or row[4],
        mapID = seen and seen.mapID,
    }
end

--- Trainers the data keeps under a zone players don't know them by: Tarren
--- Mill's spots are on the Alterac Mountains map, but players look for
--- them in Tarren Mill (2026-11-18). Words only; the pin keeps the zone.
LearnNext.TOWNS = {
    ["Daryl Stack"] = "Tarren Mill",
    ["Serge Hinott"] = "Tarren Mill",
}

--- Where a trainer place is, in words: the dungeon for one inside, the
--- town players know it by, else the zone.
function LearnNext.ZoneName(place)
    return place and (place.inside or LearnNext.TOWNS[place.name or ""] or place.zone) or nil
end

--- Where a recipe is learned: the trainer or vendor to go to.
--
-- @return { kind = "trainer" | "vendor", name, zone, x, y, price, itemID,
--   mapID (only where the game saw a vendor stand) } or nil when neither teaches it on the player's side
function LearnNext:Place(record)
    if not record then return nil end
    local side = Side()
    local spots = Spots()

    local trainers, sideTop = {}, nil
    if record.trainerCost then
        local line = ns.RecipeBook.ClassicLine and ns.RecipeBook.ClassicLine(record.skillLineID)
            or record.skillLineID
        local needs = record.classicSkill or record.skill or 0
        local specialists = LearnNext.SPECIALISTS[line] or {}
        local plain, special, own = {}, {}, {}
        for _, row in ipairs((spots.TRAINERS or {})[line] or {}) do
            if OnSide(row[5], side) then sideTop = math.max(sideTop or 0, row[6] or 0) end
            if OnSide(row[5], side) and (row[6] or 0) >= needs then
                local seen = SeenAt(row[1], row[2], "trainer")
                local place = {
                    kind = "trainer", name = row[1], zone = row[2],
                    x = seen and seen.x or row[3], y = seen and seen.y or row[4],
                    mapID = seen and seen.mapID, price = record.trainerCost,
                }
                local pattern = specialists[row[1]]
                if pattern == nil then
                    plain[#plain + 1] = place
                elseif pattern and type(record.name) == "string" and record.name:find(pattern) then
                    own[#own + 1] = place
                else
                    special[#special + 1] = place
                end
            end
        end
        -- A specialty's own recipe goes to its trainer; any other recipe to
        -- a plain trainer, and to a specialist only when no plain one
        -- teaches that high.
        trainers = (#own > 0 and own) or (#plain > 0 and plain) or special
    end

    local vendors = {}
    for _, itemID in ipairs(record.recipeItems or {}) do
        local book = ns.RECIPE_BOOK and ns.RECIPE_BOOK.ITEMS and ns.RECIPE_BOOK.ITEMS[itemID]
        local list = book and book.v
        for i = 1, list and #list - 2 or 0, 3 do
            if OnSide(list[i + 2], side) then
                -- Where the game saw the vendor stand wins over Classic's
                -- spot: Forever moved some.
                local seen = SeenAt(list[i], list[i + 1])
                local where = seen and { seen.x, seen.y }
                    or (spots.VENDORS or {})[list[i] .. "|" .. (list[i + 1] or "")]
                vendors[#vendors + 1] = {
                    kind = "vendor", name = list[i], zone = list[i + 1] ~= "" and list[i + 1] or nil,
                    x = where and where[1], y = where and where[2], mapID = seen and seen.mapID,
                    price = book[2], itemID = itemID,
                }
            end
        end
        -- Vendors the game showed selling it (Forever's trade camps sell
        -- recipes the book has no vendor for), already of the player's side.
        local pins = ns.VendorPins
        local ok, sellers = false, nil
        if pins and pins.RecipeSellers then ok, sellers = pcall(pins.RecipeSellers, pins, itemID) end
        for _, seller in ipairs(ok and type(sellers) == "table" and sellers or {}) do
            local zone = pins.ZoneName and pins.ZoneName(seller)
            vendors[#vendors + 1] = {
                kind = "vendor", name = seller.name, zone = zone ~= "" and zone or nil,
                x = seller.x, y = seller.y, mapID = seller.mapID,
                price = seller.gold, itemID = itemID,
            }
        end
    end

    -- Every way the player's side has, for "Learn From:": a recipe both
    -- a trainer and a vendor teach matches either.
    local ways = { trainer = #trainers > 0 or nil, vendor = #vendors > 0 or nil }

    -- A trainer first: it is how most recipes are learned, and the cheaper.
    local place = Nearest(trainers, side) or Nearest(vendors, side)
    if place then
        place.ways = ways
        return place
    end

    -- A trainer teaches it (it has a trainer's price) but none the data
    -- places teaches that high: Classic's Artisan trainers stand in places
    -- the data has no spot for. Still listed, with no spot to pin, rather
    -- than left out of the list.
    if record.trainerCost and sideTop and (record.classicSkill or record.skill or 0) > sideTop then
        -- One inside a dungeon, pinned at its door (Annora in Uldaman).
        local line = ns.RecipeBook.ClassicLine and ns.RecipeBook.ClassicLine(record.skillLineID)
            or record.skillLineID
        local needs = record.classicSkill or record.skill or 0
        for _, row in ipairs(LearnNext.INSIDE_TRAINERS[line] or {}) do
            if OnSide(row[5], side) and (row[6] or 0) >= needs then
                local inside = TrainerPlace(row)
                inside.price = record.trainerCost
                inside.ways = { trainer = true }
                return inside
            end
        end
        return { kind = "trainer", name = L["an Artisan trainer"], price = record.trainerCost,
                 ways = { trainer = true } }
    end
    return nil
end

--- The nearest trainer of the player's side for a profession who teaches
--- a rank, for Road to 300's trainer steps (2026-10-20).
-- A trainer's number is the highest recipe it teaches, not the rank's cap,
-- so a trainer teaches the rank whose cap is `needs` when its recipes go
-- past the rank before (needs - 75): Expert (225) wants recipes over 150.
-- Comparing it with the cap sent a 145 Alchemist past Undercity's Expert
-- to Stonard's Artisan (2026-11-13).
-- @param line   the Classic skill line
-- @param needs  the cap of the rank to train (150, 225 or 300)
-- @return { kind = "trainer", name, zone, x, y, mapID } or nil
function LearnNext:TrainerFor(line, needs)
    local side = Side()
    local from = (needs or 0) - 75
    local ranks = LearnNext.RANK_TRAINERS[line]
    local named = ranks and ranks[needs]
    local specialists = LearnNext.SPECIALISTS[line] or {}
    -- Who teaches the rank: by name where the list has the rank, else by
    -- the highest recipe, never a specialty trainer. A list that names no
    -- trainer the data has for this side falls back to the highest recipe.
    local function Teaches(row, byName)
        if byName then return named[row[1]] == true end
        return specialists[row[1]] == nil and (row[6] or 0) > from
    end
    local function Gather(byName)
        local trainers = {}
        for _, row in ipairs((Spots().TRAINERS or {})[line] or {}) do
            if OnSide(row[5], side) and Teaches(row, byName) then
                trainers[#trainers + 1] = TrainerPlace(row)
            end
        end
        if #trainers == 0 then
            for _, row in ipairs(LearnNext.INSIDE_TRAINERS[line] or {}) do
                if OnSide(row[5], side) and Teaches(row, byName) then
                    trainers[#trainers + 1] = TrainerPlace(row)
                end
            end
        end
        return trainers
    end
    local trainers = named and Gather(true) or {}
    if #trainers == 0 then trainers = Gather(false) end
    return Nearest(trainers, side)
end

--- The skill up colour an unlearned recipe gives at a skill, from Forever's
--- yellow and grey; "unknown" when they are not known.
function LearnNext.Tier(record, skill)
    local yellow, grey = record.yellow, record.grey
    if not (yellow and grey and skill) then return "unknown" end
    if skill >= grey then return "trivial" end
    if skill < yellow then return "optimal" end
    if skill < math.floor((yellow + grey) / 2) then return "medium" end
    return "easy"
end

--- How many the bags make, by the recipe's materials.
local function Makes(record)
    local reagents = record.reagents
    if not reagents or #reagents == 0 then return 0 end
    local me = ns.Config and ns.Config:GetCharacterKey()
    local possible = math.huge
    for _, reagent in ipairs(reagents) do
        local ok, have = pcall(ns.Inventory.GetCharacterBagCount, ns.Inventory, me, reagent.itemID)
        local can = math.floor(((ok and tonumber(have)) or 0) / math.max(1, reagent.quantity or 1))
        if can < possible then possible = can end
        if possible == 0 then break end
    end
    return possible == math.huge and 0 or possible
end

--- A recipe got from a drop or a quest (Learn From:, 2026-11-17): no
--- one to go to, so no spot; what its recipe item costs at the auction
--- house when a price is known.
local function ItemPlace(record, ways)
    local kind = ways.drop and "drop" or ways.quest and "quest" or nil
    if not kind then return nil end
    local itemID = record.recipeItems and record.recipeItems[1]
    local best
    for _, id in ipairs(record.recipeItems or {}) do
        local ok, price = false, nil
        if ns.Prices and ns.Prices.GetValue then ok, price = pcall(ns.Prices.GetValue, ns.Prices, id, "lowest") end
        price = ok and tonumber(price) or nil
        if price and price > 0 and (not best or price < best) then best, itemID = price, id end
    end
    return { kind = kind, itemID = itemID, price = best, auction = best ~= nil, ways = ways }
end

--- One row, in the Level Up list's shape, plus where to learn it.
--
-- @param anyWay  also drop and quest recipes, with every way each is got
--   in `place.ways` (Learn From:, 2026-11-17)
function LearnNext:BuildRow(record, skill, anyWay)
    local place = self:Place(record)
    if anyWay then
        local more = ns.RecipeBook and ns.RecipeBook.LearnWays and ns.RecipeBook:LearnWays(record) or {}
        if place then
            place.ways = place.ways or {}
            place.ways.drop, place.ways.quest = more.drop, more.quest
        else
            place = ItemPlace(record, more)
        end
    end
    if not place then return nil end

    local value = ns.RecipeBook:Value(record) or {}
    local tier = LearnNext.Tier(record, skill)
    local needs = record.skill or 0

    return {
        recipeID = record.recipeID,
        record = record,
        name = record.name or L.Format("recipe %s", record.recipeID),
        outputItemID = record.outputItemID,
        skillLineID = record.skillLineID,
        tier = tier,
        cost = value.cost,
        costDetail = value.costDetail,
        returns = value.returns,
        back = value.back,
        backWay = value.backWay,
        realCost = value.cost and value.back and (value.cost - value.back) or nil,
        craftableNow = Makes(record),
        learnNext = true,
        locked = needs > skill,
        needs = needs,
        place = place,
        price = place.price,
        skill = skill,
    }
end

--- The recipes to learn next, cheapest way up first, those still out of
--- reach last.
--
-- @param opts.skills  { [Classic skill line] = the character's skill }
-- @param opts.search  part of a name, any case
-- @param opts.anyWay  drop and quest recipes too (LearnNext.Filter picks)
-- @return rows (BuildRow's)
function LearnNext:GetRows(opts)
    opts = opts or {}
    local skills = opts.skills or {}
    if not next(skills) or not ns.RecipeBook then return {} end
    local needle = opts.search and opts.search ~= "" and opts.search:lower() or nil
    local classic = ns.RecipeBook.ClassicLine or function(id) return id end

    local open, locked = {}, {}
    for _, record in pairs((ns.RecipeBook:GetAll())) do
        local skill = skills[classic(record.skillLineID)]
        local needs = record.skill
        if skill and needs and not record.starter
            and (record.trainerCost or record.recipeItems)
            and needs <= skill + LearnNext.REACH
            and (not needle or (record.name or ""):lower():find(needle, 1, true))
            and not ns.RecipeBook:KnowsIt(record) then
            local tier = LearnNext.Tier(record, math.max(skill, needs))
            -- With no yellow and grey known, a recipe this far below the
            -- skill is grey all the same: Classic's go grey within this.
            if tier == "unknown" and skill >= needs + LearnNext.UNKNOWN_GREY then tier = "trivial" end
            if tier ~= "trivial" then
                local row = self:BuildRow(record, skill, opts.anyWay)
                if row then
                    if row.locked then locked[#locked + 1] = row else open[#open + 1] = row end
                end
            end
        end
    end

    local compare = ns.LevelUp and ns.LevelUp.Compare
    if compare then table.sort(open, compare) end
    table.sort(locked, function(a, b)
        if a.needs ~= b.needs then return a.needs < b.needs end
        if compare then return compare(a, b) end
        return a.name < b.name
    end)
    for _, row in ipairs(locked) do open[#open + 1] = row end
    return open
end

--- The words for where: "Trainer" or "Vendor", and the zone beside a vendor;
--- "Drop" or "Quest or other" for a recipe no one teaches.
function LearnNext.WhereText(place)
    if not place then return "", nil end
    if place.kind == "trainer" then return L["Trainer"], nil end
    if place.kind == "drop" then return L["Drop"], nil end
    if place.kind == "quest" then return L["Quest or other"], nil end
    return L["Vendor"], place.zone
end

--- Can Show the Way lead to it: a trainer or vendor, never a drop or quest.
function LearnNext.CanShowWay(row)
    local kind = row and row.place and row.place.kind
    return kind == "trainer" or kind == "vendor"
end

--------------------------------------------------------------------------------
-- Have Skill and Learn From (the owner said build it, 2026-11-17)
--------------------------------------------------------------------------------

--- The Learn From choices, in the menu's order. "trainerVendor" is the
--- first and the default: the list as it was before the filters.
LearnNext.LEARN_FROM = { "trainerVendor", "trainer", "vendor", "drop", "quest", "any" }
LearnNext.LEARN_FROM_DEFAULT = "trainerVendor"

local FROM_WAYS = {
    trainerVendor = { "trainer", "vendor" },
    trainer = { "trainer" }, vendor = { "vendor" },
    drop = { "drop" }, quest = { "quest" },
}

--- Is a row learned the way picked? A recipe got more than one way
--- matches each.
function LearnNext.Matches(row, from)
    if from == "any" then return true end
    local place = row and row.place
    if not place then return false end
    local ways = place.ways or { [place.kind or ""] = true }
    for _, way in ipairs(FROM_WAYS[from] or FROM_WAYS.trainerVendor) do
        if ways[way] then return true end
    end
    return false
end

--- The rows already built, filtered: Have Skill leaves out those still out
--- of reach, then Learn From keeps the way picked. Nothing is read again.
--
-- @param opts.haveSkill  leave out locked rows
-- @param opts.learnFrom  one of LEARN_FROM
-- @return kept, counts ({ [choice] = rows it would keep, after Have Skill })
function LearnNext.Filter(rows, opts)
    opts = opts or {}
    local from = opts.learnFrom
    if not FROM_WAYS[from] and from ~= "any" then from = LearnNext.LEARN_FROM_DEFAULT end
    local kept, counts = {}, {}
    for _, choice in ipairs(LearnNext.LEARN_FROM) do counts[choice] = 0 end
    for _, row in ipairs(rows or {}) do
        if not (opts.haveSkill and row.locked) then
            for _, choice in ipairs(LearnNext.LEARN_FROM) do
                if LearnNext.Matches(row, choice) then counts[choice] = counts[choice] + 1 end
            end
            if LearnNext.Matches(row, from) then kept[#kept + 1] = row end
        end
    end
    return kept, counts
end

--- What to pin the map for: the recipe item's name or the recipe's.
local function WhatFor(row)
    local item = row.place and row.place.itemID
    local name = item and ns.Util and ns.Util.GetItemLabel and ns.Util.GetItemLabel(item)
    if name and ns.Util.Uncolored then name = ns.Util.Uncolored(name) end
    -- "item 1234" (in the client's language) is GetItemLabel's stand-in
    -- while the item has not loaded: the recipe's own name says more.
    if type(name) == "string" and name ~= "" and name ~= L.Format("item %d", item) then return name end
    return row.name
end

local WHY = {
    nospot = L["no exact spot is known for them"],
    noclient = L["this client cannot put a pin on the map"],
    nomap = L["the map for that zone could not be found"],
}

--- The way there to a trainer or vendor far away, by Logic/Travel.lua (the
--- same file in every Blackthornes addon): its steps and the first stop to
--- pin, or nil when it is near, "Guide Me:" is off or no way is known.
function LearnNext.Guide(place, who)
    local Travel = ns.Travel
    if not (Travel and Travel.IsOn and Travel.IsOn() and place.zone and place.x and place.y) then return nil end
    local mapID = ns.Waypoints and ns.Waypoints:MapFor(place.zone)
    local target = { name = who, zone = place.zone, map = mapID,
        mx = mapID and place.x / 100 or nil, my = mapID and place.y / 100 or nil,
        coords = { place.x, place.y } }
    local ok, guide = pcall(Travel.Guide, Travel, target)
    if not ok or type(guide) ~= "table" or type(guide.point) ~= "table" or #guide.lines == 0 then return nil end
    return guide
end

--- Show the way: the arrow on the trainer or vendor, else the map pin (or
--- TomTom's arrow), and a line in chat that says where.
-- @return true when a pin or waypoint was set
function LearnNext:ShowTheWay(row)
    local place = row and row.place
    if not place then return false end
    local what = WhatFor(row)
    local who = place.name or L["them"]

    local ok, why
    local Waypoints = ns.Waypoints
    -- Our own marker always goes on the map (the game's pin often won't).
    local marked = Waypoints and Waypoints:Mark(place, who) or false

    -- The arrow (Logic/WayArrow.lua), the same as the other addons': it
    -- leads the way step by step with "Guide Me:" ticked, and hands off to
    -- TomTom's arrow when "Use TomTom:" is.
    local arrow = ns.WayArrow
    if arrow and arrow.AimAt then
        local aimed, took = pcall(arrow.AimAt, arrow, place, ("%s (%s)"):format(who, what))
        if aimed and took then
            ns.Print(L.Format("The arrow shows the way to %s (%s).", who, what))
            return true
        end
    end

    -- In another zone or across the sea, with "Guide Me:" ticked: the steps
    -- in chat, and the pin on the first stop (Logic/Travel.lua).
    local guide = LearnNext.Guide(place, who)
    if guide then
        local stop = { mapID = guide.point.map, x = guide.point.x * 100, y = guide.point.y * 100 }
        if Waypoints and Waypoints:HasTomTom() then
            ok = Waypoints:TomTom(stop, guide.point.name)
        end
        if not ok and Waypoints then ok = Waypoints:Pin(stop) end
        if ok then
            ns.Print(L.Format("The way to %s (%s), with a pin on the first stop:", who, what))
            local say = ns.PrintRaw or ns.Print
            for _, line in ipairs(guide.lines) do say("  " .. line) end
            return true
        end
    end

    if Waypoints and Waypoints:HasTomTom() then
        ok, why = Waypoints:TomTom(place, ("%s (%s)"):format(who, what))
    end
    local pinned
    if not ok and Waypoints then
        ok, why = Waypoints:Pin(place)
        pinned = ok
    end
    -- With the game's pin on, the marker goes when the pin does.
    if pinned and marked then Waypoints:Mark(place, who, true) end
    if not ok and marked then ok = true end

    if ok then
        ns.Print(L.Format("Pinned %s (%s) on your map, %s %s, %s.", who, what,
            place.zone, place.x, place.y))
    elseif place.zone then
        ns.Print(L.Format("Can't pin %s (%s): %s. They are in %s.", who, what,
            WHY[why] or L["no exact spot is known for them"], LearnNext.ZoneName(place)))
    else
        ns.Print(L.Format("Can't pin %s (%s): %s.", who, what,
            WHY[why] or L["no exact spot is known for them"]))
    end
    return ok == true
end

--- Where a recipe is learned, by its ID (a recipe's ID is its spell ID),
--- for Equipment's Enchants view. A fresh table, or nil when no trainer or
--- vendor of the player's side teaches it.
-- @return { kind ("trainer" or "vendor"), name, zone, x, y, price }
function LearnNext:WhereFor(recipeID)
    local book = ns.RecipeBook
    if not (book and book.Get) then return nil end
    local ok, record = pcall(book.Get, book, tonumber(recipeID))
    if not ok or type(record) ~= "table" then return nil end
    local placed, place = pcall(self.Place, self, record)
    if not placed or not place then return nil end
    return {
        kind = place.kind, name = place.name, zone = place.zone,
        x = place.x, y = place.y, price = place.price, mapID = place.mapID,
    }
end

--- Show the way to where a recipe is learned, by its ID: the same pin and
--- chat line as the Level Up tab's button.
-- @return true when a pin or waypoint was set
function LearnNext:ShowTheWayFor(recipeID)
    local book = ns.RecipeBook
    if not (book and book.Get) then return false end
    local ok, record = pcall(book.Get, book, tonumber(recipeID))
    if not ok or type(record) ~= "table" then return false end
    local place = self:Place(record)
    if not place then return false end
    return self:ShowTheWay({
        place = place, record = record,
        name = record.name or L.Format("recipe %s", record.recipeID),
    })
end

--- Queue materials: the materials for the crafts that give a skill point
--- for sure (until the recipe turns yellow, at least one), on the list to
--- buy. Set, not added, so a second click changes nothing.
-- @return how many lines were put on the list
function LearnNext:QueueMaterials(row)
    if not (row and row.record and ns.Queue and ns.Queue.EnsureBuy) then return 0 end
    local record = row.record
    local crafts = 1
    if record.yellow and row.skill and record.yellow > math.max(row.skill, row.needs or 0) then
        crafts = record.yellow - math.max(row.skill, row.needs or 0)
    end
    -- Tied to the recipe, not to its item: the first craft makes the item,
    -- and a line for owned gear lets itself go.
    local forRecipe = { recipeID = record.recipeID, name = row.name }
    local added = 0
    for _, reagent in ipairs(record.reagents or {}) do
        local ok, done = pcall(ns.Queue.EnsureBuy, ns.Queue, reagent.itemID,
            (reagent.quantity or 1) * crafts, nil, forRecipe)
        if ok and done then added = added + 1 end
    end
    if added > 0 then
        ns.Print(crafts == 1
            and L.Format("Put the materials for one %s on your list to buy.", row.name)
            or L.Format("Put the materials for %d %s on your list to buy, enough until it turns yellow.", crafts, row.name))
    else
        ns.Print(L.Format("Nothing for %s went on your list to buy.", row.name))
    end
    return added
end
