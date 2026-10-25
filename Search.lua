-- Copyright (C) 2026 BellaHealFr. Licence GPL-3.0-only avec conditions supplémentaires
-- (mention de l'auteur, nom « Strata » réservé) : voir LICENSE et NOTICE.md.

-- Strata - Carte du monde continue pour World of Warcraft 3.3.5
-- Recherche de zones et de villes : un champ dans la barre du bas, les résultats au-dessus.
--
-- Les noms sont ceux du client (GetMapZones), donc dans sa langue. La comparaison ignore
-- majuscules et accents : « foret » trouve « Forêt d'Elwynn ». Le travail n'a lieu qu'à la frappe.

local _, ns = ...

local L = ns.L
local Zones = ns.Zones

local MAX_RESULTS = 8

-- Lettres accentuées (UTF-8) ramenées à leur lettre de base, minuscules comprises.
local PLAIN = {
	["à"] = "a", ["â"] = "a", ["ä"] = "a", ["À"] = "a", ["Â"] = "a", ["Ä"] = "a",
	["é"] = "e", ["è"] = "e", ["ê"] = "e", ["ë"] = "e", ["É"] = "e", ["È"] = "e", ["Ê"] = "e", ["Ë"] = "e",
	["î"] = "i", ["ï"] = "i", ["Î"] = "i", ["Ï"] = "i",
	["ô"] = "o", ["ö"] = "o", ["Ô"] = "o", ["Ö"] = "o",
	["ù"] = "u", ["û"] = "u", ["ü"] = "u", ["Ù"] = "u", ["Û"] = "u", ["Ü"] = "u",
	["ç"] = "c", ["Ç"] = "c", ["ñ"] = "n", ["Ñ"] = "n",
}

local function Plain(s)
	s = s:gsub("’", "'"):gsub("[\192-\223][\128-\191]", PLAIN)
	return strlower(s)
end
ns.Plain = Plain

--------------------------------------------------------------------------------
-- Index : une entrée par zone dessinée, construite à la première recherche (après la lecture
-- des cartes, qui donne les noms).

local index

local function BuildIndex()
	index = {}
	for view, def in pairs(ns.VIEWS) do
		local k = 1000 / def.size.w
		for _, c in ipairs(def.continents) do
			local C = Zones[c]
			local ox, oy = 0, 0
			if C.parent == 0 then ox, oy = C.x, C.y end
			local map = ns.maps[c]
			for file, Z in pairs(C.zones) do
				local info = map and map.zones[file]
				if not Z[5] and info then
					local name = info.name or file
					index[#index + 1] = {
						name = name, plain = Plain(name), continent = map.name, view = view,
						x = (ox + Z[3]) * k, y = (oy + Z[4]) * k, w = Z[1] * k, h = Z[2] * k,
					}
				end
			end
		end
	end
end

-- Pertinence : 0 si le nom commence par la recherche, 1 si un de ses mots commence par elle
-- (« elw » dans « Forêt d'Elwynn »), 2 si elle est au milieu d'un mot (« Felwood »).
local function Rank(plain, q)
	if plain:sub(1, #q) == q then return 0 end
	if plain:find(" " .. q, 1, true) or plain:find("'" .. q, 1, true) or plain:find("-" .. q, 1, true) then return 1 end
	return 2
end

-- Zones dont le nom contient chaque mot de la recherche, les plus pertinentes d'abord, puis les
-- plus courtes.
function ns.Search(query)
	if not index then BuildIndex() end
	local q = Plain(strtrim(query or ""))
	local found = {}
	if q == "" then return found end
	local words = {}
	for word in q:gmatch("%S+") do words[#words + 1] = word end
	for _, z in ipairs(index) do
		local ok = true
		for _, word in ipairs(words) do
			if not z.plain:find(word, 1, true) then ok = false break end
		end
		if ok then found[#found + 1] = z end
	end
	for _, z in ipairs(found) do z.rank = Rank(z.plain, q) end
	sort(found, function(a, b)
		if a.rank ~= b.rank then return a.rank < b.rank end
		if #a.plain ~= #b.plain then return #a.plain < #b.plain end
		return a.plain < b.plain
	end)
	return found
end

--------------------------------------------------------------------------------
-- Interface

local box, hint, results, rows, current

-- Amène la carte sur une zone, au zoom où elle tient dans la fenêtre.
local function Go(z)
	ns.view.Show(z.view)
	local vw, vh = ns.view.Size()
	local zoom = math.min(vw / z.w, vh / z.h) * 0.9
	ns.view.Center(z.x + z.w / 2, z.y + z.h / 2, zoom)
	results:Hide()
	box:SetText("")
	box:ClearFocus()
end

local function ShowResults()
	current = ns.Search(box:GetText())
	if box:GetText() == "" then
		results:Hide()
		return
	end
	local n = math.min(#current, MAX_RESULTS)
	for i = 1, MAX_RESULTS do
		local row, z = rows[i], current[i]
		if z then
			row.name:SetText(z.name)
			row.where:SetText(z.continent or "")
			row.zone = z
			row:Show()
		else
			row:Hide()
		end
	end
	if n == 0 then
		rows[1].name:SetText("|cff888888" .. L.SEARCH_NONE .. "|r")
		rows[1].where:SetText("")
		rows[1].zone = nil
		rows[1]:Show()
		n = 1
	end
	results:SetHeight(n * 18 + 12)
	results:Show()
end

function ns.CreateSearch(frame, after)
	-- Nommé : InputBoxTemplate nomme ses textures d'après le parent ($parentLeft…).
	box = CreateFrame("EditBox", "StrataSearchBox", frame, "InputBoxTemplate")
	box:SetWidth(150)
	box:SetHeight(20)
	box:SetPoint("LEFT", after, "RIGHT", 12, 0)
	box:SetAutoFocus(false)
	box:SetMaxLetters(40)
	hint = box:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	hint:SetPoint("LEFT", 2, 0)
	hint:SetText(L.SEARCH)

	results = CreateFrame("Frame", nil, frame)
	results:SetPoint("BOTTOMLEFT", box, "TOPLEFT", -6, 2)
	results:SetWidth(260)
	results:SetFrameLevel(frame:GetFrameLevel() + 50)
	results:SetBackdrop({
		bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true, tileSize = 16, edgeSize = 12,
		insets = { left = 3, right = 3, top = 3, bottom = 3 },
	})
	results:SetBackdropColor(0, 0, 0, 0.9)
	results:Hide()

	rows = {}
	for i = 1, MAX_RESULTS do
		local row = CreateFrame("Button", nil, results)
		row:SetHeight(18)
		row:SetPoint("TOPLEFT", 6, -6 - (i - 1) * 18)
		row:SetPoint("TOPRIGHT", -6, -6 - (i - 1) * 18)
		row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
		row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		row.name:SetPoint("LEFT", 4, 0)
		row.where = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
		row.where:SetPoint("RIGHT", -4, 0)
		row:SetScript("OnClick", function(self)
			if self.zone then Go(self.zone) end
		end)
		rows[i] = row
	end

	box:SetScript("OnTextChanged", function(self)
		if self:GetText() == "" and not self.focused then hint:Show() else hint:Hide() end
		ShowResults()
	end)
	box:SetScript("OnEditFocusGained", function(self)
		self.focused = true
		hint:Hide()
	end)
	box:SetScript("OnEditFocusLost", function(self)
		self.focused = nil
		if self:GetText() == "" then hint:Show() end
	end)
	box:SetScript("OnEnterPressed", function(self)
		if current and current[1] then Go(current[1]) else self:ClearFocus() end
	end)
	box:SetScript("OnEscapePressed", function(self)
		self:SetText("")
		results:Hide()
		self:ClearFocus()
	end)
	frame:HookScript("OnHide", function() results:Hide() end)
end
