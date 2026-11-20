local ADDON, ns = ...
local T = ns.T

-- Reputation: every faction with its standing and how far into it you are,
-- and what you gained since login.

local M = ns:NewModule("rep", {
    title = "Reputation",
    desc = "Lists your factions with their standing and progress, and what you gained with each since you logged in.",
    defaults = { enabled = true, alert = true, watch = false },
    options = {
        { type = "check", key = "alert", label = "Say when your standing with a faction changes" },
        { type = "check", key = "watch", label = "Watch the faction you last gained with (the bar under your XP)" },
    },
})

local STANDING = { "Hated", "Hostile", "Unfriendly", "Neutral", "Friendly", "Honored", "Revered", "Exalted" }
local STANDING_HEX = { "ffcc2222", "ffff4444", "ffee6622", "ffffff00", "ff59d973", "ff59d9a0", "ff40c8d8", "ffb070ff" }
local seen, gained, standing = {}, {}, {}
local loginAt, lastWatched
local onlyGained = false

local function StandingName(reaction)
    return _G["FACTION_STANDING_LABEL" .. tostring(reaction)] or STANDING[reaction] or "?"
end

-- The factions as the reputation window lists them (collapsed groups stay collapsed).
local function Factions()
    local list = {}
    if C_Reputation and C_Reputation.GetNumFactions and C_Reputation.GetFactionDataByIndex then
        for i = 1, C_Reputation.GetNumFactions() or 0 do
            local d = C_Reputation.GetFactionDataByIndex(i)
            if d and d.name then
                list[#list + 1] = { id = d.factionID, name = d.name, header = d.isHeader and not d.isHeaderWithRep,
                    reaction = d.reaction, min = d.currentReactionThreshold, max = d.nextReactionThreshold, value = d.currentStanding }
            end
        end
    elseif GetNumFactions and GetFactionInfo then
        for i = 1, GetNumFactions() or 0 do
            local name, _, reaction, min, max, value, _, _, isHeader, _, hasRep, _, _, id = GetFactionInfo(i)
            if name then
                list[#list + 1] = { id = id, name = name, header = isHeader and not hasRep, reaction = reaction, min = min, max = max,
                    value = value }
            end
        end
    end
    return list
end

local function Scan(count)
    for _, f in ipairs(Factions()) do
        if f.id and not f.header and type(f.value) == "number" then
            local before = seen[f.id]
            if count and before and f.value ~= before then
                gained[f.id] = (gained[f.id] or 0) + f.value - before
                if f.value > before and M.db.watch and lastWatched ~= f.id then
                    local watch = C_Reputation and C_Reputation.SetWatchedFactionByID
                    if watch then
                        pcall(watch, f.id)
                        lastWatched = f.id
                    end
                end
            end
            seen[f.id] = f.value
            local was = standing[f.id]
            if count and was and f.reaction and f.reaction ~= was and M.db.alert then
                ns.Alert(f.name .. ": now " .. StandingName(f.reaction) .. ".")
            end
            standing[f.id] = f.reaction or was
        end
    end
end

function M:OnEnable()
    loginAt = loginAt or time()
    Scan(false)
end

-- Seconds to the next standing at the pace since login, or nil.
local function NextIn(f)
    local gain = f.id and gained[f.id]
    local took = time() - (loginAt or time())
    if not gain or gain <= 0 or took < 300 or not f.max or not f.value or f.max <= f.value then return nil end
    return (f.max - f.value) / (gain / took)
end

M:On("UPDATE_FACTION", function()
    Scan(true)
    ns.Refresh()
end)

local function Signed(n)
    if n > 0 then return "|cff59d973+" .. ns.Comma(n) .. "|r" end
    return "|cffff6060" .. ns.Comma(n) .. "|r"
end

local function StandingText(reaction)
    return "|c" .. (STANDING_HEX[reaction] or "ffffffff") .. StandingName(reaction) .. "|r"
end

local function Progress(f)
    local span = (f.max or 0) - (f.min or 0)
    return span > 0 and (ns.Comma((f.value or 0) - f.min) .. " / " .. ns.Comma(span)) or nil
end

function M:Find(part, add, has)
    for _, f in ipairs(Factions()) do
        if not f.header and has(f.name) then
            local progress = Progress(f)
            add("Faction", f.name, StandingName(f.reaction) .. (progress and (", " .. progress) or ""), "rep")
        end
    end
end

function M:Card()
    local list = {}
    for _, f in ipairs(Factions()) do
        if f.id and gained[f.id] and gained[f.id] ~= 0 then list[#list + 1] = f end
    end
    table.sort(list, function(a, b) return math.abs(gained[a.id]) > math.abs(gained[b.id]) end)
    local lines = {}
    for i = 1, math.min(4, #list) do lines[i] = { list[i].name, Signed(gained[list[i].id]) } end
    if #lines == 0 then lines[1] = { "No reputation gained since login.", "" } end
    return { title = "Reputation", lines = lines, button = { "All", function() ns.Show("rep") end } }
end

ns.AddPage({
    key = "rep", title = "Reputation", order = 22, group = "This character", module = "rep",
    Build = function(page, f)
        local w = ns.PAGE_W
        page.off = T.Text(f, "GameFontHighlightSmall", T.MUTED)
        page.off:SetPoint("TOPLEFT", 0, -4)
        page.off:SetText("The Reputation module is off. Switch it on under Settings.")
        page.list = T.Table(f, { { "Faction", w - 530 }, { "Standing", 110 }, { "Progress", 170, "RIGHT" }, { "Since login", 120, "RIGHT" },
            { "Next standing", 110, "RIGHT" } }, w, ns.PAGE_H - 30)
        page.list:SetPoint("TOPLEFT", 0, 0)
        onlyGained = M.db.onlyGained or false -- kept across /reload
        page.only = T.Button(f, "Only those gained", 150, function()
            onlyGained = not onlyGained
            M.db.onlyGained = onlyGained or nil
            page:Refresh()
        end)
        page.only:SetPoint("BOTTOMLEFT", 0, 0)
    end,
    Refresh = function(page)
        local on = M.enabled
        page.off:SetShown(not on)
        page.list:SetShown(on)
        page.only:SetShown(on)
        if not on then return end
        page.only.label:SetText(onlyGained and "Every faction" or "Only those gained")
        page.only.tip = onlyGained and "Now: only factions you gained with since login. Click for every faction." or "Now: every faction. Click for only those you gained with since login."
        local rows = {}
        for _, f in ipairs(Factions()) do
            local gain = f.id and gained[f.id]
            if f.header then
                if not onlyGained then rows[#rows + 1] = { T.Paint(f.name, T.GOLD), "", "", "", "" } end
            elseif not onlyGained or (gain and gain ~= 0) then
                local progress = Progress(f) or "-"
                local eta = NextIn(f)
                rows[#rows + 1] = { "  " .. f.name, StandingText(f.reaction), progress, (gain and gain ~= 0) and Signed(gain) or "",
                    eta and ns.Duration(eta) or "" }
            end
        end
        page.list:SetRows(rows, onlyGained and "No reputation gained since login." or "The game lists no factions for this character yet.")
    end,
})
