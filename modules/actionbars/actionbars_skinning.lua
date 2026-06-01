local ADDON_NAME, ns = ...
local env = ns.ActionBarsEnv
env.ADDON_NAME = ADDON_NAME
env.ns = ns
env.SetChunkEnv(1, env)

-- BUTTON SKINNING
---------------------------------------------------------------------------

-- Get the icon texture from a button, handling stance/pet buttons
-- that use NormalTexture as the icon source.
-- Returns: icon texture, iconUsesNormalTexture (bool)
function GetButtonIconTexture(button)
    -- Standard action buttons use .icon or .Icon
    local icon = button.icon or button.Icon
    if icon then return icon, false end

    -- Stance/pet buttons may use NormalTexture as the icon
    local normalTex = button:GetNormalTexture()
    if normalTex then
        return normalTex, true
    end

    return nil, false
end

-- Remove Blizzard's default textures and masks
function StripBlizzardArtwork(button)
    local state = GetFrameState(button)
    local icon, iconUsesNormalTexture = GetButtonIconTexture(button)

    -- Always re-hide NormalTexture — Blizzard may reset it after our init
    -- (e.g. action bar updates that call SetNormalTexture post-PLAYER_LOGIN).
    -- If a button currently uses NormalTexture as the icon source, keep it.
    -- Otherwise hide NormalTexture, including for stance buttons.
    local normalTex = button:GetNormalTexture()
    if normalTex and not iconUsesNormalTexture then
        normalTex:SetAlpha(0)
    end
    if button.NormalTexture and not iconUsesNormalTexture then
        button.NormalTexture:SetAlpha(0)
    end

    -- Remove mask textures from icon
    -- Re-run when icon object changes (can happen for stance/pet during paging).
    if icon and not iconUsesNormalTexture and icon.GetMaskTexture and icon.RemoveMaskTexture then
        if state.lastMaskStrippedIcon ~= icon then
            for i = 1, 10 do
                local mask = icon:GetMaskTexture(i)
                if mask then
                    icon:RemoveMaskTexture(mask)
                end
            end
            state.lastMaskStrippedIcon = icon
        end
    end

    -- Neutralize IconMask to prevent Blizzard's UpdateButtonArt from
    -- re-adding it during combat transitions and bar paging.
    if button.IconMask then
        button.IconMask:Hide()
        button.IconMask:SetTexture(nil)
        button.IconMask:ClearAllPoints()
        button.IconMask:SetSize(0.001, 0.001)
    end

    -- Hide FloatingBG if present
    if button.FloatingBG then
        button.FloatingBG:SetAlpha(0)
    end

    -- Hide SlotBackground if present
    if button.SlotBackground then
        button.SlotBackground:SetAlpha(0)
    end

    -- Hide SlotArt if present
    if button.SlotArt then
        button.SlotArt:SetAlpha(0)
    end

    -- Replace Blizzard's highlight, pushed, checked, and flash textures
    -- with QUI versions that are properly sized via SetAllPoints.
    local function ReplaceTexture(tex, texturePath)
        if not tex then return end
        tex:SetAtlas(nil)
        tex:SetTexture(texturePath)
        tex:SetTexCoord(0, 1, 0, 1)
        tex:ClearAllPoints()
        tex:SetAllPoints(button)
        tex:SetAlpha(1)
    end

    local highlight = button:GetHighlightTexture()
    if highlight then ReplaceTexture(highlight, TEXTURES.highlight) end
    if button.HighlightTexture and button.HighlightTexture ~= highlight then
        ReplaceTexture(button.HighlightTexture, TEXTURES.highlight)
    end

    local pushed = button:GetPushedTexture()
    if pushed then ReplaceTexture(pushed, TEXTURES.pushed) end
    if button.PushedTexture and button.PushedTexture ~= pushed then
        ReplaceTexture(button.PushedTexture, TEXTURES.pushed)
    end

    local checked = button.GetCheckedTexture and button:GetCheckedTexture()
    if checked then ReplaceTexture(checked, TEXTURES.checked) end
    if button.CheckedTexture and button.CheckedTexture ~= checked then
        ReplaceTexture(button.CheckedTexture, TEXTURES.checked)
    end

    -- Replace flash texture
    if button.Flash then
        ReplaceTexture(button.Flash, TEXTURES.flash)
    end

    -- Hide border/shadow decorations
    if button.Border then button.Border:SetAlpha(0) end
    if button.BorderShadow then button.BorderShadow:SetAlpha(0) end

    -- SpellHighlightTexture: anchor to button so it matches our size
    if button.SpellHighlightTexture then
        button.SpellHighlightTexture:ClearAllPoints()
        button.SpellHighlightTexture:SetAllPoints(button)
    end

    -- Cooldown: anchor to button so it fills correctly
    local cd = button.cooldown or button.Cooldown
    if cd then
        cd:ClearAllPoints()
        cd:SetAllPoints(button)
    end

    -- No overlay scaling needed — buttons stay at their natural 45x45 size
    -- and the container's SetScale handles visual resize. Blizzard overlays
    -- (SpellActivationAlert, proc glows, rotation assist) work naturally
    -- because the button dimensions match what overlays expect.
