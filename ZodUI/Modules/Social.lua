local ADDON, ns = ...

-- Social: answers the requests you always answer the same way.

local M = ns:NewModule("social", {
    title = "Invites and duels",
    desc = "Declines duel requests, joins groups straight away when the invite comes from a friend or a guild member, and can take resurrections and summons, decline guild invites and charters, and release in battlegrounds.",
    defaults = { enabled = false, duels = true, invites = true, res = false, summon = false, guild = false, charter = false, release = false },
    conflicts = { "NaowhForever_QoL" },
    options = {
        { type = "check", key = "duels", label = "Decline duel requests" },
        { type = "check", key = "invites", label = "Accept group invites from friends and guild members" },
        { type = "check", key = "res", label = "Take a resurrection when the one casting it is out of combat" },
        { type = "check", key = "summon", label = "Take a summons from someone in your group" },
        { type = "check", key = "guild", label = "Decline guild invites" },
        { type = "check", key = "charter", label = "Close charters someone asks you to sign" },
        { type = "check", key = "release", label = "Release your spirit at once in a battleground" },
    },
})

M:On("DUEL_REQUESTED", function(self, _, name)
    if not self.db.duels or not CancelDuel then return end
    CancelDuel()
    if StaticPopup_Hide then StaticPopup_Hide("DUEL_REQUESTED") end
    ns.Print("declined a duel" .. (type(name) == "string" and (" from " .. name) or "") .. ".")
end)

local function Known(guid)
    if not guid then return false end
    if C_FriendList and C_FriendList.IsFriend and C_FriendList.IsFriend(guid) then return true end
    if IsGuildMember and IsGuildMember(guid) then return true end
    if C_BattleNet and C_BattleNet.GetAccountInfoByGUID and C_BattleNet.GetAccountInfoByGUID(guid) then return true end
    return false
end

M:On("PARTY_INVITE_REQUEST", function(self, _, name, _, _, _, _, _, guid)
    if not self.db.invites or not AcceptGroup then return end
    if (issecretvalue and issecretvalue(guid)) or not Known(guid) then return end
    AcceptGroup()
    if StaticPopup_Hide then StaticPopup_Hide("PARTY_INVITE") end
    ns.Print("joined " .. (type(name) == "string" and name or "a friend") .. "'s group.")
end)

local function Fine(name)
    return type(name) == "string" and name ~= "" and not (issecretvalue and issecretvalue(name))
end

M:On("RESURRECT_REQUEST", function(self, _, name)
    if not self.db.res or not AcceptResurrect or not Fine(name) then return end
    if UnitAffectingCombat and UnitAffectingCombat(name) then return end -- still fighting: you may want to wait
    AcceptResurrect()
    if StaticPopup_Hide then
        for _, which in ipairs({ "RESURRECT", "RESURRECT_NO_SICKNESS", "RESURRECT_NO_TIMER" }) do StaticPopup_Hide(which) end
    end
    ns.Print("took the resurrection from " .. name .. ".")
end)

local function Summoner()
    if C_SummonInfo and C_SummonInfo.GetSummonConfirmSummoner then return C_SummonInfo.GetSummonConfirmSummoner() end
    if GetSummonConfirmSummoner then return GetSummonConfirmSummoner() end
end

local function InGroup(name)
    return (UnitInParty and UnitInParty(name)) or (UnitInRaid and ns.Plain(UnitInRaid(name))) or false
end

M:On("CONFIRM_SUMMON", function(self)
    if not self.db.summon then return end
    local confirm = (C_SummonInfo and C_SummonInfo.ConfirmSummon) or ConfirmSummon
    if not confirm or (InCombatLockdown and InCombatLockdown()) then return end
    local who = Summoner()
    if not Fine(who) or not InGroup(who) then return end
    confirm()
    if StaticPopup_Hide then StaticPopup_Hide("CONFIRM_SUMMON") end
    ns.Print("took the summons from " .. who .. ".")
end)

M:On("GUILD_INVITE_REQUEST", function(self, _, name, guild)
    if not self.db.guild or not DeclineGuild then return end
    DeclineGuild()
    if StaticPopup_Hide then StaticPopup_Hide("GUILD_INVITE") end
    ns.Print("declined a guild invite" .. (Fine(guild) and (" to " .. guild) or "") .. (Fine(name) and (" from " .. name) or "") .. ".")
end)

M:On("PETITION_SHOW", function(self)
    if not self.db.charter or not ClosePetition then return end
    ClosePetition()
    ns.Print("closed a charter you were asked to sign.")
end)

-- A way to get up where you died you can use now: a soulstone, Reincarnation, an ankh. WoW Forever has no
-- HasSoulstone global; C_DeathInfo lists these options. A hidden (secret) canUse counts as usable: better to wait.
local function CanSelfRes()
    local options = C_DeathInfo and C_DeathInfo.GetSelfResurrectOptions and C_DeathInfo.GetSelfResurrectOptions()
    if type(options) ~= "table" then return false end
    for _, option in ipairs(options) do
        local can = option.canUse
        if (issecretvalue and issecretvalue(can)) or can then return true end
    end
    return false
end

M:On("PLAYER_DEAD", function(self)
    if not self.db.release or not RepopMe or not IsInInstance then return end
    local _, kind = IsInInstance()
    if kind ~= "pvp" then return end
    if CanSelfRes() then return end -- a soulstone is worth waiting for
    ns.After(0.5, RepopMe)
end)
