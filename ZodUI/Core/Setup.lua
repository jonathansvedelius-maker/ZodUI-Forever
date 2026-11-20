local ADDON, ns = ...
local T = ns.T

-- Two pages that are about ZodUI itself.
--   Modules: every module with its switch on one page, for picking what runs.
--   What's new: what each version added. Not in the list on the left; the
--   button in the title bar and /zod news open it.

local ROW = 26

ns.AddPage({
    key = "setup", title = "Modules", order = 99, group = "ZodUI",
    Build = function(page, f)
        local w = ns.PAGE_W
        local intro = T.Text(f, "GameFontHighlightSmall", T.DIM)
        intro:SetPoint("TOPLEFT", 0, -4)
        intro:SetWidth(w)
        intro:SetText("Tick what you want ZodUI to do. Each module has more under Settings.")
        local commands = T.Button(f, "All commands", 120, function() ns.Show("commands") end)
        commands:SetPoint("TOPRIGHT", 0, 0)
        local panel = T.Panel(f, T.PANEL)
        panel:SetPoint("TOPLEFT", 0, -26)
        panel:SetSize(w, ns.PAGE_H - 26)
        local scroll, child = T.Scroll(panel)
        scroll:SetPoint("TOPLEFT", 1, -4)
        scroll:SetSize(w - 2, ns.PAGE_H - 34)
        child:SetSize(w - 2, #ns.order * ROW)
        page.checks, page.descs = {}, {}
        for i, m in ipairs(ns.order) do
            local check = T.Check(child, m.title, 180, function(on)
                if on then m:Enable() else m:Disable() end
                page:Refresh()
            end)
            check:SetPoint("TOPLEFT", 10, -(i - 1) * ROW - 3)
            page.checks[m.key] = check
            local desc = T.Text(child, "GameFontHighlightSmall", T.MUTED)
            desc:SetPoint("TOPLEFT", 200, -(i - 1) * ROW - 6)
            desc:SetWidth(w - 214)
            desc:SetHeight(14)
            desc:SetWordWrap(false)
            page.descs[m.key] = desc
        end
    end,
    Refresh = function(page)
        for _, m in ipairs(ns.order) do
            page.checks[m.key]:SetChecked(m.enabled)
            -- One line has room for the first sentence; pointing at the module shows all of it.
            local desc = m.desc or ""
            local first = desc:match("^(.-%.)%s") or desc
            page.checks[m.key].tip = desc ~= "" and desc or nil
            local text = (m.plugin and ("|cff999999From " .. m.plugin .. ".|r ") or "") .. first
            if m.db.conflict and not m.enabled then text = T.Paint(m.db.conflict .. " does this too. ", T.DIM) .. text end
            for _, addon in ipairs(m.needs or {}) do
                if m.needsAll and not ns.AddOnLoaded(addon) then
                    text = T.Paint("Needs " .. ns.NEEDS[addon].name .. ". ", T.RED) .. text
                end
            end
            if m.enabled and m.unsupported then text = T.Paint("Does nothing on this game client. ", T.RED) .. text end
            page.descs[m.key]:SetText(text)
        end
    end,
})

-- Newest first. One line per thing a player would notice.
ns.NEWS = {
    { "0.64.0", {
        "Settings say which other addon a part of ZodUI needs, and whether you have it: Forever Leveling BiS (Hand-me-downs, Loot shout's upgrades), ForeverDungeonJournal (the Dungeon guide's Forever maps) and Codex Forever (Alt-click on items). General lists all three.",
    } },
    { "0.63.2", {
        "Gold amounts leave out a unit that is 0: 25s, not 25s 0c.",
        "Forever look: notices have the game's tooltip edge in bronze.",
    } },
    { "0.63.1", {
        "The Look setting reads Forever or Modern, so it fits its button; the note under it says what each is.",
    } },
    { "0.63.0", {
        "Forever look: the game's red buttons with yellow text, and the game's own search and text boxes.",
        "Tables shade every other row, so a long list is easier to read along.",
    } },
    { "0.62.1", {
        "The game's frame is drawn under a window's texts and buttons for real now: Undead Route's tracker shows its first line and its fold button on the title band.",
    } },
    { "0.62.0", {
        "Forever look: the game's red X to close a window, and the list on the left in the game's yellow, with the open page in white.",
        "Changing the look or the accent colour asks to reload the interface, so the change is not missed.",
    } },
    { "0.61.0", {
        "Theme: Forever (the game's frames and warm colours) or Modern (flat dark grey), under Settings, General, Look, or /zod look forever and /zod look modern.",
    } },
    { "0.60.3", {
        "The game's frame sits under a window's texts (Undead Route's tracker shows its first line on the title band).",
    } },
    { "0.60.2", {
        "The game's window frame now shows: it is taken from the Options window, or from the game's standard window when that one is not laid out yet or another addon's skin emptied it. /zod look says which, and tries again.",
    } },
    { "0.60.1", {
        "Windows shorter than the game's frame (Undead Route's tracker) get it too, drawn smaller to fit.",
    } },
    { "0.60.0", {
        "ZodUI and Undead Route look like WoW Forever: the game's own window frame on the big windows and its warm dark colours everywhere else. Settings, General, Look switches back to the flat grey (after /reload).",
    } },
    { "0.59.0", {
        "Your group role stays the one you play: Deadly Boss Mods guesses it from your talents and on classic talents often makes you a healer; ZodUI puts it back. Settings, Group match, Keep my group role (it follows the one role you tick there).",
    } },
    { "0.58.0", {
        "Click a Quest done notice to pin the hand-in on the map (and in TomTom, when it is installed).",
        "A long notice wraps to a second line instead of being cut off.",
    } },
    { "0.57.0", {
        "Quest done says where to hand it in, with Undead Route installed: the hub, zone and spot, and who takes it when the route knows (\"Hand it in to Gar'Thok at Razor Hill, Durotar (51.9, 43.5)\").",
    } },
    { "0.56.5", {
        "Your level, name and class, group role and raid membership are read safely everywhere, so none of them can throw a \"secret value\" error.",
    } },
    { "0.56.4", {
        "No more \"secret boolean\" error from the Leveling coach timer: being away is read safely everywhere.",
    } },
    { "0.56.3", {
        "The corner size grip stops when you let go of the mouse button anywhere, also off the grip; before, a window could go on growing for ever.",
    } },
    { "0.56.2", {
        "Settings: the list scrolls only as far as needed to show the chosen module, also while searching, and an open Settings page follows a frame put back in unlock mode.",
    } },
    { "0.56.1", {
        "Unlock mode: right-click the info bar's box puts the bar back at the top too.",
        "The dungeon guide's Next and Back keys work outside a dungeon, on the guide you had last; with the module off they say so.",
        "Settings scrolls the list to the module it opens on.",
    } },
    { "0.56.0", {
        "Dungeon guide: keys for Next, Back and show/hide (Options > Keybindings > ZodUI), and the mouse wheel over the map steps through the route.",
        "Home: a Next up line opens its page when clicked; a line cut short shows all of it when you point at it.",
        "Settings opens on the module you looked at last, when Open the window on the page I had open last is on.",
        "Unlock mode: right-click a gold box to put just that frame back.",
        "Info bar: middle-click opens the to-do list, as on the minimap button.",
    } },
    { "0.55.4", {
        "Commands: the Loot rolls buttons follow the Loot rolls module, not Loot shout.",
    } },
    { "0.55.3", {
        "Characters: the hint's hover goes away with the hint when the module is off.",
    } },
    { "0.55.2", {
        "Notices and Home card values are measured afresh each time, so a longer one is never cut to a stub after a short one.",
        "Dungeon guide: /zod guide export says when nothing is drawn yet instead of giving a line the other end refuses.",
        "Story's Home card shows the newest event even when the newest day only had quests done.",
        "Characters: with many raid lockouts the hint names two and how many more; pointing at it shows them all.",
        "Hand-me-downs are said at the mailbox whenever the list changed, not only when its length did.",
        "Guild loans: the greyed buttons' tip also says that a right-click marks a loan paid back.",
    } },
    { "0.55.1", {
        "Home cards: a long value on the right no longer squeezes the words on the left; Story's card gives its last event the whole line.",
        "Notices are at most 440 px wide; a longer one ends in ... (the whole of it is in chat).",
        "Search keeps its best-first order (no sorting by heading), so Up and Down walk it as shown.",
        "Settings: labels end before their buttons, also with a larger text size.",
        "Dungeon guide: Share is greyed with nothing drawn, an empty route line is refused instead of wiping your own, and /zod guide draw unfolds the guide first. The fold button's tip says Unfold when folded.",
        "The settings box's reply no longer runs under its button.",
    } },
    { "0.55.0", {
        "Vendor: the junk is sold first and the repair comes after, so the grey items can pay for it.",
        "Story: its list keeps its diary order (no sorting by heading); the Home card counts today by the calendar and says when the last thing happened; the export box can be moved.",
        "Clearing the gold ledger or the roll list asks first; the gold one says it was done.",
        "Roll cards: shift-click the item to link it, ctrl-click to try it on, as on the game's own roll frame.",
        "History: point at a day in the chart for its date and its XP or play time.",
        "Dates read the same everywhere also in Gold, Milestones, chat lines and search; Zones sorts Time there by the time; Milestones shows 1,000 not 1000.",
        "Mail: Take all says when the mailbox is empty and shows on the inbox only. Hand-me-downs are said at the mailbox only when the list changed.",
        "Loot shout: upgrades are off at first, as they can be many lines in guild chat.",
        "Raids: 1 person you ran with is online.",
    } },
    { "0.54.0", {
        "Layout: things that sat a little wrong now line up. Board's search box ends inside the page; the Commands rows with many buttons fit; a roll card without Disenchant has no gap between Greed and Pass; hints on Loans, Items and Characters stop before the buttons beside them; What's new lines no longer run into each other.",
        "The controls at the top of Loot, Dungeons, Items and Modules are all as tall as the boxes beside them, and buttons in a row sit 6 px apart on every page.",
        "Loot: Best finds moves to the left when Clear is hidden.",
    } },
    { "0.53.1", {
        "Modules page: each module's line shows its first sentence; pointing at the module shows all of it.",
        "Columns given room for what they hold: Characters (Rested, Seen, Professions), Session (the values), Coach (At your pace).",
    } },
    { "0.53.0", {
        "Lists: the last column ends inside the list, clear of the scroll bar, on every page; before, on many pages a right-aligned number ran a few pixels under it.",
        "Commands: the buttons of a module that is off are greyed and say so.",
        "Settings taken over from a text take effect at once; only a new accent colour still needs /reload.",
        "After an update, the What's new button is marked until you open it, and a notice says ZodUI was updated (as does a first login's tip).",
        "Dungeon guide: how to draw is said in chat the first time only.",
    } },
    { "0.52.0", {
        "Text size (Settings > General) changes at once, without /reload. The accent colour still needs /reload.",
        "Guild loans: Paid back, Agree, Refuse and Forget are greyed until you choose a loan; Forget asks first; right-click a loan to mark it paid back; Enter moves on to the next box.",
        "Dungeon guide: outside a dungeon, /zod guide opens the guide you had last. With the guide hidden or folded, a boss kill's next step comes as a notice instead of a chat line.",
        "The level-up reminder (trainer, talent point) comes as a notice.",
        "The bag warning is said once; it comes back only after the bags had clearly more room, not each time you sell one thing and loot the next.",
    } },
    { "0.51.1", {
        "A list sorted by a column heading stays sorted that way after /reload.",
    } },
    { "0.51.0", {
        "Search: Up and Down choose a result while you type, Enter opens the one chosen.",
        "Reminders and Goals: right-click a row to remove it at once.",
        "Times and dates read the same on every page: just now, 5m ago, today 14:30, yesterday 14:30, 12 Nov 14:30, and the year only for an older date. Date columns sort by the date.",
        "The minimap and info bar tooltips also show gold this session and new mail, and leave out a reminder for the next login, like the bar.",
        "The info bar no longer twitches when a number on it changes every second.",
    } },
    { "0.50.0", {
        "Resize: drag the bottom-right corner of the ZodUI window or the dungeon guide to make it bigger or smaller; a double-click on the corner makes it normal size again. The window's size is the same as Settings > General > Window size, which now goes from 70% to 150%.",
        "Click a column heading in a list to sort by it, again for the other way round, a third time for the page's own order. Gold and numbers sort by their worth.",
        "Home cards: a long line stops before the value on its right instead of running under it.",
        "Notes: Escape while editing a line calls the edit off; a line too long for the list shows in full when you point at it.",
        "Goals and Reminders: the Remove button is greyed until you choose a row, and says so.",
        "Dungeons: a run with someone 13 minutes ago says 13m ago, not just now.",
    } },
    { "0.49.0", {
        "Pages remember how you left them after /reload: Items (this character, most first), Loot (best finds), Reputation (only those gained), History (play time), Characters (sort), Dungeons (by dungeon) and Notes (all characters).",
        "Those buttons say in their tooltip what the page shows now and what a click shows instead.",
        "Pointing at an item on the Items, Loot and Rolls pages shows the item's own tooltip; shift-click puts its link in the chat line. Items also opens in Codex Forever with Alt-click.",
        "The boxes on Guild loans, Goals and Reminders say what goes in them while empty, and Tab moves on to the next box.",
        "The away box can be moved with /zod unlock like the notices and the info bar.",
    } },
    { "0.48.0", {
        "The ZodUI window folds: the - button by the close button, or a double-click on the title bar, makes it a small box with the Undead Route's next step and what wants doing now. A click on a line opens its page; + shows the whole window again.",
        "Buttons that throw something away (Forget this character, Clear the list, Start a new session, Forget the paid ones, Start over in the dungeon guide) ask \"Sure?\" first: click again to go ahead, or move the mouse away to call it off.",
        "Escape in a search box empties it first; the next Escape lets go of the box.",
        "A table cell cut short by its column shows in full in a tooltip when you point at the row.",
        "A notice stays while the mouse is on it, so it can be read to the end.",
        "Folding the dungeon guide keeps its title where it was instead of moving the window.",
    } },
    { "0.47.2", {
        "Dungeon guide: folded, it keeps the Back and Next buttons.",
    } },
    { "0.47.1", {
        "Dungeon guide: the - button by the close button folds it to the next step, about where you are and the Back and Next buttons, without the map; + brings the map back. It stays folded until you unfold it.",
    } },
    { "0.47.0", {
        "Dungeon guide: the route now follows the corridors and caves in 27 dungeons instead of running straight from boss to boss, traced from the dungeon maps themselves. Open-air ones (Zul'Farrak, the Ruins, Krol'dok, the Excavation Site, the Drowned City) keep straight lines; so do Scholomance and the Dire Maul gardens for now.",
    } },
    { "0.46.2", {
        "Dungeon guide: the route is a thick line with a dark edge, gold for the way to the next step, so it shows on any map. The Scarlet Monastery Library's route now follows its corridors, traced from the map.",
    } },
    { "0.46.1", {
        "Dungeon guide: the title no longer runs under the wing buttons, and the Scarlet Monastery Library has its door and its corridors drawn.",
    } },
    { "0.46.0", {
        "Dungeon guide: every dungeon now, 35 guides: all the classic ones (Dire Maul's, Stratholme's and Blackrock Spire's wings told apart like Scarlet Monastery's) and Forever's own. Maps the client lacks come from ForeverDungeonJournal when it is on. Opening the guide on one dungeon and walking into another turns it to the one you are in.",
    } },
    { "0.45.0", {
        "Dungeon guide: all four Scarlet Monastery wings (/zod guide gy, lib, arm, cath, or sm). The game does not always say which wing you are in, so the guide goes by the map, then the room, then which boss dies, and a button per wing switches by hand.",
    } },
    { "0.44.1", {
        "Dungeon guide: Razorfen Kraul too (/zod guide rfk). Outside a dungeon /zod guide shows the one for your level.",
    } },
    { "0.44.0", {
        "Dungeon guide: inside a dungeon the game hides where you stand, so ZodUI shows the dungeon's map with the route drawn on instead: entrance, then each boss in turn. It turns to your floor, moves on when a boss dies and marks about where you are from the room and your last kill. Shadowfang Keep first; /zod guide sfk opens it, /zod guide draw lets you fix the line and Share sends it to others.",
    } },
    { "0.43.0", {
        "Faster: chat ads are read once instead of twice and word by word instead of with a search per word, Chat board finds a repeated ad without looking through them all, the timers are looked at only when one is due instead of every frame, and the window lays out its list of pages only when it changes.",
        "/zod perf start measures what ZodUI itself costs while you play, by module and event; /zod perf shows it, /zod perf stop ends it. Also on the Commands page.",
    } },
    { "0.42.0", {
        "Group listings: the Group Finder only shows your own layer. /zod lfg sfk tank heal lists your group (or you, out of a group) on every layer for 15 minutes; other ZodUI players see it on the Chat board and in Group match. /zod lfg shows the listings, /zod lfg stop takes yours down.",
    } },
    { "0.41.0", {
        "Healer mode: joining a group as its healer puts on your healing equipment set, and leaving the group puts back what you wore. /zod healer set <name> names the set, /zod heal swaps by hand when the group sets no roles.",
    } },
    { "0.40.0", {
        "Recap: at the first login of a week, last week in numbers (time, XP, levels, quests, dungeons, gold, deaths, best finds); coming back after an hour, where you stopped and what waits: quests to hand in, the route's next step, the next level, open to-dos. /zod recap, /zod recap guild.",
        "Hand-me-downs: a Bind on Equip item that is no upgrade for you but is one for another of your characters on this realm is said, marked in its tooltip and named again at the mailbox (with Forever Leveling BiS).",
        "Milestones, under This character: small achievements from what ZodUI keeps, from Level 10 to Twenty levels without dying. Each is said once.",
        "Guild leaderboard: /zod top ranks this week's levels, quests, dungeons and purple finds of your guild's ZodUI players.",
        "Dungeon prep: entering a dungeon lists your quests for it, and with others in your group who run ZodUI, who has which and what you lack. /zod prep share offers yours.",
        "Chat board keeps service ads for two weeks: /zod board crusader says who offered it. Travel: /zod travel says your hearthstone, the route's next stop and the portals offered in chat now.",
        "Loot rules: /zod rules says them in your group's chat; a Need on a Bind on Equip item against them is told to you and kept, and grouping with that player again reminds you.",
        "Mail: sending, an empty subject is filled with the name of what you attach.",
    } },
    { "0.39.0", {
        "Chat board, under Planning: what General, Trade and LookingForGroup sell, buy, offer and look for, on one page by kind, with a search (try 'crusader'). The same ad said again moves up with a count. A click on a row whispers its author.",
        "Group match: a notice when a group needs your role for a dungeon at your level, with their name as a link to whisper. Tick the roles you play under Settings; /zod groups test shows a sample.",
        "Neither hides anything in chat. NaowhForever_QoL's Trade Spam Filter does that, and it is off on this setup.",
    } },
    { "0.38.0", {
        "Quest items: Vendor never sells an item a quest in your log still asks for, finished or not, not even from the always-sell list, and says what it kept. The item's tooltip names the quest and how many you have of how many.",
        "With Undead Route 1.8.5, the items its class quests will ask for count too, before you have the quest: 'Needed later for A Moon-Kissed Blade'.",
    } },
    { "0.37.0", {
        "Commands, under ZodUI in the list on the left: every /zod command as buttons, so nothing needs typing in chat. A field takes a name, a number or a shift-clicked item, recipe or quest, and what the command says shows at the foot of the page.",
        "Another addon's /zod command gets a row there too, under Plugins.",
    } },
    { "0.36.0", {
        "Loot shout: your purple and better loot is said in guild chat with its link, and a green or blue item that is an upgrade for you too (with Forever Leveling BiS). At most one line a minute; /zod shout test shows what it would say.",
        "The list on the left: click a group's heading to fold it away or bring it back, and the list scrolls when it is long. Story, Leveling coach, Raid planner and Guild loans are in it again.",
    } },
    { "0.35.0", {
        "Raid planner: your calendar's events for two weeks with your answer and a notice before each, and for every dungeon and raid who of your characters is saved and who is free. Home's card or /zod raids.",
        "/zod raids group lists who to ask along: the people you ran with who are online in your guild or friends list. /zod raids invite 4 asks the first four.",
        "Your raids with who came and the loot won during each; /zod raids attendance counts who came.",
    } },
    { "0.34.1", {
        "Home's Undead Route card says how many quests are ready to hand in (with Undead Route 1.8.3).",
    } },
    { "0.34.0", {
        "Leveling coach: your XP per played hour, and when you reach the next level, the end of Undead Route's stage, your level goal and 60, in played time and in days. Home's card or /zod coach.",
        "It keeps your best zones by XP per hour, and shows when each of your characters is fully rested.",
    } },
    { "0.33.0", {
        "Story: your character's life day by day, from what ZodUI already keeps: levels, first visits, dungeons and who came along, deaths, good finds and new standings. Home's Story card or /zod story opens it.",
        "/zod story export gives the story as plain text to copy and share; /zod story export 7 gives the last 7 days.",
    } },
    { "0.32.1", {
        "A logo: a hammer in a sun, on the minimap button, in the window's title bar and in the game's addon list.",
    } },
    { "0.32.0", {
        "Guild network: ZodUI in your guild talks to each other. A rare or world boss someone sees in your zone is a notice, /zod guild rares lists them and /zod guild way sets a waypoint.",
        "/zod guild quest and a shift-clicked quest asks who else has it and how far they are; taking a group quest asks by itself.",
        "Guild crafters also asks ZodUI in the guild, which answers with their characters who know the recipe, alts too; your own characters are said at once.",
        "/zod guild shows who in your guild runs ZodUI, and a newer version in the guild is mentioned once. Each part can be switched off in Settings.",
    } },
    { "0.31.0", {
        "Guild crafters: /zod crafters and a shift-clicked recipe asks who in your guild knows it, online first. /zod crafters test checks it works on your realm.",
        "Pet coach keeps your stabled pets (seen at a stable master) with level, loyalty and diet; food tooltips say which pets eat it; /zod pet lists them.",
        "Dungeon runs remember who you ran with: player tooltips, invites and whispers say when, and /zod runs note Bob good tank keeps a note.",
        "Deaths: the spirit healer's cost and how far your corpse is, before you take it. On Hardcore, the deaths the game announces are kept (/zod deaths hardcore).",
        "Settings > General can read notices aloud with the game's text to speech (off unless you tick it).",
    } },
    { "0.30.1", {
        "Loot rolls: no more invisible box in the middle of the screen. The game kept an empty roll container there that grew with every roll and caught the mouse; it is now emptied and hidden.",
    } },
    { "0.30.0", {
        "Guild loans: write down who you lent gold to and who you owe, with /zod loans lend Bob 5g or on its page (Home's Loans card).",
        "With guild members who run ZodUI the list is shared: they agree to the loan, and the one who lent says when it is paid back.",
        "Nobody can put a debt on your list: what someone else writes down waits for your ok (/zod loans ok 2).",
        "After a trade where only gold changed hands with a guild member, a line in chat offers to write it down.",
    } },
    { "0.29.1", {
        "Invites and duels: in a battleground you are no longer released while a soulstone or Reincarnation can get you up (it never saw them on WoW Forever).",
    } },
    { "0.29.0", {
        "Pet care is now the Pet coach, and it works on WoW Forever (it read a function Forever does not have, so it said nothing).",
        "Home shows your pet's mood and damage, loyalty, the food you carry that it eats, training points and pet XP.",
        "Notices when it is unhappy (with the food to give it), loses loyalty, has new training points, runs low on food or dies.",
        "A key that feeds it the best food in your bags: Options > Keybindings > ZodUI > Feed your pet.",
    } },
    { "0.28.1", {
        "Alerts: \"Your hearthstone is ready\" is said once after you use it, and no longer while you fight, skin or mine.",
    } },
    { "0.28.0", {
        "Fewer doubles with EllesmereUI and NaowhForever: the Fight timer, Quest automation and Map coordinates modules are gone (/zod way too; EllesmereUI's /way does the same). /zod where stays.",
        "Info bar: only what the other bars leave out (XP per hour, gold this session, quests, to-dos, the next reminder, mail, speed).",
        "Vendor starts switched off next to NaowhForever_QoL or EllesmereUIQoL, which already sell grey items; switch it on and it stays on.",
        "Chat no longer makes web addresses clickable, Tooltips no longer show ids, Alerts no longer warns about worn gear, and Game settings drops four settings EllesmereUI has (each one it changed is put back).",
        "Loot rolls: a card fading out no longer takes clicks.",
    } },
    { "0.27.0", {
        "With Codex Forever installed: Alt-click an item on the Loot and Rolls pages, or on a roll card, to open it in Codex.",
        "With Codex Forever installed: the search ends with a line that looks the same words up in Codex (items, NPCs, quests, recipes).",
    } },
    { "0.26.0", {
        "Smoother: the window, notices and loot roll cards fade in and out, and a fade that turns round midway never jumps.",
        "Loot rolls: the timer bar glides instead of stepping, and the cards are only redrawn when something changes.",
    } },
    { "0.25.0", {
        "Settings: a module's settings scroll with the mouse wheel when they are taller than the window (General and Info bar were cut off), with a thin gold bar showing how far down you are.",
        "Settings: a long description no longer runs into the Module on box.",
    } },
    { "0.24.3", {
        "Loot rolls: in a group, each roll quietly notes which frames are on screen, so an invisible box that blocks the mouse can be tracked down afterwards.",
    } },
    { "0.24.2", {
        "Loot rolls: a result that comes long after everyone picked lands on your own card again, instead of on a second card for the same item.",
    } },
    { "0.24.1", {
        "Loot rolls: a roll card can no longer stay on screen until a /reload. A roll with no timer leaves after the usual minute, and /zod rolls clear removes any card at once.",
    } },
    { "0.24.0", {
        "Loot rolls: one stack of cards in place of the game's Need / Greed boxes: every open roll at once, a timer, clear buttons, and everyone's pick and roll in their class colours.",
        "Loot rolls: the winner stays on the card for a few seconds (you choose how long), with a sound when it is you.",
        "Rolls page: every roll kept, who it went to, what you picked, and everyone's roll on a click. A Loot rolls card on Home.",
        "/zod rolls test shows two sample rolls; /zod unlock moves the stack.",
    } },
    { "0.23.0", {
        "Other addons can plug into ZodUI: their own modules, pages, cards, notices, commands and ZodUI's look. The route will come back this way as ZodRoute.",
        "A page from another addon is listed under Plugins, and the Modules page says which addon a module comes from.",
    } },
    { "0.22.0", {
        "Home: a Next up card that gathers what wants doing now: a reminder that rang, gear to repair, full bags, quests to hand in, a cooldown that is ready, a rested alt.",
        "Gold: where your gold came from and went, per day and session: loot, quests, merchants, mail, trainers, flights, the auction house.",
        "Characters: profession cooldowns (a transmute, Mooncloth) of every character, and a line at login when one is ready.",
        "Characters: click one for its hearthstone spot and the dungeons and raids it is saved to.",
        "Session: when you reach level 60 at this pace.",
        "Session: XP from kills, from quests and from the rest (exploring and such).",
    } },
    { "0.21.0", {
        "/zod report sums up today in chat: play time, XP, quests, gold, kills and deaths.",
        "/zod report party or guild says the short version there.",
        "/zod played adds up the time played on all your characters.",
        "/zod reload reloads the interface.",
        "A Today card on Home: play time, XP, quests and gold so far today.",
        "History: how many days in a row you have played.",
        "Every module's settings have a Defaults button.",
        "/zod safe switches every module off to find a problem; /zod safe off brings them back.",
        "/zod commands lists every command, and the search finds commands too.",
        "Shift-click on the minimap button shows or hides the info bar.",
    } },
    { "0.20.0", {
        "New module Away timer: a box counts how long you are away, and chat says how long it was.",
        "New module Mail: a Take all button on the mailbox; letters that ask for payment are left alone.",
        "New module Kills: the creatures that gave you XP, by name, today and in all.",
        "New module Deaths: when and where you died, and at what level.",
        "New module Zones: time spent in each zone, when you first came, and the levels you gained there.",
        "New module Quests done: every quest you hand in, with its XP and gold.",
        "New module Break reminder: a nudge after an hour of play (off until you switch it on).",
        "New module Skill-ups: today's skill points on Home.",
        "New module Screenshots: purple loot, new zones and new standings (off until you switch it on).",
        "New module Pet care: for hunters, says when the pet is unhappy or has died.",
    } },
    { "0.19.0", {
        "Reputation: the faction you gain with can become the watched one on your bar (off until you tick it).",
        "Reputation: when you reach the next standing at this session's pace.",
        "Reputation: a button that shows only the factions you gained with since login.",
        "Fight timer: a Home card with today's fights, time fighting and the longest.",
        "Fight timer: a line in chat when a fight is your longest yet (off until you tick it).",
        "Invites and duels can decline guild invites.",
        "Invites and duels can close a charter someone asks you to sign.",
        "Invites and duels can release your spirit at once in a battleground.",
        "Game settings: time stamps in chat.",
        "Game settings: numbers on the health and mana bars, and the target of your target.",
    } },
    { "0.18.0", {
        "Chat: words to watch for (/zod chat watch sfk) play a sound and show in gold.",
        "Chat: /zod chat whispers lists the last whispers you got.",
        "Chat: back from being away, a line says how many whispers came meanwhile.",
        "Chat: /zod chat mentions lists who said your name, and where.",
        "/zod way 45 60 Mill: a spot to walk to, with a notice when you get there.",
        "Info bar: how far the spot from /zod way is.",
        "Click the coordinates under the minimap to put them in the chat box.",
        "A notice when a profession reaches the most your trainer level allows.",
        "A notice when your hearthstone is ready again.",
        "A notice at login when you have mail.",
    } },
    { "0.17.0", {
        "Info bar: how many to-dos are open.",
        "Info bar: gold earned or spent this session.",
        "Info bar: when the next reminder rings.",
        "Info bar: the zone or the spot in it.",
        "Info bar: larger text, under Settings > Info bar.",
        "Info bar: right-click opens its settings.",
        "Info bar: its tooltip shows XP per hour, open to-dos and the next reminder.",
        "Tooltips: the item level of gear.",
        "Tooltips: whom a player or creature is targeting, in red when it is you.",
        "Tooltips: your goal for an item, with how many you have.",
    } },
    { "0.16.0", {
        "Goals: a level to reach, typed as level and the number.",
        "Goals: a line in chat each time you get more of a goal's item.",
        "/zod goals 60 linen cloth adds a goal from chat.",
        "Goals: a button that removes the goals you reached.",
        "Goals: how long a goal will take at the pace since you set it.",
        "/zod vendor sell <item>: Vendor sells that item too, whatever its colour.",
        "/zod vendor keep <item>: Vendor never sells that grey item. /zod vendor list shows both.",
        "A notice when every objective of a quest is done.",
        "Quest automation can pick the reward a merchant pays most for (off until you tick it).",
        "Quest automation can pick the only thing an NPC has to say (off until you tick it).",
    } },
    { "0.15.0", {
        "Characters: when each character will be fully rested.",
        "Characters: time played on all characters, from what /played said on each.",
        "Characters: sort by level, gold, name or when you last played them.",
        "Characters: at login, a line for each other character that is now fully rested.",
        "To do: a v button moves a line down.",
        "To do: Edit puts a line back in the box to change it.",
        "To do: Add weekly makes one that is unticked again on a new week.",
        "To do: the tabs show how many are open.",
        "/zod remind list and /zod remind clear.",
        "/zod remind login check the mail: a reminder for the next time you log in.",
    } },
    { "0.14.0", {
        "Loot: a notice when you loot something blue or better (you choose the quality).",
        "Loot: Best finds keeps your green and better items across sessions, with where you found them.",
        "Loot: what your loot is worth an hour.",
        "Dungeons: a warning on the 4th and 5th dungeon within an hour, the game's limit.",
        "Dungeons: the page says how many dungeons you entered this hour.",
        "Dungeons: click a run and remove it.",
        "Dungeons: walking in says your fastest run there.",
        "Dungeons: the fastest run of each dungeon is marked in gold.",
        "Items: show only this character's items.",
        "Items: sort by how many you have.",
    } },
    { "0.13.0", {
        "Session: gold per hour.",
        "Session: your best XP per hour, from sessions of a quarter of an hour or more.",
        "Session: how many kills gave XP.",
        "Session: the rested XP you have left.",
        "Session: how long the last level took, and the average.",
        "History: the last 7 and 30 days added up, above the days.",
        "History: the chart can show play time instead of XP.",
        "Gold: the last 7 days and the average a day.",
        "Gold: a notice when your gold passes a round sum (100g by default).",
        "Gold: your best day in the ledger.",
    } },
    { "0.12.0", {
        "The window opens on the page you had open last time.",
        "Window opacity under Settings > General.",
        "How long a notice stays is up to you, and a notice can play a sound.",
        "/zod notices lists the last notices, for the one that went by too fast.",
        "Right-click a card on Home to hide it; Settings > General brings them back.",
        "/zod version says which version runs and how many modules are on.",
        "The minimap button's tooltip shows XP per hour, open to-dos and the next reminder.",
        "Middle-click on the minimap button opens the to-do list.",
        "A page opens from the first letters of its name: /zod rem opens Reminders.",
        "Settings > General: a button that puts every hidden card back.",
    } },
    { "0.11.0", {
        "Vendor lets the guild bank pay for the repair when your guild allows it.",
        "Invites and duels can take a resurrection when the caster is out of combat.",
        "Invites and duels can take a summons from someone in your group.",
        "A notice when your rested XP runs out.",
        "A warning when your arrows or bullets run low.",
        "Chat shows your name in gold where others write it.",
        "/zod where says where you stand; /zod where party or guild tells them.",
        "Game settings: turn off the chat language filter, and save screenshots at the best quality.",
        "To do: the ^ button moves a line up.",
        "The info bar can show XP per hour.",
    } },
    { "0.10.0", {
        "To do: Add daily makes one that is unticked again the next day.",
        "Reminders can repeat: tick Repeat, or /zod remind every 30 stretch.",
        "/zod remind 21:30 raid sets a reminder for a time of day.",
        "Snooze gives the reminders that rang ten more minutes.",
        "A notice when your standing with a faction changes.",
        "Fight timer: a new module, off until you switch it on, that times your fights.",
        "Dungeons: By dungeon shows one line per dungeon with fastest and average time.",
        "A filter box on the Loot page.",
        "Enter in the search box opens the first result.",
        "The pages of modules that are off are left out of the list on the left.",
    } },
    { "0.9.0", {
        "The list on the left is in groups: this character, all characters, planning, ZodUI.",
        "The search finds factions and dungeon runs too, and says when there are more results than it shows.",
        "The coordinates under the minimap can be dragged in unlock mode.",
    } },
    { "0.8.0", {
        "The search box in the title bar looks through pages, settings, items, to-dos, reminders, goals and characters.",
        "A greeting at login with how long you were away and your rested XP.",
        "Key bindings for the search, the to-do list and unlock mode.",
    } },
    { "0.7.0", {
        "/zod unlock shows a box for the notices and the info bar: drag them where you want them, then /zod lock.",
        "The Modules page has every module's switch in one place.",
        "This page, and a line in chat when ZodUI was updated.",
    } },
    { "0.6.0", {
        "An accent colour and a window size under Settings > General.",
        "Alerts show as ZodUI notices near the top of the screen.",
        "/zod export and /zod import pass your settings on as a line of text.",
        "A search box in Settings.",
        "The window closes and the info bar fades when a fight starts.",
    } },
    { "0.5.0", {
        "Reminders: /zod remind 20 check the auction.",
        "Goals can save up gold.",
    } },
    { "0.4.0", {
        "History: a diary with one line per day played and a chart of the last two weeks.",
        "Goals: how many of an item you want, with progress on Home.",
        "The cards on Home scroll.",
    } },
    { "0.3.0", {
        "Items: what every character carries and has in the bank, searchable.",
        "Dungeon runs: time, XP, gold and deaths of every visit.",
    } },
    { "0.2.0", {
        "Reputation, alerts for gear and bags, map coordinates, chat links, the info bar.",
    } },
    { "0.1.0", {
        "The window, Session & XP, Loot log, Gold, Characters, To do, Vendor, Quest automation, Tooltips.",
    } },
}

ns.AddPage({
    key = "news", title = "What's new", order = 101, hidden = true,
    Build = function(page, f)
        local w = ns.PAGE_W
        local title = T.Text(f, "GameFontNormalLarge", T.GOLD)
        title:SetPoint("TOPLEFT", 0, -2)
        title:SetText("What's new")
        local panel = T.Panel(f, T.PANEL)
        panel:SetPoint("TOPLEFT", 0, -34)
        panel:SetSize(w, ns.PAGE_H - 34)
        local scroll, child = T.Scroll(panel)
        scroll:SetPoint("TOPLEFT", 1, -6)
        scroll:SetSize(w - 2, ns.PAGE_H - 46)
        child:SetWidth(w - 2)
        -- Each line as tall as it wraps to, so a long one does not run into the next; laid out again
        -- when the text size changes.
        local items = {}
        for _, entry in ipairs(ns.NEWS) do
            local head = T.Text(child, "GameFontNormal", T.GOLD)
            head:SetText(entry[1] .. (entry[1] == ns.version and "  |cff999999this version|r" or ""))
            items[#items + 1] = { head, 12, 22 }
            for i, line in ipairs(entry[2]) do
                local fs = T.Text(child, "GameFontHighlightSmall")
                fs:SetWidth(w - 50)
                fs:SetWordWrap(true)
                fs:SetText(line)
                items[#items + 1] = { fs, 22, nil, i == #entry[2] and 10 or 0 }
            end
        end
        local function Layout()
            local y = 4
            for _, it in ipairs(items) do
                it[1]:ClearAllPoints()
                it[1]:SetPoint("TOPLEFT", it[2], -y)
                y = y + (it[3] or (math.max(12, it[1]:GetStringHeight() or 12) + 6)) + (it[4] or 0)
            end
            child:SetHeight(y)
            if scroll.Sync then scroll:Sync() end
        end
        Layout()
        ns.fontListeners = ns.fontListeners or {}
        table.insert(ns.fontListeners, Layout)
    end,
})
