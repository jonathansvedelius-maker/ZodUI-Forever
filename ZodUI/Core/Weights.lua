local ADDON, ns = ...

-- Stat weights: what an item is worth to a character, for Hand-me-downs and Loot shout's upgrades. Three sources,
-- the first that is there wins:
--   1. Forever Leveling BiS (ForeverLevelingBiS_API.GetWeights): made for leveling, by class and level.
--   2. NaowhForever's stat weights (NaowhForever.StatWeights): simulated on Forever, by spec; the player's own
--      changes in its window count.
--   3. ZodUI's own: worked out from how the game turns stats into damage (below), so they need no other addon.
-- Nothing of the other addons is copied: their weights are asked for in the game.
--
-- ns.Weights.Scorer(class, level, mine) -> function(link) -> score, and the name of the source.
-- class is the class file ("ROGUE"); mine is true for the character you play (its own spec and measured stats).

local W = {}
ns.Weights = W

local function Num(v)
    if issecretvalue and issecretvalue(v) then return nil end
    return type(v) == "number" and v or nil
end

-- The item's stats, by the game's keys (ITEM_MOD_AGILITY_SHORT = 10, ...).
function W.Stats(link)
    local get = (C_Item and C_Item.GetItemStats) or GetItemStats
    if not (link and get) then return nil end
    local ok, stats = pcall(get, link)
    return ok and type(stats) == "table" and stats or nil
end

---------------------------------------------------------------------------
-- 1. Forever Leveling BiS
---------------------------------------------------------------------------

-- The game's stat names -> Forever Leveling BiS's weight keys (its Equipped.lua).
local FLB_KEYS = {
    ITEM_MOD_STRENGTH_SHORT = "str", ITEM_MOD_AGILITY_SHORT = "agi", ITEM_MOD_STAMINA_SHORT = "sta",
    ITEM_MOD_INTELLECT_SHORT = "int", ITEM_MOD_SPIRIT_SHORT = "spi",
    ITEM_MOD_ATTACK_POWER_SHORT = "atkpwr", ITEM_MOD_RANGED_ATTACK_POWER_SHORT = "rgdatkpwr",
    ITEM_MOD_FERAL_ATTACK_POWER_SHORT = "feratkpwr", ITEM_MOD_MELEE_ATTACK_POWER_SHORT = "feratkpwr",
    ITEM_MOD_SPELL_POWER_SHORT = "splpwr", ITEM_MOD_SPELL_DAMAGE_DONE_SHORT = "spldmg",
    ITEM_MOD_SPELL_HEALING_DONE_SHORT = "splheal", ITEM_MOD_SPELL_PENETRATION_SHORT = "splpen",
    ITEM_MOD_ARCANE_DAMAGE_DONE_SHORT = "arcsplpwr", ITEM_MOD_FIRE_DAMAGE_DONE_SHORT = "firsplpwr",
    ITEM_MOD_FROST_DAMAGE_DONE_SHORT = "frosplpwr", ITEM_MOD_HOLY_DAMAGE_DONE_SHORT = "holsplpwr",
    ITEM_MOD_NATURE_DAMAGE_DONE_SHORT = "natsplpwr", ITEM_MOD_SHADOW_DAMAGE_DONE_SHORT = "shasplpwr",
    ITEM_MOD_DEFENSE_SKILL_RATING_SHORT = "defrtng", ITEM_MOD_BLOCK_VALUE_SHORT = "block",
    ITEM_MOD_MANA_REGENERATION_SHORT = "manargn", ITEM_MOD_POWER_REGEN0_SHORT = "manargn",
    ITEM_MOD_HEALTH_REGEN_SHORT = "healthrgn", RESISTANCE0_NAME = "armor", ITEM_MOD_DAMAGE_PER_SECOND_SHORT = "dps",
}

