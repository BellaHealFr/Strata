-- Copyright (C) 2026 BellaHealFr. Licence GPL-3.0-only avec conditions supplémentaires
-- (mention de l'auteur, nom « Strata » réservé) : voir LICENSE et NOTICE.md.

-- Strata - Carte du monde continue pour World of Warcraft 3.3.5
-- Maîtres de vol : ceux de la faction du joueur (et les neutres) sur la carte, vols appris en vert.
--
-- Positions : Data/FlightMasters.lua (tiré de Questie). Vols appris : relevés à chaque ouverture
-- de la carte des vols (TAXIMAP_OPENED), par personnage (StrataCharDB.flights).
--
-- La carte des vols place ses points dans son propre repère (TaxiNodePosition, 0-1 sur une carte
-- de 316 x 352 px), pas en coordonnées de zone. À chaque visite, le maître de vol où se tient le
-- joueur donne une paire (point de la carte des vols, position réelle) : dès deux paires sur un
-- continent, une correspondance linéaire par axe (moindres carrés) place tous les vols connus,
-- et chacun est rattaché au maître de vol le plus proche.

local _, ns = ...

local L = ns.L

local SIZE = 14                  -- px à l'écran
local ICON_KNOWN = "Interface\\TaxiFrame\\UI-Taxi-Icon-Green"
local ICON_OTHER = "Interface\\TaxiFrame\\UI-Taxi-Icon-White"
local HERE = 60                  -- yards : le joueur se tient au maître de vol
local MATCH = 250                -- yards : un vol connu placé par la correspondance

local canvas
local fileCont

local function Char()
	ns.char.flights = ns.char.flights or {}
	ns.char.taxiNodes = ns.char.taxiNodes or {}
	return ns.char
end

local function Calib()
	ns.db.taxiCalib = ns.db.taxiCalib or {}
	return ns.db.taxiCalib
end

local function Faction()
	return UnitFactionGroup("player") == "Horde" and "H" or "A"
end

-- Le continent d'un fichier de carte.
local function ContinentOf(file)
	if not fileCont then
		fileCont = {}
		for c, C in pairs(ns.Zones) do
			if c > 0 then
				for f in pairs(C.zones) do fileCont[f] = c end
			end
		end
	end
	return fileCont[file]
end

-- Maître de vol : continent, vue, position en yards de la vue.
local function Place(fm)
	local c = ContinentOf(fm[2])
	local view, x, y = ns.ToView(c, fm[2], fm[3], fm[4])
	return c, view, x, y
end

local function Mine(fm)
	return fm[5]:find(Faction(), 1, true) ~= nil
end

local function Name(fm)
	return GetLocale() == "frFR" and fm[7] or fm[6]
end

--------------------------------------------------------------------------------
-- Vols appris

-- Le maître de vol de la faction le plus proche d'un point (vue, yards), sur un continent donné.
local function Nearest(view, x, y, cont, within)
	local best, bestD
	for _, fm in ipairs(ns.FlightMasters) do
		if Mine(fm) then
			local c, v, fx, fy = Place(fm)
			if v == view and (not cont or c == cont) then
				local d = math.sqrt((fx - x) ^ 2 + (fy - y) ^ 2)
				if d <= within and (not bestD or d < bestD) then best, bestD = fm, d end
			end
		end
	end
	return best
end

-- Correspondance carte des vols -> vue, par axe : v = a * t + b (moindres carrés). nil tant
-- qu'il n'y a pas deux repères écartés d'au moins SPREAD sur chaque axe. Les repères viennent des
-- positions exactes des maîtres de vol et la carte des vols donne des positions précises : un
-- faible écart suffit (Hurlevent et Sentinelle : 0,9 % à l'horizontale). Chaque visite en ajoute.
local SPREAD = 0.004             -- un peu plus d'un pixel de la carte des vols (316 px)

local function Fit(pairs_)
	local n, st, sv, stt, stv = 0, 0, 0, 0, 0
	local axis = {}
	for k = 1, 2 do
		n, st, sv, stt, stv = 0, 0, 0, 0, 0
		local lo, hi = math.huge, -math.huge
		for _, p in pairs(pairs_) do
			local t, v = p[k], p[k + 2]
			n, st, sv, stt, stv = n + 1, st + t, sv + v, stt + t * t, stv + t * v
			lo, hi = math.min(lo, t), math.max(hi, t)
		end
		if n < 2 or hi - lo < SPREAD then return end
		local a = (n * stv - st * sv) / (n * stt - st * st)
		axis[k] = { a, (sv - a * st) / n }
	end
	return axis
end

-- Rattache les vols connus d'un continent (relevés à la dernière visite) à leurs maîtres de vol.
local function Resolve(cont)
	local nodes = Char().taxiNodes[cont]
	local axis = nodes and Fit(Calib()[cont] or {})
	if not axis then return end
	local view = cont == 3 and "outland" or "azeroth"
	for _, node in ipairs(nodes) do
		local x = axis[1][1] * node[1] + axis[1][2]
		local y = axis[2][1] * node[2] + axis[2][2]
		local fm = Nearest(view, x, y, cont, MATCH)
		if fm then Char().flights[fm[1]] = true end
	end
end

local Render

local function OnTaxiMap()
	if not WorldMapFrame:IsShown() then SetMapToCurrentZone() end
	local cont = GetCurrentMapContinent()
	local view, px, py = ns.UnitPos("player")
	local nodes, current = {}, nil
	for i = 1, NumTaxiNodes() do
		local kind = TaxiNodeGetType(i)
		if kind ~= "NONE" then
			local tx, ty = TaxiNodePosition(i)
			nodes[#nodes + 1] = { tx, ty }
			if kind == "CURRENT" then current = { tx, ty } end
		end
	end
	if not (view and cont and cont > 0) then return end
	Char().taxiNodes[cont] = nodes
	local here = Nearest(view, px, py, cont, HERE)
	if here then
		Char().flights[here[1]] = true
		if current then
			local _, _, fx, fy = Place(here)
			Calib()[cont] = Calib()[cont] or {}
			Calib()[cont][here[1]] = { current[1], current[2], fx, fy }
		end
	end
	Resolve(cont)
	Render()
end

--------------------------------------------------------------------------------
-- Affichage sur le canevas

local function Status(fm)
	if Char().flights[fm[1]] then return L.FLIGHT_KNOWN, 0.4, 1, 0.4 end
	if Char().taxiNodes[ContinentOf(fm[2])] then return L.FLIGHT_UNKNOWN, 0.7, 0.7, 0.7 end
	return L.FLIGHT_UNCHECKED, 0.7, 0.7, 0.7
end

local function NewButton(c)
	local b = CreateFrame("Button", nil, c.layers.flights)
	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetAllPoints(b)
	b:SetScript("OnEnter", function(self)
		local fm = self.fm
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine(Name(fm))
		local _, view, x, y = Place(fm)
		local zone = ns.ZoneAt(view, x, y)
		if zone then GameTooltip:AddLine(zone, 1, 1, 1) end
		local text, r, g, bl = Status(fm)
		GameTooltip:AddLine(text, r, g, bl, true)
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", function() GameTooltip:Hide() end)
	return b
end

-- Dézoomé sur le monde, des dizaines d'icônes s'entasseraient : la couche entière n'apparaît qu'à
-- partir de l'échelle d'un continent (un seul Show / Hide, pas une icône à la fois).
local FROM = 1.8                 -- fois le zoom minimal

local function Visible()
	local _, zoom = ns.view.Get()
	return ns.db.showFlights ~= false and zoom >= ns.view.ZoomMin() * FROM
end

-- Les maîtres de vol d'une vue pour la faction du joueur, en unités du canevas : calculés une fois.
local entries = {}

local function Entries(c)
	local key = c.name .. Faction()
	if not entries[key] then
		local list = {}
		for _, fm in ipairs(ns.FlightMasters) do
			if Mine(fm) then
				local _, view, x, y = Place(fm)
				if view == c.name then list[#list + 1] = { fm = fm, x = x * c.k, y = y * c.k } end
			end
		end
		entries[key] = list
	end
	return entries[key]
end

local function Paint(b)
	if Char().flights[b.fm[1]] then
		b.icon:SetTexture(ICON_KNOWN)
		b.icon:SetVertexColor(1, 1, 1)
	else
		b.icon:SetTexture(ICON_OTHER)
		b.icon:SetVertexColor(0.55, 0.55, 0.55)
	end
end

local function Resize()
	if not canvas or not canvas.flightButtons then return end
	local layer = canvas.layers.flights
	if not Visible() then
		layer:Hide()
		return
	end
	layer:Show()
	local _, zoom = ns.view.Get()
	local s = SIZE / zoom
	for _, b in pairs(canvas.flightButtons) do
		b:SetWidth(s)
		b:SetHeight(s)
	end
end

-- Crée les icônes qui entrent dans un rectangle (unités du canevas), une seule fois chacune :
-- l'ouverture de la carte ne fabrique que celles autour du joueur, pas les 80 d'Azeroth.
local function Populate(x0, y0, x1, y1)
	if not canvas or not Visible() then return end
	canvas.flightButtons = canvas.flightButtons or {}
	local buttons, created = canvas.flightButtons, false
	-- Une demi-vue de marge : les icônes sont prêtes avant d'entrer à l'écran.
	local mx, my = (x1 - x0) / 2, (y1 - y0) / 2
	for _, e in ipairs(Entries(canvas)) do
		local id = e.fm[1]
		if not buttons[id] and e.x >= x0 - mx and e.x <= x1 + mx and e.y >= y0 - my and e.y <= y1 + my then
			local b = NewButton(canvas)
			b.fm = e.fm
			b:SetPoint("CENTER", canvas.frame, "TOPLEFT", e.x, -e.y)
			Paint(b)
			buttons[id] = b
			created = true
		end
	end
	if created then Resize() end
end

-- Couleurs (vols appris), affichage ou non, puis les icônes de la vue.
function Render()
	if not canvas then return end
	canvas.flightButtons = canvas.flightButtons or {}
	local show = ns.db.showFlights ~= false
	for _, b in pairs(canvas.flightButtons) do
		if show then
			Paint(b)
			b:Show()
		else
			b:Hide()
		end
	end
	Resize()
	Populate(ns.view.Rect())
end

tinsert(ns.listeners.canvas, function(c)
	canvas = c
	Render()
end)
tinsert(ns.listeners.zoom, function() Resize() end)
tinsert(ns.listeners.view, Populate)

function ns.ToggleFlights()
	ns.db.showFlights = ns.db.showFlights == false
	Render()
	ns.Print(ns.db.showFlights and L.FLIGHTS_SHOWN or L.FLIGHTS_HIDDEN)
end

local events = CreateFrame("Frame")
events:RegisterEvent("TAXIMAP_OPENED")
events:SetScript("OnEvent", OnTaxiMap)
