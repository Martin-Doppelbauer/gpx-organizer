# GPX Organizer – User Guide

This guide is for everyone who simply wants to use the program: no technical knowledge needed.
(The *Technical Reference* in the Help menu describes file formats and details for people who want to know exactly how everything works.)

**Do you use Komoot or a Garmin device?** Then you can start right away: *File → Connect to Komoot …* downloads all your Komoot tours into a folder on your computer and uploads tracks from your computer to Komoot. *File → Connect to Garmin …* (or the cable button in the toolbar) brings the rides recorded on your Garmin watch or Edge bike computer to your computer and sends routes and tracks to the device. See the sections *Garmin watches and bike computers* and *Komoot* below.

## What is GPX Organizer?

If you go hiking, cycling or motorcycling, your tracks and routes end up as files on your computer: recordings from your watch or bike computer, routes you planned, tours from Komoot.
GPX Organizer shows all of them on a map, helps you keep them tidy in folders, lets you plan new routes, and brings tracks to and from your Garmin device.

The most important idea: **your folders are the database.** What you see in the left column is exactly what is on your disk. If you move a file to another folder in the program, it moves on your disk as well, and you can always look at your files with the Finder.

## The first start

- On the first start the program shows the folder *Documents*. Pick the folder that contains your routes: click **Folder …** (below the folder tree) and choose it. The program remembers it.
- Online maps are shown right away, you only need an internet connection. Nothing has to be installed or downloaded.
- If macOS asks whether the program may access a folder (for example *Documents* or an external disk), click **Allow**. The program needs this to see your files.

## The window at a glance

- **Top left – Folders:** your folder tree. Next to each folder the number of track files in it is shown. Click a folder to see its tracks.
- **Bottom left – Files:** the files of the selected folder. Above the list you find the sort menu and a search field.
- **Middle – the map:** all tracks of the selected folder are drawn on it. The track you picked is highlighted.
- **Below the map – the graph:** the elevation profile of the selected track (and, if available, speed, heart rate, power and cadence).
- **Top – the toolbar:** buttons for the Garmin device, the map choice, aerial images, photos, zooming, measuring, colors, the graph, export, editing and route planning.
  If you do not know what a button does, rest the mouse on it for a moment: a hint appears. *View → Show Toolbar Labels* writes a short word under each symbol.

## Looking at your tracks

- **Click a track in the file list:** it is shown on the map and its graph appears below.
- **Click a track on the map:** the same, and the file is marked in the list. When several tracks lie on top of each other, rest the mouse on them to see all of them.
- **Zooming and moving:** drag the map with the mouse. Zoom with the mouse wheel, the **+ / −** buttons at the bottom right, or <kbd>⌘</kbd><kbd>+</kbd> and <kbd>⌘</kbd><kbd>−</kbd>.
- **Show everything:** <kbd>⌘</kbd><kbd>0</kbd> zooms to all tracks shown, <kbd>⌘</kbd><kbd>9</kbd> to the selected track.
- **Several folders at once:** switch on **Show tracks in subfolders** (bottom left) to see the tracks of all folders below the current one.
- **Zooming the graph:** scroll the mouse wheel (or pinch on the trackpad) over the graph to zoom in on a part of the track; the height and heart rate scales then fit that part, so details show. Two fingers sideways move the zoomed part, the magnifier buttons below the graph zoom in and out, and *Reset Zoom* goes back. Without your own zoom the graph shows the part of the track that the map shows; the light blue band is that part, and dragging it moves the map along the track.
- **The graph:** click a point in the graph to see that place on the map; drag to mark a stretch. The button **Content** at the bottom right of the graph chooses which curves are shown (elevation, speed, heart rate, power, cadence).
- **Colors of tracks:** a track without a color of its own is drawn blue for a bike ride, green for a hike, purple for jogging, red for a car or motorcycle trip and gray for everything else (the program tells them apart by the average speed). You can change these colors and the speed limits in *Settings → General → Track icons and colors by speed*. A color you choose yourself for a file always wins.
- **Colors:** the palette button in the toolbar colors the track by speed, slope, heart rate, power or cadence, so you see at a glance where you were fast or where it was steep. Small arrows show the direction of travel.
- **Measuring:** the ruler button lets you click points on the map and tells you the distance.
- **Printing:** *File → Print Map …* (<kbd>⌘</kbd><kbd>P</kbd>) prints the map just as you see it.

