local _, ns = ...

-- Undead Route: a level-aware walk through a 1-60 leveling route, for every race and class of both
-- factions (it began as the Horde Undead route, hence the name). The route is picked at login.
-- The window lists every stage on the left and the selected stage's steps on
-- the right. The stage it recommends follows the character's level, the zone
-- they are standing in, and what they have done.
--   Data.lua     the hand-written routes: stages per faction and race, travel and tips
--   Build.lua    the quests of every zone and dungeon on them, and every class's quests, read at login from the
--                installed quest-data addons (the tests load Generated.lua, a copy of what it makes)
--   Route.lua    this file: the stage list for this character and the route's logic. It makes no frames.
--   Window.lua   the route window, the tracker, the arrow and the widgets they are made of
--   Core.lua     the reminders, the minimap button, the functions for other addons, the events and /route
-- Steps that are quests (they carry a quest id) tick themselves off from the
-- game's own quest log, and drive the dungeon and class-quest reminders.
--
-- The three files share no locals: Window.lua and Core.lua take what they use of this one from ns.I
-- (filled at the end of this file) and the look from ns.T.

-- The look: one table holds the palette and the widget builders (Window.lua adds those), so the whole window
-- can take ZodUI's look when ZodUI is installed (T.Adopt at login) and keep this copy of it otherwise.
local T = {
    WHITE = "Interface\\Buttons\\WHITE8x8",
    TICK = "Interface\\RaidFrame\\ReadyCheck-Ready",
    -- Flat dark palette, gold accent: the same values as ZodUI's.
    GOLD = { 1, 0.82, 0 },
    WINDOW = { 0.06, 0.06, 0.08 },
    SURFACE = { 0.14, 0.14, 0.17 },
    HOVER = { 0.20, 0.20, 0.24 },
    BORDER = { 0.25, 0.25, 0.25 },
    DIM = { 0.6, 0.6, 0.6 },
    FAINT = { 0.4, 0.4, 0.4 }, -- finished and inactive text only: too weak for anything you can click
    MUTED = { 0.55, 0.55, 0.55 },
    PINK = { 0.96, 0.55, 0.73 }, -- the character's class color (the Paladin's until login sets it)
}

-- A color as the "ffRRGGBB" of a |c code.
function T.Hex(c)
    return string.format("ff%02x%02x%02x", math.floor(c[1] * 255), math.floor(c[2] * 255), math.floor(c[3] * 255))
end

-- The |c code of the accent, read each time, so text in chat and the windows follows ZodUI's accent.
function T.Accent()
    return "|c" .. T.Hex(T.GOLD)
end

local QUALITY = { [2] = "ff1eff00", [3] = "ff0070dd", [4] = "ffa335ee", [5] = "ffff8000" }

-- The character's saved settings. They are not loaded yet when the files run: Core.lua hands them to every
-- function in ns.onDB once they are.
local db
ns.onDB = { function(saved) db = saved end }
local levelNow -- set on PLAYER_LEVEL_UP, where UnitLevel still returns the old level
local classStage -- the character's class quests, as a stage
local classID, raceID
local side -- "A" (Alliance) or "H" (Horde): the generated data's side codes
-- The character's class, for the class-quest lines: set at login (ClassInfo).
local CLASS = { file = "PALADIN", name = "Paladin", hex = "fff58cba", short = "Pal" }

local function Print(msg)
    print(T.Accent() .. "Undead Route:|r " .. msg)
end

local function Plain(v) -- nil for a value the client hands back as secret
    if issecretvalue and issecretvalue(v) then return nil end
    return v
end

-- The game answers 0 (or nothing) for a moment while logging in or out: the last level it did give stands.
local levelSeen
local function Level()
    if levelNow then return levelNow end
    local v = Plain(UnitLevel("player"))
    if type(v) == "number" and v > 0 then levelSeen = v end
    return levelSeen or 1
end

local function HasBit(mask, n) -- is bit n (1 = lowest) set? Race masks pass 32 bits, so no bit library.
    return math.floor(mask / 2 ^ (n - 1)) % 2 == 1
end

---------------------------------------------------------------------------
-- Quests
---------------------------------------------------------------------------

-- While a refresh draws (I.Remember), each answer of the game about a quest, each step's state, the recommended
-- stage and the hand-in list are worked out once and kept: one refresh asks for the same ones several times over.
-- Outside a refresh nothing is kept, so a click or a command always reads the game as it is.
local memo
local memoDepth = 0
local function Remember(on)
    if on then
        memoDepth = memoDepth + 1
        if memoDepth == 1 then memo = { done = {}, inlog = {}, complete = {}, state = {}, started = {} } end
    else
        memoDepth = math.max(0, memoDepth - 1)
        if memoDepth == 0 then memo = nil end
    end
end