local function FromLevelingBiS(class, level)
    local api = ForeverLevelingBiS_API
    if type(api) ~= "table" or type(api.GetWeights) ~= "function" then return nil end
    local ok, weights = pcall(api.GetWeights, class, nil, level)
    if not (ok and type(weights) == "table") then return nil end
    return function(stats)
        local score = 0
        for key, value in pairs(stats) do
            local w = FLB_KEYS[key] and Num(weights[FLB_KEYS[key]])
            if w and Num(value) then score = score + w * value end
        end
        return score
    end
end

---------------------------------------------------------------------------
-- 2. NaowhForever's stat weights
---------------------------------------------------------------------------

-- Which of a class's three talent trees it most likely levels in, for a character whose spec ZodUI cannot read.
W.LEVELING_TREE = { WARRIOR = 1, PALADIN = 3, HUNTER = 1, ROGUE = 2, PRIEST = 3, SHAMAN = 2, MAGE = 3, WARLOCK = 1, DRUID = 2 }

local function FromNaowh(class, mine)
    local N = _G.NaowhForever
    local SW = type(N) == "table" and type(N.StatWeights) == "table" and N.StatWeights
    if not (SW and type(SW.For) == "function" and type(SW.KeyWorth) == "function") then return nil end
    local key
    if mine and type(SW.ActiveSpec) == "function" then
        local ok, active = pcall(SW.ActiveSpec)
        if ok and type(active) == "string" then key = active end
    end
    if not key and type(SW.TreeSpec) == "function" then
        local ok, tree = pcall(SW.TreeSpec, class, W.LEVELING_TREE[class] or 1)
        if ok and type(tree) == "string" then key = tree end
    end
    if not key then return nil end
    local ok, weights = pcall(SW.For, key)
    if not (ok and type(weights) == "table") then return nil end
    return function(stats)
        local score = 0
        for gameKey, value in pairs(stats) do
            if Num(value) then
                local fine, worth = pcall(SW.KeyWorth, gameKey, value, weights)
                if fine and Num(worth) then score = score + worth end
            end
        end
        return score
    end
end

---------------------------------------------------------------------------
-- 3. ZodUI's own
---------------------------------------------------------------------------
-- Everything in one unit per kind of fighter: attack power for melee, ranged attack power for hunters, spell
-- damage for casters. How the game turns stats into those (classic rules, which Forever keeps):
--   attack power per Strength and Agility, by class (the game says it for your own class: GetAttackPowerForStat);
--   Agility per 1% crit, by class at 60, fewer at lower levels;
--   1 weapon DPS = 14 attack power (weapon damage gains AP / 14 a second);
--   1% crit is worth about a third of a point of attack power per level (20 at 60).
-- Stamina, armour, Intellect and Spirit are leveling comforts: priced low but not at nothing.

local ROLE = { WARRIOR = "melee", PALADIN = "melee", SHAMAN = "melee", DRUID = "melee", ROGUE = "melee",
    HUNTER = "ranged", MAGE = "caster", WARLOCK = "caster", PRIEST = "caster" }
local AP_PER = { -- attack power per point of { Strength, Agility }
    WARRIOR = { 2, 0 }, PALADIN = { 2, 0 }, SHAMAN = { 2, 0 }, DRUID = { 2, 0 }, ROGUE = { 1, 1 }, HUNTER = { 0, 2 } }
local AGI_PER_CRIT = { WARRIOR = 20, PALADIN = 20, SHAMAN = 20, DRUID = 20, ROGUE = 29, HUNTER = 53 }
local AP_PER_DPS = 14

-- Attack power per Strength and Agility for the class you play, as the game says it.
local function Measured()
    if type(GetAttackPowerForStat) ~= "function" then return nil end
    local ok1, str = pcall(GetAttackPowerForStat, 1, 100)
    local ok2, agi = pcall(GetAttackPowerForStat, 2, 100)
    str, agi = ok1 and Num(str), ok2 and Num(agi)
    if str and agi and str >= 0 and agi >= 0 then return str / 100, agi / 100 end
end

