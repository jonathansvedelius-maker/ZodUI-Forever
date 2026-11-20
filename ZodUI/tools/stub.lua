-- A stubbed WoW API for running ZodUI outside the game.
--
-- It is strict on purpose: a widget only has the methods and scripts its kind
-- has in the game, and backdrop calls need the BackdropTemplate. Calling
-- anything else is an error, so a typo or a method used on the wrong kind of
-- widget fails here instead of in the game.
--
-- The test drives it through the global `World`.

World = {
    clock = 1794650000, -- seconds; time() and date() read it
    uptime = 1000, -- GetTime()
    level = 24, xp = 4000, xpMax = 20000, rested = 3000, resting = false,
    money = 123456, zone = "Hillsbrad Foothills", subzone = "Tarren Mill",
    shift = false, combat = false,
    bags = {}, -- [bag][slot] = { id, quality, count, price, noValue }
    bagSize = { [0] = 16, 12, 12, 0, 0 },
    durability = {}, -- [slot] = { cur, max }
    cvars = { cameraDistanceMaxZoomFactor = "1.9", autoLootDefault = "0", lootUnderMouse = "0", scriptErrors = "0", profanityFilter = "1",
        screenshotQuality = "3", showTimestamps = "none", statusText = "0", showTargetOfTarget = "0" },
    party = {}, fighting = {},
    loaded = { ZodUI = true, NaowhForever_QoL = true },
    repairCost = 0, canRepair = true,
    calls = {}, -- names of the game functions the addon called, in order
    printed = {}, alerts = {},
    frames = {},
    friends = {}, cooldowns = {},
}
local W = World

