-- The Tradeskills drawer beside the auction house (UI/PostPanel.lua).
--
-- The owner's mockup (2026-10-13): one drawer the full height of the auction
-- window, Scan and Post Crafted in its header, List all at its foot.
--
-- What must hold:
--   1. Folded, the drawer is its header, so Scan is still in reach.
--   2. The close gem puts it away until the auction house is opened again.
--   3. List all lists the most valuable stack Sell shows, one a click, and
--      says how many are left to list.
--   4. Search all on Buy (2026-10-14) looks up every line the auction house
--      sells at once, with each shortfall, or one a click where the game
--      takes one a search; vendor materials are left out.

local ns = {}
ns.NewModule = function(name) local m = {}; ns[name] = m; return m end
ns.RegisterCommand = function() end
ns.Print, ns.Debug, ns.Warn = function() end, function() end, function() end
ns.RegisterEvent = function() return true end

local function Stub(fields)
    local frame = fields or {}
    return setmetatable(frame, { __index = function(self, key)
        local noop = function() end
        rawset(self, key, noop)
        return noop
    end })
end

CreateFrame = function() return Stub() end
C_Timer = { After = function() end }

ns.Theme = {
    sizes = { tiny = 10, small = 11, normal = 12 },
    CreateLabel = function() return Stub() end,
    CreateDivider = function() return Stub() end,
    Unpack = function(key) return key end,
    MeasureText = function(_, text) return #text * 6 end,
}
ns.Widgets = { CreateButton = function() return Stub() end }
ns.Util = { FormatMoney = function(c) return tostring(c) end }
ns.COLORS = { accent = "ffffd100" }

local settings = {}
ns.Config = { Get = function(_, key) return settings[key] end, Set = function(_, key, v) settings[key] = v end }
ns.Collapse = { IsCollapsed = function(key) return settings[key] == true end }

local said, requested
ns.Print = function(text) said = text end
ns.Posting = {
    GetNextPostable = function(_, _, lines)
        for _, line in ipairs(lines or {}) do
            if line.unitPrice and not line.atALoss then return line end
        end
    end,
    GetSummary = function(_, _, lines)
        local count = 0
        for _, line in ipairs(lines or {}) do
            if line.unitPrice and not line.atALoss then count = count + 1 end
        end
        return count, 0
    end,
    CanPost = function() return true end,
    Request = function(_, itemID, quantity, price) requested = { itemID, quantity, price } end,
}

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

-- 1
local AH = { GetTop = function() return 1091 end, GetBottom = function() return 551 end,
    GetRight = function() return 851 end }
ns.UI = { FindAuctionFrame = function() return AH end }
settings.postPanelCollapsed = false
check("open: the auction window's height", PostPanel:TargetHeight() == 540)
settings.postPanelCollapsed = true
check("folded: the header, Scan strip and all", PostPanel:TargetHeight() == PostPanel.FOLDED_HEIGHT)
check("which is taller than the Scan strip itself", PostPanel.FOLDED_HEIGHT > 44)
settings.postPanelCollapsed = false

-- 2
local shown = true
PostPanel.frame = Stub({
    IsShown = function() return shown end,
    Show = function() shown = true end,
    Hide = function() shown = false end,
})
PostPanel.attached = true
PostPanel:CloseForVisit()
check("the close gem puts the drawer away", shown == false)
PostPanel:Redock()
check("and it stays away while the auction house is open", shown == false)
PostPanel:Hide()
check("leaving the auction house forgets it", PostPanel.closedThisVisit == false)

-- 3
local button = Stub({ SetText = function(self, text) self.text = text end,
    SetEnabledState = function(self, on) self.enabled = on end })
PostPanel.listAll = button
local lines = {
    { itemID = 7, atALoss = true, unitPrice = 50, postQuantity = 1 },
    { itemID = 8, unitPrice = 900, postQuantity = 3 },
    { itemID = 9, unitPrice = 400, postQuantity = 2 },
}
PostPanel:UpdateListAll(lines)
check("List all counts what it can list", button.text == "List all 2")
check("and can be clicked", button.enabled == true)

PostPanel.shownLines = lines
PostPanel:ListNext()
check("a click lists the most valuable stack it can", requested and requested[1] == 8 and requested[2] == 3)

PostPanel:UpdateListAll({})
check("nothing to list: no count", button.text == "List all")
check("and greyed", button.enabled == false)

requested = nil
PostPanel.shownLines = {}
PostPanel:ListNext()
check("a click with nothing to list lists nothing", requested == nil and said ~= nil)

-- 4
local shopping = {
    { itemID = 20, shortfall = 6 },
    { itemID = 21, shortfall = 0 },
    { itemID = 22, shortfall = 4, fromVendor = true },
    { itemID = 23, shortfall = 9, fromVendor = true, vendorLimited = true },
    { itemID = 24, shortfall = 2 },
}
PostPanel.ShoppingLines = function() return shopping end
local search = Stub({ SetText = function(self, text) self.text = text end,
    SetEnabledState = function(self, on) self.enabled = on end })
PostPanel.searchAll = search
PostPanel:UpdateSearchAll()
check("Search all counts what the auction house can sell", search.text == "Search all 3" and search.enabled == true)

local many, single = nil, {}
ns.ShoppingLists = { SearchMany = function(_, ids, counts) many = { ids = ids, counts = counts }; return true end }
ns.UI.SearchAuctionHouse = function(_, id, count) single[#single + 1] = { id, count }; return true end
PostPanel:SearchAll()
check("all at once, vendor-only left out", many and #many.ids == 3 and many.ids[1] == 20
    and many.ids[2] == 23 and many.ids[3] == 24 and #single == 0)
check("each with its shortfall", many.counts[20] == 6 and many.counts[23] == 9 and many.counts[24] == 2)

ns.ShoppingLists.SearchMany = function() return false, "single" end
PostPanel:SearchAll()
check("one a search: the first, then Next", single[1][1] == 20 and single[1][2] == 6 and search.text == "Next 2/3")
PostPanel:SearchAll()
PostPanel:SearchAll()
check("Next walks the rest and ends", #single == 3 and single[3][1] == 24 and search.text == "Search all 3")

shopping = {}
said = nil
PostPanel:SearchAll()
check("nothing to look for: says so", said ~= nil and #single == 3)
PostPanel:UpdateSearchAll()
check("and greyed", search.text == "Search all" and search.enabled == false)

print(("\n%d check(s) passed\n"):format(checks))
