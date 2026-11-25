local ADDON, ns = ...

-- Motion: how frames move. Windows fade and rise in, rows lift in one after another, numbers count, a light
-- runs over a bar. This file is the same in ZodUI and Undead Route (each ships its own copy, so neither needs
-- the other); ZodUI's tools/run.js fails when the two differ.
--
--   * A few durations and one family of curves, all here; no other file makes up its own timing.
--   * Every move starts from where things are now, so a close turned round midway never jumps.
--   * One shared OnUpdate driver, on only while something moves.
--   * One switch (M.enabled): off, every helper lands on its end state at once.
--   * Movement re-anchors the frame (SetPoint) instead of a Translation animation, which snaps to whole
--     pixels and looks jerky over a few px. Protected frames are never moved in combat.
--   * Only what loops or pops uses AnimationGroups (Pulse, Pop): the game runs those with no Lua per frame.

local M = {}
ns.Motion = M

M.enabled = true

-- Timing (seconds) and distances (px).
M.FAST, M.NORMAL, M.SLOW = 0.12, 0.2, 0.4
M.OPEN, M.CLOSE = 0.22, 0.25    -- closing is a little slower than opening...
M.RISE, M.SINK = 8, 4           -- ...and sinks less than opening rises
M.PIECE, M.LIFT = 0.12, 4       -- one row lifting in
M.GAP, M.MAX_STAGGER = 0.02, 5  -- the delay between rows; after this many, the rest come together

-- Curves. Alpha on a sine (a cubic does most of the fade in the first frames and pops), movement on a cubic
-- ease-out (fast start, soft landing), fade-outs in-out, and smoothstep for what may turn round midway.
local HALF_PI = math.pi / 2
M.Ease = {
    linear = function(p) return p end,
    sine = function(p) return math.sin(p * HALF_PI) end,
    out = function(p) local q = 1 - p return 1 - q * q * q end,
    inOut = function(p)
        if p < 0.5 then return 2 * p * p end
        local q = -2 * p + 2
        return 1 - q * q / 2
    end,
    smooth = function(p) return p * p * (3 - 2 * p) end,
}

-- ---------------------------------------------------------------------------------------------------------
-- The driver: one frame whose OnUpdate is set only while there are jobs. jobs[owner][channel] = job; a new
-- job on the same owner and channel replaces the old one, so a frame can fade ("alpha") and move ("move")
-- at once.
-- ---------------------------------------------------------------------------------------------------------

local jobs = {}
local driver = CreateFrame("Frame")
M.driver = driver -- for the tests: its OnUpdate is off whenever nothing moves
local batch = {}

local function call(fn, ...)
    if not fn then return end
    local ok, err = pcall(fn, ...)
    if not ok then -- said, and the driver keeps going: one broken callback never stops every animation
        local handler = geterrorhandler and geterrorhandler()
        if handler then handler(err) else print(ADDON .. " motion: " .. tostring(err)) end
    end
end

local function OnUpdate(self, elapsed)
    -- A snapshot first: a callback may start or stop jobs while this runs.
    local n = 0
    for owner, channels in pairs(jobs) do
        for channel, job in pairs(channels) do
            n = n + 1
            batch[n] = job
            job.owner, job.channel = owner, channel
        end
    end
    for i = 1, n do
        local job = batch[i]
        batch[i] = nil
        local channels = jobs[job.owner]
        if channels and channels[job.channel] == job then -- not replaced or stopped meanwhile
            job.t = job.t + elapsed
            if job.t >= 0 then -- below 0 it is still waiting out its delay
                local p = job.t / job.dur
                if p >= 1 then
                    channels[job.channel] = nil
                    if next(channels) == nil then jobs[job.owner] = nil end
                    call(job.apply, job.to)
                    call(job.done)
                else
                    call(job.apply, job.from + (job.to - job.from) * job.ease(p))
                end
            end
        end
    end
    if next(jobs) == nil then self:SetScript("OnUpdate", nil) end
end

-- Drops a job (or every job of `owner`) where it is, without its end or its `done`.
function M.Stop(owner, channel)
    local channels = jobs[owner]
    if not channels then return end
    if channel then channels[channel] = nil end
    if not channel or next(channels) == nil then jobs[owner] = nil end
end

function M.IsMoving(owner, channel)
    local channels = jobs[owner]
    if not channels then return false end
    return channel == nil or channels[channel] ~= nil
end