local function Called(name, ...)
    W.calls[#W.calls + 1] = { name, ... }
end

---------------------------------------------------------------------------
-- Widgets
---------------------------------------------------------------------------

local function Set(list)
    local s = {}
    for name in list:gmatch("%S+") do s[name] = true end
    return s
end

local REGION = "SetPoint ClearAllPoints SetAllPoints GetPoint SetSize SetWidth SetHeight GetWidth GetHeight Show Hide SetShown IsShown "
    .. "IsVisible GetParent SetAlpha GetAlpha IsMouseOver GetCenter GetLeft GetTop "
local FRAME = REGION .. "SetScript GetScript HookScript RegisterEvent UnregisterEvent CreateFontString CreateTexture SetFrameStrata SetFrameLevel GetFrameLevel "
    .. "EnableMouse IsMouseEnabled EnableMouseWheel SetMovable SetClampedToScreen RegisterForDrag StartMoving StopMovingOrSizing GetEffectiveScale "
    .. "SetScale GetScale CreateAnimationGroup IsEventRegistered SetClipsChildren CreateLine "
local METHODS = {
    Frame = Set(FRAME),
    Button = Set(FRAME .. "RegisterForClicks SetAttribute GetAttribute"),
    ScrollFrame = Set(FRAME .. "SetScrollChild SetVerticalScroll GetVerticalScroll"),
    EditBox = Set(FRAME .. "SetMultiLine SetText GetText SetAutoFocus SetFontObject SetMaxLetters ClearFocus SetFocus HasFocus Insert HighlightText"),
    GameTooltip = Set(FRAME .. "SetOwner AddLine AddDoubleLine"),
    FontString = Set(REGION .. "SetText GetText SetFont GetFont SetTextColor GetTextColor SetJustifyH SetJustifyV SetWordWrap SetMaxLines GetStringWidth "
        .. "GetStringHeight SetSpacing"),
    Texture = Set(REGION .. "SetTexture SetVertexColor SetColorTexture SetTexCoord SetAtlas"),
    Line = Set(REGION .. "SetTexture SetVertexColor SetColorTexture SetThickness SetStartPoint SetEndPoint SetDrawLayer"),
}
local BACKDROP = Set("SetBackdrop SetBackdropColor SetBackdropBorderColor")
local SCRIPTS = {
    Frame = Set("OnEvent OnUpdate OnShow OnHide OnEnter OnLeave OnMouseWheel OnMouseUp OnMouseDown OnDragStart OnDragStop OnSizeChanged"),
}
SCRIPTS.Button = Set("OnEvent OnUpdate OnShow OnHide OnEnter OnLeave OnMouseWheel OnMouseUp OnMouseDown OnDragStart OnDragStop OnClick OnDoubleClick OnSizeChanged")
SCRIPTS.ScrollFrame = Set("OnEvent OnUpdate OnShow OnHide OnEnter OnLeave OnMouseWheel OnMouseUp OnMouseDown OnDragStart OnDragStop OnScrollRangeChanged")
SCRIPTS.GameTooltip = SCRIPTS.Frame
SCRIPTS.EditBox = Set("OnEvent OnUpdate OnShow OnHide OnEnter OnLeave OnEnterPressed OnEscapePressed OnEditFocusGained "
    .. "OnEditFocusLost OnTextChanged OnTabPressed OnArrowPressed")

local EVENTS = Set("ADDON_LOADED PLAYER_LOGIN PLAYER_LOGOUT PLAYER_ENTERING_WORLD PLAYER_XP_UPDATE PLAYER_LEVEL_UP PLAYER_DEAD "
    .. "QUEST_TURNED_IN PLAYER_MONEY ZONE_CHANGED_NEW_AREA PLAYER_UPDATE_RESTING SKILL_LINES_CHANGED MERCHANT_SHOW MERCHANT_CLOSED "
    .. "GOSSIP_SHOW QUEST_GREETING QUEST_DETAIL QUEST_PROGRESS QUEST_COMPLETE UPDATE_INVENTORY_DURABILITY BAG_UPDATE_DELAYED "
    .. "DUEL_REQUESTED PARTY_INVITE_REQUEST PLAYER_REGEN_ENABLED CHAT_MSG_LOOT UPDATE_FACTION BANKFRAME_OPENED BANKFRAME_CLOSED "
    .. "PLAYERBANKSLOTS_CHANGED PLAYER_REGEN_DISABLED RESURRECT_REQUEST CONFIRM_SUMMON CHAT_MSG_COMBAT_XP_GAIN TIME_PLAYED_MSG QUEST_LOG_UPDATE "
    .. "CHAT_MSG_WHISPER CHAT_MSG_BN_WHISPER CHAT_MSG_SAY CHAT_MSG_YELL CHAT_MSG_PARTY CHAT_MSG_PARTY_LEADER CHAT_MSG_RAID "
    .. "CHAT_MSG_RAID_LEADER CHAT_MSG_GUILD CHAT_MSG_OFFICER CHAT_MSG_CHANNEL CHAT_MSG_INSTANCE_CHAT PLAYER_FLAGS_CHANGED "
    .. "GUILD_INVITE_REQUEST PETITION_SHOW MAIL_SHOW MAIL_CLOSED PLAYER_EQUIPMENT_CHANGED MAIL_SEND_INFO_UPDATE CHAT_MSG_SKILL "
    .. "TRADE_SKILL_SHOW TRADE_SKILL_LIST_UPDATE UPDATE_INSTANCE_INFO HEARTHSTONE_BOUND LOOT_OPENED LOOT_CLOSED TRAINER_SHOW "
    .. "TRAINER_CLOSED TAXIMAP_OPENED TAXIMAP_CLOSED AUCTION_HOUSE_SHOW AUCTION_HOUSE_CLOSED START_LOOT_ROLL CANCEL_LOOT_ROLL "
    .. "UNIT_HAPPINESS UNIT_PET UNIT_PET_EXPERIENCE PET_UI_UPDATE ENCOUNTER_END BOSS_KILL ZONE_CHANGED ZONE_CHANGED_INDOORS "
    .. "PET_STABLE_SHOW PET_STABLE_UPDATE GUILD_RECIPE_KNOWN_BY_MEMBERS GROUP_ROSTER_UPDATE "
    .. "CONFIRM_XP_LOSS HARDCORE_DEATHS PLAYER_TARGET_CHANGED UPDATE_MOUSEOVER_UNIT QUEST_ACCEPTED CALENDAR_UPDATE_EVENT_LIST "
    .. "CHAT_MSG_ADDON GUILD_ROSTER_UPDATE TRADE_SHOW TRADE_ACCEPT_UPDATE TRADE_CLOSED PLAYER_ROLES_ASSIGNED")

local M = {}

function M:SetScript(name, fn)
    assert(SCRIPTS[self.kind] and SCRIPTS[self.kind][name], self.kind .. " has no script " .. tostring(name))
    assert(fn == nil or type(fn) == "function", name .. " is not a function")
    self.scripts[name] = fn
end
function M:GetScript(name) return self.scripts[name] end
function M:HookScript(name, fn)
    assert(SCRIPTS[self.kind] and SCRIPTS[self.kind][name], self.kind .. " has no script " .. tostring(name))
    local before = self.scripts[name]
    self.scripts[name] = before and function(...) before(...) return fn(...) end or fn
end
-- Attributes on a secure button are protected: changing them in combat is blocked, as in the game.
function M:SetAttribute(name, value)
    if W.combat and self.template == "SecureActionButtonTemplate" then
        error("ADDON_ACTION_BLOCKED: SetAttribute on " .. tostring(self.name) .. " in combat", 2)
    end
    self.attrs = self.attrs or {}
    self.attrs[name] = value
end
function M:GetAttribute(name) return self.attrs and self.attrs[name] end
function M:RegisterEvent(event)
    if not EVENTS[event] then error("Attempt to register unknown event \"" .. tostring(event) .. "\"", 2) end
    self.events[event] = true
end
function M:UnregisterEvent(event) self.events[event] = nil end
function M:IsEventRegistered(event) return self.events[event] == true end
function M:SetText(t) self.text = t == nil and "" or tostring(t) end
function M:GetText() return self.text or "" end
function M:SetTexture(path) self.texture = path end
function M:GetFont() return "Fonts\\FRIZQT__.TTF", self.size or 10, "" end
function M:SetFont(_, size) self.size = size end
function M:SetWordWrap(v) self.wrap = v and true or false end
function M:GetStringWidth()
    local plain = (self.text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|H.-|h", ""):gsub("|h", "")
    return #plain * 6
end
function M:GetStringHeight() return 12 end
function M:SetSize(w, h)
    assert(type(w) == "number" and type(h) == "number", "SetSize needs two numbers")
    self.w, self.h = w, h
end
function M:SetWidth(w) assert(type(w) == "number", "SetWidth needs a number") self.w = w end
function M:SetHeight(h) assert(type(h) == "number", "SetHeight needs a number") self.h = h end
function M:GetWidth() return self.w or 0 end
function M:GetHeight() return self.h or 0 end
function M:Show() self:SetShown(true) end
function M:Hide() self:SetShown(false) end
function M:SetShown(s)
    s = s and true or false
    if s == self.shown then return end
    self.shown = s
    local fn = self.scripts and self.scripts[s and "OnShow" or "OnHide"]
    if fn then fn(self) end
end
function M:IsShown() return self.shown end
function M:IsVisible()
    local r = self
    while r do
        if not r.shown then return false end
        r = r.parent
    end
    return true
end
function M:GetParent() return self.parent end
local POINTS = Set("TOPLEFT TOP TOPRIGHT LEFT CENTER RIGHT BOTTOMLEFT BOTTOM BOTTOMRIGHT")
function M:SetPoint(point, a, b, c, d)
    assert(POINTS[point], "bad anchor point " .. tostring(point))
    local rel, relPoint, x, y
    if type(a) == "number" or a == nil then
        x, y = a, b
    else
        rel = a
        if type(b) == "string" then relPoint, x, y = b, c, d else x, y = b, c end
        assert(type(rel) == "table" and rel.kind, "SetPoint: the second argument is not a widget")
        assert(relPoint == nil or POINTS[relPoint], "bad relative point " .. tostring(relPoint))
    end
    assert((x == nil or type(x) == "number") and (y == nil or type(y) == "number"), "SetPoint: offsets must be numbers")
    self.points[#self.points + 1] = { point, rel, relPoint or point, x or 0, y or 0 }
end
function M:ClearAllPoints() self.points = {} end
function M:SetAllPoints(rel) self.points = { { "ALL", rel } } end
function M:GetPoint(i)
    local p = self.points[i or 1]
    if p then return p[1], p[2], p[3], p[4], p[5] end
end
function M:GetCenter() return 400, 300 end
function M:GetEffectiveScale() return 1 end
function M:SetFrameLevel(l) self.level = l end
function M:GetFrameLevel() return self.level or 2 end
function M:IsMouseOver() return false end
function M:CreateFontString(_, layer, template) return World.New("FontString", self, template) end
function M:CreateTexture(_, layer) local t = World.New("Texture", self) t.layer = layer return t end
function M:CreateLine(_, layer) return World.New("Line", self) end
function M:SetStartPoint(point, rel, x, y)
    assert(type(point) == "string" and type(x) == "number" and type(y) == "number", "SetStartPoint(point, relativeTo, x, y)")
    self.from = { x, y }
end
function M:SetEndPoint(point, rel, x, y)
    assert(type(point) == "string" and type(x) == "number" and type(y) == "number", "SetEndPoint(point, relativeTo, x, y)")
    self.to = { x, y }
end
function M:GetLeft() return 100 end
function M:GetTop() return 600 end
function M:SetScrollChild(child) self.scrollChild = child end
function M:SetVerticalScroll(v) self.scroll = v end
function M:GetVerticalScroll() return self.scroll or 0 end
function M:SetFocus() self.focus = true end
function M:ClearFocus() self.focus = false end
function M:HasFocus() return self.focus == true end
function M:Insert(t) self.text = (self.text or "") .. tostring(t) end
function M:AddLine(text) self.lines[#self.lines + 1] = tostring(text) end
function M:AddDoubleLine(left, right) self.lines[#self.lines + 1] = tostring(left) .. " = " .. tostring(right) end
function M:SetOwner() self.lines = {} end
function M:SetBackdrop(b) self.backdrop = b end
function M:SetScale(s)
    assert(type(s) == "number" and s > 0, "SetScale needs a positive number")
    self.scale = s
end
function M:GetScale() return self.scale or 1 end
function M:SetAlpha(a)
    assert(type(a) == "number", "SetAlpha needs a number")
    self.alpha = a
end
function M:GetAlpha() return self.alpha or 1 end
-- Whether a frame takes the mouse. The game turns it on for every Button by itself; frames start without it.
function M:EnableMouse(on) self.mouse = on and true or false end
function M:IsMouseEnabled()
    if self.mouse == nil then return self.kind == "Button" end
    return self.mouse
end
-- Animation groups finish the moment they play: the alpha lands on its end value and OnFinished runs,
-- so code that hides a frame at the end of a fade is exercised. W.anims counts plays.
function M:CreateAnimationGroup()
    local owner = self
    local ag = { anims = {}, scripts = {}, playing = false }
    function ag:CreateAnimation(kind)
        assert(kind == "Alpha" or kind == "Scale" or kind == "Translation", "CreateAnimation: kind " .. tostring(kind))
        local a = { kind = kind }
        function a:SetDuration(d) assert(type(d) == "number" and d >= 0, "SetDuration needs a number") self.duration = d end
        function a:SetFromAlpha(v) self.from = v end
        function a:SetToAlpha(v) self.to = v end
        function a:SetSmoothing(s) self.smoothing = s end
        self.anims[#self.anims + 1] = a
        return a
    end
    function ag:SetToFinalAlpha(on) self.final = on end
    function ag:SetLooping(l) self.looping = l end
    function ag:SetScript(name, fn)
        assert(name == "OnFinished" or name == "OnStop" or name == "OnPlay", "AnimationGroup has no script " .. tostring(name))
        self.scripts[name] = fn
    end
    function ag:IsPlaying() return self.playing end
    function ag:Stop()
        if self.playing then self.playing = false if self.scripts.OnStop then self.scripts.OnStop(self) end end
    end
    function ag:Play()
        W.anims = (W.anims or 0) + 1
        for _, a in ipairs(self.anims) do
            if a.kind == "Alpha" and a.to then owner.alpha = a.to end
        end
        self.playing = false
        if self.scripts.OnFinished then self.scripts.OnFinished(self) end
    end
    return ag
end
function M:SetVertexColor(r, g, b, a) self.vertex = { r, g, b, a } end
function M:SetTextColor(r, g, b)
    assert(type(r) == "number" and type(g) == "number" and type(b) == "number", "SetTextColor needs three numbers")
    self.color = { r, g, b }
end
function M:GetTextColor() local c = self.color or { 1, 1, 1 } return c[1], c[2], c[3], 1 end

local function Noop() end

local meta = {
    __index = function(self, k)
        if type(k) ~= "string" or not k:match("^%u") then return nil end
        local ok = METHODS[self.kind][k] or (BACKDROP[k] and self.template == "BackdropTemplate")
        if not ok then
            if BACKDROP[k] then error(k .. " on a " .. self.kind .. " made without BackdropTemplate", 2) end
            return nil -- a field read, or a method this kind lacks: calling it fails with "attempt to call a nil value"
        end
        return M[k] or Noop
    end,
}

function World.New(kind, parent, template, name)
    assert(METHODS[kind], "unknown widget kind " .. tostring(kind))
    local w = setmetatable({ kind = kind, parent = parent, template = template, name = name, scripts = {}, events = {},
        points = {}, shown = true, lines = {} }, meta)
    W.frames[#W.frames + 1] = w
    return w
end

function CreateFrame(kind, name, parent, template)
    assert(kind == "Frame" or kind == "Button" or kind == "ScrollFrame" or kind == "EditBox", "CreateFrame: kind " .. tostring(kind))
    local f = World.New(kind, parent, template, name)
    if name then _G[name] = f end
    return f
end

UIParent = World.New("Frame")
Minimap = World.New("Frame", UIParent)
Minimap.w, Minimap.h = 140, 140
MailFrame = World.New("Frame", UIParent)
WorldMapFrame = World.New("Frame", UIParent)
WorldMapFrame.shown = false
WorldMapFrame.ScrollContainer = World.New("Frame", WorldMapFrame)
GameTooltip = World.New("GameTooltip", UIParent)
ItemRefTooltip = World.New("GameTooltip", UIParent)
UIErrorsFrame = { AddMessage = function(_, msg) W.alerts[#W.alerts + 1] = msg end }
UISpecialFrames = {}
SlashCmdList = {}

---------------------------------------------------------------------------
-- Lua 5.1 names and the game's globals
---------------------------------------------------------------------------

unpack = unpack or table.unpack
math.atan2 = math.atan2 or math.atan
tinsert = table.insert
function time() return W.clock end
function date(fmt, t) return os.date(fmt, t or W.clock) end
function GetTime() return W.uptime end
function debugprofilestop() return os.clock() * 1000 end
print = function(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
    W.printed[#W.printed + 1] = table.concat(parts, " ")
end

function UnitName(unit)
    if unit == nil or unit == "player" then return W.name or "Zod" end
    return W.units and W.units[unit] or nil
end
function UnitGUID(unit) return W.guids and W.guids[unit] or nil end
function UnitIsPlayer(unit) return W.players and W.players[unit] or false end
function UnitIsUnit(a, b) return W.units and W.units[a] ~= nil and W.units[a] == W.units[b] or false end
function GetRealmName() return "Forever" end
function UnitClass(unit)
    if unit and unit ~= "player" and W.classes and W.classes[unit] then return W.classes[unit], W.classes[unit], 0 end
    if W.hunter then return "Hunter", "HUNTER", 3 end
    return "Paladin", "PALADIN", 2
end
function UnitExists(unit) return W.units ~= nil and W.units[unit] ~= nil end
function UnitIsDead(unit)
    if W.deadUnits and W.deadUnits[unit] ~= nil then return W.deadUnits[unit] end
    return W.petDead or false
end
function UnitClassification(unit) return W.classes and W.classes[unit] or "normal" end
function GetGuildInfo(unit) return W.guild and (W.guildName or "Forever Friends") or nil, "Member", 2 end
-- Hunter pets, as WoW Forever has them (there is no GetPetHappiness global).
C_PetInfo = {
    GetPetHappiness = function()
        if W.happiness == nil then return nil end
        if W.happiness == W.secret then return W.secret, W.secret, W.secret end
        return W.happiness, ({ 75, 100, 125 })[W.happiness], W.loyaltyRate or 1
    end,
    GetPetLoyalty = function() return W.loyalty end,
    GetPetTrainingPoints = function()
        if W.tp then return W.tp[1], W.tp[2] end
        return 0, 0
    end,
    CanPetEatItem = function(id)
        W.foodChecks = (W.foodChecks or 0) + 1
        return W.petFood ~= nil and W.petFood[id] == true
    end,
    GetPetFoodTypes = function() return W.diet or {} end,
}
function GetPetExperience()
    if W.petXP then return W.petXP[1], W.petXP[2] end
    return 0, 0
end
C_Spell = { GetSpellName = function(id) return id == 6991 and "Feed Pet" or nil end }
function GetBindingKey(binding) return W.bindings and W.bindings[binding] or nil end
function GetInboxNumItems() return #(W.inbox or {}) end
function GetInboxHeaderInfo(i)
    local m = W.inbox[i]
    return nil, nil, "Bob", "Hi", m.money or 0, m.cod or 0, 1, m.items or 0
end
function TakeInboxMoney(i)
    Called("TakeInboxMoney", i)
    W.money = W.money + (W.inbox[i].money or 0)
    W.inbox[i].money = 0
end
function AutoLootMailItem(i)
    Called("AutoLootMailItem", i)
    W.inbox[i].items = 0
end
function UnitRace() return "Undead", "Scourge", 5 end
function UnitLevel() return W.level end
function UnitXP() return W.xp end
function UnitXPMax() return W.xpMax end
function GetXPExhaustion() return W.rested > 0 and W.rested or nil end
function IsResting() return W.resting end
function GetMoney() return W.money end
function GetRealZoneText() return W.zone end
function GetSubZoneText() return W.subzone end
function IsShiftKeyDown() return W.shift end
function IsAltKeyDown() return W.alt end
function InCombatLockdown() return W.combat end
function GetFramerate() return 59.6 end
function HasNewMail() return W.mail or false end
function GetUnitSpeed() return W.speed or 7 end
function GetNetStats() return 1, 1, 42, 55 end
function GetCursorPosition() return 500, 400 end
function GetInventoryItemDurability(slot)
    local d = W.durability[slot]
    if d then return d[1], d[2] end
end
function IsInInstance()
    if W.instance then return true, W.instance[2] end
    return false, "none"
end
function GetInstanceInfo()
    if W.instance then return W.instance[1], W.instance[2] end
    return "Eastern Kingdoms", "none"
end
function GetProfessions() return 1, 2 end
function UnitIsAFK() return W.afk or false end
function ReloadUI() Called("ReloadUI") end
function QuestLogPushQuest() Called("QuestLogPushQuest") end
function GetBindLocation() return W.hearth or "Tarren Mill" end
function RequestRaidInfo() Called("RequestRaidInfo") end
function GetNumSavedInstances() return #(W.saved or {}) end
function GetSavedInstanceInfo(i)
    local s = W.saved[i]
    return s[1], 1, s[2], 1, true
end
C_TradeSkillUI = {
    GetAllRecipeIDs = function() return W.recipes and W.recipeIDs or {} end,
    GetRecipeInfo = function(id) return W.recipes and W.recipes[id] and { name = W.recipes[id].name, learned = W.recipes[id].learned ~= false } end,
    IsTradeSkillLinked = function() return W.linkedSkill or false end,
    IsTradeSkillGuild = function() return false end,
    IsNPCCrafting = function() return false end,
    GetRecipeCooldown = function(id) return W.recipes and W.recipes[id] and W.recipes[id].cd or nil end,
}
function DeclineGuild() Called("DeclineGuild") end
function ClosePetition() Called("ClosePetition") end
function RepopMe() Called("RepopMe") end
C_DeathInfo = {
    GetSelfResurrectOptions = function() return W.selfRes or {} end,
    -- W.corpse = { x, y } on the map you stand on (0-1)
    GetCorpseMapPosition = function(map)
        assert(type(map) == "number", "GetCorpseMapPosition(uiMapID)")
        if not W.corpse then return nil end
        return { GetXY = function() return W.corpse[1], W.corpse[2] end }
    end,
}
C_GameRules = { IsHardcoreActive = function() return W.hardcore or false end }
C_VoiceChat = {
    SpeakText = function(voice, text, rate, volume, overlap)
        assert(type(voice) == "number" and type(text) == "string" and type(rate) == "number" and type(volume) == "number",
            "SpeakText(voiceID, text, rate, volume, overlap)")
        Called("SpeakText", text, overlap)
    end,
}
C_TTSSettings = {
    GetVoiceOptionID = function(kind) assert(kind == 0 or kind == 1, "GetVoiceOptionID(voiceType)") return 2 end,
    GetSpeechRate = function() return 0 end,
    GetSpeechVolume = function() return 100 end,
}
-- The stable: W.stable = { active = { PetInfo... }, stabled = { PetInfo... }, diets = { [slotID] = { "Meat" } } }
C_StableInfo = {
    GetActivePetList = function() return W.stable and W.stable.active or {} end,
    GetStabledPetList = function() return W.stable and W.stable.stabled or {} end,
    GetStablePetFoodTypes = function(slot)
        assert(type(slot) == "number", "GetStablePetFoodTypes(index)")
        return W.stable and W.stable.diets and W.stable.diets[slot] or {}
    end,
}
function ChatFrame_OpenChat(text) Called("OpenChat", text) end
function GetProfessionInfo(i)
    if W.profs and W.profs[i] then return unpack(W.profs[i]) end
    if i == 1 then return "Mining", nil, 150, 225 end
    return "Engineering", nil, 140, 225
end
function Screenshot() Called("Screenshot") end
function PlaySound(id) Called("PlaySound", id) end
SOUNDKIT = { TELL_MESSAGE = 3081 }
function issecretvalue(v) return v == W.secret and v ~= nil end
NUM_BAG_SLOTS = 4

C_AddOns = { IsAddOnLoaded = function(name) return W.loaded[name] or false end }
C_Map = {
    GetBestMapForUnit = function() return W.map or 1424 end,
    GetMapInfo = function(map) return { mapID = map, name = map == 1424 and "Hillsbrad Foothills" or ("Map " .. map) } end,
    CanSetUserWaypointOnMap = function(map) assert(type(map) == "number", "CanSetUserWaypointOnMap(uiMapID)") return true end,
    SetUserWaypoint = function(point)
        assert(type(point) == "table" and point.uiMapID and point.position, "SetUserWaypoint(UiMapPoint)")
        Called("SetUserWaypoint", point.uiMapID, point.position.x, point.position.y)
    end,
    GetMapWorldSize = function(map) return map == 1424 and 3000 or 0, map == 1424 and 2000 or 0 end,
    GetPlayerMapPosition = function()
        if W.instance then return nil end
        return { GetXY = function() return 0.6213, 0.2051 end }
    end,
}
UiMapPoint = {
    CreateFromCoordinates = function(map, x, y)
        assert(type(map) == "number" and type(x) == "number" and type(y) == "number", "UiMapPoint.CreateFromCoordinates(map, x, y)")
        return { uiMapID = map, position = { x = x, y = y } }
    end,
}
C_SuperTrack = { SetSuperTrackedUserWaypoint = function(on) Called("SuperTrackWaypoint", on) end }
C_QuestLog = {
    GetNumQuestLogEntries = function() return 15, 12 end,
    GetLogIndexForQuestID = function(id)
        for i, q in ipairs(W.questLog or {}) do
            if q.questID == id then return i end
        end
        return nil
    end,
    GetQuestObjectives = function(id)
        for _, q in ipairs(W.questLog or {}) do
            if q.questID == id then return q.objectives or {} end
        end
        return {}
    end,
    IsPushableQuest = function(id) return W.pushable and W.pushable[id] or false end,
    SetSelectedQuest = function(id) Called("SetSelectedQuest", id) end,
    GetSuggestedGroupSize = function(id) return W.groupQuests and W.groupQuests[id] or 0 end,
    GetInfo = function(i) return W.questLog and W.questLog[i] end,
    GetTitleForQuestID = function(id) return W.questTitles and W.questTitles[id] end,
    IsComplete = function(id)
        for _, q in ipairs(W.questLog or {}) do
            if q.questID == id then return q.complete or false end
        end
        return false
    end,
    GetMaxNumQuestsCanAccept = function() return 25 end,
}
C_Container = {
    GetContainerNumSlots = function(bag) return W.bagSize[bag] or 0 end,
    GetContainerNumFreeSlots = function(bag)
        local used = 0
        for _ in pairs(W.bags[bag] or {}) do used = used + 1 end
        return (W.bagSize[bag] or 0) - used
    end,
    GetContainerItemInfo = function(bag, slot)
        local item = W.bags[bag] and W.bags[bag][slot]
        if not item then return nil end
        return { itemID = item.id, quality = item.quality, stackCount = item.count or 1, hyperlink = "item:" .. item.id,
            hasNoValue = item.noValue or false, isLocked = false }
    end,
    UseContainerItem = function(bag, slot)
        Called("UseContainerItem", bag, slot)
        local item = W.bags[bag] and W.bags[bag][slot]
        if item and W.merchant then
            W.money = W.money + (item.price or 0) * (item.count or 1)
            W.bags[bag][slot] = nil
        end
    end,
    GetItemCooldown = function(id)
        local c = W.cooldowns[id]
        if c then return c[1], c[2], 1 end
        return 0, 0, 1
    end,
}
local function FindItem(id)
    id = tonumber(id) or tonumber(tostring(id):match("item:(%d+)"))
    for _, bag in pairs(W.bags) do
        for _, item in pairs(bag) do
            if item.id == id then return item end
        end
    end
end
C_Item = {
    GetItemInfo = function(link)
        local item = FindItem(link)
        if not item then return nil end
        return "Item " .. item.id, "item:" .. item.id, item.quality, item.ilvl or 1, 1, "Junk", "Junk", 20, item.equip or "", 1, item.price or 0
    end,
    GetItemCount = function(id, bank)
        local n = 0
        for _, bag in pairs(W.bags) do
            for _, item in pairs(bag) do
                if item.id == id then n = n + (item.count or 1) end
            end
        end
        return n + (bank and (W.bank and W.bank[id] or 0) or 0)
    end,
}
function CanMerchantRepair() return W.canRepair end
function GetRepairAllCost() return W.repairCost, W.repairCost > 0 end
function RepairAllItems(guild)
    Called("RepairAllItems", guild or false)
    if guild then
        W.guildMoney = (W.guildMoney or 0) - W.repairCost
    else
        W.money = W.money - W.repairCost
    end
    W.repairCost = 0
end
function IsInGuild() return W.guild or false end
function CanGuildBankRepair() return W.guildRepair or false end
function GetGuildBankWithdrawMoney() return W.guildLimit or -1 end
function GetGuildBankMoney() return W.guildMoney or 0 end
function AcceptResurrect() Called("AcceptResurrect") end
function UnitAffectingCombat(name) return W.fighting[name] or false end
function UnitInParty(name) return W.party[name] or false end
function UnitInRaid() return nil end
function IsInGroup() return next(W.party) ~= nil end

-- The group role the game gives you: World.role, "NONE" by default.
function UnitGroupRolesAssigned(unit) return unit == "player" and (W.role or "NONE") or "NONE" end

-- Equipment sets: World.sets = { { name = "Heal", equipped = true }, ... }; a set's id is its index.
C_EquipmentSet = {
    GetEquipmentSetIDs = function()
        local ids = {}
        for i in ipairs(W.sets or {}) do ids[#ids + 1] = i end
        return ids
    end,
    GetEquipmentSetInfo = function(id)
        local s = (W.sets or {})[id]
        if s then return s.name, 134400, id, s.equipped == true, 10, 10, 0, 0, 0 end
    end,
    GetEquipmentSetID = function(name)
        for i, s in ipairs(W.sets or {}) do
            if s.name == name then return i end
        end
    end,
    UseEquipmentSet = function(id)
        assert(not W.combat, "UseEquipmentSet in combat")
        Called("UseEquipmentSet", id)
        for i, s in ipairs(W.sets or {}) do s.equipped = i == id end
        return true
    end,
}
function ChatFrame_SendTell(name) Called("SendTell", name) end
function IsInRaid() return false end
function GetNumGroupMembers()
    local n = 0
    for _ in pairs(W.party) do n = n + 1 end
    return n
end
C_SummonInfo = {
    GetSummonConfirmSummoner = function() return W.summoner end,
    ConfirmSummon = function() Called("ConfirmSummon") end,
}
-- Addon messages: W.prefixes holds the registered ones; a send is recorded and returns W.sendResult (0: sent).
W.prefixes = {}
C_ChatInfo = {
    SendChatMessage = function(text, channel, lang, target) Called("SendChatMessage", text, channel, target) end,
    InChatMessagingLockdown = function() return W.chatLockdown or false end,
    RegisterAddonMessagePrefix = function(prefix)
        assert(type(prefix) == "string" and #prefix > 0 and #prefix <= 16, "a prefix is 1-16 characters")
        W.prefixes[prefix] = true
        return 0
    end,
    SendAddonMessage = function(prefix, text, channel, target)
        assert(W.prefixes[prefix], "SendAddonMessage with an unregistered prefix")
        assert(type(text) == "string" and #text <= 255, "an addon message is at most 255 characters")
        Called("SendAddonMessage", text, channel, target)
        return W.sendResult or 0
    end,
}
-- The guild roster: W.roster = { { "Name-Forever", online } ... }
function GetNumGuildMembers() return #(W.roster or {}) end
function GetGuildRosterInfo(i)
    local m = W.roster and W.roster[i]
    if not m then return nil end
    return m[1], "Member", 2, 25, "Warrior", "Orgrimmar", "", "", m[2]
end
-- Guild recipes: W.recipeMembers = { [recipeSpellID] = { { "Ann-Forever", true } ... } }; the test fires the answer.
C_GuildInfo = {
    GuildRoster = function() Called("GuildRoster") end,
    QueryGuildMembersForRecipe = function(skill, recipe)
        assert(type(skill) == "number" and type(recipe) == "number", "QueryGuildMembersForRecipe(skillLineID, recipeSpellID)")
        Called("QueryGuildMembersForRecipe", skill, recipe)
        W.recipeAsked = recipe
        return recipe
    end,
}
function GetGuildRecipeInfoPostQuery()
    local list = W.recipeMembers and W.recipeMembers[W.recipeAsked]
    return 197, W.recipeAsked, list and #list or 0
end
function GetGuildRecipeMember(i)
    local m = W.recipeMembers and W.recipeMembers[W.recipeAsked] and W.recipeMembers[W.recipeAsked][i]
    if m then return m[1], m[2] end
end
function Ambiguate(name, context)
    assert(type(name) == "string" and type(context) == "string", "Ambiguate(name, context)")
    return (name:gsub("%-Forever$", ""))
end
-- An open trade: W.trade = { gave = copper, got = copper, items = bool }
function GetPlayerTradeMoney() return tostring(W.trade and W.trade.gave or 0) end
function GetTargetTradeMoney() return tostring(W.trade and W.trade.got or 0) end
function GetTradePlayerItemLink(i) return W.trade and W.trade.items and i == 1 and "|Hitem:2589|h[Linen Cloth]|h" or nil end
function GetTradeTargetItemLink() return nil end
INVSLOT_AMMO = 0
function GetInventoryItemID(_, slot) return slot == 0 and W.ammo and 2512 or nil end
function GetInventoryItemCount(_, slot) return slot == 0 and W.ammo or 0 end

C_GossipInfo = {
    GetActiveQuests = function() return W.gossipActive or {} end,
    GetAvailableQuests = function() return W.gossipAvailable or {} end,
    SelectActiveQuest = function(id) Called("SelectActiveQuest", id) end,
    SelectAvailableQuest = function(id) Called("SelectAvailableQuest", id) end,
    GetOptions = function() return W.gossipOptions or {} end,
    SelectOption = function(id) Called("SelectOption", id) end,
}
function GetQuestItemLink(kind, i) return kind == "choice" and W.choiceLinks and W.choiceLinks[i] or nil end
function GetNumActiveQuests() return #(W.greetActive or {}) end
function GetActiveTitle(i) return "Quest " .. i, W.greetActive[i] end
function SelectActiveQuest(i) Called("SelectActiveQuest", i) end
function GetNumAvailableQuests() return W.greetAvailable or 0 end
function IsAvailableQuestTrivial(i) return W.greetTrivial and W.greetTrivial[i] or false end
function SelectAvailableQuest(i) Called("SelectAvailableQuest", i) end
function AcceptQuest() Called("AcceptQuest") end
function IsQuestCompletable() return W.completable end
function CompleteQuest() Called("CompleteQuest") end
function GetNumQuestChoices() return W.choices or 0 end
function GetQuestReward(i) Called("GetQuestReward", i) end

function CancelDuel() Called("CancelDuel") end
function AcceptGroup() Called("AcceptGroup") end
function StaticPopup_Hide(which) Called("StaticPopup_Hide", which) end
-- W.friendList = { { name = "Ann", connected = true, level = 60, className = "Priest" } ... }
C_FriendList = {
    IsFriend = function(guid) return W.friends[guid] or false end,
    GetNumFriends = function() return #(W.friendList or {}) end,
    GetFriendInfoByIndex = function(i) return W.friendList and W.friendList[i] end,
}
C_PartyInfo = { InviteUnit = function(name) assert(type(name) == "string", "InviteUnit(name)") Called("InviteUnit", name) end }
function RequestRaidInfo() Called("RequestRaidInfo") end
-- The calendar: W.calendarNow = { year, month, monthDay, hour, minute }; W.calendar[offset][day] = { CalendarDayEvent ... }
C_DateAndTime = { GetCurrentCalendarTime = function() return W.calendarNow end }
C_Calendar = {
    OpenCalendar = function() Called("OpenCalendar") end,
    GetMonthInfo = function(offset) return { numDays = (W.monthDays or {})[offset] or 30 } end,
    GetNumDayEvents = function(offset, day)
        assert(type(offset) == "number" and type(day) == "number", "GetNumDayEvents(offsetMonths, monthDay)")
        return #((W.calendar or {})[offset] and W.calendar[offset][day] or {})
    end,
    GetDayEvent = function(offset, day, i) return W.calendar and W.calendar[offset] and W.calendar[offset][day] and W.calendar[offset][day][i] end,
}
function IsGuildMember() return false end

C_CVar = {
    GetCVar = function(name) return W.cvars[name] end,
    SetCVar = function(name, value)
        Called("SetCVar", name, value)
        W.cvars[name] = tostring(value)
    end,
}

LOOT_ITEM_SELF = "You receive loot: %s."
LOOT_ITEM_SELF_MULTIPLE = "You receive loot: %sx%d."
LOOT_ITEM_PUSHED_SELF = "You receive item: %s."
LOOT_ITEM_PUSHED_SELF_MULTIPLE = "You receive item: %sx%d."

W.factions = {
    { name = "Horde", isHeader = true },
    { factionID = 68, name = "Undercity", reaction = 5, currentReactionThreshold = 3000, nextReactionThreshold = 9000, currentStanding = 4500 },
    { factionID = 76, name = "Orgrimmar", reaction = 4, currentReactionThreshold = 0, nextReactionThreshold = 3000, currentStanding = 1200 },
    { factionID = 21, name = "Booty Bay", reaction = 4, currentReactionThreshold = 0, nextReactionThreshold = 3000, currentStanding = 500 },
}
C_Reputation = {
    GetNumFactions = function() return #W.factions end,
    GetFactionDataByIndex = function(i) return W.factions[i] end,
    SetWatchedFactionByID = function(id) Called("SetWatchedFactionByID", id) end,
}

Enum = { TooltipDataType = { Item = 0, Spell = 1, Unit = 2 }, BagIndex = { CharacterBankTab_1 = 6 } }
W.tooltipCalls = {}
TooltipDataProcessor = {
    AddTooltipPostCall = function(kind, fn)
        assert(kind ~= nil and type(fn) == "function", "AddTooltipPostCall")
        W.tooltipCalls[kind] = fn
    end,
}
W.chatFilters = {}
W.chatFilterList = {}
-- Custom chat channels: World.channels = { name = id }.
W.channels = {}
function GetChannelName(name)
    for n, id in pairs(W.channels) do
        if type(name) == "string" and n:lower() == name:lower() then return id, n end
    end
    return 0, nil
end
function JoinTemporaryChannel(name)
    Called("JoinTemporaryChannel", name)
    local n = 0
    for _ in pairs(W.channels) do n = n + 1 end
    W.channels[name] = n + 5
end
function LeaveChannelByName(name)
    Called("LeaveChannelByName", name)
    W.channels[name] = nil
end
ChatFrameUtil = {
    AddMessageEventFilter = function(event, fn)
        assert(type(event) == "string" and type(fn) == "function", "AddMessageEventFilter")
        W.chatFilters[event] = W.chatFilters[event] or fn -- the first, as the tests knew it
        W.chatFilterList[event] = W.chatFilterList[event] or {}
        table.insert(W.chatFilterList[event], fn)
    end,
}
W.hooks = {}
function SetItemRef(link, ...)
    for _, fn in ipairs(W.hooks.SetItemRef or {}) do fn(link, ...) end
end
-- Shift-clicking a link: the game's chat box takes it; hooks see it after.
function ChatEdit_InsertLink(text)
    for _, fn in ipairs(W.hooks.ChatEdit_InsertLink or {}) do fn(text) end
    return false
end
function hooksecurefunc(name, fn)
    assert(type(name) == "string" and type(_G[name]) == "function" and type(fn) == "function", "hooksecurefunc")
    W.hooks[name] = W.hooks[name] or {}
    table.insert(W.hooks[name], fn)
end
W.registry = {}
EventRegistry = {
    RegisterCallback = function(_, name, fn, owner)
        W.registry[name] = function(...) return fn(owner, ...) end
    end,
}

-- Loot rolls: W.rolls[id] = { link, icon, name, count, quality, canNeed, canGreed, canDE, whyNeed, whyGreed, whyDE, left (ms) }.
W.rolls = {}
function GetLootRollItemLink(id) return W.rolls[id] and W.rolls[id].link end
function GetLootRollItemInfo(id)
    local r = W.rolls[id]
    if not r then return end
    return r.icon, r.name, r.count or 1, r.quality, false, r.canNeed, r.canGreed, r.canDE, r.whyNeed, r.whyGreed, r.whyDE
end
function GetLootRollTimeLeft(id) return W.rolls[id] and W.rolls[id].left or 0 end
function GetActiveLootRollIDs()
    local ids = {}
    for id in pairs(W.rolls) do ids[#ids + 1] = id end
    table.sort(ids)
    return ids
end
function RollOnLoot(id, choice) Called("RollOnLoot", id, choice) end
SOUNDKIT.READY_CHECK = 8960
NUM_GROUP_LOOT_FRAMES = 4
GroupLootFrame1 = World.New("Frame", UIParent)
LOOT_ROLL_NEED = "%s has selected Need for: %s"
LOOT_ROLL_GREED = "%s has selected Greed for: %s"
LOOT_ROLL_DISENCHANT = "%s has selected Disenchant for: %s"
LOOT_ROLL_PASSED = "%s passed on: %s"
LOOT_ROLL_PASSED_AUTO = "%s automatically passed on: %s because he cannot loot that item."
LOOT_ROLL_NEED_SELF = "You have selected Need for: %s"
LOOT_ROLL_GREED_SELF = "You have selected Greed for: %s"
LOOT_ROLL_PASSED_SELF = "You passed on: %s"
LOOT_ROLL_ROLLED_NEED = "Need Roll - %d for %s by %s"
LOOT_ROLL_ROLLED_GREED = "|HlootHistory:%d|h[Loot]|h: Greed Roll - %d for %s by %s" -- as newer clients write it
-- The 12.x client's roll container, as the in-game trace showed it: it listens to START_LOOT_ROLL itself (not only
-- UIParent), puts a free GroupLootFrame in a new slot each time, and only lets a slot go through
-- GroupLootContainer_RemoveFrame. A frame hidden from outside keeps its slot, so the empty container stays shown,
-- grows a slot per roll and takes the mouse in the middle of the screen.
GroupLootContainer = World.New("Frame", UIParent)
GroupLootContainer.rollFrames = {}
GroupLootContainer:Hide()
function GroupLootContainer_AddFrame(self, frame)
    self.rollFrames[#self.rollFrames + 1] = frame
    self:SetHeight(100 * #self.rollFrames)
    self:EnableMouse(true)
    self:Show()
    frame:Show()
end
function GroupLootContainer_RemoveFrame(self, frame)
    for i = #self.rollFrames, 1, -1 do
        if self.rollFrames[i] == frame then table.remove(self.rollFrames, i) end
    end
    frame:Hide()
    if #self.rollFrames == 0 then self:Hide() end
end
GroupLootContainer:RegisterEvent("START_LOOT_ROLL")
GroupLootContainer:SetScript("OnEvent", function(self, event)
    if event == "START_LOOT_ROLL" then GroupLootContainer_AddFrame(self, GroupLootFrame1) end
end)
LOOT_ROLL_WON = "%s won: %s"
LOOT_ROLL_YOU_WON = "You won: %s"
LOOT_ROLL_ALL_PASSED = "Everyone passed on: %s"
LOOT_ROLL_INELIGIBLE_REASON2 = "You cannot need this item."
