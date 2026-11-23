# GPX Organizer

*Ceci est la référence technique. Un guide en langage simple pour tout le monde se trouve dans l’app : Aide → Guide de l’utilisateur (source : `Resources/UserGuide.md`).*

GPX Organizer est une app macOS native pour **afficher et organiser un grand nombre de fichiers GPX stockés sur votre disque**.
Votre arborescence de dossiers est la base de données : l’app reproduit les dossiers à gauche, affiche sur la carte les traces du dossier sélectionné
et vous permet de trier, déplacer, fusionner, renommer et ranger les fichiers.

**Les cartes en ligne sont affichées par défaut.** Des cartes locales open source au format Garmin (`.gmap` / `.img`) peuvent être sélectionnées en plus.

## Fonctions

**Dossiers et fichiers**
- Arborescence des dossiers avec le nombre de fichiers de trace par dossier (à toute profondeur) et, dessous, une liste de fichiers triable
  (par nom, type, date croissante ou décroissante ; les fichiers de points de passage sont regroupés par couleur).
- Possibilité d’afficher sur la carte les traces de tous les sous-dossiers (« Afficher les traces des sous-dossiers »).
- Glisser-déposer entre la liste et les dossiers : glisser déplace, maintenir <kbd>⌥</kbd> copie (les fichiers glissés depuis l’extérieur sont toujours copiés).
- Renommer, créer des dossiers, placer des fichiers dans la corbeille, sélectionner plusieurs fichiers (clic <kbd>⌘</kbd>/<kbd>⇧</kbd>) et les fusionner en une seule trace.
- Les touches fléchées et Page précédente/suivante parcourent la liste des fichiers.
- Quand l’app est en arrière-plan, le dossier affiché est surveillé : les fichiers que d’autres programmes ajoutent, suppriment ou renomment apparaissent dans la liste dès que cela se produit.
- Recherche dans tous les dossiers : noms de fichiers, noms de dossiers, type de trace, noms de traces et noms/symboles de points de passage.
- Lit les fichiers GPX, les fichiers d’activité Garmin **FIT** (avec fréquence cardiaque, cadence et puissance, directement depuis une montre Garmin ou via *Exporter l’original* de Garmin Connect), ainsi que les fichiers de trace TRC, IKT, PTM/AXE, OVL et TRAIL. Les traces sont dessinées selon leur type, sauf si une couleur a été définie pour elles : bleu (sortie à vélo), vert (randonnée), violet (jogging), rouge (voiture ou moto) ou gris (tout le reste, traces planifiées) ; les couleurs et les limites de vitesse se règlent dans Réglages → Général → Icônes et couleurs des traces selon la vitesse. Les couleurs se choisissent partout de la même façon (menus contextuels *Couleur de l’icône* / *Couleur de la trace* et Réglages) : la palette nommée, chaque nom suivi d’un trait de sa couleur, et *Autre couleur …* avec le panneau des couleurs du système en dernier. Un fichier FIT n’est jamais modifié ; si vous le modifiez, le résultat est enregistré dans un nouveau fichier GPX. Export en GPX, KML ou CSV.

**Carte**
- De nombreuses traces dessinées les unes sur les autres, la trace sélectionnée mise en évidence ; la couleur et la largeur de ligne se règlent par fichier.
- Placez le pointeur sur une trace pour voir toutes les traces situées sous le pointeur. Zoom avec les boutons + / − en bas à droite, avec ⌘+ / ⌘− ou avec la molette de la souris.
- *Fichier → Imprimer la carte …* (⌘P) imprime la carte telle qu’elle est affichée : même centre et même échelle sur la largeur de la fenêtre, papier paysage quand la carte est plus large que haute et portrait sinon, la carte étendue pour remplir toute la feuille, avec une barre d’échelle en bas à droite.
- Quatre cartes en ligne d’origine : OpenTopoMap, TopPlusOpen, TopPlusOpen gray et OpenStreetMap.
  Les tuiles sont mises en cache sur le disque dans votre dossier des cartes (limite de taille réglable dans les Réglages, de 100 Mo à 10 Go, 2 Go par défaut ; les plus anciennes tuiles partent en premier),
  ce qui les fait charger aussitôt la fois suivante et fonctionner aussi hors ligne. Une zone peut être téléchargée pour l’usage hors ligne (petites zones seulement).
