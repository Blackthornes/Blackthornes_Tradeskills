-- Blackthornes Tradeskills -- Data/CraftsmansWrits.lua
-- Forever's Craftsman's Writs: the crafting orders that raise reputation
-- with the trade camp (Azeroth Commerce Authority for the Alliance, Durotar
-- Supply and Logistics for the Horde).
--
-- A writ drops from mobs as an item, "Craftsman's Writ: <item>", which can
-- be traded. It starts a quest: deliver that item to the customer for
-- reputation and a pouch of silver. Each order can be done once a day.
-- Logic/Writs.lua works out what reaching a reputation goal costs.
--
-- What is typed here, and where it came from (online guides, 2026-10-09,
-- not yet seen in game):
--
--   item, name  what the writ asks for, by its Classic item ID
--   prof, tier  its profession and level: 1 Journeyman, 2 Expert, 3 Artisan
--   skill       the skill the item needs to make
--   count       how many it asks for, when more than one
--   writ        the writ's own item ID, and quest the quest it starts
--               (refreshed writ data, 2026-11-16). A writ the game gives
--               another ID is still found by its name (Writs:FindWrits).
--
-- WRIT_REPUTATION is what each level is reported to pay (the refreshed
-- writ data agrees for every writ). Only reputation
-- this addon has seen a turn-in pay counts as known; these stand in until
-- then, marked as reported.

local _, ns = ...

ns.WRIT_REPUTATION = { 75, 125, 200 }

ns.WRIT_TIERS = { "Journeyman", "Expert", "Artisan" }

-- The two trade camps' faction IDs, as the guides give them. The game's own
-- name for the faction is read too, should an ID be different on Forever.
ns.WRIT_FACTIONS = {
    Alliance = { id = 2586, name = "Azeroth Commerce Authority" },
    Horde = { id = 2587, name = "Durotar Supply and Logistics" },
}

-- Forever's new items sit in one stretch of item IDs; a writ whose ID is not
-- typed below is looked for in it by name.
ns.WRIT_ID_RANGE = { 263990, 264180 }

