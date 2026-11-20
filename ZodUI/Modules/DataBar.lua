local ADDON, ns = ...
local T = ns.T

-- Info bar: one thin line of the numbers you keep checking. Each part can be
-- switched off; the bar sits at the top or the bottom, or wherever you drag it.

-- Only what EllesmereUI DataBars and NaowhForever_QoL's top bar do not show: level, XP, gold, bags,
-- durability, hearthstone, zone, coordinates, frame rate and the clock are theirs.
local PARTS = {
    { "rate", "XP per hour this session" },
    { "session", "Gold this session" },
    { "quests", "Quests in the log" },
    { "todo", "Open to-dos" },
    { "remind", "Next reminder" },
    { "mail", "New mail" },
    { "speed", "Movement speed", false },
}
local options = {
    { type = "cycle", key = "where", label = "Position", choices = { { "top", "Top of the screen" }, { "bottom", "Bottom of the screen" },
        { "free", "Where I drag it" } } },
    { type = "note", text = "With 'Where I drag it', hold Shift and drag the bar.", lines = 1 },
    { type = "check", key = "fade", label = "Fade the bar during fights" },
    { type = "check", key = "big", label = "Larger text" },
    { type = "header", label = "Shown on the bar" },
}
local defaults = { enabled = true, where = "top", pos = {}, fade = true, big = false }
for _, part in ipairs(PARTS) do
    options[#options + 1] = { type = "check", key = part[1], label = part[2] }
    defaults[part[1]] = part[3] ~= false
end

local M = ns:NewModule("databar", {
    title = "Info bar",
    desc = "A thin bar with what the other bars leave out: XP per hour, gold this session, quest count, open to-dos, the next reminder, new mail and movement speed.",
    defaults = defaults,
    conflicts = { "NaowhForever_QoL" },
    options = options,
})

local bar

local function Label(text)
    return "|cff999999" .. text .. "|r "
end

local TEXT = {}

function TEXT.rate()
    local session = ns.modules.session
    if not (session and session.enabled and session.Rate) then return nil end
    local perHour = session:Rate()
    if not perHour or perHour <= 0 then return nil end
    return Label("XP/h") .. ns.Comma(math.floor(perHour + 0.5))
end

function TEXT.quests()
    if not (C_QuestLog and C_QuestLog.GetNumQuestLogEntries) then return nil end
    local _, quests = C_QuestLog.GetNumQuestLogEntries()
    local max = C_QuestLog.GetMaxNumQuestsCanAccept and C_QuestLog.GetMaxNumQuestsCanAccept() or nil
    return Label("Quests") .. (quests or 0) .. (max and ("/" .. max) or "")
end

function TEXT.session()
    local gold = ns.modules.gold
    if not (gold and gold.enabled and gold.Session) then return nil end
    local net = gold:Session()
    if net == 0 then return nil end
    return Label("Session") .. (net > 0 and "+" or "") .. ns.Money(net, true)
end

function TEXT.todo()
    local open = 0
    for _, list in ipairs({ ns.chardb.notes or {}, ns.db.notes or {} }) do
        for _, note in ipairs(list) do
            if not note.done then open = open + 1 end
        end
    end
    if open == 0 then return nil end
    return Label("To do") .. open
end

function TEXT.remind()
    local next = ns.db.reminders and ns.db.reminders[1]
    if not next then return nil end
    if next.due then return Label("Remind") .. "|cffffd100now|r" end
    if next.login and next.at > time() then return nil end
    return Label("Remind") .. ns.Duration(next.at - time())
end

function TEXT.mail()
    if HasNewMail and HasNewMail() then return "|cffffd100Mail|r" end
    return nil
end

function TEXT.speed()
    if not GetUnitSpeed then return nil end
    local speed = GetUnitSpeed("player")
    if type(speed) ~= "number" or (issecretvalue and issecretvalue(speed)) then return nil end
    return Label("Speed") .. math.floor(speed / 7 * 100 + 0.5) .. "%"
end

local function Update()
    if not bar then return end
    local parts = {}
    for _, part in ipairs(PARTS) do
        if M.db[part[1]] then
            local text = TEXT[part[1]]()
            if text then parts[#parts + 1] = text end
        end
    end
    bar.text:SetText(table.concat(parts, "    "))
    -- The width moves in steps and shrinks only by a clear amount, so a number that ticks every second
    -- (speed, a countdown) does not make the bar twitch.
    local want = math.max(60, math.ceil(((bar.text:GetStringWidth() or 0) + 24) / 16) * 16)
    local now = bar:GetWidth() or 0
    if want > now or now - want >= 32 then bar:SetWidth(want) end
end

-- The text size: the font's own, or two points larger.
local function Size()
    if not bar then return end
    local font, size, flags = bar.text:GetFont()
    local base = T.FontSize(bar.text) or size or 10 -- follows the Text size setting as it changes
    if font then bar.text:SetFont(font, base + (M.db.big and 2 or 0), flags) end
    bar:SetHeight(M.db.big and 26 or 22)
end

ns.fontListeners = ns.fontListeners or {}
table.insert(ns.fontListeners, function() Size() end)

local function Place()
    bar:ClearAllPoints()
    local where = M.db.where
    if where == "free" and M.db.pos.point then
        bar:SetPoint(M.db.pos.point, UIParent, M.db.pos.rel or M.db.pos.point, M.db.pos.x or 0, M.db.pos.y or 0)
    elseif where == "bottom" then
        bar:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 2)
    else
        bar:SetPoint("TOP", UIParent, "TOP", 0, -2)
    end
end

local function Build()
    local b = CreateFrame("Button", "ZodUIDataBar", UIParent, "BackdropTemplate")
    b:SetSize(400, 22)
    b:SetFrameStrata("MEDIUM")
    T.Flat(b, T.WINDOW, 0.88)
    b.text = T.Text(b, "GameFontHighlightSmall")
    b.text:SetPoint("CENTER", 0, 0)
    b.text:SetWordWrap(false)
    T.Movable(b, M.db.pos, b, true)
    local stop = b:GetScript("OnDragStop")
    b:SetScript("OnDragStop", function(self)
        stop(self)
        M.db.where = "free" -- a bar that was dragged stays where it was dropped
    end)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp", "MiddleButtonUp")
    b:SetScript("OnClick", function(_, mouse)
        if mouse == "RightButton" then
            ns.Show("settings", "databar")
        elseif mouse == "MiddleButton" then -- as on the minimap button
            ns.Show("notes")
        else
            ns.Toggle()
        end
    end)
    b:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(T.GOLD[1], T.GOLD[2], T.GOLD[3], 1)
        local lines = ns.Glance and ns.Glance() or {}
        if #lines > 0 then lines[#lines + 1] = " " end
        lines[#lines + 1] = "Click: open or close ZodUI\nRight-click: the info bar's settings\nMiddle-click: the to-do list\nShift-drag: move the bar"
        T.ShowTip(self, "ZodUI", table.concat(lines, "\n"))
    end)
    b:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(T.BORDER[1], T.BORDER[2], T.BORDER[3], 1)
        T.HideTip()
    end)
    return b
end

function M:OnEnable()
    if not bar then bar = Build() end
    Place()
    Size()
    Update()
    bar:Show()
end

function M:OnDisable()
    if bar then bar:Hide() end
end

function M:OnOption(key)
    if not bar then return end
    if key == "where" or key == "pos" then
        if key == "pos" then self.db.where = "top" end
        Place()
    end
    if key == "big" then Size() end
    Update()
end

ns.AddMover({
    key = "databar", title = "Info bar", width = 400, height = 22, point = "TOP", x = 0, y = -2,
    Store = function() return M.db.pos end,
    Reset = function() -- right-click in unlock mode: back to the top of the screen
        for k in pairs(M.db.pos) do M.db.pos[k] = nil end
        M.db.where = "top"
        if bar then Place() end
    end,
    Shown = function() return M.enabled end,
    Apply = function()
        M.db.where = "free"
        if bar then Place() end
    end,
})

M:On("PLAYER_REGEN_DISABLED", function(self)
    if bar and self.db.fade then bar:SetAlpha(0.35) end
end)
M:On("PLAYER_REGEN_ENABLED", function()
    if bar then bar:SetAlpha(1) end
end)

ns.Every(1, Update, M)
