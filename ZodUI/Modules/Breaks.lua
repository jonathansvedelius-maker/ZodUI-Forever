local ADDON, ns = ...

-- Breaks: a nudge after you have played for a while without a pause. Being
-- away (marked away, or logged out) for five minutes counts as a break.

local M = ns:NewModule("breaks", {
    title = "Break reminder",
    desc = "Reminds you to take a break after you have played for a while. Five minutes away counts as a break and starts the count again.",
    defaults = { enabled = false, every = 60 },
    options = {
        { type = "step", key = "every", label = "Remind me after", min = 30, max = 180, step = 15,
            format = function(v) return ns.Duration(v * 60) .. " of play" end },
    },
})

local PAUSE = 300 -- seconds away that count as a break
local playing, awaySince, nextAt

local function Restart()
    playing = 0
    nextAt = M.db.every * 60
end

function M:OnEnable()
    Restart()
    awaySince = nil
end

M.OnOption = Restart

ns.Every(10, function()
    if not playing then Restart() end
    local away = ns.IsAway()
    if away then
        awaySince = awaySince or time()
        if time() - awaySince >= PAUSE then Restart() end
        return
    end
    awaySince = nil
    playing = playing + 10
    if playing >= nextAt then
        ns.Alert("You have played " .. ns.Duration(playing) .. " without a break. Time to stretch?")
        nextAt = playing + M.db.every * 60
    end
end, M)
