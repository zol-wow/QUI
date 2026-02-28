-- Keybinding display name (must be global before Bindings.xml loads)
BINDING_NAME_QUI_TOGGLE_OPTIONS = "Open QUI Options"

---@type table|AceAddon
QUI = LibStub("AceAddon-3.0"):NewAddon("QUI", "AceConsole-3.0", "AceEvent-3.0")

---@type table
QUI.DF = _G["DetailsFramework"]
QUI.DEBUG_MODE = false
QUI.pullAliasOwned = false

local QUI_PULL_SLASH_KEY = "QUIPULL_ALIAS"
local PULL_COMMAND_OWNERS = {
    ["BigWigs"] = true,
    ["BigWigs_Core"] = true,
    ["DBM-Core"] = true,
}

-- Version info
QUI.versionString = C_AddOns.GetAddOnMetadata("QUI", "Version") or "2.00"

---@type table
QUI.defaults = {
    global = {},
    char = {
        ---@type table
        debug = {
            ---@type boolean
            reload = false
        },
        ---@type table
        ncdm = {
            essential = {
                customEntries = { enabled = true, placement = "after", entries = {} },
            },
            utility = {
                customEntries = { enabled = true, placement = "after", entries = {} },
            },
        },
    }
}

function QUI:OnInitialize()
    -- Migrate old QuaziiUI_DB to QUI_DB if needed
    if QuaziiUI_DB and not QUI_DB then
        QUI_DB = QuaziiUI_DB
    end

    ---@type AceDBObject-3.0
    self.db = LibStub("AceDB-3.0"):New("QUI_DB", self.defaults, "Default")

    self:RegisterChatCommand("qui", "SlashCommandOpen")
    self:RegisterChatCommand("quaziiui", "SlashCommandOpen")
    self:RegisterChatCommand("rl", "SlashCommandReload")
    self:RegisterChatCommand("qpull", "SlashCommandPull")
    self:RegisterChatCommand("quipull", "SlashCommandPull")
    
    -- Register our media files with LibSharedMedia
    self:CheckMediaRegistration()
end

-- Quick Keybind Mode shortcut (/kb)
SLASH_QUIKB1 = "/kb"
SlashCmdList["QUIKB"] = function()
    local LibKeyBound = LibStub("LibKeyBound-1.0", true)
    if LibKeyBound then
        LibKeyBound:Toggle()
    elseif QuickKeybindFrame then
        -- Fallback to Blizzard's Quick Keybind Mode (no mousewheel support)
        ShowUIPanel(QuickKeybindFrame)
    else
        print("|cff34D399QUI:|r Quick Keybind Mode not available.")
    end
end

-- Cooldown Settings shortcut (/cdm)
SLASH_QUI_CDM1 = "/cdm"
SlashCmdList["QUI_CDM"] = function()
    if CooldownViewerSettings then
        CooldownViewerSettings:SetShown(not CooldownViewerSettings:IsShown())
    else
        print("|cff34D399QUI:|r Cooldown Settings not available. Enable CDM first.")
    end
end

function QUI:SlashCommandOpen(input)
    if input and input == "debug" then
        self.db.char.debug.reload = true
        QUI:SafeReload()
    elseif input and input == "editmode" then
        -- Toggle Unit Frames Edit Mode
        if _G.QUI_ToggleUnitFrameEditMode then
            _G.QUI_ToggleUnitFrameEditMode()
        else
            print("|cFF56D1FFQUI:|r Unit Frames module not loaded.")
        end
        return
    end
    
    -- Default: Open custom GUI
    if self.GUI then
        self.GUI:Toggle()
    else
        print("|cFF56D1FFQUI:|r GUI not loaded yet. Try again in a moment.")
    end
end

function QUI:SlashCommandReload()
    QUI:SafeReload()
end

function QUI:SlashCommandPull(input)
    if not (C_PartyInfo and C_PartyInfo.DoCountdown) then
        self:Print("Pull countdown is not available on this client.")
        return
    end

    local secs = tonumber(input)
    if not secs then
        secs = 10
    end
    secs = math.floor(secs + 0.5)
    if secs < 1 then
        secs = 1
    elseif secs > 60 then
        secs = 60
    end

    local ok = C_PartyInfo.DoCountdown(secs)
    if not ok then
        self:Print("Could not start pull countdown (need to be in a group and have permission).")
    end
