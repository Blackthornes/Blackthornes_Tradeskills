-- Blackthornes Tradeskills -- UI/UpgradesOnly.lua
-- "Upgrades Only:" on Blizzard's profession window (the owner, 2026-11-22,
-- from the mockup ts-upgrades-only-recipes.html). Ticked, the recipe list
-- shows only the crafts whose made item Equipment calls an upgrade for the
-- character playing (Upgrades:IsUpgrade, the same answer as the green
-- arrow), still under their category headings. Search and Filter narrow the
-- list as before, since what is filtered is Blizzard's own list after them.
--
-- Off until ticked, saved account wide as `upgradesOnlyRecipes` (never
-- rename it). The box shows only while Equipment is loaded and the upgrade
-- arrows are on; without them every answer would be "no".
--
-- How the list is filtered: Blizzard hands its recipe scroll box a tree of
-- category and recipe nodes (SetDataProvider). A hook after that call builds
-- a second tree holding only the upgrades, pointing at Blizzard's own entry
-- tables, and hands that to the scroll box. Blizzard's tree is never changed,
-- and is handed back when the box is unticked. Nothing is written onto a
-- Blizzard frame and none is hidden or shown; the only change to one is that
-- the scroll box starts a little lower, to make room for the box, and goes
-- back when the box goes away.
--
-- Work happens only when Blizzard sends a new list or an upgrade answer may
-- have changed, and a new tree is handed over only when the set of upgrades
-- is different, so the list does not jump while nothing changed.

local _, ns = ...
local L = ns.L or setmetatable({ Format = string.format }, { __index = function(_, key) return key end })

local UpgradesOnly = ns.NewModule("UpgradesOnly")

local FRAME_NAMES = { "ProfessionsFrame", "TradeSkillFrame" }
local LIST_PATHS = { "CraftingPage.RecipeList", "RecipeList" }

-- Room made under the search box for the box, in the window's pixels.
UpgradesOnly.ROOM = 20

-- How long to wait after item details arrive before asking again. They come
-- in bursts of dozens.
UpgradesOnly.ITEM_INFO_WAIT = 0.5

local function Field(object, key)
    if type(object) ~= "table" then return nil end
    local ok, value = pcall(function() return object[key] end)
    if ok then return value end
    return nil
end

