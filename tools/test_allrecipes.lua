-- UI/AllRecipesView.lua and UI/StockBox.lua outside WoW: the Profit tab's
-- All Recipes view and the Keep in Stock box.
--
--   1. Every known recipe is listed: priced, losing, unpriced, grey, an
--      enchant and an ignored one (dimmed, its tick box not).
--   2. Hide Ignored, Hide Grey, the profession and the search each narrow it,
--      and the foot line counts what is shown.
--   3. KEEP shows an item's own number with its x, else empty with the usual
--      number greyed; typing writes ns.Auctions:SetLimit, empty clears it,
--      and the x puts the usual one back. An enchant says No Item.
--   4. The IGNORE tick box calls ns.Profit:SetIgnored.
--   5. The box: its note names the profession's number or the usual one,
--      -/+ start from the usual number, Confirm writes, Use Usual clears,
--      and a craft that makes nothing opens nothing.

local ns = { db = {}, modules = {}, moduleOrder = {} }
function ns.NewModule(name) local m = {}; ns[name] = m; return m end

local function Stub(fields)
  local frame = fields or {}
  return setmetatable(frame, { __index = function(self, key)
    local noop = function() end
    rawset(self, key, noop)
    return noop
  end })
end

local function Label()
  return Stub({ text = "", shown = true, alpha = 1,
    SetText = function(self, v) self.text = tostring(v) end,
    SetShown = function(self, v) self.shown = v and true or false end,
    Show = function(self) self.shown = true end,
    Hide = function(self) self.shown = false end,
    IsShown = function(self) return self.shown end,
    SetAlpha = function(self, v) self.alpha = v end,
    SetTextColor = function(self, r) self.color = r end,
    GetStringHeight = function() return 14 end,
    GetWidth = function() return 66 end })
end

local function Frame()
  local f = Label()
  f.CreateFontString = function() return Label() end
  f.CreateTexture = function() return Label() end
  f.IsVisible = function() return true end
  f.HookScript = function(self, what, fn) rawset(self, "hook_" .. what, fn) end
  return f
end

local saved = { CreateFrame = CreateFrame, UIParent = UIParent, GameTooltip = GameTooltip,
  C_Timer = C_Timer, UISpecialFrames = UISpecialFrames }
