local _, ns = ...

-- Every route, both factions, in one list. At login Core.lua keeps the stages for the character's
-- faction and race (ns.SelectRoute). One entry per stage:
--   key     saved-variable key (never rename: ticks are stored under it). Two stages may share a key
--           only when no character can get both (different factions or races).
--   kind    "zone" (main route), "dungeon", "alt" (side branch, never auto-recommended) or
--           "city" (a capital's quests at every level, always open)
--   faction "Horde" or "Alliance": only that faction gets the stage. Left out: both do.
--   races   race ids (UnitRace's third value) that get the stage; left out: every race of the faction
--   altRaces race ids that get the stage as a side branch ("alt") instead
--   Horde / Alliance  fields that replace the stage's own for that faction (travel, hub, tasks, ...)
--   zone    the map's English name (used to find the map for a pin, and to notice you are there)
--   hub     where to base yourself; x, y are its approximate Classic coordinates (optional)
--   min     level to arrive at; max is the level to leave at
--   maps    map ids whose quests (ns.ZoneQuests in Generated.lua) are added to this stage. Stages that
--           share a map split its quests by quest level.
--   src     "classic", "new" (Forever content) or "mixed"; replaced once the stage gets quests from the data
--   travel  how to get there
--   tasks   tips only: { t = text }. The quests come from Generated.lua.
--   note    extra advice shown under the tasks
--   dungeon the dungeon's name in Generated.lua: its quests are added to this stage
--           and its level range replaces min / max
--   ally    in the other faction's land: listed, never reminded about (a dungeon)

-- Race ids, as UnitRace returns them. 95 and 96 are WoW Forever's Skyborne.
local HUMAN, ORC, DWARF, NIGHTELF, UNDEAD, TAUREN, GNOME, TROLL = 1, 2, 3, 4, 5, 6, 7, 8
local HIGH_SKYBORNE, WIND_SKYBORNE = 95, 96 -- High Order Skyborne (Alliance), Windshaper Skyborne (Horde)
ns.RaceIds = { HUMAN = HUMAN, ORC = ORC, DWARF = DWARF, NIGHTELF = NIGHTELF, UNDEAD = UNDEAD, TAUREN = TAUREN,
    GNOME = GNOME, TROLL = TROLL, HIGH_SKYBORNE = HIGH_SKYBORNE, WIND_SKYBORNE = WIND_SKYBORNE }
-- The faction of each race, for a client that cannot tell (UnitFactionGroup missing).
ns.RaceFaction = { [HUMAN] = "Alliance", [DWARF] = "Alliance", [NIGHTELF] = "Alliance", [GNOME] = "Alliance",
    [HIGH_SKYBORNE] = "Alliance", [ORC] = "Horde", [UNDEAD] = "Horde", [TAUREN] = "Horde", [TROLL] = "Horde",
    [WIND_SKYBORNE] = "Horde" }

ns.Stages = {
    ---------------------------------------------------------------------------
    -- Horde starting zones
    ---------------------------------------------------------------------------
    {
        key = "deathknell", kind = "zone", faction = "Horde", races = { UNDEAD }, maps = { 1420 },
        zone = "Tirisfal Glades", hub = "Deathknell", x = 30, y = 71,
        min = 1, max = 5, src = "classic",
        travel = "You start here.",
        tasks = {
        },
    },
    {
        key = "brill", kind = "zone", faction = "Horde", races = { UNDEAD }, maps = { 1420 },
        zone = "Tirisfal Glades", hub = "Brill", x = 61, y = 52,
        min = 5, max = 10, src = "classic",
        travel = "Walk north-east from Deathknell along the road.",
        tasks = {
            { t = "Set your hearthstone at the Gallows' End Tavern." },
            { t = "Train in Undercity when you pass it." },
        },
        note = "Undead Paladins: the Whispering Wood and Bandarion Keep class quests open at 10.",
    },
    {
        key = "tirisfal-east", kind = "zone", faction = "Horde", races = { UNDEAD }, maps = { 1420 },
        zone = "Tirisfal Glades", hub = "Brill and the east road", x = 61, y = 52,
        min = 10, max = 12, src = "classic",
        travel = "From Brill, follow the road east.",
        tasks = {
        },
        note = "Stay until 12. Late in beta the quests in this corner were raised in level, so leaving at 10 leaves you short.",
    },
    {
        key = "valley-of-trials", kind = "zone", faction = "Horde", races = { ORC, TROLL }, maps = { 1411 },
        zone = "Durotar", hub = "Valley of Trials", x = 43, y = 68,
        min = 1, max = 6, src = "classic",
        travel = "You start here.",
        tasks = {
        },
    },
    {
        key = "razor-hill", kind = "zone", faction = "Horde", races = { ORC, TROLL }, maps = { 1411 },
        zone = "Durotar", hub = "Razor Hill", x = 52, y = 43,
        min = 6, max = 11, src = "classic",
        travel = "Walk out of the Valley of Trials and follow the road north-east to Razor Hill.",
        tasks = {
            { t = "Set your hearthstone at the Razor Hill inn." },
            { t = "Train in Orgrimmar when you pass it." },
        },
    },
    {
        key = "camp-narache", kind = "zone", faction = "Horde", races = { TAUREN }, maps = { 1412 },
        zone = "Mulgore", hub = "Camp Narache", x = 45, y = 77,
        min = 1, max = 6, src = "classic",
        travel = "You start here.",
        tasks = {
        },
    },
    {
        key = "bloodhoof", kind = "zone", faction = "Horde", races = { TAUREN }, maps = { 1412 },
        zone = "Mulgore", hub = "Bloodhoof Village", x = 47, y = 58,
        min = 6, max = 11, src = "classic",
        travel = "Walk north out of Camp Narache along the road to Bloodhoof Village.",
        tasks = {
            { t = "Set your hearthstone at the Bloodhoof Village inn." },
            { t = "Train in Thunder Bluff when you pass it." },
        },
    },
    {
        key = "zephras-start", kind = "zone", faction = "Horde", races = { WIND_SKYBORNE }, maps = { 2521 },
        zone = "Zephras Isle", hub = "Zephras Isle",
        min = 1, max = 13, src = "new",
        travel = "You start here.",
        tasks = {
            { t = "The island's last quest, The Earthen Ring, sends you to Mulgore. The Barrens come next." },
        },
        note = "New in Forever: the Skyborne's own island.",
    },
    {
        key = "barrens-north", kind = "zone", faction = "Horde", races = { ORC, TROLL, TAUREN, WIND_SKYBORNE },
        maps = { 1413 }, zone = "The Barrens", hub = "The Crossroads", x = 52, y = 30,
        min = 11, max = 16, src = "classic",
        travel = "From Durotar, cross the river west into the Barrens. From Mulgore, take the road north. Follow it to the Crossroads and take the flight path.",
        tasks = {
            { t = "Set your hearthstone at the Crossroads inn." },
        },
    },
    {
        key = "barrens-south", kind = "zone", faction = "Horde", races = { ORC, TROLL, TAUREN, WIND_SKYBORNE },
        maps = { 1413 }, zone = "The Barrens", hub = "Camp Taurajo", x = 44, y = 59,
        min = 16, max = 21, src = "classic",
        travel = "Ride south from the Crossroads to Camp Taurajo. Take the flight path.",
        tasks = {
        },
        note = "Wailing Caverns and Ragefire Chasm fit this stretch.",
    },

    ---------------------------------------------------------------------------
    -- Horde route
    ---------------------------------------------------------------------------
    {
        key = "silverpine-north", kind = "zone", faction = "Horde", races = { UNDEAD }, maps = { 1421 },
        zone = "Silverpine Forest", hub = "The Sepulcher", x = 43, y = 41,
        min = 12, max = 16, src = "classic",
        travel = "Walk south from Tirisfal along the road. Take the flight path at The Sepulcher.",
        tasks = {
        },
    },
    {
        key = "ruins-lordaeron", kind = "dungeon", faction = "Horde", dungeon = "Ruins of Lordaeron", zone = "Tirisfal Glades", hub = "Above the Undercity", x = 61, y = 71,
        min = 15, max = 20, best = 17, src = "new",
        travel = "Fly to Undercity. The entrance is in the ruins above the city.",
        tasks = {
            { t = "Collect the six Horde quests first: four start outside, in Tirisfal, Silverpine and Undercity." },
            { t = "Run it once with all quests, ideally at 17-19." },
            { t = "Do not farm it: repeat runs are slower than questing." },
        },
        note = "New in Forever.",
    },
    {
        key = "silverpine-south", kind = "zone", faction = "Horde", races = { UNDEAD }, maps = { 1421 },
        zone = "Silverpine Forest", hub = "The Sepulcher", x = 43, y = 41,
        min = 16, max = 20, src = "classic",
        travel = "Same hub. The quests are in the south half of the zone.",
        tasks = {
        },
    },
    {
        key = "hillsbrad-1", kind = "zone", faction = "Horde", maps = { 1424 }, zone = "Hillsbrad Foothills", hub = "Tarren Mill", x = 62, y = 20,
        min = 20, max = 25, src = "classic",
        travel = "Walk east from The Sepulcher through the pass into Hillsbrad. From Kalimdor, take the zeppelin from Orgrimmar to Undercity and ride south through Silverpine first. Take the Tarren Mill flight path.",
        tasks = {
            { t = "Set your hearthstone in Tarren Mill." },
        },
        note = "On a PvP realm this zone is contested. If the Alliance camps you, switch to the Kalimdor branch.",
    },
    {
        key = "sfk", kind = "dungeon", faction = "Horde", dungeon = "Shadowfang Keep", zone = "Silverpine Forest", hub = "Shadowfang Keep", x = 45, y = 68,
        min = 22, max = 30, best = 25, src = "classic",
        travel = "Fly to The Sepulcher and ride south. The keep is on the cliff above Pyrewood Village.",
        tasks = {
            { t = "Run it once with all its quests." },
        },
        note = "Optional filler when Hillsbrad chains get hard.",
    },
    {
        key = "kalimdor-20s", kind = "alt", faction = "Horde", maps = { 1442, 1440, 1441 }, zone = "Thousand Needles", hub = "Freewind Post", x = 46, y = 51,
        min = 22, max = 30, src = "classic",
        travel = "From Orgrimmar (zeppelin from the tower outside Undercity), fly or run south through the Barrens.",
        tasks = {
            { t = "Use this only if Hillsbrad is blocked by PvP or overcrowded." },
        },
        note = "Listed zone by zone: Stonetalon Mountains, Ashenvale, then Thousand Needles.",
    },
    {
        key = "hillsbrad-2", kind = "zone", faction = "Horde", maps = { 1424 }, zone = "Hillsbrad Foothills", hub = "Tarren Mill", x = 62, y = 20,
        min = 25, max = 30, src = "mixed",
        travel = "Same hub: Tarren Mill.",
        tasks = {
            { t = "Start the Dalaran attunement: Magus Wordeen Voidglare in Tarren Mill. Needed for City of Dalaran." },
        },
        note = "Fill gaps with Shadowfang Keep, then City of Dalaran from 28.",
    },
    {
        key = "dalaran", kind = "dungeon", dungeon = "City of Dalaran", zone = "Alterac Mountains", hub = "City of Dalaran", x = 20, y = 82,
        min = 28, max = 33, best = 30, src = "new",
        travel = "From Tarren Mill ride west along the lake. Dalaran is at the south-west corner of Alterac Mountains.",
        tasks = {
            { t = "Finish the attunement chain from Magus Wordeen Voidglare (ends in the Dalaran Sewer Key)." },
            { t = "Run it once with all quests, around 29-31." },
        },
        note = "New in Forever. Horde access to the city itself is restricted.",
        Alliance = {
            travel = "From Southshore ride north-west along the lake. Dalaran is at the south-west corner of Alterac Mountains.",
            tasks = {
                { t = "Collect its quests first." },
                { t = "Run it once with all quests, around 29-31." },
            },
            note = "New in Forever.",
        },
    },
    {
        key = "arathi", kind = "zone", faction = "Horde", maps = { 1417 }, zone = "Arathi Highlands", hub = "Hammerfall", x = 73, y = 33,
        min = 30, max = 36, src = "classic",
        travel = "Ride east from Tarren Mill through Thoradin's Wall, then east across Arathi. Take the Hammerfall flight path.",
        tasks = {
            { t = "Set your hearthstone in Hammerfall." },
        },
        note = "Scarlet Monastery fits this whole stretch. Alterac Mountains has its own short list.",
    },
    {
        key = "alterac", kind = "alt", faction = "Horde", maps = { 1416 }, zone = "Alterac Mountains", hub = "Tarren Mill (in Hillsbrad)",
        min = 32, max = 37, src = "classic",
        travel = "North of Tarren Mill. There is no Horde town in Alterac: work out of Tarren Mill.",
        tasks = {
            { t = "A handful of quests only: do them on the way to or from Arathi." },
        },
    },
    {
        key = "zephras", kind = "alt", faction = "Horde", races = { ORC, UNDEAD, TAUREN, TROLL }, maps = { 2521 },
        zone = "Zephras Isle", hub = "Zeppelin landing",
        min = 4, max = 10, src = "new",
        travel = "Horde zeppelin from Mulgore. From Undercity that is a long trip: zeppelin to Orgrimmar, then on to Mulgore.",
        tasks = {
            { t = "An extra low-level zone: only worth the trip on a fresh character short of quests." },
        },
        note = "New in Forever: the Skyborne's starting island.",
    },
    {
        key = "stv", kind = "alt", faction = "Horde", maps = { 1434 }, zone = "Stranglethorn Vale", hub = "Grom'gol Base Camp", x = 32, y = 28,
        min = 32, max = 44, src = "classic",
        travel = "Zeppelin from the tower outside Undercity, or from Orgrimmar, straight to Grom'gol.",
        tasks = {
            { t = "Filler for 32-36, or a fallback if the Riverglades is crowded." },
        },
        note = "The hunting and Desolace centaur quests got better rewards in Forever. The Drowned City is off this coast.",
    },
    {
        key = "drowned-city", kind = "dungeon", dungeon = "The Drowned City", zone = "Stranglethorn Vale", hub = "West of Grom'gol", x = 32, y = 28,
        min = 35, max = 40, best = 37, src = "new",
        travel = "Zeppelin to Grom'gol. The entrance is underwater off the coast to the west.",
        tasks = {
            { t = "Collect its quests first (reported as Horde-side, unverified)." },
            { t = "Bring water breathing if your class has none." },
            { t = "Run it once. Its enemies were softened about 30% on 9 November." },
        },
        note = "New in Forever. Optional: only worth it if a group is already forming.",
        Alliance = {
            travel = "Northern Stranglethorn: the entrance is underwater off the coast west of Grom'gol.",
            tasks = {
                { t = "Collect its quests first." },
                { t = "Bring water breathing if your class has none." },
                { t = "Run it once. Its enemies were softened about 30% on 9 November." },
            },
        },
    },
    {
        key = "riverglades", kind = "zone", maps = { 2548 }, zone = "Riverglades", hub = "Rog'mar",
        min = 36, max = 44, src = "new",
        travel = "Easiest for Horde: boat from Steamwheedle Port in Tanaris to Powderfuse Port. Or walk in from the north of Redridge.",
        tasks = {
            { t = "Get the Rog'mar flight path and set your hearthstone there." },
            { t = "Work outward hub by hub. Move to the next hub when the remaining quests turn orange or red." },
            { t = "Group up for item quests: since 6 November more quest items drop for every party member." },
            { t = "Riding training is reported at 40, at your race's mount vendor." },
            { t = "Collect the Krol'dok Stronghold quests as you pass their givers." },
            { t = "Leave at about 44 by boat from Powderfuse Port to Tanaris." },
        },
        note = "New in Forever. Guides disagree on the start level (33 to 36).",
        Alliance = {
            hub = "Alliance quest hubs",
            travel = "Walk in from the north of Redridge Mountains, or take the boat from Steamwheedle Port in Tanaris to Powderfuse Port.",
            tasks = {
                { t = "Work outward hub by hub. Move to the next hub when the remaining quests turn orange or red." },
                { t = "Group up for item quests: since 6 November more quest items drop for every party member." },
                { t = "Riding training is reported at 40, at your race's mount vendor." },
                { t = "Collect the Krol'dok Stronghold quests as you pass their givers." },
                { t = "Leave at about 44 by boat from Powderfuse Port to Tanaris." },
            },
        },
    },
    {
        key = "badlands", kind = "alt", faction = "Horde", maps = { 1418, 1435 }, zone = "Badlands", hub = "Kargath", x = 4, y = 46,
        min = 36, max = 44, src = "classic",
        travel = "Long ride from Hammerfall through the Wetlands and Loch Modan, past Alliance guards.",
        tasks = {
            { t = "Only if the Riverglades runs dry. Pair it with Swamp of Sorrows (Stonard)." },
        },
    },
    {
        key = "kroldok", kind = "dungeon", dungeon = "Krol'dok Stronghold", zone = "Riverglades", hub = "Krol'dok Stronghold",
        min = 40, max = 45, best = 42, src = "new",
        travel = "Inside the Riverglades.",
        tasks = {
            { t = "Finish the local chains that lead into it before the run." },
            { t = "Run it once with all quests, around 41-43." },
        },
        note = "New in Forever. Rated the best dungeon stop of this stretch.",
    },
    {
        key = "tanaris", kind = "zone", maps = { 1446 }, zone = "Tanaris", hub = "Gadgetzan", x = 51, y = 28,
        min = 44, max = 47, src = "classic",
        travel = "Boat from Powderfuse Port, then ride west from Steamwheedle Port to Gadgetzan. Take the flight path.",
        tasks = {
        },
    },
    {
        key = "zf", kind = "dungeon", dungeon = "Zul'Farrak", zone = "Tanaris", hub = "Zul'Farrak", x = 39, y = 20,
        min = 44, max = 50, best = 46, src = "classic",
        travel = "North-west corner of Tanaris.",
        tasks = {
            { t = "Run it once with the quests." },
        },
    },
    {
        key = "feralas", kind = "zone", faction = "Horde", maps = { 1444 }, zone = "Feralas", hub = "Camp Mojache", x = 75, y = 44,
        min = 46, max = 49, src = "classic",
        travel = "From Tanaris go north into Thousand Needles, then west into Feralas. Take the flight path.",
        tasks = {
        },
        note = "The early chains here are low level by 46: skip any the list marks as low XP.",
    },
    {
        key = "hinterlands", kind = "zone", faction = "Horde", maps = { 1425 }, zone = "The Hinterlands", hub = "Revantusk Village", x = 78, y = 80,
        min = 47, max = 50, src = "classic",
        travel = "Fly to Tarren Mill, ride north-east into the Hinterlands and across to the east coast. Take the flight path.",
        tasks = {
        },
    },
    {
        key = "alcaz", kind = "dungeon", dungeon = "Alcaz Prison", zone = "Dustwallow Marsh", hub = "Alcaz Island", x = 76, y = 18,
        min = 48, max = 53, best = 50, src = "new",
        travel = "Alcaz Island, off the coast near Theramore. Contested: plan the trip.",
        tasks = {
            { t = "Collect its quests first." },
            { t = "Optional. Skip it unless a group is forming." },
        },
        note = "New in Forever.",
        Alliance = { travel = "Alcaz Island, off the coast near Theramore." },
    },
    {
        key = "ungoro", kind = "zone", maps = { 1449 }, zone = "Un'Goro Crater", hub = "Marshal's Refuge", x = 45, y = 7,
        min = 50, max = 53, src = "classic",
        travel = "Enter by the ramp in south-west Tanaris. Marshal's Refuge is at the far north. Take the flight path.",
        tasks = {
            { t = "Keep spare power crystals for Shaper's Terrace." },
        },
        note = "Since 10 November most quests from level 48 reward gold.",
    },
    {
        key = "felwood", kind = "zone", faction = "Horde", maps = { 1448 }, zone = "Felwood", hub = "Bloodvenom Post", x = 34, y = 53,
        min = 53, max = 55, src = "classic",
        travel = "Fly to Splintertree Post or Orgrimmar and ride north through Ashenvale. Take the flight path.",
        tasks = {
        },
    },
    {
        key = "wpl", kind = "zone", faction = "Horde", maps = { 1422 }, zone = "Western Plaguelands", hub = "The Bulwark",
        min = 55, max = 57, src = "classic",
        travel = "Fly to Undercity and ride east. The Bulwark is on the Tirisfal border.",
        tasks = {
        },
    },
    {
        key = "blackmaw", kind = "dungeon", dungeon = "Blackmaw Hold", zone = "Azshara", hub = "Valormok", x = 22, y = 52,
        min = 55, max = 60, best = 57, src = "new",
        travel = "Fly to Valormok in Azshara.",
        tasks = {
            { t = "Collect its quests first." },
            { t = "Run it once with all quests, around 56-58." },
        },
        note = "New in Forever. Rated a strong late stop for Horde.",
        Alliance = { hub = "Blackmaw Hold", x = false, y = false, travel = "In Azshara.", note = "New in Forever." },
    },
    {
        key = "epl", kind = "zone", maps = { 1423 }, zone = "Eastern Plaguelands", hub = "Light's Hope Chapel", x = 71, y = 50,
        min = 57, max = 59, src = "classic",
        travel = "Ride east from the Bulwark through Western Plaguelands. Take the Light's Hope flight path.",
        tasks = {
        },
        Alliance = { travel = "Ride north-east from Chillwind Camp through Western Plaguelands. Take the Light's Hope flight path." },
    },
    {
        key = "winterspring", kind = "zone", maps = { 1452 }, zone = "Winterspring", hub = "Everlook", x = 61, y = 38,
        min = 58, max = 60, src = "classic",
        travel = "Through Timbermaw Hold at the north end of Felwood. Take the Everlook flight path.",
        tasks = {
        },
        note = "Mount Hyjal is reached from here through Darkwhisper Gorge.",
    },
    {
        key = "shapers", kind = "dungeon", dungeon = "Shaper's Terrace", zone = "Un'Goro Crater", hub = "Shaper's Terrace", x = 45, y = 7,
        min = 58, max = 60, best = 59, src = "new",
        travel = "Northern Un'Goro Crater. Fly to Marshal's Refuge.",
        tasks = {
            { t = "Bring the Un'Goro power crystals you saved." },
            { t = "Collect its quests first, then run it once." },
        },
        note = "New in Forever. Stratholme, Scholomance and Blackrock dungeons also fit 58-60.",
    },
    {
        key = "hyjal", kind = "zone", maps = { 2482 }, zone = "Mount Hyjal", hub = "Darkwhisper Gorge",
        min = 60, max = 61, src = "new",
        travel = "From Winterspring through Darkwhisper Gorge.",
        tasks = {
            { t = "Level 60 zone: start it once you are 60." },
            { t = "Raids open 9 December: Barrow Deeps (10), Hyjal Summit (20), Onyxia's Lair (40)." },
        },
        note = "New in Forever. Most guides treat it as endgame, not a leveling zone.",
    },
    {
        key = "undercity", kind = "city", faction = "Horde", maps = { 1458 }, zone = "Undercity", hub = "City quests",
        min = 1, max = 60, src = "classic",
        travel = "Under the Ruins of Lordaeron in Tirisfal Glades. Zeppelins from Orgrimmar and Grom'gol land outside.",
        tasks = {
            { t = "Check this list whenever you are in town to train or sell." },
        },
        note = "City quests open at every level. Many send you out to a zone, so pick them up before you travel.",
    },
    {
        key = "orgrimmar", kind = "city", faction = "Horde", maps = { 1454 }, zone = "Orgrimmar", hub = "City quests",
        min = 1, max = 60, src = "classic",
        travel = "North of Durotar. From Undercity, zeppelin from the tower outside the city to Durotar, then walk in.",
        tasks = {
            { t = "Check this list whenever you pass through, for example on the way to Kalimdor zones." },
        },
        note = "City quests open at every level. Many send you out to a zone, so pick them up before you travel.",
    },
    {
        key = "thunder-bluff", kind = "city", faction = "Horde", maps = { 1456 }, zone = "Thunder Bluff", hub = "City quests",
        min = 1, max = 60, src = "classic",
        travel = "North Mulgore. From Orgrimmar fly to Thunder Bluff; on foot, south through the Barrens into Mulgore.",
        tasks = {
            { t = "Check this list when a flight or a dungeon quest brings you here." },
        },
        note = "City quests open at every level. Many send you out to a zone, so pick them up before you travel.",
    },

    ---------------------------------------------------------------------------
    -- Alliance starting zones
    ---------------------------------------------------------------------------
    {
        key = "northshire", kind = "zone", faction = "Alliance", races = { HUMAN }, maps = { 1429 },
        zone = "Elwynn Forest", hub = "Northshire Abbey", x = 48, y = 42,
        min = 1, max = 6, src = "classic",
        travel = "You start here.",
        tasks = {
        },
    },
    {
        key = "goldshire", kind = "zone", faction = "Alliance", races = { HUMAN }, maps = { 1429 },
        zone = "Elwynn Forest", hub = "Goldshire", x = 42, y = 65,
        min = 6, max = 11, src = "classic",
        travel = "Follow the road south out of Northshire Valley to Goldshire.",
        tasks = {
            { t = "Set your hearthstone at the Lion's Pride Inn." },
            { t = "Train in Stormwind when you pass it." },
        },
    },
    {
        key = "coldridge", kind = "zone", faction = "Alliance", races = { DWARF, GNOME }, maps = { 1426 },
        zone = "Dun Morogh", hub = "Coldridge Valley", x = 29, y = 71,
        min = 1, max = 6, src = "classic",
        travel = "You start here.",
        tasks = {
        },
    },
    {
        key = "kharanos", kind = "zone", faction = "Alliance", races = { DWARF, GNOME }, maps = { 1426 },
        zone = "Dun Morogh", hub = "Kharanos", x = 47, y = 52,
        min = 6, max = 11, src = "classic",
        travel = "Walk out of Coldridge Valley through the tunnel to the north-east, then follow the road to Kharanos.",
        tasks = {
            { t = "Set your hearthstone at the Thunderbrew Distillery in Kharanos." },
            { t = "Train in Ironforge when you pass it." },
        },
    },
    {
        key = "shadowglen", kind = "zone", faction = "Alliance", races = { NIGHTELF }, maps = { 1438 },
        zone = "Teldrassil", hub = "Shadowglen", x = 58, y = 40,
        min = 1, max = 6, src = "classic",
        travel = "You start here.",
        tasks = {
        },
    },
    {
        key = "dolanaar", kind = "zone", faction = "Alliance", races = { NIGHTELF }, maps = { 1438 },
        zone = "Teldrassil", hub = "Dolanaar", x = 56, y = 60,
        min = 6, max = 11, src = "classic",
        travel = "Follow the path south out of Shadowglen to Dolanaar.",
        tasks = {
            { t = "Set your hearthstone at the Dolanaar inn." },
            { t = "Train in Darnassus when you pass it." },
        },
    },
    {
        key = "zephras-start", kind = "zone", faction = "Alliance", races = { HIGH_SKYBORNE }, maps = { 2521 },
        zone = "Zephras Isle", hub = "Zephras Isle",
        min = 1, max = 13, src = "new",
        travel = "You start here.",
        tasks = {
            { t = "The island's last quest, The Magical City of Dalaran, sends you to Alterac Mountains. Westfall and Redridge come next." },
        },
        note = "New in Forever: the Skyborne's own island.",
    },

    ---------------------------------------------------------------------------
    -- Alliance route
    ---------------------------------------------------------------------------
    {
        key = "westfall", kind = "zone", faction = "Alliance", races = { HUMAN, HIGH_SKYBORNE }, altRaces = { DWARF, GNOME, NIGHTELF },
        maps = { 1436 }, zone = "Westfall", hub = "Sentinel Hill", x = 56, y = 47,
        min = 11, max = 16, src = "classic",
        travel = "From Goldshire, follow the road west out of Elwynn Forest into Westfall. Take the Sentinel Hill flight path.",
        tasks = {
        },
        note = "The Deadmines, in Moonbrook, fits the end of this stretch.",
    },
    {
        key = "loch-modan", kind = "zone", faction = "Alliance", races = { DWARF, GNOME }, altRaces = { HUMAN, NIGHTELF, HIGH_SKYBORNE },
        maps = { 1432 }, zone = "Loch Modan", hub = "Thelsamar", x = 35, y = 48,
        min = 11, max = 16, src = "classic",
        travel = "From Kharanos, ride east through the North Gate pass into Loch Modan. Take the Thelsamar flight path.",
        tasks = {
            { t = "Set your hearthstone in Thelsamar." },
        },
    },
    {
        key = "darkshore-1", kind = "zone", faction = "Alliance", races = { NIGHTELF }, maps = { 1439 },
        zone = "Darkshore", hub = "Auberdine", x = 37, y = 44,
        min = 11, max = 16, src = "classic",
        travel = "Take the boat from Rut'theran Village, below Darnassus, to Auberdine. Take the flight path.",
        tasks = {
            { t = "Set your hearthstone in Auberdine." },
        },
    },
    {
        key = "darkshore-2", kind = "zone", faction = "Alliance", races = { NIGHTELF }, maps = { 1439 },
        zone = "Darkshore", hub = "Auberdine", x = 37, y = 44,
        min = 16, max = 20, src = "classic",
        travel = "Same hub: Auberdine. The quests reach north and south along the coast.",
        tasks = {
        },
        note = "Blackfathom Deeps, in north Ashenvale, fits the end of this stretch.",
    },
    {
        key = "redridge", kind = "zone", faction = "Alliance", races = { HUMAN, DWARF, GNOME, HIGH_SKYBORNE }, altRaces = { NIGHTELF },
        maps = { 1433 }, zone = "Redridge Mountains", hub = "Lakeshire", x = 30, y = 46,
        min = 16, max = 21, src = "classic",
        travel = "East of Elwynn Forest, past Three Corners. Take the Lakeshire flight path.",
        tasks = {
        },
    },
    {
        key = "wetlands", kind = "zone", faction = "Alliance", maps = { 1437 }, zone = "Wetlands", hub = "Menethil Harbor", x = 10, y = 60,
        min = 21, max = 26, src = "classic",
        travel = "From Ironforge, ride north through Loch Modan and the Dun Algaz pass. Night elves: boat from Auberdine to Menethil Harbor.",
        tasks = {
            { t = "Set your hearthstone in Menethil Harbor." },
        },
    },
    {
        key = "ashenvale", kind = "zone", faction = "Alliance", races = { NIGHTELF }, altRaces = { HUMAN, DWARF, GNOME, HIGH_SKYBORNE },
        maps = { 1440 }, zone = "Ashenvale", hub = "Astranaar", x = 36, y = 50,
        min = 20, max = 25, src = "classic",
        travel = "Ride south from Auberdine through Darkshore into Ashenvale. From the Eastern Kingdoms, boat from Menethil Harbor to Auberdine first.",
        tasks = {
            { t = "Take the Astranaar flight path." },
        },
    },
    {
        key = "duskwood", kind = "zone", faction = "Alliance", maps = { 1431 }, zone = "Duskwood", hub = "Darkshire", x = 74, y = 46,
        min = 25, max = 30, src = "classic",
        travel = "South of Elwynn Forest. Take the Darkshire flight path.",
        tasks = {
            { t = "Set your hearthstone in Darkshire." },
        },
        note = "The Stockade, in Stormwind, fits this stretch.",
    },
    {
        key = "southshore", kind = "alt", faction = "Alliance", maps = { 1424 }, zone = "Hillsbrad Foothills", hub = "Southshore", x = 51, y = 58,
        min = 24, max = 32, src = "classic",
        travel = "From the Wetlands, ride north over Thandol Span, then west through Arathi to Southshore. Take the flight path.",
        tasks = {
            { t = "On a PvP realm this zone is contested: Tarren Mill is close." },
        },
    },
    {
        key = "arathi", kind = "zone", faction = "Alliance", maps = { 1417 }, zone = "Arathi Highlands", hub = "Refuge Pointe", x = 46, y = 47,
        min = 30, max = 35, src = "classic",
        travel = "North of the Wetlands, over Thandol Span. Take the Refuge Pointe flight path.",
        tasks = {
        },
        note = "Alterac Mountains has its own short list.",
    },
    {
        key = "alterac", kind = "alt", faction = "Alliance", maps = { 1416 }, zone = "Alterac Mountains", hub = "Southshore (in Hillsbrad)",
        min = 32, max = 37, src = "classic",
        travel = "North of Southshore. There is no Alliance town in Alterac: work out of Southshore.",
        tasks = {
            { t = "A handful of quests only: do them on the way to or from Arathi." },
        },
    },
    {
        key = "desolace", kind = "alt", faction = "Alliance", maps = { 1443 }, zone = "Desolace", hub = "Nijel's Point", x = 66, y = 7,
        min = 32, max = 38, src = "classic",
        travel = "From Astranaar ride south-west through Stonetalon Mountains into Desolace. Take the Nijel's Point flight path.",
        tasks = {
        },
    },
    {
        key = "stv", kind = "alt", faction = "Alliance", maps = { 1434 }, zone = "Stranglethorn Vale", hub = "Nesingwary's Expedition", x = 35, y = 10,
        min = 32, max = 44, src = "classic",
        travel = "Ride south from Duskwood into Stranglethorn. Booty Bay is at the far south.",
        tasks = {
            { t = "Filler for 32-36, or a fallback if the Riverglades is crowded." },
        },
        note = "The hunting quests got better rewards in Forever. The Drowned City is off this coast.",
    },
    {
        key = "dustwallow", kind = "alt", faction = "Alliance", maps = { 1445 }, zone = "Dustwallow Marsh", hub = "Theramore Isle", x = 66, y = 45,
        min = 36, max = 42, src = "classic",
        travel = "Boat from Menethil Harbor to Theramore. Take the flight path.",
        tasks = {
        },
    },
    {
        key = "feralas", kind = "zone", faction = "Alliance", maps = { 1444 }, zone = "Feralas", hub = "Feathermoon Stronghold", x = 30, y = 43,
        min = 46, max = 49, src = "classic",
        travel = "From Tanaris go north into Thousand Needles, then west into Feralas. A boat from the Forgotten Coast takes you to Feathermoon Stronghold.",
        tasks = {
        },
        note = "The early chains here are low level by 46: skip any the list marks as low XP.",
    },
    {
        key = "hinterlands", kind = "zone", faction = "Alliance", maps = { 1425 }, zone = "The Hinterlands", hub = "Aerie Peak", x = 14, y = 46,
        min = 47, max = 50, src = "classic",
        travel = "Ride north from Southshore into the Hinterlands. Aerie Peak is in the west. Take the flight path.",
        tasks = {
        },
    },
    {
        key = "felwood", kind = "zone", faction = "Alliance", maps = { 1448 }, zone = "Felwood", hub = "Talonbranch Glade", x = 62, y = 25,
        min = 53, max = 55, src = "classic",
        travel = "Fly to Astranaar and ride north through Ashenvale into Felwood. Talonbranch Glade is in the north-east.",
        tasks = {
        },
    },
    {
        key = "wpl", kind = "zone", faction = "Alliance", maps = { 1422 }, zone = "Western Plaguelands", hub = "Chillwind Camp", x = 43, y = 84,
        min = 55, max = 57, src = "classic",
        travel = "Ride north from Southshore through Alterac into Western Plaguelands. Take the Chillwind Camp flight path.",
        tasks = {
        },
    },
    {
        key = "stormwind", kind = "city", faction = "Alliance", maps = { 1453 }, zone = "Stormwind City", hub = "City quests",
        min = 1, max = 60, src = "classic",
        travel = "North of Elwynn Forest. The Deeprun Tram links it to Ironforge.",
        tasks = {
            { t = "Check this list whenever you are in town to train or sell." },
        },
        note = "City quests open at every level. Many send you out to a zone, so pick them up before you travel.",
    },
    {
        key = "ironforge", kind = "city", faction = "Alliance", maps = { 1455 }, zone = "Ironforge", hub = "City quests",
        min = 1, max = 60, src = "classic",
        travel = "In the mountain at the heart of Dun Morogh. The Deeprun Tram links it to Stormwind.",
        tasks = {
            { t = "Check this list whenever you pass through." },
        },
        note = "City quests open at every level. Many send you out to a zone, so pick them up before you travel.",
    },
    {
        key = "darnassus", kind = "city", faction = "Alliance", maps = { 1457 }, zone = "Darnassus", hub = "City quests",
        min = 1, max = 60, src = "classic",
        travel = "West Teldrassil. From the Eastern Kingdoms: boat from Menethil Harbor to Auberdine, then on to Rut'theran Village.",
        tasks = {
            { t = "Check this list when a flight or a class quest brings you here." },
        },
        note = "City quests open at every level. Many send you out to a zone, so pick them up before you travel.",
    },
}

-- General rules shown at the bottom of every stage.
ns.Rules = {
    "Quests 5 or more levels below you lose XP fast. Rows marked low XP are safe to skip.",
    "Run each dungeon once with all its quests. Repeat runs are slower than questing.",
    "Rested XP builds only in inns and capitals, and doubles kill XP only.",
    "Nobody has tested a route above level 30 on live yet. Treat 30-60 as a plan.",
}
