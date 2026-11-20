local ADDON, ns = ...

-- Pet coach, for hunters. Home shows the pet's mood and what it does to its damage, its loyalty, the food in your
-- bags it eats, its training points and XP. Notices say when it is unhappy (with the food to give it), is losing
-- loyalty, has new training points, is running out of food, or has died. A key (Key Bindings > ZodUI) feeds it the
-- best food you carry. Everything comes from C_PetInfo: WoW Forever has no GetPetHappiness global.
-- Stable keeper: the pets you own (seen at a stable master, or out now) with level, family, loyalty and diet, which
-- foods each eats (in item tooltips), and /zod pet to list them.

local M = ns:NewModule("pet", {
    title = "Pet coach",
    desc = "For hunters: your pet's mood, loyalty, food, training points and XP on Home; a notice when it needs feeding, "
        .. "is losing loyalty, has points to spend, runs low on food or has died; a key that feeds it; and your stabled pets "
        .. "with what each eats (in food tooltips, and /zod pet).",
    defaults = { enabled = true, happy = true, content = false, loyalty = true, tp = true, food = true, dead = true },
    options = {
        { type = "check", key = "happy", label = "Say when the pet is unhappy (75% damage)" },
        { type = "check", key = "content", label = "Say when it is no longer happy (100% damage, not 125%)" },
        { type = "check", key = "loyalty", label = "Say when it is losing loyalty" },
        { type = "check", key = "tp", label = "Say when it has new training points" },
        { type = "check", key = "food", label = "Say when its food runs low" },
        { type = "check", key = "dead", label = "Say when the pet has died" },
        { type = "note", text = "Feed key: Options > Keybindings > ZodUI > Feed your pet. It casts Feed Pet on the best "
            .. "food in your bags. In a macro: /click ZodUIPetFeed LeftButton 1", lines = 3 },
    },
})

local FEED_PET = 6991 -- the Feed Pet spell
local BINDING = "CLICK ZodUIPetFeed:LeftButton"
local LOW_FOOD = 5
local MOODS = { "Unhappy", "Content", "Happy" }
local Pet = C_PetInfo or {}

local function Plain(v)
    if issecretvalue and issecretvalue(v) then return nil end
    return v
end

local function HasPet()
    local _, class = ns.MyClass()
    return class == "HUNTER" and UnitExists("pet")
end

-- happiness (1-3), damage percent, loyalty rate (below 0: losing loyalty); nil while hidden or without a pet.
local function Mood()
    if not Pet.GetPetHappiness then return nil end
    local h, damage, rate = Pet.GetPetHappiness()
    h, damage, rate = Plain(h), Plain(damage), Plain(rate)
    if type(h) ~= "number" then return nil end
    return h, type(damage) == "number" and damage or nil, type(rate) == "number" and rate or nil
end

---------------------------------------------------------------------------
-- Food
---------------------------------------------------------------------------

local eats = {} -- [itemID] = true/false for the current pet

---------------------------------------------------------------------------
-- Your pets, kept per character: the one out now, and the stable's as last seen at a stable master
---------------------------------------------------------------------------

local PET_EATS_MOST = 400 -- foods remembered per pet

local function Pets()
    ns.chardb.pets = ns.chardb.pets or {}
    return ns.chardb.pets
end

-- [name] = { level, family, loyalty, diet = { "Meat" ... }, eats = { [itemID] = bool }, active, stabled }
local function Record(name)
    if type(name) ~= "string" or name == "" then return nil end
    local pets = Pets()
    local r = pets[name]
    if not r then
        r = { eats = {} }
        pets[name] = r
    end
    r.eats = r.eats or {}
    return r
end

local function Remember(id, can)
    local r = Record(Plain(UnitName("pet")))
    if not r then return end
    if r.eats[id] == nil then
        local n = 0
        for _ in pairs(r.eats) do n = n + 1 end
        if n >= PET_EATS_MOST then return end
    end
    r.eats[id] = can
end