-- Goes from `from` to `to`; apply(v) runs every frame. opts: dur, ease (a name or a function), delay, done.
function M.Tween(owner, channel, from, to, apply, opts)
    opts = opts or {}
    local dur = opts.dur or M.NORMAL
    if not M.enabled or dur <= 0 or from == to then
        M.Stop(owner, channel)
        call(apply, to)
        call(opts.done)
        return
    end
    local ease = opts.ease or "out"
    if type(ease) == "string" then ease = M.Ease[ease] end
    local delay = opts.delay or 0
    jobs[owner] = jobs[owner] or {}
    jobs[owner][channel] = { t = -delay, dur = dur, from = from, to = to, ease = ease, apply = apply, done = opts.done }
    if delay <= 0 then call(apply, from) end
    driver:SetScript("OnUpdate", OnUpdate)
end

-- Ends everything on `owner` now: each job lands on its end and runs its `done`.
function M.Settle(owner)
    local channels = jobs[owner]
    if not channels then return end
    jobs[owner] = nil
    for _, job in pairs(channels) do
        call(job.apply, job.to)
        call(job.done)
    end
end

-- ---------------------------------------------------------------------------------------------------------
-- Offsets: a frame is drawn dx, dy px from where its own code put it ("home"). Single-anchor frames only;
-- one with two anchors or SetAllPoints just fades.
-- ---------------------------------------------------------------------------------------------------------

local function Home(frame)
    if not (frame.GetNumPoints and frame:GetNumPoints() == 1) then return nil end
    local point, rel, relPoint, x, y = frame:GetPoint(1)
    if not point then return nil end
    rel = rel or frame:GetParent()
    x, y = x or 0, y or 0
    local h = frame.motionHome
    -- Re-anchored by its own code meanwhile (dragged, pinned, laid out): that is the new home.
    if not h or h.rel ~= rel or h.point ~= point or h.relPoint ~= relPoint
        or math.abs(h.lastX - x) > 0.5 or math.abs(h.lastY - y) > 0.5 then
        h = { point = point, rel = rel, relPoint = relPoint, x = x, y = y, dx = 0, dy = 0, lastX = x, lastY = y }
        frame.motionHome = h
    end
    return h
end

local function Locked(frame)
    return InCombatLockdown and InCombatLockdown() and frame.IsProtected and frame:IsProtected() and true or false
end

-- Draws `frame` dx, dy px from home (nil keeps that axis as it is).
function M.Offset(frame, dx, dy)
    if Locked(frame) then return end
    local h = Home(frame)
    if not h then return end
    h.dx, h.dy = dx or h.dx, dy or h.dy
    h.lastX, h.lastY = h.x + h.dx, h.y + h.dy
    frame:ClearAllPoints()
    frame:SetPoint(h.point, h.rel, h.relPoint, h.lastX, h.lastY)
    if h.dx == 0 and h.dy == 0 then frame.motionHome = nil end
end

function M.CurrentOffset(frame)
    local h = frame.motionHome
    if not h then return 0, 0 end
    return h.dx, h.dy
end

local function Alpha(frame) return frame:GetAlpha() or 1 end
local function SetAlpha(frame) return function(a) frame:SetAlpha(a) end end

-- ---------------------------------------------------------------------------------------------------------
-- Fades and windows
-- ---------------------------------------------------------------------------------------------------------

-- Fades `frame` to alpha `to` from where it is now. opts: dur, ease, delay, done.
function M.Fade(frame, to, opts)
    opts = opts or {}
    M.Tween(frame, "alpha", Alpha(frame), to, SetAlpha(frame),
        { dur = opts.dur or M.NORMAL, ease = opts.ease or (to < Alpha(frame) and "inOut" or "sine"),
          delay = opts.delay, done = opts.done })
end

function M.IsOpen(frame) return frame:IsShown() and not frame.motionClosing end

-- Shows `frame` fading in to `to` (default 1) and rising RISE px. Caught closing, it turns round from where
-- it is, with a shorter fade when it is already mostly on screen.
function M.Open(frame, to)
    to = to or 1
    frame.motionClosing = nil
    local shown = frame:IsShown()
    local fromAlpha = shown and Alpha(frame) or 0
    local _, fromY = M.CurrentOffset(frame)
    if not shown then
        fromY = -M.RISE
        frame:SetAlpha(0)
        frame:Show()
    end
    local left = to > 0 and math.max(0, 1 - fromAlpha / to) or 1
    M.Tween(frame, "alpha", fromAlpha, to, SetAlpha(frame), { dur = M.OPEN * math.max(0.4, left), ease = "sine" })
    M.Tween(frame, "move", fromY, 0, function(y) M.Offset(frame, nil, y) end, { dur = M.OPEN, ease = "out" })
