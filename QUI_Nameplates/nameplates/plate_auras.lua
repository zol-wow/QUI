local ADDON_NAME, ns = ...
local NP = ns.QUI_Nameplates
if not NP then return end

local QUICore = ns.Addon

local type = type
local pcall = pcall

local NPAuras = {}
NP.Auras = NPAuras

function NPAuras.IsContextEnabled(auraSettings, instanceKind)
    auraSettings = auraSettings or {}
    if instanceKind == "raid" then
        return auraSettings.enableRaid ~= false
    elseif instanceKind == "dungeon" then
        return auraSettings.enableDungeon ~= false
    end
    return auraSettings.enableWorld ~= false
end

local function GetAuraElements()
    return ns.AuraElements or (_G.QUI and _G.QUI.AuraElements)
end

local function GetAuraSkin()
    return _G.QUI and _G.QUI.AuraSkin
end

function NPAuras.DefaultNameplateBucket()
    local E = GetAuraElements()
    if not (E and E.NewFilterStripElement) then return {} end

    local debuffs = E.NewFilterStripElement("HARMFUL")
    debuffs.iconSize = 26
    debuffs.maxIcons = 5
    debuffs.spacing = 2
    debuffs.growDirection = "RIGHT"
    debuffs.anchor = "TOP"
    debuffs.offsetX = 0
    debuffs.offsetY = 20
    debuffs.onlyMine = true
    debuffs.nameplateOnly = true
    if type(debuffs.duration) == "table" then debuffs.duration.fontSize = 12 end
    if type(debuffs.stack) == "table" then debuffs.stack.fontSize = 11 end

    local buffs = E.NewFilterStripElement("HELPFUL")
    buffs.iconSize = 24
    buffs.maxIcons = 4
    buffs.spacing = 2
    buffs.growDirection = "RIGHT"
    buffs.anchor = "TOP"
    buffs.offsetX = 0
    buffs.offsetY = 50
    buffs.nameplateOnly = true
    if type(buffs.duration) == "table" then buffs.duration.fontSize = 12 end
    if type(buffs.stack) == "table" then buffs.stack.fontSize = 12 end

    local cc = E.NewFilterStripElement("HARMFUL")
    cc.iconSize = 24
    cc.maxIcons = 3
    cc.spacing = 2
    cc.growDirection = "LEFT"
    cc.anchor = "LEFT"
    cc.offsetX = -4
    cc.offsetY = 0
    if type(cc.duration) == "table" then cc.duration.fontSize = 12 end
    if type(cc.stack) == "table" then cc.stack.fontSize = 12 end
    E.ApplyWhatToShow(cc, "crowdControl")

    return { debuffs, buffs, cc }
end
NP.DefaultNameplateBucket = NPAuras.DefaultNameplateBucket

function NPAuras.ResolveElements(settings, ignoreContext)
    local auras = (settings and settings.auras) or {}
    if auras.enabled == false then return {} end
    if not ignoreContext then
        local context = NP.Extras.GetContext()
        if not NPAuras.IsContextEnabled(auras, context.instanceKind) then return {} end
    end
    local E = GetAuraElements()
    if not E then return {} end
    if type(auras.elements) ~= "table" then auras.elements = {} end
    if E.EnsureSeeded then
        E.EnsureSeeded(auras, NPAuras.DefaultNameplateBucket)
    end
    local bucket = auras.elements["*"]
    if type(bucket) ~= "table" then return {} end
    local out = {}
    for i = 1, #bucket do
        local e = bucket[i]
        if type(e) == "table" and e.enabled ~= false then
            out[#out + 1] = e
        end
    end
    return out
end

local ApplyElementPass

ApplyElementPass = function(plate, allowCreate)
    if not plate or not plate.unit then return end
    local AuraSurface = ns.AuraSurface
    local AuraSkin = GetAuraSkin()
    local AuraGlue = ns.AuraGlue
    if not (AuraSurface and AuraSkin and AuraGlue) then return end

    local settings = NP.GetTypeSettings(plate)
    local elements = NPAuras.ResolveElements(settings)
    if NP.IsLightweightMode(plate.npRenderMode) then elements = {} end

    AuraSurface.ApplyElementPass(plate, elements, {
        unit = plate.unit,
        allowCreate = allowCreate == true,
        cancelEligible = false,
        profileFor = function(element)
            return AuraGlue.ElementProfile(element)
        end,
        anchorContainer = function(container, host, element, profile)
            container:ClearAllPoints()
            container:SetPoint(AuraSkin.LayoutAnchor(profile), host.healthBar,
                element.anchor or "TOP",
                QUICore:Pixels(element.offsetX or 0, host),
                QUICore:Pixels(element.offsetY or 0, host))
        end,
        onIncomplete = function(host)
            AuraGlue.QueueRegenWork(host, function(p) ApplyElementPass(p, true) end)
        end,
    })
end

function NPAuras.ApplyAppearance(plate)
    if InCombatLockdown() then
        local ok = ns.SafeCall("best-effort-style", ApplyElementPass, plate, true)
        if not ok then
            local AuraGlue = ns.AuraGlue
            if AuraGlue then
                AuraGlue.QueueRegenWork(plate, function(p) ApplyElementPass(p, true) end)
            end
        end
        return
    end
    ApplyElementPass(plate, true)
end

function NPAuras.Clear(plate)
    local pool = plate and plate._quiAuraContainers
    if not pool then return end
    for i = 1, #pool do
        local container = pool[i]
        pcall(container.SetEnabled, container, false)
        container:Hide()
    end
end