- Des cartes locales au format Garmin (dossiers `.gmap`, fichiers `.img`) peuvent être ajoutées depuis le menu des cartes.
  Les cartes verrouillées et protégées par leur éditeur au format NT/GMP de Garmin ne sont pas prises en charge.

**Traces et points de passage**
- Graphique sous la carte avec sélection de plage (glisser), sélection de point (clic) et affichage des valeurs de toutes les courbes affichées lorsque vous le survolez ; le bouton *Contenu* en bas à droite choisit les courbes :
  altitude, vitesse (nécessite l’horodatage), fréquence cardiaque, puissance et cadence (si le fichier les contient, par ex. `hr` / `cad` de la `TrackPointExtension` Garmin ou une entrée `power`). Plusieurs courbes peuvent être affichées en même temps ; le graphique suit la carte (il montre le tronçon de la trace que montre la carte, dans les 60 % centraux de sa largeur ; la partie grisée peut être déplacée pour faire avancer la carte le long de la trace) et peut être zoomé séparément avec la molette de la souris ou par pincement, déplacé latéralement avec deux doigts, ou zoomé avec les boutons loupe situés dessous (*Réinitialiser le zoom* revient au tronçon de la carte ; les échelles de hauteur s’adaptent alors à la partie agrandie) ;
  l’échelle d’altitude est à droite, l’échelle de la première autre courbe à gauche. Aussi dans l’éditeur de trace : éditeur de trace point par point (déplacer, insérer, supprimer des points, annuler/rétablir). Sa liste *Points de passage* indique pour chaque point le numéro, la position, la distance depuis le départ et l’altitude, et sur une seconde ligne le tronçon jusqu’au point suivant : distance, durée, vitesse et direction (aucune pour le dernier point).
- Les fichiers de points de passage sont dessinés comme des repères ronds colorés avec une icône tirée du nom de symbole Garmin. Double-cliquez sur l’un d’eux pour le modifier : faites glisser le repère pour le déplacer, changez le nom, la description et le symbole, ajoutez ou supprimez des points de passage (l’original est sauvegardé avant l’enregistrement).
- Les traces sont classées d’après le contenu du fichier (horodatage et vitesse) en planifiées, randonnée, sortie à vélo ou trajet voiture/moto ;
  vous pouvez choisir n’importe quelle autre icône par fichier dans une matrice d’icônes (clic droit → *Choisir une icône …*). Les limites de vitesse se règlent dans les Réglages (⌘,).
  Une icône choisie est enregistrée sous un nom simple (`mountains`, `hike`, `spring` …), la couleur de la trace et la couleur de l’icône sous la forme `RRGGBB` et la largeur de ligne en points,
  le tout dans le fichier GPX sous forme d’une petite entrée de métadonnées :
  `<metadata><extensions><gpxorg:icon>mountains</gpxorg:icon><gpxorg:iconcolor>E6191A</gpxorg:iconcolor><gpxorg:color>8C33CC</gpxorg:color></extensions></metadata>`.
  L’entrée est insérée comme texte, de sorte que tout le reste du fichier demeure intact et que la date de modification du fichier est conservée.
  Les fichiers et l’arborescence des dossiers sont la seule base de données ; l’app ne conserve aucune donnée par fichier dans ses préférences.
  Les formats autres que GPX ne peuvent pas enregistrer ces choix.
- Les cartes en ligne forment une liste que vous gérez dans Réglages → Cartes : réordonner, modifier, retirer, revenir aux quatre d’origine, ou ajouter. *Ajouter …* propose des cartes gratuites par continent
  et explore une adresse web que vous saisissez (une adresse de tuiles, un serveur, une page web avec carte, des services WMTS ou ArcGIS ; les fautes de frappe sont tolérées) pour y trouver des cartes
  et demande lesquelles prendre. Les cartes qui nécessitent une clé d’accès ne sont pas proposées.
