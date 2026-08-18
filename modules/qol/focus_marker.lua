local ADDON_NAME, ns = ...
local Helpers = ns.Helpers

local GetSettings = Helpers.CreateDBGetter("general")

local MACRO_NAME = "FocusMarker_QUI"
local MACRO_ICON = 132219

local button
local pendingApply = false

local function Cfg()
    local s = GetSettings()
    return s and s.focusMarker or nil
end

-- <<< QUI_TEST_EXTRACT macro_body
local function BuildMacroBody(marker, useMouseover)
    marker = tonumber(marker) or 8
    if marker < 1 then marker = 1 elseif marker > 8 then marker = 8 end
    if useMouseover then
        return ("/focus [@mouseover,harm,nodead][]\n/tm [@mouseover,harm,nodead][] %d"):format(marker)
    end
    return ("/focus\n/tm %d"):format(marker)
end
-- <<< QUI_TEST_EXTRACT macro_body

local function EnsureButton()
    if button then return button end
    button = CreateFrame("Button", "QUI_FocusMarkerButton", UIParent, "SecureActionButtonTemplate")
    button:RegisterForClicks("AnyUp", "AnyDown")
    button:SetAttribute("type", "macro")
    button:SetAttribute("type1", "macro")
    return button
end

local function FindMacroIndex()
    if not (GetNumMacros and GetMacroInfo) then return nil end
    local numAccount, numCharacter = GetNumMacros()
    for i = 1, numAccount or 0 do
        if GetMacroInfo(i) == MACRO_NAME then return i end
    end
    local consts = Constants and Constants.MacroConsts
    local base = consts and consts.MAX_ACCOUNT_MACROS
    if type(base) ~= "number" then base = 120 end
    for i = base + 1, base + (numCharacter or 0) do
        if GetMacroInfo(i) == MACRO_NAME then return i end
    end
    return nil
end

local function WriteCharacterMacro(body)
    if not (CreateMacro and EditMacro) then return end
    local index = FindMacroIndex()
    if index then
        pcall(EditMacro, index, MACRO_NAME, MACRO_ICON, body)
    else
        pcall(CreateMacro, MACRO_NAME, MACRO_ICON, body, nil)
    end
end

local function Apply()
    local cfg = Cfg()
    if not cfg or not cfg.enabled then
        pendingApply = false
        if button and not InCombatLockdown() then
            button:SetAttribute("macrotext", "")
            button:SetAttribute("macrotext1", "")
        end
        return
    end

    if InCombatLockdown() then
        pendingApply = true
        return
    end
    pendingApply = false

    local body = BuildMacroBody(cfg.marker, cfg.useMouseover ~= false)
    local btn = EnsureButton()
    btn:SetAttribute("macrotext", body)
    btn:SetAttribute("macrotext1", body)

    if cfg.writeMacro ~= false then
        WriteCharacterMacro(body)
    end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
frame:SetScript("OnEvent", function()
    if pendingApply then Apply() end
end)

ns.RefreshFocusMarker = Apply

if ns.WhenLoggedIn then
    ns.WhenLoggedIn(Apply)
end