end

---------------------------------------------------------------------------
-- BUTTON SKINNING
---------------------------------------------------------------------------

env.__declared.FadeHideEffects = true
env.__declared.FadeShowEffects = true
env.__declared.SkinSpellFlyoutButtons = true
env.__declared.ApplySpellFlyoutButtonStateTextures = true
env.__declared.ShowOwnedFlyoutForButton = true
env.__declared.HideOwnedFlyout = true
PROC_ALERT_REGION_KEYS = {
    "ProcStartFlipbook",
    "ProcLoopFlipbook",
}

function SuppressProcVisualFrame(frame)
    if not frame then return end

    pcall(function()
        if frame.Hide then
            frame:Hide()
        end
        if frame.SetAlpha then
            frame:SetAlpha(0)
        end
        if frame.StopAnimating then
            frame:StopAnimating()
        end
        -- ActionButtonSpellAlertMixin keeps the proc loop alive via two
        -- AnimationGroups (ProcStartAnim → ProcLoop) defined on the alert
        -- frame itself. StopAnimating() doesn't traverse them, so the swirl
        -- keeps playing under SetAlpha(0) and pops back on the next Show.
        if frame.ProcStartAnim and frame.ProcStartAnim.Stop then
            frame.ProcStartAnim:Stop()
        end
        if frame.ProcLoop and frame.ProcLoop.Stop then
            frame.ProcLoop:Stop()
        end
    end)

    if frame.Show then
        Helpers.DeferredHideOnShow(frame, { clearAlpha = true, combatCheck = false })
    end
end

function SuppressButtonProcVisuals(button)
    if not button then return end

    pcall(function()
        local alert = button.SpellActivationAlert
        if alert then
            SuppressProcVisualFrame(alert)

            for _, regionKey in ipairs(PROC_ALERT_REGION_KEYS) do
                SuppressProcVisualFrame(alert[regionKey])
            end
        end
    end)

    pcall(function()
        SuppressProcVisualFrame(button.OverlayGlow)
    end)

    pcall(function()
        SuppressProcVisualFrame(button._ButtonGlow)
    end)
end

UpdateButtonProfessionQuality = function(button, settings)
    if not button then return end

    local overlay = button.ProfessionQualityOverlayTexture
    if settings == nil then
        local db = GetDB()
        settings = db and db.global
    end
    if settings and settings.showProfessionQuality == false then
        if overlay then
            overlay:Hide()
        end
        return
    end

    local action = GetSafeActionSlot(button)
    if not action or not (C_ActionBar and C_ActionBar.GetProfessionQualityInfo) then
        if overlay then
            overlay:Hide()
        end
        return
    end

    local ok, qualityInfo = pcall(C_ActionBar.GetProfessionQualityInfo, action)
    local atlas = ok and qualityInfo and qualityInfo.iconInventory
    if not atlas then
        if overlay then
            overlay:Hide()
        end
        return
    end

    if not overlay then
        overlay = button:CreateTexture(nil, "OVERLAY", nil, 7)
        overlay:SetPoint("CENTER", button, "TOPLEFT", 14, -14)
        overlay:SetDrawLayer("OVERLAY", 7)
        button.ProfessionQualityOverlayTexture = overlay
    end

    overlay:SetAtlas(
        atlas,
        TextureKitConstants and TextureKitConstants.UseAtlasSize or true
    )
    overlay:Show()
