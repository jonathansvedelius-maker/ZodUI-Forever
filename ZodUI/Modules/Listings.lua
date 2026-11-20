local ADDON, ns = ...

-- Group listings: the Group Finder shows only groups on your own layer, so at 60 its lists
-- look empty. A custom chat channel is realm-wide, across layers (NaowhForever_QoL's layer
-- swaps use one the same way), so ZodUI players list their group, or themselves, on a hidden
-- channel, and everyone else running ZodUI sees it on the Chat board and in Group match, on
-- every layer. Joining their group moves you to their layer.
--
-- Classic does not carry addon messages on custom channels, so a listing is a plain chat
-- line ("ZG1 sfk m th 24 3") that the chat windows never show. Sending to a channel needs a
-- key press or a click, so a listing is posted only from /zod lfg or its button, never by a
-- timer: it lasts 15 minutes and is renewed by posting again. What comes in is checked field
-- by field; the text shown is built here, never taken from the line.

local M = ns:NewModule("listings", {
    title = "Group listings",
    desc = "List your group, or yourself, for a dungeon on every layer: other ZodUI players see it on the Chat board and in Group match. /zod lfg sfk tank heal, /zod lfg stop.",
    defaults = { enabled = true },
    options = {
        { type = "note", text = "Joins a hidden chat channel (ZodUIGroups) a few seconds after login; turning this off leaves it. Only ZodUI players see the listings.", lines = 2 },
    },
})

M.CHANNEL = "ZodUIGroups"
local TAG = "ZG1"
local FRESH = 15 * 60
local GAP = 30
local JOIN_AFTER = 10
local ROLES = { { "t", "tank" }, { "h", "heal" }, { "d", "dps" } }
local ROLE_WORDS = { tank = "t", tanks = "t", heal = "h", heals = "h", healer = "h", dps = "d", dd = "d" }

local lastPost, mine, hooked, toldFull
local BY_KEY = {}
for _, d in ipairs(ns.Ads.DUNGEONS) do BY_KEY[d.key] = d end

function M.Channel()
    local id = GetChannelName and GetChannelName(M.CHANNEL)
    if type(id) == "number" and id > 0 then return id end
end

local function Join()
    if M.enabled and not M.Channel() and JoinTemporaryChannel then JoinTemporaryChannel(M.CHANNEL) end
end

local function Ours(name)
    return type(name) == "string" and not (issecretvalue and issecretvalue(name)) and name:lower():find(M.CHANNEL:lower(), 1, true) ~= nil
end

-- Our channel's lines never show in a chat window.
local function Filter(_, _, _, _, _, channelString, _, _, _, _, baseName)
    return Ours(baseName) or Ours(channelString)
end
M.Filter = Filter

function M:OnEnable()
    ns.After(JOIN_AFTER, Join)
    if hooked then return end
    local add = (ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter) or ChatFrame_AddMessageEventFilter
    if add then
        hooked = true
        pcall(add, "CHAT_MSG_CHANNEL", ns.Timed("listings filter", function(...) if M.enabled then return Filter(...) end return false end))
    end
end

function M:OnDisable()
    if M.Channel() and LeaveChannelByName then LeaveChannelByName(M.CHANNEL) end
end

-- The dungeon named by `text` (its key, a word or its name), or nil.
function M.Dungeon(text)
    local lower = (text or ""):lower()
    if lower == "" then return nil end
    for _, d in ipairs(ns.Ads.DUNGEONS) do
        if d.key == lower or d.name:lower() == lower or d.name:lower():gsub("^the ", "") == lower then return d end
        for _, w in ipairs(d.words) do
            if w == lower then return d end
        end
    end
end

function M.Encode(key, want, roles, level, size)
    return table.concat({ TAG, key, want, roles ~= "" and roles or "-", tostring(level), tostring(size) }, " ")
end

