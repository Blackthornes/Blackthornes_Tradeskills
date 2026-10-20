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

--------------------------------------------------------------------------------
-- Where the value lands on the row
--------------------------------------------------------------------------------

-- a screenshot of 2026-09-21 showed the price printed across the end of
-- the name on two kinds of row:
--
--   "Bolt of Woolen Cloth [5]5s 56c"       -- the count is a second region
--   "Double-stitched Woolen Shoulder6s 82c" -- the name reaches the edge
--
-- The first version measured the name region alone and anchored the value to
-- it, so anything else the row was drawing was invisible to it. These checks
-- reproduce both rows out of plain tables and fail against that version.

RECIPES[201] = { recipeID = 201, name = "Bolt of Woolen Cloth",   outputItemID = 2997 }
RECIPES[202] = { recipeID = 202, name = "Double-stitched Woolen Shoulders", outputItemID = 2998 }
RECIPES[203] = { recipeID = 203, name = "Linen Bag",              outputItemID = 2999 }
RECIPES[204] = { recipeID = 204, name = "Double-stitched Woolen Shoulders of the Long Winter Night", outputItemID = 2998 }

PRICES[2997] = 55600
PRICES[2998] = 68200
PRICES[2999] = 400

local ROW_LEFT, ROW_RIGHT = 0, 230
local CHAR = 6

--- A font string that knows where it is, and remembers what was done to it.
local function Region(text, left, opts)
  opts = opts or {}

  return {
    text = text,
    left = left,
    width = nil,
    wrap = opts.wrap,
    shown = opts.shown ~= false,
    justify = opts.justify,

    GetText = function(self) return self.text end,
    size = 12,
    maxLines = 1,
    GetStringWidth = function(self) return #(self.text or "") * CHAR * self.size / 12 end,
    GetFont = function(self) return "Fonts\\FRIZQT__.TTF", self.size, "" end,
    SetFont = function(self, _, size) self.size = size end,
    GetMaxLines = function(self) return self.maxLines end,
    SetMaxLines = function(self, n) self.maxLines = n end,
    GetLeft = function(self) return self.left end,
    GetRight = function(self) return ROW_RIGHT end,
    GetJustifyH = function(self) return self.justify end,
    IsShown = function(self) return self.shown end,
    SetWidth = function(self, w) self.width = w end,
    SetWordWrap = function(self, w) self.wrap = w end,
    GetWordWrap = function(self) return self.wrap == true end,
  }
end

