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
local maxLoaded = 0
local tour = measure(function()
	for gy = 0.1, 0.9, 0.2 do
		for gx = 0.05, 0.95, 0.1 do
			centerOn(gx * ns_canvas_w, gy * 667)
			maxLoaded = math.max(maxLoaded, loadedTextures(StrataFrame))
		end
	end
end)
budget("tour.textures chargées (pire moment)", maxLoaded)
budget("tour.CreateTexture", tour.CreateTexture)
TEST.time = TEST.time + 20
tick(3)
budget("tour.textures chargées après 20 s", loadedTextures(StrataFrame))

-- 6. Raid de 40 : 39 icônes à placer.
TEST.raid = 40
mean = measureFrames(150)
budget("raid 40.ops par image", mean.ops)
budget("raid 40.GetPlayerMapPosition par image", mean.GetPlayerMapPosition)
TEST.raid = 0

-- 7. Carte fermée : rien ne doit tourner, même en changeant de zone.
Strata_Toggle()
mean = measureFrames(150)
budget("fermée.ops par image", mean.ops)
local zone = measure(function() TEST.Fire("ZONE_CHANGED_NEW_AREA") end)
budget("fermée.ops changement de zone", zone.ops)

check(not TEST.failed, (TEST.failed or 0) .. " budget(s) dépassé(s)")
