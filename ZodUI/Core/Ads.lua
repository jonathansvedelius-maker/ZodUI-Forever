local ADDON, ns = ...

-- Ads: reads a line from the public channels and says what it is, for Chat board and
-- Group match. ns.Ads.Parse(text, level) returns nil for chatter, or
--   { kind = "sell" | "buy" | "service" | "group", lf = "more" | "group" (for groups: they
--     need people, or they want a group), dungeons = { dungeon, ... }, roles = { tank, heal, dps } }
-- Matching is on the plain lower-case text, by whole words.

local Ads = {}
ns.Ads = Ads

-- The classic dungeons, with the levels a group runs them at.
Ads.DUNGEONS = {
    { key = "rfc", name = "Ragefire Chasm", min = 13, max = 18, words = { "rfc", "ragefire" } },
    { key = "wc", name = "Wailing Caverns", min = 15, max = 25, words = { "wc", "wailing" } },
    { key = "vc", name = "The Deadmines", min = 17, max = 26, words = { "vc", "deadmines", "deadmine" } },
    { key = "sfk", name = "Shadowfang Keep", min = 22, max = 30, words = { "sfk", "shadowfang" } },
    { key = "stocks", name = "The Stockade", min = 22, max = 30, words = { "stocks", "stockade", "stockades" } },
    { key = "bfd", name = "Blackfathom Deeps", min = 24, max = 32, words = { "bfd", "blackfathom" } },
    { key = "gnomer", name = "Gnomeregan", min = 29, max = 38, words = { "gnomer", "gnomeregan" } },
    { key = "rfk", name = "Razorfen Kraul", min = 30, max = 40, words = { "rfk", "kraul" } },
    { key = "sm", name = "Scarlet Monastery", min = 28, max = 45,
      words = { "sm", "scarlet", "gy", "graveyard", "lib", "library", "arm", "armory", "armoury", "cath", "cathedral" } },
    { key = "rfd", name = "Razorfen Downs", min = 40, max = 50, words = { "rfd", "downs" } },
    { key = "ulda", name = "Uldaman", min = 42, max = 52, words = { "ulda", "uld", "uldaman" } },
    { key = "zf", name = "Zul'Farrak", min = 44, max = 54, words = { "zf", "zul'farrak", "zulfarrak", "farrak" } },
    { key = "mara", name = "Maraudon", min = 46, max = 55, words = { "mara", "maraudon" } },
    { key = "st", name = "Sunken Temple", min = 50, max = 60, words = { "st", "sunken temple", "temple of atal'hakkar" } },
    { key = "brd", name = "Blackrock Depths", min = 52, max = 60, words = { "brd" } },
    { key = "lbrs", name = "Lower Blackrock Spire", min = 55, max = 60, words = { "lbrs" } },
    { key = "ubrs", name = "Upper Blackrock Spire", min = 58, max = 60, words = { "ubrs" } },
    { key = "dm", name = "Dire Maul", min = 55, max = 60, words = { "dire maul", "dme", "dmw", "dmn", "dm east", "dm west", "dm north" } },
    { key = "strat", name = "Stratholme", min = 58, max = 60, words = { "strat", "strath", "stratholme" } },
    { key = "scholo", name = "Scholomance", min = 58, max = 60, words = { "scholo", "scholomance" } },
}
local BY_KEY = {}
for _, d in ipairs(Ads.DUNGEONS) do BY_KEY[d.key] = d end

