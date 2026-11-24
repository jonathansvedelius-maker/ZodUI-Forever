local ADDON, ns = ...

-- Undead Route's wiring: the reminders, the minimap button, the functions for other addons (UndeadRoute.*),
-- the events and the /route command. The route's logic is Route.lua's and the frames are Window.lua's:
-- what this file uses of them comes from ns.I, and the look from ns.T.

local I, T = ns.I, ns.T
local Print, Plain, Level, QuestDone, TakeZodUIQuests, InLog = I.Print, I.Plain, I.Level, I.QuestDone, I.TakeZodUIQuests, I.InLog
local NeedsMet, QuestName, RewardText, BuildStages, TaskState, Status = I.NeedsMet, I.QuestName, I.RewardText, I.BuildStages, I.TaskState, I.Status
local Recommend, ReadyToHandIn, CurrentBatch, NextStep, QuestsLeft, DungeonsInRange = I.Recommend, I.ReadyToHandIn, I.CurrentBatch, I.NextStep, I.QuestsLeft, I.DungeonsInRange
local xpAsked, RankedDungeons, XPText, ClassQuests, OpenTasks, RangeText = I.xpAsked, I.RankedDungeons, I.XPText, I.ClassQuests, I.OpenTasks, I.RangeText
local StageName, Where, CLASS, ClassStage, SetLevel, PinAt = I.StageName, I.Where, I.CLASS, I.ClassStage, I.SetLevel, I.PinAt
local BuildTracker, RefreshTracker, Refresh, Select, WindowShown, TrackerFight = I.BuildTracker, I.RefreshTracker, I.Refresh, I.Select, I.WindowShown, I.TrackerFight

local db -- the character's saved settings, set when the addon has loaded

---------------------------------------------------------------------------
-- Reminders
---------------------------------------------------------------------------

-- A line across the middle of the screen, with the raid-warning sound.
local function Alert(msg)
    if RaidNotice_AddMessage and RaidWarningFrame and ChatTypeInfo and ChatTypeInfo["RAID_WARNING"] then
        RaidNotice_AddMessage(RaidWarningFrame, msg, ChatTypeInfo["RAID_WARNING"])
    elseif UIErrorsFrame then
        UIErrorsFrame:AddMessage(msg, 1, 0.82, 0)
    end
    if PlaySound and SOUNDKIT and SOUNDKIT.RAID_WARNING then pcall(PlaySound, SOUNDKIT.RAID_WARNING) end
end

