--- QUI Info Bar — micromenu widget: a compact row of panel-toggle icons.
--- Registered as an ordinary datatext (zone system needs no special cases;
--- also usable on fixed-width hosts). All clicks are insecure Toggle*
--- calls; this never touches the Blizzard micro buttons (the action-bars
--- module owns hiding/moving those).

local _, ns = ...
local QUICore = ns.Addon
local Datatexts = QUICore and QUICore.Datatexts
if not Datatexts then return end

local max = math.max
local ipairs = ipairs

-- WoW globals (upvalued from _G so the file lints identically under the
-- repo-root and worktree luacheck configs, like providers_extra.lua)
local PlayerSpellsUtil = _G.PlayerSpellsUtil
local ToggleStoreUI = _G.ToggleStoreUI
local C_Texture = _G.C_Texture

local ATLAS_PREFIX = "UI-HUD-MicroMenu-"

-- Buttons in display order. `atlas` is the Blizzard micro-button texture-kit
-- name (LoadMicroButtonTextures naming: prefix..name.."-Up"/"-Down"/
-- "-Mouseover"). Two entries have no micro atlas on 12.0 and use special
-- icons instead: character (player portrait, like Blizzard's own button)
-- and spellbook (classic book icon file). The help/support entry reuses the
-- GameMenu kit (no dedicated help micro-button art exists).
local BUTTONS = {
    {
        key = "character", label = "Character", portrait = true,
        onClick = function() ToggleCharacter("PaperDollFrame") end,
    },
    {
        key = "spellbook", label = "Spellbook",
        icon = "Interface\\Spellbook\\Spellbook-Icon",
        onClick = function() PlayerSpellsUtil.ToggleSpellBookFrame() end,
    },
    {
        key = "talents", label = "Talents", atlas = "SpecTalents",
        onClick = function() PlayerSpellsUtil.ToggleClassTalentOrSpecFrame() end,
    },
    {
        key = "achievements", label = "Achievements", atlas = "Achievements",
        onClick = function() ToggleAchievementFrame() end,
    },
    {
        key = "collections", label = "Collections", atlas = "Collections",
        onClick = function() ToggleCollectionsJournal() end,
    },
    {
        key = "lfg", label = "Group Finder", atlas = "Groupfinder",
        onClick = function() PVEFrame_ToggleFrame() end,
    },
    {
        key = "shop", label = "Shop", atlas = "Shop",
        onClick = function() ToggleStoreUI() end,
    },
    {
        key = "help", label = "Support", atlas = "GameMenu",
        onClick = function() ToggleHelpFrame() end,
    },
}

local function IsButtonEnabled(key)
    local db = QUICore.db and QUICore.db.profile
    local mm = db and db.infobar and db.infobar.micromenu
    local buttons = mm and mm.buttons
    -- default true unless explicitly false
    return not (buttons and buttons[key] == false)
end

-- Width that preserves the atlas aspect ratio at the given height
-- (micro-button art is taller than wide); square fallback.
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
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(IconWidthFor(def, size), size)

    if def.portrait then
        local tex = btn:CreateTexture(nil, "ARTWORK")
        tex:SetAllPoints()
        SetPortraitTexture(tex, "player")
        btn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    elseif def.icon then
        btn:SetNormalTexture(def.icon)
        btn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    else
        -- Blizzard micro-button parity (LoadMicroButtonTextures)
        btn:SetNormalAtlas(ATLAS_PREFIX .. def.atlas .. "-Up")
        btn:SetPushedAtlas(ATLAS_PREFIX .. def.atlas .. "-Down")
        btn:SetHighlightAtlas(ATLAS_PREFIX .. def.atlas .. "-Mouseover")
    end

    btn:RegisterForClicks("AnyUp")
    btn:SetScript("OnClick", function()
        if InCombatLockdown() then return end
        def.onClick()
    end)
    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:ClearLines()
        GameTooltip:AddLine(def.label, 1, 1, 1)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    return btn
end

Datatexts:Register("micromenu", {
    displayName = "Micro Menu",
    category = "Interface",
    description = "Compact row of interface panel buttons",

    OnEnable = function(slotFrame, settings)
        local frame = CreateFrame("Frame", nil, slotFrame)
        frame:SetAllPoints()
        frame._slot = slotFrame

        -- Compound widget: no text payload (clear any placeholder text)
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

        -- Total content width (drop the trailing gap, add right inset).
        -- Auto-width hosts honor this; fixed-width hosts crop, which is fine.
        local total = (count > 0) and (x - gap + inset) or 1
        slotFrame._quiFixedWidth = total
        if slotFrame._quiOnWidthDirty then slotFrame._quiOnWidthDirty() end

        return frame
    end,

    OnDisable = function(frame)
        if frame and frame._slot then
            frame._slot._quiFixedWidth = nil
            -- Tell the host the width changed now (combat-safe: the host's
            -- reflow defers itself in combat) instead of waiting a ticker.
            if frame._slot._quiOnWidthDirty then frame._slot._quiOnWidthDirty() end
        end
    end,
})
