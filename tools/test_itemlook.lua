-- UI/ItemLook.lua outside WoW (the same file in all five addons): the
-- quality ring follows the icon and takes the quality's colour, plain grey
-- and white are softer, and the stack count shows in the corner only for
-- more than one. Loads the file on its own, with its own small stand-ins.

local failures = 0
local function check(label, ok)
    if ok then
        print("  ok    " .. label)
    else
        failures = failures + 1
        print("  FAIL  " .. label)
    end
end

local function Region()
    local r = { _shown = false }
    function r:Show() self._shown = true end
    function r:Hide() self._shown = false end
    function r:SetShown(v) self._shown = v and true or false end
    function r:IsShown() return self._shown end
    function r:SetPoint(...) self._point = { ... } end
    function r:SetColorTexture(a, b, c, d) self._fill = { a, b, c, d } end
    function r:SetText(t) self._text = t end
    function r:GetText() return self._text end
    function r:SetJustifyH() end
    function r:SetTextColor() end
    function r:SetFont() end
    return r
end

local function Icon()
    local parent = Region()
    function parent:CreateTexture() return Region() end
    function parent:CreateFontString() return Region() end
    local icon = Region()
    function icon:GetParent() return parent end
    function icon:GetDrawLayer() return "ARTWORK", 0 end
    return icon
end

local savedItem = _G.C_Item
local ns = {}
assert(loadfile(lfs_cwd .. "/UI/ItemLook.lua"))("Blackthornes", ns)
local Look = ns.ItemLook
check("the file loads", Look ~= nil)

do
    local icon = Icon()
    Look.Attach(icon)
    local ring = Look.RingOf(icon)
    check("an icon gets a ring", ring ~= nil)
    check("hidden until it has a quality", not ring:IsShown())
    icon:Show()
    Look.SetQuality(icon, 3)
    check("shown for a blue", ring:IsShown() and Look.QualityShown(icon) == 3)
    local r, g, b = Look.Color(3)
    check("in the blue colour", ring._fill[1] == r and ring._fill[2] == g and ring._fill[3] == b)
    check("at full strength", ring._fill[4] == Look.ALPHA)
    icon:Hide()
    check("hidden with the icon", not ring:IsShown())
    icon:SetShown(true)
    check("back with the icon", ring:IsShown())
    Look.SetQuality(icon, 1)
    check("white is softer", ring._fill[4] == Look.PLAIN_ALPHA)
    Look.SetQuality(icon, nil)
    check("nil takes it away", not ring:IsShown())
    check("Attach twice keeps one ring", Look.Attach(icon) and Look.RingOf(icon) == ring)
end

do
    _G.C_Item = { GetItemQualityByID = function(id) return id == 2589 and 1 or nil end }
    check("quality from the client", Look.QualityOf(2589) == 1)
    check("nil while not loaded", Look.QualityOf(9999) == nil)
    local icon = Icon()
    icon:Show()
    check("the caller's quality wins", Look.SetItem(icon, 9999, 4) == 4)
    _G.C_Item = { GetItemQualityByID = function() error("secret") end }
    check("a client that raises is no quality", Look.QualityOf(2589) == nil)
end

do
    local icon = Icon()
    icon:Show()
    Look.SetCount(icon, 1)
    check("one shows no count", Look.CountShown(icon) == nil)
    Look.SetCount(icon, 20)
    local text = Look.CountOf(icon)
    check("20 shows", Look.CountShown(icon) == 20 and text and text:GetText() == "20")
    check("in the corner", text and text._point and text._point[1] == "BOTTOMRIGHT")
    icon:Hide()
    check("hidden with the icon", not text:IsShown())
    icon:Show()
    Look.SetCount(icon, nil)
    check("nil takes it away", not text:IsShown())
end

_G.C_Item = savedItem
print("")
if failures > 0 then error(string.format("%d item look check(s) failed", failures)) end
print("  all item look checks passed")
