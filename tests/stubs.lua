-- Copyright (C) 2026 BellaHealFr. Licence GPL-3.0-only avec conditions supplémentaires
-- (mention de l'auteur, nom « Strata » réservé) : voir LICENSE et NOTICE.md.

-- Un client 3.3.5 simulé, juste assez pour charger et faire tourner Strata hors du jeu.
-- Les cartes viennent de Data/Zones.lua : chaque zone non "sub" est une zone du client, avec
-- deux morceaux découverts factices. Le joueur est au milieu de la Forêt d'Elwynn.

local noop = function() end
tinsert = table.insert

TEST = { textures = 0, loaded = 0, setTextureCalls = 0, time = 0, cursor = { 500, 400 }, prints = {}, raid = 0 }

-- Appels à l'API comptés pour les budgets de performance (tests/helpers.lua).
TEST.count = setmetatable({}, { __index = function() return 0 end })
local function count(name) TEST.count[name] = TEST.count[name] + 1 end

-- Cadres -----------------------------------------------------------------------

local Region = {}
-- Méthode inconnue (Majuscule) : ne fait rien ; champ inconnu : nil.
Region.__index = function(t, k)
	return Region[k] or (type(k) == "string" and k:find("^%u") and noop) or nil
end

local function NewRegion(kind, parent)
	local r = setmetatable({ kind = kind, parent = parent, shown = true, w = 0, h = 0, scale = 1,
		level = parent and (parent.level or 0) + 1 or 0, scripts = {}, children = {} }, Region)
	if parent then tinsert(parent.children, r) end
	return r
end

function Region:SetWidth(w) self.w = w end
function Region:SetHeight(h) self.h = h end
function Region:GetWidth() return self.w end
function Region:GetHeight() return self.h end
function Region:Show()
	local was = self:IsVisible()
	self.shown = true
	if not was and self:IsVisible() and self.scripts.OnShow then self.scripts.OnShow(self) end
end
function Region:Hide()
	local was = self:IsVisible()
	self.shown = false
	if was and self.scripts.OnHide then self.scripts.OnHide(self) end
end
function Region:IsShown() return self.shown end
function Region:IsVisible()
	local r = self
	while r do
		if not r.shown then return false end
		r = r.parent
	end
	return true
end
-- Les cadres qui ont un OnUpdate reçoivent chaque image (tests/helpers.lua, frame()).
TEST.updaters = {}
function Region:HookScript(name, fn)
	local old = self.scripts[name]
	self:SetScript(name, old and function(...) old(...) fn(...) end or fn)
end
function Region:SetScript(name, fn)
	if name == "OnUpdate" and fn and not self.scripts.OnUpdate then tinsert(TEST.updaters, self) end
	self.scripts[name] = fn
end
function Region:GetScript(name) return self.scripts[name] end
function Region:SetScale(s) assert(s > 0, "échelle nulle") count("SetScale") self.scale = s end
function Region:GetScale() return self.scale end
function Region:GetEffectiveScale()
	local s, r = 1, self
	while r do s = s * r.scale; r = r.parent end
	return s
end
function Region:GetFrameLevel() return self.level end
function Region:SetFrameLevel(l) self.level = l end
function Region:GetLeft() return 100 end
function Region:GetTop() return 900 end
function Region:GetCenter() return self.cx or 0, self.cy or 0 end
function Region:IsMouseOver() return TEST.mouseOver end
function Region:GetPoint() return "CENTER", nil, "CENTER", 0, 0 end
function Region:SetPoint(point, rel, relPoint, x, y)
	count("SetPoint")
	if type(rel) == "number" then x, y, rel, relPoint = rel, relPoint, nil, nil end
	for _, v in ipairs({ x, y }) do
		assert(v == nil or (v == v and v ~= math.huge and v ~= -math.huge), "SetPoint : valeur invalide")
	end
	self.point = { point, x, y, rel = rel, relPoint = relPoint }
end
function Region:ClearAllPoints() self.point, self.allPoints = nil, nil end
function Region:SetAllPoints(rel) self.allPoints = rel or self.parent end
-- Dégradé de transparence (couleurs des sommets) : VERTICAL va du bas (min) vers le haut (max).
function Region:SetGradientAlpha(orient, r1, g1, b1, a1, r2, g2, b2, a2)
	count("SetGradientAlpha")
	assert(orient == "HORIZONTAL" or orient == "VERTICAL", "SetGradientAlpha : orientation")
	for _, v in ipairs({ a1, a2 }) do assert(type(v) == "number" and v >= 0 and v <= 1, "SetGradientAlpha : alpha invalide") end
	self.gradient = { orient, a1, a2 }
end
function Region:SetTexCoord(...)
	for i = 1, select("#", ...) do
		local v = select(i, ...)
		assert(type(v) == "number" and v == v, "SetTexCoord : valeur invalide")
	end
	self.texcoord = { ... }
end
function Region:SetTexture(path, ...)
	TEST.setTextureCalls = TEST.setTextureCalls + 1
	if path ~= nil then count("SetTexture") end
	if type(path) == "string" then
		assert(not path:find("nil"), "chemin de texture avec nil : " .. path)
	end
	self.path = path
	return 1
end
function Region:CreateTexture()
	TEST.textures = TEST.textures + 1
	count("CreateTexture")
	return NewRegion("Texture", self)
end
function Region:CreateFontString()
	local fs = NewRegion("FontString", self)
	fs.SetText = function(s, t) s.text = t end
	fs.SetFormattedText = function(s, f, ...) s.text = format(f, ...) end
	return fs
end
-- Comme dans le jeu, changer le texte d'un champ déclenche son OnTextChanged (userInput faux).
function Region:SetText(t)
	self.text = t
	if self.kind == "EditBox" and self.scripts.OnTextChanged then self.scripts.OnTextChanged(self, false) end
end
function Region:GetText() return self.text end
function Region:SetScrollChild(c) self.scrollChild = c end

function CreateFrame(kind, name, parent)
	local f = NewRegion(kind, parent or UIParent)
	if name then _G[name] = f end
	return f
end

UIParent = NewRegion("Frame")
UIParent.w, UIParent.h = 1920, 1080
WorldMapFrame = NewRegion("Frame", UIParent)
-- La minicarte : 140 px, centrée en (1000, 800) à l'écran.
Minimap = NewRegion("Frame", UIParent)
Minimap.w, Minimap.h, Minimap.cx, Minimap.cy = 140, 140, 1000, 800
WorldMapFrame.shown = false
DEFAULT_CHAT_FRAME = { AddMessage = function(_, msg) tinsert(TEST.prints, msg) end }
UISpecialFrames = {}
SlashCmdList = {}
RAID_CLASS_COLORS = { MAGE = { r = 0.4, g = 0.8, b = 1 } }
HideUIPanel = function(f) f:Hide() end
GameTooltip = NewRegion("GameTooltip", UIParent)

-- Fonctions globales de WoW -------------------------------------------------------

floor, ceil, min, max, abs = math.floor, math.ceil, math.min, math.max, math.abs
-- Dans WoW, cos et sin prennent des degrés : les stubs aussi, pour attraper la confusion.
cos = function(d) return math.cos(math.rad(d)) end
sin = function(d) return math.sin(math.rad(d)) end
tinsert, tremove, sort = table.insert, table.remove, table.sort
strlower, format = string.lower, string.format
strtrim = function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
GetTime = function() return TEST.time end
IsControlKeyDown = function() return TEST.ctrl end
GetCursorPosition = function() return TEST.cursor[1], TEST.cursor[2] end
GetLocale = function() return TEST.locale or "frFR" end
GetPlayerFacing = function() return 1.0 end
-- TEST.raid > 0 : un raid de TEST.raid joueurs, dont le joueur (raid1).
GetNumRaidMembers = function() return TEST.raid end
local function RaidIndex(u) return tonumber(u:match("^raid(%d+)$")) end
UnitExists = function(u)
	local i = RaidIndex(u)
	if i then return i <= TEST.raid end
	return u == "party1"
end
UnitIsUnit = function(a, b) return a == b or (a == "raid1" and b == "player") end
UnitClass = function() return "Mage", "MAGE" end
UnitLevel = function() return 12 end
-- Comme dans le jeu : une couleur selon l'écart entre le niveau et celui du joueur.
GetQuestDifficultyColor = function(level)
	if level - 12 >= 5 then return { r = 1, g = 0.1, b = 0.1 } end
	if level - 12 >= -2 then return { r = 1, g = 1, b = 0 } end
	return { r = 0.5, g = 0.5, b = 0.5 }
end
-- Mesure : un temps déterministe tiré du compte d'instructions (tests/helpers.lua).
debugprofilestop = function() return (TEST.ops or 0) * 0.002 end
GetFramerate = function() return 60 end
UpdateAddOnMemoryUsage = function() count("UpdateAddOnMemoryUsage") end
-- TEST.memory permet de simuler un client qui renvoie 0 (vu en jeu, #27).
GetAddOnMemoryUsage = function() return TEST.memory or 640 end
time, date = os.time, os.date

-- Cartes ----------------------------------------------------------------------------

local CONT_FILES = { "Kalimdor", "Azeroth", "Expansion01", "Northrend" }
local map = { c = 0, z = 0 }
local zoneLists = {}

function TEST.SetupMaps(Zones)
	for c = 1, 4 do
		local list = {}
		for file, Z in pairs(Zones[c].zones) do
			if not Z[5] then list[#list + 1] = file end
		end
		table.sort(list)
		zoneLists[c] = list
	end
end

SetMapZoom = function(c, z) count("SetMapZoom") map.c, map.z = c, z or 0 end
GetMapZones = function(c) return unpack(zoneLists[c]) end
GetMapContinents = function() return "Kalimdor", "Royaumes de l'Est", "Outreterre", "Norfendre" end
GetMapInfo = function()
	if map.c <= 0 then return nil end
	if map.z == 0 then return CONT_FILES[map.c] end
	return zoneLists[map.c][map.z]
end
GetCurrentMapContinent = function() return map.c end
GetCurrentMapZone = function() return map.z end
GetCurrentMapDungeonLevel = function() return 0 end
DungeonUsesTerrainMap = function() return false end
GetNumMapOverlays = function() return map.z > 0 and 2 or 0 end
GetMapOverlayInfo = function(i)
	local file = GetMapInfo()
	-- (à l'intérieur de la carte et du territoire réel d'Elwynn, Data/Territory.lua)
	if i == 1 then return "Interface\\WorldMap\\" .. file .. "\\Piece", 300, 200, 100, 100 end
	return "Interface\\WorldMap\\" .. file .. "\\Corner", 256, 512, 746, 156   -- (dans le coin bas-droit de la carte)
end

local function ElwynnIndex()
	for i, f in ipairs(zoneLists[2]) do if f == "Elwynn" then return i end end
end
SetMapToCurrentZone = function() count("SetMapToCurrentZone") map.c, map.z = 2, ElwynnIndex() end

-- Le joueur à 50 %, 50 % de la Forêt d'Elwynn ; party1 à 60 %, 40 % ; le raid en cercle autour.
GetPlayerMapPosition = function(unit)
	count("GetPlayerMapPosition")
	if map.c ~= 2 or map.z ~= ElwynnIndex() then return 0, 0 end
	local i = RaidIndex(unit)
	if i and i <= TEST.raid then
		local a = i / TEST.raid * 2 * math.pi
		return 0.5 + 0.2 * math.cos(a), 0.5 + 0.2 * math.sin(a)
	end
	-- TEST.px / TEST.py : déplacer le joueur dans la Forêt d'Elwynn (flèche de guidage, #38).
	if unit == "player" then return TEST.px or 0.5, TEST.py or 0.5 end
	if unit == "party1" then return 0.6, 0.4 end
	return 0, 0
end
