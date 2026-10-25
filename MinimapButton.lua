-- Copyright (C) 2026 BellaHealFr. Licence GPL-3.0-only avec conditions supplémentaires
-- (mention de l'auteur, nom « Strata » réservé) : voir LICENSE et NOTICE.md.

-- Strata - Carte du monde continue pour World of Warcraft 3.3.5
-- Le bouton autour de la minicarte : ouvrir la carte sans commande.
--
-- Aspect standard des boutons de minicarte 3.3.5 (fond, icône, bordure de suivi), sans
-- bibliothèque. Placé sur le pourtour de la minicarte selon un angle retenu par compte ; sur une
-- minicarte carrée (GetMinimapShape, défini par ElvUI et les addons de minicarte), il longe le bord
-- du carré. Aucun OnUpdate en dehors d'un glisser.

local _, ns = ...

local L = ns.L

local button

-- Distance du centre de la minicarte au centre du bouton : le bord, plus une demi-marge.
local function Radius()
	return Minimap:GetWidth() / 2 + 10
end

function ns.PlaceMinimapButton()
	if not button then return end
	local a = math.rad(ns.db.minimapAngle or 200)
	local x, y = math.cos(a), math.sin(a)
	if GetMinimapShape and GetMinimapShape() == "SQUARE" then
		-- Projeter le cercle sur le carré : le plus grand des deux reste au bord.
		local d = math.max(math.abs(x), math.abs(y))
		x, y = x / d, y / d
	end
	local r = Radius()
	button:ClearAllPoints()
	button:SetPoint("CENTER", Minimap, "CENTER", x * r, y * r)
end

local function ShowTooltip(self)
	GameTooltip:SetOwner(self, "ANCHOR_LEFT")
	GameTooltip:AddLine("Strata")
	GameTooltip:AddLine(ns.version, 0.6, 0.6, 0.6)
	GameTooltip:AddLine(" ")
	GameTooltip:AddLine(L.TIP_TOGGLE, 1, 1, 1)
	GameTooltip:AddLine(L.TIP_DRAG, 0.6, 0.6, 0.6)
	GameTooltip:Show()
end

local function FollowCursor(self)
	local mx, my = Minimap:GetCenter()
	local scale = Minimap:GetEffectiveScale()
	local px, py = GetCursorPosition()
	ns.db.minimapAngle = math.deg(math.atan2(py / scale - my, px / scale - mx))
	ns.PlaceMinimapButton()
end

local function Create()
	button = CreateFrame("Button", "StrataMinimapButton", Minimap)
	button:SetWidth(31)
	button:SetHeight(31)
	button:SetFrameStrata("MEDIUM")
	button:SetFrameLevel(8)
	button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

	local background = button:CreateTexture(nil, "BACKGROUND")
	background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
	background:SetWidth(20)
	background:SetHeight(20)
	background:SetPoint("TOPLEFT", 7, -5)
	local icon = button:CreateTexture(nil, "ARTWORK")
	icon:SetTexture("Interface\\Icons\\INV_Misc_Map_01")
	icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
	icon:SetWidth(17)
	icon:SetHeight(17)
	icon:SetPoint("TOPLEFT", 7, -6)
	local border = button:CreateTexture(nil, "OVERLAY")
	border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
	border:SetWidth(53)
	border:SetHeight(53)
	border:SetPoint("TOPLEFT")

	-- Clic droit réservé au menu des options (#16).
	button:RegisterForClicks("LeftButtonUp")
	button:SetScript("OnClick", function() ns.Toggle() end)
	button:SetScript("OnEnter", ShowTooltip)
	button:SetScript("OnLeave", function() GameTooltip:Hide() end)

	button:RegisterForDrag("LeftButton")
	button:SetScript("OnDragStart", function(self)
		GameTooltip:Hide()
		self:SetScript("OnUpdate", FollowCursor)
	end)
	button:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)

	ns.PlaceMinimapButton()
	if ns.db.hideMinimapButton then button:Hide() end
end

function ns.ToggleMinimapButton()
	ns.db.hideMinimapButton = not ns.db.hideMinimapButton
	if button then
		if ns.db.hideMinimapButton then button:Hide() else button:Show() end
	end
	ns.Print(ns.db.hideMinimapButton and L.BUTTON_HIDDEN or L.BUTTON_SHOWN)
end

-- À la connexion : la minicarte et les réglages (ADDON_LOADED) sont prêts.
local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function(self)
	self:UnregisterEvent("PLAYER_LOGIN")
	if not button then Create() end
end)
