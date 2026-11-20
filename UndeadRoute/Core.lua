local ADDON, ns = ...

-- Undead Route: a level-aware walk through a 1-60 leveling route, for every race and class of both
-- factions (it began as the Horde Undead route, hence the name). The route is picked at login.
-- The window lists every stage on the left and the selected stage's steps on
-- the right. The stage it recommends follows the character's level, the zone
-- they are standing in, and what they have done.
--   Data.lua       the hand-written routes: stages per faction and race, travel and tips
--   Generated.lua  the quests of every zone and dungeon on them with their rewards, and every class's quests
-- Steps that are quests (they carry a quest id) tick themselves off from the
-- game's own quest log, and drive the dungeon and class-quest reminders.

-- The look: one table holds the palette and the widget builders, so the whole window can
-- take ZodUI's look when ZodUI is installed (T.Adopt at login) and keep this copy of it otherwise.
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

local WIDTH, HEIGHT = 820, 520
local TITLE_H, BANNER_H, BAR_H = 28, 72, 40
local LEFT_W, ROW_H, PAD = 270, 24, 8
local LIST_H = HEIGHT - TITLE_H - BANNER_H - PAD - BAR_H - PAD -- the visible height of the stage list

local db
local levelNow -- set on PLAYER_LEVEL_UP, where UnitLevel still returns the old level
local selected -- the stage shown on the right
local nowOpen = false -- the step list shows the NOW batch's quests too (they are folded, being in the box above)
local main, tracker
local classStage -- the character's class quests, as a stage
local classID, raceID
local side -- "A" (Alliance) or "H" (Horde): the generated data's side codes
-- The character's class, for the class-quest lines: set at login (ClassInfo).
local CLASS = { file = "PALADIN", name = "Paladin", hex = "fff58cba", short = "Pal" }
local Refresh

local function Print(msg)
    print(T.Accent() .. "Undead Route:|r " .. msg)
end

local function Plain(v) -- nil for a value the client hands back as secret
    if issecretvalue and issecretvalue(v) then return nil end
    return v
end

local function Level()
    return levelNow or Plain(UnitLevel("player")) or 1
end

local function HasBit(mask, n) -- is bit n (1 = lowest) set? Race masks pass 32 bits, so no bit library.
    return math.floor(mask / 2 ^ (n - 1)) % 2 == 1
end

---------------------------------------------------------------------------
-- Quests
---------------------------------------------------------------------------

