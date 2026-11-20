local ADDON, ns = ...

-- Alerts: says so once when your bags are nearly full or your ammunition runs
-- low, and reminds you of the trainer and talents when you level. Gear about to
-- break is left to NaowhForever_QoL's durability warning; Home still hints at it.
-- Each warning waits until the problem is fixed before it can fire again.

local M = ns:NewModule("alerts", {
    title = "Alerts",
    desc = "Warns once when your bags are nearly full or your arrows or bullets run low, says when your rested XP runs out, and reminds you of your class trainer and talent points when you level up.",
    defaults = { enabled = true, durabilityAt = 25, bags = true, bagsAt = 2, ammo = true, ammoAt = 200, rested = true,
        levelUp = true, questDone = true, skillCap = true, hearth = true, mail = true },
    options = {
        { type = "step", key = "durabilityAt", label = "Home hints at a repair below", min = 10, max = 50, step = 5, format = function(v) return v .. "%" end },
        { type = "check", key = "bags", label = "Warn when the bags are nearly full" },
        { type = "step", key = "bagsAt", label = "Warn at", min = 0, max = 10, step = 1,
            format = function(v) return v == 1 and "1 free slot" or (v .. " free slots") end },
        { type = "check", key = "ammo", label = "Warn when arrows or bullets run low" },
        { type = "step", key = "ammoAt", label = "Warn below", min = 50, max = 1000, step = 50, format = function(v) return v .. " left" end },
        { type = "check", key = "rested", label = "Say when your rested XP runs out" },
        { type = "check", key = "levelUp", label = "Trainer and talent reminders when you level up" },
        { type = "check", key = "questDone", label = "Say when every objective of a quest is done" },
        { type = "check", key = "skillCap", label = "Say when a profession reaches the most your trainer level allows" },
        { type = "check", key = "hearth", label = "Say when the hearthstone is ready again" },
        { type = "check", key = "mail", label = "Say at login when you have mail" },
    },
})

local warned = {}

local function CheckBags()
    if not M.db.bags then return end
    local free, total = ns.BagSlots()
    if total == 0 then return end
    local low = free <= M.db.bagsAt
    if low and not warned.bags then
        ns.Alert(free == 0 and "Your bags are full." or ("Only " .. free .. " free bag slot" .. (free == 1 and "" or "s") .. " left."))
    end
    -- Warned once; again only after the bags had clearly more room (two slots over the line), so selling
    -- one thing and looting the next does not say it every time.
    if low then
        warned.bags = true
    elseif free >= M.db.bagsAt + 2 then
        warned.bags = false
    end
end

-- How many arrows or bullets sit in the ammo slot, or nil without one (or on a client without the slot).
local function Ammo()
    if not (GetInventoryItemID and GetInventoryItemCount) then return nil end
    local slot = INVSLOT_AMMO or 0
    if not GetInventoryItemID("player", slot) then return nil end
    return GetInventoryItemCount("player", slot) or 0
end

local function CheckAmmo()
    if not M.db.ammo then return end
    local n = Ammo()
    if not n then
        warned.ammo = false
        return
    end
    local low = n < M.db.ammoAt
    if low and not warned.ammo then
        ns.Alert(n == 0 and "You are out of arrows or bullets." or ("Only " .. n .. " arrows or bullets left."))
    end
    warned.ammo = low
end

local function Rested()
    return GetXPExhaustion and GetXPExhaustion() or 0
end

local hadRested

local function CheckRested()
    local now = Rested()
    if M.db.rested and hadRested and hadRested > 0 and now <= 0 then
        ns.Alert("Your rested XP has run out.")
    end
    hadRested = now
end

function M:OnEnable()
    -- What is already wrong at login is not news: only a change for the worse is said.
    local free, total = ns.BagSlots()
    warned.bags = total > 0 and free <= self.db.bagsAt or false
    local ammo = Ammo()
    warned.ammo = ammo ~= nil and ammo < self.db.ammoAt
    hadRested = Rested()
end

M:On("BAG_UPDATE_DELAYED", CheckBags)
M:On("BAG_UPDATE_DELAYED", CheckAmmo)
M:On("PLAYER_REGEN_ENABLED", CheckAmmo) -- shots are spent in fights
M:On("PLAYER_XP_UPDATE", CheckRested)

