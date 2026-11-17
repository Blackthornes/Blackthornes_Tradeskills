-- Blackthornes Tradeskills -- UI/Wishlist.lua
-- What players see of the recipe wishlist (Logic/Wishlist.lua): the star a
-- recipe row wears, its hover and menu line, and the "On Your Wishlist:"
-- card under a vendor's or trainer's window. Nothing shows while "Recipe
-- Wishlist:" is off. While Butler's Wishlist module is loaded, Butler shows
-- the same recipes as a row of its own, so the card stays hidden.

local _, ns = ...
local L = ns.L or setmetatable({ Format = string.format }, { __index = function(_, key) return key end })

local WishlistUI = ns.NewModule("WishlistUI")
local WishlistCard = ns.NewModule("WishlistCard")

local Theme = ns.Theme
local Widgets = ns.Widgets

-- Room a star takes at a row's left edge, and how far the row's icon and
-- name move over for it.
WishlistUI.STAR_SIZE = 12
WishlistUI.STAR_ROOM = 14

local function Wishlist() return ns.Wishlist end

--- Are the stars, boxes, card and tooltip line showing?
function WishlistUI.Shown()
    local wishlist = Wishlist()
    return wishlist ~= nil and wishlist:IsOn()
end

--------------------------------------------------------------------------------
-- The star
--------------------------------------------------------------------------------

--- The hover on a star: what a click does.
function WishlistUI.ShowStarTip(owner, on)
    if not GameTooltip then return end
    GameTooltip:SetOwner(owner, "ANCHOR_TOP")
    if on then
        GameTooltip:SetText(L["On Your Wishlist"], 1, 1, 1, 1, true)
        GameTooltip:AddLine(L["Click to take it off."], 0.9, 0.9, 0.9, true)
    else
        GameTooltip:SetText(L["Add to Wishlist"], 1, 1, 1, 1, true)
        GameTooltip:AddLine(L["Click to star this recipe. A vendor or trainer that teaches it will tell you."],
            0.9, 0.9, 0.9, true)
    end
    GameTooltip:Show()
end

--- A star button for a recipe row: gold when starred, a grey one when not,
--- lit under the mouse. `getRecipeID` names the recipe when it is clicked.
function WishlistUI.CreateStar(parent, getRecipeID)
    local size = WishlistUI.STAR_SIZE
    local star = CreateFrame("Button", nil, parent)
    star:SetSize(size + 2, size + 2)

    local file = (Theme.MEDIA or "") .. "SkillUpStar"
    local glow = star:CreateTexture(nil, "BACKGROUND")
    glow:SetPoint("CENTER")
    glow:SetSize(size + 8, size + 8)
    glow:SetTexture(file)
    pcall(glow.SetBlendMode, glow, "ADD")
    glow:SetAlpha(0)

    local art = star:CreateTexture(nil, "ARTWORK")
    art:SetPoint("CENTER")
    art:SetSize(size, size)
    art:SetTexture(file)
    star.art = art

    function star:Paint(hovered)
        local recipeID = getRecipeID()
        local on = recipeID ~= nil and Wishlist() ~= nil and Wishlist():Has(recipeID)
        self.on = on
        pcall(art.SetDesaturated, art, not on)
        if on then
            art:SetVertexColor(1, 1, 1)
            art:SetAlpha(1)
        else
            art:SetVertexColor(0.85, 0.85, 0.85)
            art:SetAlpha(hovered and 0.95 or 0.45)
        end
        glow:SetAlpha(hovered and 0.5 or on and 0.15 or 0)
    end

    star:SetScript("OnClick", function(self)
        local recipeID = getRecipeID()
        if not (recipeID and Wishlist()) then return end
        Wishlist():Toggle(recipeID)
        self:Paint(true)
        WishlistUI.ShowStarTip(self, self.on)
    end)
    star:SetScript("OnEnter", function(self)
        self:Paint(true)
        WishlistUI.ShowStarTip(self, self.on)
    end)
    star:SetScript("OnLeave", function(self)
        self:Paint(false)
        if GameTooltip then GameTooltip:Hide() end
    end)
    return star
end

--- The row menu's wishlist line, or nil while the wishlist is off.
function WishlistUI.MenuLine(recipeID)
    local wishlist = Wishlist()
    if not (recipeID and wishlist and wishlist:IsOn()) then return nil end
    local on = wishlist:Has(recipeID)
    return { text = on and L["Take Off Wishlist"] or L["Add to Wishlist"],
        run = function() wishlist:Set(recipeID, not on) end }
