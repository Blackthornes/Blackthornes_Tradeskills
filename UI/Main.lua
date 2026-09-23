-- Blackthornes Tradeskills -- UI/Main.lua
-- The single window everything lives in, plus the minimap button that opens it.
--
-- Tabs register themselves here rather than being hardcoded, so each tab file
-- owns its own layout and this file only routes between them.

local _, ns = ...

local UI = ns.NewModule("UI")

local Theme = ns.Theme
local Widgets = ns.Widgets
local Util = ns.Util

local WINDOW_WIDTH = 1060
local WINDOW_HEIGHT = 580

-- The bevelled dialog border sits on the window's edge and reaches this far
-- inward, so everything inside is padded by the same amount. This is why every
-- Blizzard panel has a wide margin.
local EDGE_PAD = 11

-- The bar of controls that rides on the auction window. Tall enough that the
-- 30px buttons inside it keep their bevel clear of its own edge.
local AUCTION_BAR_HEIGHT = 44
local AUCTION_BAR_PAD = 10
local AUCTION_BAR_FALLBACK_WIDTH = 540

-- How far the window sits off the screen corner while the auction house is
-- open. Small: the three panels together are wider than the screen, so every
-- unit of margin is a unit of overlap somewhere else.
local AUCTION_LAYOUT_INSET = 4

UI.tabs = {}
UI.tabOrder = {}

--------------------------------------------------------------------------------
-- Tab registration
--------------------------------------------------------------------------------

--- @param tab { key, text, order, build(container), refresh(), onShow() }
function UI:RegisterTab(tab)
    self.tabs[tab.key] = tab
    self.tabOrder[#self.tabOrder + 1] = tab

    table.sort(self.tabOrder, function(a, b)
        return (a.order or 99) < (b.order or 99)
    end)
end

--------------------------------------------------------------------------------
-- Window
--------------------------------------------------------------------------------

function UI:Build()
    if self.window then return self.window end

    local window = CreateFrame("Frame", "BlackthornesTSWindow", UIParent)
    window:SetSize(WINDOW_WIDTH, WINDOW_HEIGHT)
    window:SetPoint("CENTER")
    window:SetFrameStrata("HIGH")
    window:SetClampedToScreen(true)
    window:EnableMouse(true)

    -- Clicking the window brings it to the front of its strata. The sell list
    -- docked beside the auction house shares that strata, and without this
    -- whichever was created last stays on top forever -- which is how the sell
    -- list ended up sitting across this window's tab row.
    if window.SetToplevel then window:SetToplevel(true) end
    window:SetMovable(true)
    window:RegisterForDrag("LeftButton")
    window:Hide()

    Theme.Fill(window, "window")

    -- The heavy bevelled gold dialog frame, so the window reads as part of the
    -- game rather than a flat overlay pasted on top of it. Flush to the edge
    -- and untinted: that texture already carries its own gold, and tinting it
    -- again muddies it.
    Theme.AddGameOutline(window, { style = "dialog", color = "natural" })

    window:SetScript("OnDragStart", function(self) self:StartMoving() end)
    window:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        UI:SavePosition()

        -- The sell list gives way to this window rather than overlapping it,
        -- so it needs to know where the window came to rest.
        if ns.PostPanel then ns.PostPanel:Reflow() end
    end)

    -- Escape closes it, like every other panel in the game.
    tinsert(UISpecialFrames, "BlackthornesTSWindow")

    self.window = window

    self:BuildHeader()
    self:BuildTabs()

    self:RestorePosition()

    return window
end

function UI:BuildHeader()
    local window = self.window

    local header = CreateFrame("Frame", nil, window)
    header:SetPoint("TOPLEFT", EDGE_PAD, -EDGE_PAD)
    header:SetPoint("TOPRIGHT", -EDGE_PAD, -EDGE_PAD)
    header:SetHeight(52)
    Theme.Fill(header, "header")

    local title = Theme.CreateLabel(header, "title", "accent")
    title:SetPoint("TOPLEFT", 14, -10)
    title:SetText("Blackthornes Tradeskills")

    local status = Theme.CreateLabel(header, "small", "muted")
    status:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    self.statusLabel = status

    -- Close
    local close = CreateFrame("Button", nil, header)
    close:SetSize(24, 24)
    close:SetPoint("TOPRIGHT", -8, -8)

    local closeLabel = Theme.CreateLabel(close, "large", "muted", "CENTER")
    closeLabel:SetPoint("CENTER")
    closeLabel:SetText("x")

    close:SetScript("OnEnter", function() closeLabel:SetTextColor(Theme.Unpack("loss")) end)
    close:SetScript("OnLeave", function() closeLabel:SetTextColor(Theme.Unpack("muted")) end)
    close:SetScript("OnClick", function() UI:Hide() end)

    -- Scan.
    --
    -- The button stays clickable even when a scan is not currently possible:
    -- a greyed-out control that cannot say why is worse than one that tells
    -- you to open the auction house.
    local scanButton = Widgets.CreateButton(header, "Scan auctions", function()
        UI:TriggerScan()
    end, { width = 120, height = 24, primary = true })

    scanButton:SetPoint("TOPRIGHT", close, "TOPLEFT", -8, -1)
    self.scanButton = scanButton

    -- Inline explanation, so the reason appears in the window rather than only
    -- in the chat frame.
    local hint = Theme.CreateLabel(header, "small", "warn", "RIGHT")
    hint:SetPoint("TOPRIGHT", scanButton, "BOTTOMRIGHT", 0, -4)
    hint:SetWidth(260)
    self.scanHint = hint

    self.header = header

    local progress = Widgets.CreateProgressBar(window)
    progress:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, 0)
    progress:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", 0, 0)
    progress:Hide()
    self.progressBar = progress
