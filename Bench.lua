-- Copyright (C) 2026 BellaHealFr. Licence GPL-3.0-only avec conditions supplémentaires
-- (mention de l'auteur, nom « Strata » réservé) : voir LICENSE et NOTICE.md.

-- Strata - Carte du monde continue pour World of Warcraft 3.3.5
-- Mesure en jeu : le compteur à l'écran (/strata debug) et le parcours de mesure (/strata bench).
--
-- Le banc du dépôt compte le travail du code ; ici on mesure ce qu'il ne voit pas : images par
-- seconde réelles (rendu compris), millisecondes de Strata par image (debugprofilestop) et mémoire
-- Lua de l'addon. Rien ne tourne tant que ni le compteur ni le bench ne sont actifs.

local _, ns = ...

local L = ns.L
local stats = ns.stats

-- Objectifs de docs/FEUILLE-DE-ROUTE.md (« Objectifs de performance en jeu »).
local GOAL_FPS_DROP = 0.10   -- images par seconde carte ouverte : au plus 10 % de moins que fermée
local GOAL_PAN_AVG = 1       -- ms de Strata par image en déplacement, en moyenne
local GOAL_PAN_WORST = 5     -- ms, pire image
local GOAL_MEMORY = 2048     -- Ko de mémoire Lua après le parcours

local overlay, overlayText, results, resultsBox
local bench

local function UpdateMeasuring()
	ns.measuring = (overlay and overlay:IsShown()) or bench ~= nil
end

local function ResetWindow()
	stats.frames, stats.ms, stats.worst = 0, 0, 0
end

local function Memory()
	UpdateAddOnMemoryUsage()
	return GetAddOnMemoryUsage("Strata")
end

--------------------------------------------------------------------------------
-- Compteur à l'écran

local function CreateOverlay(parent)
	overlay = CreateFrame("Frame", nil, parent)
	overlay:SetPoint("TOPLEFT", 16, -34)
	overlay:SetWidth(250)
	overlay:SetHeight(52)
	overlay:SetFrameLevel(parent:GetFrameLevel() + 40)
	overlay:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background" })
	overlay:SetBackdropColor(0, 0, 0, 0.7)
	overlayText = overlay:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	overlayText:SetPoint("TOPLEFT", 6, -6)
	overlayText:SetJustifyH("LEFT")
	overlay:Hide()

	local wait, memWait, memory = 0, 0, 0
	overlay:SetScript("OnUpdate", function(self, elapsed)
		wait, memWait = wait - elapsed, memWait - elapsed
		if wait > 0 then return end
		wait = 0.5
		if memWait <= 0 then
			-- UpdateAddOnMemoryUsage parcourt tous les addons : pas plus d'une fois toutes les 2 s.
			memory, memWait = Memory(), 2
		end
		local avg = stats.frames > 0 and stats.ms / stats.frames or 0
		overlayText:SetFormattedText(L.DEBUG_TEXT, GetFramerate(), avg, stats.worst, stats.layersMs,
			stats.textures, stats.zones, memory)
		if not bench then ResetWindow() end
	end)
	overlay:SetScript("OnShow", UpdateMeasuring)
	overlay:SetScript("OnHide", UpdateMeasuring)
end

function ns.ToggleDebug()
	local frame = ns.view.Frame()
	if not frame or not frame:IsShown() then ns.Open() end
	frame = ns.view.Frame()
	if not overlay then CreateOverlay(frame) end
	if overlay:IsShown() then
		overlay:Hide()
	else
		ResetWindow()
		overlay:Show()
	end
end

--------------------------------------------------------------------------------
-- Résultats

local function CreateResults()
	results = CreateFrame("Frame", "StrataBenchFrame", UIParent)
	results:SetWidth(520)
	results:SetHeight(330)
	results:SetPoint("CENTER")
	results:SetFrameStrata("DIALOG")
	results:SetToplevel(true)
	results:EnableMouse(true)
	results:SetMovable(true)
	results:RegisterForDrag("LeftButton")
	results:SetScript("OnDragStart", results.StartMoving)
	results:SetScript("OnDragStop", results.StopMovingOrSizing)
	results:SetBackdrop({
		bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
		edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
		tile = true, tileSize = 32, edgeSize = 24,
		insets = { left = 6, right = 6, top = 6, bottom = 6 },
	})
	tinsert(UISpecialFrames, "StrataBenchFrame")

	local title = results:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	title:SetPoint("TOPLEFT", 16, -14)
	title:SetText(L.BENCH_TITLE)
	local hint = results:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	hint:SetPoint("BOTTOMLEFT", 16, 14)
	hint:SetText(L.BENCH_COPY)
	local close = CreateFrame("Button", nil, results, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", -4, -4)

	resultsBox = CreateFrame("EditBox", nil, results)
	resultsBox:SetPoint("TOPLEFT", 16, -36)
	resultsBox:SetPoint("BOTTOMRIGHT", -16, 32)
	resultsBox:SetMultiLine(true)
	resultsBox:SetAutoFocus(false)
	resultsBox:SetFontObject(GameFontHighlightSmall)
	resultsBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	-- Le texte reste celui du bench même si l'on tape dedans : il ne sert qu'à être copié.
	resultsBox:SetScript("OnTextChanged", function(self, user)
		if user and results.text then self:SetText(results.text) end
	end)
end

local function Verdict(ok)
	return ok and L.OK or L.TO_CHECK
end

local function Report(r)
	local lines = {
		format("Strata %s - %s - %s", r.version, L.BENCH_TITLE, date("%Y-%m-%d %H:%M", r.time)),
		"",
		L.BENCH_HEADER,
	}
	for _, p in ipairs(r.phases) do
		local ms = p.ms and format("%.2f / %.2f", p.ms, p.worst) or "-"
		lines[#lines + 1] = format("%s   %.0f   %s   %d", L.PHASES[p.key], p.fps, ms, p.peak)
	end
	lines[#lines + 1] = ""
	lines[#lines + 1] = format(L.BENCH_MEMORY, r.memory)
	lines[#lines + 1] = ""
	lines[#lines + 1] = L.BENCH_GOALS

	local byKey = {}
	for _, p in ipairs(r.phases) do byKey[p.key] = p end
	local closed, still, pan = byKey.closed, byKey.still, byKey.pan
	local drop = closed.fps > 0 and (closed.fps - still.fps) / closed.fps or 0
	lines[#lines + 1] = format(L.GOAL_FPS, still.fps, closed.fps, -drop * 100, Verdict(drop <= GOAL_FPS_DROP))
	lines[#lines + 1] = format(L.GOAL_PAN, pan.ms or 0, pan.worst or 0,
		Verdict((pan.ms or 0) < GOAL_PAN_AVG and (pan.worst or 0) < GOAL_PAN_WORST))
	lines[#lines + 1] = format(L.GOAL_MEMORY, r.memory, Verdict(r.memory < GOAL_MEMORY))
	return table.concat(lines, "\n")
end

local function ShowResults(r)
	if not results then CreateResults() end
	results.text = Report(r)
	resultsBox:SetText(results.text)
	results:Show()
	resultsBox:SetFocus()
	resultsBox:HighlightText()
end

--------------------------------------------------------------------------------
-- Parcours

-- Le joueur en unités du canevas de sa vue, ou le milieu de la vue courante.
local function PlayerPoint()
	local view, x, y = ns.UnitPos("player")
	if view then
		local k = 1000 / ns.VIEWS[view].size.w
		return view, x * k, y * k
	end
	local name, _, _, _, w, h = ns.view.Get()
	return name, w / 2, h / 2
end

local PHASES = {
	{ key = "closed", time = 2, setup = function()
		ns.view.Frame():Hide()
	end },
	{ key = "still", time = 3, setup = function(b)
		ns.Open()
		local view, x, y = PlayerPoint()
		ns.view.Show(view)
		ns.view.Center(x, y, 6)
		b.home = { view, x, y }
	end },
	-- Aller-retour, pour ne jamais buter sur un bord de la carte.
	{ key = "pan", time = 4, step = function(b, dt, t)
		local dir = (t % 2 < 1) and -1 or 1
		ns.view.Pan(dir * 360 * dt, dir * 120 * dt)
	end },
	{ key = "zoom", time = 4, step = function(b, dt, t)
		local z = 3 * (20 / 3) ^ ((1 - math.cos(t * math.pi / 2)) / 2)
		ns.view.Center(b.home[2], b.home[3], z)
	end },
	{ key = "tour", time = 8, setup = function(b)
		ns.view.Show("azeroth")
		local _, _, _, _, w, h = ns.view.Get()
		b.points = {}
		for gy = 0.2, 0.8, 0.2 do
			for gx = 0.1, 0.9, 0.2 do b.points[#b.points + 1] = { gx * w, gy * h } end
		end
	end, step = function(b, dt, t)
		local p = b.points[math.min(#b.points, math.floor(t / 0.4) + 1)]
		ns.view.Center(p[1], p[2], 6)
	end },
	{ key = "world", time = 2, setup = function()
		local _, _, _, _, w, h = ns.view.Get()
		ns.view.Center(w / 2, h / 2, ns.view.ZoomMin())
	end },
}

local driver = CreateFrame("Frame")
driver:Hide()

local function Finish(b, cancelled)
	driver:Hide()
	bench, ns.benching = nil, nil
	UpdateMeasuring()
	local frame = ns.view.Frame()
	if b.saved then
		if not frame:IsShown() then ns.Open() end
		ns.view.Show(b.saved[1])
		ns.view.Center(b.saved[3], b.saved[4], b.saved[2])
	end
	if cancelled then
		ns.Print(L.BENCH_STOPPED)
		return
	end
	local r = { version = ns.version, time = time(), phases = b.results, memory = Memory() }
	ns.db.lastBench = r
	ns.Print(L.BENCH_DONE)
	ShowResults(r)
end

local function StartPhase(b, i)
	b.index, b.t, b.frames = i, 0, 0
	b.peak = stats.textures
	ResetWindow()
	local phase = PHASES[i]
	if phase.setup then phase.setup(b) end
end

local function EndPhase(b)
	local phase = PHASES[b.index]
	b.results[#b.results + 1] = {
		key = phase.key,
		fps = b.t > 0 and b.frames / b.t or 0,
		ms = stats.frames > 0 and stats.ms / stats.frames or nil,
		worst = stats.frames > 0 and stats.worst or nil,
		peak = b.peak,
	}
end

driver:SetScript("OnUpdate", function(self, elapsed)
	local b = bench
	b.t, b.frames = b.t + elapsed, b.frames + 1
	if stats.textures > b.peak then b.peak = stats.textures end
	local phase = PHASES[b.index]
	if b.t >= phase.time then
		EndPhase(b)
		if b.index == #PHASES then return Finish(b) end
		StartPhase(b, b.index + 1)
	elseif phase.step then
		ns.view.Stop()
		phase.step(b, elapsed, b.t)
	end
end)

function ns.Bench()
	if bench then return Finish(bench, true) end
	local frame = ns.view.Frame()
	if not frame or not frame:IsShown() then ns.Open() end
	if results then results:Hide() end
	local name, z, cx, cy = ns.view.Get()
	bench = { results = {}, saved = { name, z, cx, cy } }
	ns.benching = true
	UpdateMeasuring()
	ns.view.Stop()
	ns.Print(L.BENCH_RUNNING)
	StartPhase(bench, 1)
	driver:Show()
end
