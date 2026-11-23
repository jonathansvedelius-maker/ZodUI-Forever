local _, ns = ...

-- Undead Route's frames: the widgets, the route window, the tracker and the arrow, and the map pin they set.
-- The route's logic is Route.lua's (taken from ns.I); Core.lua wires these to the events and to /route.

local I, T = ns.I, ns.T
local Print, Plain, Level, InLog, Complete, QuestName = I.Print, I.Plain, I.Level, I.InLog, I.Complete, I.QuestName
local WaitsFor, RewardText, Dist, ClassTag, TaskKey, TaskState = I.WaitsFor, I.RewardText, I.Dist, I.ClassTag, I.TaskKey, I.TaskState
local Status, Recommend, StepPlace, WorldPos, Here, ReadyToHandIn = I.Status, I.Recommend, I.StepPlace, I.WorldPos, I.Here, I.ReadyToHandIn
local CurrentBatch, ObjectiveLines, LOW_SOON, Badges, WaitingBlocker, NextStep = I.CurrentBatch, I.ObjectiveLines, I.LOW_SOON, I.Badges, I.WaitingBlocker, I.NextStep
local QuestsLeft, DungeonValue, RankedDungeons, XPText, Leftovers, ClassQuests = I.QuestsLeft, I.DungeonValue, I.RankedDungeons, I.XPText, I.Leftovers, I.ClassQuests
local OpenTasks, RangeText, StageName, Where, CLASS = I.OpenTasks, I.RangeText, I.StageName, I.Where, I.CLASS

local WIDTH, HEIGHT = 820, 520
local TITLE_H, BANNER_H, BAR_H = 28, 72, 40
local LEFT_W, ROW_H, PAD = 270, 24, 8
local LIST_H = HEIGHT - TITLE_H - BANNER_H - PAD - BAR_H - PAD -- the visible height of the stage list

