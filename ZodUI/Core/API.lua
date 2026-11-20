local ADDON, ns = ...

-- The ZodUI API: how another addon (a plugin, such as ZodRoute) plugs into
-- ZodUI. Everything a plugin needs is on ZodUI.api; the rest of the ZodUI
-- table is ZodUI's own and may change between versions. A plugin checks
-- ZodUI.api.level, which goes up only when something here changes in a way
-- that breaks plugins.
--
--   local Z = ZodUI and ZodUI.api
--   if Z and Z.level >= 1 then
--       local M = Z.NewModule("route", { title = "Route", plugin = "ZodRoute", desc = "...",
--           defaults = { enabled = true }, options = { ... } })
--       function M:Card() return { title = "Route", lines = { { "Next", "..." } } } end
--       function M:Hints(add) add("Hand in 3 quests in Tarren Mill", 75, "route") end
--       Z.AddPage({ key = "route", title = "Route", order = 5, module = "route",
--           Build = function(page, frame) ... end, Refresh = function(page) ... end })
--       Z.AddCommand("route", function(rest) ... end, "Open the route")
--   end
--
-- A module made with NewModule works like ZodUI's own: settings described by
-- `options` (see Core\Window.lua), saved with ZodUI's, switched on and off in
-- Settings and on the Modules page, and its handlers run guarded. Its optional
-- methods: OnEnable, OnDisable, OnOption(key, value), Card(), Hints(add),
-- Find(part, add, has), Slash(rest).

local api = { level = 1, version = ns.version }
ns.api = api
local waiting = {}

-- The palette and the widget builders ZodUI's own pages use, so a plugin looks
-- the same: Text, Panel, Flat, Window (a big window's frame, in the chosen look), Close (its close button), Button, Check, Edit, Table, Scroll, Bar, Paint,
-- ShowTip, HideTip, and the colours WINDOW, PANEL, SURFACE, HOVER, BORDER,
-- GOLD (the accent), DIM, MUTED, GREEN, RED.
api.Theme = ns.T

-- fn(api) runs once ZodUI has loaded its data and switched its modules on:
-- at login, or at once when that has happened already.
function api.Ready(fn)
    if ns.ready then
        ns.Guard("plugin ready", fn, api)
    else
        waiting[#waiting + 1] = fn
    end
end

ns.On("PLAYER_LOGIN", function()
    for _, fn in ipairs(waiting) do ns.Guard("plugin ready", fn, api) end
    waiting = {}
end)

-- A module of the plugin's own; info.plugin names the addon it comes from.
function api.NewModule(key, info)
    assert(type(key) == "string" and key ~= "" and not ns.modules[key], "ZodUI: a module key must be new: " .. tostring(key))
    assert(type(info) == "table" and info.title, "ZodUI: a module needs a title")
    info.plugin = info.plugin or "another addon"
    return ns:NewModule(key, info)
end

-- A page in ZodUI's window: { key, title, Build(page, frame), Refresh(page, arg),
-- order, group, module, hidden }. Listed under Plugins unless it names a group.
function api.AddPage(page)
    assert(type(page) == "table" and page.key and page.title and page.Build, "ZodUI: a page needs a key, a title and Build")
    assert(not ns.pages[page.key], "ZodUI: a page key must be new: " .. tostring(page.key))
    page.group = page.group or "Plugins"
    page.order = page.order or 60
    ns.AddPage(page)
end

-- /zod <word> ...: fn(rest) gets what was typed after the word.
function api.AddCommand(word, fn, help)
    word = word:lower()
    ns.pluginCommands = ns.pluginCommands or {}
    ns.pluginCommands[word] = fn
    if help and ns.COMMANDS then ns.COMMANDS[#ns.COMMANDS + 1] = { "/zod " .. word, help } end
    if ns.AddAction then
        ns.AddAction("Plugins", { help or ("/zod " .. word), field = "what to add, if anything", buttons = { { "Run", word } } })
    end
end

-- A frame /zod unlock lets the player drag: { key, title, width, height, point, x, y, Apply, Shown, Store, Anchor }.
function api.AddMover(info) ns.AddMover(info) end

-- Events and timers that run guarded, and only while `module` is on (when one is given).
function api.On(event, fn, module) ns.On(event, fn, module) end
function api.Every(seconds, fn, module) ns.Every(seconds, fn, module) end
function api.After(seconds, fn) ns.After(seconds, fn) end
function api.Guard(where, fn, ...) return ns.Guard(where, fn, ...) end

function api.Show(key, arg) ns.Show(key, arg) end
function api.Refresh() ns.Refresh() end
function api.Alert(msg) ns.Alert(msg) end
function api.Print(msg, who)
    print("|cffffd100" .. (who or "ZodUI") .. ":|r " .. tostring(msg))
end
function api.Money(copper, short) return ns.Money(copper, short) end
function api.Duration(seconds) return ns.Duration(seconds) end