end

-- Apply QUI skin to a single button
SkinButton = function(button, settings)
    if not button or not settings then
        return
    end

    UpdateButtonProfessionQuality(button, settings)

    if not settings.skinEnabled then
        return
    end
    local state = GetFrameState(button)

    -- Skip if already skinned with same settings (direct field comparison,
    -- avoids string.format allocation on every call)
    local _sz = settings.iconSize or 36
    local _zm = settings.iconZoom or 0.07
    local _bd = settings.showBackdrop
    local _ba = settings.backdropAlpha or 0.8
    local _gl = settings.showGloss
    local _ga = settings.glossAlpha or 0.6
    local _br = settings.showBorders
    local _fl = settings.showFlash
    if state.sk_sz == _sz and state.sk_zm == _zm
        and state.sk_bd == _bd and state.sk_ba == _ba
        and state.sk_gl == _gl and state.sk_ga == _ga
        and state.sk_br == _br and state.sk_fl == _fl then
        return
    end
    state.sk_sz = _sz; state.sk_zm = _zm
    state.sk_bd = _bd; state.sk_ba = _ba
    state.sk_gl = _gl; state.sk_ga = _ga
    state.sk_br = _br; state.sk_fl = _fl

    -- Save original Blizzard pushed texture before stripping (for restore)
    if not state.origPushedTex then
        local p = button:GetPushedTexture()
        if p then
            state.origPushedTex = p:GetTexture()
            state.origPushedAtlas = p:GetAtlas()
        end
    end

    -- Strip Blizzard artwork first
    StripBlizzardArtwork(button)
    SuppressButtonProcVisuals(button)

    local iconSize = settings.iconSize or 36
    local zoom = settings.iconZoom or 0.07

    -- Apply icon TexCoords (crop transparent edges)
    local icon = GetButtonIconTexture(button)
    if icon then
        icon:SetTexCoord(zoom, 1 - zoom, zoom, 1 - zoom)
        icon:ClearAllPoints()
        icon:SetAllPoints(button)
        local buttonName = button.GetName and button:GetName()
        local isSpellFlyoutButton = buttonName and (
            buttonName:match("^SpellFlyoutPopupButton%d+$")
            or buttonName:match("^SpellFlyoutButton%d+$")
        )
        -- After /reload, empty slots may retain stale icon textures from the
        -- previous session. Clear them so ghost icons don't appear.
        -- Do not apply this to stance/pet buttons: they use non-standard action
        -- slot semantics and can return false from HasAction() while still
        -- having a valid icon.
        -- Also skip spell flyout buttons: Blizzard sets their icon directly.
        local barKey = GetBarKeyFromButton(button)
        local action = GetSafeActionSlot(button)
        if action and barKey ~= "stance" and barKey ~= "pet" and not isSpellFlyoutButton
            and not HasButtonContent(button, action) then
            icon:SetTexture(nil)
        end
        icon:SetAlpha(1)
        if icon.Show then icon:Show() end
    end

    -- Create or update backdrop (behind icon, configurable opacity)
    if settings.showBackdrop then
        if not state.backdrop then
            state.backdrop = button:CreateTexture(nil, "BACKGROUND", nil, -8)
            state.backdrop:SetColorTexture(0, 0, 0, 1)
        end
        state.backdrop:SetAlpha(settings.backdropAlpha or 0.8)
        state.backdrop:ClearAllPoints()
        state.backdrop:SetAllPoints(button)  -- Same size as button, not extending beyond
        state.backdrop:Show()
    elseif state.backdrop then
        state.backdrop:Hide()
    end

    -- Create or update Normal overlay (border frame texture)
    if settings.showBorders ~= false then
        if not state.normal then
            state.normal = button:CreateTexture(nil, "OVERLAY", nil, 1)
            state.normal:SetTexture(TEXTURES.normal)
            state.normal:SetVertexColor(0, 0, 0, 1)
        end
        state.normal:SetSize(iconSize, iconSize)
        state.normal:ClearAllPoints()
        state.normal:SetAllPoints(button)
        state.normal:Show()
    elseif state.normal then
        state.normal:Hide()
    end

    -- Create or update Gloss overlay (ADD blend shine)
    if settings.showGloss then
        if not state.gloss then
            state.gloss = button:CreateTexture(nil, "OVERLAY", nil, 2)
            state.gloss:SetTexture(TEXTURES.gloss)
            state.gloss:SetBlendMode("ADD")
        end
        state.gloss:SetVertexColor(1, 1, 1, settings.glossAlpha or 0.6)
        state.gloss:SetAllPoints(button)
        state.gloss:Show()
    elseif state.gloss then
        state.gloss:Hide()
    end

    -- Button-press pushed texture (the visual on keydown/click).
    -- showFlash: "qui" = QUI texture, "blizzard" = original, "off"/false = hidden
    -- Backwards compat: true → "qui", false → "off"
    local flashMode = settings.showFlash
    if flashMode == true then flashMode = "qui"
    elseif flashMode == false then flashMode = "off"
    end

    local function ApplyPushedMode(tex)
        if not tex then return end
        if flashMode == "off" then
            tex:SetAtlas(nil)
            tex:SetTexture(nil)
        elseif flashMode == "blizzard" then
            if state.origPushedAtlas then
                tex:SetTexture(nil)
                tex:SetAtlas(state.origPushedAtlas)
            elseif state.origPushedTex then
                tex:SetAtlas(nil)
                tex:SetTexture(state.origPushedTex)
                tex:SetTexCoord(0, 1, 0, 1)
            end
            -- Blizzard's pushed atlas has asymmetric padding (more on the
            -- right/bottom). Extend BOTTOMRIGHT to compensate.
            tex:ClearAllPoints()
            tex:SetPoint("TOPLEFT", button, "TOPLEFT")
            tex:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 4, -4)
        else -- "qui" (default)
            tex:SetAtlas(nil)
            tex:SetTexture(TEXTURES.pushed)
            tex:SetTexCoord(0, 1, 0, 1)
        end
    end

    ApplyPushedMode(button:GetPushedTexture())
    if button.PushedTexture and button.PushedTexture ~= button:GetPushedTexture() then
        ApplyPushedMode(button.PushedTexture)
    end

    -- Fix Cooldown frame positioning
    local cooldown = button.cooldown or button.Cooldown
    if cooldown then
        cooldown:ClearAllPoints()
        cooldown:SetAllPoints(button)
    end

    -- If the button is currently hidden (bar faded out or empty slot),
    -- keep newly-created textures hidden to match the fade state.
    -- Record _fh* flags so FadeShowTextures knows to restore them on hover.
    if state.fadeHidden then
        if state.backdrop and state.backdrop:IsShown() then state.backdrop:Hide(); state._fhBg = true end
        if state.normal and state.normal:IsShown() then state.normal:Hide(); state._fhNorm = true end
        if state.gloss and state.gloss:IsShown() then state.gloss:Hide(); state._fhGloss = true end
        FadeHideEffects(button, state)
    end

    ActionBarsOwned.skinnedButtons[button] = true

    -- PERF: Per-button UpdateButtonArt hook.
    -- Fires only when Blizzard resets button artwork (combat transitions,
    -- paging, bonus bar swaps) — much less frequent than ActionButton_Update.
    -- Cached closure avoids allocation per hook fire.
    if button.UpdateButtonArt and not button._quiArtHooked then
        local cachedSkinFn = function()
            if button:IsForbidden() then return end
            local bk = GetBarKeyFromButton(button)
            if bk then
                local s = GetEffectiveSettings(bk)
                if s then
                    -- Clear skin cache to force re-apply after Blizzard reset
                    local st = GetFrameState(button)
                    st.sk_sz = nil
                    SkinButton(button, s)
                end
            end
        end
        hooksecurefunc(button, "UpdateButtonArt", function()
            C_Timer.After(0, cachedSkinFn)
        end)
        button._quiArtHooked = true
    end