end

-- Fades `frame` out sinking SINK px, then hides it and puts its alpha back to `rest` (default 1) for the
-- next show. done() runs once it is hidden; a reopen meanwhile drops it.
function M.Close(frame, done, rest)
    if not frame:IsShown() then call(done) return end
    if frame.motionClosing then return end
    frame.motionClosing = true
    local _, y = M.CurrentOffset(frame)
    M.Tween(frame, "move", y, y - M.SINK, function(v) M.Offset(frame, nil, v) end, { dur = M.CLOSE })
    M.Tween(frame, "alpha", Alpha(frame), 0, SetAlpha(frame), {
        dur = M.CLOSE, ease = "inOut",
        done = function()
            if not frame.motionClosing then return end -- reopened meanwhile
            frame.motionClosing = nil
            M.Stop(frame, "move")
            M.Offset(frame, 0, 0)
            frame:Hide()
            frame:SetAlpha(rest or 1)
            call(done)
        end,
    })
end

-- Hides `frame` now, ending whatever it was doing (a fight starting, say).
function M.Hide(frame, rest)
    frame.motionClosing = nil
    M.Stop(frame)
    M.Offset(frame, 0, 0)
    frame:Hide()
    if rest then frame:SetAlpha(rest) end
end

-- Makes Escape close `frame` with its animation: a 1x1 stand-in sits in UISpecialFrames, the game hides it
-- on Escape, and that closes the real window. close(frame) does the closing (default M.Close).
local proxies = 0
function M.WireEscape(frame, close)
    if frame.motionEscape then return end
    proxies = proxies + 1
    local name = ADDON .. "MotionEsc" .. proxies
    local esc = CreateFrame("Frame", name, UIParent)
    esc:SetSize(1, 1)
    esc:Hide()
    esc:SetScript("OnHide", function(self)
        -- Hidden with UIParent (Alt+Z) is no Escape: then it is still shown itself.
        if not self:IsShown() and frame:IsShown() then (close or M.Close)(frame) end
    end)
    tinsert(UISpecialFrames, name)
    frame.motionEscape = esc
    frame:HookScript("OnShow", function() esc:Show() end)
    frame:HookScript("OnHide", function() esc:Hide() end)
    if frame:IsShown() then esc:Show() end
end

-- ---------------------------------------------------------------------------------------------------------
-- Content
-- ---------------------------------------------------------------------------------------------------------

-- One piece fades in to its `restAlpha` (default 1) and lifts LIFT px, after `delay`.
function M.Piece(piece, delay, dur, lift)
    delay, dur, lift = delay or 0, dur or M.PIECE, lift or M.LIFT
    if not M.enabled then
        M.Stop(piece)
        M.Offset(piece, 0, 0)
        piece:SetAlpha(piece.restAlpha or 1)
        return
    end
    M.Stop(piece, "move")
    M.Offset(piece, 0, 0)
    piece:SetAlpha(0) -- hidden now, so nothing flashes before its turn
    M.Tween(piece, "alpha", 0, piece.restAlpha or 1, SetAlpha(piece), { dur = dur, ease = "sine", delay = delay })
    if lift ~= 0 and Home(piece) then
        M.Offset(piece, nil, -lift)
        M.Tween(piece, "move", -lift, 0, function(y) M.Offset(piece, nil, y) end, { dur = dur, delay = delay })
    end
end

-- Pieces in reading order, one after another from `firstDelay`; after MAX_STAGGER the rest come with the
-- last of those, so a long list never keeps anyone waiting. Hidden and protected pieces are left alone.
function M.Stagger(pieces, firstDelay)
    firstDelay = firstDelay or 0
    local i = 0
    for _, piece in ipairs(pieces) do
        if piece:IsShown() and not (piece.IsProtected and piece:IsProtected()) then
            i = i + 1
            M.Piece(piece, firstDelay + math.min(i - 1, M.MAX_STAGGER - 1) * M.GAP)
        end
    end
end

