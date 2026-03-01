--[[
    QUI CDM Spell Data

    Essential/Utility/Buff: observes hidden Blizzard CDM viewers and exports
    spell lists. QUI reads the spell list from hidden Blizzard icons,
    then renders with addon-owned frames.

    All three viewers are hidden (alpha=0, mouse disabled). QUI creates
    addon-owned containers and reparents Blizzard's children into them.
    Blizzard continues managing all data — textures, cooldowns, stacks.

    Initialization is driven externally by cdm_containers.lua calling
    CDMSpellData:Initialize() — no self-bootstrapping event frame.
]]

local ADDON_NAME, ns = ...
local Helpers = ns.Helpers

-- Enable CDM immediately when file loads (before any events fire)
pcall(function() SetCVar("cooldownViewerEnabled", 1) end)

---------------------------------------------------------------------------
-- MODULE
---------------------------------------------------------------------------
local CDMSpellData = {}

---------------------------------------------------------------------------
-- CONSTANTS
---------------------------------------------------------------------------
local VIEWER_NAMES = {
    essential = "EssentialCooldownViewer",
    utility   = "UtilityCooldownViewer",
    buff      = "BuffIconCooldownViewer",
}

---------------------------------------------------------------------------
-- STATE
---------------------------------------------------------------------------
local spellLists = {
    essential = {},
    utility   = {},
    buff      = {},
}
local viewersHidden = false
local scanTimer = nil
local initialized = false
local lastSpellCounts = { essential = 0, utility = 0, buff = 0 }
local buffChildrenHooked = false  -- one-time hook for buff viewer aura events

-- TAINT SAFETY: Track hook state in a weak-keyed table instead of writing
-- _quiBuffHooked directly to Blizzard frames. Direct property writes taint
-- the frame, causing isActive to become a "secret boolean tainted by QUI".
local hookedBuffChildren = setmetatable({}, { __mode = "k" })

---------------------------------------------------------------------------
-- HELPER: Check if a child frame is a cooldown icon
---------------------------------------------------------------------------
local function IsIconFrame(child)
    if not child then return false end
    return (child.Icon or child.icon) and (child.Cooldown or child.cooldown)
end

---------------------------------------------------------------------------
-- HELPER: Check if an icon has a valid spell texture
---------------------------------------------------------------------------
local function HasValidTexture(icon)
    local tex = icon.Icon or icon.icon
    if tex and tex.GetTexture then
        local texID = tex:GetTexture()
        if texID == nil then return false end
        if type(issecretvalue) == "function" and issecretvalue(texID) then
            return true -- secret texture values imply a real texture exists
        end
        return texID ~= 0 and texID ~= ""
    end
    return false
end

---------------------------------------------------------------------------
-- FORCE LOAD CDM: Open settings panel invisibly to force Blizzard init
---------------------------------------------------------------------------
local function ForceLoadCDM()
    if InCombatLockdown() then return end
    local settingsFrame = _G["CooldownViewerSettings"]
    if settingsFrame then
        settingsFrame:SetAlpha(0)
        settingsFrame:Show()
        C_Timer.After(0.2, function()
            if settingsFrame then
                settingsFrame:Hide()
                settingsFrame:SetAlpha(1)
            end
        end)
    end
end

---------------------------------------------------------------------------
-- HIDE / SHOW BLIZZARD VIEWERS
-- During normal gameplay: hidden (alpha 0, no mouse).
-- During Edit Mode: visible (restored) so Blizzard's Edit Mode can interact.
-- SetAlpha hooks prevent Blizzard's CDM code from restoring viewer visibility
-- during combat (cooldown activation triggers SetAlpha(1) internally).
---------------------------------------------------------------------------
local viewerAlphaHooked = {} -- [viewerName] = true

local function HookViewerAlpha(viewer, viewerName)
    if viewerAlphaHooked[viewerName] then return end
    viewerAlphaHooked[viewerName] = true
    hooksecurefunc(viewer, "SetAlpha", function(self, alpha)
        if viewersHidden and alpha > 0 then
            self:SetAlpha(0)
        end
    end)
