-- Stubbed WoW API: every widget method exists and does nothing, except the few
-- the addon reads back (text, scripts, shown state).
local level, zone, mapId = 25, "Hillsbrad Foothills", 1424
local frames = {}
local completed, inlog = {}, {}

local function Widget()
    local w = { scripts = {}, shown = true }
    return setmetatable(w, { __index = function(_, k)
        if k == "SetScript" then return function(self, name, fn) self.scripts[name] = fn end end
        if k == "SetText" then return function(self, t) self.text = t end end
        if k == "GetFont" then return function(self) return "Font", rawget(self, "fsize") or 10, "" end end
        if k == "SetFont" then return function(self, _, size) self.fsize = size end end
        if k == "GetStringHeight" then return function() return 12 end end
        if k == "GetHeight" then return function(self) return rawget(self, "h") or 100 end end
        if k == "SetHeight" then return function(self, h) self.h = h end end
        if k == "GetVerticalScroll" then return function() return 0 end end
        if k == "Show" then return function(self) self.shown = true end end
        if k == "Hide" then return function(self) self.shown = false end end
        if k == "SetShown" then return function(self, s) self.shown = s and true or false end end
        if k == "IsShown" then return function(self) return self.shown end end
        if k == "SetPoint" then return function(self, point, rel, relPoint, x, y) self.pt = { point, rel, relPoint, x, y } end end
        if k == "ClearAllPoints" then return function(self) self.pt = nil end end
        if k == "GetPoint" then return function(self)
            local p = rawget(self, "pt")
            if p then return p[1], p[2], p[3], p[4], p[5] end
            return "CENTER", nil, "CENTER", 0, 0
        end end
        if k == "GetLeft" then return function() return 900 end end
        if k == "SetAlpha" then return function(self, v) self.alpha = v end end
        if k == "EnableMouse" then return function(self, v) self.mouse = v end end
        if k == "SetScale" then return function(self, v) self.scale = v end end
        if k == "GetScale" then return function(self) return rawget(self, "scale") or 1 end end
        if k == "GetEffectiveScale" then return function() return 1 end end
        if k == "SetWidth" then return function(self, v) self.w = v end end
        if k == "GetWidth" then return function(self) return rawget(self, "w") or 100 end end
        if k == "GetTop" then return function() return 500 end end
        if k == "CreateFontString" or k == "CreateTexture" then return function() return Widget() end end
        return function() end
    end })
end

