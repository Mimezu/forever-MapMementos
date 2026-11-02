# Map Mementos

A small field journal for places worth remembering. Eight symbols, a name, and
up to 1,200 characters of notes. Saved spots appear on the zone/continent map
and on the minimap when nearby. Hover to read your notes; click to edit.

- `/memento` or `/mmemo`: open the journal and browse saved entries.
- `/memento add`: capture your current location and open a new entry.
- `/memento add Old oak ; A peaceful place to rest.`: save immediately.
- Minimap book: left click opens the journal; right click remembers here.
- Drag the minimap book around the rim; its position is saved.
- Select an entry to change its name, symbol or notes, then Save entry.
- Delete, then Confirm? removes the selected entry.

The location is captured when you start a new entry. Walking while writing,
or editing an entry later, does not move it. Unsaved edits are discarded when
you select a different entry. Entries are account-wide. The game writes them
on logout/reload; an abrupt client crash can lose unsaved session changes.

Pins and the book button inherit their parent map's alpha. They therefore
fade with Frame Gambit's map without separate rules or native icon scaling.
The journal opts into Frame Gambit's cinematic-window integration.

World-map pins use saved normalized map coordinates directly, so custom maps
do not depend on HereBeDragons' map database. Parent maps use the client's map
rectangles. New entries also capture world coordinates for the minimap;
older entries can fall back to the client's coordinate conversion API.

## This installation

Built for this Forever/Classic client (interface 16001). Restart the client
if the newly installed addon is not discovered by `/reload`.
Saved entries load through native SavedVariables (`MapMementosDB`); the former
`_SavedVariables.local` bridge is retired.

## Validation

`lua Interface/AddOns/MapMementos/tests/regression.lua` from the game directory.
The offline harness tests entry creation, editing, original-location retention,
icon changes, database reinitialization, unique IDs, failed location capture,
delete confirmation, pin cleanup, and parent-alpha inheritance. It mocks WoW;
it does not verify rendering or the client's actual save loader.

In game: add a marker, walk away, inspect both maps, hover and edit the marker,
reload to confirm persistence, exercise Frame Gambit's minimap fade, and delete
the entry. Also check rotating minimap and zoom levels.

## Libraries

Bundled unchanged: HereBeDragons-2.0 (minor 33) and HereBeDragons-Pins-2.0
(minor 17), by Nevcairiel: https://github.com/Nevcairiel/HereBeDragons
(BSD license as declared by the upstream project).
LibStub is public domain; CallbackHandler-1.0 uses the included Ace3 license.
Sources downloaded 2026-09-20. All required libraries are bundled.

### 1.0.3 controller compatibility investigation
World-map markers now use addon-owned canvas children instead of Blizzard data
providers or pin pools. The bundled Pins library uses a private
MapMementos-MinimapPins-1.0 identity and does not register or refresh a world-map
provider. Other addons' copies of HereBeDragons-Pins are unaffected. The journal
close button hides only the journal, without calling HideUIPanel.
Saved marker data is unchanged. Offline regression checks pass; the client's
gamepad security behavior requires an in-game check after reloading.

### 1.0.4 performance pass
The open world map no longer rebuilds every marker ten times a second: it
redraws when the shown map or canvas size changes, and each marker's position
on a map is computed once. Pins and the minimap book run per-frame code only
while hovered (tooltip fade) or dragged, and the book follows minimap resizes.
`/memento button square` walks the book along a square minimap edge (for
square skins such as EllesmereUI); `round` or `auto` restore the default.
The world map is installed on demand if it loads after login. The unused
`Pins.xml` template was removed.

### 1.0.5 gamepad world-map notes
Forever 1.60.1.70009 added a soft cursor to the gamepad world map. It only snaps
to Blizzard's own pins. While the map is open in gamepad mode, resting that
cursor on a memento now shows its note, using Blizzard's 12 px reach. The code
only reads the cursor position and changes nothing but this addon's own buttons;
nothing is registered with the map or its navigation. Tested offline; confirm
in game.

### 1.0.6 no new map buttons while the gamepad map is open
Blizzard's gamepad navigation hooks `CreateFrame`. When an addon creates a
frame inside a window that the gamepad cursor is navigating, Blizzard re-reads
that window's buttons under the addon's taint. Later map opens and closes can
then fail inside Blizzard's navigation code: A stops jumping, B stops closing
windows, and windows lose the gamepad cursor until `/reload`. Map Mementos used
to create a marker button the first time a map with more markers was shown,
which could happen while browsing the open map. It now keeps one button per
saved marker, made while the map is closed. A marker added while the gamepad
map is open gets its button when the map closes. Keyboard/mouse mode is
unchanged.

