-- "Upgrades Only:" on Blizzard's profession window (UI/UpgradesOnly.lua).
--
-- Acts out the player's steps against a fake profession window: open it
-- without Equipment, with Equipment, tick the box, search, change gear, find
-- nothing, untick, reopen. Checks that Blizzard's own list is never changed,
-- that the list shown holds only upgrades under the headings that still have
-- one, and that nothing is handed over again while the answers stay the same.

local saved = {
  CreateFrame = CreateFrame, CreateTreeDataProvider = CreateTreeDataProvider,
  hooksecurefunc = hooksecurefunc, ProfessionsFrame = ProfessionsFrame,
  TradeSkillFrame = TradeSkillFrame, BlackthornesEquipment = BlackthornesEquipment,
  C_Timer = C_Timer, GameTooltip = GameTooltip, C_TradeSkillUI = C_TradeSkillUI,
  ScrollBoxConstants = ScrollBoxConstants,
  SmartNavigation_MarkFrameIgnored = SmartNavigation_MarkFrameIgnored,
  InCombatLockdown = InCombatLockdown,
}

local function check(label, got, want)
  if got ~= want then
    error(("%s: expected %s, got %s"):format(label, tostring(want), tostring(got)), 2)
  end
end

--------------------------------------------------------------------------------
-- The fake client
--------------------------------------------------------------------------------

