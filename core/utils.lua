local ADDON_NAME, ns = ...

ns.Helpers = ns.Helpers or {}
local Helpers = ns.Helpers
local pairs = pairs
local ipairs = ipairs
local tostring = tostring
local tonumber = tonumber
local select = select
local table_remove = table.remove

local LSM = LibStub("LibSharedMedia-3.0", true)
ns.LSM = LSM

Helpers.AssetPath = "Interface\\AddOns\\" .. ADDON_NAME .. "\\assets\\"

local issecretvalue = _G.issecretvalue
local canaccesstable = _G.canaccesstable

function Helpers.IsSecretValue(value)
    return issecretvalue and issecretvalue(value) or false
end

function Helpers.HasSecretValue(...)
    if not issecretvalue then return false end
    for i = 1, select("#", ...) do
        if issecretvalue(select(i, ...)) then
            return true
        end
    end
    return false
end

function Helpers.CanAccessTable(tbl)
    return not canaccesstable or canaccesstable(tbl)
end

function Helpers.CanAccessValue(value)
    return not canaccessvalue or canaccessvalue(value)
end

function Helpers.SafeValue(value, fallback)
    if issecretvalue and issecretvalue(value) then
        return fallback
    end
    return value
end

function Helpers.HasTaintedWidgetContainer(tooltip)
    if not tooltip or not tooltip.GetChildren then return false end

    local okChildren, children = pcall(function()
        return { tooltip:GetChildren() }
    end)
    if not okChildren or not children then
        return false
    end

    for i = 1, #children do
        local child = children[i]
        if child then
            local ok, isWidgetContainer, widgetSetID, shownWidgetCount, numWidgetsShowing, dirty, numPoints = pcall(function()
                local isWidget = child.RegisterForWidgetSet
                    or child.widgetType
                    or child.widgetSetID ~= nil
                    or child.shownWidgetCount ~= nil
                    or child.numWidgetsShowing ~= nil

                local points
                if child.GetNumPoints then
                    points = child:GetNumPoints()
                end

                return isWidget, child.widgetSetID, child.shownWidgetCount, child.numWidgetsShowing, child.dirty, points
            end)

            if not ok then
                return true
            end

            if isWidgetContainer then
                if Helpers.IsSecretValue(widgetSetID)
                    or Helpers.IsSecretValue(shownWidgetCount)
                    or Helpers.IsSecretValue(numWidgetsShowing)
                    or Helpers.IsSecretValue(dirty)
                    or Helpers.IsSecretValue(numPoints) then
                    return true -- @secret-policy: report-secret-detected (unreadable widget state counts as tainted)
                end

                if widgetSetID ~= nil or dirty == true then
                    return true
                end

                local shownCount = tonumber(shownWidgetCount)
                if shownCount and shownCount > 0 then
                    return true
                end

                local showingCount = tonumber(numWidgetsShowing)
                if showingCount and showingCount > 0 then
                    return true
                end

                if child.IsShown then
                    local okShown, shown = pcall(child.IsShown, child)
                    if not okShown or shown then
                        return true
                    end
                end
            end
        end
    end

    return false
end

function Helpers.BaseClearAllPoints(frame)
    if not frame then return end
    local fn = frame.ClearAllPointsBase or frame.ClearAllPoints
    if fn then fn(frame) end
end

function Helpers.BaseSetPoint(frame, ...)
    if not frame then return end
    local fn = frame.SetPointBase or frame.SetPoint
    if fn then fn(frame, ...) end
end

local PIN_POINT_FRAC = {
    TOPLEFT     = { 0,   1   }, TOP    = { 0.5, 1   }, TOPRIGHT    = { 1, 1   },
    LEFT        = { 0,   0.5 }, CENTER = { 0.5, 0.5 }, RIGHT       = { 1, 0.5 },
    BOTTOMLEFT  = { 0,   0   }, BOTTOM = { 0.5, 0   }, BOTTOMRIGHT = { 1, 0   },
}

local function ReadGeom(value)
    if issecretvalue and issecretvalue(value) then return nil end -- @secret-policy: reject-secret-value (geometry read degrades to nil)
    if type(value) ~= "number" then return nil end
    return value
end

function Helpers.PinFrameToTargetAbsolute(frame, sourcePoint, target, targetPoint, offsetX, offsetY)
    if not frame or not target then return false end
    local frac = PIN_POINT_FRAC[targetPoint] or PIN_POINT_FRAC.CENTER
    local srcPt = PIN_POINT_FRAC[sourcePoint] and sourcePoint or "CENTER"

    local tL = ReadGeom(target:GetLeft())
    local tR = ReadGeom(target:GetRight())
    local tT = ReadGeom(target:GetTop())
    local tB = ReadGeom(target:GetBottom())
    if not (tL and tR and tT and tB) then return false end

    local tS = ReadGeom(target:GetEffectiveScale())
    if not tS or tS == 0 then return false end
    local uiS = UIParent and ReadGeom(UIParent:GetEffectiveScale())
    if not uiS or uiS == 0 then return false end
    local k = tS / uiS

    tL, tR, tB, tT = tL * k, tR * k, tB * k, tT * k
    local px = tL + (tR - tL) * frac[1] + (offsetX or 0)
    local py = tB + (tT - tB) * frac[2] + (offsetY or 0)

    if frame.GetNumPoints and frame:GetNumPoints() == 1 and frame.GetPoint then
        local ok2, p, rel, relP, cx, cy = pcall(frame.GetPoint, frame, 1)
        if ok2 and p == srcPt and rel == UIParent and relP == "BOTTOMLEFT" then
            local nx, ny = ReadGeom(cx), ReadGeom(cy)
            if nx and ny and math.abs(nx - px) <= 0.5 and math.abs(ny - py) <= 0.5 then
                return true, px, py
            end
        end
    end

    Helpers.BaseClearAllPoints(frame)
    Helpers.BaseSetPoint(frame, srcPt, UIParent, "BOTTOMLEFT", px, py)
    return true, px, py
end

function Helpers.FrameIsProtected(frame)
    if not frame or not frame.IsProtected then return false end
    local ok, protected = pcall(frame.IsProtected, frame)
    if not ok then return false end
    if issecretvalue and issecretvalue(protected) then return false end -- @secret-policy: reject-secret-value (fail-open: absolute-pin only for KNOWN-protected)
    return protected == true
end

function Helpers.FrameIsAnchoringRestricted(frame)
    if not frame or not frame.IsAnchoringRestricted then return false end
    local ok, restricted = pcall(frame.IsAnchoringRestricted, frame)
    if not ok then return false end
    if issecretvalue and issecretvalue(restricted) then return false end -- @secret-policy: reject-secret-value (fail-open: absolute-pin only for KNOWN-restricted)
    return restricted == true
end

