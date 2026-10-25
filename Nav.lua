-- Copyright (C) 2026 BellaHealFr. Licence GPL-3.0-only avec conditions supplémentaires
-- (mention de l'auteur, nom « Strata » réservé) : voir LICENSE et NOTICE.md.

-- Strata - Carte du monde continue pour World of Warcraft 3.3.5
-- Flèche de guidage : vers une épingle ou un point, à l'écran, même carte fermée, sans TomTom.
--
-- La cible est en yards de sa vue (comme les épingles) ; la position du joueur vient de
-- ns.UnitPos. Orientation : le cap vers la cible moins la direction du joueur (GetPlayerFacing,
-- 0 au nord, sens inverse des aiguilles d'une montre). Le cadre ne tourne que pendant un guidage.

local _, ns = ...

local L = ns.L

local ARRIVED = 10           -- yards : arrivé
local LEAVE_AFTER = 3        -- secondes entre « Arrivé » et le retrait de la flèche
local TEXT_EVERY = 0.2       -- secondes entre deux mises à jour du texte
local FACING = math.rad(15)  -- tolérance pour colorer la flèche « dans la bonne direction »

ns.nav = {}

local arrow
local speed, lastDist, lastTime, textWait, arrivedAt

local function Target()
	return ns.db and ns.db.target
end

local function FormatTime(s)
	s = math.floor(s + 0.5)
	if s < 60 then return format(L.NAV_SECONDS, s) end
	return format(L.NAV_MINUTES, math.floor(s / 60), s % 60)
end

local function OnUpdate(self, elapsed)
	local t = Target()
	if not t then self:Hide() return end
	local view, px, py = ns.UnitPos("player")
	textWait = textWait - elapsed

	if not view then
		ns.nav.angle = nil
		self.icon:Hide()
		if textWait <= 0 then
			self.distance:SetText(L.NAV_UNKNOWN)
			self.eta:SetText("")
			textWait = TEXT_EVERY
		end
		return
	end
	if view ~= t.view then
		ns.nav.angle = nil
		self.icon:Hide()
		self.distance:SetText(L.NAV_ELSEWHERE)
		self.eta:SetText("")
		return
	end

	local dx, dy = t.x - px, t.y - py
	local dist = math.sqrt(dx * dx + dy * dy)
	-- Cap vers la cible, compté comme GetPlayerFacing : 0 au nord (y vers le haut de la carte).
	local bearing = math.atan2(-dx, -dy)
	local angle = bearing - (GetPlayerFacing() or 0)
	ns.nav.angle, ns.nav.distance = angle, dist
	self.icon:Show()
	ns.RotateTexture(self.icon, angle)
	local off = (angle + math.pi) % (2 * math.pi) - math.pi
	if math.abs(off) < FACING then
		self.icon:SetVertexColor(0.4, 1, 0.4)
	else
		self.icon:SetVertexColor(1, 0.82, 0)
	end

	if dist < ARRIVED then
		arrivedAt = arrivedAt or GetTime()
		self.distance:SetText(L.NAV_ARRIVED)
		self.eta:SetText("")
		if GetTime() - arrivedAt >= LEAVE_AFTER then ns.StopFollow() end
		return
	end
	arrivedAt = nil

	if textWait <= 0 then
		local now = GetTime()
		if lastDist and now > lastTime then
			-- Vitesse d'approche lissée : le temps estimé ne saute pas à chaque pas.
			local v = (lastDist - dist) / (now - lastTime)
			speed = speed and speed + (v - speed) * 0.3 or v
		end
		lastDist, lastTime = dist, now
		self.distance:SetFormattedText(L.NAV_DISTANCE, dist)
		if speed and speed > 0.5 then
			self.eta:SetText(FormatTime(dist / speed))
		else
			self.eta:SetText("")
		end
		textWait = TEXT_EVERY
	end
end

local function Create()
	arrow = CreateFrame("Frame", "StrataArrow", UIParent)
	arrow:SetWidth(90)
	arrow:SetHeight(84)
	local p = ns.db.arrowPoint
	if p then
		arrow:SetPoint(p[1], UIParent, p[1], p[2], p[3])
	else
		arrow:SetPoint("TOP", 0, -120)
	end
	arrow:SetFrameStrata("MEDIUM")
	arrow:SetClampedToScreen(true)
	arrow:EnableMouse(true)
	arrow:SetMovable(true)
	arrow:RegisterForDrag("LeftButton")
	arrow:SetScript("OnDragStart", arrow.StartMoving)
	arrow:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local point, _, _, x, y = self:GetPoint()
		ns.db.arrowPoint = { point, x, y }
	end)
	arrow:SetScript("OnMouseUp", function(self, button)
		if button == "RightButton" then ns.StopFollow() end
	end)
	arrow:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
		GameTooltip:AddLine(Target() and Target().label or "Strata")
		GameTooltip:AddLine(L.NAV_TIP, 0.6, 0.6, 0.6)
		GameTooltip:Show()
	end)
	arrow:SetScript("OnLeave", function() GameTooltip:Hide() end)

	arrow.icon = arrow:CreateTexture(nil, "ARTWORK")
	arrow.icon:SetTexture("Interface\\Minimap\\MinimapArrow")
	arrow.icon:SetWidth(48)
	arrow.icon:SetHeight(48)
	arrow.icon:SetPoint("TOP")
	arrow.distance = arrow:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	arrow.distance:SetPoint("TOP", arrow.icon, "BOTTOM", 0, 2)
	arrow.eta = arrow:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	arrow.eta:SetPoint("TOP", arrow.distance, "BOTTOM", 0, -1)
	arrow:SetScript("OnUpdate", OnUpdate)
	arrow:Hide()
end

-- Guide vers un point (vue, yards). label : le nom affiché dans l'infobulle.
function ns.Follow(view, x, y, label)
	if not arrow then Create() end
	ns.db.target = { view = view, x = x, y = y, label = label }
	speed, lastDist, lastTime, arrivedAt = nil, nil, nil, nil
	textWait = 0
	arrow:Show()
end

function ns.StopFollow()
	if ns.db then ns.db.target = nil end
	ns.nav.angle, ns.nav.distance = nil, nil
	if arrow then arrow:Hide() end
end

-- Reprendre le guidage après un rechargement.
local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function()
	local t = Target()
	if t then ns.Follow(t.view, t.x, t.y, t.label) end
end)
