-- Blackthornes Tradeskills -- UI/MailWindow.lua
-- The Tradeskills mailbox: a movable window in place of the game's own.
--
-- Ezmode (2026-10-07): "I might as well request a full replacement of the
-- Mailbox pane that is movable because it SUCKS." Off by default (setting
-- mailReplace), since some players like the game's mailbox as it is.
--
-- The game's mailbox can't simply be hidden: hiding it ends the mailbox
-- visit. So while this stands in, the game's window stays open but shrunk to
-- nothing and see-through, and this window shows instead. Unticking the
-- setting, "Use the game's mailbox" or the mailbox closing puts the game's
-- window back exactly as it was (scale, alpha, mouse).
--
--   Inbox  every mail, sorted sales first, then won and outbid, expired,
--          cancelled, letters and mail asking for payment. Click an auction
--          mail to take what's in it; click a letter to read it (Take,
--          Reply, Return). The Take buttons (Logic/MailTake.lua) along the
--          top. COD mail is never taken here: the reader sends you to the
--          game's mailbox to pay, where the game asks first.
--   Send   the game's own Send Mail page, moved into this window. Its fields,
--          postage, attaching by right-click and the Send button are the
--          game's, so sending is always the player's own click, and the
--          craft queue's Send to buttons (Logic/QueueMail.lua) fill it the
--          same way.
--
-- Nothing here deletes mail.

local _, ns = ...

local Theme = ns.Theme
local Widgets = ns.Widgets
local Util = ns.Util

local MailWindow = {}
ns.MailWindow = MailWindow

local WIDTH = 400
local HEIGHT = 540
local PAD = 14
local TOP = 46
-- Taller with Text size Large or Larger (Theme.TextStep), so the two
-- lines of a row keep apart.
local function RowHeight()
    local step = Theme.TextStep and Theme.TextStep() or 0
    return 38 + 3 * (tonumber(step) or 0)
end
local ICON = 30
local BUTTON_HEIGHT = 22
local GAP = 6

-- Sorting: what most people come to the mailbox for comes first.
local ORDER = { sold = 1, won = 2, outbid = 3, expired = 4, removed = 5, other = 6, cod = 7 }

local KIND_WORDS = {
    sold = { "Sold", "profit" },
    won = { "Won", "accent" },
    outbid = { "Outbid", "muted" },
    expired = { "Expired", "warn" },
    removed = { "Cancelled", "warn" },
}

local COIN_ICON = [[Interface\Icons\INV_Misc_Coin_01]]
local LETTER_ICON = [[Interface\Icons\INV_Letter_15]]

local function Call(fn, ...)
    if type(fn) ~= "function" then return false end
    return pcall(fn, ...)
end

local function Shown(frame)
    if not (frame and frame.IsShown) then return false end
    local ok, shown = pcall(frame.IsShown, frame)
    return ok and shown and true or false
end

local function Money(copper)
    return Util.FormatMoney(copper, { short = true })
end

--------------------------------------------------------------------------------
-- Standing in for the game's mailbox
--------------------------------------------------------------------------------

--- Is the Tradeskills mailbox standing in for the game's right now?
function MailWindow:IsReplacing()
    return self.replacing == true
end

--- What windows beside the mailbox (the queue panel, the haul tally)
--- should sit against.
function MailWindow:Anchor()
    if self.replacing and self.frame then return self.frame end
    return _G.MailFrame
end

--- The game's mailbox out of sight, still open.
local function HideStock()
    local stock = _G.MailFrame
    if not stock or MailWindow.saved then return end

    local saved = {}
    local ok, scale = pcall(stock.GetScale, stock)
    saved.scale = ok and scale or 1
    ok, saved.alpha = pcall(stock.GetAlpha, stock)
    if not ok then saved.alpha = 1 end
    if stock.IsMouseEnabled then
        local okMouse, mouse = pcall(stock.IsMouseEnabled, stock)
        saved.mouse = okMouse and mouse
    end
    MailWindow.saved = saved

    Call(stock.SetScale, stock, 0.001)
    Call(stock.SetAlpha, stock, 0)
    Call(stock.EnableMouse, stock, false)
end

local function ShowStock()
    local stock, saved = _G.MailFrame, MailWindow.saved
    if not stock or not saved then return end
    MailWindow.saved = nil

    Call(stock.SetScale, stock, saved.scale or 1)
    Call(stock.SetAlpha, stock, saved.alpha or 1)
    if saved.mouse ~= nil then Call(stock.EnableMouse, stock, saved.mouse) end
end

