local ADDON, ns = ...

-- The look every ZodUI frame shares (the flat dark palette with a gold accent
-- that Undead Route uses) and the widgets the pages are built from.

local T = {}
ns.T = T

T.WHITE = "Interface\\Buttons\\WHITE8x8"
T.TICK = "Interface\\RaidFrame\\ReadyCheck-Ready"
T.LOGO = "Interface\\AddOns\\ZodUI\\Media\\Logo" -- the hammer in a sun, 64x64

T.GOLD = { 1, 0.82, 0 }
T.WINDOW = { 0.06, 0.06, 0.08 }
T.PANEL = { 0.10, 0.10, 0.12 }
T.SURFACE = { 0.14, 0.14, 0.17 }
T.HOVER = { 0.20, 0.20, 0.24 }
T.BORDER = { 0.25, 0.25, 0.25 }
T.TEXT = { 0.92, 0.92, 0.92 }
T.DIM = { 0.6, 0.6, 0.6 }
T.MUTED = { 0.55, 0.55, 0.55 }
T.GREEN = { 0.35, 0.85, 0.45 }
T.RED = { 0.95, 0.40, 0.35 }
T.BLUE = { 0.40, 0.73, 1 }

-- The accent every frame uses. T.GOLD is changed in place at login, before
-- any frame is built, so a new accent shows after /reload.
T.ACCENTS = {
    { "gold", "Gold", { 1, 0.82, 0 } },
    { "class", "Your class colour" },
    { "ice", "Ice blue", { 0.40, 0.78, 1 } },
    { "fel", "Fel green", { 0.45, 0.90, 0.35 } },
    { "rose", "Rose", { 1, 0.45, 0.60 } },
    { "violet", "Violet", { 0.72, 0.52, 1 } },
    { "ember", "Ember", { 1, 0.50, 0.20 } },
}

function T.ApplyAccent(key, classFile)
    local color
    for _, accent in ipairs(T.ACCENTS) do
        if accent[1] == key then color = accent[3] end
    end
    if key == "class" then
        local hex = ns.ClassHex(classFile)
        color = { tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255, tonumber(hex:sub(7, 8), 16) / 255 }
    end
    color = color or T.ACCENTS[1][3]
    T.GOLD[1], T.GOLD[2], T.GOLD[3] = color[1], color[2], color[3]
end

function T.Hex(color)
    return string.format("ff%02x%02x%02x", math.floor(color[1] * 255 + 0.5), math.floor(color[2] * 255 + 0.5),
        math.floor(color[3] * 255 + 0.5))
end

function T.Paint(text, color)
    return "|c" .. T.Hex(color) .. text .. "|r"
end

function T.Flat(frame, color, alpha, border)
    frame:SetBackdrop({ bgFile = T.WHITE, edgeFile = T.WHITE, edgeSize = 1 })
    frame:SetBackdropColor(color[1], color[2], color[3], alpha or 1)
    local b = border or T.BORDER
    frame:SetBackdropBorderColor(b[1], b[2], b[3], 1)
end

-- The look (Settings > General > Look). "game": WoW Forever's own window frame on the big windows and its
-- warm dark colours on everything else; "flat": ZodUI's flat dark grey. Like the accent, the colours are
-- changed in place at login, before any frame is built, so a new look shows after /reload.
T.LOOKS = { { "game", "Forever" }, { "flat", "Modern" } } -- short: the name fits its button
T.look = "flat"
local GAME = {
    WINDOW = { 0.176, 0.13, 0.15 }, PANEL = { 0.12, 0.09, 0.10 }, SURFACE = { 0.21, 0.155, 0.16 },
    HOVER = { 0.30, 0.22, 0.20 }, BORDER = { 0.45, 0.34, 0.18 },
}
function T.ApplyLook(key)
    T.look = (key == "flat") and "flat" or "game"
    if T.look ~= "game" then return end
    for name, c in pairs(GAME) do T[name][1], T[name][2], T[name][3] = c[1], c[2], c[3] end
end

-- The game's yellow, as on its own window lists and headings (GameFontNormal).
T.GAME_YELLOW = { 1, 0.82, 0 }
-- The colour of a page in the list on the left: with the Forever look the game's yellow, the open one white
-- (as the Dungeon Journal's and the game's Options lists); Modern: grey, the open one in the accent.
function T.NavColor(on)
    if T.look == "game" then return on and { 1, 1, 1 } or T.GAME_YELLOW end
    return on and T.GOLD or { 0.8, 0.8, 0.8 }
end
-- A group's heading in that list. With the Forever look the pages are the game's yellow, so the headings take
-- the accent to stand apart from them; with the gold accent, which is that same yellow, a warm tan instead.
T.HEAD_TAN = { 0.80, 0.62, 0.42 }
function T.HeadColor()
    if T.look ~= "game" then return T.MUTED end
    local y, a = T.GAME_YELLOW, T.GOLD
    local same = math.abs(a[1] - y[1]) + math.abs(a[2] - y[2]) + math.abs(a[3] - y[3]) < 0.15
    return same and T.HEAD_TAN or a
end

-- A window's close button: the game's red X with the Forever look, ZodUI's own X with Modern.
function T.Close(parent, onClick)
    if T.look == "game" then
        local ok, b = pcall(CreateFrame, "Button", nil, parent, "UIPanelCloseButton")
        if ok and b then
            b:SetScript("OnClick", function(self, ...) if onClick then return onClick(self, ...) end end)
            b.gameClose = true
            return b
        end
    end
    return T.Button(parent, "X", 24, onClick)
end

