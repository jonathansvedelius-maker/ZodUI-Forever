local ADDON, ns = ...
local T = ns.T

-- The Commands page: every /zod command as buttons, so nothing needs typing in chat.
-- A row is a line of text, an optional field and its buttons; a button runs
-- "/zod <cmd> <what is in the field>" through the same handler as chat, so the
-- page and the chat command can never do different things. What the command
-- prints is shown at the foot of the page too.
--
-- A row: { label, field = "hint" | nil, need = true when the field must be filled,
--          buttons = { { text, cmd }, ... } }

local ROW_H, HEAD_H, LABEL_W, FIELD_W, BUTTON_W, GAP = 28, 26, 230, 210, 92, 6
local OUT_H, OUT_LINES = 104, 6

ns.ACTIONS = {
    { title = "ZodUI", rows = {
        { "Today's report", buttons = { { "Show", "report" }, { "Party", "report party" }, { "Guild", "report guild" } } },
        { "Where you stand", buttons = { { "Show", "where" }, { "Party", "where party" }, { "Guild", "where guild" } } },
        { "Time played on all characters", buttons = { { "Show", "played" } } },
        { "Notices", buttons = { { "The last ones", "notices" }, { "Sample", "test" } } },
        { "Errors since login", buttons = { { "Show", "errors" }, { "Forget", "errors clear" } } },
        { "What ZodUI itself costs while you play", buttons = { { "Start", "perf start" }, { "Show", "perf" }, { "Stop", "perf stop" } } },
        { "Modules", buttons = { { "List", "modules" }, { "Version", "version" }, { "What's new", "news" } } },
        { "Safe mode: every module off", buttons = { { "On", "safe" }, { "Off", "safe off" } } },
        { "Move the notices and bars", buttons = { { "Unlock", "unlock" }, { "Lock", "lock" }, { "Reset", "reset" } } },
        { "Your settings as text", buttons = { { "Export", "export" }, { "Import", "import" } } },
        { "Search ZodUI", field = "words", need = true, buttons = { { "Search", "find" } } },
        { "Reload the interface", buttons = { { "Reload", "reload" } } },
    } },
    { title = "Guild network", module = "guild", rows = {
        { "Who in your guild runs ZodUI", buttons = { { "Ask", "guild" }, { "List", "guild list" } } },
        { "Rares and world bosses seen", buttons = { { "Show", "guild rares" } } },
        { "Waypoint to rare number", field = "1", buttons = { { "Set", "guild way" } } },
        { "Who has a quest", field = "shift-click a quest", need = true, buttons = { { "Ask", "guild quest" } } },
        { "This week's leaderboard", buttons = { { "Ask", "top" } } },
    } },
    { title = "Crafters", module = "crafters", rows = {
        { "Who knows a recipe", field = "shift-click a recipe", need = true, buttons = { { "Ask", "crafters" } } },
        { "Recipes asked about", buttons = { { "List", "crafters list" }, { "Sample", "crafters test" } } },
    } },
    { title = "Raid planner", module = "raids", rows = {
        { "Who to ask along", buttons = { { "Show", "raids group" }, { "Attendance", "raids attendance" } } },
        { "Invite the ones you ran with most", field = "4", buttons = { { "Invite", "raids invite" } } },
    } },
    { title = "Dungeon prep", module = "prep", rows = {
        { "Your quests for a dungeon", field = "empty: the one you are in", buttons = { { "Show", "prep" } } },
        { "Offer your dungeon quests to the group", buttons = { { "Share", "prep share" } } },
    } },
    { title = "Dungeons", module = "runs", rows = {
        { "When you last ran with someone", field = "name", need = true, buttons = { { "Look", "runs with" } } },
        { "A note on a player", field = "Bob good tank", need = true, buttons = { { "Keep", "runs note" } } },
    } },
    { title = "Vendor", module = "vendor", rows = {
        { "An item", field = "shift-click an item", need = true,
          buttons = { { "Always sell", "vendor sell" }, { "Never sell", "vendor keep" }, { "Forget", "vendor forget" } } },
        { "Items with a rule", buttons = { { "List", "vendor list" } } },
    } },
    { title = "Chat", module = "chat", rows = {
        { "Watch for a word", field = "word", buttons = { { "Watch", "chat watch" }, { "Stop", "chat unwatch" } } },
        { "Since login", buttons = { { "Whispers", "chat whispers" }, { "Mentions", "chat mentions" } } },
    } },
    { title = "Reminders", module = "remind", rows = {
        { "A reminder", field = "20 check the auction", need = true, buttons = { { "Add", "remind" } } },
        { "Your reminders", buttons = { { "List", "remind list" }, { "Snooze", "remind snooze" }, { "Clear", "remind clear" } } },
    } },
    { title = "Goals", module = "goals", rows = {
        { "A goal", field = "60 linen cloth, level 30", need = true, buttons = { { "Add", "goals" } } },
    } },
    { title = "Guild loans", module = "loans", rows = {
        { "A loan", field = "Bob 5g", need = true, buttons = { { "I lent", "loans lend" }, { "I borrowed", "loans borrow" } } },
        { "Your loans", buttons = { { "List", "loans list" } } },
    } },
    { title = "Travel", module = "travel", rows = {
        { "Hearthstone, route and portals now", field = "a city, or empty", buttons = { { "Show", "travel" } } },
    } },
    { title = "Chat board", module = "board", rows = {
        { "Who offered a service", field = "crusader, lockpicking", need = true, buttons = { { "Look", "board" } } },
    } },
    { title = "Group match", module = "groups", rows = {
        { "A sample notice", buttons = { { "Try", "groups test" } } },
    } },
    { title = "Group listings", module = "listings", rows = {
        { "List your group, or you, on every layer", field = "a dungeon and roles: sfk tank heal", need = true, buttons = { { "List", "lfg" } } },
        { "Listings from every layer", buttons = { { "Show", "lfg" }, { "Take mine down", "lfg stop" } } },
    } },
    { title = "Dungeon guide", module = "guide", rows = {
        { "The map with the route through it", field = "a dungeon (empty: this one)", buttons = { { "Show", "guide" } } },
        { "Where you are in the run", buttons = { { "Back", "guide back" }, { "Next", "guide next" }, { "Start over", "guide reset" } } },
        { "Draw the route yourself", buttons = { { "Draw", "guide draw" }, { "Undo all", "guide clear" } } },
        { "Share your route", buttons = { { "Copy out", "guide export" }, { "Paste in", "guide import" } } },
    } },
    { title = "Healer mode", module = "healer", rows = {
        { "Your healing set", field = "an equipment set's name", need = true, buttons = { { "Use", "healer set" } } },
        { "The set to go back to", field = "a set's name, or none", buttons = { { "Use", "healer back" } } },
        { "Heal in this group", buttons = { { "Heal", "healer heal" }, { "Done", "healer solo" } } },
        { "Your sets and what is chosen", buttons = { { "Show", "healer" } } },
    } },
    { title = "Loot rules", module = "lootrules", rows = {
        { "Say the loot rules to your group", buttons = { { "Say", "rules" } } },
        { "Who rolled Need on BoE against them", buttons = { { "List", "rules log" } } },
    } },
    { title = "Loot", module = "shout", rows = {
        { "What Loot shout would say", field = "an item, or empty", buttons = { { "Try", "shout test" } } },
        { "Loot rolls", module = "rolls", buttons = { { "Sample", "rolls test" }, { "Forget", "rolls clear" } } }, -- its own module
    } },
    { title = "Hand-me-downs", module = "handouts", rows = {
        { "Gear in your bags for your other characters", buttons = { { "List", "handouts" } } },
    } },
    { title = "Recap", module = "recap", rows = {
        { "Your week in numbers", buttons = { { "Show", "recap" }, { "Guild", "recap guild" } } },
        { "What waits for you", buttons = { { "Show", "recap plan" } } },
    } },
    { title = "This character", rows = {
        { "Your story as text", field = "days", buttons = { { "Export", "story export" } } },
        { "Leveling pace", buttons = { { "Coach", "coach" } } },
        { "Hunter pets", buttons = { { "Show", "pet" } } },
        { "Hardcore deaths announced", buttons = { { "Show", "deaths hardcore" } } },
    } },
}