CreateFrame = function() return Frame() end
UIParent = Frame()
GameTooltip = Stub({ lines = {} })
GameTooltip.AddLine = function(self, text) self.lines[#self.lines + 1] = text end
GameTooltip.SetText = function(self, text) self.lines = { text } end
C_Timer = { After = function() end }
UISpecialFrames = {}

ns.Theme = {
  CreateLabel = function() return Label() end,
  CreateItemIcon = function() return Label() end,
  SetItemIcon = function() end,
  SetRowName = function(label, text) label:SetText(text) end,
  SetMoneyText = function(label, copper) label:SetText(tostring(copper) .. "c") end,
  ProfitColor = function() return 1, 1, 1 end,
  Unpack = function(name) return name, 1, 1, 1 end,
  SetBorderColor = function(box, name) box.border = name end,
  CreateDivider = function() return Stub() end,
  Fill = function() end,
  Halo = function() end,
  AddGameOutline = function() end,
}

local buttons, boxes = {}, {}
local function NumberBox(_, opts)
  local box = Frame()
  box.opts = opts
  box.editBox = Frame()
  box.editBox.GetText = function(self) return self.text end
  box.editBox.HasFocus = function(self) return self.focus == true end
  box.SetPlaceholder = function(self, text) self.placeholder = text end
  box.SetValue = function(self, value, silent)
    value = tonumber(value)
    local changed = value ~= (self.current or nil)
    self.current = value or false
    self.editBox.text = value and tostring(value) or ""
    if changed and not silent and opts.onChange then opts.onChange(value) end
  end
  boxes[#boxes + 1] = box
  return box
end

local list
ns.Widgets = {
  SEARCH_WIDTH = 170,
  CreateNumberBox = NumberBox,
  CreateButton = function(_, text, onClick)
    local b = Frame(); b.onClick = onClick; buttons[#buttons + 1] = { text = text, button = b }; return b
  end,
  CreateCheckbox = function(_, text, onToggle, initial)
    local c = Frame(); c.label = text; c.onToggle = onToggle; c.checked = initial
    c.SetChecked = function(self, v) self.checked = v and true or false end
    c.Click = function(self) self.checked = not self.checked; self.onToggle(self.checked) end
    return c
  end,
  CreateDropdown = function(_, _, onPick)
    local d = Frame(); d.onPick = onPick
    d.SetOptions = function(self, o) self.options = o end
    d.SetValue = function(self, v) self.value = v end
    return d
  end,
  CreateSearchBox = function(_, _, onChange) local s = Frame(); s.onChange = onChange; return s end,
  CreateScrollList = function(_, opts)
    list = Frame()
    list.opts = opts
    list.SetData = function(self, d) self.data = d end
    return list
  end,
}
ns.Util = {
  GetItemQualityColor = function() return nil end,
  GetItemLabel = function(id) return "item" .. tostring(id) end,
}
ns.RegisterEvent = function() end
ns.Print = function() end
ns.SkillUp = { GetTierColor = function() return 1, 0.5, 0.25 end }
ns.Recipes = { Count = function() return 6 end, SKILL_LINE_PROFESSIONS = { [197] = "Tailoring", [171] = "Alchemy", [333] = "Enchanting" } }

local config = { maxPostedPerItem = 3 }
ns.Config = { Get = function(_, key) return config[key] end }

local limits = {}
ns.Auctions = {
  SetLimit = function(_, itemID, limit)
    limits[#limits + 1] = { itemID = itemID, limit = limit }
    ns.db.postLimits = ns.db.postLimits or {}
    ns.db.postLimits[itemID] = limit
  end,
  GetRoom = function(_, itemID)
    if itemID == 100 then return 1, 2, 1, 0, 4, 2 end
    return 0, 0, 0, 0, 3, 0
  end,
  ProfessionOf = function(_, itemID) return (itemID == 100 or itemID == 300) and "Tailoring" or "Alchemy" end,
  ProfessionLabel = function(_, name) return name end,
}

local ignored = { [6] = "Minor Healing Potion" }
local setIgnored = {}
ns.Profit = {
  GetMethod = function() return "best" end,
  IsIgnored = function(_, id) return ignored[id] ~= nil end,
  SetIgnored = function(_, id, on) setIgnored[#setIgnored + 1] = { id = id, on = on } end,
  GetRanked = function(_, opts)
    assert(opts.includeIgnored and opts.includeUnpriceable and opts.ignorePostLimit,
      "All Recipes asks for every recipe")
    assert(opts.minProfit == -math.huge, "money-losing recipes are kept")
    return {
      { recipeID = 1, name = "Runecloth Bag", outputItemID = 100, skillLineID = 197, priceable = true, profit = 84210,
        posted = 2, onHand = 1, inMail = 2, skillUp = { tier = "optimal" } },
      { recipeID = 2, name = "Major Healing Potion", outputItemID = 200, skillLineID = 171, priceable = true, profit = 10650,
        posted = 5, onHand = 12, inMail = 0, skillUp = { tier = "medium" } },
      { recipeID = 3, name = "Bolt of Silk Cloth", outputItemID = 300, skillLineID = 197, priceable = true, profit = -1240,
        posted = 0, onHand = 14, inMail = 0, skillUp = { tier = "trivial" } },
      { recipeID = 4, name = "Elixir of Fortitude", outputItemID = 400, skillLineID = 171, priceable = false,
        posted = 0, onHand = 0, inMail = 0, skillUp = { tier = "trivial" } },
      { recipeID = 5, name = "Enchant Bracer - Minor Health", skillLineID = 333, priceable = false },
      { recipeID = 6, name = "Minor Healing Potion", outputItemID = 600, skillLineID = 171, priceable = true, profit = -35,
        posted = 0, onHand = 0, inMail = 0, skillUp = { tier = "trivial" } },
    }
  end,
}

ns.db.postLimits = { [100] = 4 }
ns.db.professionStockLimits = { Tailoring = 5 }

assert(loadfile(lfs_cwd .. "/UI/StockBox.lua"))("Blackthornes_TS", ns)
assert(loadfile(lfs_cwd .. "/UI/AllRecipesView.lua"))("Blackthornes_TS", ns)
local View, Box = ns.AllRecipesView, ns.StockBox

local passed = 0
local function check(cond, what)
  assert(cond, what)
  passed = passed + 1
end

View.Build(Frame())
local state, widgets = View._state, View._widgets
check(list ~= nil and list.opts.menu ~= nil, "the list is built with the row menu")

-- 1. Every recipe.
View.Refresh()
check(#list.data == 6, "every known recipe is listed")
check(widgets.countLabel.text == "6 recipes. 1 ignored. Click a heading to sort.", "foot line: " .. widgets.countLabel.text)
local opts = widgets.professionDropdown.options
check(#opts == 4 and opts[1].value == nil and opts[2].value == "Alchemy", "professions by name, A to Z")

local function Draw(analysis)
  local row = Frame()
  list.opts.createRow(row)
  row.data = analysis
  list.opts.updateRow(row, analysis)
  return row
end
local byID = {}
for _, a in ipairs(list.data) do byID[a.recipeID] = a end

local bag = Draw(byID[1])
check(bag.cells.listed.text == "2" and bag.cells.have.text == "3", "LISTED is posted; HAVE is bags plus mail")
check(bag.cells.profession.text == "Tailoring", "PROFESSION names it")
check(bag.cells.profit.text == "84210c", "PROFIT as money")
check(bag.dot.shown, "the skill-up dot shows")
check(bag.ignore.checked == false and bag.name.alpha == 1, "a kept recipe is not dimmed")

local unpriced = Draw(byID[4])
check(unpriced.cells.profit.text == "No Price", "an unpriced craft says No Price")

local enchant = Draw(byID[5])
check(enchant.cells.keep.text == "No Item" and not enchant.keep.shown, "an enchant's KEEP says No Item")
check(enchant.cells.listed.text == "-" and enchant.cells.have.text == "-", "an enchant holds nothing")
check(enchant.cells.profit.text == "No Price", "an enchant has No Price")

local minor = Draw(byID[6])
check(minor.ignore.checked == true, "an ignored recipe is ticked")
check(minor.name.alpha < 1 and minor.cells.profit.alpha < 1, "an ignored recipe is dimmed")
check(minor.ignore.alpha == 1, "its tick box is not")

-- 2. Filters.
state.hideIgnored = true; View.Refresh()
check(#list.data == 5, "Hide Ignored leaves the ignored one out")
state.hideGrey = true; View.Refresh()
check(#list.data == 3, "Hide Grey leaves grey ones out")
check(widgets.countLabel.text == "3 recipes. 0 ignored. Click a heading to sort.", "the foot counts what shows")
state.hideIgnored, state.hideGrey = false, false
state.profession = "Tailoring"; View.Refresh()
check(#list.data == 2, "the profession picks its recipes")
state.profession = nil
state.search = "potion"; View.Refresh()
check(#list.data == 2, "search matches names")
state.search = "zzz"; View.Refresh()
check(widgets.emptyLabel.shown and widgets.emptyLabel.text:find("zzz", 1, true), "a search with no match says so")
state.search = ""; View.Refresh()

-- 3. KEEP.
check(bag.keep.current == 4 and bag.keepClear.shown, "an own number shows, with its x")
check(bag.keep.editBox.color == "accentHi", "an own number is gold")
local potion = Draw(byID[2])
check(potion.keep.current == false and potion.keep.placeholder == "3", "no own number: the usual one greyed")
check(not potion.keepClear.shown, "no x without an own number")
local silk = Draw(byID[3])
check(silk.keep.placeholder == "5", "a profession's number shows when it has one")

potion.keep:SetValue(20)
check(limits[#limits].itemID == 200 and limits[#limits].limit == 20, "typing writes SetLimit")
potion.keep:SetValue(nil)
check(limits[#limits].itemID == 200 and limits[#limits].limit == nil, "empty clears it")
local before = #limits
list.opts.updateRow(potion, byID[2])
check(#limits == before, "a redraw writes nothing")
bag.keepClear.onClick()
check(limits[#limits].itemID == 100 and limits[#limits].limit == nil, "the x puts the usual number back")
ns.db.postLimits[100] = 4

potion.keep.editBox.focus = true
potion.keep.editBox.text = "1"
ns.db.postLimits[200] = 9
list.opts.updateRow(potion, byID[2])
check(potion.keep.editBox.text == "1", "a number being typed is left alone")
potion.keep.editBox.focus = false
ns.db.postLimits[200] = nil

potion.keep.hook_OnEnter(potion.keep)
check(GameTooltip.lines[1] == "Keep in Stock", "the KEEP tip has its title")
check(GameTooltip.lines[2]:find("Settings", 1, true), "it says where the number comes from")
check(GameTooltip.lines[3] == "Enter saves. Esc puts it back.", "and how to save")

-- 4. IGNORE.
potion.ignore:Click()
check(setIgnored[1].id == 2 and setIgnored[1].on == true, "the tick box ignores the recipe")
minor.ignore:Click()
check(setIgnored[2].id == 6 and setIgnored[2].on == false, "unticking brings it back")

-- Sorting values.
check(View.KeepValue(byID[1]) == 4 and View.KeepValue(byID[2]) == 3 and View.KeepValue(byID[5]) == nil,
  "KEEP sorts by the number shown")

-- 5. The box.
check(Box.Note(100) == "You have 3. Tailoring in Settings keeps 5. Empty uses that again.", "note: " .. Box.Note(100))
check(Box.Note(200) == "You have 0. The usual amount is 3. Empty uses that again.", "note: " .. Box.Note(200))
check(Box:Open(nil, "Enchant") == false, "a craft that makes nothing opens no box")
check(Box:Open(200, "Major Healing Potion") == true and Box:IsShown(), "the box opens")
check(Box.title.text == "Keep in stock: Major Healing Potion", "its title line")
check(Box.box.current == false and Box.box.placeholder == "3", "empty, with the usual number greyed")
Box:Step(1)
check(Box.box.current == 4, "+ starts from the usual number")
Box:Step(-1); Box:Step(-1)
check(Box.box.current == 2, "- takes one off")
Box:Save()
check(limits[#limits].itemID == 200 and limits[#limits].limit == 2 and not Box:IsShown(), "Confirm writes and closes")
Box:Open(200, "Major Healing Potion")
check(Box.box.current == 2, "it opens on the item's own number")
Box:UseUsual()
check(limits[#limits].itemID == 200 and limits[#limits].limit == nil and not Box:IsShown(), "Use Usual clears it")
local words = {}
for _, b in ipairs(buttons) do words[b.text] = true end
check(words["Confirm"] and words["Use Usual"] and words["-"] and words["+"], "its buttons")

-- 6. The profession picked on My Crafts or Recipes to Learn carries over
--    (a player's ask, 2026-11-27), with the real Logic/Profit.lua pick.
do
  local side = { modules = {}, moduleOrder = {}, Util = {}, Recipes = ns.Recipes,
    RegisterCommand = function() end, Config = { Get = function() end } }
  function side.NewModule(name) local m = {}; side[name] = m; return m end
  assert(loadfile(lfs_cwd .. "/Logic/Profit.lua"))("Blackthornes_TS", side)
  ns.Profit.PickProfession = side.Profit.PickProfession
  ns.Profit.PickedProfession = side.Profit.PickedProfession
  ns.Profit.ProfessionOfLine = side.Profit.ProfessionOfLine

  state.profession = nil
  side.Profit.PickProfession("Alchemy"); View.Refresh()
  check(state.profession == "Alchemy" and #list.data == 3, "a profession picked elsewhere carries over")
  check(widgets.professionDropdown.value == "Alchemy", "and shows on the drop-down")
  side.Profit.PickProfession("Cooking"); View.Refresh()
  check(state.profession == nil and #list.data == 6, "one with no recipes here shows them all")
  side.Profit.PickProfession("Tailoring"); View.Refresh()
  side.Profit.PickProfession(false); View.Refresh()
  check(state.profession == nil, "All professions carries over too")

  widgets.professionDropdown.onPick("Tailoring")
  local _, english = side.Profit.PickedProfession()
  check(english == "Tailoring", "a pick here is shared")
  state.profession = nil; View.Refresh()
  check(state.profession == nil, "and taken only once")
  widgets.professionDropdown.onPick(nil)
  check(select(2, side.Profit.PickedProfession()) == false, "All professions here is shared")
end

for name, value in pairs(saved) do _G[name] = value end
for name in pairs({ CreateFrame = 1, UIParent = 1, GameTooltip = 1, C_Timer = 1, UISpecialFrames = 1 }) do
  if saved[name] == nil then _G[name] = nil end
end
print(("test_allrecipes: %d checks passed"):format(passed))
