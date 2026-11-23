# GPX Organizer

*Dies ist die Technische Referenz. Eine allgemeinverständliche Anleitung für alle steckt in der App: Hilfe → Benutzerhandbuch (Quelle: `Resources/UserGuide.md`).*

GPX Organizer ist eine native macOS-App zum **Ansehen und Ordnen einer großen Zahl von GPX-Dateien, die auf deiner Platte liegen**.
Deine Ordnerstruktur ist die Datenbank: Die App bildet die Ordner links ab, zeigt die Tracks des gewählten Ordners
auf der Karte und lässt dich die Dateien sortieren, verschieben, zusammenfügen, umbenennen und aufräumen.

**Standardmäßig werden Online-Karten gezeigt.** Zusätzlich lassen sich lokale Open-Source-Karten im Garmin-Format (`.gmap` / `.img`) wählen.

## Funktionen

**Ordner und Dateien**
- Ordnerbaum mit der Anzahl der Trackdateien je Ordner (in beliebiger Tiefe) und darunter eine sortierbare Dateiliste
  (nach Name, Typ, Datum aufsteigend oder absteigend; Wegpunktdateien werden nach Farbe gruppiert).
- Auf Wunsch werden die Tracks aller Unterordner auf der Karte gezeigt („Tracks der Unterordner anzeigen“).
- Ziehen und Ablegen zwischen Liste und Ordnern: Ziehen verschiebt, mit gehaltener Taste <kbd>⌥</kbd> wird kopiert (von außen hereingezogene Dateien werden immer kopiert).
- Umbenennen, Ordner anlegen, Dateien in den Papierkorb legen, mehrere Dateien wählen (<kbd>⌘</kbd>/<kbd>⇧</kbd>-Klick) und zu einem Track zusammenfügen.
- Pfeiltasten und Bild auf/ab gehen durch die Dateiliste.
- Läuft die App im Hintergrund, wird der gezeigte Ordner beobachtet: Dateien, die andere Programme hinzufügen, entfernen oder umbenennen, erscheinen sofort in der Liste.
- Suche über alle Ordner: Dateinamen, Ordnernamen, Tracktyp, Tracknamen sowie Wegpunktnamen und -symbole.
- Liest GPX, Garmin-**FIT**-Aktivitätsdateien (mit Herzfrequenz, Trittfrequenz und Leistung, direkt von einer Garmin-Uhr oder per *Originaldatei exportieren* aus Garmin Connect) sowie TRC-, IKT-, PTM/AXE-, OVL- und TRAIL-Trackdateien. Tracks werden nach ihrer Art eingefärbt, sofern keine Farbe für sie gesetzt wurde: blau (Radfahrt), grün (Wanderung), lila (Joggen), rot (Auto oder Motorrad) oder grau (alles andere, geplante Tracks); die Farben und die Geschwindigkeitsgrenzen stellst du in Einstellungen → Allgemein → Track-Symbole und -Farben nach Geschwindigkeit ein. Farben werden überall gleich gewählt (Kontextmenüs *Symbolfarbe* / *Trackfarbe* und Einstellungen): die benannte Palette, hinter jedem Namen ein Strich in seiner Farbe, und zuletzt *Andere Farbe …* mit dem Farbfenster des Systems. Eine FIT-Datei wird nie verändert; wenn du sie bearbeitest, wird das Ergebnis als neue GPX-Datei gesichert. Export als GPX, KML oder CSV.

**Karte**
- Viele Tracks übereinander gezeichnet, der gewählte hervorgehoben; Farbe und Linienbreite lassen sich je Datei einstellen.
- Wenn du den Zeiger über einen Track hältst, siehst du alle Tracks unter dem Zeiger. Zoomen mit den Knöpfen + / − unten rechts, mit ⌘+ / ⌘− oder mit dem Mausrad.
- *Ablage → Karte drucken …* (⌘P) druckt die Karte wie gezeigt: gleiche Mitte und gleicher Maßstab über die Fensterbreite, Querformat, wenn die Karte breiter als hoch ist, sonst Hochformat, die Karte so erweitert, dass das ganze Blatt gefüllt ist, mit einem Maßstabsbalken unten rechts.
- Vier Online-Karten gleich ab Werk: OpenTopoMap, TopPlusOpen, TopPlusOpen gray und OpenStreetMap.
  Die Kacheln werden auf der Platte in deinem Kartenordner zwischengespeichert (Größenlimit in den Einstellungen einstellbar, 100 MB bis 10 GB, Standard 2 GB; die ältesten Kacheln gehen zuerst),
  sodass sie beim nächsten Mal sofort laden und auch offline funktionieren. Ein Gebiet lässt sich für die Offline-Nutzung laden (nur kleine Gebiete).