function Helpers.FrameMutationRestricted(frame)
    if not frame then return false end
    if frame.IsProtected then
        local ok, answer = pcall(frame.IsProtected, frame)
        if not ok then return true end
        if issecretvalue and issecretvalue(answer) then return true end -- @secret-policy: report-secret-detected (fail-closed: unprovable = restricted)
        if answer then return true end
    end
    if frame.IsAnchoringRestricted then
        local ok, answer = pcall(frame.IsAnchoringRestricted, frame)
        if not ok then return true end
        if issecretvalue and issecretvalue(answer) then return true end -- @secret-policy: report-secret-detected (fail-closed: unprovable = restricted)
        if answer then return true end
    end
    return false
end

local function ProbeIsShown(frame)
    return frame.IsShown
end
local function ProbeGetAlpha(frame)
    return frame.GetAlpha
end

function Helpers.FrameVisibleSecure(frame, alphaThreshold)
    if issecretvalue and issecretvalue(frame) then return nil end -- @secret-policy: defer-until-readable
    if not frame then return false end
    local okShownProbe, isShownM = pcall(ProbeIsShown, frame)
    if not okShownProbe then return nil end
    if issecretvalue and issecretvalue(isShownM) then return nil end -- @secret-policy: defer-until-readable
    if not isShownM then return false end
    local ok, shown = pcall(isShownM, frame)
    if not ok then return nil end
    if issecretvalue and issecretvalue(shown) then return nil end -- @secret-policy: defer-until-readable
    if not shown then return false end
    local okAlphaProbe, getAlphaM = pcall(ProbeGetAlpha, frame)
    if not okAlphaProbe then return nil end
    if issecretvalue and issecretvalue(getAlphaM) then return nil end -- @secret-policy: defer-until-readable
    if not getAlphaM then return true end
    local okAlpha, alpha = pcall(getAlphaM, frame)
    if not okAlpha then return nil end
    if issecretvalue and issecretvalue(alpha) then return nil end -- @secret-policy: defer-until-readable
    if type(alpha) == "number" and alpha < (alphaThreshold or 0.01) then
        return false
    end
    return true
end

function Helpers.SafeCompare(a, b)
    if issecretvalue and (issecretvalue(a) or issecretvalue(b)) then
        return nil
    end
    return a == b
end

function Helpers.SafeToNumber(value, fallback)
    if issecretvalue and issecretvalue(value) then
        return fallback or 0
    end
    local num = tonumber(value)
    if num then
        return num
    end
    return fallback or 0
end

function Helpers.SafeNumberOrNil(value)
    if issecretvalue and issecretvalue(value) then
        return nil -- @secret-policy: reject-to-nil — nil IS the reject signal; callers' nil guards defer/skip
    end
    return tonumber(value)
end

function Helpers.SafeToString(value, fallback)
    fallback = fallback or ""
    if issecretvalue and issecretvalue(value) then
        return fallback
    end
    local str = tostring(value)
    if str then
        return str
    end
    return fallback
end

local function FormatKeybind(keybind)
    if not keybind then return nil end

    local upper = keybind:upper()

    upper = upper:gsub(" ", "")

    upper = upper:gsub("MOUSEWHEELUP", "WU")
    upper = upper:gsub("MOUSEWHEELDOWN", "WD")
    upper = upper:gsub("MIDDLEMOUSE", "B3")
    upper = upper:gsub("MIDDLEBUTTON", "B3")
    upper = upper:gsub("BUTTON(%d+)", "B%1")

    upper = upper:gsub("SHIFT%-", "S")
    upper = upper:gsub("CTRL%-", "C")
    upper = upper:gsub("ALT%-", "A")
    upper = upper:gsub("^S%-(.+)", "S%1")
    upper = upper:gsub("^C%-(.+)", "C%1")
    upper = upper:gsub("^A%-(.+)", "A%1")

    upper = upper:gsub("NUMPADPLUS", "N+")
    upper = upper:gsub("NUMPADMINUS", "N-")
    upper = upper:gsub("NUMPADMULTIPLY", "N*")
    upper = upper:gsub("NUMPADDIVIDE", "N/")
    upper = upper:gsub("NUMPADPERIOD", "N.")
    upper = upper:gsub("NUMPADENTER", "NE")

    upper = upper:gsub("NUMPAD", "N")
    upper = upper:gsub("CAPSLOCK", "CAP")
    upper = upper:gsub("DELETE", "DEL")
    upper = upper:gsub("ESCAPE", "ESC")
    upper = upper:gsub("BACKSPACE", "BS")
    upper = upper:gsub("SPACE", "SP")
    upper = upper:gsub("INSERT", "INS")
    upper = upper:gsub("PAGEUP", "PU")
    upper = upper:gsub("PAGEDOWN", "PD")
    upper = upper:gsub("HOME", "HM")
    upper = upper:gsub("END", "ED")
    upper = upper:gsub("PRINTSCREEN", "PS")
    upper = upper:gsub("SCROLLLOCK", "SL")
    upper = upper:gsub("PAUSE", "PA")
    upper = upper:gsub("TILDE", "`")
    upper = upper:gsub("GRAVE", "`")

    upper = upper:gsub("UPARROW", "UP")
    upper = upper:gsub("DOWNARROW", "DN")
    upper = upper:gsub("LEFTARROW", "LF")
    upper = upper:gsub("RIGHTARROW", "RT")

    upper = upper:gsub("SEMICOLON", ";")
    upper = upper:gsub("APOSTROPHE", "'")
    upper = upper:gsub("LEFTBRACKET", "[")
    upper = upper:gsub("RIGHTBRACKET", "]")
    upper = upper:gsub("BACKSLASH", "\\")
    upper = upper:gsub("MINUS", "-")
    upper = upper:gsub("EQUALS", "=")
    upper = upper:gsub("COMMA", ",")
    upper = upper:gsub("^PERIOD$", ".")
    upper = upper:gsub("SLASH", "/")

    if #upper > 4 then
        upper = upper:sub(1, 4)
    end

    return upper
end

ns.FormatKeybind = FormatKeybind

local function DecodePotentialSecretBoolean(value)
    if issecretvalue and issecretvalue(value) then return nil end -- @secret-policy: reject-secret-value (nil = "can't tell")
    if value == nil then return nil end
    if type(value) == "boolean" then return value end
    return nil
end

local function UnitTokenMatches(unitToken, targetUnit)
    if not UnitIsUnit then return false end
    local ok, matched = pcall(UnitIsUnit, unitToken, targetUnit)
    if not ok then return false end
    return DecodePotentialSecretBoolean(matched) == true
end

local function GUIDMatchesUnit(sourceGUID, unit)
    if issecretvalue and issecretvalue(sourceGUID) then return false end -- @secret-policy: reject-secret-value (unproven match)
    if type(sourceGUID) ~= "string" then return false end
    if not UnitGUID then return false end
    local unitGUID = UnitGUID(unit)
    if issecretvalue and issecretvalue(unitGUID) then return false end -- @secret-policy: reject-secret-value (unproven match)
    return type(unitGUID) == "string" and sourceGUID == unitGUID
end

