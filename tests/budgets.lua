-- Copyright (C) 2026 BellaHealFr. Licence GPL-3.0-only avec conditions supplémentaires
-- (mention de l'auteur, nom « Strata » réservé) : voir LICENSE et NOTICE.md.

-- Budgets de performance du banc (tests/perf.lua). « ops » = centaines d'instructions Lua.
--
-- Règles (docs/SUIVI.md) :
-- - un budget dépassé fait échouer la vérification : on corrige le code, pas le budget ;
-- - relever un budget demande une raison écrite dans la demande de fusion et une ligne
--   « Performances » dans CHANGELOG.md ;
-- - après une optimisation, on abaisse le budget à la nouvelle mesure (plus la marge).
--
-- Valeur de référence entre crochets : mesure de la version où le budget a été fixé.

BUDGETS = {
	-- Ouverture : lecture des 73 zones et des 4 continents, canevas, centrage. [0.1.0]
	-- [0.2, #45] 529 → 635 : un cadre par profondeur de zones (7 au plus), et leur calcul, pour
	-- que le fond d'une zone passe toujours au-dessus des plus grandes qu'elle touche.
	["ouverture.ops"] = 700,                            -- [635]
	["ouverture.SetMapZoom"] = 80,                      -- [77] une fois par carte, pas plus
	["ouverture.CreateTexture"] = 64,                   -- [50]

	-- Carte ouverte, immobile : seules les icônes vivent. [0.1.0]
	["immobile.ops par image"] = 10,                   -- [7.6] index spatial (#6) ; 13.1 en 0.1.0
	["immobile.SetTexture par image"] = 0,              -- [0] rien ne se charge à l'arrêt
	["immobile.SetMapToCurrentZone par image"] = 0,     -- [0] la carte du client n'est pas touchée

	-- Déplacement à la souris. [0.1.0]
	["déplacement.ops par image (moyenne)"] = 91,      -- [72.7]
	["déplacement.ops par image (pire)"] = 443,        -- [354] image où des zones se chargent
	["déplacement.SetScale par image"] = 1,             -- [1] un seul cadre bougé, toujours

	-- Zoom animé. [0.1.0]
	["zoom.ops par image (moyenne)"] = 24,             -- [18.8]
	["zoom.ops par image (pire)"] = 288,               -- [230]

	-- Tour d'Azeroth : mémoire. [0.2, #22] 1 091 et 800 en 0.1.0 : textures des zones cachées
	-- plafonnées (MAX_HIDDEN), rendues à la fermeture et au changement de vue.
	["tour.textures chargées (pire moment)"] = 485,     -- [387]
	-- [0.2, #45] 108 → 160 : une texture rendue ne sert plus qu'à une zone de même profondeur.
	-- Objets vides réutilisés, pas des fichiers : les textures chargées ne bougent pas.
	["tour.CreateTexture"] = 180,                       -- [160] textures réutilisées, pas recréées
	["tour.textures chargées après 20 s"] = 64,         -- [51] tout ce qui est hors vue est rendu

	-- Raid de 40. [0.1.0]
	["raid 40.ops par image"] = 112,                   -- [89.5]
	["raid 40.GetPlayerMapPosition par image"] = 21,    -- [20]
	-- [0.2] Régression corrigée : 18,6 en 0.1.0 (icônes de raid masquées en boucle).
	["après raid.ops par image"] = 10,                 -- [7.7]

	-- Recherche de zone (#6) [0.2] : 1 300 et 20.7 avant l'index spatial.
	["ZoneAt.ops pour 100 appels"] = 130,               -- [104]
	["survol.ops par image"] = 11,                      -- [8.4]

	-- Recherche (#1) [0.2] : construction de l'index comprise dans la première frappe.
	["recherche.ops par frappe"] = 42,                  -- [33.4]

	-- Épingles (#2) [0.2] : posées sur le canevas, un déplacement ne touche aucune épingle.
	["200 épingles.affichage (changement de vue)"] = 1260, -- [1008]
	["200 épingles.immobile.ops par image"] = 10,        -- [7.8] comme sans épingle
	["200 épingles.déplacement.ops par image (moyenne)"] = 26, -- [20.3]
	["200 épingles.déplacement.SetPoint par image"] = 2, -- [2] le canevas et la flèche, aucune épingle
	["200 épingles.zoom.ops par image (moyenne)"] = 40,  -- [31.4] redimensionnées au zoom seulement

	-- Flèche de guidage (#38) [0.2] : seulement pendant un guidage ; arrêtée, plus rien ne tourne.
	["guidage.ops par image (carte fermée)"] = 8,       -- [6.4]

	-- Compteur à l'écran (/strata debug). [0.2]
	["compteur affiché.ops par image"] = 11,           -- [8.5]
	["compteur affiché.UpdateAddOnMemoryUsage en 3 s"] = 2, -- [2] une lecture toutes les 2 s, pas plus
	["compteur masqué.ops par image"] = 10,            -- [7.7] masqué, il ne coûte plus rien

	-- Mémoire des vues et de la carte fermée (#22). [0.2] Monde et continents : 4 x 12 tuiles.
	["vue Outreterre.textures gardées pour Azeroth"] = 48,
	["fermée.tuiles de carte chargées"] = 60,             -- [60] Azeroth 48 + Outreterre 12
	-- Réouverture : les zones visibles se rechargent, une fois (#22). [0.2]
	["réouverture.ops"] = 1350,                         -- [1084]
	["réouverture.SetTexture"] = 260,                   -- [208]

	-- Carte fermée. [0.1.0] Le résiduel vient de la boucle du banc lui-même.
	["fermée.ops par image"] = 1,                       -- [0.6]
	["fermée.ops changement de zone"] = 3,              -- [1-2]
}
