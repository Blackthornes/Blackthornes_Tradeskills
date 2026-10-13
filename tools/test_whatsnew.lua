-- UI/WhatsNew.lua outside WoW. The same test is in all five addons.
--
-- What must hold:
--   1. Two addons loaded show one window between them, with both.
--   2. Once shown, a version is never shown again; a newer one is.
--   3. A player who skipped releases sees each (newest first, at most MOST);
--      one who never saw any sees only the newest.
--   4. Off in any of them is off in all, and what is new is still kept as
--      seen, so turning it on again brings up no old news.
--   5. Never in a fight: it waits for the fight to end.
--   6. One timer, no ticker; the newest copy of the file draws the window.
--   7. Motion off lands everything at once, with no tween started.
--   8. Every line of text wraps; nothing is cut to "...".
--   9. The note (UI/About.lua) heads the window once per account, alone
--      when nothing is new, and never again in any sister.

local suite = { checks = 0 }
local function check(label, ok, detail)
    suite.checks = suite.checks + 1
    if not ok then
        error(("whatsnew: %s%s"):format(label, detail and ("  -> " .. tostring(detail)) or ""), 0)
    end
end

local saved = {}
for _, key in ipairs({ "C_Timer", "CreateFrame", "UIParent", "UISpecialFrames", "InCombatLockdown",
    "GetCursorPosition", "BlackthornesWhatsNew", "GameFontNormal", "GameTooltip" }) do
    saved[key] = _G[key]
end

