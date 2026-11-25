local ADDON, ns = ...
local T = ns.T
local M = ns.Motion

-- The ZodUI window: page names down the left, the chosen page on the right.
-- A page is { key, title, order, Build(page, frame), Refresh(page, arg) } and is
-- built the first time it is shown. Home and Settings live here; the modules add
-- their own pages with ns.AddPage.
--
-- A module's settings are described, not built by hand. Each entry of
-- module.options is one of:
--   { type = "check",  key, label, tip }
--   { type = "step",   key, label, min, max, step, format = function(value) }
--   { type = "cycle",  key, label, choices = { { value, label } ... } }
--   { type = "button", label, text, click = function(module) }
--   { type = "header", label }
--   { type = "note",   text, lines }

local WIDTH, HEIGHT = 900, 580
local TITLE_H, NAV_W, PAD = 30, 170, 10
local NAV_ROW, NAV_HEAD = 20, 20 -- a page's row in the list on the left, and a group's heading
local PAGE_W, PAGE_H = WIDTH - NAV_W - PAD * 2, HEIGHT - TITLE_H - PAD * 2

ns.pages = {}
ns.PAGE_W, ns.PAGE_H = PAGE_W, PAGE_H
local pageList = {}
local main, current, dirty
local query, back = "", nil -- what the title bar's search box holds, and the page to return to when it is cleared

local NavButton -- below

