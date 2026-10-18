-- Blackthornes Tradeskills -- UI/VendorPins.lua
-- Gold pins on the world map at vendors that sell what the queue needs for
-- less than the auction house (Logic/VendorPins.lua works out which).
--
-- A player asked, the owner said build it (2026-10-18, from a mockup). Only
-- on the world map, for the map it shows. A pin is our own frame on the
-- map's canvas, the house gold: a gold ring with a coin in it and a soft
-- glow. Hovering it names the vendor, what it has for the queue and what
-- buying there saves; a click puts the game's map pin on it, or TomTom's
-- arrow when TomTom is installed. Butler's Buy from a vendor row and the
-- vendor window still do the buying.
--
-- Smooth play: a driver looks four times a second, and only while the map
-- shows does it do more than one check. The pins are laid out again only
-- when the map, its zoom, the queue, the bags, the prices or a learned
-- vendor moved (a key), reusing the same frames. Nothing Blizzard's is
-- hidden, shown or written on: the pins are children of the map's canvas.

local ADDON, ns = ...
local L = ns.L or setmetatable({ Format = string.format }, { __index = function(_, key) return key end })

local Theme = ns.Theme
local Util = ns.Util

local VendorPinsUI = {}
ns.VendorPinsUI = VendorPinsUI

-- How often the driver looks, in seconds.
VendorPinsUI.LOOK = 0.25
-- The pin's size on screen, at any zoom.
VendorPinsUI.SIZE = 24
-- Levels over the map's art and the parts explored.
VendorPinsUI.ABOVE = 5

local ROUND = [[Interface\CharacterFrame\TempPortraitAlphaMask]]
local COIN = [[Interface\Icons\INV_Misc_Coin_02]]
local GLOW = ([[Interface\AddOns\%s\Media\Frame\Glow.tga]]):format(ADDON)

local function Number(value)
    local ok, copy = pcall(function() return tonumber(value) end)
    return ok and copy or nil
end

--- The world map's canvas, the map it shows, and how far it is zoomed.
function VendorPinsUI.WorldView()
    local map = _G.WorldMapFrame
    if type(map) ~= "table" then return nil end
    local okShown, shown = pcall(map.IsShown, map)
    if not (okShown and shown) then return nil end

    local canvas
    if type(map.GetCanvas) == "function" then
        local ok, value = pcall(map.GetCanvas, map)
        if ok then canvas = value end
    end
    canvas = canvas or (map.ScrollContainer and map.ScrollContainer.Child)
    if type(canvas) ~= "table" then return nil end

    local mapID
    if type(map.GetMapID) == "function" then
        local ok, value = pcall(map.GetMapID, map)
        if ok then mapID = Number(value) end
    end
    if not mapID then return nil end

    local scale = 1
    local scroll = map.ScrollContainer
    if type(scroll) == "table" and type(scroll.GetCanvasScale) == "function" then
        local ok, value = pcall(scroll.GetCanvasScale, scroll)
        scale = ok and Number(value) or 1
    end
    if not scale or scale <= 0 then scale = 1 end

    local okW, width = pcall(canvas.GetWidth, canvas)
    local okH, height = pcall(canvas.GetHeight, canvas)
    width = okW and Number(width) or nil
    height = okH and Number(height) or nil
    if not (width and height and width > 0 and height > 0) then return nil end

    return { canvas = canvas, mapID = mapID, scale = scale, width = width, height = height }
end