local function BlueNames(tasks)
    local parts = {}
    for _, task in ipairs(tasks) do
        local s = RewardText(task.quest.rewards, 3)
        if s ~= "" then parts[#parts + 1] = s end
    end
    return table.concat(parts, " ")
end

-- Says which quests of a dungeon are still to pick up, and where.
local function ListDungeonQuests(stage, left)
    local level = Level()
    for _, task in ipairs(left) do
        local q = task.quest
        local state = InLog(q.id) and "|cff59d973in your log|r"
            or (q.lv > level and ("from level " .. q.lv))
            or (q.inside and "starts inside or from a drop")
            or (q.pre and "has a prerequisite chain: start now")
            or "pick up"
        local rewards = RewardText(q.rewards, 3)
        print(string.format("   %s%s|r (%s)%s  |cff999999%s|r", T.Accent(), q.name, state,
            rewards ~= "" and ("  " .. rewards) or "", Where(q)))
    end
end

-- Dungeon reminders, once each per character: when a dungeon opens for you,
-- at its best level, and in its last level. `quiet` (at login): chat only.
local function RemindDungeons(quiet)
    local level = Level()
    local names = {}
    for _, stage in ipairs(DungeonsInRange()) do
        local left, blues = QuestsLeft(stage)
        if #left > 0 then
            local kind = (level >= stage.max - 1 and "last") or (level >= stage.best and "best") or "open"
            local key = stage.key .. ":" .. kind
            if not db.reminded[key] then
                db.reminded[key] = true
                local head = (kind == "last") and "Last levels for %s (%s)"
                    or (kind == "best") and "Best time for %s (%s)" or "%s is open (%s)"
                local msg = string.format(head, stage.hub, RangeText(stage))
                    .. string.format(": %d quest%s left", #left, #left == 1 and "" or "s")
                if #blues > 0 then msg = msg .. ", blue: " .. BlueNames(blues) end
                if quiet then
                    names[#names + 1] = stage.hub
                else
                    Alert(msg)
                    Print(msg)
                    ListDungeonQuests(stage, left)
                end
            end
        end
    end
    -- At login one line, not every quest of every dungeon.
    if #names > 0 then
        Print(string.format("Dungeon quests waiting: %s. /route dungeons lists them.", table.concat(names, ", ")))
    end
end

-- Class-quest reminders: each quest once, when it becomes available.
local function RemindClass(quiet)
    local open = ClassQuests()
    local new, first = 0, nil
    for _, task in ipairs(open) do
        local key = "pal:" .. task.id
        if not InLog(task.id) and not db.reminded[key] then
            db.reminded[key] = true
            local q = task.quest
            local msg = string.format("%s quest available: %s", CLASS.name, q.name)
            local rewards = RewardText(q.rewards)
            if quiet then
                new, first = new + 1, first or q.name
            else
                Alert(msg)
                Print(string.format("|c" .. CLASS.hex .. "%s|r%s  |cff999999%s|r", msg, rewards ~= "" and ("  " .. rewards) or "", Where(q)))
            end
        end
    end
    if new > 0 then
        Print(string.format("|c" .. CLASS.hex .. "%d " .. CLASS.name .. " quest%s available|r, starting with %s. /route and open " .. CLASS.name .. " class quests.",
            new, new == 1 and "" or "s", first))
    end
end

-- Standing in a city with open city quests, or in a zone with quests to pick up for a dungeon in range (or opening
-- within two levels), or a class quest: say so, once per session each.
local told = {}
local function RemindHere()
    local mapId = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    if not mapId then return end
    local level = Level()
    local function Tell(task, why)
        local q = task.quest
        if task.map == mapId and not told[q.id] and not q.inside and not q.classic and q.lv <= level
            and not QuestDone(q.id) and not InLog(q.id) and NeedsMet(q) then
            told[q.id] = true
            local rewards = RewardText(q.rewards, 3)
            Print(string.format("While you are here, pick up %s%s|r for %s%s  |cff999999%s|r", T.Accent(), q.name, why,
                rewards ~= "" and ("  " .. rewards) or "", Where(q)))
        end
    end
    -- Arriving in a route zone for the first time: flight path and hearthstone.
    local here = GetRealZoneText and GetRealZoneText()
    for _, stage in ipairs(ns.Stages) do
        if (stage.kind == "zone" or stage.kind == "alt") and stage.zone == here and stage.max > 5
            and not db.reminded["arrive:" .. here] and Status(stage, level) == "now" then
            db.reminded["arrive:" .. here] = true
            local bind = GetBindLocation and GetBindLocation()
            Print(string.format("Arrived in %s. Take the flight path, and set your hearthstone if you are staying: %s.%s",
                here, stage.hub, bind and (" It is set to " .. bind .. " now.") or ""))
            break
        end
    end
    -- In a capital with new spells waiting since your last even level.
    -- Said once for each level's spells, not again at every login or /reload in the same city.
    if db.train and not told["train" .. mapId] and db.reminded["train:" .. mapId] ~= db.train then
        for _, stage in ipairs(ns.Stages) do
            if stage.kind == "city" and stage.maps[1] == mapId then
                told["train" .. mapId] = true
                db.reminded["train:" .. mapId] = db.train
                local msg = string.format("Train while you are in %s: new spells since level %d", stage.zone, db.train)
                Alert(msg)
                Print(msg .. ".")
                break
            end
        end
    end
    -- A city with quests you can pick up there right now: one alert per session, naming a few.
    for _, stage in ipairs(ns.Stages) do
        if stage.kind == "city" and stage.maps[1] == mapId and not told[stage.key] and not db.stages[stage.key]
            and db.reminded["city:" .. stage.key] ~= level then -- once a level, not at every login
            local names = {}
            for i, task in ipairs(stage.tasks) do
                if task.id and task.map == mapId and TaskState(stage, i, level) == "do" then
                    names[#names + 1] = QuestName(task.quest)
                end
            end
            if #names > 0 then
                told[stage.key] = true
                db.reminded["city:" .. stage.key] = level
                local msg = string.format("%s: %d quest%s to pick up here", stage.zone, #names, #names == 1 and "" or "s")
                local more = #names > 4 and string.format(" and %d more", #names - 4) or ""
                for i = #names, 5, -1 do names[i] = nil end
                Alert(msg)
                Print(string.format("%s: %s%s|r%s. Type /route and open %s for where.", msg, T.Accent(),
                    table.concat(names, "|r, " .. T.Accent()), more, stage.zone))
            end
        end
    end
    for _, stage in ipairs(ns.Stages) do
        if stage.kind == "dungeon" and not stage.ally and not db.stages[stage.key]
            and level >= stage.min - 2 and level <= stage.max then
            for _, task in ipairs(stage.tasks) do
                if task.id then Tell(task, stage.hub) end
            end
        end
    end
    local classStage = ClassStage()
    if classStage then
        for _, task in ipairs(classStage.tasks) do
            if (task.req or 1) <= level then
                local q = task.quest
                Tell({ quest = { id = q.id, name = q.name, lv = q.req, needs = q.needs, classic = q.classic,
                    rewards = q.rewards, giver = q.giver, zone = q.zone, x = q.x, y = q.y }, map = task.map },
                    "your " .. CLASS.name .. " chain")
            end
        end
    end
end

---------------------------------------------------------------------------
-- TomTom's old waypoints
---------------------------------------------------------------------------

-- Versions before 1.21 put their pins in TomTom too, which keeps waypoints across logins: one left there still
-- drew TomTom's arrow. The route no longer uses TomTom, so it takes out the waypoints it made (from = "Undead
-- Route") and leaves TomTom and everything else in it alone. Returns how many it removed.
function ns.ClearOldTomTom()
    local tt = _G.TomTom
    if type(tt) ~= "table" or type(tt.waypoints) ~= "table" or type(tt.RemoveWaypoint) ~= "function" then return 0 end
    local ours = {}
    for _, byKey in pairs(tt.waypoints) do
        if type(byKey) == "table" then
            for _, uid in pairs(byKey) do
                if type(uid) == "table" and uid.from == "Undead Route" then ours[#ours + 1] = uid end
            end
        end
    end
    local removed = 0
    for _, uid in ipairs(ours) do
        if pcall(tt.RemoveWaypoint, tt, uid) then removed = removed + 1 end
    end
    return removed
end

---------------------------------------------------------------------------
-- The minimap button and the game's addon menu (the button by the minimap)
---------------------------------------------------------------------------

local ICON = "Interface\\AddOns\\UndeadRoute\\Media\\Icon" -- tools/icon.js draws it
local mini

-- What a click does, from the minimap button or the addon menu: left opens the route, right the tracker.
local function IconClick(mouse)
    if not ns.ready then return end
    if mouse == "RightButton" then
        SlashCmdList.UNDEADROUTE("tracker")
        Print("tracker " .. (db.tracker.hidden and "off" or "on") .. ".")
    else
        ns.Toggle()
    end
end

-- Its tooltip: where the route wants you, what is ready to hand in, and what the clicks do.
local function IconTip(owner)
    if not (GameTooltip and GameTooltip.SetOwner) then return end
    GameTooltip:SetOwner(owner, "ANCHOR_LEFT")
    GameTooltip:AddLine("Undead Route", 1, 0.82, 0)
    if ns.ready then
        local rec = Recommend()
        GameTooltip:AddLine(string.format("Level %d: %s, %s (%s)", Level(), rec.zone, rec.hub, RangeText(rec)), 1, 1, 1)
        local n = #ReadyToHandIn()
        if n > 0 then GameTooltip:AddLine(n .. " ready to hand in", 0.35, 0.85, 0.45) end
    end
    GameTooltip:AddLine("Click: the route   Right-click: the tracker   Drag: move", 0.6, 0.6, 0.6)
    GameTooltip:Show()
end

local function PlaceMini()
    local angle = math.rad(db.minimap.angle or 200)
    local radius = (Minimap:GetWidth() or 140) / 2 + 6
    mini:ClearAllPoints()
    mini:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

local function BuildMini()
    if mini or not Minimap then return end
    local b = CreateFrame("Button", "UndeadRouteMinimapButton", Minimap)
    mini = b
    -- As the game's own minimap buttons: a dark round background, the icon, and the gold tracking ring over it.
    b:SetSize(31, 31)
    b:SetFrameStrata("MEDIUM")
    b:SetFrameLevel((Minimap:GetFrameLevel() or 0) + 10)
    b.back = b:CreateTexture(nil, "BACKGROUND")
    b.back:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    b.back:SetSize(20, 20)
    b.back:SetPoint("TOPLEFT", 7, -5)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetTexture(ICON)
    b.icon:SetTexCoord(0.1, 0.9, 0.1, 0.9) -- inside its own bronze edge: the ring is the game's
    b.icon:SetSize(18, 18)
    b.icon:SetPoint("TOPLEFT", 7, -6)
    b.ring = b:CreateTexture(nil, "OVERLAY")
    b.ring:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    b.ring:SetSize(53, 53)
    b.ring:SetPoint("TOPLEFT", 0, 0)
    b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:RegisterForDrag("LeftButton")
    b:SetScript("OnClick", function(_, mouse) IconClick(mouse) end)
    b:SetScript("OnEnter", function(self) IconTip(self) end)
    b:SetScript("OnLeave", function() if GameTooltip and GameTooltip.Hide then GameTooltip:Hide() end end)
    -- Dragged round the minimap's edge.
    b:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local scale = Minimap:GetEffectiveScale()
            local cx, cy = GetCursorPosition and GetCursorPosition()
            if not (mx and scale and cx) then return end
            db.minimap.angle = math.deg(math.atan2(cy / scale - my, cx / scale - mx)) % 360
            PlaceMini()
        end)
    end)
    b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    PlaceMini()
    b:SetShown(not db.minimap.hidden)
end

-- The game's addon menu calls these (the .toc names them).
function UndeadRoute_OnAddonCompartmentClick(_, mouse) IconClick(mouse) end
function UndeadRoute_OnAddonCompartmentEnter(_, owner) IconTip(owner) end
function UndeadRoute_OnAddonCompartmentLeave() if GameTooltip and GameTooltip.Hide then GameTooltip:Hide() end end

-- Every generated quest by id, both factions, built the first time a hand-in is asked for.
-- Beside it, where each quest giver stands (by map), to name who takes a hand-in.
local byId, givers
local function TurnInQuest(id)
    if type(id) ~= "number" then return nil end
    if not byId then
        byId, givers = {}, {}
        local function add(list)
            for _, q in ipairs(list or {}) do
                if q.id and (not byId[q.id] or (q.turnin and not byId[q.id].turnin)) then byId[q.id] = q end
                if type(q.giver) == "string" and q.map and q.x and q.y then
                    givers[q.map] = givers[q.map] or {}
                    table.insert(givers[q.map], { q.x, q.y, q.giver })
                end
            end
        end
        for _, list in pairs(ns.ZoneQuests or {}) do add(list) end
        for _, list in pairs(ns.ClassQuests or {}) do add(list) end
        for _, d in ipairs(ns.Dungeons or {}) do add(d.quests) end
    end
    return byId[id]
end

-- The route's quest hub in `zone` closest to x, y, when one is within 4 map units.
local function HubNear(zone, x, y)
    local best, bestD
    for _, stage in ipairs(ns.AllStages or ns.Stages or {}) do
        if stage.zone == zone and type(stage.hub) == "string" and stage.x and stage.y and not stage.hub:find("[%(]") then
            local d = (stage.x - x) ^ 2 + (stage.y - y) ^ 2
            if d <= 16 and (not bestD or d < bestD) then best, bestD = stage.hub, d end
        end
    end
    return best
end

-- Who stands on a hand-in spot: a quest giver of the data at that very spot, or else the only one within 0.1
-- map units. nil when none is there or several are (a crowded hub), so a wrong name is never given.
local function NpcAt(map, x, y)
    for _, reach in ipairs({ 0.0001, 0.0101 }) do
        local found
        for _, g in ipairs(givers and givers[map] or {}) do
            if (g[1] - x) ^ 2 + (g[2] - y) ^ 2 <= reach then
                if found and found ~= g[3] then found = false break end
                found = g[3]
            end
        end
        if found then return found end
        if found == false then return nil end
    end
    return nil
end

-- For other addons (ZodUI shows this on its Home page).
UndeadRoute = {
    Toggle = function() ns.Toggle() end,
    -- Where the route wants you now and what to walk to next, or nil before login:
    -- { stage, range, min, max, kind, hub, next, left, batch } with `next` nil when nothing on the stage has a place to go,
    -- min and max the stage's levels (to arrive at, to leave at), kind its kind ("zone", "dungeon", "city", ...),
    -- ready how many quests in the log are ready to hand in (from any stage),
    -- and `batch` ({ name, done, total, pickup, work, handin }: counts of quests) nil when no batch is open.
    Status = function()
        if not (db and ns.Stages) then return nil end
        local rec, step = Recommend(), NextStep()
        local plan = CurrentBatch(rec)
        return { stage = StageName(rec), range = RangeText(rec), min = rec.min, max = rec.max, kind = rec.kind, hub = rec.hub,
            next = step and step.title or nil, ready = #ReadyToHandIn(),
            left = #OpenTasks(rec),
            batch = plan and { name = plan.batch.label, done = plan.done, total = plan.total, pickup = #plan.pickup,
                work = #plan.work, handin = #plan.handin } or nil }
    end,
    -- The items this character's class quests still ask for, from quests not yet handed in:
    -- a list of { name, quest, source }, so a bag addon or vendor can keep them. Empty before login.
    NeededItems = function()
        local out = {}
        local classStage = ClassStage()
        if not (db and classStage) then return out end
        for _, task in ipairs(classStage.tasks) do
            local q = task.quest
            if q and q.items and not QuestDone(q.id) then
                for _, item in ipairs(q.items) do
                    out[#out + 1] = { name = item[1], quest = q.name, source = item[2] }
                end
            end
        end
        return out
    end,
    -- Where a quest is handed in, from the route's quest data: { map, x, y, zone, hub, npc } or nil when the data
    -- has no hand-in for it. hub is the route's named quest hub within a few yards of the spot ("The Sepulcher"),
    -- npc the quest giver standing on the spot when only one does; either may be nil.
    TurnIn = function(questID)
        local q = TurnInQuest(questID)
        local t = q and q.turnin
        if type(t) ~= "table" or not (t[1] and t[2] and t[3]) then return nil end
        return { map = t[1], x = t[2], y = t[3], zone = t[4], hub = HubNear(t[4], t[2], t[3]), npc = NpcAt(t[1], t[2], t[3]) }
    end,
    -- Puts the map pin (and points the arrow) on where a quest is handed in, and says so in chat.
    -- false when the data has no hand-in for it.
    PinTurnIn = function(questID, title)
        local q = TurnInQuest(questID)
        local t = q and q.turnin
        if type(t) ~= "table" or not (t[1] and t[2] and t[3]) then return false end
        PinAt(t[1], t[4], t[2], t[3], "Hand in: " .. (type(title) == "string" and title or QuestName(q)))
        return true
    end,
}

local lastRec

local function Announce()
    local rec = Recommend()
    -- Not after a detour (a dungeon or a side branch): its end says "back on the route" itself.
    if lastRec and lastRec ~= rec and lastRec.kind ~= "dungeon" and lastRec.kind ~= "alt" then
        Print(string.format("Time to move on: %s, %s (%s). Type /route for the steps.", rec.zone, rec.hub,
            RangeText(rec)))
    end
    lastRec = rec
end

-- A refresh on the next frame. The quest events come in bursts: the ones of one frame are drawn once, at once
-- (not half a second later), and a burst that runs over many frames is drawn at most every GAP seconds.
local GAP = 0.1
local drawPending, lastDraw = false, 0
local function DrawNow()
    drawPending = false
    lastDraw = GetTime and GetTime() or 0
    Refresh()
end
local function Soon()
    if drawPending then return end
    if not (C_Timer and C_Timer.After) then return Refresh() end
    drawPending = true
    local wait = GAP - ((GetTime and GetTime() or 0) - lastDraw)
    C_Timer.After((wait > 0 and wait < GAP) and wait or 0, DrawNow)
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_LEVEL_UP")
events:RegisterEvent("ZONE_CHANGED_NEW_AREA")
events:RegisterEvent("QUEST_ACCEPTED")
events:RegisterEvent("QUEST_TURNED_IN")
events:RegisterEvent("QUEST_LOG_UPDATE")
events:RegisterEvent("TRAINER_CLOSED")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("QUEST_DATA_LOAD_RESULT")
events:RegisterEvent("PLAYER_ENTERING_WORLD")

-- Same name, give or take "The": the dungeon list's names against the game's instance names.
local function SameDungeon(a, b)
    local function norm(s) return (s or ""):lower():gsub("^the ", "") end
    return a ~= nil and b ~= nil and norm(a) == norm(b)
end

-- Notes going into and coming out of the dungeon of a detour: out again, the detour ends unless
-- quests wait to be handed in.
local function WatchDetour()
    if not db.detour then return end
    local inside, kind = false, nil
    if IsInInstance then inside, kind = IsInInstance() end
    local name = inside and GetInstanceInfo and GetInstanceInfo()
    local stage
    for _, s in ipairs(ns.Stages) do if s.key == db.detour then stage = s end end
    if inside and stage and SameDungeon(Plain(name), stage.dungeon) then
        db.detourIn = true
    elseif db.detourIn and not inside then
        db.detourIn, db.detourRan = nil, true
    end
end

events:SetScript("OnEvent", function(_, event, arg1)
    if event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" then
        TrackerFight(event == "PLAYER_REGEN_DISABLED")
        return
    end
    if event == "ADDON_LOADED" then
        if arg1 ~= ADDON then return end
        UndeadRouteDB = UndeadRouteDB or {}
        db = UndeadRouteDB
        db.tasks = db.tasks or {}
        db.stages = db.stages or {}
        db.window = db.window or {}
        db.tracker = db.tracker or {}
        db.arrowPos = db.arrowPos or {}
        db.minimap = db.minimap or {}
        db.reminded = db.reminded or {}
        db.turnedIn = db.turnedIn or {}
        for _, take in ipairs(ns.onDB) do take(db) end -- Route.lua and Window.lua work on it too
    elseif event == "PLAYER_LOGIN" then
        T.Adopt() -- ZodUI's look, when it is installed
        TakeZodUIQuests()
        BuildStages()
        BuildTracker()
        BuildMini()
        ns.ready = true -- the route is built: the arrow, the clicks and the keys work from here on
        lastRec = Recommend()
        Refresh()
        -- Said when it is new since the last login; the same stage again at every /reload is only noise.
        if db.lastRecKey ~= lastRec.key then
            db.lastRecKey = lastRec.key
            Print(string.format("level %d, recommended: %s, %s. Type /route.", Level(), lastRec.zone, lastRec.hub))
        end
        RemindDungeons(true)
        RemindClass(true)
        RemindHere()
        -- After TomTom has loaded its saved waypoints (its own PLAYER_LOGIN may come after this one).
        if C_Timer and C_Timer.After then C_Timer.After(3, ns.ClearOldTomTom) else ns.ClearOldTomTom() end
    elseif not ns.ready then
        return
    elseif event == "PLAYER_LEVEL_UP" then
        SetLevel(arg1)
        if arg1 and arg1 % 2 == 0 then
            db.train = arg1
            -- ZodUI says the same (with the talent point) when it is installed: once is enough.
            if not T.zod then Print(string.format("level %d: new spells at your class trainer.", arg1)) end
        end
        Announce()
        RemindDungeons()
        RemindClass()
        Refresh()
    elseif event == "TRAINER_CLOSED" then
        db.train = nil
        Refresh()
    elseif event == "ZONE_CHANGED_NEW_AREA" or event == "PLAYER_ENTERING_WORLD" then
        WatchDetour()
        if event == "ZONE_CHANGED_NEW_AREA" then RemindHere() end
        lastRec = Recommend() -- walking into another stage's zone is your own choice: nothing to announce
        Refresh()
    elseif event == "QUEST_DATA_LOAD_RESULT" then
        -- The XP of a dungeon quest has come: show it, once for a burst of answers.
        if xpAsked[tonumber(arg1) or 0] then Soon() end
    elseif event == "QUEST_TURNED_IN" then
        local id = tonumber(arg1)
        if id then db.turnedIn[id] = true end
        Soon() -- the step is ticked at once
        -- A moment later, when the game has caught up: the quest after it may have just opened, and the
        -- stage's last hand-in moves the route on.
        if C_Timer and C_Timer.After then
            C_Timer.After(1, function() Announce() RemindClass() RemindHere() Refresh() end)
        else
            Announce() RemindClass() Refresh()
        end
    else
        Soon() -- QUEST_ACCEPTED, QUEST_LOG_UPDATE
    end
end)

SLASH_UNDEADROUTE1 = "/route"
SLASH_UNDEADROUTE2 = "/undeadroute"
-- Key bindings (Options > Keybindings > Undead Route; Bindings.xml).
BINDING_HEADER_UNDEADROUTE = "Undead Route"
BINDING_NAME_UNDEADROUTE_TOGGLE = "Open or close the route"
BINDING_NAME_UNDEADROUTE_TRACKER = "Show or hide the tracker"
BINDING_NAME_UNDEADROUTE_PIN = "Pin the next step on the map"
function UndeadRoute_Key(what)
    if not ns.ready then return end
    if what == "toggle" then
        ns.Toggle()
    elseif what == "tracker" then
        SlashCmdList.UNDEADROUTE("tracker")
        if WindowShown() then -- nothing to see change while the window is open: say what happened
            Print("tracker " .. (db.tracker.hidden and "off" or "on") .. "; it shows when the route window is closed.")
        end
    elseif what == "pin" then
        local step = NextStep()
        if step and step.x then PinAt(step.map, step.zone, step.x, step.y, step.title) else Print("No map location known for the next step.") end
    end
end

SlashCmdList["UNDEADROUTE"] = function(msg)
    msg = (msg or ""):lower():match("^%s*(.-)%s*$")
    if msg == "record" or msg:find("^record ") then
        ns.Recorder.Slash(msg:match("^record%s*(.-)$"), Print)
    elseif msg == "guide" then
        ns.ToggleGuide()
    elseif msg == "data" then
        ns.Recorder.Data(Print)
    elseif msg == "minimap" then
        db.minimap.hidden = (not db.minimap.hidden) or nil
        if mini then mini:SetShown(not db.minimap.hidden) end
        Print("minimap button " .. (db.minimap.hidden and "off; the game's addon menu by the minimap still has Undead Route." or "on."))
    elseif msg == "tracker" then
        db.tracker.hidden = (not db.tracker.hidden) or nil
        Refresh()
    elseif msg == "reset" then
        local ticks, stages = 0, 0
        for _ in pairs(db.tasks) do ticks = ticks + 1 end
        for _ in pairs(db.stages) do stages = stages + 1 end
        Print(string.format("this clears %d ticked or skipped step%s, %d stage%s marked done and every reminder, "
            .. "and cannot be undone. Type /route reset confirm to do it.", ticks, ticks == 1 and "" or "s", stages,
            stages == 1 and "" or "s"))
    elseif msg == "reset confirm" then
        db.tasks, db.stages, db.reminded = {}, {}, {}
        Select(nil)
        db.window.stage = nil
        Refresh()
        Print("all ticks and reminders cleared.")
    elseif msg == "dungeons" then
        local list = RankedDungeons()
        for i, v in ipairs(list) do
            local stage, xp = v.stage, XPText(v)
            Print(string.format("%d. %s (%s, best at %d): %d quest%s left%s%s. Pick up: %s", i, stage.hub,
                RangeText(stage), stage.best, #v.left, #v.left == 1 and "" or "s", xp ~= "" and (", " .. xp) or "",
                #v.blues > 0 and (", blue: " .. BlueNames(v.blues)) or "", v.where))
            ListDungeonQuests(stage, v.left)
        end
        if #list == 0 then
            Print("no dungeon quests waiting at your level.")
        else
            Print("/route do <name> (or /route do best) pauses the route for one; /route back ends it.")
        end
    elseif msg:match("^do ") or msg == "do" then
        local want = msg:match("^do%s+(.+)$") or "best"
        local list, pick = RankedDungeons(), nil
        for _, v in ipairs(list) do
            local name = v.stage.hub:lower()
            if want == "best" or name == want or name:find(want, 1, true) or name:gsub("^the ", ""):find(want, 1, true) then
                pick = v
                break
            end
        end
        if not pick then
            Print("no dungeon with quests left at your level matches \"" .. want .. "\". /route dungeons lists them.")
        else
            local stage = pick.stage
            db.detour, db.detourIn, db.detourRan = stage.key, nil, nil
            WatchDetour()
            lastRec = stage -- no "time to move on" for this
            Select(stage)
            db.window.stage = nil
            Refresh()
            Print(string.format("detour: %s. %d quest%s to pick up or do first (%s); the tracker and arrow lead there. "
                .. "/route back ends it.", stage.hub, #pick.left, #pick.left == 1 and "" or "s", pick.where))
        end
    elseif msg:match("^follow ") or msg == "follow" then
        -- A side branch leads the same way a dungeon detour does, until its quests are done or outleveled.
        local want = msg:match("^follow%s+(.+)$")
        local level, pick, names = Level(), nil, {}
        for _, stage in ipairs(ns.Stages) do
            if stage.kind == "alt" and Status(stage, level) == "now" then
                names[#names + 1] = stage.zone
                if want and not pick and (stage.key == want or stage.zone:lower():find(want, 1, true)
                    or stage.hub:lower():find(want, 1, true)) then
                    pick = stage
                end
            end
        end
        if not pick then
            Print(#names == 0 and "no side branch is in range at your level."
                or ((want and ("no side branch in range matches \"" .. want .. "\". ") or "")
                    .. "/route follow <zone> leads through one of: " .. table.concat(names, ", ") .. "."))
        else
            db.detour, db.detourIn, db.detourRan = pick.key, nil, nil
            lastRec = pick -- no "time to move on" for this
            Select(pick)
            db.window.stage = nil
            Refresh()
            Print(string.format("side branch: %s, %s. The tracker and arrow lead there until its quests are done; "
                .. "/route back ends it.", pick.zone, pick.hub))
        end
    elseif msg == "back" then
        if not db.detour then
            Print("no detour on: the route leads already.")
        else
            db.detour, db.detourIn, db.detourRan = nil, nil, nil
            lastRec = Recommend()
            Select(lastRec)
            db.window.stage = nil
            Refresh()
            Print("back on the route: " .. lastRec.zone .. ", " .. lastRec.hub .. ".")
        end
    elseif msg == "paladin" or msg == "class" then
        Print("the class quests follow your class: open " .. CLASS.name .. " class quests in /route.")
    elseif msg == "arrow" then
        db.arrow = (db.arrow == false) and true or false
        Refresh()
        Print("arrow to the next step " .. (db.arrow and "on" or "off") .. ".")
    elseif msg:match("^font") and T.zod then
        Print("the text size follows ZodUI's: /zod settings, General, Text size.")
    elseif msg:match("^font") then
        local n = tonumber(msg:match("^font%s+(%-?%d+)$"))
        if n and n >= 0 and n <= 6 then
            db.font = n
            T.ApplyFont()
            if RefreshTracker then RefreshTracker() end
            Print("text size set to " .. n .. " pixels over the default.")
        else
            Print("text is " .. (db.font or 2) .. " pixels over the default. /route font 0 to 6 changes it.")
        end
    elseif msg == "help" then
        Print("/route opens the window. /route guide opens the new step-by-step guide. /route dungeons ranks the dungeons worth doing now. /route do <name> pauses the route for one, /route follow <zone> does the same for a side branch, /route back ends it. "
            .. "/route tracker shows or hides the small panel. /route minimap hides or shows the minimap button. /route record says what the quest recorder has kept (off/on pauses it). /route data says where the quest list comes from. /route arrow turns the arrow to the next step on or off (drag it to move it). "
            .. "/route font 0 to 6 sets the text size. "
            .. "/route reset clears your ticks and reminders. "
            .. "In the window: the NOW box lists the batch of quests to carry together (pick up, do, hand in); "
            .. "click a line in it to pin where to go. READY TO HAND IN under it lists every finished quest in your log, "
            .. "from any stage, with where it goes. Click a tip to tick it, point at a quest for its Skip button, "
            .. "right-click a step to pin where it starts.")
    else
        ns.Toggle()
    end
end
