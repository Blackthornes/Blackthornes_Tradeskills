-- Recipes to Learn: a click on SKILL sorts by skill on a narrow list.
--
-- A player clicked SKILL on the Profit tab's Recipes to Learn (2026-11-18)
-- and the list came out by the recipe's price instead, with the arrow by a
-- hidden heading. On a list too narrow for every column, some headings step
-- aside (UI/RecipeBookView.lua's SQUEEZE_ORDER); the click must never land on
-- one of those, and the list must sort by the heading that was clicked.
--
--   1. Headings set aside on a narrow list take no clicks.
--   2. Clicking SKILL sorts by skill, biggest first, then smallest first.
--   3. Widening the list brings the headings back, clickable again.
--   4. A column the player turned off takes no clicks, even on a wide list
--      where nothing steps aside.

local function noop() end

-- The game works out a frame's size when something first asks for one, and
-- runs OnSizeChanged right then. Asking a heading its width while the sort
-- arrows are still being made laid the headings out before the view had
-- its sorter (2026-11-18). The fake does the same: the first width asked
-- after a frame gets OnSizeChanged sizes that frame to `layoutWidth`.
local layoutWidth, unsized = nil, nil

local function NewFrame(parent)
  local f = { scripts = {}, shown = true, text = "", parent = parent, width = 0, points = {} }
  setmetatable(f, { __index = function(_, k)
    if type(k) == "string" and k:match("^%u") then return noop end
  end })
  f.SetScript = function(self, n, fn)
    self.scripts[n] = fn
    if n == "OnSizeChanged" and layoutWidth then unsized = self end
  end
  f.HookScript = function(self, n, fn)
    local old = self.scripts[n]
    self.scripts[n] = function(...) if old then old(...) end fn(...) end
  end
  f.GetScript = function(self, n) return self.scripts[n] end
  f.Show = function(self) self.shown = true end
  f.Hide = function(self) self.shown = false end
  f.SetShown = function(self, v) self.shown = v and true or false end
  f.IsShown = function(self) return self.shown end
  f.SetText = function(self, t) self.text = tostring(t) end
  f.GetText = function(self) return self.text end
  f.GetParent = function(self) return self.parent end
  f.SetWidth = function(self, w) self.width = w end
  f.GetWidth = function(self)
    local frame = unsized
    if frame then
      unsized = nil
      frame.width = layoutWidth
      frame.scripts.OnSizeChanged(frame, layoutWidth, 16)
    end
    return self.width
  end
  f.SetPoint = function(self, point, rel, relPoint, x, y)
    self.points[point] = { rel, relPoint, x, y }
  end
  f.ClearAllPoints = function(self) self.points = {} end
  f.GetStringWidth = function(self) return #tostring(self.text or "") * 6 end
  f.CreateTexture = function(self) return NewFrame(self) end
  f.CreateFontString = function(self) return NewFrame(self) end
  f.SetTextColor = function(self, r, g, b) self.color = { r, g, b } end
  f.GetTextColor = function() return 0.5, 0.5, 0.5 end
  f.GetJustifyH = function(self) return self.justify or "LEFT" end
  return f
end

CreateFrame = function(_, _, parent) return NewFrame(parent) end
UIParent = NewFrame()
GameTooltip = NewFrame()
C_Timer = { After = noop, NewTicker = function() return { Cancel = noop } end }
GetTime = function() return 1000 end
C_Item = { GetItemInfo = function() return "item" end }

local ns = {}
ns.COLORS = setmetatable({}, { __index = function() return "ffffffff" end })
ns.NewModule = function(name) local m = {}; ns[name] = m; return m end
ns.RegisterCommand, ns.RegisterEvent = noop, noop
ns.Print, ns.PrintRaw, ns.Debug, ns.Warn = noop, noop, noop, noop
ns.db = {}
ns.Config = { Get = function() return nil end, Set = noop }
ns.Theme = {
  FONT = "font",
  sizes = { tiny = 10, small = 11, normal = 12, large = 14, title = 16 },
  TextWidth = function(label) return label:GetStringWidth() end,
  Unpack = function() return 1, 1, 1, 1 end,
  Fill = function() return NewFrame() end,
  Border = noop, SetBorderColor = noop, TopSheen = noop,
  CreateLabel = function(parent, _, _, justify)
    local label = NewFrame(parent)
    label.justify = justify
    return label
  end,
  SetRowName = function(label, text) label:SetText(text) end,
  SetItemNameColor = function() return false end,
  CreateItemIcon = function() return NewFrame() end,
  SetItemIcon = noop,
  CreatePanel = function() return NewFrame() end,
  AccentStripe = noop,
  CreateHeading = function() return NewFrame() end,
  CreateDivider = function() return NewFrame() end,
  SetMoneyText = function(label, copper) label:SetText(tostring(copper) .. "c") end,
  ProfitColor = function() return 1, 1, 1 end,
}

assert(loadfile(lfs_cwd .. "/Core/Util.lua"))("Blackthornes_TS", ns)
assert(loadfile(lfs_cwd .. "/UI/Widgets.lua"))("Blackthornes_TS", ns)

-- The list and the controls around it, as the other suites stub them.
local list
ns.Widgets.CreateSearchBox = function() return NewFrame() end
ns.Widgets.CreateCheckbox = function() return NewFrame() end
ns.Widgets.CreateDropdown = function() return NewFrame() end
ns.Widgets.CreateScrollList = function(_, opts)
  list = NewFrame()
  list.opts = opts
  list.SetData = function(self, d) self.data = d end
  return list
end

-- Skill and price run opposite ways, so a list by price is plainly not by skill.
local function Row(id, skill, price, profit)
  return { recipeID = id, record = { recipeID = id, profession = "Enchanting" }, name = "Recipe " .. id,
    profession = "Enchanting", skill = skill, price = price, profit = profit, learn = "Vendor" }
end
local rows = {
  Row(1, 185, 9000, 226), Row(2, 140, 7000, -727), Row(3, 130, 5000, -1270),
  Row(4, 300, nil, 7582), Row(5, 250, nil, 2151), Row(6, 1, nil, 47), Row(7, 20, nil, 23),
}
ns.RecipeBook = {
  GetProfessions = function() return { "Enchanting" } end,
  List = function() return rows end,
  LearnFrom = function() return "Vendor", {} end,
  KnownByText = function() return nil end,
  Value = function() return {} end,
}
ns.Recipes = { GetLearnedProfessions = function()
  return { { name = "Enchanting", skillLevel = 27, maxSkillLevel = 75 } } end }

assert(loadfile(lfs_cwd .. "/UI/Columns.lua"))("Blackthornes_TS", ns)
assert(loadfile(lfs_cwd .. "/UI/HouseKit.lua"))("Blackthornes_TS", ns)
assert(loadfile(lfs_cwd .. "/UI/RecipeBookView.lua"))("Blackthornes_TS", ns)
local View = ns.RecipeBookView

local passed, failed = 0, 0
local function check(label, got, want)
  local ok = got == want
  if ok then passed = passed + 1 else failed = failed + 1 end
  print(string.format("  %-58s %-24s %s", label, tostring(got), ok and "ok" or
    ("WRONG, wanted " .. tostring(want))))
end

local function Skills()
  local out = {}
  for _, row in ipairs(list.data) do out[#out + 1] = tostring(row.skill) end
  return table.concat(out, ",")
end

-- As the game does it: the headings are laid out at the window's width the
-- first time a width is asked for, which is while the view is being built.
layoutWidth = 600
View.Build(NewFrame())
layoutWidth = nil
View.Refresh()
local widgets = View._widgets
local headings = widgets.headings
local sorter = widgets.sorter
check("laid out while being built", headings.width, 600)

print("\na narrow list")
for _, key in ipairs({ "price", "demand", "disenchant" }) do
  check(key .. " heading steps aside", headings.cells[key]:IsShown(), false)
  check("and takes no clicks", sorter.buttons[key]:IsShown(), false)
end
-- Which shown headings lie over the spot SKILL is drawn in: a hidden one
-- keeps the spot it had before it stepped aside.
local function Span(label)
  local right = label.points.RIGHT
  if not right then return nil end
  return right[3] - label.width, right[3]
end
local function OverSkill()
  local left, right = Span(headings.cells.skill)
  local over = {}
  for key, button in pairs(sorter.buttons) do
    local l, r = Span(button.label)
    if key ~= "skill" and button:IsShown() and l and l < right and r > left then over[#over + 1] = key end
  end
  table.sort(over)
  return table.concat(over, ",")
end
check("nothing else takes a click on SKILL", OverSkill(), "")
check("skill heading shows", headings.cells.skill:IsShown(), true)
check("and takes clicks", sorter.buttons.skill:IsShown(), true)

print("\nclicking SKILL")
sorter.buttons.skill.scripts.OnClick(sorter.buttons.skill)
check("sorts by skill", sorter.key, "skill")
check("biggest first", Skills(), "300,250,185,140,130,20,1")
sorter.buttons.skill.scripts.OnClick(sorter.buttons.skill)
check("again: smallest first", Skills(), "1,20,130,140,185,250,300")
sorter.buttons.skill.scripts.OnClick(sorter.buttons.skill)
check("a third time gives the list back", sorter.key, nil)

print("\na wide list")
headings.width = 1400
headings.scripts.OnSizeChanged(headings)
View.Refresh()
check("recipe price heading comes back", headings.cells.price:IsShown(), true)
check("and takes clicks", sorter.buttons.price:IsShown(), true)

print("\na column turned off")
-- A new copy, as the Level Up tab builds its own.
ns.Columns:SetShown("recipes", "disenchant", false)
local second = View.New({})
second.Build(NewFrame())
second.Refresh()
local wide = second._widgets.headings
wide.width = 1400
wide.scripts.OnSizeChanged(wide)
second.Refresh()
check("its heading is hidden", wide.cells.disenchant:IsShown(), false)
check("and takes no clicks", second._widgets.sorter.buttons.disenchant:IsShown(), false)
for key, button in pairs(second._widgets.sorter.buttons) do
  if button:IsShown() ~= button.label:IsShown() then
    check(key .. " clicks only while its heading shows", button:IsShown(), button.label:IsShown())
  end
end

print(string.format("\n%d passed, %d failed", passed, failed))
if failed > 0 then error(failed .. " checks failed") end