end

--- Start or cancel a scan, explaining itself when it cannot.
function UI:TriggerScan()
    if ns.Scanner.isScanning then
        ns.Scanner:CancelScan()
        self:UpdateHeader()
        return
    end

    local allowed, reason = ns.Scanner:CanFullScan()
    if not allowed then
        if self.scanHint then
            self.scanHint:SetText(reason or "cannot scan right now")
        end
        ns.Print(reason or "cannot scan right now")
        return
    end

    ns.Scanner:StartFullScan()
    self:UpdateHeader()
end

function UI:BuildTabs()
    local window = self.window

    local definitions = {}
    for _, tab in ipairs(self.tabOrder) do
        definitions[#definitions + 1] = { key = tab.key, text = tab.text }
    end

    local strip = Widgets.CreateTabStrip(window, definitions, function(key)
        UI:SelectTab(key)
    end)
    strip:SetPoint("TOPLEFT", self.header, "BOTTOMLEFT", 8, -4)
    self.tabStrip = strip

    local content = Theme.CreatePanel(window, "panel")
    content:SetPoint("TOPLEFT", strip, "BOTTOMLEFT", -8, -1)
    content:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -EDGE_PAD, EDGE_PAD)
    self.content = content

    for _, tab in ipairs(self.tabOrder) do
        local container = CreateFrame("Frame", nil, content)
        container:SetPoint("TOPLEFT", 1, -1)
        container:SetPoint("BOTTOMRIGHT", -1, 1)
        container:Hide()

        tab.container = container

        if tab.build then
            tab.build(container)
        end
    end
end

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------

function UI:SelectTab(key)
    local tab = self.tabs[key]
    if not tab then return end

    for _, other in ipairs(self.tabOrder) do
        if other.container then
            other.container:SetShown(other.key == key)
        end
    end

    self.activeTab = key
    self.tabStrip:Select(key)

    if ns.db then ns.db.lastTab = key end

    if tab.onShow then tab.onShow() end
    if tab.refresh then tab.refresh() end
end

function UI:UpdateHeader()
    if not self.statusLabel then return end

    local priceCount = ns.Prices:Count()
    local recipeCount = ns.Recipes:Count()

    local lastScan = ns.db and ns.db.lastFullScan
    local scanText = lastScan and ("scanned " .. Util.FormatAgeAgo(time() - lastScan))
        or "never scanned"

    self.statusLabel:SetText(("%s items priced  ·  %s recipes known  ·  %s"):format(
        Util.Comma(priceCount), Util.Comma(recipeCount), scanText))

    -- The scan button stays live and explains itself rather than greying out
    -- into something that looks broken.
    if ns.Scanner.isScanning then
        self.scanButton:SetText("Cancel scan")
        self.scanButton.tooltipText = "Stop the running scan"
        self.scanHint:SetText("")
    else
        self.scanButton:SetText("Scan auctions")

        local allowed, reason = ns.Scanner:CanFullScan()
        self.scanButton.tooltipText = allowed
            and "Scan the whole auction house in one go"
            or reason

        self.scanHint:SetText(allowed and "" or (reason or ""))
    end
end

function UI:SetScanProgress(fraction)
    if self.progressBar then
        self.progressBar:Show()
        self.progressBar:SetProgress(fraction)
    end

    -- Progress is also surfaced on the auction-house button, which is what the
    -- player is looking at while a scan runs.
    if self.auctionButton then
        self.auctionButton:SetText(("%d%%"):format(math.floor((fraction or 0) * 100)))
    end

    if self.scanHint then
        self.scanHint:SetText(("scanning... %d%%"):format(math.floor((fraction or 0) * 100)))
    end
end

function UI:OnScanComplete()
    if self.progressBar then self.progressBar:Hide() end
    if self.scanHint then self.scanHint:SetText("") end

    self:UpdateAuctionButton()
    self:UpdateHeader()
    self:RefreshActiveTab()
end

