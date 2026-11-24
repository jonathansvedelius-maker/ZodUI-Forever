-- A WoW API for the browser preview. Unlike tools/harness.lua, whose widgets are empty
-- shells, these keep their anchors, sizes, colours and text and draw them as HTML, so the
-- addon's own code lays out the window you see.
-- Only what the addon uses is implemented. A call to anything else does nothing and is
-- named once in the panel's chat log.
local js = require "js"
local window = js.global
local H = window.H

local unpack = table.unpack or unpack

---------------------------------------------------------------------------
-- Regions: frames, textures and font strings
---------------------------------------------------------------------------

local gen = 0 -- bumped by every change that can move something; rects are cached per value
local nextId = 0
local regions = {}
local eventFrames = {}
local updaters = {} -- regions with an OnUpdate script, by id

local POINT = {
    TOPLEFT = { 0, 0 }, TOP = { 0.5, 0 }, TOPRIGHT = { 1, 0 },
    LEFT = { 0, 0.5 }, CENTER = { 0.5, 0.5 }, RIGHT = { 1, 0.5 },
    BOTTOMLEFT = { 0, 1 }, BOTTOM = { 0.5, 1 }, BOTTOMRIGHT = { 1, 1 },
}
local FONT = { -- size and colour of the font templates the addon asks for
    GameFontNormalSmall = { 10, 1, 0.82, 0 }, GameFontNormal = { 12, 1, 0.82, 0 }, GameFontNormalLarge = { 16, 1, 0.82, 0 },
    GameFontHighlightSmall = { 10, 1, 1, 1 }, GameFontHighlight = { 12, 1, 1, 1 }, GameFontHighlightLarge = { 16, 1, 1, 1 },
}
local LAYER = { BACKGROUND = 0, BORDER = 1, ARTWORK = 2, OVERLAY = 3 }
local STRATA = { BACKGROUND = 10, LOW = 20, MEDIUM = 30, HIGH = 40, DIALOG = 50, TOOLTIP = 60 }

local M = {} -- the methods
local warned = {}
local meta = { __index = function(_, k)
    local m = M[k]
    if m then return m end
    -- The addon's own fields are lower case; an upper-case name is a WoW method the preview lacks.
    if type(k) == "string" and k:match("^%u") then
        if not warned[k] then
            warned[k] = true
            H:note("Not simulated: widget method " .. k .. "()")
        end
        return function() end
    end
end }