end

--- Starred recipes first, each part in the order it had.
function WishlistUI.StarredFirst(rows)
    local wishlist = Wishlist()
    if not (wishlist and wishlist:IsOn() and type(rows) == "table") then return rows end
    local starred, rest = {}, {}
    for _, row in ipairs(rows) do
        if wishlist:Has(row.recipeID) then starred[#starred + 1] = row else rest[#rest + 1] = row end
    end
    if #starred == 0 then return rows end
    for _, row in ipairs(rest) do starred[#starred + 1] = row end
    return starred
end

--- The "Wishlist First" box's hover.
function WishlistUI.FirstTip(box)
    if not GameTooltip then return end
    GameTooltip:SetOwner(box, "ANCHOR_TOP")
    GameTooltip:SetText(L["Wishlist First"], 1, 1, 1, 1, true)
    GameTooltip:AddLine(L["Puts the recipes you starred at the top."], 0.9, 0.9, 0.9, true)
    GameTooltip:Show()
end

--------------------------------------------------------------------------------
-- The card under a vendor or trainer
--------------------------------------------------------------------------------

WishlistCard.WIDTH = 300
WishlistCard.ROW_HEIGHT = 26
WishlistCard.MOST_ROWS = 6
WishlistCard.PAD = 10

--- Does Butler show these recipes itself? Its window comes up at the
--- vendor, and its Wishlist module reads them through WishlistHere.
function WishlistCard.ButlerShows()
    local ok, yes = pcall(function()
        local butler = _G.BlackthornesButler
        if type(butler) ~= "table" or type(rawget(butler, "Wishlist")) ~= "table" then return false end
        return not (ns.UI and ns.UI.ButlerBuysHere) or ns.UI.ButlerBuysHere() == true
    end)
    return ok and yes == true
end

--- The game window the card sits under, or nil.
function WishlistCard.Anchor(kind)
    local frame = kind == "trainer" and _G.ClassTrainerFrame or _G.MerchantFrame
    if type(frame) ~= "table" then return nil end
    local ok, shown = pcall(frame.IsShown, frame)
    return ok and shown and frame or nil
end

--- A row's words on the right: the price, or "Learn at 145" when the
--- skill is short.
function WishlistCard.RightText(entry)
    if entry.short then return L.Format("Learn at %d", entry.short), "warn" end
    if entry.price and entry.price > 0 then
        return ns.Util and ns.Util.FormatMoney and ns.Util.FormatMoney(entry.price, { short = true })
            or tostring(entry.price), "text"
    end
    return "", "text"
end

--- May a row's button be clicked? A vendor sells it whatever the skill; a
--- trainer only teaches a line it shows as available.
function WishlistCard.CanClick(entry)
    if entry.kind == "trainer" then return entry.index ~= nil and not entry.short end
    return entry.index ~= nil
end

local function RowName(entry)
    if entry.kind == "vendor" and entry.itemID and ns.Util and ns.Util.GetItemLabel then
        local ok, label = pcall(ns.Util.GetItemLabel, entry.itemID)
        if ok and type(label) == "string" and label ~= L.Format("item %d", entry.itemID) then return label end
    end
    return entry.name or ""
end

local function CreateRow(row)
    row.icon = Theme.CreateItemIcon(row, 16)
    row.icon:SetPoint("LEFT", 6, 0)

    row.action = Widgets.CreateButton(row, L["Buy"], function()
        local entry = row.data
        local wishlist = Wishlist()
        if not (entry and wishlist) then return end
        if entry.kind == "trainer" then wishlist:Learn(entry) else wishlist:Buy(entry) end
    end, { width = 56, height = 20, primary = true })
    row.action:SetPoint("RIGHT", row, "RIGHT", -6, 0)

    row.price = Theme.CreateLabel(row, "small", "text", "RIGHT")
    row.price:SetPoint("RIGHT", row.action, "LEFT", -8, 0)
    row.price:SetWordWrap(false)

    row.name = Theme.CreateLabel(row, "small", "text")
    row.name:SetPoint("LEFT", 26, 0)
    row.name:SetPoint("RIGHT", row.price, "LEFT", -8, 0)
    row.name:SetWordWrap(true)
end

local function UpdateRow(row, entry)
    if entry.kind == "vendor" and entry.itemID then
        Theme.SetItemIcon(row.icon, entry.itemID)
    else
        local record = ns.RecipeBook and ns.RecipeBook.Get and ns.RecipeBook:Get(entry.recipeID)
        if record and record.outputItemID then
            Theme.SetItemIcon(row.icon, record.outputItemID)
        else
            Theme.SetSpellIcon(row.icon, entry.recipeID)
        end
    end
    row.name:SetText(RowName(entry))
    if entry.kind == "vendor" and entry.itemID and Theme.SetItemNameColor then
        Theme.SetItemNameColor(row.name, entry.itemID)
    else
        row.name:SetTextColor(Theme.Unpack("text"))
    end
    local text, color = WishlistCard.RightText(entry)
    row.price:SetText(text)
    row.price:SetTextColor(Theme.Unpack(color))
    row.action:SetText(entry.kind == "trainer" and L["Learn"] or L["Buy"])
    if row.action.SetEnabledState then row.action:SetEnabledState(WishlistCard.CanClick(entry)) end
end

function WishlistCard:Build()
    if self.frame then return self.frame end
    local frame = CreateFrame("Frame", "BlackthornesTSWishlistCard", UIParent)
    frame:SetSize(WishlistCard.WIDTH, 80)
    frame:SetFrameStrata("HIGH")
    frame:Hide()
    self.frame = frame

    Theme.Fill(frame, "glass")
    Theme.Border(frame, "accentHi", 0.7)

    local pad = WishlistCard.PAD
    local heading = Theme.CreateLabel(frame, "small", "accent")
    heading:SetPoint("TOPLEFT", pad, -pad)
    heading:SetText(L["On Your Wishlist:"])
    self.heading = heading

    local list = Widgets.CreateScrollList(frame, {
        rowHeight = WishlistCard.ROW_HEIGHT,
        createRow = CreateRow,
        updateRow = UpdateRow,
        onEnter = function(row, entry)
            if entry.kind == "vendor" and entry.index and GameTooltip then
                GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
                if not pcall(GameTooltip.SetMerchantItem, GameTooltip, entry.index) then
                    GameTooltip:SetText(entry.name or "", 1, 1, 1)
                end
                GameTooltip:Show()
            end
        end,
        onLeave = function() if GameTooltip then GameTooltip:Hide() end end,
    })
    list:SetPoint("TOPLEFT", heading, "BOTTOMLEFT", 0, -6)
    list:SetPoint("RIGHT", frame, "RIGHT", -pad, 0)
    self.list = list

    local foot = Theme.CreateLabel(frame, "tiny", "muted")
    foot:SetPoint("TOPLEFT", list, "BOTTOMLEFT", 0, -6)
    foot:SetPoint("RIGHT", frame, "RIGHT", -pad, 0)
    foot:SetWordWrap(true)
    self.foot = foot
    return frame
end

--- What the card shows now: the list and its kind, or nil to hide.
function WishlistCard:Wanted()
    local wishlist = Wishlist()
    if not (wishlist and wishlist:IsOn()) then return nil end
    local here, kind = wishlist:Here()
    if not (here and kind and #here > 0) then return nil end
    if WishlistCard.ButlerShows() then return nil end
    if not WishlistCard.Anchor(kind) then return nil end
    return here, kind
end

--- Show, fill and place the card, or hide it.
function WishlistCard:Update()
    local here, kind = self:Wanted()
    if not here then
        if self.frame then self.frame:Hide() end
        return false
    end
    local frame = self:Build()
    local anchor = WishlistCard.Anchor(kind)
    local ok, width = pcall(anchor.GetWidth, anchor)
    width = (ok and type(width) == "number") and math.max(WishlistCard.WIDTH, width) or WishlistCard.WIDTH
    frame:SetWidth(width)
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -4)

    local shown = math.min(#here, WishlistCard.MOST_ROWS)
    self.list:SetHeight(shown * WishlistCard.ROW_HEIGHT)
    self.list:SetData(here)
    self.foot:SetText(ns.Wishlist.CountText(kind, #here))
    local pad = WishlistCard.PAD
    local height = pad + (self.heading:GetStringHeight() or 14) + 6 + shown * WishlistCard.ROW_HEIGHT
        + 6 + (self.foot:GetStringHeight() or 12) + pad
    frame:SetHeight(height)
    frame:Show()
    return true
end