--- The frame level the pins count up from: the canvas's own, or, on a zone
--- map, the parts you have explored, which the game lays over the map's art
--- as pins of their own (Farmer's MapMarkers.BaseLevel: a glow at the
--- canvas's level was drawn under them).
function VendorPinsUI.BaseLevel(canvas)
    local okLevel, level = pcall(canvas.GetFrameLevel, canvas)
    level = okLevel and Number(level) or 1
    local map = _G.WorldMapFrame
    if type(map) ~= "table" then return level end

    local top
    if type(map.EnumeratePinsByTemplate) == "function" then
        local ok, step, state, key = pcall(map.EnumeratePinsByTemplate, map, "MapExplorationPinTemplate")
        if ok and type(step) == "function" then
            for _ = 1, 64 do
                local okNext, nextKey, value = pcall(step, state, key)
                if not okNext or nextKey == nil then break end
                key = nextKey
                local pin = type(nextKey) == "table" and nextKey or value
                if type(pin) == "table" and type(pin.GetFrameLevel) == "function" then
                    local okPin, pinLevel = pcall(pin.GetFrameLevel, pin)
                    pinLevel = okPin and Number(pinLevel)
                    if pinLevel and (not top or pinLevel > top) then top = pinLevel end
                end
            end
        end
    end
    if not top and type(map.GetPinFrameLevelsManager) == "function" then
        local ok, manager = pcall(map.GetPinFrameLevelsManager, map)
        if ok and type(manager) == "table" and type(manager.GetValidFrameLevel) == "function" then
            local okKept, kept = pcall(manager.GetValidFrameLevel, manager, "PIN_FRAME_LEVEL_MAP_EXPLORATION")
            top = okKept and Number(kept) or nil
        end
    end
    if top and top > level then return top end
    return level
end

--------------------------------------------------------------------------------
-- The pin and its tooltip
--------------------------------------------------------------------------------

--- What the pin's hover says, as lines: { left, right, color }.
function VendorPinsUI.TooltipLines(vendor, hasTomTom)
    local lines = { { vendor.name or "?", nil, "white" } }
    lines[#lines + 1] = { L["Has what your queue needs:"], nil, "gold" }
    for _, item in ipairs(vendor.items or {}) do
        lines[#lines + 1] = { Util.GetItemLabel(item.itemID) .. " x" .. item.count,
            Util.FormatMoney(item.cost), "white" }
    end
    if (vendor.saving or 0) > 0 then
        lines[#lines + 1] = { L.Format("Saves you %s over the auction house.", Util.FormatMoney(vendor.saving)),
            nil, "green" }
    end
    lines[#lines + 1] = { hasTomTom and L["Click for a TomTom arrow."] or L["Click to set a map pin."], nil, "blue" }
    return lines
end

local COLORS = {
    white = { 1, 1, 1 },
    gold = { 1, 0.82, 0 },
    green = { 0.25, 1, 0.25 },
    blue = { 0.28, 0.71, 1 },
}

local function ShowTooltip(pin)
    local vendor = pin.vendor
    local tip = _G.GameTooltip
    if not (vendor and tip) then return end
    local hasTomTom = ns.Waypoints and ns.Waypoints:HasTomTom() or false
    tip:SetOwner(pin, "ANCHOR_RIGHT")
    for index, line in ipairs(VendorPinsUI.TooltipLines(vendor, hasTomTom)) do
        local c = COLORS[line[3]] or COLORS.white
        if line[2] then
            tip:AddDoubleLine(line[1], line[2], c[1], c[2], c[3], 1, 1, 1)
        elseif index == 1 then
            tip:AddLine(line[1], c[1], c[2], c[3])
        else
            tip:AddLine(line[1], c[1], c[2], c[3], true)
        end
    end
    tip:Show()
end

function VendorPinsUI.CreatePin(parent)
    local size = VendorPinsUI.SIZE
    local pin = CreateFrame("Frame", nil, parent)
    pin:SetSize(size, size)
    pin:EnableMouse(true)

    local glow = pin:CreateTexture(nil, "BACKGROUND")
    glow:SetPoint("CENTER")
    glow:SetSize(size * 1.9, size * 1.9)
    glow:SetTexture(GLOW)
    glow:SetVertexColor(Theme.Unpack("accentHi"))
    glow:SetAlpha(0.55)
    pcall(glow.SetBlendMode, glow, "ADD")

    local ring = pin:CreateTexture(nil, "BORDER")
    ring:SetAllPoints(pin)
    ring:SetTexture(ROUND)
    ring:SetVertexColor(Theme.Unpack("accent"))

    local icon = pin:CreateTexture(nil, "ARTWORK")
    local inset = math.max(2, math.floor(size / 7))
    icon:SetPoint("TOPLEFT", inset, -inset)
    icon:SetPoint("BOTTOMRIGHT", -inset, inset)
    icon:SetTexture(COIN)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    pcall(icon.SetMask, icon, ROUND)

    pin.glow, pin.ring, pin.icon = glow, ring, icon

    pin:SetScript("OnEnter", function(self)
        self.ring:SetVertexColor(Theme.Unpack("accentHi"))
        self.glow:SetAlpha(0.9)
        ShowTooltip(self)
    end)
    pin:SetScript("OnLeave", function(self)
        self.ring:SetVertexColor(Theme.Unpack("accent"))
        self.glow:SetAlpha(0.55)
        if _G.GameTooltip then _G.GameTooltip:Hide() end
    end)
    pin:SetScript("OnMouseUp", function(self, button)
        if button ~= "LeftButton" or not self.vendor then return end
        if ns.VendorPins then ns.VendorPins:ShowTheWay(self.vendor) end
    end)
    return pin
end

--------------------------------------------------------------------------------
-- Drawing
--------------------------------------------------------------------------------

VendorPinsUI.pins = {}
VendorPinsUI.used = 0

--- The key that says the pins need laying out again.
function VendorPinsUI.KeyFor(view)
    local vp = ns.VendorPins
    return ("%d:%s:%s:%s:%d:%d:%d:%d"):format(view.mapID, view.scale, view.width, view.height,
        vp and vp.version or 0,
        ns.Queue and ns.Queue.version or 0,
        ns.Inventory and ns.Inventory.changes or 0,
        ns.Prices and ns.Prices.scanCount or 0)
end

local function PutAway(self)
    for index = 1, #self.pins do self.pins[index]:Hide() end
    self.used = 0
end

function VendorPinsUI:Draw()
    local on = ns.VendorPins and ns.VendorPins:IsOn()
    local view = on and VendorPinsUI.WorldView() or nil
    if not view then
        if self.used > 0 then PutAway(self) end
        self.key = nil
        return
    end

    local key = VendorPinsUI.KeyFor(view)
    if key == self.key then return end
    self.key = key

    if self.canvas ~= view.canvas then
        PutAway(self)
        self.pins = {}
        self.canvas = view.canvas
    end

    local vendors = ns.VendorPins:For(view.mapID)
    local level = VendorPinsUI.BaseLevel(view.canvas) + VendorPinsUI.ABOVE
    local scale = 1 / view.scale

    self.used = 0
    for _, vendor in ipairs(vendors) do
        self.used = self.used + 1
        local pin = self.pins[self.used]
        if not pin then
            pin = VendorPinsUI.CreatePin(view.canvas)
            self.pins[self.used] = pin
        end
        pin.vendor = vendor
        pin:SetScale(scale)
        pin:SetFrameLevel(level)
        pin:ClearAllPoints()
        pin:SetPoint("CENTER", view.canvas, "TOPLEFT",
            vendor.x / 100 * view.width / scale, -vendor.y / 100 * view.height / scale)
        pin:Show()
    end
    for index = self.used + 1, #self.pins do self.pins[index]:Hide() end
end

function VendorPinsUI:Start()
    if self.driver then return end
    local driver = CreateFrame("Frame")
    local waited = 0
    driver:SetScript("OnUpdate", function(_, elapsed)
        waited = waited + (elapsed or 0)
        if waited < VendorPinsUI.LOOK then return end
        waited = 0
        local ok, err = pcall(VendorPinsUI.Draw, VendorPinsUI)
        if not ok then
            -- Tried again on the next look, never every frame with an error.
            VendorPinsUI.key = nil
            ns.Debug("vendor pins: " .. tostring(err))
        end
    end)
    self.driver = driver
end

if type(_G.CreateFrame) == "function" and type(_G.C_Timer) == "table" then
    _G.C_Timer.After(0, function() VendorPinsUI:Start() end)
end
