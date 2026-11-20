local ADDON, ns = ...

-- Chat: plays a sound when someone says your name, paints it gold, and watches
-- for words you pick. Clickable web addresses are left to EllesmereUIChat.

local M = ns:NewModule("chat", {
    title = "Chat",
    desc = "Shows your name in gold where others write it, and plays a sound when someone says your character's name in group or guild chat.",
    defaults = { enabled = true, mention = true, highlight = true, words = {}, watchSound = true },
    options = {
        { type = "check", key = "mention", label = "Sound when your name is said in group or guild chat" },
        { type = "check", key = "highlight", label = "Your name in gold where others write it" },
        { type = "check", key = "watchSound", label = "A sound when a word you watch for comes up" },
        { type = "note", text = "/zod chat watch sfk adds a word to watch for in say, yell and the channels; /zod chat unwatch sfk drops it. /zod chat whispers and /zod chat mentions list the last ones.", lines = 3 },
    },
})

local LINKED = { "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_WHISPER", "CHAT_MSG_WHISPER_INFORM", "CHAT_MSG_PARTY",
    "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER", "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER", "CHAT_MSG_CHANNEL",
    "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_BN_WHISPER", "CHAT_MSG_BN_WHISPER_INFORM" }
local MENTION = { CHAT_MSG_PARTY = true, CHAT_MSG_PARTY_LEADER = true, CHAT_MSG_RAID = true, CHAT_MSG_RAID_LEADER = true,
    CHAT_MSG_GUILD = true, CHAT_MSG_OFFICER = true, CHAT_MSG_INSTANCE_CHAT = true }

local hooked, myName, lastSound, namePattern

-- A pattern that finds `name` as a whole word, in any mix of capitals.
local function Pattern(name)
    local p = name:gsub(".", function(c)
        if c:find("%a") then return "[" .. c:upper() .. c:lower() .. "]" end
        if c:find("%p") then return "%" .. c end
        return c
    end)
    return "%f[%w]" .. p .. "%f[%W]"
end

-- Paints the player's name in `msg`; returns the new text and how often it was found.
-- A message with links or colours in it is left alone, and so are web addresses.
function M.Highlight(msg, lower)
    if not namePattern or msg:find("|", 1, true) then return msg, 0 end
    -- Most lines do not have the name at all: a plain search says so before the word-by-word one.
    if not (lower or msg:lower()):find(myName, 1, true) then return msg, 0 end
    local found = 0
    local out = msg:gsub("%S+", function(word)
        if word:find("^https?://") or word:find("^www%.") then return nil end
        local new, n = word:gsub(namePattern, function(s) return "|cffffd100" .. s .. "|r" end)
        found = found + n
        return new
    end)
    return out, found
end

local WATCHED = { CHAT_MSG_SAY = true, CHAT_MSG_YELL = true, CHAT_MSG_CHANNEL = true }
local KEEP = 20

-- The first watched word in `msg`, or nil.
-- A watched word's patterns, made once: to find it, and to paint it in any mix of capitals.
local FIND, PAINT = {}, {}
local function FindPattern(word)
    local p = FIND[word]
    if not p then
        p = "%f[%w]" .. word:gsub("%p", "%%%0") .. "%f[%W]"
        FIND[word] = p
    end
    return p
end

local function Watched(msg)
    local lower = msg:lower()
    for _, word in ipairs(M.db.words) do
        if lower:find(word, 1, true) and lower:find(FindPattern(word)) then return word end
    end
end

-- Paints the watched words in `msg`.
local function Gold(s) return "|cffffd100" .. s .. "|r" end

local function PaintWords(msg, lower)
    if msg:find("|", 1, true) then return msg, 0 end
    lower = lower or msg:lower()
    local found = 0
    for _, word in ipairs(M.db.words) do
        if lower:find(word, 1, true) then
            local pattern = PAINT[word]
            if not pattern then
                pattern = "%f[%w]" .. word:gsub("%a", function(c) return "[" .. c:upper() .. c:lower() .. "]" end) .. "%f[%W]"
                PAINT[word] = pattern
            end
            local n
            msg, n = msg:gsub(pattern, Gold)
            found = found + n
        end
    end
    return msg, found
end

local function Mine(author)
    if type(author) ~= "string" or not myName or (issecretvalue and issecretvalue(author)) then return false end
    return (author:match("^[^%-]+") or ""):lower() == myName
end

local function Filter(_, event, msg, author, ...)
    if not M.enabled then return false end
    if issecretvalue and issecretvalue(msg) then return false end
    if type(msg) ~= "string" then return false end
    local lower = msg:lower()
    if M.db.mention and MENTION[event] and myName and lower:find(myName, 1, true) then
        local now = GetTime()
        if not lastSound or now - lastSound > 5 then
            lastSound = now
            if PlaySound then pcall(PlaySound, SOUNDKIT and SOUNDKIT.TELL_MESSAGE or 3081) end
        end
    end
    local changed = false
    if M.db.highlight and not event:find("INFORM", 1, true) and not Mine(author) then
        local new, found = M.Highlight(msg, lower)
        if found > 0 then msg, changed = new, true end
    end
    if WATCHED[event] and #M.db.words > 0 then
        local new, found = PaintWords(msg, lower)
        if found > 0 then msg, changed = new, true end
    end
    if changed then return false, msg, author, ... end
    return false