- Lokale Karten im Garmin-Format (`.gmap`-Ordner, `.img`-Dateien) lassen sich über das Kartenmenü hinzufügen.
  Gesperrte, herstellergeschützte Karten im NT/GMP-Format von Garmin werden nicht unterstützt.

**Tracks und Wegpunkte**
- Diagramm unter der Karte mit Bereichswahl (Ziehen), Punktwahl (Klick) und einer Anzeige aller gezeigten Kurven, während du darüberfährst; der Knopf *Inhalt* unten rechts wählt die Kurven:
  Höhe, Geschwindigkeit (braucht Zeitstempel), Herzfrequenz, Leistung und Trittfrequenz (wenn die Datei sie enthält, z. B. Garmin-`TrackPointExtension` `hr` / `cad` oder ein `power`-Eintrag). Mehrere Kurven können gleichzeitig gezeigt werden; das Diagramm folgt der Karte (es zeigt den Teil des Tracks, den die Karte zeigt, in den mittleren 60 % seiner Breite; der schattierte Teil lässt sich ziehen, um die Karte am Track entlang zu bewegen) und lässt sich für sich mit dem Mausrad oder durch Zusammen- und Auseinanderziehen zoomen, mit zwei Fingern seitwärts verschieben oder mit den Lupenknöpfen darunter zoomen (*Zoom zurücksetzen* kehrt zum Ausschnitt der Karte zurück; die Höhenskalen passen sich dann dem vergrößerten Teil an);
  die Höhenskala steht rechts, die Skala der ersten anderen Kurve links. Außerdem im Track-Editor: punktweiser Track-Editor (Punkte verschieben, einfügen, löschen, Widerrufen/Wiederholen). Seine Liste *Wegpunkte* zeigt für jeden Punkt Nummer, Position, Entfernung vom Start und Höhe, und in einer zweiten Zeile die Strecke zum nächsten Punkt: Entfernung, Zeit, Geschwindigkeit und Richtung (beim letzten Punkt keine).
- Wegpunktdateien werden als farbige runde Marker mit einem Symbol nach dem Garmin-Symbolnamen gezeichnet. Ein Doppelklick bearbeitet einen: Ziehe den Marker, um ihn zu verschieben, ändere Name, Beschreibung und Symbol, füge Wegpunkte hinzu oder lösche sie (das Original wird vor dem Sichern gesichert).
- Tracks werden aus dem Dateiinhalt (Zeitstempel und Geschwindigkeit) als geplant, Wanderung, Radfahrt oder Auto-/Motorradfahrt eingestuft;
  aus einer Symbolmatrix kannst du für jede Datei ein beliebiges anderes Symbol wählen (Rechtsklick → *Symbol wählen …*). Die Geschwindigkeitsgrenzen sind in den Einstellungen (⌘,) einstellbar.
  Ein gewähltes Symbol wird unter einem einfachen Namen gespeichert (`mountains`, `hike`, `spring` …), die Trackfarbe und die Symbolfarbe als `RRGGBB` und die Linienbreite in Punkten,
  alles in der GPX-Datei als kleiner Metadaten-Eintrag:
  `<metadata><extensions><gpxorg:icon>mountains</gpxorg:icon><gpxorg:iconcolor>E6191A</gpxorg:iconcolor><gpxorg:color>8C33CC</gpxorg:color></extensions></metadata>`.
  Der Eintrag wird als Text eingefügt, sodass alles andere in der Datei unberührt bleibt und das Änderungsdatum der Datei erhalten bleibt.
  Die Dateien und die Ordnerstruktur sind die einzige Datenbank; die App hält keine Daten je Datei in ihren Einstellungen.
  Andere Formate als GPX können diese Auswahl nicht speichern.