-- After a setting that shows only after /reload (the look, the accent colour): ask, so it is not missed.
function T.AskReload(what)
    ns.Print(what .. " shows after /reload.")
    if not (StaticPopupDialogs and StaticPopup_Show) then return false end
    StaticPopupDialogs.ZODUI_RELOAD = StaticPopupDialogs.ZODUI_RELOAD or {
        button1 = "Reload now", button2 = "Later", timeout = 0, whileDead = true, hideOnEscape = true,
        OnAccept = function() if ReloadUI then ReloadUI() end end,
    }
    StaticPopupDialogs.ZODUI_RELOAD.text = "ZodUI: " .. what .. " shows after a reload of the interface. Reload now?"
    StaticPopup_Show("ZODUI_RELOAD")
    return true
end

-- The game's window frame, copied piece by piece onto `frame` (its four corners and four edges, by atlas, size
-- and anchor): nothing is named here but where to borrow it from, so it follows the game when its art changes.
-- Drawn under the frame's own content (a title in the game's title band stays readable), with the window's
-- background under it in turn. Borrowed from the first that has all eight:
--   1. the Options window (SettingsPanel.NineSlice), WoW Forever's own style;
--   2. the game's standard window layout (ButtonFrameTemplateNoPortrait), laid out on a hidden frame of ours,
--      for when the Options window has not been laid out yet or another addon (EllesmereUI's skin) emptied it.
-- False when neither has: the caller keeps the flat edge. T.artWhy says what happened (/zod look).
local PIECES = { "TopLeftCorner", "TopRightCorner", "BottomLeftCorner", "BottomRightCorner",
    "TopEdge", "BottomEdge", "LeftEdge", "RightEdge" }
T.artWhy = "not tried yet"

-- A piece's size: its own, or its atlas's when it has not been laid out (0 x 0).
local function PieceSize(src, atlas)
    local w, h = src:GetWidth() or 0, src:GetHeight() or 0
    if (w <= 0 or h <= 0) and C_Texture and C_Texture.GetAtlasInfo then
        local ok, info = pcall(C_Texture.GetAtlasInfo, atlas)
        if ok and type(info) == "table" then
            if w <= 0 then w = info.width or 0 end
            if h <= 0 then h = info.height or 0 end
        end
    end
    return w, h
end

-- Why `nine` cannot be copied, or nil when it can.
local function Unusable(nine)
    if type(nine) ~= "table" then return "not there" end
    for _, key in ipairs(PIECES) do
        local src = nine[key]
        if type(src) ~= "table" or not src.GetAtlas then return key .. " missing" end
        local atlas = src:GetAtlas()
        if type(atlas) ~= "string" or atlas == "" then return key .. " has no atlas" end
        local w, h = PieceSize(src, atlas)
        if w <= 0 or h <= 0 then return key .. " has no size" end
    end
end

local layoutFrame
local function Sources()
    local list = { { "the Options window", SettingsPanel and SettingsPanel.NineSlice } }
    if not layoutFrame and NineSliceUtil and NineSliceUtil.ApplyLayoutByName and CreateFrame then
        layoutFrame = CreateFrame("Frame", nil, UIParent)
        layoutFrame:SetSize(400, 300)
        layoutFrame:Hide()
        if not pcall(NineSliceUtil.ApplyLayoutByName, layoutFrame, "ButtonFrameTemplateNoPortrait") then layoutFrame.failed = true end
    end
    list[2] = { "the game's window layout", layoutFrame and not layoutFrame.failed and layoutFrame or nil }
    return list
end

function T.GameArt(frame)
    local nine, from
    local why = {}
    for _, source in ipairs(Sources()) do
        local bad = Unusable(source[2])
        if not bad then nine, from = source[2], source[1] break end
        why[#why + 1] = source[1] .. ": " .. bad
    end
    if not nine then
        T.artWhy = "flat edge; " .. table.concat(why, "; ")
        return false
    end
    -- Drawn on the window itself, in its BACKGROUND and BORDER layers: its texts (OVERLAY) and its child frames
    -- (buttons, rows) are always above that. (A frame of its own under the window does not work: the game keeps a
    -- child's level above its parent's, so the frame covered the tracker's first line.)
    local holder = frame
    local art = { bg = frame:CreateTexture(nil, "BACKGROUND", nil, -7) }
    art.bg:SetTexture(T.WHITE)
    art.bg:SetPoint("TOPLEFT", 4, -4)
    art.bg:SetPoint("BOTTOMRIGHT", -4, 4)
    local made, keyOf, pieces = {}, {}, {}
    for _, key in ipairs(PIECES) do
        local src = nine[key]
        local atlas = src:GetAtlas()
        keyOf[src] = key
        local _, sub = src:GetDrawLayer()
        local t = frame:CreateTexture(nil, "BORDER", nil, math.max(-8, math.min(7, tonumber(sub) or 0)))
        t:SetAtlas(atlas, false)
        if src.GetHorizTile and t.SetHorizTile then t:SetHorizTile(src:GetHorizTile()) end
        if src.GetVertTile and t.SetVertTile then t:SetVertTile(src:GetVertTile()) end
        if src.GetVertexColor then
            local r, g, b = src:GetVertexColor()
            t:SetVertexColor(r or 1, g or 1, b or 1, 1) -- the colour, never a fade another addon put on it
        end
        local w, h = PieceSize(src, atlas)
        made[key] = t
        pieces[key] = { t = t, w = w, h = h, points = {} }
    end
    -- The same anchors, to our frame or to our copy of the piece they hang on, kept so the pieces can be made
    -- smaller (T.FitArt). A corner with no anchor of its own goes in its corner.
    for key, piece in pairs(pieces) do
        local src = nine[key]
        for i = 1, (src.GetNumPoints and src:GetNumPoints() or 0) do
            local point, rel, relPoint, x, y = src:GetPoint(i)
            local target = (rel and keyOf[rel] and made[keyOf[rel]]) or holder
            piece.points[#piece.points + 1] = { point, target, relPoint or point, x or 0, y or 0 }
        end
        if #piece.points == 0 and key:find("Corner") then
            local corner = key:gsub("Corner", ""):upper()
            piece.points[1] = { corner, holder, corner, 0, 0 }
        end
    end
    frame.gameArt, frame.gameArtPieces, frame.gameArtFrom = art, pieces, from
    T.artWhy = "the game's frame, from " .. from
    T.FitArt(frame)
    -- A window that grows and shrinks (the route's tracker) keeps its frame fitting.
    if frame.HookScript then frame:HookScript("OnSizeChanged", function(self) T.FitArt(self) end) end
    return true
end

-- The game's corners are as tall as the Options window's title bar: on a window shorter (or narrower) than two
-- of them they would run into each other. Then every piece is drawn smaller, all by the same share, so the
-- frame keeps its shape. Returns that share (1: full size).
function T.FitArt(frame)
    local p = frame.gameArtPieces
    if not p then return end
    local needH = p.TopLeftCorner.h + p.BottomLeftCorner.h
    local needW = p.TopLeftCorner.w + p.TopRightCorner.w
    local h, w = frame:GetHeight() or 0, frame:GetWidth() or 0
    local k = 1
    if h > 0 and needH > 0 then k = math.min(k, h / needH) end
    if w > 0 and needW > 0 then k = math.min(k, w / needW) end
    k = math.max(0.25, k)
    if frame.gameArtShare == k then return k end
    frame.gameArtShare = k
    for _, piece in pairs(p) do
        local t = piece.t
        t:SetSize(piece.w * k, piece.h * k)
        t:ClearAllPoints()
        for _, pt in ipairs(piece.points) do t:SetPoint(pt[1], pt[2], pt[3], pt[4] * k, pt[5] * k) end
    end
    return k
end

-- A big window's background: with the game look, the game's frame and a plain background inside it;
-- else (or when the game's frame cannot be had) the flat one with its 1 px edge.
local flatOnes = setmetatable({}, { __mode = "k" }) -- windows that wanted the game's frame and got the flat edge
local hooked = false

-- The background is drawn by the frame's holder, under the game's frame; the window's own backdrop stays, empty.
local function Framed(frame, color, alpha)
    frame:SetBackdrop({ bgFile = T.WHITE, insets = { left = 4, right = 4, top = 4, bottom = 4 } })
    frame:SetBackdropColor(0, 0, 0, 0)
    frame.gameArt.bg:SetVertexColor(color[1], color[2], color[3], alpha or 1)
end

-- Tries the game's frame again on the windows that fell back to the flat edge. Returns how many got it.
function T.RetryArt()
    local n = 0
    for frame, c in pairs(flatOnes) do
        if T.GameArt(frame) then
            Framed(frame, c[1], c[2])
            flatOnes[frame] = nil
            n = n + 1
        end
    end
    return n
end

function T.Window(frame, color, alpha, border)
    if T.look == "game" and (frame.gameArt or T.GameArt(frame)) then
        Framed(frame, color, alpha)
        return true
    end
    T.Flat(frame, color, alpha, border)
    if T.look == "game" then
        flatOnes[frame] = { color, alpha }
        -- The Options window is laid out when it first opens: try again then.
        if not hooked and SettingsPanel and SettingsPanel.HookScript then
            hooked = true
            SettingsPanel:HookScript("OnShow", function() ns.After(0.2, T.RetryArt) end)
        end
    end
    return false
end

-- /zod look: which look, where the frame came from or why there is none; and one more try.
ns.pluginCommands = ns.pluginCommands or {}
ns.pluginCommands.look = function(arg)
    local want = ({ forever = "game", game = "game", modern = "flat", flat = "flat" })[(arg or ""):lower():match("^%s*(%S*)")]
    if want then
        ns.db.general.look = want
        T.AskReload("The " .. (want == "game" and "Forever" or "Modern") .. " look")
        return
    end
    local n = T.RetryArt()
    ns.Print("look: " .. (T.look == "game" and "Forever" or "Modern") .. " (/zod look forever or modern switches). " .. T.artWhy .. "."
        .. (n > 0 and (" " .. n .. " window" .. (n == 1 and "" or "s") .. " got it now.") or ""))
end

-- Every text is made here, so one setting (Settings > General > Text size) enlarges all of it.
-- Every text made here, with the size its font came with: a new Text size setting re-sizes them all at
-- once (T.ApplyFont), no /reload needed. Weak keys: a text that is gone is not kept alive by this list.
local texts = setmetatable({}, { __mode = "k" })

local function Bump()
    return ns.db and ns.db.general and ns.db.general.font or 1
end

function T.Text(parent, font, color)
    local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
    fs:SetJustifyH("LEFT")
    fs:SetJustifyV("TOP")
    local path, size, flags = fs:GetFont()
    if path and size then
        texts[fs] = size
        if Bump() ~= 0 then fs:SetFont(path, size + Bump(), flags) end
    end
    if color then fs:SetTextColor(color[1], color[2], color[3]) end
    return fs
end

-- How wide a text's words are, whatever width it was given before (a pooled toast, a card cell): a set
-- width would clamp GetStringWidth, so it is let go first.
function T.TextWidth(fs)
    if fs.GetUnboundedStringWidth then return fs:GetUnboundedStringWidth() or 0 end
    fs:SetWidth(0)
    return fs:GetStringWidth() or 0
end

-- The size a text made by T.Text has with the Text size setting, before anything of its own (nil: not ours).
function T.FontSize(fs)
    return texts[fs] and (texts[fs] + Bump()) or nil
end

-- Puts the Text size setting on every text there is, and tells whoever listens (ns.fontListeners).
function T.ApplyFont()
    for fs, base in pairs(texts) do
        local path, _, flags = fs:GetFont()
        if path then fs:SetFont(path, base + Bump(), flags) end
    end
    for _, fn in ipairs(ns.fontListeners or {}) do ns.Guard("text size", fn) end
end

function T.Panel(parent, color, alpha)
    local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    T.Flat(f, color or T.PANEL, alpha)
    return f
end

-- A button's label colour when it is not greyed: the game's yellow on its red buttons, white on ZodUI's own.
function T.ButtonText()
    return T.look == "game" and T.GAME_YELLOW or { 1, 1, 1 }
end

function T.Button(parent, label, width, onClick)
    -- Forever look: the game's own red panel button (it lights up on its own under the mouse); else ZodUI's flat one.
    local game = false
    local b
    if T.look == "game" then
        local ok, made = pcall(CreateFrame, "Button", nil, parent, "UIPanelButtonTemplate")
        if ok and made then b, game = made, true end
    end
    b = b or CreateFrame("Button", nil, parent, "BackdropTemplate")
    b.game = game or nil
    b:SetSize(width, 24)
    if not game then T.Flat(b, T.SURFACE) end
    b.label = T.Text(b, "GameFontHighlightSmall")
    b.label:SetPoint("CENTER")
    b.label:SetText(label)
    local c = T.ButtonText()
    b.label:SetTextColor(c[1], c[2], c[3])
    b:SetScript("OnEnter", function(self)
        if not self.game then
            self:SetBackdropColor(T.HOVER[1], T.HOVER[2], T.HOVER[3], 1)
            self:SetBackdropBorderColor(T.GOLD[1], T.GOLD[2], T.GOLD[3], 1)
        end
        if self.tip then T.ShowTip(self, self.tipTitle, self.tip) end
    end)
    b:SetScript("OnLeave", function(self)
        if not self.game then
            self:SetBackdropColor(T.SURFACE[1], T.SURFACE[2], T.SURFACE[3], 1)
            self:SetBackdropBorderColor(T.BORDER[1], T.BORDER[2], T.BORDER[3], 1)
        end
        if self.tip then T.HideTip() end
        if self.armed then T.Disarm(self) end -- moving away calls the click off
    end)
    -- b.confirm = "Sure?": a button that throws something away asks first. The first click
    -- changes its label to that question; only a second click within a few seconds goes through.
    b:SetScript("OnClick", function(self, ...)
        if self.off then return end -- T.Off: greyed, it says in its tip why
        if self.confirm then
            if not (self.armed and GetTime() - self.armed < 4) then
                self.armed, self.plain = GetTime(), self.label:GetText()
                self.label:SetText(self.confirm)
                self.label:SetTextColor(T.RED[1], T.RED[2], T.RED[3])
                return
            end
            T.Disarm(self)
        end
        if onClick then return onClick(self, ...) end
    end)
    return b
end

-- Puts an item's link in the open chat line. link is a full link or "item:123", whose link the game
-- knows once it has seen the item. Returns true when it was put there.
function T.InsertLink(link)
    if type(link) ~= "string" or not ChatEdit_InsertLink then return false end
    if not link:find("|H", 1, true) then
        local info = (C_Item and C_Item.GetItemInfo) or GetItemInfo
        local _, full = nil, nil
        if info then _, full = info(link) end
        if not full then return false end
        link = full
    end
    return ChatEdit_InsertLink(link) and true or false
end

-- Greys a button out while it has nothing to act on (off = true), with why in its tooltip, or brings it back.
function T.Off(b, off, why)
    b.off = off or nil
    if off then
        b.label:SetTextColor(T.MUTED[1], T.MUTED[2], T.MUTED[3])
        b.tip = why
    elseif not b.armed then
        local c = T.ButtonText()
        b.label:SetTextColor(c[1], c[2], c[3])
        b.tip = nil
    end
end

function T.Disarm(b)
    if not b.armed then return end
    b.armed = nil
    b.label:SetText(b.plain or "")
    local c = T.ButtonText()
    b.label:SetTextColor(c[1], c[2], c[3])
end

function T.ShowTip(owner, title, text)
    if not (GameTooltip and GameTooltip.SetOwner) then return end
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    if title then GameTooltip:AddLine(title, 1, 0.82, 0) end
    if text then GameTooltip:AddLine(text, 0.9, 0.9, 0.9, true) end
    GameTooltip:Show()
end

function T.HideTip()
    if GameTooltip and GameTooltip.Hide then GameTooltip:Hide() end
end

-- A tick box with its label; onChange(checked) runs when the player clicks it.
function T.Check(parent, label, width, onChange)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(width or 300, 20)
    b.box = CreateFrame("Frame", nil, b, "BackdropTemplate")
    b.box:SetSize(14, 14)
    b.box:SetPoint("LEFT", 0, 0)
    T.Flat(b.box, T.SURFACE)
    b.tick = b.box:CreateTexture(nil, "OVERLAY")
    b.tick:SetTexture(T.TICK)
    b.tick:SetAllPoints(b.box)
    b.label = T.Text(b)
    b.label:SetPoint("LEFT", b.box, "RIGHT", 8, 0)
    b.label:SetText(label)
    function b:SetChecked(v)
        self.checked = v and true or false
        self.tick:SetShown(self.checked)
    end
    b:SetChecked(false)
    b:SetScript("OnClick", function(self)
        self:SetChecked(not self.checked)
        if onChange then onChange(self.checked) end
    end)
    b:SetScript("OnEnter", function(self)
        self.box:SetBackdropBorderColor(T.GOLD[1], T.GOLD[2], T.GOLD[3], 1)
        if self.tip then T.ShowTip(self, nil, self.tip) end
    end)
    b:SetScript("OnLeave", function(self)
        self.box:SetBackdropBorderColor(T.BORDER[1], T.BORDER[2], T.BORDER[3], 1)
        if self.tip then T.HideTip() end
    end)
    return b
end

-- Fades `frame` to alpha `to` over `secs`, from wherever it is now, so a fade that turns round midway
-- never jumps. The game runs the animation itself (an AnimationGroup), no Lua each frame. `done` runs when
-- it ends; a fade cut short by a newer one drops its `done` (a fade-out that hides is cancelled by a fade-in).
function T.Fade(frame, to, secs, done)
    if not frame.CreateAnimationGroup then
        frame:SetAlpha(to)
        if done then done() end
        return
    end
    local ag = frame.zodFade
    if not ag then
        ag = frame:CreateAnimationGroup()
        ag.alpha = ag:CreateAnimation("Alpha")
        if ag.alpha.SetSmoothing then ag.alpha:SetSmoothing("OUT") end
        if ag.SetToFinalAlpha then ag:SetToFinalAlpha(true) end
        ag:SetScript("OnFinished", function(self)
            frame:SetAlpha(self.to)
            local fn = self.done
            self.done = nil
            if fn then fn() end
        end)
        frame.zodFade = ag
    end
    local from = frame:GetAlpha() -- read before Stop: mid-fade this is the alpha on screen
    ag.done = nil
    ag:Stop()
    ag.to, ag.done = to, done
    ag.alpha:SetFromAlpha(from)
    ag.alpha:SetToAlpha(to)
    ag.alpha:SetDuration(math.max(0.01, secs))
    ag:Play()
end

-- Shows `frame` fading in to `to` (default 1); a frame already on screen just fades from where it is.
function T.FadeIn(frame, secs, to)
    if not frame:IsShown() then frame:SetAlpha(0) end
    frame:Show()
    T.Fade(frame, to or 1, secs or 0.15)
end

-- Fades `frame` out, then hides it and puts its alpha back to `rest` (default 1) for the next show.
function T.FadeOut(frame, secs, rest)
    if not frame:IsShown() then return end
    T.Fade(frame, 0, secs or 0.12, function()
        frame:Hide()
        frame:SetAlpha(rest or 1)
    end)
end

-- A mouse-wheel scroll area; returns the frame and the child to fill. A thin gold thumb on the right edge
-- shows there is more below and how far down you are; it hides when everything fits.
function T.Scroll(parent)
    local sf = CreateFrame("ScrollFrame", nil, parent)
    local child = CreateFrame("Frame", nil, sf)
    child:SetSize(10, 10)
    sf:SetScrollChild(child)
    sf.thumb = sf:CreateTexture(nil, "OVERLAY")
    sf.thumb:SetTexture(T.WHITE)
    sf.thumb:SetVertexColor(T.GOLD[1], T.GOLD[2], T.GOLD[3], 0.6)
    sf.thumb:SetWidth(3)
    sf.thumb:Hide()
    -- Keeps the scroll inside the content and places the thumb; call after the child's height changes.
    function sf:Sync()
        local view, full = self:GetHeight() or 0, child:GetHeight() or 0
        local range = math.max(0, full - view)
        if self:GetVerticalScroll() > range then self:SetVerticalScroll(range) end
        local show = range > 1 and view > 0
        self.thumb:SetShown(show)
        if show then
            local h = math.max(20, view * view / full)
            self.thumb:SetHeight(h)
            self.thumb:ClearAllPoints()
            self.thumb:SetPoint("TOPRIGHT", self, "TOPRIGHT", 0, -(view - h) * self:GetVerticalScroll() / range)
        end
    end
    sf:EnableMouseWheel(true)
    sf:SetScript("OnMouseWheel", function(self, delta)
        local range = math.max(0, child:GetHeight() - self:GetHeight())
        self:SetVerticalScroll(math.min(range, math.max(0, self:GetVerticalScroll() - delta * 48)))
        self:Sync()
    end)
    sf:SetScript("OnScrollRangeChanged", function(self) self:Sync() end)
    sf:SetScript("OnShow", function(self) self:Sync() end)
    return sf, child
end

-- A one-line text field in a flat box; the EditBox is .edit.
function T.Edit(parent, width, height)
    local holder = T.Panel(parent, T.SURFACE)
    holder:SetSize(width, height or 24)
    -- Forever look: the game's own input box (its rounded left, middle and right pieces) in a clear holder.
    local e
    if T.look == "game" then
        local ok, made = pcall(CreateFrame, "EditBox", nil, holder, "InputBoxTemplate")
        if ok and made then
            e, holder.game = made, true
            holder:SetBackdropColor(0, 0, 0, 0)
            holder:SetBackdropBorderColor(0, 0, 0, 0)
            e:SetPoint("TOPLEFT", 8, -2)
            e:SetPoint("BOTTOMRIGHT", -4, 2)
        end
    end
    if not e then
        e = CreateFrame("EditBox", nil, holder)
        e:SetPoint("TOPLEFT", 6, -4)
        e:SetPoint("BOTTOMRIGHT", -6, 4)
    end
    e:SetAutoFocus(false)
    e:SetFontObject("ChatFontNormal")
    -- A search box (holder.clearOnEscape) empties on the first Escape, and lets go on the next.
    e:SetScript("OnEscapePressed", function(self)
        if holder.clearOnEscape and (self:GetText() or "") ~= "" then
            self:SetText("")
            local changed = self:GetScript("OnTextChanged")
            if changed then changed(self, true) end
        else
            self:ClearFocus()
        end
    end)
    e:SetScript("OnEditFocusGained", function()
        if not holder.game then holder:SetBackdropBorderColor(T.GOLD[1], T.GOLD[2], T.GOLD[3], 1) end
    end)
    e:SetScript("OnEditFocusLost", function()
        if not holder.game then holder:SetBackdropBorderColor(T.BORDER[1], T.BORDER[2], T.BORDER[3], 1) end
    end)
    holder.edit = e
    return holder
end

-- A grey word in an empty box saying what goes there; it goes away as soon as there is text.
function T.Placeholder(holder, text)
    local hint = T.Text(holder, "GameFontHighlightSmall", T.MUTED)
    hint:SetPoint("LEFT", 8, 0)
    hint:SetText(text)
    holder.placeholder = hint
    local function Sync(self) hint:SetShown((self:GetText() or "") == "") end
    holder.edit:HookScript("OnTextChanged", Sync)
    Sync(holder.edit)
end

-- Tab moves on to the next box of a form, Shift-Tab back, round to the first again.
function T.TabOrder(...)
    local boxes = { ... }
    for i, holder in ipairs(boxes) do
        holder.edit:SetScript("OnTabPressed", function()
            local back = IsShiftKeyDown and IsShiftKeyDown()
            boxes[(i - 1 + (back and -1 or 1)) % #boxes + 1].edit:SetFocus()
        end)
    end
end

-- A progress bar; :Set(fraction) fills it, .text is centred on it.
function T.Bar(parent, width, height, color)
    local bar = T.Panel(parent, T.SURFACE)
    bar:SetSize(width, height)
    bar.width = width
    bar.fill = bar:CreateTexture(nil, "ARTWORK")
    bar.fill:SetTexture(T.WHITE)
    bar.fill:SetVertexColor(color[1], color[2], color[3], 0.85)
    bar.fill:SetPoint("TOPLEFT", 1, -1)
    bar.fill:SetHeight(height - 2)
    bar.extra = bar:CreateTexture(nil, "BORDER") -- a second, fainter fill behind the first (rested XP)
    bar.extra:SetTexture(T.WHITE)
    bar.extra:SetVertexColor(T.BLUE[1], T.BLUE[2], T.BLUE[3], 0.45)
    bar.extra:SetPoint("TOPLEFT", 1, -1)
    bar.extra:SetHeight(height - 2)
    bar.extra:Hide()
    bar.text = T.Text(bar, "GameFontHighlightSmall")
    bar.text:SetPoint("CENTER")
    function bar:Set(fraction, extra)
        local inner = self.width - 2
        fraction = math.min(1, math.max(0, fraction or 0))
        self.fill:SetWidth(math.max(1, inner * fraction))
        self.fill:SetShown(fraction > 0)
        if extra and extra > fraction then
            self.extra:SetWidth(math.max(1, inner * math.min(1, extra)))
            self.extra:Show()
        else
            self.extra:Hide()
        end
    end
    bar:Set(0)
    return bar
end

-- A table with a header row and scrolling rows.
--   columns: { { title, width, justify } ... }
--   :SetRows({ { cell, cell, ..., data = any } ... })
--   .onClick(data) makes the rows clickable; .selected (a data value) is highlighted.
function T.Table(parent, columns, width, height, rowHeight, noSort)
    local ROW = rowHeight or 20
    -- The columns must end inside the table, clear of the scroll thumb: 8 px in from the left, 6 px between
    -- cells, 3 px thumb and 2 px air on the right. A page that gave them the table's whole width gets its
    -- last column narrowed, so a right-aligned number does not run under the thumb or past the border.
    local sum = 0
    for _, col in ipairs(columns) do sum = sum + col[2] end
    if sum > width - 9 and #columns > 0 then
        local copy = {}
        for i, col in ipairs(columns) do copy[i] = { col[1], col[2], col[3] } end
        copy[#copy][2] = copy[#copy][2] - (sum - (width - 9))
        columns = copy
    end
    local tbl = T.Panel(parent, T.PANEL)
    tbl:SetSize(width, height)
    tbl.rows = {}
    tbl.columns = columns -- as laid out (the last one maybe narrowed)

    local function Cells(owner, font, color)
        local cells, x = {}, 8
        for i, col in ipairs(columns) do
            local fs = T.Text(owner, font, color)
            fs:SetPoint("LEFT", x, 0)
            fs:SetWidth(col[2] - 6)
            fs:SetHeight(ROW - 4)
            fs:SetJustifyH(col[3] or "LEFT")
            fs:SetJustifyV("MIDDLE")
            fs:SetWordWrap(false)
            cells[i] = fs
            x = x + col[2]
        end
        return cells
    end

    local head = CreateFrame("Frame", nil, tbl)
    head:SetPoint("TOPLEFT", 1, -1)
    head:SetSize(width - 2, ROW + 2)
    local headCells = Cells(head, "GameFontHighlightSmall", T.GOLD)
    -- A click on a heading sorts by that column, a second click the other way, a third goes back to the
    -- page's own order. Numbers, money and percentages sort as numbers, the rest as text.
    -- The chosen column is kept across /reload, by the table's headings (the same list on two pages
    -- sorts the same way).
    local names = {}
    for i, col in ipairs(columns) do names[i] = col[1] end
    local sortKey = table.concat(names, "|")
    local function Sorts()
        local general = ns.db and ns.db.general
        if not general then return nil end
        general.sorts = general.sorts or {}
        return general.sorts
    end
    local saved = not noSort and Sorts() and Sorts()[sortKey]
    if saved and columns[saved[1]] and columns[saved[1]][1] ~= "" then tbl.sortCol, tbl.sortDesc = saved[1], saved[2] or nil end
    local function Heads()
        for i, col in ipairs(columns) do
            local mark = tbl.sortCol == i and (tbl.sortDesc and " v" or " ^") or ""
            headCells[i]:SetText(col[1] .. mark)
        end
    end
    local x = 8
    tbl.headButtons = {}
    for i, col in ipairs(columns) do
        if col[1] ~= "" and not noSort then -- noSort: a list whose order is its meaning (a diary)
            local hb = CreateFrame("Button", nil, head)
            tbl.headButtons[i] = hb
            hb:SetPoint("LEFT", x - 4, 0)
            hb:SetSize(col[2], ROW)
            hb:SetScript("OnClick", function()
                if tbl.sortCol ~= i then
                    tbl.sortCol, tbl.sortDesc = i, false
                elseif not tbl.sortDesc then
                    tbl.sortDesc = true
                else
                    tbl.sortCol, tbl.sortDesc = nil, nil
                end
                local sorts = Sorts()
                if sorts then sorts[sortKey] = tbl.sortCol and { tbl.sortCol, tbl.sortDesc or nil } or nil end
                Heads()
                if tbl.lastRows then tbl:SetRows(tbl.lastRows, tbl.lastEmpty) end
            end)
            hb:SetScript("OnEnter", function(self)
                headCells[i]:SetTextColor(1, 1, 1)
                T.ShowTip(self, nil, "Click to sort by " .. col[1]:lower() .. ".")
            end)
            hb:SetScript("OnLeave", function()
                headCells[i]:SetTextColor(T.GOLD[1], T.GOLD[2], T.GOLD[3])
                T.HideTip()
            end)
        end
        x = x + col[2]
    end
    Heads()
    tbl.heads = headCells
    local rule = tbl:CreateTexture(nil, "ARTWORK")
    rule:SetTexture(T.WHITE)
    rule:SetVertexColor(T.BORDER[1], T.BORDER[2], T.BORDER[3], 1)
    rule:SetPoint("TOPLEFT", 1, -(ROW + 3))
    rule:SetSize(width - 2, 1)

    local scroll, child = T.Scroll(tbl)
    scroll:SetPoint("TOPLEFT", 1, -(ROW + 5))
    scroll:SetSize(width - 2, height - ROW - 7)
    child:SetWidth(width - 2)
    tbl.scroll = scroll

    tbl.empty = T.Text(tbl, "GameFontHighlightSmall", T.MUTED)
    tbl.empty:SetPoint("TOPLEFT", 9, -(ROW + 12))
    tbl.empty:SetWidth(width - 18)
    tbl.empty:Hide()

    local function Row(i)
        local row = CreateFrame("Button", nil, child)
        row:SetSize(width - 2, ROW)
        row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW)
        -- Every other row a shade lighter, so a long list reads along its lines.
        if i % 2 == 0 then
            row.stripe = row:CreateTexture(nil, "BACKGROUND", nil, -1)
            row.stripe:SetAllPoints(row)
            row.stripe:SetTexture(T.WHITE)
            row.stripe:SetVertexColor(1, 1, 1, 0.035)
        end
        row.bg = row:CreateTexture(nil, "BACKGROUND")
        row.bg:SetAllPoints(row)
        row.bg:SetTexture(T.WHITE)
        row.bg:SetVertexColor(T.HOVER[1], T.HOVER[2], T.HOVER[3], 0)
        row.cells = Cells(row, "GameFontHighlightSmall")
        row:SetScript("OnEnter", function(self)
            if tbl.onClick and self.data ~= tbl.selected then self.bg:SetVertexColor(T.HOVER[1], T.HOVER[2], T.HOVER[3], 0.6) end
            -- An item's row (tbl.linkOf(data) gives "item:123" or a link) shows the item's own tooltip.
            local link = tbl.linkOf and self.data and tbl.linkOf(self.data)
            if link and GameTooltip and GameTooltip.SetHyperlink then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                pcall(GameTooltip.SetHyperlink, GameTooltip, link)
                GameTooltip:Show()
                self.tipShown = true
                return
            end
            -- A cell cut short by its column shows in full in a tooltip.
            local cut
            for c, fs in ipairs(self.cells) do
                if fs.IsTruncated and fs:IsTruncated() then
                    cut = cut or {}
                    cut[#cut + 1] = (columns[c][1] ~= "" and (columns[c][1] .. ": ") or "") .. (fs:GetText() or "")
                end
            end
            if cut then
                T.ShowTip(self, nil, table.concat(cut, "\n"))
                self.tipShown = true
            end
        end)
        row:SetScript("OnLeave", function(self)
            if self.data ~= tbl.selected then self.bg:SetVertexColor(T.HOVER[1], T.HOVER[2], T.HOVER[3], 0) end
            if self.tipShown then
                self.tipShown = nil
                T.HideTip()
            end
        end)
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        row:SetScript("OnClick", function(self, mouse)
            -- .onRightClick(data): a right-click acts on the row at once (removes it, on the pages that say so).
            if mouse == "RightButton" then
                if tbl.onRightClick and self.data then tbl.onRightClick(self.data) end
                return
            end
            -- .itemOf(data) names the row's item: Alt-click opens it in Codex Forever when that is installed.
            if tbl.itemOf and self.data and ns.Codex and ns.Codex.Click(tbl.itemOf(self.data)) then return end
            -- Shift-click puts the item's link in the chat line, as in the bags.
            if tbl.linkOf and self.data and IsShiftKeyDown and IsShiftKeyDown() and T.InsertLink(tbl.linkOf(self.data)) then return end
            if tbl.onClick then tbl.onClick(self.data) end
        end)
        return row
    end

    function tbl:SetRows(rows, emptyText)
        self.lastRows, self.lastEmpty = rows, emptyText
        if self.sortCol then rows = T.SortRows(rows, self.sortCol, self.sortDesc) end
        for i, cells in ipairs(rows) do
            local row = self.rows[i] or Row(i)
            self.rows[i] = row
            row.data = cells.data
            for c = 1, #columns do
                local v = cells[c]
                if type(v) == "table" then v = v[1] end -- { text, sort key }, as ns.WhenCell gives
                row.cells[c]:SetText(v ~= nil and tostring(v) or "")
            end
            local on = self.selected ~= nil and cells.data == self.selected
            row.bg:SetVertexColor(T.HOVER[1], T.HOVER[2], T.HOVER[3], on and 1 or 0)
            row:Show()
        end
        for i = #rows + 1, #self.rows do self.rows[i]:Hide() end
        child:SetHeight(math.max(1, #rows * ROW))
        local range = math.max(0, #rows * ROW - scroll:GetHeight())
        if scroll:GetVerticalScroll() > range then scroll:SetVerticalScroll(range) end
        self.empty:SetText(emptyText or "")
        self.empty:SetShown(#rows == 0 and emptyText ~= nil)
    end

    return tbl
end

-- What a cell sorts by: a number when it reads as one (1,234 / 45% / 2g 30s 5c), its plain text otherwise.
local function SortKey(v)
    if type(v) == "table" then return v[2] end -- { text, sort key }
    if type(v) == "number" then return v end
    local text = tostring(v or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", ""):gsub("^%s+", ""):gsub("%s+$", "")
    local n = tonumber((text:gsub(",", ""):gsub("%%$", "")))
    if n then return n end
    local money = text:gsub(",", "")
    if money:find("^%-?%d+[gsc]") then -- ns.Money: "-1,234g 5s 3c"
        local copper = 0
        for amount, unit in money:gmatch("(%d+)([gsc])") do
            copper = copper + tonumber(amount) * (unit == "g" and 10000 or unit == "s" and 100 or 1)
        end
        return money:sub(1, 1) == "-" and -copper or copper
    end
    return text:lower()
end

-- A copy of rows sorted on column c; rows that tie keep their order. Numbers come before text.
function T.SortRows(rows, c, desc)
    local list = {}
    for i, row in ipairs(rows) do list[i] = { row = row, key = SortKey(row[c]), i = i } end
    table.sort(list, function(a, b)
        local ka, kb = a.key, b.key
        if ka == kb then return a.i < b.i end
        if type(ka) ~= type(kb) then return type(ka) == "number" end
        if desc then return ka > kb end
        return ka < kb
    end)
    local out = {}
    for i, e in ipairs(list) do out[i] = e.row end
    return out
end

-- Lets the player drag `frame` and remembers where it was left in `store`.
function T.Movable(frame, store, handle, needShift)
    handle = handle or frame
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    handle:EnableMouse(true)
    handle:RegisterForDrag("LeftButton")
    handle:SetScript("OnDragStart", function()
        if needShift and not (IsShiftKeyDown and IsShiftKeyDown()) then return end
        frame:StartMoving()
    end)
    handle:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        local point, _, rel, x, y = frame:GetPoint(1)
        store.point, store.rel, store.x, store.y = point, rel, x, y
    end)
end

-- Anchors a frame by its top-left corner, right where it is, so a change of size keeps the title bar in
-- place instead of growing out of the middle. Returns the new anchor, to be saved like T.Movable's.
function T.PinTop(frame)
    local left, top = frame:GetLeft(), frame:GetTop()
    if not (left and top) then return end
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
    return "TOPLEFT", "BOTTOMLEFT", left, top
end

-- A grip in the bottom-right corner: drag it to make the window bigger or smaller, a double-click puts it
-- back to its normal size. It changes the window's scale, so every page keeps its layout, and the top-left
-- corner stays where it is. The frame's parent is UIParent.
-- opts = { min, max, size, set = function(scale, point, rel, x, y) end }: set saves the new scale and place;
-- size (default 16) keeps a small grip clear of what sits in the corner.
local GRIP = "Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-"
function T.ScaleGrip(frame, opts)
    local g = CreateFrame("Button", nil, frame)
    local size = opts.size or 16
    g:SetSize(size, size)
    g:SetPoint("BOTTOMRIGHT", -1, 1)
    g:SetFrameLevel(frame:GetFrameLevel() + 10)
    g.tex = g:CreateTexture(nil, "OVERLAY")
    g.tex:SetAllPoints(g)
    g.tex:SetTexture(GRIP .. "Up")
    local function Apply(scale)
        local s, left, top = frame:GetScale(), frame:GetLeft(), frame:GetTop()
        if not (left and top) then return end
        left, top = left * s, top * s -- in UIParent's units, which a new scale does not change
        frame:SetScale(scale)
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left / scale, top / scale)
        opts.set(scale, "TOPLEFT", "BOTTOMLEFT", left / scale, top / scale)
    end
    g.Apply = Apply
    g:SetScript("OnEnter", function(self)
        self.tex:SetTexture(GRIP .. "Highlight")
        T.ShowTip(self, "Size", "Drag to make the window bigger or smaller. A double-click puts it back to normal.")
    end)
    g:SetScript("OnLeave", function(self)
        self.tex:SetTexture(GRIP .. "Up")
        T.HideTip()
    end)
    g:SetScript("OnMouseDown", function(self, mouse)
        if mouse ~= "LeftButton" then return end
        local left = frame:GetLeft()
        if not left then return end
        self.tex:SetTexture(GRIP .. "Down")
        local from, width = left * frame:GetScale(), frame:GetWidth()
        self:SetScript("OnUpdate", function()
            -- The button let go somewhere else: as the window grows the grip moves away from the cursor, and a
            -- release off the grip never reaches its OnMouseUp, so without this it kept sizing for ever.
            if IsMouseButtonDown and not IsMouseButtonDown("LeftButton") then
                self.tex:SetTexture(GRIP .. "Up")
                self:SetScript("OnUpdate", nil)
                return
            end
            local cx = GetCursorPosition() / UIParent:GetEffectiveScale()
            local scale = math.min(opts.max, math.max(opts.min, (cx - from) / width))
            if math.abs(scale - frame:GetScale()) > 0.005 then Apply(scale) end
        end)
    end)
    g:SetScript("OnMouseUp", function(self)
        self.tex:SetTexture(GRIP .. "Up")
        self:SetScript("OnUpdate", nil)
    end)
    g:SetScript("OnDoubleClick", function() Apply(1) end)
    g:SetScript("OnHide", function(self) self:SetScript("OnUpdate", nil) end) -- closed mid-drag: stop
    return g
end

function T.Place(frame, store, point, x, y)
    frame:ClearAllPoints()
    if store and store.point then
        frame:SetPoint(store.point, UIParent, store.rel or store.point, store.x or 0, store.y or 0)
    else
        frame:SetPoint(point, UIParent, point, x or 0, y or 0)
    end
end
