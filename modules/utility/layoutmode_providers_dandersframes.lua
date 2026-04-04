--[[
    QUI Layout Mode Settings Providers — DandersFrames
    Anchor configuration for party, raid, and pinned containers.
]]

local ADDON_NAME, ns = ...

---------------------------------------------------------------------------
-- REGISTER ALL PROVIDERS
---------------------------------------------------------------------------
local function RegisterAllProviders()
    local settingsPanel = ns.QUI_LayoutMode_Settings
    if not settingsPanel then return end

    local GUI = QUI and QUI.GUI
    if not GUI then return end

    local U = ns.QUI_LayoutMode_Utils
    if not U then return end

    local DF = ns.QUI_DandersFrames
    if not DF or not DF.IsAvailable or not DF:IsAvailable() then return end

    local P = U.PlaceRow
    local FORM_ROW = U.FORM_ROW

    local pointOptions = {
        {value = "TOPLEFT", text = "Top Left"},
        {value = "TOP", text = "Top"},
        {value = "TOPRIGHT", text = "Top Right"},
        {value = "LEFT", text = "Left"},
        {value = "CENTER", text = "Center"},
        {value = "RIGHT", text = "Right"},
        {value = "BOTTOMLEFT", text = "Bottom Left"},
        {value = "BOTTOM", text = "Bottom"},
        {value = "BOTTOMRIGHT", text = "Bottom Right"},
    }

    ---------------------------------------------------------------------------
    -- SHARED BUILDER
    ---------------------------------------------------------------------------
    local function BuildDandersProvider(containerKey, elementKey)
        return { build = function(content, key, width)
            local db = U.GetProfileDB()
            if not db or not db.dandersFrames or not db.dandersFrames[containerKey] then return 80 end
            local cfg = db.dandersFrames[containerKey]
            local sections = {}
            local function relayout() U.StandardRelayout(content, sections) end
            local function Refresh()
                DF:ApplyPosition(containerKey)
                if _G.QUI_LayoutModeSyncHandle then
                    _G.QUI_LayoutModeSyncHandle(elementKey)
                end
            end

            U.CreateCollapsible(content, "Anchoring", 6 * FORM_ROW + 8, function(body)
                local sy = -4
                sy = P(GUI:CreateFormCheckbox(body, "Enable", "enabled", cfg, Refresh), body, sy)
                sy = P(GUI:CreateFormDropdown(body, "Anchor To", DF:BuildAnchorOptions(), "anchorTo", cfg, Refresh), body, sy)
                sy = P(GUI:CreateFormDropdown(body, "Container Point", pointOptions, "sourcePoint", cfg, Refresh), body, sy)
                sy = P(GUI:CreateFormDropdown(body, "Target Point", pointOptions, "targetPoint", cfg, Refresh), body, sy)
                sy = P(GUI:CreateFormSlider(body, "X Offset", -400, 400, 1, "offsetX", cfg, Refresh), body, sy)
                P(GUI:CreateFormSlider(body, "Y Offset", -400, 400, 1, "offsetY", cfg, Refresh), body, sy)
            end, sections, relayout)

            relayout()
            return content:GetHeight()
        end }
    end

    ---------------------------------------------------------------------------
    -- REGISTER PROVIDERS
    ---------------------------------------------------------------------------
    settingsPanel:RegisterProvider("dandersParty",   BuildDandersProvider("party",   "dandersParty"))
    settingsPanel:RegisterProvider("dandersRaid",    BuildDandersProvider("raid",    "dandersRaid"))
    settingsPanel:RegisterProvider("dandersPinned1", BuildDandersProvider("pinned1", "dandersPinned1"))
    settingsPanel:RegisterProvider("dandersPinned2", BuildDandersProvider("pinned2", "dandersPinned2"))
end

C_Timer.After(2, RegisterAllProviders)
