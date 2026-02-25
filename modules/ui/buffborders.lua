-- buffborders.lua
-- Adds configurable black borders around buff/debuff icons in the top right

local _, ns = ...
local Helpers = ns.Helpers

local GetCore = ns.Helpers.GetCore

-- Default settings
local DEFAULTS = {
    enableBuffs = true,
    enableDebuffs = true,
    hideBuffFrame = false,
    hideDebuffFrame = false,
    borderSize = 2,
    fontSize = 12,
    fontOutline = true,
}

-- Get settings from AceDB via shared helper
local function GetSettings()
    return Helpers.GetModuleSettings("buffBorders", DEFAULTS)
end

-- Border colors
local BORDER_COLOR_BUFF = {0, 0, 0, 1}        -- Black for buffs
local BORDER_COLOR_DEBUFF = {0.5, 0, 0, 1}    -- Dark red for debuffs

-- Track which buttons we've already bordered
local borderedButtons = {}

-- Store border textures in a weak-keyed table to avoid writing properties to Blizzard aura frames
local _buttonBorders = Helpers.CreateStateTable()

-- Hook guards stored locally (NOT on Blizzard frames) to avoid taint
local buffFrameShowHooked = false
local debuffFrameShowHooked = false

-- Add border to a single buff/debuff button
local function AddBorderToButton(button, isBuff)
    if not button or borderedButtons[button] then
        return
    end
    
    -- Check if borders are enabled for this type
    local settings = GetSettings()
    if not settings then return end
    if isBuff and not settings.enableBuffs then
        return
    end
    if not isBuff and not settings.enableDebuffs then
        return
    end
    
    -- Find the icon texture (the actual square icon, not the full button frame)
    local icon = button.Icon or button.icon
    if not icon then
        return
    end

    -- Validate button is a proper frame that supports CreateTexture
    -- (Boss fight frames may have Icon but not be valid Frame objects)
    if not button.CreateTexture or type(button.CreateTexture) ~= "function" then
        return
    end
    
    local borderSize = settings.borderSize or 2
    
    -- Choose border color based on buff/debuff
    local borderColor = isBuff and BORDER_COLOR_BUFF or BORDER_COLOR_DEBUFF
    
    -- Create 4 separate edge textures for clean borders around the ICON only
    -- Store in weak-keyed table to avoid writing properties directly to Blizzard frames
    _buttonBorders[button] = _buttonBorders[button] or {}
    local borders = _buttonBorders[button]
    if not borders.top then
        -- Top border
        borders.top = button:CreateTexture(nil, "OVERLAY", nil, 7)
        borders.top:SetPoint("TOPLEFT", icon, "TOPLEFT", 0, 0)
        borders.top:SetPoint("TOPRIGHT", icon, "TOPRIGHT", 0, 0)

        -- Bottom border
        borders.bottom = button:CreateTexture(nil, "OVERLAY", nil, 7)
        borders.bottom:SetPoint("BOTTOMLEFT", icon, "BOTTOMLEFT", 0, 0)
        borders.bottom:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 0, 0)

        -- Left border
        borders.left = button:CreateTexture(nil, "OVERLAY", nil, 7)
        borders.left:SetPoint("TOPLEFT", icon, "TOPLEFT", 0, 0)
        borders.left:SetPoint("BOTTOMLEFT", icon, "BOTTOMLEFT", 0, 0)

        -- Right border
        borders.right = button:CreateTexture(nil, "OVERLAY", nil, 7)
        borders.right:SetPoint("TOPRIGHT", icon, "TOPRIGHT", 0, 0)
        borders.right:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 0, 0)
    end

    -- Update border color based on type
    borders.top:SetColorTexture(borderColor[1], borderColor[2], borderColor[3], borderColor[4])
    borders.bottom:SetColorTexture(borderColor[1], borderColor[2], borderColor[3], borderColor[4])
    borders.left:SetColorTexture(borderColor[1], borderColor[2], borderColor[3], borderColor[4])
    borders.right:SetColorTexture(borderColor[1], borderColor[2], borderColor[3], borderColor[4])

    -- Update border size
    borders.top:SetHeight(borderSize)
    borders.bottom:SetHeight(borderSize)
    borders.left:SetWidth(borderSize)
    borders.right:SetWidth(borderSize)

    borders.top:Show()
    borders.bottom:Show()
    borders.left:Show()
    borders.right:Show()
    
    borderedButtons[button] = true
