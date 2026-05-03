---------------------------------------------------------------------------
-- QUI Skinning: Blizzard Damage Meter (12.0+)
-- Applies QUI's Faithful visual treatment to Blizzard's built-in Damage
-- Meter (manager `_G.DamageMeter` and session windows
-- `_G.DamageMeterSessionWindow1..3`). Registers each session window with
-- QUI Layout Mode for QUI-managed positioning; suppresses windows during
-- Blizzard Edit Mode.
--
-- Combat-taint posture: discovery via hooksecurefunc. Any QUI work reached
-- from Blizzard damage-meter refresh paths is deferred out of the current
-- call chain, and Blizzard-owned Lua methods are invoked through securecall
-- when available so restricted combat values are not compared under QUI taint.
-- Per-frame state lives in SkinBase.SetFrameData (weak-keyed external table).
-- Backdrops live on a child frame, never on the meter frame itself.
---------------------------------------------------------------------------
local ADDON_NAME, ns = ...
local Helpers   = ns.Helpers
local SkinBase  = ns.SkinBase
local LSM       = LibStub("LibSharedMedia-3.0", true)
local securecallfunction = securecallfunction

local FALLBACK_TEXTURE = "Interface\\Buttons\\WHITE8x8"

local function SecureCallFunction(fn, ...)
    if type(fn) ~= "function" then return nil end
    if securecallfunction then
        return securecallfunction(fn, ...)
    end
    return pcall(fn, ...)
end

local function SecureCallMethod(obj, method, ...)
    if not obj then return nil end
    local fn = type(method) == "string" and obj[method] or method
    if type(fn) ~= "function" then return nil end
    if securecallfunction then
        return securecallfunction(fn, obj, ...)
    end
    return pcall(fn, obj, ...)
end

local function DeferDamageMeterWork(fn, ...)
    local argc = select("#", ...)
    if argc == 0 then
        C_Timer.After(0, fn)
        return
    end

    local args = { ... }
    C_Timer.After(0, function()
        fn(unpack(args, 1, argc))
    end)
end

local entryDisplayOverridesInstalled = false

local function SafeGetMethodResult(obj, method, ...)
    if not obj then return false end
    local fn = obj[method]
    if type(fn) ~= "function" then return false end

    if securecallfunction then
        return pcall(securecallfunction, fn, obj, ...)
    end
    return pcall(fn, obj, ...)
end

local function SetEntryTextFromMethod(self, textMethod, fontStringMethod)
    local textOK, text = SafeGetMethodResult(self, textMethod)
    if not textOK then return end

    local fontStringOK, fontString = SafeGetMethodResult(self, fontStringMethod)
    if not fontStringOK then return end

    SecureCallMethod(fontString, "SetText", text)
end

local function SecretSafeUpdateName(self)
    SetEntryTextFromMethod(self, "GetNameText", "GetName")
end

local function SecretSafeUpdateValue(self)
    SetEntryTextFromMethod(self, "GetValueText", "GetValue")
end

local function SecretSafeUpdateIcon(self)
    local iconOK, icon = SafeGetMethodResult(self, "GetIcon")
    if not iconOK or not icon then return end

    local atlasOK, atlas = SafeGetMethodResult(self, "GetIconAtlasElement")
    if atlasOK and not Helpers.IsSecretValue(atlas) and atlas then
        SecureCallMethod(icon, "SetAtlas", atlas)
        return
    end

    local textureOK, texture = SafeGetMethodResult(self, "GetIconTexture")
    if textureOK then
        SecureCallMethod(icon, "SetTexture", texture)
    end
end

local function SecretSafeUpdateStatusBar(self)
    local statusBarOK, statusBar = SafeGetMethodResult(self, "GetStatusBar")
    if not statusBarOK or not statusBar then return end

    local maxValue = self.maxValue
    if not Helpers.IsSecretValue(maxValue) and maxValue == nil then
        maxValue = 0
    end

    local value = self.value
    if not Helpers.IsSecretValue(value) and value == nil then
        value = 0
    end

    SafeGetMethodResult(statusBar, "SetMinMaxValues", 0, maxValue)
    SafeGetMethodResult(statusBar, "SetValue", value)
end

local function PatchEntryDisplayMethods(target)
    if not target then return false end

    local patched = false
    if type(target.GetNameText) == "function" and type(target.GetName) == "function" then
        target.UpdateName = SecretSafeUpdateName
        patched = true
    end
    if type(target.GetValueText) == "function" and type(target.GetValue) == "function" then
        target.UpdateValue = SecretSafeUpdateValue
        patched = true
    end
    if type(target.GetIcon) == "function" and type(target.GetIconTexture) == "function" then
        target.UpdateIcon = SecretSafeUpdateIcon
        patched = true
    end
    if type(target.GetStatusBar) == "function" then
        target.UpdateStatusBar = SecretSafeUpdateStatusBar
        patched = true
    end

    return patched
end

-- Frame-instance patcher. Setting a Lua field on a frame is not a protected
-- operation, so this is safe in combat — and combat is exactly when the
-- stock-method failure mode trips, so a combat guard would defeat the fix.
local function PatchEntryFrameDisplayMethods(frame)
    PatchEntryDisplayMethods(frame)
end

-- SetSessionDuration replacement. Stock body is:
--   if durationSeconds and durationSeconds ~= 0 then
--     fontString:SetText(("[%s] "):format(SecondsToClock(durationSeconds)))
--   else
--     fontString:SetText("")
--   end
-- Both the `~= 0` compare AND the SecondsToClock call (arithmetic + tonumber
-- internally) fault on a secret-number duration under taint.
--
-- Per Blizzard's API docs (Blizzard_APIDocumentationGenerated/
-- StringUtilDocumentation.lua), C_StringUtil exposes formatters explicitly
-- marked SecretArguments=AllowedWhenTainted that fold the entire stock
-- branch into two pure C-side calls:
--   * TruncateWhenZero(n)  → "n" as a string, or "" when n == 0
--   * WrapString(infix, prefix, suffix) → prefix..infix..suffix iff infix is
--                                         non-empty, else ""
-- Both accept secret numbers/strings from tainted code. Composed, they give
-- us the same nil/zero=>clear behavior as stock without ever touching the
-- secret value at the Lua level. FontString:SetText is also AllowedWhenTainted
-- and accepts the resulting (possibly secret) string directly.
--
-- Trade-off vs stock: when the duration is non-secret we keep the [M:SS]
-- clock format via SecondsToClock; when secret (active combat) we render
-- raw seconds because splitting into minutes/seconds requires arithmetic on
-- the secret, which no documented API permits.
local function SecretSafeSetSessionDuration(self, durationSeconds)
    local fsOK, fontString = SafeGetMethodResult(self, "GetSessionTimerFontString")
    if not fsOK or not fontString then return end

    if Helpers.IsSecretValue(durationSeconds) then
        if C_StringUtil and C_StringUtil.TruncateWhenZero and C_StringUtil.WrapString then
            local seconds = C_StringUtil.TruncateWhenZero(durationSeconds)
            SecureCallMethod(fontString, "SetText", C_StringUtil.WrapString(seconds, "[", "s] "))
        end
        return
    end

    if durationSeconds and durationSeconds ~= 0 then
        SecureCallMethod(fontString, "SetText", ("[%s] "):format(SecondsToClock(durationSeconds)))
    else
        SecureCallMethod(fontString, "SetText", "")
    end
end

local function PatchSessionWindowDisplayMethods(target)
    if not target then return false end
    if type(target.GetSessionTimerFontString) ~= "function" then return false end
    target.SetSessionDuration = SecretSafeSetSessionDuration
    return true
end

-- LocalPlayerEntry isn't a direct child of the session window — it lives
-- under MinimizeContainer (per docs/blizzard/damage-meter-frames.md and
-- DamageMeterSessionWindow.xml). Earlier passes that wrote `window.LocalPlayerEntry`
-- silently no-op'd against nil and the stock UpdateName/UpdateValue/etc.
-- never got swapped on the instance. Use Blizzard's documented convenience
-- accessor when present, fall back to the explicit child path.
local function ResolveLocalPlayerEntry(window)
    if not window then return nil end
    if type(window.GetLocalPlayerEntry) == "function" then
        local ok, entry = pcall(window.GetLocalPlayerEntry, window)
        if ok and entry then return entry end
    end
    local mc = window.MinimizeContainer
    if mc and mc.LocalPlayerEntry then return mc.LocalPlayerEntry end
    return window.LocalPlayerEntry
end

local function InstallSecretSafeEntryOverrides()
    if entryDisplayOverridesInstalled then return end

    local patched = false
    patched = PatchEntryDisplayMethods(DamageMeterEntryMixin) or patched
    patched = PatchEntryDisplayMethods(DamageMeterSourceEntryMixin) or patched
    patched = PatchEntryDisplayMethods(DamageMeterSpellEntryMixin) or patched
    patched = PatchSessionWindowDisplayMethods(DamageMeterSessionWindowMixin) or patched

    entryDisplayOverridesInstalled = patched
end

-- Module-private state. Weak-keyed so frame destruction is automatic.
local trackedWindows  = Helpers.CreateStateTable()
local trackedPopups   = Helpers.CreateStateTable()
local syncInProgress      = false   -- guard against re-entry during write-through
local pendingCombatWrites = {}      -- queue for in-combat setter calls
local hooksInstalled  = false
local mixinsHooked    = false

-- Forward declarations so EnsureWindowSkinned and the SkinDropdown/SkinSourceWindow
-- definitions further down resolve to the same upvalue rather than to globals.
local SkinDropdown
local SkinSourceWindow
local RegisterWithLayoutMode
local LayoutModeKeyForWindow
local ApplyShadowValuesToBlizzard
local AttachResizeGripsToHandle
local ApplyAllSavedMeterSizes

---------------------------------------------------------------------------
-- Settings access
---------------------------------------------------------------------------
local function GetGeneralSettings()
    local core = Helpers.GetCore()
    return core and core.db and core.db.profile and core.db.profile.general
end

local function GetSettings()
    local core = Helpers.GetCore()
    return core and core.db and core.db.profile and core.db.profile.damageMeter
end

local function IsModuleEnabled()
    local g = GetGeneralSettings()
    if not g then return false end
    if g.skinDamageMeter == nil then return true end
    return g.skinDamageMeter
end