local db -- the character's saved settings, handed over once they are loaded
ns.onDB[#ns.onDB + 1] = function(saved) db = saved end
local selected -- the stage shown on the right
local nowOpen = false -- the step list shows the NOW batch's quests too (they are folded, being in the box above)
local main, tracker
local Refresh

---------------------------------------------------------------------------
-- Map pin
---------------------------------------------------------------------------

local mapByName

local function MapFor(name)
    if not mapByName then
        mapByName = {}
        if C_Map and C_Map.GetMapInfo and C_Map.GetMapChildrenInfo then
            local root = (C_Map.GetFallbackWorldMapID and C_Map.GetFallbackWorldMapID())
                or (C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player"))
            local info = root and C_Map.GetMapInfo(root)
            while info and info.parentMapID and info.parentMapID > 0 do
                root = info.parentMapID
                info = C_Map.GetMapInfo(root)
            end
            if root then
                for _, m in ipairs(C_Map.GetMapChildrenInfo(root, nil, true) or {}) do
                    if m.name and not mapByName[m.name:lower()] then mapByName[m.name:lower()] = m.mapID end
                end
            end
        end
    end
    return mapByName[name:lower()]
end

-- Pins (x, y) on map `mapId` (or the map named `zone`) and says so.
local function PinAt(mapId, zone, x, y, title, approx)
    local where = string.format("%s%s (%.1f, %.1f)", title, zone and (" in " .. zone) or "", x, y)
    mapId = mapId or (zone and MapFor(zone))
    if not mapId then
        Print(where .. ". That zone was not found on your map, so no pin was set.")
        return
    end
    local pinned = false
    if C_Map and C_Map.CanSetUserWaypointOnMap and C_Map.CanSetUserWaypointOnMap(mapId) and UiMapPoint then
        C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(mapId, x / 100, y / 100))
        if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
            C_SuperTrack.SetSuperTrackedUserWaypoint(true)
        end
        pinned = true
    end
    -- Our arrow goes there first, until you arrive.
    if ns.PinArrow then
        ns.PinArrow({ map = mapId, x = x, y = y, zone = zone, title = title, key = "pin:" .. mapId .. ":" .. x .. ":" .. y })
        pinned = true
    end
    Print((pinned and "Pinned " or "") .. where .. (approx and ". Coordinates are approximate." or "."))
end

local function PinStage(stage)
    if stage.kind == "class" then
        local open = ClassQuests()
        for _, task in ipairs(open) do
            if task.x and not InLog(task.id) then return PinAt(task.map, task.quest.zone, task.x, task.y, task.pinTitle) end
        end
        Print("No class quest to pick up right now.")
    elseif stage.x then
        PinAt(nil, stage.zone, stage.x, stage.y, stage.hub, true)
    else
        Print(StageName(stage) .. ": no map location known. " .. stage.travel)
    end
end

---------------------------------------------------------------------------
-- Widgets
---------------------------------------------------------------------------

function T.Flat(frame, color, alpha, border)
    frame:SetBackdrop({ bgFile = T.WHITE, edgeFile = T.WHITE, edgeSize = 1 })
    frame:SetBackdropColor(color[1], color[2], color[3], alpha or 1)
    local b = border or T.BORDER
    frame:SetBackdropBorderColor(b[1], b[2], b[3], 1)
end

local texts = setmetatable({}, { __mode = "k" }) -- every text made here, with its font's own size

function T.Text(parent, font, color)
    local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
    fs:SetJustifyH("LEFT")
    fs:SetJustifyV("TOP")
    -- Every text in the addon is made here, so one bump enlarges all of it (/route font N).
    local path, size, flags = fs:GetFont()
    local bump = (db and db.font) or 2
    if path and size then texts[fs] = size end
    if path and size and bump ~= 0 then fs:SetFont(path, size + bump, flags) end
    if color then fs:SetTextColor(color[1], color[2], color[3]) end
    -- A refresh writes every line of the window again, and most have not changed: the same text twice is
    -- written once, so the game lays out only what is new.
    local set = fs.SetText
    fs.SetText = function(self, text)
        if self.written ~= text then
            self.written = text
            set(self, text)
        end
    end
    return fs
end

-- /route font N: every text takes the new size at once.
function T.ApplyFont()
    local bump = (db and db.font) or 2
    for fs, base in pairs(texts) do
        local path, _, flags = fs:GetFont()
        if path then fs:SetFont(path, base + bump, flags) end
    end
end

-- Sets a text only when it changes: for lines written many times a second (the arrow's).
function T.Say(fs, text)
    if fs.said ~= text then
        fs.said = text
        fs:SetText(text)
    end
end

-- A button label's colour: the game's yellow on its red buttons (ZodUI's Forever look), else white.
function T.ButtonText()
    return T.gameLook and { 1, 0.82, 0 } or { 1, 1, 1 }
end

function T.Button(parent, label, width, onClick)
    -- With ZodUI's Forever look the game's own red panel button, as ZodUI's; else the flat one.
    local b, game
    if T.gameLook then
        local ok, made = pcall(CreateFrame, "Button", nil, parent, "UIPanelButtonTemplate")
        if ok and made then b, game = made, true end
    end
    b = b or CreateFrame("Button", nil, parent, "BackdropTemplate")
    b.game = game
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
        -- b.tip (and b.tipTitle): what the button does, on hover.
        if self.tip and GameTooltip and GameTooltip.SetOwner then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if self.tipTitle then GameTooltip:AddLine(self.tipTitle, 1, 0.82, 0) end
            GameTooltip:AddLine(self.tip, 0.9, 0.9, 0.9, true)
            GameTooltip:Show()
        end
    end)
    b:SetScript("OnLeave", function(self)
        if not self.game then
            self:SetBackdropColor(T.SURFACE[1], T.SURFACE[2], T.SURFACE[3], 1)
            self:SetBackdropBorderColor(T.BORDER[1], T.BORDER[2], T.BORDER[3], 1)
        end
        if self.tip and GameTooltip and GameTooltip.Hide then GameTooltip:Hide() end
        if self.onLeave then self.onLeave(self) end
    end)
    b:SetScript("OnClick", onClick)
    return b
end

-- A mouse-wheel scroll area; returns the frame and the child to fill.
-- With ZodUI installed the window takes its look: its palette (the accent you chose there
-- included), its text size and its flat panels. Runs at login, before any frame is built.
-- Returns whether it did.
-- A window's close button; ZodUI's (T.Adopt) is the game's red X in its Forever look.
function T.Close(parent, onClick)
    local b = T.Button(parent, "x", 22, onClick)
    b:SetHeight(20)
    return b
end

-- A big window's background; ZodUI's (T.Adopt) draws the game's frame in its Look.
function T.Window(frame, color, alpha, border) T.Flat(frame, color, alpha, border) return false end

function T.Adopt()
    local api = type(ZodUI) == "table" and type(ZodUI.api) == "table" and ZodUI.api
    local Z = api and (api.level or 0) >= 1 and api.Theme
    if type(Z) ~= "table" then return false end
    for _, k in ipairs({ "GOLD", "WINDOW", "SURFACE", "HOVER", "BORDER", "DIM", "MUTED" }) do
        if type(Z[k]) == "table" then T[k] = Z[k] end
    end
    if type(Z.Flat) == "function" then T.Flat = Z.Flat end
    if type(Z.Window) == "function" then T.Window = Z.Window end
    if type(Z.Close) == "function" then T.Close = Z.Close end
    T.gameLook = Z.look == "game" or nil -- the red buttons of ZodUI's Forever look
    if type(Z.Text) == "function" then T.Text = Z.Text end
    T.zod = true
    return true
end

function T.Scroll(parent)
    local sf = CreateFrame("ScrollFrame", nil, parent)
    local child = CreateFrame("Frame", nil, sf)
    child:SetSize(10, 10)
    sf:SetScrollChild(child)
    -- A thin gold thumb on the right edge says there is more below and how far down you are;
    -- it hides when everything fits. The same as ZodUI's.
    sf.thumb = sf:CreateTexture(nil, "OVERLAY")
    sf.thumb:SetTexture(T.WHITE)
    sf.thumb:SetVertexColor(T.GOLD[1], T.GOLD[2], T.GOLD[3], 0.6)
    sf.thumb:SetWidth(3)
    sf.thumb:Hide()
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
    end)
    -- Scrolled by the wheel or by the code (a stage chosen in the list), or the content grew: the thumb follows.
    sf:SetScript("OnVerticalScroll", function(self) self:Sync() end)
    sf:SetScript("OnScrollRangeChanged", function(self) self:Sync() end)
    sf:SetScript("OnShow", function(self) self:Sync() end)
    return sf, child
end

local function SavePosition(frame, store)
    local point, _, rel, x, y = frame:GetPoint(1)
    store.point, store.rel, store.x, store.y = point, rel, x, y
end

local function RestorePosition(frame, store, point, x, y)
    frame:ClearAllPoints()
    if store.point then
        frame:SetPoint(store.point, UIParent, store.rel or store.point, store.x or 0, store.y or 0)
    else
        frame:SetPoint(point, UIParent, point, x, y)
    end
end

-- A grip in the bottom-right corner: drag it to make the frame bigger or smaller, a double-click puts it
-- back to its normal size. It changes the scale, so the layout stays, and the top-left corner stays put.
-- The same as ZodUI's T.ScaleGrip. store gets .scale and the new place.
local GRIP = "Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-"
local function ScaleGrip(frame, store, min, max)
    local g = CreateFrame("Button", nil, frame)
    g:SetSize(12, 12)
    g:SetPoint("BOTTOMRIGHT", -1, 1)
    g:SetFrameLevel((frame:GetFrameLevel() or 0) + 10)
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
        store.scale = math.abs(scale - 1) > 0.005 and scale or nil
        store.point, store.rel, store.x, store.y = "TOPLEFT", "BOTTOMLEFT", left / scale, top / scale
    end
    g.Apply = Apply
    g:SetScript("OnEnter", function(self)
        self.tex:SetTexture(GRIP .. "Highlight")
        if GameTooltip and GameTooltip.SetOwner then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine("Size", 1, 0.82, 0)
            GameTooltip:AddLine("Drag to make it bigger or smaller. A double-click puts it back to normal.", 0.9, 0.9, 0.9, true)
            GameTooltip:Show()
        end
    end)
    g:SetScript("OnLeave", function(self)
        self.tex:SetTexture(GRIP .. "Up")
        if GameTooltip and GameTooltip.Hide then GameTooltip:Hide() end
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
            local scale = math.min(max, math.max(min, (cx - from) / width))
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

local function MakeMovable(frame, store)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:SetClampedToScreen(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SavePosition(self, store)
    end)
end

---------------------------------------------------------------------------
-- Main window
---------------------------------------------------------------------------

local SOURCE = {
    classic = "Quest names are from Classic. If one is missing in Forever, take the quests the game's map marks with a yellow ! near the hub.",
    new = "New in Forever: no quest-by-quest route exists yet. Pin the hub, then take the quests the game's map marks with a yellow !.",
    mixed = "Classic quest names plus new Forever content. For the new parts, take the quests the game's map marks with a yellow ! near the hub.",
    data = "Quests and rewards come from Undead Route's own Forever quest list. They tick off by themselves.",
    newdata = "New in Forever. Quests come from Undead Route's own Forever quest list, which may not have them all yet.",
}

-- What to do with a quest of the batch: pick it up (yellow), do it (blue), hand it in (green), or wait.
local BATCH_COLOR = setmetatable({ pickup = { 1, 0.85, 0.25 }, work = { 0.45, 0.72, 1 }, handin = { 0.35, 0.85, 0.45 } },
    { __index = function(_, k) if k == "waiting" then return T.DIM end end }) -- DIM is ZodUI's once adopted
local BATCH_VERB = { pickup = "Pick up", work = "Do", handin = "Hand in", waiting = "Later" }
local Hex = T.Hex

local STATE_COLOR = { ["do"] = { 1, 1, 1 }, inlog = { 1, 1, 1 }, done = T.FAINT, low = T.FAINT, closed = T.FAINT, later = T.DIM,
    locked = T.DIM, skipped = T.FAINT }
local STATE_TAG = {
    low = "  |cff999999(low XP: skip)|r", later = "  |cff999999(later)|r", inlog = "  |cff59d973(in your log)|r",
    closed = "  |cff999999(no longer offered)|r", skipped = "  |cff999999(skipped)|r",
}

-- A step's text as shown in the detail panel.
local function TaskText(stage, task, state, level)
    local q = task.quest
    if not q then return task.t .. (STATE_TAG[state] or "") end
    local tag = STATE_TAG[state] or ""
    if state == "later" then
        tag = string.format("  |cff999999(from level %d)|r", task.req or level)
    elseif state == "locked" then
        local first = WaitsFor(q)
        tag = "  |cff999999(after " .. (first or "the quest before it") .. ")|r"
    end
    if q.classic then tag = tag .. "  |cff999999(Classic)|r" end
    if (state == "do" or state == "inlog") and task.lv and level >= task.lv + LOW_SOON then
        tag = tag .. "  |cffe6cc8clow XP soon|r"
    end
    local head = QuestName(q) .. tag
    local rewards = RewardText(q.rewards)
    if rewards ~= "" then head = head .. "  " .. rewards end
    -- A zone quest that is finished with needs one line only.
    if state == "skipped" or (task.lv and (state == "done" or state == "closed" or state == "low")) then return head end
    local lines = { head }
    local where = Where(q)
    if q.item then where = where .. "  (starts from an item)" end
    if q.inside then where = where .. "  (starts inside or from a drop)" end
    if q.pre then where = where .. "  (has a prerequisite chain: start early)" end
    lines[#lines + 1] = "|cff999999" .. where .. "|r"
    if state ~= "done" then
        if q.objective then lines[#lines + 1] = "|cffbfbfbf" .. q.objective .. "|r" end
        for _, item in ipairs(q.items or {}) do
            lines[#lines + 1] = "|cffe6cc8cNeeds " .. item[1] .. ":|r |cffbfbfbf" .. (item[2] or "") .. "|r"
        end
        -- Where to hand it in, unless that is where you picked it up.
        local t = q.turnin
        if t and t[4] and (t[4] ~= q.zone or not q.x or Dist(t[2], t[3], q.x, q.y) > 3) then
            lines[#lines + 1] = string.format("|cff999999Hand in: %s (%.1f, %.1f)|r", q.turnin[4], q.turnin[2], q.turnin[3])
        end
    end
    return table.concat(lines, "\n")
end

local function BuildList(parent)
    local sf, child = T.Scroll(parent)
    sf:SetPoint("TOPLEFT", PAD, -(TITLE_H + BANNER_H + PAD))
    sf:SetPoint("BOTTOMLEFT", PAD, BAR_H + PAD)
    sf:SetWidth(LEFT_W)
    child:SetSize(LEFT_W, #ns.Stages * ROW_H)
    parent.rows = {}
    for i, stage in ipairs(ns.Stages) do
        local row = CreateFrame("Button", nil, child)
        row:SetSize(LEFT_W, ROW_H)
        row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
        row.bg = row:CreateTexture(nil, "BACKGROUND")
        row.bg:SetAllPoints()
        row.bg:SetTexture(T.WHITE)
        row.marker = row:CreateTexture(nil, "ARTWORK")
        row.marker:SetTexture(T.WHITE)
        row.marker:SetVertexColor(T.GOLD[1], T.GOLD[2], T.GOLD[3])
        row.marker:SetSize(3, 14)
        row.marker:SetPoint("LEFT", 0, 0)
        row.range = T.Text(row, "GameFontHighlightSmall", T.DIM)
        row.range:SetPoint("LEFT", 8, 0)
        row.range:SetWidth(46)
        row.range:SetWordWrap(false)
        -- Levels only: what kind of stage it is stands in the tag on the right.
        row.range:SetText((stage.kind == "class" or stage.kind == "city") and "" or RangeText(stage))
        row.name = T.Text(row, "GameFontHighlightSmall")
        row.name:SetPoint("LEFT", 58, 0)
        row.name:SetWidth(LEFT_W - 58 - 66)
        row.name:SetWordWrap(false)
        row.name:SetText(StageName(stage))
        row.tag = T.Text(row, "GameFontHighlightSmall", T.DIM)
        row.tag:SetPoint("RIGHT", -6, 0)
        row.tick = row:CreateTexture(nil, "ARTWORK")
        row.tick:SetTexture(T.TICK)
        row.tick:SetSize(14, 14)
        row.tick:SetPoint("RIGHT", -6, 0)
        -- Hover repaints this row only (the whole window is not worked out again), and names the stage in full.
        row:SetScript("OnEnter", function(self)
            self.hover = true
            if stage ~= selected then self.bg:SetVertexColor(T.SURFACE[1], T.SURFACE[2], T.SURFACE[3], 0.5) end
            if GameTooltip and GameTooltip.SetOwner then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:AddLine(StageName(stage), 1, 0.82, 0)
                local range = RangeText(stage)
                if range ~= "" then GameTooltip:AddLine("Levels " .. range, 0.9, 0.9, 0.9) end
                local st = Status(stage, Level())
                local said = { done = "Done", now = "Right for your level", soon = "A little ahead of you", out = "Behind you" }
                if said[st] then GameTooltip:AddLine(said[st], 0.7, 0.7, 0.7) end
                GameTooltip:AddLine("Click to open it.", 0.6, 0.6, 0.6)
                GameTooltip:Show()
            end
        end)
        row:SetScript("OnLeave", function(self)
            self.hover = false
            if stage ~= selected then self.bg:SetVertexColor(0, 0, 0, 0) end
            if GameTooltip and GameTooltip.Hide then GameTooltip:Hide() end
        end)
        row:SetScript("OnClick", function()
            selected = stage
            db.window.stage = stage.key -- kept: the window opens on it again until Show recommended
            main.detailScroll:SetVerticalScroll(0)
            Refresh()
        end)
        parent.rows[i] = row
    end
    parent.listScroll = sf
end

local function BuildDetail(parent)
    local holder = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    holder:SetPoint("TOPLEFT", PAD + LEFT_W + PAD, -(TITLE_H + BANNER_H + PAD))
    holder:SetPoint("BOTTOMRIGHT", -PAD, BAR_H + PAD)
    T.Flat(holder, T.SURFACE, 0.35)
    local sf, child = T.Scroll(holder)
    sf:SetPoint("TOPLEFT", 12, -10)
    sf:SetPoint("BOTTOMRIGHT", -12, 10)
    local width = WIDTH - PAD * 3 - LEFT_W - 24 - 8 -- clear of the scroll thumb on the right
    child:SetWidth(width)
    parent.detailScroll, parent.detail, parent.detailWidth = sf, child, width

    child.title = T.Text(child, "GameFontNormalLarge", T.GOLD)
    child.meta = T.Text(child, "GameFontHighlightSmall", T.DIM)
    child.travelHead = T.Text(child, "GameFontNormalSmall", T.GOLD)
    child.travelHead:SetText("GETTING THERE")
    child.travel = T.Text(child, "GameFontHighlightSmall")
    child.stepsHead = T.Text(child, "GameFontNormalSmall", T.GOLD)
    child.note = T.Text(child, "GameFontHighlightSmall", { 0.9, 0.8, 0.55 })
    child.source = T.Text(child, "GameFontHighlightSmall", T.DIM)
    child.rulesHead = T.Text(child, "GameFontNormalSmall", T.GOLD)
    child.rulesHead:SetText("RULES OF THUMB")
    child.rules = T.Text(child, "GameFontHighlightSmall", T.DIM)
    child.rules:SetText("- " .. table.concat(ns.Rules, "\n- "))
    for _, fs in ipairs({ child.title, child.meta, child.travel, child.note, child.source, child.rules }) do
        fs:SetWidth(width)
        fs:SetSpacing(2)
    end
    child.taskRows = {}

    -- The NOW block: the batch to work on, what to do with each of its quests, and the next step.
    local now = CreateFrame("Frame", nil, child, "BackdropTemplate")
    T.Flat(now, T.SURFACE, 1, { T.GOLD[1] * 0.6, T.GOLD[2] * 0.6, T.GOLD[3] * 0.6 })
    now:SetWidth(width)
    now.head = T.Text(now, "GameFontNormalSmall", T.GOLD)
    now.head:SetPoint("TOPLEFT", 10, -8)
    now.head:SetWidth(width - 130)
    now.head:SetWordWrap(false)
    now.count = T.Text(now, "GameFontHighlightSmall", T.DIM)
    now.count:SetPoint("TOPRIGHT", -10, -8)
    now.count:SetJustifyH("RIGHT")
    now.track = now:CreateTexture(nil, "ARTWORK")
    now.track:SetTexture(T.WHITE)
    now.track:SetVertexColor(0, 0, 0, 0.6)
    now.track:SetHeight(4)
    now.fill = now:CreateTexture(nil, "OVERLAY")
    now.fill:SetTexture(T.WHITE)
    now.fill:SetVertexColor(BATCH_COLOR.handin[1], BATCH_COLOR.handin[2], BATCH_COLOR.handin[3])
    now.fill:SetHeight(4)
    now.next = T.Text(now, "GameFontHighlight")
    now.next:SetWidth(width - 20)
    now.nextWhere = T.Text(now, "GameFontHighlightSmall", T.DIM)
    now.nextWhere:SetWidth(width - 20)
    now.rows = {}
    child.now = now

    -- READY TO HAND IN: every finished quest in your log, from any stage, and where it goes.
    local ready = CreateFrame("Frame", nil, child, "BackdropTemplate")
    T.Flat(ready, T.SURFACE, 1, { BATCH_COLOR.handin[1] * 0.6, BATCH_COLOR.handin[2] * 0.6, BATCH_COLOR.handin[3] * 0.6 })
    ready:SetWidth(width)
    ready.head = T.Text(ready, "GameFontNormalSmall", BATCH_COLOR.handin)
    ready.head:SetPoint("TOPLEFT", 10, -8)
    ready.head:SetWidth(width - 20)
    ready.head:SetWordWrap(false)
    ready.rows = {}
    ready:Hide()
    child.ready = ready
end

-- Columns of a NOW line: "1  Pick up", the level, then the quest.
local NOW_VERB_W, NOW_TEXT_X = 74, 104

-- One line of the NOW block: a coloured verb and the quest. A click pins where to go for it.
local function NowRow(now, i)
    local row = now.rows[i]
    if row then return row end
    row = CreateFrame("Button", nil, now)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()
    row.bg:SetTexture(T.WHITE)
    row.bg:SetVertexColor(T.HOVER[1], T.HOVER[2], T.HOVER[3], 0)
    row.verb = T.Text(row, "GameFontNormalSmall")
    row.verb:SetPoint("TOPLEFT", 4, -2)
    row.verb:SetWidth(NOW_VERB_W)
    row.verb:SetWordWrap(false)
    -- `lv` and `index` also let the browser preview's Shift-click cycle the quest's state here.
    row.lv = T.Text(row, "GameFontHighlightSmall", T.DIM)
    row.lv:SetPoint("TOPLEFT", NOW_VERB_W + 6, -2)
    row.lv:SetWidth(22)
    row.text = T.Text(row, "GameFontHighlightSmall")
    row.text:SetPoint("TOPLEFT", NOW_TEXT_X, -2)
    row.text:SetSpacing(2)
    -- The focused line: a bar on its left, like the step list's.
    row.focus = row:CreateTexture(nil, "ARTWORK")
    row.focus:SetTexture(T.WHITE)
    row.focus:SetVertexColor(T.GOLD[1], T.GOLD[2], T.GOLD[3])
    row.focus:SetPoint("TOPLEFT", 0, 0)
    row.focus:SetPoint("BOTTOMLEFT", 0, 0)
    row.focus:SetWidth(2)
    row.focus:Hide()
    local function Paint(self, over)
        local a = (over and not self.offRoute) and 0.8 or (self.focused and 0.45 or 0) -- nothing to click: no hover
        self.bg:SetVertexColor(T.HOVER[1], T.HOVER[2], T.HOVER[3], a)
    end
    row:SetScript("OnEnter", function(self)
        Paint(self, true)
        -- The best reward, as the game shows it, and what the clicks do.
        if not (GameTooltip and GameTooltip.SetOwner) then return end
        local rewards = self.task and self.task.quest and self.task.quest.rewards
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if rewards and rewards[1] and GameTooltip.SetHyperlink then
            local best = rewards[1]
            for _, r in ipairs(rewards) do if r[3] > best[3] then best = r end end
            pcall(GameTooltip.SetHyperlink, GameTooltip, "item:" .. best[1])
        end
        if self.offRoute then
            GameTooltip:AddLine("Not on the route, so no place is known to go to: hand it in where you got it.", 0.6, 0.6, 0.6, true)
        elseif self.jump then
            GameTooltip:AddLine("Click to open the stage it waits for.", 0.6, 0.6, 0.6)
        elseif self.task and self.task.id then
            GameTooltip:AddLine("Click: the arrow leads here first (again: the route leads). Right-click: only a map pin.", 0.6, 0.6, 0.6, true)
        end
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function(self)
        Paint(self, false)
        if GameTooltip then GameTooltip:Hide() end
    end)
    row.Paint = Paint
    -- A click sends the arrow to this quest first (and pins it); a second click lets the route lead again.
    row:SetScript("OnClick", function(self, button)
        -- The "waiting" line opens the stage that holds what the quests wait for.
        if self.jump then
            selected = self.jump
            db.window.stage = self.jump.key
            Refresh()
            return
        end
        local id = self.task and self.task.id
        if not id then return end
        if self.waiting or button == "RightButton" then -- waiting (it cannot lead the arrow) or right-click: pin it only
            local place = self.place
            if place then PinAt(place.map, place.zone, place.x, place.y, place.title) end
            return
        end
        if db.focus == id then
            db.focus = nil
            if ns.PinArrow then ns.PinArrow(nil) end -- the pin the first click put on it goes too
            Print("The arrow follows the route again.")
        else
            db.focus = id
            local place = self.place
            if place then
                PinAt(place.map, place.zone, place.x, place.y, place.title)
            else
                Print("No map location known for this step.")
            end
        end
        Refresh()
    end)
    now.rows[i] = row
    return row
end

-- The Skip button of a quest step shows while the mouse is on the step; Undo stays on a skipped one.
local function UpdateSkip(row)
    local over = row.canSkip and (row:IsMouseOver() or row.skip:IsMouseOver())
    row.skip:SetShown((row.isSkipped or over) and true or false)
end

local function TaskRow(child, i)
    local row = child.taskRows[i]
    if row then return row end
    row = CreateFrame("Button", nil, child)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row.box = CreateFrame("Frame", nil, row, "BackdropTemplate")
    row.box:SetSize(14, 14)
    row.box:SetPoint("TOPLEFT", 0, -2)
    T.Flat(row.box, T.WINDOW)
    row.tick = row.box:CreateTexture(nil, "OVERLAY")
    row.tick:SetTexture(T.TICK)
    row.tick:SetAllPoints()
    -- A bar in the box's place marks the quests of the batch you are on.
    row.mark = row:CreateTexture(nil, "ARTWORK")
    row.mark:SetTexture(T.WHITE)
    row.mark:SetWidth(3)
    row.mark:Hide()
    row.head = T.Text(row, "GameFontNormalSmall")
    row.head:SetPoint("TOPLEFT", 0, -8)
    row.head:SetWidth(main.detailWidth)
    row.head:SetWordWrap(true) -- a long batch heading takes a second line instead of ending in ...
    row.lv = T.Text(row, "GameFontHighlightSmall", T.DIM)
    row.lv:SetPoint("TOPLEFT", 22, -3)
    row.lv:SetWidth(28)
    row.text = T.Text(row, "GameFontHighlightSmall")
    row.text:SetPoint("TOPLEFT", 52, -3)
    row.text:SetWidth(main.detailWidth - 52)
    row.text:SetSpacing(2)
    row.skip = T.Button(row, "Skip", 44, function()
        local task = selected and selected.tasks[row.index]
        if not (task and task.id) then return end
        local key = TaskKey(selected, row.index)
        db.tasks[key] = (not db.tasks[key]) or nil
        Refresh()
    end)
    row.skip:SetHeight(16)
    row.skip.tip = "Skip sets this quest aside, so the route stops waiting for it; Undo brings it back."
    row.skip.onLeave = function() UpdateSkip(row) end
    row.skip:Hide()
    row:SetScript("OnClick", function(self, button)
        local task = selected.tasks[self.index]
        if self.nowHead and button ~= "RightButton" then
            nowOpen = not nowOpen
            Refresh()
            return
        end
        if button == "RightButton" then
            if task.x then
                PinAt(task.map, task.quest and task.quest.zone, task.x, task.y, task.pinTitle or selected.hub)
            else
                Print("No map location known for this step.")
            end
            return
        end
        -- A tip is ticked by hand. A quest ticks itself from the quest log; its Skip button sets it aside.
        if task.id then return end
        local key = TaskKey(selected, self.index)
        db.tasks[key] = (not db.tasks[key]) or nil
        Refresh()
    end)
    -- Hovering a quest shows its Skip button and its best reward's tooltip.
    row:SetScript("OnEnter", function(self)
        UpdateSkip(self)
        local task = selected and selected.tasks[self.index]
        if not (task and GameTooltip and GameTooltip.SetOwner) or self.nowHead then return end
        local rewards = task.quest and task.quest.rewards
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if rewards and rewards[1] and GameTooltip.SetHyperlink then
            local best = rewards[1]
            for _, r in ipairs(rewards) do
                if r[3] > best[3] then best = r end
            end
            pcall(GameTooltip.SetHyperlink, GameTooltip, "item:" .. best[1])
        end
        -- What the clicks do, which otherwise only /route help says.
        GameTooltip:AddLine(task.id and "Ticks itself from your quest log. Right-click: a map pin to it."
            or "Click to tick it off. Right-click: a map pin to it.", 0.6, 0.6, 0.6, true)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function(self)
        UpdateSkip(self)
        if GameTooltip then GameTooltip:Hide() end
    end)
    child.taskRows[i] = row
    return row
end

-- Scrolls the stage list so the selected stage is in view, near the middle.
local function RevealSelected()
    for i, stage in ipairs(ns.Stages) do
        if stage == selected then
            local range = math.max(0, #ns.Stages * ROW_H - LIST_H)
            main.listScroll:SetVerticalScroll(math.min(range, math.max(0, i * ROW_H - LIST_H / 2)))
            return
        end
    end
end

local function BuildMain()
    local f = CreateFrame("Frame", "UndeadRouteFrame", UIParent, "BackdropTemplate")
    main = f
    f:SetSize(WIDTH, HEIGHT)
    f:SetFrameStrata("HIGH")
    T.Window(f, T.WINDOW, 0.95)
    MakeMovable(f, db.window)
    f:SetScale(db.window.scale or 1)
    RestorePosition(f, db.window, "CENTER", 0, 0)
    f.grip = ScaleGrip(f, db.window, 0.6, 1.6)
    tinsert(UISpecialFrames, "UndeadRouteFrame") -- Escape closes it

    f.title = T.Text(f, "GameFontNormal", T.GOLD)
    f.title:SetPoint("TOPLEFT", 12, -8)
    f.title:SetText("Undead Route")
    f.sub = T.Text(f, "GameFontHighlightSmall", T.DIM)
    f.sub:SetPoint("LEFT", f.title, "RIGHT", 10, 0)
    f.sub:SetText((ns.Faction or "Horde") .. " 1-60, WoW Forever")
    local close = T.Close(f, function() f:Hide() end)
    close:SetPoint("TOPRIGHT", -4, -4)

    -- The recommendation banner, with the 1-60 progress bar along its foot.
    local banner = CreateFrame("Frame", nil, f, "BackdropTemplate")
    banner:SetPoint("TOPLEFT", PAD, -TITLE_H)
    banner:SetPoint("TOPRIGHT", -PAD, -TITLE_H)
    banner:SetHeight(BANNER_H)
    T.Flat(banner, T.SURFACE)
    -- A click on the banner (where the route wants you) opens that stage, as Show recommended does.
    banner:EnableMouse(true)
    -- The window still drags by the banner, as by the rest of it; a drag is not a click.
    banner:RegisterForDrag("LeftButton")
    banner:SetScript("OnDragStart", function() banner.dragged = true f:StartMoving() end)
    banner:SetScript("OnDragStop", function()
        f:StopMovingOrSizing()
        SavePosition(f, db.window)
    end)
    banner:SetScript("OnMouseUp", function(_, mouse)
        if banner.dragged then banner.dragged = nil return end
        if mouse ~= "LeftButton" then return end
        selected = Recommend()
        db.window.stage = nil
        f.detailScroll:SetVerticalScroll(0)
        RevealSelected()
        Refresh()
    end)
    banner:SetScript("OnEnter", function(self)
        if GameTooltip and GameTooltip.SetOwner then
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
            GameTooltip:AddLine("Click to open the stage the route recommends.", 0.9, 0.9, 0.9)
            GameTooltip:Show()
        end
    end)
    banner:SetScript("OnLeave", function() if GameTooltip and GameTooltip.Hide then GameTooltip:Hide() end end)
    f.bannerMain = T.Text(banner, "GameFontHighlightLarge")
    f.bannerMain:SetPoint("TOPLEFT", 12, -9)
    f.bannerSub = T.Text(banner, "GameFontHighlightSmall", T.DIM)
    f.bannerSub:SetPoint("TOPLEFT", 12, -31)
    f.bannerSub:SetWidth(WIDTH - PAD * 2 - 24)
    f.bannerSub:SetWordWrap(false)
    f.bannerSub2 = T.Text(banner, "GameFontHighlightSmall", T.DIM)
    f.bannerSub2:SetPoint("TOPLEFT", 12, -47)
    f.bannerSub2:SetWidth(WIDTH - PAD * 2 - 24)
    f.bannerSub2:SetWordWrap(false)
    local track = banner:CreateTexture(nil, "ARTWORK")
    track:SetTexture(T.WHITE)
    track:SetVertexColor(0, 0, 0, 0.6)
    track:SetPoint("BOTTOMLEFT", 1, 1)
    track:SetPoint("BOTTOMRIGHT", -1, 1)
    track:SetHeight(4)
    f.fill = banner:CreateTexture(nil, "OVERLAY")
    f.fill:SetTexture(T.WHITE)
    f.fill:SetVertexColor(T.GOLD[1], T.GOLD[2], T.GOLD[3])
    f.fill:SetPoint("BOTTOMLEFT", 1, 1)
    f.fill:SetHeight(4)
    f.fillWidth = WIDTH - PAD * 2 - 2

    BuildList(f)
    BuildDetail(f)

    -- Bottom bar.
    local pin = T.Button(f, "Pin hub", 100, function() PinStage(selected) end)
    pin:SetPoint("BOTTOMLEFT", PAD, PAD)
    pin.tip = "Puts a map pin on this stage's quest hub, or on the next class quest to pick up, and points the arrow there."
    local go = T.Button(f, "Show recommended", 130, function()
        selected = Recommend()
        db.window.stage = nil -- the route leads again
        f.detailScroll:SetVerticalScroll(0)
        RevealSelected()
        Refresh()
    end)
    go:SetPoint("LEFT", pin, "RIGHT", 6, 0)
    go.tip = "Jumps to the stage the route recommends for your level and quest log."
    f.doneButton = T.Button(f, "Mark stage done", 130, function()
        db.stages[selected.key] = (not db.stages[selected.key]) or nil
        Refresh()
    end)
    f.doneButton:SetPoint("LEFT", go, "RIGHT", 6, 0)
    f.doneButton.tip = "Marks the whole stage done (or not done again), whatever its steps say."
    f.detourButton = T.Button(f, "Do it now", 110, function()
        SlashCmdList.UNDEADROUTE(db.detour == selected.key and "back"
            or (selected.kind == "alt" and ("follow " .. selected.key) or ("do " .. selected.hub)))
    end)
    f.detourButton:SetPoint("LEFT", f.doneButton, "RIGHT", 6, 0)
    f.detourButton.tip = "Pauses the route for this dungeon or side branch: the tracker and arrow lead to its quests. "
        .. "The route takes over again once they are done: for a dungeon, when its quests are handed in or you "
        .. "come out with nothing to hand in."
    f.detourButton:Hide()
    f.trackerButton = T.Button(f, "Tracker: on", 110, function()
        db.tracker.hidden = (not db.tracker.hidden) or nil
        Refresh()
    end)
    f.trackerButton:SetPoint("BOTTOMRIGHT", -PAD - 6, PAD) -- clear of the size grip in the corner
    f.trackerButton.tip = "Shows or hides the small tracker with the next step beside the screen. It shows when this window is closed."
    -- The arrow to the next step, as /route arrow.
    f.arrowButton = T.Button(f, "Arrow: on", 120, function() SlashCmdList.UNDEADROUTE("arrow") end)
    f.arrowButton:SetPoint("RIGHT", f.trackerButton, "LEFT", -6, 0)
    f.arrowButton.tip = "Shows or hides the arrow that points at the next step. Drag the arrow to move it."
    f:Hide()
    -- Closing the window (its x, or Escape) brings the tracker back.
    f:SetScript("OnHide", function() Refresh() end)
end

-- One quest of the NOW block: its line, and where a click on it pins.
local function NowLine(stage, entry, kind, level)
    local task, q = entry.task, entry.task.quest
    local name, where = QuestName(q), nil
    if kind == "pickup" then
        where = q.giver and (q.giver .. (task.x and string.format(" (%.1f, %.1f)", task.x, task.y) or ""))
            or q.where or Where(q)
    elseif kind == "work" then
        -- What to do comes on the lines below; here only where, short.
        if q.spot then where = string.format("around (%.1f, %.1f)", q.spot[1], q.spot[2])
        elseif stage.kind == "dungeon" then where = q.inside and "starts inside" or "in the dungeon" end
    elseif kind == "handin" then
        local t = q.turnin
        where = t and string.format("%s (%.1f, %.1f)", t[4] or "", t[2], t[3]) or "where you got it"
    else
        if entry.state == "later" then where = "from level " .. (task.req or level)
        else where = "after " .. (WaitsFor(q) or "the quest before it") end
    end
    local text = name .. Badges(task, level) .. (where and ("  |cff999999" .. where .. "|r") or "")
    if entry.other then text = text .. "  |cff999999(in your log, from another batch)|r" end
    -- What is left of it, count first ("3/8  Bloodsnout Worg slain"); before pickup, what it asks, when known.
    if kind == "work" or kind == "pickup" then
        for _, o in ipairs(ObjectiveLines(task)) do text = text .. "\n" .. o end
    end
    return text, StepPlace(task, kind)
end

-- Draws the NOW block at `y` in the detail panel; returns the y under it.
local function RefreshNow(stage, level, y)
    local now = main.detail.now
    local done = Status(stage, level) == "done" -- also when marked done by hand with quests still open
    local plan = not done and CurrentBatch(stage, level) or nil
    if not plan then
        for _, row in ipairs(now.rows) do row:Hide() end
        -- A finished stage says so where the batch was, and where to go on, instead of the box just going.
        if not done then
            now:Hide()
            return y, nil
        end
        now.head:SetText("DONE   |cffffffff" .. StageName(stage) .. "|r")
        now.count:SetText("")
        now.track:Hide()
        now.fill:Hide()
        now.nextWhere:Hide()
        now.next:ClearAllPoints()
        now.next:SetPoint("TOPLEFT", 10, -28)
        -- Marked done by hand with quests still open: say that, not that nothing is left.
        local open = 0
        for i, task in ipairs(stage.tasks) do
            local ts = TaskState(stage, i, level)
            if task.id and ts ~= "done" and ts ~= "closed" and ts ~= "skipped" then open = open + 1 end
        end
        now.next:SetText(open > 0 and db.stages[stage.key]
            and string.format("Marked done by hand, with %d quest%s still open. Unmark stage (below) to see them as steps again.", open, open == 1 and "" or "s")
            or "Nothing left on this stage. Click the banner or Show recommended for what comes next.")
        now.next:Show()
        now:SetHeight(28 + math.max(14, now.next:GetStringHeight() or 14) + 12)
        now:ClearAllPoints()
        now:SetPoint("TOPLEFT", 0, -y)
        now:Show()
        return y + now:GetHeight() + 14, nil
    end
    now.track:Show()
    now.nextWhere:Show()
    now.next:Show()
    local width, batch = main.detailWidth, plan.batch
    now.head:SetText("NOW   |cffffffff" .. batch.label .. "|r")
    now.count:SetText(string.format("%d of %d handed in", plan.done, plan.total))
    local inner = width - 20
    now.track:ClearAllPoints()
    now.track:SetPoint("TOPLEFT", 10, -28)
    now.track:SetWidth(inner)
    now.fill:ClearAllPoints()
    now.fill:SetPoint("TOPLEFT", 10, -28)
    now.fill:SetWidth(math.max(1, inner * (plan.total > 0 and plan.done / plan.total or 0)))
    now.fill:SetShown(plan.done > 0)

    -- The one thing to do next, large.
    local step = NextStep(stage)
    local nextText, nextWhere
    if step then
        local c = BATCH_COLOR[step.kind] or T.GOLD
        nextText = string.format("|c%s%s|r  %s", Hex(c), BATCH_VERB[step.kind] or "Go", step.name or step.title)
        -- The arrow follows the recommended stage only.
        local arrow = db.arrow ~= false and stage == Recommend()
        nextWhere = string.format("%s(%.1f, %.1f)%s", step.zone and (step.zone .. " ") or "", step.x, step.y,
            arrow and "  -  the arrow points there" or "  -  click a line to pin it")
        -- Nothing left in this batch has a place to go (its open quests have no known spot): the step
        -- is the next batch's, to do while you finish these.
        if step.focused then
            nextText = nextText .. "  |cff999999(your pick)|r"
            nextWhere = nextWhere .. ".  Click it again to let the route lead."
        elseif step.batch ~= batch then
            nextText = nextText .. "  |cff999999(next batch)|r"
            nextWhere = "While you finish the quests below.  " .. nextWhere
        end
    elseif #plan.pickup > 0 then
        nextText, nextWhere = "|c" .. Hex(BATCH_COLOR.pickup) .. "Pick up|r  the quests below", "Their start is not on the map."
    elseif #plan.work > 0 then
        nextText, nextWhere = "|c" .. Hex(BATCH_COLOR.work) .. "Do|r  the quests below, together", nil
    else
        nextText, nextWhere = "|c" .. Hex(BATCH_COLOR.handin) .. "Hand in|r  the quests below", nil
    end
    local yy = 38
    now.next:ClearAllPoints()
    now.next:SetPoint("TOPLEFT", 10, -yy)
    now.next:SetText(nextText)
    yy = yy + now.next:GetStringHeight() + 2
    now.nextWhere:ClearAllPoints()
    now.nextWhere:SetPoint("TOPLEFT", 10, -yy)
    now.nextWhere:SetText(nextWhere or "")
    now.nextWhere:SetShown(nextWhere ~= nil)
    if nextWhere then yy = yy + now.nextWhere:GetStringHeight() end
    yy = yy + 8

    -- The quests of the batch you can act on, numbered in the order you do them: pick up, do, hand in.
    local n = 0
    local function Place(row)
        local h = math.max(16, row.text:GetStringHeight() + 4)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 6, -yy)
        row:SetSize(inner + 8, h)
        row:Show()
        yy = yy + h + 1
    end
    for _, kind in ipairs({ "pickup", "work", "handin" }) do
        for _, entry in ipairs(plan[kind]) do
            n = n + 1
            local row = NowRow(now, n)
            local text, place = NowLine(stage, entry, kind, level)
            local c = BATCH_COLOR[kind]
            row.index, row.place, row.task, row.jump = entry.i, place, entry.task, false
            row.waiting = false
            row.focused = db.focus == entry.task.id
            row.focus:SetShown(row.focused)
            row:Paint(false)
            row.verb:SetText(string.format("|cffffffff%d|r  %s", n, BATCH_VERB[kind]))
            row.verb:SetTextColor(c[1], c[2], c[3])
            row.lv:SetText(tostring(entry.task.lv or entry.task.req or ""))
            row.text:SetWidth(inner - NOW_TEXT_X)
            row.text:SetText(text)
            row.text:SetTextColor(1, 1, 1)
            Place(row)
        end
    end
    -- Quests that cannot be done yet: one line, led by what they wait for. When that is in another
    -- stage (a chain begun in an earlier zone), a click opens it.
    if #plan.waiting > 0 then
        n = n + 1
        local row = NowRow(now, n)
        local name, where = WaitingBlocker(plan.waiting)
        local names, minLevel = {}, nil
        for _, entry in ipairs(plan.waiting) do
            names[#names + 1] = QuestName(entry.task.quest)
            if entry.state == "later" then minLevel = math.min(minLevel or 99, entry.task.req or level) end
        end
        local lead
        if name and where and where ~= stage then
            lead = string.format("Finish |cffffffff%s|r first: it is in %s %s. Click to open it.", name,
                StageName(where), RangeText(where))
        elseif name then
            lead = string.format("After |cffffffff%s|r.", name)
        else
            lead = string.format("From level %d.", minLevel or level)
        end
        row.index, row.place, row.task = nil, nil, nil
        row.jump = (where and where ~= stage) and where or false
        row.waiting, row.focused = true, false
        row.focus:Hide()
        row:Paint(false)
        row.verb:SetText(string.format("Waiting (%d)", #plan.waiting))
        row.verb:SetTextColor(T.DIM[1], T.DIM[2], T.DIM[3])
        row.lv:SetText("")
        row.text:SetWidth(inner - NOW_TEXT_X)
        row.text:SetText(lead .. "\n|cff999999" .. table.concat(names, ", ") .. "|r")
        row.text:SetTextColor(0.85, 0.85, 0.85)
        Place(row)
    end
    for i = n + 1, #now.rows do now.rows[i]:Hide() end
    now:SetHeight(yy + 8)
    now:ClearAllPoints()
    now:SetPoint("TOPLEFT", 0, -y)
    now:Show()
    return y + yy + 8 + 14, plan
end

-- Draws the READY TO HAND IN block at `y` (on every stage: it is your whole log); returns the y under it.
-- A click on a line pins where it is handed in and leads the arrow there, like a NOW line.
local function RefreshReady(y)
    local box = main.detail.ready
    local list = ReadyToHandIn()
    if #list == 0 then
        box:Hide()
        for _, row in ipairs(box.rows) do row:Hide() end
        return y
    end
    local inner, c = main.detailWidth - 20, BATCH_COLOR.handin
    local stops = 0
    for _, e in ipairs(list) do stops = math.max(stops, e.stop or 0) end
    box.head:SetText(string.format("READY TO HAND IN   |cffffffff%d|r  |cff999999%sclick one to go there|r", #list,
        stops > 1 and ("in walking order, " .. stops .. " stops; ") or ""))
    local yy = 28
    for i, e in ipairs(list) do
        local row = NowRow(box, i)
        local where = e.place and string.format("%s (%.1f, %.1f)", e.place.zone or "", e.place.x, e.place.y)
            or "where you got it"
        row.index, row.place, row.task, row.jump, row.waiting = nil, e.place, e.task, false, false
        row.offRoute = e.task == nil and e.place == nil -- a quest the route does not know: nowhere to send you
        row.focused = e.task ~= nil and db.focus == e.id
        row.focus:SetShown(row.focused)
        row:Paint(false)
        row.verb:SetText(e.stop and (e.stop .. ". Hand in") or "Hand in")
        row.verb:SetTextColor(c[1], c[2], c[3])
        row.lv:SetText(tostring(e.task and (e.task.lv or e.task.req) or ""))
        row.text:SetWidth(inner - NOW_TEXT_X)
        row.text:SetText(e.name .. "  |cff999999" .. where .. "|r")
        row.text:SetTextColor(1, 1, 1)
        local h = math.max(16, row.text:GetStringHeight() + 4)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 6, -yy)
        row:SetSize(inner + 8, h)
        row:Show()
        yy = yy + h + 1
    end
    for i = #list + 1, #box.rows do box.rows[i]:Hide() end
    box:SetHeight(yy + 8)
    box:ClearAllPoints()
    box:SetPoint("TOPLEFT", 0, -y)
    box:Show()
    return y + yy + 8 + 14
end

local function RefreshMain()
    local f, level, rec = main, Level(), Recommend()
    selected = selected or rec

    -- Banner.
    local here = GetRealZoneText and GetRealZoneText()
    local verb = (rec.zone == here) and "Stay in" or "Go to"
    f.bannerMain:SetText(string.format("Level %d   |cff999999>|r   %s %s%s|r, %s  |cff999999(%s)|r", level, verb, T.Accent(),
        rec.zone, rec.hub, RangeText(rec)))
    -- The two best in full (so the line is never cut off), then how many more there are.
    local parts, more = {}, 0
    for _, v in ipairs(RankedDungeons()) do
        local d = v.stage
        if d.route or #v.blues > 0 then
            if #parts < 2 then
                local xp = XPText(v)
                parts[#parts + 1] = string.format("%s (%d quest%s%s%s)", d.hub, #v.left, #v.left == 1 and "" or "s",
                    xp ~= "" and (", " .. xp) or "", #v.blues > 0 and (", " .. #v.blues .. " blue") or "")
            else
                more = more + 1
            end
        end
    end
    if more > 0 then parts[#parts] = parts[#parts] .. string.format("  |cff999999+ %d more: /route dungeons|r", more) end
    -- Two short lines, so neither is cut off: dungeons, then what else is waiting.
    local detour = db.detour == rec.key
    f.bannerSub:SetText(detour and ((rec.kind == "alt" and ("Side branch: " .. rec.zone) or ("Detour: " .. rec.hub))
            .. ". The route waits; Back to route ends it.")
        or #parts > 0 and ("Dungeons now, best first: " .. table.concat(parts, ", "))
        or "No dungeon quests waiting right now.")
    local more = {}
    if level < rec.min then more[#more + 1] = "You are a little early for this stage." end
    local left = Leftovers()[1]
    if left then
        more[#more + 1] = string.format("Earlier: %s %s has %d step%s left.", left.stage.zone, RangeText(left.stage),
            left.count, left.count == 1 and "" or "s")
    end
    local open = ClassQuests()
    if open[1] then more[#more + 1] = string.format(ClassTag() .. " %s.", open[1].quest.name) end
    f.bannerSub2:SetText(table.concat(more, "  "))
    f.fill:SetWidth(math.max(1, f.fillWidth * math.min(1, (level - 1) / 59)))

    -- Stage list.
    for i, stage in ipairs(ns.Stages) do
        local row, st = f.rows[i], Status(stage, level)
        local isRec, isSel = stage == rec, stage == selected
        row.marker:SetShown(isRec)
        if isSel then
            row.bg:SetVertexColor(T.SURFACE[1], T.SURFACE[2], T.SURFACE[3], 1)
        elseif row.hover then
            row.bg:SetVertexColor(T.SURFACE[1], T.SURFACE[2], T.SURFACE[3], 0.5)
        else
            row.bg:SetVertexColor(0, 0, 0, 0)
        end
        local c = (isRec and T.GOLD) or (stage.kind == "class" and T.PINK) or (st == "now" and { 1, 1, 1 })
            or (st == "soon" and T.DIM) or T.MUTED
        row.name:SetTextColor(c[1], c[2], c[3])
        row.tick:SetShown(st == "done")
        local tag = ""
        if st ~= "done" then
            if stage.kind == "dungeon" then
                local _, blues = QuestsLeft(stage)
                local label = (#blues > 0) and (#blues .. " blue") or (stage.route and "Dungeon" or "Off route")
                tag = (st == "now" and not stage.ally) and ("|cff59d973" .. label .. "|r") or label
            elseif stage.kind == "class" then
                tag = "|c" .. CLASS.hex .. "Class|r"
            elseif stage.kind == "city" then
                tag = "City"
            elseif stage.kind == "alt" then
                tag = "Alt"
            elseif st == "out" then
                tag = "past"
            end
        end
        row.tag:SetText(tag)
    end

    -- Detail.
    local stage, d, y = selected, f.detail, 0
    local function Place(fs, gap)
        fs:ClearAllPoints()
        fs:SetPoint("TOPLEFT", 0, -y)
        fs:Show()
        y = y + fs:GetStringHeight() + (gap or 6)
    end
    local kind = (stage.kind == "dungeon" and "Dungeon") or (stage.kind == "alt" and "Side branch")
        or (stage.kind == "class" and "Class quests") or (stage.kind == "city" and "City quests, any level") or "Main route"
    d.title:SetText((stage.kind == "dungeon" or stage.kind == "class" or stage.kind == "city") and StageName(stage)
        or (stage.zone .. ": " .. stage.hub))
    Place(d.title, 4)
    local st = Status(stage, level)
    local state = (st == "done" and "done") or (st == "out" and "you have outleveled it")
        or (st == "soon" and ("opens at level " .. stage.min)) or "in range now"
    if stage.kind == "class" or stage.kind == "city" then
        d.meta:SetText(kind .. "   |   " .. (st == "done" and "all done" or (#OpenTasks(stage) .. " open now")))
    else
        d.meta:SetText(string.format("%s   |   Level %s%s   |   %s", kind, RangeText(stage),
            stage.best and (", best at " .. stage.best) or "", state))
    end
    if stage.kind == "dungeon" and st == "now" then
        local v = DungeonValue(stage, level)
        if #v.left > 0 then
            local xp = XPText(v)
            d.meta:SetText(string.format("%s   |   Level %s, best at %d   |   %s", kind, RangeText(stage), stage.best, state)
                .. string.format("\n%d quest%s left%s%s. Pick up: %s", #v.left,
                #v.left == 1 and "" or "s", xp ~= "" and (", " .. xp) or "",
                #v.blues > 0 and (", " .. #v.blues .. " blue") or "", v.where))
        end
    end
    Place(d.meta, 14)
    local onDetour = db.detour == stage.key
    f.detourButton:SetShown(onDetour or (stage.kind == "dungeon" and not stage.ally and st == "now"
        and #QuestsLeft(stage) > 0) or (stage.kind == "alt" and st == "now"))
    f.detourButton.label:SetText(onDetour and "Back to route" or (stage.kind == "alt" and "Follow this" or "Do it now"))
    local plan
    y, plan = RefreshNow(stage, level, y)
    y = RefreshReady(y)
    Place(d.travelHead, 4)
    d.travel:SetText(stage.travel)
    Place(d.travel, 14)

    local open = 0
    for i = 1, #stage.tasks do
        local ts = TaskState(stage, i, level)
        if ts == "do" or ts == "inlog" then open = open + 1 end
    end
    d.stepsHead:SetText(string.format("STEPS   |cff999999%d to do%s|r", open,
        #stage.batches > 1 and string.format(", in %d batches", #stage.batches) or ""))
    Place(d.stepsHead, 6)
    -- Progress of every batch, for its heading.
    local progress = {}
    for _, batch in ipairs(stage.batches) do
        local done, total = 0, 0
        for _, i in ipairs(batch.idx) do
            local ts = TaskState(stage, i, level)
            if ts == "done" then done = done + 1 end
            if ts ~= "skipped" and ts ~= "closed" and ts ~= "low" then total = total + 1 end
        end
        progress[batch] = { done = done, total = total }
    end
    local current = plan and plan.batch
    for i, task in ipairs(stage.tasks) do
        local row, ts = TaskRow(d, i), TaskState(stage, i, level)
        row.index = i
        local c = STATE_COLOR[ts]
        -- Only a tip has a box to tick. A quest shows one once it is handed in, and leaves room for Skip.
        local quest = task.id ~= nil
        row.box:SetShown(not quest or ts == "done")
        row.isSkipped = ts == "skipped"
        row.canSkip = quest and (ts == "do" or ts == "later" or ts == "locked" or ts == "low")
        row.skip.label:SetText(row.isSkipped and "Undo" or "Skip")
        row.text:SetWidth(f.detailWidth - 52 - (quest and 50 or 0))
        row.text:SetText(TaskText(stage, task, ts, level))
        row.text:SetTextColor(c[1], c[2], c[3])
        row.lv:SetText(tostring(task.lv or task.req or ""))
        row.tick:SetShown(ts == "done")
        -- A hub heading sits above the first quest picked up there and pushes the step down.
        local batch, head = task.batch, task.head
        if head and batch and progress[batch] then
            local p = progress[batch]
            local finished = p.total == 0 or p.done == p.total
            if batch == current then
                head = T.Accent() .. "NOW|r   " .. head
                row.head:SetTextColor(T.GOLD[1], T.GOLD[2], T.GOLD[3])
            elseif finished then
                row.head:SetTextColor(T.FAINT[1], T.FAINT[2], T.FAINT[3])
            else
                row.head:SetTextColor(0.85, 0.85, 0.85)
            end
            head = head .. (finished and "  |cff999999- done|r"
                or string.format("  |cff999999- %d of %d handed in|r", p.done, p.total))
        end
        row.head:SetText(head or "")
        row.head:SetShown(task.head ~= nil)
        -- The NOW batch is in the box above, so here it folds to its heading; a click on that heading
        -- shows its quests (with their Skip buttons) or folds them again.
        local folded = batch ~= nil and batch == current and not nowOpen
        row.nowHead = batch ~= nil and batch == current and task.head ~= nil
        if row.nowHead then -- the box above has the details
            local p = progress[batch]
            row.head:SetText(string.format("%sNOW|r   %s  |cff999999- %d of %d handed in  - %s|r", T.Accent(),
                batch.label, p.done, p.total, folded and "in the box above, click to show" or "click to fold"))
        end
        if folded then row.canSkip = false end
        -- A heading wraps to as many lines as it needs and pushes the step down by its height.
        local off = task.head and (8 + math.ceil(math.max(12, row.head:GetStringHeight() or 12)) + 6) or 0
        -- The quests of the batch you are on carry a bar coloured by what to do with them now.
        local mark = batch and batch == current and (ts == "do" and "pickup"
            or (ts == "inlog" and (Complete(task.id) and "handin" or "work")))
        row.mark:SetShown(mark and true or false)
        if mark then
            local c = BATCH_COLOR[mark]
            row.mark:SetVertexColor(c[1], c[2], c[3])
            row.mark:ClearAllPoints()
            row.mark:SetPoint("TOPLEFT", 5, -2 - off)
            row.mark:SetHeight(math.max(14, row.text:GetStringHeight()))
        end
        row.box:ClearAllPoints()
        row.box:SetPoint("TOPLEFT", 0, -2 - off)
        row.lv:ClearAllPoints()
        row.lv:SetPoint("TOPLEFT", 22, -3 - off)
        row.text:ClearAllPoints()
        row.text:SetPoint("TOPLEFT", 52, -3 - off)
        row.skip:ClearAllPoints()
        row.skip:SetPoint("TOPRIGHT", 0, -1 - off)
        row.text:SetShown(not folded)
        row.lv:SetShown(not folded)
        if folded then
            row.box:Hide()
            row.mark:Hide()
        end
        UpdateSkip(row)
        if folded and not task.head then
            row:Hide()
        else
            local h = folded and off or (math.max(18, row.text:GetStringHeight() + 6) + off)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", 0, -y)
            row:SetSize(f.detailWidth, h)
            row:Show()
            y = y + h + 2
        end
    end
    for i = #stage.tasks + 1, #d.taskRows do d.taskRows[i]:Hide() end
    y = y + 10
    if stage.note then
        d.note:SetText(stage.note)
        Place(d.note, 10)
    else
        d.note:Hide()
    end
    local source = SOURCE[stage.src] or ""
    if stage.kind == "dungeon" and stage.src ~= "data" and stage.src ~= "newdata" then source = source .. " " .. SOURCE.data end
    if stage.min >= 30 and stage.kind ~= "dungeon" then source = source .. " Untested on live above level 30." end
    d.source:SetText(source)
    Place(d.source, 16)
    Place(d.rulesHead, 4)
    Place(d.rules, 4)
    d:SetHeight(y)

    f.doneButton.label:SetText(db.stages[stage.key] and "Unmark stage" or "Mark stage done")
    f.trackerButton.label:SetText(db.tracker.hidden and "Tracker: off" or "Tracker: on")
    f.arrowButton.label:SetText(db.arrow == false and "Arrow: off" or "Arrow: on")
end

---------------------------------------------------------------------------
-- Tracker: the small always-on panel
---------------------------------------------------------------------------

local TRACKER_W = 260

local RefreshTracker
local function BuildTracker()
    local t = CreateFrame("Frame", "UndeadRouteTracker", UIParent, "BackdropTemplate")
    tracker = t
    t:SetWidth(TRACKER_W)
    local framed = T.Window(t, T.WINDOW, 0.85) -- ZodUI's look: the game's frame, fitted to the tracker's height
    MakeMovable(t, db.tracker)
    t:SetScale(db.tracker.scale or 1)
    RestorePosition(t, db.tracker, "RIGHT", -40, 120)
    t.grip = ScaleGrip(t, db.tracker, 0.6, 2)
    t.marker = t:CreateTexture(nil, "ARTWORK")
    t.marker:SetTexture(T.WHITE)
    t.marker:SetVertexColor(T.GOLD[1], T.GOLD[2], T.GOLD[3])
    t.marker:SetPoint("TOPLEFT", 1, -1)
    t.marker:SetPoint("BOTTOMLEFT", 1, 1)
    t.marker:SetWidth(3)
    if framed then -- inside the game's frame: under its title band, clear of its left edge
        t.marker:ClearAllPoints()
        t.marker:SetPoint("TOPLEFT", 7, -24)
        t.marker:SetPoint("BOTTOMLEFT", 7, 7)
        t.marker:SetWidth(2)
    end
    t.head = T.Text(t, "GameFontNormalSmall", T.GOLD)
    t.head:SetPoint("TOPLEFT", 12, -8)
    t.head:SetWidth(TRACKER_W - 44)
    -- Folds the tracker to what matters most: where, the next step, the batch you are on and
    -- what is ready to hand in.
    t.fold = T.Button(t, "-", 20, function()
        db.tracker.collapsed = (not db.tracker.collapsed) or nil
        -- Anchored by its top-left corner from now on, so folding keeps the heading where it is
        -- instead of shrinking towards the middle (the first place is RIGHT of the screen).
        local left, top = t:GetLeft(), t:GetTop()
        if left and top then
            t:ClearAllPoints()
            t:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
            SavePosition(t, db.tracker)
        end
        RefreshTracker()
    end)
    t.fold:SetHeight(18)
    t.fold:SetPoint("TOPRIGHT", -6, -5)
    t.fold.tip = "Folds the tracker to the next step, the batch you are on and what is ready to hand in, or shows it all again."
    t.body = T.Text(t, "GameFontHighlightSmall")
    t.body:SetWidth(TRACKER_W - 20)
    t.body:SetSpacing(3)
    t.foot = T.Text(t, "GameFontHighlightSmall", T.MUTED)
    t.foot:SetWidth(TRACKER_W - 30) -- clear of the size grip in the corner
    t.foot:SetText("Click: pin the next step. Right-click: the route")
    -- Left-click (not a drag): a map pin on the next step, no window needed. Right-click opens the route.
    t:SetScript("OnMouseDown", function(self) self.downAt = { self:GetLeft(), self:GetTop() } end)
    t:SetScript("OnMouseUp", function(self, button)
        if button == "RightButton" then ns.Toggle() return end
        local at = self.downAt
        if button ~= "LeftButton" or not at or at[1] ~= self:GetLeft() or at[2] ~= self:GetTop() then return end -- moved: a drag
        local step = NextStep()
        if step and step.x then
            PinAt(step.map, step.zone, step.x, step.y, step.title)
        else
            Print("No map location known for the next step.")
        end
    end)
end

function RefreshTracker()
    local t = tracker
    -- The window shows all of this and more, and the two overlap: one at a time.
    local hidden = db.tracker.hidden or (main and main:IsShown()) or false
    t:SetShown(not hidden)
    if hidden then return end -- nothing to work out for a tracker nobody sees; closing the window refreshes it
    local level, rec = Level(), Recommend()
    t.head:SetText(string.format("Lv %d   %s%s, %s", level, (db.detour == rec.key) and "Detour: " or "", rec.zone, rec.hub))
    local open, lines, essential = OpenTasks(rec), {}, {}
    local step = NextStep()
    if step then
        lines[#lines + 1] = string.format("%sNext:|r %s  |cff999999%s (%.1f, %.1f)|r", T.Accent(), step.title, step.zone or "",
            step.x, step.y)
        essential[#essential + 1] = lines[#lines]
    end
    if db.train then lines[#lines + 1] = string.format("|cffe6cc8cTrain:|r new spells since level %d", db.train) end
    local plan = CurrentBatch(rec, level)
    if plan then
        -- The batch you are on: each quest with what to do with it.
        lines[#lines + 1] = string.format("%sNow:|r %s  |cff999999%d of %d handed in|r", T.Accent(), plan.batch.label,
            plan.done, plan.total)
        essential[#essential + 1] = lines[#lines]
        -- Quests you are working on come first, with what is left of each ("3/10  Farmer slain").
        local shown, all = 0, #plan.pickup + #plan.work + #plan.handin
        for _, kind in ipairs({ "work", "handin", "pickup" }) do
            for _, entry in ipairs(plan[kind]) do
                if shown < 5 then
                    shown = shown + 1
                    lines[#lines + 1] = string.format("  |c%s%s|r %s%s", Hex(BATCH_COLOR[kind]), BATCH_VERB[kind],
                        QuestName(entry.task.quest), Badges(entry.task, level))
                    if kind == "work" then
                        for _, o in ipairs(ObjectiveLines(entry.task, "      ")) do lines[#lines + 1] = o end
                    end
                end
            end
        end
        if all > shown then lines[#lines + 1] = string.format("  |cff999999+ %d more|r", all - shown) end
        if #plan.waiting > 0 then
            local name, where = WaitingBlocker(plan.waiting)
            lines[#lines + 1] = string.format("  |cff999999%d waiting%s|r", #plan.waiting,
                name and (": finish " .. name .. " first" .. ((where and where ~= rec) and (" (" .. where.zone .. " "
                    .. RangeText(where) .. ")") or "")) or "")
        end
    else
        for i = 1, math.min(3, #open) do lines[#lines + 1] = "- " .. open[i] end
        if #open > 3 then lines[#lines + 1] = string.format("|cff999999+ %d more|r", #open - 3) end
    end
    -- Put first, not over the first line: that may be the Train reminder.
    if #open == 0 then table.insert(lines, 1, "Nothing left here at your level. Mark the stage done and move on.") end
    local ready = ReadyToHandIn()
    if #ready > 0 then
        -- The walking order (ReadyToHandIn): one numbered line per stop, its quests and where it is.
        local stops, unplaced = {}, {}
        for _, e in ipairs(ready) do
            if e.stop then
                local s = stops[e.stop] or { names = {}, place = e.place }
                stops[e.stop] = s
                s.names[#s.names + 1] = e.name
            else
                unplaced[#unplaced + 1] = e.name
            end
        end
        lines[#lines + 1] = string.format("|c%sReady to hand in:|r %d  |cff999999%s|r", Hex(BATCH_COLOR.handin), #ready,
            #stops > 1 and ("in " .. #stops .. " stops, nearest first") or "")
        essential[#essential + 1] = lines[#lines]
        local SHOWN = 4
        for i = 1, math.min(SHOWN, #stops) do
            local s = stops[i]
            lines[#lines + 1] = string.format("  |c%s%d.|r %s  |cff999999%s (%.0f, %.0f)|r", Hex(BATCH_COLOR.handin), i,
                table.concat(s.names, " + "), s.place.zone or "", s.place.x, s.place.y)
            if i == 1 then essential[#essential + 1] = lines[#lines] end
        end
        if #stops > SHOWN then lines[#lines + 1] = string.format("  |cff999999+ %d more stops|r", #stops - SHOWN) end
        if #unplaced > 0 then
            lines[#lines + 1] = string.format("  |cff999999%s: where you got %s|r", table.concat(unplaced, ", "),
                #unplaced == 1 and "it" or "them")
        end
    end
    local left = Leftovers()[1]
    if left then
        lines[#lines + 1] = string.format("|cffe6cc8cEarlier:|r %d step%s left in %s %s", left.count,
            left.count == 1 and "" or "s", left.stage.zone or "", RangeText(left.stage))
    end
    for _, v in ipairs(RankedDungeons()) do
        local d = v.stage
        if (d.route or #v.blues > 0) and d ~= rec then
            local xp = XPText(v)
            lines[#lines + 1] = string.format("|cff59d973Dungeon:|r %s, %d quest%s%s%s", d.hub, #v.left,
                #v.left == 1 and "" or "s", xp ~= "" and ("|cff999999, " .. xp .. "|r") or "",
                #v.blues > 0 and (", |cff0070dd" .. #v.blues .. " blue|r") or "")
        end
    end
    local class = ClassQuests()
    if class[1] then
        lines[#lines + 1] = string.format(ClassTag() .. " %s%s", class[1].quest.name,
            #class > 1 and string.format(" (+%d)", #class - 1) or "")
    end
    local folded = db.tracker.collapsed
    if folded and #open == 0 then table.insert(essential, 1, lines[1]) end
    t.fold.label:SetText(folded and "+" or "-")
    t.foot:SetText(folded and "Folded: + shows all. Click: pin the next step" or "Click: pin the next step. Right-click: the route")
    t.body:SetText(table.concat(folded and essential or lines, "\n"))
    t.body:ClearAllPoints()
    t.body:SetPoint("TOPLEFT", 12, -(8 + t.head:GetStringHeight() + 6))
    t.foot:ClearAllPoints()
    t.foot:SetPoint("TOPLEFT", t.body, "BOTTOMLEFT", 0, -6)
    t:SetHeight(8 + t.head:GetStringHeight() + 6 + t.body:GetStringHeight() + 6 + t.foot:GetStringHeight() + 8)
end

---------------------------------------------------------------------------
-- The arrow
---------------------------------------------------------------------------

-- The arrow: our own, on screen, pointing at the next step (or at a place you pinned, until you get there),
-- with how far it is. It turns with where you face (GetPlayerFacing) and measures in yards from the world
-- positions of you and the place, so it needs no other addon. On another continent, or where the game gives
-- no position (an instance), it names the zone instead. Drag it to move it; /route arrow hides it.
local ARROW_ART = "Interface\\AddOns\\UndeadRoute\\Media\\Arrow" -- tools/icon.js draws it
local ARRIVED = 10 -- yards
local arrowFrame, arrowTarget, arrowPin, arrowKey
local quickPlace -- whether UnitPosition is used for your place: nil until it is checked, then true or false

local function BuildArrow()
    local f = CreateFrame("Frame", "UndeadRouteArrow", UIParent)
    arrowFrame = f
    f:SetSize(220, 92)
    f:SetFrameStrata("MEDIUM")
    MakeMovable(f, db.arrowPos)
    RestorePosition(f, db.arrowPos, "TOP", 0, -110)
    f.art = f:CreateTexture(nil, "ARTWORK")
    f.art:SetTexture(ARROW_ART)
    f.art:SetSize(48, 48)
    f.art:SetPoint("TOP", 0, 0)
    f.title = T.Text(f, "GameFontNormal", T.GOLD)
    f.title:SetPoint("TOP", f.art, "BOTTOM", 0, -2)
    f.title:SetWidth(220)
    f.title:SetJustifyH("CENTER")
    f.dist = T.Text(f, "GameFontHighlightSmall")
    f.dist:SetPoint("TOP", f.title, "BOTTOM", 0, -2)
    f.dist:SetWidth(220)
    f.dist:SetJustifyH("CENTER")
    -- Every frame while the game gives your place straight (WhereAmI's quick way), so the arrow turns as
    -- smoothly as you do; else 20 times a second, since the slow way makes tables each time.
    local wait = 0
    f:SetScript("OnUpdate", function(self, elapsed)
        if quickPlace ~= true then
            wait = wait - elapsed
            if wait > 0 then return end
            wait = 0.05
        end
        ns.ArrowTick(self)
    end)
    f:Hide()
end

-- Where you are in the world: continent, x, y in yards, or nil. UnitPosition gives it in one call that makes
-- no table. It is trusted only once it has agreed (within AGREE yards) with the place worked out from your
-- spot on the map; if the two disagree it is not used this session.
local AGREE = 15
function ns.WhereAmI()
    local x, y, inst
    if quickPlace ~= false and UnitPosition then
        local _
        x, y, _, inst = UnitPosition("player")
        x, y, inst = Plain(x), Plain(y), Plain(inst)
        if type(x) ~= "number" or type(y) ~= "number" or type(inst) ~= "number" then x = nil end
        if x and quickPlace then return inst, x, y end
    end
    local here = Here()
    if not (here and here.continent) then return end
    if x and quickPlace == nil then
        quickPlace = inst == here.continent and math.abs(x - here.wx) <= AGREE and math.abs(y - here.wy) <= AGREE
    end
    return here.continent, here.wx, here.wy
end

-- Where the arrow points and what it says, now. Returns the yards to go, or nil when they are not known.
function ns.ArrowTick(f)
    local t = arrowTarget
    if not t then return end
    T.Say(f.title, t.title or "")
    local mine, mx, my = ns.WhereAmI()
    -- The place stands still: its world position is asked for once, and kept with it once the game gives it.
    local world = t.world
    if not world then
        local continent, tx, ty = WorldPos(t.map, t.x, t.y)
        if continent then
            world = { continent, tx, ty }
            t.world = world
        end
    end
    local continent, tx, ty
    if world then continent, tx, ty = world[1], world[2], world[3] end
    if not (mine and continent and mine == continent) then
        f.art:Hide()
        f.whole = nil
        T.Say(f.dist, t.zone and ("in " .. t.zone) or "on another map")
        return nil
    end
    -- World x runs north, y west; facing is turned from north towards west.
    local north, west = tx - mx, ty - my
    local yards = math.sqrt(north * north + west * west)
    if yards <= ARRIVED then
        f.art:Hide()
        f.whole = nil
        T.Say(f.dist, "you are there")
        if arrowPin and t == arrowPin then -- a pin is done with once reached: back to the route
            arrowPin = nil
            ns.UpdateArrow()
        end
        return yards
    end
    local whole = math.floor(yards + 0.5)
    if f.whole ~= whole then -- written when the number changes, not on every frame
        f.whole = whole
        T.Say(f.dist, string.format("%d yds", whole))
    end
    local facing = GetPlayerFacing and Plain(GetPlayerFacing())
    if type(facing) == "number" then
        f.art:SetRotation((math.atan2 or math.atan)(west, north) - facing) -- atan2: the game's Lua 5.1
        f.art:Show()
    else
        f.art:Hide() -- facing not given (an instance): the yards still help
    end
    return yards
end

-- The arrow follows a pin while there is one, else the next step. Called on every refresh.
function ns.UpdateArrow()
    if not db then return end
    local t
    if db.arrow ~= false then
        t = arrowPin
        if not t then
            local step = NextStep()
            if step and step.map and step.x then t = step end
        end
    end
    local key = t and (t.key or t.title)
    if key ~= arrowKey then
        arrowKey = key
        arrowTarget = t
        if ns.OnArrowTarget then ns.OnArrowTarget(t) end -- the tests listen here
    end
    if not arrowFrame and t then BuildArrow() end
    if arrowFrame then arrowFrame:SetShown(t ~= nil) end
end
local UpdateArrow = ns.UpdateArrow

function ns.PinArrow(place)
    arrowPin = place
    if ns.ready then UpdateArrow() end
end

local function Draw()
    if ns.ready then UpdateArrow() end
    if main and main:IsShown() then RefreshMain() end
    if tracker then RefreshTracker() end
end

-- Everything on screen, worked out again. While it draws, Route.lua keeps what it has asked the game
-- (I.Remember); an error in the drawing must not leave that on, so it is switched off before the error goes on.
Refresh = function()
    if not db then return end
    I.Remember(true)
    local ok, err = pcall(Draw)
    I.Remember(false)
    if not ok then error(err, 0) end
end

function ns.Toggle()
    if not main then BuildMain() end
    if main:IsShown() then
        main:Hide()
    else
        -- The stage you picked yourself, when there is one; otherwise where the route wants you now.
        local picked
        for _, stage in ipairs(ns.Stages) do
            if db.window.stage and stage.key == db.window.stage then picked = stage end
        end
        selected = picked or Recommend()
        main:Show()
        RevealSelected()
        Refresh()
    end
end

---------------------------------------------------------------------------
-- For Core.lua
---------------------------------------------------------------------------

I.PinAt, I.BuildTracker, I.RefreshTracker, I.Refresh = PinAt, BuildTracker, RefreshTracker, Refresh

-- The stage the window shows (nil: the recommended one, the next time it is drawn).
function I.Select(stage) selected = stage end

function I.WindowShown() return main ~= nil and main:IsShown() end

-- In a fight the tracker steps back: faint, and the clicks go through it to the world, so it is
-- not dragged away by accident.
function I.TrackerFight(fight)
    if not tracker then return end
    tracker:SetAlpha(fight and 0.4 or 1)
    tracker:EnableMouse(not fight)
    tracker.fold:EnableMouse(not fight)
    if tracker.grip then tracker.grip:EnableMouse(not fight) end
end
