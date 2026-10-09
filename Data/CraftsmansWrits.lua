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
--   writ        the writ's own item ID, where a guide lists it. Any other
--               is found by its name in the game (Writs:FindWrits).
--
-- WRIT_REPUTATION is what each level is reported to pay. Only reputation
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
    { item = 3383, name = "Elixir of Wisdom", prof = "Alchemy", tier = 1, skill = 120 },
    { item = 5996, name = "Draught of Water Breathing", prof = "Alchemy", tier = 1, skill = 120 },
    { item = 3385, name = "Lesser Mana Potion", prof = "Alchemy", tier = 1, skill = 145 },
    { item = 3388, name = "Lesser Troll's Blood Elixir", prof = "Alchemy", tier = 1, skill = 150 },
    { item = 6048, name = "Shadow Protection Potion", prof = "Alchemy", tier = 1, skill = 160 },
    { item = 3390, name = "Elixir of Lesser Agility", prof = "Alchemy", tier = 1, skill = 165 },
    { item = 3391, name = "Elixir of Ogre Strength", prof = "Alchemy", tier = 1, skill = 175 },
    { item = 5634, name = "Free Action Potion", prof = "Alchemy", tier = 1, skill = 175 },
    { item = 8951, name = "Elixir of Defense", prof = "Alchemy", tier = 1, skill = 215 },
    -- Alchemy, Expert
    { item = 3827, name = "Mana Potion", prof = "Alchemy", tier = 2, skill = 180 },
    { item = 3823, name = "Lesser Invisibility Potion", prof = "Alchemy", tier = 2, skill = 185 },
    { item = 3824, name = "Shadow Oil", prof = "Alchemy", tier = 2, skill = 190 },
    { item = 5633, name = "Great Rage Potion", prof = "Alchemy", tier = 2, skill = 195 },
    { item = 6050, name = "Frost Protection Potion", prof = "Alchemy", tier = 2, skill = 205 },
    { item = 8949, name = "Elixir of Agility", prof = "Alchemy", tier = 2, skill = 205 },
    { item = 6052, name = "Nature Protection Potion", prof = "Alchemy", tier = 2, skill = 210 },
    { item = 6049, name = "Fire Protection Potion", prof = "Alchemy", tier = 2, skill = 210 },
    { item = 10592, name = "Catseye Draught", prof = "Alchemy", tier = 2, skill = 220 },
    { item = 9061, name = "Goblin Rocket Fuel", prof = "Alchemy", tier = 2, skill = 225 },
    { item = 9144, name = "Wildvine Potion", prof = "Alchemy", tier = 2, skill = 225 },
    { item = 4623, name = "Lesser Stoneshield Potion", prof = "Alchemy", tier = 2, skill = 230 },
    -- Alchemy, Artisan
    { item = 12190, name = "Dreamless Sleep Potion", prof = "Alchemy", tier = 3, skill = 245 },
    { item = 9088, name = "Gift of Arthas", prof = "Alchemy", tier = 3, skill = 255, writ = 264120 },
    { item = 246948, name = "Distilled Firewater", prof = "Alchemy", tier = 3, skill = 260 },
    { item = 9224, name = "Potion of Demon Slaying", prof = "Alchemy", tier = 3, skill = 265 },
    { item = 9233, name = "Draught of Detect Demon", prof = "Alchemy", tier = 3, skill = 265 },
    { item = 3387, name = "Limited Invulnerability Potion", prof = "Alchemy", tier = 3, skill = 275 },
    { item = 13457, name = "Greater Fire Protection Potion", prof = "Alchemy", tier = 3, skill = 305 },
    { item = 18253, name = "Major Rejuvenation Potion", prof = "Alchemy", tier = 3, skill = 310 },
    { item = 13513, name = "Flask of Chromatic Resistance", prof = "Alchemy", tier = 3, skill = 315 },
    -- Blacksmithing, Journeyman
    { item = 15869, name = "Silver Skeleton Key", prof = "Blacksmithing", tier = 1, skill = 75 },
    { item = 3848, name = "Big Bronze Knife", prof = "Blacksmithing", tier = 1, skill = 110 },
    { item = 5540, name = "Pearl-handled Dagger", prof = "Blacksmithing", tier = 1, skill = 115 },
    { item = 2865, name = "Rough Bronze Leggings", prof = "Blacksmithing", tier = 1, skill = 120 },
    { item = 11128, name = "Golden Rod", prof = "Blacksmithing", tier = 1, skill = 130, writ = 264021 },
    { item = 3491, name = "Heavy Bronze Mace", prof = "Blacksmithing", tier = 1, skill = 135 },
    { item = 5541, name = "Iridescent Hammer", prof = "Blacksmithing", tier = 1, skill = 145 },
    { item = 3484, name = "Green Iron Boots", prof = "Blacksmithing", tier = 1, skill = 150 },
    { item = 3485, name = "Green Iron Gauntlets", prof = "Blacksmithing", tier = 1, skill = 155 },
    -- Blacksmithing, Expert
    { item = 7964, name = "Solid Sharpening Stone", prof = "Blacksmithing", tier = 2, skill = 175 },
    { item = 3853, name = "Moonsteel Broadsword", prof = "Blacksmithing", tier = 2, skill = 180 },
    { item = 11144, name = "Truesilver Rod", prof = "Blacksmithing", tier = 2, skill = 180 },
    { item = 6041, name = "Steel Weapon Chain", prof = "Blacksmithing", tier = 2, skill = 190 },
    { item = 3837, name = "Golden Scale Coif", prof = "Blacksmithing", tier = 2, skill = 190 },
    { item = 9060, name = "Inlaid Mithril Cylinder", prof = "Blacksmithing", tier = 2, skill = 200 },
    { item = 9366, name = "Golden Scale Gauntlets", prof = "Blacksmithing", tier = 2, skill = 200 },
    { item = 7922, name = "Steel Plate Helm", prof = "Blacksmithing", tier = 2, skill = 210 },
    { item = 7941, name = "Heavy Mithril Axe", prof = "Blacksmithing", tier = 2, skill = 210 },
    { item = 7928, name = "Ornate Mithril Shoulders", prof = "Blacksmithing", tier = 2, skill = 220 },
    { item = 7942, name = "Blue Glittering Axe", prof = "Blacksmithing", tier = 2, skill = 220 },
    { item = 7943, name = "Wicked Mithril Blade", prof = "Blacksmithing", tier = 2, skill = 225 },
    -- Blacksmithing, Artisan
    { item = 7929, name = "Orcish War Leggings", prof = "Blacksmithing", tier = 3, skill = 225 },
    { item = 7969, name = "Mithril Spurs", prof = "Blacksmithing", tier = 3, skill = 230 },
    { item = 15872, name = "Arcanite Skeleton Key", prof = "Blacksmithing", tier = 3, skill = 250 },
    { item = 12416, name = "Radiant Belt", prof = "Blacksmithing", tier = 3, skill = 255 },
    { item = 7947, name = "Ebon Shiv", prof = "Blacksmithing", tier = 3, skill = 255 },
    { item = 12775, name = "Huge Thorium Battleaxe", prof = "Blacksmithing", tier = 3, skill = 280 },
    { item = 12417, name = "Radiant Circlet", prof = "Blacksmithing", tier = 3, skill = 290 },
    { item = 12422, name = "Imperial Plate Chest", prof = "Blacksmithing", tier = 3, skill = 295 },
    { item = 20549, name = "Darkrune Gauntlets", prof = "Blacksmithing", tier = 3, skill = 320 },
    -- Engineering, Journeyman
    { item = 6712, name = "Practice Lock", prof = "Engineering", tier = 1, skill = 115, writ = 264033 },
    { item = 8069, name = "Crafted Solid Shot", prof = "Engineering", tier = 1, skill = 125, count = 200 },
    { item = 4380, name = "Big Bronze Bomb", prof = "Engineering", tier = 1, skill = 140 },
    { item = 4373, name = "Shadow Goggles", prof = "Engineering", tier = 1, skill = 145 },
    { item = 7506, name = "Gnomish Universal Remote", prof = "Engineering", tier = 1, skill = 150 },
    { item = 5507, name = "Ornate Spyglass", prof = "Engineering", tier = 1, skill = 160 },
    { item = 4381, name = "Minor Recombobulator", prof = "Engineering", tier = 1, skill = 165 },
    { item = 4383, name = "Moonsight Rifle", prof = "Engineering", tier = 1, skill = 170 },
    { item = 4384, name = "Explosive Sheep", prof = "Engineering", tier = 1, skill = 175, writ = 264030 },
    -- Engineering, Expert
    { item = 10498, name = "Gyromatic Micro-Adjustor", prof = "Engineering", tier = 2, skill = 175 },
    { item = 4392, name = "Advanced Target Dummy", prof = "Engineering", tier = 2, skill = 185 },
    { item = 4852, name = "Flash Bomb", prof = "Engineering", tier = 2, skill = 185 },
    { item = 10560, name = "Unstable Trigger", prof = "Engineering", tier = 2, skill = 200 },
    { item = 11590, name = "Mechanical Repair Kit", prof = "Engineering", tier = 2, skill = 200 },
    { item = 4393, name = "Craftsman's Monocle", prof = "Engineering", tier = 2, skill = 205 },
    { item = 4395, name = "Goblin Land Mine", prof = "Engineering", tier = 2, skill = 215 },
    { item = 10514, name = "Mithril Frag Bomb", prof = "Engineering", tier = 2, skill = 215 },
    { item = 4396, name = "Mechanical Dragonling", prof = "Engineering", tier = 2, skill = 220 },
    { item = 10500, name = "Fire Goggles", prof = "Engineering", tier = 2, skill = 225 },
    { item = 10501, name = "Catseye Ultra Goggles", prof = "Engineering", tier = 2, skill = 240 },
    { item = 16005, name = "Dark Iron Bomb", prof = "Engineering", tier = 2, skill = 305 },
    -- Engineering, Artisan
    { item = 10548, name = "Sniper Scope", prof = "Engineering", tier = 3, skill = 260 },
    { item = 10504, name = "Green Lens", prof = "Engineering", tier = 3, skill = 265 },
    { item = 18631, name = "Truesilver Transformer", prof = "Engineering", tier = 3, skill = 270 },
    { item = 18645, name = "Gnomish Alarm-O-Bot", prof = "Engineering", tier = 3, skill = 275 },
    { item = 15996, name = "Lifelike Mechanical Toad", prof = "Engineering", tier = 3, skill = 285 },
    { item = 18587, name = "Goblin Jumper Cables XL", prof = "Engineering", tier = 3, skill = 285 },
    { item = 16023, name = "Masterwork Target Dummy", prof = "Engineering", tier = 3, skill = 295 },
    { item = 18232, name = "Field Repair Bot 74A", prof = "Engineering", tier = 3, skill = 320 },
    { item = 21277, name = "Tranquil Mechanical Yeti", prof = "Engineering", tier = 3, skill = 320 },
    -- Leatherworking, Journeyman
    { item = 2317, name = "Dark Leather Tunic", prof = "Leatherworking", tier = 1, skill = 100 },
    { item = 5958, name = "Fine Leather Pants", prof = "Leatherworking", tier = 1, skill = 105 },
    { item = 7284, name = "Red Whelp Gloves", prof = "Leatherworking", tier = 1, skill = 120 },
    { item = 18662, name = "Heavy Leather Ball", prof = "Leatherworking", tier = 1, skill = 125 },
    { item = 7349, name = "Herbalist's Gloves", prof = "Leatherworking", tier = 1, skill = 135 },
    { item = 7358, name = "Pilferer's Gloves", prof = "Leatherworking", tier = 1, skill = 140, writ = 264042 },
    { item = 4252, name = "Dark Leather Shoulders", prof = "Leatherworking", tier = 1, skill = 140 },
    { item = 7371, name = "Heavy Quiver", prof = "Leatherworking", tier = 1, skill = 145 },
    { item = 4254, name = "Barbaric Gloves", prof = "Leatherworking", tier = 1, skill = 150, writ = 264045 },
    -- Leatherworking, Expert
    { item = 5965, name = "Guardian Cloak", prof = "Leatherworking", tier = 2, skill = 180 },
    { item = 7378, name = "Dusky Bracers", prof = "Leatherworking", tier = 2, skill = 180 },
    { item = 8174, name = "Comfortable Leather Hat", prof = "Leatherworking", tier = 2, skill = 195 },
    { item = 7391, name = "Swift Boots", prof = "Leatherworking", tier = 2, skill = 195 },
    { item = 8192, name = "Nightscape Shoulders", prof = "Leatherworking", tier = 2, skill = 205 },
    { item = 8189, name = "Turtle Scale Breastplate", prof = "Leatherworking", tier = 2, skill = 205 },
    { item = 8200, name = "Big Voodoo Robe", prof = "Leatherworking", tier = 2, skill = 210 },
    { item = 8210, name = "Wild Leather Shoulders", prof = "Leatherworking", tier = 2, skill = 215 },
    { item = 8201, name = "Big Voodoo Mask", prof = "Leatherworking", tier = 2, skill = 215 },
    { item = 8214, name = "Wild Leather Helmet", prof = "Leatherworking", tier = 2, skill = 220 },
    { item = 8217, name = "Quickdraw Quiver", prof = "Leatherworking", tier = 2, skill = 220 },
    { item = 8218, name = "Thick Leather Ammo Pouch", prof = "Leatherworking", tier = 2, skill = 220 },
    -- Leatherworking, Artisan
    { item = 15084, name = "Wicked Leather Bracers", prof = "Leatherworking", tier = 3, skill = 260 },
    { item = 15092, name = "Runic Leather Bracers", prof = "Leatherworking", tier = 3, skill = 270 },
    { item = 15071, name = "Frostsaber Boots", prof = "Leatherworking", tier = 3, skill = 270 },
    { item = 15053, name = "Volcanic Breastplate", prof = "Leatherworking", tier = 3, skill = 280 },
    { item = 15087, name = "Wicked Leather Pants", prof = "Leatherworking", tier = 3, skill = 285 },
    { item = 18258, name = "Gordok Ogre Suit", prof = "Leatherworking", tier = 3, skill = 285 },
    { item = 15094, name = "Runic Leather Headband", prof = "Leatherworking", tier = 3, skill = 285 },
    { item = 15075, name = "Chimeric Vest", prof = "Leatherworking", tier = 3, skill = 285 },
    { item = 15080, name = "Heavy Scorpid Helm", prof = "Leatherworking", tier = 3, skill = 290 },
    -- Tailoring, Journeyman
    { item = 4313, name = "Red Woolen Boots", prof = "Tailoring", tier = 1, skill = 80 },
    { item = 10048, name = "Colorful Kilt", prof = "Tailoring", tier = 1, skill = 95 },
    { item = 6263, name = "Blue Overalls", prof = "Tailoring", tier = 1, skill = 100 },
    { item = 6264, name = "Greater Adept's Robe", prof = "Tailoring", tier = 1, skill = 115 },
    { item = 4317, name = "Phoenix Pants", prof = "Tailoring", tier = 1, skill = 125 },
    { item = 5766, name = "Lesser Wizard's Robe", prof = "Tailoring", tier = 1, skill = 130 },
    { item = 7048, name = "Azure Silk Hood", prof = "Tailoring", tier = 1, skill = 130 },
    { item = 4321, name = "Spider Silk Slippers", prof = "Tailoring", tier = 1, skill = 135 },
    { item = 4245, name = "Small Silk Pack", prof = "Tailoring", tier = 1, skill = 145 },
    -- Tailoring, Expert
    { item = 7061, name = "Earthen Silk Belt", prof = "Tailoring", tier = 2, skill = 180 },
    { item = 7063, name = "Crimson Silk Robe", prof = "Tailoring", tier = 2, skill = 185 },
    { item = 4329, name = "Star Belt", prof = "Tailoring", tier = 2, skill = 185 },
    { item = 9998, name = "Black Mageweave Vest", prof = "Tailoring", tier = 2, skill = 185 },
    { item = 10008, name = "White Bandit Mask", prof = "Tailoring", tier = 2, skill = 185 },
    { item = 10052, name = "Orange Martial Shirt", prof = "Tailoring", tier = 2, skill = 190 },
    { item = 10004, name = "Shadoweave Robe", prof = "Tailoring", tier = 2, skill = 195 },
    { item = 10009, name = "Red Mageweave Pants", prof = "Tailoring", tier = 2, skill = 195 },
    { item = 10050, name = "Mageweave Bag", prof = "Tailoring", tier = 2, skill = 205 },
    { item = 10023, name = "Shadoweave Gloves", prof = "Tailoring", tier = 2, skill = 205 },
    { item = 22246, name = "Enchanted Mageweave Pouch", prof = "Tailoring", tier = 2, skill = 205 },
    { item = 10042, name = "Cindercloth Robe", prof = "Tailoring", tier = 2, skill = 205 },
    -- Tailoring, Artisan
    { item = 10036, name = "Tuxedo Jacket", prof = "Tailoring", tier = 3, skill = 155 },
    { item = 10025, name = "Shadoweave Mask", prof = "Tailoring", tier = 3, skill = 215 },
    { item = 14046, name = "Runecloth Bag", prof = "Tailoring", tier = 3, skill = 230 },
    { item = 21340, name = "Soul Pouch", prof = "Tailoring", tier = 3, skill = 230 },
    { item = 14141, name = "Ghostweave Vest", prof = "Tailoring", tier = 3, skill = 240 },
    { item = 22251, name = "Cenarion Herb Bag", prof = "Tailoring", tier = 3, skill = 245 },
    { item = 13864, name = "Runecloth Boots", prof = "Tailoring", tier = 3, skill = 250 },
    { item = 14108, name = "Felcloth Boots", prof = "Tailoring", tier = 3, skill = 255 },
    { item = 14130, name = "Wizardweave Turban", prof = "Tailoring", tier = 3, skill = 275 },
}
