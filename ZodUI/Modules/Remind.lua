local ADDON, ns = ...
local T = ns.T

-- Reminders: "in 20 minutes: check the auction". Shared by all characters,
-- and one that came due while you were logged out is said after login.
-- A repeating one (entry.every, in minutes) is set again when it rings.

local M = ns:NewModule("remind", {
    title = "Reminders",
    desc = "Set a reminder for some minutes from now, for a time of day, for your next login, or one that repeats, here or with /zod remind 20 check the auction. All characters share them, and one that came due while you were away is said when you log in.",
    defaults = { enabled = true, sound = true },
    options = {
        { type = "check", key = "sound", label = "Play a sound with the reminder" },
    },
})

local MOST = 7 * 24 * 60 -- minutes
local MAX_LEN = 80
local SETTLE = 5 -- seconds after login before anything is said
local SNOOZE = 10 -- minutes
local message = ""
local repeatOn = false
local since

local function List()
    local list = ns.db.reminders
    if not list then
        list = {}
        ns.db.reminders = list
    end
    return list
end

-- Returns whether it worked and what to say.
local function Sort(list)
    table.sort(list, function(a, b) return a.at < b.at end)
end

-- every: true makes it ring again each `minutes`.
function M:Add(minutes, text, every)
    minutes = math.floor(tonumber(minutes) or 0)
    text = (text or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if minutes < 1 or minutes > MOST then return false, "The minutes must be between 1 and " .. ns.Comma(MOST) .. " (a week)." end
    if text == "" then return false, "Type what to be reminded of." end
    local list = List()
    list[#list + 1] = { text = text:sub(1, MAX_LEN), at = time() + minutes * 60, every = every and minutes or nil }
    Sort(list)
    ns.Refresh()
    return true, "In " .. ns.Duration(minutes * 60) .. ": " .. text:sub(1, MAX_LEN) .. (every and (", then every " .. ns.Duration(minutes * 60)) or "")
end

-- A reminder for the next login (or reload) on any character.
function M:AddLogin(text)
    text = (text or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if text == "" then return false, "Type what to be reminded of." end
    local list = List()
    list[#list + 1] = { text = text:sub(1, MAX_LEN), at = time() + MOST * 60, login = true }
    Sort(list)
    ns.Refresh()
    return true, "Next time you log in: " .. text:sub(1, MAX_LEN)
end

-- The ones that rang ring again in `minutes`. Returns how many.
function M:Snooze(minutes)
    local list, n = List(), 0
    for _, entry in ipairs(list) do
        if entry.due then
            entry.due, entry.at = nil, time() + (minutes or SNOOZE) * 60
            n = n + 1
        end
    end
    Sort(list)
    ns.Refresh()
    return n
end

-- Minutes from now until the clock next reads hour:minute.
local function Until(hour, minute)
    local now = tonumber(date("%H")) * 3600 + tonumber(date("%M")) * 60 + tonumber(date("%S"))
    local left = hour * 3600 + minute * 60 - now
    if left <= 0 then left = left + 86400 end
    return math.ceil(left / 60)
end

function M:Remove(entry)
    local list = List()
    for i = #list, 1, -1 do
        if list[i] == entry then table.remove(list, i) end
    end
    ns.Refresh()
end

-- /zod remind 20 check the auction
-- /zod remind 21:30 raid, /zod remind every 30 stretch, /zod remind snooze
function M:Slash(arg)
    local word = arg:lower():match("^(%S*)")
    if word == "list" then
        local list = List()
        if #list == 0 then
            ns.Print("no reminders.")
        else
            ns.Print("reminders:")
            for _, entry in ipairs(list) do
                print("  " .. (entry.due and "|cffffd100now|r" or (entry.login and "next login" or ("in " .. ns.Duration(entry.at - time()))))
                    .. "  " .. entry.text)
            end
        end
        return
    elseif word == "clear" then
        local list, n = List(), 0
        for i = #list, 1, -1 do
            if list[i].due then
                table.remove(list, i)
                n = n + 1
            end
        end
        ns.Refresh()
        ns.Print(n == 0 and "no reminder has rung." or ("removed " .. n .. (n == 1 and " reminder that rang." or " reminders that rang.")))
        return
    elseif word == "login" then
        local _, said = self:AddLogin(arg:match("^%S+%s*(.*)$"))
        ns.Print(said)
        return
    end
    if arg:lower():match("^snooze%s*$") then
        local n = self:Snooze(SNOOZE)
        ns.Print(n == 0 and "Nothing rang." or (n .. (n == 1 and " reminder" or " reminders") .. " snoozed " .. SNOOZE .. " minutes."))
        return
    end
    local hour, minute, what = arg:match("^(%d%d?):(%d%d)%s+(.+)$")
    if hour and tonumber(hour) < 24 and tonumber(minute) < 60 then
        local ok, said = self:Add(Until(tonumber(hour), tonumber(minute)), what)
        ns.Print(said .. (ok and string.format(" (at %02d:%02d)", hour, minute) or ""))
        return
    end
    local every
    every, what = arg:match("^[Ee]very%s+(%d+)%s+(.+)$")
    if every then
        local _, said = self:Add(every, what, true)
        ns.Print(said)
        return
    end
    local minutes, text = arg:match("^(%d+)%s+(.+)$")
    if not minutes then
        ns.Print("use /zod remind <minutes> <what>, for example /zod remind 20 check the auction. Also /zod remind 21:30 raid, "
            .. "/zod remind every 30 stretch and /zod remind snooze.")
        return
    end
    local _, said = self:Add(minutes, text)
    ns.Print(said)
end

function M:OnEnable()
    since = GetTime()
    for _, entry in ipairs(List()) do
        if entry.login and not entry.due then entry.at = time() end -- rings once the login has settled
    end
    Sort(List())
end

ns.Every(1, function()
    if not since or GetTime() - since < SETTLE then return end
    local now, fired = time(), false
    for _, entry in ipairs(List()) do
        if not entry.due and now >= entry.at then
            fired = true
            if entry.every then
                entry.at = now + entry.every * 60 -- counted from now: one missed while away rings once, not once per round
            else
                entry.due = true
            end
            ns.Alert("Reminder: " .. entry.text)
        end
    end
    if fired then
        Sort(List())
        if M.db.sound and PlaySound then pcall(PlaySound, SOUNDKIT and SOUNDKIT.TELL_MESSAGE or 3081) end
        ns.Refresh()
    end
end, M)

local function When(entry)
    if entry.due then return T.Paint("now", T.GOLD) end
    if entry.login and entry.at > time() then return "next login" end
    return "in " .. ns.Duration(entry.at - time())
end

local function Every(entry)
    return entry.every and ("every " .. ns.Duration(entry.every * 60)) or nil
end

function M:Find(part, add, has)
    for _, entry in ipairs(List()) do
        if has(entry.text) then
            local every = Every(entry)
            add("Reminder", entry.text, (entry.due and "rang" or When(entry)) .. (every and (", " .. every) or ""), "remind")
        end
    end
end

function M:Card()
    local list = List()
    if #list == 0 then return nil end -- no reminders, no card
    local lines = {}
    for i = 1, math.min(4, #list) do lines[i] = { list[i].text, When(list[i]) } end
    return { title = "Reminders", lines = lines, button = { "All", function() ns.Show("remind") end } }
end

ns.AddPage({
    key = "remind", title = "Reminders", order = 41, group = "Planning", module = "remind",
    Build = function(page, f)
        local w = ns.PAGE_W
        page.off = T.Text(f, "GameFontHighlightSmall", T.MUTED)
        page.off:SetPoint("TOPLEFT", 0, -4)
        page.off:SetText("The Reminders module is off. Switch it on under Settings.")
        local body = CreateFrame("Frame", nil, f)
        body:SetAllPoints(f)
        page.body = body

        page.minutes = T.Edit(body, 60, 24)
        page.minutes:SetPoint("TOPLEFT", 0, 0)
        page.minutes.edit:SetMaxLetters(5)
        page.minutes.edit:SetText("15")
        page.unit = T.Text(body, "GameFontHighlightSmall", T.DIM)
        page.unit:SetPoint("LEFT", page.minutes, "RIGHT", 6, 0)
        page.unit:SetText("minutes:")
        page.text = T.Edit(body, w - 350, 24)
        page.text:SetPoint("TOPLEFT", 126, 0)
        page.text.edit:SetMaxLetters(MAX_LEN)
        T.Placeholder(page.text, "What to remind you of")
        T.TabOrder(page.minutes, page.text)
        page.again = T.Check(body, "Repeat", 80, function(on) repeatOn = on end)
        page.again:SetPoint("TOPLEFT", w - 214, -2)
        page.again.tip = "Ring again every so many minutes"
        local function Submit()
            local ok, said = M:Add(page.minutes.edit:GetText(), page.text.edit:GetText(), repeatOn)
            message = ok and "" or said
            if ok then page.text.edit:SetText("") end
            page:Refresh()
        end
        page.text.edit:SetScript("OnEnterPressed", Submit)
        page.minutes.edit:SetScript("OnEnterPressed", Submit)
        local add = T.Button(body, "Remind me", 124, Submit)
        add:SetPoint("TOPLEFT", w - 124, 0)
        page.said = T.Text(body, "GameFontHighlightSmall", T.DIM)
        page.said:SetPoint("TOPLEFT", 0, -32)
        page.said:SetWidth(w)
        page.said:SetJustifyH("LEFT")

        page.list = T.Table(body, { { "What", w - 240 }, { "At", 100, "RIGHT" }, { "When", 120, "RIGHT" } }, w, ns.PAGE_H - 88)
        page.list:SetPoint("TOPLEFT", 0, -54)
        page.list.onClick = function(entry)
            page.list.selected = entry
            page:Refresh()
        end
        page.list.onRightClick = function(entry) -- right-click: gone at once
            M:Remove(entry)
            if page.list.selected == entry then page.list.selected = nil end
            page:Refresh()
        end
        page.remove = T.Button(body, "Remove this one", 150, function()
            if page.list.selected then
                M:Remove(page.list.selected)
                page.list.selected = nil
                page:Refresh()
            end
        end)
        page.remove:SetPoint("BOTTOMLEFT", 0, 0)
        page.clear = T.Button(body, "Remove the ones that rang", 200, function()
            local list = List()
            for i = #list, 1, -1 do
                if list[i].due then table.remove(list, i) end
            end
            page.list.selected = nil
            page:Refresh()
        end)
        page.clear:SetPoint("LEFT", page.remove, "RIGHT", 6, 0)
        page.snooze = T.Button(body, "Snooze them " .. SNOOZE .. " min", 160, function()
            M:Snooze(SNOOZE)
            page.list.selected = nil
            page:Refresh()
        end)
        page.snooze:SetPoint("LEFT", page.clear, "RIGHT", 6, 0)
    end,
    Refresh = function(page)
        local on = M.enabled
        page.off:SetShown(not on)
        page.body:SetShown(on)
        if not on then return end
        page.again:SetChecked(repeatOn)
        page.said:SetText(message ~= "" and message
            or "Type the minutes and what to be reminded of. /zod remind 20 check the auction does the same; 21:30 sets a time of day.")
        local rows = {}
        for _, entry in ipairs(List()) do
            local every = Every(entry)
            local at = (entry.login and entry.at > time()) and "-" or date("%H:%M", entry.at)
            rows[#rows + 1] = { entry.text .. (every and ("  |cff999999" .. every .. "|r") or ""), at, When(entry), data = entry }
        end
        page.list:SetRows(rows, "No reminders.")
        T.Off(page.remove, page.list.selected == nil, "Click a reminder in the list first, or right-click one to remove it straight away.")
    end,
})

function M:Hints(add)
    for _, entry in ipairs(List()) do
        if entry.due then add("Reminder: " .. entry.text, 90, "remind") end
    end
end
