local ADDON, ns = ...
local T = ns.T

-- Goals: "I want 60 Linen Cloth". Counts what you have against what you
-- want, shows the open goals on Home and says when one is reached.

local M = ns:NewModule("goals", {
    title = "Goals",
    desc = "Set how many of an item you want to collect. Home shows how far along you are, and you are told when a goal is reached.",
    defaults = { enabled = true, bank = true, alert = true, progress = true },
    options = {
        { type = "check", key = "bank", label = "Count what is in the bank too" },
        { type = "check", key = "alert", label = "Tell me when a goal is reached" },
        { type = "check", key = "progress", label = "A line in chat each time I get more of a goal's item" },
        { type = "note", text = "/zod goals 60 linen cloth adds a goal from chat. Type level and a number for a level to reach.", lines = 2 },
    },
})

local MOST = 99999
local message = ""

local function List()
    local list = ns.chardb.goals
    if not list then
        list = {}
        ns.chardb.goals = list
    end
    return list
end

local function Have(id)
    local count = C_Item and C_Item.GetItemCount or GetItemCount
    return count and count(id, M.db.bank and true or false) or 0
end

local function NameOf(id)
    local known = ns.db.itemNames and ns.db.itemNames[id]
    if known and known.name then return known.name end
    local get = C_Item and C_Item.GetItemInfo or GetItemInfo
    return get and (get(id)) or nil
end

-- An item from what was typed: its id, a link, or (part of) the name of an
-- item one of your characters has had in its bags.
local function Resolve(text)
    local id = tonumber(text) or tonumber(text:match("item:(%d+)"))
    if id then return id, NameOf(id) or ("Item " .. id) end
    local want, found, several = text:lower(), nil, false
    for itemID, known in pairs(ns.db.itemNames or {}) do
        local name = known.name and known.name:lower()
        if name == want then return itemID, known.name end
        if name and name:find(want, 1, true) then
            if found then several = true end
            found = itemID
        end
    end
    if several then return nil, "More than one item has '" .. text .. "' in its name. Type more of it." end
    if found then return found, ns.db.itemNames[found].name end
    return nil, "No item called '" .. text .. "' has been in your bags. Its item id works too."
end
ns.ResolveItem = Resolve -- Vendor's sell and keep lists use it too

local MAX_LEVEL = 80

local function CheckLevel(quiet, level)
    local want = ns.chardb.levelGoal
    if not want then return end
    if (level or ns.Level() or 0) >= want then
        if not ns.chardb.levelDone then
            ns.chardb.levelDone = true
            if M.db.alert and not quiet then ns.Alert("Goal reached: level " .. want .. ".") end
        end
    else
        ns.chardb.levelDone = nil
    end
end

-- The gold goal: one amount, counted against what this character carries.
local function CheckGold(quiet)
    local want = ns.chardb.goldGoal
    if not want then return end
    if GetMoney() >= want then
        if not ns.chardb.goldDone then
            ns.chardb.goldDone = true
            if M.db.alert and not quiet then ns.Alert("Goal reached: " .. ns.Money(want, true) .. " saved.") end
        end
    else
        ns.chardb.goldDone = nil
    end
end

local function Check(quiet)
    CheckGold(quiet)
    for _, goal in ipairs(List()) do
        local have = Have(goal.id)
        if have >= goal.want then
            if not goal.done then
                goal.done = true
                if M.db.alert and not quiet then ns.Alert("Goal reached: " .. goal.want .. " " .. goal.name .. ".") end
            end
        else
            goal.done = nil
        end
        if goal.name:find("^Item %d+$") then goal.name = NameOf(goal.id) or goal.name end -- the name arrives late for an unseen item
        if M.db.progress and not quiet and goal.last and have > goal.last and have < goal.want then
            ns.Print(goal.name .. ": " .. ns.Comma(have) .. " / " .. ns.Comma(goal.want))
        end
        goal.last = have
    end
    ns.Refresh()
end

-- Adds a goal, or changes the count of one that is there. Returns whether it worked and what to say.
function M:Add(text, want)
    text = (text or ""):gsub("^%s+", ""):gsub("%s+$", "")
    want = math.floor(tonumber(want) or 0)
    if text == "" then return false, "Type the name of an item first." end
    if want < 1 or want > MOST then return false, "The number must be between 1 and " .. ns.Comma(MOST) .. "." end
    if text:lower() == "level" then
        if want < 2 or want > MAX_LEVEL then return false, "A level goal is between 2 and " .. MAX_LEVEL .. "." end
        ns.chardb.levelGoal, ns.chardb.levelDone = want, nil
        CheckLevel(true)
        ns.Refresh()
        return true, "Reaching level " .. want .. "."
    end
    if text:lower() == "gold" then
        ns.chardb.goldGoal, ns.chardb.goldDone = want * 10000, nil
        Check(true)
        return true, "Saving up " .. ns.Money(want * 10000, true) .. "."
    end
    local id, name = Resolve(text)
    if not id then return false, name end
    for _, goal in ipairs(List()) do
        if goal.id == id then
            goal.want, goal.done = want, nil
            Check(true)
            return true, name .. " now has a goal of " .. ns.Comma(want) .. "."
        end
    end
    table.insert(List(), { id = id, name = name, want = want, fromHave = Have(id), fromAt = time() })
    Check(true)
    return true, "Added: " .. ns.Comma(want) .. " " .. name .. "."