function Helpers.IsAuraOwnedByPlayerOrPet(auraData, strictSource)
    if not auraData then return false end

    local okFlag, ownedFlag = pcall(function() return auraData.isFromPlayerOrPlayerPet end)
    if okFlag and DecodePotentialSecretBoolean(ownedFlag) == false then
        return false
    end

    local okUnit, sourceUnit = pcall(function() return auraData.sourceUnit end)
    if okUnit then
        if UnitTokenMatches(sourceUnit, "player") then return true end
        if UnitTokenMatches(sourceUnit, "pet") then return true end
        if UnitTokenMatches(sourceUnit, "vehicle") then return true end
    end

    local okGUID, sourceGUID = pcall(function() return auraData.sourceGUID end)
    if okGUID then
        if GUIDMatchesUnit(sourceGUID, "player") then return true end
        if GUIDMatchesUnit(sourceGUID, "pet") then return true end
        if GUIDMatchesUnit(sourceGUID, "vehicle") then return true end
    end

    return false
end

function Helpers.GetCore()
    return (_G.QUI and _G.QUI.QUICore) or ns.Addon
end

function Helpers.GetProfile()
    local core = Helpers.GetCore()
    if core and core.db and core.db.profile then
        return core.db.profile
    end
    return nil
end

function Helpers.CreateDBGetter(moduleName)
    return function()
        local profile = Helpers.GetProfile()
        if profile then
            return profile[moduleName]
        end
        return nil
    end
end

function Helpers.GetModuleDB(moduleName)
    local profile = Helpers.GetProfile()
    if profile then
        return profile[moduleName]
    end
    return nil
end

function Helpers.GetConsumableMacrosDB()
    local core = Helpers.GetCore()
    if not core or not core.db then return nil end
    local charT = core.db.char and core.db.char.consumableMacros
    if charT and charT.characterSpecific then
        return charT
    end
    local profile = core.db.profile
    return profile and profile.general and profile.general.consumableMacros
end

function Helpers.GetCharConsumableMacrosDB()
    local core = Helpers.GetCore()
    return core and core.db and core.db.char and core.db.char.consumableMacros
end

function Helpers.DeepCopy(value, seen)
    if type(value) ~= "table" then
        return value
    end
    seen = seen or {}
    if seen[value] then
        return seen[value]
    end
    local copy = {}
    seen[value] = copy
    for k, v in pairs(value) do
        copy[Helpers.DeepCopy(k, seen)] = Helpers.DeepCopy(v, seen)
    end
    return copy
end

function Helpers.ShallowCopy(value)
    if type(value) ~= "table" then
        return value
    end
    local copy = {}
    for k, v in pairs(value) do
        copy[k] = v
    end
    return copy
end

local function DeepCopyDefaults(src)
    local copy = {}
    for k, v in pairs(src) do
        copy[k] = type(v) == "table" and DeepCopyDefaults(v) or v
    end
    return copy
end

local function MergeMissingDefaults(target, defaults)
    local hadStructuralMismatch = false
    if type(target) ~= "table" or type(defaults) ~= "table" then
        return hadStructuralMismatch
    end

    for k, v in pairs(defaults) do
        local cur = target[k]
        if cur == nil then
            target[k] = type(v) == "table" and DeepCopyDefaults(v) or v
        elseif type(v) == "table" then
            if type(cur) ~= "table" then
                hadStructuralMismatch = true
            else
                if MergeMissingDefaults(cur, v) then
                    hadStructuralMismatch = true
                end
            end
        end
    end

    return hadStructuralMismatch
end

function Helpers.GetModuleSettings(moduleName, defaults)
    defaults = defaults or {}
    local profile = Helpers.GetProfile()
    if profile then
        if not profile[moduleName] then
            profile[moduleName] = DeepCopyDefaults(defaults)
        else
            local settings = profile[moduleName]
            if MergeMissingDefaults(settings, defaults) then
                wipe(settings)
                MergeMissingDefaults(settings, defaults)
            end
        end
        return profile[moduleName]
    end
    return defaults
end

local function NormalizeNCDMCustomEntries(data)
    if type(data) ~= "table" then
        data = {}
    end

    if data.enabled == nil then
        data.enabled = true
    end
    if data.placement ~= "before" and data.placement ~= "after" then
        data.placement = "after"
    end
    if type(data.entries) ~= "table" then
        data.entries = {}
    end

    for i = #data.entries, 1, -1 do
        local entry = data.entries[i]
        if type(entry) ~= "table" then
            table.remove(data.entries, i)
        else
            if entry.enabled == nil then
                entry.enabled = true
            end
            if entry.position ~= nil then
                local pos = tonumber(entry.position)
                if pos and pos >= 1 then
                    entry.position = math.max(1, math.floor(pos))
                else
                    entry.position = nil
                end
            end
        end
    end

    return data
end

local function CloneNCDMCustomEntries(source)
    local cloned = {
        enabled = true,
        placement = "after",
        entries = {},
    }

    if type(source) ~= "table" then
        return cloned
    end

    if source.enabled ~= nil then
        cloned.enabled = source.enabled
    end
    if source.placement then
        cloned.placement = source.placement
    end

    if type(source.entries) == "table" then
        for _, entry in ipairs(source.entries) do
            if type(entry) == "table" then
                local copiedEntry = {}
                for k, v in pairs(entry) do
                    if type(v) == "table" then
                        local sub = {}
                        for sk, sv in pairs(v) do
                            sub[sk] = sv
                        end
                        copiedEntry[k] = sub
                    else
                        copiedEntry[k] = v
                    end
                end
                table.insert(cloned.entries, copiedEntry)
            end
        end
    end

    return NormalizeNCDMCustomEntries(cloned)
end

local function CreateNCDMSpecTemplate(sharedData)
    local enabled = true
    if type(sharedData) == "table" and sharedData.enabled ~= nil then
        enabled = sharedData.enabled
    end
    return NormalizeNCDMCustomEntries({
        enabled = enabled,
        placement = (type(sharedData) == "table" and sharedData.placement) or "after",
        entries = {},
    })
end

function Helpers.GetCurrentSpecID()
    local specIndex = GetSpecialization and GetSpecialization()
    if not specIndex then
        return nil
    end
    local specID = GetSpecializationInfo and GetSpecializationInfo(specIndex)
    if type(specID) ~= "number" then
        return nil
    end
    return specID
end

