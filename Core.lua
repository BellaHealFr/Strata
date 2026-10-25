-- Copyright (C) 2026 BellaHealFr. Licence GPL-3.0-only avec conditions supplémentaires
-- (mention de l'auteur, nom « Strata » réservé) : voir LICENSE et NOTICE.md.

-- Strata - Carte du monde continue pour World of Warcraft 3.3.5
-- Noyau : réglages, lecture des cartes du client (zones, zones découvertes) et positions.
--
-- Deux vues : "azeroth" (Kalimdor, Royaumes de l'Est et Norfendre placés sur la carte du monde,
-- en yards du monde) et "outland" (Outreterre, en yards du continent). Les rectangles viennent de
-- Data/Zones.lua ; les noms de fichiers et les morceaux découverts viennent du client, lus en
-- parcourant les cartes avec SetMapZoom (ns.Scan).

local addonName, ns = ...
_G.Strata = ns
ns.version = "0.2.0-beta.1"

local Zones = ns.Zones

ns.VIEWS = {
	azeroth = { continents = { 1, 2, 4 }, size = Zones[0], world = "World" },
	outland = { continents = { 3 }, size = Zones[3] },
}

-- Villes : leur carte est entièrement peinte (pas de morceaux à découvrir), dessinée au-dessus des
-- zones qui les entourent.
ns.CITIES = {
	Stormwind = true, Ironforge = true, Darnassis = true, TheExodar = true,
	Ogrimmar = true, Undercity = true, ThunderBluff = true, SilvermoonCity = true,
	ShattrathCity = true, Dalaran = true,
}

local defaults = {
	fog = true,          -- dessiner le fond des zones (le brouillard des parties non découvertes)
	w = 1000, h = 700,
	views = {},          -- [vue] = { zoom, cx, cy } : la dernière vue de chaque carte
}

function ns.Print(msg)
	DEFAULT_CHAT_FRAME:AddMessage("|cffe6b85cStrata|r : " .. msg)
end

--------------------------------------------------------------------------------
-- Lecture des cartes du client

-- ns.maps[c] = { file = fichier du continent, zones = { [fichier] = zone } }
-- zone = { c, file, name, prefix, overlays = { { texture, w, h, x, y }, ... } }
ns.maps = {}

local function ReadOverlays()
	local list = {}
	for i = 1, GetNumMapOverlays() do
		local tex, w, h, x, y = GetMapOverlayInfo(i)
		if tex and tex ~= "" then
			list[#list + 1] = { tex, w, h, x, y }
		end
	end
	return list
end

-- Le préfixe des tuiles de la carte affichée, comme WorldMapFrame_Update (3.3.5).
local function TilePrefix(file)
	local level = GetCurrentMapDungeonLevel()
	if DungeonUsesTerrainMap() then
		level = level - 1
	end
	if level > 0 then
		return "Interface\\WorldMap\\" .. file .. "\\" .. file .. level .. "_"
	end
	return "Interface\\WorldMap\\" .. file .. "\\" .. file
end

local function ReadZone(c, z, name)
	SetMapZoom(c, z)
	local file = GetMapInfo()
	if not file then return end
	local zone = ns.maps[c].zones[file] or { c = c, file = file }
	zone.name = name
	zone.prefix = TilePrefix(file)
	zone.overlays = ReadOverlays()
	ns.maps[c].zones[file] = zone
	return zone
end

-- Parcourt toutes les cartes. Change la carte sélectionnée du client : seulement quand la carte
-- de Blizzard est fermée, et on revient à la zone du joueur après.
function ns.Scan()
	if WorldMapFrame:IsShown() then return false end
	-- Chronométrée à chaque fois (un seul appel, une fois par session) : /strata bench l'affiche (#8).
	local start = debugprofilestop()
	for c in pairs(Zones) do
		if c > 0 then
			SetMapZoom(c)
			ns.maps[c] = ns.maps[c] or { zones = {} }
			ns.maps[c].file = GetMapInfo()
			local names = { GetMapZones(c) }
			for z = 1, #names do
				ReadZone(c, z, names[z])
			end
		end
	end
	SetMapToCurrentZone()
	ns.scanned = true
	ns.scanMs = debugprofilestop() - start
	return true
end

-- Relit les morceaux découverts de la zone du joueur (après avoir exploré).
function ns.RescanCurrent()
	if WorldMapFrame:IsShown() or not ns.scanned then return end
	SetMapToCurrentZone()
	local c, z = GetCurrentMapContinent(), GetCurrentMapZone()
	if ns.maps[c] and z > 0 then
		local names = { GetMapZones(c) }
		local zone = ReadZone(c, z, names[z])
		SetMapToCurrentZone()
		return zone
	end
end

--------------------------------------------------------------------------------
-- Positions

-- Convertit une position (0-1) sur une carte du client en (vue, x, y) en yards de la vue.
function ns.ToView(c, file, x, y, isContinent)
	local C = Zones[c]
	if not C or c == 0 then return end
	local cx, cy
	if isContinent then
		cx, cy = x * C.w, y * C.h
	else
		local Z = C.zones[file]
		if not Z then return end
		cx, cy = Z[3] + x * Z[1], Z[4] + y * Z[2]
	end
	if C.parent == 0 then
		return "azeroth", cx + C.x, cy + C.y
	end
	return "outland", cx, cy
end

-- La carte sélectionnée du client (celle par rapport à laquelle GetPlayerMapPosition répond).
local function CurrentMap()
	local c = GetCurrentMapContinent()
	return c, GetMapInfo(), GetCurrentMapZone() == 0
end

-- Position d'une unité sur la carte sélectionnée, convertie dans une vue ; nil si inconnue
-- (instance, autre zone, carte du monde affichée).
function ns.UnitPos(unit)
	local x, y = GetPlayerMapPosition(unit)
	if not x or (x == 0 and y == 0) then return end
	local c, file, isContinent = CurrentMap()
	return ns.ToView(c, file, x, y, isContinent)
end

-- La zone (dessinée) sous un point d'une vue : la plus petite qui le contient.
--
-- Appelée deux fois toutes les 30 ms (survol et joueur) : au lieu de parcourir toutes les zones,
-- une grille de GRID x GRID cases sur l'étendue des zones donne, pour chaque case, les zones qui
-- la touchent, de la plus petite à la plus grande. La première qui contient le point est la bonne.
local GRID = 32
local grids = {}
local EMPTY = {}

local function BuildGrid(view)
	local list = {}
	local minX, minY, maxX, maxY = math.huge, math.huge, -math.huge, -math.huge
	for _, c in ipairs(ns.VIEWS[view].continents) do
		local C = Zones[c]
		local ox, oy = 0, 0
		if C.parent == 0 then ox, oy = C.x, C.y end
		for file, Z in pairs(C.zones) do
			if not Z[5] then
				local z = { c = c, file = file, x = ox + Z[3], y = oy + Z[4], w = Z[1], h = Z[2] }
				list[#list + 1] = z
				minX, minY = math.min(minX, z.x), math.min(minY, z.y)
				maxX, maxY = math.max(maxX, z.x + z.w), math.max(maxY, z.y + z.h)
			end
		end
	end
	sort(list, function(a, b) return a.w * a.h < b.w * b.h end)

	local g = { x = minX, y = minY, cw = (maxX - minX) / GRID, ch = (maxY - minY) / GRID, cells = {} }
	local function cell(v, origin, size)
		return math.max(0, math.min(GRID - 1, floor((v - origin) / size)))
	end
	for _, z in ipairs(list) do
		for gy = cell(z.y, g.y, g.ch), cell(z.y + z.h, g.y, g.ch) do
			for gx = cell(z.x, g.x, g.cw), cell(z.x + z.w, g.x, g.cw) do
				local i = gy * GRID + gx
				local zones = g.cells[i] or {}
				zones[#zones + 1] = z
				g.cells[i] = zones
			end
		end
	end
	grids[view] = g
	return g
end

function ns.ZoneAt(view, x, y)
	local g = grids[view] or BuildGrid(view)
	local gx, gy = floor((x - g.x) / g.cw), floor((y - g.y) / g.ch)
	if gx < 0 or gx >= GRID or gy < 0 or gy >= GRID then
		-- Bord exact de l'étendue : la dernière case le contient encore.
		if x == g.x + GRID * g.cw then gx = GRID - 1 end
		if y == g.y + GRID * g.ch then gy = GRID - 1 end
		if gx < 0 or gx >= GRID or gy < 0 or gy >= GRID then return end
	end
	for _, z in ipairs(g.cells[gy * GRID + gx] or EMPTY) do
		local zx, zy = (x - z.x) / z.w, (y - z.y) / z.h
		if zx >= 0 and zx <= 1 and zy >= 0 and zy <= 1 then
			local m = ns.maps[z.c]
			local info = m and m.zones[z.file]
			return info and info.name or z.file, zx, zy
		end
	end
end

--------------------------------------------------------------------------------
-- Démarrage, événements, commandes

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("ZONE_CHANGED_NEW_AREA")
events:SetScript("OnEvent", function(self, event, arg1)
	if event == "ADDON_LOADED" and arg1 == addonName then
		StrataDB = StrataDB or {}
		for k, v in pairs(defaults) do
			if StrataDB[k] == nil then StrataDB[k] = v end
		end
		ns.db = StrataDB
	elseif event == "ZONE_CHANGED_NEW_AREA" then
		if not WorldMapFrame:IsShown() then
			SetMapToCurrentZone()
		end
		if ns.OnZoneChanged then ns.OnZoneChanged() end
	end
end)

local L = ns.L

BINDING_HEADER_STRATA = "Strata"
BINDING_NAME_STRATA_TOGGLE = L.BINDING_TOGGLE

function Strata_Toggle()
	ns.Toggle()
end

SLASH_STRATA1 = "/strata"
SLASH_STRATA2 = "/str"
SlashCmdList.STRATA = function(msg)
	msg = strlower(strtrim(msg or ""))
	if msg == "fog" or msg == "brouillard" then
		ns.db.fog = not ns.db.fog
		ns.Print(ns.db.fog and L.FOG_SHOWN or L.FOG_HIDDEN)
		if ns.Refresh then ns.Refresh() end
	elseif msg == "scan" then
		ns.Print(ns.Scan() and L.SCANNED or L.CLOSE_WORLDMAP)
		if ns.Rebuild then ns.Rebuild() end
	elseif msg == "bouton" or msg == "button" then
		ns.ToggleMinimapButton()
	elseif msg == "bench" then
		ns.Bench()
	elseif msg == "debug" or msg == "compteur" then
		ns.ToggleDebug()
	elseif msg == "reset" then
		ns.db.views = {}
		ns.db.point = nil
		ns.Print(L.RESET)
	elseif msg == "help" or msg == "aide" then
		ns.Print(ns.version .. " - " .. L.CREATED_BY)
		for _, line in ipairs(L.HELP) do ns.Print(line) end
	else
		ns.Toggle()
	end
end
