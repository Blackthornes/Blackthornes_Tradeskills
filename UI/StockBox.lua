-- Blackthornes Tradeskills -- UI/StockBox.lua
-- The Keep in Stock box (a player asked, the owner said build it from a
-- mockup, 2026-11-17): a small window to set how many of a craft to keep
-- listed and on hand, opened with an Alt-click on a craft pane row or from
-- a Profit row's menu. It writes the same number the Profit detail pane's
-- box does (ns.Auctions:SetLimit), so nothing new is saved.

local _, ns = ...
local L = ns.L or setmetatable({ Format = string.format }, { __index = function(_, key) return key end })

local StockBox = ns.NewModule("StockBox")

local Theme = ns.Theme
local Widgets = ns.Widgets
local Util = ns.Util

local WIDTH = 300
local INSET = 18
local BUTTON_WIDTH = 100
local MOST = 999

--- The usual number for an item with none of its own: its profession's
--- from Settings, else the usual amount. Returns the number and, when it
--- is a profession's, that profession's name as the client shows it.
function StockBox.Usual(itemID)
    local Auctions = ns.Auctions
    local byProfession = ns.db and ns.db.professionStockLimits
    if Auctions and Auctions.ProfessionOf and type(byProfession) == "table" and next(byProfession) ~= nil then
        local ok, profession = pcall(Auctions.ProfessionOf, Auctions, itemID)
        local limit = ok and profession and tonumber(byProfession[profession])
        if limit then
            local label = Auctions.ProfessionLabel and Auctions:ProfessionLabel(profession) or profession
            return limit, label
        end
    end
    return tonumber(ns.Config and ns.Config:Get("maxPostedPerItem")) or 0, nil
end

--- The item's own number, or nil when it uses the usual one.
function StockBox.Own(itemID)
    local limits = ns.db and ns.db.postLimits
    return type(limits) == "table" and tonumber(limits[itemID]) or nil
end

--- How many you have: bags, bank and the mailbox. Listed ones are not
--- counted here; they have a column of their own.
function StockBox.Have(itemID)
    if not (ns.Auctions and ns.Auctions.GetRoom) then return 0 end
    local ok, _, _, onHand, _, _, inMail = pcall(ns.Auctions.GetRoom, ns.Auctions, itemID)
    if not ok then return 0 end
    return (tonumber(onHand) or 0) + (tonumber(inMail) or 0)
end

--- Where the number comes from, in the words the Profit detail pane uses.
function StockBox.SourceTip(itemID)
    local own = StockBox.Own(itemID)
    if own then
        local raised = ns.SellOut and ns.SellOut.GetRaised and ns.SellOut:GetRaised(itemID)
        if raised and raised.to == own and raised.lowered then
            return L.Format("Lowered from %d to %d because it came back unsold 3 times in a row. Click x to use the usual number again.",
                raised.from or 0, raised.to or 0)
        elseif raised and raised.to == own then
            return L.Format("Raised from %d to %d because every copy you listed sold. Click x to use the usual number again.",
                raised.from or 0, raised.to or 0)
        end
        return L["Set for this item only. Click x to use the usual number again."]
    end
    local _, profession = StockBox.Usual(itemID)
    if profession then
        return L.Format("From %s in Settings. Type a number to set it for this item only.", profession)
    end
    return L["The usual amount from Settings. Type a number to set it for this item only."]
end

--- The box's note: what you have and what an empty box goes back to.
function StockBox.Note(itemID)
    local have = StockBox.Have(itemID)
    local usual, profession = StockBox.Usual(itemID)
    if profession then
        return L.Format("You have %d. %s in Settings keeps %d. Empty uses that again.", have, profession, usual)
    end
    return L.Format("You have %d. The usual amount is %d. Empty uses that again.", have, usual)
end

--- The box's title line, the item's name in its rarity colour.
function StockBox.Title(itemID, label)
    local name = label or Util.GetItemLabel(itemID) or ("#" .. tostring(itemID))
    local r, g, b = Util.GetItemQualityColor(itemID)
    if r and type(name) == "string" and not name:find("|c") then
        name = ("|cff%02x%02x%02x%s|r"):format(math.floor(r * 255 + 0.5),
            math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5), name)
    end
    return L.Format("Keep in stock: %s", name)
end

--- Write a number for the item, or nil (and 0) for the usual one again:
--- the detail pane's box treats 0 the same way.
function StockBox.Write(itemID, value)
    if not (itemID and ns.Auctions and ns.Auctions.SetLimit) then return end
    value = tonumber(value)
    ns.Auctions:SetLimit(itemID, value and value > 0 and math.min(MOST, math.floor(value)) or nil)
end

