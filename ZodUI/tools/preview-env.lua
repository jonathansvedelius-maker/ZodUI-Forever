-- The game functions ZodUI needs that Undead Route's browser preview does not
-- have. The preview runs this before ZodUI's own files. Everything here is a
-- made-up character: enough for every page to have something to show.
--   cd ../UndeadRoute/tools && ADDON_DIR=../../ZodUI PORT=8378 node preview/server.js
local env = ...
local js = require "js"
local window = js.global

local started = os.time()
local money = 1234567
local xp, xpMax, rested = 8200, 21300, 4100

function time() return os.time() end
function date(fmt, t) return os.date(fmt, t) end
function GetTime() return window.performance:now() / 1000 end

function UnitName() return "Zod" end
function GetRealmName() return "Forever" end
function UnitXP() return xp end
function UnitXPMax() return xpMax end
function GetXPExhaustion() return rested end
function IsResting() return false end
function GetMoney() return money end
function GetSubZoneText() return "" end
function IsShiftKeyDown() return false end
function InCombatLockdown() return false end
function GetFramerate() return 60 end
function GetNetStats() return 1, 1, 38, 41 end
function GetCursorPosition() return 0, 0 end
function GetInventoryItemDurability(slot)
    if slot == 1 then return 42, 60 end
    if slot == 5 then return 71, 100 end
end
function GetProfessions() return 1, 2 end
function GetProfessionInfo(i)
    if i == 1 then return "Mining", nil, 150, 225 end
    return "Engineering", nil, 140, 225
end

C_AddOns = { IsAddOnLoaded = function() return false end }
C_QuestLog.GetNumQuestLogEntries = function() return 15, 12 end
C_QuestLog.GetMaxNumQuestsCanAccept = function() return 25 end
local realMap = C_Map.GetBestMapForUnit
C_Map.GetPlayerMapPosition = function()
    if not realMap() then return nil end
    return { GetXY = function() return 0.6213, 0.2051 end }
end
C_Container = {
    GetContainerNumSlots = function(bag) return bag == 0 and 16 or (bag <= 2 and 12 or 0) end,
    GetContainerNumFreeSlots = function(bag) return bag == 0 and 5 or (bag == 1 and 6 or 0) end,
    GetContainerItemInfo = function(bag, slot)
        local item = bag == 0 and ({ { 2589, "Linen Cloth", 14, 1 }, { 4865, "Ruined Pelt", 9, 0 }, { 2775, "Silver Ore", 3, 1 },
            { 6948, "Hearthstone", 1, 1 }, { 1206, "Moss Agate", 1, 2 } })[slot]
        if not item then return nil end
        return { itemID = item[1], hyperlink = "|Hitem:" .. item[1] .. "|h[" .. item[2] .. "]|h", stackCount = item[3], quality = item[4] }
    end,
    GetItemCooldown = function() return GetTime() - 600, 3600, 1 end,
}

C_Item = C_Item or {}
C_Item.GetItemCount = function(id)
    return ({ [2589] = 14, [4865] = 9, [2775] = 3, [6948] = 1, [1206] = 1 })[id] or 0
end

local factions = {
    { name = "Horde", isHeader = true },
    { factionID = 68, name = "Undercity", reaction = 6, currentReactionThreshold = 9000, nextReactionThreshold = 21000, currentStanding = 12400 },
    { factionID = 76, name = "Orgrimmar", reaction = 5, currentReactionThreshold = 3000, nextReactionThreshold = 9000, currentStanding = 5150 },
    { factionID = 81, name = "Thunder Bluff", reaction = 5, currentReactionThreshold = 3000, nextReactionThreshold = 9000, currentStanding = 3900 },
    { name = "Steamwheedle Cartel", isHeader = true },
    { factionID = 21, name = "Booty Bay", reaction = 4, currentReactionThreshold = 0, nextReactionThreshold = 3000, currentStanding = 1250 },
    { factionID = 470, name = "Ratchet", reaction = 4, currentReactionThreshold = 0, nextReactionThreshold = 3000, currentStanding = 700 },
    { name = "Other", isHeader = true },
    { factionID = 349, name = "Ravenholdt", reaction = 3, currentReactionThreshold = -3000, nextReactionThreshold = 0, currentStanding = -1200 },
}
C_Reputation = {
    GetNumFactions = function() return #factions end,
    GetFactionDataByIndex = function(i) return factions[i] end,
}

-- Undead Route's answer to "what next", so the Home card has something to show.
UndeadRoute = {
    Status = function()
        return { stage = "Hillsbrad Foothills", range = "20-30", hub = "Tarren Mill", next = "Pick up: Elixir of Pain", left = 14 }
    end,
    Toggle = function() print("Undead Route would open here.") end,
}

-- A minimap to hang the minimap button on.
Minimap = CreateFrame("Frame", "Minimap", UIParent, "BackdropTemplate")
Minimap:SetSize(140, 140)
Minimap:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -30, -40)
Minimap:SetBackdrop({})
Minimap:SetBackdropColor(0.10, 0.14, 0.10, 0.9)
Minimap:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)

