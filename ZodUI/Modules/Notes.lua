local ADDON, ns = ...
local T = ns.T

-- To do: a list to tick off, one for this character and one shared by all.
-- A daily one is unticked again the day after it was ticked.

local M = ns:NewModule("notes", {
    title = "To do",
    desc = "A to-do list you tick off: one list for this character and one shared by all your characters. A daily one comes back unticked the next day.",
    defaults = { enabled = true },
})

local ROW_H, MAX_LEN = 24, 120
local scope = "char"

local function List(which)
    if which == "char" then
        ns.chardb.notes = ns.chardb.notes or {}
        return ns.chardb.notes
    end
    ns.db.notes = ns.db.notes or {}
    return ns.db.notes
end

local function Week()
    return date("%Y-%W")
end

function M:Add(text, which, daily, weekly)
    text = (text or ""):gsub("|", ""):gsub("^%s+", ""):gsub("%s+$", "")
    if text == "" then return false end
    table.insert(List(which or scope), { text = text:sub(1, MAX_LEN), daily = daily and true or nil, weekly = weekly and true or nil })
    ns.Refresh()
    return true
end

-- A daily one ticked on an earlier day is open again.
local function Roll()
    local today = ns.Today()
    for _, which in ipairs({ "char", "account" }) do
        for _, note in ipairs(List(which)) do
            if note.daily and note.done and note.day ~= today then note.done, note.day = nil, nil end
            if note.weekly and note.done and note.week ~= Week() then note.done, note.week = nil, nil end
        end
    end
end

function M:Find(part, add, has)
    Roll()
    for _, which in ipairs({ "char", "account" }) do
        for _, note in ipairs(List(which)) do
            if has(note.text) then
                add("To do", note.text, note.done and "done" or (note.daily and "daily") or (note.weekly and "weekly")
                    or (which == "char" and "this character" or "all characters"),
                    "notes")
            end
        end
    end
end

function M:Card()
    Roll()
    local lines = {}
    for _, which in ipairs({ "char", "account" }) do
        for _, note in ipairs(List(which)) do
            if not note.done and #lines < 4 then lines[#lines + 1] = { note.text, "" } end
        end
    end
    if #lines == 0 then lines[1] = { "Nothing left to do.", "" } end
    return { title = "To do", lines = lines, button = { "Open", function() ns.Show("notes") end } }
end