function StockBox:Build()
    if self.frame then return self.frame end

    local frame = CreateFrame("Frame", "BlackthornesTSStockBox", UIParent)
    frame:SetSize(WIDTH, 190)
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:Hide()

    Theme.Fill(frame, "window")
    if ns.Titanforged then
        ns.Titanforged:Dress(frame, { title = L["Keep in Stock"], close = function() StockBox:Hide() end })
    else
        Theme.AddGameOutline(frame, { style = "dialog", color = "natural" })
    end
    Theme.Halo(frame, 10, 0.10)
    if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, "BlackthornesTSStockBox") end

    local title = Theme.CreateLabel(frame, "normal", "text")
    title:SetPoint("TOPLEFT", INSET, -26)
    title:SetPoint("RIGHT", frame, "RIGHT", -INSET - 16, 0)
    title:SetWordWrap(true)
    title:SetJustifyH("LEFT")
    self.title = title

    local label = Theme.CreateLabel(frame, "small", "accent")
    label:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -12)
    label:SetText(L["Keep:"])
    self.label = label

    self.minus = Widgets.CreateButton(frame, "-", function() StockBox:Step(-1) end,
        { width = 22, height = 22 })
    self.minus:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -6)

    self.box = Widgets.CreateNumberBox(frame, {
        width = 60, height = 22, min = 0, max = MOST, background = "panel",
        justify = "CENTER", allowEmpty = true, placeholder = "",
    })
    self.box:SetPoint("LEFT", self.minus, "RIGHT", 6, 0)
    self.box.editBox:HookScript("OnEnterPressed", function() StockBox:Save() end)

    self.plus = Widgets.CreateButton(frame, "+", function() StockBox:Step(1) end,
        { width = 22, height = 22 })
    self.plus:SetPoint("LEFT", self.box, "RIGHT", 6, 0)

    local note = Theme.CreateLabel(frame, "small", "muted")
    note:SetPoint("TOPLEFT", self.minus, "BOTTOMLEFT", 0, -10)
    note:SetWidth(WIDTH - INSET * 2)
    note:SetWordWrap(true)
    note:SetJustifyH("LEFT")
    self.note = note

    self.confirm = Widgets.CreateButton(frame, L["Confirm"], function() StockBox:Save() end,
        { width = BUTTON_WIDTH, height = 24, primary = true })
    self.confirm:SetPoint("TOPRIGHT", note, "BOTTOMRIGHT", 0, -12)

    self.usual = Widgets.CreateButton(frame, L["Use Usual"], function() StockBox:UseUsual() end,
        { width = BUTTON_WIDTH, height = 24 })
    self.usual:SetPoint("RIGHT", self.confirm, "LEFT", -8, 0)

    self.frame = frame
    if ns.SharedWindow and ns.SharedWindow.KeepSpot then ns.SharedWindow.KeepSpot(frame, "ts.stockbox") end
    return frame
end

--- Open the box for the item a craft makes. A craft that makes nothing to
--- hold (an enchant) has no number, so nothing opens.
-- @return true when the box opened
function StockBox:Open(itemID, name, anchor)
    if not itemID or not (ns.Auctions and ns.Auctions.SetLimit) then return false end
    local frame = self:Build()
    self.itemID = itemID

    self.title:SetText(StockBox.Title(itemID, name))
    local usual = StockBox.Usual(itemID)
    self.box:SetPlaceholder(tostring(usual))
    self.box:SetValue(StockBox.Own(itemID), true)
    self.note:SetText(StockBox.Note(itemID))

    frame:ClearAllPoints()
    if anchor and anchor.GetRight then
        frame:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 8, 0)
    else
        frame:SetPoint("CENTER")
    end
    frame:Show()
    if ns.Titanforged and ns.Titanforged.Opened then pcall(ns.Titanforged.Opened, ns.Titanforged, frame) end
    self:FitHeight()
    return true
end

--- The -/+ buttons: one less or one more, from the usual number when the
--- box is empty.
function StockBox:Step(by)
    if not self.box then return end
    local current = tonumber(self.box.editBox:GetText()) or StockBox.Usual(self.itemID)
    self.box:SetValue(math.max(0, math.min(MOST, current + by)), true)
end

function StockBox:Hide()
    if self.frame then self.frame:Hide() end
    self.itemID = nil
end

function StockBox:IsShown()
    return self.frame ~= nil and self.frame:IsShown()
end

--- Save the number typed (empty uses the usual one again) and close.
function StockBox:Save()
    local itemID = self.itemID
    if not itemID then return end
    local edit = self.box.editBox
    if type(edit.HasFocus) == "function" and edit:HasFocus() then edit:ClearFocus() end
    local value = tonumber(edit:GetText())
    self:Hide()
    StockBox.Write(itemID, value)
end

--- Use Usual: clear this item's own number and close.
function StockBox:UseUsual()
    local itemID = self.itemID
    if not itemID then return end
    self:Hide()
    StockBox.Write(itemID, nil)
end

--- Grow the box to its title and note, whatever the text size.
function StockBox:FitHeight()
    local frame = self.frame
    local function Height(label)
        local ok, height = pcall(label.GetStringHeight, label)
        return ok and type(height) == "number" and height or 14
    end
    frame:SetHeight(math.ceil(26 + Height(self.title) + 12 + Height(self.label) + 6 + 22
        + 10 + Height(self.note) + 12 + 24 + 16))
end
