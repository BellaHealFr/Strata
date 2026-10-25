<div align="center">

# Strata

**Carte du monde continue pour World of Warcraft 3.3.5 (Wrath of the Lich King)**

*Par un passionné de Wrath of the Lich King, pour tous ceux qui aiment encore explorer Azeroth.*

![Statut](https://img.shields.io/badge/statut-en%20d%C3%A9veloppement-orange)
[![Version stable](https://img.shields.io/github/v/release/BellaHealFr/Strata?label=stable&color=1e90ff)](../../releases/latest)
[![Bêta](https://img.shields.io/github/v/release/BellaHealFr/Strata?include_prereleases&label=b%C3%AAta&color=orange)](../../releases)
![Client](https://img.shields.io/badge/client-3.3.5a-1e90ff)
![Lua](https://img.shields.io/badge/Lua-5.1-000080)
![Dépendances](https://img.shields.io/badge/d%C3%A9pendances-aucune-success)
![Langues](https://img.shields.io/badge/langues-fran%C3%A7ais%20%C2%B7%20english-informational)
![Licence](https://img.shields.io/badge/licence-GPL--3.0-blue)
[![Téléchargements](https://img.shields.io/github/downloads/BellaHealFr/Strata/total?label=t%C3%A9l%C3%A9chargements&color=success)](../../releases)

</div>

---

> **Projet en développement.** Strata fonctionne déjà, mais il grandit version après version vers une carte aussi complète qu'OpenMap (voir la [feuille de route](#feuille-de-route)). La **version stable** est la plus sûre ; les **bêtas** (marquées *Pre-release*) permettent d'essayer les nouveautés en avance. Vos retours, même courts, aident beaucoup : ouvrez un ticket dans l'onglet **Issues**.

Strata remplace le découpage zone par zone de la carte par **une seule carte continue**. Kalimdor, les Royaumes de l'Est et le Norfendre sont placés à leur vraie position, et l'on passe du monde entier à la rue d'une ville d'un simple coup de molette, sans jamais changer de carte.

Il ne dessine rien lui-même : il assemble les cartes de Blizzard déjà présentes dans votre jeu. Pas de patch à installer, rien à demander au serveur. Strata fonctionne sur n'importe quel serveur 3.3.5.

## Par un passionné, pour les passionnés

Il y a ceux qui connaissent la route de Hurlevent à Forgefer par cœur, et ceux qui découvrent encore le Norfendre pour la première fois. Dans les deux cas, la carte de la 3.3.5 a ses limites : une zone à la fois, pas de zoom, et ce « clic droit pour remonter » qui coupe le voyage en morceaux.

Strata est né d'une envie simple : voir Azeroth comme un seul monde. Suivre la côte de la Désolation des dragons jusqu'au Fjord Hurlant, regarder où se trouve Dalaran par rapport à la Couronne de glace, mesurer d'un regard le chemin entre deux maîtres de vol.

Il a été écrit pour le client 3.3.5, pas adapté d'une autre version du jeu. L'idée vient d'OpenMap, la carte continue de WoW Forever. Mais tout ce qu'OpenMap fait avec l'API moderne a dû être repensé ici : la 3.3.5 n'a ni textures masques, ni carte à zoom, ni rectangle des zones dans son API.

## Pourquoi Strata

- **Une seule carte.** Trois continents dans le même repère, à leur vraie place. L'Outreterre a sa propre vue, à un clic.
- **Fidèle au jeu.** Les cartes, les zones découvertes et les noms sont ceux de votre client. Les zones que vous n'avez pas encore explorées restent dans le brouillard, comme sur la carte de Blizzard.
- **Léger.** Strata ne charge que les zones visibles à l'écran, et les libère quelques secondes après les avoir quittées. Un déplacement ou un zoom ne bouge qu'un seul cadre, quel que soit le nombre de zones affichées.
- **À côté de la carte de Blizzard, pas à sa place.** Strata ouvre sa propre fenêtre et ne modifie pas la carte de Blizzard, que Mapster, Magnify ou Questie peuvent continuer à personnaliser.
- **En français et en anglais**, selon la langue de votre client.

## Fonctionnalités

### La carte
- **Zoom à la molette**, animé, à l'endroit du curseur. **Déplacement** au clic gauche glissé, **dézoom** au clic droit.
- **Des couches qui apparaissent avec le zoom** : la carte du monde, puis celle du continent que vous regardez, puis chaque zone avec vos zones découvertes, et enfin les villes, entièrement peintes.
- **Brouillard** : le bouton *Brouillard* affiche ou masque le fond des zones non découvertes.

### Vous et votre groupe
- **Votre position**, avec une flèche orientée dans la direction où vous regardez. Le bouton *Moi* recentre la carte sur vous.
- **Votre groupe ou votre raid**, aux couleurs de chaque classe.
- **Zone et coordonnées** sous le curseur, et pour votre position dans la barre de titre.

### La fenêtre
- **Bouton autour de la minicarte** pour ouvrir la carte d'un clic, déplaçable, compatible avec les minicartes carrées.
- Déplaçable, redimensionnable. Sa taille, sa position et la dernière vue de chaque carte sont retenues.
- Échap la ferme. Un raccourci clavier se règle dans *Menu → Raccourcis → Strata*.
- Les micro-cartes ajoutées par certains serveurs (grottes, zones de départ) sont prises en compte pour vous placer.

## Feuille de route

Strata en est à ses débuts. Les prochaines versions reprennent, adaptées à la 3.3.5, les fonctions qui font la force d'OpenMap :

| Version | Au programme |
|---|---|
| **0.2** | mesure des performances en jeu, mémoire allégée, bouton de la minicarte, recherche de zones et de villes, épingles avec note et flèche TomTom, niveau des zones au survol, plein écran |
| **0.3** | maîtres de vol (appris et inconnus, route et temps de vol), routes des bateaux et zeppelins, entrées de donjons et de raids, PNJ utiles, objectifs de quêtes |
| **0.4** | plume pour dessiner sur la carte, partage d'épingles, menu et options, fenêtre des nouveautés |
| **0.5** | zoom au niveau de la minicarte, fondu entre zones pré-assemblé |

Le plan complet, l'ordre des tâches et les critères de sortie de chaque version sont dans **[docs/FEUILLE-DE-ROUTE.md](docs/FEUILLE-DE-ROUTE.md)**. Chaque fonction est suivie dans les **[jalons](../../milestones)** et les **[tickets](../../issues)**.

Aucune modification n'entre sans vérification automatique, budgets de performance compris, et aucune version ne sort sans test en jeu : les règles sont dans **[docs/SUIVI.md](docs/SUIVI.md)**.

## Installation

1. Téléchargez `Strata-x.y.z.zip` dans **[Releases](../../releases)** : la version marquée *Latest* est la stable ; celles marquées *Pre-release* sont des bêtas, pour essayer les nouveautés en avance.
   > **Attention** : n'utilisez pas le bouton vert *Code → Download ZIP*, qui produit un dossier `Strata-main` que le jeu ne charge pas.
2. Quittez complètement le jeu.
3. Décompressez l'archive dans `World of Warcraft/Interface/AddOns/`. Vous devez obtenir `AddOns/Strata/Strata.toc`.
4. Relancez le jeu, puis tapez `/strata`.

## Commandes

| Commande | Effet |
|---|---|
| `/strata` ou `/str` | ouvrir ou fermer la carte |
| `/strata brouillard` | afficher ou masquer le fond des zones |
| `/strata scan` | relire les cartes du client |
| `/strata reset` | remettre la fenêtre et les vues à zéro |
| `/strata bouton` | afficher ou masquer le bouton de la minicarte |
| `/strata bench` | mesurer les performances (environ 25 s), résultats à copier |
| `/strata debug` | afficher ou masquer le compteur de performance |
| `/strata aide` | rappel des commandes |

| Souris | Effet |
|---|---|
| Molette | zoomer ou dézoomer à l'endroit du curseur |
| Clic gauche glissé | déplacer la carte |
| Clic droit | dézoomer |

## Sous le capot

| | |
|---|---|
| Client | 3.3.5a (build 12340), `## Interface: 30300` |
| Langage | Lua 5.1, API WoW 3.3.5 |
| Dépendances | aucune |
| Code | environ 1 500 lignes, 6 fichiers, plus les rectangles de 126 cartes de zones |

Le fonctionnement complet est décrit dans **[docs/CONSTRUCTION.md](docs/CONSTRUCTION.md)** : données des zones, lecture des cartes du client, conversion des positions, couches de la carte, chargement et mémoire, zoom, performances et vérification.

L'historique des versions est dans **[CHANGELOG.md](CHANGELOG.md)**.

## Contribuer

Les signalements de bugs et les suggestions sont les bienvenus dans l'onglet **Issues**. Pour un problème d'affichage, joignez une capture d'écran de la carte en indiquant la zone et le serveur.

Pour proposer une modification du code, lisez **[CONTRIBUTING.md](CONTRIBUTING.md)**.

## English

> **In development.** Strata already works and grows release after release. The stable release is the safest; betas (marked *Pre-release*) let you try new features early. Feedback is welcome in the **Issues** tab.

**Strata** is a seamless world map for WoW 3.3.5a. Kalimdor, the Eastern Kingdoms and Northrend are stitched into one map at their true position, with smooth zoom at the cursor and free panning. Outland has its own view. It shows your explored areas, your position and facing, and your party or raid. It uses only the maps already in your game client: no client patch, nothing server-side, any 3.3.5 server.

Download `Strata-x.y.z.zip` from **[Releases](../../releases)** (*Latest* is stable, *Pre-release* is a beta; not *Code → Download ZIP*), unzip it into `World of Warcraft/Interface/AddOns/`, and type `/strata` in game. The interface follows your client's language (English or French). Bug reports and ideas are welcome in English in the **Issues** tab.

## Retrouvez mes projets pour WotLK 3.3.5

Tous mes addons sont écrits pour le client 3.3.5a et sans dépendance. Ils fonctionnent très bien ensemble.

| Addon | Pour quoi faire | Version | Téléchargements |
|---|---|---|---|
| **[Strata](https://github.com/BellaHealFr/Strata)** | Carte du monde continue : trois continents sur une seule carte, zoom et déplacement libres, vos zones découvertes, votre groupe. | [![Version](https://img.shields.io/github/v/release/BellaHealFr/Strata?label=&color=1e90ff)](https://github.com/BellaHealFr/Strata/releases/latest) | [![Téléchargements](https://img.shields.io/github/downloads/BellaHealFr/Strata/total?label=&color=success)](https://github.com/BellaHealFr/Strata/releases) |
| **[Zénith](https://github.com/BellaHealFr/Zenith)** | Compteur de combat : dégâts, soins, boucliers, les mêmes chiffres pour tout le groupe, relecture des combats, records par boss. | [![Version](https://img.shields.io/github/v/release/BellaHealFr/Zenith?label=&color=1e90ff)](https://github.com/BellaHealFr/Zenith/releases/latest) | [![Téléchargements](https://img.shields.io/github/downloads/BellaHealFr/Zenith/total?label=&color=success)](https://github.com/BellaHealFr/Zenith/releases) |
| **[VuhPlus](https://github.com/BellaHealFr/VuhPlus)** | Cadres de raid pour soigneurs : soin au clic, dispel, débuffs de boss, rôles reconnus, recharges du raid. | [![Version](https://img.shields.io/github/v/release/BellaHealFr/VuhPlus?label=&color=1e90ff)](https://github.com/BellaHealFr/VuhPlus/releases/latest) | [![Téléchargements](https://img.shields.io/github/downloads/BellaHealFr/VuhPlus/total?label=&color=success)](https://github.com/BellaHealFr/VuhPlus/releases) |

## Licence

Copyright (C) 2026 BellaHealFr.

Strata est un logiciel libre distribué sous **GNU GPL v3** (`GPL-3.0-only`), avec des conditions supplémentaires prévues par l'article 7 de la licence. Vous pouvez l'utiliser, l'étudier, le modifier et le redistribuer. Toute version redistribuée, modifiée ou non, doit :

- rester sous la même licence, code source compris ;
- conserver la mention de l'auteur ;
- si elle est modifiée, être clairement signalée comme différente de l'original, sous **un autre nom que « Strata »** et avec un autre dossier d'installation.

Texte complet : [`LICENSE`](LICENSE). Conditions supplémentaires et éléments tiers (données d'Astrolabe) : [`NOTICE.md`](NOTICE.md).

World of Warcraft est une marque de Blizzard Entertainment. Ce projet n'est ni affilié à Blizzard Entertainment, ni approuvé par lui.

---

<div align="center">

Créé par **BellaHealFr**

*Pour tous ceux qui n'ont jamais fini d'explorer Azeroth.*

</div>
