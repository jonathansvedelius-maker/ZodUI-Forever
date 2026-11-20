local ADDON, ns = ...

-- Hand-me-downs: a Bind on Equip item you loot that is no upgrade for you, but is one
-- for another of your characters on this realm and side, is said, kept on a list, and
-- named again at the mailbox while it is still in your bags. Its tooltip names the one
-- it is for.
--
-- Each character's gear is kept as it logs in and changes gear. The scores use Forever
-- Leveling BiS's stat weights for the other character's class and level
-- (ForeverLevelingBiS_API.GetWeights), so nothing is said without that addon.

local M = ns:NewModule("handouts", {
    title = "Hand-me-downs",
    desc = "A Bind on Equip item that is no upgrade for you but is one for another of your characters is said, and named again at the mailbox. Needs Forever Leveling BiS for the stat weights.",
    needs = { "ForeverLevelingBiS" }, needsAll = true,
    defaults = { enabled = true, quality = 2, margin = 5 },
    options = {
        { type = "cycle", key = "quality", label = "From this quality", choices = { { 2, "Green and better" }, { 3, "Blue and better" }, { 4, "Purple only" } } },
        { type = "step", key = "margin", label = "Better by at least this many percent", min = 0, max = 30, step = 5 },
    },
})

local SETTLE = 1.5
local KEEP = 40
local SLOTS = { 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18 }

-- The game's stat names -> Forever Leveling BiS's weight keys (its Equipped.lua).
local STATS = {
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

-- Where an item goes: its slots, by the game's equip location.
local WHERE = {
    INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 }, INVTYPE_CHEST = { 5 }, INVTYPE_ROBE = { 5 },
    INVTYPE_WAIST = { 6 }, INVTYPE_LEGS = { 7 }, INVTYPE_FEET = { 8 }, INVTYPE_WRIST = { 9 }, INVTYPE_HAND = { 10 },
    INVTYPE_FINGER = { 11, 12 }, INVTYPE_TRINKET = { 13, 14 }, INVTYPE_CLOAK = { 15 },
    INVTYPE_WEAPON = { 16 }, INVTYPE_WEAPONMAINHAND = { 16 }, INVTYPE_2HWEAPON = { 16 },
    INVTYPE_SHIELD = { 17 }, INVTYPE_HOLDABLE = { 17 }, INVTYPE_WEAPONOFFHAND = { 17 },
    INVTYPE_RANGED = { 18 }, INVTYPE_RANGEDRIGHT = { 18 }, INVTYPE_THROWN = { 18 },
}

-- Classic proficiencies. Armour subclass: 1 cloth, 2 leather, 3 mail, 4 plate, 6 shield (0: rings,
-- necks, trinkets). Mail and plate open at 40 for the classes that move up to them.
local ARMOUR = {
    WARRIOR = { [2] = 1, [3] = 1, [4] = 40, [6] = 1 }, PALADIN = { [2] = 1, [3] = 1, [4] = 40, [6] = 1 },
    HUNTER = { [2] = 1, [3] = 40 }, SHAMAN = { [2] = 1, [3] = 40, [6] = 1 }, ROGUE = { [2] = 1 }, DRUID = { [2] = 1 },
    MAGE = {}, PRIEST = {}, WARLOCK = {},
}
-- Weapon subclass: 0/1 axe, 2 bow, 3 gun, 4/5 mace, 6 polearm, 7/8 sword, 10 staff, 13 fist, 15 dagger,
-- 16 thrown, 18 crossbow, 19 wand.
local WEAPONS = {
    WARRIOR = { 0, 1, 2, 3, 4, 5, 6, 7, 8, 10, 13, 15, 16, 18 }, PALADIN = { 0, 1, 4, 5, 6, 7, 8 },
    HUNTER = { 0, 1, 2, 3, 6, 7, 8, 10, 13, 15, 16, 18 }, ROGUE = { 2, 3, 4, 7, 13, 15, 16, 18 },
    PRIEST = { 4, 10, 15, 19 }, SHAMAN = { 0, 1, 4, 5, 10, 13, 15 }, MAGE = { 7, 10, 15, 19 },
    WARLOCK = { 7, 10, 15, 19 }, DRUID = { 4, 5, 10, 13, 15 },
}
local CAN = {}
for class, list in pairs(WEAPONS) do
    CAN[class] = {}
    for _, sub in ipairs(list) do CAN[class][sub] = true end
end

local function Info(link)
    local get = C_Item and C_Item.GetItemInfo or GetItemInfo
    if not get then return nil end
    return get(link)
end

function M.CanWear(class, level, classID, subID)
    if classID == 4 then
        if subID == 0 or subID == 1 then return true end
        local from = ARMOUR[class] and ARMOUR[class][subID]
        return from ~= nil and (level or 1) >= from
    elseif classID == 2 then
        return CAN[class] ~= nil and CAN[class][subID] == true
    end
    return false
end

function M.Score(link, weights)
    local stats = link and ((C_Item and C_Item.GetItemStats) or GetItemStats)
    stats = stats and stats(link)
    if type(stats) ~= "table" or type(weights) ~= "table" then return 0 end
    local score = 0
    for key, value in pairs(stats) do
        local w = STATS[key] and weights[STATS[key]]
        if type(w) == "number" and type(value) == "number" then score = score + w * value end
    end
    return score
