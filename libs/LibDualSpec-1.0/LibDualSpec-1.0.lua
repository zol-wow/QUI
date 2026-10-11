--[[
LibDualSpec-1.0 - Adds dual spec support to individual AceDB-3.0 databases
Copyright (C) 2009-2024 Adirelle

All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

    * Redistributions of source code must retain the above copyright notice,
      this list of conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above copyright notice,
      this list of conditions and the following disclaimer in the documentation
      and/or other materials provided with the distribution.
    * Redistribution of a stand alone version is strictly prohibited without
      prior written authorization from the LibDualSpec project manager.
    * Neither the name of the LibDualSpec authors nor the names of its contributors
      may be used to endorse or promote products derived from this software without
      specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
"AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR
CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
--]]

local MAJOR, MINOR = "LibDualSpec-1.0", 36
assert(LibStub, MAJOR.." requires LibStub")
local lib, minor = LibStub:NewLibrary(MAJOR, MINOR)
if not lib then return end

-- ----------------------------------------------------------------------------
-- Library data
-- ----------------------------------------------------------------------------

lib.eventFrame = lib.eventFrame or CreateFrame("Frame")

lib.registry = lib.registry or {}
lib.options = lib.options or {}
lib.mixin = lib.mixin or {}
lib.upgrades = lib.upgrades or {}
lib.currentSpec = tonumber(lib.currentSpec) or 0

if minor and minor < 15 then
	lib.talentsLoaded, lib.talentGroup = nil, nil
	lib.specLoaded, lib.specGroup = nil, nil
	lib.eventFrame:UnregisterAllEvents()
	wipe(lib.options)
end

-- ----------------------------------------------------------------------------
-- Locals
-- ----------------------------------------------------------------------------

local registry = lib.registry
local options = lib.options
local mixin = lib.mixin
local upgrades = lib.upgrades

local AceDB3 = LibStub("AceDB-3.0", true)
local AceDBOptions3 = LibStub("AceDBOptions-3.0", true)
local AceConfigRegistry3 = LibStub("AceConfigRegistry-3.0", true)

local isSpecBased = ClassicExpansionAtLeast(LE_EXPANSION_MISTS_OF_PANDARIA)
do
	local version = select(4, GetBuildInfo())
	if version > 16000 and version < 20000 then
		isSpecBased = false
	end
end

local numSpecs
local specNames = {}
if isSpecBased then
	local _, _, classId = UnitClass("player")
	numSpecs = C_SpecializationInfo.GetNumSpecializationsForClassID(classId)
	for i = 1, numSpecs do
		local _, name = GetSpecializationInfoForClassID(classId, i)
		specNames[i] = name
	end
else -- Primary/secondary system
	numSpecs = 2
	specNames[1] = TALENT_SPEC_PRIMARY
	specNames[2] = TALENT_SPEC_SECONDARY
end

-- ----------------------------------------------------------------------------
-- Localization
-- ----------------------------------------------------------------------------

local L_ENABLED = "Enable spec profiles"
local L_ENABLED_DESC = "When enabled, your profile will be set to the specified profile when you change specialization."
local L_CURRENT = "%s - Active"
local L_DUALSPEC_NOT_UNLOCKED = "Dual Specialization hasn't been unlocked yet."

