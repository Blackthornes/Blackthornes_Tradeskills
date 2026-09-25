-- What goes beside a recipe's name in Blizzard's own profession window, and
-- which recipe a row in that window is showing.
--
-- None of the frame plumbing can be measured outside the game; what can be
-- measured here is the part that decides what a row says. Three things in it
-- cost real gold or real confusion if they are wrong:
--
--   1. A recipe with no price data must print *nothing*. A zero beside a name
--      reads as "this sells for nothing", which is a claim about the market
--      and not the same statement as "nobody has scanned this yet".
--   2. A row must never show another recipe's price. The fallback that reads
--      the row's text has to refuse a name two recipes share rather than pick
--      one of them.
--   3. A row hands its recipe over in several different shapes depending on
--      which list this client builds, and every shape has to be read.

local ns = {}
ns.NewModule = function(name) local m = {}; ns[name] = m; return m end
ns.Theme, ns.Widgets = {}, {}

-- Money formatting is not under test here, so it is a stub that says plainly
-- what it was handed: this suite is about *whether* a value appears and which
-- one, not how it is spelled.
ns.Util = {
  FormatMoney = function(copper) return ("<%d>"):format(copper) end,
}

local RecipeValue
do
  local realNew = ns.NewModule
  ns.NewModule = function(name) local m = realNew(name); RecipeValue = m; return m end
  local chunk = assert(loadfile(lfs_cwd .. "/UI/RecipeValue.lua"))
  chunk("Blackthornes_TS", ns)
  ns.NewModule = realNew
end

--------------------------------------------------------------------------------
-- The world the rows are read against
--------------------------------------------------------------------------------

local RECIPES = {
  [101] = { recipeID = 101, name = "Copper Chain Belt",      outputItemID = 2853 },
  [102] = { recipeID = 102, name = "Rough Sharpening Stone", outputItemID = 2862 },
  [103] = { recipeID = 103, name = "Brown Linen Shirt",      outputItemID = 2575 },

  -- Two recipes, one name. Classic is full of these -- the same item taught by
  -- two trainers, or a rank the client shows under one heading.
  [104] = { recipeID = 104, name = "Linen Bandage",          outputItemID = 1251 },
  [105] = { recipeID = 105, name = "Linen Bandage",          outputItemID = 1251 },

  -- Makes nothing sellable: a skill-up craft with no item behind it.
  [106] = { recipeID = 106, name = "Smelt Copper" },
}

local PRICES = {
  [2853] = 12000,   -- Copper Chain Belt
  [2862] = 500,     -- Rough Sharpening Stone
  [1251] = 900,     -- Linen Bandage
  [2575] = 0,       -- scanned, nothing was listed
}

ns.Recipes = {
  GetAll = function() return RECIPES end,
  GetAny = function(_, recipeID) return RECIPES[recipeID] end,
  Count = function() local n = 0; for _ in pairs(RECIPES) do n = n + 1 end; return n end,
}

ns.Prices = {
  GetValue = function(_, itemID, which)
    assert(which == "market", "the profession window shows market value, got " .. tostring(which))
    return PRICES[itemID]
  end,
}

ns.Config = { Get = function(_, key) return ns.settings and ns.settings[key] end }
ns.settings = {}

--------------------------------------------------------------------------------
-- Rows, in the shapes a client might hand them over
--------------------------------------------------------------------------------

--- A fake FontString: enough of one to be recognised and read.
local function FontString(text)
  return {
    GetText = function(self) return self.text end,
    GetStringWidth = function(self) return #(self.text or "") * 6 end,
    GetLeft = function() return 20 end,
    text = text,
  }
end

--- A row whose name is a field, the way a template with a parentKey gives it.
local function NamedRow(text, extra)
  local row = extra or {}
  row.Text = FontString(text)
  return row
end

local function check(label, got, want)
  if got ~= want then
    error(("%s: expected %s, got %s"):format(label, tostring(want), tostring(got)), 2)
  end
end

--------------------------------------------------------------------------------
-- What a recipe is worth
--------------------------------------------------------------------------------

