-- Learn next's Have Skill and Learn From on the Level Up tab, outside WoW.
--
-- The owner said build it (2026-11-17, from a mockup). The tab is drawn on
-- stand-in frames and widgets, with the real Logic/LearnNext.lua filter.
-- What must hold:
--   1. With both filters as they start, the list is today's: trainer and
--      vendor recipes, the ones out of reach last.
--   2. Have Skill and Learn From sit on the LEARN NEXT line, and Learn From
--      shows how many recipes each choice keeps.
--   3. Ticking Have Skill hides the rows out of reach; picking Drop shows
--      the drop rows, with "Drop" under WHERE, the auction price under LEARN
--      (else "--") and no Show the Way. Neither reads the recipes again.
--   4. When the filters leave nothing, the LEARN NEXT line stays with the
--      empty words and Show All, which puts both filters back.
--   5. Both are kept between sessions (levelUpHaveSkill, levelUpLearnFrom).

local GLOBALS = { "wipe", "CreateFrame", "UIParent", "GameTooltip", "C_Timer", "GetProfessions",
  "GetProfessionInfo", "UnitFactionGroup", "GetRealZoneText", "GetLocale", "time", "GetTime" }
local saved = {}
for _, key in ipairs(GLOBALS) do saved[key] = _G[key] end

local function noop() end
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end

--- A stand-in frame: any method it lacks does nothing; the ones the tab
--- leans on keep what they are told.
local Obj
local FRAME = {}
function FRAME:Show() self.shown = true end
function FRAME:Hide() self.shown = false end
function FRAME:SetShown(on) self.shown = on and true or false end
function FRAME:IsShown() return self.shown ~= false end
function FRAME:IsVisible() return self.shown ~= false end
function FRAME:SetText(text) self.text = text end
function FRAME:GetText() return self.text end
function FRAME:GetStringWidth() return #(tostring(self.text or "")) * 5 end
function FRAME:GetWidth() return self.width or 900 end
function FRAME:SetWidth(width) self.width = width end
function FRAME:GetHeight() return self.height or 22 end
function FRAME:SetScript(name, fn) self.scripts = self.scripts or {}; self.scripts[name] = fn end
function FRAME:HookScript(name, fn) self:SetScript(name, fn) end
function FRAME:GetScript(name) return self.scripts and self.scripts[name] end
function FRAME:CreateTexture() return Obj() end
function FRAME:CreateFontString() return Obj() end
function FRAME:GetParent() return self.parent end
function FRAME:GetFrameLevel() return 1 end
function FRAME:GetEffectiveScale() return 1 end
function FRAME:GetCenter() return 0, 0 end
function FRAME:GetLeft() return 0 end
function FRAME:GetRight() return 900 end
function FRAME:GetTop() return 600 end
function FRAME:GetBottom() return 0 end
function FRAME:GetNumPoints() return 0 end
Obj = function(parent)
  -- Methods are named with a capital, as the game's are; fields are not.
  return setmetatable({ parent = parent }, { __index = function(_, key)
    if FRAME[key] then return FRAME[key] end
    if type(key) == "string" and key:match("^%u") then return noop end
    return nil
  end })
end