function UI:OnRecipesUpdated()
    ns.Cost:InvalidateIndex()
    self:UpdateHeader()
    self:RefreshActiveTab()

    -- The craft pane lists what the profession window is showing, and the
    -- cache it reads from fills in over several frames after that window opens.
    if ns.CraftPanel then ns.CraftPanel:RequestRefresh() end
end

--- What you have listed on the auction house has changed.
--
-- Kept apart from OnInventoryUpdated because nothing in the bags moved, and
-- because the craft pane needs telling. The pane ranks crafts by how many you
-- already hold and hides the ones at their limit, so a reading taken when the
-- auction house opened is no use to it if it is never told the number changed.
function UI:OnAuctionsUpdated()
    self:RefreshActiveTab()
    self:UpdateHeader()

    if ns.CraftPanel then ns.CraftPanel:RequestRefresh() end
end

function UI:OnInventoryUpdated()
    self:RefreshActiveTab()

    -- Crafting something new changes what there is to list.
    if self.postButton and self.postButton:IsVisible() then
        self:UpdatePostButton()
    end

    -- And changes how many of each craft the materials still cover.
    if ns.CraftPanel then ns.CraftPanel:RequestRefresh() end
end

function UI:RefreshActiveTab()
    if not self.window or not self.window:IsShown() then return end

    local tab = self.tabs[self.activeTab]
    if tab and tab.refresh then tab.refresh() end
end

--------------------------------------------------------------------------------
-- Position
--------------------------------------------------------------------------------

--- Which remembered position applies right now.
--
-- Centred is the right place for this window when it is the only thing on
-- screen, and the wrong place the moment the auction house is open: it lands
-- on top of Blizzard's window and the sell list docked beside it. So there are
-- two positions. Dragging the window while the auction house is open moves
-- only the auction-house one, and the everyday position is left alone.
function UI:PositionKey()
    if ns.Scanner and ns.Scanner.isAuctionHouseOpen then
        return "auctionWindowPosition"
    end

    return "windowPosition"
end

function UI:SavePosition()
    if not ns.db or not self.window then return end

    local point, _, relativePoint, x, y = self.window:GetPoint()

    ns.db[self:PositionKey()] =
        { point = point, relativePoint = relativePoint, x = x, y = y }
end

--- @param key string|nil which slot to restore; defaults to the current state.
-- The auction house close handler passes its slot explicitly: Scanner clears
-- isAuctionHouseOpen on the same event, and which handler runs first is not
-- ours to decide.
function UI:RestorePosition(key)
    if not self.window then return end

    key = key or self:PositionKey()

    local position = ns.db and ns.db[key]

    self.window:ClearAllPoints()

    if position then
        self.window:SetPoint(position.point or "CENTER", UIParent,
            position.relativePoint or "CENTER", position.x or 0, position.y or 0)
    elseif key == "auctionWindowPosition" then
        -- Never dragged at the auction house before: the bottom right corner.
        -- The auction window owns the left of the screen and the sell list the
        -- strip beside it, so this is the largest clear space there is.
        self.window:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT",
            -AUCTION_LAYOUT_INSET, AUCTION_LAYOUT_INSET)
    else
        self.window:SetPoint("CENTER")
    end
end

--------------------------------------------------------------------------------
-- Show / hide
--------------------------------------------------------------------------------

function UI:Show()
    self:Build()
    self.window:Show()

    self:SelectTab(self.activeTab or (ns.db and ns.db.lastTab) or self.tabOrder[1].key)
    self:UpdateHeader()

    if ns.PostPanel then ns.PostPanel:Reflow() end
end

function UI:Hide()
    if self.window then self.window:Hide() end

    -- Hidden, so the sell list can have its full height back.
    if ns.PostPanel then ns.PostPanel:Reflow() end
end

function UI:Toggle()
    self:Build()

    if self.window:IsShown() then
        self:Hide()
    else
        self:Show()
    end
end

--------------------------------------------------------------------------------
-- Auction house attachment
--------------------------------------------------------------------------------

-- Candidate globals for Blizzard's auction window. Forever is a retail client,
-- so AuctionHouseFrame is expected, but the name is not worth assuming.
local AUCTION_FRAME_NAMES = { "AuctionHouseFrame", "AuctionFrame" }

--- Locate Blizzard's auction window, whatever it is called on this client.
function UI:FindAuctionFrame()
    for _, name in ipairs(AUCTION_FRAME_NAMES) do
        local frame = _G[name]

        -- Guard against a global that exists but is not a frame.
        if type(frame) == "table" and frame.GetObjectType then
            local ok = pcall(frame.GetObjectType, frame)
            if ok then return frame, name end
        end
    end
end

