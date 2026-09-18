local _, ns = ...
if not (ns.Client and ns.Client.isForever) then return end

local Helpers = ns.Helpers
local SkinBase = ns.SkinBase
local SwingTimers = {}
ns.SwingTimers = SwingTimers

SwingTimers.entries = {
    { key = "swingTimerMainHand", label = ns.L["Main Hand Swing Timer"], frameName = "SwingTimerMainHandFrame" },
    { key = "swingTimerOffHand", label = ns.L["Off Hand Swing Timer"], frameName = "SwingTimerOffHandFrame" },
    { key = "swingTimerRanged", label = ns.L["Ranged Swing Timer"], frameName = "SwingTimerRangedFrame" },
}

function SwingTimers.GetSettings(key)
    local core = Helpers.GetCore()
    local profile = core and core.db and core.db.profile
    return profile and profile.swingTimers and profile.swingTimers[key]
end

function SwingTimers.IsEnabled()
    return _G.CVarCallbackRegistry:GetCVarValueBool("showSwingTimer")
end

function SwingTimers.SetEnabled(enabled)
    C_CVar.SetCVar("showSwingTimer", enabled and "1" or "0")
end

local function InNativeEditMode()
    return EditModeManagerFrame and EditModeManagerFrame:IsEditModeActive() or false
end

local function UpdateHolderAlpha(entry)
    local override = _G.OverrideActionBar
    local overridden = override and override:IsShown()
    entry.holder:SetAlpha(not entry.preview and (entry.hidden or overridden) and 0 or 1)
end

local function Apply(entry)
    if entry.applying or not entry.frame or InCombatLockdown() then return end
    local settings = SwingTimers.GetSettings(entry.key)
    if not settings then return end
    entry.applying = true
    local frame, holder = entry.frame, entry.holder
    local width = math.max(80, math.min(800, tonumber(settings.width) or 250))
    local height = math.max(8, math.min(80, tonumber(settings.height) or 20))
    local fontSize = math.max(6, math.min(32, tonumber(settings.fontSize) or 11))
    holder:SetSize(width, height)
    if not frame.ignoreFramePositionManager then
        frame:BreakFromFrameManager()
    end
    if frame:GetParent() ~= holder then frame:SetParent(holder) end
    frame:SetScaleBase(1)
    frame:SetSize(width, height)
    Helpers.BaseClearAllPoints(frame)
    Helpers.BaseSetPoint(frame, "TOPLEFT", holder, "TOPLEFT", 0, 0)
    Helpers.BaseSetPoint(frame, "BOTTOMRIGHT", holder, "BOTTOMRIGHT", 0, 0)

    local bar = frame:GetStatusBar()
    if not ns.IsSkinningEnabled or ns.IsSkinningEnabled() then
        local core = Helpers.GetCore()
        local r, g, b, a, br, bg, bb, ba = SkinBase.GetSkinColors(core.db.profile.general, "swingTimers")
        frame:GetBorder():SetColorTexture(r, g, b, a)
        local background = frame:GetBackground()
        background:SetColorTexture(br, bg, bb, ba)
        background:SetDrawLayer("BORDER")
        SkinBase.SetInsetPixelPoints(background, frame, 1)
        SkinBase.SetInsetPixelPoints(bar, frame, 1)
        bar:SetStatusBarTexture(ns.LSM:Fetch("statusbar", settings.texture))
        bar:SetStatusBarColor(SkinBase.GetSkinBarColor(core.db.profile.general, "swingTimers"))
        local pip = frame:GetStatusBarPip()
        pip:SetColorTexture(1, 1, 1, 0.8)
        pip:SetSize(2, height - 2)
        pip:ClearAllPoints()
        pip:SetPoint("TOPRIGHT", bar:GetStatusBarTexture(), "TOPRIGHT", 0, 0)
        pip:SetPoint("BOTTOMRIGHT", bar:GetStatusBarTexture(), "BOTTOMRIGHT", 0, 0)
        frame:GetTypeLabelShadow():SetAlpha(0)
        local title, time = frame:GetTypeLabel(), frame:GetTimeLabel()
        SkinBase.SkinFontString(title, { size = fontSize })
        SkinBase.SkinFontString(time, { size = fontSize })
        time:SetWidth(math.min(fontSize * 4, width * 0.45))
        title:SetWordWrap(false)
        time:SetWordWrap(false)
        time:ClearAllPoints()
        time:SetPoint("RIGHT", bar, "RIGHT", -4, 0)
        title:ClearAllPoints()
        title:SetPoint("LEFT", bar, "LEFT", 4, 0)
        title:SetPoint("RIGHT", settings.showTime and time or bar, settings.showTime and "LEFT" or "RIGHT", -4, 0)
    end
    frame:GetTypeLabel():SetShown(settings.showTitle)
    frame:GetTimeLabel():SetShown(settings.showTime)
    frame.visibility = settings.visibility
    frame:UpdateShownStateAndRegistration()
    frame:ApplyRangePresentation()
    UpdateHolderAlpha(entry)
    entry.applying = false
