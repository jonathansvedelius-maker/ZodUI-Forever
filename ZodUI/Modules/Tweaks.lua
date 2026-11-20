local ADDON, ns = ...

-- Game settings: a few of the game's own settings that are awkward to reach.
-- Each one remembers what the setting was and puts it back when it is unticked
-- or the module is switched off. The camera distance, addon errors and chat time
-- stamps are EllesmereUI's settings, and its unit frames replace the bars whose
-- numbers statusText showed, so those four left in 0.28.0.

local CVARS = {
    { key = "autoLoot", cvar = "autoLootDefault", value = "1", label = "Loot everything automatically" },
    { key = "lootAtMouse", cvar = "lootUnderMouse", value = "1", label = "Open the loot window at the mouse pointer" },
    { key = "profanity", cvar = "profanityFilter", value = "0", label = "Turn off the chat language filter" },
    { key = "shots", cvar = "screenshotQuality", value = "10", label = "Save screenshots at the best quality" },
    { key = "tot", cvar = "showTargetOfTarget", value = "1", label = "Show the target of your target" },
}

local options, defaults = {}, { enabled = false, was = {} }
for _, c in ipairs(CVARS) do
    options[#options + 1] = { type = "check", key = c.key, label = c.label }
    defaults[c.key] = false
end
options[#options + 1] = { type = "note", text = "Unticking a setting, or switching the module off, puts it back to what it was before.", lines = 2 }

local M = ns:NewModule("tweaks", {
    title = "Game settings",
    desc = "Changes a few of the game's own settings for you. Nothing is touched until you switch the module on and tick a setting.",
    defaults = defaults,
    options = options,
})

local function Get(cvar)
    local get = C_CVar and C_CVar.GetCVar or GetCVar
    if not get then return nil end
    local ok, value = pcall(get, cvar)
    return ok and value or nil
end

local function Set(cvar, value)
    local set = C_CVar and C_CVar.SetCVar or SetCVar
    if set then pcall(set, cvar, value) end
end

local pending

local function Apply()
    if InCombatLockdown and InCombatLockdown() then
        pending = true -- the game refuses setting changes in combat
        return
    end
    pending = false
    local was = M.db.was
    for _, c in ipairs(CVARS) do
        local want = M.enabled and M.db[c.key]
        if want then
            local now = Get(c.cvar)
            if now ~= nil and tostring(now) ~= c.value then
                if was[c.cvar] == nil then was[c.cvar] = tostring(now) end
                Set(c.cvar, c.value)
            end
        elseif was[c.cvar] ~= nil then
            Set(c.cvar, was[c.cvar])
            was[c.cvar] = nil
        end
    end
    -- A setting this module no longer offers is put back the first time round.
    local offered = {}
    for _, c in ipairs(CVARS) do offered[c.cvar] = true end
    for cvar, value in pairs(was) do
        if not offered[cvar] then
            Set(cvar, value)
            was[cvar] = nil
        end
    end
end

M.OnEnable = Apply
M.OnDisable = Apply
M.OnOption = Apply

ns.On("PLAYER_REGEN_ENABLED", function()
    if pending then ns.Guard("tweaks", Apply) end
end)
