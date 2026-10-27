-- Copyright (C) 2026 BellaHealFr. Licence GPL-3.0-only avec conditions supplémentaires
-- (mention de l'auteur, nom « Strata » réservé) : voir LICENSE et NOTICE.md.

-- Scénario hors jeu : ouvrir la carte, zoomer, déplacer, changer de vue, fermer.
-- Chaque vérification qui échoue lève une erreur (le runner l'affiche et sort en échec).

local ns = Strata

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
-- Le texte de survol, à droite de la barre de titre (premier texte ancré à droite).
local hover = find(StrataFrame, function(r) return r.kind == "FontString" and r.point and r.point[1] == "RIGHT" end)
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
check(hover.text and hover.text:find("Elwynn", 1, true) and hover.text:find("50.0, 50.0", 1, true), "survol sur le joueur : " .. tostring(hover.text))
-- #3 : tranche de niveaux de la zone survolée, à la couleur des quêtes
check(hover.text:find("(1-10)", 1, true) and hover.text:find("|cff", 1, true), "niveaux de la zone au survol : " .. hover.text)

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

-- Compteur de performance
SlashCmdList.STRATA("debug")
check(StrataFrame:IsShown() and ns.measuring, "/strata debug ouvre la carte et active la mesure")
tick(1)
local counter = find(StrataFrame, function(r) return r.kind == "FontString" and r.text and r.text:find("%d+ Ko") or (r.text and r.text:find("%d+ KB")) end)
check(counter ~= nil, "compteur affiché : " .. (counter and counter.text:gsub("\n", " | ") or "?"))
SlashCmdList.STRATA("debug")
check(not ns.measuring, "/strata debug à nouveau : compteur masqué, mesure arrêtée")

-- Parcours de mesure
local _, z0, cx0, cy0 = ns.view.Get()
SlashCmdList.STRATA("bench")
check(ns.benching and ns.measuring, "/strata bench démarre")
tick(30)
check(not ns.benching and not ns.measuring, "bench terminé, mesure arrêtée")
local r = ns.db.lastBench
check(r and #r.phases == 6, "six phases enregistrées")
for _, p in ipairs(r.phases) do
	check(p.fps > 0 and p.peak >= 0, format("phase %s : %.0f IPS, %s ms, %d textures max", p.key, p.fps, p.ms and format("%.2f", p.ms) or "-", p.peak))
end
check(r.phases[1].ms == nil and r.phases[3].ms ~= nil, "carte fermée sans temps Strata, déplacement chronométré")
check(r.memory == 640, "mémoire relevée")
check(StrataBenchFrame and StrataBenchFrame:IsShown(), "fenêtre des résultats affichée")
local box = find(StrataBenchFrame, function(r) return r.kind == "EditBox" end)
check(box.text and box.text:find(ns.L.PHASES.tour, 1, true) and box.text:find(ns.L.BENCH_GOALS, 1, true), "résultats copiables avec les phases et les objectifs")
local name, z1, cx1, cy1 = ns.view.Get()
check(name == "azeroth" and math.abs(z1 - z0) < 1e-6 and math.abs(cx1 - cx0) < 1e-3 and math.abs(cy1 - cy0) < 1e-3, "vue d'avant le bench rétablie")

-- Arrêt en cours de route
SlashCmdList.STRATA("bench")
tick(3)
SlashCmdList.STRATA("bench")
check(not ns.benching and not ns.measuring, "/strata bench pendant la mesure l'arrête")
StrataBenchFrame:Hide()
Strata_Toggle()
check(not StrataFrame:IsShown(), "fermeture après la mesure")

-- #27 : un client qui renvoie 0 pour la mémoire de l'addon. Le bench ne doit pas annoncer « ok ».
TEST.memory = 0
SlashCmdList.STRATA("bench")
tick(30)
box = find(StrataBenchFrame, function(r) return r.kind == "EditBox" end)
local memLine
for line in box.text:gmatch("[^\n]+") do
	if line:find(ns.L.GOAL_MEMORY_NONE:match("^[^:]+"), 1, true) then memLine = line end
end
check(memLine and memLine:find(ns.L.TO_CHECK, 1, true), "mémoire à 0 : « " .. tostring(memLine) .. " »")
check(box.text:find(ns.L.BENCH_MEMORY_NONE, 1, true), "mémoire de l'addon annoncée indisponible")
check(box.text:find(ns.L.BENCH_LUA_TOTAL:match("^[^:]+"), 1, true), "mémoire Lua totale du jeu indiquée")
TEST.memory = nil
StrataBenchFrame:Hide()
Strata_Toggle()

-- #27 : la phase « Immobile » ne compte pas la réouverture de la carte.
check(ns.db.lastBench.phases[2].key == "still" and ns.db.lastBench.phases[2].warmup == 0.5, "phase immobile mesurée après 0,5 s d'attente")

-- #27 : objectif de textures au plus fort, mesurable sur tous les clients.
local texLine
for line in ns.db.lastBench and box.text:gmatch("[^\n]+") or function() end do
	if line:find(ns.L.GOAL_TEXTURES:match("^[^:]+"), 1, true) then texLine = line end
end
check(texLine ~= nil, "objectif de textures au plus fort : « " .. tostring(texLine) .. " »")

-- #6 : la recherche de zone par index donne exactement le résultat du parcours complet de 0.1.0.
local function ZoneAtReference(view, x, y)
	local best, bestArea, bx, by
	for _, c in ipairs(ns.VIEWS[view].continents) do
		local C = ns.Zones[c]
		local ox, oy = 0, 0
		if C.parent == 0 then ox, oy = C.x, C.y end
		for file, Z in pairs(C.zones) do
			if not Z[5] then
				local zx, zy = (x - ox - Z[3]) / Z[1], (y - oy - Z[4]) / Z[2]
				if zx >= 0 and zx <= 1 and zy >= 0 and zy <= 1 then
					local area = Z[1] * Z[2]
					if not best or area < bestArea then best, bestArea, bx, by = { c = c, file = file }, area, zx, zy end
				end
			end
		end
	end
	if best then
		local m = ns.maps[best.c]
		local zone = m and m.zones[best.file]
		return zone and zone.name or best.file, bx, by
	end
end
local points, diffs = 0, 0
for _, view in ipairs({ "azeroth", "outland" }) do
	local size = ns.VIEWS[view].size
	for i = 0, 59 do
		for j = 0, 32 do
			local x, y = (i + 0.37) / 60 * size.w * 1.1 - size.w * 0.05, (j + 0.61) / 33 * size.h * 1.1 - size.h * 0.05
			local a, ax, ay = ns.ZoneAt(view, x, y)
			local b, bx, by = ZoneAtReference(view, x, y)
			points = points + 1
			if a ~= b or (a and (math.abs(ax - bx) > 1e-9 or math.abs(ay - by) > 1e-9)) then
				diffs = diffs + 1
				if diffs <= 3 then print(format("     écart %s (%.0f, %.0f) : %s / %s", view, x, y, tostring(a), tostring(b))) end
			end
		end
	end
end
check(diffs == 0, format("recherche de zone identique au parcours complet sur %d points (%d écarts)", points, diffs))

-- #8 : la durée de la lecture des cartes (première ouverture) figure dans les résultats du bench.
check(type(ns.scanMs) == "number" and ns.scanMs >= 0, format("lecture des cartes chronométrée : %.2f ms", ns.scanMs or -1))
SlashCmdList.STRATA("bench")
tick(30)
box = find(StrataBenchFrame, function(r) return r.kind == "EditBox" end)
check(box.text:find(ns.L.BENCH_SCAN:match("^[^:]+"), 1, true), "lecture des cartes dans les résultats du bench")
StrataBenchFrame:Hide()
Strata_Toggle()

-- #21 : bouton de la minicarte
TEST.Fire("PLAYER_LOGIN")
local mb = StrataMinimapButton
check(mb ~= nil and mb.parent == Minimap, "bouton créé sur la minicarte à la connexion")
check(find(mb, function(r) return r.path == "Interface\\Minimap\\MiniMap-TrackingBorder" end) ~= nil, "bordure standard des boutons de minicarte")
local function distance()
	local _, x, y = unpack(mb.point)
	return math.sqrt(x * x + y * y), x, y
end
local d = distance()
check(math.abs(d - 80) < 1, format("bouton sur le cercle de la minicarte (%.1f px du centre)", d))

-- Clic gauche : ouvrir puis fermer
if StrataFrame:IsShown() then Strata_Toggle() end
mb.scripts.OnClick(mb, "LeftButton")
check(StrataFrame:IsShown(), "clic gauche : la carte s'ouvre")
mb.scripts.OnClick(mb, "LeftButton")
check(not StrataFrame:IsShown(), "clic gauche à nouveau : la carte se ferme")
mb.scripts.OnEnter(mb)
check(true, "infobulle sans erreur")

-- Glisser : l'angle suit le curseur et il est retenu (curseur au nord de la minicarte)
local s = Minimap:GetEffectiveScale()
TEST.cursor = { 1000 * s, (800 + 200) * s }
mb.scripts.OnDragStart(mb)
check(mb.scripts.OnUpdate ~= nil, "glisser : le bouton suit le curseur")
mb.scripts.OnUpdate(mb, 0.02)
mb.scripts.OnDragStop(mb)
local _, nx, ny = distance()
check(math.abs(ns.db.minimapAngle - 90) < 0.01 and math.abs(nx) < 0.01 and ny > 79, format("angle retenu : %.1f°, bouton au nord", ns.db.minimapAngle))
check(mb.scripts.OnUpdate == nil, "fin du glisser : plus rien ne tourne")

-- Minicarte carrée (ElvUI) : le bouton longe le bord du carré
GetMinimapShape = function() return "SQUARE" end
ns.db.minimapAngle = 45
ns.PlaceMinimapButton()
local _, sx, sy = distance()
check(math.abs(sx - 80) < 0.5 and math.abs(sy - 80) < 0.5, format("minicarte carrée : bouton dans le coin (%.1f, %.1f)", sx, sy))
GetMinimapShape = nil

-- /strata bouton
SlashCmdList.STRATA("bouton")
check(not mb:IsShown() and ns.db.hideMinimapButton, "/strata bouton masque le bouton")
SlashCmdList.STRATA("button")
check(mb:IsShown() and not ns.db.hideMinimapButton, "/strata button le remet")

-- #1 : recherche de zones et de villes
if not StrataFrame:IsShown() then Strata_Toggle() end
local box = StrataSearchBox
local function type_(text)
	box.text = text
	box.scripts.OnTextChanged(box, true)
end
local function rowsShown()
	local out = {}
	for _, row in ipairs(find(StrataFrame, function(r) return r.kind == "Frame" and r.children[1] and r.children[1].kind == "Button" and r.children[1].name end).children) do
		if row:IsVisible() then out[#out + 1] = row end
	end
	return out
end
-- Nom accentué, comme sur un client français
ns.maps[2].zones.Elwynn.name = "Forêt d'Elwynn"
type_("FORET d")
local shown = rowsShown()
check(#shown >= 1 and shown[1].name.text == "Forêt d'Elwynn", "« FORET d » trouve « Forêt d'Elwynn » (majuscules et accents ignorés)")
check(shown[1].where.text == "Royaumes de l'Est", "continent indiqué : " .. tostring(shown[1].where.text))
type_("elw")
check(rowsShown()[1].name.text == "Forêt d'Elwynn" and rowsShown()[2].name.text == "Felwood",
	"« elw » : Forêt d'Elwynn (début de mot) avant Felwood (milieu de mot)")
type_("zzzz")
shown = rowsShown()
check(#shown == 1 and shown[1].zone == nil and shown[1].name.text:find(ns.L.SEARCH_NONE, 1, true), "aucun résultat annoncé")
-- Les noms qui commencent par la recherche d'abord
local found = ns.Search("st")
check(found[1].plain:sub(1, 2) == "st", "les noms qui commencent par la recherche en premier : " .. found[1].name)
-- Clic sur un résultat : la carte va sur la zone, à un zoom qui la fait tenir
type_("elw")
local target = rowsShown()[1].zone
rowsShown()[1].scripts.OnClick(rowsShown()[1])
local name, z, cx, cy = ns.view.Get()
check(name == "azeroth" and math.abs(cx - (target.x + target.w / 2)) < 1e-6 and math.abs(cy - (target.y + target.h / 2)) < 1e-6, "clic : carte centrée sur la zone")
local vw, vh = ns.view.Size()
check(target.w * z <= vw and target.h * z <= vh and (target.w * z > vw * 0.8 or target.h * z > vh * 0.8), "la zone tient dans la fenêtre")
check(box.text == "" and not rowsShown()[1], "résultats fermés et champ vidé après le choix")
-- Entrée : premier résultat, et changement de vue vers l'Outreterre
type_("nagr")
box.scripts.OnEnterPressed(box)
check(ns.view.Get() == "outland", "Entrée sur « nagr » : vue Outreterre, sur Nagrand")
-- Échap : tout s'efface
type_("elw")
box.scripts.OnEscapePressed(box)
check(box.text == "" and not rowsShown()[1], "Échap vide le champ et ferme les résultats")
Strata_Toggle()

-- #2 : épingles
TomTom = { calls = {} }
function TomTom:AddZWaypoint(...) table.insert(self.calls, { ... }) return "uid" end
if not StrataFrame:IsShown() then Strata_Toggle() end
local function button(label)
	return find(StrataFrame, function(r) return r.kind == "Button" and r.text == label end)
end
button(ns.L.ME).scripts.OnClick()
tick(0.3)
local pv, px, py = ns.UnitPos("player")
TEST.cursor = { 100 + child.w / 2, 900 - child.h / 2 }
TEST.ctrl = true
scroll.scripts.OnMouseDown(scroll, "LeftButton")
TEST.ctrl = nil
local pin = ns.db.pins and ns.db.pins[1]
check(pin and pin.view == "azeroth" and math.abs(pin.x - px) < 1 and math.abs(pin.y - py) < 1, "Ctrl-clic : épingle posée sous le curseur")
check(StrataPinCard:IsVisible(), "Ctrl-clic : la fiche de l'épingle s'ouvre")
local function pinButton(p)
	return find(StrataFrame, function(r) return r.kind == "Button" and r.pin == p end)
end
local pb = pinButton(pin)
local k = 1000 / ns.VIEWS.azeroth.size.w
check(pb and pb:IsVisible() and math.abs(pb.point[2] - pin.x * k) < 1e-6 and math.abs(pb.point[3] + pin.y * k) < 1e-6, "épingle placée sur le canevas, au bon endroit")
local _, zoom1 = ns.view.Get()
check(math.abs(pb.w - 18 / zoom1) < 1e-6, "taille de l'épingle : 18 px à l'écran")
StrataPinNote.text = "Mine de cuivre"
StrataPinNote.scripts.OnTextChanged(StrataPinNote, true)
check(pin.note == "Mine de cuivre", "note enregistrée")
StrataPinCard.icons[3].scripts.OnClick(StrataPinCard.icons[3])
check(pin.icon == 3 and pb.icon.path:sub(-2) == "_3" and ns.db.lastPinIcon == 3, "icône choisie (losange) et retenue pour la suivante")
-- Zoom : la taille à l'écran ne change pas
for _ = 1, 3 do scroll.scripts.OnMouseWheel(scroll, 1) end
tick(1)
local _, zoom2 = ns.view.Get()
check(zoom2 > zoom1 and math.abs(pb.w - 18 / zoom2) < 1e-6, "après un zoom, toujours 18 px à l'écran")
-- TomTom
button("TomTom").scripts.OnClick()
local call = TomTom.calls[1]
check(call and call[1] == 2 and call[2] == ns.maps[2].zones.Elwynn.index and math.abs(call[3] - 50) < 0.1 and math.abs(call[4] - 50) < 0.1,
	format("TomTom : continent %s, zone %s, %.1f, %.1f", tostring(call and call[1]), tostring(call and call[2]), call and call[3] or -1, call and call[4] or -1))
check(call[5] == "Mine de cuivre" and call[11] == true, "TomTom : la note comme titre, flèche demandée")
-- Liste
local listBtn = button(format(ns.L.PINS, 1))
check(listBtn ~= nil, "bouton de la liste : « " .. format(ns.L.PINS, 1) .. " »")
listBtn.scripts.OnClick()
check(StrataPinList:IsVisible() and StrataPinList.rows[1].label.text == "Mine de cuivre", "liste : l'épingle y figure avec sa note")
ns.view.Center(10, 10, 2)
StrataPinList.rows[1].scripts.OnClick(StrataPinList.rows[1])
local _, _, lcx, lcy = ns.view.Get()
check(math.abs(lcx - pin.x * k) < 1e-6 and math.abs(lcy - pin.y * k) < 1e-6 and StrataPinCard:IsVisible(), "liste : un clic ramène la carte sur l'épingle")
-- Une épingle en Outreterre ne s'affiche pas sur Azeroth
button(ns.L.OUTLAND).scripts.OnClick()
tick(0.2)
TEST.ctrl = true
scroll.scripts.OnMouseDown(scroll, "LeftButton")
TEST.ctrl = nil
local outPin = ns.db.pins[2]
check(outPin.view == "outland" and pinButton(outPin):IsVisible(), "épingle posée en Outreterre")
button(ns.L.AZEROTH).scripts.OnClick()
tick(0.2)
check(pinButton(pin):IsVisible() and not pinButton(outPin):IsVisible(), "vue Azeroth : seule l'épingle d'Azeroth s'affiche")
-- Réouverture : les épingles reviennent
Strata_Toggle() Strata_Toggle()
tick(0.2)
check(pinButton(pin):IsVisible(), "épingles toujours là après avoir fermé et rouvert la carte")
-- Suppression
ns.view.Center(pin.x * k, pin.y * k, 6)
pinButton(pin).scripts.OnClick(pinButton(pin))
button(ns.L.PIN_DELETE).scripts.OnClick()
check(#ns.db.pins == 1 and ns.db.pins[1] == outPin and not StrataPinCard:IsVisible(), "suppression : l'épingle disparaît, la fiche se ferme")
check(button(format(ns.L.PINS, 1)) ~= nil, "le bouton de la liste suit le compte")
ns.db.pins = {}
TomTom = nil
Strata_Toggle()

-- #38 : flèche de guidage propre à Strata
local function angleDiff(a, b)
	local d = (a - b) % (2 * math.pi)
	if d > math.pi then d = d - 2 * math.pi end
	return math.abs(d)
end
local _, px, py = ns.UnitPos("player")
ns.Follow("azeroth", px, py - 100, "Nord")
tick(0.3)
local arrowFrame = StrataArrow
check(arrowFrame and arrowFrame:IsShown(), "suivre : la flèche apparaît, carte fermée")
check(arrowFrame.distance.text:find("100", 1, true), "distance affichée : " .. tostring(arrowFrame.distance.text))
check(angleDiff(ns.nav.angle, -1.0) < 1e-6, format("cible au nord, joueur tourné de 1 rad : flèche à %.3f rad", ns.nav.angle))
ns.Follow("azeroth", px - 100, py, "Ouest")
tick(0.3)
check(angleDiff(ns.nav.angle, math.pi / 2 - 1.0) < 1e-6, format("cible à l'ouest : flèche à %.3f rad", ns.nav.angle))
-- Temps estimé : le joueur avance vers une cible à 210 m au nord, à 7 m/s
local h = ns.Zones[2].zones.Elwynn[2]
ns.Follow("azeroth", px, py - 210, "Loin")
local y0 = 0.5
for i = 1, 100 do
	TEST.py = y0 - (7 * 0.02 * i) / h
	frame()
end
local eta = tonumber(arrowFrame.eta.text and arrowFrame.eta.text:match("(%d+)"))
check(eta and eta >= 24 and eta <= 32, "temps estimé en avançant à 7 m/s : " .. tostring(arrowFrame.eta.text))
TEST.py = nil
-- Autre continent
ns.Follow("outland", 5000, 5000, "Shattrath")
tick(0.3)
check(arrowFrame.distance.text == ns.L.NAV_ELSEWHERE, "cible sur un autre continent : « " .. tostring(arrowFrame.distance.text) .. " »")
-- Arrivée : « Arrivé », puis la flèche se retire
ns.Follow("azeroth", px + 3, py, "Ici")
tick(0.3)
check(arrowFrame.distance.text == ns.L.NAV_ARRIVED, "à moins de 10 m : « " .. tostring(arrowFrame.distance.text) .. " »")
tick(3.5)
check(not arrowFrame:IsShown() and ns.db.target == nil, "arrivé : la flèche se retire et la cible est oubliée")
-- Clic droit : arrêter
ns.Follow("azeroth", px, py - 100, "Nord")
arrowFrame.scripts.OnMouseUp(arrowFrame, "RightButton")
check(not arrowFrame:IsShown() and ns.db.target == nil, "clic droit : le guidage s'arrête")
-- Cible retenue après un rechargement
ns.Follow("azeroth", px, py - 100, "Nord")
arrowFrame:Hide()
TEST.Fire("PLAYER_LOGIN")
check(arrowFrame:IsShown(), "cible retenue : la flèche revient à la connexion")
ns.StopFollow()
-- Depuis la fiche d'une épingle
Strata_Toggle()
local followPin = ns.AddPin("azeroth", px + 50, py)
find(StrataFrame, function(r) return r.kind == "Button" and r.text == ns.L.PIN_FOLLOW end).scripts.OnClick()
check(ns.db.target and ns.db.target.x == followPin.x and arrowFrame:IsShown(), "bouton « Suivre » de la fiche : la flèche guide vers l'épingle")
ns.StopFollow()
ns.db.pins = {}
Strata_Toggle()

-- #3 : intégrité des tranches de niveaux (Data/Levels.lua)
local drawn, unknown, missing, inverted = {}, {}, {}, {}
for c = 1, 4 do
	for file, Z in pairs(ns.Zones[c].zones) do
		if not Z[5] then drawn[file] = true end
	end
end
for file, r in pairs(ns.Levels) do
	if not drawn[file] then unknown[#unknown + 1] = file end
	if r[1] > r[2] then inverted[#inverted + 1] = file end
end
for file in pairs(drawn) do
	if not ns.Levels[file] and not ns.CITIES[file] and file ~= "Moonglade" then missing[#missing + 1] = file end
end
check(#unknown == 0, "chaque tranche de niveaux correspond à une vraie zone " .. table.concat(unknown, ", "))
check(#missing == 0, "chaque zone hors ville a sa tranche " .. table.concat(missing, ", "))
check(#inverted == 0, "minimum jamais au-dessus du maximum " .. table.concat(inverted, ", "))
-- Pas de niveaux sur une ville
do
	local stormwind = ns.Zones[2].zones.Stormwind
	local cx = ns.Zones[2].x + stormwind[3] + stormwind[1] / 2
	local cy = ns.Zones[2].y + stormwind[4] + stormwind[2] / 2
	check(ns.ZoneText("azeroth", cx, cy):find("(", 1, true) == nil, "pas de niveaux sur une ville : " .. ns.ZoneText("azeroth", cx, cy))
end

-- #4 : plein écran
if not StrataFrame:IsShown() then Strata_Toggle() end
ns.db.point, ns.db.w, ns.db.h = { "CENTER", 40, -20 }, 900, 640
local fullscreen = find(StrataFrame, function(r) return r.kind == "Button" and r.isFullscreenButton end)
check(fullscreen ~= nil, "bouton plein écran dans la barre de titre")
fullscreen.scripts.OnClick(fullscreen)
check(ns.db.fullscreen and StrataFrame.allPoints == UIParent, "plein écran : la carte couvre tout l'écran")
check(ns.db.w == 900 and ns.db.h == 640 and ns.db.point[2] == 40, "plein écran : la taille et la position de la fenêtre restent retenues")
local grabber = find(StrataFrame, function(r) return r.kind == "Button" and r.isSizeGrip end)
check(grabber and not grabber:IsShown(), "plein écran : plus de poignée de redimensionnement")
local moved
local real = StrataFrame.StartMoving
StrataFrame.StartMoving = function() moved = true end
find(StrataFrame, function(r) return r.scripts and r.scripts.OnDragStart and r.parent == StrataFrame and r.kind == "Frame" end).scripts.OnDragStart()
check(not moved, "plein écran : la fenêtre ne se déplace pas")
StrataFrame.StartMoving = real
-- Retenu à la réouverture
Strata_Toggle() Strata_Toggle()
check(StrataFrame.allPoints == UIParent, "plein écran retenu à la réouverture")
-- Retour en fenêtre
SlashCmdList.STRATA("plein")
check(not ns.db.fullscreen and StrataFrame.allPoints == nil and StrataFrame.w == 900 and StrataFrame.h == 640
	and StrataFrame.point and StrataFrame.point[1] == "CENTER" and StrataFrame.point[2] == 40,
	"/strata plein : retour à la fenêtre, même taille et même position")
check(grabber:IsShown(), "retour en fenêtre : poignée de redimensionnement revenue")
Strata_Toggle()

-- #45 : rendu des zones (comparé à la carte de Blizzard 3.3.5 et à OpenMap)
do
	if not StrataFrame:IsShown() then Strata_Toggle() end
	ns.Rebuild()
	local Z2 = ns.Zones[2]
	local k = 1000 / ns.VIEWS.azeroth.size.w
	local function centerOnZone(file, zoom)
		local z = Z2.zones[file]
		ns.view.Center((Z2.x + z[3] + z[1] / 2) * k, (Z2.y + z[4] + z[2] / 2) * k, zoom)
		tick(0.3)
	end
	-- Textures visibles d'une carte de zone : fichier -> { [numéro de tuile] = texture }
	local function zoneTiles()
		local out = {}
		local function walk(r)
			if r.kind == "Texture" and r:IsVisible() and type(r.path) == "string" then
				local file, n = r.path:match("^Interface\\WorldMap\\(%w+)\\%1(%d+)$")
				if file and Z2.zones[file] then
					out[file] = out[file] or {}
					out[file][tonumber(n)] = r
				end
			end
			for _, c in ipairs(r.children) do walk(c) end
		end
		walk(StrataFrame)
		return out
	end
	centerOnZone("Elwynn", 6)
	local tiles = zoneTiles().Elwynn
	check(tiles and tiles[1] and tiles[12], "Forêt d'Elwynn affichée")
	-- Joints : chaque tuile accrochée au bord de la précédente, comme WorldMapDetailTile2..12.
	-- Toute pièce qui a une voisine juste à sa gauche (même rangée) y est accrochée par son bord.
	do
		local pieces = {}
		local function walk(r)
			if r.kind == "Texture" and r:IsVisible() and r.cell and type(r.path) == "string"
				and r.path:match("Elwynn\\Elwynn%d+$") then pieces[#pieces + 1] = r end
			for _, c in ipairs(r.children) do walk(c) end
		end
		walk(StrataFrame)
		local linked, loose = 0, 0
		for _, a in ipairs(pieces) do
			for _, b in ipairs(pieces) do
				if b.cell[3] == a.cell[1] and b.cell[2] == a.cell[2] then
					if a.point.rel == b and a.point.relPoint == "TOPRIGHT" then linked = linked + 1 else loose = loose + 1 end
				end
			end
		end
		check(linked > 10 and loose == 0, format("tuiles accrochées les unes aux autres (pas de joint d'arrondi) : %d", linked))
	end
	-- Et aucune ne lit le bord de sa voisine : demi-texel de marge au bord d'un fichier, aucune
	-- ailleurs (#58 : le fond est découpé à la forme de la zone, pas seulement aux tuiles).
	do
		local bad, edges = 0, 0
		local function walk(r)
			if r.kind == "Texture" and r:IsVisible() and r.cell and type(r.path) == "string"
				and r.path:match("Elwynn\\Elwynn%d+$") then
				local c, tc = r.cell, r.texcoord
				local tx, ty = math.floor(c[1] / 256) * 256, math.floor(c[2] / 256) * 256
				local u0 = (c[1] - tx + (c[1] == tx and 0.5 or 0)) / 256
				local u1 = (c[3] - tx - (c[3] == math.min(tx + 256, 1002) and 0.5 or 0)) / 256
				if c[1] == tx then edges = edges + 1 end
				if math.abs(tc[1] - u0) > 1e-6 or math.abs(tc[2] - u1) > 1e-6 then bad = bad + 1 end
			end
			for _, ch in ipairs(r.children) do walk(ch) end
		end
		walk(StrataFrame)
		check(edges > 0 and bad == 0, format("demi-texel de marge sur les bords des tuiles (%d bords, %d fautes)", edges, bad))
	end

	-- Ordre : une zone passe au-dessus des zones plus grandes qu'elle touche, toujours.
	-- (au zoom 6, une quinzaine de zones du sud des Royaumes de l'Est sont chargées)
	centerOnZone("Duskwood", 6)
	local shown = zoneTiles()
	local function level(t) return t.parent:GetFrameLevel() end
	local wrong, pairsChecked = {}, 0
	for a, ta in pairs(shown) do
		for b, tb in pairs(shown) do
			local za, zb = Z2.zones[a], Z2.zones[b]
			if a ~= b and not ns.CITIES[a] and not ns.CITIES[b] and za[1] * za[2] > zb[1] * zb[2]
				and za[3] < zb[3] + zb[1] and zb[3] < za[3] + za[1] and za[4] < zb[4] + zb[2] and zb[4] < za[4] + za[2] then
				pairsChecked = pairsChecked + 1
				-- (une tuile quelconque : une zone coupée à sa forme n'a pas toujours la première)
				if not (level(select(2, next(ta))) < level(select(2, next(tb)))) then wrong[#wrong + 1] = b .. " sous " .. a end
			end
		end
	end
	check(pairsChecked >= 5 and #wrong == 0, format("%d paires de zones voisines dans l'ordre (petite sur grande) %s", pairsChecked, table.concat(wrong, ", ")))
	-- Les morceaux découverts restent au-dessus de tous les fonds.
	local maxBase, minOver = 0, math.huge
	local function walk(r)
		if r.kind == "Texture" and r:IsVisible() and type(r.path) == "string" and r.path:find("^Interface\\WorldMap\\") then
			local file, rest = r.path:match("^Interface\\WorldMap\\(%w+)\\(.+)$")
			if file and Z2.zones[file] and not ns.CITIES[file] then
				if rest:match("^" .. file .. "%d+$") then maxBase = math.max(maxBase, level(r))
				else minOver = math.min(minOver, level(r)) end
			end
		end
		for _, c in ipairs(r.children) do walk(c) end
	end
	walk(StrataFrame)
	check(minOver > maxBase, "morceaux découverts au-dessus de tous les fonds")

	-- Villes : comme OpenMap, seulement quand elles remplissent une part de la vue.
	local vw = ns.view.Size()
	local sw = Z2.zones.Stormwind[1] * k
	centerOnZone("Stormwind", 0.15 * vw / sw)
	check(not zoneTiles().Stormwind, "Hurlevent à 15 % de la vue : pas encore sa carte (Elwynn la dessine)")
	check(zoneTiles().Elwynn, "... et Elwynn reste affichée")
	centerOnZone("Stormwind", 0.6 * vw / sw)
	local city = zoneTiles().Stormwind
	check(city and city[1] and level(city[1]) > minOver, "Hurlevent à 60 % de la vue : sa carte, au-dessus des zones")
	ns.Rebuild()
	Strata_Toggle()
end

-- #47 : bord adouci des cartes de zone et de ville (comme le masque « feather » d'OpenMap)
do
	if not StrataFrame:IsShown() then Strata_Toggle() end
	ns.Rebuild()
	local k = 1000 / ns.VIEWS.azeroth.size.w
	local function centerOn(c, file, zoom)
		local _, x, y = ns.ToView(c, file, 0.5, 0.5)
		ns.view.Center(x * k, y * k, zoom)
		tick(0.3)
	end
	-- Les morceaux visibles du fond d'une carte, avec leur place (tex.cell, en px de la carte).
	local function quads(file)
		local out = {}
		local function walk(r)
			if r.kind == "Texture" and r:IsVisible() and r.cell and type(r.path) == "string"
				and r.path:match("^Interface\\WorldMap\\" .. file .. "\\" .. file .. "%d+$") then
				out[#out + 1] = r
			end
			for _, c in ipairs(r.children) do walk(c) end
		end
		walk(StrataFrame)
		return out
	end
	-- Transparence aux quatre coins d'un morceau : haut-gauche, haut-droit, bas-gauche, bas-droit.
	local function corners(t)
		local g = t.gradient
		if not g then return 1, 1, 1, 1 end   -- (pièce sans dégradé : opaque)
		if g[1] == "HORIZONTAL" then return g[2], g[3], g[2], g[3] end
		return g[3], g[3], g[2], g[2]
	end
	local function feathered(file, what)
		local q = quads(file)
		local bad, inner = {}, 0
		for _, t in ipairs(q) do
			local c = t.cell
			local tl, tr, bl, br = corners(t)
			if (c[1] == 0 and (tl > 0 or bl > 0)) or (c[3] == 1002 and (tr > 0 or br > 0))
				or (c[2] == 0 and (tl > 0 or tr > 0)) or (c[4] == 668 and (bl > 0 or br > 0)) then
				bad[#bad + 1] = format("%d,%d", c[1], c[2])
			end
			if c[1] >= 256 and c[3] <= 768 and c[2] >= 256 and c[4] <= 512 and tl == 1 and br == 1 then inner = inner + 1 end
		end
		check(#q >= 12 and #bad == 0 and inner == 2, format("%s : bord transparent sur tout le tour, cœur opaque (%d morceaux) %s", what, #q, table.concat(bad, " ")))
	end
	centerOn(2, "Elwynn", 6)
	feathered("Elwynn", "Forêt d'Elwynn")
	-- Pas de saut entre deux morceaux voisins d'une même rangée (même transparence au bord commun).
	do
		local q, jumps = quads("Elwynn"), 0
		for _, a in ipairs(q) do
			for _, b in ipairs(q) do
				if a.cell[3] == b.cell[1] and a.cell[2] == b.cell[2] then
					local _, atr, _, abr = corners(a)
					local btl, _, bbl = corners(b)
					if math.abs(atr - btl) > 0.26 or math.abs(abr - bbl) > 0.26 then jumps = jumps + 1 end
				end
			end
		end
		check(jumps == 0, "pas de saut de transparence entre deux morceaux voisins")
	end
	-- Le fondu d'apparition de la zone passe par le dégradé : cœur à la transparence de la zone.
	-- (une zone paraît de 220 à 352 px de large : 286 px, à mi-chemin)
	centerOn(2, "Elwynn", 286 / (ns.Zones[2].zones.Elwynn[1] * k))
	local half
	for _, t in ipairs(quads("Elwynn")) do
		if t.cell[1] == 256 and t.cell[2] == 256 then half = t.gradient[2] end
	end
	check(half and half > 0 and half < 1, "zone en cours d'apparition : cœur à moitié transparent (" .. tostring(half) .. ")")
	-- Ville : Dalaran, cadre de parchemin et bannière effacés au bord.
	centerOn(4, "Dalaran", 0.8 * ns.view.Size() / (ns.Zones[4].zones.Dalaran[1] * k))
	do
		local _, _, cx, cy = ns.view.Get()
		local _, dx, dy = ns.ToView(4, "Dalaran", 0.5, 0.5)
		check(math.abs(cx - dx * k) < 0.5 and math.abs(cy - dy * k) < 0.5, "centrée sur Dalaran malgré un zoom demandé au-delà du maximum")
	end
	feathered("Dalaran", "Dalaran")
	-- Mémoire : les morceaux d'une même tuile partagent un fichier, chargé une seule fois.
	local files, paths = 0, {}
	local function walk(r)
		if r.kind == "Texture" and type(r.path) == "string" and not paths[r.path] and r.path:find("^Interface\\WorldMap\\%w+\\") then
			paths[r.path] = true
			files = files + 1
		end
		for _, c in ipairs(r.children) do walk(c) end
	end
	walk(StrataFrame)
	check(ns.stats.files == files, format("fichiers de carte chargés comptés une fois chacun (%d / %d)", ns.stats.files, files))
	ns.Rebuild()
	Strata_Toggle()
end

-- #49 : bord adouci des morceaux découverts (côtés ouverts seulement) et des cartes de continent
do
	-- Côtés au bord de la carte de la zone (#51) : seuls ceux-là portent le cadre de Blizzard.
	local sides, band = ns.FrameBand({ "a", 300, 200, 100, 50 }, 2)
	check(not (sides.left or sides.right or sides.top or sides.bottom), "morceau à l'intérieur de la carte : aucun côté adouci")
	sides, band = ns.FrameBand({ "a", 288, 222, 0, 0 }, 2)
	check(sides.left and sides.top and not sides.right and not sides.bottom and band == 32, "morceau dans le coin haut-gauche : côtés haut et gauche, bord fin")
	sides, band = ns.FrameBand({ "a", 288, 222, 0, 0 }, 4)
	check(band == 128, "coin d'une carte du Norfendre : bande large (ornements)")
	if not StrataFrame:IsShown() then Strata_Toggle() end
	ns.Rebuild()
	local k = 1000 / ns.VIEWS.azeroth.size.w
	local _, ex, ey = ns.ToView(2, "Elwynn", 0.5, 0.5)
	ns.view.Center(ex * k, ey * k, 6)
	tick(0.3)
	local function corners(t)
		local g = t.gradient
		if not g then return 1, 1, 1, 1 end
		if g[1] == "HORIZONTAL" then return g[2], g[3], g[2], g[3] end
		return g[3], g[3], g[2], g[2]
	end
	-- Les morceaux d'un fichier « dossier\\nom » : leur bord extérieur (w x h) doit être transparent.
	local function edges(pattern, w, h)
		local n, bad, opaque = 0, 0, 0
		local function walk(r)
			if r.kind == "Texture" and r:IsVisible() and r.cell and type(r.path) == "string" and r.path:match(pattern) then
				n = n + 1
				local c = r.cell
				local tl, tr, bl, br = corners(r)
				if (c[1] == 0 and (tl > 0 or bl > 0)) or (c[3] == w and (tr > 0 or br > 0))
					or (c[2] == 0 and (tl > 0 or tr > 0)) or (c[4] == h and (bl > 0 or br > 0)) then
					bad = bad + 1
				end
				if tl == 1 and tr == 1 and bl == 1 and br == 1 then opaque = opaque + 1 end
			end
			for _, ch in ipairs(r.children) do walk(ch) end
		end
		walk(StrataFrame)
		return n, bad, opaque
	end
	-- Morceau à l'intérieur : intact (Blizzard a déjà fondu ses bords).
	local n, bad, opaque = edges("^Interface\\WorldMap\\Elwynn\\Piece%d+$", 300, 200)
	check(n == 2 and opaque == 2, format("morceau à l'intérieur : intact, sans découpe (%d pièces)", n))
	-- Morceau dans le coin bas-droit : bords droit et bas transparents, côtés intérieurs opaques.
	local inner = 0
	n, bad = edges("^Interface\\WorldMap\\Elwynn\\Corner%d+$", 256, 512)
	local function walk(r)
		if r.kind == "Texture" and r:IsVisible() and r.cell and type(r.path) == "string" and r.path:match("Elwynn\\Corner") then
			local tl, _, bl = corners(r)
			if r.cell[1] == 0 and r.cell[2] == 0 and tl == 1 then inner = inner + 1 end
		end
		for _, ch in ipairs(r.children) do walk(ch) end
	end
	walk(StrataFrame)
	check(n > 2 and inner == 1, format("morceau au bord de la carte : côtés du bord adoucis, côtés intérieurs intacts (%d pièces)", n))
	-- Carte de continent : bord large adouci (cadre, mer et ornements fondus dans la carte du monde).
	ns.view.Center(ex * k, ey * k, 2.5)
	tick(0.3)
	n, bad, opaque = edges("^Interface\\WorldMap\\Azeroth\\Azeroth%d+$", 1002, 668)
	check(n == 24 and bad == 0 and opaque == 2, format("carte du continent : bord transparent sur tout le tour (%d pièces)", n))
	ns.Rebuild()
	Strata_Toggle()
end

-- #51 : une découverte remplace la liste des morceaux d'une zone ; leur découpage suit.
do
	if not StrataFrame:IsShown() then Strata_Toggle() end
	local info = ns.maps[2].zones.Elwynn
	local old = info.overlays
	local k = 1000 / ns.VIEWS.azeroth.size.w
	local _, ex, ey = ns.ToView(2, "Elwynn", 0.5, 0.5)
	ns.Rebuild()
	ns.view.Center(ex * k, ey * k, 6)
	tick(0.3)
	-- (nouveau morceau dans le coin haut-gauche de la carte : il doit être découpé)
	info.overlays = { { "Interface\WorldMap\Elwynn\Found", 256, 256, 0, 0 } }
	ns.Rebuild()
	ns.view.Center(ex * k, ey * k, 6)
	tick(0.3)
	local pieces = 0
	local function walk(r)
		if r.kind == "Texture" and r:IsVisible() and r.path == "Interface\WorldMap\Elwynn\Found1" then pieces = pieces + 1 end
		for _, c in ipairs(r.children) do walk(c) end
	end
	walk(StrataFrame)
	check(pieces > 1, format("morceau tout juste découvert : découpé avec son bord adouci (%d pièces)", pieces))
	info.overlays = old
	ns.Rebuild()
	Strata_Toggle()
end

-- #53 : brouillard éteint, carte entière révélée (Data/Overlays.lua) ; bord du monde dans la mer
do
	-- Données : chaque zone existe et se dessine, chaque morceau tient dans sa carte.
	local drawn, bad, count = {}, {}, 0
	for c = 1, 4 do for file, Z in pairs(ns.Zones[c].zones) do if not Z[5] then drawn[file] = true end end end
	for file, list in pairs(ns.Overlays) do
		if not drawn[file] then bad[#bad + 1] = file end
		for _, o in ipairs(list) do
			count = count + 1
			if type(o[1]) ~= "string" or o[2] <= 0 or o[3] <= 0 or o[4] < 0 or o[5] < 0
				or o[4] + o[2] > 1024 or o[5] + o[3] > 768 then bad[#bad + 1] = file .. "." .. tostring(o[1]) end
		end
	end
	check(count >= 800 and #bad == 0, format("%d morceaux de carte, zones et tailles valides %s", count, table.concat(bad, ", ")))

	if not StrataFrame:IsShown() then Strata_Toggle() end
	local k = 1000 / ns.VIEWS.azeroth.size.w
	local _, ex, ey = ns.ToView(2, "Elwynn", 0.5, 0.5)
	local function shown(pattern)
		local n = 0
		local function walk(r)
			if r.kind == "Texture" and r:IsVisible() and type(r.path) == "string" and r.path:match(pattern) then n = n + 1 end
			for _, ch in ipairs(r.children) do walk(ch) end
		end
		walk(StrataFrame)
		return n
	end
	local function at(zoom)
		ns.view.Center(ex * k, ey * k, zoom)
		tick(0.3)
	end
	ns.Rebuild()
	at(6)
	check(shown("Elwynn\\NORTHSHIREVALLEY%d+$") == 0 and shown("Elwynn\\Piece%d+$") > 0,
		"brouillard : seuls les morceaux découverts")
	SlashCmdList.STRATA("brouillard")
	tick(0.3)
	check(ns.db.fog == false and shown("Elwynn\\NORTHSHIREVALLEY%d+$") > 0 and shown("Elwynn\\Piece%d+$") > 0
		and shown("Elwynn\\Elwynn%d+$") > 0,
		"brouillard éteint : carte révélée (morceaux non découverts en plus), fond des zones dessiné")
	SlashCmdList.STRATA("brouillard")
	tick(0.3)
	check(ns.db.fog == true and shown("Elwynn\\NORTHSHIREVALLEY%d+$") == 0, "brouillard rallumé : morceaux non découverts retirés")

	-- Bord du monde : la carte du monde se fond dans la mer, de la couleur de la sienne.
	at(1)
	local edgeBad, world = 0, 0
	local function walk(r)
		if r.kind == "Texture" and r:IsVisible() and r.cell and type(r.path) == "string" and r.path:match("World\\World%d+$") then
			world = world + 1
			local g, c = r.gradient, r.cell
			local tl, tr, bl, br = 1, 1, 1, 1
			if g and g[1] == "HORIZONTAL" then tl, tr, bl, br = g[2], g[3], g[2], g[3]
			elseif g then tl, tr, bl, br = g[3], g[3], g[2], g[2] end
			if (c[1] == 0 and (tl > 0 or bl > 0)) or (c[3] == 1002 and (tr > 0 or br > 0))
				or (c[2] == 0 and (tl > 0 or tr > 0)) or (c[4] == 668 and (bl > 0 or br > 0)) then edgeBad = edgeBad + 1 end
		end
		for _, ch in ipairs(r.children) do walk(ch) end
	end
	walk(StrataFrame)
	check(world == 24 and edgeBad == 0, "carte du monde : bord transparent sur tout le tour")
	local function seaColor()
		local found = find(StrataFrame, function(r) return r.kind == "Texture" and type(r.path) == "number" and r:IsVisible() end)
		return found and found.path
	end
	local azeroth = seaColor()
	button(L.OUTLAND).scripts.OnClick()
	tick(0.3)
	local outland = seaColor()
	button(L.AZEROTH).scripts.OnClick()
	tick(0.3)
	check(azeroth and math.abs(azeroth - 0.545) < 0.01 and outland and math.abs(outland - 0.49) < 0.01,
		format("mer autour de la carte, couleur de chaque vue (%s / %s)", tostring(azeroth), tostring(outland)))
	ns.Rebuild()
	Strata_Toggle()
end

-- #55 : le fond d'une zone ne déborde pas du rectangle de ses morceaux ; celui d'une ville, de son plan.
do
	if not StrataFrame:IsShown() then Strata_Toggle() end
	ns.Rebuild()
	local k = 1000 / ns.VIEWS.azeroth.size.w
	local function bounds(file)
		local x0, y0, x1, y1, n = math.huge, math.huge, -math.huge, -math.huge, 0
		local function walk(r)
			if r.kind == "Texture" and r:IsVisible() and r.cell and type(r.path) == "string"
				and r.path:match("\\" .. file .. "\\" .. file .. "%d+$") then
				n = n + 1
				x0, y0 = math.min(x0, r.cell[1]), math.min(y0, r.cell[2])
				x1, y1 = math.max(x1, r.cell[3]), math.max(y1, r.cell[4])
			end
			for _, c in ipairs(r.children) do walk(c) end
		end
		walk(StrataFrame)
		return n, x0, y0, x1, y1
	end
	-- Duskwood : le rectangle de ses 13 morceaux
	local bx0, by0, bx1, by1 = 1002, 668, 0, 0
	for _, o in ipairs(ns.Overlays.Duskwood) do
		bx0, by0 = math.min(bx0, o[4]), math.min(by0, o[5])
		bx1, by1 = math.max(bx1, o[4] + o[2]), math.max(by1, o[5] + o[3])
	end
	local _, dx, dy = ns.ToView(2, "Duskwood", 0.5, 0.5)
	ns.view.Center(dx * k, dy * k, 6)
	tick(0.3)
	local n, x0, y0, x1, y1 = bounds("Duskwood")
	check(n > 0 and x0 >= bx0 and y0 >= by0 and x1 <= bx1 and y1 <= by1,
		format("fond du Bois de la Pénombre dans le rectangle de ses morceaux (%d-%d, %d-%d)", x0, x1, y0, y1))
	-- Hurlevent : son plan, sans le blason peint à gauche
	local _, sx, sy = ns.ToView(2, "Stormwind", 0.5, 0.5)
	ns.view.Center(sx * k, sy * k, 0.6 * ns.view.Size() / (ns.Zones[2].zones.Stormwind[1] * k))
	tick(0.3)
	n, x0, y0, x1, y1 = bounds("Stormwind")
	check(n > 0 and x0 >= 170 and x1 <= 900, format("fond de Hurlevent limité à son plan (%d-%d)", x0, x1))
	ns.Rebuild()
	Strata_Toggle()
end

-- #58 : le fond et les morceaux d'une zone coupés à son territoire réel (Data/Territory.lua, en
-- escalier de colonnes de 256 px) : le nom « Bois de la Pénombre » et la rive peints sous la
-- Forêt d'Elwynn ne passent plus sur le Bois de la Pénombre.
do
	-- Données : chaque zone dessinée a sa forme, dans sa carte.
	local bad, count = {}, 0
	for c = 1, 4 do
		for file, Z in pairs(ns.Zones[c].zones) do
			if not Z[5] and not ns.CITIES[file] then
				count = count + 1
				local t = ns.Territory[file]
				local ok = t and t[1] >= 0 and t[1] < t[2] and t[2] <= 1002
				local cols = 0
				for k = 3, 6 do
					local col = t and t[k]
					if col then
						cols = cols + 1
						if not (col[1] >= 0 and col[1] < col[2] and col[2] <= 668) then ok = false end
					end
				end
				if not ok or cols == 0 then bad[#bad + 1] = file end
			end
		end
	end
	check(count >= 60 and #bad == 0, format("territoire réel de %d zones, dans leur carte %s", count, table.concat(bad, ", ")))

	if not StrataFrame:IsShown() then Strata_Toggle() end
	SlashCmdList.STRATA("brouillard")
	ns.Rebuild()
	local k = 1000 / ns.VIEWS.azeroth.size.w
	local _, ex, ey = ns.ToView(2, "Elwynn", 0.5, 0.5)
	ns.view.Center(ex * k, ey * k, 6)
	tick(0.3)
	local origin = {}
	for _, o in ipairs(ns.Overlays.Elwynn) do origin[o[1]] = o end
	local pieces, below, banner = 0, {}, false
	local function walk(r)
		if r.kind == "Texture" and r:IsVisible() and r.cell and type(r.path) == "string" then
			local c = r.cell
			local name = r.path:match("^Interface\\WorldMap\\Elwynn\\(%u+)%d+$")
			local o = name and origin[name]
			if o then
				pieces = pieces + 1
				-- (à l'est de la marche de x = 512 : le terrain d'Elwynn s'arrête à la rive, 595 px)
				if o[4] + c[1] >= 575 and o[5] + c[4] > 600 then below[#below + 1] = name end
			elseif r.path:match("^Interface\\WorldMap\\Elwynn\\Elwynn%d+$") then
				-- la bannière « Hurlevent » (vers x = 100, y = 150) : Hurlevent compte dans Elwynn
				if c[1] <= 100 and c[3] > 100 and c[2] <= 150 and c[4] > 150 then banner = true end
			end
		end
		for _, ch in ipairs(r.children) do walk(ch) end
	end
	walk(StrataFrame)
	check(pieces > 20 and #below == 0, format("morceaux d'Elwynn coupés à la rive, au-dessus du nom peint « Bois de la Pénombre » (%d pièces) %s",
		pieces, table.concat(below, ", ")))
	check(banner, "fond d'Elwynn sous la bannière « Hurlevent » : la ville compte dans sa zone")
	SlashCmdList.STRATA("brouillard")
	ns.Rebuild()
	Strata_Toggle()
end

-- #62 : le territoire se limite à la terre (fond de la mer exclu) : les griffes peintes dans les
-- coins des cartes du Norfendre (haut-gauche, bas-droit) et la mer de la zone tombent dehors.
do
	if not StrataFrame:IsShown() then Strata_Toggle() end
	ns.Rebuild()
	local k = 1000 / ns.VIEWS.azeroth.size.w
	local _, bx, by = ns.ToView(4, "BoreanTundra", 0.5, 0.5)
	ns.view.Center(bx * k, by * k, 6)
	tick(0.3)
	local n, corners = 0, {}
	local function walk(r)
		if r.kind == "Texture" and r:IsVisible() and r.cell and type(r.path) == "string"
			and r.path:match("^Interface\\WorldMap\\BoreanTundra\\BoreanTundra%d+$") then
			local c = r.cell
			n = n + 1
			if (c[1] < 100 and c[2] < 100) or (c[3] > 880 and c[4] > 560) then
				corners[#corners + 1] = format("%d,%d", c[1], c[2])
			end
		end
		for _, ch in ipairs(r.children) do walk(ch) end
	end
	walk(StrataFrame)
	check(n > 0 and #corners == 0, format("Toundra Boréenne : rien dans les coins aux griffes (%d pièces) %s", n, table.concat(corners, " ")))
	-- #64 : l'Outreterre n'a pas de mer. Le sol du Néant tombe dehors (la boussole du coin bas-droit
	-- de Raz-de-Néant), mais les îles qui ne sont que des bâtiments (Donjon de la Tempête) restent.
	local t = ns.Territory.Netherstorm
	check(t[2] >= 880 and t[6] and t[6][2] < 580,
		format("Raz-de-Néant : Donjon de la Tempête gardé, boussole du coin écartée (%d, %s)", t[2], tostring(t[6] and t[6][2])))
	-- Préparation d'avance : la carte ouverte, toutes les zones de la vue finissent découpées.
	for _ = 1, 200 do
		if ns.Warmed() then break end
		frame()
	end
	check(ns.Warmed(), "toutes les zones de la vue préparées d'avance")
	ns.Rebuild()
	Strata_Toggle()
end

-- #66 : la bannière d'une ville sur la carte de sa zone est dessinée à part et s'efface quand la
-- ville paraît, comme dans OpenMap : plus de « …NERRE » coupé par le plan des Pitons-du-Tonnerre.
do
	if not StrataFrame:IsShown() then Strata_Toggle() end
	SlashCmdList.STRATA("brouillard")
	ns.Rebuild()
	local k = 1000 / ns.VIEWS.azeroth.size.w
	local b = ns.BANNERS.Mulgore
	local origin = {}
	for _, o in ipairs(ns.Overlays.Mulgore) do origin[o[1]] = o end
	-- Pièces des morceaux de Mulgore dans le rectangle de la bannière : visibles, et la plus opaque.
	local function banner()
		local n, inside, top = 0, 0, 0
		local function walk(r)
			if r.kind == "Texture" and r.cell and type(r.path) == "string" then
				local name = r.path:match("^Interface\\WorldMap\\Mulgore\\(%u+)%d+$")
				local o = name and origin[name]
				if o then
					local mx, my = o[4] + (r.cell[1] + r.cell[3]) / 2, o[5] + (r.cell[2] + r.cell[4]) / 2
					if mx > b[2] and mx < b[4] and my > b[3] and my < b[5] then
						inside = inside + 1
						if r:IsVisible() then
							n = n + 1
							local g = r.gradient
							top = math.max(top, g and math.max(g[2], g[3]) or 1)
						end
					end
				end
			end
			for _, ch in ipairs(r.children) do walk(ch) end
		end
		walk(StrataFrame)
		return n, inside, top
	end
	local Z = ns.Zones[1].zones
	local _, mx, my = ns.ToView(1, "Mulgore", 0.5, 0.5)
	ns.view.Center(mx * k, my * k, 0.5 * ns.view.Size() / (Z.Mulgore[1] * k))
	tick(0.3)
	local n, inside, top = banner()
	check(n > 0 and top > 0, format("Mulgore vue entière : bannière des Pitons-du-Tonnerre dessinée (%d pièces)", n))
	local _, tx, ty = ns.ToView(1, "ThunderBluff", 0.5, 0.5)
	ns.view.Center(tx * k, ty * k, 0.6 * ns.view.Size() / (Z.ThunderBluff[1] * k))
	tick(0.3)
	n, inside = banner()
	check(inside > 0 and n == 0, format("Pitons-du-Tonnerre affichés : la bannière de Mulgore effacée (%d visibles sur %d)", n, inside))
	SlashCmdList.STRATA("brouillard")
	ns.Rebuild()
	Strata_Toggle()
end
