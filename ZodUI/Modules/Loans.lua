local ADDON, ns = ...
local T = ns.T

-- Guild loans: who you lent gold to and who you owe, kept per character. When the other one is in your guild
-- and runs ZodUI too, a loan is said to them in an addon whisper and they agree to it (or not), and paying it back
-- is agreed the same way: the one who lent says when it is paid. What someone else says is only ever a claim
-- until you agree to it, so nobody can put a debt on your list. After a trade where only gold changed hands
-- with a guild member, a line in chat offers to write it down.

local M = ns:NewModule("loans", {
    title = "Guild loans",
    desc = "Keeps who you lent gold to and who you owe. With guild members who run ZodUI the list is shared: they "
        .. "agree to a loan you write down, and to it being paid back. After a gold trade it offers to write it down.",
    defaults = { enabled = true, share = true, ask = true, trade = true },
    options = {
        { type = "check", key = "share", label = "Share loans with guild members who run ZodUI" },
        { type = "check", key = "ask", label = "A notice when someone writes down a loan with you" },
        { type = "check", key = "trade", label = "After a gold trade with a guild member, offer to write it down" },
        { type = "note", text = "/zod loans lend Bob 5g for the mount, or borrow Bob 50s. Then paid, ok, no or forget "
            .. "and the loan's number.", lines = 2 },
    },
})

local PREFIX = "ZodUILoans"
local MOST_GOLD = 1000000          -- the largest loan, in gold
local MOST_LOANS = 300             -- kept per character
local MOST_CLAIMS = 10             -- loans someone may ask you to agree to at once
local MOST_HEARD = 20              -- messages taken from one sender a minute
local MOST_SENT = 5                -- messages sent per round, under the game's throttle
local NOTE_MOST = 60
local ROSTER_EVERY = 60

if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then C_ChatInfo.RegisterAddonMessagePrefix(PREFIX) end

local function Data()
    local d = ns.chardb.loans
    if not d then
        d = { next = 1, list = {} }
        ns.chardb.loans = d
    end
    return d
end

local function Me() return ns.MyName() or "?" end

local function Short(name)
    if type(name) ~= "string" or (issecretvalue and issecretvalue(name)) then return nil end
    return Ambiguate and Ambiguate(name, "none") or (name:match("^([^-]+)") or name)
end

-- Text from a note, from you or from someone else: no colour or link codes, no separators, at most NOTE_MOST.
local function CleanNote(s)
    s = tostring(s or ""):gsub("[%c|~]", ""):gsub("^%s+", ""):gsub("%s+$", "")
    return s:sub(1, NOTE_MOST)
end