--- The strip of addon controls that rides on Blizzard's auction window.
--
-- Scan and Post Crafted each used to anchor themselves to the auction frame
-- separately, which left buttons hanging in the game world above it with
-- nothing visibly tying them to the window they act on. They share one bar
-- instead, flush to the auction window's top edge and the same width, so the
-- row reads as part of that window.
--
-- Still parented to UIParent rather than to the auction frame, so Blizzard's
-- own layering can never clip or bury it, and so it survives the auction UI
-- being loaded on demand.
function UI:GetAuctionBar()
    if self.auctionBar then return self.auctionBar end

    local bar = CreateFrame("Frame", "BlackthornesTSAuctionBar", UIParent)
    bar:SetHeight(AUCTION_BAR_HEIGHT)
    bar:SetFrameStrata("FULLSCREEN_DIALOG")
    bar:SetFrameLevel(90)

    -- Opaque and mouse-catching: a click meant for a button should never fall
    -- through the gaps onto whatever is behind the bar.
    bar:EnableMouse(true)
    bar:Hide()

    Theme.Fill(bar, "header")
    Theme.AddGameOutline(bar, { style = "tooltip", color = "natural", edgeSize = 12 })

    -- The bar is as wide as the auction window and the buttons only fill its
    -- right end, so name it. An unlabelled strip of empty frame reads as
    -- something that failed to load.
    local label = Theme.CreateLabel(bar, "small", "accent")
    label:SetPoint("LEFT", bar, "LEFT", AUCTION_BAR_PAD + 4, 0)
    label:SetText("Blackthornes Tradeskills")

    self.auctionBar = bar
    return bar
end

--- A scan button docked to Blizzard's auction house window.
--
-- Scanning only works while the auction house is open, so the control belongs
-- where the player already is rather than only inside our own window.
--
-- Falls back to a fixed screen position if the auction frame cannot be found
-- at all. A scan button that quietly fails to appear is worse than one in a
-- slightly odd place.
function UI:AttachToAuctionHouse()
    local auctionFrame, frameName = self:FindAuctionFrame()
    local bar = self:GetAuctionBar()

    bar:ClearAllPoints()

    if auctionFrame then
        -- Overlapping the auction window's top edge by two pixels, so the two
        -- read as one piece of furniture rather than a bar floating above it.
        bar:SetPoint("BOTTOMLEFT", auctionFrame, "TOPLEFT", 0, -2)
        bar:SetPoint("BOTTOMRIGHT", auctionFrame, "TOPRIGHT", 0, -2)

        -- Zero means "no explicit width", so the bar takes the auction
        -- window's even if the fallback below sized it on an earlier attach.
        bar:SetWidth(0)
        ns.Debug("docked auction bar to", frameName)
    else
        -- Nothing to dock to: put it somewhere it cannot be missed.
        bar:SetPoint("TOP", UIParent, "TOP", 0, -140)
        bar:SetWidth(AUCTION_BAR_FALLBACK_WIDTH)
        ns.Debug("no auction frame found; using fallback position")
    end

    bar:Show()

    local button = self.auctionButton

    if not button then
        button = Widgets.CreateButton(bar, "Scan", function()
            UI:TriggerScan()
            UI:UpdateAuctionButton()
        end, {
            -- Tall enough that the bevel does not crowd the label.
            width = 100,
            height = 30,
            primary = true,
            -- Fully opaque, so nothing behind the button shows through.
            baseColor = { 0.06, 0.07, 0.09, 1 },
        })

        -- This button lives out in the game world, where a flat one-pixel
        -- border vanishes against Blizzard's art. Give it the familiar
        -- bevelled frame edge so it always reads as a control.
        -- A lighter bevel, pushed slightly outward so it frames the button
        -- rather than closing in on the text.
        Theme.AddGameOutline(button, {
            style = "tooltip",
            color = "natural",
            edgeSize = 12,
            expand = 4,
        })
        button:ApplyBaseColor()

        self.auctionButton = button
    end

    button:ClearAllPoints()
    button:SetPoint("RIGHT", bar, "RIGHT", -AUCTION_BAR_PAD, 0)
    button:Show()

    self:UpdateAuctionButton()

    self:AttachPostButton()

    -- Before the sell list attaches: the list measures itself around this
    -- window, so it needs the window where it is going to sit. Built centred,
    -- or wherever it was last dragged with the auction house shut, it is in
    -- the wrong place now either way.
    self:RestorePosition("auctionWindowPosition")

    if ns.PostPanel then ns.PostPanel:Attach() end
end

--- A Post button beside the Scan button on the auction house window.
--
-- Left-click lists the most valuable stack; posting needs a hardware event per
-- listing anyway, so clicking repeatedly works through them. Right-click opens
-- the Post tab for the full table when you want to pick rather than take the
-- top of the list.
function UI:UpdateAuctionButton()
    local button = self.auctionButton
    if not button then return end

    if ns.Scanner.isScanning then
        button:SetText("Cancel")
        button.tooltipText = "Stop the running scan"
        return
    end

    button:SetText("Scan")

    local allowed, reason = ns.Scanner:CanFullScan()
    button:SetEnabledState(allowed)

    -- The bulk snapshot is rate limited; browsing is not, so say which one a
    -- click will actually do rather than implying a wait.
    local cooldown = ns.Scanner:GetSnapshotCooldown()

    button.tooltipText = allowed
        and (cooldown
            and ("Scan the auction house page by page.\nThe faster full scan can be used again in %s.")
                :format(Util.FormatAge(cooldown))
            or "Scan the whole auction house in one go")
        or reason
