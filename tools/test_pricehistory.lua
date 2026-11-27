-- Price History on the auction house Sell list.
--
-- A player asked, the owner said build it from a mockup (2026-11-26). A
-- click on a Sell row picks it; a click on the picked row lets it go. While
-- a row is picked, Price History shows in the foot, in the foot note's
-- place, and opens the Prices tab with that item picked. When the foot is
-- too narrow beside Queue All, it takes Duration's place too. It never
-- shows on Buy or the other views.

local ns = {}
ns.NewModule = function(name) local m = {}; ns[name] = m; return m end
ns.RegisterCommand = function() end
ns.RegisterEvent = function() return true end
ns.Print, ns.Debug, ns.Warn = function() end, function() end, function() end

--------------------------------------------------------------------------------
-- Frames that remember whether they show, their width and their anchors
--------------------------------------------------------------------------------

local function Stub(fields)
    local frame = fields or {}
    frame.shown = frame.shown == nil and true or frame.shown
    frame.width = frame.width or 0
    frame.points = {}
    frame.Show = function(self) self.shown = true end
    frame.Hide = function(self) self.shown = false end
    frame.SetShown = function(self, on) self.shown = on and true or false end
    frame.IsShown = function(self) return self.shown end
    frame.SetWidth = function(self, w) self.width = w end
    frame.GetWidth = function(self) return self.width end
    frame.ClearAllPoints = function(self) self.points = {} end
    frame.SetPoint = function(self, ...) self.points[#self.points + 1] = { ... } end
    frame.SetText = function(self, text) self.text = text end
    frame.GetParent = function() return Stub() end
    frame.IsVisible = function(self) return self.shown end
    return setmetatable(frame, { __index = function(self, key)
        local noop = function() end
        rawset(self, key, noop)
        return noop
    end })
end

CreateFrame = function() return Stub() end
C_Timer = { After = function() end, NewTicker = function() return Stub() end }

ns.Theme = setmetatable({
    FONT = "font",
    sizes = { tiny = 10, small = 11, normal = 12, large = 14, title = 16 },
    Unpack = function(key) return key end,
    TextWidth = function(label) return #(label.text or "") * 6 end,
}, { __index = function() return function() return Stub() end end })

local buttons = {}
ns.Widgets = setmetatable({
    CreateButton = function(_, text, onClick, opts)
        local button = Stub({ text = text, onClick = onClick, width = opts and opts.width or 90 })
        button.label = { text = text }
        buttons[text] = button
        return button
    end,
    CreateDropdown = function() return Stub({ width = 76 }) end,
}, { __index = function() return function() return Stub() end end })

ns.Util = { FormatMoney = function(c) return tostring(c) end }
ns.COLORS = { profit = "ff4fd18b" }
ns.Config = { Get = function() return nil end, Set = function() end }
ns.Posting = { DURATIONS = { { text = "24 Hours", value = 24 } } }
ns.Collapse = {}
ns.L = setmetatable({ Format = string.format }, { __index = function(_, key) return key end })

local PostPanel
local realNew = ns.NewModule
ns.NewModule = function(name) local m = realNew(name); PostPanel = m; return m end
assert(loadfile(lfs_cwd .. "/UI/PostPanel.lua"))("Blackthornes_TS", ns)

local checks = 0
local function check(label, condition)
    checks = checks + 1
    if not condition then error(("FAILED: %s"):format(label), 2) end
    print(("  ok  %s"):format(label))
end

-- The drawer's foot, as Build leaves it.
local refreshed = 0
PostPanel.list = Stub({ rows = {}, Refresh = function() refreshed = refreshed + 1 end })
PostPanel.frame = Stub({ width = 402 })
PostPanel.footNote = Stub()
PostPanel.duration = Stub({ width = 76 })
PostPanel.listAll = Stub({ width = 110 })
PostPanel.queueAll = Stub({ width = 100, shown = false })
PostPanel.priceHistory = Stub({ width = 96, shown = false })
PostPanel.view = "sell"

local opened
local openedLink
ns.PricesUI = { ShowItem = function(_, itemID, link) opened, openedLink = itemID, link end }

check("nothing picked at first", PostPanel:IsPicked({ itemID = 7 }) == false)
check("Price History hides with nothing picked", not PostPanel.priceHistory:IsShown())

PostPanel:Pick(7)
check("a click picks the row", PostPanel:IsPicked({ itemID = 7 }))
check("another row is not picked", PostPanel:IsPicked({ itemID = 8 }) == false)
check("the list draws the pick", refreshed > 0)
check("Price History shows once a row is picked", PostPanel.priceHistory:IsShown())
check("it takes the foot note's place", not PostPanel.footNote:IsShown())
check("Duration stays while there is room", PostPanel.duration:IsShown())
check("it sits right of Duration", PostPanel.priceHistory.points[1][2] == PostPanel.duration)

PostPanel:OpenPriceHistory()
check("it opens the Prices tab on the picked item", opened == 7)
PostPanel:Pick(7)
PostPanel:Pick(7, "|Hitem:7::::::::18:1485:::1:12722:::::|h[Band of the Monkey]|h")
PostPanel:OpenPriceHistory()
check("with the picked copy, so a suffix opens as itself", openedLink == "|Hitem:7::::::::18:1485:::1:12722:::::|h[Band of the Monkey]|h")
PostPanel:Pick(7)
check("let go, the copy goes too", PostPanel.pickedLink == nil)
PostPanel:Pick(7)

-- Queue All too: too wide for all four, so Duration steps aside.
PostPanel.queueAll.shown = true
PostPanel:AnchorFootNote()
check("too narrow: Duration steps aside", not PostPanel.duration:IsShown())
check("too narrow: it starts at the foot's left edge", PostPanel.priceHistory.points[1][2] == PostPanel.frame)
PostPanel.queueAll.shown = false
PostPanel:AnchorFootNote()
check("room again: Duration comes back", PostPanel.duration:IsShown())

PostPanel:Pick(7)
check("a click on the picked row lets it go", PostPanel.picked == nil)
check("Price History hides again", not PostPanel.priceHistory:IsShown())
check("the foot note comes back", PostPanel.footNote:IsShown())
opened = nil
PostPanel:OpenPriceHistory()
check("nothing picked opens nothing", opened == nil)

PostPanel:Pick(9)
PostPanel.view = "buy"
PostPanel:UpdatePriceHistory()
check("never on Buy", not PostPanel.priceHistory:IsShown())
PostPanel.view = "sell"
ns.PricesUI = nil
PostPanel:UpdatePriceHistory()
check("no Prices tab, no button", not PostPanel.priceHistory:IsShown())

local source = assert(io.open(lfs_cwd .. "/UI/PostPanel.lua")):read("*a")
check("a click hands on the row's copy", source:find("PostPanel:Pick(line.itemID, line.link)", 1, true) ~= nil)
check("the Sell list marks the picked row", source:find("isSelected = function(line) return PostPanel:IsPicked(line) end", 1, true) ~= nil)
check("a row that left the list lets the pick go", source:find("if not still then self.picked, self.pickedLink = nil, nil end", 1, true) ~= nil)
check("right-click still opens the keep box", source:find('mouseButton == "RightButton" and line and line.itemID and ns.KeepBox', 1, true) ~= nil)

--------------------------------------------------------------------------------
-- The Prices tab opens with the item picked
--------------------------------------------------------------------------------

local prices = assert(io.open(lfs_cwd .. "/UI/Tab_Prices.lua")):read("*a")
check("Prices has ShowItem", prices:find("function PricesUI:ShowItem(itemID, link)", 1, true) ~= nil)
check("it opens on Details", prices:find('self:ShowView("details")', 1, true) ~= nil)
check("it leaves the filters alone", select(2, prices:find("function PricesUI:ShowItem.-\nend\n")) ~= nil
    and not prices:match("function PricesUI:ShowItem.-\nend\n"):find("state.search =", 1, true))

print(("\n%d check(s) passed\n"):format(checks))
