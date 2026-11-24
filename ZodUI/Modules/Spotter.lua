local ADDON, ns = ...

-- Object glow: quest objects and chests you would walk past light up.
-- The game lets an addon see only one object at a time: the "interact target" it picks
-- near you (the gamepad's soft target, turned on here for the mouse too). That object
-- gets a nameplate of its own, and the game's small icon over it. When it is a quest
-- object or a chest, this raises a pillar of light from it, with sparkles drifting up,
-- and plays a sound the first time (gold for quests, blue for chests).
-- A quest object is one Questie lists for a quest you have (or one you can pick up),
-- one an unfinished objective in your log names, or one whose tooltip has a quest line.
-- A chest is known by its name (English names only).
-- The game's settings are changed only while the module is on, and put back when it is
-- switched off, unless you changed one yourself since.

local M = ns:NewModule("spotter", {
    title = "Object glow",
    desc = "A pillar of light rises from quest objects (gold) and chests (blue) near you, so you don't walk past them. Other objects get the game's small icon.",
    defaults = { enabled = false, quest = true, chest = true, sound = true, range = 30, was = {}, put = {} },
    options = {
        { type = "check", key = "quest", label = "Make quest objects glow" },
        { type = "check", key = "chest", label = "Make chests glow" },
        { type = "check", key = "sound", label = "Play a sound when one is found" },
        { type = "step", key = "range", label = "How far to look", min = 10, max = 40, step = 5,
            format = function(v) return v .. " yards" end },
        { type = "note", lines = 3, text = "The game shows one object at a time: the one it would interact with, the nearest around you. "
            .. "Switching the module off puts the game's settings back to what they were." },
    },
})

local SPARKLE = 984391 -- the game's sparkle (world/skillactivated/tradeskillnodes/sparkle.blp)
local BASE = "Interface\\Cooldown\\star4" -- the soft light where the pillar meets the object
local HEIGHT = 170 -- the pillar, in pixels on the screen
local RISERS = 5 -- sparkles drifting up it
local SEGMENTS = 12 -- the pillar is built of short pieces, each a little fainter, so it fades upward
local COLOR = { quest = { 1, 0.82, 0.1 }, chest = { 0.45, 0.85, 1 } }
COLOR.test = COLOR.quest

---------------------------------------------------------------------------
-- The game's settings
---------------------------------------------------------------------------

local function Get(cvar)
    local get = C_CVar and C_CVar.GetCVar or GetCVar
    if not get then return nil end
    local ok, value = pcall(get, cvar)
    return ok and value ~= nil and tostring(value) or nil
end

local function Set(cvar, value)
    local set = C_CVar and C_CVar.SetCVar or SetCVar
    if set then pcall(set, cvar, value) end
end

-- "30.000000" is 30
local function Same(a, b)
    if a == b then return true end
    local x, y = tonumber(a), tonumber(b)
    return x ~= nil and x == y
end

-- cvar -> value; `raise` ones are only made larger, never smaller.
function M:Wanted()
    local range = tostring(self.db.range or 30)
    return {
        SoftTargetInteract = { value = "3" }, -- Enum.SoftTargetEnableFlags.Any: with the mouse as well as a gamepad
        SoftTargetIconGameObject = { value = "1" },
        SoftTargetIconInteract = { value = "1" },
        SoftTargetInteractArc = { value = "2" }, -- all around you, not only in front
        SoftTargetInteractRange = { value = range },
        nameplateMaxDistance = { value = range, raise = true }, -- or the object's plate would not show that far
    }
end

local pending

function M:Apply()
    if InCombatLockdown and InCombatLockdown() then
        pending = true -- the game refuses setting changes in combat
        return
    end
    pending = false
    local was, put = self.db.was, self.db.put
    if self.enabled then
        for cvar, w in pairs(self:Wanted()) do
            local now = Get(cvar)
            local keep = w.raise and tonumber(now) and tonumber(now) >= tonumber(w.value)
            -- Set the first time; again when it is still ours (the distance changed) or was put back to the old
            -- value (Codex Forever does that when its search ends). Another value is one you chose: it stays.
            local ours = put[cvar] == nil or Same(now, put[cvar]) or Same(now, was[cvar])
            if now ~= nil and ours and not keep and not Same(now, w.value) then
                if was[cvar] == nil then was[cvar] = now end
                put[cvar] = w.value
                Set(cvar, w.value)
            end
        end
    else
        for cvar, value in pairs(was) do
            -- yours to keep if you changed it since
            if put[cvar] == nil or Same(Get(cvar), put[cvar]) then Set(cvar, value) end
            was[cvar], put[cvar] = nil, nil
        end
    end
end

---------------------------------------------------------------------------
-- What the object is
---------------------------------------------------------------------------

local CHEST = { "chest", "strongbox", "footlocker", "coffer", "lockbox", "treasure", "trunk" }

function M.IsChest(name)
    if type(name) ~= "string" then return false end
    local low = name:lower()
    for _, word in ipairs(CHEST) do
        if low:find("%f[%a]" .. word .. "%f[%A]") then return true end
    end
    return false
end

-- "GameObject-0-server-instance-zone-ID-spawn": the object's ID.
function M.ObjectID(guid)
    if type(guid) ~= "string" then return nil end
    local id = guid:match("^GameObject%-%d+%-%d+%-%d+%-%d+%-(%d+)")
    return id and tonumber(id) or nil
end

local objectives -- lower-case texts of the unfinished objectives in the log

local function Objectives()
    if objectives then return objectives end
    objectives = {}
    local log = C_QuestLog
    if log and log.GetNumQuestLogEntries and log.GetInfo and log.GetQuestObjectives then
        for i = 1, log.GetNumQuestLogEntries() or 0 do
            local info = log.GetInfo(i)
            if info and not info.isHeader and info.questID then
                for _, o in ipairs(log.GetQuestObjectives(info.questID) or {}) do
                    if not o.finished and type(o.text) == "string" then objectives[#objectives + 1] = o.text:lower() end
                end
            end
        end
    end
    return objectives
end

local function Questie(id)
    if not id or type(QuestieLoader) ~= "table" or type(QuestieLoader.ImportModule) ~= "function" then return false end
    local ok, tips = pcall(QuestieLoader.ImportModule, QuestieLoader, "QuestieTooltips")
    local list = ok and type(tips) == "table" and type(tips.lookupByKey) == "table" and tips.lookupByKey["o_" .. id]
    return type(list) == "table" and next(list) ~= nil
end

local function TooltipSaysQuest(unit)
    if not (C_TooltipInfo and C_TooltipInfo.GetUnit) then return false end
    local ok, data = pcall(C_TooltipInfo.GetUnit, unit)
    if not ok or type(data) ~= "table" or type(data.lines) ~= "table" then return false end
    for _, line in ipairs(data.lines) do
        local t = type(line) == "table" and line.type
        if t == 8 or t == 17 then return true end -- Enum.TooltipDataLineType.QuestObjective, QuestTitle
    end
    return false
end

-- "quest", "chest", "test" (an ordinary object while testing) or nil.
function M:Kind(name, id, unit)
    if self.db.quest then
        if Questie(id) or TooltipSaysQuest(unit) then return "quest" end
        if type(name) == "string" and #name >= 4 then
            local low = name:lower()
            for _, text in ipairs(Objectives()) do
                if text:find(low, 1, true) then return "quest" end
            end
        end
    end
    if self.db.chest and M.IsChest(name) then return "chest" end
    if self.testing then return "test" end -- /zod spotter test: every object, to see the look (no sound)
    return nil
end

-- /zod spotter test: every object the game picks gets the pillar (a mailbox, a door, a herb),
-- so the look can be tried without hunting for a chest. Until you type it again or /reload.
function M:Slash(arg)
    if (arg or ""):lower() ~= "test" then
        ns.Print("use /zod spotter test to make every object near you light up, to see how it looks.")
        return
    end
    if not self.enabled then
        ns.Print("Object glow is off: /zod spotter on first.")
        return
    end
    self.testing = not self.testing
    ns.Print(self.testing and "test: every object near you lights up now. Walk up to a mailbox or a door. /zod spotter test again to stop."
        or "test over: only quest objects and chests light up.")
    self:Update()
end

---------------------------------------------------------------------------
-- The glow
---------------------------------------------------------------------------

local glow -- one frame, moved to the plate of the object found
local told = {} -- objects already announced, by GUID
local toldCount = 0

local function Animate(f, elapsed)
    f.t = (f.t or 0) + (elapsed or 0)
    local t = f.t
    local pulse = 0.6 + 0.4 * math.sin(t * 2)
    f.core:SetAlpha(pulse)
    f.outer:SetAlpha(0.7 * pulse)
    f.base:SetAlpha(0.5 + 0.3 * pulse)
    for i, s in ipairs(f.risers) do
        local phase = (t * 0.5 + i / RISERS) % 1
        s:ClearAllPoints()
        s:SetPoint("CENTER", f, "BOTTOM", 14 * math.sin(i * 2 + t), phase * HEIGHT)
        s:SetAlpha(1 - phase)
    end
end

-- A beam of light `width` wide, brightest in the middle and at the bottom. A solid colour has hard
-- sides, so each piece is two halves that fade out sideways, and the pieces get fainter going up.
local function Beam(f, width, layer)
    local beam = CreateFrame("Frame", nil, f)
    beam:SetAllPoints(f)
    beam.width = width
    beam.halves = {}
    local h = HEIGHT / SEGMENTS
    for k = 1, SEGMENTS do
        for side = 1, 2 do
            local t = beam:CreateTexture(nil, layer)
            t:SetColorTexture(1, 1, 1, 1)
            t:SetBlendMode("ADD")
            t:SetSize(width / 2, h)
            t:SetPoint(side == 1 and "BOTTOMRIGHT" or "BOTTOMLEFT", beam, "BOTTOM", 0, (k - 1) * h)
            beam.halves[#beam.halves + 1] = { tex = t, side = side, fade = 1 - (k - 0.5) / SEGMENTS }
        end
    end
    return beam
end

local function PaintBeam(beam, r, g, b, peak)
    for _, half in ipairs(beam.halves) do
        local a = peak * half.fade
        if CreateColor and half.tex.SetGradient then
            local edge, middle = CreateColor(r, g, b, 0), CreateColor(r, g, b, a)
            if half.side == 1 then half.tex:SetGradient("HORIZONTAL", edge, middle)
            else half.tex:SetGradient("HORIZONTAL", middle, edge) end
        else
            half.tex:SetVertexColor(r, g, b, a * 0.5)
        end
    end
end

local function Build()
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetSize(56, HEIGHT)
    f:EnableMouse(false)
    f.outer = Beam(f, 56, "BACKGROUND")
    f.core = Beam(f, 16, "BORDER")
    f.base = f:CreateTexture(nil, "ARTWORK")
    f.base:SetTexture(BASE)
    f.base:SetBlendMode("ADD")
    f.base:SetSize(80, 80)
    f.base:SetPoint("CENTER", f, "BOTTOM", 0, 0)
    f.risers = {}
    for i = 1, RISERS do
        local s = f:CreateTexture(nil, "OVERLAY")
        s:SetTexture(SPARKLE)
        s:SetBlendMode("ADD")
        local size = i % 2 == 0 and 30 or 22
        s:SetSize(size, size)
        f.risers[i] = s
    end
    f:SetScript("OnUpdate", Animate)
    f:Hide()
    return f
end

local function Paint(f, c)
    local r, g, b = c[1], c[2], c[3]
    PaintBeam(f.core, r, g, b, 0.85)
    PaintBeam(f.outer, r, g, b, 0.4)
    f.base:SetVertexColor(r, g, b)
    for _, s in ipairs(f.risers) do s:SetVertexColor(r, g, b) end
end

local function Plate(unit)
    if not (C_NamePlate and C_NamePlate.GetNamePlateForUnit) then return nil end
    local ok, plate = pcall(C_NamePlate.GetNamePlateForUnit, unit, false)
    return ok and plate or nil
end

local function Hide()
    if glow then glow:Hide() end
    M.shown = nil
end

local function Show(plate, kind)
    glow = glow or Build()
    glow:SetParent(plate)
    if glow.SetIgnoreParentAlpha then glow:SetIgnoreParentAlpha(true) end -- the game dims plates that are not targeted
    glow:ClearAllPoints()
    glow:SetPoint("BOTTOM", plate, "BOTTOM", 0, -40) -- from the object, under its plate, upwards
    if glow.painted ~= kind then Paint(glow, COLOR[kind]) glow.painted = kind end
    if not glow:IsShown() then
        glow.t = 0
        glow:Show()
        Animate(glow, 0)
    end
    M.shown = kind
end

local function Announce(guid, kind)
    if kind == "test" or type(guid) ~= "string" or told[guid] then return end
    if toldCount > 500 then told, toldCount = {}, 0 end
    told[guid] = true
    toldCount = toldCount + 1
    if M.db.sound and PlaySound then
        local kit = SOUNDKIT or {}
        pcall(PlaySound, kind == "chest" and (kit.PUT_DOWN_SMALL_CHAIN or 1203) or (kit.MAP_PING or 3175))
    end
end

-- A plain string, or nil: in a fight the game may hand out "secret" values an addon cannot read.
local function Plain(ok, v)
    if not ok or type(v) ~= "string" then return nil end
    if issecretvalue and issecretvalue(v) then return nil end
    return v
end

function M:Update()
    local unit = "softinteract"
    local guid = Plain(pcall(UnitGUID, unit))
    local id = M.ObjectID(guid) -- an object, not an NPC (they have nameplates of their own anyway)
    if not id then return Hide() end
    local name = Plain(pcall(UnitName, unit))
    local kind = self:Kind(name, id, unit)
    local plate = kind and Plate(unit)
    if not plate then return Hide() end
    Show(plate, kind)
    Announce(guid, kind)
end

---------------------------------------------------------------------------

function M:OnEnable()
    objectives = nil
    self:Apply()
    self:Update()
end

function M:OnDisable()
    Hide()
    self:Apply()
end

function M:OnOption(key)
    objectives = nil
    if key == "range" then self:Apply() end
    self:Update()
end

local function Refresh() M:Update() end
M:On("PLAYER_SOFT_INTERACT_CHANGED", Refresh)
M:On("NAME_PLATE_UNIT_ADDED", Refresh)
M:On("NAME_PLATE_UNIT_REMOVED", Refresh)
local function Stale() objectives = nil end
M:On("QUEST_LOG_UPDATE", Stale)
M:On("QUEST_ACCEPTED", Stale)
M:On("QUEST_TURNED_IN", Stale)
-- (not tied to the module being on: switching it off in a fight puts the settings back afterwards)
ns.On("PLAYER_REGEN_ENABLED", function() if pending then M:Apply() end end)
M:On("PLAYER_ENTERING_WORLD", function() M:Apply() end)
-- Questie registers a quest's objects a moment after you take it, and another addon may undo a setting.
ns.Every(1, function() M:Update() if not pending then M:Apply() end end, M)
