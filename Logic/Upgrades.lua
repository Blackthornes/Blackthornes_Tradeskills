-- Blackthornes Tradeskills -- Logic/Upgrades.lua
-- Is this item an upgrade for the character playing? Asked of Blackthornes
-- Equipment, so the green arrow on an icon here means exactly what the arrow
-- in the bags means (2026-09-30).
--
-- Equipment is optional. Without it every answer is "no" and nothing is
-- drawn; Tradeskills works as before. With it, Equipment's own
-- Compare:IsUpgrade(itemID) decides: gear the character can wear now that
-- beats what is worn, for the spec Equipment judges them as.
--
-- Read through `_G.BlackthornesEquipment`, inside a pcall. Equipment's
-- CLAUDE.md asks its side to keep that global, `Compare` and
-- `Compare:IsUpgrade(item)` stable.
--
-- Answers are kept per item ID, since a list redraws its rows often and each
-- answer weighs the worn gear too. They are forgotten whenever the answer
-- could change: new gear on, a level, talents, or an item's details arriving.

local _, ns = ...
local L = ns.L or setmetatable({ Format = string.format }, { __index = function(_, key) return key end })

local Upgrades = ns.NewModule("Upgrades")

local known = {}
local enchants = {}
local alts = {}

--- Equipment's Compare module, or nil when Equipment is not loaded (or too
--- old to answer).
function Upgrades:Equipment()
    local equipment = rawget(_G, "BlackthornesEquipment")
    if type(equipment) ~= "table" then return nil end

    local compare = equipment.Compare
    if type(compare) ~= "table" or type(compare.IsUpgrade) ~= "function" then return nil end
    return compare
end

function Upgrades:IsEnabled()
    return not (ns.Config and ns.Config:Get("showUpgradeArrows") == false)
end

--- True when the item is an upgrade the character can wear now. False for
--- everything else, including when Equipment is not there. Never raises.
--
-- `link` is optional: a bag item's link, when the caller has one. Random-suffix
-- gear ("of the Monkey") shares its item ID with every other suffix, so asked
-- by ID it got the plain item's answer. With a link Equipment is asked about
-- that exact copy, and the answer is kept under the link's item string.
function Upgrades:IsUpgrade(itemID, link)
    itemID = tonumber(itemID)
    if not itemID or not self:IsEnabled() then return false end

    local compare = self:Equipment()
    if not compare then return false end

    -- The item string ("item:12345:0:...") names the copy, suffix and all,
    -- without the colour and name around it. Read and copied (the `.. ""`)
    -- inside a pcall: a link can be a value the client does not let addons
    -- read, and as a key below it would raise. Without one, by ID.
    local item, key = itemID, itemID
    if type(link) == "string" then
        local ok, itemString = pcall(function()
            local found = string.match(link, "item[%-?%d:]+")
            return found and found .. ""
        end)
        if ok and type(itemString) == "string" then item, key = link, itemString end
    end

    local answer = known[key]
    if answer == nil then
        local ok, result = pcall(compare.IsUpgrade, compare, item)
        answer = ok and result == true
        known[key] = answer
    end
    return answer
end

--- What an enchanting recipe would do for the character playing, from
--- Equipment's Enchants:ForRecipe: `{ slot, slotID, gain, current, best }`,
--- or nil when it beats nothing worn, or Equipment is not there (or too old
--- to say). Kept per recipe, like the item answers, so a list's redraw asks
--- once. Never raises.
function Upgrades:EnchantFor(recipeID)
    recipeID = tonumber(recipeID)
    if not recipeID or not self:IsEnabled() then return nil end

    local kept = enchants[recipeID]
    if kept ~= nil then return kept or nil end

    local answer = false
    local equipment = rawget(_G, "BlackthornesEquipment")
    local module = type(equipment) == "table" and equipment.Enchants
    if type(module) == "table" and type(module.ForRecipe) == "function" then
        local ok, result = pcall(module.ForRecipe, module, recipeID)
        if ok and type(result) == "table" and type(result.slot) == "string" then
            answer = {
                slot = result.slot,
                gain = tonumber(result.gain),
                current = type(result.current) == "string" and result.current or nil,
                best = result.best == true,
            }
        end
    end
    enchants[recipeID] = answer
    return answer or nil
end

--- "For you: Chest +3%", or nil when the enchant beats nothing worn.
--- With `short`, only "Chest +3%".
function Upgrades:EnchantText(recipeID, short)
    local answer = self:EnchantFor(recipeID)
    if not answer then return nil end
    local gain = answer.gain and answer.gain > 0 and answer.gain or nil
    if short then
        return gain and L.Format("%s +%d%%", answer.slot, gain) or answer.slot
    end
    if gain then return L.Format("For you: %s +%d%%", answer.slot, gain) end
    return L.Format("For you: %s", answer.slot)
end

