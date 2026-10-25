# Contribuer à Strata

Merci de vouloir améliorer Strata ! Que vous soyez joueur ou développeur, il y a une place pour vous.

## Signaler un problème ou proposer une idée

Ouvrez un ticket dans l'onglet **Issues** et choisissez le formulaire :
- **Signaler un problème** : erreur Lua, zone mal placée, joint visible entre deux zones, saccade ;
- **Proposer une idée** : nouvelle fonction, amélioration de l'interface.

Pour un problème d'affichage, le plus utile est une **capture d'écran** avec la commande `/strata` ouverte, en indiquant la zone et le serveur. Pour une saccade, joignez la liste de vos addons de carte (Mapster, Magnify, Questie…).

Avant d'ouvrir un ticket, vérifiez qu'il n'existe pas déjà. Les fonctions prévues sont rangées par version dans les **jalons** (*Milestones*).

## Proposer une modification du code

1. **Discutez-en d'abord** dans un ticket si la modification est importante : cela évite de travailler pour rien.
2. Créez une copie du dépôt (*Fork*), puis une branche au nom parlant (`recherche-zones`, `correction-joints`…).
3. Lisez **[docs/SUIVI.md](docs/SUIVI.md)**, qui fixe le cycle d'un ticket et les vérifications obligatoires, puis **[docs/CONSTRUCTION.md](docs/CONSTRUCTION.md)**, qui explique le fonctionnement complet. Sa section [Contribuer](docs/CONSTRUCTION.md#contribuer) donne les règles :
   - Lua 5.1 et API 3.3.5 uniquement ;
   - aucune bibliothèque embarquée ;
   - chaque texte affiché en français **et** en anglais (`Locale.lua`) ;
   - rien qui charge des textures hors de la vue.
4. **Testez en jeu** sur un client 3.3.5a, et passez le banc de simulation :
   ```
   pip install lupa
   python tests/run.py frFR
   python tests/run.py enUS
   ```
5. Ouvrez une demande de fusion (*Pull Request*) et remplissez la liste de vérifications.

La vérification automatique (syntaxe Lua 5.1, fichiers du `.toc`, numéros de version, en-têtes de licence, banc de simulation, budgets de performance) doit être verte : la branche `main` refuse la fusion sinon. Un budget dépassé se corrige dans le code ; le relever demande une raison écrite (voir [docs/SUIVI.md](docs/SUIVI.md#5-budgets-de-performance)).

## Style

- Une tabulation pour l'indentation des fichiers Lua.
- Commentaires en français, qui expliquent **pourquoi** plutôt que **quoi**.
- Messages de commit courts, en français, à l'infinitif : « Ajouter la recherche de zones », « Corriger le joint entre Elwynn et la Marche de l'Ouest ».

## Licence des contributions

Strata est publié sous **GPL-3.0** avec les conditions supplémentaires de [`NOTICE.md`](NOTICE.md). Toute contribution est publiée sous cette même licence. Vous restez l'auteur de votre contribution, et votre nom apparaît dans l'historique du dépôt.