-- Counts a FontString to `to` from the number it showed last; the first number, and the same one again, are
-- set at once. fmt(n) makes the text (default: the number).
function M.CountTo(fs, to, fmt, dur)
    fmt = fmt or tostring
    local from = fs.motionShown
    fs.motionShown = to
    if type(from) ~= "number" or from == to then
        M.Stop(fs, "count")
        fs:SetText(fmt(to))
        return
    end
    M.Tween(fs, "count", from, to, function(v)
        fs:SetText(fmt(v == to and to or math.floor(v + 0.5)))
    end, { dur = dur or M.SLOW })
end

-- Resizes `frame` to w, h (nil keeps that side) from its size now. Asked for the size it is already heading
-- to, it carries on instead of starting over.
function M.Size(frame, w, h, dur)
    local w0, h0 = frame:GetWidth(), frame:GetHeight()
    w, h = w or frame.motionW or w0, h or frame.motionH or h0
    if M.IsMoving(frame, "size") and frame.motionW == w and frame.motionH == h then return end
    frame.motionW, frame.motionH = w, h
    if w0 == w and h0 == h then M.Stop(frame, "size") return end
    M.Tween(frame, "size", 0, 1, function(p)
        frame:SetSize(w0 + (w - w0) * p, h0 + (h - h0) * p)
    end, { dur = dur or M.OPEN, ease = "smooth" })
end

-- A frame just laid out somewhere new: drawn where it was (dx, dy from its new place), it glides there.
function M.Glide(frame, dx, dy, dur)
    if dx == 0 and dy == 0 then return end
    M.Tween(frame, "move", 1, 0, function(p) M.Offset(frame, dx * p, dy * p) end, { dur = dur or M.NORMAL })
end

-- A soft light runs once over `over`. `tex` is an additive (SetBlendMode("ADD")) soft-edged texture parented
-- to it; it fades in at the start and out at the end, so it needs no mask. opts: alpha, inset, width, dur, done.
function M.Sweep(tex, over, opts)
    opts = opts or {}
    if not M.enabled then call(opts.done) return end
    local peak, inset = opts.alpha or 1, opts.inset or 0
    if opts.width then tex:SetWidth(opts.width) end
    tex:SetAlpha(0)
    tex:Show()
    M.Tween(tex, "sweep", 0, 1, function(p)
        local w = over:GetWidth() or 0
        tex:ClearAllPoints()
        tex:SetPoint("CENTER", over, "LEFT", inset + p * (w - 2 * inset), 0)
        local a = (p < 0.15 and p / 0.15) or (p > 0.75 and (1 - p) / 0.25) or 1
        tex:SetAlpha(peak * a)
    end, { dur = opts.dur or 0.5, ease = "linear", done = function()
        tex:Hide()
        call(opts.done)
    end })
end

-- ---------------------------------------------------------------------------------------------------------
-- Run by the game (AnimationGroups): what loops or pops. Each region builds its group once and reuses it; a
-- new group per call would never be freed.
-- ---------------------------------------------------------------------------------------------------------

-- Scales `region` from `from` (default 1.15) down to 1: a pop on something new.
function M.Pop(region, from, dur)
    if not M.enabled or not region.CreateAnimationGroup then return end
    local g = region.motionPop
    if not g then
        g = region:CreateAnimationGroup()
        if not g then return end
        g.scale = g:CreateAnimation("Scale")
        g.scale:SetScaleTo(1, 1)
        g.scale:SetSmoothing("OUT")
        region.motionPop = g
    end
    g:Stop()
    g.scale:SetScaleFrom(from or 1.15, from or 1.15)
    g.scale:SetDuration(dur or M.FAST)
    g:Play()
end

-- Breathes `region`'s alpha between `lo` (0.45) and `hi` (1) every `period` (1) seconds, for ever;
-- M.Pulse(region, false) stops it and leaves it at `hi`.
function M.Pulse(region, on, lo, hi, period)
    local g = region.motionPulse
    if not on or not M.enabled then
        if g then g:Stop() end
        region:SetAlpha(hi or 1)
        return
    end
    if not g then
        if not region.CreateAnimationGroup then return end
        g = region:CreateAnimationGroup()
        if not g then return end
        g:SetLooping("BOUNCE")
        g.a = g:CreateAnimation("Alpha")
        g.a:SetSmoothing("IN_OUT")
        region.motionPulse = g
    end
    if g:IsPlaying() then return end
    g.a:SetFromAlpha(hi or 1)
    g.a:SetToAlpha(lo or 0.45)
    g.a:SetDuration((period or 1) / 2)
    g:Play()
end