--- The game's Send Mail page, into this window or back where it was.
local function BorrowSendPage(body)
    local page = _G.SendMailFrame
    if not page or MailWindow.sendSaved then return end

    local saved = { points = {} }
    local okParent, parent = pcall(page.GetParent, page)
    saved.parent = okParent and parent or _G.MailFrame
    local okCount, count = pcall(page.GetNumPoints, page)
    for index = 1, (okCount and count or 0) do
        saved.points[index] = { page:GetPoint(index) }
    end
    MailWindow.sendSaved = saved

    Call(page.SetParent, page, body)
    Call(page.ClearAllPoints, page)
    Call(page.SetPoint, page, "TOP", body, "TOP", 0, 0)
end

local function ReturnSendPage()
    local page, saved = _G.SendMailFrame, MailWindow.sendSaved
    if not page or not saved then return end
    MailWindow.sendSaved = nil

    Call(page.SetParent, page, saved.parent)
    Call(page.ClearAllPoints, page)
    for _, point in ipairs(saved.points) do
        Call(page.SetPoint, page, unpack(point))
    end
end

--- The game's own tab switch, so its pages show and hide as they should.
local function StockTab(tab)
    local button = _G["MailFrameTab" .. tab]
    if _G.MailFrameTab_OnClick then
        Call(_G.MailFrameTab_OnClick, button, tab)
    elseif button and button.Click then
        Call(button.Click, button)
    end
end

--- Take over from the game's mailbox for this visit.
function MailWindow:Begin()
    if self.replacing then return end
    if ns.Config:Get("mailReplace") ~= true or self.declined then return end
    if not (Shown(_G.MailFrame) or (ns.Mail and ns.Mail.isOpen)) then return end

    local frame = self:Build()
    self.replacing = true
    HideStock()
    self:RestorePosition()
    frame:Show()
    if ns.Titanforged then ns.Titanforged:Opened(frame) end
    self:SelectTab("inbox")
    if ns.MailTakeBar and ns.MailTakeBar.frame then ns.MailTakeBar.frame:Hide() end
    if ns.QueueMailPanel then
        ns.QueueMailPanel.anchoredTo = nil
        Call(ns.QueueMailPanel.Place, ns.QueueMailPanel)
    end
end

--- Give the mailbox back to the game. `keepOpen` leaves the visit going
--- (the setting turned off, or "Use the game's mailbox").
function MailWindow:End(keepOpen)
    if not self.replacing then return end
    self.replacing = false
    self.ending = true

    ReturnSendPage()
    ShowStock()
    if keepOpen then StockTab(1) end
    if self.frame then self.frame:Hide() end
    self.ending = false

    if keepOpen then
        if ns.MailTakeBar then Call(ns.MailTakeBar.Refresh, ns.MailTakeBar) end
        if ns.QueueMailPanel then
            ns.QueueMailPanel.anchoredTo = nil
            Call(ns.QueueMailPanel.Place, ns.QueueMailPanel)
        end
    end
end

--------------------------------------------------------------------------------
-- Building
--------------------------------------------------------------------------------

function MailWindow:SavePosition()
    if not (ns.db and self.frame) then return end
    local point, _, relativePoint, x, y = self.frame:GetPoint()
    ns.db.mailWindowPosition = { point = point, relativePoint = relativePoint, x = x, y = y }
end

function MailWindow:RestorePosition()
    local frame = self.frame
    if not frame then return end
    local position = ns.db and ns.db.mailWindowPosition
    frame:ClearAllPoints()
    if type(position) == "table" and position.point then
        frame:SetPoint(position.point, UIParent, position.relativePoint or position.point,
            tonumber(position.x) or 0, tonumber(position.y) or 0)
    else
        frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 40, -110)
    end
end

local function CreateMailRow(list, index)
    local row = CreateFrame("Button", nil, list)
    row:SetHeight(RowHeight())
    row:RegisterForClicks("LeftButtonUp")
    row.background = Theme.Fill(row, "row")
    row.hover = Theme.Fill(row, "rowHover")
    row.hover:SetAlpha(0)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(ICON, ICON)
    row.icon:SetPoint("LEFT", 4, 0)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    row.count = Theme.CreateLabel(row, "tiny", "text", "RIGHT")
    row.count:SetPoint("BOTTOMRIGHT", row.icon, "BOTTOMRIGHT", -1, 1)

    row.right = Theme.CreateLabel(row, "small", "text", "RIGHT")
    row.right:SetPoint("TOPRIGHT", -6, -5)
    row.right:SetWidth(110)

    row.title = Theme.CreateLabel(row, "small", "text")
    row.title:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 8, -1)
    row.title:SetPoint("RIGHT", row.right, "LEFT", -6, 0)

    row.detail = Theme.CreateLabel(row, "tiny", "muted")
    row.detail:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 8, 1)
    row.detail:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -6, 6)

    row:SetScript("OnEnter", function(self)
        self.hover:SetAlpha(1)
        if self.mail and GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            local ok = false
            if self.mail.firstSlot then
                ok = pcall(GameTooltip.SetInboxItem, GameTooltip, self.mail.index, self.mail.firstSlot)
            end
            if not ok then GameTooltip:SetText(self.mail.subject or "Mail") end
            GameTooltip:AddLine(self.hint, 1, 0.82, 0, true)
            GameTooltip:Show()
        end
    end)
    row:SetScript("OnLeave", function(self)
        self.hover:SetAlpha(0)
        if GameTooltip then GameTooltip:Hide() end
    end)
    row:SetScript("OnClick", function(self)
        if self.mail then MailWindow:ClickMail(self.mail) end
    end)

    list.rows[index] = row
    return row
