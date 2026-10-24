-- Copyright (C) 2026 BellaHealFr. Licence GPL-3.0-only avec conditions supplémentaires
-- (mention de l'auteur, nom « Strata » réservé) : voir LICENSE et NOTICE.md.

-- Strata - Carte du monde continue pour World of Warcraft 3.3.5
-- Textes de l'interface : anglais par défaut, français sur un client frFR.
-- Les noms de zones ne sont pas ici : ils viennent du client (GetMapZones), déjà traduits.

local _, ns = ...

local L = {
	CREATED_BY = "Created by BellaHealFr",
	ME = "Me",
	YOU = "You",
	AZEROTH = "Azeroth",
	OUTLAND = "Outland",
	FOG_ON = "Fog: on",
	FOG_OFF = "Fog: off",
	FOG_SHOWN = "zone backgrounds shown",
	FOG_HIDDEN = "zone backgrounds hidden",
	NO_POSITION = "position unknown here (instance?)",
	SCANNED = "maps read again",
	CLOSE_WORLDMAP = "close Blizzard's world map first",
	RESET = "window and views reset (/reload for the window)",
	BINDING_TOGGLE = "Open / close the Strata map",
	HELP = {
		"/strata : open or close the map",
		"/strata fog : show or hide the zone backgrounds",
		"/strata scan : read the client's maps again",
		"/strata reset : reset the window and views",
	},
}

if GetLocale() == "frFR" then
	L = {
		CREATED_BY = "Créé par BellaHealFr",
		ME = "Moi",
		YOU = "Vous",
		AZEROTH = "Azeroth",
		OUTLAND = "Outreterre",
		FOG_ON = "Brouillard : oui",
		FOG_OFF = "Brouillard : non",
		FOG_SHOWN = "fond des zones affiché",
		FOG_HIDDEN = "fond des zones masqué",
		NO_POSITION = "position inconnue ici (instance ?)",
		SCANNED = "cartes relues",
		CLOSE_WORLDMAP = "fermez d'abord la carte de Blizzard",
		RESET = "fenêtre et vues remises à zéro (/reload pour la fenêtre)",
		BINDING_TOGGLE = "Ouvrir / fermer la carte Strata",
		HELP = {
			"/strata : ouvrir ou fermer la carte",
			"/strata brouillard : afficher ou masquer le fond des zones",
			"/strata scan : relire les cartes du client",
			"/strata reset : remettre la fenêtre et les vues à zéro",
		},
	}
end

ns.L = L
