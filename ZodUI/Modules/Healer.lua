local ADDON, ns = ...

-- Healer mode: many level as damage and heal in groups. Joining a group as its healer puts on
-- your healing set, and leaving the group puts back what you wore before. The sets are the
-- game's own equipment sets (the character sheet's, the ones Naowh's Gear Sets bar shows), so
-- nothing about gear is kept here but a set's name. Gear cannot change in combat, so a swap
-- asked for then waits for the fight to end.
--
-- "The group marks me healer" is the role the group gives you (UnitGroupRolesAssigned). Most
-- groups set none; then a healing set you have named gets a one-line hint instead, and
-- /zod heal swaps by hand. The state is kept per character (ZodUICharDB.healer), so logging
-- out while healing still puts your own gear back at the next login outside a group.

local M = ns:NewModule("healer", {
    title = "Healer mode",
    desc = "Joining a group as its healer puts on your healing equipment set, and leaving the group puts back what you wore. /zod healer set <name> names the set; /zod heal swaps by hand.",
    defaults = { enabled = true, when = "role", swap = true },
    options = {
        { type = "cycle", key = "when", label = "I heal", choices = { { "role", "When the group marks me healer" }, { "always", "In every group" } } },
        { type = "check", key = "swap", label = "Swap the gear myself (off: only remind me)" },
        { type = "note", text = "Name your healing set with /zod healer set <name> or on the Commands page. Without a set to go back to, the set you wore before comes back.", lines = 2 },
    },
})

local HINT_WAIT = 5
local pending -- a set's name to put on when combat ends
local hinted -- the hint is said once per group

local function State()
    ns.chardb.healer = ns.chardb.healer or {}
    return ns.chardb.healer
end