-- Blizzard's CVar is the canonical "is the meter on" signal. The DamageMeter
-- manager frame always exists once Blizzard_DamageMeter loads regardless of
-- this CVar; only session windows are governed by it.
local function IsBlizzardMeterEnabled()
    if CVarCallbackRegistry and CVarCallbackRegistry.GetCVarValueBool then
        return CVarCallbackRegistry:GetCVarValueBool("damageMeterEnabled")
    end
    return false
end

local function ResolveManager()
    return _G.DamageMeter
end

local function ResolvePrimaryWindow()
    local mgr = ResolveManager()
    return mgr and mgr.GetPrimarySessionWindow and mgr:GetPrimarySessionWindow() or nil
end

local function ResolveAllWindows()
    local list = {}
    local mgr = ResolveManager()
    if not mgr or type(mgr.windowDataList) ~= "table" then return list end
    for _, data in pairs(mgr.windowDataList) do
        if data and data.sessionWindow then list[#list+1] = data.sessionWindow end
    end
    return list
end

---------------------------------------------------------------------------
-- StripWindowChrome(window)
-- Hide Blizzard's stock chrome on a session window (Header gradient,
-- MinimizeContainer Background, ResizeButton textures). Idempotent.
---------------------------------------------------------------------------
local function HideRegion(region)
    if region and region.SetAlpha then region:SetAlpha(0) end
end

local function StripWindowChrome(window)
    if not window then return end

    -- Header is a direct fontstring/texture child of the session window.
    HideRegion(window.Header)

    local mc = window.MinimizeContainer
    if mc then
        HideRegion(mc.Background)

        local rb = mc.ResizeButton
        if rb then
            -- ResizeButton starts at alpha=0 and only animates in on mouseover.
            -- We hide its textures so even when shown it's invisible.
            HideRegion(rb:GetNormalTexture())
            HideRegion(rb:GetHighlightTexture())
            HideRegion(rb:GetPushedTexture())
        end
    end
end

local DAMAGE_METER_SCROLLBAR_HIT_WIDTH = 12
local DAMAGE_METER_SCROLLBAR_TRACK_WIDTH = 2
local DAMAGE_METER_SCROLLBAR_THUMB_WIDTH = 6

local function HideTextureRegions(frame, exceptRegion)
    if not frame or not frame.GetNumRegions then return end
    for i = 1, frame:GetNumRegions() do
        local region = select(i, frame:GetRegions())
        if region ~= exceptRegion and region and region.IsObjectType and region:IsObjectType("Texture") then
            HideRegion(region)
        end
    end
end

local function ShowTextureRegions(frame, exceptRegion)
    if not frame or not frame.GetNumRegions then return end
    for i = 1, frame:GetNumRegions() do
        local region = select(i, frame:GetRegions())
        if region ~= exceptRegion and region and region.IsObjectType and region:IsObjectType("Texture") then
            region:SetAlpha(1)
        end
    end
end

local function ResolveScrollBarThumb(scrollBar)
    if not scrollBar then return nil end

    if scrollBar.GetThumb then
        local ok, thumb = pcall(scrollBar.GetThumb, scrollBar)
        if ok and thumb then return thumb end
    end

    if scrollBar.Track and scrollBar.Track.Thumb then
        return scrollBar.Track.Thumb
    end

    return scrollBar.Thumb
end

local function ResolveScrollBarThumbTexture(scrollBar)
    if not scrollBar then return nil end
    if scrollBar.ThumbTexture then return scrollBar.ThumbTexture end
    if scrollBar.GetThumbTexture then
        local ok, thumb = pcall(scrollBar.GetThumbTexture, scrollBar)
        if ok and thumb then return thumb end
    end
    return nil
end

local function IsMinimalScrollBar(scrollBar)
    local thumb = ResolveScrollBarThumb(scrollBar)
    return scrollBar
        and scrollBar.Track
        and thumb
        and thumb.GetParent
        and thumb:GetParent() == scrollBar.Track
end

local function HideScrollButton(button)
    if not button then return end
    button:SetAlpha(0)
    if button.SetSize then button:SetSize(1, 1) end
end

local function GetDamageMeterAccentColor()
    local gSettings = GetGeneralSettings()
    local sr, sg, sb = SkinBase.GetSkinColors(gSettings, "damageMeter")
    return sr, sg, sb
end

local function GetThumbMouseAlpha(thumb)
    return thumb and thumb.IsMouseOver and thumb:IsMouseOver() and 0.9 or 0.82
end

local function PaintMinimalScrollThumb(thumb, r, g, b, alpha)
    if not thumb then return end
    local texture = SkinBase.GetFrameData(thumb, "qdmScrollThumbTexture")
    if not texture then return end

    if thumb.Begin then HideRegion(thumb.Begin) end
    if thumb.Middle then HideRegion(thumb.Middle) end
    if thumb.End then HideRegion(thumb.End) end

    texture:ClearAllPoints()
    texture:SetPoint("TOP", thumb, "TOP", 0, 0)
    texture:SetPoint("BOTTOM", thumb, "BOTTOM", 0, 0)
    texture:SetWidth(DAMAGE_METER_SCROLLBAR_THUMB_WIDTH)
    texture:SetColorTexture(r, g, b, alpha or 0.82)
    texture:SetAlpha(1)
    texture:Show()
end

local function PaintMinimalScrollThumbFromSettings(thumb, alpha)
    if not IsModuleEnabled() then return end
    local r, g, b = GetDamageMeterAccentColor()
    PaintMinimalScrollThumb(thumb, r, g, b, alpha or GetThumbMouseAlpha(thumb))
end

local function StyleMinimalScrollThumb(thumb, r, g, b)
    if not thumb then return end

    local texture = SkinBase.GetFrameData(thumb, "qdmScrollThumbTexture")
    if not texture then
        texture = thumb:CreateTexture(nil, "OVERLAY")
        texture:SetTexture(FALLBACK_TEXTURE)
        SkinBase.SetFrameData(thumb, "qdmScrollThumbTexture", texture)

        if thumb.HookScript then
            thumb:HookScript("OnShow", function(self)
                PaintMinimalScrollThumbFromSettings(self)
            end)
            thumb:HookScript("OnSizeChanged", function(self)
                PaintMinimalScrollThumbFromSettings(self)
            end)
            thumb:HookScript("OnEnter", function(self)
                PaintMinimalScrollThumbFromSettings(self, 0.9)
            end)
            thumb:HookScript("OnLeave", function(self)
                PaintMinimalScrollThumbFromSettings(self, 0.82)
            end)
            thumb:HookScript("OnMouseDown", function(self)
                PaintMinimalScrollThumbFromSettings(self, 1)
            end)
            thumb:HookScript("OnMouseUp", function(self)
                PaintMinimalScrollThumbFromSettings(self)
            end)
        end
    end

    HideTextureRegions(thumb, texture)
    if thumb.Begin then HideRegion(thumb.Begin) end
    if thumb.Middle then HideRegion(thumb.Middle) end
    if thumb.End then HideRegion(thumb.End) end
    if thumb.SetWidth then thumb:SetWidth(DAMAGE_METER_SCROLLBAR_HIT_WIDTH) end

    PaintMinimalScrollThumb(thumb, r, g, b, 0.82)
end

local function StyleDamageMeterScrollBar(scrollBar, r, g, b)
    if not scrollBar then return end

    if not r or not g or not b then
        r, g, b = GetDamageMeterAccentColor()
    end

    if not SkinBase.GetFrameData(scrollBar, "qdmScrollHooks") and scrollBar.HookScript then
        SkinBase.SetFrameData(scrollBar, "qdmScrollHooks", true)
        scrollBar:HookScript("OnShow", function(self)
            if IsModuleEnabled() then StyleDamageMeterScrollBar(self) end
        end)
    end

    scrollBar:SetAlpha(1)
    if scrollBar.SetWidth then scrollBar:SetWidth(DAMAGE_METER_SCROLLBAR_HIT_WIDTH) end

    HideTextureRegions(scrollBar)
    HideRegion(scrollBar.Background)
    HideRegion(scrollBar.BG)

    local track = scrollBar.Track
    if track then
        local trackTexture = SkinBase.GetFrameData(scrollBar, "qdmScrollTrackTexture")
        if not trackTexture then
            trackTexture = track:CreateTexture(nil, "BACKGROUND")
            trackTexture:SetTexture(FALLBACK_TEXTURE)
            SkinBase.SetFrameData(scrollBar, "qdmScrollTrackTexture", trackTexture)
        end

        HideTextureRegions(track, trackTexture)
        track:SetAlpha(1)
        if track.SetWidth then track:SetWidth(DAMAGE_METER_SCROLLBAR_HIT_WIDTH) end

        trackTexture:ClearAllPoints()
        trackTexture:SetPoint("TOP", track, "TOP", 0, 0)
        trackTexture:SetPoint("BOTTOM", track, "BOTTOM", 0, 0)
        trackTexture:SetWidth(DAMAGE_METER_SCROLLBAR_TRACK_WIDTH)
        trackTexture:SetColorTexture(r, g, b, 0.28)
        trackTexture:SetAlpha(1)
        trackTexture:Show()
    end

    local thumbTexture = ResolveScrollBarThumbTexture(scrollBar)
    if thumbTexture and thumbTexture.SetColorTexture then
        thumbTexture:SetTexture(FALLBACK_TEXTURE)
        thumbTexture:SetColorTexture(r, g, b, 0.78)
        thumbTexture:SetAlpha(1)
        if thumbTexture.SetSize then thumbTexture:SetSize(DAMAGE_METER_SCROLLBAR_THUMB_WIDTH, 40) end
    elseif IsMinimalScrollBar(scrollBar) then
        StyleMinimalScrollThumb(ResolveScrollBarThumb(scrollBar), r, g, b)
    end

    HideScrollButton(scrollBar.ScrollUpButton)
    HideScrollButton(scrollBar.ScrollDownButton)
    HideScrollButton(scrollBar.Back)
    HideScrollButton(scrollBar.Forward)
end

local function RestoreDamageMeterScrollBar(scrollBar)
    if not scrollBar then return end

    local trackTexture = SkinBase.GetFrameData(scrollBar, "qdmScrollTrackTexture")
    if trackTexture then trackTexture:Hide() end
    ShowTextureRegions(scrollBar)

    if scrollBar.Track then
        ShowTextureRegions(scrollBar.Track, trackTexture)
        scrollBar.Track:SetAlpha(1)
    end

    local thumb = ResolveScrollBarThumb(scrollBar)
    if thumb then
        local thumbTexture = SkinBase.GetFrameData(thumb, "qdmScrollThumbTexture")
        if thumbTexture then thumbTexture:Hide() end
        ShowTextureRegions(thumb, thumbTexture)
        if thumb.Begin then thumb.Begin:SetAlpha(1) end
        if thumb.Middle then thumb.Middle:SetAlpha(1) end
        if thumb.End then thumb.End:SetAlpha(1) end
    end