function Helpers.GetNCDMCustomEntries(trackerKey)
    if type(trackerKey) ~= "string" or trackerKey == "" then
        return nil
    end

    local core = Helpers.GetCore()
    if not (core and core.db and core.db.char and core.db.profile) then
        return nil
    end

    local charDB = core.db.char
    local profileDB = core.db.profile

    if type(charDB.ncdm) ~= "table" then
        charDB.ncdm = {}
    end
    if type(charDB.ncdm[trackerKey]) ~= "table" then
        charDB.ncdm[trackerKey] = {}
    end
    local trackerCharDB = charDB.ncdm[trackerKey]

    trackerCharDB.customEntries = NormalizeNCDMCustomEntries(trackerCharDB.customEntries)

    if type(trackerCharDB.customEntriesByProfile) ~= "table" then
        trackerCharDB.customEntriesByProfile = {}
    end

    local profileName = (core.db.GetCurrentProfile and core.db:GetCurrentProfile()) or "Default"
    local profileBucket = trackerCharDB.customEntriesByProfile[profileName]
    if type(profileBucket) ~= "table" then
        profileBucket = {}
        trackerCharDB.customEntriesByProfile[profileName] = profileBucket
    end

    if type(profileBucket.shared) ~= "table" then
        local legacyProfileData = profileDB and profileDB.ncdm and profileDB.ncdm[trackerKey] and profileDB.ncdm[trackerKey].customEntries
        local hasLegacyProfileData = type(legacyProfileData) == "table"
            and (
                (type(legacyProfileData.entries) == "table" and #legacyProfileData.entries > 0)
                or legacyProfileData.enabled ~= nil
                or legacyProfileData.placement ~= nil
            )
        if hasLegacyProfileData then
            profileBucket.shared = CloneNCDMCustomEntries(legacyProfileData)
        else
            profileBucket.shared = CloneNCDMCustomEntries(trackerCharDB.customEntries)
        end
    end
    profileBucket.shared = NormalizeNCDMCustomEntries(profileBucket.shared)

    local useSpecSpecific = profileDB and profileDB.ncdm and profileDB.ncdm.customEntriesSpecSpecific == true
    if not useSpecSpecific then
        return profileBucket.shared
    end

    if type(profileBucket.bySpec) ~= "table" then
        profileBucket.bySpec = {}
    end

    local specID = Helpers.GetCurrentSpecID()
    if not specID then
        return profileBucket.shared
    end

    local specKey = tostring(specID)
    if type(profileBucket.bySpec[specKey]) ~= "table" then
        profileBucket.bySpec[specKey] = CreateNCDMSpecTemplate(profileBucket.shared)
    end
    profileBucket.bySpec[specKey] = NormalizeNCDMCustomEntries(profileBucket.bySpec[specKey])
    return profileBucket.bySpec[specKey]
end

Helpers.HUD_MIN_WIDTH_DEFAULT = 200
Helpers.HUD_MIN_WIDTH_MIN = 100
Helpers.HUD_MIN_WIDTH_MAX = 500

function Helpers.ClampHUDMinWidth(width)
    local rounded = math.floor((tonumber(width) or Helpers.HUD_MIN_WIDTH_DEFAULT) + 0.5)
    if rounded < Helpers.HUD_MIN_WIDTH_MIN then
        return Helpers.HUD_MIN_WIDTH_MIN
    end
    if rounded > Helpers.HUD_MIN_WIDTH_MAX then
        return Helpers.HUD_MIN_WIDTH_MAX
    end
    return rounded
end

function Helpers.ParseHUDMinWidth(frameAnchoring)
    if type(frameAnchoring) ~= "table" then
        return false, Helpers.HUD_MIN_WIDTH_DEFAULT
    end

    local cfg = frameAnchoring.hudMinWidth
    local enabled, width

    if type(cfg) == "table" then
        enabled = cfg.enabled == true
        width = cfg.width
    else
        local legacyEnabled = frameAnchoring.hudMinWidthEnabled
        if legacyEnabled == nil then
            enabled = tonumber(cfg) ~= nil
        else
            enabled = legacyEnabled == true
        end
        width = cfg
    end

    return enabled == true, Helpers.ClampHUDMinWidth(width)
end

function Helpers.GetHUDMinWidthSettingsFromProfile(profile)
    local frameAnchoring = profile and profile.frameAnchoring
    return Helpers.ParseHUDMinWidth(frameAnchoring)
end

function Helpers.MigrateHUDMinWidthSettings(frameAnchoring)
    if type(frameAnchoring) ~= "table" then
        return nil
    end

    local cfg = frameAnchoring.hudMinWidth
    if type(cfg) == "table" then
        cfg.enabled = (cfg.enabled == true)
        cfg.width = Helpers.ClampHUDMinWidth(cfg.width)
        frameAnchoring.hudMinWidthEnabled = nil
        return cfg
    end

    local enabled, width = Helpers.ParseHUDMinWidth(frameAnchoring)
    frameAnchoring.hudMinWidth = { enabled = enabled, width = width }
    frameAnchoring.hudMinWidthEnabled = nil
    return frameAnchoring.hudMinWidth
end

function Helpers.IsHUDAnchoredToCDM(profile)
    if type(profile) ~= "table" then
        return false
    end

    local unitframes = profile.unitframes
    if unitframes then
        local playerAnchor = unitframes.player and unitframes.player.anchorTo
        local targetAnchor = unitframes.target and unitframes.target.anchorTo
        if playerAnchor == "essential" or playerAnchor == "utility" then
            return true
        end
        if targetAnchor == "essential" or targetAnchor == "utility" then
            return true
        end
    end

    local frameAnchoring = profile.frameAnchoring
    if frameAnchoring then
        for _, key in ipairs({"playerFrame", "targetFrame"}) do
            local entry = frameAnchoring[key]
            if type(entry) == "table" then
                local p = entry.parent
                if p == "cdmEssential" or p == "cdmUtility" or p == "essential" or p == "utility" then
                    return true
                end
            end
        end
    end

    return false
end

function Helpers.IsLayoutModeActive()
    return ns.QUI_LayoutMode and ns.QUI_LayoutMode.isActive or false
end

function Helpers.IsEditModeActive()
    if EditModeManagerFrame then
        if type(EditModeManagerFrame.IsEditModeActive) == "function" then
            return EditModeManagerFrame:IsEditModeActive()
        end
        return not not EditModeManagerFrame.editModeActive
    end
    return false
end

local DEFAULT_FONT = "Fonts\\FRIZQT__.TTF"
local DEFAULT_FONT_NAME = "Friz Quadrata TT"
local DEFAULT_OUTLINE = "OUTLINE"

function Helpers.GetGeneralFont()
    local profile = Helpers.GetProfile()
    if profile and profile.general then
        local fontName = profile.general.font or DEFAULT_FONT_NAME
        if LSM then
            return LSM:Fetch("font", fontName) or DEFAULT_FONT
        end
    end
    return DEFAULT_FONT
end

function Helpers.GetGeneralFontOutline()
    local profile = Helpers.GetProfile()
    if profile and profile.general then
        return profile.general.fontOutline or DEFAULT_OUTLINE
    end
    return DEFAULT_OUTLINE
end

function Helpers.GetGeneralFontSettings()
    return Helpers.GetGeneralFont(), Helpers.GetGeneralFontOutline()
end

local FONT_ALPHABET_FILES = {
    { name = "roman",              cjk = false },
    { name = "korean",             cjk = "Fonts\\2002.TTF" },
    { name = "simplifiedchinese",  cjk = "Fonts\\ARKai_T.ttf" },
    { name = "traditionalchinese", cjk = "Fonts\\blei00d.TTF" },
    { name = "russian",            cjk = false },
}

local function AlphabetValue(name)
    local enum = _G.Enum and _G.Enum.FontAlphabet
    if type(enum) == "table" then
        for k, v in pairs(enum) do
            if type(k) == "string" and k:lower() == name then return v end
        end
    end
    return name
end

local fontFamilyCache = {}

function Helpers.GetFontFamilyObject(fontPath, size, flags)
    if type(fontPath) ~= "string" or type(size) ~= "number" or size <= 0 then
        return nil
    end
    flags = flags or ""
    if not _G.CreateFontFamily then return nil end

    local key = fontPath .. "|" .. size .. "|" .. flags
    local cached = fontFamilyCache[key]
    if cached then return cached end

    local members = {}
    for i = 1, #FONT_ALPHABET_FILES do
        local entry = FONT_ALPHABET_FILES[i]
        members[i] = {
            alphabet = AlphabetValue(entry.name),
            file = entry.cjk or fontPath,
            height = size,
            flags = flags,
        }
    end

    local familyName = "QUIFB_" .. key:gsub("[^%w]", "_")
    local ok, family = pcall(_G.CreateFontFamily, familyName, members)
    if not ok or not family then
        return nil
    end
    fontFamilyCache[key] = family
    return family
end

function Helpers.ApplyFontWithFallback(fontString, fontNameOrPath, size, flags)
    if not fontString or not fontString.SetFont then return end
    flags = flags or ""

    local fontPath = fontNameOrPath
    if LSM and type(fontNameOrPath) == "string" then
        local fetched = LSM:Fetch("font", fontNameOrPath, true)
        if fetched then fontPath = fetched end
    end
    if type(fontPath) ~= "string" then fontPath = DEFAULT_FONT end

    local family
    if type(size) == "number" and size > 0 then
        family = Helpers.GetFontFamilyObject(fontPath, size, flags)
    end

    if family and fontString.SetFontObject then
        local jh = fontString.GetJustifyH and fontString:GetJustifyH()
        local jv = fontString.GetJustifyV and fontString:GetJustifyV()
        local r, g, b, a
        if fontString.GetTextColor then r, g, b, a = fontString:GetTextColor() end

        if pcall(fontString.SetFontObject, fontString, family) then
            if jh and fontString.SetJustifyH then fontString:SetJustifyH(jh) end
            if jv and fontString.SetJustifyV then fontString:SetJustifyV(jv) end
            if r and fontString.SetTextColor then fontString:SetTextColor(r, g, b, a) end
            return
        end
    end

    fontString:SetFont(fontPath, size or 12, flags)
end

function Helpers.GetLocaleGlyphFallback()
    local loc = GetLocale and GetLocale() or "enUS"
    if loc == "koKR" then return "Fonts\\2002.TTF"
    elseif loc == "zhCN" then return "Fonts\\ARKai_T.ttf"
    elseif loc == "zhTW" then return "Fonts\\blei00d.TTF" end
    return nil
end

function Helpers.GetSkinColors()
    local QUI = _G.QUI
    local sr, sg, sb, sa = 0.376, 0.647, 0.980, 1
    local bgr, bgg, bgb, bga = 0.05, 0.05, 0.05, 0.95

    if QUI and QUI.GetSkinColor then
        sr, sg, sb, sa = QUI:GetSkinColor()
    end
    if QUI and QUI.GetSkinBgColor then
        bgr, bgg, bgb, bga = QUI:GetSkinBgColor()
    end

    return sr, sg, sb, sa, bgr, bgg, bgb, bga
end

function Helpers.GetSkinAccentColor()
    local sr, sg, sb, sa = Helpers.GetSkinColors()
    return sr, sg, sb, sa
end

local function GetBorderKeys(prefix)
    if not prefix or prefix == "" then
        return {
            source = "borderColorSource",
            color  = "borderColor",
            hide   = "hideBorder",
        }
    end
    return {
        source = prefix .. "BorderColorSource",
        color  = prefix .. "BorderColor",
        hide   = prefix .. "HideBorder",
    }
end

Helpers.GetBorderKeys = GetBorderKeys

function Helpers.GetSkinBorderColor(moduleSettings, prefix)
    local profile = Helpers.GetProfile()
    local general = profile and profile.general

    local fallbackR, fallbackG, fallbackB, fallbackA = Helpers.GetSkinAccentColor()
    local r, g, b, a = fallbackR, fallbackG, fallbackB, fallbackA

    if general then
        local source = general.skinBorderColorSource
            or (general.skinBorderUseClassColor and "class")
            or "theme"
        if source == "class" then
            r, g, b = Helpers.GetPlayerClassColor()
            a = 1
        elseif source == "custom" and type(general.skinBorderColor) == "table" then
            r = general.skinBorderColor[1] or r
            g = general.skinBorderColor[2] or g
            b = general.skinBorderColor[3] or b
            a = general.skinBorderColor[4] or a
        end

        if general.hideSkinBorders then
            a = 0
        end
    end

    if type(moduleSettings) == "table" then
        local keys = GetBorderKeys(type(prefix) == "string" and prefix or "")

        local source = moduleSettings[keys.source]
        if source == nil then
            if moduleSettings.useClassColorBorder or moduleSettings.borderUseClassColor then
                source = "class"
            elseif moduleSettings.useAccentColorBorder then
                source = "theme"
            end
        end

        if source == "theme" then
            r, g, b = Helpers.GetSkinAccentColor()
            a = 1
        elseif source == "class" then
            r, g, b = Helpers.GetPlayerClassColor()
            a = 1
        elseif source == "custom" and type(moduleSettings[keys.color]) == "table" then
            local mc = moduleSettings[keys.color]
            r, g, b, a = mc[1] or r, mc[2] or g, mc[3] or b, mc[4] or a
        end

        if moduleSettings[keys.hide] then a = 0 end
    end

    return r, g, b, a
end

function Helpers.GetSkinBarColor(moduleSettings, prefix)
    local fallbackR, fallbackG, fallbackB, fallbackA = Helpers.GetSkinBorderColor(moduleSettings, prefix)
    local r, g, b, a = fallbackR, fallbackG, fallbackB, fallbackA

    if type(moduleSettings) == "table" then
        local keyPrefix = type(prefix) == "string" and prefix or ""
        local useClassKey = keyPrefix ~= "" and (keyPrefix .. "BarUseClassColor") or "barUseClassColor"
        local colorKey = keyPrefix ~= "" and (keyPrefix .. "BarColor") or "barColor"

        if moduleSettings[useClassKey] then
            r, g, b = Helpers.GetPlayerClassColor()
            a = 1
        elseif type(moduleSettings[colorKey]) == "table" then
            local moduleColor = moduleSettings[colorKey]
            r = moduleColor[1] or r
            g = moduleColor[2] or g
            b = moduleColor[3] or b
            a = moduleColor[4] or a
        end
    end

    return r, g, b, a
end

function Helpers.GetSkinBgColor()
    local _, _, _, _, bgr, bgg, bgb, bga = Helpers.GetSkinColors()
    return bgr, bgg, bgb, bga
end

function Helpers.GetSkinBgColorWithOverride(moduleSettings, prefix)
    local profile = Helpers.GetProfile()
    local general = profile and profile.general

    local fallbackR, fallbackG, fallbackB, fallbackA = Helpers.GetSkinBgColor()
    local r, g, b, a = fallbackR, fallbackG, fallbackB, fallbackA

    if type(moduleSettings) == "table" then
        local keyPrefix = type(prefix) == "string" and prefix or ""
        local overrideKey = keyPrefix ~= "" and (keyPrefix .. "BgOverride") or "bgOverride"
        local hideKey = keyPrefix ~= "" and (keyPrefix .. "HideBackground") or "hideBackground"
        local colorKey = keyPrefix ~= "" and (keyPrefix .. "BackgroundColor") or "backgroundColor"

        if moduleSettings[overrideKey] then
            if type(moduleSettings[colorKey]) == "table" then
                local moduleColor = moduleSettings[colorKey]
                r = moduleColor[1] or r
                g = moduleColor[2] or g
                b = moduleColor[3] or b
                a = moduleColor[4] or a
            end

            if moduleSettings[hideKey] then
                a = 0
            end
        end
    end

    return r, g, b, a
end

Helpers.CHROME = {
    BORDER_PX       = 1,
    BG_FALLBACK     = { 0.05, 0.05, 0.05, 0.95 },
    BORDER_FALLBACK = { 0, 0, 0, 1 },
    BUTTON_BOOST    = 0.07,
    SCROLLROW_BOOST = 0.03,
    DEPTH = {
        PANEL    = { boost = 0.00, alpha = 0.95 },
        SUBPANEL = { boost = 0.04, alpha = 0.85 },
        ROW      = { boost = 0.07, alpha = 0.75 },
    },
}

function Helpers.GetClassColorTable(classToken)
    if not classToken then return nil end
    return (CUSTOM_CLASS_COLORS and CUSTOM_CLASS_COLORS[classToken])
        or RAID_CLASS_COLORS[classToken]
end

function Helpers.GetClassColor(classToken)
    local classColor = Helpers.GetClassColorTable(classToken)
    if classColor then
        return classColor.r, classColor.g, classColor.b
    end
    return 1, 1, 1
end

function Helpers.GetPlayerClassColor()
    local _, classToken = UnitClass("player")
    return Helpers.GetClassColor(classToken)
end

function Helpers.GetUnitClassColor(unit)
    unit = unit or "player"
    if not UnitExists(unit) then
        return 0.5, 0.5, 0.5, 1
    end

    if UnitIsPlayer(unit) then
        local _, class = UnitClass(unit)
        -- @secret-policy: collapse-only — display fallback color, no state
        local classIsSecret = issecretvalue and issecretvalue(class)
        if not classIsSecret and type(class) == "string" then
            local color = Helpers.GetClassColorTable(class)
            if color then
                return color.r, color.g, color.b, 1
            end
        end
    end

    local reaction = Helpers.SafeToNumber(UnitReaction(unit, "player"), nil)
    if reaction and reaction > 0 then
        if reaction >= 5 then
            return 0.2, 0.8, 0.2, 1
        elseif reaction == 4 then
            return 1, 1, 0.2, 1
        else
            return 0.8, 0.2, 0.2, 1
        end
    end

    return 0.5, 0.5, 0.5, 1
end

function Helpers.GetItemQualityColor(quality)
    if not quality or quality < 0 then return 1, 1, 1 end
    local r, g, b = C_Item.GetItemQualityColor(quality)
    if r then
        return r, g, b
    end
    return 1, 1, 1
end

function Helpers.CreateOnUpdateThrottle(interval, callback)
    interval = tonumber(interval) or 0
    local elapsedSinceLast = 0
    return function(self, elapsed, ...)
        elapsedSinceLast = elapsedSinceLast + (elapsed or 0)
        if elapsedSinceLast < interval then
            return
        end
        local accumulated = elapsedSinceLast
        elapsedSinceLast = 0
        callback(self, accumulated, ...)
    end
end

function Helpers.CreateTimeThrottle(interval, callback)
    interval = tonumber(interval) or 0
    local lastRun = 0
    return function(...)
        local now = GetTime()
        if (now - lastRun) < interval then
            return
        end
        lastRun = now
        return callback(...)
    end
end

function Helpers.Clamp(value, minVal, maxVal)
    if value < minVal then return minVal end
    if value > maxVal then return maxVal end
    return value
end

function Helpers.FormatMMSS(seconds, padMinutes)
    if Helpers.IsSecretValue(seconds) then
        if C_StringUtil and C_StringUtil.TruncateWhenZero and C_StringUtil.WrapString then
            return C_StringUtil.WrapString(C_StringUtil.TruncateWhenZero(seconds), "", "s")
        end
        return "" -- @secret-policy: empty-text-degrade
    end
    local total = math.floor(tonumber(seconds) or 0)
    local negative = total < 0
    if negative then total = -total end
    local str = string.format(padMinutes and "%02d:%02d" or "%d:%02d",
        math.floor(total / 60), total % 60)
    return negative and ("-" .. str) or str
end

local SOAR_SPELL_ID = 381322

function Helpers.IsPlayerPassenger()
    if not (UnitInVehicle and UnitInVehicle("player")) then
        return false
    end

    if UnitControllingVehicle then
        local ok, controlling = pcall(UnitControllingVehicle, "player")
        if ok then
            return not controlling
        end
    end

    if UnitHasVehicleUI then
        local ok, hasVehicleUI = pcall(UnitHasVehicleUI, "player")
        if ok then
            return not hasVehicleUI
        end
    end

    return false
end

function Helpers.IsPlayerMounted()
    if Helpers.IsPlayerPassenger() then return false end
    if IsMounted and IsMounted() then return true end
    if GetShapeshiftFormID and GetShapeshiftFormID() == 27 then return true end
    if C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
        local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, SOAR_SPELL_ID)
        if ok then
            if issecretvalue and issecretvalue(aura) then
                return false -- @secret-policy: reject-secret-value (Soar unprovable = not mounted)
            end
            if aura then return true end
        end
    end
    return false
