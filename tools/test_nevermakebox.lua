-- UI/NeverMakeBox.lua outside WoW.
--
-- The x on a sub-craft sets it to Buy for good (Queue:NeverMake). It looked
-- like a plain "take it off", so it asks first (2026-10-22). What must hold:
--   1. The x on a sub-craft opens the box and sets nothing yet.
--   2. Keep Making closes it and still sets nothing.
--   3. Buy It sets it to Buy, once.
--   4. A craft the player queued is never asked about.
--   5. Both x buttons (Queue tab, craft pane) go through the box.

local GLOBALS = { "CreateFrame", "UIParent", "UISpecialFrames", "tinsert" }
local saved = {}
for _, key in ipairs(GLOBALS) do saved[key] = _G[key] end

local failures = 0
local function check(label, got, want)
  if got == want then
    print("  ok   " .. label)
  else
    failures = failures + 1
    print(string.format("  FAIL %s: got %s, want %s", label, tostring(got), tostring(want)))
  end
end

local function Frame()
  local frame = { shown = true, height = 0 }
  function frame:Hide() self.shown = false end
  function frame:Show() self.shown = true end
  function frame:IsShown() return self.shown end
  function frame:SetHeight(h) self.height = h end
  return setmetatable(frame, { __index = function() return function() end end })
end

local function Label()
  local label = { text = "" }
  function label:SetText(text) self.text = text end
  function label:GetStringHeight() return 14 end
  return setmetatable(label, { __index = function() return function() end end })
end

CreateFrame = function() return Frame() end
UIParent = Frame()
UISpecialFrames = {}
tinsert = table.insert

local ns = {}
ns.NewModule = function(name) local m = {} ns[name] = m return m end

local labels, buttons = {}, {}
ns.Theme = {
  Fill = function() end,
  AddGameOutline = function() end,
  CreateLabel = function() local l = Label() labels[#labels + 1] = l return l end,
}
ns.Widgets = {
  CreateButton = function(_, text, onClick)
    local b = Frame()
    b.text, b.onClick = text, onClick
    buttons[text] = b
    return b
  end,
}
ns.Util = {
  GetItemLabel = function(id) return id == 4377 and "Heavy Blasting Powder" or nil end,
  GetItemQualityColor = function() return nil end,
}
ns.Recipes = {
  GetAny = function(_, id)
    if id == 50 then return { recipeID = 50, name = "Heavy Blasting Powder", outputItemID = 4377 } end
  end,
}

local marked = {}
ns.Queue = {
  NeverMake = function(_, entry)
    if not (entry and entry.isDependency) then return false end
    marked[#marked + 1] = entry.recipeID
    return true
  end,
}

assert(loadfile(lfs_cwd .. "/UI/NeverMakeBox.lua"))("Blackthornes_TS", ns)
local Box = ns.NeverMakeBox

local sub = { recipeID = 50, isDependency = true, quantity = 3 }

print("\nthe x on a sub-craft asks first")
Box.Click(sub)
check("the box is up", Box:IsShown(), true)
check("nothing set yet", #marked, 0)
check("names what it makes", Box.title.text, "Stop making Heavy Blasting Powder?")
check("says what happens", Box.note.text,
  "The queue will buy it instead, from now on.\nYou can undo this in Settings, Queue.")
check("Buy It button", buttons["Buy It"] ~= nil, true)
check("Keep Making button", buttons["Keep Making"] ~= nil, true)

print("\nKeep Making")
buttons["Keep Making"].onClick()
check("closed", Box:IsShown(), false)
check("still nothing set", #marked, 0)

print("\nBuy It")
Box.Click(sub)
buttons["Buy It"].onClick()
check("closed", Box:IsShown(), false)
check("set to Buy once", #marked, 1)
check("the right craft", marked[1], 50)
buttons["Buy It"].onClick()
check("a second click sets nothing more", #marked, 1)

print("\na craft you queued is not asked about")
check("no box", Box:Ask({ recipeID = 10 }), false)
check("not shown", Box:IsShown(), false)

print("\nboth x buttons go through the box")
for _, path in ipairs({ "/UI/Tab_Queue.lua", "/UI/CraftPanel.lua" }) do
  local file = assert(io.open(lfs_cwd .. path))
  local text = file:read("*a")
  file:close()
  check(path .. " asks first", text:find("ns.NeverMakeBox.Click(row.data, row.remove)", 1, true) ~= nil, true)
end

for _, key in ipairs(GLOBALS) do _G[key] = saved[key] end

if failures > 0 then error(failures .. " check(s) failed") end
print("\nall NeverMakeBox checks passed")