- Online-Karten sind eine Liste, die du in Einstellungen → Karten verwaltest: umsortieren, bearbeiten, entfernen, auf die ursprünglichen vier zurücksetzen oder hinzufügen. *Hinzufügen …* bietet kostenlose Karten je Kontinent an
  und durchsucht eine von dir eingetippte Webadresse (eine Kachel-Adresse, einen Server, eine Webseite mit Karte, WMTS- oder ArcGIS-Dienste; Tippfehler werden toleriert) nach Karten
  und fragt, welche übernommen werden sollen. Karten, die einen Zugangsschlüssel brauchen, werden nicht angeboten.
- Luftbilder (wie BirdsEye): Der Bild-Knopf in der Symbolleiste (⇧⌘I) zeigt kostenlose Luft- oder Satellitenbilder über der Karte, mit einem Regler für die Deckkraft
  (bei weniger als 100 % scheint die Karte durch, sodass Straßen und Namen sichtbar bleiben). Die Server sind eine Liste in Einstellungen → Luftbild, die wie die Online-Karten verwaltet wird
  (nach Kontinent oder Webadresse hinzufügen, bearbeiten, entfernen, umsortieren, zurücksetzen). Standardmäßig enthalten: Esri World Imagery und Sentinel-2 cloudless; der Katalog ergänzt
  nationale Luftbilder (Schweiz, Frankreich, Österreich, Niederlande, Bayern, Spanien, USA, Japan). Die Bilder erscheinen auch in der gedruckten Karte.
- *Höhendaten ersetzen …* (Rechtsklick auf einen Track in der Liste oder auf der Karte; auch mehrere Dateien gleichzeitig): Die Höhen der Trackpunkte werden durch Werte eines Geländemodells (open-meteo.com)
  ersetzt, und Aufstieg und Abstieg werden neu berechnet; das Original jeder Datei kommt zuvor in den Papierkorb.
- Marker (= GPX-Wegpunkte): Rechtsklick auf die Karte → *Neuer Marker*, oder ⌘-Klick. Jeder Marker hat eine Überschrift, eine Beschreibung (als Hinweis angezeigt),
  ein Symbol, eine Farbe und eine Größe; seine Position wird durch Ziehen verschoben. Das Blatt fragt jedes Mal, ob der Marker als neue GPX-Datei gesichert
  oder einer GPX-Datei hinzugefügt wird (Standard: der in der Liste gewählten Datei hinzugefügt, sonst eine neue Datei). Doppelklick auf einen Marker oder Rechtsklick →
  *Marker bearbeiten …*, um ihn später zu ändern. Symbol, Farbe und Größe werden in der Datei gespeichert (`gpxorg:micon`, `gpxorg:mcolor`, `gpxorg:msize` innerhalb des `<wpt>`).
- Routenplanung mit Höhenprofil (Profile für Wandern, Joggen, Mountainbike, Tourenrad, Rennrad, Auto und Motorrad), gesichert als GPX. Garmin-Karten routen offline: Die Routing-Regeln werden bei jedem Start aus den eigenen Daten jeder Karte abgeleitet, sodass jede Karte funktioniert (routingfähige Karten sind in der Kartenliste markiert). Online-Karten routen auf OpenStreetMap-Daten über brouter.de (die Routenpunkte werden an diesen Server gesendet).
  Beginne eine Route mit Rechtsklick auf die Karte (*Route hier beginnen* / *Route hier beenden*), füge Punkte durch Klick auf die Karte oder auf einen Marker hinzu (die Überschrift eines Markers wird zum
  Namen des Punkts). Jeder Routenpunkt lässt sich in der Liste umbenennen. Routen werden entweder als kompletter Track (alle Punkte), als geplante GPX-Route mit nur
  deinen Routenpunkten oder als geplante Route mit zusätzlichen Zwischenpunkten gesichert, sodass ein Gerät den Weg selbst berechnen kann. *Etappen …* teilt eine lange Route in Tage
  nach Entfernung oder Aufstieg: Es kann Übernachtungspunkte in die Route einfügen oder je Tag eine GPX-Datei sichern.
  Die geschätzte Zeit nutzt eine Durchschnittsgeschwindigkeit je Profil (Wandern 4,5, Joggen 9, Mountainbike 15, Tourenrad 20, Rennrad 25 km/h, Auto und Motorrad 60 km/h) plus einen Zuschlag je 100 m Aufstieg (Wandern 10 Min., Joggen 6, Mountainbike 4, Tourenrad 3, Rennrad 2,5) und, nur bei Tourenrad und Rennrad, einen Abschlag je 100 m Abstieg (1 bzw. 1,5 Min.; höchstens ein Viertel der Zeit auf ebener Strecke).

