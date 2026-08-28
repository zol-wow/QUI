local _, ns = ...
local QUICore = ns.Addon
local Datatexts = QUICore and QUICore.Datatexts
if not Datatexts then return end

local max = math.max
local ipairs = ipairs

local PlayerSpellsUtil = _G.PlayerSpellsUtil
local ToggleProfessionsBook = _G.ToggleProfessionsBook
local ToggleQuestLog = _G.ToggleQuestLog
local ToggleEncounterJournal = _G.ToggleEncounterJournal
local C_Texture = _G.C_Texture

local ATLAS_PREFIX = "UI-HUD-MicroMenu-"

local BUTTONS = {
    {
        key = "character", label = ns.L["Character"], portrait = true,
        onClick = function() ToggleCharacter("PaperDollFrame") end,
    },
    {
        key = "spellbook", label = ns.L["Spellbook"],
        icon = "Interface\\Spellbook\\Spellbook-Icon",
        onClick = function() PlayerSpellsUtil.ToggleSpellBookFrame() end,
    },
    {
        key = "talents", label = ns.L["Talents"], atlas = "SpecTalents",
        onClick = function() PlayerSpellsUtil.ToggleClassTalentOrSpecFrame() end,
    },
    {
        key = "professions", label = ns.L["Professions"], atlas = "Professions",
        onClick = function() ToggleProfessionsBook() end,
    },
    {
        key = "achievements", label = ns.L["Achievements"], atlas = "Achievements",
        onClick = function() ToggleAchievementFrame() end,
    },
    {
        key = "questlog", label = ns.L["Quest Log"], atlas = "Questlog",
        onClick = function() ToggleQuestLog() end,
    },
    {
        key = "collections", label = ns.L["Collections"], atlas = "Collections",
        onClick = function() ToggleCollectionsJournal() end,
    },
    {
        key = "lfg", label = ns.L["Group Finder"], atlas = "Groupfinder",
        onClick = function() PVEFrame_ToggleFrame() end,
    },
    {
        key = "adventureguide", label = ns.L["Adventure Guide"], atlas = "AdventureGuide",
        onClick = function() ToggleEncounterJournal() end,
    },
    {
        key = "housing", label = ns.L["Housing"], atlas = "Housing",
        onClick = function()
            local u = _G.HousingFramesUtil
            if u and u.ToggleHousingDashboard then u.ToggleHousingDashboard() end
        end,
    },
    {
        key = "help", label = ns.L["Support"], atlas = "GameMenu",
        onClick = function() ToggleHelpFrame() end,
    },
}

local function IsButtonEnabled(key)
    local db = QUICore.db and QUICore.db.profile
    local mm = db and db.infobar and db.infobar.micromenu
    local buttons = mm and mm.buttons
    return not (buttons and buttons[key] == false)
end

local function IconWidthFor(def, size)
    if def.atlas and C_Texture and C_Texture.GetAtlasInfo then
        local info = C_Texture.GetAtlasInfo(ATLAS_PREFIX .. def.atlas .. "-Up")
        if info and info.width and info.height and info.height > 0 then
            return size * (info.width / info.height)
        end
    end
    return size
end

local function CreateIconButton(parent, def, size)
    local opts = {
        size = size,
        tooltip = def.label,
        tooltipAnchor = "ANCHOR_BOTTOM",
        onClick = def.onClick,
        combatGuard = true,
        registerClicks = "AnyUp",
    }
    if def.portrait then
        opts.portrait = true
        opts.squareHighlight = true
    elseif def.icon then
        opts.icon = def.icon
        opts.squareHighlight = true
    else
        opts.atlasTriplet = ATLAS_PREFIX .. def.atlas
    end

    local btn = ns.UIKit.CreateIconButton(parent, opts)
    btn:SetSize(IconWidthFor(def, size), size)
    return btn
end

Datatexts:Register("micromenu", {
    displayName = ns.L["Micro Menu"],
    category = ns.L["Interface"],
    description = "Compact row of interface panel buttons",

    OnEnable = function(slotFrame, settings)
        local frame = CreateFrame("Frame", nil, slotFrame)
        frame:SetAllPoints()
        frame._slot = slotFrame

        if slotFrame.text then slotFrame.text:SetText("") end

        local size = max((slotFrame:GetHeight() or 0) - 6, 12)
        local gap = 4
        local inset = 4

        local x = inset
        local count = 0
        for _, def in ipairs(BUTTONS) do
            if IsButtonEnabled(def.key) then
                local btn = CreateIconButton(frame, def, size)
                btn:SetPoint("LEFT", frame, "LEFT", x, 0)
                x = x + btn:GetWidth() + gap
                count = count + 1
            end
        end

        local total = (count > 0) and (x - gap + inset) or 1
        slotFrame._quiFixedWidth = total
        if slotFrame._quiOnWidthDirty then slotFrame._quiOnWidthDirty() end

        return frame
    end,

    OnDisable = function(frame)
        if frame and frame._slot then
            frame._slot._quiFixedWidth = nil
            if frame._slot._quiOnWidthDirty then frame._slot._quiOnWidthDirty() end
        end
    end,
})