do
	local locale = GetLocale()
	if locale == "deDE" then
		L_ENABLED = "Spezialisierungsprofile aktivieren"
		L_ENABLED_DESC = "Falls diese Option aktiviert ist, wird dein Profil auf das angegebene Profil gesetzt, wenn du die Spezialisierung wechselst."
		L_CURRENT = "%s - Aktiv"
		L_DUALSPEC_NOT_UNLOCKED = "Duale Spezialisierung wurde noch nicht freigeschaltet."
	elseif locale == "esES" then
		L_ENABLED = "Activar perfiles de especialización"
		L_ENABLED_DESC = "Cuando está habilitado, su perfil se establecerá en el perfil especificado cuando cambie de especialización."
		L_CURRENT = "%s - Activo"
		L_DUALSPEC_NOT_UNLOCKED = "Doble especialización aún no se ha desbloqueado."
	elseif locale == "esMX" then
		L_ENABLED = "Activar perfiles de especialización"
		L_ENABLED_DESC = "Cuando está habilitado, su perfil se establecerá en el perfil especificado cuando cambie de especialización."
		L_CURRENT = "%s - Activo"
		L_DUALSPEC_NOT_UNLOCKED = "Aún no has desbloqueado Doble especialización."
	elseif locale == "frFR" then
		L_ENABLED = "Activer les profils de spécialisation"
		L_ENABLED_DESC = "Lorsque cette option est activée, votre profil sera défini sur le profil spécifié lorsque vous changerez de spécialisation."
		L_CURRENT = "%s - Actifs"
		L_DUALSPEC_NOT_UNLOCKED = "Double spécialisation n’est pas encore débloquée."
	elseif locale == "itIT" then
		L_ENABLED = "Abilita i profili per la specializzazione"
		L_ENABLED_DESC = "Quando abilitato, il tuo profilo verrà impostato in base alla specializzazione usata."
		L_CURRENT = "%s - Attivi"
		L_DUALSPEC_NOT_UNLOCKED = "Doppia specializzazione non è ancora stato sbloccato."
	elseif locale == "koKR" then
		L_ENABLED = "전문화 프로필 활성화"
		L_ENABLED_DESC = "활성화하면 전문화를 변경할 때 프로필이 지정된 프로필로 설정됩니다."
		L_CURRENT = "%s - 활성화"
		L_DUALSPEC_NOT_UNLOCKED = "이중 전문화은 잠금 해제되지 않았습니다."
	elseif locale == "ptBR" then
		L_ENABLED = "Ativar perfis de especialização"
		L_ENABLED_DESC = "Quando ativado, seu perfil será definido para o perfil especificado quando você alterar a especialização."
		L_CURRENT = "%s – ativo"
		L_DUALSPEC_NOT_UNLOCKED = "Especialização Dupla não foi desbloqueada ainda."
	elseif locale == "ruRU" then
		L_ENABLED = "Включить профили специализации"
		L_ENABLED_DESC = "Если включено, ваш профиль будет зависеть от выбранной специализации."
		L_CURRENT = "%s - активен"
		L_DUALSPEC_NOT_UNLOCKED = "Двойная специализация еще не открыта."
	elseif locale == "zhCN" then
		L_ENABLED = "启用专精配置文件"
		L_ENABLED_DESC = "当启用后，当切换专精时配置文件将设置为专精配置文件。"
		L_CURRENT = "%s - 开启"
		L_DUALSPEC_NOT_UNLOCKED = "双天赋专精尚未解锁。"
	elseif locale == "zhTW" then
		L_ENABLED = "啟用專精設定檔"
		L_ENABLED_DESC = "當啟用後，當你切換專精時設定檔會設定為專精設定檔。"
		L_CURRENT = "%s - 啟動"
		L_DUALSPEC_NOT_UNLOCKED = "尚未解鎖雙天賦專精。"
	end
end

-- ----------------------------------------------------------------------------
-- Mixin
-- ----------------------------------------------------------------------------

--- Get dual spec feature status.
-- @return (boolean) true is dual spec feature enabled.
-- @name enhancedDB:IsDualSpecEnabled
function mixin:IsDualSpecEnabled()
	return lib.currentSpec > 0 and registry[self].db.char.enabled
end

--- Enable/disabled dual spec feature.
-- @param enabled (boolean) true to enable dual spec feature, false to disable it.
-- @name enhancedDB:SetDualSpecEnabled
function mixin:SetDualSpecEnabled(enabled)
	local db = registry[self].db.char
	db.enabled = not not enabled

	local currentProfile = self:GetCurrentProfile()
	for i = 1, numSpecs do
		-- nil out entries on disable, set nil entries to the current profile on enable
		db[i] = enabled and (db[i] or currentProfile) or nil
	end

	self:CheckDualSpecState()
end

--- Get the profile assigned to a specialization.
-- Defaults to the current profile.
-- @param spec (number) the specialization index.
-- @return (string) the profile name.
-- @name enhancedDB:GetDualSpecProfile
function mixin:GetDualSpecProfile(spec)
	return registry[self].db.char[spec or lib.currentSpec] or self:GetCurrentProfile()
end

--- Set the profile assigned to a specialization.
-- No validation are done to ensure the profile is valid.
-- @param profileName (string) the profile name to use.
-- @param spec (number) the specialization index.
-- @name enhancedDB:SetDualSpecProfile
function mixin:SetDualSpecProfile(profileName, spec)
	spec = spec or lib.currentSpec
	if spec < 1 or spec > numSpecs then return end

	registry[self].db.char[spec] = profileName
	self:CheckDualSpecState()
end