CreateFrame = function(_, _, parent) return Obj(parent) end
UIParent = Obj()
GameTooltip = Obj()
GameTooltip.lines = {}
GameTooltip.AddLine = function(self, text) self.lines[#self.lines + 1] = text end
GameTooltip.AddDoubleLine = function(self, left, right) self.lines[#self.lines + 1] = left .. " | " .. tostring(right) end
GameTooltip.SetOwner = function(self) self.lines = {} end
C_Timer = { After = function(_, fn) fn() end, NewTimer = function() return { Cancel = noop } end }
GetProfessions = function() return nil end
GetProfessionInfo = function() return nil end
UnitFactionGroup = function() return "Alliance" end
GetRealZoneText = function() return "Elwynn Forest" end
GetLocale = function() return "enUS" end
time = function() return 1000000 end
GetTime = function() return 1000000 end

local ns = {}
ns.COLORS = setmetatable({}, { __index = function() return "ffffffff" end })
ns.NewModule = function(name) local m = {} ns[name] = m return m end
ns.RegisterEvent = noop
ns.Debug = function(...) print("  debug", ...) end
ns.Print = noop

local config = {}
ns.Config = {
  Get = function(_, key) return config[key] end,
  Set = function(_, key, value) config[key] = value end,
  GetCharacterKey = function() return "me" end,
}

ns.Util = setmetatable({
  FormatMoney = function(c) return tostring(c) .. "c" end,
  GetItemLabel = function(id) return "Plans " .. id end,
  Uncolored = function(text) return text end,
}, { __index = function() return noop end })

-- Theme: anything not named makes a stand-in frame.
ns.Theme = setmetatable({
  Unpack = function() return 1, 1, 1, 1 end,
  sizes = setmetatable({}, { __index = function() return 12 end }),
  FONT = "font",
  SetMoneyText = function(label, copper) label.text = tostring(copper) .. "c" end,
  TextWidth = function() return 40 end,
  MeasureText = function() return 40 end,
  SetRowName = function(label, text) label.text = text end,
}, { __index = function() return function(parent) return Obj(parent) end end })

local made = { checkboxes = {}, dropdowns = {}, buttons = {}, lists = {} }
ns.Widgets = setmetatable({
  SEARCH_WIDTH = 170,
  CreateCheckbox = function(parent, text, onToggle, initial)
    local box = Obj(parent)
    box.label, box.checked, box.onToggle = text, initial and true or false, onToggle
    function box:SetChecked(on) self.checked = on and true or false end
    function box:Click() self.checked = not self.checked; self.onToggle(self.checked) end
    made.checkboxes[#made.checkboxes + 1] = box
    return box
  end,
  CreateDropdown = function(parent, options, onSelect, opts)
    local dd = Obj(parent)
    dd.options, dd.onSelect, dd.menu = options, onSelect, Obj(parent)
    function dd:SetOptions(list) self.options = list end
    function dd:SetValue(value) self.selected = value end
    function dd:GetValue() return self.selected end
    function dd:Pick(value) self.selected = value; self.onSelect(value) end
    made.dropdowns[#made.dropdowns + 1] = dd
    return dd
  end,
  CreateButton = function(parent, text, onClick)
    local button = Obj(parent)
    button.text, button.onClick = text, onClick
    function button:Click() self.onClick() end
    function button:SetEnabledState(on) self.enabled = on end
    made.buttons[#made.buttons + 1] = button
    return button
  end,
  CreateScrollList = function(parent, opts)
    local list = Obj(parent)
    list.opts, list.data = opts, {}
    function list:SetData(data) self.data = data end
    function list:ScrollToTop() end
    function list:Refresh() end
    made.lists[#made.lists + 1] = list
    return list
  end,
  CreateSearchBox = function(parent) local box = Obj(parent) box.GetText = function() return "" end return box end,
  RowItemID = function(data) return data.outputItemID end,
  FitColumns = function() end,
}, { __index = function() return function(parent) return Obj(parent) end end })

ns.Columns = setmetatable({ version = 1, Place = function() return 0 end, Squeeze = function() return {} end },
  { __index = function() return noop end })

local tabs = {}
ns.UI = { RegisterTab = function(_, tab) tabs[tab.key] = tab end }

ns.LevelUp = setmetatable({
  GetRanked = function() return {} end,
  Compare = function(a, b) return a.name < b.name end,
  CHANCE_LABEL = setmetatable({}, { __index = function(_, k) return k end }),
  GetLastSkillLine = function() return nil end,
  ShortNote = function() return nil end,
}, { __index = function() return noop end })
ns.SkillUp = setmetatable({ GetTierLabel = function(_, tier) return tier end },
  { __index = function() return noop end })
ns.Recipes = setmetatable({ Count = function() return 1 end, GetAll = function() return {} end,
  GetAccountWide = function() return {} end }, { __index = function() return noop end })
ns.RecipeBook = setmetatable({
  ClassicLine = function(id) return id end,
  LearnFrom = function() return "Drop", { "Drops from Defias Pillager" } end,
}, { __index = function() return noop end })

local function Stub() return setmetatable({}, { __index = function() return function() return Obj() end end }) end
for _, name in ipairs({ "CraftProgress", "Crafting", "ProfessionOpener", "Cost", "Queue", "Profit" }) do
  ns[name] = Stub()
end
ns.Scanner = { isAuctionHouseOpen = false }

assert(loadfile(lfs_cwd .. "/Logic/LearnNext.lua"))("Blackthornes_TS", ns)

-- The rows Learn next builds (anyWay): two trainer rows, one out of reach,
-- a vendor row, a drop row with a price and a quest row without.
local function Row(name, kind, ways, extra)
  local row = { name = name, recipeID = #name, learnNext = true, tier = "optimal", needs = 100,
    skill = 100, place = { kind = kind, ways = ways, itemID = 9000 + #name }, record = {} }
  for k, v in pairs(extra or {}) do row[k] = v end
  row.price = row.place.price
  return row
end
local built = 0
ns.LearnNext.GetRows = function(_, opts)
  built = built + 1
  assert(opts.anyWay, "the tab builds every way, then filters")
  local rows = {
    Row("Big Bronze Knife", "trainer", { trainer = true }),
    Row("Heavy Bronze Mace", "vendor", { vendor = true }),
    Row("Pearl Dagger", "drop", { drop = true }),
    Row("Odd Charm", "quest", { quest = true }),
    Row("Bronze Warhammer", "trainer", { trainer = true }, { locked = true, needs = 125 }),
  }
  rows[3].place.price, rows[3].price = 240, 240
  return rows
end

assert(loadfile(lfs_cwd .. "/UI/Tab_LevelUp.lua"))("Blackthornes_TS", ns)

local failures = 0
local function check(label, got, want)
  if got ~= want then
    failures = failures + 1
    print(string.format("  FAIL  %-56s got %s, wanted %s", label, tostring(got), tostring(want)))
  else
    print(string.format("  ok    %-56s %s", label, tostring(got)))
  end
end

local container = Obj()
local tab = tabs.levelup
tab.build(container)
-- The tab only lists Learn next once it knows a skill: one profession at 100.
local list = made.lists[1]

--- Draw every entry the way the list does, on fresh rows.
local function Draw()
  local rows = {}
  for _, entry in ipairs(list.data) do
    local row = Obj()
    list.opts.createRow(row)
    list.opts.updateRow(row, entry)
    rows[#rows + 1] = row
  end
  return rows
end

local function Names()
  local names = {}
  for _, entry in ipairs(list.data) do
    names[#names + 1] = entry.heading and "[LEARN NEXT]" or entry.learnEmpty and "[EMPTY]" or entry.name
  end
  return table.concat(names, ", ")
end

local function HeadingRow(rows)
  for index, entry in ipairs(list.data) do if entry.heading then return rows[index] end end
end

tab.refresh()
print("\nas it starts")
check("today's list: trainer and vendor, out of reach last", Names(),
  "[LEARN NEXT], Big Bronze Knife, Heavy Bronze Mace, Bronze Warhammer")
check("built once", built, 1)
local rows = Draw()
local head = HeadingRow(rows)
check("Have Skill is on the LEARN NEXT line", head and head.haveSkill and head.haveSkill.label, "Have Skill")
check("and starts off", head.haveSkill.checked, false)
check("Learn From: is beside it", head.learnFromLabel and head.learnFromLabel.text, "Learn From:")
check("starting on Trainer or Vendor", head.learnFrom.selected, "trainerVendor")
local counts = {}
for _, option in ipairs(head.learnFrom.options) do counts[option.text] = option.note end
check("Trainer or Vendor count", counts["Trainer or Vendor"], 3)
check("Drop count", counts["Drop"], 1)
check("Quest or Other count", counts["Quest or Other"], 1)
check("Any Way count", counts["Any Way"], 5)
check("six choices", #head.learnFrom.options, 6)
check("a trainer row shows the way", rows[2].wayButton.shown, true)

print("\nHave Skill ticked")
head.haveSkill:Click()
check("the row out of reach goes", Names(), "[LEARN NEXT], Big Bronze Knife, Heavy Bronze Mace")
check("nothing read again", built, 1)
check("kept between sessions", config.levelUpHaveSkill, true)

print("\nLearn From: Drop")
head.learnFrom:Pick("drop")
check("only the drop row", Names(), "[LEARN NEXT], Pearl Dagger")
check("nothing read again", built, 1)
check("kept between sessions", config.levelUpLearnFrom, "drop")
rows = Draw()
local drop = rows[2]
check("WHERE says Drop", drop.cells.where.text, "Drop")
check("LEARN shows the auction price", drop.cells.learn.text, "240c")
check("no Show the Way", drop.wayButton.shown, false)
list.opts.onEnter(drop, list.data[2])
local tip = table.concat(GameTooltip.lines, "\n")
check("the hover has the recipe book's line", tip:find("Drops from Defias Pillager", 1, true) ~= nil, true)
check("and the auction price", tip:find("Learn: 240c at the auction house", 1, true) ~= nil, true)
check("and the shift-click hint", tip:find("Shift-click to search the auction house.", 1, true) ~= nil, true)
check("and never says it shows the way", tip:find("show the way", 1, true) == nil, true)
check("its menu has no Show the Way", #(list.opts.menu(list.data[2]) or {}), 0)
check("shift-click searches the plans", list.opts.searchItem(list.data[2]), list.data[2].place.itemID)

head.learnFrom:Pick("quest")
rows = Draw()
check("a quest row says Quest or other", rows[2].cells.where.text, "Quest or other")
check("no price shows --", rows[2].cells.learn.text, "--")

print("\nnothing left")
head.learnFrom:Pick("vendor")
config.levelUpHaveSkill = true
-- Only the vendor row is left; take it out by searching nothing that holds it.
ns.LearnNext.GetRows = function() built = built + 1 return {
  Row("Bronze Warhammer", "trainer", { trainer = true }, { locked = true, needs = 125 }),
} end
tab.refresh()
check("the LEARN NEXT line stays, with the empty line", Names(), "[LEARN NEXT], [EMPTY]")
rows = Draw()
local empty = rows[2]
check("the empty words", empty.emptyText and empty.emptyText.text, "No recipes to learn here with these filters.")
check("Show All is there", empty.showAll.shown, true)
check("the LEARN NEXT line keeps its filters", rows[1].learnFrom.shown, true)
empty.showAll:Click()
check("Show All unticks Have Skill", config.levelUpHaveSkill, false)
check("and sets Learn From back", config.levelUpLearnFrom, "trainerVendor")
check("and the row out of reach shows again", Names(), "[LEARN NEXT], Bronze Warhammer")

print("\nthe next session")
config.levelUpHaveSkill, config.levelUpLearnFrom = true, "drop"
made.lists, made.checkboxes, made.dropdowns = {}, {}, {}
assert(loadfile(lfs_cwd .. "/UI/Tab_LevelUp.lua"))("Blackthornes_TS", ns)
tabs.levelup.build(Obj())
list = made.lists[1]
tabs.levelup.refresh()
rows = Draw()
check("Have Skill comes back ticked", rows[1].haveSkill.checked, true)
check("Learn From comes back on Drop", rows[1].learnFrom.selected, "drop")
config.levelUpLearnFrom = "something old"
made.lists = {}
assert(loadfile(lfs_cwd .. "/UI/Tab_LevelUp.lua"))("Blackthornes_TS", ns)
tabs.levelup.build(Obj())
list = made.lists[1]
tabs.levelup.refresh()
rows = Draw()
check("a choice it doesn't know starts on the default", rows[1].learnFrom.selected, "trainerVendor")

print("\nwith the recipe wishlist on")
config.levelUpLearnFrom, config.levelUpHaveSkill = "trainerVendor", false
ns.LearnNext.GetRows = function() built = built + 1 return {
  Row("Big Bronze Knife", "trainer", { trainer = true }),
  Row("Pearl Dagger", "drop", { drop = true }),
  Row("Heavy Bronze Mace", "vendor", { vendor = true }),
} end
local starred = { [#"Heavy Bronze Mace"] = true }
ns.WishlistUI = {
  STAR_ROOM = 14,
  Shown = function() return true end,
  CreateStar = function(parent) local star = Obj(parent) star.Paint = noop return star end,
  FirstTip = noop,
  MenuLine = function(recipeID) return { text = "Add to Wishlist", recipeID = recipeID } end,
  StarredFirst = function(rows)
    local out = {}
    for _, row in ipairs(rows) do if starred[row.recipeID] then out[#out + 1] = row end end
    for _, row in ipairs(rows) do if not starred[row.recipeID] then out[#out + 1] = row end end
    return out
  end,
}
made.lists = {}
assert(loadfile(lfs_cwd .. "/UI/Tab_LevelUp.lua"))("Blackthornes_TS", ns)
tabs.levelup.build(Obj())
list = made.lists[1]
tabs.levelup.refresh()
check("starred first, after the filter", Names(), "[LEARN NEXT], Heavy Bronze Mace, Big Bronze Knife")
rows = Draw()
check("Wishlist First shows on the line", rows[1].firstBox.shown, true)
check("and the filters show beside it", rows[1].haveSkill.shown and rows[1].learnFrom.shown, true)
rows[1].learnFrom:Pick("drop")
check("Learn From still filters with the wishlist on", Names(), "[LEARN NEXT], Pearl Dagger")
local menu = list.opts.menu(list.data[2])
check("a drop row's menu keeps the wishlist line, no Show the Way",
  menu and #menu == 1 and menu[1].text == "Add to Wishlist", true)
ns.WishlistUI = nil

-- Picking the tab built a row for every recipe known in one frame
-- (2026-11-26). Now a pick keeps the rows it had and builds a few a frame,
-- then draws what an at-once refresh draws. Any other refresh is at once
-- and drops a build under way; so does leaving the tab.
print("\npicking the tab builds its rows over frames")
do
  -- The tab as the last section left it.
  local tab, list = tabs.levelup, made.lists[#made.lists]
  local known = { "Bronze Axe", "Copper Mace", "Iron Buckle" }
  local builtRows, atOnce = 0, 0
  local function RowFor(name) return { name = name, recipeID = #name * 7, tier = "optimal" } end
  ns.LevelUp.GetRanked = function()
    atOnce = atOnce + 1
    local rows = {}
    for _, name in ipairs(known) do rows[#rows + 1] = RowFor(name) end
    return rows
  end
  ns.LevelUp.BeginRanked = function() return { items = { 1, 2, 3 }, rows = {} } end
  ns.LevelUp.RankOne = function(_, steps, index)
    builtRows = builtRows + 1
    steps.rows[#steps.rows + 1] = RowFor(known[index])
  end
  ns.LevelUp.FinishRanked = function(_, steps) return steps.rows end
  ns.LevelUp.BuildRow = function() return nil end
  ns.SkillUp.GetTierColor = function() return 1, 1, 1 end

  -- A worker that does one item each time the test says a frame passed.
  local workers = {}
  ns.Util.NewWorker = function(opts)
    local worker = { opts = opts, index = 0, items = {} }
    function worker:Start(items) self.items, self.index, self.running = items, 0, true; workers[#workers + 1] = self end
    function worker:Cancel() self.running = false end
    return worker
  end
  local function Frame()
    for _, worker in ipairs(workers) do
      if worker.running then
        worker.index = worker.index + 1
        worker.opts.onItem(worker.items[worker.index], worker.index, worker)
        if worker.running and worker.index >= #worker.items then
          worker.running = false
          worker.opts.onDone(worker)
        end
      end
    end
  end
  local function KnownNames()
    local names = {}
    for _, entry in ipairs(list.data) do
      if entry.heading then break end
      names[#names + 1] = entry.name
    end
    return table.concat(names, ", ")
  end

  ns.UI.activeTab = "levelup"
  check("the tab has a lighter redraw for a pick", type(tab.refreshPicked), "function")
  tab.refresh()
  check("a plain refresh is at once", atOnce, 1)
  check("and draws the list", KnownNames(), "Bronze Axe, Copper Mace, Iron Buckle")

  known = { "Bronze Axe", "Copper Mace", "Mithril Spurs" }
  atOnce = 0
  tab.refreshPicked()
  check("a pick builds no row in its own frame", builtRows, 0)
  check("and none at once", atOnce, 0)
  check("the rows it had stay up meanwhile", KnownNames(), "Bronze Axe, Copper Mace, Iron Buckle")
  Frame(); Frame()
  check("a row a frame", builtRows, 2)
  check("the old rows still up", KnownNames(), "Bronze Axe, Copper Mace, Iron Buckle")
  Frame()
  check("then the list an at-once refresh gives", KnownNames(), "Bronze Axe, Copper Mace, Mithril Spurs")

  -- A click, a filter or the bags answer at once and drop a build under way.
  builtRows = 0
  tab.refreshPicked()
  Frame()
  tab.refresh()
  check("any other refresh is at once", atOnce, 1)
  Frame(); Frame(); Frame()
  check("and the build under way is dropped", builtRows, 1)

  -- Another tab picked mid-build: nothing more is built or drawn.
  builtRows = 0
  known = { "Left Behind" }
  tab.refreshPicked()
  ns.UI.activeTab = "queue"
  Frame(); Frame(); Frame()
  check("leaving the tab stops the build", builtRows, 0)
  check("and draws nothing over the list", KnownNames(), "Bronze Axe, Copper Mace, Mithril Spurs")
  ns.UI.activeTab = "levelup"
end

for _, key in ipairs(GLOBALS) do _G[key] = saved[key] end

print("")
if failures > 0 then error(string.format("%d learn filter check(s) failed", failures)) end
print("  all learn filter checks passed")
print("")