end

function MailWindow:BuildInbox(page)
    -- The Take buttons, as under the game's inbox.
    page.takeButtons = {}
    local words = {
        sales = { "Sales (%d)", "Sales" },
        expired = { "Expired (%d)", "Expired" },
        cancelled = { "Cancelled (%d)", "Cancelled" },
        all = { "Take all (%d)", "All (%d)", "All" },
    }
    local tips = {
        sales = "Takes the gold from every Auction successful mail.",
        expired = "Takes the items from every Auction expired mail.",
        cancelled = "Takes the items from every Auction cancelled mail.",
        all = "Takes gold and items from every mail, auction or not.",
    }
    local count = #ns.MailTake.GROUPS
    local buttonWidth = math.floor((WIDTH - 2 * PAD - (count - 1) * GAP) / count)
    for index, group in ipairs(ns.MailTake.GROUPS) do
        local button = Widgets.CreateButton(page, words[group][#words[group]], function()
            MailWindow:ClickTake(group)
        end, { width = buttonWidth, height = BUTTON_HEIGHT, primary = group == "all",
            fontSize = "small", tooltip = tips[group] })
        button:SetPoint("TOPLEFT", page, "TOPLEFT", (index - 1) * (buttonWidth + GAP), 0)
        button.group, button.words, button.tip = group, words[group], tips[group]
        page.takeButtons[#page.takeButtons + 1] = button
    end
    page.buttonWidth = buttonWidth

    local list = CreateFrame("Frame", nil, page)
    list:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -(BUTTON_HEIGHT + 8))
    list:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", 0, 22)
    list.background = Theme.Fill(list, "panel")
    Theme.Recess(list)
    list.rows = {}
    list.offset = 0
    list:EnableMouseWheel(true)
    list:SetScript("OnMouseWheel", function(_, delta)
        list.offset = math.max(0, list.offset - delta * 3)
        MailWindow:RefreshInbox()
    end)
    page.list = list

    list.empty = Theme.CreateLabel(list, "small", "muted", "CENTER")
    list.empty:SetPoint("CENTER")
    list.empty:SetText("Your mailbox is empty.")

    page.status = Theme.CreateLabel(page, "small", "muted")
    page.status:SetPoint("BOTTOMLEFT", 0, 4)
    page.status:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", 0, 4)

    self:BuildReader(page)
end

--- A letter, open over the list: its words, what it carries, and what you
--- can do with it.
function MailWindow:BuildReader(page)
    local reader = CreateFrame("Frame", nil, page)
    reader:SetPoint("TOPLEFT", page.list, "TOPLEFT", 0, 0)
    reader:SetPoint("BOTTOMRIGHT", page.list, "BOTTOMRIGHT", 0, 0)
    reader:SetFrameLevel(page.list:GetFrameLevel() + 10)
    reader.background = Theme.Fill(reader, "panel")
    Theme.Recess(reader)
    reader:EnableMouse(true)
    reader:Hide()

    reader.from = Theme.CreateLabel(reader, "small", "accent")
    reader.from:SetPoint("TOPLEFT", 10, -10)
    reader.from:SetPoint("TOPRIGHT", reader, "TOPRIGHT", -10, -10)

    reader.subject = Theme.CreateLabel(reader, "normal", "text")
    reader.subject:SetPoint("TOPLEFT", reader.from, "BOTTOMLEFT", 0, -4)
    reader.subject:SetPoint("TOPRIGHT", reader.from, "BOTTOMRIGHT", 0, -4)

    reader.body = Theme.CreateLabel(reader, "small", "text")
    reader.body:SetPoint("TOPLEFT", reader.subject, "BOTTOMLEFT", 0, -10)
    reader.body:SetPoint("RIGHT", reader, "RIGHT", -10, 0)
    reader.body:SetHeight(200)
    reader.body:SetWordWrap(true)
    reader.body:SetJustifyV("TOP")

    reader.slots = {}
    for slot = 1, 12 do
        local button = CreateFrame("Button", nil, reader)
        button:SetSize(30, 30)
        local column, line = (slot - 1) % 8, math.floor((slot - 1) / 8)
        button:SetPoint("BOTTOMLEFT", reader, "BOTTOMLEFT", 10 + column * 34, 74 - line * 34)
        button.icon = button:CreateTexture(nil, "ARTWORK")
        button.icon:SetAllPoints(button)
        button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        button.count = Theme.CreateLabel(button, "tiny", "text", "RIGHT")
        button.count:SetPoint("BOTTOMRIGHT", -1, 1)
        button:SetScript("OnEnter", function(self)
            if not (GameTooltip and reader.mail and self.slot) then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if not pcall(GameTooltip.SetInboxItem, GameTooltip, reader.mail.index, self.slot) then
                GameTooltip:SetText("Attachment")
            end
            GameTooltip:Show()
        end)
        button:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        button:Hide()
        reader.slots[slot] = button
    end

    reader.money = Theme.CreateLabel(reader, "small", "text")
    reader.money:SetPoint("BOTTOMLEFT", 10, 40)

    local buttonWidth = math.floor((WIDTH - 2 * PAD - 20 - 3 * GAP) / 4)
    reader.back = Widgets.CreateButton(reader, "Back", function() MailWindow:CloseReader() end,
        { width = buttonWidth, height = BUTTON_HEIGHT, tooltip = "Back to the inbox" })
    reader.back:SetPoint("BOTTOMLEFT", 10, 10)

    reader.reply = Widgets.CreateButton(reader, "Reply", function() MailWindow:Reply() end,
        { width = buttonWidth, height = BUTTON_HEIGHT, tooltip = "Write back to whoever sent it" })
    reader.reply:SetPoint("LEFT", reader.back, "RIGHT", GAP, 0)

    reader.returnButton = Widgets.CreateButton(reader, "Return", function() MailWindow:ReturnMail() end,
        { width = buttonWidth, height = BUTTON_HEIGHT, danger = true,
            tooltip = "Sends it back to whoever sent it, with what it carries. Click twice." })
    reader.returnButton:SetPoint("LEFT", reader.reply, "RIGHT", GAP, 0)

    reader.take = Widgets.CreateButton(reader, "Take all", function()
        if reader.mail then MailWindow:TakeOne(reader.mail) end
    end, { width = buttonWidth, height = BUTTON_HEIGHT, primary = true,
        tooltip = "Takes the gold and items from this mail" })
    reader.take:SetPoint("LEFT", reader.returnButton, "RIGHT", GAP, 0)

    page.reader = reader
end

function MailWindow:Build()
    if self.frame then return self.frame end

    local frame = CreateFrame("Frame", "BlackthornesTSMailWindow", UIParent)
    frame:SetSize(WIDTH, HEIGHT)
    frame:SetFrameStrata("HIGH")
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    if frame.SetToplevel then frame:SetToplevel(true) end
    frame:Hide()
    Theme.Fill(frame, "window")

    if ns.Titanforged then
        local trim = ns.Titanforged:Dress(frame, {
            title = "Mailbox",
            portrait = true,
            close = function() frame:Hide() end,
        })
        local left, right, top = ns.Titanforged.Reach(trim)
        if frame.SetClampRectInsets then frame:SetClampRectInsets(-left, right, top, -32) end
    end
    Theme.Halo(frame, 10, 0.12)

    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        MailWindow:SavePosition()
    end)

    -- Closing this window closes the mailbox, as closing the game's does.
    -- Escape too.
    frame:SetScript("OnHide", function()
        if MailWindow.ending or not MailWindow.replacing then return end
        MailWindow:End(false)
        if _G.HideUIPanel and _G.MailFrame then
            Call(_G.HideUIPanel, _G.MailFrame)
        elseif _G.CloseMail then
            Call(_G.CloseMail)
        end
    end)
    if UISpecialFrames then table.insert(UISpecialFrames, "BlackthornesTSMailWindow") end

    -- Back to the game's own window, for this visit only.
    local stock = Widgets.CreateButton(frame, "Use the game's mailbox", function()
        MailWindow.declined = true
        MailWindow:End(true)
    end, { height = 16, fontSize = "tiny",
        tooltip = "Shows the game's mailbox until you next open one. Settings turns this window off for good." })
    local labelWidth = Theme.TextWidth and Theme.TextWidth(stock.label)
    stock:SetWidth(type(labelWidth) == "number" and math.ceil(labelWidth) + 16 or 150)
    stock:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PAD, -(TOP - 22))
    frame.stockButton = stock

    local body = CreateFrame("Frame", nil, frame)
    body:SetPoint("TOPLEFT", PAD, -TOP)
    body:SetPoint("BOTTOMRIGHT", -PAD, PAD)
    frame.body = body

    local inbox = CreateFrame("Frame", nil, body)
    inbox:SetAllPoints(body)
    frame.inbox = inbox
    self.frame = frame
    self:BuildInbox(inbox)

    local send = CreateFrame("Frame", nil, frame)
    send:SetPoint("TOPLEFT", 6, -(TOP - 4))
    send:SetPoint("BOTTOMRIGHT", -6, 6)
    send:Hide()
    frame.send = send

    local strip = Widgets.CreateTabStrip(frame, {
        { key = "inbox", text = "Inbox" },
        { key = "send", text = "Send Mail" },
    }, function(key) MailWindow:SelectTab(key) end, { width = 200, hanging = true })
    strip:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 16, 0)
    frame.tabs = strip

    -- The inbox changes as mail arrives and leaves; checked twice a second
    -- for a mailbox that closed without the game telling addons.
    local since = 0
    frame:SetScript("OnUpdate", function(_, elapsed)
        since = since + (tonumber(elapsed) or 0)
        if since < 0.5 then return end
        since = 0
        if not (ns.Mail and ns.Mail.isOpen) and not Shown(_G.MailFrame) then frame:Hide() end
    end)

    return frame
