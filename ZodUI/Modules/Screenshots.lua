local ADDON, ns = ...

-- Screenshots: takes one for the moments worth keeping.

local M = ns:NewModule("shots", {
    title = "Screenshots",
    desc = "Takes a screenshot when you loot something purple or better, when you come to a zone for the first time, and when you reach a new standing with a faction.",
    defaults = { enabled = false, loot = true, zone = true, standing = true },
    options = {
        { type = "check", key = "loot", label = "When you loot something purple or better" },
        { type = "check", key = "zone", label = "When you come to a zone for the first time" },
        { type = "check", key = "standing", label = "When you reach a new standing with a faction" },
        { type = "note", text = "A screenshot when you level up is under Settings > Session & XP.", lines = 1 },
    },
})

local DELAY = 1 -- seconds, so the moment is on screen
local EPIC = { ff8000 = true, a335ee = true, e6cc80 = true }
local reactions = {}
local zonesSeen

local function Shoot(why)
    if not Screenshot then return end
    ns.After(DELAY, function()
        Screenshot()
        ns.Print("screenshot: " .. why .. ".")
    end)
end

M:On("CHAT_MSG_LOOT", function(self, _, msg, _, _, _, who)
    if not self.db.loot or type(msg) ~= "string" or (issecretvalue and issecretvalue(msg)) then return end
    if type(who) == "string" and who ~= "" and who ~= ns.MyName() and not who:find("^" .. (ns.MyName() or "") .. "%-") then return end
    local hex, name = msg:match("|cff(%x%x%x%x%x%x)|Hitem:.-|h%[(.-)%]|h")
    if hex and EPIC[hex:lower()] then Shoot(name) end
end)

M:On("ZONE_CHANGED_NEW_AREA", function(self)
    local zone = GetRealZoneText and GetRealZoneText() or ""
    if zone == "" then return end
    ns.chardb.shotZones = ns.chardb.shotZones or {}
    local seen = ns.chardb.shotZones
    if not seen[zone] then
        seen[zone] = true
        if self.db.zone and zonesSeen then Shoot(zone) end
    end
    zonesSeen = true
end)

M:On("UPDATE_FACTION", function(self)
    if not (C_Reputation and C_Reputation.GetNumFactions and C_Reputation.GetFactionDataByIndex) then return end
    for i = 1, C_Reputation.GetNumFactions() or 0 do
        local d = C_Reputation.GetFactionDataByIndex(i)
        if d and d.factionID and d.reaction and not d.isHeader then
            local was = reactions[d.factionID]
            if was and d.reaction > was and self.db.standing then Shoot(d.name .. " " .. (_G["FACTION_STANDING_LABEL" .. d.reaction] or "")) end
            reactions[d.factionID] = d.reaction
        end
    end
end)

function M:OnEnable()
    ns.chardb.shotZones = ns.chardb.shotZones or {}
    local zone = GetRealZoneText and GetRealZoneText() or ""
    if zone ~= "" then ns.chardb.shotZones[zone] = true end -- where you log in is not a first visit
    zonesSeen = true
    if C_Reputation and C_Reputation.GetNumFactions and C_Reputation.GetFactionDataByIndex then
        for i = 1, C_Reputation.GetNumFactions() or 0 do
            local d = C_Reputation.GetFactionDataByIndex(i)
            if d and d.factionID and d.reaction then reactions[d.factionID] = d.reaction end
        end
    end
end