## Keeping your files tidy

- **Select several files:** click the first one, then hold <kbd>⇧</kbd> and click the last one for a range, or hold <kbd>⌘</kbd> and click single files. <kbd>⌘</kbd><kbd>A</kbd> selects all files of the folder.
- **Move a file to another folder:** drag it onto a folder in the folder tree. Hold the mouse on a closed folder for a second and it opens, so you can reach sub-folders. The folder you dragged from stays on the screen, so you can go on moving more files.
- **Copy a file instead of moving it:** hold the <kbd>⌥</kbd> key (Option) while dragging. The pointer shows a **+**.
- **Move or copy folders:** the same way, drag a folder onto another folder.
- **Rename:** click a marked file or folder a second time (slowly), or press <kbd>Return</kbd>, then type the new name. Or right-click → *Rename …*.
- **New folder:** right-click a folder → *New Folder …*.
- **Delete:** right-click → *Delete …*. Files and folders only go to the **Trash**, so you can always put them back.
- **Merge tracks:** select several files, right-click → *Merge … Files …*. A new file is created; the originals stay.
- **Sort:** the menu above the file list sorts by name, icon group, type or date. *Reverse Order* turns any of them around.
- **Search:** type into the search field above the list. The program searches all folders: file names, folder names, kinds of track and the names inside the files. Clear the field to return.
- **Icons and colors:** every file has an icon (hike, bike ride, car, mountains …) and can have its own track color and line width. Right-click one or more files → *Choose Icon …*, *Icon Color*, *Track Color*, *Track Width*. This is stored inside the file, so it is still there if you copy it to another computer. *Reset Style* takes it back.
- **A safety net:** whenever the program is about to change a file, it first puts the original in the Trash.
- **Reload:** if another program changed your folders, <kbd>⌘</kbd><kbd>R</kbd> reads them again (the program usually notices by itself).

## Maps

- **Choosing a map:** the map name in the toolbar is a menu. Four online maps are included: OpenTopoMap and TopPlusOpen (good for hiking and cycling), TopPlusOpen gray, and OpenStreetMap.
- **Garmin-format maps:** maps in Garmin format (`.img` files or `.gmap` folders) work without internet, and the program can even plan routes with them. You do not have to buy them: free maps in this format can be **downloaded from the internet** (for example the Freizeitkarte or OpenMTBMap maps of your country). Put the downloaded file into your **maps folder** – the folder shown in *Settings → General → Maps folder* (change it there if you like) – and it appears in the map menu. Or use the **Maps** button → *Add Map …* and pick the file where it is.
- **Aerial images:** the **Aerial** button shows satellite photos. A slider sets how transparent they are, so roads and names stay visible.
- **Offline use:** the **Maps** button → *Download Area for Offline Use …* stores a small region so you can look at it without internet (for example in the mountains).
- **Dark mode:** *Settings → General → Appearance* (or <kbd>⌘</kbd><kbd>,</kbd>) switches between light, dark and "same as the system". In dark mode the maps become dark as well; you can switch that off.

## Changing a track

1. Select a track and click the **Edit** button (pencil) in the toolbar.
2. Drag points to move them, click the map to add a point, select points and delete them, or reverse the direction. The **scissors** menu can cut the track to a selected range, split it in two, or smooth it.
3. Made a mistake? <kbd>⌘</kbd><kbd>Z</kbd> takes it back. Nothing is saved until you save.
4. **Save** replaces the original file (the original goes to the Trash first). **Save as a new file** keeps the original.
5. Click the check mark to finish editing.

Tracks from watches (FIT files) are never changed themselves: when you edit one, the result is saved as a new GPX file next to it.

## Markers (waypoints)

Right-click the map → *New Marker* (or <kbd>⌘</kbd>-click). Give it a name, a description, an icon and a color. You decide whether it goes into a new file or into a file you already have. Markers can be dragged to move them; double-click one to edit it.

## Planning a route

1. Click the **Route** button (or right-click the map → *Start Route Here*).
2. Choose what you travel by: hiking, jogging, mountain bike, touring bike, road bike, car or motorcycle.
3. Click on the map to add points. The program finds the way between them and shows distance and elevation.
4. Drag points to change the route. Points can be named.
5. Save it. A long route can be split into daily stages (*Stages …*).

With Garmin maps the route is calculated on your computer; with online maps the program asks the free service brouter.de (the points of your route are sent there).

