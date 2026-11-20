local ADDON, ns = ...
local T = ns.T

-- Dungeon guide: a map of the dungeon with the way through it drawn on, step by step: entrance, the
-- first boss, the next... Inside an instance the game hides where you stand (UnitPosition and
-- C_Map.GetPlayerMapPosition give no x and y there, on purpose), so no addon can put a dot on you.
-- What the game does say is enough to follow a route: which floor you are on (C_Map.GetBestMapForUnit),
-- the name of the room (GetSubZoneText) and which boss just died (ENCOUNTER_END, BOSS_KILL). So the
-- guide turns to your floor, moves on when a boss dies, and marks "about here": the room you are in,
-- once a kill there taught it the room's name, else the last boss you killed.
--
-- Routes are in Modules\GuideData.lua. Your own changes (a moved spot, bends in the line) are kept
-- account-wide in ZodUIDB.guide.edits and travel as one line of text (/zod guide export), read as data
-- and checked field by field, never run. Where you are in a run is kept per character.

local M = ns:NewModule("guide", {
    title = "Dungeon guide",
    desc = "A map of the dungeon with the route drawn on: entrance, then each boss in turn. It turns to your floor and moves on when a boss dies. /zod guide sfk, rfk or sm opens one.",
    needs = { "ForeverDungeonJournal" },
    defaults = { enabled = true, auto = true },
    options = {
        { type = "check", key = "auto", label = "Open the guide when I enter a dungeon it knows" },
        { type = "note", text = "The game hides your exact spot inside dungeons, so the guide follows floors, room names and boss kills. /zod guide draw lets you fix the line; /zod guide export shares it.", lines = 3 },
    },
})

local SCALE = 0.5
local MAP_W, MAP_H = 1002 * SCALE, 668 * SCALE
local TILE = 256 * SCALE
local FRESH = 45 * 60 -- a run not seen for this long starts over
local TAG = "ZGR1"
local MAX_VIA = 20
local MAX_SHARE = 4000

local LINE_DONE = { 0.55, 0.55, 0.55, 0.9 }
local LINE_NEXT = { 1, 0.85, 0.1, 1 }
local LINE_LATER = { 0.95, 0.95, 0.95, 0.95 }

local win -- the window, made on first use
local shownKey, shownFloor, pickedFloor, autoOpened
local drawing

---------------------------------------------------------------------------
-- Routes and your edits
---------------------------------------------------------------------------

local function Plain(v)
    if issecretvalue and issecretvalue(v) then return nil end
    return v
end

function M.Guide(key) return ns.GUIDES and ns.GUIDES[key] end

-- Whether ForeverDungeonJournal is on: its map art is used for the dungeons the client has none for.
function M.JournalArt()
    local loaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
    return loaded and loaded("ForeverDungeonJournal") and true or false
end

-- The wing of a group (Scarlet Monastery) to show: the one you went to last, else its first.
function M.Wing(group)
    local w = ns.chardb.guideWing
    if w and ns.GUIDES[w] and ns.GUIDES[w].group == group then return w end
    return ns.GUIDE_GROUPS[group].default
end

