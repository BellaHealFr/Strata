-- Copyright (C) 2026 BellaHealFr. Licence GPL-3.0-only avec conditions supplémentaires
-- (mention de l'auteur, nom « Strata » réservé) : voir LICENSE et NOTICE.md.

-- Scénario de performance : le travail demandé par chaque situation, comparé aux budgets de
-- tests/budgets.lua. « ops » = centaines d'instructions Lua (client simulé compris).

local ns = Strata

TEST.Fire("ADDON_LOADED", "Strata")

local scroll, child
local function view()
	scroll = scroll or find(StrataFrame, function(r) return r.kind == "ScrollFrame" end)
	child = child or scroll.scrollChild
	return scroll, child
end

-- 1. Ouverture : lecture de toutes les cartes, construction du canevas, centrage sur le joueur.
local open = measure(function() Strata_Toggle() end)
budget("ouverture.ops", open.ops)
budget("ouverture.SetMapZoom", open.SetMapZoom)
budget("ouverture.CreateTexture", open.CreateTexture)
tick(1)

-- 2. Carte ouverte, immobile : seules les icônes vivent.
local mean, peak = measureFrames(150)
budget("immobile.ops par image", mean.ops)
budget("immobile.SetTexture par image", mean.SetTexture)
budget("immobile.SetMapToCurrentZone par image", mean.SetMapToCurrentZone)

-- 3. Déplacement : glisser la carte de 3 px par image pendant 4 s.
view()
TEST.cursor = { 500, 400 }
scroll.scripts.OnMouseDown(scroll, "LeftButton")
mean, peak = measureFrames(200, function(i) TEST.cursor = { 500 - 3 * i, 400 - i } end)
scroll.scripts.OnMouseUp(scroll, "LeftButton")
budget("déplacement.ops par image (moyenne)", mean.ops)
budget("déplacement.ops par image (pire)", peak.ops)
budget("déplacement.SetScale par image", mean.SetScale)
tick(1)

-- 4. Zoom animé : cinq crans de molette, puis l'animation jusqu'au bout.
mean, peak = measureFrames(100, function(i)
	if i <= 5 then scroll.scripts.OnMouseWheel(scroll, 1) end
end)
budget("zoom.ops par image (moyenne)", mean.ops)
budget("zoom.ops par image (pire)", peak.ops)
tick(1)

-- 5. Tour d'Azeroth vers le zoom 6 : la mémoire doit rester bornée et être rendue ensuite.
for _ = 1, 5 do scroll.scripts.OnMouseWheel(scroll, -1) end
tick(2)
local vw, vh = child.w, child.h
local ns_canvas_w = 1000
local function centerOn(x, y)
	-- Glisser la carte pour amener le point (en unités du canevas) au centre de la vue.
	local s = child:GetEffectiveScale()
	scroll.scripts.OnMouseDown(scroll, "LeftButton")
	TEST.cursor = { 100 + vw / 2, 900 - vh / 2 }
	frame()
	-- La position courante de l'origine se lit sur l'ancrage du canevas.
	local canvas
	for _, c in ipairs(child.children) do
		if c.kind == "Frame" and c:IsShown() and c.scale ~= 1 then canvas = c end
	end
	local zoom = canvas.scale
	local ox, oy = canvas.point[2] * zoom, -canvas.point[3] * zoom
	local dx, dy = vw / 2 - (ox + x * zoom), vh / 2 - (oy + y * zoom)
	TEST.cursor = { 100 + vw / 2 + dx, 900 - vh / 2 - dy }
	frame()
	scroll.scripts.OnMouseUp(scroll, "LeftButton")
	tick(0.2)
end
-- Les icônes de maîtres de vol créées en route (une par maître de vol, une seule fois) sont
-- comptées à part des tuiles de carte, dont on vérifie qu'elles sont réutilisées.
local function flightIcons(r, n)
	n = n or 0
	if r.fm then n = n + 1 end
	for _, c in ipairs(r.children) do n = flightIcons(c, n) end
	return n
end
local iconsBefore = flightIcons(StrataFrame)
local maxLoaded = 0
local tour = measure(function()
	for gy = 0.1, 0.9, 0.2 do
		for gx = 0.05, 0.95, 0.1 do
			centerOn(gx * ns_canvas_w, gy * 667)
			maxLoaded = math.max(maxLoaded, loadedMapTiles(StrataFrame))
		end
	end
end)
budget("tour.textures chargées (pire moment)", maxLoaded)
local icons = flightIcons(StrataFrame) - iconsBefore
budget("tour.CreateTexture", tour.CreateTexture - icons)
budget("tour.icônes de vol créées", flightIcons(StrataFrame))
TEST.time = TEST.time + 20
tick(3)
budget("tour.textures chargées après 20 s", loadedMapTiles(StrataFrame))

-- 6. Raid de 40 : 39 icônes à placer.
TEST.raid = 40
mean = measureFrames(150)
budget("raid 40.ops par image", mean.ops)
budget("raid 40.GetPlayerMapPosition par image", mean.GetPlayerMapPosition)
TEST.raid = 0

-- Après le raid, la carte immobile doit retrouver son coût : en 0.1.0, les 39 icônes déjà
-- masquées l'étaient encore à chaque mise à jour.
mean = measureFrames(150)
budget("après raid.ops par image", mean.ops)

-- 6 a. Recherche de zone (#6) : 100 appels sur le joueur, et le survol réel de la carte.
local zx, zy = select(2, ns.UnitPos("player")), select(3, ns.UnitPos("player"))
local lookups = measure(function() for _ = 1, 100 do ns.ZoneAt("azeroth", zx, zy) end end)
budget("ZoneAt.ops pour 100 appels", lookups.ops)
TEST.mouseOver = true
mean = measureFrames(150)
budget("survol.ops par image", mean.ops)
TEST.mouseOver = nil

-- 6 c. Recherche (#1) : le coût d'une frappe, en tapant « nagrand » lettre par lettre.
local typing = measure(function()
	local word = "nagrand"
	for i = 1, #word do
		StrataSearchBox.text = word:sub(1, i)
		StrataSearchBox.scripts.OnTextChanged(StrataSearchBox, true)
	end
end)
budget("recherche.ops par frappe", typing.ops / 7)
StrataSearchBox.scripts.OnEscapePressed(StrataSearchBox)

-- 6 d. Épingles (#2) : 200 épingles sur Azeroth. Un déplacement ne doit coûter aucun travail
-- par épingle (elles sont sur le canevas) ; un zoom les redimensionne.
ns.db.pins = {}
for i = 1, 200 do
	ns.db.pins[i] = { view = "azeroth", x = 5000 + (i % 20) * 1500, y = 6000 + math.floor(i / 20) * 2000, note = "", icon = 1 + i % 8 }
end
local render = measure(function() ns.view.Show("outland") ns.view.Show("azeroth") end)
budget("200 épingles.affichage (changement de vue)", render.ops)
mean = measureFrames(150)
budget("200 épingles.immobile.ops par image", mean.ops)
TEST.cursor = { 500, 400 }
scroll.scripts.OnMouseDown(scroll, "LeftButton")
mean = measureFrames(100, function(i) TEST.cursor = { 500 - 3 * i, 400 - i } end)
scroll.scripts.OnMouseUp(scroll, "LeftButton")
budget("200 épingles.déplacement.ops par image (moyenne)", mean.ops)
budget("200 épingles.déplacement.SetPoint par image", mean.SetPoint)
mean, peak = measureFrames(60, function(i) if i <= 3 then scroll.scripts.OnMouseWheel(scroll, 1) end end)
budget("200 épingles.zoom.ops par image (moyenne)", mean.ops)
ns.db.pins = {}
ns.view.Show("outland") ns.view.Show("azeroth")
tick(1)

-- 6 bis. Compteur à l'écran : son coût quand il est affiché, et aucun coût une fois masqué.
SlashCmdList.STRATA("debug")
mean = measureFrames(150)
budget("compteur affiché.ops par image", mean.ops)
budget("compteur affiché.UpdateAddOnMemoryUsage en 3 s", mean.UpdateAddOnMemoryUsage * 150)
SlashCmdList.STRATA("debug")
mean = measureFrames(150)
budget("compteur masqué.ops par image", mean.ops)

-- 6 ter. Vue Outreterre : les zones d'Azeroth quittées sont rendues (#22). Restent la carte du
-- monde et celles des continents (4 x 12 tuiles).
local azeroth
for _, c in ipairs(child.children) do
	if c.kind == "Frame" and c:IsShown() and c.scale ~= 1 then azeroth = c end
end
local function viewButton(label)
	return find(StrataFrame, function(r) return r.kind == "Button" and r.text == label end)
end
-- Des zones chargées à l'écran (sur le joueur) au moment de changer de vue.
viewButton(ns.L.ME).scripts.OnClick()
tick(0.5)
check(loadedTextures(azeroth) > 100, "zones d'Azeroth chargées avant de changer de vue : " .. loadedTextures(azeroth))
viewButton(ns.L.OUTLAND).scripts.OnClick()
tick(1)
budget("vue Outreterre.textures gardées pour Azeroth", loadedMapTiles(azeroth))
viewButton(ns.L.AZEROTH).scripts.OnClick()
tick(1)

-- 6 e. Flèche de guidage (#38) : son coût par image pendant un guidage, carte fermée. Une fois
-- arrêtée, plus rien ne tourne (budgets « fermée » plus bas).
local _, gx, gy = ns.UnitPos("player")
Strata_Toggle()
ns.Follow("azeroth", gx + 300, gy - 400, "Cible")
mean = measureFrames(150)
budget("guidage.ops par image (carte fermée)", mean.ops)
ns.StopFollow()
Strata_Toggle()

-- 7. Carte fermée : rien ne doit tourner, même en changeant de zone, et les textures des zones
-- sont rendues (#22).
Strata_Toggle()
-- Les tuiles de carte (compteur de Map.lua) : les icônes du joueur et du groupe partagent un
-- seul petit fichier et ne comptent pas ici.
budget("fermée.tuiles de carte chargées", ns.stats.textures)
mean = measureFrames(150)
budget("fermée.ops par image", mean.ops)
local zone = measure(function() TEST.Fire("ZONE_CHANGED_NEW_AREA") end)
budget("fermée.ops changement de zone", zone.ops)

-- 8. Réouverture : les zones rendues à la fermeture se rechargent (#22). Coût d'une ouverture
-- et de la première image.
local reopen = measure(function() Strata_Toggle() frame() end)
budget("réouverture.ops", reopen.ops)
budget("réouverture.SetTexture", reopen.SetTexture)
Strata_Toggle()

check(not TEST.failed, (TEST.failed or 0) .. " budget(s) dépassé(s)")
