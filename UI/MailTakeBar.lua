-- Blackthornes Tradeskills -- UI/MailTakeBar.lua
-- Take buttons under the mailbox: Sales, Expired, Cancelled, All.
--
-- Ezmode (2026-10-07): "Buttons to withdraw Sales, Expired Auctions,
-- Cancelled Auctions." A strip hangs below the game's own inbox while it
-- shows, one button per kind of mail with how many are waiting. The button
-- that is running turns into Stop. Logic/MailTake.lua does the taking; the
-- haul report (UI/MailReport.lua) still says what came in. Setting:
-- mailTakeButtons, on by default, since it only adds buttons.

local _, ns = ...

local Theme = ns.Theme
local Widgets = ns.Widgets
local Util = ns.Util

local MailTakeBar = {}
ns.MailTakeBar = MailTakeBar

local PAD = 8
local GAP = 6
local BUTTON_HEIGHT = 22
local MIN_WIDTH = 300

-- Each button's wordings, longest first. %d is the count of mails.
local WORDS = {
    sales = { "Take sales (%d)", "Sales (%d)", "Sales" },
    expired = { "Take expired (%d)", "Expired (%d)", "Expired" },
    cancelled = { "Take cancelled (%d)", "Cancelled (%d)", "Cancelled" },
    all = { "Take all (%d)", "All (%d)", "All" },
}

local TIPS = {
    sales = "Takes the gold from every Auction successful mail.",
    expired = "Takes the items from every Auction expired mail.",
    cancelled = "Takes the items from every Auction cancelled mail.",
    all = "Takes gold and items from every mail, auction or not.",
}

local function Shown(frame)
    if not (frame and frame.IsShown) then return false end
    local ok, shown = pcall(frame.IsShown, frame)
    return ok and shown and true or false
end

--- Should the strip be up: setting on, the game's mailbox open on its inbox,
--- and the Tradeskills mailbox (when there is one) not standing in for it.
function MailTakeBar.ShouldShow()
    if ns.Config:Get("mailTakeButtons") == false then return false end
    if ns.MailWindow and ns.MailWindow.IsReplacing and ns.MailWindow:IsReplacing() then return false end
    if not Shown(_G.MailFrame) then return false end
    if _G.InboxFrame and not Shown(_G.InboxFrame) then return false end
    return true
end

local function Money(copper)
    return Util.FormatMoney(copper, { short = true })
end

--------------------------------------------------------------------------------
-- Building
--------------------------------------------------------------------------------

function MailTakeBar:Build()
    if self.frame then return self.frame end

    local bar = CreateFrame("Frame", nil, UIParent)
    bar:SetSize(MIN_WIDTH, 70)
    bar:SetFrameStrata("HIGH")
    bar:SetClampedToScreen(true)
    Theme.Fill(bar, "window", 0.94)
    Theme.Border(bar, "accent", 0.6)
    Theme.TopSheen(bar, 0.08)
    bar:Hide()

    bar.heading = Theme.CreateLabel(bar, "tiny", "accent")
    bar.heading:SetPoint("TOPLEFT", PAD, -6)
    bar.heading:SetText("TAKE FROM THE MAIL")

    bar.buttons = {}
    for _, group in ipairs(ns.MailTake.GROUPS) do
        local button = Widgets.CreateButton(bar, WORDS[group][3], function()
            MailTakeBar:Click(group)
        end, { width = 70, height = BUTTON_HEIGHT, primary = group == "all", fontSize = "small", tooltip = TIPS[group] })
        button.group = group
        bar.buttons[#bar.buttons + 1] = button
    end

    bar.status = Theme.CreateLabel(bar, "small", "muted")
    bar.status:SetPoint("BOTTOMLEFT", PAD, 6)
    bar.status:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", -PAD, 6)

    -- The mailbox can close, or switch to Send Mail, without the game
    -- telling addons. Checked twice a second.
    local since = 0
    bar:SetScript("OnUpdate", function(_, elapsed)
        since = since + (tonumber(elapsed) or 0)
        if since < 0.5 then return end
        since = 0
        if not MailTakeBar.ShouldShow() then
            bar:Hide()
        end
    end)

    self.frame = bar
    return bar
end

--- Below the inbox, as wide as it.
function MailTakeBar:Place()
    local bar = self.frame
    if not bar then return end

    local mailFrame = _G.MailFrame
    local width = MIN_WIDTH
    if mailFrame and mailFrame.GetWidth then
        local ok, frameWidth = pcall(mailFrame.GetWidth, mailFrame)
        if ok and type(frameWidth) == "number" and frameWidth > width then width = frameWidth end
    end
    bar:SetWidth(width)

    bar:ClearAllPoints()
    if mailFrame then
        bar:SetPoint("TOPLEFT", mailFrame, "BOTTOMLEFT", 0, -4)
    else
        bar:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 20, -560)
    end

    local count = #bar.buttons
    local buttonWidth = math.floor((width - 2 * PAD - (count - 1) * GAP) / count)
    for index, button in ipairs(bar.buttons) do
        button:SetWidth(buttonWidth)
        button:ClearAllPoints()
        button:SetPoint("TOPLEFT", bar, "TOPLEFT", PAD + (index - 1) * (buttonWidth + GAP), -20)
    end
    self.buttonWidth = buttonWidth
end

--------------------------------------------------------------------------------
-- Drawing
--------------------------------------------------------------------------------