- Photos aériennes (comme BirdsEye) : le bouton image de la barre d’outils (⇧⌘I) affiche des photos aériennes ou satellite gratuites au-dessus de la carte, avec un curseur pour l’opacité
  (à moins de 100 %, la carte transparaît, de sorte que routes et noms restent visibles). Les serveurs forment une liste dans Réglages → Photos aériennes, gérée comme les cartes en ligne
  (ajout par continent ou adresse web, modification, suppression, réordonnancement, réinitialisation). Incluses par défaut : Esri World Imagery et Sentinel-2 cloudless ; le catalogue ajoute
  des photos aériennes nationales (Suisse, France, Autriche, Pays-Bas, Bavière, Espagne, États-Unis, Japon). Les images apparaissent aussi dans la carte imprimée.
- *Remplacer les données d’altitude …* (clic droit sur une trace dans la liste ou sur la carte ; plusieurs fichiers à la fois) : les altitudes des points de trace sont remplacées par des valeurs d’un modèle de terrain
  (open-meteo.com), puis le dénivelé positif et négatif est recalculé ; l’original de chaque fichier est d’abord placé dans la corbeille.
- Repères (= points de passage GPX) : clic droit sur la carte → *Nouveau repère*, ou clic avec ⌘. Chaque repère a un titre, une description (affichée comme info-bulle),
  une icône, une couleur et une taille ; sa position se déplace en le faisant glisser. La feuille demande à chaque fois si le repère est enregistré dans un nouveau fichier GPX
  ou ajouté à un fichier GPX (par défaut : ajouté au fichier sélectionné dans la liste, sinon un nouveau fichier). Double-cliquez sur un repère ou clic droit →
  *Modifier le repère …* pour le modifier plus tard. L’icône, la couleur et la taille sont enregistrées dans le fichier (`gpxorg:micon`, `gpxorg:mcolor`, `gpxorg:msize` dans le `<wpt>`).
- Planification d’itinéraire avec profil altimétrique (profils randonnée, jogging, VTT, vélo de voyage, vélo de route, voiture et moto), enregistrée en GPX. Les cartes Garmin calculent les itinéraires hors ligne : les règles d’itinéraire sont déduites à chaque démarrage des données propres de chaque carte, de sorte que toute carte fonctionne (les cartes utilisables pour le calcul d’itinéraire sont marquées dans la liste des cartes). Les cartes en ligne calculent sur les données OpenStreetMap via brouter.de (les points d’itinéraire sont envoyés à ce serveur).
  Commencez un itinéraire par un clic droit sur la carte (*Commencer l’itinéraire ici* / *Terminer l’itinéraire ici*), ajoutez des points en cliquant sur la carte ou sur un repère (le titre d’un repère devient le
  nom du point). Chaque point d’itinéraire peut être renommé dans la liste. Les itinéraires sont enregistrés soit comme une trace complète (tous les points), soit comme un itinéraire GPX planifié avec seulement
  vos points d’itinéraire, soit comme un itinéraire planifié avec des points intermédiaires supplémentaires, pour qu’un appareil puisse calculer lui-même le chemin. *Étapes …* divise un long itinéraire en journées
  selon la distance ou le dénivelé : il peut insérer des points de nuitée dans l’itinéraire ou enregistrer un fichier GPX par jour.
  La durée estimée utilise une vitesse moyenne par profil (randonnée 4,5, jogging 9, VTT 15, vélo de voyage 20, vélo de route 25 km/h, voiture et moto 60 km/h), plus un supplément par tranche de 100 m de dénivelé positif (randonnée 10 min, jogging 6, VTT 4, vélo de voyage 3, vélo de route 2,5) et, uniquement pour le vélo de voyage et le vélo de route, une réduction par tranche de 100 m de descente (1 et 1,5 min ; au plus un quart du temps sur terrain plat).

