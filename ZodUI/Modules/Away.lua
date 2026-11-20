local ADDON, ns = ...
local T = ns.T

-- Away: while you are marked away, a small box counts how long; back again,
-- a line in chat says how long it was.

local M = ns:NewModule("afk", {
    title = "Away timer",
    desc = "While you are marked away, a box in the middle of the screen counts how long you have been gone. When you are back, chat says how long it was.",
    defaults = { enabled = true, box = true, say = true },
    options = {
        { type = "check", key = "box", label = "Show the box while you are away" },
        { type = "check", key = "say", label = "Say how long you were away when you are back" },
    },
})

local SHORTEST = 60 -- seconds; a shorter absence is not worth a line
local box, since

-- Where the box sits: up from the middle, or where it was dropped in unlock mode (/zod unlock).
local function Place()
    if box then T.Place(box, ns.MoverStore("away"), "CENTER", 0, 120) end
end
ns.AddMover({ key = "away", title = "Away box", width = 220, height = 54, point = "CENTER", x = 0, y = 120, Apply = Place })

local function Box()
    if box then return box end
    box = T.Panel(UIParent, T.WINDOW, 0.9)
    box:SetSize(220, 54)
    box:SetFrameStrata("DIALOG")
    box.title = T.Text(box, "GameFontNormal", T.GOLD)
    box.title:SetPoint("TOP", 0, -10)
    box.title:SetText("Away")
    box.time = T.Text(box, "GameFontHighlightLarge")
    box.time:SetPoint("TOP", 0, -28)
    M.box = box
    Place()
    return box
end

local function Away()
    return ns.IsAway()
end

local function Update()
    if since and M.db.box then
        local gone = time() - since
        Box().time:SetText(string.format("%d:%02d", math.floor(gone / 60), gone % 60))
        box:Show()
    elseif box then
        box:Hide()
    end
end

M:On("PLAYER_FLAGS_CHANGED", function(self)
    if Away() then
        since = since or time()
    elseif since then
        local gone = time() - since
        since = nil
        if self.db.say and gone >= SHORTEST then ns.Print("back after " .. ns.Duration(gone) .. " away.") end
    end
    Update()
end)

ns.Every(1, Update, M)

function M:OnEnable()
    since = Away() and time() or nil
end

function M:OnDisable()
    since = nil
    if box then box:Hide() end
end

M.OnOption = Update