local function Try(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b = pcall(fn, ...)
    if ok then return a, b end
    return nil
end

local function Descend(frame, path)
    local current = frame
    for segment in path:gmatch("[^%.]+") do
        current = Field(current, segment)
        if current == nil then return nil end
    end
    return current
end

--------------------------------------------------------------------------------
-- The setting
--------------------------------------------------------------------------------

function UpgradesOnly:IsOn()
    return ns.Config ~= nil and ns.Config:Get("upgradesOnlyRecipes") == true
end

function UpgradesOnly:SetOn(on)
    if ns.Config then ns.Config:Set("upgradesOnlyRecipes", on == true) end
    if self.box and self.box.SetChecked then self.box:SetChecked(on == true) end
    self:Apply()
end

--- True while Equipment can answer and the arrows are on.
function UpgradesOnly:Available()
    local upgrades = ns.Upgrades
    if not upgrades then return false end
    return upgrades:Equipment() ~= nil and upgrades:IsEnabled() == true
end

--------------------------------------------------------------------------------
-- Which recipes stay
--------------------------------------------------------------------------------

local function RecipeIDOf(data)
    local info = Field(data, "recipeInfo")
    local id = Field(info, "recipeID")
    if type(id) == "number" then return id end
    id = Field(data, "recipeID")
    if type(id) == "number" then return id end
    return nil
end

--- The item a recipe makes: the addon's own record first, then the client.
function UpgradesOnly:MadeItem(recipeID)
    local recipes = ns.Recipes
    if recipes then
        local recipe = Try(recipes.Get, recipes, recipeID)
        if not recipe and recipes.GetAny then recipe = Try(recipes.GetAny, recipes, recipeID) end
        local itemID = type(recipe) == "table" and tonumber(recipe.outputItemID)
        if itemID then return itemID end
    end
    local trade = rawget(_G, "C_TradeSkillUI")
    local out = Try(Field(trade, "GetRecipeOutputItemData"), recipeID)
    return type(out) == "table" and tonumber(Field(out, "itemID")) or nil
end

function UpgradesOnly:MakesUpgrade(recipeID)
    local itemID = recipeID and self:MadeItem(recipeID)
    if not itemID then return false end
    return ns.Upgrades:IsUpgrade(itemID) == true
end

local function NodesOf(node)
    local nodes = Try(Field(node, "GetNodes"), node)
    if type(nodes) == "table" then return nodes end
    return {}
end

--- Copy one node's kept children under `into`. Returns how many recipes
--- were kept beneath it, and adds each to `kept`.
function UpgradesOnly:CopyChildren(node, into, kept, depth)
    local count = 0
    for _, child in ipairs(NodesOf(node)) do
        local data = Try(Field(child, "GetData"), child)
        local recipeID = RecipeIDOf(data)
        local children = NodesOf(child)

        if recipeID then
            if self:MakesUpgrade(recipeID) then
                into:Insert(data)
                kept[#kept + 1] = recipeID
                count = count + 1
            end
        elseif #children > 0 then
            -- A category: kept only while it still holds an upgrade.
            if self:CountKept(child) > 0 then
                local copy = into:Insert(data)
                local collapsed = Try(Field(child, "IsCollapsed"), child)
                count = count + self:CopyChildren(child, copy, kept, depth + 1)
                if collapsed and copy.SetCollapsed then pcall(copy.SetCollapsed, copy, true) end
            end
        elseif depth > 0 then
            -- Spacing inside a category that stays.
            into:Insert(data)
        end
    end
    return count
end

--- How many recipes under a node would stay.
function UpgradesOnly:CountKept(node)
    local count = 0
    for _, child in ipairs(NodesOf(node)) do
        local recipeID = RecipeIDOf(Try(Field(child, "GetData"), child))
        if recipeID then
            if self:MakesUpgrade(recipeID) then count = count + 1 end
        else
            count = count + self:CountKept(child)
        end
    end
    return count
end

--- A new tree with only the upgrades in it, and the kept recipe IDs.
-- nil when the list is not a shape this knows.
function UpgradesOnly:Build(source)
    local root = Try(Field(source, "GetRootNode"), source)
    local make = rawget(_G, "CreateTreeDataProvider")
    if type(root) ~= "table" or type(make) ~= "function" then return nil end

    local built = Try(make)
    local into = built and Try(Field(built, "GetRootNode"), built)
    if type(into) ~= "table" or type(into.Insert) ~= "function" then return nil end

    local kept = {}
    self:CopyChildren(root, into, kept, 0)
    return built, kept
end

--------------------------------------------------------------------------------
-- The window
--------------------------------------------------------------------------------

function UpgradesOnly:FindList()
    for _, name in ipairs(FRAME_NAMES) do
        local frame = rawget(_G, name)
        if type(frame) == "table" then
            for _, path in ipairs(LIST_PATHS) do
                local list = Descend(frame, path)
                local scroll = Field(list, "ScrollBox")
                if type(Field(scroll, "SetDataProvider")) == "function"
                    and type(Field(scroll, "GetDataProvider")) == "function" then
                    return list, scroll, frame, name .. "." .. path
                end
            end
        end
    end
    return nil
end

local function Points(region)
    local points = {}
    local count = Try(Field(region, "GetNumPoints"), region) or 0
    for i = 1, count do
        local ok, point, relativeTo, relativePoint, x, y = pcall(region.GetPoint, region, i)
        if ok and point then
            points[#points + 1] = { point, relativeTo, relativePoint, x or 0, y or 0 }
        end
    end
    return points
end

local function SetPoints(region, points, drop)
    if #points == 0 then return end
    pcall(region.ClearAllPoints, region)
    for _, p in ipairs(points) do
        local y = p[5]
        if drop and p[1]:find("TOP", 1, true) then y = y - drop end
        pcall(region.SetPoint, region, p[1], p[2], p[3], p[4], y)
    end
end

--- Start the scroll box lower to fit the box, or put it back.
function UpgradesOnly:MakeRoom(scroll, on)
    if on then
        if self.moved and self.moved.scroll == scroll then return end
        self:MakeRoom(nil, false)
        local points = Points(scroll)
        if #points == 0 then return end
        self.moved = { scroll = scroll, points = points }
        SetPoints(scroll, points, self.ROOM)
    elseif self.moved then
        SetPoints(self.moved.scroll, self.moved.points)
        self.moved = nil
    end
end

function UpgradesOnly:CreateBox(list)
    local Widgets = ns.Widgets
    if not (Widgets and Widgets.CreateCheckbox) then return nil end

    local box = Widgets.CreateCheckbox(list, L["Upgrades Only:"], function(checked)
        UpgradesOnly:SetOn(checked)
    end, self:IsOn())

    if box.HookScript then
        box:HookScript("OnEnter", function(owner)
            GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
            GameTooltip:SetText(L["Upgrades Only:"])
            GameTooltip:AddLine(L["Shows only the gear you can make that beats what you wear now."], 1, 1, 1, true)
            GameTooltip:Show()
        end)
        box:HookScript("OnLeave", function() GameTooltip:Hide() end)
    end

    local search = Field(list, "SearchBox")
    if search then
        box:SetPoint("TOPLEFT", search, "BOTTOMLEFT", -4, -3)
    else
        box:SetPoint("TOPLEFT", list, "TOPLEFT", 8, -30)
    end

    return box
end

function UpgradesOnly:CreateEmpty(list, scroll)
    local holder = CreateFrame("Frame", nil, list)
    holder:SetPoint("TOPLEFT", scroll, "TOPLEFT", 10, -16)
    holder:SetPoint("TOPRIGHT", scroll, "TOPRIGHT", -10, -16)
    holder:SetHeight(40)

    local Theme = ns.Theme
    local text
    if Theme and Theme.CreateLabel then
        text = Theme.CreateLabel(holder, "small", "muted", "CENTER")
    else
        text = holder:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    end
    text:SetAllPoints(holder)
    if text.SetJustifyH then text:SetJustifyH("CENTER") end
    if text.SetWordWrap then text:SetWordWrap(true) end
    text:SetText(L["Nothing you can make here is an upgrade right now."])

    holder:Hide()
    return holder
end

--- Find the list, add the box once, and hook Blizzard's list handover.
function UpgradesOnly:Attach()
    local list, scroll, _, path = self:FindList()
    self.path = path
    if not list then return false end

    if self.scroll ~= scroll then
        self.scroll, self.list = scroll, list
        self.source, self.mine, self.keptKey = nil, nil, nil

        self.hooked = self.hooked or setmetatable({}, { __mode = "k" })
        if not self.hooked[scroll] and type(_G.hooksecurefunc) == "function" then
            self.hooked[scroll] = pcall(_G.hooksecurefunc, scroll, "SetDataProvider", function(box, provider)
                UpgradesOnly:OnNewList(box, provider)
            end)
        end

        if self.box then self.box:Hide() end
        if self.empty then self.empty:Hide() end
        self.box = self:CreateBox(list)
        self.empty = self:CreateEmpty(list, scroll)
    end

    -- On the first open of a session the list may have been handed over
    -- before the hook was in place.
    local current = Try(scroll.GetDataProvider, scroll)
    if current and current ~= self.mine then self.source = current end

    -- Kept off the gamepad's window cursor (see Compat.KeepOffGamepad).
    local Compat = ns.Compat
    if Compat and Compat.KeepOffGamepad then
        Compat.KeepOffGamepad(self.box)
        Compat.KeepOffGamepad(self.empty)
    end

    self:Apply()
    return true
end

--- Blizzard handed its scroll box a list.
function UpgradesOnly:OnNewList(scroll, provider)
    if self.applying or scroll ~= self.scroll or provider == self.mine then return end
    self.source, self.mine, self.keptKey = provider, nil, nil
    if self:IsOn() and self:Available() then self:Apply() end
end

local function SameKept(a, b)
    if not (a and b) or #a ~= #b then return false end
    for i = 1, #a do
        if a[i] ~= b[i] then return false end
    end
    return true
end

local function Hand(scroll, provider)
    local retain = rawget(_G, "ScrollBoxConstants")
    retain = type(retain) == "table" and retain.RetainScrollPosition or nil
    UpgradesOnly.applying = true
    pcall(scroll.SetDataProvider, scroll, provider, retain)
    UpgradesOnly.applying = false
end

--- Show the list the box asks for.
function UpgradesOnly:Apply()
    local scroll = self.scroll
    if not scroll then return end

    local available = self:Available()
    if self.box then
        self.box:SetShown(available)
        if self.box.SetChecked then self.box:SetChecked(self:IsOn()) end
    end
    self:MakeRoom(scroll, available and self.box ~= nil)

    if not (available and self:IsOn()) then
        if self.mine and self.source then Hand(scroll, self.source) end
        self.mine, self.keptKey = nil, nil
        if self.empty then self.empty:Hide() end
        return
    end

    if not self.source then return end

    local built, kept = self:Build(self.source)
    if not built then
        self.shapeUnknown = true
        return
    end
    self.shapeUnknown = nil

    if self.mine and SameKept(kept, self.keptKey) then return end

    self.mine, self.keptKey = built, kept
    Hand(scroll, built)
    if self.empty then self.empty:SetShown(#kept == 0) end
end

function UpgradesOnly:IsWindowOpen()
    local list = self.list
    return list ~= nil and Try(Field(list, "IsVisible"), list) == true
end

--- Ask again after upgrade answers may have changed (new gear, a level).
function UpgradesOnly:Refilter()
    if not (self.scroll and self:IsOn() and self:IsWindowOpen()) then return end
    self:Apply()
end

--- Refilter once a burst settles.
function UpgradesOnly:RefilterSoon()
    if self.pending or not (self.scroll and self:IsOn() and self:IsWindowOpen()) then return end
    if type(C_Timer) ~= "table" or type(C_Timer.After) ~= "function" then
        self:Refilter()
        return
    end
    self.pending = true
    C_Timer.After(self.ITEM_INFO_WAIT, function()
        UpgradesOnly.pending = nil
        UpgradesOnly:Refilter()
    end)
end

--- One line for `/bts value`.
function UpgradesOnly:ReportText()
    if not self:Available() then return "hidden, Equipment is not loaded" end
    if not self.path then return "no recipe list found" end
    if self.shapeUnknown then return self.path .. ", list shape not known" end
    if not self:IsOn() then return self.path .. ", off" end
    return ("%s, %d shown"):format(self.path, self.keptKey and #self.keptKey or 0)
end

function UpgradesOnly:OnEnable()
    ns.RegisterEvent(self, "TRADE_SKILL_SHOW", function()
        UpgradesOnly:Attach()
        -- The window loads on first use, so its list may not exist yet.
        if C_Timer and C_Timer.After then
            C_Timer.After(0.5, function() UpgradesOnly:Attach() end)
        end
    end)

    ns.RegisterEvent(self, "GET_ITEM_INFO_RECEIVED", function()
        UpgradesOnly:RefilterSoon()
    end)
end