local function CopyList(t)
    if type(t) ~= "table" then return nil end
    local out = {}
    for _, v in ipairs(t) do
        v = Plain(v)
        if type(v) == "string" then out[#out + 1] = v end
    end
    return #out > 0 and out or nil
end

-- At a stable master: every pet you own, with level, family, loyalty and diet.
local function ScanStable()
    local S = C_StableInfo
    if not (S and S.GetActivePetList and S.GetStabledPetList) then return end
    local seen, any = {}, false
    local function Take(list, active)
        for _, info in ipairs(type(list) == "table" and list or {}) do
            local name = Plain(info.name)
            local r = Record(name)
            if r then
                any = true
                seen[name] = true
                local level = Plain(info.level)
                r.level = type(level) == "number" and level or r.level
                r.family = Plain(info.familyName) or r.family
                r.loyalty = Plain(info.loyaltyName) or r.loyalty
                r.active, r.stabled = active, true
                local slot = Plain(info.slotID)
                if type(slot) == "number" and S.GetStablePetFoodTypes then
                    r.diet = CopyList(S.GetStablePetFoodTypes(slot)) or r.diet
                end
            end
        end
    end
    Take(S.GetActivePetList(), true)
    Take(S.GetStabledPetList(), false)
    if not any then return end -- the lists are not in yet: keep what was known
    for name, r in pairs(Pets()) do
        if r.stabled and not seen[name] then Pets()[name] = nil end -- released or abandoned
    end
    ns.chardb.stableAt = time()
end
M.ScanStable = ScanStable

-- The food in your bags the pet eats, best first (highest item level, then the smaller stack), and the total.
local function Foods()
    local byID, list, total = {}, {}, 0
    if not Pet.CanPetEatItem then return list, total end
    for bag = 0, NUM_BAG_SLOTS or 4 do
        for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            local id = info and Plain(info.itemID)
            if type(id) == "number" then
                if eats[id] == nil then
                    local can = Plain(Pet.CanPetEatItem(id))
                    if can ~= nil then
                        eats[id] = can and true or false
                        Remember(id, eats[id])
                    end
                end
                if eats[id] then
                    local food = byID[id]
                    if not food then
                        local name, _, _, level = C_Item.GetItemInfo(id)
                        food = { id = id, count = 0, level = level or 0, name = name or ("item " .. id) }
                        byID[id] = food
                        list[#list + 1] = food
                    end
                    local count = info.stackCount or 1
                    food.count = food.count + count
                    total = total + count
                end
            end
        end
    end
    table.sort(list, function(a, b)
        if a.level ~= b.level then return a.level > b.level end
        if a.count ~= b.count then return a.count < b.count end
        return a.id < b.id
    end)
    return list, total
end

local function Diet()
    local types = Pet.GetPetFoodTypes and Pet.GetPetFoodTypes()
    if type(types) ~= "table" or #types == 0 then return "" end
    return " (" .. table.concat(types, ", ") .. ")"
end

-- "Feed it: Roasted Boar Meat (4). Press F." or what it eats when you carry none.
local function FeedHint(foods)
    local best = foods[1]
    if not best then return " You carry no food it eats" .. Diet() .. "." end
    local key = GetBindingKey and GetBindingKey(BINDING)
    return (" Feed it: %s (%d).%s"):format(best.name, best.count, key and (" Press " .. key .. ".") or "")
end

---------------------------------------------------------------------------
-- The feed key: a secure button that casts Feed Pet on the best food
---------------------------------------------------------------------------

_G["BINDING_NAME_" .. BINDING] = "Feed your pet"

local feed = CreateFrame("Button", "ZodUIPetFeed", UIParent, "SecureActionButtonTemplate")
feed:RegisterForClicks("AnyDown")
feed:SetAttribute("useOnKeyDown", true)
local feedFood = false -- the item the key is set to; false: not set yet

-- Attributes on a secure button can only change out of combat; PLAYER_REGEN_ENABLED catches up.
local function SetFeed(food)
    local id = food and food.id or nil
    if id == feedFood or InCombatLockdown() then return end
    feedFood = id
    local spell = Plain(C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(FEED_PET)) or "Feed Pet"
    feed:SetAttribute("type", id and "macro" or nil)
    feed:SetAttribute("macrotext", id and ("/cast " .. spell .. "\n/use item:" .. id) or nil)
end

---------------------------------------------------------------------------
-- Watching the pet
---------------------------------------------------------------------------

local said = {}       -- what has been said for this pet: unhappy, content, losing, low, dead
local petName         -- the pet the state above belongs to
local lastMood, lastFree

local function Forget()
    said, eats, lastMood, lastFree = {}, {}, nil, nil
end

local function Check()
    if not HasPet() then
        if petName then Forget() petName = nil end
        SetFeed(nil)
        return
    end
    local name = Plain(UnitName("pet"))
    if name and name ~= petName then
        Forget()
        petName = name
    end
    local r = Record(name)
    if r then
        local level = Plain(UnitLevel("pet"))
        if type(level) == "number" then r.level = level end
        r.diet = CopyList(Pet.GetPetFoodTypes and Pet.GetPetFoodTypes()) or r.diet
        for other, o in pairs(Pets()) do o.out = other == name or nil end
    end

    local dead = Plain(UnitIsDead("pet")) and true or false
    if dead and M.db.dead and not said.dead then ns.Alert("Your pet has died.") end
    said.dead = dead

    local foods, total = Foods()
    SetFeed(foods[1])
    if dead then return end

    local h, damage, rate = Mood()
    local hinted -- a mood notice already said what food there is
    if h then
        local unhappy = h <= 1
        if unhappy and M.db.happy and not said.unhappy then
            ns.Alert("Your pet is unhappy and does " .. (damage or 75) .. "% damage." .. FeedHint(foods))
            hinted = true
        end
        said.unhappy = unhappy
        if h == 2 and lastMood == 3 and M.db.content then
            ns.Alert("Your pet is no longer happy: " .. (damage or 100) .. "% damage instead of 125%." .. FeedHint(foods))
            hinted = true
        end
        lastMood = h

        local losing = rate ~= nil and rate < 0
        if losing and M.db.loyalty and not said.losing then
            ns.Alert("Your pet is losing loyalty. Keep it fed and happy, or it may run away.")
        end
        said.losing = losing
    end

    if Pet.GetPetTrainingPoints then
        local all, used = Pet.GetPetTrainingPoints()
        all, used = Plain(all), Plain(used)
        if type(all) == "number" and type(used) == "number" then
            local free = all - used
            if lastFree and free > lastFree and M.db.tp then
                ns.Alert(("Your pet has %d training points to spend (Beast Training)."):format(free))
            end
            lastFree = free
        end
    end

    local low = total < LOW_FOOD
    if low and M.db.food and not said.low and not hinted then
        if total == 0 then
            ns.Alert("You carry no food your pet eats" .. Diet() .. ".")
        else
            ns.Alert(("Your pet's food is running low: %d left (%s)."):format(total, foods[1].name))
        end
    end
    said.low = low
end

ns.Every(3, Check, M)
M:On("UNIT_HAPPINESS", function(_, _, unit) if unit == "pet" then Check() ns.Refresh() end end)
M:On("UNIT_PET", function(_, _, unit) if unit == "player" then eats = {} Check() ns.Refresh() end end)
M:On("PET_UI_UPDATE", function() Check() ns.Refresh() end)
M:On("UNIT_PET_EXPERIENCE", function() ns.Refresh() end)
M:On("BAG_UPDATE_DELAYED", function() Check() end)
M:On("PLAYER_REGEN_ENABLED", function() Check() end)

function M:OnDisable()
    SetFeed(nil)
end

local function Hunter()
    local _, class = ns.MyClass()
    return class == "HUNTER"
end

M:On("PET_STABLE_SHOW", function() if Hunter() then ScanStable() ns.Refresh() end end)
M:On("PET_STABLE_UPDATE", function() if Hunter() then ScanStable() ns.Refresh() end end)

local function Sorted()
    local list = {}
    for name, r in pairs(Pets()) do list[#list + 1] = { name = name, r = r } end
    table.sort(list, function(a, b)
        if (a.r.out and 1 or 0) ~= (b.r.out and 1 or 0) then return a.r.out ~= nil end
        if (a.r.level or 0) ~= (b.r.level or 0) then return (a.r.level or 0) > (b.r.level or 0) end
        return a.name < b.name
    end)
    return list
end

-- Item tooltips (through the Tooltips module): which of your pets eat this food, as far as ZodUI has seen.
function M:ItemTooltip(tip, id)
    if not Hunter() then return end
    local names = {}
    for _, p in ipairs(Sorted()) do
        if p.r.eats and p.r.eats[id] then names[#names + 1] = p.name end
    end
    if #names > 0 then tip:AddDoubleLine("Pet food", table.concat(names, ", "), 0.6, 0.6, 0.6, 0.67, 0.83, 0.45) end
end

local function Describe(p)
    local r = p.r
    local parts = {}
    if r.level then parts[#parts + 1] = "level " .. r.level end
    if r.family then parts[#parts + 1] = r.family end
    if r.loyalty then parts[#parts + 1] = r.loyalty end
    if r.diet then parts[#parts + 1] = "eats " .. table.concat(r.diet, ", ") end
    return table.concat(parts, ", ")
end

-- /zod pet (or /zod pet stable): your pets.
function M:Slash(arg)
    arg = (arg or ""):lower()
    if arg ~= "" and arg ~= "stable" and arg ~= "list" then
        ns.Print("use /zod pet to list your pets, or /zod pet on | off.")
        return
    end
    local list = Sorted()
    if #list == 0 then
        ns.Print("no pets known yet. Call your pet, or visit a stable master once, and ZodUI remembers them.")
        return
    end
    local at = ns.chardb.stableAt
    ns.Print("your pets" .. (at and (" (stable last seen " .. ns.When(at, true) .. ")") or "") .. ":")
    for _, p in ipairs(list) do
        local where = p.r.out and "|cff40d040out now|r" or (p.r.stabled and "|cff999999in the stable|r" or "|cff999999seen|r")
        print("  |cffffd100" .. p.name .. "|r  " .. Describe(p) .. "  " .. where)
    end
end

function M:Find(part, add, has)
    for _, p in ipairs(Sorted()) do
        if has(p.name) or (p.r.family and has(p.r.family)) then add("Pet", p.name, Describe(p), "settings", "pet") end
    end
end

function M:Card()
    if not HasPet() then return nil end
    local h, damage, rate = Mood()
    local lines = {}
    local mood = h and MOODS[h]
    lines[1] = { Plain(UnitName("pet")) or "Your pet",
        mood and (mood .. (damage and ("  |cff999999" .. damage .. "% damage|r") or "")) or "?" }

    local loyalty = Pet.GetPetLoyalty and Plain(Pet.GetPetLoyalty())
    if type(loyalty) == "string" then
        local trend = rate and (rate < 0 and "  |cffff5555losing|r" or rate > 0 and "  |cff999999growing|r") or ""
        lines[#lines + 1] = { "Loyalty", loyalty .. trend }
    end

    local foods, total = Foods()
    lines[#lines + 1] = { "Food", total == 0 and "none it eats" or (total .. "  |cff999999" .. foods[1].name .. "|r") }

    local parts = {}
    if Pet.GetPetTrainingPoints then
        local all, used = Pet.GetPetTrainingPoints()
        all, used = Plain(all), Plain(used)
        if type(all) == "number" and type(used) == "number" and all > 0 then
            parts[#parts + 1] = (all - used) .. " free of " .. all
        end
    end
    local xp, xpMax
    if GetPetExperience then xp, xpMax = GetPetExperience() end
    xp, xpMax = Plain(xp), Plain(xpMax)
    if type(xp) == "number" and type(xpMax) == "number" and xpMax > 0 then
        parts[#parts + 1] = "XP " .. math.floor(xp / xpMax * 100) .. "%"
    end
    if #parts > 0 then lines[#lines + 1] = { "Training", table.concat(parts, "  ·  ") } end
    return { title = "Pet", lines = lines }
end
