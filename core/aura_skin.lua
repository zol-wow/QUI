local ADDON_NAME, ns = ...
ns.Addon = ns.Addon or {}
local AuraTheme = ns.Addon.AuraTheme
local AuraSkin = {}
ns.Addon.AuraSkin = AuraSkin
ns.AuraSkin = AuraSkin
_G.QUI = _G.QUI or {}
_G.QUI.AuraSkin = AuraSkin

local DISPEL_STYLES = Enum and Enum.CustomAuraButtonDispelTypeTextureStyle
local STYLE_PRESERVE_ASSET = (DISPEL_STYLES and DISPEL_STYLES.PreserveAsset) or 3
local STYLE_CUSTOM_ASSET = (DISPEL_STYLES and DISPEL_STYLES.CustomAsset) or 4

local function AurasAreSecret()
    return C_Secrets and C_Secrets.ShouldAurasBeSecret and C_Secrets.ShouldAurasBeSecret()
end

local _restrictedRestyle = {}
local _restrictedPollArmed = false
local function ScheduleRestrictedRestyle(container)
    _restrictedRestyle[container] = true
    if _restrictedPollArmed then return end
    local After = C_Timer and C_Timer.After
    if not After then return end
    _restrictedPollArmed = true
    local function tick()
        if AurasAreSecret() or (InCombatLockdown and InCombatLockdown()) then
            After(0.5, tick)
            return
        end
        _restrictedPollArmed = false
        local run = _restrictedRestyle
        _restrictedRestyle = {}
        for c in pairs(run) do
            if c._quiProfile then
                AuraSkin.Restyle(c, c._quiProfile)
            end
        end
    end
    After(0.5, tick)
end

local AuraElements
local function ResolveAuraElements()
    AuraElements = AuraElements or ns.AuraElements
    return AuraElements
end

local function ResolveLayout(profile)
    profile = profile or {}
    local m = AuraTheme.Metrics(profile)
    return {
        maxIcons  = m.maxIcons,
        iconSize  = m.iconSize,
        iconWidth = profile.iconWidth or m.iconSize,
        iconHeight = profile.iconHeight or m.iconSize,
        spacing   = m.spacing,
        rowSpacing = (profile.rowSpacing and profile.rowSpacing > 0)
            and profile.rowSpacing or m.spacing,
        grow      = m.grow,
        maxPerRow = profile.maxPerRow or 0,
        offsetX   = profile.offsetX or 0,
        offsetY   = profile.offsetY or 0,
        anchor    = profile.anchor or "TOPLEFT",
        attachPoint = profile.attachPoint or profile.anchor or "TOPLEFT",
        wrap = profile.wrap,
        crossEnd = profile.crossEnd,
    }
end