## Photos on the map

- The **Photos** button shows your photos where they were taken. At the first use you choose the folder that holds your photos. The program only **reads** them; nothing is changed, moved or deleted.
- A small picture marks each place, with the date and the number of photos. Zoom in to separate them.
- Click a picture: the photos of that place appear in a strip below the map. Click a photo there for a large view. <kbd>Esc</kbd> closes things again.
- Photos without a position are ignored. The first reading of a big photo folder takes a few minutes; you can keep working meanwhile.

## Garmin watches and bike computers

Connect the device with a **USB data cable** (a charging-only cable does not work). Then use **File → Connect to Garmin …** or the cable button at the left of the toolbar. The window has two tabs.

**Import from Device** – bring your rides to the computer
- You see all activities on the device. Those that are not yet in your folders are marked. Choose the ones you want and click **Download**. They go to the folder *Garmin* in your main folder.
- Nothing on the device is changed or deleted.

**Send to Device** – take routes and tracks along
- First select one or more files in the file list, then open this tab (or right-click the files → *Send to Garmin Device …*).
- Choose how the device should treat them: as a **Track** (it shows a line to follow) or as a **Route** (the device works out its own turn instructions).
- Click **Send**. The files are copied to the device. Unplug it (or let the program eject it) and the new courses appear on the device.

If the device is not found: check the cable, wake up the device, on a bike computer choose the USB mode *Garmin* / *Mass Storage* if it asks, and quit programs like Garmin Express that may be using it.

## Komoot

**File → Connect to Komoot …** has two tabs.
- **Import:** shows your Komoot tours. Those not yet on your computer are marked; choose a year or take everything, then download them into the folder *Komoot*.
- **Export:** sends a selected track to Komoot as a new tour.

You sign in with your Komoot e-mail and password; they are kept only in the macOS keychain. The program never changes or deletes anything that already exists on Komoot. Komoot does not officially offer this connection, so it may stop working one day.

## Statistics and duplicates

The **Statistics** menu has two helpers:
- **Track Statistics …** shows how many tracks you have, the distance, the ascent and the time, per folder, per year or per month, with a bar chart.
- **Find Duplicate Tracks …** finds files that contain the same recording twice. Click a name to see it in the main window, then move the extra copies to the Trash. The suggested one to keep is marked with a star.

## Several windows

*View → Show Tab Bar* gives you tabs, each with its own folder, selection and map. That is handy to compare two places.

## Useful keys

- <kbd>⌘</kbd><kbd>,</kbd> – Settings
- <kbd>⌘</kbd><kbd>0</kbd> – show all tracks; <kbd>⌘</kbd><kbd>9</kbd> – show the selected track
- <kbd>⌘</kbd><kbd>+</kbd> / <kbd>⌘</kbd><kbd>−</kbd> – zoom
- <kbd>⌘</kbd><kbd>A</kbd> – select all files of the folder
- <kbd>⌘</kbd><kbd>R</kbd> – reload the folders
- <kbd>⌘</kbd><kbd>Z</kbd> / <kbd>⇧</kbd><kbd>⌘</kbd><kbd>Z</kbd> – undo / redo while editing
- <kbd>⌘</kbd><kbd>P</kbd> – print the map
- <kbd>⇧</kbd><kbd>⌘</kbd><kbd>I</kbd> – aerial images on / off
- <kbd>⌥</kbd><kbd>⌘</kbd><kbd>S</kbd> – statistics
- <kbd>Esc</kbd> – close the photo strip, a large photo, or stop measuring
- Arrow keys – step through the file list

## If something does not work

- **The folder list is empty or old:** press <kbd>⌘</kbd><kbd>R</kbd>, or choose the folder again with **Folder …**.
- **The map stays gray:** check your internet connection; maps you have looked at before are kept and work offline.
- **A file does not show up:** the program reads GPX and Garmin FIT files and a few other track formats. Other files in a folder are ignored.
- **I deleted something by mistake:** open the Trash in the Dock, select the file and choose *Put Back*.
- **The program is "from an unknown developer" on the first start:** right-click the program → *Open* → *Open*. You only need to do this once.

## Good to know

GPX Organizer is free software and has no connection to Garmin or Komoot. Your files stay on your computer; the program only contacts the internet to load map pictures, elevation data or route calculations, and only when you use Komoot does it talk to Komoot.