**Outils de trace et affichage**
- En mode modification, le menu ciseaux propose *Rogner à la plage sélectionnée* (conserve la partie située entre le premier et le dernier point sélectionnés ; sélectionnez une plage en faisant glisser dans le profil
  altimétrique), *Couper au point sélectionné …* (écrit deux nouveaux fichiers à côté de l’original, l’original reste inchangé) et *Lisser* (moyenne mobile légère, moyenne ou forte de
  la position et de l’altitude, pour la plage sélectionnée ou la trace entière). Tout peut être annulé avec ⌘Z ; rien n’est enregistré avant que vous n’enregistriez.
- *Mesurer* (bouton règle) : cliquez sur des points de la carte, la longueur jusqu’à chaque point est affichée. Échap termine, clic droit retire le dernier point.
- *Couleur* (bouton palette) : colore la trace sélectionnée selon la **vitesse** (nécessite l’horodatage), la **pente** (nécessite les altitudes), la **fréquence cardiaque**, la **puissance** ou la **cadence**, sur la carte et dans le graphique situé dessous ;
  bleu = faible ou descente, vert = moyen, rouge = élevé ou montée raide. Une légende apparaît en haut à gauche de la carte. Par défaut, c’est la couleur normale de la trace.
- De petites **flèches de direction** (carrés blancs avec une flèche de la couleur de la trace) courent le long des traces sélectionnées ; désactivez-les dans le même menu.
- La barre d’outils est groupée comme celle du Finder : vue de la carte, trace, modification, itinéraire. *Présentation → Afficher les libellés de la barre d’outils* ajoute un court texte sous chaque symbole.
- Plusieurs onglets : *Présentation → Afficher la barre d’onglets*, puis le bouton +. Chaque onglet a son propre dossier, sa propre sélection et sa propre carte.

**Photos sur la carte**
- Choisissez un dossier de photos (au premier démarrage une fenêtre le demande, ensuite dans Réglages → Stockage → Photos). Le dossier et tous ses sous-dossiers sont seulement **lus** – aucune photo n’est
  ajoutée, supprimée ni modifiée. Les photos sans données GPS sont ignorées ; les formats RAW ne sont pas lus.
- La position, la date et l’appareil photo sont lus dans les métadonnées des photos et conservés dans un cache (index et miniatures) dans le dossier « Photos » du dossier de cache des cartes en ligne ; le
  cache est mis à jour à chaque démarrage, de sorte que les changements du dossier de photos sont remarqués. La première lecture d’un gros dossier prend quelques minutes (progression en haut à droite de la carte).
- Le bouton photo de la barre d’outils active et désactive les vignettes (clic avec ⌥ ou clic droit : options, par ex. *Seulement le long de la trace sélectionnée*). Partout où il y a des photos, une
  image de la taille d’un timbre de la photo la plus récente est affichée, avec sa date dessous et le nombre de photos dans un cercle rouge. Les zones deviennent plus fines à mesure que vous zoomez.
- Cliquez sur une vignette : une bande avec les photos remplace le graphique d’altitude (faites-la glisser avec la souris ou utilisez les flèches ; le ✕ ou Échap la ferme). Cliquez sur une photo pour une grande vue avec
  chemin complet, date, heure et appareil photo ; Échap ou ✕ la ferme, les touches fléchées passent à la photo précédente et suivante.

**Komoot (non officiel)**
- *Fichier → Se connecter à Komoot …* (passer à *Importer* dans la fenêtre) liste tous vos tours (planifiés et enregistrés) et marque ceux qui ne se trouvent dans aucun dossier situé sous le dossier principal (comparés d’après l’heure de départ et le
  numéro du tour). Les tours marqués peuvent être téléchargés dans le dossier « Komoot » du dossier principal ; choisissez une année pour restreindre la liste. L’onglet *Exporter* de la même fenêtre envoie la trace
  sélectionnée comme nouveau tour. Rien de ce qui existe déjà chez Komoot n’est jamais modifié ni supprimé.