local function buildButtonArt(button)
    if button._quiWired then return end
    button._quiWired = true

    local border = button:CreateTexture(nil, "BACKGROUND")
    border:SetAllPoints(button)
    button._quiBorder = border

    local dispel = button:CreateTexture(nil, "BORDER")
    dispel:SetAllPoints(button)
    dispel:SetColorTexture(1, 1, 1, 1)
    if dispel.DisablePixelSnap then dispel:DisablePixelSnap() end
    button._quiDispel = dispel

    local steal = button:CreateTexture(nil, "BORDER")
    steal:SetAllPoints(button)
    steal:SetColorTexture(1, 1, 1, 1)
    if steal.DisablePixelSnap then steal:DisablePixelSnap() end
    if steal.Hide then steal:Hide() end
    button._quiDispelSteal = steal

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", button, "TOPLEFT", 1, -1)
    icon:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    button.Icon = icon
    if button.SetIcon then button:SetIcon(icon) end

    local backdrop = button:CreateTexture(nil, "BACKGROUND", nil, -8)
    backdrop:SetAllPoints(button)
    backdrop:SetColorTexture(0, 0, 0, 1)
    if backdrop.Hide then backdrop:Hide() end
    button._quiBackdrop = backdrop

    local gloss = button:CreateTexture(nil, "OVERLAY")
    if ns.IconSkin and gloss.SetTexture then gloss:SetTexture(ns.IconSkin.GlossTexture) end
    if gloss.SetBlendMode then gloss:SetBlendMode("ADD") end
    gloss:SetAllPoints(button)
    if gloss.Hide then gloss:Hide() end
    button._quiGloss = gloss

    local pandemic = button:CreateTexture(nil, "OVERLAY")
    if ns.IconSkin and pandemic.SetTexture then pandemic:SetTexture(ns.IconSkin.FlashTexture) end
    if pandemic.SetBlendMode then pandemic:SetBlendMode("ADD") end
    pandemic:SetAllPoints(button)
    if pandemic.SetVertexColor then pandemic:SetVertexColor(1, 0.85, 0.2, 1) end
    if pandemic.SetAlpha then pandemic:SetAlpha(0) end
    if pandemic.Hide then pandemic:Hide() end
    button._quiPandemic = pandemic
    if button.AddPandemicRegion then
        button:AddPandemicRegion(pandemic)
    end

    local cd = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
    cd:SetAllPoints(button)
    cd:SetHideCountdownNumbers(true)
    button._quiCooldown = cd
    if button.SetDurationCooldown then button:SetDurationCooldown(cd) end

    local fill = CreateFrame("StatusBar", nil, button)
    fill:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
    fill:SetAllPoints(button)
    fill:Hide()
    button._quiDurationBar = fill

    -- The cooldown swipe and the duration bar are child FRAMES, which always
    -- draw above regions on the button itself — so the texts live on their
    -- own overlay frame stacked higher, or the swipe covers them.
    local textOverlay = CreateFrame("Frame", nil, button)
    textOverlay:SetAllPoints(button)
    if textOverlay.SetFrameLevel and cd.GetFrameLevel and fill.GetFrameLevel then
        textOverlay:SetFrameLevel(math.max(cd:GetFrameLevel(), fill:GetFrameLevel()) + 1)
    end
    button._quiTextOverlay = textOverlay

    local symbol = textOverlay:CreateFontString(nil, "OVERLAY", "TextStatusBarText")
    symbol:SetPoint("TOPLEFT", button, "TOPLEFT", 2, -2)
    button._quiSymbol = symbol
    if button.SetDispelTypeText then
        button:SetDispelTypeText(symbol, {
            showWhenHarmful = true,
            showWhenHelpful = false,
        })
    end

    local durText = textOverlay:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    durText:SetPoint("CENTER", button, "CENTER", 0, 0)
    button._quiDuration = durText
    if button.SetDurationText then button:SetDurationText(durText, {}) end

    local count = textOverlay:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    count:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)
    button._quiCount = count
    if button.SetApplicationCount then button:SetApplicationCount(count, {}) end
end

local function ApplyIconSkinOwnership(button, profile)
    local Bridge = ns.ExternalSkinBridge
    local surfaceKey = profile.externalSkinKey
    local external = profile.externalSkinning == true
        and surfaceKey ~= nil
        and Bridge and Bridge.IsAvailable and Bridge.IsAvailable()

    if external then
        if button._quiBridgedKey and button._quiBridgedKey ~= surfaceKey then
            Bridge.RemoveButton(button._quiBridgedKey, button)
            button._quiBridgedKey = nil
        end
        if button._quiBridgedKey ~= surfaceKey then
            local regions = button._quiRegions or {}
            button._quiRegions = regions
            regions.Icon = button.Icon
            regions.Cooldown = button._quiCooldown
            Bridge.AddButton(surfaceKey, button, regions)
            button._quiBridgedKey = surfaceKey
        end
        button._quiBridged = true
        if button._quiBorder and button._quiBorder.Hide then button._quiBorder:Hide() end
        if button._quiBackdrop and button._quiBackdrop.Hide then button._quiBackdrop:Hide() end
        if button._quiGloss and button._quiGloss.Hide then button._quiGloss:Hide() end
        return
    end

    if button._quiBridgedKey and Bridge then
        Bridge.RemoveButton(button._quiBridgedKey, button)
    end
    button._quiBridgedKey = nil
    button._quiBridged = nil

    if button._quiBorder and button._quiBorder.Show then button._quiBorder:Show() end
    local skinName = profile.iconSkin or "Default"
    if ns.IconSkin and skinName ~= "Default" then
        local regions = button._quiRegions or {}
        button._quiRegions = regions
        regions.Backdrop = button._quiBackdrop
        regions.Gloss = button._quiGloss
        ns.IconSkin.ApplySkin(button, regions, skinName)
    else
        if button._quiBackdrop and button._quiBackdrop.Hide then button._quiBackdrop:Hide() end
        if button._quiGloss and button._quiGloss.Hide then button._quiGloss:Hide() end
    end
