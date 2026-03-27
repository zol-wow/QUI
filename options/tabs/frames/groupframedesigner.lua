local ADDON_NAME, ns = ...
local QUI = QUI
local GUI = QUI.GUI
local Shared = ns.QUI_Options

local CreateScrollableContent = Shared.CreateScrollableContent

local function BuildSharedProviderTab(tabContent, searchContext, mode)
    local PAD = Shared.PADDING

    GUI:SetSearchContext(searchContext)

    local host = CreateFrame("Frame", nil, tabContent)
    host:SetPoint("TOPLEFT", PAD, -10)
    host:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
    host:SetHeight(1)

    local width = math.max(300, (tabContent:GetWidth() or 760) - (PAD * 2))
    local height = ns.SettingsBuilders.BuildGroupFrameSettings(mode, host, width, { includePosition = false })
    tabContent:SetHeight((height or 80) + 20)
end

local function BuildGeneralTab(tabContent)
    local PAD = Shared.PADDING
    local y = -15
    local C = GUI.Colors

    GUI:SetSearchContext({tabIndex = 6, tabName = "Group Frames", subTabIndex = 1, subTabName = "General"})

    local title = GUI:CreateSectionHeader(tabContent, "Group Frames Overview")
    title:SetPoint("TOPLEFT", PAD, y)
    y = y - title.gap

    local info = GUI:CreateLabel(
        tabContent,
        "Party and raid settings below reuse the same settings providers as QUI Edit Mode. Use the composer buttons there when you need element-level layout editing.",
        11,
        C.textMuted
    )
    info:SetPoint("TOPLEFT", PAD, y)
    info:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
    info:SetJustifyH("LEFT")
    info:SetWordWrap(true)
    y = y - 44

    local partyBtn = GUI:CreateButton(tabContent, "Open Party Composer", 180, 28, function()
        local composer = ns.QUI_LayoutMode_Composer
        if composer then
            composer:Open("party")
        end
    end)
    partyBtn:SetPoint("TOPLEFT", PAD, y)

    local raidBtn = GUI:CreateButton(tabContent, "Open Raid Composer", 180, 28, function()
        local composer = ns.QUI_LayoutMode_Composer
        if composer then
            composer:Open("raid")
        end
    end)
    raidBtn:SetPoint("TOPLEFT", partyBtn, "BOTTOMLEFT", 0, -10)
    y = y - 70

    local editModeBtn = GUI:CreateButton(tabContent, "Open QUI Edit Mode", 180, 28, function()
        if InCombatLockdown() then return end
        if _G.QUI_ToggleLayoutMode then
            GUI:Hide()
            _G.QUI_ToggleLayoutMode()
        end
    end)
    editModeBtn:SetPoint("TOPLEFT", PAD, y)

    tabContent:SetHeight(180)
end

local function CreateGroupFramesPage(parent)
    local scroll, content = CreateScrollableContent(parent)

    GUI:CreateSubTabs(content, {
        { name = "General", builder = BuildGeneralTab },
        {
            name = "Party",
            builder = function(tabContent)
                BuildSharedProviderTab(tabContent, {
                    tabIndex = 6,
                    tabName = "Group Frames",
                    subTabIndex = 2,
                    subTabName = "Party",
                }, "party")
            end,
        },
        {
            name = "Raid",
            builder = function(tabContent)
                BuildSharedProviderTab(tabContent, {
                    tabIndex = 6,
                    tabName = "Group Frames",
                    subTabIndex = 3,
                    subTabName = "Raid",
                }, "raid")
            end,
        },
    })

    content:SetHeight(650)
end

ns.QUI_GroupFramesDesignerOptions = {
    CreateGroupFramesPage = CreateGroupFramesPage,
}