-- Your equipment sets: list of { id, name, equipped }, by name.
function M.Sets()
    local api, out = C_EquipmentSet, {}
    if not (api and api.GetEquipmentSetIDs and api.GetEquipmentSetInfo) then return out end
    for _, id in ipairs(api.GetEquipmentSetIDs() or {}) do
        local name, _, setID, equipped = api.GetEquipmentSetInfo(id)
        if type(name) == "string" then out[#out + 1] = { id = setID or id, name = name, equipped = equipped == true } end
    end
    table.sort(out, function(a, b) return a.name < b.name end)
    return out
end

-- The set called `name` (any case), or nil.
function M.Find(name)
    if type(name) ~= "string" or name == "" then return nil end
    local lower = name:lower()
    for _, s in ipairs(M.Sets()) do
        if s.name:lower() == lower then return s end
    end
end

-- The name of the set you wear now, or nil.
function M.Worn()
    for _, s in ipairs(M.Sets()) do
        if s.equipped then return s.name end
    end
end

local function Names()
    local names = {}
    for _, s in ipairs(M.Sets()) do names[#names + 1] = s.name end
    return #names > 0 and table.concat(names, ", ") or "none yet (make them on the character sheet)"
end

-- Puts on the set called `name`, now or when combat ends. False when there is no such set.
function M:Wear(name)
    local s = M.Find(name)
    if not s then return false end
    if InCombatLockdown and InCombatLockdown() then
        pending = s.name
        ns.Print(s.name .. " goes on when combat ends.")
        return true
    end
    pending = nil
    if not s.equipped then C_EquipmentSet.UseEquipmentSet(s.id) end
    return true
end

M:On("PLAYER_REGEN_ENABLED", function(self)
    if pending then
        local name = pending
        pending = nil
        self:Wear(name)
    end
end)

-- A line when your talents are set for another role than healing and a healing spec exists;
-- nil when the client has no specs (classic talents) or you already heal.
function M.SpecHint()
    local S = C_SpecializationInfo
    if not (S and S.GetSpecialization and S.GetSpecializationInfo) then return nil end
    local ok, line = pcall(function()
        local cur = S.GetSpecialization()
        local curRole = cur and select(5, S.GetSpecializationInfo(cur))
        if curRole == "HEALER" then return nil end
        for i = 1, 4 do
            local id, name, _, _, role = S.GetSpecializationInfo(i)
            if not id then break end
            if role == "HEALER" then return "Your talents are not set for healing; " .. name .. " is your healing spec." end
        end
    end)
    return ok and line or nil
end

-- Whether you heal in the group you are in now.
function M:Heals()
    if not (IsInGroup and IsInGroup()) then return false end
    if self.db.when == "always" then return true end
    return UnitGroupRolesAssigned ~= nil and ns.Plain(UnitGroupRolesAssigned("player")) == "HEALER"
end

function M:Start(hand)
    local st = State()
    st.on, st.hand = true, hand or nil
    local set = M.Find(st.set)
    if not set then
        ns.Alert("You heal in this group. " .. ((st.set or "") ~= "" and ("There is no equipment set called " .. st.set .. ".")
            or "Name your healing set with /zod healer set <name> to have it put on."))
        return false
    end
    local worn = M.Worn()
    if worn ~= set.name then st.before = worn end
    st.wore = true
    if self.db.swap or hand then
        self:Wear(set.name)
        ns.Alert("Healer mode: you heal in this group, " .. set.name .. " goes on.")
    else
        ns.Alert("You heal in this group: put on " .. set.name .. ".")
    end
    local spec = M.SpecHint()
    if spec then print("  " .. spec) end
    return true
end

function M:Stop(hand)
    local st = State()
    local wore = st.wore
    local back = M.Find(st.back) or M.Find(st.before)
    st.on, st.hand, st.wore, st.before = false, nil, nil, nil
    if not wore then return end
    if not back then
        ns.Print("healer mode over: put your own gear back on.")
    elseif self.db.swap or hand then
        self:Wear(back.name)
        ns.Print("healer mode over, " .. back.name .. " goes back on.")
    else
        ns.Print("healer mode over: put " .. back.name .. " back on.")
    end
end

-- In a group with no role, a set you named: say once how to swap by hand.
local function Hint(self)
    local st = State()
    if hinted or st.on or self.db.when ~= "role" or not (IsInGroup and IsInGroup()) then return end
    local set = M.Find(st.set)
    if not set or (UnitGroupRolesAssigned and (ns.Plain(UnitGroupRolesAssigned("player")) or "NONE") ~= "NONE") then return end
    hinted = true
    ns.Print("you have no role in this group. If you heal, /zod heal puts on " .. set.name .. ".")
end

function M:Update()
    local st = State()
    local grouped = IsInGroup and IsInGroup()
    if not grouped then hinted = nil end
    local heals = self:Heals()
    if heals and not st.on then
        self:Start()
    elseif st.on and not heals and not (grouped and st.hand) then
        self:Stop()
    elseif grouped and not st.on and not hinted then
        ns.After(HINT_WAIT, function() if self.enabled then Hint(self) end end)
    end
end

M:On("GROUP_ROSTER_UPDATE", function(self) self:Update() end)
M:On("PLAYER_ROLES_ASSIGNED", function(self) self:Update() end)
M:On("PLAYER_ENTERING_WORLD", function(self)
    ns.After(3, function() if self.enabled then self:Update() end end)
end)

function M.Forget() pending, hinted = nil, nil end

function M:Heal()
    if not (IsInGroup and IsInGroup()) then ns.Print("you are not in a group.") return false end
    return self:Start(true)
end

function M:Slash(arg)
    local word, rest = (arg or ""):match("^%s*(%S*)%s*(.-)%s*$")
    word = word:lower()
    local st = State()
    if word == "set" or word == "back" then
        if word == "back" and (rest:lower() == "none" or rest == "") then
            st.back = nil
            ns.Print("leaving healer mode puts back the set you wore before.")
            return
        end
        local s = M.Find(rest)
        if not s then ns.Print("no equipment set called '" .. rest .. "'. Your sets: " .. Names() .. ".") return end
        st[word] = s.name
        ns.Print(word == "set" and ("your healing set is " .. s.name .. ".") or ("leaving healer mode puts on " .. s.name .. "."))
        ns.Refresh()
    elseif word == "heal" then
        self:Heal()
    elseif word == "solo" or word == "done" then
        if not st.on then ns.Print("you are not in healer mode.") return end
        self:Stop(true)
    else
        ns.Print("healing set: " .. ((st.set or "") ~= "" and st.set or "none, /zod healer set <name>")
            .. "; afterwards: " .. ((st.back or "") ~= "" and st.back or "the set you wore before")
            .. (st.on and "; healing now." or "."))
        print("  Your sets: " .. Names() .. ".")
    end
end

function M:Card()
    local st = State()
    if (st.set or "") == "" then return nil end
    return { title = "Healer mode", lines = { { "Healing set", st.set }, { "Now", st.on and "healing" or "not healing" } } }
end

-- /zod heal, shorter than /zod healer heal.
ns.pluginCommands = ns.pluginCommands or {}
ns.pluginCommands.heal = function() if M.enabled then M:Heal() else ns.Print("Healer mode is off. /zod healer on switches it on.") end end