ns.CRAFTSMANS_WRITS = {
    -- Alchemy, Journeyman
    { item = 3383, name = "Elixir of Wisdom", prof = "Alchemy", tier = 1, skill = 120, writ = 264012, quest = 94212 },
    { item = 5996, name = "Draught of Water Breathing", prof = "Alchemy", tier = 1, skill = 120, writ = 264019, quest = 94219 },
    { item = 3385, name = "Lesser Mana Potion", prof = "Alchemy", tier = 1, skill = 145, writ = 264013, quest = 94213 },
    { item = 3388, name = "Lesser Troll's Blood Elixir", prof = "Alchemy", tier = 1, skill = 150, writ = 264017, quest = 94217 },
    { item = 6048, name = "Shadow Protection Potion", prof = "Alchemy", tier = 1, skill = 160, writ = 264014, quest = 94214 },
    { item = 3390, name = "Elixir of Lesser Agility", prof = "Alchemy", tier = 1, skill = 165, writ = 264016, quest = 94216 },
    { item = 3391, name = "Elixir of Ogre Strength", prof = "Alchemy", tier = 1, skill = 175, writ = 264011, quest = 94004 },
    { item = 5634, name = "Free Action Potion", prof = "Alchemy", tier = 1, skill = 175, writ = 264015, quest = 94215 },
    { item = 8951, name = "Elixir of Defense", prof = "Alchemy", tier = 1, skill = 215, writ = 264018, quest = 94218 },
    -- Alchemy, Expert
    { item = 3827, name = "Mana Potion", prof = "Alchemy", tier = 2, skill = 180, writ = 264062, quest = 94262 },
    { item = 3823, name = "Lesser Invisibility Potion", prof = "Alchemy", tier = 2, skill = 185, writ = 264057, quest = 94257 },
    { item = 3824, name = "Shadow Oil", prof = "Alchemy", tier = 2, skill = 190, writ = 264064, quest = 94264 },
    { item = 5633, name = "Great Rage Potion", prof = "Alchemy", tier = 2, skill = 195, writ = 264061, quest = 94261 },
    { item = 6050, name = "Frost Protection Potion", prof = "Alchemy", tier = 2, skill = 205, writ = 264056, quest = 94256 },
    { item = 8949, name = "Elixir of Agility", prof = "Alchemy", tier = 2, skill = 205, writ = 264066, quest = 94266 },
    { item = 6052, name = "Nature Protection Potion", prof = "Alchemy", tier = 2, skill = 210, writ = 264059, quest = 94259 },
    { item = 6049, name = "Fire Protection Potion", prof = "Alchemy", tier = 2, skill = 210, writ = 264063, quest = 94263 },
    { item = 10592, name = "Catseye Draught", prof = "Alchemy", tier = 2, skill = 220, writ = 264060, quest = 94260 },
    { item = 9061, name = "Goblin Rocket Fuel", prof = "Alchemy", tier = 2, skill = 225, writ = 264065, quest = 94265 },
    { item = 9144, name = "Wildvine Potion", prof = "Alchemy", tier = 2, skill = 225, writ = 264067, quest = 94267 },
    { item = 4623, name = "Lesser Stoneshield Potion", prof = "Alchemy", tier = 2, skill = 230, writ = 264058, quest = 94258 },
    -- Alchemy, Artisan
    { item = 12190, name = "Dreamless Sleep Potion", prof = "Alchemy", tier = 3, skill = 245, writ = 264117, quest = 94317 },
    { item = 9088, name = "Gift of Arthas", prof = "Alchemy", tier = 3, skill = 255, writ = 264120, quest = 94320 },
    { item = 246948, name = "Distilled Firewater", prof = "Alchemy", tier = 3, skill = 260, writ = 264124, quest = 94324 },
    { item = 9224, name = "Potion of Demon Slaying", prof = "Alchemy", tier = 3, skill = 265, writ = 264116, quest = 94316 },
    { item = 9233, name = "Draught of Detect Demon", prof = "Alchemy", tier = 3, skill = 265, writ = 264119, quest = 94319 },
    { item = 3387, name = "Limited Invulnerability Potion", prof = "Alchemy", tier = 3, skill = 275, writ = 264122, quest = 94322 },
    { item = 13457, name = "Greater Fire Protection Potion", prof = "Alchemy", tier = 3, skill = 305, writ = 264118, quest = 94318 },
    { item = 18253, name = "Major Rejuvenation Potion", prof = "Alchemy", tier = 3, skill = 310, writ = 264123, quest = 94323 },
    { item = 13513, name = "Flask of Chromatic Resistance", prof = "Alchemy", tier = 3, skill = 315, writ = 264121, quest = 94321 },
    -- Blacksmithing, Journeyman
    { item = 15869, name = "Silver Skeleton Key", prof = "Blacksmithing", tier = 1, skill = 75, writ = 264023, quest = 94223 },
    { item = 3848, name = "Big Bronze Knife", prof = "Blacksmithing", tier = 1, skill = 110, writ = 264027, quest = 94227 },
    { item = 5540, name = "Pearl-handled Dagger", prof = "Blacksmithing", tier = 1, skill = 115, writ = 264020, quest = 94220 },
    { item = 2865, name = "Rough Bronze Leggings", prof = "Blacksmithing", tier = 1, skill = 120, writ = 264025, quest = 94225 },
    { item = 11128, name = "Golden Rod", prof = "Blacksmithing", tier = 1, skill = 130, writ = 264021, quest = 94221 },
    { item = 3491, name = "Heavy Bronze Mace", prof = "Blacksmithing", tier = 1, skill = 135, writ = 264024, quest = 94224 },
    { item = 5541, name = "Iridescent Hammer", prof = "Blacksmithing", tier = 1, skill = 145, writ = 264022, quest = 94222 },
    { item = 3484, name = "Green Iron Boots", prof = "Blacksmithing", tier = 1, skill = 150, writ = 264028, quest = 94228 },
    { item = 3485, name = "Green Iron Gauntlets", prof = "Blacksmithing", tier = 1, skill = 155, writ = 264026, quest = 94226 },
    -- Blacksmithing, Expert
    { item = 7964, name = "Solid Sharpening Stone", prof = "Blacksmithing", tier = 2, skill = 175, writ = 264075, quest = 94275 },
    { item = 3853, name = "Moonsteel Broadsword", prof = "Blacksmithing", tier = 2, skill = 180, writ = 264073, quest = 94273 },
    { item = 11144, name = "Truesilver Rod", prof = "Blacksmithing", tier = 2, skill = 180, writ = 264077, quest = 94277 },
    { item = 6041, name = "Steel Weapon Chain", prof = "Blacksmithing", tier = 2, skill = 190, writ = 264070, quest = 94270 },
    { item = 3837, name = "Golden Scale Coif", prof = "Blacksmithing", tier = 2, skill = 190, writ = 264074, quest = 94274 },
    { item = 9060, name = "Inlaid Mithril Cylinder", prof = "Blacksmithing", tier = 2, skill = 200, writ = 264069, quest = 94269 },
    { item = 9366, name = "Golden Scale Gauntlets", prof = "Blacksmithing", tier = 2, skill = 200, writ = 264078, quest = 94278 },
    { item = 7922, name = "Steel Plate Helm", prof = "Blacksmithing", tier = 2, skill = 210, writ = 264068, quest = 94268 },
    { item = 7941, name = "Heavy Mithril Axe", prof = "Blacksmithing", tier = 2, skill = 210, writ = 264079, quest = 94279 },
    { item = 7928, name = "Ornate Mithril Shoulders", prof = "Blacksmithing", tier = 2, skill = 220, writ = 264071, quest = 94271 },
    { item = 7942, name = "Blue Glittering Axe", prof = "Blacksmithing", tier = 2, skill = 220, writ = 264072, quest = 94272 },
    { item = 7943, name = "Wicked Mithril Blade", prof = "Blacksmithing", tier = 2, skill = 225, writ = 264076, quest = 94276 },
    -- Blacksmithing, Artisan
    { item = 7929, name = "Orcish War Leggings", prof = "Blacksmithing", tier = 3, skill = 225, writ = 264127, quest = 94327 },
    { item = 7969, name = "Mithril Spurs", prof = "Blacksmithing", tier = 3, skill = 230, writ = 264128, quest = 94328 },
    { item = 15872, name = "Arcanite Skeleton Key", prof = "Blacksmithing", tier = 3, skill = 250, writ = 264132, quest = 94332 },
    { item = 12416, name = "Radiant Belt", prof = "Blacksmithing", tier = 3, skill = 255, writ = 264126, quest = 94326 },
    { item = 7947, name = "Ebon Shiv", prof = "Blacksmithing", tier = 3, skill = 255, writ = 264133, quest = 94333 },
    { item = 12775, name = "Huge Thorium Battleaxe", prof = "Blacksmithing", tier = 3, skill = 280, writ = 264131, quest = 94331 },
    { item = 12417, name = "Radiant Circlet", prof = "Blacksmithing", tier = 3, skill = 290, writ = 264125, quest = 94325 },
    { item = 12422, name = "Imperial Plate Chest", prof = "Blacksmithing", tier = 3, skill = 295, writ = 264129, quest = 94329 },
    { item = 20549, name = "Darkrune Gauntlets", prof = "Blacksmithing", tier = 3, skill = 320, writ = 264130, quest = 94330 },
    -- Engineering, Journeyman
    { item = 6712, name = "Practice Lock", prof = "Engineering", tier = 1, skill = 115, writ = 264033, quest = 94233 },
    { item = 8069, name = "Crafted Solid Shot", prof = "Engineering", tier = 1, skill = 125, count = 200, writ = 264037, quest = 94237 },
    { item = 4380, name = "Big Bronze Bomb", prof = "Engineering", tier = 1, skill = 140, writ = 264036, quest = 94236 },
    { item = 4373, name = "Shadow Goggles", prof = "Engineering", tier = 1, skill = 145, writ = 264034, quest = 94234 },
    { item = 7506, name = "Gnomish Universal Remote", prof = "Engineering", tier = 1, skill = 150, writ = 264035, quest = 94235 },
    { item = 5507, name = "Ornate Spyglass", prof = "Engineering", tier = 1, skill = 160, writ = 264029, quest = 94229 },
    { item = 4381, name = "Minor Recombobulator", prof = "Engineering", tier = 1, skill = 165, writ = 264032, quest = 94232 },
    { item = 4383, name = "Moonsight Rifle", prof = "Engineering", tier = 1, skill = 170, writ = 264031, quest = 94231 },
    { item = 4384, name = "Explosive Sheep", prof = "Engineering", tier = 1, skill = 175, writ = 264030, quest = 94230 },
    -- Engineering, Expert
    { item = 10498, name = "Gyromatic Micro-Adjustor", prof = "Engineering", tier = 2, skill = 175, writ = 264089, quest = 94289 },
    { item = 4392, name = "Advanced Target Dummy", prof = "Engineering", tier = 2, skill = 185, writ = 264081, quest = 94281 },
    { item = 4852, name = "Flash Bomb", prof = "Engineering", tier = 2, skill = 185, writ = 264086, quest = 94286 },
    { item = 10560, name = "Unstable Trigger", prof = "Engineering", tier = 2, skill = 200, writ = 264085, quest = 94285 },
    { item = 11590, name = "Mechanical Repair Kit", prof = "Engineering", tier = 2, skill = 200, writ = 264090, quest = 94290 },
    { item = 4393, name = "Craftsman's Monocle", prof = "Engineering", tier = 2, skill = 205, writ = 264082, quest = 94282 },
    { item = 4395, name = "Goblin Land Mine", prof = "Engineering", tier = 2, skill = 215, writ = 264083, quest = 94283 },
    { item = 10514, name = "Mithril Frag Bomb", prof = "Engineering", tier = 2, skill = 215, writ = 264088, quest = 94288 },
    { item = 4396, name = "Mechanical Dragonling", prof = "Engineering", tier = 2, skill = 220, writ = 264080, quest = 94280 },
    { item = 10500, name = "Fire Goggles", prof = "Engineering", tier = 2, skill = 225, writ = 264087, quest = 94287 },
    { item = 10501, name = "Catseye Ultra Goggles", prof = "Engineering", tier = 2, skill = 240, writ = 264084, quest = 94284 },
    { item = 16005, name = "Dark Iron Bomb", prof = "Engineering", tier = 2, skill = 305, writ = 264091, quest = 94291 },
    -- Engineering, Artisan
    { item = 10548, name = "Sniper Scope", prof = "Engineering", tier = 3, skill = 260, writ = 264141, quest = 94341 },
    { item = 10504, name = "Green Lens", prof = "Engineering", tier = 3, skill = 265, writ = 264135, quest = 94335 },
    { item = 18631, name = "Truesilver Transformer", prof = "Engineering", tier = 3, skill = 270, writ = 264140, quest = 94340 },
    { item = 18645, name = "Gnomish Alarm-O-Bot", prof = "Engineering", tier = 3, skill = 275, writ = 264137, quest = 94337 },
    { item = 15996, name = "Lifelike Mechanical Toad", prof = "Engineering", tier = 3, skill = 285, writ = 264136, quest = 94336 },
    { item = 18587, name = "Goblin Jumper Cables XL", prof = "Engineering", tier = 3, skill = 285, writ = 264138, quest = 94338 },
    { item = 16023, name = "Masterwork Target Dummy", prof = "Engineering", tier = 3, skill = 295, writ = 264134, quest = 94334 },
    { item = 18232, name = "Field Repair Bot 74A", prof = "Engineering", tier = 3, skill = 320, writ = 264139, quest = 94339 },
    { item = 21277, name = "Tranquil Mechanical Yeti", prof = "Engineering", tier = 3, skill = 320, writ = 264142, quest = 94342 },
    -- Leatherworking, Journeyman
    { item = 2317, name = "Dark Leather Tunic", prof = "Leatherworking", tier = 1, skill = 100, writ = 264041, quest = 94241 },
    { item = 5958, name = "Fine Leather Pants", prof = "Leatherworking", tier = 1, skill = 105, writ = 264039, quest = 94239 },
    { item = 7284, name = "Red Whelp Gloves", prof = "Leatherworking", tier = 1, skill = 120, writ = 264046, quest = 94246 },
    { item = 18662, name = "Heavy Leather Ball", prof = "Leatherworking", tier = 1, skill = 125, writ = 264038, quest = 94238 },
    { item = 7349, name = "Herbalist's Gloves", prof = "Leatherworking", tier = 1, skill = 135, writ = 264040, quest = 94240 },
    { item = 7358, name = "Pilferer's Gloves", prof = "Leatherworking", tier = 1, skill = 140, writ = 264042, quest = 94242 },
    { item = 4252, name = "Dark Leather Shoulders", prof = "Leatherworking", tier = 1, skill = 140, writ = 264044, quest = 94244 },
    { item = 7371, name = "Heavy Quiver", prof = "Leatherworking", tier = 1, skill = 145, writ = 264043, quest = 94243 },
    { item = 4254, name = "Barbaric Gloves", prof = "Leatherworking", tier = 1, skill = 150, writ = 264045, quest = 94245 },
    -- Leatherworking, Expert
    { item = 5965, name = "Guardian Cloak", prof = "Leatherworking", tier = 2, skill = 180, writ = 264093, quest = 94293 },
    { item = 7378, name = "Dusky Bracers", prof = "Leatherworking", tier = 2, skill = 180, writ = 264094, quest = 94294 },
    { item = 8174, name = "Comfortable Leather Hat", prof = "Leatherworking", tier = 2, skill = 195, writ = 264092, quest = 94292 },
    { item = 7391, name = "Swift Boots", prof = "Leatherworking", tier = 2, skill = 195, writ = 264098, quest = 94298 },
    { item = 8192, name = "Nightscape Shoulders", prof = "Leatherworking", tier = 2, skill = 205, writ = 264099, quest = 94299 },
    { item = 8189, name = "Turtle Scale Breastplate", prof = "Leatherworking", tier = 2, skill = 205, writ = 264102, quest = 94302 },
    { item = 8200, name = "Big Voodoo Robe", prof = "Leatherworking", tier = 2, skill = 210, writ = 264101, quest = 94301 },
    { item = 8210, name = "Wild Leather Shoulders", prof = "Leatherworking", tier = 2, skill = 215, writ = 264096, quest = 94296 },
    { item = 8201, name = "Big Voodoo Mask", prof = "Leatherworking", tier = 2, skill = 215, writ = 264100, quest = 94300 },
    { item = 8214, name = "Wild Leather Helmet", prof = "Leatherworking", tier = 2, skill = 220, writ = 264095, quest = 94295 },
    { item = 8217, name = "Quickdraw Quiver", prof = "Leatherworking", tier = 2, skill = 220, writ = 264097, quest = 94297 },
    { item = 8218, name = "Thick Leather Ammo Pouch", prof = "Leatherworking", tier = 2, skill = 220, writ = 264103, quest = 94303 },
    -- Leatherworking, Artisan
    { item = 15084, name = "Wicked Leather Bracers", prof = "Leatherworking", tier = 3, skill = 260, writ = 264147, quest = 94347 },
    { item = 15092, name = "Runic Leather Bracers", prof = "Leatherworking", tier = 3, skill = 270, writ = 264150, quest = 94350 },
    { item = 15071, name = "Frostsaber Boots", prof = "Leatherworking", tier = 3, skill = 270, writ = 264151, quest = 94351 },
    { item = 15053, name = "Volcanic Breastplate", prof = "Leatherworking", tier = 3, skill = 280, writ = 264145, quest = 94345 },
    { item = 15087, name = "Wicked Leather Pants", prof = "Leatherworking", tier = 3, skill = 285, writ = 264143, quest = 94343 },
    { item = 18258, name = "Gordok Ogre Suit", prof = "Leatherworking", tier = 3, skill = 285, writ = 264144, quest = 94344 },
    { item = 15094, name = "Runic Leather Headband", prof = "Leatherworking", tier = 3, skill = 285, writ = 264146, quest = 94346 },
    { item = 15075, name = "Chimeric Vest", prof = "Leatherworking", tier = 3, skill = 285, writ = 264148, quest = 94348 },
    { item = 15080, name = "Heavy Scorpid Helm", prof = "Leatherworking", tier = 3, skill = 290, writ = 264149, quest = 94349 },
    -- Tailoring, Journeyman
    { item = 4313, name = "Red Woolen Boots", prof = "Tailoring", tier = 1, skill = 80, writ = 264052, quest = 94252 },
    { item = 10048, name = "Colorful Kilt", prof = "Tailoring", tier = 1, skill = 95, writ = 264053, quest = 94253 },
    { item = 6263, name = "Blue Overalls", prof = "Tailoring", tier = 1, skill = 100, writ = 264048, quest = 94248 },
    { item = 6264, name = "Greater Adept's Robe", prof = "Tailoring", tier = 1, skill = 115, writ = 264054, quest = 94254 },
    { item = 4317, name = "Phoenix Pants", prof = "Tailoring", tier = 1, skill = 125, writ = 264051, quest = 94251 },
    { item = 5766, name = "Lesser Wizard's Robe", prof = "Tailoring", tier = 1, skill = 130, writ = 264047, quest = 94247 },
    { item = 7048, name = "Azure Silk Hood", prof = "Tailoring", tier = 1, skill = 130, writ = 264049, quest = 94249 },
    { item = 4321, name = "Spider Silk Slippers", prof = "Tailoring", tier = 1, skill = 135, writ = 264055, quest = 94255 },
    { item = 4245, name = "Small Silk Pack", prof = "Tailoring", tier = 1, skill = 145, writ = 264050, quest = 94250 },
    -- Tailoring, Expert
    { item = 7061, name = "Earthen Silk Belt", prof = "Tailoring", tier = 2, skill = 180, writ = 264115, quest = 94315 },
    { item = 7063, name = "Crimson Silk Robe", prof = "Tailoring", tier = 2, skill = 185, writ = 264106, quest = 94306 },
    { item = 4329, name = "Star Belt", prof = "Tailoring", tier = 2, skill = 185, writ = 264109, quest = 94309 },
    { item = 9998, name = "Black Mageweave Vest", prof = "Tailoring", tier = 2, skill = 185, writ = 264110, quest = 94310 },
    { item = 10008, name = "White Bandit Mask", prof = "Tailoring", tier = 2, skill = 185, writ = 264113, quest = 94313 },
    { item = 10052, name = "Orange Martial Shirt", prof = "Tailoring", tier = 2, skill = 190, writ = 264112, quest = 94312 },
    { item = 10004, name = "Shadoweave Robe", prof = "Tailoring", tier = 2, skill = 195, writ = 264107, quest = 94307 },
    { item = 10009, name = "Red Mageweave Pants", prof = "Tailoring", tier = 2, skill = 195, writ = 264111, quest = 94311 },
    { item = 10050, name = "Mageweave Bag", prof = "Tailoring", tier = 2, skill = 205, writ = 264104, quest = 94304 },
    { item = 10023, name = "Shadoweave Gloves", prof = "Tailoring", tier = 2, skill = 205, writ = 264105, quest = 94305 },
    { item = 22246, name = "Enchanted Mageweave Pouch", prof = "Tailoring", tier = 2, skill = 205, writ = 264108, quest = 94308 },
    { item = 10042, name = "Cindercloth Robe", prof = "Tailoring", tier = 2, skill = 205, writ = 264114, quest = 94314 },
    -- Tailoring, Artisan
    { item = 10036, name = "Tuxedo Jacket", prof = "Tailoring", tier = 3, skill = 155, writ = 264155, quest = 94355 },
    { item = 10025, name = "Shadoweave Mask", prof = "Tailoring", tier = 3, skill = 215, writ = 264158, quest = 94358 },
    { item = 14046, name = "Runecloth Bag", prof = "Tailoring", tier = 3, skill = 230, writ = 264153, quest = 94353 },
    { item = 21340, name = "Soul Pouch", prof = "Tailoring", tier = 3, skill = 230, writ = 264160, quest = 94360 },
    { item = 14141, name = "Ghostweave Vest", prof = "Tailoring", tier = 3, skill = 240, writ = 264159, quest = 94359 },
    { item = 22251, name = "Cenarion Herb Bag", prof = "Tailoring", tier = 3, skill = 245, writ = 264157, quest = 94357 },
    { item = 13864, name = "Runecloth Boots", prof = "Tailoring", tier = 3, skill = 250, writ = 264154, quest = 94354 },
    { item = 14108, name = "Felcloth Boots", prof = "Tailoring", tier = 3, skill = 255, writ = 264156, quest = 94356 },
    { item = 14130, name = "Wizardweave Turban", prof = "Tailoring", tier = 3, skill = 275, writ = 264152, quest = 94352 },
}

