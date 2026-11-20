-- Drives ZodUI through a play session against stub.lua and checks what it does.
local W = World
local say = function(s) io.write(s .. "\n") end
local passed, failed = 0, 0

local function check(cond, what)
    if cond then
        passed = passed + 1
    else
        failed = failed + 1
        say("  FAIL: " .. what)
    end
end

local function plain(s)
    return (tostring(s):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

local function fire(event, ...)
    for _, f in ipairs(W.frames) do
        if f.events[event] and f.scripts.OnEvent then f.scripts.OnEvent(f, event, ...) end
    end
end

-- Lets `seconds` pass, running every OnUpdate.
local base = W.clock
local function pump(seconds, step)
    step = step or 0.1
    for _ = 1, math.floor(seconds / step + 0.5) do
        W.uptime = W.uptime + step
        W.clock = base + math.floor(W.uptime - 1000)
        for i = 1, #W.frames do
            local f = W.frames[i]
            if f.scripts.OnUpdate and f:IsVisible() then f.scripts.OnUpdate(f, step) end
        end
    end
end

local function screen(root)
    local parts = {}
    for _, f in ipairs(W.frames) do
        if f.kind == "FontString" and f.text and f.text ~= "" and f:IsVisible() then
            local r, inside = f, root == nil
            while r and not inside do
                if r == root then inside = true end
                r = r.parent
            end
            if inside then parts[#parts + 1] = plain(f.text) end
        end
    end
    return table.concat(parts, "\n")
end

local function has(text, root)
    return screen(root):find(text, 1, true) ~= nil
end

local function button(label)
    for _, f in ipairs(W.frames) do
        if f.kind == "Button" and f.scripts.OnClick and f:IsVisible() and rawget(f, "label") and plain(f.label.text or "") == label then
            return f
        end
    end
end

local function click(label, mouse)
    local b = type(label) == "table" and label or button(label)
    assert(b, "no visible button '" .. tostring(label) .. "'")
    b.scripts.OnClick(b, mouse or "LeftButton")
    pump(0.3)
    return b
end

local function printed(text)
    for _, line in ipairs(W.printed) do
        if plain(line):find(text, 1, true) then return true end
    end
    return false
end

local function called(name, arg)
    local n = 0
    for _, c in ipairs(W.calls) do
        if c[1] == name and (arg == nil or c[2] == arg) then n = n + 1 end
    end
    return n
end

local function reset()
    W.calls, W.printed, W.alerts = {}, {}, {}
end

local function slash(msg)
    SlashCmdList["ZODUI"](msg)
    pump(0.3)
end

---------------------------------------------------------------------------
say("--- load and login")
W.bags[0] = {
    [1] = { id = 100, quality = 0, count = 5, price = 20 },
    [2] = { id = 101, quality = 1, count = 1, price = 500 },
    [3] = { id = 102, quality = 0, count = 1, price = 0, noValue = true },
    [4] = { id = 103, quality = 0, count = 2, price = 150 },
}
W.durability = { [1] = { 80, 100 }, [5] = { 60, 100 } }
ZodUIDB = { chars = { ["Zod-Forever"] = { seen = W.clock - 2 * 86400 }, ["Alt-Forever"] = { name = "Alt", realm = "Forever", class = "MAGE", level = 31, money = 500000,
    xp = 1000, xpMax = 30000, rested = 3000, resting = true, seen = W.clock - 16 * 3600, zone = "Orgrimmar" } } }

local ns = {}
for _, file in ipairs(ADDON_FILES) do
    assert(load(file[2], "@" .. file[1]))("ZodUI", ns)
end
-- Every table made, with where it was made: the layout check near the end measures their columns.
local madeTables = {}
do
    local Table = ns.T.Table
    ns.T.Table = function(parent, columns, width, height, rowHeight, noSort)
        local info = debug and debug.getinfo and debug.getinfo(2, "Sl")
        local tbl = Table(parent, columns, width, height, rowHeight, noSort)
        madeTables[#madeTables + 1] = { columns = tbl.columns or columns, width = width, at = info and (info.short_src .. ":" .. info.currentline) or "?" }
        return tbl
    end
end
do -- every text made by T.Text knows where it was made, for the layout check
    local Text = ns.T.Text
    ns.T.Text = function(...)
        local fs = Text(...)
        local a, b = debug.getinfo(2, "Sl"), debug.getinfo(3, "Sl")
        local src = a and a.short_src or "?"
        if src:find("Theme.lua", 1, true) and b then a = b end -- made by a Theme helper: name its caller
        fs.at = a and (a.short_src .. ":" .. a.currentline) or "?"
        return fs
    end
end
fire("ADDON_LOADED", "SomethingElse")
check(ns.db == nil, "another addon loading does not load ZodUI's data")
fire("ADDON_LOADED", "ZodUI")
fire("PLAYER_LOGIN")
fire("PLAYER_ENTERING_WORLD")
pump(1)
ns.db.general.toasts = false -- the older checks read the game's error text; notices have their own section
pump(6)
check(W.alerts[1] == "Welcome back, Zod: away 2d, rested 15%.", "a greeting after two days away: " .. tostring(W.alerts[1]))

check(ns.ready, "ready after login")
check(printed("loaded"), "says it loaded")
check(printed("New here? /zod setup picks which modules run."), "the first login points at the Modules page")
check(ns.db.general.lastVersion == ns.version, "and remembers the version for the update notice")
check(printed("Vendor, Info bar start switched off because NaowhForever_QoL already does that. /zod settings switches them on."),
    "says once which modules start off and why")
check(not printed("Game settings,"), "a module that is off by design is not blamed on another addon")
local on = {}
for _, m in ipairs(ns.order) do on[m.key] = m.enabled end
for _, key in ipairs({ "session", "history", "goals", "remind", "loot", "runs", "gold", "alts", "items", "notes", "tooltip", "chat", "alerts", "rep" }) do
    check(on[key] == true, key .. " starts on")
end
for _, key in ipairs({ "vendor", "databar", "social", "tweaks" }) do
    check(on[key] == false, key .. " starts off")
end
check(ns.modules.databar.db.conflict == "NaowhForever_QoL", "the info bar is off because of the other addon, and says so")
check(ns.modules.chat.db.conflict == nil, "chat has no conflict here")
check(ns.modules.vendor.db.conflict == "NaowhForever_QoL" and ns.modules.vendor.db.recheck == 1, "vendor is off because NaowhForever_QoL sells grey items too")
check(ZodUIMinimapButton and ZodUIMinimapButton:IsShown(), "minimap button shown")
check(ZodUIMinimapButton.icon.texture == "Interface\\AddOns\\ZodUI\\Media\\Logo", "the minimap button shows the logo")check(#ns.order == 49, "49 modules, got " .. #ns.order)
do
    -- A setup from before a module gained a conflict: it was on, and recheck asks once more.
    ns.db.modules.recheckdemo = { enabled = true }
    local demo = ns:NewModule("recheckdemo", { title = "Recheck demo", conflicts = { "NaowhForever_QoL" }, recheck = 1 })
    check(not demo.enabled and demo.db.enabled == false and demo.db.recheck == 1 and printed("Recheck demo starts switched off because NaowhForever_QoL"),
        "recheck switches a module off once on a setup that had it on")
    demo:Enable()
    ns.db.modules.recheckdemo2 = { enabled = false }
    local off = ns:NewModule("recheckdemo2", { title = "Recheck off", conflicts = { "SomethingNotLoaded" }, recheck = 1 })
    check(not off.enabled and off.db.enabled == false, "and never switches on a module that was off")
    -- Started again (the next login): the answer stands, the module stays on.
    ns.modules.recheckdemo, ns.modules.recheckdemo2 = nil, nil
    table.remove(ns.order)
    table.remove(ns.order)
    local again = ns:NewModule("recheckdemo", { title = "Recheck demo", conflicts = { "NaowhForever_QoL" }, recheck = 1 })
    check(again.enabled, "switched on again after the recheck, it stays on")
    ns.modules.recheckdemo = nil
    table.remove(ns.order)
    ns.db.modules.recheckdemo, ns.db.modules.recheckdemo2 = nil, nil
end
check(ns.modules.map == nil and ns.modules.quests == nil and ns.modules.combat == nil, "map, quest automation and the fight timer are gone")
say("  modules: " .. #ns.order)

---------------------------------------------------------------------------
say("--- window and home")
slash("")
check(ZodUIFrame and ZodUIFrame:IsShown(), "/zod opens the window")
check(UISpecialFrames[1] == "ZodUIFrame", "Escape closes the window")
check(has("Level 24"), "home shows the level")
check(has("4,000 / 20,000 XP  (20%)   +15% rested"), "home shows the XP bar text")
for _, title in ipairs({ "Session", "Loot this session", "Gold", "Characters", "To do", "Gear and bags", "Reputation" }) do
    check(has(title, ZodUIFrame), "home has the " .. title .. " card")
end
check(not has("Undead Route", ZodUIFrame), "no route card without the route addon")
local routeOpened = 0
SlashCmdList["UNDEADROUTE"] = function() routeOpened = routeOpened + 1 end
pump(1.5)
check(has("Undead Route", ZodUIFrame), "route card with the route addon")
click("Open route")
check(routeOpened == 1, "the route button opens the route")
UndeadRoute = {
    Status = function() return { stage = "Hillsbrad Foothills", range = "20-30", hub = "Tarren Mill", next = "Pick up: Elixir of Pain", left = 7 } end,
    Toggle = function() routeOpened = routeOpened + 10 end,
}
pump(1.5)
check(has("Hillsbrad Foothills  20-30", ZodUIFrame) and has("Pick up: Elixir of Pain", ZodUIFrame), "the route card shows the stage and the next step")
check(not has("Ready to hand in", ZodUIFrame), "no hand-in line from a route that does not count them")
local routeStatus = UndeadRoute.Status
UndeadRoute.Status = function() local s = routeStatus() s.ready = 3 return s end
pump(1.5)
check(has("Ready to hand in", ZodUIFrame) and has("3", ZodUIFrame), "the route card says how many quests are ready to hand in")
UndeadRoute.Status = function() local s = routeStatus() s.ready = 0 return s end
pump(1.5)
check(not has("Ready to hand in", ZodUIFrame), "and nothing when none are")
UndeadRoute.Status = routeStatus
click("Open route")
check(routeOpened == 11, "the route button uses the route's own API when it has one")
UndeadRoute.Status = function() error("route broke") end
pump(1.5)
check(has("The step-by-step leveling route.", ZodUIFrame), "a failing route falls back to the plain card")
check(#ns.errors == 1, "and the failure is recorded once")
UndeadRoute.Status = function() return nil end
slash("errors clear")
check(#ns.errors == 0, "/zod errors clear forgets them")
check(has("20% rested", ZodUIFrame), "the alt's rested XP grew while it was away (10% + 16h in an inn = 20%)")
do
    -- Every module's settings scroll when they are taller than the page, and only then.
    local page = ns.pages.settings
    ns.Show("settings")
    local tall, wrong = {}, {}
    for _, m in ipairs(page.mods) do
        ns.Show("settings", m == page.mods[1] and "general" or m.key)
        local box = page.details[m.key]
        local full, view = box.content:GetHeight(), box:GetHeight()
        if full > view then tall[#tall + 1] = m.key .. " " .. math.floor(full) end
        if box.thumb:IsShown() ~= (full - view > 1) then wrong[#wrong + 1] = m.key end
    end
    say("   taller than the page: " .. (#tall > 0 and table.concat(tall, ", ") or "none"))
    check(#wrong == 0, "the scroll thumb shows exactly when a module's settings are taller than the page: " .. table.concat(wrong, " "))
end
for _, key in ipairs({ "session", "loot", "gold", "alts", "rep", "notes", "settings", "home" }) do
    ns.Show(key)
    pump(0.5)
    check(#ns.errors == 0, "page " .. key .. " draws without errors" .. (ns.errors[1] and (": " .. ns.errors[1]) or ""))
end
do
    -- Folding: the title bar and what wants doing now; a page asked for by name unfolds it.
    local f = ZodUIFrame
    f.fold.scripts.OnClick(f.fold, "LeftButton")
    pump(0.5)
    check(ns.db.window.folded and f.fold.label.text == "+", "the fold button folds the window")
    check(f:GetWidth() == 360 and f:GetHeight() < 200, "folded, the window is small: " .. f:GetWidth() .. "x" .. f:GetHeight())
    check(not f.navPanel:IsShown() and not f.content:IsShown() and not f.find:IsShown() and f.short:IsShown(), "folded, only the short list shows")
    check(ns.db.window.point == "TOPLEFT" and ns.db.window.rel == "BOTTOMLEFT", "folding pins the window by its top")
    check(f.short.rows[1]:IsShown() or f.short.none:IsShown(), "the folded window lists what wants doing, or says nothing does")
    check(#ns.errors == 0, "folded refresh draws without errors" .. (ns.errors[1] and (": " .. ns.errors[1]) or ""))
    ns.Show("settings")
    check(not ns.db.window.folded and f:GetWidth() == 900 and f.content:IsShown(), "opening a page by name unfolds the window")
    f.bar.scripts.OnMouseUp(f.bar, "LeftButton")
    f.bar.scripts.OnMouseUp(f.bar, "LeftButton")
    check(ns.db.window.folded, "a double-click on the title bar folds")
    f.bar.scripts.OnMouseUp(f.bar, "LeftButton")
    f.bar.scripts.OnMouseUp(f.bar, "LeftButton")
    check(not ns.db.window.folded, "and another unfolds")
    local edit = f.find.edit
    ns.Search("loot")
    check(ns.pages.find.frame:IsShown(), "the search shows its results")
    edit.scripts.OnEscapePressed(edit)
    check((edit:GetText() or "") == "" and not ns.pages.find.frame:IsShown(), "Escape in the search box empties it and goes back to the page")
end
slash("")
check(not ZodUIFrame:IsShown(), "/zod closes the window again")

---------------------------------------------------------------------------
say("--- session and xp")
reset()
W.xp = 4500
fire("PLAYER_XP_UPDATE", "player")
pump(600, 1)
slash("session")
check(has("XP earned") and has("500"), "500 XP earned")
check(has("3,000") or has("2,9"), "XP per hour is worked out: " .. tostring(select(1, ns.modules.session:Rate())))
W.level = 25
fire("PLAYER_LEVEL_UP", 25)
W.xp, W.xpMax = 200, 22000
fire("PLAYER_XP_UPDATE", "player")
check(ns.chardb.session.xp == 500 + 15500 + 200, "XP across a level-up is counted: " .. ns.chardb.session.xp)
check(printed("level 25. From here on"), "first level-up is announced")
pump(3.5)
check(not printed("class trainer"), "no trainer reminder on an odd level")
check(printed("talent point"), "talent reminder on level-up")
ns.modules.session.db.screenshot = true
pump(120, 1)
W.level = 26
fire("PLAYER_LEVEL_UP", 26)
pump(4)
check(printed("Level 25 took 2m of play"), "the time a level took is announced")
check(printed("class trainer may have new spells and you have a talent point"), "trainer and talent reminder on an even level")
check(called("Screenshot") == 1, "screenshot on level-up")
fire("QUEST_TURNED_IN", 123, 900, 50)
fire("PLAYER_DEAD")
pump(0.5)
check(has("26") and has("25"), "the level log lists both levels")
check(ns.chardb.session.quests == 1 and ns.chardb.session.deaths == 1 and ns.chardb.session.questXP == 900, "quests and deaths counted")
do
    local b = click("Start a new session")
    check(ns.chardb.session.xp ~= 0 and b.label.text == "Sure? Click again", "a button that throws something away asks first")
    b.scripts.OnLeave(b)
    check(b.label.text == "Start a new session", "moving the mouse away calls it off")
    click(click("Start a new session"))
end
check(ns.chardb.session.xp == 0, "a new session starts from zero")

---------------------------------------------------------------------------
say("--- loot log")
reset()
local function loot(msg) fire("CHAT_MSG_LOOT", msg, "", "", "", "Zod") end
W.bags[0][7] = { id = 300, quality = 2, count = 1, price = 2500 }
W.bags[0][8] = { id = 301, quality = 0, count = 3, price = 40 }
loot("You receive loot: |cff1eff00|Hitem:300::::::::24:::::|h[Sturdy Belt]|h|r.")
loot("You receive loot: |cff9d9d9d|Hitem:301::::::::24:::::|h[Ruined Pelt]|h|rx3.")
loot("You receive item: |cff9d9d9d|Hitem:301::::::::24:::::|h[Ruined Pelt]|h|r.")
loot("Bob receives loot: |cff1eff00|Hitem:300::::::::24:::::|h[Sturdy Belt]|h|r.")
loot("You receive loot: |cffffffff|Hitem:999::::::::24:::::|h[Unknown Thing]|h|rx2.")
W.secret = "secret loot"
loot(W.secret)
W.secret = nil
local rows, pieces, value, best = ns.modules.loot:Summary()
check(pieces == 7 and value == 2500 + 4 * 40, "loot counted: " .. pieces .. " items worth " .. value)
check(#rows == 3 and plain(rows[1][1]) == "Sturdy Belt" and rows[3].name == "Ruined Pelt" and rows[3][2] == 4, "best first, counts added up")
check(best and best.name == "Sturdy Belt", "the best item is the green one")
check(rows[2].name == "Unknown Thing" and rows[2][3] == "-", "an item the game does not know yet has no price")
slash("loot")
check(has("7 items this session, worth 26s 60c at a merchant"), "the loot page totals: " .. screen(ZodUIFrame):sub(1, 0))
ns.modules.loot.db.minQuality = 2
pump(1.5)
check(has("Sturdy Belt") and not has("Ruined Pelt"), "the quality setting filters the list")
ns.modules.loot.db.minQuality = 3
pump(1.5)
check(has("Nothing of that quality yet"), "an empty filter says why")
ns.modules.loot.db.minQuality = 0
click(click("Clear the list"))
check(select(2, ns.modules.loot:Summary()) == 0 and has("What you loot from now on"), "the list can be cleared")
W.bags[0][7], W.bags[0][8] = nil, nil

---------------------------------------------------------------------------
say("--- reputation")
slash("rep")
check(has("Horde") and has("Undercity") and has("Friendly") and has("1,500 / 6,000"), "the reputation page lists standing and progress")
check(not has("+"), "nothing gained yet")
W.factions[2].currentStanding = 4750
W.factions[4].currentStanding = 425
fire("UPDATE_FACTION")
fire("UPDATE_FACTION")
pump(0.5)
check(has("+250") and has("-75") and has("1,750 / 6,000"), "gains and losses since login")
slash("home")
check(has("Undercity", ZodUIFrame) and has("+250", ZodUIFrame), "the home card shows the biggest change first")

---------------------------------------------------------------------------
say("--- gold")
reset()
local before = W.money
W.money = before + 5000
fire("PLAYER_MONEY")
W.money = W.money - 2000
fire("PLAYER_MONEY")
local today = ns.db.gold.days[ns.Today()]
check(today and today.earned == 5000 and today.spent == 2000, "the day's ledger has what was earned and spent")
check(ns.modules.gold:Total() == W.money + 500000, "the total counts every character")
slash("gold")
check(has("Alt") and has("50g") and not has("50g 0s"), "the gold page lists the alt")
check(has("+30s") and not has("+30s 0c"), "the gold page shows the day's net")
check(ns.Money(1234567) == "123|cffffd100g|r 45|cffc7c7cfs|r 67|cffeda55fc|r", "money format: " .. ns.Money(1234567))
check(plain(ns.Money(-250)) == "-2s 50c", "negative money: " .. plain(ns.Money(-250)))
check(ns.Comma(1234567) == "1,234,567" and ns.Comma(999) == "999" and ns.Comma(-1234) == "-1,234", "thousands separators")
check(ns.Duration(59) == "59s" and ns.Duration(3725) == "1h 2m" and ns.Duration(90000) == "1d 1h" and ns.Duration(7200) == "2h" and ns.Duration(9 * 86400) == "9d", "durations")

---------------------------------------------------------------------------
say("--- characters")
slash("alts")
check(has("Orgrimmar") and has("Mining 150, Engineering 140"), "the characters page shows zones and professions")
local list = ns.pages.alts.list
list.onClick("Alt-Forever")
click(click("Forget this character"))
check(ns.db.chars["Alt-Forever"] == nil, "a character can be forgotten")
list.onClick(ns.charKey)
click(click("Forget this character"))
check(ns.db.chars[ns.charKey] ~= nil, "the character being played cannot be forgotten")

---------------------------------------------------------------------------
say("--- to do")
slash("notes")
local edit
for _, f in ipairs(W.frames) do
    if f.kind == "EditBox" and f:IsVisible() then edit = f end
end
edit:SetText("  Buy arrows  ")
edit.scripts.OnEnterPressed(edit)
edit:SetText("Train |cffff0000First Aid")
click("Add")
edit:SetText("   ")
click("Add")
check(#ns.chardb.notes == 2 and ns.chardb.notes[1].text == "Buy arrows", "notes are added, trimmed, and empty ones refused")
check(ns.chardb.notes[2].text == "Train cffff0000First Aid", "colour codes cannot be typed into a note")
check(edit:GetText() == "   ", "the field keeps what was refused")
pump(0.5)
local row = ns.pages.notes.rows[1]
click(row.check)
check(ns.chardb.notes[1].done == true, "a note can be ticked")
click("Remove the ticked ones")
check(#ns.chardb.notes == 1, "ticked notes are removed")
click("All characters")
edit:SetText("Send gold to the alt")
click("Add")
check(#ns.db.notes == 1 and #ns.chardb.notes == 1, "the shared list is separate")
slash("home")
check(has("Send gold to the alt") and has("Train"), "home lists what is left to do")

---------------------------------------------------------------------------
say("--- vendor")
reset()
W.merchant = true
fire("MERCHANT_SHOW")
pump(1)
check(called("RepairAllItems") == 0 and called("UseContainerItem") == 0, "nothing is sold while Vendor is off")
fire("MERCHANT_CLOSED")
slash("vendor on")
check(ns.modules.vendor.enabled, "/zod vendor on")
reset()
W.merchant, W.repairCost = true, 1234
local gold = W.money
fire("MERCHANT_SHOW")
pump(1)
check(called("RepairAllItems") == 1, "repairs")
check(called("UseContainerItem") == 2, "sells the two grey items worth something, got " .. called("UseContainerItem"))
check(W.money == gold - 1234 + 400, "gold after repair and sale")
check(printed("sold 2 grey items for 4s.") and printed("repaired for 12s 34c"), "reports the sale and the repair")
check(W.bags[0][2] and W.bags[0][3], "keeps the white item and the grey one without value")
fire("MERCHANT_CLOSED")
reset()
W.bags[0][5] = { id = 104, quality = 0, count = 1, price = 10 }
W.shift, W.repairCost = true, 50
fire("MERCHANT_SHOW")
pump(1)
check(called("UseContainerItem") == 0 and called("RepairAllItems") == 0, "Shift skips the merchant automation")
fire("MERCHANT_CLOSED")
W.shift, W.repairCost = false, 999999999
fire("MERCHANT_SHOW")
pump(1)
check(called("RepairAllItems") == 0 and printed("not enough gold to repair"), "says so when the repair costs too much")
fire("MERCHANT_CLOSED")
W.merchant, W.repairCost = false, 0

---------------------------------------------------------------------------
say("--- info bar")
reset()
check(ZodUIDataBar == nil, "no bar is built while the module is off")
slash("databar on")
pump(1.5)
local bar = ZodUIDataBar
check(bar and bar:IsShown(), "the bar shows")
local text = plain(bar.text.text)
say("  " .. text)
check(text:find("Quests 12/25", 1, true), "bar has the quest count: " .. text)
for _, piece in ipairs({ "Level", "Bags", "Gear", "Hearth", "fps", "62.1" }) do
    check(not text:find(piece, 1, true), "'" .. piece .. "' is left to the EllesmereUI and Naowh bars")
end
check(not text:find("Mail", 1, true) and not text:find("Speed", 1, true), "no mail, and speed is off by default")
W.mail, W.speed = true, 11.2
ns.modules.databar.db.speed = true
pump(1.5)
text = plain(bar.text.text)
check(text:find("Mail", 1, true) and text:find("Speed 160%", 1, true), "mail and speed: " .. text)
check(bar:GetPoint(1) == "TOP", "bar starts at the top")
slash("settings")
slash("databar")
click("Top of the screen")
check(ns.modules.databar.db.where == "bottom" and bar:GetPoint(1) == "BOTTOM", "the position setting moves the bar")
W.shift = true
bar.scripts.OnDragStart(bar)
bar.scripts.OnDragStop(bar)
W.shift = false
check(ns.modules.databar.db.where == "free", "a dragged bar stays where it was dropped")
slash("")
click(bar)
check(ZodUIFrame:IsShown(), "clicking the bar opens ZodUI")
slash("databar off")
check(not bar:IsShown(), "the bar hides when the module is switched off")

---------------------------------------------------------------------------
say("--- tooltips")
local item = W.tooltipCalls[Enum.TooltipDataType.Item]
check(W.tooltipCalls[Enum.TooltipDataType.Spell] == nil, "spell tooltips are left to Naowh's ids")
W.bank = { [101] = 3 }
W.bags[0][5] = { id = 104, quality = 0, count = 1, price = 10 }
local tipDB = ns.modules.tooltip.db
check(tipDB.naowh == true and tipDB.count == false and tipDB.alts == false, "the count lines start off next to NaowhForever_QoL")
GameTooltip.lines = {}
item(GameTooltip, { id = 101 })
check(#GameTooltip.lines == 0, "so an item's tooltip is left as it is")
tipDB.count, tipDB.alts = true, true
ns.modules.tooltip:Disable()
ns.modules.tooltip:Enable()
check(tipDB.count == true and tipDB.alts == true, "ticking them again sticks")
GameTooltip.lines = {}
item(GameTooltip, { id = 101 })
check(#GameTooltip.lines == 1 and plain(GameTooltip.lines[1]) == "You have = 1 (+3 in the bank)", "count: " .. tostring(GameTooltip.lines[1]))
GameTooltip.lines = {}
item(GameTooltip, { id = 104 })
check(#GameTooltip.lines == 2 and GameTooltip.lines[2] == "ZodUI sells this at the next merchant.",
    "junk mark, no id: " .. table.concat(GameTooltip.lines, " / "))
local other = World.New("GameTooltip", UIParent)
item(other, { id = 104 })
check(#other.lines == 0, "other addons' tooltips are left alone")
GameTooltip.lines = {}
W.secret = 777
item(GameTooltip, { id = 777 })
check(#GameTooltip.lines == 0, "a secret id is not touched")
W.secret = nil

---------------------------------------------------------------------------
say("--- chat")
reset()
check(ns.modules.chat.Linkify == nil, "web addresses are left to EllesmereUIChat")
local filter = W.chatFilters["CHAT_MSG_SAY"]
check(filter and W.chatFilters["CHAT_MSG_GUILD"] and W.chatFilters["CHAT_MSG_WHISPER"], "chat filters are installed")
local r = { filter(nil, "CHAT_MSG_SAY", "go to www.example.org", "Bob", "x") }
check(#r == 1 and r[1] == false, "a web address is left as it is")
r = { filter(nil, "CHAT_MSG_SAY", "hello", "Bob") }
check(#r == 1 and r[1] == false, "a plain message is left alone")
W.secret = "secret text"
r = { filter(nil, "CHAT_MSG_SAY", W.secret, "Bob") }
check(#r == 1 and r[1] == false, "a secret message is left alone")
W.secret = nil
filter(nil, "CHAT_MSG_GUILD", "is ZOD online?", "Bob")
filter(nil, "CHAT_MSG_GUILD", "zod?", "Bob")
check(called("PlaySound", 3081) == 1, "one sound for a mention, not one per message")
filter(nil, "CHAT_MSG_SAY", "zod", "Bob")
check(called("PlaySound") == 1, "no mention sound for /say")
---------------------------------------------------------------------------
say("--- alerts")
reset()
W.durability[1] = { 10, 100 }
fire("UPDATE_INVENTORY_DURABILITY")
check(#W.alerts == 0, "worn gear is left to Naowh's durability warning")
W.durability[1] = { 80, 100 }
W.bags[1] = {}
for slot = 1, 12 do W.bags[1][slot] = { id = 200, quality = 1 } end
W.bags[2] = {}
for slot = 1, 12 do W.bags[2][slot] = { id = 200, quality = 1 } end
for slot = 5, 16 do W.bags[0][slot] = { id = 200, quality = 1 } end
fire("BAG_UPDATE_DELAYED")
check(W.alerts[1] == "Only 2 free bag slots left.", "bag warning: " .. tostring(W.alerts[1]))
fire("BAG_UPDATE_DELAYED")
check(#W.alerts == 1, "the bag warning is said once")
W.bags[0][16] = nil -- one sold: 3 free, just over the line
fire("BAG_UPDATE_DELAYED")
W.bags[0][16] = { id = 200, quality = 1 } -- and one looted: 2 free again
fire("BAG_UPDATE_DELAYED")
check(#W.alerts == 1, "selling one thing and looting the next does not warn again")
W.bags[0][15], W.bags[0][16] = nil, nil -- clearly more room: 4 free
fire("BAG_UPDATE_DELAYED")
W.bags[0][15], W.bags[0][16] = { id = 200, quality = 1 }, { id = 200, quality = 1 }
fire("BAG_UPDATE_DELAYED")
check(#W.alerts == 2, "after clearly more room, the warning comes back")
W.bags[1], W.bags[2] = nil, nil

---------------------------------------------------------------------------
say("--- invites and duels")
reset()
fire("DUEL_REQUESTED", "Bob")
check(called("CancelDuel") == 0, "duels are left alone while the module is off")
slash("social on")
fire("DUEL_REQUESTED", "Bob")
check(called("CancelDuel") == 1 and called("StaticPopup_Hide", "DUEL_REQUESTED") == 1 and printed("declined a duel from Bob"), "declines duels")
W.friends["guid-ann"] = true
fire("PARTY_INVITE_REQUEST", "Ann", false, false, false, true, false, "guid-ann")
fire("PARTY_INVITE_REQUEST", "Stranger", false, false, false, true, false, "guid-x")
check(called("AcceptGroup") == 1 and printed("joined Ann's group"), "joins a friend's group, not a stranger's")
slash("social off")

---------------------------------------------------------------------------
say("--- game settings")
reset()
slash("tweaks on")
check(called("SetCVar") == 0, "switching the module on changes nothing by itself")
ns.Show("settings", "tweaks")
pump(0.3)
click("Open the loot window at the mouse pointer")
check(W.cvars.lootUnderMouse == "1", "the loot window setting is applied")
click("Open the loot window at the mouse pointer")
check(W.cvars.lootUnderMouse == "0", "unticking puts the old value back")
W.cvars.cameraDistanceMaxZoomFactor = "2.6" -- set by a version that still offered it
ns.modules.tweaks.db.was.cameraDistanceMaxZoomFactor = "1.9"
ns.modules.tweaks:OnOption()
check(W.cvars.cameraDistanceMaxZoomFactor == "1.9" and ns.modules.tweaks.db.was.cameraDistanceMaxZoomFactor == nil,
    "a setting the module no longer offers is put back")
W.combat = true
click("Loot everything automatically")
check(W.cvars.autoLootDefault == "0", "nothing is changed in combat")
W.combat = false
fire("PLAYER_REGEN_ENABLED")
check(W.cvars.autoLootDefault == "1", "it is applied when combat ends")
slash("tweaks off")
check(W.cvars.autoLootDefault == "0", "switching the module off restores the game's settings")

---------------------------------------------------------------------------
say("--- the other addons parts of ZodUI need, said in their settings")
W.loaded.CodexForever = true
ns.Show("settings", "handouts")
pump(0.3)
check(has("Needs Forever Leveling BiS, for its stat weights"), "Hand-me-downs says it needs Forever Leveling BiS")
ns.Show("settings", "guide")
pump(0.3)
check(has("Needs ForeverDungeonJournal, for its map pictures"), "the Dungeon guide says what ForeverDungeonJournal is for")
ns.Show("settings", "general")
pump(0.3)
check(has("Needs Forever Leveling BiS") and has("Needs ForeverDungeonJournal") and has("Installed: Codex Forever"),
    "General lists every addon ZodUI's parts need, and which are installed")
W.loaded.CodexForever = nil

---------------------------------------------------------------------------
say("--- settings: every module, every control")
ns.Show("settings")
pump(0.3)
local page = ns.pages.settings
local clicks = 0
for _, rowButton in ipairs(page.rows) do
    click(rowButton)
    local detail = page.details[rowButton.mod.key]
    check(detail and detail:IsShown(), "settings show " .. rowButton.mod.key)
    local controls = {}
    for _, f in ipairs(W.frames) do
        if f.kind == "Button" and f.scripts.OnClick and f:IsVisible() then
            local r, inside = f, false
            while r do
                if r == detail then inside = true end
                r = r.parent
            end
            if inside then controls[#controls + 1] = f end
        end
    end
    for _, c in ipairs(controls) do
        for _ = 1, 2 do
            c.scripts.OnClick(c, "LeftButton")
            if c.scripts.OnEnter then c.scripts.OnEnter(c) end
            if c.scripts.OnLeave then c.scripts.OnLeave(c) end
            pump(0.3)
            clicks = clicks + 1
        end
    end
end
say("  clicked " .. clicks .. " times across " .. #page.rows .. " settings pages")
check(clicks > 100, "the settings pages have controls")
check(#ns.errors == 0, "no errors from the settings pages")

-- Text size and the minimap button.
ns.Show("settings", "nothing-by-this-name")
click(page.rows[1])
ns.db.general.minimap = true
ns.UpdateMinimap()
click("Show the minimap button")
check(not ZodUIMinimapButton:IsShown(), "the minimap button can be hidden")
click("Show the minimap button")
check(ZodUIMinimapButton:IsShown(), "and shown again")
ZodUIMinimapButton.scripts.OnDragStart(ZodUIMinimapButton)
ZodUIMinimapButton.scripts.OnUpdate(ZodUIMinimapButton, 0.1)
ZodUIMinimapButton.scripts.OnDragStop(ZodUIMinimapButton)
check(math.abs(ns.db.general.minimapAngle - 45) < 0.01, "dragging moves the minimap button: " .. ns.db.general.minimapAngle)
ZodUIFrame:Hide()
click(ZodUIMinimapButton, "RightButton")
check(ZodUIFrame:IsShown() and has("Settings for ZodUI as a whole."), "right-click on the minimap button opens Settings")

---------------------------------------------------------------------------
say("--- a module the client cannot support says so")
ns.modules.tooltip.unsupported = true
ns.Show("settings", "tooltip")
pump(0.3)
check(has("This game client lacks what the module needs"), "the settings page says the module does nothing here")
ns.modules.tooltip.unsupported = nil
pump(1.5)
check(not has("This game client lacks what the module needs"), "and not when it works")

---------------------------------------------------------------------------
say("--- items across characters")
reset()
local mine = ns.char.items
check(mine[101] and mine[101].bags == 1 and mine[101].bank == nil, "the bags were counted at login")
check(ns.db.itemNames[101] and ns.db.itemNames[101].name == "Item 101", "item names are remembered")
ns.db.chars["Bank-Forever"] = { name = "Bank", realm = "Forever", class = "ROGUE", level = 5,
    items = { [101] = { bags = 2, bank = 4 }, [900] = { bank = 1 } } }
ns.db.itemNames[900] = { name = "Mooncloth", q = 2 }
slash("items")
check(has("Item 101") and has("Mooncloth"), "the items page lists every character's items")
check(has("Zod 1,  Bank 6 (4 in the bank)"), "and who has how many, the bank apart")
check(has("different items on 2 characters"), "the hint counts items and characters")
local search = ns.pages.items.search.edit
local function typeIn(text)
    search:SetText(text)
    search.scripts.OnTextChanged(search, true)
    pump(0.3)
end
typeIn("MOON")
check(has("Mooncloth") and not has("Item 101") and has("1 item matches."), "typing filters by name, whatever the case")
typeIn("zzz")
check(has("No character has an item with that in its name."), "no match says so")
typeIn("")
check(has("Item 101"), "clearing the search shows everything again")

W.bags[6], W.bagSize[6] = { [1] = { id = 101, quality = 1, count = 3, price = 500 }, [2] = { id = 950, quality = 1, count = 20, price = 1 } }, 28
fire("BANKFRAME_OPENED")
pump(1.5)
check(mine[101].bank == 3 and mine[101].bags == 1 and mine[950].bank == 20, "the bank is counted while it is open")
fire("BANKFRAME_CLOSED")
W.bags[6], W.bagSize[6] = nil, 0
W.bags[0][9] = { id = 951, quality = 1, count = 2, price = 1 }
fire("BAG_UPDATE_DELAYED")
pump(1.5)
check(mine[101].bank == 3 and mine[950] and mine[950].bank == 20, "and remembered after it closes")
check(mine[951] and mine[951].bags == 2, "a new item in the bags is counted")
W.bags[0][9] = nil
fire("BAG_UPDATE_DELAYED")
pump(1.5)
check(mine[951] == nil, "an item that is gone is forgotten")

local tipItem = W.tooltipCalls[Enum.TooltipDataType.Item]
GameTooltip.lines = {}
ns.modules.tooltip.db.junk = false
tipItem(GameTooltip, { id = 101 })
check(#GameTooltip.lines == 2 and plain(GameTooltip.lines[2]) == "Bank = 6 (4 in the bank)",
    "the tooltip says what other characters have: " .. plain(table.concat(GameTooltip.lines, " / ")))
slash("items off")
GameTooltip.lines = {}
tipItem(GameTooltip, { id = 101 })
check(#GameTooltip.lines == 1, "not when the Items module is off")
slash("items")
check(has("The Items module is off"), "the page says the module is off")
slash("items on")
check(has("Mooncloth"), "and lists again when it is back on")
ns.db.chars["Bank-Forever"] = nil

---------------------------------------------------------------------------
say("--- dungeon runs")
reset()
local runs = ns.chardb.runs
check(runs and runs.current == nil and #runs.list == 0, "no run outside a dungeon")
W.instance = { "Shadowfang Keep", "party" }
fire("ZONE_CHANGED_NEW_AREA")
check(runs.current and runs.current.name == "Shadowfang Keep", "walking in starts a run")
local began = runs.current.start
pump(600, 5)
W.xp = W.xp + 500
fire("PLAYER_XP_UPDATE")
W.money = W.money + 250
fire("PLAYER_MONEY")
fire("PLAYER_DEAD")
slash("home")
check(has("Dungeon run") and has("Shadowfang Keep"), "Home shows the run while it lasts")
W.instance = nil
fire("ZONE_CHANGED_NEW_AREA")
check(runs.current and runs.current.left and #runs.list == 0, "walking out does not end it at once")
W.xp = W.xp + 40
fire("PLAYER_XP_UPDATE")
pump(120, 5)
W.instance = { "Shadowfang Keep", "party" }
fire("ZONE_CHANGED_NEW_AREA")
check(runs.current and runs.current.start == began and runs.current.left == nil, "walking back in within five minutes continues it")
pump(300, 5)
W.instance = nil
fire("ZONE_CHANGED_NEW_AREA")
pump(400, 5)
local done = runs.list[1]
check(runs.current == nil and done and done.name == "Shadowfang Keep", "five minutes outside ends the run")
check(done and done.took >= 1015 and done.took <= 1030, "it lasted from the first step in to the last step out: " .. tostring(done and done.took))
check(done and done.xp == 500 and done.gold == 250 and done.deaths == 1, "XP, gold and deaths inside are counted, those outside are not")
check(printed("Shadowfang Keep: ") and printed("500 XP, 2s 50c, 1 death."), "the run is summed up in chat")
slash("home")
check(not has("Dungeon run"), "the Home card is gone after the run")
W.instance = { "Ragefire Chasm", "party" }
fire("ZONE_CHANGED_NEW_AREA")
pump(20, 5)
W.instance = nil
fire("ZONE_CHANGED_NEW_AREA")
pump(400, 5)
check(runs.current == nil and #runs.list == 1, "a visit under a minute is not a run")
W.instance = { "Warsong Gulch", "pvp" }
fire("ZONE_CHANGED_NEW_AREA")
check(runs.current == nil, "a battleground is not a dungeon")
W.instance = nil
slash("runs")
check(has("Shadowfang Keep") and has("1 run, 17m inside"), "the page lists the run and sums them up")
slash("runs off")
check(has("The Dungeon runs module is off"), "the page says when the module is off")
slash("runs on")

---------------------------------------------------------------------------
say("--- history")
reset()
local diary = ns.chardb.history
local function sum(field)
    local n = 0
    for _, day in pairs(diary.days) do n = n + day[field] end
    return n
end
check(diary and sum("played") > 600, "time played is counted per day: " .. sum("played"))
local before = { xp = sum("xp"), quests = sum("quests"), deaths = sum("deaths"), gold = sum("gold") }
W.xp = W.xp + 300
fire("PLAYER_XP_UPDATE")
fire("QUEST_TURNED_IN", 1, 300, 0)
fire("PLAYER_DEAD")
W.money = W.money + 1000
fire("PLAYER_MONEY")
check(sum("xp") == before.xp + 300 and sum("quests") == before.quests + 1, "XP and quests go into the day")
check(sum("deaths") == before.deaths + 1 and sum("gold") == before.gold + 1000, "and deaths and gold")
slash("history")
check(has("XP a day, the last two weeks") and has("best day") and has("Today"), "the page charts the days and lists them")
for i = 1, 150 do diary.days[string.format("2020-%02d-%02d", (i - 1) % 12 + 1, (i - 1) % 28 + 1)] = { xp = 1, quests = 0, deaths = 0, levels = 0, gold = 0, played = 60 } end
slash("history off")
check(has("The History module is off"), "the page says when the module is off")
slash("history on")
local kept = 0
for _ in pairs(diary.days) do kept = kept + 1 end
check(kept <= 120, "only the last 120 days are kept, got " .. kept)

---------------------------------------------------------------------------
say("--- goals")
reset()
local goals = ns.modules.goals
slash("goals")
check(has("No goals yet."), "no goals at first")
local ok, said = goals:Add("item 10", 5)
check(not ok and said:find("More than one item", 1, true), "an unclear name is refused: " .. tostring(said))
ok, said = goals:Add("nonsense", 5)
check(not ok and said:find("has been in your bags", 1, true), "an unknown name is refused")
ok = goals:Add("Item 101", 0)
check(not ok and #ns.chardb.goals == 0, "a goal of zero is refused")
ok, said = goals:Add(" item 101 ", 10)
check(ok and said == "Added: 10 Item 101." and #ns.chardb.goals == 1, "a known name adds a goal: " .. tostring(said))
pump(0.5)
check(has("4 / 10") and has("40%"), "bags and bank count towards it")
goals.db.bank = false
slash("goals")
check(has("1 / 10"), "or the bags alone")
goals.db.bank = true
W.bags[0][2].count = 7
fire("BAG_UPDATE_DELAYED")
check(#W.alerts == 1 and W.alerts[1] == "Goal reached: 10 Item 101." and printed("Goal reached"), "reaching it is said once")
fire("BAG_UPDATE_DELAYED")
check(#W.alerts == 1, "and not again")
W.bags[0][2].count = 1
fire("BAG_UPDATE_DELAYED")
check(ns.chardb.goals[1].done == nil, "dropping below opens the goal again")
ok, said = goals:Add("Item 101", 30)
check(ok and #ns.chardb.goals == 1 and ns.chardb.goals[1].want == 30, "adding it again changes the number")
local gp = ns.pages.goals
gp.name.edit:SetText("900")
click("Add goal")
check(has("Added: 20 Mooncloth.") and #ns.chardb.goals == 2 and gp.name.edit:GetText() == "", "the page adds by item id too")
slash("home")
check(has("Goals", ZodUIFrame) and has("Mooncloth", ZodUIFrame), "Home shows the goals")
slash("goals")
gp.list.onClick(900)
click("Remove this goal")
check(#ns.chardb.goals == 1 and not has("Mooncloth"), "a goal can be removed")
slash("goals off")
check(has("The Goals module is off"), "the page says when the module is off")
slash("goals on")

---------------------------------------------------------------------------
say("--- gold goal")
ns.modules.gold.db.milestone = 0 -- the settings test may have put the round-sum notice back on
reset()
ok, said = goals:Add("Gold", 500)
check(ok and ns.chardb.goldGoal == 5000000 and plain(said) == "Saving up 500g.", "typing gold sets a gold goal: " .. tostring(said))
slash("goals")
check(has("Gold") and has(" / 500g"), "the page lists it")
local purse = W.money
W.money = 5000000
fire("PLAYER_MONEY")
fire("PLAYER_MONEY")
check(#W.alerts == 1 and plain(W.alerts[1]) == "Goal reached: 500g saved.", "reaching it is said once: " .. tostring(W.alerts[1]))
W.money = purse
fire("PLAYER_MONEY")
check(ns.chardb.goldDone == nil, "spending it opens the goal again")
slash("home")
check(has("500g", ZodUIFrame), "Home shows the gold goal")
slash("goals")
gp.list.onClick("gold")
click("Remove this goal")
check(ns.chardb.goldGoal == nil, "the gold goal can be removed")

---------------------------------------------------------------------------
say("--- reminders")
reset()
local remind = ns.modules.remind
slash("remind")
check(has("No reminders."), "no reminders at first")
ok, said = remind:Add(0, "x")
check(not ok, "zero minutes is refused")
ok, said = remind:Add(5, "  ")
check(not ok and said == "Type what to be reminded of.", "an empty reminder is refused")
slash("remind 20 Check the Auction")
check(printed("In 20m: Check the Auction") and #ns.db.reminders == 1, "/zod remind adds one and keeps the capitals")
slash("remind soon")
check(printed("use /zod remind <minutes> <what>"), "a bad /zod remind says how")
local rp = ns.pages.remind
rp.minutes.edit:SetText("2")
rp.text.edit:SetText("Hearth is up")
click("Remind me")
check(#ns.db.reminders == 2 and ns.db.reminders[1].text == "Hearth is up" and rp.text.edit:GetText() == "", "the page adds one, soonest first")
check(has("Hearth is up") and (has("in 2m") or has("in 1m")), "and lists it with the time left")
pump(60, 1)
check(#W.alerts == 0, "nothing is said before it is due")
pump(70, 1)
check(#W.alerts == 1 and W.alerts[1] == "Reminder: Hearth is up" and called("PlaySound") == 1, "it is said when due, with a sound")
pump(30, 1)
check(#W.alerts == 1, "and only once")
slash("home")
check(has("Reminders", ZodUIFrame) and has("Check the Auction", ZodUIFrame), "Home shows the reminders")
slash("remind")
click("Remove the ones that rang")
check(#ns.db.reminders == 1 and ns.db.reminders[1].text == "Check the Auction", "the ones that rang can be cleared")
rp.list.onClick(ns.db.reminders[1])
click("Remove this one")
check(#ns.db.reminders == 0, "and one can be removed")
slash("remind off")
slash("remind 5 nothing")
check(printed("Reminders is off.") and #ns.db.reminders == 0, "the command says when the module is off")
slash("remind on")

---------------------------------------------------------------------------
say("--- look: accent, size, fights")
reset()
local T = ns.T
T.ApplyAccent("ice")
check(T.GOLD[1] == 0.40 and T.GOLD[3] == 1, "an accent colour replaces the gold")
T.ApplyAccent("class", "MAGE")
check(math.abs(T.GOLD[1] - 0x69 / 255) < 0.001 and math.abs(T.GOLD[2] - 0xcc / 255) < 0.001, "the class colour can be the accent")
T.ApplyAccent("nonsense")
check(T.GOLD[1] == 1 and T.GOLD[2] == 0.82 and T.GOLD[3] == 0, "an unknown accent falls back to gold")
slash("home")
ns.db.general.scale = 120
ns.ApplyScale()
check(ZodUIFrame.scale == 1.2, "the window size setting scales the window")
ns.db.general.scale = 100
ns.ApplyScale()
fire("PLAYER_REGEN_DISABLED")
check(not ZodUIFrame:IsShown(), "the window closes when a fight starts")
ns.db.general.combatClose = false
slash("home")
fire("PLAYER_REGEN_DISABLED")
check(ZodUIFrame:IsShown(), "unless that is switched off")
ns.db.general.combatClose = true
fire("PLAYER_REGEN_ENABLED")
slash("databar on")
fire("PLAYER_REGEN_DISABLED")
check(ZodUIDataBar.alpha == 0.35, "the info bar fades during a fight")
fire("PLAYER_REGEN_ENABLED")
check(ZodUIDataBar.alpha == 1, "and comes back after it")
slash("databar off")
slash("home")

---------------------------------------------------------------------------
say("--- notices")
reset()
ns.db.general.toasts = true
ns.Alert("Notice one")
check(#ns.toasts == 1 and #W.alerts == 0 and has("Notice one") and printed("Notice one"), "an alert shows as a ZodUI notice and in chat")
for i = 2, 6 do ns.Alert("Notice " .. i) end
check(#ns.toasts == 4 and has("Notice 6") and not has("Notice one"), "at most four at a time, the newest kept")
pump(4)
check(#ns.toasts == 4, "a notice stays a few seconds")
pump(3)
check(#ns.toasts == 0 and not has("Notice 6"), "and then goes away")
slash("test")
check(#ns.toasts == 1 and has("This is what a ZodUI notice looks like."), "/zod test shows a sample")
ns.toasts[1].scripts.OnMouseUp(ns.toasts[1])
check(#ns.toasts == 0, "a click dismisses a notice")
ns.db.general.toasts = false
ns.Alert("Old style")
check(#ns.toasts == 0 and W.alerts[1] == "Old style", "switched off, alerts use the game's error text")

---------------------------------------------------------------------------
say("--- sharing settings")
reset()
ns.db.general.accent, ns.db.general.scale, ns.db.general.font = "gold", 100, 1 -- the settings test clicked through these
ns.modules.vendor.db.report = true
ns.modules.kills:Enable()
ns.modules.vendor:Enable()
local text = ns.Export()
check(text:sub(1, 5) == "ZOD1;" and text:find("vendor.enabled=b1", 1, true) and text:find("general.accent=sgold", 1, true)
    and text:find("general.scale=n100", 1, true), "the export lists every setting")
check(not text:find("minimapAngle", 1, true) and not text:find("conflict", 1, true), "but not positions or why a module started off")
ns.modules.vendor.db.report = false
ns.modules.kills:Disable()
ns.db.general.font = 3
ok, said = ns.Import("  " .. text .. "  ")
check(ok and said:find("settings taken over", 1, true), "the text can be taken back: " .. tostring(said))
check(ns.modules.vendor.db.report == true and ns.modules.kills.enabled and ns.db.general.font == 1, "and puts every setting back")
ok, said = ns.Import("hello")
check(not ok and said:find("starts with ZOD1", 1, true), "other text is refused")
ok = ns.Import("ZOD1;vendor.nonsense=b1;bogus.x=n1;vendor.report=sx;general.font=b1")
check(not ok and ns.modules.vendor.db.report == true and ns.db.general.font == 1, "unknown settings and wrong kinds of value are left out")
ns.db.general.accent = "a;b=c:d%"
local odd = ns.Export()
check(odd:find("general.accent=sa%3Bb%3Dc%3Ad%25", 1, true), "text with ; = : % in it is written safely")
ns.db.general.accent = "gold"
ns.Import(odd)
check(ns.db.general.accent == "a;b=c:d%", "and read back as it was")
ns.db.general.accent = "gold"
slash("export")
check(ZodUIShareBox:IsShown() and ZodUIShareBox.input.edit:GetText() == ns.Export() and has("Your ZodUI settings"), "/zod export shows the text to copy")
ns.db.general.welcome = false
local saved = ns.Export()
ns.db.general.welcome = true
slash("import")
check(has("Take over ZodUI settings") and ZodUIShareBox.input.edit:GetText() == "", "/zod import asks for a text")
ZodUIShareBox.input.edit:SetText(saved)
click("Take these settings")
check(ns.db.general.welcome == false and has("settings taken over"), "and takes it")
ns.db.general.welcome = true
click("Close")
check(not ZodUIShareBox:IsShown(), "the box closes")

---------------------------------------------------------------------------
say("--- searching the settings")
slash("settings")
local sp = ns.pages.settings
local function visibleRows()
    local n = 0
    for _, row in ipairs(sp.rows) do
        if row:IsShown() then n = n + 1 end
    end
    return n
end
check(visibleRows() == #ns.order + 1 and has("Search settings"), "every module is listed, with a search box")
sp.search.edit:SetText("GREY")
sp.search.edit.scripts.OnTextChanged(sp.search.edit, true)
pump(0.3)
local grey = {}
for _, row in ipairs(sp.rows) do
    if row:IsShown() then grey[row.mod.key] = true end
end
check(grey.vendor and grey.tooltip and not grey.session and not grey.general and visibleRows() < 6 and not has("Search settings"),
    "typing keeps the modules with a matching setting: " .. visibleRows())
check(grey[sp.selected.key], "and shows the first of them")
sp.search.edit:SetText("zzzz")
sp.search.edit.scripts.OnTextChanged(sp.search.edit, true)
pump(0.3)
check(visibleRows() == 0 and has("No setting matches."), "no match says so")
sp.search.edit:SetText("")
sp.search.edit.scripts.OnTextChanged(sp.search.edit, true)
pump(0.3)
check(visibleRows() == #ns.order + 1, "clearing it lists everything again")

---------------------------------------------------------------------------
say("--- unlock mode")
reset()
slash("databar on")
slash("unlock")
local handles = ns.moverHandles
check(ns.IsUnlocked() and has("drag the gold boxes") and handles.toasts and handles.toasts:IsShown(), "/zod unlock shows a box for the notices")
check(handles.databar and handles.databar:IsShown(), "and one for the info bar")
local box = handles.toasts
box.scripts.OnDragStart(box)
box:ClearAllPoints()
box:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 40, -300)
box.scripts.OnDragStop(box)
check(ns.db.movers.toasts.point == "TOPLEFT" and ns.db.movers.toasts.x == 40, "dropping the box saves where it is")
ns.db.general.toasts = true
ns.Alert("Moved one")
ns.Alert("Moved two")
local p1, _, _, x1, y1 = ns.toasts[1]:GetPoint(1)
local _, _, _, _, y2 = ns.toasts[2]:GetPoint(1)
check(p1 == "TOPLEFT" and x1 == 40 and y1 == -300 and y2 == -334, "the notices show where the box was dropped, stacked down")
ns.db.general.toasts = false
pump(7)
box = handles.databar
box.scripts.OnDragStart(box)
box:ClearAllPoints()
box:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 10, 90)
box.scripts.OnDragStop(box)
check(ns.modules.databar.db.where == "free" and ZodUIDataBar:GetPoint(1) == "BOTTOMLEFT", "the info bar follows its box")
slash("lock")
check(not ns.IsUnlocked() and not has("drag the gold boxes") and not handles.toasts:IsShown(), "/zod lock puts the boxes away")
slash("unlock")
fire("PLAYER_REGEN_DISABLED")
check(not ns.IsUnlocked(), "a fight locks it too")
fire("PLAYER_REGEN_ENABLED")
slash("reset")
check(ns.db.movers.toasts.point == nil and ns.modules.databar.db.pos.point == nil, "/zod reset puts both back")
slash("databar off")
slash("unlock")
check(not handles.databar:IsShown(), "a module that is off gets no box")
slash("lock")

---------------------------------------------------------------------------
say("--- modules page and what's new")
slash("setup")
local setup = ns.pages.setup
check(has("Tick what you want ZodUI to do") and has("NaowhForever_QoL does this too."), "the Modules page lists every module and why one is off")
setup.checks.vendor.scripts.OnClick(setup.checks.vendor)
check(not ns.modules.vendor.enabled, "unticking switches a module off")
setup.checks.vendor.scripts.OnClick(setup.checks.vendor)
check(ns.modules.vendor.enabled and setup.checks.vendor.checked, "ticking switches it on")
click("What's new")
check(has(ns.version .. "  this version") and has("/zod unlock shows a box"), "the title bar button opens What's new")
local inList = false
for _, b in ipairs(ZodUIFrame.nav) do
    if b.page.key == "news" then inList = true end
end
check(not inList and ns.NEWS[1][1] == ns.version, "it is not in the list on the left, and its first entry is this version")
slash("news")
check(has("What's new"), "/zod news opens it too")

---------------------------------------------------------------------------
say("--- search")
reset()
local function found(results, kind, text)
    for _, r in ipairs(results) do
        if r[1] == kind and r[2] == text then return r end
    end
end
slash("find GREY")
check(has("found for 'grey'") and has("Sell grey items") and ZodUIFrame.find.edit:GetText() == "grey", "/zod find lists what matches")
check(found(ns.Find("reput"), "Page", "Reputation") and found(ns.Find("reput"), "Module", "Reputation"), "pages and modules are found")
check(found(ns.Find("accent"), "Setting", "Accent colour"), "and settings, General's too")
ns.db.chars["Bank-Forever"] = { name = "Bank", realm = "Forever", class = "ROGUE", level = 5, zone = "Orgrimmar", items = { [900] = { bank = 1 } } }
ns.modules.notes:Add("Buy moonberry juice", "char")
remind:Add(30, "Moonwell water")
local moon = ns.Find("moon")
local hit = found(moon, "Item", "Mooncloth")
check(hit and hit[3] == "1 across your characters" and found(moon, "To do", "Buy moonberry juice") and found(moon, "Reminder", "Moonwell water"),
    "items, to-dos and reminders are found")
check(found(ns.Find("item 101"), "Goal", "Item 101") and found(ns.Find("bank"), "Character", "Bank"), "and goals and characters")
local fe = ZodUIFrame.find.edit
local function searchFor(text)
    fe:SetText(text)
    fe.scripts.OnTextChanged(fe, true)
    pump(0.3)
end
searchFor("moon")
ns.pages.find.list.onClick(hit)
pump(0.3)
check(ns.pages.items.search.edit:GetText() == "Mooncloth" and has("Bank 1 (1 in the bank)") and not has("Item 101"),
    "clicking an item opens the Items page on it")
searchFor("")
slash("gold")
searchFor("v")
check(not has("found for"), "one letter is not searched for")
searchFor("vend")
check(has("found for 'vend'"), "two or more are")
searchFor("")
check(not has("found for") and has("Search ZodUI"), "clearing the box goes back to the page before")
searchFor("qqqq")
check(has("0 found for 'qqqq'") and has("Nothing in ZodUI matches."), "no match says so")
searchFor("")
ns.db.chars["Bank-Forever"] = nil
table.remove(ns.chardb.notes)
remind:Remove(ns.db.reminders[1])
ns.pages.items.search.edit:SetText("")
ns.pages.items.search.edit.scripts.OnTextChanged(ns.pages.items.search.edit, true)

---------------------------------------------------------------------------
say("--- groups in the list on the left")
ns.Show("home")
pump(0.3)
local keys = {}
for i, b in ipairs(ZodUIFrame.nav) do keys[i] = b.page.key end
check(table.concat(keys, " ") == "home session history questlog kills loot rolls deaths runs zones story coach milestones gold rep alts items notes remind goals raids loans board commands setup settings",
    "the pages are in order of their groups: " .. table.concat(keys, " "))
check(#ZodUIFrame.navHeads == 4 and has("THIS CHARACTER") and has("ALL CHARACTERS") and has("PLANNING"), "each group has a heading")
local function navShown()
    local n = 0
    for _, b in ipairs(ZodUIFrame.nav) do if b:IsShown() then n = n + 1 end end
    return n
end
local full = ZodUIFrame.navFrame:GetHeight()
check(full > ZodUIFrame.navScroll:GetHeight() and navShown() == #ZodUIFrame.nav, "every page is listed, and the list scrolls when it is taller than the panel")
local inGroup = 0
for _, b in ipairs(ZodUIFrame.nav) do if b.page.group == "This character" then inGroup = inGroup + 1 end end
click("THIS CHARACTER")
check(ns.db.window.collapsed["This character"] and inGroup >= 11 and navShown() == #ZodUIFrame.nav - inGroup,
    "a click on a heading folds its pages away: " .. navShown())
check(ZodUIFrame.navFrame:GetHeight() < full and has("THIS CHARACTER"), "the list gets shorter, the heading stays")
ns.Show("coach")
pump(0.3)
check(navShown() == #ZodUIFrame.nav - inGroup + 1, "the open page stays in sight in a folded group")
ns.Show("home")
click("THIS CHARACTER")
check(not ns.db.window.collapsed["This character"] and navShown() == #ZodUIFrame.nav, "a second click brings them back")

---------------------------------------------------------------------------
say("--- search: factions, dungeon runs, more than it shows")
local booty = found(ns.Find("booty"), "Faction", "Booty Bay")
check(booty and booty[3]:find("Neutral, ", 1, true) and booty.key == "rep", "a faction is found with its standing: " .. tostring(booty and booty[3]))
check(not found(ns.Find("horde"), "Faction", "Horde"), "a heading in the reputation list is not a faction")
local keptRuns = ns.chardb.runs and ns.chardb.runs.list
ns.chardb.runs = ns.chardb.runs or {}
ns.chardb.runs.list = {
    { name = "Wailing Caverns", kind = "party", at = W.clock - 9000, took = 2400, xp = 100, gold = 0, deaths = 0, level = 20 },
    { name = "Wailing Caverns", kind = "party", at = W.clock - 5000, took = 1800, xp = 100, gold = 0, deaths = 1, level = 20 },
    { name = "Deadmines", kind = "party", at = W.clock - 2000, took = 1500, xp = 100, gold = 0, deaths = 0, level = 21 },
}
local wc = found(ns.Find("wailing"), "Dungeon", "Wailing Caverns")
check(wc and wc[3] == "2 runs, fastest 30m" and wc.key == "runs", "a dungeon is found once, with its runs: " .. tostring(wc and wc[3]))
local dm = found(ns.Find("deadm"), "Dungeon", "Deadmines")
check(dm and dm[3] == "1 run, 25m", "one run reads as one")
ns.chardb.runs.list = keptRuns or {}
local keptReminders = ns.db.reminders
ns.db.reminders = {}
for i = 1, 120 do ns.db.reminders[i] = { text = "capcheck " .. i, at = W.clock + 6000 + i } end
local many = ns.Find("capcheck")
check(#many == 100 and many.total == 120, "the search keeps 100 results and counts the rest")
searchFor("capcheck")
check(has("The first 100 of 120 found for 'capcheck'"), "and the page says so")
searchFor("")
ns.db.reminders = keptReminders

---------------------------------------------------------------------------
say("--- daily to-dos")
do
    local notes = ns.modules.notes
    local kept = ns.chardb.notes
    ns.chardb.notes = {}
    notes:Add("Hand in the cloth", "char", true)
    notes:Add("Buy a mount", "char")
    local daily, once = ns.chardb.notes[1], ns.chardb.notes[2]
    check(daily.daily == true and once.daily == nil, "a to-do can be a daily one")
    ns.Show("notes")
    pump(0.3)
    click("This character")
    check(has("Hand in the cloth  daily"), "and is marked in the list")
    local rows = ns.pages.notes.rows
    rows[1].check.scripts.OnClick(rows[1].check)
    rows[2].check.scripts.OnClick(rows[2].check)
    pump(0.3)
    check(daily.done == true and daily.day == ns.Today() and once.done == true, "ticking remembers the day")
    daily.day, once.day = "2001-01-01", "2001-01-01"
    pump(1.5)
    check(daily.done == nil and once.done == true, "a daily one is open again the next day, another stays ticked")
    rows[1].check.scripts.OnClick(rows[1].check)
    click("Remove the ticked ones")
    check(#ns.chardb.notes == 1 and ns.chardb.notes[1] == daily, "removing the ticked ones leaves the daily ones")
    ns.pages.notes.input.edit:SetText("Feed the pet")
    click("Add daily")
    check(#ns.chardb.notes == 2 and ns.chardb.notes[2].daily == true, "the Add daily button adds one")
    ns.chardb.notes = kept or {}
end

---------------------------------------------------------------------------
say("--- reminders: repeating, at a time of day, snooze")
do
    local kept = ns.db.reminders
    ns.db.reminders = {}
    reset()
    slash("remind every 30 Stretch")
    local again = ns.db.reminders[1]
    check(again and again.every == 30 and printed("In 30m: Stretch, then every 30m"), "/zod remind every makes a repeating one")
    slash("remind")
    check(has("Stretch  every 30m") and has("Repeat"), "the page shows that it repeats")
    again.at = time() - 5
    reset()
    pump(2)
    check(printed("Reminder: Stretch") and not again.due and again.at > time() + 1700, "it rings and is set again")
    remind:Add(1, "Once")
    local one
    for _, entry in ipairs(ns.db.reminders) do
        if entry.text == "Once" then one = entry end
    end
    one.at = time() - 5
    pump(2)
    check(one.due == true, "one that does not repeat rings once")
    reset()
    slash("remind snooze")
    check(not one.due and one.at >= time() + 590 and printed("1 reminder snoozed 10 minutes."), "/zod remind snooze gives it ten more minutes")
    reset()
    slash("remind snooze")
    check(printed("Nothing rang."), "and says when nothing rang")
    one.at = time() - 5
    pump(2)
    slash("remind")
    click("Snooze them 10 min")
    check(not one.due, "the button on the page does the same")
    reset()
    slash("remind 23:59 Midnight snack")
    local snack
    for _, entry in ipairs(ns.db.reminders) do
        if entry.text == "Midnight snack" then snack = entry end
    end
    check(snack and date("%H:%M", snack.at) == "23:59" and printed("(at 23:59)"), "/zod remind 23:59 sets one for that time: "
        .. tostring(snack and date("%H:%M", snack.at)))
    reset()
    slash("remind 25:00 never")
    check(printed("use /zod remind <minutes> <what>"), "a time that does not exist says how")
    rp.again.scripts.OnClick(rp.again)
    rp.minutes.edit:SetText("45")
    rp.text.edit:SetText("Drink water")
    click("Remind me")
    local water
    for _, entry in ipairs(ns.db.reminders) do
        if entry.text == "Drink water" then water = entry end
    end
    check(water and water.every == 45, "ticking Repeat on the page makes a repeating one")
    rp.again.scripts.OnClick(rp.again)
    ns.db.reminders = kept
end

---------------------------------------------------------------------------
say("--- a new standing is said")
do
    local rep = ns.modules.rep
    local was = W.factions[3].reaction
    reset()
    W.factions[3].reaction = was + 1
    fire("UPDATE_FACTION")
    check(printed("Orgrimmar: now Friendly."), "a faction's new standing is said")
    rep.db.alert = false
    reset()
    W.factions[3].reaction = was + 2
    fire("UPDATE_FACTION")
    check(not printed("Orgrimmar: now"), "not when the option is off")
    rep.db.alert = true
    W.factions[3].reaction = was
    fire("UPDATE_FACTION")
end

---------------------------------------------------------------------------
say("--- dungeons, one line each")
do
    local kept = ns.chardb.runs and ns.chardb.runs.list
    ns.chardb.runs = ns.chardb.runs or {}
    ns.chardb.runs.list = {
        { name = "Wailing Caverns", kind = "party", at = W.clock - 9000, took = 2400, xp = 3000, gold = 0, deaths = 0, level = 20 },
        { name = "Wailing Caverns", kind = "party", at = W.clock - 5000, took = 1800, xp = 5000, gold = 0, deaths = 1, level = 20 },
        { name = "Deadmines", kind = "party", at = W.clock - 2000, took = 1500, xp = 100, gold = 0, deaths = 0, level = 21 },
    }
    ns.Show("runs")
    pump(0.3)
    click("By dungeon")
    local each = ns.pages.runs.each
    check(each:IsShown() and not ns.pages.runs.list:IsShown() and has("Average") and has("35m") and has("4,000"),
        "By dungeon shows one line per dungeon with fastest, average and XP a run")
    click("Every run")
    check(ns.pages.runs.list:IsShown() and not each:IsShown(), "Every run goes back")
    ns.chardb.runs.list = kept or {}
end

---------------------------------------------------------------------------
say("--- loot filter, Enter in the search box")
do
    ns.Show("loot")
    pump(0.3)
    local lp = ns.pages.loot
    local e = lp.search.edit
    e:SetText("zzzz")
    e.scripts.OnTextChanged(e, true)
    pump(0.3)
    check(has("Nothing looted matches."), "the loot filter says when nothing matches")
    e:SetText("")
    e.scripts.OnTextChanged(e, true)
    pump(0.3)
    check(not has("Nothing looted matches.") and has("Filter by name"), "clearing it lists everything again")
    searchFor("booty")
    fe.scripts.OnEnterPressed(fe)
    pump(0.3)
    check(has("Since login") and not has("found for"), "Enter in the search box opens the first result")
    searchFor("")
end

---------------------------------------------------------------------------
say("--- pages of modules that are off")
do
    local function listed(key)
        for _, b in ipairs(ZodUIFrame.nav) do
            if b.page.key == key then return b:IsShown() end
        end
    end
    ns.Show("home")
    slash("goals off")
    pump(1.5)
    check(not listed("goals") and listed("remind"), "a module that is off has no page in the list")
    ns.Show("goals")
    pump(0.3)
    check(listed("goals"), "the page that is open stays listed")
    ns.Show("home")
    ns.db.general.hideOff = false
    pump(1.5)
    check(listed("goals"), "the option lists them all again")
    ns.db.general.hideOff = true
    slash("goals on")
    slash("alts off")
    slash("items off")
    pump(1.5)
    check(listed("goals") and not has("ALL CHARACTERS"), "a group with no page left loses its heading")
    slash("alts on")
    slash("items on")
    pump(1.5)
    check(has("ALL CHARACTERS") and listed("items"), "and gets it back")
end

---------------------------------------------------------------------------
say("--- the guild bank pays for the repair")
do
    reset()
    W.merchant, W.repairCost, W.guild, W.guildRepair, W.guildMoney = true, 500, true, true, 100000
    local mine = W.money
    fire("MERCHANT_SHOW")
    pump(1)
    check(called("RepairAllItems", true) == 1 and W.money >= mine and W.guildMoney == 99500, "the guild bank pays")
    check(printed("the guild bank repaired your gear for 5s"), "and that is said")
    fire("MERCHANT_CLOSED")
    reset()
    W.repairCost, W.guildLimit = 500, 200
    fire("MERCHANT_SHOW")
    pump(1)
    check(called("RepairAllItems", false) == 1 and called("RepairAllItems", true) == 0, "over the withdraw limit you pay yourself")
    fire("MERCHANT_CLOSED")
    reset()
    W.repairCost, W.guildLimit = 500, nil
    ns.modules.vendor.db.guildRepair = false
    fire("MERCHANT_SHOW")
    pump(1)
    check(called("RepairAllItems", false) == 1, "with the option off you pay yourself")
    fire("MERCHANT_CLOSED")
    ns.modules.vendor.db.guildRepair = true
    W.merchant, W.repairCost, W.guild, W.guildRepair, W.guildMoney = false, 0, nil, nil, nil
end

---------------------------------------------------------------------------
say("--- resurrections and summons")
do
    reset()
    slash("social on")
    fire("RESURRECT_REQUEST", "Mia")
    check(called("AcceptResurrect") == 0, "a resurrection is left to you unless you tick it")
    ns.modules.social.db.res, ns.modules.social.db.summon = true, true
    W.fighting.Mia = true
    fire("RESURRECT_REQUEST", "Mia")
    check(called("AcceptResurrect") == 0, "not while the caster is fighting")
    W.fighting.Mia = nil
    fire("RESURRECT_REQUEST", "Mia")
    check(called("AcceptResurrect") == 1 and called("StaticPopup_Hide", "RESURRECT") == 1 and printed("took the resurrection from Mia"),
        "taken when the caster is out of combat")
    W.summoner = "Lok"
    fire("CONFIRM_SUMMON")
    check(called("ConfirmSummon") == 0, "a summons from someone outside the group is left to you")
    W.party.Lok = true
    W.combat = true
    fire("CONFIRM_SUMMON")
    check(called("ConfirmSummon") == 0, "not in a fight")
    W.combat = false
    fire("CONFIRM_SUMMON")
    check(called("ConfirmSummon") == 1 and printed("took the summons from Lok"), "a summons from the group is taken")
    ns.modules.social.db.res, ns.modules.social.db.summon = false, false
    W.party.Lok, W.summoner = nil, nil
    slash("social off")
end

---------------------------------------------------------------------------
say("--- rested XP runs out, ammunition runs low")
do
    reset()
    local before = #W.alerts
    W.rested = 500
    fire("PLAYER_XP_UPDATE")
    W.rested = 0
    fire("PLAYER_XP_UPDATE")
    check(W.alerts[before + 1] == "Your rested XP has run out.", "rested XP running out is said: " .. tostring(W.alerts[before + 1]))
    fire("PLAYER_XP_UPDATE")
    check(#W.alerts == before + 1, "once")
    W.rested = 3000
    fire("PLAYER_XP_UPDATE")
    W.ammo = 600
    fire("BAG_UPDATE_DELAYED")
    check(#W.alerts == before + 1, "plenty of arrows is not news")
    W.ammo = 150
    fire("PLAYER_REGEN_ENABLED")
    check(W.alerts[#W.alerts] == "Only 150 arrows or bullets left.", "low arrows are said: " .. tostring(W.alerts[#W.alerts]))
    W.ammo = 90
    fire("PLAYER_REGEN_ENABLED")
    check(#W.alerts == before + 2, "once until you buy more")
    ns.Show("home")
    pump(0.3)
    check(has("Arrows or bullets"), "Home shows the arrows")
    W.ammo = 1000
    fire("BAG_UPDATE_DELAYED")
    W.ammo = 0
    fire("PLAYER_REGEN_ENABLED")
    check(W.alerts[#W.alerts] == "You are out of arrows or bullets.", "and when they are gone")
    W.ammo = nil
    fire("BAG_UPDATE_DELAYED")
    ns.Show("home")
    pump(0.3)
    check(not has("Arrows or bullets"), "no ammo slot, no line")
end

---------------------------------------------------------------------------
say("--- your name in gold")
do
    local Highlight = ns.modules.chat.Highlight
    local out, n = Highlight("is ZOD here? zodiac no, zod yes")
    check(n == 2 and out == "is |cffffd100ZOD|r here? zodiac no, |cffffd100zod|r yes", "whole words, any capitals: " .. out)
    out, n = Highlight("see www.zod.com")
    check(n == 0, "not inside a web address")
    out, n = Highlight("|cff00ff00zod|r")
    check(n == 0, "a message with colours is left alone")
    local filter = W.chatFilters["CHAT_MSG_GUILD"]
    local r = { filter(nil, "CHAT_MSG_GUILD", "hi zod", "Bob", "x") }
    check(r[2] == "hi |cffffd100zod|r" and r[3] == "Bob" and r[4] == "x", "the filter paints it")
    r = { filter(nil, "CHAT_MSG_GUILD", "I am zod", "Zod-Forever") }
    check(#r == 1, "not in what you write yourself")
    r = { filter(nil, "CHAT_MSG_WHISPER_INFORM", "zod here", "Bob") }
    check(#r == 1, "not in whispers you send")
    ns.modules.chat.db.highlight = false
    r = { filter(nil, "CHAT_MSG_GUILD", "hi zod", "Bob") }
    check(#r == 1, "the option turns it off")
    ns.modules.chat.db.highlight = true
end

---------------------------------------------------------------------------
say("--- /zod where")
do
    reset()
    slash("where")
    check(printed("you are in Hillsbrad Foothills, Tarren Mill (62.1, 20.5)."), "says where you stand")
    slash("where party")
    check(printed("you are not in a group") and called("SendChatMessage") == 0, "not in a group: nothing is sent")
    W.party.Lok = true
    slash("where party")
    check(called("SendChatMessage", "Hillsbrad Foothills, Tarren Mill (62.1, 20.5)") == 1 and W.calls[#W.calls][3] == "PARTY", "said to the group")
    W.party.Lok = nil
    W.guild = true
    slash("where guild")
    check(W.calls[#W.calls][3] == "GUILD", "said to the guild")
    W.guild = nil
    slash("where moon")
    check(printed("use /zod where, /zod where party or /zod where guild."), "a wrong word explains")
end

---------------------------------------------------------------------------
say("--- two more game settings")
do
    slash("tweaks on")
    ns.modules.tweaks.db.profanity, ns.modules.tweaks.db.shots = true, true
    ns.modules.tweaks:OnOption("profanity")
    check(W.cvars.profanityFilter == "0" and W.cvars.screenshotQuality == "10", "the language filter is off and screenshots are best quality")
    slash("tweaks off")
    check(W.cvars.profanityFilter == "1" and W.cvars.screenshotQuality == "3", "and both are put back")
    ns.modules.tweaks.db.profanity, ns.modules.tweaks.db.shots = false, false
end

---------------------------------------------------------------------------
say("--- a to-do moves up")
do
    for i = #ns.chardb.notes, 1, -1 do ns.chardb.notes[i] = nil end
    ns.modules.notes:Add("First", "char")
    ns.modules.notes:Add("Second", "char")
    ns.Show("notes")
    pump(0.3)
    if button("This character") then click("This character") end
    local rows = ns.pages.notes.rows
    check(not rows[1].up:IsShown() and rows[2].up:IsShown(), "the top line has no up button")
    click(rows[2].up)
    check(ns.chardb.notes[1].text == "Second" and ns.chardb.notes[2].text == "First", "the second line moved up")
end

---------------------------------------------------------------------------
say("--- XP per hour on the info bar")
do
    slash("databar on")
    ns.modules.databar.db.rate = true
    local bar = ZodUIDataBar
    fire("PLAYER_XP_UPDATE")
    pump(1.2)
    local per = ns.modules.session:Rate()
    check(per > 0 and plain(bar.text:GetText()):find("XP/h [%d,]+"),
        "the bar shows XP per hour: " .. plain(bar.text:GetText()))
    ns.modules.databar.db.rate = false
    slash("databar off")
end


---------------------------------------------------------------------------
say("--- the window remembers, fades, hides cards; notices")
do
    reset()
    ns.Show("gold")
    pump(0.3)
    check(ns.db.general.lastPage == "gold", "the open page is remembered")
    ns.db.general.alpha = 70
    ns.ApplyScale()
    check(ZodUIFrame.alpha == 0.7, "the window opacity is applied")
    ns.db.general.alpha = 100
    ns.ApplyScale()
    ns.Show("home")
    pump(0.3)
    local card
    for _, c in ipairs(ns.pages.home.cards) do
        if c:IsShown() and c.key == "Gold" then card = c end
    end
    check(card ~= nil, "Home has a Gold card")
    card.scripts.OnMouseUp(card, "RightButton")
    pump(0.3)
    check(ns.db.general.hiddenCards.Gold and printed("the Gold card is hidden"), "right-click hides a card")
    local still = false
    for _, c in ipairs(ns.pages.home.cards) do
        if c:IsShown() and c.key == "Gold" then still = true end
    end
    check(not still and has("Right-click a card to hide it"), "and it is gone from Home")
    SlashCmdList["ZODUI"]("settings")
    pump(0.3)
    ns.Show("settings", "general")
    pump(0.3)
    local show
    for _, f in ipairs(W.frames) do
        if f.kind == "Button" and f:IsVisible() and rawget(f, "label") and plain(f.label.text or "") == "Show all" then show = f end
    end
    check(show ~= nil, "Settings > General has Show all")
    click(show)
    check(next(ns.db.general.hiddenCards) == nil and printed("every card is back on Home"), "Show all brings the cards back")

    reset()
    ns.Alert("First thing")
    ns.Alert("Second thing")
    slash("notices")
    check(printed("the last notices:") and printed("Second thing"), "/zod notices lists them")
    check(ns.noticeLog[1][2] == "Second thing", "newest first")
    ns.db.general.toasts, ns.db.general.toastSound, ns.db.general.toastHold = true, true, 2
    reset()
    ns.Alert("Loud one")
    check(called("PlaySound", 12889) == 1, "a notice can play a sound")
    local toast = ns.toasts[1]
    check(toast and toast.left == 3, "and stays as long as you chose: " .. tostring(toast and toast.left))
    pump(3.2)
    check(not toast:IsShown(), "then goes")
    ns.db.general.toasts, ns.db.general.toastSound, ns.db.general.toastHold = false, false, 5

    reset()
    slash("version")
    check(printed("v" .. ns.version .. ", ") and printed("modules on."), "/zod version")
    slash("rem")
    check(ns.pages.remind.frame:IsVisible(), "/zod rem opens Reminders")
    slash("goa")
    check(ns.pages.goals.frame:IsVisible(), "/zod goa opens Goals")
    reset()
    slash("zz")
    check(printed("unknown command 'zz'"), "two letters are not enough")

    local mini = ZodUIMinimapButton
    check(mini ~= nil, "the minimap button exists")
    mini.scripts.OnClick(mini, "MiddleButton")
    pump(0.3)
    check(ns.pages.notes.frame:IsVisible(), "middle-click opens To do")
    mini.scripts.OnEnter(mini)
    local tip = table.concat(GameTooltip.lines, "\n")
    check(tip:find("Middle-click: To do", 1, true), "the tooltip says what the clicks do")
    check(tip:find("To do: %d+ open"), "and how many to-dos are open: " .. tip)
end


---------------------------------------------------------------------------
say("--- session: gold, best rate, kills, rested, level times")
do
    reset()
    fire("CHAT_MSG_COMBAT_XP_GAIN", "Kobold Worker dies, you gain 45 experience.")
    fire("CHAT_MSG_COMBAT_XP_GAIN", "You gain 300 experience.")
    ns.Show("session")
    pump(0.3)
    check(has("Kills that gave XP"), "kills are listed")
    check(ns.chardb.session.kills == 1, "a kill counts, quest XP does not: " .. tostring(ns.chardb.session.kills))
    check(has("Gold per hour") and has("Rested XP left") and has("Best XP per hour"), "gold per hour, rested XP and the best rate")
    check(has("Last level took") and has("A level on average"), "level times")
    ns.chardb.session.start = time() - 1000
    ns.chardb.session.xp = 5000
    pump(11)
    check(ns.chardb.bestRate and ns.chardb.bestRate > 0, "a long enough session sets the best XP per hour")
    local best = ns.chardb.bestRate
    ns.chardb.session.xp = 1
    pump(11)
    check(ns.chardb.bestRate == best, "a slower one does not lower it")
end

---------------------------------------------------------------------------
say("--- history: totals and a chart of play time")
do
    ns.Show("history")
    pump(0.3)
    check(has("Last 7 days") and has("Last 30 days"), "the totals are listed")
    check(has("XP a day, the last two weeks"), "the chart shows XP")
    click("Show play time")
    check(has("Play time a day, the last two weeks") and has("longest day"), "and can show play time")
    click("Show XP")
    check(has("XP a day, the last two weeks"), "and back")
end

---------------------------------------------------------------------------
say("--- gold: the week, the best day, round sums")
do
    reset()
    ns.modules.gold.db.milestone = 100000
    W.money = 195000
    fire("PLAYER_MONEY")
    reset()
    W.money = 205000
    fire("PLAYER_MONEY")
    check(printed("You passed 20g."), "passing a round sum is said")
    W.money = 209000
    fire("PLAYER_MONEY")
    check(#W.alerts == 1, "once")
    ns.modules.gold.db.milestone = 0
    W.money = 310000
    fire("PLAYER_MONEY")
    check(#W.alerts == 1, "Never turns it off")
    ns.modules.gold.db.milestone = 1000000
    ns.Show("gold")
    pump(0.3)
    check(has("Last 7 days") and has("Best day"), "the week and the best day")
end


---------------------------------------------------------------------------
say("--- loot: notices, best finds, worth an hour")
do
    reset()
    local function loot(msg) fire("CHAT_MSG_LOOT", msg, "", "", "", "Zod") end
    ns.modules.loot.db.alert = 3 -- the settings pages were clicked through earlier
    loot("You receive loot: |cff0070dd|Hitem:900::::::::24:::::|h[Shiny Blade]|h|r.")
    check(W.alerts[#W.alerts] == "Loot: |cff0070ddShiny Blade|r", "a blue drop is a notice: " .. tostring(W.alerts[#W.alerts]))
    local n = #W.alerts
    loot("You receive loot: |cff1eff00|Hitem:901::::::::24:::::|h[Green Cap]|h|r.")
    check(#W.alerts == n, "a green one is not, by default")
    check(ns.chardb.finds[1].name == "Green Cap" and ns.chardb.finds[2].name == "Shiny Blade", "both are kept as finds, newest first")
    loot("You receive loot: |cffffffff|Hitem:902::::::::24:::::|h[Linen Cloth]|h|r.")
    check(ns.chardb.finds[1].name == "Green Cap", "a white item is not a find")
    ns.Show("loot")
    pump(0.3)
    click("Best finds")
    check(ns.pages.loot.finds:IsShown() and has("Shiny Blade") and has("Hillsbrad Foothills"), "Best finds lists them with where")
    click("This session")
    check(ns.pages.loot.list:IsShown(), "and back")
    ns.chardb.loot.start = time() - 3600
    ns.chardb.loot.items[903] = { name = "Gem", count = 1, quality = 1, price = 5000 }
    ns.Refresh()
    pump(0.3)
    check(has("an hour"), "what the loot is worth an hour")
end

---------------------------------------------------------------------------
say("--- dungeons: the hourly limit, the fastest, removing a run")
do
    reset()
    ns.db.entries = {}
    local kept = ns.chardb.runs.list
    ns.chardb.runs.list = {
        { name = "Deadmines", kind = "party", at = W.clock - 9000, took = 2400, xp = 3000, gold = 0, deaths = 0, level = 20 },
        { name = "Deadmines", kind = "party", at = W.clock - 5000, took = 1800, xp = 5000, gold = 0, deaths = 1, level = 20 },
    }
    for i = 1, 5 do
        W.instance = { "Deadmines", "party" }
        fire("ZONE_CHANGED_NEW_AREA")
        W.instance = nil
        fire("ZONE_CHANGED_NEW_AREA")
        pump(400, 5)
    end
    check(printed("Deadmines: your fastest run here took 30m (2 runs)."), "walking in says the fastest run")
    check(printed("4th dungeon this hour. The game lets you enter 5."), "the 4th is a warning")
    check(printed("5th dungeon this hour: that is the limit."), "the 5th says it is the limit")
    check(#ns.db.entries == 5, "five entries this hour")
    ns.Show("runs")
    pump(0.3)
    check(has("Entered this hour: 5 of 5."), "the page says how many this hour")
    pump(3700, 50)
    ns.Refresh()
    pump(0.3)
    check(not has("Entered this hour"), "an hour later they are gone")
    local page = ns.pages.runs
    check(not button("Remove this run"), "no remove button before a run is chosen")
    page.list.onClick(ns.chardb.runs.list[1])
    pump(0.3)
    click("Remove this run")
    check(#ns.chardb.runs.list == 1 and ns.chardb.runs.list[1].took == 1800, "a run can be removed")
    ns.chardb.runs.list = kept
    ns.db.entries = {}
end

---------------------------------------------------------------------------
say("--- items: this character only, most first")
do
    ns.db.chars["Bank-Forever"] = { name = "Bank", class = "MAGE", items = { [500] = { bags = 50 }, [100] = { bags = 1 } } }
    ns.db.itemNames[500] = { name = "Aaa Stone", q = 1 }
    ns.Show("items")
    pump(0.3)
    check(has("Aaa Stone"), "other characters' items are listed")
    click("This character")
    check(not has("Aaa Stone") and button("All characters"), "This character leaves them out")
    click("All characters")
    click("Most first")
    local first = ns.pages.items.list
    check(button("A to Z") and has("Aaa Stone"), "Most first sorts by count")
    click("A to Z")
    ns.db.chars["Bank-Forever"] = nil
end


---------------------------------------------------------------------------
say("--- characters: full rested, played, sorting")
do
    reset()
    ns.db.chars["Alt-Forever"] = { name = "Alt", realm = "Forever", class = "MAGE", level = 31, money = 500000, xp = 1000, zone = "Orgrimmar" }
    local alt = ns.db.chars["Alt-Forever"]
    alt.seen, alt.resting, alt.rested, alt.xpMax, alt.fullSaid = time() - 3600, true, 3000, 30000, nil
    check(ns.modules.alts:FullIn(alt) > 0, "a little rested is not full")
    alt.seen = time() - 30 * 86400
    check(ns.modules.alts:FullIn(alt) == 0, "a month in an inn is full")
    ns.modules.alts:OnEnable()
    pump(9)
    check(printed("Alt is fully rested."), "a fully rested character is said at login")
    reset()
    ns.modules.alts:OnEnable()
    pump(9)
    check(not printed("fully rested"), "once")
    fire("TIME_PLAYED_MSG", 90000, 3600)
    ns.Show("alts")
    pump(0.3)
    check(has("full in") or has("full"), "the page says when they are full")
    check(has("Played on all characters: 1d 1h") and has("1 of 2"), "time played is added up: " .. tostring(ns.pages.alts.total:GetText()))
    click("Sort: Level")
    check(button("Sort: Gold"), "the sort button goes through the orders")
    click("Sort: Gold")
    click("Sort: Name")
    click("Sort: Last played")
    check(button("Sort: Level"), "and back to level")
end

---------------------------------------------------------------------------
say("--- to-do: down, edit, weekly, counts")
do
    for i = #ns.chardb.notes, 1, -1 do ns.chardb.notes[i] = nil end
    ns.modules.notes:Add("One", "char")
    ns.modules.notes:Add("Two", "char")
    ns.modules.notes:Add("Weekly raid", "char", false, true)
    ns.Show("notes")
    pump(0.3)
    click("This character")
    local page = ns.pages.notes
    check(page.tabs[1].count:GetText() == "3", "the tab shows how many are open: " .. tostring(page.tabs[1].count:GetText()))
    check(page.rows[1].down:IsShown() and not page.rows[3].down:IsShown(), "the last line has no down button")
    click(page.rows[1].down)
    check(ns.chardb.notes[1].text == "Two" and ns.chardb.notes[2].text == "One", "a line moves down")
    click(page.rows[1].edit)
    check(page.input.edit:GetText() == "Two" and button("Save"), "Edit puts the line in the box")
    page.input.edit:SetText("Two, changed")
    click("Save")
    check(ns.chardb.notes[1].text == "Two, changed" and #ns.chardb.notes == 3 and button("Add"), "Save changes it in place")
    check(has("weekly"), "a weekly one says so")
    click(page.rows[3].check)
    check(ns.chardb.notes[3].done and ns.chardb.notes[3].week, "a weekly one remembers its week")
    click("Remove the ticked ones")
    check(#ns.chardb.notes == 3, "a weekly one is kept")
    ns.chardb.notes[3].week = "1999-01"
    ns.Refresh()
    pump(0.3)
    check(not ns.chardb.notes[3].done, "on a new week it is open again")
    page.input.edit:SetText("New weekly")
    click("Add weekly")
    check(ns.chardb.notes[4].weekly == true, "Add weekly")
end

---------------------------------------------------------------------------
say("--- reminders: list, clear, at the next login")
do
    reset()
    ns.db.reminders = {}
    slash("remind login check the mail")
    check(printed("Next time you log in: check the mail"), "a login reminder is set")
    slash("remind list")
    check(printed("next login  check the mail"), "/zod remind list")
    pump(30)
    check(not ns.db.reminders[1].due, "it waits for the next login")
    ns.Show("remind")
    pump(0.3)
    check(has("next login"), "the page says so")
    ns.modules.remind:OnEnable()
    pump(7)
    check(ns.db.reminders[1].due and W.alerts[#W.alerts] == "Reminder: check the mail", "it rings after the next login")
    reset()
    slash("remind clear")
    check(printed("removed 1 reminder that rang.") and #ns.db.reminders == 0, "/zod remind clear")
    slash("remind clear")
    check(printed("no reminder has rung."), "and says when there is nothing")
end


---------------------------------------------------------------------------
say("--- goals: a level, chat lines, from chat, reached ones, pace")
do
    reset()
    local goals = ns.modules.goals
    slash("goals level " .. (W.level + 1))
    check(printed("Reaching level " .. (W.level + 1) .. "."), "/zod goals level N")
    ns.Show("goals")
    pump(0.3)
    check(has("Level") and has(W.level .. " / " .. (W.level + 1)), "the level goal is listed")
    fire("PLAYER_LEVEL_UP", W.level + 1)
    check(W.alerts[#W.alerts] == "Goal reached: level " .. (W.level + 1) .. ".", "reaching the level is said")
    W.bags[2] = { [1] = { id = 950, quality = 1, count = 2, price = 5 } }
    W.bagSize[2] = 12
    ns.db.itemNames[950] = { name = "Copper Ore", q = 1 }
    reset()
    slash("goals 10 copper ore")
    check(printed("Added: 10 Copper Ore."), "/zod goals 10 copper ore")
    W.bags[2][1].count = 5
    fire("BAG_UPDATE_DELAYED")
    check(printed("Copper Ore: 5 / 10"), "a line in chat when you get more")
    reset()
    fire("BAG_UPDATE_DELAYED")
    check(not printed("Copper Ore:"), "nothing when the count did not change")
    for _, g in ipairs(ns.chardb.goals) do
        if g.id == 950 then g.fromAt = time() - 600 end
    end
    ns.Refresh()
    pump(0.3)
    check(has("~"), "the pace says how long is left")
    W.level = W.level + 1
    W.bags[2][1].count = 10
    fire("BAG_UPDATE_DELAYED")
    click("Remove the reached ones")
    local left = false
    for _, g in ipairs(ns.chardb.goals) do
        if g.id == 950 then left = true end
    end
    check(not left and not ns.chardb.levelGoal, "the reached goals are removed")
    W.level = W.level - 1
    W.bags[2], W.bagSize[2] = nil, 0
end

---------------------------------------------------------------------------
say("--- vendor: always sell, never sell")
do
    reset()
    W.bags[0][9] = { id = 777, quality = 1, count = 1, price = 100 }
    W.bags[0][10] = { id = 778, quality = 0, count = 1, price = 50 }
    ns.db.itemNames[777] = { name = "Old Boots", q = 1 }
    ns.db.itemNames[778] = { name = "Lucky Pebble", q = 0 }
    slash("vendor sell old boots")
    slash("vendor keep 778")
    check(printed("Old Boots is sold at every merchant") and printed("Lucky Pebble is never sold."), "both are taken")
    slash("vendor list")
    check(printed("always sold: Old Boots. Never sold: Lucky Pebble."), "/zod vendor list")
    W.merchant = true
    fire("MERCHANT_SHOW")
    pump(1)
    check(called("UseContainerItem", 0) >= 1 and W.bags[0][9] == nil and W.bags[0][10] ~= nil, "the white one is sold, the kept grey one is not")
    fire("MERCHANT_CLOSED")
    W.merchant = false
    slash("vendor forget 778")
    check(printed("Lucky Pebble is back to the usual rule"), "forget")
    W.bags[0][10] = nil
    slash("vendor moon")
    check(printed("use /zod vendor sell <item>"), "a wrong word explains")
end

---------------------------------------------------------------------------
say("--- quests: done notice")
do
    reset()
    W.questLog = { { title = "Kobold Trouble", questID = 11, complete = false }, { title = "Already", questID = 12, complete = true } }
    fire("QUEST_LOG_UPDATE")
    check(#W.alerts == 0, "what was done at login is not news")
    W.questLog[1].complete = true
    fire("QUEST_LOG_UPDATE")
    check(W.alerts[#W.alerts] == "Quest done: Kobold Trouble. Hand it in.", "a quest that is now done is said")
    fire("QUEST_LOG_UPDATE")
    check(#W.alerts == 1, "once")
    -- With Undead Route, where it goes in.
    local savedRoute = UndeadRoute
    UndeadRoute = { TurnIn = function(id)
        if id == 13 then return { zone = "Silverpine Forest", hub = "The Sepulcher", x = 43.3, y = 41 } end
        if id == 14 then return { zone = "Durotar", hub = "Razor Hill", npc = "Gar'Thok", x = 51.9, y = 43.5 } end
        if id == 15 then return { zone = "Durotar", x = 60, y = 20.25 } end
        if id == 16 then error("route broke") end
    end }
    for i, title in ipairs({ "The Moonsilver Blade", "Taming the Beast", "Far Out", "Broken" }) do
        W.questLog[#W.questLog + 1] = { title = title, questID = 12 + i, complete = false }
    end
    fire("QUEST_LOG_UPDATE")
    for i = 3, 6 do W.questLog[i].complete = true end
    fire("QUEST_LOG_UPDATE")
    local said = table.concat(W.alerts, "|")
    check(said:find("Quest done: The Moonsilver Blade. Hand it in at The Sepulcher, Silverpine Forest (43.3, 41.0).", 1, true) ~= nil,
        "the hand-in hub and zone are named")
    check(said:find("Quest done: Taming the Beast. Hand it in to Gar'Thok at Razor Hill, Durotar (51.9, 43.5).", 1, true) ~= nil,
        "the hand-in NPC is named when the route knows it")
    check(said:find("Quest done: Far Out. Hand it in: Durotar (60.0, 20.", 1, true) ~= nil, "a spot with no hub gives the zone")
    check(said:find("Quest done: Broken. Hand it in.", 1, true) ~= nil, "a route that errors leaves the plain notice")
    -- As a notice, a click pins the hand-in through the route.
    local pinned
    UndeadRoute.PinTurnIn = function(id, title) pinned = id .. " " .. title end
    ns.db.general.toasts = true
    for _, t in ipairs(ns.toasts) do t.scripts.OnMouseUp(t) end
    local turnIn = UndeadRoute.TurnIn
    UndeadRoute.TurnIn = function(id) return turnIn(id == 17 and 13 or id) end
    W.questLog[#W.questLog + 1] = { title = "Pin Me", questID = 17, complete = true }
    fire("QUEST_LOG_UPDATE")
    local card = ns.toasts[1]
    check(card and card.hint and card.text:GetText():find("Pin Me", 1, true), "a quest-done notice with a hand-in carries a click")
    if card then card.scripts.OnMouseUp(card) end
    check(pinned == "17 Pin Me" and #ns.toasts == 0, "clicking it pins the hand-in and puts the notice away")
    ns.Toast("Plain one")
    check(ns.toasts[1].click == nil and ns.toasts[1].hint == nil, "a reused card does not keep the last notice's click")
    ns.toasts[1].scripts.OnMouseUp(ns.toasts[1])
    ns.db.general.toasts = false
    UndeadRoute = savedRoute
    W.questLog = nil
end


---------------------------------------------------------------------------
say("--- info bar: to-dos, session gold, reminder, size, right-click")
do
    slash("databar on")
    local db = ns.modules.databar.db
    db.session, db.remind, db.todo = true, true, true
    ns.db.reminders = { { text = "Tea", at = time() + 600 } }
    local bar = ZodUIDataBar
    pump(1.2)
    local text = plain(bar.text:GetText())
    check(text:find("To do %d+"), "open to-dos: " .. text)
    check(text:find("Remind 10m", 1, true) or text:find("Remind 9m", 1, true), "the next reminder: " .. text)
    W.money = W.money + 50000
    fire("PLAYER_MONEY")
    pump(1.2)
    text = plain(bar.text:GetText())
    check(text:find("Session [%+%-]"), "gold this session: " .. text)
    local _, size = bar.text:GetFont()
    db.big = true
    ns.modules.databar:OnOption("big")
    local _, bigger = bar.text:GetFont()
    check(bigger == size + 2 and bar:GetHeight() == 26, "larger text")
    db.big = false
    ns.modules.databar:OnOption("big")
    bar.scripts.OnClick(bar, "RightButton")
    pump(0.3)
    check(ns.pages.settings.frame:IsVisible() and has("Larger text"), "right-click opens the info bar's settings")
    bar.scripts.OnEnter(bar)
    local tip = table.concat(GameTooltip.lines, "\n")
    check(tip:find("Right-click: the info bar's settings", 1, true) and tip:find("Next reminder: Tea", 1, true), "the tooltip: " .. tip)
    bar.scripts.OnLeave(bar)
    db.session, db.remind = false, false
    ns.db.reminders = {}
    slash("databar off")
end

---------------------------------------------------------------------------
say("--- tooltips: item level, goal, target")
do
    local itemTip, unitTip = W.tooltipCalls[0], W.tooltipCalls[2]
    W.bags[2] = { [1] = { id = 960, quality = 2, count = 3, price = 100, ilvl = 24, equip = "INVTYPE_HEAD" } }
    W.bagSize[2] = 12
    table.insert(ns.chardb.goals, { id = 960, name = "Cap", want = 10 })
    GameTooltip.lines = {}
    itemTip(GameTooltip, { id = 960 })
    local tip = table.concat(GameTooltip.lines, "\n")
    check(tip:find("Item level", 1, true), "gear shows its item level: " .. tip)
    check(tip:find("Goal", 1, true), "and the goal for it")
    W.bags[2][1].equip = ""
    GameTooltip.lines = {}
    itemTip(GameTooltip, { id = 960 })
    check(not table.concat(GameTooltip.lines, "\n"):find("Item level", 1, true), "not for other items")
    table.remove(ns.chardb.goals)
    W.bags[2], W.bagSize[2] = nil, 0
    check(unitTip ~= nil, "a unit tooltip hook is installed")
    W.units = { mouseovertarget = "Bob" }
    GameTooltip.lines = {}
    unitTip(GameTooltip, {})
    check(plain(GameTooltip.lines[1] or "") == "Targeting = Bob", "whom it targets: " .. tostring(GameTooltip.lines[1]))
    W.units = { mouseovertarget = "Zod", player = "Zod" }
    GameTooltip.lines = {}
    unitTip(GameTooltip, {})
    check(plain(GameTooltip.lines[1] or "") == "Targeting = You", "it can be you")
    W.units = nil
    GameTooltip.lines = {}
    unitTip(GameTooltip, {})
    check(#GameTooltip.lines == 0, "no target, no line")
end


---------------------------------------------------------------------------
say("--- chat: watched words, whispers, mentions, away")
do
    reset()
    slash("chat watch SFK")
    check(printed("watching for sfk in say, yell and the channels."), "a word to watch")
    slash("chat watch sfk")
    check(printed("already watching for sfk."), "once")
    local filter = W.chatFilters["CHAT_MSG_CHANNEL"]
    local r = { filter(nil, "CHAT_MSG_CHANNEL", "LFM SFK need heals", "Bob") }
    check(r[2] == "LFM |cffffd100SFK|r need heals", "the word shows in gold: " .. tostring(r[2]))
    fire("CHAT_MSG_CHANNEL", "LFM SFK need heals", "Bob")
    fire("CHAT_MSG_CHANNEL", "sfk anyone?", "Tim")
    check(called("PlaySound", 8959) == 1, "one sound, not one per message")
    r = { filter(nil, "CHAT_MSG_GUILD", "sfk tonight", "Bob") }
    check(#r == 1, "guild chat is not watched")
    slash("chat unwatch sfk")
    check(printed("no longer watching for sfk.") and #ns.modules.chat.db.words == 0, "unwatch")

    W.afk = true
    fire("PLAYER_FLAGS_CHANGED")
    fire("CHAT_MSG_WHISPER", "you there?", "Mia-Forever")
    fire("CHAT_MSG_WHISPER", "hello?", "Mia-Forever")
    W.afk = false
    fire("PLAYER_FLAGS_CHANGED")
    check(printed("2 whispers came while you were away."), "back from away says how many whispers came")
    reset()
    slash("chat whispers")
    check(printed("Mia: hello?") and printed("Mia: you there?"), "/zod chat whispers")
    fire("CHAT_MSG_GUILD", "ask zod about it", "Bob-Forever")
    fire("CHAT_MSG_GUILD", "I am Zod", "Zod-Forever")
    slash("chat mentions")
    check(printed("Bob (guild): ask zod about it") and not printed("I am Zod"), "/zod chat mentions, not your own lines")
    slash("chat nonsense")
    check(printed("use /zod chat watch <word>"), "a wrong word explains")
end

---------------------------------------------------------------------------
say("--- alerts: profession cap, hearthstone, mail")
do
    reset()
    W.profs = { { "Mining", nil, 150, 150 }, { "Engineering", nil, 140, 225 } }
    fire("SKILL_LINES_CHANGED")
    check(W.alerts[#W.alerts] == "Mining is at 150 of 150: your trainer can teach the next level.", "a profession at its cap is said")
    fire("SKILL_LINES_CHANGED")
    check(#W.alerts == 1, "once")
    W.profs = nil
    reset()
    W.bags[2] = { [1] = { id = 6948, quality = 1, count = 1 } }
    W.bagSize[2] = 12
    W.cooldowns[6948] = { W.uptime, 30 }
    pump(6)
    check(#W.alerts == 0, "nothing while it cools down")
    pump(30)
    check(W.alerts[#W.alerts] == "Your hearthstone is ready.", "said when it is ready")
    pump(10)
    check(#W.alerts == 1, "once")
    -- Every cast (a fight, skinning, mining) puts the hearthstone on the 1.5 s
    -- global cooldown; that is not a use and must never be announced.
    for _ = 1, 40 do
        W.cooldowns[6948] = { W.uptime, 1.5 }
        pump(0.5)
        W.cooldowns[6948] = { 0, 0 }
        pump(2.5)
    end
    check(#W.alerts == 1, "the global cooldown from casting is not a use (" .. #W.alerts .. " alerts)")
    W.secret = 1234
    W.cooldowns[6948] = { W.secret, W.secret }
    pump(6)
    W.cooldowns[6948] = { 0, 0 }
    pump(6)
    W.secret = nil
    check(#W.alerts == 1, "a secret cooldown in combat is not read as a use")
    W.cooldowns[6948] = { W.uptime, 30 }
    pump(6)
    W.secret = 1234
    W.cooldowns[6948] = { W.secret, W.secret }
    pump(6)
    W.secret = nil
    W.cooldowns[6948] = { W.uptime - 12, 30 }
    pump(30)
    check(#W.alerts == 2 and W.alerts[2] == "Your hearthstone is ready.", "a real use is still said once, across a secret stretch")
    W.bags[2], W.bagSize[2], W.cooldowns[6948] = nil, 0, nil
    reset()
    W.mail = true
    ns.modules.alerts:OnEnable()
    pump(9)
    check(W.alerts[#W.alerts] == "You have mail.", "mail at login")
    W.mail = false
end


---------------------------------------------------------------------------
say("--- reputation: watch, next standing, only those gained")
do
    reset()
    local org = W.factions[3]
    ns.modules.rep.db.watch = true
    org.currentStanding = org.currentStanding + 200
    fire("UPDATE_FACTION")
    check(called("SetWatchedFactionByID", org.factionID) == 1, "the faction gained with is watched")
    org.currentStanding = org.currentStanding + 50
    fire("UPDATE_FACTION")
    check(called("SetWatchedFactionByID") == 1, "not again for the same one")
    ns.modules.rep.db.watch = false
    pump(400, 10)
    ns.Show("rep")
    pump(0.3)
    check(has("Next standing"), "the column is there")
    click("Only those gained")
    check(has(org.name) and not has("Horde") and button("Every faction"), "only the factions gained with, no group headings")
    click("Every faction")
    check(has("Horde") and has("Booty Bay"), "and every faction again")
end

---------------------------------------------------------------------------
say("--- invites and duels: guilds, charters, battlegrounds")
do
    reset()
    slash("social on")
    fire("GUILD_INVITE_REQUEST", "Bob", "Knights")
    fire("PETITION_SHOW")
    check(called("DeclineGuild") == 0 and called("ClosePetition") == 0, "left to you unless ticked")
    local db = ns.modules.social.db
    db.guild, db.charter, db.release = true, true, true
    fire("GUILD_INVITE_REQUEST", "Bob", "Knights")
    check(called("DeclineGuild") == 1 and printed("declined a guild invite to Knights from Bob."), "a guild invite is declined")
    fire("PETITION_SHOW")
    check(called("ClosePetition") == 1, "a charter is closed")
    fire("PLAYER_DEAD")
    pump(1)
    check(called("RepopMe") == 0, "outside a battleground you are not released")
    W.instance = { "Warsong Gulch", "pvp" }
    fire("PLAYER_DEAD")
    pump(1)
    check(called("RepopMe") == 1, "in a battleground you are")
    W.selfRes = { { name = "Soulstone", optionType = 1, id = 5232, canUse = true, isLimited = true, priority = 1 } }
    fire("PLAYER_DEAD")
    pump(1)
    check(called("RepopMe") == 1, "not with a soulstone you can use")
    W.selfRes[1].canUse = false
    fire("PLAYER_DEAD")
    pump(1)
    check(called("RepopMe") == 2, "but with one you cannot use, you are")
    W.secret = "hidden"
    W.selfRes[1].canUse = "hidden"
    fire("PLAYER_DEAD")
    pump(1)
    check(called("RepopMe") == 2, "a hidden canUse counts as usable")
    W.secret = nil
    W.selfRes = nil
    W.instance = nil
    db.guild, db.charter, db.release = false, false, false
    slash("social off")
end

---------------------------------------------------------------------------
say("--- game settings: target of target")
do
    slash("tweaks on")
    local db = ns.modules.tweaks.db
    check(db.stamps == nil and db.numbers == nil and db.camera == nil and db.luaErrors == nil, "time stamps, bar numbers, camera and errors are EllesmereUI's")
    db.tot = true
    ns.modules.tweaks:OnOption("tot")
    check(W.cvars.showTargetOfTarget == "1" and W.cvars.showTimestamps == "none", "target of target is set, time stamps are not touched")
    slash("tweaks off")
    check(W.cvars.showTargetOfTarget == "0", "and put back")
    db.tot = false
end


---------------------------------------------------------------------------
say("--- away timer")
do
    reset()
    W.afk = true
    fire("PLAYER_FLAGS_CHANGED")
    pump(70)
    local box = ns.modules.afk.box
    check(box and box:IsShown() and box.time:GetText():find("^1:%d%d$"), "the box counts the time away: " .. tostring(box and box.time:GetText()))
    W.afk = false
    fire("PLAYER_FLAGS_CHANGED")
    pump(1.2)
    check(printed("back after 1m away.") and not box:IsShown(), "back again: a line in chat, the box goes")
end

---------------------------------------------------------------------------
say("--- mail: take all")
do
    reset()
    W.inbox = { { money = 500 }, { cod = 100, items = 1 }, { items = 2 } }
    fire("MAIL_SHOW")
    local b = ns.modules.mail.button
    check(b and b:IsShown(), "the mailbox has a Take all button")
    click(b)
    pump(2)
    check(called("TakeInboxMoney", 1) == 1 and called("AutoLootMailItem", 3) == 1, "gold and items are taken")
    check(called("AutoLootMailItem", 2) == 0, "a letter that asks for payment is left alone")
    check(printed("took 2 items and 5s from the mail."), "and it says what it took")
    fire("MAIL_CLOSED")
    W.inbox = nil
end

---------------------------------------------------------------------------
say("--- kills, deaths, zones, quests done")
do
    reset()
    local before = ns.chardb.kills and ns.chardb.kills.by["Kobold Worker"] and ns.chardb.kills.by["Kobold Worker"].n or 0
    fire("CHAT_MSG_COMBAT_XP_GAIN", "Kobold Worker dies, you gain 45 experience.")
    fire("CHAT_MSG_COMBAT_XP_GAIN", "Kobold Worker dies, you gain 45 experience. (+45 exp Rested bonus)")
    fire("CHAT_MSG_COMBAT_XP_GAIN", "You gain 300 experience.")
    check(ns.chardb.kills.by["Kobold Worker"].n == before + 2, "kills are counted by name")
    ns.Show("kills")
    pump(0.3)
    check(has("Kobold Worker") and has("today"), "the Kills page lists them")

    fire("PLAYER_DEAD")
    check(ns.chardb.deaths[1].zone == "Hillsbrad Foothills" and ns.chardb.deaths[1].sub == "Tarren Mill", "a death is kept with where")
    ns.Show("deaths")
    pump(0.3)
    check(has("Tarren Mill, Hillsbrad Foothills") and has("most in Hillsbrad Foothills"), "the Deaths page lists it")

    W.zone = "Silverpine Forest"
    fire("ZONE_CHANGED_NEW_AREA")
    check(printed("first time in Silverpine Forest."), "a first visit is said")
    pump(21)
    check(ns.chardb.zones["Silverpine Forest"].time >= 20, "time in a zone is counted")
    W.zone = "Hillsbrad Foothills"
    fire("ZONE_CHANGED_NEW_AREA")
    reset()
    W.zone = "Silverpine Forest"
    fire("ZONE_CHANGED_NEW_AREA")
    check(not printed("first time"), "a second visit is not")
    W.zone = "Hillsbrad Foothills"
    fire("ZONE_CHANGED_NEW_AREA")
    ns.Show("zones")
    pump(0.3)
    check(has("Silverpine Forest") and has("Time there"), "the Zones page lists them")

    W.questTitles = { [501] = "The Last Stand" }
    fire("QUEST_TURNED_IN", 501, 1200, 300)
    check(ns.chardb.questsDone[1].name == "The Last Stand" and ns.chardb.questsDone[1].xp == 1200, "a quest handed in is kept")
    ns.Show("questlog")
    pump(0.3)
    check(has("The Last Stand") and has("1,200"), "the Quests done page lists it")
    ns.Show("home")
    pump(0.3)
    check(has("Quests done") and has("Deaths") and has("Kills"), "they have Home cards")
    searchFor("last stand")
    check(has("Quest") and has("The Last Stand"), "the search finds a quest done")
    searchFor("")
end

---------------------------------------------------------------------------
say("--- break reminder, skill-ups")
do
    reset()
    slash("breaks on")
    ns.modules.breaks.db.every = 30
    ns.modules.breaks:OnOption("every")
    pump(1810, 10)
    check(W.alerts[#W.alerts] and W.alerts[#W.alerts]:find("without a break", 1, true), "a break reminder after half an hour")
    slash("breaks off")
    fire("CHAT_MSG_SKILL", "Your skill in Mining has increased to 151.")
    fire("CHAT_MSG_SKILL", "Your skill in Mining has increased to 152.")
    ns.Show("home")
    pump(0.3)
    check(has("Skill-ups today") and has("+2"), "skill-ups on Home")
end

---------------------------------------------------------------------------
say("--- screenshots, pet care")
do
    reset()
    slash("shots on")
    fire("CHAT_MSG_LOOT", "You receive loot: |cffa335ee|Hitem:990::::::::24:::::|h[Big Axe]|h|r.", "", "", "", "Zod")
    pump(1.2)
    check(called("Screenshot") == 1 and printed("screenshot: Big Axe."), "purple loot")
    fire("CHAT_MSG_LOOT", "Bob receives loot: |cffa335ee|Hitem:990::::::::24:::::|h[Big Axe]|h|r.", "", "", "", "Bob")
    pump(1.2)
    check(called("Screenshot") == 1, "not someone else's")
    W.zone = "Arathi Highlands"
    fire("ZONE_CHANGED_NEW_AREA")
    pump(1.2)
    check(called("Screenshot") == 2, "a first visit")
    W.zone = "Hillsbrad Foothills"
    fire("ZONE_CHANGED_NEW_AREA")
    pump(1.2)
    check(called("Screenshot") == 2, "not a zone seen before")
    local bay = W.factions[4]
    bay.reaction = bay.reaction + 1
    fire("UPDATE_FACTION")
    pump(1.2)
    check(called("Screenshot") == 3, "a new standing")
    slash("shots off")

end

---------------------------------------------------------------------------
say("--- pet coach")
do
    local savedBags = W.bags
    W.bags = { [0] = {} }
    local last = function() return W.alerts[#W.alerts] or "" end
    local feed = _G.ZodUIPetFeed
    check(feed and feed.template == "SecureActionButtonTemplate", "a secure feed button exists")
    check(_G["BINDING_NAME_CLICK ZodUIPetFeed:LeftButton"] ~= nil, "and has a key binding name")

    -- not a hunter: nothing
    reset()
    W.units, W.happiness = { pet = "Imp" }, 1
    pump(4)
    check(#W.alerts == 0, "other classes are left alone")
    W.units, W.happiness = nil, nil

    -- an unhappy hunter pet, with food in the bags
    reset()
    W.hunter, W.units = true, { pet = "Wolf" }
    W.happiness, W.loyaltyRate, W.loyalty, W.tp, W.petXP = 1, 1, "Loyal", { 100, 100 }, { 450, 1000 }
    W.bags[1] = { [1] = { id = 900, quality = 1, count = 4, ilvl = 25 }, [2] = { id = 901, quality = 1, count = 10, ilvl = 15 },
        [3] = { id = 902, quality = 1, count = 3, ilvl = 30 } }
    W.petFood = { [900] = true, [901] = true }
    W.diet = { "Meat", "Fish" }
    W.bindings = { ["CLICK ZodUIPetFeed:LeftButton"] = "F" }
    pump(4)
    check(last():find("Your pet is unhappy and does 75% damage", 1, true), "an unhappy pet is said: " .. last())
    check(last():find("Feed it: Item 900 (4)", 1, true), "with the best food it eats (highest level, not item 902 it does not eat)")
    check(last():find("Press F", 1, true), "and the feed key")
    check(feed:GetAttribute("type") == "macro" and feed:GetAttribute("macrotext") == "/cast Feed Pet\n/use item:900",
        "the feed key is set to that food: " .. tostring(feed:GetAttribute("macrotext")))
    local n = #W.alerts
    local checks = W.foodChecks
    pump(4)
    check(#W.alerts == n, "said once")
    check(W.foodChecks == checks, "what the pet eats is remembered, not asked again")

    -- fed: the best stack is gone, the key moves on to the next food
    W.happiness = 3
    W.bags[1][1] = nil
    fire("BAG_UPDATE_DELAYED")
    check(feed:GetAttribute("macrotext") == "/cast Feed Pet\n/use item:901", "the key moves to the next food")

    -- happy to content: off by default, on when ticked
    W.happiness = 2
    pump(4)
    check(#W.alerts == n, "content is not said by default")
    W.happiness = 3
    pump(4)
    ns.modules.pet.db.content = true
    W.happiness = 2
    pump(4)
    check(last():find("no longer happy", 1, true) and last():find("Item 901", 1, true), "content is said when ticked: " .. last())
    ns.modules.pet.db.content = false
    W.happiness = 3
    pump(4)

    -- loyalty
    n = #W.alerts
    W.loyaltyRate = -1
    pump(4)
    check(last():find("losing loyalty", 1, true), "losing loyalty is said: " .. last())
    pump(4)
    check(#W.alerts == n + 1, "once")
    W.loyaltyRate = 1
    pump(4)
    W.loyaltyRate = -2
    pump(4)
    check(#W.alerts == n + 2, "and again after it recovered")
    W.loyaltyRate = 1
    pump(4)

    -- training points: the first reading is the baseline, a rise is said
    n = #W.alerts
    W.tp = { 115, 100 }
    fire("PET_UI_UPDATE")
    pump(4)
    check(last() == "Your pet has 15 training points to spend (Beast Training).", "new training points are said: " .. last())
    W.tp = { 115, 110 }
    pump(4)
    check(#W.alerts == n + 1, "spending them says nothing")

    -- food running low
    n = #W.alerts
    W.bags[1][2].count = 3
    fire("BAG_UPDATE_DELAYED")
    check(last() == "Your pet's food is running low: 3 left (Item 901).", "low food is said: " .. last())
    fire("BAG_UPDATE_DELAYED")
    check(#W.alerts == n + 1, "once")

    -- Home
    ns.Show("home")
    pump(0.3)
    check(has("Wolf") and has("Happy") and has("125% damage"), "Home shows the mood and its damage")
    check(has("Loyal") and has("3  Item 901") and has("5 free of 115") and has("XP 45%"), "and loyalty, food, points and XP:\n" .. screen())

    -- in combat the key is not touched; it catches up afterwards
    W.combat = true
    W.bags[1][4] = { id = 903, quality = 1, count = 20, ilvl = 28 }
    W.petFood[903] = true
    fire("BAG_UPDATE_DELAYED")
    check(feed:GetAttribute("macrotext") == "/cast Feed Pet\n/use item:901", "not changed in combat")
    W.combat = false
    fire("PLAYER_REGEN_ENABLED")
    check(feed:GetAttribute("macrotext") == "/cast Feed Pet\n/use item:903", "set after combat")

    -- no food it eats
    reset()
    W.bags[1] = nil
    W.happiness = 1
    pump(4)
    check(last():find("You carry no food it eats (Meat, Fish)", 1, true), "no food: says its diet: " .. last())
    check(#W.alerts == 1, "in one notice, not a second one about food")
    check(feed:GetAttribute("macrotext") == nil, "and the key does nothing")

    -- a hidden (secret) mood says nothing and breaks nothing
    reset()
    W.happiness = 3
    pump(4)
    W.secret = "s"
    W.happiness = "s"
    pump(4)
    check(#W.alerts == 0, "a secret mood is ignored")
    W.secret, W.happiness = nil, 3

    -- a new pet starts fresh; death is still said
    reset()
    W.units = { pet = "Cat" }
    W.petDead = true
    pump(4)
    check(last() == "Your pet has died.", "a dead pet is said")
    W.petDead = false
    W.hunter, W.units, W.happiness, W.loyaltyRate, W.loyalty, W.tp, W.petXP, W.petFood, W.diet, W.bindings =
        nil, nil, nil, nil, nil, nil, nil, nil, nil, nil
    W.bags = savedBags
end


---------------------------------------------------------------------------
say("--- report, played, reload, safe mode")
do
    reset()
    slash("report")
    check(printed("Today: ") and printed(" played, ") and printed(" XP"), "/zod report")
    W.party.Lok = true
    slash("report party")
    local last = W.calls[#W.calls]
    check(last[1] == "SendChatMessage" and last[3] == "PARTY" and not last[2]:find("|c", 1, true), "said to the group, without colour codes: " .. tostring(last[2]))
    W.party.Lok = nil
    slash("report guild")
    check(printed("you are not in a guild."), "not in a guild: said to you instead")
    ns.char.playedTotal = 7200
    slash("played")
    check(printed("played on all characters: "), "/zod played")
    slash("reload")
    check(called("ReloadUI") == 1, "/zod reload")
    reset()
    local before = 0
    for _, m in ipairs(ns.order) do
        if m.enabled then before = before + 1 end
    end
    slash("safe")
    local now = 0
    for _, m in ipairs(ns.order) do
        if m.enabled then now = now + 1 end
    end
    check(now == 0 and printed("safe mode: " .. before .. " modules are off."), "safe mode switches everything off")
    slash("safe")
    check(printed("safe mode is already on."), "once")
    slash("safe off")
    now = 0
    for _, m in ipairs(ns.order) do
        if m.enabled then now = now + 1 end
    end
    check(now == before and printed(before .. " modules are on again."), "and brings them back")
end

---------------------------------------------------------------------------
say("--- today, the streak, defaults, commands, Shift-click")
do
    local days = ns.chardb.history.days
    days[ns.Today(1)] = days[ns.Today(1)] or { xp = 0, quests = 0, deaths = 0, levels = 0, gold = 0, played = 0 }
    days[ns.Today(1)].played = 3600
    days[ns.Today(2)] = { xp = 0, quests = 0, deaths = 0, levels = 0, gold = 0, played = 3600 }
    days[ns.Today()].played = math.max(days[ns.Today()].played, 120)
    check(ns.modules.history:Streak() >= 3, "three days in a row: " .. ns.modules.history:Streak())
    ns.Show("home")
    pump(0.3)
    check(has("Today") and has("Days in a row"), "Home has a Today card")
    ns.Show("history")
    pump(0.3)
    check(has("days in a row"), "the History page says the streak")

    reset()
    ns.modules.alerts.db.bagsAt = 7
    ns.Show("settings", "alerts")
    pump(0.3)
    click("Defaults")
    check(ns.modules.alerts.db.bagsAt == 2 and printed("Alerts: the settings are back as they came."), "Defaults puts the settings back")

    slash("commands")
    check(ns.pages.commands.frame:IsVisible() and has("Today's report") and has("Safe mode: every module off") and has("Who knows a recipe"), "/zod commands shows them as buttons")
    searchFor("snooze")
    check(has("Command"), "the search finds commands")
    searchFor("")
    slash("setup")
    click("All commands")
    check(ns.pages.commands.frame:IsVisible(), "the Modules page has a button to them")

    reset()
    local mini = ZodUIMinimapButton
    local was = ns.modules.databar.enabled
    W.shift = true
    mini.scripts.OnClick(mini, "LeftButton")
    W.shift = false
    check(ns.modules.databar.enabled ~= was and printed("the info bar is "), "Shift-click switches the info bar")
    mini.scripts.OnClick(mini, "LeftButton")
    W.shift = true
    mini.scripts.OnClick(mini, "LeftButton")
    W.shift = false
    check(ns.modules.databar.enabled == was, "and back")
end


---------------------------------------------------------------------------
say("--- next up on Home")
do
    reset()
    ns.db.reminders = { { text = "Feed the cat", at = time() - 10, due = true } }
    W.durability = { [1] = { 10, 100 } }
    ns.Show("home")
    pump(0.3)
    check(has("Next up") and has("Reminder: Feed the cat") and has("Repair: your gear is at 10%"), "Next up gathers what wants doing")
    local card
    for _, c in ipairs(ns.pages.home.cards) do
        if c:IsShown() and c.key == "Next up" then card = c end
    end
    check(card and card.left[1].text == "Reminder: Feed the cat", "the most pressing first")
    check(card == ns.pages.home.cards[1] or card.key == "Next up", "it is a card of its own")
    click(card.button)
    check(ns.pages.remind.frame:IsVisible(), "Go opens the page of the first one")
    ns.db.general.nextUp = false
    ns.Show("home")
    pump(0.3)
    check(not has("Next up"), "the setting leaves it out")
    ns.db.general.nextUp = true
    ns.db.reminders = {}
    W.durability = { [1] = { 80, 100 }, [5] = { 60, 100 } }
end

---------------------------------------------------------------------------
say("--- gold: where it came from")
do
    reset()
    fire("MERCHANT_SHOW")
    W.money = W.money + 1500
    fire("PLAYER_MONEY")
    fire("MERCHANT_CLOSED")
    pump(1.5)
    fire("LOOT_OPENED")
    W.money = W.money + 300
    fire("PLAYER_MONEY")
    fire("LOOT_CLOSED")
    pump(1.5)
    W.money = W.money + 2000
    fire("PLAYER_MONEY")
    fire("QUEST_TURNED_IN", 77, 500, 2000)
    fire("TAXIMAP_OPENED")
    W.money = W.money - 400
    fire("PLAYER_MONEY")
    fire("TAXIMAP_CLOSED")
    pump(1.5)
    local from = ns.db.gold.days[ns.Today()].from
    check(from.merchant >= 1500 and from.loot >= 300 and from.taxi == -400, "merchant, loot and flight money is sorted")
    check(from.quests >= 2000, "quest money that came first is moved to quests: " .. tostring(from.quests))
    ns.Show("gold")
    pump(0.3)
    click("Where it came from")
    check(ns.pages.gold.from:IsShown() and has("Flights") and has("Looted") and has("Quests"), "the Gold page lists them")
    click("Day by day")
    check(ns.pages.gold.days:IsShown(), "and back")
end

---------------------------------------------------------------------------
say("--- characters: cooldowns, hearth, lockouts")
do
    reset()
    W.recipes, W.recipeIDs = { [17187] = { name = "Transmute: Arcanite", cd = 3600 }, [100] = { name = "Linen Bandage" } }, { 17187, 100 }
    fire("TRADE_SKILL_SHOW")
    pump(1)
    local cds = ns.char.cooldowns
    check(cds[17187] and cds[17187].ready > time() and not cds[100], "a recipe with a cooldown is kept, the others not")
    ns.Show("alts")
    pump(0.3)
    check(has("Cooldowns:") and has("Transmute: Arcanite"), "the Characters page lists the cooldowns")
    searchFor("arcanite")
    check(has("Cooldown"), "the search finds a cooldown")
    searchFor("")
    pump(3700, 50)
    ns.Show("home")
    pump(0.3)
    check(has("Transmute: Arcanite is ready on Zod"), "a ready cooldown is in Next up")
    ns.modules.alts:OnEnable()
    pump(9)
    check(printed("ready: Transmute: Arcanite on Zod."), "and said at login")
    reset()
    ns.modules.alts:OnEnable()
    pump(9)
    check(not printed("ready: "), "once")
    W.recipes, W.recipeIDs = nil, nil

    W.saved = { { "Molten Core", 3 * 86400 } }
    fire("UPDATE_INSTANCE_INFO")
    ns.Show("alts")
    pump(0.3)
    ns.pages.alts.list.onClick(ns.charKey)
    pump(0.3)
    check(has("Hearth: Tarren Mill.") and has("Saved to: Molten Core (") and (has("(3d") or has("(2d 23h")), "a character's hearth and lockouts: " .. tostring(ns.pages.alts.hint:GetText()))
    ns.pages.alts.list.selected = nil
    W.saved = nil
end

---------------------------------------------------------------------------
say("--- session: XP sources, the top level")
do
    fire("CHAT_MSG_COMBAT_XP_GAIN", "Gnoll dies, you gain 120 experience.")
    check((ns.chardb.session.killXP or 0) >= 120, "XP from kills is added up")
    ns.Show("session")
    pump(0.3)
    check(has("XP from kills") and has("Other XP"), "the page splits the XP")
    check(has("Level 60 in"), "and says when level 60 comes")
    local left = ns.modules.session:XPToTop()
    check(left and left > 1000000, "XP to level 60 from level " .. W.level .. ": " .. tostring(left))
end


---------------------------------------------------------------------------
say("--- plugins: the ZodUI API")
do
    reset()
    local api = ZodUI.api
    check(api and api.level == 1 and api.version == ns.version and api.Theme == ns.T, "ZodUI.api is there with its level and the theme")
    ns.Show("settings")
    pump(0.3)
    slash("setup")
    local ran
    api.Ready(function(a) ran = a end)
    check(ran == api, "Ready runs at once after login")
    local P = api.NewModule("testplug", { title = "Test plugin", desc = "A plugin made by the test.", plugin = "TestAddon",
        defaults = { enabled = true, shout = true }, options = { { type = "check", key = "shout", label = "Shout loudly" } } })
    check(P.db and P.db.shout == true and P.enabled and ns.db.modules.testplug == P.db, "a module added after login gets saved settings and starts")
    function P:Card() return { title = "Plugin card", lines = { { "Hello from the plugin", "" } } } end
    function P:Hints(add) add("The plugin says hi", 95) end
    function P:Find(part, add, has)
        if has("zebra") then add("Plugin", "Zebra stripes", "", "testplug") end
    end
    api.AddPage({ key = "testplug", title = "Plugin page", module = "testplug",
        Build = function(page, f)
            page.text = api.Theme.Text(f, "GameFontNormal")
            page.text:SetPoint("TOPLEFT", 0, 0)
        end,
        Refresh = function(page) page.text:SetText("The plugin page body") end })
    ns.Show("home")
    pump(0.3)
    check(has("Plugin card") and has("The plugin says hi"), "its Home card and its Next up line")
    check(has("PLUGINS") and has("Plugin page"), "its page is listed under Plugins")
    ns.Show("testplug")
    pump(0.3)
    check(has("The plugin page body"), "and opens")
    ns.Show("settings", "testplug")
    pump(0.3)
    check(has("Shout loudly") and has("Test plugin"), "Settings, built before it came, lists it")
    slash("setup")
    check(has("From TestAddon."), "the Modules page says where it comes from")
    searchFor("zebra")
    check(has("Zebra stripes"), "the search asks it")
    searchFor("")
    local said
    api.AddCommand("plug", function(rest) said = rest end, "A test command")
    slash("plug Hello There")
    check(said == "Hello There", "a plugin command gets what was typed: " .. tostring(said))
    slash("commands")
    check(has("A test command"), "and gets a row on the Commands page")
    for _, b in ipairs(ns.pages.commands.buttons) do
        if b.cmd == "plug" then click(b) end
    end
    check(said == "", "whose button runs it: " .. tostring(said))
    slash("testplug off")
    check(not P.enabled and printed("Test plugin is off."), "it switches off like the others")
    reset()
    api.Print("hello", "ZodRoute")
    check(printed("ZodRoute: hello"), "a plugin prints under its own name")
    local ok = pcall(api.NewModule, "gold", { title = "Clash" })
    check(not ok, "a key that is taken is refused")
end

---------------------------------------------------------------------------
say("--- loot rolls")
do
    local function inside(f, root)
        while f do if f == root then return true end f = f.parent end
        return false
    end
    local function texts(root, raw)
        local parts = {}
        for _, f in ipairs(W.frames) do
            if f.kind == "FontString" and f.text and f.text ~= "" and f:IsVisible() and (not root or inside(f, root)) then
                parts[#parts + 1] = raw and f.text or plain(f.text)
            end
        end
        return table.concat(parts, "\n")
    end
    local function button(label, root)
        for _, f in ipairs(W.frames) do
            if f.kind == "Button" and f.scripts.OnClick and f:IsVisible() and rawget(f, "label") and plain(f.label.text or "") == label
                and (not root or inside(f, root)) then return f end
        end
    end
    local function called(name)
        local list = {}
        for _, c in ipairs(W.calls) do if c[1] == name then list[#list + 1] = c end end
        return list
    end
    local function link(id, name, hex) return "|cff" .. (hex or "0070dd") .. "|Hitem:" .. id .. "::::::::|h[" .. name .. "]|h|r" end
    local function loot(msg) fire("CHAT_MSG_LOOT", msg, "", "", "", "Zod") end
    local savedUnits, savedParty
    reset()
    ns.db.rolls = {}
    local M = ns.modules.rolls
    check(M and M.enabled, "Loot rolls starts on")
    slash("rolls off")
    check(UIParent.events.START_LOOT_ROLL, "switched off, the game opens its own roll boxes")
    slash("rolls on")
    check(not UIParent.events.START_LOOT_ROLL, "switched on, UIParent no longer opens the game's roll boxes")

    savedUnits, savedParty = W.units, W.party
    W.units = { party1 = "Thrallson", party2 = "Mireth-Forever" }
    W.classes = { party1 = "SHAMAN", party2 = "MAGE" }
    W.party = { Thrallson = true, Mireth = true }

    say("--- a roll opens")
    local staff = link(1800, "Staff of Westfall")
    W.rolls[7] = { link = staff, icon = "Interface\\Icons\\INV_Staff_02", name = "Staff of Westfall", quality = 3,
        canNeed = false, canGreed = true, canDE = false, whyNeed = 2, left = 60000 }
    GroupLootFrame1:Show()
    fire("START_LOOT_ROLL", 7, 60000)
    pump(0.3)
    local stack = M.stack
    check(stack and stack:IsShown(), "the stack shows")
    check(not GroupLootFrame1:IsShown(), "the game's own box is hidden")
    check(not GroupLootContainer:IsShown() and #GroupLootContainer.rollFrames == 0,
        "and the game's roll container is empty and hidden: no invisible box in the middle of the screen")
    local trace = ns.db.rollTrace and ns.db.rollTrace[1]
    check(trace and trace.why == "start 7" and #trace.ours > 0 and #trace.game > 0,
        "in a group a roll leaves a trace of our frames and the game's")
    say("   trace: " .. (trace and (trace.ours[1] .. " / " .. trace.game[1]) or "none"))
    pump(1.1)
    check(ns.db.rollTrace[1].why == "1s after start 7", "and another a second later")
    check(texts(stack):find("Staff of Westfall", 1, true), "the card names the item")
    check(texts(stack):find("Need, Greed or Pass", 1, true), "the card asks for a pick")
    local need = button("Need", stack)
    check(need and need.alpha == 0.35 and need.tip == "You cannot need this item.", "Need is dimmed and says why")
    need.scripts.OnClick(need)
    check(#called("RollOnLoot") == 0, "a dimmed Need does not roll")
    check(not button("Disenchant", stack), "no Disenchant button when the item cannot be disenchanted")
    button("Greed", stack).scripts.OnClick(button("Greed", stack))
    local r = called("RollOnLoot")
    check(#r == 1 and r[1][2] == 7 and r[1][3] == 2, "Greed rolls Greed on roll 7")
    pump(0.2)
    check(texts(stack):find("You: Greed", 1, true) and not button("Pass", stack), "the card says your pick and the buttons go")

    say("--- the party's picks and rolls come in chat")
    loot("You have selected Greed for: " .. staff)
    loot("Thrallson has selected Need for: " .. staff)
    loot("Mireth-Forever passed on: " .. staff)
    loot("|HlootHistory:12|h[Loot]|h: Greed Roll - 64 for " .. staff .. " by Zod")
    loot("Need Roll - 88 for " .. staff .. " by Thrallson")
    pump(0.2)
    local raw = texts(stack, true)
    check(raw:find("|c" .. ns.ClassHex("SHAMAN") .. "Thrallson|r", 1, true), "Thrallson is in shaman blue")
    check(raw:find("|c" .. ns.ClassHex("MAGE") .. "Mireth|r", 1, true), "Mireth, realm dropped, is in mage colour")
    check(texts(stack):find("64", 1, true) and texts(stack):find("88", 1, true), "the rolls show, the wrapped line too")
    loot("Thrallson won: " .. staff)
    pump(0.2)
    check(texts(stack):find("Won by Thrallson", 1, true), "the winner shows: " .. texts(stack):gsub("\n", " / "))
    say("   card: " .. texts(stack):gsub("\n", " / "))
    pump(6)
    check(not stack:IsShown(), "the card leaves after the hold")
    local kept = ns.db.rolls and ns.db.rolls[1]
    check(kept and kept.winner == "Thrallson" and kept.wclass == "SHAMAN" and kept.mine == 2 and kept.roll == 88 and #kept.players == 3,
        "the roll is kept with winner, class, your pick and everyone")

    say("--- you win; everyone passes; more rolls than fit")
    local ring = link(1900, "Ring of Zora", "a335ee")
    W.rolls[8] = { link = ring, name = "Ring of Zora", quality = 4, canNeed = true, canGreed = true, canDE = true, left = 60000 }
    fire("START_LOOT_ROLL", 8, 60000)
    pump(0.2)
    check(button("Disenchant", stack), "Disenchant shows when the item can be disenchanted")
    loot("You won: " .. ring)
    pump(0.2)
    check(texts(stack):find("You won!", 1, true) and #called("PlaySound") > 0, "you won, with a sound")
    local cloth = link(4306, "Silk Cloth", "ffffff")
    W.rolls[9] = { link = cloth, name = "Silk Cloth", quality = 1, canNeed = true, canGreed = true, left = 60000 }
    fire("START_LOOT_ROLL", 9, 60000)
    loot("Everyone passed on: " .. cloth)
    pump(0.2)
    check(texts(stack):find("Everyone passed.", 1, true), "everyone passed shows")
    pump(6)
    for id = 20, 24 do
        W.rolls[id] = { link = link(2000 + id, "Thing " .. id), name = "Thing " .. id, quality = 2, canNeed = true, canGreed = true, left = 30000 }
        fire("START_LOOT_ROLL", id, 30000)
    end
    pump(0.2)
    check(texts(stack):find("+ 1 more roll", 1, true), "a fifth roll waits under + 1 more")
    say("   five rolls: " .. select(2, texts(stack):gsub("Need, Greed or Pass", "")) .. " asking, " .. (texts(stack):match("%+ %d more roll") or ""))
    check(texts(stack):find("%ds") ~= nil, "a timer in seconds shows")
    do
        local draws, realDraw = 0, M.Draw
        M.Draw = function(...) draws = draws + 1 return realDraw(...) end
        local before = texts(stack):match("(%d+)s")
        pump(2)
        local after = texts(stack):match("(%d+)s")
        M.Draw = realDraw
        check(draws == 0 and before ~= after, "the timer counts down " .. tostring(before) .. " > " .. tostring(after)
            .. " without redrawing the cards (" .. draws .. " draws)")
    end
    -- They never get a result: they leave 15 seconds after time ran out, kept as no result.
    local before = #ns.db.rolls
    pump(46)
    check(not stack:IsShown() and #ns.db.rolls == before + 5 and ns.db.rolls[1].winner == "", "rolls with no result leave and are kept")

    say("--- a roll with no time, or cancelled with no result, still leaves")
    W.rolls[40] = { link = link(4000, "Timeless"), name = "Timeless", quality = 2, canNeed = true, canGreed = true, left = 0 }
    fire("START_LOOT_ROLL", 40, 0)
    pump(0.2)
    check(texts(stack):find("Timeless", 1, true), "a roll with no time shows")
    pump(60)
    check(texts(stack):find("Timeless", 1, true), "and waits the usual minute")
    pump(16)
    check(not stack:IsShown(), "then leaves instead of staying until a reload")
    W.rolls[41] = { link = link(4100, "Cancelled"), name = "Cancelled", quality = 2, canNeed = true, canGreed = true, left = 60000 }
    fire("START_LOOT_ROLL", 41, 60000)
    pump(0.2)
    fire("CANCEL_LOOT_ROLL", 41)
    pump(20)
    loot("Thrallson won: " .. link(4100, "Cancelled"))
    pump(0.2)
    check(texts(stack):find("Won by Thrallson", 1, true) and not texts(stack):find("not in this roll", 1, true),
        "a result 20 seconds after the cancel still lands on the same card")
    pump(6)
    check(not stack:IsShown(), "and the card leaves after the hold")
    W.rolls[42] = { link = link(4200, "Stuck"), name = "Stuck", quality = 2, canNeed = true, canGreed = true, left = 0 }
    fire("START_LOOT_ROLL", 42, 0)
    pump(0.2)
    local history = ns.db.rolls
    slash("rolls clear")
    pump(0.2)
    check(not stack:IsShown(), "/zod rolls clear takes the cards off the screen")
    ns.db.rolls = history -- the checks below read the rolls kept so far

    say("--- someone else's roll you could not join")
    local boots = link(3000, "Boots")
    loot("Thrallson has selected Greed for: " .. boots)
    pump(0.2)
    check(texts(stack):find("You are not in this roll.", 1, true), "a watched roll has no buttons")
    loot("Thrallson won: " .. boots)
    pump(6)

    say("--- the Rolls page and the Home card")
    slash("rolls")
    local window = ZodUIFrame
    check(window and window:IsShown() and texts(window):find("Staff of Westfall", 1, true), "the Rolls page lists the staff")
    check(texts(window):find("Who rolled on", 1, true), "the page shows who rolled on the selected one")
    local card = M:Card()
    check(card and card.title == "Loot rolls", "a Home card")

    say("--- /zod rolls test")
    local n = #ns.db.rolls
    slash("rolls test")
    pump(1)
    check(texts(stack):find("Staff of Westfall", 1, true) and texts(stack):find("Silk Cloth", 1, true), "two sample rolls show")
    local cardsShown, cardsClickThrough, iconsClickable = 0, true, true
    for _, f in ipairs(W.frames) do
        if f:GetParent() == stack and f.iconFrame and f:IsShown() then
            cardsShown = cardsShown + 1
            if f:IsMouseEnabled() then cardsClickThrough = false end
            if not f.iconFrame:IsMouseEnabled() then iconsClickable = false end
        end
    end
    check(cardsShown == 2 and cardsClickThrough and not stack:IsMouseEnabled(), "the stack and the cards let clicks through")
    check(iconsClickable, "only the item box (and the buttons) take the mouse")
    local b = button("Need", stack)
    b.scripts.OnClick(b)
    pump(10)
    check(#ns.db.rolls == n, "sample rolls are not kept")
    check(#called("RollOnLoot") == 1, "sample rolls never roll for real")
    local leaving
    for _ = 1, 100 do
        pump(0.1)
        for _, f in ipairs(W.frames) do
            if f:GetParent() == stack and f.iconFrame and f:IsShown() and f:GetAlpha() == 0 then leaving = f end
        end
        if leaving then break end
    end
    check(leaving and not leaving.iconFrame:IsMouseEnabled(), "a card fading out takes no clicks")
    pump(10)
    check(not stack:IsShown(), "the samples leave")

    say("--- switched off, the game gets its boxes back; /reload brings open rolls back")
    slash("rolls off")
    check(UIParent.events.START_LOOT_ROLL and not stack:IsShown(), "the game's boxes are back")
    check(GroupLootContainer.events.START_LOOT_ROLL, "the game's roll container gets its event back too")
    slash("rolls on")
    check(not UIParent.events.START_LOOT_ROLL and not GroupLootContainer.events.START_LOOT_ROLL, "and both are taken again")
    -- Should the container still get a roll (another addon gives it the event back), it is emptied all the same.
    GroupLootContainer:RegisterEvent("START_LOOT_ROLL")
    for id = 50, 52 do
        W.rolls[id] = { link = staff, name = "Staff of Westfall", quality = 3, canNeed = true, canGreed = true, left = 30000 }
        fire("START_LOOT_ROLL", id, 30000)
        pump(0.2)
    end
    check(#GroupLootContainer.rollFrames == 0 and not GroupLootContainer:IsShown() and not GroupLootFrame1:IsShown(),
        "three rolls later the container holds no slots and is not on screen")
    GroupLootContainer:UnregisterEvent("START_LOOT_ROLL")
    for id = 50, 52 do W.rolls[id] = nil fire("CANCEL_LOOT_ROLL", id) end
    pump(10)
    W.rolls = { [30] = { link = staff, name = "Staff of Westfall", quality = 3, canNeed = true, canGreed = true, left = 20000 } }
    fire("PLAYER_ENTERING_WORLD")
    pump(0.2)
    check(stack:IsShown() and texts(stack):find("Staff of Westfall", 1, true), "an open roll comes back after a reload")

    W.units, W.party, W.classes, W.rolls = savedUnits, savedParty, nil, {}
    slash("rolls off")
    slash("rolls on")
    reset()
end

say("--- fades")
do
    local want = (ns.db.general.alpha or 100) / 100
    ns.Close()
    pump(0.2)
    local n = W.anims or 0
    ns.Show("home")
    check(ZodUIFrame:IsShown() and (W.anims or 0) > n and ZodUIFrame:GetAlpha() == want, "the window fades in to its set alpha")
    ns.Toggle()
    check(not ZodUIFrame:IsShown() and ZodUIFrame:GetAlpha() == want, "toggled, it fades out, hides, and keeps its alpha for next time")
    ns.Toggle()
    check(ZodUIFrame:IsShown(), "and toggles back")
    ns.Close()
    for i = #ns.toasts, 1, -1 do table.remove(ns.toasts, i) end
    ns.Toast("first")
    ns.Toast("second")
    local a, b = ns.toasts[1], ns.toasts[2]
    check(#ns.toasts == 2 and a ~= b and a:IsShown() and a:GetAlpha() == 1, "two notices fade in")
    pump(20)
    check(#ns.toasts == 0 and not a:IsShown() and not b:IsShown(), "they fade out and leave")
    ns.Toast("third")
    ns.Toast("fourth")
    check(ns.toasts[1] ~= ns.toasts[2], "a notice is never handed out twice from the pool")
    pump(20)
end

say("--- Codex Forever, when it is installed")
do
    local opened = {}
    local function rowFor(data)
        for _, f in ipairs(W.frames) do
            if f.kind == "Button" and rawget(f, "data") == data and f:IsVisible() then return f end
        end
    end
    check(not ns.Codex.Has() and ns.Codex.Hint() == "", "without Codex Forever nothing links to it")
    local res = ns.Find("westfall")
    check(not (res[#res] and res[#res].codex), "and the search has no Codex line")
    check(ns.Codex.Open("x") == false, "opening it does nothing")

    W.loaded.CodexForever = true
    SlashCmdList.CODEXFOREVER = function(msg) opened[#opened + 1] = msg end
    check(ns.Codex.Has(), "installed, ZodUI sees it")
    ns.Search("westfall")
    local page = ns.pages.find
    local last = page.results[#page.results]
    check(last and last.codex == "westfall", "the search ends with a Codex Forever line")
    page.list.onClick(last)
    check(opened[#opened] == "westfall", "which opens Codex searching for it")

    local staff = "|cff0070dd|Hitem:1800::::::::|h[Staff of Westfall]|h|r"
    local savedRolls = ns.db.rolls
    ns.db.rolls = { { at = time(), link = staff, name = "Staff of Westfall", q = 3, winner = "", wclass = "", roll = 0,
        choice = -1, mine = -1, passed = false, players = {} } }
    ns.Show("rolls")
    local row = rowFor(ns.db.rolls[1])
    local n = #opened
    W.alt = false
    if row then row.scripts.OnClick(row) end
    check(row and #opened == n, "a plain click on a roll does not open Codex")
    W.alt = true
    if row then row.scripts.OnClick(row) end
    check(opened[#opened] == "Staff of Westfall", "Alt-click opens the item in Codex, by name: " .. tostring(opened[#opened]))
    W.alt = false

    SlashCmdList.CODEXFOREVER = function() error("boom") end
    check(ns.Codex.Open("x") == false, "a Codex call that fails is caught")
    W.loaded.CodexForever, SlashCmdList.CODEXFOREVER, ns.db.rolls = nil, nil, savedRolls
    slash("errors clear")
    ns.Close()
end

say("--- more key bindings")
ZodUI_Unlock()
check(ns.IsUnlocked(), "the unlock binding unlocks")
ZodUI_Unlock()
check(not ns.IsUnlocked(), "and locks")
ZodUI_Open("notes")
check(has("Remove the ticked ones"), "the to-do binding opens the list")
ZodUI_Find()
check(ZodUIFrame.find.edit.focus == true and type(BINDING_NAME_ZODUI_FIND) == "string", "the search binding puts the cursor in the box")

---------------------------------------------------------------------------
say("--- commands")
reset()
slash("help")
check(printed("/zod <module> on|off"), "/zod help")
slash("modules")
check(printed("vendor") and printed("Info bar"), "/zod modules")
slash("errors")
check(printed("no errors since login"), "/zod errors")
slash("nonsense")
check(printed("unknown command 'nonsense'"), "an unknown command says so")
slash("databar maybe")
check(printed("use /zod databar on or /zod databar off"), "a bad module argument says so")
local store = ns.db.window
store.point, store.x = "TOPLEFT", 5
slash("reset")
check(ns.db.window == store and store.point == nil and ZodUIFrame:GetPoint(1) == "CENTER", "/zod reset re-centres the window")
ZodUI_OnCompartmentClick()
check(not ZodUIFrame:IsShown(), "the addon compartment entry toggles the window")
ZodUI_Toggle()
check(ZodUIFrame:IsShown() and type(BINDING_NAME_ZODUI_TOGGLE) == "string", "the key binding toggles the window")

---------------------------------------------------------------------------
say("--- stable keeper")
do
    local P = ns.modules.pet
    local itemTip = W.tooltipCalls[Enum.TooltipDataType.Item]
    local savedBags, savedUnits = W.bags, W.units
    ns.chardb.pets, ns.chardb.stableAt = nil, nil
    reset()
    slash("pet")
    check(printed("no pets known yet"), "/zod pet with no pets says how they are learnt")

    -- the pet out now: its diet and the foods it eats are remembered
    W.hunter, W.units = true, { pet = "Wolfie" }
    W.happiness, W.diet = 3, { "Meat", "Fish" }
    W.bags = { [0] = { [1] = { id = 910, quality = 1, count = 20, ilvl = 25 }, [2] = { id = 911, quality = 1, count = 5, ilvl = 10 } } }
    W.petFood = { [910] = true, [911] = false }
    fire("BAG_UPDATE_DELAYED")
    local wolf = ns.chardb.pets and ns.chardb.pets.Wolfie
    check(wolf and wolf.out and wolf.eats[910] == true and wolf.eats[911] == false and wolf.diet[1] == "Meat",
        "the pet out now is remembered with its diet and what it eats")

    -- at the stable master
    W.stable = {
        active = { { slotID = 1, name = "Wolfie", level = 26, familyName = "Wolf", loyaltyName = "Loyal" } },
        stabled = { { slotID = 6, name = "Boar", level = 22, familyName = "Boar", loyaltyName = "Faithful" },
            { slotID = 7, name = "Old Cat", level = 12, familyName = "Cat", loyaltyName = "Disloyal" } },
        diets = { [1] = { "Meat", "Fish" }, [6] = { "Meat", "Fungus", "Bread" }, [7] = { "Meat", "Fish" } },
    }
    fire("PET_STABLE_SHOW")
    local pets = ns.chardb.pets
    check(pets.Boar and pets.Boar.level == 22 and pets.Boar.family == "Boar" and pets.Boar.diet[3] == "Bread" and pets.Boar.stabled,
        "the stable's pets are kept, with level, family and diet")
    check(pets.Wolfie.level == 26 and pets.Wolfie.eats[910] == true, "and the pet out keeps what it ate")
    pets.Boar.eats[910] = true
    GameTooltip.lines = {}
    itemTip(GameTooltip, { id = 910 })
    check(plain(table.concat(GameTooltip.lines, "\n")):find("Pet food = Wolfie, Boar", 1, true), "a food's tooltip says which pets eat it: "
        .. table.concat(GameTooltip.lines, " | "))
    GameTooltip.lines = {}
    itemTip(GameTooltip, { id = 911 })
    check(not table.concat(GameTooltip.lines, "\n"):find("Pet food", 1, true), "not for one none of them eats")

    reset()
    slash("pet")
    check(printed("Wolfie  level 26, Wolf, Loyal, eats Meat, Fish  out now") and printed("Boar  level 22, Boar, Faithful, eats Meat, Fungus, Bread  in the stable"),
        "/zod pet lists them, the one out first")
    check(found(ns.Find("boar"), "Pet", "Boar"), "search finds a pet")

    -- a released pet goes; an empty list (not loaded) keeps them
    table.remove(W.stable.stabled, 2)
    fire("PET_STABLE_UPDATE")
    check(pets["Old Cat"] == nil and pets.Boar, "a pet no longer in the stable is forgotten")
    W.stable = { active = {}, stabled = {} }
    fire("PET_STABLE_UPDATE")
    check(pets.Boar and pets.Wolfie, "an empty stable list is not taken as no pets")

    -- not a hunter: no tooltip line, and the stable is not read
    W.hunter = false
    GameTooltip.lines = {}
    itemTip(GameTooltip, { id = 910 })
    check(not table.concat(GameTooltip.lines, "\n"):find("Pet food", 1, true), "other classes get no pet food line")

    W.hunter, W.units, W.bags, W.stable, W.petFood, W.diet, W.happiness = nil, savedUnits, savedBags, nil, nil, nil, nil
    ns.chardb.pets, ns.chardb.stableAt = nil, nil
end

---------------------------------------------------------------------------
say("--- guild crafters")
do
    local C = ns.modules.crafters
    local savedGuild = W.guild
    ns.db.crafters = nil
    reset()
    W.guild = false
    slash("crafters 3915 tailoring")
    check(printed("you are not in a guild."), "outside a guild it says so")
    W.guild = true

    local r, s = C.Parse("|cffffd000|Htrade:Player-1-0001:3915:197|h[Tailoring: Brown Linen Shirt]|h|r")
    check(r == 3915 and s == 197, "a trade link gives the recipe and the profession")
    r, s = C.Parse("|cffffffff|Henchant:7418|h[Enchant Bracer - Minor Health]|h|r enchanting")
    check(r == 7418 and s == 333, "an enchant link and a profession name")
    r, s = C.Parse("18445 Tailoring")
    check(r == 18445 and s == 197, "a spell id and a profession, any capitals")
    r, s = C.Parse("18445")
    check(r == nil and s:find("Which profession", 1, true), "without the profession it asks which")
    r, s = C.Parse("18445 juggling")
    check(r == nil and s:find("not a profession", 1, true), "an unknown profession says so")
    r, s = C.Parse("")
    check(r == nil and s:find("Shift-click", 1, true), "nothing typed says how")

    W.recipeMembers = { [18445] = { { "Bob-Forever", false }, { "Ann-Forever", true }, { "Cid-Forever", true } } }
    reset()
    slash("crafters 18445 tailoring")
    check(called("QueryGuildMembersForRecipe", 197) == 1 and printed("asking your guild who knows"), "it asks the server")
    fire("GUILD_RECIPE_KNOWN_BY_MEMBERS")
    local line = ""
    for _, l in ipairs(W.printed) do if l:find("in your guild know it", 1, true) then line = l end end
    check(plain(line):find("3 in your guild know it, 2 online", 1, true), "the answer counts them: " .. plain(line))
    check(line:find("|Hplayer:Ann-Forever|h[Ann]|h", 1, true) and line:find("Ann", 1, true) < line:find("Bob", 1, true)
        and line:find("Cid", 1, true) < line:find("Bob", 1, true), "online first, as names you click to whisper")
    check(ns.db.crafters[18445] and #ns.db.crafters[18445].members == 3, "the answer is kept")
    reset()
    fire("GUILD_RECIPE_KNOWN_BY_MEMBERS")
    check(#W.printed == 0, "an answer nobody asked for is ignored")

    reset()
    slash("crafters 3915 tailoring")
    pump(6)
    check(printed("no answer about") and printed("/zod crafters test"), "no answer in time points to the test")
    fire("GUILD_RECIPE_KNOWN_BY_MEMBERS")
    check(not printed("in your guild know it"), "and a late answer is not taken")

    reset()
    slash("crafters test")
    check(printed("guild crafters test:") and printed("QueryGuildMembersForRecipe: function") and printed("asking about"), "/zod crafters test prints what the game has")
    pump(6)
    reset()
    slash("crafters")
    check(printed("recipes asked about:"), "/zod crafters lists what was asked")
    local name = ns.db.crafters[18445].name
    check(found(ns.Find(name:sub(1, 6)), "Crafters", name), "search finds a recipe asked about: " .. name)

    W.guild, W.recipeMembers = savedGuild, nil
    ns.db.crafters = nil
end

---------------------------------------------------------------------------
say("--- dungeon companions")
do
    local R = ns.modules.runs
    local unitTip = W.tooltipCalls[Enum.TooltipDataType.Unit]
    local savedUnits = W.units
    ns.db.allies = nil
    reset()
    W.units = { party1 = "Bob", party2 = "Ann" }
    W.guids = { party1 = "Player-1-000B0B", party2 = "Player-1-000A22" }
    W.instance = { "The Deadmines", "party" }
    fire("ZONE_CHANGED_NEW_AREA")
    local run = ns.chardb.runs.current
    check(run and run.with and run.with.Bob == "Player-1-000B0B" and run.with.Ann, "the group is noted when you walk in")
    W.units.party3 = "Cid"
    fire("GROUP_ROSTER_UPDATE")
    check(run.with.Cid ~= nil, "and who joins later")
    pump(400, 5)
    W.instance = nil
    fire("ZONE_CHANGED_NEW_AREA")
    pump(400, 5)
    local done = ns.chardb.runs.list[1]
    check(done.name == "The Deadmines" and done.with and #done.with == 3 and done.with[1] == "Ann", "the finished run lists who was there")
    local bob = ns.db.allies.Bob
    check(bob and bob.n == 1 and bob.dungeon == "The Deadmines" and bob.guid == "Player-1-000B0B", "and each companion is remembered")

    reset()
    slash("runs with bob")
    check(printed("Bob: you ran The Deadmines, 13m ago."), "/zod runs with: a run 13 minutes back says so, not just now: " .. (W.printed[1] or ""))
    bob.at = bob.at - 3 * 86400
    slash("runs with Bob")
    check(printed("Bob: you ran The Deadmines, 3d ago."), "and how long ago")
    slash("runs with Zed")
    check(printed("Zed: you have not run a dungeon together yet."), "someone you never ran with")
    slash("runs note bob good tank, kind")
    check(bob.note == "good tank, kind" and printed("note on Bob kept."), "/zod runs note keeps a note")
    slash("runs note Zed |cffff0000rude")
    check(ns.db.allies.Zed and ns.db.allies.Zed.note == "cffff0000rude", "a note on anyone, without colour codes")
    slash("runs note Zed")
    check(ns.db.allies.Zed == nil, "an empty note removes it, and someone only noted is forgotten")

    W.units = { mouseover = "Bob", mouseovertarget = nil }
    W.players = { mouseover = true }
    GameTooltip.lines = {}
    unitTip(GameTooltip, {})
    local tip = plain(table.concat(GameTooltip.lines, "\n"))
    check(tip:find("Ran with you = The Deadmines,", 1, true) and tip:find("Note: good tank, kind", 1, true), "a player's tooltip says when you ran together: " .. tip)
    W.players = {}
    GameTooltip.lines = {}
    unitTip(GameTooltip, {})
    check(not table.concat(GameTooltip.lines, "\n"):find("Ran with you", 1, true), "not on a creature's")
    W.players = nil

    reset()
    fire("PARTY_INVITE_REQUEST", "Bob-Forever")
    check(printed("Bob invites you: you ran The Deadmines,") and printed("Note: good tank, kind."), "an invite says who it is")
    fire("CHAT_MSG_WHISPER", "hi", "Bob-Forever")
    fire("CHAT_MSG_WHISPER", "again", "Bob-Forever")
    local n = 0
    for _, l in ipairs(W.printed) do if plain(l):find("Bob: you ran", 1, true) then n = n + 1 end end
    check(n == 1, "a whisper says it once a session")
    fire("CHAT_MSG_WHISPER", "hi", "Stranger-Forever")
    check(not printed("Stranger:"), "nothing for someone you never ran with")

    R.db.companions = false
    reset()
    fire("PARTY_INVITE_REQUEST", "Ann-Forever")
    check(not printed("Ann invites you"), "switched off it says nothing")
    R.db.companions = true

    W.units, W.guids = savedUnits, nil
    ns.db.allies = nil
end

---------------------------------------------------------------------------
say("--- death helper and the Hardcore feed")
do
    local D = ns.modules.deaths
    local savedLevel = W.level
    ns.db.hardcoreDeaths = nil
    reset()
    -- you at 62.13, 20.51 on a 3000 x 2000 yard map; the corpse 0.02 east of you: 60 yards
    W.corpse = { 0.6413, 0.2051 }
    check(D.CorpseYards() == 60, "the corpse's distance in yards: " .. tostring(D.CorpseYards()))
    W.level = 30
    fire("CONFIRM_XP_LOSS")
    check(printed("The spirit healer costs resurrection sickness") and printed("25% durability") and printed("Your corpse is 60 yards away: walking back is free."),
        "the spirit healer's cost, and that walking back is quicker")
    reset()
    W.corpse, W.level = { 0.9, 0.9 }, 8
    fire("CONFIRM_XP_LOSS")
    check(printed("(no sickness up to level 10)") and printed("yards away.") and not printed("walking back is free"), "low level: no sickness; far: just the distance")
    reset()
    W.corpse = nil
    fire("CONFIRM_XP_LOSS")
    check(printed("The spirit healer costs") and not printed("yards"), "without a corpse on this map, just the cost")
    D.db.healer = false
    reset()
    fire("CONFIRM_XP_LOSS")
    check(#W.printed == 0, "switched off it says nothing")
    D.db.healer = true

    reset()
    fire("HARDCORE_DEATHS", "Mortis")
    check(#W.printed == 0 and ns.db.hardcoreDeaths == nil, "off Hardcore the announcement is ignored")
    W.hardcore = true
    fire("HARDCORE_DEATHS", "Mortis")
    fire("HARDCORE_DEATHS", "Grim|cffff0000x")
    local list = ns.db.hardcoreDeaths
    check(list and #list == 2 and list[1].name == "Grimcffff0000x" and printed("Hardcore: Mortis has died."), "on Hardcore each death is kept, newest first, with a notice")
    slash("home")
    check(has("Hardcore today") and has("2 deaths"), "Home's Deaths card counts today's")
    reset()
    slash("deaths hardcore")
    check(printed("the last Hardcore deaths:") and printed("Mortis"), "/zod deaths hardcore lists them")
    D.db.hardcore = false
    reset()
    fire("HARDCORE_DEATHS", "Quiet")
    check(#W.alerts == 0 and list[1].name == "Quiet", "with the notice off they are still kept")
    D.db.hardcore = true

    W.hardcore, W.level, W.corpse = nil, savedLevel, nil
    ns.db.hardcoreDeaths = nil
end

---------------------------------------------------------------------------
say("--- spoken notices")
do
    local general = ns.db.general
    reset()
    ns.Alert("Off by default.")
    check(general.speak == false and called("SpeakText") == 0, "notices are not read aloud unless ticked")
    general.speak = true
    pump(3)
    ns.Alert("Your pet is |cffff5555unhappy|r: feed it |cffffffff|Hitem:910|h[Roasted Boar Meat]|h|r.")
    local said
    for _, c in ipairs(W.calls) do if c[1] == "SpeakText" then said = c[2] end end
    check(said == "Your pet is unhappy: feed it Roasted Boar Meat.", "ticked, a notice is read without colour or link codes: " .. tostring(said))
    ns.Alert("Your pet is |cffff5555unhappy|r: feed it |cffffffff|Hitem:910|h[Roasted Boar Meat]|h|r.")
    check(called("SpeakText") == 1, "the same notice twice at once is read once")
    pump(3)
    ns.Alert("Your pet is |cffff5555unhappy|r: feed it |cffffffff|Hitem:910|h[Roasted Boar Meat]|h|r.")
    check(called("SpeakText") == 2, "and again later")
    local VC = C_VoiceChat
    C_VoiceChat = nil
    ns.Alert("No speech here.")
    check(printed("No speech here."), "a client without text to speech still shows the notice")
    C_VoiceChat = VC
    general.speak = false
end

---------------------------------------------------------------------------
say("--- guild loans")
do
    local L = ns.modules.loans
    local function sends(text, target)
        local n = 0
        for _, c in ipairs(W.calls) do
            if c[1] == "SendAddonMessage" and (text == nil or c[2] == text) and (target == nil or c[4] == target) then n = n + 1 end
        end
        return n
    end
    local function hear(text, from, channel)
        fire("CHAT_MSG_ADDON", "ZodUILoans", text, channel or "WHISPER", from or "Bob-Forever", "Zod", 0, 0, "", 0)
    end
    local function loan(n)
        for _, l in ipairs(ns.chardb.loans and ns.chardb.loans.list or {}) do
            if l.n == n then return l end
        end
    end
    local savedName, savedGuild, savedMoney, savedUnits = W.name, W.guild, W.money, W.units
    W.name, W.guild, W.units = nil, true, {}
    W.roster = { { "Bob-Forever", true }, { "Ann-Forever", false } }
    ns.chardb.loans = nil
    reset()
    check(L.enabled and W.prefixes.ZodUILoans, "the module is on and its addon prefix is registered")
    fire("GUILD_ROSTER_UPDATE")

    local c, rest = L.ParseMoney("5g 20s for the mount")
    check(c == 52000 and rest == "for the mount", "5g 20s is read as gold and silver, the rest is the note")
    check(L.ParseMoney("50s") == 5000 and L.ParseMoney("2.5") == 25000 and L.ParseMoney("5g20s3c") == 52003, "50s, 2.5 and 5g20s3c")
    c, rest = L.ParseMoney("5 5 potions")
    check(c == 50000 and rest == "5 potions", "a bare number is gold only as the first word")
    check(L.ParseMoney("lots") == nil and L.ParseMoney("1.5s") == nil, "no amount, or silver with a point, is not an amount")

    slash("loans lend bob 5g for the mount")
    local at = loan(1).at
    check(printed("loan 1: Bob owes you 5g. Waiting for Bob to agree."), "a loan is written down, with the name capitalised")
    check(sends("1~A~Zod:1~L~50000~" .. at .. "~for the mount", "Bob-Forever") == 1, "and said to Bob in an addon whisper")
    fire("GUILD_ROSTER_UPDATE")
    check(sends() == 1, "but not again while Bob stays online")
    hear("1~Y~Zod:1")
    check(loan(1).agreed and printed("Bob agrees: Bob owes you 5g."), "Bob agrees")

    reset()
    W.roster[3] = { "Eve-Forever", true }
    fire("GUILD_ROSTER_UPDATE")
    hear("1~A~Mal:1~B~10000~" .. at .. "~", "Mal-Forever")
    hear("1~N~Zod:1", "Ann-Forever")
    hear("1~A~Ann:4~B~10000~" .. at .. "~", "Bob-Forever")
    hear("1~A~Bob:9~B~10000~" .. at .. "~", "Bob-Forever", "GUILD")
    hear("2~A~Bob:9~B~10000~" .. at .. "~")
    hear("1~A~Bob:9~X~10000~" .. at .. "~")
    hear("1~A~Bob:9~B~-5~" .. at .. "~")
    hear("1~A~Bob:9~B~1.5~" .. at .. "~")
    check(#ns.chardb.loans.list == 1 and loan(1).agreed and not loan(1).refused and #W.printed == 0,
        "not from outside the guild, not for someone else's loan, not in guild chat, and not malformed")

    hear("1~A~Bob:7~L~30000~" .. (at + 99999) .. "~potions |cffff0000red|r")
    local claim = loan(2)
    check(claim and claim.claim == "add" and not claim.lent and claim.note == "potions cffff0000redr" and claim.at <= time(),
        "Bob writes down that you owe him: a claim, its note without colour codes, its date not in the future")
    check(printed("Bob wrote down that you owe Bob 3g (potions cffff0000redr). /zod loans ok 2 agrees, /zod loans no 2 refuses."),
        "you are told, with the commands to answer")
    local owed, owe, _, _, ask = L:Totals()
    check(owed == 50000 and owe == 0 and ask == 1, "a claim counts only once you agree")
    slash("home")
    check(has("Loans") and has("Owed to you") and has("To answer"), "Home has a Loans card")
    slash("loans ok 2")
    check(claim.agreed and sends("1~Y~Bob:7", "Bob-Forever") == 1, "/zod loans ok agrees and tells Bob")
    hear("1~A~Bob:7~L~30000~" .. at .. "~potions")
    check(sends("1~Y~Bob:7") == 2 and #ns.chardb.loans.list == 2, "Bob saying it again gets the answer again, not a second loan")

    reset()
    slash("loans paid 2")
    check(claim.asked == "paid" and not claim.paid and sends("1~P~Bob:7") == 1 and printed("asked Bob to agree that you paid back 3g"),
        "paying back what you owe asks Bob")
    hear("1~Y~Bob:7")
    check(claim.paid and printed("Bob agrees you paid back the 3g."), "and it is paid when Bob agrees")
    slash("loans paid 1")
    check(loan(1).paid and sends("1~P~Zod:1") == 1, "the one who lent says it is paid, and tells Bob")
    slash("loans paid 1")
    check(printed("Loan 1 is paid already."), "paid twice says so")

    reset()
    slash("loans lend Bob 1g")
    hear("1~Y~Zod:3")
    hear("1~P~Zod:3")
    check(loan(3).claim == "paid" and not loan(3).paid and printed("Bob says they paid back the 1g. /zod loans ok 3"),
        "Bob saying he paid you back is a claim")
    slash("loans no 3")
    check(not loan(3).claim and not loan(3).paid and sends("1~N~Zod:3") == 1, "you can say it is not")
    hear("1~A~Bob:8~B~20000~" .. at .. "~")
    slash("loans no 4")
    check(loan(4).refused and sends("1~N~Bob:8") == 1, "and refuse a loan you never had")
    slash("loans lend Bob 2g")
    hear("1~N~Zod:5")
    check(loan(5).refused and printed("Bob says no to the loan"), "Bob can refuse yours")
    slash("loans ok 1")
    check(printed("Loan 1 has nothing to agree to."), "ok on a loan with nothing to answer says so")
    slash("loans paid 99")
    check(printed("no loan 99."), "a number that is no loan says so")

    reset()
    slash("loans lend Ann 2g")
    check(sends() == 0, "Ann is offline: nothing is sent yet")
    W.roster[2][2] = true
    fire("GUILD_ROSTER_UPDATE")
    check(sends("1~A~Zod:6~L~20000~" .. loan(6).at .. "~", "Ann-Forever") == 1, "it is sent when she comes online")
    W.roster[2][2] = false
    fire("GUILD_ROSTER_UPDATE")
    W.roster[2][2] = true
    fire("GUILD_ROSTER_UPDATE")
    check(sends(nil, "Ann-Forever") == 2, "and again after she was away, until she answers")
    slash("loans lend Carl 1g")
    check(sends(nil, "Carl") == 0 and printed("loan 7: Carl owes you 1g.") and not printed("Waiting for Carl"),
        "someone outside the guild is only on your list")
    W.combat = true
    slash("loans borrow Bob 4g")
    check(sends("1~A~Zod:8~B~40000~" .. loan(8).at .. "~") == 0, "nothing is sent in combat")
    W.combat = false
    fire("PLAYER_REGEN_ENABLED")
    check(sends("1~A~Zod:8~B~40000~" .. loan(8).at .. "~") == 1, "but after it")
    W.sendResult = 3
    slash("loans borrow Bob 6g")
    check(loan(9).out and loan(9).out[1] == "A", "a throttled send is kept")
    W.sendResult = nil
    W.roster[1][2] = false
    fire("GUILD_ROSTER_UPDATE")
    W.roster[1][2] = true
    fire("GUILD_ROSTER_UPDATE")
    check(sends("1~A~Zod:9~B~60000~" .. loan(9).at .. "~") == 2, "and sent again later")
    slash("loans lend Zod 1g")
    check(printed("That is you."), "not to yourself")
    slash("loans lend Bob")
    check(printed("Type an amount, for example 5g or 50s."), "not without an amount")

    reset()
    W.roster = {}
    fire("GUILD_ROSTER_UPDATE")
    hear("1~A~Bob:20~L~10000~" .. at .. "~early")
    check(#ns.chardb.loans.list == 9, "a message before the roster is in waits")
    W.roster = { { "Bob-Forever", true }, { "Ann-Forever", true } }
    fire("GUILD_ROSTER_UPDATE")
    check(#ns.chardb.loans.list == 10 and loan(10).note == "early", "and is read when it comes")

    reset()
    W.units.NPC = "Bob"
    fire("TRADE_SHOW")
    W.trade = { gave = 70000, got = 0 }
    fire("TRADE_ACCEPT_UPDATE", 1, 0)
    W.money = W.money - 70000
    fire("TRADE_CLOSED")
    pump(1.5)
    check(printed("You gave Bob 7g. /zod loans lend Bob 7g writes it down as a loan."), "a gold trade offers to write it down")
    reset()
    fire("TRADE_SHOW")
    W.trade = { gave = 40000, got = 0 }
    fire("TRADE_ACCEPT_UPDATE", 1, 0)
    W.money = W.money - 40000
    fire("TRADE_CLOSED")
    pump(1.5)
    check(printed("Paying Bob back? /zod loans paid 8 says so."), "and knows a payback when the amount is a loan you owe")
    reset()
    fire("TRADE_SHOW")
    W.trade = { gave = 0, got = 20000 }
    fire("TRADE_ACCEPT_UPDATE", 0, 1)
    fire("TRADE_CLOSED")
    pump(1.5)
    W.trade = { gave = 0, got = 20000, items = true }
    fire("TRADE_SHOW")
    fire("TRADE_ACCEPT_UPDATE", 1, 1)
    W.money = W.money + 20000
    fire("TRADE_CLOSED")
    pump(1.5)
    W.units.NPC = "Stranger"
    fire("TRADE_SHOW")
    W.trade = { gave = 0, got = 20000 }
    fire("TRADE_ACCEPT_UPDATE", 1, 1)
    W.money = W.money + 20000
    fire("TRADE_CLOSED")
    pump(1.5)
    check(#W.printed == 0, "not for a cancelled trade, one with items, or someone outside the guild")
    W.trade = nil

    reset()
    slash("loans list")
    check(printed("owed to you") and printed("1  Bob owes you 5g") and printed("Paid back"), "/zod loans list")
    slash("loans")
    check(has("Only on your list") and has("Asks you to agree") and has("for the mount"), "the page lists them")
    local page = ns.pages.loans
    page.list.selected = nil
    page:Refresh()
    check(page.acts[1].off and page.acts[4].off, "the loan buttons are greyed until a loan is chosen")
    page.list.onClick(10)
    check(not page.acts[1].off, "and lit once one is")
    click("Agree")
    check(loan(10).agreed and sends("1~Y~Bob:20") == 1, "the page's Agree button answers")
    page.who.edit:SetText("ann")
    page.amount.edit:SetText("3g")
    page.note.edit:SetText("arrows")
    click("I lent")
    check(has("Loan 11: Ann owes you 3g.") and loan(11).note == "arrows", "and the page writes one down")
    check(found(ns.Find("arrows"), "Loan", "Ann"), "search finds a loan by its note")
    slash("loans forget 11")
    check(not loan(11) and printed("forgot loan 11."), "/zod loans forget")
    local before = #ns.chardb.loans.list
    click(click("Forget the paid ones"))
    check(#ns.chardb.loans.list < before and not loan(1) and not loan(4), "the paid and refused ones can be forgotten")

    pump(61) -- a new minute: Bob has said a lot in this one
    for i = 30, 45 do hear("1~A~Bob:" .. i .. "~L~100~" .. at .. "~") end
    local claims = 0
    for _, l in ipairs(ns.chardb.loans.list) do if l.claim then claims = claims + 1 end end
    check(claims == 10, "one guild member can ask you to agree to at most 10 loans at once: " .. claims)

    reset()
    L.db.share = false
    hear("1~A~Bob:60~L~100~" .. at .. "~")
    slash("loans lend Bob 1g")
    check(sends() == 0 and not printed("Bob wrote down"), "with sharing off nothing is sent or taken")
    L.db.share = true

    ns.chardb.loans = nil
    W.name, W.guild, W.money, W.units, W.roster = savedName, savedGuild, savedMoney, savedUnits, nil
    fire("GUILD_ROSTER_UPDATE")
end

---------------------------------------------------------------------------
say("--- the character's story")
do
    local S = ns.modules.story
    local c = ns.chardb
    check(S.CivilDay("1970-01-01") == 0 and S.CivilDay("2024-03-01") - S.CivilDay("2024-02-28") == 2
        and S.CivilDay("2023-03-01") - S.CivilDay("2023-02-28") == 1 and S.CivilDay("2027-01-01") - S.CivilDay("2026-12-31") == 1,
        "days are counted by the calendar, leap years too")
    local saved = { zones = c.zones, deaths = c.deaths, runs = c.runs, finds = c.finds, quests = c.questsDone, history = c.history,
        story = c.story, clock = W.clock, level = W.level, zone = W.zone }
    local now = W.clock
    local today, yesterday = date("%Y-%m-%d", now), date("%Y-%m-%d", now - 86400)
    c.story = nil
    c.zones = { ["Elwynn Forest"] = { first = now - 2 * 86400, level = 1, time = 0, levels = 0 },
        Westfall = { first = now - 86400, level = 11, time = 0, levels = 0 } }
    c.deaths = { { at = now - 86400 + 60, level = 12, zone = "Westfall", sub = "Moonbrook" } }
    c.runs = { list = { { name = "The Deadmines", at = now - 86400 + 120, took = 3000, deaths = 1, level = 18, with = { "Ann", "Bob" } } } }
    c.finds = { { at = now - 86400 + 180, name = "Cruel Barb", q = 3, where = "The Deadmines" },
        { at = now - 86400 + 190, name = "Linen Cloth", q = 2, where = "Westfall" } }
    c.questsDone = { { at = now - 86400 + 10 }, { at = now - 86400 + 20 }, { at = now - 5 } }
    c.history = { days = { [yesterday] = { played = 7800 } } }
    fire("PLAYER_LEVEL_UP", 19)
    local was = W.factions[3].reaction
    W.factions[3].reaction = was + 1
    fire("UPDATE_FACTION")
    W.factions[3].reaction = was
    fire("UPDATE_FACTION")
    check(#c.story.levels == 1 and c.story.levels[1].level == 19 and c.story.levels[1].zone == W.zone, "a level reached is kept, with where")
    check(#c.story.standings == 1 and c.story.standings[1].name == "Orgrimmar", "a standing gained is kept, a lost one is not")

    local days = S:Days()
    check(#days == 3 and days[1].key == today and days[3].number == 1 and days[1].number == 3, "the days, newest first, numbered from the first")
    check(days[2].quests == 2 and days[2].played == 7800, "each day knows its quests and time played")
    local texts = {}
    for _, e in ipairs(days[2].events) do texts[#texts + 1] = e.plain end
    check(texts[1] == "First came to Westfall at level 11." and texts[2] == "Died in Moonbrook, Westfall at level 12."
        and texts[3] == "Ran The Deadmines (50m, 1 death), with Ann, Bob." and texts[4] == "Found [Cruel Barb] in The Deadmines."
        and #texts == 4, "a day's moments in order, a green find left out: " .. table.concat(texts, " | "))
    check(S.Heading(days[2]):find("^Day 2, .*: 2 quests, 2h 10m played$") ~= nil, "a day's heading: " .. S.Heading(days[2]))
    check(S.Heading(days[1]):find("level 19", 1, true) ~= nil, "with the level reached that day")

    reset()
    slash("story")
    check(has("Day 3,") and has("Reached level 19 in " .. W.zone .. ".") and has("Became Friendly with Orgrimmar.") and has("3 days,"),
        "/zod story opens the page with the timeline")
    reset()
    slash("story export")
    local box = ZodUIStoryBox
    local text = box and box.edit:GetText() or ""
    check(box and box:IsShown() and text:find("^Zod, level %d+: a story kept by ZodUI%.") and text:find("\nDay 1, ", 1, true)
        and text:find("Found [Cruel Barb] in The Deadmines.", 1, true) and not text:find("|c", 1, true), "/zod story export: plain text, oldest first")
    check(text:find("Day 1", 1, true) < text:find("Day 3", 1, true), "a story is read from the start")
    check(box.child:GetHeight() == box.edit:GetHeight() and box.child:GetHeight() >= 300, "the box scrolls the whole text")
    box:Hide()
    local one = S:Text(1)
    check(one:find("Day 3", 1, true) and not one:find("Day 2", 1, true), "/zod story export 1 gives only today")
    check(S:Card().lines[1][2] == "Day 3", "Home's card says which day it is")
    c.zones, c.deaths, c.runs, c.finds, c.questsDone, c.history, c.story = {}, {}, { list = {} }, {}, {}, { days = {} }, nil
    check(S:Text():find("Nothing yet: the story starts now.", 1, true) and S:Card() == nil, "with nothing kept, it says the story starts now")

    c.zones, c.deaths, c.runs, c.finds, c.questsDone, c.history, c.story = saved.zones, saved.deaths, saved.runs, saved.finds,
        saved.quests, saved.history, saved.story
end

---------------------------------------------------------------------------
say("--- leveling coach")
do
    local C = ns.modules.coach
    local XP = ns.modules.session.XP_TO_LEVEL
    local saved = { level = W.level, xp = W.xp, xpMax = W.xpMax, rested = W.rested, history = ns.chardb.history, coach = ns.chardb.coach,
        goal = ns.chardb.levelGoal, route = UndeadRoute, afk = W.afk }
    local now = W.clock
    W.level, W.xp, W.xpMax, W.rested = 20, 3200, XP[20], 0
    check(C:XPTo(21) == XP[20] - 3200 and C:XPTo(23) == XP[20] - 3200 + XP[21] + XP[22] and C:XPTo(20) == 0,
        "XP to a level: what is left of this one and each one between")
    local toTop = ns.modules.session:XPToTop()
    check(C:XPTo(60) == toTop, "the same as Session & XP's way to 60")

    ns.chardb.history = { days = { [date("%Y-%m-%d", now)] = { xp = 30000, played = 3600 },
        [date("%Y-%m-%d", now - 86400)] = { xp = 30000, played = 7200 },
        [date("%Y-%m-%d", now - 2 * 86400)] = { xp = 999999, played = 100 } } }
    local perHour, perDay = C:Pace()
    check(perHour and math.abs(perHour - 20000) < 0.01 and perDay == 5400, "pace: XP per played hour over the days that had play, short ones left out")

    UndeadRoute = { Toggle = function() end, Status = function()
        return { stage = "Hillsbrad Foothills (Tarren Mill)", range = "20-25", min = 20, max = 25, kind = "zone", left = 3 }
    end }
    ns.chardb.levelGoal = 30
    local list = C:Forecasts()
    local labels = {}
    for i, l in ipairs(list) do labels[i] = l[1] end
    check(table.concat(labels, " | ") == "Level 21 | Hillsbrad Foothills (Tarren Mill) done (25) | Your goal, 30 | Level 60",
        "forecasts: the next level, the route's stage, your goal and 60: " .. table.concat(labels, " | "))
    local sec = C:XPTo(25) / 20000 * 3600
    check(list[2][2]:find(ns.Duration(sec) .. " played", 1, true) == 1 and list[2][2]:find("about " .. math.ceil(sec / 5400) .. " days", 1, true),
        "in played time and in days at your usual play: " .. list[2][2])
    check(C:RouteAdvice() == "On pace for Hillsbrad Foothills (Tarren Mill) (20-25).", "in the stage: on pace")
    W.level = 18
    check(C:RouteAdvice():find("^You are 2 levels under Hillsbrad") ~= nil, "under it: how far under")
    W.level = 25
    check(C:RouteAdvice():find("^You are past Hillsbrad") ~= nil and #C:Forecasts() == 3, "past it: move on, and no forecast for it")
    W.level = 20
    UndeadRoute.Status = function() return { stage = "Old", range = "22-27", left = 1 } end
    check(C.Route() and C.Route().min == 22 and C.Route().max == 27, "an older Undead Route without numbers: its range is read")
    UndeadRoute.Status = function() return { stage = "Orgrimmar", range = "City", kind = "city", left = 1 } end
    check(C.Route() == nil, "a city is no stage to forecast")
    UndeadRoute.Status = function() error("broken") end
    check(C.Route() == nil and #C:Forecasts() == 3, "a failing route is left out")
    UndeadRoute = nil
    ns.chardb.levelGoal = nil

    -- zones by XP per hour
    ns.chardb.coach = nil
    C:OnEnable()
    W.zone = "Hillsbrad Foothills"
    W.xp = W.xp + 5000
    fire("PLAYER_XP_UPDATE", "player")
    pump(700, 10)
    W.afk = true
    pump(600, 10)
    W.afk = false
    local z = C:Zones()[1]
    check(z and z.name == "Hillsbrad Foothills" and z.time >= 600 and z.time <= 720, "a zone's time counts while you level there, not while away")
    W.xp = 100
    fire("PLAYER_XP_UPDATE", "player")
    check(ns.chardb.coach.zones["Hillsbrad Foothills"].xp == 5000 + (W.xpMax - 8200) + 100, "a level-up counts the XP on both sides of it")

    -- rested
    W.rested, W.resting = 4000, false
    ns.db.chars["Alt-Forever"].seen = now - 3600
    local rested = C:Rested()
    local me, alt = rested[1], nil
    for _, r in ipairs(rested) do if r.name == "Alt" then alt = r end end
    check(me and me.mine and me.rested == 4000 and math.abs(me.levels - 4000 / W.xpMax) < 1e-9, "your own rested XP, first")
    local grown = 3000 + 0.05 / (8 * 3600) * 30000 * (W.clock - (now - 3600))
    check(alt and alt.resting and math.abs(alt.rested - grown) < 1e-6 and alt.full > 0, "an alt's rested XP grows since you saw it: " .. tostring(alt and alt.rested))
    ns.db.chars["Alt-Forever"].seen = now - 30 * 86400
    alt = nil
    for _, r in ipairs(C:Rested()) do if r.name == "Alt" then alt = r end end
    check(alt and alt.full == 0 and math.abs(alt.levels - 1.5) < 1e-9, "and stops at one and a half levels")

    reset()
    slash("coach")
    check(has("Your pace: " .. ns.Comma((C:Pace())) .. " XP per played hour"), "/zod coach opens the page with your pace")
    check(has("Level 21") and has("Hillsbrad Foothills") and has("Alt"), "the forecasts, the best zones and the rested list")
    local card = C:Card()
    check(card and card.lines[1][1] == "Level 21" and card.lines[#card.lines][1] == "Rested", "Home's card: the next forecasts and rested XP")
    W.level = 60
    check(C:Card() == nil and #C:Forecasts() == 0, "at 60 there is nothing to coach")

    W.level, W.xp, W.xpMax, W.rested, W.afk = saved.level, saved.xp, saved.xpMax, saved.rested, saved.afk
    ns.chardb.history, ns.chardb.coach, ns.chardb.levelGoal, UndeadRoute = saved.history, saved.coach, saved.goal, saved.route
    ns.db.chars["Alt-Forever"].seen = now - 16 * 3600
    C:OnEnable()
end

---------------------------------------------------------------------------
say("--- raid planner")
do
    local R = ns.modules.raids
    local chars = ns.db.chars
    local saved = { roster = W.roster, party = W.party, allies = ns.db.allies, rolls = ns.db.rolls, runs = ns.chardb.runs,
        zodSaved = chars["Zod-Forever"].saved, zodLevel = chars["Zod-Forever"].level, altSaved = chars["Alt-Forever"].saved, reminded = ns.chardb.raidsReminded }
    reset()
    R:Disable()
    R:Enable()
    check(called("OpenCalendar") == 1 and called("RequestRaidInfo") == 1, "switched on, it asks for the calendar and the lockouts")

    -- upcoming
    W.calendarNow = { year = 2026, month = 11, monthDay = 29, hour = 19, minute = 50 }
    W.monthDays = { [0] = 30, [1] = 31 }
    local mc = { eventID = 1, title = "Molten Core", calendarType = "GUILD_EVENT", inviteStatus = 3,
        startTime = { year = 2026, month = 11, monthDay = 29, hour = 20, minute = 0 } }
    W.calendar = {
        [0] = {
            [29] = { mc, { eventID = 9, title = "Harvest Festival", calendarType = "HOLIDAY", startTime = { year = 2026, month = 11, monthDay = 29, hour = 0, minute = 0 } },
                { eventID = 3, title = "Earlier today", calendarType = "PLAYER", inviteStatus = 3, startTime = { year = 2026, month = 11, monthDay = 29, hour = 17, minute = 0 } },
                { eventID = 4, title = "Zul'Gurub", calendarType = "GUILD_EVENT", inviteStatus = 2, startTime = { year = 2026, month = 11, monthDay = 29, hour = 20, minute = 5 } } },
            [30] = { mc }, -- an event over two days
        },
        [1] = { [2] = { { eventID = 2, title = "Onyxia's |cffff0000Lair", calendarType = "PLAYER", inviteStatus = 0,
            startTime = { year = 2026, month = 12, monthDay = 2, hour = 21, minute = 0 } } } },
    }
    local events = R:Events()
    local titles = {}
    for i, e in ipairs(events) do titles[i] = e.title end
    check(table.concat(titles, " | ") == "Molten Core | Zul'Gurub | Onyxia's cffff0000Lair",
        "the next two weeks across the month's end, soonest first, once each, no holidays or past ones: " .. table.concat(titles, " | "))
    check(events[1].mins == 10 and events[3].mins == 3 * 1440 + 70 and events[1].status == "Confirmed" and events[3].status == "Invited",
        "minutes to each, and your answer")
    check(R.When(events[1].start) == "Sun 20:00" and R.When(events[3].start) == "Wed 21:00", "the weekday from the date")
    ns.chardb.raidsReminded = nil
    reset()
    pump(31)
    check(printed("Molten Core starts in 10 minutes (you: Confirmed).") and not printed("Zul'Gurub"), "a notice before an event, not one you declined")
    reset()
    pump(31)
    check(not printed("Molten Core starts"), "once")
    R.db.remind = 0
    ns.chardb.raidsReminded = nil
    reset()
    pump(31)
    check(not printed("starts in"), "none with the notice off")
    R.db.remind = 15

    -- lockouts
    chars["Zod-Forever"].saved = { { name = "Molten Core", reset = time() + 86400 }, { name = "Gone", reset = time() - 10 } }
    chars["Zod-Forever"].level = 60
    chars["Alt-Forever"].saved = {}
    chars["Mira-Forever"] = { name = "Mira", level = 60, saved = {} }
    local locks = R:Lockouts()
    check(#locks == 1 and locks[1].name == "Molten Core" and locks[1].saved[1].who == "Zod" and table.concat(locks[1].free, ",") == "Mira",
        "who is saved and who is free, by level; an expired lockout is left out")

    -- group
    ns.db.allies = { Bob = { n = 3, dungeon = "The Deadmines", note = "good tank" }, Ann = { n = 5, dungeon = "Molten Core" },
        Cid = { n = 9, dungeon = "Molten Core" }, Dan = { n = 1, dungeon = "Scholomance" }, Eve = { note = "only a note" } }
    W.roster = { { "Bob-Forever", true }, { "Cid-Forever", false }, { "Dan-Forever", true }, { "Eve-Forever", true } }
    W.friendList = { { name = "Ann", connected = true, level = 60, className = "Priest" } }
    W.party = { Dan = true }
    local names = {}
    for i, c in ipairs(R:Candidates()) do names[i] = c.name end
    check(table.concat(names, ",") == "Ann,Bob", "online people you ran with, most runs first, not offline, in your group or never run with: " .. table.concat(names, ","))
    check(#R:Candidates("molten") == 1, "narrowed to a dungeon")
    reset()
    slash("raids group")
    check(printed("1. |Hplayer:Ann|h[Ann]|h") and printed("5 runs together, last Molten Core") and printed("good tank"), "/zod raids group lists them")
    reset()
    slash("raids invite 1")
    check(called("InviteUnit") == 1 and W.calls[1][2] == "Ann" and printed("asked 1 player to your group."), "/zod raids invite asks the first ones")
    slash("raids invite")
    check(printed("use /zod raids invite 4"), "and says how without a number")

    -- history
    local t0 = W.clock - 3 * 86400
    ns.chardb.runs = { list = { { name = "Molten Core", kind = "raid", at = t0, took = 7200, with = { "Ann", "Bob" } },
        { name = "The Deadmines", kind = "party", at = t0 - 100, took = 1800, with = { "Cid" } },
        { name = "Onyxia's Lair", kind = "raid", at = t0 - 86400, took = 3600, with = { "Ann" } } } }
    ns.db.rolls = { { at = t0 + 600, name = "Robe of Volatile Power", winner = "Ann" }, { at = t0 + 9000, name = "Later", winner = "Bob" },
        { at = t0 + 700, name = "Nobody", winner = "" } }
    local raids, attendance = R:History()
    check(#raids == 2 and raids[1].loot[1] == "Robe of Volatile Power (Ann)" and #raids[1].loot == 1, "raids only, with the loot won during each")
    check(attendance[1].name == "Ann" and attendance[1].n == 2 and attendance[2].name == "Bob", "who came, most first")
    reset()
    slash("raids attendance")
    check(printed("who came to your 2 raids: Ann 2/2, Bob 1/2."), "/zod raids attendance")

    reset()
    slash("raids")
    check(has("Molten Core") and has("Confirmed") and has("Mira") and has("Robe of Volatile Power (Ann)") and has("2 people you ran with are online"),
        "/zod raids opens the page")
    local card = R:Card()
    check(card and card.lines[1][1] == "Molten Core" and card.lines[2][2] == "Confirmed" and card.lines[3][1] == "Lockouts", "Home's card")
    W.calendar, W.calendarNow = nil, nil
    check(#R:Events() == 0, "no calendar, no events")

    W.roster, W.party, W.friendList = saved.roster, saved.party, nil
    ns.db.allies, ns.db.rolls, ns.chardb.runs, ns.chardb.raidsReminded = saved.allies, saved.rolls, saved.runs, saved.reminded
    chars["Zod-Forever"].saved, chars["Zod-Forever"].level, chars["Alt-Forever"].saved = saved.zodSaved, saved.zodLevel, saved.altSaved
    chars["Mira-Forever"] = nil
end

---------------------------------------------------------------------------
say("--- loot shout")
do
    local S = ns.modules.shout
    local savedGuild, savedCombat = W.guild, W.combat
    local function guildLines()
        local out = {}
        for _, c in ipairs(W.calls) do
            if c[1] == "SendChatMessage" and c[3] == "GUILD" then out[#out + 1] = c[2] end
        end
        return out
    end
    local function loot(msg) fire("CHAT_MSG_LOOT", msg, "", "", "", "Zod") end
    local EPIC = "|cffa335ee|Hitem:19019::::::::60:::::|h[Thunderfury]|h|r"
    local EPIC2 = "|cffa335ee|Hitem:17076::::::::60:::::|h[Bonereaver's Edge]|h|r"
    local BLUE = "|cff0070dd|Hitem:13340::::::::60:::::|h[Cape of the Black Baron]|h|r"
    W.guild = true
    S.Forget()
    reset()
    loot("You receive loot: " .. EPIC .. ".")
    check(#guildLines() == 0, "it waits a moment for the game to load the item")
    pump(2)
    local lines = guildLines()
    check(#lines == 1 and lines[1]:find(EPIC, 1, true) and not lines[1]:find("upgrade"), "an epic is said in guild chat, with its link: " .. tostring(lines[1]))
    loot("You receive loot: " .. EPIC2 .. ".")
    pump(2)
    check(#guildLines() == 1, "not twice within a minute")
    pump(61)
    loot("You receive loot: " .. EPIC .. ".")
    pump(2)
    check(#guildLines() == 1, "the same item is said once in a while")
    loot("You receive loot: " .. BLUE .. ".")
    pump(2)
    check(#guildLines() == 1, "a blue is not, by default")

    -- upgrades, from Forever Leveling BiS: off by default (they can be many lines in guild chat), on here
    check(S.db.upgrades == false, "upgrade shouts start switched off")
    S.db.upgrades = true
    ForeverLevelingBiS_API = { GetGain = function(link) return link:find("13340", 1, true) and 4.2 or nil end }
    S.Forget()
    reset()
    loot("You receive loot: " .. BLUE .. ".")
    pump(2)
    lines = guildLines()
    check(#lines == 1 and lines[1]:find(BLUE, 1, true) and lines[1]:find("An upgrade for me, too.", 1, true), "a blue upgrade is said, as an upgrade")
    S.db.upgrades = false
    check(S:Line(BLUE, 13340, 3, "loot") == nil, "not with upgrades off")
    S.db.upgrades = true
    ForeverLevelingBiS_API = { GetGain = function() error("broken") end, IsUpgrade = function() return true end }
    check(S.Upgrade(BLUE) == true, "a failing GetGain falls back to IsUpgrade")
    ForeverLevelingBiS_API = nil
    check(S.Upgrade(BLUE) == false, "without the addon, nothing is an upgrade")

    -- what counts
    check(S:Line(EPIC, 19019, 4, "created") == nil, "a made item is never said")
    S.db.quests = false
    check(S:Line(EPIC, 19019, 4, "pushed") == nil and S:Line(EPIC, 19019, 4, "loot") ~= nil, "quest rewards can be left out")
    S.db.quests = true
    S.db.quality = 3
    check(S:Line(BLUE, 13340, 3, "loot") ~= nil, "blue and better says blues")
    S.db.quality = 0
    check(S:Line(EPIC, 19019, 4, "loot") == nil, "never says nothing")
    S.db.quality = 4

    -- combat, no guild
    S.Forget()
    reset()
    W.combat = true
    loot("You receive loot: " .. EPIC .. ".")
    pump(3)
    check(#guildLines() == 0, "in combat it waits")
    W.combat = false
    pump(3)
    check(#guildLines() == 1, "and says it after")
    S.Forget()
    reset()
    W.guild = false
    loot("You receive loot: " .. EPIC2 .. ".")
    pump(3)
    check(#guildLines() == 0, "nothing outside a guild")
    W.guild = true

    reset()
    slash("shout test")
    check(printed("in guild chat this would say: ") and printed("Thunderfury") and #guildLines() == 0, "/zod shout test says it only to you")

    W.guild, W.combat = savedGuild, savedCombat
    S.Forget()
end

---------------------------------------------------------------------------
say("--- guild network")
do
    local G, C, Bus = ns.modules.guild, ns.modules.crafters, ns.Bus
    local function sent(start)
        local out = {}
        for _, c in ipairs(W.calls) do
            if c[1] == "SendAddonMessage" and c[2]:sub(1, #start) == start then out[#out + 1] = c end
        end
        return out
    end
    local function hear(text, from, channel)
        fire("CHAT_MSG_ADDON", "ZodUI", text, channel or "GUILD", from or "Bob-Forever", "Zod", 0, 0, "", 0)
    end
    local function line(text)
        for _, l in ipairs(W.printed) do
            local t = plain(l):gsub("|H.-|h(.-)|h", "%1")
            if t:find(text, 1, true) then return t end
        end
        return ""
    end
    local saved = { guild = W.guild, name = W.name, units = W.units, guids = W.guids, questLog = W.questLog }
    W.guild, W.name = true, nil
    ns.db.rares, ns.db.recipeBook = nil, nil
    pump(6)
    reset()
    check(W.prefixes.ZodUI and G.enabled and Bus.On(), "on, in a guild, with its own prefix")

    -- who runs ZodUI
    hear("1~H~9.99.0", "Bob-Forever")
    check(printed("a newer ZodUI (9.99.0) runs in your guild; you have " .. ns.version), "a newer version in the guild is said")
    reset()
    hear("1~H~9.99.0", "Ann-Forever")
    check(not printed("newer ZodUI"), "once")
    hear("2~H~9.9.9", "Cid-Forever")
    hear("1~H~0.1.0", "Zod-Forever")
    hear("1~H~0.30.0", "Stranger-Elsewhere", "WHISPER")
    check(#G:Members() == 2, "another protocol, your own messages and a whispered hello nobody asked for are ignored")
    slash("guild list")
    check(printed("2 in your guild run ZodUI:") and printed("[Ann]") and printed("9.99.0"), "/zod guild list")
    reset()
    slash("guild")
    local p = sent("1~P")
    check(#p == 1 and p[1][3] == "GUILD", "/zod guild asks the guild")
    hear("1~P", "Dan-Forever")
    local h = sent("1~H~")
    check(#h == 1 and h[1][2] == "1~H~" .. ns.version and h[1][3] == "WHISPER" and h[1][4] == "Dan-Forever", "asked, it whispers its version back")
    hear("1~H~0.31.0", "Eve-Forever", "WHISPER")
    check(#G:Members() == 4, "and takes the whispered answers after it asked")

    -- rares you see
    reset()
    W.units = { target = "Ironbark" }
    W.classes = { target = "rareelite" }
    W.guids = { target = "Creature-0-1-0-1-5234-0000AB" }
    fire("PLAYER_TARGET_CHANGED")
    local r = sent("1~R~")
    check(#r == 1 and r[1][2] == "1~R~5234~Ironbark~1424~621~205~0~rareelite" and r[1][3] == "GUILD",
        "a rare you target is told to the guild: " .. tostring(r[1] and r[1][2]))
    fire("PLAYER_TARGET_CHANGED")
    W.units.mouseover, W.classes.mouseover, W.guids.mouseover = "Ironbark", "rareelite", W.guids.target
    fire("UPDATE_MOUSEOVER_UNIT")
    check(#sent("1~R~") == 1, "once, not each time you look at it")
    W.deadUnits = { target = true }
    fire("PLAYER_TARGET_CHANGED")
    r = sent("1~R~")
    check(#r == 2 and r[2][2]:find("~1~rareelite$") ~= nil, "and again when it is dead")
    W.deadUnits = nil
    W.classes, W.guids.target = { target = "elite" }, "Creature-0-1-0-1-999-0000AC"
    fire("PLAYER_TARGET_CHANGED")
    W.classes, W.players = { target = "rare" }, { target = true }
    fire("PLAYER_TARGET_CHANGED")
    W.players = nil
    G.db.rares = false
    fire("PLAYER_TARGET_CHANGED")
    G.db.rares = true
    check(#sent("1~R~") == 2, "not an ordinary elite, not a player, and not with telling off")

    -- rares the guild sees
    reset()
    hear("1~R~777~Old Vicejaw~1424~455~602~0~rare", "Bob-Forever")
    check(printed("Rare: Old Vicejaw, Bob saw it near 45.5, 60.2."), "a guild member's rare in your zone is a notice")
    check(ns.db.rares[1].name == "Old Vicejaw" and ns.db.rares[1].by == "Bob", "and kept")
    reset()
    hear("1~R~777~Old Vicejaw~1424~455~602~0~rare", "Ann-Forever")
    check(not printed("Old Vicejaw"), "the same rare told twice is said once")
    hear("1~R~888~Far Away~1430~100~100~0~worldboss", "Bob-Forever")
    check(not printed("Far Away") and ns.db.rares[1].name == "Far Away", "another zone's is only kept")
    hear("1~R~abc~Bad~1424~5000~1~0~rare", "Bob-Forever")
    hear("1~R~999~Whispered~1424~455~602~0~rare", "Bob-Forever", "WHISPER")
    hear("1~R~998~|cffff0000Red~1424~455~602~0~rare", "Ann-Forever")
    check(ns.db.rares[2].name == "Far Away" and ns.db.rares[1].name == "cffff0000Red", "bad fields are dropped, whispers do not count, codes are taken out")
    hear("1~R~777~Old Vicejaw~1424~455~602~1~rare", "Bob-Forever")
    check(printed("Old Vicejaw was killed (Bob saw it)."), "and a kill in your zone is said")
    reset()
    slash("guild rares")
    check(printed("1. Old Vicejaw (killed)") and printed("3. Far Away") and printed("Map 1430 (10.0, 10.0), Bob"), "/zod guild rares lists them")
    reset()
    slash("guild way 3")
    local way
    for _, c in ipairs(W.calls) do if c[1] == "SetUserWaypoint" then way = c end end
    check(way and way[2] == 1430 and math.abs(way[3] - 0.1) < 1e-9 and called("SuperTrackWaypoint") == 1
        and printed("waypoint to Far Away in Map 1430 (10.0, 10.0)."), "/zod guild way sets a waypoint and tracks it")

    -- who else has a quest
    pump(6) -- the game lets a few messages out at once
    W.questLog = { { title = "The Defias Brotherhood", questID = 155, objectives = { { numFulfilled = 1, numRequired = 3 } } },
        { title = "Collecting Kelp", questID = 112, complete = true } }
    W.questTitles = { [155] = "The Defias Brotherhood", [112] = "Collecting Kelp" }
    reset()
    hear("1~Q~4242~155", "Bob-Forever")
    local q = sent("1~q~")
    check(#q == 1 and q[1][2] == "1~q~4242~155~" .. W.level .. "~1/3~Hillsbrad Foothills" and q[1][4] == "Bob-Forever",
        "asked about a quest you have, it whispers how far you are: " .. tostring(q[1] and q[1][2]))
    hear("1~Q~4243~112", "Bob-Forever")
    pump(2)
    check(#sent("1~q~") == 2 and sent("1~q~")[2][2]:find("~done~", 1, true), "a finished one says done")
    hear("1~Q~4244~999", "Bob-Forever")
    G.db.answer = false
    hear("1~Q~4245~155", "Bob-Forever")
    G.db.answer = true
    pump(6)
    check(#sent("1~q~") == 2, "nothing for a quest you do not have, or with answering off")
    reset()
    slash("guild quest defias")
    local ask = sent("1~Q~")
    local id = ask[1] and ask[1][2]:match("^1~Q~(%d+)~155$")
    check(id and printed("asking your guild who has The Defias Brotherhood"), "/zod guild quest finds it in your log by name and asks")
    slash("guild quest 155")
    check(printed("already asking about The Defias Brotherhood"), "not twice at once")
    id = id or "0"
    hear("1~q~" .. id .. "~155~22~done~Westfall", "Ann-Forever", "WHISPER")
    hear("1~q~" .. id .. "~155~25~2/3~Elwynn Forest", "Bob-Forever", "WHISPER")
    hear("1~q~" .. id .. "~155~25~2/3~Elwynn Forest", "Bob-Forever", "WHISPER")
    hear("1~q~99999~155~25~2/3~Elwynn Forest", "Cid-Forever", "WHISPER")
    hear("1~q~" .. id .. "~155~25~lots~Elwynn Forest", "Dan-Forever", "WHISPER")
    hear("1~q~" .. id .. "~155~25~1/3~Duskwood", "Fay-Forever", "GUILD")
    pump(5)
    local said = line("The Defias Brotherhood: ")
    local _, bobs = said:gsub("%[Bob%]", "")
    check(said:find("[Ann] (22, Westfall: done), ", 1, true) and said:find("[Bob] (25, Elwynn Forest: 2/3).", 1, true) and bobs == 1
        and not said:find("Cid") and not said:find("Dan") and not said:find("Fay"), "the answers, each once, only to this question: " .. said)
    reset()
    slash("guild quest nothing like it")
    check(printed("no quest in your log is called 'nothing like it'."), "a quest not in your log")
    reset()
    W.groupQuests = { [155] = 5 }
    fire("QUEST_ACCEPTED", 155)
    fire("QUEST_ACCEPTED", 112)
    check(#sent("1~Q~") == 1, "taking a group quest asks by itself, an ordinary one does not")
    pump(5)
    check(not printed("no one in your guild"), "and says nothing when no one else has it")
    W.groupQuests = nil

    -- recipes, with Guild crafters
    pump(6) -- the game lets a few messages out at once
    reset()
    W.recipes, W.recipeIDs = { [3915] = { name = "Brown Linen Shirt" }, [2963] = { name = "Bolt of Linen Cloth", learned = false } }, { 3915, 2963 }
    fire("TRADE_SKILL_SHOW")
    fire("TRADE_SKILL_LIST_UPDATE")
    pump(1)
    local book = ns.db.recipeBook and ns.db.recipeBook["Zod-Forever"]
    check(book and book.known[3915] and not book.known[2963] and book.guild == "Forever Friends", "an open profession window keeps what you have learned")
    W.linkedSkill, W.recipeIDs, W.recipes[1] = true, { 1 }, { name = "Linked" }
    fire("TRADE_SKILL_SHOW")
    pump(1)
    W.linkedSkill = nil
    check(book and not book.known[1], "not a linked window's recipes")
    ns.db.recipeBook["Mira-Forever"] = { name = "Mira", guild = "Forever Friends", known = { [3915] = true }, at = W.clock }
    ns.db.recipeBook["Far-Forever"] = { name = "Far", guild = "Another Guild", known = { [3915] = true }, at = W.clock }
    check(table.concat(C.Mine(3915), ",") == "Zod,Mira", "your characters in this guild who know it, you first: " .. table.concat(C.Mine(3915), ","))
    reset()
    hear("1~C~5151~3915", "Bob-Forever")
    local c = sent("1~c~")
    check(#c == 1 and c[1][2] == "1~c~5151~3915~Zod,Mira" and c[1][4] == "Bob-Forever", "asked about a recipe, it whispers your characters who know it")
    hear("1~C~5152~1234", "Bob-Forever")
    check(#sent("1~c~") == 1, "nothing for a recipe none of them knows")
    reset()
    slash("crafters 3915 tailoring")
    check(printed("your characters who know Brown Linen Shirt: Zod, Mira."), "your own characters are said at once")
    local cid = sent("1~C~")[1] and sent("1~C~")[1][2]:match("^1~C~(%d+)~3915$")
    check(cid ~= nil, "and the guild's ZodUI is asked")
    hear("1~c~" .. (cid or "0") .. "~3915~Kim,Le|cffe,Bob", "Bob-Forever", "WHISPER")
    hear("1~c~" .. (cid or "0") .. "~3915~Joe", "Joe-Forever", "GUILD")
    pump(6)
    said = line("Brown Linen Shirt, from ZodUI in your guild: ")
    check(said:find("[Bob] (alts: Kim, Lecffe).", 1, true) and not said:find("Joe"), "the answers, with alts, whispers only: " .. said)
    W.recipes, W.recipeIDs = nil, nil

    local errors = #ns.errors
    for _, text in ipairs({ "1~H", "1~P~x~y", "1~R", "1~R~1", "1~Q", "1~q", "1~C", "1~c", "1~Z~1", "1", "", "~~~~" }) do
        hear(text, "Odd-Forever")
        hear(text, "Odd-Forever", "WHISPER")
    end
    check(#ns.errors == errors, "messages with fields missing are dropped without an error")

    -- sending: combat, the chat lockdown, the game's throttle, switched off
    reset()
    W.combat = true
    slash("guild")
    check(#sent("1~P") == 0 and Bus.Queued() == 1, "in combat a message waits")
    W.combat = false
    fire("PLAYER_REGEN_ENABLED")
    check(#sent("1~P") == 1 and Bus.Queued() == 0, "and goes out after")
    W.chatLockdown = true
    reset()
    pump(6)
    Bus.Send("H", { "x" })
    check(#sent("1~H~") == 0, "in the chat lockdown it waits")
    W.chatLockdown = false
    pump(1.3)
    check(#sent("1~H~") == 1, "and goes out after")
    reset()
    pump(6)
    for i = 1, 8 do Bus.Send("H", { "x" .. i }) end
    check(#sent("1~H~") == 4, "a burst of four, the rest wait: " .. #sent("1~H~"))
    pump(6)
    check(#sent("1~H~") == 8, "and go out one by one")
    pump(6)
    reset()
    Bus.Send("H", { string.rep("a", 300) .. "~|x" })
    local long = sent("1~H~")[1]
    check(long and long[2] == "1~H~" .. string.rep("a", 80), "a field is cut short and cleaned")
    pump(6)
    G:Disable()
    reset()
    hear("1~H~0.90.0", "Gus-Forever")
    W.classes, W.guids.target = { target = "rare" }, "Creature-0-1-0-1-4444-0000AD"
    fire("PLAYER_TARGET_CHANGED")
    check(not Bus.On() and not printed("0.90.0") and #sent("1~") == 0, "switched off it neither hears nor sends")
    G:Enable()

    W.guild, W.name, W.units, W.guids, W.questLog = saved.guild, saved.name, saved.units, saved.guids, saved.questLog
    W.classes, W.questTitles = nil, nil
    ns.db.rares, ns.db.recipeBook = nil, nil
end

---------------------------------------------------------------------------
say("--- a failing module does not take the others down")
reset()
ns.modules.gold.Card = function() error("boom") end
slash("home")
check(#ns.errors == 1 and has("Could not be shown"), "the broken card is replaced by a notice")
check(has("Session", ZodUIFrame) and has("To do", ZodUIFrame), "the other cards still draw")
check(printed("gold card failed"), "the failure is said once in chat")
slash("errors")
check(printed("boom"), "/zod errors shows what went wrong")

---------------------------------------------------------------------------
say("--- quest items")
do
    local Q, vendor = ns.modules.questitems, ns.modules.vendor
    local name, have, need = Q.ParseObjective("Linen Cloth: 3/10")
    check(name == "Linen Cloth" and have == 3 and need == 10, "reads 'Linen Cloth: 3/10'")
    name, have, need = Q.ParseObjective("3/10 Toile de lin")
    check(name == "Toile de lin" and have == 3 and need == 10, "and '3/10 Toile de lin'")
    check(Q.ParseObjective("Kill the kobolds") == nil and Q.ParseObjective(nil) == nil, "and nothing from text without a count")

    local savedRoute, savedLog = UndeadRoute, W.questLog
    UndeadRoute = nil
    W.questLog = {
        { title = "Kobold Trouble", questID = 31, objectives = {
            { type = "item", text = "Item 881: 2/5", numFulfilled = 2, numRequired = 5 },
            { type = "monster", text = "Kobold Miner: 0/8" } } },
        { title = "Old Bones", questID = 32, complete = true, objectives = { { type = "item", text = "Item 882: 1/1", finished = true } } },
        { title = "Zone", isHeader = true },
    }
    fire("QUEST_LOG_UPDATE")
    W.bags[0][11] = { id = 881, quality = 1, count = 2, price = 100 }
    W.bags[0][12] = { id = 882, quality = 0, count = 1, price = 50 }
    W.bags[0][13] = { id = 883, quality = 0, count = 1, price = 70 }
    vendor.db.sell[881] = true
    reset()
    W.merchant = true
    fire("MERCHANT_SHOW")
    pump(1)
    check(W.bags[0][11] and W.bags[0][12] and W.bags[0][13] == nil,
        "Vendor sells the grey item no quest wants, and neither the always-sold one nor the grey one quests ask for")
    check(printed("kept Item 881, Item 882: a quest needs them."), "and says what it kept")
    check(Q:For("kobold miner") == nil, "a kill objective is not an item")
    fire("MERCHANT_CLOSED")

    local lines = {}
    local tip = { AddLine = function(_, text) lines[#lines + 1] = text end }
    Q:ItemTooltip(tip, 881)
    check(lines[1] == "Needed for Kobold Trouble (2/5)", "the tooltip names the quest and the count: " .. tostring(lines[1]))

    -- Undead Route's class quests, before they are in the log.
    W.bags[0][14] = { id = 884, quality = 1, count = 1, price = 10 }
    UndeadRoute = { NeededItems = function() return { { name = "Item 884", quest = "A Moon-Kissed Blade", source = "Deadmines" }, "bad", { name = 5 } } end }
    fire("QUEST_LOG_UPDATE")
    lines = {}
    Q:ItemTooltip(tip, 884)
    check(lines[1] == "Needed later for A Moon-Kissed Blade", "Undead Route's items count, as needed later: " .. tostring(lines[1]))
    Q.db.route = false
    Q:OnOption("route")
    check(Q:For("Item 884") == nil, "unless that is switched off")
    Q.db.route = true
    UndeadRoute = { NeededItems = function() error("broken route") end }
    fire("QUEST_LOG_UPDATE")
    check(Q:For("Item 881") ~= nil, "a failing Undead Route leaves the log's items")

    Q.db.keep = false
    reset()
    W.merchant = true
    fire("MERCHANT_SHOW")
    pump(1)
    check(W.bags[0][11] == nil and W.bags[0][12] == nil, "with keeping off, Vendor sells them as before")
    fire("MERCHANT_CLOSED")
    Q.db.keep = true
    W.merchant = false
    vendor.db.sell[881] = nil
    W.bags[0][11], W.bags[0][12], W.bags[0][13], W.bags[0][14] = nil, nil, nil, nil
    UndeadRoute, W.questLog = savedRoute, savedLog
    fire("QUEST_LOG_UPDATE")
end

---------------------------------------------------------------------------
say("--- chat ads: what a line is")
do
    local cases = {
        { "WTS Mage portal from Thunder Bluff to Undercity for 50s. /w me inv", "service" },
        { "WTB portal TB to UC", "buy" },
        { "GET YOUR [Enchanting] - [Enchanting: Enchant Weapon - Fiery Weapon]", "service" },
        { "LF enchanter with [Enchanting: Enchant Weapon - Fiery Weapon] in org", "buy" },
        { "WTS [Tough Scorpid Breastplate] 4g each! am in orgrimmar", "sell" },
        { "[Blacksmithing] 300 LFW [Lionheart Helm] AVAILABLE", "service" },
        { "Rogue with lockpicking 225 opening for free <3 tip always apreciated", "service" },
        { "WTB STRONG IRON LOCKBOXES for 50S EACH", "buy" },
        { "LF1M TANK SFK", "group", "more", "sfk", "tank" },
        { "tank and heal for blackfathom deeps ?", "group", "more", "bfd" },
        { "LFM [[17D] Deviate Hides] OUT OF WC", "group", "more", "wc" },
        { "Any groups for WC?", "group", "group", "wc" },
        { "lfg Razorfen downs hunter lvl362", "group", "group", "rfd" },
        { "Looking for a long-term home? <AMANDLA> is recruiting, join our Discord", nil },
        { "its not free when begging for tip", nil },
        { "Any Tauren with TB's quest for ragefire ?", nil },
        { "just tank", nil },
    }
    for _, c in ipairs(cases) do
        local ad = ns.Ads.Parse(c[1], 26)
        local ok = (ad and ad.kind) == c[2]
        if ok and c[3] then ok = ad.lf == c[3] end
        if ok and c[4] then ok = ad.dungeons[1] and ad.dungeons[1].key == c[4] end
        if ok and c[5] then ok = ad.roles[c[5]] == true end
        check(ok, c[1] .. " -> " .. tostring(c[2]) .. ", got " .. tostring(ad and ad.kind) .. " " .. tostring(ad and ad.lf))
    end
    check(ns.Ads.Parse("lf dm tank", 20).dungeons[1].key == "vc" and ns.Ads.Parse("lf dm tank", 58).dungeons[1].key == "dm",
        "DM is the Deadmines at 20 and Dire Maul at 58")
    check(ns.Ads.Parse(nil) == nil and ns.Ads.Parse("") == nil, "nothing from nothing")
end

---------------------------------------------------------------------------
say("--- chat board")
do
    local B = ns.modules.board
    for i = #B.ads, 1, -1 do B.ads[i] = nil end
    local function say3(text, who) fire("CHAT_MSG_CHANNEL", text, who, "", "3. Trade - City", who, "", 2, 3, "Trade - City") end
    say3("WTS [Tough Scorpid Breastplate] 4g each!", "Elle-Realm")
    say3("WTB portal TB to UC", "Melkor-Realm")
    say3("hello there", "Chatty-Realm")
    say3("WTS [Tough Scorpid Breastplate] 4g each!", "Elle-Realm")
    fire("CHAT_MSG_CHANNEL", "WTS my stuff", "Custom-Realm", "", "5. mychannel", "Custom-Realm", "", 0, 5, "mychannel")
    check(#B.ads == 2 and B.ads[1].author == "Elle-Realm" and B.ads[1].count == 2, "ads are kept, chatter and custom channels are not, and a repeat counts")
    slash("board")
    local page = ns.pages.board
    check(page.frame:IsVisible() and has("Selling") and has("Buying") and has("(x2)"), "the page lists them with their kind")
    click("Buying")
    check(not has("Tough Scorpid") and has("WTB portal"), "a filter shows one kind")
    click("All")
    page.search.edit:SetText("scorpid")
    page:Refresh()
    check(has("Tough Scorpid") and not has("WTB portal"), "the search finds words")
    page.search.edit:SetText("")
    page:Refresh()
    reset()
    page.list.onClick(B.ads[1])
    check(called("SendTell", "Elle") == 1, "a click whispers the author")
    searchFor("scorpid")
    check(has("Chat ad"), "Search finds ads")
    searchFor("")
    B.ads[2].at = time() - 2 * 3600
    check(#B:List() == 1, "old ads are left out")
    -- Service ads are kept for days.
    ns.db.services = {}
    say3("GET YOUR [Enchanting] - [Enchanting: Enchant Weapon - Crusader] your mats", "Dotts-Realm")
    say3("GET YOUR [Enchanting] - [Enchanting: Enchant Weapon - Crusader] your mats", "Dotts-Realm")
    check(#ns.db.services == 1 and ns.db.services[1].author == "Dotts-Realm", "a service ad is kept, once")
    ns.db.services[1].at = time() - 3 * 86400
    reset()
    slash("board crusader")
    check(printed("offered 'crusader':") and printed("Dotts") and printed(", 3d ago:"), "/zod board crusader finds it days later")
    reset()
    slash("board mongoose")
    check(printed("no one offered 'mongoose'"), "and says when no one did")
    slash("board")
    click("Kept")
    check(has("Crusader"), "the Kept filter shows them")
    ns.db.services[1].at = time() - 20 * 86400
    check(#B:Services("") == 0 and #ns.db.services == 0, "and drops them after two weeks")
end

---------------------------------------------------------------------------
say("--- group match")
do
    local G = ns.modules.groups
    G.Forget()
    local function say1(text, who) fire("CHAT_MSG_CHANNEL", text, who, "", "1. General", who, "", 1, 1, "General") end
    reset()
    say1("LF1M TANK SFK", "Malvador-Realm")
    check(not printed("looks for"), "a tank wanted is not for a damage dealer")
    G.db.tank = true
    say1("LF1M TANK SFK", "Malvador-Realm")
    check(printed("Malvador looks for a tank for Shadowfang Keep.") and printed("[Malvador]"), "but is for a tank, with a link to whisper")
    reset()
    say1("LF1M TANK SFK", "Malvador-Realm")
    check(not printed("looks for"), "not twice")
    pump(25)
    say1("LFM WC", "Ciri-Realm")
    check(not printed("looks for"), "a dungeon below your level is not")
    say1("LFM RFD", "Downs-Realm")
    check(not printed("looks for"), "nor one far above")
    say1("tank and heal for blackfathom deeps ?", "Svit-Realm")
    check(printed("Svit looks for a tank for Blackfathom Deeps."), "a group naming your role among others is")
    pump(25)
    reset()
    W.party = { Bob = true }
    say1("LFM BFD", "Other-Realm")
    check(not printed("looks for"), "not while you are in a group")
    W.party = {}
    say1("lfg BFD warrior", "Wanting-Realm")
    check(not printed("looks for"), "nor for someone who wants a group himself")
    say1("LFM BFD", "Other-Realm")
    check(printed("Other looks for more for Blackfathom Deeps."), "a group naming no role counts for every role")
    G.db.tank = false
    reset()
    slash("groups test")
    check(printed("Sample looks for a dps for"), "/zod groups test shows a sample")
    G.Forget()

    -- Keep my group role: another addon makes you a healer, ZodUI puts the role you tick back.
    local set = {}
    UnitSetRole = function(unit, role) set[#set + 1] = role W.role = role return true end
    W.party = { Bob = true }
    W.role = "HEALER"
    reset()
    fire("PLAYER_ROLES_ASSIGNED")
    check(#set == 0, "the role is not put back at once")
    pump(3)
    check(set[1] == "DAMAGER" and W.role == "DAMAGER", "a role another addon set is put back to the one ticked")
    check(printed("your group role was set to Healer") and printed("it is Damage again"), "and it says so")
    reset()
    W.role = "HEALER"
    fire("PLAYER_ROLES_ASSIGNED") pump(3)
    check(W.role == "DAMAGER" and not printed("your group role"), "once said, not again in the same group")
    W.combat = true
    W.role = "HEALER"
    fire("PLAYER_ROLES_ASSIGNED") pump(3)
    check(W.role == "HEALER", "not in a fight")
    W.combat = false
    fire("PLAYER_REGEN_ENABLED") pump(3)
    check(W.role == "DAMAGER", "but after it")
    -- Something that fights back: it gives up and says so.
    reset()
    for _ = 1, 6 do W.role = "HEALER" fire("PLAYER_ROLES_ASSIGNED") pump(3) end
    check(W.role == "HEALER" and printed("keeps changing your group role"), "a fight over the role ends with ZodUI giving up")
    G.Forget()
    G.db.tank = true
    check(G:WantedRole() == nil, "two roles ticked: Auto keeps none")
    G.db.keep = "tank"
    check(G:WantedRole() == "TANK", "a role chosen outright is kept")
    G.db.keep, G.db.tank = "off", false
    W.role = "HEALER"
    fire("PLAYER_ROLES_ASSIGNED") pump(3)
    check(W.role == "HEALER" and G:WantedRole() == nil, "Off leaves the role alone")
    W.role = "secret role" W.secret = "secret role"
    G.db.keep = "auto"
    check(pcall(G.KeepRole, G), "a secret role does not error")
    W.secret = nil
    G.Forget()
    W.party, W.role, UnitSetRole = {}, nil, nil
end

---------------------------------------------------------------------------
say("--- recap")
do
    local R = ns.modules.recap
    local monday = R.WeekStart()
    check(date("%w", monday) == "1" and date("%H%M%S", monday) == "000000" and monday <= time() and time() - monday < 7 * 86400,
        "the week starts on Monday at midnight: " .. date("%Y-%m-%d %H:%M", monday))
    local savedDays, savedRuns, savedFinds = ns.chardb.history.days, ns.chardb.runs, ns.chardb.finds
    local savedRoute, savedRecap = UndeadRoute, ns.chardb.recap
    ns.chardb.history.days = {
        [date("%Y-%m-%d", monday - 6 * 86400 + 43200)] = { played = 7200, xp = 50000, quests = 12, levels = 1, gold = 15000, deaths = 1 },
        [date("%Y-%m-%d", monday - 86400 + 43200)] = { played = 3600, xp = 20000, quests = 3, levels = 0, gold = -500, deaths = 0 },
        [date("%Y-%m-%d", monday - 8 * 86400 + 43200)] = { played = 99999, xp = 99999, quests = 99, levels = 9, gold = 0, deaths = 9 },
    }
    ns.chardb.runs = { list = { { name = "Shadowfang Keep", at = monday - 3 * 86400 }, { name = "Old", at = monday - 9 * 86400 } } }
    ns.chardb.finds = { { at = monday - 2 * 86400, name = "Thunderfury", q = 5 }, { at = monday - 2 * 86400, name = "Linen", q = 1 } }
    local text = R:LastWeek()
    check(text == "Last week: 3h played, 70,000 XP, +1 level, 15 quests, 1 dungeon, +1g 45s, 1 death. Best finds: Thunderfury.",
        "last week, from Monday to Sunday only: " .. tostring(text))
    check(R:ThisWeek() == nil, "a week with nothing played says nothing")

    W.zone, W.subzone = "Ashenvale", "Zoram'gar Outpost"
    fire("PLAYER_LOGOUT")
    check(ns.chardb.recap.stop.zone == "Ashenvale", "logout keeps where you stopped")
    ns.chardb.recap.stop.at = time() - 7200
    UndeadRoute = { Status = function() return { ready = 3, next = "Pick up: Seeking the Kor Gem" } end }
    local lines = R:Waiting()
    local all = table.concat(lines, " | ")
    check(all:find("You stopped in Ashenvale, Zoram'gar Outpost, 2h ago.", 1, true) and all:find("3 quests are ready to hand in.", 1, true)
        and all:find("Next on the route: Pick up: Seeking the Kor Gem.", 1, true), "what waits: " .. all)

    reset()
    ns.chardb.recap.week = nil
    R.started = nil
    R:OnEnable()
    pump(10)
    check(printed("Last week: 3h played") and printed("since last time:") and printed("3 quests are ready to hand in."),
        "the first login of a week tells last week, and coming back tells what waits")
    reset()
    R.started = nil
    R:OnEnable()
    pump(10)
    check(not printed("Last week:"), "the week is told once")

    reset()
    W.guild = true
    slash("recap guild")
    local said
    for _, c in ipairs(W.calls) do
        if c[1] == "SendChatMessage" and c[3] == "GUILD" then said = c[2] end
    end
    check(said and said:find("Last week: 3h played", 1, true), "/zod recap guild says it in guild chat")

    ns.chardb.history.days, ns.chardb.runs, ns.chardb.finds = savedDays, savedRuns, savedFinds
    UndeadRoute, ns.chardb.recap = savedRoute, savedRecap
end

---------------------------------------------------------------------------
say("--- hand-me-downs")
do
    local H = ns.modules.handouts
    check(H.CanWear("WARRIOR", 30, 4, 4) == false and H.CanWear("WARRIOR", 40, 4, 4) == true, "plate opens to a warrior at 40")
    check(H.CanWear("MAGE", 30, 4, 2) == false and H.CanWear("MAGE", 30, 4, 1) and H.CanWear("MAGE", 30, 2, 19)
        and not H.CanWear("MAGE", 30, 2, 1), "a mage wears cloth and wands, not leather or axes")
    -- Item 901 a blue BoE leather chest with 10 agility, 902 the alt's chest with 4 agility.
    local saved = { C_Item.GetItemInfo, C_Item.GetItemStats, C_Item.GetItemInfoInstant, ForeverLevelingBiS_API, ns.db.chars }
    local STATS = { [901] = { ITEM_MOD_AGILITY_SHORT = 10 }, [902] = { ITEM_MOD_AGILITY_SHORT = 4 }, [903] = { ITEM_MOD_INTELLECT_SHORT = 20 } }
    local function id(link) return tonumber(tostring(link):match("item:(%d+)")) end
    C_Item.GetItemStats = function(link) return STATS[id(link)] end
    C_Item.GetItemInfoInstant = function(link) return id(link), "Armor", "Leather", "INVTYPE_CHEST", 1, 4, 2 end
    C_Item.GetItemInfo = function(link)
        local n = id(link)
        if not n then return nil end
        return "Item " .. n, "item:" .. n, 3, 25, 20, "Armor", "Leather", 1, "INVTYPE_CHEST", 1, 100, 4, 2, 2
    end
    ForeverLevelingBiS_API = { GetWeights = function(class) return class == "ROGUE" and { agi = 1 } or { int = 1 } end,
        GetGain = function() return 0 end }
    local me = ns.char
    me.faction = "Horde"
    ns.db.chars = { [ns.charKey] = me,
        ["Stab-" .. me.realm] = { name = "Stab", realm = me.realm, class = "ROGUE", className = "Rogue", level = 22, faction = "Horde", gear = { [5] = "item:902" } },
        ["Mage-" .. me.realm] = { name = "Mage", realm = me.realm, class = "MAGE", level = 30, faction = "Horde", gear = {} },
        ["Ally-" .. me.realm] = { name = "Ally", realm = me.realm, class = "ROGUE", level = 22, faction = "Alliance", gear = {} },
        ["Far-Other"] = { name = "Far", realm = "Other", class = "ROGUE", level = 22, gear = {} } }
    check(H:Gain(ns.db.chars["Stab-" .. me.realm], "item:901") == 150, "10 agility over 4 is +150% for the rogue")
    check(H:Gain(ns.db.chars["Mage-" .. me.realm], "item:901") == nil, "a mage cannot wear leather")
    local char, pct = H:For("item:901")
    check(char and char.name == "Stab" and pct == 150, "the rogue on this realm and side gets it, not one on the other side or realm")

    ns.db.handouts = {}
    W.bags[0][15] = { id = 901, quality = 3, count = 1, price = 100 }
    reset()
    fire("CHAT_MSG_LOOT", "You receive loot: |cff0070dd|Hitem:901::::::::25:::::|h[Item 901]|h|r.", "", "", "", "Zod")
    pump(2)
    check(printed("Hand-me-down:") and printed("is +150% for Stab (Rogue 22)."), "looting it says whom it is for")
    check(#ns.db.handouts == 1 and ns.db.handouts[1].to == "Stab", "and keeps it on the list")
    local lines = {}
    H:ItemTooltip({ AddLine = function(_, t) lines[#lines + 1] = t end }, 901)
    check(lines[1] == "Hand-me-down for Stab", "its tooltip names the character")
    reset()
    fire("MAIL_SHOW")
    check(printed("to mail to your characters:") and printed("-> Stab"), "the mailbox reminds you")
    fire("MAIL_CLOSED")
    ForeverLevelingBiS_API.GetGain = function() return 3 end
    ns.db.handouts = {}
    reset()
    fire("CHAT_MSG_LOOT", "You receive loot: |cff0070dd|Hitem:901::::::::25:::::|h[Item 901]|h|r.", "", "", "", "Zod")
    pump(2)
    check(#ns.db.handouts == 0 and not printed("Hand-me-down"), "an upgrade for you is yours")
    ForeverLevelingBiS_API = nil
    check(H:For("item:901") == nil, "without Forever Leveling BiS nothing is said")

    W.bags[0][15] = nil
    C_Item.GetItemInfo, C_Item.GetItemStats, C_Item.GetItemInfoInstant, ForeverLevelingBiS_API, ns.db.chars =
        saved[1], saved[2], saved[3], saved[4], saved[5]
    ns.db.handouts = {}
end

---------------------------------------------------------------------------
say("--- milestones")
do
    local MS = ns.modules.milestones
    pump(3) -- a check still waiting from the loot of the tests before must not land in the quiet first one
    local savedDone, savedFinds = ns.chardb.milestones, ns.chardb.finds
    ns.chardb.milestones = nil
    ns.chardb.finds = {}
    reset()
    MS:OnEnable()
    pump(13)
    check(ns.chardb.milestones.level10 and ns.chardb.milestones.level20 and not printed("Milestone:"),
        "what was reached before the module ran is marked quietly")
    check(not ns.chardb.milestones.purple, "and what was not, is not")
    reset()
    table.insert(ns.chardb.finds, 1, { at = time(), name = "Thunderfury", q = 5 })
    fire("CHAT_MSG_LOOT", "You receive loot: |cffff8000|Hitem:19019::::::::60:::::|h[Thunderfury]|h|r.", "", "", "", "Zod")
    pump(3)
    check(printed("Milestone: Something purple. Find a purple item.") and printed("Milestone: Something blue."), "a new one is said once it is reached")
    reset()
    fire("PLAYER_MONEY")
    pump(3)
    check(not printed("Something purple"), "and only once")
    slash("milestones")
    check(ns.pages.milestones.frame:IsVisible() and has("milestones reached") and has(" / 5"), "the page lists them with progress")
    ns.chardb.milestones, ns.chardb.finds = savedDone, savedFinds
end

---------------------------------------------------------------------------
say("--- guild leaderboard")
do
    local savedGuild = W.guild
    W.guild = true
    pump(10)
    local function sent(start)
        local out = {}
        for _, c in ipairs(W.calls) do
            if c[1] == "SendAddonMessage" and c[2]:sub(1, #start) == start then out[#out + 1] = c end
        end
        return out
    end
    local function hear(text, from, channel)
        fire("CHAT_MSG_ADDON", "ZodUI", text, channel or "GUILD", from, "Zod", 0, 0, "", 0)
    end
    reset()
    hear("1~W~424242", "Bob-Forever")
    pump(2)
    local answer = sent("1~w~424242~")
    check(#answer == 1 and answer[1][3] == "WHISPER" and answer[1][4] == "Bob-Forever", "asked, it whispers this week's numbers back")
    reset()
    hear("1~W~not a number", "Bob-Forever")
    pump(2)
    check(#sent("1~w~") == 0, "a malformed question gets no answer")

    reset()
    slash("top")
    pump(1)
    local ask = sent("1~W~")
    check(#ask == 1 and ask[1][3] == "GUILD", "/zod top asks the guild")
    local id = ask[1] and ask[1][2]:match("^1~W~(%d+)$")
    hear("1~w~" .. tostring(id) .. "~30~4~55~3~2~7200", "Ann-Forever", "WHISPER")
    hear("1~w~" .. tostring(id) .. "~30~99~55~3~2~7200", "Ann-Forever", "WHISPER")
    hear("1~w~999~30~5~5~5~5~5", "Eve-Forever", "WHISPER")
    hear("1~w~" .. tostring(id) .. "~x~1~1~1~1~1", "Bad-Forever", "WHISPER")
    pump(5)
    check(printed("this week in your guild (2 players with ZodUI):") and printed("Levels: 1. Ann 4") and printed("Quests: 1. Ann 55"),
        "the answers are ranked, once per player, and only answers to this question count")
    reset()
    slash("top")
    check(printed("asked a moment ago"), "not more than once a minute")
    W.guild = savedGuild
end

---------------------------------------------------------------------------
say("--- dungeon prep")
do
    local P = ns.modules.prep
    P.Forget()
    local saved = { instance = W.instance, log = W.questLog, party = W.party }
    local function sent(start)
        local out = {}
        for _, c in ipairs(W.calls) do
            if c[1] == "SendAddonMessage" and c[2]:sub(1, #start) == start then out[#out + 1] = c end
        end
        return out
    end
    check(P.Dungeon("Shadowfang Keep").key == "sfk" and P.Dungeon("sfk").key == "sfk" and P.Dungeon("Deadmines").key == "vc"
        and P.Dungeon("Scarlet Monastery Library").key == "sm" and P.Dungeon("Elwynn Forest") == nil, "dungeons are known by name and short name")
    W.questLog = {
        { title = "Shadowfang Keep", isHeader = true },
        { title = "Arugal Must Die", questID = 1014 },
        { title = "Deathstalkers in Shadowfang", questID = 1098, complete = true },
        { title = "Hillsbrad Foothills", isHeader = true },
        { title = "Elsewhere", questID = 500 },
    }
    W.party = { Bob = true }
    W.instance = { "Shadowfang Keep", "party" }
    pump(6)
    reset()
    fire("PLAYER_ENTERING_WORLD")
    pump(4)
    local told = sent("1~D~sfk~")
    check(#told == 1 and told[1][2] == "1~D~sfk~1014~1098" and told[1][3] == "PARTY", "entering, it tells the group its quest numbers")
    check(printed("Your quests for Shadowfang Keep: Arugal Must Die; Deathstalkers in Shadowfang (done)."), "and lists your quests for the dungeon")
    reset()
    fire("CHAT_MSG_ADDON", "ZodUI", "1~D~sfk~1014~1100", "PARTY", "Ann-Forever", "Zod", 0, 0, "", 0)
    fire("CHAT_MSG_ADDON", "ZodUI", "1~D~nowhere~1", "PARTY", "Eve-Forever", "Zod", 0, 0, "", 0)
    pump(2)
    check(#sent("1~D~sfk~") == 1, "someone new hears yours once")
    reset()
    slash("prep")
    check(printed("Arugal Must Die with Ann") and printed("Ann has 1 quest you lack: ask them to share.") and not printed("Eve"),
        "who has your quests, and what they have that you lack")
    reset()
    W.pushable = { [1014] = true }
    slash("prep share")
    check(called("QuestLogPushQuest") == 1 and printed("offered 1 quest to your group."), "/zod prep share offers the ones that can be shared")
    reset()
    slash("prep wc")
    check(printed("You have no quests for Wailing Caverns in your log."), "/zod prep wc looks at another dungeon")
    reset()
    W.instance = nil
    slash("prep")
    check(printed("you are not in a dungeon."), "outside a dungeon it says how to name one")
    W.instance, W.questLog, W.party, W.pushable = saved.instance, saved.log, saved.party, nil
    P.Forget()
end

---------------------------------------------------------------------------
say("--- travel")
do
    local TR, B = ns.modules.travel, ns.modules.board
    check(TR.City("tb") == "Thunder Bluff" and TR.City("uc") == "Undercity" and TR.City("ogri") == "Orgrimmar"
        and TR.City("nowhere") == nil, "cities are known by their short names")
    for i = #B.ads, 1, -1 do B.ads[i] = nil end
    local function say3(text, who) fire("CHAT_MSG_CHANNEL", text, who, "", "3. Trade", who, "", 2, 3, "Trade") end
    say3("WTS Mage portal from Thunder Bluff to Undercity for 50s. /w me inv", "Manda-Realm")
    say3("WTS Portal From Org To TB and UC 50s /w inv", "Noob-Realm")
    say3("WTS [Tough Scorpid Breastplate] 4g each!", "Elle-Realm")
    check(#TR:Portals() == 2 and #TR:Portals("Orgrimmar") == 1 and #TR:Portals("Stormwind") == 0, "portal offers, to one city or all")
    local savedBags, savedRoute = W.bags[0][16], UndeadRoute
    W.bags[0][16] = { id = 6948, quality = 1, count = 1 }
    UndeadRoute = { Status = function() return { stage = "Arathi Highlands", hub = "Hammerfall" } end }
    reset()
    slash("travel uc")
    check(printed("Hearthstone: Tarren Mill, ready.") and printed("Undead Route: Arathi Highlands, Hammerfall.")
        and printed("Portals to Undercity offered now:") and printed("Manda") and printed("Noob"), "/zod travel uc says all three")
    B.ads[1].at, B.ads[2].at, B.ads[3].at = time() - 3600, time() - 3600, time() - 3600
    reset()
    slash("travel")
    check(printed("No portal offered in chat in the last 15 minutes."), "old offers are not")
    reset()
    slash("travel mars")
    check(printed("no city called 'mars'"), "a city it does not know is said")
    W.bags[0][16], UndeadRoute = savedBags, savedRoute
    for i = #B.ads, 1, -1 do B.ads[i] = nil end
end

---------------------------------------------------------------------------
say("--- loot rules")
do
    local LR, R = ns.modules.lootrules, ns.modules.rolls
    LR.Forget()
    ns.db.lootBreaks = {}
    local savedParty, savedUnits, savedInfo = W.party, W.units, C_Item.GetItemInfo
    local BOE = "|cffa335ee|Hitem:905::::::::30:::::|h[Shiny Blade]|h|r"
    local BOP = "|cffa335ee|Hitem:906::::::::30:::::|h[Bound Blade]|h|r"
    C_Item.GetItemInfo = function(link)
        local id = tonumber(tostring(link):match("item:(%d+)"))
        if id == 905 or id == 906 then return "Blade", link, 4, 30, 25, "Weapon", "Sword", 1, "INVTYPE_WEAPON", 1, 100, 2, 7, id == 905 and 2 or 1 end
        return savedInfo(link)
    end
    reset()
    W.party = {}
    slash("rules")
    check(printed("you are not in a group. The rules would be: Loot rules:"), "outside a group it only shows them")
    R:Line(string.format(LOOT_ROLL_NEED, "Ann", BOE))
    check(#ns.db.lootBreaks == 0, "with no rules said, a Need is no one's business")

    W.party = { Ann = true }
    W.units = { party1 = "Ann" }
    reset()
    slash("rules")
    local said
    for _, c in ipairs(W.calls) do
        if c[1] == "SendChatMessage" and c[3] == "PARTY" then said = c[2] end
    end
    check(said == "Loot rules: Need only on what you will wear now. Bind on Equip items: Greed for everyone, no Need. Thanks!",
        "/zod rules says them in party chat: " .. tostring(said))
    reset()
    R:Line(string.format(LOOT_ROLL_NEED, "Ann", BOP))
    check(#ns.db.lootBreaks == 0, "Need on a Bind on Pickup item is fine")
    R:Line(string.format(LOOT_ROLL_NEED, "Ann", BOE))
    check(#ns.db.lootBreaks == 1 and ns.db.lootBreaks[1].name == "Ann" and printed("Ann rolled Need on")
        and printed("a Bind on Equip item, against the rules."), "Need on a Bind on Equip item is told and kept")
    reset()
    R:Line(string.format(LOOT_ROLL_NEED_SELF or "You have selected Need for: %s", BOE))
    check(#ns.db.lootBreaks == 1, "your own pick is not watched")

    -- Later, a new group with Ann.
    W.party = {}
    fire("GROUP_ROSTER_UPDATE")
    reset()
    W.party = { Ann = true }
    fire("GROUP_ROSTER_UPDATE")
    check(printed("Ann rolled Need on") and printed("against the rules, today."), "grouping with her again reminds you")
    reset()
    fire("GROUP_ROSTER_UPDATE")
    check(not printed("Ann rolled Need"), "once per group")
    reset()
    slash("rules log")
    check(printed("Need on Bind on Equip against the rules:") and printed("Ann"), "/zod rules log lists them")

    W.party, W.units, C_Item.GetItemInfo = savedParty, savedUnits, savedInfo
    LR.Forget()
    ns.db.lootBreaks = {}
end

---------------------------------------------------------------------------
say("--- group listings")
do
    local L, B, G = ns.modules.listings, ns.modules.board, ns.modules.groups
    L.Forget()
    G.Forget()
    for i = #B.ads, 1, -1 do B.ads[i] = nil end
    local saved = { party = W.party, heal = G.db.heal }
    pump(11)
    local id = W.channels.ZodUIGroups
    check(id ~= nil, "it joins the hidden channel")
    local function hear(text, who) fire("CHAT_MSG_CHANNEL", text, who, "", id .. ". ZodUIGroups", "", "", 0, id, "ZodUIGroups") end
    check(L.Decode("ZG1 sfk m th 24 3").dungeon.key == "sfk" and L.Decode("ZG1 nowhere m th 24 3") == nil
        and L.Decode("ZG1 sfk m th 999 3") == nil and L.Decode("hello") == nil and L.Decode("ZG1 sfk m |cff 24 3") == nil
        and L.Decode("ZG1 stop").stop, "lines are checked field by field")
    local hidden = false
    for _, f in ipairs(W.chatFilterList.CHAT_MSG_CHANNEL or {}) do
        if f(nil, "CHAT_MSG_CHANNEL", "ZG1 sfk m th 24 3", "Ann", "", id .. ". ZodUIGroups", "", "", 0, id, "ZodUIGroups") == true then hidden = true end
    end
    check(hidden, "its lines never show in a chat window")

    G.db.heal, W.party = true, {}
    reset()
    hear("ZG1 sfk m th 25 3", "Ann-Realm")
    check(#L:List() == 1 and B.ads[1].text == "LFM Shadowfang Keep (sfk) need tank heal, 3/5, level 25 [ZodUI, any layer]",
        "a listing lands on the Chat board: " .. tostring(B.ads[1] and B.ads[1].text))
    check(printed("Ann looks for a healer for Shadowfang Keep."), "and Group match tells you")
    hear("ZG1 sfk m t 25 4", "Ann-Realm")
    check(#L:List() == 1 and B.ads[1].text:find("4/5", 1, true), "posting again replaces it")
    hear("ZG1 bfd g h 26 1", "Bob-Realm")
    reset()
    slash("lfg")
    check(printed("group listings, every layer:") and printed("Ann") and printed("LFG Blackfathom Deeps (bfd) as heal, level 26"), "/zod lfg shows them")
    hear("ZG1 stop", "Ann-Realm")
    check(#L:List() == 1, "a stop takes it down")

    reset()
    slash("lfg sfk heal")
    local function sent()
        local out
        for _, c in ipairs(W.calls) do
            if c[1] == "SendChatMessage" and c[3] == "CHANNEL" then out = c end
        end
        return out
    end
    local level = UnitLevel("player")
    local s = sent()
    check(s and s[2] == "ZG1 sfk g h " .. level .. " 1" and s[4] == id, "out of a group it lists you: " .. tostring(s and s[2]))
    check(printed("listed you for Shadowfang Keep as heal on every layer for 15 minutes."), "and says so")
    reset()
    slash("lfg sfk")
    check(not sent() and printed("you listed a moment ago"), "not twice in half a minute")
    W.uptime = W.uptime + 31
    W.party = { Bob = true }
    reset()
    slash("lfg tank Blackfathom Deeps")
    s = sent()
    check(s and s[2]:find("^ZG1 bfd m t " .. level .. " ") and printed("listed your group for Blackfathom Deeps, needing tank"),
        "in a group it lists the group and what it needs")
    reset()
    slash("lfg mars")
    check(printed("no dungeon called 'mars'"), "an unknown dungeon is said")
    reset()
    slash("lfg stop")
    s = sent()
    check(s and s[2] == "ZG1 stop" and printed("your listing is taken down."), "/zod lfg stop")
    reset()
    slash("lfg stop")
    check(printed("you have nothing listed."), "and only once")

    W.uptime, W.chatLockdown = W.uptime + 31, true
    reset()
    slash("lfg sfk")
    check(not sent() and printed("chat is locked right now"), "not while chat is locked")
    W.chatLockdown = false
    W.channels.ZodUIGroups = nil
    reset()
    slash("lfg sfk")
    check(not sent() and printed("joining the group channel") and W.channels.ZodUIGroups, "out of the channel, it joins first")

    L:Disable()
    check(W.channels.ZodUIGroups == nil, "turned off, it leaves the channel")
    L:Enable()
    pump(11)
    check(W.channels.ZodUIGroups ~= nil, "and joins again when on")
    W.party, G.db.heal = saved.party, saved.heal
    for i = #B.ads, 1, -1 do B.ads[i] = nil end
    L.Forget()
    G.Forget()
end

---------------------------------------------------------------------------
say("--- healer mode")
do
    local H = ns.modules.healer
    H.Forget()
    ns.chardb.healer = nil
    local saved = { party = W.party, role = W.role, sets = W.sets }
    W.sets = { { name = "Shadow", equipped = true }, { name = "Heal" } }
    W.party, W.role = {}, "NONE"
    local function worn() return H.Worn() end

    reset()
    slash("healer set nothing")
    check(printed("no equipment set called 'nothing'. Your sets: Heal, Shadow."), "an unknown set is said, with your sets")
    slash("healer set heal")
    check(ns.chardb.healer.set == "Heal" and printed("your healing set is Heal."), "/zod healer set names it, in any case")

    -- A group that marks no role: a hint, no swap.
    reset()
    W.party = { Ann = true }
    fire("GROUP_ROSTER_UPDATE")
    pump(6)
    check(called("UseEquipmentSet") == 0 and printed("you have no role in this group. If you heal, /zod heal puts on Heal."),
        "with no role it hints once")
    reset()
    fire("GROUP_ROSTER_UPDATE")
    pump(6)
    check(not printed("no role"), "and not again in the same group")

    -- The group marks you healer.
    reset()
    W.role = "HEALER"
    fire("PLAYER_ROLES_ASSIGNED")
    check(worn() == "Heal" and printed("Healer mode: you heal in this group, Heal goes on."), "marked healer, the healing set goes on")
    reset()
    fire("GROUP_ROSTER_UPDATE")
    check(called("UseEquipmentSet") == 0, "more roster news changes nothing")

    -- Leaving puts back what you wore.
    reset()
    W.party, W.role = {}, "NONE"
    fire("GROUP_ROSTER_UPDATE")
    check(worn() == "Shadow" and printed("healer mode over, Shadow goes back on."), "leaving the group puts the old set back")

    -- In combat it waits.
    W.party, W.role, W.combat = { Ann = true }, "HEALER", true
    reset()
    fire("PLAYER_ROLES_ASSIGNED")
    check(worn() == "Shadow" and printed("Heal goes on when combat ends."), "in combat the swap waits")
    W.combat = false
    fire("PLAYER_REGEN_ENABLED")
    check(worn() == "Heal", "and happens when combat ends")

    -- A role change to damage ends it; by hand it stays until you leave.
    reset()
    W.role = "DAMAGER"
    fire("PLAYER_ROLES_ASSIGNED")
    check(worn() == "Shadow", "becoming damage puts the old set back")
    W.role = "NONE"
    reset()
    slash("heal")
    check(worn() == "Heal" and ns.chardb.healer.hand, "/zod heal swaps by hand")
    fire("GROUP_ROSTER_UPDATE")
    check(worn() == "Heal", "and a group with no roles keeps it")
    reset()
    slash("healer solo")
    check(worn() == "Shadow" and printed("healer mode over, Shadow goes back on."), "/zod healer solo puts it back")

    -- A set to go back to; logging out while healing.
    slash("healer back shadow")
    W.sets[1].equipped, W.sets[2].equipped = false, false
    W.sets[3] = { name = "Fishing", equipped = true }
    slash("heal")
    check(worn() == "Heal", "healing again")
    W.party = {}
    fire("PLAYER_ENTERING_WORLD")
    pump(4)
    check(worn() == "Shadow", "outside a group at the next login, the chosen set to go back to goes on")

    -- Remind only.
    H.db.swap = false
    W.party, W.role = { Ann = true }, "HEALER"
    reset()
    fire("PLAYER_ROLES_ASSIGNED")
    check(called("UseEquipmentSet") == 0 and printed("You heal in this group: put on Heal."), "with swapping off it only reminds")
    W.party, W.role = {}, "NONE"
    fire("GROUP_ROSTER_UPDATE")
    H.db.swap = true

    -- In every group; no set named.
    H.db.when = "always"
    ns.chardb.healer.set = nil
    W.party = { Ann = true }
    reset()
    fire("GROUP_ROSTER_UPDATE")
    check(called("UseEquipmentSet") == 0 and printed("Name your healing set with /zod healer set <name>"), "without a set it says how to name one")
    W.party = {}
    reset()
    fire("GROUP_ROSTER_UPDATE")
    check(called("UseEquipmentSet") == 0 and not printed("healer mode over"), "and leaving says nothing")
    H.db.when = "role"

    -- Specs, where the client has them.
    C_SpecializationInfo = {
        GetSpecialization = function() return 3 end,
        GetSpecializationInfo = function(i)
            local specs = { { 256, "Discipline", "HEALER" }, { 257, "Holy", "HEALER" }, { 258, "Shadow", "DAMAGER" } }
            local s = specs[i]
            if s then return s[1], s[2], "", 0, s[3] end
        end,
    }
    check(H.SpecHint() == "Your talents are not set for healing; Discipline is your healing spec.", "a healing spec is named")
    C_SpecializationInfo.GetSpecialization = function() return 2 end
    check(H.SpecHint() == nil, "and not when you already heal")
    C_SpecializationInfo = nil

    reset()
    slash("healer")
    check(printed("healing set: none, /zod healer set <name>; afterwards: Shadow.") and printed("Your sets: Fishing, Heal, Shadow."), "/zod healer tells the state")
    W.party, W.role, W.sets = saved.party, saved.role, saved.sets
    ns.chardb.healer = nil
    H.Forget()
end

---------------------------------------------------------------------------
say("--- dungeon guide")
do
    local G = ns.modules.guide
    local saved = { instance = W.instance, map = W.map, subzone = W.subzone }
    G.Forget()
    ns.chardb.guides, ns.chardb.guideWing, ns.db.guide = nil, nil, nil
    local function lines()
        local n = 0
        for _, f in ipairs(W.frames) do
            if f.kind == "Line" and f:IsVisible() and f.from and f.to then n = n + 1 end
        end
        return n
    end
    local function tile() return ZodUIGuide.tiles[1].texture end

    check(G.Lookup("sfk") == "sfk" and G.Lookup("Shadowfang") == "sfk" and G.Lookup("shadowfang keep") == "sfk"
        and G.Lookup("deadmines") == "vc" and G.Lookup("nowhere") == nil and G.Lookup("") == nil, "a guide is found by its key, a word or its name")
    -- every step that has a spot is on a floor the guide has, inside the map
    local ok = true
    for key, g in pairs(ns.GUIDES) do
        for _, s in ipairs(g.steps) do
            if s.x and not (g.floors[s.floor] and s.x >= 0 and s.x <= 1 and s.y >= 0 and s.y <= 1) then ok = false end
            for _, p in ipairs(s.via or {}) do
                if not (g.floors[p[1]] and p[2] >= 0 and p[2] <= 1 and p[3] >= 0 and p[3] <= 1) then ok = false end
            end
        end
    end
    local bends = 0
    for key, list in pairs(ns.GUIDE_TRACED or {}) do
        local g = ns.GUIDES[key]
        if not g then ok = false end
        for i, pts in pairs(list) do
            if not (g and g.steps[i]) then ok = false end
            for _, p in ipairs(pts) do
                bends = bends + 1
                if not (g and g.floors[p[1]] and p[2] >= 0 and p[2] <= 1 and p[3] >= 0 and p[3] <= 1) then ok = false end
            end
        end
    end
    check(ok and bends > 500, "the route data and its traced bends are on their floors and inside the map (" .. bends .. " bends)")

    check(G.Lookup("kraul") == "rfk" and G.ForLevel(23) == "sfk" and G.ForLevel(25) == "bfd" and G.ForLevel(31) == "rfk" and G.ForLevel(44) == "zf" and G.ForLevel(10) == "rfc",
        "outside, the guide that fits your level is picked, else the lowest")
    local _, listed = G.Names():gsub("/zod guide ", "")
    check(listed == 35 and G.Names():find("^Alcaz Prison %(/zod guide alcaz%), ") and G.Names():find("Zul'Farrak %(/zod guide zf%)$"), "the guides are listed by name")

    -- Outside a dungeon /zod guide shows the one for your level.
    local level = W.level
    W.level = 23
    W.instance, W.map, W.subzone = nil, 1424, ""
    ns.chardb.guideLast = nil -- never opened one yet
    reset()
    slash("guide")
    check(ZodUIGuide and ZodUIGuide:IsShown() and has("Shadowfang Keep", ZodUIGuide) and printed("here is Shadowfang Keep"),
        "/zod guide outside a dungeon shows Shadowfang Keep")
    check(ns.chardb.guideLast == "sfk", "the guide shown last is kept")
    ns.modules.guide:Show("rfk")
    slash("guide")
    reset()
    slash("guide")
    check(ZodUIGuide:IsShown() and has("Razorfen Kraul", ZodUIGuide) and not printed("here is"), "outside a dungeon it opens the one you had last, without the list again")
    ns.modules.guide:Show("sfk")
    check(tile() == "Interface\\WorldMap\\ShadowfangKeep\\ShadowfangKeep1_1" and has("Next: 1. Entrance", ZodUIGuide),
        "the courtyard's map with the first step next")
    check(lines() >= 4, "the route is drawn as lines, got " .. lines())
    slash("guide")
    check(not ZodUIGuide:IsShown(), "/zod guide again closes it")
    slash("guide nowhere")
    check(printed("no guide for 'nowhere' yet"), "a dungeon without a guide is said")

    -- Entering Shadowfang Keep opens it.
    W.instance, W.map, W.subzone = { "Shadowfang Keep", "party" }, 310, "The Jail"
    fire("PLAYER_ENTERING_WORLD")
    pump(3)
    check(ZodUIGuide:IsShown() and G.Shown() == "sfk", "entering the dungeon opens the guide")

    -- A kill moves it on and learns the room.
    reset()
    fire("ENCOUNTER_END", 2748, "Rethilgore", 1, 5, 0)
    check(G.Current("sfk") == 1, "a wipe moves nothing")
    fire("ENCOUNTER_END", 2748, "Rethilgore", 1, 5, 1)
    check(G.Current("sfk") == 3 and G.Run("sfk").done[1] and G.Run("sfk").done[2], "a kill marks the boss and the way to it done")
    check(printed("Dungeon guide: next, 3. Fel Steed."), "and says what is next")
    check(ns.db.guide.rooms.sfk[2] == "The Jail", "the room it died in is learned")
    check(has("Next: 3. Fel Steed", ZodUIGuide), "the window shows the next step")

    -- Skipping the optional one: the old encounter ID counts too.
    W.subzone = "The Kitchen"
    fire("BOSS_KILL", 465, "Razorclaw the Butcher")
    check(G.Current("sfk") == 5 and G.Run("sfk").done[3], "a later kill skips the steps before it")
    fire("BOSS_KILL", 465, "Razorclaw the Butcher")
    check(G.Current("sfk") == 5, "the same kill twice changes nothing")

    -- About here: the room when it is known, else the last kill.
    W.subzone = "The Jail"
    local w = G.Where("sfk")
    check(w.how == "room" and w.step == 2 and w.floor == 1, "in a learned room you are by its boss")
    W.subzone = "Somewhere New"
    w = G.Where("sfk")
    check(w.how == "last" and w.step == 4, "elsewhere you are about at the last kill")
    G:Draw()
    check(has("You: about at 4. Razorclaw the Butcher, in Somewhere New.", ZodUIGuide) and ZodUIGuide.you:IsShown(), "and the window says so")

    -- A new floor turns the map.
    W.map = 316
    fire("ZONE_CHANGED_INDOORS")
    check(tile() == "Interface\\WorldMap\\ShadowfangKeep\\ShadowfangKeep7_1" and has("The Wall Walk", ZodUIGuide), "a new floor turns the map to it")
    check(not ZodUIGuide.you:IsShown(), "with no kill up there yet there is no 'about here'")
    click(ZodUIGuide.floors[1])
    check(tile() == "Interface\\WorldMap\\ShadowfangKeep\\ShadowfangKeep1_1", "a floor button shows that floor")
    fire("ZONE_CHANGED")
    check(tile() == "Interface\\WorldMap\\ShadowfangKeep\\ShadowfangKeep1_1", "and it stays while you are on the same floor")
    W.map = 315
    fire("ZONE_CHANGED")
    check(tile() == "Interface\\WorldMap\\ShadowfangKeep\\ShadowfangKeep6_1", "until you change floors")
    W.map = 310

    -- A boss known only by name.
    fire("BOSS_KILL", nil, "Baron Silverlaine")
    check(G.Current("sfk") == 6 and has("Next: 6. Stairs up", ZodUIGuide), "a kill is matched by name too")

    -- Next, Back.
    click("Next")
    check(G.Current("sfk") == 7, "Next moves on by hand")
    check(has("Commander Springvale", ZodUIGuide) and has("No spot mapped yet", ZodUIGuide), "a step with no spot says so")
    click("Back")
    check(G.Current("sfk") == 6, "Back steps back")
    click("Next")

    -- Drawing.
    check(not G:Click(0.5, 0.5, "LeftButton"), "clicks do nothing outside the draw mode")
    reset()
    slash("guide draw")
    check(printed("Dungeon guide: drawing."), "/zod guide draw starts drawing")
    check(G:Click(0.64, 0.42, "LeftButton", true), "shift-click puts the step's spot")
    local s7 = G.Steps("sfk")[7]
    check(s7.x == 0.64 and s7.y == 0.42 and s7.floor == 1 and s7.edited, "the step has the spot, on the floor shown")
    check(G:Click(0.3, 0.2, "LeftButton") and G:Click(0.31, 0.25, "LeftButton") and #G.Steps("sfk")[7].via == 2, "clicks add bends")
    check(G:Click(0, 0, "RightButton") and #G.Steps("sfk")[7].via == 1, "right-click takes the last one away")
    check(not G:Click(1.5, 0.2, "LeftButton") and not G:Click(0.2, "x", "LeftButton"), "a click off the map does nothing")
    check(ns.GUIDES.sfk.steps[7].x == nil, "the route data itself is untouched")
    ZodUIGuide.map.scripts.OnMouseUp(ZodUIGuide.map, "LeftButton")
    check(#G.Steps("sfk")[7].via == 2, "a real click on the map adds a bend")

    -- Sharing.
    local line = G.Export("sfk")
    check(line:find("^ZGR1 sfk 7@1:0.64:0.42 7~1:0.3:0.2~") ~= nil, "the route goes out as one line: " .. line)
    G:Clear("sfk")
    check(G.Steps("sfk")[7].x == nil and G.Export("sfk") == "ZGR1 sfk", "clear takes your changes away")
    local key, said = G.Import(line)
    check(key == "sfk" and said == "took the route for Shadowfang Keep." and G.Export("sfk") == line, "and the line brings them back")
    local bad = { "hello", "ZGR1 dm 2@1:0.1:0.1", "ZGR1 sfk 99@1:0.1:0.1", "ZGR1 sfk 2@9:0.1:0.1", "ZGR1 sfk 2@1:1.5:0.1",
        "ZGR1 sfk 2~1:0.1:0.1~x", "ZGR1 sfk 2@1:0.1", "ZGR1 sfk " .. string.rep("2~1:0.1:0.1", 1, "~") .. string.rep("~1:0.1:0.1", 25),
        string.rep("a", 5000), 42 }
    local allBad = true
    for _, b in ipairs(bad) do
        if G.Import(b) then allBad = false end
    end
    check(allBad and G.Export("sfk") == line, "lines that do not read are refused and change nothing")
    reset()
    click("Share")
    check(ZodUIShareBox:IsShown() and has("Your route for Shadowfang Keep", ZodUIShareBox) and ZodUIShareBox.input.edit:GetText() == line,
        "Share shows the line to copy")
    ZodUIShareBox:Hide()
    click("Take")
    ZodUIShareBox.input.edit:SetText("ZGR1 sfk")
    click("Take this route")
    check(has("nothing drawn in it", ZodUIShareBox) and G.Export("sfk") == line, "an empty route line is refused, so it cannot wipe yours")
    ZodUIShareBox:Hide()
    G:Clear()
    check(G.Export("sfk") == "ZGR1 sfk" and ZodUIGuide.share.off, "with nothing drawn, Share is greyed")
    ZodUIShareBox:Hide()
    slash("export")
    check(has("Your ZodUI settings", ZodUIShareBox), "the settings export is as before")
    ZodUIShareBox:Hide()
    slash("guide draw")

    -- Folding keeps the next step and where you are, without the map; it is remembered.
    local tall = ZodUIGuide:GetHeight()
    click(ZodUIGuide.fold)
    check(G.db.folded and not ZodUIGuide.map:IsShown() and not button("Draw") and not button("Start over") and button("Back") and button("Next")
        and ZodUIGuide:GetHeight() < tall and has("Next: ", ZodUIGuide) and has("You: ", ZodUIGuide)
        and plain(ZodUIGuide.fold.label.text) == "+", "the fold button leaves the next step, where you are, Back and Next")
    local at = G.Current(G.Shown())
    click("Next")
    check(G.Current(G.Shown()) == at + 1, "and Next works folded")
    click("Back")
    ZodUIGuide:Hide()
    G:Show("sfk")
    check(not ZodUIGuide.map:IsShown(), "and stays folded the next time it opens")
    click(ZodUIGuide.fold)
    check(not G.db.folded and ZodUIGuide.map:IsShown() and button("Draw") and ZodUIGuide:GetHeight() == tall, "+ brings the map back")

    -- Start over; an old run starts over by itself.
    click(click("Start over"))
    check(G.Current("sfk") == 1, "Start over begins again")
    G.Run("sfk").done[1] = true
    G.Run("sfk").seen = time() - 3 * 3600
    G.Fresh("sfk")
    check(G.Current("sfk") == 1, "a run left hours ago starts over")

    -- Leaving closes what it opened.
    W.instance = nil
    fire("ZONE_CHANGED_NEW_AREA")
    check(not ZodUIGuide:IsShown(), "leaving the dungeon closes the guide it opened")

    -- Razorfen Kraul.
    W.instance, W.map, W.subzone = { "Razorfen Kraul", "party" }, 301, ""
    fire("ZONE_CHANGED_NEW_AREA")
    check(G.Shown() == "rfk" and tile() == "Interface\\WorldMap\\RazorfenKraul\\RazorfenKraul1_1" and has("Next: 1. Entrance", ZodUIGuide),
        "entering Razorfen Kraul opens its guide, from the start")
    check(lines() >= 7, "with its route drawn")
    reset()
    fire("ENCOUNTER_END", 2773, "Roogug", 1, 5, 1)
    check(G.Current("rfk") == 3 and printed("Dungeon guide: next, 3. Aggem Thorncurse."), "Roogug's kill moves it on to Aggem")
    fire("ENCOUNTER_END", 443, "Charlga Razorflank", 1, 5, 1)
    check(G.Current("rfk") == 8 and has("All done. Razorfen Kraul is cleared.", ZodUIGuide), "Charlga is the last")
    W.instance = nil
    fire("ZONE_CHANGED_NEW_AREA")

    -- Scarlet Monastery: four wings in one instance.
    local function smTile(n) return tile() == "Interface\\WorldMap\\ScarletMonastery\\ScarletMonastery" .. n .. "_1" end
    check(G.Lookup("sm") == "smgy" and G.Lookup("scarlet monastery") == "smgy" and G.Lookup("cath") == "smcath"
        and G.Lookup("library") == "smlib" and G.Lookup("Scarlet Monastery: Armory") == "smarm", "the wings are found by their words, sm gives the first")
    W.instance, W.map, W.subzone = { "Scarlet Monastery", "party" }, 0, ""
    fire("ZONE_CHANGED_NEW_AREA")
    check(G.Shown() == "smgy" and smTile(1) and has("Scarlet Monastery", ZodUIGuide), "when nothing tells the wing, the Graveyard shows")
    check(button("Graveyard") and button("Library") and button("Armory") and button("Cathedral") and not button("1"), "a button for each wing, none for a single floor")
    W.map = 305
    fire("ZONE_CHANGED")
    check(G.Shown() == "smcath" and smTile(4), "the Cathedral's map ID turns the guide to it")
    W.map, W.subzone = 0, "Huntsman's Cloister"
    fire("ZONE_CHANGED")
    check(G.Shown() == "smlib" and smTile(2), "a Library room's name turns it to the Library")
    check(plain(ZodUIGuide.title.text) == "Scarlet Monastery" and G.Steps("smlib")[1].x and #G.Steps("smlib")[3].via >= 6,
        "a wing's title leaves its name to the button; the Library has its door and corridors")
    W.subzone = "Grand Vestibule"
    fire("ZONE_CHANGED")
    check(G.Shown() == "smlib", "a room that says nothing keeps the wing")
    reset()
    fire("ENCOUNTER_END", 448, "Herod", 1, 5, 1)
    check(G.Shown() == "smarm" and ns.chardb.guideWing == "smarm" and G.Current("smarm") == 2 and printed("Herod done, that was the last of Scarlet Monastery: Armory."),
        "Herod's kill shows the Armory was it, and finishes it")
    click("Cathedral")
    check(G.Shown() == "smcath" and ns.chardb.guideWing == "smcath" and has("Next: 1. Entrance", ZodUIGuide), "a wing button switches by hand")
    reset()
    fire("BOSS_KILL", nil, "Scarlet Commander Mograine")
    check(G.Current("smcath") == 3 and printed("Dungeon guide: next, 3. High Inquisitor Whitemane."), "Mograine is matched by name")
    check(G.Current("smarm") == 2, "each wing keeps its own run")
    slash("guide gy")
    check(G.Shown() == "smgy" and smTile(1), "/zod guide gy shows the Graveyard")
    W.instance = nil
    fire("ZONE_CHANGED_NEW_AREA")

    -- Every guide draws, with its art or a word about it.
    local errs = #ns.errors
    local keys = {}
    for key in pairs(ns.GUIDES) do keys[#keys + 1] = key end
    table.sort(keys)
    W.loaded.ForeverDungeonJournal = true
    local drawn = 0
    for _, key in ipairs(keys) do
        if G:Show(key) and G.Shown() == key then drawn = drawn + 1 end
    end
    check(drawn == #keys and #ns.errors == errs, "all " .. #keys .. " guides draw without an error")
    G:Show("zf")
    check(ZodUIGuide.art:IsShown() and ZodUIGuide.art.texture == "Interface\\AddOns\\ForeverDungeonJournal\\Media\\ZulFarrakMap"
        and not ZodUIGuide.tiles[1]:IsShown(), "Zul'Farrak uses ForeverDungeonJournal's map art")
    W.loaded.ForeverDungeonJournal = nil
    G:Draw()
    check(not ZodUIGuide.art:IsShown() and ZodUIGuide.noart:IsShown() and has("needs the ForeverDungeonJournal addon", ZodUIGuide),
        "without it the map says where its art comes from")
    G:Show("wc")
    check(ZodUIGuide.tiles[1]:IsShown() and ZodUIGuide.tiles[1].texture == "Interface\\WorldMap\\WailingCaverns\\WailingCaverns1_1",
        "where the client has tiles, they stand in")
    G:Show("lbrs")
    check(has("No map of this dungeon yet", ZodUIGuide) and has("Next: 1. Highlord Omokk", ZodUIGuide), "a dungeon with no map still lists its steps")

    -- Dire Maul by its maps, Stratholme by a kill, Blackrock Spire by its first.
    W.instance, W.map, W.subzone = { "Dire Maul", "party" }, 237, ""
    fire("ZONE_CHANGED_NEW_AREA")
    check(G.Shown() == "dmw" and has("Court of the Highborne", ZodUIGuide), "Dire Maul's map IDs pick the West wing and its floor")
    W.map = 235
    fire("ZONE_CHANGED")
    check(G.Shown() == "dmn", "and the North")
    W.instance, W.map = nil, 0
    fire("ZONE_CHANGED_NEW_AREA")
    W.instance = { "Stratholme", "party" }
    fire("ZONE_CHANGED_NEW_AREA")
    check(G.Shown() == "stratlive", "Stratholme with nothing to go by shows the Living side")
    fire("ENCOUNTER_END", 484, "Baron Rivendare", 1, 5, 1)
    check(G.Shown() == "stratud" and G.Current("stratud") == 8, "the Baron's kill shows it was the Undead side")
    W.instance = nil
    fire("ZONE_CHANGED_NEW_AREA")
    W.instance = { "Blackrock Spire", "party" }
    fire("ZONE_CHANGED_NEW_AREA")
    check(G.Shown() == "lbrs", "Blackrock Spire shows the lower spire first")
    fire("ENCOUNTER_END", 3062, "Pyroguard Emberseer", 1, 10, 1)
    check(G.Shown() == "ubrs" and G.Current("ubrs") == 3, "Emberseer's kill turns it to the upper")

    -- The Deadmines: the Shredder counts for Sneed, the cove is the next floor.
    W.instance, W.map = { "The Deadmines", "party" }, 291
    fire("ZONE_CHANGED_NEW_AREA")
    fire("BOSS_KILL", nil, "Sneed's Shredder")
    check(G.Shown() == "vc" and G.Current("vc") == 5 and has("Next: 5. Down to the foundry", ZodUIGuide), "Sneed's Shredder counts as Sneed")
    W.map = 292
    fire("ZONE_CHANGED_INDOORS")
    check(has("Ironclad Cove", ZodUIGuide), "the cove is its own floor")
    W.instance, W.map = nil, 0
    fire("ZONE_CHANGED_NEW_AREA")
    W.level = level

    W.instance, W.map, W.subzone = saved.instance, saved.map, saved.subzone
    ns.chardb.guides, ns.chardb.guideWing, ns.db.guide = nil, nil, nil
    G.Forget()
end

---------------------------------------------------------------------------
say("--- speed: timers, the profiler and the ad cache")
do
    local fired = 0
    pump(1)
    ns.After(0.5, function() fired = fired + 1 end)
    pump(0.4)
    check(fired == 0, "a timer added between looks counts from when it was added")
    pump(0.2)
    check(fired == 1, "and runs when due")
    local ticks = 0
    ns.Every(0.3, function() ticks = ticks + 1 end)
    pump(1)
    check(ticks == 3, "a repeating timer keeps its pace: " .. ticks)

    reset()
    slash("perf stop")
    check(printed("not measuring."), "/zod perf stop with nothing running")
    slash("perf start")
    check(printed("measuring what ZodUI costs.") and ns.Profiling(), "/zod perf start")
    fire("CHAT_MSG_CHANNEL", "LFM SFK need tank", "Bob-Realm", "", "2. Trade - City", "", "", 2, 2, "Trade - City")
    pump(1)
    reset()
    slash("perf")
    check(printed("over ") and printed("board CHAT_MSG_CHANNEL") and printed("1x"), "/zod perf lists what ran, by module and event")
    reset()
    slash("perf stop")
    check(printed("stopped measuring.") and not ns.Profiling(), "/zod perf stop")

    local a = ns.Ads.Parse("LFM SFK need tank", 24)
    a.at = 1
    local b = ns.Ads.Parse("LFM SFK need tank", 24)
    check(b ~= a and b.at == nil and b.kind == "group" and b.dungeons[1].key == "sfk" and b.roles.tank, "a cached ad is a fresh copy")
    check(ns.Ads.Parse("LFM DM need tank", 20).dungeons[1].key == "vc" and ns.Ads.Parse("LFM DM need tank", 58).dungeons[1].key == "dm",
        "the cache keeps the level band apart")
    check(ns.Ads.Parse("LF tank for dire maul east", 58).dungeons[1].key == "dm" and ns.Ads.Parse("wts sunken temple run", 55).kind == "sell"
        and ns.Ads.Parse("LFG sunken temple", 55).dungeons[1].key == "st", "names of more than one word are still found")
    local B = ns.modules.board
    for i = #B.ads, 1, -1 do B.ads[i] = nil end
    B:Add("WTS [Linen Cloth] cheap", "Ann-Realm")
    B:Add("WTS [Wool Cloth] cheap", "Ann-Realm")
    B:Add("WTS [Linen Cloth] cheap", "Ann-Realm")
    check(#B.ads == 2 and B.ads[1].count == 2 and B.ads[1].plain == "wts [linen cloth] cheap", "a repeated ad moves up with a count")
    for i = #B.ads, 1, -1 do B.ads[i] = nil end
end

---------------------------------------------------------------------------
say("--- mail subject")
do
    local box = { text = "" }
    function box:GetText() return self.text end
    function box:SetText(t) self.text = t end
    local attached = {}
    SendMailSubjectEditBox = box
    GetSendMailItem = function(i) local a = attached[i] if a then return a[1], 1, 1, a[2] end end
    attached[1] = { "Linen Cloth", 20 }
    fire("MAIL_SEND_INFO_UPDATE")
    check(box.text == "Linen Cloth x20", "an attached stack names the subject: " .. box.text)
    attached[2] = { "Linen Cloth", 5 }
    fire("MAIL_SEND_INFO_UPDATE")
    check(box.text == "Linen Cloth x25", "more of the same adds up")
    attached[3] = { "Copper Ore", 10 }
    fire("MAIL_SEND_INFO_UPDATE")
    check(box.text == "Linen Cloth and 1 more", "different items: the first and how many more")
    attached = {}
    fire("MAIL_SEND_INFO_UPDATE")
    check(box.text == "", "taking them out empties it again")
    box.text = "For your alt"
    attached[1] = { "Copper Ore", 1 }
    fire("MAIL_SEND_INFO_UPDATE")
    check(box.text == "For your alt", "a subject you typed is kept")
    SendMailSubjectEditBox, GetSendMailItem = nil, nil
end

---------------------------------------------------------------------------
say("--- the Commands page")
do
    local page = ns.pages.commands
    slash("commands")
    local function find(cmd)
        for _, b in ipairs(page.buttons) do
            if b.cmd == cmd then return b end
        end
    end
    local known = { report = 1, where = 1, played = 1, notices = 1, test = 1, errors = 1, modules = 1, version = 1, safe = 1,
        unlock = 1, lock = 1, reset = 1, export = 1, import = 1, find = 1, reload = 1 }
    local bad = {}
    for _, b in ipairs(page.buttons) do
        local w = b.cmd:match("^(%S+)")
        if not (known[w] or ns.modules[w] or ns.pages[w] or (ns.pluginCommands and ns.pluginCommands[w])) then bad[#bad + 1] = b.cmd end
    end
    check(#page.buttons >= 45 and #bad == 0, "every button runs a command /zod knows (" .. #page.buttons .. "): " .. table.concat(bad, ", "))
    for _, s in ipairs(ns.ACTIONS) do
        if s.module then check(ns.modules[s.module] ~= nil, "the " .. s.title .. " section names a real module") end
    end

    local real = print
    reset()
    click(find("version"))
    check(printed("v" .. ns.version) and has("v" .. ns.version, page.frame), "a button runs its command; what it says shows on the page and in chat")
    check(print == real, "and print is given back")

    reset()
    click(find("crafters"))
    check(has("Fill in the field first: shift-click a recipe.", page.frame) and #W.printed == 0,
        "a needed field left empty says so, and runs nothing")

    local chat = ns.modules.chat
    local wasOn = chat.enabled
    if not wasOn then chat:Enable() end
    local watch = find("chat watch")
    watch.field:SetText("zebra")
    click(watch)
    local watched = false
    for _, w in ipairs(chat.db.words) do watched = watched or w == "zebra" end
    check(watched and watch.field:GetText() == "zebra", "the field goes with the command; an optional one is kept for the next button")
    click(find("chat unwatch"))
    watched = false
    for _, w in ipairs(chat.db.words) do watched = watched or w == "zebra" end
    check(not watched, "so Stop takes the same word")
    if not wasOn then chat:Disable() end

    local sell = find("vendor sell").field
    local link = "|cffffffff|Hitem:2589::::::::1:::::|h[Linen Cloth]|h|r"
    sell:SetFocus()
    ChatEdit_InsertLink(link)
    check(sell:GetText() == link, "a shift-clicked link lands in the field that has the focus")
    sell:ClearFocus()
    sell:SetText("")
    pump(1)
    ChatEdit_InsertLink(link)
    check(sell:GetText() == "", "and in no field without it")

    local run = SlashCmdList.ZODUI
    SlashCmdList.ZODUI = function() print("half way") error("bang") end
    local lines = ns.RunCommand("anything")
    SlashCmdList.ZODUI = run
    check(print == real and lines[1] == "half way", "print is given back when a command fails")

    local vendor = ns.modules.vendor
    local vendorOn = vendor.enabled
    vendor:Disable()
    page:Refresh()
    check(has("Vendor  (off: switch it on under Settings)", page.frame), "a section whose module is off says so")
    if vendorOn then vendor:Enable() end
end

---------------------------------------------------------------------------
say("--- saved data can be written to disk")
fire("PLAYER_LOGOUT")
local function plainData(t, path)
    for k, v in pairs(t) do
        local kind = type(v)
        check(type(k) == "string" or type(k) == "number", "key type at " .. path)
        if kind == "table" then
            plainData(v, path .. "." .. tostring(k))
        else
            check(kind == "string" or kind == "number" or kind == "boolean", path .. "." .. tostring(k) .. " is a " .. kind)
        end
    end
end
plainData(ZodUIDB, "ZodUIDB")
plainData(ZodUICharDB, "ZodUICharDB")
check(ZodUIDB.chars[ns.charKey].level == 26 and ZodUIDB.chars[ns.charKey].money == W.money, "the character record is current at logout")

---------------------------------------------------------------------------
say("--- small comforts")
do
    local errorsBefore = #ns.errors
    -- A page's own choice (here: one line per dungeon) is kept with the module, so it outlasts /reload.
    ns.Show("runs")
    click("By dungeon")
    check(ns.modules.runs.db.byDungeon == true, "the dungeons page remembers one line per dungeon")
    check(button("Every run").tip:find("Now: one line per dungeon", 1, true), "and its button says what it shows now")
    click("Every run")
    check(ns.modules.runs.db.byDungeon == nil, "and forgets it again when switched back")

    -- Empty boxes say what goes in them, and Tab goes on to the next.
    ns.Show("loans")
    local page = ns.pages.loans
    check(page.who.placeholder and page.who.placeholder:IsShown() and page.who.placeholder.text == "Who", "an empty box says what goes in it")
    page.who.edit:SetText("Grunt")
    page.who.edit.scripts.OnTextChanged(page.who.edit, true)
    check(not page.who.placeholder:IsShown(), "and the hint goes when there is text")
    page.who.edit.scripts.OnTabPressed(page.who.edit)
    check(page.amount.edit:HasFocus(), "Tab goes on to the next box")
    page.who.edit:SetText("")

    -- Shift-click on an item puts its link in the chat line.
    local put
    ChatEdit_InsertLink = function(link) put = link return true end
    check(T.InsertLink("|cffffffff|Hitem:101::|h[Item 101]|h|r") and put:find("Item 101", 1, true), "a full link goes into the chat line")
    check(not T.InsertLink(nil), "no link, nothing put")
    ChatEdit_InsertLink = nil

    -- The away box is one of the frames unlock mode moves.
    ns.Unlock()
    local found = false
    for _, h in pairs(ns.moverHandles) do if h.label and h.label.text == "Away box" then found = true end end
    ns.Lock()
    check(found, "unlock mode can move the away box")

    -- The corner grips size a window by its scale; the top-left corner stays, a double-click makes it normal again.
    ns.Show("home")
    local g = ZodUIFrame.grip
    g.scripts.OnMouseDown(g, "LeftButton")
    g.scripts.OnUpdate(g, 0.1) -- the stub's cursor is at x 500, the window's left at 100: smaller than the least
    g.scripts.OnMouseUp(g, "LeftButton")
    check(ZodUIFrame.scale == 0.7 and ns.db.general.scale == 70, "the grip makes the window smaller, down to 70%: " .. tostring(ns.db.general.scale))
    check(ns.db.window.point == "TOPLEFT" and g.scripts.OnUpdate == nil, "it keeps the top-left corner, and stops when let go")
    g.scripts.OnDoubleClick(g)
    check(ZodUIFrame.scale == 1 and ns.db.general.scale == 100, "a double-click on the grip makes it normal size")
    -- Let go away from the grip (no OnMouseUp reaches it): it still stops, at once.
    g.scripts.OnMouseDown(g, "LeftButton")
    IsMouseButtonDown = function() return false end
    g.scripts.OnUpdate(g, 0.1)
    check(g.scripts.OnUpdate == nil and ZodUIFrame.scale == 1, "a grip let go off itself stops sizing instead of going on for ever")
    IsMouseButtonDown = nil
    ns.modules.guide:Show("sfk")
    local gg = ZodUIGuide.grip
    gg.scripts.OnMouseDown(gg, "LeftButton")
    gg.scripts.OnUpdate(gg, 0.1)
    gg.scripts.OnMouseUp(gg, "LeftButton")
    local gs = ns.modules.guide.db.scale
    check(gs and gs > 0.7 and gs < 0.8 and ZodUIGuide.scale == gs, "the guide has a grip too: " .. tostring(gs))
    gg.scripts.OnDoubleClick(gg)
    check(ns.modules.guide.db.scale == nil and ZodUIGuide.scale == 1, "and is normal size again after a double-click")
    ns.modules.guide:Hide()

    -- Headings sort: numbers and money as numbers, text as text; a third click gives the page's order back.
    local sorted = T.SortRows({ { "b", ns.Money(25000) }, { "a", ns.Money(500) }, { "c", ns.Money(1234567) } }, 2, true)
    check(sorted[1][1] == "c" and sorted[2][1] == "b" and sorted[3][1] == "a", "money sorts by its worth, most first")
    sorted = T.SortRows({ { "1,200" }, { "95%" }, { "x" }, { "30" } }, 1)
    check(sorted[1][1] == "30" and sorted[2][1] == "95%" and sorted[3][1] == "1,200" and sorted[4][1] == "x", "numbers sort as numbers, before text")
    local tbl = T.Table(UIParent, { { "Name", 100 }, { "Count", 60 } }, 200, 100)
    tbl:SetRows({ { "b", "2" }, { "a", "10" } })
    check(tbl.rows[1].cells[1].text == "b", "a table starts in the page's order")
    local hb = tbl.headButtons[2]
    hb.scripts.OnClick(hb, "LeftButton")
    check(tbl.rows[1].cells[1].text == "b" and tbl.heads[2].text == "Count ^", "a click on a heading sorts on it, least first")
    hb.scripts.OnClick(hb, "LeftButton")
    check(tbl.rows[1].cells[1].text == "a" and tbl.heads[2].text == "Count v", "a second click, most first")
    hb.scripts.OnClick(hb, "LeftButton")
    check(tbl.rows[1].cells[1].text == "b" and tbl.heads[2].text == "Count" and tbl.sortCol == nil, "a third, the page's own order again")
    hb.scripts.OnClick(hb, "LeftButton")
    hb.scripts.OnClick(hb, "LeftButton")
    local again = T.Table(UIParent, { { "Name", 100 }, { "Count", 60 } }, 200, 100) -- as after /reload
    again:SetRows({ { "b", "2" }, { "a", "10" } })
    check(again.sortCol == 2 and again.sortDesc and again.rows[1].cells[1].text == "a" and again.heads[2].text == "Count v", "the chosen sort is kept across /reload")
    hb.scripts.OnClick(hb, "LeftButton")
    check(ns.db.general.sorts["Name|Count"] == nil, "and forgotten when the page's own order is back")

    -- A new text size shows at once, no /reload.
    local sample = T.Text(UIParent, "GameFontHighlightSmall")
    local _, was = sample:GetFont()
    local bumpWas = ns.db.general.font
    ns.db.general.font = (bumpWas or 1) + 2
    T.ApplyFont()
    local _, now = sample:GetFont()
    check(now == was + 2, "the text size changes at once: " .. tostring(was) .. " -> " .. tostring(now))
    ns.db.general.font = bumpWas
    T.ApplyFont()

    -- Remove is greyed while no row is chosen, and says why.
    ns.Show("goals")
    local gp = ns.pages.goals
    gp.list.selected = nil
    gp:Refresh()
    check(gp.remove.off and gp.remove.tip:find("first", 1, true), "Remove this goal is greyed with nothing chosen")

    -- Escape while editing a note calls the edit off.
    ns.Show("notes")
    local np = ns.pages.notes
    ns.modules.notes:Add("Buy shiny thing")
    np:Refresh()
    np.rows[1].edit.scripts.OnClick(np.rows[1].edit, "LeftButton")
    check(np.editing ~= nil, "Edit puts the line in the box")
    np.input.edit.scripts.OnEscapePressed(np.input.edit)
    check(np.editing == nil and (np.input.edit:GetText() or "") == "", "Escape calls the edit off")

    -- Times and dates read the same on every page, and a date column sorts by the moment.
    local nowAt = time()
    check(ns.Ago(30) == "just now" and ns.Ago(13 * 60) == "13m ago" and ns.Ago(3 * 86400) == "3d ago", "how long ago, one way")
    check(ns.When(nowAt) == "today " .. date("%H:%M", nowAt) and ns.When(nowAt, true) == "today", "today says today")
    check(ns.When(nowAt - 86400, true) == "yesterday", "and yesterday yesterday")
    local old = nowAt - 400 * 86400
    check(ns.When(old) == date("%d %b %Y", old), "a date from another year shows the year")
    sorted = T.SortRows({ { ns.WhenCell(nowAt) }, { ns.WhenCell(old) }, { ns.WhenCell(nowAt - 86400) } }, 1)
    check(sorted[1][1][2] == old and sorted[3][1][2] == nowAt, "a date column sorts by the moment, not the words")

    -- Up and Down choose a search result; Enter opens the chosen one.
    ns.Search("se")
    local fp = ns.pages.find
    check(#fp.results >= 2, "the search finds something to choose from")
    local fe = ZodUIFrame.find.edit
    fe.scripts.OnArrowPressed(fe, "DOWN")
    fe.scripts.OnArrowPressed(fe, "DOWN")
    check(fp.cursor == 2 and fp.list.selected == fp.results[2], "Down twice chooses the second result")
    fe.scripts.OnArrowPressed(fe, "UP")
    check(fp.cursor == 1, "Up goes back")
    fe:SetText("")
    fe.scripts.OnTextChanged(fe, true)

    -- Right-click on a reminder removes it at once.
    ns.modules.remind:Add(30, "Stretch the legs")
    ns.Show("remind")
    local rp = ns.pages.remind
    rp:Refresh()
    local before = #ns.db.reminders
    local row = rp.list.rows[1]
    row.scripts.OnClick(row, "RightButton")
    check(#ns.db.reminders == before - 1, "a right-click removes the reminder")

    -- The minimap tooltip names new mail, as the info bar does.
    local hadMail = HasNewMail
    HasNewMail = function() return true end
    local glance = table.concat(ns.Glance(), "|")
    HasNewMail = hadMail
    check(glance:find("New mail", 1, true), "the glance names new mail: " .. glance)
    check(#ns.errors == errorsBefore, "no errors from the small comforts" .. (ns.errors[errorsBefore + 1] and (": " .. ns.errors[errorsBefore + 1]) or ""))
end

---------------------------------------------------------------------------
say("--- shortcuts and small conveniences")
do
    local G = ns.modules.guide
    -- Key bindings for the dungeon guide.
    check(ZodUI_Guide and BINDING_NAME_ZODUI_GUIDE_NEXT, "the guide has key bindings")
    G:Show("sfk")
    local before = G.Current("sfk")
    ZodUI_Guide("next")
    check(G.Current("sfk") == before + 1, "the Next key steps the guide on")
    ZodUI_Guide("back")
    check(G.Current("sfk") == before, "and Back steps back")
    -- The mouse wheel over the map does the same.
    local map = ZodUIGuide.map
    map.scripts.OnMouseWheel(map, -1)
    check(G.Current("sfk") == before + 1, "wheel down over the map: the next step")
    map.scripts.OnMouseWheel(map, 1)
    check(G.Current("sfk") == before, "wheel up: the step before")
    G:Hide()

    -- Outside a dungeon, the Next key steps the guide you had last.
    G:Hide()
    W.instance, W.map, W.subzone = nil, 1424, ""
    ns.chardb.guideLast = "sfk"
    local was = G.Current("sfk")
    ZodUI_Guide("next")
    check(G.Current("sfk") == was + 1 and ZodUIGuide:IsShown(), "outside a dungeon the Next key steps the guide you had last")
    ZodUI_Guide("back")
    G:Hide()

    -- Unlock mode: right-click the info bar's box puts the bar back at the top.
    local bar = ns.modules.databar
    bar.db.where, bar.db.pos.point = "free", "CENTER"
    ns.Unlock()
    local h = ns.moverHandles.databar
    if h then
        h.scripts.OnMouseUp(h, "RightButton")
        check(bar.db.where == "top" and bar.db.pos.point == nil, "right-click on the info bar's box puts it back at the top")
    end
    ns.Lock()

    -- Settings opens on the module looked at last, when the window remembers its page.
    ns.db.general.remember = true
    ns.db.general.lastSettings = "loot"
    local sp = ns.pages.settings
    if sp.frame then sp.frame:Hide() sp.frame = nil end
    ns.Show("settings")
    check(sp.selected == ns.modules.loot, "Settings opens on the module looked at last")
    ns.Show("settings", ns.order[#ns.order].key)
    check(sp.listScroll:GetVerticalScroll() > 0, "a module far down the list is scrolled into view")
    ns.db.general.lastSettings = nil

    -- A Next up line on Home opens its page.
    ns.Show("home")
    local home = ns.pages.home
    local hit
    for _, card in ipairs(home.cards) do
        if card.title.text == "Next up" then hit = card.hits[1] end
    end
    if hit and hit.page then
        hit.scripts.OnClick(hit, "LeftButton")
        check(ns.pages[hit.page] and ns.pages[hit.page].frame and ns.pages[hit.page].frame:IsShown(), "a Next up line opens its page")
    else
        say("   (no Next up line with a page to click)")
    end
end

say("--- an update not looked at")
do
    ns.db.general.newsUnseen = true
    ns.Fold(false)
    check(ZodUIFrame.news.label.text == "What's new *", "an update marks the What's new button")
    ZodUIFrame.news.scripts.OnClick(ZodUIFrame.news, "LeftButton")
    check(ns.db.general.newsUnseen == nil and ZodUIFrame.news.label.text == "What's new", "opening it takes the mark away")
end

say("--- commands of a module that is off")
do
    local m
    for _, s in ipairs(ns.ACTIONS) do if s.module and ns.modules[s.module] and not m then m = ns.modules[s.module] end end
    local was = m.enabled
    m:Disable()
    ns.Show("commands")
    local page = ns.pages.commands
    page:Refresh()
    local b
    for _, x in ipairs(page.buttons) do if x.section and x.section.module == m.key then b = x end end
    check(b and b.off and b.tip:find("is off", 1, true), "a button of a module that is off is greyed and says why")
    m:Enable()
    page:Refresh()
    check(not b.off and b.tip == b.plainTip, "and lit again with its own tip once the module is on")
    if not was then m:Disable() end
end

say("--- table layout")
do
    -- Every page built, then every table measured: its columns must fit inside it with room for the
    -- scroll thumb on the right (8 px in, 6 px between cells, 3 px thumb, 2 px air), and should not leave
    -- a wide empty strip on the right either.
    for key in pairs(ns.pages) do ns.Show(key) end
    local over, slack = {}, {}
    for _, t in ipairs(madeTables) do
        local sum = 0
        for _, col in ipairs(t.columns) do sum = sum + col[2] end
        local room = t.width - 9
        if sum > room then over[#over + 1] = t.at .. " (" .. sum .. " > " .. room .. ")" end
        if room - sum > 24 and not t.at:find("test.lua", 1, true) then slack[#slack + 1] = t.at .. " (" .. (room - sum) .. " px spare)" end
    end
    -- Every page in turn: a button whose label is wider than the button, and a one-line text cut short.
    local tight, cut, seen = {}, {}, {}
    for key in pairs(ns.pages) do
        ns.Show(key)
        pump(0.3)
        for _, w in ipairs(W.frames) do
            if w.kind == "FontString" and w.at and (w.text or "") ~= "" and w:IsVisible() then
                local width = w:GetStringWidth()
                local p = w.parent
                if p and p.kind == "Button" and p.label == w and width > p:GetWidth() - 6 and not seen[w.at] then
                    seen[w.at] = true
                    tight[#tight + 1] = w.at .. " '" .. w.text .. "' (" .. width .. " in " .. p:GetWidth() .. ")"
                elseif w.wrap == false and (w.w or 0) > 0 and width > w.w + 2
                    and not seen[w.at .. tostring(p and p.parent)] then -- a table's cells: once per table
                    seen[w.at .. tostring(p and p.parent)] = true
                    cut[#cut + 1] = w.at .. " (" .. width .. " in " .. w.w .. ") '" .. (w.text or ""):sub(1, 40) .. "'"
                end
            end
        end
    end
    for _, line in ipairs(tight) do say("   TIGHT " .. line) end
    for _, line in ipairs(cut) do say("   CUT   " .. line) end
    say("   tables: " .. #madeTables .. (#slack > 0 and ("; spare room: " .. table.concat(slack, ", ")) or ""))
    check(#over == 0, "every table's columns fit inside it: " .. table.concat(over, ", "))
    check(#slack == 0, "no table leaves a wide empty strip on the right: " .. table.concat(slack, ", "))
end

do -- the client may hand back a secret boolean for being away
    W.afk, W.secret = "secret afk", "secret afk"
    local ok, away = pcall(ns.IsAway)
    check(ok and away == false, "a secret away flag reads as not away instead of erroring")
    W.afk, W.secret = false, nil
    W.afk = true
    check(ns.IsAway() == true, "a plain away flag still reads as away")
    W.afk = false
end

do -- your own level, name and class: a secret read keeps the last plain value instead of erroring
    local level, name = W.level, W.name
    W.level, W.name = 17, "Zod"
    check(ns.Level() == 17 and ns.MyName() == "Zod" and select(2, ns.MyClass()) == "PALADIN", "plain level, name and class read through")
    W.level, W.name, W.secret = "secret 18", "secret Zod", "secret 18"
    local ok, l = pcall(ns.Level)
    check(ok and l == 17, "a secret level gives the last plain level")
    W.secret = "secret Zod"
    local ok2, n = pcall(ns.MyName)
    check(ok2 and n == "Zod", "a secret name gives the last plain name")
    local savedClass = UnitClass
    UnitClass = function() return "secret class", "secret class" end
    W.secret = "secret class"
    local ok3, _, file = pcall(ns.MyClass)
    check(ok3 and file == "PALADIN", "a secret class gives the last plain class")
    UnitClass = savedClass
    local savedRole, party = W.role, IsInGroup
    W.role, W.secret = "secret role", "secret role"
    IsInGroup = function() return true end
    local healer = ns.modules.healer
    local ok4 = pcall(healer.Heals, healer)
    check(ok4, "a secret group role does not error the healer check")
    W.role, IsInGroup, W.secret = savedRole, party, nil
    W.level, W.name = level, name
end

---------------------------------------------------------------------------
say("--- look")
do
    local T = ns.T
    check(T.look == "game" and T.WINDOW[1] > T.WINDOW[3], "the game look is the default, in WoW Forever's warm colours")
    -- Without the game's Options window there is no frame to copy: the flat edge stays.
    local f = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    check(T.Window(f, T.WINDOW, 0.9) == false and f.backdrop.edgeFile and not f.gameArt, "no Options window: the flat edge")
    -- With it, its eight pieces are copied, anchored to the window and to each other.
    local pieces = {}
    local function Piece(atlas)
        local p = { GetAtlas = function() return atlas end, GetDrawLayer = function() return "OVERLAY", 1 end,
            GetWidth = function() return 40 end, GetHeight = function() return 40 end, GetNumPoints = function() return 1 end }
        p.GetPoint = function() return "TOPLEFT", pieces.TopLeftCorner ~= p and pieces.TopLeftCorner or nil, "TOPRIGHT", -2, 2 end
        return p
    end
    local nine = {}
    for _, key in ipairs({ "TopLeftCorner", "TopRightCorner", "BottomLeftCorner", "BottomRightCorner", "TopEdge", "BottomEdge",
        "LeftEdge", "RightEdge" }) do
        pieces[key] = Piece("Options_" .. key)
        nine[key] = pieces[key]
    end
    SettingsPanel = { NineSlice = nine }
    local g = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    check(T.Window(g, T.WINDOW, 0.9) == true and g.gameArt and not g.backdrop.edgeFile and g.backdrop.insets,
        "the Options window's frame is copied, with a plain background inside it")
    check(g.gameArtPieces.TopEdge.t.layer == "BORDER" and g.gameArt.bg.layer == "BACKGROUND",
        "drawn on the window in its lowest layers, under its texts, so a title on its band shows")
    local art = g.gameArt
    T.Window(g, T.WINDOW, 0.9)
    check(g.gameArt == art, "and not twice on one window")
    -- A short window (the route's tracker, folded) gets the same frame, smaller, so the corners do not overlap.
    g:SetSize(300, 400)
    check(T.FitArt(g) == 1, "a window taller than two corners has them at full size")
    g:SetHeight(40)
    if g.scripts.OnSizeChanged then g.scripts.OnSizeChanged(g) end
    check(g.gameArtShare == 0.5 and g.gameArtPieces.TopLeftCorner.t.w == 20, "a short one has them at the share it has room for")
    -- A piece another addon took away: no half frame, the flat edge.
    nine.LeftEdge = { GetAtlas = function() return nil end }
    local h = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    check(T.Window(h, T.WINDOW, 0.9) == false and h.backdrop.edgeFile and not h.gameArt, "a missing piece gives the flat edge")
    check(T.artWhy:find("LeftEdge has no atlas", 1, true), "and it says why: " .. T.artWhy)
    -- Pieces not laid out yet (0 x 0) take their atlas's size.
    nine.LeftEdge = Piece("Options_LeftEdge")
    nine.LeftEdge.GetWidth = function() return 0 end
    local savedTex = C_Texture
    C_Texture = { GetAtlasInfo = function() return { width = 12, height = 64 } end }
    local k = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    check(T.Window(k, T.WINDOW, 0.9) == true and k.gameArtPieces.LeftEdge.w == 12, "a piece with no size yet takes its atlas's")
    C_Texture = savedTex
    nine.LeftEdge = Piece("Options_LeftEdge")
    -- The windows that got the flat edge get the frame when it can be had (the Options window opened; /zod look).
    reset()
    slash("look")
    check(h.gameArt and f.gameArt and printed("got it now") and printed("from the Options window"),
        "/zod look tries the flat ones again and says where the frame comes from")
    reset()
    local shown
    StaticPopupDialogs, StaticPopup_Show = {}, function(which) shown = which end
    slash("look modern")
    check(ns.db.general.look == "flat" and printed("The Modern look shows after /reload") and shown == "ZODUI_RELOAD"
        and StaticPopupDialogs.ZODUI_RELOAD.button1 == "Reload now", "/zod look modern switches the look and asks to reload")
    StaticPopupDialogs, StaticPopup_Show = nil, nil
    local btn = T.Button(UIParent, "Go", 80, function() end)
    local r, g = btn.label:GetTextColor()
    check(btn.game and r == 1 and g == 0.82, "the Forever look has the game's red buttons with yellow text")
    check(T.Edit(UIParent, 120).game, "and the game's own text box")
    local tbl = T.Table(UIParent, { { "A", 100 } }, 200, 200)
    tbl:SetRows({ { "x" }, { "y" }, { "z" } })
    check(tbl.rows[2] and tbl.rows[2].stripe and not tbl.rows[1].stripe, "a table shades every other row")
    local function plainMoney(c) return (ns.Money(c):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
    check(plainMoney(2500) == "25s" and plainMoney(120005) == "12g 5c" and plainMoney(0) == "0c",
        "money leaves out a unit that is 0: " .. plainMoney(2500) .. ", " .. plainMoney(120005) .. ", " .. plainMoney(0))
    local card = ns.Toast("Framed")
    check(ns.toasts[1] and ns.toasts[1].inset == 4, "a notice has the game's tooltip edge in the Forever look")
    ns.toasts[1].scripts.OnMouseUp(ns.toasts[1])
    check(T.Close(UIParent, function() end).gameClose and T.NavColor(false) == T.GAME_YELLOW,
        "the Forever look has the game's red X and its yellow list")
    slash("look forever")
    check(ns.db.general.look == "game", "and /zod look forever back")
    SettingsPanel = nil
    check(ns.api.Theme.Window == T.Window, "plugins (Undead Route) get the same window frame")
end

say("")
say(passed .. " checks passed, " .. failed .. " failed")
if failed > 0 then error("FAILED", 0) end
say("ALL OK")
