-- The "List It / Skip" window (UI/PostConfirm.lua), Tradeskills' own since
-- 2026-11-19, so the game's pop-up box is never borrowed (see
-- tools/test_gamepopup.lua for why).
--
-- What must hold:
--   1. It shows the words and the item's icon, or the question mark.
--   2. List It runs the listing once, from its own click, and closes.
--   3. Skip, Escape and the close gem each skip once.
--   4. Taken down by the auction house closing, it neither lists nor skips.
--   5. A newer question replaces an open one, which is neither listed nor
--      skipped.
--   6. Escape knows it by name.

local GLOBALS = { "CreateFrame", "UIParent", "GameTooltip", "UISpecialFrames", "tinsert",
    "BlackthornesTSConfirmPost" }
local saved = {}
for _, key in ipairs(GLOBALS) do saved[key] = _G[key] end

local ns = {}
ns.COLORS = setmetatable({}, { __index = function() return "ffffffff" end })
ns.NewModule = function(name) local m = {}; ns[name] = m; return m end
ns.RegisterCommand = function() end
ns.RegisterEvent = function() return true end
ns.Print, ns.PrintRaw, ns.Debug, ns.Warn = function() end, function() end, function() end, function() end

local function Region()
    local region = { shown = false, scripts = {}, alpha = 1, width = 200, height = 0 }
    region.Show = function(self) self.shown = true end
    region.Hide = function(self)
        local was = self.shown
        self.shown = false
        if was and self.scripts.OnHide then self.scripts.OnHide(self) end
    end
    region.IsShown = function(self) return self.shown end
    region.SetShown = function(self, on) self.shown = on and true or false end
    region.SetText = function(self, text) self.text = text end
    region.GetText = function(self) return self.text end
    region.SetTexture = function(self, t) self.texture = t end
    region.SetSize = function(self, w, h) self.width, self.height = w, h end
    region.SetHeight = function(self, h) self.height = h end
    region.GetHeight = function(self) return self.height end
    region.GetStringHeight = function() return 70 end
    region.GetWidth = function(self) return self.width end
    region.SetWidth = function(self, w) self.width = w end
    region.SetScript = function(self, name, fn) self.scripts[name] = fn end
    region.GetScript = function(self, name) return self.scripts[name] end
    region.CreateTexture = function() return Region() end
    region.CreateFontString = function() return Region() end
    region.SetFont = function(self, _, size) self.size = size end
    return setmetatable(region, { __index = function() return function() end end })
end

CreateFrame = function() return Region() end
UIParent = Region()
UISpecialFrames = {}
tinsert = table.insert
GameTooltip = Region()
ns.Config = { Get = function() return nil end }

local function Load(path) assert(loadfile(lfs_cwd .. path))("Blackthornes_TS", ns) end
Load("/Core/Util.lua")
Load("/UI/Theme.lua")
Load("/UI/Widgets.lua")
Load("/UI/Titanforged.lua")
Load("/UI/PostConfirm.lua")
ns.Util.GetItemIcon = function(itemID) if itemID == 2589 then return 132889 end return nil end

local failures = 0
local function check(label, got, expected)
    local ok = got == expected
    if not ok then failures = failures + 1 end
    print(("  %-56s %-12s %s"):format(label, tostring(got), ok and "ok" or
        ("FAILED, expected " .. tostring(expected))))
end

local PostConfirm = ns.PostConfirm
local listed, skipped = {}, {}
local function Ask(itemID, tag)
    return PostConfirm:Show({
        text = "Posting at: 4s\n\nList it at this price, or skip it.",
        itemID = itemID,
        data = { tag = tag },
        accept = function(data) listed[#listed + 1] = data.tag end,
        skip = function(data) skipped[#skipped + 1] = data.tag end,
    })
end
-- The stub answers every missing field with a function, so "disabled" is
-- set plainly here.
local function Click(button)
    button.disabled = false
    button:GetScript("OnClick")(button, "LeftButton")
end

print("\nthe List It window")

local window = Ask(2589, "a")
check("it shows", PostConfirm:IsShown(), true)
check("with the words", window.text.text, "Posting at: 4s\n\nList it at this price, or skip it.")
check("and the item's icon", window.icon.texture, 132889)
check("Escape knows it by name", UISpecialFrames[1], "BlackthornesTSConfirmPost")
check("as a frame it can find", _G.BlackthornesTSConfirmPost, window)

Click(window.listIt)
check("List It lists", listed[1], "a")
check("once", #listed, 1)
check("and closes", PostConfirm:IsShown(), false)
check("without a skip", #skipped, 0)

Ask(9999, "b")
check("an icon not loaded yet is the question mark", window.icon.texture, 134400)
Click(window.skip)
check("Skip skips", skipped[1], "b")
check("and lists nothing", #listed, 1)

Ask(2589, "c")
window:Hide()   -- Escape
check("Escape skips", skipped[2], "c")
check("once", #skipped, 2)

Ask(2589, "d")
PostConfirm:Close()
check("the auction house closing takes it down", PostConfirm:IsShown(), false)
check("with no list", #listed, 1)
check("and no skip", #skipped, 2)

Ask(2589, "e")
Ask(2589, "f")
check("a newer question replaces the open one", #skipped + #listed, 3)
Click(window.listIt)
check("List It lists the newer one", listed[2], "f")
check("only made once", #UISpecialFrames, 1)

for _, key in ipairs(GLOBALS) do _G[key] = saved[key] end

print("")
assert(failures == 0, failures .. " check(s) failed")
