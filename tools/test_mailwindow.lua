-- The Tradeskills mailbox in place of the game's (Ezmode, 2026-10-07).
--
-- Off by default; when on, the game's mailbox is shrunk out of sight but left
-- open, and everything is put back exactly when it ends. The Send page is
-- the game's own, borrowed and returned. Auction mail is taken with a click,
-- letters are read, COD is never taken, and Return needs two clicks.

local saved = { CreateFrame = CreateFrame, GameTooltip = GameTooltip, C_Timer = C_Timer,
    UIParent = UIParent, UISpecialFrames = UISpecialFrames, hooksecurefunc = hooksecurefunc }

local ns = {}
ns.Print, ns.PrintRaw, ns.Debug, ns.Warn =
    function() end, function() end, function() end, function() end
ns.NewModule = function(name) local m = {}; ns[name] = m; return m end
local handlers = {}
ns.RegisterEvent = function(owner, event, fn)
    handlers[event] = handlers[event] or {}
    table.insert(handlers[event], fn)
    return true
end
local function Fire(event, ...)
    for _, fn in ipairs(handlers[event] or {}) do fn(nil, event, ...) end
end

local passed, failed = 0, 0
local function expect(label, got, want)
    if got == want then
        passed = passed + 1
        print(("  ok    %s"):format(label))
    else
        failed = failed + 1
        print(("  FAIL  %s: expected %s, got %s"):format(label, tostring(want), tostring(got)))
    end
end

local function Stub(fields)
    local frame = fields or {}
    return setmetatable(frame, { __index = function(self, key)
        local noop = function() end
        rawset(self, key, noop)
        return noop
    end })
end

local function Frame(name)
    local frame
    frame = Stub({
        name = name, shown = false, scale = 1, alpha = 1, mouse = true, scripts = {}, points = {},
        Show = function(self) self.shown = true; if self.scripts.OnShow then self.scripts.OnShow(self) end end,
        Hide = function(self)
            local was = self.shown
            self.shown = false
            if was and self.scripts.OnHide then self.scripts.OnHide(self) end
        end,
        IsShown = function(self) return self.shown end,
        SetShown = function(self, v) if v then self:Show() else self:Hide() end end,
        SetScript = function(self, what, fn) self.scripts[what] = fn end,
        HookScript = function() end,
        GetScale = function(self) return self.scale end,
        SetScale = function(self, v) self.scale = v end,
        GetAlpha = function(self) return self.alpha end,
        SetAlpha = function(self, v) self.alpha = v end,
        IsMouseEnabled = function(self) return self.mouse end,
        EnableMouse = function(self, v) self.mouse = v end,
        GetParent = function(self) return self.parent end,
        SetParent = function(self, p) self.parent = p end,
        GetNumPoints = function(self) return #self.points end,
        GetPoint = function(self, i) return unpack(self.points[i or 1] or {}) end,
        ClearAllPoints = function(self) self.points = {} end,
        SetPoint = function(self, ...) self.points[#self.points + 1] = { ... } end,
        GetFrameLevel = function() return 1 end,
        GetHeight = function() return 400 end,
        GetWidth = function() return 80 end,
        CreateTexture = function() return Stub() end,
        CreateFontString = function() return Stub() end,
    })
    return frame
end

local function Label()
    return Stub({ text = "", SetText = function(self, v) self.text = tostring(v) end })
end

CreateFrame = function(_, name) return Frame(name) end
UIParent = Frame("UIParent")
UISpecialFrames = {}
local timers = {}
C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end }
local clock = 0
GetTime = function() return clock end
local function Pump()
    for _ = 1, 200 do
        if #timers == 0 then return end
        clock = clock + 1
        local list = timers
        timers = {}
        for _, fn in ipairs(list) do fn() end
    end
end
GameTooltip = Stub()

-- The game's mailbox.
MailFrame = Frame("MailFrame")
MailFrame.scale, MailFrame.alpha, MailFrame.shown = 0.9, 1, true
SendMailFrame = Frame("SendMailFrame")
SendMailFrame.parent = MailFrame
SendMailFrame.points = { { "TOPLEFT", MailFrame, "TOPLEFT", 0, 0 } }
SendMailNameEditBox = Label()
SendMailSubjectEditBox = Label()
MailFrameTab1, MailFrameTab2 = Frame("Tab1"), Frame("Tab2")
local stockTab = 1
local tabHooks = {}
MailFrameTab_OnClick = function(button, tab)
    stockTab = tab
    for _, fn in ipairs(tabHooks) do fn(button, tab) end
