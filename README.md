# GPX Organizer

*This is the technical reference. A plain-language guide for everyone is in the app: Help → GPX Organizer User Guide (source: `Resources/UserGuide.md`).*

GPX Organizer is a native macOS app for **viewing and organizing a large number of GPX files that are stored on your disk**.
Your folder structure is the database: the app mirrors the folders on the left, shows the tracks of the selected folder
on the map, and lets you sort, move, merge, rename and tidy the files.

**Online maps are shown by default.** Local open-source maps in Garmin format (`.gmap` / `.img`) can be selected in addition.

## Features

**Folders and files**
- Folder tree with the number of track files per folder (at any depth) and a sortable file list below it
  (by name, type, date ascending or descending; waypoint files are grouped by color).
- Optionally show the tracks of all sub-folders on the map ("Show tracks in subfolders").
- Drag and drop between the list and the folders: dragging moves, holding <kbd>⌥</kbd> copies (files dragged in from outside are always copied).
- Rename, create folders, move files to the Trash, select several files (<kbd>⌘</kbd>/<kbd>⇧</kbd>-click) and merge them into one track.
- Arrow keys and Page Up/Down step through the file list.
- While the app is in the background, the shown folder is watched: files that other programs add, remove or rename appear in the list when they happen.
- Search over all folders: file names, folder names, track type, track names and waypoint names/symbols.
- Reads GPX, Garmin **FIT** activity files (with heart rate, cadence and power, straight from a Garmin watch or Garmin Connect's *Export Original*), and also TRC, IKT, PTM/AXE, OVL and TRAIL track files. Tracks are drawn in a color by their kind unless a color was set for them: blue (bike ride), green (hike), purple (jogging), red (car or motorcycle) or gray (anything else, planned tracks); the colors and the speed limits are set in Settings → General → Track icons and colors by speed. Colors are chosen the same way everywhere (context menus *Icon Color* / *Track Color* and Settings): the named palette, each name followed by a stroke of its color, and *Other Color …* with the system color panel last. A FIT file is never changed; if you edit it, the result is saved as a new GPX file. Export as GPX, KML or CSV.

**Map**
- Many tracks drawn on top of each other, the selected one highlighted; color and line width can be set per file.
- Hover over a track to see all tracks below the pointer. Zoom with the + / − buttons at the bottom right, with ⌘+ / ⌘−, or with the mouse wheel.
- *File → Print Map …* (⌘P) prints the map as shown: same centre and scale across the window width, landscape paper when the map is wider than high and portrait otherwise, the map extended so that the whole sheet is filled, with a scale bar at the bottom right.
- Four online maps out of the box: OpenTopoMap, TopPlusOpen, TopPlusOpen gray and OpenStreetMap.
  Tiles are cached on disk in your maps folder (size limit adjustable in Settings, 100 MB to 10 GB, default 2 GB; the oldest tiles go first),
  so they load at once next time and also work offline. An area can be downloaded for offline use (small areas only).
- Local Garmin-format maps (`.gmap` folders, `.img` files) can be added from the map menu.
  Locked, vendor-protected maps in Garmin's NT/GMP format are not supported.

**Tracks and waypoints**
- Graph below the map with range selection (drag), point selection (click) and a readout of all shown curves while you move over it; the *Content* button at the bottom right chooses the curves:
  elevation, speed (needs time stamps), heart rate, power and cadence (if the file has them, e.g. Garmin `TrackPointExtension` `hr` / `cad` or a `power` entry). Several curves can be shown at once; the graph follows the map (it shows the stretch of the track that the map shows, in the middle 60 % of its width; the shaded part can be dragged to move the map along the track) and can be zoomed on its own with the mouse wheel or by pinching, moved sideways with two fingers, or zoomed with the magnifier buttons below it (*Reset Zoom* returns to the map's stretch; the height scales then fit the zoomed part);
  the elevation scale is on the right, the scale of the first other curve on the left. Also in the track editor: point-by-point track editor (move, insert, delete points, undo/redo). Its *Waypoints* list shows for every point the number, position, distance from the start and height, and in a second line the leg to the next point: distance, time, speed and direction (none for the last point).
- Waypoint files are drawn as colored round markers with an icon taken from the Garmin symbol name. Double-click one to edit it: drag the marker to move it, change name, description and symbol, add or delete waypoints (the original is backed up before saving).
- Tracks are classified as planned, hike, bike ride or car/motorcycle trip from the file contents (timestamps and speed);
  you can pick any other icon per file from an icon matrix (right-click → *Choose Icon …*). The speed limits are adjustable in Settings (⌘,).
  A chosen icon is stored by a plain name (`mountains`, `hike`, `spring` …), the track color and the icon color as `RRGGBB` and the line width in points,
  all inside the GPX file as a small metadata entry:
  `<metadata><extensions><gpxorg:icon>mountains</gpxorg:icon><gpxorg:iconcolor>E6191A</gpxorg:iconcolor><gpxorg:color>8C33CC</gpxorg:color></extensions></metadata>`.
  The entry is patched in as text, so everything else in the file stays untouched, and the file's modification date is kept.
  The files and the folder structure are the only database; the app keeps no per-file data in its preferences.
  Formats other than GPX cannot store these choices.
- Online maps are a list you manage in Settings → Maps: reorder, edit, remove, reset to the original four, or add. *Add …* offers free maps per continent
  and searches a web address you type (a tile address, a server, a web page with a map, WMTS or ArcGIS services; typing errors are tolerated) for maps
  and asks which ones to take. Maps that need an access key are not offered.
- Aerial imagery (like BirdsEye): the picture button in the toolbar (⇧⌘I) shows free aerial or satellite images above the map, with a slider for the opacity
  (at less than 100 % the map shows through, so roads and names stay visible). The servers are a list in Settings → Aerial, managed like the online maps
  (add by continent or web address, edit, remove, reorder, reset). Included by default: Esri World Imagery and Sentinel-2 cloudless; the catalogue adds
  national aerial images (Switzerland, France, Austria, Netherlands, Bavaria, Spain, USA, Japan). The images also appear in the printed map.
- *Replace Elevation Data …* (right-click a track in the list or on the map; several files at once): the heights of the track points are replaced by terrain-model
  values (open-meteo.com) and ascent and descent are calculated again; the original of each file goes to the Trash first.
- Markers (= GPX waypoints): right-click the map → *New Marker*, or ⌘-click. Each marker has a heading, a description (shown as a tooltip),
  an icon, a color and a size; its position is moved by dragging it. The sheet asks every time whether the marker is saved as a new GPX file
  or added to a GPX file (default: added to the file selected in the list, otherwise a new file). Double-click a marker or right-click →
  *Edit Marker …* to change it later. Icon, color and size are stored in the file (`gpxorg:micon`, `gpxorg:mcolor`, `gpxorg:msize` inside the `<wpt>`).
- Route planning with elevation profile (hiking, jogging, mountain bike, touring bike, road bike, car and motorcycle profiles), saved as GPX. Garmin maps route offline: the routing rules are derived from each map's own data at every start, so any map works (maps that are routable are marked in the map list). Online maps route on OpenStreetMap data through brouter.de (the route points are sent to that server).
  Start a route with a right-click on the map (*Start Route Here* / *Finish Route Here*), add points by clicking the map or a marker (a marker's heading becomes the
  name of the point). Every route point can be renamed in the list. Routes are saved either as a complete track (all points), as a planned GPX route with only
  your route points, or as a planned route with additional via points, so a device can calculate the way itself. *Stages …* splits a long route into days
  by distance or ascent: it can insert overnight points into the route or save one GPX file per day.
  The estimated time uses an average speed per profile (hiking 4.5, jogging 9, mountain bike 15, touring bike 20, road bike 25 km/h, car and motorcycle 60 km/h), plus a surcharge for every 100 m of ascent (hiking 10 min, jogging 6, mountain bike 4, touring bike 3, road bike 2.5) and, for touring and road bike only, a bonus for every 100 m of descent (1 and 1.5 min; at most a quarter of the flat time).

**Track tools and display**
- In edit mode the scissors menu offers *Crop to Selected Range* (keeps the part between the first and last selected point; select a range by dragging in the elevation
  profile), *Split at Selected Point …* (writes two new files next to the original, the original stays unchanged) and *Smooth* (light, medium or strong moving average of
  position and elevation, for the selected range or the whole track). Everything can be undone with ⌘Z; nothing is saved before you save.
- *Measure* (ruler button): click points on the map, the length up to each point is shown. Esc ends it, right-click removes the last point.
- *Color* (palette button): colors the selected track by **speed** (needs time stamps), **gradient** (needs elevations), **heart rate**, **power** or **cadence**, on the map and in the graph below;
  blue = low or downhill, green = middle, red = high or steep uphill. A legend appears at the top left of the map. The default is the normal track color.
- Small **direction arrows** (white squares with an arrow in the color of the track) run along the selected tracks; switch them off in the same menu.
- The toolbar is grouped like the Finder's: map view, track, editing, route. *View → Show Toolbar Labels* adds a short text below each symbol.
- Several tabs: *View → Show Tab Bar*, then the + button. Every tab has its own folder, selection and map.

**Photos on the map**
- Choose a photo folder (at the first start a dialog asks for it, afterwards in Settings → Storage → Photos). The folder and all its sub-folders are only **read** – no photo is
  added, removed or altered. Photos without GPS data are ignored; RAW formats are not read.
- Position, date and camera are read from the photos' metadata and kept in a cache (index and thumbnails) in the folder "Photos" inside the online-map cache folder; the
  cache is updated at every start, so changes in the photo folder are noticed. The first reading of a large folder takes a few minutes (progress at the top right of the map).
- The photo button in the toolbar switches the stamps on and off (⌥-click or right-click: options, e.g. *only along the selected track*). Wherever photos are, a stamp-sized
  picture of the newest photo is shown, with its date below and the number of photos in a red circle. The areas get finer as you zoom in.
- Click a stamp: a strip with the photos replaces the elevation graph (drag it with the mouse or use the arrows; the ✕ or Esc closes it). Click a photo for a large view with
  full path, date, time and camera; Esc or ✕ closes it, the arrow keys go to the previous and next photo.

**Komoot (unofficial)**
- *File → Connect to Komoot …* (switch to *Import* inside the dialog) lists all your tours (planned and recorded) and marks those that are not found in any folder below the root folder (compared by start time and
  tour number). The marked tours can be downloaded into the folder "Komoot" in the root folder; choose a year to limit the list. the *Export* tab of the same dialog uploads the selected
  track as a new tour. Nothing that already exists on Komoot is ever changed or deleted.
- Komoot has no public interface for private users. The app uses the same undocumented interface as other community tools; it may stop working at any time and may not be
  covered by Komoot's terms of use. E-mail address and password are stored only in the macOS keychain.

**Dark mode**
- *Settings → General → Appearance*: same as the system, light or dark. In dark appearance the maps are shown dark as well (switch it off with *Show the maps dark as well*): the brightness of the map is turned over and every color keeps its hue
  (so water stays blue and forests green). Aerial images are not changed.

**Garmin devices (USB)** – watches and Edge bike computers, in both directions
- *File → Connect to Garmin …* (or the cable icon left of the map choice in the toolbar) (tab *Import from Device*) reads the activity files (FIT) directly from a device connected by USB, without Garmin Connect. Bike computers (Edge) appear as a drive named GARMIN and are read from
  `Garmin/Activities`. Newer watches do not appear as a drive (they use MTP); the app speaks MTP itself. The list shows all activities on the device with date, time and size and marks those whose file name is not yet
  found in your folders; the marked ones are downloaded into the folder "Garmin" in the root folder (year selectable). The device is only read. Use a USB data cable; if another program holds the device
  (e.g. Android File Transfer or Garmin Express), the dialog says so and offers to quit it. The FIT files contain heart rate, cadence and power.
- The tab *Send to Device* (also from the file list's context menu) puts the marked tracks and routes on the device to ride them later. Any supported format is converted to GPX – as a track (the device
  shows it as a course to follow) or as a route (for the device's own turn instructions) – and copied to `Garmin/NewFiles`; the device takes the new courses over when it is unplugged. For a drive the
  dialog can eject the device afterwards. Nothing on the device is changed or deleted, and your own files stay as they are. On an Edge, choose the "Garmin" (mass storage) mode if the device asks.

**Statistics**
- *Statistics → Track Statistics …* (⌥⌘S): number of tracks, distance, ascent and moving time per folder (with or without sub-folders), per year or per month over all folders,
  optionally only recorded tracks (with time stamps) and for one year, with a bar chart.
- *Statistics → Find Duplicate Tracks …*: groups of tracks whose first 100 track points are the same (GPX and FIT files are only compared with each other when the switch at the top allows it). The suggested one to keep is marked; click a track name to show it
  in the main window, or move copies to the Trash (always after a confirmation; they can be put back from the Trash).

## Requirements

- macOS 14 or later, Apple Silicon
- **Using the ready-made app (see Download below): nothing else.** The app only uses libraries that are part of macOS and does not
  start any helper programs, so no developer tools are needed to run it.
- **Building from source only:** the Apple *Command Line Tools* (the Swift compiler; the full Xcode is not required). Install them once:
  1. Open the *Terminal* app (Spotlight: type "Terminal").
  2. Run `xcode-select --install`.
  3. Click *Install* in the window that appears, accept the licence and wait until it is finished (a few minutes, 1–2 GB).
  4. Check with `swift --version`: it should print a version number (Swift 5.9 or newer).

  If macOS ever asks you to install the "command line developer tools" (for example when a Terminal command such as `git`, `swift`
  or `xattr` is used on a Mac that does not have them yet), the steps above are the right answer: click *Install* and wait.

## Download

Ready-made app: download `GPX-Organizer-<version>.zip` from the [latest release](https://github.com/Martin-Doppelbauer/gpx-organizer/releases/latest),
unpack it (double-click) and move *GPX Organizer* to your *Applications* folder.

The app is signed with an Apple Developer ID and notarized by Apple, so it opens with a normal double-click. If macOS asks
whether you want to open an app downloaded from the internet, click **Open**.

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

The app only reads the folders you select (and changes files only when you edit, save or move them; before a file is overwritten, its original goes to the macOS Trash (the app tells you)).
Online maps load tiles from the map providers' servers while you browse. Please respect their usage policies; the app does not offer bulk downloads of large regions.
Data leaves your Mac only for the features you use: map tiles, online routing (the route points go to brouter.de), elevation replacement (the track points go to open-meteo.com)
and Komoot import/export (to Komoot, with your login from the keychain). Photos, their metadata and the photo cache stay on your Mac.

Map data and services:
- © OpenStreetMap contributors (ODbL)
- OpenTopoMap (CC-BY-SA), map data © OpenStreetMap contributors, SRTM
- TopPlusOpen © Federal Agency for Cartography and Geodesy (BKG)

## License

GPX Organizer is free software, licensed under the **GNU General Public License v3.0 or later**. See [LICENSE](LICENSE).
Copyright © 2026 Martin Doppelbauer.

GPX Organizer is an independent project and is not affiliated with or endorsed by Garmin Ltd.
Garmin and BaseCamp are trademarks of Garmin Ltd.