end

--- A Post button beside the Scan button on the auction house window.
--
-- Left-click lists the most valuable stack; posting needs a hardware event
-- per listing anyway, so clicking repeatedly works down the list.
-- Right-click opens the Post tab for the full table.
function UI:AttachPostButton()
    local bar = self:GetAuctionBar()
    local button = self.postButton

    if not button then
        button = Widgets.CreateButton(bar, "Post Crafted", function(_, mouseButton)
            if mouseButton == "RightButton" or ns.Posting:IsBlocked() then
                UI:Show()
                UI:SelectTab("post")
                return
            end

            local allowed, reason = ns.Posting:CanPost()
            if not allowed then
                ns.Print(reason or "cannot post right now")
                return
            end

            local line = ns.Posting:GetNextPostable()
            if line then
                ns.Posting:Request(line.itemID, line.postQuantity, line.unitPrice)
            else
                ns.Print("nothing in your bags worth listing right now")
            end

            UI:UpdatePostButton()
        end, {
            width = 230,
            height = 30,
            primary = true,
            baseColor = { 0.06, 0.07, 0.09, 1 },
        })

        button:RegisterForClicks("LeftButtonUp", "RightButtonUp")

        Theme.AddGameOutline(button, {
            style = "tooltip", color = "natural", edgeSize = 12, expand = 4,
        })
        button:ApplyBaseColor()

        self.postButton = button
    end

    button:ClearAllPoints()

    if self.auctionButton then
        button:SetPoint("RIGHT", self.auctionButton, "LEFT", -10, 0)
    else
        button:SetPoint("RIGHT", bar, "RIGHT", -AUCTION_BAR_PAD, 0)
    end

    button:Show()

    self:UpdatePostButton()
end

--- Show a button's wait on the button itself, rather than only in a tooltip.
--
-- Posting is paced on purpose, and with the label unchanged the only sign of
-- that was a button that did nothing when clicked. The countdown is the whole
-- point: a number going down reads as working, where a dead button reads as
-- broken.
--
-- The button stays enabled throughout. Disabling it would swallow the
-- right-click that opens the full list, and a left-click during the wait still
-- prints the reason.
--
-- @param name the label to go back to once the wait is over
local function ApplyWaitLabel(button, name, seconds, reason)
    if not button then return end

    if seconds and seconds > 0.05 then
        -- Rounded up, so the last fraction of a second still shows "1s" rather
        -- than sitting on "0s" while the wait is genuinely still running.
        button:SetText(("%ds"):format(math.max(1, math.ceil(seconds))))
        button.waitingLabel = true
    elseif reason then
        -- No number to give: the client's throttle and the player's own sell
        -- window both end when they end. Saying "wait" beats counting down to
        -- zero and then carrying on refusing.
        button:SetText("wait")
        button.waitingLabel = true
    else
        button:SetText(name)
        button.waitingLabel = false
    end
end

-- Exposed as a plain function, not a method: the tests drive it directly.
UI.ApplyWaitLabel = ApplyWaitLabel

--- Relabel the posting buttons with the current wait, and nothing else.
--
-- Deliberately separate from UpdatePostButton, which rebuilds summaries and
-- walks the bags. This runs four times a second while the auction house is
-- open, so it may only touch labels.
function UI:UpdateWaitLabels()
    if not ns.Scanner.isAuctionHouseOpen then return end

    local seconds, reason = ns.Posting:SecondsUntilPostable()

    ApplyWaitLabel(self.postButton, "Post Crafted", seconds, reason)

    if ns.PostPanel then
        ns.PostPanel:UpdateWaitLabels(seconds, reason)
    end
end

function UI:UpdatePostButton()
    local button = self.postButton
    if not button then return end

    local line = ns.Posting:GetNextPostable()

    if not line then
        -- Inert rather than absent, so it never looks like it failed to load.
        button:SetText("Post Crafted")
        button:SetEnabledState(true)
        button.tooltipText =
            "Nothing in your bags that one of your recipes makes, at a price worth listing."
        return
    end

    local count, total = ns.Posting:GetSummary()
    local allowed, reason = ns.Posting:CanPost()
    local waitSeconds, waitReason = ns.Posting:SecondsUntilPostable()

    ApplyWaitLabel(button, "Post Crafted", waitSeconds, waitReason)
    button:SetEnabledState(true)

    button.tooltipText = allowed
        and ("Lists %d x %s at %s each.\n%d stack(s) to sell, worth about %s.\n\nRight-click for the full list."):format(
            line.postQuantity, line.label,
            Util.FormatMoney(line.unitPrice, { noColor = true }),
            count, Util.FormatMoney(total, { noColor = true, short = true }))
        or ((reason or "cannot post right now") .. "\n\nRight-click for the full list and prices.")

    if waitReason then
        button.tooltipText = button.tooltipText .. ("\n\nWaiting: %s."):format(waitReason)
    end
