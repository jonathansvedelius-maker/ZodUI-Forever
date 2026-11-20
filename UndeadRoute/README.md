# Undead Route

A step-by-step 1-60 leveling route for WoW Forever, for every race and class of both factions. Type `/route`.

It says where to level now and what to do there: the quests of each hub in a walking order, the hand-ins in the order
you pass their givers, your class quests, and which dungeons are worth running for their quests and blue rewards.
An arrow on screen points at the next step, a small tracker lists the next few, and the minimap button opens it all.

## Addons it needs

Undead Route ships no quest data of other addons. At login it builds its quest list from the ones you have installed:

| Addon | Needed for |
|---|---|
| NaowhForever, with its Dungeon Journal, Discovery and Journeys parts | The quest list itself: every quest, its giver, where it is handed in, who can take it |
| ForeverDungeonJournal (recommended) | Dungeon quest rewards, and the objectives of class quest chains |
| ZodUI (optional) | Its look, and its record of quests you handed in |

Without NaowhForever the route still names the zones and hubs, and says at login which addons are missing.
`/route data` lists them, each marked on or missing.

## The quest recorder

As you play, Undead Route records what the game shows of each quest you take: who gives it and where, its rewards and
XP, where its objectives move on, and who takes it in. These recordings are laid over the quest list, and a quest the
list lacks is added. They are kept for your whole account, in
`WTF\Account\<account>\SavedVariables\UndeadRoute.lua`, and hold no names, only side, race and class.
`/route record` says what is kept; `/route record off` pauses it.

To share them: send that file to whoever builds the addon, who puts it in `recordings/` and runs
`node tools/record.js`; the next version ships them in `Recorded.lua`.

## Commands

`/route` opens the route. `/route tracker`, `/route minimap` and `/route arrow` show or hide the tracker, the minimap
button and the arrow. `/route record` and `/route data` are above. `/route help` lists the rest.

## Development

`node tools/run.js .` runs the tests against a stub of the WoW API. They use `Generated.lua`, a local copy of the quest
list built by `node tools/lua.js tools/gen.lua "<WoW>/_forever_/Interface/AddOns" Generated.lua` from the addons
installed on that machine; it is never shipped or committed. `node tools/icon.js` draws the icon and the arrow.