--- Check if a profile swap should occur.
-- There is normally no reason to call this method directly as LibDualSpec
-- takes care of calling it at the appropriate time.
-- @name enhancedDB:CheckDualSpecState
function mixin:CheckDualSpecState()
	if not registry[self].db.char.enabled then return end
	if lib.currentSpec == 0 then return end

	local profileName = self:GetDualSpecProfile()
	local profileNameLength = type(profileName) == "string" and strlenutf8(profileName) or 0
	if profileNameLength == 0 or profileName:find("^ +$")
		or (profileNameLength > 50 and not (self.sv.profiles and type(self.sv.profiles[profileName]) == "table")) then return end
	if profileName ~= self:GetCurrentProfile() then
		self:SetProfile(profileName)
	end
end

-- ----------------------------------------------------------------------------
-- AceDB-3.0 support
-- ----------------------------------------------------------------------------

local function EmbedMixin(target)
	for k,v in next, mixin do
		rawset(target, k, v)
	end
end

-- Upgrade settings from current/alternate system.
-- This sets the current profile as the profile for your current spec and your
-- swapped profile as the profile for the rest of your specs.
local function UpgradeDatabase(target)
	if lib.currentSpec == 0 then
		upgrades[target] = true
		return
	end

	local db = target:GetNamespace(MAJOR, true)
	if db and db.char.profile then
		for i = 1, numSpecs do
			if i == lib.currentSpec then
				db.char[i] = target:GetCurrentProfile()
			else
				db.char[i] = db.char.profile
			end
		end
		db.char.profile = nil
		db.char.specGroup = nil
	end
end

-- Reset a spec profile to the current one if its profile is deleted.
function lib:OnProfileDeleted(event, target, profileName)
	local db = registry[target].db.char
	if not db.enabled then return end

	for i = 1, numSpecs do
		if db[i] == profileName then
			db[i] = target:GetCurrentProfile()
		end
	end
end

-- Actually enhance the database
-- This is used on first initialization and everytime the database is reset using :ResetDB
function lib:_EnhanceDatabase(event, target)
	registry[target].db = target:GetNamespace(MAJOR, true) or target:RegisterNamespace(MAJOR)
	EmbedMixin(target)
	target:CheckDualSpecState()
end

--- Embed dual spec feature into an existing AceDB-3.0 database.
-- LibDualSpec specific methods are added to the instance.
-- @name LibDualSpec:EnhanceDatabase
-- @param target (table) the AceDB-3.0 instance.
-- @param name (string) a user-friendly name of the database (best bet is the addon name).
function lib:EnhanceDatabase(target, name)
	AceDB3 = AceDB3 or LibStub("AceDB-3.0", true)
	if type(target) ~= "table" then
		error("Usage: LibDualSpec:EnhanceDatabase(target, name): target should be a table.", 2)
	elseif type(name) ~= "string" then
		error("Usage: LibDualSpec:EnhanceDatabase(target, name): name should be a string.", 2)
	elseif not AceDB3 or not AceDB3.db_registry[target] then
		error("Usage: LibDualSpec:EnhanceDatabase(target, name): target should be an AceDB-3.0 database.", 2)
	elseif target.parent then
		error("Usage: LibDualSpec:EnhanceDatabase(target, name): cannot enhance a namespace.", 2)
	elseif registry[target] then
		return
	end
	registry[target] = { name = name }
	UpgradeDatabase(target)
	lib:_EnhanceDatabase("EnhanceDatabase", target)
	target.RegisterCallback(lib, "OnDatabaseReset", "_EnhanceDatabase")
	target.RegisterCallback(lib, "OnProfileDeleted")
end

-- ----------------------------------------------------------------------------
-- AceDBOptions-3.0 support
-- ----------------------------------------------------------------------------

options.new = {
	name = "New",
	type = "input",
	get = false,
	set = function(info, value)
		local db = info.handler.db
		if db:IsDualSpecEnabled() then
			db:SetDualSpecProfile(value, lib.currentSpec)
		else
			db:SetProfile(value)
		end
	end,
	order = 30,
}

options.choose = {
	name = "Existing Profiles",
	type = "select",
	get = "GetCurrentProfile",
	set = "SetProfile",
	values = "ListProfiles",
	arg = "common",
	disabled = function(info)
		return info.handler.db:IsDualSpecEnabled()
	end,
	order = 40,
}

