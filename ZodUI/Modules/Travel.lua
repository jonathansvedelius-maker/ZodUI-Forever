local ADDON, ns = ...

-- Travel: how to get where you are going next, in one place. Your hearthstone (where it
-- is set and when it is ready), where Undead Route sends you next, and the portals mages
-- offer in the public channels right now (from Chat board). /zod travel, or /zod travel uc
-- for the portals to one city.

local M = ns:NewModule("travel", {
    title = "Travel",
    desc = "How to get where you are going: your hearthstone and when it is ready, where Undead Route sends you next, and the portals mages offer in chat right now. /zod travel.",
    defaults = { enabled = true },
})

local HEARTHSTONE = 6948
local FRESH = 15 * 60

-- City words, as ads write them.
M.CITIES = {
    { "Undercity", { "uc", "undercity" } }, { "Orgrimmar", { "org", "orgrimmar", "ogri", "ogr", "ogrimmar" } },
    { "Thunder Bluff", { "tb", "thunder bluff", "thunderbluff" } }, { "Stormwind", { "sw", "stormwind" } },
    { "Ironforge", { "if", "ironforge" } }, { "Darnassus", { "darn", "darnassus" } },
}

local function Has(p, w)
    return p:find("%f[%w]" .. w:gsub("%p", "%%%0") .. "%f[%W]") ~= nil
end

-- The city an ad or a word names, or nil.
function M.City(text)
    local p = (text or ""):lower()
    for _, c in ipairs(M.CITIES) do
        for _, w in ipairs(c[2]) do
            if Has(p, w) then return c[1] end
        end
    end
end

-- Portal offers said in the last quarter hour; to `city` when one is given.
function M:Portals(city)
    local board = ns.modules.board
    local out = {}
    if not (board and board.enabled and board.List) then return out end
    for _, ad in ipairs(board:List("service")) do
        if time() - ad.at <= FRESH and (Has(ad.plain, "portal") or Has(ad.plain, "portals") or Has(ad.plain, "port")) then
            local to = not city or ad.plain:find(city:lower(), 1, true)
            if not to then
                for _, c in ipairs(M.CITIES) do
                    if c[1] == city then
                        for _, w in ipairs(c[2]) do to = to or Has(ad.plain, w) end
                    end
                end
            end
            if to then out[#out + 1] = ad end
        end
    end
    return out
end

function M:Hearth()
    local cd = (C_Container and C_Container.GetItemCooldown) or GetItemCooldown
    local count = C_Item and C_Item.GetItemCount or GetItemCount
    if count and (count(HEARTHSTONE) or 0) == 0 then return nil end
    local where = GetBindLocation and GetBindLocation() or "?"
    local start, duration = 0, 0
    if cd then start, duration = cd(HEARTHSTONE) end
    local left = (start or 0) > 0 and ((start + (duration or 0)) - GetTime()) or 0
    return where, left > 0 and left or 0
end

function M:Lines(city)
    local lines = {}
    local where, left = self:Hearth()
    if where then
        lines[#lines + 1] = "Hearthstone: " .. where .. ", " .. (left > 0 and ("ready in " .. ns.Duration(left)) or "ready") .. "."
    end
    local route = type(UndeadRoute) == "table" and type(UndeadRoute.Status) == "function" and select(2, pcall(UndeadRoute.Status))
    if type(route) == "table" and type(route.stage) == "string" then
        lines[#lines + 1] = "Undead Route: " .. route.stage .. (type(route.hub) == "string" and (", " .. route.hub) or "") .. "."
    end
    local portals = self:Portals(city)
    if #portals > 0 then
        local shown = {}
        for i = 1, math.min(3, #portals) do
            local ad = portals[i]
            shown[i] = "|Hplayer:" .. ad.author .. "|h[" .. (ad.author:match("^[^%-]+") or ad.author) .. "]|h"
        end
        lines[#lines + 1] = "Portals" .. (city and (" to " .. city) or "") .. " offered now: " .. table.concat(shown, ", ") .. "."
    elseif ns.modules.board and ns.modules.board.enabled then
        lines[#lines + 1] = "No portal" .. (city and (" to " .. city) or "") .. " offered in chat in the last 15 minutes."
    end
    return lines
end

function M:Slash(arg)
    local word = (arg or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local city = word ~= "" and M.City(word) or nil
    if word ~= "" and not city then ns.Print("no city called '" .. word .. "'. Try uc, org, tb, sw, if or darn.") return end
    local lines = self:Lines(city)
    if #lines == 0 then ns.Print("nothing to tell: no hearthstone, route or portals.") return end
    ns.Print(lines[1])
    for i = 2, #lines do print("  " .. lines[i]) end
end

function M:Card()
    local where, left = self:Hearth()
    if not where then return nil end
    local lines = { { "Hearthstone", where .. (left > 0 and ("  |cff999999" .. ns.Duration(left) .. "|r") or "") } }
    local n = #self:Portals()
    if n > 0 then lines[#lines + 1] = { "Portals in chat", tostring(n) } end
    return { title = "Travel", lines = lines }
end
