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

-- Fire on key down or up to match the game's own action buttons. Registering
-- both would cast twice on a client whose template ignores the direction,
-- and a second cast of a profession closes the window the first one opened.
local function ClickDirection()
    if type(GetCVarBool) == "function" then
        local ok, down = pcall(GetCVarBool, "ActionButtonUseKeyDown")
        if ok and down then return "AnyDown" end
    end
    return "AnyUp"
end

function Opener:CreateOverlay()
    if self.overlay then return self.overlay end

    local overlay = CreateFrame("Button", "BlackthornesTSOpenProfession", UIParent,
        "SecureActionButtonTemplate")
    overlay:Hide()

    -- Hovering the invisible button should look like hovering the one under it.
    overlay:SetScript("OnEnter", function()
        local anchor = Opener.anchor
        local handler = anchor and anchor:GetScript("OnEnter")
        if handler then handler(anchor) end
    end)

    overlay:SetScript("OnLeave", function()
        local anchor = Opener.anchor
        local handler = anchor and anchor:GetScript("OnLeave")
        if handler then handler(anchor) end
    end)

    -- Runs after the secure cast. Only notes the click, so the outcome can be
    -- reported once we know whether a window actually opened.
    overlay:SetScript("PostClick", function()
        Opener:OnClicked()
    end)

    self.overlay = overlay
    return overlay
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

    local last = self.placed
    if last and last[1] == x and last[2] == y and last[3] == w and last[4] == h then
        return
    end

    -- Same layer as the craft button, just above it, so a bag or another
    -- window lying over ours still gets its own clicks.
    overlay:SetFrameStrata(anchor:GetFrameStrata())
    overlay:SetFrameLevel(anchor:GetFrameLevel() + 5)

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

    if overlay:GetAttribute("spell") ~= profession.spell then
        overlay:SetAttribute("type", "spell")
        overlay:SetAttribute("spell", profession.spell)
    end

    local direction = ClickDirection()
    if self.direction ~= direction then
        overlay:RegisterForClicks(direction)
        self.direction = direction
    end

    self.armed = profession
    self.armedRecipeID = recipeID
    self:Place()

    if anchor:IsVisible() then overlay:Show() end
    return true
end

--- Take the secure button away, so clicks reach the craft button again.
function Opener:Disarm()
    self.wanted = nil
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
end

-- Tries the other route, C_TradeSkillUI.OpenTradeSkill, straight from addon
-- code, and reports whether a window opened. If it works, a single click could
-- one day open and craft; if the game blocks it, that is worth knowing too.
ns.RegisterCommand("openprof", "check the Queue tab's Open profession button", function()
    Describe()

    local api = _G.C_TradeSkillUI
    local target = Opener.armed
    if not target then
        local entry = ns.Crafting:GetNextReady()
        target = entry and Opener:ProfessionFor(entry.recipeID)
    end

    if not target then
        ns.Print("Nothing queued that needs a profession opened, so no open test was run.")
        return
    end

    if ns.Crafting.isTradeSkillOpen then
        ns.Print("A profession window is already open. Close it and run /bts openprof again to test opening.")
        return
    end

    if not api or type(api.OpenTradeSkill) ~= "function" then
        ns.Print("OpenTradeSkill: not in this version of the game.")
        return
    end

    local ok, err = pcall(api.OpenTradeSkill, target.skillLineID)
    if not ok then
        ns.Print(("OpenTradeSkill(%d): refused: %s"):format(target.skillLineID, tostring(err)))
        return
    end

    C_Timer.After(1.5, function()
        ns.Print(("OpenTradeSkill(%d) for %s: window %s.")
            :format(target.skillLineID, target.name,
                ns.Crafting.isTradeSkillOpen and "OPENED" or "did NOT open"))
    end)
end)
