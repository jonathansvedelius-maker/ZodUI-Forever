-- Measures ZodUI's own cost outside the game: node tools/run.js --bench
-- Loads and logs in as the test does, then times the hot paths: every frame (the timers),
-- chat lines (events and chat filters), loot, bags, XP, money, tooltips and the window.
-- The VM is far slower than the game's Lua, so the numbers compare runs, not the game.
local W = World
local say = function(s) io.write(s .. "\n") end
local clock = os.clock

local function fire(event, ...)
    for _, f in ipairs(W.frames) do
        if f.events[event] and f.scripts.OnEvent then f.scripts.OnEvent(f, event, ...) end
    end
end

local base = W.clock
local function frames(n, step)
    for _ = 1, n do
        W.uptime = W.uptime + step
        W.clock = base + math.floor(W.uptime - 1000)
        for i = 1, #W.frames do
            local f = W.frames[i]
            if f.scripts.OnUpdate and f:IsVisible() then f.scripts.OnUpdate(f, step) end
        end
    end
end

W.bags[0] = {
    [1] = { id = 100, quality = 0, count = 5, price = 20 },
    [2] = { id = 101, quality = 1, count = 1, price = 500 },
    [3] = { id = 104, quality = 2, count = 1, price = 900 },
}
ZodUIDB = { chars = { ["Alt-Forever"] = { name = "Alt", realm = "Forever", class = "MAGE", level = 31, money = 500000 } } }

local t0 = clock()
local ns = {}
for _, file in ipairs(ADDON_FILES) do
    assert(load(file[2], "@" .. file[1]))("ZodUI", ns)