end

-- Periodic alpha enforcer: catches cases where Blizzard restores alpha
-- via internal paths that don't trigger the SetAlpha hook.
-- Runs only while viewers are hidden; stops when shown (Edit Mode).
local alphaEnforcerFrame = CreateFrame("Frame")
local alphaEnforcerElapsed = 0
alphaEnforcerFrame:SetScript("OnUpdate", function(self, dt)
    if not viewersHidden then return end
    alphaEnforcerElapsed = alphaEnforcerElapsed + dt
    if alphaEnforcerElapsed < 0.1 then return end
    alphaEnforcerElapsed = 0
    for _, viewerName in pairs(VIEWER_NAMES) do
        local viewer = _G[viewerName]
        if viewer and viewer:GetAlpha() > 0 then
            viewer:SetAlpha(0)
        end
    end
end)

local function HideBlizzardViewers()
    if viewersHidden then return end
    -- Hide all three viewers (alpha 0, no mouse).
    -- QUI creates addon-owned containers and reparents children into them.
    for vtype, viewerName in pairs(VIEWER_NAMES) do
        local viewer = _G[viewerName]
        if viewer then
            viewer:SetAlpha(0)
            viewer:EnableMouse(false)
            if viewer.SetMouseClickEnabled then
                viewer:SetMouseClickEnabled(false)
            end
            -- Hook SetAlpha to prevent Blizzard from restoring visibility
            -- during combat (CDM system calls SetAlpha(1) when cooldowns activate)
            HookViewerAlpha(viewer, viewerName)
        end
    end
    viewersHidden = true
end

local function ShowBlizzardViewers()
    if not viewersHidden then return end
    -- Clear the hidden flag BEFORE setting alpha so the hook doesn't fight us
    viewersHidden = false
    for vtype, viewerName in pairs(VIEWER_NAMES) do
        local viewer = _G[viewerName]
        if viewer then
            viewer:SetAlpha(1)
            viewer:EnableMouse(true)
            if viewer.SetMouseClickEnabled then
                viewer:SetMouseClickEnabled(true)
            end
        end
    end
end