end

local function Register(entry, index)
    local frame = _G[entry.frameName]
    if entry.frame or not frame or not SwingTimers.GetSettings(entry.key) then return end
    entry.frame = frame
    local holder = CreateFrame("Frame", "QUI_" .. entry.key .. "Holder", UIParent)
    holder:SetPoint("CENTER", UIParent, "CENTER", 0, -180 - (index - 1) * 26)
    entry.holder = holder

    ns.QUI_LayoutMode:RegisterElement({
        key = entry.key,
        label = ns.L[entry.label],
        group = ns.L["Display"],
        order = 70 + index,
        isOwned = true,
        getFrame = function() return holder end,
        setGameplayHidden = function(hidden)
            entry.hidden = hidden
            UpdateHolderAlpha(entry)
        end,
        onOpen = function()
            entry.preview = true
            frame:SetIsInEditMode(true)
            UpdateHolderAlpha(entry)
        end,
        onClose = function()
            entry.preview = false
            frame:SetIsInEditMode(InNativeEditMode())
            UpdateHolderAlpha(entry)
        end,
    })
    _G.QUI_RegisterFrameResolver(entry.key, {
        resolver = function() return holder end,
        displayName = ns.L[entry.label], category = "Display", order = 70 + index,
    })
    hooksecurefunc(frame, "ApplySystemAnchor", function() Apply(entry) end)
    hooksecurefunc(frame, "UpdateSystemSetting", function() Apply(entry) end)
    hooksecurefunc(frame, "InitializeBarPresentation", function() Apply(entry) end)
    hooksecurefunc(frame, "SetIsInEditMode", function(_, active)
        if entry.preview and not active then frame:SetIsInEditMode(true) end
    end)
    local override = _G.OverrideActionBar
    if override then
        override:HookScript("OnShow", function() UpdateHolderAlpha(entry) end)
        override:HookScript("OnHide", function() UpdateHolderAlpha(entry) end)
    end
end

function SwingTimers.Refresh()
    if InCombatLockdown() then return end
    for index, entry in ipairs(SwingTimers.entries) do
        Register(entry, index)
        Apply(entry)
        if entry.holder and not ns.QUI_LayoutMode.isActive then
            _G.QUI_ApplyFrameAnchor(entry.key)
        end
    end
    if _G.QUI_LayoutModeSyncAllHandles then _G.QUI_LayoutModeSyncAllHandles() end
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:SetScript("OnEvent", function(_, event, addon)
    if event == "PLAYER_REGEN_ENABLED" or addon == "Blizzard_SwingTimer" then
        SwingTimers.Refresh()
    end
end)
ns.WhenLoggedIn(SwingTimers.Refresh)
ns.Registry:Register("swingTimers", {
    refresh = SwingTimers.Refresh, priority = 80, group = "skinning",
    importCategories = { "trackersTimers", "theme" },
})
