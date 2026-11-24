# The guide window's art

`/route guide` draws its look from the textures in `Media/Guide/`. Most of them come from the **QuestRouteUI texture
pack** (made with ChatGPT, 2026-11-23), copied over with the pack's own file names, with only the files the guide uses.
Four files the pack has no counterpart for are drawn by `node tools/art.js`.

A file can be replaced by another with the same name. The new file must be a 32-bit uncompressed TGA with
power-of-two sides. The game reads no PNG/WebP/SVG reliably, and the browser preview shows only TGA. The sizes
below only need to keep their proportions.

## From the texture pack

| Files | What the guide uses them for |
|---|---|
| `frame_ornate_<piece>` (corners 32) | The window's gold frame |
| `panel_fill` | The window's and the menus' background |
| `header_backdrop`, `footer_backdrop` | Behind the header and the footer |
| `divider_gold` | The line under the header |
| `row_normal_<piece>` (corners 16) | A step |
| `row_active_<piece>` | The step you are on |
| `row_complete_<piece>` | A finished step |
| `row_upcoming_<piece>` | A step that waits (for a level, or a quest before it) |
| `row_hover_<piece>` | A step under the mouse |
| `button_normal_<piece>`, `button_hover_<piece>` (corners 16) | Buttons and the menus' edge |
| `step_ring_idle`, `step_ring_current`, `step_ring_done` | The ring around a step's number |
| `progress_empty`, `progress_filled` | The progress segments (their round ends are 8 of 128 px) |
| `toggle_on`, `toggle_off` | Auto Advance |
| `chevron_down` | The level menu |
| `banner_horde` | The pennant in the header, for the Horde (cropped to its middle) |
| `icon_quest_pickup` | Pick up |
| `icon_kill_target` | Do (objectives) |
| `icon_turn_in` | Turn in |
| `icon_quest_complete` | A finished step |
| `icon_timer` | A step that waits |
| `icon_travel` | A tip that sends you somewhere |
| `icon_map_pin` | Before a step's place |
| `icon_waypoint` | Before a distance |
| `icon_settings`, `icon_pin` | The header's settings and pin-the-hub buttons |
| `icon_map_scroll`, `icon_route`, `icon_quest_log` | The footer's Show on Map, Route and Quests |

`<piece>` is `top_left`, `top`, `top_right`, `left`, `center`, `right`, `bottom_left`, `bottom`, `bottom_right`.

Left out of the pack on purpose: the `pressed` and `disabled` buttons, `row_*` strips, the icon atlas, the inventory,
combat and horde-banner icons, glows, status dots, scroll bars, the PNG copies and `Textures.lua`. The guide does not
use them, and everything under `Media` is shipped. The whole pack stays in Downloads.

## Drawn by tools/art.js

| File | Size | Kind | What it is |
|---|---|---|---|
| `Pill` | 32 x 16 | white, tinted | Menu hover |
| `PillLine` | 32 x 16 | white, tinted | The route-kind tag and the "3 / 8" counter (outline on a dark see-through fill) |
| `Tip` | 32 x 32 | colour | A tip: a blue "i" |
| `Banner` | 64 x 128 | colour | The Alliance's pennant. The addon's icon is laid on it. |

## Looks (themes)

The gear's menu has **Look**, which steps through Classic (the art above) and four themes from the Ornate style of
the **QuestRouteUI v2** pack: Horde Ember, Alliance Steel, Emerald Wilds and Arcane Night. Each theme is a folder in
`Media/Guide/` with the same file names as Classic, plus `emblem` (shown where Classic has the pennant). `Pill`,
`PillLine`, `Tip`, `Banner` and `banner_horde` are shared and stay in `Media/Guide/`. The look is kept in
`db.guide.theme`, and the guide is built again when you pick one.

The theme folders are made by `tools/themes.py` (Python 3, Pillow, numpy), not copied by hand:

    python tools/themes.py <folder holding QuestRouteUI/Textures/Themes> [Theme ...]

It cuts the pack's whole row and button textures into nine-slices (the pack's own nine-slices of them have empty
corners), crops off slivers of neighbouring art, and clears the white fringe left by the pack's background removal.
What the pack has no file for it makes: a done row is the plain row tinted green, a waiting row is `row_disabled`,
the step rings are the level ring (dimmed, plain, green), the header and footer are the frame's middle darkened,
and the line under the header is the frame's top edge. The progress bars and the chevron are Classic's.

The pack's DarkForge and Radiant styles are not used: their files are cut wrong (pieces of other art at the edges,
frames without a right or bottom edge). To add a theme, add its folder name to `THEMES` in `tools/themes.py` and to
`THEMES` in `Guide.lua` (with the colour the header fades into).

## Trying new art

1. Put the files in `Media/Guide/`.
2. From `tools`, run `node preview/server.js`, open http://localhost:8377, and type `/route guide`.
3. In the game: `deploy UndeadRoute`, then restart the game (new texture files need it), then `/route guide`.
