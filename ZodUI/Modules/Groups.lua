local ADDON, ns = ...

-- Group match: a notice when someone in the public channels looks for more for a dungeon
-- at your level and asks for a role you play (or for no role in particular). The notice
-- names the dungeon and the one asking; their name in chat is a link to whisper them.
--
-- Keep my role: in a group, the game's role (right-click your portrait, Set Role) stays the one you play.
-- Deadly Boss Mods sets it from a guess at your spec, and on WoW Forever's classic talents it guesses wrong
-- (a Paladin with no points, or most in Holy, becomes a healer). When the role changes to another one, it
-- is put back a moment later; if something keeps changing it back, it gives up for a minute and says so.

local M = ns:NewModule("groups", {
    title = "Group match",
    desc = "A notice when a group in the public channels needs your role for a dungeon at your level. Their name in chat is a link to whisper them.",
    defaults = { enabled = true, tank = false, heal = false, dps = true, below = 2, solo = true, keep = "auto" },
    options = {
        { type = "check", key = "tank", label = "I tank" },
        { type = "check", key = "heal", label = "I heal" },
        { type = "check", key = "dps", label = "I deal damage" },
        { type = "step", key = "below", label = "Also dungeons this many levels above me", min = 0, max = 5, step = 1 },
        { type = "check", key = "solo", label = "Only while I am not in a group" },
        { type = "note", text = "A group that names no role counts for every role. /zod groups test shows a sample notice.", lines = 1 },
        { type = "cycle", key = "keep", label = "Keep my group role", choices = { { "auto", "The one role ticked above" },
            { "dps", "Damage" }, { "tank", "Tank" }, { "heal", "Healer" }, { "off", "Off: let other addons set it" } } },
    },
})

local SAME = 600 -- the same person and dungeon once in ten minutes
local GAP = 20 -- and at most one notice in this many seconds
local told, lastAt = {}, nil

local function Short(name)
    return type(name) == "string" and (name:match("^[^%-]+") or name) or "?"
end

local function PlayerLink(name)
    return "|Hplayer:" .. name .. "|h[" .. Short(name) .. "]|h"
end