end

function M:OnEnable()
    myName = (ns.MyName() or ""):lower()
    if myName == "" then myName = nil end
    namePattern = myName and Pattern(ns.MyName()) or nil
    if hooked then return end
    hooked = true
    local add = (ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter) or ChatFrame_AddMessageEventFilter
    if not add then
        self.unsupported = true
        return
    end
    local timed = ns.Timed("chat filter", Filter)
    for _, event in ipairs(LINKED) do pcall(add, event, timed) end
end

-- What was said to you or about you, newest first, for /zod chat whispers and mentions.
local whispers, mentions = {}, {}
local awayWhispers = 0
local wasAway = false
local lastWatchSound

local function Keep(list, entry)
    table.insert(list, 1, entry)
    while #list > KEEP do table.remove(list) end
end

local function Plain(v)
    return type(v) == "string" and not (issecretvalue and issecretvalue(v))
end

local function Short(author)
    return (author:match("^[^%-]+") or author)
end

for _, event in ipairs({ "CHAT_MSG_WHISPER", "CHAT_MSG_BN_WHISPER" }) do
    M:On(event, function(_, _, msg, author)
        if not (Plain(msg) and Plain(author)) then return end
        Keep(whispers, { time(), Short(author), msg })
        if ns.IsAway() then awayWhispers = awayWhispers + 1 end
    end)
end

local NAMED = { CHAT_MSG_SAY = "say", CHAT_MSG_YELL = "yell", CHAT_MSG_PARTY = "party", CHAT_MSG_PARTY_LEADER = "party",
    CHAT_MSG_RAID = "raid", CHAT_MSG_RAID_LEADER = "raid", CHAT_MSG_GUILD = "guild", CHAT_MSG_OFFICER = "officer",
    CHAT_MSG_CHANNEL = "channel", CHAT_MSG_INSTANCE_CHAT = "instance" }
for event, where in pairs(NAMED) do
    M:On(event, function(self, _, msg, author)
        if not (Plain(msg) and Plain(author)) or Mine(author) then return end
        if namePattern and M.Highlight(msg) ~= msg then Keep(mentions, { time(), Short(author), msg, where }) end
        if WATCHED[event] and #self.db.words > 0 and self.db.watchSound and Watched(msg) then
            local now = GetTime()
            if not lastWatchSound or now - lastWatchSound > 10 then
                lastWatchSound = now
                if PlaySound then pcall(PlaySound, SOUNDKIT and SOUNDKIT.RAID_WARNING or 8959) end
            end
        end
    end)
end

-- Back from being away: say how many whispers came meanwhile.
M:On("PLAYER_FLAGS_CHANGED", function()
    local away = ns.IsAway()
    if wasAway and not away and awayWhispers > 0 then
        ns.Print(awayWhispers .. (awayWhispers == 1 and " whisper" or " whispers") .. " came while you were away. /zod chat whispers lists them.")
    end
    if not away then awayWhispers = 0 end
    wasAway = away
end)

local function List(list, empty, withWhere)
    if #list == 0 then
        ns.Print(empty)
        return
    end
    for i = math.min(10, #list), 1, -1 do
        local e = list[i]
        print("  |cff999999" .. date("%H:%M", e[1]) .. "|r  " .. e[2] .. (withWhere and (" |cff999999(" .. e[4] .. ")|r") or "") .. ": " .. e[3])
    end
end

-- /zod chat watch <word>, unwatch <word>, whispers, mentions
function M:Slash(arg)
    local word, rest = arg:match("^(%S*)%s*(.-)$")
    word, rest = word:lower(), rest:lower():gsub("^%s+", ""):gsub("%s+$", "")
    if word == "" then
        ns.Show("settings", "chat")
    elseif word == "watch" then
        if rest == "" then
            ns.Print(#self.db.words == 0 and "no words watched." or ("watching for: " .. table.concat(self.db.words, ", ") .. "."))
            return
        end
        for _, w in ipairs(self.db.words) do
            if w == rest then
                ns.Print("already watching for " .. rest .. ".")
                return
            end
        end
        table.insert(self.db.words, rest)
        ns.Print("watching for " .. rest .. " in say, yell and the channels.")
    elseif word == "unwatch" then
        for i = #self.db.words, 1, -1 do
            if self.db.words[i] == rest then
                table.remove(self.db.words, i)
                ns.Print("no longer watching for " .. rest .. ".")
                return
            end
        end
        ns.Print("not watching for " .. rest .. ".")
    elseif word == "whispers" then
        List(whispers, "no whispers since login.")
    elseif word == "mentions" then
        List(mentions, "nobody said your name since login.", true)
    else
        ns.Print("use /zod chat watch <word>, /zod chat unwatch <word>, /zod chat whispers or /zod chat mentions.")
    end
end