end

---------------------------------------------------------------------------
-- TEXT VISIBILITY
---------------------------------------------------------------------------

-- Update keybind/hotkey text visibility and styling
-- Directly modifies Blizzard's HotKey element with abbreviated text
UpdateKeybindText = function(button, settings)
    local hotkey = button.HotKey or button.hotKey
    if not hotkey then return end

    -- Determine if keybinds should be shown
    if not settings.showKeybinds then
        hotkey:SetAlpha(0)
        hotkey:Hide()
        return
    end

    -- Get abbreviated keybind text
    local buttonName = button:GetName()
    local bindingName = nil
    local abbreviated = nil

    if buttonName then
        local num

        -- Map button frame names to WoW binding names
        num = buttonName:match("^ActionButton(%d+)$")
        if num then bindingName = "ACTIONBUTTON" .. num end

        -- QUI fresh buttons (bar1-8)
        if not bindingName then
            num = buttonName:match("^QUI_Bar1Button(%d+)$")
            if num then bindingName = "ACTIONBUTTON" .. num end
        end
        if not bindingName then
            num = buttonName:match("^QUI_Bar2Button(%d+)$")
            if num then bindingName = "MULTIACTIONBAR1BUTTON" .. num end
        end
        if not bindingName then
            num = buttonName:match("^QUI_Bar3Button(%d+)$")
            if num then bindingName = "MULTIACTIONBAR2BUTTON" .. num end
        end
        if not bindingName then
            num = buttonName:match("^QUI_Bar4Button(%d+)$")
            if num then bindingName = "MULTIACTIONBAR3BUTTON" .. num end
        end
        if not bindingName then
            num = buttonName:match("^QUI_Bar5Button(%d+)$")
            if num then bindingName = "MULTIACTIONBAR4BUTTON" .. num end
        end
        if not bindingName then
            num = buttonName:match("^QUI_Bar6Button(%d+)$")
            if num then bindingName = "MULTIACTIONBAR5BUTTON" .. num end
        end
        if not bindingName then
            num = buttonName:match("^QUI_Bar7Button(%d+)$")
            if num then bindingName = "MULTIACTIONBAR6BUTTON" .. num end
        end
        if not bindingName then
            num = buttonName:match("^QUI_Bar8Button(%d+)$")
            if num then bindingName = "MULTIACTIONBAR7BUTTON" .. num end
        end
        if not bindingName then
            num = buttonName:match("^QUI_PetButton(%d+)$")
            if num then bindingName = "BONUSACTIONBUTTON" .. num end
        end
        if not bindingName then
            num = buttonName:match("^QUI_StanceButton(%d+)$")
            if num then bindingName = "SHAPESHIFTBUTTON" .. num end
        end

        -- Blizzard button names (fallback for reparented buttons)
        if not bindingName then
            num = buttonName:match("^MultiBarBottomRightButton(%d+)$")
            if num then bindingName = "MULTIACTIONBAR2BUTTON" .. num end
        end

        if not bindingName then
            num = buttonName:match("^MultiBarBottomLeftButton(%d+)$")
            if num then bindingName = "MULTIACTIONBAR1BUTTON" .. num end
        end

        if not bindingName then
            num = buttonName:match("^MultiBarRightButton(%d+)$")
            if num then bindingName = "MULTIACTIONBAR3BUTTON" .. num end
        end

        if not bindingName then
            num = buttonName:match("^MultiBarLeftButton(%d+)$")
            if num then bindingName = "MULTIACTIONBAR4BUTTON" .. num end
        end

        if not bindingName then
            num = buttonName:match("^MultiBar5Button(%d+)$")
            if num then bindingName = "MULTIACTIONBAR5BUTTON" .. num end
        end

        if not bindingName then
            num = buttonName:match("^MultiBar6Button(%d+)$")
            if num then bindingName = "MULTIACTIONBAR6BUTTON" .. num end
        end

        if not bindingName then
            num = buttonName:match("^MultiBar7Button(%d+)$")
            if num then bindingName = "MULTIACTIONBAR7BUTTON" .. num end
        end

        -- Get keybind and abbreviate
        if bindingName then
            local key = GetBindingKey(bindingName)
            if key and ns and ns.FormatKeybind then
                abbreviated = ns.FormatKeybind(key)
            end
        end
    end

    -- Determine visibility
    local shouldShow = abbreviated and abbreviated ~= ""

    -- Only hide keybinds on empty action slots when hideEmptyKeybinds is enabled
    if shouldShow and settings.hideEmptyKeybinds then
        local action = GetSafeActionSlot(button)
        if action then
            local hasAction = HasButtonContent(button, action)
            if not hasAction then
                shouldShow = false
            end
        end
    end

    if not shouldShow then
        hotkey:SetAlpha(0)
        hotkey:Hide()
        return
    end

    -- Set the abbreviated text and show
    hotkey:SetText(abbreviated)
    hotkey:Show()
    hotkey:SetAlpha(1)

    -- Apply styling
    local fontPath, outline = GetFontSettings()

    hotkey:SetFont(fontPath, settings.keybindFontSize or 11, outline)

    local color = settings.keybindColor
    local r = color and color[1] or 1
    local g = color and color[2] or 1
    local b = color and color[3] or 1
    local a = color and color[4] or 1
    hotkey:SetTextColor(r, g, b, a)

    -- Reposition with configurable anchor and offsets
    hotkey:ClearAllPoints()
    local anchor = settings.keybindAnchor or "TOPRIGHT"

    -- Match text justification to anchor direction (Blizzard defaults to RIGHT justify)
    if anchor:find("LEFT") then
        hotkey:SetJustifyH("LEFT")
    elseif anchor:find("RIGHT") then
        hotkey:SetJustifyH("RIGHT")
    else
        hotkey:SetJustifyH("CENTER")
    end

    hotkey:SetWidth(0)
    hotkey:SetPoint(anchor, button, anchor, (settings.keybindOffsetX or 0), (settings.keybindOffsetY or 0))
