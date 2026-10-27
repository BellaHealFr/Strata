# Feuille de route

Le plan des prochaines versions de Strata : ce qui entre dans chacune, dans quel ordre, et à quelles conditions elle peut sortir. Chaque ligne renvoie à son ticket, où se fait le suivi. Les règles de vérification sont dans [SUIVI.md](SUIVI.md).

L'objectif à terme : retrouver dans le client 3.3.5 ce qu'OpenMap fait dans WoW Forever, avec le même soin et des performances mesurées. Le tableau de [correspondance avec OpenMap](#correspondance-avec-openmap) suit cet objectif fonction par fonction.

## Où on en est (27 octobre 2026)

- **0.2** : tout le développement est fait et fusionné dans `main` ; bêta publiée : 0.2.0-beta.1. Le test en jeu a fait apparaître des défauts de rendu de la carte assemblée, corrigés un à un (étape 4 ci-dessous, d'après OpenMap et les fichiers du client). Il reste à **les vérifier en jeu**, puis à publier la **0.2.0**.
- **0.3** : les maîtres de vol (#9) sont prêts dans une demande de fusion en brouillon ([#43](../../../pull/43)), à mettre à jour sur `main` et à fusionner juste après la sortie de la 0.2.0.

**Prochaines étapes, dans l'ordre**
1. Vérifier en jeu les corrections de rendu (#45, #47, #49, #51, #53, #55), brouillard allumé et éteint ; corriger ce qui reste. Une ligne reste à identifier au-dessus de « La Pénombre » (frontière Forêt d'Elwynn / Bois de la Pénombre).
2. Rédiger le rapport de test `docs/tests-en-jeu/0.2.0.md` : erreurs Lua, fonctions de base, groupe, survol, transition, nouveautés et bench sont déjà confirmés en jeu ; le rendu (#7) attend l'étape 1.
3. Publier la **0.2.0** (numéro, CHANGELOG regroupé depuis la 0.1.0, étiquette `v0.2.0`), fermer #7 et le jalon 0.2.
4. Mettre à jour [#43](../../../pull/43) sur `main` et le fusionner, puis continuer la 0.3 dans l'ordre ci-dessous (route et temps de vol : #42).

## Principe d'ordre

Dans chaque version : **mesurer d'abord, optimiser ensuite, ajouter enfin.** Une fonction n'est construite que sur une base dont on connaît le coût.

---

## 0.2 · Mesurer, alléger, naviguer

**Étape 1 : se donner les moyens de mesurer**

| Ticket | Pourquoi d'abord |
|---|---|
| [#5](../../../issues/5) `/strata bench` et compteur à l'écran | Le test en jeu de chaque version s'appuie dessus pour les performances réelles (rendu, mémoire du client), que le banc ne voit pas. |
| [#7](../../../issues/7) Vérifier le rendu en jeu | Premier rapport de test en jeu, sur la 0.1.0 : il fixe la référence et fait remonter les bugs d'affichage avant d'empiler des fonctions. |

**Étape 2 : alléger**

| Ticket | Objectif chiffré |
|---|---|
| [#22](../../../issues/22) Pic de textures pendant un tour | moins de 600 textures chargées au pire moment (aujourd'hui 1 091) |
| [#6](../../../issues/6) Index spatial pour le survol | coût du survol indépendant du nombre de zones ; nouvelle mesure « survol » au banc |
| [#8](../../../issues/8) Saccade à la première ouverture | lecture étalée ou isolée ; budget `ouverture` tenu, aucune saccade visible en jeu avec Questie et Mapster |

**Étape 3 : naviguer**

| Ticket | Note |
|---|---|
| [#21](../../../issues/21) Bouton de la minicarte | coût nul carte fermée (budget `fermée` inchangé) |
| [#38](../../../issues/38) Flèche de guidage propre à Strata | ajouté en cours de 0.2 ; aucun coût hors guidage |
| [#1](../../../issues/1) Recherche de zones et de villes | |
| [#2](../../../issues/2) Épingles, note, couleur, TomTom | mesure « 200 épingles affichées » au banc |
| [#3](../../../issues/3) Niveau des zones au survol | |
| [#4](../../../issues/4) Plein écran | |

**Étape 4 : le rendu de la carte assemblée** (ajoutée pendant le test en jeu)

Les cartes de Blizzard sont faites pour être vues seules : chaque carte de zone, de ville, de continent et du monde est un rectangle opaque qui porte un cadre (bord de parchemin, ornements, blasons) et peint ce qui l'entoure. Assemblées, elles se recouvrent. OpenMap règle cela avec des masques, absents de la 3.3.5 ; Strata s'en approche avec des dégradés de transparence et les données du client.

| Ticket | Correction | État |
|---|---|---|
| [#45](../../../issues/45) | Tuiles accrochées les unes aux autres ; zones empilées par taille ; villes au-delà d'un cinquième de la vue | à vérifier en jeu |
| [#47](../../../issues/47) | Bord adouci des fonds (dégradé) ; centrage d'une petite zone au zoom maximal | à vérifier en jeu |
| [#49](../../../issues/49) | Bord adouci des cartes de continent | à vérifier en jeu |
| [#51](../../../issues/51) | Cadre de la carte effacé des morceaux découverts (vérifié sur les fichiers du client) | à vérifier en jeu |
| [#53](../../../issues/53) | « Brouillard : non » révèle toute la carte (`Data/Overlays.lua`, 886 morceaux) ; mer au-delà du monde | à vérifier en jeu |
| [#55](../../../issues/55) | Fonds limités au territoire : zones au rectangle de leurs morceaux, villes à leur plan | à vérifier en jeu |

Limites connues, faute de masques : les coins d'une zone (entre son territoire et son rectangle) gardent un peu de la peinture des voisines ; le totem des Pitons-du-Tonnerre et l'emblème d'Orgrimmar touchent le plan de la ville ; les noms des mers et des continents restent ceux de la carte de Blizzard (#20).

**Critères de sortie**
- Pic de textures du tour d'Azeroth sous 600, budgets `tour.*` abaissés.
- Premiers objectifs de performance en jeu mesurés avec `/strata bench` et inscrits ci-dessous.
- Aucun ticket `bloquant` ou `régression` ouvert, rapport de test en jeu validé ([SUIVI.md](SUIVI.md#8-sortie-dune-version)).

---

## 0.3 · Le contenu du monde

| Ordre | Ticket | Note |
|---|---|---|
| 1 | [#9](../../../issues/9) Maîtres de vol, appris et inconnus, route et temps | le plus gros chantier de données ; pose le système d'icônes de la carte |
| 2 | [#11](../../../issues/11) Entrées de donjons et de raids | réutilise les icônes de #9 |
| 3 | [#10](../../../issues/10) Routes des bateaux et zeppelins | introduit le tracé de lignes (repris par la plume en 0.4) |
| 4 | [#12](../../../issues/12) PNJ utiles (avec Questie) | données chargées seulement à l'activation |
| 5 | [#13](../../../issues/13) Objectifs de quêtes | |

**Performances à tenir** : nouvelle mesure « 300 icônes affichées » (immobile et en déplacement) ; données des PNJ jamais lues si l'option est coupée (budget mémoire carte fermée inchangé).

**Critères de sortie** : ceux de [SUIVI.md](SUIVI.md#8-sortie-dune-version), plus une vérification en jeu des positions de chaque maître de vol et de chaque entrée de donjon (liste cochée dans le rapport).

---

## 0.4 · Annoter et partager

| Ordre | Ticket | Note |
|---|---|---|
| 1 | [#16](../../../issues/16) Menu et options | d'abord : les fonctions suivantes y rangent leurs réglages |
| 2 | [#14](../../../issues/14) Plume | mesure « 1 000 segments dessinés » au banc |
| 3 | [#15](../../../issues/15) Partage d'épingles | messages limités en taille et en fréquence ; demande de confirmation |
| 4 | [#17](../../../issues/17) Fenêtre des nouveautés | |

---

## 0.5 · La finition de la carte

| Ordre | Ticket | Note |
|---|---|---|
| 1 | [#20](../../../issues/20) Noms des mers et des continents | |
| 2 | [#18](../../../issues/18) Zoom au niveau de la minicarte | au plus quelques dizaines de tuiles chargées autour de la vue |
| 3 | [#19](../../../issues/19) Fondu entre zones pré-assemblé | **point de décision** : prototype sur un continent, puis poids de l'addon et mémoire mesurés avant de généraliser |

---

## Objectifs de performance en jeu

Mesurés avec `/strata bench` à chaque test en jeu. Dernier bench en jeu (Way of Elendil, 25 octobre, avant l'étape 4) : 175 à 190 images par seconde, carte ouverte comprise (+8 %) ; 0,01 ms de Strata par image en moyenne, 0,14 ms au pire en déplacement ; 456 textures au plus fort (1 392 au premier bench) ; lecture des cartes à la première ouverture en 11,5 ms. L'étape 4 découpe les cartes en plus de pièces (sans fichier de plus) : à remesurer au prochain test en jeu.

| Mesure | Objectif |
|---|---|
| Images par seconde, carte ouverte et immobile, comparées à carte fermée | au plus 10 % de moins |
| Temps de Strata par image en déplacement | moyenne sous 1 ms, pire image sous 5 ms |
| Fichiers de textures chargés au plus fort pendant le bench | sous 600 (#22) ; 456 au dernier bench en jeu |
| Mémoire Lua de l'addon après un tour d'Azeroth | sous 2 Mo, quand le client la donne (certains renvoient 0 pour tous les addons, #27) |
| Carte fermée | aucun coût mesurable |

Côté banc, les budgets déterministes de `tests/budgets.lua` s'appliquent à chaque modification (voir [SUIVI.md](SUIVI.md#5-budgets-de-performance)).

---

## Correspondance avec OpenMap

| Fonction d'OpenMap | Strata | Ticket |
|---|---|---|
| Une carte continue, zoom et déplacement fluides | 0.1 | |
| Zones découvertes et non découvertes | 0.1 | |
| Carte révélée (brouillard éteint) | 0.2 | [#53](../../../issues/53) |
| Bords fondus entre zones, cadres effacés, mer au-delà du monde | 0.2 (dégradés, sans masques) | [#45](../../../issues/45) à [#55](../../../issues/55) |
| Joueur et groupe sur toute la carte | 0.1 | |
| Coordonnées et survol | 0.1 | |
| Fenêtre déplaçable, redimensionnable, retenue | 0.1 | |
| Mesure des performances (bench, compteur) | 0.2 | [#5](../../../issues/5) |
| Plein écran | 0.2 | [#4](../../../issues/4) |
| Recherche (zones, villes, puis donjons et vols) | 0.2, 0.3 | [#1](../../../issues/1) |
| Épingles, note, couleur, flèche TomTom | 0.2 | [#2](../../../issues/2) |
| Point suivi et flèche de guidage (sans TomTom) | 0.2 | [#38](../../../issues/38) |
| Niveaux des zones au survol | 0.2 | [#3](../../../issues/3) |
| Accès rapide (bouton de minicarte) | 0.2 | [#21](../../../issues/21) |
| Maîtres de vol, route et temps de vol | 0.3 | [#9](../../../issues/9) |
| Bateaux et zeppelins | 0.3 (lignes entre les quais) | [#10](../../../issues/10) |
| Entrées de donjons et de raids | 0.3 | [#11](../../../issues/11) |
| PNJ utiles (avec Questie) | 0.3 | [#12](../../../issues/12) |
| Objectifs de quêtes | 0.3 | [#13](../../../issues/13) |
| Plume | 0.4 | [#14](../../../issues/14) |
| Partage d'épingles | 0.4 | [#15](../../../issues/15) |
| Menu, options, favoris | 0.4 | [#16](../../../issues/16) |
| Nouveautés | 0.4 | [#17](../../../issues/17) |
| Noms des mers et continents redessinés | 0.5 | [#20](../../../issues/20) |
| Zoom minicarte | 0.5 | [#18](../../../issues/18) |
| Fondu entre zones, bordures harmonisées | 0.5 (pré-assemblé) | [#19](../../../issues/19) |
| Carte du donjon au clic, liste des boss | à étudier après 0.5 : pas de guide des donjons en 3.3.5 | |
| Remplissage par d'anciennes cartes | impossible : absentes du client 3.3.5 | |
| Manette | impossible : absente de la 3.3.5 | |