options.enabled = {
	type = "toggle",
	name = function()
		if lib.currentSpec == 0 then
			return L_ENABLED
		end
		return "|cffffd200"..L_ENABLED.."|r"
	end,
	desc = function()
		local desc = L_ENABLED_DESC
		if lib.currentSpec == 0 then
			if isSpecBased then
				local _, reason = C_SpecializationInfo.CanPlayerUseTalentUI()
				if not reason or reason == "" or reason == "LEVEL_TOO_LOW" then
					reason = TALENT_MICRO_BUTTON_NO_SPEC
				end
				desc = desc .. "\n\n" .. RED_FONT_COLOR:WrapTextInColorCode(reason)
			else
				desc = desc .. "\n\n" .. RED_FONT_COLOR:WrapTextInColorCode(L_DUALSPEC_NOT_UNLOCKED)
			end
		end
		return desc
	end,
	descStyle = "inline",
	get = function(info) return info.handler.db:IsDualSpecEnabled() end,
	set = function(info, value) info.handler.db:SetDualSpecEnabled(value) end,
	disabled = function() return lib.currentSpec == 0 end,
	order = 41,
	width = "full",
}

local points = {}
for i = 1, numSpecs do
	options["specProfile" .. i] = {
		type = "select",
		name = function(info)
			local specIndex = tonumber(info[#info]:sub(-1))
			return lib.currentSpec == specIndex and L_CURRENT:format(specNames[specIndex]) or specNames[specIndex]
		end,
		desc = ClassicExpansionAtMost(LE_EXPANSION_SHADOWLANDS) and function(info)
			if lib.currentSpec == 0 then
				return nil
			end
			if ClassicExpansionAtMost(LE_EXPANSION_CATACLYSM) then -- Pre-5.0
				local specIndex = tonumber(info[#info]:sub(-1))
				local highPointsSpentIndex = nil
				for treeIndex = 1, 3 do
					local _, name, _, _, pointsSpent, _, previewPointsSpent = GetTalentTabInfo(treeIndex, nil, nil, specIndex)
					if name then
						local displayPointsSpent = pointsSpent + previewPointsSpent
						points[treeIndex] = displayPointsSpent
						if displayPointsSpent > 0 and (not highPointsSpentIndex or displayPointsSpent > points[highPointsSpentIndex]) then
							highPointsSpentIndex = treeIndex
						end
					else
						points[treeIndex] = 0
					end
				end
				if highPointsSpentIndex then
					points[highPointsSpentIndex] = GREEN_FONT_COLOR:WrapTextInColorCode(points[highPointsSpentIndex])
				end
				return ("|cffffffff%s / %s / %s|r"):format(unpack(points))
			elseif C_SpecializationInfo.GetSpecialization then -- 5.0 - 9.x
				local specGroup = tonumber(info[#info]:sub(-1))
				local specIndex = C_SpecializationInfo.GetSpecialization(nil, nil, specGroup)
				if specIndex then
					local sex = UnitSex("player")
					local _, specName = C_SpecializationInfo.GetSpecializationInfo(specIndex, nil, nil, sex)
					return ("|cffffffff%s|r"):format(specName)
				end
			end
		end or nil,
		get = function(info)
			local specIndex = tonumber(info[#info]:sub(-1))
			return info.handler.db:GetDualSpecProfile(specIndex)
		end,
		set = function(info, value)
			local specIndex = tonumber(info[#info]:sub(-1))
			info.handler.db:SetDualSpecProfile(value, specIndex)
		end,
		values = "ListProfiles",
		arg = "common",
		disabled = function(info) return not info.handler.db:IsDualSpecEnabled() end,
		order = 42 + i,
		width = 1.5,
	}
end

--- Embed dual spec options into an existing AceDBOptions-3.0 option table.
-- @name LibDualSpec:EnhanceOptions
-- @param optionTable (table) The option table returned by AceDBOptions-3.0.
-- @param target (table) The AceDB-3.0 the options operate on.
function lib:EnhanceOptions(optionTable, target)
	AceDBOptions3 = AceDBOptions3 or LibStub("AceDBOptions-3.0", true)
	AceConfigRegistry3 = AceConfigRegistry3 or LibStub("AceConfigRegistry-3.0", true)
	if type(optionTable) ~= "table" then
		error("Usage: LibDualSpec:EnhanceOptions(optionTable, target): optionTable should be a table.", 2)
	elseif type(target) ~= "table" then
		error("Usage: LibDualSpec:EnhanceOptions(optionTable, target): target should be a table.", 2)
	elseif not AceDBOptions3 or not AceDBOptions3.optionTables[target] then
		error("Usage: LibDualSpec:EnhanceOptions(optionTable, target): optionTable is not an AceDBOptions-3.0 table.", 2)
	elseif optionTable.handler.db ~= target then
		error("Usage: LibDualSpec:EnhanceOptions(optionTable, target): optionTable must be the option table of target.", 2)
	elseif not registry[target] then
		error("Usage: LibDualSpec:EnhanceOptions(optionTable, target): EnhanceDatabase should be called before EnhanceOptions(optionTable, target).", 2)
	end

	-- localize our replacements
	options.new.name = optionTable.args.new.name
	options.new.desc = optionTable.args.new.desc
	options.choose.name = optionTable.args.choose.name
	options.choose.desc = optionTable.args.choose.desc

	-- copy properties
	options.new.validate = optionTable.args.new.validate
	options.new.usage = optionTable.args.new.usage
	options.new.width = optionTable.args.new.width
	options.choose.width = optionTable.args.choose.width

	-- add our new options
	if not optionTable.plugins then
		optionTable.plugins = {}
	end
	optionTable.plugins[MAJOR] = options
end

-- ----------------------------------------------------------------------------
-- Upgrade existing
-- ----------------------------------------------------------------------------

for target in next, registry do
	UpgradeDatabase(target)
	EmbedMixin(target)
	target:CheckDualSpecState()
	local optionTable = AceDBOptions3 and AceDBOptions3.optionTables[target]
	if optionTable then
		lib:EnhanceOptions(optionTable, target)
	end
end

-- ----------------------------------------------------------------------------
-- Inspection
-- ----------------------------------------------------------------------------

do
	local function iterator(t, key)
		local data
		key, data = next(t, key)
		if key then
			return key, data.name
		end
	end

	--- Iterate through enhanced AceDB3.0 instances.
	-- The iterator returns (instance, name) pairs where instance and name are the
	-- arguments that were provided to lib:EnhanceDatabase.
	-- @name LibDualSpec:IterateDatabases
	-- @return Values to be used in a for .. in .. do statement.
	function lib:IterateDatabases()
		return iterator, lib.registry
	end
end

-- ----------------------------------------------------------------------------
-- Switching logic
-- ----------------------------------------------------------------------------

local GetProfileSpecialization do
	if isSpecBased then
		function GetProfileSpecialization()
			local spec = C_SpecializationInfo.GetSpecialization()
			if not spec or not C_SpecializationInfo.CanPlayerUseTalentUI() or spec > GetNumSpecializations() then
				spec = 0
			end
			return spec
		end
	elseif ClassicExpansionAtMost(LE_EXPANSION_CATACLYSM) then
		function GetProfileSpecialization()
			if GetNumTalentGroups() > 1 then
				return C_SpecializationInfo.GetActiveSpecGroup()
			end
			return 0
		end
	else
		function GetProfileSpecialization()
			if GetNumSpecGroups() > 1 then
				return C_SpecializationInfo.GetActiveSpecGroup()
			end
			return 0
		end
	end
end

local function OnEvent(self, event)
	local spec = GetProfileSpecialization()
	lib.currentSpec = spec

	if event == "PLAYER_LOGIN" then
		self:UnregisterEvent(event)
		self:RegisterEvent("PLAYER_ENTERING_WORLD")
		if isSpecBased then
			self:RegisterUnitEvent("PLAYER_SPECIALIZATION_CHANGED", "player")
			self:RegisterEvent("PLAYER_LEVEL_CHANGED")
		else
			self:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED")
		end
	end

	if spec > 0 and next(upgrades) then
		for target in next, upgrades do
			UpgradeDatabase(target)
		end
		wipe(upgrades)
	end

	for target in next, registry do
		target:CheckDualSpecState()
	end

	if AceConfigRegistry3 and next(registry) then
		-- Update the "Current" text in options
		-- We don't get the key for the actual registered options table, and we can't
		-- really check for our enhanced options without walking every options table,
		-- so just refresh anything.
		for appName in AceConfigRegistry3:IterateOptionsTables() do
			AceConfigRegistry3:NotifyChange(appName)
		end
	end
end

lib.eventFrame:SetScript("OnEvent", OnEvent)
if IsLoggedIn() then
	OnEvent(lib.eventFrame, "PLAYER_LOGIN")
else
	lib.eventFrame:RegisterEvent("PLAYER_LOGIN")
end
