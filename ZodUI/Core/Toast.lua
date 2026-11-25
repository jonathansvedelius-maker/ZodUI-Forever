local ADDON, ns = ...
local T, M = ns.T, ns.Motion

-- Notices: ZodUI's alerts as small cards near the top of the screen, newest
-- first. A card stays a few seconds and fades; a click dismisses it (and does the notice's own click, when it
-- has one: Quest done pins the hand-in). A long notice takes two lines.

local HOLD, FADE, MOST = 5, 1, 4
local TOP, GAP, HEIGHT = -60, 4, 30
local stack, pool = {}, {}
ns.toasts = stack

-- Stacks the cards from the top. glide: the cards already on screen glide from where they were (one came or
-- went) instead of jumping; `new` is the card just added, which lifts in instead.
local function Layout(glide, new)
    local down = 0
    for _, toast in ipairs(stack) do
        local _, _, _, _, wasY = toast:GetPoint(1)
        toast:ClearAllPoints()
        local store = ns.db and ns.db.movers and ns.db.movers.toasts
        if store and store.point then -- dragged in unlock mode
            toast:SetPoint(store.point, UIParent, store.rel or store.point, store.x or 0, (store.y or 0) - down)
        else
            toast:SetPoint("TOP", UIParent, "TOP", 0, TOP - down)
        end
        if glide and toast ~= new and wasY then
            local _, _, _, _, y = toast:GetPoint(1)
            M.Glide(toast, 0, wasY - y)
        end
        down = down + (toast:GetHeight() or HEIGHT) + GAP
    end
end

local function Drop(toast)
    if toast.dropped then return end -- the fade's end and the countdown can both get here
    toast.dropped = true
    for i = #stack, 1, -1 do
        if stack[i] == toast then table.remove(stack, i) end
    end
    toast:Hide()
    pool[#pool + 1] = toast
    M.Stop(toast)
    Layout(true)
end

local function New()
    local toast = T.Panel(UIParent, T.WINDOW, 0.95)
    -- Forever look: the game's tooltip edge in bronze, as the Dungeon Journal's small menus; the gold bar inside it.
    local inset = 1
    if T.look == "game" then
        toast:SetBackdrop({ bgFile = T.WHITE, edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12,
            insets = { left = 3, right = 3, top = 3, bottom = 3 } })
        toast:SetBackdropColor(T.WINDOW[1], T.WINDOW[2], T.WINDOW[3], 0.95)
        toast:SetBackdropBorderColor(0.57, 0.43, 0.20, 1)
        inset = 4
    end
    toast.inset = inset
    toast:SetFrameStrata("DIALOG")
    toast:SetSize(300, HEIGHT)
    toast.mark = toast:CreateTexture(nil, "ARTWORK")
    toast.mark:SetTexture(T.WHITE)
    toast.mark:SetVertexColor(T.GOLD[1], T.GOLD[2], T.GOLD[3], 1)
    toast.mark:SetPoint("TOPLEFT", inset, -inset)
    toast.mark:SetSize(3, HEIGHT - 2)
    toast.text = T.Text(toast, "GameFontHighlight")
    toast.text:SetPoint("LEFT", 16, 0)
    toast.text:SetJustifyH("LEFT")
    toast.text:SetWordWrap(true)
    toast.text:SetMaxLines(2)
    toast:EnableMouse(true)
    toast:SetScript("OnMouseUp", function(self)
        local click = self.click
        Drop(self)
        if click then ns.Guard("notice click", click) end
    end)
    toast:SetScript("OnEnter", function(self)
        if not (self.hint and GameTooltip) then return end
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine(self.hint, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    toast:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    -- Only a countdown runs here; the fade itself is ns.Motion's (T.Fade), and its end drops the notice.
    toast:SetScript("OnUpdate", function(self, elapsed)
        if not self.fading and self:IsMouseOver() then return end -- held while the mouse is on it, to read it
        self.left = self.left - elapsed
        if self.left < FADE and not self.fading then
            self.fading = true
            T.Fade(self, 0, math.max(0.05, self.left), function() Drop(self) end)
        elseif self.left <= -0.5 then
            Drop(self) -- in case the fade never finished (hidden with its parent)
        end
    end)
    return toast
end

ns.AddMover({ key = "toasts", title = "ZodUI notices", width = 300, height = HEIGHT, point = "TOP", x = 0, y = TOP, Apply = Layout })

function ns.Toast(msg, opts)
    local toast = table.remove(pool) or New()
    toast.click = opts and opts.click or nil
    toast.hint = opts and opts.hint or nil
    toast.text:SetText(msg)
    -- As wide as the words, up to 440 px; a longer notice wraps to a second line (past that it ends in ...,
    -- and the whole of it is in chat and /zod log).
    local width = math.min(440, math.max(220, math.ceil(T.TextWidth(toast.text)) + 1 + 32))
    toast:SetWidth(width)
    toast.text:SetWidth(width - 32)
    local height = math.max(HEIGHT, math.ceil(toast.text:GetStringHeight() or 0) + 16)
    toast:SetHeight(height)
    toast.mark:SetHeight(height - 2 * (toast.inset or 1))
    local general = ns.db and ns.db.general
    toast.left = (general and general.toastHold or HOLD) + FADE
    if general and general.toastSound and PlaySound then
        pcall(PlaySound, SOUNDKIT and SOUNDKIT.ALARM_CLOCK_WARNING_3 or 12889)
    end
    toast.dropped, toast.fading = false, false
    M.Stop(toast)
    toast:Show()
    table.insert(stack, 1, toast)
    while #stack > MOST do Drop(stack[#stack]) end
    Layout(true, toast)
    M.Piece(toast, 0, M.NORMAL, M.RISE) -- fades in and rises into its place; the others glide down
end
