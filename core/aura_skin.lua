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
        if AurasAreSecret() then
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
        grow      = m.grow,
        maxPerRow = profile.maxPerRow or 0,
        offsetX   = profile.offsetX or 0,
        offsetY   = profile.offsetY or 0,
        anchor    = profile.anchor or "TOPLEFT",
        attachPoint = profile.attachPoint or profile.anchor or "TOPLEFT",
        wrap = profile.wrap,
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

    local symbol = button:CreateFontString(nil, "OVERLAY", "TextStatusBarText")
    symbol:SetPoint("TOPLEFT", button, "TOPLEFT", 2, -2)
    button._quiSymbol = symbol
    if button.SetDispelTypeText then
        button:SetDispelTypeText(symbol, {
            showWhenHarmful = true,
            showWhenHelpful = false,
        })
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

    local durText = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    durText:SetPoint("CENTER", button, "CENTER", 0, 0)
    button._quiDuration = durText
    if button.SetDurationText then button:SetDurationText(durText, {}) end

    local count = button:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
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

    -- Border thickness is the gap between the button edge and the inset icon;
    -- external skins own the icon geometry, so leave it alone when bridged.
    local showBorder = profile.showBorder ~= false
    if not button._quiBridged and button.Icon then
        local inset = 0
        if showBorder then
            inset = profile.borderSize or 1
            if inset < 0 then inset = 0 end
        end
        button.Icon:SetPoint("TOPLEFT", button, "TOPLEFT", inset, -inset)
        button.Icon:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -inset, inset)
    end

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

    local pandemic = button._quiPandemic
    if pandemic then
        local glow = profile.pandemicGlow
        if type(glow) == "table" and type(glow.color) == "table" then
            local c = glow.color
            if pandemic.SetVertexColor then pandemic:SetVertexColor(c[1] or 1, c[2] or 0.85, c[3] or 0.2, 1) end
            if pandemic.SetAlpha then pandemic:SetAlpha(c[4] or 1) end
        elseif pandemic.SetAlpha then
            pandemic:SetAlpha(0)
        end
    end

    local border = button._quiBorder
    if border then
        if not showBorder then
            if border.Hide then border:Hide() end
        else
            local bc = profile.borderColor
            local r, g, b, a
            if type(bc) == "table" then
                r, g, b, a = bc[1] or 1, bc[2] or 1, bc[3] or 1, bc[4]
            else
                r, g, b, a = AuraTheme.BorderColor()
            end
            border:SetColorTexture(r, g, b, a or 1)
            if border.DisablePixelSnap then border:DisablePixelSnap() end
        end
    end

    local fontPath = (Helpers and Helpers.GetGeneralFont and Helpers.GetGeneralFont())
    local fontFlags = (Helpers and Helpers.GetGeneralFontOutline and Helpers.GetGeneralFontOutline()) or "OUTLINE"
    local function styleText(fs, cfg, fallbackSize, defAnchor, defX, defY)
        if not fs then return end
        local size = (cfg and cfg.fontSize) or fallbackSize or 11
        if size <= 0 then size = 11 end
        if fontPath then fs:SetFont(fontPath, size, fontFlags) end
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
    if fontPath and button._quiSymbol then button._quiSymbol:SetFont(fontPath, (profile.fontSize and profile.fontSize > 0) and profile.fontSize or 11, fontFlags) end

    local cd = button._quiCooldown
    local wantsLinear = profile.swipeStyle == "horizontal" or profile.swipeStyle == "vertical"
    if wantsLinear and button.SetDurationBar then
        if cd and cd.SetDrawSwipe then cd:SetDrawSwipe(false) end
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
            cd:SetDrawSwipe(profile.hideSwipe ~= true)
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
    if column then up = (grow == "UP") else up = (L.wrap == "UP") end
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
        elementSpacing = L.spacing,
        lineSpacing    = L.spacing,
        elementWidth   = L.iconWidth,
        elementHeight  = L.iconHeight,
    }
    if g and type(g._quiOrder) == "number" then
        t.layoutIndex = g._quiOrder
    end
    if g and type(g.groupSpacing) == "number" then
        t.groupSpacing = g.groupSpacing
    end
    return t
end

local function MakeInitializer(container, _groupDesc)
    return function(button)
        buildButtonArt(button)
        styleButton(button, container._quiProfile or {})
        if button.SetCancelAuraButtons then
            button:SetCancelAuraButtons(container._quiCancelButtons)
        end
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
                        fn(button)
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
                initializeFrame  = MakeInitializer(container, g),
                layout           = GroupLayout(L, g),
            })
            registered[key] = filter
        end
    end
    for key in pairs(registered) do
        if not wanted[key] then
            container:SetAuraGroupMaxFrameCount(key, 0)
        end
    end
    ApplyContainerLayout(container, L)

    if AurasAreSecret() then
        ScheduleRestrictedRestyle(container)
        return
    end
    EachTrackedButton(container, function(button)
        styleButton(button, profile)
        if button.SetCancelAuraButtons then
            button:SetCancelAuraButtons(container._quiCancelButtons)
        end
    end)
end

function AuraSkin.Restyle(container, profile)
    container._quiProfile = profile
    if AurasAreSecret() then
        ScheduleRestrictedRestyle(container)
        return
    end
    EachTrackedButton(container, function(button)
        styleButton(button, profile)
        if button.SetCancelAuraButtons then
            button:SetCancelAuraButtons(container._quiCancelButtons)
        end
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
        lineSpacing    = L.spacing,
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
        button._quiBridgedKey = nil
        button._quiBridged = nil
    end
end