end

function AuraSkin.StyleIconArt(button, profile)
    profile = profile or {}
    local icon = button.Icon
    local showBorder = profile.showBorder ~= false
    if not button._quiBridged and icon then
        local zoom = profile.zoom or 0
        local left = 0.08 + zoom
        local right = 0.92 - zoom
        local top = 0.08 + zoom
        local bottom = 0.92 - zoom
        local aspect = profile.aspectRatioCrop or 1
        if aspect > 1 then
            local offset = (1 - (1 / aspect)) * (bottom - top) / 2
            top = top + offset
            bottom = bottom - offset
        end
        if icon.SetTexCoord then icon:SetTexCoord(left, right, top, bottom) end
        local inset = showBorder and (profile.borderSize or 1) or 0
        if inset < 0 then inset = 0 end
        if icon.ClearAllPoints then icon:ClearAllPoints() end
        icon:SetPoint("TOPLEFT", button, "TOPLEFT", inset, -inset)
        icon:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -inset, inset)
    end

    local border = button._quiBorder
    if not border then return end
    if button._quiBridged or not showBorder then
        if border.Hide then border:Hide() end
        return
    end
    local color = profile.borderColor
    local r, g, b, a
    if type(color) == "table" then
        r, g, b, a = color[1] or 1, color[2] or 1, color[3] or 1, color[4]
    else
        r, g, b, a = AuraTheme.BorderColor()
    end
    border:SetColorTexture(r, g, b, a or 1)
    if border.DisablePixelSnap then border:DisablePixelSnap() end
    if border.Show then border:Show() end
end

