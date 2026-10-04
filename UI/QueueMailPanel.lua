-- Blackthornes Tradeskills -- UI/QueueMailPanel.lua
-- Beside the mailbox: what to send your other characters for the queue.
--
-- Asked 2026-10-03: "when you go to the mail it should allow you to auto
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

-- Quality words in the game's own rarity colours.
local QUALITY_WORDS = {
    [2] = "|cff1eff00green|r",
    [3] = "|cff0070ddblue|r",
    [4] = "|cffa335eepurple|r",
}

--- The disenchanter's row: how many of each quality, then just how many.
local function GearTexts(items)
    local byQuality, total = {}, 0
    for _, item in ipairs(items) do
        local quality = item.quality or 2
        byQuality[quality] = (byQuality[quality] or 0) + item.count
        total = total + item.count
    end

    local parts = {}
    for quality = 4, 2, -1 do
        if byQuality[quality] then
            parts[#parts + 1] = ("%d %s"):format(byQuality[quality], QUALITY_WORDS[quality])
        end
    end

    local joined = #parts > 1
        and (table.concat(parts, ", ", 1, #parts - 1) .. " and " .. parts[#parts])
        or parts[1] or ""
    return {
        joined .. " to disenchant",
        joined,
        total == 1 and "1 piece of gear" or ("%d pieces of gear"):format(total),
    }
end

--- The name a row's button and status use: the character's short name, or
--- the disenchanter's name as typed, without its realm.
local function ShortName(delivery)
    if delivery.to and ns.Recipes.GetShortCharacterName then
        return ns.Recipes:GetShortCharacterName(delivery.to)
    end
    local name = delivery.recipient or delivery.name or ""
    return name:match("^([^-]+)") or name
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
    panel.heading = heading

    local close = Widgets.CreateButton(panel, "X", function()
        QueueMailPanel.dismissed = true
        panel:Hide()
    end, { width = 18, height = 16, fontSize = "tiny", tooltip = "Hide this until the next mailbox visit" })
    close:SetPoint("TOPRIGHT", -4, -4)

    -- Asked 2026-10-04: the words under the heading were too many, and
    -- there was no way from here to the setting that picks the disenchanter.
    -- The Send button's tooltip says what it does; this goes to Settings.
    local settings = Widgets.CreateButton(panel, "Settings", function()
        if not ns.UI then return end
        ns.UI:Show()
        ns.UI:SelectTab("settings")
    end, { width = 60, height = 16, fontSize = "tiny",
        tooltip = "Pick your disenchanter and the best quality mailed to them" })
    local labelWidth = Theme.TextWidth and Theme.TextWidth(settings.label)
    if type(labelWidth) == "number" and labelWidth + 14 > 60 then
        settings:SetWidth(math.ceil(labelWidth) + 14)
    end
    settings:SetPoint("RIGHT", close, "LEFT", -6, 0)
    panel.settings = settings

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

--- What to list: the disenchanter's gear first, when one is set, then the
--- queue's deliveries, when the queue mail setting is on.
function QueueMailPanel:GetDeliveries()
    local deliveries = {}

    local okGear, gear = pcall(ns.QueueMail.GetDisenchantDelivery, ns.QueueMail)
    if okGear and gear then
        deliveries[1] = gear
    elseif not okGear then
        ns.Debug("disenchanter mail:", gear)
    end

    if ns.Config:Get("queueMailPanel") ~= false then
        local ok, queued = pcall(ns.QueueMail.GetDeliveries, ns.QueueMail)
        if ok then
            for _, delivery in ipairs(queued) do deliveries[#deliveries + 1] = delivery end
        else
            ns.Debug("queue mail:", queued)
        end
    end

    return deliveries, okGear and gear ~= nil
end

function QueueMailPanel:Refresh()
    if self.dismissed or not self.MailboxOpen() then return end

    local deliveries, hasGear = self:GetDeliveries()

    if #deliveries == 0 then
        if self.frame then self.frame:Hide() end
        return
    end

    local panel = self:Build()

    -- Headed for what is on it.
    local onlyGear = hasGear and #deliveries == 1
    local headingRoom = WIDTH - PAD - 4 - 18 - 6 - (panel.settings:GetWidth() or 60) - 8
    Theme.FitText(panel.heading, onlyGear and { "SEND TO YOUR DISENCHANTER", "DISENCHANTER" }
        or hasGear and { "SEND FROM YOUR BAGS", "SEND" }
        or { "SEND FOR THE CRAFT QUEUE", "FOR THE QUEUE" }, headingRoom)
    local room = WIDTH - 2 * PAD
    local top = -28

    for index, delivery in ipairs(deliveries) do
        if index > MAX_ROWS then break end
        local row = panel.rows[index] or CreateRow(panel, index)
        row.delivery = delivery

        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", PAD, top - (index - 1) * ROW_HEIGHT)

        local short = ShortName(delivery)
        if delivery.disenchant then
            Theme.FitText(row.name, { delivery.name .. ", disenchanter", short .. ", disenchanter", short },
                room - BUTTON_WIDTH - 8)
            Theme.FitText(row.items, GearTexts(delivery.items), room)
        else
            Theme.FitText(row.name, { delivery.name, short }, room - BUTTON_WIDTH - 8)
            Theme.FitText(row.items, ItemTexts(delivery.items), room)
        end
        local first = short:match("^(%S+)") or short
        Theme.FitText(row.send.label, { "Send to " .. short, "Send to " .. first, "Send" }, BUTTON_WIDTH - 8)
        row.send:SetEnabledState(not ns.QueueMail.filling)
        row:Show()
    end

    for index = math.min(#deliveries, MAX_ROWS) + 1, #panel.rows do
        panel.rows[index]:Hide()
        panel.rows[index].delivery = nil
    end

    local shownRows = math.min(#deliveries, MAX_ROWS)
    local height = 28 + shownRows * ROW_HEIGHT + 30

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
    local short = ShortName(delivery)
    self.lastFilled = delivery

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

-- A mail to someone who is not one of your characters (a disenchanter on
-- another account) is not written down by Logic/QueueMail.lua, so the panel
-- says it went itself.
ns.RegisterEvent(QueueMailPanel, "MAIL_SEND_SUCCESS", function()
    local panel, filled = QueueMailPanel.frame, QueueMailPanel.lastFilled
    QueueMailPanel.lastFilled = nil
    if panel and panel:IsShown() and filled and not filled.to then
        Theme.FitText(panel.status, { ("Sent to %s."):format(ShortName(filled)), "Sent." }, WIDTH - 2 * PAD)
        Soon(function() QueueMailPanel:Refresh() end)
    end
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