-- The roles of the ad that are mine, as text, or nil when none is: "" for an ad naming no role.
function M:Roles(ad)
    local mine, named = {}, false
    for _, role in ipairs({ "tank", "heal", "dps" }) do
        if ad.roles[role] then
            named = true
            if self.db[role] then mine[#mine + 1] = role == "heal" and "healer" or role end
        end
    end
    if not named then return "" end
    return #mine > 0 and table.concat(mine, " or ") or nil
end

-- The dungeon of the ad that fits `level`, or nil.
function M:Fits(ad, level)
    for _, d in ipairs(ad.dungeons) do
        if level >= d.min - self.db.below and level <= d.max then return d end
    end
end

local function OnRoute(d)
    local status = type(UndeadRoute) == "table" and type(UndeadRoute.Status) == "function" and select(2, pcall(UndeadRoute.Status))
    return type(status) == "table" and type(status.stage) == "string" and status.stage:find((d.name:gsub("^The ", "")), 1, true) ~= nil
end

-- Whether a line asks for me; tells me when it does. Returns the notice text.
function M:Check(text, author)
    if type(author) ~= "string" or (issecretvalue and (issecretvalue(author) or issecretvalue(text))) then return nil end
    if Short(author) == (UnitName and ns.MyName()) then return nil end
    if self.db.solo and IsInGroup and IsInGroup() then return nil end
    local level = UnitLevel and ns.Level() or 1
    local ad = ns.Ads.Parse(text, level)
    if not (ad and ad.kind == "group" and ad.lf == "more") then return nil end
    local d = self:Fits(ad, level)
    if not d then return nil end
    local roles = self:Roles(ad)
    if not roles then return nil end
    local key, now = author .. ":" .. d.key, GetTime()
    if told[key] and now - told[key] < SAME then return nil end
    if lastAt and now - lastAt < GAP then return nil end
    told[key], lastAt = now, now
    local msg = Short(author) .. " looks for " .. (roles ~= "" and ("a " .. roles) or "more") .. " for " .. d.name
        .. (OnRoute(d) and " (on your route)" or "") .. "."
    ns.Alert(msg)
    print("  " .. PlayerLink(author) .. ": " .. text)
    return msg
end

M:On("CHAT_MSG_CHANNEL", function(self, _, text, author, _, _, _, _, zone)
    if type(zone) == "number" and zone == 0 then return end
    self:Check(text, author)
end)

local ROLE = { tank = "TANK", heal = "HEALER", dps = "DAMAGER" }
local ROLE_NAME = { TANK = "Tank", HEALER = "Healer", DAMAGER = "Damage", NONE = "none" }
local FIXES, WINDOW = 4, 60 -- at most this many put-backs in this many seconds
local fixes, since, said = 0, nil, false

-- The role to keep (the game's word for it), or nil: Off, or Auto with no single role ticked.
function M:WantedRole()
    local keep = self.db.keep or "auto"
    if keep == "auto" then
        local only
        for _, r in ipairs({ "tank", "heal", "dps" }) do
            if self.db[r] then
                if only then return nil end
                only = r
            end
        end
        return only and ROLE[only]
    end
    return ROLE[keep]
end

-- Puts your group role back when another addon (or a role check) changed it. Returns true when it did.
function M:KeepRole()
    local want = self:WantedRole()
    if not want or type(UnitSetRole) ~= "function" or not (IsInGroup and IsInGroup()) then return false end
    if InCombatLockdown and InCombatLockdown() then return false end -- after the fight (PLAYER_REGEN_ENABLED)
    local now = UnitGroupRolesAssigned and ns.Plain(UnitGroupRolesAssigned("player"))
    if now == nil or now == want then return false end
    local t = GetTime()
    if not since or t - since > WINDOW then since, fixes = t, 0 end
    if fixes >= FIXES then
        if fixes == FIXES then
            fixes = fixes + 1
            ns.Print("something keeps changing your group role to " .. (ROLE_NAME[now] or now)
                .. "; ZodUI leaves it for a minute. Keep my group role is under Settings, Group match.")
        end
        return false
    end
    fixes = fixes + 1
    if not pcall(UnitSetRole, "player", want) then return false end
    if not said then
        said = true
        ns.Print("your group role was set to " .. (ROLE_NAME[now] or now) .. " (another addon guessed it from your talents); "
            .. "it is " .. ROLE_NAME[want] .. " again. Settings, Group match, Keep my group role changes this.")
    end
    return true
end

-- A moment after the change, so the one who made it (DBM checks a few seconds after a talent change) is done.
local queued = false
local function Queue(self)
    if queued then return end
    queued = true
    ns.After(2, function() queued = false if self.enabled then self:KeepRole() end end)
end
M:On("PLAYER_ROLES_ASSIGNED", Queue)
M:On("GROUP_ROSTER_UPDATE", function(self)
    if not (IsInGroup and IsInGroup()) then said = false end -- a new group gets the line again
    Queue(self)
end)
M:On("PLAYER_REGEN_ENABLED", Queue)

function M.Forget() told, lastAt, fixes, since, said, queued = {}, nil, 0, nil, false, false end

function M:Slash(arg)
    if (arg or ""):lower():match("^%s*test") then
        local level = UnitLevel and ns.Level() or 20
        local pick
        for _, d in ipairs(ns.Ads.DUNGEONS) do
            if level >= d.min - self.db.below and level <= d.max then pick = d break end
        end
        pick = pick or ns.Ads.DUNGEONS[1]
        local role = (self.db.tank and "tank") or (self.db.heal and "heal") or "dps"
        local was = { told, lastAt, self.db.solo }
        told, lastAt, self.db.solo = {}, nil, false
        self:Check("LF1M " .. role .. " " .. pick.words[1]:upper() .. ", then we go", "Sample-Realm")
        told, lastAt, self.db.solo = was[1], was[2], was[3]
        return
    end
    ns.Print("use /zod groups test for a sample notice; the roles you play are under Settings.")
end