end

function M:Remove(id)
    if id == "gold" then ns.chardb.goldGoal, ns.chardb.goldDone = nil, nil end
    if id == "level" then ns.chardb.levelGoal, ns.chardb.levelDone = nil, nil end
    local list = List()
    for i = #list, 1, -1 do
        if list[i].id == id then table.remove(list, i) end
    end
    ns.Refresh()
end

-- Removes the goals that are reached. Returns how many.
function M:RemoveReached()
    local n = 0
    if ns.chardb.goldGoal and GetMoney() >= ns.chardb.goldGoal then
        self:Remove("gold")
        n = n + 1
    end
    if ns.chardb.levelGoal and (ns.Level() or 0) >= ns.chardb.levelGoal then
        self:Remove("level")
        n = n + 1
    end
    local list = List()
    for i = #list, 1, -1 do
        if Have(list[i].id) >= list[i].want then
            table.remove(list, i)
            n = n + 1
        end
    end
    ns.Refresh()
    return n
end

-- /zod goals 60 linen cloth (or linen cloth 60)
function M:Slash(arg)
    local count, name = arg:match("^(%d+)%s+(.+)$")
    if not count then name, count = arg:match("^(.-)%s+(%d+)$") end
    if not count then
        if arg == "" then ns.Show("goals") return end
        ns.Print("use /zod goals 60 linen cloth, /zod goals level 30 or /zod goals gold 100.")
        return
    end
    local _, said = self:Add(name, count)
    ns.Print(said)
end

function M:OnEnable()
    Check(true)
    CheckLevel(true)
end

M:On("PLAYER_LEVEL_UP", function(_, _, level)
    CheckLevel(false, level)
    ns.Refresh()
end)

M:On("BAG_UPDATE_DELAYED", function() Check(false) end)
M:On("PLAYER_MONEY", function()
    CheckGold(false)
    ns.Refresh()
end)

local function GoldProgress()
    local have, want = GetMoney(), ns.chardb.goldGoal
    local text = ns.Money(have, true) .. " / " .. ns.Money(want, true)
    return have >= want and T.Paint(text, T.GREEN) or text, have, want
end

local function Progress(goal)
    local have = Have(goal.id)
    local text = ns.Comma(have) .. " / " .. ns.Comma(goal.want)
    return have >= goal.want and T.Paint(text, T.GREEN) or text, have
end

function M:Find(part, add, has)
    if ns.chardb.goldGoal and has("gold") then add("Goal", "Gold", ns.Money(ns.chardb.goldGoal, true), "goals") end
    for _, goal in ipairs(List()) do
        if has(goal.name) then add("Goal", goal.name, ns.Comma(Have(goal.id)) .. " / " .. ns.Comma(goal.want), "goals") end
    end
end