--- Whether a crafted item is an upgrade for one of your other characters,
--- from Equipment's Butler:Advise (its `alt`, 2026-10-16): `{ name, gain,
--- level }`, or nil when it is none, it is an upgrade here, or Equipment
--- is not there. `name` is the character's whole name, `gain` a whole
--- percent (nil for an empty slot), `level` when it waits on their level.
--- Kept per item, like the other answers. Never raises.
function Upgrades:AltFor(itemID)
    itemID = tonumber(itemID)
    if not itemID or not self:IsEnabled() or not self:ShowsAlts() then return nil end

    local kept = alts[itemID]
    if kept ~= nil then return kept or nil end

    local answer = false
    local equipment = rawget(_G, "BlackthornesEquipment")
    local butler = type(equipment) == "table" and equipment.Butler
    if type(butler) == "table" and type(butler.Advise) == "function" then
        local ok, advice = pcall(butler.Advise, butler, itemID)
        local alt = ok and type(advice) == "table" and advice.alt
        if type(alt) == "table" and type(alt.key) == "string" and ns.Recipes and ns.Recipes.GetCharacterName then
            local named, name = pcall(ns.Recipes.GetCharacterName, ns.Recipes, alt.key)
            if named and type(name) == "string" and name ~= "" and name ~= "?" and name ~= alt.key then
                local gain = tonumber(alt.gain)
                answer = {
                    name = name,
                    gain = gain and gain > 0 and math.floor(gain + 0.5) or nil,
                    level = tonumber(alt.level),
                }
            end
        end
    end
    alts[itemID] = answer
    return answer or nil
end

--- Are other characters' upgrades shown on crafts? "Show Equipment
--- Upgrades" on Profit, Level Up and the Queue (the owner, 2026-10-17: off
--- until a player ticks it). One saved value for every box.
function Upgrades:ShowsAlts()
    return ns.Config and ns.Config:Get("showAltUpgrades") == true or false
end

local altBoxes = {}

--- Tick or untick every Show Equipment Upgrades box and redraw the tab.
function Upgrades:SetShowsAlts(on)
    on = on == true
    if ns.Config then ns.Config:Set("showAltUpgrades", on) end
    for _, box in ipairs(altBoxes) do
        if box.SetChecked then box:SetChecked(on) end
    end
    if ns.UI and ns.UI.RefreshActiveTab then pcall(ns.UI.RefreshActiveTab, ns.UI) end
end

--- The Show Equipment Upgrades box for a tab's filter row. Shown only while
--- Blackthornes Equipment is loaded, since nothing else says what an alt
--- would wear.
function Upgrades:CreateAltCheckbox(parent)
    local Widgets = ns.Widgets
    if not (Widgets and Widgets.CreateCheckbox) then return nil end
    local box = Widgets.CreateCheckbox(parent, L["Show Equipment Upgrades"], function(checked)
        Upgrades:SetShowsAlts(checked)
    end, self:ShowsAlts())
    if box.HookScript then
        box:HookScript("OnEnter", function(owner)
            GameTooltip:SetOwner(owner, "ANCHOR_BOTTOM")
            GameTooltip:SetText(L["Shows when a craft is an upgrade for one of your other characters."], 1, 1, 1, 1, true)
            GameTooltip:Show()
        end)
        box:HookScript("OnLeave", function() GameTooltip:Hide() end)
    end
    local equipment = rawget(_G, "BlackthornesEquipment")
    local butler = type(equipment) == "table" and equipment.Butler
    box:SetShown(type(butler) == "table" and type(butler.Advise) == "function")
    altBoxes[#altBoxes + 1] = box
    return box
end

--- "Upgrade for Ana Stormwood, +9%" (or "... at level 32"), or nil.
function Upgrades:AltText(itemID)
    local answer = self:AltFor(itemID)
    if not answer then return nil end
    if answer.level then
        return L.Format("Upgrade for %s at level %d", answer.name, answer.level)
    end
    if answer.gain then return L.Format("Upgrade for %s, +%d%%", answer.name, answer.gain) end
    return L.Format("Upgrade for %s", answer.name)
end

--- A row's name with the alt line after it in green, or the name as it is.
function Upgrades:WithAltText(name, itemID)
    local text = itemID and self:AltText(itemID)
    if not text then return name end
    return ("%s  |c%s%s|r"):format(name, ns.COLORS and ns.COLORS.profit or "ff4fd17a", text)
end

--- Forget every answer, so the next draw asks again.
function Upgrades:Forget()
    -- Items arrive from the server all the time (chat links, the auction
    -- house); a new table each time is garbage when nothing was kept.
    if next(known) then known = {} end
    if next(enchants) then enchants = {} end
    if next(alts) then alts = {} end
end

--- Forget, and redraw the open tab, the craft pane and the sell list once
--- things settle, so a burst of events (a whole outfit swapped) costs one
--- redraw.
function Upgrades:RedrawSoon()
    self:Forget()
    if self.pending then return end
    self.pending = true

    local function Redraw()
        Upgrades.pending = false
        if ns.UI and ns.UI.RefreshActiveTab then pcall(ns.UI.RefreshActiveTab, ns.UI) end

        -- The craft pane and the sell list draw item icons too, outside the
        -- main window, so its redraw left their arrows as they were.
        local craft, post = ns.CraftPanel, ns.PostPanel
        if craft and craft.IsShown and craft:IsShown() then pcall(craft.RequestRefresh, craft) end
        if post and post.IsShown and post:IsShown() then pcall(post.Refresh, post) end
    end

    if type(C_Timer) == "table" and type(C_Timer.After) == "function" then
        C_Timer.After(0.3, Redraw)
    else
        Redraw()
    end
end

-- What can change which items are upgrades.
local CHANGES = { "PLAYER_EQUIPMENT_CHANGED", "PLAYER_LEVEL_UP", "TRAIT_CONFIG_UPDATED" }

function Upgrades:OnEnable()
    for _, event in ipairs(CHANGES) do
        ns.RegisterEvent(self, event, self.RedrawSoon)
    end

    -- An item's stats arriving, or the worn gear's, can turn a "no" into a
    -- "yes". The tabs already redraw for this event, so answers are only
    -- forgotten here.
    ns.RegisterEvent(self, "GET_ITEM_INFO_RECEIVED", function() Upgrades:Forget() end)
end
