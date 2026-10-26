-- Copyright (C) 2026 BellaHealFr. Licence GPL-3.0-only avec conditions supplémentaires
-- (mention de l'auteur, nom « Strata » réservé) : voir LICENSE et NOTICE.md.

-- Outils communs aux scénarios du banc : recherche dans l'interface, temps, vérifications,
-- et mesure du travail par image.
--
-- Le travail est compté, pas chronométré : instructions Lua exécutées (par paquets de 100,
-- via debug.sethook) et appels à l'API du client simulé (TEST.count). Les deux sont
-- déterministes : même code, même résultat, sur n'importe quelle machine. Les budgets de
-- tests/budgets.lua s'appliquent à ces chiffres.

function find(region, test)
	if test(region) then return region end
	for _, c in ipairs(region.children) do
		local r = find(c, test)
		if r then return r end
	end
end

local function countTextures(region, onlyVisible, n)
	n = n or 0
	if region.kind == "Texture" and region.path and (not onlyVisible or region:IsVisible()) then n = n + 1 end
	for _, c in ipairs(region.children) do n = countTextures(c, onlyVisible, n) end
	return n
end

-- Textures affichées.
function visibleTextures(region) return countTextures(region, true) end

-- Fichiers chargés (textures affichées ou non) : la mémoire. Plusieurs morceaux d'une même tuile
-- (bord adouci) partagent un fichier, que le client ne charge qu'une fois.
function loadedTextures(region, seen)
	seen = seen or {}
	local n = 0
	if region.kind == "Texture" and region.path and not seen[region.path] then
		seen[region.path] = true
		n = 1
	end
	for _, c in ipairs(region.children) do n = n + loadedTextures(c, seen) end
	return n
end

-- Fichiers de tuiles de carte chargés (Interface\WorldMap\...), comptés une fois chacun : sans les
-- icônes (épingles, joueur), qui partagent quelques petits fichiers.
function loadedMapTiles(region, seen)
	seen = seen or {}
	local n = 0
	if region.kind == "Texture" and type(region.path) == "string" and not seen[region.path]
		and region.path:find("Interface\\WorldMap\\", 1, true) == 1 then
		seen[region.path] = true
		n = 1
	end
	for _, c in ipairs(region.children) do n = n + loadedMapTiles(c, seen) end
	return n
end

-- Une image : le temps avance de 20 ms et chaque cadre visible reçoit son OnUpdate.
function frame()
	TEST.time = TEST.time + 0.02
	for _, f in ipairs(TEST.updaters) do
		-- f.shown d'abord : un cadre masqué est écarté sans remonter ses parents (coût du banc,
		-- pas de l'addon : le jeu n'appelle pas l'OnUpdate d'un cadre masqué).
		if f.shown and f:IsVisible() and f.scripts.OnUpdate then f.scripts.OnUpdate(f, 0.02) end
	end
end

function tick(seconds)
	for _ = 1, math.floor(seconds / 0.02 + 0.5) do frame() end
end

function check(cond, msg)
	if not cond then error("ÉCHEC : " .. msg, 2) end
	print("ok   " .. msg)
end

-- Mesure ------------------------------------------------------------------------------

TEST.ops = 0
debug.sethook(function() TEST.ops = TEST.ops + 1 end, "", 100)

local function snapshot()
	local s = { ops = TEST.ops }
	for k, v in pairs(TEST.count) do s[k] = v end
	return s
end

-- Un compteur jamais appelé vaut 0.
local function zeros() return setmetatable({}, { __index = function() return 0 end }) end

local function delta(a, b)
	local d = zeros()
	for k, v in pairs(b) do d[k] = v - (a[k] or 0) end
	return d
end

-- Mesure une action unique : le travail total qu'elle a demandé.
function measure(fn)
	local before = snapshot()
	fn()
	return delta(before, snapshot())
end

-- Mesure n images ; step(i), s'il est donné, agit avant chaque image (déplacer la souris…).
-- Renvoie, pour chaque compteur, la moyenne et le maximum par image.
function measureFrames(n, step)
	local sum, peak = zeros(), zeros()
	for i = 1, n do
		local before = snapshot()
		if step then step(i) end
		frame()
		for k, v in pairs(delta(before, snapshot())) do
			sum[k] = sum[k] + v
			peak[k] = math.max(peak[k], v)
		end
	end
	local mean = zeros()
	for k, v in pairs(sum) do mean[k] = v / n end
	return mean, peak
end

-- Budgets -----------------------------------------------------------------------------

TEST.report = {}

-- Compare une valeur à son budget (tests/budgets.lua). Un budget absent est une erreur :
-- toute nouvelle mesure doit recevoir le sien.
function budget(name, value)
	local limit = BUDGETS[name]
	if limit == nil then error("ÉCHEC : aucun budget pour « " .. name .. " » dans tests/budgets.lua", 2) end
	local ok = value <= limit
	tinsert(TEST.report, { name = name, value = value, limit = limit, ok = ok })
	print(format("%s   %-42s %10.1f  (budget %s)", ok and "ok" or "!!", name, value, limit))
	if not ok then
		TEST.failed = (TEST.failed or 0) + 1
	end
end
