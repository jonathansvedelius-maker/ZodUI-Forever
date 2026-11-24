local _, ns = ...

-- The guide: the route as one list of steps for a stage (pick up, do, hand in, in walking order), drawn with
-- the art in Media\Guide. /route guide opens it; the classic window (Window.lua) is one click away for the rest.
-- It takes the route's logic from ns.I, as Window.lua does, and is drawn again on every refresh (ns.RefreshGuide).

local I, T = ns.I, ns.T
local Print, Level, InLog, Complete, QuestName = I.Print, I.Level, I.InLog, I.Complete, I.QuestName
local TaskKey, TaskState, Status, Recommend, StepPlace, WorldPos = I.TaskKey, I.TaskState, I.Status, I.Recommend, I.StepPlace, I.WorldPos
local RangeText, StageName, WaitsFor, ObjectiveLines, ReadyToHandIn = I.RangeText, I.StageName, I.WaitsFor, I.ObjectiveLines, I.ReadyToHandIn

local unpack = unpack or table.unpack

local ART = "Interface\\AddOns\\UndeadRoute\\Media\\Guide\\"
local TITLE_FONT = "Fonts\\MORPHEUS.TTF"

local W, H = 620, 560
local EDGE = 11 -- where the frame's art ends and the window's own fill begins
local HEAD_H, PROGRESS_H, FOOT_H = 86, 36, 62
local ROW_GAP, ROW_ONE, ROW_TWO = 5, 36, 48
local LIST_PAD = 9 -- room around the rows

local TEXT = { 0.95, 0.92, 0.85 }
local GOLDT = { 1, 0.80, 0.26 }
local DIM = { 0.64, 0.62, 0.58 }
local FAINT = { 0.42, 0.41, 0.40 }
local BAR_CAP = 8 / 128 -- the round end of the progress bars' files
local SEG_H = 8
local KIND = {
    zone = { "Main route", { 0.36, 0.80, 0.40 } }, dungeon = { "Dungeon", { 0.40, 0.65, 1 } },
    alt = { "Side branch", { 0.72, 0.55, 1 } }, city = { "City quests", { 0.75, 0.75, 0.75 } },
}

local db, guide
local shownStage -- the stage on show: the recommended one while the guide follows the route

-- The looks, picked under the gear (db.guide.theme). Classic is the art in Media\Guide; the others are a folder in it
-- with the same file names (made by tools/themes.py), and an emblem where Classic has the pennant. `fade` is the
-- colour the header fades into, the panel's own.
local THEMES = {
    { key = "Classic", name = "Classic", fade = { 0.11, 0.075, 0.085 } },
    { key = "HordeEmber", name = "Horde Ember", fade = { 0.13, 0.06, 0.05 } },
    { key = "AllianceSteel", name = "Alliance Steel", fade = { 0.05, 0.07, 0.13 } },
    { key = "EmeraldWilds", name = "Emerald Wilds", fade = { 0.05, 0.09, 0.04 } },
    { key = "ArcaneNight", name = "Arcane Night", fade = { 0.08, 0.05, 0.13 } },
}
local SHARED = { Pill = true, PillLine = true, Tip = true, Banner = true, banner_horde = true } -- in every look

local function Theme()
    local key = db and db.guide and db.guide.theme
    for _, t in ipairs(THEMES) do
        if t.key == key then return t end
    end
    return THEMES[1]
end

-- A file of the guide's art, in the look picked.
local function Path(file)
    local theme = Theme()
    if theme.key ~= "Classic" and not SHARED[file] then return ART .. theme.key .. "\\" .. file end
    return ART .. file
end

---------------------------------------------------------------------------
-- Art
---------------------------------------------------------------------------

local function Tex(parent, file, layer, w, h)
    local t = parent:CreateTexture(nil, layer or "ARTWORK")
    t:SetTexture(Path(file))
    if w then t:SetSize(w, h or w) end
    return t
end

-- A nine-slice, its pieces one file each (`base`_top_left ... `base`_bottom_right): the corners are drawn `px` big,
-- the edges and the middle stretch. `out` lets the art reach past the frame. Returns the pieces, with Color,
-- SetShown and SetBase (another set of pieces, for another state: hover, active, done).
local PIECES = { "top_left", "top", "top_right", "left", "center", "right", "bottom_left", "bottom", "bottom_right" }
local function Nine(parent, base, px, layer, out)
    out = out or 0
    local set = {}
    for i, piece in ipairs(PIECES) do set[i] = Tex(parent, base .. "_" .. piece, layer) end
    function set.SetBase(_, b)
        if set.base == b then return end
        set.base = b
        for i, piece in ipairs(PIECES) do set[i]:SetTexture(Path(b .. "_" .. piece)) end
    end
    set.base = base
    local tl, tc, tr, ml, mc, mr, bl, bc, br = unpack(set)
    tl:SetSize(px, px) tr:SetSize(px, px) bl:SetSize(px, px) br:SetSize(px, px)
    tl:SetPoint("TOPLEFT", -out, out)
    tr:SetPoint("TOPRIGHT", out, out)
    bl:SetPoint("BOTTOMLEFT", -out, -out)
    br:SetPoint("BOTTOMRIGHT", out, -out)
    tc:SetPoint("TOPLEFT", tl, "TOPRIGHT") tc:SetPoint("BOTTOMRIGHT", tr, "BOTTOMLEFT")
    bc:SetPoint("TOPLEFT", bl, "TOPRIGHT") bc:SetPoint("BOTTOMRIGHT", br, "BOTTOMLEFT")
    ml:SetPoint("TOPLEFT", tl, "BOTTOMLEFT") ml:SetPoint("BOTTOMRIGHT", bl, "TOPRIGHT")
    mr:SetPoint("TOPLEFT", tr, "BOTTOMLEFT") mr:SetPoint("BOTTOMRIGHT", br, "TOPRIGHT")
    mc:SetPoint("TOPLEFT", tl, "BOTTOMRIGHT") mc:SetPoint("BOTTOMRIGHT", br, "TOPLEFT")
    function set.Color(_, r, g, b, a) for i = 1, 9 do set[i]:SetVertexColor(r, g, b, a or 1) end end
    function set.SetShown(_, on) for i = 1, 9 do set[i]:SetShown(on) end end
    return set