-- Where each writ is handed in, from refreshed writ data (2026-11-16):
-- [item the writ asks for] = { name, zone, mapID, x, y, npc }. npc is the
-- customer's creature ID. A writ missing here is still learned in play.
-- A spot the player learns, or one shipped in Data/ForeverWritCustomers.lua,
-- wins over these (Writs:GetCustomer).
ns.WRIT_HAND_INS = {
    [2317] = { name = "Kzixx", zone = "Duskwood", mapID = 1431, x = 81.8, y = 19.8, npc = 3134 },
    [2865] = { name = "Ziz Fizziks", zone = "Stonetalon Mountains", mapID = 1442, x = 59, y = 62.4, npc = 4201 },
    [3383] = { name = "Muggol Breezebeard", zone = "Arathi Highlands", mapID = 1417, x = 48.8, y = 55.8, npc = 257296 },
    [3385] = { name = "Ash'alari", zone = "Ashenvale", mapID = 1440, x = 60.2, y = 72.4, npc = 257315 },
    [3388] = { name = "Short John Mithril", zone = "Stranglethorn Vale", mapID = 1434, x = 29.6, y = 47.4, npc = 14508 },
    [3390] = { name = "Ziz Fizziks", zone = "Stonetalon Mountains", mapID = 1442, x = 59, y = 62.4, npc = 4201 },
    [3391] = { name = "Sos'mol", zone = "Alterac Mountains", mapID = 1416, x = 38.4, y = 61.2, npc = 257281 },
    [3484] = { name = "Kixxle", zone = "Wetlands", mapID = 1437, x = 50.3, y = 37.8, npc = 8305 },
    [3485] = { name = "\"Sea Wolf\" MacKinley", zone = "Stranglethorn Vale", mapID = 1434, x = 27.8, y = 77.1, npc = 2501 },
    [3491] = { name = "Gorgrash", zone = "Hillsbrad Foothills", mapID = 1424, x = 80, y = 48.4, npc = 261932 },
    [3823] = { name = "Centaur Pariah", zone = "Desolace", mapID = 1443, npc = 13717 },
    [3824] = { name = "Mukomonji", zone = "Swamp of Sorrows", mapID = 1435, x = 62.39, y = 52.85, npc = 262306 },
    [3827] = { name = "Spek", zone = "Riverglades", mapID = 2548, x = 76.91, y = 54.07, npc = 262284 },
    [3837] = { name = "Spek", zone = "Riverglades", mapID = 2548, x = 76.91, y = 54.07, npc = 262284 },
    [3848] = { name = "\"Plucky\" Johnson", zone = "Thousand Needles", mapID = 1441, x = 79.6, y = 75.6, npc = 6626 },
    [3853] = { name = "Meliri", zone = "Moonglade", mapID = 1450, x = 51.18, y = 42.31, npc = 12024 },
    [4245] = { name = "Kzixx", zone = "Duskwood", mapID = 1431, x = 81.8, y = 19.8, npc = 3134 },
    [4252] = { name = "Narkk", zone = "Stranglethorn Vale", mapID = 1434, x = 28.1, y = 74.4, npc = 2663 },
    [4254] = { name = "Goblin Pit Boss", zone = "Thousand Needles", mapID = 1441, x = 79.9, y = 76.7, npc = 4496 },
    [4313] = { name = "Ziz Fizziks", zone = "Stonetalon Mountains", mapID = 1442, x = 59, y = 62.4, npc = 4201 },
    [4317] = { name = "Bath'rah the Windwatcher", zone = "Alterac Mountains", mapID = 1416, x = 80.5, y = 66.9, npc = 6176 },
    [4321] = { name = "Kixxle", zone = "Wetlands", mapID = 1437, x = 50.3, y = 37.8, npc = 8305 },
    [4329] = { name = "Mylentha Riverbend", zone = "Moonglade", mapID = 1450, x = 51.77, y = 32.58, npc = 11795 },
    [4373] = { name = "Ziz Fizziks", zone = "Stonetalon Mountains", mapID = 1442, x = 59, y = 62.4, npc = 4201 },
    [4380] = { name = "Razzeric", zone = "Thousand Needles", mapID = 1441, x = 80.3, y = 76.1, npc = 4706 },
    [4381] = { name = "Kzixx", zone = "Duskwood", mapID = 1431, x = 81.8, y = 19.8, npc = 3134 },
    [4383] = { name = "Grembly", zone = "Ashenvale", mapID = 1440, x = 82.4, y = 50.4, npc = 257317 },
    [4384] = { name = "Alyce", zone = "Arathi Highlands", mapID = 1417, x = 34, y = 23.2, npc = 257304 },
    [4392] = { name = "Bibbly F'utzbuckle", zone = "Desolace", mapID = 1443, x = 62.33, y = 38.99, npc = 11438 },
    [4393] = { name = "The Ravenous", zone = "Dustwallow Marsh", mapID = 1445, x = 54, y = 56.48, npc = 262072 },
    [4395] = { name = "Jessir Moonbow", zone = "Felwood", mapID = 1448, x = 51.35, y = 82.01, npc = 11019 },
    [4623] = { name = "Mudcrush Durtfeet", zone = "Dustwallow Marsh", mapID = 1445, x = 35.15, y = 38.26, npc = 4503 },
    [4852] = { name = "Spek", zone = "Riverglades", mapID = 2548, x = 76.91, y = 54.07, npc = 262284 },
    [5507] = { name = "Alan Sneeks", zone = "Alterac Mountains", mapID = 1416, x = 30.4, y = 61.2, npc = 257282 },
    [5540] = { name = "Alan Sneeks", zone = "Alterac Mountains", mapID = 1416, x = 30.4, y = 61.2, npc = 257282 },
    [5541] = { name = "Cowardly Peon", zone = "Ashenvale", mapID = 1440, x = 78.4, y = 68.8, npc = 257316 },
    [5633] = { name = "Dendrite Starblaze", zone = "Moonglade", mapID = 1450, x = 56.21, y = 30.64, npc = 11802 },
    [5634] = { name = "Webbed Mudsnout Gnoll", zone = "Hillsbrad Foothills", mapID = 1424, x = 62.2, y = 69.2, npc = 261928 },
    [5766] = { name = "Alan Sneeks", zone = "Alterac Mountains", mapID = 1416, x = 30.4, y = 61.2, npc = 257282 },
    [5958] = { name = "Alyce", zone = "Arathi Highlands", mapID = 1417, x = 34, y = 23.2, npc = 257304 },
    [5965] = { name = "Azore Aldamort", zone = "Desolace", mapID = 1443, x = 38.88, y = 27.16, npc = 11863 },
    [5996] = { name = "Kixxle", zone = "Wetlands", mapID = 1437, x = 50.3, y = 37.8, npc = 8305 },
    [6041] = { name = "Ugbert", zone = "Dustwallow Marsh", mapID = 1445, x = 40.99, y = 27.88, npc = 270919 },
    [6048] = { name = "Kzixx", zone = "Duskwood", mapID = 1431, x = 81.8, y = 19.8, npc = 3134 },
    [6049] = { name = "Durganon", zone = "Searing Gorge", mapID = 1427, x = 41.06, y = 58.29, npc = 262294 },
    [6050] = { name = "Lotwil Veriatus", zone = "Badlands", mapID = 1418, x = 25.9, y = 44.9, npc = 2921 },
    [6052] = { name = "Greta Mosshoof", zone = "Felwood", mapID = 1448, x = 51.21, y = 82.11, npc = 10922 },
    [6263] = { name = "Alyce", zone = "Arathi Highlands", mapID = 1417, x = 34, y = 23.2, npc = 257304 },
    [6264] = { name = "Magus Tirth", zone = "Thousand Needles", mapID = 1441, x = 78.3, y = 75.7, npc = 6548 },
    [6712] = { name = "Gorgrash", zone = "Hillsbrad Foothills", mapID = 1424, x = 80, y = 48.4, npc = 261932 },
    [7048] = { name = "Cowardly Peon", zone = "Ashenvale", mapID = 1440, x = 78.4, y = 68.8, npc = 257316 },
    [7061] = { name = "Petra Grossen", zone = "Un'Goro Crater", mapID = 1449, x = 43.7, y = 7.24, npc = 9273 },
    [7063] = { name = "Tabetha", zone = "Dustwallow Marsh", mapID = 1445, npc = 6546 },
    [7284] = { name = "Kixxle", zone = "Wetlands", mapID = 1437, x = 50.3, y = 37.8, npc = 8305 },
    [7349] = { name = "Murache", zone = "Ashenvale", mapID = 1440, npc = 257322 },
    [7358] = { name = "Kris Legace", zone = "Hillsbrad Foothills", mapID = 1424, x = 80.1, y = 38.9, npc = 3536 },
    [7371] = { name = "Ziz Fizziks", zone = "Stonetalon Mountains", mapID = 1442, x = 59, y = 62.4, npc = 4201 },
    [7378] = { name = "The Ravenous", zone = "Dustwallow Marsh", mapID = 1445, x = 54, y = 56.48, npc = 262072 },
    [7391] = { name = "Spek", zone = "Riverglades", mapID = 2548, x = 76.91, y = 54.07, npc = 262284 },
    [7506] = { name = "Scooty", zone = "Stranglethorn Vale", mapID = 1434, x = 27.6, y = 77.4, npc = 7853 },
    [7922] = { name = "Furious Shadowforge Digger", zone = "Badlands", mapID = 1418, x = 44.29, y = 11.42, npc = 257429 },
    [7928] = { name = "Taronn Redfeather", zone = "Felwood", mapID = 1448, x = 50.89, y = 81.62, npc = 10921 },
    [7941] = { name = "Torwa Pathfinder", zone = "Un'Goro Crater", mapID = 1449, x = 71.64, y = 75.96, npc = 9619 },
    [7942] = { name = "Scout Raroul", zone = "Feralas", mapID = 1444, x = 72.41, y = 52.47, npc = 262143 },
    [7964] = { name = "Master Smith Burninate", zone = "Searing Gorge", mapID = 1427, x = 38.8, y = 28.51, npc = 14624 },
    [8069] = { name = "Kixxle", zone = "Wetlands", mapID = 1437, x = 50.3, y = 37.8, npc = 8305 },
    [8174] = { name = "Garek", zone = "Badlands", mapID = 1418, x = 61.94, y = 54.26, npc = 2888 },
    [8189] = { name = "Juo", zone = "The Hinterlands", mapID = 1425, x = 80.13, y = 55.39, npc = 262388 },
    [8192] = { name = "Evonice Sootsmoker", zone = "Searing Gorge", mapID = 1427, x = 38.35, y = 27.74, npc = 14628 },
    [8200] = { name = "Yeh'kinya", zone = "Tanaris", mapID = 1446, x = 66.99, y = 22.36, npc = 8579 },
    [8201] = { name = "Mukomonji", zone = "Swamp of Sorrows", mapID = 1435, x = 62.39, y = 52.85, npc = 262306 },
    [8210] = { name = "Scout Raroul", zone = "Feralas", mapID = 1444, x = 72.41, y = 52.47, npc = 262143 },
    [8214] = { name = "Ivy Leafrunner", zone = "Felwood", mapID = 1448, x = 50.96, y = 81.58, npc = 10924 },
    [8217] = { name = "Narianna", zone = "Moonglade", mapID = 1450, x = 53.34, y = 42.7, npc = 12029 },
    [8218] = { name = "Nergal", zone = "Un'Goro Crater", mapID = 1449, x = 43.27, y = 7.73, npc = 12959 },
    [8949] = { name = "Juo", zone = "The Hinterlands", mapID = 1425, x = 80.13, y = 55.39, npc = 262388 },
    [8951] = { name = "Rizzle Brassbolts", zone = "Thousand Needles", mapID = 1441, x = 77.2, y = 77.4, npc = 4720 },
    [9060] = { name = "Bibbly F'utzbuckle", zone = "Desolace", mapID = 1443, x = 62.33, y = 38.99, npc = 11438 },
    [9061] = { name = "Alchemist Pestlezugg", zone = "Tanaris", mapID = 1446, x = 50.89, y = 26.96, npc = 5594 },
    [9144] = { name = "Spark Nilminer", zone = "Un'Goro Crater", mapID = 1449, x = 43.5, y = 7.42, npc = 9272 },
    [9998] = { name = "Spek", zone = "Riverglades", mapID = 2548, x = 76.91, y = 54.07, npc = 262284 },
    [10004] = { name = "Eridan Bluewind", zone = "Felwood", mapID = 1448, x = 51.35, y = 81.51, npc = 9116 },
    [10008] = { name = "Vizzklick", zone = "Tanaris", mapID = 1446, x = 51.01, y = 27.36, npc = 6568 },
    [10009] = { name = "Lookout Captain Lolo Longstriker", zone = "Searing Gorge", mapID = 1427, x = 37.74, y = 26.56, npc = 14634 },
    [10023] = { name = "Willow", zone = "Desolace", mapID = 1443, x = 62.2, y = 39.63, npc = 13656 },
    [10036] = { name = "Hastings", zone = "Deadwind Pass", mapID = 1430, x = 46.99, y = 75.32, npc = 257743 },
    [10048] = { name = "Hekshi", zone = "Stranglethorn Vale", mapID = 1434, x = 50.4, y = 19.2, npc = 261961 },
    [10050] = { name = "Rigglefuzz", zone = "Badlands", mapID = 1418, x = 42.39, y = 52.93, npc = 2817 },
    [10052] = { name = "Bullets Bigblast", zone = "Swamp of Sorrows", mapID = 1435, x = 69.98, y = 41.6, npc = 262379 },
    [10498] = { name = "Jhordy Lapforge", zone = "Tanaris", mapID = 1446, x = 52.3, y = 26.89, npc = 14743 },
    [10500] = { name = "Durganon", zone = "Searing Gorge", mapID = 1427, x = 41.06, y = 58.29, npc = 262294 },
    [10501] = { name = "Scout Raroul", zone = "Feralas", mapID = 1444, x = 72.41, y = 52.47, npc = 262143 },
    [10514] = { name = "Bullets Bigblast", zone = "Swamp of Sorrows", mapID = 1435, x = 69.98, y = 41.6, npc = 262379 },
    [10560] = { name = "Narianna", zone = "Moonglade", mapID = 1450, x = 53.34, y = 42.7, npc = 12029 },
    [10592] = { name = "Scout Raroul", zone = "Feralas", mapID = 1444, x = 72.41, y = 52.47, npc = 262143 },
    [11128] = { name = "Muggol Breezebeard", zone = "Arathi Highlands", mapID = 1417, x = 48.8, y = 55.8, npc = 257296 },
    [11144] = { name = "Spigot Operator Luglunket", zone = "Tanaris", mapID = 1446, x = 52.49, y = 28.45, npc = 7408 },
    [11590] = { name = "Rhapsody Shindigger", zone = "The Hinterlands", mapID = 1425, x = 26.94, y = 48.59, npc = 5634 },
    [18232] = { name = "Kaylaena Springwhisper", zone = "Mount Hyjal", mapID = 2482, x = 60.1, y = 61.18, npc = 249235 },
    [18662] = { name = "Sos'mol", zone = "Alterac Mountains", mapID = 1416, x = 38.3, y = 61.2, npc = 257281 },
    [22246] = { name = "Impsy", zone = "Felwood", mapID = 1448, x = 41.36, y = 45.02, npc = 14470 },
}