end

function QUI:OnEnable()
    self:RegisterEvent("PLAYER_ENTERING_WORLD")
    self:RegisterEvent("ADDON_LOADED")
    self:RegisterOptionalPullAlias()
    
    -- Initialize QUICore (AceDB-based integration)
    if self.QUICore then
        -- Show intro message if enabled (defaults to true)
        if self.db.profile.chat.showIntroMessage ~= false then
            print("|cFF30D1FFQUI|r loaded. |cFFFFFF00/qui|r to setup.")
            print("|cFF30D1FFQUI REMINDER:|r")
            print("|cFF34D3991.|r ENABLE |cFFFFFF00Cooldown Manager|r in Options > Gameplay Enhancement")
            print("|cFF34D3992.|r Action Bars & Menu Bar |cFFFFFF00HIDDEN|r on mouseover |cFFFFFF00by default|r. Go to |cFFFFFF00'Actionbars'|r tab in |cFFFFFF00/qui|r to unhide.")
            print("|cFF34D3993.|r Use |cFFFFFF00100% Icon Size|r on CDM Essential & Utility bars via |cFFFFFF00Edit Mode|r for best results.")
            print("|cFF34D3994.|r Position your |cFFFFFF00CDM bars|r in |cFFFFFF00Edit Mode|r and click |cFFFFFF00Save|r before exiting.")
        end
    end
end

function QUI:RegisterOptionalPullAlias()
    local existingOwner = hash_SlashCmdList and hash_SlashCmdList["/PULL"]
    if existingOwner then
        self.pullAliasOwned = false
        return false
    end

    SlashCmdList[QUI_PULL_SLASH_KEY] = function(msg)
        QUI:SlashCommandPull(msg)
    end
    _G["SLASH_" .. QUI_PULL_SLASH_KEY .. "1"] = "/pull"
    self.pullAliasOwned = true
    return true
end

function QUI:UnregisterOptionalPullAlias()
    if not self.pullAliasOwned then
        return
    end

    SlashCmdList[QUI_PULL_SLASH_KEY] = nil
    _G["SLASH_" .. QUI_PULL_SLASH_KEY .. "1"] = nil
    if hash_SlashCmdList and hash_SlashCmdList["/PULL"] == QUI_PULL_SLASH_KEY then
        hash_SlashCmdList["/PULL"] = nil
    end
    self.pullAliasOwned = false
end

function QUI:ADDON_LOADED(_, addonName)
    if not addonName or not PULL_COMMAND_OWNERS[addonName] then
        return
    end

    self:UnregisterOptionalPullAlias()
end

function QUI:PLAYER_ENTERING_WORLD(_, isInitialLogin, isReloadingUi)
    QUI:BackwardsCompat()

    -- Ensure debug table exists
    if not self.db.char.debug then
        self.db.char.debug = { reload = false }
    end

    if not self.DEBUG_MODE then
        if self.db.char.debug.reload then
            self.DEBUG_MODE = true
            self.db.char.debug.reload = false
            self:DebugPrint("Debug Mode Enabled")
        end
    else
        self:DebugPrint("Debug Mode Enabled")
    end
end

function QUI:DebugPrint(...)
    if self.DEBUG_MODE then
        self:Print(...)
    end
end

-- ADDON COMPARTMENT FUNCTIONS --
function QUI_CompartmentClick()
    -- Open the new GUI
    if QUI.GUI then
        QUI.GUI:Toggle()
    end
end

local GameTooltip = GameTooltip
function QUI_CompartmentOnEnter(self, button)
    GameTooltip:ClearLines()
    GameTooltip:SetOwner(type(self) ~= "string" and self or button, "ANCHOR_LEFT")
    GameTooltip:AddLine("QUI v" .. QUI.versionString)
    GameTooltip:AddLine("Left Click: Open Options")
    GameTooltip:Show()
end

function QUI_CompartmentOnLeave()
    GameTooltip:Hide()
end
