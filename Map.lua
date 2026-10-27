-- Copyright (C) 2026 BellaHealFr. Licence GPL-3.0-only avec conditions supplémentaires
-- (mention de l'auteur, nom « Strata » réservé) : voir LICENSE et NOTICE.md.

-- Strata - Carte du monde continue pour World of Warcraft 3.3.5
-- La fenêtre et la carte assemblée.
--
-- Chaque vue a un canevas de UNITS unités de large (1 unité = 1/k yard). Le canevas est mis à
-- l'échelle (zoom) et placé dans un ScrollFrame qui le rogne. Couches, de bas en haut :
--   world : la carte du monde de Blizzard (vue Azeroth), bord adouci dans la mer de la fenêtre
--   cont  : la carte du continent sous le centre de la vue, en fondu avec le zoom
--   base  : le fond de chaque zone (12 tuiles, comme WorldMapDetailFrame : 1002 x 668 px)
--   over  : les morceaux découverts de chaque zone (GetMapOverlayInfo) ; brouillard éteint, tous
--           ses morceaux (Data/Overlays.lua) : la carte est révélée
--   city  : les villes, entièrement peintes, au-dessus de leurs voisines, une fois qu'elles
--           remplissent une part de la vue (comme OpenMap : avant, la zone autour les dessine)
--   Les fonds de zone et de ville ont un bord adouci (dégradé de transparence) : leurs rectangles
--   ne laissent pas de ligne sur leurs voisines.
--   base a un cadre par profondeur : le fond d'une zone (un rectangle opaque) passe au-dessus
--   des zones plus grandes qu'elle touche. Le client 3.3.5 n'a pas de sous-niveau de dessin, et
--   dans un même cadre l'ordre de textures réutilisées n'est pas garanti. Les morceaux
--   découverts, transparents autour de leur forme, gardent une seule couche.
--   pins  : les épingles (Pins.lua), emportées par un déplacement sans travail par épingle
-- Les zones ne chargent leurs textures que visibles et assez grandes à l'écran, et les rendent
-- quelques secondes après avoir quitté la vue (client 32 bits : la mémoire compte).
-- Les icônes (joueur, groupe) sont sur un cadre non mis à l'échelle : elles gardent leur taille.

local _, ns = ...

local Zones = ns.Zones
local L = ns.L

local UNITS = 1000
local MAP_W, MAP_H = 1002, 668      -- la partie utile des 4 x 3 tuiles de 256 px
local LAYERS = { "world", "cont", "base", "over", "city", "pins" }   -- base : un cadre par profondeur

local ZOOM_MAX = 40
local ZOOM_STEP = 1.3
local ZONE_MIN_PX = 220                    -- largeur à l'écran où une zone commence à paraître
-- Part de la largeur de la vue où la carte d'une ville paraît, puis est pleine (OpenMap : 0,2 à
-- 0,4 ; plus tôt où la zone ne la dessine que floue : Orgrimmar sur Durotar, les Pitons-du-Tonnerre
-- sur Mulgore).
local CITY_FADE = { 0.2, 0.4 }
local CITY_FADE_OF = { Ogrimmar = { 0.08, 0.25 }, ThunderBluff = { 0.08, 0.25 } }
local CONT_FROM, CONT_FULL = 1.4, 2.2      -- zoom où la carte du continent paraît, puis est pleine
local RELEASE_AFTER = 8                    -- secondes hors de la vue avant de rendre les textures
local MAX_HIDDEN = 160                     -- textures de zones cachées gardées au plus (les plus
                                           -- anciennes rendues d'abord) : borne le pic en déplacement

local frame, scroll, child, pins, hoverText, playerText, viewButton, fogButton, sea

-- La mer autour de la carte, de la couleur de celle de la carte (mesurée sur World et Expansion01),
-- comme OpenMap qui prolonge la mer au-delà du bord du monde.
local SEA = { azeroth = { 0.545, 0.455, 0.259 }, outland = { 0.490, 0.431, 0.318 } }
local canvases = {}
local V                       -- le canevas affiché
local zoom, ox, oy = 1, 0, 0  -- échelle, et position à l'écran (px, y vers le bas) de l'origine
local anim                    -- { target, mx, my } : zoom animé autour d'un point
local drag                    -- { x, y, ox, oy } : déplacement à la souris
local dirty = true
local hidden = 0           -- textures des zones cachées mais encore chargées (délai de RELEASE_AFTER)

-- Ce que la mesure (Bench.lua) lit. Le décompte des textures coûte une addition par texture ;
-- le chronométrage des images ne tourne que si ns.measuring est vrai (compteur ou bench).
ns.stats = { textures = 0, files = 0, zones = 0, frames = 0, ms = 0, worst = 0, layersMs = 0 }
local stats = ns.stats

--------------------------------------------------------------------------------
-- Textures

local function Acquire(layer)
	local tex = tremove(layer.pool)
	if not tex then
		tex = layer:CreateTexture(nil, "ARTWORK")
	end
	tex:Show()
	stats.textures = stats.textures + 1
	return tex
end

-- Fichiers de carte chargés : plusieurs morceaux peuvent partager une tuile, que le client ne
-- charge qu'une fois. stats.files compte les fichiers (la mémoire), stats.textures les morceaux.
local fileRefs = {}

local function SetFile(tex, path)
	tex.file = path
	local n = fileRefs[path] or 0
	if n == 0 then stats.files = stats.files + 1 end
	fileRefs[path] = n + 1
	tex:SetTexture(path)
end

local function Release(layer, tex)
	local path = tex.file
	if path then
		local n = fileRefs[path] - 1
		if n == 0 then
			fileRefs[path] = nil
			stats.files = stats.files - 1
		else
			fileRefs[path] = n
		end
		tex.file = nil
	end
	tex.cell, tex.fade = nil, nil
	tex:SetTexture(nil)
	tex:Hide()
	tex:ClearAllPoints()
	tinsert(layer.pool, tex)
	stats.textures = stats.textures - 1
end

-- Une tuile d'une grille : la première au coin (x, y) de la couche, les autres accrochées au bord
-- de leur voisine de gauche, ou de celle du dessus en début de rangée, comme WorldMapDetailTile2..12 :
-- deux voisines partagent exactement le même bord, sans joint d'arrondi au zoom.
-- (u0, u1, v0, v1) : la partie du fichier affichée, avec un demi-texel de marge au bord d'un
-- fichier, pour que le filtrage ne lise ni le bord opposé du fichier ni le vide au-delà.
local function PlaceTile(tex, layer, left, above, x, y, w, h, u0, u1, v0, v1)
	tex:ClearAllPoints()
	if left then
		tex:SetPoint("TOPLEFT", left, "TOPRIGHT")
	elseif above then
		tex:SetPoint("TOPLEFT", above, "BOTTOMLEFT")
	else
		tex:SetPoint("TOPLEFT", layer, "TOPLEFT", x, -y)
	end
	tex:SetWidth(w)
	tex:SetHeight(h)
	tex:SetTexCoord(u0, u1, v0, v1)
end

-- Bord adouci, comme le masque « feather » d'OpenMap (la 3.3.5 n'a pas de masques) : la colonne
-- et la rangée de tuiles du bord passent de l'opaque au transparent par les couleurs des sommets
-- (SetGradientAlpha). Les cartes de Blizzard débordent sur leurs voisines (et, au Norfendre,
-- portent un cadre ornementé dans les coins) : ce bord n'efface que ce débord.
-- Un coin demande les deux sens : il est découpé en CORNER_SLICES tranches verticales, chacune en
-- dégradé vertical, à la transparence horizontale de son côté extérieur (0 au bord de la carte).
local CORNER_SLICES = 4

-- Transparence horizontale et verticale en un point de la carte (px) : 0 au bord, 1 au cœur.
local function FadeX(x)
	if x <= 256 then return x / 256 end
	if x >= 768 then return (MAP_W - x) / (MAP_W - 768) end
	return 1
end
local function FadeY(y)
	if y <= 256 then return y / 256 end
	if y >= 512 then return (MAP_H - y) / (MAP_H - 512) end
	return 1
end

-- Le dégradé d'un morceau : { orientation, min, max }. VERTICAL va du bas (min) au haut (max).
local function Fade(col, row, x0, x1, y0, y1, corner)
	if corner then
		local f = col == 0 and FadeX(x0) or FadeX(x1)
		return { "VERTICAL", f * FadeY(y1), f * FadeY(y0) }
	elseif col == 0 or col == 3 then
		return { "HORIZONTAL", FadeX(x0), FadeX(x1) }
	elseif row == 0 or row == 2 then
		return { "VERTICAL", FadeY(y1), FadeY(y0) }
	end
	return { "HORIZONTAL", 1, 1 }
