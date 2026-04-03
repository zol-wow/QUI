--[[
    Blizzard UI Mover — modifier-drag repositioning for default Blizzard panels.
]]

local ADDON_NAME, ns = ...
local Helpers = ns.Helpers

local M = {
    functions = {},
    variables = {},
}
ns.QUI_BlizzardMover = M

---------------------------------------------------------------------------
-- Saved settings (profile.blizzardMover); refreshed on profile change
---------------------------------------------------------------------------

local db

local function syncDbFromProfile()
	local profile = Helpers.GetProfile()
	if not profile or not profile.blizzardMover then return end
	db = profile.blizzardMover
	local function default(key, value)
		if db[key] == nil then db[key] = value end
	end
	default("enabled", false)
	default("requireModifier", true)
	default("modifier", "SHIFT")
	default("scaleEnabled", false)
	default("scaleModifier", "CTRL")
	default("positionPersistence", "reset")
	if type(db.frames) ~= "table" then db.frames = {} end
end

function M.functions.InitDB()
	syncDbFromProfile()
end

---------------------------------------------------------------------------
-- Frame path "A.B.C" → object (WoW global + table chain)
---------------------------------------------------------------------------

local function objectFromDottedPath(path)
	if type(path) ~= "string" or path == "" then return nil end
	local head, tail = path:match("^([^.]+)%.?(.*)$")
	local obj = head and _G[head] or nil
	if not obj then return nil end
	for segment in string.gmatch(tail, "([^.]+)") do
		obj = obj[segment]
		if obj == nil then return nil end
	end
	return obj
end

---------------------------------------------------------------------------
-- Registry of panels (filled by blizzard_mover_frames.lua)
---------------------------------------------------------------------------

local R = {
	groups = {},
	groupIds = {},
	panels = {},
	panelList = {},
	pathToPanelId = {},
	addonToPanels = {},
}

M.variables.registry = R

local function isAddonLoaded(name)
	local fn = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
	return fn and fn(name)
end

