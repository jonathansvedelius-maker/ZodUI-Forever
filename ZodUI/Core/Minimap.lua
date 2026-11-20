local ADDON, ns = ...
local T = ns.T

-- The minimap button: left-click opens ZodUI, right-click opens Settings, drag
-- moves it around the minimap's edge.

local button

local function Place()
    local angle = math.rad(ns.db.general.minimapAngle or 215)
    local radius = (Minimap:GetWidth() or 140) / 2 + 6
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

local function Drag()
    local mx, my = Minimap:GetCenter()
    local scale = Minimap:GetEffectiveScale()
    local cx, cy = GetCursorPosition()
    if not (mx and scale and cx) then return end
    ns.db.general.minimapAngle = math.deg(math.atan2(cy / scale - my, cx / scale - mx)) % 360
    Place()
end

-- A few numbers worth a glance, one per line (may be empty).
function ns.Glance()
    local lines = {}
    local session = ns.modules.session
    if session and session.enabled and session.Rate then
        local perHour = session:Rate()
        if perHour and perHour > 0 then lines[#lines + 1] = "XP per hour: " .. ns.Comma(math.floor(perHour + 0.5)) end
    end
    -- The same things the info bar shows: gold this session and new mail.
    local gold = ns.modules.gold
    local net = gold and gold.enabled and gold.Session and gold:Session() or 0
    if net ~= 0 then lines[#lines + 1] = "Gold this session: " .. (net > 0 and "+" or "") .. ns.Money(net, true) end
    if HasNewMail and HasNewMail() then lines[#lines + 1] = "New mail" end
    local open = 0
    for _, list in ipairs({ ns.chardb.notes or {}, ns.db.notes or {} }) do
        for _, note in ipairs(list) do
            if not note.done then open = open + 1 end
        end
    end
    if open > 0 then lines[#lines + 1] = "To do: " .. open .. " open" end
    local next = ns.db.reminders and ns.db.reminders[1]
    if next and not (next.login and not next.due and next.at > time()) then -- one for the next login has no clock yet
        lines[#lines + 1] = "Next reminder: " .. next.text .. (next.due and " (now)" or (" in " .. ns.Duration(next.at - time())))
    end
    return lines
end

-- What the button's tooltip says: the glance, then what the clicks do.
function ns.MinimapSummary()
    local lines = ns.Glance()
    if #lines > 0 then lines[#lines + 1] = " " end
    lines[#lines + 1] = "Click: open or close\nRight-click: Settings\nMiddle-click: To do\nShift-click: the info bar on or off\nDrag: move this button"
    return table.concat(lines, "\n")
end

local function Build()
    local b = CreateFrame("Button", "ZodUIMinimapButton", Minimap)
    b:SetSize(26, 26)
    b:SetFrameStrata("MEDIUM")
    b:SetFrameLevel((Minimap:GetFrameLevel() or 0) + 10) -- above the minimap's own border art
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints()
    b.icon:SetTexture(T.LOGO)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp", "MiddleButtonUp")
    b:RegisterForDrag("LeftButton")
    b:SetScript("OnClick", function(_, mouse)
        if mouse == "LeftButton" and IsShiftKeyDown and IsShiftKeyDown() then
            local bar = ns.modules.databar
            if bar then
                if bar.enabled then bar:Disable() else bar:Enable() end
                ns.Print("the info bar is " .. (bar.enabled and "on." or "off."))
            end
        elseif mouse == "RightButton" then
            ns.Show("settings")
        elseif mouse == "MiddleButton" then
            ns.Show("notes")
        else
            ns.Toggle()
        end
    end)
    b:SetScript("OnDragStart", function(self) self:SetScript("OnUpdate", Drag) end)
    b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    b:SetScript("OnEnter", function(self)
        T.ShowTip(self, "ZodUI", ns.MinimapSummary())
    end)
    b:SetScript("OnLeave", T.HideTip)
    return b
end

function ns.UpdateMinimap()
    if not Minimap then return end
    if ns.db.general.minimap then
        if not button then button = Build() end
        Place()
        button:Show()
    elseif button then
        button:Hide()
    end
end

ns.On("PLAYER_LOGIN", function()
    ns.Guard("minimap button", ns.UpdateMinimap)
end)
