# ZodUI

A companion suite for WoW Forever. One window, opened with `/zod`, and thirty-one small modules behind it. Each module has its own switch and settings under **Settings**.

ZodUI leaves action bars, unit frames, bags and nameplates to the addons that already do them. It covers what you check and do between fights while leveling.

## Addons it needs

ZodUI runs on its own. Two parts need another addon and do nothing without it; two more get better with one. The module's settings and **Settings > General** say whether each one is installed:

| Addon | Needed for |
|---|---|
| Forever Leveling BiS (better with) | Leveling stat weights by class and level for Hand-me-downs and Loot shout's upgrades. Without it: NaowhForever BiS's weights, simulated on Forever; without both, ZodUI's own, worked out from how the game turns stats into damage (`Core/Weights.lua`). |
| ForeverDungeonJournal | The Dungeon guide's maps of Forever's dungeons and of those the game has no map for (Zul'Farrak, Sunken Temple and more). The game's own maps need nothing. |
| Codex Forever | Alt-click on an item opens it in Codex, and the search ends with a Codex line |

## Modules

| Module | What it does | Starts |
| --- | --- | --- |
| Session & XP | XP per hour, time to the next level, quests and deaths this session, and a log of how long every level took | on |
| History | A diary with one line per day played: time, XP, quests, levels, gold and deaths, and a chart of the last two weeks | on |
| Loot log | What you looted this session and what a merchant pays for it | on |
| Dungeon runs | Times every dungeon and raid visit and keeps its XP, gold and deaths; back in within five minutes continues the run; remembers who you ran with (tooltips, invites, whispers, `/zod runs note`) | on |
| Gold | Gold per character, a day-by-day ledger, and where the gold came from: loot, quests, merchants, mail and more | on |
| Characters | Level, zone, rested XP and when it is full, gold, professions, profession cooldowns, hearthstone and lockouts of every character | on |
| Items | What every character carries and has in the bank, in one searchable list; the bank is read when you open it | on |
| To do | A list to tick off, one per character and one shared | on |
| Reminders | "In 20 minutes: check the auction"; shared by all characters, and said at login when it came due while you were away | on |
| Goals | How many of an item you want to collect, or how much gold to save up, with progress on Home and a message when you get there | on |
| Vendor | Sells grey items and repairs when you open a merchant, from the guild bank when it may; Shift skips it | on (off next to NaowhForever_QoL or EllesmereUIQoL) |
| Info bar | What the EllesmereUI and Naowh bars leave out: XP per hour, gold this session, quest count, open to-dos, the next reminder, new mail, speed | on |
| Tooltips | How many of an item you and your other characters have, what Vendor will sell, item level, your goal for it, whom a unit targets | on |
| Chat | Your name in gold, a sound when your name is said, words to watch for | on |
| Alerts | Bags nearly full, ammunition running low, rested XP gone, trainer and talent reminders on level-up | on |
| Reputation | Standing and progress with every faction, and what you gained since login | on |
| Invites and duels | Declines duels, joins groups of friends and guild members, can take resurrections and summons | off |
| Away timer | Counts how long you are away, and says it when you are back | on |
| Mail | A Take all button on the mailbox; letters that ask for payment are left alone. Sending, an empty subject is filled with what you attach | on |
| Kills | The creatures that gave you XP, by name, today and in all | on |
| Deaths | When and where you died, and at what level; the spirit healer's cost and your corpse's distance; on Hardcore, the deaths the game announces | on |
| Zones | Time spent in each zone, the first visit, the levels gained there | on |
| Quests done | Every quest you hand in, with its XP and gold | on |
| Chat board | What the public channels sell, buy, offer and look for, on one page by kind and searchable, keeping service ads for two weeks; a click whispers the author. `/zod board`, `/zod board crusader` | on |
| Group match | A notice when a group needs your role for a dungeon at your level. `/zod groups test` | on |
| Recap | Each new week, last week in numbers; coming back after an hour, where you stopped and what waits. `/zod recap` | on |
| Hand-me-downs | A Bind on Equip item that is no upgrade for you but is one for another of your characters is said, and named again at the mailbox (with Forever Leveling BiS). `/zod handouts` | on |
| Milestones | Small achievements of your own from what ZodUI keeps: levels, quests, dungeons, finds, gold, zones, levels without dying. `/zod milestones` | on |
| Guild leaderboard | This week's levels, quests, dungeons and purple finds of everyone in your guild who runs ZodUI. `/zod top` | on |
| Dungeon prep | Entering a dungeon lists your quests for it, and with others in your group who run ZodUI, which they have too and which of theirs you lack. `/zod prep`, `/zod prep share` | on |
| Travel | Your hearthstone and when it is ready, where Undead Route sends you, and the portals mages offer in chat right now. `/zod travel`, `/zod travel uc` | on |
| Loot rules | `/zod rules` says your group's loot rules in its chat; a Need on a Bind on Equip item against them is told to you and kept, and grouping with that player again reminds you. `/zod rules log` | on |
| Group listings | The Group Finder only shows your own layer: `/zod lfg sfk tank heal` lists your group, or you, on every layer for 15 minutes over a hidden chat channel, and other ZodUI players see it on the Chat board and in Group match. `/zod lfg`, `/zod lfg stop` | on |
| Dungeon guide | The game hides where you stand inside a dungeon, so this shows the dungeon's own map with the route drawn on: entrance, then each boss in turn. It turns to your floor, moves on when a boss dies, and marks about where you are from the room and your last kill. Draw mode fixes the line; Share/Take pass it on as one line of text. Every classic dungeon and Forever's own, 35 guides; wings of one instance (Scarlet Monastery, Dire Maul, Stratholme, Blackrock Spire) are told apart by map, room, boss kill or a button. Maps the client lacks come from ForeverDungeonJournal when it is on. `/zod guide`, `/zod guide sfk`, `/zod guide rfk`, `/zod guide gy` (lib, arm, cath), `/zod guide draw`, `/zod guide export` | on |
| Healer mode | Joining a group as its healer puts on your healing equipment set (the game's own sets), and leaving the group puts back what you wore; swaps asked for in combat wait for it to end. `/zod healer set <name>`, `/zod heal` | on |
| Quest items | Vendor never sells an item a quest in your log asks for, or one Undead Route's class quests will need; the tooltip names the quest | on |
| Break reminder | A nudge after a while of play without a pause | off |
| Skill-ups | Today's skill points on Home | on |
| Screenshots | Purple loot, a first visit to a zone, a new standing | off |
| Guild loans | Who you lent gold to and who you owe; shared with guild members who run ZodUI, who agree to each loan and to it being paid back. `/zod loans` | on |
| Pet coach | For hunters: mood, loyalty, food, training points and XP on Home; notices; a key that feeds the pet; your stabled pets and which foods each eats (tooltips, `/zod pet`) | on |
| Guild crafters | Who in your guild knows a recipe, online first: `/zod crafters` and a shift-clicked recipe; ZodUI in the guild answers with their characters who know it, alts too | on |
| Loot shout | Says your purple and better loot in guild chat with its link, and green or blue upgrades for you (with Forever Leveling BiS); at most one line a minute. `/zod shout test` | on |
| Raid planner | Calendar events for two weeks with a notice before each; who of your characters is saved or free for each dungeon and raid; who to ask along from the people you ran with; who came to your raids and what was won. `/zod raids` | on |
| Leveling coach | XP per played hour; when you reach the next level, the end of Undead Route's stage, your level goal and 60; your best zones; when each character is fully rested. `/zod coach` | on |
| Story | Your character's life day by day: levels, first visits, dungeons and who came along, deaths, good finds, new standings. `/zod story`, `/zod story export` | on |
| Guild network | ZodUI in your guild talks to each other: rares and world bosses someone sees in your zone (`/zod guild rares`, `/zod guild way`), who else has a quest (`/zod guild quest`), who runs ZodUI (`/zod guild`) | on |
| Game settings | A few of the game's own settings, put back when unticked | off |

A module starts switched off when an installed addon already does its job: the Info bar and Invites next to NaowhForever_QoL, and Vendor next to NaowhForever_QoL or EllesmereUIQoL. Settings says so on that module's page, and you can switch it on anyway. The two item-count lines in tooltips start unticked next to NaowhForever_QoL for the same reason.

With Undead Route installed, Home shows the stage the route wants you on and the next step to walk to, and the Leveling coach forecasts when you finish that stage.

## Look and sharing

Under **Settings > General**: an accent colour (gold, your class colour or one of five others), the window's size, whether the window closes when a fight starts, and whether alerts show as ZodUI's own notices or as the game's red error text, and whether they are read aloud with the game's text to speech. The search box above the module list finds a setting by any word in its name.

The search box in the title bar (or `/zod find linen`) looks through everything at once: pages, settings, items, to-dos, reminders, goals and characters. Click a result to go there.

`/zod unlock` shows a gold box for each ZodUI frame that sits on the screen by itself (the notices, the info bar). Drag the boxes where you want them, then `/zod lock`. `/zod reset` puts everything back.

`/zod export` gives all your settings as one line of text to keep or pass on, and `/zod import` takes such a line. Only settings travel, never gold, notes or anything about a character.

## Commands

Every command below is also a button on the Commands page (`/zod commands`, under ZodUI in the window's list), so none of them needs typing.

| Command | |
| --- | --- |
| `/zod` | Open or close the window |
| `/zod session`, `history`, `loot`, `rolls`, `runs`, `gold`, `alts`, `items`, `rep`, `notes`, `remind`, `goals`, `settings` | Open that page |
| `/zod <module> on` or `off` | Switch a module, for example `/zod databar on` |
| `/zod remind 20 check the auction` | A reminder in 20 minutes |
| `/zod export`, `/zod import` | Your settings as text, and taking over such a text |
| `/zod find <text>` | Search pages, settings and what the modules hold |
| `/zod unlock`, `/zod lock` | Drag the notices, the info bar and the loot rolls into place |
| `/zod remind 21:30 raid` | A reminder for a time of day |
| `/zod remind every 30 stretch` | A reminder that repeats |
| `/zod remind snooze` | Ten more minutes for the reminders that rang |
| `/zod remind login check the mail` | A reminder for the next time you log in |
| `/zod remind list`, `/zod remind clear` | List the reminders, remove the ones that rang |
| `/zod goals 60 linen cloth` | Add a goal; `/zod goals level 30` or `/zod goals gold 100` |
| `/zod rolls test` | Two sample loot rolls; `/zod rolls clear` forgets the kept ones |
| `/zod vendor sell <item>`, `keep`, `forget`, `list` | Items Vendor always sells, or never sells |
| `/zod chat watch sfk` | Watch for a word in say, yell and the channels; also `unwatch`, `whispers`, `mentions` |
| `/zod report` | Today in chat; `/zod report party` or `guild` says it there |
| `/zod played` | Time played on all characters |
| `/zod commands` | Every command as buttons, with fields for names and shift-clicked items |
| `/zod safe`, `/zod safe off` | Every module off to find a problem, and back |
| `/zod reload` | Reload the interface |
| `/zod where` | Where you stand; `/zod where party` or `/zod where guild` says it there |
| `/zod setup` | Every module's switch on one page |
| `/zod news` | What each version added |
| `/zod test` | Show a sample notice |
| `/zod notices` | The last notices again |
| `/zod version` | The version and how many modules are on |
| `/zod rem`, `/zod his` ... | A page opens from the first three letters of its name |
| `/zod modules` | List the modules and whether they are on |
| `/zod errors` | What failed since login; `/zod errors clear` forgets it |
| `/zod perf` | What ZodUI itself costs while you play, by module and event: `/zod perf start`, `/zod perf`, `/zod perf stop` |
| `/zod reset` | Put the windows back where they started |

The minimap button opens the window (right-click: Settings). ZodUI is also in the addon compartment, and under Options > Keybindings > ZodUI you can bind keys to open it, to search, to open the to-do list and to unlock the frames.

## Development

The addon runs outside the game in two ways. Both borrow the Lua VM that Undead Route's tools install (`npm install` in `UndeadRoute/tools`).

**Tests.** `node tools/run.js` loads the files the `.toc` lists against a stub of the WoW API and plays through a session. The stub is strict: a widget has only the methods and scripts its kind has in the game, so a typo or a method on the wrong kind of widget fails there.

**Dungeon guide routes.** The guide's lines follow the corridors because `tools/trace_routes.py` traced them on ForeverDungeonJournal's copies of the dungeon maps (the same pictures the guide shows): the map's sharpest edges are its walls, what reaches the picture's border without crossing one is the parchment outside, and the way between two steps is the cheapest one inside, kept to the middle of the corridors. It writes `ns.GUIDE_TRACED` at the end of `Modules/GuideData.lua` and a picture of every floor with its lines to look over. After changing a route: `node tools/dumpguides.js > guides.json`, then `python -I tools/trace_routes.py guides.json "<WoW>/_forever_/Interface/AddOns/ForeverDungeonJournal/Media" <folder for the pictures>` (needs Pillow, numpy, scipy and scikit-image).

**Benchmark.** `node tools/run.js --bench` times the hot paths (a frame, a trade chat line, loot, bags, XP, tooltips, the open window) and profiles them by module and event with the same profiler as `/zod perf`. The VM is far slower than the game's Lua, so the numbers compare one version with another, not with the game.

**Deploy and release.** `tools/deploy.cmd` (or `deploy.ps1`) copies ZodUI and Undead Route into the game, `tools/release.ps1` zips them, and `tools/publish.ps1` publishes both to the public repo `ZodUI-Forever` with a clean history and a release; `tools/public-README.md` is that repo's README. They expect the two repos side by side.

**Preview.** From `UndeadRoute/tools`, `ADDON_DIR=../../ZodUI PORT=8378 node preview/server.js` draws the window in a browser at http://localhost:8378 with a made-up character (`tools/preview-env.lua`).

Neither replaces a look in the game: the stub is my reading of the API, not the client's.

### Adding a module

A module is one file in `Modules/`, listed in the `.toc`:

```lua
local ADDON, ns = ...

local M = ns:NewModule("example", {
    title = "Example",
    desc = "One sentence for the Settings page.",
    defaults = { enabled = true, loud = false },
    options = { { type = "check", key = "loud", label = "Be loud" } },
})

function M:OnEnable() end           -- at login when on, and when switched on
M:On("PLAYER_LEVEL_UP", function(self, event, level) end)  -- only runs while the module is on
function M:Card() return { title = "Example", lines = { { "Left", "Right" } } } end  -- a card on Home
```

`ns.AddPage` adds a page to the window; `Core/Window.lua` lists the option types. Handlers run guarded, so a module that fails is reported by `/zod errors` and the others keep working.

## For addon authors: plugging into ZodUI

Another addon can add a module, a page, a Home card, Next up lines, search results, commands and movable frames to ZodUI, and build its frames with ZodUI's look. Everything for that is on `ZodUI.api`; `Core/API.lua` lists it with an example. Check `ZodUI.api.level` (now 1) before using it.

## Left to EllesmereUI and NaowhForever

Since 0.28.0 ZodUI no longer does what those suites already do: a fight timer and quest automation (NaowhForever_QoL), map coordinates and `/way` (EllesmereUI), clickable web addresses in chat (EllesmereUIChat), level, gold, bags, durability, hearthstone, zone, coordinates, frame rate and the clock on a bar (EllesmereUI DataBars), item and spell ids in tooltips (Naowh Global Copy), and the worn-gear warning (Naowh Durability).
