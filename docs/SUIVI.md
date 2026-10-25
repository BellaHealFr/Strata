# Suivi du projet et vérifications obligatoires

Ce document fixe la façon dont Strata avance : comment une idée devient une version publiée, et ce qui doit être vérifié avant. Il vaut pour toutes les modifications, y compris celles de l'auteur.

Le principe : **rien n'entre dans `main` sans vérification automatique verte, et rien n'est publié sans test en jeu.** Les deux sont imposés par GitHub, pas seulement recommandés.

## Sommaire

1. [Les outils du suivi](#1-les-outils-du-suivi)
2. [Le cycle d'un ticket](#2-le-cycle-dun-ticket)
3. [Définition de « terminé »](#3-définition-de-terminé)
4. [Vérifications automatiques](#4-vérifications-automatiques)
5. [Budgets de performance](#5-budgets-de-performance)
6. [Bugs](#6-bugs)
7. [Test en jeu](#7-test-en-jeu)
8. [Sortie d'une version](#8-sortie-dune-version)

---

## 1. Les outils du suivi

| Outil | Rôle |
|---|---|
| **Jalons** (*Milestones*) | Une version = un jalon. Il contient tout ce qui doit y entrer. La feuille de route détaillée est dans [FEUILLE-DE-ROUTE.md](FEUILLE-DE-ROUTE.md). |
| **Tickets** (*Issues*) | Une fonction, un bug ou une tâche = un ticket, rattaché à son jalon. |
| **Étiquettes** | Le type (`bug`, `enhancement`), le domaine (`assemblage`, `positions`, `performances`, `interface`, `données`, `traduction`) et l'état (`bloquant`, `régression`, `à vérifier en jeu`). |
| **Demandes de fusion** (*Pull Requests*) | Toute modification passe par une branche et une demande de fusion, avec la liste de vérifications. |
| **Branche `main` protégée** | Fusion impossible sans vérification automatique verte. Pas d'envoi direct, même pour l'auteur. |
| **CHANGELOG.md** | La section « Non publié » se remplit à chaque fusion. Elle devient la section de la version à sa sortie. |
| **Rapports de test en jeu** | `docs/tests-en-jeu/X.Y.Z.md`, un par version, obligatoire pour publier. |

## 2. Le cycle d'un ticket

```
À faire ──► En cours ──► Demande de fusion ──► Vérification verte ──► Fusionné ──► Vérifié en jeu ──► Publié
             branche        liste cochée         automatique                       étiquette retirée    jalon
```

1. **À faire** : le ticket décrit le besoin et la piste technique. Il est rangé dans un jalon.
2. **En cours** : une branche `numéro-nom-court` (`21-bouton-minicarte`) part de `main`.
3. **Demande de fusion** : son texte contient `Closes #21` pour fermer le ticket à la fusion (GitHub ne reconnaît que les mots-clés anglais : `Closes`, `Fixes`, `Resolves`). La liste de vérifications du modèle est remplie honnêtement : une case non cochée s'explique.
4. **Vérification automatique** : elle doit être verte (voir [section 4](#4-vérifications-automatiques)). Sinon, on corrige sur la branche.
5. **Fusionné** : fusion par *squash*, pour garder un commit par ticket dans `main`. Le ticket reçoit l'étiquette `à vérifier en jeu` si le banc ne peut pas tout prouver (affichage, sensation de fluidité).
6. **Vérifié en jeu** : au test de la version (voir [section 7](#7-test-en-jeu)), l'étiquette est retirée. Un problème trouvé ouvre un nouveau ticket `bug`.

## 3. Définition de « terminé »

Une modification est terminée quand **tout** ceci est vrai :

- [ ] la vérification automatique est verte (syntaxe, `.toc`, versions, licences, banc en français et en anglais, budgets de performance, aucune variable globale en trop) ;
- [ ] la nouvelle fonction est vérifiée par le banc (`tests/scenario.lua`) ;
- [ ] si elle a un coût à l'image, en mémoire ou au chargement, une mesure et son budget sont ajoutés (`tests/perf.lua`, `tests/budgets.lua`) ;
- [ ] pour un bug, un test qui l'aurait attrapé est ajouté au banc ;
- [ ] chaque texte affiché existe en français et en anglais ;
- [ ] `CHANGELOG.md` (section « Non publié ») et, si le fonctionnement change, `docs/CONSTRUCTION.md` sont à jour ;
- [ ] elle a été essayée en jeu, sur un client 3.3.5a.

## 4. Vérifications automatiques

Lancées par GitHub à chaque envoi sur une demande de fusion et sur `main` (`.github/workflows/verification.yml`). **Bloquantes** : la protection de `main` refuse la fusion tant qu'elles ne sont pas vertes.

| Contrôle | Ce qu'il attrape |
|---|---|
| Syntaxe Lua 5.1 (`luac5.1 -p`) | une erreur de syntaxe qui empêcherait l'addon de charger |
| Fichiers du `.toc` | un fichier oublié dans le `.toc`, ou déclaré mais absent |
| Numéros de version | `Core.lua`, `Strata.toc` et `CHANGELOG.md` qui ne disent pas la même chose |
| En-têtes de licence | un fichier Lua sans l'en-tête de copyright |
| Banc : fonctions (`scenario.lua`) | une fonction cassée : ouverture, lecture des zones, positions, survol, boutons, commandes, deux langues |
| Banc : variables globales | une variable globale créée par erreur (oubli de `local`), qui peut écraser celle d'un autre addon |
| Banc : performances (`perf.lua`) | un dépassement de budget (voir ci-dessous) |

Les mesures de performance sont publiées dans le résumé de chaque vérification sur GitHub, sous forme de tableau.

Pour les lancer avant d'envoyer :

```
pip install lupa
python tests/run.py frFR
python tests/run.py enUS
```

## 5. Budgets de performance

Le banc **compte** le travail au lieu de le chronométrer : instructions Lua exécutées (par centaines) et appels à l'API du jeu. Ces chiffres sont identiques à chaque lancement, sur n'importe quelle machine. Un dépassement est donc un vrai changement du code, pas du bruit.

Situations mesurées (`tests/perf.lua`) : ouverture, carte immobile, déplacement, zoom animé, tour complet d'Azeroth (mémoire), raid de 40, carte fermée.

**Règles**

1. **Un budget dépassé fait échouer la vérification.** On corrige le code, pas le budget.
2. **Relever un budget** demande une raison écrite dans la demande de fusion (une fonction nouvelle a un coût, et ce coût est justifié), et une ligne dans la partie « Performances » du `CHANGELOG.md`.
3. **Après une optimisation**, on abaisse le budget à la nouvelle mesure, plus une marge d'environ 25 %. Les budgets ne font que descendre, sauf justification.
4. **Règles strictes**, sans marge :
   - un déplacement ou un zoom ne met à l'échelle qu'**un seul cadre** par image ;
   - carte immobile : **aucun** chargement de texture et **aucun** changement de la carte sélectionnée du client ;
   - carte fermée : pratiquement **aucun** travail.
5. Toute nouvelle fonction qui tourne à chaque image, charge des textures ou parcourt des données reçoit **sa propre mesure et son budget**. Un budget absent fait échouer le banc.

Le banc ne mesure ni le rendu ni la mémoire réelle du client. Ces deux points sont vérifiés en jeu, avec `/strata bench` (à partir de la 0.2), voir [section 7](#7-test-en-jeu).

## 6. Bugs

**Signalement** : formulaire *Signaler un problème*. Étiquette `bug`, et le domaine concerné.

**Gravité**

| Étiquette | Sens | Conséquence |
|---|---|---|
| `bloquant` | erreur Lua, addon inutilisable, perte de réglages, chute nette des images par seconde | corrigé avant tout le reste ; **aucune version ne sort avec un bug bloquant ouvert** |
| `régression` | quelque chose qui marchait dans une version précédente ne marche plus | traité comme bloquant pour la version suivante |
| *(sans)* | défaut gênant mais contournable | rangé dans le jalon le plus proche |

**Correction**

1. Reproduire le bug, en jeu ou dans le banc.
2. **Écrire d'abord le test qui échoue** dans `tests/scenario.lua` (ou une mesure dans `tests/perf.lua` pour un problème de performance).
3. Corriger jusqu'à ce que le test passe.
4. Demande de fusion avec `Closes #N`. Le test reste dans le banc pour toujours : le même bug ne peut pas revenir sans être vu.

Un bug que le banc ne peut pas reproduire (rendu, client particulier) est décrit dans le rapport de test en jeu de la version qui le corrige.

## 7. Test en jeu

Obligatoire avant chaque version : **la publication refuse une étiquette `vX.Y.Z` sans rapport validé** `docs/tests-en-jeu/X.Y.Z.md`. Le rapport part du modèle [`docs/tests-en-jeu/MODELE.md`](tests-en-jeu/MODELE.md), toutes ses cases cochées, et se termine par `Résultat : validé`.

Le protocole couvre :
- **Erreurs** : `/console scriptErrors 1`, aucune erreur Lua pendant tout le test.
- **Fonctions** : la liste de la version, plus les tickets marqués `à vérifier en jeu`.
- **Rendu** : joints, couches, villes, transitions entre continents, captures jointes.
- **Performances en jeu** (à partir de la 0.2, avec `/strata bench`) : images par seconde carte ouverte, temps de Strata par image en déplacement, mémoire de l'addon après un tour d'Azeroth. Objectifs dans [FEUILLE-DE-ROUTE.md](FEUILLE-DE-ROUTE.md#objectifs-de-performance-en-jeu).
- **Clients** : au moins deux serveurs différents, un client frFR et un client enUS.
- **Compatibilité** : avec Questie, Mapster, Magnify, TomTom et ElvUI chargés.

## 8. Sortie d'une version

Une version sort quand :

1. tous les tickets de son jalon sont fermés, ou déplacés vers le jalon suivant avec une raison ;
2. aucun ticket `bloquant` ou `régression` n'est ouvert ;
3. la vérification automatique de `main` est verte ;
4. le rapport de test en jeu est validé et fusionné.

Puis :

1. numéro de version dans `Core.lua` et `Strata.toc` ;
2. la section « Non publié » du `CHANGELOG.md` devient `## X.Y.Z` ;
3. demande de fusion « Strata X.Y.Z », fusion ;
4. étiquette `vX.Y.Z` sur `main` : la publication vérifie les numéros et le rapport de test, construit l'archive et crée la version ;
5. le jalon est fermé.

### Bêtas (pré-versions)

Entre deux versions, une bêta permet aux joueurs d'essayer ce qui est déjà fusionné.

- Numéro `X.Y.Z-beta.N` (par exemple `0.2.0-beta.1`), dans `Core.lua`, `Strata.toc` et une section `## X.Y.Z-beta.N` du `CHANGELOG.md`.
- Étiquette `vX.Y.Z-beta.N` : la publication la marque **Pre-release** sur GitHub (toute étiquette avec un tiret). La version stable reste celle proposée par défaut.
- Rapport de test en jeu **allégé**, obligatoire lui aussi : [`docs/tests-en-jeu/MODELE-BETA.md`](tests-en-jeu/MODELE-BETA.md). Un seul serveur suffit, mais aucune erreur Lua, les nouveautés de la bêta essayées et un `/strata bench`.
- Conditions : vérification de `main` verte, aucun ticket `bloquant` ou `régression` ouvert. Le jalon n'a pas besoin d'être terminé.
- Les tickets de la bêta gardent l'étiquette `à vérifier en jeu` jusqu'au rapport complet de la version finale.
