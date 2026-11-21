# GPX Organizer

GPX Organizer is a native macOS app for **viewing and organizing a large number of GPX files that are stored on your disk**.
Your folder structure is the database: the app mirrors the folders on the left, shows the tracks of the selected folder
on the map, and lets you sort, move, merge, rename and tidy the files.

**Online maps are shown by default.** Local open-source maps in Garmin format (`.gmap` / `.img`) can be selected in addition.

## Features

**Folders and files**
- Folder tree with the number of track files per folder (at any depth) and a sortable file list below it
  (by name, type, date ascending or descending; waypoint files are grouped by colour).
- Optionally show the tracks of all sub-folders on the map ("Include Subfolders").
- Drag and drop between the list and the folders: dragging copies, holding <kbd>⌥</kbd> moves.
- Rename, create folders, move files to the Trash, select several files (<kbd>⌘</kbd>/<kbd>⇧</kbd>-click) and merge them into one track.
- Arrow keys and Page Up/Down step through the file list.
- Reads GPX, and also TRC, IKT, PTM/AXE, OVL and TRAIL track files. Export as GPX, KML or CSV.

**Map**
- Many tracks drawn on top of each other, the selected one highlighted; colour and line width can be set per file.
- Hover over a track to see all tracks below the pointer.
- Four online maps out of the box: OpenTopoMap, TopPlusOpen, TopPlusOpen gray and OpenStreetMap.
  Tiles are cached in your maps folder; an area can be downloaded for offline use (small areas only).
- Local Garmin-format maps (`.gmap` folders, `.img` files) can be added from the map menu.
  Locked, vendor-protected maps in Garmin's NT/GMP format are not supported.

**Tracks and waypoints**
- Elevation profile with range selection, point-by-point track editor (move, insert, delete points, undo/redo).
- Waypoint files are drawn as coloured round markers with an icon taken from the Garmin symbol name.
- Tracks are classified as planned, hike, bike ride or car/motorcycle trip from the file contents (timestamps and speed);
  you can pick any other icon per file from an icon matrix (right-click → *Choose Icon …*).
- Route planning on a local Garmin map (hiking, road bike, mountain bike, car/motorcycle profiles), saved as GPX.

## Requirements

- macOS 14 or later, Apple Silicon
- Swift 5.9 toolchain (the Xcode Command Line Tools are enough; Xcode is not required)

## Build and run

```sh
git clone https://github.com/Martin-Doppelbauer/gpx-organizer.git
cd gpx-organizer
./build_app.sh
open "dist/GPX Organizer.app"
```

The app is signed ad hoc only. If macOS refuses to open it, right-click the app and choose *Open*.

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