--- The status line while a run goes, or after it stops.
local function RunText(run)
    local parts = {}
    if run.gold > 0 then parts[#parts + 1] = Money(run.gold) end
    if run.stacks > 0 then
        parts[#parts + 1] = run.stacks == 1 and "1 item" or ("%d items"):format(run.stacks)
    end
    local took = #parts > 0 and table.concat(parts, " and ") or "nothing"

    if not run.done then
        if run.waiting and run.more then
            return { ("Took %s. Waiting for the next %d mails..."):format(took, run.more), "Waiting for more mail..." }
        end
        return { ("Taking... %s so far"):format(took), "Taking..." }
    end

    local why = run.why
    if why == "bags" then return { ("Took %s. Your bags are full."):format(took), "Bags full." } end
    if why == "more" then
        return { ("Took %s. More mail is on its way: open the mailbox again in a minute."):format(took),
            ("Took %s. More is coming."):format(took) }
    end
    if why == "stopped" then return { ("Stopped. Took %s."):format(took), "Stopped." } end
    if why == "errors" then
        return { ("Took %s. The mail server is busy; try again in a moment."):format(took), "The mail is busy." }
    end
    if why == "refused" then
        return { ("Took %s. The game would not let the addon take mail."):format(took), "The game said no." }
    end
    return { ("Took %s."):format(took), "Done." }
end

function MailTakeBar:Refresh()
    if not self.ShouldShow() then
        if self.frame then self.frame:Hide() end
        return
    end

    local bar = self:Build()
    self:Place()

    local mails = ns.MailTake:ReadInbox()
    local run = ns.MailTake.run
    local room = (self.buttonWidth or 70) - 8

    for _, button in ipairs(bar.buttons) do
        local group = button.group
        local summary = ns.MailTake:Count(group, mails)
        if run and run.group == group then
            Theme.FitText(button.label, { "Stop" }, room)
            button.tooltipText = "Stops after the mail it is taking now."
            button:SetEnabledState(true)
        else
            local texts = {}
            for _, wording in ipairs(WORDS[group]) do
                texts[#texts + 1] = wording:find("%%d") and wording:format(summary.mails) or wording
            end
            Theme.FitText(button.label, texts, room)

            local tip = TIPS[group]
            if summary.gold > 0 then tip = tip .. "\nGold waiting: " .. Money(summary.gold) end
            if summary.items > 0 then tip = tip .. ("\nItems waiting: %d"):format(summary.items) end
            tip = tip .. "\nNever mail asking for payment (COD). Nothing is deleted."
            button.tooltipText = tip
            button:SetEnabledState(not run and summary.mails > 0)
        end
    end

    if run then
        Theme.FitText(bar.status, RunText(run), bar:GetWidth() - 2 * PAD)
    elseif self.lastRun then
        Theme.FitText(bar.status, RunText(self.lastRun), bar:GetWidth() - 2 * PAD)
    else
        local all = ns.MailTake:Count("all", mails)
        if all.mails == 0 then
            bar.status:SetText("Nothing to take.")
        else
            local parts = {}
            if all.gold > 0 then parts[#parts + 1] = Money(all.gold) end
            if all.items > 0 then parts[#parts + 1] = all.items == 1 and "1 item" or ("%d items"):format(all.items) end
            Theme.FitText(bar.status, { ("Waiting: %s"):format(table.concat(parts, " and ")), "" },
                bar:GetWidth() - 2 * PAD)
        end
    end

    bar:SetHeight(20 + BUTTON_HEIGHT + 24)
    bar:Show()
end

function MailTakeBar:Click(group)
    local run = ns.MailTake.run
    if run then
        if run.group == group then ns.MailTake:Stop() end
        return
    end

    self.lastRun = nil
    local started, why = ns.MailTake:Start(group, {
        onChange = function() MailTakeBar:RefreshSoon() end,
        onDone = function(done)
            MailTakeBar.lastRun = done
            MailTakeBar:RefreshSoon()
        end,
    })

    if not started and self.frame then
        Theme.FitText(self.frame.status, { "Can't take mail: " .. (why or "the mailbox is busy"), why or "" },
            self.frame:GetWidth() - 2 * PAD)
        return
    end
    self:Refresh()
end

--- One redraw for a burst of changes.
function MailTakeBar:RefreshSoon()
    if self.soon then return end
    self.soon = true
    local function Go()
        MailTakeBar.soon = false
        MailTakeBar:Refresh()
    end
    if C_Timer and C_Timer.After then C_Timer.After(0.2, Go) else Go() end
end

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------

ns.RegisterEvent(MailTakeBar, "MAIL_SHOW", function()
    MailTakeBar.lastRun = nil
    if C_Timer and C_Timer.After then
        C_Timer.After(0.6, function() MailTakeBar:Refresh() end)
    else
        MailTakeBar:Refresh()
    end
end)

ns.RegisterEvent(MailTakeBar, "MAIL_INBOX_UPDATE", function()
    MailTakeBar:RefreshSoon()
end)

ns.RegisterEvent(MailTakeBar, "MAIL_CLOSED", function()
    if MailTakeBar.frame then MailTakeBar.frame:Hide() end
end)

-- Back from Send Mail or a letter to the inbox.
if hooksecurefunc and _G.MailFrameTab_OnClick then
    pcall(hooksecurefunc, "MailFrameTab_OnClick", function() MailTakeBar:RefreshSoon() end)
end
