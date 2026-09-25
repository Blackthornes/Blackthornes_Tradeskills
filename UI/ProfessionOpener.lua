-- Blackthornes Tradeskills -- UI/ProfessionOpener.lua
-- Lets the Queue tab's craft button open the right profession window.
--
-- A craft only starts while its profession window is open, and opening one
-- means casting the profession (Tailoring, Smelting and so on). Addon code
-- is not allowed to cast, but the player's own click on a secure action
-- button is. So when the next craft's window is not open, an invisible
-- secure button is laid over the craft button, set to cast that profession.
-- The first click opens the window; the button then reads "Craft ..." again
-- and the second click crafts.
--
-- The secure button is parented to UIParent and placed over the craft button
-- by screen position, never anchored to it: a secure frame makes its parent
-- and anchor protected too, and then the addon's own window could not be
-- shown or hidden in combat. It is only touched out of combat, which is the
-- other rule for secure frames.

local _, ns = ...

local Opener = ns.NewModule("ProfessionOpener")

-- The profession name the client gives, keyed by both skill-line IDs this
-- client uses (see docs/FOREVER_API_FINDINGS.md). Only a fallback for when
-- GetProfessionInfoBySkillLineID says nothing.
local SKILL_LINE_NAMES = {
    [2937] = "Alchemy",        [171] = "Alchemy",
    [2938] = "Blacksmithing",  [164] = "Blacksmithing",
    [2940] = "Enchanting",     [333] = "Enchanting",
    [2941] = "Engineering",    [202] = "Engineering",
    [2945] = "Leatherworking", [165] = "Leatherworking",
    [2946] = "Mining",         [186] = "Mining",
    [2948] = "Tailoring",      [197] = "Tailoring",
    [185] = "Cooking",         [129] = "First Aid",
}

-- Mining's window is opened by casting Smelting, not Mining.
local SMELTING_SPELL_ID = 2656

-- Gathering skills have no window to open.
local NO_WINDOW = { Herbalism = true, Skinning = true, Fishing = true }

-- How long after a click the window has to open before we call it a miss.
local OPEN_TIMEOUT = 3

--------------------------------------------------------------------------------
-- Which profession
--------------------------------------------------------------------------------

local function SpellName(spellID, fallback)
    if C_Spell and type(C_Spell.GetSpellName) == "function" then
        local ok, name = pcall(C_Spell.GetSpellName, spellID)
        if ok and type(name) == "string" and name ~= "" then return name end
    end

    if type(GetSpellInfo) == "function" then
        local ok, name = pcall(GetSpellInfo, spellID)
        if ok and type(name) == "string" and name ~= "" then return name end
    end

    return fallback
end

--- The profession a recipe belongs to, and the spell that opens its window.
-- @return { name, spell, skillLineID } or nil when it cannot be worked out
function Opener:ProfessionFor(recipeID)
    local recipe = ns.Recipes and ns.Recipes:GetAny(recipeID)
    local skillLineID = recipe and recipe.skillLineID
    if not skillLineID then return nil end

    local name
    local api = _G.C_TradeSkillUI

    if api and type(api.GetProfessionInfoBySkillLineID) == "function" then
        local ok, info = pcall(api.GetProfessionInfoBySkillLineID, skillLineID)
        if ok and type(info) == "table" then
            -- A sub-line such as "Classic Tailoring" names its parent here.
            name = info.parentProfessionName or info.professionName
            if name == "" then name = nil end
        end
    end

    name = name or SKILL_LINE_NAMES[skillLineID]
    if not name or NO_WINDOW[name] then return nil end

    local spell = name
    if name == "Mining" or skillLineID == 2946 or skillLineID == 186 then
        spell = SpellName(SMELTING_SPELL_ID, "Smelting")
    end

    return { name = name, spell = spell, skillLineID = skillLineID }
end

--- Is a profession window open that can make this recipe right now?
function Opener:WindowShowsRecipe(recipeID)
    if not ns.Crafting.isTradeSkillOpen then return false end

    -- The pane's reading of the open window. Nothing to read means the client
    -- would not say, and then the open window gets the benefit of the doubt,
    -- exactly as the craft pane does.
    local open = ns.CraftPanel and ns.CraftPanel:GetOpenRecipeIDs()
    if not open then return true end

    return open[recipeID] == true