- Komoot n’a pas d’interface publique pour les particuliers. L’app utilise la même interface non documentée que d’autres outils communautaires ; elle peut cesser de fonctionner à tout moment et n’est peut-être pas
  couverte par les conditions d’utilisation de Komoot. L’adresse e-mail et le mot de passe ne sont enregistrés que dans le trousseau macOS.

**Mode sombre**
- *Réglages → Général → Apparence* : comme le système, clair ou sombre. En apparence sombre, les cartes sont aussi affichées en sombre (à désactiver avec *Afficher aussi les cartes en sombre*) : la luminosité de la carte est inversée et chaque couleur garde sa teinte
  (l’eau reste donc bleue et la forêt verte). Les photos aériennes ne sont pas modifiées.

**Appareils Garmin (USB)** – montres et compteurs vélo Edge, dans les deux sens
- *Fichier → Se connecter à Garmin …* (ou l’icône câble à gauche du choix de la carte dans la barre d’outils) (onglet *Importer depuis l’appareil*) lit les fichiers d’activité (FIT) directement depuis un appareil connecté en USB, sans Garmin Connect. Les compteurs vélo (Edge) apparaissent comme un volume nommé GARMIN et sont lus dans
  `Garmin/Activities`. Les montres récentes n’apparaissent pas comme un volume (elles utilisent MTP) ; l’app parle elle-même MTP. La liste montre toutes les activités de l’appareil avec la date, l’heure et la taille et marque celles dont le nom de fichier n’est pas encore
  trouvé dans vos dossiers ; celles qui sont marquées sont téléchargées dans le dossier « Garmin » du dossier principal (année sélectionnable). L’appareil est seulement lu. Utilisez un câble de données USB ; si un autre programme retient l’appareil
  (par ex. Android File Transfer ou Garmin Express), la fenêtre le signale et propose de le quitter. Les fichiers FIT contiennent la fréquence cardiaque, la cadence et la puissance.
- L’onglet *Envoyer vers l’appareil* (aussi depuis le menu contextuel de la liste des fichiers) place les traces et itinéraires marqués sur l’appareil pour les parcourir plus tard. Tout format pris en charge est converti en GPX – comme trace (l’appareil
  l’affiche comme un parcours à suivre) ou comme itinéraire (pour les propres instructions de virage de l’appareil) – et copié dans `Garmin/NewFiles` ; l’appareil prend en compte les nouveaux parcours quand il est débranché. Pour un volume, la
  fenêtre peut ensuite éjecter l’appareil. Rien n’est modifié ni supprimé sur l’appareil, et vos propres fichiers restent tels quels. Sur un Edge, choisissez le mode « Garmin » (stockage de masse) si l’appareil le demande.

**Statistiques**
- *Statistiques → Statistiques des traces …* (⌥⌘S) : nombre de traces, distance, dénivelé positif et temps en mouvement par dossier (avec ou sans sous-dossiers), par année ou par mois sur tous les dossiers,
  éventuellement seulement les traces enregistrées (avec horodatage) et pour une année, avec un diagramme en barres.
- *Statistiques → Rechercher les traces en double …* : groupes de traces dont les 100 premiers points de trace sont identiques (les fichiers GPX et FIT ne sont comparés entre eux que si l’interrupteur du haut le permet). La trace proposée à conserver est marquée ; cliquez sur le nom d’une trace pour l’afficher
  dans la fenêtre principale, ou placez les copies dans la corbeille (toujours après confirmation ; elles peuvent être récupérées depuis la corbeille).

## Configuration requise

- macOS 14 ou ultérieur, Apple Silicon
- **Avec l’app prête à l’emploi (voir Téléchargement ci-dessous) : rien d’autre.** L’app n’utilise que des bibliothèques faisant partie de macOS et ne
  lance aucun programme auxiliaire, aucun outil de développement n’est donc nécessaire pour l’exécuter.
