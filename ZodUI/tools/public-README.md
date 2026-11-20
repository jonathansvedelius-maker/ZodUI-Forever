# ZodUI and Undead Route for WoW Forever

Two addons for WoW Forever:

- **ZodUI**: a companion suite in one window (`/zod`): session and XP stats, loot log and rolls, gold, your characters, a dungeon guide, alerts and more. See [ZodUI/README.md](ZodUI/README.md).
- **Undead Route**: a step-by-step 1-60 leveling route for every race and class (`/route`). See [UndeadRoute/README.md](UndeadRoute/README.md).

## Installera (svenska)

1. Gå till **[Releases](../../releases/latest)** och ladda ner `ZodUI-….zip` och `UndeadRoute-….zip`.
2. Packa upp båda i `World of Warcraft\_forever_\Interface\AddOns\`.
   Du ska få mapparna `AddOns\ZodUI` och `AddOns\UndeadRoute`, alltså inte `AddOns\ZodUI-0.64.0\ZodUI`.
3. Installera de här addonen också:
   - **Behövs för Undead Route:** NaowhForever med Dungeon Journal, Discovery och Journeys. Rutten läser sin uppdragslista ur dem.
   - **Rekommenderas:** ForeverDungeonJournal, för dungeon-kartorna i ZodUI och dungeon-belöningarna i rutten.
   - **Valfritt:** Forever Leveling BiS (ZodUI:s Hand-me-downs och uppgraderingar i Loot shout) och Codex Forever (Alt-klick på föremål).
4. Starta spelet. Klicka på **AddOns** vid karaktärsvalet och kolla att allt är påslaget.
5. I spelet: `/zod` öppnar ZodUI och `/route` öppnar rutten. `/route data` visar om uppdragslistan hittades.

**Uppdatera:** ta bort de gamla mapparna `ZodUI` och `UndeadRoute` och packa upp de nya.

## Install (English)

Download both zips from **[Releases](../../releases/latest)** and unpack them into `World of Warcraft\_forever_\Interface\AddOns\`, so you get `AddOns\ZodUI` and `AddOns\UndeadRoute`. Undead Route needs NaowhForever (with Dungeon Journal, Discovery and Journeys); ForeverDungeonJournal is recommended; Forever Leveling BiS and Codex Forever are optional. In the game: `/zod`, `/route`, and `/route data` to check the quest list was found.

## Help the route

Undead Route records the quests you take as you play: no names, only side, race and class. Send your
`WTF\Account\<account>\SavedVariables\UndeadRoute.lua` to the author, and the next version will know those quests better.
