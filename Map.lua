-- Copyright (C) 2026 BellaHealFr. Licence GPL-3.0-only avec conditions supplémentaires
-- (mention de l'auteur, nom « Strata » réservé) : voir LICENSE et NOTICE.md.

-- Strata - Carte du monde continue pour World of Warcraft 3.3.5
-- La fenêtre et la carte assemblée.
--
-- Chaque vue a un canevas de UNITS unités de large (1 unité = 1/k yard). Le canevas est mis à
-- l'échelle (zoom) et placé dans un ScrollFrame qui le rogne. Couches, de bas en haut :
--   world : la carte du monde de Blizzard (vue Azeroth)
--   cont  : la carte du continent sous le centre de la vue, en fondu avec le zoom
--   base  : le fond de chaque zone (12 tuiles, comme WorldMapDetailFrame : 1002 x 668 px)
--   over  : les morceaux découverts de chaque zone (GetMapOverlayInfo)
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

local frame, scroll, child, pins, hoverText, playerText, viewButton, fogButton
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

-- Les 12 tuiles d'une carte (prefix1 .. prefix12) sur un rectangle en unités ; feather : bord
-- adouci. Chaque morceau garde sa place sur la carte (tex.cell, en px) et son dégradé (tex.fade).
local function AddMapTiles(list, layer, prefix, rx, ry, rw, rh, feather)
	local sx, sy = rw / MAP_W, rh / MAP_H
	local left, rowStart
	for _, cell in ipairs(feather and GRID.feather or GRID.plain) do
		local tex = Acquire(layer)
		if cell.rowStart then left = nil end
		PlaceTile(tex, layer, left, not left and rowStart, rx, ry, (cell[3] - cell[1]) * sx, (cell[4] - cell[2]) * sy,
			cell.u0, cell.u1, cell.v0, cell.v1)
		if cell.rowStart then rowStart = tex end
		tex.cell, tex.fade = cell, cell.fade
		SetFile(tex, prefix .. cell.tile)
		list[#list + 1] = tex
		left = tex
	end
end

-- La taille du fichier d'une tuile de bord : la puissance de 2 qui la contient (WorldMapFrame_Update).
local function FileSize(px)
	local size = 16
	while size < px do size = size * 2 end
	return size
end

-- Les morceaux découverts d'une zone, découpés en tuiles de 256 px comme Blizzard.
local function AddOverlays(list, layer, overlays, rx, ry, rw, rh)
	local sx, sy = rw / MAP_W, rh / MAP_H
	for _, o in ipairs(overlays) do
		local name, tw, th, offX, offY = o[1], o[2], o[3], o[4], o[5]
		local wide, tall = ceil(tw / 256), ceil(th / 256)
		local first = #list
		for j = 1, tall do
			local ph, fh = 256, 256
			if j == tall then
				ph = th % 256
				if ph == 0 then ph = 256 end
				fh = FileSize(ph)
			end
			for k = 1, wide do
				local pw, fw = 256, 256
				if k == wide then
					pw = tw % 256
					if pw == 0 then pw = 256 end
					fw = FileSize(pw)
				end
				local tex = Acquire(layer)
				local n = (j - 1) * wide + k
				PlaceTile(tex, layer, k > 1 and list[first + n - 1], j > 1 and list[first + n - wide],
					rx + offX * sx, ry + offY * sy, pw * sx, ph * sy,
					0.5 / fw, (pw - 0.5) / fw, 0.5 / fh, (ph - 0.5) / fh)
				SetFile(tex, name .. n)
				list[#list + 1] = tex
			end
		end
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
			0, 0, c.w, c.h)
	end

	for _, cont in ipairs(view.continents) do
		local C = Zones[cont]
		local bx, by = 0, 0
		if C.parent == 0 then bx, by = C.x, C.y end
		local map = ns.maps[cont]
		if map and map.file then
			local tiles = {}
			AddMapTiles(tiles, c.layers.cont, "Interface\\WorldMap\\" .. map.file .. "\\" .. map.file,
				bx * k, by * k, C.w * k, C.h * k)
			ShowAll(tiles, false)
			c.conts[cont] = tiles
		end
	end
	return c
end

local function LoadZone(e)
	local L = V.layers
	e.base = {}
	AddMapTiles(e.base, e.city and L.city or L.base[e.depth], e.info.prefix, e.x, e.y, e.w, e.h, true)
	e.over = {}
	AddOverlays(e.over, L.over, e.info.overlays, e.x, e.y, e.w, e.h)
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
	local fog = ns.db.fog

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
			if not e.loaded then LoadZone(e) end
			if e.hiddenAt then hidden = hidden - ZoneTextures(e) end
			e.hiddenAt = nil
			ShowAll(e.base, fog or e.city)
			ShowAll(e.over, true)
			if e.alpha ~= alpha then
				SetFadeAll(e.base, alpha)
				SetAlphaAll(e.over, alpha)
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
		if show then SetAlphaAll(tiles, contAlpha) end
	end
	dirty = false
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
	local sea = child:CreateTexture(nil, "BACKGROUND")
	sea:SetAllPoints(child)
	sea:SetTexture(0.07, 0.12, 0.16, 1)

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
