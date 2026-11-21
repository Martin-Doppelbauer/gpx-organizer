# GPX Organizer

GPX Organizer is a native macOS app for **viewing and organizing a large number of GPX files that are stored on your disk**.
Your folder structure is the database: the app mirrors the folders on the left, shows the tracks of the selected folder
on the map, and lets you sort, move, merge, rename and tidy the files.

**Online maps are shown by default.** Local open-source maps in Garmin format (`.gmap` / `.img`) can be selected in addition.

## Features

**Folders and files**
- Folder tree with the number of track files per folder (at any depth) and a sortable file list below it
  (by name, type, date ascending or descending; waypoint files are grouped by colour).
- Optionally show the tracks of all sub-folders on the map ("Show tracks in subfolders").
- Drag and drop between the list and the folders: dragging copies, holding <kbd>⌥</kbd> moves.
- Rename, create folders, move files to the Trash, select several files (<kbd>⌘</kbd>/<kbd>⇧</kbd>-click) and merge them into one track.
- Arrow keys and Page Up/Down step through the file list.
- While the app is in the background, the shown folder is watched: files that other programs add, remove or rename appear in the list when they happen.
- Search over all folders: file names, folder names, track type, track names and waypoint names/symbols.
- Reads GPX, and also TRC, IKT, PTM/AXE, OVL and TRAIL track files. Export as GPX, KML or CSV.

**Map**
- Many tracks drawn on top of each other, the selected one highlighted; colour and line width can be set per file.
- Hover over a track to see all tracks below the pointer. Zoom with the + / − buttons at the bottom right, with ⌘+ / ⌘−, or with the mouse wheel.
- *File → Print Map …* (⌘P) prints the map as shown: same centre and scale across the window width, landscape paper when the map is wider than high and portrait otherwise, the map extended so that the whole sheet is filled, with a scale bar at the bottom right.
- Four online maps out of the box: OpenTopoMap, TopPlusOpen, TopPlusOpen gray and OpenStreetMap.
  Tiles are cached on disk in your maps folder (size limit adjustable in Settings, 100 MB to 10 GB, default 2 GB; the oldest tiles go first),
  so they load at once next time and also work offline. An area can be downloaded for offline use (small areas only).
- Local Garmin-format maps (`.gmap` folders, `.img` files) can be added from the map menu.
  Locked, vendor-protected maps in Garmin's NT/GMP format are not supported.

**Tracks and waypoints**
- Elevation and speed profile (switch between *Elevation*, *Speed* and *Both* at the bottom right; speed needs time stamps in the file) with range selection, point-by-point track editor (move, insert, delete points, undo/redo).
- Waypoint files are drawn as coloured round markers with an icon taken from the Garmin symbol name. Double-click one to edit it: drag the marker to move it, change name, description and symbol, add or delete waypoints (the original is backed up before saving).
- Tracks are classified as planned, hike, bike ride or car/motorcycle trip from the file contents (timestamps and speed);
  you can pick any other icon per file from an icon matrix (right-click → *Choose Icon …*). The speed limits are adjustable in Settings (⌘,).
  A chosen icon is stored by a plain name (`mountains`, `hike`, `spring` …), the track colour and the icon colour as `RRGGBB` and the line width in points,
  all inside the GPX file as a small metadata entry:
  `<metadata><extensions><gpxorg:icon>mountains</gpxorg:icon><gpxorg:iconcolor>E6191A</gpxorg:iconcolor><gpxorg:color>8C33CC</gpxorg:color></extensions></metadata>`.
  The entry is patched in as text, so everything else in the file stays untouched, and the file's modification date is kept.
  The files and the folder structure are the only database; the app keeps no per-file data in its preferences.
  Formats other than GPX cannot store these choices.
- Route planning (hiking, road bike, mountain bike, car and motorcycle profiles), saved as GPX. Garmin maps route offline: the routing rules are derived from each map's own data at every start, so any map works (maps that are routable are marked in the map list). Online maps route on OpenStreetMap data through brouter.de (the route points are sent to that server).

## Requirements

- macOS 14 or later, Apple Silicon
- Swift 5.9 toolchain (the Xcode Command Line Tools are enough; Xcode is not required)

## Download

Ready-made app: download `GPX-Organizer-<version>.zip` from the [latest release](https://github.com/Martin-Doppelbauer/gpx-organizer/releases/latest),
unpack it and move *GPX Organizer* to your Applications folder. The app is signed ad hoc only, so on the first start use
right-click → *Open* (or run `xattr -dr com.apple.quarantine "GPX Organizer.app"` once).

## Build and run

```sh
git clone https://github.com/Martin-Doppelbauer/gpx-organizer.git
cd gpx-organizer
./build_app.sh
open "dist/GPX Organizer.app"
```

The app is signed ad hoc only. If macOS refuses to open it, right-click the app and choose *Open*.
For a signed and notarized release see [RELEASING.md](RELEASING.md).

## First start

On the first start the app asks where your maps should be stored: it can create a default folder
(`~/Library/Application Support/GPX Organizer/Maps`) or use a folder you choose. The folder gets one sub-folder per
built-in online map for its tile cache. Afterwards your Documents folder is shown on the left; use *Folder…* to switch to
the folder that holds your GPX files.

## Privacy and map services

The app only reads the folders you select. Online maps load tiles from the map providers' servers while you browse.
Please respect their usage policies; the app does not offer bulk downloads of large regions.

Map data and services:
- © OpenStreetMap contributors (ODbL)
- OpenTopoMap (CC-BY-SA), map data © OpenStreetMap contributors, SRTM
- TopPlusOpen © Federal Agency for Cartography and Geodesy (BKG)

## License

GPX Organizer is free software, licensed under the **GNU General Public License v3.0 or later**. See [LICENSE](LICENSE).
Copyright © 2026 Martin Doppelbauer.

GPX Organizer is an independent project and is not affiliated with or endorsed by Garmin Ltd.
Garmin and BaseCamp are trademarks of Garmin Ltd.