ns.AddPage({
    key = "notes", title = "To do", order = 40, group = "Planning", module = "notes",
    Build = function(page, f)
        local w = ns.PAGE_W
        page.off = T.Text(f, "GameFontHighlightSmall", T.MUTED)
        page.off:SetPoint("TOPLEFT", 0, -4)
        page.off:SetText("The To do module is off. Switch it on under Settings.")

        page.body = CreateFrame("Frame", nil, f)
        page.body:SetAllPoints(f)
        local body = page.body
        page.tabs = {}
        scope = M.db.scope == "account" and "account" or "char" -- kept across /reload
        for i, tab in ipairs({ { "char", "This character" }, { "account", "All characters" } }) do
            local b = T.Button(body, tab[2], 140, function()
                scope = tab[1]
                M.db.scope = scope ~= "char" and scope or nil
                page:Refresh()
            end)
            b:SetPoint("TOPLEFT", (i - 1) * 146, 0)
            b.scope = tab[1]
            b.count = T.Text(b, "GameFontHighlightSmall", T.MUTED)
            b.count:SetPoint("RIGHT", -8, 0)
            page.tabs[i] = b
        end

        page.input = T.Edit(body, w - 318, 24) -- 6 px to Add, as between the buttons
        page.input:SetPoint("TOPLEFT", 0, -34)
        local function Submit(daily, weekly)
            local text = page.input.edit:GetText()
            if page.editing then -- Edit put this line in the box: the change replaces it
                local clean = (text or ""):gsub("|", ""):gsub("^%s+", ""):gsub("%s+$", "")
                if clean ~= "" then
                    page.editing.text = clean:sub(1, MAX_LEN)
                    page.editing = nil
                    page.input.edit:SetText("")
                    page:Refresh()
                end
                return
            end
            if M:Add(text, nil, daily == true, weekly == true) then page.input.edit:SetText("") end
        end
        page.input.edit:SetMaxLetters(MAX_LEN)
        page.input.edit:SetScript("OnEnterPressed", function() Submit(false) end)
        -- Escape while editing a line calls the edit off: the line stays as it was.
        page.input.edit:SetScript("OnEscapePressed", function(self)
            if page.editing then
                page.editing = nil
                self:SetText("")
                page:Refresh()
            end
            self:ClearFocus()
        end)
        page.add = T.Button(body, "Add", 90, function() Submit(false) end)
        page.add:SetPoint("TOPLEFT", w - 312, -34)
        local daily = T.Button(body, "Add daily", 100, function() Submit(true) end)
        daily:SetPoint("TOPLEFT", w - 216, -34)
        daily.tip = "A daily one is unticked again the next day"
        local weekly = T.Button(body, "Add weekly", 110, function() Submit(false, true) end)
        weekly:SetPoint("TOPLEFT", w - 110, -34)
        weekly.tip = "A weekly one is unticked again when a new week starts"

        local panel = T.Panel(body, T.PANEL)
        panel:SetPoint("TOPLEFT", 0, -68)
        panel:SetSize(w, ns.PAGE_H - 102)
        page.scroll, page.child = T.Scroll(panel)
        page.scroll:SetPoint("TOPLEFT", 1, -4)
        page.scroll:SetSize(w - 2, ns.PAGE_H - 110)
        page.child:SetWidth(w - 2)
        page.rows = {}
        page.empty = T.Text(panel, "GameFontHighlightSmall", T.MUTED)
        page.empty:SetPoint("TOPLEFT", 10, -10)
        page.empty:SetText("Nothing here yet. Type what you want to remember above and press Enter.")

        page.clear = T.Button(body, "Remove the ticked ones", 180, function()
            local list = List(scope)
            for i = #list, 1, -1 do
                if list[i].done and not list[i].daily and not list[i].weekly then table.remove(list, i) end -- those come back
            end
            page:Refresh()
        end)
        page.clear:SetPoint("BOTTOMLEFT", 0, 0)
    end,
    Row = function(page, i)
        local w = ns.PAGE_W
        local row = CreateFrame("Frame", nil, page.child)
        row:SetSize(w - 2, ROW_H)
        row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
        row.check = T.Check(row, "", w - 60, function(v)
            local note = List(scope)[row.index]
            if note then
                note.done = v or nil
                note.day = v and ns.Today() or nil
                note.week = v and Week() or nil
            end
            page:Refresh()
        end)
        row.check:SetPoint("LEFT", 10, 0)
        row.check.label:SetWidth(w - 170)
        row.check.label:SetWordWrap(false)
        row.remove = T.Button(row, "x", 20, function()
            table.remove(List(scope), row.index)
            page:Refresh()
        end)
        row.remove:SetSize(20, 18)
        row.remove:SetPoint("RIGHT", -8, 0)
        row.remove.tip = "Remove"
        row.up = T.Button(row, "^", 20, function()
            local list, i = List(scope), row.index
            if i and i > 1 then list[i - 1], list[i] = list[i], list[i - 1] end
            page:Refresh()
        end)
        row.up:SetSize(20, 18)
        row.up:SetPoint("RIGHT", row.remove, "LEFT", -28, 0)
        row.up.tip = "Move up"
        row.down = T.Button(row, "v", 20, function()
            local list, i = List(scope), row.index
            if i and i < #list then list[i + 1], list[i] = list[i], list[i + 1] end
            page:Refresh()
        end)
        row.down:SetSize(20, 18)
        row.down:SetPoint("RIGHT", row.remove, "LEFT", -4, 0)
        row.down.tip = "Move down"
        row.edit = T.Button(row, "Edit", 40, function()
            local note = List(scope)[row.index]
            if not note then return end
            page.editing = note
            page.input.edit:SetText(note.text)
            page.input.edit:SetFocus()
            page:Refresh()
        end)
        row.edit:SetSize(40, 18)
        row.edit:SetPoint("RIGHT", row.up, "LEFT", -4, 0)
        return row
    end,
    Refresh = function(page)
        local on = M.enabled
        page.off:SetShown(not on)
        page.body:SetShown(on)
        if not on then return end

        Roll()
        for _, b in ipairs(page.tabs) do
            local active = b.scope == scope
            b.label:SetTextColor(active and 1 or 0.8, active and 0.82 or 0.8, active and 0 or 0.8)
            local open = 0
            for _, note in ipairs(List(b.scope)) do
                if not note.done then open = open + 1 end
            end
            b.count:SetText(open > 0 and open or "")
        end
        if page.editing then
            local still = false
            for _, note in ipairs(List(scope)) do
                if note == page.editing then still = true end
            end
            if not still then page.editing = nil end -- removed, or the other tab
        end
        page.add.label:SetText(page.editing and "Save" or "Add")
        local list = List(scope)
        for i, note in ipairs(list) do
            local row = page.rows[i] or page:Row(i)
            page.rows[i] = row
            row.index = i
            row.check:SetChecked(note.done)
            row.up:SetShown(i > 1)
            row.down:SetShown(i < #list)
            local kind = note.daily and "daily" or (note.weekly and "weekly") or nil
            local text = note.text .. (kind and ("  |cff999999" .. kind .. "|r") or "")
            row.check.tip = nil
            row.check.label:SetText(note.done and ("|cff808080" .. note.text .. (kind and ("  " .. kind) or "") .. "|r") or text)
            local label = row.check.label -- a line cut short shows in full on hover
            if label.IsTruncated and label:IsTruncated() then row.check.tip = note.text end
            row:Show()
        end
        for i = #list + 1, #page.rows do page.rows[i]:Hide() end
        page.child:SetHeight(math.max(1, #list * ROW_H))
        page.empty:SetShown(#list == 0)
    end,
})

function M:Hints(add)
    Roll()
    local open = 0
    for _, which in ipairs({ "char", "account" }) do
        for _, note in ipairs(List(which)) do
            if (note.daily or note.weekly) and not note.done then open = open + 1 end
        end
    end
    if open > 0 then add(open .. (open == 1 and " daily or weekly to-do open" or " daily and weekly to-dos open"), 50, "notes") end
end