**Track-Werkzeuge und Darstellung**
- Im Bearbeitungsmodus bietet das Scheren-Menü *Auf gewählten Bereich zuschneiden* (behält den Teil zwischen dem ersten und letzten gewählten Punkt; wähle einen Bereich durch Ziehen im Höhen-
  profil), *Am gewählten Punkt teilen …* (schreibt zwei neue Dateien neben das Original, das Original bleibt unverändert) und *Glätten* (leichter, mittlerer oder starker gleitender Mittelwert von
  Position und Höhe, für den gewählten Bereich oder den ganzen Track). Alles lässt sich mit ⌘Z widerrufen; vor dem Sichern wird nichts gespeichert.
- *Messen* (Lineal-Knopf): Klicke Punkte auf der Karte an, die Länge bis zu jedem Punkt wird gezeigt. Esc beendet es, Rechtsklick entfernt den letzten Punkt.
- *Farbe* (Paletten-Knopf): färbt den gewählten Track nach **Geschwindigkeit** (braucht Zeitstempel), **Steigung** (braucht Höhen), **Herzfrequenz**, **Leistung** oder **Trittfrequenz**, auf der Karte und im Diagramm darunter;
  blau = niedrig oder bergab, grün = mittel, rot = hoch oder steil bergauf. Oben links auf der Karte erscheint eine Legende. Standard ist die normale Trackfarbe.
- Kleine **Richtungspfeile** (weiße Quadrate mit einem Pfeil in der Farbe des Tracks) laufen an den gewählten Tracks entlang; im selben Menü lassen sie sich abschalten.
- Die Symbolleiste ist wie die des Finders gruppiert: Kartenansicht, Track, Bearbeiten, Route. *Darstellung → Symbolleisten-Beschriftungen anzeigen* fügt unter jedem Symbol einen kurzen Text hinzu.
- Mehrere Reiter: *Darstellung → Tab-Leiste einblenden*, dann der +-Knopf. Jeder Reiter hat seinen eigenen Ordner, seine Auswahl und seine Karte.

**Fotos auf der Karte**
- Wähle einen Fotoordner (beim ersten Start fragt ein Dialog danach, danach in Einstellungen → Speicher → Fotos). Der Ordner und alle seine Unterordner werden nur **gelesen** – es wird kein Foto
  hinzugefügt, entfernt oder verändert. Fotos ohne GPS-Daten werden ignoriert; RAW-Formate werden nicht gelesen.
- Position, Datum und Kamera werden aus den Metadaten der Fotos gelesen und in einem Cache (Index und Vorschaubilder) im Ordner „Photos“ innerhalb des Cache-Ordners der Online-Karten gehalten; der
  Cache wird bei jedem Start aktualisiert, sodass Änderungen im Fotoordner bemerkt werden. Das erste Einlesen eines großen Ordners dauert einige Minuten (Fortschritt oben rechts auf der Karte).
- Der Foto-Knopf in der Symbolleiste schaltet die Stempel ein und aus (⌥-Klick oder Rechtsklick: Optionen, z. B. *Nur entlang des gewählten Tracks*). Überall, wo Fotos sind, wird ein stempelgroßes
  Bild des neuesten Fotos gezeigt, mit seinem Datum darunter und der Anzahl der Fotos in einem roten Kreis. Die Bereiche werden feiner, je weiter du hineinzoomst.
- Klicke auf einen Stempel: Eine Leiste mit den Fotos ersetzt das Höhendiagramm (ziehe sie mit der Maus oder benutze die Pfeile; das ✕ oder Esc schließt sie). Klicke auf ein Foto für eine große Ansicht mit
  vollem Pfad, Datum, Uhrzeit und Kamera; Esc oder ✕ schließt sie, die Pfeiltasten gehen zum vorigen und nächsten Foto.

**Komoot (inoffiziell)**
- *Ablage → Mit Komoot verbinden …* (im Dialog auf *Importieren* wechseln) listet alle deine Touren (geplante und aufgezeichnete) und markiert die, die in keinem Ordner unterhalb des Hauptordners gefunden werden (verglichen nach Startzeit und
  Tournummer). Die markierten Touren können in den Ordner „Komoot“ im Hauptordner geladen werden; wähle ein Jahr, um die Liste einzugrenzen. Der Reiter *Exportieren* desselben Dialogs lädt den gewählten
  Track als neue Tour hoch. Nichts, was bei Komoot schon existiert, wird je verändert oder gelöscht.
