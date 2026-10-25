# Test en jeu : Strata X.Y.Z

<!--
Copier ce fichier en docs/tests-en-jeu/X.Y.Z.md avant de publier la version X.Y.Z.
Toutes les cases doivent être cochées, et le fichier doit finir par « Résultat : validé » :
la publication refuse l'étiquette vX.Y.Z sinon (docs/SUIVI.md, section 7).
Un point qui échoue : ouvrir un ticket `bug`, le corriger, refaire le point.
-->

Date :
Commit testé :

## Clients

| Serveur | Langue | Autres addons chargés |
|---|---|---|
| | frFR | |
| | enUS | |

- [ ] Testé sur au moins un serveur ; chaque serveur essayé est noté dans le tableau
- [ ] Langue anglaise couverte : banc vert en enUS, et client enUS essayé si possible (noté ci-dessus)

## Erreurs

- [ ] `/console scriptErrors 1` activé pendant tout le test
- [ ] Aucune erreur Lua de Strata, à l'ouverture comme à l'usage
- [ ] Aucune erreur d'un autre addon déclenchée par Strata (Questie, Mapster, Magnify, TomTom, ElvUI)

## Fonctions de base

- [ ] `/strata` ouvre et ferme la carte ; Échap la ferme ; le raccourci clavier fonctionne
- [ ] À l'ouverture, la carte est centrée sur le joueur ; la flèche suit sa direction
- [ ] Les membres du groupe et du raid apparaissent au bon endroit, aux couleurs de leur classe
- [ ] Survol : nom de zone et coordonnées identiques à la carte de Blizzard (vérifier 3 points)
- [ ] Zoom à la molette sous le curseur, déplacement, dézoom au clic droit
- [ ] Vue Outreterre, bouton Moi, bouton Brouillard
- [ ] Taille, position et dernière vue retenues après `/reload`
- [ ] Une zone tout juste découverte apparaît à la réouverture de la carte

## Fonctions de la version

<!-- Une ligne par ticket du jalon, et chaque ticket marqué « à vérifier en jeu ». -->

- [ ] #… :

## Rendu

- [ ] Pas de joint visible entre les tuiles d'une même zone, à plusieurs zooms
- [ ] Villes au-dessus de leurs voisines (Hurlevent, Orgrimmar, Dalaran)
- [ ] Transition propre entre deux continents au centre de la vue
- [ ] Captures jointes ci-dessous

## Performances en jeu

<!-- À partir de la 0.2 : résultats de /strata bench, objectifs dans docs/FEUILLE-DE-ROUTE.md. -->

| Mesure | Résultat | Objectif |
|---|---|---|
| Images par seconde carte fermée / ouverte | | au plus 10 % de moins |
| Temps de Strata par image en déplacement (moyenne / pire) | | sous 1 ms / 5 ms |
| Textures chargées au plus fort | | sous 600 |
| Mémoire Lua de l'addon après un tour d'Azeroth (si le client la donne) | | sous 2 Mo |

- [ ] Objectifs tenus, ou écart expliqué et ticket ouvert
- [ ] Aucune saccade visible à la première ouverture ni en déplacement

## Captures

## Remarques

Résultat : à compléter
