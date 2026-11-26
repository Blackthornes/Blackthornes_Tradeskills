-- Blackthornes Tradeskills -- UI/ProfitCard.lua
-- How This Profit Adds Up: a side card that lays out one craft's profit
-- (the owner said build it, 2026-11-26, from ts-improve-3). Sells For, the
-- Auction Cut, the Deposit, each material and where it comes from, how many
-- one craft makes, and the Profit, which is the same number the Profit tab,
-- the Queue and the craft pane show (Profit:Counted). A craft whose output
-- comes with random rolls shows its range under the profit.
--
-- The lines come from Profit:Sum, worked out on the click for one craft; no
-- list is built again. Dark glass rows, the house frame, a red close gem.
-- Its spot is kept (`windowSpots["ts.profitcard"]`).

local _, ns = ...
local L = ns.L or setmetatable({ Format = string.format }, { __index = function(_, key) return key end })

local ProfitCard = ns.NewModule("ProfitCard")

local Theme = ns.Theme
local Util = ns.Util

ProfitCard.WIDTH = 320
ProfitCard.INSET = 14
ProfitCard.ROW_PAD = 6

local INSET = ProfitCard.INSET

--- A signed amount as gold, silver and copper: "+83s 29c" or "-17s 39c",
--- the sign green for a gain and red for a loss. `parts` keeps only the
--- biggest coins (Util.FormatMoney).
function ProfitCard.Signed(copper, parts)
    copper = math.floor((copper or 0) + 0.5)
    local colors = ns.COLORS or {}
    local sign = ""
    if copper > 0 then
        sign = colors.profit and ("|c" .. colors.profit .. "+|r") or "+"
    elseif copper < 0 then
        sign = colors.loss and ("|c" .. colors.loss .. "-|r") or "-"
    end
    return sign .. Util.FormatMoney(math.abs(copper), { parts = parts })
end

--- The range for a random roll craft: "-20s to +3g".
function ProfitCard.RangeText(low, high, parts)
    return L.Format("%s to %s", ProfitCard.Signed(low, parts), ProfitCard.Signed(high, parts))
end

