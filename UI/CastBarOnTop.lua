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
local L = ns.L or setmetatable({ Format = string.format }, { __index = function(_, key) return key end })

local CastBar = ns.NewModule("CastBarOnTop")

local TOP_STRATA = "TOOLTIP"

-- The player's cast bar goes by different names in different clients.
-- The overlay one is the bar some clients draw over the profession window.
local BAR_NAMES = { "PlayerCastingBarFrame", "OverlayPlayerCastingBarFrame", "CastingBarFrame" }

-- A run of crafts is one cast after another with a short gap between. Wait
-- this long after a cast stops before putting the bar back, so it does not
-- flicker down and up again between two crafts.
local SETTLE = 0.4

CastBar.saved = {}     -- bar name -> strata it had before it was raised
CastBar.raised = false

-- Bars already hooked. Kept here rather than marked on the bar itself: the
-- addon never writes to the game's own frames.
local hooked = setmetatable({}, { __mode = "k" })

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

--- Is this event about the player's own cast?
-- These events fire for every unit, and inside a dungeon the game hands the
-- addon a unit token it may not compare: `unit ~= "player"` raised a Lua error
-- on every cast by every mob and party member. The comparison happens inside
-- the pcall, and a token that cannot be read is not the player.
local function IsPlayer(unit)
    local ok, yes = pcall(function() return unit == "player" end)
    return ok and yes == true
end
CastBar.IsPlayer = IsPlayer

--- Is this spell one of the character's recipes, the craft the addon
--- started, or a queued craft? A recipe's ID is its spell's ID, and the name
--- is checked too in case a client hands back no spell ID.
-- @return true, false, or nil when no recipes are known to check against
function CastBar:IsRecipeCast(name, spellID)
    local crafting = ns.Crafting
    if spellID and crafting and crafting.active and crafting.active.recipeID == spellID then
        return true
    end

    local recipes = ns.Recipes and ns.Recipes.GetAll and ns.Recipes:GetAll() or {}
    if spellID and recipes[spellID] then return true end

    local any = false
    for _, recipe in pairs(recipes) do
        any = true
        if type(recipe) == "table" and name and recipe.name == name then return true end
    end

    for _, entry in ipairs(ns.Queue and ns.Queue.GetAll and ns.Queue:GetAll() or {}) do
        any = true
        if spellID and entry.recipeID == spellID then return true end
    end

    if not any then return nil end
    return false
end

--- Whether the player is casting a craft right now.
function CastBar:IsCrafting()
    if type(UnitCastingInfo) ~= "function" then return false end

    -- The cast's name and craft flag are tested inside the pcall too, for the
    -- same reason: a value the game will not let us read is not a craft.
    local ok, flag, name, spellID = pcall(function()
        local castName, _, _, _, _, isTradeSkill, _, _, castSpellID = UnitCastingInfo("player")
        if not castName then return false end
        if isTradeSkill then return true end
        -- Copied out as plain values, still inside the pcall.
        return nil, castName .. "", tonumber(castSpellID)
    end)
    if not ok or flag == false then return false end
    if flag == true then return true end

    -- Some clients leave isTradeSkill empty. Then a cast with the profession
    -- window open, or while the addon is crafting, counts only when the spell
    -- is a recipe: a Hearthstone with the window open is not a craft.
    local crafting = ns.Crafting
    if not (crafting ~= nil and (crafting.isTradeSkillOpen or crafting.active ~= nil)) then
        return false
    end

    local okRecipe, isRecipe = pcall(self.IsRecipeCast, self, name, spellID)
    if not okRecipe then return false end
    -- No recipes saved yet to tell by: any cast counts, as before.
    return isRecipe ~= false
end

function CastBar:Raise()
    for _, bar in ipairs(Bars()) do
        local frame = bar.frame
        if self.saved[bar.name] == nil then
            local ok, strata = pcall(frame.GetFrameStrata, frame)
            self.saved[bar.name] = ok and strata or "MEDIUM"
        end
        pcall(frame.SetFrameStrata, frame, TOP_STRATA)

        -- The game may set the bar's layer again when it shows the bar for
        -- the next cast, so lift it again whenever it shows mid-run.
        if not hooked[frame] and type(frame.HookScript) == "function" then
            hooked[frame] = true
            pcall(frame.HookScript, frame, "OnShow", function(shown)
                if CastBar.raised then pcall(shown.SetFrameStrata, shown, TOP_STRATA) end
            end)
        end
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
    if not IsPlayer(unit) then return end
    if self:IsCrafting() then self:Raise() end
end

function CastBar:OnCastEnd(_, unit)
    if not self.raised or not IsPlayer(unit) then return end

    C_Timer.After(SETTLE, function()
        if CastBar.raised and not CastBar:IsCrafting() then
            CastBar:Restore()
        end
    end)
end

-- Only the player's casts are wanted (ns.RegisterPlayerEvent).
local function RegisterForPlayer(event, fn)
    if ns.RegisterPlayerEvent then return ns.RegisterPlayerEvent(CastBar, event, fn) end
    return CastBar:RegisterEvent(event, fn)
end
RegisterForPlayer("UNIT_SPELLCAST_START", CastBar.OnCastStart)
RegisterForPlayer("UNIT_SPELLCAST_STOP", CastBar.OnCastEnd)
RegisterForPlayer("UNIT_SPELLCAST_INTERRUPTED", CastBar.OnCastEnd)
RegisterForPlayer("UNIT_SPELLCAST_FAILED", CastBar.OnCastEnd)

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

ns.RegisterCommand("castbar", L["check the cast bar is kept on top while crafting"], Describe)
