local ADDON, ns = ...
local T = ns.T

-- Loot rolls: ZodUI's own roll window in place of the game's Need / Greed boxes.
-- Every open roll is a card in one stack: the item, how long is left, your
-- buttons, and as the rolls come in, who picked what and rolled what, names in
-- their class colours. The winner stays on the card for a few seconds, and every
-- roll is kept on the Rolls page.
--
-- The game says who rolled what only in chat (CHAT_MSG_LOOT), so those lines are
-- read with the game's own message formats (LOOT_ROLL_*), whatever the language.

local M = ns:NewModule("rolls", {
    title = "Loot rolls",
    desc = "Replaces the game's Need / Greed boxes with one stack of cards: every open roll, a timer, your buttons, "
        .. "and everyone's pick and roll in their class colours. The winner stays for a moment, and the Rolls page keeps them all. "
        .. "/zod rolls test shows it; /zod unlock moves it.",
    conflicts = { "HolyRollForever" },
    defaults = { enabled = true, replace = true, hold = 5, everyone = true, sound = true, say = false, minQuality = 0 },
    options = {
        { type = "check", key = "replace", label = "Hide the game's own roll boxes" },
        { type = "check", key = "everyone", label = "List every player's pick and roll on the card" },
        { type = "cycle", key = "hold", label = "Show the winner for", choices = { { 3, "3 seconds" }, { 5, "5 seconds" },
            { 10, "10 seconds" }, { 20, "20 seconds" } } },
        { type = "cycle", key = "minQuality", label = "Show results for", choices = { { 0, "Every item" }, { 2, "Green and better" },
            { 3, "Blue and better" }, { 4, "Purple and better" } } },
        { type = "check", key = "sound", label = "A sound when you win" },
        { type = "check", key = "say", label = "Say each winner in your chat window" },
        { type = "button", label = "See how it looks", text = "Try it", click = function(m) m:Slash("test") end },
        { type = "button", label = "Every roll kept so far", text = "Clear", confirm = "Sure? Click again", click = function(m) m:Slash("clear") end },
    },
})

local PASS, NEED, GREED, DE = 0, 1, 2, 3
local CHOICE = {
    [NEED] = { "Need", { 1, 0.82, 0.25 } },
    [GREED] = { "Greed", T.GREEN },
    [DE] = { "Disenchant", { 0.72, 0.52, 1 } },
    [PASS] = { "Pass", T.MUTED },
}
local RANK = { [NEED] = 1, [GREED] = 2, [DE] = 3, [PASS] = 4 } -- a card lists Need first, then Greed...
local QUALITY = { [0] = { 0.62, 0.62, 0.62 }, { 1, 1, 1 }, { 0.12, 1, 0 }, { 0, 0.44, 0.87 }, { 0.64, 0.21, 0.93 }, { 1, 0.5, 0 } }

local CARD_W, ICON, ROW = 300, 34, 15
local SHOWN = 4 -- cards at once; the rest wait under "+N more"
local PLAYERS_SHOWN = 6 -- roller rows on one card
local KEEP = 100 -- rolls kept for the Rolls page
local LATE = 15 -- seconds after a roll's timer that a result may still come in chat
local USUAL = 60 -- the game's roll time, for a roll that came without one (a card must never stay for good)

local rolls = {} -- open and just-finished rolls, oldest first
local testId = 0
local stack -- the frame the cards hang from
local cards = {}

-- Something changed: the open page, and the stack at once rather than at the next tick.
local function Changed()
    ns.Refresh()
    if M.enabled and M.Draw then ns.Guard("rolls draw", M.Draw, M) end
end

---------------------------------------------------------------------------
-- Names and classes
---------------------------------------------------------------------------

local function Short(name)
    if not name then return "?" end
    if Ambiguate then
        local ok, short = pcall(Ambiguate, name, "short")
        if ok and short then name = short end
    end
    return (name:gsub("%-.*$", ""))
end