end

--------------------------------------------------------------------------------
-- Transfer dialog
--------------------------------------------------------------------------------

--- A selectable text box for copying an export code out, or pasting one in.
--
-- WoW chat cannot be selected, so a code has to live in an edit box for Ctrl+C
-- to reach it.
function UI:ShowTransferDialog(mode)
    local dialog = self.transferDialog

    if not dialog then
        dialog = CreateFrame("Frame", "BlackthornesTSTransferDialog", UIParent)
        dialog:SetSize(560, 260)
        dialog:SetPoint("CENTER")
        dialog:SetFrameStrata("FULLSCREEN_DIALOG")
        dialog:EnableMouse(true)
        dialog:SetMovable(true)
        dialog:RegisterForDrag("LeftButton")
        dialog:SetScript("OnDragStart", dialog.StartMoving)
        dialog:SetScript("OnDragStop", dialog.StopMovingOrSizing)

        Theme.Fill(dialog, "window")
        Theme.AddGameOutline(dialog, { style = "dialog", color = "natural" })

        tinsert(UISpecialFrames, "BlackthornesTSTransferDialog")

        dialog.title = Theme.CreateLabel(dialog, "large", "accent")
        dialog.title:SetPoint("TOPLEFT", 20, -20)

        dialog.hint = Theme.CreateLabel(dialog, "small", "muted")
        dialog.hint:SetPoint("TOPLEFT", dialog.title, "BOTTOMLEFT", 0, -6)
        dialog.hint:SetPoint("RIGHT", dialog, "RIGHT", -20, 0)
        dialog.hint:SetWordWrap(true)

        local box = Theme.CreatePanel(dialog, "row")
        box:SetPoint("TOPLEFT", 20, -80)
        box:SetPoint("BOTTOMRIGHT", -20, 56)

        local scroll = CreateFrame("ScrollFrame", nil, box)
        scroll:SetPoint("TOPLEFT", 6, -6)
        scroll:SetPoint("BOTTOMRIGHT", -6, 6)

        local editBox = CreateFrame("EditBox", nil, scroll)
        editBox:SetMultiLine(true)
        editBox:SetAutoFocus(false)
        editBox:SetFont(Theme.FONT, Theme.sizes.small, "")
        editBox:SetTextColor(Theme.Unpack("text"))
        editBox:SetWidth(500)
        editBox:SetScript("OnEscapePressed", function() dialog:Hide() end)

        scroll:SetScrollChild(editBox)
        dialog.editBox = editBox

        dialog.action = Widgets.CreateButton(dialog, "Import", function()
            local ok, message = ns.Transfer:Import(dialog.editBox:GetText())

            ns.Print(message)
            if ok then dialog:Hide() end
        end, { width = 120, height = 26, primary = true })
        dialog.action:SetPoint("BOTTOMRIGHT", -20, 18)

        local close = Widgets.CreateButton(dialog, "Close", function()
            dialog:Hide()
        end, { width = 90, height = 26 })
        close:SetPoint("BOTTOMRIGHT", dialog.action, "BOTTOMLEFT", -8, 0)

        self.transferDialog = dialog
    end

    if mode == "export" then
        local code = ns.Transfer:Export()
        local queued, settings, limits = ns.Transfer:Describe()

        dialog.title:SetText("Export")
        dialog.hint:SetText(("%d craft(s), %d changed setting(s), %d stock limit(s). Press Ctrl+C to copy, then keep it somewhere until you need it."):format(
            queued, settings, limits))

        dialog.editBox:SetText(code)
        dialog.editBox:HighlightText()
        dialog.action:Hide()
    else
        dialog.title:SetText("Import")
        dialog.hint:SetText("Paste a code with Ctrl+V, then press Import. Crafts are added to your queue; settings and stock limits are replaced.")

        dialog.editBox:SetText("")
        dialog.action:Show()
    end

    dialog:Show()
    dialog.editBox:SetFocus()
end

--------------------------------------------------------------------------------
-- Merchant attachment
--------------------------------------------------------------------------------