function ns.AddPage(page)
    ns.pages[page.key] = page
    pageList[#pageList + 1] = page
    page.added = page.added or #pageList
    -- table.sort is not stable: pages with the same order keep the order they were added in (the .toc's)
    table.sort(pageList, function(a, b)
        if a.order ~= b.order then return a.order < b.order end
        return a.added < b.added
    end)
    if main and not page.hidden then -- the window is up already: a plugin's page joins the list
        NavButton(main, page)
        local byPage = {}
        for _, b in ipairs(main.nav) do byPage[b.page] = b end
        local nav = {}
        for _, p in ipairs(pageList) do
            if byPage[p] then nav[#nav + 1] = byPage[p] end
        end
        main.nav = nav
        ns.Refresh()
    end
end

-- Puts the list on the left in place. The page of a module that is off is
-- left out (unless it is the page that is open), and a group with no page
-- left loses its heading.
-- Groups folded away in the list, by name; kept with the window's place.
local function Collapsed()
    ns.db.window.collapsed = ns.db.window.collapsed or {}
    return ns.db.window.collapsed
end

-- A group's heading: a click folds its pages away or brings them back.
local function Heading(f, group)
    local head = f.navHeadOf[group]
    if head then return head end
    head = CreateFrame("Button", nil, f.navFrame)
    head:SetSize(NAV_W - 2, NAV_HEAD)
    head.label = T.Text(head, "GameFontHighlightSmall", T.HeadColor())
    head.label:SetPoint("LEFT", 13, -3)
    head.label:SetText(group:upper())
    head.sign = T.Text(head, "GameFontHighlightSmall", T.HeadColor())
    head.sign:SetPoint("RIGHT", -12, -3)
    head.group = group
    head:SetScript("OnClick", function(self)
        local c = Collapsed()
        c[self.group] = not c[self.group] or nil
        ns.Refresh()
    end)
    head:SetScript("OnEnter", function(self) -- white: the heading may already be in the accent
        self.label:SetTextColor(1, 1, 1)
        self.sign:SetTextColor(1, 1, 1)
    end)
    head:SetScript("OnLeave", function(self)
        local c = T.HeadColor()
        self.label:SetTextColor(c[1], c[2], c[3])
        self.sign:SetTextColor(c[1], c[2], c[3])
    end)
    f.navHeads[#f.navHeads + 1] = head
    f.navHeadOf[group] = head
    return head
end

local function LayoutNav()
    if not main then return end
    local hide, folded = ns.db.general.hideOff, Collapsed()
    for _, head in ipairs(main.navHeads) do head:Hide() end
    local y, group = 8, nil
    for _, b in ipairs(main.nav) do
        local page = b.page
        local m = page.module and ns.modules[page.module]
        if hide and m and not m.enabled and page ~= current then
            b:Hide()
        else
            if page.group and page.group ~= group then
                local head = Heading(main, page.group)
                head.sign:SetText(folded[page.group] and "+" or "-")
                head:ClearAllPoints()
                head:SetPoint("TOPLEFT", 1, -y)
                head:Show()
                y = y + NAV_HEAD
            end
            group = page.group
            if page.group and folded[page.group] and page ~= current then -- the open page stays in sight
                b:Hide()
            else
                b:ClearAllPoints()
                b:SetPoint("TOPLEFT", 1, -y)
                b:Show()
                y = y + NAV_ROW + 1
            end
        end
    end
    -- Taller than the panel: the list scrolls.
    main.navFrame:SetHeight(y + 8)
    if main.navScroll.Sync then main.navScroll:Sync() end
end

-- What the list of pages depends on: the open page, the setting to leave out pages of modules that are off,
-- the folded groups and which modules are on. The list is laid out again only when this changes.
local navParts, navWas = {}, nil
local function NavKey()
    local n = 0
    for i, m in ipairs(ns.order) do
        navParts[i] = m.enabled and "1" or "0"
        n = i
    end
    for i = #navParts, n + 1, -1 do navParts[i] = nil end
    local folded = {}
    for group, on in pairs(Collapsed()) do
        if on then folded[#folded + 1] = group end
    end
    table.sort(folded)
    return (current and current.key or "") .. (ns.db.general.hideOff and "h" or "") .. #main.nav .. table.concat(navParts)
        .. table.concat(folded, ",")
end

-- Folded, the window is its title bar and what wants doing now: the Undead Route's next step and the top
-- Next up hints. A line opens its page with the whole window again.
local FOLD_W, FOLD_ROW, FOLD_ROWS = 360, 18, 5

local function FoldedLines()
    local lines = {}
    local route, status = UndeadRoute, nil
    if type(route) == "table" and route.Status then
        ns.Guard("route card", function() status = route.Status() end)
    end
    if status and status.next then
        lines[1] = { text = "|cff999999Route:|r " .. status.next, open = function() route.Toggle() end }
    end
    for _, hint in ipairs(ns.Hints()) do
        if #lines >= FOLD_ROWS then break end
        lines[#lines + 1] = { text = hint.text, page = hint.page }
    end
    return lines
end

-- Sets a size; on screen the window gets there smoothly (ns.Motion), hidden it is set at once.
local function Resize(frame, w, h)
    if frame:IsShown() then
        M.Size(frame, w, h)
        return
    end
    M.Stop(frame, "size")
    frame.motionW, frame.motionH = nil, nil
    if w then frame:SetWidth(w) end
    if h then frame:SetHeight(h) end
end

local function RefreshFolded()
    local lines, short = FoldedLines(), main.short
    for i, row in ipairs(short.rows) do
        local line = lines[i]
        row:SetShown(line ~= nil)
        if line then
            row.label:SetText(line.text)
            row.line = line
        end
    end
    short.none:SetShown(#lines == 0)
    Resize(main, nil, TITLE_H + 8 + math.max(1, #lines) * FOLD_ROW + 6 + 14 + 8)
end

local function ApplyFold()
    local folded = ns.db.window.folded
    -- An update not looked at yet: the What's new button says so in gold.
    local unseen = ns.db.general.newsUnseen
    main.news.label:SetText(unseen and "What's new *" or "What's new")
    if unseen then main.news.label:SetTextColor(T.GOLD[1], T.GOLD[2], T.GOLD[3]) else local c = T.ButtonText() main.news.label:SetTextColor(c[1], c[2], c[3]) end
    M.Pulse(main.news, unseen and not folded, 0.55, 1, 1.6) -- breathes until it is opened
    main.fold.label:SetText(folded and "+" or "-")
    main.fold.tipTitle = folded and "Unfold" or "Fold"
    main.fold.tip = folded and "Show the whole window again." or "Fold the window to what wants doing now. A double-click on the title bar does the same."
    main.news:SetShown(not folded)
    main.find:SetShown(not folded)
    main.navPanel:SetShown(not folded)
    main.content:SetShown(not folded)
    main.short:SetShown(folded)
    local w = folded and FOLD_W or WIDTH
    Resize(main, w, not folded and HEIGHT or nil)
    Resize(main.bar, w, nil) -- the same length and curve, so the title bar keeps to the window's edge
    if folded then RefreshFolded() end
end

local function RefreshNow(arg)
    dirty = false
    if main and main:IsShown() and ns.db.window.folded then
        RefreshFolded()
        return
    end
    if main and main:IsShown() then
        local key = NavKey()
        if key ~= navWas then
            navWas = key
            LayoutNav()
        end
    end
    if main and main:IsShown() and current and current.Refresh then
        current.perfLabel = current.perfLabel or (current.key .. " page")
        ns.Run(current.perfLabel, current.Refresh, current, arg)
    end
end

function ns.Refresh()
    dirty = true
end

ns.Every(0.2, function()
    if dirty then RefreshNow() end
end)

ns.Every(1, function() -- the pages show clocks and rates, so an open window is redrawn every second
    if main and main:IsShown() then dirty = true end
end)

-- What lifts in when a page opens: Home's cards, else the rows of the page's tables.
local function Pieces(page)
    if page.cards then return page.cards end
    local list = {}
    for _, tbl in ipairs(T.tables) do
        local p = tbl
        while p and p ~= page.frame do p = p:GetParent() end
        if p then
            for _, row in ipairs(tbl.rows) do list[#list + 1] = row end
        end
    end
    return list
end

local function Select(key, arg, opening)
    local page = ns.pages[key] or ns.pages.home
    local same = page == current and not opening -- search results typed on, say
    if current and current.frame then current.frame:Hide() end
    current = page
    if page.key ~= "find" then
        back = page.key
        ns.db.general.lastPage = page.key
    end
    if not page.frame then
        page.frame = CreateFrame("Frame", nil, main.content)
        page.frame:SetAllPoints(main.content)
        ns.Guard(page.key .. " page build", page.Build, page, page.frame)
    end
    page.frame:Show()
    for _, b in ipairs(main.nav) do
        local on = b.page == page
        b.bg:SetVertexColor(T.SURFACE[1], T.SURFACE[2], T.SURFACE[3], on and 1 or 0)
        b.mark:SetShown(on)
        local c = T.NavColor(on)
        b.label:SetTextColor(c[1], c[2], c[3])
    end
    RefreshNow(arg)
    -- Only here, on a change of page: the redraw every second must never lift the rows in again.
    if not same then M.Stagger(Pieces(page), 0.04) end
end

local function Build()
    local f = CreateFrame("Frame", "ZodUIFrame", UIParent, "BackdropTemplate")
    f:SetSize(WIDTH, HEIGHT)
    f:SetFrameStrata("HIGH")
    T.Window(f, T.WINDOW, 0.97)
    f:SetScale((ns.db.general.scale or 100) / 100)
    f:SetAlpha((ns.db.general.alpha or 100) / 100)
    f:EnableMouse(true)
    f:Hide()
    M.WireEscape(f, function() ns.Close() end) -- Escape closes it, with its fade

    local bar = CreateFrame("Frame", nil, f, "BackdropTemplate")
    bar:SetPoint("TOPLEFT", 0, 0)
    bar:SetSize(WIDTH, TITLE_H)
    T.Flat(bar, T.SURFACE)
    if f.gameArt then -- the game's frame has a title band of its own: the title goes on it
        bar:SetBackdropColor(0, 0, 0, 0)
        bar:SetBackdropBorderColor(0, 0, 0, 0)
    end
    T.Movable(f, ns.db.window, bar)
    local logo = bar:CreateTexture(nil, "ARTWORK")
    logo:SetSize(20, 20)
    logo:SetPoint("LEFT", 8, 0)
    logo:SetTexture(T.LOGO)
    local title = T.Text(bar, "GameFontNormal", T.GOLD)
    title:SetPoint("LEFT", logo, "RIGHT", 6, 0)
    title:SetText("ZodUI")
    local version = T.Text(bar, "GameFontHighlightSmall", T.MUTED)
    version:SetPoint("LEFT", title, "RIGHT", 8, 0)
    version:SetText("v" .. ns.version)
    local close = T.Close(bar, function() ns.Close() end)
    close:SetPoint("RIGHT", -3, 0)
    close.tip = "Close (Escape)"
    local fold = T.Button(bar, "-", 24, function() ns.Fold(not ns.db.window.folded) end)
    fold:SetPoint("RIGHT", close, "LEFT", -4, 0)
    fold.tipTitle = "Fold"
    local news = T.Button(bar, "What's new", 96, function() ns.Show("news") end) -- ns.Show clears the mark
    news:SetSize(96, 22)
    news:SetPoint("RIGHT", fold, "LEFT", -4, 0)
    -- A double-click on the title bar folds or unfolds, as in many windows outside the game.
    bar:SetScript("OnMouseUp", function(_, mouse)
        if mouse ~= "LeftButton" then return end
        local now = GetTime()
        if bar.lastClick and now - bar.lastClick < 0.4 then
            bar.lastClick = nil
            ns.Fold(not ns.db.window.folded)
        else
            bar.lastClick = now
        end
    end)
    f.bar, f.fold, f.news = bar, fold, news

    -- Search: looks through pages, settings and what the modules hold. Two letters open the results.
    local find = T.Edit(bar, 190, 22)
    find:SetPoint("RIGHT", news, "LEFT", -6, 0)
    find.edit:SetMaxLetters(40)
    find.clearOnEscape = true
    find.hint = T.Text(find, "GameFontHighlightSmall", T.MUTED)
    find.hint:SetPoint("LEFT", 8, 0)
    find.hint:SetText("Search ZodUI")
    find.edit:SetScript("OnTextChanged", function(self)
        local text = (self:GetText() or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
        find.hint:SetShown(text == "")
        if text == query then return end
        query = text
        if #text >= 2 then
            Select("find")
        elseif current and current.key == "find" then
            Select(back or "home")
        end
    end)
    find.edit:SetScript("OnEnterPressed", function(self) -- Enter opens the chosen result, or the first
        local page = ns.pages.find
        local first = current == page and page.results and (page.results[page.cursor or 1] or page.results[1])
        if first then
            self:ClearFocus()
            if first.codex then ns.Codex.Open(first.codex) else ns.Show(first.key, first.arg) end
        end
    end)
    -- Up and Down choose a result while typing; Enter opens it.
    find.edit:SetScript("OnArrowPressed", function(_, key)
        local page = ns.pages.find
        if current ~= page or not page.results or #page.results == 0 then return end
        if key == "DOWN" then
            page.cursor = math.min(#page.results, (page.cursor or 0) + 1)
        elseif key == "UP" then
            page.cursor = math.max(1, (page.cursor or 1) - 1)
        else
            return
        end
        RefreshNow()
    end)
    f.find = find

    local nav = CreateFrame("Frame", nil, f, "BackdropTemplate")
    nav:SetPoint("TOPLEFT", 0, -TITLE_H + 1)
    nav:SetSize(NAV_W, HEIGHT - TITLE_H + 1)
    T.Flat(nav, T.PANEL)
    f.nav = {}
    local listed = {}
    for _, page in ipairs(pageList) do
        if not page.hidden then listed[#listed + 1] = page end -- a hidden page is opened by a button or a command
    end
    -- A page says which group it belongs to; a small heading goes above the first
    -- page of each, and folds the group away. LayoutNav puts the rows and headings in place,
    -- in a scroll that takes over when the list is taller than the panel.
    local navScroll, navChild = T.Scroll(nav)
    navScroll:SetPoint("TOPLEFT", 0, 0)
    navScroll:SetSize(NAV_W, HEIGHT - TITLE_H + 1 - 40) -- clear of the two-line hint at the bottom
    navChild:SetWidth(NAV_W)
    f.navHeads, f.navHeadOf, f.navFrame, f.navScroll = {}, {}, navChild, navScroll
    for _, page in ipairs(listed) do
        if page.group then Heading(f, page.group) end
        NavButton(f, page)
    end
    local hint = T.Text(nav, "GameFontHighlightSmall", T.MUTED)
    hint:SetPoint("BOTTOMLEFT", 12, 10)
    hint:SetWidth(NAV_W - 24)
    hint:SetText("/zod commands lists every command.")

    f.content = CreateFrame("Frame", nil, f)
    f.content:SetPoint("TOPLEFT", NAV_W + PAD, -(TITLE_H + PAD))
    f.content:SetSize(PAGE_W, PAGE_H)
    f.navPanel = nav

    local short = CreateFrame("Frame", nil, f)
    short:SetPoint("TOPLEFT", PAD, -(TITLE_H + 8))
    short:SetSize(FOLD_W - PAD * 2, FOLD_ROWS * FOLD_ROW)
    short.rows = {}
    for i = 1, FOLD_ROWS do
        local row = CreateFrame("Button", nil, short)
        row:SetSize(FOLD_W - PAD * 2, FOLD_ROW)
        row:SetPoint("TOPLEFT", 0, -(i - 1) * FOLD_ROW)
        row.label = T.Text(row, "GameFontHighlightSmall")
        row.label:SetPoint("LEFT", 0, 0)
        row.label:SetWidth(FOLD_W - PAD * 2)
        row.label:SetWordWrap(false)
        row:SetScript("OnClick", function(self)
            local line = self.line
            if not line then return end
            if line.open then
                ns.Guard("folded line", line.open)
            else
                ns.Fold(false)
                ns.Show(line.page or "home")
            end
        end)
        row:SetScript("OnEnter", function(self) self.label:SetTextColor(T.GOLD[1], T.GOLD[2], T.GOLD[3]) end)
        row:SetScript("OnLeave", function(self) self.label:SetTextColor(1, 1, 1) end)
        short.rows[i] = row
    end
    short.none = T.Text(short, "GameFontHighlightSmall", T.MUTED)
    short.none:SetPoint("TOPLEFT", 0, -3)
    short.none:SetText("Nothing wants doing right now.")
    short.foot = T.Text(short, "GameFontHighlightSmall", T.MUTED)
    short.foot:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", PAD, 8)
    short.foot:SetText("Click a line to open it. + shows the whole window.")
    f.short = short

    -- The corner grip sizes the whole window; the size is the same setting as Settings > General > Window size.
    f.grip = T.ScaleGrip(f, { min = 0.7, max = 1.5, size = 12, set = function(scale, point, rel, x, y)
        ns.db.general.scale = math.floor(scale * 100 + 0.5)
        local store = ns.db.window
        store.point, store.rel, store.x, store.y = point, rel, x, y
    end })

    T.Place(f, ns.db.window, "CENTER", 0, 20)
    return f
end

-- One row of the list on the left.
function NavButton(f, page)
    if page.group then Heading(f, page.group) end
    local b = CreateFrame("Button", nil, f.navFrame)
    b:SetSize(NAV_W - 2, NAV_ROW)
    do
        b.page = page
        b.bg = b:CreateTexture(nil, "BACKGROUND")
        b.bg:SetAllPoints(b)
        b.bg:SetTexture(T.WHITE)
        b.bg:SetVertexColor(T.SURFACE[1], T.SURFACE[2], T.SURFACE[3], 0)
        b.mark = b:CreateTexture(nil, "ARTWORK")
        b.mark:SetTexture(T.WHITE)
        b.mark:SetVertexColor(T.GOLD[1], T.GOLD[2], T.GOLD[3], 1)
        b.mark:SetPoint("TOPLEFT", 0, 0)
        b.mark:SetSize(3, NAV_ROW)
        b.mark:Hide()
        b.label = T.Text(b, "GameFontHighlight")
        b.label:SetPoint("LEFT", 14, 0)
        b.label:SetText(page.title)
        b:SetScript("OnClick", function(self) Select(self.page.key) end)
        b:SetScript("OnEnter", function(self)
            if self.page ~= current then self.bg:SetVertexColor(T.HOVER[1], T.HOVER[2], T.HOVER[3], 0.6) end
        end)
        b:SetScript("OnLeave", function(self)
            if self.page ~= current then self.bg:SetVertexColor(T.SURFACE[1], T.SURFACE[2], T.SURFACE[3], 0) end
        end)
    end
    f.nav[#f.nav + 1] = b
    return b
end

-- Folds the window to its title bar and what wants doing now, or unfolds it. The title bar stays where it is.
function ns.Fold(on)
    ns.db.window.folded = on and true or nil
    if not main then return end
    local store = ns.db.window
    M.Settle(main) -- pinned where it really is, not midway through its rise
    local point, rel, x, y = T.PinTop(main)
    if point then store.point, store.rel, store.x, store.y = point, rel, x, y end
    ApplyFold()
    navWas = nil -- the list was not kept up while folded
    RefreshNow()
end

function ns.Show(key, arg)
    if not ns.ready then return end
    if not main then
        main = Build()
        LayoutNav()
        ApplyFold()
    end
    if key and ns.db.window.folded then ns.Fold(false) end -- asked for a page: show it
    if key == "news" and ns.db.general.newsUnseen then
        ns.db.general.newsUnseen = nil
        ApplyFold()
    end
    local opening = not M.IsOpen(main)
    M.Open(main, (ns.db.general.alpha or 100) / 100)
    local general = ns.db.general
    local last = general.remember and general.lastPage and ns.pages[general.lastPage] and general.lastPage or nil
    Select(key or (current and current.key) or last or "home", arg, opening)
end

-- Closes the window: it fades and sinks a little. A fight starting still closes it at once.
function ns.Close()
    if main then M.Close(main, nil, (ns.db.general.alpha or 100) / 100) end
end

function ns.Toggle()
    if main and M.IsOpen(main) then
        ns.Close()
    else
        ns.Show()
    end
end

-- Opens the window with `text` in the search box; with no text, puts the cursor there.
function ns.Search(text)
    if not ns.ready then return end
    ns.Show()
    if ns.db.window.folded then ns.Fold(false) end
    local edit = main.find.edit
    edit:SetText(text or "")
    edit:GetScript("OnTextChanged")(edit, false) -- the game runs this itself on SetText; a second run changes nothing
    if (text or "") == "" then edit:SetFocus() end
end

function ns.ApplyScale()
    if main then
        main:SetScale((ns.db.general.scale or 100) / 100)
        main:SetAlpha((ns.db.general.alpha or 100) / 100)
    end
end

-- The page whose key or title starts with `part` (three letters or more), for /zod rem.
function ns.PageFor(part)
    part = part:lower()
    for _, page in ipairs(pageList) do
        if page.key ~= "find" and (page.key:sub(1, #part) == part or page.title:lower():sub(1, #part) == part) then return page.key end
    end
end

-- A fight starts: the window gets out of the way.
ns.On("PLAYER_REGEN_DISABLED", function()
    if ns.db and ns.db.general.combatClose and main and main:IsShown() then M.Hide(main, (ns.db.general.alpha or 100) / 100) end
end)

function ns.ResetWindow()
    if main then T.Place(main, ns.db.window, "CENTER", 0, 20) end
end

---------------------------------------------------------------------------
-- Home
---------------------------------------------------------------------------

local CARD_W, CARD_H, CARD_LINES = (PAGE_W - PAD) / 2, 100, 4

local function Card(parent, i)
    local card = T.Panel(parent, T.PANEL)
    card:SetSize(CARD_W, CARD_H)
    card:SetPoint("TOPLEFT", ((i - 1) % 2) * (CARD_W + PAD), -math.floor((i - 1) / 2) * (CARD_H + 8))
    card.title = T.Text(card, "GameFontNormal", T.GOLD)
    card.title:SetPoint("TOPLEFT", 10, -8)
    card.left, card.right = {}, {}
    for n = 1, CARD_LINES do
        local y = -12 - n * 17
        card.left[n] = T.Text(card, "GameFontHighlightSmall", T.DIM)
        card.left[n]:SetPoint("TOPLEFT", 10, y)
        card.left[n]:SetWidth(CARD_W - 20)
        card.left[n]:SetWordWrap(false)
        card.right[n] = T.Text(card, "GameFontHighlightSmall")
        card.right[n]:SetPoint("TOPRIGHT", -10, y)
        card.right[n]:SetJustifyH("RIGHT")
        -- The line itself: a line that names a page opens it, and one cut short shows all of it on hover.
        local hit = CreateFrame("Button", nil, card)
        hit:SetPoint("TOPLEFT", card.left[n], "TOPLEFT", 0, 2)
        hit:SetSize(CARD_W - 20, 16)
        hit:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        hit.n = n
        hit:SetScript("OnClick", function(self, mouse)
            if mouse == "RightButton" then -- as on the card: hide it
                card:GetScript("OnMouseUp")(card, "RightButton")
            elseif self.page then
                ns.Show(self.page)
            end
        end)
        hit:SetScript("OnEnter", function(self)
            local left = card.left[self.n]
            local cut = T.TextWidth(left) > (left:GetWidth() or 0) + 1
            local full = left:GetText() or ""
            left:SetWidth(self.leftW or (CARD_W - 20)) -- TextWidth let the width go: put it back
            if cut or self.page then
                T.ShowTip(self, nil, (cut and full or "") .. (self.page and ((cut and "\n" or "") .. "|cff999999Click to open it.|r") or ""))
            end
        end)
        hit:SetScript("OnLeave", T.HideTip)
        card.hits = card.hits or {}
        card.hits[n] = hit
    end
    card.button = T.Button(card, "", 96, function(self)
        if self.click then ns.Guard("card button", self.click) end
    end)
    card.button:SetSize(96, 20)
    card.button:SetPoint("TOPRIGHT", -6, -5)
    card:EnableMouse(true)
    card:SetScript("OnMouseUp", function(self, mouse) -- right-click hides the card
        if mouse ~= "RightButton" or not self.key then return end
        ns.db.general.hiddenCards = ns.db.general.hiddenCards or {}
        ns.db.general.hiddenCards[self.key] = true
        ns.Print("the " .. self.key .. " card is hidden. Settings > General shows it again.")
        ns.Refresh()
    end)
    return card
end

-- What wants doing now, most pressing first: { text, p = priority, page }.
-- A module adds its own with M:Hints(add), add(text, priority, page).
function ns.Hints()
    local list = {}
    local function Add(text, priority, page)
        list[#list + 1] = { text = text, p = priority or 50, page = page }
    end
    for _, m in ipairs(ns.order) do
        if m.enabled and m.Hints then ns.Guard(m.key .. " hints", m.Hints, m, Add) end
    end
    table.sort(list, function(a, b)
        if a.p ~= b.p then return a.p > b.p end
        return a.text < b.text
    end)
    return list
end

function ns.ModuleAdded()
    for _, key in ipairs({ "settings", "setup" }) do
        local page = ns.pages[key]
        if page and page.frame then
            page.frame:Hide()
            page.frame = nil -- built again, with the new module, the next time it opens
            if current == page then Select(key) end
        end
    end
    ns.Refresh()
end

local function AddCard(m, list)
    local card = m:Card()
    if card then list[#list + 1] = card end
end

local function Cards()
    local list = {}
    for _, m in ipairs(ns.order) do
        if m.enabled and m.Card then
            m.cardLabel = m.cardLabel or (m.key .. " card")
            local ok = ns.Run(m.cardLabel, AddCard, m, list)
            if not ok then list[#list + 1] = { title = m.title, lines = { { "Could not be shown. /zod errors", "" } } } end
        end
    end
    -- Undead Route, when it is installed: where the route wants you and what to walk to next.
    local route = UndeadRoute
    local status
    if type(route) == "table" and route.Status then
        ns.Guard("route card", function() status = route.Status() end)
    end
    if status then -- first: what to do next is what the page is opened for
        table.insert(list, 1, {
            title = "Undead Route",
            lines = {
                { "Stage", tostring(status.stage) .. "  |cff999999" .. tostring(status.range) .. "|r" },
                { status.next or "Nothing on this stage has a place to walk to yet.", "" },
                { "Steps open", tostring(status.left or 0) },
                (tonumber(status.ready) or 0) > 0 and { "Ready to hand in", "|cff59d973" .. status.ready .. "|r" } or nil,
            },
            button = { "Open route", function() route.Toggle() end },
        })
    elseif SlashCmdList and SlashCmdList["UNDEADROUTE"] then
        table.insert(list, 1, {
            title = "Undead Route",
            lines = { { "The step-by-step leveling route.", "" }, { "It follows your level, zone and quest log.", "" } },
            button = { "Open route", function() SlashCmdList["UNDEADROUTE"]("") end },
        })
    end
    if ns.db.general.nextUp then
        local hints = ns.Hints()
        if #hints > 0 then
            local lines = {}
            for i = 1, math.min(4, #hints) do lines[i] = { hints[i].text, "", page = hints[i].page } end
            local top = hints[1]
            table.insert(list, 1, { title = "Next up", lines = lines,
                button = top.page and { "Go", function() ns.Show(top.page) end } or nil })
        end
    end
    local hidden = ns.db.general.hiddenCards
    if hidden then
        for i = #list, 1, -1 do
            if hidden[list[i].title] then table.remove(list, i) end
        end
    end
    return list
end

ns.AddPage({
    key = "home", title = "Home", order = 1,
    Build = function(page, f)
        page.name = T.Text(f, "GameFontNormalLarge")
        page.name:SetPoint("TOPLEFT", 0, -2)
        page.sub = T.Text(f, "GameFontHighlightSmall", T.DIM)
        page.sub:SetPoint("TOPLEFT", 0, -26)
        page.sub:SetWidth(PAGE_W)
        page.xp = T.Bar(f, PAGE_W, 18, T.GOLD)
        page.xp:SetPoint("TOPLEFT", 0, -52)
        page.cards = {}
        -- The cards scroll: with every module on there are more than fit.
        page.scroll, page.child = T.Scroll(f)
        page.scroll:SetPoint("TOPLEFT", 0, -84)
        page.scroll:SetSize(PAGE_W, PAGE_H - 84)
        page.child:SetWidth(PAGE_W)
        page.more = T.Text(f, "GameFontHighlightSmall", T.MUTED)
        page.more:SetPoint("TOPRIGHT", 0, -6)
        page.more:SetText("Scroll for more")
        page.empty = T.Text(f, "GameFontHighlightSmall", T.MUTED)
        page.empty:SetPoint("TOPLEFT", 0, -90)
        page.empty:SetWidth(PAGE_W)
        page.empty:SetText("No cards to show. Switch modules on under Settings, or bring hidden cards back under Settings > General.")
    end,
    Refresh = function(page)
        local char = ns.char
        local level = ns.Level() or char.level or 1
        if page.level and level > page.level and main:IsShown() then page.xp:Sweep() end -- a level up while you look
        page.level = level
        page.name:SetText("|c" .. ns.ClassHex(char.class) .. (char.name or "?") .. "|r  |cffffffffLevel " .. level .. "|r")
        local zone, sub = GetRealZoneText and GetRealZoneText() or "", GetSubZoneText and GetSubZoneText() or ""
        local where = (sub ~= "" and sub ~= zone) and (sub .. ", " .. zone) or zone
        page.sub:SetText((char.race or "") .. " " .. (char.className or "") .. (where ~= "" and ("   |cff999999in|r " .. where) or ""))

        local xp, max = UnitXP and UnitXP("player") or 0, UnitXPMax and UnitXPMax("player") or 0
        if max > 0 then
            local rested = GetXPExhaustion and GetXPExhaustion() or 0
            page.xp:Set(xp / max, (xp + rested) / max)
            page.xp.text:SetText(string.format("%s / %s XP  (%d%%)%s", ns.Comma(xp), ns.Comma(max), math.floor(xp / max * 100),
                rested > 0 and string.format("   +%d%% rested", math.floor(rested / max * 100)) or ""))
        else
            page.xp:Set(1)
            page.xp.text:SetText("Level " .. level)
        end

        local cards = Cards()
        for i, spec in ipairs(cards) do
            local card = page.cards[i] or Card(page.child, i)
            page.cards[i] = card
            card.title:SetText(spec.title)
            card.key = spec.title
            for n = 1, CARD_LINES do
                local line = spec.lines and spec.lines[n]
                card.left[n]:SetText(line and line[1] or "")
                card.right[n]:SetText(line and line[2] or "")
                -- The left text stops short of the right one instead of running under it; the right one takes
                -- at most 60% of the card, so the left keeps room for its words.
                local right = (line and line[2] or "") ~= "" and math.min(math.floor(CARD_W * 0.6), math.ceil(T.TextWidth(card.right[n])) + 1) or 0
                card.right[n]:SetWidth(right > 0 and right or 1)
                card.right[n]:SetWordWrap(false)
                card.left[n]:SetWidth(CARD_W - 20 - (right > 0 and right + 8 or 0))
                card.hits[n].page = line and line.page
                card.hits[n].leftW = CARD_W - 20 - (right > 0 and right + 8 or 0)
                card.hits[n]:SetShown(line ~= nil and (line[1] or "") ~= "")
            end
            card.button:SetShown(spec.button ~= nil)
            if spec.button then
                card.button.label:SetText(spec.button[1])
                card.button.click = spec.button[2]
            end
            card:Show()
        end
        for i = #cards + 1, #page.cards do page.cards[i]:Hide() end
        local height = math.ceil(#cards / 2) * (CARD_H + 8)
        page.child:SetHeight(math.max(1, height))
        local range = math.max(0, height - page.scroll:GetHeight())
        if page.scroll:GetVerticalScroll() > range then page.scroll:SetVerticalScroll(range) end
        page.more:SetText(range > 0 and "Scroll for more. Right-click a card to hide it." or "Right-click a card to hide it.")
        page.more:SetShown(#cards > 0)
        page.empty:SetShown(#cards == 0)
    end,
})

---------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------

local LIST_W = 200
local DETAIL_W = PAGE_W - LIST_W - PAD
local OPT_W = DETAIL_W - 8 -- the detail's content, clear of the scroll thumb

-- Settings that belong to no module. It is listed first and cannot be switched off.
local general = {
    key = "general", title = "General", enabled = true, noToggle = true,
    desc = "Settings for ZodUI as a whole. ZodUI runs on its own; these addons are needed for the parts named:",
    needs = ns.NEEDS_ORDER,
    options = {
        { type = "step", key = "font", label = "Text size", min = 0, max = 4, step = 1,
            format = function(v) return v == 0 and "Game default" or ("+" .. v) end },
        { type = "cycle", key = "accent", label = "Accent colour", reload = "The new accent colour", choices = (function()
            local choices = {}
            for i, accent in ipairs(T.ACCENTS) do choices[i] = { accent[1], accent[2] } end
            return choices
        end)() },
        { type = "cycle", key = "look", label = "Look", reload = "The new look", choices = T.LOOKS },
        { type = "note", text = "Forever: the game's frames, buttons and warm colours. Modern: ZodUI's flat dark look. A new look or accent colour shows after /reload.", lines = 2 },
        { type = "step", key = "scale", label = "Window size (or drag its corner)", min = 70, max = 150, step = 5, format = function(v) return v .. "%" end },
        { type = "step", key = "alpha", label = "Window opacity", min = 50, max = 100, step = 5, format = function(v) return v .. "%" end },
        { type = "check", key = "remember", label = "Open the window on the page I had open last" },
        { type = "check", key = "nextUp", label = "A Next up card on Home with what wants doing now" },
        { type = "check", key = "combatClose", label = "Close the window when a fight starts" },
        { type = "check", key = "motion", label = "Animations: windows rise in, rows lift in, numbers count", tip = "Off: everything is at once where it ends up." },
        { type = "check", key = "hideOff", label = "Leave the pages of modules that are off out of the list" },
        { type = "check", key = "toasts", label = "Show alerts as ZodUI notices (off: the game's red error text)" },
        { type = "step", key = "toastHold", label = "How long a notice stays", min = 2, max = 15, step = 1, format = function(v) return v .. " s" end },
        { type = "check", key = "toastSound", label = "Play a sound with each notice" },
        { type = "check", key = "speak", label = "Read notices aloud (text to speech)", tip = "The game's text to speech; its voice and speed are under Options > Accessibility." },
        { type = "button", label = "See what a notice looks like", text = "Show one", click = function() SlashCmdList["ZODUI"]("test") end },
        { type = "button", label = "Cards you hid from Home", text = "Show all", click = function()
            ns.db.general.hiddenCards = {}
            ns.Print("every card is back on Home.")
            ns.Refresh()
        end },
        { type = "check", key = "greet", label = "Greet me at login: how long I was away and my rested XP" },
        { type = "check", key = "minimap", label = "Show the minimap button" },
        { type = "check", key = "welcome", label = "Say in chat that ZodUI loaded" },
        { type = "button", label = "Move the notices, the info bar and the coordinates", text = "Unlock", click = function() SlashCmdList["ZODUI"]("unlock") end },
        { type = "button", label = "Window positions", text = "Reset", click = function() SlashCmdList["ZODUI"]("reset") end },
        { type = "button", label = "Your settings as text, to keep or share", text = "Export", click = function() SlashCmdList["ZODUI"]("export") end },
        { type = "button", label = "Take over settings from a text", text = "Import", click = function() SlashCmdList["ZODUI"]("import") end },
    },
    OnOption = function(_, key)
        if key == "font" then T.ApplyFont() end
        if key == "minimap" and ns.UpdateMinimap then ns.UpdateMinimap() end
        if key == "scale" or key == "alpha" then ns.ApplyScale() end
        if key == "motion" then ns.Motion.enabled = ns.db.general.motion and true or false end
    end,
}

-- Whether a module's name, description or one of its settings contains `part`.
local function Matches(mod, part)
    if part == "" then return true end
    local function Has(s) return type(s) == "string" and s:lower():find(part, 1, true) ~= nil end
    if Has(mod.title) or Has(mod.desc) then return true end
    for _, opt in ipairs(mod.options or {}) do
        if Has(opt.label) or Has(opt.text) then return true end
    end
    return false
end

local function BuildOptions(holder, mod)
    local y = 0
    holder.sync = {}
    local function Sync(fn) holder.sync[#holder.sync + 1] = fn end
    local function Changed(opt, value)
        mod.db[opt.key] = value
        if mod.OnOption and mod.enabled then ns.Guard(mod.key .. " option", mod.OnOption, mod, opt.key, value) end
        if opt.reload then T.AskReload(opt.reload) end -- it shows only after /reload: ask, so it is not missed
        ns.Refresh()
    end
    local function Label(text, dy)
        local fs = T.Text(holder, "GameFontHighlightSmall")
        fs:SetPoint("TOPLEFT", 0, -y - (dy or 5))
        fs:SetWidth(OPT_W - 178) -- ends before the control on the right, also with a larger text size
        fs:SetWordWrap(false)
        fs:SetText(text)
        return fs
    end

    for _, opt in ipairs(mod.options or {}) do
        if opt.type == "check" then
            local c = T.Check(holder, opt.label, OPT_W, function(v) Changed(opt, v) end)
            c.tip = opt.tip
            c:SetPoint("TOPLEFT", 0, -y)
            Sync(function() c:SetChecked(mod.db[opt.key]) end)
            y = y + 24
        elseif opt.type == "step" then
            Label(opt.label)
            local value = T.Text(holder, "GameFontHighlightSmall")
            local function Show()
                local v = mod.db[opt.key]
                value:SetText(opt.format and opt.format(v) or tostring(v))
            end
            local function Step(dir)
                local v = (mod.db[opt.key] or opt.min) + dir * (opt.step or 1)
                Changed(opt, math.min(opt.max, math.max(opt.min, v)))
                Show()
            end
            local minus = T.Button(holder, "-", 24, function() Step(-1) end)
            minus:SetPoint("TOPLEFT", OPT_W - 170, -y)
            local plus = T.Button(holder, "+", 24, function() Step(1) end)
            plus:SetPoint("TOPLEFT", OPT_W - 24, -y)
            value:SetPoint("TOPLEFT", OPT_W - 142, -y - 5)
            value:SetWidth(114)
            value:SetJustifyH("CENTER")
            Sync(Show)
            y = y + 28
        elseif opt.type == "cycle" then
            Label(opt.label)
            local b
            local function Index()
                for i, choice in ipairs(opt.choices) do
                    if choice[1] == mod.db[opt.key] then return i end
                end
                return 1
            end
            local function Show() b.label:SetText(opt.choices[Index()][2]) end
            b = T.Button(holder, "", 170, function()
                Changed(opt, opt.choices[Index() % #opt.choices + 1][1])
                Show()
            end)
            b:SetPoint("TOPLEFT", OPT_W - 170, -y)
            b.tip = "Click to change"
            Sync(Show)
            y = y + 28
        elseif opt.type == "button" then
            Label(opt.label)
            local b = T.Button(holder, opt.text, 170, function()
                ns.Guard(mod.key .. " button", opt.click, mod)
                ns.Refresh()
            end)
            b.confirm = opt.confirm -- one that throws something away asks first
            b:SetPoint("TOPLEFT", OPT_W - 170, -y)
            y = y + 28
        elseif opt.type == "header" then
            y = y + 6
            local fs = Label(opt.label, 0)
            fs:SetTextColor(T.GOLD[1], T.GOLD[2], T.GOLD[3])
            y = y + 20
        elseif opt.type == "note" then
            local fs = Label(opt.text, 0)
            fs:SetTextColor(T.MUTED[1], T.MUTED[2], T.MUTED[3])
            fs:SetWidth(OPT_W)
            fs:SetWordWrap(true)
            fs:SetSpacing(2)
            y = y + (opt.lines or 2) * 15 + 6
        end
    end
    if mod.defaults and mod.options and #mod.options > 0 then
        y = y + 6
        Label("Put this module's settings back as they came")
        local b = T.Button(holder, "Defaults", 170, function()
            for k, v in pairs(mod.defaults) do
                if k ~= "enabled" and type(v) ~= "table" and mod.db[k] ~= v then -- lists and positions are yours, not settings
                    mod.db[k] = v
                    if mod.OnOption and mod.enabled then ns.Guard(mod.key .. " option", mod.OnOption, mod, k, v) end
                end
            end
            for _, fn in ipairs(holder.sync) do fn() end
            ns.Print(mod.title .. ": the settings are back as they came.")
            ns.Refresh()
        end)
        b:SetPoint("TOPLEFT", OPT_W - 170, -y)
        y = y + 28
    end
    holder:SetHeight(math.max(1, y))
end

ns.AddPage({
    key = "settings", title = "Settings", order = 100, group = "ZodUI",
    Build = function(page, f)
        general.db = ns.db.general
        page.mods = { general }
        for _, m in ipairs(ns.order) do page.mods[#page.mods + 1] = m end
        page.selected = general
        -- With Remember the page on, Settings opens on the module you last looked at.
        local lastMod = ns.db.general.remember and ns.db.general.lastSettings
        if lastMod and ns.modules[lastMod] then page.selected = ns.modules[lastMod] end
        page.details = {}

        page.filter = ""
        page.search = T.Edit(f, LIST_W, 24)
        page.search:SetPoint("TOPLEFT", 0, 0)
        page.search.edit:SetMaxLetters(30)
        page.search.clearOnEscape = true
        page.search.hint = T.Text(page.search, "GameFontHighlightSmall", T.MUTED)
        page.search.hint:SetPoint("LEFT", 8, 0)
        page.search.hint:SetText("Search settings")
        page.search.edit:SetScript("OnTextChanged", function(self)
            local text = (self:GetText() or ""):lower()
            page.search.hint:SetShown(text == "")
            if text ~= page.filter then
                page.filter = text
                page:Refresh()
            end
        end)

        local list = T.Panel(f, T.PANEL)
        list:SetPoint("TOPLEFT", 0, -30)
        list:SetSize(LIST_W, PAGE_H - 30)
        local scroll, child = T.Scroll(list)
        scroll:SetPoint("TOPLEFT", 1, -1)
        scroll:SetSize(LIST_W - 2, PAGE_H - 32)
        child:SetSize(LIST_W - 2, #page.mods * 26)
        page.child, page.listScroll = child, scroll
        page.none = T.Text(list, "GameFontHighlightSmall", T.MUTED)
        page.none:SetPoint("TOPLEFT", 10, -10)
        page.none:SetText("No setting matches.")
        page.rows = {}
        for i, m in ipairs(page.mods) do
            local row = CreateFrame("Button", nil, child)
            row:SetSize(LIST_W - 2, 26)
            row:SetPoint("TOPLEFT", 0, -(i - 1) * 26)
            row.mod = m
            row.bg = row:CreateTexture(nil, "BACKGROUND")
            row.bg:SetAllPoints(row)
            row.bg:SetTexture(T.WHITE)
            row.bg:SetVertexColor(T.HOVER[1], T.HOVER[2], T.HOVER[3], 0)
            row.name = T.Text(row, "GameFontHighlightSmall")
            row.name:SetPoint("LEFT", 10, 0)
            row.name:SetText(m.title)
            row.state = T.Text(row, "GameFontHighlightSmall")
            row.state:SetPoint("RIGHT", -10, 0)
            row:SetScript("OnClick", function(self)
                page.selected = self.mod
                ns.db.general.lastSettings = self.mod.key ~= "general" and self.mod.key or nil
                page:Refresh()
            end)
            row:SetScript("OnEnter", function(self)
                if self.mod ~= page.selected then self.bg:SetVertexColor(T.HOVER[1], T.HOVER[2], T.HOVER[3], 0.6) end
            end)
            row:SetScript("OnLeave", function(self)
                if self.mod ~= page.selected then self.bg:SetVertexColor(T.HOVER[1], T.HOVER[2], T.HOVER[3], 0) end
            end)
            page.rows[i] = row
        end
    end,
    Detail = function(page, mod)
        -- The detail scrolls: a module with many options, or a long description, is taller than the page.
        local box, d = T.Scroll(page.frame)
        box:SetPoint("TOPLEFT", LIST_W + PAD, 0)
        box:SetSize(DETAIL_W, PAGE_H)
        d:SetWidth(OPT_W) -- room for the thumb
        local title = T.Text(d, "GameFontNormalLarge", T.GOLD)
        title:SetPoint("TOPLEFT", 0, -2)
        title:SetText(mod.title)
        local desc = T.Text(d, "GameFontHighlightSmall", T.DIM)
        desc:SetPoint("TOPLEFT", 0, -28)
        desc:SetWidth(OPT_W)
        desc:SetWordWrap(true)
        desc:SetSpacing(2)
        desc:SetText(mod.desc or "")
        -- Below the description however many lines it takes, never closer than before.
        local y = math.max(78, math.ceil(28 + (desc:GetStringHeight() or 0) + 14))
        -- The other addons it needs, each with whether it is installed.
        d.needs = {}
        for _, addon in ipairs(mod.needs or {}) do
            local line = T.Text(d, "GameFontHighlightSmall", T.DIM)
            line:SetPoint("TOPLEFT", 0, -y)
            line:SetWidth(OPT_W)
            line:SetWordWrap(true)
            line:SetSpacing(2)
            line:SetText(ns.NeedText(addon))
            line.addon = addon
            d.needs[#d.needs + 1] = line
            y = y + math.ceil((line:GetStringHeight() or 0) + 8)
        end
        if #d.needs > 0 then y = y + 6 end
        if not mod.noToggle then
            d.toggle = T.Check(d, "Module on", OPT_W, function(v)
                if v then mod:Enable() else mod:Disable() end
                page:Refresh()
            end)
            d.toggle:SetPoint("TOPLEFT", 0, -y)
            d.unsupported = T.Text(d, "GameFontHighlightSmall", T.RED)
            d.unsupported:SetPoint("TOPLEFT", 130, -y - 3)
            d.unsupported:SetText("This game client lacks what the module needs, so it does nothing.")
            d.unsupported:Hide()
            y = y + 26
            if mod.db.conflict then
                local note = T.Text(d, "GameFontHighlightSmall", T.MUTED)
                note:SetPoint("TOPLEFT", 0, -y)
                note:SetWidth(OPT_W)
                note:SetWordWrap(true)
                note:SetSpacing(2)
                note:SetText("It started switched off because " .. mod.db.conflict .. " is installed and does the same job.")
                y = y + 34
            end
            y = y + 8
        end
        d.options = CreateFrame("Frame", nil, d)
        d.options:SetPoint("TOPLEFT", 0, -y)
        d.options:SetSize(OPT_W, 10)
        BuildOptions(d.options, mod)
        d:SetHeight(y + d.options:GetHeight() + 8)
        box.toggle, box.unsupported, box.options, box.content = d.toggle, d.unsupported, d.options, d
        box:Sync()
        return box
    end,
    Refresh = function(page, arg)
        if arg and ns.modules[arg] then page.selected = ns.modules[arg] end
        if arg == "general" then page.selected = general end
        local shown, first, selectedShown = 0, nil, false
        for _, row in ipairs(page.rows) do
            local match = Matches(row.mod, page.filter)
            row:SetShown(match)
            if match then
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", 0, -shown * 26)
                shown = shown + 1
                first = first or row.mod
                if row.mod == page.selected then selectedShown = true end
            end
        end
        page.child:SetHeight(math.max(1, shown * 26))
        page.listScroll:Sync()
        page.none:SetShown(shown == 0)
        if not selectedShown and first then page.selected = first end -- the search moved on: show the first match
        -- The chosen module (remembered, from a search or a card) is brought into view, once, and only as far
        -- as needed: a row half under the edge moves up just enough, so the list does not jump under the mouse.
        if page.scrolledTo ~= page.selected then
            page.scrolledTo = page.selected
            local index = 0
            for _, row in ipairs(page.rows) do
                if row:IsShown() then
                    index = index + 1
                    if row.mod == page.selected then break end
                end
            end
            local view, now = page.listScroll:GetHeight() or 0, page.listScroll:GetVerticalScroll()
            local top, range = (index - 1) * 26, math.max(0, page.child:GetHeight() - view)
            local want = now
            if top < now then want = top elseif top + 26 > now + view then want = top + 26 - view end
            if want ~= now then
                page.listScroll:SetVerticalScroll(math.min(range, math.max(0, want)))
                page.listScroll:Sync()
            end
        end
        for _, row in ipairs(page.rows) do
            local m = row.mod
            local on = m == page.selected
            row.bg:SetVertexColor(T.HOVER[1], T.HOVER[2], T.HOVER[3], on and 1 or 0)
            row.state:SetText(m.noToggle and "" or (m.enabled and T.Paint("On", T.GREEN) or T.Paint("Off", T.MUTED)))
        end
        local mod = page.selected
        for key, d in pairs(page.details) do d:SetShown(key == mod.key) end
        local d = page.details[mod.key]
        if not d then
            d = page:Detail(mod)
            page.details[mod.key] = d
        end
        if d.toggle then
            d.toggle:SetChecked(mod.enabled)
            d.unsupported:SetShown(mod.enabled and mod.unsupported or false)
        end
        for _, line in ipairs(d.content and d.content.needs or {}) do line:SetText(ns.NeedText(line.addon)) end
        for _, fn in ipairs(d.options.sync) do fn() end
    end,
})

---------------------------------------------------------------------------
-- Search
---------------------------------------------------------------------------

-- Everything in ZodUI with `part` (lower case) in it: { kind, text, detail, key = page, arg = its argument }.
-- A module adds what it holds with M:Find(part, add, has).
local MOST_FOUND = 100

function ns.Find(part)
    local results = { total = 0 } -- total counts the ones past MOST_FOUND too
    local function Has(s)
        return type(s) == "string" and s:lower():find(part, 1, true) ~= nil
    end
    local function Add(kind, text, detail, key, arg)
        results.total = results.total + 1
        if #results < MOST_FOUND then results[#results + 1] = { kind, text, detail or "", key = key, arg = arg } end
    end
    for _, page in ipairs(pageList) do
        if not page.hidden and Has(page.title) then Add("Page", page.title, "", page.key) end
    end
    for _, opt in ipairs(general.options) do
        if opt.label and Has(opt.label) then Add("Setting", opt.label, "General", "settings", "general") end
    end
    for _, m in ipairs(ns.order) do
        if Has(m.title) or Has(m.desc) then Add("Module", m.title, m.enabled and "on" or "off", "settings", m.key) end
        for _, opt in ipairs(m.options or {}) do
            if opt.label and opt.type ~= "header" and Has(opt.label) then Add("Setting", opt.label, m.title, "settings", m.key) end
        end
    end
    for _, m in ipairs(ns.order) do
        if m.enabled and m.Find then ns.Guard(m.key .. " search", m.Find, m, part, Add, Has) end
    end
    for _, c in ipairs(ns.COMMANDS or {}) do
        if Has(c[1]) or Has(c[2]) then Add("Command", c[1], c[2], "commands") end
    end
    -- Last: the same words in Codex Forever's database of items, NPCs and quests, when it is installed.
    if ns.Codex.Has() then
        results.total = results.total + 1
        results[#results + 1] = { "Codex", 'Search Codex Forever for "' .. part .. '"', "items, NPCs, quests, recipes", codex = part }
    end
    return results
end

ns.AddPage({
    key = "find", title = "Search", order = 102, hidden = true,
    Build = function(page, f)
        page.head = T.Text(f, "GameFontNormalLarge", T.GOLD)
        page.head:SetPoint("TOPLEFT", 0, -2)
        page.keys = T.Text(f, "GameFontHighlightSmall", T.MUTED)
        page.keys:SetPoint("TOPRIGHT", 0, -6)
        page.keys:SetText("Up and Down choose, Enter opens")
        page.list = T.Table(f, { { "Kind", 90 }, { "Found", PAGE_W - 420 }, { "", 310 } }, PAGE_W, PAGE_H - 34, nil, true) -- best first, and Up/Down walk it
        page.list:SetPoint("TOPLEFT", 0, -34)
        page.list.onClick = function(result)
            if result.codex then
                ns.Codex.Open(result.codex)
            else
                ns.Show(result.key, result.arg)
            end
        end
    end,
    Refresh = function(page)
        local results = #query >= 2 and ns.Find(query) or {}
        page.results = results
        if page.cursorFor ~= query then page.cursor, page.cursorFor = nil, query end -- new words: nothing chosen yet
        if page.cursor and page.cursor > #results then page.cursor = #results > 0 and #results or nil end
        local total = results.total or 0
        page.head:SetText((total > #results and ("The first " .. #results .. " of " .. total) or #results) .. " found for '" .. query .. "'")
        local rows = {}
        for i, result in ipairs(results) do rows[i] = { result[1], result[2], result[3], data = result } end
        page.list.selected = page.cursor and results[page.cursor] or nil
        page.list:SetRows(rows, "Nothing in ZodUI matches. The search looks through pages, settings, items, to-dos, reminders, goals, characters, factions and dungeon runs.")
    end,
})