-- A dungeon's one-word names -> the dungeon, and its longer names as { name, dungeon }.
local DUNGEON_WORD, DUNGEON_LONG, hit = {}, {}, {}
for _, d in ipairs(Ads.DUNGEONS) do
    for _, w in ipairs(d.words) do
        if w:find("^[%w']+$") then
            DUNGEON_WORD[w] = DUNGEON_WORD[w] or d
        else
            DUNGEON_LONG[#DUNGEON_LONG + 1] = { w, d }
        end
    end
end

-- A line is looked at word by word: its words ([%w'] runs) go into a set once, and a one-word
-- entry is a lookup in it. Only entries of more than one word ("need tank", "dire maul") are
-- searched for, with a pattern made once per entry.
-- A longer entry is searched for only when its first word is in the line.
local PATTERN = {} -- entry -> its pattern, or false for a one-word entry
local FIRST = {}   -- longer entry -> its first word
local words = {}   -- the words of the line being parsed

local function Word(p, w)
    local pattern = PATTERN[w]
    if pattern == nil then
        pattern = not w:find("^[%w']+$") and ("%f[%w']" .. w:gsub("%p", "%%%0") .. "%f[^%w']") or false
        PATTERN[w], FIRST[w] = pattern, pattern and w:match("^[%w']+") or nil
    end
    if not pattern then return words[w] == true end
    local first = FIRST[w]
    if first and not words[first] then return false end
    return p:find(pattern) ~= nil
end

local function Any(p, list)
    for i = 1, #list do
        if Word(p, list[i]) then return true end
    end
    return false
end

-- The text without colours and link codes, lower case: "[Linen Cloth]" stays.
function Ads.Plain(text)
    return (text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|H.-|h", ""):gsub("|h", ""):lower())
end

local MORE = { "lfm", "lf1m", "lf2m", "lf3m", "lf4m", "lf 1m", "lf 2m", "lf 3m", "lf 4m", "need tank", "need heal", "need healer",
    "need dps", "lf tank", "lf heal", "lf healer", "lf dps", "lf1", "lf2", "lf3", "lf4" }
local WANT = { "lfg", "lf group", "lf grp", "lf party", "any group", "any groups", "any grp" }
local SERVICE = { "lfw", "your mats", "ur mats", "tip", "tips", "portal", "portals", "summon", "summons", "lockpicking", "lockpick" }
local PROFESSIONS = { "enchanting", "blacksmithing", "leatherworking", "tailoring", "alchemy", "engineering", "jewelcrafting", "inscription" }
local SELL = { "wts", "selling", "for sale", "cheaper than ah" }
local BUY = { "wtb", "buying", "lf", "looking for" }
local GROUPISH, RECRUIT = { "lf", "group", "need", "inv" }, { "recruiting", "recruit", "recruits", "discord" }
local SERVICES, MATS = { "service", "services" }, { "your mats", "ur mats", "lockpicking" }
local FREE, GET = { "get your", "for free" }, { "get your", "lfw" }
local TANK, HEAL, DPS = { "tank", "tanks" }, { "heal", "heals", "healer", "healers", "healz" }, { "dps", "dd" }

local function Parse(text, level)
    local p = Ads.Plain(text)
    for k in pairs(words) do words[k] = nil end
    for w in p:gmatch("[%w']+") do words[w] = true end
    local ad = { dungeons = {}, roles = {} }
    for k in pairs(hit) do hit[k] = nil end
    local any = false
    for w in pairs(words) do
        local d = DUNGEON_WORD[w]
        if d then hit[d], any = true, true end
    end
    for i = 1, #DUNGEON_LONG do
        local entry = DUNGEON_LONG[i]
        if not hit[entry[2]] and Word(p, entry[1]) then hit[entry[2]], any = true, true end
    end
    if any then
        for _, d in ipairs(Ads.DUNGEONS) do
            if hit[d] then ad.dungeons[#ad.dungeons + 1] = d end
        end
    end
    -- "DM" is the Deadmines to a low level player and Dire Maul to a high one.
    if Word(p, "dm") then
        local d = BY_KEY[(level or 1) < 40 and "vc" or "dm"]
        local have = false
        for _, x in ipairs(ad.dungeons) do have = have or x == d end
        if not have then ad.dungeons[#ad.dungeons + 1] = d end
    end
    if Any(p, TANK) then ad.roles.tank = true end
    if Any(p, HEAL) then ad.roles.heal = true end
    if Any(p, DPS) then ad.roles.dps = true end

    local more, want = Any(p, MORE), Any(p, WANT)
    if more or want or (#ad.dungeons > 0 and not Any(p, SELL)
        and (Any(p, GROUPISH) or next(ad.roles))) then
        ad.kind, ad.lf = "group", (more or not want) and "more" or "group"
        return ad
    end
    local sell = Any(p, SELL)
    -- A guild looking for members is not an ad for something.
    if not (sell or Word(p, "wtb")) and Any(p, RECRUIT) then return nil end
    if Word(p, "lfw") or Any(p, SERVICES) or Any(p, MATS)
        or (Any(p, SERVICE) and (sell or Any(p, FREE)))
        or (Any(p, PROFESSIONS) and (sell or Any(p, GET))) then
        ad.kind = "service"
    elseif sell then
        ad.kind = "sell"
    elseif Any(p, BUY) then
        ad.kind = "buy"
    else
        return nil
    end
    return ad
end

-- The last lines parsed, since Chat board and Group match both read each one: text and level
-- band -> ad (false for chatter). Each caller gets its own copy of the ad's top table.
local SEEN_MOST = 64
local seen, order, at = {}, {}, 0

function Ads.Parse(text, level)
    if type(text) ~= "string" or (issecretvalue and issecretvalue(text)) or text == "" then return nil end
    local key = ((level or 1) < 40 and "1" or "2") .. text
    local ad = seen[key]
    if ad == nil then
        ad = Parse(text, level) or false
        at = at % SEEN_MOST + 1
        if order[at] then seen[order[at]] = nil end
        order[at], seen[key] = key, ad
    end
    if not ad then return nil end
    return { kind = ad.kind, lf = ad.lf, dungeons = ad.dungeons, roles = ad.roles }
end