end

-- Le découpage d'une carte en morceaux, le même pour toutes : calculé une fois. Pour chaque
-- morceau : sa place (cell, en px de la carte), sa tuile, ses coordonnées dans le fichier, son
-- dégradé, et s'il commence une rangée. GRID.plain : une tuile par morceau ; GRID.feather : bord
-- adouci, les coins en tranches.
local GRID = {}
for _, feather in ipairs({ false, true }) do
	local cells = {}
	for row = 0, 2 do
		local ty = row * 256
		local th = min(256, MAP_H - ty)
		for col = 0, 3 do
			local tx = col * 256
			local tw = min(256, MAP_W - tx)
			local corner = feather and (col == 0 or col == 3) and (row == 0 or row == 2)
			local n = corner and CORNER_SLICES or 1
			for s = 1, n do
				local x0, x1 = tx + tw * (s - 1) / n, tx + tw * s / n
				cells[#cells + 1] = {
					x0, ty, x1, ty + th,
					tile = row * 4 + col + 1,
					rowStart = col == 0 and s == 1,
					u0 = (x0 - tx + (s == 1 and 0.5 or 0)) / 256, u1 = (x1 - tx - (s == n and 0.5 or 0)) / 256,
					v0 = 0.5 / 256, v1 = (th - 0.5) / 256,
					fade = feather and Fade(col, row, x0, x1, ty, ty + th, corner) or nil,
				}
			end
		end
	end
	GRID[feather and "feather" or "plain"] = cells
end