-- Done when the game says so, or when this character was seen handing it in. The game never flags a
-- repeatable quest as done (such as Forever's Seeking the Kor Gem), so the route keeps its own list.
local function QuestDone(id)
    if db and db.turnedIn and db.turnedIn[id] then return true end
    local kept = memo and memo.done
    local v = kept and kept[id]
    if v == nil then
        v = C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted and C_QuestLog.IsQuestFlaggedCompleted(id) or false
        if kept then kept[id] = v end
    end
    return v
end

-- At login: the quests ZodUI saw this character hand in, from before the route kept its own list.
local function TakeZodUIQuests()
    local list = type(ZodUICharDB) == "table" and ZodUICharDB.questsDone
    if type(list) ~= "table" then return 0 end
    local n = 0
    for _, q in ipairs(list) do
        local id = type(q) == "table" and tonumber(q.id)
        if id and not db.turnedIn[id] then
            db.turnedIn[id] = true
            n = n + 1
        end
    end
    return n
end

local function InLog(id)
    local kept = memo and memo.inlog
    local v = kept and kept[id]
    if v == nil then
        v = C_QuestLog and C_QuestLog.IsOnQuest and C_QuestLog.IsOnQuest(id) or false
        if kept then kept[id] = v end
    end
    return v
end

-- In the log with every objective met: ready to hand in.
local function Complete(id)
    local kept = memo and memo.complete
    local v = kept and kept[id]
    if v == nil then
        if C_QuestLog and C_QuestLog.IsComplete then v = C_QuestLog.IsComplete(id) or false
        elseif IsQuestComplete then v = IsQuestComplete(id) or false
        else v = false end
        if kept then kept[id] = v end
    end
    return v
end

-- Race masks: bit (id - 1) for the Classic races. WoW Forever's Skyborne (race ids 95 and 96) have
-- bits 32 and 33, and also pass a mask that lets in every Classic race of their faction, since
-- faction-wide masks often leave the Skyborne bit out.
local SKYBORNE_BIT = { [95] = 33, [96] = 34 } -- as n for HasBit
local FACTION_RACES = { A = { 1, 3, 4, 7 }, H = { 2, 5, 6, 8 } }

local function RaceAllowed(mask, rid, sideCode)
    if rid <= 32 then return HasBit(mask, rid) end
    if SKYBORNE_BIT[rid] and HasBit(mask, SKYBORNE_BIT[rid]) then return true end
    local classic = FACTION_RACES[sideCode]
    if not classic then return false end
    for _, r in ipairs(classic) do
        if not HasBit(mask, r) then return false end
    end
    return true
end

-- Whether a character of side `sideCode` ("A" / "H"), race `rid` and class `cid` may take quest `q`
-- (or any table with side / race / class limits). A nil character field is not checked.
local function QuestAllowed(q, sideCode, rid, cid)
    if q.side and sideCode and q.side ~= sideCode then return false end
    if q.race and rid and not RaceAllowed(q.race, rid, sideCode) then return false end
    if q.class and cid and not HasBit(q.class, cid) then return false end
    return true
end
ns.QuestAllowed = QuestAllowed

-- Whether this character's side, class and race may take quest `q`.
local function Eligible(q)
    return QuestAllowed(q, side, raceID, classID)
end

-- Whether prerequisite `id` counts for this character: one another side, race or class takes does not.
local function NeedApplies(id)
    local limit = ns.NeedLimit and ns.NeedLimit[id]
    return not limit or Eligible(limit)
end

-- Whether a prerequisite is met: handed in, or one this character could never take.
local function NeedMet(id)
    return not NeedApplies(id) or QuestDone(id)
end

-- Whether the quests `q` needs are handed in. An entry that is a list means any one of them,
-- counting only those this character can take (none at all: it is met).
local function NeedsMet(q)
    for _, need in ipairs(q.needs or {}) do
        if type(need) == "table" then
            local any, counted = false, 0
            for _, id in ipairs(need) do
                if NeedApplies(id) then
                    counted = counted + 1
                    if QuestDone(id) then any = true break end
                end
            end
            if counted > 0 and not any then return false end
        elseif not NeedMet(need) then
            return false
        end
    end
    return true
end

-- Whether `q` is no longer offered: a quest that replaces it, or follows it, is done or in the log.
local function Closed(q)
    for _, id in ipairs(q.closed or {}) do
        if QuestDone(id) or InLog(id) then return true end
    end
    return false
end

local function QuestName(q)
    return q.part and (q.name .. " (part " .. q.part .. ")") or q.name
end

-- The name of the first quest `q` still waits for, if this addon knows it.
local questNames = {}
local function WaitsFor(q)
    for _, need in ipairs(q.needs or {}) do
        for _, id in ipairs(type(need) == "table" and need or { need }) do
            if not NeedMet(id) and questNames[id] then return questNames[id] end
        end
    end
end

local function RewardText(rewards, minQuality)
    local parts = {}
    for _, r in ipairs(rewards or {}) do
        if r[3] >= (minQuality or 2) then
            parts[#parts + 1] = "|c" .. (QUALITY[r[3]] or "ffffffff") .. "[" .. r[2] .. "]|r"
        end
    end
    return table.concat(parts, " ")
end

local function HasBlue(q)
    for _, r in ipairs(q.rewards or {}) do
        if r[3] >= 3 then return true end
    end
    return false
end

---------------------------------------------------------------------------
-- Building the stage list (once, at login: it depends on class and race)
---------------------------------------------------------------------------

-- Where each dungeon is, for those the hand-written route does not cover.
--   land    "A" / "H": the faction whose territory it is in. For the other faction it is listed, never
--           reminded about (stage.ally).
--   route   true, or "A" / "H" for one faction only: on the main route (reminders and the tracker).
--   travel  how to get there; Alliance replaces it for the Alliance when the way differs.
local DUNGEON_INFO = {
    ["Ragefire Chasm"] = { zone = "Orgrimmar", land = "H", travel = "Inside Orgrimmar, in the Cleft of Shadow." },
    ["Ruins of Lordaeron"] = { zone = "Tirisfal Glades", x = 61, y = 71, land = "H",
        travel = "In the ruins above the Undercity.", Alliance = "Tirisfal Glades, in the ruins above the Undercity: deep in Horde land." },
    ["Shadowfang Keep"] = { zone = "Silverpine Forest", x = 45, y = 68, land = "H",
        travel = "Silverpine Forest, on the cliff above Pyrewood Village.",
        Alliance = "Silverpine Forest, in Horde land: the keep is on the cliff above Pyrewood Village." },
    ["Wailing Caverns"] = { zone = "The Barrens", x = 46, y = 36, travel = "The Barrens, south-west of the Crossroads." },
    ["Blackfathom Deeps"] = { zone = "Ashenvale", x = 14, y = 14, travel = "Ashenvale, on the Zoram Strand. Fly to Zoram'gar Outpost.",
        Alliance = "Ashenvale, on the Zoram Strand. Ride north-west from Astranaar, or south from Darkshore." },
    ["Razorfen Kraul"] = { zone = "The Barrens", x = 42, y = 90, travel = "Far south of the Barrens. Fly to Camp Taurajo.",
        Alliance = "Far south of the Barrens." },
    ["Razorfen Downs"] = { zone = "The Barrens", x = 49, y = 94, travel = "Southern tip of the Barrens, by the Great Lift." },
    ["Scarlet Monastery - Graveyard"] = { zone = "Tirisfal Glades", x = 83, y = 33, route = true,
        travel = "Fly to Undercity and ride north-east. Far north-east corner of Tirisfal.",
        Alliance = "Far north-east corner of Tirisfal Glades, in Horde land. Ride north from Southshore through Alterac." },
    ["Scarlet Monastery - Library"] = { zone = "Tirisfal Glades", x = 83, y = 33, route = true,
        travel = "Fly to Undercity and ride north-east. Far north-east corner of Tirisfal.",
        Alliance = "Far north-east corner of Tirisfal Glades, in Horde land. Ride north from Southshore through Alterac." },
    ["Scarlet Monastery - Armory"] = { zone = "Tirisfal Glades", x = 83, y = 33, route = true,
        travel = "Fly to Undercity and ride north-east. Far north-east corner of Tirisfal.",
        Alliance = "Far north-east corner of Tirisfal Glades, in Horde land. Ride north from Southshore through Alterac." },
    ["Scarlet Monastery - Cathedral"] = { zone = "Tirisfal Glades", x = 83, y = 33, route = true,
        travel = "Fly to Undercity and ride north-east. Far north-east corner of Tirisfal.",
        Alliance = "Far north-east corner of Tirisfal Glades, in Horde land. Ride north from Southshore through Alterac." },
    ["Uldaman"] = { zone = "Badlands", x = 44, y = 12, travel = "North Badlands. Fly to Kargath.",
        Alliance = "North Badlands. Ride south-east from Loch Modan." },
    ["Maraudon"] = { zone = "Desolace", x = 29, y = 62, travel = "West Desolace. Fly to Shadowprey Village.",
        Alliance = "West Desolace. Fly to Nijel's Point." },
    ["Sunken Temple"] = { zone = "Swamp of Sorrows", x = 70, y = 54, travel = "The lake in the Swamp of Sorrows. Fly to Stonard.",
        Alliance = "The lake in the Swamp of Sorrows. Ride east from Duskwood through Deadwind Pass." },
    ["Blackrock Depths"] = { zone = "Searing Gorge", travel = "Inside Blackrock Mountain. Fly to Kargath or Thorium Point.",
        Alliance = "Inside Blackrock Mountain. Fly to Thorium Point or Morgan's Vigil." },
    ["Lower Blackrock Spire"] = { zone = "Burning Steppes", travel = "Inside Blackrock Mountain. Fly to Flame Crest.",
        Alliance = "Inside Blackrock Mountain. Fly to Morgan's Vigil." },
    ["Upper Blackrock Spire"] = { zone = "Burning Steppes", travel = "Inside Blackrock Mountain. Fly to Flame Crest.",
        Alliance = "Inside Blackrock Mountain. Fly to Morgan's Vigil." },
    ["Dire Maul"] = { zone = "Feralas", x = 59, y = 44, travel = "Central Feralas. Fly to Camp Mojache.",
        Alliance = "Central Feralas. Fly to Feathermoon Stronghold." },
    ["Scholomance"] = { zone = "Western Plaguelands", x = 69, y = 73, travel = "Caer Darrow, in the lake of Western Plaguelands." },
    ["Stratholme"] = { zone = "Eastern Plaguelands", x = 31, y = 12, travel = "North-west Eastern Plaguelands." },
    ["The Hall of Thanes"] = { zone = "Dun Morogh", land = "A", route = "A", travel = "Beneath Ironforge: deep in Alliance territory.",
        Alliance = "Beneath Ironforge." },
    ["The Deadmines"] = { zone = "Westfall", land = "A", route = "A", travel = "Westfall: deep in Alliance territory.",
        Alliance = "Moonbrook, in south-west Westfall." },
    ["The Stockade"] = { zone = "Stormwind City", land = "A", route = "A", travel = "Inside Stormwind: deep in Alliance territory.",
        Alliance = "Inside Stormwind City." },
    ["Gnomeregan"] = { zone = "Dun Morogh", land = "A", route = "A", travel = "Dun Morogh: deep in Alliance territory.",
        Alliance = "West Dun Morogh." },
    ["Excavation Site: Wetlands"] = { zone = "Wetlands", land = "A", route = "A", travel = "Wetlands: Alliance territory. Go as a group.",
        Alliance = "In the Wetlands." },
}

local function QuestTask(q)
    return { id = q.id, req = q.lv, quest = q, map = q.map, x = q.x, y = q.y, pinTitle = q.name }
end

-- Walking order for a stage's zone quests. Quests are banded by zone and by quest level
-- (TIER levels per band) so the list never sends you to a camp far above you. Inside a
-- band it is a nearest-neighbour tour: the closest quest giver comes next, and givers
-- within HUB map units count as one hub, where the quests are chained by where their
-- objectives are. A quest never comes before a prerequisite that is in the same stage.
local HUB, TIER = 5, 3
local BATCH, BATCH_LV, BATCH_SPREAD = 5, 3, 22

local function Dist(ax, ay, bx, by)
    local dx, dy = ax - bx, ay - by
    return math.sqrt(dx * dx + dy * dy)
end

local function WalkOrder(stage, tasks)
    local mapIndex, lowest, inStage, placed, left, out = {}, {}, {}, {}, {}, {}
    for i, map in ipairs(stage.maps) do mapIndex[map] = i end
    for _, task in ipairs(tasks) do lowest[task.zmap] = math.min(lowest[task.zmap] or 99, task.lv) end
    for i, task in ipairs(tasks) do
        inStage[task.id] = true
        task.seq = i
        task.band = mapIndex[task.zmap] * 100 + math.floor((task.lv - lowest[task.zmap]) / TIER)
        left[i] = task
    end
    local ready = {} -- once a quest's prerequisites are placed they stay placed: asked until yes, then kept
    local function Ready(task)
        if ready[task] then return true end
        local needs = task.quest.needs
        if needs then
            for _, need in ipairs(needs) do
                if type(need) == "table" then
                    local here, ok = false, false
                    for _, id in ipairs(need) do
                        if inStage[id] then here = true end
                        if placed[id] then ok = true end
                    end
                    if here and not ok then return false end
                elseif inStage[need] and not placed[need] then
                    return false
                end
            end
        end
        ready[task] = true
        return true
    end
    local zmap, px, py, wx, wy
    while #left > 0 do
        -- One pass: the lowest band with a ready quest, and the best quest in it. A lower
        -- band showing up throws the pick so far away; nothing of that band came earlier,
        -- or it would have lowered the band itself. With nothing ready (a loop in the
        -- data) every quest is scored, so the list still comes out.
        local band, pick, pickScore
        local stuck = true
        for i = 1, #left do
            if Ready(left[i]) then stuck = false break end
        end
        for i = 1, #left do
            local task = left[i]
            local tb = task.band
            if stuck or ((not band or tb <= band) and Ready(task)) then
                if not stuck and tb ~= band then band, pick, pickScore = tb, nil, nil end
                local score
                if not task.x then score = 1e6          -- start not known: last in its band
                elseif task.map ~= task.zmap then score = -1e6 -- picked up elsewhere: before the trip
                elseif task.zmap ~= zmap or not px then score = 0
                else
                    score = Dist(px, py, task.x, task.y)
                    if score <= HUB then
                        local spot = task.quest.spot
                        score = Dist(wx, wy, spot and spot[1] or task.wx, spot and spot[2] or task.wy) - 1000
                    end
                end
                if not pickScore or score < pickScore then pick, pickScore = i, score end
            end
        end
        local task = table.remove(left, pick)
        placed[task.id] = true
        out[#out + 1] = task
        if task.x and task.map == task.zmap then
            local spot = task.quest.spot
            zmap, px, py = task.zmap, task.x, task.y
            wx, wy = spot and spot[1] or task.wx, spot and spot[2] or task.wy
        end
    end
    -- Hub headings: the first quest of every run of quests picked up in one place carries
    -- the heading (task.head), so headings are not steps and do not count as such.
    local function Area(x, y)
        local ns = (y < 34 and "North") or (y > 66 and "South") or nil
        local ew = (x < 34 and "west") or (x > 66 and "east") or nil
        if ns and ew then return ns .. "-" .. ew end
        if ns then return ns end
        if ew then return (ew == "west") and "West" or "East" end
        return "Centre"
    end
    local groups, group = {}, nil
    for _, task in ipairs(out) do
        local kind = (not task.x and "unknown") or (task.map ~= task.zmap and ("away" .. task.map)) or "here"
        local near = group and group.kind == kind and group.zmap == task.zmap
            and (kind ~= "here" or Dist(group.x, group.y, task.x, task.y) <= HUB)
        if not near then
            group = { kind = kind, zmap = task.zmap, first = task, sx = 0, sy = 0, n = 0, tasks = {} }
            groups[#groups + 1] = group
        end
        group.n = group.n + 1
        group.tasks[#group.tasks + 1] = task
        if kind == "here" then
            group.x, group.y = task.x, task.y
            group.sx, group.sy = group.sx + task.x, group.sy + task.y
        end
    end
    for _, g in ipairs(groups) do
        local q, name = g.first.quest, nil
        if g.kind == "unknown" then
            name = "Start not known yet"
        elseif g.kind ~= "here" then
            name = "Picked up in " .. (q.zone or "another zone")
        else
            local x, y = g.sx / g.n, g.sy / g.n
            if stage.x and q.zone == stage.zone and Dist(stage.x, stage.y, x, y) <= 8 then
                name = stage.hub
            else
                name = Area(x, y) .. ", around " .. (q.giver or "the quest giver")
            end
            if #stage.maps > 1 then name = q.zone .. ": " .. name end
            g.where = string.format("%.0f, %.0f", x, y)
        end
        g.name = name
    end
    -- Batches: the quests of a hub you can carry at the same time, at most BATCH of them. A quest
    -- joins the open batch when it does not wait on a quest in it (the parts of a chain are never
    -- parallel), its level is within BATCH_LV of the batch's first, and its objectives lie within
    -- BATCH_SPREAD map units of the batch's first known objectives. The batches keep the walking order otherwise, and each
    -- batch's first quest carries the heading, so the arrow goes batch by batch: pick up, do, hand in.
    local done, ordered = {}, {}
    local function Free(task) -- every prerequisite in this stage is in an earlier batch
        local needs = task.quest.needs
        if not needs then return true end
        for _, need in ipairs(needs) do
            if type(need) == "table" then
                local here, ok = false, false
                for _, id in ipairs(need) do
                    if inStage[id] then here = true end
                    if done[id] then ok = true end
                end
                if here and not ok then return false end
            elseif inStage[need] and not done[need] then
                return false
            end
        end
        return true
    end
    for _, g in ipairs(groups) do
        local left, batches = {}, {}
        for i, task in ipairs(g.tasks) do left[i] = task end
        while #left > 0 do
            -- `area` is the first objective spot in the batch: a quest without a known spot (a delivery,
            -- or data that lacks it) never splits a batch.
            local batch, first, area, keep = { tasks = {}, group = g }, nil, nil, {}
            for _, task in ipairs(left) do
                local spot = task.quest.spot
                local fits = #batch.tasks < BATCH and Free(task)
                if fits and first then
                    fits = math.abs(task.lv - first.lv) <= BATCH_LV
                        and not (area and spot and Dist(area[1], area[2], spot[1], spot[2]) > BATCH_SPREAD)
                end
                if fits then
                    first, area = first or task, area or spot
                    batch.tasks[#batch.tasks + 1] = task
                else
                    keep[#keep + 1] = task
                end
            end
            if #batch.tasks == 0 then -- a prerequisite loop in the data: take the first as it stands
                batch.tasks[1] = table.remove(keep, 1)
            end
            for _, task in ipairs(batch.tasks) do done[task.id] = true end
            batches[#batches + 1] = batch
            left = keep
        end
        for k, batch in ipairs(batches) do
            local lo, hi = 99, 0
            for _, task in ipairs(batch.tasks) do
                lo, hi = math.min(lo, task.lv), math.max(hi, task.lv)
                task.batch = batch
                ordered[#ordered + 1] = task
            end
            local n = #batch.tasks
            batch.name, batch.n, batch.of = g.name, k, #batches
            batch.label = (#batches > 1) and string.format("%s, batch %d of %d", g.name, k, #batches) or g.name
            local levels = (lo == hi) and ("level " .. lo) or ("levels " .. lo .. "-" .. hi)
            batch.tasks[1].head = string.format("%s  |cff999999%s%d %s, %s|r", batch.label,
                g.where and ("(" .. g.where .. ")  ") or "", n, n == 1 and "quest" or "quests", levels)
        end
    end
    return ordered
end

-- The character's faction: UnitFactionGroup, or the race's when the client cannot say.
local function FactionOf(rid)
    local faction = UnitFactionGroup and UnitFactionGroup("player")
    if faction == "Alliance" or faction == "Horde" then return faction end
    return ns.RaceFaction and ns.RaceFaction[rid] or "Horde"
end

local function Has(list, value)
    for _, v in ipairs(list or {}) do
        if v == value then return true end
    end
    return false
end

-- The stages of `all` (Data.lua's list) for one faction ("Alliance" / "Horde") and race id, as new
-- tables, with the faction's own fields laid over each (stage.Alliance / stage.Horde; false clears a
-- field). A race in a stage's altRaces gets it as a side branch. Order is kept.
local function SelectRoute(all, faction, rid)
    local out = {}
    for _, stage in ipairs(all) do
        local mine = (not stage.faction or stage.faction == faction)
            and (not stage.races or Has(stage.races, rid) or Has(stage.altRaces, rid))
        if mine then
            local copy = {}
            for k, v in pairs(stage) do copy[k] = v end
            for k, v in pairs(stage[faction] or {}) do
                if v == false then copy[k] = nil else copy[k] = v end
            end
            copy.Alliance, copy.Horde, copy.races, copy.altRaces = nil, nil, nil, nil
            if stage.races and not Has(stage.races, rid) then copy.kind = "alt" end
            -- BuildStages adds the quests to the step list: each character gets a list of its own.
            local tasks = {}
            for i, task in ipairs(copy.tasks or {}) do tasks[i] = task end
            copy.tasks = tasks
            out[#out + 1] = copy
        end
    end
    return out
end
ns.SelectRoute = SelectRoute

-- The class's name, color and short tag, for the class-quest stage and lines.
local CLASS_COLOR = { WARRIOR = "ffc69b6d", PALADIN = "fff58cba", HUNTER = "ffaad372", ROGUE = "fffff468",
    PRIEST = "ffffffff", SHAMAN = "ff0070dd", MAGE = "ff3fc7eb", WARLOCK = "ff8788ee", DRUID = "ffff7c0a" }
local function ClassInfo(name, file)
    local hex = CLASS_COLOR[file] or "fff58cba"
    local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[file]
    if type(c) == "table" and type(c.colorStr) == "string" then hex = c.colorStr end
    local short = (name or file or "Class"):sub(1, 3)
    return { file = file, name = name or file or "Class", hex = hex, short = short }
end
ns.ClassInfo = ClassInfo

-- "|cffRRGGBBName:|r", the class's name in its color, as the class-quest lines begin.
local function ClassTag()
    return "|c" .. CLASS.hex .. CLASS.name .. ":|r"
end

local function BuildStages()
    local className, classFile, cid = UnitClass("player")
    local raceName, _, rid = UnitRace("player")
    classID, raceID = cid, rid
    local faction = FactionOf(rid)
    side = (faction == "Alliance") and "A" or "H"
    for k, v in pairs(ClassInfo(className, classFile)) do CLASS[k] = v end -- in place: the other files hold this table
    local hex = CLASS.hex
    T.PINK = { tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255, tonumber(hex:sub(7, 8), 16) / 255 }
    ns.AllStages = ns.AllStages or ns.Stages
    ns.Stages = SelectRoute(ns.AllStages, faction, rid)
    ns.Faction = faction
    -- Chain parts that the two sides count differently: keep this side's number.
    for _, list in pairs(ns.ZoneQuests or {}) do
        for _, q in ipairs(list) do
            if type(q.part) == "table" then q.part = q.part[side] end
        end
    end

    local byName = {}
    for _, stage in ipairs(ns.Stages) do
        if stage.dungeon then byName[stage.dungeon] = stage end
    end
    -- A quest that needs things from several dungeons (A Moon-Kissed Blade, The Orb of Soran'ruk) is listed and
    -- counted under one: the first on your side of the map. The others say what to bring back from there.
    local owner = {}
    for pass = 1, 2 do
        for _, d in ipairs(ns.Dungeons or {}) do
            local info = DUNGEON_INFO[d.name]
            local enemy = not byName[d.name] and info and info.land ~= nil and info.land ~= side
            if pass == 2 or not enemy then
                for _, q in ipairs(d.quests) do
                    if Eligible(q) and not owner[q.id] then owner[q.id] = d.name end
                end
            end
        end
    end
    local itemsOf = {}
    for _, list in pairs(ns.ClassQuests or {}) do
        for _, q in ipairs(list) do if q.items then itemsOf[q.id] = q.items end end
    end
    for _, d in ipairs(ns.Dungeons or {}) do
        local quests, real = {}, 0
        for _, q in ipairs(d.quests) do
            if Eligible(q) then
                if owner[q.id] == d.name then
                    quests[#quests + 1] = QuestTask(q)
                    real = real + 1
                else
                    local bring
                    for _, item in ipairs(itemsOf[q.id] or {}) do
                        if item[2]:find(d.name, 1, true) and not item[2]:find("^Reward") then bring = item[1] end
                    end
                    quests[#quests + 1] = { t = string.format("%s: %s here (the quest is listed under %s).", q.name,
                        bring and ("bring back the " .. bring .. " from") or "part of it is", owner[q.id]) }
                end
            end
        end
        local stage = byName[d.name]
        if stage then
            -- The generated quests replace the hand-written quest steps; the tips stay.
            for _, task in ipairs(stage.tasks) do
                if not task.lv then quests[#quests + 1] = task end
            end
            stage.tasks, stage.min, stage.max, stage.route = quests, d.min, d.max, true
        elseif real > 0 then -- only notes: nothing of its own to list
            local info = DUNGEON_INFO[d.name] or { zone = d.name, travel = "Not on this route." }
            local enemy = info.land ~= nil and info.land ~= side
            local route = (info.route == true or info.route == side) and not enemy
            quests[#quests + 1] = { t = "Run it once with all its quests. Repeat runs are slower than questing." }
            ns.Stages[#ns.Stages + 1] = {
                key = "d:" .. d.name, kind = "dungeon", dungeon = d.name, zone = info.zone, hub = d.name,
                x = info.x, y = info.y, min = d.min, max = d.max, src = "data",
                travel = (faction == "Alliance" and info.Alliance) or info.travel,
                tasks = quests, ally = enemy or nil, route = route or nil,
                note = (not route) and (enemy and ((info.land == "A" and "Alliance" or "Horde") .. " territory: no reminders for this one.")
                    or "Not on the main route: worth it when a group is forming or a reward is an upgrade.") or nil,
            }
        end
    end
    -- Zone quests. Stages that share a map split its quests by quest level: a quest goes
    -- to the first stage it is below the top of. Quests more than 5 levels under the first
    -- stage or 3 over the last are left out, as are those you could not take before leaving.
    for _, list in pairs(ns.ZoneQuests or {}) do
        for _, q in ipairs(list) do questNames[q.id] = QuestName(q) end
    end
    for _, d in ipairs(ns.Dungeons or {}) do
        for _, q in ipairs(d.quests) do questNames[q.id] = q.name end
    end
    local classQuests = {}
    for _, q in ipairs(ns.ClassQuests and ns.ClassQuests[cid] or {}) do
        questNames[q.id] = q.name
        if Eligible(q) then classQuests[#classQuests + 1] = q end
    end
    local claims, mapOrder = {}, {}
    for _, stage in ipairs(ns.Stages) do
        if stage.maps then stage.quests = {} end
        for _, map in ipairs(stage.maps or {}) do
            if not claims[map] then claims[map] = {} mapOrder[#mapOrder + 1] = map end
            table.insert(claims[map], stage)
        end
    end
    for _, map in ipairs(mapOrder) do
        local stages = claims[map]
        for _, q in ipairs(ns.ZoneQuests and ns.ZoneQuests[map] or {}) do
            if Eligible(q) and q.lv >= stages[1].min - 5 then
                for i, stage in ipairs(stages) do
                    if (q.lv < stage.max or (i == #stages and q.lv <= stage.max + 3)) and q.req <= stage.max then
                        local task = QuestTask(q)
                        task.lv, task.req, task.zmap = q.lv, q.req, map
                        -- Where its work is when no objective spot is known: the hand-in, else the giver.
                        local turnin = q.turnin
                        if turnin and turnin[1] == map then task.wx, task.wy = turnin[2], turnin[3]
                        else task.wx, task.wy = q.x, q.y end
                        table.insert(stage.quests, task)
                        break
                    end
                end
            end
        end
    end
    for _, stage in ipairs(ns.Stages) do
        if stage.quests and #stage.quests > 0 then
            for _, task in ipairs(WalkOrder(stage, stage.quests)) do stage.tasks[#stage.tasks + 1] = task end
            stage.src = (stage.src == "new") and "newdata" or "data"
        end
        stage.quests = nil
        -- A dungeon's quests are one batch: you collect them all, then run it once.
        if stage.kind == "dungeon" then
            local batch = { tasks = {}, name = "Dungeon run", label = "Dungeon run", n = 1, of = 1, dungeon = true }
            for _, task in ipairs(stage.tasks) do
                if task.id then task.batch = batch batch.tasks[#batch.tasks + 1] = task end
            end
        end
        -- Where each batch's quests sit in the stage's step list.
        stage.batches = {}
        for i, task in ipairs(stage.tasks) do
            local batch = task.batch
            if batch then
                if not batch.idx then
                    batch.idx = {}
                    stage.batches[#stage.batches + 1] = batch
                end
                batch.idx[#batch.idx + 1] = i
            end
        end
    end

    for i, stage in ipairs(ns.Stages) do
        stage.order = i
        if stage.kind == "dungeon" then stage.best = math.min(stage.max, stage.best or (stage.min + 2)) end
    end
    table.sort(ns.Stages, function(a, b)
        if a.min ~= b.min then return a.min < b.min end
        return a.order < b.order
    end)

    -- The class quests this character's class, race and faction can take.
    if #classQuests > 0 then
        local tasks = {}
        for _, q in ipairs(classQuests) do
            tasks[#tasks + 1] = { id = q.id, req = q.req, quest = q, class = true, map = q.map, x = q.x, y = q.y,
                pinTitle = (q.giver or q.name) .. ": " .. q.name }
        end
        classStage = {
            key = (classFile or "class"):lower(), kind = "class", zone = CLASS.name .. " class quests",
            hub = raceName or faction, min = 1, max = 61,
            src = "data", tasks = tasks, batches = {},
            travel = "Your class quests, in order. Each opens at its level and once the one before it is handed in.",
            note = "Rows marked Classic are the old level 60 set turn-ins, listed for completeness.",
        }
        table.insert(ns.Stages, 1, classStage)
    end
end

---------------------------------------------------------------------------
-- Route logic
---------------------------------------------------------------------------

local function TaskKey(stage, i)
    local task = stage.tasks[i]
    return task.id and ("q" .. task.id) or (stage.key .. ":" .. i)
end

-- Whether you have plainly been to a stage already: STARTED of its quests are handed in. Its tips (set your
-- hearthstone, take the flight path) are for arriving, so they count as done from then on.
local STARTED = 2
local function Started(stage)
    local kept = memo and memo.started
    local v = kept and kept[stage]
    if v == nil then
        local n = 0
        v = false
        for _, task in ipairs(stage.tasks) do
            if task.id and QuestDone(task.id) then
                n = n + 1
                if n >= STARTED then v = true break end
            end
        end
        if kept then kept[stage] = v end
    end
    return v
end

-- "done", "inlog", "skipped" (you clicked it away), "closed" (no longer offered), "locked" (a quest before it is not
-- handed in), "later" (too high yet), "low" (6+ levels under you: little XP) or "do".
local function TaskStateNow(stage, i, level)
    local task = stage.tasks[i]
    if task.id then
        if QuestDone(task.id) then return "done" end
        if InLog(task.id) then return "inlog" end
        if db.tasks["q" .. task.id] then return "skipped" end
        if Closed(task.quest) then return "closed" end
        if task.lv and level >= task.lv + 6 then return "low" end
        if not NeedsMet(task.quest) then return "locked" end
        if task.req and task.req > level then return "later" end
        return "do"
    end
    if db.tasks[TaskKey(stage, i)] then return "done" end
    if Started(stage) then return "done" end -- a tip for arriving, and you have been there
    if task.lv and level >= task.lv + 6 then return "low" end
    if task.lv and task.lv > level + 3 then return "later" end
    return "do"
end

-- The same, kept for the length of a refresh (every caller passes the character's level).
local function TaskState(stage, i, level)
    local kept = memo and memo.state
    if not kept then return TaskStateNow(stage, i, level) end
    local task = stage.tasks[i]
    local v = kept[task]
    if not v then
        v = TaskStateNow(stage, i, level)
        kept[task] = v
    end
    return v
end

-- "done", "out" (outleveled), "soon" (not yet in range) or "now".
-- A stage with quests is done when its quests are; else when every step is ticked.
local function Status(stage, level)
    if db.stages[stage.key] then return "done" end
    local quests, all = 0, #stage.tasks > 0
    for _, task in ipairs(stage.tasks) do
        if task.id then quests = quests + 1 end
    end
    for i, task in ipairs(stage.tasks) do
        if quests == 0 or task.id then -- with quests, the tips do not count (and are not worked out here)
            local ts = TaskState(stage, i, level)
            if ts ~= "done" and ts ~= "closed" and ts ~= "skipped" then all = false break end
        end
    end
    if all then return "done" end
    if stage.kind == "class" or stage.kind == "city" then return "now" end
    if stage.kind == "dungeon" then
        if level > stage.max then return "out" end
    elseif level >= stage.max then
        return "out"
    end
    if level < stage.min then return "soon" end
    return "now"
end

-- A detour ("Do it now" on a dungeon): the route leads to that dungeon until its quests are handed in, you
-- outlevel it, or you are back out of it with nothing to hand in. A side branch (/route follow) is one too, and
-- lasts until its quests are done or you outlevel it. Returns the stage while it lasts.
-- Only "done" and "out" end it: a stage that reads "soon" is kept, since the game can give no level for a
-- moment while logging in or out, and the choice must not be lost to that.
local function Detour(level)
    local key = db.detour
    if not key then return end
    local why
    for _, stage in ipairs(ns.Stages) do
        if stage.key == key then
            local st = Status(stage, level)
            if st == "soon" then return end
            local name = (stage.kind == "dungeon") and stage.hub or stage.zone
            if st == "now" then
                if not db.detourRan then return stage end
                for _, task in ipairs(stage.tasks) do
                    if task.id and InLog(task.id) and Complete(task.id) then return stage end -- hand-ins left
                end
                why = name .. ": the run is over"
            else
                why = name .. ((st == "done") and " is done" or " is below your level now")
            end
            break
        end
    end
    db.detour, db.detourIn, db.detourRan = nil, nil, nil
    Print("back on the route" .. (why and (" (" .. why .. ")") or "") .. ".")
end

-- The main-route stage to be in now: a dungeon you are on a detour to, else the one for the zone you are
-- standing in if it is still in range, else the first that is neither done nor outleveled.
local function RecommendNow()
    local level, here = Level(), GetRealZoneText and GetRealZoneText()
    local detour = Detour(level)
    if detour then return detour end
    local first, inZone, last
    for _, stage in ipairs(ns.Stages) do
        if stage.kind == "zone" then
            last = stage
            local st = Status(stage, level)
            if st == "now" or st == "soon" then
                first = first or stage
                if st == "now" and not inZone and stage.zone == here then inZone = stage end
            end
        end
    end
    return inZone or first or last
end

local function Recommend()
    if not memo then return RecommendNow() end
    if not memo.rec then memo.rec = RecommendNow() end
    return memo.rec
end

-- Where to walk for one quest step: its giver ("pickup"), the middle of its objectives ("do")
-- or where it is handed in ("handin"). Returns { key, map, x, y, zone, title } or nil.
local function StepPlaceOf(task, kind)
    local q = task.quest
    if kind == "pickup" then
        if task.x then
            return { key = "p" .. task.id, kind = "pickup", map = task.map, x = task.x, y = task.y, zone = q.zone,
                title = "Pick up: " .. QuestName(q), name = QuestName(q) }
        end
    elseif kind == "handin" then
        if q.turnin then
            return { key = "h" .. task.id, kind = "handin", map = q.turnin[1], x = q.turnin[2], y = q.turnin[3],
                zone = q.turnin[4], title = "Hand in: " .. QuestName(q), name = QuestName(q) }
        end
    elseif q.spot and task.zmap then
        return { key = "o" .. task.id, kind = "work", map = task.zmap, x = q.spot[1], y = q.spot[2], zone = q.zone,
            title = "Do: " .. QuestName(q), name = QuestName(q) }
    end
end

-- The same, with the batch it belongs to.
local function StepPlace(task, kind)
    local place = StepPlaceOf(task, kind)
    if place then place.batch, place.id = task.batch, task.id end
    return place
end

-- Every quest step of the route by quest id, across its stages (built the first time it is asked, after login).
local taskById
local function TaskOf(id)
    if not taskById then
        taskById = {}
        for _, stage in ipairs(ns.Stages or {}) do
            for _, task in ipairs(stage.tasks or {}) do
                if task.id and task.quest and not taskById[task.id] then taskById[task.id] = task end
            end
        end
    end
    return taskById[id]
end

-- Where a map spot (0-100 map units) is in the world, in yards: continent, x, y; nil when the client cannot say.
local function WorldPos(map, x, y)
    if not (map and x and y and C_Map and C_Map.GetWorldPosFromMapPos and CreateVector2D) then return end
    local ok, continent, pos = pcall(C_Map.GetWorldPosFromMapPos, map, CreateVector2D(x / 100, y / 100))
    if not (ok and continent and pos) then return end
    local wx, wy
    if pos.GetXY then wx, wy = pos:GetXY() else wx, wy = pos.x, pos.y end
    wx, wy, continent = Plain(wx), Plain(wy), Plain(continent)
    if type(wx) == "number" and type(wy) == "number" then return continent, wx, wy end
end

-- Where you stand: { map, x, y } in map units, with the world position when known; nil in an instance.
local function Here()
    local map = C_Map and C_Map.GetBestMapForUnit and Plain(C_Map.GetBestMapForUnit("player"))
    if not map then return end
    local here = { map = map }
    local pos = C_Map.GetPlayerMapPosition and C_Map.GetPlayerMapPosition(map, "player")
    if pos and pos.GetXY then
        local x, y = pos:GetXY()
        x, y = Plain(x), Plain(y)
        if type(x) == "number" and type(y) == "number" and (x > 0 or y > 0) then
            here.x, here.y = x * 100, y * 100
            here.continent, here.wx, here.wy = WorldPos(map, here.x, here.y)
        end
    end
    return here
end

-- How far apart two spots are, for ordering only: yards when the world positions are known, else map units
-- scaled to about yards on one map; another map or continent costs far more than any walk on this one.
local YARDS_PER_UNIT = 30
local function Cost(a, b)
    if a.continent and b.continent then
        if a.continent ~= b.continent then return 1e7 end
        return math.sqrt((a.wx - b.wx) ^ 2 + (a.wy - b.wy) ^ 2)
    end
    if a.map == b.map and a.x and b.x then return Dist(a.x, a.y, b.x, b.y) * YARDS_PER_UNIT end
    return 1e6
end

-- The hand-ins put in a walking order: quests handed in at the same spot (one NPC or two side by side) are one
-- stop, and the next stop is always the nearest one left, starting where you stand. Each entry gets `stop`
-- (its stop's number, from 1); the ones the route has no place for come last, without one.
local SAME_STOP = 1.5
local function WalkHandIns(list)
    local stops, unknown = {}, {}
    for _, e in ipairs(list) do
        local p = e.place
        if p and p.map and p.x then
            local stop
            for _, s in ipairs(stops) do
                if s.map == p.map and Dist(s.x, s.y, p.x, p.y) <= SAME_STOP then stop = s break end
            end
            if not stop then
                stop = { map = p.map, x = p.x, y = p.y, zone = p.zone, entries = {} }
                stop.continent, stop.wx, stop.wy = WorldPos(p.map, p.x, p.y)
                stops[#stops + 1] = stop
            end
            table.insert(stop.entries, e)
        else
            unknown[#unknown + 1] = e
        end
    end
    local from = Here()
    if not (from and from.x) then
        -- No spot for you (an instance, or a client that does not say): begin with a stop on your map, if any.
        local map = from and from.map
        for _, s in ipairs(stops) do if s.map == map then from = s break end end
        from = (from and from.x) and from or stops[1]
    end
    local out, left, n = {}, stops, 0
    while #left > 0 do
        local best, bestCost = 1, math.huge
        for i, s in ipairs(left) do
            local c = Cost(from, s)
            if c < bestCost then best, bestCost = i, c end
        end
        local stop = table.remove(left, best)
        n = n + 1
        table.sort(stop.entries, function(a, b) return a.name < b.name end)
        for _, e in ipairs(stop.entries) do e.stop = n out[#out + 1] = e end
        from = stop
    end
    table.sort(unknown, function(a, b) return a.name < b.name end)
    for _, e in ipairs(unknown) do e.stop = nil out[#out + 1] = e end
    return out
end

-- Every quest in your log that is ready to hand in, from any stage or none: { id, name, task, place, stop },
-- where `place` is where it is handed in when the route knows it. In walking order (WalkHandIns).
local function ReadyToHandIn()
    if memo and memo.ready then return memo.ready end
    local out, seen = {}, {}
    local function Add(id, title)
        if type(id) ~= "number" or seen[id] or not Complete(id) then return end
        seen[id] = true
        local task = TaskOf(id)
        out[#out + 1] = { id = id, task = task, place = task and StepPlace(task, "handin") or nil,
            name = task and QuestName(task.quest) or (type(title) == "string" and title ~= "" and title) or ("Quest " .. id) }
    end
    local log = C_QuestLog
    if log and log.GetNumQuestLogEntries and log.GetInfo then
        for i = 1, log.GetNumQuestLogEntries() or 0 do
            local info = log.GetInfo(i)
            if info and not info.isHeader then Add(info.questID, info.title) end
        end
    else -- a client without the log list: the route's own quests that are in the log
        for _, stage in ipairs(ns.Stages or {}) do
            for _, task in ipairs(stage.tasks or {}) do
                if task.id and InLog(task.id) then Add(task.id) end
            end
        end
    end
    local list = WalkHandIns(out)
    if memo then memo.ready = list end
    return list
end
ns.ReadyToHandIn = ReadyToHandIn

-- What a stage's batch asks of you now. Each entry of pickup, work, handin and waiting is
-- { task, i (its place in stage.tasks), state }. done and total count the batch's own quests
-- (skipped, closed and low-XP ones aside); quests in your log from other batches of the stage join
-- work and handin with `other` set, since you carry them anyway.
local function BatchPlan(stage, batch, level)
    local plan = { batch = batch, pickup = {}, work = {}, handin = {}, waiting = {}, done = 0, total = 0 }
    local mine = {}
    for _, i in ipairs(batch.idx) do
        mine[i] = true
        local task = stage.tasks[i]
        local ts = TaskState(stage, i, level)
        local entry = { task = task, i = i, state = ts }
        if ts == "done" then
            plan.done = plan.done + 1
        elseif ts == "do" then
            plan.pickup[#plan.pickup + 1] = entry
        elseif ts == "inlog" then
            local list = Complete(task.id) and plan.handin or plan.work
            list[#list + 1] = entry
        elseif ts == "later" or ts == "locked" then
            plan.waiting[#plan.waiting + 1] = entry
        end
        if ts ~= "skipped" and ts ~= "closed" and ts ~= "low" then plan.total = plan.total + 1 end
    end
    for i, task in ipairs(stage.tasks) do
        if task.id and not mine[i] and TaskState(stage, i, level) == "inlog" then
            local list = Complete(task.id) and plan.handin or plan.work
            list[#list + 1] = { task = task, i = i, state = "inlog", other = true }
        end
    end
    return plan
end

-- The batch to work on now: the first with a quest to pick up or in your log. Returns its plan or nil.
local function CurrentBatch(stage, level)
    level = level or Level()
    for _, batch in ipairs(stage.batches or {}) do
        for _, i in ipairs(batch.idx) do
            local ts = TaskState(stage, i, level)
            if ts == "do" or ts == "inlog" then return BatchPlan(stage, batch, level) end
        end
    end
end

-- The objectives of a quest in your log: { { text, done }, ... }, or nil when the game gives none.
local function Objectives(id)
    if not (C_QuestLog and C_QuestLog.GetQuestObjectives) then return end
    local list = C_QuestLog.GetQuestObjectives(id)
    if (issecretvalue and issecretvalue(list)) or type(list) ~= "table" then return end
    local out = {}
    for _, o in ipairs(list) do
        if type(o) == "table" and type(o.text) == "string" and o.text ~= "" then
            out[#out + 1] = { text = o.text, done = o.finished and true or false }
        end
    end
    return #out > 0 and out or nil
end

-- A quest's objectives as lines to show, count first so it reads at a glance: "3/10  Hillsbrad Farmer slain".
-- Finished ones are muted and say so. Without a quest log entry, the data's own objective text, if any.
local function ObjectiveLines(task, indent)
    local out = {}
    indent = indent or ""
    local list = task.id and Objectives(task.id)
    if list then
        for _, o in ipairs(list) do
            -- The game writes "Worg slain: 3/8" or "3/8 Worg slain".
            local label, have, need = o.text:match("^(.-):%s*(%d+)%s*/%s*(%d+)$")
            if not label then have, need, label = o.text:match("^(%d+)%s*/%s*(%d+)%s+(.+)$") end
            if o.done then
                out[#out + 1] = indent .. "|cff8c8c8c" .. (label and (have .. "/" .. need .. "  " .. label) or o.text)
                    .. "  - done|r"
            elseif label then
                out[#out + 1] = string.format("%s|cffffffff%s/%s|r  |cffbfbfbf%s|r", indent, have, need, label)
            else
                out[#out + 1] = indent .. "|cffbfbfbf" .. o.text .. "|r"
            end
        end
    elseif task.quest and task.quest.objective then
        out[1] = indent .. "|cffbfbfbf" .. task.quest.objective .. "|r"
    end
    return out
end

-- Levels over a quest at which it is still worth it but should be done soon: at 6 over it turns "low".
local LOW_SOON = 4

-- Short labels on a quest line: a blue reward, and a quest about to give little XP.
local function Badges(task, level)
    local parts = {}
    if task.quest and HasBlue(task.quest) then parts[#parts + 1] = "|cff66b3ffblue reward|r" end
    if task.lv and level >= task.lv + LOW_SOON and level < task.lv + 6 then
        parts[#parts + 1] = "|cffe6cc8clow XP soon|r"
    end
    return #parts > 0 and ("  " .. table.concat(parts, "  ")) or ""
end

-- The first unfinished prerequisite of `q` that this addon knows: its name and the stage it is in.
local function Blocker(q)
    for _, need in ipairs(q.needs or {}) do
        for _, id in ipairs(type(need) == "table" and need or { need }) do
            if not NeedMet(id) and questNames[id] then
                for _, stage in ipairs(ns.Stages) do
                    for _, task in ipairs(stage.tasks) do
                        if task.id == id then return questNames[id], stage end
                    end
                end
                return questNames[id]
            end
        end
    end
end

-- The first blocker among a batch plan's waiting entries.
local function WaitingBlocker(waiting)
    for _, entry in ipairs(waiting) do
        if entry.task.quest then
            local name, stage = Blocker(entry.task.quest)
            if name then return name, stage end
        end
    end
end

-- Quests in your log whose objectives lie in the same place are one step: "Do: A + B".
local TOGETHER = 8
local function Together(stage, place, level)
    if not (place and place.kind == "work") then return place end
    local names, ids = { place.name }, { [place.id] = true }
    for i, task in ipairs(stage.tasks) do
        local spot = task.quest and task.quest.spot
        if task.id and not ids[task.id] and spot and task.zmap == place.map and TaskState(stage, i, level) == "inlog"
            and not Complete(task.id) and Dist(spot[1], spot[2], place.x, place.y) <= TOGETHER then
            ids[task.id] = true
            names[#names + 1] = QuestName(task.quest)
        end
    end
    if #names > 1 then
        place.name = table.concat(names, " + ")
        place.title = "Do: " .. place.name
    end
    return place
end

-- The quest you clicked in the NOW box: the arrow goes for it first while it is open.
local function Focused(stage, level)
    local id = db.focus
    if not id then return end
    for i, task in ipairs(stage.tasks) do
        if task.id == id then
            local ts = TaskState(stage, i, level)
            if ts == "do" then return StepPlace(task, "pickup") end
            if ts == "inlog" then return StepPlace(task, Complete(id) and "handin" or "do") end
            db.focus = nil -- handed in, skipped or no longer offered: the route leads again
            return
        end
    end
end

-- The next thing to walk to on a stage (the recommended one if none is given), batch by
-- batch: pick up the batch's quests, then go to their objectives, then hand them in together.
-- Returns { key, map, x, y, zone, title } or nil.
local function NextStep(stage)
    local rec, level = stage or Recommend(), Level()
    local focus = Focused(rec, level)
    if focus then
        focus.focused = true
        return Together(rec, focus, level)
    end
    for _, batch in ipairs(rec.batches or {}) do
        local pickup, objective, handin, open
        for _, j in ipairs(batch.idx) do
            local task = rec.tasks[j]
            local ts = TaskState(rec, j, level)
            if ts == "do" then
                open = true
                pickup = pickup or StepPlace(task, "pickup")
            elseif ts == "inlog" then
                open = true
                if Complete(task.id) then
                    handin = handin or StepPlace(task, "handin")
                else
                    objective = objective or StepPlace(task, "do")
                end
            end
        end
        if handin and not (pickup or objective) then
            -- The batch is all handing in now: go to the first stop of the walking order that is one of its own.
            local own = {}
            for _, j in ipairs(batch.idx) do own[rec.tasks[j].id or 0] = true end
            for _, e in ipairs(ReadyToHandIn()) do
                if own[e.id] and e.place then handin = StepPlace(e.task, "handin") break end
            end
        end
        if open and (pickup or objective or handin) then return pickup or Together(rec, objective, level) or handin end
    end
end

-- The quests of a dungeon stage still to do: all of them, and those with a blue reward.
local function QuestsLeft(stage)
    local level, left, blues = Level(), {}, {}
    for i, task in ipairs(stage.tasks) do
        if task.id then
            local ts = TaskState(stage, i, level)
            if ts ~= "done" and ts ~= "skipped" then
                left[#left + 1] = task
                if HasBlue(task.quest) then blues[#blues + 1] = task end
            end
        end
    end
    return left, blues
end

-- Dungeons whose level range you are inside, with quests left, Alliance ones aside.
local function DungeonsInRange()
    local level, list = Level(), {}
    for _, stage in ipairs(ns.Stages) do
        if stage.kind == "dungeon" and not stage.ally and Status(stage, level) == "now" then list[#list + 1] = stage end
    end
    return list
end

-- The XP a quest gives you now, from the game. A quest not in your log is asked for once; the answer comes
-- with QUEST_DATA_LOAD_RESULT, which refreshes the window. nil until it is known.
local xpAsked, xpSeen = {}, { sum = 0, n = 0 }
local function QuestXP(id)
    if type(GetQuestLogRewardXP) ~= "function" then return end
    local ok, xp = pcall(GetQuestLogRewardXP, id)
    xp = ok and Plain(xp) or nil
    if type(xp) == "number" and xp > 0 then return xp end
    if not xpAsked[id] and C_QuestLog and type(C_QuestLog.RequestLoadQuestByID) == "function" then
        xpAsked[id] = true -- before the call: cached data can answer at once
        pcall(C_QuestLog.RequestLoadQuestByID, id)
    end
end

-- Where a dungeon quest is picked up: the zone its line starts with, or "inside" for a drop.
local function PickupZone(q)
    if q.inside then return "inside" end
    local w = (q.where or ""):gsub("^%a+ only %- ", "")
    return w:match("^([^,%-%(]-)%s*[,%-%(]") or (w ~= "" and w) or "?"
end

-- What a dungeon is worth now: its quests left, their XP (known, and an estimate for the ones not answered
-- yet), the blue rewards, and a score to rank it by. The value is in the quests and the gear, not the kills.
local function DungeonValue(stage, level)
    local left, blues = QuestsLeft(stage)
    local xp, unknown, zones, order = 0, 0, {}, {}
    for _, task in ipairs(left) do
        local q = QuestXP(task.id)
        if q then xp = xp + q else unknown = unknown + 1 end
        local z = PickupZone(task.quest)
        if not zones[z] then zones[z] = 0 order[#order + 1] = z end
        zones[z] = zones[z] + 1
    end
    local estimate = xp + ((xpSeen.n > 0) and unknown * xpSeen.sum / xpSeen.n or 0)
    local max = Plain(UnitXPMax and UnitXPMax("player"))
    local share = (type(max) == "number" and max > 0) and estimate / max or nil
    local where = {}
    for _, z in ipairs(order) do where[#where + 1] = zones[z] .. " " .. (z == "inside" and "inside" or ("in " .. z)) end
    local score = (share or #left * 0.05) + 0.12 * #blues
    if level < stage.best then score = score * 0.85 end -- early: some quests are not open yet, the run is harder
    if level >= stage.max - 1 then score = score * 1.25 end -- last levels: now or never
    if stage.route then score = score + 0.01 end
    return { stage = stage, left = left, blues = blues, xp = xp, unknown = unknown, share = share, score = score,
        where = table.concat(where, ", ") }
end

-- The dungeons in range with quests left, the best first.
local function RankedDungeons()
    local level, list = Level(), {}
    -- The average XP of the dungeon quests known so far stands in for the ones still loading.
    xpSeen.sum, xpSeen.n = 0, 0
    for _, stage in ipairs(DungeonsInRange()) do
        for _, task in ipairs(QuestsLeft(stage)) do
            local q = QuestXP(task.id)
            if q then xpSeen.sum, xpSeen.n = xpSeen.sum + q, xpSeen.n + 1 end
        end
    end
    for _, stage in ipairs(DungeonsInRange()) do
        local v = DungeonValue(stage, level)
        if #v.left > 0 then list[#list + 1] = v end
    end
    table.sort(list, function(a, b)
        if a.score ~= b.score then return a.score > b.score end
        return a.stage.min < b.stage.min
    end)
    return list
end

-- "~38% of a level" (or the XP itself when the level's size is not known), "XP loading" before any is known.
local function XPText(v)
    if v.xp == 0 and v.unknown > 0 and xpSeen.n == 0 then return "XP loading" end
    local approx = v.unknown > 0 and "~" or ""
    if v.share then return string.format("%s%d%% of a level", approx, math.floor(v.share * 100 + 0.5)) end
    if v.xp > 0 then return string.format("%s%d XP", approx, v.xp) end
    return ""
end

-- Stages you have just outleveled that still hold quests worth full XP
-- (someone who joins the route mid-way has not done them): { stage, count }.
local function Leftovers()
    local level, list = Level(), {}
    for _, stage in ipairs(ns.Stages) do
        if stage.kind == "zone" and Status(stage, level) == "out" and stage.max >= level - 4 then
            local count = 0
            for i, task in ipairs(stage.tasks) do
                if task.lv and TaskState(stage, i, level) == "do" then count = count + 1 end
            end
            if count > 0 then list[#list + 1] = { stage = stage, count = count } end
        end
    end
    return list
end

-- The class quests you can pick up now, and the next one that will open.
local function ClassQuests()
    local open, nextUp = {}, nil
    if not classStage then return open end
    local level = Level()
    for i, task in ipairs(classStage.tasks) do
        if not task.quest.classic then
            local ts = TaskState(classStage, i, level)
            if ts == "do" or ts == "inlog" then
                open[#open + 1] = task
            elseif ts == "later" and not nextUp then
                nextUp = task
            end
        end
    end
    return open, nextUp
end

local function TaskTitle(task)
    return task.quest and QuestName(task.quest) or task.t
end

local function OpenTasks(stage)
    local level, list = Level(), {}
    for i, task in ipairs(stage.tasks) do
        local ts = TaskState(stage, i, level)
        if ts == "do" or ts == "inlog" then list[#list + 1] = TaskTitle(task) end
    end
    return list
end

local function RangeText(stage)
    if stage.kind == "class" then return CLASS.short end
    if stage.kind == "city" then return "City" end
    if stage.min >= 60 then return "60" end
    return stage.min .. "-" .. stage.max
end

local function StageName(stage)
    if stage.kind == "dungeon" then return stage.hub end
    return stage.zone
end

local function Where(q)
    if q.where then return q.where end
    local s = q.giver and (q.giver .. (q.zone and (", " .. q.zone) or "")) or (q.zone or "Start not known yet")
    if q.x then s = s .. string.format(" (%.1f, %.1f)", q.x, q.y) end
    return s
end

---------------------------------------------------------------------------
-- For Window.lua and Core.lua
---------------------------------------------------------------------------

ns.T = T
ns.I = {
    Print = Print, Plain = Plain, Level = Level, QuestDone = QuestDone, TakeZodUIQuests = TakeZodUIQuests,
    InLog = InLog, Complete = Complete, NeedsMet = NeedsMet, QuestName = QuestName, WaitsFor = WaitsFor,
    RewardText = RewardText, Dist = Dist, ClassTag = ClassTag, BuildStages = BuildStages, TaskKey = TaskKey,
    TaskState = TaskState, Status = Status, Recommend = Recommend, StepPlace = StepPlace, WorldPos = WorldPos,
    Here = Here, ReadyToHandIn = ReadyToHandIn, CurrentBatch = CurrentBatch, ObjectiveLines = ObjectiveLines, LOW_SOON = LOW_SOON,
    Badges = Badges, WaitingBlocker = WaitingBlocker, NextStep = NextStep, QuestsLeft = QuestsLeft, DungeonsInRange = DungeonsInRange,
    xpAsked = xpAsked, DungeonValue = DungeonValue, RankedDungeons = RankedDungeons, XPText = XPText, Leftovers = Leftovers,
    ClassQuests = ClassQuests, OpenTasks = OpenTasks, RangeText = RangeText, StageName = StageName, Where = Where,
    CLASS = CLASS,
    Remember = Remember,
    -- State kept here that the other files read or set.
    ClassStage = function() return classStage end,
    SetLevel = function(level) levelNow = level end,
}
