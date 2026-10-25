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
--   city  : les villes, entièrement peintes, au-dessus de leurs voisines
-- Les zones ne chargent leurs textures que visibles et assez grandes à l'écran, et les rendent
-- quelques secondes après avoir quitté la vue (client 32 bits : la mémoire compte).
-- Les icônes (joueur, groupe) sont sur un cadre non mis à l'échelle : elles gardent leur taille.

local _, ns = ...

local Zones = ns.Zones
local L = ns.L

local UNITS = 1000
local MAP_W, MAP_H = 1002, 668      -- la partie utile des 4 x 3 tuiles de 256 px
local LAYERS = { "world", "cont", "base", "over", "city" }

local ZOOM_MAX = 40
local ZOOM_STEP = 1.3
local ZONE_MIN_PX, CITY_MIN_PX = 220, 90   -- largeur à l'écran où une zone commence à paraître
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
ns.stats = { textures = 0, zones = 0, frames = 0, ms = 0, worst = 0, layersMs = 0 }
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

local function Release(layer, tex)
	tex:SetTexture(nil)
	tex:Hide()
	tex:ClearAllPoints()
	tinsert(layer.pool, tex)
	stats.textures = stats.textures - 1
end

local function Place(tex, layer, x, y, w, h, u, v)
	tex:ClearAllPoints()
	tex:SetPoint("TOPLEFT", layer, "TOPLEFT", x, -y)
	tex:SetWidth(w)
	tex:SetHeight(h)
	tex:SetTexCoord(0, u, 0, v)
end

-- Les 12 tuiles d'une carte (prefix1 .. prefix12) sur un rectangle en unités.
local function AddMapTiles(list, layer, prefix, rx, ry, rw, rh)
	local sx, sy = rw / MAP_W, rh / MAP_H
	for i = 1, 12 do
		local col, row = (i - 1) % 4, floor((i - 1) / 4)
		local px, py = col * 256, row * 256
		local pw, ph = min(256, MAP_W - px), min(256, MAP_H - py)
		local tex = Acquire(layer)
		Place(tex, layer, rx + px * sx, ry + py * sy, pw * sx, ph * sy, pw / 256, ph / 256)
		tex:SetTexture(prefix .. i)
		list[#list + 1] = tex
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
				Place(tex, layer, rx + (offX + 256 * (k - 1)) * sx, ry + (offY + 256 * (j - 1)) * sy,
					pw * sx, ph * sy, pw / fw, ph / fh)
				tex:SetTexture(name .. ((j - 1) * wide + k))
				list[#list + 1] = tex
			end
		end
	end
end

local function SetAlphaAll(list, alpha)
	for i = 1, #list do list[i]:SetAlpha(alpha) end
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
		zones = {}, conts = {},
	}
	c.frame = CreateFrame("Frame", nil, child)
	c.frame:SetWidth(c.w)
	c.frame:SetHeight(c.h)
	c.layers = {}
	for i, layerName in ipairs(LAYERS) do
		local layer = CreateFrame("Frame", nil, c.frame)
		layer:SetAllPoints(c.frame)
		layer:SetFrameLevel(c.frame:GetFrameLevel() + i)
		layer.pool = {}
		c.layers[layerName] = layer
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
		for file, Z in pairs(C.zones) do
			local info = map and map.zones[file]
			if not Z[5] and info then
				c.zones[#c.zones + 1] = {
					info = info, city = ns.CITIES[file],
					x = (bx + Z[3]) * k, y = (by + Z[4]) * k, w = Z[1] * k, h = Z[2] * k,
				}
			end
		end
	end
	-- Les grandes d'abord : à alpha égal, une petite zone posée après reste lisible.
	sort(c.zones, function(a, b) return a.w * a.h > b.w * b.h end)
	return c
end

local function LoadZone(e)
	local L = V.layers
	e.base = {}
	AddMapTiles(e.base, e.city and L.city or L.base, e.info.prefix, e.x, e.y, e.w, e.h)
	e.over = {}
	AddOverlays(e.over, L.over, e.info.overlays, e.x, e.y, e.w, e.h)
	e.loaded = true
	stats.zones = stats.zones + 1
end

local function ZoneTextures(e)
	return #e.base + #e.over
end

-- Rend les textures d'une zone ; c : son canevas (celui affiché par défaut).
local function UnloadZone(e, c)
	local L = (c or V).layers
	if e.hiddenAt then hidden = hidden - ZoneTextures(e) end
	ReleaseAll(e.city and L.city or L.base, e.base)
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
	zoom, ox, oy = Clamp(z, x, y)
	V.frame:SetScale(zoom)
	V.frame:ClearAllPoints()
	V.frame:SetPoint("TOPLEFT", child, "TOPLEFT", ox / zoom, -oy / zoom)
	dirty = true
end

-- Centre la vue sur un point du canevas.
local function CenterOn(x, y, z)
	local vw, vh = ViewSize()
	z = z or zoom
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
		local minPx = e.city and CITY_MIN_PX or ZONE_MIN_PX
		local alpha = Ramp(px, minPx, minPx * 1.6)
		local visible = alpha > 0 and e.x < x1 and e.x + e.w > x0 and e.y < y1 and e.y + e.h > y0
		if visible then
			if not e.loaded then LoadZone(e) end
			if e.hiddenAt then hidden = hidden - ZoneTextures(e) end
			e.hiddenAt = nil
			ShowAll(e.base, fog or e.city)
			ShowAll(e.over, true)
			SetAlphaAll(e.base, alpha)
			SetAlphaAll(e.over, alpha)
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
	local zone, zx, zy = ns.ZoneAt(V.name, x, y)
	if zone then
		hoverText:SetFormattedText("%s  %.1f, %.1f", zone, zx * 100, zy * 100)
	else
		hoverText:SetText("")
	end
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
	frame:SetMinResize(480, 340)
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
	title:SetPoint("TOPRIGHT", -32, -6)
	title:SetHeight(22)
	title:EnableMouse(true)
	title:RegisterForDrag("LeftButton")
	title:SetScript("OnDragStart", function() frame:StartMoving() end)
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
	pins:SetFrameLevel(child:GetFrameLevel() + 20)
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
		if button == "LeftButton" then
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
	hoverText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	hoverText:SetPoint("BOTTOMRIGHT", -28, 15)
	hoverText:SetJustifyH("RIGHT")

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
