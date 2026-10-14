-- What goes on an enchant's tooltip (UI/EnchantTooltip.lua, asked 2026-10-14).
--
--   1. An Enchanting recipe that makes no item gets its materials' cost, each
--      material, what is short and who knows it.
--   2. A craft that makes an item, or a spell no profession teaches, gets
--      nothing: those have their own tooltips or nothing to say.
--   3. A material with no price says so instead of a zero.
--   4. The lines are kept, so a redraw asks Cost nothing new, until the bags
--      move; and the same tooltip is never given the lines twice.

local ns = {}
ns.NewModule = function(name) local m = {}; ns[name] = m; return m end
ns.COLORS = { accent = "ffc8a44d", muted = "ff7a8089", text = "ffe6e8ec",
  warn = "ffe0b040", profit = "ff40c060" }
ns.Util = {
  FormatMoney = function(copper) return ("<%d>"):format(copper) end,
  GetItemLabel = function(itemID) return ("item %d"):format(itemID) end,
  Uncolored = function(text) return text end,
}

local SOUL_DUST, MYSTIC = 11083, 11134
local NAMES = { [SOUL_DUST] = "Soul Dust", [MYSTIC] = "Lesser Mystic Essence" }
C_Item = { GetItemInfo = function(id) return NAMES[id] end }

local now = 100
GetTime = function() return now end

local BRACER, ROD, FIREBALL, UNPRICED = 13536, 13628, 133, 13537
local BOOK = {
  [BRACER] = { recipeID = BRACER, profession = "Enchanting", skillLineID = 333,
    reagents = { { itemID = SOUL_DUST, quantity = 2 }, { itemID = MYSTIC, quantity = 1 } } },
  [ROD] = { recipeID = ROD, profession = "Enchanting", outputItemID = 11145,
    reagents = { { itemID = SOUL_DUST, quantity = 1 } } },
  [UNPRICED] = { recipeID = UNPRICED, profession = "Enchanting",
    reagents = { { itemID = 99999, quantity = 3 } } },
}
ns.RecipeBook = {
  merged = BOOK,
  Get = function(_, id) return BOOK[id] end,
  KnownByText = function(_, record) if record.recipeID == BRACER then return "you", true end end,
}
ns.Recipes = { GetAny = function() return nil end }

local HAVE = { [SOUL_DUST] = 1, [MYSTIC] = 4 }
local PRICE = { [SOUL_DUST] = 55, [MYSTIC] = 32 }
local costCalls = 0
ns.Cost = {
  GetCraftCost = function(_, recipeID, _, _, opts)
    costCalls = costCalls + 1
    local result = { reagents = {}, priceable = true, total = 0 }
    for _, r in ipairs(opts.recipe.reagents) do
      local unit = PRICE[r.itemID]
      local entry = { itemID = r.itemID, quantity = r.quantity,
        lineCost = unit and unit * r.quantity or nil,
        shortfall = math.max(0, r.quantity - (HAVE[r.itemID] or 0)) }
      result.reagents[#result.reagents + 1] = entry
      if unit then result.total = result.total + entry.lineCost else result.priceable = false end
    end
    if not result.priceable then result.total = nil end
    return result
  end,
}
ns.Inventory = { changes = 1 }

local EnchantTooltip
do
  local realNew = ns.NewModule
  ns.NewModule = function(name) local m = realNew(name); EnchantTooltip = m; return m end
  assert(loadfile(lfs_cwd .. "/UI/EnchantTooltip.lua"))("Blackthornes_TS", ns)
  ns.NewModule = realNew
end
EnchantTooltip.fired, EnchantTooltip.cache, EnchantTooltip.shown = {}, {}, 0

local function check(label, got, want)
  if got ~= want then
    error(("%s: got %s, want %s"):format(label, tostring(got), tostring(want)), 2)
  end
end

local lines = EnchantTooltip:LinesFor(BRACER)
check("total first", lines[1][1], "Materials")
check("total is both materials", lines[1][2], "<142>")
check("each material", lines[2][1], "  2 Soul Dust")
check("its cost", lines[2][2], "<110>")
check("second material", lines[3][1], "  1 Lesser Mystic Essence")
check("short", lines[4][1], "You're short")
check("by what", lines[4][2], "1 Soul Dust")
check("who knows it", lines[5][2], "you")

HAVE[SOUL_DUST] = 5
lines = EnchantTooltip:LinesFor(BRACER)
check("nothing short", lines[4][2], "all of it")

check("an item craft gets nothing", #EnchantTooltip:LinesFor(ROD), 0)
check("a spell no recipe has gets nothing", #EnchantTooltip:LinesFor(FIREBALL), 0)

lines = EnchantTooltip:LinesFor(UNPRICED)
check("an unpriced total says so", lines[1][2], "materials not scanned")
check("and is muted", lines[1][3], true)
check("an unpriced material says so", lines[2][2], "not scanned yet")

-- Links from chat.
check("enchant link", EnchantTooltip.SpellIDFromLink("|cffffd000|Henchant:13536|h[Enchant]|h|r"), 13536)
check("item link is no spell", EnchantTooltip.SpellIDFromLink("|Hitem:2589|h[Linen]|h"), nil)

-- A tooltip.
local function Tooltip(spellID)
  local t = { lines = {} }
  function t:AddDoubleLine(a, b) self.lines[#self.lines + 1] = { a, b } end
  function t:NumLines() return #self.lines end
  function t:Show() end
  function t:GetSpell() return "Enchant", spellID end
  return t
end

costCalls = 0
local tip = Tooltip(BRACER)
check("decorated", EnchantTooltip:Decorate(tip, nil), "shown")
check("five lines", #tip.lines, 5)
check("not twice", EnchantTooltip:Decorate(tip, nil), "duplicate")
check("still five", #tip.lines, 5)
EnchantTooltip:Decorate(Tooltip(BRACER), { id = BRACER })
check("a redraw is kept", costCalls, 1)
ns.Inventory.changes = 2
EnchantTooltip:Decorate(Tooltip(BRACER), nil)
check("bags moved, read again", costCalls, 2)
now = now + 10
EnchantTooltip:Decorate(Tooltip(BRACER), nil)
check("old lines read again", costCalls, 3)

ns.Config = { Get = function(_, key) if key == "tooltipEnchantCosts" then return false end end }
check("turned off", EnchantTooltip:Decorate(Tooltip(BRACER), nil), "quiet")
ns.Config = nil

print("test_enchanttooltip: ok")
