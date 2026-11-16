-- A button made by Widgets.CreateButton keeps its words in button.label, a
-- FontString: SetText and the label colour call methods on it. Writing a
-- plain string there broke "Forget character" and "Clear Items" on the
-- Characters tab (attempt to call a nil value in Widgets.lua as the button
-- armed). Keep a button's own words in another field, such as baseText.

local root = lfs_cwd or "."
local function Read(path)
    local f = assert(io.open(root .. "/" .. path, "r"), "can't open " .. path)
    local text = f:read("*a")
    f:close()
    return text
end

-- The files the game loads, from the TOC (UI and Logic only).
local files = {}
for line in Read("Blackthornes_TS.toc"):gmatch("[^\r\n]+") do
    local path = line:gsub("\\", "/"):match("^%s*(.-)%s*$")
    if path:match("^UI/.+%.lua$") or path:match("^Logic/.+%.lua$") then
        files[#files + 1] = path
    end
end
if #files == 0 then files = { "UI/Tab_Characters.lua" } end

local bad = {}
for _, path in ipairs(files) do
    local n = 0
    for line in (Read(path) .. "\n"):gmatch("([^\n]*)\n") do
        n = n + 1
        if line:match("%.label%s*=%s*L[%[%.]") or line:match("%.label%s*=%s*[\"']") then
            bad[#bad + 1] = path .. ":" .. n .. ": " .. line
        end
    end
end
assert(#bad == 0, "a button's label FontString is overwritten with a string:\n" .. table.concat(bad, "\n"))

-- The Characters tab keeps both buttons' words apart and puts them back
-- from there when the two-click arm runs out.
local chars = Read("UI/Tab_Characters.lua")
assert(chars:find('card.forget.baseText = L["Forget character"]', 1, true), "forget keeps its words in baseText")
assert(chars:find('card.clear.baseText = L["Clear Items"]', 1, true), "clear keeps its words in baseText")
assert(chars:find("button:SetText(button.baseText", 1, true), "Disarm restores from baseText")
assert(not chars:find("button:SetText(button.label", 1, true), "Disarm never passes the FontString to SetText")

print("test_buttonlabels: ok (" .. #files .. " files)")