-- Done when the game says so, or when this character was seen handing it in. The game never flags a
-- repeatable quest as done (such as Forever's Seeking the Kor Gem), so the route keeps its own list.
local function QuestDone(id)
    if db and db.turnedIn and db.turnedIn[id] then return true end
    return C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted and C_QuestLog.IsQuestFlaggedCompleted(id) or false
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
    return C_QuestLog and C_QuestLog.IsOnQuest and C_QuestLog.IsOnQuest(id) or false
end

-- In the log with every objective met: ready to hand in.
local function Complete(id)
    if C_QuestLog and C_QuestLog.IsComplete then return C_QuestLog.IsComplete(id) or false end
    if IsQuestComplete then return IsQuestComplete(id) or false end
    return false
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
    local function Ready(task)
        for _, need in ipairs(task.quest.needs or {}) do
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
        return true
    end
    local zmap, px, py, wx, wy
    while #left > 0 do
        local band
        for _, task in ipairs(left) do
            if (not band or task.band < band) and Ready(task) then band = task.band end
        end
        local pick, pickScore
        for i, task in ipairs(left) do
            if not band or (task.band == band and Ready(task)) then
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
        for _, need in ipairs(task.quest.needs or {}) do
            local ids = type(need) == "table" and need or { need }
            local here, ok = false, false
            for _, id in ipairs(ids) do
                if inStage[id] then here = true end
                if done[id] then ok = true end
            end
            if here and not ok then return false end
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
    CLASS = ClassInfo(className, classFile)
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

-- "done", "inlog", "skipped" (you clicked it away), "closed" (no longer offered), "locked" (a quest before it is not
-- handed in), "later" (too high yet), "low" (6+ levels under you: little XP) or "do".
local function TaskState(stage, i, level)
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
    if task.lv and level >= task.lv + 6 then return "low" end
    if task.lv and task.lv > level + 3 then return "later" end
    return "do"
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
        local ts = TaskState(stage, i, level)
        if (quests == 0 or task.id) and ts ~= "done" and ts ~= "closed" and ts ~= "skipped" then all = false break end
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
-- outlevel it, or you are back out of it with nothing to hand in. Returns the stage while it lasts.
local function Detour(level)
    local key = db.detour
    if not key then return end
    for _, stage in ipairs(ns.Stages) do
        if stage.key == key then
            if Status(stage, level) ~= "now" then break end
            if not db.detourRan then return stage end
            for _, task in ipairs(stage.tasks) do
                if task.id and InLog(task.id) and Complete(task.id) then return stage end -- hand-ins left
            end
            break
        end
    end
    db.detour, db.detourIn, db.detourRan = nil, nil, nil
    Print("back on the route.")
end

-- The main-route stage to be in now: a dungeon you are on a detour to, else the one for the zone you are
-- standing in if it is still in range, else the first that is neither done nor outleveled.
local function Recommend()
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
    return WalkHandIns(out)
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
        SlashCmdList.UNDEADROUTE(db.detour == selected.key and "back" or ("do " .. selected.hub))
    end)
    f.detourButton:SetPoint("LEFT", f.doneButton, "RIGHT", 6, 0)
    f.detourButton.tip = "Pauses the route for this dungeon: the tracker and arrow lead to its quests, then the run. "
        .. "The route takes over again once they are handed in, or when you come out with nothing to hand in."
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
    local detour = db.detour and rec.kind == "dungeon"
    f.bannerSub:SetText(detour and ("Detour: " .. rec.hub .. ". The route waits; Back to route ends it.")
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
        and #QuestsLeft(stage) > 0))
    f.detourButton.label:SetText(onDetour and "Back to route" or "Do it now")
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
    t:SetShown(not db.tracker.hidden and not (main and main:IsShown()))
    if db.tracker.hidden then return end
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
-- Wiring
---------------------------------------------------------------------------

-- The arrow: our own, on screen, pointing at the next step (or at a place you pinned, until you get there),
-- with how far it is. It turns with where you face (GetPlayerFacing) and measures in yards from the world
-- positions of you and the place, so it needs no other addon. On another continent, or where the game gives
-- no position (an instance), it names the zone instead. Drag it to move it; /route arrow hides it.
local ready = false
local ARROW_ART = "Interface\\AddOns\\UndeadRoute\\Media\\Arrow" -- tools/icon.js draws it
local ARRIVED = 10 -- yards
local arrowFrame, arrowTarget, arrowPin, arrowKey

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
    local wait = 0
    f:SetScript("OnUpdate", function(self, elapsed)
        wait = wait - elapsed
        if wait > 0 then return end
        wait = 0.05
        ns.ArrowTick(self)
    end)
    f:Hide()
end

-- Where the arrow points and what it says, now. Returns the yards to go, or nil when they are not known.
function ns.ArrowTick(f)
    local t = arrowTarget
    if not t then return end
    f.title:SetText(t.title or "")
    local here = Here()
    local continent, tx, ty = WorldPos(t.map, t.x, t.y)
    if not (here and here.continent and continent and here.continent == continent) then
        f.art:Hide()
        f.dist:SetText(t.zone and ("in " .. t.zone) or "on another map")
        return nil
    end
    -- World x runs north, y west; facing is turned from north towards west.
    local north, west = tx - here.wx, ty - here.wy
    local yards = math.sqrt(north * north + west * west)
    if yards <= ARRIVED then
        f.art:Hide()
        f.dist:SetText("you are there")
        if arrowPin and t == arrowPin then -- a pin is done with once reached: back to the route
            arrowPin = nil
            ns.UpdateArrow()
        end
        return yards
    end
    f.dist:SetText(string.format("%d yds", math.floor(yards + 0.5)))
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
    if ready then UpdateArrow() end
end

Refresh = function()
    if not db then return end
    if ready then UpdateArrow() end
    if main and main:IsShown() then RefreshMain() end
    if tracker then RefreshTracker() end
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
-- The minimap button and the game's addon menu (the button by the minimap)
---------------------------------------------------------------------------

local ICON = "Interface\\AddOns\\UndeadRoute\\Media\\Icon" -- tools/icon.js draws it
local mini

-- What a click does, from the minimap button or the addon menu: left opens the route, right the tracker.
local function IconClick(mouse)
    if not ready then return end
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
    if ready then
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
    if lastRec and lastRec ~= rec then
        Print(string.format("Time to move on: %s, %s (%s). Type /route for the steps.", rec.zone, rec.hub,
            RangeText(rec)))
    end
    lastRec = rec
end

local questTimer = false

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

local xpTimer = false
events:SetScript("OnEvent", function(_, event, arg1)
    if event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" then
        -- In a fight the tracker steps back: faint, and the clicks go through it to the world, so it is
        -- not dragged away by accident.
        local fight = event == "PLAYER_REGEN_DISABLED"
        if tracker then
            tracker:SetAlpha(fight and 0.4 or 1)
            tracker:EnableMouse(not fight)
            tracker.fold:EnableMouse(not fight)
            if tracker.grip then tracker.grip:EnableMouse(not fight) end
        end
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
    elseif event == "PLAYER_LOGIN" then
        T.Adopt() -- ZodUI's look, when it is installed
        TakeZodUIQuests()
        BuildStages()
        BuildTracker()
        BuildMini()
        ready = true
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
    elseif not ready then
        return
    elseif event == "PLAYER_LEVEL_UP" then
        levelNow = arg1
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
        Refresh()
    elseif event == "QUEST_DATA_LOAD_RESULT" then
        -- The XP of a dungeon quest has come: show it, once for a burst of answers.
        if xpAsked[tonumber(arg1) or 0] and not xpTimer and C_Timer and C_Timer.After then
            xpTimer = true
            C_Timer.After(0.5, function() xpTimer = false Refresh() end)
        end
    elseif event == "QUEST_TURNED_IN" then
        local id = tonumber(arg1)
        if id then db.turnedIn[id] = true end
        -- The quest after it may have just opened.
        if C_Timer and C_Timer.After then
            C_Timer.After(1, function() RemindClass() RemindHere() Refresh() end)
        else
            RemindClass() Refresh()
        end
    elseif not questTimer and C_Timer and C_Timer.After then
        -- QUEST_LOG_UPDATE fires in bursts: refresh once, a moment later.
        questTimer = true
        C_Timer.After(0.5, function() questTimer = false Refresh() end)
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
    if not ready then return end
    if what == "toggle" then
        ns.Toggle()
    elseif what == "tracker" then
        SlashCmdList.UNDEADROUTE("tracker")
        if main and main:IsShown() then -- nothing to see change while the window is open: say what happened
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
        selected, db.window.stage = nil, nil
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
            selected, db.window.stage = stage, nil
            Refresh()
            Print(string.format("detour: %s. %d quest%s to pick up or do first (%s); the tracker and arrow lead there. "
                .. "/route back ends it.", stage.hub, #pick.left, #pick.left == 1 and "" or "s", pick.where))
        end
    elseif msg == "back" then
        if not db.detour then
            Print("no detour on: the route leads already.")
        else
            db.detour, db.detourIn, db.detourRan = nil, nil, nil
            lastRec = Recommend()
            selected, db.window.stage = lastRec, nil
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
        Print("/route opens the window. /route dungeons ranks the dungeons worth doing now. /route do <name> pauses the route for one, /route back ends it. "
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
