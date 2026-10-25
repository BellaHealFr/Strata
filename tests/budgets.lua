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
	["ouverture.ops"] = 600,                            -- [474]
	["ouverture.SetMapZoom"] = 80,                      -- [77] une fois par carte, pas plus
	["ouverture.CreateTexture"] = 64,                   -- [50]

	-- Carte ouverte, immobile : seules les icônes vivent. [0.1.0]
	["immobile.ops par image"] = 17,                    -- [13.1]
	["immobile.SetTexture par image"] = 0,              -- [0] rien ne se charge à l'arrêt
	["immobile.SetMapToCurrentZone par image"] = 0,     -- [0] la carte du client n'est pas touchée

	-- Déplacement à la souris. [0.1.0]
	["déplacement.ops par image (moyenne)"] = 98,       -- [78.2]
	["déplacement.ops par image (pire)"] = 455,         -- [364] image où des zones se chargent
	["déplacement.SetScale par image"] = 1,             -- [1] un seul cadre bougé, toujours

	-- Zoom animé. [0.1.0]
	["zoom.ops par image (moyenne)"] = 31,              -- [24.4]
	["zoom.ops par image (pire)"] = 300,                -- [241]

	-- Tour d'Azeroth : mémoire. [0.1.0] Objectif 0.2 : moins de 600 au pire moment.
	["tour.textures chargées (pire moment)"] = 1150,    -- [1091]
	["tour.CreateTexture"] = 850,                       -- [800] textures réutilisées, pas recréées
	["tour.textures chargées après 20 s"] = 64,         -- [51] tout ce qui est hors vue est rendu

	-- Raid de 40. [0.1.0]
	["raid 40.ops par image"] = 119,                    -- [95.2]
	["raid 40.GetPlayerMapPosition par image"] = 21,    -- [20]

	-- Carte fermée. [0.1.0] Le résiduel vient de la boucle du banc lui-même.
	["fermée.ops par image"] = 1,                       -- [0.6]
	["fermée.ops changement de zone"] = 3,              -- [1-2]
}
