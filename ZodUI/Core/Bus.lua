local ADDON, ns = ...

-- The guild network: ZodUI talking to ZodUI in your guild, over addon messages. A message is
-- "1~K~field~field...": the protocol version, a kind (one letter) and up to MOST_FIELDS fields. Broadcasts and
-- questions go to the guild channel, so the server vouches that the sender is in your guild; answers come back as
-- whispers, and a module only takes an answer to a question it asked. What comes in is data, never code: each
-- listener checks every field before it keeps or shows anything.
--
-- Sending is held to what the game allows (a burst of BURST, then one per EVERY seconds), and waits out combat and
-- the chat lockdown in instances. Nothing is sent or heard while the Guild network module is off.

local PREFIX = "ZodUI"
local VERSION = "1"
local MOST_FIELDS = 10
local FIELD_MOST = 80       -- characters in one field
local MOST_HEARD = 30       -- messages taken from one sender a minute
local BURST, EVERY = 4, 1.2 -- under the game's throttle per prefix
local QUEUE_MOST = 30
local TRIES = 3

local Bus = { PREFIX = PREFIX }
ns.Bus = Bus

local listeners = {} -- kind -> { fn, mod }
local queue = {}     -- { text, to, tries }
local tokens = BURST
local heard = {}     -- sender -> { n, from }

if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then C_ChatInfo.RegisterAddonMessagePrefix(PREFIX) end

local function Plain(v)
    if issecretvalue and issecretvalue(v) then return nil end
    return v
end

-- Whether the network may talk: the module is on, you are in a guild and the client can send.
function Bus.On()
    local m = ns.modules.guild
    return (m and m.enabled and IsInGuild and IsInGuild() and C_ChatInfo and C_ChatInfo.SendAddonMessage) and true or false
end

-- Whether it may talk to your group: the module is on, you are in a group and the client can send.
function Bus.PartyOn()
    local m = ns.modules.guild
    return (m and m.enabled and IsInGroup and IsInGroup() and C_ChatInfo and C_ChatInfo.SendAddonMessage) and true or false
end

local function May(m)
    if m.to == "PARTY" then return Bus.PartyOn() end
    return Bus.On()
end

-- A field as it may travel: no separators, colour or link codes, at most FIELD_MOST characters.
function Bus.Clean(v)
    return (tostring(v == nil and "" or v):gsub("[%c|~]", ""):sub(1, FIELD_MOST))
end

-- fn(sender, fields, channel, fullSender) for messages of `kind`, while `mod` (if given) is on.
function Bus.Listen(kind, fn, mod)
    listeners[kind] = { fn = fn, mod = mod }
end

local function Held()
    if InCombatLockdown and InCombatLockdown() then return true end
    if C_ChatInfo and C_ChatInfo.InChatMessagingLockdown and Plain(C_ChatInfo.InChatMessagingLockdown()) then return true end
    return false
end

local function Sent(result)
    return result == nil or result == true or result == 0
end

function Bus.Flush()
    if Held() then return end
    while tokens >= 1 and queue[1] do
        local m = queue[1]
        if not May(m) then
            table.remove(queue, 1) -- left the guild or the group since: dropped
        else
        tokens = tokens - 1
        local channel = (m.to == "PARTY" and "PARTY") or (m.to and "WHISPER") or "GUILD"
        local ok = Sent(C_ChatInfo.SendAddonMessage(PREFIX, m.text, channel, m.to ~= "PARTY" and m.to or nil))
        if ok then
            table.remove(queue, 1)
        else
            m.tries = m.tries + 1
            if m.tries >= TRIES then table.remove(queue, 1) end
            return -- throttled: the next tick tries again
        end
        end
    end
end

-- Sends a message of `kind` to the guild, to your group (`to` "PARTY"), or as a whisper to `to` (a full
-- name). Returns whether it was queued.
function Bus.Send(kind, fields, to)
    if not May({ to = to }) then return false end
    local parts = { VERSION, kind }
    for i = 1, math.min(#(fields or {}), MOST_FIELDS) do parts[#parts + 1] = Bus.Clean(fields[i]) end
    local text = table.concat(parts, "~")
    if #text > 255 then return false end
    queue[#queue + 1] = { text = text, to = to, tries = 0 }
    while #queue > QUEUE_MOST do table.remove(queue, 1) end
    Bus.Flush()
    return true
end

ns.Every(EVERY, function()
    tokens = math.min(BURST, tokens + 1)
    if queue[1] then Bus.Flush() end
end)
ns.On("PLAYER_REGEN_ENABLED", function() Bus.Flush() end)

-- A question's id, unique enough among the few open at once.
local asked = 0
function Bus.NewID()
    asked = asked + 1
    return tostring((time() % 100000) * 100 + asked % 100)
end

local function Split(text)
    local fields = {}
    for f in (text .. "~"):gmatch("(.-)~") do
        fields[#fields + 1] = f
        if #fields > MOST_FIELDS + 2 then break end
    end
    return fields
end

function Bus.Receive(prefix, text, channel, sender)
    if prefix ~= PREFIX then return end
    if channel == "PARTY" or channel == "RAID" then
        if not Bus.PartyOn() then return end
    elseif channel ~= "GUILD" and channel ~= "WHISPER" then
        return
    elseif not (Bus.On() or (channel == "WHISPER" and Bus.PartyOn())) then
        return
    end
    if Plain(text) == nil or Plain(sender) == nil or type(text) ~= "string" or type(sender) ~= "string" then return end
    local short = Ambiguate and Ambiguate(sender, "none") or sender:match("^([^-]+)") or sender
    if short == ns.MyName() then return end
    local now = GetTime and GetTime() or 0
    local h = heard[sender]
    if not h or now - h.from >= 60 then
        h = { n = 0, from = now }
        heard[sender] = h
    end
    h.n = h.n + 1
    if h.n > MOST_HEARD then return end
    local fields = Split(text)
    if fields[1] ~= VERSION or type(fields[2]) ~= "string" then return end
    local l = listeners[fields[2]]
    if not l or (l.mod and not l.mod.enabled) then return end
    local rest = {}
    for i = 3, math.min(#fields, MOST_FIELDS + 2) do rest[#rest + 1] = fields[i] end
    ns.Guard("network " .. fields[2], l.fn, short, rest, channel, sender)
end

ns.On("CHAT_MSG_ADDON", function(_, _, prefix, text, channel, sender) Bus.Receive(prefix, text, channel, sender) end)

-- For tests: what is waiting to be sent.
function Bus.Queued() return #queue end