-- "bob" -> "Bob"; a realm after a dash is kept as typed.
local function CleanName(s)
    s = (s or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if s == "" or #s > 48 or s:find("[%s%c|~:]") then return nil end
    local name, realm = s:match("^([^-]+)(.*)$")
    if name:find("^[%a]+$") then name = name:sub(1, 1):upper() .. name:sub(2):lower() end
    return name .. realm
end

-- Copper from "5g", "5g20s", "5g 20s", "50s", "75c", "2.5" (gold) or "5"; then the words after it (the note).
local function Token(word, first)
    if word:find("^%d+%.?%d*$") then return first and math.floor(tonumber(word) * 10000 + 0.5) or nil end
    local total, pos = 0, 1
    while pos <= #word do
        local num, unit, after = word:match("^(%d+%.?%d*)([gsc])()", pos)
        if not num or (unit ~= "g" and num:find("%.")) then return nil end
        total = total + math.floor(tonumber(num) * (unit == "g" and 10000 or unit == "s" and 100 or 1) + 0.5)
        pos = after
    end
    return total
end

local function ParseMoney(text)
    local words = {}
    for word in tostring(text or ""):gmatch("%S+") do words[#words + 1] = word end
    local copper, used = nil, 0
    for i, word in ipairs(words) do
        local c = Token(word:lower(), i == 1)
        if not c then break end
        copper, used = (copper or 0) + c, i
    end
    return copper, table.concat(words, " ", used + 1)
end
M.ParseMoney = ParseMoney

-- "a~b~~c" -> a, b, "", c
local function Split(text)
    local out = {}
    for field in (text .. "~"):gmatch("([^~]*)~") do out[#out + 1] = field end
    return unpack(out)
end

local function Find(n)
    for i, loan in ipairs(Data().list) do
        if loan.n == n then return loan, i end
    end
end

local function ById(id, who)
    for _, loan in ipairs(Data().list) do
        if loan.id == id and loan.who == who then return loan end
    end
end

local function Describe(loan)
    return loan.lent and (loan.who .. " owes you " .. ns.Money(loan.amount, true))
        or ("you owe " .. loan.who .. " " .. ns.Money(loan.amount, true))
end

---------------------------------------------------------------------------
-- The guild roster: who is a member and who is online
---------------------------------------------------------------------------

local roster = {} -- [short name] = { full = "Name-Realm", online = bool }
local sentA = {}  -- [loan id] = true: the loan has been said to them since they came online

local function ScanRoster()
    local seen = {}
    if IsInGuild and IsInGuild() and GetNumGuildMembers and GetGuildRosterInfo then
        for i = 1, GetNumGuildMembers() or 0 do
            local full, _, _, _, _, _, _, _, online = GetGuildRosterInfo(i)
            local short = Short(full)
            if short and not (issecretvalue and issecretvalue(full)) then
                seen[short] = { full = full, online = online and true or false }
            end
        end
    end
    for short in pairs(roster) do
        if not (seen[short] and seen[short].online) then
            for _, loan in ipairs(Data().list) do
                if loan.who == short then sentA[loan.id] = nil end -- said again when they are back
            end
        end
    end
    roster = seen
end

local function InGuild(who) return roster[who] ~= nil end

---------------------------------------------------------------------------
-- Sending: each loan keeps what is still to be said to the other one
---------------------------------------------------------------------------

local function Queue(loan, kind)
    if not (M.db.share and InGuild(loan.who)) then return end
    loan.out = loan.out or {}
    for _, k in ipairs(loan.out) do
        if k == kind then return end
    end
    loan.out[#loan.out + 1] = kind
end

local function Unqueue(loan, kind)
    if not loan.out then return end
    for i = #loan.out, 1, -1 do
        if loan.out[i] == kind then table.remove(loan.out, i) end
    end
    if #loan.out == 0 then loan.out = nil end
end

local function Message(loan, kind)
    if kind == "A" then
        return table.concat({ "1", "A", loan.id, loan.lent and "L" or "B", loan.amount, loan.at, loan.note or "" }, "~")
    end
    return "1~" .. kind .. "~" .. loan.id
end

local function Sent(result)
    return result == nil or result == true or result == 0
end

local function Flush()
    if not (M.db.share and C_ChatInfo and C_ChatInfo.SendAddonMessage) then return end
    if InCombatLockdown and InCombatLockdown() then return end
    local budget = MOST_SENT
    for _, loan in ipairs(Data().list) do
        local member = roster[loan.who]
        if loan.out and member and member.online then
            local kinds = {}
            for i, k in ipairs(loan.out) do kinds[i] = k end
            for _, kind in ipairs(kinds) do
                if budget <= 0 then return end
                if not (kind == "A" and sentA[loan.id]) then
                    budget = budget - 1
                    if Sent(C_ChatInfo.SendAddonMessage(PREFIX, Message(loan, kind), "WHISPER", member.full)) then
                        if kind == "A" then sentA[loan.id] = true else Unqueue(loan, kind) end -- A waits for a yes or no
                    end
                end
            end
        end
    end
end

---------------------------------------------------------------------------
-- What you do
---------------------------------------------------------------------------

-- Writes down a loan: lent is true when you lent it. Returns the loan, or nil and what is wrong.
function M:Add(lent, who, amount, note)
    who = CleanName(who)
    if not who then return nil, "Type a character's name." end
    if who == Me() then return nil, "That is you." end
    if type(amount) ~= "number" or amount < 1 then return nil, "Type an amount, for example 5g or 50s." end
    if amount > MOST_GOLD * 10000 then return nil, "A loan is at most " .. ns.Comma(MOST_GOLD) .. "g." end
    local d = Data()
    if #d.list >= MOST_LOANS then return nil, "There are " .. MOST_LOANS .. " loans already. Forget some paid ones first." end
    local loan = { n = d.next, id = Me() .. ":" .. d.next, who = who, lent = lent and true or false, amount = math.floor(amount),
        note = CleanNote(note), at = time(), mine = true }
    d.next = d.next + 1
    d.list[#d.list + 1] = loan
    Queue(loan, "A")
    Flush()
    ns.Refresh()
    return loan
end

-- Agree to what the other one said: the loan, or that it is paid.
function M:Agree(loan)
    if loan.claim == "add" then
        loan.claim, loan.agreed = nil, true
    elseif loan.claim == "paid" then
        loan.claim, loan.paid, loan.paidAt = nil, true, time()
    else
        return false, "Loan " .. loan.n .. " has nothing to agree to."
    end
    Queue(loan, "Y")
    Flush()
    ns.Refresh()
    return true
end

function M:Refuse(loan)
    if loan.claim == "add" then
        loan.claim, loan.refused = nil, true
    elseif loan.claim == "paid" then
        loan.claim = nil
    else
        return false, "Loan " .. loan.n .. " has nothing to refuse."
    end
    Queue(loan, "N")
    Flush()
    ns.Refresh()
    return true
end

-- Paid back. The one who lent decides; the one who borrowed asks them, when they share the list.
function M:Paid(loan)
    if loan.paid then return false, "Loan " .. loan.n .. " is paid already." end
    if loan.claim == "add" or loan.refused then return false, "Loan " .. loan.n .. " was never agreed to." end
    local shared = loan.agreed and M.db.share and InGuild(loan.who)
    if loan.lent or not shared then
        loan.paid, loan.paidAt, loan.asked = true, time(), nil
        Unqueue(loan, "A")
        if shared then Queue(loan, "P") end
    else
        loan.asked = "paid"
        Queue(loan, "P")
    end
    Flush()
    ns.Refresh()
    return true
end

function M:Forget(loan)
    local _, i = Find(loan.n)
    if i then table.remove(Data().list, i) end
    ns.Refresh()
end

function M:ForgetPaid()
    local list, n = Data().list, 0
    for i = #list, 1, -1 do
        if list[i].paid or list[i].refused then
            table.remove(list, i)
            n = n + 1
        end
    end
    ns.Refresh()
    return n
end

-- The state of a loan in a few words.
local function State(loan)
    if loan.paid then return T.Paint("Paid back", T.MUTED) end
    if loan.refused then return T.Paint(loan.mine and (loan.who .. " said no") or "You said no", T.MUTED) end
    if loan.claim == "add" then return T.Paint("Asks you to agree", T.GOLD) end
    if loan.claim == "paid" then return T.Paint("Says it is paid", T.GOLD) end
    if loan.asked == "paid" then return "Waiting for " .. loan.who end
    if loan.agreed then return T.Paint("Agreed", T.GREEN) end
    if not (M.db.share and InGuild(loan.who)) then return "Only on your list" end
    return "Waiting for " .. loan.who
end

local function PlainState(loan) return (State(loan):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end

local function Open(loan) return not (loan.paid or loan.refused or loan.claim == "add") end

-- Owed to you, what you owe, and how many of each.
function M:Totals()
    local owed, owe, nOwed, nOwe, ask = 0, 0, 0, 0, 0
    for _, loan in ipairs(Data().list) do
        if loan.claim then ask = ask + 1 end
        if Open(loan) then
            if loan.lent then owed, nOwed = owed + loan.amount, nOwed + 1 else owe, nOwe = owe + loan.amount, nOwe + 1 end
        end
    end
    return owed, owe, nOwed, nOwe, ask
end

---------------------------------------------------------------------------
-- What the other one says
---------------------------------------------------------------------------

local heard = {} -- [sender] = { minute, count }
local early = {}  -- messages that came before the roster did, read once it is there
local OnMessage   -- below

local function TooMuch(who)
    local minute = math.floor(time() / 60)
    local h = heard[who]
    if not h or h[1] ~= minute then
        h = { minute, 0 }
        heard[who] = h
    end
    h[2] = h[2] + 1
    return h[2] > MOST_HEARD
end

local function Ask(text)
    if M.db.ask then ns.Alert(text) else ns.Print(text) end
end

local function OnAdd(who, id, dir, amount, at, note)
    if id:match("^(.-):%d+$") ~= (who:match("^([^-]+)") or who) then return end -- only the one who wrote a loan down can say it
    amount, at = tonumber(amount), tonumber(at)
    if dir ~= "L" and dir ~= "B" or not amount or amount < 1 or amount > MOST_GOLD * 10000 or amount % 1 ~= 0 or not at then return end
    local loan = ById(id, who)
    if loan then -- said again: answer again, they may have missed it
        if loan.agreed then
            Queue(loan, "Y")
        elseif loan.refused then
            Queue(loan, "N")
        end
        return
    end
    local d, claims = Data(), 0
    for _, l in ipairs(d.list) do
        if l.who == who and l.claim then claims = claims + 1 end
    end
    if claims >= MOST_CLAIMS or #d.list >= MOST_LOANS then return end
    loan = { n = d.next, id = id, who = who, lent = dir == "B", amount = amount, note = CleanNote(note),
        at = math.min(at, time()), claim = "add" }
    d.next = d.next + 1
    d.list[#d.list + 1] = loan
    Ask(who .. " wrote down that " .. Describe(loan) .. (loan.note ~= "" and (" (" .. loan.note .. ")") or "")
        .. ". /zod loans ok " .. loan.n .. " agrees, /zod loans no " .. loan.n .. " refuses.")
    ns.Refresh()
end

local function OnAnswer(who, kind, id)
    local loan = ById(id, who)
    if not loan then return end
    if kind == "Y" then
        if loan.mine and not loan.agreed and not loan.refused then
            loan.agreed = true
            Unqueue(loan, "A")
            ns.Print(who .. " agrees: " .. Describe(loan) .. ".")
        elseif loan.asked == "paid" then
            loan.asked, loan.paid, loan.paidAt = nil, true, time()
            Unqueue(loan, "P")
            ns.Print(who .. " agrees you paid back the " .. ns.Money(loan.amount, true) .. ".")
        end
    elseif kind == "N" then
        if loan.mine and not loan.agreed and not loan.refused then
            loan.refused = true
            Unqueue(loan, "A")
            ns.Print(who .. " says no to the loan: " .. Describe(loan) .. ".")
        elseif loan.asked == "paid" then
            loan.asked = nil
            Unqueue(loan, "P")
            ns.Print(who .. " says the " .. ns.Money(loan.amount, true) .. " is not paid back yet.")
        end
    elseif kind == "P" and not loan.paid and loan.agreed then
        if not loan.lent then -- the one who lent says it is paid: it is
            loan.paid, loan.paidAt, loan.asked = true, time(), nil
            Unqueue(loan, "A")
            Unqueue(loan, "P")
            ns.Print(who .. " says the " .. ns.Money(loan.amount, true) .. " you owed is paid back.")
        else
            loan.claim = "paid"
            Ask(who .. " says they paid back the " .. ns.Money(loan.amount, true) .. ". /zod loans ok " .. loan.n
                .. " agrees, /zod loans no " .. loan.n .. " says it is not.")
        end
    end
    ns.Refresh()
end

function OnMessage(text, sender)
    if type(text) ~= "string" or #text > 255 then return end
    local who = Short(sender)
    if not who or who == Me() then return end
    if next(roster) == nil then -- the roster is not in yet: keep a few to read when it is
        if #early < MOST_HEARD then early[#early + 1] = { text, sender } end
        return
    end
    if not InGuild(who) or TooMuch(who) then return end
    local version, kind, id, a, b, c, note = Split(text)
    if version ~= "1" or type(id) ~= "string" or #id > 64 or not id:find("^[^:~]+:%d+$") then return end
    if kind == "A" then
        OnAdd(who, id, a, b, c, note)
    elseif kind == "Y" or kind == "N" or kind == "P" then
        OnAnswer(who, kind, id)
    end
    Flush()
end

M:On("CHAT_MSG_ADDON", function(self, _, prefix, text, channel, sender)
    if prefix ~= PREFIX or channel ~= "WHISPER" or not self.db.share then return end
    if issecretvalue and (issecretvalue(text) or issecretvalue(sender)) then return end
    OnMessage(text, sender)
end)

M:On("GUILD_ROSTER_UPDATE", function()
    ScanRoster()
    if next(roster) ~= nil and #early > 0 then
        local waiting = early
        early = {}
        for _, m in ipairs(waiting) do OnMessage(m[1], m[2]) end
    end
    Flush()
    ns.Refresh()
end)
M:On("PLAYER_REGEN_ENABLED", function() Flush() end)

local function AskRoster()
    if IsInGuild and IsInGuild() and C_GuildInfo and C_GuildInfo.GuildRoster then C_GuildInfo.GuildRoster() end
end
ns.Every(ROSTER_EVERY, AskRoster, M)

function M:OnEnable()
    ScanRoster()
    AskRoster()
end

---------------------------------------------------------------------------
-- Trades: a gold-only trade with a guild member offers to write it down
---------------------------------------------------------------------------

local trade -- what the open trade holds once someone accepted

local function TradeHasItems()
    for i = 1, 7 do
        if (GetTradePlayerItemLink and GetTradePlayerItemLink(i)) or (GetTradeTargetItemLink and GetTradeTargetItemLink(i)) then return true end
    end
    return false
end

M:On("TRADE_SHOW", function() trade = { who = Short(UnitName("NPC")) } end)

M:On("TRADE_ACCEPT_UPDATE", function()
    if not trade then return end
    trade.gave = tonumber(GetPlayerTradeMoney and GetPlayerTradeMoney()) or 0
    trade.got = tonumber(GetTargetTradeMoney and GetTargetTradeMoney()) or 0
    trade.items = TradeHasItems()
    trade.before = GetMoney()
end)

local function OpenWith(who, lent, amount)
    for _, loan in ipairs(Data().list) do
        if loan.who == who and loan.lent == lent and loan.amount == amount and Open(loan) and loan.asked ~= "paid" then return loan end
    end
end

local function TradeDone(t)
    if not (M.enabled and M.db.trade) or t.items or not t.before or not t.who or not InGuild(t.who) then return end
    local moved = t.got - t.gave
    if moved == 0 or GetMoney() - t.before ~= moved then return end -- cancelled, or both gave gold
    local money = ns.Money(math.abs(moved), true)
    if moved < 0 then
        local loan = OpenWith(t.who, false, -moved)
        if loan then
            ns.Print("Paying " .. t.who .. " back? |cffffd100/zod loans paid " .. loan.n .. "|r says so.")
        else
            ns.Print("You gave " .. t.who .. " " .. money .. ". |cffffd100/zod loans lend " .. t.who .. " "
                .. ns.PlainMoney(-moved) .. "|r writes it down as a loan.")
        end
    else
        local loan = OpenWith(t.who, true, moved)
        if loan then
            ns.Print(t.who .. " paid you back " .. money .. "? |cffffd100/zod loans paid " .. loan.n .. "|r says so.")
        else
            ns.Print(t.who .. " gave you " .. money .. ". |cffffd100/zod loans borrow " .. t.who .. " "
                .. ns.PlainMoney(moved) .. "|r writes it down as a loan.")
        end
    end
end

M:On("TRADE_CLOSED", function()
    local t = trade
    trade = nil
    if t then ns.After(1, function() TradeDone(t) end) end -- the gold lands after the window closes
end)

---------------------------------------------------------------------------
-- /zod loans
---------------------------------------------------------------------------

local function Numbered(arg)
    local n = tonumber(arg)
    local loan = n and Find(n)
    if not loan then
        ns.Print("no loan " .. (arg ~= "" and arg or "number") .. ". /zod loans list shows them, with their numbers.")
        return
    end
    return loan
end

function M:Slash(arg)
    local verb, rest = arg:match("^(%S*)%s*(.-)$")
    verb = verb:lower()
    if verb == "" then
        ns.Show("loans")
    elseif verb == "lend" or verb == "borrow" then
        local who, after = rest:match("^(%S+)%s*(.-)$")
        local amount, note = ParseMoney(after or "")
        local loan, said = self:Add(verb == "lend", who, amount, note)
        if not loan then
            ns.Print(said .. " For example /zod loans " .. verb .. " Bob 5g for the mount.")
            return
        end
        ns.Print("loan " .. loan.n .. ": " .. Describe(loan) .. "."
            .. ((M.db.share and InGuild(loan.who)) and (" Waiting for " .. loan.who .. " to agree.") or ""))
    elseif verb == "ok" or verb == "no" or verb == "paid" then
        local loan = Numbered(rest)
        if not loan then return end
        local ok, said
        if verb == "ok" then ok, said = self:Agree(loan) elseif verb == "no" then ok, said = self:Refuse(loan) else ok, said = self:Paid(loan) end
        if not ok then ns.Print(said) return end
        if verb == "paid" and loan.asked == "paid" then
            ns.Print("asked " .. loan.who .. " to agree that you paid back " .. ns.Money(loan.amount, true) .. ".")
        else
            ns.Print("loan " .. loan.n .. ": " .. PlainState(loan) .. ".")
        end
    elseif verb == "forget" then
        local loan = Numbered(rest)
        if not loan then return end
        self:Forget(loan)
        ns.Print("forgot loan " .. loan.n .. ".")
    elseif verb == "list" then
        local list = Data().list
        if #list == 0 then ns.Print("no loans written down.") return end
        local owed, owe = self:Totals()
        ns.Print("owed to you " .. ns.Money(owed, true) .. ", you owe " .. ns.Money(owe, true) .. ":")
        for _, loan in ipairs(list) do
            print("  |cffffd100" .. loan.n .. "|r  " .. Describe(loan) .. (loan.note ~= "" and ("  |cff999999" .. loan.note .. "|r") or "")
                .. "  |cff999999" .. PlainState(loan) .. "|r")
        end
    else
        ns.Print("use /zod loans lend Bob 5g, borrow Bob 5g, list, paid 3, ok 3, no 3 or forget 3.")
    end
end


---------------------------------------------------------------------------
-- Home, hints, search and the page
---------------------------------------------------------------------------

function M:Card()
    local owed, owe, nOwed, nOwe, ask = self:Totals()
    if nOwed + nOwe + ask == 0 then return nil end
    local lines = {}
    if nOwed > 0 then lines[#lines + 1] = { "Owed to you", T.Paint(ns.Money(owed, true), T.GREEN) .. "  |cff999999" .. nOwed .. "|r" } end
    if nOwe > 0 then lines[#lines + 1] = { "You owe", T.Paint(ns.Money(owe, true), T.RED) .. "  |cff999999" .. nOwe .. "|r" } end
    if ask > 0 then lines[#lines + 1] = { "To answer", T.Paint(ask .. (ask == 1 and " loan" or " loans"), T.GOLD) } end
    return { title = "Loans", lines = lines, button = { "All", function() ns.Show("loans") end } }
end

function M:Hints(add)
    for _, loan in ipairs(Data().list) do
        if loan.claim then add(loan.who .. (loan.claim == "add" and " asks you to agree to a loan" or " says a loan is paid back"), 40, "loans") end
    end
end

function M:Find(part, add, has)
    for _, loan in ipairs(Data().list) do
        if has(loan.who) or (loan.note ~= "" and has(loan.note)) then add("Loan", loan.who, Describe(loan), "loans") end
    end
end

local message = ""

ns.AddPage({
    key = "loans", title = "Guild loans", order = 44, group = "Planning", module = "loans",
    Build = function(page, f)
        local w = ns.PAGE_W
        page.off = T.Text(f, "GameFontHighlightSmall", T.MUTED)
        page.off:SetPoint("TOPLEFT", 0, -4)
        page.off:SetText("The Guild loans module is off. Switch it on under Settings.")
        local body = CreateFrame("Frame", nil, f)
        body:SetAllPoints(f)
        page.body = body

        page.who = T.Edit(body, 140, 24)
        page.who:SetPoint("TOPLEFT", 0, 0)
        page.who.edit:SetMaxLetters(48)
        page.amount = T.Edit(body, 100, 24)
        page.amount:SetPoint("TOPLEFT", 146, 0)
        page.amount.edit:SetMaxLetters(20)
        page.note = T.Edit(body, 220, 24)
        page.note:SetPoint("TOPLEFT", 252, 0)
        page.note.edit:SetMaxLetters(NOTE_MOST)
        T.Placeholder(page.who, "Who")
        T.Placeholder(page.amount, "How much: 5g 20s")
        T.Placeholder(page.note, "A note, if you like")
        T.TabOrder(page.who, page.amount, page.note)
        page.who.edit:SetScript("OnEnterPressed", function() page.amount.edit:SetFocus() end)
        page.amount.edit:SetScript("OnEnterPressed", function() page.note.edit:SetFocus() end)
        page.note.edit:SetScript("OnEnterPressed", function(self)
            self:ClearFocus()
            message = "Now click I lent or I borrowed."
            page:Refresh()
        end)
        local function Submit(lent)
            local amount = ParseMoney(page.amount.edit:GetText() or "")
            local loan, said = M:Add(lent, page.who.edit:GetText(), amount, page.note.edit:GetText())
            if loan then
                message = "Loan " .. loan.n .. ": " .. Describe(loan) .. "."
                page.who.edit:SetText("")
                page.amount.edit:SetText("")
                page.note.edit:SetText("")
            else
                message = said
            end
            page:Refresh()
        end
        local lend = T.Button(body, "I lent", 110, function() Submit(true) end)
        lend:SetPoint("TOPLEFT", 478, 0)
        local borrow = T.Button(body, "I borrowed", 110, function() Submit(false) end)
        borrow:SetPoint("TOPLEFT", 594, 0)
        page.said = T.Text(body, "GameFontHighlightSmall", T.DIM)
        page.said:SetPoint("TOPLEFT", 0, -32)
        page.said:SetWidth(w)
        page.said:SetJustifyH("LEFT")

        page.list = T.Table(body, { { "#", 36 }, { "Who", 120 }, { "Amount", 110, "RIGHT" }, { "Note", w - 36 - 120 - 110 - 80 - 160 },
            { "Since", 80, "RIGHT" }, { "State", 160, "RIGHT" } }, w, ns.PAGE_H - 88)
        page.list:SetPoint("TOPLEFT", 0, -54)
        page.list.onClick = function(n)
            page.list.selected = n
            page:Refresh()
        end
        local function Act(fn)
            return function()
                local loan = page.list.selected and Find(page.list.selected)
                if not loan then return end
                local ok, said = fn(M, loan)
                message = (ok == false and said) or ""
                if fn == M.Forget then page.list.selected = nil end
                page:Refresh()
            end
        end
        -- Right-click on a loan: paid back, at once.
        page.list.onRightClick = function(n)
            local loan = Find(n)
            if loan then
                local ok, said = M:Paid(loan)
                message = (ok == false and said) or ""
            end
            page:Refresh()
        end
        local x = 0
        page.acts = {}
        for _, spec in ipairs({ { "Paid back", M.Paid }, { "Agree", M.Agree }, { "Refuse", M.Refuse }, { "Forget", M.Forget } }) do
            local b = T.Button(body, spec[1], 90, Act(spec[2]))
            b:SetPoint("BOTTOMLEFT", x, 0)
            if spec[2] == M.Forget then b.confirm = "Sure?" end
            page.acts[#page.acts + 1] = b
            x = x + 96
        end
        page.hint = T.Text(body, "GameFontHighlightSmall", T.MUTED)
        page.hint:SetPoint("BOTTOMLEFT", x + 4, 6)
        page.hint:SetWidth(540 - (x + 4) - 8) -- ends before "Forget the paid ones"
        page.hint:SetWordWrap(false)
        local clear = T.Button(body, "Forget the paid ones", 170, function()
            M:ForgetPaid()
            page.list.selected = nil
            message = ""
            page:Refresh()
        end)
        clear:SetPoint("BOTTOMRIGHT", 0, 0)
        clear.confirm = "Sure? Click again"
    end,
    Refresh = function(page)
        local on = M.enabled
        page.off:SetShown(not on)
        page.body:SetShown(on)
        if not on then return end
        local owed, owe = M:Totals()
        page.said:SetText(message ~= "" and message or ("Owed to you " .. ns.Money(owed, true) .. ", you owe " .. ns.Money(owe, true)
            .. ". A name, an amount (5g, 50s) and a note, then who lent it."))
        local rows = {}
        local list = {}
        for _, loan in ipairs(Data().list) do list[#list + 1] = loan end
        table.sort(list, function(a, b)
            if Open(a) ~= Open(b) then return Open(a) end
            return a.n > b.n
        end)
        for _, loan in ipairs(list) do
            local amount = ns.Money(loan.amount, true)
            if Open(loan) then amount = T.Paint((loan.lent and "+" or "-"), loan.lent and T.GREEN or T.RED) .. amount end
            rows[#rows + 1] = { tostring(loan.n), loan.who, amount, loan.note or "", ns.WhenCell(loan.at, true), State(loan), data = loan.n }
        end
        page.list:SetRows(rows, "No loans written down yet.")
        page.hint:SetText(page.list.selected and "" or "Click a loan to pick it.")
        for _, b in ipairs(page.acts) do T.Off(b, page.list.selected == nil, "Click a loan in the list first, or right-click one: paid back at once.") end
        if page.list.selected then page.acts[1].tip = "Or right-click a loan in the list: paid back at once." end
    end,
})