end

-- A pill cut in three, round ends kept, `h` high, filling its frame's width. `cap` is the part of the file's width
-- that each end takes (Pill and PillLine: a quarter; the progress bars: 8 of their 128 pixels).
local function Pill(parent, file, h, layer, cap)
    cap = cap or 0.25
    local set = {}
    for i, cut in ipairs({ { 0, cap }, { cap, 1 - cap }, { 1 - cap, 1 } }) do
        local t = Tex(parent, file, layer)
        t:SetTexCoord(cut[1], cut[2], 0, 1)
        set[i] = t
    end
    local l, m, r = set[1], set[2], set[3]
    l:SetSize(h / 2, h) r:SetSize(h / 2, h)
    l:SetPoint("LEFT") r:SetPoint("RIGHT")
    m:SetPoint("TOPLEFT", l, "TOPRIGHT") m:SetPoint("BOTTOMRIGHT", r, "BOTTOMLEFT")
    function set.Color(_, cr, cg, cb, ca) for i = 1, 3 do set[i]:SetVertexColor(cr, cg, cb, ca or 1) end end
    function set.SetFile(_, f)
        if set.file == f then return end
        set.file = f
        for i = 1, 3 do set[i]:SetTexture(Path(f)) end
    end
    set.file = file
    return set
end

local function Text(parent, font, color, size)
    local fs = T.Text(parent, font or "GameFontHighlightSmall", color)
    if size then
        local path = fs:GetFont()
        fs:SetFont(path or "Fonts\\FRIZQT__.TTF", size + ((db and db.font or 2) - 2), "")
    end
    return fs
end

local function Tip(owner, title, text)
    if not (GameTooltip and GameTooltip.SetOwner) then return end
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:AddLine(title, 1, 0.82, 0)
    if text then GameTooltip:AddLine(text, 0.9, 0.9, 0.9, true) end
    GameTooltip:Show()
end
local function Untip() if GameTooltip and GameTooltip.Hide then GameTooltip:Hide() end end

