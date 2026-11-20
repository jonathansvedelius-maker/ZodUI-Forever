local ADDON, ns = ...

-- Guild crafters: "who in my guild can make this?". /zod crafters with a shift-clicked recipe (or its spell id, and
-- the profession) asks the server which guild members know it, and lists them online first, as names you click to
-- whisper. The answers are kept, so /zod find finds them later. The guild recipe lookup is from the modern client
-- (C_GuildInfo.QueryGuildMembersForRecipe and two undocumented globals); whether the WoW Forever server answers it
-- on classic content is not known yet: /zod crafters test prints what the game returns.
-- Besides the server, it asks ZodUI in the guild (Core\Bus.lua): each character's recipes are kept when its
-- profession window opens, and a guild member with ZodUI answers with their characters in your guild who know it,
-- alts too. Your own characters are said at once.

local M = ns:NewModule("crafters", {
    title = "Guild crafters",
    desc = "Finds who in your guild knows a recipe: /zod crafters and a shift-clicked recipe (or its spell id and the "
        .. "profession). Online members first, click a name to whisper.",
    defaults = { enabled = true },
    options = {
        { type = "note", text = "/zod crafters [Recipe: Mooncloth Bag], or /zod crafters 18445 tailoring. /zod crafters "
            .. "test shows what the game answers, to check that it works on your realm.", lines = 3 },
    },
})

-- Classic profession skill lines, for when the recipe alone does not say which one it is.
local SKILL = {
    alchemy = 171, blacksmithing = 164, enchanting = 333, engineering = 202, leatherworking = 165, tailoring = 197,
    cooking = 185, ["first aid"] = 129, firstaid = 129, mining = 186, jewelcrafting = 755, inscription = 773, fishing = 356,
}
local WAIT = 5        -- seconds to wait for the server's answer
local KEEP = 100      -- answers kept
local SHOW_MOST = 20  -- names shown in chat
local BOOK_MOST = 3000 -- recipes kept per character
local NAMES_MOST = 6   -- characters in one answer

local pending -- { recipe, skill, name, at }

local function Plain(v)
    if issecretvalue and issecretvalue(v) then return nil end
    return v
end

local function Cache()
    ns.db.crafters = ns.db.crafters or {}
    return ns.db.crafters
end

local function RecipeName(id)
    local info = C_TradeSkillUI and C_TradeSkillUI.GetRecipeInfo and C_TradeSkillUI.GetRecipeInfo(id)
    local name = type(info) == "table" and Plain(info.name)
    if type(name) ~= "string" or name == "" then
        name = Plain(C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id))
    end
    return type(name) == "string" and name ~= "" and name or ("recipe " .. id)
end

-- The profession a recipe belongs to, from the game if it says.
local function SkillOf(recipe)
    local get = C_TradeSkillUI and C_TradeSkillUI.GetProfessionInfoByRecipeID
    local info = get and get(recipe)
    if type(info) ~= "table" then return nil end
    local id = Plain(info.parentProfessionID) or Plain(info.professionID)
    return type(id) == "number" and id > 0 and id or nil
end

