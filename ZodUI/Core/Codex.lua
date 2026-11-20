local ADDON, ns = ...

-- Codex Forever (an addon of its own: every item, NPC, quest and recipe of WoW Forever) when it is installed.
-- ZodUI only calls it while the game runs, through its /codex command: nothing of it is copied here (it is
-- GPLv3), and without it nothing shows and nothing breaks. Its own Alt-click on bags and chat links keeps working;
-- this adds the same on ZodUI's item lists and search.

local Codex = {}
ns.Codex = Codex

local NAME = "CodexForever"

function Codex.Has()
    local loaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
    if not (loaded and loaded(NAME)) then return false end
    return type(SlashCmdList) == "table" and type(SlashCmdList.CODEXFOREVER) == "function"
end

-- Opens Codex Forever searching for `text`; false when it is not there or the call failed.
function Codex.Open(text)
    if not Codex.Has() then return false end
    text = tostring(text or ""):gsub("|", ""):gsub("^%s+", ""):gsub("%s+$", "")
    local ok, err = pcall(SlashCmdList.CODEXFOREVER, text)
    if not ok then
        ns.Guard("codex", error, err) -- recorded under /zod errors, once
        return false
    end
    return true
end

-- An item by its link or name: Codex searches by name, so the name is taken out of a link.
function Codex.OpenItem(item)
    if type(item) ~= "string" or item == "" then return false end
    return Codex.Open(item:match("|h%[(.-)%]|h") or item)
end

-- Alt-click on something that names an item: opens it in Codex. True when it did (the click is used up).
function Codex.Click(item)
    if not (IsAltKeyDown and IsAltKeyDown()) then return false end
    return Codex.OpenItem(item)
end

-- A short note for a page that lists items, or "" without Codex.
function Codex.Hint()
    return Codex.Has() and "  |cff999999Alt-click an item: Codex Forever|r" or ""
end
