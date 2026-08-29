local ADDON_NAME, ns = ...
local Helpers = ns.Helpers

local GetSettings = Helpers.CreateDBGetter("general")

local BTN = 26
local GAP = 4
local PAD = 6

local panel
local buttons = {}
local built = false

local function Enabled()
    local s = GetSettings()
    return s and s.worldMapTeleports == true
end

local function UpdateCooldowns()
    if not panel or not panel:IsShown() then return end
    if not (C_Spell and C_Spell.GetSpellCooldownDuration) then return end
    for _, btn in ipairs(buttons) do
        if btn.spellID and btn.cooldown then
            local dur = C_Spell.GetSpellCooldownDuration(btn.spellID)
            if dur then
                btn.cooldown:SetCooldownFromDurationObject(dur)
            else
                btn.cooldown:Clear()
            end
        end
    end
end

local function UpdateKnownState()
    for _, btn in ipairs(buttons) do
        local known = btn.spellID and IsSpellKnown(btn.spellID)
        btn.icon:SetDesaturated(not known)
        btn.label:SetTextColor(known and 1 or 0.5, known and 0.82 or 0.5, known and 0 or 0.5)
    end
end

local function Build()
    if built or InCombatLockdown() then return end
    if not (C_ChallengeMode and C_ChallengeMode.GetMapTable) then return end
    local DD = ns.DungeonData
    if not DD then return end

    local maps = C_ChallengeMode.GetMapTable()
    if type(maps) ~= "table" or #maps == 0 then return end

    local worldMap = _G.WorldMapFrame
    if not worldMap then return end

    built = true
    panel = CreateFrame("Frame", nil, worldMap)
    panel:SetFrameStrata("HIGH")
    panel:SetPoint("TOPRIGHT", worldMap, "TOPRIGHT", -8, -70)
    local bg = panel:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.05, 0.05, 0.05, 0.85)

    local entries = {}
    for _, mapID in ipairs(maps) do
        local spellID = DD.GetTeleportSpellID(mapID)
        if spellID then
            local name, _, _, icon = C_ChallengeMode.GetMapUIInfo(mapID)
            entries[#entries + 1] = {
                mapID = mapID,
                spellID = spellID,
                short = DD.GetShortName(mapID),
                name = name,
                icon = icon,
            }
        end
    end
    table.sort(entries, function(a, b) return (a.short or "") < (b.short or "") end)

    local y = -PAD
    for _, entry in ipairs(entries) do
        local btn = CreateFrame("Button", nil, panel, "SecureActionButtonTemplate")
        btn:SetSize(BTN + 44, BTN)
        btn:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, y)
        btn:SetAttribute("type", "spell")
        btn:SetAttribute("spell", entry.spellID)
        btn:RegisterForClicks("AnyUp", "AnyDown")
        btn.spellID = entry.spellID

        btn.icon = btn:CreateTexture(nil, "ARTWORK")
        btn.icon:SetSize(BTN, BTN)
        btn.icon:SetPoint("LEFT")
        btn.icon:SetTexture(entry.icon or "Interface\\Icons\\INV_Misc_QuestionMark")

        btn.cooldown = CreateFrame("Cooldown", nil, btn, "CooldownFrameTemplate")
        btn.cooldown:SetAllPoints(btn.icon)

        btn.label = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        btn.label:SetPoint("LEFT", btn.icon, "RIGHT", 4, 0)
        btn.label:SetText(entry.short or "?")

        btn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            GameTooltip:SetText(entry.name or entry.short or "")
            if self.spellID and not IsSpellKnown(self.spellID) then
                GameTooltip:AddLine(ns.L["Teleport not learned yet (time this dungeon at +10)."], 0.8, 0.4, 0.4, true)
            end
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

        buttons[#buttons + 1] = btn
        y = y - BTN - GAP
    end

    panel:SetSize(BTN + 44 + PAD * 2, -y + PAD - GAP)
    UpdateKnownState()
    UpdateCooldowns()
    panel:SetShown(Enabled())
end

local function OnMapShow()
    if not Enabled() then
        if panel then panel:Hide() end
        return
    end
    if not built then Build() end
    if panel then
        panel:Show()
        UpdateKnownState()
        UpdateCooldowns()
    end
end

local hooked = false
local function EnsureHook()
    if hooked then return end
    local worldMap = _G.WorldMapFrame
    if not worldMap then return end
    hooked = true
    worldMap:HookScript("OnShow", OnMapShow)
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
frame:SetScript("OnEvent", function()
    UpdateCooldowns()
end)

if ns.WhenLoggedIn then
    ns.WhenLoggedIn(EnsureHook)
else
    EnsureHook()
end

ns.RefreshWorldMapTeleports = function()
    EnsureHook()
    local worldMap = _G.WorldMapFrame
    if worldMap and worldMap:IsShown() then
        OnMapShow()
    elseif panel and not Enabled() then
        panel:Hide()
    end
end
