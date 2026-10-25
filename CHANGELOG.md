# Historique des versions

## Non publié

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