--- A row that can be decorated, and a label that records where it was put.
local function Row(name, opts)
  opts = opts or {}

  local row = {}
  row.Text = Region(name, opts.nameLeft or 20, opts)

  local extras = {}
  if opts.count then
    extras[#extras + 1] = Region(opts.count, opts.countLeft or 148, opts)
  end

  row.GetLeft = function() return ROW_LEFT end
  row.GetRight = function() return ROW_RIGHT end
  row.IsShown = function() return true end

  -- Written out rather than folded into one `and`/`or` expression: that
  -- shape is what hid a live self-undercutting bug in Logic/Profit.lua, and
  -- an empty `extras` is exactly the falsy middle it gets wrong.
  local unpack_ = unpack or table.unpack

  row.GetRegions = function(self)
    local all = { row.Text }

    if row.label then all[#all + 1] = row.label end

    for i = 1, #extras do all[#all + 1] = extras[i] end

    return unpack_(all)
  end

  row.CreateFontString = function(self)
    local label = Region("", 0)

    label.points = {}
    label.visible = false
    label.ClearAllPoints = function(self) self.points = {} end
    label.SetPoint = function(self, point, rel, relPoint, x, y)
      self.points[#self.points + 1] = { point = point, x = x }
    end

    -- A label that knows where it was put. Without this the fake cannot
    -- reproduce the worst failure available here: a label that measures
    -- itself steps to the right of where it already is, every refresh, and
    -- walks off the end of the list within a second or two.
    label.GetLeft = function(self)
      local point = self.points[1]

      if point and point.point == "LEFT" then return ROW_LEFT + point.x end

      return ROW_RIGHT - RecipeValue.RIGHT_INSET - #(self.text or "") * CHAR
    end
    label.SetJustifyH = function(self, j) self.justify = j end
    label.SetText = function(self, t) self.text = t end
    label.Show = function(self) self.visible = true end
    label.Hide = function(self) self.visible = false end

    row.label = label
    return label
  end

  return row
end

local function Placement(row)
  local point = row.label and row.label.points[1]
  return point and point.point, point and point.x
end

-- Row 1: a name with a separate "[5]" beside it, the shape that broke.
do
  local row = Row("Bolt of Woolen Cloth", { count = "[5]" })
  local outcome, placement = RecipeValue:DecorateRow(row)

  check("a counted recipe is still valued", outcome, "valued")
  check("and its value sits in the right-hand column", placement, "column")

  local point, x = Placement(row)
  check("anchored to the row's right edge", point, "RIGHT")
  check("at the same inset as every other row", x, -RecipeValue.RIGHT_INSET)
  check("right-justified, so the coins line up", row.label.justify, "RIGHT")

  -- The count region runs from 148 to 166. A value starting at or left of
  -- 166 would be printed over the "[5]".
  local countRight = 148 + #"[5]" * CHAR
  local valueLeft = ROW_RIGHT - RecipeValue.RIGHT_INSET - #row.label.text * CHAR

  check("the value clears the count, not just the name",
    valueLeft >= countRight + RecipeValue.NAME_GAP, true)
  check("and the name keeps its full width", row.Text.width, nil)
end

-- Row 1b: a short name and a long one put their values at the same edge.
do
  local short = Row("Linen Bag")
  local long = Row("Bolt of Woolen Cloth", { count = "[5]" })
  RecipeValue:DecorateRow(short)
  RecipeValue:DecorateRow(long)

  local p1, x1 = Placement(short)
  local p2, x2 = Placement(long)
  check("short and long names share one value column", p1 .. x1, p2 .. x2)
end

-- Row 2: the label must not measure itself. Left in, it would step right by
-- its own width every refresh until it walked off the end of the list.
do
  local row = Row("Bolt of Woolen Cloth", { count = "[5]" })

  RecipeValue:DecorateRow(row)
  local _, first = Placement(row)

  RecipeValue:DecorateRow(row)
  local _, second = Placement(row)

  RecipeValue:DecorateRow(row)
  local _, third = Placement(row)

  check("a second pass puts the value in the same place", second, first)
  check("and so does a third", third, first)
end

-- Row 3: a name long enough to reach the right edge. There is no room beside
-- it, so the name gives way rather than the two being drawn over each other.
do
  local row = Row("Double-stitched Woolen Shoulders")
  local _, placement = RecipeValue:DecorateRow(row)

  check("a name that reaches the edge makes room", placement, "shortened")

  local point = Placement(row)
  check("the value goes to the right edge", point, "RIGHT")
  check("the name was given a width", type(row.Text.width), "number")
  check("the name wraps rather than ending in ...", row.Text.wrap, true)
  check("onto as many lines as it needs", row.Text.maxLines, 0)
  check("at its usual size while two lines hold it", row.Text.size, 12)

  -- It has to stop short of the value, with the gap between them.
  local valueWidth = #row.label.text * CHAR
  local valueLeft = ROW_RIGHT - RecipeValue.RIGHT_INSET - valueWidth

  check("and stops short of the value",
    row.Text.left + row.Text.width <= valueLeft - RecipeValue.NAME_GAP + 0.5, true)

  check("but is never squeezed to nothing",
    row.Text.width >= RecipeValue.MIN_NAME_WIDTH, true)
end

-- Row 3b: a name too long for two lines steps down a size, and gets its
-- own size, wrap and lines back when the row is reused for a short name.
do
  local row = Row("Double-stitched Woolen Shoulders of the Long Winter Night")
  RecipeValue:DecorateRow(row)

  check("a very long name steps down a size", row.Text.size < 12, true)
  check("but only a step or two", row.Text.size >= 10, true)

  row.Text.text = "Linen Bag"
  RecipeValue:DecorateRow(row)
  check("its size comes back", row.Text.size, 12)
  check("it no longer wraps", row.Text.wrap == true, false)
  check("its lines come back", row.Text.maxLines, 1)
end

-- Row 4: rows are recycled. One that held a long name and now holds a short
-- one has to get its full width back, or it stays cut for no reason.
do
  local row = Row("Double-stitched Woolen Shoulders")
  RecipeValue:DecorateRow(row)
  check("narrowed while it was long", type(row.Text.width), "number")

  row.Text.text = "Linen Bag"
  local _, placement = RecipeValue:DecorateRow(row)

  check("the short name fits beside its value", placement, "column")
  check("and the width was handed back", row.Text.width, 0)
end

-- Row 5: a recipe with no price data shows nothing, and takes nothing from
-- the name in exchange for it.
do
  local row = Row("Double-stitched Woolen Shoulders")
  RecipeValue:DecorateRow(row)
  check("narrowed while it had a value", type(row.Text.width), "number")

  PRICES[2998] = nil
  local outcome = RecipeValue:DecorateRow(row)
  PRICES[2998] = 68200

  check("an unpriced recipe says nothing", outcome, "unpriced")
  check("its label is hidden", row.label.visible, false)
  check("and the name has its width back", row.Text.width, 0)
end

-- Row 6: a region with nothing showing takes up no space, so it must not
-- push the value across the row.
do
  local visible = Row("Linen Bag")
  RecipeValue:DecorateRow(visible)
  local _, without = Placement(visible)

  local hidden = Row("Linen Bag", { count = "[10]", countLeft = 200 })
  hidden.GetRegions = function(self)
    local extra = Region("[10]", 200, { shown = false })
    if self.label then return self.Text, self.label, extra end
    return self.Text, extra
  end

  RecipeValue:DecorateRow(hidden)
  local _, with = Placement(hidden)

  check("a hidden region is not measured", with, without)
end

-- Row 7: four times a second most rows are as they were, and placing a value
-- again makes the game lay the row out again. An unchanged row is left alone;
-- one whose text changed is placed again.
do
  local row = Row("Bolt of Woolen Cloth", { count = "[5]" })
  RecipeValue:DecorateRow(row)

  local placed = 0
  local setPoint = row.label.SetPoint
  row.label.SetPoint = function(...) placed = placed + 1; return setPoint(...) end

  local outcome, placement = RecipeValue:DecorateRow(row)
  check("an unchanged row is not placed again", placed, 0)
  check("and still reports its value and place", outcome .. " " .. placement, "valued column")

  row.Text.text = "Bolt of Woolen Cloth [12]"
  RecipeValue:DecorateRow(row)
  check("a row whose text changed is placed again", placed, 1)
end

-- The measurement itself, for the justifications a client might use.
do
  local left = Region("Copper Chain Belt", 20)
  check("left-justified text ends where it stops",
    RecipeValue._TextRight(left), 20 + #"Copper Chain Belt" * CHAR)

  local right = Region("12s", 20, { justify = "RIGHT" })
  check("right-justified text ends at its region's edge",
    RecipeValue._TextRight(right), ROW_RIGHT)
end

print("test_recipevalue: ok")
