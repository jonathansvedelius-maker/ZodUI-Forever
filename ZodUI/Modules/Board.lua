local ADDON, ns = ...
local T = ns.T

-- Chat board: what the public channels sell, buy, offer and look for, on one page,
-- sorted by kind instead of scrolling past in chat. The same ad said again moves to the
-- top with a count, rather than taking another row. Kept for this session only.
-- Service ads (enchants, lockpicking, portals, crafting) are also kept across sessions for two
-- weeks, so "who did Crusader?" can be asked days later: /zod board crusader, or the Kept filter.
-- Hiding the ads in chat is NaowhForever_QoL's Trade Spam Filter; this does not hide anything.

local M = ns:NewModule("board", {
    title = "Chat board",
    desc = "Collects what the public channels sell, buy, offer and look for on one page, sorted by kind and searchable, and keeps service ads for two weeks. A click on a row whispers the one who said it.",
    defaults = { enabled = true, minutes = 60, days = 14 },
    options = {
        { type = "step", key = "minutes", label = "Keep ads for this many minutes", min = 10, max = 180, step = 10 },
        { type = "step", key = "days", label = "Keep service ads (enchants, crafting) for this many days", min = 1, max = 30, step = 1 },
        { type = "note", text = "This does not hide ads in chat. NaowhForever_QoL's Trade Spam Filter does that.", lines = 1 },
    },
})

local MOST = 300
local ads = {} -- newest first: { at, author, text, plain, kind, lf, dungeons, count, key }
M.ads = ads
local byKey = {} -- author and text -> the ad, so a repeat is found without looking through them all

local KINDS = { sell = "Selling", buy = "Buying", service = "Service", group = "Group" }
local COLOURS = { sell = "ff40d040", buy = "ff66bbff", service = "ffffd100", group = "ffff8040" }

local function Short(name)
    return type(name) == "string" and (name:match("^[^%-]+") or name) or "?"
end

local SERVICES_MOST = 200

local function Kept()
    ns.db.services = ns.db.services or {}
    return ns.db.services
end

-- A service ad, kept across sessions: the newest of each author and text.
local function Keep(ad)
    local list = Kept()
    for i = #list, 1, -1 do
        if list[i].author == ad.author and list[i].plain == ad.plain then table.remove(list, i) end
    end
    table.insert(list, 1, { author = ad.author, text = ad.text:sub(1, 255), plain = ad.plain, at = ad.at })
    while #list > SERVICES_MOST do table.remove(list) end
end

