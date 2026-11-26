-- Blackthornes Tradeskills -- UI/TidyUpBox.lua
-- The Tidy Up window: what a tidy would remove, and Confirm before it does.
--
-- The owner said build it (2026-11-26, idea 4, from the mockup and its
-- words). Opened by Tidy Up on the Data page, and by picking 30 days, 90
-- days or a year for Keep Price History For. Nothing is removed and no
-- choice is saved until Confirm (Logic/TidyUp.lua). Cancel or the close gem
-- leaves everything as it was.

local _, ns = ...
local L = ns.L or setmetatable({ Format = string.format }, { __index = function(_, key) return key end })

local TidyUpBox = ns.NewModule("TidyUpBox")

local Theme = ns.Theme
local Widgets = ns.Widgets

local WIDTH = 380
local INSET = 18
local ROW_HEIGHT = 44
local BUTTON_WIDTH = 100

-- How a choice reads in the window's line.
function TidyUpBox.PeriodText(days)
    if days == 30 then return L["30 days"] end
    if days == 90 then return L["90 days"] end
    if days == 365 then return L["a year"] end
    return ""
end

local function Row(frame, index)
    local row = CreateFrame("Frame", nil, frame)
    row:SetHeight(ROW_HEIGHT)
    row.back = row:CreateTexture(nil, "BACKGROUND")
    row.back:SetAllPoints()
    row.back:SetColorTexture(Theme.Unpack(index % 2 == 1 and "glass" or "glassAlt"))
    row.rule = row:CreateTexture(nil, "BORDER")
    row.rule:SetPoint("BOTTOMLEFT")
    row.rule:SetPoint("BOTTOMRIGHT")
    row.rule:SetHeight(1)
    row.rule:SetColorTexture(Theme.Unpack("border"))
    row.rule:SetAlpha(0.6)

    row.value = Theme.CreateLabel(row, "small", "text", "RIGHT")
    row.value:SetPoint("RIGHT", row, "RIGHT", -10, 0)
    row.value:SetWordWrap(false)

    row.name = Theme.CreateLabel(row, "small", "text")
    row.name:SetPoint("TOPLEFT", 10, -7)
    row.name:SetPoint("RIGHT", row.value, "LEFT", -8, 0)
    row.name:SetWordWrap(true)

    row.note = Theme.CreateLabel(row, "tiny", "muted")
    row.note:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -3)
    row.note:SetPoint("RIGHT", row.value, "LEFT", -8, 0)
    row.note:SetWordWrap(true)
    return row
end

function TidyUpBox:Build()
    if self.frame then return self.frame end

    local frame = CreateFrame("Frame", "BlackthornesTSTidyUpBox", UIParent)
    frame:SetSize(WIDTH, 220)
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
        ns.Titanforged:Dress(frame, { close = function() TidyUpBox:Cancel() end })
    else
        Theme.AddGameOutline(frame, { style = "dialog", color = "natural" })
    end
    if Theme.Halo then Theme.Halo(frame, 10, 0.10) end
    if type(UISpecialFrames) == "table" then tinsert(UISpecialFrames, "BlackthornesTSTidyUpBox") end
    -- Escape closes it like Cancel: the choice goes back to what it was.
    frame:SetScript("OnHide", function()
        if TidyUpBox.open then TidyUpBox:Cancel() end
    end)

    local title = Theme.CreateLabel(frame, "normal", "text")
    title:SetPoint("TOPLEFT", INSET, -18)
    title:SetText(L["Tidy Up"])
    self.title = title

    local heading = Theme.CreateLabel(frame, "small", "accent")
    heading:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -10)
    heading:SetText(L["Tidy up saved data"])
    self.heading = heading

    self.old = Row(frame, 1)
    self.old:SetPoint("TOPLEFT", heading, "BOTTOMLEFT", 0, -8)
    self.old:SetWidth(WIDTH - INSET * 2)
    self.old.name:SetText(L["Old price readings"])

    self.kept = Row(frame, 2)
    self.kept:SetPoint("TOPLEFT", self.old, "BOTTOMLEFT", 0, 0)
    self.kept:SetWidth(WIDTH - INSET * 2)
    self.kept.name:SetText(L["Your sales, mail, gold and settings"])
    self.kept.note:SetText(L["Nothing of these is touched"])
    self.kept.value:SetText(L["kept"])
    self.kept.value:SetTextColor(Theme.Unpack("profit"))

    self.confirm = Widgets.CreateButton(frame, L["Confirm"], function() TidyUpBox:Confirm() end,
        { width = BUTTON_WIDTH, height = 24, primary = true })
    self.confirm:SetPoint("TOPRIGHT", self.kept, "BOTTOMRIGHT", 0, -12)

    self.cancel = Widgets.CreateButton(frame, L["Cancel"], function() TidyUpBox:Cancel() end,
        { width = BUTTON_WIDTH, height = 24 })
    self.cancel:SetPoint("RIGHT", self.confirm, "LEFT", -8, 0)

    self.frame = frame
    if ns.SharedWindow and ns.SharedWindow.KeepSpot then ns.SharedWindow.KeepSpot(frame, "ts.tidyup") end
    return frame
