-- Blackthornes Tradeskills -- UI/QueueMailPanel.lua
-- Beside the mailbox: what to send your other characters for the queue.
--
-- Trent, 2026-10-03: "when you go to the mail it should allow you to auto
-- send materials this character has to the one that needs it". One row per
-- character, with what to send and a Send to button that opens Send Mail,
-- fills in the name and attaches the items. The player presses Send: mail
-- costs postage and cannot be taken back. Logic/QueueMail.lua works out
-- what goes where; this only draws it.

local _, ns = ...

local Theme = ns.Theme
local Widgets = ns.Widgets
local Util = ns.Util

local QueueMailPanel = {}
ns.QueueMailPanel = QueueMailPanel

local WIDTH = 286
local PAD = 12
local ROW_HEIGHT = 44
local BUTTON_WIDTH = 112
local MAX_ROWS = 5

--------------------------------------------------------------------------------
-- Building
--------------------------------------------------------------------------------

local function ItemName(itemID)
    return Util.Uncolored(Util.GetItemLabel(itemID))
end

--- The items line, longest wording first, so the row can take the first
--- that fits: every item, then the first and a count, then a count.
local function ItemTexts(items)
    local parts = {}
    local total = 0
    for index, item in ipairs(items) do
        parts[index] = ("%d %s"):format(item.count, ItemName(item.itemID))
        total = total + item.count
    end

    local texts = { table.concat(parts, ", ") }
    if #parts > 1 then
        texts[#texts + 1] = ("%s and %d more"):format(parts[1], #parts - 1)
    end
    texts[#texts + 1] = total == 1 and "1 item" or ("%d items"):format(total)
    return texts
end

local function CreateRow(panel, index)
    local row = CreateFrame("Frame", nil, panel)
    row:SetSize(WIDTH - 2 * PAD, ROW_HEIGHT)

    row.name = Theme.CreateLabel(row, "normal", "text")
    row.name:SetPoint("TOPLEFT", 0, -6)
    row.name:SetPoint("TOPRIGHT", row, "TOPRIGHT", -(BUTTON_WIDTH + 8), -6)

    row.items = Theme.CreateLabel(row, "small", "muted")
    row.items:SetPoint("TOPLEFT", 0, -24)
    row.items:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, -24)

    row.send = Widgets.CreateButton(row, "Send", function()
        if row.delivery then QueueMailPanel:FillFor(row) end
    end, { width = BUTTON_WIDTH, height = 20, primary = true,
        tooltip = "Opens Send Mail with the name filled in and these attached. You press Send." })
    row.send:SetPoint("TOPRIGHT", 0, -3)

    row.rule = Theme.CreateDivider(row)
    row.rule:SetPoint("BOTTOMLEFT", 0, 0)
    row.rule:SetPoint("BOTTOMRIGHT", 0, 0)

    panel.rows[index] = row
    return row
end

function QueueMailPanel:Build()
    if self.frame then return self.frame end

    local panel = CreateFrame("Frame", nil, UIParent)
    panel:SetSize(WIDTH, 100)
    panel:SetFrameStrata("HIGH")
    panel:SetClampedToScreen(true)
    Theme.Fill(panel, "window", 0.94)
    Theme.Border(panel, "accent", 0.6)
    Theme.AccentStripe(panel, 3)
    Theme.TopSheen(panel, 0.08)
    Theme.Halo(panel, 6, 0.14)
    panel:Hide()

    local heading = Theme.CreateLabel(panel, "tiny", "accent")
    heading:SetPoint("TOPLEFT", PAD, -8)
    heading:SetText("SEND FOR THE CRAFT QUEUE")

    local close = Widgets.CreateButton(panel, "X", function()
        QueueMailPanel.dismissed = true
        panel:Hide()
    end, { width = 18, height = 16, fontSize = "tiny", tooltip = "Hide this until the next mailbox visit" })
    close:SetPoint("TOPRIGHT", -4, -4)

    local hint = Theme.CreateLabel(panel, "tiny", "muted")
    hint:SetPoint("TOPLEFT", PAD, -22)
    hint:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -PAD, -22)
    hint:SetText("Your other characters need these. The button fills in the mail; you press Send.")
    hint:SetWordWrap(true)
    hint:SetJustifyV("TOP")
    hint:SetHeight(26)

    panel.rows = {}

    panel.more = Theme.CreateLabel(panel, "tiny", "muted")

    panel.status = Theme.CreateLabel(panel, "small", "accent")
    panel.status:SetPoint("BOTTOMLEFT", PAD, 8)
    panel.status:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -PAD, 8)

    -- The mailbox can close without the game saying so, and a mail being
    -- read opens beside it. Checked once a second.
    local since = 0
    panel:SetScript("OnUpdate", function(_, elapsed)
        since = since + (tonumber(elapsed) or 0)
        if since < 1 then return end
        since = 0
        if not QueueMailPanel.MailboxOpen() then
            panel:Hide()
        else
            QueueMailPanel:Place()
        end
    end)

    self.frame = panel
    return panel