-- First run: two other characters and a few days of gold, so the lists are not empty.
if not ZodUIDB then
    local now = os.time()
    ZodUIDB = {
        chars = {
            ["Morgana-Forever"] = { name = "Morgana", realm = "Forever", class = "MAGE", className = "Mage", race = "Undead",
                level = 42, money = 3456700, xp = 21000, xpMax = 60000, rested = 9000, resting = true, seen = now - 30 * 3600,
                zone = "Undercity", profs = { { name = "Tailoring", rank = 210, max = 225 }, { name = "Enchanting", rank = 190, max = 225 } },
                items = { [2589] = { bags = 40, bank = 120 }, [14047] = { bags = 12 }, [14342] = { bank = 2 }, [11137] = { bags = 30 },
                    [6948] = { bags = 1 } } },
            ["Grub-Forever"] = { name = "Grub", realm = "Forever", class = "WARRIOR", className = "Warrior", race = "Orc",
                level = 17, money = 45600, xp = 300, xpMax = 14000, rested = 0, resting = false, seen = now - 9 * 86400,
                zone = "The Barrens", profs = { { name = "Skinning", rank = 75, max = 150 } },
                items = { [2318] = { bags = 17 }, [4865] = { bags = 4 }, [2775] = { bank = 10 }, [6948] = { bags = 1 } } },
        },
        gold = { days = {
            [os.date("%Y-%m-%d", now - 86400)] = { earned = 184500, spent = 61200 },
            [os.date("%Y-%m-%d", now - 2 * 86400)] = { earned = 92000, spent = 130500 },
            [os.date("%Y-%m-%d", now - 3 * 86400)] = { earned = 45100, spent = 8000 },
        } },
        notes = { { text = "Send the Mooncloth to Morgana" } },
        reminders = { { text = "Check the auction house", at = now + 14 * 60 }, { text = "Mooncloth cooldown on Morgana", at = now + 3 * 3600 } },
        itemNames = { [14047] = { name = "Runecloth", q = 1 }, [14342] = { name = "Mooncloth", q = 2 },
            [11137] = { name = "Vision Dust", q = 1 }, [2318] = { name = "Light Leather", q = 1 } },
    }
    ZodUICharDB = {
        notes = { { text = "Buy the level 26 spells" }, { text = "Hand in Elixir of Agony", done = true } },
        played = 41 * 3600,
        goldGoal = 1000000,
        goals = { { id = 2589, name = "Linen Cloth", want = 60 }, { id = 2775, name = "Silver Ore", want = 3, done = true },
            { id = 1206, name = "Moss Agate", want = 5 } },
        history = { days = (function()
            local days = {}
            local xp = { 0, 9200, 14100, 0, 6100, 18800, 21500, 3900, 0, 12400, 16900, 8800, 20300, 6400 }
            for i, gained in ipairs(xp) do
                if gained > 0 then
                    days[os.date("%Y-%m-%d", now - (14 - i) * 86400)] = { xp = gained, quests = math.floor(gained / 1900), deaths = i % 3,
                        levels = gained > 18000 and 1 or 0, gold = gained * 3 - 20000, played = math.floor(gained / 2.6) }
                end
            end
            return days
        end)() },
        runs = { list = {
            { name = "Shadowfang Keep", kind = "party", at = now - 20 * 3600, took = 2940, xp = 14800, gold = 21500, deaths = 1, level = 25 },
            { name = "Shadowfang Keep", kind = "party", at = now - 44 * 3600, took = 3480, xp = 13100, gold = 16400, deaths = 0, level = 24 },
            { name = "Wailing Caverns", kind = "party", at = now - 4 * 86400, took = 4620, xp = 11900, gold = 9800, deaths = 2, level = 22 },
            { name = "Ragefire Chasm", kind = "party", at = now - 9 * 86400, took = 1710, xp = 5200, gold = 3100, deaths = 0, level = 17 },
        } },
        levels = {
            [23] = { at = now - 3 * 86400, played = 36 * 3600 },
            [24] = { at = now - 2 * 86400, played = 38 * 3600 + 900, took = 2 * 3600 + 900 },
            [25] = { at = now - 86400, played = 40 * 3600 + 1500, took = 2 * 3600 + 600 },
        },
        loot = { last = now, items = {
            [2589] = { name = "Linen Cloth", count = 14, quality = 1, price = 13 },
            [4865] = { name = "Ruined Pelt", count = 9, quality = 0, price = 5 },
            [15223] = { name = "Jagged Star", count = 1, quality = 2, price = 4130 },
            [2775] = { name = "Silver Ore", count = 3, quality = 1, price = 75 },
            [1206] = { name = "Moss Agate", count = 1, quality = 2, price = 400 },
            [12037] = { name = "Mystery Meat", count = 6, quality = 1, price = 87 },
        } },
        session = { start = started - 2700, last = started, xp = 6400, gains = 31, quests = 4, questXP = 3900, deaths = 1, levels = 0 },
    }
end
