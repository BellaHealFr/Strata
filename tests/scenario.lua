-- Copyright (C) 2026 BellaHealFr. Licence GPL-3.0-only avec conditions supplémentaires
-- (mention de l'auteur, nom « Strata » réservé) : voir LICENSE et NOTICE.md.

-- Scénario hors jeu : ouvrir la carte, zoomer, déplacer, changer de vue, fermer.
-- Chaque vérification qui échoue lève une erreur (le runner l'affiche et sort en échec).

local ns = Strata

local function find(region, test)
	if test(region) then return region end
	for _, c in ipairs(region.children) do
		local r = find(c, test)
		if r then return r end
	end
end

local function visibleTextures(region, n)
	n = n or 0
	if region.kind == "Texture" and region:IsVisible() and region.path then n = n + 1 end
	for _, c in ipairs(region.children) do n = visibleTextures(c, n) end
	return n
end

local function tick(seconds)
	local t = 0
	while t < seconds do
		TEST.time = TEST.time + 0.02
		t = t + 0.02
		local f = StrataFrame
		if f and f:IsVisible() and f.scripts.OnUpdate then f.scripts.OnUpdate(f, 0.02) end
	end
end

local function check(cond, msg)
	if not cond then error("ÉCHEC : " .. msg, 2) end
	print("ok   " .. msg)
end

-- Chargement
TEST.Fire("ADDON_LOADED", "Strata")
check(ns.db and ns.db.fog == true, "réglages initialisés")

-- Ouverture : lit toutes les cartes, centre sur le joueur
Strata_Toggle()
check(StrataFrame:IsShown(), "la fenêtre s'ouvre")
check(ns.scanned, "les cartes du client sont lues")
local nZones = 0
for _, m in pairs(ns.maps) do for _ in pairs(m.zones) do nZones = nZones + 1 end end
check(nZones == 73, "zones lues : " .. nZones .. " (24 Kalimdor, 29 Royaumes de l'Est, 8 Outreterre, 12 Norfendre)")
tick(0.5)

local scroll = find(StrataFrame, function(r) return r.kind == "ScrollFrame" end)
local child = scroll.scrollChild
local arrow = find(StrataFrame, function(r) return r.path == "Interface\\Minimap\\MinimapArrow" end)
check(arrow:IsVisible(), "flèche du joueur affichée")
local _, ax, ay = unpack(arrow.point)
check(math.abs(ax - child.w / 2) < 1 and math.abs(-ay - child.h / 2) < 1,
	format("flèche au centre de la vue (%.1f, %.1f) / (%.1f, %.1f)", ax, -ay, child.w / 2, child.h / 2))
check(arrow.texcoord and #arrow.texcoord == 8, "flèche tournée")
local party = find(StrataFrame, function(r) return r.path == "Interface\\WorldMap\\WorldMapPartyIcon" end)
check(party and party:IsVisible(), "membre du groupe affiché")

local title = find(StrataFrame, function(r) return r.kind == "FontString" and r.text and r.text:find("Elwynn") end)
check(title ~= nil, "zone du joueur dans le titre : " .. (title and title.text or "?"))

local n1 = visibleTextures(StrataFrame)
check(n1 > 12, "textures visibles au zoom de départ : " .. n1)

-- Zoom arrière complet : seules les cartes du monde et du continent restent
for _ = 1, 30 do scroll.scripts.OnMouseWheel(scroll, -1) tick(0.1) end
tick(0.5)
local nOut = visibleTextures(StrataFrame)
check(nOut <= 40, "dézoomé : peu de textures visibles (" .. nOut .. ")")
TEST.time = TEST.time + 20
tick(2.5)
check(TEST.textures < 5000, "textures créées au total : " .. TEST.textures)

-- Zoom avant au curseur
TEST.mouseOver = true
for _ = 1, 25 do scroll.scripts.OnMouseWheel(scroll, 1) tick(0.1) end
tick(0.5)
local hover = find(StrataFrame, function(r) return r.kind == "FontString" and r.point and r.point[1] == "BOTTOMRIGHT" end)
print("     survol : " .. tostring(hover and hover.text))

-- Déplacement à la souris
scroll.scripts.OnMouseDown(scroll, "LeftButton")
TEST.cursor = { 700, 300 }
tick(0.2)
scroll.scripts.OnMouseUp(scroll, "LeftButton")
check(true, "déplacement sans erreur")
scroll.scripts.OnMouseDown(scroll, "RightButton")
tick(0.5)

-- Boutons : Moi, vue Outreterre, brouillard
local function button(label)
	return find(StrataFrame, function(r) return r.kind == "Button" and r.text == label end)
end
local L = ns.L
button(L.FOG_ON).scripts.OnClick()
tick(0.2)
check(ns.db.fog == false and button(L.FOG_OFF), "bouton brouillard")
button(L.OUTLAND).scripts.OnClick()
tick(0.5)
check(button(L.AZEROTH) ~= nil, "vue Outreterre")
check(not arrow:IsVisible(), "pas de flèche en Outreterre (joueur à Elwynn)")
button(L.ME).scripts.OnClick()
tick(0.5)
check(arrow:IsVisible(), "bouton Moi : retour sur Azeroth et le joueur")
-- Curseur sur le joueur (centre de la vue ; GetLeft = 100, GetTop = 900 dans les stubs)
TEST.cursor = { 100 + child.w / 2, 900 - child.h / 2 }
tick(0.2)
check(hover.text and hover.text:find("Elwynn  50.0, 50.0", 1, true), "survol sur le joueur : " .. tostring(hover.text))

-- Commandes
SlashCmdList.STRATA("help")
SlashCmdList.STRATA("fog")
check(ns.db.fog == true, "/strata fog")
StrataFrame:Hide()
SlashCmdList.STRATA("scan")
Strata_Toggle()
tick(0.5)
check(StrataFrame:IsShown(), "réouverture après /strata scan")
TEST.Fire("ZONE_CHANGED_NEW_AREA")
tick(0.5)
Strata_Toggle()
check(not StrataFrame:IsShown(), "fermeture")
check(ns.db.views.azeroth ~= nil, "vue mémorisée")

print(format("\n%d textures créées, %d SetTexture, %d messages", TEST.textures, TEST.setTextureCalls, #TEST.prints))
for _, m in ipairs(TEST.prints) do print("     chat : " .. m) end