local function Node(data)
  local node = { data = data, nodes = {}, collapsed = false }
  function node:GetData() return self.data end
  function node:GetNodes() return self.nodes end
  function node:Insert(d) local c = Node(d); self.nodes[#self.nodes + 1] = c; return c end
  function node:IsCollapsed() return self.collapsed end
  function node:SetCollapsed(v) self.collapsed = v end
  return node
end

CreateTreeDataProvider = function()
  local tree = { root = Node(nil) }
  function tree:GetRootNode() return self.root end
  function tree:Insert(d) return self.root:Insert(d) end
  return tree
end

local function Region()
  local r = { shown = true, points = {} }
  function r:Show() self.shown = true end
  function r:Hide() self.shown = false end
  function r:SetShown(v) self.shown = v and true or false end
  function r:IsShown() return self.shown end
  function r:IsVisible() return self.shown end
  function r:SetPoint(p, rel, rp, x, y) self.points[#self.points + 1] = { p, rel, rp, x or 0, y or 0 } end
  function r:ClearAllPoints() self.points = {} end
  function r:GetNumPoints() return #self.points end
  function r:GetPoint(i) local p = self.points[i]; return p[1], p[2], p[3], p[4], p[5] end
  function r:SetHeight() end
  function r:SetAllPoints() end
  function r:SetText(t) self.text = t end
  function r:SetJustifyH() end
  function r:SetWordWrap() end
  function r:HookScript(name, fn) self[name] = fn end
  function r:CreateFontString() return Region() end
  return r
end

CreateFrame = function() return Region() end

hooksecurefunc = function(t, name, fn)
  local orig = t[name]
  t[name] = function(...)
    local a, b = orig(...)
    fn(...)
    return a, b
  end
end

C_Timer = { After = function(_, fn) fn() end }
GameTooltip = { SetOwner = function() end, SetText = function() end, AddLine = function() end, Show = function() end, Hide = function() end }
C_TradeSkillUI = nil
ScrollBoxConstants = { RetainScrollPosition = true }

local handed = 0
local scroll = Region()
function scroll:SetDataProvider(p) handed = handed + 1; self.provider = p end
function scroll:GetDataProvider() return self.provider end

local list = Region()
list.ScrollBox = scroll
list.SearchBox = Region()
scroll:SetPoint("TOPLEFT", list.SearchBox, "BOTTOMLEFT", -5, -7)
scroll:SetPoint("BOTTOMRIGHT", list, "BOTTOMRIGHT", 0, 5)

ProfessionsFrame = Region()
ProfessionsFrame.CraftingPage = { RecipeList = list }
TradeSkillFrame = nil

--- Blizzard's list: Camping (no upgrades), Chest (one), Hands (one), Bags
--- (none). Each category ends in a spacer, as Blizzard's does.
local function BlizzardList(names)
  local tree = CreateTreeDataProvider()
  local recipes = {
    Camping = { 1, 2 }, Chest = { 3, 4 }, Hands = { 5 }, Bags = { 6 },
  }
  for _, cat in ipairs({ "Camping", "Chest", "Hands", "Bags" }) do
    local c = tree:Insert({ categoryInfo = { name = cat } })
    for _, id in ipairs(recipes[cat]) do
      if not names or names[id] then c:Insert({ recipeInfo = { recipeID = id } }) end
    end
    c:Insert({ bottomPadding = true })
  end
  tree:Insert({ isDivider = true })
  return tree
end

--------------------------------------------------------------------------------
-- The addon
--------------------------------------------------------------------------------

local settings = {}
local ns = {}
ns.NewModule = function(name) local m = {}; ns[name] = m; return m end
ns.Config = {
  Get = function(_, key) return settings[key] end,
  Set = function(_, key, value) settings[key] = value end,
}
ns.Recipes = {
  Get = function(_, id) return { outputItemID = 100 + id } end,
}
local clicks = {}
ns.Widgets = {
  CreateCheckbox = function(parent, text, onToggle, initial)
    local box = Region()
    box.label, box.checked = text, initial and true or false
    function box:SetChecked(v) self.checked = v and true or false end
    function box:GetChecked() return self.checked end
    function box:Click() self.checked = not self.checked; onToggle(self.checked) end
    clicks[#clicks + 1] = box
    return box
  end,
}

assert(loadfile(lfs_cwd .. "/Core/Compat.lua"))("Blackthornes_TS", ns)
assert(loadfile(lfs_cwd .. "/Logic/Upgrades.lua"))("Blackthornes_TS", ns)
assert(loadfile(lfs_cwd .. "/UI/UpgradesOnly.lua"))("Blackthornes_TS", ns)
local Only, Upgrades = ns.UpgradesOnly, ns.Upgrades

local UP = { [103] = true, [105] = true }
local function Equip()
  BlackthornesEquipment = { Compare = { IsUpgrade = function(_, item) return UP[item] == true end } }
end

--- The recipe IDs and headings a provider shows, as one line.
local function Shown(provider)
  local out = {}
  for _, cat in ipairs(provider:GetRootNode():GetNodes()) do
    local d = cat:GetData()
    if d.categoryInfo then
      local ids = {}
      for _, child in ipairs(cat:GetNodes()) do
        local cd = child:GetData()
        ids[#ids + 1] = cd.recipeInfo and tostring(cd.recipeInfo.recipeID) or "pad"
      end
      out[#out + 1] = d.categoryInfo.name .. "(" .. table.concat(ids, ",") .. ")"
    else
      out[#out + 1] = "div"
    end
  end
  return table.concat(out, " ")
end

local function TopY() return scroll.points[1][5] end

--------------------------------------------------------------------------------
-- The steps
--------------------------------------------------------------------------------

-- 1. Without Equipment: no box, nothing moved, Blizzard's list as it is.
BlackthornesEquipment = nil
local blizzard = BlizzardList()
scroll:SetDataProvider(blizzard)
handed = 0
check("finds the list", Only:Attach(), true)
check("no box without Equipment", Only.box:IsShown(), false)
check("list not moved", TopY(), -7)
check("Blizzard's list untouched", scroll.provider, blizzard)
check("nothing handed over", handed, 0)

-- 2. Equipment on, box off: the box shows, the list starts lower.
Equip()
Only:Attach()
check("box shows with Equipment", Only.box:IsShown(), true)
check("box starts unticked", Only.box:GetChecked(), false)
check("room made", TopY(), -7 - Only.ROOM)
check("bottom edge kept", scroll.points[2][5], 5)
check("still Blizzard's list", scroll.provider, blizzard)
Only:Attach()
check("room made once", TopY(), -7 - Only.ROOM)

-- 3. Tick: only upgrades, in their headings.
local blizzardShape = Shown(blizzard)
Only.box:Click()
check("saved account wide", settings.upgradesOnlyRecipes, true)
check("ours shown", scroll.provider ~= blizzard, true)
check("only upgrades", Shown(scroll.provider), "Chest(3,pad) Hands(5,pad)")
check("Blizzard's list unchanged", Shown(blizzard), blizzardShape)
check("entries are Blizzard's own",
  scroll.provider:GetRootNode():GetNodes()[1]:GetNodes()[1]:GetData(),
  blizzard:GetRootNode():GetNodes()[2]:GetNodes()[1]:GetData())
check("no empty note", Only.empty:IsShown(), false)

-- 4. Search narrows: Blizzard hands a new list, which is filtered at once.
local searched = BlizzardList({ [3] = true, [4] = true })
scroll:SetDataProvider(searched)
check("search still narrows", Shown(scroll.provider), "Chest(3,pad)")

-- 5. Nothing changed: nothing handed over again.
handed = 0
Only:Refilter()
Only:RefilterSoon()
check("same answers, list left alone", handed, 0)

-- 6. New gear: answers change, the list follows.
scroll:SetDataProvider(blizzard)
UP[103], UP[101] = nil, true
Upgrades:Forget()
Only:Refilter()
check("new answers shown", Shown(scroll.provider), "Camping(1,pad) Hands(5,pad)")

-- 7. A collapsed heading stays collapsed.
blizzard:GetRootNode():GetNodes()[4].collapsed = true
UP[106] = true
Upgrades:Forget()
Only:Refilter()
local bags = scroll.provider:GetRootNode():GetNodes()[3]
check("bags kept", bags:GetData().categoryInfo.name, "Bags")
check("still collapsed", bags:IsCollapsed(), true)

-- 8. Nothing is an upgrade: the empty note shows.
UP = {}
Upgrades:Forget()
Only:Refilter()
check("empty list", Shown(scroll.provider), "")
check("empty note shows", Only.empty:IsShown(), true)
check("empty note words", Only.empty and true, true)

-- 9. Untick: Blizzard's latest list comes back.
Only.box:Click()
check("unticked saved", settings.upgradesOnlyRecipes, false)
check("Blizzard's list back", scroll.provider, blizzard)
check("empty note gone", Only.empty:IsShown(), false)
handed = 0
scroll:SetDataProvider(searched)
check("off: Blizzard's lists pass through", scroll.provider, searched)
check("off: handed once", handed, 1)

-- 10. Reopen with the box saved on: filtered at once.
UP[105] = true
Upgrades:Forget()
settings.upgradesOnlyRecipes = true
local reopened = BlizzardList()
scroll:SetDataProvider(reopened)
check("saved on filters on the next list", Shown(scroll.provider), "Hands(5,pad)")

-- 11. Arrows turned off: no box, room and list given back.
settings.showUpgradeArrows = false
Only:Apply()
check("box hidden with arrows off", Only.box:IsShown(), false)
check("room given back", TopY(), -7)
check("list given back", scroll.provider, reopened)
settings.showUpgradeArrows = nil

-- 12. Equipment gone: same.
Only:Apply()
check("back on", TopY(), -7 - Only.ROOM)
BlackthornesEquipment = nil
Only:Apply()
check("no Equipment, room given back", TopY(), -7)
check("no Equipment, list given back", scroll.provider, reopened)
check("report says why", Only:ReportText(), "hidden, Equipment is not loaded")

-- 13. A gamepad player (a player's report, 2026-11-22): the gamepad's window
-- cursor must never land on the box. When the cursor leaves a piece of ours,
-- the game runs our code inside its own close-window steps, and then blocks
-- its next step (14x "Blackthornes_TS tried to call the protected function
-- SetPreferredGamepadInteractTarget()"). The game's own mark keeps the cursor
-- off, set out of a fight only, once the gamepad's code is loaded.
local ignored = {}
local fighting = true
InCombatLockdown = function() return fighting end
SmartNavigation_MarkFrameIgnored = function(frame) ignored[frame] = (ignored[frame] or 0) + 1 end
Equip()
Only:Attach()
check("not marked in a fight", ignored[Only.box], nil)
fighting = false
Only:Attach()
check("box kept off the gamepad cursor", ignored[Only.box], 1)
check("empty note kept off too", ignored[Only.empty], 1)
Only:Attach()
check("marked once", ignored[Only.box], 1)
SmartNavigation_MarkFrameIgnored = function() error("blocked") end
local fresh = Only:CreateBox(list)
check("a refused mark breaks nothing", ns.Compat.KeepOffGamepad(fresh), false)
SmartNavigation_MarkFrameIgnored = nil
local later = Region()
check("no gamepad code, nothing to do", ns.Compat.KeepOffGamepad(later), false)
-- The gamepad code loads later, or the fight ends: the waiting frames get
-- their mark then.
SmartNavigation_MarkFrameIgnored = function(frame) ignored[frame] = (ignored[frame] or 0) + 1 end
fighting = true
ns.Compat.KeepWaitingOffGamepad()
check("still waiting in a fight", ignored[later], nil)
fighting = false
ns.Compat.KeepWaitingOffGamepad()
check("marked once the gamepad code is there", ignored[later], 1)
check("refused box marked on the next try", ignored[fresh], 1)
ns.Compat.KeepWaitingOffGamepad()
check("nothing marked twice", ignored[later], 1)

for key, value in pairs(saved) do _G[key] = value end
print("test_upgradesonly: all checks passed")
