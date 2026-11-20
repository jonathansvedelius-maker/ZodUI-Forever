local ADDON, ns = ...
local T = ns.T

-- Characters: one line per character that has logged in with ZodUI: level,
-- where it was left, how rested it is by now, gold and professions.

local M = ns:NewModule("alts", {
    title = "Characters",
    desc = "Keeps an overview of all your characters: level, where you left them, their rested XP as it stands now and when it is full, gold, professions and time played.",
    defaults = { enabled = true, full = true, cooldowns = true },
    options = {
        { type = "check", key = "full", label = "At login, say which other characters are fully rested" },
        { type = "check", key = "cooldowns", label = "At login, say which profession cooldowns are ready" },
        { type = "note", text = "A cooldown (a transmute, Mooncloth) is learned when that character opens its profession window.", lines = 2 },
    },
})

local FULL = 1.5 -- rested XP stops at a level and a half
local SORTS = { { "level", "Level" }, { "money", "Gold" }, { "name", "Name" }, { "seen", "Last played" } }
local sortBy = 1

local function Professions()
    local list = {}
    if not (GetProfessions and GetProfessionInfo) then return list end
    for _, index in ipairs({ GetProfessions() }) do
        local name, _, rank, max = GetProfessionInfo(index)
        if name then list[#list + 1] = { name = name, rank = rank or 0, max = max or 0 } end
    end
    return list
end

-- The dungeons and raids this character is saved to: { name, reset = when }.
local function Saved()
    local list = {}
    if not (GetNumSavedInstances and GetSavedInstanceInfo) then return list end
    for i = 1, GetNumSavedInstances() or 0 do
        local name, _, reset, _, locked = GetSavedInstanceInfo(i)
        if name and locked and type(reset) == "number" and reset > 0 then list[#list + 1] = { name = name, reset = time() + reset } end
    end
    return list
end

local function Update()
    local char = ns.char
    char.level = ns.Level()
    char.zone = GetRealZoneText and GetRealZoneText() or char.zone
    char.xp, char.xpMax = UnitXP("player") or 0, UnitXPMax("player") or 0
    char.rested = GetXPExhaustion and GetXPExhaustion() or 0
    char.resting = IsResting and IsResting() and true or false
    char.money = GetMoney()
    char.seen = time()
    if GetBindLocation then char.hearth = GetBindLocation() or char.hearth end
    ns.Refresh()
end

function M:OnEnable()
    Update()
    ns.char.profs = Professions()
    if (self:Rested(ns.char) or 0) < FULL then ns.char.fullSaid = nil end
    local full = {}
    for key, char in pairs(ns.db.chars) do
        if key ~= ns.charKey and not char.fullSaid and self:FullIn(char) == 0 and (char.level or 0) > 0 then
            char.fullSaid = true -- said once, until that character plays again
            full[#full + 1] = char.name or key
        end
    end
    if RequestRaidInfo then RequestRaidInfo() end -- the answer is UPDATE_INSTANCE_INFO
    local ready = {}
    for _, c in ipairs(self:Cooldowns()) do
        if c.ready <= time() and not c.cd.said then
            c.cd.said = true
            ready[#ready + 1] = c.name .. " on " .. c.who
        end
    end
    if self.db.cooldowns and #ready > 0 then
        ns.After(8, function() ns.Print("ready: " .. table.concat(ready, ", ") .. ".") end)
    end
    if self.db.full and #full > 0 then
        table.sort(full)
        ns.After(8, function()
            ns.Print(table.concat(full, ", ") .. (#full == 1 and " is" or " are") .. " fully rested.")
        end)
    end
end

for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "PLAYER_UPDATE_RESTING", "PLAYER_XP_UPDATE", "PLAYER_LOGOUT" }) do
    M:On(event, Update)
end

M:On("PLAYER_LEVEL_UP", function(_, _, level)
    Update()
    ns.char.level = level -- UnitLevel still gives the old level here
end)

M:On("UPDATE_INSTANCE_INFO", function()
    ns.char.saved = Saved()
    ns.Refresh()
end)

M:On("HEARTHSTONE_BOUND", function()
    if GetBindLocation then ns.char.hearth = GetBindLocation() end
end)

-- Profession cooldowns, read from the open profession window: [recipe] = { name, ready = when }.
local function ScanCooldowns()
    local list = ns.char.cooldowns or {}
    ns.char.cooldowns = list
    local trade = C_TradeSkillUI
    if trade and trade.GetAllRecipeIDs and trade.GetRecipeCooldown then
        for _, id in ipairs(trade.GetAllRecipeIDs() or {}) do
            local left = trade.GetRecipeCooldown(id)
            if type(left) == "number" and left > 0 then
                local info = trade.GetRecipeInfo and trade.GetRecipeInfo(id)
                list[id] = { name = info and info.name or ("Recipe " .. id), ready = time() + left }
            elseif list[id] and list[id].ready > time() then
                list[id].ready = time() -- ready sooner than we thought
            end
        end
    elseif GetNumTradeSkills and GetTradeSkillInfo and GetTradeSkillCooldown then
        for i = 1, GetNumTradeSkills() or 0 do
            local name, kind = GetTradeSkillInfo(i)
            local left = kind ~= "header" and GetTradeSkillCooldown(i)
            if name and type(left) == "number" and left > 0 then list[name] = { name = name, ready = time() + left } end
        end
    end
    ns.Refresh()
end

local scanning
local function ScanSoon()
    if scanning then return end
    scanning = true
    ns.After(0.5, function()
        scanning = false
        ScanCooldowns()
    end)
end
M:On("TRADE_SKILL_SHOW", ScanSoon)
M:On("TRADE_SKILL_LIST_UPDATE", ScanSoon)

-- Every cooldown of every character: { who, name, ready, key, char }, soonest first.
function M:Cooldowns()
    local list = {}
    for key, char in pairs(ns.db.chars) do
        for id, cd in pairs(char.cooldowns or {}) do
            list[#list + 1] = { who = char.name or key, name = cd.name, ready = cd.ready, cd = cd }
        end
    end
    table.sort(list, function(a, b)
        if a.ready ~= b.ready then return a.ready < b.ready end
        return a.who < b.who
    end)
    return list
end

local function When(ready)
    local left = ready - time()
    return left <= 0 and "|cff59d973ready|r" or ns.Duration(left)
end

M:On("SKILL_LINES_CHANGED", function()
    ns.char.profs = Professions()
end)

-- Rested XP as a share of a level, as it should stand now: 5% per eight hours
-- in an inn or city, a quarter of that elsewhere, up to a level and a half.
function M:Rested(char)
    local max = char.xpMax or 0
    if max <= 0 then return nil end
    local rested = (char.rested or 0) / max
    if char ~= ns.char then
        local hours = math.max(0, time() - (char.seen or time())) / 3600
        rested = rested + hours / 8 * 0.05 * (char.resting and 1 or 0.25)
    end
    return math.min(1.5, rested)
end

-- Seconds until `char` is fully rested, 0 when it is, nil when it cannot tell.
function M:FullIn(char)
    local rested = self:Rested(char)
    if not rested then return nil end
    if rested >= FULL then return 0 end
    local resting
    if char == ns.char then resting = IsResting and IsResting() else resting = char.resting end
    local perHour = 0.05 / 8 * (resting and 1 or 0.25)
    return (FULL - rested) / perHour * 3600
end

local function FullText(sec)
    if not sec then return "" end
    if sec <= 0 then return "full" end
    return "full in " .. ns.Duration(sec)
end

M:On("TIME_PLAYED_MSG", function(_, _, total)
    if type(total) == "number" and not (issecretvalue and issecretvalue(total)) then ns.char.playedTotal = total end
end)

local function Ago(at)
    if not at then return "-" end
    return ns.Ago(time() - at)
end

function M:Find(part, add, has)
    local found = {}
    for _, char in pairs(ns.db.chars) do
        if has(char.name) then found[#found + 1] = char end
    end
    table.sort(found, function(a, b) return (a.name or "") < (b.name or "") end)
    for _, char in ipairs(found) do
        add("Character", char.name, "level " .. (char.level or "?") .. (char.zone and (", " .. char.zone) or "")
            .. (char.hearth and (", hearth " .. char.hearth) or ""), "alts")
    end
    for _, c in ipairs(self:Cooldowns()) do
        if has(c.name) then add("Cooldown", c.name, c.who .. ": " .. (c.ready <= time() and "ready" or ("in " .. ns.Duration(c.ready - time()))), "alts") end
    end
end

function M:Hints(add)
    for _, c in ipairs(self:Cooldowns()) do
        if c.ready <= time() then add(c.name .. " is ready on " .. c.who, 60, "alts") end
    end
    for key, char in pairs(ns.db.chars) do
        if key ~= ns.charKey and self:FullIn(char) == 0 then add((char.name or key) .. " is fully rested", 40, "alts") end
    end
end

function M:Card()
    local others = {}
    for key, char in pairs(ns.db.chars) do
        if key ~= ns.charKey then others[#others + 1] = char end
    end
    table.sort(others, function(a, b) return (a.level or 0) > (b.level or 0) end)
    local lines = {}
    for i = 1, math.min(4, #others) do
        local char = others[i]
        local rested = self:Rested(char)
        local full = self:FullIn(char)
        lines[i] = { "|c" .. ns.ClassHex(char.class) .. (char.name or "?") .. "|r  |cff999999" .. (char.level or "?") .. "|r",
            rested and (math.floor(rested * 100) .. "% rested" .. (full and ("  |cff999999" .. FullText(full) .. "|r") or "")) or "" }
    end
    if #lines == 0 then lines[1] = { "Your other characters show up here", "" } lines[2] = { "once they have logged in.", "" } end
    return { title = "Characters", lines = lines, button = { "All", function() ns.Show("alts") end } }
end

ns.AddPage({
    key = "alts", title = "Characters", order = 30, group = "All characters", module = "alts",
    Build = function(page, f)
        local w = ns.PAGE_W
        page.off = T.Text(f, "GameFontHighlightSmall", T.MUTED)
        page.off:SetPoint("TOPLEFT", 0, -4)
        page.off:SetText("The Characters module is off. Switch it on under Settings.")
        page.list = T.Table(f, { { "Character", 100 }, { "Lvl", 34 }, { "Left in", 120 }, { "Rested", 120, "RIGHT" },
            { "Gold", 90, "RIGHT" }, { "Professions", w - 548 }, { "Seen", 84, "RIGHT" } }, w, ns.PAGE_H - 78)
        page.list:SetPoint("TOPLEFT", 0, 0)
        page.list.onClick = function(key)
            page.list.selected = key
            page:Refresh()
        end
        page.forget = T.Button(f, "Forget this character", 170, function()
            local key = page.list.selected
            if key and key ~= ns.charKey then -- the one you play cannot be forgotten
                ns.db.chars[key] = nil
                page.list.selected = nil
                page:Refresh()
            end
        end)
        page.forget:SetPoint("BOTTOMLEFT", 0, 0)
        page.forget.confirm = "Sure? Click again"
        page.hint = T.Text(f, "GameFontHighlightSmall", T.MUTED)
        page.hint:SetPoint("LEFT", page.forget, "RIGHT", 10, 0)
        -- Up to two lines in the room before the Sort button.
        page.hint:SetWidth(ns.PAGE_W - 130 - 10 - 180)
        page.hint:SetHeight(24)
        page.hint:SetJustifyV("MIDDLE")
        -- Pointing at the hint shows all of it, when two lines are not enough (many raid lockouts).
        page.hintHit = CreateFrame("Frame", nil, f)
        page.hintHit:SetAllPoints(page.hint)
        page.hintHit:EnableMouse(true)
        page.hintHit:SetScript("OnEnter", function(self) if page.fullHint then T.ShowTip(self, nil, page.fullHint) end end)
        page.hintHit:SetScript("OnLeave", T.HideTip)
        page.total = T.Text(f, "GameFontHighlightSmall", T.DIM)
        page.total:SetPoint("BOTTOMLEFT", 0, 30)
        page.cds = T.Text(f, "GameFontHighlightSmall", T.DIM)
        page.cds:SetPoint("BOTTOMLEFT", 0, 50)
        page.cds:SetWidth(w)
        page.cds:SetWordWrap(false)
        sortBy = SORTS[M.db.sortBy or 1] and M.db.sortBy or 1 -- kept across /reload
        page.sort = T.Button(f, "Sort: Level", 130, function()
            sortBy = sortBy % #SORTS + 1
            M.db.sortBy = sortBy ~= 1 and sortBy or nil
            page:Refresh()
        end)
        page.sort:SetPoint("BOTTOMRIGHT", 0, 0)
    end,
    Refresh = function(page)
        local on = M.enabled
        page.off:SetShown(not on)
        page.list:SetShown(on)
        page.forget:SetShown(on)
        page.hint:SetShown(on)
        page.hintHit:SetShown(on) -- its tooltip goes with the hint
        if not on then page.fullHint = nil end
        page.total:SetShown(on)
        page.sort:SetShown(on)
        page.cds:SetShown(on)
        if not on then return end
        page.sort.label:SetText("Sort: " .. SORTS[sortBy][2])
        page.sort.tip = "Click to sort by " .. SORTS[sortBy % #SORTS + 1][2]:lower() .. " instead."

        local rows = {}
        for key, char in pairs(ns.db.chars) do
            local profs = {}
            for _, p in ipairs(char.profs or {}) do profs[#profs + 1] = p.name .. " " .. p.rank end
            local rested = M:Rested(char)
            rows[#rows + 1] = {
                "|c" .. ns.ClassHex(char.class) .. (char.name or "?") .. "|r",
                char.level or "?",
                char.zone or "-",
                rested and (math.floor(rested * 100) .. "%" .. (M:FullIn(char) and ("  |cff999999" .. FullText(M:FullIn(char)) .. "|r") or "")) or "-",
                ns.Money(char.money or 0, true),
                table.concat(profs, ", "),
                key == ns.charKey and "now" or Ago(char.seen),
                data = key, level = char.level or 0, money = char.money or 0, name = char.name or key,
                seen = key == ns.charKey and time() or (char.seen or 0),
            }
        end
        local by = SORTS[sortBy][1]
        table.sort(rows, function(a, b)
            if by == "name" then
                if a.name ~= b.name then return a.name < b.name end
            elseif a[by] ~= b[by] then
                return a[by] > b[by]
            end
            return a.data < b.data
        end)
        page.list:SetRows(rows)
        local cds = {}
        for _, c in ipairs(M:Cooldowns()) do cds[#cds + 1] = c.who .. " " .. c.name .. " " .. When(c.ready) end
        page.cds:SetText(#cds > 0 and ("|cffffd100Cooldowns:|r " .. table.concat(cds, ",  ")) or "")
        local played, known, all = 0, 0, 0
        for _, char in pairs(ns.db.chars) do
            all = all + 1
            if char.playedTotal then played, known = played + char.playedTotal, known + 1 end
        end
        page.total:SetText(known == 0 and "Type /played on a character and its time played is added up here."
            or ("Played on all characters: " .. ns.Duration(played)
                .. (known < all and ("  |cff999999(" .. known .. " of " .. all .. "; /played on the others adds them)|r") or "")))
        local key = page.list.selected
        if not key then
            page.fullHint = nil
            page.hint:SetText("Click a character for its hearthstone and lockouts, or to remove one you deleted.")
        else
            local char = ns.db.chars[key] or {}
            local saved = {}
            for _, s in ipairs(char.saved or {}) do
                if s.reset > time() then saved[#saved + 1] = s.name .. " (" .. ns.Duration(s.reset - time()) .. ")" end
            end
            local full = "Hearth: " .. (char.hearth or "not known yet") .. ".  Saved to: " .. (#saved > 0 and table.concat(saved, ", ") or "nothing") .. "."
            page.fullHint = full
            local short = #saved > 2 and ("Hearth: " .. (char.hearth or "not known yet") .. ".  Saved to: " .. saved[1] .. ", " .. saved[2]
                .. " and " .. (#saved - 2) .. " more (point here for all).") or full
            page.hint:SetText(short .. ((key == ns.charKey or #saved > 2) and "" or "  The button removes it from ZodUI."))
        end
    end,
})
