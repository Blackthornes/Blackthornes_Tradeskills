-- How the craft pane's words fit the room they have, outside WoW.
--
-- What must hold:
--   1. A row says how many are queued once. At the Keep in stock limit the
--      stock already says "2 queued", and the line said "queued 2" as well.
--   2. A detail line too long for its row drops the queued count first (the
--      box beside the name shows it), then coins off the amount. Its end is
--      never cut off.
--   3. The queue total keeps its warning that some crafts have no price: a *
--      on the line, and what it means on the hover.
--   4. A shopping line names the character holding a material by the short
--      name, and says "on an alt" when even that has no room.
--   5. A greyed name shows grey: the item link's own colour no longer shows
--      over it, in either kind of colour code.
--   6. Materials waiting in the mailbox read "in mail".

-- Tests share one Lua state, so every global replaced here is put back,
-- including the ones that were not set at all.
local GLOBALS = { "CreateFrame", "C_TradeSkillUI" }
local saved = {}
for _, key in ipairs(GLOBALS) do saved[key] = _G[key] end

local function noop() end

-- Six pixels a character, colour codes left out as the game leaves them out.
local function Measure(text)
    local plain = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|cn[%w_]+:", ""):gsub("|r", "")
    return #plain * 6
end

-- Frames and labels whose methods do nothing unless named here. A label is
-- `room` wide; 0 is one not laid out yet.
local function NewFrame()
    local f = { text = "", room = 0 }
    setmetatable(f, { __index = function(_, k)
        if type(k) == "string" and k:match("^%u") then return noop end
    end })
    f.SetText = function(self, text) self.text = text end
    f.GetWidth = function(self) return self.room end
    f.GetStringWidth = function(self) return Measure(self.text) end
    -- The colour's name stands in for the colour (see Theme.Unpack below).
    f.SetTextColor = function(self, colour) self.colour = colour end
    return f
end

CreateFrame = function() return NewFrame() end
C_TradeSkillUI = nil

local ns = {}
ns.NewModule = function(name) local m = {}; ns[name] = m; return m end
ns.COLORS = setmetatable({ warn = "ffe8c25a" }, { __index = function() return "ffffffff" end })
ns.RegisterCommand, ns.RegisterEvent = noop, noop
ns.Print, ns.Warn, ns.Debug = noop, noop, noop

assert(loadfile(lfs_cwd .. "/Core/Util.lua"))("Blackthornes_TS", ns)
local Util = ns.Util

ns.Theme = { Unpack = function(key) return key end, SetItemIcon = noop, SetMark = noop }
ns.Widgets = {}

local CraftPanel
do
    local realNew = ns.NewModule
    ns.NewModule = function(name) local m = realNew(name); CraftPanel = m; return m end
    assert(loadfile(lfs_cwd .. "/UI/CraftPanel.lua"))("Blackthornes_TS", ns)
    ns.NewModule = realNew
end

ns.Config = { Get = function() return nil end, GetCharacterKey = function() return "Player-1-ME" end }
ns.Crafting = { IsBusy = function() return false end, GetReadiness = function() return true end }

local passed, failed = 0, 0

local function check(label, got, want)
    local ok = got == want
    if ok then passed = passed + 1 else failed = failed + 1 end
    print(string.format("  %-58s %s", label, ok and "ok" or
        ("WRONG\n      got    " .. tostring(got) .. "\n      wanted " .. tostring(want))))
end

local function Count(text, word)
    local _, found = text:gsub(word, "")
    return found
end

print("the detail line under a craft")

local function CraftRow(room)
    local row = NewFrame()
    row.name, row.detail, row.icon, row.mark = NewFrame(), NewFrame(), NewFrame(), NewFrame()
    row.quantity, row.craft, row.add, row.remove = NewFrame(), NewFrame(), NewFrame(), NewFrame()
    row.quantity.editBox = NewFrame()
    row.detail.room = room
    return row
end

-- 12g 34s 56c a craft.
local function CraftLine(fields)
    local line = { recipeID = 101, name = "Copper Chain Belt", outputItemID = 2853,
        priceable = true, profit = 123456, craftable = 3, queued = 0, stock = 0 }
    for key, value in pairs(fields) do line[key] = value end
    return line
end

do
    local row = CraftRow(1000)
    CraftPanel._UpdateRow(row, CraftLine({ queued = 2, stock = 3, postLimit = 5,
        atPostLimit = true, queuedElsewhere = 2 }))
    check("at the limit, the queued count is said once",
        row.detail.text, "12g 34s 56c each · can make 3 · have 3, 2 queued, limit 5")
    check("just once", Count(row.detail.text, "queued"), 1)

    local line = CraftLine({ queued = 3, stock = 2, postLimit = 5 })
    local full = "12g 34s 56c each · can make 3 · have 2 of 5 · queued 3"
    local noQueued = "12g 34s 56c each · can make 3 · have 2 of 5"
    local twoCoins = "12g 35s each · can make 3 · have 2 of 5"
    local oneCoin = "12g each · can make 3 · have 2 of 5"

    CraftPanel._UpdateRow(row, line)
    check("with room, the whole line", row.detail.text, full)

    row.detail.room = Measure(noQueued)
    CraftPanel._UpdateRow(row, line)
    check("a little short, the queued count goes first", row.detail.text, noQueued)

    row.detail.room = Measure(twoCoins)
    CraftPanel._UpdateRow(row, line)
    check("shorter, the copper goes, rounded", row.detail.text, twoCoins)

    row.detail.room = Measure(oneCoin)
    CraftPanel._UpdateRow(row, line)
    check("shorter still, the gold alone", row.detail.text, oneCoin)

    row.detail.room = 0
    CraftPanel._UpdateRow(row, line)
    check("a row not laid out yet gets the whole line", row.detail.text, full)