check("a priced craft is valued", RecipeValue:ValueFor(101), 12000)
check("and formatted", RecipeValue:TextFor(101), "<12000>")

-- The rule this file exists for. Each of these is a different unknown and all
-- three have to print nothing rather than a zero.
check("unknown recipe says nothing", RecipeValue:TextFor(999), nil)
check("a craft with no sellable item says nothing", RecipeValue:TextFor(106), nil)
check("a scanned-but-unsold item says nothing", RecipeValue:TextFor(103), nil)

-- ...and nothing is not the string "0", which is what a naive `or 0` produces
-- and what would be read as a price.
assert(RecipeValue:TextFor(103) ~= "<0>", "an unsold item must not print as zero")

--------------------------------------------------------------------------------
-- Which recipe a row is showing
--------------------------------------------------------------------------------

-- The shapes a list has been seen to use, all of which have to be read.
check("recipeID on the row", RecipeValue:RecipeForRow({ recipeInfo = { recipeID = 102 } }), 102)

check("recipeID on element data",
  RecipeValue:RecipeForRow({ elementData = { recipeInfo = { recipeID = 102 } } }), 102)

check("recipeID behind GetElementData",
  RecipeValue:RecipeForRow({
    GetElementData = function() return { recipeInfo = { recipeID = 101 } } end,
  }), 101)

check("recipeID behind a tree node's GetData",
  RecipeValue:RecipeForRow({
    GetElementData = function()
      return { GetData = function() return { recipeInfo = { recipeID = 103 } } end }
    end,
  }), 103)

-- The fallback, for a list that hands its rows nothing but text.
check("matched by name", RecipeValue:RecipeForRow(NamedRow("Copper Chain Belt")), 101)

check("matched despite the client's decoration",
  RecipeValue:RecipeForRow(NamedRow("|cffffffffRough Sharpening Stone|r [3]")), 102)

-- Rule 2: a shared name is refused. Showing 104's price on 105's row would be
-- a wrong number presented as a right one.
check("a name two recipes share matches neither",
  RecipeValue:RecipeForRow(NamedRow("Linen Bandage")), nil)

check("a name nothing owns matches nothing",
  RecipeValue:RecipeForRow(NamedRow("Sharpened Reputation")), nil)

-- Data beats text: a row that says which recipe it is, is believed over what
-- it happens to be rendering.
check("data wins over the name",
  RecipeValue:RecipeForRow(NamedRow("Copper Chain Belt", { recipeInfo = { recipeID = 102 } })), 102)

--------------------------------------------------------------------------------
-- Judging a candidate list
--------------------------------------------------------------------------------

-- How the real thing tells the recipe list apart from the other six frames
-- under the profession window that also have children.
check("a list of recipe rows counts", RecipeValue:CountRecipes({
  NamedRow("Copper Chain Belt"),
  NamedRow("Rough Sharpening Stone"),
  NamedRow("Brown Linen Shirt"),
}), 3)

check("a frame full of buttons counts nothing", RecipeValue:CountRecipes({
  NamedRow("Create"),
  NamedRow("Close"),
  {},
}), 0)

--------------------------------------------------------------------------------
-- The setting
--------------------------------------------------------------------------------

check("on by default", RecipeValue:IsEnabled(), true)

ns.settings.showValueInProfessionWindow = false
check("off when switched off", RecipeValue:IsEnabled(), false)

ns.settings.showValueInProfessionWindow = true
check("on when switched on", RecipeValue:IsEnabled(), true)

--------------------------------------------------------------------------------
-- The name index follows the recipe cache
--------------------------------------------------------------------------------

-- The cache fills as the client hands recipes over. An index built once at the
-- first refresh would leave every recipe learned afterwards blank for the rest
-- of the session, and that is a whole profession window of nothing on the
-- first open, which is exactly when someone looks.
RECIPES[107] = { recipeID = 107, name = "Runed Copper Rod", outputItemID = 6218 }
PRICES[6218] = 3000

check("a recipe added after the first read is matched",
  RecipeValue:RecipeForRow(NamedRow("Runed Copper Rod")), 107)

print("test_recipevalue: ok")