end

-- Hide borders on a button
local function HideBorderOnButton(button)
    local borders = _buttonBorders[button]
    if not borders then return end
    if borders.top then borders.top:Hide() end
    if borders.bottom then borders.bottom:Hide() end
    if borders.left then borders.left:Hide() end
    if borders.right then borders.right:Hide() end
end

-- Apply font settings to duration text
local function ApplyFontSettings(button)
    if not button then return end

    local settings = GetSettings()
    if not settings then return end

    -- Get font and outline from general settings
    local LSM = LibStub("LibSharedMedia-3.0", true)
    local generalFont = "Fonts\\FRIZQT__.TTF"
    local generalOutline = "OUTLINE"

    local core = GetCore()
    if core and core.db and core.db.profile and core.db.profile.general then
        local general = core.db.profile.general
        if general.font and LSM then
            generalFont = LSM:Fetch("font", general.font) or generalFont
        end
        generalOutline = general.fontOutline or "OUTLINE"
    end

    -- Duration text (timer showing remaining time)
    local duration = button.Duration or button.duration
    if duration and duration.SetFont then
        local fontSize = settings.fontSize or 12
        duration:SetFont(generalFont, fontSize, generalOutline)
    end
end

-- Process all aura buttons in a container
local function ProcessAuraContainer(container, isBuff)
    if not container then return end
    
    -- Get all child frames
    local frames = {container:GetChildren()}
    for _, frame in ipairs(frames) do
        -- Check if this looks like an aura button
        if frame.Icon or frame.icon then
            AddBorderToButton(frame, isBuff)
            ApplyFontSettings(frame)
        end
    end
end

-- Hide/show entire BuffFrame or DebuffFrame based on settings
local _frameHidingPendingRegen = false
local function ApplyFrameHiding()
    if InCombatLockdown() then
        if not _frameHidingPendingRegen then
            _frameHidingPendingRegen = true
            local f = CreateFrame("Frame")
            f:RegisterEvent("PLAYER_REGEN_ENABLED")
            f:SetScript("OnEvent", function(self)
                self:UnregisterEvent("PLAYER_REGEN_ENABLED")
                _frameHidingPendingRegen = false
                ApplyFrameHiding()
            end)
        end
        return
    end
    local settings = GetSettings()
    if not settings then return end

    -- BuffFrame hiding (simple Hide + Show hook, no EnableMouse)
    if BuffFrame then
        if settings.hideBuffFrame then
            BuffFrame:Hide()
        else
            BuffFrame:Show()
        end
        -- Hook Show() once to prevent Blizzard from re-showing
        if not buffFrameShowHooked then
            buffFrameShowHooked = true
            -- TAINT SAFETY: Defer to break taint chain — BuffFrame.Show() can fire
            -- inside secure execution contexts (compact unit frame updates).
            hooksecurefunc(BuffFrame, "Show", function(self)
                C_Timer.After(0, function()
                    local s = GetSettings()
                    if s and s.hideBuffFrame then
                        self:Hide()
                    end
                end)
            end)
        end
    end

    -- DebuffFrame hiding (simple Hide + Show hook, no EnableMouse)
    if DebuffFrame then
        if settings.hideDebuffFrame then
            DebuffFrame:Hide()
        else
            DebuffFrame:Show()
        end
        -- Hook Show() once to prevent Blizzard from re-showing
        if not debuffFrameShowHooked then
            debuffFrameShowHooked = true
            -- TAINT SAFETY: Defer to break taint chain — DebuffFrame.Show() can fire
            -- inside secure execution contexts (compact unit frame updates).
            hooksecurefunc(DebuffFrame, "Show", function(self)
                C_Timer.After(0, function()
                    local s = GetSettings()
                    if s and s.hideDebuffFrame then
                        self:Hide()
                    end
                end)
            end)
        end
    end