--- The card's rows for one sum, in order: { label, note, value, kind }.
--- kind is "line", "makes" or "profit". Kept apart from the drawing so a
--- test can read what the card would say.
function ProfitCard.Rows(sum)
    local rows = {}
    if type(sum) ~= "table" then return rows end
    for _, line in ipairs(sum.lines or {}) do
        local value
        if line.sale then
            value = Util.FormatMoney(line.amount)
        else
            value = ProfitCard.Signed(line.amount)
        end
        rows[#rows + 1] = { label = line.label, note = line.note, value = value,
            amount = line.amount, kind = "line", itemID = line.itemID }
    end
    local yieldText = ns.Profit and ns.Profit.YieldText and ns.Profit.YieldText(sum.yield)
        or tostring(sum.yield or 1)
    rows[#rows + 1] = { label = L["Makes"], value = L.Format("%s a craft", yieldText), kind = "makes" }
    local profitRow = { label = L["Profit"],
        note = L["The same number on the Queue, the tooltip and the profession window"],
        value = ProfitCard.Signed(math.floor(sum.profit + 0.5)), amount = sum.profit, kind = "profit" }
    if sum.low and sum.high then
        profitRow.range = ProfitCard.RangeText(math.floor(sum.low + 0.5), math.floor(sum.high + 0.5))
    end
    rows[#rows + 1] = profitRow
    return rows
end

local function NewRow(parent)
    local row = CreateFrame("Frame", nil, parent)
    row.fill = row:CreateTexture(nil, "BACKGROUND")
    row.fill:SetAllPoints(row)
    row.line = row:CreateTexture(nil, "BORDER")
    row.line:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
    row.line:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
    row.line:SetHeight(1)
    row.line:SetColorTexture(Theme.Unpack("border", 0.6))

    row.label = Theme.CreateLabel(row, "small", "text")
    row.label:SetPoint("TOPLEFT", row, "TOPLEFT", 8, -ProfitCard.ROW_PAD)
    row.label:SetJustifyH("LEFT")
    row.label:SetWordWrap(true)

    row.value = Theme.CreateLabel(row, "small", "text", "RIGHT")
    row.value:SetPoint("TOPRIGHT", row, "TOPRIGHT", -8, -ProfitCard.ROW_PAD)

    row.range = Theme.CreateLabel(row, "tiny", "muted", "RIGHT")
    row.range:SetPoint("TOPRIGHT", row.value, "BOTTOMRIGHT", 0, -3)

    row.note = Theme.CreateLabel(row, "tiny", "muted")
    row.note:SetPoint("TOPLEFT", row.label, "BOTTOMLEFT", 0, -3)
    row.note:SetJustifyH("LEFT")
    row.note:SetWordWrap(true)
    return row
end

function ProfitCard:Build()
    if self.frame then return self.frame end

    local frame = CreateFrame("Frame", "BlackthornesTSProfitCard", UIParent)
    frame:SetSize(ProfitCard.WIDTH, 300)
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:Hide()

    Theme.Fill(frame, "window")
    if ns.Titanforged then
        ns.Titanforged:Dress(frame, { close = function() ProfitCard:Hide() end })
    else
        Theme.AddGameOutline(frame, { style = "dialog", color = "natural" })
    end
    if Theme.Halo then Theme.Halo(frame, 10, 0.10) end
    if type(UISpecialFrames) == "table" then tinsert(UISpecialFrames, "BlackthornesTSProfitCard") end

    local title = Theme.CreateLabel(frame, "normal", "text")
    title:SetPoint("TOPLEFT", INSET, -20)
    title:SetPoint("RIGHT", frame, "RIGHT", -INSET - 20, 0)
    title:SetJustifyH("LEFT")
    title:SetText(L["How This Profit Adds Up"])
    self.title = title

    local item = Theme.CreateLabel(frame, "normal", "text")
    item:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -10)
    item:SetPoint("RIGHT", frame, "RIGHT", -INSET, 0)
    item:SetJustifyH("LEFT")
    item:SetWordWrap(true)
    self.item = item

    local body = CreateFrame("Frame", nil, frame)
    body:SetPoint("TOPLEFT", item, "BOTTOMLEFT", 0, -8)
    body:SetPoint("RIGHT", frame, "RIGHT", -INSET, 0)
    body:SetHeight(10)
    Theme.Border(body, "border", 0.6)
    self.body = body
    self.rows = {}

    self.frame = frame
    if ns.SharedWindow and ns.SharedWindow.KeepSpot then ns.SharedWindow.KeepSpot(frame, "ts.profitcard") end
    return frame
end

local function Height(label)
    local ok, height = pcall(label.GetStringHeight, label)
    return ok and type(height) == "number" and height or 12
end

--- Fill the card from one sum and size it to its rows.
function ProfitCard:Fill(sum)
    self:Build()
    local name = sum.itemID and Util.GetItemLabel and Util.GetItemLabel(sum.itemID) or sum.name or ""
    self.item:SetText(name)
    if sum.itemID and Theme.SetItemNameColor then
        Theme.SetItemNameColor(self.item, sum.itemID, "profit")
    end

    local rows = ProfitCard.Rows(sum)
    local width = ProfitCard.WIDTH - INSET * 2
    local y = 0
    for index, data in ipairs(rows) do
        local row = self.rows[index] or NewRow(self.body)
        self.rows[index] = row
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", self.body, "TOPLEFT", 0, -y)
        row:SetWidth(width)

        -- Dark glass, by place; the Profit row is the one lit.
        local key = data.kind == "profit" and "glassActive" or (index % 2 == 1 and "glass" or "glassAlt")
        row.fill:SetColorTexture(Theme.Unpack(key))

        row.label:SetText(data.label)
        row.label:SetTextColor(Theme.Unpack(data.kind == "profit" and "accent" or "text"))
        row.value:SetText(data.value)
        if data.kind == "profit" then
            row.value:SetTextColor(Theme.Unpack((data.amount or 0) >= 0 and "profit" or "loss"))
        elseif data.kind == "line" and (data.amount or 0) < 0 then
            row.value:SetTextColor(Theme.Unpack("loss"))
        else
            row.value:SetTextColor(Theme.Unpack("text"))
        end

        local valueWidth = Theme.TextWidth and Theme.TextWidth(row.value) or 90
        row.label:SetWidth(math.max(80, width - 24 - (valueWidth or 90)))
        row.note:SetWidth(math.max(80, width - 24 - (valueWidth or 90)))
        row.note:SetText(data.note or "")
        row.note:SetShown(data.note ~= nil)
        row.range:SetText(data.range or "")
        row.range:SetShown(data.range ~= nil)

        local left = Height(row.label) + (data.note and (3 + Height(row.note)) or 0)
        local right = Height(row.value) + (data.range and (3 + Height(row.range)) or 0)
        local height = math.ceil(math.max(left, right) + ProfitCard.ROW_PAD * 2)
        row:SetHeight(height)
        row:Show()
        y = y + height
    end
    for index = #rows + 1, #self.rows do self.rows[index]:Hide() end

    self.body:SetHeight(math.max(10, y))
    self.frame:SetHeight(math.ceil(20 + Height(self.title) + 10 + Height(self.item) + 8 + y + INSET))
end

--- Open the card for one craft, beside `anchor` when given.
-- @param analysis  a Profit:Analyse result
-- @return true when it opened
function ProfitCard:Show(analysis, anchor)
    local sum = ns.Profit and ns.Profit.Sum and ns.Profit:Sum(analysis)
    if not sum then return false end
    local frame = self:Build()
    self.recipeID = sum.recipeID
    self:Fill(sum)

    -- Beside what was clicked; once dragged, its kept spot wins on show.
    frame:ClearAllPoints()
    if anchor and anchor.GetRight then
        frame:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 8, 0)
    else
        frame:SetPoint("CENTER")
    end
    frame:Show()
    if ns.Titanforged and ns.Titanforged.Opened then pcall(ns.Titanforged.Opened, ns.Titanforged, frame) end
    return true
end

--- Open the card for a recipe, counted as the Profit tab counts it.
function ProfitCard:ShowRecipe(recipeID, anchor, method)
    if not (recipeID and ns.Profit) then return false end
    local analysis
    if method ~= nil then
        analysis = ns.Profit:Analyse(recipeID, nil, method)
    elseif ns.Profit.Counted then
        analysis = ns.Profit:Counted(recipeID)
    else
        analysis = ns.Profit:Analyse(recipeID)
    end
    return self:Show(analysis, anchor)
end

function ProfitCard:Hide()
    if self.frame then self.frame:Hide() end
    self.recipeID = nil
end

function ProfitCard:IsShown()
    return self.frame ~= nil and self.frame:IsShown()
end

--- The line a profit's hover adds, so the click can be found.
function ProfitCard.AddHint(tooltip)
    tooltip = tooltip or GameTooltip
    if tooltip and tooltip.AddLine then
        tooltip:AddLine(L["Click to see how it adds up."], 0.5, 0.5, 0.5, true)
    end
end