-- What the last command said; the page shows the end of it.
local said = {}

local function Clean(line)
    line = tostring(line):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    line = line:gsub("|H.-|h(.-)|h", "%1")
    return (line:gsub("^ZodUI: ", ""))
end

-- Runs "/zod <text>" and keeps what it printed. print is lent out only while the
-- command runs, and put back even when the command fails.
function ns.RunCommand(text)
    local run = SlashCmdList and SlashCmdList["ZODUI"]
    if not run then return end
    local real = print
    local lines = {}
    print = function(...)
        local parts = {}
        for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
        lines[#lines + 1] = Clean(table.concat(parts, " "))
        return real(...)
    end
    local ok, err = pcall(run, text)
    print = real
    if not ok then ns.Guard("command " .. text, error, err) end
    said = lines
    if ns.pages.commands and ns.pages.commands.frame and ns.pages.commands.frame:IsVisible() then
        ns.pages.commands:Refresh()
    end
    return lines
end

-- Shift-clicking an item, recipe or quest while a field on this page has the focus
-- puts its link there, as it would in the chat box.
local fields = {}
local lastLink, lastAt
local function InsertLink(link)
    if type(link) ~= "string" then return end
    for _, e in ipairs(fields) do
        if e:IsVisible() and e:HasFocus() then
            if lastLink == link and lastAt == GetTime() then return end
            lastLink, lastAt = link, GetTime()
            e:Insert(link)
            return
        end
    end
end
if type(ChatEdit_InsertLink) == "function" and hooksecurefunc then
    hooksecurefunc("ChatEdit_InsertLink", InsertLink)
end
ns.CommandLink = InsertLink -- for the tests

local function Head(page, child, y, section)
    local head = T.Text(child, "GameFontNormal", T.GOLD)
    head:SetPoint("TOPLEFT", 0, -y - 6)
    head:SetText(section.title)
    page.heads[#page.heads + 1] = { text = head, section = section }
    return y + HEAD_H
end

local function Row(page, child, y, row)
    local label = T.Text(child, "GameFontHighlightSmall", T.TEXT)
    label:SetPoint("TOPLEFT", 8, -y - 7)
    label:SetWidth(LABEL_W - 8)
    label:SetJustifyH("LEFT")
    label:SetText(row[1])
    local x = LABEL_W
    local field
    if row.field then
        field = T.Edit(child, FIELD_W, 24)
        field:SetPoint("TOPLEFT", x, -y)
        field.edit:SetMaxLetters(255)
        field.hint = T.Text(field, "GameFontHighlightSmall", T.MUTED)
        field.hint:SetPoint("LEFT", 8, 0)
        field.hint:SetText(row.field)
        local e = field.edit
        local function Hint() field.hint:SetShown((e:GetText() or "") == "" and not e:HasFocus()) end
        e:HookScript("OnTextChanged", Hint)
        e:HookScript("OnEditFocusGained", Hint)
        e:HookScript("OnEditFocusLost", Hint)
        fields[#fields + 1] = e
        x = x + FIELD_W + GAP
    end
    local first
    -- The buttons share what is left of the row: narrower than usual when there are many after a field.
    local count = #row.buttons
    local bw = math.min(BUTTON_W, math.floor((ns.PAGE_W - 8 - x - GAP * (count - 1)) / math.max(1, count)))
    for _, spec in ipairs(row.buttons) do
        local b = T.Button(child, spec[1], bw, nil)
        b:SetPoint("TOPLEFT", x, -y)
        b.cmd, b.field = spec[2], field and field.edit
        b.module = row.module -- a row of another module than its section's
        b.tipTitle = "/zod " .. spec[2] .. (row.field and (" <" .. row.field .. ">") or "")
        b.tip, b.plainTip = row[1], row[1]
        b:SetScript("OnClick", function(self)
            if self.off then -- its module is off: say so instead of running a command that does nothing
                said = { "Switch " .. (self.offName or "its module") .. " on under Settings first." }
                page:Refresh()
                return
            end
            local extra = field and (field.edit:GetText() or ""):gsub("^%s+", ""):gsub("%s+$", "") or ""
            if row.need and extra == "" then
                said = { "Fill in the field first: " .. row.field .. "." }
                page:Refresh()
                return
            end
            ns.RunCommand(spec[2] .. (extra ~= "" and (" " .. extra) or ""))
            if field and row.need then field.edit:SetText("") end
        end)
        page.buttons[#page.buttons + 1] = b
        first = first or b
        x = x + bw + GAP
    end
    if field then
        field.edit:SetScript("OnEnterPressed", function(self)
            self:ClearFocus()
            first:GetScript("OnClick")(first)
        end)
    end
    return y + ROW_H
end

-- Another addon's command (ZodUI.api.AddCommand) gets a row under Plugins, also
-- when the page is already built.
function ns.AddAction(title, row)
    local section
    for _, s in ipairs(ns.ACTIONS) do
        if s.title == title then section = s end
    end
    local new = not section
    if new then
        section = { title = title, rows = {} }
        ns.ACTIONS[#ns.ACTIONS + 1] = section
    end
    section.rows[#section.rows + 1] = row
    local page = ns.pages.commands
    if page and page.child then
        if new then page.y = Head(page, page.child, page.y, section) end
        local before = #page.buttons
        page.y = Row(page, page.child, page.y, row)
        for k = before + 1, #page.buttons do page.buttons[k].section = section end
        page.child:SetHeight(page.y)
    end
end

ns.AddPage({
    key = "commands", title = "Commands", order = 98, group = "ZodUI",
    Build = function(page, f)
        local w, h = ns.PAGE_W, ns.PAGE_H
        page.heads, page.buttons = {}, {}
        local scroll, child = T.Scroll(f)
        scroll:SetPoint("TOPLEFT", 0, 0)
        scroll:SetSize(w, h - OUT_H - 8)
        child:SetWidth(w - 8)
        local y = 0
        for _, section in ipairs(ns.ACTIONS) do
            y = Head(page, child, y, section)
            for _, row in ipairs(section.rows) do
                local before = #page.buttons
                y = Row(page, child, y, row)
                for k = before + 1, #page.buttons do page.buttons[k].section = section end
            end
            y = y + 4
        end
        child:SetHeight(y)
        page.scroll, page.child, page.y = scroll, child, y

        local out = T.Panel(f, T.SURFACE)
        out:SetPoint("BOTTOMLEFT", 0, 0)
        out:SetSize(w, OUT_H)
        page.out = T.Text(out, "GameFontHighlightSmall", T.TEXT)
        page.out:SetPoint("TOPLEFT", 8, -8)
        page.out:SetPoint("BOTTOMRIGHT", -8, 8)
        page.out:SetJustifyH("LEFT")
        page.out:SetJustifyV("TOP")
    end,
    Refresh = function(page)
        for _, head in ipairs(page.heads) do
            local m = head.section.module and ns.modules[head.section.module]
            local off = m and not m.enabled
            head.text:SetText(head.section.title .. (off and "  |cff999999(off: switch it on under Settings)|r" or ""))
        end
        -- A section's buttons are greyed while its module is off.
        for _, b in ipairs(page.buttons) do
            local key = b.module or (b.section and b.section.module)
            local m = key and ns.modules[key]
            local off = m and not m.enabled or false
            b.offName = m and m.title
            if off then
                T.Off(b, true, "The " .. m.title .. " module is off. Switch it on under Settings.")
            elseif b.off then
                T.Off(b, false)
                b.tip = b.plainTip
            end
        end
        local shown = {}
        for i = math.max(1, #said - OUT_LINES + 1), #said do shown[#shown + 1] = said[i] end
        page.out:SetText(#shown > 0 and table.concat(shown, "\n")
            or "|cff999999Press a button. What the command says shows here, and in chat. A field takes typing, or a shift-clicked item, recipe or quest.|r")
        page.scroll:Sync()
    end,
})