end
local loadMs = (clock() - t0) * 1000
ns.ProfileStart()
fire("ADDON_LOADED", "ZodUI")
fire("PLAYER_LOGIN")
fire("PLAYER_ENTERING_WORLD")
local loginMs = (clock() - t0) * 1000
frames(30 * 10, 0.1) -- let the login timers run out
local loginProf = ns.ProfileStop()
W.printed = {}
say(string.format("  %-44s %10.1f ms", "loading the files", loadMs))
local llines = ns.PerfLines(loginProf, 30)
say("  the first 30 s after login, most costly:")
for i = 2, math.min(7, #llines) do say("    " .. llines[i]:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end

local results = {}
local function bench(name, n, fn)
    pcall(collectgarbage)
    local start = clock()
    for i = 1, n do fn(i) end
    local us = (clock() - start) * 1e6 / n
    results[#results + 1] = { name, us }
    say(string.format("  %-44s %10.1f us", name, us))
end

say(string.format("  %-44s %10.1f ms", "load and login", loginMs))

-- Every frame at 60 fps: the timers and OnUpdate scripts, window closed.
bench("a frame (60 fps), window closed", 3000, function() frames(1, 1 / 60) end)
local ticking = {}
for _, f in ipairs(W.frames) do
    if f.scripts.OnUpdate and f:IsVisible() then ticking[#ticking + 1] = f end
end
say(string.format("  %-44s %10d", "  frames with an OnUpdate, shown", #ticking))
bench("  of which ZodUI's OnUpdate scripts alone", 3000, function()
    W.uptime = W.uptime + 1 / 60
    for _, f in ipairs(ticking) do f.scripts.OnUpdate(f, 1 / 60) end
end)

local ADS = {
    "WTS [Linen Cloth] x20 cheap /w me", "LFM SFK need tank and heals", "LF2M BFD heal and dps", "WTB Mageweave 1g each",
    "anyone up for some world pvp?", "LFG RFK as dps", "Enchanting your mats, tips welcome: crusader",
    "lol that was a wipe", "WTS Mage portal to UC 50s", "guild recruiting casual levelers, discord", "LF tank for SM lib",
    "selling [Tough Scorpid Breastplate] 4g", "where is the flight master in Hillsbrad?", "LF1M Gnomer heals then go",
}
local n = 0
bench("a trade/LFG chat line (events)", 1400, function(i)
    n = n + 1
    fire("CHAT_MSG_CHANNEL", ADS[i % #ADS + 1] .. " " .. (n % 37), "Seller" .. (i % 50) .. "-Forever", "", "2. Trade - City",
        "", "", 2, 2, "Trade - City")
end)

bench("  of which ns.Ads.Parse (uncached line)", 1400, function(i)
    ns.Ads.Parse(ADS[i % #ADS + 1] .. " x" .. i, 24)
end)
bench("  of which ns.Ads.Plain", 1400, function(i) ns.Ads.Plain(ADS[i % #ADS + 1]) end)

local filters = W.chatFilterList and W.chatFilterList.CHAT_MSG_CHANNEL or { W.chatFilters.CHAT_MSG_CHANNEL }
bench("a chat line through the chat filters (x1 frame)", 1400, function(i)
    for _, f in ipairs(filters) do
        f(nil, "CHAT_MSG_CHANNEL", ADS[i % #ADS + 1], "Seller-Forever", "", "2. Trade - City", "", "", 2, 2, "Trade - City")
    end
end)

local guild = W.chatFilters.CHAT_MSG_GUILD
bench("a guild line through the chat filter", 1400, function(i)
    if guild then guild(nil, "CHAT_MSG_GUILD", "hey Zod, want to run sfk later? " .. i, "Ann-Forever") end
    fire("CHAT_MSG_GUILD", "hey Zod, want to run sfk later? " .. i, "Ann-Forever")
end)

local LOOT = LOOT_ITEM_SELF or "You receive loot: %s."
bench("a loot line", 600, function(i)
    fire("CHAT_MSG_LOOT", string.format(LOOT, "|cffffffff|Hitem:" .. (100 + i % 3) .. "::::::::24:::::|h[Thing]|h|r"), "Zod")
end)

bench("bags change, then 1 s of frames", 200, function()
    fire("BAG_UPDATE_DELAYED")
    frames(60, 1 / 60)
end)

bench("XP, money and a kill", 600, function(i)
    W.xp = W.xp + 10
    fire("CHAT_MSG_COMBAT_XP_GAIN", "Defias Thug dies, you gain 120 experience.")
    fire("PLAYER_XP_UPDATE", "player")
    W.money = W.money + 1
    fire("PLAYER_MONEY")
end)

local item = W.tooltipCalls[Enum.TooltipDataType.Item]
bench("an item tooltip", 1400, function(i)
    GameTooltip.lines = {}
    item(GameTooltip, { id = 100 + i % 5 })
end)
local unit = W.tooltipCalls[Enum.TooltipDataType.Unit]
if unit then
    bench("a unit tooltip", 1400, function()
        GameTooltip.lines = {}
        unit(GameTooltip, { guid = "Player-1" })
    end)
end

bench("group roster change", 600, function() fire("GROUP_ROSTER_UPDATE") end)
bench("zone change", 300, function() fire("ZONE_CHANGED_NEW_AREA") end)

SlashCmdList.ZODUI("")
frames(2, 0.1)
bench("a frame (60 fps), window open", 1200, function() frames(1, 1 / 60) end)
SlashCmdList.ZODUI("")

-- Where the time goes, by handler: the whole run again with the profiler on.
say("")
say("profile of one more pass:")
ns.ProfileStart()
local p0 = clock()
for i = 1, 700 do
    fire("CHAT_MSG_CHANNEL", ADS[i % #ADS + 1] .. " " .. i, "Seller" .. (i % 50) .. "-Forever", "", "2. Trade - City", "", "", 2, 2, "Trade - City")
    for _, f in ipairs(filters) do f(nil, "CHAT_MSG_CHANNEL", ADS[i % #ADS + 1], "Seller-Forever", "", "2. Trade", "", "", 2, 2, "Trade") end
end
for i = 1, 300 do fire("CHAT_MSG_LOOT", string.format(LOOT, "|cffffffff|Hitem:" .. (100 + i % 3) .. "::::::::24:::::|h[Thing]|h|r"), "Zod") end
for i = 1, 300 do
    W.xp = W.xp + 10
    fire("CHAT_MSG_COMBAT_XP_GAIN", "Defias Thug dies, you gain 120 experience.")
    fire("PLAYER_XP_UPDATE", "player")
    W.money = W.money + 1
    fire("PLAYER_MONEY")
end
for i = 1, 700 do GameTooltip.lines = {} item(GameTooltip, { id = 100 + i % 5 }) end
for _ = 1, 30 do fire("BAG_UPDATE_DELAYED") frames(60, 1 / 60) end
SlashCmdList.ZODUI("")
frames(600, 1 / 60)
SlashCmdList.ZODUI("")
local lines, rows = ns.PerfLines(ns.ProfileStop(), clock() - p0)
for _, l in ipairs(lines) do say("  " .. l:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
say("  the window's cards, each:")
for _, r in ipairs(rows) do
    if r.label:find(" card$") and r.ms / r.n > 0.02 then say(string.format("    %-24s %6.0f us", r.label, r.ms / r.n * 1000)) end
end

say("")
say("errors: " .. #ns.errors)
for _, e in ipairs(ns.errors) do say("  " .. e) end