function M:Card()
    local list = List()
    local lines = {}
    if ns.chardb.levelGoal then lines[1] = { "Level", (ns.Level() or 0) .. " / " .. ns.chardb.levelGoal } end
    if ns.chardb.goldGoal then lines[#lines + 1] = { "Gold", (GoldProgress()) } end
    for _, goal in ipairs(list) do
        if #lines < 4 then lines[#lines + 1] = { goal.name, (Progress(goal)) } end
    end
    if #lines == 0 then return nil end -- no goals, no card
    return { title = "Goals", lines = lines, button = { "All", function() ns.Show("goals") end } }
end

ns.AddPage({
    key = "goals", title = "Goals", order = 42, group = "Planning", module = "goals",
    Build = function(page, f)
        local w = ns.PAGE_W
        page.off = T.Text(f, "GameFontHighlightSmall", T.MUTED)
        page.off:SetPoint("TOPLEFT", 0, -4)
        page.off:SetText("The Goals module is off. Switch it on under Settings.")
        local body = CreateFrame("Frame", nil, f)
        body:SetAllPoints(f)
        page.body = body

        page.name = T.Edit(body, 300, 24)
        page.name:SetPoint("TOPLEFT", 0, 0)
        page.name.edit:SetMaxLetters(60)
        page.count = T.Edit(body, 70, 24)
        page.count:SetPoint("TOPLEFT", 306, 0)
        page.count.edit:SetMaxLetters(5)
        page.count.edit:SetText("20")
        T.Placeholder(page.name, "An item's name, or level")
        T.Placeholder(page.count, "How many")
        T.TabOrder(page.name, page.count)
        local function Submit()
            local ok, said = M:Add(page.name.edit:GetText(), page.count.edit:GetText())
            message = said or ""
            if ok then page.name.edit:SetText("") end
            page:Refresh()
        end
        page.name.edit:SetScript("OnEnterPressed", Submit)
        page.count.edit:SetScript("OnEnterPressed", Submit)
        local add = T.Button(body, "Add goal", 100, Submit)
        add:SetPoint("TOPLEFT", 382, 0)
        page.said = T.Text(body, "GameFontHighlightSmall", T.DIM)
        page.said:SetPoint("TOPLEFT", 0, -32)
        page.said:SetWidth(w)
        page.said:SetJustifyH("LEFT")

        page.list = T.Table(body, { { "Item", w - 420 }, { "Have / goal", 150, "RIGHT" }, { "Left", 100, "RIGHT" }, { "Done", 150, "RIGHT" } },
            w, ns.PAGE_H - 88)
        page.list:SetPoint("TOPLEFT", 0, -54)
        page.list.onClick = function(id)
            page.list.selected = id
            page:Refresh()
        end
        page.list.onRightClick = function(id) -- right-click: gone at once
            M:Remove(id)
            if page.list.selected == id then page.list.selected = nil end
            message = ""
            page:Refresh()
        end
        page.remove = T.Button(body, "Remove this goal", 150, function()
            if page.list.selected then
                M:Remove(page.list.selected)
                page.list.selected = nil
                message = ""
                page:Refresh()
            end
        end)
        page.remove:SetPoint("BOTTOMLEFT", 0, 0)
        page.hint = T.Text(body, "GameFontHighlightSmall", T.MUTED)
        page.hint:SetPoint("LEFT", page.remove, "RIGHT", 10, 0)
        page.reached = T.Button(body, "Remove the reached ones", 190, function()
            M:RemoveReached()
            page.list.selected = nil
            message = ""
            page:Refresh()
        end)
        page.reached:SetPoint("BOTTOMRIGHT", 0, 0)
    end,
    Refresh = function(page)
        local on = M.enabled
        page.off:SetShown(not on)
        page.body:SetShown(on)
        if not on then return end
        page.said:SetText(message ~= "" and message
            or "An item's name (one your characters have had in their bags) or id, and how many. Or gold and an amount, or level and a level.")
        local rows = {}
        if ns.chardb.levelGoal then
            local level, want = ns.Level() or 0, ns.chardb.levelGoal
            local text = level .. " / " .. want
            rows[1] = { T.Paint("Level", T.GOLD), level >= want and T.Paint(text, T.GREEN) or text,
                level < want and ((want - level) .. (want - level == 1 and " level" or " levels")) or "-",
                math.floor(math.min(1, level / want) * 100) .. "%", data = "level" }
        end
        if ns.chardb.goldGoal then
            local text, have, want = GoldProgress()
            rows[#rows + 1] = { T.Paint("Gold", T.GOLD), text, have < want and ns.Money(want - have, true) or "-",
                math.floor(math.min(1, have / want) * 100) .. "%", data = "gold" }
        end
        for _, goal in ipairs(List()) do
            local text, have = Progress(goal)
            local left = math.max(0, goal.want - have)
            local eta = ""
            local gained, took = have - (goal.fromHave or have), time() - (goal.fromAt or time())
            if left > 0 and gained > 0 and took >= 60 then eta = "  |cff999999~" .. ns.Duration(left / gained * took) .. "|r" end
            rows[#rows + 1] = { goal.name, text, left > 0 and ns.Comma(left) or "-",
                math.floor(math.min(1, have / goal.want) * 100) .. "%" .. eta, data = goal.id }
        end
        page.list:SetRows(rows, "No goals yet.")
        T.Off(page.remove, page.list.selected == nil, "Click a goal in the list first, or right-click one to remove it straight away.")
        page.hint:SetText(page.list.selected and "" or "Click a goal to pick it.")
    end,
})

function M:Hints(add)
    if ns.chardb.goldDone then add("Goal reached: " .. ns.Money(ns.chardb.goldGoal, true) .. " saved", 30, "goals") end
    if ns.chardb.levelDone then add("Goal reached: level " .. ns.chardb.levelGoal, 30, "goals") end
    for _, goal in ipairs(List()) do
        if goal.done then add("Goal reached: " .. goal.want .. " " .. goal.name, 30, "goals") end
    end
end