end
hooksecurefunc = function(name, fn) if name == "MailFrameTab_OnClick" then tabHooks[#tabHooks + 1] = fn end end
local closedByAddon = 0
HideUIPanel = function(frame)
    if frame == MailFrame then
        closedByAddon = closedByAddon + 1
        MailFrame.shown = false
        Fire("MAIL_CLOSED")
    end
end

ns.Theme = {
    Unpack = function(key) return key end,
    Fill = function() return Stub() end,
    Border = function() end,
    TopSheen = function() end,
    Halo = function() end,
    Recess = function() end,
    CreateLabel = function() return Label() end,
    FitText = function(label, texts) label:SetText(texts[1]); return texts[1] end,
    SetMoneyText = function(label, copper) label:SetText(tostring(copper) .. "c") end,
    TextWidth = function() return 100 end,
}
ns.Widgets = {
    CreateButton = function(_, text, onClick, opts)
        local button = Frame()
        button.label = Label()
        button.label:SetText(text)
        button.onClick = onClick
        button.opts = opts
        button.enabled = true
        button.SetEnabledState = function(self, on) self.enabled = on and true or false end
        button.GetWidth = function() return 80 end
        return button
    end,
    CreateTabStrip = function()
        return Stub({ Select = function(self, key) self.selected = key end })
    end,
}
ns.Util = {
    FormatMoney = function(copper) return tostring(copper) .. "c" end,
    GetItemIcon = function(itemID) return "icon" .. itemID end,
}
local settings = { mailReplace = false }
ns.Config = { Get = function(_, key) return settings[key] end, Set = function(_, key, v) settings[key] = v end }
ns.db = {}

-- The inbox.
AUCTION_SOLD_MAIL_SUBJECT = "Auction successful: %s"
local server = {}
GetInboxNumItems = function() return #server, #server end
GetInboxHeaderInfo = function(index)
    local mail = server[index]
    if not mail then return end
    local n = 0
    for _ in pairs(mail.items) do n = n + 1 end
    return "pkg", nil, mail.sender, mail.subject, mail.money, mail.cod or 0, 10, n
end
GetInboxText = function(index) return server[index] and server[index].body end
local returned = {}
ReturnInboxItem = function(index) returned[#returned + 1] = table.remove(server, index) end
local purse = 0
TakeInboxMoney = function(index)
    purse = purse + server[index].money
    server[index].money = 0
    if next(server[index].items) == nil and not server[index].body then table.remove(server, index) end
end
TakeInboxItem = function(index, slot)
    server[index].items[slot] = nil
    if next(server[index].items) == nil and server[index].money == 0 and not server[index].body then
        table.remove(server, index)
    end
end

ns.Mail = {
    isOpen = true,
    inboxUpdatedThisVisit = true,
    Read = function() end,
    ReadAttachment = function(_, index, slot)
        local item = server[index] and server[index].items[slot]
        if item then return item.itemID, item.count end
    end,
    Classify = function(_, mail)
        local name = type(mail.subject) == "string" and mail.subject:match("^Auction successful: (.+)$")
        if name then return "sold", name end
    end,
}

assert(loadfile(lfs_cwd .. "/Logic/MailTake.lua"))("Blackthornes_TS", ns)
ns.MailTake:OnEnable()
assert(loadfile(lfs_cwd .. "/UI/MailWindow.lua"))("Blackthornes_TS", ns)
local MailWindow = ns.MailWindow

local function Inbox()
    server = {
        { sender = "Bob", subject = "Hello", money = 0, items = {}, body = "Hi there" },
        { sender = "Stranger", subject = "Buy this", money = 0, cod = 500, items = { { itemID = 7, count = 1 } } },
        { sender = "Auction House", subject = "Auction successful: Linen Cloth", money = 300, items = {} },
        { sender = "Ana", subject = "Gift", money = 50, items = { { itemID = 9, count = 2 } }, body = "For you" },
    }
end

--------------------------------------------------------------------------------
print("")
print("Off by default")

Inbox()
Fire("MAIL_SHOW")
Pump()
expect("not standing in", MailWindow:IsReplacing(), false)
expect("the game's mailbox untouched", MailFrame.scale, 0.9)
expect("anchor is the game's", MailWindow:Anchor(), MailFrame)

--------------------------------------------------------------------------------
print("")
print("Standing in")

settings.mailReplace = true
MailWindow:SettingChanged()
expect("standing in", MailWindow:IsReplacing(), true)
expect("the game's mailbox shrunk", MailFrame.scale, 0.001)
expect("and see-through", MailFrame.alpha, 0)
expect("and takes no clicks", MailFrame.mouse, false)
expect("but still open", MailFrame.shown, true)
expect("our window shows", MailWindow.frame.shown, true)
expect("anchor is ours", MailWindow:Anchor(), MailWindow.frame)

local rows = MailWindow.frame.inbox.list.rows
expect("the sale first", rows[1].mail.kind, "sold")
expect("letters after", rows[2].mail.sender, "Bob")
expect("COD last", rows[4].mail.kind, "cod")

--------------------------------------------------------------------------------
print("")
print("Clicking mail")

local function Click(row) row.scripts.OnClick(row) end

Click(rows[1])
Pump()
expect("the sale's gold taken", purse, 300)
expect("its mail gone", #server, 3)

rows = MailWindow.frame.inbox.list.rows
local reader = MailWindow.frame.inbox.reader
Click(rows[1])
expect("a letter opens to read", reader.shown, true)
expect("its words", reader.body.text, "Hi there")
expect("nothing to take from it", reader.take.enabled, false)
reader.back.onClick()
expect("back to the list", reader.shown, false)

-- Ana's gift: gold and items, a letter so it stays.
rows = MailWindow.frame.inbox.list.rows
Click(rows[2])
expect("Ana's letter open", reader.from.text, "From Ana")
reader.take.onClick()
Pump()
expect("her gold", purse, 350)
expect("her items", server[3] and next(server[3].items), nil)
expect("the letter stays", server[3] and server[3].sender, "Ana")

-- COD is never taken here.
MailWindow:CloseReader()
rows = MailWindow.frame.inbox.list.rows
local codRow
for _, row in ipairs(rows) do if type(rawget(row, "mail")) == "table" and row.mail.kind == "cod" then codRow = row end end
Click(codRow)
expect("COD opens the reader", reader.shown, true)
expect("and can't be taken", reader.take.enabled, false)
local none = ns.MailTake:StartOne(codRow.mail.index)
expect("not even asked directly", none, nil)
expect("its item still there", server[2].items[1] ~= nil, true)

-- Return needs a second click.
reader.returnButton.onClick()
expect("one click returns nothing", #returned, 0)
reader.returnButton.onClick()
expect("the second returns it", returned[1] and returned[1].sender, "Stranger")

--------------------------------------------------------------------------------
print("")
print("Send Mail")

MailWindow:SelectTab("send")
expect("the game's Send page is in our window", SendMailFrame.parent, MailWindow.frame.send)
expect("the game's own tab switched", stockTab, 2)
MailWindow:SelectTab("inbox")
expect("given back", SendMailFrame.parent, MailFrame)
expect("where it was", SendMailFrame.points[1][2], MailFrame)

-- The craft queue's Send to buttons switch the game's tab: we follow.
MailFrameTab_OnClick(MailFrameTab2, 2)
expect("followed to Send", MailWindow.tab, "send")
MailWindow:SelectTab("inbox")

--------------------------------------------------------------------------------
print("")
print("Giving it back")

MailWindow.frame.stockButton.onClick()
expect("the game's mailbox back", MailFrame.scale, 0.9)
expect("seen again", MailFrame.alpha, 1)
expect("clickable again", MailFrame.mouse, true)
expect("still open", MailFrame.shown, true)
expect("ours hidden", MailWindow.frame.shown, false)
expect("not closed", closedByAddon, 0)
MailWindow:Begin()
expect("declined for this visit", MailWindow:IsReplacing(), false)

-- Next visit it stands in again; closing ours closes the mailbox.
Fire("MAIL_CLOSED")
MailFrame.shown = true
Fire("MAIL_SHOW")
Pump()
expect("next visit, ours again", MailWindow:IsReplacing(), true)
MailWindow:SelectTab("send")
MailWindow.frame:Hide()
expect("closing ours closes the mailbox", closedByAddon, 1)
expect("the game's put back", MailFrame.scale, 0.9)
expect("the Send page put back", SendMailFrame.parent, MailFrame)
expect("not standing in", MailWindow:IsReplacing(), false)

-- Turning the setting off while open gives the game's window back.
MailFrame.shown = true
Fire("MAIL_SHOW")
Pump()
settings.mailReplace = false
MailWindow:SettingChanged()
expect("setting off: the game's back", MailFrame.scale, 0.9)
expect("and open", MailFrame.shown, true)

for key, value in pairs(saved) do _G[key] = value end

print("")
print(("%d passed, %d failed"):format(passed, failed))
if failed > 0 then error("mail window tests failed") end
