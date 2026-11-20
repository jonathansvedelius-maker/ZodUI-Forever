local ADDON, ns = ...
local T = ns.T

-- Mail: a Take all button on the mailbox. It takes the gold and the items of
-- every letter, one letter at a time, and leaves letters that ask for payment
-- (cash on delivery) alone.

local M = ns:NewModule("mail", {
    title = "Mail",
    desc = "Adds a Take all button to the mailbox: it takes the gold and items of every letter, and leaves letters that ask for payment alone. It stops when your bags are full.",
    defaults = { enabled = true, auto = false, subject = true },
    options = {
        { type = "check", key = "auto", label = "Take everything as soon as the mailbox opens" },
        { type = "check", key = "subject", label = "Fill an empty subject with the name of what you attach" },
    },
})

local STEP = 0.4 -- seconds between letters: the mailbox drops requests that come too fast
local button, busy, taken, gold

local function Count()
    return GetInboxNumItems and GetInboxNumItems() or 0
end

local function Finish(why)
    busy = false
    if button then button.label:SetText("Take all") end
    if taken > 0 or gold > 0 then
        ns.Print("took " .. taken .. (taken == 1 and " item" or " items") .. (gold > 0 and (" and " .. ns.Money(gold)) or "") .. " from the mail"
            .. (why and (". " .. why) or ".") )
    elseif why then
        ns.Print(why)
    end
end

-- One letter per step, from the last to the first so the numbers do not shift.
local function Step(index)
    if not busy then return end
    if index < 1 then
        Finish()
        return
    end
    local _, _, _, _, money, cod, _, items = GetInboxHeaderInfo(index)
    if (cod or 0) == 0 then
        if (money or 0) > 0 and TakeInboxMoney then
            TakeInboxMoney(index)
            gold = gold + money
        end
        if (items or 0) > 0 and AutoLootMailItem then
            local free = ns.BagSlots()
            if free == 0 then
                Finish("Your bags are full.")
                return
            end
            AutoLootMailItem(index)
            taken = taken + items
        end
    end
    ns.After(STEP, function() Step(index - 1) end)
end

function M:TakeAll()
    if busy or not GetInboxHeaderInfo then return end
    if Count() == 0 then
        ns.Print("the mailbox is empty: nothing to take.")
        return
    end
    busy, taken, gold = true, 0, 0
    if button then button.label:SetText("Taking...") end
    Step(Count())
end

local function Button()
    if button or not MailFrame then return button end
    button = T.Button(InboxFrame or MailFrame, "Take all", 90, function() M:TakeAll() end) -- the inbox tab only
    button:SetSize(90, 22)
    button:SetPoint("TOPRIGHT", MailFrame, "TOPRIGHT", -60, -28)
    button.tip = "Take the gold and items of every letter (ZodUI)"
    M.button = button
    return button
end

M:On("MAIL_SHOW", function(self)
    local b = Button()
    if b then b:Show() end
    if self.db.auto then ns.After(0.5, function() self:TakeAll() end) end
end)

M:On("MAIL_CLOSED", function()
    if busy then Finish() end
end)

function M:OnDisable()
    busy = false
    if button then button:Hide() end
end

-- Sending: the game left the subject empty when an item is attached. It is filled with the item's
-- name (and how many), or "X and 2 more"; text you typed yourself is never replaced.
local filled -- the subject this module last wrote
local ATTACH_MOST = 12

function M.Subject()
    if not GetSendMailItem then return nil end
    local first, count, kinds, seen = nil, 0, 0, {}
    for i = 1, ATTACH_MOST do
        local name, _, _, n = GetSendMailItem(i)
        if type(name) == "string" and name ~= "" then
            if not seen[name] then
                seen[name] = true
                kinds = kinds + 1
            end
            first = first or name
            if name == first then count = count + (tonumber(n) or 1) end
        end
    end
    if not first then return nil end
    if kinds > 1 then return first .. " and " .. (kinds - 1) .. " more" end
    return count > 1 and (first .. " x" .. count) or first
end

M:On("MAIL_SEND_INFO_UPDATE", function(self)
    local box = SendMailSubjectEditBox
    if not (self.db.subject and box and box.GetText and box.SetText) then return end
    local now = box:GetText() or ""
    if now ~= "" and now ~= filled then return end -- typed by you
    local subject = M.Subject()
    if subject then
        filled = subject
        box:SetText(subject)
    elseif now == filled then
        filled = nil
        box:SetText("")
    end
end)
