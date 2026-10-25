-- Copyright (C) 2026 BellaHealFr. Licence GPL-3.0-only avec conditions supplémentaires
-- (mention de l'auteur, nom « Strata » réservé) : voir LICENSE et NOTICE.md.

-- Tranches de niveaux des zones en 3.3.5, par nom de fichier de carte (comme Data/Zones.lua).
-- Le client ne les donne pas : valeurs du Warcraft Wiki pour Wrath of the Lich King.
-- Sans entrée : les villes, et Reflet-de-Lune (pas de monstres à niveau).
-- [fichier] = { minimum, maximum }

local _, ns = ...

ns.Levels = {
	-- Kalimdor
	Ashenvale = { 18, 30 },
	Aszhara = { 45, 55 },
	AzuremystIsle = { 1, 10 },
	Barrens = { 10, 25 },
	BloodmystIsle = { 10, 20 },
	Darkshore = { 10, 20 },
	Desolace = { 30, 40 },
	Durotar = { 1, 10 },
	Dustwallow = { 35, 45 },
	Felwood = { 48, 55 },
	Feralas = { 40, 50 },
	Mulgore = { 1, 10 },
	Silithus = { 55, 60 },
	StonetalonMountains = { 15, 27 },
	Tanaris = { 40, 50 },
	Teldrassil = { 1, 10 },
	ThousandNeedles = { 25, 35 },
	UngoroCrater = { 48, 55 },
	Winterspring = { 55, 60 },

	-- Royaumes de l'Est
	Alterac = { 30, 40 },
	Arathi = { 30, 40 },
	Badlands = { 35, 45 },
	BlastedLands = { 45, 55 },
	BurningSteppes = { 50, 58 },
	DeadwindPass = { 55, 60 },
	DunMorogh = { 1, 10 },
	Duskwood = { 18, 30 },
	EasternPlaguelands = { 53, 60 },
	Elwynn = { 1, 10 },
	EversongWoods = { 1, 10 },
	Ghostlands = { 10, 20 },
	Hilsbrad = { 20, 30 },
	Hinterlands = { 40, 50 },
	LochModan = { 10, 20 },
	Redridge = { 15, 25 },
	SearingGorge = { 43, 50 },
	Silverpine = { 10, 20 },
	Stranglethorn = { 30, 45 },
	Sunwell = { 70, 70 },
	SwampOfSorrows = { 35, 45 },
	Tirisfal = { 1, 10 },
	WesternPlaguelands = { 51, 58 },
	Westfall = { 10, 20 },
	Wetlands = { 20, 30 },

	-- Outreterre
	BladesEdgeMountains = { 65, 68 },
	Hellfire = { 58, 63 },
	Nagrand = { 64, 67 },
	Netherstorm = { 67, 70 },
	ShadowmoonValley = { 67, 70 },
	TerokkarForest = { 62, 65 },
	Zangarmarsh = { 60, 64 },

	-- Norfendre
	BoreanTundra = { 68, 72 },
	CrystalsongForest = { 77, 80 },
	Dragonblight = { 71, 75 },
	GrizzlyHills = { 73, 75 },
	HowlingFjord = { 68, 72 },
	HrothgarsLanding = { 77, 80 },
	IcecrownGlacier = { 77, 80 },
	LakeWintergrasp = { 77, 80 },
	SholazarBasin = { 76, 78 },
	TheStormPeaks = { 77, 80 },
	ZulDrak = { 74, 77 },
}
