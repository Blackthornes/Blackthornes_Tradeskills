-- Blackthornes Tradeskills -- UI/Collapse.lua
-- The small button at the top left of a side panel that folds it down to its
-- title strip and opens it back up.
--
-- The sell list and the craft pane both sit beside a Blizzard window and take
-- up a lot of the screen. Closing them outright means losing them until the
-- window is reopened, so this folds one away instead and remembers that it
-- was folded.
--
-- A panel hands over a `body` frame holding everything below the title. The
-- title stays on the panel itself, so it is still there to read and click
-- when the body is hidden.

local _, ns = ...

local Collapse = {}
ns.Collapse = Collapse

-- Title strip height: the title's own 14 inset, one line of text, and room
-- below it so the border does not sit on the letters.
Collapse.HEIGHT = 40

local BUTTON_SIZE = 16

-- How far the title moves right to make room for the button. Anything a panel
-- anchors under its title takes this back off, so it stays at the 14 inset
-- the rest of the panel lines up on.
Collapse.TITLE_SHIFT = 20

--- Is this panel folded down to its title?
--
-- Read from settings each time rather than kept on the frame, so the answer
-- is right before the panel has ever been built.
function Collapse.IsCollapsed(key)
    return ns.Config ~= nil and ns.Config:Get(key) == true
end

--- The height a panel should take: its title strip when folded, else `full`.
function Collapse.Height(key, full)
    if Collapse.IsCollapsed(key) then return Collapse.HEIGHT end
    return full
end

local function UpdateButton(button, collapsed)
    button:SetText(collapsed and "+" or "-")
    button.tooltipText = collapsed and "Expand this window" or "Collapse this window"
end

--- Put the button on a panel.
--
-- opts.key       settings key that remembers the state between sessions
-- opts.title     the panel's title, moved over to make room for the button
-- opts.body      the frame holding everything that folds away
-- opts.onToggle  called with the new state after it changes; the panel
--                re-measures its height and refreshes itself there
function Collapse.Attach(frame, opts)
    local button = ns.Widgets.CreateButton(frame, "-", function()
        local collapsed = not Collapse.IsCollapsed(opts.key)

        ns.Config:Set(opts.key, collapsed)
        Collapse.Apply(frame)

        if opts.onToggle then opts.onToggle(collapsed) end
    end, { width = BUTTON_SIZE, height = BUTTON_SIZE })

    button:SetPoint("TOPLEFT", 12, -12)

    -- The same height as before, just over to the right of the button.
    opts.title:ClearAllPoints()
    opts.title:SetPoint("TOPLEFT", 14 + Collapse.TITLE_SHIFT, -14)

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
