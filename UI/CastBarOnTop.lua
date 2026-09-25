-- Blackthornes Tradeskills -- UI/CastBarOnTop.lua
-- Keeps the game's cast bar on top of everything while a craft is going.
--
-- The addon's windows sit in the HIGH strata and rise when clicked, so they
-- can cover the cast bar and hide how far along a craft is. While a craft is
-- casting, the cast bar is lifted to the TOOLTIP strata, the top one. When
-- the craft run ends it goes back to where it was.
--
-- Only the cast bar moves. The addon's windows keep their own layer, so they
-- still sit where they always did against the rest of the game's windows.
-- Changing a frame's strata is not a protected action (the cast bar is not a
-- secure frame), and nothing here writes to Blizzard's tables.

local _, ns = ...

local CastBar = ns.NewModule("CastBarOnTop")

local TOP_STRATA = "TOOLTIP"

-- The player's cast bar goes by different names in different clients.
local BAR_NAMES = { "PlayerCastingBarFrame", "CastingBarFrame" }

-- A run of crafts is one cast after another with a short gap between. Wait
-- this long after a cast stops before putting the bar back, so it does not
-- flicker down and up again between two crafts.
local SETTLE = 0.4

CastBar.saved = {}     -- bar name -> strata it had before it was raised
CastBar.raised = false

local function Bars()
    local found = {}
    for _, name in ipairs(BAR_NAMES) do
        local bar = _G[name]
        if type(bar) == "table" and type(bar.SetFrameStrata) == "function" then
            found[#found + 1] = { name = name, frame = bar }
        end
    end
    return found
end

--- Whether the player is casting a craft right now.
function CastBar:IsCrafting()
    if type(UnitCastingInfo) ~= "function" then return false end

    local ok, name, _, _, _, _, isTradeSkill = pcall(UnitCastingInfo, "player")
    if not ok or not name then return false end
    if isTradeSkill then return true end

    -- Some clients leave isTradeSkill empty. A cast with the profession
    -- window open, or one the addon itself started, is a craft too.
    local crafting = ns.Crafting
    return crafting ~= nil and (crafting.isTradeSkillOpen or crafting.active ~= nil)
end

function CastBar:Raise()
    for _, bar in ipairs(Bars()) do
        local frame = bar.frame
        if self.saved[bar.name] == nil then
            local ok, strata = pcall(frame.GetFrameStrata, frame)
            self.saved[bar.name] = ok and strata or "MEDIUM"
        end
        pcall(frame.SetFrameStrata, frame, TOP_STRATA)
    end
    self.raised = true
end

function CastBar:Restore()
    for _, bar in ipairs(Bars()) do
        local strata = self.saved[bar.name]
        if strata then
            pcall(bar.frame.SetFrameStrata, bar.frame, strata)
            self.saved[bar.name] = nil
        end
    end
    self.raised = false
end

function CastBar:OnCastStart(_, unit)
    if unit ~= "player" then return end
    if self:IsCrafting() then self:Raise() end
end

function CastBar:OnCastEnd(_, unit)
    if unit ~= "player" or not self.raised then return end

    C_Timer.After(SETTLE, function()
        if CastBar.raised and not CastBar:IsCrafting() then
            CastBar:Restore()
        end
    end)
end

CastBar:RegisterEvent("UNIT_SPELLCAST_START", CastBar.OnCastStart)
CastBar:RegisterEvent("UNIT_SPELLCAST_STOP", CastBar.OnCastEnd)
CastBar:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED", CastBar.OnCastEnd)
CastBar:RegisterEvent("UNIT_SPELLCAST_FAILED", CastBar.OnCastEnd)

--- /bts castbar: which cast bar was found and what layer it is on now.
local function Describe()
    local bars = Bars()
    if #bars == 0 then
        ns.Warn("Cast bar: none found, so it cannot be kept on top.")
        return
    end
    for _, bar in ipairs(bars) do
        local ok, strata = pcall(bar.frame.GetFrameStrata, bar.frame)
        ns.Print(("Cast bar %s: layer %s%s."):format(bar.name,
            ok and tostring(strata) or "unknown",
            CastBar.saved[bar.name] and (", raised from " .. CastBar.saved[bar.name]) or ""))
    end
    ns.Print(CastBar:IsCrafting() and "Crafting now: yes." or "Crafting now: no.")
end

ns.RegisterCommand("castbar", "check the cast bar is kept on top while crafting", Describe)