local durationFormatters = {}
local function DurationFormatter(decimals, hideUnit)
    local key = (decimals and "d" or "-") .. (hideUnit and "u" or "-")
    local cached = durationFormatters[key]
    if cached ~= nil then return cached or nil end
    local rounding = Enum and Enum.NumericRuleFormatRounding
    local built
    if C_StringUtil and C_StringUtil.CreateNumericRuleFormatter and rounding then
        local ok, formatter = pcall(C_StringUtil.CreateNumericRuleFormatter)
        if ok and formatter then
            local breakpoints = {}
            local secondsFmt = hideUnit and "%d" or "%ds"
            if decimals then
                breakpoints[#breakpoints + 1] = { threshold = 0, format = hideUnit and "%.1f" or "%.1fs" }
                breakpoints[#breakpoints + 1] = { threshold = 3, step = 1, rounding = rounding.Up, format = secondsFmt }
            else
                breakpoints[#breakpoints + 1] = { threshold = 0, step = 1, rounding = rounding.Up, format = secondsFmt }
            end
            -- Minute+ bands keep their unit even with hideUnit: a bare "2"
            -- for two minutes is indistinguishable from two seconds.
            breakpoints[#breakpoints + 1] = { threshold = 90, format = "%dm",
                components = { { div = 60, step = 1, rounding = rounding.Up } } }
            breakpoints[#breakpoints + 1] = { threshold = 5400, format = "%dh",
                components = { { div = 3600, step = 1, rounding = rounding.Up } } }
            breakpoints[#breakpoints + 1] = { threshold = 129600, format = "%dd",
                components = { { div = 86400, step = 1, rounding = rounding.Up } } }
            local applied = pcall(formatter.SetBreakpoints, formatter, breakpoints)
            if applied then built = formatter end
        end
    end
    durationFormatters[key] = built or false
    return built
end

function AuraSkin.BuildDurationTextOptions(profile)
    local durS = (profile and profile.duration) or {}
    local opts = {}
    local decimals = durS.decimals == true
    local hideUnit = durS.hideUnit == true
    if decimals or hideUnit then
        opts.textFormatter = DurationFormatter(decimals, hideUnit)
    end
    return opts
end

function AuraSkin.ResolveDurationTextOptions(_button, profile)
    return AuraSkin.BuildDurationTextOptions(profile)
end

local Helpers = ns.Helpers
local function StylePandemic(button, glow)
    local texture = button._quiPandemic
    if not texture then return end
    local color = type(glow) == "table" and type(glow.color) == "table" and glow.color
    local style = color and glow.style or "steady"
    local add = style == "pulse" and button.AddPandemicActiveAnimation
        or style == "flash" and button.AddPandemicEnterAnimation
    local remove = style == "pulse" and button.RemovePandemicActiveAnimation
        or style == "flash" and button.RemovePandemicEnterAnimation
    if not texture.CreateAnimationGroup or not ((add and remove) or button._quiPreview) then
        style = "steady"
    end
    if style ~= "pulse" and style ~= "flash" then style = "steady" end

    local previous = button._quiPandemicStyle
    if previous ~= style then
        local old = button._quiPandemicAnimations and button._quiPandemicAnimations[previous]
        if old then
            old:Stop()
            if not button._quiPreview then
                local unregister = previous == "pulse" and button.RemovePandemicActiveAnimation
                    or button.RemovePandemicEnterAnimation
                unregister(button, old)
            end
        end
        button._quiPandemicStyle = style
    end

    if texture.SetVertexColor and color then
        texture:SetVertexColor(color[1] or 1, color[2] or 0.85, color[3] or 0.2,
            style == "steady" and 1 or (color[4] or 1))
    end
    if texture.SetAlpha then
        texture:SetAlpha(not color and 0 or style == "flash" and 0
            or style == "pulse" and 1 or (color[4] or 1))
    end
    if style == "steady" or previous == style then return end

    local animations = button._quiPandemicAnimations or {}
    button._quiPandemicAnimations = animations
    local group = animations[style]
    if not group then
        group = texture:CreateAnimationGroup()
        group:SetLooping(style == "pulse" and "REPEAT" or "NONE")
        local fade = group:CreateAnimation("Alpha")
        fade:SetOrder(1)
        fade:SetFromAlpha(style == "pulse" and 0.25 or 1)
        fade:SetToAlpha(style == "pulse" and 1 or 0)
        fade:SetDuration(style == "pulse" and 0.45 or 0.6)
        if style == "pulse" then
            local down = group:CreateAnimation("Alpha")
            down:SetOrder(2)
            down:SetFromAlpha(1)
            down:SetToAlpha(0.25)
            down:SetDuration(0.45)
        end
        animations[style] = group
    end
    if not button._quiPreview then add(button, group) end
    group:Play()
end

local function styleButton(button, profile)
    local size = profile.iconSize or 22
    if size <= 0 then size = 22 end
    local width = profile.iconWidth or size
    local height = profile.iconHeight or size
    button:SetSize(width, height)

    if button.SetTooltipAnchorPoint then
        if profile.tooltipAnchor then
            if not button._quiTipPrev and button.GetTooltipAnchorPoint then
                button._quiTipPrev = { button:GetTooltipAnchorPoint() }
            end
            local ok = pcall(button.SetTooltipAnchorPoint, button, profile.tooltipAnchor,
                profile.tooltipAnchorX or 0, profile.tooltipAnchorY or 0)
            if ok then button._quiTipAnchored = true end
        elseif button._quiTipAnchored then
            local prev = button._quiTipPrev
            pcall(button.SetTooltipAnchorPoint, button,
                (prev and prev[1]) or "ANCHOR_BOTTOMLEFT",
                (prev and prev[2]) or 0, (prev and prev[3]) or 0)
            button._quiTipAnchored = nil
        end
    end
    if button.SetHideTooltipInCombat then
        button:SetHideTooltipInCombat(profile.tooltipHideInCombat == true)
    end

    ApplyIconSkinOwnership(button, profile)
    button:SetAlpha(profile.opacity or 1)
    AuraSkin.StyleIconArt(button, profile)

    local dispel = button._quiDispel
    if dispel and button.ClearDispelTypeTextures and button.AddDispelTypeTexture then
        local mode = profile.dispelBorderMode
        local borderOpts = {
            style = STYLE_PRESERVE_ASSET,
            showWhenHarmful = true,
            showWhenHelpful = false,
        }
        if mode == "all" then
            borderOpts.showAlways = true
        end
        if type(profile.dispelColors) == "table" then
            borderOpts.customDispelColorMap = profile.dispelColors
        elseif profile.dispelColorCurve then
            borderOpts.customDispelColorCurve = profile.dispelColorCurve
        end
        if type(profile.dispelAssets) == "table" then
            borderOpts.style = STYLE_CUSTOM_ASSET
            borderOpts.customDispelAssetMap = profile.dispelAssets
        end
        local steal = button._quiDispelSteal
        button:ClearDispelTypeTextures()
        if button._quiBridged or profile.showDispelBorder == false then
            if dispel.Hide then dispel:Hide() end
            if steal and steal.Hide then steal:Hide() end
        else
            if dispel.Show then dispel:Show() end
            button:AddDispelTypeTexture(dispel, borderOpts)
            local filters = Enum and Enum.CustomAuraButtonDispelTypeStealableFilter
            if mode == "stealable" and steal and filters then
                local stealOpts = {
                    style = borderOpts.style,
                    showWhenHarmful = false,
                    showWhenHelpful = true,
                    stealableFilter = filters.Stealable,
                    customDispelColorMap = borderOpts.customDispelColorMap,
                    customDispelColorCurve = borderOpts.customDispelColorCurve,
                    customDispelAssetMap = borderOpts.customDispelAssetMap,
                }
                if steal.Show then steal:Show() end
                button:AddDispelTypeTexture(steal, stealOpts)
            elseif steal and steal.Hide then
                steal:Hide()
            end
        end
    end

    StylePandemic(button, profile.pandemicGlow)

    local fontPath = (Helpers and Helpers.GetGeneralFont and Helpers.GetGeneralFont())
    local fontFlags = (Helpers and Helpers.GetGeneralFontOutline and Helpers.GetGeneralFontOutline()) or "OUTLINE"
    local function styleText(fs, cfg, fallbackSize, defAnchor, defX, defY)
        if not fs then return end
        local size = (cfg and cfg.fontSize) or fallbackSize or 11
        if size <= 0 then size = 11 end
        local font = (cfg and cfg.font) or fontPath
        if font then fs:SetFont(font, size, fontFlags) end
        fs:ClearAllPoints()
        fs:SetPoint((cfg and cfg.anchor) or defAnchor, button, (cfg and cfg.anchor) or defAnchor,
            (cfg and cfg.offsetX) or defX, (cfg and cfg.offsetY) or defY)
        local c = cfg and cfg.color
        if c then fs:SetTextColor(c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1) end
        fs:SetAlpha(cfg and cfg.show == false and 0 or 1)
    end
    styleText(button._quiDuration, profile.duration, profile.fontSize, "CENTER", 0, 0)
    if button.SetDurationText and button._quiDuration then
        ns.SafeCall("sink-forward", button.SetDurationText, button, button._quiDuration,
            AuraSkin.ResolveDurationTextOptions(button, profile))
    end
    styleText(button._quiCount, profile.stack, profile.fontSize, "BOTTOMRIGHT", -1, 1)
    local caster = type(profile.casterName) == "table" and profile.casterName
    if caster and (button.SetCasterName or button._quiPreview) then
        local text = button._quiCaster
        if not text then
            text = button._quiTextOverlay:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            text:SetWordWrap(false)
            text:SetJustifyH("CENTER")
            button._quiCaster = text
        end
        styleText(text, caster, 10, "BOTTOM", 0, 1)
        text:SetWidth(width)
        if button._quiPreview then
            text:SetText(caster.showRealmName and "Caster-Realm" or "Caster")
            if caster.useClassColors then text:SetTextColor(1, 0.49, 0.04) end
        else
            button:SetCasterName(text, {
                showRealmName = caster.showRealmName == true,
                useClassColors = caster.useClassColors == true,
            })
        end
    elseif button._quiCaster then
        if button.ClearCasterName then button:ClearCasterName() end
        button._quiCaster:SetAlpha(0)
    end
    if fontPath and button._quiSymbol then button._quiSymbol:SetFont(fontPath, (profile.fontSize and profile.fontSize > 0) and profile.fontSize or 11, fontFlags) end

    local cd = button._quiCooldown
    local wantsLinear = profile.swipeStyle == "horizontal" or profile.swipeStyle == "vertical"
    if wantsLinear and button.SetDurationBar and profile.hideSwipe ~= true then
        if cd and cd.SetDrawSwipe then cd:SetDrawSwipe(false) end
        if cd and cd.SetDrawEdge then cd:SetDrawEdge(false) end
        if cd and cd.SetDrawBling then cd:SetDrawBling(false) end
        local fill = button._quiDurationBar
        if not fill and InCombatLockdown() then
            return
        end
        if not fill then
            fill = CreateFrame("StatusBar", nil, button)
            fill:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
            fill:SetAllPoints(button)
            button._quiDurationBar = fill
        end
        button:SetDurationBar(fill, {
            direction = (profile.reverseSwipe and Enum.StatusBarTimerDirection.ElapsedTime)
                or Enum.StatusBarTimerDirection.RemainingTime,
            interpolation = Enum.StatusBarInterpolation.Immediate,
        })
        fill:SetOrientation(profile.swipeStyle == "vertical" and "VERTICAL" or "HORIZONTAL")
        fill:Show()
    else
        if button._quiDurationBar then button._quiDurationBar:Hide() end
        if cd then
            if cd.SetSwipeTexture and profile.swipeTexture then
                cd:SetSwipeTexture(profile.swipeTexture)
            end
            local showSwipe = profile.hideSwipe ~= true
            cd:SetDrawSwipe(showSwipe)
            if cd.SetDrawEdge then
                cd:SetDrawEdge(showSwipe and profile.showEdge ~= false)
            end
            if cd.SetDrawBling then
                cd:SetDrawBling(showSwipe)
            end
            if profile.swipeColor and cd.SetSwipeColor then
                local c = profile.swipeColor
                cd:SetSwipeColor(c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1)
            end
            cd:SetReverse(profile.reverseSwipe == true)
            cd:SetHideCountdownNumbers(true)
        end
    end
end

local function FlowFor(L)
    local grow = L.grow == "CENTER" and "RIGHT" or L.grow
    local column = (grow == "UP" or grow == "DOWN")
    local left = (grow == "LEFT")
    local up
    if column then
        up = (grow == "UP")
        -- Vertical flows anchor their cross axis on the left unless the
        -- profile asks for the far edge (packed group blocks aligned END).
        if L.crossEnd ~= nil then left = (L.crossEnd == true) end
    else
        up = (L.wrap == "UP")
    end
    local anchor = (up and "BOTTOM" or "TOP") .. (left and "RIGHT" or "LEFT")
    return anchor, left, up, column
end

function AuraSkin.LayoutAnchor(profile)
    local L = ResolveLayout(profile)
    if L.grow == "CENTER" then
        return "CENTER"
    end
    local anchor = FlowFor(L)
    return anchor
end

local function ApplyContainerLayout(container, L)
    local anchor, left, up, column = FlowFor(L)
    local FD = AnchorUtil.FlowDirection
    local AX = AnchorUtil.FlowLayoutAxis
    container:SetFlowLayoutAnchorPoint(anchor)
    container:SetFlowLayoutGrowthDirection(
        left and FD.Left or FD.Right,
        up and FD.Up or FD.Down)
    container:SetFlowLayoutPadding(0, 0, 0, 0)
    container:SetFlowLayoutAxis(column and AX.Vertical or AX.Horizontal)
    local lineSize
    if L.maxPerRow and L.maxPerRow > 0 then
        lineSize = L.maxPerRow * L.iconSize + (L.maxPerRow - 1) * L.spacing + 0.5
    end
    container:SetFlowLayoutMaximumLineSize(lineSize)
end

local function GroupLayout(L, g)
    local t = {
        elementSpacing = g and g.elementSpacing or L.spacing,
        lineSpacing    = L.rowSpacing,
        elementWidth   = g and g.elementWidth or L.iconWidth,
        elementHeight  = g and g.elementHeight or L.iconHeight,
    }
    if g and type(g._quiOrder) == "number" then
        t.layoutIndex = g._quiOrder
    end
    if g and type(g.groupSpacing) == "number" then
        t.groupSpacing = g.groupSpacing
    end
    return t
end

local function ApplyLatchedMouseMotion(container, button)
    local mouseMotion = container._quiRangeGateMouseEnabled
    if mouseMotion == nil then return end
    if AurasAreSecret() or (InCombatLockdown and InCombatLockdown()) then
        ScheduleRestrictedRestyle(container)
        return
    end
    if button.SetMouseMotionEnabled and button.SetMouseClickEnabled then
        button:SetMouseMotionEnabled(mouseMotion)
        button:SetMouseClickEnabled(mouseMotion)
    elseif button.EnableMouse then
        button:EnableMouse(mouseMotion)
    end
end

-- A group may carry its own style profile (packed aura-display groups mix
-- displays with different icon sizes in one container); it is looked up by
-- key at style time so later Configure passes can swap it without rebirth.
local function GroupProfile(container, key)
    local byKey = key ~= nil and container._quiGroupProfiles or nil
    return (byKey and byKey[key]) or container._quiProfile or {}
end

local function MakeInitializer(container, _groupDesc, key)
    return function(button)
        buildButtonArt(button)
        styleButton(button, GroupProfile(container, key))
        if button.SetCancelAuraButtons then
            button:SetCancelAuraButtons(container._quiCancelButtons)
        end
        ApplyLatchedMouseMotion(container, button)
        local reg = container._quiButtons
        if not reg then
            reg = {}
            container._quiButtons = reg
        end
        if not button._quiTracked then
            button._quiTracked = true
            reg[#reg + 1] = button
        end
    end
end

local function EachTrackedButton(container, fn)
    local seen
    if container.GetAuraGroupFrame and container.GetAuraGroupFrameCount then
        seen = {}
        local registered = container._quiGroups
        if registered then
            for key in pairs(registered) do
                local count = container:GetAuraGroupFrameCount(key)
                for i = 1, count or 0 do
                    local button = container:GetAuraGroupFrame(key, i)
                    if button then
                        seen[button] = true
                        fn(button, key)
                    end
                end
            end
        end
    end
    local reg = container._quiButtons
    if reg then
        for i = 1, #reg do
            local button = reg[i]
            if button and not (seen and seen[button]) then
                fn(button)
            end
        end
    end
end

function AuraSkin.Configure(container, profile, groups)
    local L = ResolveLayout(profile)
    container._quiProfile = profile
    local cancel
    for i = 1, #groups do
        local c = groups[i].cancelButtons
        if c then cancel = c end
    end
    container._quiCancelButtons = cancel
    local registered = container._quiGroups
    if not registered then
        registered = {}
        container._quiGroups = registered
    end
    local groupProfiles = container._quiGroupProfiles
    if not groupProfiles then
        groupProfiles = {}
        container._quiGroupProfiles = groupProfiles
    end
    local wanted = {}
    local E = ResolveAuraElements()
    local canMutateFilter = container.SetAuraGroupFilterString ~= nil
    for i = 1, #groups do
        local g = groups[i]
        g._quiOrder = i
        local gkey = g.key or ""
        assert(not gkey:find("|", 1, true),
            "AuraSkin group key must not contain '|'")
        local filter = (E and E.CanonicalizeFilterString) and E.CanonicalizeFilterString(g.filter) or g.filter
        local key = canMutateFilter and gkey or (gkey .. "|" .. filter)
        wanted[key] = true
        groupProfiles[key] = g.profile
        local maxCount   = g.maxFrameCount or L.maxIcons
        local sortMethod = g.sortMethod or AuraContainerSortMethod.Default
        local sortDir    = g.sortDirection or AuraContainerSortDirection.Normal
        if registered[key] or container:HasAuraGroup(key) then
            if canMutateFilter and registered[key] ~= filter then
                container:SetAuraGroupFilterString(key, filter)
            end
            container:SetAuraGroupMaxFrameCount(key, maxCount)
            container:SetAuraGroupSortMethod(key, sortMethod, sortDir)
            container:SetAuraGroupCandidateFilters(key, g.candidateFilters)
            container:SetAuraGroupLayout(key, GroupLayout(L, g))
            registered[key] = filter
        else
            container:AddAuraGroup(key, filter, {
                maxFrameCount    = maxCount,
                sortMethod       = sortMethod,
                sortDirection    = sortDir,
                candidateFilters = g.candidateFilters,
                initializeFrame  = MakeInitializer(container, g, key),
                layout           = GroupLayout(L, g),
            })
            registered[key] = filter
        end
    end
    for key in pairs(registered) do
        if not wanted[key] then
            container:SetAuraGroupMaxFrameCount(key, 0)
            groupProfiles[key] = nil
        end
    end
    ApplyContainerLayout(container, L)

    if AurasAreSecret() then
        ScheduleRestrictedRestyle(container)
        return
    end
    EachTrackedButton(container, function(button, key)
        styleButton(button, GroupProfile(container, key))
        if button.SetCancelAuraButtons then
            button:SetCancelAuraButtons(container._quiCancelButtons)
        end
        ApplyLatchedMouseMotion(container, button)
    end)
end

function AuraSkin.Restyle(container, profile)
    container._quiProfile = profile
    if AurasAreSecret() then
        ScheduleRestrictedRestyle(container)
        return
    end
    EachTrackedButton(container, function(button, key)
        styleButton(button, GroupProfile(container, key))
        if button.SetCancelAuraButtons then
            button:SetCancelAuraButtons(container._quiCancelButtons)
        end
        ApplyLatchedMouseMotion(container, button)
    end)
end

function AuraSkin.ConfigureEnchantments(container, profile)
    local slots = _G.AuraContainerItemEnchantmentSlot
    local placement = _G.CustomAuraContainerItemEnchantmentPlacement
    if not (slots and placement and container.AddItemEnchantment) then
        return false
    end
    container._quiProfile = profile
    local L = ResolveLayout(profile)
    container:SetItemEnchantmentLayout({
        placement      = placement.BeforeAuraGroups,
        elementSpacing = L.spacing,
        lineSpacing    = L.rowSpacing,
        elementWidth   = L.iconSize,
        elementHeight  = L.iconSize,
    })
    if not AurasAreSecret() then
        local reg = container._quiButtons
        if reg then
            for i = 1, #reg do
                local b = reg[i]
                if b and b.SetCancelAuraButtons then
                    b:SetCancelAuraButtons(container._quiCancelButtons)
                end
            end
        end
    end
    if not container._quiEnchantsAdded then
        local init = MakeInitializer(container, {})
        for _, slot in ipairs({ slots.MainHand, slots.OffHand, slots.Ranged }) do
            container:AddItemEnchantment(slot, {
                initializeFrame = init,
                hidePermanent   = true,
            })
        end
        container._quiEnchantsAdded = true
    end
    return true
end

function AuraSkin.WireButton(button, profile)
    buildButtonArt(button)
    styleButton(button, profile or {})
end

function AuraSkin.WirePreviewButton(button, profile)
    button._quiPreview = true
    if not button.SetDurationBar then
        button.SetDurationBar = function(self, bar, options)
            self._quiPreviewDurationBar = bar
            self._quiPreviewDurationOptions = options
        end
        button._quiPreviewDurationBarShim = true
    end
    buildButtonArt(button)
    styleButton(button, profile or {})
    button._tex = button.Icon
    if button._quiDispel and button._quiDispel.Hide then button._quiDispel:Hide() end
end

function AuraSkin.ReleasePreviewButton(button)
    local key = button and button._quiBridgedKey
    local Bridge = ns.ExternalSkinBridge
    if key and Bridge then Bridge.RemoveButton(key, button) end
    if button then
        if button._quiCaster then button._quiCaster:SetAlpha(0) end
        if button._quiPandemicAnimations then
            for _, animation in pairs(button._quiPandemicAnimations) do animation:Stop() end
        end
        button._quiPandemicStyle = nil
        button._quiBridgedKey = nil
        button._quiBridged = nil
    end
end