local function New(kind, parent, z)
    nextId = nextId + 1
    local r = setmetatable({ id = nextId, kind = kind, parent = parent, points = {}, shown = true, children = {},
        scripts = {} }, meta)
    regions[r.id] = r
    if parent then parent.children[#parent.children + 1] = r end
    H:create(r.id, parent and parent.id or 0, kind, z)
    gen = gen + 1
    return r
end

local function IsText(r) return r.kind == "FontString" end

local Resolve
local function TextWidth(r) return math.ceil(H:measureW(r.text or "", r.size, r.spacing or 0, r.font or "")) end
local function TextHeight(r, width)
    return H:measureH(r.text or "", r.size, width or 0, r.wrap ~= false, r.spacing or 0, r.font or "")
end

Resolve = function(r)
    if r.gen == gen then return r.rect end
    local rect = { l = 0, t = 0, w = 0, h = 0 }
    r.gen, r.rect = gen, rect
    if not r.parent then -- UIParent
        rect.w, rect.h = H.w, H.h
        return rect
    end
    if r.scrollOf then -- a scroll child sits at its scroll frame's corner, moved up by the scroll
        local sf = Resolve(r.scrollOf)
        rect.l, rect.t, rect.w, rect.h = sf.l, sf.t - (r.scrollOf.scroll or 0), r.w or 0, r.h or 0
        return rect
    end
    local xs, ys = {}, {}
    for _, p in ipairs(r.points) do
        local rel, f, rf = Resolve(p.rel or r.parent), POINT[p.point], POINT[p.relPoint]
        xs[f[1]] = rel.l + rel.w * rf[1] + p.x
        ys[f[2]] = rel.t + rel.h * rf[2] - p.y
    end
    local base = Resolve(r.parent)
    local w = r.w
    if xs[0] and xs[1] then
        rect.l, w = xs[0], xs[1] - xs[0]
    else
        if not w then w = IsText(r) and TextWidth(r) or 0 end
        rect.l = xs[0] or (xs[1] and xs[1] - w) or (xs[0.5] and xs[0.5] - w / 2) or base.l
    end
    rect.w = w
    local h = r.h
    if ys[0] and ys[1] then
        rect.t, h = ys[0], ys[1] - ys[0]
    else
        if IsText(r) then h = TextHeight(r, r.w or (xs[0] and xs[1] and w) or nil) end
        h = h or 0
        rect.t = ys[0] or (ys[1] and ys[1] - h) or (ys[0.5] and ys[0.5] - h / 2) or base.t
    end
    rect.h = h
    return rect
end

-- Position and size ----------------------------------------------------

function M:SetPoint(point, a, b, c, d)
    local rel, relPoint, x, y
    if type(a) == "number" then
        relPoint, x, y = point, a, b or 0
    else
        rel, relPoint, x, y = a, b or point, c or 0, d or 0
    end
    local p = { point = point, rel = rel, relPoint = relPoint, x = x, y = y }
    for i, old in ipairs(self.points) do
        if old.point == point then self.points[i] = p p = nil break end
    end
    if p then self.points[#self.points + 1] = p end
    gen = gen + 1
end
function M:ClearAllPoints() self.points = {} gen = gen + 1 end
function M:SetAllPoints(rel)
    self.points = {}
    self:SetPoint("TOPLEFT", rel, "TOPLEFT", 0, 0)
    self:SetPoint("BOTTOMRIGHT", rel, "BOTTOMRIGHT", 0, 0)
end
function M:GetPoint(i)
    local p = self.points[i or 1]
    if p then return p.point, p.rel or self.parent, p.relPoint, p.x, p.y end
end
function M:SetSize(w, h) self.w, self.h = w, h gen = gen + 1 end
function M:SetWidth(w) self.w = w gen = gen + 1 end
function M:SetHeight(h) self.h = h gen = gen + 1 end
function M:GetWidth() return Resolve(self).w end
function M:GetHeight() return Resolve(self).h end
function M:GetParent() return self.parent end
function M:SetShown(s)
    s = s and true or false
    if s == self.shown then return end
    self.shown = s
    local fn = self.scripts[s and "OnShow" or "OnHide"]
    if fn then fn(self) end
end
function M:Show() self:SetShown(true) end
function M:Hide() self:SetShown(false) end
function M:IsMouseOver() return H:over(self.id) end
function M:IsShown() return self.shown end
function M:IsVisible()
    local r = self
    while r do
        if not r.shown then return false end
        r = r.parent
    end
    return true
end
function M:SetAlpha(a) self.alpha = a self.dirty = true end

-- Font strings ---------------------------------------------------------

function M:SetText(t)
    self.text = t == nil and "" or tostring(t)
    self.dirty = true
    gen = gen + 1
    if self.kind == "EditBox" then H:editText(self.id, self.text) end
end
function M:GetText() return self.text or "" end

-- Edit boxes -----------------------------------------------------------

function M:SetFocus() H:editFocus(self.id, true, false) end
function M:ClearFocus() H:editFocus(self.id, false, false) end
function M:HighlightText() H:editFocus(self.id, true, true) end
function M:SetAutoFocus() end
function M:SetFontObject() end
function M:SetMaxLetters() end
function M:GetCenter()
    local r = Resolve(self)
    return r.l + r.w / 2, H.h - (r.t + r.h / 2)
end
function M:GetEffectiveScale() return 1 end
function M:GetFont() return self.font or "Fonts\\FRIZQT__.TTF", self.size, "" end
function M:SetFont(path, size) self.font, self.size, self.dirty = path, size, true gen = gen + 1 end
function M:SetTextColor(r, g, b, a) self.color = { r, g, b, a or 1 } self.dirty = true end
function M:SetWordWrap(w) self.wrap = w and true or false self.dirty = true gen = gen + 1 end
function M:SetSpacing(s) self.spacing = s self.dirty = true gen = gen + 1 end
function M:SetJustifyH(j) self.justify = j self.dirty = true end
function M:SetJustifyV() end
function M:GetStringWidth() return TextWidth(self) end
function M:GetStringHeight() return TextHeight(self, self.w) end

-- Textures -------------------------------------------------------------

function M:SetTexture(path) self.texture = path self.dirty = true end
function M:SetVertexColor(r, g, b, a) self.vertex = { r, g, b, a or 1 } self.dirty = true end
function M:SetColorTexture(r, g, b, a)
    self.texture, self.vertex, self.dirty = "Interface\\Buttons\\WHITE8x8", { r, g, b, a or 1 }, true
end
-- The part of the image shown: left, right, top, bottom (0-1).
function M:SetTexCoord(l, r, t, b)
    self.coord = (l == 0 and r == 1 and t == 0 and b == 1) and "" or string.format("%g %g %g %g", l, r, t, b)
    self.dirty = true
end
-- The modern form: SetGradient("HORIZONTAL" or "VERTICAL", CreateColor(...), CreateColor(...)).
function M:SetGradient(orient, a, b)
    if type(a) ~= "table" or type(b) ~= "table" then return end
    self.grad = string.format("%s %g %g %g %g %g %g %g %g", orient, a.r, a.g, a.b, a.a or 1, b.r, b.g, b.b, b.a or 1)
    self.dirty = true
end
function M:SetBlendMode(m) self.blend = m self.dirty = true end
function M:SetRotation(rad) self.rot = rad self.dirty = true end
function M:SetDesaturated() end

-- Frames ---------------------------------------------------------------

function M:CreateTexture(_, layer) return New("Texture", self, LAYER[layer] or 2) end
function M:CreateFontString(_, layer, template)
    local fs = New("FontString", self, LAYER[layer] or 3)
    local f = FONT[template] or FONT.GameFontHighlightSmall
    fs.size, fs.color, fs.text, fs.dirty = f[1], { f[2], f[3], f[4], 1 }, "", true
    return fs
end
function M:SetBackdrop(b) self.backdrop = b self.dirty = true end
function M:SetBackdropColor(r, g, b, a) self.bg = { r, g, b, a or 1 } self.dirty = true end
function M:SetBackdropBorderColor(r, g, b, a) self.edge = { r, g, b, a or 1 } self.dirty = true end
function M:SetFrameStrata(s) H:z(self.id, STRATA[s] or 30) end
function M:SetScript(name, fn)
    self.scripts[name] = fn
    if name == "OnUpdate" then updaters[self.id] = fn and self or nil end
end
function M:GetScript(name) return self.scripts[name] end
function M:RegisterEvent(e)
    if not self.events then
        self.events = {}
        eventFrames[#eventFrames + 1] = self
    end
    self.events[e] = true
end
function M:UnregisterEvent(e) if self.events then self.events[e] = nil end end
function M:EnableMouse(on) if on then H:mouse(self.id) end end
function M:EnableMouseWheel(on) if on then H:wheel(self.id) end end
function M:RegisterForClicks(...)
    self.clicks = {}
    for _, c in ipairs({ ... }) do self.clicks[(c:gsub("Up$", ""):gsub("Down$", ""))] = true end
end
function M:RegisterForDrag() H:drag(self.id) end
function M:SetMovable() end
function M:SetClampedToScreen() end
function M:StartMoving() self.moving = true end
function M:StopMovingOrSizing() self.moving = false end
function M:SetScrollChild(child) self.scrollChild, child.scrollOf = child, self gen = gen + 1 end
function M:SetVerticalScroll(v) self.scroll = v gen = gen + 1 end
function M:GetVerticalScroll() return self.scroll or 0 end

-- Draw -------------------------------------------------------------------

local function Push(r)
    r.dirty = false
    if r.kind == "FontString" then
        local c = r.color
        H:text(r.id, r.text or "", r.size, c[1], c[2], c[3], r.wrap ~= false, r.spacing or 0, r.w ~= nil,
            r.justify or "LEFT", r.font or "")
    elseif r.kind == "Texture" then
        local v = r.vertex or { 1, 1, 1, 1 }
        H:texture(r.id, r.texture or "", v[1], v[2], v[3], v[4], r.coord or "", r.grad or "", r.blend or "", r.rot or 0)
    elseif r.backdrop then
        local b, e = r.bg or { 0, 0, 0, 0 }, r.edge or { 0, 0, 0, 0 }
        H:backdrop(r.id, b[1], b[2], b[3], b[4], e[1], e[2], e[3], e[4])
    end
end

local function Draw(r, pl, pt)
    if not r.shown then
        if r.drawn ~= false then r.drawn = false H:hide(r.id) end
        return -- nothing below a hidden region is laid out
    end
    local rect = Resolve(r)
    local l, t, w, h = rect.l - pl, rect.t - pt, rect.w, rect.h
    if r.drawn ~= true or l ~= r.dl or t ~= r.dt or w ~= r.dw or h ~= r.dh then
        r.drawn, r.dl, r.dt, r.dw, r.dh = true, l, t, w, h
        H:place(r.id, l, t, w, h)
    end
    if r.dirty then Push(r) end
    for _, c in ipairs(r.children) do Draw(c, rect.l, rect.t) end
end

---------------------------------------------------------------------------
-- The game
---------------------------------------------------------------------------

local state = H.state
local level = math.floor(state.level or 1)
local zone, mapId = state.zone or "Tirisfal Glades", nil
local quests = {} -- quest id -> 1 in the log, 2 ready to hand in, 3 handed in
local zones, zoneOrder = { Undercity = 1458, Orgrimmar = 1454, ["Thunder Bluff"] = 1456 }, {}

local CLASSES = { WARRIOR = { "Warrior", 1 }, PALADIN = { "Paladin", 2 }, HUNTER = { "Hunter", 3 }, ROGUE = { "Rogue", 4 },
    PRIEST = { "Priest", 5 }, SHAMAN = { "Shaman", 7 }, MAGE = { "Mage", 8 }, WARLOCK = { "Warlock", 9 },
    DRUID = { "Druid", 11 } }
-- { name, race id, faction }. The Skyborne keys are this preview's own: the addon goes by the race id.
local RACES = { Orc = { "Orc", 2, "Horde" }, Scourge = { "Undead", 5, "Horde" }, Tauren = { "Tauren", 6, "Horde" },
    Troll = { "Troll", 8, "Horde" }, WindshaperSkyborne = { "Windshaper Skyborne", 96, "Horde" },
    Human = { "Human", 1, "Alliance" }, Dwarf = { "Dwarf", 3, "Alliance" }, NightElf = { "Night Elf", 4, "Alliance" },
    Gnome = { "Gnome", 7, "Alliance" }, HighOrderSkyborne = { "High Order Skyborne", 95, "Alliance" } }

UIParent = New("Frame", nil, 0)
function CreateColor(r, g, b, a)
    return { r = r, g = g, b = b, a = a or 1, GetRGBA = function(c) return c.r, c.g, c.b, c.a end }
end
UISpecialFrames = {}
SlashCmdList = {}
tinsert, tremove, wipe = table.insert, table.remove, function(t) for k in pairs(t) do t[k] = nil end return t end
strsplit = function(sep, s)
    local out = {}
    for part in (s .. sep):gmatch("(.-)" .. sep:gsub("%p", "%%%0")) do out[#out + 1] = part end
    return unpack(out)
end

function CreateFrame(kind, name, parent)
    local f = New(kind, parent or UIParent, 5)
    if kind == "Button" then
        f.clicks = { LeftButton = true }
        H:mouse(f.id)
    end
    if name then _G[name] = f end
    return f
end

function UnitLevel() return level end
function UnitClass()
    local file = state.class or "PALADIN"
    local c = CLASSES[file] or CLASSES.PALADIN
    return c[1], file, c[2]
end
function UnitRace()
    local file = state.race or "Scourge"
    local r = RACES[file] or RACES.Scourge
    return r[1], file, r[2]
end
function UnitFactionGroup()
    local r = RACES[state.race or "Scourge"] or RACES.Scourge
    return r[3], r[3]
end
function GetRealZoneText() return zone end
function GetBindLocation() return state.bind or "Brill" end

C_QuestLog = {
    IsQuestFlaggedCompleted = function(id) return quests[id] == 3 end,
    IsOnQuest = function(id) return quests[id] == 1 or quests[id] == 2 end,
    IsComplete = function(id) return quests[id] == 2 end,
    -- Made-up objectives, so the preview shows counts: half done in the log, all done when ready to hand in.
    GetQuestObjectives = function(id)
        local s = quests[id]
        if s ~= 1 and s ~= 2 then return nil end
        local need = 6 + id % 5
        return {
            { text = string.format("Preview foe slain: %d/%d", s == 2 and need or math.floor(need / 2), need), finished = s == 2 },
            { text = "Preview item found: 1/1", finished = true },
        }
    end,
}
C_Timer = { After = function(_, fn) fn() end } -- no waiting: the preview shows the result at once
C_Map = {
    GetBestMapForUnit = function() return mapId end,
    GetFallbackWorldMapID = function() return 947 end,
    GetMapInfo = function(id) return { mapID = id, name = id == 947 and "Azeroth" or "", parentMapID = id == 947 and 0 or 947 } end,
    GetMapChildrenInfo = function()
        local out = {}
        for name, id in pairs(zones) do out[#out + 1] = { name = name, mapID = id } end
        return out
    end,
    CanSetUserWaypointOnMap = function() return true end,
    SetUserWaypoint = function(p) H:pin(string.format("Map pin on map %d at %.1f, %.1f", p.map, p.x * 100, p.y * 100)) end,
}
UiMapPoint = { CreateFromCoordinates = function(map, x, y) return { map = map, x = x, y = y } end }
C_SuperTrack = { SetSuperTrackedUserWaypoint = function() end }

local arrow
TomTom = {
    AddWaypoint = function(_, map, x, y, opts)
        local uid = { map = map, x = x, y = y, title = opts and opts.title or "" }
        local text = string.format("%s  (map %d: %.1f, %.1f)", uid.title, map, x * 100, y * 100)
        if opts and opts.crazy then
            arrow = uid
            H:arrow(text)
        else
            H:pin("TomTom waypoint: " .. text)
        end
        return uid
    end,
    RemoveWaypoint = function(_, uid)
        if uid == arrow then arrow = nil H:arrow("") end
    end,
}

GameTooltip = setmetatable({
    SetOwner = function(self) self.link, self.lines = nil, {} end,
    SetHyperlink = function(self, link) self.link = link end,
    AddLine = function(self, text)
        self.lines = self.lines or {}
        self.lines[#self.lines + 1] = tostring(text)
    end,
    Show = function(self)
        if self.link then H:tooltip(self.link) else H:tip(table.concat(self.lines or {}, "\n")) end
    end,
    Hide = function() H:tooltip("") end,
}, { __index = function() return function() end end })
UIErrorsFrame = { AddMessage = function(_, msg) H:alert(tostring(msg)) end }

print = function(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
    H:chat(table.concat(parts, " "))
end

---------------------------------------------------------------------------
-- Driving it
---------------------------------------------------------------------------

local function Serialize(v, out)
    local t = type(v)
    if t == "table" then
        out[#out + 1] = "{"
        for k, x in pairs(v) do
            local kt = type(k)
            if (kt == "string" or kt == "number") and type(x) ~= "function" and type(x) ~= "userdata" then
                out[#out + 1] = "[" .. (kt == "string" and string.format("%q", k) or tostring(k)) .. "]="
                Serialize(x, out)
                out[#out + 1] = ","
            end
        end
        out[#out + 1] = "}"
    elseif t == "string" then
        out[#out + 1] = string.format("%q", v)
    else
        out[#out + 1] = tostring(v)
    end
end

-- Draws what changed and keeps the saved variables and quest states for the next reload.
local function Flush()
    Draw(UIParent, 0, 0)
    local db, ids, vars = {}, {}, {}
    for i = 0, H.savedNames.length - 1 do vars[H.savedNames[i]] = _G[H.savedNames[i]] end
    Serialize(vars, db)
    for id, s in pairs(quests) do ids[#ids + 1] = id .. "=" .. s end
    H:persist(table.concat(db), table.concat(ids, ";"))
end

local function Safe(fn, ...)
    local ok, err = xpcall(fn, debug.traceback, ...)
    if not ok then H:fail(tostring(err)) end
    return ok
end

local function Fire(event, ...)
    for _, f in ipairs(eventFrames) do
        if f.events[event] and f.scripts.OnEvent then Safe(f.scripts.OnEvent, f, event, ...) end
    end
end

-- The stage open in the window: the list row drawn with the selected background.
local function SelectedStage(ns)
    local w = UndeadRouteFrame
    if not (w and w.rows) then return end
    for i, row in ipairs(w.rows) do
        local v = row.bg and row.bg.vertex
        if v and v[4] == 1 then return ns.Stages[i] end
    end
end

local ns = {}
local STATE_NAME = { [0] = "not in the log", "in the log", "ready to hand in", "handed in" }

-- Shift-click on a quest step is the preview's own control: it moves that quest one state on.
local function CycleQuest(row)
    local stage = SelectedStage(ns)
    local task = stage and stage.tasks[row.index]
    local id = task and task.id
    if not id then
        H:note("That step is a tip, not a quest: it has no quest state.")
        return
    end
    local s = ((quests[id] or 0) + 1) % 4
    quests[id] = s > 0 and s or nil
    H:note(string.format("Quest %d (%s): %s", id, task.quest and task.quest.name or "?", STATE_NAME[s]))
    if s == 1 then Fire("QUEST_ACCEPTED", id) end
    if s == 3 then Fire("QUEST_TURNED_IN", id) end
    Fire("QUEST_LOG_UPDATE")
end

H.dispatch = function(_, id, what, a, b)
    local r = regions[id]
    if not r then return end
    local s = r.scripts
    if what == "click" then
        if b and rawget(r, "index") and rawget(r, "lv") then
            Safe(CycleQuest, r)
        else
            if r.clicks and r.clicks[a] and s.OnClick then Safe(s.OnClick, r, a) end
            if s.OnMouseUp then Safe(s.OnMouseUp, r, a) end
        end
    elseif what == "enter" then
        if s.OnEnter then Safe(s.OnEnter, r) end
    elseif what == "leave" then
        if s.OnLeave then Safe(s.OnLeave, r) end
    elseif what == "wheel" then
        if s.OnMouseWheel then Safe(s.OnMouseWheel, r, a) end
    elseif what == "dragstart" then
        local rect = Resolve(r)
        r.dragFrom = { rect.l, rect.t }
        if s.OnDragStart then Safe(s.OnDragStart, r) end
    elseif what == "drag" then
        if r.moving and r.dragFrom then
            r.points = { { point = "TOPLEFT", rel = UIParent, relPoint = "TOPLEFT", x = r.dragFrom[1] + a,
                y = -(r.dragFrom[2] + b) } }
            gen = gen + 1
        end
    elseif what == "dragstop" then
        if s.OnDragStop then Safe(s.OnDragStop, r) end
    elseif what == "text" then
        r.text = tostring(a or "")
        if s.OnTextChanged then Safe(s.OnTextChanged, r, true) end
    elseif what == "enterkey" then
        if s.OnEnterPressed then Safe(s.OnEnterPressed, r) end
    elseif what == "escape" then
        if s.OnEscapePressed then Safe(s.OnEscapePressed, r) end
    elseif what == "focus" then
        if s.OnEditFocusGained then Safe(s.OnEditFocusGained, r) end
    elseif what == "blur" then
        if s.OnEditFocusLost then Safe(s.OnEditFocusLost, r) end
    end
    Flush()
end

local Sim = js.new(window.Object)
window.Sim = Sim

Sim.setLevel = function(_, n)
    level = math.floor(n)
    Fire("PLAYER_LEVEL_UP", level)
    Flush()
end
Sim.setZone = function(_, name)
    zone, mapId = name, zones[name]
    Fire("ZONE_CHANGED_NEW_AREA")
    Flush()
end
Sim.event = function(_, name)
    Fire(name)
    Flush()
end
local function Slash(text)
    local cmd, rest = text:match("^%s*(/%S+)%s*(.-)%s*$")
    if not cmd then return false end
    for key, fn in pairs(SlashCmdList) do
        local i = 1
        while _G["SLASH_" .. key .. i] do
            if _G["SLASH_" .. key .. i]:lower() == cmd:lower() then
                Safe(fn, rest)
                Flush()
                return true
            end
            i = i + 1
        end
    end
    return false
end
Sim.slash = function(_, text) return Slash(text) end
Sim.escape = function()
    for _, name in ipairs(UISpecialFrames) do
        if _G[name] and _G[name].Hide then _G[name]:Hide() end
    end
    Flush()
end
-- A tenth of a second passes: every visible frame with an OnUpdate script runs it.
Sim.tick = function(_, elapsed)
    if next(updaters) == nil then return end
    for _, r in pairs(updaters) do
        if r:IsVisible() then Safe(r.scripts.OnUpdate, r, elapsed) end
    end
    Draw(UIParent, 0, 0)
end
Sim.resize = function()
    gen = gen + 1
    Flush()
end
Sim.resetQuests = function()
    quests = {}
    Fire("QUEST_LOG_UPDATE")
    Flush()
end

-- Saved variables and quest states from the last run.
if H.saved and H.saved ~= "" then
    local fn = load("return " .. H.saved)
    local ok, value = pcall(fn or error)
    if ok and type(value) == "table" then
        for name, v in pairs(value) do _G[name] = v end
    end
end
for id, s in (H.savedQuests or ""):gmatch("(%d+)=(%d)") do quests[tonumber(id)] = tonumber(s) end

-- Game functions this preview lacks, brought by the addon being shown (tools/preview-env.lua).
if H.env and H.env ~= "" then
    local fn, err = load(H.env, "@preview-env.lua")
    if not fn then
        H:fail(tostring(err))
    else
        Safe(fn, { H = H, state = state, Level = function() return level end })
    end
end

-- Load the addon's files in .toc order, as the game does.
local loaded = true
for i = 0, H.files.length - 1 do
    local name = H.files[i]
    local fn, err = load(H.sources[name], "@" .. name)
    if not fn then
        H:fail(tostring(err))
        loaded = false
        break
    end
    if not Safe(fn, H.addon, ns) then loaded = false break end
end

if loaded then
    -- The zones the route knows, for the panel's zone list and for C_Map.
    for _, s in ipairs(ns.Stages or {}) do
        if s.zone and s.maps and s.maps[1] and not zones[s.zone] then zones[s.zone] = s.maps[1] end
    end
    for name in pairs(zones) do zoneOrder[#zoneOrder + 1] = name end
    table.sort(zoneOrder)
    for _, name in ipairs(zoneOrder) do H:zone(name) end
    if not zones[zone] then zone = "Tirisfal Glades" end
    mapId = zones[zone]

    Fire("ADDON_LOADED", H.addon)
    Fire("PLAYER_LOGIN")
    Slash(H.start) -- start with the window open
end
Flush()