-- Pose des morceaux précalculés (cells) au coin (x, y) d'une couche, sx, sy unités par px de la
-- carte. Chaque morceau garde sa place (tex.cell, en px) et son dégradé (tex.fade).
-- Les morceaux sont rangés par rangées, de gauche à droite ; un morceau entièrement transparent
-- n'est pas créé. Chacun s'accroche à son voisin de gauche s'il le touche, sinon (début de rangée)
-- au premier morceau de la rangée du dessus s'il est juste au-dessus, sinon il est placé seul.
local function AddCells(list, layer, cells, prefix, x, y, sx, sy)
	local left, rowFirst, aboveFirst
	for _, cell in ipairs(cells) do
		if not left or left.cell[2] ~= cell[2] then
			aboveFirst, rowFirst, left = rowFirst, nil, nil
		end
		local l = left and left.cell[3] == cell[1] and left or nil
		local a = not l and not rowFirst and aboveFirst and aboveFirst.cell[1] == cell[1]
			and aboveFirst.cell[4] == cell[2] and aboveFirst or nil
		local tex = Acquire(layer)
		PlaceTile(tex, layer, l, a, x + cell[1] * sx, y + cell[2] * sy, (cell[3] - cell[1]) * sx, (cell[4] - cell[2]) * sy,
			cell.u0, cell.u1, cell.v0, cell.v1)
		rowFirst = rowFirst or tex
		tex.cell, tex.fade = cell, cell.fade
		SetFile(tex, prefix .. cell.tile)
		list[#list + 1] = tex
		left = tex
	end
end

-- Les 12 tuiles d'une carte (prefix1 .. prefix12) sur un rectangle en unités ; feather : bord
-- adouci.
local function AddMapTiles(list, layer, prefix, rx, ry, rw, rh, feather)
	AddCells(list, layer, feather and GRID.feather or GRID.plain, prefix, rx, ry, rw / MAP_W, rh / MAP_H)
end

-- Morceaux découverts. Ils ont leur propre transparence (bords fondus par Blizzard), sauf là où
-- ils touchent le bord de la carte de leur zone : ils y portent un bout du cadre de la carte (bord
-- de parchemin déchiré et son ombre ; au Norfendre, de gros ornements dans les coins). Dans une
-- carte assemblée, ce cadre tombe au milieu du monde. Comme OpenMap (« a thin feather at the
-- art's edge »), ces côtés-là seulement ont un bord adouci.
local FRAME_TOLERANCE = 2        -- px de la carte : un morceau à moins de 2 px du bord le touche
local FRAME_BAND = 32            -- px : le bord déchiré et son ombre
local CORNER_BAND = 128          -- px : un morceau dans un coin d'une carte du Norfendre (ornements)

-- Fond d'une zone ou d'une ville, comme OpenMap qui ne le montre que sur son territoire (masques) :
-- sans masques, il est limité au rectangle de son territoire, avec un bord fin adouci. Le cadre,
-- les ornements, la mer et les noms des zones voisines que la carte de Blizzard peint autour
-- tombent dehors. Zone : son territoire réel en escalier (Shape, plus bas), ou à défaut le
-- rectangle qui englobe tous ses morceaux (Data/Overlays.lua). Ville (pas de morceaux) : son
-- plan, relevé sur sa carte (px de la carte, 1002 x 668), sans les blasons et emblèmes peints à côté.
local BASE_BAND = 48             -- px : bord adouci du fond
local BASE_SLICES = 4            -- tranches d'un coin : paliers de 25 %
local CITY_PLAN = {
	Stormwind = { 170, 30, 900, 650 }, Ironforge = { 80, 10, 900, 640 }, Darnassis = { 40, 10, 930, 640 },
	TheExodar = { 200, 10, 830, 650 }, Ogrimmar = { 90, 20, 860, 630 }, Undercity = { 130, 20, 910, 600 },
	ThunderBluff = { 110, 20, 830, 600 }, SilvermoonCity = { 20, 20, 990, 650 }, ShattrathCity = { 80, 20, 810, 660 },
	Dalaran = { 40, 30, 840, 640 },
}

-- Les côtés d'un morceau qui touchent le cadre de la carte, et la largeur du bord adouci.
function ns.FrameBand(o, c)
	local x0, y0, x1, y1 = o[4], o[5], o[4] + o[2], o[5] + o[3]
	local sides = {
		left = x0 <= FRAME_TOLERANCE, top = y0 <= FRAME_TOLERANCE,
		right = x1 >= MAP_W - FRAME_TOLERANCE, bottom = y1 >= MAP_H - FRAME_TOLERANCE,
	}
	local corner = (sides.left or sides.right) and (sides.top or sides.bottom)
	return sides, (corner and c == 4) and CORNER_BAND or FRAME_BAND
end

-- La taille du fichier d'une tuile de bord : la puissance de 2 qui la contient (WorldMapFrame_Update).
local function FileSize(px)
	local size = 16
	while size < px do size = size * 2 end
	return size
end

local function SortUnique(t)
	sort(t)
	local out = {}
	for _, v in ipairs(t) do
		if not out[1] or v - out[#out] > 1e-6 then out[#out + 1] = v end
	end
	return out
end

-- Le découpage d'un morceau tw x th (tuiles de 256 px comme Blizzard, fichiers de bord en
-- puissance de 2), avec un bord adouci de band px sur les côtés demandés (sides). Un coin (deux
-- côtés) est coupé en deux tranches, en dégradé vertical à la transparence horizontale de son
-- côté extérieur ; une pièce entièrement transparente n'est pas créée.

-- Le fond d'une carte limité au rectangle (x0, y0) - (x1, y1), en px de la carte, avec un bord
-- adouci de BASE_BAND px tout autour. Les coins sont coupés en BASE_SLICES tranches.
local function RectCells(x0, y0, x1, y1)
	local bx, by = min(BASE_BAND, (x1 - x0) / 3), min(BASE_BAND, (y1 - y0) / 3)
	-- Colonnes : bords des tuiles et du bord adouci ; les rangées des coins (bandes du haut et du
	-- bas) ont en plus les tranches des coins.
	local xs, ys = { x0, x1, x0 + bx, x1 - bx }, { y0, y1, y0 + by, y1 - by }
	for k = 1, 3 do
		if 256 * k > x0 and 256 * k < x1 then xs[#xs + 1] = 256 * k end
	end
	for j = 1, 2 do
		if 256 * j > y0 and 256 * j < y1 then ys[#ys + 1] = 256 * j end
	end
	local xsCorner = { unpack(xs) }
	for i = 1, BASE_SLICES - 1 do
		xsCorner[#xsCorner + 1], xsCorner[#xsCorner + 2] = x0 + bx * i / BASE_SLICES, x1 - bx * i / BASE_SLICES
	end
	xs, xsCorner, ys = SortUnique(xs), SortUnique(xsCorner), SortUnique(ys)
	local function FX(x) return min(1, (x - x0) / bx, (x1 - x) / bx) end
	local function FY(y) return min(1, (y - y0) / by, (y1 - y) / by) end
	local cells = {}
	for r = 1, #ys - 1 do
		local ya, yb = ys[r], ys[r + 1]
		local j = floor(ya / 256)
		local ty = 256 * j
		local inY = yb <= y0 + by + 1e-6 or ya >= y1 - by - 1e-6
		local cols = inY and xsCorner or xs
		for c = 1, #cols - 1 do
			local xa, xb = cols[c], cols[c + 1]
			local k = floor(xa / 256)
			local tx = 256 * k
			local inLeft = xb <= x0 + bx + 1e-6
			local inX = inLeft or xa >= x1 - bx - 1e-6
			local fade
			if inX and inY then
				local f = inLeft and FX(xa) or FX(xb)
				fade = { "VERTICAL", f * FY(yb), f * FY(ya) }
			elseif inX then
				fade = { "HORIZONTAL", FX(xa), FX(xb) }
			elseif inY then
				fade = { "VERTICAL", FY(yb), FY(ya) }
			else
				fade = { "HORIZONTAL", 1, 1 }
			end
			if not (fade[2] == 0 and fade[3] == 0) then
				-- (demi-texel de marge au bord d'un fichier ou de la partie utile de la carte)
				local tEnd, vEnd = min(tx + 256, MAP_W), min(ty + 256, MAP_H)
				cells[#cells + 1] = {
					xa, ya, xb, yb,
					tile = j * 4 + k + 1,
					u0 = (xa - tx + (xa == tx and 0.5 or 0)) / 256, u1 = (xb - tx - (xb == tEnd and 0.5 or 0)) / 256,
					v0 = (ya - ty + (ya == ty and 0.5 or 0)) / 256, v1 = (yb - ty - (yb == vEnd and 0.5 or 0)) / 256,
					fade = fade,
				}
			end
		end
	end
	return cells
end

-- Le rectangle qui englobe tous les morceaux d'une zone (Data/Overlays.lua), ou nil.
local function PiecesRect(file)
	local list = ns.Overlays[file]
	if not list then return nil end
	local x0, y0, x1, y1 = MAP_W, MAP_H, 0, 0
	for _, o in ipairs(list) do
		x0, y0 = min(x0, o[4]), min(y0, o[5])
		x1, y1 = max(x1, o[4] + o[2]), max(y1, o[5] + o[3])
	end
	return { max(0, x0), max(0, y0), min(MAP_W, x1), min(MAP_H, y1) }
end

-- Territoire réel d'une zone (Data/Territory.lua, relevé sur le terrain du client) : un escalier
-- de colonnes de 256 px, celles des tuiles, chacune à l'étendue nord-sud du terrain de la zone,
-- dans le rectangle de ses morceaux. Le fond et les morceaux y sont coupés, avec un bord adouci
-- de BASE_BAND px : en haut et en bas de chaque colonne, sur les côtés est et ouest, et sur la
-- marche entre deux colonnes (la plus haute déborde en fondu sur sa voisine). Le cadre et les
-- noms des voisines que Blizzard peint au-delà du territoire tombent dehors : sous la Forêt
-- d'Elwynn, le nom « Bois de la Pénombre » et la rive.
local shapes = {}
local function Shape(file)
	if shapes[file] == nil then
		local t, r = ns.Territory[file], PiecesRect(file)
		local s = false
		if t then
			local x0, x1 = t[1], t[2]
			if r then x0, x1 = max(x0, r[1]), min(x1, r[3]) end
			local cols = {}
			for k = 1, 4 do
				local c = t[k + 2]
				local a, b = max(x0, 256 * (k - 1)), min(x1, 256 * k)
				if c and a < b then
					local y0, y1 = c[1], c[2]
					if r then y0, y1 = max(y0, r[2]), min(y1, r[4]) end
					local p = cols[#cols]
					if p and p[2] == a and abs(p[3] - y0) < BASE_BAND and abs(p[4] - y1) < BASE_BAND then
						-- (presque la même étendue que sa voisine : une seule colonne, sans marche)
						p[2], p[3], p[4] = b, min(p[3], y0), max(p[4], y1)
						p[5] = min(BASE_BAND, (p[4] - p[3]) / 3)
					elseif y0 < y1 then
						cols[#cols + 1] = { a, b, y0, y1, min(BASE_BAND, (y1 - y0) / 3) }
					end
				end
			end
			if cols[1] and x0 < x1 then s = { x0 = x0, x1 = x1, bx = min(BASE_BAND, (x1 - x0) / 3), cols = cols } end
		end
		shapes[file] = s
	end
	return shapes[file] or nil
end

local function Band(v, a, b, band)
	return max(0, min(1, (v - a) / band, (b - v) / band))
end

-- Transparence d'une forme en un point (px de la carte) : 0 dehors, 1 au cœur.
local function ShapeAlpha(s, x, y)
	local fx = Band(x, s.x0, s.x1, s.bx)
	local best = 0
	if fx > 0 then
		local cols = s.cols
		for i = 1, #cols do
			local c = cols[i]
			local inner = x < c[1] and (x - c[1] + BASE_BAND) / BASE_BAND or x > c[2] and (c[2] + BASE_BAND - x) / BASE_BAND or 1
			if inner > 0 and y > c[3] and y < c[4] then
				local a = (inner < fx and inner or fx) * Band(y, c[3], c[4], c[5])
				if a > best then best = a end
			end
		end
	end
	return best
end

-- Bornes d'une forme, décalées de (dx, dy) : en x, et en y pour les colonnes qui touchent [xa, xb].
local function ShapeXs(s, xs, dx)
	xs[#xs + 1], xs[#xs + 2], xs[#xs + 3], xs[#xs + 4] = s.x0 - dx, s.x1 - dx, s.x0 + s.bx - dx, s.x1 - s.bx - dx
	for _, c in ipairs(s.cols) do
		xs[#xs + 1], xs[#xs + 2], xs[#xs + 3], xs[#xs + 4] = c[1] - dx, c[2] - dx, c[1] - BASE_BAND - dx, c[2] + BASE_BAND - dx
	end
end
local function ShapeYs(s, ys, xa, xb, dx, dy)
	for _, c in ipairs(s.cols) do
		if c[1] - BASE_BAND < xb + dx and c[2] + BASE_BAND > xa + dx then
			ys[#ys + 1], ys[#ys + 2], ys[#ys + 3], ys[#ys + 4] = c[3] - dy, c[4] - dy, c[3] + c[5] - dy, c[4] - c[5] - dy
		end
	end
end

-- Les bornes gardées dans [lo, hi], triées, sans doublon (false : borne absente). snap : une
-- borne à moins de SNAP px d'une autre est retirée (pas de lamelles) ; lo, hi et les bords des
-- tuiles (multiples de 256) restent.
local SNAP = 12
local function Within(t, lo, hi, snap)
	local fixed, other = { lo, hi }, {}
	for _, v in ipairs(t) do
		if v and v > lo and v < hi then
			if v % 256 == 0 or not snap then fixed[#fixed + 1] = v else other[#other + 1] = v end
		end
	end
	local out = SortUnique(fixed)
	if snap then
		for _, v in ipairs(SortUnique(other)) do
			local ok = true
			for _, w in ipairs(out) do
				if abs(v - w) < SNAP then ok = false break end
			end
			if ok then out[#out + 1] = v end
		end
		out = SortUnique(out)
	end
	return out
end

local function Near(a, b) return abs(a - b) < 1e-3 end

-- Découpe [0, w] x [0, h] (px) aux bornes xs, et ys(xa, xb) par bande verticale, en morceaux de
-- transparence linéaire Alpha(x, y) : dégradé vertical ou horizontal ; là où elle change dans les
-- deux sens (coins, marches), CORNER_SLICES tranches verticales, chacune à la transparence de son
-- côté le moins opaque. Emit(x0, y0, x1, y1, fade) pour chaque morceau non entièrement
-- transparent ; fade est nil s'il est opaque.
local function Cut(xs, YsFor, Alpha, Emit)
	local left, right = {}, {}       -- transparence sur les bords gauche et droit, par borne y
	for i = 1, #xs - 1 do
		local xa, xb = xs[i], xs[i + 1]
		local ys = YsFor(xa, xb)
		for j = 1, #ys do
			left[j], right[j] = Alpha(xa, ys[j]), Alpha(xb, ys[j])
		end
		for j = 1, #ys - 1 do
			local ya, yb = ys[j], ys[j + 1]
			local tl, tr, bl, br = left[j], right[j], left[j + 1], right[j + 1]
			if Near(tl, tr) and Near(bl, br) then
				if not (Near(tl, 0) and Near(bl, 0)) then
					Emit(xa, ya, xb, yb, not (Near(tl, 1) and Near(bl, 1)) and { "VERTICAL", bl, tl } or nil)
				end
			elseif Near(tl, bl) and Near(tr, br) then
				Emit(xa, ya, xb, yb, { "HORIZONTAL", tl, tr })
			elseif xb - xa < 16 then
				local top, bottom = min(tl, tr), min(bl, br)
				if top > 0 or bottom > 0 then Emit(xa, ya, xb, yb, { "VERTICAL", bottom, top }) end
			else
				for s = 1, CORNER_SLICES do
					local sa, sb = xa + (xb - xa) * (s - 1) / CORNER_SLICES, xa + (xb - xa) * s / CORNER_SLICES
					local top, bottom = min(Alpha(sa, ya), Alpha(sb, ya)), min(Alpha(sa, yb), Alpha(sb, yb))
					if top > 0 or bottom > 0 then Emit(sa, ya, sb, yb, { "VERTICAL", bottom, top }) end
				end
			end
		end
	end
end

-- Les morceaux rangés par rangées, de gauche à droite (AddCells accroche chacun à sa voisine),
-- deux voisins d'une même tuile au même dégradé vertical (ou opaques) réunis en un seul.
local function ByRows(a, b)
	if a[2] ~= b[2] then return a[2] < b[2] end
	return a[1] < b[1]
end
local function SameFade(f, g)
	if not f or not g then return not f and not g end
	if f[1] == "HORIZONTAL" and g[1] == "HORIZONTAL" then
		return f[2] == 1 and f[3] == 1 and g[2] == 1 and g[3] == 1
	end
	return f[1] == "VERTICAL" and g[1] == "VERTICAL" and Near(f[2], g[2]) and Near(f[3], g[3])
end
local function Opaque(f)
	return not f or Near(f[2], 1) and Near(f[3], 1)
end
local function Rows(cells)
	sort(cells, ByRows)
	local out = {}
	for _, c in ipairs(cells) do
		local p = out[#out]
		if p and p[2] == c[2] and p[4] == c[4] and p[3] == c[1] and p.tile == c.tile and SameFade(p.fade, c.fade) then
			p[3], p.u1 = c[3], c.u1
		else
			out[#out + 1] = c
		end
	end
	-- (puis les morceaux opaques l'un sous l'autre, de même largeur et de même tuile)
	local below = {}                 -- [x0][y0] = morceau opaque
	for _, c in ipairs(out) do
		if Opaque(c.fade) then
			below[c[1]] = below[c[1]] or {}
			below[c[1]][c[2]] = c
		end
	end
	local merged = {}
	for _, c in ipairs(out) do
		if not c.gone and Opaque(c.fade) then
			local col = below[c[1]]
			local n = col[c[4]]
			while n and not n.gone and n[3] == c[3] and n.tile == c.tile and n ~= c do
				c[4], c.v1, n.gone = n[4], n.v1, true
				n = col[c[4]]
			end
		end
	end
	for _, c in ipairs(out) do
		if not c.gone then merged[#merged + 1] = c end
	end
	return merged
end

-- Le fond d'une zone coupé à sa forme : 12 tuiles de 256 px (MAP_W x MAP_H utiles).
local function ShapeCells(s)
	local xs = { 256, 512, 768 }
	ShapeXs(s, xs, 0)
	xs = Within(xs, s.x0, s.x1, true)
	local cells = {}
	Cut(xs, function(xa, xb)
		local ys = { 256, 512 }
		ShapeYs(s, ys, xa, xb, 0, 0)
		return Within(ys, 0, MAP_H, true)
	end, function(x, y) return ShapeAlpha(s, x, y) end, function(xa, ya, xb, yb, fade)
		local k, j = floor(xa / 256), floor(ya / 256)
		local tx, ty = 256 * k, 256 * j
		local tEnd, vEnd = min(tx + 256, MAP_W), min(ty + 256, MAP_H)
		cells[#cells + 1] = {
			xa, ya, xb, yb,
			tile = j * 4 + k + 1,
			u0 = (xa - tx + (xa == tx and 0.5 or 0)) / 256, u1 = (xb - tx - (xb == tEnd and 0.5 or 0)) / 256,
			v0 = (ya - ty + (ya == ty and 0.5 or 0)) / 256, v1 = (yb - ty - (yb == vEnd and 0.5 or 0)) / 256,
			fade = fade or { "HORIZONTAL", 1, 1 },
		}
	end)
	return Rows(cells)
end

-- Le découpage du fond d'une zone ou d'une ville (calculé une fois par carte).
local baseCells = {}
local function BaseCells(file, city)
	if baseCells[file] == nil then
		local s = not city and Shape(file)
		if s then
			baseCells[file] = ShapeCells(s)
		else
			local r = city and CITY_PLAN[file] or not city and PiecesRect(file)
			-- (sans territoire connu : la carte entière, au bord large)
			baseCells[file] = r and RectCells(r[1], r[2], r[3], r[4]) or false
		end
	end
	return baseCells[file] or GRID.feather
end

local function PieceCells(tw, th, sides, band)
	local wide, tall = ceil(tw / 256), ceil(th / 256)
	local bx, by = min(band, tw / 3), min(band, th / 3)
	local xs, ys = { 0, tw }, { 0, th }
	for k = 1, wide - 1 do xs[#xs + 1] = 256 * k end
	for j = 1, tall - 1 do ys[#ys + 1] = 256 * j end
	if sides.left then xs[#xs + 1], xs[#xs + 2] = bx / 2, bx end
	if sides.right then xs[#xs + 1], xs[#xs + 2] = tw - bx / 2, tw - bx end
	if sides.top then ys[#ys + 1] = by end
	if sides.bottom then ys[#ys + 1] = th - by end
	xs, ys = SortUnique(xs), SortUnique(ys)
	local function FX(x)
		local a = 1
		if sides.left then a = min(a, x / bx) end
		if sides.right then a = min(a, (tw - x) / bx) end
		return a
	end
	local function FY(y)
		local a = 1
		if sides.top then a = min(a, y / by) end
		if sides.bottom then a = min(a, (th - y) / by) end
		return a
	end
	local cells = {}
	for r = 1, #ys - 1 do
		local y0, y1 = ys[r], ys[r + 1]
		local j = floor(y0 / 256) + 1
		local ty = 256 * (j - 1)
		local ph = min(256, th - ty)
		local fh = j < tall and 256 or FileSize(ph)
		local inY = (sides.top and y1 <= by + 1e-6) or (sides.bottom and y0 >= th - by - 1e-6)
		for c = 1, #xs - 1 do
			local x0, x1 = xs[c], xs[c + 1]
			local k = floor(x0 / 256) + 1
			local tx = 256 * (k - 1)
			local pw = min(256, tw - tx)
			local fw = k < wide and 256 or FileSize(pw)
			local inLeft = sides.left and x1 <= bx + 1e-6
			local inX = inLeft or (sides.right and x0 >= tw - bx - 1e-6)
			local fade
			if inX and inY then
				local f = inLeft and FX(x0) or FX(x1)
				fade = { "VERTICAL", f * FY(y1), f * FY(y0) }
			elseif inX then
				fade = { "HORIZONTAL", FX(x0), FX(x1) }
			elseif inY then
				fade = { "VERTICAL", FY(y1), FY(y0) }
			end
			if not (fade and fade[2] == 0 and fade[3] == 0) then cells[#cells + 1] = {
				x0, y0, x1, y1,
				tile = (j - 1) * wide + k,
				u0 = (x0 - tx + (x0 == tx and 0.5 or 0)) / fw, u1 = (x1 - tx - (x1 == tx + pw and 0.5 or 0)) / fw,
				v0 = (y0 - ty + (y0 == ty and 0.5 or 0)) / fh, v1 = (y1 - ty - (y1 == ty + ph and 0.5 or 0)) / fh,
				fade = fade,
			} end
		end
	end
	return cells
end

-- Brouillard éteint : tous les morceaux de la zone (Data/Overlays.lua) en plus des découverts, comme
-- le « fog clear » de Mapster. Fusionnés par nom, une fois par liste de découverts (une découverte
-- remplace la liste).
local function Revealed(info)
	local all = ns.Overlays[info.file]
	if not all then return info.overlays end
	if info.revealFor ~= info.overlays then
		local list, seen = {}, {}
		for _, o in ipairs(info.overlays) do
			list[#list + 1] = o
			seen[strlower(o[1]:match("[^\\]+$"))] = true
		end
		local dir = "Interface\\WorldMap\\" .. info.file .. "\\"
		for _, o in ipairs(all) do
			if not seen[strlower(o[1])] then list[#list + 1] = { dir .. o[1], o[2], o[3], o[4], o[5] } end
		end
		info.reveal, info.revealFor = list, info.overlays
	end
	return info.reveal
end

-- Un morceau coupé à la forme de sa zone (s), avec le bord adouci de son cadre (sides, band).
local function PieceShapeCells(o, sides, band, s)
	local tw, th, ox, oy = o[2], o[3], o[4], o[5]
	-- (entièrement dans le cœur du territoire : le découpage d'origine. Le cœur, sous chaque
	-- colonne que le morceau touche, sans trou entre elles, loin des bords est et ouest.)
	local px0, px1, py0, py1 = ox, ox + tw, oy, oy + th
	local inside = px0 >= s.x0 + s.bx and px1 <= s.x1 - s.bx
	local reach = px0
	for _, c in ipairs(s.cols) do
		if inside and c[1] < px1 and c[2] > px0 then
			if c[1] > reach or py0 < c[3] + c[5] or py1 > c[4] - c[5] then inside = false end
			reach = max(reach, c[2])
		end
	end
	if inside and reach >= px1 then return PieceCells(tw, th, sides, band) end
	local wide, tall = ceil(tw / 256), ceil(th / 256)
	local bx, by = min(band, tw / 3), min(band, th / 3)
	local function Alpha(x, y)
		local fx, fy = 1, 1
		if sides.left then fx = min(fx, x / bx) end
		if sides.right then fx = min(fx, (tw - x) / bx) end
		if sides.top then fy = min(fy, y / by) end
		if sides.bottom then fy = min(fy, (th - y) / by) end
		return max(0, fx) * max(0, fy) * ShapeAlpha(s, ox + x, oy + y)
	end
	local xs = { 0, tw, sides.left and bx, sides.right and tw - bx }
	for k = 1, wide - 1 do xs[#xs + 1] = 256 * k end
	ShapeXs(s, xs, ox)
	xs = Within(xs, 0, tw, true)
	local cells = {}
	Cut(xs, function(xa, xb)
		local ys = { 0, th, sides.top and by, sides.bottom and th - by }
		for j = 1, tall - 1 do ys[#ys + 1] = 256 * j end
		ShapeYs(s, ys, xa, xb, ox, oy)
		return Within(ys, 0, th, true)
	end, Alpha, function(x0, y0, x1, y1, fade)
		local j, k = floor(y0 / 256) + 1, floor(x0 / 256) + 1
		local ty, tx = 256 * (j - 1), 256 * (k - 1)
		local ph, pw = min(256, th - ty), min(256, tw - tx)
		local fh, fw = j < tall and 256 or FileSize(ph), k < wide and 256 or FileSize(pw)
		cells[#cells + 1] = {
			x0, y0, x1, y1,
			tile = (j - 1) * wide + k,
			u0 = (x0 - tx + (x0 == tx and 0.5 or 0)) / fw, u1 = (x1 - tx - (x1 == tx + pw and 0.5 or 0)) / fw,
			v0 = (y0 - ty + (y0 == ty and 0.5 or 0)) / fh, v1 = (y1 - ty - (y1 == ty + ph and 0.5 or 0)) / fh,
			fade = fade,
		}
	end)
	return Rows(cells)
end

-- Les morceaux d'une zone (overlays : découverts, ou tous), coupés à sa forme quand elle est
-- connue. Leur découpage est calculé une fois par liste et gardé sur elle (overlays.cells) : une
-- découverte donne une nouvelle liste.
local function OverlayCells(overlays, i, file, c)
	local cells = overlays.cells
	if not cells then
		cells = {}
		overlays.cells = cells
	end
	if not cells[i] then
		local o, s = overlays[i], Shape(file)
		local sides, band = ns.FrameBand(o, c)
		cells[i] = s and PieceShapeCells(o, sides, band, s) or PieceCells(o[2], o[3], sides, band)
	end
	return cells[i]
end

local function AddOverlays(list, layer, overlays, file, c, rx, ry, rw, rh)
	local sx, sy = rw / MAP_W, rh / MAP_H
	for i, o in ipairs(overlays) do
		AddCells(list, layer, OverlayCells(overlays, i, file, c), o[1], rx + o[4] * sx, ry + o[5] * sy, sx, sy)
	end
end

local function SetAlphaAll(list, alpha)
	for i = 1, #list do list[i]:SetAlpha(alpha) end
end

-- La transparence d'un fond à bord adouci passe par son dégradé (les couleurs des sommets).
local function SetFadeAll(list, alpha)
	for i = 1, #list do
		local tex = list[i]
		local f = tex.fade
		if f then
			tex:SetGradientAlpha(f[1], 1, 1, 1, f[2] * alpha, 1, 1, 1, f[3] * alpha)
		else
			tex:SetAlpha(alpha)
		end
	end
end

local function ShowAll(list, show)
	for i = 1, #list do
		if show then list[i]:Show() else list[i]:Hide() end
	end
end

local function ReleaseAll(layer, list)
	for i = #list, 1, -1 do
		Release(layer, list[i])
		list[i] = nil
	end
end

--------------------------------------------------------------------------------
-- Canevas d'une vue

local function BuildCanvas(name)
	local view = ns.VIEWS[name]
	local k = UNITS / view.size.w
	local c = {
		name = name, k = k, w = UNITS, h = view.size.h * k,
		conts = {},
	}
	c.frame = CreateFrame("Frame", nil, child)
	c.frame:SetWidth(c.w)
	c.frame:SetHeight(c.h)
	-- Les zones, avant les couches : leur profondeur fixe le nombre de cadres de base.
	c.zones = {}
	local depth = 1
	for _, cont in ipairs(view.continents) do
		local C = Zones[cont]
		local bx, by = 0, 0
		if C.parent == 0 then bx, by = C.x, C.y end
		local map = ns.maps[cont]
		local land = {}       -- les zones du continent hors villes, seules à pouvoir se toucher
		for file, Z in pairs(C.zones) do
			local info = map and map.zones[file]
			if not Z[5] and info then
				local e = {
					info = info, file = file, city = ns.CITIES[file], depth = 1,
					x = (bx + Z[3]) * k, y = (by + Z[4]) * k, w = Z[1] * k, h = Z[2] * k,
				}
				c.zones[#c.zones + 1] = e
				if not e.city then land[#land + 1] = e end
			end
		end
		-- Les grandes d'abord ; chaque zone un cran au-dessus des plus grandes qu'elle touche.
		sort(land, function(a, b) return a.w * a.h > b.w * b.h end)
		for i, e in ipairs(land) do
			for j = 1, i - 1 do
				local o = land[j]
				if e.x < o.x + o.w and o.x < e.x + e.w and e.y < o.y + o.h and o.y < e.y + e.h and o.depth >= e.depth then
					e.depth = o.depth + 1
				end
			end
			if e.depth > depth then depth = e.depth end
		end
	end

	c.layers = {}
	local level = c.frame:GetFrameLevel()
	local function NewLayer()
		level = level + 1
		local layer = CreateFrame("Frame", nil, c.frame)
		layer:SetAllPoints(c.frame)
		layer:SetFrameLevel(level)
		layer.pool = {}
		return layer
	end
	for _, layerName in ipairs(LAYERS) do
		if layerName == "base" then
			c.layers[layerName] = {}
			for d = 1, depth do c.layers[layerName][d] = NewLayer() end
		else
			c.layers[layerName] = NewLayer()
		end
	end

	if view.world then
		c.world = {}
		AddMapTiles(c.world, c.layers.world, "Interface\\WorldMap\\" .. view.world .. "\\" .. view.world,
			0, 0, c.w, c.h, true)
		SetFadeAll(c.world, 1)
	end

	for _, cont in ipairs(view.continents) do
		local C = Zones[cont]
		local bx, by = 0, 0
		if C.parent == 0 then bx, by = C.x, C.y end
		local map = ns.maps[cont]
		if map and map.file then
			local tiles = {}
			-- (bord adouci, comme OpenMap : le cadre ornementé et la mer du continent se fondent
			-- dans la carte du monde)
			AddMapTiles(tiles, c.layers.cont, "Interface\\WorldMap\\" .. map.file .. "\\" .. map.file,
				bx * k, by * k, C.w * k, C.h * k, true)
			ShowAll(tiles, false)
			c.conts[cont] = tiles
		end
	end
	return c
end

local function LoadZone(e)
	local L = V.layers
	e.base = {}
	AddCells(e.base, e.city and L.city or L.base[e.depth], BaseCells(e.file, e.city), e.info.prefix,
		e.x, e.y, e.w / MAP_W, e.h / MAP_H)
	e.over = {}
	e.reveal = not ns.db.fog
	AddOverlays(e.over, L.over, e.reveal and Revealed(e.info) or e.info.overlays, e.file, e.info.c, e.x, e.y, e.w, e.h)
	e.loaded, e.alpha = true, nil
	stats.zones = stats.zones + 1
end

local function ZoneTextures(e)
	return #e.base + #e.over
end

-- Rend les textures d'une zone ; c : son canevas (celui affiché par défaut).
local function UnloadZone(e, c)
	local L = (c or V).layers
	if e.hiddenAt then hidden = hidden - ZoneTextures(e) end
	ReleaseAll(e.city and L.city or L.base[e.depth], e.base)
	ReleaseAll(L.over, e.over)
	e.loaded, e.hiddenAt = nil, nil
	stats.zones = stats.zones - 1
end

-- Rend toutes les zones d'un canevas : vue quittée, ou carte fermée. Les cartes du monde et des
-- continents (quelques dizaines de tuiles) restent : elles reviennent sans délai.
local function UnloadAll(c)
	for _, e in ipairs(c.zones) do
		if e.loaded then UnloadZone(e, c) end
	end
end

-- Le continent sous un point du canevas (vue Azeroth) : celui dont une zone le contient.
local function ContinentAt(x, y)
	for _, e in ipairs(V.zones) do
		if x >= e.x and x <= e.x + e.w and y >= e.y and y <= e.y + e.h then
			return e.info.c
		end
	end
end

--------------------------------------------------------------------------------
-- Vue : zoom et position

local function ViewSize()
	return child:GetWidth(), child:GetHeight()
end

local function ZoomMin()
	local vw, vh = ViewSize()
	return min(vw / V.w, vh / V.h)
end

local function Clamp(z, x, y)
	local vw, vh = ViewSize()
	z = max(ZoomMin(), min(ZOOM_MAX, z))
	local function axis(pos, size, view)
		if size <= view then return (view - size) / 2 end
		local margin = view * 0.25
		return max(view - size - margin, min(margin, pos))
	end
	return z, axis(x, V.w * z, vw), axis(y, V.h * z, vh)
end

local function SetView(z, x, y)
	local before = zoom
	zoom, ox, oy = Clamp(z, x, y)
	if zoom ~= before and ns.OnZoom then ns.OnZoom() end
	V.frame:SetScale(zoom)
	V.frame:ClearAllPoints()
	V.frame:SetPoint("TOPLEFT", child, "TOPLEFT", ox / zoom, -oy / zoom)
	dirty = true
end

-- Centre la vue sur un point du canevas.
local function CenterOn(x, y, z)
	local vw, vh = ViewSize()
	-- Le zoom borné avant de placer : sinon une petite zone (Dalaran) demandée au-delà du zoom
	-- maximal serait placée pour ce zoom-là, puis décentrée quand SetView le borne.
	z = max(ZoomMin(), min(ZOOM_MAX, z or zoom))
	SetView(z, vw / 2 - x * z, vh / 2 - y * z)
end

local function ZoomAt(z, mx, my)
	local ux, uy = (mx - ox) / zoom, (my - oy) / zoom
	SetView(z, mx - ux * z, my - uy * z)
end

local function Cursor()
	local s = child:GetEffectiveScale()
	local x, y = GetCursorPosition()
	return x / s - child:GetLeft(), child:GetTop() - y / s
end

local function SaveView()
	if not V then return end
	local vw, vh = ViewSize()
	ns.db.views[V.name] = { zoom, (vw / 2 - ox) / zoom, (vh / 2 - oy) / zoom }
	ns.db.lastView = V.name
end

--------------------------------------------------------------------------------
-- Mise à jour : ce qui est visible

local function Ramp(v, from, to)
	if v <= from then return 0 end
	if v >= to then return 1 end
	return (v - from) / (to - from)
end

local function UpdateLayers()
	local vw, vh = ViewSize()
	local x0, y0 = -ox / zoom, -oy / zoom
	local x1, y1 = x0 + vw / zoom, y0 + vh / zoom
	local now = GetTime()
	local reveal = not ns.db.fog

	for _, e in ipairs(V.zones) do
		local px = e.w * zoom
		local alpha
		if e.city then
			local fade = CITY_FADE_OF[e.file] or CITY_FADE
			alpha = Ramp(px, fade[1] * vw, fade[2] * vw)
		else
			alpha = Ramp(px, ZONE_MIN_PX, ZONE_MIN_PX * 1.6)
		end
		local visible = alpha > 0 and e.x < x1 and e.x + e.w > x0 and e.y < y1 and e.y + e.h > y0
		if visible then
			-- (brouillard changé : la zone n'a pas les bons morceaux)
			if e.loaded and e.reveal ~= reveal then UnloadZone(e) end
			if not e.loaded then LoadZone(e) end
			if e.hiddenAt then hidden = hidden - ZoneTextures(e) end
			e.hiddenAt = nil
			ShowAll(e.base, true)
			ShowAll(e.over, true)
			if e.alpha ~= alpha then
				SetFadeAll(e.base, alpha)
				SetFadeAll(e.over, alpha)
				e.alpha = alpha
			end
		elseif e.loaded and not e.hiddenAt then
			ShowAll(e.base, false)
			ShowAll(e.over, false)
			e.hiddenAt = now
			hidden = hidden + ZoneTextures(e)
		end
	end

	-- Trop de zones cachées encore chargées (déplacement rapide) : rendre les plus anciennes.
	while hidden > MAX_HIDDEN do
		local oldest
		for _, e in ipairs(V.zones) do
			if e.hiddenAt and (not oldest or e.hiddenAt < oldest.hiddenAt) then oldest = e end
		end
		if not oldest then break end
		UnloadZone(oldest)
	end

	local contAlpha = Ramp(zoom / ZoomMin(), CONT_FROM, CONT_FULL)
	local active
	if V.name == "outland" then
		active, contAlpha = 3, 1
	else
		active = ContinentAt((x0 + x1) / 2, (y0 + y1) / 2)
	end
	for cont, tiles in pairs(V.conts) do
		local show = cont == active and contAlpha > 0
		ShowAll(tiles, show)
		if show and tiles.alpha ~= contAlpha then
			SetFadeAll(tiles, contAlpha)
			tiles.alpha = contAlpha
		elseif not show then
			tiles.alpha = nil
		end
	end
	dirty = false
end

-- Préparation d'avance (#62) : le découpage d'une zone à son territoire (fond et morceaux) coûte
-- jusqu'à quelques ms, trop pour l'image où elle paraît. Carte ouverte, aux images sans
-- chargement, les zones les plus proches du centre de la vue sont préparées, un morceau après
-- l'autre, au plus WARM_MS ms par image. Une zone préparée paraît sans calcul.
local WARM_MS = 1.5
local function Warm()
	local t0 = debugprofilestop()
	local vw, vh = ViewSize()
	local cx, cy = (-ox + vw / 2) / zoom, (-oy + vh / 2) / zoom
	local reveal = not ns.db.fog
	while debugprofilestop() - t0 < WARM_MS do
		local e, best
		for _, z in ipairs(V.zones) do
			if z.readyFog ~= reveal or z.readyList ~= z.info.overlays then
				local dx, dy = z.x + z.w / 2 - cx, z.y + z.h / 2 - cy
				local d = dx * dx + dy * dy
				if not best or d < best then e, best = z, d end
			end
		end
		if not e then
			V.warmed = reveal
			return
		end
		if baseCells[e.file] == nil then
			BaseCells(e.file, e.city)
		else
			local list = reveal and Revealed(e.info) or e.info.overlays
			local i = 1
			while list[i] and list.cells and list.cells[i] do i = i + 1 end
			if list[i] then
				OverlayCells(list, i, e.file, e.info.c)
			else
				e.readyFog, e.readyList = reveal, e.info.overlays
			end
		end
	end
end

-- Toutes les zones de la vue sont-elles préparées ? (le banc attend la fin avant de mesurer)
function ns.Warmed()
	return V and V.warmed == not ns.db.fog
end

local function ReleaseHidden()
	local now = GetTime()
	for _, e in ipairs(V.zones) do
		if e.hiddenAt and now - e.hiddenAt > RELEASE_AFTER then
			UnloadZone(e)
		end
	end
end

--------------------------------------------------------------------------------
-- Icônes : joueur et groupe

local arrow
local members = {}

-- Tourne une texture carrée de a radians (sens inverse des aiguilles d'une montre).
-- math.cos / math.sin : les cos / sin globaux de WoW prennent des degrés.
local function Rotate(tex, a)
	local c, s = math.cos(a), math.sin(a)
	local function tc(x, y)
		return 0.5 + x * c + y * s, 0.5 + x * s - y * c
	end
	local ulx, uly = tc(-0.5, 0.5)
	local llx, lly = tc(-0.5, -0.5)
	local urx, ury = tc(0.5, 0.5)
	local lrx, lry = tc(0.5, -0.5)
	tex:SetTexCoord(ulx, uly, llx, lly, urx, ury, lrx, lry)
end
ns.RotateTexture = Rotate  -- aussi pour la flèche de guidage (Nav.lua)

-- Position à l'écran (dans child) d'un point d'une vue en yards ; nil si autre vue.
local function ToScreen(view, x, y)
	if view ~= V.name then return end
	return ox + x * V.k * zoom, oy + y * V.k * zoom
end

local function PlaceIcon(tex, sx, sy)
	tex:ClearAllPoints()
	tex:SetPoint("CENTER", pins, "TOPLEFT", sx, -sy)
	tex:Show()
end

local lastResync = 0

local function UpdatePins()
	local view, x, y = ns.UnitPos("player")
	if not view and not WorldMapFrame:IsShown() and GetTime() - lastResync > 2 then
		-- Une autre carte est sélectionnée (un autre addon) : revenir à celle du joueur.
		lastResync = GetTime()
		SetMapToCurrentZone()
		view, x, y = ns.UnitPos("player")
	end
	local sx, sy
	if view then sx, sy = ToScreen(view, x, y) end
	if sx then
		PlaceIcon(arrow, sx, sy)
		Rotate(arrow, GetPlayerFacing() or 0)
	else
		arrow:Hide()
	end

	local n = 0
	local raid = GetNumRaidMembers() > 0
	for i = 1, raid and 40 or 4 do
		local unit = raid and ("raid" .. i) or ("party" .. i)
		if UnitExists(unit) and not UnitIsUnit(unit, "player") then
			local uv, ux, uy = ns.UnitPos(unit)
			local mx, my
			if uv then mx, my = ToScreen(uv, ux, uy) end
			if mx then
				n = n + 1
				local tex = members[n]
				if not tex then
					tex = pins:CreateTexture(nil, "ARTWORK")
					tex:SetTexture("Interface\\WorldMap\\WorldMapPartyIcon")
					tex:SetWidth(16)
					tex:SetHeight(16)
					members[n] = tex
				end
				local _, class = UnitClass(unit)
				local color = class and RAID_CLASS_COLORS[class]
				if color then tex:SetVertexColor(color.r, color.g, color.b) else tex:SetVertexColor(1, 1, 1) end
				PlaceIcon(tex, mx, my)
			end
		end
	end
	-- Seulement celles affichées la fois d'avant : après un raid, 39 icônes déjà masquées
	-- le seraient encore 33 fois par seconde.
	for i = n + 1, members.shown or 0 do members[i]:Hide() end
	members.shown = n

	if view then
		local zone, zx, zy = ns.ZoneAt(view, x, y)
		if zone then
			playerText:SetFormattedText("|cffffd100%s|r  %s  %.1f, %.1f", L.YOU, zone, zx * 100, zy * 100)
		end
	else
		playerText:SetText("")
	end
end

local function UpdateHover()
	if not scroll:IsMouseOver() then
		hoverText:SetText("")
		return
	end
	local mx, my = Cursor()
	local x, y = (mx - ox) / zoom / V.k, (my - oy) / zoom / V.k
	hoverText:SetText(ns.ZoneText(V.name, x, y) or "")
end

--------------------------------------------------------------------------------
-- Affichage d'une vue

local function UpdateButtons()
	viewButton:SetText(V.name == "azeroth" and L.OUTLAND or L.AZEROTH)
	fogButton:SetText(ns.db.fog and L.FOG_ON or L.FOG_OFF)
end

local function ShowView(name, centerOnPlayer)
	if V then
		SaveView()
		if V.name ~= name then UnloadAll(V) end
		V.frame:Hide()
	end
	canvases[name] = canvases[name] or BuildCanvas(name)
	V = canvases[name]
	sea:SetTexture(SEA[name][1], SEA[name][2], SEA[name][3], 1)
	V.frame:Show()
	if ns.OnCanvas then ns.OnCanvas(V) end

	local view, x, y = ns.UnitPos("player")
	local saved = ns.db.views[name]
	if centerOnPlayer and view == name then
		CenterOn(x * V.k, y * V.k, saved and saved[1] or 6)
	elseif saved then
		CenterOn(saved[2], saved[3], saved[1])
	else
		CenterOn(V.w / 2, V.h / 2, ZoomMin())
	end
	UpdateButtons()
end

function ns.Refresh()
	if frame and frame:IsShown() then
		dirty = true
		UpdateButtons()
	end
end

function ns.Rebuild()
	if not V then return end
	local name = V.name
	SaveView()
	for _, c in pairs(canvases) do c.frame:Hide() end
	wipe(canvases)
	V = nil
	if frame:IsShown() then ShowView(name) end
end

-- Recharge les morceaux découverts d'une zone (après l'avoir explorée).
local function RefreshZone(info)
	for _, c in pairs(canvases) do
		for _, e in ipairs(c.zones) do
			if e.info == info and e.loaded then UnloadZone(e, c) end
		end
	end
	dirty = true
end

--------------------------------------------------------------------------------
-- Accès à la vue pour la mesure (Bench.lua)

ns.view = {}

function ns.view.Get()
	if not V then return end
	local vw, vh = ViewSize()
	return V.name, zoom, (vw / 2 - ox) / zoom, (vh / 2 - oy) / zoom, V.w, V.h
end

function ns.view.Show(name) ShowView(name) end
function ns.view.Center(x, y, z) CenterOn(x, y, z) end
function ns.view.Pan(dx, dy) SetView(zoom, ox + dx, oy + dy) end
function ns.view.ZoomMin() return ZoomMin() end
function ns.view.Size() return ViewSize() end
-- Le point sous le curseur : vue, et position en yards de la vue.
function ns.view.CursorPoint()
	local mx, my = Cursor()
	return V.name, (mx - ox) / zoom / V.k, (my - oy) / zoom / V.k
end
function ns.view.Frame() return frame end
function ns.view.Stop() drag, anim = nil, nil end

--------------------------------------------------------------------------------
-- La fenêtre

local function OnUpdate(self, elapsed)
	if drag then
		local mx, my = Cursor()
		SetView(zoom, drag.ox + mx - drag.x, drag.oy + my - drag.y)
	elseif anim then
		local z = zoom + (anim.target - zoom) * min(1, elapsed * 14)
		if abs(z - anim.target) < anim.target * 0.002 then
			z = anim.target
		end
		ZoomAt(z, anim.mx, anim.my)
		if z == anim.target or zoom ~= z then anim = nil end
	end

	self.layerWait = (self.layerWait or 0) - elapsed
	if dirty and self.layerWait <= 0 then
		if ns.measuring then
			local t = debugprofilestop()
			UpdateLayers()
			stats.layersMs = debugprofilestop() - t
		else
			UpdateLayers()
		end
		self.layerWait = 0.08
	elseif V.warmed ~= not ns.db.fog then
		Warm()
	end
	self.pinWait = (self.pinWait or 0) - elapsed
	if self.pinWait <= 0 then
		UpdatePins()
		UpdateHover()
		self.pinWait = 0.03
	end
	self.releaseWait = (self.releaseWait or 0) - elapsed
	if self.releaseWait <= 0 then
		ReleaseHidden()
		self.releaseWait = 2
	end
end

local function Button(text, width)
	local b = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	b:SetWidth(width)
	b:SetHeight(22)
	b:SetText(text)
	return b
end

local function CreateWindow()
	local db = ns.db
	frame = CreateFrame("Frame", "StrataFrame", UIParent)
	frame:SetWidth(db.w)
	frame:SetHeight(db.h)
	if db.point then
		frame:SetPoint(db.point[1], UIParent, db.point[1], db.point[2], db.point[3])
	else
		frame:SetPoint("CENTER")
	end
	frame:SetFrameStrata("HIGH")
	frame:SetToplevel(true)
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:SetResizable(true)
	frame:SetMinResize(600, 340)
	frame:EnableMouse(true)
	frame:SetBackdrop({
		bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
		edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
		tile = true, tileSize = 32, edgeSize = 24,
		insets = { left = 6, right = 6, top = 6, bottom = 6 },
	})
	frame:Hide()
	tinsert(UISpecialFrames, "StrataFrame")

	local title = CreateFrame("Frame", nil, frame)
	title:SetPoint("TOPLEFT", 8, -6)
	title:SetPoint("TOPRIGHT", -58, -6)
	title:SetHeight(22)
	title:EnableMouse(true)
	title:RegisterForDrag("LeftButton")
	title:SetScript("OnDragStart", function()
		if not db.fullscreen then frame:StartMoving() end
	end)
	title:SetScript("OnDragStop", function()
		frame:StopMovingOrSizing()
		local point, _, _, x, y = frame:GetPoint()
		db.point = { point, x, y }
	end)
	local titleText = title:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	titleText:SetPoint("LEFT", 6, -2)
	titleText:SetText("Strata")
	title:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:AddLine("Strata " .. ns.version)
		GameTooltip:AddLine(L.CREATED_BY, 1, 1, 1)
		GameTooltip:Show()
	end)
	title:SetScript("OnLeave", function() GameTooltip:Hide() end)
	playerText = title:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	playerText:SetPoint("LEFT", titleText, "RIGHT", 16, 0)

	local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", -2, -2)

	scroll = CreateFrame("ScrollFrame", nil, frame)
	scroll:SetPoint("TOPLEFT", 12, -30)
	scroll:SetPoint("BOTTOMRIGHT", -12, 36)
	child = CreateFrame("Frame", nil, scroll)
	child:SetWidth(1)
	child:SetHeight(1)
	scroll:SetScrollChild(child)
	sea = child:CreateTexture(nil, "BACKGROUND")
	sea:SetAllPoints(child)
	sea:SetTexture(SEA.azeroth[1], SEA.azeroth[2], SEA.azeroth[3], 1)

	pins = CreateFrame("Frame", nil, child)
	pins:SetAllPoints(child)
	pins:SetFrameLevel(child:GetFrameLevel() + 30)   -- au-dessus des couches du canevas (une vingtaine)
	arrow = pins:CreateTexture(nil, "OVERLAY")
	arrow:SetTexture("Interface\\Minimap\\MinimapArrow")
	arrow:SetWidth(32)
	arrow:SetHeight(32)

	scroll:SetScript("OnSizeChanged", function(self, w, h)
		local vw, vh = child:GetWidth(), child:GetHeight()
		child:SetWidth(w)
		child:SetHeight(h)
		if V then
			-- Garder le même centre.
			local cx, cy = (vw / 2 - ox) / zoom, (vh / 2 - oy) / zoom
			CenterOn(cx, cy)
		end
	end)
	scroll:EnableMouse(true)
	scroll:EnableMouseWheel(true)
	scroll:SetScript("OnMouseWheel", function(self, delta)
		if ns.benching then return end
		local mx, my = Cursor()
		local target = (anim and anim.target or zoom) * ZOOM_STEP ^ delta
		anim = { target = max(ZoomMin(), min(ZOOM_MAX, target)), mx = mx, my = my }
	end)
	scroll:SetScript("OnMouseDown", function(self, button)
		if ns.benching then return end
		if button == "LeftButton" and IsControlKeyDown() then
			ns.AddPin(ns.view.CursorPoint())
		elseif button == "LeftButton" then
			local mx, my = Cursor()
			anim = nil
			drag = { x = mx, y = my, ox = ox, oy = oy }
		elseif button == "RightButton" then
			local mx, my = Cursor()
			anim = { target = max(ZoomMin(), zoom / 2), mx = mx, my = my }
		end
	end)
	scroll:SetScript("OnMouseUp", function(self, button)
		if button == "LeftButton" then drag = nil end
	end)

	local grip = CreateFrame("Button", nil, frame)
	grip:SetWidth(16)
	grip:SetHeight(16)
	grip:SetPoint("BOTTOMRIGHT", -6, 6)
	grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
	grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
	grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
	grip:SetScript("OnMouseDown", function() frame:StartSizing("BOTTOMRIGHT") end)
	grip:SetScript("OnMouseUp", function()
		frame:StopMovingOrSizing()
		db.w, db.h = frame:GetWidth(), frame:GetHeight()
		local point, _, _, x, y = frame:GetPoint()
		db.point = { point, x, y }
	end)
	grip.isSizeGrip = true

	-- Plein écran : la fenêtre couvre UIParent ; sa taille et sa position (db.w, db.h, db.point)
	-- restent celles de la fenêtre, pour y revenir à l'identique. La carte garde son centre
	-- (OnSizeChanged du ScrollFrame).
	local fullscreen = CreateFrame("Button", nil, frame)
	fullscreen:SetWidth(32)
	fullscreen:SetHeight(32)
	fullscreen:SetPoint("RIGHT", close, "LEFT", 8, 0)
	fullscreen:SetHighlightTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight", "ADD")
	fullscreen.isFullscreenButton = true
	local function ApplyFullscreen()
		frame:ClearAllPoints()
		if db.fullscreen then
			frame:SetAllPoints(UIParent)
			grip:Hide()
			fullscreen:SetNormalTexture("Interface\\Buttons\\UI-Panel-SmallerButton-Up")
			fullscreen:SetPushedTexture("Interface\\Buttons\\UI-Panel-SmallerButton-Down")
		else
			frame:SetWidth(db.w)
			frame:SetHeight(db.h)
			if db.point then
				frame:SetPoint(db.point[1], UIParent, db.point[1], db.point[2], db.point[3])
			else
				frame:SetPoint("CENTER")
			end
			grip:Show()
			fullscreen:SetNormalTexture("Interface\\Buttons\\UI-Panel-BiggerButton-Up")
			fullscreen:SetPushedTexture("Interface\\Buttons\\UI-Panel-BiggerButton-Down")
		end
	end
	function ns.ToggleFullscreen()
		db.fullscreen = not db.fullscreen
		ApplyFullscreen()
	end
	fullscreen:SetScript("OnClick", function(self)
		ns.ToggleFullscreen()
		if GameTooltip:IsOwned(self) then self:GetScript("OnEnter")(self) end
	end)
	fullscreen:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:AddLine(db.fullscreen and L.WINDOWED or L.FULLSCREEN)
		GameTooltip:Show()
	end)
	fullscreen:SetScript("OnLeave", function() GameTooltip:Hide() end)
	ApplyFullscreen()

	local me = Button(L.ME, 60)
	me:SetPoint("BOTTOMLEFT", 12, 10)
	me:SetScript("OnClick", function()
		local view, x, y = ns.UnitPos("player")
		if not view then
			ns.Print(L.NO_POSITION)
			return
		end
		if view ~= V.name then ShowView(view) end
		CenterOn(x * V.k, y * V.k, max(zoom, 6))
	end)
	viewButton = Button(L.OUTLAND, 90)
	viewButton:SetPoint("LEFT", me, "RIGHT", 4, 0)
	viewButton:SetScript("OnClick", function()
		ShowView(V.name == "azeroth" and "outland" or "azeroth")
	end)
	fogButton = Button(L.FOG_ON, 120)
	fogButton:SetPoint("LEFT", viewButton, "RIGHT", 4, 0)
	fogButton:SetScript("OnClick", function()
		db.fog = not db.fog
		ns.Refresh()
	end)
	-- La zone survolée, à droite de la barre de titre (la barre du bas porte la recherche).
	hoverText = title:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	hoverText:SetPoint("RIGHT", title, "RIGHT", -4, -2)
	hoverText:SetJustifyH("RIGHT")
	ns.CreateSearch(frame, fogButton)
	ns.CreatePinsUI(frame)

	frame:SetScript("OnUpdate", function(self, elapsed)
		if not ns.measuring then return OnUpdate(self, elapsed) end
		local t = debugprofilestop()
		OnUpdate(self, elapsed)
		local ms = debugprofilestop() - t
		stats.frames, stats.ms = stats.frames + 1, stats.ms + ms
		if ms > stats.worst then stats.worst = ms end
	end)
	frame:SetScript("OnHide", function()
		SaveView()
		-- Carte fermée : les zones ne servent plus, leurs textures sont rendues tout de suite.
		for _, c in pairs(canvases) do UnloadAll(c) end
		dirty = true
		drag, anim = nil, nil
		if not WorldMapFrame:IsShown() then SetMapToCurrentZone() end
	end)
end

function ns.Open()
	if not frame then CreateWindow() end
	if WorldMapFrame:IsShown() then HideUIPanel(WorldMapFrame) end
	if not ns.scanned then
		ns.Scan()
	else
		local info = ns.RescanCurrent()
		if info then RefreshZone(info) end
	end
	frame:Show()
	child:SetWidth(scroll:GetWidth())
	child:SetHeight(scroll:GetHeight())
	local view = ns.UnitPos("player")
	ShowView(view or ns.db.lastView or "azeroth", view ~= nil)
end

function ns.Toggle()
	if frame and frame:IsShown() then
		frame:Hide()
	else
		ns.Open()
	end
end

function ns.OnZoneChanged()
	if frame and frame:IsShown() then
		local info = ns.RescanCurrent()
		if info then RefreshZone(info) end
	end
end