end

--------------------------------------------------------------------------------
-- Tabs
--------------------------------------------------------------------------------

function MailWindow:SelectTab(key)
    local frame = self.frame
    if not frame then return end
    self.tab = key
    if frame.tabs.Select then frame.tabs:Select(key) end

    if key == "send" then
        frame.inbox:Hide()
        frame.stockButton:Hide()
        self.switching = true
        StockTab(2)
        self.switching = false
        BorrowSendPage(frame.send)
        frame.send:Show()
    else
        frame.send:Hide()
        ReturnSendPage()
        self.switching = true
        StockTab(1)
        self.switching = false
        frame.inbox:Show()
        frame.stockButton:Show()
        self:RefreshInbox()
    end
end

--------------------------------------------------------------------------------
-- The inbox
--------------------------------------------------------------------------------

--- The inbox as rows, sorted.
function MailWindow:GetMails()
    local mails, total, shown = ns.MailTake:ReadInbox()
    for _, mail in ipairs(mails) do
        local okHeader, packageIcon, _, _, _, _, _, daysLeft = Call(_G.GetInboxHeaderInfo, mail.index)
        if okHeader then
            if type(packageIcon) == "number" or type(packageIcon) == "string" then mail.packageIcon = packageIcon end
            local okDays, days = pcall(function() return tonumber(daysLeft) end)
            mail.daysLeft = okDays and days or nil
        end
        if mail.itemCount > 0 and ns.Mail and ns.Mail.ReadAttachment then
            for slot = 1, 16 do
                local ok, itemID, quantity = pcall(ns.Mail.ReadAttachment, ns.Mail, mail.index, slot)
                if ok and itemID then
                    mail.firstSlot, mail.firstItem = mail.firstSlot or slot, mail.firstItem or itemID
                    mail.units = (mail.units or 0) + (quantity or 1)
                end
            end
        end
        if mail.cod > 0 then mail.kind = "cod" end
        local subject = mail.subject or ""
        mail.itemName = subject:match(":%s*(.+)$")
    end

    table.sort(mails, function(a, b)
        local orderA, orderB = ORDER[a.kind] or 6, ORDER[b.kind] or 6
        if orderA ~= orderB then return orderA < orderB end
        return a.index < b.index
    end)
    return mails, total, shown