end

function Helpers.IsPlayerFlying()
    if Helpers.IsPlayerPassenger() then return false end
    if IsFlying then return IsFlying() end
    return false
end

function Helpers.IsPlayerSkyriding()
    if Helpers.IsPlayerPassenger() then return false end
    if not (C_PlayerInfo and C_PlayerInfo.GetGlidingInfo) then return false end
    local ok, gliding = pcall(C_PlayerInfo.GetGlidingInfo)
    return ok and gliding
end

function Helpers.IsPlayerInVehicle()
    if UnitInVehicle and UnitInVehicle("player") then return true end
    if UnitHasVehicleUI and UnitHasVehicleUI("player") then return true end
    if HasOverrideActionBar and HasOverrideActionBar() then return true end
    return false
end

function Helpers.IsPlayerInDungeonOrRaid()
    local _, instanceType = GetInstanceInfo()
    return instanceType == "party" or instanceType == "raid"
end

function Helpers.CreateSkinColorGetter(prefix, settingsPath)
    settingsPath = settingsPath or "general"
    return function()
        local profile = Helpers.GetProfile()
        local settings = profile and profile[settingsPath]
        local sr, sg, sb, sa = Helpers.GetSkinBorderColor(settings, prefix)
        local bgr, bgg, bgb, bga = Helpers.GetSkinBgColorWithOverride(settings, prefix)
        return sr, sg, sb, sa, bgr, bgg, bgb, bga
    end
