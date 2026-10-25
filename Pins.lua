-- Copyright (C) 2026 BellaHealFr. Licence GPL-3.0-only avec conditions supplémentaires
-- (mention de l'auteur, nom « Strata » réservé) : voir LICENSE et NOTICE.md.

-- Strata - Carte du monde continue pour World of Warcraft 3.3.5
-- Épingles : Ctrl-clic pour en poser une, avec une note et une icône ; liste ; flèche TomTom.
--
-- Les épingles sont posées sur le canevas de la carte (couche « pins »), en unités du canevas :
-- un déplacement les emporte sans aucun travail par épingle. Seul un changement de zoom les
-- redimensionne (PIN_SIZE / zoom), pour qu'elles gardent leur taille à l'écran.
-- Gardées par compte dans StrataDB.pins : { view, x, y (yards de la vue), note, icon }.

local _, ns = ...

local L = ns.L

local PIN_SIZE = 18              -- px à l'écran
local ICON = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_"
local LIST_ROWS = 12

local canvas                     -- le canevas affiché (Map.lua), avec ses boutons d'épingles
local host                       -- la fenêtre de la carte ; fiche et liste y sont créées au premier usage
local card, noteBox, cardTitle, tomtomButton, listButton, list
local shownPin                   -- l'épingle de la fiche ouverte

local function Pins()
	ns.db.pins = ns.db.pins or {}
	return ns.db.pins
end

local function K(view)
	return 1000 / ns.VIEWS[view].size.w
end

-- Zone et coordonnées (en %) d'une épingle ; nil hors des zones dessinées (en mer).
local function Where(p)
	local zone, zx, zy = ns.ZoneAt(p.view, p.x, p.y)
	if zone then return format("%s  %.1f, %.1f", zone, zx * 100, zy * 100) end
	return ns.VIEWS[p.view] and (p.view == "outland" and L.OUTLAND or L.AZEROTH)
end

local function Label(p)
	if p.note and p.note ~= "" then return p.note end
	return Where(p)
end

--------------------------------------------------------------------------------
-- Affichage sur le canevas

local function Resize()
	if not canvas or not canvas.pinButtons then return end
	local _, zoom = ns.view.Get()
	local s = PIN_SIZE / zoom
	for _, b in ipairs(canvas.pinButtons) do
		if b:IsShown() then
			b:SetWidth(s)
			b:SetHeight(s)
		end
	end
end

local OpenCard, CreateCard, CreateList

local function NewButton(c)
	local b = CreateFrame("Button", nil, c.layers.pins)
	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetAllPoints(b)
	b:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine(Label(self.pin))
		if self.pin.note and self.pin.note ~= "" then GameTooltip:AddLine(Where(self.pin), 1, 1, 1) end
		GameTooltip:AddLine(L.PIN_CLICK, 0.6, 0.6, 0.6)
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", function() GameTooltip:Hide() end)
	b:SetScript("OnClick", function(self) OpenCard(self.pin) end)
	return b
end

-- Place les épingles de la vue affichée. Appelé quand le canevas change ou qu'une épingle est
-- ajoutée, modifiée ou supprimée ; jamais à chaque image.
local function Render()
	if not canvas then return end
	canvas.pinButtons = canvas.pinButtons or {}
	local buttons, k, n = canvas.pinButtons, canvas.k, 0
	for _, p in ipairs(Pins()) do
		if p.view == canvas.name then
			n = n + 1
			local b = buttons[n] or NewButton(canvas)
			buttons[n] = b
			b.pin = p
			b.icon:SetTexture(ICON .. p.icon)
			b:ClearAllPoints()
			b:SetPoint("CENTER", canvas.frame, "TOPLEFT", p.x * k, -p.y * k)
			b:Show()
		end
	end
	for i = n + 1, #buttons do buttons[i]:Hide() end
	Resize()
	if listButton then listButton:SetText(format(L.PINS, #Pins())) end
end

tinsert(ns.listeners.canvas, function(c)
	canvas = c
	Render()
end)
tinsert(ns.listeners.zoom, function() Resize() end)

--------------------------------------------------------------------------------
-- Fiche d'une épingle

local function GoTo(p)
	ns.view.Show(p.view)
	local _, zoom = ns.view.Get()
	local k = K(p.view)
	ns.view.Center(p.x * k, p.y * k, math.max(zoom, 6))
end

local function SetTomTom(p)
	if not (TomTom and TomTom.AddZWaypoint) then
		ns.Print(L.TOMTOM_MISSING)
		return
	end
	local zone, zx, zy, c, file = ns.ZoneAt(p.view, p.x, p.y)
	local info = zone and ns.maps[c] and ns.maps[c].zones[file]
	if not (info and info.index) then
		ns.Print(L.TOMTOM_NO_ZONE)
		return
	end
	-- persistent non, minicarte et carte oui, rappels par défaut, silencieux, flèche oui.
	TomTom:AddZWaypoint(c, info.index, zx * 100, zy * 100, Label(p), false, true, true, nil, true, true)
	ns.Print(format(L.TOMTOM_SET, Label(p)))
end

local function Delete(p)
	local pins = Pins()
	for i = #pins, 1, -1 do
		if pins[i] == p then tremove(pins, i) end
	end
	if shownPin == p and card then card:Hide() end
	Render()
	if list and list:IsShown() then ns.ShowPinList() end
end

function CreateCard(frame)
	card = CreateFrame("Frame", "StrataPinCard", frame)
	card:SetWidth(250)
	card:SetHeight(128)
	card:SetPoint("TOPRIGHT", -18, -36)
	card:SetFrameLevel(frame:GetFrameLevel() + 60)
	card:EnableMouse(true)
	card:SetBackdrop({
		bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true, tileSize = 16, edgeSize = 14,
		insets = { left = 4, right = 4, top = 4, bottom = 4 },
	})
	card:Hide()
	tinsert(UISpecialFrames, "StrataPinCard")

	cardTitle = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	cardTitle:SetPoint("TOPLEFT", 12, -12)
	cardTitle:SetPoint("RIGHT", -28, 0)
	cardTitle:SetJustifyH("LEFT")
	local close = CreateFrame("Button", nil, card, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", 0, 0)
	close:SetWidth(26)
	close:SetHeight(26)

	-- Nommé : InputBoxTemplate nomme ses textures d'après le parent.
	noteBox = CreateFrame("EditBox", "StrataPinNote", card, "InputBoxTemplate")
	noteBox:SetWidth(218)
	noteBox:SetHeight(20)
	noteBox:SetPoint("TOPLEFT", 18, -32)
	noteBox:SetAutoFocus(false)
	noteBox:SetMaxLetters(80)
	noteBox:SetScript("OnTextChanged", function(self, user)
		if user and shownPin then
			shownPin.note = self:GetText()
			Render()
		end
	end)
	noteBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
	noteBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

	card.icons = {}
	for i = 1, 8 do
		local b = CreateFrame("Button", nil, card)
		b:SetWidth(22)
		b:SetHeight(22)
		b:SetPoint("TOPLEFT", 12 + (i - 1) * 28, -58)
		b:SetNormalTexture(ICON .. i)
		b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
		b:SetScript("OnClick", function()
			-- La dernière icône choisie sert aux épingles suivantes.
			ns.db.lastPinIcon = i
			if shownPin then
				shownPin.icon = i
				Render()
			end
		end)
		card.icons[i] = b
	end

	-- Flèche de Strata (Nav.lua), qui marche sans TomTom.
	local follow = CreateFrame("Button", nil, card, "UIPanelButtonTemplate")
	follow:SetWidth(70)
	follow:SetHeight(22)
	follow:SetPoint("BOTTOMLEFT", 10, 10)
	follow:SetText(L.PIN_FOLLOW)
	follow:SetScript("OnClick", function()
		if shownPin then ns.Follow(shownPin.view, shownPin.x, shownPin.y, Label(shownPin)) end
	end)
	tomtomButton = CreateFrame("Button", nil, card, "UIPanelButtonTemplate")
	tomtomButton:SetWidth(84)
	tomtomButton:SetHeight(22)
	tomtomButton:SetPoint("LEFT", follow, "RIGHT", 2, 0)
	tomtomButton:SetText("TomTom")
	tomtomButton:SetScript("OnClick", function() if shownPin then SetTomTom(shownPin) end end)
	local delete = CreateFrame("Button", nil, card, "UIPanelButtonTemplate")
	delete:SetWidth(76)
	delete:SetHeight(22)
	delete:SetPoint("BOTTOMRIGHT", -10, 10)
	delete:SetText(L.PIN_DELETE)
	delete:SetScript("OnClick", function() if shownPin then Delete(shownPin) end end)
end

function OpenCard(p)
	if not card then CreateCard(host) end
	shownPin = p
	cardTitle:SetText(Where(p))
	noteBox:SetText(p.note or "")
	if TomTom and TomTom.AddZWaypoint then tomtomButton:Enable() else tomtomButton:Disable() end
	card:Show()
end

--------------------------------------------------------------------------------
-- Ajout

function ns.AddPin(view, x, y)
	local pins = Pins()
	local p = { view = view, x = x, y = y, note = "", icon = ns.db.lastPinIcon or 1 }
	pins[#pins + 1] = p
	Render()
	OpenCard(p)
	noteBox:SetFocus()
	return p
end

--------------------------------------------------------------------------------
-- Liste

function ns.ShowPinList()
	if not list then CreateList(host) end
	local pins = Pins()
	-- Les plus récentes d'abord.
	for i = 1, LIST_ROWS do
		local row, p = list.rows[i], pins[#pins - i + 1]
		if p then
			row.pin = p
			row.icon:SetTexture(ICON .. p.icon)
			row.label:SetText(Label(p))
			row:Show()
		else
			row:Hide()
		end
	end
	local shown = math.min(#pins, LIST_ROWS)
	if #pins == 0 then
		list.more:SetText(L.PINS_EMPTY)
	elseif #pins > LIST_ROWS then
		list.more:SetText(format(L.PINS_MORE, #pins - LIST_ROWS))
	else
		list.more:SetText("")
	end
	list:SetHeight(shown * 18 + 30)
	list:Show()
end

function CreateList(frame)
	list = CreateFrame("Frame", "StrataPinList", frame)
	list:SetWidth(260)
	list:SetPoint("BOTTOMRIGHT", listButton, "TOPRIGHT", 0, 2)
	list:SetFrameLevel(frame:GetFrameLevel() + 50)
	list:EnableMouse(true)
	list:SetBackdrop({
		bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true, tileSize = 16, edgeSize = 12,
		insets = { left = 3, right = 3, top = 3, bottom = 3 },
	})
	list:SetBackdropColor(0, 0, 0, 0.9)
	list:Hide()
	tinsert(UISpecialFrames, "StrataPinList")
	list.rows = {}
	for i = 1, LIST_ROWS do
		local row = CreateFrame("Button", nil, list)
		row:SetHeight(18)
		row:SetPoint("TOPLEFT", 6, -6 - (i - 1) * 18)
		row:SetPoint("TOPRIGHT", -6, -6 - (i - 1) * 18)
		row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
		row.icon = row:CreateTexture(nil, "ARTWORK")
		row.icon:SetWidth(14)
		row.icon:SetHeight(14)
		row.icon:SetPoint("LEFT", 2, 0)
		row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		row.label:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
		row.label:SetPoint("RIGHT", -2, 0)
		row.label:SetJustifyH("LEFT")
		row:SetScript("OnClick", function(self)
			list:Hide()
			GoTo(self.pin)
			OpenCard(self.pin)
		end)
		list.rows[i] = row
	end
	list.more = list:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	list.more:SetPoint("BOTTOMLEFT", 10, 8)
end

-- Seul le bouton de la liste est créé avec la fenêtre : fiche et liste (une trentaine de cadres)
-- le sont au premier usage, pour ne pas alourdir l'ouverture de la carte.
function ns.CreatePinsUI(frame)
	host = frame
	listButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	listButton:SetWidth(100)
	listButton:SetHeight(22)
	listButton:SetPoint("BOTTOMRIGHT", -28, 10)
	listButton:SetText(format(L.PINS, #Pins()))
	listButton:SetScript("OnClick", function()
		if list and list:IsShown() then list:Hide() else ns.ShowPinList() end
	end)
	frame:HookScript("OnHide", function()
		if card then card:Hide() end
		if list then list:Hide() end
	end)
end