end

-- Update macro name text visibility and styling
function UpdateMacroText(button, settings)
    local name = button.Name
    if not name then return end

    if not settings.showMacroNames then
        name:SetAlpha(0)
        return
    end

    name:SetAlpha(1)

    -- Apply styling
    local fontPath, outline = GetFontSettings()

    name:SetFont(fontPath, settings.macroNameFontSize or 10, outline)

    local color = settings.macroNameColor
    local r = color and color[1] or 1
    local g = color and color[2] or 1
    local b = color and color[3] or 1
    local a = color and color[4] or 1
    name:SetTextColor(r, g, b, a)

    -- Reposition with configurable anchor and offsets
    name:ClearAllPoints()
    local anchor = settings.macroNameAnchor or "BOTTOM"
    name:SetPoint(anchor, button, anchor, (settings.macroNameOffsetX or 0), (settings.macroNameOffsetY or 0))
end

-- Update count/charge text visibility and styling
function UpdateCountText(button, settings)
    local count = button.Count
    if not count then return end

    if not settings.showCounts then
        count:SetAlpha(0)
        return
    end

    count:SetAlpha(1)

    -- Apply styling
    local fontPath, outline = GetFontSettings()

    count:SetFont(fontPath, settings.countFontSize or 14, outline)

    local color = settings.countColor
    local r = color and color[1] or 1
    local g = color and color[2] or 1
    local b = color and color[3] or 1
    local a = color and color[4] or 1
    count:SetTextColor(r, g, b, a)

    -- Reposition with configurable anchor and offsets
    count:ClearAllPoints()
    local anchor = settings.countAnchor or "BOTTOMRIGHT"
    count:SetPoint(anchor, button, anchor, (settings.countOffsetX or 0), (settings.countOffsetY or 0))