end

ns.Utils = ns.Utils or {}

function ns.Utils.IsInInstancedContent()
    local inInstance, instanceType = IsInInstance()
    return inInstance and (instanceType == "party" or instanceType == "raid")
end

 function Helpers.TruncateUTF8(text, maxLength)
     if Helpers.IsSecretValue(text) then
         return text
     end
     if text == nil then return "" end
     if type(text) ~= "string" then
         return Helpers.SafeToString(text, "")
     end
     if not maxLength or maxLength <= 0 then return text end

     local lenOk, textLen = pcall(function() return #text end)
     if not lenOk then
         return string.format("%." .. maxLength .. "s", text)
     end

     if textLen <= maxLength then
         return text
     end

     local byte = string.byte
     local i = 1
     local c = 0
     while i <= textLen and c < maxLength do
         c = c + 1
         local b = byte(text, i)
         if b < 0x80 then
             i = i + 1
         elseif b < 0xE0 then
             i = i + 2
         elseif b < 0xF0 then
             i = i + 3
         else
             i = i + 4
         end
     end

     local subOk, truncated = pcall(string.sub, text, 1, i - 1)
     if subOk and truncated then
         return truncated
     end

     return string.format("%." .. maxLength .. "s", text)
 end

local UTF8_FOLD = {}
for hi = 0x80, 0x96 do
    UTF8_FOLD["\195" .. string.char(hi)] = "\195" .. string.char(hi + 0x20)
end
for hi = 0x98, 0x9E do
    UTF8_FOLD["\195" .. string.char(hi)] = "\195" .. string.char(hi + 0x20)
end
for hi = 0x90, 0x9F do
    UTF8_FOLD["\208" .. string.char(hi)] = "\208" .. string.char(hi + 0x20)
end
for hi = 0xA0, 0xAF do
    UTF8_FOLD["\208" .. string.char(hi)] = "\209" .. string.char(hi - 0x20)
end
UTF8_FOLD["\208\129"] = "\209\145"
UTF8_FOLD["\197\146"] = "\197\147"

local UTF8_UNFOLD = {}
for upper, lower in pairs(UTF8_FOLD) do UTF8_UNFOLD[lower] = upper end

local UTF8_CASED_PAIR = "[\195\197\208\209][\128-\191]"

function Helpers.FoldUTF8(text)
    if Helpers.IsSecretValue(text) then return text end
    if text == nil then return "" end
    if type(text) ~= "string" then
        text = Helpers.SafeToString(text, "")
    end
    text = string.lower(text)
    if string.find(text, UTF8_CASED_PAIR) then
        text = string.gsub(text, UTF8_CASED_PAIR, UTF8_FOLD)
    end
    return text
end

function Helpers.UpperUTF8(text)
    if Helpers.IsSecretValue(text) then return text end
    if text == nil then return "" end
    if type(text) ~= "string" then
        text = Helpers.SafeToString(text, "")
    end
    text = string.upper(text)
    if string.find(text, UTF8_CASED_PAIR) then
        text = string.gsub(text, UTF8_CASED_PAIR, UTF8_UNFOLD)
    end
    return text
end

function Helpers.CreateStateTable()
    local tbl = setmetatable({}, { __mode = "k" })
    local function get(key)
        local s = tbl[key]
        if not s then s = {}; tbl[key] = s end
        return s
    end
    return tbl, get
end

local _deferredHideHooked = setmetatable({}, { __mode = "k" })

local _combatHideQueue = {}
local _combatHideFrame
local function FlushCombatHideQueue()
    if InCombatLockdown() then return end
    for frame, shouldClearAlpha in pairs(_combatHideQueue) do
        if not (frame.IsForbidden and frame:IsForbidden()) then
            ns.SafeCallMethod("best-effort-style", frame, "Hide")
            if shouldClearAlpha and frame.SetAlpha then frame:SetAlpha(0) end
        end
    end
    wipe(_combatHideQueue)
    _combatHideFrame:UnregisterEvent("PLAYER_REGEN_ENABLED")
end
local function QueueCombatHide(frame, clearAlpha)
    _combatHideQueue[frame] = clearAlpha or false
    if not _combatHideFrame then
        _combatHideFrame = CreateFrame("Frame")
        _combatHideFrame:SetScript("OnEvent", FlushCombatHideQueue)
    end
    _combatHideFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
end

function Helpers.DeferredHideOnShow(frame, opts)
    if not frame or not frame.Show then return end
    if _deferredHideHooked[frame] then return end
    _deferredHideHooked[frame] = true
    local clearAlpha = opts and opts.clearAlpha or false
    local combatCheck = not opts or opts.combatCheck ~= false
    hooksecurefunc(frame, "Show", function(self)
        C_Timer.After(0, function()
            if self.IsForbidden and self:IsForbidden() then return end
            if InCombatLockdown() then
                if combatCheck then return end
                if self.SetAlpha then self:SetAlpha(0) end
                QueueCombatHide(self, clearAlpha)
                return
            end
            ns.SafeCallMethod("best-effort-style", self, "Hide")
            if clearAlpha and self.SetAlpha then self:SetAlpha(0) end
        end)
    end)
end

local _deferredAtlasHooked = setmetatable({}, { __mode = "k" })
function Helpers.DeferredSetAtlasBlock(texture, combatCheck)
    if not texture or not texture.SetAtlas then return end
    if _deferredAtlasHooked[texture] then return end
    _deferredAtlasHooked[texture] = true
    if combatCheck == nil then combatCheck = true end
    hooksecurefunc(texture, "SetAtlas", function(self)
        C_Timer.After(0, function()
            if combatCheck and InCombatLockdown() then return end
            if not self then return end
            if self.SetTexture then self:SetTexture(nil) end
            if self.SetAlpha then self:SetAlpha(0) end
        end)
    end)
end

function Helpers.IsEditModeShown()
    return EditModeManagerFrame and EditModeManagerFrame:IsShown() or false
end

local function CombatProtected(frame)
    if not InCombatLockdown() then return false end
    if not frame.IsProtected then return false end
    local protected = frame:IsProtected()
    if Helpers.IsSecretValue(protected) then return true end -- @secret-policy: report-secret-detected (fail-closed: unprovable = protected)
    return protected == true
end

function Helpers.SafeShow(frame)
    if not frame then return false end
    local shown = frame.IsShown and frame:IsShown()
    if not Helpers.IsSecretValue(shown) and shown then return true end -- @secret-policy: defer-until-readable
    if CombatProtected(frame) then return false end
    return ns.SafeCallMethod("best-effort-style", frame, "Show")
end

function Helpers.SafeHide(frame)
    if not frame then return false end
    local shown = frame.IsShown and frame:IsShown()
    if not Helpers.IsSecretValue(shown) and not shown then return true end -- @secret-policy: defer-until-readable
    if CombatProtected(frame) then return false end
    return ns.SafeCallMethod("best-effort-style", frame, "Hide")
end

function Helpers.ReadSpellCooldown(spellID)
    if C_Spell and C_Spell.GetSpellCooldown then
        local a, b, _, d = C_Spell.GetSpellCooldown(spellID)
        if type(a) == "table" then
            local info = a
            return info.startTime, info.duration, info.modRate, info.isActive, info
        end
        return a, b, d, nil, nil
    end

    return nil, nil, nil, nil, nil
end

function Helpers.IsCooldownActive(start, duration, isActive)
    if type(isActive) == "boolean" then
        return isActive
    end

    if Helpers.IsSecretValue(start) or Helpers.IsSecretValue(duration) then
        return true -- @secret-policy: assume-cooldown-when-unknown
    end

    if not start or not duration then return false end
    if type(start) ~= "number" or type(duration) ~= "number" then return false end
    return duration > 0 and start > 0
end

function Helpers.ApplyCooldownFromStart(cooldownFrame, durationObj, startTime, duration, modRate, reverse)
    if not cooldownFrame then
        return false
    end

    if durationObj and cooldownFrame.SetCooldownFromDurationObject then
        local applied = pcall(cooldownFrame.SetCooldownFromDurationObject, cooldownFrame, durationObj, reverse)
        if applied then
            return true
        end
    end

    if Helpers.IsSecretValue(startTime) or Helpers.IsSecretValue(duration) or Helpers.IsSecretValue(modRate) then
        return false -- @secret-policy: reject-secret-value (numeric SetCooldown path needs readable args; DurationObject sink already tried above)
    end
    if type(startTime) ~= "number" or type(duration) ~= "number" then
        return false
    end
    if duration <= 0 or not cooldownFrame.SetCooldown then
        return false
    end

    if modRate ~= nil then
        if type(modRate) ~= "number" then
            return false
        end
        return pcall(cooldownFrame.SetCooldown, cooldownFrame, startTime, duration, modRate)
    end
    return pcall(cooldownFrame.SetCooldown, cooldownFrame, startTime, duration)
end

function Helpers.ApplyCooldownFromSpell(cooldownFrame, spellID, reverse, ignoreGCD)
    if not cooldownFrame or not spellID then
        return false
    end

    if ignoreGCD == nil then ignoreGCD = true end

    local start, duration, modRate, isActive = Helpers.ReadSpellCooldown(spellID)
    if not Helpers.IsCooldownActive(start, duration, isActive) then
        return false
    end

    local durationObj = nil
    if cooldownFrame.SetCooldownFromDurationObject
        and C_Spell and C_Spell.GetSpellCooldownDuration then
        local ok, fetchedDurationObj = pcall(C_Spell.GetSpellCooldownDuration, spellID, ignoreGCD)
        if ok and fetchedDurationObj then
            durationObj = fetchedDurationObj
        end
    end

    return Helpers.ApplyCooldownFromStart(cooldownFrame, durationObj, start, duration, modRate, reverse)
end

local function ApplyCooldownFromExpiration(cooldownFrame, expirationTime, duration, modRate)
    if Helpers.IsSecretValue(expirationTime) or Helpers.IsSecretValue(duration) or Helpers.IsSecretValue(modRate) then
        return false -- @secret-policy: reject-secret-value (numeric cooldown path needs readable args)
    end
    if expirationTime == nil or duration == nil then
        return false
    end
    if type(expirationTime) ~= "number" or type(duration) ~= "number" then
        return false
    end
    if duration <= 0 then
        return false
    end
    if modRate ~= nil and type(modRate) ~= "number" then
        return false
    end

    if cooldownFrame.SetCooldownFromExpirationTime then
        local ok
        if modRate ~= nil then
            ok = pcall(cooldownFrame.SetCooldownFromExpirationTime, cooldownFrame, expirationTime, duration, modRate)
        else
            ok = pcall(cooldownFrame.SetCooldownFromExpirationTime, cooldownFrame, expirationTime, duration)
        end
        if ok then
            return true
        end
    end

    if not cooldownFrame.SetCooldown then
        return false
    end

    local startTime = expirationTime - duration
    if modRate ~= nil then
        return pcall(cooldownFrame.SetCooldown, cooldownFrame, startTime, duration, modRate)
    end
    return pcall(cooldownFrame.SetCooldown, cooldownFrame, startTime, duration)
end

function Helpers.ApplyCooldownFromAura(cooldownFrame, unit, auraInstanceID, expirationTime, duration, reverse, modRate)
    if not cooldownFrame then
        return false
    end

    if cooldownFrame.SetCooldownFromDurationObject
        and unit and auraInstanceID
        and C_UnitAuras and C_UnitAuras.GetAuraDuration then
        local ok, durationObj = pcall(C_UnitAuras.GetAuraDuration, unit, auraInstanceID)
        if ok and durationObj then
            local applied = pcall(cooldownFrame.SetCooldownFromDurationObject, cooldownFrame, durationObj, reverse)
            if applied then
                return true
            end
        end
    end

    if ApplyCooldownFromExpiration(cooldownFrame, expirationTime, duration, modRate) then
        return true
    end

    if cooldownFrame.Clear then
        cooldownFrame:Clear()
    end
    return false
end

function Helpers.ApplyCooldownSwipeStyle(cooldownFrame, element)
    if not cooldownFrame then
        return
    end
    local style = (element and element.swipeStyle) or "radial"
    ns.SafeCallMethodIfPresent("best-effort-style", cooldownFrame, "SetDrawSwipe",
        style == "radial" and (not element or element.hideSwipe ~= true))
    ns.SafeCallMethodIfPresent("best-effort-style", cooldownFrame, "SetReverse", element and element.reverseSwipe == true)
end

function Helpers.PlaceRow(widget, body, sy, rowHeight)
    widget:SetPoint("TOPLEFT", 0, sy)
    widget:SetPoint("RIGHT", body, "RIGHT", 0, 0)
    return sy - (rowHeight or 32)
end

local _backdropColorRecovery = Helpers.CreateStateTable()
ns._backdropColorRecovery = _backdropColorRecovery

function Helpers.SetFrameBackdropColor(frame, r, g, b, a)
    frame._quiBgR, frame._quiBgG, frame._quiBgB, frame._quiBgA = r, g, b, a
    local ok = ns.SafeCallMethod("defer-ooc", frame, "SetBackdropColor", r, g, b, a)
    if not ok then
        _backdropColorRecovery[frame] = true
    end
end

function Helpers.SetFrameBackdropBorderColor(frame, r, g, b, a)
    frame._quiBorderR, frame._quiBorderG, frame._quiBorderB, frame._quiBorderA = r, g, b, a
    local ok = ns.SafeCallMethod("defer-ooc", frame, "SetBackdropBorderColor", r, g, b, a)
    if not ok then
        _backdropColorRecovery[frame] = true
    end
end

function Helpers.EnsureDefaults(tbl, defaults)
    for k, v in pairs(defaults) do
        if tbl[k] == nil then
            if type(v) == "table" then
                local copy = {}
                for tk, tv in pairs(v) do copy[tk] = tv end
                tbl[k] = copy
            else
                tbl[k] = v
            end
        end
    end
end