-- A line from the channel: { stop = true }, or { dungeon, want = "m"|"g", roles = "th", level, size }; nil when it is not one.
function M.Decode(text)
    if type(text) ~= "string" or (issecretvalue and issecretvalue(text)) or #text > 60 then return nil end
    if text == TAG .. " stop" then return { stop = true } end
    local key, want, roles, level, size = text:match("^" .. TAG .. " (%l+) ([mg]) ([thd%-]+) (%d+) (%d+)$")
    local d = key and BY_KEY[key]
    level, size = tonumber(level), tonumber(size)
    if not (d and level and size and level >= 1 and level <= 80 and size >= 1 and size <= 40 and #roles <= 3) then return nil end
    return { dungeon = d, want = want, roles = roles == "-" and "" or roles, level = level, size = size }
end

local function RoleNames(letters)
    local names = {}
    for _, r in ipairs(ROLES) do
        if letters:find(r[1], 1, true) then names[#names + 1] = r[2] end
    end
    return names
end

-- The line Chat board and Group match read, made from the checked fields.
function M.Text(l)
    local d, names = l.dungeon, RoleNames(l.roles)
    if l.want == "m" then
        return "LFM " .. d.name .. " (" .. d.words[1] .. ")" .. (#names > 0 and (" need " .. table.concat(names, " ")) or "")
            .. ", " .. l.size .. (l.size <= 5 and "/5" or "") .. ", level " .. l.level .. " [ZodUI, any layer]"
    end
    return "LFG " .. d.name .. " (" .. d.words[1] .. ")" .. (#names > 0 and (" as " .. table.concat(names, " ")) or "")
        .. ", level " .. l.level .. " [ZodUI, any layer]"
end

function M:Take(text, author)
    if type(author) ~= "string" or (issecretvalue and issecretvalue(author)) then return nil end
    local l = M.Decode(text)
    if not l then return nil end
    local board = ns.modules.board
    if board and board.Drop then board:Drop(author) end
    if l.stop then ns.Refresh() return l end
    local line = M.Text(l)
    if board and board.enabled then
        local ad = board:Add(line, author)
        if ad then ad.net = true end
    end
    local groups = ns.modules.groups
    if groups and groups.enabled and l.want == "m" then groups:Check(line, author) end
    ns.Refresh()
    return l
end

M:On("CHAT_MSG_CHANNEL", function(self, _, text, author, _, channelString, _, _, _, _, baseName)
    if Ours(baseName) or Ours(channelString) then self:Take(text, author) end
end)

-- Your listings and others' still fresh, from the Chat board.
function M:List()
    local board, out = ns.modules.board, {}
    if not (board and board.List) then return out end
    for _, ad in ipairs(board:List("group")) do
        if ad.net and time() - ad.at <= FRESH then out[#out + 1] = ad end
    end
    return out
end

local function Send(text)
    local id = M.Channel()
    local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
    send(text, "CHANNEL", nil, id)
end

local function Ready()
    if not M.Channel() then
        Join()
        ns.Print("joining the group channel; try again in a moment.")
        return false
    end
    if C_ChatInfo and C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown() then
        ns.Print("chat is locked right now, so nothing was listed.")
        return false
    end
    return true
end

-- Lists you: your group needing `roles` (letters), or you wanting a group as `roles`.
function M:Post(d, roles)
    if not Ready() then return false end
    if lastPost and GetTime() - lastPost < GAP then
        ns.Print("you listed a moment ago; wait half a minute.")
        return false
    end
    local grouped = IsInGroup and IsInGroup()
    local want = grouped and "m" or "g"
    if not grouped and roles == "" then
        local g = ns.modules.groups
        for _, r in ipairs(ROLES) do
            if g and g.db[r[2]] then roles = roles .. r[1] end
        end
    end
    local level = UnitLevel and ns.Level() or 1
    local size = grouped and (GetNumGroupMembers and GetNumGroupMembers() or 1) or 1
    Send(M.Encode(d.key, want, roles, level, size))
    lastPost, mine, toldFull = GetTime(), d.key, nil
    local names = RoleNames(roles)
    local what
    if want == "m" then
        what = "listed your group for " .. d.name .. (#names > 0 and (", needing " .. table.concat(names, " and ")) or "")
    else
        what = "listed you for " .. d.name .. (#names > 0 and (" as " .. table.concat(names, " or ")) or "")
    end
    ns.Print(what .. " on every layer for 15 minutes. /zod lfg stop takes it down.")
    return true
end

function M:Stop()
    if not mine then ns.Print("you have nothing listed.") return false end
    if not Ready() then return false end
    Send(TAG .. " stop")
    mine = nil
    ns.Print("your listing is taken down.")
    return true
end

M:On("GROUP_ROSTER_UPDATE", function(self)
    if mine and not toldFull and lastPost and GetTime() - lastPost < FRESH and GetNumGroupMembers and GetNumGroupMembers() >= 5
        and not (IsInRaid and IsInRaid()) then
        toldFull = true
        ns.Print("your group is full: /zod lfg stop takes your listing down.")
    end
end)

function M.Forget() lastPost, mine, toldFull = nil, nil, nil end

local function Show()
    local list = M:List()
    if #list == 0 then
        ns.Print("no group listings from ZodUI players right now. /zod lfg sfk tank heal lists yours.")
        return
    end
    ns.Print("group listings, every layer:")
    for i = 1, math.min(10, #list) do
        local ad = list[i]
        print("  |Hplayer:" .. ad.author .. "|h[" .. (ad.author:match("^[^%-]+") or ad.author) .. "]|h: " .. ad.text:gsub(" %[ZodUI, any layer%]$", ""))
    end
end

function M:Slash(arg)
    local text = (arg or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if text == "" then Show() return end
    if text:lower() == "stop" then self:Stop() return end
    local roles, rest = "", {}
    for word in text:gmatch("%S+") do
        local r = ROLE_WORDS[word:lower()]
        if r then
            if not roles:find(r, 1, true) then roles = roles .. r end
        else
            rest[#rest + 1] = word
        end
    end
    local d = M.Dungeon(table.concat(rest, " "))
    if not d then
        ns.Print("no dungeon called '" .. table.concat(rest, " ") .. "'. Try /zod lfg sfk tank heal.")
        return
    end
    local order = ""
    for _, r in ipairs(ROLES) do
        if roles:find(r[1], 1, true) then order = order .. r[1] end
    end
    self:Post(d, order)
end

-- /zod lfg, shorter than /zod listings.
ns.pluginCommands = ns.pluginCommands or {}
ns.pluginCommands.lfg = function(arg) if M.enabled then M:Slash(arg) else ns.Print("Group listings is off. /zod listings on switches it on.") end end