end

--------------------------------------------------------------------------------
-- Placing
--------------------------------------------------------------------------------

function QueueMailPanel.MailboxOpen()
    local mailFrame = _G.MailFrame
    if mailFrame and mailFrame.IsShown then
        local ok, shown = pcall(mailFrame.IsShown, mailFrame)
        if ok then return shown and true or false end
    end
    return ns.Mail and ns.Mail.isOpen == true
end

local function Shown(frame)
    if not (frame and frame.IsShown) then return false end
    local ok, shown = pcall(frame.IsShown, frame)
    return ok and shown and true or false
end

--- To the right of the mailbox, or of the open letter when one is open, so
--- neither is covered.
function QueueMailPanel:Place()
    local panel = self.frame
    if not panel then return end

    local anchor = Shown(_G.OpenMailFrame) and _G.OpenMailFrame or _G.MailFrame
    if anchor == self.anchoredTo then return end
    self.anchoredTo = anchor

    panel:ClearAllPoints()
    if anchor then
        panel:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 8, 0)
    else
        panel:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 420, -110)
    end
end

--------------------------------------------------------------------------------
-- Drawing
--------------------------------------------------------------------------------

function QueueMailPanel:Refresh()
    if ns.Config:Get("queueMailPanel") == false then
        if self.frame then self.frame:Hide() end
        return
    end
    if self.dismissed or not self.MailboxOpen() then return end

    local ok, deliveries = pcall(ns.QueueMail.GetDeliveries, ns.QueueMail)
    if not ok then
        ns.Debug("queue mail:", deliveries)
        deliveries = {}
    end

    if #deliveries == 0 then
        if self.frame then self.frame:Hide() end
        return
    end

    local panel = self:Build()
    local room = WIDTH - 2 * PAD
    local top = -52

    for index, delivery in ipairs(deliveries) do
        if index > MAX_ROWS then break end
        local row = panel.rows[index] or CreateRow(panel, index)
        row.delivery = delivery

        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", PAD, top - (index - 1) * ROW_HEIGHT)

        local short = ns.Recipes.GetShortCharacterName
            and ns.Recipes:GetShortCharacterName(delivery.to) or delivery.name
        Theme.FitText(row.name, { delivery.name, short }, room - BUTTON_WIDTH - 8)
        Theme.FitText(row.send.label, { "Send to " .. short, "Fill mail" }, BUTTON_WIDTH - 8)
        Theme.FitText(row.items, ItemTexts(delivery.items), room)
        row.send:SetEnabledState(not ns.QueueMail.filling)
        row:Show()
    end

    for index = math.min(#deliveries, MAX_ROWS) + 1, #panel.rows do
        panel.rows[index]:Hide()
        panel.rows[index].delivery = nil
    end

    local shownRows = math.min(#deliveries, MAX_ROWS)
    local height = 52 + shownRows * ROW_HEIGHT + 30

    panel.more:ClearAllPoints()
    if #deliveries > MAX_ROWS then
        panel.more:SetPoint("TOPLEFT", PAD, top - shownRows * ROW_HEIGHT - 4)
        panel.more:SetText(("and %d more after these are sent"):format(#deliveries - MAX_ROWS))
        panel.more:Show()
        height = height + 16
    else
        panel.more:Hide()
    end

    panel:SetHeight(height)
    self:Place()
    panel:Show()
end

--- The postage the game asks for the mail as it stands, or nil.
local function Postage()
    if type(GetSendMailPrice) ~= "function" then return nil end
    local ok, price = pcall(function() return GetSendMailPrice() + 0 end)
    if ok then return price end
end

function QueueMailPanel:FillFor(row)
    local panel = self.frame
    local delivery = row.delivery
    local short = ns.Recipes.GetShortCharacterName
        and ns.Recipes:GetShortCharacterName(delivery.to) or delivery.name

    local started, why = ns.QueueMail:Fill(delivery, function(attached, leftOver)
        if not panel then return end

        local postage = Postage()
        local cost = postage and postage > 0
            and (" Postage " .. Util.FormatMoney(postage, { short = true }) .. ".") or ""

        local texts
        if attached == 0 and leftOver == 0 then
            texts = { ("Name filled in. Drag the items in for %s."):format(short), "Drag the items in." }
        elseif leftOver > 0 then
            texts = { ("%d attached; the rest go in the next mail.%s Press Send."):format(attached, cost),
                ("%d attached. Press Send."):format(attached) }
        else
            texts = { ("All attached.%s Press Send."):format(cost), "Press Send." }
        end
        Theme.FitText(panel.status, texts, WIDTH - 2 * PAD)
        QueueMailPanel:Refresh()
    end)

    if not started then
        Theme.FitText(panel.status, { "Can't fill the mail: " .. (why or "the mailbox is busy"), why or "" },
            WIDTH - 2 * PAD)
        return
    end

    Theme.FitText(panel.status, { ("Filling a mail for %s..."):format(short), "Filling..." }, WIDTH - 2 * PAD)
    for _, other in ipairs(panel.rows) do other.send:SetEnabledState(false) end
end

--- A mail to one of your characters went. Logic/QueueMail.lua calls this.
function QueueMailPanel:OnSent(toKey)
    local panel = self.frame
    if panel then
        local short = ns.Recipes.GetShortCharacterName
            and ns.Recipes:GetShortCharacterName(toKey) or ns.Recipes:GetCharacterName(toKey)
        Theme.FitText(panel.status, { ("Sent to %s."):format(short), "Sent." }, WIDTH - 2 * PAD)
    end
    self:Refresh()
end

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------

local function Soon(fn)
    if C_Timer and C_Timer.After then C_Timer.After(0.6, fn) else fn() end
end

ns.RegisterEvent(QueueMailPanel, "MAIL_SHOW", function()
    QueueMailPanel.dismissed = false
    QueueMailPanel.anchoredTo = nil
    if QueueMailPanel.frame then QueueMailPanel.frame.status:SetText("") end
    -- A moment for the inbox to be read, so what is waiting there counts.
    Soon(function() QueueMailPanel:Refresh() end)
end)

ns.RegisterEvent(QueueMailPanel, "MAIL_CLOSED", function()
    if QueueMailPanel.frame then QueueMailPanel.frame:Hide() end
end)

-- Items going into a mail and coming out of the bags change what is left.
ns.RegisterEvent(QueueMailPanel, "BAG_UPDATE_DELAYED", function()
    if QueueMailPanel.frame and QueueMailPanel.frame:IsShown() and not ns.QueueMail.filling then
        QueueMailPanel:Refresh()
    end
end)