-- A frame, texture or label that remembers what was done to it, and answers
-- any other call as a no-op.
local made
local function Stub(kind)
    local o = { _kind = kind, _shown = kind ~= "Frame" and kind ~= "ScrollFrame" and kind ~= "Button",
        _alpha = 1, _scripts = {}, _events = {} }
    if kind == "Frame" or kind == "Button" then o._shown = true end
    function o:Show() self._shown = true end
    function o:Hide()
        local was = self._shown
        self._shown = false
        if was and self._scripts.OnHide then self._scripts.OnHide(self) end
    end
    function o:IsShown() return self._shown end
    function o:SetShown(v) if v then self:Show() else self:Hide() end end
    function o:SetAlpha(a) self._alpha = a end
    function o:GetAlpha() return self._alpha end
    function o:SetWidth(w) self._width = w end
    function o:GetWidth() return self._width or 0 end
    function o:SetHeight(h) self._height = h end
    function o:GetHeight() return self._height or 0 end
    function o:SetSize(w, h) self._width, self._height = w, h end
    function o:SetScale(s) self._scale = s end
    function o:GetEffectiveScale() return 1 end
    function o:SetText(t) self._text = tostring(t or "") end
    function o:GetText() return self._text end
    function o:GetStringWidth() return #(self._text or "") * 6 end
    function o:SetWordWrap(v) self._wrap = v end
    function o:SetScript(name, fn) self._scripts[name] = fn end
    function o:GetScript(name) return self._scripts[name] end
    function o:HookScript(name, fn) self._scripts[name] = fn end
    function o:RegisterEvent(e) self._events[e] = true end
    function o:UnregisterAllEvents() self._events = {} end
    function o:CreateTexture() local t = Stub("Texture") made[#made + 1] = t return t end
    function o:CreateFontString() local t = Stub("FontString") made[#made + 1] = t return t end
    function o:GetFrameLevel() return 1 end
    return setmetatable(o, { __index = function(self, key)
        local noop = function() end
        rawset(self, key, noop)
        return noop
    end })
end

local timers, tickers, combat, built
local function Client()
    _G.BlackthornesWhatsNew = nil
    _G.BlackthornesWhatsNewFrame = nil
    timers, tickers, combat, made, built = {}, 0, false, {}, 0
    _G.C_Timer = {
        After = function(_, fn) timers[#timers + 1] = fn end,
        NewTicker = function() tickers = tickers + 1 end,
    }
    _G.CreateFrame = function(kind, name)
        local frame = Stub(kind or "Frame")
        if kind == "Frame" or kind == "ScrollFrame" or kind == "Button" then frame._shown = true end
        if name == "BlackthornesWhatsNewFrame" then built = built + 1 end
        if name then _G[name] = frame end
        made[#made + 1] = frame
        return frame
    end
    _G.UIParent = Stub("Frame")
    _G.UIParent._height = 900
    _G.UISpecialFrames = {}
    _G.InCombatLockdown = function() return combat end
    _G.GetCursorPosition = function() return 0, 0 end
end

local runs
--- One addon as the client loads it: the release notes, the file, then the save.
local function Addon(folder, db, news, opts)
    opts = opts or {}
    local ns = { commands = {}, printed = {} }
    function ns.NewModule(name) local m = { moduleName = name } ns[name] = m return m end
    function ns.RegisterCommand(name, _, fn) ns.commands[name] = fn end
    function ns.Print(line) ns.printed[#ns.printed + 1] = line end
    function ns.Debug() end
    ns.Motion = {
        Level = function() return "full" end,
        Run = function(_, _, _, _, apply, o)
            runs = runs + 1
            pcall(apply, 1)
            if o and o.done then o.done() end
        end,
        Stop = function() end,
        FinishAll = function() end,
    }
    ns.Widgets = {
        CreateCheckbox = function(parent, text, onToggle, initial)
            local box = CreateFrame("Button", nil, parent)
            box.label, box.onToggle, box.checked = text, onToggle, initial
            box:SetWidth(#text * 6 + 24)
            function box:SetChecked(v) self.checked = v end
            return box
        end,
        CreateButton = function(parent, text, onClick, o)
            local button = CreateFrame("Button", nil, parent)
            button.label, button.onClick, button.opts = text, onClick, o
            button:SetWidth(o and o.width or 100)
            return button
        end,
    }
    ns.WHATS_NEW = news
    if opts.note then ns.About = { NOTE = { "First paragraph.", "Second paragraph." } } end
    local chunk = assert(loadfile(lfs_cwd .. "/UI/WhatsNew.lua"))
    chunk(folder, ns)
    if opts.fileVersion then ns.WhatsNew.FILE_VERSION = opts.fileVersion end
    ns.db = db
    return ns
end

local function Login(list)
    for _, ns in ipairs(list) do ns.WhatsNew:OnEnable() end
end

local function Fire()
    local run = timers
    timers = {}
    for _, fn in ipairs(run) do fn() end
end

local function Window() return _G.BlackthornesWhatsNewFrame end

local function Shown(ns)
    local owner = ns.WhatsNew.Owner()
    local frame = owner.frame
    return frame and frame:IsShown() and owner.list or nil
end

local FARMER_NEWS = {
    { version = "0.30.0", lines = { "Farmer's newest thing." } },
    { version = "0.29.0", lines = { "Farmer's middle thing." } },
    { version = "0.28.0", lines = { "Farmer's older thing.", "And another." } },
}
local TS_NEWS = {
    { version = "0.52.0", lines = { "Tradeskills' newest thing, long enough that it has to wrap onto a second line in the window." } },
}

--------------------------------------------------------------------------------
-- Two loaded, first time: one window, each with its newest
--------------------------------------------------------------------------------

Client()
runs = 0
local farmerDB, tsDB = {}, {}
local farmer = Addon("Blackthornes_Farmer", farmerDB, FARMER_NEWS)
local ts = Addon("Blackthornes_TS", tsDB, TS_NEWS)
Login({ farmer, ts })

check("one timer for both", #timers == 1, #timers)
check("and no ticker", tickers == 0)
check("the command is there", type(farmer.commands.whatsnew) == "function")
check("nothing shown before it fires", not Window())
Fire()

local list = Shown(farmer)
check("one window", built == 1, built)
check("both in it", list and #list == 2, list and #list)
check("in house order", list[1].addon.folder == "Blackthornes_Farmer" and list[2].addon.folder == "Blackthornes_TS")
check("never seen: the newest only", #list[1].sections == 1 and list[1].sections[1].version == "0.30.0")
check("Farmer's save keeps it as seen", farmerDB.whatsNewSeen == "0.30.0", farmerDB.whatsNewSeen)
check("so does Tradeskills'", tsDB.whatsNewSeen == "0.52.0", tsDB.whatsNewSeen)
check("Escape closes it", _G.UISpecialFrames[1] == "BlackthornesWhatsNewFrame")
check("it moved as it opened", runs > 0, runs)

local wraps, cut = true, nil
for _, region in ipairs(made) do
    if region._kind == "FontString" then
        if rawget(region, "_wrap") ~= true then wraps = false end
        local text = rawget(region, "_text") or ""
        if text:find("...", 1, true) then cut = text end
    end
end
check("every label wraps", wraps)
check("nothing is cut short", not cut, cut)

local owner = farmer.WhatsNew.Owner()
check("the longest line fits its card", owner.cards[2]:GetHeight() > 60, owner.cards[2]:GetHeight())
owner:Close()
check("Got it closes it", not Window():IsShown())

--------------------------------------------------------------------------------
-- The next login: nothing; then an update that skipped two releases
--------------------------------------------------------------------------------

Client()
farmer = Addon("Blackthornes_Farmer", farmerDB, FARMER_NEWS)
ts = Addon("Blackthornes_TS", tsDB, TS_NEWS)
Login({ farmer, ts })
Fire()
check("the next login shows nothing", not Window(), built)

farmerDB.whatsNewSeen = "0.27.0"
local newer = { { version = "0.31.0", lines = { "a" } }, { version = "0.30.0", lines = { "b" } },
    { version = "0.29.0", lines = { "c" } }, { version = "0.28.0", lines = { "d" } } }
Client()
farmer = Addon("Blackthornes_Farmer", farmerDB, newer)
ts = Addon("Blackthornes_TS", tsDB, TS_NEWS)
Login({ farmer, ts })
Fire()
list = Shown(farmer)
check("only the updated addon", list and #list == 1 and list[1].addon.folder == "Blackthornes_Farmer", list and #list)
check("each skipped release, at most three, newest first", #list[1].sections == 3
    and list[1].sections[1].version == "0.31.0" and list[1].sections[3].version == "0.29.0")
check("kept as the newest", farmerDB.whatsNewSeen == "0.31.0", farmerDB.whatsNewSeen)
check("versions compare as numbers", farmer.WhatsNew.Newer("0.10.0", "0.9.9")
    and not farmer.WhatsNew.Newer("0.9.9", "0.10.0") and farmer.WhatsNew.Newer("1.0.0", nil))

--------------------------------------------------------------------------------
-- Turned off in one is off in all, and still kept as seen
--------------------------------------------------------------------------------

Client()
tsDB.whatsNewPopup = false
tsDB.whatsNewSeen = "0.51.0"
farmer = Addon("Blackthornes_Farmer", farmerDB, FARMER_NEWS)
ts = Addon("Blackthornes_TS", tsDB, TS_NEWS)
check("off in Tradeskills is off in Farmer", not farmer.WhatsNew:IsOn())
Login({ farmer, ts })
Fire()
check("so nothing comes up", not Window())
check("but it is kept as seen", tsDB.whatsNewSeen == "0.52.0", tsDB.whatsNewSeen)
farmer.WhatsNew:SetOn(true)
check("on again writes both", farmerDB.whatsNewPopup == true and tsDB.whatsNewPopup == true)

--------------------------------------------------------------------------------
-- The command opens it any time, with each newest
--------------------------------------------------------------------------------

farmer.commands.whatsnew()
list = Shown(farmer)
check("the command opens it", list and #list == 2, list and #list)
farmer.commands.whatsnew()
check("and closes it", not Window():IsShown())

--------------------------------------------------------------------------------
-- Never in a fight
--------------------------------------------------------------------------------

Client()
farmerDB.whatsNewSeen = "0.29.0"
farmer = Addon("Blackthornes_Farmer", farmerDB, FARMER_NEWS)
Login({ farmer })
combat = true
Fire()
check("not in a fight", not Window())
local waiting = _G.BlackthornesWhatsNew.waiting
check("it waits for the fight to end", waiting and waiting._events.PLAYER_REGEN_ENABLED)
check("nothing kept as seen yet", farmerDB.whatsNewSeen == "0.29.0", farmerDB.whatsNewSeen)
combat = false
waiting._scripts.OnEvent(waiting, "PLAYER_REGEN_ENABLED")
check("then it comes up", Shown(farmer) and #Shown(farmer) == 1)

--------------------------------------------------------------------------------
-- The newest file draws it; Motion off moves nothing
--------------------------------------------------------------------------------

Client()
runs = 0
farmerDB.whatsNewSeen, tsDB.whatsNewSeen = nil, nil
farmerDB.whatsNewMotion = false
farmer = Addon("Blackthornes_Farmer", farmerDB, FARMER_NEWS)
ts = Addon("Blackthornes_TS", tsDB, TS_NEWS, { fileVersion = 99 })
check("the newest file draws it", farmer.WhatsNew.Owner() == ts.WhatsNew)
Login({ farmer, ts })
Fire()
check("drawn by that copy", ts.WhatsNew.frame and ts.WhatsNew.frame:IsShown() and not farmer.WhatsNew.frame)
check("Motion off starts no tween", runs == 0, runs)
check("and everything is in place", Window():GetAlpha() == 1, Window():GetAlpha())
check("off in one is off in all", not ts.WhatsNew:IsMotionOn())

-- A save that is not a table, and notes that are not either, never raise.
Client()
farmer = Addon("Blackthornes_Farmer", nil, "nonsense")
Login({ farmer })
Fire()
check("nonsense shows nothing", not Window())

--------------------------------------------------------------------------------
-- The note: once per account, at the top
--------------------------------------------------------------------------------

Client()
farmerDB, tsDB = {}, {}
farmer = Addon("Blackthornes_Farmer", farmerDB, FARMER_NEWS, { note = true })
ts = Addon("Blackthornes_TS", tsDB, TS_NEWS, { note = true })
check("the note is due", farmer.WhatsNew:NoteDue())
Login({ farmer, ts })
Fire()
list = Shown(farmer)
check("the note heads the window", list and list[1].note and #list == 3, list and #list)
check("with its paragraphs", list[1].paragraphs and #list[1].paragraphs == 2)
check("kept as seen in every sister", farmerDB.aboutNoteSeen == true and tsDB.aboutNoteSeen == true)

Client()
farmer = Addon("Blackthornes_Farmer", farmerDB, FARMER_NEWS, { note = true })
ts = Addon("Blackthornes_TS", tsDB, TS_NEWS, { note = true })
Login({ farmer, ts })
Fire()
check("never again", not Window())

-- Nothing new, but the note never shown: it comes up alone.
Client()
local quietDB = { whatsNewSeen = "0.30.0" }
farmer = Addon("Blackthornes_Farmer", quietDB, FARMER_NEWS, { note = true })
Login({ farmer })
Fire()
list = Shown(farmer)
check("the note alone", list and #list == 1 and list[1].note, list and #list)

-- Seen in one sister is seen in all.
Client()
farmer = Addon("Blackthornes_Farmer", { whatsNewSeen = "0.30.0" }, FARMER_NEWS, { note = true })
ts = Addon("Blackthornes_TS", { whatsNewSeen = "0.52.0", aboutNoteSeen = true }, TS_NEWS, { note = true })
Login({ farmer, ts })
Fire()
check("seen in one, seen in all", not Window())

-- With the window turned off the note waits, kept unseen.
Client()
local offDB = { whatsNewSeen = "0.30.0", whatsNewPopup = false }
farmer = Addon("Blackthornes_Farmer", offDB, FARMER_NEWS, { note = true })
Login({ farmer })
Fire()
check("off: no window", not Window())
check("and the note is not kept as seen", offDB.aboutNoteSeen == nil)

for key, value in pairs(saved) do _G[key] = value end
_G.BlackthornesWhatsNewFrame = nil
print(("  whatsnew: %d checks passed"):format(suite.checks))