--- A button on Blizzard's vendor window that buys the queue's shortfalls.
--
-- Spending your gold is never automatic: this is one deliberate click, and the
-- button states the exact cost before you press it.
function UI:AttachToMerchant()
    local button = self.merchantButton

    if not button then
        button = Widgets.CreateButton(UIParent, "Buy materials", function()
            ns.Vendor:BuyNeeded()
            UI:UpdateMerchantButton()
        end, {
            width = 170,
            height = 30,
            primary = true,
            baseColor = { 0.06, 0.07, 0.09, 1 },
        })

        button:SetFrameStrata("FULLSCREEN_DIALOG")
        button:SetFrameLevel(100)

        Theme.AddGameOutline(button, {
            style = "tooltip", color = "natural", edgeSize = 12, expand = 4,
        })
        button:ApplyBaseColor()

        self.merchantButton = button
    end

    local merchantFrame = _G.MerchantFrame

    button:ClearAllPoints()
    if merchantFrame then
        button:SetPoint("BOTTOMRIGHT", merchantFrame, "TOPRIGHT", -4, 4)
    else
        button:SetPoint("TOP", UIParent, "TOP", 0, -180)
    end

    button:Show()
    self:UpdateMerchantButton()
end

function UI:UpdateMerchantButton()
    local button = self.merchantButton
    if not button then return end

    if ns.Vendor:IsBuying() then
        button:SetText("Buying...")
        button:SetEnabledState(false)
        button.tooltipText = "Purchases in progress"
        return
    end

    local lines, total = ns.Vendor:GetNeeded()

    if #lines == 0 then
        -- Present but inert, so it never looks like it failed to appear.
        button:SetText("Nothing needed here")
        button:SetEnabledState(false)
        button.tooltipText = ns.Queue:Count() == 0
            and "Your craft queue is empty"
            or "This vendor sells none of the materials your queue needs"
        return
    end

    button:SetText(("Buy materials  %s"):format(Util.FormatMoney(total, { short = true })))
    button:SetEnabledState(true)

    -- Spell out exactly what will be bought before any gold moves.
    local parts = { ("Buys %d material%s for your queue:"):format(
        #lines, #lines == 1 and "" or "s") }

    for index = 1, math.min(#lines, 10) do
        local line = lines[index]
        parts[#parts + 1] = ("  %dx %s  (%s)%s"):format(
            line.amount, Util.GetItemLabel(line.itemID),
            Util.FormatMoney(line.cost, { noColor = true, short = true }),
            line.short and "  - vendor stock limited" or "")
    end

    if #lines > 10 then
        parts[#parts + 1] = ("  ...and %d more"):format(#lines - 10)
    end

    button.tooltipText = table.concat(parts, "\n")
end

--------------------------------------------------------------------------------
-- Minimap button
--------------------------------------------------------------------------------

function UI:BuildMinimapButton()
    if self.minimapButton or not Minimap then return end

    local button = CreateFrame("Button", "BlackthornesTSMinimapButton", Minimap)
    button:SetSize(31, 31)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    local background = button:CreateTexture(nil, "BACKGROUND")
    background:SetSize(20, 20)
    background:SetPoint("CENTER")
    background:SetColorTexture(Theme.Unpack("window"))

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetSize(18, 18)
    icon:SetPoint("CENTER")
    icon:SetTexture([[Interface\Icons\Trade_BlackSmithing]])
    icon:SetTexCoord(0.1, 0.9, 0.1, 0.9)

    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT")
    border:SetTexture([[Interface\Minimap\MiniMap-TrackingBorder]])

    -- Derived from the minimap's real size rather than assumed. A fixed radius
    -- only clears the ring on a default 140px minimap; anyone running a larger
    -- one gets the button sitting on top of the map.
    local function GetOrbitRadius()
        local size = Minimap:GetWidth()
        if not size or size <= 0 then size = 140 end

        return (size / 2) + (ns.db and ns.db.minimapGap or 16)
    end

    local function UpdatePosition(angle)
        local radius = GetOrbitRadius()

        button:ClearAllPoints()
        button:SetPoint("CENTER", Minimap, "CENTER",
            math.cos(angle) * radius, math.sin(angle) * radius)
    end

    button.UpdatePosition = UpdatePosition

    local angle = (ns.db and ns.db.minimapAngle) or math.rad(200)
    UpdatePosition(angle)

    -- Dragging around the minimap edge is the expected behaviour for these.
    button:SetMovable(true)
    button:RegisterForDrag("LeftButton")
    button:SetScript("OnDragStart", function(self)
        self.dragging = true
        self:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local cx, cy = GetCursorPosition()
            local scale = UIParent:GetEffectiveScale()

            local newAngle = math.atan2((cy / scale) - my, (cx / scale) - mx)
            UpdatePosition(newAngle)

            if ns.db then ns.db.minimapAngle = newAngle end
        end)
    end)

    button:SetScript("OnDragStop", function(self)
        self.dragging = false
        self:SetScript("OnUpdate", nil)
    end)

    button:SetScript("OnClick", function()
        UI:Toggle()
    end)

    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("Blackthornes Tradeskills")
        GameTooltip:AddLine("Click to open", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)

    button:SetScript("OnLeave", function() GameTooltip:Hide() end)

    self.minimapButton = button
    self.lastMinimapWidth = Minimap:GetWidth()
end

--- Point Blizzard's auction browse at one item.
--
-- Searching is unrestricted; buying is never automated. The addon puts the item
-- in front of you and gets out of the way.
function UI:SearchAuctionHouse(itemID)
    if not ns.Scanner.isAuctionHouseOpen then
        ns.Print("open the auction house first")
        return false
    end

    local name
    if Util.HasFunction("C_Item.GetItemInfo") then
        local ok, itemName = pcall(C_Item.GetItemInfo, itemID)
        if ok then name = itemName end
    end

    if not name then
        ns.Print("the game has not loaded that item yet; hover over it once and try again")
        return false
    end

    -- Queued rather than sent directly. This shares one throttled channel with
    -- the player's own posting, and a search fired the instant a row is clicked
    -- is a search that can cost them a listing.
    ns.AHQueue:Request({
        name = ("search the auction house for %s"):format(name),
        key = "ui-search",
        -- The player clicked this and is watching the auction house for it, so
        -- it ranks with their other clicks.
        priority = ns.AHQueue.PRIORITY.urgent,
        expires = 8,

        send = function()
            local ok = pcall(C_AuctionHouse.SendBrowseQuery, {
                searchString = name,
                sorts = {},
                filters = {},
                itemClassFilters = {},
                minLevel = 0,
                maxLevel = 0,
            })

            if not ok then
                ns.Warn("the game refused that search")
                return false
            end

            return true
        end,

        onGiveUp = function()
            ns.Warn("the auction house stayed busy; that search was not sent.")
        end,
    })

    return true
end

--- Re-seat the minimap button at its stored angle, using the current radius.
function UI:RepositionMinimapButton()
    local button = self.minimapButton
    if not button or not button.UpdatePosition then return end

    button.UpdatePosition((ns.db and ns.db.minimapAngle) or math.rad(200))
    self.lastMinimapWidth = Minimap and Minimap:GetWidth()
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

function UI:OnEnable()
    self:Build()
    self:BuildMinimapButton()

    -- The minimap's final size is not always settled at login, and other addons
    -- resize it afterwards, so re-seat the button once things have calmed down.
    C_Timer.After(1, function() UI:RepositionMinimapButton() end)

    -- The header is the addon's status line; keep it honest while open.
    self.ticker = C_Timer.NewTicker(5, function()
        if UI.window and UI.window:IsShown() then
            UI:UpdateHeader()
        end

        -- Cheap enough to check, and catches a minimap resized at any point.
        if Minimap and UI.lastMinimapWidth ~= Minimap:GetWidth() then
            UI:RepositionMinimapButton()
        end
    end)

    ns.RegisterEvent(self, "AUCTION_HOUSE_SHOW", function()
        UI:UpdateHeader()
        UI:AttachToAuctionHouse()

        -- Blizzard's auction UI is load-on-demand, so on the first open of a
        -- session the frame may not exist yet when this event arrives.
        -- Re-anchor shortly after in case it appeared late.
        C_Timer.After(0.5, function()
            if ns.Scanner.isAuctionHouseOpen then
                UI:AttachToAuctionHouse()
            end
        end)

        -- The auction house throttle clears on its own with no event to say
        -- so. Without this the Post button stays greyed out, explaining that
        -- the house is busy, long after it stopped being busy.
        if UI.postTicker then UI.postTicker:Cancel() end

        UI.postTicker = C_Timer.NewTicker(1, function()
            if not ns.Scanner.isAuctionHouseOpen then return end

            UI:UpdatePostButton()

            if ns.PostPanel then ns.PostPanel:Refresh() end

            if UI.activeTab == "post" then
                UI:RefreshActiveTab()
            end
        end)

        -- A second, faster ticker purely for the countdown. One second is too
        -- coarse for a wait that is often only a second or two: the number
        -- would jump or sit still, which is what a broken button looks like.
        -- Kept apart from the ticker above because that one rebuilds the sell
        -- list and walks the bags, which is far too much to do four times a
        -- second.
        if UI.waitTicker then UI.waitTicker:Cancel() end

        UI.waitTicker = C_Timer.NewTicker(0.25, function()
            UI:UpdateWaitLabels()
        end)
    end)

    ns.RegisterEvent(self, "AUCTION_HOUSE_CLOSED", function()
        UI:UpdateHeader()
        if UI.auctionBar then UI.auctionBar:Hide() end
        if ns.PostPanel then ns.PostPanel:Hide() end

        -- Back to wherever the window normally lives.
        UI:RestorePosition("windowPosition")

        if UI.postTicker then
            UI.postTicker:Cancel()
            UI.postTicker = nil
        end

        if UI.waitTicker then
            UI.waitTicker:Cancel()
            UI.waitTicker = nil
        end
    end)
end
