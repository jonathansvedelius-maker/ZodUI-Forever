local ADDON, ns = ...
local T = ns.T

-- Unlock mode: /zod unlock shows a box for every ZodUI frame that sits on the
-- screen by itself (the notices, the info bar). Drag a box, then /zod lock.
--
-- A frame joins with ns.AddMover({ key, title, width, height, point, x, y,
-- Apply = function() ... end }): point, x and y are where it sits until it is
-- dragged, Apply puts the real frame where the box was dropped. Store (a
-- function returning the table the position is saved in) and Shown (whether
-- the box should be offered now) are optional. A frame that hangs on another
-- one until it is dragged gives Anchor (a function returning what SetPoint
-- takes) instead of point, x and y.

local order, handles = {}, {}
local banner
local unlocked = false
ns.moverHandles = handles

-- Where a mover's position is saved when it brings no table of its own.
function ns.MoverStore(key)
    ns.db.movers = ns.db.movers or {}
    ns.db.movers[key] = ns.db.movers[key] or {}
    return ns.db.movers[key]
end

local function Store(info)
    return info.Store and info.Store() or ns.MoverStore(info.key)
end

function ns.AddMover(info)
    order[#order + 1] = info
end

local function Handle(info)
    local h = T.Panel(UIParent, T.WINDOW, 0.85)
    h:SetFrameStrata("DIALOG")
    h:SetSize(info.width, info.height)
    h:SetBackdropBorderColor(T.GOLD[1], T.GOLD[2], T.GOLD[3], 1)
    h.label = T.Text(h, "GameFontHighlightSmall", T.GOLD)
    h.label:SetPoint("CENTER", 0, 0)
    h.label:SetText(info.title)
    T.Movable(h, Store(info), h)
    local stop = h:GetScript("OnDragStop")
    h:SetScript("OnDragStop", function(self)
        stop(self)
        ns.Guard(info.key .. " mover", info.Apply)
    end)
    -- Right-click: this one frame back where it started, without /zod reset putting back all of them.
    h:SetScript("OnMouseUp", function(_, mouse)
        if mouse ~= "RightButton" then return end
        if info.Reset then -- a frame that keeps its place in its own settings knows how to put itself back
            ns.Guard(info.key .. " mover", info.Reset)
        elseif not info.Store then
            local store = ns.MoverStore(info.key)
            for k in pairs(store) do store[k] = nil end
            ns.Guard(info.key .. " mover", info.Apply)
        else
            return
        end
        ns.Unlock() -- the boxes follow
        ns.Refresh() -- an open Settings page shows the frame's place as it is now
    end)
    return h
end

local function Banner()
    local b = T.Panel(UIParent, T.WINDOW, 0.95)
    b:SetFrameStrata("DIALOG")
    b:SetSize(560, 34)
    b:SetPoint("TOP", UIParent, "TOP", 0, -200)
    b:SetBackdropBorderColor(T.GOLD[1], T.GOLD[2], T.GOLD[3], 1)
    b.text = T.Text(b, "GameFontHighlightSmall")
    b.text:SetPoint("LEFT", 12, 0)
    b.text:SetText("ZodUI is unlocked: drag the gold boxes where you want them; right-click one to put it back.")
    b.lock = T.Button(b, "Lock", 70, function() ns.Lock() end)
    b.lock:SetPoint("RIGHT", -6, 0)
    return b
end

function ns.Unlock()
    unlocked = true
    for _, info in ipairs(order) do
        local h = handles[info.key]
        if not info.Shown or info.Shown() then
            if not h then
                h = Handle(info)
                handles[info.key] = h
            end
            if info.Anchor and not Store(info).point then
                h:ClearAllPoints()
                h:SetPoint(info.Anchor())
            else
                T.Place(h, Store(info), info.point, info.x, info.y)
            end
            h:Show()
        elseif h then
            h:Hide()
        end
    end
    if not banner then banner = Banner() end
    banner:Show()
end

function ns.Lock()
    unlocked = false
    for _, h in pairs(handles) do h:Hide() end
    if banner then banner:Hide() end
end

function ns.IsUnlocked()
    return unlocked
end

-- /zod reset: every frame without a position table of its own goes back to where it started.
function ns.ResetMovers()
    for _, info in ipairs(order) do
        if not info.Store then
            local store = ns.MoverStore(info.key)
            for k in pairs(store) do store[k] = nil end
            ns.Guard(info.key .. " mover", info.Apply)
        end
    end
    if unlocked then ns.Unlock() end -- the boxes follow
end

-- Boxes on the screen are in the way of a fight.
ns.On("PLAYER_REGEN_DISABLED", function()
    if unlocked then ns.Lock() end
end)
