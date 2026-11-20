local ADDON, ns = ...
local T = ns.T

-- Sharing settings: /zod export gives every setting as one line of text to
-- copy, /zod import takes such a line. Only settings travel: which modules
-- are on and how they are set, not gold, notes or anything about a character.
--
-- The text is "ZOD1;" and then scope.key=<kind><value> entries, where kind is
-- b (0 or 1), n (a number) or s (text with ; = : % written as %XX). It is read
-- as data, never run.

local SKIP = { conflict = true, naowh = true, pos = true, minimapAngle = true, seenSetup = true, lastVersion = true }

local function Escape(s)
    return (s:gsub("[%%;=:]", function(c) return string.format("%%%02X", c:byte()) end))
end

local function Unescape(s)
    return (s:gsub("%%(%x%x)", function(hex) return string.char(tonumber(hex, 16)) end))
end

function ns.Export()
    local parts = {}
    local function Add(scope, settings)
        local keys = {}
        for key in pairs(settings) do
            if type(key) == "string" and not SKIP[key] then keys[#keys + 1] = key end
        end
        table.sort(keys)
        for _, key in ipairs(keys) do
            local value, kind = settings[key], type(settings[key])
            local text
            if kind == "boolean" then
                text = "b" .. (value and 1 or 0)
            elseif kind == "number" then
                text = "n" .. tostring(value)
            elseif kind == "string" then
                text = "s" .. Escape(value)
            end
            if text then parts[#parts + 1] = scope .. "." .. key .. "=" .. text end
        end
    end
    Add("general", ns.db.general)
    for _, m in ipairs(ns.order) do Add(m.key, m.db) end
    return "ZOD1;" .. table.concat(parts, ";")
end

-- Returns whether the text was taken and what to say about it.
function ns.Import(text)
    text = (text or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if text:sub(1, 5) ~= "ZOD1;" then return false, "That is not a ZodUI settings text: it starts with ZOD1." end
    local taken, toggles, changed = 0, {}, {}
    for entry in text:sub(6):gmatch("[^;]+") do
        local scope, key, kind, raw = entry:match("^([%w_]+)%.([%w_]+)=(%a)(.*)$")
        local settings = scope == "general" and ns.db.general or (scope and ns.modules[scope] and ns.modules[scope].db)
        local value
        if kind == "b" then
            value = raw == "1"
        elseif kind == "n" then
            value = tonumber(raw)
        elseif kind == "s" then
            value = Unescape(raw)
        end
        -- Only a setting this version knows, with a value of the kind it has now.
        if settings and value ~= nil and not SKIP[key] then
            if key == "enabled" and scope ~= "general" then
                if type(value) == "boolean" then
                    toggles[scope] = value
                    taken = taken + 1
                end
            elseif settings[key] ~= nil and type(settings[key]) == type(value) then
                if settings[key] ~= value then changed[#changed + 1] = { scope, key, value } end
                settings[key] = value
                taken = taken + 1
            end
        end
    end
    if taken == 0 then return false, "Nothing in that text is a setting this version of ZodUI has." end
    for scope, on in pairs(toggles) do
        local m = ns.modules[scope]
        if on then m:Enable() else m:Disable() end
    end
    -- Each changed setting takes effect now, as if it had been changed under Settings.
    local accent = false
    for _, c in ipairs(changed) do
        local m = c[1] ~= "general" and ns.modules[c[1]]
        if m and m.enabled and m.OnOption then ns.Guard(m.key .. " option", m.OnOption, m, c[2], c[3]) end
        if c[1] == "general" and c[2] == "font" then T.ApplyFont() end
        if c[1] == "general" and c[2] == "accent" then accent = true end
    end
    if ns.UpdateMinimap then ns.UpdateMinimap() end
    if ns.ApplyScale then ns.ApplyScale() end
    ns.Refresh()
    return true, taken .. " settings taken over" .. (accent and "; the new accent colour shows after /reload." or ".")
end

local box

local function Build()
    local f = CreateFrame("Frame", "ZodUIShareBox", UIParent, "BackdropTemplate")
    f:SetSize(560, 150)
    f:SetFrameStrata("DIALOG")
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
    T.Window(f, T.WINDOW, 0.98, T.GOLD)
    f:EnableMouse(true)
    f:Hide()
    tinsert(UISpecialFrames, "ZodUIShareBox")
    f.title = T.Text(f, "GameFontNormal", T.GOLD)
    f.title:SetPoint("TOPLEFT", 14, -12)
    f.hint = T.Text(f, "GameFontHighlightSmall", T.DIM)
    f.hint:SetPoint("TOPLEFT", 14, -36)
    f.hint:SetWidth(532)
    f.input = T.Edit(f, 532, 26)
    f.input:SetPoint("TOPLEFT", 14, -62)
    f.said = T.Text(f, "GameFontHighlightSmall")
    f.said:SetPoint("BOTTOMLEFT", 14, 18)
    f.said:SetWidth(276) -- ends before the apply button
    f.close = T.Button(f, "Close", 90, function() f:Hide() end)
    f.close:SetPoint("BOTTOMRIGHT", -14, 12)
    f.apply = T.Button(f, "Take these settings", 150, function()
        f.said:SetText(f.take(f.input.edit:GetText()) or "")
    end)
    f.apply:SetPoint("RIGHT", f.close, "LEFT", -8, 0)
    f.input.edit:SetScript("OnEnterPressed", function(self)
        if f.mode == "import" then f.said:SetText(f.take(self:GetText()) or "") end
    end)
    return f
end

local function TakeSettings(text)
    local _, said = ns.Import(text)
    return said
end

-- mode: "export" shows the text to copy, "import" asks for one. Settings by default; `opts` makes it
-- share something else: { title, hint, text (export), apply (the button's label), take (import: text -> what to say) }.
function ns.ShareBox(mode, opts)
    if not box then box = Build() end
    opts = opts or {}
    box.mode = mode
    box.said:SetText("")
    box.take = opts.take or TakeSettings
    if mode == "export" then
        box.title:SetText(opts.title or "Your ZodUI settings")
        box.hint:SetText(opts.hint or "Press Ctrl+C to copy the text, then paste it where you want to keep or share it.")
        box.input.edit:SetText(opts.text or ns.Export())
        box.apply:Hide()
        box:Show()
        box.input.edit:SetFocus()
        box.input.edit:HighlightText()
    else
        box.title:SetText(opts.title or "Take over ZodUI settings")
        box.hint:SetText(opts.hint or "Paste a settings text here (Ctrl+V). It changes settings only, never gold, notes or characters.")
        box.apply.label:SetText(opts.apply or "Take these settings")
        box.input.edit:SetText("")
        box.apply:Show()
        box:Show()
        box.input.edit:SetFocus()
    end
end