end

local function ResolveWindowScrollBar(window)
    if not window then return nil end
    if type(window.GetScrollBar) == "function" then
        local ok, scrollBar = pcall(window.GetScrollBar, window)
        if ok and scrollBar then return scrollBar end
    end
    local mc = window.MinimizeContainer
    return (mc and mc.ScrollBar) or window.ScrollBar
end

local function ResolvePopupScrollBar(popup)
    if not popup then return nil end
    if type(popup.GetScrollBar) == "function" then
        local ok, scrollBar = pcall(popup.GetScrollBar, popup)
        if ok and scrollBar then return scrollBar end
    end
    return popup.ScrollBar
end

---------------------------------------------------------------------------
-- ForceLockWindow(window)
-- Lock a session window unconditionally — QUI Layout Mode is the sole
-- editor. Idempotent. Called from EnsureWindowSkinned and from the
-- SetupSessionWindow hook (Blizzard re-asserts SetMovable(true) on every
-- setup; we re-lock immediately after).
---------------------------------------------------------------------------
local function ForceLockWindow(window)
    if not window then return end
    if window.SetLocked then
        -- SetLocked also calls InitializeSettingsDropdown, refreshing the
        -- "lock" entry in the dropdown menu so it reflects locked state.
        SecureCallMethod(window, "SetLocked", true)
    end
    if window.SetMovable    then SecureCallMethod(window, "SetMovable", false) end
    if window.SetResizable  then SecureCallMethod(window, "SetResizable", false) end
end