end

--------------------------------------------------------------------------------
-- The secure button
--------------------------------------------------------------------------------

local function InCombat()
    return type(InCombatLockdown) == "function" and InCombatLockdown() and true or false
end

-- Fire on mouse release only. Seen in game: registered for key down (the
-- game's ActionButtonUseKeyDown setting was on), this client's secure button
-- never cast, and the release fell through to the craft button underneath.
-- Registering both directions would cast twice on a client whose template
-- ignores the direction, and a second cast closes the window the first one
-- opened. The useOnKeyDown attribute tells a template that does check the
-- direction to act on the release too.
local CLICK_DIRECTION = "AnyUp"

function Opener:CreateOverlay()
    if self.overlay then return self.overlay end

    local overlay = CreateFrame("Button", "BlackthornesTSOpenProfession", UIParent,
        "SecureActionButtonTemplate")
    overlay:Hide()
    overlay:EnableMouse(true)

    -- Drawn as a real button rather than left invisible. When it sits where it
    -- should it looks exactly like the craft button under it; when it does
    -- not, you can see where it went instead of clicking something else.
    local Theme = ns.Theme
    overlay.background = Theme.Fill(overlay, "rowActive")
    Theme.Border(overlay, "border")
    overlay.label = Theme.CreateLabel(overlay, "small", "accent", "CENTER")
    overlay.label:SetPoint("CENTER")

    overlay:SetScript("OnEnter", function(self)
        self.background:SetColorTexture(Theme.Unpack("rowHover"))
        local anchor = Opener.anchor
        if anchor and anchor.tooltipText then
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(anchor.tooltipText, 1, 1, 1, 1, true)
            GameTooltip:Show()
        end
    end)

    overlay:SetScript("OnLeave", function(self)
        self.background:SetColorTexture(Theme.Unpack("rowActive"))
        GameTooltip:Hide()
    end)

    -- Runs after the secure cast. Only notes the click, so the outcome can be
    -- reported once we know whether a window actually opened.
    -- Noted before the secure handler runs, so a click that casts nothing
    -- can still be told apart from a click that never arrived.
    -- Any press at all, registered click or not, so /bts openprof can say
    -- whether the mouse ever reached this button.
    overlay:HookScript("OnMouseDown", function(_, mouseButton)
        Opener.lastMouseDown = { button = tostring(mouseButton), at = GetTime() }
    end)

    overlay:SetScript("PreClick", function(_, mouseButton, down)
        Opener.lastClick = { button = tostring(mouseButton), down = down and true or false, at = GetTime() }
    end)

    overlay:SetScript("PostClick", function()
        Opener:OnClicked()
    end)

    self.overlay = overlay
    return overlay
end

local STRATA_ABOVE = {
    BACKGROUND = "LOW", LOW = "MEDIUM", MEDIUM = "HIGH", HIGH = "DIALOG",
    DIALOG = "FULLSCREEN", FULLSCREEN = "FULLSCREEN_DIALOG",
    FULLSCREEN_DIALOG = "TOOLTIP", TOOLTIP = "TOOLTIP",
}

-- While the secure button is up, the craft button under it stops taking the
-- mouse, so there is only one thing there to click. The craft button is ours
-- and not protected, so this is allowed at any time, combat included.
local function SetAnchorMouse(anchor, enabled)
    if anchor and anchor.EnableMouse then anchor:EnableMouse(enabled) end
end

--- Keep the secure button exactly over the craft button.
function Opener:Place()
    local overlay, anchor = self.overlay, self.anchor
    if not overlay or not anchor or InCombat() then return end

    local left, bottom = anchor:GetLeft(), anchor:GetBottom()
    local width, height = anchor:GetWidth(), anchor:GetHeight()
    if not left or not bottom then return end

    local scale = anchor:GetEffectiveScale() / UIParent:GetEffectiveScale()
    local x, y = left * scale, bottom * scale
    local w, h = width * scale, height * scale

    -- Same layer as the craft button, just above it, so a bag or another
    -- window lying over ours still gets its own clicks. Checked every time,
    -- not only when the button moves: our window is a top-level frame, so
    -- clicking it or reopening it raises its level, and a secure button left
    -- at the old level ends up underneath the craft button. That is exactly
    -- how the first in-game try missed.
    --
    -- One whole layer above, as well. Seen in game: at HIGH 9 over the craft
    -- button's HIGH 4, placed exactly on it, the craft button still took
    -- every click and the secure button never received one.
    local strata = STRATA_ABOVE[anchor:GetFrameStrata()] or "DIALOG"
    local level = anchor:GetFrameLevel() + 5
    if overlay:GetFrameStrata() ~= strata then overlay:SetFrameStrata(strata) end
    if overlay:GetFrameLevel() ~= level then overlay:SetFrameLevel(level) end

    local last = self.placed
    if last and last[1] == x and last[2] == y and last[3] == w and last[4] == h then
        return
    end

    overlay:ClearAllPoints()
    overlay:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", x, y)
    overlay:SetSize(w, h)
    self.placed = { x, y, w, h }
end

--- Put the secure button over `anchor`, set to open `profession`.
function Opener:Arm(anchor, profession, recipeID)
    self.wanted = { anchor = anchor, profession = profession, recipeID = recipeID }

    if InCombat() then return false end

    local overlay = self:CreateOverlay()

    if self.anchor ~= anchor then
        self.anchor = anchor
        self.placed = nil

        -- The craft button is ours, so hooking it is safe. Moving or hiding the
        -- window moves or hides the secure button with it.
        if not anchor.btsOpenerHooked then
            anchor.btsOpenerHooked = true
            anchor:HookScript("OnUpdate", function(button)
                if Opener.anchor == button and Opener.overlay:IsShown() then
                    Opener:Place()
                end
            end)
            anchor:HookScript("OnShow", function(button)
                if Opener.anchor == button and Opener.armed and not InCombat() then
                    Opener.placed = nil
                    Opener:Place()
                    Opener.overlay:Show()
                end
            end)
            anchor:HookScript("OnHide", function(button)
                if Opener.anchor == button and not InCombat() then
                    Opener.overlay:Hide()
                end
            end)
        end
    end

    overlay.label:SetText(("Open %s"):format(profession.name))

    if overlay:GetAttribute("spell") ~= profession.spell then
        overlay:SetAttribute("type", "spell")
        overlay:SetAttribute("spell", profession.spell)
    end

    if self.direction ~= CLICK_DIRECTION then
        overlay:RegisterForClicks(CLICK_DIRECTION)
        overlay:SetAttribute("useOnKeyDown", false)
        self.direction = CLICK_DIRECTION
    end

    self.armed = profession
    self.armedRecipeID = recipeID
    self:Place()

    if anchor:IsVisible() then overlay:Show() end
    SetAnchorMouse(anchor, false)
    return true
end

--- Take the secure button away, so clicks reach the craft button again.
function Opener:Disarm()
    self.wanted = nil
    SetAnchorMouse(self.anchor, true)
    if InCombat() then return false end

    self.armed = nil
    self.armedRecipeID = nil
    if self.overlay then self.overlay:Hide() end
    return true
end

function Opener:IsArmed()
    return self.armed ~= nil and self.overlay ~= nil and self.overlay:IsShown()
end

--------------------------------------------------------------------------------
-- Reporting what happened
--------------------------------------------------------------------------------

-- A click is not a result. Say whether the window really opened, so a silent
-- failure cannot look like a success.
function Opener:OnClicked()
    local profession = self.armed
    if not profession then return end

    local token = {}
    self.pending = { profession = profession, token = token, at = GetTime() }

    C_Timer.After(OPEN_TIMEOUT, function()
        local pending = Opener.pending
        if not pending or pending.token ~= token then return end
        Opener.pending = nil

        ns.Warn(("clicked Open %s, but no profession window opened. "
            .. "Type /bts openprof and send the lines it prints."):format(profession.name))
        Opener:DescribeLastClick()
    end)
end

function Opener:OnTradeSkillShow()
    local pending = self.pending
    if not pending then return end
    self.pending = nil

    ns.Print(("opened your %s window. Click the button again to craft.")
        :format(pending.profession.name))
end

function Opener:OnEnable()
    -- The last moment a secure frame may still be hidden before combat locks it.
    ns.RegisterEvent(self, "PLAYER_REGEN_DISABLED", function()
        if Opener.overlay then Opener.overlay:Hide() end
        SetAnchorMouse(Opener.anchor, true)
    end)

    -- Put back whatever was wanted while combat held it.
    ns.RegisterEvent(self, "PLAYER_REGEN_ENABLED", function()
        if ns.UI and ns.UI.RefreshActiveTab then ns.UI:RefreshActiveTab() end
    end)

    ns.RegisterEvent(self, "TRADE_SKILL_SHOW", function()
        Opener:OnTradeSkillShow()
    end)
end

--------------------------------------------------------------------------------
-- /bts openprof
--------------------------------------------------------------------------------

function Opener:DescribeLastClick()
    local press = self.lastMouseDown
    ns.Print(press
        and ("Open button last felt the mouse press %s, %.1f seconds ago."):format(press.button, GetTime() - press.at)
        or "Open button has not felt a mouse press yet.")

    local click = self.lastClick
    if not click then
        ns.Print("Open button has not received a click yet.")
        return
    end
    ns.Print(("Open button last got %s %s, %.1f seconds ago.")
        :format(click.button, click.down and "down" or "up", GetTime() - click.at))
end

local function DescribePlacement()
    local overlay, anchor = Opener.overlay, Opener.anchor
    if not overlay or not anchor then return end

    ns.Print(("Open button layer: %s %d over the craft button's %s %d, size %dx%d, %s.")
        :format(overlay:GetFrameStrata(), overlay:GetFrameLevel(),
            anchor:GetFrameStrata(), anchor:GetFrameLevel(),
            overlay:GetWidth() or 0, overlay:GetHeight() or 0,
            overlay:IsShown() and "showing" or "hidden"))
    ns.Print(("Craft button takes mouse: %s."):format(tostring(anchor:IsMouseEnabled())))

    -- Both in screen pixels, so a scale mistake shows up as different numbers.
    local function Screen(frame)
        local scale = frame:GetEffectiveScale()
        return (frame:GetLeft() or 0) * scale, (frame:GetBottom() or 0) * scale
    end
    local ox, oy = Screen(overlay)
    local ax, ay = Screen(anchor)
    ns.Print(("Open button at %d,%d; craft button at %d,%d. Mouse over Open: %s, over craft: %s, Open takes mouse: %s.")
        :format(ox, oy, ax, ay,
            tostring(overlay:IsMouseOver()), tostring(anchor:IsMouseOver()),
            tostring(overlay:IsMouseEnabled())))
end

--- A click reached the craft button while it read "Open ...", so the secure
-- button did not catch it. Say why, as far as we can tell, and put it back.
function Opener:MissedClick()
    if InCombat() then
        ns.Print("the Queue cannot open a profession during combat. Open it yourself, or try again after the fight.")
        return
    end

    ns.Warn("that click missed the Open button. Click it again; if it misses twice, "
        .. "type /bts openprof and send the lines it prints.")
    DescribePlacement()
    self:DescribeLastClick()

    self.placed = nil
    self:Place()
    if self.overlay and self.armed and self.anchor and self.anchor:IsVisible() then
        self.overlay:Show()
    end
end

local function Describe()
    local armed = Opener.armed
    if armed then
        ns.Print(("Open button: set to cast '%s' for %s, %s, clicks on %s.")
            :format(armed.spell, armed.name,
                Opener:IsArmed() and "showing" or "hidden",
                Opener.direction == "AnyDown" and "key down" or "key up"))
    elseif Opener.wanted and InCombat() then
        ns.Print("Open button: waiting for combat to end.")
    else
        ns.Print("Open button: not in use (no queued craft needs a window opened).")
    end
    DescribePlacement()
    Opener:DescribeLastClick()
end

-- C_TradeSkillUI.OpenTradeSkill was tried here from addon code: in game it
-- opened nothing for 2945, and the game then reported "Interface action
-- failed because of an AddOn" (most likely the 165 try). The secure button is the
-- only way, so this command now only reports on it.
ns.RegisterCommand("openprof", "check the Queue tab's Open profession button", Describe)