end

local function DaysText(days)
    if not days then return nil end
    if days < 1 then return "|cffff4040expires today|r" end
    local whole = math.floor(days)
    return whole == 1 and "1 day left" or ("%d days left"):format(whole)
end

local function DrawRow(row, mail, room)
    row.mail = mail

    local icon = mail.firstItem and Util.GetItemIcon and Util.GetItemIcon(mail.firstItem)
        or mail.packageIcon
        or (mail.money > 0 and COIN_ICON) or LETTER_ICON
    row.icon:SetTexture(icon)
    row.count:SetText((mail.units or 0) > 1 and tostring(mail.units) or "")

    local words = KIND_WORDS[mail.kind]
    if words then
        row.title:SetTextColor(Theme.Unpack(words[2]))
        Theme.FitText(row.title, { words[1] .. ": " .. (mail.itemName or mail.subject or ""), words[1] }, room)
    elseif mail.kind == "cod" then
        row.title:SetTextColor(Theme.Unpack("loss"))
        Theme.FitText(row.title, { "Pay to open: " .. (mail.subject or ""), "Pay to open" }, room)
    else
        row.title:SetTextColor(Theme.Unpack("text"))
        Theme.FitText(row.title, { mail.subject ~= "" and mail.subject or "(no subject)" }, room)
    end

    local parts = { mail.sender or "" }
    local days = DaysText(mail.daysLeft)
    if days then parts[#parts + 1] = days end
    row.detail:SetText(table.concat(parts, ", "))

    if mail.kind == "cod" then
        row.right:SetText("|cffff4040COD|r " .. Money(mail.cod))
        row.hint = "Asks for payment. Read it, then pay in the game's mailbox."
    elseif mail.money > 0 then
        Theme.SetMoneyText(row.right, mail.money, { short = true })
        row.hint = words and "Click to take the gold." or "Click to read it."
    elseif mail.itemCount > 0 then
        row.right:SetText(mail.itemCount == 1 and "1 item" or ("%d items"):format(mail.itemCount))
        row.hint = words and "Click to take it." or "Click to read it."
    else
        row.right:SetText("")
        row.hint = "Click to read it."
    end
end

function MailWindow:RefreshInbox()
    local frame = self.frame
    if not (frame and frame:IsShown() and self.tab ~= "send") then return end
    local page = frame.inbox
    local list = page.list

    local mails, total, shown = self:GetMails()
    self.mails = mails

    local height = list:GetHeight()
    local rowHeight = RowHeight()
    local visible = math.max(1, math.floor(((type(height) == "number" and height > 0) and height or 400) / rowHeight))
    list.offset = math.max(0, math.min(list.offset, #mails - visible))

    local room = WIDTH - 2 * PAD - ICON - 8 - 4 - 110 - 12
    for index = 1, visible do
        local mail = mails[list.offset + index]
        local row = list.rows[index] or (mail and CreateMailRow(list, index))
        if row then
            if mail then
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", list, "TOPLEFT", 2, -2 - (index - 1) * rowHeight)
                row:SetPoint("RIGHT", list, "RIGHT", -2, 0)
                DrawRow(row, mail, room)
                row:Show()
            else
                row:Hide()
                row.mail = nil
            end
        end
    end
    for index = visible + 1, #list.rows do list.rows[index]:Hide() end
    list.empty:SetShown(#mails == 0)

    -- The Take buttons.
    local run = ns.MailTake.run
    for _, button in ipairs(page.takeButtons) do
        local summary = ns.MailTake:Count(button.group, mails)
        if run and run.group == button.group then
            Theme.FitText(button.label, { "Stop" }, page.buttonWidth - 8)
            button.tooltipText = "Stops after the mail it is taking now."
            button:SetEnabledState(true)
        else
            local texts = {}
            for _, wording in ipairs(button.words) do
                texts[#texts + 1] = wording:find("%%d") and wording:format(summary.mails) or wording
            end
            Theme.FitText(button.label, texts, page.buttonWidth - 8)
            local tip = button.tip
            if summary.gold > 0 then tip = tip .. "\nGold waiting: " .. Money(summary.gold) end
            if summary.items > 0 then tip = tip .. ("\nItems waiting: %d"):format(summary.items) end
            button.tooltipText = tip .. "\nNever mail asking for payment (COD). Nothing is deleted."
            button:SetEnabledState(not run and summary.mails > 0)
        end
    end

    -- The line under the list.
    local statusRoom = WIDTH - 2 * PAD
    if self.statusText and (run or self.statusHold) then
        Theme.FitText(page.status, self.statusText, statusRoom)
    elseif total and shown and total > shown then
        Theme.FitText(page.status, { ("Showing %d of %d. The rest come in as you take mail."):format(shown, total),
            ("%d of %d shown"):format(shown, total) }, statusRoom)
    else
        Theme.FitText(page.status, { #mails == 1 and "1 mail" or ("%d mails"):format(#mails) }, statusRoom)
    end

    if page.reader:IsShown() then self:RefreshReader() end
end

--- What a run has done, for the line under the list.
local function RunText(run)
    local parts = {}
    if run.gold > 0 then parts[#parts + 1] = Money(run.gold) end
    if run.stacks > 0 then parts[#parts + 1] = run.stacks == 1 and "1 item" or ("%d items"):format(run.stacks) end
    local took = #parts > 0 and table.concat(parts, " and ") or "nothing"

    if not run.done then
        if run.waiting and run.more then
            return { ("Took %s. Waiting for the next %d mails..."):format(took, run.more), "Waiting for more mail..." }
        end
        return { ("Taking... %s so far"):format(took), "Taking..." }
    end
    local why = run.why
    if why == "bags" then return { ("Took %s. Your bags are full."):format(took), "Bags full." } end
    if why == "more" then return { ("Took %s. More mail is on its way: open the mailbox again in a minute."):format(took), "More is coming." } end
    if why == "stopped" then return { ("Stopped. Took %s."):format(took), "Stopped." } end
    if why == "errors" then return { ("Took %s. The mail server is busy; try again in a moment."):format(took), "The mail is busy." } end
    if why == "refused" then return { ("Took %s. The game would not let the addon take mail."):format(took), "The game said no." } end
    return { ("Took %s."):format(took), "Done." }
end

function MailWindow:RunOptions()
    return {
        onChange = function(run)
            MailWindow.statusText = RunText(run)
            MailWindow.statusHold = run.done
            MailWindow:RefreshSoon()
        end,
    }
end

function MailWindow:Say(texts)
    self.statusText, self.statusHold = texts, true
    self:RefreshInbox()
end

function MailWindow:ClickTake(group)
    local run = ns.MailTake.run
    if run then
        if run.group == group then ns.MailTake:Stop() end
        return
    end
    local started, why = ns.MailTake:Start(group, self:RunOptions())
    if not started then return self:Say({ "Can't take mail: " .. (why or "the mailbox is busy"), why or "" }) end
    self:RefreshInbox()
end

function MailWindow:TakeOne(mail)
    if ns.MailTake.run then return self:Say({ "Still taking mail. Stop that first.", "Busy." }) end
    local started, why = ns.MailTake:StartOne(mail.index, self:RunOptions())
    if not started then return self:Say({ "Can't take it: " .. (why or "the mailbox is busy"), why or "" }) end
    self:RefreshInbox()
end

--- An auction mail is taken; anything else is opened to read.
function MailWindow:ClickMail(mail)
    if KIND_WORDS[mail.kind] and (mail.money > 0 or mail.itemCount > 0) then
        return self:TakeOne(mail)
    end
    self:OpenReader(mail)
end

--------------------------------------------------------------------------------
-- Reading a letter
--------------------------------------------------------------------------------

function MailWindow:OpenReader(mail)
    local reader = self.frame.inbox.reader
    reader.mail = { index = mail.index, sender = mail.sender, subject = mail.subject }
    reader.confirmReturn = false
    reader:Show()
    self:RefreshReader()
end

function MailWindow:CloseReader()
    local reader = self.frame and self.frame.inbox.reader
    if not reader then return end
    reader:Hide()
    reader.mail = nil
    self:RefreshInbox()
end

--- The letter as the inbox has it now, or nil when it has gone.
local function CurrentLetter(wanted)
    for _, mail in ipairs((ns.MailTake:ReadInbox())) do
        if mail.index == wanted.index and mail.sender == wanted.sender and mail.subject == wanted.subject then
            return mail
        end
    end
end

function MailWindow:RefreshReader()
    local reader = self.frame.inbox.reader
    local wanted = reader.mail
    if not wanted then return reader:Hide() end

    local mail = CurrentLetter(wanted)
    if not mail then return self:CloseReader() end

    Theme.FitText(reader.from, { "From " .. (mail.sender or "?"), mail.sender or "?" }, WIDTH - 2 * PAD - 20)
    Theme.FitText(reader.subject, { mail.subject ~= "" and mail.subject or "(no subject)" }, WIDTH - 2 * PAD - 20)

    -- Reading the words marks the letter read, as opening it in the game's
    -- mailbox does.
    local okText, text = Call(_G.GetInboxText, mail.index)
    reader.body:SetText(okText and type(text) == "string" and text or "")

    for slot, button in ipairs(reader.slots) do
        local itemID, quantity
        if ns.Mail and ns.Mail.ReadAttachment then
            local ok, id, units = pcall(ns.Mail.ReadAttachment, ns.Mail, mail.index, slot)
            if ok then itemID, quantity = id, units end
        end
        if itemID then
            button.slot = slot
            button.icon:SetTexture(Util.GetItemIcon and Util.GetItemIcon(itemID) or LETTER_ICON)
            button.count:SetText((quantity or 1) > 1 and tostring(quantity) or "")
            button:Show()
        else
            button.slot = nil
            button:Hide()
        end
    end

    if mail.cod > 0 then
        reader.money:SetText("|cffff4040Asks " .. Money(mail.cod) .. " to open.|r Pay in the game's mailbox.")
    elseif mail.money > 0 then
        reader.money:SetText("Gold: " .. Money(mail.money))
    else
        reader.money:SetText("")
    end

    local canTake = mail.cod == 0 and (mail.money > 0 or mail.itemCount > 0)
    reader.take:SetEnabledState(canTake and not ns.MailTake.run)
    if mail.cod > 0 then
        Theme.FitText(reader.take.label, { "Pay in game's", "Pay" }, reader.take:GetWidth() - 8)
        reader.take.tooltipText = "Payment on delivery: use Use the game's mailbox to pay and take it."
    else
        Theme.FitText(reader.take.label, { "Take all", "Take" }, reader.take:GetWidth() - 8)
        reader.take.tooltipText = "Takes the gold and items from this mail"
    end

    -- Only a player's mail goes back; the auction house's can't.
    local isPlayer = mail.kind == "other" or mail.kind == "cod"
    reader.reply:SetEnabledState(isPlayer and mail.sender ~= nil)
    reader.returnButton:SetEnabledState(isPlayer and (mail.money > 0 or mail.itemCount > 0 or mail.cod > 0))
    Theme.FitText(reader.returnButton.label, reader.confirmReturn and { "Sure? Click", "Sure?" } or { "Return" },
        reader.returnButton:GetWidth() - 8)
end

function MailWindow:Reply()
    local reader = self.frame.inbox.reader
    local wanted = reader.mail
    if not wanted then return end
    self:SelectTab("send")
    local nameBox, subjectBox = _G.SendMailNameEditBox, _G.SendMailSubjectEditBox
    if nameBox then Call(nameBox.SetText, nameBox, wanted.sender or "") end
    if subjectBox and wanted.subject and wanted.subject ~= "" then
        local prefix = _G.MAIL_REPLY_PREFIX or "RE:"
        local subject = wanted.subject
        if subject:sub(1, #prefix) ~= prefix then subject = prefix .. " " .. subject end
        Call(subjectBox.SetText, subjectBox, subject)
    end
end

--- Return to sender, on the second click.
function MailWindow:ReturnMail()
    local reader = self.frame.inbox.reader
    local wanted = reader.mail
    if not wanted then return end
    if not reader.confirmReturn then
        reader.confirmReturn = true
        return self:RefreshReader()
    end
    reader.confirmReturn = false

    local mail = CurrentLetter(wanted)
    if not mail then return self:CloseReader() end
    if ns.MailHaul and ns.MailHaul.NoteReturned then pcall(ns.MailHaul.NoteReturned, ns.MailHaul, mail.index) end
    local ok = Call(_G.ReturnInboxItem, mail.index)
    self:CloseReader()
    self:Say(ok and { ("Returned to %s."):format(mail.sender or "the sender"), "Returned." }
        or { "The game would not return it.", "Not returned." })
end

--------------------------------------------------------------------------------
-- Redrawing
--------------------------------------------------------------------------------

function MailWindow:RefreshSoon()
    if self.soon then return end
    self.soon = true
    local function Go()
        MailWindow.soon = false
        MailWindow:RefreshInbox()
    end
    if C_Timer and C_Timer.After then C_Timer.After(0.2, Go) else Go() end
end

--- The setting changed in Settings.
function MailWindow:SettingChanged()
    if ns.Config:Get("mailReplace") == true then
        self.declined = false
        self:Begin()
    else
        self:End(true)
    end
end

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------

ns.RegisterEvent(MailWindow, "MAIL_SHOW", function()
    MailWindow.declined = false
    if ns.Config:Get("mailReplace") ~= true then return end
    -- The game shows its mailbox on this same event; take over just after.
    if C_Timer and C_Timer.After then
        C_Timer.After(0, function() MailWindow:Begin() end)
    else
        MailWindow:Begin()
    end
end)

ns.RegisterEvent(MailWindow, "MAIL_CLOSED", function()
    MailWindow:End(false)
end)

ns.RegisterEvent(MailWindow, "MAIL_INBOX_UPDATE", function()
    if MailWindow.replacing then MailWindow:RefreshSoon() end
end)

-- Something else asked the game's mailbox for Send Mail (the craft queue's
-- Send to buttons): follow it here.
if hooksecurefunc and _G.MailFrameTab_OnClick then
    pcall(hooksecurefunc, "MailFrameTab_OnClick", function(button, tab)
        if not MailWindow.replacing or MailWindow.switching then return end
        if tab == nil and button and button.GetID then
            local ok, id = pcall(button.GetID, button)
            tab = ok and id or nil
        end
        if tab == 2 and MailWindow.tab ~= "send" then
            MailWindow:SelectTab("send")
        end
    end)
end