local function requiredAddonsForPanel(panel)
	local out, seen = {}, {}
	local function add(n)
		if type(n) == "string" and not seen[n] then
			seen[n] = true
			out[#out + 1] = n
		end
	end
	if type(panel.addon) == "string" then
		add(panel.addon)
	elseif type(panel.addon) == "table" then
		for _, n in ipairs(panel.addon) do add(n) end
	end
	if type(panel.addons) == "table" then
		for _, n in ipairs(panel.addons) do add(n) end
	end
	return out
end

local function indexPanelByAddon(panel)
	local need = requiredAddonsForPanel(panel)
	if #need == 0 then
		R.waitingOnPanel = R.waitingOnPanel or {}
		table.insert(R.waitingOnPanel, panel)
		return
	end
	for _, name in ipairs(need) do
		R.addonToPanels[name] = R.addonToPanels[name] or {}
		table.insert(R.addonToPanels[name], panel)
	end
end

local function resolvePanel(x)
	if type(x) == "table" then return x end
	if type(x) == "string" then return R.panels[x] end
	return nil
end

local function storageRowForPanel(panel)
	panel = resolvePanel(panel)
	if not panel or not db then return nil end
	db.frames[panel.id] = db.frames[panel.id] or {}
	local row = db.frames[panel.id]
	if row.enabled == nil then
		row.enabled = panel.defaultEnabled ~= false
	end
	return row
end

local function moveModifierHeld()
	if not db or not db.requireModifier then return true end
	local which = db.modifier or "SHIFT"
	if which == "SHIFT" then return IsShiftKeyDown() end
	if which == "CTRL" then return IsControlKeyDown() end
	if which == "ALT" then return IsAltKeyDown() end
	return false
end

local SCALE_LO, SCALE_HI, SCALE_STEP = 0.5, 2.0, 0.05

local function clampScale(x)
	if type(x) ~= "number" then return 1 end
	if x < SCALE_LO then return SCALE_LO end
	if x > SCALE_HI then return SCALE_HI end
	return x
end

local function scaleModifierHeld()
	if not db then return false end
	local which = db.scaleModifier or "CTRL"
	if which == "SHIFT" then return IsShiftKeyDown() end
	if which == "CTRL" then return IsControlKeyDown() end
	if which == "ALT" then return IsAltKeyDown() end
	return false
end

local function storedScaleValue(panelRow)
	if not db or not db.scaleEnabled then return nil end
	if panelRow and type(panelRow.scale) == "number" then return clampScale(panelRow.scale) end
	return nil
end

local function panelIsSuppressed(panel)
	panel = resolvePanel(panel)
	if not panel then return false end
	if panel.id ~= "QueueStatusButton" then return false end

	local profile = Helpers and Helpers.GetProfile and Helpers.GetProfile()
	local minimap = profile and profile.minimap
	return minimap
		and minimap.enabled
		and minimap.dungeonEye
		and minimap.dungeonEye.enabled
end

local function panelIsActive(panel)
	if not db or not db.enabled then return false end
	if panelIsSuppressed(panel) then return false end
	local row = storageRowForPanel(panel)
	return row and row.enabled ~= false
end

function M.functions.RegisterGroup(id, label, opts)
	if not id or id == "" then return nil end
	local g = R.groups[id]
	if not g then
		g = {
			id = id,
			label = label or id,
			order = opts and opts.order,
			expanded = opts and opts.expanded,
		}
		R.groups[id] = g
		R.groupIds[#R.groupIds + 1] = id
	else
		if label then g.label = label end
		if opts then
			if opts.order ~= nil then g.order = opts.order end
			if opts.expanded ~= nil then g.expanded = opts.expanded end
		end
	end
	return g
end

local function optionKeyForId(id)
	return "moverFrame_" .. tostring(id):gsub("[^%w]", "_")
end

local function collectNameList(def)
	if type(def.names) == "table" then return def.names end
	if type(def.names) == "string" then return { def.names } end
	if type(def.name) == "string" then return { def.name } end
	if type(def.frame) == "string" then return { def.frame } end
	return { def.id }
end

local function buildHandlePaths(def, baseNames)
	local paths, seen = {}, {}
	local function add(p)
		if type(p) == "string" and p ~= "" and not seen[p] then
			seen[p] = true
			paths[#paths + 1] = p
		end
	end
	if type(def.handles) == "string" then
		add(def.handles)
	elseif type(def.handles) == "table" then
		for _, p in ipairs(def.handles) do add(p) end
	end
	local rel = def.handlesRelative or def.dragbars or def.subframes
	if type(rel) == "string" then rel = { rel } end
	if type(rel) == "table" then
		for _, piece in ipairs(rel) do
			if type(piece) == "string" then
				for _, base in ipairs(baseNames) do
					add(base .. "." .. piece)
				end
			end
		end
	end
	return #paths > 0 and paths or nil
end

local function buildScalePaths(def)
	local paths, seen = {}, {}
	local function add(p)
		if type(p) == "string" and p ~= "" and not seen[p] then
			seen[p] = true
			paths[#paths + 1] = p
		end
	end
	if type(def.scaleTargets) == "string" then
		add(def.scaleTargets)
	elseif type(def.scaleTargets) == "table" then
		for _, p in ipairs(def.scaleTargets) do add(p) end
	end
	if type(def.scaleTarget) == "string" then add(def.scaleTarget) end
	return #paths > 0 and paths or nil
end

function M.functions.RegisterFrame(def)
	if not def or not def.id or R.panels[def.id] then
		return def and R.panels[def.id]
	end

	local names = collectNameList(def)
	local panel = {
		id = def.id,
		label = def.label or def.id,
		group = def.group or "default",
		groupLabel = def.groupLabel,
		groupOrder = def.groupOrder,
		defaultEnabled = def.defaultEnabled,
		names = names,
		handles = buildHandlePaths(def, names),
		scalePaths = buildScalePaths(def),
		addon = def.addon,
		useRootHandle = def.useRootHandle,
		keepTwoPointSize = def.keepTwoPointSize,
		disableMove = def.disableMove or def.scaleOnly,
		ignoreFramePositionManager = def.ignoreFramePositionManager,
		userPlaced = def.userPlaced,
		skipOnHide = def.skipOnHide,
		settingKey = def.settingKey or optionKeyForId(def.id),
	}

	R.panels[panel.id] = panel
	R.panelList[#R.panelList + 1] = panel

	M.functions.RegisterGroup(panel.group, panel.groupLabel, { order = panel.groupOrder })

	for _, pathKey in ipairs(names) do
		R.pathToPanelId[pathKey] = panel.id
	end

	storageRowForPanel(panel)
	indexPanelByAddon(panel)
	M.functions.TryHookEntry(panel)

	return panel
end

function M.functions.GetGroups()
	local out = {}
	for _, id in ipairs(R.groupIds) do
		local g = R.groups[id]
		if g then out[#out + 1] = g end
	end
	table.sort(out, function(a, b)
		local oa, ob = a.order or 1000, b.order or 1000
		if oa ~= ob then return oa < ob end
		return (a.label or a.id) < (b.label or b.id)
	end)
	return out
end

function M.functions.GetEntriesForGroup(groupId)
	local list = {}
	for _, panel in ipairs(R.panelList) do
		if panel.group == groupId then list[#list + 1] = panel end
	end
	table.sort(list, function(a, b) return (a.label or a.id) < (b.label or b.id) end)
	return list
end

function M.functions.GetEntryForFrameName(name)
	local id = name and R.pathToPanelId[name]
	return id and R.panels[id] or nil
end

function M.functions.IsFrameEnabled(entry)
	return panelIsActive(resolvePanel(entry))
end

function M.functions.SetFrameEnabled(entry, on)
	local row = storageRowForPanel(entry)
	if row then row.enabled = on and true or false end
end

---------------------------------------------------------------------------
-- Transient runtime (not saved): combat queue, session positions, scale UI
---------------------------------------------------------------------------

M.variables.pendingApply = M.variables.pendingApply or {}
M.variables.combatQueue = M.variables.combatQueue or {}
M.variables.sessionPositions = M.variables.sessionPositions or {}
M.variables.scalePin = M.variables.scalePin or {}
M.variables.scaleUnderMouse = M.variables.scaleUnderMouse or {}
M.variables.moveHandleSet = M.variables.moveHandleSet or {}
M.variables.wheelProxy = M.variables.wheelProxy or nil

-- Weak keys: which helper objects already have scripts (avoids cluttering frame fields)
local leafScriptState = setmetatable({}, { __mode = "k" })

local function leafMark(target, key)
	if not target then return end
	local t = leafScriptState[target]
	if not t then
		t = {}
		leafScriptState[target] = t
	end
	t[key] = true
end

local function leafHas(target, key)
	local t = leafScriptState[target]
	return t and t[key]
end

---------------------------------------------------------------------------
-- Per-root-frame context (single named slot on Blizzard root widgets)
---------------------------------------------------------------------------

local CTX_KEY = "_QUI_BlizzardPanelMover"

local function ctx(root)
	local t = root[CTX_KEY]
	if not t then
		t = {}
		root[CTX_KEY] = t
	end
	return t
end

function M.functions.deferApply(frame, entry)
	if frame then M.variables.pendingApply[frame] = entry or true end
end

---------------------------------------------------------------------------
-- Saved layout: where to pin relative to UIParent
---------------------------------------------------------------------------

local function readSavedOffset(panel, row)
	local mode = db.positionPersistence or "reset"
	if mode == "lockout" then
		local sp = M.variables.sessionPositions
		return sp and sp[panel.id] or nil
	end
	if mode == "reset" then return row end
	return nil
end

local function writeSavedOffset(panel, row, point, x, y)
	local mode = db.positionPersistence or "reset"
	if mode == "close" then return end
	if mode == "lockout" then
		local sp = M.variables.sessionPositions
		sp[panel.id] = sp[panel.id] or {}
		local slot = sp[panel.id]
		slot.point, slot.x, slot.y = point, x, y
		return
	end
	if row then
		row.point, row.x, row.y = point, x, y
	end
end

local function clearSavedOffset(panel, row)
	local mode = db.positionPersistence or "reset"
	if mode == "lockout" then
		local sp = M.variables.sessionPositions
		if sp then sp[panel.id] = nil end
	elseif mode == "reset" and row then
		row.point, row.x, row.y = nil, nil, nil
	end
end

---------------------------------------------------------------------------
-- Remember Blizzard layout before we override; restore on demand
---------------------------------------------------------------------------

local function rememberAnchors(f)
	local c = ctx(f)
	if c.blizzardAnchors then return end
	local n = f.GetNumPoints and f:GetNumPoints() or 0
	if n < 1 then return end
	local copy = {}
	for i = 1, n do
		local pt, rel, relPt, ox, oy = f:GetPoint(i)
		if pt then
			copy[#copy + 1] = {
				point = pt,
				relative = rel,
				relativeName = rel and rel.GetName and rel:GetName() or nil,
				relativePoint = relPt,
				x = ox,
				y = oy,
			}
		end
	end
	if #copy > 0 then c.blizzardAnchors = copy end
end

local function restoreAnchors(f)
	local c = ctx(f)
	local copy = c.blizzardAnchors
	if not copy or #copy == 0 then return false end
	f:ClearAllPoints()
	for _, a in ipairs(copy) do
		local rel = a.relative
		if type(rel) == "string" then rel = _G[rel] end
		if not rel and a.relativeName then rel = _G[a.relativeName] end
		rel = rel or UIParent
		f:SetPoint(a.point, rel, a.relativePoint or a.point, a.x or 0, a.y or 0)
	end
	return true
end

local function rememberInteraction(f)
	local c = ctx(f)
	if c.wasInteractive then return end
	c.wasInteractive = {
		movable = f.IsMovable and f:IsMovable(),
		clamped = f.IsClampedToScreen and f:IsClampedToScreen(),
		mouse = f.IsMouseEnabled and f:IsMouseEnabled(),
		wheel = f.IsMouseWheelEnabled and f:IsMouseWheelEnabled(),
		userPlaced = f.IsUserPlaced and f:IsUserPlaced(),
		fpm = f.ignoreFramePositionManager,
	}
end

local function applyInteractionBaseline(f, panel, active, usedOverlay)
	local c = ctx(f)
	local base = c.wasInteractive
	if not base then return end
	if InCombatLockdown() and f.IsProtected and f:IsProtected() then return end
	if active then
		if f.SetMovable then f:SetMovable(true) end
		if f.SetClampedToScreen then f:SetClampedToScreen(true) end
		if panel.userPlaced ~= nil and f.SetUserPlaced then f:SetUserPlaced(panel.userPlaced) end
		if panel.ignoreFramePositionManager ~= nil then f.ignoreFramePositionManager = panel.ignoreFramePositionManager end
		if not usedOverlay and f.EnableMouse then f:EnableMouse(true) end
		return
	end
	if base.movable ~= nil and f.SetMovable then f:SetMovable(base.movable) end
	if base.clamped ~= nil and f.SetClampedToScreen then f:SetClampedToScreen(base.clamped) end
	if not usedOverlay and base.mouse ~= nil and f.EnableMouse then f:EnableMouse(base.mouse) end
	if base.wheel ~= nil and f.EnableMouseWheel then f:EnableMouseWheel(base.wheel) end
	if panel.userPlaced ~= nil and base.userPlaced ~= nil and f.SetUserPlaced then f:SetUserPlaced(base.userPlaced) end
	if panel.ignoreFramePositionManager ~= nil then f.ignoreFramePositionManager = base.fpm end
end

local function applyLeafInteraction(f, active)
	local c = ctx(f)
	local base = c.wasInteractive
	if not base then return end
	if InCombatLockdown() and f.IsProtected and f:IsProtected() then return end
	if active then
		if f.EnableMouse then f:EnableMouse(true) end
		return
	end
	if base.mouse ~= nil and f.EnableMouse then f:EnableMouse(base.mouse) end
	if base.wheel ~= nil and f.EnableMouseWheel then f:EnableMouseWheel(base.wheel) end
end

---------------------------------------------------------------------------
-- Apply stored point + scale to a root frame
---------------------------------------------------------------------------

local function applyDualCornerSize(f, x, y, pt, relPt)
	pt, relPt = pt or "TOPLEFT", relPt or pt
	local w, h = f:GetSize()
	if not w or not h or w <= 0 or h <= 0 then
		w = f:GetWidth() or 700
		h = f:GetHeight() or 700
	end
	f:ClearAllPoints()
	f:SetPoint(pt, UIParent, relPt, x or 0, y or 0)
	f:SetPoint("BOTTOMRIGHT", UIParent, relPt, (x or 0) + w, (y or 0) - h)
end

function M.functions.applyFrameSettings(f, entry)
	local panel = resolvePanel(entry) or M.functions.GetEntryForFrameName(f:GetName() or "")
	if not panel or not panelIsActive(panel) then return end
	local row = storageRowForPanel(panel)
	local saved = readSavedOffset(panel, row)
	local hasPos = saved and saved.point and saved.x ~= nil and saved.y ~= nil
	local sc = storedScaleValue(row)
	if not hasPos and not sc then return end
	if InCombatLockdown() and f:IsProtected() then
		M.functions.deferApply(f, panel)
		return
	end
	local c = ctx(f)
	c.applyingLayout = true
	if hasPos then
		if panel.keepTwoPointSize then
			applyDualCornerSize(f, saved.x, saved.y, saved.point, saved.point)
		else
			f:ClearAllPoints()
			f:SetPoint(saved.point, UIParent, saved.point, saved.x, saved.y)
		end
	end
	if sc and f.SetScale then f:SetScale(sc) end
	c.applyingLayout = false
end

function M.functions.StoreFramePosition(f, entry)
	local panel = resolvePanel(entry) or M.functions.GetEntryForFrameName(f:GetName() or "")
	if not panel then return end
	local row = storageRowForPanel(panel)
	if not row then return end
	local pt, _, _, ox, oy = f:GetPoint()
	if not pt then return end
	writeSavedOffset(panel, row, pt, ox, oy)
end

---------------------------------------------------------------------------
-- Mouse-wheel scaling: full-screen catcher only when modifier + valid target
---------------------------------------------------------------------------

local function wheelConsumeTarget()
	if not GetMouseFoci then return nil end
	local under = M.variables.scaleUnderMouse
	if not under or not next(under) then return nil end
	local pins = M.variables.scalePin
	local handles = M.variables.moveHandleSet
	for _, focus in ipairs(GetMouseFoci()) do
		local root = pins and pins[focus]
		local entryOnRoot = root and root[CTX_KEY] and root[CTX_KEY].panel
		if entryOnRoot and panelIsActive(entryOnRoot) then return root end
		if handles and handles[focus] then return handles[focus] end
		if not root and not (handles and handles[focus]) then
			if focus.IsForbidden and focus:IsForbidden() then return nil end
			if IsFrameHandle and IsFrameHandle(focus) then return nil end
			local w = focus.IsMouseWheelEnabled and focus:IsMouseWheelEnabled()
			local c = focus.IsMouseClickEnabled and focus:IsMouseClickEnabled()
			if issecretvalue and (issecretvalue(w) or issecretvalue(c)) then return nil end
			if w or c then return nil end
		end
	end
	return nil
end

function M.functions.CheckScaleWheelCapture()
	local proxy = M.variables.wheelProxy
	if not proxy then return end
	proxy:EnableMouseWheel(false)
	if not db or not db.enabled or not db.scaleEnabled then return end
	if not scaleModifierHeld() then return end
	if wheelConsumeTarget() then proxy:EnableMouseWheel(true) end
end

function M.functions.UpdateScaleWheelCaptureState()
	local proxy = M.variables.wheelProxy
	if not proxy then return end
	if db and db.enabled and db.scaleEnabled and scaleModifierHeld() then
		if proxy:GetScript("OnUpdate") == nil then
			proxy:SetScript("OnUpdate", M.functions.CheckScaleWheelCapture)
		end
		M.functions.CheckScaleWheelCapture()
	else
		proxy:EnableMouseWheel(false)
		if proxy:GetScript("OnUpdate") ~= nil then proxy:SetScript("OnUpdate", nil) end
	end
end

function M.functions.HandleScaleWheel(delta)
	if not db or not db.enabled or not db.scaleEnabled then return end
	if not scaleModifierHeld() then return end
	local target = wheelConsumeTarget()
	local c = target and ctx(target)
	if not c or not c.onWheelScale then return end
	c.onWheelScale(delta)
end

function M.functions.EnsureScaleCaptureFrame()
	if M.variables.wheelProxy then return end
	local proxy = CreateFrame("Frame")
	proxy:SetAllPoints(UIParent)
	proxy:SetFrameStrata("TOOLTIP")
	proxy:SetFrameLevel(9999)
	proxy:EnableMouseWheel(false)
	proxy:RegisterEvent("MODIFIER_STATE_CHANGED")
	proxy:SetScript("OnEvent", function() M.functions.UpdateScaleWheelCaptureState() end)
	proxy:SetScript("OnMouseWheel", function(_, d) M.functions.HandleScaleWheel(d) end)
	M.variables.wheelProxy = proxy
	M.functions.UpdateScaleWheelCaptureState()
end

---------------------------------------------------------------------------
-- Blizzard-specific layout quirks (public API names unchanged for options)
---------------------------------------------------------------------------

local function collectionsPanelEnabled()
	if not db or not db.enabled then return false end
	local p = R.panels.CollectionsJournal
	return p and panelIsActive(p)
end

local function tweakWardrobeSecondaryLabel()
	if not collectionsPanelEnabled() then return false end
	local wardrobe = WardrobeFrame
	local xmog = wardrobe and wardrobe.WardrobeTransmogFrame or WardrobeTransmogFrame
	local box = xmog and xmog.ToggleSecondaryAppearanceCheckbox
	local lbl = box and box.Label
	if not (box and lbl and lbl.ClearAllPoints) then return false end
	lbl:ClearAllPoints()
	lbl:SetPoint("LEFT", box, "RIGHT", 2, 1)
	lbl:SetPoint("RIGHT", box, "RIGHT", 160, 1)
	return true
end

local function playerChoiceMoverOn()
	if not db or not db.enabled then return false end
	local p = R.panels.PlayerChoiceFrame
	return p and panelIsActive(p)
end

local function installPlayerChoiceLayoutGuard(f)
	if not f or f._QUI_BM_playerChoiceGuard then return true end
	if not playerChoiceMoverOn() then return false end
	f._QUI_BM_playerChoiceGuard = true

	f:HookScript("OnHide", function(self)
		if not playerChoiceMoverOn() then return end
		if InCombatLockdown() and self:IsProtected() then return end
		local cx = ctx(self)
		cx.applyingLayout = true
		self:ClearAllPoints()
		self:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
		cx.applyingLayout = nil
		self._QUI_BM_reapplyWhenShown = true
	end)

	f:HookScript("OnShow", function(self)
		if not playerChoiceMoverOn() then return end
		if not self._QUI_BM_reapplyWhenShown then return end
		self._QUI_BM_reapplyWhenShown = nil
		C_Timer.After(0, function()
			if self:IsShown() then
				local p = R.panels.PlayerChoiceFrame
				if p then M.functions.applyFrameSettings(self, p) end
			end
		end)
	end)
	return true
end

local function heroDialogMoverOn()
	if not db or not db.enabled then return false end
	local p = R.panels.HeroTalentsSelectionDialog
	return p and panelIsActive(p)
end

local function installHeroTalentAnchorWorkaround()
	if M.variables.heroTalentWorkaround then return true end
	if not heroDialogMoverOn() then return false end
	if not (TalentFrameUtil and TalentFrameUtil.GetNormalizedSubTreeNodePosition) then return false end
	if not (HeroTalentsSelectionDialog and PlayerSpellsFrame) then return false end

	M.variables.heroTalentWorkaround = true
	local reenter = false

	hooksecurefunc(TalentFrameUtil, "GetNormalizedSubTreeNodePosition", function(talentFrame)
		if reenter then return end
		if not heroDialogMoverOn() then return end
		local trace = debugstack(3)
		if not trace then return end
		local conflict = (trace:find("UpdateContainerVisibility", 1, true)
			or trace:find("UpdateHeroTalentButtonPosition", 1, true)
			or trace:find("PlaceHeroTalentButton", 1, true))
			and not trace:find("InstantiateTalentButton", 1, true)
		if not conflict then return end
		reenter = true
		if talentFrame and talentFrame.EnumerateAllTalentButtons then
			for btn in talentFrame:EnumerateAllTalentButtons() do
				local info = btn and btn.GetNodeInfo and btn:GetNodeInfo()
				if info and info.subTreeID and btn.ClearAllPoints then btn:ClearAllPoints() end
			end
		end
		local function clearGuard()
			reenter = false
		end
		if RunNextFrame then
			RunNextFrame(clearGuard)
		elseif C_Timer and C_Timer.After then
			C_Timer.After(0, clearGuard)
		else
			reenter = false
		end
	end)
	return true
end

---------------------------------------------------------------------------
-- Install hooks on one concrete root frame for a panel definition
---------------------------------------------------------------------------

function M.functions.createHooks(root, entry)
	local panel = resolvePanel(entry) or M.functions.GetEntryForFrameName(root:GetName() or "")
	if not root or (root.IsForbidden and root:IsForbidden()) then return end
	if not panel then return end

	local c = ctx(root)
	if c.hooksInstalled then return end

	rememberAnchors(root)
	rememberInteraction(root)

	if InCombatLockdown() then
		M.variables.combatQueue[root] = panel
		return
	end

	c.panel = panel
	c.hooksInstalled = true
	M.variables.combatQueue[root] = nil

	local function beginDrag(_, btn)
		if btn and btn ~= "LeftButton" then return end
		if not panelIsActive(panel) then return end
		if not moveModifierHeld() then return end
		if InCombatLockdown() and root:IsProtected() then return end
		c.dragging = true
		root:StartMoving()
	end

	local function endDrag(_, btn)
		if btn and btn ~= "LeftButton" then return end
		if not panelIsActive(panel) then return end
		if InCombatLockdown() and root:IsProtected() then return end
		root:StopMovingOrSizing()
		c.dragging = false
		M.functions.StoreFramePosition(root, panel)
		if panel.keepTwoPointSize then M.functions.applyFrameSettings(root, panel) end
	end

	local function pushScale(next)
		local row = storageRowForPanel(panel)
		if row then row.scale = next end
		if InCombatLockdown() and root:IsProtected() then
			M.functions.deferApply(root, panel)
			return
		end
		if root.SetScale then root:SetScale(next) end
	end

	local function nudgeScale(delta)
		if not panelIsActive(panel) then return end
		if not db.scaleEnabled then return end
		if not scaleModifierHeld() then return end
		local row = storageRowForPanel(panel)
		local cur = row and row.scale
		if type(cur) ~= "number" and root.GetScale then cur = root:GetScale() end
		cur = clampScale(cur or 1)
		pushScale(clampScale(cur + delta * SCALE_STEP))
	end

	local function resetScaleAndLayout(_, btn)
		if btn ~= "RightButton" then return end
		if not panelIsActive(panel) then return end
		if not scaleModifierHeld() then return end
		pushScale(1)
		local row = storageRowForPanel(panel)
		clearSavedOffset(panel, row)
		if c.blizzardAnchors then
			c.applyingLayout = true
			restoreAnchors(root)
			c.applyingLayout = false
		end
	end

	c.onWheelScale = function(d) nudgeScale(d) end

	local function trackScaleHover(widget)
		if not widget or leafHas(widget, "hover") then return end
		leafMark(widget, "hover")
		widget:HookScript("OnEnter", function()
			if not panelIsActive(panel) then return end
			M.variables.scaleUnderMouse[widget] = true
			M.functions.CheckScaleWheelCapture()
		end)
		widget:HookScript("OnLeave", function()
			M.variables.scaleUnderMouse[widget] = nil
			M.functions.CheckScaleWheelCapture()
		end)
		if MouseIsOver and MouseIsOver(widget) then
			local function bump()
				if panelIsActive(panel) and MouseIsOver(widget) then
					M.variables.scaleUnderMouse[widget] = true
					M.functions.CheckScaleWheelCapture()
				end
			end
			if RunNextFrame then RunNextFrame(bump)
			elseif C_Timer and C_Timer.After then C_Timer.After(0, bump)
			else bump() end
		end
	end

	local function pinScaleTree(widget)
		if not widget or leafHas(widget, "pin") then return end
		if widget.IsForbidden and widget:IsForbidden() then return end
		leafMark(widget, "pin")
		M.variables.scalePin[widget] = root
		trackScaleHover(widget)
	end

	local function hookResetClick(widget)
		if not widget or leafHas(widget, "resetClick") then return end
		leafMark(widget, "resetClick")
		widget:HookScript("OnMouseUp", resetScaleAndLayout)
	end

	local function registerDragHandle(h)
		if not h then return end
		M.variables.moveHandleSet[h] = root
		trackScaleHover(h)
		hookResetClick(h)
	end

	pinScaleTree(root)
	hookResetClick(root)

	if panel.scalePaths then
		local function wireScalePath(p)
			local w = objectFromDottedPath(p)
			if w then
				pinScaleTree(w)
				hookResetClick(w)
			end
		end
		for _, p in ipairs(panel.scalePaths) do wireScalePath(p) end
		root:HookScript("OnShow", function()
			for _, p in ipairs(panel.scalePaths) do wireScalePath(p) end
		end)
	end

	local function makeDragStrip(anchor)
		if not anchor then return nil end
		local strip
		local ok = pcall(function()
			strip = CreateFrame("Frame", nil, anchor, "PanelDragBarTemplate")
		end)
		if not ok or not strip then strip = CreateFrame("Frame", nil, anchor) end
		pcall(function()
			strip.onDragStartCallback = function() return false end
			strip.onDragStopCallback = function() return false end
		end)
		strip.target = root
		strip:SetAllPoints(anchor)
		strip:SetFrameLevel(anchor:GetFrameLevel() + 1)
		if not InCombatLockdown() then
			if strip.SetPropagateMouseMotion then strip:SetPropagateMouseMotion(true) end
			if strip.SetPropagateMouseClicks then strip:SetPropagateMouseClicks(true) end
		end
		if strip.EnableMouse then strip:EnableMouse(true) end
		strip:HookScript("OnDragStart", beginDrag)
		strip:HookScript("OnDragStop", endDrag)
		registerDragHandle(strip)
		return strip
	end

	local partners = {}
	c.dragPartners = partners

	local function wireDirectDrag(surface)
		if not surface or leafHas(surface, "directDrag") then return end
		if surface.IsForbidden and surface:IsForbidden() then return end
		leafMark(surface, "directDrag")
		rememberInteraction(surface)
		if surface ~= root then partners[surface] = true end
		if surface.EnableMouse then surface:EnableMouse(true) end
		surface:HookScript("OnMouseDown", beginDrag)
		surface:HookScript("OnMouseUp", endDrag)
		pinScaleTree(surface)
		hookResetClick(surface)
	end

	local useStripOverlay = false
	if not panel.disableMove then
		useStripOverlay = panel.useRootHandle
		if useStripOverlay == nil then useStripOverlay = root:IsProtected() end
	end

	if not panel.disableMove then
		if useStripOverlay then
			if panel.useRootHandle ~= false then c.stripOnRoot = makeDragStrip(root) end
			c.stripChildren = c.stripChildren or {}
			if panel.handles then
				local function stripForPath(p)
					local a = objectFromDottedPath(p)
					if not a or c.stripChildren[a] then return end
					if a.IsForbidden and a:IsForbidden() then return end
					c.stripChildren[a] = makeDragStrip(a)
				end
				for _, p in ipairs(panel.handles) do stripForPath(p) end
				root:HookScript("OnShow", function()
					for _, p in ipairs(panel.handles) do stripForPath(p) end
				end)
			end
		else
			wireDirectDrag(root)
			if panel.handles then
				local function wireHandlePath(p)
					local a = objectFromDottedPath(p)
					if a then wireDirectDrag(a) end
				end
				for _, p in ipairs(panel.handles) do wireHandlePath(p) end
				root:HookScript("OnShow", function()
					for _, p in ipairs(panel.handles) do wireHandlePath(p) end
				end)
			end
		end
	end

	-- QUI character pane: stats panel / scroll areas sit above the default root drag strip
	-- (strip uses rootLevel+1; QUI uses ~+10). Add a thin top band above those children.
	if not panel.disableMove and panel.id == "CharacterFrame" then
		local topHost = root._QUI_BlizzardMoverCharTopDrag
		if not topHost then
			topHost = CreateFrame("Frame", nil, root)
			root._QUI_BlizzardMoverCharTopDrag = topHost
		end
		local topH = 36
		local rightInset = 140 -- sidebar tabs + close; leave clickable
		local function layoutCharTopDragHost(self)
			local h = self._QUI_BlizzardMoverCharTopDrag
			if not h then return end
			h:ClearAllPoints()
			h:SetPoint("TOPLEFT", self, "TOPLEFT", 0, 0)
			h:SetPoint("TOPRIGHT", self, "TOPRIGHT", -rightInset, 0)
			h:SetHeight(topH)
			local rll = self:GetFrameLevel() or 0
			h:SetFrameLevel(math.max(rll + 55, 25))
		end
		layoutCharTopDragHost(root)
		topHost:EnableMouse(true)
		topHost:Show()
		if useStripOverlay then
			if not c.stripCharacterTop then
				c.stripCharacterTop = makeDragStrip(topHost)
			end
		else
			wireDirectDrag(topHost)
		end
		if not leafHas(root, "charTopDragOnShow") then
			leafMark(root, "charTopDragOnShow")
			root:HookScript("OnShow", function(self)
				layoutCharTopDragHost(self)
			end)
		end
	end

	local function reassertLayout(self)
		if not panelIsActive(panel) then return end
		if c.dragging or c.applyingLayout then return end
		local row = storageRowForPanel(panel)
		local saved = readSavedOffset(panel, row)
		local hasPos = saved and saved.point and saved.x ~= nil and saved.y ~= nil
		local sc = storedScaleValue(row)
		if not hasPos and not sc then return end
		if InCombatLockdown() and self:IsProtected() then
			M.functions.deferApply(self, panel)
			return
		end
		c.applyingLayout = true
		if hasPos then
			if panel.keepTwoPointSize then
				applyDualCornerSize(self, saved.x, saved.y, saved.point, saved.point)
			else
				self:ClearAllPoints()
				self:SetPoint(saved.point, UIParent, saved.point, saved.x, saved.y)
			end
		end
		if sc and self.SetScale then self:SetScale(sc) end
		c.applyingLayout = false
	end

	hooksecurefunc(root, "SetPoint", reassertLayout)

	root:HookScript("OnShow", function(self)
		if not ctx(self).blizzardAnchors then rememberAnchors(self) end
		M.functions.applyFrameSettings(self, panel)
	end)

	if not panel.skipOnHide then
		root:HookScript("OnHide", function(self)
			if (db.positionPersistence or "reset") ~= "close" then return end
			if not panelIsActive(panel) then return end
			if c.dragging or c.applyingLayout then return end
			if InCombatLockdown() and self:IsProtected() then return end
			if not c.blizzardAnchors then return end
			c.applyingLayout = true
			restoreAnchors(self)
			c.applyingLayout = false
		end)
	end

	local function setStripVisible(strip, on)
		if not strip then return end
		if strip.EnableMouse then strip:EnableMouse(on) end
		if strip.SetShown then strip:SetShown(on) end
	end

	function c.refresh()
		local on = panelIsActive(panel)
		if not panel.disableMove then
			applyInteractionBaseline(root, panel, on, useStripOverlay)
			for surf in pairs(partners) do
				applyLeafInteraction(surf, on)
			end
			setStripVisible(c.stripOnRoot, on)
			setStripVisible(c.stripCharacterTop, on)
			if c.stripChildren then
				for _, strip in pairs(c.stripChildren) do setStripVisible(strip, on) end
			end
		end
		if not on then
			M.variables.scaleUnderMouse[root] = nil
			for surf in pairs(partners) do M.variables.scaleUnderMouse[surf] = nil end
			if c.stripOnRoot then M.variables.scaleUnderMouse[c.stripOnRoot] = nil end
			if c.stripCharacterTop then M.variables.scaleUnderMouse[c.stripCharacterTop] = nil end
			if c.stripChildren then
				for _, strip in pairs(c.stripChildren) do M.variables.scaleUnderMouse[strip] = nil end
			end
		elseif MouseIsOver then
			local function hover(w)
				if w and MouseIsOver(w) then M.variables.scaleUnderMouse[w] = true end
			end
			hover(root)
			for surf in pairs(partners) do hover(surf) end
			hover(c.stripOnRoot)
			hover(c.stripCharacterTop)
			if c.stripChildren then
				for _, strip in pairs(c.stripChildren) do hover(strip) end
			end
		end
		M.functions.CheckScaleWheelCapture()
	end

	c.refresh()
end

---------------------------------------------------------------------------
-- Addon / combat drivers
---------------------------------------------------------------------------

local function addonsSatisfied(panel)
	local need = requiredAddonsForPanel(panel)
	if #need == 0 then return true end
	for _, n in ipairs(need) do
		if isAddonLoaded(n) then return true end
	end
	return false
end

function M.functions.TryHookEntry(entry)
	local panel = resolvePanel(entry)
	if not panel or not addonsSatisfied(panel) or not panelIsActive(panel) then return end
	for _, path in ipairs(panel.names or {}) do
		local f = objectFromDottedPath(path)
		if f then
			M.functions.createHooks(f, panel)
			M.functions.applyFrameSettings(f, panel)
		end
	end
end

function M.functions.TryHookAll()
	for _, panel in ipairs(R.panelList) do
		M.functions.TryHookEntry(panel)
	end
end

function M.functions.UpdateHandleState(entry)
	local panel = resolvePanel(entry)
	if not panel then return end
	for _, path in ipairs(panel.names or {}) do
		local f = objectFromDottedPath(path)
		local c = f and ctx(f)
		if c and c.refresh then c.refresh() end
	end
end

function M.functions.RefreshEntry(entry)
	M.functions.TryHookEntry(entry)
	M.functions.UpdateHandleState(entry)
	local panel = resolvePanel(entry)
	if not panel then return end
	if panel.id == "CollectionsJournal" then tweakWardrobeSecondaryLabel() end
	if panel.id == "PlayerChoiceFrame" and PlayerChoiceFrame then installPlayerChoiceLayoutGuard(PlayerChoiceFrame) end
	if panel.id == "HeroTalentsSelectionDialog" then installHeroTalentAnchorWorkaround() end
end

function M.functions.ApplyAll()
	for _, panel in ipairs(R.panelList) do
		M.functions.RefreshEntry(panel)
	end
end

function M.functions.ClearSessionPositions()
	local sp = M.variables.sessionPositions
	if sp then wipe(sp) end
end

function M.functions.InitRegistry()
	if M.variables.registryInitialized then return end
	syncDbFromProfile()
	if not db then return end
	local pack = M._FrameRegistryData
	if not pack then return end
	M.functions.EnsureScaleCaptureFrame()
	for gid, meta in pairs(pack.groups or {}) do
		local ord = pack.groupOrder and pack.groupOrder[gid] or meta.order
		M.functions.RegisterGroup(gid, meta.label, { order = ord, expanded = meta.expanded })
	end
	for _, def in ipairs(pack.frames or {}) do
		if pack.groupOrder and def.group and def.groupOrder == nil then
			def.groupOrder = pack.groupOrder[def.group]
		end
		M.functions.RegisterFrame(def)
	end
	M.variables.registryInitialized = true
end

local function onAddonLoaded(name)
	if name == ADDON_NAME then
		for _, panel in ipairs(R.waitingOnPanel or {}) do
			M.functions.TryHookEntry(panel)
		end
	end
	if name == "Blizzard_Collections" then tweakWardrobeSecondaryLabel() end
	if name == "Blizzard_PlayerChoice" and PlayerChoiceFrame then installPlayerChoiceLayoutGuard(PlayerChoiceFrame) end
	if name == "Blizzard_PlayerSpells" then installHeroTalentAnchorWorkaround() end
	local list = R.addonToPanels and R.addonToPanels[name]
	if list then
		for _, panel in ipairs(list) do M.functions.TryHookEntry(panel) end
	end
end

local function onRegenEnabled()
	for f, panel in pairs(M.variables.combatQueue) do
		M.variables.combatQueue[f] = nil
		if f then M.functions.createHooks(f, panel) end
	end
	for f, panel in pairs(M.variables.pendingApply) do
		M.variables.pendingApply[f] = nil
		if f then M.functions.applyFrameSettings(f, panel) end
	end
end

local eventFrame

local function attachEventFrame()
	if eventFrame then return end
	eventFrame = CreateFrame("Frame")
	eventFrame:RegisterEvent("ADDON_LOADED")
	eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
	eventFrame:SetScript("OnEvent", function(_, ev, a1)
		syncDbFromProfile()
		if ev == "ADDON_LOADED" then onAddonLoaded(a1)
		elseif ev == "PLAYER_REGEN_ENABLED" then onRegenEnabled() end
	end)
end

local function boot(core)
	syncDbFromProfile()
	M.functions.InitRegistry()
	M.functions.TryHookAll()
	attachEventFrame()
	if core and core.db and core.db.RegisterCallback then
		local sink = {}
		function sink:OnProfileChanged()
			syncDbFromProfile()
			M.functions.ApplyAll()
		end
		core.db.RegisterCallback(sink, "OnProfileChanged", "OnProfileChanged")
		core.db.RegisterCallback(sink, "OnProfileCopied", "OnProfileChanged")
		core.db.RegisterCallback(sink, "OnProfileReset", "OnProfileChanged")
	end
end

if ns.Addon and ns.Addon.RegisterPostInitialize then
	ns.Addon:RegisterPostInitialize(function(core)
		boot(core)
	end)
end