function CreateFrame(kind, name)
    local f = Widget()
    f.kind = kind
    frames[#frames + 1] = f
    if name then _G[name] = f end
    return f
end
UIParent = Widget()
Minimap = Widget()
GameTooltip = Widget()
UISpecialFrames = {}
tinsert = table.insert
function UnitLevel() return level end
function UnitClass() return "Paladin", "PALADIN", 2 end
function UnitRace() return "Undead", "Scourge", 5 end
function GetRealZoneText() return zone end
C_QuestLog = {
    IsQuestFlaggedCompleted = function(id) return completed[id] or false end,
    IsOnQuest = function(id) return inlog[id] or false end,
    IsComplete = function(id) return inlog[id] == "complete" end,
    -- The log as a list: every quest in `inlog`, by id, with a title for the ones the route does not know.
    GetNumQuestLogEntries = function()
        local n = 0
        for _ in pairs(inlog) do n = n + 1 end
        return n
    end,
    GetInfo = function(i)
        local ids = {}
        for id in pairs(inlog) do ids[#ids + 1] = id end
        table.sort(ids)
        return ids[i] and { questID = ids[i], title = "Logged " .. ids[i], isHeader = false } or nil
    end,
}
function GetBindLocation() return "Tarren Mill" end
-- The route's own arrow (no TomTom here: the route needs none); its target, as the tests read it.
local waypoints, arrow = 0, nil
C_Map = { GetBestMapForUnit = function() return mapId end }
C_Timer = { After = function(_, fn) fn() end }
local alerts = {}
UIErrorsFrame = { AddMessage = function(_, msg) alerts[#alerts + 1] = msg end }
SlashCmdList = {}
local out = {}
print = function(...) out[#out + 1] = table.concat({ ... }, " ") end
local say = function(s) io.write(s .. "\n") end
local function plain(s) return (s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
local function flush(label)
    say("--- " .. label)
    for _, line in ipairs(alerts) do say("  [ALERT] " .. plain(line)) end
    for _, line in ipairs(out) do say("  " .. plain(line)) end
    out, alerts = {}, {}
end

local ns = {}
assert(load(@DATA@, "Data.lua"))("UndeadRoute", ns)
assert(load(@BUILD@, "Build.lua"))("UndeadRoute", ns)
assert(load(@GEN@, "Generated.lua"))("UndeadRoute", ns) -- the tests' copy of what Build.lua makes at login
assert(load(@REC@, "Recorded.lua"))("UndeadRoute", ns)
assert(load(@RECORDER@, "Recorder.lua"))("UndeadRoute", ns)
local recorder = frames[#frames]
assert(recorder.scripts.OnEvent, "the quest recorder listens to nothing")
assert(load(@MOTION@, "Motion.lua"))("UndeadRoute", ns)
assert(load(@ROUTE@, "Route.lua"))("UndeadRoute", ns)
assert(load(@WINDOW@, "Window.lua"))("UndeadRoute", ns)
assert(load(@GUIDE@, "Guide.lua"))("UndeadRoute", ns)
assert(load(@CORE@, "Core.lua"))("UndeadRoute", ns)
ns.OnArrowTarget = function(t)
    if t then
        waypoints = waypoints + 1
        arrow = { map = t.map, x = t.x / 100, y = t.y / 100, title = t.title }
    else
        arrow = nil
    end
end

local events
for _, f in ipairs(frames) do if f.scripts.OnEvent then events = f end end
-- Each event goes to the quest recorder first, then the route, as both frames registered for it.
local function fire(e, a, b)
    recorder.scripts.OnEvent(recorder, e, a, b)
    events.scripts.OnEvent(events, e, a, b)
end

-- The character has done the Paladin chain up to The Debt, and has one SFK quest in the log.
for _, id in ipairs({ 98601, 90902, 91208, 91209, 91285, 91282, 91294, 91316, 91317, 95803, 94427, 94434, 94435, 94436,
    94438, 94440, 94441, 91858, 91859, 91860, 91861, 91862, 96204, 95034 }) do completed[id] = true end
inlog[1098] = true
-- ZodUI saw this character hand in Seeking the Kor Gem, which the game never flags as done.
ZodUICharDB = { questsDone = { { id = 95042, name = "Seeking the Kor Gem" }, { id = "bad" }, "bad" } }

fire("ADDON_LOADED", "UndeadRoute")
-- Nothing here runs the motion driver's OnUpdate: with animations off a close hides at once, as the checks expect.
assert(ns.Motion.enabled == true, "animations are not on by default")
ns.Motion.enabled = false
fire("PLAYER_LOGIN")
flush("login: Undead Paladin, level 25, in Hillsbrad")

-- Stage sanity after the merge.
local keys = {}
for i, s in ipairs(ns.Stages) do
    assert(s.key and not keys[s.key], "duplicate or missing key at " .. i)
    keys[s.key] = true
    assert(s.zone and s.hub and s.travel and s.min and s.max and s.min <= s.max, "bad stage " .. s.key)
    assert(#s.tasks > 0, "no tasks " .. s.key)
    local quests, lo, hi = 0, 99, 0
    for _, t in ipairs(s.tasks) do
        assert(type(t.t) == "string" or t.quest, "bad task in " .. s.key)
        if s.kind ~= "dungeon" and s.kind ~= "class" then
            assert(not (t.t and t.lv), "memory-based quest step left in " .. s.key)
            if t.id then quests, lo, hi = quests + 1, math.min(lo, t.lv), math.max(hi, t.lv) end
        end
    end
    if s.kind == "zone" or s.kind == "alt" or s.kind == "city" then
        assert(quests > 0, "no verified quests in " .. s.key)
        say(string.format("  %-17s %2d-%2d  %3d verified quests, quest levels %d-%d", s.key, s.min, s.max, quests, lo, hi))
    end
end
say(#ns.Stages .. " stages OK")
-- No quest sits in two zone stages.
local seenQuest = {}
for _, s in ipairs(ns.Stages) do
    if s.kind == "zone" or s.kind == "alt" or s.kind == "city" then
        for _, t in ipairs(s.tasks) do
            if t.id then assert(not seenQuest[t.id], "quest " .. t.id .. " twice") seenQuest[t.id] = true end
        end
    end
end
-- Walking order: prerequisites first, and
-- the giver-to-giver distance is shorter than in the old order (level, then giver name).
local function travel(list)
    local total, last = 0, nil
    for _, t in ipairs(list) do
        if t.x and t.map == t.zmap then
            if last and last.zmap == t.zmap then
                total = total + math.sqrt((t.x - last.x) ^ 2 + (t.y - last.y) ^ 2)
            end
            last = t
        end
    end
    return total
end
local sumOld, sumNew = 0, 0
for _, s in ipairs(ns.Stages) do
    if s.kind == "zone" or s.kind == "alt" or s.kind == "city" then
        local quests, pos = {}, {}
        for _, t in ipairs(s.tasks) do if t.id then quests[#quests + 1] = t pos[t.id] = #quests end end
        for i, t in ipairs(quests) do
            for _, need in ipairs(t.quest.needs or {}) do
                if type(need) == "number" and pos[need] then
                    assert(pos[need] < i, s.key .. ": " .. t.quest.name .. " is listed before its prerequisite")
                end
            end
        end
        local old = {}
        for i, t in ipairs(quests) do old[i] = t end
        table.sort(old, function(a, b) return a.seq < b.seq end)
        local a, b = travel(old), travel(quests)
        sumOld, sumNew = sumOld + a, sumNew + b
        say(string.format("  %-17s giver-to-giver distance %5.0f -> %5.0f map units", s.key, a, b))
    end
end
say(string.format("walking order: total %.0f -> %.0f map units (%.0f%% shorter)", sumOld, sumNew, math.floor(100 - sumNew / sumOld * 100 + 0.5)))
assert(sumNew < sumOld, "walking order is not shorter")

SlashCmdList["UNDEADROUTE"]("")
local W = UndeadRouteFrame
assert(W and W:IsShown(), "window did not open")
say("banner: " .. plain(W.bannerMain.text))
say("   sub: " .. plain(W.bannerSub.text))
say("  sub2: " .. plain(W.bannerSub2.text))
assert(not UndeadRouteTracker:IsShown(), "tracker still shown under the open window")
-- The tracker is not worked out while the window hides it: peek() gives it as it reads with the window closed.
local function peek()
    local was = W.shown -- the stub window fires no OnHide of its own, so a closed one is refreshed here too
    W.shown = false
    W.scripts.OnHide(W)
    W.shown = was
    if was then UndeadRouteTracker.shown = false end
    return UndeadRouteTracker
end
do
    local stale = UndeadRouteTracker.body.text
    UndeadRouteTracker.body.text = "untouched"
    fire("QUEST_LOG_UPDATE")
    assert(UndeadRouteTracker.body.text == "untouched", "the hidden tracker was worked out under the open window")
    UndeadRouteTracker.body.text = stale
end
say("tracker: " .. plain(peek().head.text) .. " / " .. plain(peek().body.text):gsub("\n", " / "))

local function show(key, max)
    for i, s in ipairs(ns.Stages) do
        if s.key == key then
            W.rows[i].scripts.OnClick(W.rows[i])
            say("== " .. plain(W.detail.title.text) .. "  [" .. plain(W.detail.meta.text) .. "]  list tag: "
                .. plain(W.rows[i].tag.text or ""))
            local now = W.detail.now
            if now.shown then
                say("   [" .. plain(now.head.text) .. "  |  " .. plain(now.count.text) .. "]")
                say("   >> " .. plain(now.next.text) .. (now.nextWhere.shown and ("   " .. plain(now.nextWhere.text)) or ""))
                for _, r in ipairs(now.rows) do
                    if r.shown then say(string.format("      %-8s %s", plain(r.verb.text), plain(r.text.text))) end
                end
            end
            local n = 0
            for _, row in ipairs(W.detail.taskRows) do
                if row.shown and n < (max or 99) then
                    n = n + 1
                    if row.head.shown then say("   -- " .. plain(row.head.text) .. " --") end
                    say("   " .. (row.lv.text or "") .. "  " .. plain(row.text.text):gsub("\n", "\n        "))
                end
            end
            return
        end
    end
    error("no stage " .. key)
end
-- Hub headings: every zone stage has them, its first quest carries one, tips and dungeon quests never do.
local heads = 0
for _, s in ipairs(ns.Stages) do
    local n, first = 0, nil
    for _, t in ipairs(s.tasks) do
        if t.head then
            assert(t.id and t.zmap, "heading on a step that is not a zone quest in " .. s.key)
            n = n + 1
        end
        if t.zmap and not first then first = t end
    end
    if s.kind == "zone" or s.kind == "alt" or s.kind == "city" then
        assert(n > 0 and first.head, "no hub headings in " .. s.key)
    else
        assert(n == 0, "hub heading outside a zone stage: " .. s.key)
    end
    heads = heads + n
end
say("hub headings: " .. heads)
-- Batches: 1-5 quests, contiguous in the list, a heading on the first, no quest waiting on another of the same batch.
local nb, sizes = 0, {}
for _, s in ipairs(ns.Stages) do
    for _, b in ipairs(s.batches) do
        nb = nb + 1
        assert(#b.idx >= 1 and (#b.idx <= 5 or b.dungeon), "batch of " .. #b.idx .. " in " .. s.key)
        sizes[#b.idx] = (sizes[#b.idx] or 0) + 1
        local inBatch = {}
        for k, i in ipairs(b.idx) do
            if k > 1 then assert(i == b.idx[k - 1] + 1, "batch not contiguous in " .. s.key) end
            inBatch[s.tasks[i].id] = true
        end
        if not b.dungeon then assert(s.tasks[b.idx[1]].head, "batch without a heading in " .. s.key) end
        for _, i in ipairs(b.idx) do
            for _, need in ipairs(s.tasks[i].quest.needs or {}) do
                if type(need) == "number" then
                    assert(not inBatch[need], s.key .. ": " .. s.tasks[i].quest.name .. " shares a batch with its prerequisite")
                end
            end
        end
    end
end
local sz = {}
for n = 1, 5 do sz[#sz + 1] = n .. ":" .. (sizes[n] or 0) end
say("batches: " .. nb .. " (by size " .. table.concat(sz, " ") .. ")")
assert(W.title.fsize == 12 and W.detail.title.fsize == 12, "text is not 2 pixels bigger")
say("text size: " .. W.title.fsize .. " (stub default 10)")
SlashCmdList["UNDEADROUTE"]("font 4") assert(UndeadRouteDB.font == 4) SlashCmdList["UNDEADROUTE"]("font 9") assert(UndeadRouteDB.font == 4)
UndeadRouteDB.font = nil
SlashCmdList["UNDEADROUTE"]("motion")
assert(UndeadRouteDB.motion == false and ns.Motion.enabled == false, "/route motion does not turn the animations off")
SlashCmdList["UNDEADROUTE"]("motion")
assert(UndeadRouteDB.motion == true and ns.Motion.enabled == true, "/route motion does not turn them back on")
ns.Motion.enabled = false

-- Hub coordinates in Data.lua against the data: how many of the stage's givers stand within 8 units.
for _, s in ipairs(ns.Stages) do
    if (s.kind == "zone" or s.kind == "alt") and s.x then
        local near, all = 0, 0
        for _, t in ipairs(s.tasks) do
            if t.id and t.x and t.quest.zone == s.zone then
                all = all + 1
                if math.sqrt((t.x - s.x) ^ 2 + (t.y - s.y) ^ 2) <= 8 then near = near + 1 end
            end
        end
        say(string.format("  hub check %-17s %-22s (%2d, %2d): %2d of %2d givers nearby", s.key, s.hub, s.x, s.y, near, all))
    end
end

-- The arrow: next step on the recommended stage, following pick up -> objective -> hand in.
local function trackerText() return plain(peek().body.text) end
assert(arrow and arrow.title:find("^Pick up: "), "no arrow to the first pickup")
say("arrow 1: " .. arrow.title .. string.format("  map %d (%.3f, %.3f)", arrow.map, arrow.x, arrow.y))
assert(trackerText():find("Next: " .. arrow.title, 1, true), "tracker does not name the next step")
local rec
for _, s in ipairs(ns.Stages) do if s.key == "hillsbrad-2" then rec = s end end
-- The quests of the batch the arrow points into (the first batch with something to pick up).
local hubQuests = {}
for _, t in ipairs(rec.tasks) do
    if t.id and arrow.title == "Pick up: " .. (t.quest.part and (t.quest.name .. " (part " .. t.quest.part .. ")") or t.quest.name) then
        for _, bt in ipairs(t.batch.tasks) do hubQuests[#hubQuests + 1] = bt end
        break
    end
end
assert(#hubQuests > 0, "the arrow's quest is in no batch")
say("arrow batch: " .. plain(hubQuests[1].head) .. ": " .. #hubQuests .. " quests")
local first = arrow.title
for _, t in ipairs(hubQuests) do inlog[t.id] = true end -- everything in the batch picked up
fire("QUEST_LOG_UPDATE")
assert(arrow and arrow.title ~= first, "arrow did not move after the pickups")
say("arrow 2: " .. arrow.title)
for _, t in ipairs(hubQuests) do if t.quest.turnin then inlog[t.id] = "complete" end end
fire("QUEST_LOG_UPDATE")
say("arrow 3: " .. arrow.title)
assert(arrow.title:find("^Hand in: ") or arrow.title:find("^Do: ") or arrow.title:find("^Pick up: "))
-- READY TO HAND IN: every finished quest in the log, from any stage, where you stand first; and a tracker line.
do
    local done = {}
    for _, t in ipairs(hubQuests) do if inlog[t.id] == "complete" then done[#done + 1] = t end end
    inlog[999001] = "complete" -- a quest the route does not know
    W:Show()
    fire("QUEST_LOG_UPDATE")
    local box = W.detail.ready
    assert(box and box.shown, "READY TO HAND IN not shown")
    assert(plain(box.head.text):find("READY TO HAND IN   " .. (#done + 1), 1, true), "ready count wrong: " .. plain(box.head.text))
    local rows = {}
    for _, r in ipairs(box.rows) do if r.shown then rows[#rows + 1] = plain(r.text.text) end end
    assert(#rows == #done + 1, "ready rows: " .. #rows)
    assert(rows[#rows] == "Logged 999001  where you got it", "an unknown quest comes last, by its log title: " .. rows[#rows])
    assert(rows[1]:find("(", 1, true), "a known quest says where it is handed in: " .. rows[1])
    assert(trackerText():find("Ready to hand in: " .. (#done + 1), 1, true), "no ready line in the tracker: " .. trackerText())
    say("ready: " .. rows[1])
    inlog[999001] = nil
    for _, t in ipairs(hubQuests) do inlog[t.id] = nil end
    fire("QUEST_LOG_UPDATE")
    assert(not box.shown, "READY TO HAND IN still shown with nothing to hand in")
    assert(not trackerText():find("Ready to hand in", 1, true), "tracker line left with nothing to hand in")
end
for _, t in ipairs(hubQuests) do inlog[t.id] = nil end
SlashCmdList["UNDEADROUTE"]("arrow")
assert(arrow == nil and UndeadRouteDB.arrow == false, "arrow not removed when turned off")
SlashCmdList["UNDEADROUTE"]("arrow")
assert(arrow and UndeadRouteDB.arrow == true, "arrow not restored")
say("arrow: on/off works, " .. waypoints .. " waypoints set so far")
out = {}

-- Skipping a quest: its Skip button hides it from the count, Undo brings it back. A click on the quest does nothing.
do
    local i
    for j, s in ipairs(ns.Stages) do if s.key == "hillsbrad-2" then i = j end end
    W.rows[i].scripts.OnClick(W.rows[i])
    local idx
    for j, t in ipairs(rec.tasks) do if t.id and not idx and W.detail.taskRows[j].text.text:find("Dangerous!", 1, true) then idx = j end end
    local before = plain(W.detail.stepsHead.text):match("(%d+) to do")
    local row = W.detail.taskRows[idx]
    row.scripts.OnClick(row, "LeftButton")
    assert(not plain(row.text.text):find("skipped", 1, true), "a click on a quest skipped it")
    assert(not row.box.shown and not row.skip.shown, "open quest shows a tick box or a Skip button unasked")
    row.skip.scripts.OnClick(row.skip)
    assert(plain(row.text.text):find("skipped", 1, true), "quest not shown as skipped")
    assert(row.skip.shown and row.skip.label.text == "Undo", "no Undo on a skipped quest")
    assert(tonumber(plain(W.detail.stepsHead.text):match("(%d+) to do")) == before - 1, "skipped quest still counted")
    row.skip.scripts.OnClick(row.skip)
    assert(plain(W.detail.stepsHead.text):match("(%d+) to do") == before, "skip not undone")
    say("skip: " .. before .. " to do -> " .. (before - 1) .. " -> " .. before)
end
-- The NOW box: a click on a line leads the arrow there first, a second click gives it back to the route;
-- a quest in the log shows its objectives; two quests worked in one place are one step.
do
    local i
    for j, s in ipairs(ns.Stages) do if s.key == "hillsbrad-2" then i = j end end
    W.rows[i].scripts.OnClick(W.rows[i])
    -- One quest of the batch in the log, so the box has a Do line beside the pickup the arrow points at.
    local held
    for _, t in ipairs(rec.tasks) do
        if not held and t.id and t.quest.spot and t.batch == hubQuests[1].batch and arrow.title ~= "Pick up: " .. t.quest.name then
            held = t
        end
    end
    if held then inlog[held.id] = true fire("QUEST_LOG_UPDATE") end
    local now, before = W.detail.now, arrow.title
    local pick
    for _, r in ipairs(now.rows) do
        if r.shown and not r.waiting and r.place and ("Pick up: " .. plain(r.text.text):match("^(.-)  ")) ~= before then pick = r end
    end
    if pick then
        pick.scripts.OnClick(pick)

        assert(arrow.title == pick.place.title, "the arrow did not go for the clicked quest: " .. arrow.title)
        assert(pick.focus.shown and plain(now.next.text):find("your pick", 1, true), "the clicked line is not marked")
        say("focus: " .. before .. " -> " .. arrow.title)
        pick.scripts.OnClick(pick)
        assert(arrow.title == before and UndeadRouteDB.focus == nil, "a second click did not give the arrow back")
    else
        error("focus: no second open line to click")
    end
    if held then inlog[held.id] = nil fire("QUEST_LOG_UPDATE") end
    -- Objectives and a joint step: two quests of the batch in the log, their objectives in one spot.
    C_QuestLog.GetQuestObjectives = function(id)
        return { { text = "Thing " .. id .. " slain: 2/8", finished = false }, { text = "Done bit", finished = true } }
    end
    local a, b
    for _, t in ipairs(rec.tasks) do
        if t.id and t.quest.spot and not inlog[t.id] and not completed[t.id] then
            if not a then a = t elseif not b and math.abs(t.quest.spot[1] - a.quest.spot[1]) + math.abs(t.quest.spot[2] - a.quest.spot[2]) < 6 then b = t end
        end
    end
    if a and b then
        local saved = UndeadRouteDB.focus
        inlog[a.id], inlog[b.id] = true, true
        UndeadRouteDB.focus = a.id
        fire("QUEST_LOG_UPDATE")
        assert(arrow.title:find(" + ", 1, true), "two quests in one spot are not one step: " .. arrow.title)
        local seen = false
        for _, r in ipairs(now.rows) do if r.shown and plain(r.text.text):find("2/8  Thing " .. a.id .. " slain", 1, true) then seen = true end end
        assert(seen, "objective counts not shown, count first, in the NOW box")
        -- The tracker carries the same counts, since it is what you look at while you play.
        local body = plain(peek().body.text)
        assert(body:find("2/8  Thing " .. a.id .. " slain", 1, true), "objective counts not in the tracker: " .. body)
        assert(body:find("Done bit  - done", 1, true), "finished objective not marked done in the tracker")
        say("tracker objectives: " .. body:gsub("\n", " / "))
        say("together: " .. arrow.title)
        inlog[a.id], inlog[b.id], UndeadRouteDB.focus = nil, nil, saved
        fire("QUEST_LOG_UPDATE")
    end
    C_QuestLog.GetQuestObjectives = nil
end
-- The NOW box numbers what you can do and folds what waits into one line; the step list folds the NOW batch.
do
    local now, waiting, numbered = W.detail.now, 0, 0
    for _, r in ipairs(now.rows) do
        if r.shown then
            if r.waiting then waiting = waiting + 1
            else
                numbered = numbered + 1
                assert(plain(r.verb.text):match("^(%d+)") == tostring(numbered), "NOW line not numbered: " .. plain(r.verb.text))
            end
        end
    end
    assert(waiting <= 1, "waiting quests not folded into one line: " .. waiting)
    say(string.format("now box: %d numbered, %d waiting line", numbered, waiting))
    local head, hidden, shownRows = nil, 0, 0
    for _, row in ipairs(W.detail.taskRows) do
        if row.nowHead then head = row end
    end
    assert(head and head.shown, "NOW batch heading missing in the step list")
    assert(plain(head.head.text):find("in the box above", 1, true), "NOW batch not folded: " .. plain(head.head.text))
    for _, row in ipairs(W.detail.taskRows) do if not row.shown then hidden = hidden + 1 end end
    head.scripts.OnClick(head, "LeftButton")
    for _, row in ipairs(W.detail.taskRows) do if not row.shown then shownRows = shownRows + 1 end end
    assert(shownRows < hidden and plain(head.head.text):find("click to fold", 1, true), "NOW batch did not unfold")
    head.scripts.OnClick(head, "LeftButton")
    assert(plain(head.head.text):find("in the box above", 1, true), "NOW batch did not fold again")
    say("steps: NOW batch folds and unfolds")
end
show("undercity", 14)
show("orgrimmar", 10)
show("thunder-bluff", 12)
show("sfk")
show("paladin", 30)
show("hillsbrad-2")
show("deathknell", 8)
show("riverglades", 12)

-- Every stage row: select, left-click, right-click and hover its first step.
for i, row in ipairs(W.rows) do
    row.scripts.OnEnter(row) row.scripts.OnClick(row) row.scripts.OnLeave(row)
    local task = W.detail.taskRows[1]
    task.scripts.OnEnter(task) task.scripts.OnLeave(task)
    task.scripts.OnClick(task, "RightButton")
    task.scripts.OnClick(task, "LeftButton") task.scripts.OnClick(task, "LeftButton")
end
say("clicked all " .. #W.rows .. " stage rows without error")
-- A stage picked by hand is where the window opens again; Show recommended lets the route lead.
do
    local picked = UndeadRouteDB.window.stage
    assert(picked, "a clicked stage is not kept")
    SlashCmdList.UNDEADROUTE("") SlashCmdList.UNDEADROUTE("")
    assert(UndeadRouteDB.window.stage == picked, "opening the window again forgets the picked stage")
    UndeadRouteDB.window.stage = nil
end
-- A stage marked done shows DONE where its batch was, with where to go on.
do
    local first = W.rows[3]
    first.scripts.OnClick(first)
    local key = UndeadRouteDB.window.stage
    UndeadRouteDB.stages[key] = true
    SlashCmdList.UNDEADROUTE("") SlashCmdList.UNDEADROUTE("")
    local head = plain(W.detail.now.head.text or "")
    assert(head:find("^DONE"), "a finished stage does not say DONE: " .. head)
    UndeadRouteDB.stages[key] = nil
    UndeadRouteDB.window.stage = nil
    say("finished stage: " .. head)
end
out = {}
local clicked = 0
for pass = 1, 2 do -- twice, so toggles end where they began
    for _, f in ipairs(frames) do
        local label = rawget(f, "label")
        if f.kind == "Button" and f.scripts.OnClick and type(label) == "table" and label.text ~= "x" then
            f.scripts.OnEnter(f) f.scripts.OnLeave(f) f.scripts.OnClick(f) clicked = clicked + 1
        end
    end
end
say("clicked the bar buttons " .. clicked .. " times")
for k in pairs(UndeadRouteDB.stages) do UndeadRouteDB.stages[k] = nil end -- the clicks marked stages done
for k in pairs(UndeadRouteDB.tasks) do UndeadRouteDB.tasks[k] = nil end -- and pressed Skip on two different stages
out = {}
SlashCmdList["UNDEADROUTE"]("dungeons")
flush("/route dungeons")

zone, mapId = "Undercity", 1458
fire("ZONE_CHANGED_NEW_AREA")
local cityAlert = false
for _, a in ipairs(alerts) do if a:find("Undercity: %d+ quests? to pick up here") then cityAlert = true end end
assert(cityAlert, "no city reminder on entering Undercity")
flush("entering Undercity")
fire("ZONE_CHANGED_NEW_AREA")
assert(#alerts == 0, "city reminder repeated in one session")

for lv = 26, 30 do
    level = lv
    fire("PLAYER_LEVEL_UP", lv)
    flush("level up to " .. lv)
end

-- Trainer reminder: set on the even level-ups above, raised in a capital, cleared at the trainer.
assert(UndeadRouteDB.train == 30, "trainer reminder not set")
assert(plain(peek().body.text):find("Train: new spells since level 30", 1, true), "tracker has no trainer line")
zone, mapId = "Orgrimmar", 1454
fire("ZONE_CHANGED_NEW_AREA")
local trainAlert = false
for _, a in ipairs(alerts) do if a:find("Train while you are in Orgrimmar", 1, true) then trainAlert = true end end
assert(trainAlert, "no trainer reminder in Orgrimmar")
flush("entering Orgrimmar with spells to train")
fire("TRAINER_CLOSED")
assert(UndeadRouteDB.train == nil, "trainer reminder not cleared")
-- Arriving in a route zone for the first time.
zone, mapId = "Arathi Highlands", 1417
fire("ZONE_CHANGED_NEW_AREA")
local arrived = false
for _, line in ipairs(out) do if line:find("Arrived in Arathi Highlands", 1, true) then arrived = true end end
assert(arrived, "no arrival reminder")
flush("arriving in Arathi Highlands at 30")
fire("ZONE_CHANGED_NEW_AREA")
assert(#out == 0, "arrival reminder repeated")

-- Handing in the quest that gates the next Paladin step.
completed[95036], completed[95111], completed[95125] = true, true, true
fire("QUEST_TURNED_IN", 95125)
flush("handed in Ott's Masterwork")
fire("QUEST_LOG_UPDATE")

-- Recommendation at every level.
zone, mapId = "Orgrimmar", 1454
local last
for lv = 1, 60 do
    level = lv
    fire("PLAYER_LEVEL_UP", lv)
    local where = plain(W.bannerMain.text):match(">%s+(.+)$")
    if where ~= last then say(string.format("  lv %2d: %s", lv, where)) last = where end
end
say("alerts fired across 1-60: " .. #alerts)
SlashCmdList["UNDEADROUTE"]("help") SlashCmdList["UNDEADROUTE"]("tracker") SlashCmdList["UNDEADROUTE"]("tracker")
-- Reset asks first.
UndeadRouteDB.stages.deathknell = true
SlashCmdList["UNDEADROUTE"]("reset")
assert(UndeadRouteDB.stages.deathknell, "reset cleared without confirmation")
SlashCmdList["UNDEADROUTE"]("reset confirm")
assert(not UndeadRouteDB.stages.deathknell, "reset confirm did not clear")
-- Closing the window brings the tracker back.
W:Hide()
if W.scripts.OnHide then W.scripts.OnHide(W) end
assert(UndeadRouteTracker:IsShown(), "tracker not back after the window closed")

-- Folding the tracker keeps only the essentials: the next step, the batch, what is ready to hand in.
do
    local t = UndeadRouteTracker
    local full = plain(t.body.text)
    t.fold.scripts.OnClick(t.fold, "LeftButton")
    local short = plain(t.body.text)
    assert(UndeadRouteDB.tracker.collapsed and t.fold.label.text == "+", "the fold button does not fold")
    local tr = UndeadRouteDB.tracker
    assert(tr.point == "TOPLEFT" and tr.rel == "BOTTOMLEFT" and tr.x == 900 and tr.y == 500,
        "folding does not pin the tracker by its top: " .. tostring(tr.point) .. " " .. tostring(tr.x) .. " " .. tostring(tr.y))
    assert(#short < #full and select(2, short:gsub("\n", "")) < select(2, full:gsub("\n", "")), "folded tracker is not shorter: " .. short)
    for line in short:gmatch("[^\n]+") do
        assert(line:find("^Next:") or line:find("^Now:") or line:find("^Ready to hand in:") or line:find("^Nothing left here"),
            "folded tracker shows more than the essentials: " .. line)
    end
    assert(plain(t.foot.text):find("Folded", 1, true), "folded tracker does not say so")
    t.fold.scripts.OnClick(t.fold, "LeftButton")
    assert(not UndeadRouteDB.tracker.collapsed and plain(t.body.text) == full and t.fold.label.text == "-", "unfolding does not bring it all back")
    -- The corner grip sizes the tracker by its scale and keeps its top-left corner.
    GetCursorPosition = function() return 900 + t:GetWidth() * 1.5, 0 end
    t.grip.scripts.OnMouseDown(t.grip, "LeftButton")
    t.grip.scripts.OnUpdate(t.grip, 0.1)
    t.grip.scripts.OnMouseUp(t.grip, "LeftButton")
    assert(math.abs((UndeadRouteDB.tracker.scale or 0) - 1.5) < 0.01 and t.scale == UndeadRouteDB.tracker.scale, "the grip does not size the tracker: " .. tostring(UndeadRouteDB.tracker.scale))
    assert(UndeadRouteDB.tracker.point == "TOPLEFT" and t.grip.scripts.OnUpdate == nil, "the grip does not keep the corner or stop when let go")
    -- Let go away from the grip (no OnMouseUp reaches it): it still stops.
    t.grip.scripts.OnMouseDown(t.grip, "LeftButton")
    IsMouseButtonDown = function() return false end
    t.grip.scripts.OnUpdate(t.grip, 0.1)
    assert(t.grip.scripts.OnUpdate == nil, "a grip let go off itself keeps sizing")
    IsMouseButtonDown = nil
    t.grip.scripts.OnDoubleClick(t.grip)
    assert(UndeadRouteDB.tracker.scale == nil and t.scale == 1, "a double-click does not make the tracker normal size")
    GetCursorPosition = nil
    -- A click on the tracker pins the next step; a drag (the tracker moved between down and up) does not.
    local function pins()
        local n = 0
        for _, line in ipairs(out) do if plain(line):find("Pinned ", 1, true) then n = n + 1 end end
        return n
    end
    out = {}
    t.scripts.OnMouseDown(t, "LeftButton")
    t.scripts.OnMouseUp(t, "LeftButton")
    assert(pins() == 1, "a click on the tracker does not pin the next step")
    assert(arrow and arrow.title, "the arrow does not go to the pin")
    assert(UndeadRoute_Key and BINDING_NAME_UNDEADROUTE_PIN, "the route has no key bindings")
    UndeadRoute_Key("pin")
    assert(pins() == 2, "the Pin key does not pin the next step")
    -- In a fight the tracker is faint and lets the clicks through.
    fire("PLAYER_REGEN_DISABLED")
    assert(t.alpha == 0.4 and t.mouse == false and t.fold.mouse == false, "the tracker does not step back in a fight")
    fire("PLAYER_REGEN_ENABLED")
    assert(t.alpha == 1 and t.mouse == true, "the tracker does not come back after the fight")
    say("tracker folded: " .. short:gsub("\n", " / "))
end

-- A quest the route was seen handing in counts as done, though the game does not flag it.
assert(UndeadRouteDB.turnedIn[95042] and UndeadRouteDB.turnedIn[95125], "turned-in quests not kept")
zone, mapId, level = "Ashenvale", 1440, 31
out = {}
fire("ZONE_CHANGED_NEW_AREA")
local function told(name)
    for _, line in ipairs(out) do if plain(line):find(name, 1, true) then return true end end
    return false
end
assert(not told("Seeking the Kor Gem"), "Kor Gem suggested though it was handed in")
UndeadRouteDB.turnedIn[95042] = nil
fire("ZONE_CHANGED_NEW_AREA")
assert(told("Seeking the Kor Gem"), "Kor Gem not suggested when it was not handed in: the check above proves nothing")
flush("Ashenvale at 31: Seeking the Kor Gem only when not handed in")
fire("QUEST_TURNED_IN", 95042)
assert(UndeadRouteDB.turnedIn[95042], "a hand-in is not kept")

-- Dungeons ranked by what their quests are worth now, and a detour into one.
do
    local xpOf, asked, instance = {}, {}, nil
    level = 31
    fire("PLAYER_LEVEL_UP", 31) -- the route goes by the level the last level-up gave
    function UnitXPMax() return 20000 end
    function IsInInstance() return instance ~= nil, instance and "party" or "none" end
    function GetInstanceInfo() return instance end
    GetQuestLogRewardXP = function(id) return xpOf[id] or 0 end
    C_QuestLog.RequestLoadQuestByID = function(id) asked[#asked + 1] = id end
    local function ranked()
        local list = {}
        for _, line in ipairs(out) do
            local n, name = plain(line):match("^Undead Route: (%d+)%. (.-) %(")
            if n then list[tonumber(n)] = { name = name, line = plain(line) } end
        end
        return list
    end
    out = {}
    SlashCmdList.UNDEADROUTE("dungeons")
    local before = ranked()
    assert(#before >= 2, "fewer than two dungeons ranked at 31")
    assert(#asked > 0 and before[1].line:find("XP loading", 1, true), "dungeon quest XP not asked for")
    local n = #asked
    SlashCmdList.UNDEADROUTE("dungeons")
    assert(#asked == n, "dungeon quest XP asked for twice")
    -- The answers come: the second dungeon's quests are worth far more, so it goes first.
    for _, id in ipairs(asked) do xpOf[id] = 1000 end
    local second = before[2].name
    for _, stage in ipairs(ns.Stages) do
        if stage.hub == second then
            for _, t in ipairs(stage.tasks) do if t.id then xpOf[t.id] = 8000 end end
        end
    end
    fire("QUEST_DATA_LOAD_RESULT", asked[1])
    out = {}
    SlashCmdList.UNDEADROUTE("dungeons")
    local after = ranked()
    assert(after[1].name == second, "the dungeon worth the most XP is not first: " .. after[1].line)
    assert(after[1].line:find("%d+%% of a level") and after[1].line:find("Pick up: %d+ "),
        "a ranked dungeon does not say its XP and where its quests are: " .. after[1].line)
    say("ranked: " .. after[1].line)
    say("ranked: " .. after[2].line)
    -- The banner names the best first.
    SlashCmdList.UNDEADROUTE("") -- open the window
    assert(plain(W.bannerSub.text):find("best first: " .. second, 1, true), "banner: " .. plain(W.bannerSub.text))
    SlashCmdList.UNDEADROUTE("")
    -- Do it now: the route and the tracker lead to the dungeon.
    out = {}
    SlashCmdList.UNDEADROUTE("do " .. second:lower():gsub("^the ", ""):sub(1, 6))
    assert(told("detour: " .. second), "/route do did not start a detour")
    assert(UndeadRoute.Status().stage:find(second, 1, true) or plain(UndeadRouteTracker.head.text):find("Detour:", 1, true),
        "the route does not lead to the dungeon on a detour")
    assert(plain(UndeadRouteTracker.head.text):find("Detour:", 1, true), "the tracker does not say Detour")
    -- In and out with a quest to hand in: the detour stays until it is handed in.
    local stage
    for _, s in ipairs(ns.Stages) do if s.hub == second then stage = s end end
    local quest
    for _, t in ipairs(stage.tasks) do if t.id and not t.quest.inside then quest = t.id break end end
    inlog[quest] = "complete"
    instance = second
    fire("PLAYER_ENTERING_WORLD")
    instance = nil
    fire("ZONE_CHANGED_NEW_AREA")
    assert(plain(UndeadRouteTracker.head.text):find("Detour:", 1, true), "the detour ended with a quest left to hand in")
    out = {}
    inlog[quest] = nil
    completed[quest] = true
    fire("QUEST_LOG_UPDATE")
    assert(not plain(UndeadRouteTracker.head.text):find("Detour:", 1, true) and told("back on the route"),
        "the detour did not end once the run was over and nothing was left to hand in")
    completed[quest] = nil
    -- /route back ends one at once; a name that matches nothing says so.
    SlashCmdList.UNDEADROUTE("do best")
    assert(UndeadRouteDB.detour, "/route do best did not start a detour")
    out = {}
    SlashCmdList.UNDEADROUTE("back")
    assert(not UndeadRouteDB.detour and told("back on the route"), "/route back did not end the detour")
    out = {}
    SlashCmdList.UNDEADROUTE("do nowhere at all")
    assert(not UndeadRouteDB.detour and told("matches"), "/route do with an unknown name")
    -- A side branch leads the same way: /route follow, until /route back.
    local was = level
    level = 34
    fire("PLAYER_LEVEL_UP", 34)
    out = {}
    SlashCmdList.UNDEADROUTE("follow nowhere at all")
    assert(not UndeadRouteDB.detour and told("matches") and told("Desolace"), "/route follow with an unknown name")
    out = {}
    SlashCmdList.UNDEADROUTE("follow deso")
    assert(UndeadRouteDB.detour == "desolace" and told("side branch: Desolace"), "/route follow did not start a side branch")
    assert(plain(UndeadRouteTracker.head.text):find("Desolace", 1, true), "the tracker does not lead into the side branch: "
        .. plain(UndeadRouteTracker.head.text))
    assert(UndeadRoute.Status().stage:find("Desolace", 1, true), "the route does not lead into the side branch")
    fire("ZONE_CHANGED_NEW_AREA")
    assert(UndeadRouteDB.detour == "desolace", "a zone change ended the side branch")
    -- The choice is kept while the stage is out of reach for now (the game gives no level for a moment while
    -- logging in or out): only done or outleveled ends it.
    level = 20
    fire("PLAYER_LEVEL_UP", 20)
    assert(UndeadRouteDB.detour == "desolace", "a side branch was dropped while its stage read as not open yet")
    assert(not plain(UndeadRouteTracker.head.text):find("Desolace", 1, true), "the tracker leads into a stage that is not open")
    level = 34
    fire("PLAYER_LEVEL_UP", 34)
    assert(plain(UndeadRouteTracker.head.text):find("Desolace", 1, true), "the side branch does not lead again once in range")
    -- Its tips are for arriving: with two of its quests handed in you have been there, and they are done.
    do
        local stage, tip, two = nil, nil, {}
        for _, s in ipairs(ns.Stages) do if s.key == "desolace" then stage = s end end
        for i, t in ipairs(stage.tasks) do
            if not t.id then tip = tip or i elseif #two < 2 then two[#two + 1] = t.id end
        end
        assert(ns.I.TaskState(stage, tip, 34) == "do", "a tip of a stage you have not been to is not open")
        completed[two[1]] = true
        assert(ns.I.TaskState(stage, tip, 34) == "do", "one quest handed in already ticks a stage's tips")
        completed[two[2]] = true
        assert(ns.I.TaskState(stage, tip, 34) == "done", "the tips of a stage you have been to are still open")
        completed[two[1]], completed[two[2]] = nil, nil
    end
    SlashCmdList.UNDEADROUTE("") -- the window: its button ends it
    assert(plain(W.bannerSub.text):find("Side branch: Desolace", 1, true), "banner: " .. plain(W.bannerSub.text))
    SlashCmdList.UNDEADROUTE("")
    out = {}
    SlashCmdList.UNDEADROUTE("back")
    assert(not UndeadRouteDB.detour and told("back on the route"), "/route back did not end the side branch")
    assert(not told("Time to move on"), "leaving a side branch said Time to move on")
    say("side branch: /route follow leads the tracker and arrow through Desolace")
    level = was
    fire("PLAYER_LEVEL_UP", was)
    out = {}
    UnitXPMax, IsInInstance, GetInstanceInfo, GetQuestLogRewardXP = nil, nil, nil, nil
    level = 60
    fire("PLAYER_LEVEL_UP", 60)
    out, alerts = {}, {}
end

-- A quest that needs things from several dungeons is a quest in one of them and a note in the others.
do
    local quest, notes = {}, {}
    for _, s in ipairs(ns.Stages) do
        if s.kind == "dungeon" then
            for _, t in ipairs(s.tasks) do
                if t.id == 95036 then quest[#quest + 1] = s.hub end
                if t.t and t.t:find("A Moon-Kissed Blade", 1, true) then notes[#notes + 1] = s.hub .. ": " .. t.t end
            end
        end
    end
    assert(#quest == 1, "A Moon-Kissed Blade is a quest in " .. #quest .. " dungeons: " .. table.concat(quest, ", "))
    assert(#notes >= 1, "the other dungeons do not say what A Moon-Kissed Blade needs from them")
    say("Moon-Kissed Blade: quest in " .. quest[1] .. "; " .. table.concat(notes, " / "))
end

-- Hand-ins in walking order: one stop per spot, and each next stop the nearest one left.
do
    local savedMap = mapId
    -- Five quests of Tirisfal Glades handed in at different spots there, and two at one spot.
    local picked, spots = {}, {}
    local function key(t) return math.floor(t[2] / 5) .. ":" .. math.floor(t[3] / 5) end -- spots 5 units apart and more
    for _, q in ipairs(ns.ZoneQuests[1420] or {}) do
        local t = q.turnin
        if t and t[1] == 1420 and #picked < 5 and not spots[key(t)] then spots[key(t)] = q picked[#picked + 1] = q end
    end
    for _, q in ipairs(ns.ZoneQuests[1420] or {}) do -- and one more where one of them is handed in
        local t, first = q.turnin, nil
        if t and t[1] == 1420 and #picked == 5 then
            for _, o in ipairs(picked) do
                if o.id ~= q.id and o.turnin[2] == t[2] and o.turnin[3] == t[3] then first = o end
            end
            if first then picked[#picked + 1] = q end
        end
    end
    assert(#picked >= 5, "not enough Tirisfal hand-ins to test the walking order")
    for _, q in ipairs(picked) do inlog[q.id] = "complete" end
    mapId = 1420
    local px, py = 60, 52 -- Brill
    C_Map.GetPlayerMapPosition = function() return { GetXY = function() return px / 100, py / 100 end } end
    local list = ns.ReadyToHandIn()
    local mine = {}
    for _, e in ipairs(list) do if e.place and e.place.map == 1420 and inlog[e.id] == "complete" then mine[#mine + 1] = e end end
    assert(#mine == #picked, "the hand-ins are not all in the list: " .. #mine .. " of " .. #picked)
    -- From where you stand, every next stop is the nearest stop not yet visited.
    local function d(ax, ay, bx, by) return math.sqrt((ax - bx) ^ 2 + (ay - by) ^ 2) end
    local x, y, lastStop = px, py, 0
    for i, e in ipairs(mine) do
        assert(e.stop and e.stop >= lastStop, "stops out of order")
        if e.stop ~= lastStop then
            for j = i + 1, #mine do
                local o = mine[j]
                if o.stop ~= e.stop then
                    assert(d(x, y, e.place.x, e.place.y) <= d(x, y, o.place.x, o.place.y) + 1e-6,
                        "stop " .. e.stop .. " is not the nearest: " .. e.name .. " before " .. o.name)
                end
            end
            x, y, lastStop = e.place.x, e.place.y, e.stop
        end
    end
    say(string.format("hand-in walk from Brill: %d quests, %d stops: %s", #mine, lastStop, (function()
        local parts = {}
        for _, e in ipairs(mine) do parts[#parts + 1] = e.stop .. ". " .. e.name .. string.format(" (%.0f, %.0f)", e.place.x, e.place.y) end
        return table.concat(parts, ", ")
    end)()))
    -- Two quests at one spot are one stop.
    local byStop = {}
    for _, e in ipairs(mine) do byStop[e.stop] = (byStop[e.stop] or 0) + 1 end
    local shared = false
    for _, n in pairs(byStop) do if n > 1 then shared = true end end
    assert(shared, "two quests handed in at one spot are not one stop")
    -- In the window: numbered.
    SlashCmdList.UNDEADROUTE("") -- open
    local head = plain(W.detail.ready.head.text or "")
    assert(head:find("in walking order", 1, true), "the window does not say the hand-ins are in walking order: " .. head)
    SlashCmdList.UNDEADROUTE("")
    local tr = trackerText()
    assert(tr:find("stops, nearest first", 1, true) and tr:find("  1%. ") and tr:find("  2%. "),
        "the tracker does not number the hand-in stops: " .. tr)
    say("tracker: " .. (tr:match("Ready to hand in[^\n]*") or "") .. " / " .. (tr:match("  1%. [^\n]*") or ""))
    C_Map.GetPlayerMapPosition = nil
    -- Without your spot (an instance), it still orders them, from a stop on your map.
    assert(#ns.ReadyToHandIn() >= #picked, "no hand-ins without your spot")
    for _, q in ipairs(picked) do inlog[q.id] = nil end
    mapId = savedMap
    out = {}
end

-- Walking order from where you stand: the nearest giver of the open batch first, the nearest objective camp,
-- and a camp two quests in your log share before a lone one about as far. Two of the batch's quests are moved
-- to known spots for it, and put back after.
do
    local I = ns.I
    local rec, plan -- a stage whose open batch has two quests to pick up
    for _, stage in ipairs(ns.Stages) do
        local p = stage.kind == "zone" and I.CurrentBatch(stage)
        if p and #p.pickup >= 2 and not rec then rec, plan = stage, p end
    end
    assert(rec, "no open batch with two quests to pick up to test the walking order")
    local a, b = plan.pickup[1].task, plan.pickup[2].task
    local map = a.zmap
    local saved = {}
    for _, t in ipairs({ a, b }) do
        saved[t] = { map = t.map, x = t.x, y = t.y, zmap = t.zmap, spot = t.quest.spot, camps = t.quest.camps }
        t.map, t.zmap = map, map
    end
    local savedMap, savedPos, savedFocus = mapId, C_Map.GetPlayerMapPosition, UndeadRouteDB.focus
    UndeadRouteDB.focus = nil
    mapId = map
    local px, py = 0, 0
    C_Map.GetPlayerMapPosition = function() return { GetXY = function() return px / 100, py / 100 end } end
    local function standAt(x, y) px, py = x, y end
    -- Givers at (20, 20) and (80, 80): whichever you stand by comes first, in the arrow and in the guide's order.
    a.x, a.y, b.x, b.y = 20, 20, 80, 80
    standAt(78, 80)
    local step = I.NextStep(rec)
    assert(step and step.kind == "pickup" and step.id == b.id, "the nearest giver is not first: " .. tostring(step and step.title))
    local sorted = I.WalkSort(rec, level, plan.pickup, "pickup")
    assert(sorted[1].task == b, "the guide's pick-ups are not nearest first")
    standAt(22, 20)
    step = I.NextStep(rec)
    assert(step and step.id == a.id, "standing by the other giver does not make it first: " .. tostring(step and step.title))
    say("nearest giver: " .. step.title)
    -- A in the log, its objectives at two camps: the arrow goes to the camp you stand nearer.
    inlog[a.id] = true
    a.quest.camps, a.quest.spot = { { 10, 10 }, { 50, 50 } }, { 30, 30 }
    UndeadRouteDB.focus = a.id -- the batch's other pick-up aside
    standAt(12, 10)
    step = I.NextStep(rec)
    assert(step.kind == "work" and step.x == 10 and step.y == 10, "not the nearest camp: " .. step.x .. ", " .. step.y)
    standAt(48, 50)
    step = I.NextStep(rec)
    assert(step.x == 50 and step.y == 50, "the arrow does not move on to the camp now nearer: " .. step.x .. ", " .. step.y)
    -- B in the log too, its work by A's far camp: from halfway, the shared camp wins, as one step for both.
    inlog[b.id] = true
    b.quest.camps, b.quest.spot = nil, { 52, 51 }
    standAt(30, 30)
    step = I.NextStep(rec)
    assert(step.x == 50 and step.y == 50, "the shared camp does not win from halfway: " .. step.x .. ", " .. step.y)
    assert(step.title:find(" + ", 1, true), "two quests at one camp are not one step: " .. step.title)
    local sharedTitle = step.title
    -- Close by the lone camp, the lone camp still comes first.
    standAt(11, 10)
    step = I.NextStep(rec)
    assert(step.x == 10 and step.y == 10, "a shared camp far away beats the camp you stand at")
    say("camps: nearest first, a shared camp first from halfway: " .. sharedTitle)
    -- Without your spot, the shared camp.
    C_Map.GetPlayerMapPosition = nil
    step = I.NextStep(rec)
    assert(step.x == 50 and step.y == 50, "without your spot the shared camp does not win")
    inlog[a.id], inlog[b.id] = nil, nil
    for t, s in pairs(saved) do
        t.map, t.x, t.y, t.zmap, t.quest.spot, t.quest.camps = s.map, s.x, s.y, s.zmap, s.spot, s.camps
    end
    mapId, C_Map.GetPlayerMapPosition, UndeadRouteDB.focus = savedMap, savedPos, savedFocus
    fire("QUEST_LOG_UPDATE")
    out = {}
end

-- The arrow: it turns towards the place from where you face, and says how far it is, in yards.
do
    local a = UndeadRouteArrow
    assert(a and a.art, "no arrow frame")
    local savedWorld, savedVec, savedPos = C_Map.GetWorldPosFromMapPos, CreateVector2D, C_Map.GetPlayerMapPosition
    -- A map 1000 yards a side: map x runs east (world y falls), map y runs south (world x falls).
    CreateVector2D = function(x, y) return { x = x, y = y } end
    C_Map.GetWorldPosFromMapPos = function(_, v) return 1, { GetXY = function() return 1000 - v.y * 1000, 1000 - v.x * 1000 end } end
    local px, py = 50, 50
    C_Map.GetPlayerMapPosition = function() return { GetXY = function() return px / 100, py / 100 end } end
    local facing = 0
    GetPlayerFacing = function() return facing end
    local rot
    a.art.SetRotation = function(_, r) rot = r end
    -- A place 100 yards west of you (map x 10 units less), you facing north: the arrow points left (+90 degrees).
    ns.PinArrow({ map = mapId, x = 40, y = 50, title = "Test spot", key = "test" })
    local yards = ns.ArrowTick(a)
    assert(yards and math.abs(yards - 100) < 0.01, "the arrow does not say 100 yards: " .. tostring(yards))
    assert(math.abs(rot - math.pi / 2) < 1e-6, "west, facing north, is not a quarter turn left: " .. tostring(rot))
    -- Facing west it points straight ahead.
    facing = math.pi / 2
    ns.ArrowTick(a)
    assert(math.abs(rot) < 1e-6, "facing the place, the arrow does not point ahead: " .. tostring(rot))
    assert(plain(a.dist.text or ""):find("100 yds", 1, true), "the arrow does not show the yards")
    -- Arrived at a pin: it is done with, and the arrow goes back to the route.
    px = 40.5
    ns.ArrowTick(a)
    assert(arrow == nil or arrow.title ~= "Test spot", "a reached pin still holds the arrow")
    -- The quick way to your place: UnitPosition, used once it has agreed with the place worked out from the map.
    px = 50
    ns.PinArrow({ map = mapId, x = 40, y = 50, title = "Quick spot", key = "quick" })
    UnitPosition = function() return 1000 - 50 * 10, 1000 - px * 10, 0, 1 end
    assert(math.abs(ns.ArrowTick(a) - 100) < 0.01, "the arrow is off while UnitPosition is being checked")
    local mapAsks, pos = 0, C_Map.GetPlayerMapPosition
    C_Map.GetPlayerMapPosition = function(...) mapAsks = mapAsks + 1 return pos(...) end
    px = 45
    local quick = ns.ArrowTick(a)
    assert(mapAsks == 0, "the map is still asked for your place after UnitPosition agreed with it")
    assert(math.abs(quick - 50) < 0.01 and plain(a.dist.text):find("50 yds", 1, true), "the quick way gives the wrong yards: " .. tostring(quick))
    -- Where UnitPosition says nothing (an instance), the map is asked again.
    UnitPosition = function() return nil end
    assert(math.abs(ns.ArrowTick(a) - 50) < 0.01 and mapAsks > 0, "no place when UnitPosition gives none")
    UnitPosition = nil
    C_Map.GetPlayerMapPosition = pos
    ns.PinArrow(nil)
    say("arrow: 100 yds west turns a quarter left, ahead when facing it; a reached pin lets go; UnitPosition used once it agrees")
    C_Map.GetWorldPosFromMapPos, CreateVector2D, C_Map.GetPlayerMapPosition, GetPlayerFacing = savedWorld, savedVec, savedPos, nil
end

-- The quest recorder: what you take, from whom and where, what it gives, where its work moves on and who takes
-- it in where. Then laid over the generated quests: a recorded place replaces the generated one, a new quest joins.
do
    local R = ns.Recorder
    assert(R and UndeadRouteRecordDB and UndeadRouteRecordDB.quests, "no quest recorder")
    local names = { "GetQuestID", "GetTitleText", "UnitExists", "UnitName", "GetNumQuestChoices", "GetNumQuestRewards",
        "GetQuestItemInfo", "GetRewardXP", "UnitFactionGroup" }
    local saved = {}
    for _, n in ipairs(names) do saved[n] = _G[n] end
    local savedPos, savedInfo = C_Map.GetPlayerMapPosition, C_Map.GetMapInfo
    local savedObj, savedLv = C_QuestLog.GetQuestObjectives, C_QuestLog.GetQuestDifficultyLevel
    local px, py, fulfilled = 0.40, 0.50, 0
    C_Map.GetPlayerMapPosition = function() return { GetXY = function() return px, py end } end
    C_Map.GetMapInfo = function() return { name = "Hillsbrad Foothills" } end
    UnitFactionGroup = function() return "Horde" end
    GetQuestID = function() return 777001 end
    GetTitleText = function() return "Bears of the Hills" end
    UnitExists = function(u) return u == "npc" end
    UnitName = function() return "Farmer Ray" end
    GetNumQuestChoices = function() return 2 end
    GetNumQuestRewards = function() return 0 end
    GetQuestItemInfo = function(_, i) return i == 1 and "Bear Boots" or "Grey Rag", nil, 1, i == 1 and 2 or 0, true, 500 + i end
    GetRewardXP = function() return 1450 end
    C_QuestLog.GetQuestDifficultyLevel = function() return 24 end
    C_QuestLog.GetQuestObjectives = function()
        return { { text = "Bear killed: " .. fulfilled .. "/5", numFulfilled = fulfilled, numRequired = 5 } }
    end
    fire("QUEST_DETAIL")
    fire("QUEST_ACCEPTED", 777001)
    px, py, fulfilled = 0.60, 0.70, 1
    fire("QUEST_LOG_UPDATE")
    px, py, fulfilled = 0.62, 0.72, 2
    fire("QUEST_LOG_UPDATE")
    -- One kill on another map (a cave, the next zone) is counted apart: the spot here stays.
    local home = mapId
    mapId, fulfilled = 9999, 3
    fire("QUEST_LOG_UPDATE")
    mapId = home
    px, py = 0.41, 0.51
    UnitName = function() return "Farmer Ray's Wife" end
    fire("QUEST_COMPLETE")
    fire("QUEST_TURNED_IN", 777001, 1450)
    local q = UndeadRouteRecordDB.quests[777001]
    assert(q and q.name == "Bears of the Hills" and q.lv == 24 and q.req == level and q.giver == "Farmer Ray",
        "the recorder does not keep the quest's name, level and giver")
    assert(q.pick[1] == mapId and q.pick[2] == 40 and q.pick[3] == 50 and q.pick[4] == "Hillsbrad Foothills",
        "the recorder does not keep where the quest was taken")
    assert(#q.rewards == 1 and q.rewards[1][1] == 501 and q.rewards[1][3] == 2, "the recorder keeps a grey reward, or none")
    assert(q.xp == 1450 and q.sides.H and q.races[5] and q.classes[2], "the recorder does not keep the XP and who took it")
    assert(q.obj and q.obj[1]:find("Bear killed", 1, true), "the recorder does not keep the objectives")
    assert(q.spot and q.spot[4] == 2 and math.abs(q.spot[2] / q.spot[4] - 61) < 0.01, "the recorder does not see where the work moved on")
    assert(q.spot[1] == mapId and q.spotAlt and q.spotAlt[1] == 9999 and q.spotAlt[4] == 1,
        "one objective on another map threw the work spot away")
    assert(q.turnin[2] == 41 and q.ender == "Farmer Ray's Wife" and q.done == 1, "the recorder does not keep the hand-in")
    for k, v in pairs(q) do
        assert(v ~= "Testchar" and k ~= "player" and k ~= "realm", "the recorder keeps who you are")
    end
    -- Laid over the generated data.
    local list = ns.ZoneQuests[mapId]
    local g = list[1]
    local before = {}
    for k, v in pairs(g) do before[k] = v end
    local n = #list
    local changed, added = R.Apply({ [g.id] = { turnin = { mapId, 12.3, 45.6 }, giver = "Someone Else" }, [777001] = q })
    assert(g.turnin[2] == 12.3 and g.turnin[4] and g.giver == "Someone Else" and g.rec,
        "a recorded hand-in and giver do not replace the generated ones")
    local found = list[#list]
    assert(#list == n + 1 and found.id == 777001 and found.side == "H" and found.lv == 24 and found.req <= 24
        and found.spot and found.turnin and found.name == "Bears of the Hills", "a recorded quest the data lacks is not added to its zone")
    assert(changed >= 1 and added == 1, "Apply does not say what it did")
    out = {}
    SlashCmdList.UNDEADROUTE("record")
    assert(plain(out[1] or ""):find("quest recorder on: ", 1, true) and plain(out[1]):find("holds no names", 1, true),
        "/route record does not say what is kept: " .. tostring(out[1]))
    SlashCmdList.UNDEADROUTE("record off")
    assert(UndeadRouteRecordDB.off == true, "/route record off does not pause it")
    fire("QUEST_ACCEPTED", 777002)
    assert(not UndeadRouteRecordDB.quests[777002], "a paused recorder still records")
    SlashCmdList.UNDEADROUTE("record on")
    assert(not UndeadRouteRecordDB.off, "/route record on does not start it again")
    -- A quest out of the log (abandoned) is not followed any more.
    fire("QUEST_ACCEPTED", 777003)
    fire("QUEST_REMOVED", 777003)
    fulfilled = 4
    fire("QUEST_LOG_UPDATE")
    assert(not UndeadRouteRecordDB.quests[777003].spot, "an abandoned quest's objectives are still followed")
    UndeadRouteRecordDB.quests[777003] = nil
    say("recorder: giver, place, level, rewards, objectives, work spot and hand-in kept, no names; laid over the data")
    -- Back as it was, for what follows.
    for k in pairs(g) do g[k] = nil end
    for k, v in pairs(before) do g[k] = v end
    table.remove(list)
    UndeadRouteRecordDB.quests[777001] = nil
    for _, name in ipairs(names) do _G[name] = saved[name] end
    C_Map.GetPlayerMapPosition, C_Map.GetMapInfo = savedPos, savedInfo
    C_QuestLog.GetQuestObjectives, C_QuestLog.GetQuestDifficultyLevel = savedObj, savedLv
    out = {}
end

-- In the game the quest lists are built at login from the quest-data addons the player has (Build.lua): none of
-- their data ships with the route. Without them the list is empty and the route says which are missing.
do
    local keep = { ns.Dungeons, ns.ClassQuests, ns.ZoneQuests, ns.NeedLimit, ns.questSource, ns.questMissing }
    local asked = {}
    C_AddOns = { IsAddOnLoaded = function() return false end, LoadAddOn = function(name) asked[name] = true return false end }
    ns.Dungeons, ns.ClassQuests, ns.ZoneQuests, ns.NeedLimit = nil, nil, nil, nil
    local how, missing = ns.LoadQuests()
    assert(how == nil and #missing >= 3 and next(ns.ZoneQuests) == nil, "without the quest-data addons the route still has quests")
    assert(asked.NaowhForever_DiscoveryData and asked.NaowhForever_JourneysData, "the data packs that load on demand are not asked for")
    out = {}
    recorder.scripts.OnEvent(recorder, "PLAYER_LOGIN")
    assert(plain(out[1] or ""):find("no quest list", 1, true) and plain(out[1]):find("NaowhForever Discovery", 1, true),
        "the route does not say which quest-data addons are missing: " .. tostring(out[1]))
    out = {}
    SlashCmdList.UNDEADROUTE("data")
    assert(plain(table.concat(out, " ")):find("missing NaowhForever Dungeon Journal", 1, true), "/route data does not list what is missing")
    local map
    for _, stage in ipairs(ns.AllStages or ns.Stages) do if stage.maps then map = stage.maps[1] break end end
    NaowhForever = {
        Journal = { QuestData = { { name = "Test Hold", levels = { 15, 20 },
            quests = { { 900001, "Into the Hold", 16, "H", "pre", "Testland - Bob", map, 50, 50 } } } } },
        CompletoQuestData = {
            Zones = { { map = map, name = "Testland", quests = { 900003, 900002 } } },
            Quests = { [900001] = { "Into the Hold", 16, 14, 2, 0, 0 },
                [900002] = { "First Steps", 5, 4, 3, 0, 0, map, 40, 40, "Guide Bob" },
                [900003] = { "Second Steps", 6, 5, 3, 0, 0, map, 41, 41, "Guide Bob" },
                [900004] = { "Smite the Test", 10, 10, 3, 0, 2, map, 1, 1, "Trainer" } },
            Requires = { [900003] = { 900002 } }, Dungeon = {}, Repeatable = {},
        },
        JourneyQuestSpots = { [900002] = { { map, 42, 42 }, { { map, 60, 60 } } } },
    }
    ns.Dungeons, ns.ClassQuests, ns.ZoneQuests, ns.NeedLimit = nil, nil, nil, nil
    how = ns.LoadQuests()
    local zone = ns.ZoneQuests[map]
    assert(how == "built" and zone and #zone == 2 and zone[1].id == 900002 and zone[2].id == 900003, "the zone quests are not built, prerequisites first")
    assert(zone[1].giver == "Guide Bob" and zone[1].turnin[2] == 42 and zone[1].turnin[4] == "Testland" and zone[1].spot[1] == 60,
        "a built quest lacks its giver, hand-in or objective spot")
    assert(zone[2].needs and zone[2].needs[1] == 900002, "a built quest lacks its prerequisite")
    assert(ns.ClassQuests[2] and ns.ClassQuests[2][1].id == 900004 and #ns.ClassQuests[1] == 0, "class quests are not sorted to their class")
    assert(ns.Dungeons[1].name == "Test Hold" and ns.Dungeons[1].quests[1].side == "H" and ns.Dungeons[1].quests[1].pre,
        "dungeon quests are not built")
    say("quest lists built from the installed addons at login; without them it says which are missing")
    NaowhForever, C_AddOns = nil, nil
    ns.Dungeons, ns.ClassQuests, ns.ZoneQuests, ns.NeedLimit, ns.questSource, ns.questMissing = table.unpack(keep, 1, 6)
    out = {}
end

-- An old version's waypoint left in TomTom is taken out; one you set yourself, or another addon's, stays.
do
    local ours = { 1434, 0.356, 0.108, title = "Hand in: Welcome to the Jungle", from = "Undead Route" }
    local yours = { 1434, 0.5, 0.5, title = "My spot", from = "TomTom/way" }
    local removedUids = {}
    TomTom = {
        waypoints = { [1434] = { a = ours, b = yours } },
        RemoveWaypoint = function(self, uid)
            for _, byKey in pairs(self.waypoints) do
                for k, v in pairs(byKey) do if v == uid then byKey[k] = nil end end
            end
            removedUids[#removedUids + 1] = uid
        end,
    }
    local n = ns.ClearOldTomTom()
    assert(n == 1 and removedUids[1] == ours, "the route's old TomTom waypoint is not taken out")
    assert(TomTom.waypoints[1434].b == yours, "the route takes out a TomTom waypoint that is not its own")
    TomTom = nil
    assert(ns.ClearOldTomTom() == 0, "without TomTom the clean-up does not stay quiet")
    say("old TomTom waypoints of the route cleared; the player's own stay")
end

-- What other addons can ask.
local needed = UndeadRoute.NeededItems()
local lumber, kor = false, false
for _, item in ipairs(needed) do
    assert(type(item.name) == "string" and type(item.quest) == "string", "NeededItems() entry without a name or quest")
    if item.name == "Fenris Isle Key" then error("NeededItems() lists an item for a quest already handed in") end
    lumber = lumber or item.name == "Whitestone Oak Lumber"
    kor = kor or item.name == "Purified Kor Gem"
end
assert(not lumber and not kor, "NeededItems() lists A Moon-Kissed Blade's items after it was handed in")
completed[95036] = nil
for _, item in ipairs(UndeadRoute.NeededItems()) do
    if item.name == "Whitestone Oak Lumber" and item.quest == "A Moon-Kissed Blade" then lumber = true end
end
completed[95036] = true
assert(lumber, "NeededItems() leaves out the items of a class quest still to do")
say(string.format("api: %d items needed for class quests", #needed))
local status = UndeadRoute.Status()
assert(status and type(status.stage) == "string" and type(status.range) == "string" and type(status.left) == "number"
    and type(status.min) == "number" and type(status.max) == "number" and status.min <= status.max
    and type(status.ready) == "number",
    "UndeadRoute.Status() is incomplete")
say(string.format("api: %s (%s), %d open, next: %s", status.stage, status.range, status.left, tostring(status.next)))
local blade = UndeadRoute.TurnIn(95126) -- The Moonsilver Blade
assert(blade and blade.zone == "Silverpine Forest" and blade.hub == "The Sepulcher" and blade.x == 43.3 and blade.y == 41,
    "TurnIn() does not place The Moonsilver Blade at The Sepulcher")
local beast = UndeadRoute.TurnIn(6062) -- Taming the Beast, Durotar
assert(beast and beast.zone == "Durotar" and beast.hub == "Razor Hill" and beast.npc == "Gar'Thok",
    "TurnIn() does not name Gar'Thok at Razor Hill: " .. tostring(beast and beast.npc))
assert(UndeadRoute.TurnIn(1) == nil and UndeadRoute.TurnIn("x") == nil, "TurnIn() answers for a quest it has no data for")
assert(UndeadRoute.PinTurnIn(95126, "The Moonsilver Blade") == true and UndeadRoute.PinTurnIn(1) == false,
    "PinTurnIn() pins a known hand-in and refuses an unknown one")
say(string.format("api: Moonsilver Blade -> %s, %s (%s); Taming the Beast -> %s, %s", blade.hub, blade.zone,
    tostring(blade.npc), beast.npc, beast.hub))
UndeadRoute.Toggle()
assert(W:IsShown(), "UndeadRoute.Toggle() did not open the window")
-- The minimap button and the game's addon menu: click opens or closes the route, right-click the tracker.
local mini = UndeadRouteMinimapButton
assert(mini and mini.shown, "no minimap button")
mini.scripts.OnClick(mini, "LeftButton")
assert(not W:IsShown(), "a click on the minimap button does not close the route")
UndeadRoute_OnAddonCompartmentClick(nil, "LeftButton")
assert(W:IsShown(), "the addon menu entry does not open the route")
local hidden = UndeadRouteDB.tracker.hidden
mini.scripts.OnClick(mini, "RightButton")
assert(UndeadRouteDB.tracker.hidden ~= hidden, "a right-click on the minimap button does not switch the tracker")
mini.scripts.OnClick(mini, "RightButton")
mini.scripts.OnEnter(mini) mini.scripts.OnLeave(mini)
SlashCmdList.UNDEADROUTE("minimap")
assert(not mini.shown and UndeadRouteDB.minimap.hidden, "/route minimap does not hide the button")
SlashCmdList.UNDEADROUTE("minimap")
assert(mini.shown, "/route minimap does not bring the button back")
say("minimap button and addon menu: ok")
-- Quest events are drawn on the next frame: a burst in one frame once, a burst over many frames every 0.1 s.
do
    local savedAfter, waits, now = C_Timer.After, {}, 100
    GetTime = function() return now end
    C_Timer.After = function(seconds, fn) waits[#waits + 1] = { seconds, fn } end
    local route = events.scripts.OnEvent
    local body = UndeadRouteTracker.body
    W.shown = false
    route(events, "QUEST_LOG_UPDATE") route(events, "QUEST_ACCEPTED", 1) route(events, "QUEST_LOG_UPDATE")
    assert(#waits == 1 and waits[1][1] == 0, "a burst of quest events in one frame is not drawn once, on the next frame")
    body.text, body.written = "untouched", nil -- written: a text is only set again when it changes
    waits[1][2]()
    assert(body.text ~= "untouched", "the next frame did not draw")
    now = 100.03
    route(events, "QUEST_LOG_UPDATE")
    assert(#waits == 2 and math.abs(waits[2][1] - 0.07) < 1e-6, "a second draw within 0.1 s does not wait out the rest of it")
    waits[2][2]()
    C_Timer.After, GetTime = savedAfter, nil
    say("draw: on the next frame, at most every 0.1 s")
end

-- Handing in the last quest of the stage you are on moves the route on, and says so (not only a level-up does).
do
    fire("PLAYER_LEVEL_UP", 25)
    zone = "Nowhere"
    fire("ZONE_CHANGED_NEW_AREA")
    local st = UndeadRoute.Status()
    local stage
    for _, s in ipairs(ns.Stages) do
        if s.kind == "zone" and s.zone == st.stage and s.min == st.min and s.max == st.max then stage = s end
    end
    assert(stage, "no stage to finish")
    local last
    for _, t in ipairs(stage.tasks) do
        if t.id then completed[t.id] = true last = t.id end
    end
    out = {}
    fire("ZONE_CHANGED_NEW_AREA")
    assert(not told("Time to move on"), "a zone change announced a new stage")
    -- lastRec follows the zone change, so set the stage open again, then hand in its last quest.
    completed[last] = nil
    inlog[last] = "complete"
    fire("ZONE_CHANGED_NEW_AREA")
    assert(UndeadRoute.Status().min == stage.min, "the stage did not open again")
    inlog[last] = nil
    completed[last] = true
    out = {}
    fire("QUEST_TURNED_IN", last)
    assert(told("Time to move on"), "the stage's last hand-in did not say where to go next")
    say("move on: said after the last hand-in of " .. stage.zone .. " " .. stage.min .. "-" .. stage.max)
end

-- The guide (/route guide): the stage as one list of steps, the one you are on marked, and it moves on as you play.
do
    SlashCmdList.UNDEADROUTE("guide")
    local G = UndeadRouteGuide
    assert(G and G.shown, "/route guide did not open the guide")
    assert(G.title.text and G.title.text ~= "", "the guide has no title")
    local rows = 0
    for _, r in ipairs(G.list.rows) do
        if r.shown then
            rows = rows + 1
            assert(r.title.text and r.title.text ~= "", "a step without a text")
        end
    end
    assert(rows > 0, "the guide lists no steps")
    assert(plain(G.stepText.text):match("^Step %d+ of " .. rows .. "$"), "the step count is wrong: " .. G.stepText.text)
    -- A quest picked up: its pick-up step is done, and the guide moves on from it.
    local step = G.activeStep
    assert(step, "no step is marked as the one you are on")
    if step.kind == "pickup" then
        local id = step.task.id
        inlog[id] = true
        fire("QUEST_ACCEPTED", id)
        fire("QUEST_LOG_UPDATE")
        local now = G.activeStep
        assert(not (now and now.task.id == id and now.kind == "pickup"), "a quest in the log is still to be picked up")
        inlog[id] = nil
        fire("QUEST_LOG_UPDATE")
    end
    assert(UndeadRouteTracker == nil or not UndeadRouteTracker.shown, "the tracker shows while the guide is open")
    SlashCmdList.UNDEADROUTE("guide")
    assert(not G.shown, "/route guide did not close the guide")
    say("guide: " .. rows .. " steps for " .. plain(G.title.text) .. ", moves on after a pick-up (" .. step.kind .. " first)")
    -- The looks: the gear's menu steps through them, the guide built again in each, open and filled, back to Classic.
    SlashCmdList.UNDEADROUTE("guide")
    local seen = {}
    for _ = 1, 5 do
        local g = UndeadRouteGuide
        local item
        for _, it in ipairs(g.settings.items) do
            if it.label():find("^Look: ") then item = it end
        end
        assert(item, "no look to pick in the gear's menu")
        seen[#seen + 1] = item.label():sub(7)
        item.scripts.OnClick(item)
        local now = UndeadRouteGuide
        assert(now ~= g and now.shown and not g.shown, "picking a look did not build the guide again in its place")
        assert(now.title.text and now.title.text ~= "" and now.list.rows[1] and now.list.rows[1].shown,
            "the guide in a new look is empty")
    end
    assert(UndeadRouteDB.guide.theme == "Classic" and #seen == 5, "five picks did not come back to Classic")
    SlashCmdList.UNDEADROUTE("guide")
    say("looks: " .. table.concat(seen, ", "))
end
say("ALL OK")