-- Kept service ads with `query` in them, newest first; old ones are dropped on the way.
function M:Services(query)
    local list, out, from = Kept(), {}, time() - self.db.days * 86400
    for i = #list, 1, -1 do
        if (list[i].at or 0) < from then table.remove(list, i) end
    end
    query = (query or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    for _, s in ipairs(list) do
        if query == "" or s.plain:find(query, 1, true) or s.author:lower():find(query, 1, true) then
            out[#out + 1] = { at = s.at, author = s.author, text = s.text, plain = s.plain, kind = "service", count = 1 }
        end
    end
    return out
end

function M:Add(text, author)
    if type(author) ~= "string" or (issecretvalue and (issecretvalue(author) or issecretvalue(text))) then return nil end
    if Short(author) == (UnitName and ns.MyName()) then return nil end
    local ad = ns.Ads.Parse(text, UnitLevel and ns.Level())
    if not ad then return nil end
    local plain = ns.Ads.Plain(text)
    local key = author .. "\1" .. plain
    local old = byKey[key]
    if old then
        for i = 1, #ads do
            if ads[i] == old then
                table.remove(ads, i)
                old.at, old.count = time(), old.count + 1
                table.insert(ads, 1, old)
                return old
            end
        end
    end
    ad.at, ad.author, ad.text, ad.plain, ad.count, ad.key = time(), author, text, plain, 1, key
    table.insert(ads, 1, ad)
    byKey[key] = ad
    if ad.kind == "service" then Keep(ad) end
    while #ads > MOST do
        local gone = table.remove(ads)
        if gone.key and byKey[gone.key] == gone then byKey[gone.key] = nil end
    end
    return ad
end

-- Takes down the listings (Group listings' ads) of `author`.
function M:Drop(author)
    for i = #ads, 1, -1 do
        if ads[i].net and ads[i].author == author then
            local gone = table.remove(ads, i)
            if byKey[gone.key] == gone then byKey[gone.key] = nil end
        end
    end
end

-- The ads still fresh, of one kind (or all), with `query` in their text when one is given.
function M:List(kind, query)
    local out, from = {}, time() - self.db.minutes * 60
    query = query and query:lower():gsub("^%s+", ""):gsub("%s+$", "") or ""
    for _, ad in ipairs(ads) do
        if ad.at < from then break end
        if (not kind or ad.kind == kind) and (query == "" or ad.plain:find(query, 1, true) or ad.author:lower():find(query, 1, true)) then
            out[#out + 1] = ad
        end
    end
    return out
end

M:On("CHAT_MSG_CHANNEL", function(self, _, text, author, _, _, _, _, zone)
    -- World channels only: General, Trade, LookingForGroup and the like, not a custom one.
    if type(zone) == "number" and zone == 0 then return end
    if self:Add(text, author) then ns.Refresh() end
end)

function M:Find(part, add, has)
    for _, ad in ipairs(self:List(nil, part)) do
        add("Chat ad", Short(ad.author) .. ": " .. ad.plain:sub(1, 60), KINDS[ad.kind], "board")
    end
end

local function Ago(at)
    return ns.Ago(time() - at)
end

-- /zod board <words>: who offered it, in this session or the last two weeks.
function M:Slash(arg)
    local query = (arg or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if query == "" then ns.Show("board") return end
    local list = self:Services(query)
    if #list == 0 then ns.Print("no one offered '" .. query .. "' in the last " .. self.db.days .. " days.") return end
    ns.Print("offered '" .. query .. "':")
    for i = 1, math.min(8, #list) do
        local s = list[i]
        print("  |Hplayer:" .. s.author .. "|h[" .. Short(s.author) .. "]|h, " .. Ago(s.at) .. ": " .. s.text)
    end
end

ns.AddPage({
    key = "board", title = "Chat board", order = 45, group = "Planning", module = "board",
    Build = function(page, f)
        local w = ns.PAGE_W
        page.off = T.Text(f, "GameFontHighlightSmall", T.MUTED)
        page.off:SetPoint("TOPLEFT", 0, -4)
        page.off:SetText("The Chat board module is off. Switch it on under Settings.")
        local body = CreateFrame("Frame", nil, f)
        body:SetAllPoints(f)
        page.body = body
        page.kind = nil
        local x = 0
        page.filters = {}
        for _, spec in ipairs({ { "All", nil }, { "Selling", "sell" }, { "Buying", "buy" }, { "Services", "service" }, { "Groups", "group" },
            { "Kept", "kept" } }) do
            local b = T.Button(body, spec[1], 86, function()
                page.kind = spec[2]
                page:Refresh()
            end)
            b:SetPoint("TOPLEFT", x, 0)
            b.filter = spec[2]
            page.filters[#page.filters + 1] = b
            x = x + 92
        end
        page.search = T.Edit(body, ns.PAGE_W - x, 24) -- the rest of the row, 6 px after the last button
        page.search.clearOnEscape = true
        page.search:SetPoint("TOPLEFT", x, 0)
        page.search.edit:SetMaxLetters(40)
        page.search.edit:SetScript("OnTextChanged", function() page:Refresh() end)
        page.searchHint = T.Text(page.search, "GameFontHighlightSmall", T.MUTED)
        page.searchHint:SetPoint("LEFT", 8, 0)
        page.searchHint:SetText("search, e.g. crusader")
        page.list = T.Table(body, { { "When", 80 }, { "Who", 120 }, { "Kind", 80 }, { "What they said", w - 280 } }, w, ns.PAGE_H - 34)
        page.list:SetPoint("TOPLEFT", 0, -34)
        page.list.onClick = function(ad)
            if ad and ChatFrame_SendTell then ChatFrame_SendTell(Short(ad.author)) end
        end
    end,
    Refresh = function(page)
        page.off:SetShown(not M.enabled)
        page.body:SetShown(M.enabled)
        if not M.enabled then return end
        local query = page.search.edit:GetText() or ""
        page.searchHint:SetShown(query == "")
        for _, b in ipairs(page.filters) do
            local on = b.filter == page.kind
            b.label:SetTextColor(on and T.GOLD[1] or 1, on and T.GOLD[2] or 1, on and T.GOLD[3] or 1)
        end
        local rows = {}
        local list = page.kind == "kept" and M:Services(query) or M:List(page.kind, query)
        for _, ad in ipairs(list) do
            rows[#rows + 1] = { Ago(ad.at), Short(ad.author), "|c" .. COLOURS[ad.kind] .. KINDS[ad.kind] .. "|r",
                ad.text .. (ad.count > 1 and (" |cff999999(x" .. ad.count .. ")|r") or ""), data = ad }
        end
        page.list:SetRows(rows, "Nothing yet. Ads from General, Trade and LookingForGroup show here as they are said; a click on one whispers its author.")
    end,
})