end

-- Update native cooldown duration text visibility and styling.
function UpdateCooldownText(button, settings)
    local cooldown = button.cooldown or button.Cooldown
    if not cooldown then return end

    local showCooldownText = settings.showCooldownText ~= false
    if cooldown.SetHideCountdownNumbers then
        cooldown:SetHideCountdownNumbers(not showCooldownText)
    end

    if not cooldown.GetCountdownFontString then return end
    local text = cooldown:GetCountdownFontString()
    if not text then return end

    if not showCooldownText then
        text:SetAlpha(0)
        return
    end

    local fontPath, outline = GetFontSettings()
    local fontSize = settings.cooldownTextFontSize or 14
    text:SetFont(fontPath, fontSize, outline)

    local color = settings.cooldownTextColor
    local r = color and color[1] or 1
    local g = color and color[2] or 1
    local b = color and color[3] or 1
    local a = color and color[4] or 1
    text:SetTextColor(r, g, b, a)
    text:SetAlpha(1)

    text:ClearAllPoints()
    local anchor = settings.cooldownTextAnchor or "CENTER"
    text:SetPoint(anchor, cooldown, anchor, (settings.cooldownTextOffsetX or 0), (settings.cooldownTextOffsetY or 0))

    if text.SetJustifyH then
        if anchor:find("LEFT") then
            text:SetJustifyH("LEFT")
        elseif anchor:find("RIGHT") then
            text:SetJustifyH("RIGHT")
        else
            text:SetJustifyH("CENTER")
        end
    end
    if text.SetJustifyV then
        if anchor:find("TOP") then
            text:SetJustifyV("TOP")
        elseif anchor:find("BOTTOM") then
            text:SetJustifyV("BOTTOM")
        else
            text:SetJustifyV("MIDDLE")
        end
    end

    local width = button.GetWidth and button:GetWidth() or cooldown.GetWidth and cooldown:GetWidth() or 36
    if text.SetWidth then text:SetWidth(math.max((width or 36) - 4, 1)) end
    if text.SetHeight then text:SetHeight(math.max(fontSize + 4, 1)) end