- Komoot hat für Privatnutzer keine öffentliche Schnittstelle. Die App benutzt dieselbe undokumentierte Schnittstelle wie andere Community-Werkzeuge; sie kann jederzeit aufhören zu funktionieren und ist möglicherweise nicht
  von den Nutzungsbedingungen von Komoot gedeckt. E-Mail-Adresse und Passwort werden nur im macOS-Schlüsselbund gespeichert.

**Dunkler Modus**
- *Einstellungen → Allgemein → Darstellung*: wie das System, hell oder dunkel. In der dunklen Darstellung werden auch die Karten dunkel gezeigt (abschaltbar mit *Karten ebenfalls dunkel darstellen*): Die Helligkeit der Karte wird umgekehrt, und jede Farbe behält ihren Farbton
  (Wasser bleibt also blau und Wald grün). Luftbilder werden nicht verändert.

**Garmin-Geräte (USB)** – Uhren und Edge-Fahrradcomputer, in beide Richtungen
- *Ablage → Mit Garmin verbinden …* (oder das Kabelsymbol links neben der Kartenwahl in der Symbolleiste) (Reiter *Vom Gerät importieren*) liest die Aktivitätsdateien (FIT) direkt von einem per USB verbundenen Gerät, ohne Garmin Connect. Fahrradcomputer (Edge) erscheinen als Laufwerk namens GARMIN und werden aus
  `Garmin/Activities` gelesen. Neuere Uhren erscheinen nicht als Laufwerk (sie benutzen MTP); die App spricht MTP selbst. Die Liste zeigt alle Aktivitäten auf dem Gerät mit Datum, Uhrzeit und Größe und markiert die, deren Dateiname in deinen Ordnern noch nicht
  gefunden wird; die markierten werden in den Ordner „Garmin“ im Hauptordner geladen (Jahr wählbar). Das Gerät wird nur gelesen. Benutze ein USB-Datenkabel; hält ein anderes Programm das Gerät
  (z. B. Android File Transfer oder Garmin Express), sagt der Dialog das und bietet an, es zu beenden. Die FIT-Dateien enthalten Herzfrequenz, Trittfrequenz und Leistung.
- Der Reiter *An Gerät senden* (auch aus dem Kontextmenü der Dateiliste) legt die markierten Tracks und Routen auf dem Gerät ab, um sie später zu fahren. Jedes unterstützte Format wird in GPX umgewandelt – als Track (das Gerät
  zeigt ihn als Strecke zum Abfahren) oder als Route (für die eigenen Abbiegehinweise des Geräts) – und nach `Garmin/NewFiles` kopiert; das Gerät übernimmt die neuen Strecken, wenn es abgezogen wird. Bei einem Laufwerk kann der
  Dialog das Gerät danach auswerfen. Auf dem Gerät wird nichts verändert oder gelöscht, und deine eigenen Dateien bleiben, wie sie sind. Wähle bei einem Edge den Modus „Garmin“ (Massenspeicher), falls das Gerät danach fragt.

**Statistik**
- *Statistik → Track-Statistik …* (⌥⌘S): Anzahl der Tracks, Entfernung, Aufstieg und Bewegungszeit je Ordner (mit oder ohne Unterordner), je Jahr oder je Monat über alle Ordner,
  auf Wunsch nur aufgezeichnete Tracks (mit Zeitstempeln) und für ein Jahr, mit einem Balkendiagramm.
- *Statistik → Doppelte Tracks suchen …*: Gruppen von Tracks, deren erste 100 Trackpunkte gleich sind (GPX- und FIT-Dateien werden nur miteinander verglichen, wenn der Schalter oben es erlaubt). Der vorgeschlagene Track zum Behalten ist markiert; klicke auf einen Tracknamen, um ihn
  im Hauptfenster zu zeigen, oder lege Kopien in den Papierkorb (immer nach einer Bestätigung; sie lassen sich aus dem Papierkorb zurückholen).

## Voraussetzungen

- macOS 14 oder neuer, Apple Silicon
- **Bei der fertigen App (siehe Download unten): sonst nichts.** Die App benutzt nur Bibliotheken, die Teil von macOS sind, und
  startet keine Hilfsprogramme, sodass zum Ausführen keine Entwicklerwerkzeuge nötig sind.
