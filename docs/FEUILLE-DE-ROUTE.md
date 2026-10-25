# Feuille de route

Le plan des prochaines versions de Strata : ce qui entre dans chacune, dans quel ordre, et à quelles conditions elle peut sortir. Chaque ligne renvoie à son ticket, où se fait le suivi. Les règles de vérification sont dans [SUIVI.md](SUIVI.md).

L'objectif à terme : retrouver dans le client 3.3.5 ce qu'OpenMap fait dans WoW Forever, avec le même soin et des performances mesurées. Le tableau de [correspondance avec OpenMap](#correspondance-avec-openmap) suit cet objectif fonction par fonction.

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

Mesurés avec `/strata bench` à chaque test en jeu. Premier bench en jeu (Way of Elendil, 0.2 en cours) : −3 % d'images par seconde carte ouverte, 0,02 ms par image en moyenne. Ces valeurs ne peuvent que baisser ; les objectifs seront resserrés quand #22 sera terminé.

| Mesure | Objectif |
|---|---|
| Images par seconde, carte ouverte et immobile, comparées à carte fermée | au plus 10 % de moins |
| Temps de Strata par image en déplacement | moyenne sous 1 ms, pire image sous 5 ms |
| Textures chargées au plus fort pendant le bench | sous 600 (#22) ; 1 392 au premier bench en jeu |
| Mémoire Lua de l'addon après un tour d'Azeroth | sous 2 Mo, quand le client la donne (certains renvoient 0 pour tous les addons, #27) |
| Carte fermée | aucun coût mesurable |

Côté banc, les budgets déterministes de `tests/budgets.lua` s'appliquent à chaque modification (voir [SUIVI.md](SUIVI.md#5-budgets-de-performance)).

---

## Correspondance avec OpenMap

| Fonction d'OpenMap | Strata | Ticket |
|---|---|---|
| Une carte continue, zoom et déplacement fluides | 0.1 | |
| Zones découvertes et non découvertes | 0.1 | |
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