end

-- Main function to process all buff/debuff frames
local function ApplyBuffBorders()
    -- Apply frame hiding first
    ApplyFrameHiding()
    -- Process BuffFrame containers (top right buffs)
    if BuffFrame and BuffFrame.AuraContainer then
        ProcessAuraContainer(BuffFrame.AuraContainer, true) -- true = buff
    end
    
    -- Process DebuffFrame if it exists separately
    if DebuffFrame and DebuffFrame.AuraContainer then
        ProcessAuraContainer(DebuffFrame.AuraContainer, false) -- false = debuff
    end
    
    -- Process temporary enchant frames (treat as buffs)
    if TemporaryEnchantFrame then
        local frames = {TemporaryEnchantFrame:GetChildren()}
        for _, frame in ipairs(frames) do
            AddBorderToButton(frame, true) -- true = buff
            ApplyFontSettings(frame)
        end
    end
end

-- Debounce state for buff border updates (shared across all hooks)
local buffBorderPending = false

-- Schedule a debounced buff border update
-- Only one timer runs at a time, no matter how many hooks fire
local function ScheduleBuffBorders()
    if buffBorderPending then return end
    buffBorderPending = true
    C_Timer.After(0.15, function()  -- 150ms debounce for CPU efficiency
        buffBorderPending = false
        ApplyBuffBorders()
    end)
end

-- Hook into aura update functions
-- TAINT SAFETY: All hooks defer via C_Timer.After(0) to break taint chain from secure context.
-- Even a simple boolean check + C_Timer.After call inside a synchronous hooksecurefunc callback
-- contaminates the secure execution context in the Midnight (12.0+) taint model.
local function HookAuraUpdates()
    -- Hook BuffFrame updates
    if BuffFrame and BuffFrame.Update then
        hooksecurefunc(BuffFrame, "Update", function()
            C_Timer.After(0, ScheduleBuffBorders)
        end)
    end

    -- Hook AuraContainer updates if it exists (buffs)
    if BuffFrame and BuffFrame.AuraContainer and BuffFrame.AuraContainer.Update then
        hooksecurefunc(BuffFrame.AuraContainer, "Update", function()
            C_Timer.After(0, ScheduleBuffBorders)
        end)
    end

    -- Hook DebuffFrame updates
    if DebuffFrame and DebuffFrame.Update then
        hooksecurefunc(DebuffFrame, "Update", function()
            C_Timer.After(0, ScheduleBuffBorders)
        end)
    end

    -- Hook DebuffFrame.AuraContainer updates if it exists
    if DebuffFrame and DebuffFrame.AuraContainer and DebuffFrame.AuraContainer.Update then
        hooksecurefunc(DebuffFrame.AuraContainer, "Update", function()
            C_Timer.After(0, ScheduleBuffBorders)
        end)
    end

    -- Hook the global aura update function if available
    if type(AuraButton_Update) == "function" then
        hooksecurefunc("AuraButton_Update", function()
            C_Timer.After(0, ScheduleBuffBorders)
        end)
    end
end

-- Performance: Removed redundant 1-second polling loop
-- UNIT_AURA event and AuraButton_Update hook already handle all buff border updates

-- Initialize (UNIT_AURA handles dynamic updates)
-- Note: Initial application is called from core/main.lua OnEnable() to ensure AceDB is ready
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("UNIT_AURA")

eventFrame:SetScript("OnEvent", function(self, event, arg)
    if event == "UNIT_AURA" and arg == "player" then
        ScheduleBuffBorders()  -- Use shared debounce
    end
end)

-- Hook aura updates on first load
C_Timer.After(2, HookAuraUpdates)

-- Export to QUI namespace
QUI.BuffBorders = {
    Apply = ApplyBuffBorders,
    AddBorder = AddBorderToButton,
}

-- Global function for config panel to call
_G.QUI_RefreshBuffBorders = function()
    borderedButtons = borderedButtons or {}
    wipe(borderedButtons) -- Clear cache to force re-border
    ApplyBuffBorders()
end