end

-- Update all text elements on a button
UpdateButtonText = function(button, settings)
    UpdateKeybindText(button, settings)
    UpdateMacroText(button, settings)
    UpdateCountText(button, settings)
    UpdateCooldownText(button, settings)
end

---------------------------------------------------------------------------
-- FADE-HIDE HELPERS
-- QUI-owned textures (backdrop, border, gloss, tintOverlay) may not
-- respect parent alpha inheritance — especially MOD-blend textures.
-- We must explicitly Hide()/Show() them when the button should be
-- invisible (bar faded to alpha 0, or hidden empty slot).
---------------------------------------------------------------------------

FadeHideEffects = function(button, state)
    if not button then return end

    local cooldown = button.cooldown or button.Cooldown
    if cooldown then
        if not state._fhCooldownShowHooked and cooldown.HookScript then
            state._fhCooldownShowHooked = true
            cooldown:HookScript("OnShow", function(self)
                local st = GetFrameState(button)
                if st and st.fadeHidden then
                    self:Hide()
                end
            end)
        end

        if cooldown:IsShown() then
            state._fhCooldownFrameShown = true
            cooldown:Hide()
        end
        if state._fhCooldownSwipe == nil and cooldown.GetDrawSwipe then
            state._fhCooldownSwipe = cooldown:GetDrawSwipe()
        end
        if state._fhCooldownEdge == nil and cooldown.GetDrawEdge then
            state._fhCooldownEdge = cooldown:GetDrawEdge()
        end
        if cooldown.SetDrawSwipe then cooldown:SetDrawSwipe(false) end
        if cooldown.SetDrawEdge then cooldown:SetDrawEdge(false) end
    end

    SuppressButtonProcVisuals(button)
end

FadeShowEffects = function(button, state)
    if not button then return end

    local cooldown = button.cooldown or button.Cooldown
    if cooldown then
        if state._fhCooldownSwipe ~= nil and cooldown.SetDrawSwipe then
            cooldown:SetDrawSwipe(state._fhCooldownSwipe)
        end
        if state._fhCooldownEdge ~= nil and cooldown.SetDrawEdge then
            cooldown:SetDrawEdge(state._fhCooldownEdge)
        end
        if state._fhCooldownFrameShown and cooldown.Show then
            cooldown:Show()
        end
    end
    state._fhCooldownFrameShown = nil
    state._fhCooldownSwipe = nil
    state._fhCooldownEdge = nil
    SuppressButtonProcVisuals(button)
end