---------------------------------------------------------------------------
-- SCAN: Extract spell data from hidden Blizzard CDM icons
-- All three viewer types: read shown children for spell lists with
-- _blizzChild references. Buff children are reparented by cdm_containers.
---------------------------------------------------------------------------
local function ScanCooldownViewer(viewerType)
    local viewerName = VIEWER_NAMES[viewerType]
    local viewer = _G[viewerName]
    if not viewer then return end

    local container = viewer.viewerFrame or viewer

    local list = {}
    local sel = viewer.Selection

    -- For buff: scan both the Blizzard viewer AND QUI_BuffContainer.
    -- After reparenting, children live in the addon container, not the viewer.
    local containersToScan = { container }
    if viewerType == "buff" then
        local addonContainer = _G["QUI_BuffIconContainer"]
        if addonContainer and addonContainer ~= container then
            containersToScan[#containersToScan + 1] = addonContainer
        end
    end

    for _, scanContainer in ipairs(containersToScan) do
        local numChildren = scanContainer:GetNumChildren()
        for i = 1, numChildren do
            local child = select(i, scanContainer:GetChildren())
            if child and child ~= sel and not child._isCustomCDMIcon and IsIconFrame(child) then
                local shown = child:IsShown()
                local hasTex = HasValidTexture(child)
                local hasCDInfo = (child.cooldownInfo ~= nil)

                if shown and hasTex and (hasTex or hasCDInfo) then
                    local spellID, overrideSpellID, name, isAura
                    local layoutIndex = child.layoutIndex or 9999

                    if child.cooldownInfo then
                        local info = child.cooldownInfo
                        spellID = Helpers.SafeValue(info.spellID, nil)
                        overrideSpellID = Helpers.SafeValue(info.overrideSpellID, nil)
                        name = Helpers.SafeValue(info.name, nil)
                        isAura = info.wasSetFromAura or info.cooldownUseAuraDisplayTime or false

                    end

                    if spellID and not name then
                        local spellInfo = C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(spellID)
                        if spellInfo then name = spellInfo.name end
                    end

                    if spellID then
                        -- Check for multi-charge spells
                        -- maxCharges can be a secret value in combat; use SafeToNumber
                        local hasCharges = false
                        if C_Spell.GetSpellCharges then
                            local ci = C_Spell.GetSpellCharges(overrideSpellID or spellID)
                            if ci then
                                local maxC = Helpers.SafeToNumber(ci.maxCharges, 0)
                                if maxC and maxC > 1 then
                                    hasCharges = true
                                end
                            end
                        end

                        list[#list + 1] = {
                            spellID = spellID,
                            overrideSpellID = overrideSpellID or spellID,
                            name = name or "",
                            isAura = isAura or false,
                            hasCharges = hasCharges,
                            layoutIndex = layoutIndex,
                            viewerType = viewerType,
                            _blizzChild = child,
                        }
                    end
                end
            end
        end
    end

    table.sort(list, function(a, b)
        return a.layoutIndex < b.layoutIndex
    end)

    spellLists[viewerType] = list
end

---------------------------------------------------------------------------
-- BUFF VIEWER: Legacy scan (no longer used — buff now routes through
-- ScanCooldownViewer like essential/utility). Kept for reference only.
---------------------------------------------------------------------------
local function ScanBuffViewer()
    local viewerName = VIEWER_NAMES["buff"]
    local viewer = _G[viewerName]
    if not viewer then return end

    -- Count shown children for change detection
    local container = viewer.viewerFrame or viewer
    local sel = viewer.Selection
    local numChildren = container:GetNumChildren()
    local shownCount = 0

    for i = 1, numChildren do
        local child = select(i, container:GetChildren())
        if child and child ~= sel then
            local hasIcon = child.Icon or child.icon
            if hasIcon and child:IsShown() and child.layoutIndex then
                shownCount = shownCount + 1
            end
        end
    end

    -- Store count for change detection (used by ScanAll)
    spellLists["buff"] = shownCount
end

---------------------------------------------------------------------------
-- HOOK BUFF VIEWER CHILDREN: Aura events trigger rescan + reparent
-- Hook OnActiveStateChanged, OnUnitAuraAddedEvent,
-- OnUnitAuraRemovedEvent on each child frame.
---------------------------------------------------------------------------
local buffEventPending = false
local function OnBuffAuraEvent()
    -- Debounce: batch rapid aura events into a single rescan + reparent
    if buffEventPending then return end
    buffEventPending = true
    C_Timer.After(0.1, function()
        buffEventPending = false
        -- Rescan buff viewer to update spell list (needed for reparent)
        ScanCooldownViewer("buff")
        -- Notify containers to reparent children + buffbar to style/position
        if _G.QUI_OnBuffDataChanged then
            _G.QUI_OnBuffDataChanged()
        end
    end)
end

local function HookBuffViewerChildren()
    if buffChildrenHooked then return end

    local viewer = _G[VIEWER_NAMES["buff"]]
    if not viewer then return end

    local container = viewer.viewerFrame or viewer
    local numChildren = container:GetNumChildren()

    for i = 1, numChildren do
        local child = select(i, container:GetChildren())
        if child and child ~= viewer.Selection then
            -- Hook aura lifecycle methods (like CMC does)
            -- TAINT SAFETY: Track hook state in hookedBuffChildren (weak-keyed)
            -- instead of writing _quiBuffHooked to the Blizzard frame directly.
            local hookState = hookedBuffChildren[child]
            if not hookState then
                hookState = {}
                hookedBuffChildren[child] = hookState
            end
            if child.OnActiveStateChanged and not hookState.active then
                hooksecurefunc(child, "OnActiveStateChanged", OnBuffAuraEvent)
                hookState.active = true
            end
            if child.OnUnitAuraAddedEvent and not hookState.added then
                hooksecurefunc(child, "OnUnitAuraAddedEvent", OnBuffAuraEvent)
                hookState.added = true
            end
            if child.OnUnitAuraRemovedEvent and not hookState.removed then
                hooksecurefunc(child, "OnUnitAuraRemovedEvent", OnBuffAuraEvent)
                hookState.removed = true
            end
        end
    end

    buffChildrenHooked = true
end

local function ScanViewer(viewerType)
    ScanCooldownViewer(viewerType)
    -- Hook aura event callbacks on buff children for live updates
    if viewerType == "buff" and not buffChildrenHooked then
        HookBuffViewerChildren()
    end
end

local function ScanAll()
    if InCombatLockdown() then return end

    ScanViewer("essential")
    ScanViewer("utility")
    ScanViewer("buff")

    -- Check if spell counts changed (indicates meaningful data change)
    local changed = false
    for viewerType, list in pairs(spellLists) do
        local count = type(list) == "table" and #list or 0
        if count ~= lastSpellCounts[viewerType] then
            lastSpellCounts[viewerType] = count
            changed = true
        end
    end

    -- Notify containers that spell data changed
    if changed then
        if _G.QUI_OnSpellDataChanged then
            _G.QUI_OnSpellDataChanged()
        end
    end
end

---------------------------------------------------------------------------
-- BLIZZARD SETTINGS SYNC: Detect when user changes CDM settings
-- and rescan so owned icons match Blizzard's view state.
---------------------------------------------------------------------------
local settingsHooked = false

local function HookBlizzardSettings()
    if settingsHooked then return end
    settingsHooked = true

    -- EventRegistry: fires when user adds/removes spells or changes settings
    if EventRegistry and EventRegistry.RegisterCallback then
        EventRegistry:RegisterCallback("CooldownViewerSettings.OnDataChanged", function()
            C_Timer.After(0.1, ScanAll)
        end, CDMSpellData)
    end

    -- Per-viewer RefreshLayout: fires when Blizzard recalculates layout
    for _, viewerName in pairs(VIEWER_NAMES) do
        local viewer = _G[viewerName]
        if viewer and viewer.RefreshLayout then
            hooksecurefunc(viewer, "RefreshLayout", function()
                if not Helpers.IsEditModeActive() then
                    C_Timer.After(0, ScanAll)
                end
            end)
        end
    end
end

---------------------------------------------------------------------------
-- UPDATE CVar: Sync Blizzard CVar with QUI's enable/disable settings
---------------------------------------------------------------------------
local function UpdateCooldownViewerCVar()
    local QUICore = ns.Addon
    local db = QUICore and QUICore.db and QUICore.db.profile and QUICore.db.profile.ncdm
    if not db then return end

    local essentialEnabled = db.essential and db.essential.enabled
    local utilityEnabled = db.utility and db.utility.enabled
    local buffEnabled = db.buff and db.buff.enabled

    if essentialEnabled or utilityEnabled or buffEnabled then
        pcall(function() SetCVar("cooldownViewerEnabled", 1) end)
    else
        pcall(function() SetCVar("cooldownViewerEnabled", 0) end)
    end
end

---------------------------------------------------------------------------
-- PUBLIC API
---------------------------------------------------------------------------
function CDMSpellData:GetSpellList(viewerType)
    return spellLists[viewerType] or {}
end

function CDMSpellData:ForceScan()
    ScanAll()
end

function CDMSpellData:IsViewerHidden()
    return viewersHidden
end

function CDMSpellData:HideViewers()
    HideBlizzardViewers()
end

function CDMSpellData:ShowViewers()
    ShowBlizzardViewers()
end

function CDMSpellData:UpdateCVar()
    UpdateCooldownViewerCVar()
end

function CDMSpellData:GetBlizzardViewer(viewerType)
    local name = VIEWER_NAMES[viewerType]
    return name and _G[name] or nil
end

function CDMSpellData:GetBlizzardViewerName(viewerType)
    return VIEWER_NAMES[viewerType]
end

---------------------------------------------------------------------------
-- EDIT MODE INTEGRATION
-- Show Blizzard viewers during Edit Mode, hide them when exiting.
---------------------------------------------------------------------------
local function RegisterEditModeCallbacks()
    local QUICore = ns.Addon
    if not QUICore then return end

    if QUICore.RegisterEditModeEnter then
        QUICore:RegisterEditModeEnter(function()
            -- Show Blizzard viewers so Edit Mode can interact with them.
            -- Position them at the owned containers' current position so
            -- the user sees them where QUI had them.
            if _G.QUI_OnEditModeEnterCDM then
                _G.QUI_OnEditModeEnterCDM()
            end
            ShowBlizzardViewers()
        end)
    end

    if QUICore.RegisterEditModeExit then
        QUICore:RegisterEditModeExit(function()
            -- Read new position from Blizzard viewers, hide them again,
            -- show owned containers at the new position.
            HideBlizzardViewers()
            if _G.QUI_OnEditModeExitCDM then
                _G.QUI_OnEditModeExitCDM()
            end
            -- Rescan after Edit Mode (Blizzard may have changed settings)
            C_Timer.After(0.3, ScanAll)
        end)
    end
end

---------------------------------------------------------------------------
-- INITIALIZE: Called by cdm_containers.lua Initialize() to bootstrap
-- spell data scanning. Replaces the self-bootstrapping event frame.
---------------------------------------------------------------------------
function CDMSpellData:Initialize()
    ForceLoadCDM()
    C_Timer.After(0.5, function()
        UpdateCooldownViewerCVar()
        HideBlizzardViewers()
        ScanAll()
        RegisterEditModeCallbacks()
        HookBlizzardSettings()
        initialized = true
        -- Start periodic scan (out of combat only, 0.5s interval)
        if not scanTimer then
            scanTimer = C_Timer.NewTicker(0.5, function()
                if not InCombatLockdown() then
                    ScanAll()
                end
            end)
        end
    end)
    -- Register runtime events
    local eventFrame = CreateFrame("Frame")
    eventFrame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
    eventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    eventFrame:SetScript("OnEvent", function(self, event, arg)
        if event == "SPELL_UPDATE_COOLDOWN" then
            if not InCombatLockdown() then
                ScanAll()
            end
        elseif event == "PLAYER_SPECIALIZATION_CHANGED" then
            C_Timer.After(0.5, function() ScanAll() end)
        elseif event == "PLAYER_ENTERING_WORLD" then
            C_Timer.After(1.0, function()
                if not initialized then
                    -- Blizzard_CooldownManager may have loaded before us
                    ForceLoadCDM()
                    C_Timer.After(0.5, function()
                        UpdateCooldownViewerCVar()
                        HideBlizzardViewers()
                        ScanAll()
                        RegisterEditModeCallbacks()
                        HookBlizzardSettings()
                        initialized = true
                    end)
                else
                    HideBlizzardViewers()
                    ScanAll()
                end
            end)
        end
    end)
end

---------------------------------------------------------------------------
-- DEBUG SLASH COMMAND: /cdmdebug
---------------------------------------------------------------------------
SLASH_CDMDEBUG1 = "/cdmdebug"
local P = "|cff00ccff[CDM-Debug]|r"

SlashCmdList["CDMDEBUG"] = function()
    print(P, "Running debug scan...")
    ScanAll()

    --------------------------------------------------------------------------
    -- 1. HARVESTED DATA (all three viewer types store spell tables)
    --------------------------------------------------------------------------
    for _, vtype in ipairs({"essential", "utility", "buff"}) do
        local list = spellLists[vtype] or {}
        print(P, vtype, "has", #list, "harvested entries")
        for idx, entry in ipairs(list) do
            print(P, "  [" .. idx .. "]",
                "spell:", entry.spellID,
                "name:", entry.name,
                "aura:", tostring(entry.isAura))
        end
    end

    --------------------------------------------------------------------------
    -- 2. BUFF DB SETTINGS (what LayoutContainer reads)
    --------------------------------------------------------------------------
    local QUICore = ns.Addon
    local ncdmDB = QUICore and QUICore.db and QUICore.db.profile and QUICore.db.profile.ncdm
    local buffSettings = ncdmDB and ncdmDB.buff
    if buffSettings then
        print(P, "--- BUFF DB SETTINGS ---")
        print(P, "  enabled:", tostring(buffSettings.enabled))
        print(P, "  iconSize:", tostring(buffSettings.iconSize))
        print(P, "  borderSize:", tostring(buffSettings.borderSize))
        print(P, "  zoom:", tostring(buffSettings.zoom))
        print(P, "  aspectRatioCrop:", tostring(buffSettings.aspectRatioCrop))
        print(P, "  durationSize:", tostring(buffSettings.durationSize),
            "anchor:", tostring(buffSettings.durationAnchor),
            "offX:", tostring(buffSettings.durationOffsetX),
            "offY:", tostring(buffSettings.durationOffsetY))
        print(P, "  stackSize:", tostring(buffSettings.stackSize),
            "anchor:", tostring(buffSettings.stackAnchor),
            "offX:", tostring(buffSettings.stackOffsetX),
            "offY:", tostring(buffSettings.stackOffsetY))
    else
        print(P, "  BUFF SETTINGS NOT FOUND in db.profile.ncdm.buff")
    end

    --------------------------------------------------------------------------
    -- 3. SWIPE SETTINGS (what ApplySwipeToIcon reads)
    --------------------------------------------------------------------------
    local swipeSettings = QUICore and QUICore.db and QUICore.db.profile and QUICore.db.profile.cooldownSwipe
    print(P, "--- SWIPE DB SETTINGS (profile.cooldownSwipe) ---")
    if swipeSettings then
        for k, v in pairs(swipeSettings) do
            if type(v) == "table" then
                print(P, "  ", k, ":", "{" .. table.concat(v, ", ") .. "}")
            else
                print(P, "  ", k, ":", tostring(v))
            end
        end
    else
        print(P, "  NOT FOUND — will use swipe.lua DEFAULTS")
    end

    -- Show what GetSettings actually resolves to
    local swipeMod = _G.QUI and _G.QUI.CooldownSwipe
    if swipeMod and swipeMod.GetSettings then
        local resolved = swipeMod.GetSettings()
        print(P, "--- SWIPE RESOLVED SETTINGS ---")
        if resolved then
            print(P, "  showBuffSwipe:", tostring(resolved.showBuffSwipe))
            print(P, "  showBuffIconSwipe:", tostring(resolved.showBuffIconSwipe))
            print(P, "  showGCDSwipe:", tostring(resolved.showGCDSwipe))
            print(P, "  showCooldownSwipe:", tostring(resolved.showCooldownSwipe))
            print(P, "  showRechargeEdge:", tostring(resolved.showRechargeEdge))
            print(P, "  overlayColorMode:", tostring(resolved.overlayColorMode or "nil"))
            print(P, "  overlayColor:", tostring(resolved.overlayColor and ("{" .. table.concat(resolved.overlayColor, ", ") .. "}") or "nil"))
            print(P, "  swipeColorMode:", tostring(resolved.swipeColorMode or "nil"))
            print(P, "  swipeColor:", tostring(resolved.swipeColor and ("{" .. table.concat(resolved.swipeColor, ", ") .. "}") or "nil"))
        end
    else
        print(P, "  QUI.CooldownSwipe NOT FOUND (swipe.lua not loaded?)")
    end

    --------------------------------------------------------------------------
    -- 4. BUFF VIEWER CHILDREN (Blizzard's actual frames, styled by QUI)
    --------------------------------------------------------------------------
    local buffViewer = _G["BuffIconCooldownViewer"]
    if buffViewer then
        local cnt = buffViewer.viewerFrame or buffViewer
        local n = cnt:GetNumChildren()
        print(P, "--- BuffIconCooldownViewer children:", n, "---")
        for i = 1, n do
            local child = select(i, cnt:GetChildren())
            if child and child ~= buffViewer.Selection then
                local shown = child:IsShown()
                local hasIcon = child.Icon or child.icon

                if hasIcon then
                    local iconTex = child.Icon or child.icon
                    local texID = iconTex and iconTex.GetTexture and iconTex:GetTexture()
                    local w, h = child:GetSize()
                    print(P, "  [" .. i .. "]",
                        "shown:", tostring(shown),
                        "layoutIdx:", tostring(child.layoutIndex or "nil"),
                        "tex:", tostring(texID or "nil"),
                        "size:", string.format("%.0fx%.0f", w or 0, h or 0),
                        "hooked:", tostring(hookedBuffChildren[child] and true or false))

                    -- Cooldown state (native Blizzard)
                    local cd = child.Cooldown
                    if cd then
                        local drawSwipe = cd.GetDrawSwipe and cd:GetDrawSwipe() or false
                        local drawEdge = cd.GetDrawEdge and cd:GetDrawEdge() or false
                        local r, g, b, a = 0, 0, 0, 0
                        if cd.GetSwipeColor then r, g, b, a = cd:GetSwipeColor() end
                        local swipeTex = cd.GetSwipeTexture and cd:GetSwipeTexture() or "n/a"
                        print(P, "    cooldown: drawSwipe=", tostring(drawSwipe),
                            "drawEdge=", tostring(drawEdge),
                            "swipeColor=", string.format("%.2f,%.2f,%.2f,%.2f", r or 0, g or 0, b or 0, a or 0),
                            "swipeTex:", tostring(swipeTex))
                    end

                    -- Blizzard sub-frames
                    local stacks = child.Applications and child.Applications.Applications
                    local charges = child.ChargeCount and child.ChargeCount.Current
                    local flash = child.CooldownFlash
                    local debuff = child.DebuffBorder
                    print(P, "    blizz: stacks=", tostring(stacks and stacks:GetText() or "nil"),
                        "charges=", tostring(charges and charges:GetText() or "nil"),
                        "flash=", tostring(flash and flash:IsShown() or "nil"),
                        "debuffBorder=", tostring(debuff and debuff:IsShown() or "nil"))

                    -- cooldownInfo (if available)
                    if child.cooldownInfo then
                        local info = child.cooldownInfo
                        print(P, "    cdInfo: spellID=", tostring(info.spellID),
                            "name=", tostring(info.name),
                            "isAura=", tostring(info.wasSetFromAura or info.cooldownUseAuraDisplayTime or false))
                    end
                else
                    print(P, "  [" .. i .. "] non-icon child, shown:", tostring(shown),
                        "name:", tostring(child:GetName()))
                end
            end
        end
    else
        print(P, "BuffIconCooldownViewer NOT FOUND")
    end

    --------------------------------------------------------------------------
    -- 5. BUFF VIEWER HOOK & CONTAINER STATE
    --------------------------------------------------------------------------
    print(P, "--- BUFF VIEWER HOOKS ---")
    print(P, "buffChildrenHooked:", tostring(buffChildrenHooked))
    local bv = _G["BuffIconCooldownViewer"]
    if bv then
        local cnt2 = bv.viewerFrame or bv
        local nChildren = cnt2:GetNumChildren()
        local hookedCount, shownCount2 = 0, 0
        for i = 1, nChildren do
            local c = select(i, cnt2:GetChildren())
            if c then
                if hookedBuffChildren[c] then hookedCount = hookedCount + 1 end
                if c:IsShown() then shownCount2 = shownCount2 + 1 end
            end
        end
        print(P, "children:", nChildren, "hooked:", hookedCount, "shown:", shownCount2)
        print(P, "alpha:", bv:GetAlpha(), "mouseEnabled:", tostring(bv:IsMouseEnabled()))
    end

    -- Confirm QUI_BuffIconContainer points at the viewer
    local buffCont = _G["QUI_BuffIconContainer"]
    if buffCont then
        local isViewer = (buffCont == bv)
        print(P, "QUI_BuffIconContainer == BuffIconCooldownViewer:", tostring(isViewer))
        if not isViewer then
            print(P, "  WARNING: QUI_BuffIconContainer is NOT the viewer — old mirror path still active?")
        end
    else
        print(P, "QUI_BuffIconContainer NOT FOUND (containers not yet initialized?)")
    end
end

---------------------------------------------------------------------------
-- NAMESPACE EXPORT
---------------------------------------------------------------------------
ns.CDMSpellData = CDMSpellData
