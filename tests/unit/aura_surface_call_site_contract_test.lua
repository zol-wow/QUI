local function fail(msg)
    print("FAIL: aura_surface_call_site_contract_test - " .. msg)
    os.exit(1)
end
local function noop() end

local failNextContainer = false

local NewStub
NewStub = function(parent)
    local s = { _parent = parent, _points = {}, _shown = false, _enabled = nil, _frameLevel = 1 }
    function s:SetSize() end
    function s:ClearAllPoints() end
    function s:SetPoint(...) self._points[#self._points + 1] = { ... } end
    function s:SetAllPoints() end
    function s:SetParent() end
    function s:RegisterEvent() end
    function s:RegisterUnitEvent() end
    function s:UnregisterAllEvents() end
    function s:SetScript(k, h) self._scripts = self._scripts or {}; self._scripts[k] = h end
    function s:GetScript(k) return self._scripts and self._scripts[k] end
    function s:EnableMouse() end
    function s:SetAlpha() end
    function s:Show() self._shown = true end
    function s:Hide() self._shown = false end
    function s:IsShown() return self._shown end
    function s:SetUnit(u) self._unit = u end
    function s:SetEnabled(v) self._enabled = v end
    function s:SetFrameLevel(v) self._frameLevel = v end
    function s:GetFrameLevel() return self._frameLevel end
    function s:CreateTexture() return NewStub(self) end
    function s:CreateFontString() return NewStub(self) end
    function s:SetTexture() end
    function s:SetColorTexture() end
    function s:SetTexCoord() end
    function s:SetText() end
    function s:SetFont() end
    function s:SetTextColor() end
    function s:SetJustifyH() end
    return s
end

_G.CreateFrame = function(kind, _name, parent)
    if kind == "AuraContainer" and failNextContainer then
        failNextContainer = false
        return nil
    end
    return NewStub(parent)
end
_G.UIParent = NewStub(nil)
_G.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
_G.InCombatLockdown = function() return false end
_G.UnitExists = function() return true end
_G.AuraContainerSortMethod = { Default = 0, AuraInstanceIDOnly = 8 }
_G.AuraContainerSortDirection = { Normal = 0, Reverse = 1 }
_G.C_Timer = { After = noop, NewTicker = function() return { Cancel = noop } end }
_G.Enum = {}

local function NewNS(records)
    local skin = {
        Configure = function(_container, profile, groups)
            records[#records + 1] = { profile = profile, groups = groups }
        end,
        Restyle = noop,
        LayoutAnchor = function() return "TOPLEFT" end,
    }
    local ns = {
        SafeCall = function(_policy, fn, ...) return (pcall(fn, ...)) end,
        Addon = { AuraSkin = skin, Pixels = function(_, v) return v end },
        AuraSlots = { Park = noop, Sync = function() return true end },
        AuraSkin = skin,
    }
    _G.QUI = { AuraSkin = skin }
    assert(loadfile("core/aura_elements.lua"))("QUI", ns)
    assert(loadfile("core/aura_glue.lua"))("QUI", ns)
    assert(loadfile("core/aura_surface.lua"))("QUI", ns)
    return ns
end

local function FixedElements(E)
    local debuffs = E.NewFilterStripElement("HARMFUL")
    debuffs.iconSize = 20
    debuffs.maxIcons = 4
    local buffs = E.NewFilterStripElement("HELPFUL")
    buffs.iconSize = 18
    buffs.maxIcons = 6
    return { debuffs, buffs }
end

local function LoadUnitFrames(unitKey)
    local records = {}
    local ns = NewNS(records)
    local auras = { elementsSeeded = true, elements = { ["*"] = FixedElements(ns.AuraElements) } }
    ns.QUI_UnitFrames = {
        GetFrameUnit = function(frame) return frame.unitKey end,
        _GetUnitSettings = function() return { auras = auras } end,
    }
    assert(loadfile("QUI_UnitFrames/unitframes/unitframe_auras.lua"))("QUI_UnitFrames", ns)
    local frame = { unitKey = unitKey }
    return records, frame, function() ns.QUI_UnitFrames.ApplyContainerConfig(frame) end, 2
end

local function LoadGroupFrames()
    local records = {}
    local ns = NewNS(records)
    assert(loadfile("QUI_GroupFrames/groupframes/groupframes_aura_model.lua"))("QUI_GroupFrames", ns)
    local auras = { elementsSeeded = true, elements = { ["*"] = FixedElements(ns.AuraElements) } }
    local db = { auras = auras }
    ns.Helpers = {
        IsSecretValue = function() return false end,
        SafeValue = function(v) return v end,
        SafeToNumber = function(v) return tonumber(v) end,
        CreateDBGetter = function() return function() return db end end,
    }
    ns.QUI_GroupFrames = { GetFrameUnit = function(frame) return frame.unit end }
    assert(loadfile("QUI_GroupFrames/groupframes/groupframes_auras.lua"))("QUI_GroupFrames", ns)
    local frame = { unit = "party1", GetFrameLevel = function() return 1 end }
    return records, frame, function() ns.QUI_GroupFrameAuras.ApplyStripContainers(frame) end, 2
end

local function LoadNameplates()
    local records = {}
    local ns = NewNS(records)
    local settings = { types = { enemyNPC = { auras = { enabled = true, elements = {} } } } }
    ns.Helpers = {
        IsSecretValue = function() return false end,
        GetModuleSettings = function() return settings end,
    }
    assert(loadfile("QUI_Nameplates/nameplates/shared.lua"))("QUI_Nameplates", ns)
assert(loadfile("QUI_Nameplates/nameplates/plate_type.lua"))("QUI_Nameplates", ns)
    local NP = ns.QUI_Nameplates
    NP.Extras = { GetContext = function() return { instanceKind = "world" } end }
    assert(loadfile("QUI_Nameplates/nameplates/plate_auras.lua"))("QUI_Nameplates", ns)
    local plate = { unit = "nameplate1", npType = "enemyNPC", healthBar = {} }
    return records, plate, function() NP.Auras.ApplyAppearance(plate) end, 3
end

local function HelpfulGroup(records)
    for i = 1, #records do
        local groups = records[i].groups
        if type(groups) == "table" then
            for j = 1, #groups do
                local filter = groups[j].filter
                if type(filter) == "string" and filter:sub(1, 7) == "HELPFUL" then
                    return groups[j]
                end
            end
        end
    end
    return nil
end

local function CheckCancel(label, records, want)
    local group = HelpfulGroup(records)
    if not group then
        fail(label .. ": no HELPFUL group reached AuraSkin.Configure")
    end
    if group.cancelButtons ~= want then
        fail(string.format("%s: cancelButtons must be %s, got %s",
            label, tostring(want), tostring(group.cancelButtons)))
    end
end

local ufPlayerRecords, _ufPlayerFrame, runUFPlayer = LoadUnitFrames("player")
runUFPlayer()
CheckCancel("unit frames (player)", ufPlayerRecords, "RightButtonUp")

local ufTargetRecords, _ufTargetFrame, runUFTarget = LoadUnitFrames("target")
runUFTarget()
CheckCancel("unit frames (target)", ufTargetRecords, nil)

local gfRecords, _gfFrame, runGF = LoadGroupFrames()
runGF()
CheckCancel("group frames", gfRecords, nil)

local npRecords, _npPlate, runNP = LoadNameplates()
runNP()
CheckCancel("nameplates", npRecords, nil)

local function PoolSize(host)
    local pool = host._quiAuraContainers
    if type(pool) ~= "table" then return 0 end
    local n = 0
    for i = 1, 32 do
        if pool[i] ~= nil then n = n + 1 end
    end
    return n
end

local function CheckRegenReplay(label, loader)
    local _records, host, run, wantPool = loader()
    failNextContainer = true
    run()
    failNextContainer = false
    local pool = host._quiAuraContainers
    if type(pool) ~= "table" then
        fail(label .. ": pass produced no container pool")
    end
    if pool[1] == nil then
        fail(label .. ": onIncomplete must replay the pass and fill the dropped ordinal 1")
    end
    if PoolSize(host) ~= wantPool then
        fail(string.format("%s: replay must complete the pool, want %d containers, got %d",
            label, wantPool, PoolSize(host)))
    end
end

CheckRegenReplay("unit frames", function() return LoadUnitFrames("player") end)
CheckRegenReplay("group frames", LoadGroupFrames)
CheckRegenReplay("nameplates", LoadNameplates)

print("OK: aura_surface_call_site_contract_test")