-- A dark button with a gold edge (lit while the mouse is on it): an optional icon and a label.
local function Button(parent, w, h, glyph, label, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(w, h)
    b.frame = Nine(b, "button_normal", 10, "BACKGROUND")
    if glyph then
        b.glyph = Tex(b, glyph, "ARTWORK", h - 10)
        b.glyph:SetPoint(label and "LEFT" or "CENTER", label and 8 or 0, 0)
    end
    if label then
        b.label = Text(b, "GameFontHighlight", TEXT, 13)
        b.label:SetPoint("LEFT", glyph and (h + 2) or 12, 0)
        b.label:SetText(label)
    end
    b:SetScript("OnEnter", function(self)
        self.frame:SetBase("button_hover")
        if self.tip then Tip(self, self.tipTitle or (label or ""), self.tip) end
    end)
    b:SetScript("OnLeave", function(self)
        self.frame:SetBase("button_normal")
        Untip()
    end)
    b:SetScript("OnClick", onClick)
    return b
end

---------------------------------------------------------------------------
-- The steps of a stage
---------------------------------------------------------------------------

-- A tip that sends you somewhere gets the gold target; the others the blue "i".
local function TipKind(text)
    local t = (text or ""):lower()
    if t:find("^go ") or t:find("^travel") or t:find("^fly") or t:find("^take the") or t:find("^run ") or t:find("^ride") then
        return "travel"
    end
    return "tip"
end

-- The first unfinished objective of a quest in your log: its label, have, need.
local function Objective(task)
    for _, line in ipairs(ObjectiveLines(task)) do
        local plain = line:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
        if not plain:find("%- done$") then
            local have, need, label = plain:match("^(%d+)/(%d+)%s+(.+)$")
            if have then return label, tonumber(have), tonumber(need) end
            return plain
        end
    end
end

-- The stage as a list of steps: { kind, task, i, title, place, done, waiting, sub, have, need }, in the order you do them:
-- the tips where they stand, then each batch as pick up all, do all, hand in all.
local function Steps(stage, level)
    local steps, seen = {}, {}
    local function Quest(list, kind)
        for _, e in ipairs(list) do
            local task, ts = e.task, e.state
            local name = QuestName(task.quest)
            local step = { kind = kind, task = task, i = e.i, state = ts }
            if ts == "later" or ts == "locked" then
                if kind ~= "pickup" then return end
                step.waiting = true
                step.title = "Later: " .. name
                step.sub = ts == "later" and ("from level " .. (task.req or level))
                    or ("after " .. (WaitsFor(task.quest) or "the quest before it"))
            elseif kind == "pickup" then
                step.title, step.done = "Pick up: " .. name, ts ~= "do"
                step.place = StepPlace(task, "pickup")
            elseif kind == "work" then
                local finished = ts == "done" or (ts == "inlog" and Complete(task.id))
                step.title, step.done = "Do: " .. name, finished
                local w = ts == "inlog" and not finished and I.BestWork(stage, level, { task })
                step.place = StepPlace(task, "do", w and w.at)
                if ts == "inlog" and not finished then
                    local label, have, need = Objective(task)
                    step.sub, step.have, step.need = label, have, need
                end
            else
                step.title, step.done = "Turn in: " .. name, ts == "done"
                step.place = StepPlace(task, "handin")
            end
            steps[#steps + 1] = step
        end
    end
    -- One group of quests (a batch, or a quest of its own): pick up all, do all, hand in all.
    local function Group(idx)
        local list = {}
        for _, i in ipairs(idx) do
            local ts = TaskState(stage, i, level)
            if ts ~= "skipped" and ts ~= "closed" and ts ~= "low" then
                list[#list + 1] = { task = stage.tasks[i], i = i, state = ts }
            end
        end
        local open, waiting = {}, {}
        for _, e in ipairs(list) do
            local wait = e.state == "later" or e.state == "locked"
            if wait then waiting[#waiting + 1] = e else open[#open + 1] = e end
        end
        -- In the order the arrow takes them: the nearest giver first, then the best objective camp.
        Quest(I.WalkSort(stage, level, open, "pickup"), "pickup")
        Quest(I.WalkSort(stage, level, open, "do"), "work")
        Quest(open, "handin")
        Quest(waiting, "pickup") -- what cannot be done yet comes after the group: it waits for it, or for a level
    end
    for i, task in ipairs(stage.tasks) do
        if not task.id then
            local ts = TaskState(stage, i, level)
            if ts ~= "low" then
                steps[#steps + 1] = { kind = TipKind(task.t), task = task, i = i, title = task.t, done = ts == "done",
                    waiting = ts == "later", place = task.x and { map = task.map, zone = stage.zone, x = task.x, y = task.y,
                    title = task.pinTitle or stage.hub } or nil }
            end
        elseif task.batch and task.batch.idx then
            if not seen[task.batch] then
                seen[task.batch] = true
                Group(task.batch.idx)
            end
        else
            Group({ i })
        end
    end
    return steps
end

-- The step you are on: where the route's next step (the arrow's, or the quest you clicked) is; else the first open
-- quest step, else the first open tip. Tips are for arriving, so they do not hold the route up.
local function Active(steps, stage)
    local next = I.NextStep(stage)
    if next and next.id then
        for k, s in ipairs(steps) do
            if s.task.id == next.id and s.kind == next.kind and not s.done then
                return k
            end
        end
    end
    local tip
    for k, s in ipairs(steps) do
        if not s.done and not s.waiting then
            if s.task.id then return k end
            tip = tip or k
        end
    end
    return tip
end

---------------------------------------------------------------------------
-- Distance
---------------------------------------------------------------------------

local worldOf = {} -- place key -> { continent, x, y }: a place stands still, so it is asked for once

-- Yards from you to a place, or nil when the game cannot say (another continent, an instance, no position).
local function Yards(place)
    if not (place and place.map and place.x and ns.WhereAmI) then return end
    local key = place.key or (place.map .. ":" .. place.x .. ":" .. place.y)
    local w = worldOf[key]
    if not w then
        local continent, x, y = WorldPos(place.map, place.x, place.y)
        if not continent then return end
        w = { continent, x, y }
        worldOf[key] = w
    end
    local mine, mx, my = ns.WhereAmI()
    if not (mine and mine == w[1]) then return end
    return math.sqrt((w[2] - mx) ^ 2 + (w[3] - my) ^ 2)
end

local function DistText(yards)
    if not yards then return nil end
    if yards < 10 then return "here" end
    if yards >= 1000 then return string.format("%.1fk yd", yards / 1000) end
    return string.format("%d yd", math.floor(yards / 5 + 0.5) * 5)
end

---------------------------------------------------------------------------
-- The window
---------------------------------------------------------------------------

local ICON = { pickup = "icon_quest_pickup", work = "icon_kill_target", handin = "icon_turn_in", tip = "Tip",
    travel = "icon_travel", done = "icon_quest_complete", waiting = "icon_timer" }
local Refresh -- the route's refresh (Window.lua's), which redraws the guide too

local function Show(stage, follow)
    db.guide.follow = follow and true or nil
    db.guide.stage = (not follow) and stage.key or nil
    shownStage = stage
    guide.list.scroll:SetVerticalScroll(0)
    guide.lastActive = nil
    Refresh()
end

-- One row of the list, made the first time it is needed.
local function Row(k)
    local rows = guide.list.rows
    if rows[k] then return rows[k] end
    local row = CreateFrame("Button", nil, guide.list.child)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row.bg = Nine(row, "row_normal", 12, "BACKGROUND")
    row.ring = Tex(row, "step_ring_idle", "ARTWORK", 30)
    row.ring:SetPoint("LEFT", 10, 0)
    row.num = Text(row, "GameFontHighlight", TEXT)
    row.num:SetPoint("CENTER", row.ring, "CENTER", 0, 0)
    row.num:SetJustifyH("CENTER")
    row.icon = Tex(row, "icon_quest_pickup", "ARTWORK", 28)
    row.icon:SetPoint("LEFT", 44, 0)
    row.title = Text(row, "GameFontHighlight", TEXT, 14)
    row.title:SetWordWrap(false)
    row.pin = Tex(row, "icon_map_pin", "ARTWORK", 14)
    row.sub = Text(row, "GameFontHighlightSmall", DIM)
    row.sub:SetWordWrap(false)
    row.nav = Tex(row, "icon_waypoint", "ARTWORK", 18)
    row.dist = Text(row, "GameFontHighlightSmall", TEXT)
    row.dist:SetJustifyH("RIGHT")
    row.count = CreateFrame("Frame", nil, row)
    row.count:SetSize(64, 22)
    row.count:SetPoint("RIGHT", -12, 0)
    row.count.pill = Pill(row.count, "PillLine", 22)
    row.count.text = Text(row.count, "GameFontHighlightSmall", TEXT)
    row.count.text:SetPoint("CENTER")
    row.count.text:SetJustifyH("CENTER")
    row:SetScript("OnEnter", function(self)
        if not self.active then self.bg:SetBase("row_hover") end
        local step = self.step
        if not (step and GameTooltip and GameTooltip.SetOwner) then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        local rewards = step.task.quest and step.task.quest.rewards
        if rewards and rewards[1] and GameTooltip.SetHyperlink then
            local best = rewards[1]
            for _, r in ipairs(rewards) do if r[3] > best[3] then best = r end end
            pcall(GameTooltip.SetHyperlink, GameTooltip, "item:" .. best[1])
        else
            GameTooltip:AddLine(step.title, 1, 0.82, 0, true)
        end
        if step.task.id then
            for _, line in ipairs(ObjectiveLines(step.task)) do GameTooltip:AddLine(line, 1, 1, 1, true) end
            GameTooltip:AddLine("Click: the arrow leads here first (again: the route leads). Right-click: only a map pin.",
                0.6, 0.6, 0.6, true)
        else
            GameTooltip:AddLine("Click to tick it off. Right-click: a map pin to it.", 0.6, 0.6, 0.6, true)
        end
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function(self)
        self.bg:SetBase(self.base or "row_normal")
        Untip()
    end)
    row:SetScript("OnClick", function(self, button)
        local step = self.step
        if not step then return end
        local place = step.place
        if button == "RightButton" then
            if place then I.PinAt(place.map, place.zone, place.x, place.y, place.title) else Print("No map location known for this step.") end
            return
        end
        if not step.task.id then -- a tip: ticked by hand
            local key = TaskKey(shownStage, step.i)
            db.tasks[key] = (not db.tasks[key]) or nil
        elseif step.waiting then
            return
        elseif db.focus == step.task.id then
            db.focus = nil
            if ns.PinArrow then ns.PinArrow(nil) end
            Print("The arrow follows the route again.")
        else
            db.focus = step.task.id
            if place then I.PinAt(place.map, place.zone, place.x, place.y, place.title) end
        end
        Refresh()
    end)
    rows[k] = row
    return row
end

-- Draws one step into its row; returns the row's height.
local function Paint(row, k, step, active, width)
    row.step, row.active = step, active
    local two = (step.place and step.place.x) or step.sub
    local h = two and ROW_TWO or ROW_ONE
    row:SetSize(width, h)
    row.title:SetWordWrap(not two) -- a tip with no place may be long: it takes the lines it needs
    local faded = step.done or step.waiting
    row.base = (active and "row_active") or (step.done and "row_complete") or (step.waiting and "row_upcoming") or "row_normal"
    row.bg:SetBase(row.base)
    local tc = active and GOLDT or (faded and FAINT or TEXT)
    row.num:SetText(tostring(k))
    row.num:SetTextColor(tc[1], tc[2], tc[3])
    row.ring:SetTexture(Path((active and "step_ring_current") or (step.done and "step_ring_done") or "step_ring_idle"))
    row.icon:SetTexture(Path((step.done and ICON.done) or (step.waiting and ICON.waiting) or ICON[step.kind] or ICON.tip))
    row.icon:SetVertexColor(1, 1, 1, faded and 0.75 or 1)
    row.title:SetText(step.title)
    row.title:SetTextColor(tc[1], tc[2], tc[3])

    -- The right column: how far, or how many of the objective.
    local right = 0
    local dist = (not faded and step.place) and DistText(Yards(step.place)) or nil
    row.count:SetShown(step.need ~= nil)
    if step.need then
        row.count.text:SetText(string.format("%d / %d", step.have, step.need))
        local w = math.max(56, (row.count.text:GetStringWidth() or 30) + 24)
        row.count:SetWidth(w)
        row.count.pill:Color(0.75, 0.75, 0.75, 0.9)
        right = w + 18
    end
    row.nav:SetShown(dist ~= nil and not step.need)
    row.dist:SetShown(dist ~= nil and not step.need)
    if dist and not step.need then
        row.dist:SetText(dist)
        row.dist:ClearAllPoints()
        row.dist:SetPoint("RIGHT", -16, 0)
        row.nav:ClearAllPoints()
        row.nav:SetPoint("RIGHT", row.dist, "LEFT", -8, 0)
        row.nav:SetVertexColor(1, 1, 1, active and 1 or 0.7)
        right = (row.dist:GetStringWidth() or 40) + 16 + 32
    end
    row.distShown = dist ~= nil and not step.need

    local textW = width - 82 - right - 8
    row.title:SetWidth(textW)
    row.title:ClearAllPoints()
    row.sub:ClearAllPoints()
    if two then
        row.title:SetPoint("TOPLEFT", 82, -8)
        local place, sub = step.place, step.sub
        local line = sub or ""
        if place and place.x then
            line = string.format("%s (%.1f, %.1f)", place.zone or "", place.x, place.y)
            if sub then line = sub .. "  |cff8c8c8c·  " .. line .. "|r" end
        end
        row.pin:SetShown(place ~= nil and place.x ~= nil and not sub)
        row.sub:SetPoint("TOPLEFT", (row.pin:IsShown() and 98) or 82, -28)
        row.pin:ClearAllPoints()
        row.pin:SetPoint("TOPLEFT", 82, -28)
        row.sub:SetWidth(textW - 16)
        row.sub:SetText(line)
        row.sub:SetTextColor(faded and FAINT[1] or DIM[1], faded and FAINT[2] or DIM[2], faded and FAINT[3] or DIM[3])
        row.sub:Show()
    else
        row.title:SetPoint("LEFT", 82, 0)
        row.pin:Hide()
        row.sub:Hide()
        h = math.max(ROW_ONE, math.ceil(row.title:GetStringHeight() or 14) + 18)
        row:SetHeight(h)
    end
    row:Show()
    return h
end

-- The stage menu under the level button: every stage, by level.
local function BuildMenu(f)
    local m = CreateFrame("Frame", nil, f)
    m:SetSize(300, 320)
    m:SetPoint("TOPRIGHT", f.levelButton, "BOTTOMRIGHT", 0, -4)
    m:SetFrameStrata("DIALOG")
    m.fill = Tex(m, "panel_fill", "BACKGROUND")
    m.fill:SetAllPoints()
    m.frame = Nine(m, "button_normal", 10, "BORDER")
    m:EnableMouse(true)
    local sf, child = T.Scroll(m)
    sf:SetPoint("TOPLEFT", 8, -8)
    sf:SetPoint("BOTTOMRIGHT", -8, 8)
    child:SetWidth(284)
    m.rows = {}
    for i, stage in ipairs(ns.Stages) do
        local r = CreateFrame("Button", nil, child)
        r:SetSize(280, 22)
        r:SetPoint("TOPLEFT", 0, -(i - 1) * 22)
        r.bg = Tex(r, "Pill", "BACKGROUND")
        r.bg:SetAllPoints()
        r.bg:SetVertexColor(1, 0.8, 0.3, 0)
        r.range = Text(r, "GameFontHighlightSmall", DIM)
        r.range:SetPoint("LEFT", 8, 0)
        r.range:SetText(RangeText(stage))
        r.name = Text(r, "GameFontHighlightSmall", TEXT)
        r.name:SetPoint("LEFT", 62, 0)
        r.name:SetWidth(210)
        r.name:SetWordWrap(false)
        r.name:SetText(StageName(stage))
        r:SetScript("OnEnter", function(self) self.bg:SetVertexColor(1, 0.8, 0.3, 0.18) end)
        r:SetScript("OnLeave", function(self) self.bg:SetVertexColor(1, 0.8, 0.3, 0) end)
        r:SetScript("OnClick", function()
            m:Hide()
            Show(stage, stage == Recommend())
        end)
        r.stage = stage
        m.rows[i] = r
    end
    child:SetHeight(#ns.Stages * 22)
    m:Hide()
    m:SetScript("OnShow", function(self)
        local level = Level()
        for i, r in ipairs(self.rows) do
            local st = Status(r.stage, level)
            local c = (r.stage == shownStage and GOLDT) or ((st == "done" or st == "out") and FAINT) or TEXT
            r.name:SetTextColor(c[1], c[2], c[3])
            if r.stage == shownStage then sf:SetVerticalScroll(math.max(0, (i - 6) * 22)) end
        end
        sf:Sync()
    end)
    return m
end

-- The gear's menu: the switches the classic window keeps in its bottom bar.
local function BuildSettings(f)
    local m = CreateFrame("Frame", nil, f)
    m:SetSize(210, 5 * 26 + 16)
    m:SetPoint("TOPRIGHT", f.gear, "BOTTOMRIGHT", 0, -4)
    m:SetFrameStrata("DIALOG")
    m.fill = Tex(m, "panel_fill", "BACKGROUND")
    m.fill:SetAllPoints()
    m.frame = Nine(m, "button_normal", 10, "BORDER")
    m:EnableMouse(true)
    m.items = {}
    local items = {
        { function() return db.arrow ~= false and "Arrow: on" or "Arrow: off" end, function() SlashCmdList.UNDEADROUTE("arrow") end },
        { function() return db.tracker.hidden and "Tracker: off" or "Tracker: on" end, function()
            db.tracker.hidden = (not db.tracker.hidden) or nil
        end },
        { function() return db.stages[shownStage.key] and "Unmark stage" or "Mark stage done" end, function()
            db.stages[shownStage.key] = (not db.stages[shownStage.key]) or nil
        end },
        { function() return "Look: " .. Theme().name end, function()
            -- The next look in the list; the guide is built again in it.
            local at = 1
            for i, t in ipairs(THEMES) do if t == Theme() then at = i end end
            db.guide.theme = THEMES[at % #THEMES + 1].key
            ns.RebuildGuide()
        end },
        { function() return "Classic window" end, function() f:Hide() ns.Toggle() end },
    }
    for i, item in ipairs(items) do
        local r = CreateFrame("Button", nil, m)
        r:SetSize(194, 24)
        r:SetPoint("TOPLEFT", 8, -8 - (i - 1) * 26)
        r.bg = Tex(r, "Pill", "BACKGROUND")
        r.bg:SetAllPoints()
        r.bg:SetVertexColor(1, 0.8, 0.3, 0)
        r.text = Text(r, "GameFontHighlightSmall", TEXT)
        r.text:SetPoint("LEFT", 10, 0)
        r:SetScript("OnEnter", function(self) self.bg:SetVertexColor(1, 0.8, 0.3, 0.18) end)
        r:SetScript("OnLeave", function(self) self.bg:SetVertexColor(1, 0.8, 0.3, 0) end)
        r:SetScript("OnClick", function()
            item[2]()
            Refresh()
            for _, it in ipairs(m.items) do it.text:SetText(it.label()) end
        end)
        r.label = item[1]
        m.items[i] = r
    end
    m:SetScript("OnShow", function(self) for _, it in ipairs(self.items) do it.text:SetText(it.label()) end end)
    m:Hide()
    return m
end

local function Build()
    local f = CreateFrame("Frame", "UndeadRouteGuide", UIParent)
    guide = f
    f:SetSize(W, H)
    f:SetFrameStrata("HIGH")
    f:SetScale(db.guide.scale or 1)
    f:ClearAllPoints()
    if db.guide.point then
        f:SetPoint(db.guide.point, UIParent, db.guide.rel or db.guide.point, db.guide.x or 0, db.guide.y or 0)
    else
        f:SetPoint("CENTER", UIParent, "CENTER", 0, 20)
    end
    f:SetMovable(true)
    f:EnableMouse(true)
    f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, rel, x, y = self:GetPoint(1)
        db.guide.point, db.guide.rel, db.guide.x, db.guide.y = point, rel, x, y
    end)
    tinsert(UISpecialFrames, "UndeadRouteGuide")

    -- The window: its fill, the header's art, then the gold frame over the edges.
    f.fill = Tex(f, "panel_fill", "BACKGROUND")
    f.fill:SetPoint("TOPLEFT", EDGE, -EDGE)
    f.fill:SetPoint("BOTTOMRIGHT", -EDGE, EDGE)
    f.footArt = Tex(f, "footer_backdrop", "BORDER")
    f.footArt:SetPoint("BOTTOMLEFT", EDGE, EDGE)
    f.footArt:SetPoint("BOTTOMRIGHT", -EDGE, EDGE)
    f.footArt:SetHeight(FOOT_H - EDGE + 2)
    f.headArt = Tex(f, "header_backdrop", "BORDER")
    f.headArt:SetPoint("TOPLEFT", EDGE, -EDGE)
    f.headArt:SetPoint("TOPRIGHT", -EDGE, -EDGE)
    f.headArt:SetHeight(HEAD_H - EDGE)
    f.headFade = f:CreateTexture(nil, "ARTWORK")
    f.headFade:SetTexture(T.WHITE)
    f.headFade:SetPoint("BOTTOMLEFT", f.headArt, "BOTTOMLEFT")
    f.headFade:SetPoint("BOTTOMRIGHT", f.headArt, "BOTTOMRIGHT")
    f.headFade:SetHeight(30)
    local fr, fg, fb = unpack(Theme().fade)
    if CreateColor then
        f.headFade:SetGradient("VERTICAL", CreateColor(fr, fg, fb, 0.9), CreateColor(fr, fg, fb, 0))
    else
        f.headFade:SetVertexColor(fr, fg, fb, 0.4)
    end
    -- The gold line under the header.
    f.divider = Tex(f, "divider_gold", "ARTWORK")
    f.divider:SetPoint("TOPLEFT", EDGE + 8, -HEAD_H + 3)
    f.divider:SetPoint("TOPRIGHT", -EDGE - 8, -HEAD_H + 3)
    f.divider:SetHeight(6)
    f.frame = Nine(f, "frame_ornate", 32, "OVERLAY")

    -- The header: the pennant, the stage, what kind it is, and the controls on the right.
    local banner = CreateFrame("Frame", nil, f)
    banner:SetSize(68, 76)
    banner:SetPoint("TOPLEFT", 10, 6)
    banner:SetFrameLevel((f:GetFrameLevel() or 0) + 5)
    -- Classic: the Horde's own banner, or the Alliance's plain pennant with the addon's icon on it. The other looks:
    -- their emblem.
    local horde = (ns.Faction or "Horde") ~= "Alliance"
    local themed = Theme().key ~= "Classic"
    banner.art = Tex(banner, (themed and "emblem") or (horde and "banner_horde") or "Banner", "ARTWORK")
    banner.art:SetAllPoints()
    if themed then
        banner:SetSize(66, 66)
        banner:SetPoint("TOPLEFT", 10, 0)
    elseif horde then
        banner.art:SetTexCoord(0, 1, 44 / 256, 176 / 256) -- the file's empty space above and below cut off
    else
        banner.icon = banner:CreateTexture(nil, "OVERLAY")
        banner.icon:SetTexture("Interface\\AddOns\\UndeadRoute\\Media\\Icon")
        banner:SetSize(40, 80)
        banner.icon:SetSize(30, 30)
        banner.icon:SetPoint("TOP", 0, -20)
    end
    f.banner = banner

    f.title = f:CreateFontString(nil, "OVERLAY")
    f.title:SetFont(TITLE_FONT, 24, "")
    f.title:SetTextColor(0.96, 0.90, 0.78)
    f.title:SetPoint("TOPLEFT", 82, -20)
    f.title:SetJustifyH("LEFT")
    f.title:SetWordWrap(false)
    f.sub = Text(f, "GameFontHighlight", DIM, 14)
    f.sub:SetPoint("TOPLEFT", 82, -54)
    f.sub:SetText("Leveling Guide")
    f.kind = CreateFrame("Frame", nil, f)
    f.kind:SetHeight(22)
    f.kind:SetPoint("LEFT", f.sub, "RIGHT", 12, 0)
    f.kind.pill = Pill(f.kind, "PillLine", 22)
    f.kind.text = Text(f.kind, "GameFontHighlightSmall", TEXT)
    f.kind.text:SetPoint("CENTER")
    f.kind.text:SetJustifyH("CENTER")

    f.gear = Button(f, 36, 36, "icon_settings", nil, function()
        f.menu:Hide()
        f.settings:SetShown(not f.settings:IsShown())
    end)
    f.gear:SetPoint("TOPRIGHT", -22, -24)
    f.gear.tipTitle, f.gear.tip = "Settings", "The arrow, the tracker, marking the stage done, and the classic window."
    f.tack = Button(f, 36, 36, "icon_pin", nil, function()
        local stage = shownStage
        if stage.x then
            I.PinAt(nil, stage.zone, stage.x, stage.y, stage.hub, true)
        else
            Print(StageName(stage) .. ": no map location known. " .. (stage.travel or ""))
        end
    end)
    f.tack:SetPoint("RIGHT", f.gear, "LEFT", -8, 0)
    f.tack.tipTitle, f.tack.tip = "Pin the hub", "Puts a map pin on this stage's quest hub and points the arrow there."
    f.levelButton = Button(f, 100, 36, nil, "", function()
        f.settings:Hide()
        f.menu:SetShown(not f.menu:IsShown())
    end)
    f.levelButton:SetPoint("RIGHT", f.tack, "LEFT", -12, 0)
    f.levelButton.label:ClearAllPoints()
    f.levelButton.label:SetPoint("LEFT", 12, 0)
    f.levelButton.chevron = Tex(f.levelButton, "chevron_down", "ARTWORK", 22)
    f.levelButton.chevron:SetPoint("RIGHT", -6, 0)
    f.levelButton.tipTitle, f.levelButton.tip = "Stage", "Pick another stage of the route to look at."

    -- Progress: "Step 3 of 12", a segment per step, and how much is done.
    f.stepText = Text(f, "GameFontHighlight", TEXT, 15)
    f.stepText:SetPoint("TOPLEFT", 26, -HEAD_H - 12)
    f.percent = Text(f, "GameFontHighlight", TEXT, 15)
    f.percent:SetPoint("TOPRIGHT", -26, -HEAD_H - 12)
    f.percent:SetJustifyH("RIGHT")
    f.segments = {}
    f.bar = CreateFrame("Frame", nil, f) -- the filled part, when there are too many steps for a segment each
    f.bar.pill = Pill(f.bar, "progress_filled", SEG_H, "OVERLAY", BAR_CAP)
    f.bar:Hide()

    -- The list.
    local list = CreateFrame("Frame", nil, f)
    list:SetPoint("TOPLEFT", EDGE + 4, -(HEAD_H + PROGRESS_H))
    list:SetPoint("BOTTOMRIGHT", -EDGE - 4, FOOT_H)
    local sf, child = T.Scroll(list)
    sf:SetAllPoints()
    list.scroll, list.child, list.rows = sf, child, {}
    list.width = W - 2 * (EDGE + 4) - 2 * LIST_PAD - 6
    child:SetWidth(list.width + 2 * LIST_PAD)
    f.list = list

    -- The footer.
    f.mapButton = Button(f, 136, 38, "icon_map_scroll", "Show on Map", function()
        local step = f.activeStep
        local place = step and step.place
        if place and place.x then I.PinAt(place.map, place.zone, place.x, place.y, place.title)
        else Print("No map location known for this step.") end
    end)
    f.mapButton:SetPoint("BOTTOMLEFT", 24, 16)
    f.mapButton.tip = "Puts a map pin on the step you are on."
    f.routeButton = Button(f, 96, 38, "icon_route", "Route", function() Show(Recommend(), true) end)
    f.routeButton:SetPoint("LEFT", f.mapButton, "RIGHT", 10, 0)
    f.routeButton.tip = "Goes back to the stage the route recommends for your level and quest log, and follows it."
    f.questButton = Button(f, 116, 38, "icon_quest_log", "Quests", function() f:Hide() ns.Toggle() end)
    f.questButton:SetPoint("LEFT", f.routeButton, "RIGHT", 10, 0)
    f.questButton.tip = "Opens the classic window: every stage, the batch you are on, the rules of thumb."

    -- Follow the route: the switch. On, the guide moves on to the next stage by itself.
    local sw = CreateFrame("Button", nil, f)
    sw:SetSize(60, 22)
    sw:SetPoint("BOTTOMRIGHT", -24, 24)
    sw.art = Tex(sw, "toggle_on", "ARTWORK")
    sw.art:SetAllPoints()
    sw.art:SetTexCoord(0.03, 0.97, 0.2, 0.8) -- the switch without the file's empty margin
    sw:SetScript("OnClick", function()
        if db.guide.follow then Show(shownStage, false) else Show(Recommend(), true) end
    end)
    sw:SetScript("OnEnter", function(self)
        Tip(self, "Auto advance", "On: the guide follows the route and moves on to the next stage by itself. "
            .. "Picking a stage in the level menu turns it off.")
    end)
    sw:SetScript("OnLeave", Untip)
    f.switch = sw
    f.switchLabel = Text(f, "GameFontHighlight", TEXT, 13)
    f.switchLabel:SetPoint("RIGHT", sw, "LEFT", -8, 0)
    f.switchLabel:SetText("Auto Advance")

    f.menu = BuildMenu(f)
    f.settings = BuildSettings(f)

    -- The distances count down as you walk, without a full refresh.
    local wait = 0
    f:SetScript("OnUpdate", function(self, elapsed)
        wait = wait - elapsed
        if wait > 0 then return end
        wait = 0.5
        for _, row in ipairs(self.list.rows) do
            if row:IsShown() and row.distShown and row.step then
                local d = DistText(Yards(row.step.place))
                if d then row.dist:SetText(d) end
            end
        end
    end)
    f:SetScript("OnHide", function(self)
        self.menu:Hide()
        self.settings:Hide()
        Refresh()
    end)
    f:Hide()
end

local function PaintProgress(f, steps, active)
    local n = #steps
    local done = 0
    for _, s in ipairs(steps) do if s.done then done = done + 1 end end
    f.stepText:SetText(n > 0 and string.format("Step %d of %d", active or n, n) or "No steps")
    f.percent:SetText(n > 0 and string.format("%d%%", math.floor(100 * done / n + 0.5)) or "")
    local left = 26 + (f.stepText:GetStringWidth() or 90) + 18
    local right = 26 + math.max(44, f.percent:GetStringWidth() or 40) + 14
    local avail = W - left - right
    -- A segment a step while they fit; else one bar.
    local count = (n > 0 and avail / n >= 12) and n or 1
    local gap = count > 1 and 3 or 0
    local segW = (avail - gap * (count - 1)) / count
    for k = 1, math.max(count, #f.segments) do
        local seg = f.segments[k]
        if k <= count then
            if not seg then
                seg = CreateFrame("Frame", nil, f)
                seg.pill = Pill(seg, "progress_empty", SEG_H, nil, BAR_CAP)
                f.segments[k] = seg
            end
            seg:SetSize(segW, SEG_H)
            seg:ClearAllPoints()
            seg:SetPoint("TOPLEFT", left + (k - 1) * (segW + gap), -HEAD_H - 17)
            seg:Show()
            local lit = count > 1 and (k == active or steps[k].done)
            seg.pill:SetFile(lit and "progress_filled" or "progress_empty")
            seg.pill:Color(1, 1, 1, (count > 1 and steps[k].done and k ~= active) and 0.75 or 1)
        elseif seg then
            seg:Hide()
        end
    end
    -- One bar: its filled part over the track.
    if count == 1 and n > 0 then
        f.bar:SetSize(math.max(SEG_H, avail * done / n), SEG_H)
        f.bar:ClearAllPoints()
        f.bar:SetPoint("TOPLEFT", left, -HEAD_H - 17)
        f.bar:SetShown(done > 0)
    else
        f.bar:Hide()
    end
end

local function RefreshGuide()
    if not (guide and guide:IsShown()) then return end
    local f, level = guide, Level()
    local rec = Recommend()
    if db.guide.follow or not shownStage then shownStage = rec end
    local stage = shownStage

    -- Header.
    local kind = stage.kind == "class" and { (I.CLASS.name or "Class") .. " quests", T.PINK }
        or KIND[stage.kind] or KIND.zone
    if stage.kind == "dungeon" or stage.kind == "class" or stage.kind == "city" then
        f.title:SetText(StageName(stage))
    else
        f.title:SetText(stage.zone .. "  |cffc8a060»|r  " .. stage.hub)
    end
    -- As big as fits beside the controls: a long zone and hub take a smaller size.
    local maxTitle = W - 82 - 22 - 36 - 8 - 36 - 12 - 100 - 14
    for size = 24, 15, -1 do
        f.title:SetFont(TITLE_FONT, size, "")
        if (f.title:GetStringWidth() or 0) <= maxTitle then break end
    end
    f.title:SetWidth(maxTitle)
    f.kind.text:SetText(kind[1])
    f.kind.text:SetTextColor(kind[2][1], kind[2][2], kind[2][3])
    f.kind.pill:Color(kind[2][1], kind[2][2], kind[2][3], 0.9)
    f.kind:SetWidth((f.kind.text:GetStringWidth() or 60) + 28)
    local range = RangeText(stage)
    f.levelButton.label:SetText(range ~= "" and ("Lv " .. range:gsub("%-", " - ")) or "Stages")

    -- Steps.
    local steps = Steps(stage, level)
    local active = Active(steps, stage)
    f.activeStep = active and steps[active] or nil
    PaintProgress(f, steps, active)

    local list, y = f.list, LIST_PAD
    local activeTop, activeH
    for k, step in ipairs(steps) do
        local row = Row(k)
        local h = Paint(row, k, step, k == active, list.width)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", LIST_PAD, -y)
        if k == active then activeTop, activeH = y, h end
        y = y + h + ROW_GAP
    end
    for k = #steps + 1, #list.rows do list.rows[k]:Hide() end
    list.child:SetHeight(y + LIST_PAD)
    list.scroll:Sync()
    -- A new step to be on: scroll it into view, a row above it showing.
    local key = active and (stage.key .. ":" .. active)
    if key ~= f.lastActive and activeTop then
        f.lastActive = key
        local view = list.scroll:GetHeight() or 300
        local top = list.scroll:GetVerticalScroll()
        if activeTop < top or activeTop + activeH > top + view then
            local range = math.max(0, y + LIST_PAD - view)
            list.scroll:SetVerticalScroll(math.min(range, math.max(0, activeTop - ROW_ONE - ROW_GAP)))
        end
    end

    -- Footer.
    local ready = #ReadyToHandIn()
    f.questButton.label:SetText(ready > 0 and string.format("Quests |cff59d973(%d)|r", ready) or "Quests")
    local on = db.guide.follow and true or false
    f.switch.art:SetTexture(Path(on and "toggle_on" or "toggle_off"))
end

---------------------------------------------------------------------------
-- For Window.lua and Core.lua
---------------------------------------------------------------------------

ns.onDB[#ns.onDB + 1] = function(saved)
    db = saved
    db.guide = db.guide or { follow = true }
end

ns.RefreshGuide = RefreshGuide

function ns.GuideShown() return guide ~= nil and guide:IsShown() end

function ns.ToggleGuide()
    Refresh = I.Refresh
    if not guide then Build() end
    if guide:IsShown() then
        guide:Hide()
        return
    end
    shownStage = nil
    if not db.guide.follow and db.guide.stage then
        for _, stage in ipairs(ns.Stages) do
            if stage.key == db.guide.stage then shownStage = stage end
        end
    end
    if not shownStage then db.guide.follow = true end
    guide.lastActive = nil
    guide:Show()
    Refresh()
end

-- The guide built again, in the look now picked, where it stood. A frame cannot be thrown away, so the old one is
-- only hidden; this happens when you pick a look, not often enough to matter.
function ns.RebuildGuide()
    if not guide then return end
    local shown = guide:IsShown()
    guide:Hide()
    guide = nil
    if shown then ns.ToggleGuide() end
end