- **Nur zum Bauen aus dem Quelltext:** die Apple-*Command Line Tools* (der Swift-Compiler; das vollständige Xcode ist nicht nötig). Installiere sie einmalig:
  1. Öffne die App *Terminal* (Spotlight: „Terminal“ eintippen).
  2. Führe `xcode-select --install` aus.
  3. Klicke im erscheinenden Fenster auf *Installieren*, akzeptiere die Lizenz und warte, bis es fertig ist (einige Minuten, 1–2 GB).
  4. Prüfe mit `swift --version`: Es sollte eine Versionsnummer ausgeben (Swift 5.9 oder neuer).

  Bittet macOS dich irgendwann, die „Entwicklerwerkzeuge für die Befehlszeile“ zu installieren (zum Beispiel wenn auf einem Mac, der sie noch nicht hat, ein Terminal-Befehl wie `git`, `swift`
  oder `xattr` benutzt wird), sind die obigen Schritte die richtige Antwort: Klicke auf *Installieren* und warte.

## Download

Fertige App: Lade `GPX-Organizer-<Version>.zip` vom [neuesten Release](https://github.com/Martin-Doppelbauer/gpx-organizer/releases/latest),
entpacke es (Doppelklick) und verschiebe *GPX Organizer* in deinen Ordner *Programme*.

Die App ist mit einer Apple-Developer-ID signiert und von Apple notariell beglaubigt, sie öffnet sich also mit einem normalen Doppelklick.
Fragt macOS, ob du eine aus dem Internet geladene App öffnen willst, klicke auf **Öffnen**.

## Bauen und starten

```sh
git clone https://github.com/Martin-Doppelbauer/gpx-organizer.git
cd gpx-organizer
./build_app.sh
open "dist/GPX Organizer.app"
```

Die App ist nur ad hoc signiert. Weigert sich macOS, sie zu öffnen, klicke mit der rechten Maustaste auf die App und wähle *Öffnen*.
Für ein signiertes und notariell beglaubigtes Release siehe [RELEASING.md](RELEASING.md).

## Erster Start

Beim ersten Start fragt die App, wo deine Karten gespeichert werden sollen: Sie kann einen Standardordner anlegen
(`~/Library/Application Support/GPX Organizer/Maps`) oder einen Ordner benutzen, den du wählst. Der Ordner bekommt je
eingebauter Online-Karte einen Unterordner für ihren Kachelcache. Danach wird links dein Ordner „Dokumente“ gezeigt; wechsle mit *Ordner …* zu
dem Ordner, der deine GPX-Dateien enthält.

## Datenschutz und Kartendienste

Die App liest nur die Ordner, die du wählst (und verändert Dateien nur, wenn du sie bearbeitest, sicherst oder verschiebst; bevor eine Datei überschrieben wird, kommt ihr Original in den macOS-Papierkorb (die App sagt es dir)).
Online-Karten laden Kacheln von den Servern der Kartenanbieter, während du stöberst. Bitte beachte deren Nutzungsrichtlinien; die App bietet keine Massendownloads großer Regionen an.
Daten verlassen deinen Mac nur für die Funktionen, die du benutzt: Kartenkacheln, Online-Routing (die Routenpunkte gehen an brouter.de), Höhenersatz (die Trackpunkte gehen an open-meteo.com)
und Komoot-Import/-Export (an Komoot, mit deinem Login aus dem Schlüsselbund). Fotos, ihre Metadaten und der Fotocache bleiben auf deinem Mac.

Kartendaten und Dienste:
- © OpenStreetMap-Mitwirkende (ODbL)
- OpenTopoMap (CC-BY-SA), Kartendaten © OpenStreetMap-Mitwirkende, SRTM
- TopPlusOpen © Bundesamt für Kartographie und Geodäsie (BKG)

## Lizenz

GPX Organizer ist freie Software, lizenziert unter der **GNU General Public License v3.0 oder später**. Siehe [LICENSE](LICENSE).
Copyright © 2026 Martin Doppelbauer.

GPX Organizer ist ein unabhängiges Projekt und weder mit Garmin Ltd. verbunden noch von Garmin Ltd. unterstützt.
Garmin und BaseCamp sind Marken von Garmin Ltd.
