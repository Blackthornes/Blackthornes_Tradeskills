-- Shift-click on any item in the addon's windows (Trent, 2026-10-12).
--
-- With the auction house open, a shift-click on an item row, a detail
-- pane's icon or a reagent line searches the house for that item. With it
-- closed, the click puts the item's link in the chat box being typed in, as
-- the bags do, and falls through to the row's own click when no chat box is
-- open. One handler, Widgets.ItemShiftClick, decides for all of them.

local ns = {}

-- What Theme.SetItemIcon remembers for an icon, as Theme.lua keeps it.
local iconItems = {}
ns.Theme = {
    Fill = function() return { SetColorTexture = function() end, SetAlpha = function() end } end,
    Unpack = function() return 0, 0, 0, 1 end,
    Border = function() end,
    CreateLabel = function() return {} end,
    AccentStripe = function(frame) return frame:CreateTexture() end,
    IconItem = function(icon)
        local item = iconItems[icon]
        if item then return item.itemID, item.link end
    end,
    SetIconSpot = function(icon, spot) icon.spot = spot; return true end,
}

local function Frame()
    local frame = { points = {}, scripts = {}, shown = true, height = 0, min = 0, max = 0, value = 0 }
    frame.SetHeight = function(self, h) self.height = h end
    frame.GetHeight = function(self) return self.height end
    frame.Show = function(self) self.shown = true end
    frame.Hide = function(self) self.shown = false end
    frame.IsShown = function(self) return self.shown end
    frame.SetShown = function(self, on) self.shown = on and true or false end
    frame.SetScript = function(self, name, fn) self.scripts[name] = fn end
    frame.SetMinMaxValues = function(self, lo, hi) self.min, self.max = lo, hi end
    frame.GetMinMaxValues = function(self) return self.min, self.max end
    frame.SetValue = function(self, v) self.value = v end
    frame.GetValue = function(self) return self.value end
    frame.GetParent = function(self) return self.parent end
    frame.CreateTexture = function(self) local t = Frame(); t.parent = self; return t end
    return setmetatable(frame, { __index = function() return function() end end })
end

CreateFrame = function(_, _, parent) local f = Frame(); f.parent = parent; return f end

local shift = false
IsShiftKeyDown = function() return shift end

C_Item = {
    GetItemInfo = function(itemID) return "Item " .. itemID, "|Hitem:" .. itemID .. "|h[Item]|h" end,
}

local chatOpen, linked = false, {}
ChatEdit_InsertLink = function(link)
    if not chatOpen then return false end
    linked[#linked + 1] = link
    return true
end

local searched = {}
ns.Scanner = { isAuctionHouseOpen = false }
ns.UI = { SearchAuctionHouse = function(_, itemID) searched[#searched + 1] = itemID; return true end }
ns.Util = { HasFunction = function() return true end }
ns.Recipes = { GetAny = function(_, recipeID) return { outputItemID = recipeID + 1000 } end }

local Widgets
do
    local chunk = assert(loadfile(lfs_cwd .. "/UI/Widgets.lua"))
    chunk("Blackthornes_TS", ns)
    Widgets = ns.Widgets
end

local passed, failed = 0, 0
local function check(label, got, want)
    local ok = got == want
    if ok then passed = passed + 1 else failed = failed + 1 end
    print(string.format("  %-58s %-10s %s", label, tostring(got), ok and "ok" or
        ("WRONG, wanted " .. tostring(want))))
end

local function Reset() searched, linked = {}, {} end

-- A list with one row, whose own click is counted.
local clicks = 0
local function ListWith(data, opts)
    opts = opts or {}
    opts.rowHeight = 22
    opts.onClick = function() clicks = clicks + 1 end
    local list = Widgets.CreateScrollList(Frame(), opts)
    list:SetHeight(100)
    list:SetData({ data })
    return list.rows[1]
end

local function Click(row) row.scripts.OnClick(row, "LeftButton") end

print("")
print("rows, with the auction house open")
ns.Scanner.isAuctionHouseOpen = true

Reset(); clicks = 0; shift = true
Click(ListWith({ itemID = 2589 }))
check("a shift-click searches for the row's item",      searched[1], 2589)
check("and the row's own click does not run",           clicks, 0)

Reset()
Click(ListWith({ recipeID = 7 }))
check("a recipe row searches for what it makes",        searched[1], 1007)

Reset(); clicks = 0
Click(ListWith({ itemID = 5 }, { searchItem = function() return false end }))
check("a list that keeps shift-clicks gets the click",  clicks, 1)
check("and nothing is searched",                        #searched, 0)

Reset(); clicks = 0; shift = false
Click(ListWith({ itemID = 2589 }))
check("a plain click is the row's own",                 clicks, 1)
check("and searches nothing",                           #searched, 0)

print("")
print("rows, with the auction house closed")
ns.Scanner.isAuctionHouseOpen = false

Reset(); clicks = 0; shift = true; chatOpen = true
Click(ListWith({ itemID = 2589 }))
check("with a chat box open, the link goes in",         linked[1], "|Hitem:2589|h[Item]|h")
check("and the row's own click does not run",           clicks, 0)
check("nothing is searched",                            #searched, 0)

Reset(); clicks = 0
Click(ListWith({ itemID = 2589, link = "|Hitem:2589:0:0:0:0:0:617|h[Item of the Monkey]|h" }))
check("a row with a link sends that very copy",         linked[1], "|Hitem:2589:0:0:0:0:0:617|h[Item of the Monkey]|h")

Reset(); clicks = 0; chatOpen = false
Click(ListWith({ itemID = 2589 }))
check("with no chat box, the row's own click runs",     clicks, 1)

print("")
print("icons in detail panes and reagent lines")

local pane = Frame()
local icon = pane:CreateTexture()
local spot = Widgets.ItemHotspot(icon)
check("the icon gets a spot",                           icon.spot, spot)

ns.Scanner.isAuctionHouseOpen = true
Reset(); shift = true
iconItems[icon] = { itemID = 4306 }
spot.scripts.OnClick(spot)
check("a shift-click on it searches for its item",      searched[1], 4306)

Reset()
iconItems[icon] = { itemID = 4338 }
spot.scripts.OnClick(spot)
check("it follows the icon's item as it changes",       searched[1], 4338)

Reset(); shift = false
spot.scripts.OnClick(spot)
check("a plain click searches nothing",                 #searched, 0)

Reset(); shift = true
iconItems[icon] = nil
spot.scripts.OnClick(spot)
check("an icon with no item searches nothing",          #searched, 0)

ns.Scanner.isAuctionHouseOpen = false
Reset(); chatOpen = true
iconItems[icon] = { itemID = 4306 }
spot.scripts.OnClick(spot)
check("with the house closed it links in chat",         linked[1], "|Hitem:4306|h[Item]|h")
check("and searches nothing",                           #searched, 0)

print("")
if failed > 0 then
    error(("%d shift-click check(s) failed"):format(failed))
end
print(("  shift-click: all %d checks passed"):format(passed))