end

print("")
print("the queue total along the bottom")

do
    local totals = { crafts = 4, profit = 123456, priceable = false }
    ns.Queue = { Count = function() return 4 end, GetTotals = function() return totals end }
    CraftPanel.summary = NewFrame()
    CraftPanel.summary.room = 1000

    CraftPanel:UpdateSummary()
    check("some crafts unpriced: a * after the profit",
        CraftPanel.summary.text, "4 queued · profit |cffffffff12g 34s 56c|r|cffe8c25a*|r")
    check("and the hover says what it means", CraftPanel.summaryNote,
        "Some queued crafts have no price, so this profit leaves them out.")

    CraftPanel.summary.room = Measure("4 queued · profit 12g 35s*")
    CraftPanel:UpdateSummary()
    check("too long for the line: coins go, the * stays",
        CraftPanel.summary.text, "4 queued · profit |cffffffff12g 35s|r|cffe8c25a*|r")

    totals.priceable = true
    CraftPanel.summary.room = 1000
    CraftPanel:UpdateSummary()
    check("every craft priced: no *", CraftPanel.summary.text, "4 queued · profit |cffffffff12g 34s 56c|r")
    check("and nothing on the hover", CraftPanel.summaryNote, nil)
end

print("")
print("the shopping list")

local CLOTH, BOLT = 2589, 2996
local LINKS = {
    [CLOTH] = "|cffffffff|Hitem:2589::::::::|h[Linen Cloth]|h|r",
    [BOLT] = "|cnIQ1:|Hitem:2996::::::::|h[Bolt of Linen Cloth]|h|r",
}
Util.GetItemLabel = function(itemID) return LINKS[itemID] end

ns.db = { characters = {
    ["Player-1-ME"] = { inventory = {} },
    ["Player-1-ALT"] = { inventory = { [CLOTH] = 40 } },
} }
ns.Recipes = {
    GetCharacterName = function(_, key) return key == "Player-1-ALT" and "Voldar Ashbringer" or "Me" end,
    GetShortCharacterName = function(_, key) return key == "Player-1-ALT" and "Voldar" or "Me" end,
}

local function ShoppingRow(room)
    local row = NewFrame()
    row.name, row.icon, row.count, row.tag = NewFrame(), NewFrame(), NewFrame(), NewFrame()
    row.bar = { Set = noop }
    row.tag.room = room
    return row
end

do
    check("another character is named by the short name", (CraftPanel:AltHolder(CLOTH)), "Voldar")

    local row = ShoppingRow(1000)
    local onAlt = { itemID = CLOTH, needed = 30, have = 0, shortfall = 30, estimatedCost = 300 }
    CraftPanel.UpdateShoppingRow(row, onAlt)
    check("so the tag reads", row.tag.text, "on Voldar")

    row.tag.room = Measure("on Voldar") - 1
    CraftPanel.UpdateShoppingRow(row, onAlt)
    check("with no room for the name, on an alt", row.tag.text, "on an alt")

    local toBuy = { itemID = BOLT, needed = 3, have = 0, shortfall = 3, estimatedCost = 123456 }
    row.tag.room = 1000
    CraftPanel.UpdateShoppingRow(row, toBuy)
    check("a cost with room for every coin", Util.Uncolored(row.tag.text), "12g 34s 56c")

    row.tag.room = Measure("12g 35s")
    CraftPanel.UpdateShoppingRow(row, toBuy)
    check("and with less room, fewer", Util.Uncolored(row.tag.text), "12g 35s")
    check("still to buy keeps its link colour", row.name.text, LINKS[BOLT])

    CraftPanel.UpdateShoppingRow(row, { itemID = CLOTH, needed = 4, have = 6, shortfall = 0 })
    check("have all reads grey", row.name.colour, "muted")
    check("without the link's own colour over it", row.name.text, "|Hitem:2589::::::::|h[Linen Cloth]|h")

    CraftPanel.UpdateShoppingRow(row, { itemID = BOLT, needed = 4, have = 6, shortfall = 0 })
    check("the named kind of colour code goes too", row.name.text, "|Hitem:2996::::::::|h[Bolt of Linen Cloth]|h")

    local look = CraftPanel:ShoppingLook({ itemID = BOLT, needed = 5, have = 5, shortfall = 0,
        needsMailTrip = true })
    check("enough only counting the mailbox says in mail", look.tag, "in mail")
    check("in amber", look.colour, "warn")
end

print("")
print("taking colour codes off")

do
    check("text with none is left alone", Util.Uncolored("Linen Cloth"), "Linen Cloth")
    check("nothing to read comes back as it was", Util.Uncolored(nil), nil)
end

ns.Queue, ns.db = nil, nil
for _, key in ipairs(GLOBALS) do _G[key] = saved[key] end

print("")
if failed > 0 then
    error(string.format("FAIL -- %d of %d craft pane wording checks wrong", failed, passed + failed))
end
print(string.format("PASS -- the craft pane's words fit their room (%d checks)", passed))
