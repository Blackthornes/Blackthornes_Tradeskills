-- Blackthornes Tradeskills -- UI/Collapse.lua
-- The header strip on the side panels, and the small button at its left that
-- folds a panel down to that strip and opens it back up.
--
-- The sell list and the craft pane both sit beside a Blizzard window and take
-- up a lot of the screen. Closing them outright means losing them until the
-- window is reopened, so this folds one away instead and remembers that it
-- was folded.
--
-- The strip is the main window's header in miniature (gold stripe down the
-- left, a faint sheen on top, a lit rule underneath), so the side panels read
-- as part of the same addon.
--
-- A panel hands over a `body` frame holding everything below the header. The
-- header stays on the panel itself, so it is still there to read and click
-- when the body is hidden.

local _, ns = ...

local Collapse = {}
ns.Collapse = Collapse

-- Inside the gold dialog bevel, the same inset the main window's header uses.
local EDGE_PAD = 11
local HEADER_HEIGHT = 28

-- Folded height: the bevel, the header strip, the bevel again.
Collapse.HEIGHT = EDGE_PAD + HEADER_HEIGHT + EDGE_PAD

-- Where a panel's content starts, a little under the header's rule.
Collapse.CONTENT_TOP = -(EDGE_PAD + HEADER_HEIGHT + 7)

local BUTTON_SIZE = 16

--- Is this panel folded down to its header?
--
-- Read from settings each time rather than kept on the frame, so the answer
-- is right before the panel has ever been built.
function Collapse.IsCollapsed(key)
    return ns.Config ~= nil and ns.Config:Get(key) == true
end

--- The height a panel should take: its header strip when folded, else `full`.
function Collapse.Height(key, full)
    if Collapse.IsCollapsed(key) then return Collapse.HEIGHT end
    return full
end

--- The house header strip across the top of a side panel.
-- @return header, title
function Collapse.CreateHeader(frame, text)
    local Theme = ns.Theme

    local header = CreateFrame("Frame", nil, frame)
    header:SetPoint("TOPLEFT", EDGE_PAD, -EDGE_PAD)
    header:SetPoint("TOPRIGHT", -EDGE_PAD, -EDGE_PAD)
    header:SetHeight(HEADER_HEIGHT)

    Theme.Fill(header, "header")
    Theme.TopSheen(header, 0.07)
    Theme.AccentStripe(header, 3)

    local rule = Theme.CreateDivider(header, "borderLit")
    rule:SetPoint("BOTTOMLEFT")
    rule:SetPoint("BOTTOMRIGHT")

    local title = Theme.CreateLabel(header, "normal", "accent")
    title:SetText(text)

    -- Stands in for the button until Attach puts one there.
    title:SetPoint("LEFT", header, "LEFT", 10, 0)

    return header, title
end

local function UpdateButton(button, collapsed)
    button:SetText(collapsed and "+" or "-")
    button.tooltipText = collapsed and "Expand this window" or "Collapse this window"
end

--- Put the button at the left of a panel's header.
--
-- opts.key       settings key that remembers the state between sessions
-- opts.header    the strip from CreateHeader
-- opts.title     its title, moved over to make room for the button
-- opts.body      the frame holding everything that folds away
-- opts.onToggle  called with the new state after it changes; the panel
--                re-measures its height and refreshes itself there
function Collapse.Attach(frame, opts)
    local button = ns.Widgets.CreateButton(opts.header, "-", function()
        local collapsed = not Collapse.IsCollapsed(opts.key)

        ns.Config:Set(opts.key, collapsed)
        Collapse.Apply(frame)

        if opts.onToggle then opts.onToggle(collapsed) end
    end, { width = BUTTON_SIZE, height = BUTTON_SIZE })

    button:SetPoint("LEFT", opts.header, "LEFT", 8, 0)

    opts.title:ClearAllPoints()
    opts.title:SetPoint("LEFT", button, "RIGHT", 7, 0)

    frame.collapse = { button = button, key = opts.key, body = opts.body }
    Collapse.Apply(frame)

    return button
end

--- Show or hide the body to match the saved state. The caller sets the height.
function Collapse.Apply(frame)
    local state = frame.collapse
    if not state then return end

    local collapsed = Collapse.IsCollapsed(state.key)

    state.body:SetShown(not collapsed)
    UpdateButton(state.button, collapsed)
end

--- A band behind the controls along a panel's bottom edge, topped with the
--- same lit rule as the header, so the footer reads as its own shelf.
function Collapse.CreateFooter(body, height)
    local Theme = ns.Theme

    local band = body:CreateTexture(nil, "BACKGROUND", nil, 1)
    band:SetPoint("BOTTOMLEFT", EDGE_PAD, EDGE_PAD)
    band:SetPoint("BOTTOMRIGHT", -EDGE_PAD, EDGE_PAD)
    band:SetHeight(height)
    band:SetColorTexture(Theme.Unpack("header"))

    local rule = Theme.CreateDivider(body, "borderLit")
    rule:SetPoint("BOTTOMLEFT", band, "TOPLEFT")
    rule:SetPoint("BOTTOMRIGHT", band, "TOPRIGHT")

    return band
end
