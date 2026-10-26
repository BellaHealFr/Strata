# Avis de droit d'auteur et de licence

**Strata**, carte du monde continue pour World of Warcraft 3.3.5
Copyright (C) 2026 BellaHealFr

Ce programme est un logiciel libre : vous pouvez le redistribuer et le modifier selon les termes de la **GNU General Public License, version 3** (GPL-3.0-only), publiée par la Free Software Foundation, complétée par les conditions supplémentaires ci-dessous (article 7 de la licence).

Ce programme est distribué dans l'espoir qu'il sera utile, mais **sans aucune garantie**, ni explicite ni implicite, y compris de qualité marchande ou d'adéquation à un usage particulier. Voir le texte de la licence dans le fichier [`LICENSE`](LICENSE).

## Conditions supplémentaires (article 7 de la GPL-3.0)

1. **Mention de l'auteur** *(art. 7 b)* : toute copie ou version modifiée doit conserver la mention « Copyright (C) 2026 BellaHealFr », le présent avis et la mention « Créé par BellaHealFr » affichée dans l'infobulle de la barre de titre de la carte.
2. **Origine des versions modifiées** *(art. 7 c)* : une version modifiée ne doit pas être présentée comme la version originale. Elle doit être clairement signalée comme différente, dans sa description, dans son fichier `.toc` (titre et auteur) et dans l'interface.
3. **Nom de l'auteur** *(art. 7 d)* : le nom de l'auteur ne peut pas être utilisé pour promouvoir une version modifiée sans son accord écrit.
4. **Nom « Strata »** *(art. 7 e)* : la licence n'accorde aucun droit sur le nom « Strata » ni sur son logo. Une version modifiée redistribuée doit porter un autre nom et un autre logo, et ne pas utiliser le dossier d'installation `Strata`. Ce nom de dossier sert de nom technique à l'addon et entrerait en conflit avec l'original.

## Éléments tiers

- `Data/Zones.lua` contient la taille et la position des continents et des zones (données factuelles du client, table `WorldMapArea`), reprises de la table `WorldMapSize` de **Astrolabe** par Esamynn (LGPL 2.1). Aucun code d'Astrolabe n'est inclus dans l'addon. Le fichier de référence `tools/ref/Astrolabe-r107.lua`, qui sert seulement à régénérer ces données, est distribué sous sa propre licence : [`tools/ref/lgpl.txt`](tools/ref/lgpl.txt).
- `Data/Overlays.lua` contient la liste de tous les morceaux des cartes de zone (nom de texture, taille, place : données factuelles du client), lue dans la table `WorldMapOverlay` du client 3.3.5 par `tools/extract_overlays.py`. Aucune image de Blizzard n'est incluse : les textures sont celles du client du joueur.
- `Data/Levels.lua` contient les tranches de niveaux des zones (données factuelles du jeu), relevées sur le **Warcraft Wiki**.
- L'idée d'une carte du monde continue vient d'**OpenMap** pour WoW Forever (licence MIT). Strata est écrit pour l'API 3.3.5 : aucun code ni aucune image d'OpenMap n'est inclus.
- World of Warcraft est une marque de Blizzard Entertainment. Strata n'est ni affilié à Blizzard Entertainment, ni approuvé par lui. Aucun fichier du jeu n'est distribué avec l'addon : les cartes du jeu sont seulement référencées par leur chemin dans le client.

---

# Copyright and license notice (English)

**Strata**, seamless world map for World of Warcraft 3.3.5
Copyright (C) 2026 BellaHealFr

This program is free software: you can redistribute it and/or modify it under the terms of the **GNU General Public License, version 3 only** (GPL-3.0-only), as published by the Free Software Foundation, supplemented by the additional terms below (section 7 of the license).

This program is distributed in the hope that it will be useful, but **WITHOUT ANY WARRANTY**; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the [`LICENSE`](LICENSE) file for details.

## Additional terms (GPL-3.0 section 7)

1. **Author attribution** *(7 b)*: every copy or modified version must preserve the notice "Copyright (C) 2026 BellaHealFr", this notice, and the "Created by BellaHealFr" credit shown in the map's title bar tooltip.
2. **Origin of modified versions** *(7 c)*: modified versions must not be misrepresented as the original version and must be clearly marked as different, in their description, in their `.toc` file (title and author) and in their user interface.
3. **Author name** *(7 d)*: the author's name may not be used to promote a modified version without prior written permission.
4. **The name "Strata"** *(7 e)*: this license grants no rights to the name "Strata" or its logo. A redistributed modified version must use a different name and logo, and must not use the `Strata` install folder name. That folder name is the add-on's technical name and would conflict with the original.

## Third-party material

- `Data/Zones.lua` holds the size and position of continents and zones (factual client data, `WorldMapArea` table), taken from the `WorldMapSize` table of **Astrolabe** by Esamynn (LGPL 2.1). No Astrolabe code ships in the add-on. The reference file `tools/ref/Astrolabe-r107.lua`, used only to regenerate that data, is distributed under its own license: [`tools/ref/lgpl.txt`](tools/ref/lgpl.txt).
- `Data/Overlays.lua` lists every piece of the zone maps (texture name, size, position: factual client data), read from the 3.3.5 client's `WorldMapOverlay` table by `tools/extract_overlays.py`. No Blizzard image ships: the textures are the player's own client's.
- `Data/Levels.lua` holds the zones' level ranges (factual game data), taken from the **Warcraft Wiki**.
- The idea of a seamless world map comes from **OpenMap** for WoW Forever (MIT license). Strata is written for the 3.3.5 API: no OpenMap code or art is included.
- World of Warcraft is a trademark of Blizzard Entertainment. Strata is neither affiliated with nor endorsed by Blizzard Entertainment. No game file ships with the add-on: the game's maps are only referenced by their path in the client.