-- From what was typed: a recipe link (trade, enchant or spell), or a spell id; and a profession name.
-- Returns recipe, skill, or nil and what is wrong.
function M.Parse(arg)
    arg = (arg or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local recipe, skill
    local tradeSpell, tradeSkill = arg:match("|Htrade:[^:|]*:(%d+):(%d+)")
    if tradeSpell then recipe, skill = tonumber(tradeSpell), tonumber(tradeSkill) end
    recipe = recipe or tonumber(arg:match("|Henchant:(%d+)") or arg:match("|Hspell:(%d+)") or "")
    local rest = arg:gsub("|c%x+|H.-|h.-|h|r", ""):gsub("|H.-|h.-|h", "")
    if not recipe then
        local n = rest:match("^%s*(%d+)")
        recipe = tonumber(n or "")
        if n then rest = rest:gsub("^%s*%d+", "", 1) end
    end
    if not recipe then return nil, "Shift-click a recipe into the command, or type its spell id." end
    local word = rest:lower():gsub("^%s+", ""):gsub("%s+$", "")
    if word ~= "" then
        skill = SKILL[word]
        if not skill then return nil, "'" .. word .. "' is not a profession. Try tailoring, alchemy, cooking..." end
    end
    skill = skill or SkillOf(recipe)
    if not skill then return nil, "Which profession is it? Add its name, for example /zod crafters " .. recipe .. " tailoring." end
    return recipe, skill
end

---------------------------------------------------------------------------
-- The recipe book: which of your characters know what
---------------------------------------------------------------------------

local function Book()
    ns.db.recipeBook = ns.db.recipeBook or {}
    return ns.db.recipeBook
end

local function GuildName()
    local name = GetGuildInfo and Plain(GetGuildInfo("player"))
    return type(name) == "string" and name ~= "" and name or nil
end

-- Reads the open profession window, unless it shows someone else's recipes.
function M.Record()
    local ui = C_TradeSkillUI
    if not (ui and ui.GetAllRecipeIDs and ui.GetRecipeInfo) then return end
    if (ui.IsTradeSkillLinked and ui.IsTradeSkillLinked()) or (ui.IsTradeSkillGuild and ui.IsTradeSkillGuild())
        or (ui.IsNPCCrafting and ui.IsNPCCrafting()) then return end
    local key = (ns.MyName() or "?") .. "-" .. (GetRealmName and GetRealmName() or "")
    local entry = Book()[key] or { known = {} }
    local n = 0
    for _ in pairs(entry.known) do n = n + 1 end
    for _, id in ipairs(ui.GetAllRecipeIDs() or {}) do
        local info = ui.GetRecipeInfo(id)
        if type(id) == "number" and type(info) == "table" and Plain(info.learned) and not entry.known[id] and n < BOOK_MOST then
            entry.known[id] = true
            n = n + 1
        end
    end
    entry.name, entry.guild, entry.at = ns.MyName(), GuildName(), time()
    Book()[key] = entry
end

local recording
local function RecordSoon()
    if recording then return end
    recording = true
    ns.After(0.5, function()
        recording = false
        if M.enabled then M.Record() end
    end)
end
M:On("TRADE_SKILL_SHOW", RecordSoon)
M:On("TRADE_SKILL_LIST_UPDATE", RecordSoon)

-- Your characters in your guild who know a recipe, the one you play first.
function M.Mine(recipe)
    local me, guild, names = ns.MyName(), GuildName(), {}
    for _, e in pairs(Book()) do
        if e.known[recipe] and e.name and (e.name == me or (guild and e.guild == guild)) then names[#names + 1] = e.name end
    end
    table.sort(names, function(a, b)
        if (a == me) ~= (b == me) then return a == me end
        return a < b
    end)
    return names
end

local function PlayerLink(name)
    return "|Hplayer:" .. name .. "|h[" .. Ambiguate(name, "none") .. "]|h"
end

local function Say(entry)
    local online, offline = {}, {}
    for _, m in ipairs(entry.members) do
        if m.online then online[#online + 1] = m.name else offline[#offline + 1] = m.name end
    end
    if #entry.members == 0 then
        ns.Print("no one in your guild knows " .. entry.name .. ".")
        return
    end
    local shown = {}
    for _, name in ipairs(online) do
        if #shown < SHOW_MOST then shown[#shown + 1] = "|cff40d040" .. PlayerLink(name) .. "|r" end
    end
    for _, name in ipairs(offline) do
        if #shown < SHOW_MOST then shown[#shown + 1] = "|cff999999" .. PlayerLink(name) .. "|r" end
    end
    local more = #entry.members - #shown
    ns.Print(entry.name .. ": " .. #entry.members .. " in your guild know it, " .. #online .. " online. "
        .. table.concat(shown, ", ") .. (more > 0 and (" and " .. more .. " more") or "") .. ". Click a name to whisper.")
end

function M:Query(recipe, skill)
    if not (IsInGuild and IsInGuild()) then return false, "you are not in a guild." end
    local query = C_GuildInfo and C_GuildInfo.QueryGuildMembersForRecipe
    if not query then return false, "this client has no guild recipe lookup." end
    local updated = Plain(query(skill, recipe))
    if type(updated) == "number" and updated > 0 then recipe = updated end
    pending = { recipe = recipe, skill = skill, name = RecipeName(recipe), at = GetTime() }
    local asked = pending
    ns.After(WAIT, function()
        if pending == asked then
            pending = nil
            ns.Print("no answer about " .. asked.name .. " from the server. Guild recipe lookups may not work on this "
                .. "realm: /zod crafters test shows what the game returns.")
        end
    end)
    return true
end

M:On("GUILD_RECIPE_KNOWN_BY_MEMBERS", function()
    if not pending then return end
    local asked = pending
    pending = nil
    local info = GetGuildRecipeInfoPostQuery
    local _, recipe, count = nil, nil, nil
    if info then _, recipe, count = info() end
    count = Plain(count)
    if type(count) ~= "number" then count = 0 end
    local members = {}
    for i = 1, GetGuildRecipeMember and math.min(count, 500) or 0 do
        local name, online = GetGuildRecipeMember(i) -- not `fn and fn(i)`: that keeps only the first value
        name = Plain(name)
        if type(name) == "string" and name ~= "" then members[#members + 1] = { name = name, online = Plain(online) and true or false } end
    end
    table.sort(members, function(a, b)
        if a.online ~= b.online then return a.online end
        return a.name < b.name
    end)
    local entry = { name = asked.name, skill = asked.skill, at = time(), members = members }
    local cache = Cache()
    cache[asked.recipe] = entry
    local n, oldest, oldestAt = 0, nil, nil
    for id, e in pairs(cache) do
        n = n + 1
        if not oldestAt or e.at < oldestAt then oldest, oldestAt = id, e.at end
    end
    if n > KEEP and oldest then cache[oldest] = nil end
    Say(entry)
end)

---------------------------------------------------------------------------
-- Asking ZodUI in the guild
---------------------------------------------------------------------------

local Bus = ns.Bus
local open = {} -- question id -> { recipe, name, answers }

local function Finish(id)
    local q = open[id]
    open[id] = nil
    if not q or #q.answers == 0 then return end
    local shown = {}
    for _, a in ipairs(q.answers) do
        local alts = {}
        for i = 2, #a.names do alts[#alts + 1] = a.names[i] end
        shown[#shown + 1] = "|cff40d040" .. PlayerLink(a.names[1]) .. "|r" .. (#alts > 0 and (" (alts: " .. table.concat(alts, ", ") .. ")") or "")
    end
    ns.Print(q.name .. ", from ZodUI in your guild: " .. table.concat(shown, "; ") .. ".")
end

-- Asks the guild's ZodUI; returns whether it could.
function M:AskGuild(recipe)
    if not Bus.On() then return false end
    local id = Bus.NewID()
    open[id] = { recipe = recipe, name = RecipeName(recipe), answers = {}, from = {} }
    Bus.Send("C", { id, recipe })
    ns.After(WAIT, function() Finish(id) end)
    return true
end

Bus.Listen("C", function(_, f, channel, full)
    local guild = ns.modules.guild
    if channel ~= "GUILD" or not (guild and guild.db.answer) then return end
    local recipe = tonumber(f[2] or "")
    if not (recipe and recipe > 0 and (f[1] or ""):match("^%d+$")) then return end
    local names = M.Mine(recipe)
    if #names == 0 then return end
    local list = {}
    for i = 1, math.min(#names, NAMES_MOST) do list[i] = names[i] end
    Bus.Send("c", { f[1], recipe, table.concat(list, ",") }, full)
end, M)

Bus.Listen("c", function(name, f, channel)
    local q = channel == "WHISPER" and open[f[1]]
    if not q or tonumber(f[2] or "") ~= q.recipe or q.from[name] or #q.answers >= SHOW_MOST then return end
    local names = { name } -- the one answering first, then their alts
    for n in (f[3] or ""):gmatch("[^,]+") do
        n = n:gsub("[%c|~%s]", ""):sub(1, 24)
        if n ~= "" and n ~= name and #names <= NAMES_MOST then names[#names + 1] = n end
    end
    q.from[name] = true
    q.answers[#q.answers + 1] = { names = names }
end, M)

-- What the game returns, raw, to check the lookup on this realm.
local function Test(arg)
    local function show(label, ...)
        local parts = {}
        for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
        print("  " .. label .. ": " .. (#parts > 0 and table.concat(parts, ", ") or "(nothing)"))
    end
    ns.Print("guild crafters test:")
    show("in a guild", IsInGuild and IsInGuild())
    show("QueryGuildMembersForRecipe", type(C_GuildInfo and C_GuildInfo.QueryGuildMembersForRecipe))
    show("GetGuildRecipeInfoPostQuery", type(GetGuildRecipeInfoPostQuery))
    show("GetGuildRecipeMember", type(GetGuildRecipeMember))
    if CanViewGuildRecipes then show("CanViewGuildRecipes(197)", pcall(CanViewGuildRecipes, 197)) end
    if GetNumGuildTradeSkill then show("GetNumGuildTradeSkill", pcall(GetNumGuildTradeSkill)) end
    if GetGuildTradeSkillInfo then show("GetGuildTradeSkillInfo(1)", pcall(GetGuildTradeSkillInfo, 1)) end
    if GetGuildRecipeInfoPostQuery then show("last answer", pcall(GetGuildRecipeInfoPostQuery)) end
    local recipe, skill = M.Parse(arg ~= "" and arg or "3915 tailoring") -- Brown Linen Shirt by default
    if recipe and C_GuildInfo and C_GuildInfo.QueryGuildMembersForRecipe and IsInGuild and IsInGuild() then
        print("  asking about " .. RecipeName(recipe) .. " (" .. recipe .. ", skill line " .. skill .. "); the answer follows if the server sends one.")
        M:Query(recipe, skill)
    end
end

-- /zod crafters <recipe> [profession], /zod crafters test, /zod crafters list
function M:Slash(arg)
    local verb, rest = arg:match("^(%S*)%s*(.-)$")
    verb = verb:lower()
    if verb == "test" then
        Test(rest)
        return
    end
    if verb == "" or verb == "list" then
        local list = {}
        for _, e in pairs(Cache()) do list[#list + 1] = e end
        if #list == 0 then
            ns.Print("use /zod crafters and shift-click a recipe, or /zod crafters 18445 tailoring.")
            return
        end
        table.sort(list, function(a, b) return a.at > b.at end)
        ns.Print("recipes asked about:")
        for i = 1, math.min(#list, 15) do
            local e = list[i]
            print("  " .. e.name .. "  |cff999999" .. #e.members .. " know it, asked " .. ns.When(e.at, true) .. "|r")
        end
        return
    end
    local recipe, skill = M.Parse(arg)
    if not recipe then
        ns.Print(skill)
        return
    end
    local mine = M.Mine(recipe)
    if #mine > 0 then ns.Print("your characters who know " .. RecipeName(recipe) .. ": " .. table.concat(mine, ", ") .. ".") end
    local ok, said = self:Query(recipe, skill)
    local asked = self:AskGuild(recipe)
    if not ok and not asked then ns.Print(said) return end
    ns.Print("asking your guild who knows " .. RecipeName(recipe) .. "...")
end

function M:Find(part, add, has)
    for _, e in pairs(Cache()) do
        if has(e.name) then add("Crafters", e.name, #e.members .. " in your guild know it", "settings", "crafters") end
    end
end
