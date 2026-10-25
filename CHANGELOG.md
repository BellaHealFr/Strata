# Historique des versions

## Non publié

### Ajouts
- **`/strata bench`** : un parcours de mesure d'environ 25 secondes en six phases (carte fermée, immobile, déplacement, zoom, tour d'Azeroth, dézoomé). Pour chaque phase : images par seconde, temps de Strata par image (moyenne et pire image), textures chargées au plus fort. Puis la mémoire Lua de l'addon, et la comparaison avec les objectifs de performance. Résultats dans une fenêtre où l'on peut copier le texte, et enregistrés. La vue d'avant la mesure est rétablie ; `/strata bench` pendant la mesure l'arrête.
- **`/strata debug`** : un compteur dans le coin de la carte (images par seconde, temps de Strata par image, mise à jour des couches, textures et zones chargées, mémoire Lua).

### Corrections
- `/strata bench` : une mémoire d'addon relevée à 0 (renvoyée ainsi par certains clients) n'est plus annoncée « ok » ; elle est indiquée « indisponible » et « à revoir ». La mémoire Lua totale du jeu est ajoutée comme repère, ainsi qu'un objectif de textures chargées au plus fort (sous 600), mesurable sur tous les clients.
- `/strata bench` : la phase « Immobile » attend 0,5 s avant de mesurer, pour ne plus compter la réouverture de la carte.

### Performances
- Après un raid, la carte immobile retrouve son coût : les icônes des membres partis étaient masquées à nouveau 33 fois par seconde (−26 % de travail par image dans le banc après un raid de 40).
- Rien n'est chronométré tant que ni le compteur ni le bench ne sont actifs.

### Suivi et vérifications
- **Budgets de performance au banc.** Le travail de chaque situation (ouverture, carte immobile, déplacement, zoom, tour d'Azeroth, raid de 40, carte fermée) est compté en instructions Lua et en appels à l'API, et comparé à un budget. Un dépassement fait échouer la vérification. Les mesures sont publiées dans le résumé de chaque vérification.
- Le banc refuse toute variable globale créée par l'addon en dehors de la liste attendue.
- La publication d'une version exige un rapport de test en jeu validé (`docs/tests-en-jeu/`).
- Cycle des tickets, définition de « terminé » et règles de vérification : `docs/SUIVI.md`. Plan des versions 0.2 à 0.5 : `docs/FEUILLE-DE-ROUTE.md`.

## 0.1.0

Première version publique.

### Ajouts
- **Une seule carte pour Azeroth.** Kalimdor, les Royaumes de l'Est et le Norfendre sont placés à leur vraie position sur la carte du monde. L'Outreterre a sa propre vue.
- **Zoom et déplacement libres.** La molette zoome à l'endroit du curseur, avec une animation. Le clic gauche glissé déplace la carte, le clic droit dézoome.
- **Les cartes du client, en couches.** La carte du monde, puis celle du continent sous le centre de la vue, puis le fond de chaque zone et vos zones découvertes, puis les villes par-dessus. Chaque couche apparaît en fondu selon le zoom.
- **Vos zones découvertes**, lues dans le jeu comme sur la carte de Blizzard. Le bouton *Brouillard* affiche ou masque le fond des zones.
- **Vous et votre groupe.** Flèche orientée pour le joueur, membres du groupe ou du raid aux couleurs de leur classe. Le bouton *Moi* recentre la carte sur vous.
- **Zone et coordonnées** sous le curseur et pour votre position.
- **Fenêtre déplaçable et redimensionnable.** La position, la taille et la dernière vue de chaque carte sont retenues. Échap ferme la carte.
- **Micro-cartes des serveurs** (grottes, zones de départ ajoutées par certains patchs) : prises en compte pour vous placer, sans être dessinées par-dessus les zones.
- Commandes `/strata` (`/str`), raccourci clavier dans le menu des raccourcis.
- Interface en français et en anglais, selon la langue du client.

### Performances
- Les zones ne chargent leurs textures que visibles et assez grandes à l'écran, et les rendent 8 secondes après avoir quitté la vue.
- Un déplacement ou un zoom ne bouge qu'un seul cadre, quel que soit le nombre de zones affichées.
