local ADDON, ns = ...

-- /zod perf: what ZodUI itself costs while you play. /zod perf start times every event
-- handler, timer, tooltip line and chat filter (Core\Init.lua's ns.Run and ns.Timed);
-- /zod perf shows the most costly so far, /zod perf stop shows them and stops. Nothing is
-- timed while it is off, so it costs nothing then.

local MOST = 12
local started, startMem

-- ZodUI's memory in KB, or nil where the client does not say.
local function Memory()
    local update = UpdateAddOnMemoryUsage or (C_AddOns and C_AddOns.UpdateAddOnMemoryUsage)
    local get = GetAddOnMemoryUsage or (C_AddOns and C_AddOns.GetAddOnMemoryUsage)
    if not (update and get) then return nil end
    if not pcall(update) then return nil end
    local ok, kb = pcall(get, ADDON)
    return ok and type(kb) == "number" and kb or nil
end

local function Ms(ms)
    if ms >= 10 then return string.format("%.0f ms", ms) end
    if ms >= 0.1 then return string.format("%.2f ms", ms) end
    return string.format("%.0f us", ms * 1000)
end

local function Kb(kb)
    return kb >= 1024 and string.format("%.1f MB", kb / 1024) or string.format("%.0f KB", kb)
end

-- The report as lines: the whole, then the most costly by time spent.
function ns.PerfLines(prof, seconds)
    local rows, total, calls = {}, 0, 0
    for label, p in pairs(prof or {}) do
        rows[#rows + 1] = { label = label, ms = p[1], n = p[2], slowest = p[3] }
        total, calls = total + p[1], calls + p[2]
    end
    table.sort(rows, function(a, b)
        if a.ms ~= b.ms then return a.ms > b.ms end
        return a.label < b.label
    end)
    seconds = math.max(1, seconds or 1)
    local lines = { string.format("over %s: %s in all, %s a minute (%.3f%% of the time), %d calls.",
        ns.Duration(seconds), Ms(total), Ms(total / seconds * 60), total / (seconds * 1000) * 100, calls) }
    for i = 1, math.min(MOST, #rows) do
        local r = rows[i]
        lines[#lines + 1] = string.format("%s  |cff999999%s, %dx, %s each, slowest %s|r", r.label, Ms(r.ms), r.n, Ms(r.ms / r.n), Ms(r.slowest))
    end
    return lines, rows
end

local function Show(prof)
    local lines = ns.PerfLines(prof, GetTime() - started)
    ns.Print(lines[1])
    for i = 2, #lines do print("  " .. lines[i]) end
    local mem = Memory()
    if mem then print("  Memory: " .. Kb(mem) .. (startMem and (" (" .. (mem >= startMem and "+" or "-") .. Kb(math.abs(mem - startMem)) .. " since start)") or "")) end
end

ns.pluginCommands = ns.pluginCommands or {}
ns.pluginCommands.perf = function(arg)
    local word = (arg or ""):lower():match("^%s*(%S*)")
    local prof = ns.Profiling()
    if word == "start" or (word == "" and not prof) then
        ns.ProfileStart()
        started, startMem = GetTime(), Memory()
        ns.Print("measuring what ZodUI costs. Play a while, then /zod perf shows it and /zod perf stop ends it.")
    elseif word == "stop" then
        if not prof then ns.Print("not measuring. /zod perf start begins.") return end
        Show(ns.ProfileStop())
        ns.Print("stopped measuring.")
    elseif word == "" then
        Show(prof)
    else
        ns.Print("/zod perf start, /zod perf, /zod perf stop.")
    end
end