end

local function Weights(class, level)
    local api = ForeverLevelingBiS_API
    if type(api) ~= "table" or type(api.GetWeights) ~= "function" then return nil end
    local ok, weights = pcall(api.GetWeights, class, nil, level)
    return ok and type(weights) == "table" and weights or nil
end

-- How much better `link` is for `char` than what it wears in that slot, in percent, and true when it
-- wears nothing there; nil when it is no better.
function M:Gain(char, link)
    local instant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
    if not (instant and char and char.class and char.gear) then return nil end
    local _, _, _, equip, _, classID, subID = instant(link)
    local slots = WHERE[equip]
    if not slots or not M.CanWear(char.class, char.level, classID, subID) then return nil end
    local _, _, _, _, req = Info(link)
    if (tonumber(req) or 0) > (char.level or 1) + 3 then return nil end
    local weights = Weights(char.class, char.level)
    if not weights then return nil end
    local new = M.Score(link, weights)
    if new <= 0 then return nil end
    local old
    for _, slot in ipairs(slots) do
        local s = M.Score(char.gear[slot], weights)
        old = old and math.min(old, s) or s
    end
    old = old or 0
    if old <= 0 then return 100, true end
    local pct = (new - old) / old * 100
    return pct >= self.db.margin and math.floor(pct + 0.5) or nil
end

-- The best other character for `link`: char, percent.
function M:For(link)
    local me = ns.char
    local best, bestPct, bestEmpty
    for _, char in pairs(ns.db.chars or {}) do
        if char ~= me and char.realm == (me and me.realm) and (not char.faction or not (me and me.faction) or char.faction == me.faction) then
            local pct, empty = self:Gain(char, link)
            if pct and (not bestPct or pct > bestPct) then best, bestPct, bestEmpty = char, pct, empty end
        end
    end
    return best, bestPct, bestEmpty
end

local function List()
    ns.db.handouts = ns.db.handouts or {}
    return ns.db.handouts
end

local function KeepGear()
    if not (ns.char and GetInventoryItemLink) then return end
    local gear = {}
    for _, slot in ipairs(SLOTS) do gear[slot] = GetInventoryItemLink("player", slot) end
    ns.char.gear = gear
    if UnitFactionGroup then ns.char.faction = UnitFactionGroup("player") end
end

function M:OnEnable() KeepGear() end
M:On("PLAYER_EQUIPMENT_CHANGED", function() KeepGear() end)

function M:Consider(link)
    local name, _, quality, _, _, _, _, _, _, _, _, _, _, bind = Info(link)
    if not name or (quality or 0) < self.db.quality or bind ~= 2 then return nil end
    local shout = ns.modules.shout
    if shout and shout.Upgrade and shout.Upgrade(link) then return nil end -- yours to wear
    local char, pct, empty = self:For(link)
    if not char then return nil end
    local list = List()
    table.insert(list, 1, { link = link, id = tonumber(link:match("item:(%d+)")), to = char.name, at = time() })
    while #list > KEEP do table.remove(list) end
    ns.Alert("Hand-me-down: " .. link .. " is " .. (empty and "an upgrade (nothing worn there)" or ("+" .. pct .. "%")) .. " for " .. char.name
        .. " (" .. (char.className or char.class) .. " " .. (char.level or "?") .. ").")
    return char, pct
end

M:On("CHAT_MSG_LOOT", function(self, _, msg)
    local loot = ns.modules.loot
    if not (loot and loot.Parse) then return end
    local link, _, _, _, kind = loot.Parse(msg)
    if not link or kind == "created" then return end
    ns.After(SETTLE, function() if self.enabled then ns.Guard("hand-me-down", self.Consider, self, link) end end)
end)

-- Still in your bags: the ones to mail.
function M:Waiting()
    local count = C_Item and C_Item.GetItemCount or GetItemCount
    local out = {}
    for _, h in ipairs(List()) do
        if h.id and count and (count(h.id) or 0) > 0 then out[#out + 1] = h end
    end
    return out
end

local saidFor -- the list as it was last said: the same list is not said at every mailbox
M:On("MAIL_SHOW", function(self)
    local list = self:Waiting()
    local parts = {}
    for _, h in ipairs(list) do parts[#parts + 1] = tostring(h.link) .. ">" .. tostring(h.to) end
    table.sort(parts)
    local said = table.concat(parts, ";")
    if #list == 0 or said == saidFor then return end
    saidFor = said
    ns.Print("to mail to your characters:")
    for _, h in ipairs(list) do print("  " .. h.link .. " -> " .. h.to) end
end)

function M:ItemTooltip(tip, id)
    for _, h in ipairs(List()) do
        if h.id == id then
            tip:AddLine("Hand-me-down for " .. h.to, 0.4, 0.73, 1)
            return
        end
    end
end

function M:Slash(arg)
    local list = self:Waiting()
    if #list == 0 then ns.Print("no hand-me-downs in your bags.") return end
    ns.Print("hand-me-downs in your bags:")
    for _, h in ipairs(list) do print("  " .. h.link .. " -> " .. h.to) end
end
