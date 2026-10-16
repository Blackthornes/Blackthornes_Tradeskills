-- Blackthornes Tradeskills -- Data/WaylaidCrates.lua
-- Forever's Waylaid Crates: what fills each one, and what handing it in pays.
--
-- A Waylaid Crate drops from mobs. Using it fills it with any one bundle from
-- the list on its label, and the filled crate is handed to the faction's
-- Supply Officer for Merchant's Favor and a little silver. Any character can
-- do it whatever their professions, so buying the crate and the cheapest
-- bundle on the auction house is a way to buy favor (a player's idea and
-- spreadsheet, 2026-10-08). Logic/MerchantsFavor.lua works out what each
-- favor costs.
--
-- What is typed here, and where it came from:
--
--   bundles  item ID and count. From a player's spreadsheet, which they read off
--            the crates in game; Apprentice Textiles matches the item's own
--            "Use:" text. The item IDs are the Classic ones, checked against
--            the recipe book and Farmer's data.
--   id       the crate's item ID, from the Forever client's game tables;
--            248684, 248687 and 248705 were also looted in Forever (Farmer's
--            harvest). A crate the game names under another ID is still
--            found by its name (MerchantsFavor:FindCrates).
--   favor,   what players report a turn-in pays, silver in copper. A crate
--   silver   filled with plain goods (herbs, ore, cloth, dust) pays 5, 10 or 15
--            favor by tier, one filled with crafted goods 10, 20 or 30, and
--            the silver is 50 copper a favor (checked 2026-10-16 against
--            players' turn-in reports; Expert's silver follows the rule). Only a reward this addon has seen paid
--            (MerchantsFavor's learned rewards) counts as known; these are
--            shown as reported until then. Artisan crates are not in the game
--            yet, so nobody knows what they pay and nothing is filled in.
--
-- `words` are what the crate's name must hold, lower case, so a name the
-- game words a little differently ("Expert Earthly Herbs", "Earthly Expert")
-- is still found.

local _, ns = ...

ns.WAYLAID_CRATES = {
    -- Apprentice
    { key = "apprentice-curiosities", tier = 1, label = "Apprentice Curiosities", id = 248685,
      words = { "apprentice", "curiosities" }, favor = 5, silver = 250,
      bundles = { { 10940, 20 }, { 10939, 4 }, { 10978, 6 }, { 11084, 2 } } },
      -- Strange Dust, Greater Magic Essence, Small and Large Glimmering Shard
    { key = "apprentice-herbs", tier = 1, label = "Apprentice Herbs", id = 248682,
      words = { "apprentice", "herbs" }, favor = 5, silver = 250,
      bundles = { { 2447, 20 }, { 765, 20 }, { 2449, 10 }, { 785, 10 }, { 2450, 10 } } },
      -- Peacebloom, Silverleaf, Earthroot, Mageroyal, Briarthorn
    { key = "apprentice-ore", tier = 1, label = "Apprentice Ore", id = 248683,
      words = { "apprentice", "ore" }, favor = 5, silver = 250,
      bundles = { { 2770, 20 }, { 2771, 20 } } },
      -- Copper Ore, Tin Ore
    { key = "apprentice-textiles", tier = 1, label = "Apprentice Textiles", id = 248684,
      words = { "apprentice", "textiles" }, favor = 5, silver = 250,
      bundles = { { 2589, 40 }, { 2318, 20 } } },
      -- Linen Cloth, Light Leather
    { key = "apprentice-fabrics", tier = 1, label = "Apprentice Fabrics", id = 248702,
      words = { "apprentice", "fabrics" }, favor = 10, silver = 500,
      bundles = { { 4231, 2 }, { 2996, 20 } } },
      -- Cured Light Hide, Bolt of Linen Cloth
    { key = "apprentice-ingots", tier = 1, label = "Apprentice Ingots", id = 248703,
      words = { "apprentice", "ingots" }, favor = 10, silver = 500,
      bundles = { { 2840, 20 }, { 3576, 20 }, { 2841, 10 } } },
      -- Copper Bar, Tin Bar, Bronze Bar
    { key = "apprentice-parts", tier = 1, label = "Apprentice Parts", id = 248704,
      words = { "apprentice", "parts" }, favor = 10, silver = 500,
      bundles = { { 4359, 16 }, { 4361, 16 }, { 4363, 4 } } },
      -- Handful of Copper Bolts, Copper Tube, Copper Modulator

    -- Journeyman
    { key = "journeyman-curiosities", tier = 2, label = "Journeyman Curiosities", id = 248689,
      words = { "journeyman", "curiosities" }, favor = 10, silver = 500,
      bundles = { { 11083, 20 }, { 11082, 4 }, { 11138, 6 }, { 11139, 2 } } },
      -- Soul Dust, Greater Astral Essence, Small and Large Glowing Shard
    { key = "journeyman-herbs", tier = 2, label = "Journeyman Herbs", id = 248686,
      words = { "journeyman", "herbs" }, favor = 10, silver = 500,
      bundles = { { 3820, 10 }, { 2453, 10 }, { 3355, 10 }, { 3369, 10 }, { 3356, 10 } } },
      -- Stranglekelp, Bruiseweed, Wild Steelbloom, Grave Moss, Kingsblood
    { key = "journeyman-ore", tier = 2, label = "Journeyman Ore", id = 248687,
      words = { "journeyman", "ore" }, favor = 10, silver = 500,
      bundles = { { 2772, 20 }, { 2775, 10 } } },
      -- Iron Ore, Silver Ore
    { key = "journeyman-textiles", tier = 2, label = "Journeyman Textiles", id = 248688,
      words = { "journeyman", "textiles" }, favor = 10, silver = 500,
      bundles = { { 2592, 20 }, { 4306, 40 }, { 2319, 20 } } },
      -- Wool Cloth, Silk Cloth, Medium Leather
    { key = "journeyman-fabrics", tier = 2, label = "Journeyman Fabrics", id = 248705,
      words = { "journeyman", "fabrics" }, favor = 20, silver = 1000,
      bundles = { { 2997, 6 }, { 4305, 10 }, { 4233, 2 } } },
      -- Bolt of Woolen Cloth, Bolt of Silk Cloth, Cured Medium Hide
    { key = "journeyman-ingots", tier = 2, label = "Journeyman Ingots", id = 248706,
      words = { "journeyman", "ingots" }, favor = 20, silver = 1000,
      bundles = { { 2842, 10 }, { 3575, 20 } } },
      -- Silver Bar, Iron Bar
    { key = "journeyman-parts", tier = 2, label = "Journeyman Parts", id = 248707,
      words = { "journeyman", "parts" }, favor = 20, silver = 1000,
      bundles = { { 4371, 8 }, { 4375, 7 }, { 4382, 4 }, { 10558, 45 } } },
      -- Bronze Tube, Whirring Bronze Gizmo, Bronze Framework, Gold Power Core

    -- Expert
    { key = "expert-curiosities", tier = 3, label = "Expert Curiosities", id = 248694,
      words = { "expert", "curiosities" }, favor = 15, silver = 750,
      bundles = { { 11137, 20 }, { 11135, 4 }, { 11177, 6 }, { 11178, 2 } } },
      -- Vision Dust, Greater Mystic Essence, Small and Large Radiant Shard
    { key = "expert-earthly", tier = 3, label = "Expert Earthly Herbs", id = 248690,
      words = { "expert", "earthly" }, favor = 15, silver = 750,
      bundles = { { 3357, 20 }, { 3818, 10 }, { 3821, 10 }, { 3358, 10 } } },
      -- Liferoot, Fadeleaf, Goldthorn, Khadgar's Whisker
    { key = "expert-flowering", tier = 3, label = "Expert Flowering Herbs", id = 248691,
      words = { "expert", "flowering" }, favor = 15, silver = 750,
      bundles = { { 3819, 10 }, { 4625, 10 }, { 8831, 20 }, { 8836, 10 } } },
      -- Wintersbite, Firebloom, Purple Lotus, Arthas' Tears
    { key = "expert-ore", tier = 3, label = "Expert Ore", id = 248692,
      words = { "expert", "ore" }, favor = 15, silver = 750,
      bundles = { { 2776, 10 }, { 3858, 20 } } },
      -- Gold Ore, Mithril Ore
    { key = "expert-textiles", tier = 3, label = "Expert Textiles", id = 248693,
      words = { "expert", "textiles" }, favor = 15, silver = 750,
      bundles = { { 4338, 40 }, { 4234, 20 } } },
      -- Mageweave Cloth, Heavy Leather
    { key = "expert-fabrics", tier = 3, label = "Expert Fabrics", id = 248708,
      words = { "expert", "fabrics" }, favor = 30, silver = 1500,
      bundles = { { 4339, 8 }, { 4236, 2 } } },
      -- Bolt of Mageweave, Cured Heavy Hide
    { key = "expert-ingots", tier = 3, label = "Expert Ingots", id = 248709,
      words = { "expert", "ingots" }, favor = 30, silver = 1500,
      bundles = { { 3860, 20 }, { 3859, 15 }, { 3577, 10 } } },
      -- Mithril Bar, Steel Bar, Gold Bar
    { key = "expert-parts", tier = 3, label = "Expert Parts", id = 248710,
      words = { "expert", "parts" }, favor = 30, silver = 1500,
      bundles = { { 4387, 8 }, { 10559, 5 }, { 10560, 12 }, { 10561, 5 } } },
      -- Iron Strut, Mithril Tube, Unstable Trigger, Mithril Casing

    -- Artisan: not in the game yet. The bundles are what players expect;
    -- the rewards are left out until a turn-in is seen.
    { key = "artisan-curiosities", tier = 4, label = "Artisan Curiosities", id = 248699,
      words = { "artisan", "curiosities" },
      bundles = { { 11176, 20 }, { 11175, 4 }, { 14343, 6 }, { 14344, 2 } } },
      -- Dream Dust, Greater Nether Essence, Small and Large Brilliant Shard
    { key = "artisan-earthly", tier = 4, label = "Artisan Earthly Herbs", id = 248695,
      words = { "artisan", "earthly" },
      bundles = { { 8839, 10 }, { 8845, 10 }, { 8846, 10 }, { 13464, 10 } } },
      -- Blindweed, Ghost Mushroom, Gromsblood, Golden Sansam
    { key = "artisan-flowering", tier = 4, label = "Artisan Flowering Herbs", id = 248696,
      words = { "artisan", "flowering" },
      bundles = { { 13465, 20 }, { 13466, 20 }, { 13467, 20 }, { 13463, 20 } } },
      -- Mountain Silversage, Plaguebloom, Icecap, Dreamfoil
    { key = "artisan-ore", tier = 4, label = "Artisan Ore", id = 248697,
      words = { "artisan", "ore" },
      bundles = { { 10620, 20 }, { 11370, 20 } } },
      -- Thorium Ore, Dark Iron Ore
    { key = "artisan-textiles", tier = 4, label = "Artisan Textiles", id = 248698,
      words = { "artisan", "textiles" },
      bundles = { { 14047, 40 }, { 8170, 20 } } },
      -- Runecloth, Rugged Leather
    { key = "artisan-fabrics", tier = 4, label = "Artisan Fabrics", id = 248711,
      words = { "artisan", "fabrics" },
      bundles = { { 14048, 8 }, { 8172, 2 } } },
      -- Bolt of Runecloth, Cured Thick Hide
    { key = "artisan-ingots", tier = 4, label = "Artisan Ingots", id = 248712,
      words = { "artisan", "ingots" },
      bundles = { { 12359, 20 }, { 11371, 2 } } },
      -- Thorium Bar, Dark Iron Bar
    { key = "artisan-parts", tier = 4, label = "Artisan Parts", id = 248713,
      words = { "artisan", "parts" },
      bundles = { { 15994, 5 }, { 16000, 5 } } },
      -- Thorium Widget, Thorium Tube
}

-- Forever's new items sit in one stretch of item IDs. A crate whose ID is
-- not typed above is looked for in it by name.
ns.WAYLAID_CRATE_ID_RANGE = { 248540, 248800 }