---------------------------------------------------------------------------
-- EnsureWindowSkinned(window)
-- Idempotent. Skins the session window's chrome.
---------------------------------------------------------------------------
local function EnsureWindowSkinned(window)
    if not window then return end

    -- Pre-patch entry-frame method copies on every call, BEFORE the IsSkinned
    -- early exit. LocalPlayerEntry is an XML child of the session window, so
    -- its UpdateName/UpdateValue/UpdateIcon are copied from
    -- DamageMeterSourceEntryMixin at frame-creation time. On /reload, the
    -- session window (and its LocalPlayerEntry child) are constructed during
    -- DamageMeter:OnLoad → RestoreWindowData → SetupSessionWindow, which runs
    -- BEFORE our ADDON_LOADED+0.1s mixin patch — so the instance ends up with
    -- stock UpdateName whose `text ~= self.nameText` compare blows up under
    -- taint as soon as the secret-string source name lands. Patching the
    -- instance directly swaps in our SecretSafe* before the next Init runs.
    -- Same race for SetSessionDuration on the window itself
    -- (`durationSeconds ~= 0` compare on a secret number from C_DamageMeter).
    -- Idempotent: re-assigning the same function is a no-op.
    PatchSessionWindowDisplayMethods(window)
    local localEntry = ResolveLocalPlayerEntry(window)
    if localEntry then
        PatchEntryFrameDisplayMethods(localEntry)
    end
    if window.ForEachEntryFrame then
        window:ForEachEntryFrame(PatchEntryFrameDisplayMethods)
    end

    local g = GetGeneralSettings()
    local sr, sg, sb, sa, bgr, bgg, bgb, bga = SkinBase.GetSkinColors(g, "damageMeter")

    if SkinBase.IsSkinned(window) then
        StyleDamageMeterScrollBar(ResolveWindowScrollBar(window), sr, sg, sb)
        local mc = window.MinimizeContainer
        if mc and mc.SourceWindow then
            SkinSourceWindow(mc.SourceWindow)
        end
        return
    end

    -- Backdrop on a child frame — never written onto the Blizzard frame itself.
    SkinBase.CreateBackdrop(window, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    StripWindowChrome(window)
    StyleDamageMeterScrollBar(ResolveWindowScrollBar(window), sr, sg, sb)

    -- Skin dropdowns (segment / type / settings). All three are direct children of the session window.
    if window.SessionDropdown        then SkinDropdown(window.SessionDropdown)        end
    if window.DamageMeterTypeDropdown then SkinDropdown(window.DamageMeterTypeDropdown) end
    if window.SettingsDropdown       then SkinDropdown(window.SettingsDropdown)       end

    -- The SourceWindow exists as a child of MinimizeContainer at all times
    -- but is hidden until first row click. Skin proactively so first show is clean.
    local mc = window.MinimizeContainer
    if mc and mc.SourceWindow then
        SkinSourceWindow(mc.SourceWindow)
    end

    SkinBase.MarkSkinned(window)
    trackedWindows[window] = true

    ForceLockWindow(window)

    local key, label = LayoutModeKeyForWindow(window)
    RegisterWithLayoutMode(window, key, label)
end

---------------------------------------------------------------------------
-- SkinRow(row)
-- Hide stock background/edge atlases on each row's StatusBar; build a
-- 1px QUI-accent backdrop around the row. Idempotent.
--
-- IMPORTANT: do NOT call SetStatusBarTexture — class color rides on
-- the bar texture's vertex color and would be lost when the texture
-- swaps. Blizzard's atlas is flat enough to read as our QUI texture
-- once chrome is stripped.
---------------------------------------------------------------------------
local function SkinRow(row)
    if not row then return end
    PatchEntryFrameDisplayMethods(row)
    if SkinBase.GetFrameData(row, "qdmRowSkinned") then return end

    local statusBar = row.StatusBar
    if not statusBar then return end

    local g = GetGeneralSettings()
    local sr, sg, sb, sa = SkinBase.GetSkinColors(g, "damageMeter")

    -- Strip stock backgrounds. Use the BackgroundRegions array Blizzard provides.
    if type(statusBar.BackgroundRegions) == "table" then
        for _, region in ipairs(statusBar.BackgroundRegions) do
            HideRegion(region)
        end
    else
        HideRegion(statusBar.Background)
        HideRegion(statusBar.BackgroundEdge)
    end

    -- Row backdrop child for the dark row bg + accent border.
    local backdrop = SkinBase.GetFrameData(row, "qdmRowBackdrop")
    if not backdrop then
        backdrop = CreateFrame("Frame", nil, row, "BackdropTemplate")
        local rowLevel = row:GetFrameLevel()
        backdrop:SetFrameLevel(rowLevel > 0 and (rowLevel - 1) or 0)
        backdrop:SetPoint("TOPLEFT", statusBar, "TOPLEFT", -1, 1)
        backdrop:SetPoint("BOTTOMRIGHT", statusBar, "BOTTOMRIGHT", 1, -1)
        backdrop:EnableMouse(false)
        SkinBase.SetFrameData(row, "qdmRowBackdrop", backdrop)
    end
    local px = SkinBase.GetPixelSize(backdrop, 1)
    backdrop:SetBackdrop({
        bgFile = FALLBACK_TEXTURE,
        edgeFile = FALLBACK_TEXTURE,
        edgeSize = px,
        insets = { left = px, right = px, top = px, bottom = px },
    })
    backdrop:SetBackdropColor(0.18, 0.18, 0.20, 1)
    backdrop:SetBackdropBorderColor(sr, sg, sb, sa)

    -- Restyle name / value fontstrings using QUI font.
    local fontPath = (Helpers.GetGeneralFont and Helpers.GetGeneralFont()) or "Fonts\\FRIZQT__.TTF"
    local outline  = (Helpers.GetGeneralFontOutline and Helpers.GetGeneralFontOutline()) or ""
    local function styleText(fs)
        if not fs or not fs.SetFont then return end
        local _, size = fs:GetFont()
        fs:SetFont(fontPath, size or 11, outline)
        fs:SetTextColor(0.95, 0.95, 0.95, 1)
    end
    styleText(statusBar.Name)
    styleText(statusBar.Value)

    SkinBase.SetFrameData(row, "qdmRowSkinned", true)
end

local function DeferSkinRow(row, forceRefresh)
    if not row then return end
    DeferDamageMeterWork(function(frame)
        if not IsModuleEnabled() then return end
        if forceRefresh then
            SkinBase.SetFrameData(frame, "qdmRowSkinned", nil)
        end
        SkinRow(frame)
    end, row)
end

local function DeferStripRowBackground(row)
    if not row then return end
    DeferDamageMeterWork(function(frame)
        if not IsModuleEnabled() then return end
        local sb = frame.StatusBar
        if not sb then return end
        if type(sb.BackgroundRegions) == "table" then
            for _, region in ipairs(sb.BackgroundRegions) do HideRegion(region) end
        else
            HideRegion(sb.Background)
            HideRegion(sb.BackgroundEdge)
        end
    end, row)
end

---------------------------------------------------------------------------
-- SkinDropdown(dropdown)
-- 1px accent border + dark bg around any of the meter's dropdowns.
-- Strips stock common-dropdown texture and blizz arrow chrome.
-- Idempotent.
---------------------------------------------------------------------------
local DROPDOWN_STOCK_TEXTURE_FIELDS = {
    "Background", "Bg", "Border", "BorderTexture",
    "NormalTexture", "PushedTexture", "HighlightTexture", "DisabledTexture",
}

SkinDropdown = function(dropdown)
    if not dropdown or SkinBase.GetFrameData(dropdown, "qdmDdSkinned") then return end

    -- Strip stock textures (set alpha 0 — don't destroy, dropdown logic may inspect them).
    for _, field in ipairs(DROPDOWN_STOCK_TEXTURE_FIELDS) do
        local region = dropdown[field]
        if region and region.SetAlpha then region:SetAlpha(0) end
    end
    -- Some dropdown templates use accessor methods rather than fields.
    if dropdown.GetNormalTexture    then HideRegion(dropdown:GetNormalTexture())    end
    if dropdown.GetPushedTexture    then HideRegion(dropdown:GetPushedTexture())    end
    if dropdown.GetHighlightTexture then HideRegion(dropdown:GetHighlightTexture()) end

    -- Borderless: dark fill, transparent border. Stock chrome already stripped above.
    -- Keep the dark fill so text reads cleanly over the meter window's backdrop.
    SkinBase.CreateBackdrop(dropdown, 0, 0, 0, 0, 0.05, 0.05, 0.05, 0.95)

    SkinBase.SetFrameData(dropdown, "qdmDdSkinned", true)
end

---------------------------------------------------------------------------
-- SkinSourceWindow(popup)
-- Strip the common-dropdown-bg atlas, build a QUI backdrop, hide the
-- ResizeButton chrome. Per-ability rows are auto-skinned by the mixin
-- hooks in Task 7 (they're DamageMeterSpellEntryTemplate, inheriting
-- from DamageMeterEntryTemplate).
---------------------------------------------------------------------------
SkinSourceWindow = function(popup)
    if not popup then return end

    local g = GetGeneralSettings()
    local sr, sg, sb, sa, bgr, bgg, bgb, bga = SkinBase.GetSkinColors(g, "damageMeter")

    if SkinBase.IsSkinned(popup) then
        StyleDamageMeterScrollBar(ResolvePopupScrollBar(popup), sr, sg, sb)
        return
    end

    HideRegion(popup.Background)

    SkinBase.CreateBackdrop(popup, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    StyleDamageMeterScrollBar(ResolvePopupScrollBar(popup), sr, sg, sb)

    if popup.ResizeButton then
        HideRegion(popup.ResizeButton:GetNormalTexture())
        HideRegion(popup.ResizeButton:GetHighlightTexture())
        HideRegion(popup.ResizeButton:GetPushedTexture())
    end

    SkinBase.MarkSkinned(popup)
    trackedPopups[popup] = true
end

---------------------------------------------------------------------------
-- LayoutModeFrameForWindow(window)
-- Returns the frame Layout Mode should anchor for this window. The primary
-- window inherits position from _G.DamageMeter via Blizzard's hardcoded
-- TOPLEFT/BOTTOMRIGHT anchors (set every SetupSessionWindow call), so we
-- anchor the manager itself. Secondary windows are independently positioned
-- by Blizzard (UIParent-relative offset), so we anchor the window directly
-- and re-apply via QUI_ApplyFrameAnchor in the SetupSessionWindow hook.
---------------------------------------------------------------------------
local function LayoutModeFrameForWindow(window)
    if not window then return nil end
    local idx = window.GetSessionWindowIndex and window:GetSessionWindowIndex() or window.sessionWindowIndex
    if idx == 1 then
        return ResolveManager() or window
    end
    return window
end

---------------------------------------------------------------------------
-- RegisterWithLayoutMode(window, key, label)
-- Idempotent. No-op if QUI_LayoutMode isn't loaded.
---------------------------------------------------------------------------
RegisterWithLayoutMode = function(window, key, label)
    if not window or not key then return end
    if SkinBase.GetFrameData(window, "qdmLmRegistered") then return end

    local lm = ns.QUI_LayoutMode
    if not lm or type(lm.RegisterElement) ~= "function" then return end

    local targetFrame = LayoutModeFrameForWindow(window)
    if not targetFrame then return end

    lm:RegisterElement({
        key      = key,
        label    = label,
        group    = "Display",
        order    = 60,
        isOwned  = false,
        getFrame = function() return targetFrame end,
        getSize  = function()
            if not targetFrame or not targetFrame.GetWidth then return nil end
            local w = targetFrame:GetWidth()
            local h = targetFrame:GetHeight()
            if type(w) ~= "number" or type(h) ~= "number" or w < 1 or h < 1 then return nil end
            return w, h
        end,
        isEnabled = function()
            return IsModuleEnabled() and IsBlizzardMeterEnabled()
        end,
        setGameplayHidden = function(hide)
            -- Always toggle the session WINDOW (not the manager) so the
            -- manager keeps its anchor-target footprint stable for other
            -- frames that may anchor to it via QUI_Anchoring.
            if hide then SecureCallMethod(window, "Hide") else SecureCallMethod(window, "Show") end
        end,
        onOpen = function()
            -- Layout Mode calls onOpen before creating the handle on first
            -- entry. Try now for existing handles, then once more next frame.
            local function Attach()
                local lm2 = ns.QUI_LayoutMode
                local handle = lm2 and lm2._handles and lm2._handles[key]
                if handle and AttachResizeGripsToHandle then
                    AttachResizeGripsToHandle(handle, key, function() return targetFrame end)
                    return true
                end
                return false
            end

            if not Attach() and C_Timer and C_Timer.After then
                C_Timer.After(0, Attach)
            end
        end,
    })

    -- Anchor system registration. Use QUI_RegisterFrameResolver so the key
    -- is recognized by both _G.QUI_ApplyFrameAnchor (which gates on
    -- FRAME_RESOLVERS via HasFrameResolverForKey) AND the anchor target
    -- registry (so other QUI elements can anchor TO the meter). Without the
    -- frame resolver, _G.QUI_ApplyFrameAnchor silently no-ops on the meter
    -- keys, which is why secondaries reset to Blizzard's hardcoded offsets
    -- on /reload despite a valid saved anchor.
    if _G.QUI_RegisterFrameResolver then
        _G.QUI_RegisterFrameResolver(key, {
            resolver = function() return targetFrame end,
            displayName = label,
            category = "Display",
            order = 60,
        })
    else
        -- Fallback: registry helper not available (early load), at least
        -- populate the anchor target registry directly.
        local anchoring = ns.QUI_Anchoring
        if anchoring and anchoring.RegisterAnchorTarget then
            anchoring:RegisterAnchorTarget(key, targetFrame, {
                displayName = label,
                category = "Display",
                order = 60,
            })
        end
        if ns.FRAME_ANCHOR_INFO then
            ns.FRAME_ANCHOR_INFO[key] = {
                displayName = label,
                category = "Display",
                order = 60,
            }
        end
    end

    SkinBase.SetFrameData(window, "qdmLmRegistered", true)
end

---------------------------------------------------------------------------
-- LayoutModeKeyForWindow(window)
-- Stable per-window key. The session window has a sessionWindowIndex field
-- that maps 1..3, set by DamageMeterMixin:SetDamageMeterOwner.
---------------------------------------------------------------------------
LayoutModeKeyForWindow = function(window)
    local idx = window.GetSessionWindowIndex and window:GetSessionWindowIndex() or window.sessionWindowIndex
    if idx == 1 then
        return "damageMeter_primary", "Damage Meter (Primary)"
    end
    return "damageMeter_extra_" .. tostring(idx or "x"),
           "Damage Meter (Extra " .. tostring(idx or "?") .. ")"
end

---------------------------------------------------------------------------
-- Resize support: 4-corner grips attached to each meter mover handle in
-- Layout Mode, persisted size in db.profile.damageMeter.windowSizes[key].
-- Bounds match Blizzard's Edit Mode caps for the manager: 300×120 to 600×400.
---------------------------------------------------------------------------
local METER_RESIZE_MIN_W, METER_RESIZE_MIN_H = 300, 120
local METER_RESIZE_MAX_W, METER_RESIZE_MAX_H = 600, 400

local function ClampMeterSize(w, h)
    if type(w) ~= "number" or type(h) ~= "number" then return nil, nil end
    w = math.floor(w + 0.5)
    h = math.floor(h + 0.5)
    if w < METER_RESIZE_MIN_W then w = METER_RESIZE_MIN_W end
    if w > METER_RESIZE_MAX_W then w = METER_RESIZE_MAX_W end
    if h < METER_RESIZE_MIN_H then h = METER_RESIZE_MIN_H end
    if h > METER_RESIZE_MAX_H then h = METER_RESIZE_MAX_H end
    return w, h
end

local function GetMeterSizeStore()
    local g = GetSettings()
    if not g then return nil end
    if type(g.windowSizes) ~= "table" then g.windowSizes = {} end
    return g.windowSizes
end

local function SaveMeterSize(key, w, h)
    local cw, ch = ClampMeterSize(w, h)
    if not cw or not ch then return end
    local store = GetMeterSizeStore()
    if store then
        store[key] = { w = cw, h = ch }
    end
end

local function LoadMeterSize(key)
    local g = GetSettings()
    if not g or type(g.windowSizes) ~= "table" then return nil end
    local entry = g.windowSizes[key]
    if type(entry) == "table" and type(entry.w) == "number" and type(entry.h) == "number" then
        return entry.w, entry.h
    end
    return nil
end

-- For primary, we resize the manager (the window inherits via TOPLEFT/
-- BOTTOMRIGHT). For secondaries, we resize the window directly.
local function ResolveResizeTargetForWindow(window)
    if not window then return nil end
    local idx = window.GetSessionWindowIndex and window:GetSessionWindowIndex() or window.sessionWindowIndex
    if idx == 1 then
        return ResolveManager() or window
    end
    return window
end

local function ApplySavedSizeToWindow(window)
    if not window or InCombatLockdown() then return end
    local key = LayoutModeKeyForWindow(window)
    local w, h = LoadMeterSize(key)
    if not w or not h then return end
    local target = ResolveResizeTargetForWindow(window)
    if not target then return end
    SecureCallMethod(target, "SetSize", w, h)
end

ApplyAllSavedMeterSizes = function()
    if not IsModuleEnabled() then return end
    for _, w in ipairs(ResolveAllWindows()) do
        ApplySavedSizeToWindow(w)
    end
end

-- Map a Layout Mode mover key back to the resize target frame. Mirrors
-- ResolveResizeTargetForWindow but takes a key (used by the slider plumbing
-- in the Layout Mode mover settings panel).
local function ResolveResizeTargetForKey(key)
    if key == "damageMeter_primary" then
        return ResolveManager() or ResolvePrimaryWindow()
    end
    local idx = tonumber(string.match(key or "", "^damageMeter_extra_(%d+)$"))
    if not idx then return nil end
    for _, w in ipairs(ResolveAllWindows()) do
        local widx = w.GetSessionWindowIndex and w:GetSessionWindowIndex() or w.sessionWindowIndex
        if widx == idx then return w end
    end
    return nil
end

local function MeterSliderGetSize(key)
    local target = ResolveResizeTargetForKey(key)
    if target then
        local w, h = target:GetWidth() or 0, target:GetHeight() or 0
        if w > 0 and h > 0 then return w, h end
    end
    local saved_w, saved_h = LoadMeterSize(key)
    if saved_w and saved_h then return saved_w, saved_h end
    return METER_RESIZE_MIN_W, METER_RESIZE_MIN_H
end

local function MeterSliderSetSize(key, w, h)
    if InCombatLockdown() then return end
    local cw, ch = ClampMeterSize(w, h)
    if not cw or not ch then return end
    SaveMeterSize(key, cw, ch)
    local target = ResolveResizeTargetForKey(key)
    if target then
        SecureCallMethod(target, "SetSize", cw, ch)
    end
end

---------------------------------------------------------------------------
-- AttachResizeGripsToHandle(handle, key, getResizeTarget)
-- Adds 4 corner resize grips (mint accent L-shapes) to a Layout Mode proxy
-- mover handle. The handle owns the live resize rectangle, while the meter
-- target fills the handle. Mouseup saves the new dimensions and records the
-- handle center through Layout Mode's normal pending-position path.
-- Idempotent.
---------------------------------------------------------------------------
local GRIP_CORNERS = { "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT" }

local function GetCursorInUIParent()
    local x, y = GetCursorPosition()
    local scale = UIParent and UIParent:GetEffectiveScale() or 1
    if not x or not y or not scale or scale == 0 then return nil, nil end
    return x / scale, y / scale
end

local function GetResizeEdges(handle, target)
    local left, right, top, bottom
    if handle then
        left, right, top, bottom = handle:GetLeft(), handle:GetRight(), handle:GetTop(), handle:GetBottom()
    end
    if (not left or not right or not top or not bottom) and target then
        left, right, top, bottom = target:GetLeft(), target:GetRight(), target:GetTop(), target:GetBottom()
    end
    if not left or not right or not top or not bottom then return nil end
    return left, right, top, bottom
end

local function ApplyResizeRect(handle, target, left, bottom, width, height)
    local w, h = ClampMeterSize(width, height)
    if not w or not h then return end

    left = math.floor(left + 0.5)
    bottom = math.floor(bottom + 0.5)

    handle:ClearAllPoints()
    handle:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left, bottom)
    handle:SetSize(w, h)

    if not target then return end
    SecureCallMethod(target, "SetSize", w, h)

    -- Layout Mode normally reparents proxy targets into the handle. When
    -- resize runs before that deferred step, keep the target aligned manually.
    local targetParent = target.GetParent and target:GetParent() or nil
    if handle._savedTargetParent or targetParent == handle then
        pcall(target.ClearAllPoints, target)
        pcall(target.SetAllPoints, target, handle)
    else
        local pw, ph = UIParent:GetWidth() or 0, UIParent:GetHeight() or 0
        pcall(target.ClearAllPoints, target)
        pcall(target.SetPoint, target, "CENTER", UIParent, "CENTER",
            left + (w / 2) - (pw / 2),
            bottom + (h / 2) - (ph / 2))
    end
end

local function UpdateGripResize(handle)
    local state = handle and handle._qdmResizeState
    if not state then return end

    local cursorX, cursorY = GetCursorInUIParent()
    if not cursorX or not cursorY then return end

    local left, right, top, bottom = state.left, state.right, state.top, state.bottom
    if state.resizeLeft then
        left = cursorX
    else
        right = cursorX
    end
    if state.resizeTop then
        top = cursorY
    else
        bottom = cursorY
    end

    local width = right - left
    if width < METER_RESIZE_MIN_W then
        if state.resizeLeft then
            left = right - METER_RESIZE_MIN_W
        else
            right = left + METER_RESIZE_MIN_W
        end
    elseif width > METER_RESIZE_MAX_W then
        if state.resizeLeft then
            left = right - METER_RESIZE_MAX_W
        else
            right = left + METER_RESIZE_MAX_W
        end
    end

    local height = top - bottom
    if height < METER_RESIZE_MIN_H then
        if state.resizeTop then
            top = bottom + METER_RESIZE_MIN_H
        else
            bottom = top - METER_RESIZE_MIN_H
        end
    elseif height > METER_RESIZE_MAX_H then
        if state.resizeTop then
            top = bottom + METER_RESIZE_MAX_H
        else
            bottom = top - METER_RESIZE_MAX_H
        end
    end

    local startWidth = state.right - state.left
    local startHeight = state.top - state.bottom
    if math.abs((right - left) - startWidth) > 0.5
        or math.abs((top - bottom) - startHeight) > 0.5
        or math.abs(left - state.left) > 0.5
        or math.abs(bottom - state.bottom) > 0.5 then
        state.didResize = true
    end

    ApplyResizeRect(handle, state.target, left, bottom, right - left, top - bottom)
end

local function GetAccentRGB()
    local GUI = _G.QUI and _G.QUI.GUI
    local accent = GUI and GUI.Colors and GUI.Colors.accent
    if accent then
        return accent[1], accent[2], accent[3]
    end
    return 0.204, 0.827, 0.6
end

local function MakeResizeGrip(handle, corner)
    local grip = CreateFrame("Button", nil, handle)
    grip:SetSize(18, 18)
    grip:SetFrameLevel((handle:GetFrameLevel() or 100) + 10)
    grip:EnableMouse(true)

    -- Position grip at the requested corner with a 2px inset
    local insetX = (corner == "TOPLEFT" or corner == "BOTTOMLEFT") and 2 or -2
    local insetY = (corner == "TOPLEFT" or corner == "TOPRIGHT") and -2 or 2
    grip:ClearAllPoints()
    grip:SetPoint(corner, handle, corner, insetX, insetY)

    -- L-shape accent bars pointing inward.
    local r, g, b = GetAccentRGB()
    local barH = grip:CreateTexture(nil, "OVERLAY")
    barH:SetColorTexture(r, g, b, 0.9)
    barH:SetSize(16, 3)
    barH:SetPoint(corner, 0, 0)

    local barV = grip:CreateTexture(nil, "OVERLAY")
    barV:SetColorTexture(r, g, b, 0.9)
    barV:SetSize(3, 16)
    barV:SetPoint(corner, 0, 0)

    local hl = grip:CreateTexture(nil, "HIGHLIGHT")
    hl:SetColorTexture(1, 1, 1, 0.35)
    hl:SetAllPoints()
    hl:SetBlendMode("ADD")

    return grip
end

AttachResizeGripsToHandle = function(handle, key, getResizeTarget)
    if not handle or handle._qdmGripsAttached then return end
    handle._qdmGripsAttached = true

    local function StartGripResize(corner)
        if InCombatLockdown() then return end
        local target = getResizeTarget()
        if not target then return end
        local left, right, top, bottom = GetResizeEdges(handle, target)
        if not left or not right or not top or not bottom then return end

        if GameTooltip then GameTooltip:Hide() end
        handle._resizing = true
        handle._resizeTarget = target
        handle._qdmResizeState = {
            target = target,
            left = left,
            right = right,
            top = top,
            bottom = bottom,
            resizeLeft = corner:find("LEFT", 1, true) ~= nil,
            resizeTop = corner:find("TOP", 1, true) ~= nil,
        }

        -- Resize the Layout Mode handle itself and keep the meter filled to
        -- it. Resizing the Blizzard window directly lets corner sizing move
        -- the window center while the handle stays behind.
        handle:SetScript("OnUpdate", function(self)
            if not self._resizing or not self._qdmResizeState then
                self:SetScript("OnUpdate", nil)
                return
            end
            UpdateGripResize(self)
        end)
    end

    local function StopGripResize()
        local resizeState = handle._qdmResizeState
        if handle._qdmResizeState then
            UpdateGripResize(handle)
        end

        if resizeState and resizeState.didResize then
            local w, h = handle:GetWidth(), handle:GetHeight()
            if type(w) == "number" and type(h) == "number" and w > 0 and h > 0 then
                SaveMeterSize(key, w, h)
            end

            if _G.QUI_LayoutModeSaveCurrentHandlePosition then
                _G.QUI_LayoutModeSaveCurrentHandlePosition(key)
            elseif _G.QUI_LayoutModeMarkChanged then
                _G.QUI_LayoutModeMarkChanged()
            end
        end

        handle._resizing = false
        handle._resizeTarget = nil
        handle._qdmResizeState = nil
        handle:SetScript("OnUpdate", nil)
    end

    for _, corner in ipairs(GRIP_CORNERS) do
        local grip = MakeResizeGrip(handle, corner)
        grip:SetScript("OnEnter", function(self)
            if GameTooltip then
                GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
                GameTooltip:SetText("Drag to resize")
                GameTooltip:Show()
            end
        end)
        grip:SetScript("OnLeave", function()
            if GameTooltip then GameTooltip:Hide() end
        end)
        grip:SetScript("OnMouseDown", function(_, button)
            if button == "LeftButton" then StartGripResize(corner) end
        end)
        grip:SetScript("OnMouseUp", function(_, button)
            if button == "LeftButton" then StopGripResize() end
        end)
    end
end

---------------------------------------------------------------------------
-- InstallEditModeSuppression
-- Make the damage meter invisible to Blizzard Edit Mode. The meter never
-- enters editing state, the "Show Damage Meter" checkbox is hidden from
-- Edit Mode's Account Settings panel, and Edit Mode preset writes to the
-- meter are dropped (our shadow values win).
---------------------------------------------------------------------------
local editModeSuppressed = false

local function InstallEditModeSuppression()
    if editModeSuppressed then return end
    if not EditModeManagerFrame then return end
    if not EditModeAccountSettingsMixin then return end
    editModeSuppressed = true

    -- 1. Force RefreshDamageMeter to always run the off path. Hook the FRAME
    --    instance, not the mixin: Blizzard's Mixin() copies methods onto the
    --    frame at creation time, so a hooksecurefunc on EditModeAccountSettingsMixin
    --    never fires when EditModeManagerFrame.AccountSettings:RefreshDamageMeter
    --    is called.
    if EditModeManagerFrame.AccountSettings and EditModeManagerFrame.AccountSettings.RefreshDamageMeter then
        hooksecurefunc(EditModeManagerFrame.AccountSettings, "RefreshDamageMeter", function(self)
            if not self.GetDamageMeterFrames then return end
            for _, frame in ipairs(self:GetDamageMeterFrames()) do
                if frame.SetIsEditing then SecureCallMethod(frame, "SetIsEditing", false) end
                if frame.ClearHighlight then SecureCallMethod(frame, "ClearHighlight") end
            end
        end)
    end

    -- 2. Hide the "Show Damage Meter" checkbox in Edit Mode's Account Settings panel.
    local function HideDamageMeterCheckbox()
        local panel = EditModeManagerFrame and EditModeManagerFrame.AccountSettings
        local cb = panel and panel.settingsCheckButtons and panel.settingsCheckButtons.DamageMeter
        if cb and cb.Hide then SecureCallMethod(cb, "Hide") end
    end
    HideDamageMeterCheckbox()
    if EditModeManagerFrame.AccountSettings and EditModeManagerFrame.AccountSettings.LayoutSettings then
        hooksecurefunc(EditModeManagerFrame.AccountSettings, "LayoutSettings", HideDamageMeterCheckbox)
    end

    -- 3. Drop Edit Mode preset writes; our shadow wins. Defer one frame so
    --    Blizzard's path completes first, then re-apply our shadow.
    if EditModeManagerFrame.OnSystemSettingChange then
        hooksecurefunc(EditModeManagerFrame, "OnSystemSettingChange", function(_, systemFrame, _setting, _value)
            if systemFrame == _G.DamageMeter then
                C_Timer.After(0, function()
                    if ApplyShadowValuesToBlizzard then ApplyShadowValuesToBlizzard() end
                end)
            end
        end)
    end

    -- 4. Suppress Blizzard Edit Mode mover/selection overlay on _G.DamageMeter.
    --    Mirrors QUICore:HookEditMode (core/main.lua) for QUI-replaced frames.
    --
    --    CRITICAL: Hook the FRAME INSTANCE, not the mixin. Blizzard's Mixin()
    --    copies methods directly onto the frame at creation time, so a hook on
    --    EditModeSystemMixin.HighlightSystem never fires when _G.DamageMeter:
    --    HighlightSystem() is called — the frame holds its own (pre-hook) copy.
    --
    --    SuppressMeterSelection clears state via ClearHighlight, hides the
    --    Selection overlay, and unregisters from EditModeMagnetismManager so
    --    other Edit Mode frames can't snap to the meter. Do not write
    --    defaultHideSelection onto the manager frame; it would taint the same
    --    table that later carries restricted combat-session values.
    if _G.DamageMeter then
        local function SuppressMeterSelection()
            local mgr = _G.DamageMeter
            if not mgr then return end
            if mgr.ClearHighlight then
                SecureCallMethod(mgr, "ClearHighlight")
            end
            if mgr.Selection and mgr.Selection.Hide then
                SecureCallMethod(mgr.Selection, "Hide")
            end
            if EditModeMagnetismManager and EditModeMagnetismManager.UnregisterFrame then
                SecureCallMethod(EditModeMagnetismManager, "UnregisterFrame", mgr)
            end
        end

        if _G.DamageMeter.HighlightSystem then
            hooksecurefunc(_G.DamageMeter, "HighlightSystem", SuppressMeterSelection)
        end
        if _G.DamageMeter.SelectSystem then
            hooksecurefunc(_G.DamageMeter, "SelectSystem", SuppressMeterSelection)
        end

        -- Deferred clear on Edit Mode entry: Blizzard's ShowSystemSelections
        -- iterates registered systems via secureexecuterange after EnterEditMode
        -- returns, so we re-clear on the next frame to catch that state.
        if EditModeManagerFrame.EnterEditMode then
            hooksecurefunc(EditModeManagerFrame, "EnterEditMode", function()
                C_Timer.After(0, SuppressMeterSelection)
            end)
        end

        -- Initial clear in case Edit Mode is already active when this installs.
        SuppressMeterSelection()

        -- 5. Re-apply QUI-saved meter size after Blizzard's UpdateSystem runs.
        --    Blizzard's EditModeManagerFrame:UpdateSystem -> UpdateSystemSettingFrameWidth/Height
        --    overwrites the manager's size from Blizzard's saved Edit Mode layout. We
        --    suppress Edit Mode UI but Blizzard's UpdateSystem still fires on layout
        --    refresh. Hook the meter-specific size setters and re-assert our value.
        if _G.DamageMeter.UpdateSystemSettingFrameWidth then
            hooksecurefunc(_G.DamageMeter, "UpdateSystemSettingFrameWidth", function(self)
                local w, _ = LoadMeterSize("damageMeter_primary")
                if w and not InCombatLockdown() then
                    SecureCallMethod(self, "SetWidth", w)
                end
            end)
        end
        if _G.DamageMeter.UpdateSystemSettingFrameHeight then
            hooksecurefunc(_G.DamageMeter, "UpdateSystemSettingFrameHeight", function(self)
                local _, h = LoadMeterSize("damageMeter_primary")
                if h and not InCombatLockdown() then
                    SecureCallMethod(self, "SetHeight", h)
                end
            end)
        end
    end
end

---------------------------------------------------------------------------
-- SETTING_KEYS
-- The 11 shadowed setting keys, in order. Used by SnapshotFromBlizzard and
-- ApplyShadowValuesToBlizzard to iterate. Order matters only for predictable
-- iteration; semantically the keys are independent.
---------------------------------------------------------------------------
local SETTING_KEYS = {
    "enabled", "visibility", "style", "numberDisplay",
    "useClassColor", "showBarIcons", "barHeight",
    "barSpacing", "textSize", "windowAlpha", "backgroundAlpha",
}

local function UpdateBlizzardDamageMeterSetting(key, value)
    local mgr = _G.DamageMeter
    local settingEnum = Enum and Enum.EditModeDamageMeterSetting
    if not (mgr and settingEnum and mgr.UpdateSystemSettingValue) then
        return false
    end

    local setting, displayValue
    if key == "visibility" then
        setting, displayValue = settingEnum.Visibility, value
    elseif key == "style" then
        setting, displayValue = settingEnum.Style, value
    elseif key == "numberDisplay" then
        setting, displayValue = settingEnum.Numbers, value
    elseif key == "useClassColor" then
        setting, displayValue = settingEnum.ShowClassColor, value and 1 or 0
    elseif key == "showBarIcons" then
        setting, displayValue = settingEnum.ShowSpecIcon, value and 1 or 0
    elseif key == "barHeight" then
        setting, displayValue = settingEnum.BarHeight, value
    elseif key == "barSpacing" then
        setting, displayValue = settingEnum.Padding, value
    elseif key == "textSize" then
        setting, displayValue = settingEnum.TextSize, value
    elseif key == "windowAlpha" then
        setting, displayValue = settingEnum.Transparency, value
    elseif key == "backgroundAlpha" then
        setting, displayValue = settingEnum.BackgroundTransparency, value
    else
        return false
    end

    if setting == nil then return false end
    SecureCallMethod(mgr, "UpdateSystemSettingValue", setting, displayValue)
    return true
end

---------------------------------------------------------------------------
-- SnapshotFromBlizzard
-- Read every Blizzard meter value into db.profile.damageMeter. Called once
-- per character at module init (gated by g._initialized in T6). Subsequent
-- loads trust the shadow.
---------------------------------------------------------------------------
local function SnapshotFromBlizzard()
    local g = GetSettings()
    if not g then return end
    if not _G.DamageMeter then return end

    g.enabled         = CVarCallbackRegistry and CVarCallbackRegistry.GetCVarValueBool
                            and CVarCallbackRegistry:GetCVarValueBool("damageMeterEnabled") or false
    g.visibility      = _G.DamageMeter.visibility or (Enum and Enum.DamageMeterVisibility and Enum.DamageMeterVisibility.Always) or 0
    g.style           = _G.DamageMeter.GetStyle and _G.DamageMeter:GetStyle() or g.style
    g.numberDisplay   = _G.DamageMeter.GetNumberDisplayType and _G.DamageMeter:GetNumberDisplayType() or g.numberDisplay
    g.useClassColor   = _G.DamageMeter.ShouldUseClassColor and _G.DamageMeter:ShouldUseClassColor() and true or false
    g.showBarIcons    = _G.DamageMeter.ShouldShowBarIcons and _G.DamageMeter:ShouldShowBarIcons() and true or false
    g.barHeight       = _G.DamageMeter.GetBarHeight and _G.DamageMeter:GetBarHeight() or g.barHeight
    g.barSpacing      = _G.DamageMeter.GetBarSpacing and _G.DamageMeter:GetBarSpacing() or g.barSpacing
    g.textSize        = _G.DamageMeter.GetTextSize and _G.DamageMeter:GetTextSize() or g.textSize
    g.windowAlpha     = _G.DamageMeter.GetWindowAlpha and (_G.DamageMeter:GetWindowAlpha() * 100) or g.windowAlpha
    g.backgroundAlpha = _G.DamageMeter.GetBackgroundAlpha and (_G.DamageMeter:GetBackgroundAlpha() * 100) or g.backgroundAlpha
end

---------------------------------------------------------------------------
-- WriteOneToBlizzard(key, value)
-- Push a single shadow value to Blizzard via the documented setter. Combat
-- lockdown queues the write to be flushed at PLAYER_REGEN_ENABLED.
---------------------------------------------------------------------------
local function WriteOneToBlizzard(key, value)
    if syncInProgress then return end
    syncInProgress = true

    if InCombatLockdown() then
        pendingCombatWrites[key] = value
        syncInProgress = false
        return
    end

    if not _G.DamageMeter then
        syncInProgress = false
        return
    end

    if key == "enabled" then
        SecureCallFunction(SetCVar, "damageMeterEnabled", value and "1" or "0")
    elseif not UpdateBlizzardDamageMeterSetting(key, value) then
        if key == "style" then
            SecureCallMethod(_G.DamageMeter, "SetStyle", value)
        elseif key == "numberDisplay" then
            SecureCallMethod(_G.DamageMeter, "SetNumberDisplayType", value)
        elseif key == "useClassColor" then
            SecureCallMethod(_G.DamageMeter, "SetUseClassColor", value and true or false)
        elseif key == "showBarIcons" then
            SecureCallMethod(_G.DamageMeter, "SetShowBarIcons", value and true or false)
        elseif key == "barHeight" then
            SecureCallMethod(_G.DamageMeter, "SetBarHeight", value)
        elseif key == "barSpacing" then
            SecureCallMethod(_G.DamageMeter, "SetBarSpacing", value)
        elseif key == "textSize" then
            SecureCallMethod(_G.DamageMeter, "SetTextSize", value)
        elseif key == "windowAlpha" then
            SecureCallMethod(_G.DamageMeter, "SetWindowAlpha", value / 100)
        elseif key == "backgroundAlpha" then
            SecureCallMethod(_G.DamageMeter, "SetBackgroundAlpha", value / 100)
        end
    end

    syncInProgress = false
end

---------------------------------------------------------------------------
-- ApplyShadowValuesToBlizzard
-- Push every shadow value to Blizzard. Used by Registry refresh callback
-- and by Edit Mode preset-write defense (see InstallEditModeSuppression).
---------------------------------------------------------------------------
ApplyShadowValuesToBlizzard = function()
    local g = GetSettings()
    if not g then return end
    for _, key in ipairs(SETTING_KEYS) do
        if g[key] ~= nil then WriteOneToBlizzard(key, g[key]) end
    end
end

---------------------------------------------------------------------------
-- Combat deferral: flush queued writes when leaving combat.
---------------------------------------------------------------------------
local combatFlushFrame = CreateFrame("Frame")
combatFlushFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
combatFlushFrame:SetScript("OnEvent", function()
    if next(pendingCombatWrites) then
        local queue = pendingCombatWrites
        pendingCombatWrites = {}
        for key, value in pairs(queue) do
            WriteOneToBlizzard(key, value)
        end
    end
end)

---------------------------------------------------------------------------
-- InstallMixinHooks
-- Hook Blizzard mixin methods so every row instance — current and future —
-- picks up the QUI skin and survives Blizzard's re-anchor / re-alpha cycles.
---------------------------------------------------------------------------
local function InstallMixinHooks()
    InstallSecretSafeEntryOverrides()

    if mixinsHooked then return end
    mixinsHooked = true

    -- Per-row first-time setup: SessionWindow:SetupEntry(frame) is called on
    -- every row when it's acquired from the WowScrollBoxList pool.
    if DamageMeterSessionWindowMixin and DamageMeterSessionWindowMixin.SetupEntry then
        hooksecurefunc(DamageMeterSessionWindowMixin, "SetupEntry", function(_, frame)
            -- Patch before any Blizzard Init reads the entry's display methods.
            -- SetupEntry fires once per pool acquisition, before InitEntry/Init,
            -- so synchronously swapping UpdateName/UpdateValue/UpdateIcon to our
            -- SecretSafe* version here keeps the stock comparison off the path
            -- when secret source names land. Done unconditionally — even with
            -- the visual skin disabled, our hooks taint the meter pipeline and
            -- the stock comparison still trips.
            PatchEntryFrameDisplayMethods(frame)
            if not IsModuleEnabled() then return end
            DeferSkinRow(frame)
        end)
    end

    -- Per-row data refresh: cheap re-skin point in case our skin sentinel got cleared.
    if DamageMeterSessionWindowMixin and DamageMeterSessionWindowMixin.InitEntry then
        hooksecurefunc(DamageMeterSessionWindowMixin, "InitEntry", function(_, frame)
            -- Defensive re-patch: if a pool entry somehow slipped through with
            -- stock methods (acquired before our SetupEntry hook installed),
            -- the next Init cycle will at least run our SecretSafe* version.
            PatchEntryFrameDisplayMethods(frame)
            if not IsModuleEnabled() then return end
            DeferSkinRow(frame)
        end)
    end

    -- UpdateBackground re-asserts background-region alpha — re-strip after.
    if DamageMeterEntryMixin and DamageMeterEntryMixin.UpdateBackground then
        hooksecurefunc(DamageMeterEntryMixin, "UpdateBackground", function(self)
            if not IsModuleEnabled() then return end
            DeferStripRowBackground(self)
        end)
    end

    -- UpdateStyle re-anchors the row for Default / Bordered / FullBackground / Thin.
    -- Re-skin so our backdrop tracks the new geometry.
    if DamageMeterEntryMixin and DamageMeterEntryMixin.UpdateStyle then
        hooksecurefunc(DamageMeterEntryMixin, "UpdateStyle", function(self)
            if not IsModuleEnabled() then return end
            DeferSkinRow(self, true)
        end)
    end

    -- Skin the breakdown popup (SourceWindow) on first show.
    if DamageMeterSessionWindowMixin and DamageMeterSessionWindowMixin.ShowSourceWindow then
        hooksecurefunc(DamageMeterSessionWindowMixin, "ShowSourceWindow", function(self)
            if not IsModuleEnabled() then return end
            DeferDamageMeterWork(function(window)
                if not IsModuleEnabled() then return end
                local popup = window.GetSourceWindow and window:GetSourceWindow() or nil
                if popup then SkinSourceWindow(popup) end
            end, self)
        end)
    end
end

---------------------------------------------------------------------------
-- Forward declarations (filled in by later tasks)
---------------------------------------------------------------------------
local function ApplyAll() end
local function RefreshAll() end
local function RemoveAllSkin() end
local function InstallMeterHooks() end
local function ScanExistingWindows() end

InstallMeterHooks = function()
    local mgr = ResolveManager()
    if not mgr then return end

    -- New window detection: SetupSessionWindow runs whenever a session window
    -- is created/reused (primary at startup, secondaries via "Show New Window").
    if type(mgr.SetupSessionWindow) == "function" then
        hooksecurefunc(mgr, "SetupSessionWindow", function(self, idx, data)
            if data and data.sessionWindow then
                local sessionWindow = data.sessionWindow

                -- Synchronous taint-safety patches. Blizzard can fire
                -- Refresh → ShowLocalPlayerEntry → InitEntry → Init →
                -- (stock) UpdateName in the SAME frame as SetupSessionWindow,
                -- so deferring these patches via DeferDamageMeterWork would
                -- be too late: the first stock UpdateName would already have
                -- compared a secret string and faulted. Setting Lua fields
                -- on a frame is not a protected operation, so this is safe
                -- in combat. Idempotent on re-entry.
                PatchSessionWindowDisplayMethods(sessionWindow)
                local localEntry = ResolveLocalPlayerEntry(sessionWindow)
                if localEntry then
                    PatchEntryFrameDisplayMethods(localEntry)
                end
                if sessionWindow.ForEachEntryFrame then
                    sessionWindow:ForEachEntryFrame(PatchEntryFrameDisplayMethods)
                end

                if not IsModuleEnabled() then return end
                DeferDamageMeterWork(function(window, windowIndex)
                    if not IsModuleEnabled() then return end
                    EnsureWindowSkinned(window)
                    -- Re-assert lock unconditionally: Blizzard re-enables SetMovable on every
                    -- SetupSessionWindow call (line 314 of DamageMeter.lua); EnsureWindowSkinned
                    -- early-exits on already-skinned windows so we can't rely on the call inside.
                    ForceLockWindow(window)

                    -- For secondary windows, Blizzard hardcoded SetPoint("TOPLEFT", UIParent, ...)
                    -- on every setup. Re-apply our QUI saved anchor after Blizzard finishes.
                    -- Primary inherits manager position via TOPLEFT/BOTTOMRIGHT anchors set by
                    -- Blizzard, so it needs no re-apply here.
                    if windowIndex and windowIndex ~= 1 and _G.QUI_ApplyFrameAnchor and not InCombatLockdown() then
                        local key = LayoutModeKeyForWindow(window)
                        _G.QUI_ApplyFrameAnchor(key)
                    end
                end, sessionWindow, idx)
            end
        end)
    end

    -- Style / class-color / icon visibility changes propagate to all windows.
    -- Re-skin so anchors and backgrounds re-apply.
    local function refreshAllWindows()
        if not IsModuleEnabled() then return end
        DeferDamageMeterWork(function()
            if not IsModuleEnabled() then return end
            for _, w in ipairs(ResolveAllWindows()) do
                EnsureWindowSkinned(w)
            end
        end)
    end
    if type(mgr.OnStyleChanged) == "function" then
        hooksecurefunc(mgr, "OnStyleChanged", refreshAllWindows)
    end
    if type(mgr.OnUseClassColorChanged) == "function" then
        hooksecurefunc(mgr, "OnUseClassColorChanged", refreshAllWindows)
    end
    if type(mgr.OnShowBarIconsChanged) == "function" then
        hooksecurefunc(mgr, "OnShowBarIconsChanged", refreshAllWindows)
    end
end

RefreshAll = function()
    if not IsModuleEnabled() then
        RemoveAllSkin()
        return
    end
    local g = GetGeneralSettings()
    local sr, sg, sb, sa, bgr, bgg, bgb, bga = SkinBase.GetSkinColors(g, "damageMeter")

    for window in pairs(trackedWindows) do
        local backdrop = SkinBase.GetBackdrop(window)
        if backdrop then
            backdrop:SetBackdropColor(bgr, bgg, bgb, bga)
            backdrop:SetBackdropBorderColor(sr, sg, sb, sa)
        end
        StyleDamageMeterScrollBar(ResolveWindowScrollBar(window), sr, sg, sb)
        -- Re-skin every visible row.
        if window.ForEachEntryFrame then
            window:ForEachEntryFrame(function(frame)
                DeferSkinRow(frame, true)
            end)
        end
    end

    for popup in pairs(trackedPopups) do
        local backdrop = SkinBase.GetBackdrop(popup)
        if backdrop then
            backdrop:SetBackdropColor(bgr, bgg, bgb, bga)
            backdrop:SetBackdropBorderColor(sr, sg, sb, sa)
        end
        StyleDamageMeterScrollBar(ResolvePopupScrollBar(popup), sr, sg, sb)
    end
end

RemoveAllSkin = function()
    -- Hide our backdrops; restore stripped chrome alpha.
    for window in pairs(trackedWindows) do
        local backdrop = SkinBase.GetBackdrop(window)
        if backdrop then backdrop:Hide() end
        RestoreDamageMeterScrollBar(ResolveWindowScrollBar(window))

        -- Restore stock chrome.
        if window.Header then window.Header:SetAlpha(1) end
        local mc = window.MinimizeContainer
        if mc then
            -- Background starts at alpha=0 in XML; restoring to current Blizzard-managed value
            -- is tricky — leave at 0, Blizzard's UpdateBackground will re-assert if needed.
            if window.UpdateBackground then SecureCallMethod(window, "UpdateBackground") end
        end

        -- Per-row: hide our backdrops; do NOT restore stock backgrounds because
        -- the next Blizzard UpdateBackground re-asserts them automatically.
        if window.ForEachEntryFrame then
            window:ForEachEntryFrame(function(frame)
                local rb = SkinBase.GetFrameData(frame, "qdmRowBackdrop")
                if rb then rb:Hide() end
                SkinBase.SetFrameData(frame, "qdmRowSkinned", nil)
                if frame.UpdateBackground then SecureCallMethod(frame, "UpdateBackground") end
            end)
        end
    end

    -- Popups
    for popup in pairs(trackedPopups) do
        local backdrop = SkinBase.GetBackdrop(popup)
        if backdrop then backdrop:Hide() end
        RestoreDamageMeterScrollBar(ResolvePopupScrollBar(popup))
        if popup.Background then popup.Background:SetAlpha(1) end
    end

    -- Note: hooksecurefunc cannot be uninstalled. Hooks no-op via IsModuleEnabled().
    -- Note: font/text-color changes do not auto-revert; /reload required for full
    -- pre-skin appearance. Documented limitation per spec "minimal toggle UX".
end

ScanExistingWindows = function()
    if not IsModuleEnabled() then return end
    for _, w in ipairs(ResolveAllWindows()) do
        EnsureWindowSkinned(w)
    end
end

---------------------------------------------------------------------------
-- PatchAllExistingEntryFrames
-- Synchronous, taint-safety-only pass over every existing session window:
-- patches each window's SetSessionDuration plus every entry-frame instance
-- (LocalPlayerEntry + visible pool entries) so subsequent stock Refresh /
-- ShowLocalPlayerEntry / InitEntry / Init calls find our SecretSafe*
-- methods on the instance instead of the stock compare-then-cache bodies.
--
-- Distinct from EnsureWindowSkinned: that function does this AND visual
-- skin work (backdrops, dropdowns, layout-mode registration), which depends
-- on settings being loaded and isn't time-critical for taint. This one is
-- minimal so it can run immediately at ADDON_LOADED, before the 0.1s
-- positioning timer that gates EnsureWindowSkinned.
---------------------------------------------------------------------------
local function PatchAllExistingEntryFrames()
    local mgr = ResolveManager()
    if not mgr or type(mgr.windowDataList) ~= "table" then return end
    for _, data in pairs(mgr.windowDataList) do
        local window = data and data.sessionWindow
        if window then
            PatchSessionWindowDisplayMethods(window)
            local localEntry = ResolveLocalPlayerEntry(window)
            if localEntry then
                PatchEntryFrameDisplayMethods(localEntry)
            end
            if window.ForEachEntryFrame then
                window:ForEachEntryFrame(PatchEntryFrameDisplayMethods)
            end
        end
    end
end

---------------------------------------------------------------------------
-- ReapplyAnchorsForExistingWindows
-- On /reload, _G.DamageMeter:OnLoad runs RestoreWindowData → SetupSessionWindow
-- for every saved secondary BEFORE our ADDON_LOADED handler fires (we delay
-- 0.1s before installing hooks). The hooksecurefunc on SetupSessionWindow only
-- catches FUTURE calls, so the initial restoration runs unhooked and secondaries
-- end up at Blizzard's hardcoded TOPLEFT-relative positions (DamageMeter.lua:308–310).
--
-- After ScanExistingWindows has registered anchor targets for all current
-- windows, re-apply the QUI saved anchor for non-primary windows so positions
-- survive /reload. Primary inherits its position from _G.DamageMeter (which
-- carries its own anchor independently).
---------------------------------------------------------------------------
local function ReapplyAnchorsForExistingWindows()
    if not IsModuleEnabled() then return end
    if not _G.QUI_ApplyFrameAnchor then return end
    if InCombatLockdown() then return end
    for _, w in ipairs(ResolveAllWindows()) do
        local idx = w.GetSessionWindowIndex and w:GetSessionWindowIndex() or w.sessionWindowIndex
        if idx and idx ~= 1 then
            local key = LayoutModeKeyForWindow(w)
            _G.QUI_ApplyFrameAnchor(key)
        end
    end
end

ApplyAll = ScanExistingWindows

---------------------------------------------------------------------------
-- Public API (live refresh + introspection)
---------------------------------------------------------------------------
_G.QUI_RefreshDamageMeterSkin = function() RefreshAll() end
_G.QUI_ApplyDamageMeterSkin   = function() ApplyAll() end
_G.QUI_RemoveDamageMeterSkin  = function() RemoveAllSkin() end

-- Stage 2 public API: settings sync and refresh.
_G.QUI_DamageMeter_SnapshotFromBlizzard = function() SnapshotFromBlizzard() end
_G.QUI_DamageMeter_ApplyToBlizzard      = function()
    if ApplyShadowValuesToBlizzard then ApplyShadowValuesToBlizzard() end
end
_G.QUI_RefreshDamageMeterSettings       = function()
    if ApplyShadowValuesToBlizzard then ApplyShadowValuesToBlizzard() end
end

---------------------------------------------------------------------------
-- Settings.Registry features for the meter movers.
-- Without these, right-clicking a Layout Mode handle for the damage meter
-- shows an empty settings panel — Layout Mode looks up the position-anchor
-- provider via Settings.Registry:GetFeatureByMoverKey(key), and finds none.
-- Mirrors the bulk position-only registration in modules/utility/layoutmode_utils.lua.
---------------------------------------------------------------------------
do
    local Settings = ns.Settings
    local Registry = Settings and Settings.Registry
    local Schema = Settings and Settings.Schema
    local RenderAdapters = Settings and Settings.RenderAdapters

    if Registry and Schema and RenderAdapters
        and type(Registry.RegisterFeature) == "function"
        and type(Schema.Feature) == "function" then
        for _, key in ipairs({
            "damageMeter_primary",
            "damageMeter_extra_2",
            "damageMeter_extra_3",
        }) do
            local moverKey = key
            Registry:RegisterFeature(Schema.Feature({
                id = key,
                moverKey = moverKey,
                render = {
                    layout = function(host, options)
                        local providerKey = (options and options.providerKey) or moverKey
                        local U = ns.QUI_LayoutMode_Utils
                        if not host or not U
                            or type(U.BuildPositionCollapsible) ~= "function"
                            or type(U.BuildSizeCollapsible) ~= "function"
                            or type(U.StandardRelayout) ~= "function" then
                            return RenderAdapters.RenderPositionOnly(host, providerKey)
                        end

                        local prevPosOnly = U._layoutModePositionOnly
                        U._layoutModePositionOnly = false
                        local sections = {}
                        local function relayout() U.StandardRelayout(host, sections) end
                        local ok, err = xpcall(function()
                            U.BuildPositionCollapsible(host, providerKey, nil, sections, relayout)
                            U.BuildSizeCollapsible(host, {
                                getSize = function() return MeterSliderGetSize(providerKey) end,
                                setSize = function(w, h) MeterSliderSetSize(providerKey, w, h) end,
                                minW = METER_RESIZE_MIN_W, maxW = METER_RESIZE_MAX_W,
                                minH = METER_RESIZE_MIN_H, maxH = METER_RESIZE_MAX_H,
                                widthDescription  = "Damage meter window width in pixels. Persisted in your QUI profile and applied on login.",
                                heightDescription = "Damage meter window height in pixels. Persisted in your QUI profile and applied on login.",
                            }, sections, relayout)
                            relayout()
                        end, function(msg) return msg end)
                        U._layoutModePositionOnly = prevPosOnly
                        if not ok and geterrorhandler then geterrorhandler()(err) end
                        return host:GetHeight()
                    end,
                },
            }))
        end
    end
end

---------------------------------------------------------------------------
-- Registry hookup for live profile refresh
---------------------------------------------------------------------------
if ns.Registry and ns.Registry.Register then
    ns.Registry:Register("skinDamageMeter", {
        refresh = _G.QUI_RefreshDamageMeterSkin,
        priority = 80,
        group = "skinning",
        importCategories = { "skinning", "theme" },
    })
end

if ns.Registry and ns.Registry.Register then
    ns.Registry:Register("damageMeterSettings", {
        refresh = _G.QUI_RefreshDamageMeterSettings,
        priority = 75,
        group = "skinning",
        importCategories = { "skinning", "theme" },
    })
end

---------------------------------------------------------------------------
-- Init: hybrid (ADDON_LOADED for Blizzard_DamageMeter + PLAYER_ENTERING_WORLD)
---------------------------------------------------------------------------
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("ADDON_LOADED")
initFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
initFrame:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == "Blizzard_DamageMeter" then
        -- Taint-safety hooks + existing-instance patch run IMMEDIATELY, NOT
        -- behind the 0.1s positioning timer below. Race we hit otherwise:
        -- DamageMeter:OnLoad already ran during this same addon-load tick
        -- (it's how the manager + saved session windows + their
        -- LocalPlayerEntry XML children come into existence — Mixin() copies
        -- the stock UpdateName onto each entry instance at frame creation).
        -- A damage event landing inside our 0.1s delay would call stock
        -- UpdateName on those un-patched instances; the very first call
        -- writes its `text` (potentially secret) into `self.nameText`, and
        -- from that point on every subsequent compare faults on the cached
        -- secret. By installing the secret-safety patches synchronously
        -- here we close that window. Visual / position work (which needs
        -- the AceDB profile and Blizzard's anchor reset to settle) can
        -- still wait on the timer.
        if not hooksInstalled then
            InstallMixinHooks()
            InstallMeterHooks()
            InstallEditModeSuppression()
            hooksInstalled = true
        end
        PatchAllExistingEntryFrames()

        C_Timer.After(0.1, function()
            ScanExistingWindows()

            -- Sync init: snapshot Blizzard's current state into the shadow exactly ONCE
            -- per character (first ever load). On subsequent loads the shadow is the
            -- source of truth and we never overwrite it.
            local g = GetSettings()
            if g and not g._initialized then
                SnapshotFromBlizzard()
                g._initialized = true
            end
            if ApplyShadowValuesToBlizzard then ApplyShadowValuesToBlizzard() end
            ReapplyAnchorsForExistingWindows()
            if ApplyAllSavedMeterSizes then ApplyAllSavedMeterSizes() end
        end)
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- Same shape as ADDON_LOADED: taint-safety patches run immediately
        -- (in case Blizzard_DamageMeter loaded before our ADDON_LOADED
        -- handler had its addon-name match), visual/position work waits.
        if not hooksInstalled and ResolveManager() then
            InstallMixinHooks()
            InstallMeterHooks()
            InstallEditModeSuppression()
            hooksInstalled = true
        end
        PatchAllExistingEntryFrames()

        C_Timer.After(0.5, function()
            ScanExistingWindows()

            -- Safety net for first-load race: if AceDB profile-load hadn't completed
            -- by ADDON_LOADED (g was nil), this branch picks up the snapshot.
            local g = GetSettings()
            if g and not g._initialized then
                SnapshotFromBlizzard()
                g._initialized = true
            end
            if ApplyShadowValuesToBlizzard then ApplyShadowValuesToBlizzard() end
            ReapplyAnchorsForExistingWindows()
            if ApplyAllSavedMeterSizes then ApplyAllSavedMeterSizes() end
        end)
    end
end)
