## Ce que change cette proposition

<!-- En quelques phrases : le problème ou le besoin, et la solution. -->

Ferme #

## Vérifications (docs/SUIVI.md)

Une case laissée vide s'explique sous la liste.

- [ ] Vérification automatique verte (syntaxe, `.toc`, versions, licences, banc FR/EN, budgets, variables globales)
- [ ] Nouvelle fonction vérifiée par le banc (`tests/scenario.lua`)
- [ ] Coût à l'image, en mémoire ou au chargement : mesure et budget ajoutés (`tests/perf.lua`, `tests/budgets.lua`)
- [ ] Bug : un test qui l'aurait attrapé est ajouté au banc
- [ ] Aucun budget relevé, ou raison écrite ci-dessous et ligne « Performances » dans `CHANGELOG.md`
- [ ] Aucune fonction absente de l'API 3.3.5 (`C_Map`, `C_Timer`, `CreateMaskTexture`, `SetMapByID`…)
- [ ] Chaque texte affiché existe en français **et** en anglais (`Locale.lua`)
- [ ] Essayé en jeu sur un client **3.3.5a** (sinon : étiquette `à vérifier en jeu` sur le ticket)
- [ ] `CHANGELOG.md` (« Non publié ») et, si besoin, `docs/CONSTRUCTION.md` à jour

## Budgets de performance

<!-- Mesures qui changent (le tableau est dans le résumé de la vérification) ; raison si un budget monte. -->

En proposant cette contribution, j'accepte qu'elle soit publiée sous la licence du projet (GPL-3.0 avec les conditions de `NOTICE.md`).