-- The guide named by `text`: its key, its name or one of its words ("shadowfang", "gy"); a whole
-- group ("sm") gives the wing you went to last.
function M.Lookup(text)
    local lower = (text or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if lower == "" then return nil end
    for key, g in pairs(ns.GUIDES or {}) do
        if key == lower or g.name:lower() == lower then return key end
        for _, w in ipairs(g.words or {}) do
            if w == lower then return key end
        end
    end
    for group, info in pairs(ns.GUIDE_GROUPS or {}) do
        if info.name:lower() == lower then return M.Wing(group) end
        for _, w in ipairs(info.words) do
            if w == lower then return M.Wing(group) end
        end
    end
end

local function BestMap()
    if not (C_Map and C_Map.GetBestMapForUnit) then return nil end
    local ok, map = pcall(C_Map.GetBestMapForUnit, "player")
    return ok and Plain(map) or nil
end

local function Room()
    local room = Plain(GetSubZoneText and GetSubZoneText())
    return type(room) == "string" and room ~= "" and room or nil
end

-- The guide for the instance you are in, or nil. Wings sharing one instance (Scarlet Monastery) are
-- told apart by the floor map, then the room's name, then the wing a kill or you settled on.
function M.Here()
    if not (IsInInstance and IsInInstance()) then return nil end
    local name, _, _, _, _, _, _, id = GetInstanceInfo()
    name, id = Plain(name), Plain(id)
    local found = {}
    for key, g in pairs(ns.GUIDES or {}) do
        if (id and id == g.instance) or (name and (name == g.name or name == g.zone)) then found[#found + 1] = key end
    end
    if #found <= 1 then return found[1] end
    table.sort(found)
    local map = BestMap()
    -- What the map or the room says for sure is remembered, for the rooms that say nothing.
    for _, key in ipairs(found) do
        for _, f in ipairs(ns.GUIDES[key].floors) do
            if map and f.map == map then ns.chardb.guideWing = key return key end
        end
    end
    local room = Room()
    room = room and room:lower()
    for _, key in ipairs(found) do
        for _, r in ipairs(ns.GUIDES[key].rooms or {}) do
            if r == room then ns.chardb.guideWing = key return key end
        end
    end
    local group = ns.GUIDES[found[1]].group
    return group and M.Wing(group) or found[1]
end

local function Saved()
    local s = ns.db.guide
    if not s then
        s = { edits = {}, rooms = {} }
        ns.db.guide = s
    end
    s.edits, s.rooms = s.edits or {}, s.rooms or {}
    return s
end

local function Edits(key, create)
    local all = Saved().edits
    if create and not all[key] then all[key] = {} end
    return all[key]
end

-- The steps of a route with your edits on top: copies, so drawing never changes GuideData.
function M.Steps(key)
    local g, out = M.Guide(key), {}
    if not g then return out end
    local edits = Edits(key) or {}
    local traced = ns.GUIDE_TRACED and ns.GUIDE_TRACED[key] or {}
    for i, s in ipairs(g.steps) do
        local e = edits[i] or {}
        local step = {}
        for k, v in pairs(s) do step[k] = v end
        if traced[i] then step.via = traced[i] end -- the corridors' bends, from tools/trace_routes.py
        if e.x then step.floor, step.x, step.y = e.floor, e.x, e.y end
        if e.via then step.via = e.via end
        step.i, step.edited = i, edits[i] ~= nil
        out[i] = step
    end
    return out
end

---------------------------------------------------------------------------
-- Where you are in the run
---------------------------------------------------------------------------

local function Runs()
    if not ns.chardb.guides then
        ns.chardb.guides = {}
        ns.chardb.guide = nil -- 0.44's single run
    end
    return ns.chardb.guides
end

local function Run(key)
    local runs = Runs()
    runs[key] = runs[key] or { done = {}, seen = time() }
    return runs[key]
end
M.Run = Run

-- Starts the run over when it was left long ago (a new run, most likely).
function M.Fresh(key)
    local r = Runs()[key]
    if r and time() - (r.seen or 0) <= FRESH then
        r.seen = time()
        return r
    end
    Runs()[key] = nil
    return Run(key)
end

-- The step to go to next: the one after the furthest step done.
function M.Current(key)
    local r, steps = Run(key), M.Steps(key)
    local last = 0
    for i = 1, #steps do
        if r.done[i] then last = i end
    end
    return math.min(last + 1, #steps), last
end

local function Matches(step, id, name)
    if id and step.boss then
        for _, b in ipairs(step.boss) do
            if b == id then return true end
        end
    end
    return name ~= nil and (name == step.title or name == step.name)
end

-- A boss died in `key`'s dungeon: its step and the plain steps before it are done, and the room it
-- died in is learned. Returns the step, or nil when the boss is not on this route.
local function KillIn(key, id, name)
    local steps = M.Steps(key)
    for i, step in ipairs(steps) do
        if Matches(step, id, name) then
            local r = Run(key)
            r.seen = time()
            r.done[i] = true
            for j = i - 1, 1, -1 do
                if steps[j].boss then break end
                r.done[j] = true
            end
            local room = Plain(GetSubZoneText and GetSubZoneText())
            if type(room) == "string" and room ~= "" then
                local rooms = Saved().rooms
                rooms[key] = rooms[key] or {}
                rooms[key][i] = room
            end
            local nextI = M.Current(key)
            local nxt = steps[nextI]
            -- With the guide open in full the window says it (and chat); hidden or folded, also a notice,
            -- which is easier to see in the middle of a fight than a chat line.
            local say = (M.Shown() and not M.db.folded) and ns.Print or ns.Alert
            if nextI == i then
                say("Dungeon guide: " .. step.title .. " done, that was the last of " .. M.Guide(key).name .. ".")
            else
                say("Dungeon guide: next, " .. nextI .. ". " .. nxt.title .. ". " .. nxt.text)
            end
            return i
        end
    end
end

-- A boss died. In a group of wings, a boss of another wing tells which wing you are in.
function M:Kill(id, name)
    id, name = tonumber(Plain(id)), Plain(name)
    local key = M.Here() or shownKey
    if not key then return nil end
    local tries, group = { key }, M.Guide(key).group
    if group then
        for k, g in pairs(ns.GUIDES) do
            if g.group == group and k ~= key then tries[#tries + 1] = k end
        end
    end
    for _, k in ipairs(tries) do
        local i = KillIn(k, id, name)
        if i then
            if group then ns.chardb.guideWing = k end
            if M.Shown() and k ~= shownKey then M:Show(k) else M:Draw() end
            return i, k
        end
    end
end

-- Your floor (an index into the route's floors), or nil when the game does not say.
function M.Floor(key)
    local g = M.Guide(key)
    if not g then return nil end
    local map = BestMap()
    for i, f in ipairs(g.floors) do
        if f.map == map then return i end
    end
end

-- About where you are: { step, floor, room, how = "room" | "last" | "start" }.
function M.Where(key)
    local room = Room()
    local floor = M.Floor(key)
    local steps = M.Steps(key)
    local rooms = Saved().rooms[key]
    if room and rooms then
        local best
        for i, r in pairs(rooms) do
            local s = steps[i]
            if r == room and s and s.x and (not floor or s.floor == floor) and (not best or i > best) then best = i end
        end
        if best then return { step = best, floor = floor or steps[best].floor, room = room, how = "room" } end
    end
    local _, last = M.Current(key)
    for i = last, 1, -1 do
        local s = steps[i]
        if s.x and (not floor or s.floor == floor) then return { step = i, floor = floor or s.floor, room = room, how = "last" } end
    end
    return { step = nil, floor = floor, room = room, how = "start" }
end

function M:Next()
    if not shownKey then return end
    local cur = M.Current(shownKey)
    Run(shownKey).done[cur] = true
    pickedFloor = nil
    M:Draw()
end

function M:Back()
    if not shownKey then return end
    local _, last = M.Current(shownKey)
    if last > 0 then Run(shownKey).done[last] = nil end
    pickedFloor = nil
    M:Draw()
end

function M:StartOver()
    if not shownKey then return end
    Runs()[shownKey] = nil
    Run(shownKey)
    pickedFloor = nil
    M:Draw()
end

---------------------------------------------------------------------------
-- Drawing your own line
---------------------------------------------------------------------------

-- The step the draw mode changes: the next one.
function M.Editing() return shownKey and (M.Current(shownKey)) end

local function Round(v) return math.floor(v * 1000 + 0.5) / 1000 end

-- A click on the map at x, y (0..1) of the floor shown. Left adds a bend to the line into the step,
-- shift-left puts the step's own spot there, right takes the last bend away.
function M:Click(x, y, mouse, shift)
    if not (drawing and shownKey and shownFloor) then return false end
    if type(x) ~= "number" or type(y) ~= "number" or x < 0 or x > 1 or y < 0 or y > 1 then return false end
    local i = M.Editing()
    local step = M.Steps(shownKey)[i]
    local edits = Edits(shownKey, true)
    local e = edits[i] or {}
    if mouse == "RightButton" then
        local via = {}
        for _, p in ipairs(step.via or {}) do via[#via + 1] = p end
        if #via == 0 then return false end
        table.remove(via)
        e.via = via
    elseif shift then
        e.floor, e.x, e.y = shownFloor, Round(x), Round(y)
    else
        local via = {}
        for _, p in ipairs(step.via or {}) do via[#via + 1] = p end
        if #via >= MAX_VIA then return false end
        via[#via + 1] = { shownFloor, Round(x), Round(y) }
        e.via = via
    end
    edits[i] = e
    M:Draw()
    return true
end

-- Takes your changes to the route away.
function M:Clear(key)
    key = key or shownKey
    local all = Saved().edits
    if key then all[key] = nil end
    M:Draw()
end

local function Num(v) return string.format("%.3f", v):gsub("0+$", ""):gsub("%.$", "") end

-- Your changes as one line: "ZGR1 sfk 7@2:0.64:0.42 9~2:0.6:0.7~2:0.61:0.8".
function M.Export(key)
    local edits = Edits(key)
    local parts = { TAG, key }
    if edits then
        local list = {}
        for i in pairs(edits) do list[#list + 1] = i end
        table.sort(list)
        for _, i in ipairs(list) do
            local e = edits[i]
            if e.x then parts[#parts + 1] = i .. "@" .. e.floor .. ":" .. Num(e.x) .. ":" .. Num(e.y) end
            if e.via then
                local bits = { i .. "~" }
                for n, p in ipairs(e.via) do bits[#bits + 1] = (n > 1 and "~" or "") .. p[1] .. ":" .. Num(p[2]) .. ":" .. Num(p[3]) end
                parts[#parts + 1] = table.concat(bits)
            end
        end
    end
    return table.concat(parts, " ")
end

local function Point(text, floors)
    local f, x, y = text:match("^(%d+):([%d%.]+):([%d%.]+)$")
    f, x, y = tonumber(f), tonumber(x), tonumber(y)
    if f and x and y and f >= 1 and f <= floors and x >= 0 and x <= 1 and y >= 0 and y <= 1 then return f, x, y end
end

-- Reads a shared line. Returns the guide's key, or nil and why not. Nothing is changed unless all of it reads.
function M.Import(text)
    if type(text) ~= "string" or #text > MAX_SHARE then return nil, "that is not a route line." end
    text = text:gsub("^%s+", ""):gsub("%s+$", "")
    local tag, key, rest = text:match("^(%S+)%s+(%l+)%s*(.-)$")
    if tag ~= TAG then return nil, "that is not a route line." end
    local g = M.Guide(key)
    if not g then return nil, "no guide for '" .. tostring(key) .. "'." end
    local edits, floors = {}, #g.floors
    for token in rest:gmatch("%S+") do
        local i, spot = token:match("^(%d+)@(.+)$")
        local j, via = token:match("^(%d+)~(.*)$")
        i, j = tonumber(i), tonumber(j)
        if i and g.steps[i] then
            local f, x, y = Point(spot, floors)
            if not f then return nil, "step " .. i .. " has a spot that does not read." end
            edits[i] = edits[i] or {}
            edits[i].floor, edits[i].x, edits[i].y = f, x, y
        elseif j and g.steps[j] then
            local list = {}
            for p in (via .. "~"):gmatch("([^~]*)~") do
                if p ~= "" then
                    local f, x, y = Point(p, floors)
                    if not f then return nil, "step " .. j .. " has a bend that does not read." end
                    list[#list + 1] = { f, x, y }
                end
            end
            if #list > MAX_VIA then return nil, "step " .. j .. " has too many bends." end
            edits[j] = edits[j] or {}
            edits[j].via = list
        else
            return nil, "'" .. token:sub(1, 20) .. "' does not read."
        end
    end
    if not next(edits) then return nil, "that route line has nothing drawn in it." end -- it would wipe yours
    Saved().edits[key] = edits
    M:Draw()
    return key, "took the route for " .. g.name .. "."
end

---------------------------------------------------------------------------
-- The window
---------------------------------------------------------------------------

local function Pool(list, make)
    list.used = 0
    return function()
        list.used = list.used + 1
        local item = list[list.used]
        if not item then
            item = make()
            list[list.used] = item
        end
        item:Show()
        return item
    end
end

local function HideRest(list)
    for i = list.used + 1, #list do list[i]:Hide() end
end

local function MakePin(parent)
    local p = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    p:SetSize(18, 18)
    p:SetFrameLevel(parent:GetFrameLevel() + 3)
    p.num = T.Text(p, "GameFontHighlightSmall")
    p.num:SetPoint("CENTER", 0, 0)
    p.num:SetJustifyH("CENTER")
    p:EnableMouse(true)
    p:SetScript("OnEnter", function(self) T.ShowTip(self, self.tipTitle, self.tip) end)
    p:SetScript("OnLeave", function() T.HideTip() end)
    return p
end

local function Build()
    local f = CreateFrame("Frame", "ZodUIGuide", UIParent, "BackdropTemplate")
    f:SetSize(MAP_W + 20, MAP_H + 132)
    f:SetFrameStrata("MEDIUM")
    T.Window(f, T.WINDOW, 0.96, T.GOLD)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, rel, x, y = self:GetPoint(1)
        M.db.pos = { point, rel, x, y }
    end)
    local pos = M.db.pos
    if pos then f:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4]) else f:SetPoint("RIGHT", UIParent, "RIGHT", -40, 40) end
    f:SetScale(M.db.scale or 1)
    f:Hide()
    tinsert(UISpecialFrames, "ZodUIGuide")
    -- The corner grip makes the guide, map and all, bigger or smaller.
    f.grip = T.ScaleGrip(f, { min = 0.6, max = 1.8, set = function(scale, point, rel, x, y)
        M.db.scale = math.abs(scale - 1) > 0.005 and scale or nil
        M.db.pos = { point, rel, x, y }
    end })

    f.title = T.Text(f, "GameFontNormal", T.GOLD)
    f.title:SetPoint("TOPLEFT", 10, -10)
    f.close = T.Close(f, function() M:Hide() end)
    f.close:SetPoint("TOPRIGHT", -8, -6)
    -- Folds the guide to its essentials: the next step and about where you are, without the map.
    f.fold = T.Button(f, "-", 22, function()
        M.db.folded = (not M.db.folded) or nil
        local point, rel, x, y = T.PinTop(f) -- the title stays where it is; the window grows or shrinks below it
        if point then M.db.pos = { point, rel, x, y } end
        if M.db.folded and drawing then M:Draw(false) else M:Draw() end
    end)
    f.fold:SetPoint("RIGHT", f.close, "LEFT", -4, 0)
    f.fold.tipTitle = "Fold"
    f.floors = {}

    local map = CreateFrame("Frame", nil, f)
    map:SetSize(MAP_W, MAP_H)
    map:SetPoint("TOPLEFT", 10, -36)
    map:SetClipsChildren(true)
    map:EnableMouse(true)
    -- The mouse wheel over the map steps through the route: down for the next step, up for the one before.
    map:EnableMouseWheel(true)
    map:SetScript("OnMouseWheel", function(_, delta)
        if drawing then return end
        if delta < 0 then M:Next() else M:Back() end
    end)
    map:SetScript("OnMouseUp", function(self, mouse)
        if not drawing then return end
        local cx, cy = GetCursorPosition()
        local s = self:GetEffectiveScale()
        local left, top = self:GetLeft(), self:GetTop()
        if not (left and top) then return end
        M:Click((cx / s - left) / MAP_W, (top - cy / s) / MAP_H, mouse, IsShiftKeyDown and IsShiftKeyDown())
    end)
    f.map = map
    f.tiles = {}
    for i = 1, 12 do
        local t = map:CreateTexture(nil, "BACKGROUND")
        t:SetSize(TILE, TILE)
        t:SetPoint("TOPLEFT", map, "TOPLEFT", ((i - 1) % 4) * TILE, -math.floor((i - 1) / 4) * TILE)
        f.tiles[i] = t
    end
    -- Map art of ForeverDungeonJournal's own (the Forever dungeons, Zul'Farrak...): one texture whose
    -- top-left part is the map.
    f.art = map:CreateTexture(nil, "BACKGROUND")
    f.art:SetAllPoints(map)
    f.noart = T.Text(map, "GameFontHighlight", T.DIM)
    f.noart:SetPoint("CENTER", map, "CENTER", 0, 0)
    f.noart:SetJustifyH("CENTER")
    f.noart:SetWidth(MAP_W - 40)
    f.lines, f.pins = {}, {}
    f.you = CreateFrame("Frame", nil, map, "BackdropTemplate")
    f.you:SetSize(30, 30)
    f.you:SetBackdrop({ edgeFile = T.WHITE, edgeSize = 2 })
    f.you:SetBackdropBorderColor(0.3, 0.8, 1, 1)
    f.you:SetFrameLevel(map:GetFrameLevel() + 2)
    f.you.label = T.Text(f.you, "GameFontHighlightSmall", { 0.3, 0.8, 1 })
    f.you.label:SetPoint("TOP", f.you, "BOTTOM", 0, -1)
    f.you.label:SetText("about here")

    f.next = T.Text(f, "GameFontHighlight")
    f.next:SetPoint("TOPLEFT", map, "BOTTOMLEFT", 0, -8)
    f.next:SetWidth(MAP_W)
    f.where = T.Text(f, "GameFontHighlightSmall", T.DIM)
    f.where:SetPoint("TOPLEFT", f.next, "BOTTOMLEFT", 0, -4)
    f.where:SetWidth(MAP_W)

    f.back = T.Button(f, "Back", 60, function() M:Back() end)
    f.back:SetPoint("BOTTOMLEFT", 10, 10)
    f.fwd = T.Button(f, "Next", 60, function() M:Next() end)
    f.fwd:SetPoint("LEFT", f.back, "RIGHT", 6, 0)
    f.fwd.tip = "Or turn the mouse wheel down over the map. A key can do it too: Options > Keybindings > ZodUI."
    f.back.tip = "Or turn the mouse wheel up over the map."
    f.over = T.Button(f, "Start over", 84, function() M:StartOver() end)
    f.over:SetPoint("LEFT", f.fwd, "RIGHT", 6, 0)
    f.over.confirm = "Sure?"
    f.draw = T.Button(f, "Draw", 60, function() M:Draw(not drawing) end)
    f.draw:SetPoint("BOTTOMRIGHT", -22, 10) -- clear of the size grip
    f.draw.tipTitle, f.draw.tip = "Draw the route", "Click the map to bend the line into the next step; shift-click puts the step itself there; right-click takes the last bend away."
    f.share = T.Button(f, "Share", 60, function()
        ns.ShareBox("export", { title = "Your route for " .. M.Guide(shownKey).name, text = M.Export(shownKey) })
    end)
    f.share:SetPoint("RIGHT", f.draw, "LEFT", -6, 0)
    f.take = T.Button(f, "Take", 60, function()
        ns.ShareBox("import", { title = "Take a route", hint = "Paste a route line here (Ctrl+V). It changes only the drawn route.",
            apply = "Take this route", take = function(text) local _, said = M.Import(text) return said end })
    end)
    f.take:SetPoint("RIGHT", f.share, "LEFT", -6, 0)
    return f
end

-- One piece of the route: a dark edge under a thick coloured line, so it reads on light and dark map art.
local function Line(f, a, b, color)
    for n = 1, 2 do
        local l = f.nextLine()
        l:SetDrawLayer("ARTWORK", n)
        l:SetThickness(n == 1 and 8 or 4)
        if n == 1 then l:SetColorTexture(0, 0, 0, 0.8) else l:SetColorTexture(color[1], color[2], color[3], color[4]) end
        l:SetStartPoint("TOPLEFT", f.map, a[1] * MAP_W, -a[2] * MAP_H)
        l:SetEndPoint("TOPLEFT", f.map, b[1] * MAP_W, -b[2] * MAP_H)
    end
end

-- The route's points from step i-1 to step i, each { floor, x, y }.
local function Leg(steps, i)
    local pts, prev = {}, nil
    for j = i - 1, 1, -1 do
        if steps[j].x then prev = steps[j] break end
    end
    if prev then pts[1] = { prev.floor, prev.x, prev.y } end
    for _, p in ipairs(steps[i].via or {}) do pts[#pts + 1] = p end
    local s = steps[i]
    if s.x then pts[#pts + 1] = { s.floor, s.x, s.y } end
    return pts
end

-- Draws the guide again; with `draw` given, turns the draw mode on or off first.
function M:Draw(draw)
    if draw ~= nil then
        drawing = draw and true or nil
        if win then win.draw.label:SetText(drawing and "Done" or "Draw") end
        -- How to draw is said the first time; after that the title's "(drawing)", the Done button and its tip say it.
        if drawing and not M.db.drawTold then M.db.drawTold = true ns.Print("Dungeon guide: drawing. Click the map to bend the line into the next step, shift-click to put the step there, right-click to undo. Done when you are.") end
    end
    if not (win and win:IsShown() and shownKey) then return end
    local g, steps = M.Guide(shownKey), M.Steps(shownKey)
    local cur, last = M.Current(shownKey)
    local where = M.Where(shownKey)
    local floor = pickedFloor or where.floor or steps[cur].floor or 1
    shownFloor = floor
    local fl = g.floors[floor]

    local group = g.group and ns.GUIDE_GROUPS[g.group]
    -- A wing's own name is on its button, so its one floor is not named again.
    local floorName = (group and #g.floors == 1) and "" or ("  " .. fl.name)
    win.title:SetText((group and group.name or g.name) .. "|cff999999" .. floorName .. (drawing and "  (drawing)" or "") .. "|r")
    local art = fl.texture and M.JournalArt() and "texture" or (fl.tiles and "tiles") or nil
    for i = 1, 12 do
        win.tiles[i]:SetShown(art == "tiles")
        if art == "tiles" then win.tiles[i]:SetTexture(fl.tiles .. i) end
    end
    win.art:SetShown(art == "texture")
    if art == "texture" then
        win.art:SetTexture(fl.texture)
        win.art:SetTexCoord(0, fl.texRight or 1, 0, fl.texBottom or 1)
    end
    win.noart:SetShown(art == nil)
    win.noart:SetText(fl.texture and "This map's picture needs the ForeverDungeonJournal addon: with it installed and on, the map shows here."
        or "No map of this dungeon yet. The steps below still follow the bosses.")
    -- Wings of one instance: a button each, to switch by hand when the game cannot tell them apart.
    local wings = {}
    if group then
        for k, w in pairs(ns.GUIDES) do
            if w.group == g.group then wings[#wings + 1] = k end
        end
        table.sort(wings, function(a, b) return ns.GUIDES[a].order < ns.GUIDES[b].order end)
    end
    win.wings = win.wings or {}
    for n, k in ipairs(wings) do
        local b = win.wings[n]
        if not b then
            b = T.Button(win, "", 66, function(self)
                ns.chardb.guideWing = self.key
                M:Show(self.key)
            end)
            win.wings[n] = b
        end
        b.key = k
        b.label:SetText(ns.GUIDES[k].short)
        local on = k == shownKey
        b.label:SetTextColor(on and T.GOLD[1] or 1, on and T.GOLD[2] or 1, on and T.GOLD[3] or 1)
        b.tipTitle, b.tip = ns.GUIDES[k].name, on and "Shown now." or "Show this wing."
        b:ClearAllPoints()
        b:SetPoint("TOPRIGHT", win, "TOPRIGHT", -60 - (#wings - n) * 70, -6)
        b:Show()
    end
    for n = #wings + 1, #win.wings do win.wings[n]:Hide() end
    for i, fd in ipairs(g.floors) do
        local b = win.floors[i]
        if not b then
            b = T.Button(win, tostring(i), 22, function() pickedFloor = i M:Draw() end)
            win.floors[i] = b
        end
        b.tipTitle = fd.name
        b:SetShown(#g.floors > 1)
        b:ClearAllPoints()
        b:SetPoint("TOPRIGHT", win, "TOPRIGHT", -60 - #wings * 70 - (#g.floors - i) * 26, -6)
        b.label:SetTextColor(i == floor and T.GOLD[1] or 1, i == floor and T.GOLD[2] or 1, i == floor and T.GOLD[3] or 1)
        b.tip = (i == where.floor and "You are on this floor." or "Show this floor.")
    end
    for i = #g.floors + 1, #win.floors do win.floors[i]:Hide() end
    -- The title gets what the buttons leave, cut short rather than running under them.
    win.title:SetWidth(math.max(80, MAP_W - 50 - #wings * 70 - (#g.floors > 1 and #g.floors * 26 or 0)))
    win.title:SetWordWrap(false)

    win.nextLine = Pool(win.lines, function() return win.map:CreateLine(nil, "ARTWORK") end)
    win.nextPin = Pool(win.pins, function() return MakePin(win.map) end)
    for i = 2, #steps do
        local pts = Leg(steps, i)
        local color = i <= last and LINE_DONE or (i == cur and LINE_NEXT or LINE_LATER)
        for n = 2, #pts do
            if pts[n - 1][1] == floor and pts[n][1] == floor then
                Line(win, { pts[n - 1][2], pts[n - 1][3] }, { pts[n][2], pts[n][3] }, color)
            end
        end
    end
    for i, s in ipairs(steps) do
        if s.x and s.floor == floor then
            local p = win.nextPin()
            p:ClearAllPoints()
            p:SetPoint("CENTER", win.map, "TOPLEFT", s.x * MAP_W, -s.y * MAP_H)
            local c = (i == cur and T.GOLD) or (i <= last and { 0.3, 0.3, 0.3 }) or (s.boss and { 0.55, 0.15, 0.12 }) or { 0.2, 0.25, 0.3 }
            T.Flat(p, c, s.optional and 0.6 or 1, i == cur and { 1, 1, 1 } or T.BORDER)
            p.num:SetText(tostring(i))
            p.num:SetTextColor(i == cur and 0 or 1, i == cur and 0 or 1, i == cur and 0 or 1)
            p.tipTitle = i .. ". " .. s.title .. (s.optional and " (optional)" or "") .. (i <= last and " - done" or "")
            p.tip = s.text
        end
    end
    HideRest(win.lines)
    HideRest(win.pins)

    local at = where.step and steps[where.step]
    if at and at.floor == floor then
        win.you:ClearAllPoints()
        win.you:SetPoint("CENTER", win.map, "TOPLEFT", at.x * MAP_W, -at.y * MAP_H)
        win.you:Show()
    else
        win.you:Hide()
    end

    local nxt = steps[cur]
    local done = last >= #steps
    if done then
        win.next:SetText("All done. " .. g.name .. " is cleared.")
    else
        local away = nxt.floor and nxt.floor ~= floor and (" |cff999999(on " .. g.floors[nxt.floor].name .. ")|r") or ""
        win.next:SetText("|cffffd100Next: " .. cur .. ". " .. nxt.title .. "|r" .. away .. "  " .. nxt.text)
    end
    local you
    if where.how == "room" then
        you = "You: " .. where.room .. ", by " .. where.step .. ". " .. steps[where.step].title .. "."
    elseif where.how == "last" then
        you = "You: about at " .. where.step .. ". " .. steps[where.step].title .. (where.room and (", in " .. where.room) or "") .. "."
    else
        you = "You: " .. (where.room or "near the entrance") .. "."
    end
    win.where:SetText(you .. " The game hides your exact spot in dungeons.")

    -- Folded: no map, only what to do next, where you are, and Back and Next to step by hand.
    local folded = M.db.folded
    win.fold.label:SetText(folded and "+" or "-")
    win.fold.tipTitle = folded and "Unfold" or "Fold"
    win.fold.tip = folded and "Show the map and all the buttons again." or "Show only the next step, where you are, Back and Next."
    win.map:SetShown(not folded)
    for _, b in ipairs({ win.over, win.draw, win.share, win.take }) do b:SetShown(not folded) end
    local mine = Edits(shownKey)
    T.Off(win.share, not (mine and next(mine)), "Nothing drawn yet: there is no route of yours to share.")
    win.next:ClearAllPoints()
    if folded then
        win.next:SetPoint("TOPLEFT", win, "TOPLEFT", 10, -36)
        win:SetHeight(36 + win.next:GetStringHeight() + 4 + win.where:GetStringHeight() + 8 + 24 + 10)
    else
        win.next:SetPoint("TOPLEFT", win.map, "BOTTOMLEFT", 0, -8)
        win:SetHeight(MAP_H + 132)
    end
end

function M:Show(key)
    key = key or shownKey or M.Here()
    if not M.Guide(key) then return false end
    if not win then win = Build() end
    if key ~= shownKey then pickedFloor = nil end
    shownKey = key
    ns.chardb.guideLast = key -- outside a dungeon, /zod guide opens this one again
    M.Fresh(key)
    win:Show()
    M:Draw()
    return true
end

function M:Hide()
    if win then win:Hide() end
    autoOpened = nil
    if drawing then M:Draw(false) end
end

function M.Shown() return win and win:IsShown() and shownKey or nil end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

local lastFloor
local function Check()
    local key = M.Here()
    if key then
        M.Fresh(key)
        local shown = M.Shown()
        if shown and shown ~= key then
            M:Show(key) -- open on another dungeon: turn it to the one you entered
        elseif M.db.auto and not shown then
            M:Show(key)
            autoOpened = true
        end
    elseif autoOpened and M.Shown() then
        M:Hide()
    end
end

M:On("PLAYER_ENTERING_WORLD", function() ns.After(2, Check) end)
M:On("ZONE_CHANGED_NEW_AREA", Check)

-- A new room or floor: follow it (unless you picked a floor to look at).
local function Moved()
    if not M.Shown() then return end
    local here = M.Here()
    local g = M.Guide(shownKey)
    if here and here ~= shownKey and g.group and g.group == M.Guide(here).group then
        M:Show(here)
        return
    end
    local floor = M.Floor(shownKey)
    if floor ~= lastFloor then
        lastFloor = floor
        pickedFloor = nil
    end
    M:Draw()
end
M:On("ZONE_CHANGED", Moved)
M:On("ZONE_CHANGED_INDOORS", Moved)

M:On("ENCOUNTER_END", function(self, _, id, name, _, _, success)
    if Plain(success) == 1 then self:Kill(id, name) end
end)
M:On("BOSS_KILL", function(self, _, id, name) self:Kill(id, name) end)

function M:OnDisable() M:Hide() end

-- The guides there are, as "Razorfen Kraul (/zod guide rfk), ...".
function M.Names()
    local keys = {}
    for key in pairs(ns.GUIDES or {}) do keys[#keys + 1] = key end
    table.sort(keys, function(a, b) return ns.GUIDES[a].name < ns.GUIDES[b].name end)
    for i, key in ipairs(keys) do keys[i] = ns.GUIDES[key].name .. " (/zod guide " .. key .. ")" end
    return table.concat(keys, ", ")
end

-- Outside a dungeon: the guide for the dungeon that fits your level best (the highest one you are in
-- the range of), else the lowest one.
function M.ForLevel(level)
    level = level or (UnitLevel and ns.Level()) or 1
    local keys = {}
    for key in pairs(ns.GUIDES or {}) do keys[#keys + 1] = key end
    table.sort(keys)
    local best, low
    for _, key in ipairs(keys) do
        local g = ns.GUIDES[key]
        if level >= g.min and level <= g.max and (not best or g.min > ns.GUIDES[best].min) then best = key end
        if not low or g.min < ns.GUIDES[low].min then low = key end
    end
    return best or low or "sfk"
end

function M:Slash(arg)
    local text = (arg or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local verb = text:lower():match("^(%S*)")
    if text == "" then
        if M.Shown() then M:Hide() return end
        if not M:Show() then
            local last = ns.chardb.guideLast
            if last and M.Guide(last) then
                M:Show(last) -- the one you had open last
            else
                local key = M.ForLevel()
                M:Show(key)
                ns.Print("Dungeon guide: you are not in a dungeon it knows, so here is " .. M.Guide(key).name .. ". Guides so far: " .. M.Names() .. ".")
            end
        end
    elseif verb == "next" or verb == "back" then
        -- Outside a dungeon (a key pressed after /reload) it steps the guide you had last.
        local open = M:Show() or (ns.chardb.guideLast and M:Show(ns.chardb.guideLast))
        if not open then
            ns.Print("Dungeon guide: no guide is open; /zod guide shows the one for your level.")
        elseif verb == "next" then
            M:Next()
        else
            M:Back()
        end
    elseif verb == "reset" then M:Show() M:StartOver() ns.Print("Dungeon guide: starting over.")
    elseif verb == "draw" then
        if not M.Shown() then M:Show(M.Here() or shownKey or M.ForLevel()) end
        if not drawing and M.db.folded then -- drawing needs the map: unfold first
            M.db.folded = nil
            local point, rel, x, y = T.PinTop(ZodUIGuide)
            if point then M.db.pos = { point, rel, x, y } end
        end
        M:Draw(not drawing)
    elseif verb == "clear" then
        if not M.Shown() then M:Show(M.Here() or shownKey or M.ForLevel()) end
        M:Clear()
        ns.Print("Dungeon guide: your changes to " .. M.Guide(shownKey).name .. " are gone; the route is as it came.")
    elseif verb == "export" then
        local key = shownKey or M.Here() or M.ForLevel()
        local mine = Edits(key)
        if not (mine and next(mine)) then -- an empty line would only be refused at the other end
            ns.Print("Dungeon guide: nothing drawn yet for " .. M.Guide(key).name .. ", so there is no route of yours to share.")
            return
        end
        ns.ShareBox("export", { title = "Your route for " .. M.Guide(key).name, text = M.Export(key) })
    elseif verb == "import" then
        local rest = text:match("^%S+%s+(.+)$")
        if rest then
            local _, said = M.Import(rest)
            ns.Print("Dungeon guide: " .. said)
        else
            ns.ShareBox("import", { title = "Take a route", hint = "Paste a route line here (Ctrl+V). It changes only the drawn route.",
                apply = "Take this route", take = function(t) local _, said = M.Import(t) return said end })
        end
    else
        local key = M.Lookup(text)
        if key then M:Show(key) return end
        ns.Print("Dungeon guide: no guide for '" .. text .. "' yet. Guides so far: " .. M.Names() .. ".")
    end
end

function M.Forget()
    shownKey, shownFloor, pickedFloor, autoOpened, drawing, lastFloor = nil, nil, nil, nil, nil, nil
    if win then win:Hide() end
end