-- Own weights by the game's stat keys, for a class at a level.
function W.Own(class, level, mine)
    level = math.max(1, math.min(60, tonumber(level) or 1))
    local role = ROLE[class] or "melee"
    local critWorth = math.max(2, level / 3) -- 1% crit, in attack power
    local w = { ITEM_MOD_STAMINA_SHORT = 0.5, RESISTANCE0_NAME = 0.02 }
    if role == "caster" then
        local spell = 1
        w.ITEM_MOD_SPELL_POWER_SHORT, w.ITEM_MOD_SPELL_DAMAGE_DONE_SHORT = spell, spell
        for _, school in ipairs({ "ARCANE", "FIRE", "FROST", "NATURE", "SHADOW", "HOLY" }) do
            w["ITEM_MOD_" .. school .. "_DAMAGE_DONE_SHORT"] = 0.6 -- one school: most of a caster's spells, not all
        end
        w.ITEM_MOD_SPELL_HEALING_DONE_SHORT = class == "PRIEST" and 0.3 or 0.1
        w.ITEM_MOD_INTELLECT_SHORT, w.ITEM_MOD_SPIRIT_SHORT = 0.4, class == "PRIEST" and 0.45 or 0.35
        w.ITEM_MOD_MANA_REGENERATION_SHORT, w.ITEM_MOD_POWER_REGEN0_SHORT = 0.8, 0.8
        w.ITEM_MOD_STAMINA_SHORT, w.RESISTANCE0_NAME = 0.35, 0.005
        w.ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 2 -- a wand
        return w
    end
    local per = AP_PER[class] or { 2, 0 }
    local str, agi = per[1], per[2]
    if mine then
        local s, a = Measured()
        if s then str, agi = s, a end
    end
    local agiPerCrit = (AGI_PER_CRIT[class] or 20) * math.max(10, level) / 60
    w.ITEM_MOD_STRENGTH_SHORT = str
    w.ITEM_MOD_AGILITY_SHORT = agi + critWorth / agiPerCrit
    w.ITEM_MOD_DAMAGE_PER_SECOND_SHORT = AP_PER_DPS
    w.ITEM_MOD_CRIT_RATING_SHORT = critWorth / 14 -- ratings: 14 to 1% crit, 10 to 1% hit (NaowhForever's numbers)
    w.ITEM_MOD_HIT_RATING_SHORT = critWorth / 10
    if role == "ranged" then
        w.ITEM_MOD_RANGED_ATTACK_POWER_SHORT, w.ITEM_MOD_ATTACK_POWER_SHORT = 1, 0.3
        w.ITEM_MOD_STRENGTH_SHORT = 0.1
        w.ITEM_MOD_INTELLECT_SHORT, w.ITEM_MOD_SPIRIT_SHORT = 0.3, 0.05
    else
        w.ITEM_MOD_ATTACK_POWER_SHORT = 1
        local hybrid = class == "PALADIN" or class == "SHAMAN" or class == "DRUID"
        w.ITEM_MOD_INTELLECT_SHORT, w.ITEM_MOD_SPIRIT_SHORT = hybrid and 0.2 or 0.05, 0.05
    end
    return w
end

local function FromOwn(class, level, mine)
    local w = W.Own(class, level, mine)
    return function(stats)
        local score = 0
        for key, value in pairs(stats) do
            if w[key] and Num(value) then score = score + w[key] * value end
        end
        return score
    end
end

---------------------------------------------------------------------------

-- The scorer for a character: function(link) -> score (0 for an item it cannot read), and its source's name.
function W.Scorer(class, level, mine)
    local fn, source = FromLevelingBiS(class, level), "Forever Leveling BiS"
    if not fn then fn, source = FromNaowh(class, mine), "NaowhForever" end
    if not fn then fn, source = FromOwn(class, level, mine), "ZodUI" end
    return function(link)
        local stats = W.Stats(link)
        if not stats then return 0 end
        local ok, score = pcall(fn, stats)
        return ok and Num(score) or 0
    end, source
end
