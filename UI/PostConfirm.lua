-- Blackthornes Tradeskills -- UI/PostConfirm.lua
-- The "List It / Skip" question before a listing, in a window of our own.
--
-- It used to be the game's own pop-up (StaticPopup_Show). Showing that box
-- from an addon leaves it marked as the addon's, and the game lends the same
-- box to its own questions later. A Spellstone listing (2026-11-19) was
-- blocked that way: "Blackthornes_TS has been blocked from an action only
-- available to the Blizzard UI", when the game asked to replace the
-- weapon's enchant in the box we had used. So nothing here touches the game's
-- pop-ups, and tools/test_gamepopup.lua keeps it so.
--
-- The words, the item's icon beside them and the two buttons are as before.
-- List It lists from inside its own click, which posting needs. Escape and
-- the close gem are Skip, like the old box. A newer question replaces an
-- open one without listing or skipping it.

local _, ns = ...
local L = ns.L or setmetatable({ Format = string.format }, { __index = function(_, key) return key end })

local Theme = ns.Theme
local Widgets = ns.Widgets

local PostConfirm = {}
ns.PostConfirm = PostConfirm

PostConfirm.FRAME_NAME = "BlackthornesTSConfirmPost"
PostConfirm.WIDTH = 420
PostConfirm.ICON = 36
-- The question mark, for an item whose icon the game has not got yet.
PostConfirm.UNKNOWN_ICON = 134400
-- Where the game's own box sat, so the question shows where it always did.
PostConfirm.FROM_TOP = -135

local PAD = 20
local GAP = 12
local BUTTON_HEIGHT = 22

local function Build()
    local titan = ns.Titanforged
    local window = Theme.CreatePanel(UIParent, "window", not titan and "accent" or false)
    if window.SetSize then window:SetSize(PostConfirm.WIDTH, 140) end
    window:SetFrameStrata("DIALOG")
    window:SetClampedToScreen(true)
    window:EnableMouse(true)
    window:SetMovable(true)
    window:RegisterForDrag("LeftButton")
    window:SetScript("OnDragStart", window.StartMoving)
    window:SetScript("OnDragStop", window.StopMovingOrSizing)
    window.top = titan and -34 or -PAD
    if titan then
        titan:Dress(window, { title = L["Auction House"], close = function() PostConfirm:Skip() end })
    else
        Theme.TopSheen(window, 0.08)
    end
    Theme.Halo(window, 8, 0.24)

    window.icon = window:CreateTexture(nil, "ARTWORK")
    window.icon:SetSize(PostConfirm.ICON, PostConfirm.ICON)
    window.icon:SetPoint("TOPLEFT", window, "TOPLEFT", PAD, window.top)

    window.text = Theme.CreateLabel(window, "normal", "text", "CENTER")
    window.text:SetPoint("TOPLEFT", window, "TOPLEFT", PAD + PostConfirm.ICON + GAP, window.top)
    window.text:SetWidth(PostConfirm.WIDTH - (PAD + PostConfirm.ICON + GAP) - PAD)

    window.listIt = Widgets.CreateButton(window, L["List It"], function() PostConfirm:Accept() end,
        { width = 110, height = BUTTON_HEIGHT, primary = true })
    window.skip = Widgets.CreateButton(window, L["Skip"], function() PostConfirm:Skip() end,
        { width = 110, height = BUTTON_HEIGHT })
    window.listIt:SetPoint("BOTTOMRIGHT", window, "BOTTOM", -4, 14)
    window.skip:SetPoint("BOTTOMLEFT", window, "BOTTOM", 4, 14)

    -- Hidden any other way (Escape, a closed UI) is a Skip, as the old box was.
    window:SetScript("OnHide", function()
        if PostConfirm.ask then PostConfirm:Skip() end
    end)

    window:Hide()
    if type(UISpecialFrames) == "table" and type(tinsert) == "function" then
        tinsert(UISpecialFrames, PostConfirm.FRAME_NAME)
    end
    return window
end

local function Height(region)
    local ok, height = pcall(function()
        return (region.GetStringHeight and region:GetStringHeight()) or region:GetHeight()
    end)
    return ok and tonumber(height) or 0
end

--- Ask about one listing.
--- ask = { text, itemID, data, accept = fn(data), skip = fn(data) }
--- Returns the window, or nil when it could not be made.
function PostConfirm:Show(ask)
    if type(ask) ~= "table" then return nil end
    if not self.window then
        local ok, window = pcall(Build)
        if not ok or not window then return nil end
        -- Escape looks for the window by name.
        _G[self.FRAME_NAME] = window
        self.window = window
    end
    local window = self.window

    -- A newer question takes the place of an open one, which is neither
    -- listed nor skipped.
    self.ask = ask

    window.text:SetText(ask.text or "")
    local icon = ask.itemID and ns.Util and ns.Util.GetItemIcon and ns.Util.GetItemIcon(ask.itemID)
    window.icon:SetTexture(icon or self.UNKNOWN_ICON)
    window.icon:Show()

    local body = math.max(self.ICON, Height(window.text))
    window:SetHeight(-window.top + body + GAP + BUTTON_HEIGHT + 14 + 6)

    window:ClearAllPoints()
    window:SetPoint("TOP", UIParent, "TOP", 0, self.FROM_TOP)
    window:Show()
    if window.Raise then pcall(window.Raise, window) end
    return window
end

function PostConfirm:IsShown()
    local window = self.window
    return (window and self.ask and window:IsShown()) and true or false
end

--- Take the question down without listing or skipping (the auction house
--- closed).
function PostConfirm:Close()
    self.ask = nil
    if self.window then self.window:Hide() end
end

--- List It. Runs inside the button's click, as posting needs.
function PostConfirm:Accept()
    local ask = self.ask
    self.ask = nil
    if self.window then self.window:Hide() end
    if ask and type(ask.accept) == "function" then ask.accept(ask.data) end
end

function PostConfirm:Skip()
    local ask = self.ask
    self.ask = nil
    if self.window then self.window:Hide() end
    if ask and type(ask.skip) == "function" then ask.skip(ask.data) end
end