- **Seulement pour compiler depuis les sources :** les *Command Line Tools* d’Apple (le compilateur Swift ; Xcode complet n’est pas nécessaire). Installez-les une fois :
  1. Ouvrez l’app *Terminal* (Spotlight : saisissez « Terminal »).
  2. Exécutez `xcode-select --install`.
  3. Cliquez sur *Installer* dans la fenêtre qui apparaît, acceptez la licence et attendez la fin (quelques minutes, 1 à 2 Go).
  4. Vérifiez avec `swift --version` : cela doit afficher un numéro de version (Swift 5.9 ou plus récent).

  Si macOS vous demande un jour d’installer les « outils de développement en ligne de commande » (par exemple quand une commande du Terminal comme `git`, `swift`
  ou `xattr` est utilisée sur un Mac qui ne les a pas encore), les étapes ci-dessus sont la bonne réponse : cliquez sur *Installer* et attendez.

## Téléchargement

App prête à l’emploi : téléchargez `GPX-Organizer-<version>.zip` depuis la [dernière version](https://github.com/Martin-Doppelbauer/gpx-organizer/releases/latest),
décompressez-le (double-clic) et déplacez *GPX Organizer* dans votre dossier *Applications*.

L’app est signée avec un Developer ID Apple et notariée par Apple : elle s’ouvre donc par un simple double-clic. Si macOS demande
si vous voulez ouvrir une app téléchargée sur Internet, cliquez sur **Ouvrir**.

## Compiler et lancer

```sh
git clone https://github.com/Martin-Doppelbauer/gpx-organizer.git
cd gpx-organizer
./build_app.sh
open "dist/GPX Organizer.app"
```

L’app n’est signée qu’« ad hoc ». Si macOS refuse de l’ouvrir, faites un clic droit sur l’app et choisissez *Ouvrir*.
Pour une version signée et notariée, voir [RELEASING.md](RELEASING.md).

## Premier démarrage

Au premier démarrage, l’app demande où stocker vos cartes : elle peut créer un dossier par défaut
(`~/Library/Application Support/GPX Organizer/Maps`) ou utiliser un dossier que vous choisissez. Le dossier reçoit un sous-dossier par
carte en ligne intégrée pour son cache de tuiles. Ensuite, votre dossier Documents est affiché à gauche ; utilisez *Dossier …* pour passer au
dossier qui contient vos fichiers GPX.

## Confidentialité et services cartographiques

L’app ne lit que les dossiers que vous sélectionnez (et ne modifie des fichiers que lorsque vous les modifiez, les enregistrez ou les déplacez ; avant qu’un fichier ne soit remplacé, son original est placé dans la corbeille de macOS (l’app vous le dit)).
Les cartes en ligne chargent des tuiles depuis les serveurs des fournisseurs de cartes pendant que vous naviguez. Veuillez respecter leurs règles d’utilisation ; l’app ne propose pas de téléchargement en masse de grandes régions.
Des données ne quittent votre Mac que pour les fonctions que vous utilisez : tuiles de carte, calcul d’itinéraire en ligne (les points d’itinéraire vont à brouter.de), remplacement des altitudes (les points de trace vont à open-meteo.com)
et import/export Komoot (vers Komoot, avec votre identifiant du trousseau). Les photos, leurs métadonnées et le cache des photos restent sur votre Mac.

Données cartographiques et services :
- © contributeurs d’OpenStreetMap (ODbL)
- OpenTopoMap (CC-BY-SA), données cartographiques © contributeurs d’OpenStreetMap, SRTM
- TopPlusOpen © Agence fédérale de cartographie et de géodésie (BKG)

## Licence

GPX Organizer est un logiciel libre, sous licence **GNU General Public License v3.0 ou ultérieure**. Voir [LICENSE](LICENSE).
Copyright © 2026 Martin Doppelbauer.

GPX Organizer est un projet indépendant, ni affilié à Garmin Ltd. ni approuvé par cette société.
Garmin et BaseCamp sont des marques de Garmin Ltd.
