# Construction de Strata

Ce document décrit comment Strata est construit : ses objectifs, son architecture, le fonctionnement de chaque module et les raisons des choix faits. Il s'adresse à qui veut comprendre le code, le vérifier ou y contribuer.

Version décrite : **0.1.0**.

## Sommaire

1. [Objectifs et contraintes](#1-objectifs-et-contraintes)
2. [Vue d'ensemble](#2-vue-densemble)
3. [Données des zones](#3-données-des-zones)
4. [Lecture des cartes du client](#4-lecture-des-cartes-du-client)
5. [Positions](#5-positions)
6. [Le canevas et ses couches](#6-le-canevas-et-ses-couches)
7. [Chargement et mémoire](#7-chargement-et-mémoire)
8. [Zoom et déplacement](#8-zoom-et-déplacement)
9. [Joueur et groupe](#9-joueur-et-groupe)
10. [Interface et langues](#10-interface-et-langues)
11. [Données sauvegardées](#11-données-sauvegardées)
12. [Performances](#12-performances)
13. [Vérification](#13-vérification)
14. [Mesure en jeu](#14-mesure-en-jeu)
15. [Limites connues](#15-limites-connues)
16. [Contribuer](#contribuer)

---

## 1. Objectifs et contraintes

**Objectifs**
- Une seule carte continue : passer d'une zone à l'autre, et du monde entier à la rue, sans changer de carte.
- Rester fidèle aux cartes du jeu : Strata n'invente aucune image, il assemble celles du client.
- Fonctionner sur n'importe quel serveur 3.3.5, sans patch client ni modification côté serveur.
- Rester léger : un client 3.3.5 est un programme 32 bits, la mémoire des textures compte.

**Contraintes**
- **Client 3.3.5a** (Interface `30300`). Une grande partie de l'API des cartes modernes n'existe pas encore :
  - pas de `C_Map` : ni rectangle d'une zone sur son continent, ni carte choisie par identifiant (`SetMapByID` arrive en 4.0) ;
  - pas de textures masques (`CreateMaskTexture`, 7.0) : impossible de fondre deux zones l'une dans l'autre à la volée ;
  - pas de `MapCanvas` : la carte de Blizzard est un cadre fixe de 1002 × 668 pixels sans zoom ;
  - pas de `C_Timer` : les minuteries passent par `OnUpdate`.
- **Lua 5.1**, comme le client.
- **Aucune bibliothèque embarquée.**

## 2. Vue d'ensemble

| Fichier | Rôle |
|---|---|
| `Strata.toc` | Déclaration de l'addon pour le client |
| `Locale.lua` | Textes de l'interface, en anglais et en français |
| `Data/Zones.lua` | Taille et position de chaque continent et zone, en yards (généré) |
| `Core.lua` | Réglages, lecture des cartes du client, conversion des positions, commandes |
| `Map.lua` | La fenêtre, le canevas, le zoom, les icônes |
| `Bench.lua` | Mesure en jeu : compteur à l'écran (`/strata debug`) et parcours de mesure (`/strata bench`) |
| `Bindings.xml` | Le raccourci clavier |
| `tools/extract_zones.py` | Génère `Data/Zones.lua` |
| `tests/` | Banc de simulation : un client 3.3.5 simulé et un scénario |

Le client fournit tout ce qui se voit : images des cartes, morceaux découverts, noms des zones (déjà traduits), positions des unités. Strata n'apporte que les rectangles des zones, que le client ne donne pas à un addon.

## 3. Données des zones

La carte d'une zone, dans le client, couvre un rectangle connu du jeu (table `WorldMapArea`). Pour placer une zone sur son continent, il faut ce rectangle : sa largeur, sa hauteur et son coin haut-gauche, en yards. L'API 3.3.5 ne le donne pas.

Ces valeurs sont reprises de la table `WorldMapSize` d'Astrolabe, la bibliothèque de positionnement de référence en 3.3.5. `tools/extract_zones.py` la lit et écrit `Data/Zones.lua` :

```lua
[2] = { w = 40741.175, h = 27149.795, x = 18542.312, y = 3585.575, parent = 0, zones = {
	Elwynn = { 3470.833, 2314.592, 16636.551, 19116.002 },
	Northshire = { 968.75, 645.834, 17984.471, 19747.176, true },
} },
```

- Un continent porte son rectangle sur la carte du monde (`parent = 0`). Kalimdor, les Royaumes de l'Est et le Norfendre partagent ainsi un même repère : c'est ce qui permet une seule carte pour Azeroth. L'Outreterre est son propre parent.
- Une zone est indexée par le **nom de fichier de sa carte**, celui que renvoie `GetMapInfo()`. Ce nom ne dépend pas de la langue du client, contrairement aux noms affichés.
- Certains serveurs ajoutent des micro-cartes (grottes, zones de départ, étages). Elles sont marquées `true` en cinquième valeur : elles servent à placer le joueur quand il s'y trouve, mais ne sont pas dessinées, pour ne pas recouvrir les vraies zones. L'outil les reconnaît en comparant avec un Astrolabe de client non patché (`tools/ref/`).

## 4. Lecture des cartes du client

`ns.Scan` (`Core.lua`) parcourt chaque continent et chaque zone avec `SetMapZoom`, et retient pour chacune :
- le nom de fichier de la carte (`GetMapInfo`) ;
- le préfixe de ses tuiles, calculé comme `WorldMapFrame_Update` (étage de donjon compris) ;
- ses morceaux découverts (`GetMapOverlayInfo`) : seuls ceux que le joueur a découverts sont renvoyés, ce qui donne le brouillard sans aucune donnée en plus.

`SetMapZoom` change la carte sélectionnée du client, celle que partagent la carte de Blizzard et les autres addons. La lecture n'a donc lieu que **carte de Blizzard fermée**, et la zone du joueur est resélectionnée juste après (`SetMapToCurrentZone`). Elle est faite une fois, à la première ouverture. Ensuite, seule la zone du joueur est relue, à chaque ouverture et à chaque changement de zone, pour suivre ce qui vient d'être découvert.

## 5. Positions

`GetPlayerMapPosition` donne une position de 0 à 1 **sur la carte sélectionnée**, quelle qu'elle soit. `ns.UnitPos` lit donc la carte sélectionnée (continent, fichier, niveau zone ou continent) et convertit avec son rectangle :

```
yards dans le continent = coin de la zone + position × taille de la zone
yards dans la vue       = yards dans le continent + coin du continent (vue Azeroth)
```

Cette conversion reste juste même si un autre addon a sélectionné une autre carte, tant que l'unité s'y trouve. Si le joueur n'est sur aucune carte connue alors que la carte de Blizzard est fermée, Strata resélectionne sa zone, au plus une fois toutes les 2 secondes. En instance, le client renvoie 0, 0 : la flèche est masquée.

`ns.ZoneAt` fait le chemin inverse pour le survol : la plus petite zone dessinée qui contient le point, et la position dans cette zone en pourcentage. Appelée deux fois toutes les 30 ms (survol et joueur), elle passe par un index : une grille de 32 × 32 cases sur l'étendue des zones de la vue, construite au premier appel, où chaque case liste les zones qui la touchent, de la plus petite à la plus grande. Seules ces quelques zones sont testées, et la première qui contient le point est la bonne. Le banc vérifie que le résultat est identique au parcours complet.

## 6. Le canevas et ses couches

Chaque vue (Azeroth, Outreterre) a son canevas de 1 000 unités de large. Une unité vaut `1 / k` yard, avec `k = 1000 / largeur de la vue`. Tout est placé une fois pour toutes en unités sur ce canevas.

Couches, de bas en haut (un cadre par couche, niveaux croissants) :

| Couche | Contenu | Visible |
|---|---|---|
| `world` | la carte du monde de Blizzard | vue Azeroth, toujours |
| `cont` | la carte du continent **sous le centre de la vue** | en fondu, de 1,4 à 2,2 fois le zoom minimal |
| `base` | le fond de chaque zone, 12 tuiles | si le brouillard est affiché |
| `over` | les morceaux découverts de chaque zone | toujours |
| `city` | les villes, entièrement peintes | au-dessus de leurs voisines |

Les tuiles d'une carte suivent exactement la carte de Blizzard : une grille de 4 × 3 tuiles de 256 pixels dont seuls 1002 × 668 pixels sont utiles. Les tuiles de bord sont recadrées (`SetTexCoord`). Les morceaux découverts sont découpés comme le fait `WorldMapFrame_Update`, avec la taille de fichier en puissance de 2 pour les tuiles de bord.

Une seule carte de continent est affichée à la fois : leurs rectangles se chevauchent largement en mer (celui du Norfendre couvre le nord des Royaumes de l'Est), et leur océan opaque masquerait le continent voisin.

Une zone paraît quand sa largeur à l'écran dépasse 220 pixels (90 pour une ville), en fondu jusqu'à 1,6 fois ce seuil. Les grandes zones sont posées d'abord, pour qu'une petite reste lisible.

## 7. Chargement et mémoire

Charger toutes les zones d'Azeroth représenterait plus de 5 000 textures. Strata ne charge donc que ce qui se voit :
- `UpdateLayers` calcule le rectangle visible et, pour chaque zone, si elle le touche et si elle est assez grande à l'écran ;
- une zone qui devient visible charge ses tuiles (`LoadZone`) ;
- une zone qui sort de la vue est masquée tout de suite, et rend ses textures **8 secondes** plus tard (`ReleaseHidden`, toutes les 2 secondes). Un aller-retour rapide ne recharge donc rien ;
- les zones cachées mais encore chargées sont plafonnées à **160 textures** (`MAX_HIDDEN`) : au-delà, les plus anciennes sont rendues tout de suite. Sans ce plafond, un déplacement rapide accumulait plus de 1 000 textures en attente ;
- **carte fermée**, toutes les zones rendent leurs textures ; seules restent les cartes du monde et des continents (60 tuiles), qui reviennent sans délai. **Changer de vue** rend de même les zones de la vue quittée ;
- les textures rendues retournent dans une réserve par couche et sont réutilisées.

Une couche qui a disparu en fondu est **masquée**, pas laissée à transparence nulle : le client ne dessine pas un objet masqué.

## 8. Zoom et déplacement

Le canevas est placé dans un `ScrollFrame`, qui le rogne aux bords de la fenêtre. L'état de la vue tient en trois nombres : le zoom, et la position à l'écran de l'origine du canevas.

- **Un déplacement ou un zoom ne touche qu'un seul cadre** : `SetView` change l'échelle du canevas et son unique ancrage. Les milliers de tuiles, ancrées au canevas, suivent sans être replacées une à une.
- La molette lance un zoom animé vers une cible, multipliée par 1,3 par cran. Le point sous le curseur reste immobile : `ZoomAt` recalcule l'origine pour que ce point garde sa position à l'écran.
- La vue est bornée : zoom entre « tout le monde visible » et 40, et un quart de fenêtre de marge au-delà des bords.
- La dernière vue de chaque carte est retenue (centre et zoom), ainsi que la taille et la position de la fenêtre.

## 9. Joueur et groupe

Les icônes sont posées sur un cadre **non mis à l'échelle** au-dessus du canevas : elles gardent leur taille à l'écran quel que soit le zoom, et seule leur position est recalculée.

- La flèche du joueur (`Interface\Minimap\MinimapArrow`) est tournée selon `GetPlayerFacing` en recalculant les coordonnées de ses quatre coins. Attention : les fonctions globales `cos` et `sin` de WoW prennent des **degrés**, la rotation utilise donc `math.cos` et `math.sin`.
- Les membres du groupe ou du raid utilisent `Interface\WorldMap\WorldMapPartyIcon`, teintée à la couleur de leur classe.
- Positions et survol sont mis à jour toutes les 30 ms, la visibilité des zones au plus toutes les 80 ms et seulement si la vue a changé.

## 10. Interface et langues

Tous les textes affichés passent par `ns.L` (`Locale.lua`) : anglais par défaut, français si `GetLocale()` vaut `frFR`. Les noms de zones n'y sont pas : ils viennent de `GetMapZones`, déjà dans la langue du client.

La fenêtre a un fond et une bordure de boîte de dialogue standard. Elle se déplace par la barre de titre et se redimensionne par la poignée en bas à droite. Échap la ferme (`UISpecialFrames`). Elle est indépendante de la carte de Blizzard, pour ne pas entrer en conflit avec les addons qui la modifient (Mapster, Magnify).

## 11. Données sauvegardées

`StrataDB`, par compte :

| Clé | Contenu |
|---|---|
| `fog` | affichage du fond des zones |
| `w`, `h`, `point` | taille et position de la fenêtre |
| `views[vue]` | zoom et centre de la dernière vue de chaque carte |
| `lastView` | la dernière carte affichée |

## 12. Performances

| Situation | Travail |
|---|---|
| Fenêtre fermée | aucun (pas d'`OnUpdate`) |
| Déplacement, zoom | un `SetScale` et un `SetPoint` par image |
| Vue qui change | parcours des 73 zones de la vue, au plus toutes les 80 ms |
| Icônes | jusqu'à 40 positions de raid toutes les 30 ms |
| Mémoire | les zones visibles, plus au plus 160 textures cachées pendant 8 s ; carte fermée : 60 tuiles |

Ces coûts sont tenus par les budgets du banc (section 13). Pistes suivies dans la [feuille de route](FEUILLE-DE-ROUTE.md) : saccade possible à la première ouverture (#8).

## 13. Vérification

Les règles (cycle des tickets, vérifications obligatoires, test en jeu) sont dans [SUIVI.md](SUIVI.md). Cette section décrit les outils.

Le banc de simulation (`tests/`) charge le vrai code de l'addon, dans l'ordre du `.toc`, dans un client 3.3.5 simulé (Lua 5.1 via lupa). Chaque scénario part d'un client neuf. Le client simulé reprend les 73 zones de `Data/Zones.lua`, des morceaux découverts factices, un joueur au milieu de la Forêt d'Elwynn et un membre de groupe. Le scénario vérifie notamment :
- la lecture des 73 zones (24 en Kalimdor, 29 dans les Royaumes de l'Est, 8 en Outreterre, 12 en Norfendre) ;
- la flèche au centre de la vue à l'ouverture, et tournée ;
- le survol du joueur, qui doit lire « Elwynn 50.0, 50.0 » ;
- le nombre de textures visibles dézoomé et le plafond de textures créées ;
- les boutons, la vue Outreterre, les commandes, la mémorisation de la vue ;
- les deux langues.

Les fonctions `cos` et `sin` du client simulé prennent des degrés, comme dans le jeu, pour attraper une confusion. Après chaque scénario, le banc refuse toute variable globale créée par l'addon hors de la liste attendue.

**Performances** (`tests/perf.lua`). Le travail est **compté**, pas chronométré : instructions Lua exécutées, par centaines, via `debug.sethook`, et appels à l'API du client simulé (`SetPoint`, `SetTexture`, `CreateTexture`, `SetScale`, `SetMapZoom`, `GetPlayerMapPosition`…). Ces chiffres sont déterministes : même code, même mesure, sur n'importe quelle machine. Chaque situation (ouverture, immobile, déplacement, zoom, tour d'Azeroth, raid de 40, carte fermée) est comparée à son budget dans `tests/budgets.lua`, avec la valeur de référence en commentaire. Le tableau des mesures est publié dans le résumé de chaque vérification sur GitHub.

À chaque envoi sur GitHub, la vérification automatique contrôle la syntaxe Lua 5.1, les fichiers du `.toc`, la cohérence des numéros de version (`Core.lua`, `Strata.toc`, `CHANGELOG.md`), les en-têtes de licence, et passe le banc en français et en anglais.

## 14. Mesure en jeu

Le banc compte le travail du code, mais ne voit ni le rendu ni la mémoire réelle du client. `Bench.lua` les mesure dans le jeu.

**Coût nul hors mesure.** `Map.lua` tient deux compteurs entiers (textures et zones chargées, une addition à chaque chargement ou libération). Le chronométrage (`debugprofilestop`) ne tourne que si `ns.measuring` est vrai, c'est-à-dire compteur affiché ou bench en cours. Le banc le vérifie (`compteur masqué`, `immobile`).

**Compteur (`/strata debug`).** Un cadre dans le coin de la carte, rafraîchi toutes les 0,5 s : images par seconde (`GetFramerate`), temps moyen et pire de Strata par image sur la dernière demi-seconde, temps de la dernière mise à jour des couches, textures et zones chargées, mémoire Lua de l'addon. La mémoire n'est relue que toutes les 2 s : `UpdateAddOnMemoryUsage` parcourt tous les addons du client.

**Parcours (`/strata bench`).** Un cadre pilote la carte par l'accès interne `ns.view` (centrer, déplacer, zoomer), pendant que la souris est ignorée :

| Phase | Durée | Ce qui se passe |
|---|---|---|
| Carte fermée | 2 s | référence d'images par seconde sans Strata |
| Immobile | 3 s | carte centrée sur le joueur, zoom 6, mesurée après 0,5 s d'attente (la réouverture de la carte n'est pas comptée) |
| Déplacement | 4 s | aller-retour à 360 px/s, pour ne jamais buter sur un bord |
| Zoom | 4 s | va-et-vient entre les zooms 3 et 20 |
| Tour d'Azeroth | 8 s | 20 points de la carte, 0,4 s chacun, zoom 6 |
| Dézoomé | 2 s | le monde entier |

Pour chaque phase : images par seconde, temps de Strata par image (moyenne et pire) et pic de textures chargées. Puis la durée de la lecture des cartes à la première ouverture de la session (`ns.Scan`, chronométrée à chaque fois), la mémoire Lua de l'addon et la mémoire Lua totale du jeu (`collectgarbage("count")`), et la comparaison avec les [objectifs de performance en jeu](FEUILLE-DE-ROUTE.md#objectifs-de-performance-en-jeu). Certains clients renvoient 0 pour la mémoire d'un addon : elle est alors indiquée « indisponible » et l'objectif « à revoir », jamais « ok ». La vue d'avant est rétablie, les résultats s'affichent dans une boîte de texte prête à copier dans un rapport de test, et sont enregistrés (`StrataDB.lastBench`).

## 15. Limites connues

- **Joints entre zones.** Sans textures masques, deux zones voisines ne se fondent pas : leurs fonds se superposent par rectangles. Une version pré-assemblée hors du jeu est à l'étude.
- **Pas de zoom minicarte.** Les tuiles de la minicarte existent dans le client, mais sous des noms chiffrés. Il faudrait livrer leur table de correspondance.
- **Première ouverture.** La lecture de toutes les cartes déclenche des mises à jour de carte que d'autres addons (Questie, Mapster) peuvent suivre : une courte saccade est possible.
- **Instances.** Le client ne donne pas de position en instance : la flèche est masquée.

## Contribuer

Les règles à respecter pour qu'une modification soit acceptée :

- **Lua 5.1 et API 3.3.5 uniquement.** Vérifiez chaque fonction : beaucoup d'exemples trouvés en ligne viennent de versions plus récentes.
- **Aucune bibliothèque embarquée.**
- **Chaque texte affiché en français et en anglais**, dans `Locale.lua`.
- **Rien qui charge des textures hors de la vue**, et toute nouvelle couche masquée quand elle n'est pas visible.
- **`Data/Zones.lua` ne se modifie pas à la main** : changez l'outil et régénérez.
- **Le banc doit passer** dans les deux langues, et toute nouvelle fonction doit y être vérifiée.

Voir aussi [CONTRIBUTING.md](../CONTRIBUTING.md).