-- The loot lines can carry a name the game shortens elsewhere ("Holy Miau" and "Holy"): the same player.
local function Same(a, b)
    if a == b then return true end
    if #a > #b then a, b = b, a end
    return b:sub(1, #a + 1) == a .. " "
end

local function Me() return Short(ns.MyName()) end

local function ClassOf(name)
    if Same(name, Me()) then return select(2, ns.MyClass()) end
    local raid = IsInRaid and IsInRaid()
    local n = raid and (GetNumGroupMembers and GetNumGroupMembers() or 0) or 4
    for i = 1, n do
        local unit = (raid and "raid" or "party") .. i
        local who = ns.Plain(UnitName(unit))
        if who and Same(Short(who), name) then return ns.Plain(select(2, UnitClass(unit))) end
    end
end

local function Painted(name, class)
    return "|c" .. ns.ClassHex(class) .. name .. "|r"
end

---------------------------------------------------------------------------
-- Rolls
---------------------------------------------------------------------------

local function ItemKey(link)
    return link and (link:match("|H(item:[^|]+)|h") or link)
end

local function Find(link)
    local key = ItemKey(link)
    for _, r in ipairs(rolls) do
        if not r.done and r.key == key then return r end
    end
end

local function New(id, link, seconds)
    local r = { id = id, link = link, key = ItemKey(link), players = {}, started = GetTime(), total = seconds or 0 }
    r.name = link and link:match("|h%[(.-)%]|h") or "Item"
    local get = C_Item and C_Item.GetItemInfo or GetItemInfo
    if get and link then
        local _, _, quality, _, _, _, _, _, _, icon = get(link)
        r.quality, r.icon = quality, icon
    end
    rolls[#rolls + 1] = r
    return r
end

-- A roll the game opened: what it is and which buttons you may press.
local function Open(id, seconds)
    for _, r in ipairs(rolls) do
        if r.id == id then return r end
    end
    local link = GetLootRollItemLink and GetLootRollItemLink(id)
    local r = New(id, link, seconds)
    if GetLootRollItemInfo then
        local icon, name, count, quality, _, canNeed, canGreed, canDE, whyNeed, whyGreed, whyDE = GetLootRollItemInfo(id)
        r.icon, r.quality, r.count = icon or r.icon, quality or r.quality, count
        r.name = name or r.name
        r.can = { [NEED] = canNeed ~= false, [GREED] = canGreed ~= false, [DE] = canDE == true, [PASS] = true }
        r.why = { [NEED] = whyNeed, [GREED] = whyGreed, [DE] = whyDE }
    end
    return r
end

local function Player(r, name)
    name = Short(name)
    for _, p in ipairs(r.players) do
        if Same(p.name, name) then
            if #name > #p.name then p.name = name end
            return p
        end
    end
    local p = { name = name, class = ClassOf(name) }
    r.players[#r.players + 1] = p
    return p
end

local function Sorted(r)
    local list = {}
    for _, p in ipairs(r.players) do list[#list + 1] = p end
    table.sort(list, function(a, b)
        if (a.name == r.winner) ~= (b.name == r.winner) then return a.name == r.winner end
        local ra, rb = RANK[a.choice] or 5, RANK[b.choice] or 5
        if ra ~= rb then return ra < rb end
        if (a.roll or -1) ~= (b.roll or -1) then return (a.roll or -1) > (b.roll or -1) end
        return a.name < b.name
    end)
    return list
end

-- A finished roll goes to the Rolls page.
local function Keep(r)
    if r.test then return end
    local list = ns.db.rolls or {}
    ns.db.rolls = list
    local players = {}
    for _, p in ipairs(Sorted(r)) do players[#players + 1] = { p.name, p.class or "", p.choice or -1, p.roll or 0 } end
    local me = r.mine
    table.insert(list, 1, { at = time(), link = r.link or "", name = r.name, q = r.quality or 1, winner = r.winner or "",
        wclass = r.winnerClass or "", roll = r.winRoll or 0, choice = r.winChoice or -1, mine = me or -1,
        passed = r.allPassed or false, players = players })
    while #list > KEEP do table.remove(list) end
end

local function Finish(r, winner, allPassed)
    if r.done then return end
    r.done, r.closedAt = true, GetTime()
    r.allPassed = allPassed or false
    if winner then
        local p = Player(r, winner)
        r.winner, r.winnerClass, r.winRoll, r.winChoice = p.name, p.class, p.roll, p.choice
        local mine = Same(p.name, Me())
        if mine and M.db.sound and PlaySound and SOUNDKIT then pcall(PlaySound, SOUNDKIT.READY_CHECK or 8960) end
        if M.db.say then
            ns.Print((mine and "You won " or (Painted(p.name, p.class) .. " won ")) .. (r.link or r.name)
                .. (p.roll and (" with " .. p.roll) or "") .. ".")
        end
    elseif allPassed and M.db.say then
        ns.Print("Everyone passed on " .. (r.link or r.name) .. ".")
    end
    -- A result under the quality to show leaves at once.
    if (r.quality or 1) < (M.db.minQuality or 0) then r.gone = true end
    Keep(r)
    Changed()
end

---------------------------------------------------------------------------
-- Reading the loot lines
---------------------------------------------------------------------------

-- { global string, what it says, choice, about you }
local LINES = {
    { "LOOT_ROLL_NEED_SELF", "pick", NEED, true }, { "LOOT_ROLL_GREED_SELF", "pick", GREED, true },
    { "LOOT_ROLL_DISENCHANT_SELF", "pick", DE, true }, { "LOOT_ROLL_PASSED_SELF_AUTO", "pick", PASS, true },
    { "LOOT_ROLL_PASSED_SELF", "pick", PASS, true },
    { "LOOT_ROLL_ROLLED_NEED_ROLE_BONUS", "roll", NEED }, { "LOOT_ROLL_ROLLED_NEED", "roll", NEED },
    { "LOOT_ROLL_ROLLED_GREED", "roll", GREED }, { "LOOT_ROLL_ROLLED_DE", "roll", DE },
    { "LOOT_ROLL_YOU_WON", "won", nil, true }, { "LOOT_ROLL_WON", "won" }, { "LOOT_ROLL_ALL_PASSED", "passed" },
    { "LOOT_ROLL_NEED", "pick", NEED }, { "LOOT_ROLL_GREED", "pick", GREED }, { "LOOT_ROLL_DISENCHANT", "pick", DE },
    { "LOOT_ROLL_PASSED_AUTO", "pick", PASS }, { "LOOT_ROLL_PASSED_AUTO_FEMALE", "pick", PASS }, { "LOOT_ROLL_PASSED", "pick", PASS },
}
local rules

-- Newer clients wrap part of a loot line in a loot history link; only its text matters.
local function Unwrap(s)
    return (s:gsub("|HlootHistory:[^|]*|h(.-)|h", "%1"))
end

local function Rule(format)
    local p = Unwrap(format):gsub("%%%d?%$?s", "\1"):gsub("%%%d?%$?d", "\2")
    p = p:gsub("[%(%)%.%+%-%*%?%[%]%^%$%%]", "%%%0")
    p = p:gsub("\1", "(.-)"):gsub("\2", "(%%d+)")
    return "^" .. p .. "$"
end

-- The longest stretch of a format with nothing filled in: a line without it cannot be that format, and a plain
-- search for it is far quicker than the pattern.
local function Literal(format)
    local best = ""
    for piece in (Unwrap(format):gsub("%%%d?%$?[sd]", "\1") .. "\1"):gmatch("([^\1]*)\1") do
        if #piece > #best then best = piece end
    end
    return #best >= 4 and best or nil
end

local function Rules()
    local list = {}
    for _, line in ipairs(LINES) do
        local format = _G[line[1]]
        if type(format) == "string" then
            list[#list + 1] = { pattern = Rule(format), what = line[2], choice = line[3], self = line[4], literal = Literal(format) }
        end
    end
    return list
end

-- What a loot line says: the item, the player and the number are told apart by their look, not their place.
local function Read(msg)
    msg = Unwrap(msg)
    for _, rule in ipairs(rules) do
        -- Most loot lines match none of the rules: find says so without making a table for each.
        local found = (not rule.literal or msg:find(rule.literal, 1, true)) and msg:find(rule.pattern)
            and { msg:match(rule.pattern) } or nil
        if found and #found > 0 then
            local link, name, number
            for _, v in ipairs(found) do
                if v:find("|Hitem:", 1, true) then link = v
                elseif tonumber(v) and not number then number = tonumber(v)
                else name = name or v end
            end
            if rule.self then name = Me() end
            if link then return rule, link, name, number end
        end
    end
end

function M:Line(msg)
    if (issecretvalue and issecretvalue(msg)) or type(msg) ~= "string" then return end
    rules = rules or Rules()
    local rule, link, name, number = Read(msg)
    if not rule then return end
    local r = Find(link)
    if not r then
        if rule.what ~= "pick" then return end -- a result for a roll this window never saw
        r = New(nil, link, 0) -- someone else's roll you could not join: watched, without buttons
        r.watch = true
    end
    if rule.what == "pick" then
        local p = Player(r, name)
        p.choice = rule.choice
        if Same(p.name, Me()) then r.mine = rule.choice end
        -- Others may watch the picks: fn(link, name, choice, mine) with choice M.NEED, M.GREED...
        for _, fn in ipairs(M.watchers) do ns.Guard("roll watcher", fn, link, p.name, rule.choice, Same(p.name, Me())) end
    elseif rule.what == "roll" then
        local p = Player(r, name)
        p.choice, p.roll = rule.choice, number
        if Same(p.name, Me()) then r.myRoll = number end
    elseif rule.what == "won" then
        Finish(r, name)
    elseif rule.what == "passed" then
        Finish(r, nil, true)
    end
    Changed()
end

M.watchers = {}
M.PASS, M.NEED, M.GREED, M.DE = PASS, NEED, GREED, DE
M:On("CHAT_MSG_LOOT", function(self, _, msg) self:Line(msg) end)

---------------------------------------------------------------------------
-- The game's roll events
---------------------------------------------------------------------------

local blizzard = true -- whether UIParent still opens the game's boxes (it does until this module takes over)

-- The 12.x client opens its roll boxes from GroupLootContainer as well as from UIParent. The container gives each
-- roll a slot and only lets it go through GroupLootContainer_RemoveFrame: a box hidden from outside keeps its slot,
-- so the empty container stayed shown, grew a slot per roll and took the mouse in the middle of the screen (the
-- invisible panel; ns.db.rollTrace showed it). So the boxes leave the container its own way, and an empty
-- container is hidden.
local function HideGame()
    local container = _G.GroupLootContainer
    if container and type(container.rollFrames) == "table" and type(GroupLootContainer_RemoveFrame) == "function" then
        local list = {}
        for _, f in pairs(container.rollFrames) do list[#list + 1] = f end
        for _, f in ipairs(list) do pcall(GroupLootContainer_RemoveFrame, container, f) end
    end
    for i = 1, NUM_GROUP_LOOT_FRAMES or 4 do
        local f = _G["GroupLootFrame" .. i]
        if f and f.Hide then f:Hide() end
    end
    if container and container.Hide and container.IsShown and container:IsShown() then
        local busy = false
        for _, f in pairs(type(container.rollFrames) == "table" and container.rollFrames or {}) do
            if f.IsShown and f:IsShown() then busy = true end
        end
        if not busy then container:Hide() end
    end
end

-- The frames that open the game's boxes: take the event away from them, or give it back.
local OPENERS = { "UIParent", "GroupLootContainer" }
local took = {} -- the openers this module took the event from

local function Takeover()
    local want = M.enabled and M.db.replace
    if want and not blizzard then return end
    if want then
        for _, name in ipairs(OPENERS) do
            local f = _G[name]
            if f and f.UnregisterEvent and (name == "UIParent" or not f.IsEventRegistered or f:IsEventRegistered("START_LOOT_ROLL")) then
                f:UnregisterEvent("START_LOOT_ROLL")
                took[name] = true
            end
        end
        blizzard = false
        HideGame()
    elseif not blizzard then
        for name in pairs(took) do
            local f = _G[name]
            if f and f.RegisterEvent then pcall(f.RegisterEvent, f, "START_LOOT_ROLL") end
        end
        took = {}
        blizzard = true
    end
end

M:On("START_LOOT_ROLL", function(_, _, id, ms)
    Open(id, (ms or 0) / 1000)
    if M.db.replace then
        HideGame()
        ns.After(0, HideGame) -- in case the game's own handler runs after this one
    end
    Changed()
end)

M:On("CANCEL_LOOT_ROLL", function(_, _, id)
    for _, r in ipairs(rolls) do
        if r.id == id then r.closed = true end
    end
    Changed()
end)

-- After a /reload the rolls still open come back.
M:On("PLAYER_ENTERING_WORLD", function()
    if not (GetActiveLootRollIDs and GetLootRollTimeLeft) then return end
    for _, id in ipairs(GetActiveLootRollIDs() or {}) do
        local left = (GetLootRollTimeLeft(id) or 0) / 1000
        local r = Open(id, left)
        r.started = GetTime()
    end
    Changed()
end)

---------------------------------------------------------------------------
-- Trace: what is on screen around a roll, kept in ns.db.rollTrace
---------------------------------------------------------------------------
-- In a group, an invisible box sometimes blocks the mouse while this module is on. Nobody can stop to look
-- mid-dungeon, so a roll leaves a few snapshots behind: our own frames, the game's roll frames and anything
-- visible that takes the mouse while being (nearly) see-through. Read from the SavedVariables afterwards.

local TRACE_KEEP, TRACE_GHOSTS = 40, 12
local TRACE_AFTER = { 1, 5, 20, 80 } -- seconds after a roll opens

local function Call(f, method, ...)
    local fn = f and f[method]
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c, d = pcall(fn, f, ...)
    if not ok then return nil end
    for _, v in ipairs({ a, b, c, d }) do
        if issecretvalue and issecretvalue(v) then return nil end
    end
    return a, b, c, d
end

local function Round(v) return type(v) == "number" and math.floor(v + 0.5) or nil end

-- One frame in a line: name shown mouse alpha(effective) at x,y size wxh.
local function Describe(f, name)
    if not f or Call(f, "IsForbidden") then return (name or "?") .. " forbidden" end
    local l, b, w, h = Call(f, "GetRect")
    local ea = Call(f, "GetEffectiveAlpha")
    return string.format("%s shown=%s visible=%s mouse=%s alpha=%s at %s,%s size %sx%s",
        name or Call(f, "GetDebugName") or "?", tostring(Call(f, "IsShown")), tostring(Call(f, "IsVisible")),
        tostring(Call(f, "IsMouseEnabled")), ea and string.format("%.2f", ea) or "?",
        tostring(Round(l)), tostring(Round(b)), tostring(Round(w)), tostring(Round(h)))
end

local function Snapshot(why)
    if not (ns.db and IsInGroup and IsInGroup()) then return end
    local s = { at = time(), why = why, ours = {}, game = {}, ghosts = {} }
    if stack then
        s.ours[#s.ours + 1] = Describe(stack, "stack")
        for i, c in ipairs(cards) do
            s.ours[#s.ours + 1] = Describe(c, "card" .. i)
            s.ours[#s.ours + 1] = Describe(c.iconFrame, "card" .. i .. ".icon")
        end
    end
    local open = 0
    for _, r in ipairs(rolls) do if not r.done then open = open + 1 end end
    s.open, s.kept = open, #rolls
    local container = _G.GroupLootContainer
    if container then
        s.game[#s.game + 1] = Describe(container, "GroupLootContainer")
        if type(container.rollFrames) == "table" then
            for k, f in pairs(container.rollFrames) do s.game[#s.game + 1] = Describe(f, "rollFrames." .. tostring(k)) end
        end
    end
    for i = 1, NUM_GROUP_LOOT_FRAMES or 4 do
        local f = _G["GroupLootFrame" .. i]
        if f then s.game[#s.game + 1] = Describe(f, "GroupLootFrame" .. i) end
    end
    -- Anything visible that takes the mouse and can hardly be seen.
    if EnumerateFrames then
        local f = EnumerateFrames()
        while f and #s.ghosts < TRACE_GHOSTS do
            if not Call(f, "IsForbidden") and Call(f, "IsVisible") and Call(f, "IsMouseEnabled") then
                local ea = Call(f, "GetEffectiveAlpha")
                if ea and ea < 0.05 then s.ghosts[#s.ghosts + 1] = Describe(f) end
            end
            f = EnumerateFrames(f)
        end
    end
    local list = ns.db.rollTrace or {}
    ns.db.rollTrace = list
    table.insert(list, 1, s)
    while #list > TRACE_KEEP do table.remove(list) end
end

M.Snapshot = Snapshot

local function Trace(why)
    ns.Guard("rolls trace", Snapshot, why)
end

M:On("START_LOOT_ROLL", function(_, _, id)
    Trace("start " .. tostring(id))
    for _, sec in ipairs(TRACE_AFTER) do
        ns.After(sec, function() Trace(sec .. "s after start " .. tostring(id)) end)
    end
end)

M:On("CANCEL_LOOT_ROLL", function(_, _, id)
    Trace("cancel " .. tostring(id))
    ns.After(2, function() Trace("2s after cancel " .. tostring(id)) end)
end)

function M:Pick(r, choice)
    if r.done or r.closed or r.mine or not (r.can and r.can[choice]) then return end
    if r.test then
        r.mine = choice
        Player(r, Me()).choice = choice
    elseif RollOnLoot then
        RollOnLoot(r.id, choice)
        r.mine = choice -- the game's own line confirms it a moment later
    end
    Changed()
end

---------------------------------------------------------------------------
-- The stack of cards
---------------------------------------------------------------------------

local function Place()
    if stack then T.Place(stack, ns.MoverStore("rolls"), "TOP", 0, -140) end
end

local BUTTONS = { NEED, GREED, DE, PASS }

local function Card(i)
    if cards[i] then return cards[i] end
    local c = T.Panel(stack, T.WINDOW, 0.92)
    c:SetWidth(CARD_W)
    c.iconFrame = T.Panel(c, T.SURFACE)
    c.iconFrame:SetSize(ICON + 2, ICON + 2)
    c.iconFrame:SetPoint("TOPLEFT", 8, -8)
    c.icon = c.iconFrame:CreateTexture(nil, "ARTWORK")
    c.icon:SetPoint("TOPLEFT", 1, -1)
    c.icon:SetSize(ICON, ICON)
    c.iconFrame:EnableMouse(true)
    c.iconFrame:SetScript("OnEnter", function(self)
        local r = c.roll
        if r and r.link and GameTooltip and GameTooltip.SetHyperlink then
            GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            pcall(GameTooltip.SetHyperlink, GameTooltip, r.link)
            if ns.Codex.Has() then GameTooltip:AddLine("Alt-click: open in Codex Forever", 0.6, 0.6, 0.6) end
            GameTooltip:Show()
        end
    end)
    c.iconFrame:SetScript("OnLeave", T.HideTip)
    c.iconFrame:SetScript("OnMouseUp", function()
        local r = c.roll
        if not r then return end
        -- Alt-click: Codex Forever; otherwise the game's own: shift-click links it, ctrl-click tries it on.
        if not ns.Codex.Click(r.link or r.name) and r.link and HandleModifiedItemClick then HandleModifiedItemClick(r.link) end
    end)
    c.name = T.Text(c, "GameFontNormal")
    c.name:SetPoint("TOPLEFT", ICON + 18, -8)
    c.name:SetWidth(CARD_W - ICON - 26)
    c.name:SetWordWrap(false)
    c.status = T.Text(c, "GameFontHighlightSmall", T.DIM)
    c.status:SetPoint("TOPLEFT", ICON + 18, -26)
    c.status:SetWidth(CARD_W - ICON - 26)
    c.status:SetWordWrap(false)
    -- The time left, a thin bar under the head.
    c.track = c:CreateTexture(nil, "ARTWORK")
    c.track:SetTexture(T.WHITE)
    c.track:SetVertexColor(0, 0, 0, 0.6)
    c.track:SetPoint("TOPLEFT", 8, -(ICON + 14))
    c.track:SetSize(CARD_W - 16, 3)
    c.fill = c:CreateTexture(nil, "OVERLAY")
    c.fill:SetTexture(T.WHITE)
    c.fill:SetPoint("TOPLEFT", 8, -(ICON + 14))
    c.fill:SetHeight(3)
    c.buttons = {}
    local width = math.floor((CARD_W - 16 - 3 * 4) / 4)
    for k, choice in ipairs(BUTTONS) do
        local b = T.Button(c, CHOICE[choice][1], width, function() if c.roll then M:Pick(c.roll, choice) end end)
        b:SetHeight(22)
        b.label:SetTextColor(CHOICE[choice][2][1], CHOICE[choice][2][2], CHOICE[choice][2][3])
        b:SetPoint("TOPLEFT", 8 + (k - 1) * (width + 4), -(ICON + 22))
        b.choice = choice
        c.buttons[choice] = b
    end
    c.rows = {}
    for k = 1, PLAYERS_SHOWN + 1 do
        local row = {}
        row.name = T.Text(c, "GameFontHighlightSmall")
        row.name:SetWidth(150)
        row.name:SetWordWrap(false)
        row.choice = T.Text(c, "GameFontHighlightSmall")
        row.choice:SetWidth(80)
        row.roll = T.Text(c, "GameFontHighlightSmall")
        row.roll:SetWidth(40)
        row.roll:SetJustifyH("RIGHT")
        c.rows[k] = row
    end
    cards[i] = c
    return c
end

local function Status(r, now)
    if r.done then
        if r.allPassed then return "|cff999999Everyone passed.|r" end
        if r.winner then
            local mine = Same(r.winner, Me())
            local who = mine and T.Paint("You won!", T.GREEN) or ("Won by " .. Painted(r.winner, r.winnerClass))
            local how = r.winChoice and CHOICE[r.winChoice] and T.Paint(CHOICE[r.winChoice][1], CHOICE[r.winChoice][2]) or nil
            return who .. (how and ("  " .. how) or "") .. (r.winRoll and ("  |cffffffff" .. r.winRoll .. "|r") or "")
        end
        return "|cff999999No result.|r"
    end
    if r.mine then
        return "You: " .. T.Paint(CHOICE[r.mine][1], CHOICE[r.mine][2]) .. (r.myRoll and ("  |cffffffff" .. r.myRoll .. "|r") or "")
            .. "  |cff999999waiting for the others|r"
    end
    if r.watch then return "|cff999999You are not in this roll.|r" end
    if r.closed then return "|cff999999Closed.|r" end
    local left = r.total > 0 and math.max(0, r.total - (now - r.started)) or nil
    return "Need, Greed or Pass" .. (left and string.format("  |cff999999%ds|r", math.ceil(left)) or "")
end

-- The time left on a card: the bar, red in the last fifth, and the seconds in the status line, which only
-- changes once a second. The stack's OnUpdate runs this every frame while it is on screen, so the bar glides
-- instead of stepping; everything else on a card is drawn only when something changes (M:Draw).
local function Timer(c, r, now)
    local timed = not r.done and not r.closed and not r.watch and r.total > 0
    local frac = timed and math.max(0, 1 - (now - r.started) / r.total) or 0
    c.track:SetShown(timed)
    c.fill:SetShown(timed and frac > 0)
    if timed then
        local col = frac < 0.2 and T.RED or T.GOLD
        c.fill:SetVertexColor(col[1], col[2], col[3], 1)
        c.fill:SetWidth(math.max(1, (CARD_W - 16) * frac))
    end
    local sec = (timed and not r.mine) and math.ceil(math.max(0, r.total - (now - r.started))) or nil
    if sec ~= c.sec then
        c.sec = sec
        c.status:SetText(Status(r, now))
    end
end

local LEAVE = 0.3 -- seconds a finished card takes to fade out at the end of the hold

-- The cards worth showing: waiting for your pick first, then waiting for the others, then results.
local function Visible(now)
    local list = {}
    for _, r in ipairs(rolls) do
        if not r.gone then list[#list + 1] = r end
    end
    local function Stage(r) return (r.done and 3) or (r.mine or r.watch or r.closed) and 2 or 1 end
    table.sort(list, function(a, b)
        local sa, sb = Stage(a), Stage(b)
        if sa ~= sb then return sa < sb end
        return a.started < b.started
    end)
    return list
end

function M:Draw()
    if not stack then return end
    local now = GetTime()
    local list = Visible(now)
    local y = 0
    for i = 1, math.min(SHOWN, #list) do
        local r, c = list[i], Card(i)
        local moved = false
        if c.roll ~= r then -- this card now shows another roll
            c.roll = r
            if r.leaving then -- already fading out: leave it
            elseif not r.seen then
                r.seen = true
                c:SetAlpha(0)
                T.Fade(c, 1, 0.2) -- a new roll fades in
            else
                T.Fade(c, 1, 0.01) -- moved up from another card: no fade, but no leftover one either
                moved = true
            end
        end
        c.iconFrame:EnableMouse(not r.leaving) -- only the item box and the buttons take the mouse
        local q = QUALITY[r.quality or 1] or QUALITY[1]
        c.iconFrame:SetBackdropBorderColor(q[1], q[2], q[3], 1)
        c.icon:SetTexture(r.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
        c.name:SetText(T.Paint(r.name .. ((r.count and r.count > 1) and (" x" .. r.count) or ""), q))
        c.name:SetTextColor(q[1], q[2], q[3])
        c.sec = false -- forces the status line
        Timer(c, r, now)
        -- Buttons until you pick; one you may not press is dimmed and says why.
        local ask = not r.done and not r.closed and not r.mine and not r.watch
        local h = ICON + 20
        for choice, b in pairs(c.buttons) do
            local can = r.can and r.can[choice]
            local show = ask and (choice ~= DE or (r.can and r.can[DE]))
            b:SetShown(show and true or false)
            b:SetAlpha(can and 1 or 0.35)
            local why = r.why and r.why[choice]
            b.tip = (not can and why and _G["LOOT_ROLL_INELIGIBLE_REASON" .. why]) or nil
            b.tipTitle = b.tip and CHOICE[choice][1] or nil
        end
        -- The shown buttons share the row, so a hidden Disenchant leaves no hole between Greed and Pass.
        local row = {}
        for _, choice in ipairs(BUTTONS) do
            if c.buttons[choice]:IsShown() then row[#row + 1] = c.buttons[choice] end
        end
        local bw = math.floor((CARD_W - 16 - (#row - 1) * 4) / math.max(1, #row))
        for k, b in ipairs(row) do
            b:SetWidth(bw)
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", 8 + (k - 1) * (bw + 4), -(ICON + 22))
        end
        if ask then h = h + 28 end
        -- Who picked what, with rolls once they come.
        local players = M.db.everyone and Sorted(r) or {}
        local shown = math.min(#players, PLAYERS_SHOWN)
        for k, row in ipairs(c.rows) do
            local p = players[k]
            local on = k <= shown
            row.name:SetShown(on)
            row.choice:SetShown(on)
            row.roll:SetShown(on)
            if on then
                local win = r.winner and p.name == r.winner
                row.name:SetText((win and T.Paint("> ", T.GOLD) or "  ") .. Painted(p.name, p.class))
                local ch = p.choice and CHOICE[p.choice]
                row.choice:SetText(ch and T.Paint(ch[1], ch[2]) or "|cff999999...|r")
                row.roll:SetText(p.roll and ((win and "|cffffd100" or "|cffffffff") .. p.roll .. "|r") or (p.choice == PASS and "|cff999999-|r" or ""))
                local ry = -(h + (k - 1) * ROW)
                row.name:ClearAllPoints()
                row.name:SetPoint("TOPLEFT", 10, ry)
                row.choice:ClearAllPoints()
                row.choice:SetPoint("TOPLEFT", 170, ry)
                row.roll:ClearAllPoints()
                row.roll:SetPoint("TOPRIGHT", -10, ry)
            end
        end
        if #players > shown then
            local row = c.rows[PLAYERS_SHOWN + 1]
            row.name:SetText(string.format("|cff999999+ %d more|r", #players - shown))
            row.name:SetShown(true)
            row.name:ClearAllPoints()
            row.name:SetPoint("TOPLEFT", 10, -(h + shown * ROW))
            shown = shown + 1
        end
        h = h + shown * ROW + (shown > 0 and 6 or 0)
        c:SetHeight(h)
        c:ClearAllPoints()
        c:SetPoint("TOP", stack, "TOP", 0, -y)
        if moved and r.drawnY and r.drawnY ~= y then ns.Motion.Glide(c, 0, y - r.drawnY) end -- from where it was
        r.drawnY = y
        c:SetBackdropBorderColor(r.done and r.winner and Same(r.winner, Me()) and T.GREEN[1] or T.BORDER[1],
            r.done and r.winner and Same(r.winner, Me()) and T.GREEN[2] or T.BORDER[2],
            r.done and r.winner and Same(r.winner, Me()) and T.GREEN[3] or T.BORDER[3], 1)
        c:Show()
        y = y + h + 4
    end
    for i = math.min(SHOWN, #list) + 1, #cards do
        cards[i]:Hide()
        cards[i].roll = nil
    end
    stack.more:SetShown(#list > SHOWN)
    stack.more:SetText(string.format("+ %d more roll%s", #list - SHOWN, #list - SHOWN == 1 and "" or "s"))
    stack.more:ClearAllPoints()
    stack.more:SetPoint("TOP", stack, "TOP", 0, -y)
    stack:SetHeight(math.max(1, y + (#list > SHOWN and 16 or 0)))
    stack:SetShown(#list > 0)
end

local function Stack()
    if stack then return stack end
    stack = CreateFrame("Frame", nil, UIParent)
    stack:SetSize(CARD_W, 1)
    stack:SetFrameStrata("HIGH")
    stack.more = T.Text(stack, "GameFontHighlightSmall", T.DIM)
    -- Only while the stack shows: the timers, nothing else (see Timer).
    stack:SetScript("OnUpdate", function()
        local now = GetTime()
        for i = 1, SHOWN do
            local c = cards[i]
            if c and c.roll and c:IsShown() then Timer(c, c.roll, now) end
        end
    end)
    M.stack = stack
    Place()
    stack:Hide()
    return stack
end

-- Whether a roll with no result has waited long enough: LATE seconds after its time ran out (USUAL when it
-- came without a time), or a minute for a roll you only watch. A cancelled roll waits the same: the game
-- cancels it once everyone has picked, and the result line can come well after that.
local function Expired(r, now)
    if r.watch then return now - r.started > 60 end
    return now - r.started > (r.total > 0 and r.total or USUAL) + LATE
end

-- Results leave after the hold, counted from when they came; rolls that never got one leave once Expired.
-- The cards are redrawn only when one leaves; a result starts fading LEAVE seconds before its hold ends.
local function Tidy()
    local now, hold = GetTime(), M.db.hold or 5
    local changed = false
    for i = #rolls, 1, -1 do
        local r = rolls[i]
        if r.done then
            if r.gone or now - r.closedAt > hold then
                table.remove(rolls, i)
                changed = true
            elseif now - r.closedAt > hold - LEAVE and not r.leaving then
                r.leaving = true
                for _, c in ipairs(cards) do
                    if c.roll == r and c:IsShown() then
                        c.iconFrame:EnableMouse(false) -- a card on its way out takes no clicks
                        T.Fade(c, 0, LEAVE)
                    end
                end
            end
        elseif Expired(r, now) then
            Finish(r)
            r.gone = true
            changed = true
        end
    end
    if changed and stack then M:Draw() end
end

ns.Every(0.25, Tidy, M) -- a quarter second is fine for when a card leaves

function M:OnEnable()
    rules = rules or Rules()
    Stack()
    Takeover()
end

function M:OnDisable()
    Takeover()
    if stack then stack:Hide() end
end

function M:OnOption()
    Takeover()
    if stack then self:Draw() end
end

ns.AddMover({
    key = "rolls", title = "Loot rolls", width = CARD_W, height = 80, point = "TOP", x = 0, y = -140,
    Shown = function() return M.enabled end,
    Apply = Place,
})

---------------------------------------------------------------------------
-- /zod rolls test: a party of four rolls on two items
---------------------------------------------------------------------------

local FAKE = { { "Thrallson", "SHAMAN" }, { "Mireth", "MAGE" }, { "Gorruk", "WARRIOR" }, { "Velya", "PRIEST" } }
local FAKE_ITEMS = {
    { "Staff of Westfall", 3, "Interface\\Icons\\INV_Staff_02", 1800 },
    { "Silk Cloth", 1, "Interface\\Icons\\INV_Fabric_Silk_01", 7 },
}

local function Test()
    for k, item in ipairs(FAKE_ITEMS) do
        testId = testId - 1
        local link = string.format("|cff%s|Hitem:%d::::::::|h[%s]|h|r", T.Hex(QUALITY[item[2]]):sub(3), item[4], item[1])
        local r = New(testId, link, 30 - k * 8)
        r.test, r.quality, r.icon, r.name = true, item[2], item[3], item[1]
        r.can = { [NEED] = k == 1, [GREED] = true, [DE] = k == 1, [PASS] = true }
        r.why = { [NEED] = 2 }
        -- The others pick, then roll, then someone wins.
        for n, who in ipairs(FAKE) do
            ns.After(0.6 * n + k, function()
                local p = Player(r, who[1])
                p.class = who[2]
                p.choice = (n % 3 == 0) and PASS or (k == 1 and NEED or GREED)
                Changed()
            end)
        end
        ns.After(4 + k * 2, function()
            for n, who in ipairs(FAKE) do
                local p = Player(r, who[1])
                if p.choice ~= PASS then p.roll = (n * 37 + k * 11) % 100 + 1 end
            end
            local me = Player(r, Me())
            me.class = select(2, ns.MyClass())
            if not r.mine then r.mine, me.choice = GREED, GREED end
            if me.choice ~= PASS then me.roll = 64 end
            local best
            for _, p in ipairs(r.players) do
                if p.roll and (not best or (RANK[p.choice] < RANK[best.choice]) or (p.choice == best.choice and p.roll > best.roll)) then best = p end
            end
            Finish(r, best and best.name, not best)
        end)
    end
    Changed()
end

function M:Slash(arg)
    arg = (arg or ""):lower()
    if arg == "test" then
        Test()
        self:Print("Two sample rolls: press a button on them. Nothing is really rolled.")
    elseif arg == "clear" then
        ns.db.rolls = {}
        for i = #rolls, 1, -1 do rolls[i] = nil end -- and any card still on screen
        Changed()
        self:Print("Every roll kept so far is cleared, and the cards on screen are gone.")
    else
        self:Print("/zod rolls opens the list; /zod rolls test shows two sample rolls; /zod rolls clear forgets them.")
    end
end

---------------------------------------------------------------------------
-- The Rolls page and the Home card
---------------------------------------------------------------------------

local function WinnerText(e)
    if e.passed then return "|cff999999everyone passed|r" end
    if e.winner == "" then return "|cff999999no result|r" end
    return Painted(e.winner, e.wclass ~= "" and e.wclass or nil)
end

local function ChoiceText(c)
    local ch = CHOICE[c]
    return ch and T.Paint(ch[1], ch[2]) or "|cff999999-|r"
end

function M:Card()
    local list = ns.db.rolls or {}
    if #list == 0 then return nil end
    local today, n, won = ns.Today(), 0, 0
    for _, e in ipairs(list) do
        if date("%Y-%m-%d", e.at) == today then
            n = n + 1
            if Same(e.winner, Me()) then won = won + 1 end
        end
    end
    local last = list[1]
    return {
        title = "Loot rolls",
        lines = {
            { "Rolls today", n },
            { "Won today", won },
            { "Last", "|c" .. T.Hex(QUALITY[last.q] or QUALITY[1]) .. last.name .. "|r" },
            { "Went to", WinnerText(last) },
        },
        button = { "List", function() ns.Show("rolls") end },
    }
end

ns.AddPage({
    key = "rolls", title = "Rolls", order = 16, group = "This character", module = "rolls",
    Build = function(page, f)
        local w = ns.PAGE_W
        page.off = T.Text(f, "GameFontHighlightSmall", T.MUTED)
        page.off:SetPoint("TOPLEFT", 0, -4)
        page.off:SetText("The Loot rolls module is off. Switch it on under Settings.")
        page.total = T.Text(f, "GameFontNormal")
        page.total:SetPoint("TOPLEFT", 0, -4)
        local top = math.floor((ns.PAGE_H - 70) * 0.58)
        page.list = T.Table(f, { { "Item", w - 470 }, { "Went to", 150 }, { "Roll", 60, "RIGHT" }, { "You", 100 }, { "When", 140 } },
            w, top)
        page.list:SetPoint("TOPLEFT", 0, -28)
        page.list.itemOf = function(e) return e.link ~= "" and e.link or e.name end -- Alt-click: Codex Forever
        page.list.linkOf = function(e) return e.link ~= "" and e.link or nil end
        page.list.onClick = function(e)
            page.list.selected = e
            page:Refresh()
        end
        page.whoHead = T.Text(f, "GameFontNormalSmall", T.GOLD)
        page.whoHead:SetPoint("TOPLEFT", 0, -(36 + top))
        page.who = T.Table(f, { { "Player", 220 }, { "Picked", 140 }, { "Roll", 70, "RIGHT" } }, 460, ns.PAGE_H - top - 90)
        page.who:SetPoint("TOPLEFT", 0, -(54 + top))
        page.test = T.Button(f, "Try it", 100, function() M:Slash("test") end)
        page.test:SetPoint("BOTTOMLEFT", 0, 0)
        page.clear = T.Button(f, "Clear the list", 140, function() M:Slash("clear") end)
        page.clear:SetPoint("LEFT", page.test, "RIGHT", 6, 0)
        page.clear.confirm = "Sure? Click again"
    end,
    Refresh = function(page)
        local on = M.enabled
        for _, part in ipairs({ page.total, page.list, page.whoHead, page.who, page.test, page.clear }) do part:SetShown(on) end
        page.off:SetShown(not on)
        if not on then return end
        local list, rows, won = ns.db.rolls or {}, {}, 0
        for _, e in ipairs(list) do
            if Same(e.winner, Me()) then won = won + 1 end
            rows[#rows + 1] = { "|c" .. T.Hex(QUALITY[e.q] or QUALITY[1]) .. e.name .. "|r", WinnerText(e),
                e.roll > 0 and tostring(e.roll) or "-", ChoiceText(e.mine), ns.WhenCell(e.at), data = e }
        end
        page.total:SetText(string.format("|cffffffff%d roll%s kept, %d won by you|r  |cff999999click one for everyone's roll|r",
            #list, #list == 1 and "" or "s", won) .. ns.Codex.Hint())
        if page.list.selected == nil or not page.list.selected.players then page.list.selected = list[1] end
        page.list:SetRows(rows, "Rolls you take part in from now on are kept here. /zod rolls test shows how the window looks.")
        local e = page.list.selected
        page.whoHead:SetText(e and ("Who rolled on |c" .. T.Hex(QUALITY[e.q] or QUALITY[1]) .. e.name .. "|r") or "")
        local who = {}
        for _, p in ipairs(e and e.players or {}) do
            local win = e.winner ~= "" and p[1] == e.winner
            who[#who + 1] = { (win and T.Paint("> ", T.GOLD) or "") .. Painted(p[1], p[2] ~= "" and p[2] or nil), ChoiceText(p[3]),
                p[4] > 0 and tostring(p[4]) or "-" }
        end
        page.who:SetRows(who, e and "Nobody's roll was seen." or "")
    end,
})