M:On("PLAYER_LEVEL_UP", function(self, _, level)
    if not self.db.levelUp or type(level) ~= "number" then return end
    local parts = {}
    if level % 2 == 0 then parts[#parts + 1] = "your class trainer may have new spells" end
    if level >= 10 then parts[#parts + 1] = "you have a talent point to spend" end
    if #parts == 0 then return end
    local text = table.concat(parts, " and ")
    ns.After(3, function()
        ns.Alert("Level " .. level .. ": " .. text .. ".") -- a notice, not a chat line lost among the others
    end)
end)

function M:Card()
    local d = ns.Durability()
    local free, total = ns.BagSlots()
    return {
        title = "Gear and bags",
        lines = {
            { "Durability (most worn piece)", d and (math.floor(d * 100) .. "%") or "-" },
            { "Free bag slots", total > 0 and (free .. " of " .. total) or "-" },
            Ammo() and { "Arrows or bullets", tostring(Ammo()) } or nil,
        },
    }
end

-- Quests whose objectives are all done. The first look after login only learns
-- what is already done; after that a quest that becomes done is said once.
local doneQuests

-- Where to hand a quest in, from Undead Route's quest data when it is installed: "to Gar'Thok at Razor Hill,
-- Durotar (51.9, 43.5)", or ": Durotar (60.0, 20.3)" with only the zone. nil when the route has no hand-in for the quest (or is not there).
local function HandIn(id)
    local route = UndeadRoute
    if type(route) ~= "table" or type(route.TurnIn) ~= "function" then return nil end
    local ok, t = pcall(route.TurnIn, id)
    if not ok or type(t) ~= "table" or type(t.zone) ~= "string" then return nil end
    local place = t.hub and (t.hub .. ", " .. t.zone) or t.zone
    local spot = (t.x and t.y) and string.format(" (%.1f, %.1f)", t.x, t.y) or ""
    if not (t.npc or t.hub) then return ": " .. place .. spot end
    return " " .. (t.npc and ("to " .. t.npc .. " ") or "") .. (t.hub and "at " or "in ") .. place .. spot
end
M.HandIn = HandIn

local function ScanQuests()
    if not (C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetInfo and C_QuestLog.IsComplete) then return end
    local first = doneQuests == nil
    doneQuests = doneQuests or {}
    local seen = {}
    for i = 1, C_QuestLog.GetNumQuestLogEntries() or 0 do
        local info = C_QuestLog.GetInfo(i)
        local id = info and not info.isHeader and info.questID
        if id and C_QuestLog.IsComplete(id) then
            seen[id] = true
            if not doneQuests[id] and not first and M.db.questDone then
                local where, title = HandIn(id), info.title
                local route = UndeadRoute
                local pin = where and type(route) == "table" and type(route.PinTurnIn) == "function"
                    and { hint = "Click: pin the hand-in on the map.", click = function() route.PinTurnIn(id, title) end } or nil
                ns.Alert("Quest done: " .. (title or "a quest") .. ". Hand it in" .. (where or "") .. ".", pin)
            end
        end
    end
    doneQuests = seen
end

M:On("QUEST_LOG_UPDATE", ScanQuests)

-- A profession at the most its current trainer level allows: say it once per cap.
local function CheckSkills()
    if not (M.db.skillCap and GetProfessions and GetProfessionInfo) then return end
    ns.chardb.capSaid = ns.chardb.capSaid or {}
    for _, index in ipairs({ GetProfessions() }) do
        local name, _, rank, max = GetProfessionInfo(index)
        if name and max and max > 0 and rank == max and max < 300 then
            local key = name .. " " .. max
            if not ns.chardb.capSaid[key] then
                ns.chardb.capSaid[key] = true
                ns.Alert(name .. " is at " .. rank .. " of " .. max .. ": your trainer can teach the next level.")
            end
        end
    end
end
M:On("SKILL_LINES_CHANGED", CheckSkills)

-- The hearthstone: said when its cooldown runs out (not at login).
-- Every cast puts the hearthstone on the global cooldown (1.5 s or less), so a
-- cooldown only counts as a use when it is longer than that. In combat the
-- numbers can be secret; then nothing changes until they can be read again.
local HEARTH = 6948
local GCD = 2
local cooling

ns.Every(5, function()
    local get = C_Container and C_Container.GetItemCooldown
    local count = C_Item and C_Item.GetItemCount or GetItemCount
    if not (get and count) or (count(HEARTH) or 0) == 0 then return end
    local start, duration = get(HEARTH)
    if issecretvalue and (issecretvalue(start) or issecretvalue(duration)) then return end
    start, duration = start or 0, duration or 0
    local now = start > 0 and duration > GCD and (start + duration - GetTime()) > 1
    if cooling and not now and M.db.hearth then ns.Alert("Your hearthstone is ready.") end
    cooling = now
end, M)

local enable = M.OnEnable
function M:OnEnable()
    enable(self)
    cooling = nil
    CheckSkills()
    ns.After(8, function()
        if self.db.mail and HasNewMail and HasNewMail() then ns.Alert("You have mail.") end
    end)
end

function M:Hints(add)
    local d = ns.Durability()
    if d and d * 100 < self.db.durabilityAt then add("Repair: your gear is at " .. math.floor(d * 100) .. "%", 85) end
    local free, total = ns.BagSlots()
    if total > 0 and free <= math.max(self.db.bagsAt, 2) then
        add(free == 0 and "Bags full: sell or bank something" or ("Bags nearly full: " .. free .. " free"), 80)
    end
    local done = 0
    for _ in pairs(doneQuests or {}) do done = done + 1 end
    if done > 0 then add(done .. (done == 1 and " quest is" or " quests are") .. " ready to hand in", 70) end
    if HasNewMail and HasNewMail() then add("Mail is waiting", 45) end
end