-- Hide QUI textures on a button, saving which were visible for later restore.
FadeHideTextures = function(state, button)
    if state.fadeHidden then return end
    state.fadeHidden = true
    if state.tintOverlay and state.tintOverlay:IsShown() then
        state.tintOverlay:Hide(); state._fhTint = true
    end
    if state.backdrop and state.backdrop:IsShown() then
        state.backdrop:Hide(); state._fhBg = true
    end
    if state.normal and state.normal:IsShown() then
        state.normal:Hide(); state._fhNorm = true
    end
    if state.gloss and state.gloss:IsShown() then
        state.gloss:Hide(); state._fhGloss = true
    end
    FadeHideEffects(button, state)
end

-- Restore QUI textures that were hidden by FadeHideTextures.
FadeShowTextures = function(state, button)
    if not state.fadeHidden then return end
    state.fadeHidden = nil
    if state._fhTint and state.tintOverlay then state.tintOverlay:Show() end
    if state._fhBg and state.backdrop then state.backdrop:Show() end
    if state._fhNorm and state.normal then state.normal:Show() end
    if state._fhGloss and state.gloss then state.gloss:Show() end
    state._fhTint = nil; state._fhBg = nil
    state._fhNorm = nil; state._fhGloss = nil
    FadeShowEffects(button, state)
end

---------------------------------------------------------------------------
-- BAR LAYOUT FEATURES
---------------------------------------------------------------------------


-- Drag preview: show hidden empty slots at low alpha while cursor holds a placeable action
DRAG_PREVIEW_ALPHA = 0.3

-- Update empty slot visibility for a single button
UpdateEmptySlotVisibility = function(button, settings)
    if not settings then return end
    local state = GetFrameState(button)

    local barKey = GetBarKeyFromButton(button)

    -- Stance/pet buttons are not standard action slots and can report action
    -- data that does not map cleanly to HasAction(). Never apply hide-empty
    -- logic to them.
    -- Button-level alpha handles only empty-slot hiding.  The mouseover
    -- fade effect is applied on the *container*, so buttons should be at
    -- alpha 1 when they have content.  Using the container's currentAlpha
    -- here would leave buttons stuck at 0 after a fade-in because
    -- SetOwnedBarAlpha only animates the container, not individual buttons.

    if barKey == "stance" or barKey == "pet" then
        if state.hiddenEmpty then
            state.hiddenEmpty = nil
            FadeShowTextures(state, button)
        end
        button:SetAlpha(1)
        return
    end

    if not settings.hideEmptySlots then
        -- Restore visibility if setting is off
        if state.hiddenEmpty then
            button:SetAlpha(1)
            state.hiddenEmpty = nil
            FadeShowTextures(state, button)
        end
        return
    end

    -- Only applies to action buttons with action property
    local action = GetSafeActionSlot(button)
    if action then
        local hasAction = HasButtonContent(button, action)
        if hasAction then
            button:SetAlpha(1)
            if state.hiddenEmpty then
                state.hiddenEmpty = nil
                FadeShowTextures(state, button)
            end
        else
            -- Show at preview alpha while dragging a placeable action
            if ActionBarsOwned.dragPreviewActive then
                button:SetAlpha(DRAG_PREVIEW_ALPHA)
            else
                button:SetAlpha(0)
            end
            if not state.hiddenEmpty then
                state.hiddenEmpty = true
                FadeHideTextures(state, button)
            end
        end
    else
        button:SetAlpha(1)
        if state.hiddenEmpty then
            state.hiddenEmpty = nil
            FadeShowTextures(state, button)
        end
    end
end


-- Usability indicator state tracking
-- PERF: Relaxed from 250ms/100ms to 500ms.  State-change gating in
-- UpdateButtonUsability means visual updates only happen when the tint
-- actually changes, so polling less often has no visible impact.
usabilityState = {
    checkFrame = nil,
    INTERVAL_COMBAT = 0.5,   -- 500ms in combat
    INTERVAL_IDLE = 2.0,     -- 2s OOC (range matters less)
    EVENT_DEBOUNCE = 0.05,   -- same-frame/event-burst coalescing floor
    inCombat = false,
    rangePollingActive = false,
    updatePending = false,
    lastScanTime = 0,
}