end

--- Show what a tidy at `days` would remove. `onCancel` runs when the
--- player cancels or closes it; `onDone(tally)` after Confirm's tidy.
function TidyUpBox:Open(days, onCancel, onDone)
    local TidyUp = ns.TidyUp
    days = TidyUp and TidyUp.Valid(days) or 0
    if days == 0 then return false end
    local frame = self:Build()
    self.days, self.onCancel, self.onDone, self.open = days, onCancel, onDone, true
    self.ask = (self.ask or 0) + 1
    local ask = self.ask

    self.old.note:SetText(L.Format("Older than %s, for items you don't craft, star or sell",
        TidyUpBox.PeriodText(days)))
    self.old.value:SetText("...")
    self.confirm:SetEnabledState(false)

    frame:ClearAllPoints()
    frame:SetPoint("CENTER")
    frame:Show()
    if ns.Titanforged and ns.Titanforged.Opened then pcall(ns.Titanforged.Opened, ns.Titanforged, frame) end
    self:FitHeight()

    TidyUp:Find(days, nil, function(tally)
        if ask ~= TidyUpBox.ask or not TidyUpBox.open then return end
        TidyUpBox.found = tally
        local any = tally.rows > 0 or tally.readings > 0
        TidyUpBox.old.value:SetText(any and L.Format("about %s", TidyUp.FormatSize(tally.bytes)) or L["None"])
        TidyUpBox.confirm:SetEnabledState(true)
    end)
    return true
end

function TidyUpBox:Close()
    self.open = false
    if self.frame then self.frame:Hide() end
end

function TidyUpBox:Cancel()
    local onCancel = self.onCancel
    self.onCancel, self.onDone = nil, nil
    self:Close()
    if onCancel then pcall(onCancel) end
end

--- Confirm: keep the choice and tidy now.
function TidyUpBox:Confirm()
    local days, onDone = self.days, self.onDone
    self.onCancel, self.onDone = nil, nil
    self:Close()
    if not (days and ns.TidyUp) then return end
    ns.TidyUp:Confirm(days, nil, function(tally)
        if tally.rows > 0 or tally.readings > 0 then
            ns.Print(L.Format("tidied up about %s of old price readings", ns.TidyUp.FormatSize(tally.bytes)))
        end
        if onDone then pcall(onDone, tally) end
    end)
end

function TidyUpBox:IsShown()
    return self.frame ~= nil and self.frame:IsShown()
end

--- Grow the box to its rows, whatever the text size.
function TidyUpBox:FitHeight()
    local function Height(label)
        local ok, height = pcall(label.GetStringHeight, label)
        return ok and type(height) == "number" and height or 14
    end
    local function RowHeight(row)
        return math.max(ROW_HEIGHT, math.ceil(7 + Height(row.name) + 3 + Height(row.note) + 7))
    end
    local oldHeight, keptHeight = RowHeight(self.old), RowHeight(self.kept)
    self.old:SetHeight(oldHeight)
    self.kept:SetHeight(keptHeight)
    self.frame:SetHeight(math.ceil(18 + Height(self.title) + 10 + Height(self.heading) + 8
        + oldHeight + keptHeight + 12 + 24 + 18))
end
